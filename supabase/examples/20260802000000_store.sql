-- ================================================================
-- Supasheet Example — "Store" (ecommerce / order management)
-- ================================================================
-- A production-shaped ecommerce back office: a brand and category
-- catalogue, products with variants and per-warehouse stock, a
-- customer book with addresses, the order pipeline with items,
-- payments, shipments and returns, discount campaigns, and product
-- reviews with moderation.
--
-- The schema is called `store` rather than `ecommerce` because that
-- is the name this project reserves for it — see the commented
-- `api.schemas` line in supabase/config.toml, and the `store.*`
-- examples throughout the documentation.
--
-- Demo data lives in supabase/examples/s_seed.sql — apply this file
-- first, then that one.
--
-- Feature coverage:
--   - Native-role RBAC with THREE custom roles ("merchandiser",
--     "fulfillment", "support") alongside the built-in
--     "x-admin"/"user" — CREATE ROLE + GRANT, no permissions table
--   - Row Level Security including a real storefront pattern: the
--     "user" role is the CUSTOMER, and sees only their own orders,
--     addresses, returns and reviews, resolved through one STABLE
--     SECURITY DEFINER helper (store.current_customer_id)
--   - Column-level GRANT so support can annotate an order without
--     being able to reprice it
--   - Cost and margin live in a 1:1 extension table rather than
--     behind a column-level SELECT grant, because `select *` fails
--     outright for a role that is missing one column
--   - All column data types: URL, TEL, EMAIL, RICH_TEXT, COLOR,
--     PERCENTAGE, DURATION, RATING, file, AVATAR, enums, arrays
--   - All six view layouts: kanban (orders, returns, reviews),
--     calendar (orders, shipments), gallery (products, brands,
--     categories), list (warehouses, inventory, payments), tree
--     (category hierarchy), gantt (discount campaigns)
--   - Field sections, filter presets, quick_create, conditional
--     field behavior, lookup fill + lookup filter, resource links
--   - Singleton resource (store_settings)
--   - 1:1 extension record (product_costs — never seen by
--     fulfillment or support)
--   - Detail lines with business triggers that keep parent rollups
--     in sync (order_items -> order totals -> customer lifetime
--     value, inventory_movements -> inventory_levels -> variant and
--     product stock, reviews -> product rating, orders -> discount
--     usage)
--   - Real inventory mechanics: confirming an order RESERVES stock,
--     shipping converts the reservation into a sale movement, a
--     received return restocks it, and every change lands in an
--     append-only movement ledger
--   - Integrity guards that raise rather than corrupt: you cannot
--     oversell, cannot edit a completed or cancelled order, cannot
--     return more than was bought, cannot use an expired or
--     exhausted discount, and cannot delete a product that has been
--     sold
--   - Detail page "tabs" allowlist + "timelines" (order_events, a
--     trigger-populated, read-only activity feed)
--   - Row actions backed by SQL functions (confirm, mark paid, ship,
--     deliver, cancel, refund, approve and reject a review, receive
--     a return, publish and archive a product, set order status as
--     an enum picker)
--   - Custom forms backed by SQL functions, each returning a
--     different shape: receive_stock (scalar uuid, on "warehouses"),
--     create_manual_order (single object via OUT params, on
--     "customers"), bulk_reprice (setof store.products, on
--     "brands"), preview_restock_plan (setof rows via an explicit
--     table(...) list, on "warehouses")
--   - Templates (bulk insert via supasheet.apply_template): one
--     static (default_categories_template) and two dynamic
--     (restock_movements_template, winback_discounts_template)
--   - Reports, including one with an HTML/Handlebars print template
--     (sales_report -> supabase/examples/templates/sales_report.hbs)
--     and a MATERIALIZED VIEW report (sales_rollup)
--   - Dashboard widgets: every contract (card_1..card_6, table_1,
--     table_2, list_1..list_4), global and resource-scoped
--   - Charts: every contract (pie, bar, line, area, radar), global
--     and resource-scoped
--   - Notifications (order placed and paid, shipment dispatched,
--     low stock, return requested, review awaiting moderation, and a
--     comment-notify pairing on supasheet.comments)
--   - Audit logging and per-resource comments
--   - Column footer aggregates via the `aggregate` column comment key
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260802000000_store.sql \
--     -f supabase/examples/s_seed.sql
--
-- Requires the base Supasheet migrations (supabase/migrations/*) to
-- already be applied. Also add "store" to config.toml's `api.schemas`
-- and `api.extra_search_path` so PostgREST exposes it, then restart
-- Supabase.
--
-- Not idempotent: `create schema` / `create type` / `create table`
-- fail on a second run. Re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists store;

-------------------------------------------------------------------
-- Roles
--
-- "x-admin" ships with the base migrations. "user" and "admin" are
-- the optional built-in tiers (created in supabase/seed.sql), and
-- "merchandiser"/"fulfillment"/"support" are custom roles specific
-- to this module — a custom role is nothing more than
-- `create role ... nologin` plus grants.
--
--   x-admin       store owner: everything, including cost and margin
--   merchandiser  catalogue and pricing: products, variants,
--                 categories, brands, discounts, review moderation;
--                 reads orders but never edits them
--   fulfillment   operations: orders, shipments, inventory and
--                 returns; reads the catalogue, never sees cost
--   support       customer service: reads everything customer-facing
--                 and may annotate an order, but cannot reprice,
--                 refund or fulfil it
--   user          THE CUSTOMER: their own orders, addresses, returns
--                 and reviews, and the published catalogue
--
-- Assign a user to a custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "fulfillment"}'
--   where email = 'ops@supasheet.app';
-- (takes effect on next login / token refresh)
-------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'user') then
    create role "user" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'admin') then
    create role "admin" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'merchandiser') then
    create role "merchandiser" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'fulfillment') then
    create role "fulfillment" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'support') then
    create role "support" nologin;
  end if;
end;
$$;

-- Let PostgREST SET ROLE into each role...
grant "user",
"admin",
"merchandiser",
"fulfillment",
"support" to authenticator;

-- ...and let `to authenticated` policies still apply to them.
grant authenticated to "user",
"admin",
"merchandiser",
"fulfillment",
"support";

-- Schema usage is granted per native role, never to `authenticated`.
grant usage on schema store to "x-admin",
"merchandiser",
"fulfillment",
"support",
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

----------------------------------------------------------------
-- Enums (must commit before they can be used by later statements)
----------------------------------------------------------------
begin;

create type store.product_status as enum('draft', 'active', 'archived');

create type store.product_type as enum('simple', 'variant', 'digital', 'bundle');

create type store.order_status as enum(
  'pending',
  'confirmed',
  'processing',
  'completed',
  'cancelled'
);

create type store.payment_status as enum(
  'unpaid',
  'authorized',
  'partially_paid',
  'paid',
  'partially_refunded',
  'refunded',
  'failed'
);

create type store.fulfillment_status as enum(
  'unfulfilled',
  'partially_fulfilled',
  'fulfilled',
  'returned'
);

create type store.sales_channel as enum(
  'web',
  'mobile_app',
  'pos',
  'marketplace',
  'phone'
);

create type store.payment_method as enum(
  'card',
  'paypal',
  'bank_transfer',
  'cash_on_delivery',
  'wallet',
  'gift_card'
);

create type store.payment_state as enum(
  'pending',
  'authorized',
  'captured',
  'failed',
  'refunded',
  'voided'
);

create type store.shipment_status as enum(
  'pending',
  'label_created',
  'in_transit',
  'out_for_delivery',
  'delivered',
  'failed',
  'returned'
);

create type store.return_status as enum(
  'requested',
  'approved',
  'received',
  'refunded',
  'rejected',
  'cancelled'
);

create type store.return_reason as enum(
  'damaged',
  'wrong_item',
  'not_as_described',
  'no_longer_needed',
  'late_delivery',
  'other'
);

create type store.movement_type as enum(
  'receipt',
  'sale',
  'return',
  'adjustment',
  'transfer_in',
  'transfer_out',
  'damage',
  'stocktake'
);

create type store.discount_type as enum('percentage', 'fixed_amount', 'free_shipping');

create type store.discount_status as enum('scheduled', 'active', 'paused', 'expired');

create type store.customer_group as enum(
  'guest',
  'registered',
  'member',
  'vip',
  'wholesale'
);

create type store.customer_status as enum('active', 'inactive', 'blocked');

create type store.review_status as enum('pending', 'approved', 'rejected', 'spam');

create type store.address_type as enum('billing', 'shipping');

create type store.order_event_type as enum(
  'created',
  'confirmed',
  'paid',
  'fulfilled',
  'shipped',
  'delivered',
  'cancelled',
  'refunded',
  'return_requested',
  'note_added',
  'record_updated'
);

commit;

----------------------------------------------------------------
-- Users replica view
--
-- FKs point at the real supasheet.users table, but PostgREST cannot
-- embed across schemas — every app schema needs a same-name replica
-- view so `query.join` on a user column resolves.
----------------------------------------------------------------
create or replace view store.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on store.users
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.users to "x-admin",
  "merchandiser",
  "fulfillment",
  "support",
  "user";

----------------------------------------------------------------
-- Staff helper
--
-- "Is the caller store staff, as opposed to a shopper?" Every
-- customer-scoped policy below needs it. Kept as a plain STABLE
-- function (not SECURITY DEFINER) because pg_has_role answers about
-- current_user, and inside a definer function current_user would be
-- the owner instead of the caller.
----------------------------------------------------------------
create or replace function store.is_store_staff () returns boolean language sql stable
set
  search_path = '' as $$
  select pg_has_role(current_user, 'x-admin', 'member')
      or pg_has_role(current_user, 'merchandiser', 'member')
      or pg_has_role(current_user, 'fulfillment', 'member')
      or pg_has_role(current_user, 'support', 'member');
$$;

revoke all on function store.is_store_staff ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.is_store_staff () to "x-admin",
"merchandiser",
"fulfillment",
"support",
"user";

----------------------------------------------------------------
-- Brands
----------------------------------------------------------------
create table store.brands (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(160) not null unique,
  slug varchar(160) not null unique,
  description text,
  logo supasheet.file,
  website supasheet.URL,
  support_email supasheet.EMAIL,
  country varchar(120),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table store.brands is '{
    "icon": "Tag",
    "collapsible_group": "Catalogue",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "name", "badges": ["is_active", "country"]},
        "tabs": ["products"]
    },
    "views": [
        {
            "id": "gallery",
            "name": "Brand Wall",
            "type": "gallery",
            "cover": "logo",
            "title": "name",
            "description": "description",
            "badge": "country"
        },
        {
            "id": "list",
            "name": "All Brands",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "country",
            "field_2": "is_active"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["name", "slug", "country"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "slug", "description", "logo"]},
            {"id": "contact", "title": "Contact", "fields": ["website", "support_email", "country"]},
            {"id": "display", "title": "Display", "fields": ["is_active", "sort_order", "color"]}
        ]
    },
    "query": {
        "sort": [{"id": "sort_order", "desc": false}]
    }
}';

comment on column store.brands.logo is '{"accept": "image/*", "max_size": 2097152}';

revoke all on table store.brands
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
delete on table store.brands to "x-admin";

grant
select
,
  insert,
update on table store.brands to "merchandiser";

grant
select
  on table store.brands to "fulfillment",
  "support",
  "user";

create index idx_store_brands_is_active on store.brands (is_active);

alter table store.brands enable row level security;

create policy brands_select on store.brands for
select
  to authenticated using (true);

create policy brands_insert on store.brands for insert to authenticated
with
  check (true);

create policy brands_update on store.brands
for update
  to authenticated using (true)
with
  check (true);

create policy brands_delete on store.brands for delete to authenticated using (true);

----------------------------------------------------------------
-- Categories (self-referencing merchandising tree)
----------------------------------------------------------------
create table store.categories (
  id uuid primary key default extensions.uuid_generate_v4 (),
  parent_id uuid references store.categories (id) on delete set null,
  name varchar(160) not null,
  slug varchar(160) not null unique,
  description text,
  image supasheet.file,
  is_active boolean not null default true,
  show_in_menu boolean not null default true,
  sort_order integer not null default 0,
  seo_title varchar(200),
  seo_description varchar(400),
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint categories_not_own_parent check (id <> parent_id)
);

comment on table store.categories is '{
    "icon": "FolderTree",
    "collapsible_group": "Catalogue",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["is_active", "show_in_menu"]},
        "tabs": ["products", "categories"]
    },
    "views": [
        {
            "id": "tree",
            "name": "Category Tree",
            "type": "tree",
            "parent": "parent_id",
            "title": "name",
            "secondary": "slug"
        },
        {
            "id": "gallery",
            "name": "Shop By Category",
            "type": "gallery",
            "cover": "image",
            "title": "name",
            "description": "description",
            "badge": "is_active"
        },
        {
            "id": "list",
            "name": "All Categories",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "slug",
            "field_2": "sort_order"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "top_level", "name": "Top Level", "filters": [{"id": "parent_id", "value": "null", "operator": "is"}]},
        {"id": "menu", "name": "In Menu", "filters": [{"id": "show_in_menu", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["name", "slug", "parent_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "slug", "description", "parent_id", "image"]},
            {"id": "display", "title": "Display", "fields": ["is_active", "show_in_menu", "sort_order", "color"]},
            {"id": "seo", "title": "SEO", "collapsible": true, "fields": ["seo_title", "seo_description"]}
        ]
    },
    "query": {
        "sort": [{"id": "sort_order", "desc": false}],
        "join": [{"table": "categories", "on": "parent_id", "alias": "parent", "columns": ["name", "slug"]}]
    }
}';

comment on column store.categories.image is '{"accept": "image/*", "max_size": 5242880}';

revoke all on table store.categories
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
delete on table store.categories to "x-admin";

grant
select
,
  insert,
update on table store.categories to "merchandiser";

grant
select
  on table store.categories to "fulfillment",
  "support",
  "user";

create index idx_store_categories_parent_id on store.categories (parent_id);

create index idx_store_categories_sort_order on store.categories (sort_order);

-- Two sibling categories cannot share a name; two branches may.
create unique index idx_store_categories_sibling_name on store.categories (
  coalesce(
    parent_id,
    '00000000-0000-0000-0000-000000000000'::uuid
  ),
  lower(name)
);

alter table store.categories enable row level security;

create policy categories_select on store.categories for
select
  to authenticated using (true);

create policy categories_insert on store.categories for insert to authenticated
with
  check (true);

create policy categories_update on store.categories
for update
  to authenticated using (true)
with
  check (true);

create policy categories_delete on store.categories for delete to authenticated using (true);

----------------------------------------------------------------
-- Products
--
-- The catalogue record. Prices live on the variants; the columns
-- here are the defaults a single-variant product is created with,
-- and the rollups the storefront and the merchandising reports read.
----------------------------------------------------------------
create table store.products (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null,
  -- Nullable on purpose: store.trg_products_apply_defaults slugifies
  -- the name whenever the field is left empty.
  slug varchar(255) unique,
  brand_id uuid references store.brands (id) on delete set null,
  category_id uuid references store.categories (id) on delete set null,
  product_type store.product_type not null default 'simple',
  status store.product_status not null default 'draft',
  short_description varchar(500),
  description supasheet.RICH_TEXT,
  image supasheet.file,
  gallery supasheet.file,
  price numeric(12, 2) not null default 0,
  compare_at_price numeric(12, 2),
  currency varchar(3) not null default 'USD',
  tax_rate supasheet.PERCENTAGE not null default 0,
  weight_grams integer,
  requires_shipping boolean not null default true,
  is_featured boolean not null default false,
  option_1_name varchar(60),
  option_2_name varchar(60),
  option_3_name varchar(60),
  variant_count integer not null default 0,
  inventory_quantity integer not null default 0,
  units_sold integer not null default 0,
  revenue_to_date numeric(14, 2) not null default 0,
  average_rating supasheet.RATING,
  review_count integer not null default 0,
  published_at timestamptz,
  seo_title varchar(200),
  seo_description varchar(400),
  tags varchar(500) [],
  color supasheet.COLOR,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint products_price_non_negative check (price >= 0),
  constraint products_compare_price_higher check (
    compare_at_price is null
    or compare_at_price >= price
  ),
  constraint products_tax_rate_range check (
    tax_rate >= 0
    and tax_rate <= 100
  ),
  constraint products_weight_non_negative check (
    weight_grams is null
    or weight_grams >= 0
  )
);

comment on column store.products.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "active": {"variant": "success", "icon": "CircleCheck"},
        "archived": {"variant": "warning", "icon": "Archive"}
    }
}';

comment on column store.products.product_type is '{
    "progress": false,
    "values": {
        "simple": {"variant": "default", "icon": "Box"},
        "variant": {"variant": "info", "icon": "Boxes"},
        "digital": {"variant": "secondary", "icon": "Download"},
        "bundle": {"variant": "warning", "icon": "PackagePlus"}
    }
}';

comment on table store.products is '{
    "icon": "Package",
    "collapsible_group": "Catalogue",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "name", "badges": ["status", "product_type", "is_featured"]},
        "tabs": ["product_variants", "inventory_levels", "reviews", "order_items", "product_costs"]
    },
    "views": [
        {
            "id": "gallery",
            "name": "Product Gallery",
            "type": "gallery",
            "cover": "image",
            "title": "name",
            "description": "short_description",
            "badge": "status"
        },
        {
            "id": "kanban",
            "name": "Catalogue Pipeline",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "short_description",
            "date": "published_at",
            "badge": "product_type"
        },
        {
            "id": "list",
            "name": "All Products",
            "type": "list",
            "title": "name",
            "description": "short_description",
            "field_1": "price",
            "field_2": "inventory_quantity"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "drafts", "name": "Drafts", "filters": [{"id": "status", "value": "draft", "operator": "eq"}]},
        {"id": "featured", "name": "Featured", "filters": [{"id": "is_featured", "value": "true", "operator": "eq"}]},
        {"id": "out_of_stock", "name": "Out Of Stock", "filters": [{"id": "inventory_quantity", "value": "0", "operator": "lte"}]},
        {"id": "on_sale", "name": "On Sale", "filters": [{"id": "compare_at_price", "value": "null", "operator": "not.is"}]}
    ],
    "links": [
        {"id": "product_report", "name": "Product Performance", "url": "/store/report/product_performance_report", "icon": "BarChart3", "description": "Units, revenue, margin and rating per product"},
        {"id": "inventory_report", "name": "Inventory", "url": "/store/report/inventory_report", "icon": "Boxes", "description": "Stock on hand, reserved and below reorder point"}
    ],
    "fields": {
        "quick_create": ["name", "brand_id", "category_id", "price"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "slug", "brand_id", "category_id", "product_type"]},
            {"id": "media", "title": "Media", "fields": ["image", "gallery"]},
            {"id": "copy", "title": "Copy", "fields": ["short_description", "description"]},
            {"id": "pricing", "title": "Pricing", "fields": ["price", "compare_at_price", "currency", "tax_rate"]},
            {"id": "shipping", "title": "Shipping", "fields": ["requires_shipping", "weight_grams"]},
            {"id": "options", "title": "Variant options", "fields": ["option_1_name", "option_2_name", "option_3_name"]},
            {"id": "publishing", "title": "Publishing", "fields": ["status", "is_featured", "published_at"]},
            {"id": "performance", "title": "Performance", "fields": {"read": ["variant_count", "inventory_quantity", "units_sold", "revenue_to_date", "average_rating", "review_count"]}},
            {"id": "seo", "title": "SEO", "collapsible": true, "fields": ["seo_title", "seo_description", "tags", "color"]}
        ],
        "behavior": {
            "option_1_name": {"visible": [{"id": "product_type", "operator": "eq", "value": "variant"}]},
            "option_2_name": {"visible": [{"id": "product_type", "operator": "eq", "value": "variant"}]},
            "option_3_name": {"visible": [{"id": "product_type", "operator": "eq", "value": "variant"}]},
            "weight_grams": {
                "visible": [{"id": "requires_shipping", "operator": "eq", "value": "true"}],
                "required": [{"id": "requires_shipping", "operator": "eq", "value": "true"}]
            },
            "published_at": {"visible": [{"id": "status", "operator": "in", "value": ["active", "archived"]}]},
            "slug": {"read_only": [{"id": "status", "operator": "eq", "value": "active"}]}
        },
        "lookups": {
            "category_id": {"fill": [{"source_column": "tax_rate", "target_column": "default_tax_rate"}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "brands", "on": "brand_id", "columns": ["name", "logo"]},
            {"table": "categories", "on": "category_id", "columns": ["name", "slug"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column store.products.image is '{"accept": "image/*", "max_size": 5242880}';

comment on column store.products.gallery is '{"accept": "image/*", "max_files": 8, "max_size": 5242880}';

comment on column store.products.price is '{"aggregate": "avg"}';

comment on column store.products.inventory_quantity is '{"name": "In Stock", "aggregate": "sum"}';

comment on column store.products.units_sold is '{"name": "Units Sold", "aggregate": "sum"}';

comment on column store.products.revenue_to_date is '{"name": "Revenue", "aggregate": "sum"}';

comment on column store.products.average_rating is '{"name": "Rating", "aggregate": "avg"}';

revoke all on table store.products
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
delete on table store.products to "x-admin";

grant
select
,
  insert,
update on table store.products to "merchandiser";

grant
select
  on table store.products to "fulfillment",
  "support",
  "user";

-- Case-insensitive dedupe on the shopper-facing name.
create unique index idx_store_products_name_unique on store.products (lower(name));

create index idx_store_products_brand_id on store.products (brand_id);

create index idx_store_products_category_id on store.products (category_id);

create index idx_store_products_status on store.products (status);

create index idx_store_products_created_at on store.products (created_at desc);

-- The storefront only ever asks for active products, newest first.
create index idx_store_products_storefront on store.products (category_id, created_at desc)
where
  status = 'active';

alter table store.products enable row level security;

-- Shoppers see the published catalogue; staff see everything,
-- including drafts and archived lines.
create policy products_select on store.products for
select
  to authenticated using (
    status = 'active'
    or store.is_store_staff ()
  );

create policy products_insert on store.products for insert to authenticated
with
  check (true);

create policy products_update on store.products
for update
  to authenticated using (true)
with
  check (true);

create policy products_delete on store.products for delete to authenticated using (true);

----------------------------------------------------------------
-- Product costs (1:1 extension — margin data lives here rather
-- than on the product, because a column-level SELECT grant would
-- break `select *` for every role missing that one column. Granted
-- to the owner and merchandising only.)
----------------------------------------------------------------
create table store.product_costs (
  id uuid primary key default extensions.uuid_generate_v4 (),
  product_id uuid not null references store.products (id) on delete cascade,
  unit_cost numeric(12, 2) not null default 0,
  last_purchase_price numeric(12, 2),
  margin_percent supasheet.PERCENTAGE,
  supplier_name varchar(200),
  supplier_sku varchar(80),
  lead_time_days integer not null default 14,
  minimum_order_quantity integer not null default 1,
  currency varchar(3) not null default 'USD',
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (product_id),
  constraint product_costs_non_negative check (
    unit_cost >= 0
    and lead_time_days >= 0
    and minimum_order_quantity > 0
  )
);

comment on table store.product_costs is '{
    "icon": "Calculator",
    "name": "Cost & Supply",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "product", "title": "Product", "fields": ["product_id", "currency"]},
            {"id": "cost", "title": "Cost", "fields": ["unit_cost", "last_purchase_price"]},
            {"id": "margin", "title": "Margin", "fields": {"read": ["margin_percent"]}},
            {"id": "supply", "title": "Supply", "fields": ["supplier_name", "supplier_sku", "lead_time_days", "minimum_order_quantity"]},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "join": [{"table": "products", "on": "product_id", "columns": ["name", "price", "status"]}]
    }
}';

comment on column store.product_costs.unit_cost is '{"name": "Unit Cost", "aggregate": "avg"}';

comment on column store.product_costs.margin_percent is '{"name": "Margin", "aggregate": "avg"}';

revoke all on table store.product_costs
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
delete on table store.product_costs to "x-admin";

grant
select
,
  insert,
update on table store.product_costs to "merchandiser";

create index idx_store_product_costs_product_id on store.product_costs (product_id);

alter table store.product_costs enable row level security;

create policy product_costs_select on store.product_costs for
select
  to authenticated using (true);

create policy product_costs_insert on store.product_costs for insert to authenticated
with
  check (true);

create policy product_costs_update on store.product_costs
for update
  to authenticated using (true)
with
  check (true);

create policy product_costs_delete on store.product_costs for delete to authenticated using (true);

----------------------------------------------------------------
-- Product variants (the thing that actually has a SKU and stock)
----------------------------------------------------------------
create table store.product_variants (
  id uuid primary key default extensions.uuid_generate_v4 (),
  product_id uuid not null references store.products (id) on delete cascade,
  sku varchar(80) not null,
  name varchar(255),
  option_1 varchar(80),
  option_2 varchar(80),
  option_3 varchar(80),
  price numeric(12, 2) not null default 0,
  compare_at_price numeric(12, 2),
  barcode varchar(80),
  weight_grams integer,
  image supasheet.file,
  is_default boolean not null default false,
  is_active boolean not null default true,
  inventory_quantity integer not null default 0,
  reserved_quantity integer not null default 0,
  position integer not null default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint variants_price_non_negative check (price >= 0),
  constraint variants_compare_price_higher check (
    compare_at_price is null
    or compare_at_price >= price
  )
);

comment on table store.product_variants is '{
    "icon": "Boxes",
    "name": "Variants",
    "collapsible_group": "Catalogue",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {
        "header": {"title": "sku", "badges": ["is_default", "is_active"]},
        "tabs": ["inventory_levels", "order_items", "inventory_movements"]
    },
    "views": [
        {
            "id": "list",
            "name": "All Variants",
            "type": "list",
            "title": "sku",
            "description": "name",
            "field_1": "price",
            "field_2": "inventory_quantity"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "out_of_stock", "name": "Out Of Stock", "filters": [{"id": "inventory_quantity", "value": "0", "operator": "lte"}]}
    ],
    "fields": {
        "quick_create": ["product_id", "sku", "price"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["product_id", "sku", "name", "barcode", "image"]},
            {"id": "options", "title": "Options", "fields": ["option_1", "option_2", "option_3", "position"]},
            {"id": "pricing", "title": "Pricing", "fields": ["price", "compare_at_price"]},
            {"id": "logistics", "title": "Logistics", "fields": ["weight_grams", "is_default", "is_active"]},
            {"id": "stock", "title": "Stock", "fields": {"read": ["inventory_quantity", "reserved_quantity"]}}
        ],
        "lookups": {
            "product_id": {
                "fill": [
                    {"source_column": "price", "target_column": "price"},
                    {"source_column": "weight_grams", "target_column": "weight_grams"}
                ]
            }
        }
    },
    "query": {
        "sort": [{"id": "position", "desc": false}],
        "join": [{"table": "products", "on": "product_id", "columns": ["name", "status", "image"]}]
    }
}';

comment on column store.product_variants.image is '{"accept": "image/*", "max_size": 5242880}';

comment on column store.product_variants.price is '{"aggregate": "avg"}';

comment on column store.product_variants.inventory_quantity is '{"name": "On Hand", "aggregate": "sum"}';

comment on column store.product_variants.reserved_quantity is '{"name": "Reserved", "aggregate": "sum"}';

revoke all on table store.product_variants
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
delete on table store.product_variants to "x-admin";

grant
select
,
  insert,
update on table store.product_variants to "merchandiser";

grant
select
  on table store.product_variants to "fulfillment",
  "support",
  "user";

-- A SKU identifies exactly one sellable thing, case-insensitively.
create unique index idx_store_variants_sku_unique on store.product_variants (upper(sku));

-- One row per option combination within a product.
create unique index idx_store_variants_options_unique on store.product_variants (
  product_id,
  coalesce(option_1, ''),
  coalesce(option_2, ''),
  coalesce(option_3, '')
);

-- At most one default variant per product.
create unique index idx_store_variants_default_unique on store.product_variants (product_id)
where
  is_default;

create index idx_store_variants_product_id on store.product_variants (product_id);

create index idx_store_variants_is_active on store.product_variants (is_active);

alter table store.product_variants enable row level security;

create policy variants_select on store.product_variants for
select
  to authenticated using (true);

create policy variants_insert on store.product_variants for insert to authenticated
with
  check (true);

create policy variants_update on store.product_variants
for update
  to authenticated using (true)
with
  check (true);

create policy variants_delete on store.product_variants for delete to authenticated using (true);

----------------------------------------------------------------
-- Warehouses
----------------------------------------------------------------
create table store.warehouses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(160) not null,
  address_line_1 varchar(200),
  address_line_2 varchar(200),
  city varchar(120),
  region varchar(120),
  postal_code varchar(40),
  country varchar(120) not null default 'United States',
  contact_email supasheet.EMAIL,
  contact_phone supasheet.TEL,
  is_active boolean not null default true,
  is_default boolean not null default false,
  fulfillment_priority integer not null default 10,
  handling_time supasheet.DURATION not null default 86400000,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table store.warehouses is '{
    "icon": "Warehouse",
    "collapsible_group": "Inventory",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["country", "is_active"]},
        "tabs": ["inventory_levels", "shipments", "inventory_movements"]
    },
    "views": [
        {
            "id": "list",
            "name": "All Warehouses",
            "type": "list",
            "title": "name",
            "description": "city",
            "field_1": "code",
            "field_2": "fulfillment_priority"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "links": [
        {"id": "inventory_report", "name": "Inventory Report", "url": "/store/report/inventory_report", "icon": "Boxes", "description": "Stock position across every location"}
    ],
    "fields": {
        "quick_create": ["code", "name", "city", "country"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "is_active", "is_default"]},
            {"id": "address", "title": "Address", "fields": ["address_line_1", "address_line_2", "city", "region", "postal_code", "country"]},
            {"id": "contact", "title": "Contact", "fields": ["contact_email", "contact_phone"]},
            {"id": "fulfillment", "title": "Fulfillment", "fields": ["fulfillment_priority", "handling_time"]}
        ]
    },
    "query": {
        "sort": [{"id": "fulfillment_priority", "desc": false}]
    }
}';

comment on column store.warehouses.handling_time is '{"name": "Handling Time", "aggregate": "avg"}';

revoke all on table store.warehouses
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
delete on table store.warehouses to "x-admin";

grant
select
,
  insert,
update on table store.warehouses to "fulfillment";

grant
select
  on table store.warehouses to "merchandiser",
  "support";

-- Exactly one default location.
create unique index idx_store_warehouses_default_unique on store.warehouses (is_default)
where
  is_default;

create index idx_store_warehouses_is_active on store.warehouses (is_active);

alter table store.warehouses enable row level security;

create policy warehouses_select on store.warehouses for
select
  to authenticated using (true);

create policy warehouses_insert on store.warehouses for insert to authenticated
with
  check (true);

create policy warehouses_update on store.warehouses
for update
  to authenticated using (true)
with
  check (true);

create policy warehouses_delete on store.warehouses for delete to authenticated using (true);

----------------------------------------------------------------
-- Inventory levels (one row per variant per location — the current
-- stock position, maintained by the movement ledger below)
----------------------------------------------------------------
create table store.inventory_levels (
  id uuid primary key default extensions.uuid_generate_v4 (),
  variant_id uuid not null references store.product_variants (id) on delete cascade,
  warehouse_id uuid not null references store.warehouses (id) on delete cascade,
  on_hand integer not null default 0,
  reserved integer not null default 0,
  available integer not null default 0,
  reorder_point integer not null default 0,
  reorder_quantity integer not null default 0,
  bin_location varchar(60),
  is_below_reorder_point boolean not null default false,
  last_counted_at timestamptz,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (variant_id, warehouse_id),
  constraint inventory_on_hand_non_negative check (on_hand >= 0),
  constraint inventory_reserved_non_negative check (reserved >= 0),
  -- You cannot reserve stock you do not have. The order triggers
  -- raise a readable error long before this constraint fires, but
  -- the constraint is what makes overselling actually impossible.
  constraint inventory_reserved_within_on_hand check (reserved <= on_hand),
  constraint inventory_reorder_non_negative check (
    reorder_point >= 0
    and reorder_quantity >= 0
  )
);

comment on table store.inventory_levels is '{
    "icon": "Boxes",
    "name": "Inventory",
    "collapsible_group": "Inventory",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {
        "header": {"title": "bin_location", "badges": ["is_below_reorder_point"]},
        "tabs": ["inventory_movements"]
    },
    "views": [
        {
            "id": "list",
            "name": "Stock Position",
            "type": "list",
            "title": "bin_location",
            "description": "variant_id",
            "field_1": "available",
            "field_2": "on_hand"
        }
    ],
    "filter_presets": [
        {"id": "low", "name": "Below Reorder Point", "filters": [{"id": "is_below_reorder_point", "value": "true", "operator": "eq"}]},
        {"id": "out", "name": "Out Of Stock", "filters": [{"id": "available", "value": "0", "operator": "lte"}]},
        {"id": "reserved", "name": "Has Reservations", "filters": [{"id": "reserved", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["variant_id", "warehouse_id", "reorder_point"],
        "sections": [
            {"id": "where", "title": "Location", "fields": ["variant_id", "warehouse_id", "bin_location"]},
            {"id": "policy", "title": "Replenishment", "fields": ["reorder_point", "reorder_quantity"]},
            {"id": "position", "title": "Position", "fields": {"read": ["on_hand", "reserved", "available", "is_below_reorder_point", "last_counted_at"]}}
        ]
    },
    "query": {
        "sort": [{"id": "available", "desc": false}],
        "join": [
            {"table": "product_variants", "on": "variant_id", "columns": ["sku", "name", "price"]},
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column store.inventory_levels.on_hand is '{"name": "On Hand", "aggregate": "sum"}';

comment on column store.inventory_levels.reserved is '{"aggregate": "sum"}';

comment on column store.inventory_levels.available is '{"aggregate": "sum"}';

revoke all on table store.inventory_levels
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
delete on table store.inventory_levels to "x-admin";

-- Operations set the replenishment policy; the quantities themselves
-- only ever move through the ledger.
grant
select
,
  insert,
update on table store.inventory_levels to "fulfillment";

grant
select
  on table store.inventory_levels to "merchandiser",
  "support";

create index idx_store_inventory_levels_variant_id on store.inventory_levels (variant_id);

create index idx_store_inventory_levels_warehouse_id on store.inventory_levels (warehouse_id);

-- The replenishment queue: what to reorder, worst first.
create index idx_store_inventory_levels_low on store.inventory_levels (warehouse_id, available)
where
  is_below_reorder_point;

alter table store.inventory_levels enable row level security;

create policy inventory_levels_select on store.inventory_levels for
select
  to authenticated using (true);

create policy inventory_levels_insert on store.inventory_levels for insert to authenticated
with
  check (true);

create policy inventory_levels_update on store.inventory_levels
for update
  to authenticated using (true)
with
  check (true);

create policy inventory_levels_delete on store.inventory_levels for delete to authenticated using (true);

----------------------------------------------------------------
-- Inventory movements (append-only ledger)
--
-- Every change in stock is a row here, and stock levels are derived
-- from it — never edited directly. That is why no role holds UPDATE
-- or DELETE on this table, including the owner: a correction is a
-- new movement, not a rewritten one.
----------------------------------------------------------------
create table store.inventory_movements (
  id uuid primary key default extensions.uuid_generate_v4 (),
  variant_id uuid not null references store.product_variants (id) on delete cascade,
  warehouse_id uuid not null references store.warehouses (id) on delete cascade,
  movement_type store.movement_type not null default 'adjustment',
  quantity integer not null,
  unit_cost numeric(12, 2),
  reference varchar(80),
  note varchar(500),
  occurred_at timestamptz not null default current_timestamp,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  constraint movements_quantity_not_zero check (quantity <> 0),
  -- The sign has to agree with the reason: goods in are positive,
  -- goods out are negative, and only a correction may be either.
  constraint movements_sign_matches_type check (
    (
      movement_type in ('receipt', 'return', 'transfer_in')
      and quantity > 0
    )
    or (
      movement_type in ('sale', 'damage', 'transfer_out')
      and quantity < 0
    )
    or movement_type in ('adjustment', 'stocktake')
  )
);

comment on column store.inventory_movements.movement_type is '{
    "progress": false,
    "values": {
        "receipt": {"variant": "success", "icon": "PackageCheck"},
        "sale": {"variant": "info", "icon": "ShoppingCart"},
        "return": {"variant": "warning", "icon": "Undo2"},
        "adjustment": {"variant": "secondary", "icon": "Pencil"},
        "transfer_in": {"variant": "success", "icon": "ArrowDownToLine"},
        "transfer_out": {"variant": "warning", "icon": "ArrowUpFromLine"},
        "damage": {"variant": "destructive", "icon": "PackageX"},
        "stocktake": {"variant": "default", "icon": "ClipboardCheck"}
    }
}';

comment on table store.inventory_movements is '{
    "icon": "ArrowRightLeft",
    "name": "Stock Ledger",
    "collapsible_group": "Inventory",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "reference", "badges": ["movement_type"]}},
    "views": [
        {
            "id": "list",
            "name": "Ledger",
            "type": "list",
            "title": "reference",
            "description": "note",
            "field_1": "movement_type",
            "field_2": "quantity"
        },
        {
            "id": "calendar",
            "name": "By Day",
            "type": "calendar",
            "title": "reference",
            "badge": "movement_type",
            "start_date": "occurred_at",
            "read_only": true
        }
    ],
    "filter_presets": [
        {"id": "receipts", "name": "Goods In", "filters": [{"id": "movement_type", "value": ["receipt", "return", "transfer_in"], "operator": "in"}]},
        {"id": "issues", "name": "Goods Out", "filters": [{"id": "movement_type", "value": ["sale", "damage", "transfer_out"], "operator": "in"}]},
        {"id": "corrections", "name": "Corrections", "filters": [{"id": "movement_type", "value": ["adjustment", "stocktake"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["variant_id", "warehouse_id", "movement_type", "quantity"],
        "sections": [
            {"id": "what", "title": "What moved", "fields": ["variant_id", "warehouse_id", "movement_type", "quantity"]},
            {"id": "why", "title": "Why", "fields": ["reference", "note", "unit_cost", "occurred_at"]}
        ],
        "behavior": {
            "unit_cost": {"visible": [{"id": "movement_type", "operator": "in", "value": ["receipt", "transfer_in"]}]}
        }
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [
            {"table": "product_variants", "on": "variant_id", "columns": ["sku", "name"]},
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column store.inventory_movements.quantity is '{"aggregate": "sum"}';

revoke all on table store.inventory_movements
from
  public,
  anon,
  authenticated,
  service_role;

-- Append-only: select and insert, for everyone who holds it at all.
grant
select
,
  insert on table store.inventory_movements to "x-admin",
  "fulfillment";

grant
select
  on table store.inventory_movements to "merchandiser",
  "support";

create index idx_store_movements_variant_id on store.inventory_movements (variant_id);

create index idx_store_movements_warehouse_id on store.inventory_movements (warehouse_id);

create index idx_store_movements_occurred_at on store.inventory_movements (occurred_at desc);

create index idx_store_movements_type on store.inventory_movements (movement_type);

alter table store.inventory_movements enable row level security;

create policy inventory_movements_select on store.inventory_movements for
select
  to authenticated using (true);

create policy inventory_movements_insert on store.inventory_movements for insert to authenticated
with
  check (true);

----------------------------------------------------------------
-- Customers
--
-- user_id is what makes the "user" role a shopper rather than an
-- operator: it links a customer record to a login, and every
-- customer-scoped policy below resolves through it.
----------------------------------------------------------------
create table store.customers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  email supasheet.EMAIL not null,
  first_name varchar(120) not null,
  last_name varchar(120) not null,
  name varchar(255),
  phone supasheet.TEL,
  avatar supasheet.AVATAR,
  customer_group store.customer_group not null default 'registered',
  status store.customer_status not null default 'active',
  accepts_marketing boolean not null default false,
  marketing_opt_in_at timestamptz,
  date_of_birth date,
  country varchar(120),
  preferred_currency varchar(3) not null default 'USD',
  order_count integer not null default 0,
  total_spent numeric(14, 2) not null default 0,
  average_order_value numeric(12, 2) not null default 0,
  first_order_at timestamptz,
  last_order_at timestamptz,
  tags varchar(500) [],
  notes text,
  user_id uuid references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column store.customers.customer_group is '{
    "progress": true,
    "values": {
        "guest": {"variant": "secondary", "icon": "UserRound"},
        "registered": {"variant": "info", "icon": "UserCheck"},
        "member": {"variant": "default", "icon": "BadgeCheck"},
        "vip": {"variant": "warning", "icon": "Crown"},
        "wholesale": {"variant": "success", "icon": "Building2"}
    }
}';

comment on column store.customers.status is '{
    "progress": false,
    "values": {
        "active": {"variant": "success", "icon": "CircleCheck"},
        "inactive": {"variant": "secondary", "icon": "Moon"},
        "blocked": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table store.customers is '{
    "icon": "Users",
    "collapsible_group": "Customers",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["customer_group", "status"]},
        "tabs": ["orders", "addresses", "reviews", "return_requests"]
    },
    "views": [
        {
            "id": "list",
            "name": "All Customers",
            "type": "list",
            "title": "name",
            "description": "email",
            "field_1": "customer_group",
            "field_2": "total_spent"
        },
        {
            "id": "kanban",
            "name": "By Segment",
            "type": "kanban",
            "group": "customer_group",
            "title": "name",
            "description": "email",
            "date": "last_order_at",
            "badge": "status"
        },
        {
            "id": "gallery",
            "name": "Directory",
            "type": "gallery",
            "cover": "avatar",
            "title": "name",
            "description": "email",
            "badge": "customer_group"
        }
    ],
    "filter_presets": [
        {"id": "vip", "name": "VIP & Wholesale", "filters": [{"id": "customer_group", "value": ["vip", "wholesale"], "operator": "in"}]},
        {"id": "marketing", "name": "Marketable", "filters": [{"id": "accepts_marketing", "value": "true", "operator": "eq"}]},
        {"id": "repeat", "name": "Repeat Buyers", "filters": [{"id": "order_count", "value": "1", "operator": "gt"}]},
        {"id": "blocked", "name": "Blocked", "filters": [{"id": "status", "value": "blocked", "operator": "eq"}]}
    ],
    "links": [
        {"id": "customer_report", "name": "Customer Report", "url": "/store/report/customer_report", "icon": "FileText", "description": "Spend, frequency and recency per customer"}
    ],
    "fields": {
        "quick_create": ["first_name", "last_name", "email", "customer_group"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["first_name", "last_name", "email", "phone", "avatar"]},
            {"id": "segment", "title": "Segment", "fields": ["customer_group", "status", "country", "preferred_currency"]},
            {"id": "marketing", "title": "Marketing", "fields": ["accepts_marketing", "marketing_opt_in_at", "date_of_birth"]},
            {"id": "account", "title": "Account", "fields": ["user_id", "default_shipping_address_id", "default_billing_address_id"]},
            {"id": "value", "title": "Lifetime value", "fields": {"read": ["order_count", "total_spent", "average_order_value", "first_order_at", "last_order_at"]}},
            {"id": "extras", "title": "Notes & tags", "collapsible": true, "fields": ["notes", "tags"]}
        ],
        "behavior": {
            "marketing_opt_in_at": {"visible": [{"id": "accepts_marketing", "operator": "eq", "value": "true"}]}
        },
        "lookups": {
            "default_shipping_address_id": {"filter": [{"source_column": "id", "target_column": "customer_id"}]},
            "default_billing_address_id": {"filter": [{"source_column": "id", "target_column": "customer_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [{"table": "users", "on": "user_id", "columns": ["name", "email"]}]
    }
}';

comment on column store.customers.avatar is '{"accept": "image/*", "max_size": 2097152}';

comment on column store.customers.total_spent is '{"name": "Lifetime Spend", "aggregate": "sum"}';

comment on column store.customers.average_order_value is '{"name": "AOV", "aggregate": "avg"}';

comment on column store.customers.order_count is '{"name": "Orders", "aggregate": "sum"}';

revoke all on table store.customers
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
delete on table store.customers to "x-admin";

grant
select
,
  insert,
update on table store.customers to "fulfillment",
"support";

grant
select
  on table store.customers to "merchandiser";

-- A shopper may keep their own contact details current.
grant
select
  on table store.customers to "user";

grant
update (
  first_name,
  last_name,
  phone,
  avatar,
  accepts_marketing,
  country,
  preferred_currency
) on table store.customers to "user";

-- One account per address, case-insensitively.
create unique index idx_store_customers_email_unique on store.customers (lower(email));

-- One customer record per login.
create unique index idx_store_customers_user_unique on store.customers (user_id)
where
  user_id is not null;

create index idx_store_customers_group on store.customers (customer_group);

create index idx_store_customers_status on store.customers (status);

create index idx_store_customers_created_at on store.customers (created_at desc);

alter table store.customers enable row level security;

-- A shopper sees exactly one customer record: their own.
create policy customers_select on store.customers for
select
  to authenticated using (
    store.is_store_staff ()
    or user_id = (
      select
        auth.uid ()
    )
  );

create policy customers_insert on store.customers for insert to authenticated
with
  check (true);

create policy customers_update on store.customers
for update
  to authenticated using (
    store.is_store_staff ()
    or user_id = (
      select
        auth.uid ()
    )
  )
with
  check (true);

create policy customers_delete on store.customers for delete to authenticated using (true);

----------------------------------------------------------------
-- Shopper helper
--
-- "Which customer record is this login?" Same reasoning as the CRM
-- module's current_rep_id: a STABLE SECURITY DEFINER function is
-- evaluated once per statement, does not recurse into the policy it
-- is used by, and leaves the policy as an indexable equality.
----------------------------------------------------------------
create or replace function store.current_customer_id () returns uuid language sql stable security definer
set
  search_path = '' as $$
  select id
  from store.customers
  where user_id = auth.uid ()
  limit 1;
$$;

revoke all on function store.current_customer_id ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.current_customer_id () to "x-admin",
"merchandiser",
"fulfillment",
"support",
"user";

----------------------------------------------------------------
-- Addresses
----------------------------------------------------------------
create table store.addresses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  customer_id uuid not null references store.customers (id) on delete cascade,
  address_type store.address_type not null default 'shipping',
  label varchar(60),
  first_name varchar(120) not null,
  last_name varchar(120) not null,
  company varchar(160),
  address_line_1 varchar(200) not null,
  address_line_2 varchar(200),
  city varchar(120) not null,
  region varchar(120),
  postal_code varchar(40),
  country varchar(120) not null,
  phone supasheet.TEL,
  delivery_instructions varchar(500),
  is_default boolean not null default false,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table store.addresses is '{
    "icon": "MapPin",
    "collapsible_group": "Customers",
    "display": "none",
    "inline_form": true,
    "fields": {
        "sections": [
            {"id": "who", "title": "Recipient", "fields": ["customer_id", "address_type", "label", "first_name", "last_name", "company", "phone"]},
            {"id": "where", "title": "Address", "fields": ["address_line_1", "address_line_2", "city", "region", "postal_code", "country"]},
            {"id": "extras", "title": "Delivery", "collapsible": true, "fields": ["delivery_instructions", "is_default"]}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [{"table": "customers", "on": "customer_id", "columns": ["name", "email"]}]
    }
}';

revoke all on table store.addresses
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
delete on table store.addresses to "x-admin";

grant
select
,
  insert,
update on table store.addresses to "fulfillment",
"support";

grant
select
,
  insert,
update,
delete on table store.addresses to "user";

-- One default per address type per customer.
create unique index idx_store_addresses_default_unique on store.addresses (customer_id, address_type)
where
  is_default;

create index idx_store_addresses_customer_id on store.addresses (customer_id);

alter table store.addresses enable row level security;

create policy addresses_select on store.addresses for
select
  to authenticated using (
    store.is_store_staff ()
    or customer_id = store.current_customer_id ()
  );

create policy addresses_insert on store.addresses for insert to authenticated
with
  check (
    store.is_store_staff ()
    or customer_id = store.current_customer_id ()
  );

create policy addresses_update on store.addresses
for update
  to authenticated using (
    store.is_store_staff ()
    or customer_id = store.current_customer_id ()
  )
with
  check (true);

create policy addresses_delete on store.addresses for delete to authenticated using (
  store.is_store_staff ()
  or customer_id = store.current_customer_id ()
);

-- Customers gained default addresses only after the address book
-- existed — adding the FKs afterwards is the normal pattern for a
-- circular reference.
alter table store.customers
add column default_shipping_address_id uuid references store.addresses (id) on delete set null,
add column default_billing_address_id uuid references store.addresses (id) on delete set null;

create index idx_store_customers_default_shipping on store.customers (default_shipping_address_id);

create index idx_store_customers_default_billing on store.customers (default_billing_address_id);

----------------------------------------------------------------
-- Discounts (promotion campaigns — the gantt roadmap)
----------------------------------------------------------------
create table store.discounts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(40) not null,
  name varchar(160) not null,
  description varchar(500),
  discount_type store.discount_type not null default 'percentage',
  status store.discount_status not null default 'scheduled',
  value numeric(12, 2) not null default 0,
  minimum_spend numeric(12, 2) not null default 0,
  usage_limit integer,
  usage_limit_per_customer integer not null default 1,
  used_count integer not null default 0,
  redemption_rate supasheet.PERCENTAGE not null default 0,
  revenue_influenced numeric(14, 2) not null default 0,
  category_id uuid references store.categories (id) on delete set null,
  starts_on date not null default current_date,
  ends_on date not null default (current_date + 30),
  is_active boolean not null default true,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint discounts_dates_ordered check (ends_on >= starts_on),
  constraint discounts_value_non_negative check (value >= 0),
  constraint discounts_percentage_within_bounds check (
    discount_type <> 'percentage'
    or value <= 100
  ),
  constraint discounts_usage_limit_positive check (
    usage_limit is null
    or usage_limit > 0
  )
);

comment on column store.discounts.status is '{
    "progress": true,
    "values": {
        "scheduled": {"variant": "secondary", "icon": "CalendarClock"},
        "active": {"variant": "success", "icon": "Rocket"},
        "paused": {"variant": "warning", "icon": "PauseCircle"},
        "expired": {"variant": "destructive", "icon": "TimerOff"}
    }
}';

comment on column store.discounts.discount_type is '{
    "progress": false,
    "values": {
        "percentage": {"variant": "info", "icon": "Percent"},
        "fixed_amount": {"variant": "default", "icon": "DollarSign"},
        "free_shipping": {"variant": "success", "icon": "Truck"}
    }
}';

comment on table store.discounts is '{
    "icon": "TicketPercent",
    "collapsible_group": "Marketing",
    "display": "block",
    "primary_view": "gantt",
    "detail": {
        "header": {"title": "code", "badges": ["status", "discount_type"]},
        "tabs": ["orders"]
    },
    "views": [
        {
            "id": "gantt",
            "name": "Promotion Calendar",
            "type": "gantt",
            "title": "name",
            "start_date": "starts_on",
            "end_date": "ends_on",
            "group": "status",
            "progress": "redemption_rate",
            "badge": "discount_type"
        },
        {
            "id": "kanban",
            "name": "By Status",
            "type": "kanban",
            "group": "status",
            "title": "code",
            "description": "name",
            "date": "ends_on",
            "badge": "discount_type"
        },
        {
            "id": "list",
            "name": "All Discounts",
            "type": "list",
            "title": "code",
            "description": "name",
            "field_1": "status",
            "field_2": "used_count"
        }
    ],
    "filter_presets": [
        {"id": "live", "name": "Live", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "upcoming", "name": "Scheduled", "filters": [{"id": "status", "value": "scheduled", "operator": "eq"}]},
        {"id": "exhausted", "name": "Exhausted", "filters": [{"id": "redemption_rate", "value": "100", "operator": "gte"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "discount_type", "value"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "category_id"]},
            {"id": "offer", "title": "Offer", "fields": ["discount_type", "value", "minimum_spend"]},
            {"id": "limits", "title": "Limits", "fields": ["usage_limit", "usage_limit_per_customer"]},
            {"id": "schedule", "title": "Schedule", "fields": ["status", "starts_on", "ends_on", "is_active", "color"]},
            {"id": "results", "title": "Results", "fields": {"read": ["used_count", "redemption_rate", "revenue_influenced"]}}
        ],
        "behavior": {
            "value": {"visible": [{"id": "discount_type", "operator": "not.eq", "value": "free_shipping"}]},
            "usage_limit_per_customer": {"visible": [{"id": "usage_limit", "operator": "not.is", "value": "null"}]}
        }
    },
    "query": {
        "sort": [{"id": "starts_on", "desc": true}],
        "join": [{"table": "categories", "on": "category_id", "columns": ["name", "slug"]}]
    }
}';

comment on column store.discounts.used_count is '{"name": "Redemptions", "aggregate": "sum"}';

comment on column store.discounts.revenue_influenced is '{"name": "Revenue", "aggregate": "sum"}';

comment on column store.discounts.redemption_rate is '{"name": "Redeemed", "aggregate": "avg"}';

revoke all on table store.discounts
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
delete on table store.discounts to "x-admin";

grant
select
,
  insert,
update on table store.discounts to "merchandiser";

grant
select
  on table store.discounts to "fulfillment",
  "support";

-- Codes are matched case-insensitively at checkout, so they have to
-- be unique that way too.
create unique index idx_store_discounts_code_unique on store.discounts (upper(code));

create index idx_store_discounts_status on store.discounts (status);

create index idx_store_discounts_window on store.discounts (starts_on, ends_on);

alter table store.discounts enable row level security;

create policy discounts_select on store.discounts for
select
  to authenticated using (true);

create policy discounts_insert on store.discounts for insert to authenticated
with
  check (true);

create policy discounts_update on store.discounts
for update
  to authenticated using (true)
with
  check (true);

create policy discounts_delete on store.discounts for delete to authenticated using (true);

----------------------------------------------------------------
-- Orders (the core resource)
--
-- customer_id is ON DELETE RESTRICT: deleting a customer who has
-- ordered should fail loudly rather than quietly destroy the sales
-- history. Every money column is a rollup of the line items,
-- payments and returns below.
----------------------------------------------------------------
create sequence if not exists store.order_number_seq;

create table store.orders (
  id uuid primary key default extensions.uuid_generate_v4 (),
  order_number varchar(30) not null unique default (
    'ORD-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('store.order_number_seq')::text, 5, '0')
  ),
  customer_id uuid not null references store.customers (id) on delete restrict,
  email supasheet.EMAIL not null,
  status store.order_status not null default 'pending',
  payment_status store.payment_status not null default 'unpaid',
  fulfillment_status store.fulfillment_status not null default 'unfulfilled',
  channel store.sales_channel not null default 'web',
  currency varchar(3) not null default 'USD',
  item_count integer not null default 0,
  subtotal numeric(14, 2) not null default 0,
  discount_total numeric(14, 2) not null default 0,
  shipping_total numeric(14, 2) not null default 0,
  tax_total numeric(14, 2) not null default 0,
  grand_total numeric(14, 2) not null default 0,
  paid_total numeric(14, 2) not null default 0,
  refunded_total numeric(14, 2) not null default 0,
  discount_id uuid references store.discounts (id) on delete set null,
  shipping_address_id uuid references store.addresses (id) on delete set null,
  billing_address_id uuid references store.addresses (id) on delete set null,
  shipping_method varchar(120),
  requested_delivery_on date,
  customer_note text,
  staff_note text,
  placed_at timestamptz not null default current_timestamp,
  confirmed_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason varchar(500),
  tags varchar(500) [],
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint orders_money_non_negative check (
    subtotal >= 0
    and discount_total >= 0
    and shipping_total >= 0
    and tax_total >= 0
    and grand_total >= 0
    and paid_total >= 0
    and refunded_total >= 0
  ),
  constraint orders_refund_within_paid check (refunded_total <= paid_total)
);

comment on column store.orders.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "secondary", "icon": "Hourglass"},
        "confirmed": {"variant": "info", "icon": "CircleCheck"},
        "processing": {"variant": "default", "icon": "PackageSearch"},
        "completed": {"variant": "success", "icon": "PackageCheck"},
        "cancelled": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on column store.orders.payment_status is '{
    "progress": true,
    "values": {
        "unpaid": {"variant": "secondary", "icon": "CreditCard"},
        "authorized": {"variant": "info", "icon": "ShieldCheck"},
        "partially_paid": {"variant": "warning", "icon": "CircleDollarSign"},
        "paid": {"variant": "success", "icon": "BadgeDollarSign"},
        "partially_refunded": {"variant": "warning", "icon": "Undo2"},
        "refunded": {"variant": "destructive", "icon": "RotateCcw"},
        "failed": {"variant": "destructive", "icon": "TriangleAlert"}
    }
}';

comment on column store.orders.fulfillment_status is '{
    "progress": true,
    "values": {
        "unfulfilled": {"variant": "secondary", "icon": "Package"},
        "partially_fulfilled": {"variant": "warning", "icon": "PackageOpen"},
        "fulfilled": {"variant": "success", "icon": "PackageCheck"},
        "returned": {"variant": "destructive", "icon": "Undo2"}
    }
}';

comment on column store.orders.channel is '{
    "progress": false,
    "values": {
        "web": {"variant": "info", "icon": "Globe"},
        "mobile_app": {"variant": "default", "icon": "Smartphone"},
        "pos": {"variant": "success", "icon": "Store"},
        "marketplace": {"variant": "warning", "icon": "ShoppingBag"},
        "phone": {"variant": "secondary", "icon": "Phone"}
    }
}';

comment on table store.orders is '{
    "icon": "ShoppingCart",
    "collapsible_group": "Orders",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "order_number", "badges": ["status", "payment_status", "fulfillment_status"]},
        "tabs": ["order_items", "payments", "shipments", "return_requests"],
        "timelines": ["order_events"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Order Pipeline",
            "type": "kanban",
            "group": "status",
            "title": "order_number",
            "description": "email",
            "date": "placed_at",
            "badge": "payment_status"
        },
        {
            "id": "calendar",
            "name": "Order Calendar",
            "type": "calendar",
            "title": "order_number",
            "badge": "status",
            "start_date": "placed_at",
            "read_only": true
        },
        {
            "id": "list",
            "name": "All Orders",
            "type": "list",
            "title": "order_number",
            "description": "email",
            "field_1": "status",
            "field_2": "grand_total"
        }
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["pending", "confirmed", "processing"], "operator": "in"}]},
        {"id": "unpaid", "name": "Awaiting Payment", "filters": [{"id": "payment_status", "value": ["unpaid", "authorized", "partially_paid"], "operator": "in"}]},
        {"id": "to_ship", "name": "To Ship", "filters": [{"id": "fulfillment_status", "value": ["unfulfilled", "partially_fulfilled"], "operator": "in"}]},
        {"id": "refunded", "name": "Refunded", "filters": [{"id": "payment_status", "value": ["refunded", "partially_refunded"], "operator": "in"}]},
        {"id": "cancelled", "name": "Cancelled", "filters": [{"id": "status", "value": "cancelled", "operator": "eq"}]}
    ],
    "links": [
        {"id": "sales_report", "name": "Sales Report", "url": "/store/report/sales_report", "icon": "FileText", "description": "Every order with customer, channel and settlement context"},
        {"id": "returns_report", "name": "Returns", "url": "/store/report/returns_report", "icon": "Undo2", "description": "Return rate and reasons by product"}
    ],
    "fields": {
        "quick_create": ["customer_id", "email", "channel"],
        "sections": [
            {"id": "customer", "title": "Customer", "fields": ["customer_id", "email", "channel"]},
            {"id": "state", "title": "State", "fields": ["status", "payment_status", "fulfillment_status"]},
            {"id": "delivery", "title": "Delivery", "fields": ["shipping_address_id", "billing_address_id", "shipping_method", "requested_delivery_on"]},
            {"id": "money", "title": "Money", "fields": {"create": ["currency", "shipping_total", "discount_id"], "update": ["currency", "shipping_total", "discount_id"], "read": ["currency", "item_count", "subtotal", "discount_total", "shipping_total", "tax_total", "grand_total", "paid_total", "refunded_total"]}},
            {"id": "cancellation", "title": "Cancellation", "fields": ["cancel_reason"]},
            {"id": "timeline", "title": "Timeline", "fields": {"read": ["placed_at", "confirmed_at", "completed_at", "cancelled_at"]}},
            {"id": "notes", "title": "Notes", "collapsible": true, "fields": ["customer_note", "staff_note", "tags"]}
        ],
        "behavior": {
            "cancel_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "cancelled"}],
                "required": [{"id": "status", "operator": "eq", "value": "cancelled"}]
            },
            "shipping_method": {"read_only": [{"id": "fulfillment_status", "operator": "in", "value": ["fulfilled", "returned"]}]},
            "discount_id": {"read_only": [{"id": "status", "operator": "in", "value": ["completed", "cancelled"]}]}
        },
        "lookups": {
            "customer_id": {"fill": [{"source_column": "email", "target_column": "email"}]},
            "shipping_address_id": {"filter": [{"source_column": "customer_id", "target_column": "customer_id"}]},
            "billing_address_id": {"filter": [{"source_column": "customer_id", "target_column": "customer_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "placed_at", "desc": true}],
        "join": [
            {"table": "customers", "on": "customer_id", "columns": ["name", "email", "customer_group"]},
            {"table": "discounts", "on": "discount_id", "columns": ["code", "discount_type"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column store.orders.order_number is '{"name": "Order", "icon": "Hash"}';

comment on column store.orders.grand_total is '{"name": "Total", "aggregate": "sum"}';

comment on column store.orders.subtotal is '{"aggregate": "sum"}';

comment on column store.orders.discount_total is '{"name": "Discount", "aggregate": "sum"}';

comment on column store.orders.refunded_total is '{"name": "Refunded", "aggregate": "sum"}';

comment on column store.orders.item_count is '{"name": "Items", "aggregate": "sum"}';

revoke all on table store.orders
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
delete on table store.orders to "x-admin";

grant
select
,
  insert,
update on table store.orders to "fulfillment";

grant
select
  on table store.orders to "merchandiser";

-- Support can annotate an order and nothing else: the column list is
-- the whole of their write access.
grant
select
  on table store.orders to "support";

grant
update (staff_note, tags) on table store.orders to "support";

grant
select
  on table store.orders to "user";

revoke all on sequence store.order_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence store.order_number_seq to "x-admin",
"fulfillment";

create index idx_store_orders_customer_id on store.orders (customer_id);

create index idx_store_orders_discount_id on store.orders (discount_id);

create index idx_store_orders_status on store.orders (status);

create index idx_store_orders_payment_status on store.orders (payment_status);

create index idx_store_orders_fulfillment_status on store.orders (fulfillment_status);

create index idx_store_orders_placed_at on store.orders (placed_at desc);

-- The two queues the back office lives in.
create index idx_store_orders_open on store.orders (placed_at desc)
where
  status in ('pending', 'confirmed', 'processing');

create index idx_store_orders_to_ship on store.orders (placed_at)
where
  fulfillment_status in ('unfulfilled', 'partially_fulfilled')
  and status <> 'cancelled';

alter table store.orders enable row level security;

-- A shopper sees their own orders and nothing else; staff see the
-- whole book.
create policy orders_select on store.orders for
select
  to authenticated using (
    store.is_store_staff ()
    or customer_id = store.current_customer_id ()
  );

create policy orders_insert on store.orders for insert to authenticated
with
  check (true);

create policy orders_update on store.orders
for update
  to authenticated using (true)
with
  check (true);

create policy orders_delete on store.orders for delete to authenticated using (true);

----------------------------------------------------------------
-- Order items
--
-- The product name and SKU are snapshotted on purpose: renaming a
-- product two years from now must not rewrite what a customer
-- actually bought.
----------------------------------------------------------------
create table store.order_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  order_id uuid not null references store.orders (id) on delete cascade,
  variant_id uuid not null references store.product_variants (id) on delete restrict,
  product_name varchar(255) not null,
  sku varchar(80) not null,
  variant_label varchar(180),
  quantity integer not null default 1,
  unit_price numeric(12, 2) not null default 0,
  discount_amount numeric(12, 2) not null default 0,
  tax_amount numeric(12, 2) not null default 0,
  line_total numeric(14, 2) not null default 0,
  fulfilled_quantity integer not null default 0,
  returned_quantity integer not null default 0,
  position integer not null default 0,
  created_at timestamptz default current_timestamp,
  constraint order_items_quantity_positive check (quantity > 0),
  constraint order_items_money_non_negative check (
    unit_price >= 0
    and discount_amount >= 0
    and tax_amount >= 0
  ),
  constraint order_items_fulfilled_within_quantity check (
    fulfilled_quantity >= 0
    and fulfilled_quantity <= quantity
  ),
  constraint order_items_returned_within_quantity check (
    returned_quantity >= 0
    and returned_quantity <= quantity
  )
);

comment on table store.order_items is '{
    "icon": "Receipt",
    "name": "Order Items",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["order_id", "variant_id", "quantity", "position"]},
            {"id": "pricing", "title": "Pricing", "fields": ["unit_price", "discount_amount", "tax_amount"]},
            {"id": "snapshot", "title": "Snapshot", "fields": {"read": ["product_name", "sku", "variant_label", "line_total"]}},
            {"id": "progress", "title": "Progress", "fields": {"read": ["fulfilled_quantity", "returned_quantity"]}}
        ],
        "lookups": {
            "variant_id": {"fill": [{"source_column": "unit_price", "target_column": "price"}]}
        }
    },
    "query": {
        "sort": [{"id": "position", "desc": false}],
        "join": [
            {"table": "orders", "on": "order_id", "columns": ["order_number", "status"]},
            {"table": "product_variants", "on": "variant_id", "columns": ["sku", "name", "price"]}
        ]
    }
}';

comment on column store.order_items.line_total is '{"name": "Line Total", "aggregate": "sum"}';

comment on column store.order_items.quantity is '{"aggregate": "sum"}';

comment on column store.order_items.returned_quantity is '{"name": "Returned", "aggregate": "sum"}';

revoke all on table store.order_items
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
delete on table store.order_items to "x-admin",
"fulfillment";

grant
select
  on table store.order_items to "merchandiser",
  "support",
  "user";

create index idx_store_order_items_order_id on store.order_items (order_id);

create index idx_store_order_items_variant_id on store.order_items (variant_id);

alter table store.order_items enable row level security;

create policy order_items_select on store.order_items for
select
  to authenticated using (
    store.is_store_staff ()
    or exists (
      select
        1
      from
        store.orders o
      where
        o.id = order_id
        and o.customer_id = store.current_customer_id ()
    )
  );

create policy order_items_insert on store.order_items for insert to authenticated
with
  check (true);

create policy order_items_update on store.order_items
for update
  to authenticated using (true)
with
  check (true);

create policy order_items_delete on store.order_items for delete to authenticated using (true);

----------------------------------------------------------------
-- Payments
----------------------------------------------------------------
create table store.payments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  order_id uuid not null references store.orders (id) on delete cascade,
  method store.payment_method not null default 'card',
  state store.payment_state not null default 'pending',
  amount numeric(14, 2) not null default 0,
  currency varchar(3) not null default 'USD',
  gateway varchar(80),
  transaction_reference varchar(120),
  card_brand varchar(40),
  card_last_four varchar(4),
  processed_at timestamptz,
  failure_reason varchar(300),
  is_refund boolean not null default false,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint payments_amount_positive check (amount > 0)
);

comment on column store.payments.state is '{
    "progress": true,
    "values": {
        "pending": {"variant": "secondary", "icon": "Hourglass"},
        "authorized": {"variant": "info", "icon": "ShieldCheck"},
        "captured": {"variant": "success", "icon": "CircleCheck"},
        "failed": {"variant": "destructive", "icon": "TriangleAlert"},
        "refunded": {"variant": "warning", "icon": "Undo2"},
        "voided": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on column store.payments.method is '{
    "progress": false,
    "values": {
        "card": {"variant": "info", "icon": "CreditCard"},
        "paypal": {"variant": "default", "icon": "Wallet"},
        "bank_transfer": {"variant": "secondary", "icon": "Landmark"},
        "cash_on_delivery": {"variant": "warning", "icon": "Banknote"},
        "wallet": {"variant": "success", "icon": "WalletCards"},
        "gift_card": {"variant": "default", "icon": "Gift"}
    }
}';

comment on table store.payments is '{
    "icon": "CreditCard",
    "collapsible_group": "Orders",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "transaction_reference", "badges": ["state", "method"]}},
    "views": [
        {
            "id": "list",
            "name": "All Payments",
            "type": "list",
            "title": "transaction_reference",
            "description": "gateway",
            "field_1": "state",
            "field_2": "amount"
        },
        {
            "id": "kanban",
            "name": "By State",
            "type": "kanban",
            "group": "state",
            "title": "transaction_reference",
            "description": "gateway",
            "date": "processed_at",
            "badge": "method"
        }
    ],
    "filter_presets": [
        {"id": "captured", "name": "Captured", "filters": [{"id": "state", "value": "captured", "operator": "eq"}]},
        {"id": "failed", "name": "Failed", "filters": [{"id": "state", "value": "failed", "operator": "eq"}]},
        {"id": "refunds", "name": "Refunds", "filters": [{"id": "is_refund", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["order_id", "method", "amount"],
        "sections": [
            {"id": "payment", "title": "Payment", "fields": ["order_id", "method", "state", "amount", "currency", "is_refund"]},
            {"id": "gateway", "title": "Gateway", "fields": ["gateway", "transaction_reference", "card_brand", "card_last_four", "processed_at"]},
            {"id": "failure", "title": "Failure", "fields": ["failure_reason"]}
        ],
        "behavior": {
            "failure_reason": {
                "visible": [{"id": "state", "operator": "eq", "value": "failed"}],
                "required": [{"id": "state", "operator": "eq", "value": "failed"}]
            },
            "card_brand": {"visible": [{"id": "method", "operator": "eq", "value": "card"}]},
            "card_last_four": {"visible": [{"id": "method", "operator": "eq", "value": "card"}]}
        },
        "lookups": {
            "order_id": {
                "fill": [
                    {"source_column": "amount", "target_column": "grand_total"},
                    {"source_column": "currency", "target_column": "currency"}
                ]
            }
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [{"table": "orders", "on": "order_id", "columns": ["order_number", "status", "grand_total"]}]
    }
}';

comment on column store.payments.amount is '{"aggregate": "sum"}';

revoke all on table store.payments
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
delete on table store.payments to "x-admin";

grant
select
,
  insert,
update on table store.payments to "fulfillment";

grant
select
  on table store.payments to "merchandiser",
  "support";

create index idx_store_payments_order_id on store.payments (order_id);

create index idx_store_payments_state on store.payments (state);

create index idx_store_payments_processed_at on store.payments (processed_at desc);

alter table store.payments enable row level security;

create policy payments_select on store.payments for
select
  to authenticated using (true);

create policy payments_insert on store.payments for insert to authenticated
with
  check (true);

create policy payments_update on store.payments
for update
  to authenticated using (true)
with
  check (true);

create policy payments_delete on store.payments for delete to authenticated using (true);

----------------------------------------------------------------
-- Shipments
----------------------------------------------------------------
create table store.shipments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  order_id uuid not null references store.orders (id) on delete cascade,
  warehouse_id uuid references store.warehouses (id) on delete set null,
  status store.shipment_status not null default 'pending',
  carrier varchar(80),
  service_level varchar(80),
  tracking_number varchar(120),
  tracking_url supasheet.URL,
  shipping_cost numeric(12, 2) not null default 0,
  weight_grams integer,
  package_count integer not null default 1,
  shipped_at timestamptz,
  estimated_delivery_on date,
  delivered_at timestamptz,
  notes varchar(500),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint shipments_cost_non_negative check (shipping_cost >= 0),
  constraint shipments_package_count_positive check (package_count > 0)
);

comment on column store.shipments.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "secondary", "icon": "Package"},
        "label_created": {"variant": "info", "icon": "Printer"},
        "in_transit": {"variant": "default", "icon": "Truck"},
        "out_for_delivery": {"variant": "warning", "icon": "MapPin"},
        "delivered": {"variant": "success", "icon": "PackageCheck"},
        "failed": {"variant": "destructive", "icon": "TriangleAlert"},
        "returned": {"variant": "destructive", "icon": "Undo2"}
    }
}';

comment on table store.shipments is '{
    "icon": "Truck",
    "collapsible_group": "Orders",
    "display": "block",
    "inline_form": true,
    "primary_view": "kanban",
    "detail": {"header": {"title": "tracking_number", "badges": ["status", "carrier"]}},
    "views": [
        {
            "id": "kanban",
            "name": "Dispatch Board",
            "type": "kanban",
            "group": "status",
            "title": "tracking_number",
            "description": "carrier",
            "date": "estimated_delivery_on",
            "badge": "carrier"
        },
        {
            "id": "calendar",
            "name": "Dispatch Calendar",
            "type": "calendar",
            "title": "tracking_number",
            "badge": "status",
            "start_date": "shipped_at",
            "end_date": "delivered_at"
        },
        {
            "id": "list",
            "name": "All Shipments",
            "type": "list",
            "title": "tracking_number",
            "description": "carrier",
            "field_1": "status",
            "field_2": "shipped_at"
        }
    ],
    "filter_presets": [
        {"id": "in_transit", "name": "In Transit", "filters": [{"id": "status", "value": ["in_transit", "out_for_delivery"], "operator": "in"}]},
        {"id": "delivered", "name": "Delivered", "filters": [{"id": "status", "value": "delivered", "operator": "eq"}]},
        {"id": "problem", "name": "Problems", "filters": [{"id": "status", "value": ["failed", "returned"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["order_id", "warehouse_id", "carrier"],
        "sections": [
            {"id": "shipment", "title": "Shipment", "fields": ["order_id", "warehouse_id", "status", "package_count", "weight_grams"]},
            {"id": "carrier", "title": "Carrier", "fields": ["carrier", "service_level", "tracking_number", "tracking_url", "shipping_cost"]},
            {"id": "dates", "title": "Dates", "fields": ["shipped_at", "estimated_delivery_on", "delivered_at"]},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ],
        "behavior": {
            "delivered_at": {"visible": [{"id": "status", "operator": "eq", "value": "delivered"}]},
            "tracking_number": {"required": [{"id": "status", "operator": "in", "value": ["in_transit", "out_for_delivery", "delivered"]}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "orders", "on": "order_id", "columns": ["order_number", "status", "email"]},
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column store.shipments.shipping_cost is '{"name": "Cost", "aggregate": "sum"}';

revoke all on table store.shipments
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
delete on table store.shipments to "x-admin";

grant
select
,
  insert,
update on table store.shipments to "fulfillment";

grant
select
  on table store.shipments to "merchandiser",
  "support",
  "user";

create index idx_store_shipments_order_id on store.shipments (order_id);

create index idx_store_shipments_warehouse_id on store.shipments (warehouse_id);

create index idx_store_shipments_status on store.shipments (status);

create index idx_store_shipments_shipped_at on store.shipments (shipped_at desc);

alter table store.shipments enable row level security;

create policy shipments_select on store.shipments for
select
  to authenticated using (
    store.is_store_staff ()
    or exists (
      select
        1
      from
        store.orders o
      where
        o.id = order_id
        and o.customer_id = store.current_customer_id ()
    )
  );

create policy shipments_insert on store.shipments for insert to authenticated
with
  check (true);

create policy shipments_update on store.shipments
for update
  to authenticated using (true)
with
  check (true);

create policy shipments_delete on store.shipments for delete to authenticated using (true);

----------------------------------------------------------------
-- Return requests (RMA)
----------------------------------------------------------------
create sequence if not exists store.rma_number_seq;

create table store.return_requests (
  id uuid primary key default extensions.uuid_generate_v4 (),
  rma_number varchar(30) not null unique default (
    'RMA-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('store.rma_number_seq')::text, 4, '0')
  ),
  order_id uuid not null references store.orders (id) on delete cascade,
  customer_id uuid not null references store.customers (id) on delete restrict,
  status store.return_status not null default 'requested',
  reason store.return_reason not null default 'other',
  customer_comment text,
  resolution_note text,
  refund_amount numeric(14, 2) not null default 0,
  restock boolean not null default true,
  warehouse_id uuid references store.warehouses (id) on delete set null,
  requested_at timestamptz not null default current_timestamp,
  approved_at timestamptz,
  received_at timestamptz,
  refunded_at timestamptz,
  rejected_reason varchar(500),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint returns_refund_non_negative check (refund_amount >= 0)
);

comment on column store.return_requests.status is '{
    "progress": true,
    "values": {
        "requested": {"variant": "secondary", "icon": "Inbox"},
        "approved": {"variant": "info", "icon": "CircleCheck"},
        "received": {"variant": "warning", "icon": "PackageOpen"},
        "refunded": {"variant": "success", "icon": "BadgeDollarSign"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "cancelled": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on column store.return_requests.reason is '{
    "progress": false,
    "values": {
        "damaged": {"variant": "destructive", "icon": "PackageX"},
        "wrong_item": {"variant": "warning", "icon": "ArrowLeftRight"},
        "not_as_described": {"variant": "warning", "icon": "FileWarning"},
        "no_longer_needed": {"variant": "secondary", "icon": "CircleSlash"},
        "late_delivery": {"variant": "info", "icon": "Clock"},
        "other": {"variant": "secondary", "icon": "CircleHelp"}
    }
}';

comment on table store.return_requests is '{
    "icon": "Undo2",
    "name": "Returns",
    "collapsible_group": "Orders",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "rma_number", "badges": ["status", "reason"]},
        "tabs": ["return_items"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Returns Desk",
            "type": "kanban",
            "group": "status",
            "title": "rma_number",
            "description": "customer_comment",
            "date": "requested_at",
            "badge": "reason"
        },
        {
            "id": "list",
            "name": "All Returns",
            "type": "list",
            "title": "rma_number",
            "description": "customer_comment",
            "field_1": "status",
            "field_2": "refund_amount"
        }
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["requested", "approved", "received"], "operator": "in"}]},
        {"id": "damaged", "name": "Damaged", "filters": [{"id": "reason", "value": "damaged", "operator": "eq"}]},
        {"id": "refunded", "name": "Refunded", "filters": [{"id": "status", "value": "refunded", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["order_id", "customer_id", "reason"],
        "sections": [
            {"id": "request", "title": "Request", "fields": ["order_id", "customer_id", "reason", "customer_comment"]},
            {"id": "handling", "title": "Handling", "fields": ["status", "warehouse_id", "restock", "refund_amount"]},
            {"id": "rejection", "title": "Rejection", "fields": ["rejected_reason"]},
            {"id": "resolution", "title": "Resolution", "fields": ["resolution_note"]},
            {"id": "timeline", "title": "Timeline", "fields": {"read": ["requested_at", "approved_at", "received_at", "refunded_at"]}}
        ],
        "behavior": {
            "rejected_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "rejected"}],
                "required": [{"id": "status", "operator": "eq", "value": "rejected"}]
            },
            "warehouse_id": {"visible": [{"id": "restock", "operator": "eq", "value": "true"}]}
        },
        "lookups": {
            "order_id": {"fill": [{"source_column": "customer_id", "target_column": "customer_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "requested_at", "desc": true}],
        "join": [
            {"table": "orders", "on": "order_id", "columns": ["order_number", "grand_total"]},
            {"table": "customers", "on": "customer_id", "columns": ["name", "email"]},
            {"table": "warehouses", "on": "warehouse_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column store.return_requests.refund_amount is '{"name": "Refund", "aggregate": "sum"}';

revoke all on table store.return_requests
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
delete on table store.return_requests to "x-admin";

grant
select
,
  insert,
update on table store.return_requests to "fulfillment",
"support";

grant
select
  on table store.return_requests to "merchandiser";

grant
select
,
  insert on table store.return_requests to "user";

revoke all on sequence store.rma_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence store.rma_number_seq to "x-admin",
"fulfillment",
"support",
"user";

create index idx_store_returns_order_id on store.return_requests (order_id);

create index idx_store_returns_customer_id on store.return_requests (customer_id);

create index idx_store_returns_status on store.return_requests (status);

create index idx_store_returns_requested_at on store.return_requests (requested_at desc);

alter table store.return_requests enable row level security;

create policy returns_select on store.return_requests for
select
  to authenticated using (
    store.is_store_staff ()
    or customer_id = store.current_customer_id ()
  );

create policy returns_insert on store.return_requests for insert to authenticated
with
  check (
    store.is_store_staff ()
    or customer_id = store.current_customer_id ()
  );

create policy returns_update on store.return_requests
for update
  to authenticated using (true)
with
  check (true);

create policy returns_delete on store.return_requests for delete to authenticated using (true);

----------------------------------------------------------------
-- Return items (what is actually coming back)
----------------------------------------------------------------
create table store.return_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  return_id uuid not null references store.return_requests (id) on delete cascade,
  order_item_id uuid not null references store.order_items (id) on delete restrict,
  quantity integer not null default 1,
  reason store.return_reason not null default 'other',
  condition_note varchar(300),
  restock boolean not null default true,
  refund_amount numeric(12, 2) not null default 0,
  created_at timestamptz default current_timestamp,
  unique (return_id, order_item_id),
  constraint return_items_quantity_positive check (quantity > 0),
  constraint return_items_refund_non_negative check (refund_amount >= 0)
);

comment on table store.return_items is '{
    "icon": "PackageOpen",
    "name": "Return Items",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["return_id", "order_item_id", "quantity", "reason"]},
            {"id": "handling", "title": "Handling", "fields": ["restock", "condition_note", "refund_amount"]}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [
            {"table": "return_requests", "on": "return_id", "columns": ["rma_number", "status"]},
            {"table": "order_items", "on": "order_item_id", "columns": ["product_name", "sku", "quantity"]}
        ]
    }
}';

comment on column store.return_items.quantity is '{"aggregate": "sum"}';

revoke all on table store.return_items
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
delete on table store.return_items to "x-admin",
"fulfillment";

grant
select
  on table store.return_items to "merchandiser",
  "support",
  "user";

grant insert on table store.return_items to "user";

create index idx_store_return_items_return_id on store.return_items (return_id);

create index idx_store_return_items_order_item_id on store.return_items (order_item_id);

alter table store.return_items enable row level security;

create policy return_items_select on store.return_items for
select
  to authenticated using (true);

create policy return_items_insert on store.return_items for insert to authenticated
with
  check (true);

create policy return_items_update on store.return_items
for update
  to authenticated using (true)
with
  check (true);

create policy return_items_delete on store.return_items for delete to authenticated using (true);

----------------------------------------------------------------
-- Reviews (moderated, and only counted once approved)
----------------------------------------------------------------
create table store.reviews (
  id uuid primary key default extensions.uuid_generate_v4 (),
  product_id uuid not null references store.products (id) on delete cascade,
  variant_id uuid references store.product_variants (id) on delete set null,
  customer_id uuid references store.customers (id) on delete set null,
  order_id uuid references store.orders (id) on delete set null,
  rating supasheet.RATING not null,
  title varchar(200),
  body text,
  status store.review_status not null default 'pending',
  is_verified_purchase boolean not null default false,
  helpful_count integer not null default 0,
  reported_count integer not null default 0,
  merchant_response text,
  responded_at timestamptz,
  rejected_reason varchar(300),
  published_at timestamptz,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint reviews_rating_range check (
    rating >= 1
    and rating <= 5
  )
);

comment on column store.reviews.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "rejected": {"variant": "secondary", "icon": "CircleX"},
        "spam": {"variant": "destructive", "icon": "ShieldAlert"}
    }
}';

comment on table store.reviews is '{
    "icon": "Star",
    "collapsible_group": "Marketing",
    "display": "block",
    "primary_view": "kanban",
    "detail": {"header": {"title": "title", "badges": ["status", "rating", "is_verified_purchase"]}},
    "views": [
        {
            "id": "kanban",
            "name": "Moderation Queue",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "body",
            "date": "created_at",
            "badge": "rating"
        },
        {
            "id": "list",
            "name": "All Reviews",
            "type": "list",
            "title": "title",
            "description": "body",
            "field_1": "rating",
            "field_2": "status"
        }
    ],
    "filter_presets": [
        {"id": "pending", "name": "Awaiting Moderation", "filters": [{"id": "status", "value": "pending", "operator": "eq"}]},
        {"id": "critical", "name": "1 & 2 Star", "filters": [{"id": "rating", "value": "2", "operator": "lte"}]},
        {"id": "verified", "name": "Verified Purchases", "filters": [{"id": "is_verified_purchase", "value": "true", "operator": "eq"}]},
        {"id": "unanswered", "name": "No Response", "filters": [{"id": "merchant_response", "value": "null", "operator": "is"}]}
    ],
    "fields": {
        "quick_create": ["product_id", "rating", "title"],
        "sections": [
            {"id": "review", "title": "Review", "fields": ["product_id", "variant_id", "rating", "title", "body"]},
            {"id": "author", "title": "Author", "fields": ["customer_id", "order_id"]},
            {"id": "moderation", "title": "Moderation", "fields": ["status", "rejected_reason"]},
            {"id": "response", "title": "Merchant response", "fields": ["merchant_response"]},
            {"id": "signals", "title": "Signals", "fields": {"read": ["is_verified_purchase", "helpful_count", "reported_count", "published_at", "responded_at"]}}
        ],
        "behavior": {
            "rejected_reason": {
                "visible": [{"id": "status", "operator": "in", "value": ["rejected", "spam"]}],
                "required": [{"id": "status", "operator": "eq", "value": "rejected"}]
            },
            "variant_id": {"filter": [{"source_column": "product_id", "target_column": "product_id"}]}
        },
        "lookups": {
            "variant_id": {"filter": [{"source_column": "product_id", "target_column": "product_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "products", "on": "product_id", "columns": ["name", "image"]},
            {"table": "customers", "on": "customer_id", "columns": ["name", "email"]},
            {"table": "orders", "on": "order_id", "columns": ["order_number"]}
        ]
    }
}';

comment on column store.reviews.rating is '{"aggregate": "avg"}';

comment on column store.reviews.helpful_count is '{"aggregate": "sum"}';

revoke all on table store.reviews
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
delete on table store.reviews to "x-admin";

grant
select
,
  insert,
update on table store.reviews to "merchandiser";

grant
select
  on table store.reviews to "fulfillment",
  "support";

grant
select
,
  insert on table store.reviews to "user";

-- One review per customer per product.
create unique index idx_store_reviews_customer_product_unique on store.reviews (product_id, customer_id)
where
  customer_id is not null;

create index idx_store_reviews_product_id on store.reviews (product_id);

create index idx_store_reviews_status on store.reviews (status);

create index idx_store_reviews_created_at on store.reviews (created_at desc);

alter table store.reviews enable row level security;

-- Shoppers read the approved wall plus their own submissions.
create policy reviews_select on store.reviews for
select
  to authenticated using (
    status = 'approved'
    or store.is_store_staff ()
    or customer_id = store.current_customer_id ()
  );

create policy reviews_insert on store.reviews for insert to authenticated
with
  check (true);

create policy reviews_update on store.reviews
for update
  to authenticated using (true)
with
  check (true);

create policy reviews_delete on store.reviews for delete to authenticated using (true);

----------------------------------------------------------------
-- Order events (system-generated order history — display: none,
-- never browsable on its own; surfaced only as the "order_events"
-- timeline tab on the order's detail page)
----------------------------------------------------------------
create table store.order_events (
  id uuid primary key default extensions.uuid_generate_v4 (),
  order_id uuid not null references store.orders (id) on delete cascade,
  event_type store.order_event_type not null,
  title varchar(255) not null,
  metadata jsonb,
  actor_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  occurred_at timestamptz not null default current_timestamp
);

comment on column store.order_events.event_type is '{
    "progress": false,
    "values": {
        "created": {"variant": "info", "icon": "Sparkles"},
        "confirmed": {"variant": "default", "icon": "CircleCheck"},
        "paid": {"variant": "success", "icon": "BadgeDollarSign"},
        "fulfilled": {"variant": "success", "icon": "PackageCheck"},
        "shipped": {"variant": "info", "icon": "Truck"},
        "delivered": {"variant": "success", "icon": "MapPinCheck"},
        "cancelled": {"variant": "destructive", "icon": "CircleX"},
        "refunded": {"variant": "warning", "icon": "Undo2"},
        "return_requested": {"variant": "warning", "icon": "PackageOpen"},
        "note_added": {"variant": "secondary", "icon": "StickyNote"},
        "record_updated": {"variant": "secondary", "icon": "RefreshCw"}
    }
}';

comment on table store.order_events is '{
    "icon": "History",
    "name": "Order History",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "event", "title": "Event", "fields": ["order_id", "event_type", "title", "metadata", "actor_id", "occurred_at"]}
        ]
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [{"table": "users", "on": "actor_id", "alias": "actor", "columns": ["name", "email"]}]
    }
}';

revoke all on table store.order_events
from
  public,
  anon,
  authenticated,
  service_role;

-- Select only — the order history is evidence, not a scratchpad.
grant
select
  on table store.order_events to "x-admin",
  "merchandiser",
  "fulfillment",
  "support";

create index idx_store_order_events_order_id on store.order_events (order_id);

create index idx_store_order_events_occurred_at on store.order_events (occurred_at desc);

alter table store.order_events enable row level security;

create policy order_events_select on store.order_events for
select
  to authenticated using (true);

----------------------------------------------------------------
-- Store settings (singleton — one row only, no delete grant)
----------------------------------------------------------------
create table store.store_settings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  store_name varchar(160) not null default 'Supasheet Store',
  logo supasheet.file,
  brand_color supasheet.COLOR default '#111827',
  support_email supasheet.EMAIL,
  support_phone supasheet.TEL,
  default_currency varchar(3) not null default 'USD',
  default_tax_rate supasheet.PERCENTAGE not null default 0,
  prices_include_tax boolean not null default false,
  default_warehouse_id uuid references store.warehouses (id) on delete set null,
  free_shipping_threshold numeric(12, 2) not null default 0,
  standard_shipping_rate numeric(12, 2) not null default 0,
  low_stock_threshold integer not null default 5,
  reserve_stock_on_confirm boolean not null default true,
  auto_approve_reviews boolean not null default false,
  return_window_days integer not null default 30,
  order_prefix varchar(10) not null default 'ORD',
  timezone varchar(100) not null default 'UTC',
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint settings_non_negative check (
    default_tax_rate >= 0
    and free_shipping_threshold >= 0
    and standard_shipping_rate >= 0
    and low_stock_threshold >= 0
    and return_window_days >= 0
  )
);

comment on table store.store_settings is '{
    "icon": "Settings",
    "name": "Store Settings",
    "collapsible_group": "Configuration",
    "display": "block",
    "singleton": true,
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["store_name", "logo", "brand_color", "support_email", "support_phone"]},
            {"id": "money", "title": "Money", "fields": ["default_currency", "default_tax_rate", "prices_include_tax"]},
            {"id": "shipping", "title": "Shipping", "fields": ["default_warehouse_id", "standard_shipping_rate", "free_shipping_threshold"]},
            {"id": "operations", "title": "Operations", "fields": ["reserve_stock_on_confirm", "low_stock_threshold", "return_window_days", "order_prefix"]},
            {"id": "marketing", "title": "Marketing", "fields": ["auto_approve_reviews"]},
            {"id": "locale", "title": "Locale", "collapsible": true, "fields": ["timezone"]}
        ]
    },
    "query": {
        "join": [{"table": "warehouses", "on": "default_warehouse_id", "columns": ["code", "name"]}]
    }
}';

comment on column store.store_settings.logo is '{"accept": "image/*", "max_size": 2097152}';

revoke all on table store.store_settings
from
  public,
  anon,
  authenticated,
  service_role;

-- Singleton: select/insert/update, never delete.
grant
select
,
  insert,
update on table store.store_settings to "x-admin";

grant
select
  on table store.store_settings to "merchandiser",
  "fulfillment",
  "support";

alter table store.store_settings enable row level security;

create policy store_settings_select on store.store_settings for
select
  to authenticated using (true);

create policy store_settings_insert on store.store_settings for insert to authenticated
with
  check (true);

create policy store_settings_update on store.store_settings
for update
  to authenticated using (true)
with
  check (true);

----------------------------------------------------------------
-- Stock allocation column
--
-- Which location an order line was reserved from. Written only by
-- the reservation trigger below, which is why it is not in the
-- order_items form: the operator picks a warehouse for a SHIPMENT,
-- never for a line.
----------------------------------------------------------------
alter table store.order_items
add column warehouse_id uuid references store.warehouses (id) on delete set null;

create index idx_store_order_items_warehouse_id on store.order_items (warehouse_id);

----------------------------------------------------------------
-- Fulfilment helper
--
-- Which location should serve an order line: the configured default
-- first, then the flagged default, then the highest-priority active
-- warehouse. SECURITY DEFINER so a shopper-facing action can resolve
-- it without holding select on the settings table.
----------------------------------------------------------------
create or replace function store.default_warehouse_id () returns uuid language sql stable security definer
set
  search_path = '' as $$
  select coalesce(
    (select s.default_warehouse_id from store.store_settings s order by s.created_at asc limit 1),
    (select w.id from store.warehouses w where w.is_default and w.is_active limit 1),
    (select w.id from store.warehouses w where w.is_active order by w.fulfillment_priority asc, w.code asc limit 1)
  );
$$;

revoke all on function store.default_warehouse_id ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.default_warehouse_id () to "x-admin",
"merchandiser",
"fulfillment",
"support",
"user";

----------------------------------------------------------------
-- Catalogue triggers
----------------------------------------------------------------
-- Products: slug, publication stamp, and the housekeeping the
-- storefront depends on.
create or replace function store.trg_products_apply_defaults () returns trigger as $$
declare
    v_slug text;
begin
    if new.slug is null or btrim(new.slug) = '' then
        v_slug := btrim(regexp_replace(lower(btrim(new.name)), '[^a-z0-9]+', '-', 'g'), '-');

        if v_slug = '' then
            v_slug := 'product';
        end if;

        v_slug := left(v_slug, 200);

        if exists (select 1 from store.products p where p.slug = v_slug and p.id <> new.id) then
            v_slug := v_slug || '-' || left(replace(new.id::text, '-', ''), 6);
        end if;

        new.slug := v_slug;
    end if;

    if new.status = 'active' then
        new.published_at := coalesce(new.published_at, current_timestamp);
    elsif tg_op = 'UPDATE' and old.status = 'active' and new.status = 'draft' then
        -- Pulled back to draft: it is not published any more.
        new.published_at := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger products_apply_defaults
before insert or update on store.products for each row
execute function store.trg_products_apply_defaults ();

-- Variants: a readable label, a price that falls back to the parent,
-- and exactly one default per product.
create or replace function store.trg_variants_apply_defaults () returns trigger as $$
declare
    v_product store.products%rowtype;
    v_label text;
begin
    select * into v_product from store.products where id = new.product_id;

    new.sku := upper(btrim(new.sku));

    if new.price = 0 and v_product.price > 0 then
        new.price := v_product.price;
    end if;

    if new.weight_grams is null then
        new.weight_grams := v_product.weight_grams;
    end if;

    v_label := btrim(
        concat_ws(' / ', nullif(new.option_1, ''), nullif(new.option_2, ''), nullif(new.option_3, ''))
    );

    if new.name is null or btrim(new.name) = '' then
        new.name := coalesce(nullif(v_label, ''), v_product.name);
    end if;

    -- The first variant of a product is its default.
    if tg_op = 'INSERT' and not new.is_default then
        if not exists (
            select 1 from store.product_variants v
            where v.product_id = new.product_id and v.is_default
        ) then
            new.is_default := true;
        end if;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger variants_apply_defaults
before insert or update on store.product_variants for each row
execute function store.trg_variants_apply_defaults ();

-- Variant counts and stock roll up to the product the storefront
-- actually lists.
create or replace function store.trg_variants_rollup_product () returns trigger as $$
declare
    v_products uuid[] := '{}';
    v_id uuid;
begin
    if tg_op <> 'INSERT' then
        v_products := v_products || old.product_id;
    end if;

    if tg_op <> 'DELETE' then
        v_products := v_products || new.product_id;
    end if;

    v_products := array_remove(v_products, null);

    foreach v_id in array v_products loop
        update store.products p
        set variant_count = sub.variants,
            inventory_quantity = sub.stock
        from (
            select
                count(*) as variants,
                coalesce(sum(v.inventory_quantity), 0) as stock
            from store.product_variants v
            where v.product_id = v_id
              and v.is_active
        ) as sub
        where p.id = v_id
          and (p.variant_count, p.inventory_quantity) is distinct from (sub.variants, sub.stock);
    end loop;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger variants_rollup_product
after insert or update of product_id,
inventory_quantity,
is_active or delete on store.product_variants for each row
execute function store.trg_variants_rollup_product ();

----------------------------------------------------------------
-- Inventory triggers
----------------------------------------------------------------
-- Availability is on hand minus what is already promised to an
-- order, and the reorder flag falls out of it.
create or replace function store.trg_inventory_levels_derive () returns trigger as $$
begin
    new.available := new.on_hand - new.reserved;
    new.is_below_reorder_point := new.reorder_point > 0 and new.available <= new.reorder_point;
    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger inventory_levels_derive
before insert or update on store.inventory_levels for each row
execute function store.trg_inventory_levels_derive ();

-- Per-location stock rolls up to the variant, which rolls up to the
-- product through the trigger above.
create or replace function store.trg_inventory_levels_rollup_variant () returns trigger as $$
declare
    v_variants uuid[] := '{}';
    v_id uuid;
begin
    if tg_op <> 'INSERT' then
        v_variants := v_variants || old.variant_id;
    end if;

    if tg_op <> 'DELETE' then
        v_variants := v_variants || new.variant_id;
    end if;

    v_variants := array_remove(v_variants, null);

    foreach v_id in array v_variants loop
        update store.product_variants v
        set inventory_quantity = sub.on_hand,
            reserved_quantity = sub.reserved
        from (
            select
                coalesce(sum(l.on_hand), 0) as on_hand,
                coalesce(sum(l.reserved), 0) as reserved
            from store.inventory_levels l
            where l.variant_id = v_id
        ) as sub
        where v.id = v_id
          and (v.inventory_quantity, v.reserved_quantity) is distinct from (sub.on_hand, sub.reserved);
    end loop;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger inventory_levels_rollup_variant
after insert or update of on_hand,
reserved,
variant_id or delete on store.inventory_levels for each row
execute function store.trg_inventory_levels_rollup_variant ();

-- The ledger is what actually moves stock. A movement creates the
-- level row if this variant has never been held at this location,
-- and refuses to take the balance below zero.
create or replace function store.trg_inventory_movements_apply () returns trigger as $$
declare
    v_level store.inventory_levels%rowtype;
    v_sku varchar(80);
    v_new_on_hand integer;
begin
    select * into v_level
    from store.inventory_levels l
    where l.variant_id = new.variant_id
      and l.warehouse_id = new.warehouse_id
    for update;

    if v_level.id is null then
        insert into store.inventory_levels (variant_id, warehouse_id, on_hand)
        values (new.variant_id, new.warehouse_id, 0)
        returning * into v_level;
    end if;

    if new.movement_type = 'stocktake' then
        -- A stocktake states the counted truth; the quantity IS the
        -- new balance rather than a delta.
        v_new_on_hand := new.quantity;
    else
        v_new_on_hand := v_level.on_hand + new.quantity;
    end if;

    if v_new_on_hand < 0 then
        select sku into v_sku from store.product_variants where id = new.variant_id;

        raise exception 'Movement would take % below zero at this location: % on hand, % requested',
            coalesce(v_sku, new.variant_id::text), v_level.on_hand, abs(new.quantity)
            using errcode = 'check_violation';
    end if;

    if v_new_on_hand < v_level.reserved then
        select sku into v_sku from store.product_variants where id = new.variant_id;

        raise exception 'Movement would leave % short of its reservations: % reserved, % would remain',
            coalesce(v_sku, new.variant_id::text), v_level.reserved, v_new_on_hand
            using errcode = 'check_violation';
    end if;

    update store.inventory_levels
    set on_hand = v_new_on_hand,
        last_counted_at = case
            when new.movement_type = 'stocktake' then new.occurred_at
            else last_counted_at
        end
    where id = v_level.id;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger inventory_movements_apply
after insert on store.inventory_movements for each row
execute function store.trg_inventory_movements_apply ();

----------------------------------------------------------------
-- Reservation helpers
--
-- Reserving is the only place overselling can happen, so it lives in
-- one function that every caller goes through. It picks the location
-- that can serve the whole line, preferring the configured default,
-- and records the allocation on the line itself.
----------------------------------------------------------------
create or replace function store.reserve_order_stock (p_order_id uuid) returns void language plpgsql security definer
set
  search_path = '' as $$
declare
  v_item record;
  v_warehouse uuid;
  v_default uuid := store.default_warehouse_id ();
  v_available integer;
begin
  for v_item in
    select oi.id, oi.variant_id, oi.quantity, oi.sku
    from store.order_items oi
    where oi.order_id = p_order_id
      and oi.warehouse_id is null
    order by oi.position
  loop
    -- Prefer the default location, then anywhere that can serve the
    -- whole line in one piece.
    select l.warehouse_id into v_warehouse
    from store.inventory_levels l
    join store.warehouses w on w.id = l.warehouse_id
    where l.variant_id = v_item.variant_id
      and w.is_active
      and l.available >= v_item.quantity
    order by (l.warehouse_id = v_default) desc, w.fulfillment_priority asc
    limit 1;

    if v_warehouse is null then
      select coalesce(max(l.available), 0) into v_available
      from store.inventory_levels l
      where l.variant_id = v_item.variant_id;

      raise exception 'Cannot reserve % x %: no location has that many free (best is %)',
        v_item.quantity, v_item.sku, v_available
        using errcode = 'check_violation';
    end if;

    update store.inventory_levels
    set reserved = reserved + v_item.quantity
    where variant_id = v_item.variant_id
      and warehouse_id = v_warehouse;

    update store.order_items
    set warehouse_id = v_warehouse
    where id = v_item.id;
  end loop;
end;
$$;

revoke all on function store.reserve_order_stock (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.reserve_order_stock (uuid) to "x-admin",
"fulfillment";

-- Releasing is the mirror image: hand the promise back and forget
-- the allocation.
create or replace function store.release_order_stock (p_order_id uuid) returns void language plpgsql security definer
set
  search_path = '' as $$
declare
  v_item record;
begin
  for v_item in
    select oi.id, oi.variant_id, oi.quantity, oi.fulfilled_quantity, oi.warehouse_id
    from store.order_items oi
    where oi.order_id = p_order_id
      and oi.warehouse_id is not null
  loop
    update store.inventory_levels
    set reserved = greatest(0, reserved - (v_item.quantity - v_item.fulfilled_quantity))
    where variant_id = v_item.variant_id
      and warehouse_id = v_item.warehouse_id;

    update store.order_items
    set warehouse_id = null
    where id = v_item.id;
  end loop;
end;
$$;

revoke all on function store.release_order_stock (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.release_order_stock (uuid) to "x-admin",
"fulfillment";

----------------------------------------------------------------
-- Order triggers
----------------------------------------------------------------
-- Line items snapshot the product, price themselves, and refuse to
-- change once the order is settled.
--
-- SECURITY INVOKER, unlike most triggers here: the guard asks
-- whether the CALLER is the owner, and inside a SECURITY DEFINER
-- function current_user would be the function owner instead.
create or replace function store.trg_order_items_apply_defaults () returns trigger as $$
declare
    v_variant store.product_variants%rowtype;
    v_product store.products%rowtype;
    v_order store.orders%rowtype;
begin
    select * into v_order from store.orders where id = new.order_id;

    if v_order.status in ('completed', 'cancelled')
       and pg_trigger_depth() = 1
       and not pg_has_role(current_user, 'x-admin', 'member') then
        raise exception 'Order % is % and its lines can no longer be changed.',
            v_order.order_number, v_order.status
            using errcode = 'check_violation';
    end if;

    select * into v_variant from store.product_variants where id = new.variant_id;
    select * into v_product from store.products where id = v_variant.product_id;

    -- Snapshot what was bought, so a later rename cannot rewrite
    -- somebody's receipt.
    new.product_name := coalesce(nullif(new.product_name, ''), v_product.name);
    new.sku := coalesce(nullif(new.sku, ''), v_variant.sku);
    new.variant_label := coalesce(new.variant_label, v_variant.name);

    if new.unit_price = 0 then
        new.unit_price := v_variant.price;
    end if;

    if new.tax_amount = 0 and coalesce(v_product.tax_rate, 0) > 0 then
        new.tax_amount := round(
            ((new.quantity * new.unit_price - new.discount_amount) * v_product.tax_rate / 100)::numeric,
            2
        );
    end if;

    new.line_total := round((new.quantity * new.unit_price - new.discount_amount)::numeric, 2);

    if new.line_total < 0 then
        raise exception 'Line discount is larger than the line itself on %', new.sku
            using errcode = 'check_violation';
    end if;

    return new;
end;
$$ language plpgsql security invoker
set
  search_path = '';

create trigger order_items_apply_defaults
before insert or update on store.order_items for each row
execute function store.trg_order_items_apply_defaults ();

-- The order carries what its lines add up to.
create or replace function store.trg_order_items_rollup () returns trigger as $$
declare
    v_order_id uuid := coalesce(new.order_id, old.order_id);
    v_items integer;
    v_subtotal numeric(14, 2);
    v_tax numeric(14, 2);
begin
    select
        coalesce(sum(oi.quantity), 0),
        coalesce(sum(oi.quantity * oi.unit_price), 0),
        coalesce(sum(oi.tax_amount), 0)
    into v_items, v_subtotal, v_tax
    from store.order_items oi
    where oi.order_id = v_order_id;

    update store.orders o
    set item_count = v_items,
        subtotal = v_subtotal,
        tax_total = v_tax
    where o.id = v_order_id
      and (o.item_count, o.subtotal, o.tax_total) is distinct from (v_items, v_subtotal, v_tax);

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger order_items_rollup
after insert or update or delete on store.order_items for each row
execute function store.trg_order_items_rollup ();

-- The order maths and the lifecycle stamps, in one place.
--
-- SECURITY INVOKER for the same reason as the line-item trigger:
-- the settled-order guard asks about the caller.
create or replace function store.trg_orders_apply_defaults () returns trigger as $$
declare
    v_discount store.discounts%rowtype;
    v_order_discount numeric(14, 2) := 0;
    v_customer_email text;
    v_used_by_customer integer;
begin
    if tg_op = 'UPDATE'
       and pg_trigger_depth() = 1
       and old.status in ('completed', 'cancelled')
       and new.status = old.status
       and not pg_has_role(current_user, 'x-admin', 'member') then
        raise exception 'Order % is % and can no longer be edited.', old.order_number, old.status
            using errcode = 'check_violation';
    end if;

    if btrim(coalesce(new.email, '')) = '' then
        select email into v_customer_email from store.customers where id = new.customer_id;
        new.email := v_customer_email;
    end if;

    -- A discount is only usable while it is live, inside its window,
    -- under its cap and over its threshold.
    if new.discount_id is not null
       and (tg_op = 'INSERT' or new.discount_id is distinct from old.discount_id) then
        select * into v_discount from store.discounts where id = new.discount_id;

        if v_discount.id is null then
            raise exception 'Discount not found' using errcode = 'check_violation';
        end if;

        if not v_discount.is_active or v_discount.status = 'paused' then
            raise exception 'Discount % is not currently active', v_discount.code
                using errcode = 'check_violation';
        end if;

        if current_date < v_discount.starts_on or current_date > v_discount.ends_on then
            raise exception 'Discount % runs from % to %', v_discount.code, v_discount.starts_on, v_discount.ends_on
                using errcode = 'check_violation';
        end if;

        if v_discount.usage_limit is not null and v_discount.used_count >= v_discount.usage_limit then
            raise exception 'Discount % has been fully redeemed (% of %)',
                v_discount.code, v_discount.used_count, v_discount.usage_limit
                using errcode = 'check_violation';
        end if;

        select count(*) into v_used_by_customer
        from store.orders o
        where o.customer_id = new.customer_id
          and o.discount_id = new.discount_id
          and o.id <> new.id
          and o.status <> 'cancelled';

        if v_used_by_customer >= v_discount.usage_limit_per_customer then
            raise exception 'Discount % has already been used by this customer', v_discount.code
                using errcode = 'check_violation';
        end if;

        if new.subtotal > 0 and new.subtotal < v_discount.minimum_spend then
            raise exception 'Discount % needs a subtotal of at least %', v_discount.code, v_discount.minimum_spend
                using errcode = 'check_violation';
        end if;
    end if;

    -- Money: what the lines add up to, less the offer, plus carriage
    -- and tax.
    if new.discount_id is not null then
        select * into v_discount from store.discounts where id = new.discount_id;

        v_order_discount := case v_discount.discount_type
            when 'percentage' then round((new.subtotal * v_discount.value / 100)::numeric, 2)
            when 'fixed_amount' then least(v_discount.value, new.subtotal)
            when 'free_shipping' then new.shipping_total
            else 0
        end;
    end if;

    new.discount_total := least(
        round((v_order_discount + coalesce((
            select sum(oi.discount_amount) from store.order_items oi where oi.order_id = new.id
        ), 0))::numeric, 2),
        new.subtotal + new.shipping_total
    );

    new.grand_total := greatest(
        0,
        round((new.subtotal - new.discount_total + new.shipping_total + new.tax_total)::numeric, 2)
    );

    -- Lifecycle stamps
    if new.status = 'confirmed' and (tg_op = 'INSERT' or old.status <> 'confirmed') then
        new.confirmed_at := coalesce(new.confirmed_at, current_timestamp);
    end if;

    if new.status = 'completed' and (tg_op = 'INSERT' or old.status <> 'completed') then
        new.completed_at := coalesce(new.completed_at, current_timestamp);
        new.confirmed_at := coalesce(new.confirmed_at, current_timestamp);
    end if;

    if new.status = 'cancelled' and (tg_op = 'INSERT' or old.status <> 'cancelled') then
        new.cancelled_at := coalesce(new.cancelled_at, current_timestamp);

        if btrim(coalesce(new.cancel_reason, '')) = '' then
            raise exception 'Order % cannot be cancelled without a reason.', new.order_number
                using errcode = 'check_violation';
        end if;
    end if;

    if new.status <> 'cancelled' then
        new.cancelled_at := null;
        new.cancel_reason := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security invoker
set
  search_path = '';

create trigger orders_apply_defaults
before insert or update on store.orders for each row
execute function store.trg_orders_apply_defaults ();

-- Confirming an order promises stock; cancelling hands it back.
create or replace function store.trg_orders_stock_lifecycle () returns trigger as $$
declare
    v_reserve boolean;
begin
    select reserve_stock_on_confirm into v_reserve
    from store.store_settings
    order by created_at asc
    limit 1;

    if coalesce(v_reserve, true)
       and new.status in ('confirmed', 'processing')
       and old.status = 'pending' then
        perform store.reserve_order_stock(new.id);
    elsif new.status = 'cancelled' and old.status <> 'cancelled' then
        perform store.release_order_stock(new.id);
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger orders_stock_lifecycle
after update of status on store.orders for each row
execute function store.trg_orders_stock_lifecycle ();

-- Order history: one entry per thing a customer would ask about.
create or replace function store.trg_orders_log_event () returns trigger as $$
begin
    if tg_op = 'INSERT' then
        insert into store.order_events (order_id, event_type, title, metadata, actor_id)
        values (
            new.id,
            'created',
            'Order ' || new.order_number || ' placed',
            jsonb_build_object('channel', new.channel, 'total', new.grand_total),
            new.user_id
        );
        return new;
    end if;

    if new.status = 'cancelled' and old.status <> 'cancelled' then
        insert into store.order_events (order_id, event_type, title, metadata)
        values (new.id, 'cancelled', 'Order cancelled', jsonb_build_object('reason', new.cancel_reason));
    elsif new.status = 'confirmed' and old.status <> 'confirmed' then
        insert into store.order_events (order_id, event_type, title, metadata)
        values (new.id, 'confirmed', 'Order confirmed', jsonb_build_object('total', new.grand_total));
    elsif new.payment_status = 'paid' and old.payment_status <> 'paid' then
        insert into store.order_events (order_id, event_type, title, metadata)
        values (new.id, 'paid', 'Payment received', jsonb_build_object('paid', new.paid_total));
    elsif new.payment_status in ('refunded', 'partially_refunded')
          and old.payment_status not in ('refunded', 'partially_refunded') then
        insert into store.order_events (order_id, event_type, title, metadata)
        values (new.id, 'refunded', 'Refund issued', jsonb_build_object('refunded', new.refunded_total));
    elsif new.fulfillment_status = 'fulfilled' and old.fulfillment_status <> 'fulfilled' then
        insert into store.order_events (order_id, event_type, title, metadata)
        values (new.id, 'fulfilled', 'Order fulfilled', jsonb_build_object('items', new.item_count));
    elsif new.status is distinct from old.status then
        insert into store.order_events (order_id, event_type, title, metadata)
        values (
            new.id,
            'record_updated',
            'Status changed to ' || new.status,
            jsonb_build_object('from', old.status, 'to', new.status)
        );
    else
        insert into store.order_events (order_id, event_type, title)
        values (new.id, 'record_updated', 'Order updated');
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger orders_log_event
after insert or update of status,
payment_status,
fulfillment_status on store.orders for each row
execute function store.trg_orders_log_event ();

-- Customer lifetime value, product sales counters and discount
-- redemption all follow the order.
create or replace function store.trg_orders_rollup () returns trigger as $$
declare
    v_customers uuid[] := '{}';
    v_discounts uuid[] := '{}';
    v_id uuid;
begin
    if tg_op <> 'INSERT' then
        v_customers := v_customers || old.customer_id;
        v_discounts := v_discounts || old.discount_id;
    end if;

    if tg_op <> 'DELETE' then
        v_customers := v_customers || new.customer_id;
        v_discounts := v_discounts || new.discount_id;
    end if;

    v_customers := array_remove(v_customers, null);
    v_discounts := array_remove(v_discounts, null);

    foreach v_id in array v_customers loop
        update store.customers c
        set order_count = sub.orders,
            total_spent = sub.spent,
            average_order_value = case when sub.orders > 0 then round(sub.spent / sub.orders, 2) else 0 end,
            first_order_at = sub.first_at,
            last_order_at = sub.last_at
        from (
            select
                count(*) as orders,
                coalesce(sum(o.grand_total - o.refunded_total), 0) as spent,
                min(o.placed_at) as first_at,
                max(o.placed_at) as last_at
            from store.orders o
            where o.customer_id = v_id
              and o.status <> 'cancelled'
        ) as sub
        where c.id = v_id
          and (c.order_count, c.total_spent, c.first_order_at, c.last_order_at)
              is distinct from (sub.orders, sub.spent, sub.first_at, sub.last_at);
    end loop;

    foreach v_id in array v_discounts loop
        update store.discounts d
        set used_count = sub.uses,
            revenue_influenced = sub.revenue,
            redemption_rate = case
                when d.usage_limit is not null and d.usage_limit > 0
                    then least(100, round(100.0 * sub.uses / d.usage_limit))::real
                else 0
            end
        from (
            select
                count(*) as uses,
                coalesce(sum(o.grand_total), 0) as revenue
            from store.orders o
            where o.discount_id = v_id
              and o.status <> 'cancelled'
        ) as sub
        where d.id = v_id
          and (d.used_count, d.revenue_influenced) is distinct from (sub.uses, sub.revenue);
    end loop;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger orders_rollup
after insert or update of status,
grand_total,
refunded_total,
customer_id,
discount_id or delete on store.orders for each row
execute function store.trg_orders_rollup ();

-- Units sold and revenue per product, counted from settled orders
-- only — a cancelled basket never sold anything.
create or replace function store.trg_orders_rollup_products () returns trigger as $$
declare
    v_product uuid;
begin
    for v_product in
        select distinct v.product_id
        from store.order_items oi
        join store.product_variants v on v.id = oi.variant_id
        where oi.order_id = new.id
    loop
        update store.products p
        set units_sold = sub.units,
            revenue_to_date = sub.revenue
        from (
            select
                coalesce(sum(oi.quantity - oi.returned_quantity), 0) as units,
                coalesce(sum(oi.line_total), 0) as revenue
            from store.order_items oi
            join store.product_variants v on v.id = oi.variant_id
            join store.orders o on o.id = oi.order_id
            where v.product_id = v_product
              and o.status = 'completed'
        ) as sub
        where p.id = v_product
          and (p.units_sold, p.revenue_to_date) is distinct from (sub.units, sub.revenue);
    end loop;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger orders_rollup_products
after update of status on store.orders for each row
execute function store.trg_orders_rollup_products ();

----------------------------------------------------------------
-- Payment triggers
----------------------------------------------------------------
create or replace function store.trg_payments_apply_defaults () returns trigger as $$
begin
    if new.state = 'captured' and (tg_op = 'INSERT' or old.state <> 'captured') then
        new.processed_at := coalesce(new.processed_at, current_timestamp);
    end if;

    if new.state <> 'failed' then
        new.failure_reason := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger payments_apply_defaults
before insert or update on store.payments for each row
execute function store.trg_payments_apply_defaults ();

-- What has actually settled decides the order's payment status.
create or replace function store.trg_payments_rollup () returns trigger as $$
declare
    v_order_id uuid := coalesce(new.order_id, old.order_id);
    v_order store.orders%rowtype;
    v_paid numeric(14, 2);
    v_refunded numeric(14, 2);
    v_authorized integer;
    v_failed integer;
    v_status store.payment_status;
begin
    select * into v_order from store.orders where id = v_order_id;

    if v_order.id is null then
        return coalesce(new, old);
    end if;

    select
        coalesce(sum(p.amount) filter (where p.state = 'captured' and not p.is_refund), 0),
        coalesce(sum(p.amount) filter (where p.state in ('captured', 'refunded') and p.is_refund), 0),
        count(*) filter (where p.state = 'authorized'),
        count(*) filter (where p.state = 'failed')
    into v_paid, v_refunded, v_authorized, v_failed
    from store.payments p
    where p.order_id = v_order_id;

    v_status := case
        when v_paid > 0 and v_refunded >= v_paid then 'refunded'
        when v_refunded > 0 then 'partially_refunded'
        when v_order.grand_total > 0 and v_paid >= v_order.grand_total then 'paid'
        when v_paid > 0 then 'partially_paid'
        when v_authorized > 0 then 'authorized'
        when v_failed > 0 then 'failed'
        else 'unpaid'
    end;

    update store.orders o
    set paid_total = v_paid,
        refunded_total = v_refunded,
        payment_status = v_status
    where o.id = v_order_id
      and (o.paid_total, o.refunded_total, o.payment_status)
          is distinct from (v_paid, v_refunded, v_status);

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger payments_rollup
after insert or update or delete on store.payments for each row
execute function store.trg_payments_rollup ();

----------------------------------------------------------------
-- Shipment triggers
----------------------------------------------------------------
create or replace function store.trg_shipments_apply_defaults () returns trigger as $$
begin
    if new.status in ('in_transit', 'out_for_delivery', 'delivered')
       and (tg_op = 'INSERT' or old.status not in ('in_transit', 'out_for_delivery', 'delivered')) then
        new.shipped_at := coalesce(new.shipped_at, current_timestamp);
    end if;

    if new.status = 'delivered' and (tg_op = 'INSERT' or old.status <> 'delivered') then
        new.delivered_at := coalesce(new.delivered_at, current_timestamp);
    end if;

    if new.warehouse_id is null then
        new.warehouse_id := store.default_warehouse_id ();
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger shipments_apply_defaults
before insert or update on store.shipments for each row
execute function store.trg_shipments_apply_defaults ();

-- Dispatching a shipment is what turns a promise into a sale: the
-- reservation is released, the stock actually leaves through the
-- ledger, and the order's fulfilment status follows.
create or replace function store.trg_shipments_dispatch () returns trigger as $$
declare
    v_item record;
    v_outstanding integer;
    v_order store.orders%rowtype;
    v_fulfilled integer;
    v_total integer;
    v_status store.fulfillment_status;
begin
    if new.status not in ('in_transit', 'out_for_delivery', 'delivered') then
        return new;
    end if;

    if tg_op = 'UPDATE' and old.status in ('in_transit', 'out_for_delivery', 'delivered') then
        -- Already dispatched; nothing new leaves the building.
        return new;
    end if;

    for v_item in
        select oi.id, oi.variant_id, oi.quantity, oi.fulfilled_quantity, oi.sku,
               coalesce(oi.warehouse_id, new.warehouse_id) as source_warehouse
        from store.order_items oi
        where oi.order_id = new.order_id
          and oi.fulfilled_quantity < oi.quantity
        order by oi.position
    loop
        v_outstanding := v_item.quantity - v_item.fulfilled_quantity;

        -- Release the promise first, so the stock ledger never leaves
        -- the location short of its own reservations.
        update store.inventory_levels
        set reserved = greatest(0, reserved - v_outstanding)
        where variant_id = v_item.variant_id
          and warehouse_id = v_item.source_warehouse;

        insert into store.inventory_movements (
            variant_id, warehouse_id, movement_type, quantity, reference, note, occurred_at
        )
        values (
            v_item.variant_id,
            v_item.source_warehouse,
            'sale',
            -v_outstanding,
            new.tracking_number,
            'Dispatched on shipment ' || coalesce(new.tracking_number, new.id::text),
            coalesce(new.shipped_at, current_timestamp)
        );

        update store.order_items
        set fulfilled_quantity = quantity
        where id = v_item.id;
    end loop;

    select * into v_order from store.orders where id = new.order_id;

    select
        coalesce(sum(oi.fulfilled_quantity), 0),
        coalesce(sum(oi.quantity), 0)
    into v_fulfilled, v_total
    from store.order_items oi
    where oi.order_id = new.order_id;

    v_status := case
        when v_total = 0 then 'unfulfilled'
        when v_fulfilled >= v_total then 'fulfilled'
        when v_fulfilled > 0 then 'partially_fulfilled'
        else 'unfulfilled'
    end;

    update store.orders
    set fulfillment_status = v_status,
        status = case
            when v_status = 'fulfilled' and status in ('confirmed', 'processing') then 'processing'
            else status
        end
    where id = new.order_id
      and fulfillment_status is distinct from v_status;

    insert into store.order_events (order_id, event_type, title, metadata)
    values (
        new.order_id,
        'shipped',
        'Shipment dispatched' || coalesce(' via ' || new.carrier, ''),
        jsonb_build_object('shipment_id', new.id, 'tracking', new.tracking_number)
    );

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger shipments_dispatch
after insert or update of status on store.shipments for each row
execute function store.trg_shipments_dispatch ();

create or replace function store.trg_shipments_delivered () returns trigger as $$
begin
    if new.status = 'delivered' and (tg_op = 'INSERT' or old.status <> 'delivered') then
        insert into store.order_events (order_id, event_type, title, metadata)
        values (
            new.order_id,
            'delivered',
            'Delivered',
            jsonb_build_object('shipment_id', new.id, 'delivered_at', new.delivered_at)
        );
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger shipments_delivered
after insert or update of status on store.shipments for each row
execute function store.trg_shipments_delivered ();

----------------------------------------------------------------
-- Customer triggers
----------------------------------------------------------------
create or replace function store.trg_customers_apply_defaults () returns trigger as $$
begin
    new.name := btrim(new.first_name || ' ' || new.last_name);
    new.email := lower(btrim(new.email));

    if new.accepts_marketing and (tg_op = 'INSERT' or not old.accepts_marketing) then
        new.marketing_opt_in_at := coalesce(new.marketing_opt_in_at, current_timestamp);
    elsif not new.accepts_marketing then
        new.marketing_opt_in_at := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger customers_apply_defaults
before insert or update on store.customers for each row
execute function store.trg_customers_apply_defaults ();

----------------------------------------------------------------
-- Return triggers
----------------------------------------------------------------
-- You cannot send back more than you bought, counting what has
-- already come back on other returns.
create or replace function store.trg_return_items_guard () returns trigger as $$
declare
    v_item store.order_items%rowtype;
    v_already integer;
begin
    select * into v_item from store.order_items where id = new.order_item_id;

    if v_item.id is null then
        raise exception 'Order line not found' using errcode = 'check_violation';
    end if;

    select coalesce(sum(ri.quantity), 0) into v_already
    from store.return_items ri
    join store.return_requests r on r.id = ri.return_id
    where ri.order_item_id = new.order_item_id
      and ri.id <> new.id
      and r.status <> 'rejected'
      and r.status <> 'cancelled';

    if v_already + new.quantity > v_item.quantity then
        raise exception 'Cannot return % x %: only % were bought and % are already coming back',
            new.quantity, v_item.sku, v_item.quantity, v_already
            using errcode = 'check_violation';
    end if;

    if new.refund_amount = 0 then
        new.refund_amount := round(
            (new.quantity * (v_item.line_total / nullif(v_item.quantity, 0)))::numeric,
            2
        );
    end if;

    return new;
end;
$$ language plpgsql security invoker
set
  search_path = '';

create trigger return_items_guard
before insert or update on store.return_items for each row
execute function store.trg_return_items_guard ();

-- The requested refund is what the lines add up to.
create or replace function store.trg_return_items_rollup () returns trigger as $$
declare
    v_return_id uuid := coalesce(new.return_id, old.return_id);
    v_total numeric(14, 2);
begin
    select coalesce(sum(ri.refund_amount), 0)
    into v_total
    from store.return_items ri
    where ri.return_id = v_return_id;

    update store.return_requests r
    set refund_amount = v_total
    where r.id = v_return_id
      and r.status not in ('refunded', 'rejected', 'cancelled')
      and r.refund_amount is distinct from v_total;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger return_items_rollup
after insert or update or delete on store.return_items for each row
execute function store.trg_return_items_rollup ();

create or replace function store.trg_returns_apply_defaults () returns trigger as $$
begin
    if new.status = 'approved' and (tg_op = 'INSERT' or old.status <> 'approved') then
        new.approved_at := coalesce(new.approved_at, current_timestamp);
    end if;

    if new.status = 'received' and (tg_op = 'INSERT' or old.status <> 'received') then
        new.received_at := coalesce(new.received_at, current_timestamp);
        new.approved_at := coalesce(new.approved_at, current_timestamp);
    end if;

    if new.status = 'refunded' and (tg_op = 'INSERT' or old.status <> 'refunded') then
        new.refunded_at := coalesce(new.refunded_at, current_timestamp);
    end if;

    if new.status <> 'rejected' then
        new.rejected_reason := null;
    end if;

    if new.warehouse_id is null and new.restock then
        new.warehouse_id := store.default_warehouse_id ();
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger returns_apply_defaults
before insert or update on store.return_requests for each row
execute function store.trg_returns_apply_defaults ();

-- Receiving a return puts the goods back on the shelf; refunding it
-- books the money back through the payment ledger.
create or replace function store.trg_returns_after () returns trigger as $$
declare
    v_line record;
begin
    if tg_op = 'INSERT' then
        insert into store.order_events (order_id, event_type, title, metadata, actor_id)
        values (
            new.order_id,
            'return_requested',
            'Return ' || new.rma_number || ' requested',
            jsonb_build_object('return_id', new.id, 'reason', new.reason),
            auth.uid ()
        );
        return new;
    end if;

    if new.status = 'received' and old.status <> 'received' then
        for v_line in
            select ri.quantity, ri.restock, oi.id as order_item_id, oi.variant_id, oi.sku,
                   coalesce(oi.warehouse_id, new.warehouse_id, store.default_warehouse_id ()) as target_warehouse
            from store.return_items ri
            join store.order_items oi on oi.id = ri.order_item_id
            where ri.return_id = new.id
        loop
            if v_line.restock and new.restock then
                insert into store.inventory_movements (
                    variant_id, warehouse_id, movement_type, quantity, reference, note
                )
                values (
                    v_line.variant_id,
                    v_line.target_warehouse,
                    'return',
                    v_line.quantity,
                    new.rma_number,
                    'Restocked from return ' || new.rma_number
                );
            end if;

            update store.order_items
            set returned_quantity = least(quantity, returned_quantity + v_line.quantity)
            where id = v_line.order_item_id;
        end loop;

        update store.orders o
        set fulfillment_status = 'returned'
        where o.id = new.order_id
          and not exists (
            select 1
            from store.order_items oi
            where oi.order_id = new.order_id
              and oi.returned_quantity < oi.quantity
          );
    end if;

    if new.status = 'refunded' and old.status <> 'refunded' and new.refund_amount > 0 then
        insert into store.payments (
            order_id, method, state, amount, gateway, transaction_reference, is_refund, processed_at
        )
        select
            new.order_id,
            coalesce(
                (
                    select p.method
                    from store.payments p
                    where p.order_id = new.order_id and not p.is_refund and p.state = 'captured'
                    order by p.processed_at desc
                    limit 1
                ),
                'card'::store.payment_method
            ),
            'captured',
            new.refund_amount,
            'refund',
            new.rma_number,
            true,
            current_timestamp;
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger returns_after
after insert or update of status on store.return_requests for each row
execute function store.trg_returns_after ();

----------------------------------------------------------------
-- Review triggers
----------------------------------------------------------------
create or replace function store.trg_reviews_apply_defaults () returns trigger as $$
declare
    v_auto_approve boolean;
begin
    if tg_op = 'INSERT' then
        -- A verified purchase is one we can actually find in a
        -- completed order for this customer.
        if new.customer_id is not null then
            new.is_verified_purchase := exists (
                select 1
                from store.order_items oi
                join store.orders o on o.id = oi.order_id
                join store.product_variants v on v.id = oi.variant_id
                where o.customer_id = new.customer_id
                  and o.status = 'completed'
                  and v.product_id = new.product_id
            );

            if new.order_id is null then
                select o.id into new.order_id
                from store.orders o
                join store.order_items oi on oi.order_id = o.id
                join store.product_variants v on v.id = oi.variant_id
                where o.customer_id = new.customer_id
                  and v.product_id = new.product_id
                  and o.status = 'completed'
                order by o.placed_at desc
                limit 1;
            end if;
        end if;

        select auto_approve_reviews into v_auto_approve
        from store.store_settings
        order by created_at asc
        limit 1;

        if coalesce(v_auto_approve, false) and new.status = 'pending' then
            new.status := 'approved';
        end if;
    end if;

    if new.status = 'approved' then
        new.published_at := coalesce(new.published_at, current_timestamp);
    else
        new.published_at := null;
    end if;

    if new.status not in ('rejected', 'spam') then
        new.rejected_reason := null;
    end if;

    if btrim(coalesce(new.merchant_response, '')) <> ''
       and (tg_op = 'INSERT' or new.merchant_response is distinct from old.merchant_response) then
        new.responded_at := coalesce(new.responded_at, current_timestamp);
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger reviews_apply_defaults
before insert or update on store.reviews for each row
execute function store.trg_reviews_apply_defaults ();

-- Only approved reviews count towards the star rating a shopper sees.
create or replace function store.trg_reviews_rollup () returns trigger as $$
declare
    v_product_id uuid := coalesce(new.product_id, old.product_id);
    v_rating numeric;
    v_count integer;
begin
    select
        round(avg(r.rating)::numeric, 2),
        count(*)
    into v_rating, v_count
    from store.reviews r
    where r.product_id = v_product_id
      and r.status = 'approved';

    update store.products p
    set average_rating = v_rating,
        review_count = coalesce(v_count, 0)
    where p.id = v_product_id
      and (p.average_rating, p.review_count) is distinct from (v_rating::real, coalesce(v_count, 0));

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger reviews_rollup
after insert or update or delete on store.reviews for each row
execute function store.trg_reviews_rollup ();

----------------------------------------------------------------
-- Scheduled maintenance
--
-- Discount windows and low-stock flags both age on their own, with
-- nothing touching the row to trigger a recalculation. Run this
-- nightly:
--
--   select cron.schedule(
--     'store-refresh-state', '10 0 * * *',
--     $job$ select store.refresh_store_state(); $job$
--   );
----------------------------------------------------------------
create or replace function store.refresh_store_state () returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_discounts integer;
  v_levels integer;
begin
  update store.discounts
  set status = case
    when not is_active then 'paused'::store.discount_status
    when current_date > ends_on then 'expired'::store.discount_status
    when current_date < starts_on then 'scheduled'::store.discount_status
    else 'active'::store.discount_status
  end
  where status is distinct from case
    when not is_active then 'paused'::store.discount_status
    when current_date > ends_on then 'expired'::store.discount_status
    when current_date < starts_on then 'scheduled'::store.discount_status
    else 'active'::store.discount_status
  end;

  get diagnostics v_discounts = row_count;

  update store.inventory_levels
  set is_below_reorder_point = reorder_point > 0 and available <= reorder_point
  where is_below_reorder_point is distinct from (reorder_point > 0 and available <= reorder_point);

  get diagnostics v_levels = row_count;

  return v_discounts + v_levels;
end;
$$;

revoke all on function store.refresh_store_state ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.refresh_store_state () to "x-admin";

-- Keep updated_at fresh on the tables without a defaults trigger.
create trigger brands_set_updated_at
before update on store.brands for each row
execute function supasheet.set_updated_at ();

create trigger categories_set_updated_at
before update on store.categories for each row
execute function supasheet.set_updated_at ();

create trigger product_costs_set_updated_at
before update on store.product_costs for each row
execute function supasheet.set_updated_at ();

create trigger warehouses_set_updated_at
before update on store.warehouses for each row
execute function supasheet.set_updated_at ();

create trigger addresses_set_updated_at
before update on store.addresses for each row
execute function supasheet.set_updated_at ();

create trigger discounts_set_updated_at
before update on store.discounts for each row
execute function supasheet.set_updated_at ();

create trigger store_settings_set_updated_at
before update on store.store_settings for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Row action: confirm an order
----------------------------------------------------------------
create or replace function store.confirm_order (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_order store.orders%rowtype;
  v_items integer;
begin
  select * into v_order from store.orders where id = p_id;

  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  if v_order.status <> 'pending' then
    raise exception 'Order % is already %', v_order.order_number, v_order.status;
  end if;

  select count(*) into v_items from store.order_items where order_id = p_id;

  if v_items = 0 then
    raise exception 'Order % has no lines to confirm', v_order.order_number;
  end if;

  -- The stock reservation happens in the trigger, and will refuse
  -- the whole statement if anything cannot be served.
  update store.orders set status = 'confirmed' where id = p_id;
end;
$$;

comment on function store.confirm_order (uuid) is '{
    "type": "action",
    "resource": "orders",
    "name": "Confirm",
    "description": "Accept the order and reserve stock for every line",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "pending"}],
    "confirm": {"title": "Confirm this order?", "description": "Stock is reserved immediately; the order is refused if anything is short."},
    "success_message": "Order confirmed"
}';

revoke all on function store.confirm_order (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.confirm_order (uuid) to "x-admin",
"fulfillment";

----------------------------------------------------------------
-- Row action: take payment
----------------------------------------------------------------
create or replace function store.mark_order_paid (
  p_id uuid,
  p_method store.payment_method default 'card',
  p_reference varchar default null
) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_order store.orders%rowtype;
  v_outstanding numeric(14, 2);
begin
  select * into v_order from store.orders where id = p_id;

  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  if v_order.status = 'cancelled' then
    raise exception 'Order % was cancelled', v_order.order_number;
  end if;

  v_outstanding := v_order.grand_total - v_order.paid_total;

  if v_outstanding <= 0 then
    raise exception 'Order % is already settled', v_order.order_number;
  end if;

  insert into store.payments (order_id, method, state, amount, currency, transaction_reference, gateway)
  values (p_id, p_method, 'captured', v_outstanding, v_order.currency, p_reference, 'manual');
end;
$$;

comment on function store.mark_order_paid (uuid, store.payment_method, varchar) is '{
    "type": "action",
    "resource": "orders",
    "name": "Mark paid",
    "description": "Record a captured payment for the outstanding balance",
    "icon": "BadgeDollarSign",
    "visible": [{"id": "payment_status", "operator": "not.in", "value": ["paid", "refunded"]}],
    "success_message": "Payment recorded"
}';

revoke all on function store.mark_order_paid (uuid, store.payment_method, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.mark_order_paid (uuid, store.payment_method, varchar) to "x-admin",
"fulfillment";

----------------------------------------------------------------
-- Row action: ship an order
----------------------------------------------------------------
create or replace function store.ship_order (
  p_id uuid,
  p_carrier varchar default 'DHL',
  p_tracking_number varchar default null,
  p_warehouse_id uuid default null
) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_order store.orders%rowtype;
begin
  select * into v_order from store.orders where id = p_id;

  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  if v_order.status = 'cancelled' then
    raise exception 'Order % was cancelled', v_order.order_number;
  end if;

  if v_order.fulfillment_status = 'fulfilled' then
    raise exception 'Order % has already shipped', v_order.order_number;
  end if;

  -- The dispatch trigger does the real work: releasing the
  -- reservation, writing the sale movements and moving the order on.
  insert into store.shipments (order_id, warehouse_id, carrier, tracking_number, status)
  values (
    p_id,
    coalesce(p_warehouse_id, store.default_warehouse_id ()),
    p_carrier,
    coalesce(p_tracking_number, 'TRK-' || upper(left(replace(p_id::text, '-', ''), 10))),
    'in_transit'
  );
end;
$$;

comment on function store.ship_order (uuid, varchar, varchar, uuid) is '{
    "type": "action",
    "resource": "orders",
    "name": "Ship",
    "description": "Dispatch everything outstanding and book the stock out",
    "icon": "Truck",
    "visible": [{"id": "fulfillment_status", "operator": "not.in", "value": ["fulfilled", "returned"]}],
    "confirm": {"title": "Ship this order?", "description": "Reserved stock is booked out of the warehouse and the customer is notified."},
    "success_message": "Order shipped"
}';

revoke all on function store.ship_order (uuid, varchar, varchar, uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.ship_order (uuid, varchar, varchar, uuid) to "x-admin",
"fulfillment";

----------------------------------------------------------------
-- Row action: complete an order
----------------------------------------------------------------
create or replace function store.complete_order (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_order store.orders%rowtype;
begin
  select * into v_order from store.orders where id = p_id;

  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  if v_order.fulfillment_status not in ('fulfilled', 'returned') then
    raise exception 'Order % has not been fulfilled yet', v_order.order_number;
  end if;

  update store.orders set status = 'completed' where id = p_id;
end;
$$;

comment on function store.complete_order (uuid) is '{
    "type": "action",
    "resource": "orders",
    "name": "Complete",
    "description": "Close the order out once it has been delivered",
    "icon": "PackageCheck",
    "visible": [{"id": "status", "operator": "in", "value": ["confirmed", "processing"]}],
    "success_message": "Order completed"
}';

revoke all on function store.complete_order (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.complete_order (uuid) to "x-admin",
"fulfillment";

----------------------------------------------------------------
-- Row action: cancel an order
----------------------------------------------------------------
create or replace function store.cancel_order (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'Say why the order is being cancelled';
  end if;

  update store.orders
  set status = 'cancelled',
      cancel_reason = p_reason
  where id = p_id
    and status not in ('completed', 'cancelled');

  if not found then
    raise exception 'Order not found, already cancelled, or already completed';
  end if;
end;
$$;

comment on function store.cancel_order (uuid, varchar) is '{
    "type": "action",
    "resource": "orders",
    "name": "Cancel",
    "description": "Cancel the order and release every reservation",
    "icon": "CircleX",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "not.in", "value": ["completed", "cancelled"]}],
    "confirm": {"title": "Cancel this order?", "description": "Reserved stock goes back on sale immediately."},
    "success_message": "Order cancelled"
}';

revoke all on function store.cancel_order (uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.cancel_order (uuid, varchar) to "x-admin",
"fulfillment";

----------------------------------------------------------------
-- Row action: refund an order
----------------------------------------------------------------
create or replace function store.refund_order (
  p_id uuid,
  p_amount numeric default null,
  p_reason varchar default null
) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_order store.orders%rowtype;
  v_amount numeric(14, 2);
begin
  select * into v_order from store.orders where id = p_id;

  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  v_amount := coalesce(p_amount, v_order.paid_total - v_order.refunded_total);

  if v_amount <= 0 then
    raise exception 'Nothing left to refund on %', v_order.order_number;
  end if;

  if v_amount > v_order.paid_total - v_order.refunded_total then
    raise exception 'Cannot refund % — only % was collected and not yet returned',
      v_amount, v_order.paid_total - v_order.refunded_total;
  end if;

  insert into store.payments (
    order_id, method, state, amount, currency, gateway, transaction_reference, is_refund
  )
  values (
    p_id,
    'card',
    'captured',
    v_amount,
    v_order.currency,
    'refund',
    coalesce(p_reason, 'Manual refund'),
    true
  );
end;
$$;

comment on function store.refund_order (uuid, numeric, varchar) is '{
    "type": "action",
    "resource": "orders",
    "name": "Refund",
    "description": "Book a refund back through the payment ledger",
    "icon": "Undo2",
    "variant": "destructive",
    "visible": [{"id": "payment_status", "operator": "in", "value": ["paid", "partially_paid", "partially_refunded"]}],
    "confirm": {"title": "Refund this order?", "description": "Defaults to the full outstanding amount."},
    "success_message": "Refund recorded"
}';

revoke all on function store.refund_order (uuid, numeric, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.refund_order (uuid, numeric, varchar) to "x-admin";

----------------------------------------------------------------
-- Row action: move an order (enum value-picker)
----------------------------------------------------------------
create or replace function store.set_order_status (p_id uuid, p_status store.order_status) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_status = 'cancelled' then
    raise exception 'Use the "Cancel" action so the reason is captured';
  end if;

  update store.orders set status = p_status where id = p_id;
end;
$$;

comment on function store.set_order_status (uuid, store.order_status) is '{
    "type": "action",
    "resource": "orders",
    "name": "Set status",
    "icon": "ArrowRightLeft",
    "action_type": "picker"
}';

revoke all on function store.set_order_status (uuid, store.order_status)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.set_order_status (uuid, store.order_status) to "x-admin",
"fulfillment";

----------------------------------------------------------------
-- Row action: mark a shipment delivered
----------------------------------------------------------------
create or replace function store.mark_shipment_delivered (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update store.shipments
  set status = 'delivered'
  where id = p_id
    and status <> 'delivered';

  if not found then
    raise exception 'Shipment not found or already delivered';
  end if;
end;
$$;

comment on function store.mark_shipment_delivered (uuid) is '{
    "type": "action",
    "resource": "shipments",
    "name": "Mark delivered",
    "description": "Record the parcel as delivered",
    "icon": "MapPinCheck",
    "visible": [{"id": "status", "operator": "not.in", "value": ["delivered", "returned"]}],
    "success_message": "Shipment delivered"
}';

revoke all on function store.mark_shipment_delivered (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.mark_shipment_delivered (uuid) to "x-admin",
"fulfillment";

----------------------------------------------------------------
-- Row actions: the returns desk
----------------------------------------------------------------
create or replace function store.receive_return (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update store.return_requests
  set status = 'received'
  where id = p_id
    and status in ('requested', 'approved');

  if not found then
    raise exception 'Return not found or not awaiting receipt';
  end if;
end;
$$;

comment on function store.receive_return (uuid) is '{
    "type": "action",
    "resource": "return_requests",
    "name": "Receive",
    "description": "Book the goods back in and restock them",
    "icon": "PackageOpen",
    "visible": [{"id": "status", "operator": "in", "value": ["requested", "approved"]}],
    "confirm": {"title": "Receive this return?", "description": "Restockable lines go straight back into available stock."},
    "success_message": "Return received"
}';

revoke all on function store.receive_return (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.receive_return (uuid) to "x-admin",
"fulfillment";

create or replace function store.refund_return (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_return store.return_requests%rowtype;
begin
  select * into v_return from store.return_requests where id = p_id;

  if v_return.id is null then
    raise exception 'Return not found';
  end if;

  if v_return.status <> 'received' then
    raise exception 'Return % has not been received yet', v_return.rma_number;
  end if;

  if v_return.refund_amount <= 0 then
    raise exception 'Return % has nothing to refund', v_return.rma_number;
  end if;

  update store.return_requests set status = 'refunded' where id = p_id;
end;
$$;

comment on function store.refund_return (uuid) is '{
    "type": "action",
    "resource": "return_requests",
    "name": "Refund",
    "description": "Pay the customer back through the payment ledger",
    "icon": "BadgeDollarSign",
    "visible": [{"id": "status", "operator": "eq", "value": "received"}],
    "success_message": "Refund issued"
}';

revoke all on function store.refund_return (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.refund_return (uuid) to "x-admin";

----------------------------------------------------------------
-- Row actions: review moderation
----------------------------------------------------------------
create or replace function store.approve_review (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update store.reviews set status = 'approved' where id = p_id and status <> 'approved';

  if not found then
    raise exception 'Review not found or already approved';
  end if;
end;
$$;

comment on function store.approve_review (uuid) is '{
    "type": "action",
    "resource": "reviews",
    "name": "Approve",
    "description": "Publish this review and count it towards the star rating",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "neq", "value": "approved"}],
    "success_message": "Review approved"
}';

revoke all on function store.approve_review (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.approve_review (uuid) to "x-admin",
"merchandiser";

create or replace function store.reject_review (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'Say why the review was rejected';
  end if;

  update store.reviews
  set status = 'rejected',
      rejected_reason = p_reason
  where id = p_id
    and status <> 'rejected';

  if not found then
    raise exception 'Review not found or already rejected';
  end if;
end;
$$;

comment on function store.reject_review (uuid, varchar) is '{
    "type": "action",
    "resource": "reviews",
    "name": "Reject",
    "description": "Keep this review off the storefront",
    "icon": "CircleX",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "neq", "value": "rejected"}],
    "success_message": "Review rejected"
}';

revoke all on function store.reject_review (uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.reject_review (uuid, varchar) to "x-admin",
"merchandiser";

----------------------------------------------------------------
-- Row actions: catalogue lifecycle
----------------------------------------------------------------
create or replace function store.publish_product (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_variants integer;
begin
  select count(*) into v_variants
  from store.product_variants
  where product_id = p_id and is_active;

  if v_variants = 0 then
    raise exception 'A product needs at least one active variant before it can go live';
  end if;

  update store.products set status = 'active' where id = p_id and status <> 'active';

  if not found then
    raise exception 'Product not found or already active';
  end if;
end;
$$;

comment on function store.publish_product (uuid) is '{
    "type": "action",
    "resource": "products",
    "name": "Publish",
    "description": "Put this product on the storefront",
    "icon": "Globe",
    "visible": [{"id": "status", "operator": "neq", "value": "active"}],
    "success_message": "Product published"
}';

revoke all on function store.publish_product (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.publish_product (uuid) to "x-admin",
"merchandiser";

create or replace function store.archive_product (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update store.products set status = 'archived' where id = p_id and status <> 'archived';

  if not found then
    raise exception 'Product not found or already archived';
  end if;
end;
$$;

comment on function store.archive_product (uuid) is '{
    "type": "action",
    "resource": "products",
    "name": "Archive",
    "description": "Retire this product without deleting its sales history",
    "icon": "Archive",
    "variant": "secondary",
    "visible": [{"id": "status", "operator": "neq", "value": "archived"}],
    "confirm": {"title": "Archive this product?", "description": "It disappears from the storefront; past orders keep their snapshot."},
    "success_message": "Product archived"
}';

revoke all on function store.archive_product (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.archive_product (uuid) to "x-admin",
"merchandiser";

----------------------------------------------------------------
-- Custom form: receive stock (listed on the "warehouses" resource
-- overview). Returns a scalar uuid — the UI toasts and refreshes.
----------------------------------------------------------------
create or replace function store.receive_stock (
  p_warehouse_id uuid,
  p_variant_id uuid,
  p_quantity integer,
  p_unit_cost numeric default null,
  p_reference varchar default null,
  p_note varchar default null
) returns uuid language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_id uuid;
begin
  if p_quantity <= 0 then
    raise exception 'Receipt quantity has to be positive';
  end if;

  insert into store.inventory_movements (
    variant_id, warehouse_id, movement_type, quantity, unit_cost, reference, note
  )
  values (
    p_variant_id,
    p_warehouse_id,
    'receipt',
    p_quantity,
    p_unit_cost,
    p_reference,
    coalesce(p_note, 'Goods received')
  )
  returning id into v_id;

  -- A receipt is also the best moment to refresh what we paid.
  if p_unit_cost is not null then
    update store.product_costs pc
    set last_purchase_price = p_unit_cost
    from store.product_variants v
    where v.id = p_variant_id
      and pc.product_id = v.product_id;
  end if;

  return v_id;
end;
$$;

comment on function store.receive_stock (uuid, uuid, integer, numeric, varchar, varchar) is '{
    "type": "form",
    "resource": "warehouses",
    "name": "Receive stock",
    "description": "Book a delivery into this location and update the last purchase price.",
    "icon": "PackageCheck",
    "success_message": "Stock received",
    "fields": {
        "sections": [
            {"id": "where", "title": "Location", "fields": ["p_warehouse_id", "p_variant_id"]},
            {"id": "what", "title": "Delivery", "fields": ["p_quantity", "p_unit_cost", "p_reference", "p_note"]}
        ],
        "relations": {
            "p_warehouse_id": {"table": "warehouses", "column": "id", "display": ["code", "name"]},
            "p_variant_id": {"table": "product_variants", "column": "id", "display": ["sku", "name"]}
        }
    }
}';

revoke all on function store.receive_stock (uuid, uuid, integer, numeric, varchar, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.receive_stock (uuid, uuid, integer, numeric, varchar, varchar) to "x-admin",
"fulfillment";

----------------------------------------------------------------
-- Custom form: take an order over the phone (listed on the
-- "customers" resource overview). Returns a single object row via
-- explicit OUT parameters — the UI renders the created record as a
-- detail card.
----------------------------------------------------------------
create or replace function store.create_manual_order (
  p_customer_id uuid,
  p_variant_id uuid,
  p_quantity integer default 1,
  p_channel store.sales_channel default 'phone',
  p_shipping_total numeric default 0,
  p_discount_id uuid default null,
  p_confirm boolean default false,
  out order_id uuid,
  out order_number varchar,
  out status store.order_status,
  out item_count integer,
  out subtotal numeric,
  out grand_total numeric,
  out payment_status store.payment_status
) language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_customer store.customers%rowtype;
  v_order store.orders%rowtype;
begin
  select * into v_customer from store.customers where id = p_customer_id;

  if v_customer.id is null then
    raise exception 'Customer not found';
  end if;

  if v_customer.status = 'blocked' then
    raise exception 'Customer % is blocked', v_customer.email;
  end if;

  if p_quantity <= 0 then
    raise exception 'Quantity has to be positive';
  end if;

  insert into store.orders (
    customer_id, email, channel, shipping_total, discount_id,
    shipping_address_id, billing_address_id
  )
  values (
    p_customer_id,
    v_customer.email,
    p_channel,
    coalesce(p_shipping_total, 0),
    p_discount_id,
    v_customer.default_shipping_address_id,
    v_customer.default_billing_address_id
  )
  returning * into v_order;

  insert into store.order_items (order_id, variant_id, quantity, position)
  values (v_order.id, p_variant_id, p_quantity, 1);

  if p_confirm then
    update store.orders set status = 'confirmed' where id = v_order.id;
  end if;

  select * into v_order from store.orders where id = v_order.id;

  order_id := v_order.id;
  order_number := v_order.order_number;
  status := v_order.status;
  item_count := v_order.item_count;
  subtotal := v_order.subtotal;
  grand_total := v_order.grand_total;
  payment_status := v_order.payment_status;
end;
$$;

comment on function store.create_manual_order (
  uuid,
  uuid,
  integer,
  store.sales_channel,
  numeric,
  uuid,
  boolean
) is '{
    "type": "form",
    "resource": "customers",
    "name": "Take an order",
    "description": "Raise an order on behalf of this customer — e.g. over the phone.",
    "icon": "ShoppingCart",
    "success_message": "Order created",
    "fields": {
        "sections": [
            {"id": "customer", "title": "Customer", "fields": ["p_customer_id", "p_channel"]},
            {"id": "line", "title": "Line", "fields": ["p_variant_id", "p_quantity"]},
            {"id": "money", "title": "Money", "fields": ["p_shipping_total", "p_discount_id", "p_confirm"]}
        ],
        "relations": {
            "p_customer_id": {"table": "customers", "column": "id", "display": ["name", "email"]},
            "p_variant_id": {"table": "product_variants", "column": "id", "display": ["sku", "name"]},
            "p_discount_id": {"table": "discounts", "column": "id", "display": ["code", "name"]}
        }
    }
}';

revoke all on function store.create_manual_order (
  uuid,
  uuid,
  integer,
  store.sales_channel,
  numeric,
  uuid,
  boolean
)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.create_manual_order (
  uuid,
  uuid,
  integer,
  store.sales_channel,
  numeric,
  uuid,
  boolean
) to "x-admin",
"fulfillment";

----------------------------------------------------------------
-- Custom form: reprice a brand (listed on the "brands" resource
-- overview). Returns setof store.products — the UI renders the
-- repriced rows as a table.
----------------------------------------------------------------
create or replace function store.bulk_reprice (
  p_brand_id uuid,
  p_percent numeric,
  p_only_active boolean default true
) returns setof store.products language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_percent = 0 then
    raise exception 'Give a non-zero percentage — positive to raise, negative to discount';
  end if;

  if abs(p_percent) > 50 then
    raise exception 'A % percent move needs to go through the pricing committee, not this form', p_percent;
  end if;

  -- Variants first, because the product price is the shop window and
  -- the variant price is what actually gets charged.
  update store.product_variants v
  set price = round(v.price * (1 + p_percent / 100), 2)
  from store.products p
  where p.id = v.product_id
    and p.brand_id = p_brand_id
    and (not p_only_active or p.status = 'active');

  return query
  update store.products p
  set price = round(p.price * (1 + p_percent / 100), 2)
  where p.brand_id = p_brand_id
    and (not p_only_active or p.status = 'active')
  returning *;
end;
$$;

comment on function store.bulk_reprice (uuid, numeric, boolean) is '{
    "type": "form",
    "resource": "brands",
    "name": "Reprice brand",
    "description": "Move every price for this brand by a percentage — positive to raise, negative to discount.",
    "icon": "Percent",
    "success_message": "Prices updated",
    "fields": {
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["p_brand_id", "p_only_active"]},
            {"id": "move", "title": "Move", "fields": ["p_percent"]}
        ],
        "relations": {
            "p_brand_id": {"table": "brands", "column": "id", "display": ["name", "slug"]}
        }
    }
}';

revoke all on function store.bulk_reprice (uuid, numeric, boolean)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.bulk_reprice (uuid, numeric, boolean) to "x-admin",
"merchandiser";

----------------------------------------------------------------
-- Custom form: what to reorder (listed on the "warehouses" resource
-- overview). Pure computation — no writes. Returns setof rows via
-- an explicit table(...) column list.
----------------------------------------------------------------
create or replace function store.preview_restock_plan (
  p_warehouse_id uuid,
  p_include_healthy boolean default false
) returns table (
  sku varchar,
  product varchar,
  on_hand integer,
  reserved integer,
  available integer,
  reorder_point integer,
  suggested_order integer,
  estimated_cost numeric,
  supplier varchar,
  lead_time_days integer
) language plpgsql security invoker
set
  search_path = '' as $$
begin
  return query
  select
    v.sku,
    p.name,
    l.on_hand,
    l.reserved,
    l.available,
    l.reorder_point,
    greatest(
      coalesce(nullif(l.reorder_quantity, 0), l.reorder_point * 2 - l.available),
      0
    )::integer as suggested_order,
    round(
      greatest(
        coalesce(nullif(l.reorder_quantity, 0), l.reorder_point * 2 - l.available),
        0
      ) * coalesce(pc.unit_cost, 0),
      2
    ) as estimated_cost,
    pc.supplier_name,
    coalesce(pc.lead_time_days, 0)
  from store.inventory_levels l
  join store.product_variants v on v.id = l.variant_id
  join store.products p on p.id = v.product_id
  left join store.product_costs pc on pc.product_id = p.id
  where l.warehouse_id = p_warehouse_id
    and (p_include_healthy or l.is_below_reorder_point)
  order by (l.available - l.reorder_point) asc, v.sku;
end;
$$;

comment on function store.preview_restock_plan (uuid, boolean) is '{
    "type": "form",
    "resource": "warehouses",
    "name": "Restock plan",
    "description": "What this location needs to reorder, what it will cost and how long it takes to arrive.",
    "icon": "ClipboardList",
    "success_message": "Restock plan calculated",
    "fields": {
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["p_warehouse_id", "p_include_healthy"]}
        ],
        "relations": {
            "p_warehouse_id": {"table": "warehouses", "column": "id", "display": ["code", "name"]}
        }
    }
}';

revoke all on function store.preview_restock_plan (uuid, boolean)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function store.preview_restock_plan (uuid, boolean) to "x-admin",
"fulfillment",
"merchandiser";

----------------------------------------------------------------
-- Templates (bulk insert payloads applied via supasheet.apply_template)
--
--   select supasheet.apply_template('store', '<template_view>', 'categories');
--
-- Only column names present on BOTH the view and the target table
-- are copied; everything else falls back to the target's defaults.
----------------------------------------------------------------
-- Static: the department structure a new store starts with. Applying
-- it twice is a no-op because the view filters out slugs that exist.
create or replace view store.default_categories_template
with
  (security_invoker = true) as
select
  t.name,
  t.slug,
  t.description,
  t.sort_order
from
  (
    values
      (
        'New Arrivals'::varchar(160),
        'new-arrivals'::varchar(160),
        'Everything added in the last thirty days.'::text,
        10
      ),
      (
        'Best Sellers',
        'best-sellers',
        'What everyone else is buying.',
        20
      ),
      (
        'Audio',
        'audio',
        'Headphones, speakers and everything that makes a noise.',
        30
      ),
      (
        'Computing',
        'computing',
        'Laptops, desktops and the parts inside them.',
        40
      ),
      (
        'Accessories',
        'accessories',
        'Cables, cases and the things that go missing.',
        50
      ),
      (
        'Clearance',
        'clearance',
        'Last chance, last stock.',
        60
      )
  ) as t (name, slug, description, sort_order)
where
  not exists (
    select
      1
    from
      store.categories c
    where
      c.slug = t.slug
  );

revoke all on store.default_categories_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.default_categories_template to "x-admin",
  "merchandiser";

comment on view store.default_categories_template is '{"type": "template", "name": "Default Categories", "description": "The six departments a new store starts with. Apply to store.categories.", "target_table": "categories"}';

-- Dynamic: a receipt line for everything sitting below its reorder
-- point, sized to the reorder quantity.
create or replace view store.restock_movements_template
with
  (security_invoker = true) as
select
  l.variant_id,
  l.warehouse_id,
  'receipt'::store.movement_type as movement_type,
  greatest(
    coalesce(
      nullif(l.reorder_quantity, 0),
      l.reorder_point * 2 - l.available
    ),
    1
  )::integer as quantity,
  pc.unit_cost,
  ('RESTOCK-' || to_char(current_date, 'YYYYMMDD'))::varchar(80) as reference,
  ('Auto-planned restock for ' || v.sku)::varchar(500) as note
from
  store.inventory_levels l
  join store.product_variants v on v.id = l.variant_id
  join store.products p on p.id = v.product_id
  left join store.product_costs pc on pc.product_id = p.id
where
  l.is_below_reorder_point
  and v.is_active
  and p.status = 'active';

revoke all on store.restock_movements_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.restock_movements_template to "x-admin",
  "fulfillment";

comment on view store.restock_movements_template is '{"type": "template", "name": "Restock Receipts", "description": "A goods-in line for every variant below its reorder point. Apply to store.inventory_movements once the delivery actually lands.", "target_table": "inventory_movements"}';

-- Dynamic: a personal win-back code for every customer who used to
-- buy and has gone quiet.
create or replace view store.winback_discounts_template
with
  (security_invoker = true) as
select
  (
    'WINBACK-' || upper(left(replace(c.id::text, '-', ''), 6))
  )::varchar(40) as code,
  ('Win-back — ' || c.name)::varchar(160) as name,
  (
    'Lapsed since ' || to_char(c.last_order_at, 'Mon YYYY') || '. Lifetime spend ' || round(c.total_spent, 0) || '.'
  )::varchar(500) as description,
  'percentage'::store.discount_type as discount_type,
  case
    when c.total_spent >= 100000 then 20
    when c.total_spent >= 25000 then 15
    else 10
  end::numeric(12, 2) as value,
  1 as usage_limit,
  1 as usage_limit_per_customer,
  current_date as starts_on,
  (current_date + 45) as ends_on,
  'scheduled'::store.discount_status as status
from
  store.customers c
where
  c.status = 'active'
  and c.accepts_marketing
  and c.order_count > 0
  and c.last_order_at < current_timestamp - interval '120 days'
  and not exists (
    select
      1
    from
      store.discounts d
    where
      d.code = 'WINBACK-' || upper(left(replace(c.id::text, '-', ''), 6))
  );

revoke all on store.winback_discounts_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.winback_discounts_template to "x-admin",
  "merchandiser";

comment on view store.winback_discounts_template is '{"type": "template", "name": "Win-back Codes", "description": "A single-use personal discount for every marketable customer who has not ordered in four months, scaled to their lifetime spend. Apply to store.discounts.", "target_table": "discounts"}';

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view store.sales_report
with
  (security_invoker = true) as
select
  o.id,
  o.order_number,
  o.placed_at,
  c.name as customer,
  c.email,
  c.customer_group,
  o.channel,
  o.status,
  o.payment_status,
  o.fulfillment_status,
  o.item_count,
  o.subtotal,
  o.discount_total,
  o.shipping_total,
  o.tax_total,
  o.grand_total,
  o.paid_total,
  o.refunded_total,
  (o.grand_total - o.refunded_total) as net_revenue,
  o.currency,
  d.code as discount_code,
  (
    select
      string_agg(distinct s.carrier, ', ')
    from
      store.shipments s
    where
      s.order_id = o.id
  ) as carriers,
  (
    select
      min(s.shipped_at)
    from
      store.shipments s
    where
      s.order_id = o.id
  ) as first_shipped_at,
  o.completed_at,
  o.cancel_reason
from
  store.orders o
  join store.customers c on c.id = o.customer_id
  left join store.discounts d on d.id = o.discount_id;

revoke all on store.sales_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.sales_report to "x-admin",
  "merchandiser",
  "fulfillment",
  "support";

-- `template: true` means a Handlebars HTML file has been uploaded to
-- the `report-templates` bucket at the deterministic key
-- `store/sales_report.hbs` (one template per report). Upload
-- supabase/examples/templates/sales_report.hbs there as-is (as
-- "x-admin") to enable the "Print Report" button on this report.
comment on view store.sales_report is '{"type": "report", "name": "Sales Report", "description": "Every order with customer, channel, settlement and shipping context", "template": true}';

create or replace view store.product_performance_report
with
  (security_invoker = true) as
select
  p.id,
  p.name as product,
  b.name as brand,
  cat.name as category,
  p.status,
  p.price,
  pc.unit_cost,
  case
    when p.price > 0
    and pc.unit_cost is not null then round(100.0 * (p.price - pc.unit_cost) / p.price, 1)
    else null
  end as margin_percent,
  p.variant_count,
  p.inventory_quantity,
  coalesce(sold.units, 0) as units_sold,
  coalesce(sold.revenue, 0) as revenue,
  coalesce(returned.units, 0) as units_returned,
  case
    when coalesce(sold.units, 0) > 0 then round(
      100.0 * coalesce(returned.units, 0) / sold.units,
      1
    )
    else 0
  end as return_rate,
  p.average_rating,
  p.review_count,
  p.published_at
from
  store.products p
  left join store.brands b on b.id = p.brand_id
  left join store.categories cat on cat.id = p.category_id
  left join store.product_costs pc on pc.product_id = p.id
  left join (
    select
      v.product_id,
      sum(oi.quantity) as units,
      sum(oi.line_total) as revenue
    from
      store.order_items oi
      join store.product_variants v on v.id = oi.variant_id
      join store.orders o on o.id = oi.order_id
    where
      o.status <> 'cancelled'
    group by
      v.product_id
  ) sold on sold.product_id = p.id
  left join (
    select
      v.product_id,
      sum(oi.returned_quantity) as units
    from
      store.order_items oi
      join store.product_variants v on v.id = oi.variant_id
    group by
      v.product_id
  ) returned on returned.product_id = p.id;

revoke all on store.product_performance_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.product_performance_report to "x-admin",
  "merchandiser";

comment on view store.product_performance_report is '{"type": "report", "name": "Product Performance", "description": "Units, revenue, margin, returns and rating per product"}';

create or replace view store.inventory_report
with
  (security_invoker = true) as
select
  l.id,
  v.sku,
  p.name as product,
  v.name as variant,
  w.code as warehouse,
  w.name as warehouse_name,
  l.on_hand,
  l.reserved,
  l.available,
  l.reorder_point,
  l.reorder_quantity,
  l.is_below_reorder_point,
  l.bin_location,
  pc.unit_cost,
  round(l.on_hand * coalesce(pc.unit_cost, 0), 2) as stock_value,
  pc.supplier_name,
  pc.lead_time_days,
  l.last_counted_at,
  (
    select
      max(m.occurred_at)
    from
      store.inventory_movements m
    where
      m.variant_id = l.variant_id
      and m.warehouse_id = l.warehouse_id
  ) as last_movement_at
from
  store.inventory_levels l
  join store.product_variants v on v.id = l.variant_id
  join store.products p on p.id = v.product_id
  join store.warehouses w on w.id = l.warehouse_id
  left join store.product_costs pc on pc.product_id = p.id;

revoke all on store.inventory_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.inventory_report to "x-admin",
  "fulfillment",
  "merchandiser";

comment on view store.inventory_report is '{"type": "report", "name": "Inventory Report", "description": "Stock on hand, reserved, available and its value per location"}';

create or replace view store.customer_report
with
  (security_invoker = true) as
select
  c.id,
  c.name as customer,
  c.email,
  c.customer_group,
  c.status,
  c.country,
  c.order_count,
  c.total_spent,
  c.average_order_value,
  c.first_order_at,
  c.last_order_at,
  case
    when c.last_order_at is null then null
    else current_date - c.last_order_at::date
  end as days_since_order,
  coalesce(returns.count, 0) as returns_raised,
  coalesce(reviews.count, 0) as reviews_left,
  c.accepts_marketing,
  c.created_at
from
  store.customers c
  left join (
    select
      r.customer_id,
      count(*) as count
    from
      store.return_requests r
    group by
      r.customer_id
  ) returns on returns.customer_id = c.id
  left join (
    select
      rv.customer_id,
      count(*) as count
    from
      store.reviews rv
    group by
      rv.customer_id
  ) reviews on reviews.customer_id = c.id;

revoke all on store.customer_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.customer_report to "x-admin",
  "merchandiser",
  "support";

comment on view store.customer_report is '{"type": "report", "name": "Customer Report", "description": "Spend, frequency, recency, returns and reviews per customer"}';

create or replace view store.returns_report
with
  (security_invoker = true) as
select
  r.id,
  r.rma_number,
  o.order_number,
  c.name as customer,
  r.status,
  r.reason,
  r.refund_amount,
  r.restock,
  w.code as warehouse,
  r.requested_at,
  r.received_at,
  r.refunded_at,
  case
    when r.refunded_at is not null then r.refunded_at::date - r.requested_at::date
    else current_date - r.requested_at::date
  end as days_open,
  (
    select
      sum(ri.quantity)
    from
      store.return_items ri
    where
      ri.return_id = r.id
  ) as units,
  (
    select
      string_agg(distinct oi.product_name, ', ')
    from
      store.return_items ri
      join store.order_items oi on oi.id = ri.order_item_id
    where
      ri.return_id = r.id
  ) as products
from
  store.return_requests r
  join store.orders o on o.id = r.order_id
  join store.customers c on c.id = r.customer_id
  left join store.warehouses w on w.id = r.warehouse_id;

revoke all on store.returns_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.returns_report to "x-admin",
  "fulfillment",
  "merchandiser",
  "support";

comment on view store.returns_report is '{"type": "report", "name": "Returns Report", "description": "Return volume, reasons, refunds and turnaround time"}';

create or replace view store.discount_report
with
  (security_invoker = true) as
select
  d.id,
  d.code,
  d.name,
  d.discount_type,
  d.status,
  d.value,
  d.minimum_spend,
  d.usage_limit,
  d.used_count,
  d.redemption_rate,
  d.revenue_influenced,
  round(coalesce(sum(o.discount_total), 0), 2) as discount_given,
  case
    when coalesce(sum(o.discount_total), 0) > 0 then round(
      coalesce(sum(o.grand_total), 0) / sum(o.discount_total),
      2
    )
    else null
  end as revenue_per_currency_discounted,
  round(avg(o.grand_total), 2) as average_order_value,
  d.starts_on,
  d.ends_on
from
  store.discounts d
  left join store.orders o on o.discount_id = d.id
  and o.status <> 'cancelled'
group by
  d.id,
  d.code,
  d.name,
  d.discount_type,
  d.status,
  d.value,
  d.minimum_spend,
  d.usage_limit,
  d.used_count,
  d.redemption_rate,
  d.revenue_influenced,
  d.starts_on,
  d.ends_on;

revoke all on store.discount_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.discount_report to "x-admin",
  "merchandiser";

comment on view store.discount_report is '{"type": "report", "name": "Discount Report", "description": "Redemption, revenue influenced and cost per promotion"}';

----------------------------------------------------------------
-- Materialized view report (precomputed monthly trading)
--
-- Two different refreshes — don't confuse them:
--   select supasheet.refresh_metadata();            -- the catalog
--   refresh materialized view concurrently
--     store.sales_rollup;                           -- the data
----------------------------------------------------------------
create materialized view store.sales_rollup as
select
  to_char(date_trunc('month', o.placed_at), 'YYYY-MM') as month,
  count(*) filter (
    where
      o.status <> 'cancelled'
  ) as orders,
  count(*) filter (
    where
      o.status = 'cancelled'
  ) as cancelled_orders,
  coalesce(
    sum(o.grand_total) filter (
      where
        o.status <> 'cancelled'
    ),
    0
  ) as gross_revenue,
  coalesce(sum(o.refunded_total), 0) as refunds,
  coalesce(
    sum(o.grand_total - o.refunded_total) filter (
      where
        o.status <> 'cancelled'
    ),
    0
  ) as net_revenue,
  coalesce(
    sum(o.discount_total) filter (
      where
        o.status <> 'cancelled'
    ),
    0
  ) as discounts_given,
  coalesce(
    sum(o.item_count) filter (
      where
        o.status <> 'cancelled'
    ),
    0
  ) as units,
  round(
    avg(o.grand_total) filter (
      where
        o.status <> 'cancelled'
    ),
    2
  ) as average_order_value,
  count(distinct o.customer_id) filter (
    where
      o.status <> 'cancelled'
  ) as buying_customers,
  round(
    100.0 * count(*) filter (
      where
        o.status = 'cancelled'
    ) / nullif(count(*), 0),
    1
  ) as cancellation_rate
from
  store.orders o
group by
  date_trunc('month', o.placed_at)
order by
  date_trunc('month', o.placed_at) desc;

-- Unique index is REQUIRED for `refresh ... concurrently`.
create unique index idx_store_sales_rollup_month on store.sales_rollup (month);

revoke all on store.sales_rollup
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.sales_rollup to "x-admin",
  "merchandiser",
  "fulfillment";

comment on materialized view store.sales_rollup is '{"type": "report", "name": "Monthly Trading", "description": "Precomputed monthly revenue, refunds, units and basket size"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: orders still to work
create or replace view store.open_orders_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'shopping-cart' as icon,
  'open orders' as label
from
  store.orders
where
  status in ('pending', 'confirmed', 'processing');

revoke all on store.open_orders_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.open_orders_count to "x-admin",
  "merchandiser",
  "fulfillment",
  "support";

-- card_2: settled against outstanding
create or replace view store.payment_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      payment_status = 'paid'
  ) as primary,
  count(*) filter (
    where
      payment_status in ('unpaid', 'authorized', 'partially_paid')
  ) as secondary,
  'Paid' as primary_label,
  'Outstanding' as secondary_label
from
  store.orders
where
  status <> 'cancelled';

revoke all on store.payment_split
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.payment_split to "x-admin",
  "merchandiser",
  "fulfillment",
  "support";

-- card_3: how much of the book has shipped
create or replace view store.fulfillment_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        fulfillment_status = 'fulfilled'
    ) / nullif(count(*), 0),
    1
  ) as percent
from
  store.orders
where
  status <> 'cancelled';

revoke all on store.fulfillment_rate
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.fulfillment_rate to "x-admin",
  "fulfillment";

-- card_4: where the order book sits
create or replace view store.order_pipeline_progress
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'completed'
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
      'Confirmed',
      'value',
      count(*) filter (
        where
          status = 'confirmed'
      )
    ),
    json_build_object(
      'label',
      'Processing',
      'value',
      count(*) filter (
        where
          status = 'processing'
      )
    ),
    json_build_object(
      'label',
      'Completed',
      'value',
      count(*) filter (
        where
          status = 'completed'
      )
    ),
    json_build_object(
      'label',
      'Cancelled',
      'value',
      count(*) filter (
        where
          status = 'cancelled'
      )
    )
  ) as segments
from
  store.orders;

revoke all on store.order_pipeline_progress
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.order_pipeline_progress to "x-admin",
  "fulfillment";

-- card_5: revenue headline plus the channels behind it
create or replace view store.revenue_by_channel_overview
with
  (security_invoker = true) as
select
  round(
    coalesce(
      sum(grand_total - refunded_total) filter (
        where
          status <> 'cancelled'
      ),
      0
    ),
    0
  ) as value,
  'Net Revenue' as label,
  'banknote' as icon,
  json_build_array(
    json_build_object(
      'label',
      'Web',
      'value',
      round(
        coalesce(
          sum(grand_total) filter (
            where
              channel = 'web'
              and status <> 'cancelled'
          ),
          0
        ),
        0
      ),
      'variant',
      'info'
    ),
    json_build_object(
      'label',
      'Mobile',
      'value',
      round(
        coalesce(
          sum(grand_total) filter (
            where
              channel = 'mobile_app'
              and status <> 'cancelled'
          ),
          0
        ),
        0
      ),
      'variant',
      'default'
    ),
    json_build_object(
      'label',
      'Marketplace',
      'value',
      round(
        coalesce(
          sum(grand_total) filter (
            where
              channel = 'marketplace'
              and status <> 'cancelled'
          ),
          0
        ),
        0
      ),
      'variant',
      'warning'
    ),
    json_build_object(
      'label',
      'Retail & phone',
      'value',
      round(
        coalesce(
          sum(grand_total) filter (
            where
              channel in ('pos', 'phone')
              and status <> 'cancelled'
          ),
          0
        ),
        0
      ),
      'variant',
      'secondary'
    )
  ) as breakdown
from
  store.orders;

revoke all on store.revenue_by_channel_overview
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.revenue_by_channel_overview to "x-admin",
  "merchandiser";

-- card_6: full-width metric grid
create or replace view store.store_pulse
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Revenue 30d',
      'value',
      round(
        coalesce(
          sum(grand_total - refunded_total) filter (
            where
              status <> 'cancelled'
              and placed_at >= current_timestamp - interval '30 days'
          ),
          0
        ),
        0
      ),
      'icon',
      'banknote'
    ),
    json_build_object(
      'label',
      'Orders 30d',
      'value',
      count(*) filter (
        where
          status <> 'cancelled'
          and placed_at >= current_timestamp - interval '30 days'
      ),
      'icon',
      'shopping-cart'
    ),
    json_build_object(
      'label',
      'Avg basket',
      'value',
      round(
        coalesce(
          avg(grand_total) filter (
            where
              status <> 'cancelled'
          ),
          0
        ),
        0
      ),
      'icon',
      'shopping-bag'
    ),
    json_build_object(
      'label',
      'To ship',
      'value',
      count(*) filter (
        where
          fulfillment_status in ('unfulfilled', 'partially_fulfilled')
          and status not in ('cancelled', 'pending')
      ),
      'icon',
      'truck'
    ),
    json_build_object(
      'label',
      'Low stock',
      'value',
      (
        select
          count(*)
        from
          store.inventory_levels
        where
          is_below_reorder_point
      ),
      'icon',
      'package-x'
    ),
    json_build_object(
      'label',
      'Open returns',
      'value',
      (
        select
          count(*)
        from
          store.return_requests
        where
          status in ('requested', 'approved', 'received')
      ),
      'icon',
      'undo-2'
    )
  ) as metrics
from
  store.orders;

revoke all on store.store_pulse
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.store_pulse to "x-admin",
  "merchandiser",
  "fulfillment";

-- table_1: the newest orders
create or replace view store.recent_orders
with
  (security_invoker = true) as
select
  o.order_number,
  c.name as customer,
  o.status,
  round(o.grand_total, 0) as total,
  to_char(o.placed_at, 'Mon DD') as placed,
  '/store/resource/orders/' || o.id || '/detail' as link
from
  store.orders o
  join store.customers c on c.id = o.customer_id
order by
  o.placed_at desc
limit
  10;

revoke all on store.recent_orders
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.recent_orders to "x-admin",
  "merchandiser",
  "fulfillment",
  "support";

-- table_1: the dispatch queue (pairs with Recent Orders)
create or replace view store.orders_to_ship
with
  (security_invoker = true) as
select
  o.order_number,
  c.name as customer,
  o.item_count as items,
  o.payment_status,
  to_char(o.placed_at, 'Mon DD') as placed,
  '/store/resource/orders/' || o.id || '/detail' as link
from
  store.orders o
  join store.customers c on c.id = o.customer_id
where
  o.fulfillment_status in ('unfulfilled', 'partially_fulfilled')
  and o.status in ('confirmed', 'processing')
order by
  o.placed_at asc
limit
  10;

revoke all on store.orders_to_ship
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.orders_to_ship to "x-admin",
  "fulfillment";

-- table_2: what is actually selling
create or replace view store.top_products
with
  (security_invoker = true) as
select
  p.name as product,
  b.name as brand,
  coalesce(sum(oi.quantity), 0) as units,
  round(coalesce(sum(oi.line_total), 0), 0) as revenue,
  p.inventory_quantity as in_stock,
  '/store/resource/products/' || p.id || '/detail' as link
from
  store.products p
  left join store.brands b on b.id = p.brand_id
  left join store.product_variants v on v.product_id = p.id
  left join store.order_items oi on oi.variant_id = v.id
  left join store.orders o on o.id = oi.order_id
  and o.status <> 'cancelled'
group by
  p.id,
  p.name,
  b.name,
  p.inventory_quantity
order by
  revenue desc
limit
  10;

revoke all on store.top_products
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.top_products to "x-admin",
  "merchandiser";

-- list_1: what to reorder
create or replace view store.low_stock_alerts
with
  (security_invoker = true) as
select
  v.sku || ' — ' || p.name as title,
  w.code || ' · ' || l.available || ' available, reorder at ' || l.reorder_point as description,
  'package-x' as icon,
  case
    when l.available <= 0 then 'destructive'
    else 'warning'
  end as variant,
  '/store/resource/inventory_levels/' || l.id || '/detail' as link
from
  store.inventory_levels l
  join store.product_variants v on v.id = l.variant_id
  join store.products p on p.id = v.product_id
  join store.warehouses w on w.id = l.warehouse_id
where
  l.is_below_reorder_point
order by
  l.available asc
limit
  10;

revoke all on store.low_stock_alerts
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.low_stock_alerts to "x-admin",
  "fulfillment",
  "merchandiser";

-- list_2: the returns desk (wider list)
create or replace view store.pending_returns
with
  (security_invoker = true) as
select
  r.rma_number as title,
  c.name || ' · ' || r.reason as description,
  'undo-2' as icon,
  case
    when r.reason = 'damaged' then 'destructive'
    else 'warning'
  end as variant,
  r.status as field_1,
  to_char(r.requested_at, 'Mon DD') as field_2,
  '/store/resource/return_requests/' || r.id || '/detail' as link
from
  store.return_requests r
  join store.customers c on c.id = r.customer_id
where
  r.status in ('requested', 'approved', 'received')
order by
  r.requested_at asc
limit
  10;

revoke all on store.pending_returns
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.pending_returns to "x-admin",
  "fulfillment",
  "support";

-- list_3: the shop floor feed
create or replace view store.recent_store_activity
with
  (security_invoker = true) as
select
  coalesce(u.name, c.name, 'A customer') as actor,
  case e.event_type
    when 'created' then 'placed'
    when 'paid' then 'paid for'
    when 'shipped' then 'shipped'
    when 'delivered' then 'received'
    when 'cancelled' then 'cancelled'
    when 'refunded' then 'was refunded on'
    when 'return_requested' then 'opened a return on'
    else 'updated'
  end as action,
  o.order_number as entity,
  to_char(e.occurred_at, 'Mon DD, YYYY') as date,
  '/store/resource/orders/' || o.id || '/detail' as link
from
  store.order_events e
  join store.orders o on o.id = e.order_id
  join store.customers c on c.id = o.customer_id
  left join store.users u on u.id = e.actor_id
order by
  e.occurred_at desc
limit
  10;

revoke all on store.recent_store_activity
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.recent_store_activity to "x-admin",
  "merchandiser",
  "fulfillment",
  "support";

-- list_4: the best customers
create or replace view store.top_customers
with
  (security_invoker = true) as
select
  c.name,
  round(c.total_spent, 0) as value,
  c.customer_group::text as label,
  '/store/resource/customers/' || c.id || '/detail' as link
from
  store.customers c
where
  c.total_spent > 0
order by
  c.total_spent desc
limit
  10;

revoke all on store.top_customers
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.top_customers to "x-admin",
  "merchandiser",
  "support";

-- card_1: moderation queue — shown on the reviews resource page
create or replace view store.pending_reviews_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'star' as icon,
  'reviews awaiting moderation' as label
from
  store.reviews
where
  status = 'pending';

revoke all on store.pending_reviews_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.pending_reviews_count to "x-admin",
  "merchandiser";

-- card_2: healthy against short — shown on the inventory page
create or replace view store.stock_health_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      not is_below_reorder_point
  ) as primary,
  count(*) filter (
    where
      is_below_reorder_point
  ) as secondary,
  'Healthy' as primary_label,
  'Below Reorder' as secondary_label
from
  store.inventory_levels;

revoke all on store.stock_health_split
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.stock_health_split to "x-admin",
  "fulfillment",
  "merchandiser";

-- card_3: return rate — shown on the returns resource page
create or replace view store.return_rate_card
with
  (security_invoker = true) as
select
  (
    select
      count(*)
    from
      store.return_requests
  ) as value,
  round(
    100.0 * (
      select
        count(*)
      from
        store.return_requests
    ) / nullif(
      (
        select
          count(*)
        from
          store.orders
        where
          status <> 'cancelled'
      ),
      0
    ),
    1
  ) as percent;

revoke all on store.return_rate_card
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.return_rate_card to "x-admin",
  "fulfillment",
  "merchandiser",
  "support";

-- card_1: live promotions — shown on the discounts resource page
create or replace view store.active_discounts_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'ticket-percent' as icon,
  'live promotions' as label
from
  store.discounts
where
  status = 'active';

revoke all on store.active_discounts_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.active_discounts_count to "x-admin",
  "merchandiser";

comment on view store.open_orders_count is '{"type": "dashboard_widget", "name": "Open Orders", "description": "Orders still being worked", "widget_type": "card_1"}';

comment on view store.payment_split is '{"type": "dashboard_widget", "name": "Payment Split", "description": "Settled orders vs outstanding balances", "widget_type": "card_2"}';

comment on view store.fulfillment_rate is '{"type": "dashboard_widget", "name": "Fulfillment Rate", "description": "Share of live orders fully shipped", "widget_type": "card_3"}';

comment on view store.order_pipeline_progress is '{"type": "dashboard_widget", "name": "Order Pipeline", "description": "Where the order book sits", "widget_type": "card_4"}';

comment on view store.revenue_by_channel_overview is '{"type": "dashboard_widget", "name": "Revenue By Channel", "description": "Net revenue and where it came from", "widget_type": "card_5"}';

comment on view store.store_pulse is '{"type": "dashboard_widget", "name": "Store Pulse", "description": "Trading, dispatch and stock at a glance", "widget_type": "card_6"}';

comment on view store.recent_orders is '{"type": "dashboard_widget", "name": "Recent Orders", "description": "The last ten orders placed", "widget_type": "table_1", "resource": "orders", "url": "/store/resource/orders"}';

comment on view store.orders_to_ship is '{"type": "dashboard_widget", "name": "Dispatch Queue", "description": "Paid and confirmed orders waiting to go out", "widget_type": "table_1", "url": "/store/resource/orders"}';

comment on view store.top_products is '{"type": "dashboard_widget", "name": "Top Products", "description": "Units and revenue by product", "widget_type": "table_2", "url": "/store/resource/products"}';

comment on view store.low_stock_alerts is '{"type": "dashboard_widget", "name": "Low Stock", "description": "Variants at or below their reorder point", "widget_type": "list_1", "url": "/store/resource/inventory_levels"}';

comment on view store.pending_returns is '{"type": "dashboard_widget", "name": "Open Returns", "description": "Returns waiting on the desk", "widget_type": "list_2", "url": "/store/resource/return_requests"}';

comment on view store.recent_store_activity is '{"type": "dashboard_widget", "name": "Recent Activity", "description": "The latest movements across the order book", "widget_type": "list_3", "url": "/store/resource/orders"}';

comment on view store.top_customers is '{"type": "dashboard_widget", "name": "Top Customers", "description": "Customers ranked by lifetime spend", "widget_type": "list_4", "url": "/store/resource/customers"}';

comment on view store.pending_reviews_count is '{"type": "dashboard_widget", "name": "Awaiting Moderation", "description": "Reviews queued for a decision", "widget_type": "card_1", "resource": "reviews"}';

comment on view store.stock_health_split is '{"type": "dashboard_widget", "name": "Stock Health", "description": "Healthy stock lines vs those below reorder", "widget_type": "card_2", "resource": "inventory_levels"}';

comment on view store.return_rate_card is '{"type": "dashboard_widget", "name": "Return Rate", "description": "Returns as a share of live orders", "widget_type": "card_3", "resource": "return_requests"}';

comment on view store.active_discounts_count is '{"type": "dashboard_widget", "name": "Live Promotions", "description": "Discounts currently running", "widget_type": "card_1", "resource": "discounts"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: the order book by status
create or replace view store.orders_by_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  store.orders
group by
  status;

revoke all on store.orders_by_status_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.orders_by_status_pie to "x-admin",
  "merchandiser",
  "fulfillment",
  "support";

-- Bar: revenue and units by category
create or replace view store.revenue_by_category_bar
with
  (security_invoker = true) as
select
  c.name as label,
  round(coalesce(sum(oi.line_total), 0), 0) as revenue,
  coalesce(sum(oi.quantity), 0) as units,
  count(distinct p.id) as products
from
  store.categories c
  left join store.products p on p.category_id = c.id
  left join store.product_variants v on v.product_id = p.id
  left join store.order_items oi on oi.variant_id = v.id
  left join store.orders o on o.id = oi.order_id
  and o.status <> 'cancelled'
group by
  c.id,
  c.name
order by
  revenue desc;

revoke all on store.revenue_by_category_bar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.revenue_by_category_bar to "x-admin",
  "merchandiser";

-- Line: orders and revenue over the last 14 days
create or replace view store.daily_sales_line
with
  (security_invoker = true) as
select
  to_char(d.day, 'Mon DD') as date,
  (
    select
      count(*)
    from
      store.orders o
    where
      o.placed_at::date = d.day
      and o.status <> 'cancelled'
  ) as orders,
  (
    select
      round(coalesce(sum(o.grand_total), 0), 0)
    from
      store.orders o
    where
      o.placed_at::date = d.day
      and o.status <> 'cancelled'
  ) as revenue
from
  generate_series(current_date - 13, current_date, interval '1 day') as d (day)
order by
  d.day;

revoke all on store.daily_sales_line
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.daily_sales_line to "x-admin",
  "merchandiser",
  "fulfillment";

-- Area: weekly revenue split by channel
create or replace view store.revenue_composition_area
with
  (security_invoker = true) as
select
  to_char(date_trunc('week', o.placed_at), 'Mon DD') as date,
  round(
    coalesce(
      sum(o.grand_total) filter (
        where
          o.channel = 'web'
      ),
      0
    ),
    0
  ) as web,
  round(
    coalesce(
      sum(o.grand_total) filter (
        where
          o.channel = 'mobile_app'
      ),
      0
    ),
    0
  ) as mobile,
  round(
    coalesce(
      sum(o.grand_total) filter (
        where
          o.channel in ('marketplace', 'pos', 'phone')
      ),
      0
    ),
    0
  ) as other
from
  store.orders o
where
  o.status <> 'cancelled'
  and o.placed_at >= current_timestamp - interval '56 days'
group by
  date_trunc('week', o.placed_at)
order by
  date_trunc('week', o.placed_at);

revoke all on store.revenue_composition_area
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.revenue_composition_area to "x-admin",
  "merchandiser";

-- Radar: how each category performs across three axes
create or replace view store.category_scorecard_radar
with
  (security_invoker = true) as
select
  c.name as metric,
  count(distinct p.id) as products,
  coalesce(sum(oi.quantity), 0) as units_sold,
  coalesce(round(avg(p.average_rating)::numeric, 1), 0) as rating
from
  store.categories c
  left join store.products p on p.category_id = c.id
  left join store.product_variants v on v.product_id = p.id
  left join store.order_items oi on oi.variant_id = v.id
group by
  c.id,
  c.name
order by
  units_sold desc;

revoke all on store.category_scorecard_radar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.category_scorecard_radar to "x-admin",
  "merchandiser";

-- Pie: where orders come from — shown on the orders resource page
create or replace view store.orders_by_channel_pie
with
  (security_invoker = true) as
select
  channel::text as label,
  count(*) as value
from
  store.orders
where
  status <> 'cancelled'
group by
  channel;

revoke all on store.orders_by_channel_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.orders_by_channel_pie to "x-admin",
  "merchandiser",
  "fulfillment";

-- Pie: the book by segment — shown on the customers resource page
create or replace view store.customers_by_group_pie
with
  (security_invoker = true) as
select
  customer_group::text as label,
  count(*) as value
from
  store.customers
group by
  customer_group;

revoke all on store.customers_by_group_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.customers_by_group_pie to "x-admin",
  "merchandiser",
  "support";

-- Bar: the rating distribution — shown on the reviews resource page
create or replace view store.reviews_by_rating_bar
with
  (security_invoker = true) as
select
  round(rating)::text || ' star' as label,
  count(*) as reviews,
  count(*) filter (
    where
      is_verified_purchase
  ) as verified
from
  store.reviews
where
  status = 'approved'
group by
  round(rating)
order by
  round(rating) desc;

revoke all on store.reviews_by_rating_bar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.reviews_by_rating_bar to "x-admin",
  "merchandiser";

-- Line: stock in and out — shown on the ledger resource page
create or replace view store.inventory_flow_line
with
  (security_invoker = true) as
select
  to_char(d.day, 'Mon DD') as date,
  (
    select
      coalesce(sum(m.quantity), 0)
    from
      store.inventory_movements m
    where
      m.occurred_at::date = d.day
      and m.quantity > 0
  ) as goods_in,
  (
    select
      coalesce(abs(sum(m.quantity)), 0)
    from
      store.inventory_movements m
    where
      m.occurred_at::date = d.day
      and m.quantity < 0
  ) as goods_out
from
  generate_series(current_date - 13, current_date, interval '1 day') as d (day)
order by
  d.day;

revoke all on store.inventory_flow_line
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on store.inventory_flow_line to "x-admin",
  "fulfillment",
  "merchandiser";

comment on view store.orders_by_status_pie is '{"type": "chart", "name": "Orders By Status", "description": "The order book grouped by status", "chart_type": "pie"}';

comment on view store.revenue_by_category_bar is '{"type": "chart", "name": "Revenue By Category", "description": "Revenue, units and range depth per category", "chart_type": "bar", "format": "currency"}';

comment on view store.daily_sales_line is '{"type": "chart", "name": "Daily Sales", "description": "Orders and revenue over 14 days", "chart_type": "line"}';

comment on view store.revenue_composition_area is '{"type": "chart", "name": "Revenue By Channel", "description": "Weekly revenue split across sales channels", "chart_type": "area", "format": "currency"}';

comment on view store.category_scorecard_radar is '{"type": "chart", "name": "Category Scorecard", "description": "Range depth, units sold and rating per category", "chart_type": "radar"}';

comment on view store.orders_by_channel_pie is '{"type": "chart", "name": "Orders By Channel", "description": "Where orders are placed", "chart_type": "pie", "resource": "orders"}';

comment on view store.customers_by_group_pie is '{"type": "chart", "name": "Customers By Segment", "description": "How the book splits across segments", "chart_type": "pie", "resource": "customers"}';

comment on view store.reviews_by_rating_bar is '{"type": "chart", "name": "Rating Distribution", "description": "Approved reviews by star rating", "chart_type": "bar", "resource": "reviews"}';

comment on view store.inventory_flow_line is '{"type": "chart", "name": "Stock Flow", "description": "Units received against units shipped over 14 days", "chart_type": "line", "resource": "inventory_movements"}';

----------------------------------------------------------------
-- Audit triggers (INSERT/UPDATE fire AFTER, DELETE must fire BEFORE
-- so the row still exists when it is captured)
--
-- store.order_events and store.inventory_movements are left out:
-- both are already append-only ledgers of exactly this kind.
----------------------------------------------------------------
create trigger audit_store_brands_insert
after insert on store.brands for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_brands_update
after update on store.brands for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_brands_delete
before delete on store.brands for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_categories_insert
after insert on store.categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_categories_update
after update on store.categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_categories_delete
before delete on store.categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_products_insert
after insert on store.products for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_products_update
after update on store.products for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_products_delete
before delete on store.products for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_product_costs_insert
after insert on store.product_costs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_product_costs_update
after update on store.product_costs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_product_costs_delete
before delete on store.product_costs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_variants_insert
after insert on store.product_variants for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_variants_update
after update on store.product_variants for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_variants_delete
before delete on store.product_variants for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_warehouses_insert
after insert on store.warehouses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_warehouses_update
after update on store.warehouses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_warehouses_delete
before delete on store.warehouses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_inventory_levels_insert
after insert on store.inventory_levels for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_inventory_levels_update
after update on store.inventory_levels for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_inventory_levels_delete
before delete on store.inventory_levels for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_customers_insert
after insert on store.customers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_customers_update
after update on store.customers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_customers_delete
before delete on store.customers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_addresses_insert
after insert on store.addresses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_addresses_update
after update on store.addresses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_addresses_delete
before delete on store.addresses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_discounts_insert
after insert on store.discounts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_discounts_update
after update on store.discounts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_discounts_delete
before delete on store.discounts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_orders_insert
after insert on store.orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_orders_update
after update on store.orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_orders_delete
before delete on store.orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_order_items_insert
after insert on store.order_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_order_items_update
after update on store.order_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_order_items_delete
before delete on store.order_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_payments_insert
after insert on store.payments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_payments_update
after update on store.payments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_payments_delete
before delete on store.payments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_shipments_insert
after insert on store.shipments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_shipments_update
after update on store.shipments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_shipments_delete
before delete on store.shipments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_returns_insert
after insert on store.return_requests for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_returns_update
after update on store.return_requests for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_returns_delete
before delete on store.return_requests for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_return_items_insert
after insert on store.return_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_return_items_update
after update on store.return_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_return_items_delete
before delete on store.return_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_reviews_insert
after insert on store.reviews for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_reviews_update
after update on store.reviews for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_reviews_delete
before delete on store.reviews for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_store_settings_insert
after insert on store.store_settings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_store_store_settings_update
after update on store.store_settings for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
--
-- supasheet.create_notification() is service_role-only, so every
-- caller below is a `security definer set search_path = ''` trigger.
--
-- "Operations" is resolved as everyone who can update store.orders:
-- that grant is held by "fulfillment" and "x-admin" but not by
-- "merchandiser" or "support", which makes it a precise stand-in for
-- the dispatch desk without a second source of truth to keep in sync.
-- "Merchandising" is resolved the same way against store.products.
----------------------------------------------------------------
create or replace function store.trg_orders_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_shopper    uuid;
    v_type       text;
    v_title      text;
    v_body       text;
begin
    select c.user_id into v_shopper from store.customers c where c.id = new.customer_id;

    if tg_op = 'INSERT' then
        v_type  := 'store_order_placed';
        v_title := 'New order';
        v_body  := new.order_number || ' — ' || round(new.grand_total, 0) || ' ' || new.currency;
        v_recipients := supasheet.get_users_with_table_privilege('store', 'orders', 'update');
    elsif new.payment_status = 'paid' and old.payment_status <> 'paid' then
        v_type  := 'store_order_paid';
        v_title := 'Payment received';
        v_body  := new.order_number || ' settled at ' || round(new.paid_total, 0) || ' ' || new.currency;
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('store', 'orders', 'update') || array[v_shopper],
            null
        );
    elsif new.status = 'cancelled' and old.status <> 'cancelled' then
        v_type  := 'store_order_cancelled';
        v_title := 'Order cancelled';
        v_body  := new.order_number || ': ' || coalesce(new.cancel_reason, 'no reason recorded');
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('store', 'orders', 'update') || array[v_shopper],
            null
        );
    elsif new.fulfillment_status = 'fulfilled' and old.fulfillment_status <> 'fulfilled' then
        v_type  := 'store_order_fulfilled';
        v_title := 'Order on its way';
        v_body  := new.order_number || ' has been dispatched.';
        v_recipients := array_remove(array[v_shopper], null);
    else
        return new;
    end if;

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'order_id',     new.id,
            'order_number', new.order_number,
            'status',       new.status,
            'total',        new.grand_total,
            'customer_id',  new.customer_id
        ),
        '/store/resource/orders/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists orders_notify on store.orders;

create trigger orders_notify
after insert or update of status,
payment_status,
fulfillment_status on store.orders for each row
execute function store.trg_orders_notify ();

-- Stock: tell the dispatch desk the moment a line drops below its
-- reorder point, and only on the crossing rather than every movement.
create or replace function store.trg_inventory_low_stock_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_sku        text;
    v_product    text;
begin
    if not new.is_below_reorder_point or old.is_below_reorder_point then
        return new;
    end if;

    select v.sku, p.name into v_sku, v_product
    from store.product_variants v
    join store.products p on p.id = v.product_id
    where v.id = new.variant_id;

    v_recipients := supasheet.get_users_with_table_privilege('store', 'inventory_levels', 'update');

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'store_low_stock',
        'Low stock',
        coalesce(v_sku, 'A variant') || ' (' || coalesce(v_product, 'unknown product') || ') is down to '
          || new.available || ', reorder point is ' || new.reorder_point || '.',
        v_recipients,
        jsonb_build_object(
            'variant_id',  new.variant_id,
            'warehouse_id', new.warehouse_id,
            'available',   new.available
        ),
        '/store/resource/inventory_levels/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists inventory_low_stock_notify on store.inventory_levels;

-- Deliberately NOT scoped with `update of ...`: `UPDATE OF column`
-- fires on what a statement mentions in its SET list, and the stock
-- ledger only ever sets on_hand — available and the reorder flag are
-- derived afterwards by the BEFORE trigger. Scoping this to those
-- derived columns would mean the alert never fired at all. The
-- crossing test inside the function is what keeps it quiet.
create trigger inventory_low_stock_notify
after update on store.inventory_levels for each row
execute function store.trg_inventory_low_stock_notify ();

-- Returns and reviews both land on somebody's desk.
create or replace function store.trg_returns_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if tg_op = 'UPDATE' and new.status is not distinct from old.status then
        return new;
    end if;

    if tg_op = 'INSERT' then
        v_recipients := supasheet.get_users_with_table_privilege('store', 'return_requests', 'update');

        if array_length(v_recipients, 1) is null then
            return new;
        end if;

        perform supasheet.create_notification(
            'store_return_requested',
            'Return requested',
            new.rma_number || ' — ' || new.reason::text,
            v_recipients,
            jsonb_build_object('return_id', new.id, 'order_id', new.order_id, 'reason', new.reason),
            '/store/resource/return_requests/' || new.id::text || '/detail'
        );
    elsif new.status = 'refunded' then
        select array_remove(array[c.user_id], null) into v_recipients
        from store.customers c
        where c.id = new.customer_id;

        if array_length(v_recipients, 1) is null then
            return new;
        end if;

        perform supasheet.create_notification(
            'store_return_refunded',
            'Refund on its way',
            new.rma_number || ' has been refunded: ' || round(new.refund_amount, 0),
            v_recipients,
            jsonb_build_object('return_id', new.id, 'refund_amount', new.refund_amount),
            '/store/resource/return_requests/' || new.id::text || '/detail'
        );
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists returns_notify on store.return_requests;

create trigger returns_notify
after insert or update of status on store.return_requests for each row
execute function store.trg_returns_notify ();

create or replace function store.trg_reviews_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_product    text;
begin
    if new.status <> 'pending' then
        return new;
    end if;

    select name into v_product from store.products where id = new.product_id;

    v_recipients := supasheet.get_users_with_table_privilege('store', 'products', 'update');

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'store_review_pending',
        'Review awaiting moderation',
        round(new.rating) || ' stars on ' || coalesce(v_product, 'a product')
          || coalesce(': ' || left(new.title, 80), ''),
        v_recipients,
        jsonb_build_object('review_id', new.id, 'product_id', new.product_id, 'rating', new.rating),
        '/store/resource/reviews/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists reviews_notify on store.reviews;

create trigger reviews_notify
after insert on store.reviews for each row
execute function store.trg_reviews_notify ();

-- Comments: pair the per-record comment system with notifications.
-- The trigger lives on the CENTRAL supasheet.comments table and
-- filters down to this schema's tables.
create or replace function store.trg_store_comments_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.schema_name <> 'store'
       or new.table_name not in ('orders', 'products', 'customers', 'return_requests') then
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('store', new.table_name, 'update'),
        new.created_by
    );

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'store_comment_added',
        'New comment on ' || new.table_name,
        left(new.content, 140),
        v_recipients,
        jsonb_build_object('record_id', new.record_id, 'table_name', new.table_name),
        '/store/resource/' || new.table_name || '/' || new.record_id::text || '/comment'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists store_comments_notify on supasheet.comments;

create trigger store_comments_notify
after insert on supasheet.comments for each row
execute function store.trg_store_comments_notify ();

----------------------------------------------------------------
-- Refresh the metadata catalog (materialized views — NOT automatic)
----------------------------------------------------------------
select
  supasheet.refresh_metadata ();
