/*
 * -------------------------------------------------------
 * Section: Report
 * This migration creates the schema for reports.
 * -------------------------------------------------------
 */
drop function if exists supasheet.get_reports (text);

create or replace function supasheet.get_reports (
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
    and v.comment::jsonb ->> 'type' = 'report'
    and has_table_privilege(
      p_caller,
      v.id::oid,
      'select'
    );
$$;

revoke all on function supasheet.get_reports (text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on function supasheet.get_reports (text, text) to anon,
authenticated;
