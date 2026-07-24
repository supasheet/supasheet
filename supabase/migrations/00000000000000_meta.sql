create schema if not exists supasheet;

-- Initialize schema and extensions
grant usage on schema supasheet to anon,
authenticated,
service_role;

----------------------------------------------------------------
-- Materialized View: supasheet.tables
----------------------------------------------------------------
create materialized view if not exists supasheet.tables as
select
  c.oid::int8 as id,
  nc.nspname::text as schema,
  c.relname::text as name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as rls_forced,
  case
    when c.relreplident = 'd' then 'DEFAULT'
    when c.relreplident = 'i' then 'INDEX'
    when c.relreplident = 'f' then 'FULL'
    else 'NOTHING'
  end as replica_identity,
  pg_total_relation_size(format('%I.%I', nc.nspname, c.relname))::int8 as bytes,
  pg_size_pretty(
    pg_total_relation_size(format('%I.%I', nc.nspname, c.relname))
  ) as size,
  pg_stat_get_live_tuples (c.oid) as live_rows_estimate,
  pg_stat_get_dead_tuples (c.oid) as dead_rows_estimate,
  obj_description(c.oid) as comment,
  coalesce(pk.primary_keys, '[]') as primary_keys,
  coalesce(
    jsonb_agg(relationships) filter (
      where
        relationships is not null
    ),
    '[]'
  ) as relationships
from
  pg_namespace nc
  join pg_class c on nc.oid = c.relnamespace
  left join (
    select
      table_id,
      jsonb_agg(_pk.*) as primary_keys
    from
      (
        select
          n.nspname as schema,
          c.relname as table_name,
          a.attname as name,
          c.oid::int8 as table_id
        from
          pg_index i,
          pg_class c,
          pg_attribute a,
          pg_namespace n
        where
          i.indrelid = c.oid
          and c.relnamespace = n.oid
          and a.attrelid = c.oid
          and a.attnum = any (i.indkey)
          and i.indisprimary
      ) as _pk
    group by
      table_id
  ) as pk on pk.table_id = c.oid
  left join (
    select
      c.oid::int8 as id,
      c.conname as constraint_name,
      nsa.nspname as source_schema,
      csa.relname as source_table_name,
      sa.attname as source_column_name,
      nta.nspname as target_table_schema,
      cta.relname as target_table_name,
      ta.attname as target_column_name
    from
      pg_constraint c
      join (
        pg_attribute sa
        join pg_class csa on sa.attrelid = csa.oid
        join pg_namespace nsa on csa.relnamespace = nsa.oid
      ) on sa.attrelid = c.conrelid
      and sa.attnum = any (c.conkey)
      join (
        pg_attribute ta
        join pg_class cta on ta.attrelid = cta.oid
        join pg_namespace nta on cta.relnamespace = nta.oid
      ) on ta.attrelid = c.confrelid
      and ta.attnum = any (c.confkey)
    where
      c.contype = 'f'
  ) as relationships on (
    relationships.source_schema = nc.nspname
    and relationships.source_table_name = c.relname
  )
  or (
    relationships.target_table_schema = nc.nspname
    and relationships.target_table_name = c.relname
  )
where
  c.relkind in ('r', 'p')
  and not pg_is_other_temp_schema(nc.oid)
  -- Exclude transient rewrite heaps (pg_temp_<oid>) created in this schema
  -- while these materialized views refresh themselves
  and c.relname !~ '^pg_temp_\d+$'
  and nc.nspname not in (
    'vault',
    'supabase_migrations',
    'pg_catalog',
    'realtime',
    'storage',
    'supabase_functions',
    '_realtime',
    'information_schema',
    'net',
    'auth',
    'extensions'
  )
  and (
    pg_has_role(c.relowner, 'USAGE')
    or has_table_privilege(
      c.oid,
      'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
    )
    or has_any_column_privilege(c.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
  )
group by
  c.oid,
  c.relname,
  c.relrowsecurity,
  c.relforcerowsecurity,
  c.relreplident,
  nc.nspname,
  pk.primary_keys
order by
  c.oid
with
  no data;

revoke all on supasheet.tables
from
  public,
  anon,
  authenticated,
  service_role;

create unique index on supasheet.tables (id);

create unique index on supasheet.tables (schema, name);

create index on supasheet.tables (schema);

create index on supasheet.tables (name);

----------------------------------------------------------------
-- Materialized View: supasheet.columns
----------------------------------------------------------------
create materialized view if not exists supasheet.columns as
-- Adapted from information_schema.columns
select
  c.oid::int8 as table_id,
  nc.nspname::text as schema,
  c.relname::text as "table",
  (c.oid || '.' || a.attnum) as id,
  a.attnum as ordinal_position,
  a.attname::text as "name",
  case
    when a.atthasdef then pg_get_expr(ad.adbin, ad.adrelid)
    else null
  end as default_value,
  case
    when t.typtype = 'd' then case
      when bt.typelem <> 0::oid
      and bt.typlen = -1 then 'ARRAY'
      when nbt.nspname = 'pg_catalog' then format_type(t.typbasetype, null)
      else 'USER-DEFINED'
    end
    else case
      when t.typelem <> 0::oid
      and t.typlen = -1 then 'ARRAY'
      when nt.nspname = 'pg_catalog' then format_type(a.atttypid, null)
      else 'USER-DEFINED'
    end
  end as data_type,
  t.typname::text as actual_type,
  COALESCE(bt.typname, t.typname)::text as format,
  COALESCE(nbt.nspname, nt.nspname)::text as format_schema,
  a.attidentity in ('a', 'd') as is_identity,
  case a.attidentity
    when 'a' then 'ALWAYS'
    when 'd' then 'BY DEFAULT'
    else null
  end as identity_generation,
  a.attgenerated in ('s') as is_generated,
  not (
    a.attnotnull
    or t.typtype = 'd'
    and t.typnotnull
  ) as is_nullable,
  (
    c.relkind in ('r', 'p')
    or c.relkind in ('v', 'f')
    and pg_column_is_updatable (c.oid, a.attnum, false)
  ) as is_updatable,
  uniques.table_id is not null as is_unique,
  check_constraints.definition as "check",
  array_to_json(
    array(
      select
        enumlabel
      from
        pg_catalog.pg_enum enums
      where
        enums.enumtypid = coalesce(bt.oid, t.oid)
        or enums.enumtypid = coalesce(bt.typelem, t.typelem)
      order by
        enums.enumsortorder
    )
  ) as enums,
  col_description(c.oid, a.attnum) as "comment"
from
  pg_attribute a
  left join pg_attrdef ad on a.attrelid = ad.adrelid
  and a.attnum = ad.adnum
  join (
    pg_class c
    join pg_namespace nc on c.relnamespace = nc.oid
  ) on a.attrelid = c.oid
  join (
    pg_type t
    join pg_namespace nt on t.typnamespace = nt.oid
  ) on a.atttypid = t.oid
  left join (
    pg_type bt
    join pg_namespace nbt on bt.typnamespace = nbt.oid
  ) on t.typtype = 'd'
  and t.typbasetype = bt.oid
  left join (
    select distinct
      on (table_id, ordinal_position) conrelid as table_id,
      conkey[1] as ordinal_position
    from
      pg_catalog.pg_constraint
    where
      contype = 'u'
      and cardinality(conkey) = 1
  ) as uniques on uniques.table_id = c.oid
  and uniques.ordinal_position = a.attnum
  left join (
    -- We only select the first column check
    select distinct
      on (table_id, ordinal_position) conrelid as table_id,
      conkey[1] as ordinal_position,
      substring(
        pg_get_constraintdef(pg_constraint.oid, true),
        8,
        length(pg_get_constraintdef(pg_constraint.oid, true)) - 8
      ) as "definition"
    from
      pg_constraint
    where
      contype = 'c'
      and cardinality(conkey) = 1
    order by
      table_id,
      ordinal_position,
      oid asc
  ) as check_constraints on check_constraints.table_id = c.oid
  and check_constraints.ordinal_position = a.attnum
where
  not pg_is_other_temp_schema(nc.oid)
  -- Exclude transient rewrite heaps (pg_temp_<oid>) created in this schema
  -- while these materialized views refresh themselves
  and c.relname !~ '^pg_temp_\d+$'
  and nc.nspname not in (
    'vault',
    'supabase_migrations',
    'pg_catalog',
    'realtime',
    'storage',
    'supabase_functions',
    '_realtime',
    'information_schema',
    'net',
    'auth',
    'extensions'
  )
  and a.attnum > 0
  and not a.attisdropped
  and (c.relkind in ('r', 'v', 'm', 'f', 'p'))
  and (
    pg_has_role(c.relowner, 'USAGE')
    or has_column_privilege(
      c.oid,
      a.attnum,
      'SELECT, INSERT, UPDATE, REFERENCES'
    )
  )
order by
  c.oid,
  a.attnum
with
  no data;

revoke all on supasheet.columns
from
  public,
  anon,
  authenticated,
  service_role;

create unique index on supasheet.columns (id);

create index on supasheet.columns (table_id);

create index on supasheet.columns (schema, "table");

create index on supasheet.columns (schema, "table", name);

create index on supasheet.columns (name);

----------------------------------------------------------------
-- Materialized View: supasheet.views
----------------------------------------------------------------
create materialized view if not exists supasheet.views as
select
  c.oid::int8 as id,
  n.nspname::text as schema,
  c.relname::text as name,
  -- See definition of information_schema.views
  (pg_relation_is_updatable (c.oid, false) & 20) = 20 as is_updatable,
  obj_description(c.oid) as comment
from
  pg_class c
  join pg_namespace n on n.oid = c.relnamespace
where
  c.relkind = 'v'
  and not pg_is_other_temp_schema(n.oid)
  and n.nspname not in (
    'vault',
    'supabase_migrations',
    'pg_catalog',
    'realtime',
    'storage',
    'supabase_functions',
    '_realtime',
    'information_schema',
    'net',
    'auth',
    'extensions'
  )
  and (
    pg_has_role(c.relowner, 'USAGE')
    or has_table_privilege(
      c.oid,
      'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
    )
    or has_any_column_privilege(c.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
  )
order by
  c.oid
with
  no data;

revoke all on supasheet.views
from
  public,
  anon,
  authenticated,
  service_role;

create unique index on supasheet.views (id);

create unique index on supasheet.views (schema, name);

create index on supasheet.views (schema);

----------------------------------------------------------------
-- Materialized View: supasheet.materialized_views
----------------------------------------------------------------
create materialized view if not exists supasheet.materialized_views as
select
  c.oid::int8 as id,
  n.nspname::text as schema,
  c.relname::text as name,
  c.relispopulated as is_populated,
  obj_description(c.oid) as comment
from
  pg_class c
  join pg_namespace n on n.oid = c.relnamespace
where
  c.relkind = 'm'
  and not pg_is_other_temp_schema(n.oid)
  and n.nspname not in (
    'vault',
    'supabase_migrations',
    'pg_catalog',
    'realtime',
    'storage',
    'supabase_functions',
    '_realtime',
    'information_schema',
    'net',
    'auth',
    'extensions'
  )
  and (
    pg_has_role(c.relowner, 'USAGE')
    or has_table_privilege(
      c.oid,
      'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'
    )
    or has_any_column_privilege(c.oid, 'SELECT, INSERT, UPDATE, REFERENCES')
  )
order by
  c.oid
with
  no data;

revoke all on supasheet.materialized_views
from
  public,
  anon,
  authenticated,
  service_role;

create unique index on supasheet.materialized_views (id);

create unique index on supasheet.materialized_views (schema, name);

create index on supasheet.materialized_views (schema);

----------------------------------------------------------------
-- Materialized View: supasheet.functions
----------------------------------------------------------------
create materialized view if not exists supasheet.functions as
select
  p.oid::int8 as id,
  n.nspname::text as schema,
  p.proname::text as name,
  pg_get_function_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as return_type,
  case
    when p.prosecdef then 'DEFINER'
    else 'INVOKER'
  end as security_type,
  l.lanname::text as language,
  coalesce(
    (
      select
        jsonb_agg(
          distinct r.rolname
          order by
            r.rolname
        )
      from
        aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
        join pg_roles r on r.oid = acl.grantee
      where
        acl.privilege_type = 'EXECUTE'
    ),
    '[]'
  ) as roles,
  obj_description(p.oid, 'pg_proc') as comment
from
  pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  join pg_language l on l.oid = p.prolang
where
  p.prokind = 'f'
  and p.prorettype <> 'trigger'::regtype
  and not pg_is_other_temp_schema(n.oid)
  and n.nspname not in (
    'vault',
    'supabase_migrations',
    'pg_catalog',
    'realtime',
    'storage',
    'supabase_functions',
    '_realtime',
    'information_schema',
    'net',
    'auth',
    'extensions'
  )
  and (
    pg_has_role(p.proowner, 'USAGE')
    or has_function_privilege(p.oid, 'EXECUTE')
  )
order by
  p.oid
with
  no data;

revoke all on supasheet.functions
from
  public,
  anon,
  authenticated,
  service_role;

create unique index on supasheet.functions (id);

create index on supasheet.functions (schema, name);

-- Initial population
refresh materialized view supasheet.columns;

refresh materialized view supasheet.tables;

refresh materialized view supasheet.views;

refresh materialized view supasheet.materialized_views;

refresh materialized view supasheet.functions;

----------------------------------------------------------------
-- Manual refresh function for all metadata materialized views
----------------------------------------------------------------
-- Run this after any DDL changes (create/alter/drop table, view,
-- materialized view, schema, enum, or comment) to keep the
-- metadata materialized views in sync:
--   select supasheet.refresh_metadata();
create or replace function supasheet.refresh_metadata () RETURNS void as $$
BEGIN
    REFRESH MATERIALIZED VIEW supasheet.tables;
    REFRESH MATERIALIZED VIEW supasheet.columns;
    REFRESH MATERIALIZED VIEW supasheet.views;
    REFRESH MATERIALIZED VIEW supasheet.materialized_views;
    REFRESH MATERIALIZED VIEW supasheet.functions;
END;
$$ LANGUAGE plpgsql
set
  search_path = '';

-- By default Postgres grants EXECUTE on new functions to PUBLIC.
-- Revoke it so only the owner (postgres) role can refresh metadata.
revoke all on function supasheet.refresh_metadata ()
from
  public,
  anon,
  authenticated,
  service_role;
