create schema if not exists quality;

grant usage on schema quality to authenticated;

----------------------------------------------------------------
-- Enums
----------------------------------------------------------------
create type quality.standard_type as enum('iso', 'regulatory', 'internal', 'customer_spec');

create type quality.standard_status as enum('draft', 'active', 'superseded', 'retired');

create type quality.inspection_type as enum(
  'incoming',
  'in_process',
  'final',
  'first_article',
  'supplier_audit'
);

create type quality.inspection_result as enum(
  'pending',
  'passed',
  'failed',
  'conditional',
  'cancelled'
);

create type quality.inspection_item_result as enum('pending', 'pass', 'fail', 'na');

create type quality.ncr_severity as enum('minor', 'major', 'critical');

create type quality.ncr_status as enum(
  'open',
  'investigating',
  'resolved',
  'closed',
  'cancelled'
);

create type quality.ncr_disposition as enum(
  'rework',
  'scrap',
  'use_as_is',
  'return_to_supplier',
  'rework_under_concession'
);

create type quality.capa_type as enum('corrective', 'preventive');

create type quality.capa_status as enum(
  'open',
  'in_progress',
  'verification',
  'closed',
  'cancelled'
);

create type quality.capa_priority as enum('low', 'medium', 'high', 'critical');

create type quality.audit_type as enum('internal', 'external', 'supplier', 'regulatory');

create type quality.audit_status as enum(
  'planned',
  'in_progress',
  'completed',
  'closed',
  'cancelled'
);

create type quality.finding_severity as enum('observation', 'minor', 'major', 'critical');

create type quality.finding_status as enum(
  'open',
  'in_progress',
  'resolved',
  'verified',
  'closed'
);

create type quality.certification_status as enum(
  'pending',
  'active',
  'expiring_soon',
  'expired',
  'suspended'
);

create type quality.complaint_severity as enum('low', 'medium', 'high', 'critical');

create type quality.complaint_status as enum(
  'received',
  'investigating',
  'resolved',
  'closed',
  'rejected'
);

----------------------------------------------------------------
-- Users mirror view
----------------------------------------------------------------
create or replace view quality.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on quality.users
from
  authenticated,
  service_role;

grant
select
  on quality.users to "x-admin";

----------------------------------------------------------------
-- Standards (quality specs / regulatory references)
----------------------------------------------------------------
create table quality.standards (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(100) unique not null,
  name varchar(500) not null,
  version varchar(50) default '1.0',
  type quality.standard_type default 'internal',
  status quality.standard_status default 'draft',
  description supasheet.RICH_TEXT,
  scope text,
  issued_by varchar(255),
  effective_from date,
  review_due_date date,
  superseded_by_id uuid references quality.standards (id) on delete set null,
  document supasheet.file,
  attachments supasheet.file,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.standards.type is '{
    "progress": false,
    "enums": {
        "iso":           {"variant": "info",      "icon": "BadgeCheck"},
        "regulatory":    {"variant": "warning",   "icon": "Scale"},
        "internal":      {"variant": "secondary", "icon": "Building"},
        "customer_spec": {"variant": "success",   "icon": "UserCheck"}
    }
}';

comment on column quality.standards.status is '{
    "progress": true,
    "enums": {
        "draft":      {"variant": "outline",     "icon": "FileEdit"},
        "active":     {"variant": "success",     "icon": "CircleCheck"},
        "superseded": {"variant": "warning",     "icon": "Replace"},
        "retired":    {"variant": "destructive", "icon": "Archive"}
    }
}';

comment on table quality.standards is '{
    "icon": "BookCheck",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Standards By Status",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "code",
            "date": "effective_from",
            "badge": "type"
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
                    "version",
                    "type",
                    "status",
                    "description"
                ]
            },
            {
                "id": "scope",
                "title": "Scope",
                "fields": [
                    "scope",
                    "issued_by"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "effective_from",
                    "review_due_date",
                    "superseded_by_id"
                ]
            },
            {
                "id": "extras",
                "title": "Document, Tags & Notes",
                "collapsible": true,
                "fields": [
                    "document",
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
            },
            {
                "table": "standards",
                "on": "superseded_by_id",
                "columns": [
                    "code",
                    "name"
                ]
            }
        ]
    }
}';

comment on column quality.standards.document is '{"accept":"application/pdf,.doc,.docx", "maxFiles": 1}';

comment on column quality.standards.attachments is '{"accept":"*", "maxFiles": 10}';

revoke all on table quality.standards
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table quality.standards to "x-admin";

create index idx_qms_standards_user_id on quality.standards (user_id);

create index idx_qms_standards_type on quality.standards (type);

create index idx_qms_standards_status on quality.standards (status);

create index idx_qms_standards_review_due_date on quality.standards (review_due_date);

alter table quality.standards enable row level security;

create policy standards_select on quality.standards for
select
  to authenticated using (true);

create policy standards_insert on quality.standards for insert to authenticated
with
  check (true);

create policy standards_update on quality.standards
for update
  to authenticated using (true)
with
  check (true);

create policy standards_delete on quality.standards for delete to authenticated using (true);

----------------------------------------------------------------
-- Inspections
----------------------------------------------------------------
create table quality.inspections (
  id uuid primary key default extensions.uuid_generate_v4 (),
  inspection_number varchar(50) unique not null,
  title varchar(500) not null,
  type quality.inspection_type default 'incoming',
  result quality.inspection_result default 'pending',
  standard_id uuid references quality.standards (id) on delete set null,
  -- Polymorphic source: PO / WO / shipment / supplier (free-form to keep module independent)
  source_type varchar(50),
  source_reference varchar(255),
  source_id uuid,
  supplier_name varchar(500),
  product_sku varchar(100),
  product_name varchar(500),
  lot_number varchar(100),
  sample_size integer default 1,
  pass_count integer default 0,
  fail_count integer default 0,
  inspector_user_id uuid references supasheet.users (id) on delete set null,
  scheduled_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  description supasheet.RICH_TEXT,
  findings text,
  attachments supasheet.file,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.inspections.type is '{
    "progress": false,
    "enums": {
        "incoming":       {"variant": "info",      "icon": "PackageOpen"},
        "in_process":     {"variant": "warning",   "icon": "Loader"},
        "final":          {"variant": "success",   "icon": "PackageCheck"},
        "first_article":  {"variant": "info",      "icon": "Sparkles"},
        "supplier_audit": {"variant": "secondary", "icon": "Factory"}
    }
}';

comment on column quality.inspections.result is '{
    "progress": true,
    "enums": {
        "pending":     {"variant": "outline",     "icon": "Clock"},
        "passed":      {"variant": "success",     "icon": "CircleCheck"},
        "failed":      {"variant": "destructive", "icon": "XCircle"},
        "conditional": {"variant": "warning",     "icon": "AlertTriangle"},
        "cancelled":   {"variant": "outline",     "icon": "Ban"}
    }
}';

comment on table quality.inspections is '{
    "icon": "ShieldCheck",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Inspections By Result",
            "type": "kanban",
            "group": "result",
            "title": "inspection_number",
            "description": "title",
            "date": "scheduled_at",
            "badge": "type"
        },
        {
            "id": "calendar",
            "name": "Inspection Calendar",
            "type": "calendar",
            "title": "inspection_number",
            "badge": "result",
            "start_date": "scheduled_at",
            "end_date": "completed_at"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "inspection_number",
                    "title",
                    "type",
                    "result",
                    "description"
                ]
            },
            {
                "id": "source",
                "title": "Source",
                "fields": [
                    "source_type",
                    "source_reference",
                    "source_id",
                    "supplier_name"
                ]
            },
            {
                "id": "product",
                "title": "Product",
                "fields": [
                    "product_sku",
                    "product_name",
                    "lot_number",
                    "standard_id"
                ]
            },
            {
                "id": "sampling",
                "title": "Sampling",
                "fields": [
                    "sample_size",
                    "pass_count",
                    "fail_count"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "inspector_user_id",
                    "scheduled_at",
                    "started_at",
                    "completed_at"
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
                "id": "scheduled_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "standards",
                "on": "standard_id",
                "columns": [
                    "code",
                    "name"
                ]
            },
            {
                "table": "users",
                "on": "inspector_user_id",
                "alias": "inspector_user",
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

comment on column quality.inspections.attachments is '{"accept":"*", "maxFiles": 20}';

revoke all on table quality.inspections
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table quality.inspections to "x-admin";

create index idx_qms_inspections_user_id on quality.inspections (user_id);

create index idx_qms_inspections_inspector on quality.inspections (inspector_user_id);

create index idx_qms_inspections_standard_id on quality.inspections (standard_id);

create index idx_qms_inspections_type on quality.inspections (type);

create index idx_qms_inspections_result on quality.inspections (result);

create index idx_qms_inspections_scheduled_at on quality.inspections (scheduled_at desc);

create index idx_qms_inspections_product_sku on quality.inspections (product_sku);

create index idx_qms_inspections_source_id on quality.inspections (source_id);

alter table quality.inspections enable row level security;

create policy inspections_select on quality.inspections for
select
  to authenticated using (true);

create policy inspections_insert on quality.inspections for insert to authenticated
with
  check (true);

create policy inspections_update on quality.inspections
for update
  to authenticated using (true)
with
  check (true);

create policy inspections_delete on quality.inspections for delete to authenticated using (true);

----------------------------------------------------------------
-- Inspection items (line items checked)
----------------------------------------------------------------
create table quality.inspection_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  inspection_id uuid not null references quality.inspections (id) on delete cascade,
  line_number integer default 0,
  characteristic varchar(500) not null,
  method varchar(255),
  specification varchar(500),
  measured_value varchar(255),
  tolerance varchar(255),
  result quality.inspection_item_result default 'pending',
  notes text,
  created_at timestamptz default current_timestamp
);

comment on column quality.inspection_items.result is '{
    "progress": true,
    "enums": {
        "pending": {"variant": "outline",     "icon": "Clock"},
        "pass":    {"variant": "success",     "icon": "CircleCheck"},
        "fail":    {"variant": "destructive", "icon": "XCircle"},
        "na":      {"variant": "secondary",   "icon": "MinusCircle"}
    }
}';

comment on table quality.inspection_items is '{
    "icon": "ListChecks",
    "display": "none",
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "inspection_id",
                    "line_number"
                ]
            },
            {
                "id": "check",
                "title": "Check",
                "fields": [
                    "characteristic",
                    "method",
                    "specification"
                ]
            },
            {
                "id": "result",
                "title": "Result",
                "fields": [
                    "measured_value",
                    "tolerance",
                    "result"
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
                "table": "inspections",
                "on": "inspection_id",
                "columns": [
                    "inspection_number",
                    "title"
                ]
            }
        ]
    }
}';

revoke all on table quality.inspection_items
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table quality.inspection_items to "x-admin";

create index idx_qms_inspection_items_inspection_id on quality.inspection_items (inspection_id);

create index idx_qms_inspection_items_result on quality.inspection_items (result);

alter table quality.inspection_items enable row level security;

create policy inspection_items_select on quality.inspection_items for
select
  to authenticated using (true);

create policy inspection_items_insert on quality.inspection_items for insert to authenticated
with
  check (true);

create policy inspection_items_update on quality.inspection_items
for update
  to authenticated using (true)
with
  check (true);

create policy inspection_items_delete on quality.inspection_items for delete to authenticated using (true);

----------------------------------------------------------------
-- Non-conformances (NCRs)
----------------------------------------------------------------
create table quality.non_conformances (
  id uuid primary key default extensions.uuid_generate_v4 (),
  ncr_number varchar(50) unique not null,
  title varchar(500) not null,
  severity quality.ncr_severity default 'minor',
  status quality.ncr_status default 'open',
  disposition quality.ncr_disposition,
  inspection_id uuid references quality.inspections (id) on delete set null,
  -- Polymorphic source
  source_type varchar(50),
  source_reference varchar(255),
  source_id uuid,
  supplier_name varchar(500),
  product_sku varchar(100),
  product_name varchar(500),
  lot_number varchar(100),
  quantity_affected integer default 0,
  estimated_cost numeric(12, 2) default 0,
  currency varchar(3) default 'USD',
  description supasheet.RICH_TEXT,
  root_cause text,
  discovered_at timestamptz default current_timestamp,
  resolved_at timestamptz,
  closed_at timestamptz,
  assigned_user_id uuid references supasheet.users (id) on delete set null,
  attachments supasheet.file,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.non_conformances.severity is '{
    "progress": false,
    "enums": {
        "minor":    {"variant": "info",        "icon": "AlertCircle"},
        "major":    {"variant": "warning",     "icon": "AlertTriangle"},
        "critical": {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on column quality.non_conformances.status is '{
    "progress": true,
    "enums": {
        "open":          {"variant": "destructive", "icon": "AlertCircle"},
        "investigating": {"variant": "warning",     "icon": "Search"},
        "resolved":      {"variant": "info",        "icon": "Wrench"},
        "closed":        {"variant": "success",     "icon": "CircleCheck"},
        "cancelled":     {"variant": "outline",     "icon": "Ban"}
    }
}';

comment on column quality.non_conformances.disposition is '{
    "progress": false,
    "enums": {
        "rework":                 {"variant": "warning",     "icon": "RotateCcw"},
        "scrap":                  {"variant": "destructive", "icon": "Trash2"},
        "use_as_is":              {"variant": "info",        "icon": "Check"},
        "return_to_supplier":     {"variant": "outline",     "icon": "Undo2"},
        "rework_under_concession":{"variant": "warning",     "icon": "FileSignature"}
    }
}';

comment on table quality.non_conformances is '{
    "icon": "AlertOctagon",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "NCRs By Status",
            "type": "kanban",
            "group": "status",
            "title": "ncr_number",
            "description": "title",
            "date": "discovered_at",
            "badge": "severity"
        },
        {
            "id": "calendar",
            "name": "NCR Calendar",
            "type": "calendar",
            "title": "ncr_number",
            "badge": "status",
            "start_date": "discovered_at",
            "end_date": "closed_at"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "ncr_number",
                    "title",
                    "severity",
                    "status",
                    "disposition",
                    "description"
                ]
            },
            {
                "id": "source",
                "title": "Source",
                "fields": [
                    "inspection_id",
                    "source_type",
                    "source_reference",
                    "source_id",
                    "supplier_name"
                ]
            },
            {
                "id": "product",
                "title": "Product & Impact",
                "fields": [
                    "product_sku",
                    "product_name",
                    "lot_number",
                    "quantity_affected",
                    "estimated_cost",
                    "currency"
                ]
            },
            {
                "id": "investigation",
                "title": "Investigation",
                "fields": [
                    "root_cause",
                    "assigned_user_id"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "discovered_at",
                    "resolved_at",
                    "closed_at"
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
                "id": "discovered_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "inspections",
                "on": "inspection_id",
                "columns": [
                    "inspection_number",
                    "title"
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

comment on column quality.non_conformances.attachments is '{"accept":"*", "maxFiles": 20}';

revoke all on table quality.non_conformances
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table quality.non_conformances to "x-admin";

create index idx_qms_ncr_user_id on quality.non_conformances (user_id);

create index idx_qms_ncr_assigned_user_id on quality.non_conformances (assigned_user_id);

create index idx_qms_ncr_inspection_id on quality.non_conformances (inspection_id);

create index idx_qms_ncr_severity on quality.non_conformances (severity);

create index idx_qms_ncr_status on quality.non_conformances (status);

create index idx_qms_ncr_discovered_at on quality.non_conformances (discovered_at desc);

create index idx_qms_ncr_product_sku on quality.non_conformances (product_sku);

alter table quality.non_conformances enable row level security;

create policy non_conformances_select on quality.non_conformances for
select
  to authenticated using (true);

create policy non_conformances_insert on quality.non_conformances for insert to authenticated
with
  check (true);

create policy non_conformances_update on quality.non_conformances
for update
  to authenticated using (true)
with
  check (true);

create policy non_conformances_delete on quality.non_conformances for delete to authenticated using (true);

----------------------------------------------------------------
-- CAPA (corrective and preventive actions)
----------------------------------------------------------------
create table quality.capa (
  id uuid primary key default extensions.uuid_generate_v4 (),
  capa_number varchar(50) unique not null,
  title varchar(500) not null,
  type quality.capa_type default 'corrective',
  status quality.capa_status default 'open',
  priority quality.capa_priority default 'medium',
  ncr_id uuid references quality.non_conformances (id) on delete set null,
  audit_finding_id uuid,
  description supasheet.RICH_TEXT,
  root_cause text,
  corrective_action text,
  preventive_action text,
  verification_plan text,
  owner_user_id uuid references supasheet.users (id) on delete set null,
  verifier_user_id uuid references supasheet.users (id) on delete set null,
  opened_at timestamptz default current_timestamp,
  target_close_date date,
  closed_at timestamptz,
  effectiveness_score supasheet.RATING,
  cost numeric(12, 2) default 0,
  currency varchar(3) default 'USD',
  attachments supasheet.file,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.capa.type is '{
    "progress": false,
    "enums": {
        "corrective": {"variant": "warning", "icon": "Wrench"},
        "preventive": {"variant": "info",    "icon": "ShieldCheck"}
    }
}';

comment on column quality.capa.status is '{
    "progress": true,
    "enums": {
        "open":         {"variant": "destructive", "icon": "AlertCircle"},
        "in_progress":  {"variant": "warning",     "icon": "Loader"},
        "verification": {"variant": "info",        "icon": "Search"},
        "closed":       {"variant": "success",     "icon": "CircleCheck"},
        "cancelled":    {"variant": "outline",     "icon": "Ban"}
    }
}';

comment on column quality.capa.priority is '{
    "progress": false,
    "enums": {
        "low":      {"variant": "outline",     "icon": "CircleArrowDown"},
        "medium":   {"variant": "info",        "icon": "CircleMinus"},
        "high":     {"variant": "warning",     "icon": "CircleArrowUp"},
        "critical": {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on table quality.capa is '{
    "icon": "Wrench",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "CAPA By Status",
            "type": "kanban",
            "group": "status",
            "title": "capa_number",
            "description": "title",
            "date": "target_close_date",
            "badge": "priority"
        },
        {
            "id": "calendar",
            "name": "CAPA Calendar",
            "type": "calendar",
            "title": "capa_number",
            "badge": "status",
            "start_date": "opened_at",
            "end_date": "target_close_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "capa_number",
                    "title",
                    "type",
                    "status",
                    "priority",
                    "description"
                ]
            },
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "ncr_id",
                    "audit_finding_id"
                ]
            },
            {
                "id": "investigation",
                "title": "Investigation",
                "fields": [
                    "root_cause",
                    "corrective_action",
                    "preventive_action",
                    "verification_plan"
                ]
            },
            {
                "id": "ownership",
                "title": "Ownership",
                "fields": [
                    "owner_user_id",
                    "verifier_user_id"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "opened_at",
                    "target_close_date",
                    "closed_at"
                ]
            },
            {
                "id": "effectiveness",
                "title": "Effectiveness",
                "fields": [
                    "effectiveness_score",
                    "cost",
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
                "id": "opened_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "non_conformances",
                "on": "ncr_id",
                "columns": [
                    "ncr_number",
                    "title"
                ]
            },
            {
                "table": "users",
                "on": "owner_user_id",
                "alias": "owner_user",
                "columns": [
                    "name",
                    "email"
                ]
            },
            {
                "table": "users",
                "on": "verifier_user_id",
                "alias": "verifier_user",
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

comment on column quality.capa.attachments is '{"accept":"*", "maxFiles": 20}';

revoke all on table quality.capa
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table quality.capa to "x-admin";

create index idx_qms_capa_user_id on quality.capa (user_id);

create index idx_qms_capa_owner_user_id on quality.capa (owner_user_id);

create index idx_qms_capa_verifier_user_id on quality.capa (verifier_user_id);

create index idx_qms_capa_ncr_id on quality.capa (ncr_id);

create index idx_qms_capa_status on quality.capa (status);

create index idx_qms_capa_priority on quality.capa (priority);

create index idx_qms_capa_target_close_date on quality.capa (target_close_date);

alter table quality.capa enable row level security;

create policy capa_select on quality.capa for
select
  to authenticated using (true);

create policy capa_insert on quality.capa for insert to authenticated
with
  check (true);

create policy capa_update on quality.capa
for update
  to authenticated using (true)
with
  check (true);

create policy capa_delete on quality.capa for delete to authenticated using (true);

----------------------------------------------------------------
-- Audits
----------------------------------------------------------------
create table quality.audits (
  id uuid primary key default extensions.uuid_generate_v4 (),
  audit_number varchar(50) unique not null,
  title varchar(500) not null,
  type quality.audit_type default 'internal',
  status quality.audit_status default 'planned',
  standard_id uuid references quality.standards (id) on delete set null,
  auditee varchar(500),
  auditor_user_id uuid references supasheet.users (id) on delete set null,
  external_auditor varchar(500),
  scope text,
  objectives text,
  scheduled_date date,
  started_at timestamptz,
  completed_at timestamptz,
  closed_at timestamptz,
  overall_score supasheet.RATING,
  summary supasheet.RICH_TEXT,
  report supasheet.file,
  attachments supasheet.file,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.audits.type is '{
    "progress": false,
    "enums": {
        "internal":   {"variant": "info",      "icon": "Building"},
        "external":   {"variant": "warning",   "icon": "Globe"},
        "supplier":   {"variant": "secondary", "icon": "Factory"},
        "regulatory": {"variant": "destructive","icon": "Scale"}
    }
}';

comment on column quality.audits.status is '{
    "progress": true,
    "enums": {
        "planned":     {"variant": "outline",     "icon": "Calendar"},
        "in_progress": {"variant": "warning",     "icon": "Loader"},
        "completed":   {"variant": "info",        "icon": "ClipboardCheck"},
        "closed":      {"variant": "success",     "icon": "CircleCheck"},
        "cancelled":   {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table quality.audits is '{
    "icon": "ClipboardCheck",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Audits By Status",
            "type": "kanban",
            "group": "status",
            "title": "audit_number",
            "description": "title",
            "date": "scheduled_date",
            "badge": "type"
        },
        {
            "id": "calendar",
            "name": "Audit Calendar",
            "type": "calendar",
            "title": "audit_number",
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
                    "audit_number",
                    "title",
                    "type",
                    "status",
                    "standard_id",
                    "summary"
                ]
            },
            {
                "id": "parties",
                "title": "Parties",
                "fields": [
                    "auditee",
                    "auditor_user_id",
                    "external_auditor"
                ]
            },
            {
                "id": "plan",
                "title": "Plan",
                "fields": [
                    "scope",
                    "objectives"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "scheduled_date",
                    "started_at",
                    "completed_at",
                    "closed_at"
                ]
            },
            {
                "id": "outcome",
                "title": "Outcome",
                "fields": [
                    "overall_score",
                    "report"
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
                "id": "scheduled_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "standards",
                "on": "standard_id",
                "columns": [
                    "code",
                    "name"
                ]
            },
            {
                "table": "users",
                "on": "auditor_user_id",
                "alias": "auditor_user",
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

comment on column quality.audits.report is '{"accept":"application/pdf,.doc,.docx", "maxFiles": 1}';

comment on column quality.audits.attachments is '{"accept":"*", "maxFiles": 20}';

revoke all on table quality.audits
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table quality.audits to "x-admin";

create index idx_qms_audits_user_id on quality.audits (user_id);

create index idx_qms_audits_auditor on quality.audits (auditor_user_id);

create index idx_qms_audits_standard_id on quality.audits (standard_id);

create index idx_qms_audits_type on quality.audits (type);

create index idx_qms_audits_status on quality.audits (status);

create index idx_qms_audits_scheduled_date on quality.audits (scheduled_date desc);

alter table quality.audits enable row level security;

create policy audits_select on quality.audits for
select
  to authenticated using (true);

create policy audits_insert on quality.audits for insert to authenticated
with
  check (true);

create policy audits_update on quality.audits
for update
  to authenticated using (true)
with
  check (true);

create policy audits_delete on quality.audits for delete to authenticated using (true);

----------------------------------------------------------------
-- Audit findings
----------------------------------------------------------------
create table quality.audit_findings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  finding_number varchar(50) unique not null,
  audit_id uuid not null references quality.audits (id) on delete cascade,
  severity quality.finding_severity default 'minor',
  status quality.finding_status default 'open',
  clause varchar(255),
  title varchar(500) not null,
  description supasheet.RICH_TEXT,
  evidence text,
  recommendation text,
  capa_id uuid references quality.capa (id) on delete set null,
  owner_user_id uuid references supasheet.users (id) on delete set null,
  target_close_date date,
  closed_at timestamptz,
  attachments supasheet.file,
  tags varchar(255) [],
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.audit_findings.severity is '{
    "progress": false,
    "enums": {
        "observation": {"variant": "outline",     "icon": "Eye"},
        "minor":       {"variant": "info",        "icon": "AlertCircle"},
        "major":       {"variant": "warning",     "icon": "AlertTriangle"},
        "critical":    {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on column quality.audit_findings.status is '{
    "progress": true,
    "enums": {
        "open":        {"variant": "destructive", "icon": "AlertCircle"},
        "in_progress": {"variant": "warning",     "icon": "Loader"},
        "resolved":    {"variant": "info",        "icon": "Wrench"},
        "verified":    {"variant": "info",        "icon": "Search"},
        "closed":      {"variant": "success",     "icon": "CircleCheck"}
    }
}';

comment on table quality.audit_findings is '{
    "icon": "FileWarning",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Findings By Status",
            "type": "kanban",
            "group": "status",
            "title": "finding_number",
            "description": "title",
            "date": "target_close_date",
            "badge": "severity"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "finding_number",
                    "audit_id",
                    "clause",
                    "title",
                    "severity",
                    "status",
                    "description"
                ]
            },
            {
                "id": "evidence",
                "title": "Evidence & Recommendation",
                "fields": [
                    "evidence",
                    "recommendation"
                ]
            },
            {
                "id": "action",
                "title": "Action",
                "fields": [
                    "capa_id",
                    "owner_user_id",
                    "target_close_date",
                    "closed_at"
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
                "id": "created_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "audits",
                "on": "audit_id",
                "columns": [
                    "audit_number",
                    "title"
                ]
            },
            {
                "table": "capa",
                "on": "capa_id",
                "columns": [
                    "capa_number",
                    "title"
                ]
            },
            {
                "table": "users",
                "on": "owner_user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column quality.audit_findings.attachments is '{"accept":"*", "maxFiles": 10}';

revoke all on table quality.audit_findings
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table quality.audit_findings to "x-admin";

create index idx_qms_findings_audit_id on quality.audit_findings (audit_id);

create index idx_qms_findings_capa_id on quality.audit_findings (capa_id);

create index idx_qms_findings_owner_user_id on quality.audit_findings (owner_user_id);

create index idx_qms_findings_severity on quality.audit_findings (severity);

create index idx_qms_findings_status on quality.audit_findings (status);

create index idx_qms_findings_target_close_date on quality.audit_findings (target_close_date);

alter table quality.audit_findings enable row level security;

create policy audit_findings_select on quality.audit_findings for
select
  to authenticated using (true);

create policy audit_findings_insert on quality.audit_findings for insert to authenticated
with
  check (true);

create policy audit_findings_update on quality.audit_findings
for update
  to authenticated using (true)
with
  check (true);

create policy audit_findings_delete on quality.audit_findings for delete to authenticated using (true);

----------------------------------------------------------------
-- Certifications (held by org)
----------------------------------------------------------------
create table quality.certifications (
  id uuid primary key default extensions.uuid_generate_v4 (),
  certificate_number varchar(100) unique not null,
  name varchar(500) not null,
  standard_id uuid references quality.standards (id) on delete set null,
  status quality.certification_status default 'pending',
  issuing_body varchar(500),
  scope text,
  issued_date date,
  expiry_date date,
  last_audit_date date,
  next_audit_date date,
  contact_user_id uuid references supasheet.users (id) on delete set null,
  document supasheet.file,
  attachments supasheet.file,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.certifications.status is '{
    "progress": true,
    "enums": {
        "pending":       {"variant": "outline",     "icon": "Clock"},
        "active":        {"variant": "success",     "icon": "BadgeCheck"},
        "expiring_soon": {"variant": "warning",     "icon": "AlertTriangle"},
        "expired":       {"variant": "destructive", "icon": "XCircle"},
        "suspended":     {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table quality.certifications is '{
    "icon": "Award",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Certifications By Status",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "certificate_number",
            "date": "expiry_date",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Certification Calendar",
            "type": "calendar",
            "title": "name",
            "badge": "status",
            "start_date": "issued_date",
            "end_date": "expiry_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "certificate_number",
                    "name",
                    "standard_id",
                    "status",
                    "scope"
                ]
            },
            {
                "id": "issuance",
                "title": "Issuance",
                "fields": [
                    "issuing_body",
                    "issued_date",
                    "expiry_date"
                ]
            },
            {
                "id": "audits",
                "title": "Audits",
                "fields": [
                    "last_audit_date",
                    "next_audit_date"
                ]
            },
            {
                "id": "ownership",
                "title": "Ownership",
                "fields": [
                    "contact_user_id"
                ]
            },
            {
                "id": "extras",
                "title": "Document & Notes",
                "collapsible": true,
                "fields": [
                    "document",
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
                "id": "expiry_date",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "standards",
                "on": "standard_id",
                "columns": [
                    "code",
                    "name"
                ]
            },
            {
                "table": "users",
                "on": "contact_user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column quality.certifications.document is '{"accept":"application/pdf", "maxFiles": 1}';

comment on column quality.certifications.attachments is '{"accept":"*", "maxFiles": 10}';

revoke all on table quality.certifications
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table quality.certifications to "x-admin";

create index idx_qms_certs_user_id on quality.certifications (user_id);

create index idx_qms_certs_contact_user_id on quality.certifications (contact_user_id);

create index idx_qms_certs_standard_id on quality.certifications (standard_id);

create index idx_qms_certs_status on quality.certifications (status);

create index idx_qms_certs_expiry_date on quality.certifications (expiry_date);

alter table quality.certifications enable row level security;

create policy certifications_select on quality.certifications for
select
  to authenticated using (true);

create policy certifications_insert on quality.certifications for insert to authenticated
with
  check (true);

create policy certifications_update on quality.certifications
for update
  to authenticated using (true)
with
  check (true);

create policy certifications_delete on quality.certifications for delete to authenticated using (true);

----------------------------------------------------------------
-- Customer complaints
----------------------------------------------------------------
create table quality.complaints (
  id uuid primary key default extensions.uuid_generate_v4 (),
  complaint_number varchar(50) unique not null,
  title varchar(500) not null,
  severity quality.complaint_severity default 'medium',
  status quality.complaint_status default 'received',
  customer_name varchar(500),
  customer_email supasheet.EMAIL,
  product_sku varchar(100),
  product_name varchar(500),
  lot_number varchar(100),
  order_reference varchar(255),
  received_at timestamptz default current_timestamp,
  resolved_at timestamptz,
  closed_at timestamptz,
  description supasheet.RICH_TEXT,
  response text,
  resolution text,
  ncr_id uuid references quality.non_conformances (id) on delete set null,
  capa_id uuid references quality.capa (id) on delete set null,
  assigned_user_id uuid references supasheet.users (id) on delete set null,
  attachments supasheet.file,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.complaints.severity is '{
    "progress": false,
    "enums": {
        "low":      {"variant": "outline",     "icon": "CircleArrowDown"},
        "medium":   {"variant": "info",        "icon": "CircleMinus"},
        "high":     {"variant": "warning",     "icon": "CircleArrowUp"},
        "critical": {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on column quality.complaints.status is '{
    "progress": true,
    "enums": {
        "received":      {"variant": "outline",     "icon": "Inbox"},
        "investigating": {"variant": "warning",     "icon": "Search"},
        "resolved":      {"variant": "info",        "icon": "Wrench"},
        "closed":        {"variant": "success",     "icon": "CircleCheck"},
        "rejected":      {"variant": "destructive", "icon": "XCircle"}
    }
}';

comment on table quality.complaints is '{
    "icon": "MessageSquareWarning",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Complaints By Status",
            "type": "kanban",
            "group": "status",
            "title": "complaint_number",
            "description": "title",
            "date": "received_at",
            "badge": "severity"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "complaint_number",
                    "title",
                    "severity",
                    "status",
                    "description"
                ]
            },
            {
                "id": "customer",
                "title": "Customer",
                "fields": [
                    "customer_name",
                    "customer_email",
                    "order_reference"
                ]
            },
            {
                "id": "product",
                "title": "Product",
                "fields": [
                    "product_sku",
                    "product_name",
                    "lot_number"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "received_at",
                    "resolved_at",
                    "closed_at"
                ]
            },
            {
                "id": "action",
                "title": "Action",
                "fields": [
                    "assigned_user_id",
                    "response",
                    "resolution",
                    "ncr_id",
                    "capa_id"
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
                "id": "received_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "non_conformances",
                "on": "ncr_id",
                "columns": [
                    "ncr_number",
                    "title"
                ]
            },
            {
                "table": "capa",
                "on": "capa_id",
                "columns": [
                    "capa_number",
                    "title"
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

comment on column quality.complaints.attachments is '{"accept":"*", "maxFiles": 10}';

revoke all on table quality.complaints
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table quality.complaints to "x-admin";

create index idx_qms_complaints_user_id on quality.complaints (user_id);

create index idx_qms_complaints_assigned_user_id on quality.complaints (assigned_user_id);

create index idx_qms_complaints_ncr_id on quality.complaints (ncr_id);

create index idx_qms_complaints_capa_id on quality.complaints (capa_id);

create index idx_qms_complaints_severity on quality.complaints (severity);

create index idx_qms_complaints_status on quality.complaints (status);

create index idx_qms_complaints_received_at on quality.complaints (received_at desc);

create index idx_qms_complaints_product_sku on quality.complaints (product_sku);

alter table quality.complaints enable row level security;

create policy complaints_select on quality.complaints for
select
  to authenticated using (true);

create policy complaints_insert on quality.complaints for insert to authenticated
with
  check (true);

create policy complaints_update on quality.complaints
for update
  to authenticated using (true)
with
  check (true);

create policy complaints_delete on quality.complaints for delete to authenticated using (true);

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view quality.inspections_report
with
  (security_invoker = true) as
select
  i.id,
  i.inspection_number,
  i.title,
  i.type,
  i.result,
  s.code as standard_code,
  s.name as standard_name,
  i.product_sku,
  i.product_name,
  i.lot_number,
  i.sample_size,
  i.pass_count,
  i.fail_count,
  case
    when i.sample_size > 0 then round(
      (i.pass_count::numeric / i.sample_size::numeric) * 100,
      1
    )
    else null
  end as pass_rate_pct,
  u.name as inspector,
  i.scheduled_at,
  i.started_at,
  i.completed_at,
  i.created_at
from
  quality.inspections i
  left join quality.standards s on s.id = i.standard_id
  left join supasheet.users u on u.id = i.inspector_user_id;

revoke all on quality.inspections_report
from
  authenticated,
  service_role;

grant
select
  on quality.inspections_report to "x-admin";

comment on view quality.inspections_report is '{"type": "report", "name": "Inspections Report", "description": "Inspections with pass rate and inspector"}';

create or replace view quality.ncr_report
with
  (security_invoker = true) as
select
  n.id,
  n.ncr_number,
  n.title,
  n.severity,
  n.status,
  n.disposition,
  n.product_sku,
  n.product_name,
  n.lot_number,
  n.quantity_affected,
  n.estimated_cost,
  n.currency,
  n.discovered_at,
  n.resolved_at,
  n.closed_at,
  case
    when n.status = 'closed' then null
    else extract(
      day
      from
        (current_timestamp - n.discovered_at)
    )::int
  end as days_open,
  a.name as assigned_to,
  i.inspection_number as source_inspection,
  n.created_at
from
  quality.non_conformances n
  left join quality.inspections i on i.id = n.inspection_id
  left join supasheet.users a on a.id = n.assigned_user_id;

revoke all on quality.ncr_report
from
  authenticated,
  service_role;

grant
select
  on quality.ncr_report to "x-admin";

comment on view quality.ncr_report is '{"type": "report", "name": "NCR Report", "description": "Non-conformance records with severity, status, and aging"}';

create or replace view quality.capa_report
with
  (security_invoker = true) as
select
  c.id,
  c.capa_number,
  c.title,
  c.type,
  c.status,
  c.priority,
  n.ncr_number as source_ncr,
  o.name as owner,
  v.name as verifier,
  c.opened_at,
  c.target_close_date,
  c.closed_at,
  case
    when c.status = 'closed' then 0
    when c.target_close_date is null then null
    else greatest(0, (current_date - c.target_close_date))::int
  end as days_overdue,
  c.effectiveness_score,
  c.cost,
  c.currency,
  c.created_at
from
  quality.capa c
  left join quality.non_conformances n on n.id = c.ncr_id
  left join supasheet.users o on o.id = c.owner_user_id
  left join supasheet.users v on v.id = c.verifier_user_id;

revoke all on quality.capa_report
from
  authenticated,
  service_role;

grant
select
  on quality.capa_report to "x-admin";

comment on view quality.capa_report is '{"type": "report", "name": "CAPA Report", "description": "Corrective and preventive actions with overdue tracking"}';

create or replace view quality.audit_findings_report
with
  (security_invoker = true) as
select
  f.id,
  f.finding_number,
  a.audit_number,
  a.title as audit_title,
  a.type as audit_type,
  f.clause,
  f.title,
  f.severity,
  f.status,
  o.name as owner,
  f.target_close_date,
  f.closed_at,
  case
    when f.status = 'closed' then 0
    when f.target_close_date is null then null
    else greatest(0, (current_date - f.target_close_date))::int
  end as days_overdue,
  c.capa_number as linked_capa,
  f.created_at
from
  quality.audit_findings f
  left join quality.audits a on a.id = f.audit_id
  left join quality.capa c on c.id = f.capa_id
  left join supasheet.users o on o.id = f.owner_user_id;

revoke all on quality.audit_findings_report
from
  authenticated,
  service_role;

grant
select
  on quality.audit_findings_report to "x-admin";

comment on view quality.audit_findings_report is '{"type": "report", "name": "Audit Findings Report", "description": "Audit findings with severity, owner, and linked CAPA"}';

create or replace view quality.certifications_register
with
  (security_invoker = true) as
select
  c.id,
  c.certificate_number,
  c.name,
  s.code as standard_code,
  s.name as standard_name,
  c.status,
  c.issuing_body,
  c.issued_date,
  c.expiry_date,
  case
    when c.expiry_date is null then null
    else (c.expiry_date - current_date)::int
  end as days_to_expiry,
  c.last_audit_date,
  c.next_audit_date,
  u.name as contact,
  c.created_at
from
  quality.certifications c
  left join quality.standards s on s.id = c.standard_id
  left join supasheet.users u on u.id = c.contact_user_id;

revoke all on quality.certifications_register
from
  authenticated,
  service_role;

grant
select
  on quality.certifications_register to "x-admin";

comment on view quality.certifications_register is '{"type": "report", "name": "Certifications Register", "description": "Certifications held with expiry countdown and contacts"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: open NCRs count
create or replace view quality.open_ncrs
with
  (security_invoker = true) as
select
  count(*) as value,
  'alert-octagon' as icon,
  'open NCRs' as label
from
  quality.non_conformances
where
  status in ('open', 'investigating', 'resolved');

revoke all on quality.open_ncrs
from
  authenticated,
  service_role;

grant
select
  on quality.open_ncrs to "x-admin";

-- card_2: pass vs fail (recent inspections)
create or replace view quality.pass_fail_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      result = 'passed'
  ) as primary,
  count(*) filter (
    where
      result = 'failed'
  ) as secondary,
  'Passed' as primary_label,
  'Failed' as secondary_label
from
  quality.inspections
where
  completed_at >= current_timestamp - interval '90 days';

revoke all on quality.pass_fail_split
from
  authenticated,
  service_role;

grant
select
  on quality.pass_fail_split to "x-admin";

-- card_3: open CAPA cost + closure rate
create or replace view quality.open_capa_value
with
  (security_invoker = true) as
select
  coalesce(
    sum(cost) filter (
      where
        status in ('open', 'in_progress', 'verification')
    ),
    0
  )::numeric(14, 2) as value,
  case
    when count(*) filter (
      where
        status in ('closed', 'cancelled')
    ) > 0 then round(
      (
        count(*) filter (
          where
            status = 'closed'
        )::numeric / count(*) filter (
          where
            status in ('closed', 'cancelled')
        )::numeric
      ) * 100,
      1
    )
    else 0
  end as percent
from
  quality.capa;

revoke all on quality.open_capa_value
from
  authenticated,
  service_role;

grant
select
  on quality.open_capa_value to "x-admin";

-- card_4: quality health (overdue CAPA + expiring certs + critical NCRs + overdue findings)
create or replace view quality.quality_health
with
  (security_invoker = true) as
with
  metrics as (
    select
      (
        select
          count(*)
        from
          quality.capa
        where
          status in ('open', 'in_progress', 'verification')
          and target_close_date is not null
          and target_close_date < current_date
      ) as overdue_capa,
      (
        select
          count(*)
        from
          quality.certifications
        where
          status in ('active', 'expiring_soon')
          and expiry_date is not null
          and expiry_date <= current_date + interval '60 days'
          and expiry_date >= current_date
      ) as expiring_certs,
      (
        select
          count(*)
        from
          quality.non_conformances
        where
          status in ('open', 'investigating')
          and severity = 'critical'
      ) as critical_open_ncrs,
      (
        select
          count(*)
        from
          quality.audit_findings
        where
          status in ('open', 'in_progress', 'resolved')
          and target_close_date is not null
          and target_close_date < current_date
      ) as overdue_findings,
      (
        select
          count(*)
        from
          quality.non_conformances
        where
          status in ('open', 'investigating')
      ) as total_open_ncrs
  )
select
  (
    overdue_capa + expiring_certs + critical_open_ncrs + overdue_findings
  ) as current,
  total_open_ncrs as total,
  json_build_array(
    json_build_object('label', 'Overdue CAPA', 'value', overdue_capa),
    json_build_object(
      'label',
      'Expiring certs',
      'value',
      expiring_certs
    ),
    json_build_object(
      'label',
      'Critical NCRs',
      'value',
      critical_open_ncrs
    ),
    json_build_object(
      'label',
      'Overdue findings',
      'value',
      overdue_findings
    )
  ) as segments
from
  metrics;

revoke all on quality.quality_health
from
  authenticated,
  service_role;

grant
select
  on quality.quality_health to "x-admin";

-- table_1: recent inspections
create or replace view quality.recent_inspections
with
  (security_invoker = true) as
select
  inspection_number as number,
  coalesce(title, '') as title,
  coalesce(result::text, '') as result,
  to_char(
    coalesce(completed_at, scheduled_at, created_at),
    'MM/DD'
  ) as date
from
  quality.inspections
order by
  coalesce(completed_at, scheduled_at, created_at) desc
limit
  10;

revoke all on quality.recent_inspections
from
  authenticated,
  service_role;

grant
select
  on quality.recent_inspections to "x-admin";

-- table_2: top defect reasons (root_cause from NCRs, last 90d)
create or replace view quality.top_defect_reasons
with
  (security_invoker = true) as
select
  coalesce(nullif(trim(root_cause), ''), 'Unspecified') as reason,
  coalesce(severity::text, '') as severity,
  count(*) as count,
  coalesce(sum(quantity_affected), 0)::bigint as units
from
  quality.non_conformances
where
  discovered_at >= current_timestamp - interval '90 days'
group by
  coalesce(nullif(trim(root_cause), ''), 'Unspecified'),
  severity
order by
  count desc
limit
  10;

revoke all on quality.top_defect_reasons
from
  authenticated,
  service_role;

grant
select
  on quality.top_defect_reasons to "x-admin";

comment on view quality.open_ncrs is '{"type": "dashboard_widget", "name": "Open NCRs", "description": "Count of non-conformances not yet closed", "widget_type": "card_1"}';

comment on view quality.pass_fail_split is '{"type": "dashboard_widget", "name": "Pass vs Fail (90d)", "description": "Recent inspection outcomes", "widget_type": "card_2"}';

comment on view quality.open_capa_value is '{"type": "dashboard_widget", "name": "Open CAPA", "description": "Open CAPA cost and closure rate", "widget_type": "card_3"}';

comment on view quality.quality_health is '{"type": "dashboard_widget", "name": "Quality Health", "description": "Overdue CAPA, certs, critical NCRs and findings", "widget_type": "card_4"}';

comment on view quality.recent_inspections is '{"type": "dashboard_widget", "name": "Recent Inspections", "description": "Latest 10 inspections", "widget_type": "table_1"}';

comment on view quality.top_defect_reasons is '{"type": "dashboard_widget", "name": "Top Defect Reasons", "description": "Top 10 root causes from recent NCRs", "widget_type": "table_2"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: inspections by result
create or replace view quality.inspections_by_result_pie
with
  (security_invoker = true) as
select
  result::text as label,
  count(*) as value
from
  quality.inspections
group by
  result
order by
  case result
    when 'pending' then 1
    when 'passed' then 2
    when 'conditional' then 3
    when 'failed' then 4
    when 'cancelled' then 5
  end;

revoke all on quality.inspections_by_result_pie
from
  authenticated,
  service_role;

grant
select
  on quality.inspections_by_result_pie to "x-admin";

-- Bar: NCRs by severity (open vs closed)
create or replace view quality.ncrs_by_severity_bar
with
  (security_invoker = true) as
select
  severity::text as label,
  count(*) filter (
    where
      status in ('open', 'investigating', 'resolved')
  )::bigint as open,
  count(*) filter (
    where
      status = 'closed'
  )::bigint as closed
from
  quality.non_conformances
group by
  severity
order by
  case severity
    when 'critical' then 1
    when 'major' then 2
    when 'minor' then 3
  end;

revoke all on quality.ncrs_by_severity_bar
from
  authenticated,
  service_role;

grant
select
  on quality.ncrs_by_severity_bar to "x-admin";

-- Line: weekly inspection trend (last 12 weeks)
create or replace view quality.inspection_trend_line
with
  (security_invoker = true) as
select
  to_char(
    date_trunc(
      'week',
      coalesce(completed_at, scheduled_at, created_at)
    ),
    'Mon DD'
  ) as date,
  count(*) filter (
    where
      result = 'passed'
  )::bigint as passed,
  count(*) filter (
    where
      result = 'failed'
  )::bigint as failed
from
  quality.inspections
where
  coalesce(completed_at, scheduled_at, created_at) >= current_date - interval '12 weeks'
group by
  date_trunc(
    'week',
    coalesce(completed_at, scheduled_at, created_at)
  )
order by
  date_trunc(
    'week',
    coalesce(completed_at, scheduled_at, created_at)
  );

revoke all on quality.inspection_trend_line
from
  authenticated,
  service_role;

grant
select
  on quality.inspection_trend_line to "x-admin";

-- Radar: audit findings by severity
create or replace view quality.audit_findings_radar
with
  (security_invoker = true) as
select
  severity::text as metric,
  count(*) as total,
  count(*) filter (
    where
      status in ('open', 'in_progress')
  )::bigint as open_count,
  count(*) filter (
    where
      status in ('resolved', 'verified', 'closed')
  )::bigint as resolved_count
from
  quality.audit_findings
group by
  severity
order by
  case severity
    when 'critical' then 1
    when 'major' then 2
    when 'minor' then 3
    when 'observation' then 4
  end;

revoke all on quality.audit_findings_radar
from
  authenticated,
  service_role;

grant
select
  on quality.audit_findings_radar to "x-admin";

comment on view quality.inspections_by_result_pie is '{"type": "chart", "name": "Inspections By Result", "description": "Inspection count grouped by result", "chart_type": "pie"}';

comment on view quality.ncrs_by_severity_bar is '{"type": "chart", "name": "NCRs By Severity", "description": "Open vs closed NCRs per severity", "chart_type": "bar"}';

comment on view quality.inspection_trend_line is '{"type": "chart", "name": "Inspection Trend", "description": "Weekly passed vs failed over 12 weeks", "chart_type": "line"}';

comment on view quality.audit_findings_radar is '{"type": "chart", "name": "Audit Findings", "description": "Findings count by severity with open vs resolved split", "chart_type": "radar"}';

----------------------------------------------------------------
-- Audit triggers
----------------------------------------------------------------
create trigger audit_qms_standards_insert
after insert on quality.standards for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_standards_update
after update on quality.standards for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_standards_delete
before delete on quality.standards for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_inspections_insert
after insert on quality.inspections for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_inspections_update
after update on quality.inspections for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_inspections_delete
before delete on quality.inspections for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_inspection_items_insert
after insert on quality.inspection_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_inspection_items_update
after update on quality.inspection_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_inspection_items_delete
before delete on quality.inspection_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_ncr_insert
after insert on quality.non_conformances for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_ncr_update
after update on quality.non_conformances for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_ncr_delete
before delete on quality.non_conformances for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_capa_insert
after insert on quality.capa for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_capa_update
after update on quality.capa for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_capa_delete
before delete on quality.capa for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_audits_insert
after insert on quality.audits for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_audits_update
after update on quality.audits for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_audits_delete
before delete on quality.audits for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_audit_findings_insert
after insert on quality.audit_findings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_audit_findings_update
after update on quality.audit_findings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_audit_findings_delete
before delete on quality.audit_findings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_certifications_insert
after insert on quality.certifications for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_certifications_update
after update on quality.certifications for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_certifications_delete
before delete on quality.certifications for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_complaints_insert
after insert on quality.complaints for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_complaints_update
after update on quality.complaints for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_qms_complaints_delete
before delete on quality.complaints for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
-- Non-conformances: notify QA on opened (esp. critical) and on closure
create or replace function quality.trg_ncr_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if tg_op = 'INSERT' then
        v_type  := 'quality_ncr_opened';
        v_title := case when new.severity = 'critical' then 'Critical NCR opened' else 'New NCR opened' end;
        v_body  := 'NCR ' || new.ncr_number || ' (' || new.severity::text ||
                   ') opened on ' || coalesce(new.product_name, 'product') || '.';
    elsif new.status is distinct from old.status and new.status in ('resolved', 'closed', 'cancelled') then
        v_type  := 'quality_ncr_' || new.status::text;
        v_title := 'NCR ' || new.status::text;
        v_body  := 'NCR ' || new.ncr_number || ' is now ' || new.status::text || '.';
    else
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('quality', 'non_conformances', 'update')
            || array[new.user_id, new.assigned_user_id],
        null
    );

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'ncr_id',            new.id,
            'severity',          new.severity,
            'status',            new.status,
            'product_sku',       new.product_sku,
            'quantity_affected', new.quantity_affected
        ),
        '/quality/resource/non_conformances/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists ncr_notify on quality.non_conformances;

create trigger ncr_notify
after insert or update of status on quality.non_conformances for each row
execute function quality.trg_ncr_notify ();

-- CAPA: notify owner on creation and on status changes
create or replace function quality.trg_capa_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if tg_op = 'INSERT' then
        v_type  := 'quality_capa_opened';
        v_title := 'New CAPA opened';
        v_body  := 'CAPA ' || new.capa_number || ' (' || new.type::text ||
                   ', ' || new.priority::text || ') opened.';
    elsif new.status is distinct from old.status and new.status in ('in_progress', 'verification', 'closed', 'cancelled') then
        v_type  := 'quality_capa_' || new.status::text;
        v_title := 'CAPA ' || new.status::text;
        v_body  := 'CAPA ' || new.capa_number || ' is now ' || new.status::text || '.';
    else
        return new;
    end if;

    v_recipients := array_remove(
        array[new.owner_user_id, new.verifier_user_id, new.user_id],
        null
    );

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'capa_id',          new.id,
            'type',             new.type,
            'status',           new.status,
            'priority',         new.priority,
            'target_close_date', new.target_close_date,
            'ncr_id',           new.ncr_id
        ),
        '/quality/resource/capa/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists capa_notify on quality.capa;

create trigger capa_notify
after insert or update of status on quality.capa for each row
execute function quality.trg_capa_notify ();

-- Certifications: notify QA team on expiring/expired transitions
create or replace function quality.trg_certifications_notify () returns trigger as $$
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
    if new.status not in ('expiring_soon', 'expired', 'suspended', 'active') then
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('quality', 'certifications', 'update')
            || array[new.user_id, new.contact_user_id],
        null
    );

    v_type  := 'quality_cert_' || new.status::text;
    v_title := 'Certification ' || new.status::text;
    v_body  := 'Certification "' || new.name || '" (' || new.certificate_number || ') is now ' || new.status::text ||
               coalesce('. Expiry: ' || to_char(new.expiry_date, 'YYYY-MM-DD'), '') || '.';

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'certification_id',   new.id,
            'standard_id',        new.standard_id,
            'status',             new.status,
            'expiry_date',        new.expiry_date,
            'next_audit_date',    new.next_audit_date
        ),
        '/quality/resource/certifications/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists certifications_notify on quality.certifications;

create trigger certifications_notify
after update of status on quality.certifications for each row
execute function quality.trg_certifications_notify ();
