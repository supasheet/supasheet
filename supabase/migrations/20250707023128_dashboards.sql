/*
 * -------------------------------------------------------
 * Section: Dashboard
 * This migration creates the schema for dashboards.
 * -------------------------------------------------------
 */

create or replace function supasheet.get_widgets (
  p_schema text default null,
  p_resource text default null
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
    and (
      (
        (select auth.uid()) is null
        and has_table_privilege(
          'anon',
          format('%I.%I', v.schema, v.name),
          'select'
        )
      )
      or
      (
        (select auth.uid()) is not null
        and has_table_privilege(
          'authenticated',
          format('%I.%I', v.schema, v.name),
          'select'
        )
        and exists (
          select 1
          from supasheet.role_permissions rp
          inner join supasheet.user_roles ur
              on ur.role = rp.role
          where ur.user_id = (select auth.uid())
              and rp.permission::text = v.schema || '.' || v.name || ':select'
        )
      )
    );
$$;

revoke all on function supasheet.get_widgets (text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on function supasheet.get_widgets (text, text) to anon,
authenticated;
