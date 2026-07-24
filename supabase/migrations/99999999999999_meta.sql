----------------------------------------------------------------
-- Function: supasheet.get_schemas
----------------------------------------------------------------
drop function if exists supasheet.get_schemas ();

create or replace function supasheet.get_schemas (p_caller text default current_user) RETURNS table (schema text) LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        DISTINCT t.schema
    FROM supasheet.tables t
    WHERE has_table_privilege(
        p_caller,
        t.id::oid,
        'select'
    );
$$;

revoke all on FUNCTION supasheet.get_schemas (text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_schemas (text) to authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_tables
----------------------------------------------------------------
drop function if exists supasheet.get_tables (text, text, text);

create or replace function supasheet.get_tables (
  schema_name text default null,
  table_name text default null,
  action text default 'select',
  p_caller text default current_user
) RETURNS SETOF supasheet.tables LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        t.*
    FROM supasheet.tables t
    WHERE (table_name IS NULL OR t.name = table_name)
        AND (schema_name IS NULL OR t.schema = schema_name)
        AND has_table_privilege(
            p_caller,
            t.id::oid,
            action
        );
$$;

revoke all on FUNCTION supasheet.get_tables (text, text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_tables (text, text, text, text) to anon,
authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_views
----------------------------------------------------------------
drop function if exists supasheet.get_views (text, text, text);

create or replace function supasheet.get_views (
  schema_name text default null,
  view_name text default null,
  action text default 'select',
  p_caller text default current_user
) RETURNS SETOF supasheet.views LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        t.*
    FROM supasheet.views t
    WHERE (view_name IS NULL OR t.name = view_name)
        AND (schema_name IS NULL OR t.schema = schema_name)
        AND has_table_privilege(
            p_caller,
            t.id::oid,
            action
        );
$$;

revoke all on FUNCTION supasheet.get_views (text, text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_views (text, text, text, text) to anon,
authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_materialized_views
----------------------------------------------------------------
drop function if exists supasheet.get_materialized_views (text, text, text);

create or replace function supasheet.get_materialized_views (
  schema_name text default null,
  view_name text default null,
  action text default 'select',
  p_caller text default current_user
) RETURNS SETOF supasheet.materialized_views LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        t.*
    FROM supasheet.materialized_views t
    WHERE (view_name IS NULL OR t.name = view_name)
        AND (schema_name IS NULL OR t.schema = schema_name)
        AND has_table_privilege(
            p_caller,
            t.id::oid,
            action
        );
$$;

revoke all on FUNCTION supasheet.get_materialized_views (text, text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_materialized_views (text, text, text, text) to anon,
authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_columns
----------------------------------------------------------------
drop function if exists supasheet.get_columns (text, text, text);

create or replace function supasheet.get_columns (
  schema_name text default null,
  table_name text default null,
  action text default 'select',
  p_caller text default current_user
) RETURNS SETOF supasheet.columns LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        t.*
    FROM supasheet.columns t
    WHERE (table_name IS NULL OR t.table = table_name)
        AND (schema_name IS NULL OR t.schema = schema_name)
        AND CASE
            WHEN lower(action) = 'delete'
                THEN has_table_privilege(p_caller, t.table_id::oid, action)
            ELSE has_column_privilege(p_caller, t.table_id::oid, t.name, action)
        END
    ORDER BY (t.ordinal_position::int);
$$;

revoke all on FUNCTION supasheet.get_columns (text, text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_columns (text, text, text, text) to anon,
authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_privileges
----------------------------------------------------------------
drop function if exists supasheet.get_privileges (text, text);

create or replace function supasheet.get_privileges (
  schema_name text,
  resource_name text,
  p_caller text default current_user
) RETURNS table (privilege text) LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT act.action AS privilege
    FROM (VALUES ('select'), ('insert'), ('update'), ('delete')) AS act(action)
    WHERE has_table_privilege(
        p_caller,
        format('%I.%I', schema_name, resource_name),
        act.action
    );
$$;

revoke all on FUNCTION supasheet.get_privileges (text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_privileges (text, text, text) to anon,
authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_related_tables
----------------------------------------------------------------
drop function if exists supasheet.get_related_tables (text, text);

create or replace function supasheet.get_related_tables (
  schema_name text,
  table_name text,
  p_caller text default current_user
) RETURNS table (
  id bigint,
  schema text,
  name text,
  rls_enabled boolean,
  rls_forced boolean,
  replica_identity text,
  bytes int8,
  size text,
  live_rows_estimate int8,
  dead_rows_estimate int8,
  comment text,
  primary_keys jsonb,
  relationships jsonb
) LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        t.id,
        t.schema,
        t.name,
        t.rls_enabled,
        t.rls_forced,
        t.replica_identity,
        t.bytes,
        t.size,
        t.live_rows_estimate,
        t.dead_rows_estimate,
        t.comment,
        t.primary_keys,
        t.relationships
    FROM supasheet.tables t
    WHERE has_table_privilege(p_caller, t.id::oid, 'select')
        AND NOT (t.schema = schema_name AND t.name = table_name)
        AND EXISTS (
            SELECT 1
            FROM jsonb_array_elements(t.relationships) AS rel
            WHERE (
                (rel->>'source_table_name' = table_name AND rel->>'source_schema' = schema_name)
                OR
                (rel->>'target_table_name' = table_name AND rel->>'target_table_schema' = schema_name)
            )
        );
$$;

revoke all on FUNCTION supasheet.get_related_tables (text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_related_tables (text, text, text) to authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_permissions
----------------------------------------------------------------
drop function if exists supasheet.get_permissions (text, text);

create or replace function supasheet.get_permissions (
  schema_name text default null,
  p_caller text default current_user
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT coalesce(jsonb_object_agg(schemas.schema, schemas.resources), '{}'::jsonb)
    FROM (
        SELECT
            grants.schema,
            jsonb_object_agg(grants.name, grants.actions) AS resources
        FROM (
            SELECT
                t.schema,
                t.name,
                jsonb_agg(act.action ORDER BY act.action) AS actions
            FROM supasheet.tables t
            CROSS JOIN (VALUES ('select'), ('insert'), ('update'), ('delete')) AS act (action)
            WHERE (schema_name IS NULL OR t.schema = schema_name)
                AND has_table_privilege(p_caller, t.id::oid, act.action)
            GROUP BY t.schema, t.name

            UNION ALL

            SELECT v.schema, v.name, jsonb_build_array('select')
            FROM supasheet.views v
            WHERE (schema_name IS NULL OR v.schema = schema_name)
                AND has_table_privilege(p_caller, v.id::oid, 'select')

            UNION ALL

            SELECT mv.schema, mv.name, jsonb_build_array('select')
            FROM supasheet.materialized_views mv
            WHERE (schema_name IS NULL OR mv.schema = schema_name)
                AND has_table_privilege(p_caller, mv.id::oid, 'select')
        ) grants (schema, name, actions)
        GROUP BY grants.schema
    ) schemas (schema, resources);
$$;

revoke all on FUNCTION supasheet.get_permissions (text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_permissions (text, text) to authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_nav_items
----------------------------------------------------------------
drop function if exists supasheet.get_nav_items (text);

create or replace function supasheet.get_nav_items (
  schema_name text default null,
  p_caller text default current_user
) returns table (type text, count bigint) language sql security definer
set
  search_path = '' as $$
  SELECT
    combined.type,
    count(*) AS count
  FROM (
    SELECT
      v.comment::jsonb ->> 'type' AS type
    FROM supasheet.views v
    WHERE (schema_name IS NULL OR v.schema = schema_name)
      AND v.comment IS NOT NULL
      AND v.comment::jsonb ->> 'type' IN ('dashboard_widget', 'chart', 'report', 'template')
      AND has_table_privilege(p_caller, v.id::oid, 'select')

    UNION ALL

    SELECT
      mv.comment::jsonb ->> 'type' AS type
    FROM supasheet.materialized_views mv
    WHERE (schema_name IS NULL OR mv.schema = schema_name)
      AND mv.comment IS NOT NULL
      AND mv.comment::jsonb ->> 'type' IN ('dashboard_widget', 'chart', 'report', 'template')
      AND has_table_privilege(p_caller, mv.id::oid, 'select')
  ) combined
  GROUP BY combined.type;
$$;

revoke all on FUNCTION supasheet.get_nav_items (text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_nav_items (text, text) to authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_actions
----------------------------------------------------------------
drop function if exists supasheet.get_actions (text, text, text);

create or replace function supasheet.get_actions (
  p_schema text default null,
  p_resource text default null,
  p_caller text default current_user
) returns table (
  id bigint,
  schema text,
  name text,
  arguments text,
  return_type text,
  security_type text,
  language text,
  roles jsonb,
  comment text
) language sql security definer
set
  search_path = '' as $$
    SELECT
        f.*
    FROM supasheet.functions f
    WHERE f.schema = p_schema
        AND f.comment::jsonb ->> 'type' = 'action'
        AND f.comment::jsonb ->> 'resource' = p_resource
        AND has_function_privilege(p_caller, f.id::oid, 'execute');
$$;

revoke all on FUNCTION supasheet.get_actions (text, text, text)
from
  public,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_actions (text, text, text) to authenticated;

----------------------------------------------------------------
-- Function: supasheet.set_updated_at
----------------------------------------------------------------
create or replace function supasheet.set_updated_at () returns trigger as $$
begin
    new.updated_at := now();
    return new;
end;
$$ language plpgsql;

----------------------------------------------------------------
-- Function: supasheet.set_updated_by
----------------------------------------------------------------
create or replace function supasheet.set_updated_by () returns trigger as $$
begin
    if auth.uid () is not null then
        new.updated_by := auth.uid ();
    end if;
    return new;
end;
$$ language plpgsql;
