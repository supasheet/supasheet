----------------------------------------------------------------
-- Function: supasheet.get_schemas
----------------------------------------------------------------
create or replace function supasheet.get_schemas () RETURNS table (schema text) LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        DISTINCT t.schema
    FROM supasheet.tables t
    INNER JOIN supasheet.role_permissions rp
        ON rp.permission::text = t.schema || '.' || t.name || ':select'
    INNER JOIN supasheet.user_roles ur
        ON ur.role = rp.role
    WHERE ur.user_id = (select auth.uid());
$$;

revoke all on FUNCTION supasheet.get_schemas ()
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_schemas () to authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_tables
----------------------------------------------------------------
create or replace function supasheet.get_tables (
  schema_name text default null,
  table_name text default null,
  action text default 'select'
) RETURNS SETOF supasheet.tables LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        t.*
    FROM supasheet.tables t
    WHERE (table_name IS NULL OR t.name = table_name)
        AND (schema_name IS NULL OR t.schema = schema_name)
        AND (
            (
                (select auth.uid()) IS NULL
                AND has_table_privilege(
                    'anon',
                    format('%I.%I', t.schema, t.name),
                    action
                )
            )
            OR
            (
                (select auth.uid()) IS NOT NULL
                AND has_table_privilege(
                    'authenticated',
                    format('%I.%I', t.schema, t.name),
                    action
                )
                AND EXISTS (
                    SELECT 1
                    FROM supasheet.role_permissions rp
                    INNER JOIN supasheet.user_roles ur
                        ON ur.role = rp.role
                    WHERE ur.user_id = (select auth.uid())
                        AND rp.permission::text = t.schema || '.' || t.name || ':' || action
                )
            )
        );
$$;

revoke all on FUNCTION supasheet.get_tables (text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_tables (text, text, text) to anon,
authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_views
----------------------------------------------------------------
create or replace function supasheet.get_views (
  schema_name text default null,
  view_name text default null,
  action text default 'select'
) RETURNS SETOF supasheet.views LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        t.*
    FROM supasheet.views t
    WHERE (view_name IS NULL OR t.name = view_name)
        AND (schema_name IS NULL OR t.schema = schema_name)
        AND (
            (
                (select auth.uid()) IS NULL
                AND has_table_privilege(
                    'anon',
                    format('%I.%I', t.schema, t.name),
                    action
                )
            )
            OR
            (
                (select auth.uid()) IS NOT NULL
                AND has_table_privilege(
                    'authenticated',
                    format('%I.%I', t.schema, t.name),
                    action
                )
                AND EXISTS (
                    SELECT 1
                    FROM supasheet.role_permissions rp
                    INNER JOIN supasheet.user_roles ur
                        ON ur.role = rp.role
                    WHERE ur.user_id = (select auth.uid())
                        AND rp.permission::text = t.schema || '.' || t.name || ':' || action
                )
            )
        );
$$;

revoke all on FUNCTION supasheet.get_views (text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_views (text, text, text) to anon,
authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_materialized_views
----------------------------------------------------------------
create or replace function supasheet.get_materialized_views (
  schema_name text default null,
  view_name text default null,
  action text default 'select'
) RETURNS SETOF supasheet.materialized_views LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        t.*
    FROM supasheet.materialized_views t
    WHERE (view_name IS NULL OR t.name = view_name)
        AND (schema_name IS NULL OR t.schema = schema_name)
        AND (
            (
                (select auth.uid()) IS NULL
                AND has_table_privilege(
                    'anon',
                    format('%I.%I', t.schema, t.name),
                    action
                )
            )
            OR
            (
                (select auth.uid()) IS NOT NULL
                AND has_table_privilege(
                    'authenticated',
                    format('%I.%I', t.schema, t.name),
                    action
                )
                AND EXISTS (
                    SELECT 1
                    FROM supasheet.role_permissions rp
                    INNER JOIN supasheet.user_roles ur
                        ON ur.role = rp.role
                    WHERE ur.user_id = (select auth.uid())
                        AND rp.permission::text = t.schema || '.' || t.name || ':' || action
                )
            )
        );
$$;

revoke all on FUNCTION supasheet.get_materialized_views (text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_materialized_views (text, text, text) to anon,
authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_columns
----------------------------------------------------------------
create or replace function supasheet.get_columns (
  schema_name text default null,
  table_name text default null,
  action text default 'select'
) RETURNS SETOF supasheet.columns LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        t.*
    FROM supasheet.columns t
    WHERE (table_name IS NULL OR t.table = table_name)
        AND (schema_name IS NULL OR t.schema = schema_name)
        AND (
            (
                (select auth.uid()) IS NULL
                AND CASE
                    WHEN lower(action) = 'delete'
                        THEN has_table_privilege('anon', t.table_id::oid, action)
                    ELSE has_column_privilege('anon', t.table_id::oid, t.name, action)
                END
            )
            OR
            (
                (select auth.uid()) IS NOT NULL
                AND CASE
                    WHEN lower(action) = 'delete'
                        THEN has_table_privilege('authenticated', t.table_id::oid, action)
                    ELSE has_column_privilege('authenticated', t.table_id::oid, t.name, action)
                END
                AND EXISTS (
                    SELECT 1
                    FROM supasheet.role_permissions rp
                    INNER JOIN supasheet.user_roles ur
                        ON ur.role = rp.role
                    WHERE ur.user_id = (select auth.uid())
                        AND rp.permission::text = t.schema || '.' || t.table || ':' || action
                )
            )
        )
    ORDER BY (t.ordinal_position::int);
$$;

revoke all on FUNCTION supasheet.get_columns (text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_columns (text, text, text) to anon,
authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_privileges
----------------------------------------------------------------
-- Returns the CRUD privileges (select/insert/update/delete) the caller
-- effectively holds on a table/view. The role is derived from the session:
-- `anon` when unauthenticated, `authenticated` otherwise. For authenticated
-- callers the postgres grant must be matched by an app permission in
-- role_permissions (same rule as get_tables); anon relies on the grant alone.
create or replace function supasheet.get_privileges (schema_name text, resource_name text) RETURNS table (privilege text) LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    WITH effective AS (
        SELECT
            CASE WHEN (select auth.uid()) IS NULL THEN 'anon' ELSE 'authenticated' END AS role
    )
    SELECT act.action AS privilege
    FROM effective e
    CROSS JOIN (VALUES ('select'), ('insert'), ('update'), ('delete')) AS act(action)
    WHERE has_table_privilege(
            e.role,
            format('%I.%I', schema_name, resource_name),
            act.action
        )
        AND (
            e.role <> 'authenticated'
            OR EXISTS (
                SELECT 1
                FROM supasheet.role_permissions rp
                INNER JOIN supasheet.user_roles ur
                    ON ur.role = rp.role
                WHERE ur.user_id = (select auth.uid())
                    AND rp.permission::text = schema_name || '.' || resource_name || ':' || act.action
            )
        );
$$;

revoke all on FUNCTION supasheet.get_privileges (text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_privileges (text, text) to anon,
authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_related_tables
----------------------------------------------------------------
drop function if exists supasheet.get_related_tables (text, text);

create or replace function supasheet.get_related_tables (schema_name text, table_name text) RETURNS table (
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
    INNER JOIN supasheet.role_permissions rp
        ON rp.permission::text = t.schema || '.' || t.name || ':select'
    INNER JOIN supasheet.user_roles ur
        ON ur.role = rp.role
    WHERE ur.user_id = (select auth.uid())
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

revoke all on FUNCTION supasheet.get_related_tables (text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_related_tables (text, text) to authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_permissions
----------------------------------------------------------------
create or replace function supasheet.get_permissions (schema_name text default null) RETURNS table (permission supasheet.app_permission) LANGUAGE sql SECURITY DEFINER
set
  search_path = '' as $$
    SELECT
        DISTINCT rp.permission
    FROM supasheet.role_permissions rp
    INNER JOIN supasheet.user_roles ur
        ON ur.role = rp.role
    WHERE ur.user_id = (select auth.uid())
        AND (schema_name IS NULL OR rp.permission::text LIKE schema_name || '.%');
$$;

revoke all on FUNCTION supasheet.get_permissions (text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_permissions (text) to authenticated;

----------------------------------------------------------------
-- Function: supasheet.get_nav_items
----------------------------------------------------------------
create or replace function supasheet.get_nav_items (schema_name text default null) returns table (type text, count bigint) language sql security definer
set
  search_path = '' as $$
  SELECT
    combined.type,
    count(*) AS count
  FROM (
    SELECT
      v.comment::jsonb ->> 'type' AS type
    FROM supasheet.views v
    INNER JOIN supasheet.role_permissions rp
        ON rp.permission::text = v.schema || '.' || v.name || ':select'
    INNER JOIN supasheet.user_roles ur
        ON ur.role = rp.role
    WHERE ur.user_id = (SELECT auth.uid())
      AND (schema_name IS NULL OR v.schema = schema_name)
      AND v.comment IS NOT NULL
      AND v.comment::jsonb ->> 'type' IN ('dashboard_widget', 'chart', 'report', 'template')

    UNION ALL

    SELECT
      mv.comment::jsonb ->> 'type' AS type
    FROM supasheet.materialized_views mv
    INNER JOIN supasheet.role_permissions rp
        ON rp.permission::text = mv.schema || '.' || mv.name || ':select'
    INNER JOIN supasheet.user_roles ur
        ON ur.role = rp.role
    WHERE ur.user_id = (SELECT auth.uid())
      AND (schema_name IS NULL OR mv.schema = schema_name)
      AND mv.comment IS NOT NULL
      AND mv.comment::jsonb ->> 'type' IN ('dashboard_widget', 'chart', 'report', 'template')
  ) combined
  GROUP BY combined.type;
$$;

revoke all on FUNCTION supasheet.get_nav_items (text)
from
  anon,
  authenticated,
  service_role;

grant
execute on FUNCTION supasheet.get_nav_items (text) to authenticated;

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
