/*
 * -------------------------------------------------------
 * Section: Charts
 * This migration creates the schema for charts module.
 * Separate from dashboards to handle chart-specific functionality.
 * -------------------------------------------------------
 */
-- Function to get charts
drop function if exists supasheet.get_charts (text, text);

create or replace function supasheet.get_charts (
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
    and v.comment::jsonb ->> 'type' = 'chart'
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

revoke all on function supasheet.get_charts (text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on function supasheet.get_charts (text, text, text) to anon,
authenticated;
