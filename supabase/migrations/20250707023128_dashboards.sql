/*
 * -------------------------------------------------------
 * Section: Dashboard
 * This migration creates the schema for dashboards.
 * -------------------------------------------------------
 */
drop function if exists supasheet.get_widgets (text, text);

create or replace function supasheet.get_widgets (
  p_schema text default null,
  p_resource text default null,
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
    and v.comment::jsonb ->> 'type' = 'dashboard_widget'
    and (
      case
        when p_resource is null then v.comment::jsonb ->> 'resource' is null
        else v.comment::jsonb ->> 'resource' = p_resource
      end
    )
    and has_table_privilege(
      p_caller,
      v.id::oid,
      'select'
    );
$$;

revoke all on function supasheet.get_widgets (text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on function supasheet.get_widgets (text, text, text) to anon,
authenticated;
