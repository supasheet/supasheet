create schema if not exists procurement;

grant usage on schema procurement to authenticated;

----------------------------------------------------------------
-- Enums + permissions (must commit before use)
----------------------------------------------------------------
begin;

create type procurement.supplier_status as enum(
  'pending',
  'qualified',
  'preferred',
  'on_hold',
  'blacklisted'
);

create type procurement.supplier_tier as enum(
  'strategic',
  'tier_1',
  'tier_2',
  'tier_3',
  'transactional'
);

create type procurement.contract_status as enum(
  'draft',
  'active',
  'expiring_soon',
  'expired',
  'terminated'
);

create type procurement.contract_type as enum('master', 'msa', 'sow', 'nda', 'spot');

create type procurement.requisition_status as enum(
  'draft',
  'submitted',
  'approved',
  'rejected',
  'converted',
  'cancelled'
);

create type procurement.requisition_priority as enum('low', 'medium', 'high', 'critical');

create type procurement.rfq_status as enum('draft', 'open', 'closed', 'awarded', 'cancelled');

create type procurement.quote_status as enum(
  'submitted',
  'shortlisted',
  'awarded',
  'rejected',
  'withdrawn'
);

create type procurement.asset_status as enum(
  'available',
  'in_use',
  'maintenance',
  'retired',
  'disposed',
  'lost'
);

create type procurement.asset_condition as enum('new', 'excellent', 'good', 'fair', 'poor');

create type procurement.depreciation_method as enum(
  'straight_line',
  'declining_balance',
  'units_of_production',
  'none'
);

create type procurement.assignment_status as enum('active', 'returned', 'lost', 'transferred');

create type procurement.maintenance_type as enum(
  'preventive',
  'corrective',
  'inspection',
  'calibration',
  'upgrade'
);

create type procurement.maintenance_status as enum(
  'scheduled',
  'in_progress',
  'completed',
  'cancelled'
);

commit;

----------------------------------------------------------------
-- Users mirror view
----------------------------------------------------------------
create or replace view procurement.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on procurement.users
from
  authenticated,
  service_role;

grant
select
  on procurement.users to "x-admin";

----------------------------------------------------------------
-- Suppliers (with qualification + scorecard)
----------------------------------------------------------------
create table procurement.suppliers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(50) unique,
  name varchar(500) not null,
  legal_name varchar(500),
  status procurement.supplier_status default 'pending',
  tier procurement.supplier_tier default 'tier_3',
  contact_name varchar(255),
  email supasheet.EMAIL,
  phone supasheet.TEL,
  website supasheet.URL,
  address text,
  city varchar(255),
  country varchar(255),
  tax_id varchar(100),
  payment_terms varchar(100),
  currency varchar(3) default 'USD',
  categories varchar(255) [],
  certifications text,
  qualified_at date,
  qualified_by_user_id uuid references supasheet.users (id) on delete set null,
  -- Scorecard (0-5 each)
  score_quality supasheet.RATING,
  score_delivery supasheet.RATING,
  score_cost supasheet.RATING,
  score_communication supasheet.RATING,
  score_overall supasheet.RATING,
  logo supasheet.file,
  description supasheet.RICH_TEXT,
  attachments supasheet.file,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column procurement.suppliers.status is '{
    "progress": true,
    "values": {
        "pending":     {"variant": "warning",     "icon": "Clock"},
        "qualified":   {"variant": "info",        "icon": "BadgeCheck"},
        "preferred":   {"variant": "success",     "icon": "Star"},
        "on_hold":     {"variant": "warning",     "icon": "PauseCircle"},
        "blacklisted": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on column procurement.suppliers.tier is '{
    "progress": false,
    "values": {
        "strategic":     {"variant": "success",     "icon": "Crown"},
        "tier_1":        {"variant": "info",        "icon": "Trophy"},
        "tier_2":        {"variant": "info",        "icon": "Medal"},
        "tier_3":        {"variant": "secondary",   "icon": "Award"},
        "transactional": {"variant": "outline",     "icon": "ShoppingCart"}
    }
}';

comment on table procurement.suppliers is '{
    "icon": "Factory",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Suppliers By Status",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "contact_name",
            "badge": "tier"
        },
        {
            "id": "gallery",
            "name": "Supplier Gallery",
            "type": "gallery",
            "cover": "logo",
            "title": "name",
            "description": "city",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "name",
                    "legal_name",
                    "code",
                    "status",
                    "tier",
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
                    "tax_id",
                    "payment_terms",
                    "currency",
                    "categories"
                ]
            },
            {
                "id": "qualification",
                "title": "Qualification",
                "fields": [
                    "qualified_at",
                    "qualified_by_user_id",
                    "certifications"
                ]
            },
            {
                "id": "scorecard",
                "title": "Scorecard",
                "fields": [
                    "score_quality",
                    "score_delivery",
                    "score_cost",
                    "score_communication",
                    "score_overall"
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
                "table": "users",
                "on": "user_id",
                "alias": "user",
                "columns": [
                    "name",
                    "email"
                ]
            },
            {
                "table": "users",
                "on": "qualified_by_user_id",
                "alias": "qualified_by_user",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column procurement.suppliers.logo is '{"accept":"image/*"}';

comment on column procurement.suppliers.attachments is '{"accept":"*", "max_files": 20}';

revoke all on table procurement.suppliers
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table procurement.suppliers to "x-admin";

create index idx_proc_suppliers_user_id on procurement.suppliers (user_id);

create index idx_proc_suppliers_status on procurement.suppliers (status);

create index idx_proc_suppliers_tier on procurement.suppliers (tier);

create index idx_proc_suppliers_country on procurement.suppliers (country);

alter table procurement.suppliers enable row level security;

create policy suppliers_select on procurement.suppliers for
select
  to authenticated using (true);

create policy suppliers_insert on procurement.suppliers for insert to authenticated
with
  check (true);

create policy suppliers_update on procurement.suppliers
for update
  to authenticated using (true)
with
  check (true);

create policy suppliers_delete on procurement.suppliers for delete to authenticated using (true);

----------------------------------------------------------------
-- Contracts (supplier agreements)
----------------------------------------------------------------
create table procurement.contracts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  contract_number varchar(50) unique not null,
  title varchar(500) not null,
  supplier_id uuid references procurement.suppliers (id) on delete set null,
  type procurement.contract_type default 'master',
  status procurement.contract_status default 'draft',
  start_date date,
  end_date date,
  auto_renew boolean default false,
  renewal_notice_days integer default 60,
  value numeric(14, 2),
  currency varchar(3) default 'USD',
  description supasheet.RICH_TEXT,
  terms text,
  signed_by_user_id uuid references supasheet.users (id) on delete set null,
  signed_at timestamptz,
  document supasheet.file,
  attachments supasheet.file,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column procurement.contracts.type is '{
    "progress": false,
    "values": {
        "master": {"variant": "success",   "icon": "FileSignature"},
        "msa":    {"variant": "info",      "icon": "FileText"},
        "sow":    {"variant": "warning",   "icon": "ClipboardList"},
        "nda":    {"variant": "secondary", "icon": "ShieldCheck"},
        "spot":   {"variant": "outline",   "icon": "Zap"}
    }
}';

comment on column procurement.contracts.status is '{
    "progress": true,
    "values": {
        "draft":          {"variant": "outline",     "icon": "FileEdit"},
        "active":         {"variant": "success",     "icon": "CircleCheck"},
        "expiring_soon":  {"variant": "warning",     "icon": "AlertTriangle"},
        "expired":        {"variant": "destructive", "icon": "XCircle"},
        "terminated":     {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table procurement.contracts is '{
    "icon": "FileSignature",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Contracts By Status",
            "type": "kanban",
            "group": "status",
            "title": "contract_number",
            "description": "title",
            "date": "end_date",
            "badge": "type"
        },
        {
            "id": "calendar",
            "name": "Contract Calendar",
            "type": "calendar",
            "title": "contract_number",
            "badge": "status",
            "start_date": "start_date",
            "end_date": "end_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "contract_number",
                    "title",
                    "supplier_id",
                    "type",
                    "status",
                    "description"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "start_date",
                    "end_date",
                    "auto_renew",
                    "renewal_notice_days"
                ]
            },
            {
                "id": "financial",
                "title": "Financial",
                "fields": [
                    "value",
                    "currency"
                ]
            },
            {
                "id": "signing",
                "title": "Signing",
                "fields": [
                    "signed_by_user_id",
                    "signed_at",
                    "document"
                ]
            },
            {
                "id": "extras",
                "title": "Terms, Attachments & Notes",
                "collapsible": true,
                "fields": [
                    "terms",
                    "attachments",
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
                "id": "end_date",
                "desc": false
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
                "table": "users",
                "on": "signed_by_user_id",
                "alias": "signed_by_user",
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

comment on column procurement.contracts.document is '{"accept":"application/pdf,.doc,.docx", "max_files": 1}';

comment on column procurement.contracts.attachments is '{"accept":"*", "max_files": 20}';

revoke all on table procurement.contracts
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table procurement.contracts to "x-admin";

create index idx_proc_contracts_user_id on procurement.contracts (user_id);

create index idx_proc_contracts_supplier_id on procurement.contracts (supplier_id);

create index idx_proc_contracts_status on procurement.contracts (status);

create index idx_proc_contracts_type on procurement.contracts (type);

create index idx_proc_contracts_end_date on procurement.contracts (end_date);

alter table procurement.contracts enable row level security;

create policy contracts_select on procurement.contracts for
select
  to authenticated using (true);

create policy contracts_insert on procurement.contracts for insert to authenticated
with
  check (true);

create policy contracts_update on procurement.contracts
for update
  to authenticated using (true)
with
  check (true);

create policy contracts_delete on procurement.contracts for delete to authenticated using (true);

----------------------------------------------------------------
-- Requisitions (internal purchase requests)
----------------------------------------------------------------
create table procurement.requisitions (
  id uuid primary key default extensions.uuid_generate_v4 (),
  requisition_number varchar(50) unique not null,
  title varchar(500) not null,
  status procurement.requisition_status default 'draft',
  priority procurement.requisition_priority default 'medium',
  department varchar(255),
  cost_center varchar(100),
  requested_date date default current_date,
  needed_by_date date,
  estimated_total numeric(14, 2) default 0,
  currency varchar(3) default 'USD',
  justification supasheet.RICH_TEXT,
  approver_user_id uuid references supasheet.users (id) on delete set null,
  approved_at timestamptz,
  response text,
  contract_id uuid references procurement.contracts (id) on delete set null,
  rfq_id uuid,
  attachments supasheet.file,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column procurement.requisitions.status is '{
    "progress": true,
    "values": {
        "draft":     {"variant": "outline",     "icon": "FileEdit"},
        "submitted": {"variant": "info",        "icon": "Send"},
        "approved":  {"variant": "success",     "icon": "BadgeCheck"},
        "rejected":  {"variant": "destructive", "icon": "XCircle"},
        "converted": {"variant": "info",        "icon": "ArrowRight"},
        "cancelled": {"variant": "outline",     "icon": "Ban"}
    }
}';

comment on column procurement.requisitions.priority is '{
    "progress": false,
    "values": {
        "low":      {"variant": "outline",     "icon": "CircleArrowDown"},
        "medium":   {"variant": "info",        "icon": "CircleMinus"},
        "high":     {"variant": "warning",     "icon": "CircleArrowUp"},
        "critical": {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on table procurement.requisitions is '{
    "icon": "ClipboardList",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Requisitions By Status",
            "type": "kanban",
            "group": "status",
            "title": "requisition_number",
            "description": "title",
            "date": "needed_by_date",
            "badge": "priority"
        },
        {
            "id": "calendar",
            "name": "Requisition Calendar",
            "type": "calendar",
            "title": "requisition_number",
            "badge": "status",
            "start_date": "requested_date",
            "end_date": "needed_by_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "requisition_number",
                    "title",
                    "status",
                    "priority",
                    "justification"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "department",
                    "cost_center",
                    "contract_id",
                    "rfq_id"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "requested_date",
                    "needed_by_date"
                ]
            },
            {
                "id": "financial",
                "title": "Financial",
                "fields": [
                    "estimated_total",
                    "currency"
                ]
            },
            {
                "id": "approval",
                "title": "Approval",
                "fields": [
                    "approver_user_id",
                    "approved_at",
                    "response"
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
                "id": "requested_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "users",
                "on": "user_id",
                "alias": "user",
                "columns": [
                    "name",
                    "email"
                ]
            },
            {
                "table": "users",
                "on": "approver_user_id",
                "alias": "approver_user",
                "columns": [
                    "name",
                    "email"
                ]
            },
            {
                "table": "contracts",
                "on": "contract_id",
                "columns": [
                    "contract_number",
                    "title"
                ]
            }
        ]
    }
}';

comment on column procurement.requisitions.attachments is '{"accept":"*", "max_files": 10}';

revoke all on table procurement.requisitions
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table procurement.requisitions to "x-admin";

create index idx_proc_requisitions_user_id on procurement.requisitions (user_id);

create index idx_proc_requisitions_approver on procurement.requisitions (approver_user_id);

create index idx_proc_requisitions_status on procurement.requisitions (status);

create index idx_proc_requisitions_priority on procurement.requisitions (priority);

create index idx_proc_requisitions_needed_by_date on procurement.requisitions (needed_by_date);

create index idx_proc_requisitions_contract_id on procurement.requisitions (contract_id);

alter table procurement.requisitions enable row level security;

create policy requisitions_select on procurement.requisitions for
select
  to authenticated using (true);

create policy requisitions_insert on procurement.requisitions for insert to authenticated
with
  check (true);

create policy requisitions_update on procurement.requisitions
for update
  to authenticated using (true)
with
  check (true);

create policy requisitions_delete on procurement.requisitions for delete to authenticated using (true);

----------------------------------------------------------------
-- Requisition items
----------------------------------------------------------------
create table procurement.requisition_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  requisition_id uuid not null references procurement.requisitions (id) on delete cascade,
  line_number integer default 0,
  item_name varchar(500) not null,
  item_sku varchar(100),
  description text,
  category varchar(255),
  quantity numeric(12, 4) not null default 1,
  unit_of_measure varchar(50) default 'each',
  estimated_unit_cost numeric(12, 4) default 0,
  estimated_total numeric(14, 4) generated always as (quantity * estimated_unit_cost) stored,
  suggested_supplier_id uuid references procurement.suppliers (id) on delete set null,
  notes text,
  created_at timestamptz default current_timestamp
);

comment on table procurement.requisition_items is '{
    "icon": "ListChecks",
    "display": "none",
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "requisition_id",
                    "line_number"
                ]
            },
            {
                "id": "item",
                "title": "Item",
                "fields": [
                    "item_name",
                    "item_sku",
                    "category",
                    "description"
                ]
            },
            {
                "id": "quantity",
                "title": "Quantity & Cost",
                "fields": [
                    "quantity",
                    "unit_of_measure",
                    "estimated_unit_cost",
                    "estimated_total"
                ]
            },
            {
                "id": "supplier",
                "title": "Supplier",
                "fields": [
                    "suggested_supplier_id"
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
                "table": "requisitions",
                "on": "requisition_id",
                "columns": [
                    "requisition_number",
                    "title"
                ]
            },
            {
                "table": "suppliers",
                "on": "suggested_supplier_id",
                "columns": [
                    "name",
                    "code"
                ]
            }
        ]
    }
}';

revoke all on table procurement.requisition_items
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table procurement.requisition_items to "x-admin";

create index idx_proc_req_items_req_id on procurement.requisition_items (requisition_id);

create index idx_proc_req_items_supplier on procurement.requisition_items (suggested_supplier_id);

create index idx_proc_req_items_category on procurement.requisition_items (category);

alter table procurement.requisition_items enable row level security;

create policy requisition_items_select on procurement.requisition_items for
select
  to authenticated using (true);

create policy requisition_items_insert on procurement.requisition_items for insert to authenticated
with
  check (true);

create policy requisition_items_update on procurement.requisition_items
for update
  to authenticated using (true)
with
  check (true);

create policy requisition_items_delete on procurement.requisition_items for delete to authenticated using (true);

----------------------------------------------------------------
-- RFQs (request for quotation / sourcing events)
----------------------------------------------------------------
create table procurement.rfqs (
  id uuid primary key default extensions.uuid_generate_v4 (),
  rfq_number varchar(50) unique not null,
  title varchar(500) not null,
  status procurement.rfq_status default 'draft',
  requisition_id uuid references procurement.requisitions (id) on delete set null,
  description supasheet.RICH_TEXT,
  requirements text,
  issued_date date,
  response_due_date date,
  expected_award_date date,
  awarded_at timestamptz,
  estimated_value numeric(14, 2),
  awarded_value numeric(14, 2),
  currency varchar(3) default 'USD',
  awarded_supplier_id uuid references procurement.suppliers (id) on delete set null,
  invited_supplier_count integer default 0,
  attachments supasheet.file,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column procurement.rfqs.status is '{
    "progress": true,
    "values": {
        "draft":     {"variant": "outline",     "icon": "FileEdit"},
        "open":      {"variant": "info",        "icon": "Send"},
        "closed":    {"variant": "warning",     "icon": "Lock"},
        "awarded":   {"variant": "success",     "icon": "Trophy"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table procurement.rfqs is '{
    "icon": "Gavel",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "RFQs By Status",
            "type": "kanban",
            "group": "status",
            "title": "rfq_number",
            "description": "title",
            "date": "response_due_date",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "RFQ Calendar",
            "type": "calendar",
            "title": "rfq_number",
            "badge": "status",
            "start_date": "issued_date",
            "end_date": "response_due_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "rfq_number",
                    "title",
                    "status",
                    "description",
                    "requirements"
                ]
            },
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "requisition_id"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "issued_date",
                    "response_due_date",
                    "expected_award_date",
                    "awarded_at"
                ]
            },
            {
                "id": "financial",
                "title": "Financial",
                "fields": [
                    "estimated_value",
                    "awarded_value",
                    "currency"
                ]
            },
            {
                "id": "award",
                "title": "Award",
                "fields": [
                    "awarded_supplier_id",
                    "invited_supplier_count"
                ]
            },
            {
                "id": "extras",
                "title": "Attachments & Notes",
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
                "id": "response_due_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "requisitions",
                "on": "requisition_id",
                "columns": [
                    "requisition_number",
                    "title"
                ]
            },
            {
                "table": "suppliers",
                "on": "awarded_supplier_id",
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

comment on column procurement.rfqs.attachments is '{"accept":"*", "max_files": 20}';

revoke all on table procurement.rfqs
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table procurement.rfqs to "x-admin";

create index idx_proc_rfqs_user_id on procurement.rfqs (user_id);

create index idx_proc_rfqs_requisition_id on procurement.rfqs (requisition_id);

create index idx_proc_rfqs_awarded_supplier on procurement.rfqs (awarded_supplier_id);

create index idx_proc_rfqs_status on procurement.rfqs (status);

create index idx_proc_rfqs_response_due_date on procurement.rfqs (response_due_date);

alter table procurement.rfqs enable row level security;

create policy rfqs_select on procurement.rfqs for
select
  to authenticated using (true);

create policy rfqs_insert on procurement.rfqs for insert to authenticated
with
  check (true);

create policy rfqs_update on procurement.rfqs
for update
  to authenticated using (true)
with
  check (true);

create policy rfqs_delete on procurement.rfqs for delete to authenticated using (true);

----------------------------------------------------------------
-- Quotes (supplier responses to RFQs)
----------------------------------------------------------------
create table procurement.quotes (
  id uuid primary key default extensions.uuid_generate_v4 (),
  quote_number varchar(50) unique not null,
  rfq_id uuid not null references procurement.rfqs (id) on delete cascade,
  supplier_id uuid not null references procurement.suppliers (id) on delete restrict,
  status procurement.quote_status default 'submitted',
  submitted_at timestamptz default current_timestamp,
  valid_until date,
  total_price numeric(14, 2) not null default 0,
  currency varchar(3) default 'USD',
  lead_time_days integer,
  payment_terms varchar(100),
  line_items jsonb,
  description supasheet.RICH_TEXT,
  notes text,
  score supasheet.RATING,
  attachments supasheet.file,
  tags varchar(255) [],
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column procurement.quotes.status is '{
    "progress": true,
    "values": {
        "submitted":   {"variant": "info",        "icon": "Send"},
        "shortlisted": {"variant": "warning",     "icon": "Star"},
        "awarded":     {"variant": "success",     "icon": "Trophy"},
        "rejected":    {"variant": "destructive", "icon": "XCircle"},
        "withdrawn":   {"variant": "outline",     "icon": "Undo2"}
    }
}';

comment on table procurement.quotes is '{
    "icon": "DollarSign",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Quotes By Status",
            "type": "kanban",
            "group": "status",
            "title": "quote_number",
            "description": "description",
            "date": "submitted_at",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "quote_number",
                    "rfq_id",
                    "supplier_id",
                    "status"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "submitted_at",
                    "valid_until"
                ]
            },
            {
                "id": "pricing",
                "title": "Pricing",
                "fields": [
                    "total_price",
                    "currency",
                    "lead_time_days",
                    "payment_terms"
                ]
            },
            {
                "id": "line_items",
                "title": "Line Items",
                "fields": [
                    "line_items",
                    "description"
                ]
            },
            {
                "id": "evaluation",
                "title": "Evaluation",
                "fields": [
                    "score",
                    "notes"
                ]
            },
            {
                "id": "extras",
                "title": "Tags & Attachments",
                "collapsible": true,
                "fields": [
                    "tags",
                    "attachments"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "submitted_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "rfqs",
                "on": "rfq_id",
                "columns": [
                    "rfq_number",
                    "title"
                ]
            },
            {
                "table": "suppliers",
                "on": "supplier_id",
                "columns": [
                    "name",
                    "tier"
                ]
            }
        ]
    }
}';

comment on column procurement.quotes.attachments is '{"accept":"*", "max_files": 10}';

revoke all on table procurement.quotes
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table procurement.quotes to "x-admin";

create index idx_proc_quotes_user_id on procurement.quotes (user_id);

create index idx_proc_quotes_rfq_id on procurement.quotes (rfq_id);

create index idx_proc_quotes_supplier_id on procurement.quotes (supplier_id);

create index idx_proc_quotes_status on procurement.quotes (status);

alter table procurement.quotes enable row level security;

create policy quotes_select on procurement.quotes for
select
  to authenticated using (true);

create policy quotes_insert on procurement.quotes for insert to authenticated
with
  check (true);

create policy quotes_update on procurement.quotes
for update
  to authenticated using (true)
with
  check (true);

create policy quotes_delete on procurement.quotes for delete to authenticated using (true);

----------------------------------------------------------------
-- Asset categories
----------------------------------------------------------------
create table procurement.asset_categories (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(50) unique not null,
  name varchar(255) not null,
  parent_id uuid references procurement.asset_categories (id) on delete set null,
  description supasheet.RICH_TEXT,
  cover supasheet.file,
  default_depreciation_method procurement.depreciation_method default 'straight_line',
  default_useful_life_months integer,
  default_salvage_pct numeric(5, 2) default 0,
  color supasheet.COLOR,
  tags varchar(255) [],
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column procurement.asset_categories.default_depreciation_method is '{
    "progress": false,
    "values": {
        "straight_line":        {"variant": "info",     "icon": "TrendingDown"},
        "declining_balance":    {"variant": "warning",  "icon": "ChartLine"},
        "units_of_production":  {"variant": "secondary","icon": "Settings2"},
        "none":                 {"variant": "outline",  "icon": "MinusCircle"}
    }
}';

comment on table procurement.asset_categories is '{
    "icon": "FolderTree",
    "display": "block",
    "primary_view": "gallery",
    "views": [
        {
            "id": "gallery",
            "name": "Category Gallery",
            "type": "gallery",
            "cover": "cover",
            "title": "name",
            "description": "code",
            "badge": "default_depreciation_method"
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
                    "parent_id",
                    "description",
                    "cover"
                ]
            },
            {
                "id": "depreciation",
                "title": "Default Depreciation",
                "fields": [
                    "default_depreciation_method",
                    "default_useful_life_months",
                    "default_salvage_pct"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "color",
                    "tags"
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
        ]
    }
}';

comment on column procurement.asset_categories.cover is '{"accept":"image/*"}';

revoke all on table procurement.asset_categories
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table procurement.asset_categories to "x-admin";

create index idx_proc_asset_cats_parent_id on procurement.asset_categories (parent_id);

alter table procurement.asset_categories enable row level security;

create policy asset_categories_select on procurement.asset_categories for
select
  to authenticated using (true);

create policy asset_categories_insert on procurement.asset_categories for insert to authenticated
with
  check (true);

create policy asset_categories_update on procurement.asset_categories
for update
  to authenticated using (true)
with
  check (true);

create policy asset_categories_delete on procurement.asset_categories for delete to authenticated using (true);

----------------------------------------------------------------
-- Assets (fixed asset register)
----------------------------------------------------------------
create table procurement.assets (
  id uuid primary key default extensions.uuid_generate_v4 (),
  asset_tag varchar(100) unique not null,
  name varchar(500) not null,
  serial_number varchar(255),
  barcode varchar(100),
  category_id uuid references procurement.asset_categories (id) on delete set null,
  supplier_id uuid references procurement.suppliers (id) on delete set null,
  status procurement.asset_status default 'available',
  condition procurement.asset_condition default 'good',
  description supasheet.RICH_TEXT,
  image supasheet.file,
  attachments supasheet.file,
  manufacturer varchar(255),
  model varchar(255),
  location varchar(255),
  department varchar(255),
  purchase_date date,
  purchase_cost numeric(14, 2) default 0,
  currency varchar(3) default 'USD',
  depreciation_method procurement.depreciation_method default 'straight_line',
  useful_life_months integer,
  salvage_value numeric(14, 2) default 0,
  accumulated_depreciation numeric(14, 2) default 0,
  current_value numeric(14, 2) default 0,
  warranty_until date,
  insured boolean default false,
  insurance_policy varchar(255),
  last_inspection_date date,
  next_inspection_date date,
  disposed_at date,
  disposal_reason text,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column procurement.assets.status is '{
    "progress": true,
    "values": {
        "available":   {"variant": "success",     "icon": "CircleCheck"},
        "in_use":      {"variant": "info",        "icon": "UserCheck"},
        "maintenance": {"variant": "warning",     "icon": "Wrench"},
        "retired":     {"variant": "secondary",   "icon": "Archive"},
        "disposed":    {"variant": "destructive", "icon": "Trash2"},
        "lost":        {"variant": "destructive", "icon": "AlertTriangle"}
    }
}';

comment on column procurement.assets.condition is '{
    "progress": true,
    "values": {
        "new":       {"variant": "success",     "icon": "Sparkles"},
        "excellent": {"variant": "success",     "icon": "Star"},
        "good":      {"variant": "info",        "icon": "ThumbsUp"},
        "fair":      {"variant": "warning",     "icon": "Equal"},
        "poor":      {"variant": "destructive", "icon": "ThumbsDown"}
    }
}';

comment on column procurement.assets.depreciation_method is '{
    "progress": false,
    "values": {
        "straight_line":       {"variant": "info",      "icon": "TrendingDown"},
        "declining_balance":   {"variant": "warning",   "icon": "ChartLine"},
        "units_of_production": {"variant": "secondary", "icon": "Settings2"},
        "none":                {"variant": "outline",   "icon": "MinusCircle"}
    }
}';

comment on table procurement.assets is '{
    "icon": "Building",
    "display": "block",
    "primary_view": "gallery",
    "views": [
        {
            "id": "gallery",
            "name": "Asset Gallery",
            "type": "gallery",
            "cover": "image",
            "title": "name",
            "description": "asset_tag",
            "badge": "status"
        },
        {
            "id": "kanban",
            "name": "Assets By Status",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "location",
            "badge": "condition"
        },
        {
            "id": "calendar",
            "name": "Inspection Calendar",
            "type": "calendar",
            "title": "name",
            "badge": "status",
            "start_date": "last_inspection_date",
            "end_date": "next_inspection_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Identity",
                "fields": [
                    "asset_tag",
                    "name",
                    "serial_number",
                    "barcode",
                    "image"
                ]
            },
            {
                "id": "classification",
                "title": "Classification",
                "fields": [
                    "category_id",
                    "manufacturer",
                    "model",
                    "status",
                    "condition"
                ]
            },
            {
                "id": "location",
                "title": "Location",
                "fields": [
                    "location",
                    "department"
                ]
            },
            {
                "id": "acquisition",
                "title": "Acquisition",
                "fields": [
                    "supplier_id",
                    "purchase_date",
                    "purchase_cost",
                    "currency"
                ]
            },
            {
                "id": "depreciation",
                "title": "Depreciation",
                "fields": [
                    "depreciation_method",
                    "useful_life_months",
                    "salvage_value",
                    "accumulated_depreciation",
                    "current_value"
                ]
            },
            {
                "id": "warranty",
                "title": "Warranty & Insurance",
                "fields": [
                    "warranty_until",
                    "insured",
                    "insurance_policy"
                ]
            },
            {
                "id": "inspection",
                "title": "Inspection & Disposal",
                "fields": [
                    "last_inspection_date",
                    "next_inspection_date",
                    "disposed_at",
                    "disposal_reason"
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
                    "notes",
                    "description"
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
                "table": "asset_categories",
                "on": "category_id",
                "columns": [
                    "code",
                    "name"
                ]
            },
            {
                "table": "suppliers",
                "on": "supplier_id",
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

comment on column procurement.assets.image is '{"accept":"image/*"}';

comment on column procurement.assets.attachments is '{"accept":"*", "max_files": 20}';

revoke all on table procurement.assets
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table procurement.assets to "x-admin";

create index idx_proc_assets_user_id on procurement.assets (user_id);

create index idx_proc_assets_category_id on procurement.assets (category_id);

create index idx_proc_assets_supplier_id on procurement.assets (supplier_id);

create index idx_proc_assets_status on procurement.assets (status);

create index idx_proc_assets_condition on procurement.assets (condition);

create index idx_proc_assets_asset_tag on procurement.assets (asset_tag);

create index idx_proc_assets_serial_number on procurement.assets (serial_number);

create index idx_proc_assets_next_inspection_date on procurement.assets (next_inspection_date);

alter table procurement.assets enable row level security;

create policy assets_select on procurement.assets for
select
  to authenticated using (true);

create policy assets_insert on procurement.assets for insert to authenticated
with
  check (true);

create policy assets_update on procurement.assets
for update
  to authenticated using (true)
with
  check (true);

create policy assets_delete on procurement.assets for delete to authenticated using (true);

----------------------------------------------------------------
-- Asset assignments (custodian history)
----------------------------------------------------------------
create table procurement.asset_assignments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  asset_id uuid not null references procurement.assets (id) on delete cascade,
  assignee_user_id uuid references supasheet.users (id) on delete set null,
  assignee_name varchar(500),
  assignee_department varchar(255),
  status procurement.assignment_status default 'active',
  assigned_at timestamptz default current_timestamp,
  expected_return_date date,
  returned_at timestamptz,
  location varchar(255),
  purpose text,
  return_condition procurement.asset_condition,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column procurement.asset_assignments.status is '{
    "progress": true,
    "values": {
        "active":      {"variant": "info",        "icon": "UserCheck"},
        "returned":    {"variant": "success",     "icon": "CircleCheck"},
        "transferred": {"variant": "warning",     "icon": "ArrowLeftRight"},
        "lost":        {"variant": "destructive", "icon": "AlertTriangle"}
    }
}';

comment on table procurement.asset_assignments is '{
    "icon": "UserPlus",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Assignments By Status",
            "type": "kanban",
            "group": "status",
            "title": "assignee_name",
            "description": "purpose",
            "date": "assigned_at",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Assignment Calendar",
            "type": "calendar",
            "title": "assignee_name",
            "badge": "status",
            "start_date": "assigned_at",
            "end_date": "expected_return_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "asset_id",
                    "status"
                ]
            },
            {
                "id": "assignee",
                "title": "Assignee",
                "fields": [
                    "assignee_user_id",
                    "assignee_name",
                    "assignee_department"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "assigned_at",
                    "expected_return_date",
                    "returned_at"
                ]
            },
            {
                "id": "details",
                "title": "Details",
                "fields": [
                    "location",
                    "purpose",
                    "return_condition"
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
                "id": "assigned_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "assets",
                "on": "asset_id",
                "columns": [
                    "asset_tag",
                    "name"
                ]
            },
            {
                "table": "users",
                "on": "assignee_user_id",
                "alias": "assignee_user",
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

revoke all on table procurement.asset_assignments
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table procurement.asset_assignments to "x-admin";

create index idx_proc_asset_assignments_asset_id on procurement.asset_assignments (asset_id);

create index idx_proc_asset_assignments_assignee on procurement.asset_assignments (assignee_user_id);

create index idx_proc_asset_assignments_status on procurement.asset_assignments (status);

create index idx_proc_asset_assignments_assigned_at on procurement.asset_assignments (assigned_at desc);

alter table procurement.asset_assignments enable row level security;

create policy asset_assignments_select on procurement.asset_assignments for
select
  to authenticated using (true);

create policy asset_assignments_insert on procurement.asset_assignments for insert to authenticated
with
  check (true);

create policy asset_assignments_update on procurement.asset_assignments
for update
  to authenticated using (true)
with
  check (true);

create policy asset_assignments_delete on procurement.asset_assignments for delete to authenticated using (true);

----------------------------------------------------------------
-- Asset maintenance
----------------------------------------------------------------
create table procurement.asset_maintenance (
  id uuid primary key default extensions.uuid_generate_v4 (),
  maintenance_number varchar(50) unique not null,
  asset_id uuid not null references procurement.assets (id) on delete cascade,
  type procurement.maintenance_type default 'preventive',
  status procurement.maintenance_status default 'scheduled',
  title varchar(500) not null,
  description supasheet.RICH_TEXT,
  scheduled_date date,
  started_at timestamptz,
  completed_at timestamptz,
  technician_user_id uuid references supasheet.users (id) on delete set null,
  vendor_supplier_id uuid references procurement.suppliers (id) on delete set null,
  cost numeric(12, 2) default 0,
  currency varchar(3) default 'USD',
  parts_used text,
  findings text,
  next_due_date date,
  attachments supasheet.file,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column procurement.asset_maintenance.type is '{
    "progress": false,
    "values": {
        "preventive":  {"variant": "success",     "icon": "ShieldCheck"},
        "corrective":  {"variant": "warning",     "icon": "Wrench"},
        "inspection":  {"variant": "info",        "icon": "Eye"},
        "calibration": {"variant": "info",        "icon": "Settings2"},
        "upgrade":     {"variant": "info",        "icon": "ArrowUp"}
    }
}';

comment on column procurement.asset_maintenance.status is '{
    "progress": true,
    "values": {
        "scheduled":   {"variant": "outline",     "icon": "Calendar"},
        "in_progress": {"variant": "warning",     "icon": "Loader"},
        "completed":   {"variant": "success",     "icon": "CircleCheck"},
        "cancelled":   {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table procurement.asset_maintenance is '{
    "icon": "Wrench",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Maintenance By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "description",
            "date": "scheduled_date",
            "badge": "type"
        },
        {
            "id": "calendar",
            "name": "Maintenance Calendar",
            "type": "calendar",
            "title": "title",
            "badge": "status",
            "start_date": "scheduled_date",
            "end_date": "completed_at"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "maintenance_number",
                    "asset_id",
                    "title",
                    "type",
                    "status",
                    "description"
                ]
            },
            {
                "id": "schedule",
                "title": "Schedule",
                "fields": [
                    "scheduled_date",
                    "started_at",
                    "completed_at",
                    "next_due_date"
                ]
            },
            {
                "id": "resources",
                "title": "Resources",
                "fields": [
                    "technician_user_id",
                    "vendor_supplier_id",
                    "cost",
                    "currency",
                    "parts_used"
                ]
            },
            {
                "id": "findings",
                "title": "Findings",
                "fields": [
                    "findings"
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
                "id": "scheduled_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "assets",
                "on": "asset_id",
                "columns": [
                    "asset_tag",
                    "name"
                ]
            },
            {
                "table": "suppliers",
                "on": "vendor_supplier_id",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "users",
                "on": "technician_user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column procurement.asset_maintenance.attachments is '{"accept":"*", "max_files": 10}';

revoke all on table procurement.asset_maintenance
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table procurement.asset_maintenance to "x-admin";

create index idx_proc_maintenance_user_id on procurement.asset_maintenance (user_id);

create index idx_proc_maintenance_asset_id on procurement.asset_maintenance (asset_id);

create index idx_proc_maintenance_technician on procurement.asset_maintenance (technician_user_id);

create index idx_proc_maintenance_vendor on procurement.asset_maintenance (vendor_supplier_id);

create index idx_proc_maintenance_status on procurement.asset_maintenance (status);

create index idx_proc_maintenance_type on procurement.asset_maintenance (type);

create index idx_proc_maintenance_scheduled_date on procurement.asset_maintenance (scheduled_date);

alter table procurement.asset_maintenance enable row level security;

create policy asset_maintenance_select on procurement.asset_maintenance for
select
  to authenticated using (true);

create policy asset_maintenance_insert on procurement.asset_maintenance for insert to authenticated
with
  check (true);

create policy asset_maintenance_update on procurement.asset_maintenance
for update
  to authenticated using (true)
with
  check (true);

create policy asset_maintenance_delete on procurement.asset_maintenance for delete to authenticated using (true);

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view procurement.suppliers_scorecard
with
  (security_invoker = true) as
select
  s.id,
  s.code,
  s.name,
  s.status,
  s.tier,
  s.country,
  s.score_quality,
  s.score_delivery,
  s.score_cost,
  s.score_communication,
  s.score_overall,
  count(distinct c.id) as contract_count,
  coalesce(
    sum(c.value) filter (
      where
        c.status = 'active'
    ),
    0
  ) as active_contract_value,
  count(distinct q.id) as quote_count,
  count(distinct q.id) filter (
    where
      q.status = 'awarded'
  ) as awards_won,
  s.qualified_at,
  s.created_at
from
  procurement.suppliers s
  left join procurement.contracts c on c.supplier_id = s.id
  left join procurement.quotes q on q.supplier_id = s.id
group by
  s.id;

revoke all on procurement.suppliers_scorecard
from
  authenticated,
  service_role;

grant
select
  on procurement.suppliers_scorecard to "x-admin";

comment on view procurement.suppliers_scorecard is '{"type": "report", "name": "Supplier Scorecard", "description": "Suppliers with scores, contracts, and award history"}';

create or replace view procurement.requisitions_report
with
  (security_invoker = true) as
select
  r.id,
  r.requisition_number,
  r.title,
  r.status,
  r.priority,
  r.department,
  r.cost_center,
  r.requested_date,
  r.needed_by_date,
  case
    when r.status in ('approved', 'converted') then 0
    when r.needed_by_date is null then null
    else greatest(0, (current_date - r.needed_by_date))::int
  end as days_overdue,
  r.estimated_total,
  r.currency,
  u.name as requester,
  a.name as approver,
  r.approved_at,
  count(ri.id) as line_count,
  r.created_at
from
  procurement.requisitions r
  left join supasheet.users u on u.id = r.user_id
  left join supasheet.users a on a.id = r.approver_user_id
  left join procurement.requisition_items ri on ri.requisition_id = r.id
group by
  r.id,
  u.name,
  a.name;

revoke all on procurement.requisitions_report
from
  authenticated,
  service_role;

grant
select
  on procurement.requisitions_report to "x-admin";

comment on view procurement.requisitions_report is '{"type": "report", "name": "Requisitions Report", "description": "Requisitions with approver, line counts, and overdue days"}';

create or replace view procurement.contracts_report
with
  (security_invoker = true) as
select
  c.id,
  c.contract_number,
  c.title,
  s.name as supplier,
  c.type,
  c.status,
  c.start_date,
  c.end_date,
  case
    when c.end_date is null then null
    else (c.end_date - current_date)::int
  end as days_to_expiry,
  c.value,
  c.currency,
  c.auto_renew,
  c.renewal_notice_days,
  u.name as signed_by,
  c.signed_at,
  c.created_at
from
  procurement.contracts c
  left join procurement.suppliers s on s.id = c.supplier_id
  left join supasheet.users u on u.id = c.signed_by_user_id;

revoke all on procurement.contracts_report
from
  authenticated,
  service_role;

grant
select
  on procurement.contracts_report to "x-admin";

comment on view procurement.contracts_report is '{"type": "report", "name": "Contracts Report", "description": "Contracts with supplier and renewal countdown"}';

create or replace view procurement.assets_register
with
  (security_invoker = true) as
select
  a.id,
  a.asset_tag,
  a.name,
  a.serial_number,
  cat.name as category,
  a.status,
  a.condition,
  a.manufacturer,
  a.model,
  a.location,
  a.department,
  s.name as supplier,
  a.purchase_date,
  a.purchase_cost,
  a.accumulated_depreciation,
  a.current_value,
  a.currency,
  a.warranty_until,
  case
    when a.warranty_until is null then null
    else (a.warranty_until - current_date)::int
  end as warranty_days_left,
  a.next_inspection_date,
  aa.assignee_name as current_assignee,
  a.created_at
from
  procurement.assets a
  left join procurement.asset_categories cat on cat.id = a.category_id
  left join procurement.suppliers s on s.id = a.supplier_id
  left join lateral (
    select
      assignee_name
    from
      procurement.asset_assignments
    where
      asset_id = a.id
      and status = 'active'
    order by
      assigned_at desc
    limit
      1
  ) aa on true;

revoke all on procurement.assets_register
from
  authenticated,
  service_role;

grant
select
  on procurement.assets_register to "x-admin";

comment on view procurement.assets_register is '{"type": "report", "name": "Assets Register", "description": "Fixed asset register with category, value, and current custodian"}';

create or replace view procurement.asset_maintenance_report
with
  (security_invoker = true) as
select
  am.id,
  am.maintenance_number,
  a.asset_tag,
  a.name as asset,
  am.title,
  am.type,
  am.status,
  am.scheduled_date,
  am.started_at,
  am.completed_at,
  am.cost,
  am.currency,
  u.name as technician,
  s.name as vendor,
  am.next_due_date,
  am.created_at
from
  procurement.asset_maintenance am
  left join procurement.assets a on a.id = am.asset_id
  left join supasheet.users u on u.id = am.technician_user_id
  left join procurement.suppliers s on s.id = am.vendor_supplier_id;

revoke all on procurement.asset_maintenance_report
from
  authenticated,
  service_role;

grant
select
  on procurement.asset_maintenance_report to "x-admin";

comment on view procurement.asset_maintenance_report is '{"type": "report", "name": "Asset Maintenance Report", "description": "Maintenance records with asset, technician, and vendor info"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: total asset current value
create or replace view procurement.asset_value_summary
with
  (security_invoker = true) as
select
  coalesce(
    sum(current_value) filter (
      where
        status not in ('disposed', 'lost')
    ),
    0
  )::numeric(14, 2) as value,
  'building' as icon,
  'asset value' as label
from
  procurement.assets;

revoke all on procurement.asset_value_summary
from
  authenticated,
  service_role;

grant
select
  on procurement.asset_value_summary to "x-admin";

-- card_2: qualified vs pending suppliers
create or replace view procurement.supplier_qualification_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status in ('qualified', 'preferred')
  ) as primary,
  count(*) filter (
    where
      status = 'pending'
  ) as secondary,
  'Qualified' as primary_label,
  'Pending' as secondary_label
from
  procurement.suppliers;

revoke all on procurement.supplier_qualification_split
from
  authenticated,
  service_role;

grant
select
  on procurement.supplier_qualification_split to "x-admin";

-- card_3: open requisitions value + approval rate
create or replace view procurement.open_requisitions_value
with
  (security_invoker = true) as
select
  coalesce(
    sum(estimated_total) filter (
      where
        status in ('submitted', 'approved')
    ),
    0
  )::numeric(14, 2) as value,
  case
    when count(*) filter (
      where
        status in ('approved', 'rejected')
    ) > 0 then round(
      (
        count(*) filter (
          where
            status = 'approved'
        )::numeric / count(*) filter (
          where
            status in ('approved', 'rejected')
        )::numeric
      ) * 100,
      1
    )
    else 0
  end as percent
from
  procurement.requisitions;

revoke all on procurement.open_requisitions_value
from
  authenticated,
  service_role;

grant
select
  on procurement.open_requisitions_value to "x-admin";

-- card_4: procurement health
create or replace view procurement.procurement_health
with
  (security_invoker = true) as
with
  metrics as (
    select
      (
        select
          count(*)
        from
          procurement.requisitions
        where
          status = 'submitted'
          and needed_by_date is not null
          and needed_by_date < current_date
      ) as overdue_reqs,
      (
        select
          count(*)
        from
          procurement.contracts
        where
          status in ('active', 'expiring_soon')
          and end_date is not null
          and end_date <= current_date + interval '60 days'
          and end_date >= current_date
      ) as expiring_contracts,
      (
        select
          count(*)
        from
          procurement.asset_maintenance
        where
          status = 'scheduled'
          and scheduled_date is not null
          and scheduled_date < current_date
      ) as overdue_maintenance,
      (
        select
          count(*)
        from
          procurement.suppliers
        where
          status = 'blacklisted'
      ) as blacklisted,
      (
        select
          count(*)
        from
          procurement.requisitions
        where
          status in ('submitted', 'approved')
      ) as open_reqs
  )
select
  (
    overdue_reqs + expiring_contracts + overdue_maintenance + blacklisted
  ) as current,
  open_reqs as total,
  json_build_array(
    json_build_object(
      'label',
      'Overdue requisitions',
      'value',
      overdue_reqs
    ),
    json_build_object(
      'label',
      'Expiring contracts',
      'value',
      expiring_contracts
    ),
    json_build_object(
      'label',
      'Overdue maintenance',
      'value',
      overdue_maintenance
    ),
    json_build_object('label', 'Blacklisted', 'value', blacklisted)
  ) as segments
from
  metrics;

revoke all on procurement.procurement_health
from
  authenticated,
  service_role;

grant
select
  on procurement.procurement_health to "x-admin";

-- table_1: recent requisitions
create or replace view procurement.recent_requisitions
with
  (security_invoker = true) as
select
  requisition_number as number,
  title,
  coalesce(status::text, '') as status,
  to_char(requested_date, 'MM/DD') as date
from
  procurement.requisitions
order by
  requested_date desc
limit
  10;

revoke all on procurement.recent_requisitions
from
  authenticated,
  service_role;

grant
select
  on procurement.recent_requisitions to "x-admin";

-- table_2: top suppliers by award value
create or replace view procurement.top_suppliers
with
  (security_invoker = true) as
select
  s.name as supplier,
  coalesce(s.tier::text, '') as tier,
  count(q.id) filter (
    where
      q.status = 'awarded'
  ) as awards,
  coalesce(
    sum(q.total_price) filter (
      where
        q.status = 'awarded'
    ),
    0
  ) as awarded_value
from
  procurement.suppliers s
  left join procurement.quotes q on q.supplier_id = s.id
group by
  s.id,
  s.name,
  s.tier
order by
  awarded_value desc nulls last
limit
  10;

revoke all on procurement.top_suppliers
from
  authenticated,
  service_role;

grant
select
  on procurement.top_suppliers to "x-admin";

comment on view procurement.asset_value_summary is '{"type": "dashboard_widget", "name": "Asset Value", "description": "Total current value of active assets", "widget_type": "card_1"}';

comment on view procurement.supplier_qualification_split is '{"type": "dashboard_widget", "name": "Qualified vs Pending", "description": "Supplier qualification status split", "widget_type": "card_2"}';

comment on view procurement.open_requisitions_value is '{"type": "dashboard_widget", "name": "Open Requisitions", "description": "Open requisition value and approval rate", "widget_type": "card_3"}';

comment on view procurement.procurement_health is '{"type": "dashboard_widget", "name": "Procurement Health", "description": "Overdue requisitions, contracts, and maintenance", "widget_type": "card_4"}';

comment on view procurement.recent_requisitions is '{"type": "dashboard_widget", "name": "Recent Requisitions", "description": "Latest 10 requisitions", "widget_type": "table_1"}';

comment on view procurement.top_suppliers is '{"type": "dashboard_widget", "name": "Top Suppliers", "description": "Top 10 suppliers by awarded value", "widget_type": "table_2"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: requisitions by status
create or replace view procurement.requisitions_by_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  procurement.requisitions
group by
  status
order by
  case status
    when 'draft' then 1
    when 'submitted' then 2
    when 'approved' then 3
    when 'rejected' then 4
    when 'converted' then 5
    when 'cancelled' then 6
  end;

revoke all on procurement.requisitions_by_status_pie
from
  authenticated,
  service_role;

grant
select
  on procurement.requisitions_by_status_pie to "x-admin";

-- Bar: assets by category (count + value)
create or replace view procurement.assets_by_category_bar
with
  (security_invoker = true) as
select
  coalesce(cat.name, 'Uncategorized') as label,
  count(a.id) as count,
  coalesce(sum(a.current_value), 0)::bigint as value
from
  procurement.assets a
  left join procurement.asset_categories cat on cat.id = a.category_id
where
  a.status not in ('disposed', 'lost')
group by
  cat.name
order by
  sum(a.current_value) desc nulls last
limit
  10;

revoke all on procurement.assets_by_category_bar
from
  authenticated,
  service_role;

grant
select
  on procurement.assets_by_category_bar to "x-admin";

-- Line: monthly procurement spend (awarded RFQs)
create or replace view procurement.procurement_spend_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', awarded_at), 'Mon YY') as date,
  coalesce(sum(awarded_value), 0)::bigint as awarded,
  count(*)::bigint as awards
from
  procurement.rfqs
where
  status = 'awarded'
  and awarded_at is not null
  and awarded_at >= current_date - interval '12 months'
group by
  date_trunc('month', awarded_at)
order by
  date_trunc('month', awarded_at);

revoke all on procurement.procurement_spend_line
from
  authenticated,
  service_role;

grant
select
  on procurement.procurement_spend_line to "x-admin";

-- Radar: supplier scorecard (averages by dimension across all suppliers)
create or replace view procurement.supplier_scorecard_radar
with
  (security_invoker = true) as
select
  'Quality' as metric,
  round(avg(score_quality)::numeric, 2) as average,
  count(*) filter (
    where
      score_quality is not null
  ) as scored
from
  procurement.suppliers
union all
select
  'Delivery',
  round(avg(score_delivery)::numeric, 2),
  count(*) filter (
    where
      score_delivery is not null
  )
from
  procurement.suppliers
union all
select
  'Cost',
  round(avg(score_cost)::numeric, 2),
  count(*) filter (
    where
      score_cost is not null
  )
from
  procurement.suppliers
union all
select
  'Communication',
  round(avg(score_communication)::numeric, 2),
  count(*) filter (
    where
      score_communication is not null
  )
from
  procurement.suppliers
union all
select
  'Overall',
  round(avg(score_overall)::numeric, 2),
  count(*) filter (
    where
      score_overall is not null
  )
from
  procurement.suppliers;

revoke all on procurement.supplier_scorecard_radar
from
  authenticated,
  service_role;

grant
select
  on procurement.supplier_scorecard_radar to "x-admin";

comment on view procurement.requisitions_by_status_pie is '{"type": "chart", "name": "Requisitions By Status", "description": "Requisition count grouped by status", "chart_type": "pie"}';

comment on view procurement.assets_by_category_bar is '{"type": "chart", "name": "Assets By Category", "description": "Asset count and current value per category", "chart_type": "bar"}';

comment on view procurement.procurement_spend_line is '{"type": "chart", "name": "Procurement Spend", "description": "Monthly awarded value over the last 12 months", "chart_type": "line"}';

comment on view procurement.supplier_scorecard_radar is '{"type": "chart", "name": "Supplier Scorecard", "description": "Average supplier scores across dimensions", "chart_type": "radar"}';

----------------------------------------------------------------
-- Audit triggers
----------------------------------------------------------------
create trigger audit_proc_suppliers_insert
after insert on procurement.suppliers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_suppliers_update
after update on procurement.suppliers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_suppliers_delete
before delete on procurement.suppliers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_contracts_insert
after insert on procurement.contracts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_contracts_update
after update on procurement.contracts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_contracts_delete
before delete on procurement.contracts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_requisitions_insert
after insert on procurement.requisitions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_requisitions_update
after update on procurement.requisitions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_requisitions_delete
before delete on procurement.requisitions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_req_items_insert
after insert on procurement.requisition_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_req_items_update
after update on procurement.requisition_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_req_items_delete
before delete on procurement.requisition_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_rfqs_insert
after insert on procurement.rfqs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_rfqs_update
after update on procurement.rfqs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_rfqs_delete
before delete on procurement.rfqs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_quotes_insert
after insert on procurement.quotes for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_quotes_update
after update on procurement.quotes for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_quotes_delete
before delete on procurement.quotes for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_asset_cats_insert
after insert on procurement.asset_categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_asset_cats_update
after update on procurement.asset_categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_asset_cats_delete
before delete on procurement.asset_categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_assets_insert
after insert on procurement.assets for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_assets_update
after update on procurement.assets for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_assets_delete
before delete on procurement.assets for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_asset_assignments_insert
after insert on procurement.asset_assignments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_asset_assignments_update
after update on procurement.asset_assignments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_asset_assignments_delete
before delete on procurement.asset_assignments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_asset_maintenance_insert
after insert on procurement.asset_maintenance for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_asset_maintenance_update
after update on procurement.asset_maintenance for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_proc_asset_maintenance_delete
before delete on procurement.asset_maintenance for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
-- Requisitions: notify approver on submission, requester on decision
create or replace function procurement.trg_requisitions_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if tg_op = 'INSERT' then
        if new.status <> 'submitted' then
            return new;
        end if;
        v_type  := 'procurement_req_submitted';
        v_title := 'New requisition submitted';
        v_body  := 'Requisition ' || new.requisition_number ||
                   ' (' || coalesce(new.estimated_total::text, '0') || ' ' || new.currency ||
                   ') awaits approval.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('procurement', 'requisitions', 'update')
                || array[new.approver_user_id],
            null
        );
    elsif new.status is distinct from old.status and new.status in ('approved', 'rejected', 'converted', 'cancelled') then
        v_type  := 'procurement_req_' || new.status::text;
        v_title := 'Requisition ' || new.status::text;
        v_body  := 'Requisition ' || new.requisition_number || ' is now ' || new.status::text || '.';
        v_recipients := array_remove(array[new.user_id], null);
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'requisition_id',  new.id,
            'status',          new.status,
            'priority',        new.priority,
            'estimated_total', new.estimated_total
        ),
        '/procurement/resource/requisitions/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists requisitions_notify on procurement.requisitions;

create trigger requisitions_notify
after insert or update of status on procurement.requisitions for each row
execute function procurement.trg_requisitions_notify ();

-- Contracts: notify on creation and status changes (expiring_soon, expired, terminated)
create or replace function procurement.trg_contracts_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_supplier_name text;
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if new.supplier_id is not null then
        select name into v_supplier_name from procurement.suppliers where id = new.supplier_id;
    end if;

    if tg_op = 'INSERT' then
        v_type  := 'procurement_contract_created';
        v_title := 'New contract';
        v_body  := 'Contract ' || new.contract_number ||
                   ' with ' || coalesce(v_supplier_name, 'supplier') || ' was created.';
    elsif new.status is distinct from old.status and new.status in ('active', 'expiring_soon', 'expired', 'terminated') then
        v_type  := 'procurement_contract_' || new.status::text;
        v_title := 'Contract ' || new.status::text;
        v_body  := 'Contract ' || new.contract_number ||
                   ' with ' || coalesce(v_supplier_name, 'supplier') ||
                   ' is now ' || new.status::text || '.';
    else
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('procurement', 'contracts', 'select')
            || array[new.user_id, new.signed_by_user_id],
        null
    );

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'contract_id', new.id,
            'supplier_id', new.supplier_id,
            'status',      new.status,
            'end_date',    new.end_date,
            'value',       new.value
        ),
        '/procurement/resource/contracts/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists contracts_notify on procurement.contracts;

create trigger contracts_notify
after insert or update of status on procurement.contracts for each row
execute function procurement.trg_contracts_notify ();

-- Asset maintenance: notify technician + asset owner on schedule and completion
create or replace function procurement.trg_asset_maintenance_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_asset_owner uuid;
    v_asset_tag text;
    v_asset_name text;
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if new.asset_id is not null then
        select user_id, asset_tag, name
          into v_asset_owner, v_asset_tag, v_asset_name
          from procurement.assets where id = new.asset_id;
    end if;

    if tg_op = 'INSERT' then
        if new.status <> 'scheduled' then
            return new;
        end if;
        v_type  := 'procurement_maintenance_scheduled';
        v_title := 'Maintenance scheduled';
        v_body  := new.type::text || ' maintenance "' || new.title || '" scheduled for ' ||
                   coalesce(v_asset_name, 'asset') ||
                   coalesce(' on ' || to_char(new.scheduled_date, 'YYYY-MM-DD'), '') || '.';
    elsif new.status is distinct from old.status and new.status in ('in_progress', 'completed', 'cancelled') then
        v_type  := 'procurement_maintenance_' || new.status::text;
        v_title := 'Maintenance ' || new.status::text;
        v_body  := 'Maintenance ' || new.maintenance_number ||
                   ' on ' || coalesce(v_asset_name, 'asset') ||
                   ' is now ' || new.status::text || '.';
    else
        return new;
    end if;

    v_recipients := array_remove(
        array[new.technician_user_id, v_asset_owner, new.user_id],
        null
    );

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'maintenance_id', new.id,
            'asset_id',       new.asset_id,
            'asset_tag',      v_asset_tag,
            'type',           new.type,
            'status',         new.status,
            'scheduled_date', new.scheduled_date
        ),
        '/procurement/resource/asset_maintenance/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists asset_maintenance_notify on procurement.asset_maintenance;

create trigger asset_maintenance_notify
after insert or update of status on procurement.asset_maintenance for each row
execute function procurement.trg_asset_maintenance_notify ();
