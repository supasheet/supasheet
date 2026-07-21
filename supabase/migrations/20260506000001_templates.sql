/*
 * -------------------------------------------------------
 * Section: Template
 * This migration creates the schema for templates.
 * -------------------------------------------------------
 */
drop function if exists supasheet.get_templates (text);

create or replace function supasheet.get_templates (
  p_schema text default null,
  p_caller text default current_user
) returns table (
  id bigint,
  schema text,
  name text,
  is_updatable boolean,
  comment text
) language sql security definer
set
  search_path = '' as $$
  select
    v.*
  from supasheet.views v
  where v.schema = p_schema
    and v.comment::jsonb ->> 'type' = 'template'
    and has_table_privilege(p_caller, v.id::oid, 'select');
$$;

revoke all on function supasheet.get_templates (text, text)
from
  authenticated,
  service_role;

grant
execute on function supasheet.get_templates (text, text) to authenticated;

create or replace function supasheet.apply_template (
  p_schema text,
  p_template_name text,
  p_target_table text
) returns integer language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_columns text;
  v_sql     text;
  v_count   integer;
begin
  select string_agg(quote_ident(tc.name), ', ' order by tc.ordinal_position::int)
  into v_columns
  from supasheet.get_columns(p_schema, p_template_name) tc
  where tc.name in (
    select tgt.name
    from supasheet.get_columns(p_schema, p_target_table) tgt
  );

  if v_columns is null then
    raise exception 'No matching columns between template "%" and table "%"',
      p_template_name, p_target_table
      using errcode = 'P0001';
  end if;

  v_sql := format(
    'insert into %I.%I (%s) select %s from %I.%I',
    p_schema, p_target_table,
    v_columns,
    v_columns,
    p_schema, p_template_name
  );

  execute v_sql;
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

revoke all on function supasheet.apply_template (text, text, text)
from
  authenticated,
  service_role;

grant
execute on function supasheet.apply_template (text, text, text) to authenticated;
