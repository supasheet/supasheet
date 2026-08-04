-- ================================================================
-- Supasheet Example — "Inventory" (warehouse and stock control)
-- ================================================================
-- A production-shaped inventory back office: a multi-warehouse bin
-- structure, an item master with lot and serial tracking, an
-- append-only stock ledger, purchasing and goods receipt, put-away,
-- internal transfers, picking, cycle counting and adjustments.
--
-- Demo data lives in supabase/examples/i_seed.sql — apply this file
-- first, then that one.
--
-- This is NOT the store module with different words on it. The store
-- example asks "how much of this product can I sell?"; this one asks
-- "where exactly is it, where did it come from, and who touched it
-- last?" — which is a different database.
--
-- The rules that make it a stock system rather than a spreadsheet:
--
--   - STOCK IS A LEDGER. Quantities are never written directly.
--     inventory.stock_movements is append-only — no role holds UPDATE
--     or DELETE on it, including the manager — and every on-hand
--     figure in the schema is the sum of it.
--   - STOCK HAS A PLACE. A quantity belongs to a BIN, not to a
--     warehouse. Moving stock is two ledger lines that must net to
--     zero, so nothing is ever in transit by accident.
--   - NO NEGATIVE STOCK. A pick, issue or transfer that would take a
--     bin below zero is refused at the ledger, not at the form.
--   - TRACEABILITY. An item declared lot-tracked cannot move without
--     a lot, a serial-tracked one cannot move without a serial, and a
--     serial can only be in one place at a time.
--   - RESERVED IS NOT AVAILABLE. Allocated stock stays on hand and
--     stops being sellable at the same moment.
--
-- Everything the other modules cover is here too:
--   - Native-role RBAC with two custom roles ("warehouse" and
--     "inventory-planner") alongside "x-admin"/"user"
--   - COLUMN-LEVEL GRANT used for something real: the warehouse
--     operative can see and move every unit of stock and cannot see
--     what any of it cost
--   - The "user" role is THE REQUESTER: raises internal stock
--     requests, sees their own, and reads the catalogue
--   - All six view layouts, every widget and chart contract, reports
--     with a Handlebars print template, a materialized valuation
--     snapshot, templates, row actions, custom form shapes,
--     notifications, audit logging and per-resource comments
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260805000000_inventory.sql \
--     -f supabase/examples/i_seed.sql
--
-- Requires the base Supasheet migrations. Add "inventory" to
-- config.toml's `api.schemas` and `api.extra_search_path`, then
-- restart Supabase.
--
-- Not idempotent: re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists inventory;

-------------------------------------------------------------------
-- Roles
--
--   x-admin    inventory manager: everything, including posting
--              adjustments and approving write-offs
--   warehouse  the operative on the floor: receives, puts away,
--              picks, transfers and counts. Sees every unit of stock
--              and, by column-level grant, none of its value
--   inventory-planner  demand and supply: items, suppliers, purchase
--              orders and reorder rules. Cannot move a single unit
--   user       THE REQUESTER: raises internal stock requests and
--              sees their own, plus the catalogue
--
-- Assign a user to a custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "warehouse"}'
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

  if not exists (select 1 from pg_roles where rolname = 'warehouse') then
    create role "warehouse" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'inventory-planner') then
    create role "inventory-planner" nologin;
  end if;
end;
$$;

grant "user",
"admin",
"warehouse",
"inventory-planner" to authenticator;

grant authenticated to "user",
"admin",
"warehouse",
"inventory-planner";

grant usage on schema inventory to "x-admin",
"warehouse",
"inventory-planner",
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
create type inventory.item_tracking as enum('none', 'lot', 'serial');

create type inventory.item_status as enum('draft', 'active', 'discontinued', 'obsolete');

create type inventory.abc_class as enum('a', 'b', 'c', 'unclassified');

create type inventory.valuation_method as enum('standard', 'average', 'fifo');

create type inventory.uom_type as enum('quantity', 'weight', 'volume', 'length');

create type inventory.zone_type as enum('inbound', 'storage', 'outbound', 'quarantine');

create type inventory.location_type as enum(
  'dock',
  'staging',
  'bin',
  'rack',
  'floor',
  'pallet'
);

create type inventory.lot_status as enum(
  'available',
  'quarantine',
  'expired',
  'recalled',
  'consumed'
);

create type inventory.serial_status as enum(
  'in_stock',
  'allocated',
  'shipped',
  'scrapped',
  'returned'
);

create type inventory.movement_type as enum(
  'receipt',
  'putaway',
  'pick',
  'ship',
  'transfer_out',
  'transfer_in',
  'adjustment_in',
  'adjustment_out',
  'count_in',
  'count_out',
  'return_in',
  'scrap'
);

create type inventory.supplier_status as enum('active', 'on_hold', 'inactive');

create type inventory.po_status as enum(
  'draft',
  'submitted',
  'approved',
  'partially_received',
  'received',
  'cancelled'
);

create type inventory.receipt_status as enum('draft', 'checking', 'put_away', 'cancelled');

create type inventory.transfer_status as enum(
  'draft',
  'picked',
  'in_transit',
  'received',
  'cancelled'
);

create type inventory.pick_status as enum(
  'pending',
  'assigned',
  'picking',
  'picked',
  'dispatched',
  'cancelled'
);

create type inventory.count_status as enum(
  'planned',
  'counting',
  'review',
  'posted',
  'cancelled'
);

create type inventory.count_type as enum('cycle', 'full', 'spot');

create type inventory.adjustment_status as enum(
  'draft',
  'pending_approval',
  'approved',
  'posted',
  'rejected'
);

create type inventory.adjustment_reason as enum(
  'damage',
  'expiry',
  'theft',
  'found',
  'correction',
  'sample',
  'scrap',
  'rework'
);

create type inventory.request_status as enum(
  'draft',
  'submitted',
  'approved',
  'rejected',
  'fulfilled',
  'cancelled'
);

create type inventory.priority as enum('low', 'normal', 'high', 'urgent');

-------------------------------------------------------------------
-- Users
-------------------------------------------------------------------
create or replace view inventory.users
with
  (security_invoker = true) as
select
  id,
  name,
  email,
  picture_url
from
  supasheet.users;

revoke all on inventory.users
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on inventory.users to "x-admin",
  "warehouse",
  "inventory-planner",
  "user";

comment on view inventory.users is '{"display": "none"}';

----------------------------------------------------------------
-- Units of measure
----------------------------------------------------------------
create table inventory.unit_of_measures (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(12) not null unique,
  name varchar(60) not null,
  uom_type inventory.uom_type not null default 'quantity',
  decimal_places integer not null default 0,
  is_base boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint uom_decimals_sane check (decimal_places between 0 and 4)
);

comment on table inventory.unit_of_measures is '{
    "icon": "Ruler",
    "name": "Units of Measure",
    "description": "How each item is counted, weighed or measured.",
    "collapsible_group": "Configuration",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "views": [
        {"id": "list", "name": "All Units", "type": "list", "title": "code", "description": "name", "field_1": "uom_type", "field_2": "decimal_places"}
    ],
    "filter_presets": [
        {"id": "base", "name": "Base Units", "filters": [{"id": "is_base", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "uom_type"],
        "sections": [
            {"id": "unit", "title": "Unit", "fields": ["code", "name", "uom_type"]},
            {"id": "behaviour", "title": "Behaviour", "fields": ["decimal_places", "is_base", "is_active"]}
        ]
    },
    "query": {"sort": [{"id": "code", "desc": false}]}
}';

revoke all on table inventory.unit_of_measures
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
delete on table inventory.unit_of_measures to "x-admin";

grant
select
,
  insert,
update on table inventory.unit_of_measures to "inventory-planner";

grant
select
  on table inventory.unit_of_measures to "warehouse",
  "user";

alter table inventory.unit_of_measures enable row level security;

create policy uom_select on inventory.unit_of_measures for
select
  to authenticated using (true);

create policy uom_insert on inventory.unit_of_measures for insert to authenticated
with
  check (true);

create policy uom_update on inventory.unit_of_measures
for update
  to authenticated using (true)
with
  check (true);

create policy uom_delete on inventory.unit_of_measures for delete to authenticated using (true);

----------------------------------------------------------------
-- Item categories (a tree)
----------------------------------------------------------------
create table inventory.item_categories (
  id uuid primary key default extensions.uuid_generate_v4 (),
  parent_id uuid references inventory.item_categories (id) on delete set null,
  code varchar(24) not null unique,
  name varchar(120) not null,
  description varchar(300),
  default_count_frequency_days integer not null default 90,
  item_count integer not null default 0,
  color supasheet.COLOR,
  is_active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table inventory.item_categories is '{
    "icon": "FolderTree",
    "name": "Item Categories",
    "description": "The product hierarchy, and how often each branch gets counted.",
    "collapsible_group": "Catalogue",
    "display": "block",
    "primary_view": "tree",
    "detail": {"header": {"title": "name", "badges": ["code", "item_count"]}, "tabs": ["items"]},
    "views": [
        {"id": "tree", "name": "Hierarchy", "type": "tree", "parent": "parent_id", "title": "name", "secondary": "code"},
        {"id": "list", "name": "Flat List", "type": "list", "title": "name", "description": "description", "field_1": "code", "field_2": "item_count"}
    ],
    "fields": {
        "quick_create": ["code", "name", "parent_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "parent_id"]},
            {"id": "policy", "title": "Policy", "fields": ["default_count_frequency_days", "color", "is_active"]},
            {"id": "rollup", "title": "Rollup", "fields": {"read": ["item_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "item_categories", "on": "parent_id", "alias": "parent", "columns": ["code", "name"]}]
    }
}';

revoke all on table inventory.item_categories
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
delete on table inventory.item_categories to "x-admin";

grant
select
,
  insert,
update on table inventory.item_categories to "inventory-planner";

grant
select
  on table inventory.item_categories to "warehouse",
  "user";

create index idx_inv_categories_parent_id on inventory.item_categories (parent_id);

alter table inventory.item_categories enable row level security;

create policy categories_select on inventory.item_categories for
select
  to authenticated using (true);

create policy categories_insert on inventory.item_categories for insert to authenticated
with
  check (true);

create policy categories_update on inventory.item_categories
for update
  to authenticated using (true)
with
  check (true);

create policy categories_delete on inventory.item_categories for delete to authenticated using (true);

----------------------------------------------------------------
-- Items
--
-- The item master. `tracking` is the most consequential column in the
-- schema: it decides whether the ledger will accept a movement
-- without a lot or a serial against it.
--
-- COLUMN-LEVEL GRANT lives here. The warehouse operative needs every
-- column that tells them what a thing is and where it goes, and none
-- of the ones that say what it is worth. Rather than a second
-- "operational item" view to keep in step, the grant names the
-- columns and Postgres enforces it on every path — PostgREST, the SQL
-- editor and psql alike.
----------------------------------------------------------------
create table inventory.items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  sku varchar(40) not null unique,
  name varchar(200) not null,
  description text,
  category_id uuid references inventory.item_categories (id) on delete set null,
  status inventory.item_status not null default 'draft',
  tracking inventory.item_tracking not null default 'none',
  uom_id uuid references inventory.unit_of_measures (id) on delete set null,
  barcode varchar(60) unique,
  abc_class inventory.abc_class not null default 'unclassified',
  valuation_method inventory.valuation_method not null default 'average',
  standard_cost numeric(14, 4) not null default 0,
  average_cost numeric(14, 4) not null default 0,
  last_cost numeric(14, 4) not null default 0,
  reorder_point numeric(14, 3) not null default 0,
  reorder_quantity numeric(14, 3) not null default 0,
  max_stock numeric(14, 3),
  lead_time_days integer not null default 7,
  shelf_life_days integer,
  is_serialised boolean generated always as (tracking = 'serial') stored,
  requires_quarantine boolean not null default false,
  weight_kg numeric(10, 3),
  volume_m3 numeric(10, 4),
  hazard_class varchar(40),
  on_hand numeric(14, 3) not null default 0,
  allocated numeric(14, 3) not null default 0,
  available numeric(14, 3) not null default 0,
  on_order numeric(14, 3) not null default 0,
  stock_value numeric(16, 2) not null default 0,
  is_below_reorder_point boolean not null default false,
  location_count integer not null default 0,
  last_movement_on date,
  image supasheet.file,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint items_costs_non_negative check (
    standard_cost >= 0
    and average_cost >= 0
    and last_cost >= 0
  ),
  constraint items_reorder_non_negative check (
    reorder_point >= 0
    and reorder_quantity >= 0
  ),
  constraint items_max_above_reorder check (
    max_stock is null
    or max_stock >= reorder_point
  ),
  constraint items_shelf_life_needs_lots check (
    shelf_life_days is null
    or tracking = 'lot'
  )
);

comment on column inventory.items.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "active": {"variant": "success", "icon": "CircleCheck"},
        "discontinued": {"variant": "warning", "icon": "CircleMinus"},
        "obsolete": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on column inventory.items.tracking is '{
    "progress": false,
    "values": {
        "none": {"variant": "secondary", "icon": "Package"},
        "lot": {"variant": "info", "icon": "Boxes"},
        "serial": {"variant": "warning", "icon": "ScanBarcode"}
    }
}';

comment on column inventory.items.abc_class is '{
    "progress": false,
    "values": {
        "a": {"variant": "destructive", "icon": "ChevronsUp"},
        "b": {"variant": "warning", "icon": "ChevronUp"},
        "c": {"variant": "secondary", "icon": "Minus"},
        "unclassified": {"variant": "secondary", "icon": "CircleHelp"}
    }
}';

comment on table inventory.items is '{
    "icon": "Package",
    "description": "Everything the business stocks, and how much of it there is.",
    "collapsible_group": "Catalogue",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "name", "badges": ["sku", "status", "tracking"]},
        "tabs": ["stock_levels", "stock_movements", "lots", "serials", "supplier_items", "item_barcodes"],
        "timelines": ["stock_movements"]
    },
    "views": [
        {"id": "gallery", "name": "Catalogue", "type": "gallery", "cover": "image", "title": "name", "description": "sku", "badge": "status"},
        {"id": "list", "name": "Stock List", "type": "list", "title": "name", "description": "sku", "field_1": "available", "field_2": "abc_class"},
        {"id": "kanban", "name": "By Lifecycle", "type": "kanban", "group": "status", "title": "name", "description": "sku", "date": "created_at", "badge": "abc_class"}
    ],
    "filter_presets": [
        {"id": "reorder", "name": "Below Reorder Point", "filters": [{"id": "is_below_reorder_point", "value": "true", "operator": "eq"}]},
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "serialised", "name": "Serialised", "filters": [{"id": "tracking", "value": "serial", "operator": "eq"}]},
        {"id": "no_stock", "name": "Out Of Stock", "filters": [{"id": "on_hand", "value": "0", "operator": "lte"}]},
        {"id": "class_a", "name": "A Class", "filters": [{"id": "abc_class", "value": "a", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["sku", "name", "category_id", "uom_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["sku", "name", "description", "category_id", "status", "image"]},
            {"id": "handling", "title": "Handling", "fields": ["tracking", "uom_id", "barcode", "requires_quarantine", "shelf_life_days", "hazard_class"]},
            {"id": "planning", "title": "Planning", "fields": ["reorder_point", "reorder_quantity", "max_stock", "lead_time_days", "abc_class"]},
            {"id": "costing", "title": "Costing", "fields": ["valuation_method", "standard_cost"]},
            {"id": "physical", "title": "Physical", "fields": ["weight_kg", "volume_m3"]},
            {"id": "position", "title": "Stock position", "fields": {"read": ["on_hand", "allocated", "available", "on_order", "stock_value", "location_count", "last_movement_on", "average_cost", "last_cost"]}},
            {"id": "notes", "title": "Notes", "fields": ["notes"]}
        ],
        "behavior": {
            "shelf_life_days": {"visible": [{"id": "tracking", "operator": "eq", "value": "lot"}]},
            "requires_quarantine": {"visible": [{"id": "tracking", "operator": "in", "value": ["lot", "serial"]}]},
            "standard_cost": {"visible": [{"id": "valuation_method", "operator": "eq", "value": "standard"}]}
        },
        "lookups": {
            "category_id": {"filter": [{"source_column": "is_active", "target_column": "is_active"}]}
        },
        "metadata": {
            "sku": {"placeholder": "SKU-0000"},
            "reorder_point": {"description": "Raise a replenishment suggestion when available stock falls to or below this."}
        }
    },
    "query": {
        "sort": [{"id": "sku", "desc": false}],
        "join": [
            {"table": "item_categories", "on": "category_id", "columns": ["code", "name"]},
            {"table": "unit_of_measures", "on": "uom_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column inventory.items.image is '{"accept": "image/*", "max_files": 5, "max_size": 5242880}';

comment on column inventory.items.on_hand is '{"name": "On Hand", "aggregate": "sum"}';

comment on column inventory.items.available is '{"aggregate": "sum"}';

comment on column inventory.items.stock_value is '{"name": "Value", "aggregate": "sum"}';

comment on column inventory.items.is_below_reorder_point is '{"name": "Below Reorder"}';

revoke all on table inventory.items
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
delete on table inventory.items to "x-admin";

grant
select
,
  insert,
update on table inventory.items to "inventory-planner";

-- The operative reads everything that says what a thing IS and where
-- it goes. standard_cost, average_cost, last_cost and stock_value are
-- deliberately absent, and no query they can write will get them.
grant
select
  (
    id,
    sku,
    name,
    description,
    category_id,
    status,
    tracking,
    uom_id,
    barcode,
    abc_class,
    reorder_point,
    reorder_quantity,
    max_stock,
    lead_time_days,
    shelf_life_days,
    is_serialised,
    requires_quarantine,
    weight_kg,
    volume_m3,
    hazard_class,
    on_hand,
    allocated,
    available,
    on_order,
    is_below_reorder_point,
    location_count,
    last_movement_on,
    image,
    notes,
    created_at,
    updated_at
  ) on table inventory.items to "warehouse",
  "user";

create index idx_inv_items_category_id on inventory.items (category_id);

create index idx_inv_items_status on inventory.items (status);

create index idx_inv_items_tracking on inventory.items (tracking);

create index idx_inv_items_reorder on inventory.items (sku)
where
  is_below_reorder_point;

create index idx_inv_items_name on inventory.items (name);

alter table inventory.items enable row level security;

create policy items_select on inventory.items for
select
  to authenticated using (true);

create policy items_insert on inventory.items for insert to authenticated
with
  check (true);

create policy items_update on inventory.items
for update
  to authenticated using (true)
with
  check (true);

create policy items_delete on inventory.items for delete to authenticated using (true);

----------------------------------------------------------------
-- Alternate barcodes
----------------------------------------------------------------
create table inventory.item_barcodes (
  id uuid primary key default extensions.uuid_generate_v4 (),
  item_id uuid not null references inventory.items (id) on delete cascade,
  barcode varchar(60) not null unique,
  pack_size numeric(12, 3) not null default 1,
  label varchar(80),
  is_primary boolean not null default false,
  created_at timestamptz default current_timestamp,
  constraint barcodes_pack_positive check (pack_size > 0)
);

comment on table inventory.item_barcodes is '{
    "icon": "ScanBarcode",
    "name": "Barcodes",
    "description": "Case, pallet and supplier barcodes that scan to the same item.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "code", "title": "Barcode", "fields": ["item_id", "barcode", "label"]},
            {"id": "pack", "title": "Pack", "fields": ["pack_size", "is_primary"]}
        ]
    },
    "query": {
        "sort": [{"id": "pack_size", "desc": false}],
        "join": [{"table": "items", "on": "item_id", "columns": ["sku", "name"]}]
    }
}';

revoke all on table inventory.item_barcodes
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
delete on table inventory.item_barcodes to "x-admin",
"inventory-planner";

grant
select
  on table inventory.item_barcodes to "warehouse",
  "user";

create index idx_inv_barcodes_item_id on inventory.item_barcodes (item_id);

alter table inventory.item_barcodes enable row level security;

create policy barcodes_select on inventory.item_barcodes for
select
  to authenticated using (true);

create policy barcodes_insert on inventory.item_barcodes for insert to authenticated
with
  check (true);

create policy barcodes_update on inventory.item_barcodes
for update
  to authenticated using (true)
with
  check (true);

create policy barcodes_delete on inventory.item_barcodes for delete to authenticated using (true);

----------------------------------------------------------------
-- Warehouses, zones and bins
--
-- Three levels, because that is the shortest structure that lets a
-- pick list say something useful. A warehouse has zones, a zone has
-- bins, and stock lives in a bin.
----------------------------------------------------------------
create table inventory.warehouses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(12) not null unique,
  name varchar(120) not null,
  address varchar(300),
  city varchar(80),
  country varchar(2),
  timezone varchar(64) not null default 'UTC',
  manager_id uuid references supasheet.users (id) on delete set null,
  contact_email supasheet.EMAIL,
  contact_phone supasheet.TEL,
  is_active boolean not null default true,
  is_default boolean not null default false,
  allows_negative_stock boolean not null default false,
  zone_count integer not null default 0,
  location_count integer not null default 0,
  distinct_items integer not null default 0,
  stock_value numeric(16, 2) not null default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table inventory.warehouses is '{
    "icon": "Warehouse",
    "description": "The buildings, and what is sitting in each of them.",
    "collapsible_group": "Network",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["code", "is_default"]},
        "tabs": ["zones", "locations", "stock_levels"]
    },
    "views": [
        {"id": "list", "name": "All Sites", "type": "list", "title": "name", "description": "city", "field_1": "distinct_items", "field_2": "location_count"},
        {"id": "kanban", "name": "By Country", "type": "kanban", "group": "country", "title": "name", "description": "city", "date": "created_at", "badge": "code"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "city"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "is_active", "is_default"]},
            {"id": "address", "title": "Address", "fields": ["address", "city", "country", "timezone"]},
            {"id": "contact", "title": "Contact", "fields": ["manager_id", "contact_email", "contact_phone"]},
            {"id": "policy", "title": "Policy", "fields": ["allows_negative_stock"]},
            {"id": "rollup", "title": "Contents", "fields": {"read": ["zone_count", "location_count", "distinct_items", "stock_value"]}}
        ],
        "metadata": {
            "allows_negative_stock": {"description": "Leave off. Turning it on lets a bin go below zero, which is almost always a scanning error rather than a business rule."}
        }
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "users", "on": "manager_id", "alias": "manager", "columns": ["name", "email"]}]
    }
}';

comment on column inventory.warehouses.stock_value is '{"name": "Value", "aggregate": "sum"}';

revoke all on table inventory.warehouses
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
delete on table inventory.warehouses to "x-admin";

grant
select
  on table inventory.warehouses to "inventory-planner",
  "user";

grant
select
  (
    id,
    code,
    name,
    address,
    city,
    country,
    timezone,
    manager_id,
    contact_email,
    contact_phone,
    is_active,
    is_default,
    allows_negative_stock,
    zone_count,
    location_count,
    distinct_items,
    created_at,
    updated_at
  ) on table inventory.warehouses to "warehouse";

create unique index idx_inv_warehouse_default on inventory.warehouses (is_default)
where
  is_default;

alter table inventory.warehouses enable row level security;

create policy warehouses_select on inventory.warehouses for
select
  to authenticated using (true);

create policy warehouses_insert on inventory.warehouses for insert to authenticated
with
  check (true);

create policy warehouses_update on inventory.warehouses
for update
  to authenticated using (true)
with
  check (true);

create policy warehouses_delete on inventory.warehouses for delete to authenticated using (true);

create table inventory.zones (
  id uuid primary key default extensions.uuid_generate_v4 (),
  warehouse_id uuid not null references inventory.warehouses (id) on delete cascade,
  code varchar(16) not null,
  name varchar(120) not null,
  zone_type inventory.zone_type not null default 'storage',
  temperature_controlled boolean not null default false,
  pick_sequence integer not null default 100,
  location_count integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (warehouse_id, code)
);

comment on column inventory.zones.zone_type is '{
    "progress": false,
    "values": {
        "inbound": {"variant": "info", "icon": "ArrowDownToLine"},
        "storage": {"variant": "default", "icon": "Boxes"},
        "outbound": {"variant": "success", "icon": "ArrowUpFromLine"},
        "quarantine": {"variant": "destructive", "icon": "ShieldAlert"}
    }
}';

comment on table inventory.zones is '{
    "icon": "LayoutGrid",
    "description": "Areas within a site, and the order they are walked in.",
    "collapsible_group": "Network",
    "display": "block",
    "inline_form": true,
    "primary_view": "kanban",
    "detail": {"header": {"title": "name", "badges": ["code", "zone_type"]}, "tabs": ["locations"]},
    "views": [
        {"id": "kanban", "name": "By Purpose", "type": "kanban", "group": "zone_type", "title": "name", "description": "code", "date": "created_at", "badge": "location_count"},
        {"id": "list", "name": "All Zones", "type": "list", "title": "name", "description": "code", "field_1": "zone_type", "field_2": "location_count"}
    ],
    "filter_presets": [
        {"id": "quarantine", "name": "Quarantine", "filters": [{"id": "zone_type", "value": "quarantine", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["warehouse_id", "code", "name", "zone_type"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["warehouse_id", "code", "name", "zone_type"]},
            {"id": "handling", "title": "Handling", "fields": ["temperature_controlled", "pick_sequence", "is_active"]},
            {"id": "rollup", "title": "Contents", "fields": {"read": ["location_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "pick_sequence", "desc": false}],
        "join": [{"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]}]
    }
}';

revoke all on table inventory.zones
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
delete on table inventory.zones to "x-admin";

grant
select
  on table inventory.zones to "warehouse",
  "inventory-planner",
  "user";

create index idx_inv_zones_warehouse_id on inventory.zones (warehouse_id);

alter table inventory.zones enable row level security;

create policy zones_select on inventory.zones for
select
  to authenticated using (true);

create policy zones_insert on inventory.zones for insert to authenticated
with
  check (true);

create policy zones_update on inventory.zones
for update
  to authenticated using (true)
with
  check (true);

create policy zones_delete on inventory.zones for delete to authenticated using (true);

create table inventory.locations (
  id uuid primary key default extensions.uuid_generate_v4 (),
  warehouse_id uuid not null references inventory.warehouses (id) on delete cascade,
  zone_id uuid references inventory.zones (id) on delete set null,
  code varchar(24) not null,
  barcode varchar(60) unique,
  location_type inventory.location_type not null default 'bin',
  aisle varchar(8),
  rack varchar(8),
  level varchar(8),
  position varchar(8),
  pick_sequence integer not null default 1000,
  max_weight_kg numeric(10, 2),
  max_volume_m3 numeric(10, 4),
  is_pickable boolean not null default true,
  is_receiving boolean not null default false,
  is_quarantine boolean not null default false,
  -- Stock on a lorry is still stock. A transfer ships out of the
  -- source bin and into the destination site's in-transit bin, so
  -- there is no window in which the company owns units the ledger
  -- cannot account for.
  is_in_transit boolean not null default false,
  is_active boolean not null default true,
  distinct_items integer not null default 0,
  total_quantity numeric(14, 3) not null default 0,
  occupancy supasheet.PERCENTAGE,
  last_counted_on date,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (warehouse_id, code)
);

comment on table inventory.locations is '{
    "icon": "MapPin",
    "name": "Bins",
    "description": "The addressable places stock can actually be.",
    "collapsible_group": "Network",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "code", "badges": ["location_type", "is_pickable"]},
        "tabs": ["stock_levels", "stock_movements"]
    },
    "views": [
        {"id": "list", "name": "All Bins", "type": "list", "title": "code", "description": "location_type", "field_1": "distinct_items", "field_2": "total_quantity"},
        {"id": "kanban", "name": "By Type", "type": "kanban", "group": "location_type", "title": "code", "description": "aisle", "date": "last_counted_on", "badge": "distinct_items"},
        {"id": "calendar", "name": "Count History", "type": "calendar", "title": "code", "badge": "location_type", "start_date": "last_counted_on", "read_only": true}
    ],
    "filter_presets": [
        {"id": "occupied", "name": "Occupied", "filters": [{"id": "distinct_items", "value": "0", "operator": "gt"}]},
        {"id": "empty", "name": "Empty", "filters": [{"id": "distinct_items", "value": "0", "operator": "eq"}]},
        {"id": "pickable", "name": "Pickable", "filters": [{"id": "is_pickable", "value": "true", "operator": "eq"}]},
        {"id": "quarantine", "name": "Quarantine", "filters": [{"id": "is_quarantine", "value": "true", "operator": "eq"}]},
        {"id": "in_transit", "name": "In Transit", "filters": [{"id": "is_in_transit", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["warehouse_id", "zone_id", "code", "location_type"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["warehouse_id", "zone_id", "code", "barcode", "location_type"]},
            {"id": "address", "title": "Bin address", "fields": ["aisle", "rack", "level", "position", "pick_sequence"]},
            {"id": "capacity", "title": "Capacity", "fields": ["max_weight_kg", "max_volume_m3"]},
            {"id": "behaviour", "title": "Behaviour", "fields": ["is_pickable", "is_receiving", "is_quarantine", "is_in_transit", "is_active"]},
            {"id": "contents", "title": "Contents", "fields": {"read": ["distinct_items", "total_quantity", "occupancy", "last_counted_on"]}}
        ],
        "lookups": {
            "zone_id": {"filter": [{"source_column": "warehouse_id", "target_column": "warehouse_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "pick_sequence", "desc": false}],
        "join": [
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]},
            {"table": "zones", "on": "zone_id", "columns": ["code", "name", "zone_type"]}
        ]
    }
}';

comment on column inventory.locations.total_quantity is '{"name": "Units", "aggregate": "sum"}';

revoke all on table inventory.locations
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
delete on table inventory.locations to "x-admin";

grant
select
,
update on table inventory.locations to "warehouse";

grant
select
  on table inventory.locations to "inventory-planner",
  "user";

create index idx_inv_locations_warehouse_id on inventory.locations (warehouse_id);

create index idx_inv_locations_zone_id on inventory.locations (zone_id);

create index idx_inv_locations_pickable on inventory.locations (warehouse_id, pick_sequence)
where
  is_pickable
  and is_active;

alter table inventory.locations enable row level security;

create policy locations_select on inventory.locations for
select
  to authenticated using (true);

create policy locations_insert on inventory.locations for insert to authenticated
with
  check (true);

create policy locations_update on inventory.locations
for update
  to authenticated using (true)
with
  check (true);

create policy locations_delete on inventory.locations for delete to authenticated using (true);

----------------------------------------------------------------
-- Suppliers
----------------------------------------------------------------
create table inventory.suppliers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(200) not null,
  status inventory.supplier_status not null default 'active',
  email supasheet.EMAIL,
  phone supasheet.TEL,
  website supasheet.URL,
  contact_name varchar(120),
  address varchar(300),
  country varchar(2),
  currency varchar(3) not null default 'USD',
  payment_terms_days integer not null default 30,
  default_lead_time_days integer not null default 14,
  minimum_order_value numeric(14, 2) not null default 0,
  on_time_rate supasheet.PERCENTAGE,
  quality_rating supasheet.RATING,
  order_count integer not null default 0,
  ordered_value numeric(16, 2) not null default 0,
  open_order_value numeric(16, 2) not null default 0,
  last_order_on date,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column inventory.suppliers.status is '{
    "progress": false,
    "values": {
        "active": {"variant": "success", "icon": "CircleCheck"},
        "on_hold": {"variant": "warning", "icon": "PauseCircle"},
        "inactive": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table inventory.suppliers is '{
    "icon": "Truck",
    "description": "Who the stock is bought from, and how well they deliver.",
    "collapsible_group": "Purchasing",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["code", "status", "quality_rating"]},
        "tabs": ["purchase_orders", "supplier_items"]
    },
    "views": [
        {"id": "list", "name": "All Suppliers", "type": "list", "title": "name", "description": "contact_name", "field_1": "on_time_rate", "field_2": "open_order_value"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "name", "description": "country", "date": "last_order_on", "badge": "quality_rating"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "late", "name": "Poor Delivery", "filters": [{"id": "on_time_rate", "value": "85", "operator": "lt"}]},
        {"id": "open", "name": "With Open Orders", "filters": [{"id": "open_order_value", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "email"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "status", "website"]},
            {"id": "contact", "title": "Contact", "fields": ["contact_name", "email", "phone", "address", "country"]},
            {"id": "terms", "title": "Terms", "fields": ["currency", "payment_terms_days", "default_lead_time_days", "minimum_order_value"]},
            {"id": "performance", "title": "Performance", "fields": ["quality_rating"]},
            {"id": "rollup", "title": "History", "fields": {"read": ["order_count", "ordered_value", "open_order_value", "on_time_rate", "last_order_on"]}},
            {"id": "notes", "title": "Notes", "fields": ["notes"]}
        ]
    },
    "query": {"sort": [{"id": "name", "desc": false}]}
}';

comment on column inventory.suppliers.open_order_value is '{"name": "On Order", "aggregate": "sum"}';

revoke all on table inventory.suppliers
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
delete on table inventory.suppliers to "x-admin";

grant
select
,
  insert,
update on table inventory.suppliers to "inventory-planner";

grant
select
  (
    id,
    code,
    name,
    status,
    email,
    phone,
    contact_name,
    country,
    default_lead_time_days,
    last_order_on
  ) on table inventory.suppliers to "warehouse";

create index idx_inv_suppliers_status on inventory.suppliers (status);

alter table inventory.suppliers enable row level security;

create policy suppliers_select on inventory.suppliers for
select
  to authenticated using (true);

create policy suppliers_insert on inventory.suppliers for insert to authenticated
with
  check (true);

create policy suppliers_update on inventory.suppliers
for update
  to authenticated using (true)
with
  check (true);

create policy suppliers_delete on inventory.suppliers for delete to authenticated using (true);

create table inventory.supplier_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  supplier_id uuid not null references inventory.suppliers (id) on delete cascade,
  item_id uuid not null references inventory.items (id) on delete cascade,
  supplier_sku varchar(60),
  unit_price numeric(14, 4) not null default 0,
  currency varchar(3) not null default 'USD',
  lead_time_days integer not null default 14,
  minimum_order_quantity numeric(14, 3) not null default 1,
  pack_size numeric(12, 3) not null default 1,
  is_preferred boolean not null default false,
  last_purchased_on date,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (supplier_id, item_id),
  constraint supplier_items_moq_positive check (minimum_order_quantity > 0)
);

comment on table inventory.supplier_items is '{
    "icon": "Handshake",
    "name": "Supplier Catalogue",
    "description": "Who can supply what, at what price and how quickly.",
    "collapsible_group": "Purchasing",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "views": [
        {"id": "list", "name": "Catalogue", "type": "list", "title": "supplier_sku", "description": "currency", "field_1": "unit_price", "field_2": "lead_time_days"}
    ],
    "filter_presets": [
        {"id": "preferred", "name": "Preferred", "filters": [{"id": "is_preferred", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["supplier_id", "item_id", "unit_price"],
        "sections": [
            {"id": "link", "title": "Link", "fields": ["supplier_id", "item_id", "supplier_sku", "is_preferred"]},
            {"id": "terms", "title": "Terms", "fields": ["unit_price", "currency", "lead_time_days", "minimum_order_quantity", "pack_size"]},
            {"id": "history", "title": "History", "fields": {"read": ["last_purchased_on"]}}
        ]
    },
    "query": {
        "sort": [{"id": "unit_price", "desc": false}],
        "join": [
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name", "status"]},
            {"table": "items", "on": "item_id", "columns": ["sku", "name"]}
        ]
    }
}';

revoke all on table inventory.supplier_items
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
delete on table inventory.supplier_items to "x-admin",
"inventory-planner";

create index idx_inv_supplier_items_supplier_id on inventory.supplier_items (supplier_id);

create index idx_inv_supplier_items_item_id on inventory.supplier_items (item_id);

create unique index idx_inv_supplier_items_preferred on inventory.supplier_items (item_id)
where
  is_preferred;

alter table inventory.supplier_items enable row level security;

create policy supplier_items_select on inventory.supplier_items for
select
  to authenticated using (true);

create policy supplier_items_insert on inventory.supplier_items for insert to authenticated
with
  check (true);

create policy supplier_items_update on inventory.supplier_items
for update
  to authenticated using (true)
with
  check (true);

create policy supplier_items_delete on inventory.supplier_items for delete to authenticated using (true);

----------------------------------------------------------------
-- Lots and serials
----------------------------------------------------------------
create table inventory.lots (
  id uuid primary key default extensions.uuid_generate_v4 (),
  item_id uuid not null references inventory.items (id) on delete cascade,
  lot_code varchar(60) not null,
  supplier_id uuid references inventory.suppliers (id) on delete set null,
  status inventory.lot_status not null default 'available',
  manufactured_on date,
  received_on date not null default current_date,
  expires_on date,
  supplier_lot_code varchar(60),
  received_quantity numeric(14, 3) not null default 0,
  on_hand numeric(14, 3) not null default 0,
  unit_cost numeric(14, 4) not null default 0,
  days_to_expiry integer,
  certificate supasheet.file,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (item_id, lot_code),
  constraint lots_expiry_after_manufacture check (
    expires_on is null
    or manufactured_on is null
    or expires_on >= manufactured_on
  )
);

comment on column inventory.lots.status is '{
    "progress": true,
    "values": {
        "available": {"variant": "success", "icon": "CircleCheck"},
        "quarantine": {"variant": "warning", "icon": "ShieldAlert"},
        "expired": {"variant": "destructive", "icon": "CalendarX"},
        "recalled": {"variant": "destructive", "icon": "TriangleAlert"},
        "consumed": {"variant": "secondary", "icon": "PackageMinus"}
    }
}';

comment on table inventory.lots is '{
    "icon": "Boxes",
    "description": "Batches of a tracked item, with where they came from and when they expire.",
    "collapsible_group": "Stock",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "lot_code", "badges": ["status", "expires_on"]},
        "tabs": ["stock_levels", "stock_movements"]
    },
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "lot_code", "description": "supplier_lot_code", "date": "expires_on", "badge": "on_hand"},
        {"id": "calendar", "name": "Expiry Calendar", "type": "calendar", "title": "lot_code", "badge": "status", "start_date": "expires_on"},
        {"id": "list", "name": "All Lots", "type": "list", "title": "lot_code", "description": "status", "field_1": "on_hand", "field_2": "expires_on"},
        {"id": "gantt", "name": "Shelf Life", "type": "gantt", "title": "lot_code", "start_date": "received_on", "end_date": "expires_on", "group": "status", "badge": "on_hand"}
    ],
    "filter_presets": [
        {"id": "in_stock", "name": "In Stock", "filters": [{"id": "on_hand", "value": "0", "operator": "gt"}]},
        {"id": "expiring", "name": "Expiring Soon", "filters": [{"id": "days_to_expiry", "value": "45", "operator": "lte"}]},
        {"id": "quarantine", "name": "Quarantined", "filters": [{"id": "status", "value": "quarantine", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["item_id", "lot_code", "expires_on"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["item_id", "lot_code", "status"]},
            {"id": "provenance", "title": "Provenance", "fields": ["supplier_id", "supplier_lot_code", "manufactured_on", "received_on", "certificate"]},
            {"id": "shelf_life", "title": "Shelf life", "fields": ["expires_on"]},
            {"id": "position", "title": "Position", "fields": {"read": ["received_quantity", "on_hand", "unit_cost", "days_to_expiry"]}},
            {"id": "note", "title": "Note", "fields": ["note"]}
        ]
    },
    "query": {
        "sort": [{"id": "expires_on", "desc": false}],
        "join": [
            {"table": "items", "on": "item_id", "columns": ["sku", "name", "tracking"]},
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column inventory.lots.certificate is '{"accept": ".pdf,.png,.jpg", "max_files": 2, "max_size": 5242880}';

comment on column inventory.lots.on_hand is '{"name": "On Hand", "aggregate": "sum"}';

revoke all on table inventory.lots
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
delete on table inventory.lots to "x-admin";

grant
select
,
  insert,
update on table inventory.lots to "warehouse";

grant
select
  on table inventory.lots to "inventory-planner",
  "user";

create index idx_inv_lots_item_id on inventory.lots (item_id);

create index idx_inv_lots_expiry on inventory.lots (expires_on)
where
  on_hand > 0;

alter table inventory.lots enable row level security;

create policy lots_select on inventory.lots for
select
  to authenticated using (true);

create policy lots_insert on inventory.lots for insert to authenticated
with
  check (true);

create policy lots_update on inventory.lots
for update
  to authenticated using (true)
with
  check (true);

create policy lots_delete on inventory.lots for delete to authenticated using (true);

create table inventory.serials (
  id uuid primary key default extensions.uuid_generate_v4 (),
  item_id uuid not null references inventory.items (id) on delete cascade,
  serial_number varchar(80) not null,
  lot_id uuid references inventory.lots (id) on delete set null,
  receipt_line_id uuid,
  status inventory.serial_status not null default 'in_stock',
  location_id uuid references inventory.locations (id) on delete set null,
  warranty_expires_on date,
  received_on date not null default current_date,
  shipped_on date,
  unit_cost numeric(14, 4) not null default 0,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (item_id, serial_number)
);

comment on column inventory.serials.status is '{
    "progress": true,
    "values": {
        "in_stock": {"variant": "success", "icon": "PackageCheck"},
        "allocated": {"variant": "info", "icon": "Lock"},
        "shipped": {"variant": "secondary", "icon": "Send"},
        "scrapped": {"variant": "destructive", "icon": "Trash2"},
        "returned": {"variant": "warning", "icon": "Undo2"}
    }
}';

comment on table inventory.serials is '{
    "icon": "ScanBarcode",
    "name": "Serial Numbers",
    "description": "Individually tracked units, and the one place each of them is.",
    "collapsible_group": "Stock",
    "display": "block",
    "primary_view": "kanban",
    "detail": {"header": {"title": "serial_number", "badges": ["status", "warranty_expires_on"]}, "tabs": ["stock_movements"]},
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "serial_number", "description": "note", "date": "received_on", "badge": "status"},
        {"id": "list", "name": "All Serials", "type": "list", "title": "serial_number", "description": "status", "field_1": "received_on", "field_2": "warranty_expires_on"}
    ],
    "filter_presets": [
        {"id": "in_stock", "name": "In Stock", "filters": [{"id": "status", "value": "in_stock", "operator": "eq"}]},
        {"id": "shipped", "name": "Shipped", "filters": [{"id": "status", "value": "shipped", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["item_id", "serial_number"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["item_id", "serial_number", "lot_id", "status"]},
            {"id": "provenance", "title": "Provenance", "fields": {"read": ["receipt_line_id"]}},
            {"id": "where", "title": "Where", "fields": ["location_id", "received_on", "shipped_on"]},
            {"id": "warranty", "title": "Warranty", "fields": ["warranty_expires_on", "note"]}
        ],
        "behavior": {
            "shipped_on": {"visible": [{"id": "status", "operator": "eq", "value": "shipped"}]},
            "location_id": {"visible": [{"id": "status", "operator": "in", "value": ["in_stock", "allocated", "returned"]}]}
        }
    },
    "query": {
        "sort": [{"id": "serial_number", "desc": false}],
        "join": [
            {"table": "items", "on": "item_id", "columns": ["sku", "name"]},
            {"table": "locations", "on": "location_id", "columns": ["code"]},
            {"table": "lots", "on": "lot_id", "columns": ["lot_code"]}
        ]
    }
}';

revoke all on table inventory.serials
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
delete on table inventory.serials to "x-admin";

grant
select
,
  insert,
update on table inventory.serials to "warehouse";

grant
select
  on table inventory.serials to "inventory-planner";

create index idx_inv_serials_item_id on inventory.serials (item_id);

create index idx_inv_serials_location_id on inventory.serials (location_id);

create index idx_inv_serials_status on inventory.serials (status);

alter table inventory.serials enable row level security;

create policy serials_select on inventory.serials for
select
  to authenticated using (true);

create policy serials_insert on inventory.serials for insert to authenticated
with
  check (true);

create policy serials_update on inventory.serials
for update
  to authenticated using (true)
with
  check (true);

create policy serials_delete on inventory.serials for delete to authenticated using (true);

----------------------------------------------------------------
-- The stock ledger
--
-- APPEND ONLY. No role holds UPDATE or DELETE on this table — not the
-- warehouse, not the planner, not the inventory manager. A movement
-- that was wrong is corrected by another movement, which is why the
-- adjustment tables further down exist at all.
--
-- Quantity is SIGNED against the location: positive is stock arriving
-- in that bin, negative is stock leaving it. A transfer is therefore
-- two rows that sum to zero, and there is no state in which stock has
-- left one bin without arriving somewhere.
----------------------------------------------------------------
create sequence if not exists inventory.movement_number_seq;

create table inventory.stock_movements (
  id uuid primary key default extensions.uuid_generate_v4 (),
  movement_number varchar(30) not null unique default (
    'MV-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('inventory.movement_number_seq')::text,
      7,
      '0'
    )
  ),
  item_id uuid not null references inventory.items (id) on delete restrict,
  location_id uuid not null references inventory.locations (id) on delete restrict,
  lot_id uuid references inventory.lots (id) on delete restrict,
  serial_id uuid references inventory.serials (id) on delete restrict,
  movement_type inventory.movement_type not null,
  quantity numeric(14, 3) not null,
  balance_after numeric(14, 3),
  uom_id uuid references inventory.unit_of_measures (id) on delete set null,
  unit_cost numeric(14, 4) not null default 0,
  total_cost numeric(16, 4) not null default 0,
  reference_type varchar(30),
  reference_id uuid,
  reference_number varchar(40),
  -- The inbound half of a move points at the outbound half it came
  -- from. One directed edge, set when the row is written — a mutual
  -- pair would need an UPDATE, and there is no UPDATE on this table.
  counterpart_id uuid references inventory.stock_movements (id) on delete set null,
  occurred_at timestamptz not null default current_timestamp,
  performed_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  constraint movements_quantity_not_zero check (quantity <> 0)
);

comment on column inventory.stock_movements.movement_type is '{
    "progress": false,
    "values": {
        "receipt": {"variant": "success", "icon": "ArrowDownToLine"},
        "putaway": {"variant": "info", "icon": "PackagePlus"},
        "pick": {"variant": "warning", "icon": "HandGrab"},
        "ship": {"variant": "secondary", "icon": "Send"},
        "transfer_out": {"variant": "warning", "icon": "ArrowUpFromLine"},
        "transfer_in": {"variant": "info", "icon": "ArrowDownToLine"},
        "adjustment_in": {"variant": "success", "icon": "Plus"},
        "adjustment_out": {"variant": "destructive", "icon": "Minus"},
        "count_in": {"variant": "success", "icon": "ClipboardCheck"},
        "count_out": {"variant": "destructive", "icon": "ClipboardX"},
        "return_in": {"variant": "info", "icon": "Undo2"},
        "scrap": {"variant": "destructive", "icon": "Trash2"}
    }
}';

comment on table inventory.stock_movements is '{
    "icon": "ArrowLeftRight",
    "name": "Stock Ledger",
    "description": "Every unit that moved, where from, where to and who did it. Append only.",
    "collapsible_group": "Stock",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "movement_number", "badges": ["movement_type", "quantity"]}},
    "views": [
        {"id": "list", "name": "All Movements", "type": "list", "title": "movement_number", "description": "reference_number", "field_1": "movement_type", "field_2": "quantity", "read_only": true},
        {"id": "kanban", "name": "By Type", "type": "kanban", "group": "movement_type", "title": "movement_number", "description": "reference_number", "date": "occurred_at", "badge": "quantity", "read_only": true},
        {"id": "calendar", "name": "By Day", "type": "calendar", "title": "movement_number", "badge": "movement_type", "start_date": "occurred_at", "read_only": true}
    ],
    "filter_presets": [
        {"id": "in", "name": "Stock In", "filters": [{"id": "quantity", "value": "0", "operator": "gt"}]},
        {"id": "out", "name": "Stock Out", "filters": [{"id": "quantity", "value": "0", "operator": "lt"}]},
        {"id": "adjustments", "name": "Adjustments", "filters": [{"id": "movement_type", "value": ["adjustment_in", "adjustment_out"], "operator": "in"}]}
    ],
    "fields": {
        "sections": [
            {"id": "what", "title": "What moved", "fields": {"read": ["movement_number", "item_id", "quantity", "uom_id", "movement_type"]}},
            {"id": "where", "title": "Where", "fields": {"read": ["location_id", "lot_id", "serial_id", "balance_after"]}},
            {"id": "why", "title": "Why", "fields": {"read": ["reference_type", "reference_number", "counterpart_id", "note"]}},
            {"id": "who", "title": "Who and when", "fields": {"read": ["performed_by", "occurred_at"]}}
        ]
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [
            {"table": "items", "on": "item_id", "columns": ["sku", "name"]},
            {"table": "locations", "on": "location_id", "columns": ["code"]},
            {"table": "lots", "on": "lot_id", "columns": ["lot_code"]},
            {"table": "users", "on": "performed_by", "alias": "operator", "columns": ["name"]}
        ]
    }
}';

comment on column inventory.stock_movements.quantity is '{"aggregate": "sum"}';

revoke all on table inventory.stock_movements
from
  public,
  anon,
  authenticated,
  service_role;

-- SELECT only, and nobody holds INSERT either. The single door into
-- the ledger is inventory.post_movement (), which is SECURITY DEFINER
-- — so every write goes through the guard that checks tracking,
-- negative stock and bin state, and none can go around it.
--
-- The cost columns are absent from the warehouse grant for the same
-- reason they are absent from items: the floor moves stock, it does
-- not price it.
grant
select
  on table inventory.stock_movements to "x-admin";

grant
select
  (
    id,
    movement_number,
    item_id,
    location_id,
    lot_id,
    serial_id,
    movement_type,
    quantity,
    balance_after,
    uom_id,
    reference_type,
    reference_id,
    reference_number,
    counterpart_id,
    occurred_at,
    performed_by,
    note,
    created_at
  ) on table inventory.stock_movements to "warehouse",
  "inventory-planner";

revoke all on sequence inventory.movement_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence inventory.movement_number_seq to "x-admin";

create index idx_inv_movements_item_id on inventory.stock_movements (item_id);

create index idx_inv_movements_location_id on inventory.stock_movements (location_id);

create index idx_inv_movements_lot_id on inventory.stock_movements (lot_id);

create index idx_inv_movements_occurred on inventory.stock_movements (occurred_at desc);

create index idx_inv_movements_reference on inventory.stock_movements (reference_type, reference_id);

create index idx_inv_movements_item_location on inventory.stock_movements (item_id, location_id, occurred_at desc);

alter table inventory.stock_movements enable row level security;

create policy movements_select on inventory.stock_movements for
select
  to authenticated using (true);

create policy movements_insert on inventory.stock_movements for insert to authenticated
with
  check (true);

----------------------------------------------------------------
-- Stock levels
--
-- The ledger summed by item, bin and lot. Nothing writes to this
-- table except the trigger on the ledger, which is why it can be
-- trusted as the answer to "what is in this bin".
----------------------------------------------------------------
create table inventory.stock_levels (
  id uuid primary key default extensions.uuid_generate_v4 (),
  item_id uuid not null references inventory.items (id) on delete cascade,
  location_id uuid not null references inventory.locations (id) on delete cascade,
  lot_id uuid references inventory.lots (id) on delete cascade,
  warehouse_id uuid references inventory.warehouses (id) on delete cascade,
  on_hand numeric(14, 3) not null default 0,
  allocated numeric(14, 3) not null default 0,
  available numeric(14, 3) not null default 0,
  unit_cost numeric(14, 4) not null default 0,
  stock_value numeric(16, 2) not null default 0,
  last_movement_at timestamptz,
  last_counted_on date,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint stock_levels_allocated_within_hand check (allocated <= on_hand),
  constraint stock_levels_allocated_non_negative check (allocated >= 0)
);

comment on table inventory.stock_levels is '{
    "icon": "LayoutList",
    "name": "Stock On Hand",
    "description": "What is in which bin, from which lot, and how much of it is already spoken for.",
    "collapsible_group": "Stock",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "on_hand", "badges": ["available", "allocated"]}},
    "views": [
        {"id": "list", "name": "By Bin", "type": "list", "title": "on_hand", "description": "available", "field_1": "allocated", "field_2": "last_movement_at", "read_only": true}
    ],
    "filter_presets": [
        {"id": "in_stock", "name": "In Stock", "filters": [{"id": "on_hand", "value": "0", "operator": "gt"}]},
        {"id": "allocated", "name": "Has Allocation", "filters": [{"id": "allocated", "value": "0", "operator": "gt"}]},
        {"id": "negative", "name": "Negative", "filters": [{"id": "on_hand", "value": "0", "operator": "lt"}]}
    ],
    "fields": {
        "sections": [
            {"id": "what", "title": "What and where", "fields": {"read": ["item_id", "warehouse_id", "location_id", "lot_id"]}},
            {"id": "position", "title": "Position", "fields": {"read": ["on_hand", "allocated", "available", "unit_cost", "stock_value"]}},
            {"id": "history", "title": "History", "fields": {"read": ["last_movement_at", "last_counted_on"]}}
        ]
    },
    "query": {
        "sort": [{"id": "on_hand", "desc": true}],
        "join": [
            {"table": "items", "on": "item_id", "columns": ["sku", "name", "tracking"]},
            {"table": "locations", "on": "location_id", "columns": ["code", "pick_sequence"]},
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]},
            {"table": "lots", "on": "lot_id", "columns": ["lot_code", "expires_on"]}
        ]
    }
}';

comment on column inventory.stock_levels.on_hand is '{"name": "On Hand", "aggregate": "sum"}';

comment on column inventory.stock_levels.available is '{"aggregate": "sum"}';

comment on column inventory.stock_levels.stock_value is '{"name": "Value", "aggregate": "sum"}';

revoke all on table inventory.stock_levels
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on table inventory.stock_levels to "x-admin";

grant
select
  (
    id,
    item_id,
    location_id,
    lot_id,
    warehouse_id,
    on_hand,
    allocated,
    available,
    last_movement_at,
    last_counted_on,
    created_at,
    updated_at
  ) on table inventory.stock_levels to "warehouse",
  "inventory-planner",
  "user";

-- A bin holds one balance per item and lot. Coalescing the lot means
-- untracked stock still gets exactly one row rather than a new one
-- per movement, which NULLs in a unique index would otherwise allow.
create unique index idx_inv_stock_levels_key on inventory.stock_levels (
  item_id,
  location_id,
  coalesce(
    lot_id,
    '00000000-0000-0000-0000-000000000000'::uuid
  )
);

create index idx_inv_stock_levels_item_id on inventory.stock_levels (item_id);

create index idx_inv_stock_levels_location_id on inventory.stock_levels (location_id);

create index idx_inv_stock_levels_warehouse_id on inventory.stock_levels (warehouse_id);

create index idx_inv_stock_levels_available on inventory.stock_levels (item_id, available)
where
  available > 0;

alter table inventory.stock_levels enable row level security;

create policy stock_levels_select on inventory.stock_levels for
select
  to authenticated using (true);

----------------------------------------------------------------
-- Purchase orders
----------------------------------------------------------------
create sequence if not exists inventory.po_number_seq;

create table inventory.purchase_orders (
  id uuid primary key default extensions.uuid_generate_v4 (),
  po_number varchar(30) not null unique default (
    'PO-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('inventory.po_number_seq')::text, 5, '0')
  ),
  supplier_id uuid not null references inventory.suppliers (id) on delete restrict,
  warehouse_id uuid not null references inventory.warehouses (id) on delete restrict,
  status inventory.po_status not null default 'draft',
  priority inventory.priority not null default 'normal',
  ordered_on date not null default current_date,
  expected_on date,
  received_on date,
  currency varchar(3) not null default 'USD',
  subtotal numeric(16, 2) not null default 0,
  freight numeric(14, 2) not null default 0,
  total numeric(16, 2) not null default 0,
  line_count integer not null default 0,
  ordered_quantity numeric(14, 3) not null default 0,
  received_quantity numeric(14, 3) not null default 0,
  outstanding_quantity numeric(14, 3) not null default 0,
  fill_rate supasheet.PERCENTAGE,
  days_late integer not null default 0,
  supplier_reference varchar(60),
  approved_by uuid references supasheet.users (id) on delete set null,
  approved_at timestamptz,
  cancelled_reason varchar(300),
  document supasheet.file,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint po_expected_after_order check (
    expected_on is null
    or expected_on >= ordered_on
  )
);

comment on column inventory.purchase_orders.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "submitted": {"variant": "warning", "icon": "Send"},
        "approved": {"variant": "info", "icon": "CircleCheck"},
        "partially_received": {"variant": "warning", "icon": "PackageOpen"},
        "received": {"variant": "success", "icon": "PackageCheck"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on column inventory.purchase_orders.priority is '{
    "progress": true,
    "values": {
        "low": {"variant": "secondary", "icon": "ChevronDown"},
        "normal": {"variant": "default", "icon": "Minus"},
        "high": {"variant": "warning", "icon": "ChevronUp"},
        "urgent": {"variant": "destructive", "icon": "ChevronsUp"}
    }
}';

comment on table inventory.purchase_orders is '{
    "icon": "ShoppingCart",
    "name": "Purchase Orders",
    "description": "What has been ordered in, from whom, and how much of it has actually turned up.",
    "collapsible_group": "Purchasing",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "po_number", "badges": ["status", "priority", "total"]},
        "tabs": ["purchase_order_lines", "receipts"]
    },
    "views": [
        {"id": "kanban", "name": "Order Board", "type": "kanban", "group": "status", "title": "po_number", "description": "supplier_reference", "date": "expected_on", "badge": "priority"},
        {"id": "gantt", "name": "Lead Times", "type": "gantt", "title": "po_number", "start_date": "ordered_on", "end_date": "expected_on", "group": "status", "badge": "priority"},
        {"id": "calendar", "name": "Expected In", "type": "calendar", "title": "po_number", "badge": "status", "start_date": "expected_on"},
        {"id": "list", "name": "All Orders", "type": "list", "title": "po_number", "description": "status", "field_1": "total", "field_2": "expected_on"}
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["approved", "partially_received"], "operator": "in"}]},
        {"id": "awaiting", "name": "To Approve", "filters": [{"id": "status", "value": "submitted", "operator": "eq"}]},
        {"id": "late", "name": "Late", "filters": [{"id": "days_late", "value": "0", "operator": "gt"}]},
        {"id": "urgent", "name": "Urgent", "filters": [{"id": "priority", "value": "urgent", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["supplier_id", "warehouse_id", "expected_on", "priority"],
        "sections": [
            {"id": "order", "title": "Order", "fields": ["supplier_id", "warehouse_id", "ordered_on", "expected_on", "priority", "currency"]},
            {"id": "state", "title": "State", "fields": ["status", "cancelled_reason"]},
            {"id": "reference", "title": "Reference", "fields": ["supplier_reference", "document", "notes"]},
            {"id": "money", "title": "Money", "fields": ["freight"], "read": ["subtotal", "total"]},
            {"id": "fulfilment", "title": "Fulfilment", "fields": {"read": ["line_count", "ordered_quantity", "received_quantity", "outstanding_quantity", "fill_rate", "days_late", "received_on", "approved_by", "approved_at"]}}
        ],
        "behavior": {
            "cancelled_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "cancelled"}],
                "required": [{"id": "status", "operator": "eq", "value": "cancelled"}]
            }
        },
        "lookups": {
            "supplier_id": {"filter": [{"source_column": "status", "target_column": "status"}]}
        }
    },
    "query": {
        "sort": [{"id": "ordered_on", "desc": true}],
        "join": [
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name", "status"]},
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column inventory.purchase_orders.total is '{"aggregate": "sum"}';

comment on column inventory.purchase_orders.document is '{"accept": ".pdf", "max_files": 2, "max_size": 5242880}';

revoke all on table inventory.purchase_orders
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
delete on table inventory.purchase_orders to "x-admin";

grant
select
,
  insert,
update on table inventory.purchase_orders to "inventory-planner";

grant
select
  (
    id,
    po_number,
    supplier_id,
    warehouse_id,
    status,
    priority,
    ordered_on,
    expected_on,
    received_on,
    line_count,
    ordered_quantity,
    received_quantity,
    outstanding_quantity,
    supplier_reference,
    notes,
    created_at,
    updated_at
  ) on table inventory.purchase_orders to "warehouse";

revoke all on sequence inventory.po_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence inventory.po_number_seq to "x-admin",
"inventory-planner";

create index idx_inv_po_supplier_id on inventory.purchase_orders (supplier_id);

create index idx_inv_po_warehouse_id on inventory.purchase_orders (warehouse_id);

create index idx_inv_po_status on inventory.purchase_orders (status);

create index idx_inv_po_open on inventory.purchase_orders (expected_on)
where
  status in ('approved', 'partially_received');

alter table inventory.purchase_orders enable row level security;

create policy po_select on inventory.purchase_orders for
select
  to authenticated using (true);

create policy po_insert on inventory.purchase_orders for insert to authenticated
with
  check (true);

create policy po_update on inventory.purchase_orders
for update
  to authenticated using (true)
with
  check (true);

create policy po_delete on inventory.purchase_orders for delete to authenticated using (true);

create table inventory.purchase_order_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  purchase_order_id uuid not null references inventory.purchase_orders (id) on delete cascade,
  item_id uuid not null references inventory.items (id) on delete restrict,
  line_number integer,
  description varchar(300),
  ordered_quantity numeric(14, 3) not null,
  received_quantity numeric(14, 3) not null default 0,
  outstanding_quantity numeric(14, 3) not null default 0,
  unit_price numeric(14, 4) not null default 0,
  line_total numeric(16, 2) not null default 0,
  expected_on date,
  is_closed boolean not null default false,
  created_at timestamptz default current_timestamp,
  constraint po_lines_ordered_positive check (ordered_quantity > 0),
  constraint po_lines_not_over_received check (received_quantity <= ordered_quantity * 1.1)
);

comment on table inventory.purchase_order_lines is '{
    "icon": "List",
    "name": "Order Lines",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["purchase_order_id", "item_id", "description", "expected_on"]},
            {"id": "quantity", "title": "Quantity", "fields": ["ordered_quantity", "unit_price"]},
            {"id": "progress", "title": "Progress", "fields": {"read": ["received_quantity", "outstanding_quantity", "line_total", "is_closed"]}}
        ]
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "items", "on": "item_id", "columns": ["sku", "name", "tracking"]},
            {"table": "purchase_orders", "on": "purchase_order_id", "columns": ["po_number", "status"]}
        ]
    }
}';

comment on column inventory.purchase_order_lines.ordered_quantity is '{"name": "Ordered", "aggregate": "sum"}';

revoke all on table inventory.purchase_order_lines
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
delete on table inventory.purchase_order_lines to "x-admin",
"inventory-planner";

grant
select
  (
    id,
    purchase_order_id,
    item_id,
    line_number,
    description,
    ordered_quantity,
    received_quantity,
    outstanding_quantity,
    expected_on,
    is_closed,
    created_at
  ) on table inventory.purchase_order_lines to "warehouse";

create index idx_inv_po_lines_po_id on inventory.purchase_order_lines (purchase_order_id);

create index idx_inv_po_lines_item_id on inventory.purchase_order_lines (item_id);

alter table inventory.purchase_order_lines enable row level security;

create policy po_lines_select on inventory.purchase_order_lines for
select
  to authenticated using (true);

create policy po_lines_insert on inventory.purchase_order_lines for insert to authenticated
with
  check (true);

create policy po_lines_update on inventory.purchase_order_lines
for update
  to authenticated using (true)
with
  check (true);

create policy po_lines_delete on inventory.purchase_order_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Goods receipt
--
-- Receiving is two steps on purpose. A receipt books stock into the
-- inbound bin and no further; put-away is what moves it to where it
-- will actually be picked from. Collapsing the two is how stock ends
-- up "in the warehouse" and nowhere findable.
----------------------------------------------------------------
create sequence if not exists inventory.receipt_number_seq;

create table inventory.receipts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  receipt_number varchar(30) not null unique default (
    'GRN-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('inventory.receipt_number_seq')::text,
      5,
      '0'
    )
  ),
  purchase_order_id uuid references inventory.purchase_orders (id) on delete set null,
  supplier_id uuid references inventory.suppliers (id) on delete set null,
  warehouse_id uuid not null references inventory.warehouses (id) on delete restrict,
  dock_location_id uuid references inventory.locations (id) on delete set null,
  status inventory.receipt_status not null default 'draft',
  received_on date not null default current_date,
  carrier varchar(120),
  tracking_number varchar(80),
  packing_slip varchar(60),
  line_count integer not null default 0,
  total_quantity numeric(14, 3) not null default 0,
  put_away_quantity numeric(14, 3) not null default 0,
  has_discrepancy boolean not null default false,
  received_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  put_away_at timestamptz,
  document supasheet.file,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column inventory.receipts.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "checking": {"variant": "warning", "icon": "ScanSearch"},
        "put_away": {"variant": "success", "icon": "PackageCheck"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table inventory.receipts is '{
    "icon": "PackageOpen",
    "name": "Goods Receipts",
    "description": "What arrived on the dock, and whether it has been put away yet.",
    "collapsible_group": "Inbound",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "receipt_number", "badges": ["status", "has_discrepancy"]},
        "tabs": ["receipt_lines"]
    },
    "views": [
        {"id": "kanban", "name": "Dock Board", "type": "kanban", "group": "status", "title": "receipt_number", "description": "carrier", "date": "received_on", "badge": "total_quantity"},
        {"id": "calendar", "name": "Arrivals", "type": "calendar", "title": "receipt_number", "badge": "status", "start_date": "received_on"},
        {"id": "list", "name": "All Receipts", "type": "list", "title": "receipt_number", "description": "carrier", "field_1": "total_quantity", "field_2": "received_on"}
    ],
    "filter_presets": [
        {"id": "to_put_away", "name": "To Put Away", "filters": [{"id": "status", "value": "checking", "operator": "eq"}]},
        {"id": "discrepancies", "name": "With Discrepancies", "filters": [{"id": "has_discrepancy", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["purchase_order_id", "warehouse_id", "received_on"],
        "sections": [
            {"id": "delivery", "title": "Delivery", "fields": ["purchase_order_id", "supplier_id", "warehouse_id", "dock_location_id", "received_on"]},
            {"id": "carrier", "title": "Carrier", "fields": ["carrier", "tracking_number", "packing_slip", "document"]},
            {"id": "state", "title": "State", "fields": ["status", "notes"]},
            {"id": "rollup", "title": "Contents", "fields": {"read": ["line_count", "total_quantity", "put_away_quantity", "has_discrepancy", "received_by", "put_away_at"]}}
        ],
        "lookups": {
            "dock_location_id": {"filter": [{"source_column": "warehouse_id", "target_column": "warehouse_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "received_on", "desc": true}],
        "join": [
            {"table": "purchase_orders", "on": "purchase_order_id", "columns": ["po_number", "status"]},
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name"]},
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column inventory.receipts.document is '{"accept": ".pdf,.png,.jpg", "max_files": 3, "max_size": 5242880}';

revoke all on table inventory.receipts
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
delete on table inventory.receipts to "x-admin";

grant
select
,
  insert,
update on table inventory.receipts to "warehouse";

grant
select
  on table inventory.receipts to "inventory-planner";

revoke all on sequence inventory.receipt_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence inventory.receipt_number_seq to "x-admin",
"warehouse";

create index idx_inv_receipts_po_id on inventory.receipts (purchase_order_id);

create index idx_inv_receipts_warehouse_id on inventory.receipts (warehouse_id);

create index idx_inv_receipts_status on inventory.receipts (status);

alter table inventory.receipts enable row level security;

create policy receipts_select on inventory.receipts for
select
  to authenticated using (true);

create policy receipts_insert on inventory.receipts for insert to authenticated
with
  check (true);

create policy receipts_update on inventory.receipts
for update
  to authenticated using (true)
with
  check (true);

create policy receipts_delete on inventory.receipts for delete to authenticated using (true);

create table inventory.receipt_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  receipt_id uuid not null references inventory.receipts (id) on delete cascade,
  purchase_order_line_id uuid references inventory.purchase_order_lines (id) on delete set null,
  item_id uuid not null references inventory.items (id) on delete restrict,
  lot_id uuid references inventory.lots (id) on delete set null,
  line_number integer,
  expected_quantity numeric(14, 3) not null default 0,
  received_quantity numeric(14, 3) not null,
  rejected_quantity numeric(14, 3) not null default 0,
  variance_quantity numeric(14, 3) not null default 0,
  unit_cost numeric(14, 4) not null default 0,
  lot_code varchar(60),
  expires_on date,
  put_away_location_id uuid references inventory.locations (id) on delete set null,
  is_put_away boolean not null default false,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  constraint receipt_lines_received_non_negative check (received_quantity >= 0),
  constraint receipt_lines_rejected_within check (rejected_quantity <= received_quantity)
);

comment on table inventory.receipt_lines is '{
    "icon": "List",
    "name": "Receipt Lines",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["receipt_id", "purchase_order_line_id", "item_id"]},
            {"id": "quantity", "title": "Quantity", "fields": ["received_quantity", "rejected_quantity", "unit_cost"]},
            {"id": "tracking", "title": "Tracking", "fields": ["lot_code", "expires_on"]},
            {"id": "putaway", "title": "Put away", "fields": ["put_away_location_id", "note"]},
            {"id": "derived", "title": "Derived", "fields": {"read": ["expected_quantity", "variance_quantity", "lot_id", "is_put_away"]}}
        ],
        "behavior": {
            "lot_code": {"visible": [{"id": "expires_on", "operator": "neq", "value": null}]}
        }
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "items", "on": "item_id", "columns": ["sku", "name", "tracking"]},
            {"table": "receipts", "on": "receipt_id", "columns": ["receipt_number", "status"]},
            {"table": "locations", "on": "put_away_location_id", "alias": "bin", "columns": ["code"]}
        ]
    }
}';

comment on column inventory.receipt_lines.received_quantity is '{"name": "Received", "aggregate": "sum"}';

revoke all on table inventory.receipt_lines
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
delete on table inventory.receipt_lines to "x-admin",
"warehouse";

grant
select
  (
    id,
    receipt_id,
    purchase_order_line_id,
    item_id,
    lot_id,
    line_number,
    expected_quantity,
    received_quantity,
    rejected_quantity,
    variance_quantity,
    lot_code,
    expires_on,
    put_away_location_id,
    is_put_away,
    note,
    created_at
  ) on table inventory.receipt_lines to "inventory-planner";

create index idx_inv_receipt_lines_receipt_id on inventory.receipt_lines (receipt_id);

create index idx_inv_receipt_lines_item_id on inventory.receipt_lines (item_id);

alter table inventory.receipt_lines enable row level security;

create policy receipt_lines_select on inventory.receipt_lines for
select
  to authenticated using (true);

create policy receipt_lines_insert on inventory.receipt_lines for insert to authenticated
with
  check (true);

create policy receipt_lines_update on inventory.receipt_lines
for update
  to authenticated using (true)
with
  check (true);

create policy receipt_lines_delete on inventory.receipt_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Internal transfers
----------------------------------------------------------------
create sequence if not exists inventory.transfer_number_seq;

create table inventory.stock_transfers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  transfer_number varchar(30) not null unique default (
    'TRF-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('inventory.transfer_number_seq')::text,
      5,
      '0'
    )
  ),
  from_warehouse_id uuid not null references inventory.warehouses (id) on delete restrict,
  to_warehouse_id uuid not null references inventory.warehouses (id) on delete restrict,
  status inventory.transfer_status not null default 'draft',
  priority inventory.priority not null default 'normal',
  requested_on date not null default current_date,
  shipped_on date,
  expected_on date,
  received_on date,
  reason varchar(200),
  carrier varchar(120),
  tracking_number varchar(80),
  line_count integer not null default 0,
  total_quantity numeric(14, 3) not null default 0,
  received_quantity numeric(14, 3) not null default 0,
  in_transit_quantity numeric(14, 3) not null default 0,
  requested_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint transfers_different_sites check (from_warehouse_id <> to_warehouse_id)
);

comment on column inventory.stock_transfers.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "picked": {"variant": "warning", "icon": "HandGrab"},
        "in_transit": {"variant": "info", "icon": "Truck"},
        "received": {"variant": "success", "icon": "PackageCheck"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table inventory.stock_transfers is '{
    "icon": "ArrowRightLeft",
    "name": "Stock Transfers",
    "description": "Stock moving between sites, and what is on a lorry right now.",
    "collapsible_group": "Internal",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "transfer_number", "badges": ["status", "priority"]},
        "tabs": ["stock_transfer_lines"]
    },
    "views": [
        {"id": "kanban", "name": "Transfer Board", "type": "kanban", "group": "status", "title": "transfer_number", "description": "reason", "date": "expected_on", "badge": "priority"},
        {"id": "gantt", "name": "In Transit", "type": "gantt", "title": "transfer_number", "start_date": "shipped_on", "end_date": "expected_on", "group": "status", "badge": "priority"},
        {"id": "calendar", "name": "Arrivals", "type": "calendar", "title": "transfer_number", "badge": "status", "start_date": "expected_on"},
        {"id": "list", "name": "All Transfers", "type": "list", "title": "transfer_number", "description": "reason", "field_1": "status", "field_2": "total_quantity"}
    ],
    "filter_presets": [
        {"id": "in_transit", "name": "In Transit", "filters": [{"id": "status", "value": "in_transit", "operator": "eq"}]},
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["draft", "picked", "in_transit"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["from_warehouse_id", "to_warehouse_id", "reason", "priority"],
        "sections": [
            {"id": "route", "title": "Route", "fields": ["from_warehouse_id", "to_warehouse_id", "priority", "reason"]},
            {"id": "dates", "title": "Dates", "fields": ["requested_on", "expected_on"]},
            {"id": "state", "title": "State", "fields": ["status", "carrier", "tracking_number", "notes"]},
            {"id": "rollup", "title": "Contents", "fields": {"read": ["line_count", "total_quantity", "in_transit_quantity", "received_quantity", "shipped_on", "received_on", "requested_by"]}}
        ],
        "behavior": {
            "carrier": {"visible": [{"id": "status", "operator": "in", "value": ["in_transit", "received"]}]}
        }
    },
    "query": {
        "sort": [{"id": "requested_on", "desc": true}],
        "join": [
            {"table": "warehouses", "on": "from_warehouse_id", "alias": "origin", "columns": ["code", "name"]},
            {"table": "warehouses", "on": "to_warehouse_id", "alias": "destination", "columns": ["code", "name"]}
        ]
    }
}';

revoke all on table inventory.stock_transfers
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
delete on table inventory.stock_transfers to "x-admin";

grant
select
,
  insert,
update on table inventory.stock_transfers to "warehouse";

grant
select
  on table inventory.stock_transfers to "inventory-planner";

revoke all on sequence inventory.transfer_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence inventory.transfer_number_seq to "x-admin",
"warehouse";

create index idx_inv_transfers_status on inventory.stock_transfers (status);

create index idx_inv_transfers_from on inventory.stock_transfers (from_warehouse_id);

create index idx_inv_transfers_to on inventory.stock_transfers (to_warehouse_id);

alter table inventory.stock_transfers enable row level security;

create policy transfers_select on inventory.stock_transfers for
select
  to authenticated using (true);

create policy transfers_insert on inventory.stock_transfers for insert to authenticated
with
  check (true);

create policy transfers_update on inventory.stock_transfers
for update
  to authenticated using (true)
with
  check (true);

create policy transfers_delete on inventory.stock_transfers for delete to authenticated using (true);

create table inventory.stock_transfer_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  transfer_id uuid not null references inventory.stock_transfers (id) on delete cascade,
  item_id uuid not null references inventory.items (id) on delete restrict,
  lot_id uuid references inventory.lots (id) on delete set null,
  from_location_id uuid references inventory.locations (id) on delete set null,
  to_location_id uuid references inventory.locations (id) on delete set null,
  line_number integer,
  quantity numeric(14, 3) not null,
  shipped_quantity numeric(14, 3) not null default 0,
  received_quantity numeric(14, 3) not null default 0,
  variance_quantity numeric(14, 3) not null default 0,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  constraint transfer_lines_quantity_positive check (quantity > 0)
);

comment on table inventory.stock_transfer_lines is '{
    "icon": "List",
    "name": "Transfer Lines",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["transfer_id", "item_id", "lot_id", "quantity"]},
            {"id": "route", "title": "Bins", "fields": ["from_location_id", "to_location_id", "note"]},
            {"id": "progress", "title": "Progress", "fields": {"read": ["shipped_quantity", "received_quantity", "variance_quantity"]}}
        ]
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "items", "on": "item_id", "columns": ["sku", "name", "tracking"]},
            {"table": "locations", "on": "from_location_id", "alias": "origin_bin", "columns": ["code"]},
            {"table": "locations", "on": "to_location_id", "alias": "destination_bin", "columns": ["code"]}
        ]
    }
}';

comment on column inventory.stock_transfer_lines.quantity is '{"aggregate": "sum"}';

revoke all on table inventory.stock_transfer_lines
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
delete on table inventory.stock_transfer_lines to "x-admin",
"warehouse";

grant
select
  on table inventory.stock_transfer_lines to "inventory-planner";

create index idx_inv_transfer_lines_transfer_id on inventory.stock_transfer_lines (transfer_id);

create index idx_inv_transfer_lines_item_id on inventory.stock_transfer_lines (item_id);

alter table inventory.stock_transfer_lines enable row level security;

create policy transfer_lines_select on inventory.stock_transfer_lines for
select
  to authenticated using (true);

create policy transfer_lines_insert on inventory.stock_transfer_lines for insert to authenticated
with
  check (true);

create policy transfer_lines_update on inventory.stock_transfer_lines
for update
  to authenticated using (true)
with
  check (true);

create policy transfer_lines_delete on inventory.stock_transfer_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Internal stock requests (the one table an ordinary user writes)
----------------------------------------------------------------
create sequence if not exists inventory.request_number_seq;

create table inventory.stock_requests (
  id uuid primary key default extensions.uuid_generate_v4 (),
  request_number varchar(30) not null unique default (
    'REQ-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('inventory.request_number_seq')::text,
      5,
      '0'
    )
  ),
  requester_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  requester_name varchar(200),
  warehouse_id uuid references inventory.warehouses (id) on delete set null,
  status inventory.request_status not null default 'draft',
  priority inventory.priority not null default 'normal',
  needed_by date,
  purpose varchar(300),
  cost_centre varchar(40),
  deliver_to varchar(200),
  line_count integer not null default 0,
  total_quantity numeric(14, 3) not null default 0,
  fulfilled_quantity numeric(14, 3) not null default 0,
  submitted_at timestamptz,
  decided_by uuid references supasheet.users (id) on delete set null,
  decided_at timestamptz,
  rejected_reason varchar(300),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column inventory.stock_requests.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "submitted": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "info", "icon": "CircleCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "fulfilled": {"variant": "success", "icon": "PackageCheck"},
        "cancelled": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table inventory.stock_requests is '{
    "icon": "ClipboardList",
    "name": "Stock Requests",
    "description": "Internal requisitions from the rest of the business.",
    "collapsible_group": "Outbound",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "request_number", "badges": ["status", "priority"]},
        "tabs": ["stock_request_lines"]
    },
    "views": [
        {"id": "kanban", "name": "Request Board", "type": "kanban", "group": "status", "title": "request_number", "description": "purpose", "date": "needed_by", "badge": "priority"},
        {"id": "calendar", "name": "Needed By", "type": "calendar", "title": "request_number", "badge": "priority", "start_date": "needed_by"},
        {"id": "list", "name": "All Requests", "type": "list", "title": "request_number", "description": "purpose", "field_1": "status", "field_2": "needed_by"}
    ],
    "filter_presets": [
        {"id": "to_decide", "name": "To Decide", "filters": [{"id": "status", "value": "submitted", "operator": "eq"}]},
        {"id": "to_pick", "name": "To Pick", "filters": [{"id": "status", "value": "approved", "operator": "eq"}]},
        {"id": "urgent", "name": "Urgent", "filters": [{"id": "priority", "value": "urgent", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["purpose", "needed_by", "priority"],
        "sections": [
            {"id": "request", "title": "Request", "fields": ["purpose", "needed_by", "priority", "warehouse_id"]},
            {"id": "delivery", "title": "Delivery", "fields": ["deliver_to", "cost_centre"]},
            {"id": "state", "title": "State", "fields": ["status", "rejected_reason"]},
            {"id": "trail", "title": "Trail", "fields": {"read": ["requester_name", "line_count", "total_quantity", "fulfilled_quantity", "submitted_at", "decided_by", "decided_at"]}}
        ],
        "behavior": {
            "rejected_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "rejected"}],
                "required": [{"id": "status", "operator": "eq", "value": "rejected"}]
            }
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "users", "on": "requester_id", "alias": "requester", "columns": ["name", "email"]},
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]}
        ]
    }
}';

revoke all on table inventory.stock_requests
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
delete on table inventory.stock_requests to "x-admin";

grant
select
,
  insert,
update on table inventory.stock_requests to "warehouse";

grant
select
  on table inventory.stock_requests to "inventory-planner";

grant
select
,
  insert,
update on table inventory.stock_requests to "user";

revoke all on sequence inventory.request_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence inventory.request_number_seq to "x-admin",
"warehouse",
"user";

create index idx_inv_requests_requester_id on inventory.stock_requests (requester_id);

create index idx_inv_requests_status on inventory.stock_requests (status);

alter table inventory.stock_requests enable row level security;

-- A requester sees their own and nothing else; the warehouse and the
-- manager see the queue.
create policy requests_select on inventory.stock_requests for
select
  to authenticated using (
    pg_has_role(current_user, 'warehouse', 'member')
    or pg_has_role(current_user, 'inventory-planner', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
    or requester_id = (
      select
        auth.uid ()
    )
  );

create policy requests_insert on inventory.stock_requests for insert to authenticated
with
  check (true);

create policy requests_update on inventory.stock_requests
for update
  to authenticated using (
    pg_has_role(current_user, 'warehouse', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
    or requester_id = (
      select
        auth.uid ()
    )
  )
with
  check (true);

create policy requests_delete on inventory.stock_requests for delete to authenticated using (true);

create table inventory.stock_request_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  request_id uuid not null references inventory.stock_requests (id) on delete cascade,
  item_id uuid not null references inventory.items (id) on delete restrict,
  line_number integer,
  requested_quantity numeric(14, 3) not null,
  approved_quantity numeric(14, 3),
  fulfilled_quantity numeric(14, 3) not null default 0,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  constraint request_lines_quantity_positive check (requested_quantity > 0)
);

comment on table inventory.stock_request_lines is '{
    "icon": "List",
    "name": "Request Lines",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["request_id", "item_id", "requested_quantity", "note"]},
            {"id": "decision", "title": "Decision", "fields": ["approved_quantity"]},
            {"id": "progress", "title": "Progress", "fields": {"read": ["fulfilled_quantity"]}}
        ]
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "items", "on": "item_id", "columns": ["sku", "name", "available"]},
            {"table": "stock_requests", "on": "request_id", "columns": ["request_number", "status"]}
        ]
    }
}';

revoke all on table inventory.stock_request_lines
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
delete on table inventory.stock_request_lines to "x-admin",
"warehouse",
"user";

grant
select
  on table inventory.stock_request_lines to "inventory-planner";

create index idx_inv_request_lines_request_id on inventory.stock_request_lines (request_id);

alter table inventory.stock_request_lines enable row level security;

create policy request_lines_select on inventory.stock_request_lines for
select
  to authenticated using (
    pg_has_role(current_user, 'warehouse', 'member')
    or pg_has_role(current_user, 'inventory-planner', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
    or exists (
      select
        1
      from
        inventory.stock_requests r
      where
        r.id = request_id
        and r.requester_id = (
          select
            auth.uid ()
        )
    )
  );

create policy request_lines_insert on inventory.stock_request_lines for insert to authenticated
with
  check (true);

create policy request_lines_update on inventory.stock_request_lines
for update
  to authenticated using (true)
with
  check (true);

create policy request_lines_delete on inventory.stock_request_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Picking
----------------------------------------------------------------
create sequence if not exists inventory.pick_number_seq;

create table inventory.pick_lists (
  id uuid primary key default extensions.uuid_generate_v4 (),
  pick_number varchar(30) not null unique default (
    'PCK-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('inventory.pick_number_seq')::text,
      5,
      '0'
    )
  ),
  warehouse_id uuid not null references inventory.warehouses (id) on delete restrict,
  request_id uuid references inventory.stock_requests (id) on delete set null,
  transfer_id uuid references inventory.stock_transfers (id) on delete set null,
  status inventory.pick_status not null default 'pending',
  priority inventory.priority not null default 'normal',
  assigned_to uuid references supasheet.users (id) on delete set null,
  scheduled_for date not null default current_date,
  started_at timestamptz,
  completed_at timestamptz,
  dispatched_at timestamptz,
  line_count integer not null default 0,
  requested_quantity numeric(14, 3) not null default 0,
  picked_quantity numeric(14, 3) not null default 0,
  short_quantity numeric(14, 3) not null default 0,
  pick_accuracy supasheet.PERCENTAGE,
  duration_minutes integer,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column inventory.pick_lists.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "secondary", "icon": "Clock"},
        "assigned": {"variant": "info", "icon": "UserCheck"},
        "picking": {"variant": "warning", "icon": "HandGrab"},
        "picked": {"variant": "success", "icon": "PackageCheck"},
        "dispatched": {"variant": "success", "icon": "Send"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table inventory.pick_lists is '{
    "icon": "HandGrab",
    "name": "Pick Lists",
    "description": "The work on the floor, in the order the bins are walked.",
    "collapsible_group": "Outbound",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "pick_number", "badges": ["status", "priority"]},
        "tabs": ["pick_lines"]
    },
    "views": [
        {"id": "kanban", "name": "Floor Board", "type": "kanban", "group": "status", "title": "pick_number", "description": "notes", "date": "scheduled_for", "badge": "priority"},
        {"id": "calendar", "name": "Schedule", "type": "calendar", "title": "pick_number", "badge": "status", "start_date": "scheduled_for"},
        {"id": "list", "name": "All Picks", "type": "list", "title": "pick_number", "description": "status", "field_1": "picked_quantity", "field_2": "scheduled_for"}
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["pending", "assigned", "picking"], "operator": "in"}]},
        {"id": "short", "name": "Short Picked", "filters": [{"id": "short_quantity", "value": "0", "operator": "gt"}]},
        {"id": "today", "name": "Today", "filters": [{"id": "scheduled_for", "value": "today", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["warehouse_id", "scheduled_for", "priority"],
        "sections": [
            {"id": "work", "title": "Work", "fields": ["warehouse_id", "scheduled_for", "priority", "assigned_to"]},
            {"id": "source", "title": "Raised from", "fields": ["request_id", "transfer_id"]},
            {"id": "state", "title": "State", "fields": ["status", "notes"]},
            {"id": "rollup", "title": "Result", "fields": {"read": ["line_count", "requested_quantity", "picked_quantity", "short_quantity", "pick_accuracy", "duration_minutes", "started_at", "completed_at", "dispatched_at"]}}
        ]
    },
    "query": {
        "sort": [{"id": "scheduled_for", "desc": false}],
        "join": [
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]},
            {"table": "users", "on": "assigned_to", "alias": "picker", "columns": ["name"]},
            {"table": "stock_requests", "on": "request_id", "columns": ["request_number", "status"]}
        ]
    }
}';

revoke all on table inventory.pick_lists
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
delete on table inventory.pick_lists to "x-admin";

grant
select
,
  insert,
update on table inventory.pick_lists to "warehouse";

grant
select
  on table inventory.pick_lists to "inventory-planner";

revoke all on sequence inventory.pick_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence inventory.pick_number_seq to "x-admin",
"warehouse";

create index idx_inv_picks_warehouse_id on inventory.pick_lists (warehouse_id);

create index idx_inv_picks_status on inventory.pick_lists (status);

create index idx_inv_picks_assigned_to on inventory.pick_lists (assigned_to);

alter table inventory.pick_lists enable row level security;

create policy picks_select on inventory.pick_lists for
select
  to authenticated using (true);

create policy picks_insert on inventory.pick_lists for insert to authenticated
with
  check (true);

create policy picks_update on inventory.pick_lists
for update
  to authenticated using (true)
with
  check (true);

create policy picks_delete on inventory.pick_lists for delete to authenticated using (true);

create table inventory.pick_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  pick_list_id uuid not null references inventory.pick_lists (id) on delete cascade,
  item_id uuid not null references inventory.items (id) on delete restrict,
  location_id uuid references inventory.locations (id) on delete set null,
  lot_id uuid references inventory.lots (id) on delete set null,
  serial_id uuid references inventory.serials (id) on delete set null,
  request_line_id uuid references inventory.stock_request_lines (id) on delete set null,
  line_number integer,
  pick_sequence integer,
  requested_quantity numeric(14, 3) not null,
  picked_quantity numeric(14, 3) not null default 0,
  short_quantity numeric(14, 3) not null default 0,
  is_picked boolean not null default false,
  short_reason varchar(200),
  note varchar(300),
  created_at timestamptz default current_timestamp,
  constraint pick_lines_quantity_positive check (requested_quantity > 0),
  constraint pick_lines_picked_non_negative check (picked_quantity >= 0)
);

comment on table inventory.pick_lines is '{
    "icon": "List",
    "name": "Pick Lines",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["pick_list_id", "item_id", "requested_quantity"]},
            {"id": "where", "title": "Where from", "fields": ["location_id", "lot_id", "serial_id"]},
            {"id": "result", "title": "Result", "fields": ["picked_quantity", "short_reason", "note"]},
            {"id": "derived", "title": "Derived", "fields": {"read": ["pick_sequence", "short_quantity", "is_picked"]}}
        ],
        "behavior": {
            "short_reason": {"required": [{"id": "short_quantity", "operator": "gt", "value": "0"}]}
        }
    },
    "query": {
        "sort": [{"id": "pick_sequence", "desc": false}],
        "join": [
            {"table": "items", "on": "item_id", "columns": ["sku", "name", "tracking"]},
            {"table": "locations", "on": "location_id", "columns": ["code", "pick_sequence"]},
            {"table": "lots", "on": "lot_id", "columns": ["lot_code", "expires_on"]}
        ]
    }
}';

comment on column inventory.pick_lines.picked_quantity is '{"name": "Picked", "aggregate": "sum"}';

revoke all on table inventory.pick_lines
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
delete on table inventory.pick_lines to "x-admin",
"warehouse";

grant
select
  on table inventory.pick_lines to "inventory-planner";

create index idx_inv_pick_lines_pick_id on inventory.pick_lines (pick_list_id);

create index idx_inv_pick_lines_item_id on inventory.pick_lines (item_id);

alter table inventory.pick_lines enable row level security;

create policy pick_lines_select on inventory.pick_lines for
select
  to authenticated using (true);

create policy pick_lines_insert on inventory.pick_lines for insert to authenticated
with
  check (true);

create policy pick_lines_update on inventory.pick_lines
for update
  to authenticated using (true)
with
  check (true);

create policy pick_lines_delete on inventory.pick_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Cycle counting
--
-- A count does not change stock. Posting one does — by writing the
-- variance to the ledger like any other movement, so a count that
-- found four missing units is as auditable as a pick that took them.
----------------------------------------------------------------
create sequence if not exists inventory.count_number_seq;

create table inventory.cycle_counts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  count_number varchar(30) not null unique default (
    'CNT-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('inventory.count_number_seq')::text,
      5,
      '0'
    )
  ),
  warehouse_id uuid not null references inventory.warehouses (id) on delete restrict,
  zone_id uuid references inventory.zones (id) on delete set null,
  count_type inventory.count_type not null default 'cycle',
  status inventory.count_status not null default 'planned',
  scheduled_for date not null default current_date,
  started_at timestamptz,
  counted_by uuid references supasheet.users (id) on delete set null,
  posted_at timestamptz,
  posted_by uuid references supasheet.users (id) on delete set null,
  line_count integer not null default 0,
  counted_lines integer not null default 0,
  variance_lines integer not null default 0,
  variance_units numeric(14, 3) not null default 0,
  variance_value numeric(16, 2) not null default 0,
  accuracy_rate supasheet.PERCENTAGE,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column inventory.cycle_counts.status is '{
    "progress": true,
    "values": {
        "planned": {"variant": "secondary", "icon": "CalendarClock"},
        "counting": {"variant": "warning", "icon": "ClipboardPen"},
        "review": {"variant": "info", "icon": "ScanSearch"},
        "posted": {"variant": "success", "icon": "CircleCheck"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table inventory.cycle_counts is '{
    "icon": "ClipboardCheck",
    "name": "Cycle Counts",
    "description": "Scheduled counts, what they found, and how accurate the records turned out to be.",
    "collapsible_group": "Internal",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "count_number", "badges": ["status", "count_type", "accuracy_rate"]},
        "tabs": ["cycle_count_lines"]
    },
    "views": [
        {"id": "kanban", "name": "Count Board", "type": "kanban", "group": "status", "title": "count_number", "description": "count_type", "date": "scheduled_for", "badge": "variance_lines"},
        {"id": "calendar", "name": "Count Schedule", "type": "calendar", "title": "count_number", "badge": "status", "start_date": "scheduled_for"},
        {"id": "list", "name": "All Counts", "type": "list", "title": "count_number", "description": "count_type", "field_1": "accuracy_rate", "field_2": "variance_units"}
    ],
    "filter_presets": [
        {"id": "due", "name": "Due", "filters": [{"id": "status", "value": ["planned", "counting"], "operator": "in"}]},
        {"id": "review", "name": "To Review", "filters": [{"id": "status", "value": "review", "operator": "eq"}]},
        {"id": "variances", "name": "With Variances", "filters": [{"id": "variance_lines", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["warehouse_id", "zone_id", "count_type", "scheduled_for"],
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["warehouse_id", "zone_id", "count_type", "scheduled_for"]},
            {"id": "state", "title": "State", "fields": ["status", "counted_by", "notes"]},
            {"id": "result", "title": "Result", "fields": {"read": ["line_count", "counted_lines", "variance_lines", "variance_units", "variance_value", "accuracy_rate", "started_at", "posted_at", "posted_by"]}}
        ],
        "lookups": {
            "zone_id": {"filter": [{"source_column": "warehouse_id", "target_column": "warehouse_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "scheduled_for", "desc": true}],
        "join": [
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]},
            {"table": "zones", "on": "zone_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column inventory.cycle_counts.variance_value is '{"name": "Variance Value", "aggregate": "sum"}';

revoke all on table inventory.cycle_counts
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
delete on table inventory.cycle_counts to "x-admin";

grant
select
,
  insert,
update on table inventory.cycle_counts to "warehouse";

grant
select
  (
    id,
    count_number,
    warehouse_id,
    zone_id,
    count_type,
    status,
    scheduled_for,
    line_count,
    counted_lines,
    variance_lines,
    variance_units,
    accuracy_rate,
    created_at
  ) on table inventory.cycle_counts to "inventory-planner";

revoke all on sequence inventory.count_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence inventory.count_number_seq to "x-admin",
"warehouse";

create index idx_inv_counts_warehouse_id on inventory.cycle_counts (warehouse_id);

create index idx_inv_counts_status on inventory.cycle_counts (status);

alter table inventory.cycle_counts enable row level security;

create policy counts_select on inventory.cycle_counts for
select
  to authenticated using (true);

create policy counts_insert on inventory.cycle_counts for insert to authenticated
with
  check (true);

create policy counts_update on inventory.cycle_counts
for update
  to authenticated using (true)
with
  check (true);

create policy counts_delete on inventory.cycle_counts for delete to authenticated using (true);

create table inventory.cycle_count_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  count_id uuid not null references inventory.cycle_counts (id) on delete cascade,
  item_id uuid not null references inventory.items (id) on delete restrict,
  location_id uuid not null references inventory.locations (id) on delete restrict,
  lot_id uuid references inventory.lots (id) on delete set null,
  line_number integer,
  system_quantity numeric(14, 3) not null default 0,
  counted_quantity numeric(14, 3),
  variance_quantity numeric(14, 3) not null default 0,
  variance_value numeric(16, 2) not null default 0,
  is_counted boolean not null default false,
  is_variance boolean not null default false,
  recount_requested boolean not null default false,
  note varchar(300),
  created_at timestamptz default current_timestamp
);

comment on table inventory.cycle_count_lines is '{
    "icon": "List",
    "name": "Count Lines",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": {"read": ["count_id", "item_id", "location_id", "lot_id", "system_quantity"]}},
            {"id": "count", "title": "Count", "fields": ["counted_quantity", "recount_requested", "note"]},
            {"id": "variance", "title": "Variance", "fields": {"read": ["variance_quantity", "variance_value", "is_counted", "is_variance"]}}
        ]
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "items", "on": "item_id", "columns": ["sku", "name"]},
            {"table": "locations", "on": "location_id", "columns": ["code"]},
            {"table": "lots", "on": "lot_id", "columns": ["lot_code"]}
        ]
    }
}';

comment on column inventory.cycle_count_lines.variance_quantity is '{"name": "Variance", "aggregate": "sum"}';

revoke all on table inventory.cycle_count_lines
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
delete on table inventory.cycle_count_lines to "x-admin",
"warehouse";

grant
select
  (
    id,
    count_id,
    item_id,
    location_id,
    lot_id,
    line_number,
    system_quantity,
    counted_quantity,
    variance_quantity,
    is_counted,
    is_variance,
    recount_requested,
    note,
    created_at
  ) on table inventory.cycle_count_lines to "inventory-planner";

create index idx_inv_count_lines_count_id on inventory.cycle_count_lines (count_id);

create index idx_inv_count_lines_item_id on inventory.cycle_count_lines (item_id);

alter table inventory.cycle_count_lines enable row level security;

create policy count_lines_select on inventory.cycle_count_lines for
select
  to authenticated using (true);

create policy count_lines_insert on inventory.cycle_count_lines for insert to authenticated
with
  check (true);

create policy count_lines_update on inventory.cycle_count_lines
for update
  to authenticated using (true)
with
  check (true);

create policy count_lines_delete on inventory.cycle_count_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Adjustments
--
-- The only sanctioned way to change stock without a physical event
-- behind it, which is why it needs a reason code, an approver and a
-- value threshold.
----------------------------------------------------------------
create sequence if not exists inventory.adjustment_number_seq;

create table inventory.stock_adjustments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  adjustment_number varchar(30) not null unique default (
    'ADJ-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('inventory.adjustment_number_seq')::text,
      5,
      '0'
    )
  ),
  warehouse_id uuid not null references inventory.warehouses (id) on delete restrict,
  status inventory.adjustment_status not null default 'draft',
  reason inventory.adjustment_reason not null default 'correction',
  adjusted_on date not null default current_date,
  reference varchar(80),
  explanation varchar(500),
  line_count integer not null default 0,
  total_units numeric(14, 3) not null default 0,
  total_value numeric(16, 2) not null default 0,
  requires_approval boolean not null default false,
  raised_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  approved_by uuid references supasheet.users (id) on delete set null,
  approved_at timestamptz,
  posted_at timestamptz,
  rejected_reason varchar(300),
  evidence supasheet.file,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column inventory.stock_adjustments.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "pending_approval": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "info", "icon": "CircleCheck"},
        "posted": {"variant": "success", "icon": "PackageCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on column inventory.stock_adjustments.reason is '{
    "progress": false,
    "values": {
        "damage": {"variant": "destructive", "icon": "PackageX"},
        "expiry": {"variant": "warning", "icon": "CalendarX"},
        "theft": {"variant": "destructive", "icon": "ShieldAlert"},
        "found": {"variant": "success", "icon": "PackagePlus"},
        "correction": {"variant": "info", "icon": "Pencil"},
        "sample": {"variant": "secondary", "icon": "FlaskConical"},
        "scrap": {"variant": "destructive", "icon": "Trash2"},
        "rework": {"variant": "warning", "icon": "Hammer"}
    }
}';

comment on table inventory.stock_adjustments is '{
    "icon": "SlidersHorizontal",
    "name": "Adjustments",
    "description": "Stock written on or off, with a reason and somebody''s name against it.",
    "collapsible_group": "Internal",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "adjustment_number", "badges": ["status", "reason", "total_value"]},
        "tabs": ["stock_adjustment_lines"]
    },
    "views": [
        {"id": "kanban", "name": "Approval Board", "type": "kanban", "group": "status", "title": "adjustment_number", "description": "explanation", "date": "adjusted_on", "badge": "reason"},
        {"id": "list", "name": "All Adjustments", "type": "list", "title": "adjustment_number", "description": "reason", "field_1": "total_units", "field_2": "adjusted_on"},
        {"id": "calendar", "name": "By Day", "type": "calendar", "title": "adjustment_number", "badge": "reason", "start_date": "adjusted_on"}
    ],
    "filter_presets": [
        {"id": "to_approve", "name": "To Approve", "filters": [{"id": "status", "value": "pending_approval", "operator": "eq"}]},
        {"id": "write_offs", "name": "Write-offs", "filters": [{"id": "reason", "value": ["damage", "expiry", "theft", "scrap"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["warehouse_id", "reason", "explanation"],
        "sections": [
            {"id": "adjustment", "title": "Adjustment", "fields": ["warehouse_id", "reason", "adjusted_on", "reference"]},
            {"id": "justification", "title": "Justification", "fields": ["explanation", "evidence"]},
            {"id": "state", "title": "State", "fields": ["status", "rejected_reason"]},
            {"id": "rollup", "title": "Impact", "fields": {"read": ["line_count", "total_units", "total_value", "requires_approval", "raised_by", "approved_by", "approved_at", "posted_at"]}}
        ],
        "behavior": {
            "rejected_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "rejected"}],
                "required": [{"id": "status", "operator": "eq", "value": "rejected"}]
            }
        }
    },
    "query": {
        "sort": [{"id": "adjusted_on", "desc": true}],
        "join": [
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]},
            {"table": "users", "on": "raised_by", "alias": "raiser", "columns": ["name"]}
        ]
    }
}';

comment on column inventory.stock_adjustments.total_value is '{"name": "Value", "aggregate": "sum"}';

comment on column inventory.stock_adjustments.evidence is '{"accept": ".pdf,.png,.jpg", "max_files": 4, "max_size": 5242880}';

revoke all on table inventory.stock_adjustments
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
delete on table inventory.stock_adjustments to "x-admin";

grant
select
,
  insert,
update on table inventory.stock_adjustments to "warehouse";

grant
select
  (
    id,
    adjustment_number,
    warehouse_id,
    status,
    reason,
    adjusted_on,
    reference,
    explanation,
    line_count,
    total_units,
    raised_by,
    approved_by,
    posted_at,
    created_at
  ) on table inventory.stock_adjustments to "inventory-planner";

revoke all on sequence inventory.adjustment_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence inventory.adjustment_number_seq to "x-admin",
"warehouse";

create index idx_inv_adjustments_warehouse_id on inventory.stock_adjustments (warehouse_id);

create index idx_inv_adjustments_status on inventory.stock_adjustments (status);

alter table inventory.stock_adjustments enable row level security;

create policy adjustments_select on inventory.stock_adjustments for
select
  to authenticated using (true);

create policy adjustments_insert on inventory.stock_adjustments for insert to authenticated
with
  check (true);

create policy adjustments_update on inventory.stock_adjustments
for update
  to authenticated using (true)
with
  check (true);

create policy adjustments_delete on inventory.stock_adjustments for delete to authenticated using (true);

create table inventory.stock_adjustment_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  adjustment_id uuid not null references inventory.stock_adjustments (id) on delete cascade,
  item_id uuid not null references inventory.items (id) on delete restrict,
  location_id uuid not null references inventory.locations (id) on delete restrict,
  lot_id uuid references inventory.lots (id) on delete set null,
  serial_id uuid references inventory.serials (id) on delete set null,
  line_number integer,
  system_quantity numeric(14, 3) not null default 0,
  adjustment_quantity numeric(14, 3) not null,
  unit_cost numeric(14, 4) not null default 0,
  line_value numeric(16, 2) not null default 0,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  constraint adjustment_lines_not_zero check (adjustment_quantity <> 0)
);

comment on table inventory.stock_adjustment_lines is '{
    "icon": "List",
    "name": "Adjustment Lines",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["adjustment_id", "item_id", "location_id", "lot_id"]},
            {"id": "quantity", "title": "Quantity", "fields": ["adjustment_quantity", "note"]},
            {"id": "derived", "title": "Derived", "fields": {"read": ["system_quantity", "unit_cost", "line_value"]}}
        ],
        "metadata": {
            "adjustment_quantity": {"description": "Positive writes stock on, negative writes it off. The bin cannot be taken below zero."}
        }
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "items", "on": "item_id", "columns": ["sku", "name", "tracking"]},
            {"table": "locations", "on": "location_id", "columns": ["code"]},
            {"table": "lots", "on": "lot_id", "columns": ["lot_code"]}
        ]
    }
}';

comment on column inventory.stock_adjustment_lines.adjustment_quantity is '{"name": "Adjustment", "aggregate": "sum"}';

revoke all on table inventory.stock_adjustment_lines
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
delete on table inventory.stock_adjustment_lines to "x-admin",
"warehouse";

grant
select
  (
    id,
    adjustment_id,
    item_id,
    location_id,
    lot_id,
    serial_id,
    line_number,
    system_quantity,
    adjustment_quantity,
    note,
    created_at
  ) on table inventory.stock_adjustment_lines to "inventory-planner";

create index idx_inv_adj_lines_adjustment_id on inventory.stock_adjustment_lines (adjustment_id);

create index idx_inv_adj_lines_item_id on inventory.stock_adjustment_lines (item_id);

alter table inventory.stock_adjustment_lines enable row level security;

create policy adj_lines_select on inventory.stock_adjustment_lines for
select
  to authenticated using (true);

create policy adj_lines_insert on inventory.stock_adjustment_lines for insert to authenticated
with
  check (true);

create policy adj_lines_update on inventory.stock_adjustment_lines
for update
  to authenticated using (true)
with
  check (true);

create policy adj_lines_delete on inventory.stock_adjustment_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Inventory settings (singleton)
----------------------------------------------------------------
create table inventory.inventory_settings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  company_name varchar(200) not null default 'Supasheet',
  logo supasheet.file,
  base_currency varchar(3) not null default 'USD',
  default_warehouse_id uuid references inventory.warehouses (id) on delete set null,
  default_valuation_method inventory.valuation_method not null default 'average',
  allow_negative_stock boolean not null default false,
  enforce_fefo boolean not null default true,
  adjustment_approval_threshold numeric(14, 2) not null default 500,
  expiry_warning_days integer not null default 45,
  count_frequency_a_days integer not null default 30,
  count_frequency_b_days integer not null default 90,
  count_frequency_c_days integer not null default 180,
  reorder_check_enabled boolean not null default true,
  timezone varchar(64) not null default 'UTC',
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint settings_thresholds_positive check (
    adjustment_approval_threshold >= 0
    and expiry_warning_days > 0
  )
);

comment on table inventory.inventory_settings is '{
    "icon": "Settings",
    "name": "Inventory Settings",
    "description": "The policy every stock routine reads before it does anything.",
    "collapsible_group": "Configuration",
    "display": "block",
    "singleton": true,
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["company_name", "logo", "base_currency", "timezone"]},
            {"id": "defaults", "title": "Defaults", "fields": ["default_warehouse_id", "default_valuation_method"]},
            {"id": "policy", "title": "Stock policy", "fields": ["allow_negative_stock", "enforce_fefo", "adjustment_approval_threshold", "expiry_warning_days", "reorder_check_enabled"]},
            {"id": "counting", "title": "Count frequency", "fields": ["count_frequency_a_days", "count_frequency_b_days", "count_frequency_c_days"]}
        ],
        "metadata": {
            "enforce_fefo": {"description": "First expired, first out. With this on, a pick suggested against a later-expiring lot when an earlier one is available is flagged."}
        }
    }
}';

comment on column inventory.inventory_settings.logo is '{"accept": "image/*", "max_size": 2097152}';

revoke all on table inventory.inventory_settings
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update on table inventory.inventory_settings to "x-admin";

grant
select
  on table inventory.inventory_settings to "warehouse",
  "inventory-planner";

alter table inventory.inventory_settings enable row level security;

create policy settings_select on inventory.inventory_settings for
select
  to authenticated using (true);

create policy settings_insert on inventory.inventory_settings for insert to authenticated
with
  check (true);

create policy settings_update on inventory.inventory_settings
for update
  to authenticated using (true)
with
  check (true);

----------------------------------------------------------------
-- Shared helpers
----------------------------------------------------------------
create or replace function inventory.set_updated_at () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  new.updated_at := current_timestamp;
  return new;
end;
$$;

create or replace function inventory.settings () returns inventory.inventory_settings language sql stable security definer
set
  search_path = '' as $$
  select * from inventory.inventory_settings limit 1;
$$;

revoke all on function inventory.settings ()
from
  public;

grant
execute on function inventory.settings () to "x-admin",
"warehouse",
"inventory-planner";

-- What is in this bin, of this item, from this lot, right now.
create or replace function inventory.on_hand_at (
  p_item_id uuid,
  p_location_id uuid,
  p_lot_id uuid default null
) returns numeric language sql stable security definer
set
  search_path = '' as $$
  select coalesce(
    (
      select sl.on_hand
      from inventory.stock_levels sl
      where sl.item_id = p_item_id
        and sl.location_id = p_location_id
        and coalesce(sl.lot_id, '00000000-0000-0000-0000-000000000000'::uuid)
          = coalesce(p_lot_id, '00000000-0000-0000-0000-000000000000'::uuid)
    ),
    0
  );
$$;

grant
execute on function inventory.on_hand_at (uuid, uuid, uuid) to "x-admin",
"warehouse",
"inventory-planner";

create or replace function inventory.recalc_lot_position (p_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  update inventory.lots l
  set on_hand = s.qty,
    days_to_expiry = case
      when l.expires_on is null then null
      else (l.expires_on - current_date)
    end,
    status = case
      when l.status in ('recalled', 'quarantine') then l.status
      when l.expires_on is not null and l.expires_on < current_date then 'expired'
      when s.qty <= 0 and l.received_quantity > 0 then 'consumed'
      else 'available'
    end,
    updated_at = current_timestamp
  from (select distinct x.id from unnest(p_ids) as x (id) where x.id is not null) t
    cross join lateral (
      select coalesce(sum(sl.on_hand), 0) as qty
      from inventory.stock_levels sl
      where sl.lot_id = t.id
    ) s
  where l.id = t.id
    and (l.on_hand, l.days_to_expiry) is distinct from (
      s.qty,
      case when l.expires_on is null then null else (l.expires_on - current_date) end
    );
end;
$$;

create or replace function inventory.recalc_item_position (p_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  update inventory.items i
  set on_hand = s.on_hand,
    allocated = s.allocated,
    available = s.on_hand - s.allocated,
    stock_value = s.value,
    location_count = s.bins,
    last_movement_on = s.last_moved,
    is_below_reorder_point = (
      i.status = 'active'
      and i.reorder_point > 0
      and (s.on_hand - s.allocated) <= i.reorder_point
    ),
    updated_at = current_timestamp
  from (select distinct x.id from unnest(p_ids) as x (id) where x.id is not null) t
    cross join lateral (
      select coalesce(sum(sl.on_hand), 0) as on_hand,
        coalesce(sum(sl.allocated), 0) as allocated,
        coalesce(sum(sl.stock_value), 0) as value,
        count(*) filter (where sl.on_hand <> 0) as bins,
        (
          select max(m.occurred_at)::date
          from inventory.stock_movements m
          where m.item_id = t.id
        ) as last_moved
      from inventory.stock_levels sl
      where sl.item_id = t.id
    ) s
  where i.id = t.id
    and (i.on_hand, i.allocated, i.stock_value, i.location_count, i.last_movement_on)
      is distinct from (s.on_hand, s.allocated, s.value, s.bins::integer, s.last_moved);
end;
$$;

create or replace function inventory.recalc_location_position (p_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  update inventory.locations l
  set distinct_items = s.items,
    total_quantity = s.qty,
    updated_at = current_timestamp
  from (select distinct x.id from unnest(p_ids) as x (id) where x.id is not null) t
    cross join lateral (
      select count(distinct sl.item_id) filter (where sl.on_hand <> 0) as items,
        coalesce(sum(sl.on_hand), 0) as qty
      from inventory.stock_levels sl
      where sl.location_id = t.id
    ) s
  where l.id = t.id
    and (l.distinct_items, l.total_quantity) is distinct from (s.items::integer, s.qty);
end;
$$;

create or replace function inventory.recalc_warehouse_position (p_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  update inventory.warehouses w
  set zone_count = s.zones,
    location_count = s.bins,
    distinct_items = s.items,
    stock_value = s.value,
    updated_at = current_timestamp
  from (select distinct x.id from unnest(p_ids) as x (id) where x.id is not null) t
    cross join lateral (
      select (select count(*) from inventory.zones z where z.warehouse_id = t.id) as zones,
        (select count(*) from inventory.locations lo where lo.warehouse_id = t.id) as bins,
        (
          select count(distinct sl.item_id)
          from inventory.stock_levels sl
          where sl.warehouse_id = t.id
            and sl.on_hand <> 0
        ) as items,
        (
          select coalesce(sum(sl.stock_value), 0)
          from inventory.stock_levels sl
          where sl.warehouse_id = t.id
        ) as value
    ) s
  where w.id = t.id
    and (w.zone_count, w.location_count, w.distinct_items, w.stock_value)
      is distinct from (s.zones::integer, s.bins::integer, s.items::integer, s.value);
end;
$$;

revoke all on function inventory.recalc_lot_position (uuid[])
from
  public;

revoke all on function inventory.recalc_item_position (uuid[])
from
  public;

revoke all on function inventory.recalc_location_position (uuid[])
from
  public;

revoke all on function inventory.recalc_warehouse_position (uuid[])
from
  public;

----------------------------------------------------------------
-- The ledger guard
--
-- Everything that makes this a stock system rather than a table of
-- numbers happens in this function.
----------------------------------------------------------------
create or replace function inventory.movements_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_item inventory.items;
  v_location inventory.locations;
  v_allow_negative boolean;
  v_current numeric(14, 3);
  v_allocated numeric(14, 3);
  v_lot_item uuid;
  v_serial_item uuid;
begin
  select * into v_item from inventory.items where id = new.item_id;
  select * into v_location from inventory.locations where id = new.location_id;

  if v_location.is_active is false then
    raise exception 'Bin % is not active and cannot take stock.', v_location.code;
  end if;

  new.uom_id := coalesce(new.uom_id, v_item.uom_id);
  new.quantity := round(new.quantity, 3);
  new.total_cost := round(new.quantity * coalesce(new.unit_cost, 0), 4);

  -- TRACEABILITY. An item declared lot-tracked has no meaning without
  -- a lot on every movement; the same for serials, which additionally
  -- can only ever move one at a time.
  if v_item.tracking = 'lot' and new.lot_id is null then
    raise exception '% is lot-tracked — a movement needs a lot.', v_item.sku
      using hint = 'Receive against a lot, or change the item to untracked.';
  end if;

  if v_item.tracking = 'serial' then
    if new.serial_id is null then
      raise exception '% is serial-tracked — a movement needs a serial number.', v_item.sku;
    end if;

    if abs(new.quantity) <> 1 then
      raise exception 'A serialised movement is one unit; % was requested for %.', new.quantity, v_item.sku;
    end if;
  end if;

  if v_item.tracking = 'none' and new.lot_id is not null then
    raise exception '% is not lot-tracked, so a lot cannot be recorded against it.', v_item.sku;
  end if;

  if new.lot_id is not null then
    select item_id into v_lot_item from inventory.lots where id = new.lot_id;

    if v_lot_item is distinct from new.item_id then
      raise exception 'That lot belongs to a different item.';
    end if;
  end if;

  if new.serial_id is not null then
    select item_id into v_serial_item from inventory.serials where id = new.serial_id;

    if v_serial_item is distinct from new.item_id then
      raise exception 'That serial number belongs to a different item.';
    end if;
  end if;

  v_current := inventory.on_hand_at (new.item_id, new.location_id, new.lot_id);

  -- NO NEGATIVE STOCK. Refused at the ledger rather than at the form,
  -- so it holds for the API, the SQL editor and every future caller
  -- that has not been written yet.
  if new.quantity < 0 and v_current + new.quantity < 0 then
    v_allow_negative := coalesce(v_location.warehouse_id is not null
      and (select allows_negative_stock from inventory.warehouses where id = v_location.warehouse_id), false)
      or coalesce((inventory.settings ()).allow_negative_stock, false);

    if not v_allow_negative then
      raise exception 'Bin % holds % of %, so % cannot be taken out of it.',
        v_location.code, v_current, v_item.sku, abs(new.quantity)
        using hint = 'Count the bin, or pick from somewhere that has the stock.';
    end if;
  end if;

  -- RESERVED IS NOT AVAILABLE, enforced rather than displayed. A
  -- deliberate withdrawal may not take units another pick has already
  -- promised — without this, on_hand can fall below allocated and the
  -- reservation is stranded against stock that has left the building.
  --
  -- Corrections are exempt: an adjustment, a count or a scrap records
  -- units that physically are not there, so any reservation against
  -- them was void already. movements_apply () clamps the allocation
  -- down to match instead.
  if new.quantity < 0 and new.movement_type in ('pick', 'ship', 'transfer_out') then
    select coalesce(allocated, 0)
    into v_allocated
    from inventory.stock_levels
    where item_id = new.item_id
      and location_id = new.location_id
      and coalesce(lot_id, '00000000-0000-0000-0000-000000000000'::uuid)
        = coalesce(new.lot_id, '00000000-0000-0000-0000-000000000000'::uuid);

    if v_current + new.quantity < coalesce(v_allocated, 0) then
      raise exception 'Bin % holds % of %, of which % is reserved — % cannot be taken.',
        v_location.code, v_current, v_item.sku, coalesce(v_allocated, 0), abs(new.quantity)
        using hint = 'Release the reservation on the other pick first.';
    end if;
  end if;

  new.balance_after := v_current + new.quantity;

  return new;
end;
$$;

create trigger trg_movements_guard
before insert on inventory.stock_movements for each row
execute function inventory.movements_guard ();

-- Append only, said twice. The grants stop the roles; this stops
-- everything else, including a definer function written later that
-- forgets.
create or replace function inventory.movements_immutable () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  raise exception 'The stock ledger is append only. Correct % with a new movement.', old.movement_number
    using hint = 'Raise an adjustment — that is what they are for.';
end;
$$;

create trigger trg_movements_no_update
before update on inventory.stock_movements for each row
execute function inventory.movements_immutable ();

create trigger trg_movements_no_delete
before delete on inventory.stock_movements for each row
execute function inventory.movements_immutable ();

----------------------------------------------------------------
-- Applying a movement
--
-- One ledger row in, one bin balance changed, and every rollup that
-- depends on it brought back into line.
----------------------------------------------------------------
create or replace function inventory.movements_apply () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_warehouse_id uuid;
  v_cost numeric(14, 4);
  v_rows integer;
begin
  select warehouse_id into v_warehouse_id from inventory.locations where id = new.location_id;

  v_cost := case
    when new.unit_cost > 0 then new.unit_cost
    else coalesce((select average_cost from inventory.items where id = new.item_id), 0)
  end;

  -- A correction removes units somebody had reserved. The units are
  -- going, so the reservation goes with them — and it has to go FIRST,
  -- because the allocated <= on_hand check fires on the balance update
  -- itself and would refuse the correction before any tidying up
  -- afterwards could run.
  update inventory.stock_levels sl
  set allocated = least(sl.allocated, greatest(sl.on_hand + new.quantity, 0)),
    available = sl.on_hand - least(sl.allocated, greatest(sl.on_hand + new.quantity, 0))
  where sl.item_id = new.item_id
    and sl.location_id = new.location_id
    and coalesce(sl.lot_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(new.lot_id, '00000000-0000-0000-0000-000000000000'::uuid)
    and sl.allocated > greatest(sl.on_hand + new.quantity, 0);

  -- UPDATE first, INSERT only if there was nothing to update.
  --
  -- The obvious INSERT ... ON CONFLICT DO UPDATE does not work here:
  -- Postgres evaluates a table''s CHECK constraints against the tuple
  -- being proposed BEFORE it looks for a conflict, so the outbound
  -- half of every transfer — a row carrying on_hand = -60 that was
  -- always going to be merged into an existing balance — is rejected
  -- by the allocated <= on_hand check before the merge can happen.
  --
  -- The insert branch only ever runs with a positive quantity, because
  -- taking stock out of a bin with no balance row is refused by the
  -- guard above.
  update inventory.stock_levels sl
  set on_hand = sl.on_hand + new.quantity,
    available = sl.on_hand + new.quantity - sl.allocated,
    unit_cost = case when new.unit_cost > 0 then new.unit_cost else sl.unit_cost end,
    stock_value = round(
      (sl.on_hand + new.quantity)
        * case when new.unit_cost > 0 then new.unit_cost else sl.unit_cost end,
      2
    ),
    last_movement_at = new.occurred_at,
    updated_at = current_timestamp
  where sl.item_id = new.item_id
    and sl.location_id = new.location_id
    and coalesce(sl.lot_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(new.lot_id, '00000000-0000-0000-0000-000000000000'::uuid);

  -- FOUND refers to the statement immediately above, so nothing may be
  -- run between the balance update and this test.
  get diagnostics v_rows = row_count;

  if v_rows = 0 then
    insert into inventory.stock_levels (
      item_id, location_id, lot_id, warehouse_id, on_hand, allocated, available,
      unit_cost, stock_value, last_movement_at
    )
    values (
      new.item_id,
      new.location_id,
      new.lot_id,
      v_warehouse_id,
      new.quantity,
      0,
      new.quantity,
      v_cost,
      round(new.quantity * v_cost, 2),
      new.occurred_at
    );
  end if;

  -- A serial is in exactly one place. Moving it moves the pointer.
  if new.serial_id is not null then
    update inventory.serials
    set location_id = case when new.quantity > 0 then new.location_id else null end,
      status = case
        when new.quantity > 0 then 'in_stock'::inventory.serial_status
        when new.movement_type = 'scrap' then 'scrapped'::inventory.serial_status
        else 'shipped'::inventory.serial_status
      end,
      shipped_on = case when new.quantity < 0 then new.occurred_at::date else null end,
      updated_at = current_timestamp
    where id = new.serial_id;
  end if;

  -- A receipt is the only movement that establishes what a unit cost,
  -- so it is the only one that moves the average.
  if new.quantity > 0 and new.unit_cost > 0 and new.movement_type in ('receipt', 'return_in') then
    update inventory.items i
    set last_cost = new.unit_cost,
      average_cost = case
        when i.on_hand + new.quantity <= 0 then new.unit_cost
        else round(
          ((i.on_hand * i.average_cost) + (new.quantity * new.unit_cost)) / (i.on_hand + new.quantity),
          4
        )
      end
    where i.id = new.item_id;
  end if;

  perform inventory.recalc_lot_position (array[new.lot_id]);
  perform inventory.recalc_item_position (array[new.item_id]);
  perform inventory.recalc_location_position (array[new.location_id]);
  perform inventory.recalc_warehouse_position (array[v_warehouse_id]);

  return new;
end;
$$;

create trigger trg_movements_apply
after insert on inventory.stock_movements for each row
execute function inventory.movements_apply ();

----------------------------------------------------------------
-- The single door into the ledger
--
-- Every document flow below goes through these two functions rather
-- than inserting movements of its own. One place to get the argument
-- order right, one place that knows a transfer is two rows.
----------------------------------------------------------------
create or replace function inventory.post_movement (
  p_item_id uuid,
  p_location_id uuid,
  p_movement_type inventory.movement_type,
  p_quantity numeric,
  p_lot_id uuid default null,
  p_serial_id uuid default null,
  p_unit_cost numeric default 0,
  p_reference_type varchar default null,
  p_reference_id uuid default null,
  p_reference_number varchar default null,
  p_occurred_at timestamptz default null,
  p_note varchar default null
) returns uuid language plpgsql security definer
set
  search_path = '' as $$
declare
  v_id uuid;
begin
  insert into inventory.stock_movements (
    item_id, location_id, lot_id, serial_id, movement_type, quantity,
    unit_cost, reference_type, reference_id, reference_number, occurred_at, note
  )
  values (
    p_item_id,
    p_location_id,
    p_lot_id,
    p_serial_id,
    p_movement_type,
    p_quantity,
    coalesce(p_unit_cost, 0),
    p_reference_type,
    p_reference_id,
    p_reference_number,
    coalesce(p_occurred_at, current_timestamp),
    p_note
  )
  returning id into v_id;

  return v_id;
end;
$$;

-- Two rows that sum to zero, pointed at each other. There is no
-- window in which the stock has left one bin and not arrived in the
-- other, because both rows are written in the same statement.
create or replace function inventory.move_stock (
  p_item_id uuid,
  p_from_location_id uuid,
  p_to_location_id uuid,
  p_quantity numeric,
  p_lot_id uuid default null,
  p_serial_id uuid default null,
  p_out_type inventory.movement_type default 'transfer_out',
  p_in_type inventory.movement_type default 'transfer_in',
  p_reference_type varchar default null,
  p_reference_id uuid default null,
  p_reference_number varchar default null,
  p_occurred_at timestamptz default null,
  p_note varchar default null
) returns uuid language plpgsql security definer
set
  search_path = '' as $$
declare
  v_out uuid;
  v_in uuid;
  v_cost numeric(14, 4);
begin
  if p_quantity <= 0 then
    raise exception 'A move needs a positive quantity; % was given.', p_quantity;
  end if;

  if p_from_location_id = p_to_location_id then
    raise exception 'Moving stock from a bin to itself does nothing.';
  end if;

  select coalesce(unit_cost, 0) into v_cost
  from inventory.stock_levels
  where item_id = p_item_id
    and location_id = p_from_location_id
    and coalesce(lot_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_lot_id, '00000000-0000-0000-0000-000000000000'::uuid);

  v_out := inventory.post_movement (
    p_item_id, p_from_location_id, p_out_type, -p_quantity, p_lot_id, p_serial_id,
    coalesce(v_cost, 0), p_reference_type, p_reference_id, p_reference_number, p_occurred_at, p_note
  );

  insert into inventory.stock_movements (
    item_id, location_id, lot_id, serial_id, movement_type, quantity,
    unit_cost, reference_type, reference_id, reference_number, occurred_at, note,
    counterpart_id
  )
  values (
    p_item_id,
    p_to_location_id,
    p_lot_id,
    p_serial_id,
    p_in_type,
    p_quantity,
    coalesce(v_cost, 0),
    p_reference_type,
    p_reference_id,
    p_reference_number,
    coalesce(p_occurred_at, current_timestamp),
    p_note,
    v_out
  )
  returning id into v_in;

  return v_in;
end;
$$;

revoke all on function inventory.post_movement (
  uuid,
  uuid,
  inventory.movement_type,
  numeric,
  uuid,
  uuid,
  numeric,
  varchar,
  uuid,
  varchar,
  timestamptz,
  varchar
)
from
  public,
  anon,
  authenticated,
  service_role;

revoke all on function inventory.move_stock (
  uuid,
  uuid,
  uuid,
  numeric,
  uuid,
  uuid,
  inventory.movement_type,
  inventory.movement_type,
  varchar,
  uuid,
  varchar,
  timestamptz,
  varchar
)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function inventory.post_movement (
  uuid,
  uuid,
  inventory.movement_type,
  numeric,
  uuid,
  uuid,
  numeric,
  varchar,
  uuid,
  varchar,
  timestamptz,
  varchar
) to "x-admin",
"warehouse";

grant
execute on function inventory.move_stock (
  uuid,
  uuid,
  uuid,
  numeric,
  uuid,
  uuid,
  inventory.movement_type,
  inventory.movement_type,
  varchar,
  uuid,
  varchar,
  timestamptz,
  varchar
) to "x-admin",
"warehouse";

----------------------------------------------------------------
-- Bin resolution
--
-- Every flow needs to answer "which bin?" the same way, so it is
-- asked once here rather than five times with five slightly different
-- fallbacks.
----------------------------------------------------------------
create or replace function inventory.receiving_bin (p_warehouse_id uuid) returns uuid language sql stable security definer
set
  search_path = '' as $$
  select id
  from inventory.locations
  where warehouse_id = p_warehouse_id
    and is_active
    and is_receiving
  order by pick_sequence
  limit 1;
$$;

create or replace function inventory.transit_bin (p_warehouse_id uuid) returns uuid language sql stable security definer
set
  search_path = '' as $$
  select id
  from inventory.locations
  where warehouse_id = p_warehouse_id
    and is_active
    and is_in_transit
  order by pick_sequence
  limit 1;
$$;

-- Where to pick from. FEFO where the settings ask for it: the lot that
-- expires first goes first, and only then the fullest bin. Untracked
-- stock just takes the lowest pick sequence with enough in it.
create or replace function inventory.suggest_pick_bin (
  p_item_id uuid,
  p_warehouse_id uuid,
  p_quantity numeric,
  out location_id uuid,
  out lot_id uuid,
  out available numeric
) language plpgsql stable security definer
set
  search_path = '' as $$
declare
  v_fefo boolean := coalesce((inventory.settings ()).enforce_fefo, true);
begin
  select sl.location_id, sl.lot_id, sl.available
  into location_id, lot_id, available
  from inventory.stock_levels sl
    join inventory.locations l on l.id = sl.location_id
    left join inventory.lots lo on lo.id = sl.lot_id
  where sl.item_id = p_item_id
    and sl.warehouse_id = p_warehouse_id
    and sl.available >= p_quantity
    and l.is_pickable
    and l.is_active
    and not l.is_in_transit
    and coalesce(lo.status, 'available') = 'available'
  order by case when v_fefo then lo.expires_on end asc nulls last,
    l.pick_sequence asc,
    sl.available desc
  limit 1;
end;
$$;

grant
execute on function inventory.receiving_bin (uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.transit_bin (uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.suggest_pick_bin (uuid, uuid, numeric) to "x-admin",
"warehouse";

----------------------------------------------------------------
-- Allocation
--
-- Reserving stock does not move it. It moves the line between what is
-- on hand and what is available, at the same moment, so a second pick
-- cannot promise the same units.
----------------------------------------------------------------
create or replace function inventory.allocate (
  p_item_id uuid,
  p_location_id uuid,
  p_lot_id uuid,
  p_quantity numeric
) returns void language plpgsql security definer
set
  search_path = '' as $$
declare
  v_available numeric(14, 3);
begin
  select available into v_available
  from inventory.stock_levels
  where item_id = p_item_id
    and location_id = p_location_id
    and coalesce(lot_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_lot_id, '00000000-0000-0000-0000-000000000000'::uuid);

  if p_quantity > 0 and coalesce(v_available, 0) < p_quantity then
    raise exception 'Only % available to allocate, not %.', coalesce(v_available, 0), p_quantity;
  end if;

  update inventory.stock_levels
  set allocated = least(greatest(allocated + p_quantity, 0), greatest(on_hand, 0)),
    available = on_hand - least(greatest(allocated + p_quantity, 0), greatest(on_hand, 0)),
    updated_at = current_timestamp
  where item_id = p_item_id
    and location_id = p_location_id
    and coalesce(lot_id, '00000000-0000-0000-0000-000000000000'::uuid)
      = coalesce(p_lot_id, '00000000-0000-0000-0000-000000000000'::uuid);

  perform inventory.recalc_item_position (array[p_item_id]);
end;
$$;

revoke all on function inventory.allocate (uuid, uuid, uuid, numeric)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function inventory.allocate (uuid, uuid, uuid, numeric) to "x-admin",
"warehouse";

----------------------------------------------------------------
-- Purchase orders
----------------------------------------------------------------
create or replace function inventory.po_lines_compute () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.line_number is null then
    select coalesce(max(line_number), 0) + 1 into new.line_number
    from inventory.purchase_order_lines
    where purchase_order_id = new.purchase_order_id;
  end if;

  new.line_total := round(new.ordered_quantity * coalesce(new.unit_price, 0), 2);
  new.outstanding_quantity := greatest(new.ordered_quantity - new.received_quantity, 0);
  new.is_closed := new.received_quantity >= new.ordered_quantity;

  return new;
end;
$$;

create trigger trg_po_lines_compute
before insert or update on inventory.purchase_order_lines for each row
execute function inventory.po_lines_compute ();

create or replace function inventory.po_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_po_id uuid;
  v_subtotal numeric(16, 2);
  v_ordered numeric(14, 3);
  v_received numeric(14, 3);
  v_count integer;
begin
  v_po_id := coalesce(new.purchase_order_id, old.purchase_order_id);

  select coalesce(sum(line_total), 0),
    coalesce(sum(ordered_quantity), 0),
    coalesce(sum(received_quantity), 0),
    count(*)
  into v_subtotal, v_ordered, v_received, v_count
  from inventory.purchase_order_lines
  where purchase_order_id = v_po_id;

  update inventory.purchase_orders
  set subtotal = v_subtotal,
    total = v_subtotal + freight,
    line_count = v_count,
    ordered_quantity = v_ordered,
    received_quantity = v_received,
    outstanding_quantity = greatest(v_ordered - v_received, 0),
    fill_rate = case
      when v_ordered = 0 then null
      else round(100.0 * v_received / v_ordered, 2)::real
    end
  where id = v_po_id
    and (subtotal, line_count, ordered_quantity, received_quantity)
      is distinct from (v_subtotal, v_count, v_ordered, v_received);

  return coalesce(new, old);
end;
$$;

create trigger trg_po_lines_rollup
after insert or delete or update on inventory.purchase_order_lines for each row
execute function inventory.po_rollup ();

-- SECURITY INVOKER, so pg_has_role sees the person approving rather
-- than the owner of the function.
create or replace function inventory.po_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.expected_on := coalesce(
      new.expected_on,
      new.ordered_on + coalesce(
        (select default_lead_time_days from inventory.suppliers where id = new.supplier_id),
        14
      )
    );
    return new;
  end if;

  if new.status = 'approved' and old.status <> 'approved' then
    if not (
      pg_has_role(current_user, 'inventory-planner', 'member')
      or pg_has_role(current_user, 'x-admin', 'member')
    ) then
      raise exception 'Only an inventory-planner can approve purchase order %.', new.po_number;
    end if;

    if coalesce(old.line_count, 0) = 0 then
      raise exception 'Purchase order % has no lines to approve.', new.po_number;
    end if;

    new.approved_by := coalesce(new.approved_by, auth.uid ());
    new.approved_at := coalesce(new.approved_at, current_timestamp);
  end if;

  if new.status = 'cancelled' then
    if coalesce(old.received_quantity, 0) > 0 then
      raise exception 'Purchase order % has already had % units delivered against it.',
        new.po_number, old.received_quantity
        using hint = 'Close the remaining lines instead of cancelling the order.';
    end if;

    if coalesce(new.cancelled_reason, '') = '' then
      raise exception 'Cancelling % needs a reason.', new.po_number;
    end if;
  end if;

  -- Receipt progress owns the middle of the lifecycle. Draft,
  -- submitted, approved and cancelled are decisions; the rest is
  -- arithmetic, and letting somebody type it is how a "received"
  -- order ends up with three pallets outstanding.
  if new.status in ('approved', 'partially_received', 'received') then
    if new.ordered_quantity > 0 and new.received_quantity >= new.ordered_quantity then
      new.status := 'received';
      new.received_on := coalesce(new.received_on, current_date);
    elsif new.received_quantity > 0 then
      new.status := 'partially_received';
      new.received_on := null;
    else
      new.status := 'approved';
      new.received_on := null;
    end if;
  end if;

  new.days_late := case
    when new.status = 'received' and new.expected_on is not null and new.received_on is not null
      then greatest(new.received_on - new.expected_on, 0)
    when new.status in ('approved', 'partially_received') and new.expected_on < current_date
      then current_date - new.expected_on
    else 0
  end;

  return new;
end;
$$;

create trigger trg_po_guard
before insert or update on inventory.purchase_orders for each row
execute function inventory.po_guard ();

create trigger trg_po_updated_at
before update on inventory.purchase_orders for each row
execute function inventory.set_updated_at ();

create or replace function inventory.recalc_supplier_position (p_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  update inventory.suppliers s
  set order_count = x.orders,
    ordered_value = x.value,
    open_order_value = x.open_value,
    last_order_on = x.last_on,
    on_time_rate = x.on_time,
    updated_at = current_timestamp
  from (select distinct t.id from unnest(p_ids) as t (id) where t.id is not null) t
    cross join lateral (
      select count(*) filter (where po.status <> 'draft') as orders,
        coalesce(sum(po.total) filter (where po.status <> 'cancelled'), 0) as value,
        coalesce(sum(po.total) filter (where po.status in ('approved', 'partially_received')), 0) as open_value,
        max(po.ordered_on) filter (where po.status <> 'draft') as last_on,
        round(
          100.0 * count(*) filter (where po.status = 'received' and po.days_late = 0)
            / nullif(count(*) filter (where po.status = 'received'), 0),
          2
        )::real as on_time
      from inventory.purchase_orders po
      where po.supplier_id = t.id
    ) x
  where s.id = t.id
    and (s.order_count, s.ordered_value, s.open_order_value, s.last_order_on, s.on_time_rate)
      is distinct from (x.orders::integer, x.value, x.open_value, x.last_on, x.on_time);
end;
$$;

create or replace function inventory.po_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  perform inventory.recalc_supplier_position (
    array[
      (coalesce(new, old)).supplier_id,
      case when tg_op = 'UPDATE' then old.supplier_id end
    ]
  );

  -- On order is what has been approved and not yet delivered. It is
  -- the difference between "we are out of stock" and "we are out of
  -- stock and nobody has done anything about it".
  update inventory.items i
  set on_order = coalesce(x.qty, 0)
  from (
      select l.item_id, sum(l.outstanding_quantity) as qty
      from inventory.purchase_order_lines l
        join inventory.purchase_orders p on p.id = l.purchase_order_id
      where p.status in ('approved', 'partially_received')
      group by l.item_id
    ) x
  where i.id = x.item_id
    and i.on_order is distinct from x.qty;

  update inventory.items i
  set on_order = 0
  where i.on_order <> 0
    and not exists (
      select 1
      from inventory.purchase_order_lines l
        join inventory.purchase_orders p on p.id = l.purchase_order_id
      where l.item_id = i.id
        and p.status in ('approved', 'partially_received')
    );

  return coalesce(new, old);
end;
$$;

create trigger trg_po_after_change
after insert or delete or update on inventory.purchase_orders for each row
execute function inventory.po_after_change ();

----------------------------------------------------------------
-- Goods receipt
----------------------------------------------------------------
create or replace function inventory.receipt_lines_compute () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.line_number is null then
    select coalesce(max(line_number), 0) + 1 into new.line_number
    from inventory.receipt_lines
    where receipt_id = new.receipt_id;
  end if;

  if new.purchase_order_line_id is not null and new.expected_quantity = 0 then
    select outstanding_quantity into new.expected_quantity
    from inventory.purchase_order_lines
    where id = new.purchase_order_line_id;
  end if;

  new.variance_quantity := new.received_quantity - coalesce(new.expected_quantity, 0);

  return new;
end;
$$;

create trigger trg_receipt_lines_compute
before insert or update on inventory.receipt_lines for each row
execute function inventory.receipt_lines_compute ();

create or replace function inventory.receipt_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_receipt_id uuid;
  v_count integer;
  v_total numeric(14, 3);
  v_put_away numeric(14, 3);
  v_discrepancy boolean;
begin
  v_receipt_id := coalesce(new.receipt_id, old.receipt_id);

  select count(*),
    coalesce(sum(received_quantity), 0),
    coalesce(sum(received_quantity) filter (where is_put_away), 0),
    coalesce(bool_or(variance_quantity <> 0 or rejected_quantity > 0), false)
  into v_count, v_total, v_put_away, v_discrepancy
  from inventory.receipt_lines
  where receipt_id = v_receipt_id;

  update inventory.receipts
  set line_count = v_count,
    total_quantity = v_total,
    put_away_quantity = v_put_away,
    has_discrepancy = v_discrepancy
  where id = v_receipt_id
    and (line_count, total_quantity, put_away_quantity, has_discrepancy)
      is distinct from (v_count, v_total, v_put_away, v_discrepancy);

  return coalesce(new, old);
end;
$$;

create trigger trg_receipt_lines_rollup
after insert or delete or update on inventory.receipt_lines for each row
execute function inventory.receipt_rollup ();

-- Booking a delivery in: create the lot if the line carries one, put
-- the stock in the receiving bin, and tell the purchase order what
-- turned up.
create or replace function inventory.post_receipt (p_receipt_id uuid) returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_receipt inventory.receipts;
  v_line record;
  v_bin uuid;
  v_lot_id uuid;
  v_serial_id uuid;
  v_n integer;
  v_posted integer := 0;
begin
  select * into v_receipt from inventory.receipts where id = p_receipt_id;

  if v_receipt.id is null then
    raise exception 'Receipt % does not exist.', p_receipt_id;
  end if;

  v_bin := coalesce(v_receipt.dock_location_id, inventory.receiving_bin (v_receipt.warehouse_id));

  if v_bin is null then
    raise exception 'There is no receiving bin at that site.'
      using hint = 'Flag one location as is_receiving, or set the dock on the receipt.';
  end if;

  for v_line in
    select rl.*, i.tracking, i.sku
    from inventory.receipt_lines rl
      join inventory.items i on i.id = rl.item_id
    where rl.receipt_id = p_receipt_id
      and rl.received_quantity > 0
    order by rl.line_number
  loop
    v_lot_id := v_line.lot_id;

    -- A lot-tracked delivery arrives as a batch whether or not
    -- anybody typed a code, so one is minted rather than refused.
    if v_line.tracking = 'lot' and v_lot_id is null then
      insert into inventory.lots (
        item_id, lot_code, supplier_id, received_on, expires_on,
        supplier_lot_code, received_quantity, unit_cost
      )
      values (
        v_line.item_id,
        coalesce(v_line.lot_code, v_receipt.receipt_number || '-' || v_line.line_number),
        v_receipt.supplier_id,
        v_receipt.received_on,
        v_line.expires_on,
        v_line.lot_code,
        v_line.received_quantity,
        v_line.unit_cost
      )
      returning id into v_lot_id;

      update inventory.receipt_lines set lot_id = v_lot_id where id = v_line.id;
    end if;

    if v_line.tracking = 'serial' then
      -- A serialised line is not one movement of N units, it is N
      -- movements of one, each against its own serial. Real sites scan
      -- them in; here they are minted from the receipt number so the
      -- provenance is still traceable to the delivery.
      for v_n in 1..(v_line.received_quantity - v_line.rejected_quantity)::integer loop
        insert into inventory.serials (
          item_id, serial_number, lot_id, receipt_line_id, received_on, unit_cost
        )
        values (
          v_line.item_id,
          v_receipt.receipt_number || '-' || lpad(v_line.line_number::text, 2, '0') || '-' || lpad(v_n::text, 3, '0'),
          v_lot_id,
          v_line.id,
          v_receipt.received_on,
          v_line.unit_cost
        )
        returning id into v_serial_id;

        perform inventory.post_movement (
          v_line.item_id,
          v_bin,
          'receipt',
          1,
          v_lot_id,
          v_serial_id,
          v_line.unit_cost,
          'receipt',
          p_receipt_id,
          v_receipt.receipt_number,
          v_receipt.received_on::timestamptz + interval '9 hours',
          v_line.note
        );
      end loop;
    else
      perform inventory.post_movement (
        v_line.item_id,
        v_bin,
        'receipt',
        v_line.received_quantity - v_line.rejected_quantity,
        v_lot_id,
        null,
        v_line.unit_cost,
        'receipt',
        p_receipt_id,
        v_receipt.receipt_number,
        v_receipt.received_on::timestamptz + interval '9 hours',
        v_line.note
      );
    end if;

    if v_line.purchase_order_line_id is not null then
      update inventory.purchase_order_lines
      set received_quantity = received_quantity + v_line.received_quantity
      where id = v_line.purchase_order_line_id;
    end if;

    v_posted := v_posted + 1;
  end loop;

  return v_posted;
end;
$$;

-- Put-away is a separate act on purpose. Until it happens the stock
-- is on the dock, and a pick list that promises it is lying.
create or replace function inventory.put_away_receipt (p_receipt_id uuid) returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_receipt inventory.receipts;
  v_line record;
  v_serial record;
  v_from uuid;
  v_when timestamptz;
  v_moved integer := 0;
begin
  select * into v_receipt from inventory.receipts where id = p_receipt_id;

  v_from := coalesce(v_receipt.dock_location_id, inventory.receiving_bin (v_receipt.warehouse_id));

  -- Stamped with when the work happened, not when the row was
  -- written. The ledger refuses UPDATE, so a movement dated wrongly
  -- stays dated wrongly — there is no fixing it afterwards.
  v_when := least(v_receipt.received_on + 1, current_date)::timestamptz + interval '14 hours';

  for v_line in
    select rl.*, i.tracking
    from inventory.receipt_lines rl
      join inventory.items i on i.id = rl.item_id
    where rl.receipt_id = p_receipt_id
      and not rl.is_put_away
      and rl.put_away_location_id is not null
      and rl.received_quantity > rl.rejected_quantity
    order by rl.line_number
  loop
    if v_line.tracking = 'serial' then
      for v_serial in
        select id from inventory.serials where receipt_line_id = v_line.id
      loop
        perform inventory.move_stock (
          v_line.item_id,
          v_from,
          v_line.put_away_location_id,
          1,
          v_line.lot_id,
          v_serial.id,
          'putaway',
          'putaway',
          'receipt',
          p_receipt_id,
          v_receipt.receipt_number,
          v_when,
          'Put away from ' || v_receipt.receipt_number
        );
      end loop;
    else
      perform inventory.move_stock (
        v_line.item_id,
        v_from,
        v_line.put_away_location_id,
        v_line.received_quantity - v_line.rejected_quantity,
        v_line.lot_id,
        null,
        'putaway',
        'putaway',
        'receipt',
        p_receipt_id,
        v_receipt.receipt_number,
        v_when,
        'Put away from ' || v_receipt.receipt_number
      );
    end if;

    update inventory.receipt_lines set is_put_away = true where id = v_line.id;

    v_moved := v_moved + 1;
  end loop;

  return v_moved;
end;
$$;

create or replace function inventory.receipts_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.supplier_id is null and new.purchase_order_id is not null then
      select supplier_id into new.supplier_id
      from inventory.purchase_orders
      where id = new.purchase_order_id;
    end if;

    new.dock_location_id := coalesce(new.dock_location_id, inventory.receiving_bin (new.warehouse_id));
    return new;
  end if;

  if new.status = 'put_away' and old.status <> 'put_away' then
    new.put_away_at := coalesce(new.put_away_at, current_timestamp);
  end if;

  if old.status = 'put_away' and new.status <> 'put_away' then
    raise exception 'Receipt % has been put away and cannot be reopened.', old.receipt_number
      using hint = 'Raise an adjustment or a transfer instead.';
  end if;

  return new;
end;
$$;

create trigger trg_receipts_guard
before insert or update on inventory.receipts for each row
execute function inventory.receipts_guard ();

create trigger trg_receipts_updated_at
before update on inventory.receipts for each row
execute function inventory.set_updated_at ();

create or replace function inventory.receipts_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = 'checking' and old.status = 'draft' then
    perform inventory.post_receipt (new.id);
  end if;

  if new.status = 'put_away' and old.status <> 'put_away' then
    perform inventory.put_away_receipt (new.id);
  end if;

  return new;
end;
$$;

create trigger trg_receipts_after_change
after update on inventory.receipts for each row
execute function inventory.receipts_after_change ();

----------------------------------------------------------------
-- Transfers
----------------------------------------------------------------
create or replace function inventory.transfer_lines_compute () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.line_number is null then
    select coalesce(max(line_number), 0) + 1 into new.line_number
    from inventory.stock_transfer_lines
    where transfer_id = new.transfer_id;
  end if;

  new.variance_quantity := new.received_quantity - new.shipped_quantity;

  return new;
end;
$$;

create trigger trg_transfer_lines_compute
before insert or update on inventory.stock_transfer_lines for each row
execute function inventory.transfer_lines_compute ();

create or replace function inventory.transfer_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_id uuid;
  v_count integer;
  v_total numeric(14, 3);
  v_shipped numeric(14, 3);
  v_received numeric(14, 3);
begin
  v_id := coalesce(new.transfer_id, old.transfer_id);

  select count(*),
    coalesce(sum(quantity), 0),
    coalesce(sum(shipped_quantity), 0),
    coalesce(sum(received_quantity), 0)
  into v_count, v_total, v_shipped, v_received
  from inventory.stock_transfer_lines
  where transfer_id = v_id;

  update inventory.stock_transfers
  set line_count = v_count,
    total_quantity = v_total,
    received_quantity = v_received,
    in_transit_quantity = greatest(v_shipped - v_received, 0)
  where id = v_id
    and (line_count, total_quantity, received_quantity, in_transit_quantity)
      is distinct from (v_count, v_total, v_received, greatest(v_shipped - v_received, 0));

  return coalesce(new, old);
end;
$$;

create trigger trg_transfer_lines_rollup
after insert or delete or update on inventory.stock_transfer_lines for each row
execute function inventory.transfer_rollup ();

create or replace function inventory.ship_transfer (p_transfer_id uuid) returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_transfer inventory.stock_transfers;
  v_line record;
  v_from uuid;
  v_transit uuid;
  v_shipped integer := 0;
begin
  select * into v_transfer from inventory.stock_transfers where id = p_transfer_id;

  v_transit := inventory.transit_bin (v_transfer.to_warehouse_id);

  if v_transit is null then
    raise exception 'The destination site has no in-transit bin.'
      using hint = 'Flag one location there as is_in_transit.';
  end if;

  for v_line in
    select *
    from inventory.stock_transfer_lines
    where transfer_id = p_transfer_id
      and shipped_quantity < quantity
    order by line_number
  loop
    v_from := v_line.from_location_id;

    if v_from is null then
      select location_id into v_from
      from inventory.suggest_pick_bin (v_line.item_id, v_transfer.from_warehouse_id, v_line.quantity);
    end if;

    if v_from is null then
      raise exception 'Nothing available to ship for line % at the origin site.', v_line.line_number;
    end if;

    perform inventory.move_stock (
      v_line.item_id,
      v_from,
      v_transit,
      v_line.quantity,
      v_line.lot_id,
      null,
      'transfer_out',
      'transfer_in',
      'transfer',
      p_transfer_id,
      v_transfer.transfer_number,
      coalesce(v_transfer.shipped_on, current_date)::timestamptz + interval '11 hours',
      'Shipped on ' || v_transfer.transfer_number
    );

    update inventory.stock_transfer_lines
    set shipped_quantity = v_line.quantity,
      from_location_id = v_from
    where id = v_line.id;

    v_shipped := v_shipped + 1;
  end loop;

  return v_shipped;
end;
$$;

create or replace function inventory.receive_transfer (p_transfer_id uuid) returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_transfer inventory.stock_transfers;
  v_line record;
  v_transit uuid;
  v_to uuid;
  v_received integer := 0;
begin
  select * into v_transfer from inventory.stock_transfers where id = p_transfer_id;

  v_transit := inventory.transit_bin (v_transfer.to_warehouse_id);

  for v_line in
    select *
    from inventory.stock_transfer_lines
    where transfer_id = p_transfer_id
      and received_quantity < shipped_quantity
    order by line_number
  loop
    v_to := coalesce(v_line.to_location_id, inventory.receiving_bin (v_transfer.to_warehouse_id));

    if v_to is null then
      raise exception 'The destination site has no receiving bin for line %.', v_line.line_number;
    end if;

    perform inventory.move_stock (
      v_line.item_id,
      v_transit,
      v_to,
      v_line.shipped_quantity - v_line.received_quantity,
      v_line.lot_id,
      null,
      'transfer_out',
      'transfer_in',
      'transfer',
      p_transfer_id,
      v_transfer.transfer_number,
      coalesce(v_transfer.received_on, current_date)::timestamptz + interval '15 hours',
      'Received against ' || v_transfer.transfer_number
    );

    update inventory.stock_transfer_lines
    set received_quantity = v_line.shipped_quantity,
      to_location_id = v_to
    where id = v_line.id;

    v_received := v_received + 1;
  end loop;

  return v_received;
end;
$$;

create or replace function inventory.transfers_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.expected_on := coalesce(new.expected_on, new.requested_on + 3);
    return new;
  end if;

  -- Only a real transition is worth checking. Shipping and receiving
  -- both write back to the lines, and the line rollup updates this row
  -- again — so without this the second pass would test "received" as
  -- though somebody had just typed it, and refuse the transfer that
  -- had already succeeded.
  if new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'in_transit' then
    if coalesce(old.line_count, 0) = 0 then
      raise exception 'Transfer % has nothing on it to ship.', new.transfer_number;
    end if;

    new.shipped_on := coalesce(new.shipped_on, current_date);
  end if;

  if new.status = 'received' then
    if old.status not in ('in_transit', 'picked') then
      raise exception 'Transfer % has not been shipped yet.', new.transfer_number;
    end if;

    new.received_on := coalesce(new.received_on, current_date);
  end if;

  if old.status = 'received' then
    raise exception 'Transfer % has been received and is closed.', old.transfer_number;
  end if;

  if new.status = 'cancelled' and old.status = 'in_transit' then
    raise exception 'Transfer % is already on the road and cannot be cancelled.', old.transfer_number;
  end if;

  return new;
end;
$$;

create trigger trg_transfers_guard
before insert or update on inventory.stock_transfers for each row
execute function inventory.transfers_guard ();

create trigger trg_transfers_updated_at
before update on inventory.stock_transfers for each row
execute function inventory.set_updated_at ();

create or replace function inventory.transfers_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = 'in_transit' and old.status <> 'in_transit' then
    perform inventory.ship_transfer (new.id);
  end if;

  if new.status = 'received' and old.status <> 'received' then
    perform inventory.receive_transfer (new.id);
  end if;

  return new;
end;
$$;

create trigger trg_transfers_after_change
after update on inventory.stock_transfers for each row
execute function inventory.transfers_after_change ();

----------------------------------------------------------------
-- Picking
----------------------------------------------------------------
create or replace function inventory.pick_lines_compute () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_suggested record;
  v_warehouse uuid;
begin
  if new.line_number is null then
    select coalesce(max(line_number), 0) + 1 into new.line_number
    from inventory.pick_lines
    where pick_list_id = new.pick_list_id;
  end if;

  -- Nobody should have to work out which bin to walk to. If the line
  -- does not name one, the FEFO rule picks it.
  if new.location_id is null then
    select warehouse_id into v_warehouse from inventory.pick_lists where id = new.pick_list_id;

    select * into v_suggested
    from inventory.suggest_pick_bin (new.item_id, v_warehouse, new.requested_quantity);

    new.location_id := v_suggested.location_id;
    new.lot_id := coalesce(new.lot_id, v_suggested.lot_id);
  end if;

  if new.location_id is not null then
    select pick_sequence into new.pick_sequence from inventory.locations where id = new.location_id;
  end if;

  new.short_quantity := greatest(new.requested_quantity - new.picked_quantity, 0);
  new.is_picked := new.picked_quantity > 0;

  return new;
end;
$$;

create trigger trg_pick_lines_compute
before insert or update on inventory.pick_lines for each row
execute function inventory.pick_lines_compute ();

create or replace function inventory.pick_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_id uuid;
  v_count integer;
  v_requested numeric(14, 3);
  v_picked numeric(14, 3);
begin
  v_id := coalesce(new.pick_list_id, old.pick_list_id);

  select count(*), coalesce(sum(requested_quantity), 0), coalesce(sum(picked_quantity), 0)
  into v_count, v_requested, v_picked
  from inventory.pick_lines
  where pick_list_id = v_id;

  update inventory.pick_lists
  set line_count = v_count,
    requested_quantity = v_requested,
    picked_quantity = v_picked,
    short_quantity = greatest(v_requested - v_picked, 0),
    pick_accuracy = case
      when v_requested = 0 then null
      else round(100.0 * v_picked / v_requested, 2)::real
    end
  where id = v_id
    and (line_count, requested_quantity, picked_quantity)
      is distinct from (v_count, v_requested, v_picked);

  return coalesce(new, old);
end;
$$;

create trigger trg_pick_lines_rollup
after insert or delete or update on inventory.pick_lines for each row
execute function inventory.pick_rollup ();

create or replace function inventory.allocate_pick (
  p_pick_list_id uuid,
  p_release boolean default false
) returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_line record;
  v_n integer := 0;
begin
  for v_line in
    select *
    from inventory.pick_lines
    where pick_list_id = p_pick_list_id
      and location_id is not null
      and picked_quantity = 0
  loop
    perform inventory.allocate (
      v_line.item_id,
      v_line.location_id,
      v_line.lot_id,
      case when p_release then -v_line.requested_quantity else v_line.requested_quantity end
    );

    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

-- Picking releases the allocation and takes the stock in the same
-- statement, so there is no moment where the units are both reserved
-- and gone.
create or replace function inventory.post_pick (p_pick_list_id uuid) returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_pick inventory.pick_lists;
  v_line record;
  v_qty numeric(14, 3);
  v_n integer := 0;
begin
  select * into v_pick from inventory.pick_lists where id = p_pick_list_id;

  for v_line in
    select *
    from inventory.pick_lines
    where pick_list_id = p_pick_list_id
      and location_id is not null
    order by pick_sequence, line_number
  loop
    v_qty := case
      when v_line.picked_quantity > 0 then v_line.picked_quantity
      else v_line.requested_quantity
    end;

    perform inventory.allocate (
      v_line.item_id, v_line.location_id, v_line.lot_id, -v_line.requested_quantity
    );

    continue when v_qty <= 0;

    perform inventory.post_movement (
      v_line.item_id,
      v_line.location_id,
      'pick',
      -v_qty,
      v_line.lot_id,
      v_line.serial_id,
      0,
      'pick_list',
      p_pick_list_id,
      v_pick.pick_number,
      coalesce(v_pick.completed_at, v_pick.scheduled_for::timestamptz + interval '13 hours'),
      v_line.note
    );

    update inventory.pick_lines
    set picked_quantity = v_qty
    where id = v_line.id;

    if v_line.request_line_id is not null then
      update inventory.stock_request_lines
      set fulfilled_quantity = fulfilled_quantity + v_qty
      where id = v_line.request_line_id;
    end if;

    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

create or replace function inventory.picks_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    return new;
  end if;

  if new.status = 'assigned' and new.assigned_to is null then
    raise exception 'Assign pick % to somebody before setting it to assigned.', new.pick_number;
  end if;

  if new.status = 'picking' and old.status <> 'picking' then
    new.started_at := coalesce(new.started_at, current_timestamp);
  end if;

  if new.status = 'picked' and old.status <> 'picked' then
    if coalesce(old.line_count, 0) = 0 then
      raise exception 'Pick % has no lines on it.', new.pick_number;
    end if;

    new.completed_at := coalesce(new.completed_at, current_timestamp);
    new.duration_minutes := case
      when new.started_at is null then null
      else greatest(extract(epoch from (new.completed_at - new.started_at)) / 60, 1)::integer
    end;
  end if;

  if new.status = 'dispatched' then
    if old.status not in ('picked', 'dispatched') then
      raise exception 'Pick % has not been picked yet.', new.pick_number;
    end if;

    new.dispatched_at := coalesce(new.dispatched_at, current_timestamp);
  end if;

  if old.status in ('picked', 'dispatched') and new.status in ('pending', 'assigned', 'picking') then
    raise exception 'Pick % has already been picked.', old.pick_number
      using hint = 'Raise an adjustment if the stock came back.';
  end if;

  return new;
end;
$$;

create trigger trg_picks_guard
before insert or update on inventory.pick_lists for each row
execute function inventory.picks_guard ();

create trigger trg_picks_updated_at
before update on inventory.pick_lists for each row
execute function inventory.set_updated_at ();

create or replace function inventory.picks_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = 'assigned' and old.status = 'pending' then
    perform inventory.allocate_pick (new.id, false);
  end if;

  if new.status = 'cancelled' and old.status in ('assigned', 'picking') then
    perform inventory.allocate_pick (new.id, true);
  end if;

  if new.status = 'picked' and old.status <> 'picked' then
    perform inventory.post_pick (new.id);
  end if;

  if new.status = 'dispatched' and old.status <> 'dispatched' and new.request_id is not null then
    update inventory.stock_requests
    set status = 'fulfilled'
    where id = new.request_id
      and status = 'approved';
  end if;

  return new;
end;
$$;

create trigger trg_picks_after_change
after update on inventory.pick_lists for each row
execute function inventory.picks_after_change ();

----------------------------------------------------------------
-- Cycle counting
--
-- The system quantity is stamped onto the line when it is raised, not
-- read when it is posted. A count is a claim about a moment; comparing
-- it against a balance that has moved since would produce a variance
-- that nobody can explain.
----------------------------------------------------------------
create or replace function inventory.count_lines_compute () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.line_number is null then
      select coalesce(max(line_number), 0) + 1 into new.line_number
      from inventory.cycle_count_lines
      where count_id = new.count_id;
    end if;

    new.system_quantity := inventory.on_hand_at (new.item_id, new.location_id, new.lot_id);
  end if;

  new.is_counted := new.counted_quantity is not null;
  new.variance_quantity := coalesce(new.counted_quantity, new.system_quantity) - new.system_quantity;
  new.is_variance := new.is_counted and new.variance_quantity <> 0;
  new.variance_value := round(
    new.variance_quantity * coalesce(
      (select average_cost from inventory.items where id = new.item_id),
      0
    ),
    2
  );

  return new;
end;
$$;

create trigger trg_count_lines_compute
before insert or update on inventory.cycle_count_lines for each row
execute function inventory.count_lines_compute ();

create or replace function inventory.count_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_id uuid;
  v_lines integer;
  v_counted integer;
  v_variances integer;
  v_units numeric(14, 3);
  v_value numeric(16, 2);
begin
  v_id := coalesce(new.count_id, old.count_id);

  select count(*),
    count(*) filter (where is_counted),
    count(*) filter (where is_variance),
    coalesce(sum(abs(variance_quantity)), 0),
    coalesce(sum(variance_value), 0)
  into v_lines, v_counted, v_variances, v_units, v_value
  from inventory.cycle_count_lines
  where count_id = v_id;

  update inventory.cycle_counts
  set line_count = v_lines,
    counted_lines = v_counted,
    variance_lines = v_variances,
    variance_units = v_units,
    variance_value = v_value,
    accuracy_rate = case
      when v_counted = 0 then null
      else round(100.0 * (v_counted - v_variances) / v_counted, 2)::real
    end
  where id = v_id
    and (line_count, counted_lines, variance_lines, variance_units, variance_value)
      is distinct from (v_lines, v_counted, v_variances, v_units, v_value);

  return coalesce(new, old);
end;
$$;

create trigger trg_count_lines_rollup
after insert or delete or update on inventory.cycle_count_lines for each row
execute function inventory.count_rollup ();

create or replace function inventory.post_count (p_count_id uuid) returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_count inventory.cycle_counts;
  v_line record;
  v_n integer := 0;
begin
  select * into v_count from inventory.cycle_counts where id = p_count_id;

  for v_line in
    select *
    from inventory.cycle_count_lines
    where count_id = p_count_id
      and is_variance
    order by line_number
  loop
    perform inventory.post_movement (
      v_line.item_id,
      v_line.location_id,
      case when v_line.variance_quantity > 0 then 'count_in' else 'count_out' end::inventory.movement_type,
      v_line.variance_quantity,
      v_line.lot_id,
      null,
      0,
      'cycle_count',
      p_count_id,
      v_count.count_number,
      coalesce(v_count.posted_at, v_count.scheduled_for::timestamptz + interval '16 hours'),
      coalesce(v_line.note, 'Counted ' || v_line.counted_quantity || ' against ' || v_line.system_quantity)
    );

    v_n := v_n + 1;
  end loop;

  update inventory.stock_levels sl
  set last_counted_on = current_date
  from inventory.cycle_count_lines cl
  where cl.count_id = p_count_id
    and sl.item_id = cl.item_id
    and sl.location_id = cl.location_id
    and cl.is_counted;

  update inventory.locations l
  set last_counted_on = current_date
  where l.id in (
    select distinct location_id
    from inventory.cycle_count_lines
    where count_id = p_count_id
      and is_counted
  );

  return v_n;
end;
$$;

create or replace function inventory.counts_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    return new;
  end if;

  if new.status = 'counting' and old.status = 'planned' then
    new.started_at := coalesce(new.started_at, current_timestamp);
  end if;

  if new.status = 'posted' then
    if old.status = 'posted' then
      return new;
    end if;

    if old.status not in ('counting', 'review') then
      raise exception 'Count % has not been counted yet.', new.count_number;
    end if;

    if coalesce(old.counted_lines, 0) = 0 then
      raise exception 'Count % has no counted lines to post.', new.count_number;
    end if;

    new.posted_at := coalesce(new.posted_at, current_timestamp);
    new.posted_by := coalesce(new.posted_by, auth.uid ());
  end if;

  if old.status = 'posted' and new.status <> 'posted' then
    raise exception 'Count % has been posted to the ledger and cannot be reopened.', old.count_number;
  end if;

  return new;
end;
$$;

create trigger trg_counts_guard
before insert or update on inventory.cycle_counts for each row
execute function inventory.counts_guard ();

create trigger trg_counts_updated_at
before update on inventory.cycle_counts for each row
execute function inventory.set_updated_at ();

create or replace function inventory.counts_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = 'posted' and old.status <> 'posted' then
    perform inventory.post_count (new.id);
  end if;

  return new;
end;
$$;

create trigger trg_counts_after_change
after update on inventory.cycle_counts for each row
execute function inventory.counts_after_change ();

-- A posted count is evidence. Once it is in the ledger the numbers on
-- it stop being editable, or the variance report becomes fiction.
create or replace function inventory.count_lines_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_status inventory.count_status;
  v_number varchar(30);
begin
  select status, count_number into v_status, v_number
  from inventory.cycle_counts
  where id = coalesce(new.count_id, old.count_id);

  if v_status = 'posted' then
    raise exception 'Count % has been posted — its lines are fixed.', v_number;
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_count_lines_guard
before insert or delete or update of counted_quantity,
recount_requested,
note on inventory.cycle_count_lines for each row
execute function inventory.count_lines_guard ();

----------------------------------------------------------------
-- Adjustments
----------------------------------------------------------------
create or replace function inventory.adjustment_lines_compute () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.line_number is null then
    select coalesce(max(line_number), 0) + 1 into new.line_number
    from inventory.stock_adjustment_lines
    where adjustment_id = new.adjustment_id;
  end if;

  new.system_quantity := inventory.on_hand_at (new.item_id, new.location_id, new.lot_id);

  if new.unit_cost = 0 then
    select coalesce(average_cost, 0) into new.unit_cost
    from inventory.items
    where id = new.item_id;
  end if;

  new.line_value := round(new.adjustment_quantity * new.unit_cost, 2);

  return new;
end;
$$;

create trigger trg_adj_lines_compute
before insert or update on inventory.stock_adjustment_lines for each row
execute function inventory.adjustment_lines_compute ();

create or replace function inventory.adjustment_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_id uuid;
  v_count integer;
  v_units numeric(14, 3);
  v_value numeric(16, 2);
  v_threshold numeric(14, 2);
begin
  v_id := coalesce(new.adjustment_id, old.adjustment_id);
  v_threshold := coalesce((inventory.settings ()).adjustment_approval_threshold, 500);

  select count(*), coalesce(sum(adjustment_quantity), 0), coalesce(sum(line_value), 0)
  into v_count, v_units, v_value
  from inventory.stock_adjustment_lines
  where adjustment_id = v_id;

  update inventory.stock_adjustments
  set line_count = v_count,
    total_units = v_units,
    total_value = v_value,
    requires_approval = abs(v_value) > v_threshold
  where id = v_id
    and (line_count, total_units, total_value) is distinct from (v_count, v_units, v_value);

  return coalesce(new, old);
end;
$$;

create trigger trg_adj_lines_rollup
after insert or delete or update on inventory.stock_adjustment_lines for each row
execute function inventory.adjustment_rollup ();

create or replace function inventory.post_adjustment (p_adjustment_id uuid) returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_adj inventory.stock_adjustments;
  v_line record;
  v_n integer := 0;
begin
  select * into v_adj from inventory.stock_adjustments where id = p_adjustment_id;

  for v_line in
    select *
    from inventory.stock_adjustment_lines
    where adjustment_id = p_adjustment_id
    order by line_number
  loop
    perform inventory.post_movement (
      v_line.item_id,
      v_line.location_id,
      case
        when v_adj.reason = 'scrap' then 'scrap'
        when v_line.adjustment_quantity > 0 then 'adjustment_in'
        else 'adjustment_out'
      end::inventory.movement_type,
      v_line.adjustment_quantity,
      v_line.lot_id,
      v_line.serial_id,
      v_line.unit_cost,
      'adjustment',
      p_adjustment_id,
      v_adj.adjustment_number,
      v_adj.adjusted_on::timestamptz + interval '12 hours',
      coalesce(v_line.note, v_adj.reason::text)
    );

    v_n := v_n + 1;
  end loop;

  return v_n;
end;
$$;

create or replace function inventory.adjustments_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    return new;
  end if;

  -- Value is what decides whether a second pair of eyes is needed, so
  -- a small correction does not need a manager and a large write-off
  -- cannot avoid one.
  if new.status = 'approved' and old.status <> 'approved' then
    if old.requires_approval and not pg_has_role(current_user, 'x-admin', 'member') then
      raise exception 'Adjustment % is worth % and needs the inventory manager.',
        new.adjustment_number, old.total_value
        using hint = 'Anything under the threshold in settings can be posted directly.';
    end if;

    if coalesce(old.line_count, 0) = 0 then
      raise exception 'Adjustment % has no lines.', new.adjustment_number;
    end if;

    if coalesce(new.explanation, '') = '' then
      raise exception 'Adjustment % needs an explanation before it is approved.', new.adjustment_number;
    end if;

    new.approved_by := coalesce(new.approved_by, auth.uid ());
    new.approved_at := coalesce(new.approved_at, current_timestamp);
  end if;

  if new.status = 'rejected' and coalesce(new.rejected_reason, '') = '' then
    raise exception 'Rejecting % needs a reason.', new.adjustment_number;
  end if;

  if new.status = 'posted' then
    if old.status = 'posted' then
      return new;
    end if;

    if old.status <> 'approved' then
      raise exception 'Adjustment % must be approved before it is posted.', new.adjustment_number;
    end if;

    new.posted_at := coalesce(new.posted_at, current_timestamp);
  end if;

  if old.status = 'posted' and new.status <> 'posted' then
    raise exception 'Adjustment % is in the ledger and cannot be reopened.', old.adjustment_number;
  end if;

  return new;
end;
$$;

create trigger trg_adjustments_guard
before insert or update on inventory.stock_adjustments for each row
execute function inventory.adjustments_guard ();

create trigger trg_adjustments_updated_at
before update on inventory.stock_adjustments for each row
execute function inventory.set_updated_at ();

create or replace function inventory.adjustments_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = 'posted' and old.status <> 'posted' then
    perform inventory.post_adjustment (new.id);
  end if;

  return new;
end;
$$;

create trigger trg_adjustments_after_change
after update on inventory.stock_adjustments for each row
execute function inventory.adjustments_after_change ();

create or replace function inventory.adjustment_lines_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_status inventory.adjustment_status;
  v_number varchar(30);
begin
  select status, adjustment_number into v_status, v_number
  from inventory.stock_adjustments
  where id = coalesce(new.adjustment_id, old.adjustment_id);

  if v_status in ('approved', 'posted') then
    raise exception 'Adjustment % is % — its lines are fixed.', v_number, v_status;
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_adj_lines_guard
before insert or delete or update of item_id,
location_id,
lot_id,
serial_id,
adjustment_quantity,
note on inventory.stock_adjustment_lines for each row
execute function inventory.adjustment_lines_guard ();

----------------------------------------------------------------
-- Stock requests
----------------------------------------------------------------
create or replace function inventory.request_lines_compute () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.line_number is null then
    select coalesce(max(line_number), 0) + 1 into new.line_number
    from inventory.stock_request_lines
    where request_id = new.request_id;
  end if;

  return new;
end;
$$;

create trigger trg_request_lines_compute
before insert or update on inventory.stock_request_lines for each row
execute function inventory.request_lines_compute ();

create or replace function inventory.request_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_id uuid;
  v_count integer;
  v_total numeric(14, 3);
  v_fulfilled numeric(14, 3);
begin
  v_id := coalesce(new.request_id, old.request_id);

  select count(*),
    coalesce(sum(coalesce(approved_quantity, requested_quantity)), 0),
    coalesce(sum(fulfilled_quantity), 0)
  into v_count, v_total, v_fulfilled
  from inventory.stock_request_lines
  where request_id = v_id;

  update inventory.stock_requests
  set line_count = v_count,
    total_quantity = v_total,
    fulfilled_quantity = v_fulfilled
  where id = v_id
    and (line_count, total_quantity, fulfilled_quantity)
      is distinct from (v_count, v_total, v_fulfilled);

  return coalesce(new, old);
end;
$$;

create trigger trg_request_lines_rollup
after insert or delete or update on inventory.stock_request_lines for each row
execute function inventory.request_rollup ();

create or replace function inventory.requests_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.requester_id := coalesce(new.requester_id, auth.uid ());
    new.warehouse_id := coalesce(
      new.warehouse_id,
      (select id from inventory.warehouses where is_default limit 1)
    );

    if new.status <> 'draft' then
      raise exception 'A request starts as a draft.';
    end if;

    return new;
  end if;

  if new.status is distinct from old.status then
    if new.status = 'submitted' then
      if coalesce(old.line_count, 0) = 0 then
        raise exception 'Request % has nothing on it to submit.', new.request_number;
      end if;

      new.submitted_at := coalesce(new.submitted_at, current_timestamp);
    end if;

    -- Nobody approves their own requisition, and only the warehouse
    -- decides. INVOKER again, so current_user is the person.
    if new.status in ('approved', 'rejected') then
      if not (
        pg_has_role(current_user, 'warehouse', 'member')
        or pg_has_role(current_user, 'x-admin', 'member')
      ) then
        raise exception 'Only the warehouse can decide request %.', new.request_number;
      end if;

      if old.status <> 'submitted' then
        raise exception 'Request % is % — only a submitted request can be decided.',
          new.request_number, old.status;
      end if;

      new.decided_by := coalesce(new.decided_by, auth.uid ());
      new.decided_at := coalesce(new.decided_at, current_timestamp);
    end if;

    if new.status = 'rejected' and coalesce(new.rejected_reason, '') = '' then
      raise exception 'Rejecting request % needs a reason the requester can act on.', new.request_number;
    end if;

    if old.status = 'fulfilled' then
      raise exception 'Request % has been fulfilled and is closed.', old.request_number;
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_requests_guard
before insert or update on inventory.stock_requests for each row
execute function inventory.requests_guard ();

create trigger trg_requests_updated_at
before update on inventory.stock_requests for each row
execute function inventory.set_updated_at ();

----------------------------------------------------------------
-- Remaining housekeeping triggers
----------------------------------------------------------------
create trigger trg_items_updated_at
before update on inventory.items for each row
execute function inventory.set_updated_at ();

create trigger trg_categories_updated_at
before update on inventory.item_categories for each row
execute function inventory.set_updated_at ();

create trigger trg_uom_updated_at
before update on inventory.unit_of_measures for each row
execute function inventory.set_updated_at ();

create trigger trg_warehouses_updated_at
before update on inventory.warehouses for each row
execute function inventory.set_updated_at ();

create trigger trg_zones_updated_at
before update on inventory.zones for each row
execute function inventory.set_updated_at ();

create trigger trg_locations_updated_at
before update on inventory.locations for each row
execute function inventory.set_updated_at ();

create trigger trg_suppliers_updated_at
before update on inventory.suppliers for each row
execute function inventory.set_updated_at ();

create trigger trg_supplier_items_updated_at
before update on inventory.supplier_items for each row
execute function inventory.set_updated_at ();

create trigger trg_lots_updated_at
before update on inventory.lots for each row
execute function inventory.set_updated_at ();

create trigger trg_serials_updated_at
before update on inventory.serials for each row
execute function inventory.set_updated_at ();

create trigger trg_settings_updated_at
before update on inventory.inventory_settings for each row
execute function inventory.set_updated_at ();

create or replace function inventory.category_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  update inventory.item_categories c
  set item_count = x.n
  from (
      select t.id, count(i.id) as n
      from (
          select (coalesce(new, old)).category_id as id
          union
          select case when tg_op = 'UPDATE' then old.category_id end
        ) t
        left join inventory.items i on i.category_id = t.id
      where t.id is not null
      group by t.id
    ) x
  where c.id = x.id
    and c.item_count is distinct from x.n::integer;

  return coalesce(new, old);
end;
$$;

create trigger trg_items_category_rollup
after insert or delete or update of category_id on inventory.items for each row
execute function inventory.category_rollup ();

----------------------------------------------------------------
-- Row actions
----------------------------------------------------------------
create or replace function inventory.submit_purchase_order (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.purchase_orders set status = 'submitted' where id = p_id;
end;
$$;

comment on function inventory.submit_purchase_order (uuid) is '{
    "type": "action",
    "resource": "purchase_orders",
    "name": "Submit",
    "description": "Send the order for approval.",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Order submitted"
}';

create or replace function inventory.approve_purchase_order (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.purchase_orders set status = 'approved' where id = p_id;
end;
$$;

comment on function inventory.approve_purchase_order (uuid) is '{
    "type": "action",
    "resource": "purchase_orders",
    "name": "Approve",
    "description": "Commit to the order and put the quantities on order.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "submitted"]}],
    "success_message": "Order approved"
}';

create or replace function inventory.cancel_purchase_order (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.purchase_orders
  set status = 'cancelled',
    cancelled_reason = p_reason
  where id = p_id;
end;
$$;

comment on function inventory.cancel_purchase_order (uuid, varchar) is '{
    "type": "action",
    "resource": "purchase_orders",
    "name": "Cancel",
    "description": "Cancel the order. Refused once anything has been delivered against it.",
    "icon": "Ban",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "submitted", "approved"]}],
    "success_message": "Order cancelled"
}';

create or replace function inventory.book_in_delivery (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.receipts set status = 'checking' where id = p_id;
end;
$$;

comment on function inventory.book_in_delivery (uuid) is '{
    "type": "action",
    "resource": "receipts",
    "name": "Book in",
    "description": "Take the delivery onto the dock and raise any lots it came with.",
    "icon": "PackageOpen",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Delivery booked in"
}';

create or replace function inventory.complete_put_away (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.receipts set status = 'put_away' where id = p_id;
end;
$$;

comment on function inventory.complete_put_away (uuid) is '{
    "type": "action",
    "resource": "receipts",
    "name": "Put away",
    "description": "Move everything on the dock to the bins named on the lines.",
    "icon": "PackagePlus",
    "visible": [{"id": "status", "operator": "eq", "value": "checking"}],
    "success_message": "Stock put away"
}';

create or replace function inventory.despatch_transfer (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.stock_transfers set status = 'in_transit' where id = p_id;
end;
$$;

comment on function inventory.despatch_transfer (uuid) is '{
    "type": "action",
    "resource": "stock_transfers",
    "name": "Despatch",
    "description": "Pick the lines and put the stock into the destination''s in-transit bin.",
    "icon": "Truck",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "picked"]}],
    "success_message": "Transfer on its way"
}';

create or replace function inventory.book_in_transfer (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.stock_transfers set status = 'received' where id = p_id;
end;
$$;

comment on function inventory.book_in_transfer (uuid) is '{
    "type": "action",
    "resource": "stock_transfers",
    "name": "Book in",
    "description": "Take the transfer out of transit and into the destination bins.",
    "icon": "PackageCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "in_transit"}],
    "success_message": "Transfer received"
}';

create or replace function inventory.assign_pick (p_id uuid, p_picker_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.pick_lists
  set assigned_to = p_picker_id,
    status = 'assigned'
  where id = p_id;
end;
$$;

comment on function inventory.assign_pick (uuid, uuid) is '{
    "type": "action",
    "resource": "pick_lists",
    "name": "Assign",
    "description": "Give the pick to somebody and reserve the stock it needs.",
    "icon": "UserCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "pending"}],
    "success_message": "Pick assigned"
}';

create or replace function inventory.complete_pick (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.pick_lists set status = 'picked' where id = p_id;
end;
$$;

comment on function inventory.complete_pick (uuid) is '{
    "type": "action",
    "resource": "pick_lists",
    "name": "Complete",
    "description": "Take the stock out of the bins and release the reservation.",
    "icon": "PackageCheck",
    "visible": [{"id": "status", "operator": "in", "value": ["assigned", "picking"]}],
    "success_message": "Pick complete"
}';

create or replace function inventory.set_pick_status (p_id uuid, p_status inventory.pick_status) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.pick_lists set status = p_status where id = p_id;
end;
$$;

comment on function inventory.set_pick_status (uuid, inventory.pick_status) is '{
    "type": "action",
    "resource": "pick_lists",
    "name": "Set status",
    "icon": "ArrowRightLeft",
    "action_type": "picker"
}';

create or replace function inventory.post_cycle_count (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.cycle_counts set status = 'posted' where id = p_id;
end;
$$;

comment on function inventory.post_cycle_count (uuid) is '{
    "type": "action",
    "resource": "cycle_counts",
    "name": "Post",
    "description": "Write every variance to the stock ledger. Cannot be undone.",
    "icon": "ClipboardCheck",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "in", "value": ["counting", "review"]}],
    "success_message": "Count posted"
}';

create or replace function inventory.approve_adjustment (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.stock_adjustments set status = 'approved' where id = p_id;
end;
$$;

comment on function inventory.approve_adjustment (uuid) is '{
    "type": "action",
    "resource": "stock_adjustments",
    "name": "Approve",
    "description": "Approve the adjustment for posting.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "pending_approval"]}],
    "success_message": "Adjustment approved"
}';

create or replace function inventory.post_adjustment_action (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.stock_adjustments set status = 'posted' where id = p_id;
end;
$$;

comment on function inventory.post_adjustment_action (uuid) is '{
    "type": "action",
    "resource": "stock_adjustments",
    "name": "Post",
    "description": "Write the adjustment to the stock ledger.",
    "icon": "PackageCheck",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "eq", "value": "approved"}],
    "success_message": "Adjustment posted"
}';

create or replace function inventory.reject_adjustment (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.stock_adjustments
  set status = 'rejected',
    rejected_reason = p_reason
  where id = p_id;
end;
$$;

comment on function inventory.reject_adjustment (uuid, varchar) is '{
    "type": "action",
    "resource": "stock_adjustments",
    "name": "Reject",
    "description": "Send it back with a reason.",
    "icon": "CircleX",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "pending_approval"]}],
    "success_message": "Adjustment rejected"
}';

create or replace function inventory.submit_request (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.stock_requests set status = 'submitted' where id = p_id;
end;
$$;

comment on function inventory.submit_request (uuid) is '{
    "type": "action",
    "resource": "stock_requests",
    "name": "Submit",
    "description": "Send the request to the warehouse.",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Request submitted"
}';

create or replace function inventory.approve_request (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.stock_requests set status = 'approved' where id = p_id;
end;
$$;

comment on function inventory.approve_request (uuid) is '{
    "type": "action",
    "resource": "stock_requests",
    "name": "Approve",
    "description": "Approve the request so it can be picked.",
    "icon": "ThumbsUp",
    "visible": [{"id": "status", "operator": "eq", "value": "submitted"}],
    "success_message": "Request approved"
}';

create or replace function inventory.reject_request (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.stock_requests
  set status = 'rejected',
    rejected_reason = p_reason
  where id = p_id;
end;
$$;

comment on function inventory.reject_request (uuid, varchar) is '{
    "type": "action",
    "resource": "stock_requests",
    "name": "Reject",
    "description": "Decline the request with a reason.",
    "icon": "ThumbsDown",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "eq", "value": "submitted"}],
    "success_message": "Request rejected"
}';

create or replace function inventory.quarantine_lot (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.lots
  set status = 'quarantine',
    note = p_reason
  where id = p_id;
end;
$$;

comment on function inventory.quarantine_lot (uuid, varchar) is '{
    "type": "action",
    "resource": "lots",
    "name": "Quarantine",
    "description": "Hold the batch back. Quarantined lots are never suggested for picking.",
    "icon": "ShieldAlert",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "eq", "value": "available"}],
    "success_message": "Lot quarantined"
}';

create or replace function inventory.release_lot (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update inventory.lots set status = 'available' where id = p_id;
end;
$$;

comment on function inventory.release_lot (uuid) is '{
    "type": "action",
    "resource": "lots",
    "name": "Release",
    "description": "Put the batch back into circulation.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "quarantine"}],
    "success_message": "Lot released"
}';

do $$
declare
  f text;
begin
  foreach f in array array[
    'inventory.submit_purchase_order(uuid)',
    'inventory.approve_purchase_order(uuid)',
    'inventory.cancel_purchase_order(uuid, varchar)',
    'inventory.book_in_delivery(uuid)',
    'inventory.complete_put_away(uuid)',
    'inventory.despatch_transfer(uuid)',
    'inventory.book_in_transfer(uuid)',
    'inventory.assign_pick(uuid, uuid)',
    'inventory.complete_pick(uuid)',
    'inventory.set_pick_status(uuid, inventory.pick_status)',
    'inventory.post_cycle_count(uuid)',
    'inventory.approve_adjustment(uuid)',
    'inventory.post_adjustment_action(uuid)',
    'inventory.reject_adjustment(uuid, varchar)',
    'inventory.submit_request(uuid)',
    'inventory.approve_request(uuid)',
    'inventory.reject_request(uuid, varchar)',
    'inventory.quarantine_lot(uuid, varchar)',
    'inventory.release_lot(uuid)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role;', f);
  end loop;
end;
$$;

grant
execute on function inventory.submit_purchase_order (uuid) to "x-admin",
"inventory-planner";

grant
execute on function inventory.approve_purchase_order (uuid) to "x-admin",
"inventory-planner";

grant
execute on function inventory.cancel_purchase_order (uuid, varchar) to "x-admin",
"inventory-planner";

grant
execute on function inventory.book_in_delivery (uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.complete_put_away (uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.despatch_transfer (uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.book_in_transfer (uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.assign_pick (uuid, uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.complete_pick (uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.set_pick_status (uuid, inventory.pick_status) to "x-admin",
"warehouse";

grant
execute on function inventory.post_cycle_count (uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.approve_adjustment (uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.post_adjustment_action (uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.reject_adjustment (uuid, varchar) to "x-admin",
"warehouse";

grant
execute on function inventory.submit_request (uuid) to "x-admin",
"warehouse",
"user";

grant
execute on function inventory.approve_request (uuid) to "x-admin",
"warehouse";

grant
execute on function inventory.reject_request (uuid, varchar) to "x-admin",
"warehouse";

grant
execute on function inventory.quarantine_lot (uuid, varchar) to "x-admin",
"warehouse";

grant
execute on function inventory.release_lot (uuid) to "x-admin",
"warehouse";

----------------------------------------------------------------
-- Forms
----------------------------------------------------------------
-- Raise a receipt already carrying every outstanding line on the
-- order, because typing them again is how quantities drift.
create or replace function inventory.quick_receive (
  p_purchase_order_id uuid,
  p_carrier varchar default null,
  p_packing_slip varchar default null,
  p_received_on date default current_date
) returns setof inventory.receipts language plpgsql security definer
set
  search_path = '' as $$
declare
  v_po inventory.purchase_orders;
  v_receipt uuid;
begin
  select * into v_po from inventory.purchase_orders where id = p_purchase_order_id;

  if v_po.id is null then
    raise exception 'That purchase order does not exist.';
  end if;

  if v_po.status not in ('approved', 'partially_received') then
    raise exception 'Purchase order % is % — only an approved order can be received against.',
      v_po.po_number, v_po.status;
  end if;

  insert into inventory.receipts (
    purchase_order_id, supplier_id, warehouse_id, received_on, carrier, packing_slip
  )
  values (
    p_purchase_order_id,
    v_po.supplier_id,
    v_po.warehouse_id,
    p_received_on,
    p_carrier,
    p_packing_slip
  )
  returning id into v_receipt;

  insert into inventory.receipt_lines (
    receipt_id, purchase_order_line_id, item_id, expected_quantity, received_quantity, unit_cost
  )
  select v_receipt, l.id, l.item_id, l.outstanding_quantity, l.outstanding_quantity, l.unit_price
  from inventory.purchase_order_lines l
  where l.purchase_order_id = p_purchase_order_id
    and l.outstanding_quantity > 0
  order by l.line_number;

  return query
  select * from inventory.receipts where id = v_receipt;
end;
$$;

comment on function inventory.quick_receive (uuid, varchar, varchar, date) is '{
    "type": "form",
    "resource": "purchase_orders",
    "name": "Receive delivery",
    "description": "Raise a goods receipt pre-filled with everything still outstanding on this order.",
    "icon": "PackageOpen",
    "success_message": "Receipt raised",
    "fields": {
        "sections": [
            {"id": "order", "title": "Order", "fields": ["p_purchase_order_id", "p_received_on"]},
            {"id": "delivery", "title": "Delivery", "fields": ["p_carrier", "p_packing_slip"]}
        ],
        "relations": {
            "p_purchase_order_id": {"table": "purchase_orders", "column": "id", "display": ["po_number", "status"]}
        }
    }
}';

-- An ad-hoc bin move. Everything else in the schema moves stock as a
-- side effect of a document; sometimes a pallet just needs to be
-- somewhere else.
create or replace function inventory.relocate_stock (
  p_item_id uuid,
  p_from_location_id uuid,
  p_to_location_id uuid,
  p_quantity numeric,
  p_lot_id uuid default null,
  p_note varchar default null
) returns uuid language plpgsql security definer
set
  search_path = '' as $$
begin
  return inventory.move_stock (
    p_item_id,
    p_from_location_id,
    p_to_location_id,
    p_quantity,
    p_lot_id,
    null,
    'transfer_out',
    'transfer_in',
    'relocation',
    null,
    null,
    current_timestamp,
    coalesce(p_note, 'Manual relocation')
  );
end;
$$;

comment on function inventory.relocate_stock (uuid, uuid, uuid, numeric, uuid, varchar) is '{
    "type": "form",
    "resource": "stock_levels",
    "name": "Move stock",
    "description": "Move units from one bin to another. Two ledger lines, netting to zero.",
    "icon": "ArrowRightLeft",
    "success_message": "Stock moved",
    "fields": {
        "sections": [
            {"id": "what", "title": "What", "fields": ["p_item_id", "p_lot_id", "p_quantity"]},
            {"id": "where", "title": "Where", "fields": ["p_from_location_id", "p_to_location_id", "p_note"]}
        ],
        "relations": {
            "p_item_id": {"table": "items", "column": "id", "display": ["sku", "name"]},
            "p_lot_id": {"table": "lots", "column": "id", "display": ["lot_code", "expires_on"]},
            "p_from_location_id": {"table": "locations", "column": "id", "display": ["code"]},
            "p_to_location_id": {"table": "locations", "column": "id", "display": ["code"]}
        }
    }
}';

-- Build a count sheet from what the system currently believes, so the
-- counter has a line for every bin rather than a blank page.
create or replace function inventory.plan_cycle_count (
  p_warehouse_id uuid,
  p_zone_id uuid default null,
  p_abc_class inventory.abc_class default null,
  p_scheduled_for date default current_date,
  p_count_type inventory.count_type default 'cycle'
) returns setof inventory.cycle_counts language plpgsql security definer
set
  search_path = '' as $$
declare
  v_count uuid;
  v_lines integer;
begin
  insert into inventory.cycle_counts (warehouse_id, zone_id, count_type, scheduled_for)
  values (p_warehouse_id, p_zone_id, p_count_type, p_scheduled_for)
  returning id into v_count;

  insert into inventory.cycle_count_lines (count_id, item_id, location_id, lot_id)
  select v_count, sl.item_id, sl.location_id, sl.lot_id
  from inventory.stock_levels sl
    join inventory.locations l on l.id = sl.location_id
    join inventory.items i on i.id = sl.item_id
  where sl.warehouse_id = p_warehouse_id
    and (p_zone_id is null or l.zone_id = p_zone_id)
    and (p_abc_class is null or i.abc_class = p_abc_class)
    and sl.on_hand <> 0
    and l.is_active
    -- Serialised stock is verified by scanning each serial, not by
    -- counting a bin, so it does not belong on a count sheet.
    and i.tracking <> 'serial';

  get diagnostics v_lines = row_count;

  if v_lines = 0 then
    delete from inventory.cycle_counts where id = v_count;
    raise exception 'Nothing to count in that scope.'
      using hint = 'Widen the zone or the ABC class.';
  end if;

  return query
  select * from inventory.cycle_counts where id = v_count;
end;
$$;

comment on function inventory.plan_cycle_count (
  uuid,
  uuid,
  inventory.abc_class,
  date,
  inventory.count_type
) is '{
    "type": "form",
    "resource": "cycle_counts",
    "name": "Plan a count",
    "description": "Raise a count sheet with a line for every bin holding stock in the chosen scope.",
    "icon": "ClipboardPen",
    "success_message": "Count sheet ready",
    "fields": {
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["p_warehouse_id", "p_zone_id", "p_abc_class"]},
            {"id": "when", "title": "When", "fields": ["p_scheduled_for", "p_count_type"]}
        ],
        "relations": {
            "p_warehouse_id": {"table": "warehouses", "column": "id", "display": ["code", "name"]},
            "p_zone_id": {"table": "zones", "column": "id", "display": ["code", "name"]}
        }
    }
}';

-- Turn the replenishment list into an actual order, per supplier,
-- rounded up to the pack size each of them insists on.
create or replace function inventory.raise_replenishment (
  p_supplier_id uuid,
  p_warehouse_id uuid,
  out po_number varchar,
  out line_count integer,
  out order_value numeric
) language plpgsql security definer
set
  search_path = '' as $$
declare
  v_po uuid;
  v_line record;
  v_qty numeric(14, 3);
begin
  insert into inventory.purchase_orders (supplier_id, warehouse_id, priority)
  values (p_supplier_id, p_warehouse_id, 'normal')
  returning id into v_po;

  line_count := 0;
  order_value := 0;

  for v_line in
    select i.id as item_id,
      i.reorder_quantity,
      i.reorder_point,
      i.available,
      i.on_order,
      si.unit_price,
      si.minimum_order_quantity,
      si.pack_size
    from inventory.items i
      join inventory.supplier_items si on si.item_id = i.id and si.supplier_id = p_supplier_id
    where i.status = 'active'
      and i.is_below_reorder_point
      and (i.available + i.on_order) <= i.reorder_point
    order by i.sku
  loop
    v_qty := greatest(
      coalesce(nullif(v_line.reorder_quantity, 0), v_line.reorder_point),
      v_line.minimum_order_quantity
    );

    v_qty := ceil(v_qty / v_line.pack_size) * v_line.pack_size;

    insert into inventory.purchase_order_lines (
      purchase_order_id, item_id, ordered_quantity, unit_price
    )
    values (v_po, v_line.item_id, v_qty, v_line.unit_price);

    line_count := line_count + 1;
    order_value := order_value + round(v_qty * v_line.unit_price, 2);
  end loop;

  if line_count = 0 then
    delete from inventory.purchase_orders where id = v_po;
    raise exception 'Nothing from that supplier is below its reorder point.';
  end if;

  select p.po_number into po_number from inventory.purchase_orders p where p.id = v_po;
end;
$$;

comment on function inventory.raise_replenishment (uuid, uuid) is '{
    "type": "form",
    "resource": "suppliers",
    "name": "Raise replenishment",
    "description": "Draft a purchase order covering everything this supplier stocks that has fallen below its reorder point.",
    "icon": "ShoppingCart",
    "success_message": "Replenishment order drafted",
    "fields": {
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["p_supplier_id", "p_warehouse_id"]}
        ],
        "relations": {
            "p_supplier_id": {"table": "suppliers", "column": "id", "display": ["code", "name"]},
            "p_warehouse_id": {"table": "warehouses", "column": "id", "display": ["code", "name"]}
        }
    }
}';

revoke all on function inventory.quick_receive (uuid, varchar, varchar, date)
from
  public,
  anon,
  authenticated,
  service_role;

revoke all on function inventory.relocate_stock (uuid, uuid, uuid, numeric, uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

revoke all on function inventory.plan_cycle_count (
  uuid,
  uuid,
  inventory.abc_class,
  date,
  inventory.count_type
)
from
  public,
  anon,
  authenticated,
  service_role;

revoke all on function inventory.raise_replenishment (uuid, uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function inventory.quick_receive (uuid, varchar, varchar, date) to "x-admin",
"warehouse";

grant
execute on function inventory.relocate_stock (uuid, uuid, uuid, numeric, uuid, varchar) to "x-admin",
"warehouse";

grant
execute on function inventory.plan_cycle_count (
  uuid,
  uuid,
  inventory.abc_class,
  date,
  inventory.count_type
) to "x-admin",
"warehouse";

grant
execute on function inventory.raise_replenishment (uuid, uuid) to "x-admin",
"inventory-planner";

----------------------------------------------------------------
-- Templates
----------------------------------------------------------------
create or replace view inventory.unit_of_measures_template
with
  (security_invoker = true) as
select
  t.code,
  t.name,
  t.uom_type,
  t.decimal_places,
  t.is_base
from
  (
    values
      ('EA', 'Each', 'quantity', 0, true),
      ('BOX', 'Box', 'quantity', 0, false),
      ('CASE', 'Case', 'quantity', 0, false),
      ('PLT', 'Pallet', 'quantity', 0, false),
      ('KG', 'Kilogram', 'weight', 3, true),
      ('G', 'Gram', 'weight', 0, false),
      ('L', 'Litre', 'volume', 3, true),
      ('ML', 'Millilitre', 'volume', 0, false),
      ('M', 'Metre', 'length', 2, true),
      ('ROLL', 'Roll', 'quantity', 0, false)
  ) as t (code, name, uom_type, decimal_places, is_base)
where
  not exists (
    select
      1
    from
      inventory.unit_of_measures u
    where
      u.code = t.code
  );

comment on view inventory.unit_of_measures_template is '{"type": "template", "name": "Standard Units", "description": "Ten units covering count, weight, volume and length. Apply to inventory.unit_of_measures.", "target_table": "unit_of_measures"}';

create or replace view inventory.item_categories_template
with
  (security_invoker = true) as
select
  t.code,
  t.name,
  t.description,
  t.default_count_frequency_days
from
  (
    values
      (
        'RAW',
        'Raw Materials',
        'Inputs consumed in production',
        30
      ),
      (
        'WIP',
        'Work In Progress',
        'Partly finished goods',
        30
      ),
      ('FIN', 'Finished Goods', 'Ready to ship', 30),
      (
        'PACK',
        'Packaging',
        'Cartons, labels and fillers',
        90
      ),
      (
        'SPARE',
        'Spare Parts',
        'Maintenance and service stock',
        180
      ),
      (
        'CONS',
        'Consumables',
        'Used up rather than sold',
        180
      ),
      (
        'TOOL',
        'Tools and Equipment',
        'Durable items issued to staff',
        365
      )
  ) as t (
    code,
    name,
    description,
    default_count_frequency_days
  )
where
  not exists (
    select
      1
    from
      inventory.item_categories c
    where
      c.code = t.code
  );

comment on view inventory.item_categories_template is '{"type": "template", "name": "Default Categories", "description": "Seven top-level categories with sensible count frequencies. Apply to inventory.item_categories.", "target_table": "item_categories"}';

-- Bin codes are generated rather than typed, because a rack of forty
-- locations entered by hand will contain a typo and the typo will be
-- the one bin nobody can find.
create or replace view inventory.locations_template
with
  (security_invoker = true) as
select
  w.id as warehouse_id,
  z.id as zone_id,
  a.aisle || '-' || lpad(r.rack::text, 2, '0') || '-' || l.level || '-' || p.position as code,
  'bin'::inventory.location_type as location_type,
  a.aisle,
  lpad(r.rack::text, 2, '0') as rack,
  l.level,
  p.position,
  (
    (ascii(a.aisle) - 64) * 10000 + r.rack * 100 + (ascii(l.level) - 64) * 10 + p.position::integer
  ) as pick_sequence
from
  inventory.warehouses w
  join inventory.zones z on z.warehouse_id = w.id
  and z.zone_type = 'storage'
  cross join (
    values
      ('A'),
      ('B'),
      ('C')
  ) as a (aisle)
  cross join generate_series(1, 4) as r (rack)
  cross join (
    values
      ('A'),
      ('B')
  ) as l (level)
  cross join (
    values
      ('1'),
      ('2')
  ) as p (position)
where
  w.is_active
  and not exists (
    select
      1
    from
      inventory.locations x
    where
      x.warehouse_id = w.id
      and x.code = a.aisle || '-' || lpad(r.rack::text, 2, '0') || '-' || l.level || '-' || p.position
  );

comment on view inventory.locations_template is '{"type": "template", "name": "Rack Layout", "description": "Forty-eight bins per storage zone — three aisles, four racks, two levels, two positions — with pick sequences already in walking order. Apply to inventory.locations.", "target_table": "locations"}';

revoke all on inventory.unit_of_measures_template,
inventory.item_categories_template,
inventory.locations_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on inventory.unit_of_measures_template,
  inventory.item_categories_template,
  inventory.locations_template to "x-admin";

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view inventory.stock_on_hand_report
with
  (security_invoker = true) as
select
  sl.id,
  i.sku,
  i.name as item,
  c.name as category,
  w.code as warehouse,
  l.code as bin,
  coalesce(lo.lot_code, '—') as lot,
  lo.expires_on,
  i.tracking,
  sl.on_hand,
  sl.allocated,
  sl.available,
  sl.last_movement_at,
  sl.last_counted_on
from
  inventory.stock_levels sl
  join inventory.items i on i.id = sl.item_id
  join inventory.locations l on l.id = sl.location_id
  left join inventory.warehouses w on w.id = sl.warehouse_id
  left join inventory.item_categories c on c.id = i.category_id
  left join inventory.lots lo on lo.id = sl.lot_id
where
  sl.on_hand <> 0
order by
  w.code,
  l.pick_sequence,
  i.sku;

-- Deliberately carries no money. It is the report the floor uses, and
-- inventory.stock_levels does not expose cost to the warehouse role —
-- a security_invoker view would simply be denied. Value lives in
-- Stock Valuation, which the floor does not need and cannot open.
comment on view inventory.stock_on_hand_report is '{"type": "report", "name": "Stock On Hand", "description": "Every bin holding something, and how much of it is spoken for"}';

create or replace view inventory.stock_valuation_report
with
  (security_invoker = true) as
select
  i.id,
  i.sku,
  i.name as item,
  c.name as category,
  i.abc_class,
  i.valuation_method,
  i.on_hand,
  i.allocated,
  i.available,
  i.average_cost,
  i.last_cost,
  i.stock_value,
  i.location_count,
  round(
    100.0 * i.stock_value / nullif(sum(i.stock_value) over (), 0),
    2
  ) as share_of_value,
  i.last_movement_on
from
  inventory.items i
  left join inventory.item_categories c on c.id = i.category_id
where
  i.on_hand <> 0
order by
  i.stock_value desc;

comment on view inventory.stock_valuation_report is '{"type": "report", "name": "Stock Valuation", "description": "What the stock is worth, ranked, with each line''s share of the total"}';

create or replace view inventory.movement_history_report
with
  (security_invoker = true) as
select
  m.id,
  m.movement_number,
  m.occurred_at,
  m.movement_type,
  i.sku,
  i.name as item,
  w.code as warehouse,
  l.code as bin,
  coalesce(lo.lot_code, '—') as lot,
  m.quantity,
  m.balance_after,
  m.unit_cost,
  m.total_cost,
  coalesce(m.reference_type, '—') as reference_type,
  coalesce(m.reference_number, '—') as reference,
  coalesce(u.name, 'System') as performed_by,
  coalesce(m.note, '') as note
from
  inventory.stock_movements m
  join inventory.items i on i.id = m.item_id
  join inventory.locations l on l.id = m.location_id
  left join inventory.warehouses w on w.id = l.warehouse_id
  left join inventory.lots lo on lo.id = m.lot_id
  left join inventory.users u on u.id = m.performed_by
order by
  m.occurred_at desc,
  m.movement_number desc;

comment on view inventory.movement_history_report is '{"type": "report", "name": "Movement History", "description": "The stock ledger in date order. The book of record."}';

create or replace view inventory.reorder_report
with
  (security_invoker = true) as
select
  i.id,
  i.sku,
  i.name as item,
  c.name as category,
  i.abc_class,
  i.status,
  i.on_hand,
  i.allocated,
  i.available,
  i.on_order,
  i.reorder_point,
  i.reorder_quantity,
  greatest(i.reorder_point - (i.available + i.on_order), 0) as shortfall,
  i.lead_time_days,
  coalesce(s.name, 'No preferred supplier') as supplier,
  coalesce(si.supplier_sku, '—') as supplier_sku,
  si.unit_price,
  round(
    greatest(
      coalesce(nullif(i.reorder_quantity, 0), i.reorder_point),
      coalesce(si.minimum_order_quantity, 1)
    ) * coalesce(si.unit_price, 0),
    2
  ) as suggested_order_value,
  i.last_movement_on
from
  inventory.items i
  left join inventory.item_categories c on c.id = i.category_id
  left join inventory.supplier_items si on si.item_id = i.id
  and si.is_preferred
  left join inventory.suppliers s on s.id = si.supplier_id
where
  i.status = 'active'
  and i.is_below_reorder_point
order by
  i.abc_class,
  (i.available + i.on_order) - i.reorder_point;

comment on view inventory.reorder_report is '{"type": "report", "name": "Reorder Report", "description": "Everything at or below its reorder point, with who to buy it from", "template": true}';

create or replace view inventory.expiry_report
with
  (security_invoker = true) as
select
  l.id,
  i.sku,
  i.name as item,
  l.lot_code,
  coalesce(s.name, '—') as supplier,
  l.status,
  l.received_on,
  l.expires_on,
  l.days_to_expiry,
  l.on_hand,
  case
    when l.expires_on is null then 'no expiry'
    when l.expires_on < current_date then 'expired'
    when l.expires_on <= current_date + 30 then 'within 30 days'
    when l.expires_on <= current_date + 90 then 'within 90 days'
    else 'beyond 90 days'
  end as bucket
from
  inventory.lots l
  join inventory.items i on i.id = l.item_id
  left join inventory.suppliers s on s.id = l.supplier_id
where
  l.on_hand > 0
order by
  l.expires_on nulls last;

comment on view inventory.expiry_report is '{"type": "report", "name": "Expiry Report", "description": "Batches still in stock, soonest to expire first, and what they are worth"}';

create or replace view inventory.purchase_order_report
with
  (security_invoker = true) as
select
  po.id,
  po.po_number,
  s.name as supplier,
  w.code as warehouse,
  po.status,
  po.priority,
  po.ordered_on,
  po.expected_on,
  po.received_on,
  po.days_late,
  po.line_count,
  po.ordered_quantity,
  po.received_quantity,
  po.outstanding_quantity,
  po.fill_rate,
  po.currency,
  po.subtotal,
  po.freight,
  po.total,
  coalesce(po.supplier_reference, '—') as supplier_reference
from
  inventory.purchase_orders po
  join inventory.suppliers s on s.id = po.supplier_id
  join inventory.warehouses w on w.id = po.warehouse_id
order by
  po.ordered_on desc;

comment on view inventory.purchase_order_report is '{"type": "report", "name": "Purchase Orders", "description": "Every order with its fill rate and how late it ran"}';

create or replace view inventory.receipt_variance_report
with
  (security_invoker = true) as
select
  rl.id,
  r.receipt_number,
  r.received_on,
  coalesce(po.po_number, '—') as po_number,
  coalesce(s.name, '—') as supplier,
  i.sku,
  i.name as item,
  rl.expected_quantity,
  rl.received_quantity,
  rl.rejected_quantity,
  rl.variance_quantity,
  coalesce(lo.lot_code, '—') as lot,
  coalesce(bin.code, 'not put away') as put_away_to,
  rl.is_put_away
from
  inventory.receipt_lines rl
  join inventory.receipts r on r.id = rl.receipt_id
  join inventory.items i on i.id = rl.item_id
  left join inventory.purchase_orders po on po.id = r.purchase_order_id
  left join inventory.suppliers s on s.id = r.supplier_id
  left join inventory.lots lo on lo.id = rl.lot_id
  left join inventory.locations bin on bin.id = rl.put_away_location_id
order by
  r.received_on desc,
  rl.line_number;

comment on view inventory.receipt_variance_report is '{"type": "report", "name": "Receipt Variances", "description": "What was expected against what turned up, line by line"}';

create or replace view inventory.count_variance_report
with
  (security_invoker = true) as
select
  cl.id,
  cc.count_number,
  cc.scheduled_for,
  cc.status,
  w.code as warehouse,
  l.code as bin,
  i.sku,
  i.name as item,
  coalesce(lo.lot_code, '—') as lot,
  cl.system_quantity,
  cl.counted_quantity,
  cl.variance_quantity,
  cl.is_variance,
  cl.recount_requested,
  coalesce(cl.note, '') as note
from
  inventory.cycle_count_lines cl
  join inventory.cycle_counts cc on cc.id = cl.count_id
  join inventory.items i on i.id = cl.item_id
  join inventory.locations l on l.id = cl.location_id
  left join inventory.warehouses w on w.id = cc.warehouse_id
  left join inventory.lots lo on lo.id = cl.lot_id
order by
  cc.scheduled_for desc,
  abs(cl.variance_quantity) desc;

comment on view inventory.count_variance_report is '{"type": "report", "name": "Count Variances", "description": "Where the records and the shelves disagreed, and by how much"}';

create or replace view inventory.adjustment_report
with
  (security_invoker = true) as
select
  al.id,
  a.adjustment_number,
  a.adjusted_on,
  a.status,
  a.reason,
  w.code as warehouse,
  l.code as bin,
  i.sku,
  i.name as item,
  al.system_quantity,
  al.adjustment_quantity,
  al.unit_cost,
  al.line_value,
  coalesce(u.name, '—') as raised_by,
  coalesce(ap.name, '—') as approved_by,
  coalesce(a.explanation, '') as explanation
from
  inventory.stock_adjustment_lines al
  join inventory.stock_adjustments a on a.id = al.adjustment_id
  join inventory.items i on i.id = al.item_id
  join inventory.locations l on l.id = al.location_id
  left join inventory.warehouses w on w.id = a.warehouse_id
  left join inventory.users u on u.id = a.raised_by
  left join inventory.users ap on ap.id = a.approved_by
order by
  a.adjusted_on desc;

comment on view inventory.adjustment_report is '{"type": "report", "name": "Adjustments", "description": "Stock written on and off, with the reason and the names attached"}';

create or replace view inventory.abc_analysis_report
with
  (security_invoker = true) as
select
  i.id,
  i.sku,
  i.name as item,
  c.name as category,
  i.abc_class as current_class,
  i.on_hand,
  i.stock_value,
  coalesce(mv.units_out, 0) as units_shipped_90d,
  round(coalesce(mv.units_out, 0) * i.average_cost, 2) as throughput_value_90d,
  round(
    100.0 * coalesce(mv.units_out, 0) * i.average_cost / nullif(
      sum(coalesce(mv.units_out, 0) * i.average_cost) over (),
      0
    ),
    2
  ) as share_of_throughput,
  case
    when coalesce(mv.units_out, 0) = 0 then 'no movement'
    when i.on_hand = 0 then 'stocked out'
    else round(coalesce(mv.units_out, 0) / 90.0, 3)::text || ' per day'
  end as velocity
from
  inventory.items i
  left join inventory.item_categories c on c.id = i.category_id
  left join lateral (
    select
      sum(abs(m.quantity)) as units_out
    from
      inventory.stock_movements m
    where
      m.item_id = i.id
      and m.quantity < 0
      and m.movement_type in ('pick', 'ship')
      and m.occurred_at >= current_date - 90
  ) mv on true
where
  i.status = 'active'
order by
  coalesce(mv.units_out, 0) * i.average_cost desc;

comment on view inventory.abc_analysis_report is '{"type": "report", "name": "ABC Analysis", "description": "Items ranked by what actually moves, against the class they are filed under"}';

create or replace view inventory.bin_utilisation_report
with
  (security_invoker = true) as
select
  l.id,
  w.code as warehouse,
  coalesce(z.name, '—') as zone,
  l.code as bin,
  l.location_type,
  l.pick_sequence,
  l.is_pickable,
  l.is_quarantine,
  l.distinct_items,
  l.total_quantity,
  l.last_counted_on,
  case
    when l.last_counted_on is null then 'never counted'
    else (current_date - l.last_counted_on)::text || ' days ago'
  end as last_count,
  case
    when l.distinct_items = 0 then 'empty'
    when l.distinct_items = 1 then 'single item'
    else 'mixed'
  end as occupancy_state
from
  inventory.locations l
  join inventory.warehouses w on w.id = l.warehouse_id
  left join inventory.zones z on z.id = l.zone_id
order by
  w.code,
  l.pick_sequence;

comment on view inventory.bin_utilisation_report is '{"type": "report", "name": "Bin Utilisation", "description": "Which bins are working, which are empty, and which have not been counted"}';

revoke all on inventory.stock_on_hand_report,
inventory.stock_valuation_report,
inventory.movement_history_report,
inventory.reorder_report,
inventory.expiry_report,
inventory.purchase_order_report,
inventory.receipt_variance_report,
inventory.count_variance_report,
inventory.adjustment_report,
inventory.abc_analysis_report,
inventory.bin_utilisation_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on inventory.stock_on_hand_report,
  inventory.stock_valuation_report,
  inventory.movement_history_report,
  inventory.reorder_report,
  inventory.expiry_report,
  inventory.purchase_order_report,
  inventory.receipt_variance_report,
  inventory.count_variance_report,
  inventory.adjustment_report,
  inventory.abc_analysis_report,
  inventory.bin_utilisation_report to "x-admin";

-- The planner buys, so it gets the reports that inform buying. The
-- warehouse gets the ones about where things are — and neither of the
-- two that put a price on stock.
grant
select
  on inventory.reorder_report,
  inventory.expiry_report,
  inventory.purchase_order_report,
  inventory.abc_analysis_report,
  inventory.stock_valuation_report,
  inventory.count_variance_report to "inventory-planner";

grant
select
  on inventory.stock_on_hand_report,
  inventory.expiry_report,
  inventory.count_variance_report,
  inventory.bin_utilisation_report,
  inventory.receipt_variance_report to "warehouse";

----------------------------------------------------------------
-- A view and a materialized view surfaced as browsable resources
----------------------------------------------------------------
-- The buying list. A report you read; this is a list you work
-- through, so it gets to be a resource with its own board and presets.
create or replace view inventory.replenishment_suggestions
with
  (security_invoker = true) as
select
  i.id,
  i.sku,
  i.name as item,
  i.abc_class,
  i.status,
  i.available,
  i.on_order,
  i.reorder_point,
  round(
    greatest(
      coalesce(nullif(i.reorder_quantity, 0), i.reorder_point),
      coalesce(si.minimum_order_quantity, 1)
    ),
    3
  ) as suggested_quantity,
  greatest(i.reorder_point - (i.available + i.on_order), 0) as shortfall,
  i.lead_time_days,
  coalesce(s.name, 'No preferred supplier') as supplier,
  si.supplier_id,
  case
    when i.available <= 0 then 'stocked out'
    when i.on_order > 0 then 'on order'
    when si.supplier_id is null then 'no supplier'
    else 'to order'
  end as state,
  '/inventory/resource/items/' || i.id || '/detail' as link
from
  inventory.items i
  left join inventory.supplier_items si on si.item_id = i.id
  and si.is_preferred
  left join inventory.suppliers s on s.id = si.supplier_id
where
  i.status = 'active'
  and i.is_below_reorder_point;

comment on view inventory.replenishment_suggestions is '{
    "icon": "ShoppingBasket",
    "name": "Replenishment",
    "description": "What to buy next, worst first.",
    "collapsible_group": "Insights",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {"id": "kanban", "name": "By State", "type": "kanban", "group": "state", "title": "sku", "description": "item", "date": "reorder_point", "badge": "abc_class", "read_only": true},
        {"id": "list", "name": "Buying List", "type": "list", "title": "sku", "description": "item", "field_1": "shortfall", "field_2": "supplier", "read_only": true}
    ],
    "filter_presets": [
        {"id": "stocked_out", "name": "Stocked Out", "filters": [{"id": "state", "value": "stocked out", "operator": "eq"}]},
        {"id": "to_order", "name": "Nothing On Order", "filters": [{"id": "state", "value": "to order", "operator": "eq"}]},
        {"id": "class_a", "name": "A Class", "filters": [{"id": "abc_class", "value": "a", "operator": "eq"}]}
    ],
    "query": {"sort": [{"id": "shortfall", "desc": true}]}
}';

comment on column inventory.replenishment_suggestions.shortfall is '{"aggregate": "sum"}';

-- Twelve months of throughput, precomputed. Refresh with:
--   refresh materialized view concurrently inventory.movement_summary;
create materialized view inventory.movement_summary as
select
  (
    w.id::text || '-' || to_char(date_trunc('month', m.occurred_at), 'YYYYMM')
  ) as id,
  w.id as warehouse_id,
  w.code as warehouse,
  date_trunc('month', m.occurred_at)::date as month_start,
  to_char(m.occurred_at, 'Mon YY') as month,
  count(*) as movement_count,
  count(distinct m.item_id) as distinct_items,
  coalesce(
    sum(m.quantity) filter (
      where
        m.movement_type = 'receipt'
    ),
    0
  ) as units_received,
  coalesce(
    sum(abs(m.quantity)) filter (
      where
        m.movement_type in ('pick', 'ship')
    ),
    0
  ) as units_picked,
  coalesce(
    sum(abs(m.quantity)) filter (
      where
        m.movement_type in ('transfer_out')
    ),
    0
  ) as units_transferred,
  coalesce(
    sum(m.quantity) filter (
      where
        m.movement_type in ('adjustment_in', 'adjustment_out', 'scrap')
    ),
    0
  ) as units_adjusted,
  coalesce(
    sum(m.quantity) filter (
      where
        m.movement_type in ('count_in', 'count_out')
    ),
    0
  ) as units_counted,
  coalesce(
    sum(m.total_cost) filter (
      where
        m.movement_type = 'receipt'
    ),
    0
  ) as value_received
from
  inventory.stock_movements m
  join inventory.locations l on l.id = m.location_id
  join inventory.warehouses w on w.id = l.warehouse_id
group by
  w.id,
  w.code,
  date_trunc('month', m.occurred_at),
  to_char(m.occurred_at, 'Mon YY');

create unique index idx_inv_movement_summary_id on inventory.movement_summary (id);

create index idx_inv_movement_summary_month on inventory.movement_summary (month_start);

comment on materialized view inventory.movement_summary is '{
    "icon": "ChartNoAxesCombined",
    "name": "Throughput",
    "description": "Precomputed monthly movement per site. Refresh with: refresh materialized view concurrently inventory.movement_summary;",
    "collapsible_group": "Insights",
    "display": "block",
    "primary_view": "list",
    "views": [
        {"id": "list", "name": "By Month", "type": "list", "title": "month", "description": "warehouse", "field_1": "units_received", "field_2": "units_picked"}
    ],
    "filter_presets": [
        {"id": "adjusted", "name": "Months With Adjustments", "filters": [{"id": "units_adjusted", "value": "0", "operator": "neq"}]}
    ],
    "query": {"sort": [{"id": "month_start", "desc": true}]}
}';

comment on column inventory.movement_summary.units_received is '{"name": "Received", "aggregate": "sum"}';

comment on column inventory.movement_summary.units_picked is '{"name": "Picked", "aggregate": "sum"}';

revoke all on inventory.replenishment_suggestions,
inventory.movement_summary
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on inventory.replenishment_suggestions to "x-admin",
  "inventory-planner",
  "warehouse";

grant
select
  on inventory.movement_summary to "x-admin",
  "inventory-planner";

----------------------------------------------------------------
-- Dashboard widgets
----------------------------------------------------------------
create or replace view inventory.stock_value_total
with
  (security_invoker = true) as
select
  round(coalesce(sum(stock_value), 0), 2) as value,
  'boxes' as icon,
  'total stock at cost' as label
from
  inventory.items;

create or replace view inventory.reorder_alert_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'triangle-alert' as icon,
  'items below reorder point' as label
from
  inventory.items
where
  status = 'active'
  and is_below_reorder_point;

create or replace view inventory.open_picks_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'hand-grab' as icon,
  'picks on the floor' as label
from
  inventory.pick_lists
where
  status in ('pending', 'assigned', 'picking');

create or replace view inventory.expiring_lots_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'calendar-x' as icon,
  'lots expiring within 45 days' as label
from
  inventory.lots
where
  on_hand > 0
  and expires_on is not null
  and expires_on <= current_date + 45;

create or replace view inventory.receipts_vs_picks
with
  (security_invoker = true) as
select
  round(
    coalesce(
      sum(quantity) filter (
        where
          movement_type = 'receipt'
      ),
      0
    ),
    0
  ) as primary,
  round(
    coalesce(
      sum(abs(quantity)) filter (
        where
          movement_type in ('pick', 'ship')
      ),
      0
    ),
    0
  ) as secondary,
  'Received (30d)' as primary_label,
  'Picked (30d)' as secondary_label
from
  inventory.stock_movements
where
  occurred_at >= current_date - 30;

create or replace view inventory.orders_open_vs_late
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status in ('approved', 'partially_received')
  ) as primary,
  count(*) filter (
    where
      status in ('approved', 'partially_received')
      and days_late > 0
  ) as secondary,
  'Open orders' as primary_label,
  'Running late' as secondary_label
from
  inventory.purchase_orders;

create or replace view inventory.stock_accuracy_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        not is_variance
    ) / nullif(
      count(*) filter (
        where
          is_counted
      ),
      0
    ),
    1
  ) as percent
from
  inventory.cycle_count_lines
where
  is_counted;

create or replace view inventory.bin_occupancy_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        distinct_items > 0
    ) / nullif(count(*), 0),
    1
  ) as percent
from
  inventory.locations
where
  is_active;

create or replace view inventory.pick_progress
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status in ('picked', 'dispatched')
  ) as current,
  count(*) as total,
  json_build_array(
    json_build_object(
      'label',
      'Pending',
      'value',
      count(*) filter (
        where
          status = 'pending'
      )
    ),
    json_build_object(
      'label',
      'Assigned',
      'value',
      count(*) filter (
        where
          status = 'assigned'
      )
    ),
    json_build_object(
      'label',
      'Picking',
      'value',
      count(*) filter (
        where
          status = 'picking'
      )
    ),
    json_build_object(
      'label',
      'Done',
      'value',
      count(*) filter (
        where
          status in ('picked', 'dispatched')
      )
    )
  ) as segments
from
  inventory.pick_lists
where
  scheduled_for >= current_date - 7;

create or replace view inventory.stock_by_class_overview
with
  (security_invoker = true) as
select
  count(*) as value,
  'Stocked items' as label,
  'package' as icon,
  json_build_array(
    json_build_object(
      'label',
      'A class',
      'value',
      count(*) filter (
        where
          abc_class = 'a'
      ),
      'variant',
      'destructive'
    ),
    json_build_object(
      'label',
      'B class',
      'value',
      count(*) filter (
        where
          abc_class = 'b'
      ),
      'variant',
      'warning'
    ),
    json_build_object(
      'label',
      'C class',
      'value',
      count(*) filter (
        where
          abc_class = 'c'
      ),
      'variant',
      'secondary'
    ),
    json_build_object(
      'label',
      'Unclassified',
      'value',
      count(*) filter (
        where
          abc_class = 'unclassified'
      ),
      'variant',
      'default'
    )
  ) as breakdown
from
  inventory.items
where
  on_hand > 0;

create or replace view inventory.warehouse_pulse
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Stocked items',
      'value',
      (
        select
          count(*)
        from
          inventory.items
        where
          on_hand > 0
      ),
      'icon',
      'package'
    ),
    json_build_object(
      'label',
      'Bins in use',
      'value',
      (
        select
          count(*)
        from
          inventory.locations
        where
          distinct_items > 0
      ),
      'icon',
      'map-pin'
    ),
    json_build_object(
      'label',
      'Open orders',
      'value',
      (
        select
          count(*)
        from
          inventory.purchase_orders
        where
          status in ('approved', 'partially_received')
      ),
      'icon',
      'shopping-cart'
    ),
    json_build_object(
      'label',
      'In transit',
      'value',
      (
        select
          count(*)
        from
          inventory.stock_transfers
        where
          status = 'in_transit'
      ),
      'icon',
      'truck'
    ),
    json_build_object(
      'label',
      'To put away',
      'value',
      (
        select
          count(*)
        from
          inventory.receipts
        where
          status = 'checking'
      ),
      'icon',
      'package-open'
    ),
    json_build_object(
      'label',
      'Counts due',
      'value',
      (
        select
          count(*)
        from
          inventory.cycle_counts
        where
          status in ('planned', 'counting')
      ),
      'icon',
      'clipboard-check'
    )
  ) as metrics;

create or replace view inventory.arrivals_due
with
  (security_invoker = true) as
select
  po.po_number,
  s.name as supplier,
  po.outstanding_quantity as outstanding,
  to_char(po.expected_on, 'Mon DD') as expected,
  po.days_late,
  '/inventory/resource/purchase_orders/' || po.id || '/detail' as link
from
  inventory.purchase_orders po
  join inventory.suppliers s on s.id = po.supplier_id
where
  po.status in ('approved', 'partially_received')
order by
  po.expected_on
limit
  10;

create or replace view inventory.work_on_the_floor
with
  (security_invoker = true) as
select
  pl.pick_number,
  coalesce(u.name, 'Unassigned') as picker,
  pl.line_count as lines,
  pl.requested_quantity as units,
  pl.status,
  '/inventory/resource/pick_lists/' || pl.id || '/detail' as link
from
  inventory.pick_lists pl
  left join inventory.users u on u.id = pl.assigned_to
where
  pl.status in ('pending', 'assigned', 'picking')
order by
  pl.priority desc,
  pl.scheduled_for
limit
  10;

create or replace view inventory.warehouse_scorecard
with
  (security_invoker = true) as
select
  w.name as warehouse,
  w.distinct_items as items,
  w.location_count as bins,
  (
    select
      count(*)
    from
      inventory.locations l
    where
      l.warehouse_id = w.id
      and l.distinct_items > 0
  ) as bins_in_use,
  (
    select
      count(*)
    from
      inventory.pick_lists p
    where
      p.warehouse_id = w.id
      and p.status in ('pending', 'assigned', 'picking')
  ) as open_picks,
  '/inventory/resource/warehouses/' || w.id || '/detail' as link
from
  inventory.warehouses w
where
  w.is_active
order by
  w.distinct_items desc
limit
  10;

create or replace view inventory.reorder_watchlist
with
  (security_invoker = true) as
select
  i.sku || ' — ' || i.name as title,
  'available ' || i.available || ' against a reorder point of ' || i.reorder_point as description,
  'triangle-alert' as icon,
  case
    when i.available <= 0 then 'destructive'
    else 'warning'
  end as variant,
  '/inventory/resource/items/' || i.id || '/detail' as link
from
  inventory.items i
where
  i.status = 'active'
  and i.is_below_reorder_point
order by
  i.available - i.reorder_point
limit
  10;

create or replace view inventory.expiry_watchlist
with
  (security_invoker = true) as
select
  i.sku as title,
  l.lot_code as description,
  'calendar-x' as icon,
  case
    when l.expires_on < current_date then 'destructive'
    else 'warning'
  end as variant,
  l.on_hand::text as field_1,
  to_char(l.expires_on, 'Mon DD') as field_2,
  '/inventory/resource/lots/' || l.id || '/detail' as link
from
  inventory.lots l
  join inventory.items i on i.id = l.item_id
where
  l.on_hand > 0
  and l.expires_on is not null
  and l.expires_on <= current_date + 60
order by
  l.expires_on
limit
  10;

create or replace view inventory.recent_stock_activity
with
  (security_invoker = true) as
select
  coalesce(u.name, 'System') as actor,
  case m.movement_type
    when 'receipt' then 'booked in'
    when 'putaway' then 'put away'
    when 'pick' then 'picked'
    when 'ship' then 'shipped'
    when 'transfer_out' then 'moved'
    when 'transfer_in' then 'moved in'
    when 'adjustment_in' then 'wrote on'
    when 'adjustment_out' then 'wrote off'
    when 'count_in' then 'counted up'
    when 'count_out' then 'counted down'
    when 'scrap' then 'scrapped'
    else 'moved'
  end as action,
  i.sku || ' × ' || abs(m.quantity) as entity,
  to_char(m.occurred_at, 'Mon DD, HH24:MI') as date,
  '/inventory/resource/stock_movements/' || m.id || '/detail' as link
from
  inventory.stock_movements m
  join inventory.items i on i.id = m.item_id
  left join inventory.users u on u.id = m.performed_by
order by
  m.occurred_at desc
limit
  10;

create or replace view inventory.busiest_items
with
  (security_invoker = true) as
select
  i.sku as name,
  count(m.id) as value,
  i.name as label,
  '/inventory/resource/items/' || i.id || '/detail' as link
from
  inventory.items i
  join inventory.stock_movements m on m.item_id = i.id
where
  m.occurred_at >= current_date - 90
group by
  i.id,
  i.sku,
  i.name
order by
  count(m.id) desc
limit
  10;

create or replace view inventory.adjustments_awaiting_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'sliders-horizontal' as icon,
  'adjustments awaiting approval' as label
from
  inventory.stock_adjustments
where
  status = 'pending_approval';

create or replace view inventory.requests_awaiting_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'clipboard-list' as icon,
  'requests to decide' as label
from
  inventory.stock_requests
where
  status = 'submitted';

revoke all on inventory.stock_value_total,
inventory.reorder_alert_count,
inventory.open_picks_count,
inventory.expiring_lots_count,
inventory.receipts_vs_picks,
inventory.orders_open_vs_late,
inventory.stock_accuracy_rate,
inventory.bin_occupancy_rate,
inventory.pick_progress,
inventory.stock_by_class_overview,
inventory.warehouse_pulse,
inventory.arrivals_due,
inventory.work_on_the_floor,
inventory.warehouse_scorecard,
inventory.reorder_watchlist,
inventory.expiry_watchlist,
inventory.recent_stock_activity,
inventory.busiest_items,
inventory.adjustments_awaiting_count,
inventory.requests_awaiting_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on inventory.stock_value_total,
  inventory.reorder_alert_count,
  inventory.open_picks_count,
  inventory.expiring_lots_count,
  inventory.receipts_vs_picks,
  inventory.orders_open_vs_late,
  inventory.stock_accuracy_rate,
  inventory.bin_occupancy_rate,
  inventory.pick_progress,
  inventory.stock_by_class_overview,
  inventory.warehouse_pulse,
  inventory.arrivals_due,
  inventory.work_on_the_floor,
  inventory.warehouse_scorecard,
  inventory.reorder_watchlist,
  inventory.expiry_watchlist,
  inventory.recent_stock_activity,
  inventory.busiest_items,
  inventory.adjustments_awaiting_count,
  inventory.requests_awaiting_count to "x-admin";

-- The floor gets the operational tiles; stock_value_total is not
-- among them, and neither is anything built on a cost column.
grant
select
  on inventory.reorder_alert_count,
  inventory.open_picks_count,
  inventory.expiring_lots_count,
  inventory.receipts_vs_picks,
  inventory.stock_accuracy_rate,
  inventory.bin_occupancy_rate,
  inventory.pick_progress,
  inventory.stock_by_class_overview,
  inventory.warehouse_pulse,
  inventory.work_on_the_floor,
  inventory.warehouse_scorecard,
  inventory.expiry_watchlist,
  inventory.recent_stock_activity,
  inventory.adjustments_awaiting_count,
  inventory.requests_awaiting_count to "warehouse";

grant
select
  on inventory.reorder_alert_count,
  inventory.expiring_lots_count,
  inventory.orders_open_vs_late,
  inventory.stock_by_class_overview,
  inventory.warehouse_pulse,
  inventory.arrivals_due,
  inventory.reorder_watchlist,
  inventory.busiest_items,
  inventory.stock_value_total to "inventory-planner";

comment on view inventory.stock_value_total is '{"type": "dashboard_widget", "name": "Stock Value", "description": "Everything on hand, at cost", "widget_type": "card_1"}';

comment on view inventory.reorder_alert_count is '{"type": "dashboard_widget", "name": "Below Reorder", "description": "Items that need buying", "widget_type": "card_1", "resource": "items"}';

comment on view inventory.open_picks_count is '{"type": "dashboard_widget", "name": "Open Picks", "description": "Work not yet finished", "widget_type": "card_1", "resource": "pick_lists"}';

comment on view inventory.expiring_lots_count is '{"type": "dashboard_widget", "name": "Expiring Soon", "description": "Batches with a short life left", "widget_type": "card_1", "resource": "lots"}';

comment on view inventory.adjustments_awaiting_count is '{"type": "dashboard_widget", "name": "Adjustments To Approve", "description": "Write-offs waiting on a decision", "widget_type": "card_1", "resource": "stock_adjustments"}';

comment on view inventory.requests_awaiting_count is '{"type": "dashboard_widget", "name": "Requests To Decide", "description": "Requisitions from the business", "widget_type": "card_1", "resource": "stock_requests"}';

comment on view inventory.receipts_vs_picks is '{"type": "dashboard_widget", "name": "In vs Out", "description": "Thirty days of throughput", "widget_type": "card_2"}';

comment on view inventory.orders_open_vs_late is '{"type": "dashboard_widget", "name": "Orders vs Late", "description": "How much of the order book is behind", "widget_type": "card_2", "resource": "purchase_orders"}';

comment on view inventory.stock_accuracy_rate is '{"type": "dashboard_widget", "name": "Stock Accuracy", "description": "Counted lines that matched the record", "widget_type": "card_3"}';

comment on view inventory.bin_occupancy_rate is '{"type": "dashboard_widget", "name": "Bin Occupancy", "description": "Share of active bins holding something", "widget_type": "card_3", "resource": "locations"}';

comment on view inventory.pick_progress is '{"type": "dashboard_widget", "name": "Picking This Week", "description": "Where the week''s picks have got to", "widget_type": "card_4"}';

comment on view inventory.stock_by_class_overview is '{"type": "dashboard_widget", "name": "Stock By Class", "description": "How the stocked range splits by ABC", "widget_type": "card_5"}';

comment on view inventory.warehouse_pulse is '{"type": "dashboard_widget", "name": "Warehouse Pulse", "description": "Everything worth glancing at, in one row", "widget_type": "card_6"}';

comment on view inventory.arrivals_due is '{"type": "dashboard_widget", "name": "Arriving Next", "description": "Orders due in, soonest first", "widget_type": "table_1", "resource": "purchase_orders", "url": "/inventory/resource/purchase_orders"}';

comment on view inventory.work_on_the_floor is '{"type": "dashboard_widget", "name": "On The Floor", "description": "Picks in progress and who has them", "widget_type": "table_1", "url": "/inventory/resource/pick_lists"}';

comment on view inventory.warehouse_scorecard is '{"type": "dashboard_widget", "name": "Site Scorecard", "description": "Items, bins and open work per site", "widget_type": "table_2", "url": "/inventory/resource/warehouses"}';

comment on view inventory.reorder_watchlist is '{"type": "dashboard_widget", "name": "Buy These Next", "description": "The shortest items first", "widget_type": "list_1", "url": "/inventory/resource/items"}';

comment on view inventory.expiry_watchlist is '{"type": "dashboard_widget", "name": "Expiry Watchlist", "description": "Batches running out of shelf life", "widget_type": "list_2", "url": "/inventory/resource/lots"}';

comment on view inventory.recent_stock_activity is '{"type": "dashboard_widget", "name": "Recent Activity", "description": "The last movements through the ledger", "widget_type": "list_3", "url": "/inventory/resource/stock_movements"}';

comment on view inventory.busiest_items is '{"type": "dashboard_widget", "name": "Busiest Items", "description": "Most handled over ninety days", "widget_type": "list_4", "url": "/inventory/resource/items"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
create or replace view inventory.throughput_bar
with
  (security_invoker = true) as
select
  month as label,
  round(sum(units_received), 0) as received,
  round(sum(units_picked), 0) as picked
from
  inventory.movement_summary
where
  month_start >= (current_date - interval '12 months')
group by
  month_start,
  month
order by
  month_start;

create or replace view inventory.stock_value_line
with
  (security_invoker = true) as
select
  month as date,
  round(sum(value_received), 0) as value_received,
  round(sum(units_received), 0) as units_received
from
  inventory.movement_summary
where
  month_start >= (current_date - interval '12 months')
group by
  month_start,
  month
order by
  month_start;

create or replace view inventory.movement_mix_area
with
  (security_invoker = true) as
select
  month as date,
  round(sum(units_received), 0) as received,
  round(sum(units_picked), 0) as picked,
  round(sum(units_transferred), 0) as transferred,
  round(sum(abs(units_adjusted)), 0) as adjusted
from
  inventory.movement_summary
where
  month_start >= (current_date - interval '12 months')
group by
  month_start,
  month
order by
  month_start;

create or replace view inventory.stock_by_category_pie
with
  (security_invoker = true) as
select
  coalesce(c.name, 'Uncategorised') as label,
  round(sum(i.stock_value), 0) as value
from
  inventory.items i
  left join inventory.item_categories c on c.id = i.category_id
where
  i.stock_value > 0
group by
  1
having
  sum(i.stock_value) > 0;

create or replace view inventory.stock_by_warehouse_pie
with
  (security_invoker = true) as
select
  w.name as label,
  round(sum(sl.on_hand), 0) as value
from
  inventory.stock_levels sl
  join inventory.warehouses w on w.id = sl.warehouse_id
where
  sl.on_hand > 0
group by
  1;

create or replace view inventory.movement_type_pie
with
  (security_invoker = true) as
select
  initcap(replace(movement_type::text, '_', ' ')) as label,
  count(*) as value
from
  inventory.stock_movements
where
  occurred_at >= current_date - 90
group by
  1;

create or replace view inventory.supplier_performance_bar
with
  (security_invoker = true) as
select
  s.name as label,
  s.order_count as orders,
  coalesce(s.on_time_rate, 0)::numeric as on_time_rate
from
  inventory.suppliers s
where
  s.order_count > 0
order by
  s.order_count desc
limit
  10;

create or replace view inventory.top_moving_items_bar
with
  (security_invoker = true) as
select
  i.sku as label,
  round(
    coalesce(
      sum(abs(m.quantity)) filter (
        where
          m.movement_type in ('pick', 'ship')
      ),
      0
    ),
    0
  ) as picked,
  round(
    coalesce(
      sum(m.quantity) filter (
        where
          m.movement_type = 'receipt'
      ),
      0
    ),
    0
  ) as received
from
  inventory.items i
  join inventory.stock_movements m on m.item_id = i.id
where
  m.occurred_at >= current_date - 90
group by
  i.id,
  i.sku
order by
  sum(abs(m.quantity)) desc
limit
  10;

create or replace view inventory.warehouse_health_radar
with
  (security_invoker = true) as
select
  'Stock accuracy' as label,
  round(
    100.0 * count(*) filter (
      where
        not is_variance
    ) / nullif(count(*), 0),
    0
  ) as score
from
  inventory.cycle_count_lines
where
  is_counted
union all
select
  'Bin occupancy',
  round(
    100.0 * count(*) filter (
      where
        distinct_items > 0
    ) / nullif(count(*), 0),
    0
  )
from
  inventory.locations
where
  is_active
union all
select
  'Supplier on time',
  round(coalesce(avg(on_time_rate), 0)::numeric, 0)
from
  inventory.suppliers
where
  order_count > 0
union all
select
  'Pick accuracy',
  round(coalesce(avg(pick_accuracy), 0)::numeric, 0)
from
  inventory.pick_lists
where
  status in ('picked', 'dispatched')
union all
select
  'Range in stock',
  round(
    100.0 * count(*) filter (
      where
        on_hand > 0
    ) / nullif(count(*), 0),
    0
  )
from
  inventory.items
where
  status = 'active';

revoke all on inventory.throughput_bar,
inventory.stock_value_line,
inventory.movement_mix_area,
inventory.stock_by_category_pie,
inventory.stock_by_warehouse_pie,
inventory.movement_type_pie,
inventory.supplier_performance_bar,
inventory.top_moving_items_bar,
inventory.warehouse_health_radar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on inventory.throughput_bar,
  inventory.stock_value_line,
  inventory.movement_mix_area,
  inventory.stock_by_category_pie,
  inventory.stock_by_warehouse_pie,
  inventory.movement_type_pie,
  inventory.supplier_performance_bar,
  inventory.top_moving_items_bar,
  inventory.warehouse_health_radar to "x-admin";

grant
select
  on inventory.stock_by_warehouse_pie,
  inventory.movement_type_pie,
  inventory.top_moving_items_bar,
  inventory.warehouse_health_radar to "warehouse";

grant
select
  on inventory.throughput_bar,
  inventory.stock_value_line,
  inventory.stock_by_category_pie,
  inventory.supplier_performance_bar,
  inventory.top_moving_items_bar to "inventory-planner";

comment on view inventory.throughput_bar is '{"type": "chart", "name": "Throughput", "description": "Units in against units out, month by month", "chart_type": "bar"}';

comment on view inventory.stock_value_line is '{"type": "chart", "name": "Purchasing Value", "description": "What was booked in each month, at cost", "chart_type": "line", "format": "currency"}';

comment on view inventory.movement_mix_area is '{"type": "chart", "name": "Movement Mix", "description": "Receipts, picks, transfers and adjustments over time", "chart_type": "area"}';

comment on view inventory.stock_by_category_pie is '{"type": "chart", "name": "Value By Category", "description": "Where the money is sitting", "chart_type": "pie", "format": "currency", "resource": "items"}';

comment on view inventory.stock_by_warehouse_pie is '{"type": "chart", "name": "Units By Site", "description": "How the stock is spread across the network", "chart_type": "pie", "resource": "warehouses"}';

comment on view inventory.movement_type_pie is '{"type": "chart", "name": "Movement Types", "description": "What the ledger has been doing for ninety days", "chart_type": "pie", "resource": "stock_movements"}';

comment on view inventory.supplier_performance_bar is '{"type": "chart", "name": "Supplier Performance", "description": "Order volume against delivery reliability", "chart_type": "bar", "resource": "suppliers"}';

comment on view inventory.top_moving_items_bar is '{"type": "chart", "name": "Top Movers", "description": "The ten items that pass through most", "chart_type": "bar", "resource": "items"}';

comment on view inventory.warehouse_health_radar is '{"type": "chart", "name": "Warehouse Health", "description": "Five operating measures, scored out of a hundred", "chart_type": "radar"}';

----------------------------------------------------------------
-- Maintenance
--
-- The routine that ages the things nobody touches: expired lots,
-- reorder flags, ABC classification and the throughput snapshot.
----------------------------------------------------------------
create or replace function inventory.run_daily_maintenance (
  out lots_expired integer,
  out items_flagged integer,
  out items_reclassified integer,
  out counts_due integer
) language plpgsql security definer
set
  search_path = '' as $$
begin
  with expired as (
    update inventory.lots
    set status = 'expired'
    where status = 'available'
      and expires_on is not null
      and expires_on < current_date
    returning 1
  )
  select count(*) into lots_expired from expired;

  update inventory.lots
  set days_to_expiry = expires_on - current_date
  where expires_on is not null
    and days_to_expiry is distinct from (expires_on - current_date);

  with flagged as (
    update inventory.items
    set is_below_reorder_point = (
      status = 'active'
      and reorder_point > 0
      and available <= reorder_point
    )
    where is_below_reorder_point is distinct from (
      status = 'active'
      and reorder_point > 0
      and available <= reorder_point
    )
    returning 1
  )
  select count(*) into items_flagged from flagged;

  -- ABC by what actually moved, not by what somebody typed a year ago.
  -- The top 80% of throughput value is A, the next 15% B, the rest C.
  with movement as (
    select i.id,
      coalesce(sum(abs(m.quantity)) filter (where m.quantity < 0), 0) * i.average_cost as throughput
    from inventory.items i
      left join inventory.stock_movements m on m.item_id = i.id
      and m.occurred_at >= current_date - 180
    where i.status = 'active'
    group by i.id, i.average_cost
  ),
  ranked as (
    select id,
      throughput,
      sum(throughput) over (order by throughput desc rows between unbounded preceding and current row)
        / nullif(sum(throughput) over (), 0) as running_share
    from movement
  ),
  classified as (
    update inventory.items i
    set abc_class = case
      when r.throughput = 0 then 'c'
      when r.running_share <= 0.80 then 'a'
      when r.running_share <= 0.95 then 'b'
      else 'c'
    end::inventory.abc_class
    from ranked r
    where i.id = r.id
      and i.abc_class is distinct from case
        when r.throughput = 0 then 'c'
        when r.running_share <= 0.80 then 'a'
        when r.running_share <= 0.95 then 'b'
        else 'c'
      end::inventory.abc_class
    returning 1
  )
  select count(*) into items_reclassified from classified;

  select count(*) into counts_due
  from inventory.cycle_counts
  where status in ('planned', 'counting')
    and scheduled_for <= current_date;

  refresh materialized view concurrently inventory.movement_summary;
end;
$$;

revoke all on function inventory.run_daily_maintenance ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function inventory.run_daily_maintenance () to "x-admin";

----------------------------------------------------------------
-- Audit triggers (INSERT/UPDATE fire AFTER, DELETE must fire BEFORE)
--
-- inventory.stock_movements is left out: it is already the trail, it
-- cannot be updated or deleted, and auditing an append-only table
-- would simply store every row twice.
----------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'unit_of_measures', 'item_categories', 'items', 'item_barcodes',
    'warehouses', 'zones', 'locations', 'suppliers', 'supplier_items',
    'lots', 'serials', 'stock_levels', 'purchase_orders', 'purchase_order_lines',
    'receipts', 'receipt_lines', 'stock_transfers', 'stock_transfer_lines',
    'stock_requests', 'stock_request_lines', 'pick_lists', 'pick_lines',
    'cycle_counts', 'cycle_count_lines', 'stock_adjustments', 'stock_adjustment_lines'
  ]
  loop
    execute format(
      'create trigger audit_inventory_%1$s_insert after insert on inventory.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
    execute format(
      'create trigger audit_inventory_%1$s_update after update on inventory.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
    execute format(
      'create trigger audit_inventory_%1$s_delete before delete on inventory.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
  end loop;
end;
$$;

create trigger audit_inventory_inventory_settings_insert
after insert on inventory.inventory_settings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inventory_inventory_settings_update
after update on inventory.inventory_settings for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
--
-- Recipients come from privileges rather than a list of names, so
-- changing who can do a job changes who hears about it.
----------------------------------------------------------------
create or replace function inventory.trg_request_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if tg_op = 'UPDATE' and new.status is not distinct from old.status then
        return new;
    end if;

    if new.status = 'submitted' then
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('inventory', 'stock_requests', 'update'),
            new.requester_id
        );

        if array_length(v_recipients, 1) is null then
            return new;
        end if;

        perform supasheet.create_notification(
            'inventory_request_submitted',
            'Stock request to decide',
            coalesce(new.requester_name, 'Someone') || ' raised ' || new.request_number
              || ' for ' || new.line_count || ' line(s)',
            v_recipients,
            jsonb_build_object('request_id', new.id, 'priority', new.priority),
            '/inventory/resource/stock_requests/' || new.id::text || '/detail'
        );
    elsif new.status in ('approved', 'rejected', 'fulfilled') and new.requester_id is not null then
        perform supasheet.create_notification(
            'inventory_request_' || new.status,
            'Your stock request was ' || new.status,
            new.request_number || ' — ' || coalesce(new.rejected_reason, coalesce(new.purpose, '')),
            array[new.requester_id],
            jsonb_build_object('request_id', new.id, 'status', new.status),
            '/inventory/resource/stock_requests/' || new.id::text || '/detail'
        );
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger request_notify
after insert or update of status on inventory.stock_requests for each row
execute function inventory.trg_request_notify ();

create or replace function inventory.trg_reorder_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if not new.is_below_reorder_point or old.is_below_reorder_point then
        return new;
    end if;

    v_recipients := supasheet.get_users_with_table_privilege('inventory', 'purchase_orders', 'insert');

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'inventory_reorder_point',
        'Reorder point reached',
        new.sku || ' — ' || new.name || ' is down to ' || new.available
          || ' against a reorder point of ' || new.reorder_point,
        v_recipients,
        jsonb_build_object('item_id', new.id, 'available', new.available),
        '/inventory/resource/items/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

-- Unscoped on purpose. is_below_reorder_point is recomputed by the
-- rollup rather than named in anybody's SET list, and UPDATE OF keys
-- off the statement's SET list — so scoping it to that column would
-- mean the notification never fired at all.
create trigger reorder_notify
after update on inventory.items for each row
execute function inventory.trg_reorder_notify ();

create or replace function inventory.trg_adjustment_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.status <> 'pending_approval' or (tg_op = 'UPDATE' and old.status = 'pending_approval') then
        return new;
    end if;

    v_recipients := supasheet.get_users_with_table_privilege('inventory', 'stock_adjustments', 'delete');

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'inventory_adjustment_approval',
        'Adjustment needs approval',
        new.adjustment_number || ' — ' || new.reason || ', ' || new.total_units || ' unit(s)',
        v_recipients,
        jsonb_build_object('adjustment_id', new.id, 'reason', new.reason),
        '/inventory/resource/stock_adjustments/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger adjustment_notify
after insert or update of status on inventory.stock_adjustments for each row
execute function inventory.trg_adjustment_notify ();

create or replace function inventory.trg_receipt_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.status <> 'checking' or (tg_op = 'UPDATE' and old.status = 'checking') then
        return new;
    end if;

    v_recipients := supasheet.get_users_with_table_privilege('inventory', 'receipts', 'update');

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'inventory_receipt_to_put_away',
        'Stock waiting on the dock',
        new.receipt_number || ' — ' || new.total_quantity || ' unit(s) to put away',
        v_recipients,
        jsonb_build_object('receipt_id', new.id, 'quantity', new.total_quantity),
        '/inventory/resource/receipts/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger receipt_notify
after insert or update of status on inventory.receipts for each row
execute function inventory.trg_receipt_notify ();

create or replace function inventory.trg_inventory_comments_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.schema_name <> 'inventory'
       or new.table_name not in ('items', 'purchase_orders', 'stock_adjustments', 'cycle_counts', 'stock_requests') then
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('inventory', new.table_name, 'update'),
        new.created_by
    );

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'inventory_comment_added',
        'New comment on ' || new.table_name,
        left(new.content, 140),
        v_recipients,
        jsonb_build_object('record_id', new.record_id, 'table_name', new.table_name),
        '/inventory/resource/' || new.table_name || '/' || new.record_id::text || '/comment'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists inventory_comments_notify on supasheet.comments;

create trigger inventory_comments_notify
after insert on supasheet.comments for each row
execute function inventory.trg_inventory_comments_notify ();

----------------------------------------------------------------
-- Private document storage
--
-- Packing slips, certificates of analysis and damage photographs are
-- evidence. The policies delegate to the same table privileges the
-- rest of the module uses.
----------------------------------------------------------------
insert into
  storage.buckets (id, name, public)
values
  (
    'inventory-documents',
    'inventory-documents',
    false
  )
on conflict (id) do nothing;

drop policy if exists inventory_documents_read on storage.objects;

create policy inventory_documents_read on storage.objects for
select
  to authenticated using (
    bucket_id = 'inventory-documents'
    and (
      has_table_privilege(current_user, 'inventory.receipts', 'select')
      or has_table_privilege(current_user, 'inventory.lots', 'select')
    )
  );

drop policy if exists inventory_documents_insert on storage.objects;

create policy inventory_documents_insert on storage.objects for insert to authenticated
with
  check (
    bucket_id = 'inventory-documents'
    and (
      has_table_privilege(current_user, 'inventory.receipts', 'insert')
      or has_table_privilege(current_user, 'inventory.lots', 'insert')
    )
  );

drop policy if exists inventory_documents_update on storage.objects;

create policy inventory_documents_update on storage.objects
for update
  to authenticated using (
    bucket_id = 'inventory-documents'
    and has_table_privilege(current_user, 'inventory.receipts', 'update')
  );

drop policy if exists inventory_documents_delete on storage.objects;

create policy inventory_documents_delete on storage.objects for delete to authenticated using (
  bucket_id = 'inventory-documents'
  and has_table_privilege(current_user, 'inventory.items', 'delete')
);

----------------------------------------------------------------
-- App configuration
----------------------------------------------------------------
insert into
  supasheet.configs (key, value, description, is_public)
values
  (
    'inventory.base_currency',
    '"USD"',
    'Currency stock is valued in',
    true
  ),
  (
    'inventory.enforce_fefo',
    'true',
    'Suggest the earliest-expiring lot when picking',
    true
  ),
  (
    'inventory.allow_negative_stock',
    'false',
    'Whether a bin may be taken below zero',
    false
  ),
  (
    'inventory.adjustment_approval_threshold',
    '500',
    'Adjustment value above which the inventory manager must approve',
    false
  ),
  (
    'inventory.expiry_warning_days',
    '45',
    'How far ahead the expiry watchlist looks',
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
