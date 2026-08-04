-- ================================================================
-- Supasheet Example — "Procurement" (source-to-pay)
-- ================================================================
-- A production-shaped procurement back office: spend categories and
-- departmental budgets, a supplier master with compliance documents,
-- requisitions that route through a sequential approval chain, RFQs
-- and supplier quotes, blanket/framework contracts, purchase orders,
-- goods receipts, and vendor invoices reconciled by three-way match.
--
-- Demo data lives in supabase/examples/p_seed.sql — apply this file
-- first, then that one.
--
-- This is not the inventory module's purchase-order flow with
-- different words on it. That one asks "what do we have and where
-- did it come from?" — receiving is its whole concern, and its
-- purchase order exists to get stock into a bin. This one asks "who
-- authorised spending this money, against what agreement, and does
-- what we were billed match what we ordered and what actually
-- turned up?" — sourcing, approval and financial reconciliation are
-- the whole concern here, and nothing in this schema knows what a
-- warehouse bin is.
--
-- The rules that make it a procurement system rather than a set of
-- lists:
--
--   - SEQUENTIAL APPROVAL. A requisition or purchase order clears
--     its approval steps IN ORDER. Step 2 cannot be decided before
--     step 1 has approved it, nobody approves their own request, and
--     a single rejection anywhere in the chain kills the document and
--     skips whatever steps were still pending.
--   - THREE-WAY MATCH. A vendor invoice is reconciled against the
--     purchase order it bills and the goods receipts posted against
--     that order. A quantity or price variance outside tolerance
--     forces the invoice to `discrepancy` and REFUSES approval —
--     that is not a checkbox a clerk ticks, it is a trigger that
--     will not let the status move.
--   - CONTRACT CEILING. A purchase order raised against a blanket or
--     framework contract cannot push that contract's cumulative
--     committed spend past its ceiling. The trigger sums every other
--     order against the same contract before it lets a new one in.
--   - NO ORDERING BLOCKED SUPPLIERS. A purchase order cannot be
--     raised against a supplier who is on hold or blacklisted, full
--     stop, regardless of who is placing it.
--   - RECEIPT CANNOT EXCEED ORDER. A goods receipt line is refused
--     the moment it would accept more than the quantity still
--     outstanding on its order line. Over-delivery gets logged
--     against the order, never quietly absorbed.
--
-- Everything the other modules cover is here too:
--   - Native-role RBAC with two custom roles ("buyer" runs sourcing
--     and ordering, "approver" is a budget owner who can only decide
--     approval steps) alongside "x-admin"/"user"
--   - Column-level grants: the "user" role (the requester) sees a
--     supplier's name and terms but never its bank details or spend
--     history
--   - All six view layouts, every widget and chart contract, reports
--     with a Handlebars print template, a materialized spend rollup,
--     both a static and a live-data template, custom form shapes, row
--     actions, notifications, audit logging, per-resource comments
--     and a private `procurement-documents` storage bucket for
--     contracts, compliance certificates and invoices
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260807000000_procurement.sql \
--     -f supabase/examples/p_seed.sql
--
-- Requires the base Supasheet migrations. Add "procurement" to
-- config.toml's `api.schemas` and `api.extra_search_path`, then
-- restart Supabase.
--
-- Not idempotent: re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists procurement;

-------------------------------------------------------------------
-- Roles
--
--   x-admin    procurement director: everything, including deleting
--              suppliers/contracts and overriding a blocked
--              three-way match
--   buyer      day-to-day procurement: owns suppliers, categories,
--              sourcing (RFQs/quotes), contracts, purchase orders,
--              goods receipts and invoice matching. Cannot decide an
--              approval step and cannot delete a supplier or contract
--   approver   a budget/department owner: sees what is asked of them
--              and can only act on the approvals table — deciding
--              their own step of a requisition's or order's chain.
--              Cannot create or edit the documents themselves
--   user       THE REQUESTER: raises requisitions and sees their own,
--              plus a read-only, financially-redacted supplier
--              directory
--
-- Assign a user to a custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "buyer"}'
--   where email = 'procurement@example.com';
-------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'user') then
    create role "user" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'admin') then
    create role "admin" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'buyer') then
    create role "buyer" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'approver') then
    create role "approver" nologin;
  end if;
end;
$$;

grant "user",
"admin",
"buyer",
"approver" to authenticator;

grant authenticated to "user",
"admin",
"buyer",
"approver";

grant usage on schema procurement to "x-admin",
"buyer",
"approver",
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
create type procurement.requisition_status as enum(
  'draft',
  'submitted',
  'pending_approval',
  'approved',
  'rejected',
  'converted',
  'cancelled'
);

create type procurement.approval_status as enum(
  'pending',
  'approved',
  'rejected',
  'skipped'
);

create type procurement.priority_level as enum('low', 'normal', 'high', 'urgent');

create type procurement.supplier_status as enum(
  'prospective',
  'active',
  'on_hold',
  'blacklisted',
  'inactive'
);

create type procurement.supplier_risk as enum('low', 'medium', 'high', 'critical');

create type procurement.document_type as enum(
  'insurance',
  'w9_tax_form',
  'tax_certificate',
  'nda',
  'quality_certification',
  'business_license',
  'other'
);

create type procurement.rfq_status as enum(
  'draft',
  'sent',
  'closed',
  'awarded',
  'cancelled'
);

create type procurement.quote_status as enum(
  'invited',
  'submitted',
  'shortlisted',
  'awarded',
  'rejected',
  'expired'
);

create type procurement.contract_type as enum('blanket', 'framework', 'spot', 'service');

create type procurement.contract_status as enum(
  'draft',
  'active',
  'expired',
  'terminated',
  'renewed'
);

create type procurement.po_status as enum(
  'draft',
  'pending_approval',
  'approved',
  'sent',
  'acknowledged',
  'partially_received',
  'received',
  'invoiced',
  'closed',
  'cancelled'
);

create type procurement.receipt_status as enum('draft', 'posted', 'disputed');

create type procurement.receipt_line_condition as enum(
  'accepted',
  'damaged',
  'rejected',
  'short',
  'over'
);

create type procurement.invoice_status as enum(
  'draft',
  'pending_match',
  'matched',
  'discrepancy',
  'approved',
  'disputed',
  'paid',
  'void'
);

create type procurement.match_status as enum(
  'not_matched',
  'matched',
  'over_tolerance',
  'under_tolerance'
);

create type procurement.payment_method as enum(
  'bank_transfer',
  'card',
  'cheque',
  'cash',
  'other'
);

create type procurement.savings_type as enum('hard_savings', 'cost_avoidance', 'rebate');

create type procurement.po_event_type as enum(
  'created',
  'submitted',
  'approved',
  'rejected',
  'sent',
  'acknowledged',
  'received',
  'invoiced',
  'closed',
  'cancelled'
);

----------------------------------------------------------------
-- Users replica view
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
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on procurement.users to "x-admin",
  "buyer",
  "approver",
  "user";

comment on view procurement.users is '{"display": "none"}';

----------------------------------------------------------------
-- Role helpers
----------------------------------------------------------------
create or replace function procurement.is_procurement_staff () returns boolean language sql stable
set
  search_path = '' as $$
  select pg_has_role(current_user, 'x-admin', 'member')
      or pg_has_role(current_user, 'buyer', 'member');
$$;

revoke all on function procurement.is_procurement_staff ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function procurement.is_procurement_staff () to "x-admin",
"buyer",
"approver",
"user";

----------------------------------------------------------------
-- Departments
--
-- Who spends the money and against what budget. Committed spend is
-- everything on an open requisition or order; actual spend is what
-- has actually been received or invoiced. Both are rollups — nobody
-- types them.
----------------------------------------------------------------
create table procurement.departments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(160) not null,
  description varchar(300),
  budget_owner_id uuid references supasheet.users (id) on delete set null,
  cost_center_code varchar(20),
  annual_budget numeric(14, 2) not null default 0,
  committed_spend numeric(14, 2) not null default 0,
  actual_spend numeric(14, 2) not null default 0,
  is_active boolean not null default true,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint departments_budget_non_negative check (annual_budget >= 0)
);

comment on table procurement.departments is '{
    "icon": "Building2",
    "name": "Departments",
    "description": "Who spends the money, and how much of the annual budget is already spoken for.",
    "collapsible_group": "Governance",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["code", "is_active"]},
        "tabs": ["purchase_requisitions", "purchase_orders"]
    },
    "views": [
        {"id": "list", "name": "All Departments", "type": "list", "title": "name", "description": "code", "field_1": "annual_budget", "field_2": "committed_spend"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "is_active", "title": "name", "description": "code", "date": "created_at", "badge": "actual_spend"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "overcommitted", "name": "Over Budget", "filters": [{"id": "committed_spend", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "annual_budget"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "color", "is_active"]},
            {"id": "ownership", "title": "Ownership", "fields": ["budget_owner_id", "cost_center_code"]},
            {"id": "budget", "title": "Budget", "fields": ["annual_budget"]},
            {"id": "position", "title": "Position", "fields": {"read": ["committed_spend", "actual_spend"]}}
        ],
        "metadata": {
            "committed_spend": {"description": "Estimated value of every open requisition plus every order not yet closed or cancelled."},
            "actual_spend": {"description": "What has actually been received or invoiced against this department, regardless of order status."}
        }
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [{"table": "users", "on": "budget_owner_id", "alias": "owner", "columns": ["name", "email"]}]
    }
}';

comment on column procurement.departments.annual_budget is '{"name": "Budget", "aggregate": "sum"}';

comment on column procurement.departments.committed_spend is '{"name": "Committed", "aggregate": "sum"}';

comment on column procurement.departments.actual_spend is '{"name": "Actual", "aggregate": "sum"}';

revoke all on table procurement.departments
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
delete on table procurement.departments to "x-admin";

grant
select
  on table procurement.departments to "buyer",
  "approver",
  "user";

create index idx_proc_departments_active on procurement.departments (is_active);

alter table procurement.departments enable row level security;

create policy departments_select on procurement.departments for
select
  to authenticated using (true);

create policy departments_insert on procurement.departments for insert to authenticated
with
  check (true);

create policy departments_update on procurement.departments
for update
  to authenticated using (true)
with
  check (true);

create policy departments_delete on procurement.departments for delete to authenticated using (true);

----------------------------------------------------------------
-- Spend categories (self-referencing tree)
----------------------------------------------------------------
create table procurement.categories (
  id uuid primary key default extensions.uuid_generate_v4 (),
  parent_id uuid references procurement.categories (id) on delete set null,
  code varchar(20) not null unique,
  name varchar(160) not null,
  description varchar(300),
  default_approval_threshold numeric(14, 2) not null default 1000,
  is_active boolean not null default true,
  spend_total numeric(14, 2) not null default 0,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint categories_not_own_parent check (id <> parent_id),
  constraint categories_threshold_non_negative check (default_approval_threshold >= 0)
);

comment on table procurement.categories is '{
    "icon": "Tags",
    "name": "Spend Categories",
    "description": "What the money is being spent on, arranged as a tree. The default approval threshold routes new requisitions raised in this category.",
    "collapsible_group": "Governance",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["code", "is_active"]},
        "tabs": ["suppliers", "purchase_requisitions", "purchase_orders", "contracts"]
    },
    "views": [
        {"id": "tree", "name": "Category Tree", "type": "tree", "parent": "parent_id", "title": "name", "secondary": "code"},
        {"id": "list", "name": "All Categories", "type": "list", "title": "name", "description": "description", "field_1": "code", "field_2": "spend_total"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "parent_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "parent_id", "color", "is_active"]},
            {"id": "routing", "title": "Approval Routing", "fields": ["default_approval_threshold"]},
            {"id": "position", "title": "Position", "fields": {"read": ["spend_total"]}}
        ],
        "metadata": {
            "default_approval_threshold": {"description": "Requisitions raised in this category above this amount require a second approval step."}
        }
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "categories", "on": "parent_id", "alias": "parent", "columns": ["name", "code"]}]
    }
}';

comment on column procurement.categories.spend_total is '{"name": "Spend", "aggregate": "sum"}';

revoke all on table procurement.categories
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
delete on table procurement.categories to "x-admin";

grant
select
,
  insert,
update on table procurement.categories to "buyer";

grant
select
  on table procurement.categories to "approver",
  "user";

create index idx_proc_categories_parent_id on procurement.categories (parent_id);

alter table procurement.categories enable row level security;

create policy categories_select on procurement.categories for
select
  to authenticated using (true);

create policy categories_insert on procurement.categories for insert to authenticated
with
  check (true);

create policy categories_update on procurement.categories
for update
  to authenticated using (true)
with
  check (true);

create policy categories_delete on procurement.categories for delete to authenticated using (true);

----------------------------------------------------------------
-- Suppliers
--
-- The vendor master. Financial terms and performance history are
-- hidden from the requester ("user") at the column level below —
-- raising a requisition against a preferred supplier does not
-- require knowing what we pay them or how they have scored.
----------------------------------------------------------------
create table procurement.suppliers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(200) not null,
  legal_name varchar(200),
  category_id uuid references procurement.categories (id) on delete set null,
  status procurement.supplier_status not null default 'prospective',
  risk_rating procurement.supplier_risk not null default 'medium',
  is_preferred boolean not null default false,
  tax_number varchar(60),
  duns_number varchar(20),
  email supasheet.EMAIL,
  phone supasheet.TEL,
  website supasheet.URL,
  address text,
  country varchar(120),
  currency varchar(3) not null default 'USD',
  payment_terms_days integer not null default 30,
  incoterms varchar(20),
  bank_details varchar(200),
  onboarded_on date,
  logo supasheet.AVATAR,
  on_time_delivery_rate supasheet.PERCENTAGE,
  quality_score supasheet.RATING,
  responsiveness_score supasheet.RATING,
  overall_rating supasheet.RATING,
  total_spend numeric(16, 2) not null default 0,
  open_po_value numeric(16, 2) not null default 0,
  open_contract_value numeric(16, 2) not null default 0,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint suppliers_terms_non_negative check (payment_terms_days >= 0)
);

comment on column procurement.suppliers.status is '{
    "progress": true,
    "values": {
        "prospective": {"variant": "secondary", "icon": "CircleDashed"},
        "active": {"variant": "success", "icon": "CircleCheck"},
        "on_hold": {"variant": "warning", "icon": "PauseCircle"},
        "blacklisted": {"variant": "destructive", "icon": "Ban"},
        "inactive": {"variant": "secondary", "icon": "Archive"}
    }
}';

comment on column procurement.suppliers.risk_rating is '{
    "progress": false,
    "values": {
        "low": {"variant": "success", "icon": "ShieldCheck"},
        "medium": {"variant": "info", "icon": "Shield"},
        "high": {"variant": "warning", "icon": "ShieldAlert"},
        "critical": {"variant": "destructive", "icon": "ShieldX"}
    }
}';

comment on table procurement.suppliers is '{
    "icon": "Truck",
    "name": "Suppliers",
    "description": "Who we buy from, how much we owe them by way of trust, and how they have performed.",
    "collapsible_group": "Sourcing",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "name", "badges": ["status", "risk_rating", "is_preferred"]},
        "tabs": ["supplier_contacts", "supplier_documents", "rfq_suppliers", "supplier_quotes", "contracts", "purchase_orders", "vendor_invoices", "supplier_performance_reviews"]
    },
    "views": [
        {"id": "gallery", "name": "Directory", "type": "gallery", "cover": "logo", "title": "name", "description": "country", "badge": "status"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "name", "description": "code", "date": "onboarded_on", "badge": "risk_rating"},
        {"id": "list", "name": "All Suppliers", "type": "list", "title": "name", "description": "code", "field_1": "overall_rating", "field_2": "total_spend"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "preferred", "name": "Preferred", "filters": [{"id": "is_preferred", "value": "true", "operator": "eq"}]},
        {"id": "blocked", "name": "Blocked", "filters": [{"id": "status", "value": ["on_hold", "blacklisted"], "operator": "in"}]},
        {"id": "high_risk", "name": "High Risk", "filters": [{"id": "risk_rating", "value": ["high", "critical"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "category_id", "email"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": {"create": ["code", "name", "legal_name", "category_id", "tax_number", "duns_number"], "update": ["name", "legal_name", "category_id", "tax_number", "duns_number", "status", "risk_rating", "is_preferred", "logo"], "read": ["code", "name", "legal_name", "category_id", "tax_number", "duns_number", "status", "risk_rating", "is_preferred", "logo"]}},
            {"id": "contact", "title": "Contact", "fields": ["email", "phone", "website", "address", "country"]},
            {"id": "terms", "title": "Commercial Terms", "fields": ["currency", "payment_terms_days", "incoterms", "bank_details", "onboarded_on"]},
            {"id": "performance", "title": "Performance", "fields": {"read": ["on_time_delivery_rate", "quality_score", "responsiveness_score", "overall_rating"]}},
            {"id": "position", "title": "Position", "fields": {"read": ["total_spend", "open_po_value", "open_contract_value"]}},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [{"table": "categories", "on": "category_id", "columns": ["code", "name"]}]
    }
}';

comment on column procurement.suppliers.logo is '{"accept": "image/*", "maxSize": 1048576}';

comment on column procurement.suppliers.overall_rating is '{"name": "Overall Rating"}';

comment on column procurement.suppliers.total_spend is '{"name": "Total Spend", "aggregate": "sum"}';

comment on column procurement.suppliers.open_po_value is '{"name": "Open Orders", "aggregate": "sum"}';

revoke all on table procurement.suppliers
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
delete on table procurement.suppliers to "x-admin";

grant
select
,
  insert,
update on table procurement.suppliers to "buyer";

grant
select
  on table procurement.suppliers to "approver";

-- The requester sees who a supplier is, not what we pay them or how
-- they have scored — a purely financial view is a buyer's job.
grant
select
  (
    id,
    code,
    name,
    legal_name,
    category_id,
    status,
    is_preferred,
    email,
    phone,
    website,
    address,
    country,
    logo,
    created_at,
    updated_at
  ) on table procurement.suppliers to "user";

create unique index idx_proc_suppliers_name on procurement.suppliers (lower(name));

create index idx_proc_suppliers_status on procurement.suppliers (status);

create index idx_proc_suppliers_category_id on procurement.suppliers (category_id);

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
-- Supplier contacts
----------------------------------------------------------------
create table procurement.supplier_contacts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  supplier_id uuid not null references procurement.suppliers (id) on delete cascade,
  name varchar(160) not null,
  title varchar(120),
  email supasheet.EMAIL,
  phone supasheet.TEL,
  is_primary boolean not null default false,
  notes varchar(300),
  created_at timestamptz default current_timestamp
);

comment on table procurement.supplier_contacts is '{
    "icon": "Contact",
    "name": "Contacts",
    "description": "Who to call at each supplier.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "contact", "title": "Contact", "fields": ["supplier_id", "name", "title", "is_primary"]},
            {"id": "reach", "title": "Reach", "fields": ["email", "phone", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "is_primary", "desc": true}],
        "join": [{"table": "suppliers", "on": "supplier_id", "columns": ["code", "name"]}]
    }
}';

revoke all on table procurement.supplier_contacts
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
delete on table procurement.supplier_contacts to "x-admin",
"buyer";

grant
select
  on table procurement.supplier_contacts to "approver";

create index idx_proc_supplier_contacts_supplier_id on procurement.supplier_contacts (supplier_id);

create unique index idx_proc_supplier_contacts_one_primary on procurement.supplier_contacts (supplier_id)
where
  is_primary;

alter table procurement.supplier_contacts enable row level security;

create policy supplier_contacts_select on procurement.supplier_contacts for
select
  to authenticated using (true);

create policy supplier_contacts_insert on procurement.supplier_contacts for insert to authenticated
with
  check (true);

create policy supplier_contacts_update on procurement.supplier_contacts
for update
  to authenticated using (true)
with
  check (true);

create policy supplier_contacts_delete on procurement.supplier_contacts for delete to authenticated using (true);

----------------------------------------------------------------
-- Supplier compliance documents
--
-- Insurance certificates, tax forms, quality certifications — each
-- with an expiry. is_expired is recomputed by trigger, not typed,
-- because "is this still valid" cannot be left to whoever last
-- edited the row.
----------------------------------------------------------------
create table procurement.supplier_documents (
  id uuid primary key default extensions.uuid_generate_v4 (),
  supplier_id uuid not null references procurement.suppliers (id) on delete cascade,
  document_type procurement.document_type not null default 'other',
  name varchar(200) not null,
  file supasheet.file,
  issued_on date,
  expires_on date,
  is_required boolean not null default false,
  is_verified boolean not null default false,
  verified_by uuid references supasheet.users (id) on delete set null,
  is_expired boolean not null default false,
  notes varchar(300),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint supplier_documents_window check (
    expires_on is null
    or issued_on is null
    or expires_on >= issued_on
  )
);

comment on column procurement.supplier_documents.document_type is '{
    "progress": false,
    "values": {
        "insurance": {"variant": "info", "icon": "ShieldCheck"},
        "w9_tax_form": {"variant": "secondary", "icon": "FileText"},
        "tax_certificate": {"variant": "secondary", "icon": "Receipt"},
        "nda": {"variant": "warning", "icon": "FileLock"},
        "quality_certification": {"variant": "success", "icon": "BadgeCheck"},
        "business_license": {"variant": "default", "icon": "FileCheck"},
        "other": {"variant": "secondary", "icon": "File"}
    }
}';

comment on table procurement.supplier_documents is '{
    "icon": "FileCheck",
    "name": "Compliance Documents",
    "description": "Insurance, tax and quality paperwork on file for each supplier, and whether it has lapsed.",
    "collapsible_group": "Sourcing",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "name", "badges": ["document_type", "is_expired", "is_verified"]}},
    "views": [
        {"id": "list", "name": "All Documents", "type": "list", "title": "name", "description": "document_type", "field_1": "expires_on", "field_2": "is_expired"},
        {"id": "calendar", "name": "Expiry Calendar", "type": "calendar", "title": "name", "badge": "document_type", "start_date": "expires_on", "read_only": true}
    ],
    "filter_presets": [
        {"id": "expired", "name": "Expired", "filters": [{"id": "is_expired", "value": "true", "operator": "eq"}]},
        {"id": "unverified", "name": "Unverified", "filters": [{"id": "is_verified", "value": "false", "operator": "eq"}]},
        {"id": "required", "name": "Required", "filters": [{"id": "is_required", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["supplier_id", "document_type", "name", "file"],
        "sections": [
            {"id": "document", "title": "Document", "fields": ["supplier_id", "document_type", "name", "file", "is_required"]},
            {"id": "validity", "title": "Validity", "fields": ["issued_on", "expires_on"]},
            {"id": "verification", "title": "Verification", "fields": {"create": ["notes"], "update": ["is_verified", "notes"], "read": ["is_verified", "verified_by", "notes"]}},
            {"id": "derived", "title": "Status", "fields": {"read": ["is_expired"]}}
        ]
    },
    "query": {
        "sort": [{"id": "expires_on", "desc": false}],
        "join": [
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name", "status"]},
            {"table": "users", "on": "verified_by", "alias": "verifier", "columns": ["name", "email"]}
        ]
    }
}';

comment on column procurement.supplier_documents.file is '{"accept": ".pdf,.png,.jpg", "maxFiles": 3, "maxSize": 10485760}';

revoke all on table procurement.supplier_documents
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
delete on table procurement.supplier_documents to "x-admin",
"buyer";

grant
select
  on table procurement.supplier_documents to "approver";

create index idx_proc_supplier_documents_supplier_id on procurement.supplier_documents (supplier_id);

create index idx_proc_supplier_documents_expires_on on procurement.supplier_documents (expires_on);

alter table procurement.supplier_documents enable row level security;

create policy supplier_documents_select on procurement.supplier_documents for
select
  to authenticated using (true);

create policy supplier_documents_insert on procurement.supplier_documents for insert to authenticated
with
  check (true);

create policy supplier_documents_update on procurement.supplier_documents
for update
  to authenticated using (true)
with
  check (true);

create policy supplier_documents_delete on procurement.supplier_documents for delete to authenticated using (true);

create or replace function procurement.supplier_documents_set_expired () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  new.is_expired := (new.expires_on is not null and new.expires_on < current_date);
  return new;
end;
$$;

create trigger trg_supplier_documents_set_expired before insert
or
update on procurement.supplier_documents for each row
execute function procurement.supplier_documents_set_expired ();

----------------------------------------------------------------
-- Purchase requisitions
--
-- Internal demand. A requisition is only ever converted to a
-- purchase order once its approval chain (below) has cleared every
-- step — the "Convert to PO" form (see forms section) enforces that
-- at the point of use, and the status itself cannot reach 'approved'
-- any other way than the chain closing out.
----------------------------------------------------------------
create sequence if not exists procurement.requisition_number_seq;

create table procurement.purchase_requisitions (
  id uuid primary key default extensions.uuid_generate_v4 (),
  requisition_number varchar(30) not null unique default (
    'REQ-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('procurement.requisition_number_seq')::text,
      6,
      '0'
    )
  ),
  department_id uuid not null references procurement.departments (id) on delete restrict,
  category_id uuid references procurement.categories (id) on delete set null,
  requester_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  status procurement.requisition_status not null default 'draft',
  priority procurement.priority_level not null default 'normal',
  needed_by date,
  justification supasheet.RICH_TEXT,
  estimated_total numeric(14, 2) not null default 0,
  line_count integer not null default 0,
  current_approval_step integer not null default 0,
  total_approval_steps integer not null default 0,
  submitted_at timestamptz,
  approved_at timestamptz,
  rejected_reason varchar(300),
  attachments supasheet.file,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint requisitions_total_non_negative check (estimated_total >= 0)
);

comment on column procurement.purchase_requisitions.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "submitted": {"variant": "info", "icon": "Send"},
        "pending_approval": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "converted": {"variant": "success", "icon": "ArrowRightCircle"},
        "cancelled": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on column procurement.purchase_requisitions.priority is '{
    "progress": false,
    "values": {
        "low": {"variant": "secondary", "icon": "ArrowDown"},
        "normal": {"variant": "info", "icon": "Minus"},
        "high": {"variant": "warning", "icon": "ArrowUp"},
        "urgent": {"variant": "destructive", "icon": "TriangleAlert"}
    }
}';

comment on table procurement.purchase_requisitions is '{
    "icon": "ClipboardList",
    "name": "Requisitions",
    "description": "Internal demand, before it becomes an order. Nothing here commits to spending anything until it is approved.",
    "collapsible_group": "Requisitioning",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "requisition_number", "badges": ["status", "priority", "estimated_total"]},
        "tabs": ["requisition_lines", "requisition_approvals", "purchase_orders"]
    },
    "views": [
        {"id": "kanban", "name": "Approval Board", "type": "kanban", "group": "status", "title": "requisition_number", "description": "justification", "date": "needed_by", "badge": "priority"},
        {"id": "calendar", "name": "Needed By", "type": "calendar", "title": "requisition_number", "badge": "status", "start_date": "needed_by", "read_only": true},
        {"id": "list", "name": "All Requisitions", "type": "list", "title": "requisition_number", "description": "justification", "field_1": "status", "field_2": "estimated_total"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "My Requisitions", "filters": [{"id": "requester_id", "value": "me", "operator": "eq"}]},
        {"id": "pending", "name": "Awaiting Approval", "filters": [{"id": "status", "value": "pending_approval", "operator": "eq"}]},
        {"id": "urgent", "name": "Urgent", "filters": [{"id": "priority", "value": "urgent", "operator": "eq"}]},
        {"id": "approved", "name": "Ready To Convert", "filters": [{"id": "status", "value": "approved", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["department_id", "category_id", "needed_by", "priority"],
        "sections": [
            {"id": "request", "title": "Request", "fields": {"create": ["department_id", "category_id", "needed_by", "priority", "justification"], "update": ["needed_by", "priority", "justification"], "read": ["department_id", "category_id", "requester_id", "needed_by", "priority", "justification"]}},
            {"id": "state", "title": "State", "fields": {"read": ["status", "rejected_reason", "submitted_at", "approved_at"]}},
            {"id": "totals", "title": "Totals", "fields": {"read": ["line_count", "estimated_total", "current_approval_step", "total_approval_steps"]}},
            {"id": "extras", "title": "Attachments", "collapsible": true, "fields": ["attachments"]}
        ],
        "behavior": {
            "rejected_reason": {"visible": [{"id": "status", "operator": "eq", "value": "rejected"}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "departments", "on": "department_id", "columns": ["code", "name"]},
            {"table": "categories", "on": "category_id", "columns": ["code", "name"]},
            {"table": "users", "on": "requester_id", "alias": "requester", "columns": ["name", "email"]}
        ]
    }
}';

comment on column procurement.purchase_requisitions.estimated_total is '{"aggregate": "sum"}';

comment on column procurement.purchase_requisitions.attachments is '{"accept": "*", "maxFiles": 5, "maxSize": 10485760}';

revoke all on table procurement.purchase_requisitions
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
delete on table procurement.purchase_requisitions to "x-admin";

grant
select
,
update on table procurement.purchase_requisitions to "buyer";

grant
select
  on table procurement.purchase_requisitions to "approver";

grant
select
,
  insert,
update on table procurement.purchase_requisitions to "user";

revoke all on sequence procurement.requisition_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence procurement.requisition_number_seq to "x-admin",
"user";

create index idx_proc_requisitions_department_id on procurement.purchase_requisitions (department_id);

create index idx_proc_requisitions_status on procurement.purchase_requisitions (status);

create index idx_proc_requisitions_requester_id on procurement.purchase_requisitions (requester_id);

alter table procurement.purchase_requisitions enable row level security;

create policy requisitions_select on procurement.purchase_requisitions for
select
  to authenticated using (
    requester_id = (select auth.uid ())
    or pg_has_role (current_user, 'buyer', 'member')
    or pg_has_role (current_user, 'approver', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  );

create policy requisitions_insert on procurement.purchase_requisitions for insert to authenticated
with
  check (true);

create policy requisitions_update on procurement.purchase_requisitions
for update
  to authenticated using (
    requester_id = (select auth.uid ())
    or pg_has_role (current_user, 'buyer', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy requisitions_delete on procurement.purchase_requisitions for delete to authenticated using (true);

----------------------------------------------------------------
-- Requisition lines
----------------------------------------------------------------
create table procurement.requisition_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  requisition_id uuid not null references procurement.purchase_requisitions (id) on delete cascade,
  category_id uuid references procurement.categories (id) on delete set null,
  suggested_supplier_id uuid references procurement.suppliers (id) on delete set null,
  line_number integer,
  description varchar(300) not null,
  quantity numeric(12, 3) not null default 1,
  uom varchar(20) not null default 'EA',
  estimated_unit_price numeric(14, 4) not null default 0,
  estimated_total numeric(14, 2) not null default 0,
  needed_by date,
  notes varchar(300),
  created_at timestamptz default current_timestamp,
  constraint requisition_lines_quantity_positive check (quantity > 0),
  constraint requisition_lines_price_non_negative check (estimated_unit_price >= 0)
);

comment on table procurement.requisition_lines is '{
    "icon": "Rows3",
    "name": "Requisition Lines",
    "description": "What is being asked for, and roughly what it will cost.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "item", "title": "Item", "fields": ["requisition_id", "line_number", "description", "category_id"]},
            {"id": "quantity", "title": "Quantity & Price", "fields": ["quantity", "uom", "estimated_unit_price"]},
            {"id": "sourcing", "title": "Sourcing", "fields": ["suggested_supplier_id", "needed_by", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "purchase_requisitions", "on": "requisition_id", "columns": ["requisition_number", "status"]},
            {"table": "categories", "on": "category_id", "columns": ["code", "name"]},
            {"table": "suppliers", "on": "suggested_supplier_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column procurement.requisition_lines.estimated_total is '{"name": "Est. Total", "aggregate": "sum"}';

revoke all on table procurement.requisition_lines
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
delete on table procurement.requisition_lines to "x-admin",
"user";

grant
select
,
update on table procurement.requisition_lines to "buyer";

grant
select
  on table procurement.requisition_lines to "approver";

create index idx_proc_requisition_lines_requisition_id on procurement.requisition_lines (requisition_id);

create index idx_proc_requisition_lines_category_id on procurement.requisition_lines (category_id);

alter table procurement.requisition_lines enable row level security;

create policy requisition_lines_select on procurement.requisition_lines for
select
  to authenticated using (
    exists (
      select
        1
      from
        procurement.purchase_requisitions r
      where
        r.id = requisition_id
        and (
          r.requester_id = (select auth.uid ())
          or pg_has_role (current_user, 'buyer', 'member')
          or pg_has_role (current_user, 'approver', 'member')
          or pg_has_role (current_user, 'x-admin', 'member')
        )
    )
  );

create policy requisition_lines_insert on procurement.requisition_lines for insert to authenticated
with
  check (true);

create policy requisition_lines_update on procurement.requisition_lines
for update
  to authenticated using (true)
with
  check (true);

create policy requisition_lines_delete on procurement.requisition_lines for delete to authenticated using (true);

create or replace function procurement.requisition_lines_set_total () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.line_number is null then
    select coalesce(max(line_number), 0) + 10 into new.line_number
    from procurement.requisition_lines
    where requisition_id = new.requisition_id;
  end if;

  new.estimated_total := round(new.quantity * new.estimated_unit_price, 2);
  return new;
end;
$$;

create trigger trg_requisition_lines_set_total before insert
or
update on procurement.requisition_lines for each row
execute function procurement.requisition_lines_set_total ();

create or replace function procurement.requisition_lines_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_requisition_id uuid := coalesce(new.requisition_id, old.requisition_id);
begin
  update procurement.purchase_requisitions r
  set line_count = x.n,
    estimated_total = x.total,
    updated_at = current_timestamp
  from (
    select
      count(*) as n,
      coalesce(sum(estimated_total), 0) as total
    from procurement.requisition_lines
    where requisition_id = v_requisition_id
  ) x
  where r.id = v_requisition_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_requisition_lines_rollup
after insert
or delete
or
update on procurement.requisition_lines for each row
execute function procurement.requisition_lines_rollup ();

----------------------------------------------------------------
-- Requisition approvals — the sequential approval chain
--
-- Steps are decided strictly in order. A step cannot move until every
-- earlier step is approved, the assigned approver is the only one who
-- can decide it (x-admin can override), and the requester can never
-- be their own approver. One rejection anywhere skips everything
-- still pending and kills the requisition — see the rollup trigger
-- below.
----------------------------------------------------------------
create table procurement.requisition_approvals (
  id uuid primary key default extensions.uuid_generate_v4 (),
  requisition_id uuid not null references procurement.purchase_requisitions (id) on delete cascade,
  step_number integer not null default 1,
  approver_id uuid references supasheet.users (id) on delete set null,
  status procurement.approval_status not null default 'pending',
  threshold_amount numeric(14, 2),
  comment varchar(500),
  decided_by uuid references supasheet.users (id) on delete set null,
  decided_at timestamptz,
  created_at timestamptz default current_timestamp,
  unique (requisition_id, step_number),
  constraint requisition_approvals_step_positive check (step_number > 0)
);

comment on column procurement.requisition_approvals.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "skipped": {"variant": "secondary", "icon": "SkipForward"}
    }
}';

comment on table procurement.requisition_approvals is '{
    "icon": "ListChecks",
    "name": "Approvals",
    "description": "The approval chain, one row per step. Steps are decided in order.",
    "display": "none",
    "primary_view": "list",
    "views": [
        {"id": "list", "name": "All Approvals", "type": "list", "title": "step_number", "description": "comment", "field_1": "status", "field_2": "decided_at"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "Awaiting Me", "filters": [{"id": "approver_id", "value": "me", "operator": "eq"}, {"id": "status", "value": "pending", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "step", "title": "Step", "fields": ["requisition_id", "step_number", "approver_id", "threshold_amount"]},
            {"id": "decision", "title": "Decision", "fields": {"update": ["status", "comment"], "read": ["status", "comment", "decided_by", "decided_at"]}}
        ]
    },
    "query": {
        "sort": [{"id": "step_number", "desc": false}],
        "join": [
            {"table": "purchase_requisitions", "on": "requisition_id", "columns": ["requisition_number", "status", "estimated_total"]},
            {"table": "users", "on": "approver_id", "alias": "approver", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table procurement.requisition_approvals
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
delete on table procurement.requisition_approvals to "x-admin";

grant
select
,
  insert on table procurement.requisition_approvals to "buyer";

grant
select
,
update on table procurement.requisition_approvals to "approver";

grant
select
  on table procurement.requisition_approvals to "user";

create index idx_proc_requisition_approvals_requisition_id on procurement.requisition_approvals (requisition_id);

create index idx_proc_requisition_approvals_approver_id on procurement.requisition_approvals (approver_id);

alter table procurement.requisition_approvals enable row level security;

create policy requisition_approvals_select on procurement.requisition_approvals for
select
  to authenticated using (
    approver_id = (select auth.uid ())
    or pg_has_role (current_user, 'buyer', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
    or exists (
      select
        1
      from
        procurement.purchase_requisitions r
      where
        r.id = requisition_id
        and r.requester_id = (select auth.uid ())
    )
  );

create policy requisition_approvals_insert on procurement.requisition_approvals for insert to authenticated
with
  check (true);

create policy requisition_approvals_update on procurement.requisition_approvals
for update
  to authenticated using (true)
with
  check (true);

create policy requisition_approvals_delete on procurement.requisition_approvals for delete to authenticated using (true);

create or replace function procurement.requisition_approvals_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  -- security definer swaps current_user for this function's owner, so
  -- pg_has_role(current_user, ...) would always see the owner's roles,
  -- not the caller's — read the caller's role from the JWT claim instead.
  v_caller_role text := (select auth.jwt () ->> 'role');
begin
  if new.status = old.status then
    return new;
  end if;

  if new.status not in ('approved', 'rejected') then
    raise exception 'An approval step can only be moved to approved or rejected directly.';
  end if;

  if exists (
    select 1
    from procurement.requisition_approvals
    where requisition_id = new.requisition_id
      and step_number < new.step_number
      and status <> 'approved'
  ) then
    raise exception 'Step % cannot be decided until every earlier step has approved.', new.step_number;
  end if;

  if new.approver_id is not null
    and new.approver_id <> (select auth.uid ())
    and not pg_has_role (v_caller_role, 'x-admin', 'member') then
    raise exception 'Only the assigned approver, or x-admin, can decide this step.';
  end if;

  if exists (
    select 1
    from procurement.purchase_requisitions r
    where r.id = new.requisition_id
      and r.requester_id = (select auth.uid ())
  ) and not pg_has_role (v_caller_role, 'x-admin', 'member') then
    raise exception 'The requester cannot approve their own requisition.';
  end if;

  new.decided_by := (select auth.uid ());
  new.decided_at := current_timestamp;
  return new;
end;
$$;

create trigger trg_requisition_approvals_guard before
update of status on procurement.requisition_approvals for each row
execute function procurement.requisition_approvals_guard ();

create or replace function procurement.requisition_approvals_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_requisition_id uuid := coalesce(new.requisition_id, old.requisition_id);
  v_total integer;
  v_approved integer;
  v_rejected boolean;
  v_new_status procurement.requisition_status;
  v_step integer;
begin
  select count(*), count(*) filter (where status = 'approved'), bool_or(status = 'rejected')
    into v_total, v_approved, v_rejected
  from procurement.requisition_approvals
  where requisition_id = v_requisition_id;

  if v_total = 0 then
    return coalesce(new, old);
  end if;

  if v_rejected then
    update procurement.requisition_approvals
    set status = 'skipped'
    where requisition_id = v_requisition_id
      and status = 'pending';

    v_new_status := 'rejected';
    v_step := v_total;
  elsif v_approved = v_total then
    v_new_status := 'approved';
    v_step := v_total;
  else
    v_new_status := 'pending_approval';
    v_step := v_approved + 1;
  end if;

  update procurement.purchase_requisitions
  set status = v_new_status,
    current_approval_step = v_step,
    total_approval_steps = v_total,
    approved_at = case
      when v_new_status = 'approved' then current_timestamp
      else approved_at
    end,
    updated_at = current_timestamp
  where id = v_requisition_id
    and status not in ('cancelled', 'converted');

  return coalesce(new, old);
end;
$$;

create trigger trg_requisition_approvals_rollup
after insert
or delete
or
update on procurement.requisition_approvals for each row
execute function procurement.requisition_approvals_rollup ();

----------------------------------------------------------------
-- RFQs (requests for quotation)
----------------------------------------------------------------
create sequence if not exists procurement.rfq_number_seq;

create table procurement.rfqs (
  id uuid primary key default extensions.uuid_generate_v4 (),
  rfq_number varchar(30) not null unique default (
    'RFQ-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('procurement.rfq_number_seq')::text,
      6,
      '0'
    )
  ),
  requisition_id uuid references procurement.purchase_requisitions (id) on delete set null,
  category_id uuid references procurement.categories (id) on delete set null,
  buyer_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  status procurement.rfq_status not null default 'draft',
  title varchar(200) not null,
  description supasheet.RICH_TEXT,
  issue_date date not null default current_date,
  due_date date,
  currency varchar(3) not null default 'USD',
  supplier_count integer not null default 0,
  quote_count integer not null default 0,
  lowest_quote_total numeric(14, 2),
  awarded_supplier_id uuid references procurement.suppliers (id) on delete set null,
  awarded_at timestamptz,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint rfqs_due_after_issue check (
    due_date is null
    or due_date >= issue_date
  )
);

comment on column procurement.rfqs.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "sent": {"variant": "info", "icon": "Send"},
        "closed": {"variant": "warning", "icon": "Lock"},
        "awarded": {"variant": "success", "icon": "Trophy"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table procurement.rfqs is '{
    "icon": "FileQuestion",
    "name": "RFQs",
    "description": "Requests for quotation — who was asked, what they quoted, and who won.",
    "collapsible_group": "Sourcing",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "rfq_number", "badges": ["status", "quote_count", "lowest_quote_total"]},
        "tabs": ["rfq_lines", "rfq_suppliers", "supplier_quotes"]
    },
    "views": [
        {"id": "kanban", "name": "Sourcing Board", "type": "kanban", "group": "status", "title": "rfq_number", "description": "title", "date": "due_date", "badge": "quote_count"},
        {"id": "calendar", "name": "Due Dates", "type": "calendar", "title": "title", "badge": "status", "start_date": "issue_date", "end_date": "due_date"},
        {"id": "list", "name": "All RFQs", "type": "list", "title": "title", "description": "rfq_number", "field_1": "status", "field_2": "lowest_quote_total"}
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["draft", "sent"], "operator": "in"}]},
        {"id": "awarded", "name": "Awarded", "filters": [{"id": "status", "value": "awarded", "operator": "eq"}]},
        {"id": "no_quotes", "name": "No Quotes Yet", "filters": [{"id": "quote_count", "value": "0", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["title", "category_id", "due_date"],
        "sections": [
            {"id": "identity", "title": "RFQ", "fields": {"create": ["title", "description", "requisition_id", "category_id", "issue_date", "due_date", "currency"], "update": ["title", "description", "due_date", "status"], "read": ["title", "description", "requisition_id", "category_id", "buyer_id", "issue_date", "due_date", "currency", "status"]}},
            {"id": "totals", "title": "Responses", "fields": {"read": ["supplier_count", "quote_count", "lowest_quote_total"]}},
            {"id": "award", "title": "Award", "fields": {"read": ["awarded_supplier_id", "awarded_at"]}},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "issue_date", "desc": true}],
        "join": [
            {"table": "purchase_requisitions", "on": "requisition_id", "columns": ["requisition_number", "status"]},
            {"table": "categories", "on": "category_id", "columns": ["code", "name"]},
            {"table": "suppliers", "on": "awarded_supplier_id", "alias": "winner", "columns": ["code", "name"]},
            {"table": "users", "on": "buyer_id", "alias": "buyer", "columns": ["name", "email"]}
        ]
    }
}';

comment on column procurement.rfqs.lowest_quote_total is '{"name": "Lowest Quote", "aggregate": "min"}';

revoke all on table procurement.rfqs
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
delete on table procurement.rfqs to "x-admin";

grant
select
,
  insert,
update on table procurement.rfqs to "buyer";

revoke all on sequence procurement.rfq_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence procurement.rfq_number_seq to "x-admin",
"buyer";

create index idx_proc_rfqs_status on procurement.rfqs (status);

create index idx_proc_rfqs_requisition_id on procurement.rfqs (requisition_id);

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

create table procurement.rfq_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  rfq_id uuid not null references procurement.rfqs (id) on delete cascade,
  line_number integer,
  description varchar(300) not null,
  quantity numeric(12, 3) not null default 1,
  uom varchar(20) not null default 'EA',
  target_price numeric(14, 4),
  created_at timestamptz default current_timestamp,
  constraint rfq_lines_quantity_positive check (quantity > 0)
);

comment on table procurement.rfq_lines is '{
    "icon": "Rows3",
    "name": "RFQ Lines",
    "description": "What is being quoted.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "item", "title": "Item", "fields": ["rfq_id", "line_number", "description"]},
            {"id": "quantity", "title": "Quantity", "fields": ["quantity", "uom", "target_price"]}
        ]
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [{"table": "rfqs", "on": "rfq_id", "columns": ["rfq_number", "status"]}]
    }
}';

revoke all on table procurement.rfq_lines
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
delete on table procurement.rfq_lines to "x-admin",
"buyer";

create index idx_proc_rfq_lines_rfq_id on procurement.rfq_lines (rfq_id);

alter table procurement.rfq_lines enable row level security;

create policy rfq_lines_select on procurement.rfq_lines for
select
  to authenticated using (true);

create policy rfq_lines_insert on procurement.rfq_lines for insert to authenticated
with
  check (true);

create policy rfq_lines_update on procurement.rfq_lines
for update
  to authenticated using (true)
with
  check (true);

create policy rfq_lines_delete on procurement.rfq_lines for delete to authenticated using (true);

create or replace function procurement.rfq_lines_set_number () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.line_number is null then
    select coalesce(max(line_number), 0) + 10 into new.line_number
    from procurement.rfq_lines
    where rfq_id = new.rfq_id;
  end if;
  return new;
end;
$$;

create trigger trg_rfq_lines_set_number before insert on procurement.rfq_lines for each row
execute function procurement.rfq_lines_set_number ();

----------------------------------------------------------------
-- RFQ suppliers (junction — who was invited)
----------------------------------------------------------------
create table procurement.rfq_suppliers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  rfq_id uuid not null references procurement.rfqs (id) on delete cascade,
  supplier_id uuid not null references procurement.suppliers (id) on delete restrict,
  invited_at timestamptz not null default current_timestamp,
  notes varchar(300),
  unique (rfq_id, supplier_id)
);

comment on table procurement.rfq_suppliers is '{
    "icon": "Users",
    "name": "Invited Suppliers",
    "description": "Who this RFQ was sent to.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "invite", "title": "Invite", "fields": ["rfq_id", "supplier_id", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "invited_at", "desc": false}],
        "join": [
            {"table": "rfqs", "on": "rfq_id", "columns": ["rfq_number", "status"]},
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name", "status"]}
        ]
    }
}';

revoke all on table procurement.rfq_suppliers
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
delete on table procurement.rfq_suppliers to "x-admin",
"buyer";

create index idx_proc_rfq_suppliers_rfq_id on procurement.rfq_suppliers (rfq_id);

create index idx_proc_rfq_suppliers_supplier_id on procurement.rfq_suppliers (supplier_id);

alter table procurement.rfq_suppliers enable row level security;

create policy rfq_suppliers_select on procurement.rfq_suppliers for
select
  to authenticated using (true);

create policy rfq_suppliers_insert on procurement.rfq_suppliers for insert to authenticated
with
  check (true);

create policy rfq_suppliers_delete on procurement.rfq_suppliers for delete to authenticated using (true);

create or replace function procurement.rfq_suppliers_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_rfq_id uuid := coalesce(new.rfq_id, old.rfq_id);
begin
  update procurement.rfqs
  set supplier_count = (
      select count(*) from procurement.rfq_suppliers where rfq_id = v_rfq_id
    ),
    updated_at = current_timestamp
  where id = v_rfq_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_rfq_suppliers_rollup
after insert
or delete on procurement.rfq_suppliers for each row
execute function procurement.rfq_suppliers_rollup ();

----------------------------------------------------------------
-- Supplier quotes
----------------------------------------------------------------
create table procurement.supplier_quotes (
  id uuid primary key default extensions.uuid_generate_v4 (),
  rfq_id uuid not null references procurement.rfqs (id) on delete cascade,
  supplier_id uuid not null references procurement.suppliers (id) on delete restrict,
  status procurement.quote_status not null default 'invited',
  quote_reference varchar(60),
  submitted_at timestamptz,
  valid_until date,
  currency varchar(3) not null default 'USD',
  subtotal numeric(14, 2) not null default 0,
  tax_total numeric(14, 2) not null default 0,
  total numeric(14, 2) not null default 0,
  lead_time_days integer,
  payment_terms_days integer,
  is_compliant boolean not null default true,
  document supasheet.file,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (rfq_id, supplier_id)
);

comment on column procurement.supplier_quotes.status is '{
    "progress": true,
    "values": {
        "invited": {"variant": "secondary", "icon": "Mail"},
        "submitted": {"variant": "info", "icon": "FileCheck"},
        "shortlisted": {"variant": "warning", "icon": "Star"},
        "awarded": {"variant": "success", "icon": "Trophy"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "expired": {"variant": "secondary", "icon": "Clock"}
    }
}';

comment on table procurement.supplier_quotes is '{
    "icon": "FileSpreadsheet",
    "name": "Supplier Quotes",
    "description": "What each supplier bid, and whether it is still worth the paper.",
    "collapsible_group": "Sourcing",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "quote_reference", "badges": ["status", "total"]},
        "tabs": ["quote_lines"]
    },
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "quote_reference", "description": "currency", "date": "valid_until", "badge": "total"},
        {"id": "list", "name": "All Quotes", "type": "list", "title": "quote_reference", "description": "currency", "field_1": "status", "field_2": "total"}
    ],
    "filter_presets": [
        {"id": "submitted", "name": "Submitted", "filters": [{"id": "status", "value": "submitted", "operator": "eq"}]},
        {"id": "shortlisted", "name": "Shortlisted", "filters": [{"id": "status", "value": "shortlisted", "operator": "eq"}]},
        {"id": "non_compliant", "name": "Non-Compliant", "filters": [{"id": "is_compliant", "value": "false", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["rfq_id", "supplier_id", "valid_until"],
        "sections": [
            {"id": "quote", "title": "Quote", "fields": {"create": ["rfq_id", "supplier_id", "quote_reference", "submitted_at", "valid_until", "currency"], "update": ["quote_reference", "submitted_at", "valid_until", "status", "is_compliant"], "read": ["rfq_id", "supplier_id", "quote_reference", "submitted_at", "valid_until", "currency", "status", "is_compliant"]}},
            {"id": "terms", "title": "Terms", "fields": ["lead_time_days", "payment_terms_days"]},
            {"id": "totals", "title": "Totals", "fields": {"read": ["subtotal", "tax_total", "total"]}},
            {"id": "extras", "title": "Document & Notes", "collapsible": true, "fields": ["document", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "total", "desc": false}],
        "join": [
            {"table": "rfqs", "on": "rfq_id", "columns": ["rfq_number", "title", "status"]},
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name", "status"]}
        ]
    }
}';

comment on column procurement.supplier_quotes.total is '{"aggregate": "sum"}';

comment on column procurement.supplier_quotes.document is '{"accept": ".pdf", "maxFiles": 2, "maxSize": 10485760}';

revoke all on table procurement.supplier_quotes
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
delete on table procurement.supplier_quotes to "x-admin",
"buyer";

create index idx_proc_supplier_quotes_rfq_id on procurement.supplier_quotes (rfq_id);

create index idx_proc_supplier_quotes_supplier_id on procurement.supplier_quotes (supplier_id);

alter table procurement.supplier_quotes enable row level security;

create policy supplier_quotes_select on procurement.supplier_quotes for
select
  to authenticated using (true);

create policy supplier_quotes_insert on procurement.supplier_quotes for insert to authenticated
with
  check (true);

create policy supplier_quotes_update on procurement.supplier_quotes
for update
  to authenticated using (true)
with
  check (true);

create policy supplier_quotes_delete on procurement.supplier_quotes for delete to authenticated using (true);

create or replace function procurement.supplier_quotes_rollup_rfq () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_rfq_id uuid := coalesce(new.rfq_id, old.rfq_id);
begin
  update procurement.rfqs
  set quote_count = x.n,
    lowest_quote_total = x.lowest,
    updated_at = current_timestamp
  from (
    select
      count(*) filter (where status in ('submitted', 'shortlisted', 'awarded')) as n,
      min(total) filter (where status in ('submitted', 'shortlisted', 'awarded')) as lowest
    from procurement.supplier_quotes
    where rfq_id = v_rfq_id
  ) x
  where id = v_rfq_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_supplier_quotes_rollup_rfq
after insert
or delete
or
update on procurement.supplier_quotes for each row
execute function procurement.supplier_quotes_rollup_rfq ();

create table procurement.quote_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  quote_id uuid not null references procurement.supplier_quotes (id) on delete cascade,
  rfq_line_id uuid not null references procurement.rfq_lines (id) on delete restrict,
  unit_price numeric(14, 4) not null default 0,
  quantity numeric(12, 3) not null default 1,
  lead_time_days integer,
  line_total numeric(14, 2) not null default 0,
  notes varchar(300),
  created_at timestamptz default current_timestamp,
  unique (quote_id, rfq_line_id),
  constraint quote_lines_price_non_negative check (unit_price >= 0),
  constraint quote_lines_quantity_positive check (quantity > 0)
);

comment on table procurement.quote_lines is '{
    "icon": "Rows3",
    "name": "Quote Lines",
    "description": "Line-by-line pricing for one supplier''s quote.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["quote_id", "rfq_line_id", "quantity", "unit_price", "lead_time_days"]},
            {"id": "notes", "title": "Notes", "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [
            {"table": "supplier_quotes", "on": "quote_id", "columns": ["quote_reference", "status"]},
            {"table": "rfq_lines", "on": "rfq_line_id", "columns": ["description", "quantity", "uom"]}
        ]
    }
}';

comment on column procurement.quote_lines.line_total is '{"aggregate": "sum"}';

revoke all on table procurement.quote_lines
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
delete on table procurement.quote_lines to "x-admin",
"buyer";

create index idx_proc_quote_lines_quote_id on procurement.quote_lines (quote_id);

create index idx_proc_quote_lines_rfq_line_id on procurement.quote_lines (rfq_line_id);

alter table procurement.quote_lines enable row level security;

create policy quote_lines_select on procurement.quote_lines for
select
  to authenticated using (true);

create policy quote_lines_insert on procurement.quote_lines for insert to authenticated
with
  check (true);

create policy quote_lines_update on procurement.quote_lines
for update
  to authenticated using (true)
with
  check (true);

create policy quote_lines_delete on procurement.quote_lines for delete to authenticated using (true);

create or replace function procurement.quote_lines_set_total () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  new.line_total := round(new.quantity * new.unit_price, 2);
  return new;
end;
$$;

create trigger trg_quote_lines_set_total before insert
or
update on procurement.quote_lines for each row
execute function procurement.quote_lines_set_total ();

create or replace function procurement.quote_lines_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_quote_id uuid := coalesce(new.quote_id, old.quote_id);
begin
  update procurement.supplier_quotes q
  set subtotal = x.subtotal,
    total = x.subtotal + q.tax_total,
    updated_at = current_timestamp
  from (
    select coalesce(sum(line_total), 0) as subtotal
    from procurement.quote_lines
    where quote_id = v_quote_id
  ) x
  where q.id = v_quote_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_quote_lines_rollup
after insert
or delete
or
update on procurement.quote_lines for each row
execute function procurement.quote_lines_rollup ();

----------------------------------------------------------------
-- Contracts (blanket / framework agreements)
--
-- consumed_amount is a rollup maintained from the purchase orders
-- section below, which is also where the ceiling is enforced —
-- a purchase order cannot push consumed_amount past ceiling_amount.
----------------------------------------------------------------
create sequence if not exists procurement.contract_number_seq;

create table procurement.contracts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  contract_number varchar(30) not null unique default (
    'CTR-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('procurement.contract_number_seq')::text,
      5,
      '0'
    )
  ),
  supplier_id uuid not null references procurement.suppliers (id) on delete restrict,
  category_id uuid references procurement.categories (id) on delete set null,
  owner_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  contract_type procurement.contract_type not null default 'blanket',
  status procurement.contract_status not null default 'draft',
  title varchar(200) not null,
  start_date date not null default current_date,
  end_date date not null,
  currency varchar(3) not null default 'USD',
  ceiling_amount numeric(14, 2) not null default 0,
  consumed_amount numeric(14, 2) not null default 0,
  auto_renew boolean not null default false,
  renewal_notice_days integer not null default 30,
  payment_terms_days integer not null default 30,
  document supasheet.file,
  terms supasheet.RICH_TEXT,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint contracts_window check (end_date >= start_date),
  constraint contracts_ceiling_non_negative check (ceiling_amount >= 0)
);

comment on column procurement.contracts.contract_type is '{
    "progress": false,
    "values": {
        "blanket": {"variant": "info", "icon": "FileStack"},
        "framework": {"variant": "default", "icon": "Layers"},
        "spot": {"variant": "secondary", "icon": "Zap"},
        "service": {"variant": "success", "icon": "Handshake"}
    }
}';

comment on column procurement.contracts.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "active": {"variant": "success", "icon": "CircleCheck"},
        "expired": {"variant": "warning", "icon": "Clock"},
        "terminated": {"variant": "destructive", "icon": "Ban"},
        "renewed": {"variant": "info", "icon": "RefreshCw"}
    }
}';

comment on table procurement.contracts is '{
    "icon": "FileSignature",
    "name": "Contracts",
    "description": "Standing agreements with a ceiling. An order raised against one cannot push spend past it.",
    "collapsible_group": "Sourcing",
    "display": "block",
    "primary_view": "gantt",
    "detail": {
        "header": {"title": "title", "badges": ["status", "contract_type", "consumed_amount"]},
        "tabs": ["purchase_orders"]
    },
    "views": [
        {"id": "gantt", "name": "Contract Calendar", "type": "gantt", "title": "title", "start_date": "start_date", "end_date": "end_date", "group": "status", "badge": "contract_type"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "title", "description": "contract_number", "date": "end_date", "badge": "contract_type"},
        {"id": "list", "name": "All Contracts", "type": "list", "title": "title", "description": "contract_number", "field_1": "ceiling_amount", "field_2": "consumed_amount"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "expiring_soon", "name": "Expiring Within 60 Days", "filters": [{"id": "end_date", "value": "60_days_from_now", "operator": "lte"}, {"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "near_ceiling", "name": "Near Ceiling", "filters": [{"id": "consumed_amount", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["supplier_id", "title", "contract_type", "end_date"],
        "sections": [
            {"id": "identity", "title": "Contract", "fields": {"create": ["supplier_id", "category_id", "title", "contract_type", "start_date", "end_date", "currency"], "update": ["title", "contract_type", "status", "start_date", "end_date"], "read": ["supplier_id", "category_id", "owner_id", "title", "contract_type", "status", "start_date", "end_date", "currency"]}},
            {"id": "value", "title": "Value", "fields": ["ceiling_amount"]},
            {"id": "position", "title": "Position", "fields": {"read": ["consumed_amount"]}},
            {"id": "terms", "title": "Terms", "fields": ["payment_terms_days", "auto_renew", "renewal_notice_days"]},
            {"id": "extras", "title": "Document & Notes", "collapsible": true, "fields": ["document", "terms", "notes"]}
        ],
        "metadata": {
            "consumed_amount": {"description": "Sum of every non-cancelled purchase order raised against this contract. Cannot be typed — a new order is refused once this would exceed the ceiling."}
        }
    },
    "query": {
        "sort": [{"id": "end_date", "desc": false}],
        "join": [
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name", "status"]},
            {"table": "categories", "on": "category_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column procurement.contracts.ceiling_amount is '{"name": "Ceiling", "aggregate": "sum"}';

comment on column procurement.contracts.consumed_amount is '{"name": "Consumed", "aggregate": "sum"}';

comment on column procurement.contracts.document is '{"accept": ".pdf,.doc,.docx", "maxFiles": 3, "maxSize": 10485760}';

revoke all on table procurement.contracts
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
delete on table procurement.contracts to "x-admin";

grant
select
,
  insert,
update on table procurement.contracts to "buyer";

grant
select
  on table procurement.contracts to "approver";

revoke all on sequence procurement.contract_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence procurement.contract_number_seq to "x-admin",
"buyer";

create index idx_proc_contracts_supplier_id on procurement.contracts (supplier_id);

create index idx_proc_contracts_status on procurement.contracts (status);

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

create trigger contracts_updated_at before
update on procurement.contracts for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Purchase orders
--
-- The guard trigger below is what makes the "no blocked suppliers"
-- and "contract ceiling" rules real: it runs on insert AND on every
-- update that could change either fact (supplier, contract, total,
-- status), which includes the line-rollup trigger further down
-- rewriting `total` — so re-pricing an order re-checks the ceiling
-- automatically, nobody has to remember to.
----------------------------------------------------------------
create sequence if not exists procurement.po_number_seq;

create table procurement.purchase_orders (
  id uuid primary key default extensions.uuid_generate_v4 (),
  po_number varchar(30) not null unique default (
    'PO-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('procurement.po_number_seq')::text,
      6,
      '0'
    )
  ),
  supplier_id uuid not null references procurement.suppliers (id) on delete restrict,
  requisition_id uuid references procurement.purchase_requisitions (id) on delete set null,
  contract_id uuid references procurement.contracts (id) on delete set null,
  department_id uuid not null references procurement.departments (id) on delete restrict,
  category_id uuid references procurement.categories (id) on delete set null,
  buyer_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  status procurement.po_status not null default 'draft',
  priority procurement.priority_level not null default 'normal',
  currency varchar(3) not null default 'USD',
  incoterms varchar(20),
  order_date date not null default current_date,
  expected_delivery_date date,
  delivery_address text,
  billing_address text,
  supplier_reference varchar(60),
  subtotal numeric(14, 2) not null default 0,
  tax_total numeric(14, 2) not null default 0,
  shipping_total numeric(14, 2) not null default 0,
  total numeric(14, 2) not null default 0,
  received_value numeric(14, 2) not null default 0,
  invoiced_value numeric(14, 2) not null default 0,
  line_count integer not null default 0,
  current_approval_step integer not null default 0,
  total_approval_steps integer not null default 0,
  document supasheet.file,
  notes supasheet.RICH_TEXT,
  terms supasheet.RICH_TEXT,
  sent_at timestamptz,
  acknowledged_at timestamptz,
  closed_at timestamptz,
  cancelled_reason varchar(300),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint po_totals_non_negative check (
    subtotal >= 0
    and tax_total >= 0
    and shipping_total >= 0
    and total >= 0
  )
);

comment on column procurement.purchase_orders.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "pending_approval": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "sent": {"variant": "info", "icon": "Send"},
        "acknowledged": {"variant": "info", "icon": "MailCheck"},
        "partially_received": {"variant": "warning", "icon": "PackageOpen"},
        "received": {"variant": "success", "icon": "PackageCheck"},
        "invoiced": {"variant": "default", "icon": "Receipt"},
        "closed": {"variant": "secondary", "icon": "Archive"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on column procurement.purchase_orders.priority is '{
    "progress": false,
    "values": {
        "low": {"variant": "secondary", "icon": "ArrowDown"},
        "normal": {"variant": "info", "icon": "Minus"},
        "high": {"variant": "warning", "icon": "ArrowUp"},
        "urgent": {"variant": "destructive", "icon": "TriangleAlert"}
    }
}';

comment on table procurement.purchase_orders is '{
    "icon": "FileText",
    "name": "Purchase Orders",
    "description": "The commitment to spend. What was ordered, from whom, against what agreement, and how far along it is.",
    "collapsible_group": "Ordering",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "po_number", "badges": ["status", "priority", "total"]},
        "tabs": ["purchase_order_lines", "po_approvals", "goods_receipts", "vendor_invoices"],
        "timelines": ["purchase_order_events"]
    },
    "views": [
        {"id": "kanban", "name": "Order Board", "type": "kanban", "group": "status", "title": "po_number", "description": "supplier_reference", "date": "expected_delivery_date", "badge": "priority"},
        {"id": "calendar", "name": "Delivery Calendar", "type": "calendar", "title": "po_number", "badge": "status", "start_date": "order_date", "end_date": "expected_delivery_date"},
        {"id": "list", "name": "All Orders", "type": "list", "title": "po_number", "description": "supplier_reference", "field_1": "status", "field_2": "total"}
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["draft", "pending_approval", "approved", "sent", "acknowledged", "partially_received"], "operator": "in"}]},
        {"id": "pending_approval", "name": "Awaiting Approval", "filters": [{"id": "status", "value": "pending_approval", "operator": "eq"}]},
        {"id": "overdue", "name": "Overdue Delivery", "filters": [{"id": "expected_delivery_date", "value": "today", "operator": "lt"}, {"id": "status", "value": ["sent", "acknowledged", "partially_received"], "operator": "in"}]},
        {"id": "urgent", "name": "Urgent", "filters": [{"id": "priority", "value": "urgent", "operator": "eq"}]}
    ],
    "links": [
        {"id": "print", "name": "Printable Order", "url": "/procurement/report/purchase_orders_report", "icon": "Printer", "description": "The order document to send to the supplier"}
    ],
    "fields": {
        "quick_create": ["supplier_id", "department_id", "expected_delivery_date", "priority"],
        "sections": [
            {"id": "order", "title": "Order", "fields": {"create": ["supplier_id", "requisition_id", "contract_id", "department_id", "category_id", "order_date", "expected_delivery_date", "priority", "currency"], "update": ["expected_delivery_date", "priority", "supplier_reference", "incoterms"], "read": ["supplier_id", "requisition_id", "contract_id", "department_id", "category_id", "buyer_id", "order_date", "expected_delivery_date", "priority", "currency", "supplier_reference", "incoterms"]}},
            {"id": "addresses", "title": "Addresses", "fields": ["delivery_address", "billing_address"]},
            {"id": "state", "title": "State", "fields": {"read": ["status", "cancelled_reason", "sent_at", "acknowledged_at", "closed_at"]}},
            {"id": "totals", "title": "Totals", "fields": {"create": ["shipping_total"], "update": ["shipping_total"], "read": ["line_count", "subtotal", "tax_total", "shipping_total", "total", "received_value", "invoiced_value"]}},
            {"id": "extras", "title": "Document & Notes", "collapsible": true, "fields": ["document", "terms", "notes"]}
        ],
        "behavior": {
            "cancelled_reason": {"visible": [{"id": "status", "operator": "eq", "value": "cancelled"}]}
        },
        "lookups": {
            "supplier_id": {"filter": [{"source_column": "category_id", "target_column": "category_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "order_date", "desc": true}],
        "join": [
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name", "status"]},
            {"table": "purchase_requisitions", "on": "requisition_id", "columns": ["requisition_number", "status"]},
            {"table": "contracts", "on": "contract_id", "columns": ["contract_number", "title"]},
            {"table": "departments", "on": "department_id", "columns": ["code", "name"]},
            {"table": "users", "on": "buyer_id", "alias": "buyer", "columns": ["name", "email"]}
        ]
    }
}';

comment on column procurement.purchase_orders.total is '{"aggregate": "sum"}';

comment on column procurement.purchase_orders.received_value is '{"name": "Received", "aggregate": "sum"}';

comment on column procurement.purchase_orders.document is '{"accept": ".pdf", "maxFiles": 3, "maxSize": 10485760}';

revoke all on table procurement.purchase_orders
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
delete on table procurement.purchase_orders to "x-admin";

grant
select
,
  insert,
update on table procurement.purchase_orders to "buyer";

grant
select
  on table procurement.purchase_orders to "approver",
  "user";

revoke all on sequence procurement.po_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence procurement.po_number_seq to "x-admin",
"buyer";

create index idx_proc_po_supplier_id on procurement.purchase_orders (supplier_id);

create index idx_proc_po_requisition_id on procurement.purchase_orders (requisition_id);

create index idx_proc_po_contract_id on procurement.purchase_orders (contract_id);

create index idx_proc_po_department_id on procurement.purchase_orders (department_id);

create index idx_proc_po_status on procurement.purchase_orders (status);

create index idx_proc_po_open on procurement.purchase_orders (expected_delivery_date)
where
  status in (
    'sent',
    'acknowledged',
    'partially_received'
  );

alter table procurement.purchase_orders enable row level security;

create policy po_select on procurement.purchase_orders for
select
  to authenticated using (
    pg_has_role (current_user, 'buyer', 'member')
    or pg_has_role (current_user, 'approver', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
    or exists (
      select
        1
      from
        procurement.purchase_requisitions r
      where
        r.id = requisition_id
        and r.requester_id = (select auth.uid ())
    )
  );

create policy po_insert on procurement.purchase_orders for insert to authenticated
with
  check (true);

create policy po_update on procurement.purchase_orders
for update
  to authenticated using (true)
with
  check (true);

create policy po_delete on procurement.purchase_orders for delete to authenticated using (true);

create trigger po_updated_at before
update on procurement.purchase_orders for each row
execute function supasheet.set_updated_at ();

create or replace function procurement.purchase_orders_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_supplier_status procurement.supplier_status;
  v_ceiling numeric(14, 2);
  v_consumed_others numeric(14, 2);
begin
  select status into v_supplier_status
  from procurement.suppliers
  where id = new.supplier_id;

  if v_supplier_status in ('on_hold', 'blacklisted') then
    raise exception 'This supplier is % and cannot be ordered from.', v_supplier_status
      using hint = 'Take the supplier off hold, or choose a different one.';
  end if;

  if new.contract_id is not null and new.status <> 'cancelled' then
    select ceiling_amount into v_ceiling
    from procurement.contracts
    where id = new.contract_id;

    select coalesce(sum(total), 0) into v_consumed_others
    from procurement.purchase_orders
    where contract_id = new.contract_id
      and status <> 'cancelled'
      and id <> new.id;

    if (v_consumed_others + new.total) > v_ceiling then
      raise exception 'This order would take contract spend to % against a ceiling of %.',
        (v_consumed_others + new.total), v_ceiling
        using hint = 'Reduce the order, raise the ceiling, or order against a different contract.';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_purchase_orders_guard before insert
or
update of supplier_id,
contract_id,
total,
status on procurement.purchase_orders for each row
execute function procurement.purchase_orders_guard ();

----------------------------------------------------------------
-- Purchase order lines
----------------------------------------------------------------
create table procurement.purchase_order_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  po_id uuid not null references procurement.purchase_orders (id) on delete cascade,
  requisition_line_id uuid references procurement.requisition_lines (id) on delete set null,
  category_id uuid references procurement.categories (id) on delete set null,
  line_number integer,
  description varchar(300) not null,
  quantity_ordered numeric(12, 3) not null default 1,
  uom varchar(20) not null default 'EA',
  unit_price numeric(14, 4) not null default 0,
  discount_percent supasheet.PERCENTAGE not null default 0,
  tax_rate supasheet.PERCENTAGE not null default 0,
  line_subtotal numeric(14, 2) not null default 0,
  tax_amount numeric(14, 2) not null default 0,
  line_total numeric(14, 2) not null default 0,
  quantity_received numeric(12, 3) not null default 0,
  quantity_invoiced numeric(12, 3) not null default 0,
  needed_by date,
  created_at timestamptz default current_timestamp,
  constraint po_lines_quantity_positive check (quantity_ordered > 0),
  constraint po_lines_price_non_negative check (unit_price >= 0),
  constraint po_lines_discount_range check (
    discount_percent >= 0
    and discount_percent <= 100
  ),
  constraint po_lines_received_sane check (quantity_received >= 0)
);

comment on table procurement.purchase_order_lines is '{
    "icon": "Rows3",
    "name": "Order Lines",
    "description": "What was ordered, and how much of it has arrived or been billed so far.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "item", "title": "Item", "fields": ["po_id", "requisition_line_id", "line_number", "description", "category_id"]},
            {"id": "quantity", "title": "Quantity & Price", "fields": ["quantity_ordered", "uom", "unit_price", "discount_percent", "tax_rate"]},
            {"id": "delivery", "title": "Delivery", "fields": ["needed_by"]},
            {"id": "totals", "title": "Totals", "fields": {"read": ["line_subtotal", "tax_amount", "line_total", "quantity_received", "quantity_invoiced"]}}
        ]
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "purchase_orders", "on": "po_id", "columns": ["po_number", "status"]},
            {"table": "categories", "on": "category_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column procurement.purchase_order_lines.line_total is '{"aggregate": "sum"}';

comment on column procurement.purchase_order_lines.quantity_received is '{"name": "Received", "aggregate": "sum"}';

revoke all on table procurement.purchase_order_lines
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
delete on table procurement.purchase_order_lines to "x-admin",
"buyer";

grant
select
  on table procurement.purchase_order_lines to "approver",
  "user";

create index idx_proc_po_lines_po_id on procurement.purchase_order_lines (po_id);

create index idx_proc_po_lines_category_id on procurement.purchase_order_lines (category_id);

alter table procurement.purchase_order_lines enable row level security;

create policy po_lines_select on procurement.purchase_order_lines for
select
  to authenticated using (
    exists (
      select
        1
      from
        procurement.purchase_orders po
      where
        po.id = po_id
        and (
          pg_has_role (current_user, 'buyer', 'member')
          or pg_has_role (current_user, 'approver', 'member')
          or pg_has_role (current_user, 'x-admin', 'member')
          or exists (
            select
              1
            from
              procurement.purchase_requisitions r
            where
              r.id = po.requisition_id
              and r.requester_id = (select auth.uid ())
          )
        )
    )
  );

create policy po_lines_insert on procurement.purchase_order_lines for insert to authenticated
with
  check (true);

create policy po_lines_update on procurement.purchase_order_lines
for update
  to authenticated using (true)
with
  check (true);

create policy po_lines_delete on procurement.purchase_order_lines for delete to authenticated using (true);

create or replace function procurement.po_lines_set_total () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.line_number is null then
    select coalesce(max(line_number), 0) + 10 into new.line_number
    from procurement.purchase_order_lines
    where po_id = new.po_id;
  end if;

  new.line_subtotal := round(new.quantity_ordered * new.unit_price * (1 - new.discount_percent::numeric / 100.0), 2);
  new.tax_amount := round(new.line_subtotal * new.tax_rate::numeric / 100.0, 2);
  new.line_total := new.line_subtotal + new.tax_amount;
  return new;
end;
$$;

create trigger trg_po_lines_set_total before insert
or
update on procurement.purchase_order_lines for each row
execute function procurement.po_lines_set_total ();

create or replace function procurement.po_lines_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_po_id uuid := coalesce(new.po_id, old.po_id);
begin
  update procurement.purchase_orders po
  set line_count = x.n,
    subtotal = x.subtotal,
    tax_total = x.tax_total,
    total = x.subtotal + x.tax_total + po.shipping_total
  from (
    select
      count(*) as n,
      coalesce(sum(line_subtotal), 0) as subtotal,
      coalesce(sum(tax_amount), 0) as tax_total
    from procurement.purchase_order_lines
    where po_id = v_po_id
  ) x
  where po.id = v_po_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_po_lines_rollup
after insert
or delete
or
update on procurement.purchase_order_lines for each row
execute function procurement.po_lines_rollup ();

----------------------------------------------------------------
-- PO approvals — the same sequential engine as requisitions
----------------------------------------------------------------
create table procurement.po_approvals (
  id uuid primary key default extensions.uuid_generate_v4 (),
  po_id uuid not null references procurement.purchase_orders (id) on delete cascade,
  step_number integer not null default 1,
  approver_id uuid references supasheet.users (id) on delete set null,
  status procurement.approval_status not null default 'pending',
  threshold_amount numeric(14, 2),
  comment varchar(500),
  decided_by uuid references supasheet.users (id) on delete set null,
  decided_at timestamptz,
  created_at timestamptz default current_timestamp,
  unique (po_id, step_number),
  constraint po_approvals_step_positive check (step_number > 0)
);

comment on column procurement.po_approvals.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "skipped": {"variant": "secondary", "icon": "SkipForward"}
    }
}';

comment on table procurement.po_approvals is '{
    "icon": "ListChecks",
    "name": "Order Approvals",
    "description": "The approval chain for this order, one row per step, decided in order.",
    "display": "none",
    "primary_view": "list",
    "views": [
        {"id": "list", "name": "All Approvals", "type": "list", "title": "step_number", "description": "comment", "field_1": "status", "field_2": "decided_at"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "Awaiting Me", "filters": [{"id": "approver_id", "value": "me", "operator": "eq"}, {"id": "status", "value": "pending", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "step", "title": "Step", "fields": ["po_id", "step_number", "approver_id", "threshold_amount"]},
            {"id": "decision", "title": "Decision", "fields": {"update": ["status", "comment"], "read": ["status", "comment", "decided_by", "decided_at"]}}
        ]
    },
    "query": {
        "sort": [{"id": "step_number", "desc": false}],
        "join": [
            {"table": "purchase_orders", "on": "po_id", "columns": ["po_number", "status", "total"]},
            {"table": "users", "on": "approver_id", "alias": "approver", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table procurement.po_approvals
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
delete on table procurement.po_approvals to "x-admin";

grant
select
,
  insert on table procurement.po_approvals to "buyer";

grant
select
,
update on table procurement.po_approvals to "approver";

create index idx_proc_po_approvals_po_id on procurement.po_approvals (po_id);

create index idx_proc_po_approvals_approver_id on procurement.po_approvals (approver_id);

alter table procurement.po_approvals enable row level security;

create policy po_approvals_select on procurement.po_approvals for
select
  to authenticated using (
    approver_id = (select auth.uid ())
    or pg_has_role (current_user, 'buyer', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  );

create policy po_approvals_insert on procurement.po_approvals for insert to authenticated
with
  check (true);

create policy po_approvals_update on procurement.po_approvals
for update
  to authenticated using (true)
with
  check (true);

create policy po_approvals_delete on procurement.po_approvals for delete to authenticated using (true);

create or replace function procurement.po_approvals_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  -- security definer swaps current_user for this function's owner, so
  -- pg_has_role(current_user, ...) would always see the owner's roles,
  -- not the caller's — read the caller's role from the JWT claim instead.
  v_caller_role text := (select auth.jwt () ->> 'role');
begin
  if new.status = old.status then
    return new;
  end if;

  if new.status not in ('approved', 'rejected') then
    raise exception 'An approval step can only be moved to approved or rejected directly.';
  end if;

  if exists (
    select 1
    from procurement.po_approvals
    where po_id = new.po_id
      and step_number < new.step_number
      and status <> 'approved'
  ) then
    raise exception 'Step % cannot be decided until every earlier step has approved.', new.step_number;
  end if;

  if new.approver_id is not null
    and new.approver_id <> (select auth.uid ())
    and not pg_has_role (v_caller_role, 'x-admin', 'member') then
    raise exception 'Only the assigned approver, or x-admin, can decide this step.';
  end if;

  new.decided_by := (select auth.uid ());
  new.decided_at := current_timestamp;
  return new;
end;
$$;

create trigger trg_po_approvals_guard before
update of status on procurement.po_approvals for each row
execute function procurement.po_approvals_guard ();

create or replace function procurement.po_approvals_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_po_id uuid := coalesce(new.po_id, old.po_id);
  v_total integer;
  v_approved integer;
  v_rejected boolean;
  v_new_status procurement.po_status;
  v_step integer;
begin
  select count(*), count(*) filter (where status = 'approved'), bool_or(status = 'rejected')
    into v_total, v_approved, v_rejected
  from procurement.po_approvals
  where po_id = v_po_id;

  if v_total = 0 then
    return coalesce(new, old);
  end if;

  if v_rejected then
    update procurement.po_approvals
    set status = 'skipped'
    where po_id = v_po_id
      and status = 'pending';

    v_new_status := 'cancelled';
    v_step := v_total;
  elsif v_approved = v_total then
    v_new_status := 'approved';
    v_step := v_total;
  else
    v_new_status := 'pending_approval';
    v_step := v_approved + 1;
  end if;

  update procurement.purchase_orders
  set status = v_new_status,
    current_approval_step = v_step,
    total_approval_steps = v_total,
    cancelled_reason = case
      when v_new_status = 'cancelled' then 'Rejected during approval'
      else cancelled_reason
    end
  where id = v_po_id
    and status in ('draft', 'pending_approval');

  return coalesce(new, old);
end;
$$;

create trigger trg_po_approvals_rollup
after insert
or delete
or
update on procurement.po_approvals for each row
execute function procurement.po_approvals_rollup ();

----------------------------------------------------------------
-- Goods receipts
--
-- The guard trigger on the lines below is the "receipt cannot exceed
-- order" rule: it computes what is still outstanding on the order
-- line at the moment of the write and refuses anything past it.
----------------------------------------------------------------
create sequence if not exists procurement.receipt_number_seq;

create table procurement.goods_receipts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  receipt_number varchar(30) not null unique default (
    'GRN-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('procurement.receipt_number_seq')::text,
      6,
      '0'
    )
  ),
  purchase_order_id uuid not null references procurement.purchase_orders (id) on delete restrict,
  received_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  received_on date not null default current_date,
  status procurement.receipt_status not null default 'draft',
  delivery_note_reference varchar(60),
  carrier varchar(120),
  line_count integer not null default 0,
  total_accepted_value numeric(14, 2) not null default 0,
  total_rejected_value numeric(14, 2) not null default 0,
  document supasheet.file,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column procurement.goods_receipts.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "posted": {"variant": "success", "icon": "PackageCheck"},
        "disputed": {"variant": "destructive", "icon": "TriangleAlert"}
    }
}';

comment on table procurement.goods_receipts is '{
    "icon": "PackageCheck",
    "name": "Goods Receipts",
    "description": "What actually turned up against an order, and how much of it was in good shape.",
    "collapsible_group": "Ordering",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "receipt_number", "badges": ["status", "total_accepted_value"]},
        "tabs": ["goods_receipt_lines"]
    },
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "receipt_number", "description": "delivery_note_reference", "date": "received_on", "badge": "total_accepted_value"},
        {"id": "calendar", "name": "Receiving Calendar", "type": "calendar", "title": "receipt_number", "badge": "status", "start_date": "received_on", "read_only": true},
        {"id": "list", "name": "All Receipts", "type": "list", "title": "receipt_number", "description": "carrier", "field_1": "status", "field_2": "total_accepted_value"}
    ],
    "filter_presets": [
        {"id": "with_rejections", "name": "With Rejections", "filters": [{"id": "total_rejected_value", "value": "0", "operator": "gt"}]},
        {"id": "disputed", "name": "Disputed", "filters": [{"id": "status", "value": "disputed", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["purchase_order_id", "received_on", "delivery_note_reference"],
        "sections": [
            {"id": "receipt", "title": "Receipt", "fields": {"create": ["purchase_order_id", "received_on", "delivery_note_reference", "carrier"], "update": ["status", "delivery_note_reference", "carrier"], "read": ["purchase_order_id", "received_by", "received_on", "delivery_note_reference", "carrier", "status"]}},
            {"id": "totals", "title": "Totals", "fields": {"read": ["line_count", "total_accepted_value", "total_rejected_value"]}},
            {"id": "extras", "title": "Document & Notes", "collapsible": true, "fields": ["document", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "received_on", "desc": true}],
        "join": [
            {"table": "purchase_orders", "on": "purchase_order_id", "columns": ["po_number", "status"]},
            {"table": "users", "on": "received_by", "alias": "receiver", "columns": ["name", "email"]}
        ]
    }
}';

comment on column procurement.goods_receipts.total_accepted_value is '{"name": "Accepted", "aggregate": "sum"}';

comment on column procurement.goods_receipts.total_rejected_value is '{"name": "Rejected", "aggregate": "sum"}';

comment on column procurement.goods_receipts.document is '{"accept": ".pdf,.png,.jpg", "maxFiles": 5, "maxSize": 10485760}';

revoke all on table procurement.goods_receipts
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
delete on table procurement.goods_receipts to "x-admin",
"buyer";

grant
select
  on table procurement.goods_receipts to "approver";

revoke all on sequence procurement.receipt_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence procurement.receipt_number_seq to "x-admin",
"buyer";

create index idx_proc_receipts_po_id on procurement.goods_receipts (purchase_order_id);

create index idx_proc_receipts_status on procurement.goods_receipts (status);

alter table procurement.goods_receipts enable row level security;

create policy receipts_select on procurement.goods_receipts for
select
  to authenticated using (true);

create policy receipts_insert on procurement.goods_receipts for insert to authenticated
with
  check (true);

create policy receipts_update on procurement.goods_receipts
for update
  to authenticated using (true)
with
  check (true);

create policy receipts_delete on procurement.goods_receipts for delete to authenticated using (true);

----------------------------------------------------------------
-- Goods receipt lines
----------------------------------------------------------------
create table procurement.goods_receipt_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  receipt_id uuid not null references procurement.goods_receipts (id) on delete cascade,
  po_line_id uuid not null references procurement.purchase_order_lines (id) on delete restrict,
  quantity_received numeric(12, 3) not null default 0,
  quantity_accepted numeric(12, 3) not null default 0,
  quantity_rejected numeric(12, 3) not null default 0,
  condition procurement.receipt_line_condition not null default 'accepted',
  rejection_reason varchar(300),
  lot_or_batch varchar(60),
  notes varchar(300),
  created_at timestamptz default current_timestamp,
  constraint receipt_lines_quantities_non_negative check (
    quantity_received >= 0
    and quantity_accepted >= 0
    and quantity_rejected >= 0
  ),
  constraint receipt_lines_split_matches_received check (quantity_accepted + quantity_rejected = quantity_received)
);

comment on column procurement.goods_receipt_lines.condition is '{
    "progress": false,
    "values": {
        "accepted": {"variant": "success", "icon": "CircleCheck"},
        "damaged": {"variant": "warning", "icon": "PackageX"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "short": {"variant": "warning", "icon": "TrendingDown"},
        "over": {"variant": "info", "icon": "TrendingUp"}
    }
}';

comment on table procurement.goods_receipt_lines is '{
    "icon": "Rows3",
    "name": "Receipt Lines",
    "description": "What arrived against one order line, split into accepted and rejected quantities.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["receipt_id", "po_line_id", "lot_or_batch"]},
            {"id": "quantities", "title": "Quantities", "fields": ["quantity_received", "quantity_accepted", "quantity_rejected", "condition"]},
            {"id": "detail", "title": "Detail", "fields": ["rejection_reason", "notes"]}
        ],
        "behavior": {
            "rejection_reason": {"visible": [{"id": "quantity_rejected", "operator": "gt", "value": "0"}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [
            {"table": "goods_receipts", "on": "receipt_id", "columns": ["receipt_number", "status"]},
            {"table": "purchase_order_lines", "on": "po_line_id", "columns": ["description", "quantity_ordered", "unit_price"]}
        ]
    }
}';

revoke all on table procurement.goods_receipt_lines
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
delete on table procurement.goods_receipt_lines to "x-admin",
"buyer";

grant
select
  on table procurement.goods_receipt_lines to "approver";

create index idx_proc_receipt_lines_receipt_id on procurement.goods_receipt_lines (receipt_id);

create index idx_proc_receipt_lines_po_line_id on procurement.goods_receipt_lines (po_line_id);

alter table procurement.goods_receipt_lines enable row level security;

create policy receipt_lines_select on procurement.goods_receipt_lines for
select
  to authenticated using (true);

create policy receipt_lines_insert on procurement.goods_receipt_lines for insert to authenticated
with
  check (true);

create policy receipt_lines_update on procurement.goods_receipt_lines
for update
  to authenticated using (true)
with
  check (true);

create policy receipt_lines_delete on procurement.goods_receipt_lines for delete to authenticated using (true);

create or replace function procurement.goods_receipt_lines_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_ordered numeric(12, 3);
  v_already_received numeric(12, 3);
  v_previous numeric(12, 3) := 0;
  v_remaining numeric(12, 3);
begin
  select quantity_ordered, quantity_received into v_ordered, v_already_received
  from procurement.purchase_order_lines
  where id = new.po_line_id;

  if tg_op = 'UPDATE' then
    v_previous := old.quantity_received;
  end if;

  v_remaining := v_ordered - (v_already_received - v_previous);

  if new.quantity_received > v_remaining then
    raise exception 'Only % is still outstanding on this order line, but % was entered.', v_remaining, new.quantity_received
      using hint = 'Raise a new order line for the overage instead of over-receiving this one.';
  end if;

  return new;
end;
$$;

create trigger trg_goods_receipt_lines_guard before insert
or
update of quantity_received,
quantity_accepted,
quantity_rejected,
po_line_id on procurement.goods_receipt_lines for each row
execute function procurement.goods_receipt_lines_guard ();

create or replace function procurement.goods_receipt_lines_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_receipt_id uuid := coalesce(new.receipt_id, old.receipt_id);
  v_po_line_id uuid := coalesce(new.po_line_id, old.po_line_id);
  v_po_id uuid;
begin
  update procurement.goods_receipts gr
  set line_count = x.n,
    total_accepted_value = x.accepted_value,
    total_rejected_value = x.rejected_value,
    updated_at = current_timestamp
  from (
    select
      count(*) as n,
      coalesce(sum(grl.quantity_accepted * pol.unit_price), 0) as accepted_value,
      coalesce(sum(grl.quantity_rejected * pol.unit_price), 0) as rejected_value
    from procurement.goods_receipt_lines grl
      join procurement.purchase_order_lines pol on pol.id = grl.po_line_id
    where grl.receipt_id = v_receipt_id
  ) x
  where gr.id = v_receipt_id;

  update procurement.purchase_order_lines pol
  set quantity_received = coalesce(
    (
      select
        sum(grl.quantity_received)
      from
        procurement.goods_receipt_lines grl
      where
        grl.po_line_id = v_po_line_id
    ),
    0
  )
  where
    pol.id = v_po_line_id;

  select po_id into v_po_id
  from procurement.purchase_order_lines
  where id = v_po_line_id;

  update procurement.purchase_orders po
  set received_value = x.received_value,
    status = case
      when x.fully_received
      and po.status in ('sent', 'acknowledged', 'partially_received') then 'received'::procurement.po_status
      when x.any_received
      and po.status in ('sent', 'acknowledged') then 'partially_received'::procurement.po_status
      else po.status
    end
  from (
    select
      coalesce(sum(quantity_received * unit_price), 0) as received_value,
      bool_and(quantity_received >= quantity_ordered) as fully_received,
      bool_or(quantity_received > 0) as any_received
    from procurement.purchase_order_lines
    where po_id = v_po_id
  ) x
  where po.id = v_po_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_goods_receipt_lines_rollup
after insert
or delete
or
update on procurement.goods_receipt_lines for each row
execute function procurement.goods_receipt_lines_rollup ();

----------------------------------------------------------------
-- Vendor invoices — reconciled by three-way match
--
-- Every line records its own variance against the order (price) and
-- against what was actually received (quantity) the moment it is
-- written — see the BEFORE trigger. The AFTER trigger rolls those
-- per-line flags up into the invoice's match_status, and the guard
-- on the invoice itself refuses to move to 'approved' while that
-- status is anything but 'matched', unless x-admin overrides it.
----------------------------------------------------------------
create sequence if not exists procurement.invoice_reference_seq;

create table procurement.vendor_invoices (
  id uuid primary key default extensions.uuid_generate_v4 (),
  internal_reference varchar(30) not null unique default (
    'INV-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('procurement.invoice_reference_seq')::text,
      6,
      '0'
    )
  ),
  supplier_invoice_number varchar(60) not null,
  purchase_order_id uuid not null references procurement.purchase_orders (id) on delete restrict,
  supplier_id uuid not null references procurement.suppliers (id) on delete restrict,
  status procurement.invoice_status not null default 'draft',
  match_status procurement.match_status not null default 'not_matched',
  invoice_date date not null default current_date,
  due_date date not null default (current_date + 30),
  currency varchar(3) not null default 'USD',
  subtotal numeric(14, 2) not null default 0,
  tax_total numeric(14, 2) not null default 0,
  total numeric(14, 2) not null default 0,
  tolerance_percent supasheet.PERCENTAGE not null default 2,
  variance_amount numeric(14, 2) not null default 0,
  matched_amount numeric(14, 2) not null default 0,
  paid_total numeric(14, 2) not null default 0,
  balance_due numeric(14, 2) not null default 0,
  approved_by uuid references supasheet.users (id) on delete set null,
  approved_at timestamptz,
  document supasheet.file,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (supplier_id, supplier_invoice_number),
  constraint invoices_dates_ordered check (due_date >= invoice_date),
  constraint invoices_totals_non_negative check (
    subtotal >= 0
    and tax_total >= 0
    and total >= 0
    and paid_total >= 0
  )
);

comment on column procurement.vendor_invoices.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "pending_match": {"variant": "info", "icon": "GitCompare"},
        "matched": {"variant": "success", "icon": "CircleCheck"},
        "discrepancy": {"variant": "destructive", "icon": "TriangleAlert"},
        "approved": {"variant": "success", "icon": "BadgeCheck"},
        "disputed": {"variant": "destructive", "icon": "Flag"},
        "paid": {"variant": "success", "icon": "BadgeDollarSign"},
        "void": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on column procurement.vendor_invoices.match_status is '{
    "progress": false,
    "values": {
        "not_matched": {"variant": "secondary", "icon": "CircleDashed"},
        "matched": {"variant": "success", "icon": "CircleCheck"},
        "over_tolerance": {"variant": "destructive", "icon": "TrendingUp"},
        "under_tolerance": {"variant": "warning", "icon": "TrendingDown"}
    }
}';

comment on table procurement.vendor_invoices is '{
    "icon": "Receipt",
    "name": "Vendor Invoices",
    "description": "What we were billed, reconciled against what we ordered and what actually arrived.",
    "collapsible_group": "Financials",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "internal_reference", "badges": ["status", "match_status", "balance_due"]},
        "tabs": ["vendor_invoice_lines", "invoice_payments"]
    },
    "views": [
        {"id": "kanban", "name": "Matching Board", "type": "kanban", "group": "status", "title": "internal_reference", "description": "supplier_invoice_number", "date": "due_date", "badge": "match_status"},
        {"id": "calendar", "name": "Due Dates", "type": "calendar", "title": "internal_reference", "badge": "status", "start_date": "invoice_date", "end_date": "due_date"},
        {"id": "list", "name": "All Invoices", "type": "list", "title": "internal_reference", "description": "supplier_invoice_number", "field_1": "status", "field_2": "balance_due"}
    ],
    "filter_presets": [
        {"id": "discrepancies", "name": "Discrepancies", "filters": [{"id": "match_status", "value": ["over_tolerance", "under_tolerance"], "operator": "in"}]},
        {"id": "unpaid", "name": "Unpaid", "filters": [{"id": "status", "value": ["approved", "matched"], "operator": "in"}]},
        {"id": "overdue", "name": "Overdue", "filters": [{"id": "due_date", "value": "today", "operator": "lt"}, {"id": "status", "value": "paid", "operator": "neq"}]}
    ],
    "fields": {
        "quick_create": ["purchase_order_id", "supplier_invoice_number", "invoice_date", "document"],
        "sections": [
            {"id": "invoice", "title": "Invoice", "fields": {"create": ["purchase_order_id", "supplier_id", "supplier_invoice_number", "invoice_date", "due_date", "currency", "tolerance_percent", "document"], "update": ["due_date", "status", "tolerance_percent", "document"], "read": ["purchase_order_id", "supplier_id", "supplier_invoice_number", "invoice_date", "due_date", "currency", "status"]}},
            {"id": "match", "title": "Match", "fields": {"read": ["match_status", "tolerance_percent", "variance_amount", "matched_amount"]}},
            {"id": "totals", "title": "Totals", "fields": {"read": ["subtotal", "tax_total", "total", "paid_total", "balance_due"]}},
            {"id": "approval", "title": "Approval", "fields": {"read": ["approved_by", "approved_at"]}},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ],
        "lookups": {
            "purchase_order_id": {"fill": [{"source_column": "supplier_id", "target_column": "supplier_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "invoice_date", "desc": true}],
        "join": [
            {"table": "purchase_orders", "on": "purchase_order_id", "columns": ["po_number", "status", "total"]},
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name"]},
            {"table": "users", "on": "approved_by", "alias": "approver", "columns": ["name", "email"]}
        ]
    }
}';

comment on column procurement.vendor_invoices.total is '{"aggregate": "sum"}';

comment on column procurement.vendor_invoices.balance_due is '{"name": "Balance", "aggregate": "sum"}';

comment on column procurement.vendor_invoices.document is '{"accept": ".pdf", "maxFiles": 2, "maxSize": 10485760}';

revoke all on table procurement.vendor_invoices
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
delete on table procurement.vendor_invoices to "x-admin";

grant
select
,
  insert,
update on table procurement.vendor_invoices to "buyer";

grant
select
  on table procurement.vendor_invoices to "approver";

revoke all on sequence procurement.invoice_reference_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence procurement.invoice_reference_seq to "x-admin",
"buyer";

create index idx_proc_invoices_po_id on procurement.vendor_invoices (purchase_order_id);

create index idx_proc_invoices_supplier_id on procurement.vendor_invoices (supplier_id);

create index idx_proc_invoices_status on procurement.vendor_invoices (status);

create index idx_proc_invoices_match_status on procurement.vendor_invoices (match_status);

alter table procurement.vendor_invoices enable row level security;

create policy invoices_select on procurement.vendor_invoices for
select
  to authenticated using (true);

create policy invoices_insert on procurement.vendor_invoices for insert to authenticated
with
  check (true);

create policy invoices_update on procurement.vendor_invoices
for update
  to authenticated using (true)
with
  check (true);

create policy invoices_delete on procurement.vendor_invoices for delete to authenticated using (true);

create or replace function procurement.vendor_invoices_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if new.status = 'approved' and old.status <> 'approved' then
    -- security definer swaps current_user for this function's owner, so
    -- pg_has_role(current_user, ...) would always see the owner's roles,
    -- not the caller's — read the caller's role from the JWT claim instead.
    if new.match_status <> 'matched' and not pg_has_role ((select auth.jwt () ->> 'role'), 'x-admin', 'member') then
      raise exception 'This invoice has a % three-way match and cannot be approved.', new.match_status
        using hint = 'Resolve the variance, or have x-admin override it.';
    end if;

    new.approved_by := (select auth.uid ());
    new.approved_at := current_timestamp;
  end if;

  return new;
end;
$$;

create trigger trg_vendor_invoices_guard before
update of status on procurement.vendor_invoices for each row
execute function procurement.vendor_invoices_guard ();

----------------------------------------------------------------
-- Vendor invoice lines
----------------------------------------------------------------
create table procurement.vendor_invoice_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  invoice_id uuid not null references procurement.vendor_invoices (id) on delete cascade,
  po_line_id uuid not null references procurement.purchase_order_lines (id) on delete restrict,
  description varchar(300) not null,
  quantity_invoiced numeric(12, 3) not null default 1,
  unit_price numeric(14, 4) not null default 0,
  tax_amount numeric(14, 2) not null default 0,
  line_total numeric(14, 2) not null default 0,
  quantity_variance numeric(12, 3) not null default 0,
  price_variance numeric(14, 4) not null default 0,
  is_over_tolerance boolean not null default false,
  is_under_tolerance boolean not null default false,
  created_at timestamptz default current_timestamp,
  constraint invoice_lines_quantity_positive check (quantity_invoiced > 0),
  constraint invoice_lines_price_non_negative check (unit_price >= 0)
);

comment on table procurement.vendor_invoice_lines is '{
    "icon": "Rows3",
    "name": "Invoice Lines",
    "description": "Billed quantity and price, and how far each sits from what was ordered and received.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["invoice_id", "po_line_id", "description"]},
            {"id": "billed", "title": "Billed", "fields": ["quantity_invoiced", "unit_price", "tax_amount"]},
            {"id": "variance", "title": "Variance", "fields": {"read": ["line_total", "quantity_variance", "price_variance", "is_over_tolerance", "is_under_tolerance"]}}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [
            {"table": "vendor_invoices", "on": "invoice_id", "columns": ["internal_reference", "status"]},
            {"table": "purchase_order_lines", "on": "po_line_id", "columns": ["description", "quantity_ordered", "unit_price", "quantity_received"]}
        ]
    }
}';

comment on column procurement.vendor_invoice_lines.line_total is '{"aggregate": "sum"}';

revoke all on table procurement.vendor_invoice_lines
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
delete on table procurement.vendor_invoice_lines to "x-admin",
"buyer";

grant
select
  on table procurement.vendor_invoice_lines to "approver";

create index idx_proc_invoice_lines_invoice_id on procurement.vendor_invoice_lines (invoice_id);

create index idx_proc_invoice_lines_po_line_id on procurement.vendor_invoice_lines (po_line_id);

alter table procurement.vendor_invoice_lines enable row level security;

create policy invoice_lines_select on procurement.vendor_invoice_lines for
select
  to authenticated using (true);

create policy invoice_lines_insert on procurement.vendor_invoice_lines for insert to authenticated
with
  check (true);

create policy invoice_lines_update on procurement.vendor_invoice_lines
for update
  to authenticated using (true)
with
  check (true);

create policy invoice_lines_delete on procurement.vendor_invoice_lines for delete to authenticated using (true);

create or replace function procurement.vendor_invoice_lines_match () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_received numeric(12, 3);
  v_po_price numeric(14, 4);
  v_tolerance supasheet.PERCENTAGE;
  v_qty_variance_pct numeric;
  v_price_variance_pct numeric;
begin
  select quantity_received, unit_price into v_received, v_po_price
  from procurement.purchase_order_lines
  where id = new.po_line_id;

  select tolerance_percent into v_tolerance
  from procurement.vendor_invoices
  where id = new.invoice_id;

  v_tolerance := coalesce(v_tolerance, 0);

  new.line_total := round(new.quantity_invoiced * new.unit_price, 2) + coalesce(new.tax_amount, 0);
  new.quantity_variance := new.quantity_invoiced - coalesce(v_received, 0);
  new.price_variance := new.unit_price - coalesce(v_po_price, 0);

  v_qty_variance_pct := abs(new.quantity_variance) / nullif(v_received, 0) * 100;
  v_price_variance_pct := abs(new.price_variance) / nullif(v_po_price, 0) * 100;

  new.is_over_tolerance := (
    new.quantity_variance > 0
    and coalesce(v_qty_variance_pct, 100) > v_tolerance
  )
  or (
    new.price_variance > 0
    and coalesce(v_price_variance_pct, 100) > v_tolerance
  );

  new.is_under_tolerance := (
    new.quantity_variance < 0
    and coalesce(v_qty_variance_pct, 100) > v_tolerance
  )
  or (
    new.price_variance < 0
    and coalesce(v_price_variance_pct, 100) > v_tolerance
  );

  return new;
end;
$$;

create trigger trg_vendor_invoice_lines_match before insert
or
update on procurement.vendor_invoice_lines for each row
execute function procurement.vendor_invoice_lines_match ();

create or replace function procurement.vendor_invoice_lines_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_invoice_id uuid := coalesce(new.invoice_id, old.invoice_id);
begin
  update procurement.vendor_invoices vi
  set subtotal = x.subtotal,
    tax_total = x.tax_total,
    total = x.total,
    variance_amount = x.variance_amount,
    matched_amount = x.total - x.variance_amount,
    balance_due = x.total - vi.paid_total,
    match_status = case
      when x.n = 0 then 'not_matched'::procurement.match_status
      when x.over_tolerance then 'over_tolerance'::procurement.match_status
      when x.under_tolerance then 'under_tolerance'::procurement.match_status
      else 'matched'::procurement.match_status
    end,
    status = case
      when vi.status not in (
        'draft', 'pending_match', 'matched', 'discrepancy'
      ) then vi.status
      when x.n = 0 then 'draft'::procurement.invoice_status
      when x.over_tolerance
      or x.under_tolerance then 'discrepancy'::procurement.invoice_status
      else 'matched'::procurement.invoice_status
    end,
    updated_at = current_timestamp
  from (
    select
      count(*) as n,
      coalesce(sum(quantity_invoiced * unit_price), 0) as subtotal,
      coalesce(sum(tax_amount), 0) as tax_total,
      coalesce(sum(line_total), 0) as total,
      coalesce(
        sum(
          abs(quantity_variance) * unit_price + abs(price_variance) * quantity_invoiced
        ),
        0
      ) as variance_amount,
      bool_or(is_over_tolerance) as over_tolerance,
      bool_or(is_under_tolerance) as under_tolerance
    from procurement.vendor_invoice_lines
    where invoice_id = v_invoice_id
  ) x
  where vi.id = v_invoice_id;

  update procurement.purchase_order_lines pol
  set quantity_invoiced = coalesce(
    (
      select
        sum(vil.quantity_invoiced)
      from
        procurement.vendor_invoice_lines vil
      where
        vil.po_line_id = pol.id
    ),
    0
  )
  where pol.id = coalesce(new.po_line_id, old.po_line_id);

  update procurement.purchase_orders po
  set invoiced_value = coalesce(
    (
      select
        sum(quantity_invoiced * unit_price)
      from
        procurement.purchase_order_lines
      where
        po_id = po.id
    ),
    0
  )
  where po.id = (
    select
      po_id
    from
      procurement.purchase_order_lines
    where
      id = coalesce(new.po_line_id, old.po_line_id)
  );

  return coalesce(new, old);
end;
$$;

create trigger trg_vendor_invoice_lines_rollup
after insert
or delete
or
update on procurement.vendor_invoice_lines for each row
execute function procurement.vendor_invoice_lines_rollup ();

----------------------------------------------------------------
-- Invoice payments
----------------------------------------------------------------
create table procurement.invoice_payments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  invoice_id uuid not null references procurement.vendor_invoices (id) on delete cascade,
  payment_date date not null default current_date,
  amount numeric(14, 2) not null,
  method procurement.payment_method not null default 'bank_transfer',
  reference varchar(80),
  notes varchar(300),
  recorded_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  constraint invoice_payments_amount_positive check (amount > 0)
);

comment on column procurement.invoice_payments.method is '{
    "progress": false,
    "values": {
        "bank_transfer": {"variant": "success", "icon": "Landmark"},
        "card": {"variant": "info", "icon": "CreditCard"},
        "cheque": {"variant": "secondary", "icon": "FileText"},
        "cash": {"variant": "default", "icon": "Banknote"},
        "other": {"variant": "secondary", "icon": "CircleDollarSign"}
    }
}';

comment on table procurement.invoice_payments is '{
    "icon": "BadgeDollarSign",
    "name": "Payments",
    "description": "Money actually sent against an invoice.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "payment", "title": "Payment", "fields": ["invoice_id", "payment_date", "amount", "method", "reference"]},
            {"id": "notes", "title": "Notes", "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "payment_date", "desc": true}],
        "join": [
            {"table": "vendor_invoices", "on": "invoice_id", "columns": ["internal_reference", "status", "balance_due"]},
            {"table": "users", "on": "recorded_by", "alias": "recorder", "columns": ["name", "email"]}
        ]
    }
}';

comment on column procurement.invoice_payments.amount is '{"aggregate": "sum"}';

revoke all on table procurement.invoice_payments
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
delete on table procurement.invoice_payments to "x-admin";

grant
select
,
  insert on table procurement.invoice_payments to "buyer";

grant
select
  on table procurement.invoice_payments to "approver";

create index idx_proc_invoice_payments_invoice_id on procurement.invoice_payments (invoice_id);

alter table procurement.invoice_payments enable row level security;

create policy invoice_payments_select on procurement.invoice_payments for
select
  to authenticated using (true);

create policy invoice_payments_insert on procurement.invoice_payments for insert to authenticated
with
  check (true);

create policy invoice_payments_update on procurement.invoice_payments
for update
  to authenticated using (true)
with
  check (true);

create policy invoice_payments_delete on procurement.invoice_payments for delete to authenticated using (true);

create or replace function procurement.invoice_payments_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_invoice_id uuid := coalesce(new.invoice_id, old.invoice_id);
begin
  update procurement.vendor_invoices vi
  set paid_total = x.paid,
    balance_due = vi.total - x.paid,
    status = case
      when x.paid >= vi.total
      and vi.total > 0 then 'paid'::procurement.invoice_status
      else vi.status
    end,
    updated_at = current_timestamp
  from (
    select coalesce(sum(amount), 0) as paid
    from procurement.invoice_payments
    where invoice_id = v_invoice_id
  ) x
  where vi.id = v_invoice_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_invoice_payments_rollup
after insert
or delete
or
update on procurement.invoice_payments for each row
execute function procurement.invoice_payments_rollup ();

----------------------------------------------------------------
-- Purchase order events (trigger-populated timeline)
----------------------------------------------------------------
create table procurement.purchase_order_events (
  id uuid primary key default extensions.uuid_generate_v4 (),
  po_id uuid not null references procurement.purchase_orders (id) on delete cascade,
  event_type procurement.po_event_type not null,
  title varchar(255) not null,
  metadata jsonb,
  actor_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  occurred_at timestamptz not null default current_timestamp
);

comment on column procurement.purchase_order_events.event_type is '{
    "progress": false,
    "values": {
        "created": {"variant": "info", "icon": "Sparkles"},
        "submitted": {"variant": "warning", "icon": "Send"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "sent": {"variant": "info", "icon": "Mail"},
        "acknowledged": {"variant": "info", "icon": "MailCheck"},
        "received": {"variant": "success", "icon": "PackageCheck"},
        "invoiced": {"variant": "default", "icon": "Receipt"},
        "closed": {"variant": "secondary", "icon": "Archive"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table procurement.purchase_order_events is '{
    "icon": "History",
    "name": "Order History",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "event", "title": "Event", "fields": ["po_id", "event_type", "title", "metadata", "actor_id", "occurred_at"]}
        ]
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [{"table": "users", "on": "actor_id", "alias": "actor", "columns": ["name", "email"]}]
    }
}';

revoke all on table procurement.purchase_order_events
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on table procurement.purchase_order_events to "x-admin",
  "buyer",
  "approver";

create index idx_proc_po_events_po_id on procurement.purchase_order_events (po_id);

create index idx_proc_po_events_occurred_at on procurement.purchase_order_events (occurred_at desc);

alter table procurement.purchase_order_events enable row level security;

create policy po_events_select on procurement.purchase_order_events for
select
  to authenticated using (true);

create or replace function procurement.purchase_orders_log_event () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_title varchar(255);
  v_event procurement.po_event_type;
begin
  if tg_op = 'INSERT' then
    v_event := 'created';
    v_title := 'Order created';
  elsif new.status is distinct from old.status then
    v_event := case new.status
      when 'pending_approval' then 'submitted'
      when 'approved' then 'approved'
      when 'cancelled' then 'rejected'
      when 'sent' then 'sent'
      when 'acknowledged' then 'acknowledged'
      when 'partially_received' then 'received'
      when 'received' then 'received'
      when 'invoiced' then 'invoiced'
      when 'closed' then 'closed'
      else null
    end;
    v_title := 'Status changed to ' || new.status;
  else
    return new;
  end if;

  if v_event is null then
    return new;
  end if;

  insert into procurement.purchase_order_events (po_id, event_type, title, actor_id)
  values (new.id, v_event, v_title, (select auth.uid ()));

  return new;
end;
$$;

create trigger trg_po_log_event
after insert
or
update of status on procurement.purchase_orders for each row
execute function procurement.purchase_orders_log_event ();

----------------------------------------------------------------
-- Purchase order / contract / supplier / department / category
-- rollups, all driven from one order-level trigger
----------------------------------------------------------------
create or replace function procurement.purchase_orders_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_supplier_id uuid;
  v_contract_id uuid;
  v_department_id uuid;
  v_category_id uuid;
begin
  for v_supplier_id in
    select distinct v from unnest(array[new.supplier_id, old.supplier_id]) as t (v)
    where v is not null
  loop
    update procurement.suppliers s
    set total_spend = x.total_spend,
      open_po_value = x.open_value
    from (
      select
        coalesce(sum(total) filter (where status <> 'cancelled'), 0) as total_spend,
        coalesce(sum(total) filter (where status not in ('cancelled', 'closed', 'invoiced')), 0) as open_value
      from procurement.purchase_orders
      where supplier_id = v_supplier_id
    ) x
    where s.id = v_supplier_id;
  end loop;

  for v_contract_id in
    select distinct v from unnest(array[new.contract_id, old.contract_id]) as t (v)
    where v is not null
  loop
    update procurement.contracts c
    set consumed_amount = x.consumed
    from (
      select coalesce(sum(total), 0) as consumed
      from procurement.purchase_orders
      where contract_id = v_contract_id
        and status <> 'cancelled'
    ) x
    where c.id = v_contract_id;

    update procurement.suppliers s
    set open_contract_value = coalesce(
      (
        select sum(ceiling_amount - consumed_amount)
        from procurement.contracts
        where supplier_id = s.id
          and status = 'active'
      ),
      0
    )
    where s.id = (
      select supplier_id
      from procurement.contracts
      where id = v_contract_id
    );
  end loop;

  for v_department_id in
    select distinct v from unnest(array[new.department_id, old.department_id]) as t (v)
    where v is not null
  loop
    update procurement.departments d
    set committed_spend = x.committed,
      actual_spend = x.actual
    from (
      select
        coalesce(
          (
            select sum(estimated_total)
            from procurement.purchase_requisitions
            where department_id = v_department_id
              and status in ('submitted', 'pending_approval', 'approved')
          ), 0
        )
        + coalesce(
          (
            select sum(total)
            from procurement.purchase_orders
            where department_id = v_department_id
              and status <> 'cancelled'
          ), 0
        ) as committed,
        coalesce(
          (
            select sum(invoiced_value)
            from procurement.purchase_orders
            where department_id = v_department_id
          ), 0
        ) as actual
    ) x
    where d.id = v_department_id;
  end loop;

  for v_category_id in
    select distinct v from unnest(array[new.category_id, old.category_id]) as t (v)
    where v is not null
  loop
    update procurement.categories cat
    set spend_total = x.spend
    from (
      select coalesce(sum(total), 0) as spend
      from procurement.purchase_orders
      where category_id = v_category_id
        and status <> 'cancelled'
    ) x
    where cat.id = v_category_id;
  end loop;

  return coalesce(new, old);
end;
$$;

create trigger trg_purchase_orders_rollup
after insert
or delete
or
update of supplier_id,
contract_id,
department_id,
category_id,
total,
status,
invoiced_value on procurement.purchase_orders for each row
execute function procurement.purchase_orders_rollup ();

----------------------------------------------------------------
-- Supplier performance reviews
----------------------------------------------------------------
create table procurement.supplier_performance_reviews (
  id uuid primary key default extensions.uuid_generate_v4 (),
  supplier_id uuid not null references procurement.suppliers (id) on delete cascade,
  reviewed_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  review_period varchar(20) not null,
  period_start date,
  period_end date,
  on_time_delivery_rate supasheet.PERCENTAGE,
  quality_score supasheet.RATING,
  responsiveness_score supasheet.RATING,
  cost_competitiveness supasheet.RATING,
  overall_rating supasheet.RATING,
  comments supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  unique (supplier_id, review_period)
);

comment on table procurement.supplier_performance_reviews is '{
    "icon": "Star",
    "name": "Performance Reviews",
    "description": "Periodic scorecards — delivery, quality, responsiveness and cost, rolled into a rating on the supplier itself.",
    "collapsible_group": "Sourcing",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "review_period", "badges": ["overall_rating"]}},
    "views": [
        {"id": "list", "name": "All Reviews", "type": "list", "title": "review_period", "description": "comments", "field_1": "overall_rating", "field_2": "on_time_delivery_rate"},
        {"id": "calendar", "name": "Review Calendar", "type": "calendar", "title": "review_period", "badge": "overall_rating", "start_date": "period_start", "end_date": "period_end", "read_only": true}
    ],
    "fields": {
        "quick_create": ["supplier_id", "review_period"],
        "sections": [
            {"id": "review", "title": "Review", "fields": ["supplier_id", "review_period", "period_start", "period_end"]},
            {"id": "scores", "title": "Scores", "fields": ["on_time_delivery_rate", "quality_score", "responsiveness_score", "cost_competitiveness"]},
            {"id": "outcome", "title": "Outcome", "fields": {"read": ["overall_rating"]}},
            {"id": "extras", "title": "Comments", "collapsible": true, "fields": ["comments"]}
        ]
    },
    "query": {
        "sort": [{"id": "period_start", "desc": true}],
        "join": [
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name"]},
            {"table": "users", "on": "reviewed_by", "alias": "reviewer", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table procurement.supplier_performance_reviews
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
delete on table procurement.supplier_performance_reviews to "x-admin",
"buyer";

grant
select
  on table procurement.supplier_performance_reviews to "approver";

create index idx_proc_reviews_supplier_id on procurement.supplier_performance_reviews (supplier_id);

alter table procurement.supplier_performance_reviews enable row level security;

create policy reviews_select on procurement.supplier_performance_reviews for
select
  to authenticated using (true);

create policy reviews_insert on procurement.supplier_performance_reviews for insert to authenticated
with
  check (true);

create policy reviews_update on procurement.supplier_performance_reviews
for update
  to authenticated using (true)
with
  check (true);

create policy reviews_delete on procurement.supplier_performance_reviews for delete to authenticated using (true);

create or replace function procurement.supplier_reviews_set_overall () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  new.overall_rating := round(
    (
      coalesce(new.quality_score, 0) + coalesce(new.responsiveness_score, 0) + coalesce(new.cost_competitiveness, 0)
    )::numeric / nullif(
      (case when new.quality_score is not null then 1 else 0 end)
      + (case when new.responsiveness_score is not null then 1 else 0 end)
      + (case when new.cost_competitiveness is not null then 1 else 0 end),
      0
    ),
    2
  );
  return new;
end;
$$;

create trigger trg_supplier_reviews_set_overall before insert
or
update on procurement.supplier_performance_reviews for each row
execute function procurement.supplier_reviews_set_overall ();

create or replace function procurement.supplier_reviews_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_supplier_id uuid := coalesce(new.supplier_id, old.supplier_id);
begin
  update procurement.suppliers s
  set on_time_delivery_rate = x.on_time,
    quality_score = x.quality,
    responsiveness_score = x.responsiveness,
    overall_rating = x.overall
  from (
    select
      avg(on_time_delivery_rate) as on_time,
      avg(quality_score) as quality,
      avg(responsiveness_score) as responsiveness,
      avg(overall_rating) as overall
    from procurement.supplier_performance_reviews
    where supplier_id = v_supplier_id
  ) x
  where s.id = v_supplier_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_supplier_reviews_rollup
after insert
or delete
or
update on procurement.supplier_performance_reviews for each row
execute function procurement.supplier_reviews_rollup ();

----------------------------------------------------------------
-- Cost savings tracking
----------------------------------------------------------------
create table procurement.cost_savings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  category_id uuid references procurement.categories (id) on delete set null,
  supplier_id uuid references procurement.suppliers (id) on delete set null,
  contract_id uuid references procurement.contracts (id) on delete set null,
  po_id uuid references procurement.purchase_orders (id) on delete set null,
  savings_type procurement.savings_type not null default 'hard_savings',
  baseline_amount numeric(14, 2) not null default 0,
  negotiated_amount numeric(14, 2) not null default 0,
  savings_amount numeric(14, 2) not null default 0,
  currency varchar(3) not null default 'USD',
  realized boolean not null default false,
  recorded_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  recorded_on date not null default current_date,
  notes varchar(500),
  created_at timestamptz default current_timestamp,
  constraint cost_savings_amounts_non_negative check (
    baseline_amount >= 0
    and negotiated_amount >= 0
  )
);

comment on column procurement.cost_savings.savings_type is '{
    "progress": false,
    "values": {
        "hard_savings": {"variant": "success", "icon": "PiggyBank"},
        "cost_avoidance": {"variant": "info", "icon": "ShieldCheck"},
        "rebate": {"variant": "default", "icon": "Undo2"}
    }
}';

comment on table procurement.cost_savings is '{
    "icon": "PiggyBank",
    "name": "Cost Savings",
    "description": "What negotiating actually bought — baseline versus what we settled on.",
    "collapsible_group": "Financials",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "savings_type", "badges": ["realized", "savings_amount"]}},
    "views": [
        {"id": "list", "name": "All Savings", "type": "list", "title": "savings_type", "description": "notes", "field_1": "savings_amount", "field_2": "realized"},
        {"id": "kanban", "name": "By Type", "type": "kanban", "group": "savings_type", "title": "notes", "description": "recorded_on", "date": "recorded_on", "badge": "savings_amount"}
    ],
    "filter_presets": [
        {"id": "realized", "name": "Realized", "filters": [{"id": "realized", "value": "true", "operator": "eq"}]},
        {"id": "pipeline", "name": "Pipeline", "filters": [{"id": "realized", "value": "false", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["category_id", "savings_type", "baseline_amount", "negotiated_amount"],
        "sections": [
            {"id": "context", "title": "Context", "fields": ["category_id", "supplier_id", "contract_id", "po_id", "savings_type"]},
            {"id": "amounts", "title": "Amounts", "fields": ["baseline_amount", "negotiated_amount", "currency"]},
            {"id": "outcome", "title": "Outcome", "fields": {"create": ["realized", "recorded_on"], "update": ["realized"], "read": ["savings_amount", "realized", "recorded_on"]}},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "recorded_on", "desc": true}],
        "join": [
            {"table": "categories", "on": "category_id", "columns": ["code", "name"]},
            {"table": "suppliers", "on": "supplier_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column procurement.cost_savings.savings_amount is '{"aggregate": "sum"}';

revoke all on table procurement.cost_savings
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
delete on table procurement.cost_savings to "x-admin",
"buyer";

grant
select
  on table procurement.cost_savings to "approver";

create index idx_proc_cost_savings_category_id on procurement.cost_savings (category_id);

alter table procurement.cost_savings enable row level security;

create policy cost_savings_select on procurement.cost_savings for
select
  to authenticated using (true);

create policy cost_savings_insert on procurement.cost_savings for insert to authenticated
with
  check (true);

create policy cost_savings_update on procurement.cost_savings
for update
  to authenticated using (true)
with
  check (true);

create policy cost_savings_delete on procurement.cost_savings for delete to authenticated using (true);

create or replace function procurement.cost_savings_set_amount () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  new.savings_amount := new.baseline_amount - new.negotiated_amount;
  return new;
end;
$$;

create trigger trg_cost_savings_set_amount before insert
or
update on procurement.cost_savings for each row
execute function procurement.cost_savings_set_amount ();

----------------------------------------------------------------
-- Notification triggers
----------------------------------------------------------------
create or replace function procurement.trg_requisitions_notify () returns trigger as $$
declare
  v_approver_id uuid;
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'pending_approval' then
      select approver_id into v_approver_id
      from procurement.requisition_approvals
      where requisition_id = new.id and step_number = new.current_approval_step;

      if v_approver_id is not null then
        perform supasheet.create_notification(
          'requisition_pending_approval',
          'Approval needed: ' || new.requisition_number,
          'A requisition is waiting on your approval.',
          array[v_approver_id],
          jsonb_build_object('requisition_id', new.id),
          '/procurement/resource/purchase_requisitions/' || new.id::text || '/detail'
        );
      end if;
    elsif new.status in ('approved', 'rejected') then
      perform supasheet.create_notification(
        case when new.status = 'approved' then 'requisition_approved' else 'requisition_rejected' end,
        'Requisition ' || new.status || ': ' || new.requisition_number,
        case when new.status = 'approved' then 'Your requisition was approved.' else 'Your requisition was rejected.' end,
        array_remove(array[new.requester_id], null),
        jsonb_build_object('requisition_id', new.id),
        '/procurement/resource/purchase_requisitions/' || new.id::text || '/detail'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_requisitions_notify on procurement.purchase_requisitions;

create trigger trg_requisitions_notify
after
update of status on procurement.purchase_requisitions for each row
execute function procurement.trg_requisitions_notify ();

create or replace function procurement.trg_po_notify () returns trigger as $$
declare
  v_approver_id uuid;
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'pending_approval' then
      select approver_id into v_approver_id
      from procurement.po_approvals
      where po_id = new.id and step_number = new.current_approval_step;

      if v_approver_id is not null then
        perform supasheet.create_notification(
          'po_pending_approval',
          'Approval needed: ' || new.po_number,
          'A purchase order is waiting on your approval.',
          array[v_approver_id],
          jsonb_build_object('po_id', new.id),
          '/procurement/resource/purchase_orders/' || new.id::text || '/detail'
        );
      end if;
    elsif new.status = 'approved' then
      perform supasheet.create_notification(
        'po_approved',
        'Order approved: ' || new.po_number,
        'The order has cleared approval and can be sent to the supplier.',
        array_remove(array[new.buyer_id], null),
        jsonb_build_object('po_id', new.id),
        '/procurement/resource/purchase_orders/' || new.id::text || '/detail'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_po_notify on procurement.purchase_orders;

create trigger trg_po_notify
after
update of status on procurement.purchase_orders for each row
execute function procurement.trg_po_notify ();

create or replace function procurement.trg_receipts_notify () returns trigger as $$
declare
  v_buyer_id uuid;
begin
  if tg_op = 'UPDATE'
    and new.status is distinct from old.status
    and new.status = 'posted'
    and new.total_rejected_value > 0 then
    select buyer_id into v_buyer_id
    from procurement.purchase_orders
    where id = new.purchase_order_id;

    perform supasheet.create_notification(
      'receipt_has_rejections',
      'Rejections on ' || new.receipt_number,
      'This receipt carries ' || new.total_rejected_value::text || ' in rejected goods.',
      array_remove(array[v_buyer_id], null),
      jsonb_build_object('receipt_id', new.id),
      '/procurement/resource/goods_receipts/' || new.id::text || '/detail'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_receipts_notify on procurement.goods_receipts;

create trigger trg_receipts_notify
after
update of status on procurement.goods_receipts for each row
execute function procurement.trg_receipts_notify ();

create or replace function procurement.trg_invoices_notify () returns trigger as $$
declare
  v_buyer_id uuid;
begin
  if tg_op = 'UPDATE'
    and new.match_status is distinct from old.match_status
    and new.match_status in ('over_tolerance', 'under_tolerance') then
    select buyer_id into v_buyer_id
    from procurement.purchase_orders
    where id = new.purchase_order_id;

    perform supasheet.create_notification(
      'invoice_discrepancy',
      'Match discrepancy: ' || new.internal_reference,
      'This invoice is ' || new.match_status || ' against its order.',
      array_remove(array[v_buyer_id], null),
      jsonb_build_object('invoice_id', new.id),
      '/procurement/resource/vendor_invoices/' || new.id::text || '/detail'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_invoices_notify on procurement.vendor_invoices;

create trigger trg_invoices_notify
after
update of match_status on procurement.vendor_invoices for each row
execute function procurement.trg_invoices_notify ();

----------------------------------------------------------------
-- Audit logging on the high-value tables
----------------------------------------------------------------
create trigger audit_procurement_suppliers_insert
after insert on procurement.suppliers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_suppliers_update
after
update on procurement.suppliers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_suppliers_delete before delete on procurement.suppliers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_contracts_insert
after insert on procurement.contracts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_contracts_update
after
update on procurement.contracts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_contracts_delete before delete on procurement.contracts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_requisitions_insert
after insert on procurement.purchase_requisitions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_requisitions_update
after
update on procurement.purchase_requisitions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_requisitions_delete before delete on procurement.purchase_requisitions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_po_insert
after insert on procurement.purchase_orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_po_update
after
update on procurement.purchase_orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_po_delete before delete on procurement.purchase_orders for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_invoices_insert
after insert on procurement.vendor_invoices for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_invoices_update
after
update on procurement.vendor_invoices for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_procurement_invoices_delete before delete on procurement.vendor_invoices for each row
execute function supasheet.audit_trigger_function ();

-- ================================================================
-- Dashboard widgets
-- ================================================================
create or replace view procurement.open_requisitions_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'clipboard-list' as icon,
  'open requisitions' as label
from
  procurement.purchase_requisitions
where
  status in ('submitted', 'pending_approval');

comment on view procurement.open_requisitions_count is '{"type": "dashboard_widget", "name": "Open Requisitions", "description": "Requisitions awaiting action", "widget_type": "card_1"}';

create or replace view procurement.po_value_comparison
with
  (security_invoker = true) as
select
  coalesce(
    sum(total) filter (
      where
        status in (
          'approved',
          'sent',
          'acknowledged',
          'partially_received',
          'received',
          'invoiced',
          'closed'
        )
    ),
    0
  ) as primary,
  coalesce(
    sum(total) filter (
      where
        status in ('draft', 'pending_approval')
    ),
    0
  ) as secondary,
  'Committed' as primary_label,
  'Pending Approval' as secondary_label
from
  procurement.purchase_orders
where
  status <> 'cancelled';

comment on view procurement.po_value_comparison is '{"type": "dashboard_widget", "name": "Order Value", "description": "Committed spend versus what is still awaiting approval", "widget_type": "card_2"}';

create or replace view procurement.on_time_delivery_summary
with
  (security_invoker = true) as
select
  count(*) as value,
  round(coalesce(avg(s.on_time_delivery_rate), 0)) as percent
from
  procurement.goods_receipts gr
  join procurement.purchase_orders po on po.id = gr.purchase_order_id
  join procurement.suppliers s on s.id = po.supplier_id
where
  gr.status = 'posted';

comment on view procurement.on_time_delivery_summary is '{"type": "dashboard_widget", "name": "On-Time Delivery", "description": "Posted receipts and the average on-time rate of the suppliers behind them", "widget_type": "card_3"}';

create or replace view procurement.po_approval_progress
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'approved'
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
      'Approved',
      'value',
      count(*) filter (
        where
          status = 'approved'
      )
    ),
    json_build_object(
      'label',
      'Rejected',
      'value',
      count(*) filter (
        where
          status = 'rejected'
      )
    )
  ) as segments
from
  procurement.po_approvals;

comment on view procurement.po_approval_progress is '{"type": "dashboard_widget", "name": "Order Approval Steps", "description": "Every order approval step, by outcome", "widget_type": "card_4"}';

create or replace view procurement.spend_ytd_breakdown
with
  (security_invoker = true) as
with
  ytd as (
    select
      po.category_id,
      po.total
    from
      procurement.purchase_orders po
    where
      po.status <> 'cancelled'
      and po.order_date >= date_trunc('year', current_date)
  ),
  by_category as (
    select
      cat.name,
      coalesce(sum(y.total), 0) as total
    from
      procurement.categories cat
      left join ytd y on y.category_id = cat.id
    group by
      cat.name
    order by
      total desc
    limit
      5
  )
select
  (
    select
      coalesce(sum(total), 0)
    from
      ytd
  ) as value,
  'Spend YTD' as label,
  'dollar-sign' as icon,
  (
    select
      json_agg(
        json_build_object('label', name, 'value', total)
      )
    from
      by_category
  ) as breakdown;

comment on view procurement.spend_ytd_breakdown is '{"type": "dashboard_widget", "name": "Spend YTD", "description": "Total spend this year, by top category", "widget_type": "card_5"}';

create or replace view procurement.procurement_metrics_grid
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Open Requisitions',
      'value',
      (
        select
          count(*)
        from
          procurement.purchase_requisitions
        where
          status in ('submitted', 'pending_approval')
      )
    ),
    json_build_object(
      'label',
      'Open Orders',
      'value',
      (
        select
          count(*)
        from
          procurement.purchase_orders
        where
          status not in ('cancelled', 'closed')
      )
    ),
    json_build_object(
      'label',
      'Pending Invoices',
      'value',
      (
        select
          count(*)
        from
          procurement.vendor_invoices
        where
          status in ('pending_match', 'discrepancy')
      )
    ),
    json_build_object(
      'label',
      'Active Contracts',
      'value',
      (
        select
          count(*)
        from
          procurement.contracts
        where
          status = 'active'
      )
    )
  ) as metrics;

comment on view procurement.procurement_metrics_grid is '{"type": "dashboard_widget", "name": "Procurement At A Glance", "description": "The four headline counts", "widget_type": "card_6"}';

create or replace view procurement.recent_purchase_orders
with
  (security_invoker = true) as
select
  po_number,
  status,
  order_date::date as date,
  total,
  '/procurement/resource/purchase_orders/' || id || '/detail' as link
from
  procurement.purchase_orders
order by
  order_date desc
limit
  10;

comment on view procurement.recent_purchase_orders is '{"type": "dashboard_widget", "name": "Recent Orders", "description": "The most recently raised orders", "widget_type": "table_1"}';

create or replace view procurement.spend_by_supplier_table
with
  (security_invoker = true) as
select
  s.name as supplier,
  count(po.id) as orders,
  coalesce(sum(po.total), 0) as total_spend,
  '/procurement/resource/suppliers/' || s.id || '/detail' as link
from
  procurement.suppliers s
  left join procurement.purchase_orders po on po.supplier_id = s.id
  and po.status <> 'cancelled'
group by
  s.id,
  s.name
order by
  total_spend desc
limit
  10;

comment on view procurement.spend_by_supplier_table is '{"type": "dashboard_widget", "name": "Spend By Supplier", "description": "Order count and value, by supplier", "widget_type": "table_2"}';

create or replace view procurement.blocked_suppliers_alert
with
  (security_invoker = true) as
select
  name as title,
  code || ' — ' || status as description,
  'ban' as icon,
  'destructive' as variant,
  '/procurement/resource/suppliers/' || id || '/detail' as link
from
  procurement.suppliers
where
  status in ('on_hold', 'blacklisted')
order by
  updated_at desc
limit
  10;

comment on view procurement.blocked_suppliers_alert is '{"type": "dashboard_widget", "name": "Blocked Suppliers", "description": "Suppliers that cannot currently be ordered from", "widget_type": "list_1"}';

create or replace view procurement.invoice_discrepancies_alert
with
  (security_invoker = true) as
select
  internal_reference as title,
  supplier_invoice_number as description,
  'triangle-alert' as icon,
  'warning' as variant,
  match_status::text as field_1,
  to_char(due_date, 'MM/DD') as field_2,
  '/procurement/resource/vendor_invoices/' || id || '/detail' as link
from
  procurement.vendor_invoices
where
  match_status in ('over_tolerance', 'under_tolerance')
order by
  due_date asc nulls last
limit
  10;

comment on view procurement.invoice_discrepancies_alert is '{"type": "dashboard_widget", "name": "Invoice Discrepancies", "description": "Invoices whose three-way match is outside tolerance", "widget_type": "list_2"}';

create or replace view procurement.recent_po_activity
with
  (security_invoker = true) as
select
  u.name as actor,
  case
    when e.event_type = 'created' then 'created'
    when e.event_type = 'approved' then 'approved'
    when e.event_type = 'sent' then 'sent'
    when e.event_type = 'received' then 'received against'
    when e.event_type = 'invoiced' then 'billed'
    else 'updated'
  end as action,
  po.po_number as entity,
  to_char(e.occurred_at, 'Mon DD, YYYY') as date,
  '/procurement/resource/purchase_orders/' || po.id || '/detail' as link
from
  procurement.purchase_order_events e
  join procurement.purchase_orders po on po.id = e.po_id
  left join procurement.users u on u.id = e.actor_id
order by
  e.occurred_at desc
limit
  5;

comment on view procurement.recent_po_activity is '{"type": "dashboard_widget", "name": "Recent Order Activity", "description": "The latest events across every order", "widget_type": "list_3"}';

create or replace view procurement.top_suppliers_leaderboard
with
  (security_invoker = true) as
select
  name,
  total_spend as value,
  code as label,
  '/procurement/resource/suppliers/' || id || '/detail' as link
from
  procurement.suppliers
where
  total_spend > 0
order by
  total_spend desc
limit
  5;

comment on view procurement.top_suppliers_leaderboard is '{"type": "dashboard_widget", "name": "Top Suppliers", "description": "Ranked by total spend", "widget_type": "list_4"}';

do $$
declare
  v text;
begin
  foreach v in array array[
    'procurement.open_requisitions_count',
    'procurement.po_value_comparison',
    'procurement.on_time_delivery_summary',
    'procurement.po_approval_progress',
    'procurement.spend_ytd_breakdown',
    'procurement.procurement_metrics_grid',
    'procurement.recent_purchase_orders',
    'procurement.spend_by_supplier_table',
    'procurement.blocked_suppliers_alert',
    'procurement.invoice_discrepancies_alert',
    'procurement.recent_po_activity',
    'procurement.top_suppliers_leaderboard'
  ]
  loop
    execute format('revoke all on %s from public, anon, authenticated, service_role;', v);
    execute format('grant select on %s to "x-admin", "buyer", "approver";', v);
  end loop;
end;
$$;

-- ================================================================
-- Charts
-- ================================================================
create or replace view procurement.spend_by_category_pie
with
  (security_invoker = true) as
select
  cat.name as label,
  coalesce(sum(po.total), 0) as value
from
  procurement.categories cat
  join procurement.purchase_orders po on po.category_id = cat.id
  and po.status <> 'cancelled'
group by
  cat.name;

comment on view procurement.spend_by_category_pie is '{"type": "chart", "name": "Spend By Category", "description": "Non-cancelled order value, by category", "chart_type": "pie", "format": "currency"}';

create or replace view procurement.po_value_by_department_bar
with
  (security_invoker = true) as
select
  d.name as label,
  count(po.id) as orders,
  coalesce(sum(po.total), 0) as value
from
  procurement.departments d
  left join procurement.purchase_orders po on po.department_id = d.id
  and po.status <> 'cancelled'
group by
  d.name
order by
  value desc;

comment on view procurement.po_value_by_department_bar is '{"type": "chart", "name": "Order Value By Department", "description": "Order count and value per department", "chart_type": "bar", "format": "currency"}';

create or replace view procurement.monthly_spend_trend_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', order_date), 'Mon YYYY') as date,
  coalesce(sum(total), 0) as spend
from
  procurement.purchase_orders
where
  status <> 'cancelled'
group by
  date_trunc('month', order_date)
order by
  date_trunc('month', order_date);

comment on view procurement.monthly_spend_trend_line is '{"type": "chart", "name": "Monthly Spend", "description": "Order value by month raised", "chart_type": "line", "format": "currency"}';

create or replace view procurement.requisitions_trend_area
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', created_at), 'Mon YYYY') as date,
  count(*) filter (
    where
      status in (
        'submitted',
        'pending_approval',
        'approved',
        'rejected',
        'converted'
      )
  ) as submitted,
  count(*) filter (
    where
      status in ('approved', 'converted')
  ) as approved
from
  procurement.purchase_requisitions
group by
  date_trunc('month', created_at)
order by
  date_trunc('month', created_at);

comment on view procurement.requisitions_trend_area is '{"type": "chart", "name": "Requisitions Submitted vs Approved", "description": "Monthly requisition volume against how much cleared approval", "chart_type": "area"}';

create or replace view procurement.supplier_scores_radar
with
  (security_invoker = true) as
select
  name as metric,
  coalesce(quality_score, 0) as quality,
  coalesce(responsiveness_score, 0) as responsiveness,
  coalesce(overall_rating, 0) as overall
from
  procurement.suppliers
where
  total_spend > 0
order by
  total_spend desc
limit
  6;

comment on view procurement.supplier_scores_radar is '{"type": "chart", "name": "Supplier Scores", "description": "Quality, responsiveness and overall rating for the top suppliers by spend", "chart_type": "radar"}';

do $$
declare
  v text;
begin
  foreach v in array array[
    'procurement.spend_by_category_pie',
    'procurement.po_value_by_department_bar',
    'procurement.monthly_spend_trend_line',
    'procurement.requisitions_trend_area',
    'procurement.supplier_scores_radar'
  ]
  loop
    execute format('revoke all on %s from public, anon, authenticated, service_role;', v);
    execute format('grant select on %s to "x-admin", "buyer", "approver";', v);
  end loop;
end;
$$;

-- ================================================================
-- Reports
-- ================================================================
create or replace view procurement.purchase_orders_report
with
  (security_invoker = true) as
select
  po.id,
  po.po_number,
  po.status,
  po.order_date,
  po.expected_delivery_date,
  s.name as supplier,
  s.email as supplier_email,
  s.address as supplier_address,
  d.name as department,
  po.currency,
  po.subtotal,
  po.tax_total,
  po.shipping_total,
  po.total,
  po.delivery_address,
  po.billing_address,
  po.supplier_reference,
  count(pol.id) as line_count
from
  procurement.purchase_orders po
  left join procurement.suppliers s on s.id = po.supplier_id
  left join procurement.departments d on d.id = po.department_id
  left join procurement.purchase_order_lines pol on pol.po_id = po.id
group by
  po.id,
  s.name,
  s.email,
  s.address,
  d.name;

comment on view procurement.purchase_orders_report is '{"type": "report", "name": "Purchase Orders", "description": "Every order with supplier, department and line count — the printable order document.", "template": true}';

revoke all on procurement.purchase_orders_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on procurement.purchase_orders_report to "x-admin",
  "buyer",
  "approver";

create or replace view procurement.three_way_match_report
with
  (security_invoker = true) as
select
  vi.id,
  vi.internal_reference,
  vi.supplier_invoice_number,
  s.name as supplier,
  po.po_number,
  vi.match_status,
  vi.status,
  vi.total as invoiced_total,
  po.total as ordered_total,
  po.received_value,
  vi.variance_amount,
  vi.tolerance_percent,
  vi.invoice_date,
  vi.due_date
from
  procurement.vendor_invoices vi
  join procurement.purchase_orders po on po.id = vi.purchase_order_id
  join procurement.suppliers s on s.id = vi.supplier_id;

comment on view procurement.three_way_match_report is '{"type": "report", "name": "Three-Way Match", "description": "Every invoice next to the order it bills and the receipt behind it, with the variance called out."}';

revoke all on procurement.three_way_match_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on procurement.three_way_match_report to "x-admin",
  "buyer",
  "approver";

create or replace view procurement.supplier_performance_report
with
  (security_invoker = true) as
select
  s.id,
  s.code,
  s.name,
  s.status,
  s.risk_rating,
  s.on_time_delivery_rate,
  s.quality_score,
  s.responsiveness_score,
  s.overall_rating,
  s.total_spend,
  s.open_po_value,
  count(distinct po.id) as order_count,
  count(distinct spr.id) as review_count
from
  procurement.suppliers s
  left join procurement.purchase_orders po on po.supplier_id = s.id
  and po.status <> 'cancelled'
  left join procurement.supplier_performance_reviews spr on spr.supplier_id = s.id
group by
  s.id;

comment on view procurement.supplier_performance_report is '{"type": "report", "name": "Supplier Performance", "description": "Every supplier''s scorecard next to how much business they actually do."}';

revoke all on procurement.supplier_performance_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on procurement.supplier_performance_report to "x-admin",
  "buyer",
  "approver";

-- Heavy monthly rollup — a materialized view instead of a live report.
create materialized view procurement.spend_analysis as
select
  date_trunc('month', po.order_date)::date as month,
  coalesce(cat.name, 'Uncategorised') as category,
  coalesce(d.name, 'Unassigned') as department,
  count(*) as order_count,
  sum(po.total) as spend
from
  procurement.purchase_orders po
  left join procurement.categories cat on cat.id = po.category_id
  left join procurement.departments d on d.id = po.department_id
where
  po.status <> 'cancelled'
group by
  1,
  2,
  3;

create unique index idx_proc_spend_analysis on procurement.spend_analysis (month, category, department);

comment on materialized view procurement.spend_analysis is '{"type": "report", "name": "Spend Analysis", "description": "Monthly spend by category and department — precomputed since it scans every order. Refresh with: refresh materialized view concurrently procurement.spend_analysis;"}';

revoke all on procurement.spend_analysis
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on procurement.spend_analysis to "x-admin",
  "buyer",
  "approver";

-- ================================================================
-- Templates (bulk insert)
-- ================================================================
create or replace view procurement.standard_categories_template
with
  (security_invoker = true) as
select
  *
from
  (
    values
      (
        'IT'::varchar(20),
        'Information Technology'::varchar(160),
        5000::numeric(14, 2)
      ),
      ('FAC', 'Facilities', 2000),
      ('MKT', 'Marketing', 3000),
      ('PROF', 'Professional Services', 10000),
      ('RAW', 'Raw Materials', 15000),
      ('LOG', 'Logistics', 5000),
      (
        'MRO',
        'Maintenance, Repair & Operating',
        2000
      )
  ) as t (code, name, default_approval_threshold);

comment on view procurement.standard_categories_template is '{
    "type": "template",
    "name": "Standard Category Set",
    "description": "A sensible starting spend taxonomy for a fresh install. Apply to procurement.categories.",
    "target_table": "categories"
}';

revoke all on procurement.standard_categories_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on procurement.standard_categories_template to "x-admin";

create or replace view procurement.contract_renewal_template
with
  (security_invoker = true) as
select
  supplier_id,
  category_id,
  owner_id,
  contract_type,
  'draft'::procurement.contract_status as status,
  title || ' (Renewal)' as title,
  (end_date + 1)::date as start_date,
  (end_date + (end_date - start_date) + 1)::date as end_date,
  currency,
  ceiling_amount,
  auto_renew,
  renewal_notice_days,
  payment_terms_days
from
  procurement.contracts
where
  status = 'active'
  and auto_renew = true
  and end_date <= current_date + 30;

comment on view procurement.contract_renewal_template is '{
    "type": "template",
    "name": "Contracts Due For Renewal",
    "description": "Draft renewal rows for every auto-renew contract expiring within 30 days, same term length carried forward. Apply to procurement.contracts.",
    "target_table": "contracts"
}';

revoke all on procurement.contract_renewal_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on procurement.contract_renewal_template to "x-admin",
  "buyer";

-- ================================================================
-- Custom forms
-- ================================================================
create or replace function procurement.award_rfq (
  p_rfq_id uuid,
  p_supplier_id uuid,
  p_notes text default null
) returns procurement.rfqs language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_rfq procurement.rfqs;
begin
  if not exists (
    select 1
    from procurement.supplier_quotes
    where rfq_id = p_rfq_id
      and supplier_id = p_supplier_id
      and status in ('submitted', 'shortlisted')
  ) then
    raise exception 'That supplier has not submitted a live quote for this RFQ.';
  end if;

  update procurement.supplier_quotes
  set status = case
    when supplier_id = p_supplier_id then 'awarded'::procurement.quote_status
    else 'rejected'::procurement.quote_status
  end
  where rfq_id = p_rfq_id
    and status in ('submitted', 'shortlisted');

  update procurement.rfqs
  set status = 'awarded',
    awarded_supplier_id = p_supplier_id,
    awarded_at = current_timestamp,
    notes = coalesce(p_notes, notes),
    updated_at = current_timestamp
  where id = p_rfq_id
  returning * into v_rfq;

  return v_rfq;
end;
$$;

comment on function procurement.award_rfq (uuid, uuid, text) is '{
    "type": "form",
    "resource": "rfqs",
    "name": "Award RFQ",
    "description": "Pick the winning supplier. Every other live quote is rejected automatically.",
    "icon": "Trophy",
    "success_message": "RFQ awarded",
    "fields": {
        "sections": [
            {"id": "award", "title": "Award", "fields": ["p_rfq_id", "p_supplier_id", "p_notes"]}
        ],
        "relations": {
            "p_rfq_id": {"table": "rfqs", "column": "id", "display": ["rfq_number", "title"]},
            "p_supplier_id": {"table": "suppliers", "column": "id", "display": ["code", "name"]}
        }
    }
}';

create or replace function procurement.convert_requisition_to_po (
  p_requisition_id uuid,
  p_supplier_id uuid,
  p_expected_delivery_date date default null,
  p_contract_id uuid default null
) returns procurement.purchase_orders language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_requisition procurement.purchase_requisitions;
  v_po procurement.purchase_orders;
begin
  select * into v_requisition
  from procurement.purchase_requisitions
  where id = p_requisition_id;

  if v_requisition.id is null then
    raise exception 'Requisition not found.';
  end if;

  if v_requisition.status <> 'approved' then
    raise exception 'Only an approved requisition can be converted to an order.';
  end if;

  insert into procurement.purchase_orders (
    supplier_id, requisition_id, contract_id, department_id, category_id, expected_delivery_date
  )
  values (
    p_supplier_id, p_requisition_id, p_contract_id, v_requisition.department_id, v_requisition.category_id, p_expected_delivery_date
  )
  returning * into v_po;

  insert into procurement.purchase_order_lines (
    po_id, requisition_line_id, category_id, description, quantity_ordered, uom, unit_price
  )
  select v_po.id, rl.id, rl.category_id, rl.description, rl.quantity, rl.uom, rl.estimated_unit_price
  from procurement.requisition_lines rl
  where rl.requisition_id = p_requisition_id;

  update procurement.purchase_requisitions
  set status = 'converted',
    updated_at = current_timestamp
  where id = p_requisition_id;

  select * into v_po
  from procurement.purchase_orders
  where id = v_po.id;

  return v_po;
end;
$$;

comment on function procurement.convert_requisition_to_po (uuid, uuid, date, uuid) is '{
    "type": "form",
    "resource": "purchase_requisitions",
    "name": "Convert to Order",
    "description": "Turn an approved requisition into a purchase order, carrying every line across.",
    "icon": "ArrowRightCircle",
    "success_message": "Order created",
    "fields": {
        "sections": [
            {"id": "order", "title": "Order", "fields": ["p_requisition_id", "p_supplier_id", "p_contract_id", "p_expected_delivery_date"]}
        ],
        "relations": {
            "p_requisition_id": {"table": "purchase_requisitions", "column": "id", "display": ["requisition_number", "status"]},
            "p_supplier_id": {"table": "suppliers", "column": "id", "display": ["code", "name"]},
            "p_contract_id": {"table": "contracts", "column": "id", "display": ["contract_number", "title"]}
        }
    }
}';

create or replace function procurement.record_invoice_payment (
  p_invoice_id uuid,
  p_amount numeric,
  p_payment_date date default current_date,
  p_method procurement.payment_method default 'bank_transfer',
  p_reference varchar default null
) returns procurement.invoice_payments language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_payment procurement.invoice_payments;
  v_balance numeric(14, 2);
begin
  select balance_due into v_balance
  from procurement.vendor_invoices
  where id = p_invoice_id;

  if v_balance is null then
    raise exception 'Invoice not found.';
  end if;

  if p_amount > v_balance then
    raise exception 'Payment of % exceeds the outstanding balance of %.', p_amount, v_balance;
  end if;

  insert into procurement.invoice_payments (invoice_id, amount, payment_date, method, reference)
  values (p_invoice_id, p_amount, p_payment_date, p_method, p_reference)
  returning * into v_payment;

  return v_payment;
end;
$$;

comment on function procurement.record_invoice_payment (
  uuid, numeric, date, procurement.payment_method, varchar
) is '{
    "type": "form",
    "resource": "vendor_invoices",
    "name": "Record Payment",
    "description": "Log money sent against this invoice. Refused past the outstanding balance.",
    "icon": "BadgeDollarSign",
    "success_message": "Payment recorded",
    "fields": {
        "sections": [
            {"id": "payment", "title": "Payment", "fields": ["p_invoice_id", "p_amount", "p_payment_date", "p_method", "p_reference"]}
        ],
        "relations": {
            "p_invoice_id": {"table": "vendor_invoices", "column": "id", "display": ["internal_reference", "supplier_invoice_number"]}
        }
    }
}';

do $$
declare
  f text;
begin
  foreach f in array array[
    'procurement.award_rfq(uuid, uuid, text)',
    'procurement.convert_requisition_to_po(uuid, uuid, date, uuid)',
    'procurement.record_invoice_payment(uuid, numeric, date, procurement.payment_method, varchar)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role;', f);
  end loop;
end;
$$;

grant
execute on function procurement.award_rfq (uuid, uuid, text) to "x-admin",
"buyer";

grant
execute on function procurement.convert_requisition_to_po (uuid, uuid, date, uuid) to "x-admin",
"buyer";

grant
execute on function procurement.record_invoice_payment (
  uuid, numeric, date, procurement.payment_method, varchar
) to "x-admin",
"buyer";

-- ================================================================
-- Row actions
-- ================================================================
create or replace function procurement.submit_requisition (p_id uuid) returns void language plpgsql security definer
set
  search_path = '' as $$
declare
  v_requisition procurement.purchase_requisitions;
  v_owner_id uuid;
  v_threshold numeric(14, 2);
  -- security definer swaps current_user for this function's owner, so
  -- pg_has_role(current_user, ...) would always see the owner's roles,
  -- not the caller's — read the caller's role from the JWT claim instead.
  v_caller_role text := (select auth.jwt () ->> 'role');
begin
  select * into v_requisition
  from procurement.purchase_requisitions
  where id = p_id;

  if v_requisition.id is null then
    raise exception 'Requisition not found.';
  end if;

  if v_requisition.requester_id <> (select auth.uid ())
    and not pg_has_role (v_caller_role, 'buyer', 'member')
    and not pg_has_role (v_caller_role, 'x-admin', 'member') then
    raise exception 'Only the requester (or procurement staff) can submit this requisition.';
  end if;

  if v_requisition.status <> 'draft' then
    raise exception 'Only a draft requisition can be submitted.';
  end if;

  if v_requisition.line_count = 0 then
    raise exception 'Add at least one line before submitting.';
  end if;

  select budget_owner_id into v_owner_id
  from procurement.departments
  where id = v_requisition.department_id;

  select default_approval_threshold into v_threshold
  from procurement.categories
  where id = v_requisition.category_id;

  v_threshold := coalesce(v_threshold, 1000);

  delete from procurement.requisition_approvals
  where requisition_id = p_id;

  insert into procurement.requisition_approvals (requisition_id, step_number, approver_id, threshold_amount)
  values (p_id, 1, v_owner_id, v_threshold);

  -- Big-ticket requisitions pick up a second, director-level sign-off —
  -- approver_id left null means any x-admin can take that step.
  if v_requisition.estimated_total > v_threshold * 3 then
    insert into procurement.requisition_approvals (requisition_id, step_number, approver_id, threshold_amount)
    values (p_id, 2, null, v_threshold * 3);
  end if;

  update procurement.purchase_requisitions
  set submitted_at = current_timestamp
  where id = p_id;
end;
$$;

comment on function procurement.submit_requisition (uuid) is '{
    "type": "action",
    "resource": "purchase_requisitions",
    "name": "Submit",
    "description": "Send for approval. Builds the approval chain from the department''s budget owner and, for larger amounts, a director sign-off.",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Requisition submitted"
}';

create or replace function procurement.submit_po (p_id uuid) returns void language plpgsql security definer
set
  search_path = '' as $$
declare
  v_po procurement.purchase_orders;
  v_owner_id uuid;
  v_threshold numeric(14, 2);
begin
  select * into v_po
  from procurement.purchase_orders
  where id = p_id;

  if v_po.id is null then
    raise exception 'Order not found.';
  end if;

  if v_po.status <> 'draft' then
    raise exception 'Only a draft order can be submitted.';
  end if;

  if v_po.line_count = 0 then
    raise exception 'Add at least one line before submitting.';
  end if;

  select budget_owner_id into v_owner_id
  from procurement.departments
  where id = v_po.department_id;

  select default_approval_threshold into v_threshold
  from procurement.categories
  where id = v_po.category_id;

  v_threshold := coalesce(v_threshold, 1000);

  delete from procurement.po_approvals
  where po_id = p_id;

  insert into procurement.po_approvals (po_id, step_number, approver_id, threshold_amount)
  values (p_id, 1, v_owner_id, v_threshold);

  -- Big-ticket orders pick up a second, director-level sign-off — a null
  -- approver_id means any x-admin can take that step.
  if v_po.total > v_threshold * 3 then
    insert into procurement.po_approvals (po_id, step_number, approver_id, threshold_amount)
    values (p_id, 2, null, v_threshold * 3);
  end if;
end;
$$;

comment on function procurement.submit_po (uuid) is '{
    "type": "action",
    "resource": "purchase_orders",
    "name": "Submit",
    "description": "Send for approval. Builds the approval chain from the department''s budget owner and, for larger amounts, a director sign-off.",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Order submitted"
}';

create or replace function procurement.send_po_to_supplier (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update procurement.purchase_orders
  set status = 'sent',
    sent_at = current_timestamp
  where id = p_id
    and status = 'approved';
end;
$$;

comment on function procurement.send_po_to_supplier (uuid) is '{
    "type": "action",
    "resource": "purchase_orders",
    "name": "Send to Supplier",
    "description": "Mark the order as sent once it has cleared approval.",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "eq", "value": "approved"}],
    "success_message": "Order sent"
}';

create or replace function procurement.acknowledge_po (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update procurement.purchase_orders
  set status = 'acknowledged',
    acknowledged_at = current_timestamp
  where id = p_id
    and status = 'sent';
end;
$$;

comment on function procurement.acknowledge_po (uuid) is '{
    "type": "action",
    "resource": "purchase_orders",
    "name": "Mark Acknowledged",
    "description": "Record that the supplier has confirmed the order.",
    "icon": "MailCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "sent"}],
    "success_message": "Order acknowledged"
}';

create or replace function procurement.cancel_po (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update procurement.purchase_orders
  set status = 'cancelled',
    cancelled_reason = p_reason
  where id = p_id
    and status not in (
      'received',
      'invoiced',
      'closed',
      'cancelled'
    );
end;
$$;

comment on function procurement.cancel_po (uuid, varchar) is '{
    "type": "action",
    "resource": "purchase_orders",
    "name": "Cancel",
    "description": "Cancel the order. Refused once anything has been received or billed against it.",
    "icon": "Ban",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "pending_approval", "approved", "sent", "acknowledged", "partially_received"]}],
    "success_message": "Order cancelled"
}';

create or replace function procurement.close_po (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update procurement.purchase_orders
  set status = 'closed',
    closed_at = current_timestamp
  where id = p_id
    and status in ('received', 'invoiced');
end;
$$;

comment on function procurement.close_po (uuid) is '{
    "type": "action",
    "resource": "purchase_orders",
    "name": "Close",
    "description": "Close the order out once it is fully received and billed.",
    "icon": "Archive",
    "visible": [{"id": "status", "operator": "in", "value": ["received", "invoiced"]}],
    "success_message": "Order closed"
}';

create or replace function procurement.post_goods_receipt (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if not exists (
    select 1
    from procurement.goods_receipt_lines
    where receipt_id = p_id
  ) then
    raise exception 'Add at least one line before posting.';
  end if;

  update procurement.goods_receipts
  set status = 'posted'
  where id = p_id
    and status = 'draft';
end;
$$;

comment on function procurement.post_goods_receipt (uuid) is '{
    "type": "action",
    "resource": "goods_receipts",
    "name": "Post",
    "description": "Commit the receipt — order lines and the parent order''s status update immediately.",
    "icon": "PackageCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Receipt posted"
}';

create or replace function procurement.dispute_goods_receipt (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update procurement.goods_receipts
  set status = 'disputed'
  where id = p_id
    and status = 'posted';
end;
$$;

comment on function procurement.dispute_goods_receipt (uuid) is '{
    "type": "action",
    "resource": "goods_receipts",
    "name": "Dispute",
    "description": "Flag this receipt as under dispute with the carrier or supplier.",
    "icon": "TriangleAlert",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "eq", "value": "posted"}],
    "success_message": "Receipt disputed"
}';

create or replace function procurement.approve_invoice (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update procurement.vendor_invoices
  set status = 'approved'
  where id = p_id
    and status in ('matched', 'discrepancy');
end;
$$;

comment on function procurement.approve_invoice (uuid) is '{
    "type": "action",
    "resource": "vendor_invoices",
    "name": "Approve",
    "description": "Approve for payment. Refused while the three-way match is outside tolerance, unless x-admin overrides it.",
    "icon": "BadgeCheck",
    "visible": [{"id": "status", "operator": "in", "value": ["matched", "discrepancy"]}],
    "success_message": "Invoice approved"
}';

create or replace function procurement.dispute_invoice (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update procurement.vendor_invoices
  set status = 'disputed',
    notes = coalesce(notes || E'\n', '') || 'Disputed: ' || p_reason
  where id = p_id
    and status not in ('paid', 'void');
end;
$$;

comment on function procurement.dispute_invoice (uuid, varchar) is '{
    "type": "action",
    "resource": "vendor_invoices",
    "name": "Dispute",
    "description": "Push this invoice back to the supplier with a reason.",
    "icon": "Flag",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "not.in", "value": ["paid", "void"]}],
    "success_message": "Invoice disputed"
}';

do $$
declare
  f text;
begin
  foreach f in array array[
    'procurement.submit_requisition(uuid)',
    'procurement.submit_po(uuid)',
    'procurement.send_po_to_supplier(uuid)',
    'procurement.acknowledge_po(uuid)',
    'procurement.cancel_po(uuid, varchar)',
    'procurement.close_po(uuid)',
    'procurement.post_goods_receipt(uuid)',
    'procurement.dispute_goods_receipt(uuid)',
    'procurement.approve_invoice(uuid)',
    'procurement.dispute_invoice(uuid, varchar)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role;', f);
  end loop;
end;
$$;

grant
execute on function procurement.submit_requisition (uuid) to "x-admin",
"buyer",
"user";

grant
execute on function procurement.submit_po (uuid) to "x-admin",
"buyer";

grant
execute on function procurement.send_po_to_supplier (uuid) to "x-admin",
"buyer";

grant
execute on function procurement.acknowledge_po (uuid) to "x-admin",
"buyer";

grant
execute on function procurement.cancel_po (uuid, varchar) to "x-admin",
"buyer";

grant
execute on function procurement.close_po (uuid) to "x-admin",
"buyer";

grant
execute on function procurement.post_goods_receipt (uuid) to "x-admin",
"buyer";

grant
execute on function procurement.dispute_goods_receipt (uuid) to "x-admin",
"buyer";

grant
execute on function procurement.approve_invoice (uuid) to "x-admin",
"buyer";

grant
execute on function procurement.dispute_invoice (uuid, varchar) to "x-admin",
"buyer";

----------------------------------------------------------------
-- Private document storage
--
-- Contracts and invoices are evidence beyond what any single FILE
-- column holds. This bucket delegates to the same table privileges
-- the rest of the module uses: if your role cannot read
-- procurement.contracts, it cannot read the paperwork behind one
-- either.
----------------------------------------------------------------
insert into
  storage.buckets (id, name, public)
values
  (
    'procurement-documents',
    'procurement-documents',
    false
  )
on conflict (id) do nothing;

drop policy if exists procurement_documents_read on storage.objects;

create policy procurement_documents_read on storage.objects for
select
  to authenticated using (
    bucket_id = 'procurement-documents'
    and (
      has_table_privilege (current_user, 'procurement.contracts', 'select')
      or has_table_privilege (current_user, 'procurement.vendor_invoices', 'select')
    )
  );

drop policy if exists procurement_documents_insert on storage.objects;

create policy procurement_documents_insert on storage.objects for insert to authenticated
with
  check (
    bucket_id = 'procurement-documents'
    and (
      has_table_privilege (current_user, 'procurement.contracts', 'insert')
      or has_table_privilege (current_user, 'procurement.vendor_invoices', 'insert')
    )
  );

drop policy if exists procurement_documents_update on storage.objects;

create policy procurement_documents_update on storage.objects
for update
  to authenticated using (
    bucket_id = 'procurement-documents'
    and has_table_privilege (current_user, 'procurement.contracts', 'update')
  );

drop policy if exists procurement_documents_delete on storage.objects;

create policy procurement_documents_delete on storage.objects for delete to authenticated using (
  bucket_id = 'procurement-documents'
  and has_table_privilege (current_user, 'procurement.contracts', 'delete')
);

----------------------------------------------------------------
-- App configuration
----------------------------------------------------------------
insert into
  supasheet.configs (key, value, description, is_public)
values
  (
    'procurement.default_currency',
    '"USD"',
    'Currency assumed when a supplier or order does not specify one',
    true
  ),
  (
    'procurement.default_invoice_tolerance_percent',
    '2',
    'Default three-way match tolerance applied to new vendor invoices',
    false
  ),
  (
    'procurement.default_payment_terms_days',
    '30',
    'Payment terms applied to a new supplier with none of its own',
    false
  ),
  (
    'procurement.director_approval_multiplier',
    '3',
    'A requisition above this many times its category threshold picks up a second, director-level approval step',
    false
  )
on conflict (key) do nothing;

-- ================================================================
-- Refresh the metadata catalog — must be last
-- ================================================================
select
  supasheet.refresh_metadata ();
