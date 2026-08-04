-- ================================================================
-- Supasheet Example — "Manufacturing" (works orders and the shop floor)
-- ================================================================
-- A production-shaped manufacturing back office: an engineering item
-- master with multi-level bills of material, routings across work
-- centres, works orders that explode both, shop-floor confirmations,
-- machine downtime and maintenance, and inspection with
-- non-conformance handling.
--
-- Demo data lives in supabase/examples/m_seed.sql — apply this file
-- first, then that one.
--
-- This is not the inventory module with different words on it. That
-- one asks "where is it and where did it come from?". This one asks
-- "what is it made of, who built it, on which machine, how long did
-- it take, and did it pass?" — which is a different database, built
-- around a structure none of the other examples have: a bill of
-- material is RECURSIVE, and almost every rule below follows from
-- that one fact.
--
-- The rules that make it a manufacturing system rather than a set of
-- lists:
--
--   - A BILL OF MATERIAL CANNOT CONTAIN ITSELF. Not directly, and not
--     through any depth of sub-assembly. The check is a recursive
--     walk on write, because a cycle here does not produce a wrong
--     number — it produces a query that never returns.
--   - YOU CANNOT BUILD WHAT YOU CANNOT CONSUME. Releasing a works
--     order explodes the bill at the quantity ordered and freezes the
--     requirement; completing it consumes exactly that.
--   - MATERIAL IS CONSERVED. What went in equals what came out plus
--     what was scrapped. A works order that yielded 95 good and 5
--     scrapped consumed components for 100.
--   - OPERATIONS ARE SEQUENTIAL. Operation 20 cannot start until
--     operation 10 has finished, because the part is not there yet.
--   - STANDARD COST ROLLS UP. A parent costs the sum of its children
--     plus its own labour and overhead, computed by walking the tree.
--     Nobody types a rolled-up cost.
--
-- Everything the other modules cover is here too:
--   - Native-role RBAC with three custom roles ("production-planner",
--     "operator", "inspector") alongside "x-admin"/"user"
--   - RLS that follows the shop floor: an operator sees the works
--     orders at the work centres they are certified on, resolved
--     through STABLE SECURITY DEFINER helpers
--   - All six view layouts, every widget and chart contract, reports
--     with a Handlebars print template, a materialized cost rollup,
--     templates, row actions, custom form shapes, notifications,
--     audit logging and per-resource comments
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260806000000_manufacturing.sql \
--     -f supabase/examples/m_seed.sql
--
-- Requires the base Supasheet migrations. Add "manufacturing" to
-- config.toml's `api.schemas` and `api.extra_search_path`, then
-- restart Supabase.
--
-- Not idempotent: re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists manufacturing;

-------------------------------------------------------------------
-- Roles
--
--   x-admin    production manager: everything, including closing
--              works orders and dispositioning non-conformances
--   production-planner  owns the engineering data and the schedule:
--              products, bills of material, routings, works orders.
--              Cannot confirm production
--   operator   the shop floor: starts and finishes operations,
--              declares output and scrap, reports downtime and
--              defects — on the work centres they are certified on
--   inspector  quality: inspection plans, results and
--              non-conformances. Cannot build anything
--   user       reads the product catalogue and nothing else
--
-- Assign a user to a custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "operator"}'
--   where email = 'floor@example.com';
-------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'user') then
    create role "user" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'admin') then
    create role "admin" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'production-planner') then
    create role "production-planner" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'operator') then
    create role "operator" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'inspector') then
    create role "inspector" nologin;
  end if;
end;
$$;

grant "user",
"admin",
"production-planner",
"operator",
"inspector" to authenticator;

grant authenticated to "user",
"admin",
"production-planner",
"operator",
"inspector";

grant usage on schema manufacturing to "x-admin",
"production-planner",
"operator",
"inspector",
"user";

create or replace function supasheet.assign_default_role () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.raw_app_meta_data ->> 'role' is null then
    new.raw_app_meta_data := coalesce(new.raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'user');
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_assign_role on auth.users;

create trigger on_auth_user_created_assign_role
before insert on auth.users for each row
execute function supasheet.assign_default_role ();

-------------------------------------------------------------------
-- Enums
-------------------------------------------------------------------
create type manufacturing.product_type as enum('make', 'buy', 'phantom');

create type manufacturing.product_status as enum('draft', 'active', 'obsolete');

create type manufacturing.bom_status as enum('draft', 'active', 'obsolete');

create type manufacturing.routing_status as enum('draft', 'active', 'obsolete');

create type manufacturing.work_center_type as enum(
  'machining',
  'assembly',
  'fabrication',
  'finishing',
  'inspection',
  'packing'
);

create type manufacturing.machine_status as enum(
  'running',
  'idle',
  'down',
  'maintenance',
  'retired'
);

create type manufacturing.order_status as enum(
  'draft',
  'planned',
  'released',
  'in_progress',
  'completed',
  'closed',
  'cancelled'
);

create type manufacturing.order_priority as enum('low', 'normal', 'high', 'urgent');

create type manufacturing.operation_status as enum(
  'pending',
  'setup',
  'running',
  'paused',
  'completed',
  'skipped'
);

create type manufacturing.issue_method as enum('manual', 'backflush');

create type manufacturing.downtime_reason as enum(
  'breakdown',
  'changeover',
  'material_shortage',
  'no_operator',
  'quality_hold',
  'planned_maintenance',
  'tooling'
);

create type manufacturing.maintenance_type as enum(
  'preventive',
  'corrective',
  'calibration',
  'inspection'
);

create type manufacturing.maintenance_status as enum(
  'scheduled',
  'in_progress',
  'completed',
  'overdue',
  'cancelled'
);

create type manufacturing.inspection_result as enum('pending', 'pass', 'fail', 'conditional_pass');

create type manufacturing.characteristic_type as enum(
  'dimensional',
  'visual',
  'functional',
  'material',
  'weight'
);

create type manufacturing.ncr_status as enum(
  'open',
  'investigating',
  'dispositioned',
  'closed'
);

create type manufacturing.ncr_disposition as enum(
  'pending',
  'rework',
  'scrap',
  'use_as_is',
  'return_to_supplier',
  'regrade'
);

create type manufacturing.defect_severity as enum('minor', 'major', 'critical');

-------------------------------------------------------------------
-- Users
-------------------------------------------------------------------
create or replace view manufacturing.users
with
  (security_invoker = true) as
select
  id,
  name,
  email,
  picture_url
from
  supasheet.users;

revoke all on manufacturing.users
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on manufacturing.users to "x-admin",
  "production-planner",
  "operator",
  "inspector",
  "user";

comment on view manufacturing.users is '{"display": "none"}';

----------------------------------------------------------------
-- Product families
----------------------------------------------------------------
create table manufacturing.product_families (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(120) not null,
  description varchar(300),
  product_count integer not null default 0,
  color supasheet.COLOR,
  is_active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table manufacturing.product_families is '{
    "icon": "Layers",
    "name": "Product Families",
    "description": "How the engineering catalogue is grouped.",
    "collapsible_group": "Engineering",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "name", "badges": ["code", "product_count"]}, "tabs": ["products"]},
    "views": [
        {"id": "list", "name": "All Families", "type": "list", "title": "name", "description": "description", "field_1": "code", "field_2": "product_count"}
    ],
    "fields": {
        "quick_create": ["code", "name"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "color", "is_active"]},
            {"id": "rollup", "title": "Rollup", "fields": {"read": ["product_count"]}}
        ]
    },
    "query": {"sort": [{"id": "code", "desc": false}]}
}';

revoke all on table manufacturing.product_families
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.product_families to "x-admin";

grant
select
,
  insert,
update on table manufacturing.product_families to "production-planner";

grant
select
  on table manufacturing.product_families to "operator",
  "inspector",
  "user";

alter table manufacturing.product_families enable row level security;

create policy families_select on manufacturing.product_families for
select
  to authenticated using (true);

create policy families_insert on manufacturing.product_families for insert to authenticated
with
  check (true);

create policy families_update on manufacturing.product_families
for update
  to authenticated using (true)
with
  check (true);

create policy families_delete on manufacturing.product_families for delete to authenticated using (true);

----------------------------------------------------------------
-- Products
--
-- The engineering master: everything that can appear on a bill of
-- material, whether it is bought in, made here, or a phantom that
-- exists only to group components.
--
-- The three cost columns are rolled up from the bill by
-- manufacturing.roll_up_cost (), never typed. They carry no grant to
-- the shop floor for the same reason the inventory example hides
-- cost from its operatives: building a part does not require knowing
-- its margin.
----------------------------------------------------------------
create table manufacturing.products (
  id uuid primary key default extensions.uuid_generate_v4 (),
  sku varchar(40) not null unique,
  name varchar(200) not null,
  description text,
  family_id uuid references manufacturing.product_families (id) on delete set null,
  product_type manufacturing.product_type not null default 'make',
  status manufacturing.product_status not null default 'draft',
  revision varchar(12) not null default 'A',
  uom varchar(12) not null default 'EA',
  drawing_number varchar(40),
  is_lot_controlled boolean not null default false,
  is_serialised boolean not null default false,
  shelf_life_days integer,
  lead_time_days integer not null default 5,
  lot_size numeric(14, 3) not null default 1,
  yield_percent supasheet.PERCENTAGE not null default 100,
  -- Rolled up, never entered.
  material_cost numeric(14, 4) not null default 0,
  labour_cost numeric(14, 4) not null default 0,
  overhead_cost numeric(14, 4) not null default 0,
  standard_cost numeric(14, 4) not null default 0,
  bom_level integer not null default 0,
  component_count integer not null default 0,
  where_used_count integer not null default 0,
  drawing supasheet.file,
  image supasheet.file,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint products_yield_sane check (
    yield_percent > 0
    and yield_percent <= 100
  ),
  constraint products_lot_size_positive check (lot_size > 0),
  constraint products_costs_non_negative check (
    material_cost >= 0
    and labour_cost >= 0
    and overhead_cost >= 0
  ),
  -- A bought part has no bill and no routing, so it cannot have a
  -- rolled-up labour cost. Its cost is what the supplier charges.
  constraint products_bought_has_no_labour check (
    product_type <> 'buy'
    or labour_cost = 0
  )
);

comment on column manufacturing.products.product_type is '{
    "progress": false,
    "values": {
        "make": {"variant": "info", "icon": "Factory"},
        "buy": {"variant": "secondary", "icon": "Truck"},
        "phantom": {"variant": "warning", "icon": "Ghost"}
    }
}';

comment on column manufacturing.products.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "active": {"variant": "success", "icon": "CircleCheck"},
        "obsolete": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table manufacturing.products is '{
    "icon": "Package",
    "description": "Everything that can appear on a bill of material.",
    "collapsible_group": "Engineering",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "name", "badges": ["sku", "revision", "product_type", "status"]},
        "tabs": ["boms", "routings", "production_orders"]
    },
    "views": [
        {"id": "gallery", "name": "Catalogue", "type": "gallery", "cover": "image", "title": "name", "description": "sku", "badge": "product_type"},
        {"id": "list", "name": "Item Master", "type": "list", "title": "name", "description": "sku", "field_1": "product_type", "field_2": "bom_level"},
        {"id": "kanban", "name": "By Lifecycle", "type": "kanban", "group": "status", "title": "name", "description": "sku", "date": "created_at", "badge": "revision"}
    ],
    "filter_presets": [
        {"id": "made", "name": "Made Here", "filters": [{"id": "product_type", "value": "make", "operator": "eq"}]},
        {"id": "bought", "name": "Bought In", "filters": [{"id": "product_type", "value": "buy", "operator": "eq"}]},
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "orphans", "name": "Not Used Anywhere", "filters": [{"id": "where_used_count", "value": "0", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["sku", "name", "product_type", "family_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": {"create": ["sku", "name", "description", "family_id", "product_type"], "update": ["name", "description", "family_id", "product_type", "status", "revision"], "read": ["sku", "name", "description", "family_id", "product_type", "status", "revision"]}},
            {"id": "engineering", "title": "Engineering", "fields": ["drawing_number", "drawing", "image", "uom"]},
            {"id": "planning", "title": "Planning", "fields": ["lead_time_days", "lot_size", "yield_percent", "is_lot_controlled", "is_serialised", "shelf_life_days"]},
            {"id": "purchase", "title": "Purchase cost", "fields": ["material_cost"]},
            {"id": "cost", "title": "Rolled-up cost", "fields": {"read": ["labour_cost", "overhead_cost", "standard_cost"]}},
            {"id": "structure", "title": "Structure", "fields": {"read": ["bom_level", "component_count", "where_used_count"]}},
            {"id": "notes", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ],
        "behavior": {
            "shelf_life_days": {"visible": [{"id": "is_lot_controlled", "operator": "eq", "value": "true"}]},
            "yield_percent": {"visible": [{"id": "product_type", "operator": "eq", "value": "make"}]},
            "lot_size": {"visible": [{"id": "product_type", "operator": "eq", "value": "make"}]},
            "material_cost": {"read_only": [{"id": "product_type", "operator": "neq", "value": "buy"}]}
        },
        "metadata": {
            "yield_percent": {"description": "Expected good output as a share of what is started. A 96% yield means a works order for 100 will start 105."},
            "bom_level": {"description": "How deep this part sits in the deepest bill that uses it. Level 0 is a finished good."},
            "material_cost": {"description": "Typed for a bought part — that is what the supplier charges. Rolled up from the bill for anything made here, so it is read-only there."}
        }
    },
    "query": {
        "sort": [{"id": "sku", "desc": false}],
        "join": [{"table": "product_families", "on": "family_id", "columns": ["code", "name"]}]
    }
}';

comment on column manufacturing.products.image is '{"accept": "image/*", "max_files": 4, "max_size": 5242880}';

comment on column manufacturing.products.drawing is '{"accept": ".pdf,.dxf,.step", "max_files": 3, "max_size": 10485760}';

comment on column manufacturing.products.standard_cost is '{"name": "Standard Cost", "aggregate": "sum"}';

comment on column manufacturing.products.where_used_count is '{"name": "Where Used"}';

revoke all on table manufacturing.products
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.products to "x-admin";

grant
select
,
  insert,
update on table manufacturing.products to "production-planner";

-- The floor and the inspector get everything that says what a part is
-- and nothing that says what it costs.
grant
select
  (
    id,
    sku,
    name,
    description,
    family_id,
    product_type,
    status,
    revision,
    uom,
    drawing_number,
    is_lot_controlled,
    is_serialised,
    shelf_life_days,
    lead_time_days,
    lot_size,
    yield_percent,
    bom_level,
    component_count,
    where_used_count,
    drawing,
    image,
    notes,
    created_at,
    updated_at
  ) on table manufacturing.products to "operator",
  "inspector",
  "user";

create index idx_mfg_products_family_id on manufacturing.products (family_id);

create index idx_mfg_products_type on manufacturing.products (product_type);

create index idx_mfg_products_status on manufacturing.products (status);

alter table manufacturing.products enable row level security;

create policy products_select on manufacturing.products for
select
  to authenticated using (true);

create policy products_insert on manufacturing.products for insert to authenticated
with
  check (true);

create policy products_update on manufacturing.products
for update
  to authenticated using (true)
with
  check (true);

create policy products_delete on manufacturing.products for delete to authenticated using (true);

----------------------------------------------------------------
-- Work centres and machines
----------------------------------------------------------------
create table manufacturing.work_centers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(120) not null,
  work_center_type manufacturing.work_center_type not null default 'machining',
  description varchar(300),
  capacity_hours_per_day numeric(6, 2) not null default 16,
  efficiency_percent supasheet.PERCENTAGE not null default 85,
  labour_rate_per_hour numeric(12, 4) not null default 0,
  overhead_rate_per_hour numeric(12, 4) not null default 0,
  queue_time_hours numeric(6, 2) not null default 0,
  is_bottleneck boolean not null default false,
  is_active boolean not null default true,
  machine_count integer not null default 0,
  open_operations integer not null default 0,
  scheduled_hours numeric(10, 2) not null default 0,
  utilisation supasheet.PERCENTAGE,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint work_centers_capacity_positive check (capacity_hours_per_day > 0),
  constraint work_centers_rates_non_negative check (
    labour_rate_per_hour >= 0
    and overhead_rate_per_hour >= 0
  )
);

comment on column manufacturing.work_centers.work_center_type is '{
    "progress": false,
    "values": {
        "machining": {"variant": "info", "icon": "Cog"},
        "assembly": {"variant": "success", "icon": "Wrench"},
        "fabrication": {"variant": "warning", "icon": "Hammer"},
        "finishing": {"variant": "default", "icon": "Paintbrush"},
        "inspection": {"variant": "secondary", "icon": "ScanSearch"},
        "packing": {"variant": "secondary", "icon": "PackageOpen"}
    }
}';

comment on table manufacturing.work_centers is '{
    "icon": "Factory",
    "name": "Work Centres",
    "description": "Where the work happens, what it costs per hour, and how loaded it is.",
    "collapsible_group": "Shop Floor",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "name", "badges": ["code", "work_center_type", "utilisation"]},
        "tabs": ["machines", "routing_operations", "production_order_operations"]
    },
    "views": [
        {"id": "kanban", "name": "By Type", "type": "kanban", "group": "work_center_type", "title": "name", "description": "code", "date": "created_at", "badge": "utilisation"},
        {"id": "list", "name": "All Work Centres", "type": "list", "title": "name", "description": "code", "field_1": "open_operations", "field_2": "utilisation"}
    ],
    "filter_presets": [
        {"id": "bottleneck", "name": "Bottlenecks", "filters": [{"id": "is_bottleneck", "value": "true", "operator": "eq"}]},
        {"id": "loaded", "name": "Loaded", "filters": [{"id": "open_operations", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "work_center_type"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "work_center_type", "description", "color", "is_active"]},
            {"id": "capacity", "title": "Capacity", "fields": ["capacity_hours_per_day", "efficiency_percent", "queue_time_hours", "is_bottleneck"]},
            {"id": "rates", "title": "Rates", "fields": ["labour_rate_per_hour", "overhead_rate_per_hour"]},
            {"id": "load", "title": "Load", "fields": {"read": ["machine_count", "open_operations", "scheduled_hours", "utilisation"]}}
        ],
        "metadata": {
            "efficiency_percent": {"description": "How much of the clock is actually productive here. Standard times are divided by this when the schedule is built."}
        }
    },
    "query": {"sort": [{"id": "code", "desc": false}]}
}';

comment on column manufacturing.work_centers.scheduled_hours is '{"name": "Scheduled", "aggregate": "sum"}';

revoke all on table manufacturing.work_centers
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.work_centers to "x-admin";

grant
select
,
  insert,
update on table manufacturing.work_centers to "production-planner";

grant
select
  (
    id,
    code,
    name,
    work_center_type,
    description,
    capacity_hours_per_day,
    efficiency_percent,
    queue_time_hours,
    is_bottleneck,
    is_active,
    machine_count,
    open_operations,
    scheduled_hours,
    utilisation,
    color,
    created_at,
    updated_at
  ) on table manufacturing.work_centers to "operator",
  "inspector";

alter table manufacturing.work_centers enable row level security;

create policy work_centers_select on manufacturing.work_centers for
select
  to authenticated using (true);

create policy work_centers_insert on manufacturing.work_centers for insert to authenticated
with
  check (true);

create policy work_centers_update on manufacturing.work_centers
for update
  to authenticated using (true)
with
  check (true);

create policy work_centers_delete on manufacturing.work_centers for delete to authenticated using (true);

create table manufacturing.machines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  work_center_id uuid not null references manufacturing.work_centers (id) on delete cascade,
  code varchar(24) not null unique,
  name varchar(120) not null,
  manufacturer varchar(120),
  model varchar(80),
  serial_number varchar(80),
  status manufacturing.machine_status not null default 'idle',
  commissioned_on date,
  last_service_on date,
  next_service_due date,
  service_interval_days integer not null default 90,
  runtime_hours numeric(12, 2) not null default 0,
  downtime_hours numeric(12, 2) not null default 0,
  availability supasheet.PERCENTAGE,
  open_downtime_events integer not null default 0,
  photo supasheet.file,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint machines_interval_positive check (service_interval_days > 0)
);

comment on column manufacturing.machines.status is '{
    "progress": true,
    "values": {
        "running": {"variant": "success", "icon": "Play"},
        "idle": {"variant": "secondary", "icon": "Pause"},
        "down": {"variant": "destructive", "icon": "TriangleAlert"},
        "maintenance": {"variant": "warning", "icon": "Wrench"},
        "retired": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table manufacturing.machines is '{
    "icon": "Cog",
    "description": "The assets that do the work, and how much of the time they are able to.",
    "collapsible_group": "Shop Floor",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "name", "badges": ["code", "status", "availability"]},
        "tabs": ["downtime_events", "maintenance_orders"]
    },
    "views": [
        {"id": "kanban", "name": "Floor Status", "type": "kanban", "group": "status", "title": "name", "description": "code", "date": "next_service_due", "badge": "availability"},
        {"id": "gallery", "name": "Asset Photos", "type": "gallery", "cover": "photo", "title": "name", "description": "model", "badge": "status"},
        {"id": "calendar", "name": "Service Due", "type": "calendar", "title": "name", "badge": "status", "start_date": "next_service_due"},
        {"id": "list", "name": "All Machines", "type": "list", "title": "name", "description": "manufacturer", "field_1": "status", "field_2": "availability"}
    ],
    "filter_presets": [
        {"id": "down", "name": "Down", "filters": [{"id": "status", "value": "down", "operator": "eq"}]},
        {"id": "service_due", "name": "Service Due", "filters": [{"id": "next_service_due", "value": "today", "operator": "lte"}]},
        {"id": "poor", "name": "Poor Availability", "filters": [{"id": "availability", "value": "85", "operator": "lt"}]}
    ],
    "fields": {
        "quick_create": ["work_center_id", "code", "name"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["work_center_id", "code", "name", "status", "photo"]},
            {"id": "asset", "title": "Asset", "fields": ["manufacturer", "model", "serial_number", "commissioned_on"]},
            {"id": "service", "title": "Service", "fields": ["service_interval_days", "last_service_on", "next_service_due"]},
            {"id": "performance", "title": "Performance", "fields": {"read": ["runtime_hours", "downtime_hours", "availability", "open_downtime_events"]}},
            {"id": "notes", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "work_centers", "on": "work_center_id", "columns": ["code", "name", "work_center_type"]}]
    }
}';

comment on column manufacturing.machines.photo is '{"accept": "image/*", "max_files": 3, "max_size": 5242880}';

comment on column manufacturing.machines.downtime_hours is '{"name": "Downtime", "aggregate": "sum"}';

revoke all on table manufacturing.machines
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.machines to "x-admin";

grant
select
,
  insert,
update on table manufacturing.machines to "production-planner";

grant
select
,
update on table manufacturing.machines to "operator";

grant
select
  on table manufacturing.machines to "inspector";

create index idx_mfg_machines_work_center_id on manufacturing.machines (work_center_id);

create index idx_mfg_machines_status on manufacturing.machines (status);

alter table manufacturing.machines enable row level security;

create policy machines_select on manufacturing.machines for
select
  to authenticated using (true);

create policy machines_insert on manufacturing.machines for insert to authenticated
with
  check (true);

create policy machines_update on manufacturing.machines
for update
  to authenticated using (true)
with
  check (true);

create policy machines_delete on manufacturing.machines for delete to authenticated using (true);

----------------------------------------------------------------
-- Bills of material
--
-- A BOM header belongs to a product and carries a version. Only one
-- version may be active at a time, because "which bill did we build
-- this to?" has to have exactly one answer.
----------------------------------------------------------------
create table manufacturing.boms (
  id uuid primary key default extensions.uuid_generate_v4 (),
  product_id uuid not null references manufacturing.products (id) on delete cascade,
  version varchar(12) not null default 'A',
  status manufacturing.bom_status not null default 'draft',
  name varchar(160),
  output_quantity numeric(14, 3) not null default 1,
  effective_from date not null default current_date,
  effective_to date,
  line_count integer not null default 0,
  material_cost numeric(14, 4) not null default 0,
  approved_by uuid references supasheet.users (id) on delete set null,
  approved_at timestamptz,
  change_note varchar(300),
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (product_id, version),
  constraint boms_output_positive check (output_quantity > 0),
  constraint boms_effective_window check (
    effective_to is null
    or effective_to >= effective_from
  )
);

comment on column manufacturing.boms.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "active": {"variant": "success", "icon": "CircleCheck"},
        "obsolete": {"variant": "destructive", "icon": "Archive"}
    }
}';

comment on table manufacturing.boms is '{
    "icon": "ListTree",
    "name": "Bills of Material",
    "description": "What each product is made of, by version.",
    "collapsible_group": "Engineering",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "version", "badges": ["status", "line_count"]},
        "tabs": ["bom_lines"]
    },
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "version", "description": "name", "date": "effective_from", "badge": "line_count"},
        {"id": "list", "name": "All Bills", "type": "list", "title": "version", "description": "name", "field_1": "status", "field_2": "line_count"},
        {"id": "gantt", "name": "Effectivity", "type": "gantt", "title": "version", "start_date": "effective_from", "end_date": "effective_to", "group": "status", "badge": "status"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "draft", "name": "In Development", "filters": [{"id": "status", "value": "draft", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["product_id", "version", "output_quantity"],
        "sections": [
            {"id": "header", "title": "Bill", "fields": ["product_id", "version", "name", "output_quantity", "status"]},
            {"id": "effectivity", "title": "Effectivity", "fields": ["effective_from", "effective_to", "change_note"]},
            {"id": "rollup", "title": "Rollup", "fields": {"read": ["line_count", "material_cost", "approved_by", "approved_at"]}},
            {"id": "notes", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ],
        "metadata": {
            "output_quantity": {"description": "How many the bill makes. A bill that yields 100 units states its component quantities per 100, not per one."}
        }
    },
    "query": {
        "sort": [{"id": "version", "desc": true}],
        "join": [{"table": "products", "on": "product_id", "columns": ["sku", "name", "product_type"]}]
    }
}';

revoke all on table manufacturing.boms
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.boms to "x-admin";

grant
select
,
  insert,
update on table manufacturing.boms to "production-planner";

grant
select
  (
    id,
    product_id,
    version,
    status,
    name,
    output_quantity,
    effective_from,
    effective_to,
    line_count,
    approved_by,
    approved_at,
    change_note,
    notes,
    created_at,
    updated_at
  ) on table manufacturing.boms to "operator",
  "inspector";

create index idx_mfg_boms_product_id on manufacturing.boms (product_id);

-- One active bill per product. "Which bill did we build this to?" has
-- to have exactly one answer.
create unique index idx_mfg_boms_one_active on manufacturing.boms (product_id)
where
  status = 'active';

alter table manufacturing.boms enable row level security;

create policy boms_select on manufacturing.boms for
select
  to authenticated using (true);

create policy boms_insert on manufacturing.boms for insert to authenticated
with
  check (true);

create policy boms_update on manufacturing.boms
for update
  to authenticated using (true)
with
  check (true);

create policy boms_delete on manufacturing.boms for delete to authenticated using (true);

create table manufacturing.bom_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  bom_id uuid not null references manufacturing.boms (id) on delete cascade,
  component_product_id uuid not null references manufacturing.products (id) on delete restrict,
  line_number integer,
  quantity_per numeric(14, 4) not null,
  scrap_percent supasheet.PERCENTAGE not null default 0,
  operation_sequence integer,
  issue_method manufacturing.issue_method not null default 'manual',
  is_optional boolean not null default false,
  reference_designator varchar(120),
  unit_cost numeric(14, 4) not null default 0,
  extended_cost numeric(14, 4) not null default 0,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  constraint bom_lines_quantity_positive check (quantity_per > 0),
  constraint bom_lines_scrap_sane check (
    scrap_percent >= 0
    and scrap_percent < 100
  ),
  unique (bom_id, component_product_id, operation_sequence)
);

comment on table manufacturing.bom_lines is '{
    "icon": "List",
    "name": "Bill Lines",
    "description": "The components, how many of each, and how much gets wasted.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "component", "title": "Component", "fields": ["bom_id", "component_product_id", "quantity_per", "scrap_percent"]},
            {"id": "consumption", "title": "Consumption", "fields": ["operation_sequence", "issue_method", "is_optional", "reference_designator"]},
            {"id": "cost", "title": "Cost", "fields": {"read": ["unit_cost", "extended_cost"]}},
            {"id": "note", "title": "Note", "fields": ["note"]}
        ],
        "metadata": {
            "scrap_percent": {"description": "Expected loss on this component. 2% means a bill needing 100 will issue 102."},
            "operation_sequence": {"description": "Which routing step consumes it. Leave blank to issue everything at the first operation."}
        }
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "products", "on": "component_product_id", "alias": "component", "columns": ["sku", "name", "product_type"]},
            {"table": "boms", "on": "bom_id", "columns": ["version", "status"]}
        ]
    }
}';

comment on column manufacturing.bom_lines.extended_cost is '{"name": "Extended", "aggregate": "sum"}';

revoke all on table manufacturing.bom_lines
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.bom_lines to "x-admin",
"production-planner";

grant
select
  (
    id,
    bom_id,
    component_product_id,
    line_number,
    quantity_per,
    scrap_percent,
    operation_sequence,
    issue_method,
    is_optional,
    reference_designator,
    note,
    created_at
  ) on table manufacturing.bom_lines to "operator",
  "inspector";

create index idx_mfg_bom_lines_bom_id on manufacturing.bom_lines (bom_id);

create index idx_mfg_bom_lines_component on manufacturing.bom_lines (component_product_id);

alter table manufacturing.bom_lines enable row level security;

create policy bom_lines_select on manufacturing.bom_lines for
select
  to authenticated using (true);

create policy bom_lines_insert on manufacturing.bom_lines for insert to authenticated
with
  check (true);

create policy bom_lines_update on manufacturing.bom_lines
for update
  to authenticated using (true)
with
  check (true);

create policy bom_lines_delete on manufacturing.bom_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Routings
----------------------------------------------------------------
create table manufacturing.routings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  product_id uuid not null references manufacturing.products (id) on delete cascade,
  version varchar(12) not null default 'A',
  status manufacturing.routing_status not null default 'draft',
  name varchar(160),
  operation_count integer not null default 0,
  total_setup_minutes numeric(12, 2) not null default 0,
  total_run_minutes_per_unit numeric(12, 4) not null default 0,
  labour_cost numeric(14, 4) not null default 0,
  overhead_cost numeric(14, 4) not null default 0,
  effective_from date not null default current_date,
  effective_to date,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (product_id, version)
);

comment on column manufacturing.routings.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "active": {"variant": "success", "icon": "CircleCheck"},
        "obsolete": {"variant": "destructive", "icon": "Archive"}
    }
}';

comment on table manufacturing.routings is '{
    "icon": "Route",
    "description": "The sequence of operations that turns components into a product.",
    "collapsible_group": "Engineering",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "version", "badges": ["status", "operation_count"]},
        "tabs": ["routing_operations"]
    },
    "views": [
        {"id": "list", "name": "All Routings", "type": "list", "title": "version", "description": "name", "field_1": "status", "field_2": "operation_count"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "version", "description": "name", "date": "effective_from", "badge": "operation_count"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["product_id", "version"],
        "sections": [
            {"id": "header", "title": "Routing", "fields": ["product_id", "version", "name", "status"]},
            {"id": "effectivity", "title": "Effectivity", "fields": ["effective_from", "effective_to"]},
            {"id": "rollup", "title": "Standard time", "fields": {"read": ["operation_count", "total_setup_minutes", "total_run_minutes_per_unit", "labour_cost", "overhead_cost"]}},
            {"id": "notes", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "version", "desc": true}],
        "join": [{"table": "products", "on": "product_id", "columns": ["sku", "name"]}]
    }
}';

revoke all on table manufacturing.routings
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.routings to "x-admin";

grant
select
,
  insert,
update on table manufacturing.routings to "production-planner";

grant
select
  (
    id,
    product_id,
    version,
    status,
    name,
    operation_count,
    total_setup_minutes,
    total_run_minutes_per_unit,
    effective_from,
    effective_to,
    notes,
    created_at,
    updated_at
  ) on table manufacturing.routings to "operator",
  "inspector";

create index idx_mfg_routings_product_id on manufacturing.routings (product_id);

create unique index idx_mfg_routings_one_active on manufacturing.routings (product_id)
where
  status = 'active';

alter table manufacturing.routings enable row level security;

create policy routings_select on manufacturing.routings for
select
  to authenticated using (true);

create policy routings_insert on manufacturing.routings for insert to authenticated
with
  check (true);

create policy routings_update on manufacturing.routings
for update
  to authenticated using (true)
with
  check (true);

create policy routings_delete on manufacturing.routings for delete to authenticated using (true);

create table manufacturing.routing_operations (
  id uuid primary key default extensions.uuid_generate_v4 (),
  routing_id uuid not null references manufacturing.routings (id) on delete cascade,
  work_center_id uuid not null references manufacturing.work_centers (id) on delete restrict,
  sequence_number integer not null,
  name varchar(160) not null,
  description supasheet.RICH_TEXT,
  setup_minutes numeric(10, 2) not null default 0,
  run_minutes_per_unit numeric(10, 4) not null default 0,
  move_minutes numeric(10, 2) not null default 0,
  is_inspection_point boolean not null default false,
  requires_certification boolean not null default false,
  work_instruction supasheet.file,
  created_at timestamptz default current_timestamp,
  unique (routing_id, sequence_number),
  constraint routing_ops_times_non_negative check (
    setup_minutes >= 0
    and run_minutes_per_unit >= 0
    and move_minutes >= 0
  ),
  constraint routing_ops_sequence_positive check (sequence_number > 0)
);

comment on table manufacturing.routing_operations is '{
    "icon": "ListOrdered",
    "name": "Routing Steps",
    "description": "One step of the routing, on one work centre, with its standard time.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "step", "title": "Step", "fields": ["routing_id", "sequence_number", "name", "work_center_id"]},
            {"id": "time", "title": "Standard time", "fields": ["setup_minutes", "run_minutes_per_unit", "move_minutes"]},
            {"id": "control", "title": "Control", "fields": ["is_inspection_point", "requires_certification", "work_instruction"]},
            {"id": "detail", "title": "Instruction", "collapsible": true, "fields": ["description"]}
        ],
        "metadata": {
            "sequence_number": {"description": "Steps run in this order and cannot overtake each other. Number in tens so a step can be inserted later."},
            "run_minutes_per_unit": {"description": "Time per unit once set up. Setup is charged once per works order, this is charged per piece."}
        }
    },
    "query": {
        "sort": [{"id": "sequence_number", "desc": false}],
        "join": [
            {"table": "work_centers", "on": "work_center_id", "columns": ["code", "name", "work_center_type"]},
            {"table": "routings", "on": "routing_id", "columns": ["version", "status"]}
        ]
    }
}';

comment on column manufacturing.routing_operations.work_instruction is '{"accept": ".pdf,.png,.jpg", "max_files": 3, "max_size": 10485760}';

revoke all on table manufacturing.routing_operations
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.routing_operations to "x-admin",
"production-planner";

grant
select
  on table manufacturing.routing_operations to "operator",
  "inspector";

create index idx_mfg_routing_ops_routing_id on manufacturing.routing_operations (routing_id);

create index idx_mfg_routing_ops_work_center_id on manufacturing.routing_operations (work_center_id);

alter table manufacturing.routing_operations enable row level security;

create policy routing_ops_select on manufacturing.routing_operations for
select
  to authenticated using (true);

create policy routing_ops_insert on manufacturing.routing_operations for insert to authenticated
with
  check (true);

create policy routing_ops_update on manufacturing.routing_operations
for update
  to authenticated using (true)
with
  check (true);

create policy routing_ops_delete on manufacturing.routing_operations for delete to authenticated using (true);

----------------------------------------------------------------
-- A bill of material cannot contain itself
--
-- This is the one rule in the schema that cannot be expressed as a
-- CHECK constraint, because it is a property of the whole graph
-- rather than of a row. It is also the one that hurts most if it is
-- missing: a cycle does not give a wrong answer, it gives a recursive
-- query that never comes back.
--
-- The depth bound in the walk is not decoration. It is what lets this
-- function terminate even if a cycle somehow already exists — during
-- a restore, say, or if a future migration loads rows with the
-- trigger disabled.
----------------------------------------------------------------
create or replace function manufacturing.bom_contains (p_product_id uuid, p_search_id uuid) returns boolean language sql stable security definer
set
  search_path = '' as $$
  with recursive explosion as (
    select bl.component_product_id as id, 1 as depth
    from manufacturing.bom_lines bl
      join manufacturing.boms b on b.id = bl.bom_id
    where b.product_id = p_product_id
      and b.status <> 'obsolete'
    union all
    select bl.component_product_id, e.depth + 1
    from explosion e
      join manufacturing.boms b on b.product_id = e.id and b.status <> 'obsolete'
      join manufacturing.bom_lines bl on bl.bom_id = b.id
    where e.depth < 25
  )
  select exists (
    select 1 from explosion where id = p_search_id
  );
$$;

comment on function manufacturing.bom_contains (uuid, uuid) is 'True when p_search_id appears anywhere beneath p_product_id in the bill of material, at any depth.';

create or replace function manufacturing.bom_lines_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_parent_id uuid;
  v_parent_sku varchar(40);
  v_component_sku varchar(40);
  v_component_type manufacturing.product_type;
  v_bom_status manufacturing.bom_status;
begin
  select b.product_id, b.status, p.sku
  into v_parent_id, v_bom_status, v_parent_sku
  from manufacturing.boms b
    join manufacturing.products p on p.id = b.product_id
  where b.id = new.bom_id;

  select sku, product_type into v_component_sku, v_component_type
  from manufacturing.products
  where id = new.component_product_id;

  -- The direct case, which is the one people actually type by accident.
  if new.component_product_id = v_parent_id then
    raise exception '% cannot be a component of itself.', v_parent_sku;
  end if;

  -- And the case that matters: A contains B contains C contains A.
  if manufacturing.bom_contains (new.component_product_id, v_parent_id) then
    raise exception 'Adding % to the bill for % would close a loop — % already contains % further down its own bill.',
      v_component_sku, v_parent_sku, v_component_sku, v_parent_sku
      using hint = 'Something in this chain should probably be a bought part or a phantom.';
  end if;

  -- A bought part has no bill, so nothing can hang beneath it.
  if v_component_type = 'buy' and exists (
    select 1 from manufacturing.boms b2
    where b2.product_id = new.component_product_id and b2.status = 'active'
  ) then
    raise exception '% is a bought part but has an active bill of material.', v_component_sku;
  end if;

  if new.line_number is null then
    select coalesce(max(line_number), 0) + 10 into new.line_number
    from manufacturing.bom_lines
    where bom_id = new.bom_id;
  end if;

  return new;
end;
$$;

create trigger trg_bom_lines_guard
before insert or update of bom_id,
component_product_id on manufacturing.bom_lines for each row
execute function manufacturing.bom_lines_guard ();

-- Explode a bill to every level, with the quantity actually needed at
-- each one. This is what a works order freezes at release, what the
-- cost roll-up walks, and what the "Where used" report reverses.
create or replace function manufacturing.explode_bom (p_product_id uuid, p_quantity numeric default 1) returns table (
  level integer,
  product_id uuid,
  sku varchar,
  name varchar,
  product_type manufacturing.product_type,
  quantity_required numeric,
  path text
) language sql stable security definer
set
  search_path = '' as $$
  with recursive explosion as (
    select 1 as level,
      bl.component_product_id as product_id,
      -- Scrap is a multiplier, not an addition: 2% scrap on a
      -- requirement of 100 means issuing 102, not 100 plus 2 later.
      (p_quantity * bl.quantity_per / b.output_quantity)
        * (1 + coalesce(bl.scrap_percent, 0)::numeric / 100) as quantity_required,
      p.sku::text as path
    from manufacturing.boms b
      join manufacturing.bom_lines bl on bl.bom_id = b.id
      join manufacturing.products p on p.id = bl.component_product_id
    where b.product_id = p_product_id
      and b.status = 'active'
    union all
    select e.level + 1,
      bl.component_product_id,
      (e.quantity_required * bl.quantity_per / b.output_quantity)
        * (1 + coalesce(bl.scrap_percent, 0)::numeric / 100),
      e.path || ' > ' || p.sku
    from explosion e
      join manufacturing.boms b on b.product_id = e.product_id and b.status = 'active'
      join manufacturing.bom_lines bl on bl.bom_id = b.id
      join manufacturing.products p on p.id = bl.component_product_id
    where e.level < 25
  )
  select e.level,
    e.product_id,
    p.sku,
    p.name,
    p.product_type,
    round(e.quantity_required, 4),
    e.path
  from explosion e
    join manufacturing.products p on p.id = e.product_id
  order by e.level, p.sku;
$$;

revoke all on function manufacturing.bom_contains (uuid, uuid)
from
  public,
  anon,
  authenticated,
  service_role;

revoke all on function manufacturing.explode_bom (uuid, numeric)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function manufacturing.bom_contains (uuid, uuid) to "x-admin",
"production-planner";

grant
execute on function manufacturing.explode_bom (uuid, numeric) to "x-admin",
"production-planner",
"operator",
"inspector";

----------------------------------------------------------------
-- Operators and certifications
----------------------------------------------------------------
create table manufacturing.operators (
  id uuid primary key default extensions.uuid_generate_v4 (),
  user_id uuid unique references supasheet.users (id) on delete set null,
  badge_number varchar(20) not null unique,
  name varchar(160) not null,
  email supasheet.EMAIL,
  shift varchar(20) not null default 'day',
  hired_on date,
  is_active boolean not null default true,
  certification_count integer not null default 0,
  hours_booked numeric(12, 2) not null default 0,
  units_produced numeric(14, 3) not null default 0,
  scrap_rate supasheet.PERCENTAGE,
  avatar supasheet.AVATAR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table manufacturing.operators is '{
    "icon": "HardHat",
    "description": "Who is on the floor, what they are signed off to run, and what they have produced.",
    "collapsible_group": "Shop Floor",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "name", "badges": ["badge_number", "shift", "certification_count"]},
        "tabs": ["operator_certifications", "production_confirmations"]
    },
    "views": [
        {"id": "gallery", "name": "Crew", "type": "gallery", "cover": "avatar", "title": "name", "description": "badge_number", "badge": "shift"},
        {"id": "kanban", "name": "By Shift", "type": "kanban", "group": "shift", "title": "name", "description": "badge_number", "date": "hired_on", "badge": "certification_count"},
        {"id": "list", "name": "All Operators", "type": "list", "title": "name", "description": "badge_number", "field_1": "hours_booked", "field_2": "scrap_rate"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "high_scrap", "name": "High Scrap", "filters": [{"id": "scrap_rate", "value": "5", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["badge_number", "name", "shift"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["badge_number", "name", "email", "avatar", "user_id"]},
            {"id": "employment", "title": "Employment", "fields": ["shift", "hired_on", "is_active"]},
            {"id": "performance", "title": "Performance", "fields": {"read": ["certification_count", "hours_booked", "units_produced", "scrap_rate"]}}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [{"table": "users", "on": "user_id", "columns": ["name", "email"]}]
    }
}';

comment on column manufacturing.operators.hours_booked is '{"name": "Hours", "aggregate": "sum"}';

revoke all on table manufacturing.operators
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.operators to "x-admin";

grant
select
,
  insert,
update on table manufacturing.operators to "production-planner";

grant
select
  on table manufacturing.operators to "operator",
  "inspector";

alter table manufacturing.operators enable row level security;

create policy operators_select on manufacturing.operators for
select
  to authenticated using (true);

create policy operators_insert on manufacturing.operators for insert to authenticated
with
  check (true);

create policy operators_update on manufacturing.operators
for update
  to authenticated using (true)
with
  check (true);

create policy operators_delete on manufacturing.operators for delete to authenticated using (true);

create table manufacturing.operator_certifications (
  id uuid primary key default extensions.uuid_generate_v4 (),
  operator_id uuid not null references manufacturing.operators (id) on delete cascade,
  work_center_id uuid not null references manufacturing.work_centers (id) on delete cascade,
  certified_on date not null default current_date,
  expires_on date,
  skill_level integer not null default 1,
  assessed_by varchar(160),
  is_expired boolean not null default false,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  unique (operator_id, work_center_id),
  constraint certifications_skill_range check (skill_level between 1 and 5),
  constraint certifications_window check (
    expires_on is null
    or expires_on >= certified_on
  )
);

comment on table manufacturing.operator_certifications is '{
    "icon": "BadgeCheck",
    "name": "Certifications",
    "description": "Which operator is signed off on which work centre, and until when.",
    "collapsible_group": "Shop Floor",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "views": [
        {"id": "list", "name": "All Certifications", "type": "list", "title": "certified_on", "description": "skill_level", "field_1": "expires_on", "field_2": "is_expired"},
        {"id": "calendar", "name": "Expiry", "type": "calendar", "title": "assessed_by", "badge": "skill_level", "start_date": "expires_on"}
    ],
    "filter_presets": [
        {"id": "expired", "name": "Expired", "filters": [{"id": "is_expired", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "certification", "title": "Certification", "fields": ["operator_id", "work_center_id", "skill_level"]},
            {"id": "validity", "title": "Validity", "fields": ["certified_on", "expires_on", "assessed_by", "note"]},
            {"id": "derived", "title": "Derived", "fields": {"read": ["is_expired"]}}
        ]
    },
    "query": {
        "sort": [{"id": "certified_on", "desc": true}],
        "join": [
            {"table": "operators", "on": "operator_id", "columns": ["badge_number", "name"]},
            {"table": "work_centers", "on": "work_center_id", "columns": ["code", "name"]}
        ]
    }
}';

revoke all on table manufacturing.operator_certifications
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.operator_certifications to "x-admin",
"production-planner";

grant
select
  on table manufacturing.operator_certifications to "operator",
  "inspector";

create index idx_mfg_certs_operator_id on manufacturing.operator_certifications (operator_id);

create index idx_mfg_certs_work_center_id on manufacturing.operator_certifications (work_center_id);

alter table manufacturing.operator_certifications enable row level security;

create policy certs_select on manufacturing.operator_certifications for
select
  to authenticated using (true);

create policy certs_insert on manufacturing.operator_certifications for insert to authenticated
with
  check (true);

create policy certs_update on manufacturing.operator_certifications
for update
  to authenticated using (true)
with
  check (true);

create policy certs_delete on manufacturing.operator_certifications for delete to authenticated using (true);

----------------------------------------------------------------
-- Who is who on the floor
--
-- STABLE SECURITY DEFINER so the RLS policies below can call them
-- without every operator needing to read the whole operator table,
-- and so the planner is resolved once per statement rather than once
-- per row.
----------------------------------------------------------------
create or replace function manufacturing.current_operator_id () returns uuid language sql stable security definer
set
  search_path = '' as $$
  select id from manufacturing.operators where user_id = auth.uid () limit 1;
$$;

create or replace function manufacturing.is_production_staff () returns boolean language sql stable
set
  search_path = '' as $$
  select pg_has_role(current_user, 'production-planner', 'member')
      or pg_has_role(current_user, 'x-admin', 'member');
$$;

-- The certifications an operator currently holds. An expired ticket
-- is not a ticket.
create or replace function manufacturing.certified_work_centers () returns setof uuid language sql stable security definer
set
  search_path = '' as $$
  select c.work_center_id
  from manufacturing.operator_certifications c
    join manufacturing.operators o on o.id = c.operator_id
  where o.user_id = auth.uid ()
    and o.is_active
    and (c.expires_on is null or c.expires_on >= current_date);
$$;

revoke all on function manufacturing.current_operator_id ()
from
  public;

revoke all on function manufacturing.certified_work_centers ()
from
  public;

grant
execute on function manufacturing.current_operator_id () to "x-admin",
"production-planner",
"operator",
"inspector";

grant
execute on function manufacturing.is_production_staff () to "x-admin",
"production-planner",
"operator",
"inspector";

grant
execute on function manufacturing.certified_work_centers () to "x-admin",
"production-planner",
"operator",
"inspector";

----------------------------------------------------------------
-- Works orders
--
-- A demand to make a quantity of something. Releasing one freezes
-- both the bill and the routing onto it, so a bill revised next month
-- does not retrospectively change what this order was built to.
----------------------------------------------------------------
create sequence if not exists manufacturing.order_number_seq;

create table manufacturing.production_orders (
  id uuid primary key default extensions.uuid_generate_v4 (),
  order_number varchar(30) not null unique default (
    'WO-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('manufacturing.order_number_seq')::text,
      5,
      '0'
    )
  ),
  product_id uuid not null references manufacturing.products (id) on delete restrict,
  bom_id uuid references manufacturing.boms (id) on delete set null,
  routing_id uuid references manufacturing.routings (id) on delete set null,
  status manufacturing.order_status not null default 'draft',
  priority manufacturing.order_priority not null default 'normal',
  quantity_ordered numeric(14, 3) not null,
  quantity_started numeric(14, 3) not null default 0,
  quantity_produced numeric(14, 3) not null default 0,
  quantity_scrapped numeric(14, 3) not null default 0,
  quantity_remaining numeric(14, 3) not null default 0,
  yield_percent supasheet.PERCENTAGE,
  planned_start date,
  planned_end date,
  actual_start timestamptz,
  actual_end timestamptz,
  released_at timestamptz,
  released_by uuid references supasheet.users (id) on delete set null,
  closed_at timestamptz,
  lot_code varchar(60),
  sales_reference varchar(60),
  operation_count integer not null default 0,
  component_count integer not null default 0,
  standard_hours numeric(12, 2) not null default 0,
  actual_hours numeric(12, 2) not null default 0,
  material_cost numeric(16, 4) not null default 0,
  labour_cost numeric(16, 4) not null default 0,
  overhead_cost numeric(16, 4) not null default 0,
  total_cost numeric(16, 4) not null default 0,
  cancelled_reason varchar(300),
  notes supasheet.RICH_TEXT,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint orders_quantity_positive check (quantity_ordered > 0),
  constraint orders_quantities_non_negative check (
    quantity_produced >= 0
    and quantity_scrapped >= 0
    and quantity_started >= 0
  ),
  constraint orders_window check (
    planned_end is null
    or planned_start is null
    or planned_end >= planned_start
  ),
  -- MATERIAL IS CONSERVED. You cannot finish more than you started,
  -- and everything started is either good or scrap.
  constraint orders_output_within_started check (
    quantity_produced + quantity_scrapped <= quantity_started
  )
);

comment on column manufacturing.production_orders.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "planned": {"variant": "info", "icon": "CalendarClock"},
        "released": {"variant": "warning", "icon": "Play"},
        "in_progress": {"variant": "warning", "icon": "Loader"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "closed": {"variant": "secondary", "icon": "Archive"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on column manufacturing.production_orders.priority is '{
    "progress": true,
    "values": {
        "low": {"variant": "secondary", "icon": "ChevronDown"},
        "normal": {"variant": "default", "icon": "Minus"},
        "high": {"variant": "warning", "icon": "ChevronUp"},
        "urgent": {"variant": "destructive", "icon": "ChevronsUp"}
    }
}';

comment on table manufacturing.production_orders is '{
    "icon": "ClipboardList",
    "name": "Works Orders",
    "description": "What the floor has been told to make, and how far it has got.",
    "collapsible_group": "Production",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "order_number", "badges": ["status", "priority", "quantity_ordered"]},
        "tabs": ["production_order_operations", "production_order_components", "production_confirmations", "nonconformances"],
        "timelines": ["production_confirmations"]
    },
    "views": [
        {"id": "kanban", "name": "Shop Floor", "type": "kanban", "group": "status", "title": "order_number", "description": "sales_reference", "date": "planned_end", "badge": "priority"},
        {"id": "gantt", "name": "Schedule", "type": "gantt", "title": "order_number", "start_date": "planned_start", "end_date": "planned_end", "group": "status", "badge": "priority"},
        {"id": "calendar", "name": "Due", "type": "calendar", "title": "order_number", "badge": "status", "start_date": "planned_end"},
        {"id": "list", "name": "All Orders", "type": "list", "title": "order_number", "description": "status", "field_1": "quantity_ordered", "field_2": "planned_end"}
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["released", "in_progress"], "operator": "in"}]},
        {"id": "late", "name": "Late", "filters": [{"id": "planned_end", "value": "today", "operator": "lt"}]},
        {"id": "urgent", "name": "Urgent", "filters": [{"id": "priority", "value": "urgent", "operator": "eq"}]},
        {"id": "scrapped", "name": "With Scrap", "filters": [{"id": "quantity_scrapped", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["product_id", "quantity_ordered", "planned_end", "priority"],
        "sections": [
            {"id": "order", "title": "Order", "fields": {"create": ["product_id", "quantity_ordered", "priority", "planned_start", "planned_end", "sales_reference"], "update": ["quantity_ordered", "priority", "planned_start", "planned_end", "sales_reference", "status"], "read": ["order_number", "product_id", "quantity_ordered", "priority", "status", "sales_reference"]}},
            {"id": "frozen", "title": "Built to", "fields": {"read": ["bom_id", "routing_id", "lot_code"]}},
            {"id": "progress", "title": "Progress", "fields": {"read": ["quantity_started", "quantity_produced", "quantity_scrapped", "quantity_remaining", "yield_percent", "operation_count", "component_count"]}},
            {"id": "time", "title": "Time and cost", "fields": {"read": ["standard_hours", "actual_hours", "material_cost", "labour_cost", "overhead_cost", "total_cost"]}},
            {"id": "trail", "title": "Trail", "fields": {"read": ["actual_start", "actual_end", "released_at", "released_by", "closed_at"]}},
            {"id": "cancel", "title": "Cancellation", "fields": ["cancelled_reason"]},
            {"id": "notes", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ],
        "behavior": {
            "cancelled_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "cancelled"}],
                "required": [{"id": "status", "operator": "eq", "value": "cancelled"}]
            }
        },
        "lookups": {
            "product_id": {"filter": [{"source_column": "status", "target_column": "status"}]}
        }
    },
    "query": {
        "sort": [{"id": "planned_end", "desc": false}],
        "join": [
            {"table": "products", "on": "product_id", "columns": ["sku", "name", "uom"]},
            {"table": "boms", "on": "bom_id", "columns": ["version"]},
            {"table": "routings", "on": "routing_id", "columns": ["version"]}
        ]
    }
}';

comment on column manufacturing.production_orders.quantity_ordered is '{"name": "Ordered", "aggregate": "sum"}';

comment on column manufacturing.production_orders.quantity_produced is '{"name": "Good", "aggregate": "sum"}';

comment on column manufacturing.production_orders.quantity_scrapped is '{"name": "Scrap", "aggregate": "sum"}';

revoke all on table manufacturing.production_orders
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.production_orders to "x-admin";

grant
select
,
  insert,
update on table manufacturing.production_orders to "production-planner";

grant
select
  (
    id,
    order_number,
    product_id,
    bom_id,
    routing_id,
    status,
    priority,
    quantity_ordered,
    quantity_started,
    quantity_produced,
    quantity_scrapped,
    quantity_remaining,
    yield_percent,
    planned_start,
    planned_end,
    actual_start,
    actual_end,
    released_at,
    lot_code,
    sales_reference,
    operation_count,
    component_count,
    standard_hours,
    actual_hours,
    notes,
    created_at,
    updated_at
  ) on table manufacturing.production_orders to "operator",
  "inspector";

grant
update on table manufacturing.production_orders to "operator";

revoke all on sequence manufacturing.order_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence manufacturing.order_number_seq to "x-admin",
"production-planner";

create index idx_mfg_orders_product_id on manufacturing.production_orders (product_id);

create index idx_mfg_orders_status on manufacturing.production_orders (status);

create index idx_mfg_orders_open on manufacturing.production_orders (planned_end)
where
  status in ('released', 'in_progress');

alter table manufacturing.production_orders enable row level security;

create policy orders_select on manufacturing.production_orders for
select
  to authenticated using (true);

create policy orders_insert on manufacturing.production_orders for insert to authenticated
with
  check (true);

create policy orders_update on manufacturing.production_orders
for update
  to authenticated using (true)
with
  check (true);

create policy orders_delete on manufacturing.production_orders for delete to authenticated using (true);

----------------------------------------------------------------
-- The frozen bill: what this order will consume
----------------------------------------------------------------
create table manufacturing.production_order_components (
  id uuid primary key default extensions.uuid_generate_v4 (),
  production_order_id uuid not null references manufacturing.production_orders (id) on delete cascade,
  component_product_id uuid not null references manufacturing.products (id) on delete restrict,
  operation_sequence integer,
  line_number integer,
  quantity_required numeric(14, 4) not null,
  quantity_issued numeric(14, 4) not null default 0,
  quantity_consumed numeric(14, 4) not null default 0,
  quantity_outstanding numeric(14, 4) not null default 0,
  unit_cost numeric(14, 4) not null default 0,
  extended_cost numeric(16, 4) not null default 0,
  issue_method manufacturing.issue_method not null default 'manual',
  is_fully_issued boolean not null default false,
  created_at timestamptz default current_timestamp,
  constraint order_components_required_positive check (quantity_required > 0),
  constraint order_components_issued_non_negative check (quantity_issued >= 0)
);

comment on table manufacturing.production_order_components is '{
    "icon": "Boxes",
    "name": "Order Components",
    "description": "The bill as it stood when this order was released, and how much of it has gone out.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "component", "title": "Component", "fields": {"read": ["production_order_id", "component_product_id", "operation_sequence", "quantity_required", "issue_method"]}},
            {"id": "issue", "title": "Issued", "fields": ["quantity_issued"]},
            {"id": "derived", "title": "Derived", "fields": {"read": ["quantity_consumed", "quantity_outstanding", "unit_cost", "extended_cost", "is_fully_issued"]}}
        ]
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "products", "on": "component_product_id", "alias": "component", "columns": ["sku", "name", "product_type"]},
            {"table": "production_orders", "on": "production_order_id", "columns": ["order_number", "status"]}
        ]
    }
}';

comment on column manufacturing.production_order_components.quantity_required is '{"name": "Required", "aggregate": "sum"}';

revoke all on table manufacturing.production_order_components
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.production_order_components to "x-admin",
"production-planner";

grant
select
  (
    id,
    production_order_id,
    component_product_id,
    operation_sequence,
    line_number,
    quantity_required,
    quantity_issued,
    quantity_consumed,
    quantity_outstanding,
    issue_method,
    is_fully_issued,
    created_at
  ) on table manufacturing.production_order_components to "operator",
  "inspector";

grant
update (quantity_issued) on table manufacturing.production_order_components to "operator";

create index idx_mfg_order_components_order on manufacturing.production_order_components (production_order_id);

create index idx_mfg_order_components_product on manufacturing.production_order_components (component_product_id);

alter table manufacturing.production_order_components enable row level security;

create policy order_components_select on manufacturing.production_order_components for
select
  to authenticated using (true);

create policy order_components_insert on manufacturing.production_order_components for insert to authenticated
with
  check (true);

create policy order_components_update on manufacturing.production_order_components
for update
  to authenticated using (true)
with
  check (true);

create policy order_components_delete on manufacturing.production_order_components for delete to authenticated using (true);

----------------------------------------------------------------
-- The frozen routing: the steps this order must go through
----------------------------------------------------------------
create table manufacturing.production_order_operations (
  id uuid primary key default extensions.uuid_generate_v4 (),
  production_order_id uuid not null references manufacturing.production_orders (id) on delete cascade,
  work_center_id uuid not null references manufacturing.work_centers (id) on delete restrict,
  machine_id uuid references manufacturing.machines (id) on delete set null,
  sequence_number integer not null,
  name varchar(160) not null,
  status manufacturing.operation_status not null default 'pending',
  assigned_operator_id uuid references manufacturing.operators (id) on delete set null,
  planned_setup_minutes numeric(10, 2) not null default 0,
  planned_run_minutes numeric(12, 2) not null default 0,
  actual_minutes numeric(12, 2) not null default 0,
  quantity_completed numeric(14, 3) not null default 0,
  quantity_scrapped numeric(14, 3) not null default 0,
  scheduled_start timestamptz,
  scheduled_end timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  is_inspection_point boolean not null default false,
  efficiency supasheet.PERCENTAGE,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (production_order_id, sequence_number),
  constraint order_ops_quantities_non_negative check (
    quantity_completed >= 0
    and quantity_scrapped >= 0
  )
);

comment on column manufacturing.production_order_operations.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "secondary", "icon": "Clock"},
        "setup": {"variant": "info", "icon": "Settings"},
        "running": {"variant": "warning", "icon": "Play"},
        "paused": {"variant": "warning", "icon": "Pause"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "skipped": {"variant": "secondary", "icon": "SkipForward"}
    }
}';

comment on table manufacturing.production_order_operations is '{
    "icon": "ListOrdered",
    "name": "Order Operations",
    "description": "The steps this order goes through, in order, and where each one has got to.",
    "collapsible_group": "Production",
    "display": "block",
    "primary_view": "kanban",
    "detail": {"header": {"title": "name", "badges": ["status", "sequence_number"]}, "tabs": ["production_confirmations"]},
    "views": [
        {"id": "kanban", "name": "Operation Board", "type": "kanban", "group": "status", "title": "name", "description": "note", "date": "scheduled_start", "badge": "sequence_number"},
        {"id": "gantt", "name": "Machine Schedule", "type": "gantt", "title": "name", "start_date": "scheduled_start", "end_date": "scheduled_end", "group": "status", "badge": "sequence_number"},
        {"id": "calendar", "name": "Scheduled", "type": "calendar", "title": "name", "badge": "status", "start_date": "scheduled_start"},
        {"id": "list", "name": "All Operations", "type": "list", "title": "name", "description": "status", "field_1": "quantity_completed", "field_2": "efficiency"}
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["pending", "setup", "running", "paused"], "operator": "in"}]},
        {"id": "running", "name": "Running Now", "filters": [{"id": "status", "value": "running", "operator": "eq"}]},
        {"id": "inspection", "name": "Inspection Points", "filters": [{"id": "is_inspection_point", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "step", "title": "Step", "fields": {"read": ["production_order_id", "sequence_number", "name", "work_center_id", "is_inspection_point"]}},
            {"id": "assignment", "title": "Assignment", "fields": ["machine_id", "assigned_operator_id", "status", "note"]},
            {"id": "schedule", "title": "Schedule", "fields": ["scheduled_start", "scheduled_end"]},
            {"id": "result", "title": "Result", "fields": {"read": ["planned_setup_minutes", "planned_run_minutes", "actual_minutes", "quantity_completed", "quantity_scrapped", "efficiency", "started_at", "completed_at"]}}
        ],
        "lookups": {
            "machine_id": {"filter": [{"source_column": "work_center_id", "target_column": "work_center_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "sequence_number", "desc": false}],
        "join": [
            {"table": "production_orders", "on": "production_order_id", "columns": ["order_number", "status", "priority"]},
            {"table": "work_centers", "on": "work_center_id", "columns": ["code", "name"]},
            {"table": "machines", "on": "machine_id", "columns": ["code", "name"]},
            {"table": "operators", "on": "assigned_operator_id", "alias": "operator", "columns": ["badge_number", "name"]}
        ]
    }
}';

revoke all on table manufacturing.production_order_operations
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.production_order_operations to "x-admin",
"production-planner";

grant
select
,
update on table manufacturing.production_order_operations to "operator";

grant
select
  on table manufacturing.production_order_operations to "inspector";

create index idx_mfg_order_ops_order on manufacturing.production_order_operations (production_order_id);

create index idx_mfg_order_ops_work_center on manufacturing.production_order_operations (work_center_id);

create index idx_mfg_order_ops_status on manufacturing.production_order_operations (status);

create index idx_mfg_order_ops_open on manufacturing.production_order_operations (work_center_id, scheduled_start)
where
  status in ('pending', 'setup', 'running', 'paused');

alter table manufacturing.production_order_operations enable row level security;

-- An operator sees the work at the centres they are certified on.
-- Planning and management see the whole floor.
create policy order_ops_select on manufacturing.production_order_operations for
select
  to authenticated using (
    manufacturing.is_production_staff ()
    or pg_has_role(current_user, 'inspector', 'member')
    or work_center_id in (
      select
        manufacturing.certified_work_centers ()
    )
  );

create policy order_ops_insert on manufacturing.production_order_operations for insert to authenticated
with
  check (true);

create policy order_ops_update on manufacturing.production_order_operations
for update
  to authenticated using (
    manufacturing.is_production_staff ()
    or work_center_id in (
      select
        manufacturing.certified_work_centers ()
    )
  )
with
  check (true);

create policy order_ops_delete on manufacturing.production_order_operations for delete to authenticated using (true);

----------------------------------------------------------------
-- Production confirmations
--
-- What the floor actually declared: how many good, how many scrap,
-- how long it took. Append-only in spirit — a wrong confirmation is
-- corrected by a negative one, not by editing history.
----------------------------------------------------------------
create sequence if not exists manufacturing.confirmation_number_seq;

create table manufacturing.production_confirmations (
  id uuid primary key default extensions.uuid_generate_v4 (),
  confirmation_number varchar(30) not null unique default (
    'CNF-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('manufacturing.confirmation_number_seq')::text,
      6,
      '0'
    )
  ),
  production_order_id uuid not null references manufacturing.production_orders (id) on delete cascade,
  operation_id uuid references manufacturing.production_order_operations (id) on delete cascade,
  operator_id uuid references manufacturing.operators (id) on delete set null,
  machine_id uuid references manufacturing.machines (id) on delete set null,
  confirmed_at timestamptz not null default current_timestamp,
  quantity_good numeric(14, 3) not null default 0,
  quantity_scrap numeric(14, 3) not null default 0,
  setup_minutes numeric(10, 2) not null default 0,
  run_minutes numeric(10, 2) not null default 0,
  total_minutes numeric(10, 2) not null default 0,
  is_final boolean not null default false,
  scrap_reason varchar(200),
  note varchar(300),
  created_at timestamptz default current_timestamp,
  constraint confirmations_minutes_non_negative check (
    setup_minutes >= 0
    and run_minutes >= 0
  ),
  -- A confirmation that declares nothing and books no time is not a
  -- confirmation.
  constraint confirmations_not_empty check (
    quantity_good <> 0
    or quantity_scrap <> 0
    or setup_minutes > 0
    or run_minutes > 0
  ),
  constraint confirmations_scrap_needs_reason check (
    quantity_scrap <= 0
    or scrap_reason is not null
  )
);

comment on table manufacturing.production_confirmations is '{
    "icon": "ClipboardCheck",
    "name": "Confirmations",
    "description": "What the floor declared: good, scrap and time booked.",
    "collapsible_group": "Production",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "confirmation_number", "badges": ["quantity_good", "quantity_scrap"]}},
    "views": [
        {"id": "list", "name": "All Confirmations", "type": "list", "title": "confirmation_number", "description": "note", "field_1": "quantity_good", "field_2": "confirmed_at"},
        {"id": "calendar", "name": "By Day", "type": "calendar", "title": "confirmation_number", "badge": "quantity_good", "start_date": "confirmed_at", "read_only": true},
        {"id": "kanban", "name": "By Operator", "type": "kanban", "group": "operator_id", "title": "confirmation_number", "description": "scrap_reason", "date": "confirmed_at", "badge": "quantity_good", "read_only": true}
    ],
    "filter_presets": [
        {"id": "scrap", "name": "With Scrap", "filters": [{"id": "quantity_scrap", "value": "0", "operator": "gt"}]},
        {"id": "final", "name": "Final", "filters": [{"id": "is_final", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["production_order_id", "operation_id", "quantity_good", "quantity_scrap"],
        "sections": [
            {"id": "what", "title": "Declared", "fields": ["production_order_id", "operation_id", "quantity_good", "quantity_scrap", "scrap_reason", "is_final"]},
            {"id": "time", "title": "Time booked", "fields": ["setup_minutes", "run_minutes"]},
            {"id": "who", "title": "Who and where", "fields": ["operator_id", "machine_id", "confirmed_at", "note"]},
            {"id": "derived", "title": "Derived", "fields": {"read": ["total_minutes"]}}
        ],
        "behavior": {
            "scrap_reason": {"required": [{"id": "quantity_scrap", "operator": "gt", "value": "0"}]}
        }
    },
    "query": {
        "sort": [{"id": "confirmed_at", "desc": true}],
        "join": [
            {"table": "production_orders", "on": "production_order_id", "columns": ["order_number", "status"]},
            {"table": "production_order_operations", "on": "operation_id", "alias": "operation", "columns": ["sequence_number", "name"]},
            {"table": "operators", "on": "operator_id", "columns": ["badge_number", "name"]}
        ]
    }
}';

comment on column manufacturing.production_confirmations.quantity_good is '{"name": "Good", "aggregate": "sum"}';

comment on column manufacturing.production_confirmations.quantity_scrap is '{"name": "Scrap", "aggregate": "sum"}';

revoke all on table manufacturing.production_confirmations
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.production_confirmations to "x-admin";

grant
select
,
  insert on table manufacturing.production_confirmations to "operator";

grant
select
  on table manufacturing.production_confirmations to "production-planner",
  "inspector";

revoke all on sequence manufacturing.confirmation_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence manufacturing.confirmation_number_seq to "x-admin",
"operator";

create index idx_mfg_confirmations_order on manufacturing.production_confirmations (production_order_id);

create index idx_mfg_confirmations_operation on manufacturing.production_confirmations (operation_id);

create index idx_mfg_confirmations_operator on manufacturing.production_confirmations (operator_id);

create index idx_mfg_confirmations_when on manufacturing.production_confirmations (confirmed_at desc);

alter table manufacturing.production_confirmations enable row level security;

create policy confirmations_select on manufacturing.production_confirmations for
select
  to authenticated using (true);

create policy confirmations_insert on manufacturing.production_confirmations for insert to authenticated
with
  check (true);

create policy confirmations_update on manufacturing.production_confirmations
for update
  to authenticated using (true)
with
  check (true);

create policy confirmations_delete on manufacturing.production_confirmations for delete to authenticated using (true);

----------------------------------------------------------------
-- Downtime and maintenance
----------------------------------------------------------------
create table manufacturing.downtime_events (
  id uuid primary key default extensions.uuid_generate_v4 (),
  machine_id uuid not null references manufacturing.machines (id) on delete cascade,
  work_center_id uuid references manufacturing.work_centers (id) on delete set null,
  production_order_id uuid references manufacturing.production_orders (id) on delete set null,
  reason manufacturing.downtime_reason not null default 'breakdown',
  started_at timestamptz not null default current_timestamp,
  ended_at timestamptz,
  duration_minutes numeric(10, 2),
  reported_by uuid references manufacturing.operators (id) on delete set null,
  description varchar(300),
  resolution supasheet.RICH_TEXT,
  is_open boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint downtime_window check (
    ended_at is null
    or ended_at >= started_at
  )
);

comment on column manufacturing.downtime_events.reason is '{
    "progress": false,
    "values": {
        "breakdown": {"variant": "destructive", "icon": "TriangleAlert"},
        "changeover": {"variant": "info", "icon": "Repeat"},
        "material_shortage": {"variant": "warning", "icon": "PackageX"},
        "no_operator": {"variant": "warning", "icon": "UserX"},
        "quality_hold": {"variant": "destructive", "icon": "ShieldAlert"},
        "planned_maintenance": {"variant": "secondary", "icon": "Wrench"},
        "tooling": {"variant": "warning", "icon": "Hammer"}
    }
}';

comment on table manufacturing.downtime_events is '{
    "icon": "TriangleAlert",
    "name": "Downtime",
    "description": "Every minute a machine was not able to run, and why.",
    "collapsible_group": "Shop Floor",
    "display": "block",
    "primary_view": "kanban",
    "detail": {"header": {"title": "description", "badges": ["reason", "duration_minutes"]}},
    "views": [
        {"id": "kanban", "name": "By Reason", "type": "kanban", "group": "reason", "title": "description", "description": "resolution", "date": "started_at", "badge": "duration_minutes"},
        {"id": "calendar", "name": "By Day", "type": "calendar", "title": "description", "badge": "reason", "start_date": "started_at"},
        {"id": "gantt", "name": "Timeline", "type": "gantt", "title": "description", "start_date": "started_at", "end_date": "ended_at", "group": "reason", "badge": "reason"},
        {"id": "list", "name": "All Events", "type": "list", "title": "description", "description": "reason", "field_1": "duration_minutes", "field_2": "started_at"}
    ],
    "filter_presets": [
        {"id": "open", "name": "Still Down", "filters": [{"id": "is_open", "value": "true", "operator": "eq"}]},
        {"id": "breakdowns", "name": "Breakdowns", "filters": [{"id": "reason", "value": "breakdown", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["machine_id", "reason", "description"],
        "sections": [
            {"id": "event", "title": "Event", "fields": ["machine_id", "reason", "description", "production_order_id"]},
            {"id": "window", "title": "Window", "fields": ["started_at", "ended_at", "reported_by"]},
            {"id": "resolution", "title": "Resolution", "fields": ["resolution"]},
            {"id": "derived", "title": "Derived", "fields": {"read": ["duration_minutes", "is_open", "work_center_id"]}}
        ]
    },
    "query": {
        "sort": [{"id": "started_at", "desc": true}],
        "join": [
            {"table": "machines", "on": "machine_id", "columns": ["code", "name"]},
            {"table": "production_orders", "on": "production_order_id", "columns": ["order_number"]}
        ]
    }
}';

comment on column manufacturing.downtime_events.duration_minutes is '{"name": "Minutes", "aggregate": "sum"}';

revoke all on table manufacturing.downtime_events
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.downtime_events to "x-admin";

grant
select
,
  insert,
update on table manufacturing.downtime_events to "operator";

grant
select
  on table manufacturing.downtime_events to "production-planner",
  "inspector";

create index idx_mfg_downtime_machine on manufacturing.downtime_events (machine_id);

create index idx_mfg_downtime_open on manufacturing.downtime_events (machine_id)
where
  is_open;

alter table manufacturing.downtime_events enable row level security;

create policy downtime_select on manufacturing.downtime_events for
select
  to authenticated using (true);

create policy downtime_insert on manufacturing.downtime_events for insert to authenticated
with
  check (true);

create policy downtime_update on manufacturing.downtime_events
for update
  to authenticated using (true)
with
  check (true);

create policy downtime_delete on manufacturing.downtime_events for delete to authenticated using (true);

create sequence if not exists manufacturing.maintenance_number_seq;

create table manufacturing.maintenance_orders (
  id uuid primary key default extensions.uuid_generate_v4 (),
  maintenance_number varchar(30) not null unique default (
    'MNT-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('manufacturing.maintenance_number_seq')::text,
      5,
      '0'
    )
  ),
  machine_id uuid not null references manufacturing.machines (id) on delete cascade,
  maintenance_type manufacturing.maintenance_type not null default 'preventive',
  status manufacturing.maintenance_status not null default 'scheduled',
  scheduled_for date not null default current_date,
  started_at timestamptz,
  completed_at timestamptz,
  duration_minutes numeric(10, 2),
  assigned_to varchar(160),
  description varchar(300) not null,
  work_done supasheet.RICH_TEXT,
  parts_used varchar(300),
  cost numeric(14, 2) not null default 0,
  is_overdue boolean not null default false,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column manufacturing.maintenance_orders.status is '{
    "progress": true,
    "values": {
        "scheduled": {"variant": "info", "icon": "CalendarClock"},
        "in_progress": {"variant": "warning", "icon": "Wrench"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "overdue": {"variant": "destructive", "icon": "TriangleAlert"},
        "cancelled": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table manufacturing.maintenance_orders is '{
    "icon": "Wrench",
    "name": "Maintenance",
    "description": "Planned and breakdown work on the machines.",
    "collapsible_group": "Shop Floor",
    "display": "block",
    "primary_view": "kanban",
    "detail": {"header": {"title": "maintenance_number", "badges": ["status", "maintenance_type"]}},
    "views": [
        {"id": "kanban", "name": "Maintenance Board", "type": "kanban", "group": "status", "title": "description", "description": "assigned_to", "date": "scheduled_for", "badge": "maintenance_type"},
        {"id": "calendar", "name": "Schedule", "type": "calendar", "title": "description", "badge": "maintenance_type", "start_date": "scheduled_for"},
        {"id": "list", "name": "All Work", "type": "list", "title": "maintenance_number", "description": "description", "field_1": "status", "field_2": "scheduled_for"}
    ],
    "filter_presets": [
        {"id": "due", "name": "Due", "filters": [{"id": "status", "value": ["scheduled", "overdue"], "operator": "in"}]},
        {"id": "overdue", "name": "Overdue", "filters": [{"id": "is_overdue", "value": "true", "operator": "eq"}]},
        {"id": "breakdowns", "name": "Corrective", "filters": [{"id": "maintenance_type", "value": "corrective", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["machine_id", "maintenance_type", "description", "scheduled_for"],
        "sections": [
            {"id": "work", "title": "Work", "fields": ["machine_id", "maintenance_type", "description", "scheduled_for", "assigned_to"]},
            {"id": "state", "title": "State", "fields": ["status", "started_at", "completed_at"]},
            {"id": "outcome", "title": "Outcome", "fields": ["work_done", "parts_used", "cost"]},
            {"id": "derived", "title": "Derived", "fields": {"read": ["duration_minutes", "is_overdue"]}}
        ]
    },
    "query": {
        "sort": [{"id": "scheduled_for", "desc": false}],
        "join": [{"table": "machines", "on": "machine_id", "columns": ["code", "name", "status"]}]
    }
}';

comment on column manufacturing.maintenance_orders.cost is '{"aggregate": "sum"}';

revoke all on table manufacturing.maintenance_orders
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.maintenance_orders to "x-admin";

grant
select
,
  insert,
update on table manufacturing.maintenance_orders to "production-planner",
"operator";

grant
select
  on table manufacturing.maintenance_orders to "inspector";

revoke all on sequence manufacturing.maintenance_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence manufacturing.maintenance_number_seq to "x-admin",
"production-planner",
"operator";

create index idx_mfg_maintenance_machine on manufacturing.maintenance_orders (machine_id);

create index idx_mfg_maintenance_status on manufacturing.maintenance_orders (status);

alter table manufacturing.maintenance_orders enable row level security;

create policy maintenance_select on manufacturing.maintenance_orders for
select
  to authenticated using (true);

create policy maintenance_insert on manufacturing.maintenance_orders for insert to authenticated
with
  check (true);

create policy maintenance_update on manufacturing.maintenance_orders
for update
  to authenticated using (true)
with
  check (true);

create policy maintenance_delete on manufacturing.maintenance_orders for delete to authenticated using (true);

----------------------------------------------------------------
-- Quality
----------------------------------------------------------------
create table manufacturing.defect_codes (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(120) not null,
  description varchar(300),
  severity manufacturing.defect_severity not null default 'minor',
  category varchar(60),
  occurrence_count integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column manufacturing.defect_codes.severity is '{
    "progress": true,
    "values": {
        "minor": {"variant": "secondary", "icon": "Info"},
        "major": {"variant": "warning", "icon": "TriangleAlert"},
        "critical": {"variant": "destructive", "icon": "OctagonAlert"}
    }
}';

comment on table manufacturing.defect_codes is '{
    "icon": "Bug",
    "name": "Defect Codes",
    "description": "The agreed vocabulary for what goes wrong.",
    "collapsible_group": "Quality",
    "display": "block",
    "inline_form": true,
    "primary_view": "kanban",
    "views": [
        {"id": "kanban", "name": "By Severity", "type": "kanban", "group": "severity", "title": "name", "description": "category", "date": "created_at", "badge": "occurrence_count"},
        {"id": "list", "name": "All Codes", "type": "list", "title": "code", "description": "name", "field_1": "severity", "field_2": "occurrence_count"}
    ],
    "filter_presets": [
        {"id": "critical", "name": "Critical", "filters": [{"id": "severity", "value": "critical", "operator": "eq"}]},
        {"id": "common", "name": "Most Common", "filters": [{"id": "occurrence_count", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "severity"],
        "sections": [
            {"id": "code", "title": "Code", "fields": ["code", "name", "description", "category", "severity", "is_active"]},
            {"id": "rollup", "title": "Rollup", "fields": {"read": ["occurrence_count"]}}
        ]
    },
    "query": {"sort": [{"id": "code", "desc": false}]}
}';

revoke all on table manufacturing.defect_codes
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.defect_codes to "x-admin",
"inspector";

grant
select
  on table manufacturing.defect_codes to "production-planner",
  "operator";

alter table manufacturing.defect_codes enable row level security;

create policy defect_codes_select on manufacturing.defect_codes for
select
  to authenticated using (true);

create policy defect_codes_insert on manufacturing.defect_codes for insert to authenticated
with
  check (true);

create policy defect_codes_update on manufacturing.defect_codes
for update
  to authenticated using (true)
with
  check (true);

create policy defect_codes_delete on manufacturing.defect_codes for delete to authenticated using (true);

create table manufacturing.quality_characteristics (
  id uuid primary key default extensions.uuid_generate_v4 (),
  product_id uuid not null references manufacturing.products (id) on delete cascade,
  operation_sequence integer,
  code varchar(24) not null,
  name varchar(160) not null,
  characteristic_type manufacturing.characteristic_type not null default 'dimensional',
  unit varchar(16),
  nominal_value numeric(14, 4),
  tolerance_lower numeric(14, 4),
  tolerance_upper numeric(14, 4),
  method varchar(160),
  sample_size integer not null default 1,
  is_critical boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (product_id, code),
  constraint characteristics_tolerance_order check (
    tolerance_lower is null
    or tolerance_upper is null
    or tolerance_upper >= tolerance_lower
  ),
  constraint characteristics_sample_positive check (sample_size > 0)
);

comment on table manufacturing.quality_characteristics is '{
    "icon": "Ruler",
    "name": "Inspection Plan",
    "description": "What gets measured on each product, and what counts as in specification.",
    "collapsible_group": "Quality",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "views": [
        {"id": "list", "name": "All Characteristics", "type": "list", "title": "name", "description": "code", "field_1": "characteristic_type", "field_2": "nominal_value"},
        {"id": "kanban", "name": "By Type", "type": "kanban", "group": "characteristic_type", "title": "name", "description": "method", "date": "created_at", "badge": "is_critical"}
    ],
    "filter_presets": [
        {"id": "critical", "name": "Critical", "filters": [{"id": "is_critical", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["product_id", "code", "name", "characteristic_type"],
        "sections": [
            {"id": "what", "title": "Characteristic", "fields": ["product_id", "code", "name", "characteristic_type", "operation_sequence"]},
            {"id": "spec", "title": "Specification", "fields": ["nominal_value", "tolerance_lower", "tolerance_upper", "unit"]},
            {"id": "how", "title": "Method", "fields": ["method", "sample_size", "is_critical", "is_active"]}
        ],
        "behavior": {
            "nominal_value": {"visible": [{"id": "characteristic_type", "operator": "in", "value": ["dimensional", "weight", "material"]}]},
            "tolerance_lower": {"visible": [{"id": "characteristic_type", "operator": "in", "value": ["dimensional", "weight", "material"]}]},
            "tolerance_upper": {"visible": [{"id": "characteristic_type", "operator": "in", "value": ["dimensional", "weight", "material"]}]}
        }
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "products", "on": "product_id", "columns": ["sku", "name"]}]
    }
}';

revoke all on table manufacturing.quality_characteristics
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.quality_characteristics to "x-admin",
"inspector";

grant
select
,
  insert,
update on table manufacturing.quality_characteristics to "production-planner";

grant
select
  on table manufacturing.quality_characteristics to "operator";

create index idx_mfg_characteristics_product on manufacturing.quality_characteristics (product_id);

alter table manufacturing.quality_characteristics enable row level security;

create policy characteristics_select on manufacturing.quality_characteristics for
select
  to authenticated using (true);

create policy characteristics_insert on manufacturing.quality_characteristics for insert to authenticated
with
  check (true);

create policy characteristics_update on manufacturing.quality_characteristics
for update
  to authenticated using (true)
with
  check (true);

create policy characteristics_delete on manufacturing.quality_characteristics for delete to authenticated using (true);

create sequence if not exists manufacturing.inspection_number_seq;

create table manufacturing.inspections (
  id uuid primary key default extensions.uuid_generate_v4 (),
  inspection_number varchar(30) not null unique default (
    'QC-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('manufacturing.inspection_number_seq')::text,
      5,
      '0'
    )
  ),
  production_order_id uuid not null references manufacturing.production_orders (id) on delete cascade,
  operation_id uuid references manufacturing.production_order_operations (id) on delete set null,
  product_id uuid references manufacturing.products (id) on delete set null,
  result manufacturing.inspection_result not null default 'pending',
  inspected_at timestamptz not null default current_timestamp,
  inspector_name varchar(160),
  inspector_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  quantity_inspected numeric(14, 3) not null default 0,
  quantity_passed numeric(14, 3) not null default 0,
  quantity_failed numeric(14, 3) not null default 0,
  characteristic_count integer not null default 0,
  failed_count integer not null default 0,
  pass_rate supasheet.PERCENTAGE,
  certificate supasheet.file,
  note supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint inspections_quantities_non_negative check (
    quantity_inspected >= 0
    and quantity_passed >= 0
    and quantity_failed >= 0
  )
);

comment on column manufacturing.inspections.result is '{
    "progress": true,
    "values": {
        "pending": {"variant": "secondary", "icon": "Clock"},
        "pass": {"variant": "success", "icon": "CircleCheck"},
        "conditional_pass": {"variant": "warning", "icon": "CircleAlert"},
        "fail": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on table manufacturing.inspections is '{
    "icon": "ScanSearch",
    "description": "Checks carried out against a works order, and what they found.",
    "collapsible_group": "Quality",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "inspection_number", "badges": ["result", "pass_rate"]},
        "tabs": ["inspection_results", "nonconformances"]
    },
    "views": [
        {"id": "kanban", "name": "By Result", "type": "kanban", "group": "result", "title": "inspection_number", "description": "inspector_name", "date": "inspected_at", "badge": "pass_rate"},
        {"id": "calendar", "name": "By Day", "type": "calendar", "title": "inspection_number", "badge": "result", "start_date": "inspected_at"},
        {"id": "list", "name": "All Inspections", "type": "list", "title": "inspection_number", "description": "inspector_name", "field_1": "result", "field_2": "pass_rate"}
    ],
    "filter_presets": [
        {"id": "failed", "name": "Failed", "filters": [{"id": "result", "value": "fail", "operator": "eq"}]},
        {"id": "pending", "name": "Awaiting Result", "filters": [{"id": "result", "value": "pending", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["production_order_id", "quantity_inspected"],
        "sections": [
            {"id": "what", "title": "Inspection", "fields": ["production_order_id", "operation_id", "product_id", "inspected_at"]},
            {"id": "result", "title": "Result", "fields": ["result", "quantity_inspected", "quantity_passed", "quantity_failed", "certificate"]},
            {"id": "who", "title": "Inspector", "fields": ["inspector_name", "inspector_id"]},
            {"id": "derived", "title": "Derived", "fields": {"read": ["characteristic_count", "failed_count", "pass_rate"]}},
            {"id": "note", "title": "Note", "collapsible": true, "fields": ["note"]}
        ]
    },
    "query": {
        "sort": [{"id": "inspected_at", "desc": true}],
        "join": [
            {"table": "production_orders", "on": "production_order_id", "columns": ["order_number", "status"]},
            {"table": "products", "on": "product_id", "columns": ["sku", "name"]}
        ]
    }
}';

comment on column manufacturing.inspections.certificate is '{"accept": ".pdf,.png,.jpg", "max_files": 3, "max_size": 5242880}';

revoke all on table manufacturing.inspections
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.inspections to "x-admin",
"inspector";

grant
select
  on table manufacturing.inspections to "production-planner",
  "operator";

revoke all on sequence manufacturing.inspection_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence manufacturing.inspection_number_seq to "x-admin",
"inspector";

create index idx_mfg_inspections_order on manufacturing.inspections (production_order_id);

create index idx_mfg_inspections_result on manufacturing.inspections (result);

alter table manufacturing.inspections enable row level security;

create policy inspections_select on manufacturing.inspections for
select
  to authenticated using (true);

create policy inspections_insert on manufacturing.inspections for insert to authenticated
with
  check (true);

create policy inspections_update on manufacturing.inspections
for update
  to authenticated using (true)
with
  check (true);

create policy inspections_delete on manufacturing.inspections for delete to authenticated using (true);

create table manufacturing.inspection_results (
  id uuid primary key default extensions.uuid_generate_v4 (),
  inspection_id uuid not null references manufacturing.inspections (id) on delete cascade,
  characteristic_id uuid references manufacturing.quality_characteristics (id) on delete set null,
  sample_number integer not null default 1,
  measured_value numeric(14, 4),
  text_value varchar(160),
  is_within_spec boolean,
  deviation numeric(14, 4),
  defect_code_id uuid references manufacturing.defect_codes (id) on delete set null,
  note varchar(300),
  created_at timestamptz default current_timestamp
);

comment on table manufacturing.inspection_results is '{
    "icon": "ListChecks",
    "name": "Measurements",
    "description": "One measurement against one characteristic, and whether it held.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "measurement", "title": "Measurement", "fields": ["inspection_id", "characteristic_id", "sample_number", "measured_value", "text_value"]},
            {"id": "outcome", "title": "Outcome", "fields": ["defect_code_id", "note"]},
            {"id": "derived", "title": "Derived", "fields": {"read": ["is_within_spec", "deviation"]}}
        ]
    },
    "query": {
        "sort": [{"id": "sample_number", "desc": false}],
        "join": [
            {"table": "quality_characteristics", "on": "characteristic_id", "alias": "characteristic", "columns": ["code", "name", "nominal_value", "unit"]},
            {"table": "defect_codes", "on": "defect_code_id", "columns": ["code", "name", "severity"]}
        ]
    }
}';

revoke all on table manufacturing.inspection_results
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.inspection_results to "x-admin",
"inspector";

grant
select
  on table manufacturing.inspection_results to "production-planner",
  "operator";

create index idx_mfg_inspection_results_inspection on manufacturing.inspection_results (inspection_id);

alter table manufacturing.inspection_results enable row level security;

create policy inspection_results_select on manufacturing.inspection_results for
select
  to authenticated using (true);

create policy inspection_results_insert on manufacturing.inspection_results for insert to authenticated
with
  check (true);

create policy inspection_results_update on manufacturing.inspection_results
for update
  to authenticated using (true)
with
  check (true);

create policy inspection_results_delete on manufacturing.inspection_results for delete to authenticated using (true);

create sequence if not exists manufacturing.ncr_number_seq;

create table manufacturing.nonconformances (
  id uuid primary key default extensions.uuid_generate_v4 (),
  ncr_number varchar(30) not null unique default (
    'NCR-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('manufacturing.ncr_number_seq')::text,
      5,
      '0'
    )
  ),
  production_order_id uuid references manufacturing.production_orders (id) on delete set null,
  inspection_id uuid references manufacturing.inspections (id) on delete set null,
  product_id uuid references manufacturing.products (id) on delete set null,
  defect_code_id uuid references manufacturing.defect_codes (id) on delete set null,
  status manufacturing.ncr_status not null default 'open',
  disposition manufacturing.ncr_disposition not null default 'pending',
  severity manufacturing.defect_severity not null default 'minor',
  quantity_affected numeric(14, 3) not null default 0,
  raised_at timestamptz not null default current_timestamp,
  raised_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  dispositioned_by uuid references supasheet.users (id) on delete set null,
  dispositioned_at timestamptz,
  closed_at timestamptz,
  age_days integer,
  title varchar(200) not null,
  description supasheet.RICH_TEXT,
  root_cause supasheet.RICH_TEXT,
  corrective_action supasheet.RICH_TEXT,
  cost_impact numeric(14, 2) not null default 0,
  evidence supasheet.file,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column manufacturing.nonconformances.status is '{
    "progress": true,
    "values": {
        "open": {"variant": "destructive", "icon": "CircleAlert"},
        "investigating": {"variant": "warning", "icon": "Search"},
        "dispositioned": {"variant": "info", "icon": "Gavel"},
        "closed": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on column manufacturing.nonconformances.disposition is '{
    "progress": false,
    "values": {
        "pending": {"variant": "secondary", "icon": "Clock"},
        "rework": {"variant": "warning", "icon": "Hammer"},
        "scrap": {"variant": "destructive", "icon": "Trash2"},
        "use_as_is": {"variant": "info", "icon": "CircleCheck"},
        "return_to_supplier": {"variant": "warning", "icon": "Undo2"},
        "regrade": {"variant": "secondary", "icon": "ArrowDownUp"}
    }
}';

comment on table manufacturing.nonconformances is '{
    "icon": "OctagonAlert",
    "name": "Non-conformances",
    "description": "What went wrong, what was decided about it, and whether it was fixed.",
    "collapsible_group": "Quality",
    "display": "block",
    "primary_view": "kanban",
    "detail": {"header": {"title": "title", "badges": ["status", "disposition", "severity"]}},
    "views": [
        {"id": "kanban", "name": "NCR Board", "type": "kanban", "group": "status", "title": "title", "description": "ncr_number", "date": "raised_at", "badge": "severity"},
        {"id": "calendar", "name": "Raised", "type": "calendar", "title": "title", "badge": "severity", "start_date": "raised_at"},
        {"id": "list", "name": "All NCRs", "type": "list", "title": "ncr_number", "description": "title", "field_1": "disposition", "field_2": "age_days"}
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["open", "investigating"], "operator": "in"}]},
        {"id": "critical", "name": "Critical", "filters": [{"id": "severity", "value": "critical", "operator": "eq"}]},
        {"id": "awaiting", "name": "Awaiting Disposition", "filters": [{"id": "disposition", "value": "pending", "operator": "eq"}]},
        {"id": "stale", "name": "Open Over 14 Days", "filters": [{"id": "age_days", "value": "14", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["title", "production_order_id", "severity", "quantity_affected"],
        "sections": [
            {"id": "what", "title": "What happened", "fields": ["title", "description", "production_order_id", "inspection_id", "product_id", "defect_code_id"]},
            {"id": "impact", "title": "Impact", "fields": ["severity", "quantity_affected", "cost_impact", "evidence"]},
            {"id": "decision", "title": "Decision", "fields": ["status", "disposition", "dispositioned_by"]},
            {"id": "analysis", "title": "Analysis", "collapsible": true, "fields": ["root_cause", "corrective_action"]},
            {"id": "trail", "title": "Trail", "fields": {"read": ["raised_at", "raised_by", "dispositioned_at", "closed_at", "age_days"]}}
        ],
        "behavior": {
            "root_cause": {"required": [{"id": "status", "operator": "eq", "value": "closed"}]},
            "corrective_action": {"required": [{"id": "status", "operator": "eq", "value": "closed"}]}
        }
    },
    "query": {
        "sort": [{"id": "raised_at", "desc": true}],
        "join": [
            {"table": "production_orders", "on": "production_order_id", "columns": ["order_number"]},
            {"table": "products", "on": "product_id", "columns": ["sku", "name"]},
            {"table": "defect_codes", "on": "defect_code_id", "columns": ["code", "name", "severity"]}
        ]
    }
}';

comment on column manufacturing.nonconformances.cost_impact is '{"name": "Cost Impact", "aggregate": "sum"}';

comment on column manufacturing.nonconformances.evidence is '{"accept": ".pdf,.png,.jpg", "max_files": 5, "max_size": 5242880}';

revoke all on table manufacturing.nonconformances
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.nonconformances to "x-admin",
"inspector";

grant
select
,
  insert on table manufacturing.nonconformances to "operator";

grant
select
  on table manufacturing.nonconformances to "production-planner";

revoke all on sequence manufacturing.ncr_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence manufacturing.ncr_number_seq to "x-admin",
"inspector",
"operator";

create index idx_mfg_ncr_order on manufacturing.nonconformances (production_order_id);

create index idx_mfg_ncr_status on manufacturing.nonconformances (status);

create index idx_mfg_ncr_open on manufacturing.nonconformances (raised_at)
where
  status in ('open', 'investigating');

alter table manufacturing.nonconformances enable row level security;

create policy ncr_select on manufacturing.nonconformances for
select
  to authenticated using (true);

create policy ncr_insert on manufacturing.nonconformances for insert to authenticated
with
  check (true);

create policy ncr_update on manufacturing.nonconformances
for update
  to authenticated using (true)
with
  check (true);

create policy ncr_delete on manufacturing.nonconformances for delete to authenticated using (true);

----------------------------------------------------------------
-- Manufacturing settings (singleton)
----------------------------------------------------------------
create table manufacturing.manufacturing_settings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  company_name varchar(200) not null default 'Supasheet',
  logo supasheet.file,
  base_currency varchar(3) not null default 'USD',
  default_overhead_rate_per_hour numeric(12, 4) not null default 45,
  working_hours_per_day numeric(5, 2) not null default 16,
  working_days_per_week integer not null default 5,
  enforce_operation_sequence boolean not null default true,
  enforce_certification boolean not null default true,
  auto_release_on_schedule boolean not null default false,
  scrap_alert_threshold supasheet.PERCENTAGE not null default 5,
  ncr_escalation_days integer not null default 14,
  timezone varchar(64) not null default 'UTC',
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint settings_hours_sane check (
    working_hours_per_day > 0
    and working_hours_per_day <= 24
  )
);

comment on table manufacturing.manufacturing_settings is '{
    "icon": "Settings",
    "name": "Manufacturing Settings",
    "description": "The policy every production routine reads before it does anything.",
    "collapsible_group": "Configuration",
    "display": "block",
    "singleton": true,
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["company_name", "logo", "base_currency", "timezone"]},
            {"id": "capacity", "title": "Capacity", "fields": ["working_hours_per_day", "working_days_per_week", "default_overhead_rate_per_hour"]},
            {"id": "control", "title": "Shop-floor control", "fields": ["enforce_operation_sequence", "enforce_certification", "auto_release_on_schedule"]},
            {"id": "quality", "title": "Quality", "fields": ["scrap_alert_threshold", "ncr_escalation_days"]}
        ],
        "metadata": {
            "enforce_operation_sequence": {"description": "With this on, operation 20 cannot start until operation 10 has finished. Turning it off allows parallel routings and is rarely what you want."},
            "enforce_certification": {"description": "With this on, only an operator certified on the work centre can confirm work there."}
        }
    }
}';

comment on column manufacturing.manufacturing_settings.logo is '{"accept": "image/*", "max_size": 2097152}';

revoke all on table manufacturing.manufacturing_settings
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update on table manufacturing.manufacturing_settings to "x-admin";

grant
select
  on table manufacturing.manufacturing_settings to "production-planner",
  "operator",
  "inspector";

alter table manufacturing.manufacturing_settings enable row level security;

create policy settings_select on manufacturing.manufacturing_settings for
select
  to authenticated using (true);

create policy settings_insert on manufacturing.manufacturing_settings for insert to authenticated
with
  check (true);

create policy settings_update on manufacturing.manufacturing_settings
for update
  to authenticated using (true)
with
  check (true);

----------------------------------------------------------------
-- Shared helpers
----------------------------------------------------------------
create or replace function manufacturing.set_updated_at () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  new.updated_at := current_timestamp;
  return new;
end;
$$;

create or replace function manufacturing.settings () returns manufacturing.manufacturing_settings language sql stable security definer
set
  search_path = '' as $$
  select * from manufacturing.manufacturing_settings limit 1;
$$;

revoke all on function manufacturing.settings ()
from
  public;

grant
execute on function manufacturing.settings () to "x-admin",
"production-planner",
"operator",
"inspector";

----------------------------------------------------------------
-- Where each part sits in the structure
--
-- Level 0 is something nothing else is made of — a finished good. A
-- component's level is one below the deepest parent that uses it,
-- which is what makes a bottom-up cost roll-up possible: process the
-- deepest level first and every child is already priced when its
-- parent is reached.
----------------------------------------------------------------
create or replace function manufacturing.recalc_bom_levels () returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  with recursive lvl as (
    select p.id, 0 as level
    from manufacturing.products p
    where not exists (
      select 1
      from manufacturing.bom_lines bl
        join manufacturing.boms b on b.id = bl.bom_id and b.status = 'active'
      where bl.component_product_id = p.id
    )
    union all
    select bl.component_product_id, l.level + 1
    from lvl l
      join manufacturing.boms b on b.product_id = l.id and b.status = 'active'
      join manufacturing.bom_lines bl on bl.bom_id = b.id
    where l.level < 25
  ),
  deepest as (
    select id, max(level) as level
    from lvl
    group by id
  )
  update manufacturing.products p
  set bom_level = d.level
  from deepest d
  where p.id = d.id
    and p.bom_level is distinct from d.level;
end;
$$;

-- How many components a part has, and how many bills it appears on.
create or replace function manufacturing.recalc_product_structure (p_ids uuid[] default null) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  update manufacturing.products p
  set component_count = s.components,
    where_used_count = s.used_in
  from (
      select pr.id,
        (
          select count(*)
          from manufacturing.bom_lines bl
            join manufacturing.boms b on b.id = bl.bom_id and b.status = 'active'
          where b.product_id = pr.id
        ) as components,
        (
          select count(distinct b.product_id)
          from manufacturing.bom_lines bl
            join manufacturing.boms b on b.id = bl.bom_id and b.status = 'active'
          where bl.component_product_id = pr.id
        ) as used_in
      from manufacturing.products pr
      where p_ids is null or pr.id = any (p_ids)
    ) s
  where p.id = s.id
    and (p.component_count, p.where_used_count) is distinct from (s.components::integer, s.used_in::integer);
end;
$$;

----------------------------------------------------------------
-- The standard cost roll-up
--
-- Walked bottom-up, deepest level first, so that by the time a parent
-- is reached every one of its children already carries a settled
-- standard cost. A single pass over the whole catalogue in level
-- order does what a naive recursive query cannot: it prices a
-- five-level assembly correctly in one go.
--
-- Bought parts are left alone. Their cost is what the supplier
-- charges, which no amount of walking will reveal.
----------------------------------------------------------------
create or replace function manufacturing.roll_up_cost () returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_level integer;
  v_max_level integer;
  v_updated integer := 0;
  v_rows integer;
  v_overhead numeric(12, 4);
begin
  perform manufacturing.recalc_bom_levels ();

  v_overhead := coalesce((manufacturing.settings ()).default_overhead_rate_per_hour, 0);

  select coalesce(max(bom_level), 0) into v_max_level from manufacturing.products;

  for v_level in reverse v_max_level..0 loop
    -- Material: what the active bill says, at the quantities it says,
    -- including the scrap it expects to lose.
    update manufacturing.products p
    set material_cost = coalesce(m.cost, p.material_cost)
    from (
        select b.product_id,
          sum(
            c.standard_cost * bl.quantity_per
              * (1 + coalesce(bl.scrap_percent, 0)::numeric / 100)
              / b.output_quantity
          ) as cost
        from manufacturing.boms b
          join manufacturing.bom_lines bl on bl.bom_id = b.id
          join manufacturing.products c on c.id = bl.component_product_id
        where b.status = 'active'
        group by b.product_id
      ) m
    where p.id = m.product_id
      and p.bom_level = v_level
      and p.product_type <> 'buy'
      and p.material_cost is distinct from round(m.cost, 4);

    -- Labour and overhead: the active routing, at the work centre
    -- rates, spread over the lot size the part is made in.
    update manufacturing.products p
    set labour_cost = round(r.labour, 4),
      overhead_cost = round(r.overhead, 4)
    from (
        select rt.product_id,
          sum(
            (
              ro.setup_minutes / greatest(pr.lot_size, 1) + ro.run_minutes_per_unit
            ) / 60.0 * wc.labour_rate_per_hour
          ) as labour,
          sum(
            (
              ro.setup_minutes / greatest(pr.lot_size, 1) + ro.run_minutes_per_unit
            ) / 60.0 * coalesce(nullif(wc.overhead_rate_per_hour, 0), v_overhead)
          ) as overhead
        from manufacturing.routings rt
          join manufacturing.routing_operations ro on ro.routing_id = rt.id
          join manufacturing.work_centers wc on wc.id = ro.work_center_id
          join manufacturing.products pr on pr.id = rt.product_id
        where rt.status = 'active'
        group by rt.product_id
      ) r
    where p.id = r.product_id
      and p.bom_level = v_level
      and p.product_type <> 'buy'
      and (p.labour_cost, p.overhead_cost) is distinct from (round(r.labour, 4), round(r.overhead, 4));

    update manufacturing.products p
    set standard_cost = round(p.material_cost + p.labour_cost + p.overhead_cost, 4)
    where p.bom_level = v_level
      and p.standard_cost is distinct from round(p.material_cost + p.labour_cost + p.overhead_cost, 4);

    get diagnostics v_rows = row_count;
    v_updated := v_updated + v_rows;
  end loop;

  -- A bought part's standard cost is simply what it costs to buy.
  update manufacturing.products
  set standard_cost = material_cost
  where product_type = 'buy'
    and standard_cost is distinct from material_cost;

  -- Push the settled costs back onto the bill lines so the structure
  -- can be read without recomputing it.
  update manufacturing.bom_lines bl
  set unit_cost = c.standard_cost,
    extended_cost = round(
      c.standard_cost * bl.quantity_per * (1 + coalesce(bl.scrap_percent, 0)::numeric / 100),
      4
    )
  from manufacturing.products c
  where c.id = bl.component_product_id
    and (bl.unit_cost, bl.extended_cost) is distinct from (
      c.standard_cost,
      round(c.standard_cost * bl.quantity_per * (1 + coalesce(bl.scrap_percent, 0)::numeric / 100), 4)
    );

  update manufacturing.boms b
  set material_cost = coalesce(x.total, 0)
  from (
      select bom_id, sum(extended_cost) as total
      from manufacturing.bom_lines
      group by bom_id
    ) x
  where b.id = x.bom_id
    and b.material_cost is distinct from coalesce(x.total, 0);

  perform manufacturing.recalc_product_structure ();

  return v_updated;
end;
$$;

revoke all on function manufacturing.recalc_bom_levels ()
from
  public;

revoke all on function manufacturing.recalc_product_structure (uuid[])
from
  public;

revoke all on function manufacturing.roll_up_cost ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function manufacturing.roll_up_cost () to "x-admin",
"production-planner";

----------------------------------------------------------------
-- Releasing a works order
--
-- Freezes both the bill and the routing onto the order. A bill
-- revised next month must not retrospectively change what this order
-- was built to, which is the whole reason these are separate tables
-- rather than joins back to the engineering data.
----------------------------------------------------------------
create or replace function manufacturing.release_order (p_order_id uuid) returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_order manufacturing.production_orders;
  v_bom_id uuid;
  v_routing_id uuid;
  v_start_qty numeric(14, 3);
  v_yield numeric;
  v_lines integer := 0;
begin
  select * into v_order from manufacturing.production_orders where id = p_order_id;

  if v_order.id is null then
    raise exception 'Works order % does not exist.', p_order_id;
  end if;

  -- "Already released" means "already carries a frozen bill", not
  -- "the status column says released". This function is reached from
  -- the AFTER trigger on that very status change, so testing the
  -- status here would reject every release on the way in.
  if v_order.bom_id is not null then
    raise exception 'Works order % was already released against bill %.',
      v_order.order_number, v_order.bom_id;
  end if;

  if v_order.status in ('completed', 'closed', 'cancelled') then
    raise exception 'Works order % is % and cannot be released.', v_order.order_number, v_order.status;
  end if;

  select id into v_bom_id
  from manufacturing.boms
  where product_id = v_order.product_id
    and status = 'active';

  if v_bom_id is null then
    raise exception 'There is no active bill of material for that product.'
      using hint = 'Activate a bill before releasing the order.';
  end if;

  select id into v_routing_id
  from manufacturing.routings
  where product_id = v_order.product_id
    and status = 'active';

  -- YOU CANNOT BUILD WHAT YOU CANNOT CONSUME. The quantity started is
  -- the quantity ordered grossed up for the expected yield, so an
  -- order for 100 at 96% yield starts 105 and the bill is exploded at
  -- 105 rather than 100.
  select coalesce(nullif(yield_percent, 0), 100) into v_yield
  from manufacturing.products
  where id = v_order.product_id;

  v_start_qty := round(v_order.quantity_ordered * 100.0 / v_yield, 3);

  delete from manufacturing.production_order_components where production_order_id = p_order_id;

  insert into manufacturing.production_order_components (
    production_order_id, component_product_id, operation_sequence, line_number,
    quantity_required, unit_cost, extended_cost, issue_method
  )
  select p_order_id,
    bl.component_product_id,
    bl.operation_sequence,
    bl.line_number,
    round(
      v_start_qty * bl.quantity_per / b.output_quantity
        * (1 + coalesce(bl.scrap_percent, 0)::numeric / 100),
      4
    ),
    c.standard_cost,
    round(
      v_start_qty * bl.quantity_per / b.output_quantity
        * (1 + coalesce(bl.scrap_percent, 0)::numeric / 100) * c.standard_cost,
      4
    ),
    bl.issue_method
  from manufacturing.boms b
    join manufacturing.bom_lines bl on bl.bom_id = b.id
    join manufacturing.products c on c.id = bl.component_product_id
  where b.id = v_bom_id;

  get diagnostics v_lines = row_count;

  delete from manufacturing.production_order_operations where production_order_id = p_order_id;

  if v_routing_id is not null then
    insert into manufacturing.production_order_operations (
      production_order_id, work_center_id, sequence_number, name,
      planned_setup_minutes, planned_run_minutes, is_inspection_point,
      scheduled_start, scheduled_end
    )
    select p_order_id,
      ro.work_center_id,
      ro.sequence_number,
      ro.name,
      ro.setup_minutes,
      round(ro.run_minutes_per_unit * v_start_qty, 2),
      ro.is_inspection_point,
      coalesce(v_order.planned_start, current_date)::timestamptz
        + (row_number() over (order by ro.sequence_number) - 1) * interval '1 day',
      coalesce(v_order.planned_start, current_date)::timestamptz
        + (row_number() over (order by ro.sequence_number)) * interval '1 day'
    from manufacturing.routing_operations ro
    where ro.routing_id = v_routing_id
    order by ro.sequence_number;
  end if;

  update manufacturing.production_orders
  set status = 'released',
    bom_id = v_bom_id,
    routing_id = v_routing_id,
    quantity_started = v_start_qty,
    released_at = coalesce(released_at, current_timestamp),
    released_by = coalesce(released_by, auth.uid ())
  where id = p_order_id;

  return v_lines;
end;
$$;

revoke all on function manufacturing.release_order (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function manufacturing.release_order (uuid) to "x-admin",
"production-planner";

----------------------------------------------------------------
-- Works order rollups and guards
----------------------------------------------------------------
create or replace function manufacturing.orders_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.quantity_remaining := new.quantity_ordered;
    new.planned_start := coalesce(new.planned_start, current_date);
    new.planned_end := coalesce(new.planned_end, new.planned_start + 7);
    return new;
  end if;

  if new.status is not distinct from old.status then
    new.quantity_remaining := greatest(new.quantity_ordered - new.quantity_produced, 0);
    return new;
  end if;

  if new.status = 'cancelled' then
    if coalesce(old.quantity_produced, 0) > 0 then
      raise exception 'Works order % has already produced % units and cannot be cancelled.',
        old.order_number, old.quantity_produced
        using hint = 'Close it short instead — the output has to go somewhere.';
    end if;

    if coalesce(new.cancelled_reason, '') = '' then
      raise exception 'Cancelling % needs a reason.', new.order_number;
    end if;
  end if;

  if new.status = 'closed' and old.status not in ('completed', 'in_progress') then
    raise exception 'Works order % cannot be closed from %.', old.order_number, old.status;
  end if;

  if old.status in ('closed', 'cancelled') then
    raise exception 'Works order % is % and cannot be reopened.', old.order_number, old.status;
  end if;

  if new.status = 'in_progress' and old.status = 'released' then
    new.actual_start := coalesce(new.actual_start, current_timestamp);
  end if;

  if new.status = 'completed' then
    new.actual_end := coalesce(new.actual_end, current_timestamp);
  end if;

  if new.status = 'closed' then
    new.closed_at := coalesce(new.closed_at, current_timestamp);
  end if;

  new.quantity_remaining := greatest(new.quantity_ordered - new.quantity_produced, 0);

  return new;
end;
$$;

create trigger trg_orders_guard
before insert or update on manufacturing.production_orders for each row
execute function manufacturing.orders_guard ();

create trigger trg_orders_updated_at
before update on manufacturing.production_orders for each row
execute function manufacturing.set_updated_at ();

create or replace function manufacturing.orders_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = 'released' and old.status in ('draft', 'planned') and new.bom_id is null then
    perform manufacturing.release_order (new.id);
  end if;

  return new;
end;
$$;

create trigger trg_orders_after_change
after update on manufacturing.production_orders for each row
execute function manufacturing.orders_after_change ();

create or replace function manufacturing.recalc_order_rollup (p_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  update manufacturing.production_orders o
  set operation_count = s.ops,
    component_count = s.comps,
    standard_hours = s.std_hours,
    actual_hours = s.act_hours,
    quantity_produced = s.good,
    quantity_scrapped = s.scrap,
    quantity_remaining = greatest(o.quantity_ordered - s.good, 0),
    yield_percent = case
      when o.quantity_started = 0 then null
      else round(100.0 * s.good / o.quantity_started, 2)::real
    end,
    material_cost = s.material,
    labour_cost = s.labour,
    overhead_cost = s.overhead,
    total_cost = s.material + s.labour + s.overhead,
    updated_at = current_timestamp
  from (select distinct x.id from unnest(p_ids) as x (id) where x.id is not null) t
    cross join lateral (
      select (
          select count(*)
          from manufacturing.production_order_operations op
          where op.production_order_id = t.id
        ) as ops,
        (
          select count(*)
          from manufacturing.production_order_components c
          where c.production_order_id = t.id
        ) as comps,
        (
          select coalesce(sum(op.planned_setup_minutes + op.planned_run_minutes), 0) / 60.0
          from manufacturing.production_order_operations op
          where op.production_order_id = t.id
        ) as std_hours,
        (
          select coalesce(sum(cf.total_minutes), 0) / 60.0
          from manufacturing.production_confirmations cf
          where cf.production_order_id = t.id
        ) as act_hours,
        -- The final operation is the one that yields finished units.
        -- Summing every operation would count the same part once per
        -- step it passed through.
        coalesce(
          (
            select sum(cf.quantity_good)
            from manufacturing.production_confirmations cf
              join manufacturing.production_order_operations op on op.id = cf.operation_id
            where cf.production_order_id = t.id
              and op.sequence_number = (
                select max(o2.sequence_number)
                from manufacturing.production_order_operations o2
                where o2.production_order_id = t.id
              )
          ),
          (
            select sum(cf.quantity_good)
            from manufacturing.production_confirmations cf
            where cf.production_order_id = t.id
              and cf.operation_id is null
          ),
          0
        ) as good,
        (
          select coalesce(sum(cf.quantity_scrap), 0)
          from manufacturing.production_confirmations cf
          where cf.production_order_id = t.id
        ) as scrap,
        (
          select coalesce(sum(c.quantity_issued * c.unit_cost), 0)
          from manufacturing.production_order_components c
          where c.production_order_id = t.id
        ) as material,
        (
          select coalesce(sum(cf.total_minutes / 60.0 * wc.labour_rate_per_hour), 0)
          from manufacturing.production_confirmations cf
            join manufacturing.production_order_operations op on op.id = cf.operation_id
            join manufacturing.work_centers wc on wc.id = op.work_center_id
          where cf.production_order_id = t.id
        ) as labour,
        (
          select coalesce(sum(cf.total_minutes / 60.0 * wc.overhead_rate_per_hour), 0)
          from manufacturing.production_confirmations cf
            join manufacturing.production_order_operations op on op.id = cf.operation_id
            join manufacturing.work_centers wc on wc.id = op.work_center_id
          where cf.production_order_id = t.id
        ) as overhead
    ) s
  where o.id = t.id;
end;
$$;

----------------------------------------------------------------
-- Confirmations
--
-- OPERATIONS ARE SEQUENTIAL, and only somebody signed off on the work
-- centre may book time against it. Both checks are settings-driven,
-- because a job shop running parallel routings genuinely does need to
-- turn the first one off.
----------------------------------------------------------------
create or replace function manufacturing.confirmations_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_order manufacturing.production_orders;
  v_op manufacturing.production_order_operations;
  v_settings manufacturing.manufacturing_settings;
  v_blocking integer;
  v_operator_user uuid;
begin
  select * into v_order from manufacturing.production_orders where id = new.production_order_id;
  v_settings := manufacturing.settings ();

  if v_order.status in ('draft', 'planned') then
    raise exception 'Works order % has not been released yet.', v_order.order_number;
  end if;

  if v_order.status in ('closed', 'cancelled') then
    raise exception 'Works order % is % — nothing further can be booked to it.',
      v_order.order_number, v_order.status;
  end if;

  new.total_minutes := coalesce(new.setup_minutes, 0) + coalesce(new.run_minutes, 0);

  if new.operation_id is not null then
    select * into v_op
    from manufacturing.production_order_operations
    where id = new.operation_id;

    if v_op.production_order_id <> new.production_order_id then
      raise exception 'That operation belongs to a different works order.';
    end if;

    -- OPERATIONS ARE SEQUENTIAL.
    if coalesce(v_settings.enforce_operation_sequence, true) then
      select count(*)
      into v_blocking
      from manufacturing.production_order_operations o
      where o.production_order_id = new.production_order_id
        and o.sequence_number < v_op.sequence_number
        and o.status not in ('completed', 'skipped');

      if v_blocking > 0 then
        raise exception 'Operation % cannot be booked yet — % earlier operation(s) are still open.',
          v_op.sequence_number, v_blocking
          using hint = 'The part has not reached this step.';
      end if;
    end if;

    -- Only somebody certified on the work centre.
    if coalesce(v_settings.enforce_certification, true) and new.operator_id is not null then
      select user_id into v_operator_user from manufacturing.operators where id = new.operator_id;

      if not exists (
        select 1
        from manufacturing.operator_certifications c
          join manufacturing.operators o on o.id = c.operator_id
        where o.id = new.operator_id
          and c.work_center_id = v_op.work_center_id
          and (c.expires_on is null or c.expires_on >= current_date)
      ) then
        raise exception 'That operator is not certified on this work centre.'
          using hint = 'Certify them, or book the work to somebody who is.';
      end if;
    end if;

    if new.machine_id is not null and not exists (
      select 1 from manufacturing.machines m
      where m.id = new.machine_id and m.work_center_id = v_op.work_center_id
    ) then
      raise exception 'That machine does not belong to this operation''s work centre.';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_confirmations_guard
before insert on manufacturing.production_confirmations for each row
execute function manufacturing.confirmations_guard ();

create or replace function manufacturing.confirmations_apply () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_op manufacturing.production_order_operations;
begin
  if new.operation_id is not null then
    update manufacturing.production_order_operations op
    set quantity_completed = op.quantity_completed + new.quantity_good,
      quantity_scrapped = op.quantity_scrapped + new.quantity_scrap,
      actual_minutes = op.actual_minutes + new.total_minutes,
      started_at = coalesce(op.started_at, new.confirmed_at),
      status = case
        when new.is_final then 'completed'::manufacturing.operation_status
        when op.status in ('pending', 'setup') then 'running'::manufacturing.operation_status
        else op.status
      end,
      completed_at = case when new.is_final then new.confirmed_at else op.completed_at end,
      efficiency = case
        when op.actual_minutes + new.total_minutes = 0 then null
        else round(
          100.0 * (op.planned_setup_minutes + op.planned_run_minutes)
            / (op.actual_minutes + new.total_minutes),
          2
        )::real
      end,
      updated_at = current_timestamp
    where op.id = new.operation_id;
  end if;

  -- The first confirmation is what actually starts a works order.
  update manufacturing.production_orders
  set status = 'in_progress',
    actual_start = coalesce(actual_start, new.confirmed_at)
  where id = new.production_order_id
    and status = 'released';

  perform manufacturing.recalc_order_rollup (array[new.production_order_id]);

  -- Backflushed components are consumed as output is declared, rather
  -- than being issued by hand.
  update manufacturing.production_order_components c
  set quantity_consumed = least(
      c.quantity_consumed + round(
        c.quantity_required * (new.quantity_good + new.quantity_scrap)
          / nullif((select quantity_started from manufacturing.production_orders where id = new.production_order_id), 0),
        4
      ),
      c.quantity_required
    )
  where c.production_order_id = new.production_order_id
    and c.issue_method = 'backflush';

  return new;
end;
$$;

create trigger trg_confirmations_apply
after insert on manufacturing.production_confirmations for each row
execute function manufacturing.confirmations_apply ();

create or replace function manufacturing.order_components_derive () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  new.quantity_outstanding := greatest(new.quantity_required - new.quantity_issued, 0);
  new.is_fully_issued := new.quantity_issued >= new.quantity_required;
  new.extended_cost := round(new.quantity_required * coalesce(new.unit_cost, 0), 4);

  if new.line_number is null then
    select coalesce(max(line_number), 0) + 10 into new.line_number
    from manufacturing.production_order_components
    where production_order_id = new.production_order_id;
  end if;

  return new;
end;
$$;

create trigger trg_order_components_derive
before insert or update on manufacturing.production_order_components for each row
execute function manufacturing.order_components_derive ();

create or replace function manufacturing.order_components_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  perform manufacturing.recalc_order_rollup (
    array[(coalesce(new, old)).production_order_id]
  );
  return coalesce(new, old);
end;
$$;

create trigger trg_order_components_rollup
after insert or delete or update on manufacturing.production_order_components for each row
execute function manufacturing.order_components_rollup ();

create or replace function manufacturing.order_operations_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  perform manufacturing.recalc_order_rollup (
    array[(coalesce(new, old)).production_order_id]
  );

  perform manufacturing.recalc_work_center_load (
    array[
      (coalesce(new, old)).work_center_id,
      case when tg_op = 'UPDATE' then old.work_center_id end
    ]
  );

  return coalesce(new, old);
end;
$$;

create or replace function manufacturing.recalc_work_center_load (p_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  update manufacturing.work_centers wc
  set machine_count = s.machines,
    open_operations = s.open_ops,
    scheduled_hours = s.hours,
    utilisation = case
      when wc.capacity_hours_per_day = 0 then null
      else round(100.0 * s.hours / (wc.capacity_hours_per_day * 5), 2)::real
    end,
    updated_at = current_timestamp
  from (select distinct x.id from unnest(p_ids) as x (id) where x.id is not null) t
    cross join lateral (
      select (
          select count(*)
          from manufacturing.machines m
          where m.work_center_id = t.id
        ) as machines,
        (
          select count(*)
          from manufacturing.production_order_operations op
          where op.work_center_id = t.id
            and op.status in ('pending', 'setup', 'running', 'paused')
        ) as open_ops,
        (
          select coalesce(sum(op.planned_setup_minutes + op.planned_run_minutes), 0) / 60.0
          from manufacturing.production_order_operations op
          where op.work_center_id = t.id
            and op.status in ('pending', 'setup', 'running', 'paused')
        ) as hours
    ) s
  where wc.id = t.id
    and (wc.machine_count, wc.open_operations, wc.scheduled_hours)
      is distinct from (s.machines::integer, s.open_ops::integer, round(s.hours, 2));
end;
$$;

create trigger trg_order_operations_rollup
after insert or delete or update on manufacturing.production_order_operations for each row
execute function manufacturing.order_operations_rollup ();

create trigger trg_order_operations_updated_at
before update on manufacturing.production_order_operations for each row
execute function manufacturing.set_updated_at ();

----------------------------------------------------------------
-- Downtime, maintenance and machine availability
----------------------------------------------------------------
create or replace function manufacturing.downtime_derive () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.work_center_id is null then
    select work_center_id into new.work_center_id from manufacturing.machines where id = new.machine_id;
  end if;

  new.is_open := new.ended_at is null;
  new.duration_minutes := case
    when new.ended_at is null then null
    else round(extract(epoch from (new.ended_at - new.started_at)) / 60.0, 2)
  end;

  return new;
end;
$$;

create trigger trg_downtime_derive
before insert or update on manufacturing.downtime_events for each row
execute function manufacturing.downtime_derive ();

create trigger trg_downtime_updated_at
before update on manufacturing.downtime_events for each row
execute function manufacturing.set_updated_at ();

create or replace function manufacturing.recalc_machine_position (p_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  update manufacturing.machines m
  set downtime_hours = s.down_hours,
    runtime_hours = s.run_hours,
    open_downtime_events = s.open_events,
    -- Availability is runtime over the time the machine was expected
    -- to be available, which is runtime plus everything that stopped
    -- it. A machine nobody logged anything against is not 0% available.
    availability = case
      when s.run_hours + s.down_hours = 0 then null
      else round(100.0 * s.run_hours / (s.run_hours + s.down_hours), 2)::real
    end,
    updated_at = current_timestamp
  from (select distinct x.id from unnest(p_ids) as x (id) where x.id is not null) t
    cross join lateral (
      select (
          select coalesce(sum(d.duration_minutes), 0) / 60.0
          from manufacturing.downtime_events d
          where d.machine_id = t.id
        ) as down_hours,
        (
          select coalesce(sum(cf.total_minutes), 0) / 60.0
          from manufacturing.production_confirmations cf
          where cf.machine_id = t.id
        ) as run_hours,
        (
          select count(*)
          from manufacturing.downtime_events d
          where d.machine_id = t.id
            and d.is_open
        ) as open_events
    ) s
  where m.id = t.id
    and (m.downtime_hours, m.runtime_hours, m.open_downtime_events)
      is distinct from (round(s.down_hours, 2), round(s.run_hours, 2), s.open_events::integer);
end;
$$;

create or replace function manufacturing.downtime_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  perform manufacturing.recalc_machine_position (array[(coalesce(new, old)).machine_id]);

  -- A machine with an open downtime event is down, and stops being
  -- down when the last one is closed.
  update manufacturing.machines m
  set status = case
    when exists (
      select 1 from manufacturing.downtime_events d
      where d.machine_id = m.id and d.is_open
    ) then 'down'::manufacturing.machine_status
    when m.status = 'down' then 'idle'::manufacturing.machine_status
    else m.status
  end
  where m.id = (coalesce(new, old)).machine_id
    and m.status <> 'retired';

  return coalesce(new, old);
end;
$$;

create trigger trg_downtime_rollup
after insert or delete or update on manufacturing.downtime_events for each row
execute function manufacturing.downtime_rollup ();

create or replace function manufacturing.maintenance_derive () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  new.is_overdue := new.status in ('scheduled', 'in_progress')
    and new.scheduled_for < current_date;

  if new.is_overdue and new.status = 'scheduled' then
    new.status := 'overdue';
  end if;

  if new.status = 'in_progress' and coalesce(old.status, 'scheduled') <> 'in_progress' then
    new.started_at := coalesce(new.started_at, current_timestamp);
  end if;

  if new.status = 'completed' then
    new.completed_at := coalesce(new.completed_at, current_timestamp);
    new.duration_minutes := case
      when new.started_at is null then null
      else round(extract(epoch from (new.completed_at - new.started_at)) / 60.0, 2)
    end;
  end if;

  return new;
end;
$$;

create trigger trg_maintenance_derive
before insert or update on manufacturing.maintenance_orders for each row
execute function manufacturing.maintenance_derive ();

create trigger trg_maintenance_updated_at
before update on manufacturing.maintenance_orders for each row
execute function manufacturing.set_updated_at ();

create or replace function manufacturing.maintenance_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = 'completed' and coalesce(old.status, 'scheduled') <> 'completed' then
    update manufacturing.machines
    set last_service_on = new.completed_at::date,
      next_service_due = new.completed_at::date + service_interval_days,
      status = case when status = 'maintenance' then 'idle' else status end
    where id = new.machine_id;
  end if;

  if new.status = 'in_progress' and coalesce(old.status, 'scheduled') <> 'in_progress' then
    update manufacturing.machines
    set status = 'maintenance'
    where id = new.machine_id
      and status not in ('retired', 'down');
  end if;

  return new;
end;
$$;

create trigger trg_maintenance_after_change
after insert or update on manufacturing.maintenance_orders for each row
execute function manufacturing.maintenance_after_change ();

----------------------------------------------------------------
-- Quality
----------------------------------------------------------------
create or replace function manufacturing.inspection_results_derive () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_char manufacturing.quality_characteristics;
begin
  if new.characteristic_id is not null then
    select * into v_char from manufacturing.quality_characteristics where id = new.characteristic_id;

    if new.measured_value is not null and v_char.nominal_value is not null then
      new.deviation := round(new.measured_value - v_char.nominal_value, 4);
    end if;

    -- In specification means inside the tolerance band, where one is
    -- defined. A characteristic with no tolerances is judged by the
    -- inspector, not by arithmetic.
    if new.measured_value is not null
      and (v_char.tolerance_lower is not null or v_char.tolerance_upper is not null) then
      new.is_within_spec := (
        v_char.tolerance_lower is null or new.measured_value >= v_char.tolerance_lower
      ) and (
        v_char.tolerance_upper is null or new.measured_value <= v_char.tolerance_upper
      );
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_inspection_results_derive
before insert or update on manufacturing.inspection_results for each row
execute function manufacturing.inspection_results_derive ();

create or replace function manufacturing.inspection_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_id uuid;
  v_total integer;
  v_failed integer;
begin
  v_id := coalesce(new.inspection_id, old.inspection_id);

  select count(*), count(*) filter (where is_within_spec is false)
  into v_total, v_failed
  from manufacturing.inspection_results
  where inspection_id = v_id;

  update manufacturing.inspections
  set characteristic_count = v_total,
    failed_count = v_failed,
    pass_rate = case
      when v_total = 0 then null
      else round(100.0 * (v_total - v_failed) / v_total, 2)::real
    end,
    -- A measured failure decides the result on its own. An inspector
    -- can still downgrade a pass to a conditional one by hand.
    result = case
      when v_failed > 0 then 'fail'::manufacturing.inspection_result
      when v_total > 0 and result = 'pending' then 'pass'::manufacturing.inspection_result
      else result
    end
  where id = v_id
    and (characteristic_count, failed_count) is distinct from (v_total, v_failed);

  return coalesce(new, old);
end;
$$;

create trigger trg_inspection_results_rollup
after insert or delete or update on manufacturing.inspection_results for each row
execute function manufacturing.inspection_rollup ();

create or replace function manufacturing.inspections_derive () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.product_id is null then
    select product_id into new.product_id
    from manufacturing.production_orders
    where id = new.production_order_id;
  end if;

  if new.inspector_name is null and new.inspector_id is not null then
    select name into new.inspector_name from supasheet.users where id = new.inspector_id;
  end if;

  if new.quantity_inspected > 0 then
    new.quantity_passed := coalesce(nullif(new.quantity_passed, 0), new.quantity_inspected - new.quantity_failed);
  end if;

  return new;
end;
$$;

create trigger trg_inspections_derive
before insert or update on manufacturing.inspections for each row
execute function manufacturing.inspections_derive ();

create trigger trg_inspections_updated_at
before update on manufacturing.inspections for each row
execute function manufacturing.set_updated_at ();

create or replace function manufacturing.ncr_derive () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  new.age_days := greatest(
    extract(day from (coalesce(new.closed_at, current_timestamp) - new.raised_at))::integer,
    0
  );

  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'dispositioned' then
      if new.disposition = 'pending' then
        raise exception 'NCR % cannot be dispositioned without a disposition.', new.ncr_number;
      end if;

      new.dispositioned_by := coalesce(new.dispositioned_by, auth.uid ());
      new.dispositioned_at := coalesce(new.dispositioned_at, current_timestamp);
    end if;

    if new.status = 'closed' then
      if old.status <> 'dispositioned' then
        raise exception 'NCR % must be dispositioned before it is closed.', new.ncr_number;
      end if;

      if coalesce(new.root_cause, '') = '' or coalesce(new.corrective_action, '') = '' then
        raise exception 'Closing NCR % needs a root cause and a corrective action.', new.ncr_number
          using hint = 'An NCR closed without either of those teaches nobody anything.';
      end if;

      new.closed_at := coalesce(new.closed_at, current_timestamp);
    end if;

    if old.status = 'closed' then
      raise exception 'NCR % is closed.', old.ncr_number;
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_ncr_derive
before insert or update on manufacturing.nonconformances for each row
execute function manufacturing.ncr_derive ();

create trigger trg_ncr_updated_at
before update on manufacturing.nonconformances for each row
execute function manufacturing.set_updated_at ();

create or replace function manufacturing.defect_code_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  update manufacturing.defect_codes d
  set occurrence_count = x.n
  from (
      select t.id, count(n.id) as n
      from (
          select (coalesce(new, old)).defect_code_id as id
          union
          select case when tg_op = 'UPDATE' then old.defect_code_id end
        ) t
        left join manufacturing.nonconformances n on n.defect_code_id = t.id
      where t.id is not null
      group by t.id
    ) x
  where d.id = x.id
    and d.occurrence_count is distinct from x.n::integer;

  return coalesce(new, old);
end;
$$;

create trigger trg_ncr_defect_rollup
after insert or delete or update of defect_code_id on manufacturing.nonconformances for each row
execute function manufacturing.defect_code_rollup ();

----------------------------------------------------------------
-- Engineering rollups
----------------------------------------------------------------
create or replace function manufacturing.bom_lines_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_bom_id uuid;
  v_count integer;
begin
  v_bom_id := coalesce(new.bom_id, old.bom_id);

  select count(*) into v_count from manufacturing.bom_lines where bom_id = v_bom_id;

  update manufacturing.boms
  set line_count = v_count
  where id = v_bom_id
    and line_count is distinct from v_count;

  perform manufacturing.recalc_product_structure (
    array[
      (select product_id from manufacturing.boms where id = v_bom_id),
      (coalesce(new, old)).component_product_id
    ]
  );

  return coalesce(new, old);
end;
$$;

create trigger trg_bom_lines_rollup
after insert or delete or update on manufacturing.bom_lines for each row
execute function manufacturing.bom_lines_rollup ();

create or replace function manufacturing.routing_ops_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_routing_id uuid;
  v_count integer;
  v_setup numeric(12, 2);
  v_run numeric(12, 4);
begin
  v_routing_id := coalesce(new.routing_id, old.routing_id);

  select count(*), coalesce(sum(setup_minutes), 0), coalesce(sum(run_minutes_per_unit), 0)
  into v_count, v_setup, v_run
  from manufacturing.routing_operations
  where routing_id = v_routing_id;

  update manufacturing.routings
  set operation_count = v_count,
    total_setup_minutes = v_setup,
    total_run_minutes_per_unit = v_run
  where id = v_routing_id
    and (operation_count, total_setup_minutes, total_run_minutes_per_unit)
      is distinct from (v_count, v_setup, v_run);

  return coalesce(new, old);
end;
$$;

create trigger trg_routing_ops_rollup
after insert or delete or update on manufacturing.routing_operations for each row
execute function manufacturing.routing_ops_rollup ();

create or replace function manufacturing.family_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  update manufacturing.product_families f
  set product_count = x.n
  from (
      select t.id, count(p.id) as n
      from (
          select (coalesce(new, old)).family_id as id
          union
          select case when tg_op = 'UPDATE' then old.family_id end
        ) t
        left join manufacturing.products p on p.family_id = t.id
      where t.id is not null
      group by t.id
    ) x
  where f.id = x.id
    and f.product_count is distinct from x.n::integer;

  return coalesce(new, old);
end;
$$;

create trigger trg_products_family_rollup
after insert or delete or update of family_id on manufacturing.products for each row
execute function manufacturing.family_rollup ();

create or replace function manufacturing.certifications_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  update manufacturing.operator_certifications
  set is_expired = expires_on is not null and expires_on < current_date
  where id = (coalesce(new, old)).id
    and is_expired is distinct from (expires_on is not null and expires_on < current_date);

  update manufacturing.operators o
  set certification_count = (
    select count(*)
    from manufacturing.operator_certifications c
    where c.operator_id = o.id
      and (c.expires_on is null or c.expires_on >= current_date)
  )
  where o.id = (coalesce(new, old)).operator_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_certifications_rollup
after insert or delete or update on manufacturing.operator_certifications for each row
execute function manufacturing.certifications_rollup ();

create or replace function manufacturing.operator_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  update manufacturing.operators o
  set hours_booked = s.hours,
    units_produced = s.good,
    scrap_rate = case
      when s.good + s.scrap = 0 then null
      else round(100.0 * s.scrap / (s.good + s.scrap), 2)::real
    end,
    updated_at = current_timestamp
  from (
      select coalesce(sum(total_minutes), 0) / 60.0 as hours,
        coalesce(sum(quantity_good), 0) as good,
        coalesce(sum(quantity_scrap), 0) as scrap
      from manufacturing.production_confirmations
      where operator_id = new.operator_id
    ) s
  where o.id = new.operator_id;

  perform manufacturing.recalc_machine_position (array[new.machine_id]);

  return new;
end;
$$;

create trigger trg_confirmations_operator_rollup
after insert on manufacturing.production_confirmations for each row
execute function manufacturing.operator_rollup ();

create trigger trg_products_updated_at
before update on manufacturing.products for each row
execute function manufacturing.set_updated_at ();

create trigger trg_families_updated_at
before update on manufacturing.product_families for each row
execute function manufacturing.set_updated_at ();

create trigger trg_boms_updated_at
before update on manufacturing.boms for each row
execute function manufacturing.set_updated_at ();

create trigger trg_routings_updated_at
before update on manufacturing.routings for each row
execute function manufacturing.set_updated_at ();

create trigger trg_work_centers_updated_at
before update on manufacturing.work_centers for each row
execute function manufacturing.set_updated_at ();

create trigger trg_machines_updated_at
before update on manufacturing.machines for each row
execute function manufacturing.set_updated_at ();

create trigger trg_operators_updated_at
before update on manufacturing.operators for each row
execute function manufacturing.set_updated_at ();

create trigger trg_characteristics_updated_at
before update on manufacturing.quality_characteristics for each row
execute function manufacturing.set_updated_at ();

create trigger trg_defect_codes_updated_at
before update on manufacturing.defect_codes for each row
execute function manufacturing.set_updated_at ();

create trigger trg_settings_updated_at
before update on manufacturing.manufacturing_settings for each row
execute function manufacturing.set_updated_at ();

----------------------------------------------------------------
-- Row actions
----------------------------------------------------------------
create or replace function manufacturing.activate_bom (p_id uuid) returns void language plpgsql security definer
set
  search_path = '' as $$
declare
  v_product uuid;
begin
  select product_id into v_product from manufacturing.boms where id = p_id;

  -- Only one bill can be active, so activating this one retires the
  -- incumbent rather than tripping the unique index.
  update manufacturing.boms
  set status = 'obsolete',
    effective_to = coalesce(effective_to, current_date)
  where product_id = v_product
    and status = 'active'
    and id <> p_id;

  update manufacturing.boms
  set status = 'active',
    approved_by = coalesce(approved_by, auth.uid ()),
    approved_at = coalesce(approved_at, current_timestamp)
  where id = p_id;

  perform manufacturing.roll_up_cost ();
end;
$$;

comment on function manufacturing.activate_bom (uuid) is '{
    "type": "action",
    "resource": "boms",
    "name": "Activate",
    "description": "Make this the bill everything is built to, and retire the previous one.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "confirm": {"title": "Activate this bill?", "description": "The currently active bill for this product is retired and the standard cost is rolled up again. Works orders already released keep the bill they were released against."},
    "success_message": "Bill activated"
}';

create or replace function manufacturing.activate_routing (p_id uuid) returns void language plpgsql security definer
set
  search_path = '' as $$
declare
  v_product uuid;
begin
  select product_id into v_product from manufacturing.routings where id = p_id;

  update manufacturing.routings
  set status = 'obsolete',
    effective_to = coalesce(effective_to, current_date)
  where product_id = v_product
    and status = 'active'
    and id <> p_id;

  update manufacturing.routings set status = 'active' where id = p_id;

  perform manufacturing.roll_up_cost ();
end;
$$;

comment on function manufacturing.activate_routing (uuid) is '{
    "type": "action",
    "resource": "routings",
    "name": "Activate",
    "description": "Make this the routing everything is built to.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "confirm": {"title": "Activate this routing?", "description": "The current routing is retired and labour and overhead costs are rolled up again."},
    "success_message": "Routing activated"
}';

create or replace function manufacturing.release_order_action (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update manufacturing.production_orders set status = 'released' where id = p_id;
end;
$$;

comment on function manufacturing.release_order_action (uuid) is '{
    "type": "action",
    "resource": "production_orders",
    "name": "Release",
    "description": "Freeze the bill and the routing onto this order and send it to the floor.",
    "icon": "Play",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "planned"]}],
    "confirm": {"title": "Release this works order?", "description": "The current bill and routing are copied onto the order. Later revisions will not change what this order is built to."},
    "success_message": "Order released"
}';

create or replace function manufacturing.complete_order (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update manufacturing.production_orders set status = 'completed' where id = p_id;
end;
$$;

comment on function manufacturing.complete_order (uuid) is '{
    "type": "action",
    "resource": "production_orders",
    "name": "Complete",
    "description": "Mark production finished.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "in_progress"}],
    "confirm": {"title": "Complete this works order?", "description": "No further confirmations can be booked once it is closed."},
    "success_message": "Order completed"
}';

create or replace function manufacturing.close_order (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update manufacturing.production_orders set status = 'closed' where id = p_id;
end;
$$;

comment on function manufacturing.close_order (uuid) is '{
    "type": "action",
    "resource": "production_orders",
    "name": "Close",
    "description": "Close the order for good.",
    "icon": "Archive",
    "variant": "secondary",
    "visible": [{"id": "status", "operator": "in", "value": ["completed", "in_progress"]}],
    "confirm": {"title": "Close this works order?", "description": "A closed order cannot be reopened and takes no further bookings."},
    "success_message": "Order closed"
}';

create or replace function manufacturing.cancel_order (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update manufacturing.production_orders
  set status = 'cancelled',
    cancelled_reason = p_reason
  where id = p_id;
end;
$$;

comment on function manufacturing.cancel_order (uuid, varchar) is '{
    "type": "action",
    "resource": "production_orders",
    "name": "Cancel",
    "description": "Cancel the order. Refused once anything has been produced against it.",
    "icon": "Ban",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "planned", "released"]}],
    "confirm": {"title": "Cancel this works order?", "description": "This cannot be undone."},
    "success_message": "Order cancelled"
}';

create or replace function manufacturing.start_operation (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update manufacturing.production_order_operations
  set status = 'running',
    started_at = coalesce(started_at, current_timestamp)
  where id = p_id;
end;
$$;

comment on function manufacturing.start_operation (uuid) is '{
    "type": "action",
    "resource": "production_order_operations",
    "name": "Start",
    "description": "Begin this operation.",
    "icon": "Play",
    "visible": [{"id": "status", "operator": "in", "value": ["pending", "setup", "paused"]}],
    "success_message": "Operation started"
}';

create or replace function manufacturing.set_operation_status (
  p_id uuid,
  p_status manufacturing.operation_status
) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update manufacturing.production_order_operations set status = p_status where id = p_id;
end;
$$;

comment on function manufacturing.set_operation_status (uuid, manufacturing.operation_status) is '{
    "type": "action",
    "resource": "production_order_operations",
    "name": "Set status",
    "icon": "ArrowRightLeft",
    "action_type": "picker"
}';

create or replace function manufacturing.close_downtime (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update manufacturing.downtime_events
  set ended_at = coalesce(ended_at, current_timestamp)
  where id = p_id;
end;
$$;

comment on function manufacturing.close_downtime (uuid) is '{
    "type": "action",
    "resource": "downtime_events",
    "name": "Machine back up",
    "description": "Close the event and put the machine back into service.",
    "icon": "CircleCheck",
    "visible": [{"id": "is_open", "operator": "eq", "value": "true"}],
    "success_message": "Downtime closed"
}';

create or replace function manufacturing.complete_maintenance (p_id uuid, p_work_done varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update manufacturing.maintenance_orders
  set status = 'completed',
    work_done = p_work_done
  where id = p_id;
end;
$$;

comment on function manufacturing.complete_maintenance (uuid, varchar) is '{
    "type": "action",
    "resource": "maintenance_orders",
    "name": "Complete",
    "description": "Sign the job off and reset the service clock on the machine.",
    "icon": "Wrench",
    "visible": [{"id": "status", "operator": "in", "value": ["scheduled", "in_progress", "overdue"]}],
    "confirm": {"title": "Complete this maintenance?", "description": "The machine''s next service date is recalculated from today."},
    "success_message": "Maintenance completed"
}';

create or replace function manufacturing.disposition_ncr (
  p_id uuid,
  p_disposition manufacturing.ncr_disposition
) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update manufacturing.nonconformances
  set disposition = p_disposition,
    status = 'dispositioned'
  where id = p_id;
end;
$$;

comment on function manufacturing.disposition_ncr (uuid, manufacturing.ncr_disposition) is '{
    "type": "action",
    "resource": "nonconformances",
    "name": "Disposition",
    "description": "Decide what happens to the affected material.",
    "icon": "Gavel",
    "action_type": "picker",
    "visible": [{"id": "status", "operator": "in", "value": ["open", "investigating"]}],
    "success_message": "Disposition recorded"
}';

create or replace function manufacturing.close_ncr (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update manufacturing.nonconformances set status = 'closed' where id = p_id;
end;
$$;

comment on function manufacturing.close_ncr (uuid) is '{
    "type": "action",
    "resource": "nonconformances",
    "name": "Close",
    "description": "Close the report. Needs a root cause and a corrective action.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "dispositioned"}],
    "confirm": {"title": "Close this NCR?", "description": "Closing records that the cause was found and something was done about it."},
    "success_message": "NCR closed"
}';

do $$
declare
  f text;
begin
  foreach f in array array[
    'manufacturing.activate_bom(uuid)',
    'manufacturing.activate_routing(uuid)',
    'manufacturing.release_order_action(uuid)',
    'manufacturing.complete_order(uuid)',
    'manufacturing.close_order(uuid)',
    'manufacturing.cancel_order(uuid, varchar)',
    'manufacturing.start_operation(uuid)',
    'manufacturing.set_operation_status(uuid, manufacturing.operation_status)',
    'manufacturing.close_downtime(uuid)',
    'manufacturing.complete_maintenance(uuid, varchar)',
    'manufacturing.disposition_ncr(uuid, manufacturing.ncr_disposition)',
    'manufacturing.close_ncr(uuid)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role;', f);
  end loop;
end;
$$;

grant
execute on function manufacturing.activate_bom (uuid) to "x-admin",
"production-planner";

grant
execute on function manufacturing.activate_routing (uuid) to "x-admin",
"production-planner";

grant
execute on function manufacturing.release_order_action (uuid) to "x-admin",
"production-planner";

grant
execute on function manufacturing.complete_order (uuid) to "x-admin",
"production-planner",
"operator";

grant
execute on function manufacturing.close_order (uuid) to "x-admin",
"production-planner";

grant
execute on function manufacturing.cancel_order (uuid, varchar) to "x-admin",
"production-planner";

grant
execute on function manufacturing.start_operation (uuid) to "x-admin",
"operator";

grant
execute on function manufacturing.set_operation_status (uuid, manufacturing.operation_status) to "x-admin",
"operator";

grant
execute on function manufacturing.close_downtime (uuid) to "x-admin",
"operator";

grant
execute on function manufacturing.complete_maintenance (uuid, varchar) to "x-admin",
"production-planner",
"operator";

grant
execute on function manufacturing.disposition_ncr (uuid, manufacturing.ncr_disposition) to "x-admin",
"inspector";

grant
execute on function manufacturing.close_ncr (uuid) to "x-admin",
"inspector";

----------------------------------------------------------------
-- Forms
----------------------------------------------------------------
-- Copy a bill to a new version so it can be edited without touching
-- what the floor is currently building to.
create or replace function manufacturing.revise_bom (
  p_bom_id uuid,
  p_new_version varchar,
  p_change_note varchar default null
) returns setof manufacturing.boms language plpgsql security definer
set
  search_path = '' as $$
declare
  v_source manufacturing.boms;
  v_new uuid;
begin
  select * into v_source from manufacturing.boms where id = p_bom_id;

  if v_source.id is null then
    raise exception 'That bill does not exist.';
  end if;

  if exists (
    select 1 from manufacturing.boms
    where product_id = v_source.product_id and version = p_new_version
  ) then
    raise exception 'Version % already exists for that product.', p_new_version;
  end if;

  insert into manufacturing.boms (
    product_id, version, status, name, output_quantity, effective_from, change_note, notes
  )
  values (
    v_source.product_id,
    p_new_version,
    'draft',
    v_source.name,
    v_source.output_quantity,
    current_date,
    p_change_note,
    v_source.notes
  )
  returning id into v_new;

  insert into manufacturing.bom_lines (
    bom_id, component_product_id, line_number, quantity_per, scrap_percent,
    operation_sequence, issue_method, is_optional, reference_designator, note
  )
  select v_new,
    component_product_id,
    line_number,
    quantity_per,
    scrap_percent,
    operation_sequence,
    issue_method,
    is_optional,
    reference_designator,
    note
  from manufacturing.bom_lines
  where bom_id = p_bom_id
  order by line_number;

  return query
  select * from manufacturing.boms where id = v_new;
end;
$$;

comment on function manufacturing.revise_bom (uuid, varchar, varchar) is '{
    "type": "form",
    "resource": "boms",
    "name": "Revise",
    "description": "Copy this bill to a new draft version, so it can be changed without disturbing what is being built today.",
    "icon": "GitBranch",
    "success_message": "New version drafted",
    "fields": {
        "sections": [
            {"id": "source", "title": "Source", "fields": ["p_bom_id"]},
            {"id": "new", "title": "New version", "fields": ["p_new_version", "p_change_note"]}
        ],
        "relations": {
            "p_bom_id": {"table": "boms", "column": "id", "display": ["version", "status"]}
        }
    }
}';

-- What a quantity of something actually needs, all the way down.
create or replace function manufacturing.explode_requirements (p_product_id uuid, p_quantity numeric default 1) returns table (
  level integer,
  sku varchar,
  name varchar,
  product_type manufacturing.product_type,
  quantity_required numeric,
  path text
) language sql stable security definer
set
  search_path = '' as $$
  select e.level, e.sku, e.name, e.product_type, e.quantity_required, e.path
  from manufacturing.explode_bom (p_product_id, p_quantity) e;
$$;

comment on function manufacturing.explode_requirements (uuid, numeric) is '{
    "type": "form",
    "resource": "products",
    "name": "Explode bill",
    "description": "Walk the bill to every level and show what a given quantity actually needs.",
    "icon": "ListTree",
    "success_message": "Requirements calculated",
    "fields": {
        "sections": [
            {"id": "what", "title": "What to build", "fields": ["p_product_id", "p_quantity"]}
        ],
        "relations": {
            "p_product_id": {"table": "products", "column": "id", "display": ["sku", "name"]}
        }
    }
}';

-- Raise the works order and release it in one step.
create or replace function manufacturing.plan_production (
  p_product_id uuid,
  p_quantity numeric,
  p_planned_start date default current_date,
  p_planned_end date default null,
  p_priority manufacturing.order_priority default 'normal',
  p_release boolean default true,
  out order_number varchar,
  out components integer,
  out operations integer
) language plpgsql security definer
set
  search_path = '' as $$
declare
  v_order uuid;
begin
  if p_quantity <= 0 then
    raise exception 'A works order needs a positive quantity.';
  end if;

  if not exists (
    select 1 from manufacturing.boms
    where product_id = p_product_id and status = 'active'
  ) then
    raise exception 'That product has no active bill of material.'
      using hint = 'Activate one before planning production.';
  end if;

  insert into manufacturing.production_orders (
    product_id, quantity_ordered, planned_start, planned_end, priority, status
  )
  values (
    p_product_id,
    p_quantity,
    p_planned_start,
    coalesce(p_planned_end, p_planned_start + 7),
    p_priority,
    'planned'
  )
  returning id into v_order;

  if p_release then
    update manufacturing.production_orders set status = 'released' where id = v_order;
  end if;

  select o.order_number, o.component_count, o.operation_count
  into order_number, components, operations
  from manufacturing.production_orders o
  where o.id = v_order;
end;
$$;

comment on function manufacturing.plan_production (
  uuid,
  numeric,
  date,
  date,
  manufacturing.order_priority,
  boolean
) is '{
    "type": "form",
    "resource": "production_orders",
    "name": "Plan production",
    "description": "Raise a works order and, unless you say otherwise, release it so the bill and routing are frozen onto it straight away.",
    "icon": "ClipboardPlus",
    "success_message": "Works order raised",
    "fields": {
        "sections": [
            {"id": "what", "title": "What to make", "fields": ["p_product_id", "p_quantity", "p_priority"]},
            {"id": "when", "title": "When", "fields": ["p_planned_start", "p_planned_end"]},
            {"id": "options", "title": "Options", "fields": ["p_release"]}
        ],
        "relations": {
            "p_product_id": {"table": "products", "column": "id", "display": ["sku", "name"]}
        }
    }
}';

-- Book work from the floor in one call rather than three.
create or replace function manufacturing.confirm_production (
  p_operation_id uuid,
  p_operator_id uuid,
  p_quantity_good numeric,
  p_quantity_scrap numeric default 0,
  p_run_minutes numeric default 0,
  p_setup_minutes numeric default 0,
  p_scrap_reason varchar default null,
  p_is_final boolean default false
) returns setof manufacturing.production_confirmations language plpgsql security definer
set
  search_path = '' as $$
declare
  v_op manufacturing.production_order_operations;
  v_id uuid;
begin
  select * into v_op from manufacturing.production_order_operations where id = p_operation_id;

  if v_op.id is null then
    raise exception 'That operation does not exist.';
  end if;

  insert into manufacturing.production_confirmations (
    production_order_id, operation_id, operator_id, machine_id,
    quantity_good, quantity_scrap, setup_minutes, run_minutes, scrap_reason, is_final
  )
  values (
    v_op.production_order_id,
    p_operation_id,
    p_operator_id,
    v_op.machine_id,
    p_quantity_good,
    p_quantity_scrap,
    p_setup_minutes,
    p_run_minutes,
    p_scrap_reason,
    p_is_final
  )
  returning id into v_id;

  return query
  select * from manufacturing.production_confirmations where id = v_id;
end;
$$;

comment on function manufacturing.confirm_production (
  uuid,
  uuid,
  numeric,
  numeric,
  numeric,
  numeric,
  varchar,
  boolean
) is '{
    "type": "form",
    "resource": "production_order_operations",
    "name": "Confirm work",
    "description": "Declare output and book time against this operation.",
    "icon": "ClipboardCheck",
    "success_message": "Work confirmed",
    "fields": {
        "sections": [
            {"id": "what", "title": "Output", "fields": ["p_operation_id", "p_quantity_good", "p_quantity_scrap", "p_scrap_reason"]},
            {"id": "time", "title": "Time", "fields": ["p_setup_minutes", "p_run_minutes"]},
            {"id": "who", "title": "Who", "fields": ["p_operator_id", "p_is_final"]}
        ],
        "relations": {
            "p_operation_id": {"table": "production_order_operations", "column": "id", "display": ["sequence_number", "name"]},
            "p_operator_id": {"table": "operators", "column": "id", "display": ["badge_number", "name"]}
        }
    }
}';

revoke all on function manufacturing.revise_bom (uuid, varchar, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

revoke all on function manufacturing.explode_requirements (uuid, numeric)
from
  public,
  anon,
  authenticated,
  service_role;

revoke all on function manufacturing.plan_production (
  uuid,
  numeric,
  date,
  date,
  manufacturing.order_priority,
  boolean
)
from
  public,
  anon,
  authenticated,
  service_role;

revoke all on function manufacturing.confirm_production (
  uuid,
  uuid,
  numeric,
  numeric,
  numeric,
  numeric,
  varchar,
  boolean
)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function manufacturing.revise_bom (uuid, varchar, varchar) to "x-admin",
"production-planner";

grant
execute on function manufacturing.explode_requirements (uuid, numeric) to "x-admin",
"production-planner",
"operator",
"inspector";

grant
execute on function manufacturing.plan_production (
  uuid,
  numeric,
  date,
  date,
  manufacturing.order_priority,
  boolean
) to "x-admin",
"production-planner";

grant
execute on function manufacturing.confirm_production (
  uuid,
  uuid,
  numeric,
  numeric,
  numeric,
  numeric,
  varchar,
  boolean
) to "x-admin",
"operator";

----------------------------------------------------------------
-- Templates
----------------------------------------------------------------
create or replace view manufacturing.work_centers_template
with
  (security_invoker = true) as
select
  t.code,
  t.name,
  t.work_center_type,
  t.capacity_hours_per_day,
  t.labour_rate_per_hour,
  t.overhead_rate_per_hour
from
  (
    values
      (
        'WC-SAW',
        'Sawing',
        'fabrication',
        16,
        26.00,
        18.00
      ),
      (
        'WC-CNC',
        'CNC machining',
        'machining',
        20,
        38.00,
        32.00
      ),
      (
        'WC-MILL',
        'Manual milling',
        'machining',
        16,
        32.00,
        24.00
      ),
      (
        'WC-WELD',
        'Welding',
        'fabrication',
        16,
        34.00,
        22.00
      ),
      (
        'WC-PAINT',
        'Paint and finishing',
        'finishing',
        8,
        28.00,
        20.00
      ),
      (
        'WC-ASM',
        'Assembly',
        'assembly',
        24,
        30.00,
        20.00
      ),
      (
        'WC-TEST',
        'Test and inspection',
        'inspection',
        16,
        36.00,
        16.00
      ),
      ('WC-PACK', 'Packing', 'packing', 16, 22.00, 12.00)
  ) as t (
    code,
    name,
    work_center_type,
    capacity_hours_per_day,
    labour_rate_per_hour,
    overhead_rate_per_hour
  )
where
  not exists (
    select
      1
    from
      manufacturing.work_centers w
    where
      w.code = t.code
  );

comment on view manufacturing.work_centers_template is '{"type": "template", "name": "Standard Work Centres", "description": "Eight work centres covering a typical fabrication and assembly shop, with indicative rates. Apply to manufacturing.work_centers.", "target_table": "work_centers"}';

create or replace view manufacturing.defect_codes_template
with
  (security_invoker = true) as
select
  t.code,
  t.name,
  t.description,
  t.severity,
  t.category
from
  (
    values
      (
        'DIM-OUT',
        'Dimension out of tolerance',
        'Measured feature outside the drawing limits',
        'major',
        'Dimensional'
      ),
      (
        'SURF-SCR',
        'Surface scratch',
        'Cosmetic damage to a finished face',
        'minor',
        'Cosmetic'
      ),
      (
        'WELD-POR',
        'Weld porosity',
        'Gas inclusion visible in the weld',
        'major',
        'Process'
      ),
      (
        'MAT-WRONG',
        'Wrong material',
        'Part made from the wrong stock',
        'critical',
        'Material'
      ),
      (
        'ASM-MISS',
        'Missing component',
        'Assembly short of a component',
        'critical',
        'Assembly'
      ),
      (
        'FIN-RUN',
        'Paint run',
        'Finish applied too heavily',
        'minor',
        'Cosmetic'
      ),
      (
        'THR-DAM',
        'Damaged thread',
        'Thread stripped or crossed',
        'major',
        'Mechanical'
      ),
      (
        'LEAK',
        'Leak on test',
        'Failed pressure or leak test',
        'critical',
        'Functional'
      ),
      (
        'LBL-ERR',
        'Labelling error',
        'Wrong or missing identification',
        'minor',
        'Documentation'
      ),
      (
        'CONT',
        'Contamination',
        'Foreign matter present',
        'major',
        'Material'
      )
  ) as t (code, name, description, severity, category)
where
  not exists (
    select
      1
    from
      manufacturing.defect_codes d
    where
      d.code = t.code
  );

comment on view manufacturing.defect_codes_template is '{"type": "template", "name": "Standard Defect Codes", "description": "Ten defect codes covering dimensional, cosmetic, material and functional failures. Apply to manufacturing.defect_codes.", "target_table": "defect_codes"}';

create or replace view manufacturing.product_families_template
with
  (security_invoker = true) as
select
  t.code,
  t.name,
  t.description
from
  (
    values
      ('FG', 'Finished Goods', 'Shipped to customers'),
      (
        'SA',
        'Sub-assemblies',
        'Built to stock and consumed internally'
      ),
      ('MC', 'Machined Parts', 'Made from bar and plate'),
      (
        'FB',
        'Fabrications',
        'Welded and formed structures'
      ),
      (
        'RM',
        'Raw Material',
        'Bar, plate, sheet and granulate'
      ),
      ('BO', 'Bought-out Parts', 'Purchased complete'),
      ('CN', 'Consumables', 'Used up in production')
  ) as t (code, name, description)
where
  not exists (
    select
      1
    from
      manufacturing.product_families f
    where
      f.code = t.code
  );

comment on view manufacturing.product_families_template is '{"type": "template", "name": "Default Families", "description": "Seven families covering the usual split from raw material to finished goods. Apply to manufacturing.product_families.", "target_table": "product_families"}';

revoke all on manufacturing.work_centers_template,
manufacturing.defect_codes_template,
manufacturing.product_families_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on manufacturing.work_centers_template,
  manufacturing.defect_codes_template,
  manufacturing.product_families_template to "x-admin";

----------------------------------------------------------------
-- The structure, browsable
--
-- A view surfaced as a resource rather than a report, because the
-- multi-level bill is something people navigate rather than print.
-- The tree layout hangs off parent_product_id.
----------------------------------------------------------------
create or replace view manufacturing.bom_structure
with
  (security_invoker = true) as
select
  bl.id,
  b.product_id as parent_product_id,
  parent.sku as parent_sku,
  parent.name as parent_name,
  bl.component_product_id,
  child.sku,
  child.name,
  child.product_type,
  child.bom_level,
  b.version as bom_version,
  b.status as bom_status,
  bl.quantity_per,
  bl.scrap_percent,
  bl.operation_sequence,
  bl.issue_method,
  bl.is_optional,
  '/manufacturing/resource/products/' || child.id || '/detail' as link
from
  manufacturing.bom_lines bl
  join manufacturing.boms b on b.id = bl.bom_id
  join manufacturing.products parent on parent.id = b.product_id
  join manufacturing.products child on child.id = bl.component_product_id
where
  b.status = 'active';

comment on view manufacturing.bom_structure is '{
    "icon": "ListTree",
    "name": "Product Structure",
    "description": "The active bills, arranged by what goes into what.",
    "collapsible_group": "Engineering",
    "display": "block",
    "primary_view": "tree",
    "views": [
        {"id": "tree", "name": "Structure", "type": "tree", "parent": "parent_product_id", "title": "sku", "secondary": "name"},
        {"id": "list", "name": "Flat List", "type": "list", "title": "sku", "description": "parent_sku", "field_1": "quantity_per", "field_2": "product_type", "read_only": true}
    ],
    "filter_presets": [
        {"id": "scrapped", "name": "With Scrap Allowance", "filters": [{"id": "scrap_percent", "value": "0", "operator": "gt"}]},
        {"id": "optional", "name": "Optional", "filters": [{"id": "is_optional", "value": "true", "operator": "eq"}]}
    ],
    "query": {"sort": [{"id": "parent_sku", "desc": false}]}
}';

comment on column manufacturing.bom_structure.quantity_per is '{"name": "Qty Per", "aggregate": "sum"}';

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view manufacturing.where_used_report
with
  (security_invoker = true) as
select
  bl.id,
  child.sku as component_sku,
  child.name as component_name,
  child.product_type,
  parent.sku as used_in_sku,
  parent.name as used_in_name,
  b.version as bom_version,
  bl.quantity_per,
  bl.scrap_percent,
  child.where_used_count,
  child.bom_level
from
  manufacturing.bom_lines bl
  join manufacturing.boms b on b.id = bl.bom_id
  and b.status = 'active'
  join manufacturing.products parent on parent.id = b.product_id
  join manufacturing.products child on child.id = bl.component_product_id
order by
  child.sku,
  parent.sku;

comment on view manufacturing.where_used_report is '{"type": "report", "name": "Where Used", "description": "Every bill a component appears on — the question asked before any engineering change"}';

create or replace view manufacturing.cost_rollup_report
with
  (security_invoker = true) as
select
  p.id,
  p.sku,
  p.name,
  f.name as family,
  p.product_type,
  p.bom_level,
  p.material_cost,
  p.labour_cost,
  p.overhead_cost,
  p.standard_cost,
  p.component_count,
  p.where_used_count,
  round(
    100.0 * p.material_cost / nullif(p.standard_cost, 0),
    1
  ) as material_share,
  p.lot_size,
  p.yield_percent
from
  manufacturing.products p
  left join manufacturing.product_families f on f.id = p.family_id
where
  p.status = 'active'
order by
  p.bom_level,
  p.sku;

comment on view manufacturing.cost_rollup_report is '{"type": "report", "name": "Standard Cost Rollup", "description": "What every part costs, split into material, labour and overhead"}';

create or replace view manufacturing.production_schedule_report
with
  (security_invoker = true) as
select
  o.id,
  o.order_number,
  p.sku,
  p.name as product,
  o.status,
  o.priority,
  o.quantity_ordered,
  o.quantity_started,
  o.quantity_produced,
  o.quantity_scrapped,
  o.quantity_remaining,
  o.yield_percent,
  o.planned_start,
  o.planned_end,
  greatest(current_date - o.planned_end, 0) as days_late,
  o.operation_count,
  round(o.standard_hours, 2) as standard_hours,
  round(o.actual_hours, 2) as actual_hours,
  coalesce(o.sales_reference, '—') as sales_reference
from
  manufacturing.production_orders o
  join manufacturing.products p on p.id = o.product_id
where
  o.status not in ('closed', 'cancelled')
order by
  o.planned_end,
  o.priority desc;

comment on view manufacturing.production_schedule_report is '{"type": "report", "name": "Production Schedule", "description": "Every open works order, when it is due and how far behind it is", "template": true}';

create or replace view manufacturing.work_order_cost_report
with
  (security_invoker = true) as
select
  o.id,
  o.order_number,
  p.sku,
  p.name as product,
  o.status,
  o.quantity_ordered,
  o.quantity_produced,
  o.material_cost,
  o.labour_cost,
  o.overhead_cost,
  o.total_cost,
  round(o.total_cost / nullif(o.quantity_produced, 0), 4) as actual_unit_cost,
  p.standard_cost as standard_unit_cost,
  round(
    o.total_cost / nullif(o.quantity_produced, 0) - p.standard_cost,
    4
  ) as unit_variance,
  round(o.standard_hours, 2) as standard_hours,
  round(o.actual_hours, 2) as actual_hours,
  round(o.actual_hours - o.standard_hours, 2) as hours_variance
from
  manufacturing.production_orders o
  join manufacturing.products p on p.id = o.product_id
where
  o.status in ('completed', 'closed')
order by
  o.actual_end desc nulls last;

comment on view manufacturing.work_order_cost_report is '{"type": "report", "name": "Works Order Costing", "description": "What each finished order actually cost against what it should have"}';

create or replace view manufacturing.shop_floor_report
with
  (security_invoker = true) as
select
  op.id,
  o.order_number,
  p.sku,
  op.sequence_number,
  op.name as operation,
  wc.code as work_center,
  coalesce(m.code, '—') as machine,
  coalesce(opr.name, 'Unassigned') as operator,
  op.status,
  op.quantity_completed,
  op.quantity_scrapped,
  round(
    op.planned_setup_minutes + op.planned_run_minutes,
    2
  ) as planned_minutes,
  round(op.actual_minutes, 2) as actual_minutes,
  op.efficiency,
  op.scheduled_start,
  op.completed_at
from
  manufacturing.production_order_operations op
  join manufacturing.production_orders o on o.id = op.production_order_id
  join manufacturing.products p on p.id = o.product_id
  join manufacturing.work_centers wc on wc.id = op.work_center_id
  left join manufacturing.machines m on m.id = op.machine_id
  left join manufacturing.operators opr on opr.id = op.assigned_operator_id
order by
  op.scheduled_start nulls last,
  op.sequence_number;

comment on view manufacturing.shop_floor_report is '{"type": "report", "name": "Shop Floor", "description": "Every operation, where it is, who has it and how it ran against standard"}';

create or replace view manufacturing.machine_downtime_report
with
  (security_invoker = true) as
select
  d.id,
  m.code as machine,
  m.name as machine_name,
  wc.code as work_center,
  d.reason,
  d.started_at,
  d.ended_at,
  d.duration_minutes,
  round(d.duration_minutes / 60.0, 2) as duration_hours,
  d.is_open,
  coalesce(o.order_number, '—') as works_order,
  coalesce(opr.name, '—') as reported_by,
  coalesce(d.description, '') as description
from
  manufacturing.downtime_events d
  join manufacturing.machines m on m.id = d.machine_id
  left join manufacturing.work_centers wc on wc.id = d.work_center_id
  left join manufacturing.production_orders o on o.id = d.production_order_id
  left join manufacturing.operators opr on opr.id = d.reported_by
order by
  d.started_at desc;

comment on view manufacturing.machine_downtime_report is '{"type": "report", "name": "Downtime", "description": "Every stoppage, how long it lasted and what caused it"}';

create or replace view manufacturing.scrap_report
with
  (security_invoker = true) as
select
  cf.id,
  cf.confirmation_number,
  o.order_number,
  p.sku,
  p.name as product,
  coalesce(op.sequence_number, 0) as operation_sequence,
  coalesce(op.name, '—') as operation,
  coalesce(wc.code, '—') as work_center,
  coalesce(opr.name, '—') as operator,
  cf.confirmed_at,
  cf.quantity_good,
  cf.quantity_scrap,
  round(
    100.0 * cf.quantity_scrap / nullif(cf.quantity_good + cf.quantity_scrap, 0),
    2
  ) as scrap_rate,
  coalesce(cf.scrap_reason, '') as scrap_reason
from
  manufacturing.production_confirmations cf
  join manufacturing.production_orders o on o.id = cf.production_order_id
  join manufacturing.products p on p.id = o.product_id
  left join manufacturing.production_order_operations op on op.id = cf.operation_id
  left join manufacturing.work_centers wc on wc.id = op.work_center_id
  left join manufacturing.operators opr on opr.id = cf.operator_id
where
  cf.quantity_scrap > 0
order by
  cf.confirmed_at desc;

comment on view manufacturing.scrap_report is '{"type": "report", "name": "Scrap Analysis", "description": "Every unit scrapped, where it happened and what was said about it"}';

create or replace view manufacturing.quality_report
with
  (security_invoker = true) as
select
  n.id,
  n.ncr_number,
  coalesce(o.order_number, '—') as works_order,
  coalesce(p.sku, '—') as sku,
  n.title,
  n.status,
  n.disposition,
  n.severity,
  coalesce(dc.code, '—') as defect_code,
  n.quantity_affected,
  n.cost_impact,
  n.raised_at,
  n.dispositioned_at,
  n.closed_at,
  n.age_days
from
  manufacturing.nonconformances n
  left join manufacturing.production_orders o on o.id = n.production_order_id
  left join manufacturing.products p on p.id = n.product_id
  left join manufacturing.defect_codes dc on dc.id = n.defect_code_id
order by
  n.raised_at desc;

comment on view manufacturing.quality_report is '{"type": "report", "name": "Non-conformance Register", "description": "Every NCR, its disposition and how long it stayed open"}';

create or replace view manufacturing.operator_productivity_report
with
  (security_invoker = true) as
select
  o.id,
  o.badge_number,
  o.name,
  o.shift,
  o.certification_count,
  round(o.hours_booked, 2) as hours_booked,
  o.units_produced,
  o.scrap_rate,
  round(o.units_produced / nullif(o.hours_booked, 0), 2) as units_per_hour,
  (
    select
      count(*)
    from
      manufacturing.production_confirmations cf
    where
      cf.operator_id = o.id
  ) as confirmations,
  (
    select
      round(avg(op.efficiency)::numeric, 1)
    from
      manufacturing.production_confirmations cf
      join manufacturing.production_order_operations op on op.id = cf.operation_id
    where
      cf.operator_id = o.id
      and op.efficiency is not null
  ) as avg_efficiency
from
  manufacturing.operators o
where
  o.is_active
order by
  o.units_produced desc;

comment on view manufacturing.operator_productivity_report is '{"type": "report", "name": "Operator Productivity", "description": "Hours booked, units made and scrap rate per operator"}';

create or replace view manufacturing.capacity_report
with
  (security_invoker = true) as
select
  wc.id,
  wc.code,
  wc.name,
  wc.work_center_type,
  wc.is_bottleneck,
  wc.capacity_hours_per_day,
  wc.efficiency_percent,
  -- efficiency_percent is a PERCENTAGE domain over real, and there is
  -- no round(double precision, integer) in Postgres.
  round(
    (
      wc.capacity_hours_per_day * 5 * wc.efficiency_percent / 100
    )::numeric,
    2
  ) as effective_weekly_hours,
  wc.open_operations,
  round(wc.scheduled_hours, 2) as scheduled_hours,
  wc.utilisation,
  wc.machine_count,
  (
    select
      count(*)
    from
      manufacturing.machines m
    where
      m.work_center_id = wc.id
      and m.status = 'down'
  ) as machines_down
from
  manufacturing.work_centers wc
where
  wc.is_active
order by
  wc.utilisation desc nulls last;

comment on view manufacturing.capacity_report is '{"type": "report", "name": "Capacity and Load", "description": "What each work centre can do against what is queued on it"}';

revoke all on manufacturing.bom_structure,
manufacturing.where_used_report,
manufacturing.cost_rollup_report,
manufacturing.production_schedule_report,
manufacturing.work_order_cost_report,
manufacturing.shop_floor_report,
manufacturing.machine_downtime_report,
manufacturing.scrap_report,
manufacturing.quality_report,
manufacturing.operator_productivity_report,
manufacturing.capacity_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on manufacturing.bom_structure,
  manufacturing.where_used_report,
  manufacturing.cost_rollup_report,
  manufacturing.production_schedule_report,
  manufacturing.work_order_cost_report,
  manufacturing.shop_floor_report,
  manufacturing.machine_downtime_report,
  manufacturing.scrap_report,
  manufacturing.quality_report,
  manufacturing.operator_productivity_report,
  manufacturing.capacity_report to "x-admin";

grant
select
  on manufacturing.bom_structure,
  manufacturing.where_used_report,
  manufacturing.cost_rollup_report,
  manufacturing.production_schedule_report,
  manufacturing.work_order_cost_report,
  manufacturing.shop_floor_report,
  manufacturing.capacity_report,
  manufacturing.scrap_report to "production-planner";

-- The floor and the inspector get the operational reports. Neither
-- gets the two that put a price on anything.
grant
select
  on manufacturing.bom_structure,
  manufacturing.production_schedule_report,
  manufacturing.shop_floor_report,
  manufacturing.machine_downtime_report,
  manufacturing.scrap_report,
  manufacturing.operator_productivity_report to "operator";

grant
select
  on manufacturing.bom_structure,
  manufacturing.where_used_report,
  manufacturing.scrap_report,
  manufacturing.quality_report,
  manufacturing.shop_floor_report to "inspector";

----------------------------------------------------------------
-- Precomputed production history
--
-- Refresh with:
--   refresh materialized view concurrently manufacturing.production_summary;
----------------------------------------------------------------
create materialized view manufacturing.production_summary as
select
  (
    wc.id::text || '-' || to_char(date_trunc('month', cf.confirmed_at), 'YYYYMM')
  ) as id,
  wc.id as work_center_id,
  wc.code as work_center,
  date_trunc('month', cf.confirmed_at)::date as month_start,
  to_char(cf.confirmed_at, 'Mon YY') as month,
  count(*) as confirmations,
  count(distinct cf.production_order_id) as orders_touched,
  coalesce(sum(cf.quantity_good), 0) as units_good,
  coalesce(sum(cf.quantity_scrap), 0) as units_scrap,
  round(
    100.0 * coalesce(sum(cf.quantity_scrap), 0) / nullif(sum(cf.quantity_good + cf.quantity_scrap), 0),
    2
  ) as scrap_rate,
  round(coalesce(sum(cf.total_minutes), 0) / 60.0, 2) as hours_booked,
  round(
    coalesce(
      sum(cf.total_minutes / 60.0 * wc.labour_rate_per_hour),
      0
    ),
    2
  ) as labour_cost
from
  manufacturing.production_confirmations cf
  join manufacturing.production_order_operations op on op.id = cf.operation_id
  join manufacturing.work_centers wc on wc.id = op.work_center_id
group by
  wc.id,
  wc.code,
  date_trunc('month', cf.confirmed_at),
  to_char(cf.confirmed_at, 'Mon YY');

create unique index idx_mfg_production_summary_id on manufacturing.production_summary (id);

create index idx_mfg_production_summary_month on manufacturing.production_summary (month_start);

comment on materialized view manufacturing.production_summary is '{
    "icon": "ChartNoAxesCombined",
    "name": "Production History",
    "description": "Precomputed monthly output per work centre. Refresh with: refresh materialized view concurrently manufacturing.production_summary;",
    "collapsible_group": "Insights",
    "display": "block",
    "primary_view": "list",
    "views": [
        {"id": "list", "name": "By Month", "type": "list", "title": "month", "description": "work_center", "field_1": "units_good", "field_2": "scrap_rate"}
    ],
    "filter_presets": [
        {"id": "high_scrap", "name": "High Scrap Months", "filters": [{"id": "scrap_rate", "value": "5", "operator": "gt"}]}
    ],
    "query": {"sort": [{"id": "month_start", "desc": true}]}
}';

comment on column manufacturing.production_summary.units_good is '{"name": "Good", "aggregate": "sum"}';

revoke all on manufacturing.production_summary
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on manufacturing.production_summary to "x-admin",
  "production-planner";

----------------------------------------------------------------
-- Dashboard widgets
----------------------------------------------------------------
create or replace view manufacturing.open_orders_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'clipboard-list' as icon,
  'works orders on the floor' as label
from
  manufacturing.production_orders
where
  status in ('released', 'in_progress');

create or replace view manufacturing.late_orders_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'triangle-alert' as icon,
  'orders past their due date' as label
from
  manufacturing.production_orders
where
  status in ('released', 'in_progress')
  and planned_end < current_date;

create or replace view manufacturing.machines_down_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'octagon-alert' as icon,
  'machines down right now' as label
from
  manufacturing.machines
where
  status = 'down';

create or replace view manufacturing.open_ncr_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'shield-alert' as icon,
  'non-conformances open' as label
from
  manufacturing.nonconformances
where
  status in ('open', 'investigating');

create or replace view manufacturing.maintenance_due_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'wrench' as icon,
  'maintenance jobs due' as label
from
  manufacturing.maintenance_orders
where
  status in ('scheduled', 'overdue', 'in_progress');

create or replace view manufacturing.good_vs_scrap
with
  (security_invoker = true) as
select
  round(coalesce(sum(quantity_good), 0), 0) as primary,
  round(coalesce(sum(quantity_scrap), 0), 0) as secondary,
  'Good (30d)' as primary_label,
  'Scrap (30d)' as secondary_label
from
  manufacturing.production_confirmations
where
  confirmed_at >= current_date - 30;

create or replace view manufacturing.planned_vs_actual_hours
with
  (security_invoker = true) as
select
  round(coalesce(sum(standard_hours), 0), 0) as primary,
  round(coalesce(sum(actual_hours), 0), 0) as secondary,
  'Standard hours' as primary_label,
  'Actual hours' as secondary_label
from
  manufacturing.production_orders
where
  status in ('completed', 'closed');

create or replace view manufacturing.first_pass_yield
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * coalesce(sum(quantity_good), 0) / nullif(sum(quantity_good + quantity_scrap), 0),
    1
  ) as percent
from
  manufacturing.production_confirmations
where
  confirmed_at >= current_date - 90;

create or replace view manufacturing.on_time_completion
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        actual_end::date <= planned_end
    ) / nullif(count(*), 0),
    1
  ) as percent
from
  manufacturing.production_orders
where
  status in ('completed', 'closed')
  and actual_end is not null;

create or replace view manufacturing.order_progress
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status in ('completed', 'closed')
  ) as current,
  count(*) as total,
  json_build_array(
    json_build_object(
      'label',
      'Planned',
      'value',
      count(*) filter (
        where
          status in ('draft', 'planned')
      )
    ),
    json_build_object(
      'label',
      'Released',
      'value',
      count(*) filter (
        where
          status = 'released'
      )
    ),
    json_build_object(
      'label',
      'Running',
      'value',
      count(*) filter (
        where
          status = 'in_progress'
      )
    ),
    json_build_object(
      'label',
      'Done',
      'value',
      count(*) filter (
        where
          status in ('completed', 'closed')
      )
    )
  ) as segments
from
  manufacturing.production_orders
where
  created_at >= current_date - 90;

create or replace view manufacturing.structure_overview
with
  (security_invoker = true) as
select
  count(*) as value,
  'Active parts' as label,
  'package' as icon,
  json_build_array(
    json_build_object(
      'label',
      'Made here',
      'value',
      count(*) filter (
        where
          product_type = 'make'
      ),
      'variant',
      'info'
    ),
    json_build_object(
      'label',
      'Bought in',
      'value',
      count(*) filter (
        where
          product_type = 'buy'
      ),
      'variant',
      'secondary'
    ),
    json_build_object(
      'label',
      'Phantom',
      'value',
      count(*) filter (
        where
          product_type = 'phantom'
      ),
      'variant',
      'warning'
    ),
    json_build_object(
      'label',
      'Deepest level',
      'value',
      coalesce(max(bom_level), 0),
      'variant',
      'default'
    )
  ) as breakdown
from
  manufacturing.products
where
  status = 'active';

create or replace view manufacturing.factory_pulse
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Open orders',
      'value',
      (
        select
          count(*)
        from
          manufacturing.production_orders
        where
          status in ('released', 'in_progress')
      ),
      'icon',
      'clipboard-list'
    ),
    json_build_object(
      'label',
      'Running now',
      'value',
      (
        select
          count(*)
        from
          manufacturing.production_order_operations
        where
          status = 'running'
      ),
      'icon',
      'play'
    ),
    json_build_object(
      'label',
      'Machines down',
      'value',
      (
        select
          count(*)
        from
          manufacturing.machines
        where
          status = 'down'
      ),
      'icon',
      'octagon-alert'
    ),
    json_build_object(
      'label',
      'Open NCRs',
      'value',
      (
        select
          count(*)
        from
          manufacturing.nonconformances
        where
          status in ('open', 'investigating')
      ),
      'icon',
      'shield-alert'
    ),
    json_build_object(
      'label',
      'Bottlenecks',
      'value',
      (
        select
          count(*)
        from
          manufacturing.work_centers
        where
          is_bottleneck
      ),
      'icon',
      'funnel'
    ),
    json_build_object(
      'label',
      'Operators on shift',
      'value',
      (
        select
          count(*)
        from
          manufacturing.operators
        where
          is_active
      ),
      'icon',
      'hard-hat'
    )
  ) as metrics;

create or replace view manufacturing.orders_due_next
with
  (security_invoker = true) as
select
  o.order_number,
  p.sku,
  o.quantity_remaining as remaining,
  to_char(o.planned_end, 'Mon DD') as due,
  o.priority,
  '/manufacturing/resource/production_orders/' || o.id || '/detail' as link
from
  manufacturing.production_orders o
  join manufacturing.products p on p.id = o.product_id
where
  o.status in ('released', 'in_progress')
order by
  o.planned_end
limit
  10;

create or replace view manufacturing.running_operations
with
  (security_invoker = true) as
select
  o.order_number,
  op.name as operation,
  wc.code as work_center,
  coalesce(opr.name, 'Unassigned') as operator,
  op.status,
  '/manufacturing/resource/production_order_operations/' || op.id || '/detail' as link
from
  manufacturing.production_order_operations op
  join manufacturing.production_orders o on o.id = op.production_order_id
  join manufacturing.work_centers wc on wc.id = op.work_center_id
  left join manufacturing.operators opr on opr.id = op.assigned_operator_id
where
  op.status in ('setup', 'running', 'paused')
order by
  op.started_at desc nulls last
limit
  10;

create or replace view manufacturing.work_center_scorecard
with
  (security_invoker = true) as
select
  wc.name as work_center,
  wc.open_operations as open_ops,
  round(wc.scheduled_hours, 1) as queued_hours,
  wc.utilisation,
  wc.machine_count as machines,
  '/manufacturing/resource/work_centers/' || wc.id || '/detail' as link
from
  manufacturing.work_centers wc
where
  wc.is_active
order by
  wc.scheduled_hours desc
limit
  10;

create or replace view manufacturing.ncr_queue
with
  (security_invoker = true) as
select
  n.title as title,
  n.ncr_number || ' — ' || n.severity as description,
  'shield-alert' as icon,
  case n.severity
    when 'critical' then 'destructive'
    when 'major' then 'warning'
    else 'secondary'
  end as variant,
  '/manufacturing/resource/nonconformances/' || n.id || '/detail' as link
from
  manufacturing.nonconformances n
where
  n.status in ('open', 'investigating')
order by
  n.severity desc,
  n.raised_at
limit
  10;

create or replace view manufacturing.downtime_watchlist
with
  (security_invoker = true) as
select
  m.name as title,
  coalesce(d.description, d.reason::text) as description,
  'octagon-alert' as icon,
  'destructive' as variant,
  d.reason::text as field_1,
  to_char(d.started_at, 'Mon DD HH24:MI') as field_2,
  '/manufacturing/resource/downtime_events/' || d.id || '/detail' as link
from
  manufacturing.downtime_events d
  join manufacturing.machines m on m.id = d.machine_id
where
  d.is_open
order by
  d.started_at
limit
  10;

create or replace view manufacturing.recent_floor_activity
with
  (security_invoker = true) as
select
  coalesce(opr.name, 'Floor') as actor,
  case
    when cf.quantity_scrap > 0 then 'scrapped ' || cf.quantity_scrap || ' on'
    else 'confirmed ' || cf.quantity_good || ' on'
  end as action,
  o.order_number as entity,
  to_char(cf.confirmed_at, 'Mon DD, HH24:MI') as date,
  '/manufacturing/resource/production_orders/' || o.id || '/detail' as link
from
  manufacturing.production_confirmations cf
  join manufacturing.production_orders o on o.id = cf.production_order_id
  left join manufacturing.operators opr on opr.id = cf.operator_id
order by
  cf.confirmed_at desc
limit
  10;

create or replace view manufacturing.top_scrap_products
with
  (security_invoker = true) as
select
  p.sku as name,
  round(sum(cf.quantity_scrap), 0) as value,
  p.name as label,
  '/manufacturing/resource/products/' || p.id || '/detail' as link
from
  manufacturing.production_confirmations cf
  join manufacturing.production_orders o on o.id = cf.production_order_id
  join manufacturing.products p on p.id = o.product_id
where
  cf.quantity_scrap > 0
group by
  p.id,
  p.sku,
  p.name
order by
  sum(cf.quantity_scrap) desc
limit
  10;

revoke all on manufacturing.open_orders_count,
manufacturing.late_orders_count,
manufacturing.machines_down_count,
manufacturing.open_ncr_count,
manufacturing.maintenance_due_count,
manufacturing.good_vs_scrap,
manufacturing.planned_vs_actual_hours,
manufacturing.first_pass_yield,
manufacturing.on_time_completion,
manufacturing.order_progress,
manufacturing.structure_overview,
manufacturing.factory_pulse,
manufacturing.orders_due_next,
manufacturing.running_operations,
manufacturing.work_center_scorecard,
manufacturing.ncr_queue,
manufacturing.downtime_watchlist,
manufacturing.recent_floor_activity,
manufacturing.top_scrap_products
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on manufacturing.open_orders_count,
  manufacturing.late_orders_count,
  manufacturing.machines_down_count,
  manufacturing.open_ncr_count,
  manufacturing.maintenance_due_count,
  manufacturing.good_vs_scrap,
  manufacturing.planned_vs_actual_hours,
  manufacturing.first_pass_yield,
  manufacturing.on_time_completion,
  manufacturing.order_progress,
  manufacturing.structure_overview,
  manufacturing.factory_pulse,
  manufacturing.orders_due_next,
  manufacturing.running_operations,
  manufacturing.work_center_scorecard,
  manufacturing.ncr_queue,
  manufacturing.downtime_watchlist,
  manufacturing.recent_floor_activity,
  manufacturing.top_scrap_products to "x-admin",
  "production-planner";

grant
select
  on manufacturing.open_orders_count,
  manufacturing.late_orders_count,
  manufacturing.machines_down_count,
  manufacturing.maintenance_due_count,
  manufacturing.good_vs_scrap,
  manufacturing.first_pass_yield,
  manufacturing.order_progress,
  manufacturing.factory_pulse,
  manufacturing.orders_due_next,
  manufacturing.running_operations,
  manufacturing.downtime_watchlist,
  manufacturing.recent_floor_activity to "operator";

grant
select
  on manufacturing.open_ncr_count,
  manufacturing.first_pass_yield,
  manufacturing.good_vs_scrap,
  manufacturing.ncr_queue,
  manufacturing.top_scrap_products,
  manufacturing.factory_pulse to "inspector";

comment on view manufacturing.open_orders_count is '{"type": "dashboard_widget", "name": "Open Orders", "description": "Works orders on the floor", "widget_type": "card_1", "resource": "production_orders"}';

comment on view manufacturing.late_orders_count is '{"type": "dashboard_widget", "name": "Late Orders", "description": "Past their due date", "widget_type": "card_1", "resource": "production_orders"}';

comment on view manufacturing.machines_down_count is '{"type": "dashboard_widget", "name": "Machines Down", "description": "Not able to run right now", "widget_type": "card_1", "resource": "machines"}';

comment on view manufacturing.open_ncr_count is '{"type": "dashboard_widget", "name": "Open NCRs", "description": "Quality issues still unresolved", "widget_type": "card_1", "resource": "nonconformances"}';

comment on view manufacturing.maintenance_due_count is '{"type": "dashboard_widget", "name": "Maintenance Due", "description": "Jobs scheduled or overdue", "widget_type": "card_1", "resource": "maintenance_orders"}';

comment on view manufacturing.good_vs_scrap is '{"type": "dashboard_widget", "name": "Good vs Scrap", "description": "Thirty days of output", "widget_type": "card_2"}';

comment on view manufacturing.planned_vs_actual_hours is '{"type": "dashboard_widget", "name": "Standard vs Actual", "description": "How the shop runs against its own standards", "widget_type": "card_2"}';

comment on view manufacturing.first_pass_yield is '{"type": "dashboard_widget", "name": "First Pass Yield", "description": "Share of output that came off right first time", "widget_type": "card_3"}';

comment on view manufacturing.on_time_completion is '{"type": "dashboard_widget", "name": "On Time", "description": "Orders finished by their due date", "widget_type": "card_3", "resource": "production_orders"}';

comment on view manufacturing.order_progress is '{"type": "dashboard_widget", "name": "Order Pipeline", "description": "Where the last quarter''s orders have got to", "widget_type": "card_4"}';

comment on view manufacturing.structure_overview is '{"type": "dashboard_widget", "name": "Item Master", "description": "How the active catalogue splits", "widget_type": "card_5"}';

comment on view manufacturing.factory_pulse is '{"type": "dashboard_widget", "name": "Factory Pulse", "description": "Everything worth glancing at, in one row", "widget_type": "card_6"}';

comment on view manufacturing.orders_due_next is '{"type": "dashboard_widget", "name": "Due Next", "description": "Orders to finish first", "widget_type": "table_1", "url": "/manufacturing/resource/production_orders"}';

comment on view manufacturing.running_operations is '{"type": "dashboard_widget", "name": "Running Now", "description": "Operations in progress on the floor", "widget_type": "table_1", "url": "/manufacturing/resource/production_order_operations"}';

comment on view manufacturing.work_center_scorecard is '{"type": "dashboard_widget", "name": "Work Centre Load", "description": "Queued hours and utilisation per centre", "widget_type": "table_2", "url": "/manufacturing/resource/work_centers"}';

comment on view manufacturing.ncr_queue is '{"type": "dashboard_widget", "name": "NCRs To Resolve", "description": "Worst first", "widget_type": "list_1", "url": "/manufacturing/resource/nonconformances"}';

comment on view manufacturing.downtime_watchlist is '{"type": "dashboard_widget", "name": "Machines Down", "description": "Open stoppages, oldest first", "widget_type": "list_2", "url": "/manufacturing/resource/downtime_events"}';

comment on view manufacturing.recent_floor_activity is '{"type": "dashboard_widget", "name": "Recent Activity", "description": "The last confirmations booked", "widget_type": "list_3", "url": "/manufacturing/resource/production_confirmations"}';

comment on view manufacturing.top_scrap_products is '{"type": "dashboard_widget", "name": "Most Scrapped", "description": "Where the losses are", "widget_type": "list_4", "url": "/manufacturing/resource/products"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
create or replace view manufacturing.output_trend_bar
with
  (security_invoker = true) as
select
  month as label,
  round(sum(units_good), 0) as good,
  round(sum(units_scrap), 0) as scrap
from
  manufacturing.production_summary
where
  month_start >= (current_date - interval '12 months')
group by
  month_start,
  month
order by
  month_start;

create or replace view manufacturing.scrap_rate_line
with
  (security_invoker = true) as
select
  month as date,
  round(
    100.0 * sum(units_scrap) / nullif(sum(units_good + units_scrap), 0),
    2
  ) as scrap_rate
from
  manufacturing.production_summary
where
  month_start >= (current_date - interval '12 months')
group by
  month_start,
  month
order by
  month_start;

create or replace view manufacturing.hours_area
with
  (security_invoker = true) as
select
  month as date,
  round(sum(hours_booked), 0) as hours_booked,
  round(sum(labour_cost), 0) as labour_cost
from
  manufacturing.production_summary
where
  month_start >= (current_date - interval '12 months')
group by
  month_start,
  month
order by
  month_start;

create or replace view manufacturing.downtime_reason_pie
with
  (security_invoker = true) as
select
  initcap(replace(reason::text, '_', ' ')) as label,
  round(coalesce(sum(duration_minutes), 0) / 60.0, 1) as value
from
  manufacturing.downtime_events
where
  started_at >= current_date - 90
group by
  1
having
  sum(duration_minutes) > 0;

create or replace view manufacturing.order_status_pie
with
  (security_invoker = true) as
select
  initcap(replace(status::text, '_', ' ')) as label,
  count(*) as value
from
  manufacturing.production_orders
group by
  1;

create or replace view manufacturing.defect_severity_pie
with
  (security_invoker = true) as
select
  initcap(severity::text) as label,
  count(*) as value
from
  manufacturing.nonconformances
group by
  1;

create or replace view manufacturing.work_center_load_bar
with
  (security_invoker = true) as
select
  wc.code as label,
  round(wc.scheduled_hours, 1) as queued_hours,
  round((wc.capacity_hours_per_day * 5)::numeric, 1) as weekly_capacity
from
  manufacturing.work_centers wc
where
  wc.is_active
order by
  wc.scheduled_hours desc
limit
  12;

create or replace view manufacturing.cost_structure_bar
with
  (security_invoker = true) as
select
  p.sku as label,
  round(p.material_cost, 2) as material,
  round(p.labour_cost, 2) as labour,
  round(p.overhead_cost, 2) as overhead
from
  manufacturing.products p
where
  p.status = 'active'
  and p.product_type = 'make'
  and p.standard_cost > 0
order by
  p.standard_cost desc
limit
  10;

create or replace view manufacturing.factory_health_radar
with
  (security_invoker = true) as
select
  'First pass yield' as label,
  round(
    100.0 * coalesce(sum(quantity_good), 0) / nullif(sum(quantity_good + quantity_scrap), 0),
    0
  ) as score
from
  manufacturing.production_confirmations
where
  confirmed_at >= current_date - 90
union all
select
  'On-time delivery',
  round(
    100.0 * count(*) filter (
      where
        actual_end::date <= planned_end
    ) / nullif(count(*), 0),
    0
  )
from
  manufacturing.production_orders
where
  status in ('completed', 'closed')
  and actual_end is not null
union all
select
  'Machine availability',
  round(coalesce(avg(availability), 0)::numeric, 0)
from
  manufacturing.machines
where
  status <> 'retired'
union all
select
  'Operation efficiency',
  round(coalesce(avg(efficiency), 0)::numeric, 0)
from
  manufacturing.production_order_operations
where
  status = 'completed'
  and efficiency is not null
union all
select
  'NCRs closed',
  round(
    100.0 * count(*) filter (
      where
        status = 'closed'
    ) / nullif(count(*), 0),
    0
  )
from
  manufacturing.nonconformances;

revoke all on manufacturing.output_trend_bar,
manufacturing.scrap_rate_line,
manufacturing.hours_area,
manufacturing.downtime_reason_pie,
manufacturing.order_status_pie,
manufacturing.defect_severity_pie,
manufacturing.work_center_load_bar,
manufacturing.cost_structure_bar,
manufacturing.factory_health_radar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on manufacturing.output_trend_bar,
  manufacturing.scrap_rate_line,
  manufacturing.hours_area,
  manufacturing.downtime_reason_pie,
  manufacturing.order_status_pie,
  manufacturing.defect_severity_pie,
  manufacturing.work_center_load_bar,
  manufacturing.cost_structure_bar,
  manufacturing.factory_health_radar to "x-admin",
  "production-planner";

grant
select
  on manufacturing.downtime_reason_pie,
  manufacturing.order_status_pie,
  manufacturing.work_center_load_bar,
  manufacturing.factory_health_radar to "operator";

grant
select
  on manufacturing.defect_severity_pie,
  manufacturing.scrap_rate_line,
  manufacturing.factory_health_radar to "inspector";

comment on view manufacturing.output_trend_bar is '{"type": "chart", "name": "Output Trend", "description": "Good against scrapped, month by month", "chart_type": "bar"}';

comment on view manufacturing.scrap_rate_line is '{"type": "chart", "name": "Scrap Rate", "description": "Share of output scrapped over time", "chart_type": "line"}';

comment on view manufacturing.hours_area is '{"type": "chart", "name": "Hours and Labour", "description": "Time booked and what it cost", "chart_type": "area", "format": "currency"}';

comment on view manufacturing.downtime_reason_pie is '{"type": "chart", "name": "Downtime By Reason", "description": "Ninety days of lost hours", "chart_type": "pie", "resource": "downtime_events"}';

comment on view manufacturing.order_status_pie is '{"type": "chart", "name": "Orders By Status", "description": "Where the order book sits", "chart_type": "pie", "resource": "production_orders"}';

comment on view manufacturing.defect_severity_pie is '{"type": "chart", "name": "NCRs By Severity", "description": "How serious the quality issues are", "chart_type": "pie", "resource": "nonconformances"}';

comment on view manufacturing.work_center_load_bar is '{"type": "chart", "name": "Load vs Capacity", "description": "Queued hours against what each centre can do in a week", "chart_type": "bar", "resource": "work_centers"}';

comment on view manufacturing.cost_structure_bar is '{"type": "chart", "name": "Cost Structure", "description": "Material, labour and overhead on the dearest parts", "chart_type": "bar", "format": "currency", "resource": "products"}';

comment on view manufacturing.factory_health_radar is '{"type": "chart", "name": "Factory Health", "description": "Five operating measures, scored out of a hundred", "chart_type": "radar"}';

----------------------------------------------------------------
-- Maintenance
----------------------------------------------------------------
create or replace function manufacturing.run_daily_maintenance (
  out orders_flagged integer,
  out maintenance_raised integer,
  out certifications_expired integer,
  out ncrs_escalated integer
) language plpgsql security definer
set
  search_path = '' as $$
declare
  v_settings manufacturing.manufacturing_settings;
begin
  v_settings := manufacturing.settings ();

  -- Anything scheduled that has slipped past its date.
  with flagged as (
    update manufacturing.maintenance_orders
    set status = 'overdue'
    where status = 'scheduled'
      and scheduled_for < current_date
    returning 1
  )
  select count(*) into orders_flagged from flagged;

  -- Machines whose service interval has come round and have nothing
  -- open against them get a job raised automatically.
  with raised as (
    insert into manufacturing.maintenance_orders (machine_id, maintenance_type, scheduled_for, description)
    select m.id,
      'preventive',
      coalesce(m.next_service_due, current_date),
      'Scheduled service — ' || m.name
    from manufacturing.machines m
    where m.status <> 'retired'
      and coalesce(m.next_service_due, current_date) <= current_date
      and not exists (
        select 1
        from manufacturing.maintenance_orders mo
        where mo.machine_id = m.id
          and mo.status in ('scheduled', 'in_progress', 'overdue')
      )
    returning 1
  )
  select count(*) into maintenance_raised from raised;

  with expired as (
    update manufacturing.operator_certifications
    set is_expired = true
    where not is_expired
      and expires_on is not null
      and expires_on < current_date
    returning 1
  )
  select count(*) into certifications_expired from expired;

  select count(*)
  into ncrs_escalated
  from manufacturing.nonconformances
  where status in ('open', 'investigating')
    and raised_at < current_timestamp - (coalesce(v_settings.ncr_escalation_days, 14) || ' days')::interval;

  update manufacturing.nonconformances
  set age_days = greatest(
    extract(day from (coalesce(closed_at, current_timestamp) - raised_at))::integer,
    0
  )
  where age_days is distinct from greatest(
    extract(day from (coalesce(closed_at, current_timestamp) - raised_at))::integer,
    0
  );

  perform manufacturing.roll_up_cost ();

  refresh materialized view concurrently manufacturing.production_summary;
end;
$$;

revoke all on function manufacturing.run_daily_maintenance ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function manufacturing.run_daily_maintenance () to "x-admin";

----------------------------------------------------------------
-- Audit triggers (INSERT/UPDATE fire AFTER, DELETE must fire BEFORE)
----------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'product_families', 'products', 'boms', 'bom_lines', 'routings',
    'routing_operations', 'work_centers', 'machines', 'operators',
    'operator_certifications', 'production_orders', 'production_order_components',
    'production_order_operations', 'production_confirmations', 'downtime_events',
    'maintenance_orders', 'defect_codes', 'quality_characteristics',
    'inspections', 'inspection_results', 'nonconformances'
  ]
  loop
    execute format(
      'create trigger audit_manufacturing_%1$s_insert after insert on manufacturing.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
    execute format(
      'create trigger audit_manufacturing_%1$s_update after update on manufacturing.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
    execute format(
      'create trigger audit_manufacturing_%1$s_delete before delete on manufacturing.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
  end loop;
end;
$$;

create trigger audit_manufacturing_manufacturing_settings_insert
after insert on manufacturing.manufacturing_settings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_manufacturing_manufacturing_settings_update
after update on manufacturing.manufacturing_settings for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
create or replace function manufacturing.trg_order_release_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_sku        text;
begin
    if new.status <> 'released' or (tg_op = 'UPDATE' and old.status = 'released') then
        return new;
    end if;

    v_recipients := supasheet.get_users_with_table_privilege('manufacturing', 'production_confirmations', 'insert');

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    select sku into v_sku from manufacturing.products where id = new.product_id;

    perform supasheet.create_notification(
        'manufacturing_order_released',
        'Works order released',
        new.order_number || ' — ' || new.quantity_ordered || ' of ' || coalesce(v_sku, 'a product')
          || ', due ' || to_char(new.planned_end, 'Mon DD'),
        v_recipients,
        jsonb_build_object('order_id', new.id, 'priority', new.priority),
        '/manufacturing/resource/production_orders/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger order_release_notify
after insert or update of status on manufacturing.production_orders for each row
execute function manufacturing.trg_order_release_notify ();

create or replace function manufacturing.trg_downtime_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_machine    text;
begin
    if not new.is_open or (tg_op = 'UPDATE' and old.is_open) then
        return new;
    end if;

    v_recipients := supasheet.get_users_with_table_privilege('manufacturing', 'maintenance_orders', 'insert');

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    select name into v_machine from manufacturing.machines where id = new.machine_id;

    perform supasheet.create_notification(
        'manufacturing_machine_down',
        'Machine down',
        coalesce(v_machine, 'A machine') || ' — ' || new.reason
          || coalesce(': ' || new.description, ''),
        v_recipients,
        jsonb_build_object('machine_id', new.machine_id, 'reason', new.reason),
        '/manufacturing/resource/downtime_events/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger downtime_notify
after insert or update of ended_at on manufacturing.downtime_events for each row
execute function manufacturing.trg_downtime_notify ();

create or replace function manufacturing.trg_ncr_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if tg_op = 'UPDATE' and new.status is not distinct from old.status then
        return new;
    end if;

    if new.status in ('open', 'investigating') and new.severity in ('major', 'critical') then
        v_recipients := supasheet.get_users_with_table_privilege('manufacturing', 'nonconformances', 'update');

        if array_length(v_recipients, 1) is null then
            return new;
        end if;

        perform supasheet.create_notification(
            'manufacturing_ncr_raised',
            new.severity || ' non-conformance raised',
            new.ncr_number || ' — ' || new.title,
            v_recipients,
            jsonb_build_object('ncr_id', new.id, 'severity', new.severity),
            '/manufacturing/resource/nonconformances/' || new.id::text || '/detail'
        );
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger ncr_notify
after insert or update of status on manufacturing.nonconformances for each row
execute function manufacturing.trg_ncr_notify ();

create or replace function manufacturing.trg_manufacturing_comments_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.schema_name <> 'manufacturing'
       or new.table_name not in ('products', 'boms', 'production_orders', 'nonconformances', 'machines') then
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('manufacturing', new.table_name, 'update'),
        new.created_by
    );

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'manufacturing_comment_added',
        'New comment on ' || new.table_name,
        left(new.content, 140),
        v_recipients,
        jsonb_build_object('record_id', new.record_id, 'table_name', new.table_name),
        '/manufacturing/resource/' || new.table_name || '/' || new.record_id::text || '/comment'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists manufacturing_comments_notify on supasheet.comments;

create trigger manufacturing_comments_notify
after insert on supasheet.comments for each row
execute function manufacturing.trg_manufacturing_comments_notify ();

----------------------------------------------------------------
-- Private document storage
--
-- Drawings, work instructions and inspection certificates are
-- controlled documents. The policies delegate to the same table
-- privileges the rest of the module uses.
----------------------------------------------------------------
insert into
  storage.buckets (id, name, public)
values
  (
    'manufacturing-documents',
    'manufacturing-documents',
    false
  )
on conflict (id) do nothing;

drop policy if exists manufacturing_documents_read on storage.objects;

create policy manufacturing_documents_read on storage.objects for
select
  to authenticated using (
    bucket_id = 'manufacturing-documents'
    and (
      has_table_privilege(current_user, 'manufacturing.products', 'select')
      or has_table_privilege(
        current_user,
        'manufacturing.inspections',
        'select'
      )
    )
  );

drop policy if exists manufacturing_documents_insert on storage.objects;

create policy manufacturing_documents_insert on storage.objects for insert to authenticated
with
  check (
    bucket_id = 'manufacturing-documents'
    and (
      has_table_privilege(current_user, 'manufacturing.products', 'insert')
      or has_table_privilege(
        current_user,
        'manufacturing.inspections',
        'insert'
      )
    )
  );

drop policy if exists manufacturing_documents_update on storage.objects;

create policy manufacturing_documents_update on storage.objects
for update
  to authenticated using (
    bucket_id = 'manufacturing-documents'
    and has_table_privilege(current_user, 'manufacturing.products', 'update')
  );

drop policy if exists manufacturing_documents_delete on storage.objects;

create policy manufacturing_documents_delete on storage.objects for delete to authenticated using (
  bucket_id = 'manufacturing-documents'
  and has_table_privilege(current_user, 'manufacturing.products', 'delete')
);

----------------------------------------------------------------
-- App configuration
----------------------------------------------------------------
insert into
  supasheet.configs (key, value, description, is_public)
values
  (
    'manufacturing.base_currency',
    '"USD"',
    'Currency standard costs are held in',
    true
  ),
  (
    'manufacturing.enforce_operation_sequence',
    'true',
    'Operation 20 cannot start until operation 10 has finished',
    true
  ),
  (
    'manufacturing.enforce_certification',
    'true',
    'Only an operator certified on the work centre may confirm work there',
    true
  ),
  (
    'manufacturing.default_overhead_rate',
    '45',
    'Overhead per hour applied where a work centre has no rate of its own',
    false
  ),
  (
    'manufacturing.scrap_alert_threshold',
    '5',
    'Scrap percentage above which the shop-floor board flags an order',
    true
  )
on conflict (key) do update
set
  value = excluded.value,
  description = excluded.description,
  is_public = excluded.is_public;

----------------------------------------------------------------
-- Refresh the metadata catalog (materialized views — NOT automatic)
----------------------------------------------------------------
select
  supasheet.refresh_metadata ();
