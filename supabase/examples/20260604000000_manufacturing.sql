create schema if not exists manufacturing;

grant usage on schema manufacturing to authenticated;

----------------------------------------------------------------
-- Enums + permissions (must commit before use)
----------------------------------------------------------------
begin;

create type manufacturing.work_center_type as enum(
  'assembly',
  'machining',
  'packaging',
  'inspection',
  'finishing',
  'storage'
);

create type manufacturing.work_center_status as enum('available', 'busy', 'maintenance', 'offline');

create type manufacturing.bom_status as enum('draft', 'active', 'obsolete', 'archived');

create type manufacturing.routing_status as enum('draft', 'active', 'obsolete');

create type manufacturing.work_order_status as enum(
  'draft',
  'planned',
  'released',
  'in_progress',
  'on_hold',
  'completed',
  'cancelled'
);

create type manufacturing.work_order_priority as enum('low', 'medium', 'high', 'critical');

create type manufacturing.operation_status as enum(
  'pending',
  'in_progress',
  'completed',
  'skipped',
  'failed'
);

create type manufacturing.output_status as enum('good', 'rework', 'scrap', 'pending_inspection');

create type manufacturing.issue_status as enum('reserved', 'issued', 'returned');

commit;

----------------------------------------------------------------
-- Users mirror view
----------------------------------------------------------------
create or replace view manufacturing.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on manufacturing.users
from
  authenticated,
  service_role;

grant
select
  on manufacturing.users to "x-admin",
  "user";

----------------------------------------------------------------
-- Work centers
----------------------------------------------------------------
create table manufacturing.work_centers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(50) unique not null,
  name varchar(255) not null,
  type manufacturing.work_center_type default 'assembly',
  status manufacturing.work_center_status default 'available',
  description supasheet.RICH_TEXT,
  cover supasheet.file,
  location varchar(255),
  capacity_per_hour integer,
  cost_per_hour numeric(10, 2),
  currency varchar(3) default 'USD',
  operator_user_id uuid references supasheet.users (id) on delete set null,
  is_active boolean default true,
  color supasheet.COLOR,
  tags varchar(255) [],
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column manufacturing.work_centers.type is '{
    "progress": false,
    "enums": {
        "assembly":   {"variant": "info",      "icon": "Wrench"},
        "machining":  {"variant": "warning",   "icon": "Cog"},
        "packaging":  {"variant": "secondary", "icon": "Package"},
        "inspection": {"variant": "success",   "icon": "ShieldCheck"},
        "finishing":  {"variant": "info",      "icon": "Sparkles"},
        "storage":    {"variant": "outline",   "icon": "Warehouse"}
    }
}';

comment on column manufacturing.work_centers.status is '{
    "progress": true,
    "enums": {
        "available":   {"variant": "success",     "icon": "CircleCheck"},
        "busy":        {"variant": "warning",     "icon": "Loader"},
        "maintenance": {"variant": "info",        "icon": "Wrench"},
        "offline":     {"variant": "destructive", "icon": "PowerOff"}
    }
}';

comment on table manufacturing.work_centers is '{
    "icon": "Factory",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Work Centers By Status",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "location",
            "badge": "type"
        },
        {
            "id": "gallery",
            "name": "Work Center Gallery",
            "type": "gallery",
            "cover": "cover",
            "title": "name",
            "description": "location",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "code",
                    "name",
                    "type",
                    "status",
                    "description",
                    "cover"
                ]
            },
            {
                "id": "location",
                "title": "Location",
                "fields": [
                    "location",
                    "capacity_per_hour"
                ]
            },
            {
                "id": "cost",
                "title": "Cost",
                "fields": [
                    "cost_per_hour",
                    "currency"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "operator_user_id",
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
                "on": "operator_user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column manufacturing.work_centers.cover is '{"accept":"image/*"}';

revoke all on table manufacturing.work_centers
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.work_centers to "x-admin";

create index idx_mfg_work_centers_type on manufacturing.work_centers (type);

create index idx_mfg_work_centers_status on manufacturing.work_centers (status);

create index idx_mfg_work_centers_operator on manufacturing.work_centers (operator_user_id);

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

----------------------------------------------------------------
-- BOMs (bill of materials, header)
----------------------------------------------------------------
create table manufacturing.boms (
  id uuid primary key default extensions.uuid_generate_v4 (),
  bom_number varchar(50) unique not null,
  name varchar(500) not null,
  version varchar(20) default '1.0',
  product_sku varchar(100) not null,
  product_name varchar(500) not null,
  product_id uuid,
  status manufacturing.bom_status default 'draft',
  output_quantity integer default 1,
  unit_of_measure varchar(50) default 'each',
  description supasheet.RICH_TEXT,
  image supasheet.file,
  attachments supasheet.file,
  effective_from date,
  effective_to date,
  estimated_cost numeric(12, 2),
  currency varchar(3) default 'USD',
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column manufacturing.boms.status is '{
    "progress": true,
    "enums": {
        "draft":    {"variant": "outline",     "icon": "FileEdit"},
        "active":   {"variant": "success",     "icon": "CircleCheck"},
        "obsolete": {"variant": "warning",     "icon": "AlertTriangle"},
        "archived": {"variant": "destructive", "icon": "Archive"}
    }
}';

comment on table manufacturing.boms is '{
    "icon": "ListTree",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "BOMs By Status",
            "type": "kanban",
            "group": "status",
            "title": "product_name",
            "description": "bom_number",
            "date": "effective_from",
            "badge": "version"
        },
        {
            "id": "gallery",
            "name": "BOM Gallery",
            "type": "gallery",
            "cover": "image",
            "title": "product_name",
            "description": "bom_number",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "bom_number",
                    "name",
                    "version",
                    "status",
                    "description",
                    "image"
                ]
            },
            {
                "id": "product",
                "title": "Product",
                "fields": [
                    "product_sku",
                    "product_name",
                    "product_id",
                    "output_quantity",
                    "unit_of_measure"
                ]
            },
            {
                "id": "effective",
                "title": "Effective Dates",
                "fields": [
                    "effective_from",
                    "effective_to"
                ]
            },
            {
                "id": "cost",
                "title": "Cost",
                "fields": [
                    "estimated_cost",
                    "currency"
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
                "id": "product_name",
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

comment on column manufacturing.boms.image is '{"accept":"image/*"}';

comment on column manufacturing.boms.attachments is '{"accept":"*", "maxFiles": 10}';

revoke all on table manufacturing.boms
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.boms to "x-admin";

create index idx_mfg_boms_user_id on manufacturing.boms (user_id);

create index idx_mfg_boms_status on manufacturing.boms (status);

create index idx_mfg_boms_product_sku on manufacturing.boms (product_sku);

create index idx_mfg_boms_product_id on manufacturing.boms (product_id);

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

----------------------------------------------------------------
-- BOM items (component lines)
----------------------------------------------------------------
create table manufacturing.bom_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  bom_id uuid not null references manufacturing.boms (id) on delete cascade,
  line_number integer default 0,
  component_sku varchar(100) not null,
  component_name varchar(500) not null,
  component_id uuid,
  quantity numeric(12, 4) not null default 1,
  unit_of_measure varchar(50) default 'each',
  scrap_pct numeric(5, 2) default 0,
  unit_cost numeric(12, 4) default 0,
  total_cost numeric(14, 4) generated always as (quantity * unit_cost) stored,
  is_optional boolean default false,
  notes text,
  created_at timestamptz default current_timestamp
);

comment on table manufacturing.bom_items is '{
    "icon": "ListChecks",
    "display": "none",
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "bom_id",
                    "line_number"
                ]
            },
            {
                "id": "component",
                "title": "Component",
                "fields": [
                    "component_sku",
                    "component_name",
                    "component_id"
                ]
            },
            {
                "id": "quantity",
                "title": "Quantity",
                "fields": [
                    "quantity",
                    "unit_of_measure",
                    "scrap_pct",
                    "is_optional"
                ]
            },
            {
                "id": "cost",
                "title": "Cost",
                "fields": [
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
                "id": "line_number",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "boms",
                "on": "bom_id",
                "columns": [
                    "bom_number",
                    "product_name"
                ]
            }
        ]
    }
}';

revoke all on table manufacturing.bom_items
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.bom_items to "x-admin";

create index idx_mfg_bom_items_bom_id on manufacturing.bom_items (bom_id);

create index idx_mfg_bom_items_component_sku on manufacturing.bom_items (component_sku);

alter table manufacturing.bom_items enable row level security;

create policy bom_items_select on manufacturing.bom_items for
select
  to authenticated using (true);

create policy bom_items_insert on manufacturing.bom_items for insert to authenticated
with
  check (true);

create policy bom_items_update on manufacturing.bom_items
for update
  to authenticated using (true)
with
  check (true);

create policy bom_items_delete on manufacturing.bom_items for delete to authenticated using (true);

----------------------------------------------------------------
-- Routings (operation sequence templates)
----------------------------------------------------------------
create table manufacturing.routings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  routing_number varchar(50) unique not null,
  name varchar(500) not null,
  version varchar(20) default '1.0',
  product_sku varchar(100),
  product_name varchar(500),
  bom_id uuid references manufacturing.boms (id) on delete set null,
  status manufacturing.routing_status default 'draft',
  description supasheet.RICH_TEXT,
  attachments supasheet.file,
  estimated_minutes integer,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column manufacturing.routings.status is '{
    "progress": true,
    "enums": {
        "draft":    {"variant": "outline", "icon": "FileEdit"},
        "active":   {"variant": "success", "icon": "CircleCheck"},
        "obsolete": {"variant": "warning", "icon": "AlertTriangle"}
    }
}';

comment on table manufacturing.routings is '{
    "icon": "Workflow",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Routings By Status",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "product_name",
            "badge": "version"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "routing_number",
                    "name",
                    "version",
                    "status",
                    "description"
                ]
            },
            {
                "id": "product",
                "title": "Product & BOM",
                "fields": [
                    "product_sku",
                    "product_name",
                    "bom_id"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "estimated_minutes"
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
                "id": "name",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "boms",
                "on": "bom_id",
                "columns": [
                    "bom_number",
                    "product_name"
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

comment on column manufacturing.routings.attachments is '{"accept":"*", "maxFiles": 10}';

revoke all on table manufacturing.routings
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.routings to "x-admin";

create index idx_mfg_routings_user_id on manufacturing.routings (user_id);

create index idx_mfg_routings_bom_id on manufacturing.routings (bom_id);

create index idx_mfg_routings_status on manufacturing.routings (status);

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

----------------------------------------------------------------
-- Routing operations (template steps)
----------------------------------------------------------------
create table manufacturing.routing_operations (
  id uuid primary key default extensions.uuid_generate_v4 (),
  routing_id uuid not null references manufacturing.routings (id) on delete cascade,
  sequence_number integer default 0,
  name varchar(255) not null,
  description supasheet.RICH_TEXT,
  work_center_id uuid references manufacturing.work_centers (id) on delete set null,
  setup_minutes integer default 0,
  run_minutes_per_unit numeric(8, 2) default 0,
  instructions text,
  notes text,
  created_at timestamptz default current_timestamp
);

comment on table manufacturing.routing_operations is '{
    "icon": "ListOrdered",
    "display": "none",
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "routing_id",
                    "sequence_number"
                ]
            },
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "name",
                    "description",
                    "work_center_id"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "setup_minutes",
                    "run_minutes_per_unit"
                ]
            },
            {
                "id": "extras",
                "title": "Instructions & Notes",
                "collapsible": true,
                "fields": [
                    "instructions",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "sequence_number",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "routings",
                "on": "routing_id",
                "columns": [
                    "routing_number",
                    "name"
                ]
            },
            {
                "table": "work_centers",
                "on": "work_center_id",
                "columns": [
                    "code",
                    "name"
                ]
            }
        ]
    }
}';

revoke all on table manufacturing.routing_operations
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.routing_operations to "x-admin";

create index idx_mfg_routing_ops_routing_id on manufacturing.routing_operations (routing_id);

create index idx_mfg_routing_ops_work_center_id on manufacturing.routing_operations (work_center_id);

alter table manufacturing.routing_operations enable row level security;

create policy routing_operations_select on manufacturing.routing_operations for
select
  to authenticated using (true);

create policy routing_operations_insert on manufacturing.routing_operations for insert to authenticated
with
  check (true);

create policy routing_operations_update on manufacturing.routing_operations
for update
  to authenticated using (true)
with
  check (true);

create policy routing_operations_delete on manufacturing.routing_operations for delete to authenticated using (true);

----------------------------------------------------------------
-- Work orders
----------------------------------------------------------------
create table manufacturing.work_orders (
  id uuid primary key default extensions.uuid_generate_v4 (),
  work_order_number varchar(50) unique not null,
  product_sku varchar(100) not null,
  product_name varchar(500) not null,
  product_id uuid,
  bom_id uuid references manufacturing.boms (id) on delete set null,
  routing_id uuid references manufacturing.routings (id) on delete set null,
  status manufacturing.work_order_status default 'draft',
  priority manufacturing.work_order_priority default 'medium',
  quantity_planned integer not null default 1,
  quantity_completed integer default 0,
  quantity_scrapped integer default 0,
  unit_of_measure varchar(50) default 'each',
  planned_start_date date,
  planned_end_date date,
  actual_start_date timestamptz,
  actual_end_date timestamptz,
  estimated_cost numeric(12, 2),
  actual_cost numeric(12, 2),
  currency varchar(3) default 'USD',
  description supasheet.RICH_TEXT,
  attachments supasheet.file,
  sales_order_reference varchar(255),
  assigned_user_id uuid references supasheet.users (id) on delete set null,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column manufacturing.work_orders.status is '{
    "progress": true,
    "enums": {
        "draft":       {"variant": "outline",     "icon": "FileEdit"},
        "planned":     {"variant": "info",        "icon": "Calendar"},
        "released":    {"variant": "info",        "icon": "Send"},
        "in_progress": {"variant": "warning",     "icon": "Loader"},
        "on_hold":     {"variant": "warning",     "icon": "PauseCircle"},
        "completed":   {"variant": "success",     "icon": "CircleCheck"},
        "cancelled":   {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on column manufacturing.work_orders.priority is '{
    "progress": false,
    "enums": {
        "low":      {"variant": "outline",     "icon": "CircleArrowDown"},
        "medium":   {"variant": "info",        "icon": "CircleMinus"},
        "high":     {"variant": "warning",     "icon": "CircleArrowUp"},
        "critical": {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on table manufacturing.work_orders is '{
    "icon": "ClipboardList",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Work Orders By Status",
            "type": "kanban",
            "group": "status",
            "title": "work_order_number",
            "description": "product_name",
            "date": "planned_end_date",
            "badge": "priority"
        },
        {
            "id": "calendar",
            "name": "Production Schedule",
            "type": "calendar",
            "title": "work_order_number",
            "badge": "status",
            "start_date": "planned_start_date",
            "end_date": "planned_end_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "work_order_number",
                    "status",
                    "priority",
                    "description"
                ]
            },
            {
                "id": "product",
                "title": "Product",
                "fields": [
                    "product_sku",
                    "product_name",
                    "product_id",
                    "bom_id",
                    "routing_id"
                ]
            },
            {
                "id": "quantity",
                "title": "Quantity",
                "fields": [
                    "quantity_planned",
                    "quantity_completed",
                    "quantity_scrapped",
                    "unit_of_measure"
                ]
            },
            {
                "id": "schedule",
                "title": "Schedule",
                "fields": [
                    "planned_start_date",
                    "planned_end_date",
                    "actual_start_date",
                    "actual_end_date"
                ]
            },
            {
                "id": "cost",
                "title": "Cost",
                "fields": [
                    "estimated_cost",
                    "actual_cost",
                    "currency"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "assigned_user_id",
                    "sales_order_reference",
                    "tags",
                    "color"
                ]
            },
            {
                "id": "extras",
                "title": "Attachments & Notes",
                "collapsible": true,
                "fields": [
                    "attachments",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "planned_start_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "boms",
                "on": "bom_id",
                "columns": [
                    "bom_number",
                    "product_name"
                ]
            },
            {
                "table": "routings",
                "on": "routing_id",
                "columns": [
                    "routing_number",
                    "name"
                ]
            },
            {
                "table": "users",
                "on": "assigned_user_id",
                "alias": "assigned_user",
                "columns": [
                    "name",
                    "email"
                ]
            },
            {
                "table": "users",
                "on": "user_id",
                "alias": "user",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column manufacturing.work_orders.attachments is '{"accept":"*", "maxFiles": 20}';

revoke all on table manufacturing.work_orders
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.work_orders to "x-admin";

create index idx_mfg_work_orders_user_id on manufacturing.work_orders (user_id);

create index idx_mfg_work_orders_assigned_user_id on manufacturing.work_orders (assigned_user_id);

create index idx_mfg_work_orders_bom_id on manufacturing.work_orders (bom_id);

create index idx_mfg_work_orders_routing_id on manufacturing.work_orders (routing_id);

create index idx_mfg_work_orders_status on manufacturing.work_orders (status);

create index idx_mfg_work_orders_priority on manufacturing.work_orders (priority);

create index idx_mfg_work_orders_planned_start_date on manufacturing.work_orders (planned_start_date desc);

create index idx_mfg_work_orders_product_sku on manufacturing.work_orders (product_sku);

alter table manufacturing.work_orders enable row level security;

create policy work_orders_select on manufacturing.work_orders for
select
  to authenticated using (true);

create policy work_orders_insert on manufacturing.work_orders for insert to authenticated
with
  check (true);

create policy work_orders_update on manufacturing.work_orders
for update
  to authenticated using (true)
with
  check (true);

create policy work_orders_delete on manufacturing.work_orders for delete to authenticated using (true);

----------------------------------------------------------------
-- Work order operations (executed steps)
----------------------------------------------------------------
create table manufacturing.work_order_operations (
  id uuid primary key default extensions.uuid_generate_v4 (),
  work_order_id uuid not null references manufacturing.work_orders (id) on delete cascade,
  routing_operation_id uuid references manufacturing.routing_operations (id) on delete set null,
  work_center_id uuid references manufacturing.work_centers (id) on delete set null,
  sequence_number integer default 0,
  name varchar(255) not null,
  status manufacturing.operation_status default 'pending',
  planned_start_at timestamptz,
  planned_end_at timestamptz,
  actual_start_at timestamptz,
  actual_end_at timestamptz,
  planned_minutes integer default 0,
  actual_minutes integer default 0,
  operator_user_id uuid references supasheet.users (id) on delete set null,
  quantity_good integer default 0,
  quantity_scrap integer default 0,
  instructions text,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column manufacturing.work_order_operations.status is '{
    "progress": true,
    "enums": {
        "pending":     {"variant": "outline",     "icon": "Clock"},
        "in_progress": {"variant": "warning",     "icon": "Loader"},
        "completed":   {"variant": "success",     "icon": "CircleCheck"},
        "skipped":     {"variant": "secondary",   "icon": "SkipForward"},
        "failed":      {"variant": "destructive", "icon": "XCircle"}
    }
}';

comment on table manufacturing.work_order_operations is '{
    "icon": "ListOrdered",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Operations By Status",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "notes",
            "date": "planned_start_at",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Operation Schedule",
            "type": "calendar",
            "title": "name",
            "badge": "status",
            "start_date": "planned_start_at",
            "end_date": "planned_end_at"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "work_order_id",
                    "routing_operation_id",
                    "sequence_number",
                    "name",
                    "status"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "work_center_id",
                    "operator_user_id"
                ]
            },
            {
                "id": "schedule",
                "title": "Schedule",
                "fields": [
                    "planned_start_at",
                    "planned_end_at",
                    "actual_start_at",
                    "actual_end_at"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "planned_minutes",
                    "actual_minutes"
                ]
            },
            {
                "id": "output",
                "title": "Output",
                "fields": [
                    "quantity_good",
                    "quantity_scrap"
                ]
            },
            {
                "id": "extras",
                "title": "Instructions & Notes",
                "collapsible": true,
                "fields": [
                    "instructions",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "sequence_number",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "work_orders",
                "on": "work_order_id",
                "columns": [
                    "work_order_number",
                    "product_name"
                ]
            },
            {
                "table": "work_centers",
                "on": "work_center_id",
                "columns": [
                    "code",
                    "name"
                ]
            },
            {
                "table": "users",
                "on": "operator_user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

revoke all on table manufacturing.work_order_operations
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.work_order_operations to "x-admin";

create index idx_mfg_wo_ops_work_order_id on manufacturing.work_order_operations (work_order_id);

create index idx_mfg_wo_ops_work_center_id on manufacturing.work_order_operations (work_center_id);

create index idx_mfg_wo_ops_operator on manufacturing.work_order_operations (operator_user_id);

create index idx_mfg_wo_ops_status on manufacturing.work_order_operations (status);

create index idx_mfg_wo_ops_planned_start_at on manufacturing.work_order_operations (planned_start_at);

alter table manufacturing.work_order_operations enable row level security;

create policy work_order_operations_select on manufacturing.work_order_operations for
select
  to authenticated using (true);

create policy work_order_operations_insert on manufacturing.work_order_operations for insert to authenticated
with
  check (true);

create policy work_order_operations_update on manufacturing.work_order_operations
for update
  to authenticated using (true)
with
  check (true);

create policy work_order_operations_delete on manufacturing.work_order_operations for delete to authenticated using (true);

----------------------------------------------------------------
-- Material issues (components consumed in WO)
----------------------------------------------------------------
create table manufacturing.material_issues (
  id uuid primary key default extensions.uuid_generate_v4 (),
  issue_number varchar(50) unique not null,
  work_order_id uuid not null references manufacturing.work_orders (id) on delete cascade,
  bom_item_id uuid references manufacturing.bom_items (id) on delete set null,
  component_sku varchar(100) not null,
  component_name varchar(500) not null,
  component_id uuid,
  warehouse_code varchar(50),
  quantity_required numeric(12, 4) not null default 0,
  quantity_issued numeric(12, 4) default 0,
  quantity_returned numeric(12, 4) default 0,
  unit_of_measure varchar(50) default 'each',
  unit_cost numeric(12, 4) default 0,
  total_cost numeric(14, 4) generated always as (quantity_issued * unit_cost) stored,
  status manufacturing.issue_status default 'reserved',
  issued_at timestamptz,
  returned_at timestamptz,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column manufacturing.material_issues.status is '{
    "progress": true,
    "enums": {
        "reserved": {"variant": "outline", "icon": "Clock"},
        "issued":   {"variant": "success", "icon": "PackageCheck"},
        "returned": {"variant": "warning", "icon": "Undo2"}
    }
}';

comment on table manufacturing.material_issues is '{
    "icon": "PackageMinus",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Issues By Status",
            "type": "kanban",
            "group": "status",
            "title": "issue_number",
            "description": "component_name",
            "date": "issued_at",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "issue_number",
                    "work_order_id",
                    "bom_item_id"
                ]
            },
            {
                "id": "component",
                "title": "Component",
                "fields": [
                    "component_sku",
                    "component_name",
                    "component_id",
                    "warehouse_code"
                ]
            },
            {
                "id": "quantity",
                "title": "Quantity",
                "fields": [
                    "quantity_required",
                    "quantity_issued",
                    "quantity_returned",
                    "unit_of_measure"
                ]
            },
            {
                "id": "cost",
                "title": "Cost",
                "fields": [
                    "unit_cost",
                    "total_cost"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "status",
                    "issued_at",
                    "returned_at"
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
                "id": "issued_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "work_orders",
                "on": "work_order_id",
                "columns": [
                    "work_order_number",
                    "product_name"
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

revoke all on table manufacturing.material_issues
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.material_issues to "x-admin";

create index idx_mfg_material_issues_user_id on manufacturing.material_issues (user_id);

create index idx_mfg_material_issues_work_order_id on manufacturing.material_issues (work_order_id);

create index idx_mfg_material_issues_bom_item_id on manufacturing.material_issues (bom_item_id);

create index idx_mfg_material_issues_status on manufacturing.material_issues (status);

create index idx_mfg_material_issues_component_sku on manufacturing.material_issues (component_sku);

alter table manufacturing.material_issues enable row level security;

create policy material_issues_select on manufacturing.material_issues for
select
  to authenticated using (true);

create policy material_issues_insert on manufacturing.material_issues for insert to authenticated
with
  check (true);

create policy material_issues_update on manufacturing.material_issues
for update
  to authenticated using (true)
with
  check (true);

create policy material_issues_delete on manufacturing.material_issues for delete to authenticated using (true);

----------------------------------------------------------------
-- Production outputs (completed batch records)
----------------------------------------------------------------
create table manufacturing.production_outputs (
  id uuid primary key default extensions.uuid_generate_v4 (),
  output_number varchar(50) unique not null,
  work_order_id uuid not null references manufacturing.work_orders (id) on delete cascade,
  work_center_id uuid references manufacturing.work_centers (id) on delete set null,
  status manufacturing.output_status default 'pending_inspection',
  quantity numeric(12, 2) not null default 0,
  unit_of_measure varchar(50) default 'each',
  lot_number varchar(100),
  serial_numbers text,
  produced_at timestamptz default current_timestamp,
  inspected_at timestamptz,
  inspector_user_id uuid references supasheet.users (id) on delete set null,
  quality_score supasheet.RATING,
  defect_reason text,
  destination_warehouse_code varchar(50),
  attachments supasheet.file,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column manufacturing.production_outputs.status is '{
    "progress": true,
    "enums": {
        "good":               {"variant": "success",     "icon": "CircleCheck"},
        "rework":             {"variant": "warning",     "icon": "RotateCcw"},
        "scrap":              {"variant": "destructive", "icon": "Trash2"},
        "pending_inspection": {"variant": "outline",     "icon": "Clock"}
    }
}';

comment on table manufacturing.production_outputs is '{
    "icon": "PackagePlus",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Outputs By Status",
            "type": "kanban",
            "group": "status",
            "title": "output_number",
            "description": "lot_number",
            "date": "produced_at",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Output Calendar",
            "type": "calendar",
            "title": "output_number",
            "badge": "status",
            "start_date": "produced_at",
            "end_date": "produced_at"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "output_number",
                    "work_order_id",
                    "work_center_id"
                ]
            },
            {
                "id": "quantity",
                "title": "Quantity",
                "fields": [
                    "quantity",
                    "unit_of_measure",
                    "status",
                    "quality_score"
                ]
            },
            {
                "id": "identification",
                "title": "Identification",
                "fields": [
                    "lot_number",
                    "serial_numbers",
                    "destination_warehouse_code"
                ]
            },
            {
                "id": "inspection",
                "title": "Inspection",
                "fields": [
                    "produced_at",
                    "inspected_at",
                    "inspector_user_id",
                    "defect_reason"
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
                "id": "produced_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "work_orders",
                "on": "work_order_id",
                "columns": [
                    "work_order_number",
                    "product_name"
                ]
            },
            {
                "table": "work_centers",
                "on": "work_center_id",
                "columns": [
                    "code",
                    "name"
                ]
            },
            {
                "table": "users",
                "on": "inspector_user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column manufacturing.production_outputs.attachments is '{"accept":"*", "maxFiles": 10}';

revoke all on table manufacturing.production_outputs
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table manufacturing.production_outputs to "x-admin";

create index idx_mfg_outputs_user_id on manufacturing.production_outputs (user_id);

create index idx_mfg_outputs_work_order_id on manufacturing.production_outputs (work_order_id);

create index idx_mfg_outputs_work_center_id on manufacturing.production_outputs (work_center_id);

create index idx_mfg_outputs_inspector on manufacturing.production_outputs (inspector_user_id);

create index idx_mfg_outputs_status on manufacturing.production_outputs (status);

create index idx_mfg_outputs_produced_at on manufacturing.production_outputs (produced_at desc);

create index idx_mfg_outputs_lot_number on manufacturing.production_outputs (lot_number);

alter table manufacturing.production_outputs enable row level security;

create policy production_outputs_select on manufacturing.production_outputs for
select
  to authenticated using (true);

create policy production_outputs_insert on manufacturing.production_outputs for insert to authenticated
with
  check (true);

create policy production_outputs_update on manufacturing.production_outputs
for update
  to authenticated using (true)
with
  check (true);

create policy production_outputs_delete on manufacturing.production_outputs for delete to authenticated using (true);

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view manufacturing.work_orders_report
with
  (security_invoker = true) as
select
  wo.id,
  wo.work_order_number,
  wo.product_sku,
  wo.product_name,
  b.bom_number,
  r.routing_number,
  wo.status,
  wo.priority,
  wo.quantity_planned,
  wo.quantity_completed,
  wo.quantity_scrapped,
  case
    when wo.quantity_planned > 0 then round(
      (
        wo.quantity_completed::numeric / wo.quantity_planned::numeric
      ) * 100,
      1
    )
    else 0
  end as completion_pct,
  case
    when (wo.quantity_completed + wo.quantity_scrapped) > 0 then round(
      (
        wo.quantity_completed::numeric / (wo.quantity_completed + wo.quantity_scrapped)::numeric
      ) * 100,
      1
    )
    else null
  end as yield_pct,
  wo.planned_start_date,
  wo.planned_end_date,
  wo.actual_start_date,
  wo.actual_end_date,
  case
    when wo.status = 'completed' then 0
    when wo.planned_end_date is null then null
    else greatest(0, (current_date - wo.planned_end_date))::int
  end as days_overdue,
  wo.estimated_cost,
  wo.actual_cost,
  wo.currency,
  u.name as assigned_to,
  wo.created_at
from
  manufacturing.work_orders wo
  left join manufacturing.boms b on b.id = wo.bom_id
  left join manufacturing.routings r on r.id = wo.routing_id
  left join supasheet.users u on u.id = wo.assigned_user_id;

revoke all on manufacturing.work_orders_report
from
  authenticated,
  service_role;

grant
select
  on manufacturing.work_orders_report to "x-admin";

comment on view manufacturing.work_orders_report is '{"type": "report", "name": "Work Orders Report", "description": "WOs with completion, yield, and overdue days"}';

create or replace view manufacturing.bom_explosion_report
with
  (security_invoker = true) as
select
  b.id as bom_id,
  b.bom_number,
  b.product_sku,
  b.product_name,
  b.version,
  b.status as bom_status,
  bi.line_number,
  bi.component_sku,
  bi.component_name,
  bi.quantity,
  bi.unit_of_measure,
  bi.scrap_pct,
  bi.unit_cost,
  bi.total_cost,
  bi.is_optional,
  b.output_quantity,
  (bi.total_cost / nullif(b.output_quantity, 0)) as cost_per_unit
from
  manufacturing.boms b
  left join manufacturing.bom_items bi on bi.bom_id = b.id;

revoke all on manufacturing.bom_explosion_report
from
  authenticated,
  service_role;

grant
select
  on manufacturing.bom_explosion_report to "x-admin";

comment on view manufacturing.bom_explosion_report is '{"type": "report", "name": "BOM Explosion", "description": "BOMs flattened with component lines and per-unit cost"}';

create or replace view manufacturing.production_outputs_report
with
  (security_invoker = true) as
select
  po.id,
  po.output_number,
  wo.work_order_number,
  wo.product_sku,
  wo.product_name,
  wc.name as work_center,
  po.status,
  po.quantity,
  po.unit_of_measure,
  po.lot_number,
  po.quality_score,
  po.produced_at,
  po.inspected_at,
  u.name as inspector,
  po.destination_warehouse_code,
  po.created_at
from
  manufacturing.production_outputs po
  left join manufacturing.work_orders wo on wo.id = po.work_order_id
  left join manufacturing.work_centers wc on wc.id = po.work_center_id
  left join supasheet.users u on u.id = po.inspector_user_id;

revoke all on manufacturing.production_outputs_report
from
  authenticated,
  service_role;

grant
select
  on manufacturing.production_outputs_report to "x-admin";

comment on view manufacturing.production_outputs_report is '{"type": "report", "name": "Production Outputs Report", "description": "Production output records with WO, work center, and QC info"}';

create or replace view manufacturing.material_consumption_report
with
  (security_invoker = true) as
select
  mi.id,
  mi.issue_number,
  wo.work_order_number,
  wo.product_sku as wo_product_sku,
  wo.product_name as wo_product_name,
  mi.component_sku,
  mi.component_name,
  mi.warehouse_code,
  mi.quantity_required,
  mi.quantity_issued,
  mi.quantity_returned,
  (mi.quantity_issued - mi.quantity_returned) as quantity_consumed,
  mi.unit_of_measure,
  mi.unit_cost,
  mi.total_cost,
  mi.status,
  mi.issued_at,
  mi.created_at
from
  manufacturing.material_issues mi
  left join manufacturing.work_orders wo on wo.id = mi.work_order_id;

revoke all on manufacturing.material_consumption_report
from
  authenticated,
  service_role;

grant
select
  on manufacturing.material_consumption_report to "x-admin";

comment on view manufacturing.material_consumption_report is '{"type": "report", "name": "Material Consumption Report", "description": "Components issued and consumed per work order"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: open work orders count
create or replace view manufacturing.open_work_orders
with
  (security_invoker = true) as
select
  count(*) as value,
  'clipboard-list' as icon,
  'open work orders' as label
from
  manufacturing.work_orders
where
  status in ('planned', 'released', 'in_progress', 'on_hold');

revoke all on manufacturing.open_work_orders
from
  authenticated,
  service_role;

grant
select
  on manufacturing.open_work_orders to "x-admin";

-- card_2: yield split (good vs scrap units across recent WOs)
create or replace view manufacturing.yield_split
with
  (security_invoker = true) as
select
  coalesce(sum(quantity_completed), 0)::bigint as primary,
  coalesce(sum(quantity_scrapped), 0)::bigint as secondary,
  'Good' as primary_label,
  'Scrap' as secondary_label
from
  manufacturing.work_orders
where
  actual_end_date >= current_timestamp - interval '90 days'
  or status = 'completed';

revoke all on manufacturing.yield_split
from
  authenticated,
  service_role;

grant
select
  on manufacturing.yield_split to "x-admin";

-- card_3: production value (completed × estimated unit cost) + on-time %
create or replace view manufacturing.production_value
with
  (security_invoker = true) as
select
  coalesce(
    sum(actual_cost) filter (
      where
        status = 'completed'
    ),
    0
  )::numeric(14, 2) as value,
  case
    when count(*) filter (
      where
        status = 'completed'
        and planned_end_date is not null
    ) > 0 then round(
      (
        count(*) filter (
          where
            status = 'completed'
            and actual_end_date is not null
            and actual_end_date::date <= planned_end_date
        )::numeric / count(*) filter (
          where
            status = 'completed'
            and planned_end_date is not null
        )::numeric
      ) * 100,
      1
    )
    else 0
  end as percent
from
  manufacturing.work_orders;

revoke all on manufacturing.production_value
from
  authenticated,
  service_role;

grant
select
  on manufacturing.production_value to "x-admin";

-- card_4: production health (overdue + on-hold + failed ops)
create or replace view manufacturing.production_health
with
  (security_invoker = true) as
with
  metrics as (
    select
      (
        select
          count(*)
        from
          manufacturing.work_orders
        where
          status in ('planned', 'released', 'in_progress')
          and planned_end_date is not null
          and planned_end_date < current_date
      ) as overdue_wos,
      (
        select
          count(*)
        from
          manufacturing.work_orders
        where
          status = 'on_hold'
      ) as on_hold_wos,
      (
        select
          count(*)
        from
          manufacturing.work_order_operations
        where
          status = 'failed'
      ) as failed_ops,
      (
        select
          count(*)
        from
          manufacturing.work_centers
        where
          status in ('maintenance', 'offline')
      ) as offline_centers,
      (
        select
          count(*)
        from
          manufacturing.work_orders
        where
          status in ('planned', 'released', 'in_progress', 'on_hold')
      ) as open_total
  )
select
  (
    overdue_wos + on_hold_wos + failed_ops + offline_centers
  ) as current,
  open_total as total,
  json_build_array(
    json_build_object('label', 'Overdue WOs', 'value', overdue_wos),
    json_build_object('label', 'On hold WOs', 'value', on_hold_wos),
    json_build_object('label', 'Failed ops', 'value', failed_ops),
    json_build_object(
      'label',
      'Centers offline',
      'value',
      offline_centers
    )
  ) as segments
from
  metrics;

revoke all on manufacturing.production_health
from
  authenticated,
  service_role;

grant
select
  on manufacturing.production_health to "x-admin";

-- table_1: recent work orders
create or replace view manufacturing.recent_work_orders
with
  (security_invoker = true) as
select
  work_order_number as number,
  product_name as product,
  coalesce(status::text, '') as status,
  to_char(
    coalesce(planned_start_date, created_at::date),
    'MM/DD'
  ) as date
from
  manufacturing.work_orders
order by
  coalesce(planned_start_date, created_at::date) desc
limit
  10;

revoke all on manufacturing.recent_work_orders
from
  authenticated,
  service_role;

grant
select
  on manufacturing.recent_work_orders to "x-admin";

-- table_2: top work centers by output
create or replace view manufacturing.top_work_centers
with
  (security_invoker = true) as
select
  wc.name as center,
  coalesce(wc.type::text, '') as type,
  count(po.id) as outputs,
  coalesce(sum(po.quantity), 0)::bigint as units
from
  manufacturing.work_centers wc
  left join manufacturing.production_outputs po on po.work_center_id = wc.id
group by
  wc.id,
  wc.name,
  wc.type
order by
  units desc nulls last
limit
  10;

revoke all on manufacturing.top_work_centers
from
  authenticated,
  service_role;

grant
select
  on manufacturing.top_work_centers to "x-admin";

comment on view manufacturing.open_work_orders is '{"type": "dashboard_widget", "name": "Open Work Orders", "description": "Count of WOs not yet completed", "widget_type": "card_1"}';

comment on view manufacturing.yield_split is '{"type": "dashboard_widget", "name": "Good vs Scrap", "description": "Recent production yield split", "widget_type": "card_2"}';

comment on view manufacturing.production_value is '{"type": "dashboard_widget", "name": "Production Value", "description": "Completed cost and on-time finish rate", "widget_type": "card_3"}';

comment on view manufacturing.production_health is '{"type": "dashboard_widget", "name": "Production Health", "description": "Overdue, on-hold, failed and offline issues", "widget_type": "card_4"}';

comment on view manufacturing.recent_work_orders is '{"type": "dashboard_widget", "name": "Recent Work Orders", "description": "Latest 10 work orders", "widget_type": "table_1"}';

comment on view manufacturing.top_work_centers is '{"type": "dashboard_widget", "name": "Top Work Centers", "description": "Top 10 work centers by units produced", "widget_type": "table_2"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: work orders by status
create or replace view manufacturing.work_orders_by_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  manufacturing.work_orders
group by
  status
order by
  case status
    when 'draft' then 1
    when 'planned' then 2
    when 'released' then 3
    when 'in_progress' then 4
    when 'on_hold' then 5
    when 'completed' then 6
    when 'cancelled' then 7
  end;

revoke all on manufacturing.work_orders_by_status_pie
from
  authenticated,
  service_role;

grant
select
  on manufacturing.work_orders_by_status_pie to "x-admin";

-- Bar: production by work center (good vs scrap)
create or replace view manufacturing.production_by_work_center_bar
with
  (security_invoker = true) as
select
  wc.name as label,
  coalesce(
    sum(po.quantity) filter (
      where
        po.status = 'good'
    ),
    0
  )::bigint as good,
  coalesce(
    sum(po.quantity) filter (
      where
        po.status in ('scrap', 'rework')
    ),
    0
  )::bigint as defects
from
  manufacturing.work_centers wc
  left join manufacturing.production_outputs po on po.work_center_id = wc.id
group by
  wc.id,
  wc.name
having
  count(po.id) > 0
order by
  sum(po.quantity) desc nulls last
limit
  10;

revoke all on manufacturing.production_by_work_center_bar
from
  authenticated,
  service_role;

grant
select
  on manufacturing.production_by_work_center_bar to "x-admin";

-- Line: weekly production trend (last 12 weeks)
create or replace view manufacturing.production_trend_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('week', produced_at), 'Mon DD') as date,
  coalesce(
    sum(quantity) filter (
      where
        status = 'good'
    ),
    0
  )::bigint as good,
  coalesce(
    sum(quantity) filter (
      where
        status in ('scrap', 'rework')
    ),
    0
  )::bigint as defects
from
  manufacturing.production_outputs
where
  produced_at >= current_date - interval '12 weeks'
group by
  date_trunc('week', produced_at)
order by
  date_trunc('week', produced_at);

revoke all on manufacturing.production_trend_line
from
  authenticated,
  service_role;

grant
select
  on manufacturing.production_trend_line to "x-admin";

-- Radar: operation metrics by status
create or replace view manufacturing.operation_metrics_radar
with
  (security_invoker = true) as
select
  status::text as metric,
  count(*) as total,
  coalesce(sum(quantity_good), 0)::bigint as good_units,
  coalesce(sum(quantity_scrap), 0)::bigint as scrap_units
from
  manufacturing.work_order_operations
group by
  status;

revoke all on manufacturing.operation_metrics_radar
from
  authenticated,
  service_role;

grant
select
  on manufacturing.operation_metrics_radar to "x-admin";

comment on view manufacturing.work_orders_by_status_pie is '{"type": "chart", "name": "Work Orders By Status", "description": "WO count grouped by status", "chart_type": "pie"}';

comment on view manufacturing.production_by_work_center_bar is '{"type": "chart", "name": "Production By Work Center", "description": "Good vs defective units per work center", "chart_type": "bar"}';

comment on view manufacturing.production_trend_line is '{"type": "chart", "name": "Production Trend", "description": "Weekly good vs defective output over 12 weeks", "chart_type": "line"}';

comment on view manufacturing.operation_metrics_radar is '{"type": "chart", "name": "Operation Metrics", "description": "Operation counts and unit yields by status", "chart_type": "radar"}';

----------------------------------------------------------------
-- Audit triggers
----------------------------------------------------------------
create trigger audit_mfg_work_centers_insert
after insert on manufacturing.work_centers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_work_centers_update
after update on manufacturing.work_centers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_work_centers_delete
before delete on manufacturing.work_centers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_boms_insert
after insert on manufacturing.boms for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_boms_update
after update on manufacturing.boms for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_boms_delete
before delete on manufacturing.boms for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_bom_items_insert
after insert on manufacturing.bom_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_bom_items_update
after update on manufacturing.bom_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_bom_items_delete
before delete on manufacturing.bom_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_routings_insert
after insert on manufacturing.routings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_routings_update
after update on manufacturing.routings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_routings_delete
before delete on manufacturing.routings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_routing_ops_insert
after insert on manufacturing.routing_operations for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_routing_ops_update
after update on manufacturing.routing_operations for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_routing_ops_delete
before delete on manufacturing.routing_operations for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_work_orders_insert
after insert on manufacturing.work_orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_work_orders_update
after update on manufacturing.work_orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_work_orders_delete
before delete on manufacturing.work_orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_wo_ops_insert
after insert on manufacturing.work_order_operations for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_wo_ops_update
after update on manufacturing.work_order_operations for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_wo_ops_delete
before delete on manufacturing.work_order_operations for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_material_issues_insert
after insert on manufacturing.material_issues for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_material_issues_update
after update on manufacturing.material_issues for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_material_issues_delete
before delete on manufacturing.material_issues for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_outputs_insert
after insert on manufacturing.production_outputs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_outputs_update
after update on manufacturing.production_outputs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_mfg_outputs_delete
before delete on manufacturing.production_outputs for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
-- Work orders: notify on creation, release, completion, cancellation
create or replace function manufacturing.trg_work_orders_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if tg_op = 'INSERT' then
        v_type  := 'manufacturing_wo_created';
        v_title := 'New work order';
        v_body  := 'Work order ' || new.work_order_number ||
                   ' for ' || new.product_name ||
                   ' (qty ' || new.quantity_planned::text || ') was created.';
    elsif new.status is distinct from old.status and new.status in ('released', 'completed', 'cancelled', 'on_hold') then
        v_type  := 'manufacturing_wo_' || new.status::text;
        v_title := 'Work order ' || new.status::text;
        v_body  := 'Work order ' || new.work_order_number || ' is now ' || new.status::text || '.';
    else
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('manufacturing', 'work_orders', 'select')
            || array[new.user_id, new.assigned_user_id],
        null
    );

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'work_order_id',     new.id,
            'product_sku',       new.product_sku,
            'status',            new.status,
            'priority',          new.priority,
            'quantity_planned',  new.quantity_planned,
            'quantity_completed',new.quantity_completed
        ),
        '/manufacturing/resource/work_orders/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists work_orders_notify on manufacturing.work_orders;

create trigger work_orders_notify
after insert or update of status on manufacturing.work_orders for each row
execute function manufacturing.trg_work_orders_notify ();

-- Work order operations: notify operator + WO owner on start/complete/fail
create or replace function manufacturing.trg_wo_operations_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_wo_owner uuid;
    v_wo_assigned uuid;
    v_wo_number text;
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
    if new.status not in ('in_progress', 'completed', 'failed') then
        return new;
    end if;

    select user_id, assigned_user_id, work_order_number
      into v_wo_owner, v_wo_assigned, v_wo_number
      from manufacturing.work_orders where id = new.work_order_id;

    v_recipients := array_remove(
        array[v_wo_owner, v_wo_assigned, new.operator_user_id],
        null
    );

    v_type  := 'manufacturing_op_' || new.status::text;
    v_title := 'Operation ' || new.status::text;
    v_body  := 'Operation "' || new.name || '" on ' || coalesce(v_wo_number, 'work order') ||
               ' is now ' || new.status::text || '.';

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'work_order_operation_id', new.id,
            'work_order_id',           new.work_order_id,
            'work_center_id',          new.work_center_id,
            'status',                  new.status,
            'quantity_good',           new.quantity_good,
            'quantity_scrap',          new.quantity_scrap
        ),
        '/manufacturing/resource/work_order_operations/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists wo_operations_notify on manufacturing.work_order_operations;

create trigger wo_operations_notify
after update of status on manufacturing.work_order_operations for each row
execute function manufacturing.trg_wo_operations_notify ();

-- Production outputs: notify QA on scrap and rework
create or replace function manufacturing.trg_production_outputs_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_wo_number text;
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if tg_op = 'INSERT' then
        if new.status not in ('scrap', 'rework') then
            return new;
        end if;
    elsif new.status is not distinct from old.status then
        return new;
    elsif new.status not in ('scrap', 'rework') then
        return new;
    end if;

    select work_order_number into v_wo_number
      from manufacturing.work_orders where id = new.work_order_id;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('manufacturing', 'production_outputs', 'update')
            || array[new.user_id, new.inspector_user_id],
        null
    );

    v_type  := 'manufacturing_output_' || new.status::text;
    v_title := 'Production output flagged: ' || new.status::text;
    v_body  := 'Output ' || new.output_number || ' (' || new.quantity::text || ' ' || new.unit_of_measure ||
               ') on ' || coalesce(v_wo_number, 'work order') ||
               ' is ' || new.status::text ||
               coalesce('. Reason: ' || new.defect_reason, '') || '.';

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'production_output_id', new.id,
            'work_order_id',        new.work_order_id,
            'work_center_id',       new.work_center_id,
            'status',               new.status,
            'quantity',             new.quantity,
            'lot_number',           new.lot_number
        ),
        '/manufacturing/resource/production_outputs/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists production_outputs_notify on manufacturing.production_outputs;

create trigger production_outputs_notify
after insert or update of status on manufacturing.production_outputs for each row
execute function manufacturing.trg_production_outputs_notify ();
