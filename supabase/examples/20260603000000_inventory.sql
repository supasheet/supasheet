create schema if not exists inventory;

grant usage on schema inventory to authenticated;

----------------------------------------------------------------
-- Enums (must commit before use)
----------------------------------------------------------------
begin;

create type inventory.warehouse_type as enum(
  'main',
  'satellite',
  'fulfillment',
  'returns',
  'cold_storage'
);

create type inventory.supplier_status as enum('active', 'pending', 'on_hold', 'inactive');

create type inventory.product_status as enum(
  'active',
  'discontinued',
  'preorder',
  'backorder',
  'archived'
);

create type inventory.stock_status as enum(
  'in_stock',
  'low_stock',
  'out_of_stock',
  'overstocked'
);

create type inventory.po_status as enum(
  'draft',
  'submitted',
  'confirmed',
  'partially_received',
  'received',
  'cancelled'
);

create type inventory.shipment_status as enum(
  'pending',
  'preparing',
  'shipped',
  'in_transit',
  'delivered',
  'returned',
  'cancelled'
);

create type inventory.shipment_carrier as enum('ups', 'fedex', 'usps', 'dhl', 'freight', 'other');

create type inventory.movement_type as enum(
  'purchase_in',
  'sale_out',
  'transfer_in',
  'transfer_out',
  'adjustment',
  'return_in',
  'damage_out'
);

commit;

----------------------------------------------------------------
-- Users mirror view
----------------------------------------------------------------
create or replace view inventory.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on inventory.users
from
  authenticated,
  service_role;

grant
select
  on inventory.users to "x-admin";

----------------------------------------------------------------
-- Warehouses
----------------------------------------------------------------
create table inventory.warehouses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null,
  code varchar(50) unique not null,
  type inventory.warehouse_type default 'main',
  description supasheet.RICH_TEXT,
  cover supasheet.file,
  address text,
  city varchar(255),
  country varchar(255),
  capacity integer,
  manager_user_id uuid references supasheet.users (id) on delete set null,
  is_active boolean default true,
  color supasheet.COLOR,
  tags varchar(255) [],
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column inventory.warehouses.type is '{
    "progress": false,
    "values": {
        "main":         {"variant": "success",   "icon": "Warehouse"},
        "satellite":    {"variant": "info",      "icon": "Building2"},
        "fulfillment":  {"variant": "warning",   "icon": "PackageCheck"},
        "returns":      {"variant": "outline",   "icon": "Undo2"},
        "cold_storage": {"variant": "info",      "icon": "Snowflake"}
    }
}';

comment on table inventory.warehouses is '{
    "icon": "Warehouse",
    "display": "block",
    "primary_view": "gallery",
    "views": [
        {
            "id": "gallery",
            "name": "Warehouse Gallery",
            "type": "gallery",
            "cover": "cover",
            "title": "name",
            "description": "city",
            "badge": "type"
        },
        {
            "id": "kanban",
            "name": "Warehouses By Type",
            "type": "kanban",
            "group": "type",
            "title": "name",
            "description": "city",
            "badge": "type"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "name",
                    "code",
                    "type",
                    "description",
                    "cover"
                ]
            },
            {
                "id": "location",
                "title": "Location",
                "fields": [
                    "address",
                    "city",
                    "country",
                    "capacity"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "manager_user_id",
                    "is_active",
                    "color",
                    "tags"
                ]
            },
            {
                "id": "extras",
                "title": "Notes",
                "collapsible": true,
                "fields": [
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "name",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "users",
                "on": "manager_user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column inventory.warehouses.cover is '{"accept":"image/*"}';

revoke all on table inventory.warehouses
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table inventory.warehouses to "x-admin";

create index idx_inv_warehouses_type on inventory.warehouses (type);

create index idx_inv_warehouses_manager_user_id on inventory.warehouses (manager_user_id);

create index idx_inv_warehouses_country on inventory.warehouses (country);

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

----------------------------------------------------------------
-- Suppliers
----------------------------------------------------------------
create table inventory.suppliers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(500) not null,
  code varchar(50) unique,
  status inventory.supplier_status default 'active',
  contact_name varchar(255),
  email supasheet.EMAIL,
  phone supasheet.TEL,
  website supasheet.URL,
  address text,
  city varchar(255),
  country varchar(255),
  lead_time_days integer,
  payment_terms varchar(100),
  tax_id varchar(100),
  rating supasheet.RATING,
  logo supasheet.file,
  description supasheet.RICH_TEXT,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column inventory.suppliers.status is '{
    "progress": true,
    "values": {
        "active":   {"variant": "success",     "icon": "CircleCheck"},
        "pending":  {"variant": "warning",     "icon": "Clock"},
        "on_hold":  {"variant": "warning",     "icon": "PauseCircle"},
        "inactive": {"variant": "outline",     "icon": "Ban"}
    }
}';

comment on table inventory.suppliers is '{
    "icon": "Factory",
    "display": "block",
    "primary_view": "gallery",
    "views": [
        {
            "id": "gallery",
            "name": "Supplier Gallery",
            "type": "gallery",
            "cover": "logo",
            "title": "name",
            "description": "city",
            "badge": "status"
        },
        {
            "id": "kanban",
            "name": "Suppliers By Status",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "contact_name",
            "badge": "country"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "name",
                    "code",
                    "status",
                    "logo",
                    "description"
                ]
            },
            {
                "id": "contact",
                "title": "Contact",
                "fields": [
                    "contact_name",
                    "email",
                    "phone",
                    "website"
                ]
            },
            {
                "id": "location",
                "title": "Location",
                "fields": [
                    "address",
                    "city",
                    "country"
                ]
            },
            {
                "id": "commercial",
                "title": "Commercial",
                "fields": [
                    "lead_time_days",
                    "payment_terms",
                    "tax_id",
                    "rating"
                ]
            },
            {
                "id": "extras",
                "title": "Tags & Notes",
                "collapsible": true,
                "fields": [
                    "tags",
                    "color",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "name",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "users",
                "on": "user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column inventory.suppliers.logo is '{"accept":"image/*"}';

revoke all on table inventory.suppliers
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table inventory.suppliers to "x-admin";

create index idx_inv_suppliers_user_id on inventory.suppliers (user_id);

create index idx_inv_suppliers_status on inventory.suppliers (status);

create index idx_inv_suppliers_country on inventory.suppliers (country);

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

----------------------------------------------------------------
-- Products
----------------------------------------------------------------
create table inventory.products (
  id uuid primary key default extensions.uuid_generate_v4 (),
  sku varchar(100) unique not null,
  name varchar(500) not null,
  barcode varchar(100),
  status inventory.product_status default 'active',
  category varchar(255),
  brand varchar(255),
  description supasheet.RICH_TEXT,
  image supasheet.file,
  attachments supasheet.file,
  unit_of_measure varchar(50) default 'each',
  weight numeric(10, 3),
  dimensions varchar(100),
  cost_price numeric(12, 2) default 0,
  list_price numeric(12, 2) default 0,
  currency varchar(3) default 'USD',
  reorder_point integer default 0,
  reorder_quantity integer default 0,
  safety_stock integer default 0,
  default_supplier_id uuid references inventory.suppliers (id) on delete set null,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column inventory.products.status is '{
    "progress": true,
    "values": {
        "active":       {"variant": "success",     "icon": "CircleCheck"},
        "discontinued": {"variant": "destructive", "icon": "XCircle"},
        "preorder":     {"variant": "info",        "icon": "Clock"},
        "backorder":    {"variant": "warning",     "icon": "AlertTriangle"},
        "archived":     {"variant": "outline",     "icon": "Archive"}
    }
}';

comment on table inventory.products is '{
    "icon": "Package",
    "display": "block",
    "primary_view": "gallery",
    "views": [
        {
            "id": "gallery",
            "name": "Product Catalog",
            "type": "gallery",
            "cover": "image",
            "title": "name",
            "description": "sku",
            "badge": "status"
        },
        {
            "id": "kanban",
            "name": "Products By Status",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "category",
            "badge": "category"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Identity",
                "fields": [
                    "sku",
                    "name",
                    "barcode",
                    "status",
                    "image"
                ]
            },
            {
                "id": "classification",
                "title": "Classification",
                "fields": [
                    "category",
                    "brand",
                    "unit_of_measure",
                    "description"
                ]
            },
            {
                "id": "physical",
                "title": "Physical",
                "fields": [
                    "weight",
                    "dimensions"
                ]
            },
            {
                "id": "pricing",
                "title": "Pricing",
                "fields": [
                    "cost_price",
                    "list_price",
                    "currency"
                ]
            },
            {
                "id": "replenishment",
                "title": "Replenishment",
                "fields": [
                    "reorder_point",
                    "reorder_quantity",
                    "safety_stock",
                    "default_supplier_id"
                ]
            },
            {
                "id": "extras",
                "title": "Tags, Attachments & Notes",
                "collapsible": true,
                "fields": [
                    "tags",
                    "color",
                    "attachments",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "name",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "suppliers",
                "on": "default_supplier_id",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "users",
                "on": "user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column inventory.products.image is '{"accept":"image/*"}';

comment on column inventory.products.attachments is '{"accept":"*", "max_files": 10}';

revoke all on table inventory.products
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table inventory.products to "x-admin";

create index idx_inv_products_user_id on inventory.products (user_id);

create index idx_inv_products_status on inventory.products (status);

create index idx_inv_products_category on inventory.products (category);

create index idx_inv_products_brand on inventory.products (brand);

create index idx_inv_products_default_supplier_id on inventory.products (default_supplier_id);

create index idx_inv_products_sku on inventory.products (sku);

alter table inventory.products enable row level security;

create policy products_select on inventory.products for
select
  to authenticated using (true);

create policy products_insert on inventory.products for insert to authenticated
with
  check (true);

create policy products_update on inventory.products
for update
  to authenticated using (true)
with
  check (true);

create policy products_delete on inventory.products for delete to authenticated using (true);

----------------------------------------------------------------
-- Stock levels (warehouse × product)
----------------------------------------------------------------
create table inventory.stock_levels (
  id uuid primary key default extensions.uuid_generate_v4 (),
  warehouse_id uuid not null references inventory.warehouses (id) on delete cascade,
  product_id uuid not null references inventory.products (id) on delete cascade,
  quantity_on_hand integer default 0,
  quantity_reserved integer default 0,
  quantity_available integer generated always as (quantity_on_hand - quantity_reserved) stored,
  bin_location varchar(100),
  last_counted_at timestamptz,
  status inventory.stock_status default 'in_stock',
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (warehouse_id, product_id)
);

comment on column inventory.stock_levels.status is '{
    "progress": true,
    "values": {
        "in_stock":     {"variant": "success",     "icon": "CircleCheck"},
        "low_stock":    {"variant": "warning",     "icon": "AlertTriangle"},
        "out_of_stock": {"variant": "destructive", "icon": "PackageX"},
        "overstocked":  {"variant": "info",        "icon": "Boxes"}
    }
}';

comment on table inventory.stock_levels is '{
    "icon": "Boxes",
    "inline_form": true,
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Stock By Status",
            "type": "kanban",
            "group": "status",
            "title": "bin_location",
            "description": "notes",
            "date": "last_counted_at",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "warehouse_id",
                    "product_id",
                    "bin_location"
                ]
            },
            {
                "id": "quantity",
                "title": "Quantity",
                "fields": [
                    "quantity_on_hand",
                    "quantity_reserved",
                    "quantity_available",
                    "status"
                ]
            },
            {
                "id": "audit",
                "title": "Audit",
                "fields": [
                    "last_counted_at",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "updated_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "warehouses",
                "on": "warehouse_id",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "products",
                "on": "product_id",
                "columns": [
                    "sku",
                    "name"
                ]
            }
        ]
    }
}';

revoke all on table inventory.stock_levels
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table inventory.stock_levels to "x-admin";

create index idx_inv_stock_levels_warehouse_id on inventory.stock_levels (warehouse_id);

create index idx_inv_stock_levels_product_id on inventory.stock_levels (product_id);

create index idx_inv_stock_levels_status on inventory.stock_levels (status);

alter table inventory.stock_levels enable row level security;

create policy stock_levels_select on inventory.stock_levels for
select
  to authenticated using (true);

create policy stock_levels_insert on inventory.stock_levels for insert to authenticated
with
  check (true);

create policy stock_levels_update on inventory.stock_levels
for update
  to authenticated using (true)
with
  check (true);

create policy stock_levels_delete on inventory.stock_levels for delete to authenticated using (true);

----------------------------------------------------------------
-- Purchase orders
----------------------------------------------------------------
create table inventory.purchase_orders (
  id uuid primary key default extensions.uuid_generate_v4 (),
  po_number varchar(50) unique not null,
  supplier_id uuid references inventory.suppliers (id) on delete set null,
  warehouse_id uuid references inventory.warehouses (id) on delete set null,
  status inventory.po_status default 'draft',
  order_date date not null,
  expected_date date,
  received_date date,
  subtotal numeric(14, 2) default 0,
  tax numeric(14, 2) default 0,
  shipping numeric(14, 2) default 0,
  total numeric(14, 2) default 0,
  currency varchar(3) default 'USD',
  description supasheet.RICH_TEXT,
  attachments supasheet.file,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column inventory.purchase_orders.status is '{
    "progress": true,
    "values": {
        "draft":              {"variant": "outline",     "icon": "FileEdit"},
        "submitted":          {"variant": "info",        "icon": "Send"},
        "confirmed":          {"variant": "info",        "icon": "BadgeCheck"},
        "partially_received": {"variant": "warning",     "icon": "PackageOpen"},
        "received":           {"variant": "success",     "icon": "PackageCheck"},
        "cancelled":          {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table inventory.purchase_orders is '{
    "icon": "ClipboardList",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "POs By Status",
            "type": "kanban",
            "group": "status",
            "title": "po_number",
            "description": "description",
            "date": "expected_date",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "PO Calendar",
            "type": "calendar",
            "title": "po_number",
            "badge": "status",
            "start_date": "order_date",
            "end_date": "expected_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "po_number",
                    "supplier_id",
                    "warehouse_id",
                    "status",
                    "description"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "order_date",
                    "expected_date",
                    "received_date"
                ]
            },
            {
                "id": "amounts",
                "title": "Amounts",
                "fields": [
                    "subtotal",
                    "tax",
                    "shipping",
                    "total",
                    "currency"
                ]
            },
            {
                "id": "extras",
                "title": "Tags, Attachments & Notes",
                "collapsible": true,
                "fields": [
                    "tags",
                    "attachments",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "order_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "suppliers",
                "on": "supplier_id",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "warehouses",
                "on": "warehouse_id",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "users",
                "on": "user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column inventory.purchase_orders.attachments is '{"accept":"*", "max_files": 20}';

revoke all on table inventory.purchase_orders
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table inventory.purchase_orders to "x-admin";

create index idx_inv_purchase_orders_user_id on inventory.purchase_orders (user_id);

create index idx_inv_purchase_orders_supplier_id on inventory.purchase_orders (supplier_id);

create index idx_inv_purchase_orders_warehouse_id on inventory.purchase_orders (warehouse_id);

create index idx_inv_purchase_orders_status on inventory.purchase_orders (status);

create index idx_inv_purchase_orders_order_date on inventory.purchase_orders (order_date desc);

create index idx_inv_purchase_orders_expected_date on inventory.purchase_orders (expected_date);

alter table inventory.purchase_orders enable row level security;

create policy purchase_orders_select on inventory.purchase_orders for
select
  to authenticated using (true);

create policy purchase_orders_insert on inventory.purchase_orders for insert to authenticated
with
  check (true);

create policy purchase_orders_update on inventory.purchase_orders
for update
  to authenticated using (true)
with
  check (true);

create policy purchase_orders_delete on inventory.purchase_orders for delete to authenticated using (true);

----------------------------------------------------------------
-- Purchase order items
----------------------------------------------------------------
create table inventory.purchase_order_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  po_id uuid not null references inventory.purchase_orders (id) on delete cascade,
  product_id uuid not null references inventory.products (id) on delete restrict,
  quantity_ordered integer not null default 0,
  quantity_received integer default 0,
  unit_cost numeric(12, 2) not null default 0,
  total_cost numeric(14, 2) generated always as (quantity_ordered * unit_cost) stored,
  notes text,
  created_at timestamptz default current_timestamp
);

comment on table inventory.purchase_order_items is '{
    "icon": "ListChecks",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "po_id",
                    "product_id"
                ]
            },
            {
                "id": "quantity",
                "title": "Quantity & Cost",
                "fields": [
                    "quantity_ordered",
                    "quantity_received",
                    "unit_cost",
                    "total_cost"
                ]
            },
            {
                "id": "extras",
                "title": "Notes",
                "collapsible": true,
                "fields": [
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "created_at",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "purchase_orders",
                "on": "po_id",
                "columns": [
                    "po_number",
                    "status"
                ]
            },
            {
                "table": "products",
                "on": "product_id",
                "columns": [
                    "sku",
                    "name"
                ]
            }
        ]
    }
}';

revoke all on table inventory.purchase_order_items
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table inventory.purchase_order_items to "x-admin";

create index idx_inv_po_items_po_id on inventory.purchase_order_items (po_id);

create index idx_inv_po_items_product_id on inventory.purchase_order_items (product_id);

alter table inventory.purchase_order_items enable row level security;

create policy purchase_order_items_select on inventory.purchase_order_items for
select
  to authenticated using (true);

create policy purchase_order_items_insert on inventory.purchase_order_items for insert to authenticated
with
  check (true);

create policy purchase_order_items_update on inventory.purchase_order_items
for update
  to authenticated using (true)
with
  check (true);

create policy purchase_order_items_delete on inventory.purchase_order_items for delete to authenticated using (true);

----------------------------------------------------------------
-- Shipments
----------------------------------------------------------------
create table inventory.shipments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  shipment_number varchar(50) unique not null,
  warehouse_id uuid references inventory.warehouses (id) on delete set null,
  customer_name varchar(500),
  customer_email supasheet.EMAIL,
  destination_address text,
  destination_city varchar(255),
  destination_country varchar(255),
  status inventory.shipment_status default 'pending',
  carrier inventory.shipment_carrier default 'other',
  tracking_number varchar(255),
  shipped_date timestamptz,
  expected_delivery_date date,
  delivered_date timestamptz,
  weight numeric(10, 3),
  cost numeric(12, 2),
  currency varchar(3) default 'USD',
  description supasheet.RICH_TEXT,
  attachments supasheet.file,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column inventory.shipments.status is '{
    "progress": true,
    "values": {
        "pending":    {"variant": "outline",     "icon": "Clock"},
        "preparing":  {"variant": "info",        "icon": "PackageOpen"},
        "shipped":    {"variant": "info",        "icon": "Send"},
        "in_transit": {"variant": "warning",     "icon": "Truck"},
        "delivered":  {"variant": "success",     "icon": "PackageCheck"},
        "returned":   {"variant": "destructive", "icon": "Undo2"},
        "cancelled":  {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on column inventory.shipments.carrier is '{
    "progress": false,
    "values": {
        "ups":     {"variant": "warning",   "icon": "Truck"},
        "fedex":   {"variant": "info",      "icon": "Truck"},
        "usps":    {"variant": "info",      "icon": "Mail"},
        "dhl":     {"variant": "warning",   "icon": "Truck"},
        "freight": {"variant": "secondary", "icon": "Container"},
        "other":   {"variant": "outline",   "icon": "CircleEllipsis"}
    }
}';

comment on table inventory.shipments is '{
    "icon": "Truck",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Shipments By Status",
            "type": "kanban",
            "group": "status",
            "title": "shipment_number",
            "description": "customer_name",
            "date": "expected_delivery_date",
            "badge": "carrier"
        },
        {
            "id": "calendar",
            "name": "Shipment Calendar",
            "type": "calendar",
            "title": "shipment_number",
            "badge": "status",
            "start_date": "shipped_date",
            "end_date": "expected_delivery_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "shipment_number",
                    "warehouse_id",
                    "status",
                    "carrier",
                    "tracking_number"
                ]
            },
            {
                "id": "customer",
                "title": "Customer",
                "fields": [
                    "customer_name",
                    "customer_email"
                ]
            },
            {
                "id": "destination",
                "title": "Destination",
                "fields": [
                    "destination_address",
                    "destination_city",
                    "destination_country"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "shipped_date",
                    "expected_delivery_date",
                    "delivered_date"
                ]
            },
            {
                "id": "shipping",
                "title": "Shipping",
                "fields": [
                    "weight",
                    "cost",
                    "currency"
                ]
            },
            {
                "id": "extras",
                "title": "Description, Attachments & Notes",
                "collapsible": true,
                "fields": [
                    "description",
                    "attachments",
                    "tags",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "shipped_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "warehouses",
                "on": "warehouse_id",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "users",
                "on": "user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column inventory.shipments.attachments is '{"accept":"*", "max_files": 10}';

revoke all on table inventory.shipments
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table inventory.shipments to "x-admin";

create index idx_inv_shipments_user_id on inventory.shipments (user_id);

create index idx_inv_shipments_warehouse_id on inventory.shipments (warehouse_id);

create index idx_inv_shipments_status on inventory.shipments (status);

create index idx_inv_shipments_carrier on inventory.shipments (carrier);

create index idx_inv_shipments_shipped_date on inventory.shipments (shipped_date desc);

create index idx_inv_shipments_expected_delivery_date on inventory.shipments (expected_delivery_date);

alter table inventory.shipments enable row level security;

create policy shipments_select on inventory.shipments for
select
  to authenticated using (true);

create policy shipments_insert on inventory.shipments for insert to authenticated
with
  check (true);

create policy shipments_update on inventory.shipments
for update
  to authenticated using (true)
with
  check (true);

create policy shipments_delete on inventory.shipments for delete to authenticated using (true);

----------------------------------------------------------------
-- Shipment items
----------------------------------------------------------------
create table inventory.shipment_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  shipment_id uuid not null references inventory.shipments (id) on delete cascade,
  product_id uuid not null references inventory.products (id) on delete restrict,
  quantity integer not null default 0,
  unit_price numeric(12, 2),
  total_price numeric(14, 2) generated always as (quantity * coalesce(unit_price, 0)) stored,
  notes text,
  created_at timestamptz default current_timestamp
);

comment on table inventory.shipment_items is '{
    "icon": "ListChecks",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "shipment_id",
                    "product_id"
                ]
            },
            {
                "id": "quantity",
                "title": "Quantity & Price",
                "fields": [
                    "quantity",
                    "unit_price",
                    "total_price"
                ]
            },
            {
                "id": "extras",
                "title": "Notes",
                "collapsible": true,
                "fields": [
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "created_at",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "shipments",
                "on": "shipment_id",
                "columns": [
                    "shipment_number",
                    "status"
                ]
            },
            {
                "table": "products",
                "on": "product_id",
                "columns": [
                    "sku",
                    "name"
                ]
            }
        ]
    }
}';

revoke all on table inventory.shipment_items
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table inventory.shipment_items to "x-admin";

create index idx_inv_shipment_items_shipment_id on inventory.shipment_items (shipment_id);

create index idx_inv_shipment_items_product_id on inventory.shipment_items (product_id);

alter table inventory.shipment_items enable row level security;

create policy shipment_items_select on inventory.shipment_items for
select
  to authenticated using (true);

create policy shipment_items_insert on inventory.shipment_items for insert to authenticated
with
  check (true);

create policy shipment_items_update on inventory.shipment_items
for update
  to authenticated using (true)
with
  check (true);

create policy shipment_items_delete on inventory.shipment_items for delete to authenticated using (true);

----------------------------------------------------------------
-- Stock movements (audit trail)
----------------------------------------------------------------
create table inventory.stock_movements (
  id uuid primary key default extensions.uuid_generate_v4 (),
  movement_number varchar(50) unique not null,
  type inventory.movement_type not null,
  product_id uuid not null references inventory.products (id) on delete restrict,
  warehouse_id uuid references inventory.warehouses (id) on delete set null,
  destination_warehouse_id uuid references inventory.warehouses (id) on delete set null,
  quantity integer not null default 0,
  unit_cost numeric(12, 2),
  reference_type varchar(50),
  reference_id uuid,
  occurred_at timestamptz default current_timestamp,
  reason text,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp
);

comment on column inventory.stock_movements.type is '{
    "progress": false,
    "values": {
        "purchase_in":  {"variant": "success",     "icon": "PackagePlus"},
        "sale_out":     {"variant": "warning",     "icon": "PackageMinus"},
        "transfer_in":  {"variant": "info",        "icon": "ArrowDownLeft"},
        "transfer_out": {"variant": "info",        "icon": "ArrowUpRight"},
        "adjustment":   {"variant": "secondary",   "icon": "ClipboardEdit"},
        "return_in":    {"variant": "outline",     "icon": "Undo2"},
        "damage_out":   {"variant": "destructive", "icon": "AlertTriangle"}
    }
}';

comment on table inventory.stock_movements is '{
    "icon": "ArrowLeftRight",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Movements By Type",
            "type": "kanban",
            "group": "type",
            "title": "movement_number",
            "description": "reason",
            "date": "occurred_at",
            "badge": "type"
        },
        {
            "id": "calendar",
            "name": "Movement Calendar",
            "type": "calendar",
            "title": "movement_number",
            "badge": "type",
            "start_date": "occurred_at",
            "end_date": "occurred_at"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "movement_number",
                    "type",
                    "occurred_at"
                ]
            },
            {
                "id": "product",
                "title": "Product & Warehouse",
                "fields": [
                    "product_id",
                    "warehouse_id",
                    "destination_warehouse_id"
                ]
            },
            {
                "id": "quantity",
                "title": "Quantity",
                "fields": [
                    "quantity",
                    "unit_cost"
                ]
            },
            {
                "id": "reference",
                "title": "Reference",
                "fields": [
                    "reference_type",
                    "reference_id",
                    "reason"
                ]
            },
            {
                "id": "extras",
                "title": "Notes",
                "collapsible": true,
                "fields": [
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "occurred_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "products",
                "on": "product_id",
                "columns": [
                    "sku",
                    "name"
                ]
            },
            {
                "table": "warehouses",
                "on": "warehouse_id",
                "alias": "warehouse",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "warehouses",
                "on": "destination_warehouse_id",
                "alias": "destination_warehouse",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "users",
                "on": "user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

revoke all on table inventory.stock_movements
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table inventory.stock_movements to "x-admin";

create index idx_inv_stock_movements_user_id on inventory.stock_movements (user_id);

create index idx_inv_stock_movements_product_id on inventory.stock_movements (product_id);

create index idx_inv_stock_movements_warehouse_id on inventory.stock_movements (warehouse_id);

create index idx_inv_stock_movements_destination_warehouse_id on inventory.stock_movements (destination_warehouse_id);

create index idx_inv_stock_movements_type on inventory.stock_movements (type);

create index idx_inv_stock_movements_occurred_at on inventory.stock_movements (occurred_at desc);

alter table inventory.stock_movements enable row level security;

create policy stock_movements_select on inventory.stock_movements for
select
  to authenticated using (true);

create policy stock_movements_insert on inventory.stock_movements for insert to authenticated
with
  check (true);

create policy stock_movements_update on inventory.stock_movements
for update
  to authenticated using (true)
with
  check (true);

create policy stock_movements_delete on inventory.stock_movements for delete to authenticated using (true);

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view inventory.products_report
with
  (security_invoker = true) as
select
  p.id,
  p.sku,
  p.name,
  p.status,
  p.category,
  p.brand,
  p.cost_price,
  p.list_price,
  p.currency,
  s.name as default_supplier,
  p.reorder_point,
  coalesce(sum(sl.quantity_on_hand), 0)::int as total_on_hand,
  coalesce(sum(sl.quantity_reserved), 0)::int as total_reserved,
  coalesce(sum(sl.quantity_available), 0)::int as total_available,
  (
    coalesce(sum(sl.quantity_on_hand), 0) * p.cost_price
  ) as inventory_value,
  p.created_at,
  p.updated_at
from
  inventory.products p
  left join inventory.suppliers s on s.id = p.default_supplier_id
  left join inventory.stock_levels sl on sl.product_id = p.id
group by
  p.id,
  s.name;

revoke all on inventory.products_report
from
  authenticated,
  service_role;

grant
select
  on inventory.products_report to "x-admin";

comment on view inventory.products_report is '{"type": "report", "name": "Products Report", "description": "Products with aggregated stock levels and inventory value"}';

create or replace view inventory.purchase_orders_report
with
  (security_invoker = true) as
select
  po.id,
  po.po_number,
  s.name as supplier,
  w.name as warehouse,
  po.status,
  po.order_date,
  po.expected_date,
  po.received_date,
  po.total,
  po.currency,
  case
    when po.status = 'received' then 0
    when po.expected_date is null then null
    else greatest(0, (current_date - po.expected_date))::int
  end as days_overdue,
  count(poi.id) as line_count,
  coalesce(sum(poi.quantity_ordered), 0)::int as units_ordered,
  coalesce(sum(poi.quantity_received), 0)::int as units_received,
  po.created_at
from
  inventory.purchase_orders po
  left join inventory.suppliers s on s.id = po.supplier_id
  left join inventory.warehouses w on w.id = po.warehouse_id
  left join inventory.purchase_order_items poi on poi.po_id = po.id
group by
  po.id,
  s.name,
  w.name;

revoke all on inventory.purchase_orders_report
from
  authenticated,
  service_role;

grant
select
  on inventory.purchase_orders_report to "x-admin";

comment on view inventory.purchase_orders_report is '{"type": "report", "name": "Purchase Orders Report", "description": "POs with supplier, warehouse and receipt progress"}';

create or replace view inventory.shipments_report
with
  (security_invoker = true) as
select
  sh.id,
  sh.shipment_number,
  w.name as warehouse,
  sh.customer_name,
  sh.destination_city,
  sh.destination_country,
  sh.status,
  sh.carrier,
  sh.tracking_number,
  sh.shipped_date,
  sh.expected_delivery_date,
  sh.delivered_date,
  case
    when sh.delivered_date is not null
    and sh.expected_delivery_date is not null then case
      when sh.delivered_date::date <= sh.expected_delivery_date then 'on_time'
      else 'late'
    end
    else null
  end as delivery_outcome,
  count(si.id) as line_count,
  coalesce(sum(si.quantity), 0)::int as units_shipped,
  sh.cost,
  sh.currency
from
  inventory.shipments sh
  left join inventory.warehouses w on w.id = sh.warehouse_id
  left join inventory.shipment_items si on si.shipment_id = sh.id
group by
  sh.id,
  w.name;

revoke all on inventory.shipments_report
from
  authenticated,
  service_role;

grant
select
  on inventory.shipments_report to "x-admin";

comment on view inventory.shipments_report is '{"type": "report", "name": "Shipments Report", "description": "Shipments with delivery outcome and unit counts"}';

create or replace view inventory.low_stock_report
with
  (security_invoker = true) as
select
  p.id as product_id,
  p.sku,
  p.name as product,
  w.name as warehouse,
  sl.bin_location,
  sl.quantity_on_hand,
  sl.quantity_available,
  p.reorder_point,
  p.reorder_quantity,
  p.safety_stock,
  sl.status,
  s.name as default_supplier,
  p.cost_price,
  sl.last_counted_at,
  sl.updated_at
from
  inventory.stock_levels sl
  join inventory.products p on p.id = sl.product_id
  join inventory.warehouses w on w.id = sl.warehouse_id
  left join inventory.suppliers s on s.id = p.default_supplier_id
where
  sl.status in ('low_stock', 'out_of_stock')
  or (
    p.reorder_point > 0
    and sl.quantity_available <= p.reorder_point
  );

revoke all on inventory.low_stock_report
from
  authenticated,
  service_role;

grant
select
  on inventory.low_stock_report to "x-admin";

comment on view inventory.low_stock_report is '{"type": "report", "name": "Low Stock Report", "description": "Products at or below reorder point"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: total inventory value (cost_price × on_hand)
create or replace view inventory.inventory_value_summary
with
  (security_invoker = true) as
select
  coalesce(sum(p.cost_price * sl.quantity_on_hand), 0)::numeric(14, 2) as value,
  'package' as icon,
  'inventory value' as label
from
  inventory.stock_levels sl
  join inventory.products p on p.id = sl.product_id;

revoke all on inventory.inventory_value_summary
from
  authenticated,
  service_role;

grant
select
  on inventory.inventory_value_summary to "x-admin";

-- card_2: in-stock vs at-risk SKUs
create or replace view inventory.stock_status_split
with
  (security_invoker = true) as
select
  count(distinct product_id) filter (
    where
      status = 'in_stock'
  ) as primary,
  count(distinct product_id) filter (
    where
      status in ('low_stock', 'out_of_stock')
  ) as secondary,
  'In stock' as primary_label,
  'At risk' as secondary_label
from
  inventory.stock_levels;

revoke all on inventory.stock_status_split
from
  authenticated,
  service_role;

grant
select
  on inventory.stock_status_split to "x-admin";

-- card_3: open POs value + on-time fulfillment %
create or replace view inventory.open_pos_value
with
  (security_invoker = true) as
select
  coalesce(
    sum(total) filter (
      where
        status in ('submitted', 'confirmed', 'partially_received')
    ),
    0
  )::numeric(14, 2) as value,
  case
    when count(*) filter (
      where
        status = 'received'
        and expected_date is not null
    ) > 0 then round(
      (
        count(*) filter (
          where
            status = 'received'
            and received_date is not null
            and received_date <= expected_date
        )::numeric / count(*) filter (
          where
            status = 'received'
            and expected_date is not null
        )::numeric
      ) * 100,
      1
    )
    else 0
  end as percent
from
  inventory.purchase_orders;

revoke all on inventory.open_pos_value
from
  authenticated,
  service_role;

grant
select
  on inventory.open_pos_value to "x-admin";

-- card_4: stock health (out_of_stock + low + overstocked + overdue POs)
create or replace view inventory.stock_health
with
  (security_invoker = true) as
with
  metrics as (
    select
      (
        select
          count(*)
        from
          inventory.stock_levels
        where
          status = 'out_of_stock'
      ) as out_count,
      (
        select
          count(*)
        from
          inventory.stock_levels
        where
          status = 'low_stock'
      ) as low_count,
      (
        select
          count(*)
        from
          inventory.stock_levels
        where
          status = 'overstocked'
      ) as over_count,
      (
        select
          count(*)
        from
          inventory.purchase_orders
        where
          status in ('submitted', 'confirmed', 'partially_received')
          and expected_date is not null
          and expected_date < current_date
      ) as overdue_pos,
      (
        select
          count(*)
        from
          inventory.stock_levels
      ) as total
  )
select
  (out_count + low_count + over_count + overdue_pos) as current,
  total,
  json_build_array(
    json_build_object('label', 'Out of stock', 'value', out_count),
    json_build_object('label', 'Low stock', 'value', low_count),
    json_build_object('label', 'Overstocked', 'value', over_count),
    json_build_object('label', 'Overdue POs', 'value', overdue_pos)
  ) as segments
from
  metrics;

revoke all on inventory.stock_health
from
  authenticated,
  service_role;

grant
select
  on inventory.stock_health to "x-admin";

-- table_1: recent shipments
create or replace view inventory.recent_shipments
with
  (security_invoker = true) as
select
  shipment_number as number,
  coalesce(customer_name, '') as customer,
  coalesce(status::text, '') as status,
  to_char(coalesce(shipped_date, created_at), 'MM/DD') as date
from
  inventory.shipments
order by
  coalesce(shipped_date, created_at) desc
limit
  10;

revoke all on inventory.recent_shipments
from
  authenticated,
  service_role;

grant
select
  on inventory.recent_shipments to "x-admin";

-- table_2: top suppliers by PO spend
create or replace view inventory.top_suppliers
with
  (security_invoker = true) as
select
  s.name as supplier,
  coalesce(s.country, '') as country,
  count(po.id) as orders,
  coalesce(sum(po.total), 0) as spend
from
  inventory.suppliers s
  left join inventory.purchase_orders po on po.supplier_id = s.id
group by
  s.id,
  s.name,
  s.country
order by
  spend desc nulls last
limit
  10;

revoke all on inventory.top_suppliers
from
  authenticated,
  service_role;

grant
select
  on inventory.top_suppliers to "x-admin";

comment on view inventory.inventory_value_summary is '{"type": "dashboard_widget", "name": "Inventory Value", "description": "Total on-hand value at cost", "widget_type": "card_1"}';

comment on view inventory.stock_status_split is '{"type": "dashboard_widget", "name": "Stock Health Split", "description": "SKUs in stock vs at risk", "widget_type": "card_2"}';

comment on view inventory.open_pos_value is '{"type": "dashboard_widget", "name": "Open POs", "description": "Value of open POs and on-time receipt rate", "widget_type": "card_3"}';

comment on view inventory.stock_health is '{"type": "dashboard_widget", "name": "Stock Health", "description": "At-risk stock and overdue POs", "widget_type": "card_4"}';

comment on view inventory.recent_shipments is '{"type": "dashboard_widget", "name": "Recent Shipments", "description": "Latest 10 shipments", "widget_type": "table_1"}';

comment on view inventory.top_suppliers is '{"type": "dashboard_widget", "name": "Top Suppliers", "description": "Top 10 suppliers by PO spend", "widget_type": "table_2"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: products by category
create or replace view inventory.products_by_category_pie
with
  (security_invoker = true) as
select
  coalesce(category, 'Uncategorized') as label,
  count(*) as value
from
  inventory.products
where
  status = 'active'
group by
  category
order by
  count(*) desc;

revoke all on inventory.products_by_category_pie
from
  authenticated,
  service_role;

grant
select
  on inventory.products_by_category_pie to "x-admin";

-- Bar: stock units by warehouse
create or replace view inventory.stock_by_warehouse_bar
with
  (security_invoker = true) as
select
  w.name as label,
  coalesce(sum(sl.quantity_on_hand), 0)::bigint as on_hand,
  coalesce(sum(sl.quantity_reserved), 0)::bigint as reserved
from
  inventory.warehouses w
  left join inventory.stock_levels sl on sl.warehouse_id = w.id
group by
  w.id,
  w.name
order by
  sum(sl.quantity_on_hand) desc nulls last
limit
  10;

revoke all on inventory.stock_by_warehouse_bar
from
  authenticated,
  service_role;

grant
select
  on inventory.stock_by_warehouse_bar to "x-admin";

-- Line: weekly shipment volume (last 12 weeks)
create or replace view inventory.shipment_volume_line
with
  (security_invoker = true) as
select
  to_char(
    date_trunc('week', coalesce(shipped_date, created_at)),
    'Mon DD'
  ) as date,
  count(*) as shipments,
  count(*) filter (
    where
      status = 'delivered'
  )::bigint as delivered
from
  inventory.shipments
where
  coalesce(shipped_date, created_at) >= current_date - interval '12 weeks'
group by
  date_trunc('week', coalesce(shipped_date, created_at))
order by
  date_trunc('week', coalesce(shipped_date, created_at));

revoke all on inventory.shipment_volume_line
from
  authenticated,
  service_role;

grant
select
  on inventory.shipment_volume_line to "x-admin";

-- Radar: stock movement metrics by type
create or replace view inventory.movement_metrics_radar
with
  (security_invoker = true) as
select
  type::text as metric,
  count(*) as total,
  coalesce(sum(quantity), 0)::bigint as units,
  count(*) filter (
    where
      occurred_at >= current_date - interval '30 days'
  ) as recent
from
  inventory.stock_movements
group by
  type;

revoke all on inventory.movement_metrics_radar
from
  authenticated,
  service_role;

grant
select
  on inventory.movement_metrics_radar to "x-admin";

comment on view inventory.products_by_category_pie is '{"type": "chart", "name": "Products By Category", "description": "Active product count per category", "chart_type": "pie"}';

comment on view inventory.stock_by_warehouse_bar is '{"type": "chart", "name": "Stock By Warehouse", "description": "On-hand vs reserved units per warehouse", "chart_type": "bar"}';

comment on view inventory.shipment_volume_line is '{"type": "chart", "name": "Shipment Volume", "description": "Weekly shipment counts over 12 weeks", "chart_type": "line"}';

comment on view inventory.movement_metrics_radar is '{"type": "chart", "name": "Movement Metrics", "description": "Stock movement counts and units across types", "chart_type": "radar"}';

----------------------------------------------------------------
-- Audit triggers
----------------------------------------------------------------
create trigger audit_inv_warehouses_insert
after insert on inventory.warehouses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_warehouses_update
after update on inventory.warehouses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_warehouses_delete
before delete on inventory.warehouses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_suppliers_insert
after insert on inventory.suppliers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_suppliers_update
after update on inventory.suppliers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_suppliers_delete
before delete on inventory.suppliers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_products_insert
after insert on inventory.products for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_products_update
after update on inventory.products for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_products_delete
before delete on inventory.products for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_stock_levels_insert
after insert on inventory.stock_levels for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_stock_levels_update
after update on inventory.stock_levels for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_stock_levels_delete
before delete on inventory.stock_levels for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_purchase_orders_insert
after insert on inventory.purchase_orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_purchase_orders_update
after update on inventory.purchase_orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_purchase_orders_delete
before delete on inventory.purchase_orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_purchase_order_items_insert
after insert on inventory.purchase_order_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_purchase_order_items_update
after update on inventory.purchase_order_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_purchase_order_items_delete
before delete on inventory.purchase_order_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_shipments_insert
after insert on inventory.shipments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_shipments_update
after update on inventory.shipments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_shipments_delete
before delete on inventory.shipments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_shipment_items_insert
after insert on inventory.shipment_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_shipment_items_update
after update on inventory.shipment_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_shipment_items_delete
before delete on inventory.shipment_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_stock_movements_insert
after insert on inventory.stock_movements for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_stock_movements_update
after update on inventory.stock_movements for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_inv_stock_movements_delete
before delete on inventory.stock_movements for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
-- Stock levels: notify ops on low/out-of-stock transitions
create or replace function inventory.trg_stock_levels_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_product_name text;
    v_warehouse_name text;
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if new.status is not distinct from old.status then
        return new;
    end if;
    if new.status not in ('low_stock', 'out_of_stock') then
        return new;
    end if;

    select name into v_product_name from inventory.products where id = new.product_id;
    select name into v_warehouse_name from inventory.warehouses where id = new.warehouse_id;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('inventory', 'stock_levels', 'update'),
        null
    );

    v_type  := 'inventory_stock_' || new.status::text;
    v_title := 'Stock alert: ' || new.status::text;
    v_body  := coalesce(v_product_name, 'Product') ||
               ' is ' || new.status::text ||
               ' at ' || coalesce(v_warehouse_name, 'a warehouse') ||
               ' (on hand: ' || new.quantity_on_hand::text || ').';

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'stock_level_id',     new.id,
            'product_id',         new.product_id,
            'warehouse_id',       new.warehouse_id,
            'quantity_on_hand',   new.quantity_on_hand,
            'status',             new.status
        ),
        '/inventory/resource/stock_levels/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists stock_levels_notify on inventory.stock_levels;

create trigger stock_levels_notify
after update of status on inventory.stock_levels for each row
execute function inventory.trg_stock_levels_notify ();

-- Purchase orders: notify on submission and receipt
create or replace function inventory.trg_purchase_orders_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_supplier_name text;
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if new.supplier_id is not null then
        select name into v_supplier_name from inventory.suppliers where id = new.supplier_id;
    end if;

    if tg_op = 'INSERT' then
        v_type  := 'inventory_po_created';
        v_title := 'New purchase order';
        v_body  := 'PO ' || new.po_number || ' for ' || coalesce(v_supplier_name, 'supplier') || ' was created.';
    elsif new.status is distinct from old.status and new.status in ('submitted', 'received', 'cancelled') then
        v_type  := 'inventory_po_' || new.status::text;
        v_title := 'PO ' || new.status::text;
        v_body  := 'Purchase order ' || new.po_number || ' is now ' || new.status::text || '.';
    else
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('inventory', 'purchase_orders', 'select') || array[new.user_id],
        null
    );

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'purchase_order_id', new.id,
            'supplier_id',       new.supplier_id,
            'warehouse_id',      new.warehouse_id,
            'status',            new.status,
            'total',             new.total
        ),
        '/inventory/resource/purchase_orders/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists purchase_orders_notify on inventory.purchase_orders;

create trigger purchase_orders_notify
after insert or update of status on inventory.purchase_orders for each row
execute function inventory.trg_purchase_orders_notify ();

-- Shipments: notify on shipped and delivered transitions
create or replace function inventory.trg_shipments_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if tg_op <> 'UPDATE' then
        return new;
    end if;
    if new.status is not distinct from old.status then
        return new;
    end if;
    if new.status not in ('shipped', 'delivered', 'returned') then
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('inventory', 'shipments', 'select') || array[new.user_id],
        null
    );

    v_type  := 'inventory_shipment_' || new.status::text;
    v_title := 'Shipment ' || new.status::text;
    v_body  := 'Shipment ' || new.shipment_number ||
               ' for ' || coalesce(new.customer_name, 'customer') ||
               ' is now ' || new.status::text || '.';

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'shipment_id',     new.id,
            'warehouse_id',    new.warehouse_id,
            'status',          new.status,
            'carrier',         new.carrier,
            'tracking_number', new.tracking_number
        ),
        '/inventory/resource/shipments/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists shipments_notify on inventory.shipments;

create trigger shipments_notify
after update of status on inventory.shipments for each row
execute function inventory.trg_shipments_notify ();
