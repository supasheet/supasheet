-- ================================================================
-- Supasheet Example — "Quality" (quality management system)
-- ================================================================
-- A production-shaped QMS: controlled documents with real revision
-- history, an audit program that raises findings, an enterprise-wide
-- nonconformance and customer-complaint log, the CAPA engine that
-- ties all of it together, FMEA-style risk assessment, equipment
-- calibration, and training records.
--
-- Demo data lives in supabase/examples/q_seed.sql — apply this file
-- first, then that one.
--
-- This is not the manufacturing module's shop-floor quality control
-- with different words on it. That one asks "did this batch pass
-- inspection?" and lives entirely inside a works order. This one
-- asks "across the whole business, what went wrong, why, what did we
-- do about it, and can we prove it actually worked?" — document
-- control, audits, CAPA and calibration are all things a shop floor
-- inspection never touches, and nothing here references a works
-- order or a bill of material.
--
-- The rules that make it a QMS rather than a set of lists:
--
--   - A CAPA CANNOT CLOSE UNTIL IT IS PROVEN TO HAVE WORKED. Every
--     one of its actions must be completed, and the effectiveness
--     check must have come back `effective`, before the status can
--     reach `closed`. "We did the actions" is not the same claim as
--     "the actions fixed it," and the trigger only accepts the
--     second one.
--   - A MAJOR OR CRITICAL FINDING CANNOT CLOSE WITHOUT A CAPA. Minor
--     findings and observations can be closed on the spot; anything
--     serious enough to be major or critical is refused a close
--     until at least one CAPA has been raised against it.
--   - ONLY ONE EFFECTIVE VERSION OF A DOCUMENT AT A TIME. Publishing
--     a new version does not just add a row — it supersedes whatever
--     was effective before it, in the same trigger, so "which
--     version is the real one" never has two answers. Nothing skips
--     straight to effective without passing through review and
--     approval first.
--   - CALIBRATION STATUS IS DERIVED, NEVER TYPED. Equipment flips to
--     `overdue` the moment its calibration due date passes, computed
--     the same way a supplier's compliance document expiry is
--     computed elsewhere in this catalogue — nobody has to remember
--     to go and mark it.
--   - A RISK PRIORITY NUMBER IS A PRODUCT, NOT AN OPINION. severity ×
--     occurrence × detection is computed on write; nobody types the
--     100.
--
-- Everything the other modules cover is here too:
--   - Native-role RBAC with two custom roles ("qa-manager" runs
--     document control, audits and CAPA disposition; "quality-auditor"
--     conducts audits and raises findings)
--     alongside "x-admin"/"user"
--   - RLS that lets any employee ("user") own and work their own
--     CAPA actions and training records, not just quality staff
--   - All six view layouts, every widget and chart contract, reports
--     with a Handlebars print template, a materialized KPI rollup,
--     both a static and a live-data template, custom form shapes,
--     row actions, notifications, audit logging, per-resource
--     comments and a private `quality-documents` storage bucket
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260808000000_quality.sql \
--     -f supabase/examples/q_seed.sql
--
-- Requires the base Supasheet migrations. Add "quality" to
-- config.toml's `api.schemas` and `api.extra_search_path`, then
-- restart Supabase.
--
-- Not idempotent: re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists quality;

-------------------------------------------------------------------
-- Roles
--
--   x-admin      quality director: everything, including deleting
--                documents/audits and overriding a blocked close
--   qa-manager   day-to-day quality: document control, schedules and
--                owns audits, dispositions nonconformances and
--                complaints, runs the CAPA programme end to end,
--                manages equipment and calibration. Cannot delete
--                documents or audits
--   quality-auditor  conducts audits — fills checklists, raises findings
--                and can open a CAPA from one. Cannot approve documents
--                or close a CAPA
--   user         THE EMPLOYEE: acknowledges controlled documents,
--                reports nonconformances, and owns whatever CAPA
--                actions or training records are assigned to them —
--                corrective action is everyone's job, not just
--                quality's
--
-- Assign a user to a custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "qa-manager"}'
--   where email = 'quality@example.com';
-------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'user') then
    create role "user" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'admin') then
    create role "admin" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'qa-manager') then
    create role "qa-manager" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'quality-auditor') then
    create role "quality-auditor" nologin;
  end if;
end;
$$;

grant "user",
"admin",
"qa-manager",
"quality-auditor" to authenticator;

grant authenticated to "user",
"admin",
"qa-manager",
"quality-auditor";

grant usage on schema quality to "x-admin",
"qa-manager",
"quality-auditor",
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
create type quality.process_category as enum('core', 'support', 'management');

create type quality.document_type as enum(
  'policy',
  'procedure',
  'work_instruction',
  'form',
  'quality_manual',
  'external_standard',
  'record'
);

create type quality.document_status as enum('active', 'obsolete');

create type quality.version_status as enum(
  'draft',
  'in_review',
  'approved',
  'effective',
  'superseded',
  'obsolete'
);

create type quality.audit_type as enum('internal', 'external', 'supplier', 'certification');

create type quality.audit_status as enum(
  'planned',
  'scheduled',
  'in_progress',
  'completed',
  'closed',
  'cancelled'
);

create type quality.audit_result as enum(
  'pending',
  'pass',
  'minor_findings',
  'major_findings',
  'fail'
);

create type quality.checklist_response as enum(
  'pending',
  'conformant',
  'nonconformant',
  'not_applicable',
  'observation'
);

create type quality.finding_severity as enum('observation', 'minor', 'major', 'critical');

create type quality.finding_status as enum('open', 'capa_raised', 'closed');

create type quality.nc_source as enum(
  'audit_finding',
  'customer_complaint',
  'internal_report',
  'supplier_issue',
  'inspection',
  'other'
);

create type quality.nc_severity as enum('minor', 'major', 'critical');

create type quality.nc_status as enum(
  'open',
  'under_investigation',
  'capa_raised',
  'closed'
);

create type quality.complaint_status as enum('open', 'investigating', 'resolved', 'closed');

create type quality.capa_type as enum('corrective', 'preventive', 'both');

create type quality.capa_source as enum(
  'audit_finding',
  'nonconformance',
  'complaint',
  'management_review',
  'risk_assessment',
  'other'
);

create type quality.capa_status as enum(
  'open',
  'root_cause_analysis',
  'action_planned',
  'in_progress',
  'pending_verification',
  'verified',
  'closed',
  'cancelled'
);

create type quality.capa_priority as enum('low', 'medium', 'high', 'critical');

create type quality.effectiveness_result as enum('pending', 'effective', 'not_effective');

create type quality.action_type as enum('corrective', 'preventive', 'containment');

create type quality.action_status as enum('open', 'in_progress', 'completed', 'overdue');

create type quality.risk_category as enum('process', 'product', 'supplier', 'safety', 'compliance');

create type quality.risk_status as enum(
  'identified',
  'mitigating',
  'mitigated',
  'accepted',
  'closed'
);

create type quality.equipment_category as enum(
  'measuring_device',
  'test_equipment',
  'production_tooling',
  'calibration_standard'
);

create type quality.equipment_status as enum(
  'in_service',
  'due',
  'overdue',
  'out_of_service',
  'retired'
);

create type quality.calibration_result as enum('pass', 'fail', 'adjusted');

create type quality.training_status as enum(
  'not_started',
  'in_progress',
  'completed',
  'expired'
);

create type quality.capa_event_type as enum(
  'created',
  'action_added',
  'action_completed',
  'verified',
  'closed',
  'reopened'
);

----------------------------------------------------------------
-- Users replica view
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
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on quality.users to "x-admin",
  "qa-manager",
  "quality-auditor",
  "user";

comment on view quality.users is '{"display": "none"}';

----------------------------------------------------------------
-- Processes
--
-- The ISO 9001 "process approach": every audit, nonconformance, CAPA
-- and risk assessment is scoped to one of these, and each carries a
-- named owner who is accountable for it.
----------------------------------------------------------------
create table quality.processes (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(160) not null,
  description varchar(300),
  category quality.process_category not null default 'core',
  owner_id uuid references supasheet.users (id) on delete set null,
  is_active boolean not null default true,
  open_nonconformance_count integer not null default 0,
  open_capa_count integer not null default 0,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.processes.category is '{
    "progress": false,
    "values": {
        "core": {"variant": "info", "icon": "Workflow"},
        "support": {"variant": "secondary", "icon": "LifeBuoy"},
        "management": {"variant": "default", "icon": "Compass"}
    }
}';

comment on table quality.processes is '{
    "icon": "Workflow",
    "name": "Processes",
    "description": "The process map — who owns what, and how much open quality work sits against each.",
    "collapsible_group": "Governance",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["code", "category", "is_active"]},
        "tabs": ["audits", "nonconformances", "capas", "risk_assessments"]
    },
    "views": [
        {"id": "list", "name": "All Processes", "type": "list", "title": "name", "description": "description", "field_1": "open_nonconformance_count", "field_2": "open_capa_count"},
        {"id": "kanban", "name": "By Category", "type": "kanban", "group": "category", "title": "name", "description": "code", "date": "created_at", "badge": "open_capa_count"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "with_open_work", "name": "Open Quality Work", "filters": [{"id": "open_capa_count", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "category", "owner_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "category", "color", "is_active"]},
            {"id": "ownership", "title": "Ownership", "fields": ["owner_id"]},
            {"id": "position", "title": "Open Work", "fields": {"read": ["open_nonconformance_count", "open_capa_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "users", "on": "owner_id", "alias": "owner", "columns": ["name", "email"]}]
    }
}';

revoke all on table quality.processes
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
delete on table quality.processes to "x-admin";

grant
select
,
  insert,
update on table quality.processes to "qa-manager";

grant
select
  on table quality.processes to "quality-auditor",
  "user";

alter table quality.processes enable row level security;

create policy processes_select on quality.processes for
select
  to authenticated using (true);

create policy processes_insert on quality.processes for insert to authenticated
with
  check (true);

create policy processes_update on quality.processes
for update
  to authenticated using (true)
with
  check (true);

create policy processes_delete on quality.processes for delete to authenticated using (true);

----------------------------------------------------------------
-- Document categories (self-referencing tree)
----------------------------------------------------------------
create table quality.document_categories (
  id uuid primary key default extensions.uuid_generate_v4 (),
  parent_id uuid references quality.document_categories (id) on delete set null,
  code varchar(20) not null unique,
  name varchar(160) not null,
  description varchar(300),
  is_active boolean not null default true,
  document_count integer not null default 0,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint doc_categories_not_own_parent check (id <> parent_id)
);

comment on table quality.document_categories is '{
    "icon": "FolderTree",
    "name": "Document Categories",
    "description": "How the controlled document library is organised.",
    "collapsible_group": "Document Control",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["code", "document_count"]},
        "tabs": ["documents"]
    },
    "views": [
        {"id": "tree", "name": "Category Tree", "type": "tree", "parent": "parent_id", "title": "name", "secondary": "code"},
        {"id": "list", "name": "All Categories", "type": "list", "title": "name", "description": "description", "field_1": "code", "field_2": "document_count"}
    ],
    "fields": {
        "quick_create": ["code", "name", "parent_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "parent_id", "color", "is_active"]},
            {"id": "position", "title": "Position", "fields": {"read": ["document_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "document_categories", "on": "parent_id", "alias": "parent", "columns": ["name", "code"]}]
    }
}';

revoke all on table quality.document_categories
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
delete on table quality.document_categories to "x-admin";

grant
select
,
  insert,
update on table quality.document_categories to "qa-manager";

grant
select
  on table quality.document_categories to "quality-auditor",
  "user";

create index idx_qual_doc_categories_parent_id on quality.document_categories (parent_id);

alter table quality.document_categories enable row level security;

create policy doc_categories_select on quality.document_categories for
select
  to authenticated using (true);

create policy doc_categories_insert on quality.document_categories for insert to authenticated
with
  check (true);

create policy doc_categories_update on quality.document_categories
for update
  to authenticated using (true)
with
  check (true);

create policy doc_categories_delete on quality.document_categories for delete to authenticated using (true);

----------------------------------------------------------------
-- Documents (the controlled document master)
--
-- current_version_id is filled in once a version passes through
-- review and approval and is published effective — see the version
-- table below. The FK is added by ALTER TABLE after that table
-- exists.
----------------------------------------------------------------
create sequence if not exists quality.document_number_seq;

create table quality.documents (
  id uuid primary key default extensions.uuid_generate_v4 (),
  document_number varchar(30) not null unique default (
    'DOC-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('quality.document_number_seq')::text,
      5,
      '0'
    )
  ),
  title varchar(200) not null,
  document_type quality.document_type not null default 'procedure',
  category_id uuid references quality.document_categories (id) on delete set null,
  owner_id uuid references supasheet.users (id) on delete set null,
  department varchar(120),
  status quality.document_status not null default 'active',
  review_cycle_months integer not null default 12,
  next_review_date date,
  current_version_id uuid,
  version_count integer not null default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint documents_review_cycle_positive check (review_cycle_months > 0)
);

comment on column quality.documents.status is '{
    "progress": false,
    "values": {
        "active": {"variant": "success", "icon": "CircleCheck"},
        "obsolete": {"variant": "secondary", "icon": "Archive"}
    }
}';

comment on table quality.documents is '{
    "icon": "FileText",
    "name": "Documents",
    "description": "The controlled document library. Every one of these has a full revision history below it.",
    "collapsible_group": "Document Control",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "title", "badges": ["document_number", "document_type", "status"]},
        "tabs": ["document_versions"]
    },
    "views": [
        {"id": "list", "name": "All Documents", "type": "list", "title": "title", "description": "document_number", "field_1": "document_type", "field_2": "next_review_date"},
        {"id": "kanban", "name": "By Type", "type": "kanban", "group": "document_type", "title": "title", "description": "document_number", "date": "next_review_date", "badge": "status"},
        {"id": "calendar", "name": "Review Calendar", "type": "calendar", "title": "title", "badge": "document_type", "start_date": "next_review_date", "read_only": true}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "review_due", "name": "Review Due", "filters": [{"id": "next_review_date", "value": "today", "operator": "lte"}]}
    ],
    "fields": {
        "quick_create": ["title", "document_type", "category_id", "owner_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": {"create": ["title", "document_type", "category_id", "department", "owner_id"], "update": ["title", "category_id", "department", "owner_id", "status", "review_cycle_months"], "read": ["document_number", "title", "document_type", "category_id", "department", "owner_id", "status", "review_cycle_months"]}},
            {"id": "position", "title": "Position", "fields": {"read": ["current_version_id", "version_count", "next_review_date"]}}
        ]
    },
    "query": {
        "sort": [{"id": "document_number", "desc": true}],
        "join": [
            {"table": "document_categories", "on": "category_id", "columns": ["code", "name"]},
            {"table": "users", "on": "owner_id", "alias": "owner", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table quality.documents
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
delete on table quality.documents to "x-admin";

grant
select
,
  insert,
update on table quality.documents to "qa-manager";

grant
select
  on table quality.documents to "quality-auditor",
  "user";

revoke all on sequence quality.document_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence quality.document_number_seq to "x-admin",
"qa-manager";

create index idx_qual_documents_category_id on quality.documents (category_id);

create index idx_qual_documents_status on quality.documents (status);

alter table quality.documents enable row level security;

create policy documents_select on quality.documents for
select
  to authenticated using (true);

create policy documents_insert on quality.documents for insert to authenticated
with
  check (true);

create policy documents_update on quality.documents
for update
  to authenticated using (true)
with
  check (true);

create policy documents_delete on quality.documents for delete to authenticated using (true);

----------------------------------------------------------------
-- Document versions — the revision history
--
-- Status only moves forward along one path: draft -> in_review ->
-- approved -> effective -> superseded/obsolete (with a document
-- sent back to draft from in_review, or back to in_review from
-- approved, if it fails). The guard below is the whole rulebook;
-- the publish trigger after it is what makes "effective" mean
-- something — it supersedes whatever was effective before.
----------------------------------------------------------------
create table quality.document_versions (
  id uuid primary key default extensions.uuid_generate_v4 (),
  document_id uuid not null references quality.documents (id) on delete cascade,
  version_number varchar(12) not null default 'A',
  status quality.version_status not null default 'draft',
  file supasheet.file,
  change_summary varchar(500),
  author_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  reviewer_id uuid references supasheet.users (id) on delete set null,
  approver_id uuid references supasheet.users (id) on delete set null,
  approved_at timestamptz,
  effective_date date,
  superseded_at timestamptz,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (document_id, version_number)
);

alter table quality.documents
add constraint documents_current_version_fk foreign key (current_version_id) references quality.document_versions (id) on delete set null;

comment on column quality.document_versions.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "in_review": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "info", "icon": "BadgeCheck"},
        "effective": {"variant": "success", "icon": "CircleCheck"},
        "superseded": {"variant": "secondary", "icon": "History"},
        "obsolete": {"variant": "destructive", "icon": "Archive"}
    }
}';

comment on table quality.document_versions is '{
    "icon": "GitBranch",
    "name": "Versions",
    "description": "One row per revision. Only one can ever be effective at a time.",
    "collapsible_group": "Document Control",
    "display": "block",
    "inline_form": true,
    "primary_view": "kanban",
    "detail": {"header": {"title": "version_number", "badges": ["status", "effective_date"]}},
    "views": [
        {"id": "kanban", "name": "Revision Board", "type": "kanban", "group": "status", "title": "version_number", "description": "change_summary", "date": "effective_date", "badge": "status"},
        {"id": "list", "name": "All Versions", "type": "list", "title": "version_number", "description": "change_summary", "field_1": "status", "field_2": "effective_date"}
    ],
    "filter_presets": [
        {"id": "effective", "name": "Effective", "filters": [{"id": "status", "value": "effective", "operator": "eq"}]},
        {"id": "in_review", "name": "In Review", "filters": [{"id": "status", "value": "in_review", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["document_id", "version_number", "file"],
        "sections": [
            {"id": "revision", "title": "Revision", "fields": {"create": ["document_id", "version_number", "file", "change_summary"], "update": ["change_summary", "reviewer_id"], "read": ["document_id", "version_number", "file", "change_summary", "author_id"]}},
            {"id": "state", "title": "State", "fields": {"read": ["status", "reviewer_id", "approver_id", "approved_at", "effective_date", "superseded_at"]}}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "documents", "on": "document_id", "columns": ["document_number", "title"]},
            {"table": "users", "on": "approver_id", "alias": "approver", "columns": ["name", "email"]}
        ]
    }
}';

comment on column quality.document_versions.file is '{"accept": ".pdf,.doc,.docx", "maxFiles": 1, "maxSize": 10485760}';

revoke all on table quality.document_versions
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
delete on table quality.document_versions to "x-admin";

grant
select
,
  insert,
update on table quality.document_versions to "qa-manager";

grant
select
  on table quality.document_versions to "quality-auditor",
  "user";

create index idx_qual_doc_versions_document_id on quality.document_versions (document_id);

create index idx_qual_doc_versions_status on quality.document_versions (status);

alter table quality.document_versions enable row level security;

create policy doc_versions_select on quality.document_versions for
select
  to authenticated using (true);

create policy doc_versions_insert on quality.document_versions for insert to authenticated
with
  check (true);

create policy doc_versions_update on quality.document_versions
for update
  to authenticated using (true)
with
  check (true);

create policy doc_versions_delete on quality.document_versions for delete to authenticated using (true);

create trigger doc_versions_updated_at before
update on quality.document_versions for each row
execute function supasheet.set_updated_at ();

create or replace function quality.document_versions_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_valid boolean;
begin
  if new.status = old.status then
    return new;
  end if;

  v_valid := case old.status
    when 'draft' then new.status = 'in_review'
    when 'in_review' then new.status in ('approved', 'draft')
    when 'approved' then new.status in ('effective', 'in_review')
    when 'effective' then new.status in ('superseded', 'obsolete')
    when 'superseded' then new.status = 'obsolete'
    else false
  end;

  if not v_valid then
    raise exception 'A document version cannot move from % to %.', old.status, new.status
      using hint = 'Versions move draft -> in_review -> approved -> effective -> superseded/obsolete, in that order.';
  end if;

  if new.status = 'approved' then
    new.approver_id := coalesce(new.approver_id, (select auth.uid ()));
    new.approved_at := current_timestamp;
  end if;

  if new.status = 'effective' and new.effective_date is null then
    new.effective_date := current_date;
  end if;

  if new.status = 'superseded' then
    new.superseded_at := current_timestamp;
  end if;

  return new;
end;
$$;

create trigger trg_document_versions_guard before
update of status on quality.document_versions for each row
execute function quality.document_versions_guard ();

-- Publishing a version effective is the one transition with side
-- effects on other rows: it supersedes whatever else was effective
-- for the same document, and rolls the document header forward.
create or replace function quality.document_versions_publish () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = 'effective' and old.status is distinct from 'effective' then
    update quality.document_versions
    set status = 'superseded',
      superseded_at = current_timestamp
    where document_id = new.document_id
      and id <> new.id
      and status = 'effective';

    update quality.documents d
    set current_version_id = new.id,
      next_review_date = (new.effective_date + make_interval (months => d.review_cycle_months))::date,
      updated_at = current_timestamp
    where d.id = new.document_id;
  end if;

  return new;
end;
$$;

create trigger trg_document_versions_publish
after
update of status on quality.document_versions for each row
execute function quality.document_versions_publish ();

create or replace function quality.document_versions_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_document_id uuid := coalesce(new.document_id, old.document_id);
begin
  update quality.documents
  set version_count = (
      select count(*)
      from quality.document_versions
      where document_id = v_document_id
    ),
    updated_at = current_timestamp
  where id = v_document_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_document_versions_rollup
after insert
or delete on quality.document_versions for each row
execute function quality.document_versions_rollup ();

----------------------------------------------------------------
-- Document acknowledgements — read receipts
----------------------------------------------------------------
create table quality.document_acknowledgements (
  id uuid primary key default extensions.uuid_generate_v4 (),
  document_version_id uuid not null references quality.document_versions (id) on delete cascade,
  user_id uuid default auth.uid () references supasheet.users (id) on delete cascade,
  acknowledged_at timestamptz not null default current_timestamp,
  notes varchar(300),
  unique (document_version_id, user_id)
);

comment on table quality.document_acknowledgements is '{
    "icon": "BadgeCheck",
    "name": "Acknowledgements",
    "description": "Who has read and understood this version.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "ack", "title": "Acknowledgement", "fields": ["document_version_id", "user_id", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "acknowledged_at", "desc": true}],
        "join": [
            {"table": "document_versions", "on": "document_version_id", "columns": ["version_number", "status"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table quality.document_acknowledgements
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
delete on table quality.document_acknowledgements to "x-admin",
"qa-manager",
"quality-auditor",
"user";

create index idx_qual_doc_acks_version_id on quality.document_acknowledgements (document_version_id);

create index idx_qual_doc_acks_user_id on quality.document_acknowledgements (user_id);

alter table quality.document_acknowledgements enable row level security;

create policy doc_acks_select on quality.document_acknowledgements for
select
  to authenticated using (true);

create policy doc_acks_insert on quality.document_acknowledgements for insert to authenticated
with
  check (true);

create policy doc_acks_delete on quality.document_acknowledgements for delete to authenticated using (
  user_id = (select auth.uid ())
  or pg_has_role (current_user, 'qa-manager', 'member')
  or pg_has_role (current_user, 'x-admin', 'member')
);

----------------------------------------------------------------
-- Audits
----------------------------------------------------------------
create sequence if not exists quality.audit_number_seq;

create table quality.audits (
  id uuid primary key default extensions.uuid_generate_v4 (),
  audit_number varchar(30) not null unique default (
    'AUD-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('quality.audit_number_seq')::text,
      5,
      '0'
    )
  ),
  audit_type quality.audit_type not null default 'internal',
  process_id uuid references quality.processes (id) on delete set null,
  lead_auditor_id uuid references supasheet.users (id) on delete set null,
  status quality.audit_status not null default 'planned',
  result quality.audit_result not null default 'pending',
  scope varchar(300),
  standard_reference varchar(200),
  planned_date date not null default current_date,
  actual_start_date date,
  actual_end_date date,
  finding_count integer not null default 0,
  open_finding_count integer not null default 0,
  report supasheet.file,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint audits_dates_ordered check (
    actual_end_date is null
    or actual_start_date is null
    or actual_end_date >= actual_start_date
  )
);

comment on column quality.audits.audit_type is '{
    "progress": false,
    "values": {
        "internal": {"variant": "info", "icon": "Building2"},
        "external": {"variant": "warning", "icon": "Globe"},
        "supplier": {"variant": "default", "icon": "Truck"},
        "certification": {"variant": "success", "icon": "Award"}
    }
}';

comment on column quality.audits.status is '{
    "progress": true,
    "values": {
        "planned": {"variant": "secondary", "icon": "CalendarClock"},
        "scheduled": {"variant": "info", "icon": "CalendarCheck"},
        "in_progress": {"variant": "warning", "icon": "Loader"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "closed": {"variant": "secondary", "icon": "Archive"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on column quality.audits.result is '{
    "progress": false,
    "values": {
        "pending": {"variant": "secondary", "icon": "CircleDashed"},
        "pass": {"variant": "success", "icon": "CircleCheck"},
        "minor_findings": {"variant": "info", "icon": "AlertCircle"},
        "major_findings": {"variant": "warning", "icon": "TriangleAlert"},
        "fail": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on table quality.audits is '{
    "icon": "ClipboardCheck",
    "name": "Audits",
    "description": "The audit programme — internal, external, supplier and certification — and what each one turned up.",
    "collapsible_group": "Audits",
    "display": "block",
    "primary_view": "gantt",
    "detail": {
        "header": {"title": "audit_number", "badges": ["status", "audit_type", "result"]},
        "tabs": ["audit_checklist_items", "audit_findings"]
    },
    "views": [
        {"id": "gantt", "name": "Audit Calendar", "type": "gantt", "title": "audit_number", "start_date": "planned_date", "end_date": "actual_end_date", "group": "status", "badge": "audit_type"},
        {"id": "kanban", "name": "Audit Board", "type": "kanban", "group": "status", "title": "audit_number", "description": "scope", "date": "planned_date", "badge": "result"},
        {"id": "list", "name": "All Audits", "type": "list", "title": "audit_number", "description": "scope", "field_1": "status", "field_2": "open_finding_count"}
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["planned", "scheduled", "in_progress"], "operator": "in"}]},
        {"id": "with_findings", "name": "With Open Findings", "filters": [{"id": "open_finding_count", "value": "0", "operator": "gt"}]},
        {"id": "failed", "name": "Failed", "filters": [{"id": "result", "value": "fail", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["audit_type", "process_id", "lead_auditor_id", "planned_date"],
        "sections": [
            {"id": "audit", "title": "Audit", "fields": {"create": ["audit_type", "process_id", "lead_auditor_id", "scope", "standard_reference", "planned_date"], "update": ["lead_auditor_id", "scope", "standard_reference", "status", "actual_start_date", "actual_end_date"], "read": ["audit_type", "process_id", "lead_auditor_id", "scope", "standard_reference", "planned_date", "status"]}},
            {"id": "outcome", "title": "Outcome", "fields": {"read": ["result", "finding_count", "open_finding_count"]}},
            {"id": "extras", "title": "Report & Notes", "collapsible": true, "fields": ["report", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "planned_date", "desc": true}],
        "join": [
            {"table": "processes", "on": "process_id", "columns": ["code", "name"]},
            {"table": "users", "on": "lead_auditor_id", "alias": "lead_auditor", "columns": ["name", "email"]}
        ]
    }
}';

comment on column quality.audits.report is '{"accept": ".pdf", "maxFiles": 3, "maxSize": 10485760}';

revoke all on table quality.audits
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
delete on table quality.audits to "x-admin";

grant
select
,
  insert,
update on table quality.audits to "qa-manager";

grant
select
,
update on table quality.audits to "quality-auditor";

revoke all on sequence quality.audit_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence quality.audit_number_seq to "x-admin",
"qa-manager";

create index idx_qual_audits_process_id on quality.audits (process_id);

create index idx_qual_audits_status on quality.audits (status);

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

create trigger audits_updated_at before
update on quality.audits for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Audit checklist items
----------------------------------------------------------------
create table quality.audit_checklist_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  audit_id uuid not null references quality.audits (id) on delete cascade,
  sequence_number integer,
  criteria varchar(500) not null,
  clause_reference varchar(60),
  response quality.checklist_response not null default 'pending',
  notes varchar(500),
  evidence supasheet.file,
  created_at timestamptz default current_timestamp
);

comment on column quality.audit_checklist_items.response is '{
    "progress": false,
    "values": {
        "pending": {"variant": "secondary", "icon": "CircleDashed"},
        "conformant": {"variant": "success", "icon": "CircleCheck"},
        "nonconformant": {"variant": "destructive", "icon": "CircleX"},
        "not_applicable": {"variant": "secondary", "icon": "MinusCircle"},
        "observation": {"variant": "warning", "icon": "Eye"}
    }
}';

comment on table quality.audit_checklist_items is '{
    "icon": "ListChecks",
    "name": "Checklist",
    "description": "One line per criterion assessed during the audit.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "criterion", "title": "Criterion", "fields": ["audit_id", "sequence_number", "criteria", "clause_reference"]},
            {"id": "response", "title": "Response", "fields": ["response", "notes", "evidence"]}
        ]
    },
    "query": {
        "sort": [{"id": "sequence_number", "desc": false}],
        "join": [{"table": "audits", "on": "audit_id", "columns": ["audit_number", "status"]}]
    }
}';

comment on column quality.audit_checklist_items.evidence is '{"accept": "*", "maxFiles": 3, "maxSize": 10485760}';

revoke all on table quality.audit_checklist_items
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
delete on table quality.audit_checklist_items to "x-admin",
"qa-manager";

grant
select
,
  insert,
update on table quality.audit_checklist_items to "quality-auditor";

create index idx_qual_checklist_audit_id on quality.audit_checklist_items (audit_id);

alter table quality.audit_checklist_items enable row level security;

create policy checklist_select on quality.audit_checklist_items for
select
  to authenticated using (true);

create policy checklist_insert on quality.audit_checklist_items for insert to authenticated
with
  check (true);

create policy checklist_update on quality.audit_checklist_items
for update
  to authenticated using (true)
with
  check (true);

create policy checklist_delete on quality.audit_checklist_items for delete to authenticated using (true);

create or replace function quality.checklist_items_set_number () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.sequence_number is null then
    select coalesce(max(sequence_number), 0) + 10 into new.sequence_number
    from quality.audit_checklist_items
    where audit_id = new.audit_id;
  end if;
  return new;
end;
$$;

create trigger trg_checklist_items_set_number before insert on quality.audit_checklist_items for each row
execute function quality.checklist_items_set_number ();

----------------------------------------------------------------
-- Audit findings
--
-- The close guard is the "no serious finding closes without a CAPA"
-- rule: it looks forward at quality.capas, which is defined further
-- down this file. That is safe — a function body is only checked
-- against the catalogue the first time it runs, and by the time
-- anyone can write to this table both tables already exist.
----------------------------------------------------------------
create table quality.audit_findings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  audit_id uuid not null references quality.audits (id) on delete cascade,
  checklist_item_id uuid references quality.audit_checklist_items (id) on delete set null,
  finding_number integer,
  severity quality.finding_severity not null default 'minor',
  clause_reference varchar(60),
  description varchar(1000) not null,
  status quality.finding_status not null default 'open',
  due_date date,
  closed_at timestamptz,
  closed_by uuid references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (audit_id, finding_number)
);

comment on column quality.audit_findings.severity is '{
    "progress": false,
    "values": {
        "observation": {"variant": "secondary", "icon": "Eye"},
        "minor": {"variant": "info", "icon": "AlertCircle"},
        "major": {"variant": "warning", "icon": "TriangleAlert"},
        "critical": {"variant": "destructive", "icon": "OctagonAlert"}
    }
}';

comment on column quality.audit_findings.status is '{
    "progress": true,
    "values": {
        "open": {"variant": "warning", "icon": "CircleDot"},
        "capa_raised": {"variant": "info", "icon": "ClipboardList"},
        "closed": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on table quality.audit_findings is '{
    "icon": "TriangleAlert",
    "name": "Findings",
    "description": "What the audit turned up. Major and critical findings cannot close without a CAPA raised against them.",
    "collapsible_group": "Audits",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "finding_number", "badges": ["severity", "status"]},
        "tabs": ["capas"]
    },
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "description", "description": "clause_reference", "date": "due_date", "badge": "severity"},
        {"id": "list", "name": "All Findings", "type": "list", "title": "description", "description": "clause_reference", "field_1": "severity", "field_2": "status"}
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": "open", "operator": "eq"}]},
        {"id": "serious", "name": "Major & Critical", "filters": [{"id": "severity", "value": ["major", "critical"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["audit_id", "severity", "description"],
        "sections": [
            {"id": "finding", "title": "Finding", "fields": {"create": ["audit_id", "checklist_item_id", "severity", "clause_reference", "description", "due_date"], "update": ["severity", "description", "due_date", "status"], "read": ["audit_id", "checklist_item_id", "severity", "clause_reference", "description", "due_date", "status"]}},
            {"id": "closure", "title": "Closure", "fields": {"read": ["closed_at", "closed_by"]}}
        ]
    },
    "query": {
        "sort": [{"id": "finding_number", "desc": false}],
        "join": [{"table": "audits", "on": "audit_id", "columns": ["audit_number", "status"]}]
    }
}';

revoke all on table quality.audit_findings
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
delete on table quality.audit_findings to "x-admin",
"qa-manager";

grant
select
,
  insert,
update on table quality.audit_findings to "quality-auditor";

create index idx_qual_findings_audit_id on quality.audit_findings (audit_id);

create index idx_qual_findings_status on quality.audit_findings (status);

alter table quality.audit_findings enable row level security;

create policy findings_select on quality.audit_findings for
select
  to authenticated using (true);

create policy findings_insert on quality.audit_findings for insert to authenticated
with
  check (true);

create policy findings_update on quality.audit_findings
for update
  to authenticated using (true)
with
  check (true);

create policy findings_delete on quality.audit_findings for delete to authenticated using (true);

create or replace function quality.audit_findings_set_number () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.finding_number is null then
    select coalesce(max(finding_number), 0) + 1 into new.finding_number
    from quality.audit_findings
    where audit_id = new.audit_id;
  end if;
  return new;
end;
$$;

create trigger trg_audit_findings_set_number before insert on quality.audit_findings for each row
execute function quality.audit_findings_set_number ();

create or replace function quality.audit_findings_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if new.status = 'closed'
    and old.severity in ('major', 'critical')
    and not exists (
      select 1
      from quality.capas
      where source_audit_finding_id = new.id
        and status <> 'cancelled'
    ) then
    raise exception 'A % finding cannot close without a CAPA raised against it.', old.severity
      using hint = 'Raise a CAPA from this finding first.';
  end if;

  if new.status = 'closed' then
    new.closed_at := current_timestamp;
    new.closed_by := (select auth.uid ());
  end if;

  return new;
end;
$$;

create trigger trg_audit_findings_guard before
update of status on quality.audit_findings for each row
execute function quality.audit_findings_guard ();

create or replace function quality.audit_findings_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_audit_id uuid := coalesce(new.audit_id, old.audit_id);
begin
  update quality.audits a
  set finding_count = x.n,
    open_finding_count = x.open_n,
    result = case
      when x.n = 0 then a.result
      when x.critical_n > 0 then 'fail'::quality.audit_result
      when x.major_n > 0 then 'major_findings'::quality.audit_result
      else 'minor_findings'::quality.audit_result
    end
  from (
    select
      count(*) as n,
      count(*) filter (where status <> 'closed') as open_n,
      count(*) filter (where severity = 'major') as major_n,
      count(*) filter (where severity = 'critical') as critical_n
    from quality.audit_findings
    where audit_id = v_audit_id
  ) x
  where a.id = v_audit_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_audit_findings_rollup
after insert
or delete
or
update on quality.audit_findings for each row
execute function quality.audit_findings_rollup ();

----------------------------------------------------------------
-- Nonconformances
--
-- Enterprise-wide: anything that did not meet requirements, from
-- any source, anywhere in the business. Not to be confused with
-- manufacturing.ncrs, which is scoped to one works order's output —
-- this table does not know what a lot or a production order is.
----------------------------------------------------------------
create sequence if not exists quality.nc_number_seq;

create table quality.nonconformances (
  id uuid primary key default extensions.uuid_generate_v4 (),
  nc_number varchar(30) not null unique default (
    'NCR-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('quality.nc_number_seq')::text,
      5,
      '0'
    )
  ),
  source quality.nc_source not null default 'internal_report',
  source_audit_finding_id uuid references quality.audit_findings (id) on delete set null,
  process_id uuid references quality.processes (id) on delete set null,
  reported_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  title varchar(300) not null,
  description supasheet.RICH_TEXT,
  severity quality.nc_severity not null default 'minor',
  status quality.nc_status not null default 'open',
  root_cause supasheet.RICH_TEXT,
  containment_action varchar(500),
  closed_at timestamptz,
  closed_by uuid references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.nonconformances.source is '{
    "progress": false,
    "values": {
        "audit_finding": {"variant": "info", "icon": "ClipboardCheck"},
        "customer_complaint": {"variant": "warning", "icon": "MessageSquareWarning"},
        "internal_report": {"variant": "secondary", "icon": "FileWarning"},
        "supplier_issue": {"variant": "default", "icon": "Truck"},
        "inspection": {"variant": "info", "icon": "Search"},
        "other": {"variant": "secondary", "icon": "CircleHelp"}
    }
}';

comment on column quality.nonconformances.severity is '{
    "progress": false,
    "values": {
        "minor": {"variant": "info", "icon": "AlertCircle"},
        "major": {"variant": "warning", "icon": "TriangleAlert"},
        "critical": {"variant": "destructive", "icon": "OctagonAlert"}
    }
}';

comment on column quality.nonconformances.status is '{
    "progress": true,
    "values": {
        "open": {"variant": "warning", "icon": "CircleDot"},
        "under_investigation": {"variant": "info", "icon": "Search"},
        "capa_raised": {"variant": "default", "icon": "ClipboardList"},
        "closed": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on table quality.nonconformances is '{
    "icon": "FileWarning",
    "name": "Nonconformances",
    "description": "Anything that did not meet requirements, from any source, anywhere in the business.",
    "collapsible_group": "Issues",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "nc_number", "badges": ["severity", "status", "source"]},
        "tabs": ["capas"]
    },
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "nc_number", "description": "title", "date": "created_at", "badge": "severity"},
        {"id": "list", "name": "All Nonconformances", "type": "list", "title": "title", "description": "nc_number", "field_1": "status", "field_2": "severity"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "Reported By Me", "filters": [{"id": "reported_by", "value": "me", "operator": "eq"}]},
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["open", "under_investigation"], "operator": "in"}]},
        {"id": "serious", "name": "Major & Critical", "filters": [{"id": "severity", "value": ["major", "critical"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["title", "source", "severity", "process_id"],
        "sections": [
            {"id": "issue", "title": "Issue", "fields": {"create": ["title", "description", "source", "source_audit_finding_id", "process_id", "severity"], "update": ["title", "description", "severity", "status"], "read": ["title", "description", "source", "source_audit_finding_id", "process_id", "severity", "reported_by", "status"]}},
            {"id": "investigation", "title": "Investigation", "fields": {"update": ["root_cause", "containment_action"], "read": ["root_cause", "containment_action"]}},
            {"id": "closure", "title": "Closure", "fields": {"read": ["closed_at", "closed_by"]}}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "processes", "on": "process_id", "columns": ["code", "name"]},
            {"table": "users", "on": "reported_by", "alias": "reporter", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table quality.nonconformances
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
delete on table quality.nonconformances to "x-admin";

grant
select
,
  insert,
update on table quality.nonconformances to "qa-manager";

grant
select
,
  insert on table quality.nonconformances to "quality-auditor";

grant
select
,
  insert on table quality.nonconformances to "user";

revoke all on sequence quality.nc_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence quality.nc_number_seq to "x-admin",
"qa-manager",
"quality-auditor",
"user";

create index idx_qual_nc_process_id on quality.nonconformances (process_id);

create index idx_qual_nc_status on quality.nonconformances (status);

create index idx_qual_nc_reported_by on quality.nonconformances (reported_by);

alter table quality.nonconformances enable row level security;

create policy nc_select on quality.nonconformances for
select
  to authenticated using (
    reported_by = (select auth.uid ())
    or pg_has_role (current_user, 'qa-manager', 'member')
    or pg_has_role (current_user, 'quality-auditor', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  );

create policy nc_insert on quality.nonconformances for insert to authenticated
with
  check (true);

create policy nc_update on quality.nonconformances
for update
  to authenticated using (
    pg_has_role (current_user, 'qa-manager', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy nc_delete on quality.nonconformances for delete to authenticated using (true);

create trigger nc_updated_at before
update on quality.nonconformances for each row
execute function supasheet.set_updated_at ();

create or replace function quality.nonconformances_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_process_id uuid;
begin
  for v_process_id in
    select distinct v from unnest(array[new.process_id, old.process_id]) as t (v)
    where v is not null
  loop
    update quality.processes
    set open_nonconformance_count = (
        select count(*)
        from quality.nonconformances
        where process_id = v_process_id
          and status <> 'closed'
      ),
      updated_at = current_timestamp
    where id = v_process_id;
  end loop;

  return coalesce(new, old);
end;
$$;

create trigger trg_nonconformances_rollup
after insert
or delete
or
update of process_id,
status on quality.nonconformances for each row
execute function quality.nonconformances_rollup ();

----------------------------------------------------------------
-- Customer complaints
----------------------------------------------------------------
create sequence if not exists quality.complaint_number_seq;

create table quality.customer_complaints (
  id uuid primary key default extensions.uuid_generate_v4 (),
  complaint_number varchar(30) not null unique default (
    'COMP-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('quality.complaint_number_seq')::text,
      5,
      '0'
    )
  ),
  customer_name varchar(200) not null,
  contact_email supasheet.EMAIL,
  product_or_service varchar(200),
  description supasheet.RICH_TEXT not null,
  severity quality.nc_severity not null default 'minor',
  received_date date not null default current_date,
  status quality.complaint_status not null default 'open',
  nonconformance_id uuid references quality.nonconformances (id) on delete set null,
  resolution supasheet.RICH_TEXT,
  resolved_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.customer_complaints.status is '{
    "progress": true,
    "values": {
        "open": {"variant": "warning", "icon": "CircleDot"},
        "investigating": {"variant": "info", "icon": "Search"},
        "resolved": {"variant": "success", "icon": "CircleCheck"},
        "closed": {"variant": "secondary", "icon": "Archive"}
    }
}';

comment on table quality.customer_complaints is '{
    "icon": "MessageSquareWarning",
    "name": "Customer Complaints",
    "description": "What customers told us, and whether it turned into a formal nonconformance.",
    "collapsible_group": "Issues",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "complaint_number", "badges": ["status", "severity"]}
    },
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "customer_name", "description": "product_or_service", "date": "received_date", "badge": "severity"},
        {"id": "calendar", "name": "Received", "type": "calendar", "title": "customer_name", "badge": "status", "start_date": "received_date", "read_only": true},
        {"id": "list", "name": "All Complaints", "type": "list", "title": "customer_name", "description": "product_or_service", "field_1": "status", "field_2": "severity"}
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["open", "investigating"], "operator": "in"}]},
        {"id": "unlinked", "name": "No Nonconformance Yet", "filters": [{"id": "nonconformance_id", "value": "", "operator": "is"}]}
    ],
    "fields": {
        "quick_create": ["customer_name", "product_or_service", "severity", "description"],
        "sections": [
            {"id": "complaint", "title": "Complaint", "fields": {"create": ["customer_name", "contact_email", "product_or_service", "received_date", "severity", "description"], "update": ["status", "nonconformance_id"], "read": ["customer_name", "contact_email", "product_or_service", "received_date", "severity", "description", "status", "nonconformance_id"]}},
            {"id": "resolution", "title": "Resolution", "fields": {"update": ["resolution"], "read": ["resolution", "resolved_at", "closed_at"]}}
        ]
    },
    "query": {
        "sort": [{"id": "received_date", "desc": true}],
        "join": [{"table": "nonconformances", "on": "nonconformance_id", "columns": ["nc_number", "status"]}]
    }
}';

revoke all on table quality.customer_complaints
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
delete on table quality.customer_complaints to "x-admin";

grant
select
,
  insert,
update on table quality.customer_complaints to "qa-manager";

grant
select
  on table quality.customer_complaints to "quality-auditor";

revoke all on sequence quality.complaint_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence quality.complaint_number_seq to "x-admin",
"qa-manager";

create index idx_qual_complaints_status on quality.customer_complaints (status);

create index idx_qual_complaints_nc_id on quality.customer_complaints (nonconformance_id);

alter table quality.customer_complaints enable row level security;

create policy complaints_select on quality.customer_complaints for
select
  to authenticated using (true);

create policy complaints_insert on quality.customer_complaints for insert to authenticated
with
  check (true);

create policy complaints_update on quality.customer_complaints
for update
  to authenticated using (true)
with
  check (true);

create policy complaints_delete on quality.customer_complaints for delete to authenticated using (true);

create trigger complaints_updated_at before
update on quality.customer_complaints for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- CAPAs — the corrective/preventive action engine
--
-- The close guard is the headline rule: every action must be
-- completed AND the effectiveness check must have come back
-- `effective` before status can reach `closed`. Nothing else in
-- this schema is allowed to shortcut it.
----------------------------------------------------------------
create sequence if not exists quality.capa_number_seq;

create table quality.capas (
  id uuid primary key default extensions.uuid_generate_v4 (),
  capa_number varchar(30) not null unique default (
    'CAPA-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('quality.capa_number_seq')::text,
      5,
      '0'
    )
  ),
  capa_type quality.capa_type not null default 'corrective',
  source quality.capa_source not null default 'other',
  source_audit_finding_id uuid references quality.audit_findings (id) on delete set null,
  source_nonconformance_id uuid references quality.nonconformances (id) on delete set null,
  source_complaint_id uuid references quality.customer_complaints (id) on delete set null,
  process_id uuid references quality.processes (id) on delete set null,
  title varchar(300) not null,
  description supasheet.RICH_TEXT,
  root_cause supasheet.RICH_TEXT,
  priority quality.capa_priority not null default 'medium',
  status quality.capa_status not null default 'open',
  owner_id uuid references supasheet.users (id) on delete set null,
  opened_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  due_date date,
  action_count integer not null default 0,
  completed_action_count integer not null default 0,
  effectiveness_check_date date,
  effectiveness_result quality.effectiveness_result not null default 'pending',
  verification_notes varchar(1000),
  closed_at timestamptz,
  closed_by uuid references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.capas.capa_type is '{
    "progress": false,
    "values": {
        "corrective": {"variant": "warning", "icon": "Wrench"},
        "preventive": {"variant": "info", "icon": "ShieldCheck"},
        "both": {"variant": "default", "icon": "ShieldAlert"}
    }
}';

comment on column quality.capas.priority is '{
    "progress": false,
    "values": {
        "low": {"variant": "secondary", "icon": "ArrowDown"},
        "medium": {"variant": "info", "icon": "Minus"},
        "high": {"variant": "warning", "icon": "ArrowUp"},
        "critical": {"variant": "destructive", "icon": "TriangleAlert"}
    }
}';

comment on column quality.capas.status is '{
    "progress": true,
    "values": {
        "open": {"variant": "secondary", "icon": "CircleDot"},
        "root_cause_analysis": {"variant": "info", "icon": "Search"},
        "action_planned": {"variant": "info", "icon": "ListChecks"},
        "in_progress": {"variant": "warning", "icon": "Loader"},
        "pending_verification": {"variant": "warning", "icon": "Hourglass"},
        "verified": {"variant": "default", "icon": "BadgeCheck"},
        "closed": {"variant": "success", "icon": "CircleCheck"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on column quality.capas.effectiveness_result is '{
    "progress": false,
    "values": {
        "pending": {"variant": "secondary", "icon": "CircleDashed"},
        "effective": {"variant": "success", "icon": "CircleCheck"},
        "not_effective": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on table quality.capas is '{
    "icon": "ClipboardList",
    "name": "CAPAs",
    "description": "Corrective and preventive actions. Nothing closes here until it is proven to have worked.",
    "collapsible_group": "Issues",
    "display": "block",
    "primary_view": "gantt",
    "detail": {
        "header": {"title": "capa_number", "badges": ["status", "priority", "capa_type"]},
        "tabs": ["capa_actions"],
        "timelines": ["capa_events"]
    },
    "views": [
        {"id": "gantt", "name": "CAPA Timeline", "type": "gantt", "title": "capa_number", "start_date": "created_at", "end_date": "due_date", "group": "status", "badge": "priority"},
        {"id": "kanban", "name": "CAPA Board", "type": "kanban", "group": "status", "title": "title", "description": "capa_number", "date": "due_date", "badge": "priority"},
        {"id": "list", "name": "All CAPAs", "type": "list", "title": "title", "description": "capa_number", "field_1": "status", "field_2": "due_date"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "Owned By Me", "filters": [{"id": "owner_id", "value": "me", "operator": "eq"}]},
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["closed", "cancelled"], "operator": "not.in"}]},
        {"id": "overdue", "name": "Overdue", "filters": [{"id": "due_date", "value": "today", "operator": "lt"}, {"id": "status", "value": ["closed", "cancelled"], "operator": "not.in"}]},
        {"id": "awaiting_verification", "name": "Awaiting Verification", "filters": [{"id": "status", "value": "pending_verification", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["title", "capa_type", "process_id", "owner_id", "due_date"],
        "sections": [
            {"id": "capa", "title": "CAPA", "fields": {"create": ["title", "description", "capa_type", "source", "source_audit_finding_id", "source_nonconformance_id", "source_complaint_id", "process_id", "priority", "owner_id", "due_date"], "update": ["title", "description", "priority", "owner_id", "due_date", "status"], "read": ["title", "description", "capa_type", "source", "process_id", "priority", "opened_by", "due_date", "status"]}},
            {"id": "analysis", "title": "Root Cause", "fields": {"update": ["root_cause"], "read": ["root_cause"]}},
            {"id": "verification", "title": "Verification", "fields": {"update": ["effectiveness_check_date", "effectiveness_result", "verification_notes"], "read": ["effectiveness_check_date", "effectiveness_result", "verification_notes"]}},
            {"id": "progress", "title": "Action Progress", "fields": {"read": ["action_count", "completed_action_count"]}},
            {"id": "closure", "title": "Closure", "fields": {"read": ["closed_at", "closed_by"]}}
        ],
        "behavior": {
            "effectiveness_check_date": {"visible": [{"id": "status", "operator": "in", "value": ["pending_verification", "verified", "closed"]}]}
        }
    },
    "query": {
        "sort": [{"id": "due_date", "desc": false}],
        "join": [
            {"table": "processes", "on": "process_id", "columns": ["code", "name"]},
            {"table": "users", "on": "owner_id", "alias": "owner", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table quality.capas
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
delete on table quality.capas to "x-admin";

grant
select
,
  insert,
update on table quality.capas to "qa-manager";

grant
select
,
  insert on table quality.capas to "quality-auditor";

grant
select
,
update on table quality.capas to "user";

revoke all on sequence quality.capa_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence quality.capa_number_seq to "x-admin",
"qa-manager",
"quality-auditor";

create index idx_qual_capas_process_id on quality.capas (process_id);

create index idx_qual_capas_owner_id on quality.capas (owner_id);

create index idx_qual_capas_status on quality.capas (status);

alter table quality.capas enable row level security;

create policy capas_select on quality.capas for
select
  to authenticated using (true);

create policy capas_insert on quality.capas for insert to authenticated
with
  check (true);

create policy capas_update on quality.capas
for update
  to authenticated using (
    owner_id = (select auth.uid ())
    or pg_has_role (current_user, 'qa-manager', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy capas_delete on quality.capas for delete to authenticated using (true);

create or replace function quality.capas_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if new.status = 'closed' then
    if new.action_count = 0
      or new.completed_action_count < new.action_count then
      raise exception 'Every action must be completed before a CAPA can close (% of % done).', new.completed_action_count, new.action_count;
    end if;

    if new.effectiveness_result <> 'effective' then
      raise exception 'A CAPA cannot close until its effectiveness check has come back effective.'
        using hint = 'Record the effectiveness check first.';
    end if;

    new.closed_at := current_timestamp;
    new.closed_by := (select auth.uid ());
  end if;

  return new;
end;
$$;

create trigger trg_capas_guard before
update of status on quality.capas for each row
execute function quality.capas_guard ();

-- Raising a CAPA against a finding, nonconformance or complaint moves
-- that source record forward — the paper trail links itself.
create or replace function quality.capas_link_source () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.source_audit_finding_id is not null then
    update quality.audit_findings
    set status = 'capa_raised'
    where id = new.source_audit_finding_id
      and status = 'open';
  end if;

  if new.source_nonconformance_id is not null then
    update quality.nonconformances
    set status = 'capa_raised'
    where id = new.source_nonconformance_id
      and status in ('open', 'under_investigation');
  end if;

  if new.source_complaint_id is not null then
    update quality.customer_complaints
    set status = 'investigating'
    where id = new.source_complaint_id
      and status = 'open';
  end if;

  return new;
end;
$$;

create trigger trg_capas_link_source
after insert on quality.capas for each row
execute function quality.capas_link_source ();

create or replace function quality.capas_rollup_process () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_process_id uuid;
begin
  for v_process_id in
    select distinct v from unnest(array[new.process_id, old.process_id]) as t (v)
    where v is not null
  loop
    update quality.processes
    set open_capa_count = (
        select count(*)
        from quality.capas
        where process_id = v_process_id
          and status not in ('closed', 'cancelled')
      ),
      updated_at = current_timestamp
    where id = v_process_id;
  end loop;

  return coalesce(new, old);
end;
$$;

create trigger trg_capas_rollup_process
after insert
or delete
or
update of process_id,
status on quality.capas for each row
execute function quality.capas_rollup_process ();

----------------------------------------------------------------
-- CAPA actions
----------------------------------------------------------------
create table quality.capa_actions (
  id uuid primary key default extensions.uuid_generate_v4 (),
  capa_id uuid not null references quality.capas (id) on delete cascade,
  action_type quality.action_type not null default 'corrective',
  description varchar(500) not null,
  assigned_to uuid references supasheet.users (id) on delete set null,
  due_date date,
  status quality.action_status not null default 'open',
  completed_at timestamptz,
  completed_by uuid references supasheet.users (id) on delete set null,
  evidence supasheet.file,
  created_at timestamptz default current_timestamp
);

comment on column quality.capa_actions.action_type is '{
    "progress": false,
    "values": {
        "corrective": {"variant": "warning", "icon": "Wrench"},
        "preventive": {"variant": "info", "icon": "ShieldCheck"},
        "containment": {"variant": "destructive", "icon": "ShieldAlert"}
    }
}';

comment on column quality.capa_actions.status is '{
    "progress": true,
    "values": {
        "open": {"variant": "secondary", "icon": "CircleDot"},
        "in_progress": {"variant": "warning", "icon": "Loader"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "overdue": {"variant": "destructive", "icon": "TriangleAlert"}
    }
}';

comment on table quality.capa_actions is '{
    "icon": "ListChecks",
    "name": "Actions",
    "description": "The individual steps that make up a CAPA. Every one of these has to be completed before the CAPA can close.",
    "collapsible_group": "Issues",
    "display": "block",
    "inline_form": true,
    "primary_view": "kanban",
    "detail": {"header": {"title": "description", "badges": ["action_type", "status"]}},
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "description", "description": "action_type", "date": "due_date", "badge": "action_type"},
        {"id": "calendar", "name": "Due Dates", "type": "calendar", "title": "description", "badge": "status", "start_date": "due_date", "read_only": true},
        {"id": "list", "name": "All Actions", "type": "list", "title": "description", "description": "action_type", "field_1": "status", "field_2": "due_date"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "Assigned To Me", "filters": [{"id": "assigned_to", "value": "me", "operator": "eq"}]},
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["open", "in_progress", "overdue"], "operator": "in"}]},
        {"id": "overdue", "name": "Overdue", "filters": [{"id": "status", "value": "overdue", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["capa_id", "action_type", "description", "assigned_to", "due_date"],
        "sections": [
            {"id": "action", "title": "Action", "fields": {"create": ["capa_id", "action_type", "description", "assigned_to", "due_date"], "update": ["description", "assigned_to", "due_date", "status", "evidence"], "read": ["capa_id", "action_type", "description", "assigned_to", "due_date", "status"]}},
            {"id": "completion", "title": "Completion", "fields": {"read": ["completed_at", "completed_by", "evidence"]}}
        ]
    },
    "query": {
        "sort": [{"id": "due_date", "desc": false}],
        "join": [
            {"table": "capas", "on": "capa_id", "columns": ["capa_number", "title", "status"]},
            {"table": "users", "on": "assigned_to", "columns": ["name", "email"]}
        ]
    }
}';

comment on column quality.capa_actions.evidence is '{"accept": "*", "maxFiles": 5, "maxSize": 10485760}';

revoke all on table quality.capa_actions
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
delete on table quality.capa_actions to "x-admin";

grant
select
,
  insert,
update on table quality.capa_actions to "qa-manager";

grant
select
,
  insert on table quality.capa_actions to "quality-auditor";

grant
select
,
update on table quality.capa_actions to "user";

create index idx_qual_capa_actions_capa_id on quality.capa_actions (capa_id);

create index idx_qual_capa_actions_assigned_to on quality.capa_actions (assigned_to);

alter table quality.capa_actions enable row level security;

create policy capa_actions_select on quality.capa_actions for
select
  to authenticated using (true);

create policy capa_actions_insert on quality.capa_actions for insert to authenticated
with
  check (true);

create policy capa_actions_update on quality.capa_actions
for update
  to authenticated using (
    assigned_to = (select auth.uid ())
    or pg_has_role (current_user, 'qa-manager', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy capa_actions_delete on quality.capa_actions for delete to authenticated using (true);

create or replace function quality.capa_actions_guard () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    new.completed_at := current_timestamp;
    new.completed_by := (select auth.uid ());
  end if;

  if new.status in ('open', 'in_progress')
    and new.due_date is not null
    and new.due_date < current_date then
    new.status := 'overdue';
  end if;

  return new;
end;
$$;

create trigger trg_capa_actions_guard before insert
or
update on quality.capa_actions for each row
execute function quality.capa_actions_guard ();

create or replace function quality.capa_actions_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_capa_id uuid := coalesce(new.capa_id, old.capa_id);
begin
  update quality.capas c
  set action_count = x.n,
    completed_action_count = x.completed_n,
    updated_at = current_timestamp
  from (
    select
      count(*) as n,
      count(*) filter (where status = 'completed') as completed_n
    from quality.capa_actions
    where capa_id = v_capa_id
  ) x
  where c.id = v_capa_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_capa_actions_rollup
after insert
or delete
or
update on quality.capa_actions for each row
execute function quality.capa_actions_rollup ();

----------------------------------------------------------------
-- CAPA events (trigger-populated timeline)
----------------------------------------------------------------
create table quality.capa_events (
  id uuid primary key default extensions.uuid_generate_v4 (),
  capa_id uuid not null references quality.capas (id) on delete cascade,
  event_type quality.capa_event_type not null,
  title varchar(255) not null,
  metadata jsonb,
  actor_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  occurred_at timestamptz not null default current_timestamp
);

comment on column quality.capa_events.event_type is '{
    "progress": false,
    "values": {
        "created": {"variant": "info", "icon": "Sparkles"},
        "action_added": {"variant": "secondary", "icon": "ListPlus"},
        "action_completed": {"variant": "success", "icon": "CircleCheck"},
        "verified": {"variant": "default", "icon": "BadgeCheck"},
        "closed": {"variant": "success", "icon": "Archive"},
        "reopened": {"variant": "destructive", "icon": "RotateCcw"}
    }
}';

comment on table quality.capa_events is '{
    "icon": "History",
    "name": "CAPA History",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "event", "title": "Event", "fields": ["capa_id", "event_type", "title", "metadata", "actor_id", "occurred_at"]}
        ]
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [{"table": "users", "on": "actor_id", "alias": "actor", "columns": ["name", "email"]}]
    }
}';

revoke all on table quality.capa_events
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on table quality.capa_events to "x-admin",
  "qa-manager",
  "quality-auditor",
  "user";

create index idx_qual_capa_events_capa_id on quality.capa_events (capa_id);

create index idx_qual_capa_events_occurred_at on quality.capa_events (occurred_at desc);

alter table quality.capa_events enable row level security;

create policy capa_events_select on quality.capa_events for
select
  to authenticated using (true);

create or replace function quality.capas_log_event () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into quality.capa_events (capa_id, event_type, title, actor_id)
    values (new.id, 'created', 'CAPA opened', (select auth.uid ()));
  elsif new.status is distinct from old.status and new.status = 'verified' then
    insert into quality.capa_events (capa_id, event_type, title, actor_id)
    values (new.id, 'verified', 'Effectiveness verified', (select auth.uid ()));
  elsif new.status is distinct from old.status and new.status = 'closed' then
    insert into quality.capa_events (capa_id, event_type, title, actor_id)
    values (new.id, 'closed', 'CAPA closed', (select auth.uid ()));
  elsif new.status is distinct from old.status
    and new.status = 'open'
    and old.status = 'closed' then
    insert into quality.capa_events (capa_id, event_type, title, actor_id)
    values (new.id, 'reopened', 'CAPA reopened', (select auth.uid ()));
  end if;

  return new;
end;
$$;

create trigger trg_capas_log_event
after insert
or
update of status on quality.capas for each row
execute function quality.capas_log_event ();

create or replace function quality.capa_actions_log_event () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into quality.capa_events (capa_id, event_type, title, actor_id)
    values (new.capa_id, 'action_added', 'Action added: ' || new.description, (select auth.uid ()));
  elsif new.status = 'completed' and old.status is distinct from 'completed' then
    insert into quality.capa_events (capa_id, event_type, title, actor_id)
    values (new.capa_id, 'action_completed', 'Action completed: ' || new.description, (select auth.uid ()));
  end if;

  return new;
end;
$$;

create trigger trg_capa_actions_log_event
after insert
or
update of status on quality.capa_actions for each row
execute function quality.capa_actions_log_event ();

----------------------------------------------------------------
-- Risk assessments (FMEA-lite)
--
-- rpn is a product, not an opinion — severity x occurrence x
-- detection, computed on every write.
----------------------------------------------------------------
create sequence if not exists quality.risk_number_seq;

create table quality.risk_assessments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  risk_number varchar(30) not null unique default (
    'RISK-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('quality.risk_number_seq')::text,
      5,
      '0'
    )
  ),
  title varchar(300) not null,
  description supasheet.RICH_TEXT,
  category quality.risk_category not null default 'process',
  process_id uuid references quality.processes (id) on delete set null,
  severity integer not null default 1,
  occurrence integer not null default 1,
  detection integer not null default 1,
  rpn integer not null default 1,
  mitigation_plan supasheet.RICH_TEXT,
  owner_id uuid references supasheet.users (id) on delete set null,
  status quality.risk_status not null default 'identified',
  review_date date,
  capa_id uuid references quality.capas (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint risk_scores_range check (
    severity between 1 and 10
    and occurrence between 1 and 10
    and detection between 1 and 10
  )
);

comment on column quality.risk_assessments.category is '{
    "progress": false,
    "values": {
        "process": {"variant": "info", "icon": "Workflow"},
        "product": {"variant": "default", "icon": "Package"},
        "supplier": {"variant": "secondary", "icon": "Truck"},
        "safety": {"variant": "destructive", "icon": "ShieldAlert"},
        "compliance": {"variant": "warning", "icon": "Scale"}
    }
}';

comment on column quality.risk_assessments.status is '{
    "progress": true,
    "values": {
        "identified": {"variant": "secondary", "icon": "CircleDot"},
        "mitigating": {"variant": "warning", "icon": "Loader"},
        "mitigated": {"variant": "success", "icon": "ShieldCheck"},
        "accepted": {"variant": "info", "icon": "CircleCheck"},
        "closed": {"variant": "secondary", "icon": "Archive"}
    }
}';

comment on table quality.risk_assessments is '{
    "icon": "ShieldAlert",
    "name": "Risk Assessments",
    "description": "FMEA-style risk scoring — severity, occurrence and detection multiply into a risk priority number nobody types by hand.",
    "collapsible_group": "Issues",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "title", "badges": ["category", "status", "rpn"]},
        "tabs": ["capas"]
    },
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "title", "description": "risk_number", "date": "review_date", "badge": "rpn"},
        {"id": "list", "name": "All Risks", "type": "list", "title": "title", "description": "risk_number", "field_1": "category", "field_2": "rpn"}
    ],
    "filter_presets": [
        {"id": "high_rpn", "name": "High RPN (100+)", "filters": [{"id": "rpn", "value": "100", "operator": "gte"}]},
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["identified", "mitigating"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["title", "category", "process_id", "severity", "occurrence", "detection"],
        "sections": [
            {"id": "risk", "title": "Risk", "fields": {"create": ["title", "description", "category", "process_id", "owner_id"], "update": ["title", "description", "status", "review_date", "capa_id"], "read": ["title", "description", "category", "process_id", "owner_id", "status", "review_date", "capa_id"]}},
            {"id": "scoring", "title": "Scoring", "fields": {"create": ["severity", "occurrence", "detection"], "update": ["severity", "occurrence", "detection"], "read": ["severity", "occurrence", "detection", "rpn"]}},
            {"id": "mitigation", "title": "Mitigation", "fields": ["mitigation_plan"]}
        ],
        "metadata": {
            "rpn": {"description": "Severity x occurrence x detection, 1-1000. Recomputed automatically whenever any of the three scores changes."}
        }
    },
    "query": {
        "sort": [{"id": "rpn", "desc": true}],
        "join": [
            {"table": "processes", "on": "process_id", "columns": ["code", "name"]},
            {"table": "capas", "on": "capa_id", "columns": ["capa_number", "status"]}
        ]
    }
}';

comment on column quality.risk_assessments.rpn is '{"name": "RPN", "aggregate": "avg"}';

revoke all on table quality.risk_assessments
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
delete on table quality.risk_assessments to "x-admin";

grant
select
,
  insert,
update on table quality.risk_assessments to "qa-manager";

grant
select
,
  insert on table quality.risk_assessments to "quality-auditor";

revoke all on sequence quality.risk_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence quality.risk_number_seq to "x-admin",
"qa-manager",
"quality-auditor";

create index idx_qual_risk_process_id on quality.risk_assessments (process_id);

create index idx_qual_risk_status on quality.risk_assessments (status);

alter table quality.risk_assessments enable row level security;

create policy risk_select on quality.risk_assessments for
select
  to authenticated using (true);

create policy risk_insert on quality.risk_assessments for insert to authenticated
with
  check (true);

create policy risk_update on quality.risk_assessments
for update
  to authenticated using (true)
with
  check (true);

create policy risk_delete on quality.risk_assessments for delete to authenticated using (true);

create trigger risk_updated_at before
update on quality.risk_assessments for each row
execute function supasheet.set_updated_at ();

create or replace function quality.risk_assessments_set_rpn () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  new.rpn := new.severity * new.occurrence * new.detection;
  return new;
end;
$$;

create trigger trg_risk_assessments_set_rpn before insert
or
update on quality.risk_assessments for each row
execute function quality.risk_assessments_set_rpn ();

----------------------------------------------------------------
-- Equipment
--
-- Calibration status is derived, never typed — the same is_expired
-- pattern the procurement example uses for supplier compliance
-- documents, applied here to measuring and test equipment.
----------------------------------------------------------------
create sequence if not exists quality.equipment_number_seq;

create table quality.equipment (
  id uuid primary key default extensions.uuid_generate_v4 (),
  equipment_number varchar(30) not null unique default (
    'EQP-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('quality.equipment_number_seq')::text,
      5,
      '0'
    )
  ),
  name varchar(200) not null,
  category quality.equipment_category not null default 'measuring_device',
  serial_number varchar(80),
  location varchar(160),
  custodian_id uuid references supasheet.users (id) on delete set null,
  calibration_frequency_days integer not null default 365,
  last_calibrated_on date,
  next_calibration_due date,
  status quality.equipment_status not null default 'in_service',
  is_overdue boolean not null default false,
  photo supasheet.file,
  certificate supasheet.file,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint equipment_frequency_positive check (calibration_frequency_days > 0)
);

comment on column quality.equipment.category is '{
    "progress": false,
    "values": {
        "measuring_device": {"variant": "info", "icon": "Ruler"},
        "test_equipment": {"variant": "default", "icon": "TestTube"},
        "production_tooling": {"variant": "secondary", "icon": "Wrench"},
        "calibration_standard": {"variant": "success", "icon": "BadgeCheck"}
    }
}';

comment on column quality.equipment.status is '{
    "progress": true,
    "values": {
        "in_service": {"variant": "success", "icon": "CircleCheck"},
        "due": {"variant": "warning", "icon": "Clock"},
        "overdue": {"variant": "destructive", "icon": "TriangleAlert"},
        "out_of_service": {"variant": "secondary", "icon": "CircleSlash"},
        "retired": {"variant": "secondary", "icon": "Archive"}
    }
}';

comment on table quality.equipment is '{
    "icon": "Ruler",
    "name": "Equipment",
    "description": "Measuring and test equipment, and whether its calibration is current.",
    "collapsible_group": "Calibration",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "name", "badges": ["category", "status"]},
        "tabs": ["calibration_records"]
    },
    "views": [
        {"id": "gallery", "name": "Asset Photos", "type": "gallery", "cover": "photo", "title": "name", "description": "equipment_number", "badge": "status"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "name", "description": "location", "date": "next_calibration_due", "badge": "category"},
        {"id": "calendar", "name": "Calibration Due", "type": "calendar", "title": "name", "badge": "status", "start_date": "next_calibration_due", "read_only": true},
        {"id": "list", "name": "All Equipment", "type": "list", "title": "name", "description": "equipment_number", "field_1": "status", "field_2": "next_calibration_due"}
    ],
    "filter_presets": [
        {"id": "overdue", "name": "Overdue", "filters": [{"id": "is_overdue", "value": "true", "operator": "eq"}]},
        {"id": "due_soon", "name": "Due Within 30 Days", "filters": [{"id": "status", "value": "due", "operator": "eq"}]},
        {"id": "in_service", "name": "In Service", "filters": [{"id": "status", "value": "in_service", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["name", "category", "location", "calibration_frequency_days"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "category", "serial_number", "location", "custodian_id", "photo"]},
            {"id": "calibration", "title": "Calibration", "fields": {"create": ["calibration_frequency_days"], "update": ["calibration_frequency_days", "status"], "read": ["calibration_frequency_days", "last_calibrated_on", "next_calibration_due", "is_overdue"]}},
            {"id": "extras", "title": "Certificate & Notes", "collapsible": true, "fields": ["certificate", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "next_calibration_due", "desc": false}],
        "join": [{"table": "users", "on": "custodian_id", "alias": "custodian", "columns": ["name", "email"]}]
    }
}';

comment on column quality.equipment.photo is '{"accept": "image/*", "maxFiles": 3, "maxSize": 5242880}';

comment on column quality.equipment.certificate is '{"accept": ".pdf", "maxFiles": 1, "maxSize": 10485760}';

revoke all on table quality.equipment
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
delete on table quality.equipment to "x-admin";

grant
select
,
  insert,
update on table quality.equipment to "qa-manager";

grant
select
  on table quality.equipment to "quality-auditor";

revoke all on sequence quality.equipment_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence quality.equipment_number_seq to "x-admin",
"qa-manager";

create index idx_qual_equipment_status on quality.equipment (status);

create index idx_qual_equipment_due on quality.equipment (next_calibration_due);

alter table quality.equipment enable row level security;

create policy equipment_select on quality.equipment for
select
  to authenticated using (true);

create policy equipment_insert on quality.equipment for insert to authenticated
with
  check (true);

create policy equipment_update on quality.equipment
for update
  to authenticated using (true)
with
  check (true);

create policy equipment_delete on quality.equipment for delete to authenticated using (true);

create or replace function quality.equipment_set_status () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  new.is_overdue := (
    new.next_calibration_due is not null
    and new.next_calibration_due < current_date
  );

  if new.status not in ('out_of_service', 'retired') then
    if new.is_overdue then
      new.status := 'overdue';
    elsif new.next_calibration_due is not null
      and new.next_calibration_due <= current_date + 30 then
      new.status := 'due';
    else
      new.status := 'in_service';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_equipment_set_status before insert
or
update on quality.equipment for each row
execute function quality.equipment_set_status ();

----------------------------------------------------------------
-- Calibration records
----------------------------------------------------------------
create table quality.calibration_records (
  id uuid primary key default extensions.uuid_generate_v4 (),
  equipment_id uuid not null references quality.equipment (id) on delete cascade,
  calibrated_on date not null default current_date,
  performed_by uuid references supasheet.users (id) on delete set null,
  vendor varchar(160),
  result quality.calibration_result not null default 'pass',
  next_due_date date not null,
  certificate supasheet.file,
  notes varchar(500),
  created_at timestamptz default current_timestamp,
  constraint calibration_next_due_after check (next_due_date >= calibrated_on)
);

comment on column quality.calibration_records.result is '{
    "progress": false,
    "values": {
        "pass": {"variant": "success", "icon": "CircleCheck"},
        "fail": {"variant": "destructive", "icon": "CircleX"},
        "adjusted": {"variant": "warning", "icon": "Settings"}
    }
}';

comment on table quality.calibration_records is '{
    "icon": "History",
    "name": "Calibration Records",
    "description": "Every calibration event for a piece of equipment, and what it reset the due date to.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "record", "title": "Record", "fields": ["equipment_id", "calibrated_on", "performed_by", "vendor", "result"]},
            {"id": "outcome", "title": "Outcome", "fields": ["next_due_date", "certificate", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "calibrated_on", "desc": true}],
        "join": [
            {"table": "equipment", "on": "equipment_id", "columns": ["equipment_number", "name", "status"]},
            {"table": "users", "on": "performed_by", "columns": ["name", "email"]}
        ]
    }
}';

comment on column quality.calibration_records.certificate is '{"accept": ".pdf", "maxFiles": 1, "maxSize": 10485760}';

revoke all on table quality.calibration_records
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
delete on table quality.calibration_records to "x-admin",
"qa-manager";

grant
select
,
  insert on table quality.calibration_records to "quality-auditor";

create index idx_qual_calibration_equipment_id on quality.calibration_records (equipment_id);

alter table quality.calibration_records enable row level security;

create policy calibration_select on quality.calibration_records for
select
  to authenticated using (true);

create policy calibration_insert on quality.calibration_records for insert to authenticated
with
  check (true);

create policy calibration_update on quality.calibration_records
for update
  to authenticated using (true)
with
  check (true);

create policy calibration_delete on quality.calibration_records for delete to authenticated using (true);

create or replace function quality.calibration_records_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  update quality.equipment
  set last_calibrated_on = new.calibrated_on,
    next_calibration_due = new.next_due_date
  where id = new.equipment_id
    and (
      last_calibrated_on is null
      or new.calibrated_on >= last_calibrated_on
    );

  return new;
end;
$$;

create trigger trg_calibration_records_rollup
after insert on quality.calibration_records for each row
execute function quality.calibration_records_rollup ();

----------------------------------------------------------------
-- Training courses
----------------------------------------------------------------
create table quality.training_courses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  title varchar(200) not null,
  description supasheet.RICH_TEXT,
  category varchar(120),
  related_document_id uuid references quality.documents (id) on delete set null,
  is_mandatory boolean not null default false,
  validity_months integer,
  is_active boolean not null default true,
  record_count integer not null default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint training_validity_positive check (
    validity_months is null
    or validity_months > 0
  )
);

comment on table quality.training_courses is '{
    "icon": "GraduationCap",
    "name": "Training Courses",
    "description": "The course catalogue — what people can be assigned, and how long a completion stays valid.",
    "collapsible_group": "Training",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "title", "badges": ["code", "is_mandatory"]},
        "tabs": ["training_records"]
    },
    "views": [
        {"id": "list", "name": "All Courses", "type": "list", "title": "title", "description": "category", "field_1": "code", "field_2": "record_count"},
        {"id": "kanban", "name": "By Category", "type": "kanban", "group": "category", "title": "title", "description": "code", "date": "created_at", "badge": "is_mandatory"}
    ],
    "filter_presets": [
        {"id": "mandatory", "name": "Mandatory", "filters": [{"id": "is_mandatory", "value": "true", "operator": "eq"}]},
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["code", "title", "is_mandatory"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "title", "description", "category", "related_document_id"]},
            {"id": "rules", "title": "Rules", "fields": ["is_mandatory", "validity_months", "is_active"]},
            {"id": "position", "title": "Position", "fields": {"read": ["record_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "documents", "on": "related_document_id", "columns": ["document_number", "title"]}]
    }
}';

revoke all on table quality.training_courses
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
delete on table quality.training_courses to "x-admin";

grant
select
,
  insert,
update on table quality.training_courses to "qa-manager";

grant
select
  on table quality.training_courses to "quality-auditor",
  "user";

alter table quality.training_courses enable row level security;

create policy training_courses_select on quality.training_courses for
select
  to authenticated using (true);

create policy training_courses_insert on quality.training_courses for insert to authenticated
with
  check (true);

create policy training_courses_update on quality.training_courses
for update
  to authenticated using (true)
with
  check (true);

create policy training_courses_delete on quality.training_courses for delete to authenticated using (true);

----------------------------------------------------------------
-- Training records
----------------------------------------------------------------
create table quality.training_records (
  id uuid primary key default extensions.uuid_generate_v4 (),
  course_id uuid not null references quality.training_courses (id) on delete restrict,
  user_id uuid not null references supasheet.users (id) on delete cascade,
  assigned_by uuid references supasheet.users (id) on delete set null,
  assigned_on date not null default current_date,
  due_date date,
  completed_on date,
  expires_on date,
  score numeric(5, 2),
  status quality.training_status not null default 'not_started',
  certificate supasheet.file,
  notes varchar(300),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column quality.training_records.status is '{
    "progress": true,
    "values": {
        "not_started": {"variant": "secondary", "icon": "CircleDashed"},
        "in_progress": {"variant": "warning", "icon": "Loader"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "expired": {"variant": "destructive", "icon": "Clock"}
    }
}';

comment on table quality.training_records is '{
    "icon": "GraduationCap",
    "name": "Training Records",
    "description": "Who has been assigned what, and whether their completion is still current.",
    "collapsible_group": "Training",
    "display": "block",
    "primary_view": "calendar",
    "detail": {"header": {"title": "course_id", "badges": ["status", "expires_on"]}},
    "views": [
        {"id": "calendar", "name": "Due Dates", "type": "calendar", "title": "notes", "badge": "status", "start_date": "due_date", "read_only": true},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "notes", "description": "score", "date": "due_date", "badge": "status"},
        {"id": "list", "name": "All Records", "type": "list", "title": "notes", "description": "score", "field_1": "status", "field_2": "expires_on"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "My Training", "filters": [{"id": "user_id", "value": "me", "operator": "eq"}]},
        {"id": "outstanding", "name": "Not Completed", "filters": [{"id": "status", "value": ["not_started", "in_progress"], "operator": "in"}]},
        {"id": "expired", "name": "Expired", "filters": [{"id": "status", "value": "expired", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["course_id", "user_id", "due_date"],
        "sections": [
            {"id": "assignment", "title": "Assignment", "fields": {"create": ["course_id", "user_id", "due_date"], "update": ["due_date"], "read": ["course_id", "user_id", "assigned_by", "assigned_on", "due_date"]}},
            {"id": "completion", "title": "Completion", "fields": {"update": ["completed_on", "score", "certificate", "notes"], "read": ["completed_on", "expires_on", "score", "status", "certificate", "notes"]}}
        ]
    },
    "query": {
        "sort": [{"id": "due_date", "desc": false}],
        "join": [
            {"table": "training_courses", "on": "course_id", "columns": ["code", "title", "is_mandatory"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column quality.training_records.certificate is '{"accept": ".pdf,.png,.jpg", "maxFiles": 1, "maxSize": 5242880}';

revoke all on table quality.training_records
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
delete on table quality.training_records to "x-admin";

grant
select
,
  insert,
update on table quality.training_records to "qa-manager";

grant
select
  on table quality.training_records to "quality-auditor";

grant
select
,
update on table quality.training_records to "user";

create index idx_qual_training_records_course_id on quality.training_records (course_id);

create index idx_qual_training_records_user_id on quality.training_records (user_id);

create index idx_qual_training_records_status on quality.training_records (status);

alter table quality.training_records enable row level security;

create policy training_records_select on quality.training_records for
select
  to authenticated using (
    user_id = (select auth.uid ())
    or pg_has_role (current_user, 'qa-manager', 'member')
    or pg_has_role (current_user, 'quality-auditor', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  );

create policy training_records_insert on quality.training_records for insert to authenticated
with
  check (true);

create policy training_records_update on quality.training_records
for update
  to authenticated using (
    user_id = (select auth.uid ())
    or pg_has_role (current_user, 'qa-manager', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy training_records_delete on quality.training_records for delete to authenticated using (true);

create trigger training_records_updated_at before
update on quality.training_records for each row
execute function supasheet.set_updated_at ();

create or replace function quality.training_records_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_validity integer;
begin
  if new.completed_on is not null then
    if new.status not in ('completed', 'expired') then
      new.status := 'completed';
    end if;

    if new.expires_on is null then
      select validity_months into v_validity
      from quality.training_courses
      where id = new.course_id;

      if v_validity is not null then
        new.expires_on := (new.completed_on + make_interval (months => v_validity))::date;
      end if;
    end if;

    if new.expires_on is not null and new.expires_on < current_date then
      new.status := 'expired';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_training_records_guard before insert
or
update on quality.training_records for each row
execute function quality.training_records_guard ();

create or replace function quality.training_records_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_course_id uuid := coalesce(new.course_id, old.course_id);
begin
  update quality.training_courses
  set record_count = (
      select count(*)
      from quality.training_records
      where course_id = v_course_id
    ),
    updated_at = current_timestamp
  where id = v_course_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_training_records_rollup
after insert
or delete on quality.training_records for each row
execute function quality.training_records_rollup ();

----------------------------------------------------------------
-- Notification triggers
----------------------------------------------------------------
create or replace function quality.trg_capas_notify () returns trigger as $$
begin
  if tg_op = 'INSERT' and new.owner_id is not null then
    perform supasheet.create_notification(
      'capa_assigned',
      'CAPA assigned: ' || new.capa_number,
      'You have been made the owner of a CAPA.',
      array[new.owner_id],
      jsonb_build_object('capa_id', new.id),
      '/quality/resource/capas/' || new.id::text || '/detail'
    );
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status and new.status = 'closed' then
    perform supasheet.create_notification(
      'capa_closed',
      'CAPA closed: ' || new.capa_number,
      'The CAPA you raised has been closed and verified effective.',
      array_remove(array[new.opened_by], null),
      jsonb_build_object('capa_id', new.id),
      '/quality/resource/capas/' || new.id::text || '/detail'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_capas_notify on quality.capas;

create trigger trg_capas_notify
after insert
or
update of status on quality.capas for each row
execute function quality.trg_capas_notify ();

create or replace function quality.trg_capa_actions_notify () returns trigger as $$
begin
  if new.assigned_to is not null then
    perform supasheet.create_notification(
      'capa_action_assigned',
      'Action assigned on a CAPA',
      new.description,
      array[new.assigned_to],
      jsonb_build_object('capa_id', new.capa_id, 'action_id', new.id),
      '/quality/resource/capas/' || new.capa_id::text || '/detail'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_capa_actions_notify on quality.capa_actions;

create trigger trg_capa_actions_notify
after insert on quality.capa_actions for each row
execute function quality.trg_capa_actions_notify ();

create or replace function quality.trg_findings_notify () returns trigger as $$
begin
  if new.severity in ('major', 'critical') then
    perform supasheet.create_notification(
      'serious_finding_raised',
      upper(new.severity::text) || ' finding raised',
      new.description,
      supasheet.get_users_with_role ('qa-manager'),
      jsonb_build_object('finding_id', new.id, 'audit_id', new.audit_id),
      '/quality/resource/audit_findings/' || new.id::text || '/detail'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_findings_notify on quality.audit_findings;

create trigger trg_findings_notify
after insert on quality.audit_findings for each row
execute function quality.trg_findings_notify ();

create or replace function quality.trg_nc_notify () returns trigger as $$
declare
  v_owner_id uuid;
begin
  if new.process_id is not null then
    select owner_id into v_owner_id from quality.processes where id = new.process_id;

    if v_owner_id is not null then
      perform supasheet.create_notification(
        'nonconformance_opened',
        'Nonconformance raised: ' || new.nc_number,
        new.title,
        array[v_owner_id],
        jsonb_build_object('nonconformance_id', new.id),
        '/quality/resource/nonconformances/' || new.id::text || '/detail'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_nc_notify on quality.nonconformances;

create trigger trg_nc_notify
after insert on quality.nonconformances for each row
execute function quality.trg_nc_notify ();

create or replace function quality.trg_complaints_notify () returns trigger as $$
begin
  perform supasheet.create_notification(
    'complaint_received',
    'Complaint received: ' || new.complaint_number,
    new.customer_name || ' — ' || coalesce(new.product_or_service, 'unspecified product/service'),
    supasheet.get_users_with_role ('qa-manager'),
    jsonb_build_object('complaint_id', new.id),
    '/quality/resource/customer_complaints/' || new.id::text || '/detail'
  );

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_complaints_notify on quality.customer_complaints;

create trigger trg_complaints_notify
after insert on quality.customer_complaints for each row
execute function quality.trg_complaints_notify ();

create or replace function quality.trg_training_records_notify () returns trigger as $$
begin
  perform supasheet.create_notification(
    'training_assigned',
    'Training assigned',
    'A new training record has been assigned to you.',
    array[new.user_id],
    jsonb_build_object('training_record_id', new.id, 'course_id', new.course_id),
    '/quality/resource/training_records/' || new.id::text || '/detail'
  );

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_training_records_notify on quality.training_records;

create trigger trg_training_records_notify
after insert on quality.training_records for each row
execute function quality.trg_training_records_notify ();

create or replace function quality.trg_equipment_notify () returns trigger as $$
begin
  if new.status = 'overdue' and old.status is distinct from 'overdue' and new.custodian_id is not null then
    perform supasheet.create_notification(
      'equipment_calibration_overdue',
      'Calibration overdue: ' || new.name,
      'This equipment''s calibration due date has passed.',
      array[new.custodian_id],
      jsonb_build_object('equipment_id', new.id),
      '/quality/resource/equipment/' || new.id::text || '/detail'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_equipment_notify on quality.equipment;

create trigger trg_equipment_notify
after
update of status on quality.equipment for each row
execute function quality.trg_equipment_notify ();

----------------------------------------------------------------
-- Audit logging on the high-value tables
----------------------------------------------------------------
create trigger audit_quality_documents_insert
after insert on quality.documents for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_quality_documents_update
after
update on quality.documents for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_quality_documents_delete before delete on quality.documents for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_quality_document_versions_insert
after insert on quality.document_versions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_quality_document_versions_update
after
update on quality.document_versions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_quality_capas_insert
after insert on quality.capas for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_quality_capas_update
after
update on quality.capas for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_quality_capas_delete before delete on quality.capas for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_quality_audits_insert
after insert on quality.audits for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_quality_audits_update
after
update on quality.audits for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_quality_nc_insert
after insert on quality.nonconformances for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_quality_nc_update
after
update on quality.nonconformances for each row
execute function supasheet.audit_trigger_function ();

-- ================================================================
-- Dashboard widgets
-- ================================================================
create or replace view quality.open_capas_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'clipboard-list' as icon,
  'open capas' as label
from
  quality.capas
where
  status not in ('closed', 'cancelled');

comment on view quality.open_capas_count is '{"type": "dashboard_widget", "name": "Open CAPAs", "description": "CAPAs not yet closed or cancelled", "widget_type": "card_1"}';

create or replace view quality.capa_action_comparison
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'overdue'
  ) as primary,
  count(*) filter (
    where
      status in ('open', 'in_progress')
  ) as secondary,
  'Overdue' as primary_label,
  'On Track' as secondary_label
from
  quality.capa_actions;

comment on view quality.capa_action_comparison is '{"type": "dashboard_widget", "name": "CAPA Actions", "description": "Overdue actions against everything still on track", "widget_type": "card_2"}';

create or replace view quality.finding_closure_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        status = 'closed'
    ) / nullif(count(*), 0),
    1
  ) as percent
from
  quality.audit_findings;

comment on view quality.finding_closure_rate is '{"type": "dashboard_widget", "name": "Finding Closure Rate", "description": "Share of every audit finding that has been closed", "widget_type": "card_3"}';

create or replace view quality.capa_pipeline_progress
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'closed'
  ) as current,
  count(*) as total,
  json_build_array(
    json_build_object(
      'label', 'Open', 'value', count(*) filter (
        where
          status in ('open', 'root_cause_analysis', 'action_planned')
      )
    ),
    json_build_object(
      'label', 'In Progress', 'value', count(*) filter (
        where
          status = 'in_progress'
      )
    ),
    json_build_object(
      'label', 'Verification', 'value', count(*) filter (
        where
          status in ('pending_verification', 'verified')
      )
    ),
    json_build_object(
      'label', 'Closed', 'value', count(*) filter (
        where
          status = 'closed'
      )
    )
  ) as segments
from
  quality.capas;

comment on view quality.capa_pipeline_progress is '{"type": "dashboard_widget", "name": "CAPA Pipeline", "description": "Every CAPA, by stage", "widget_type": "card_4"}';

create or replace view quality.open_nonconformance_breakdown
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status <> 'closed'
  ) as value,
  'Open Nonconformances' as label,
  'file-warning' as icon,
  json_build_array(
    json_build_object(
      'label',
      'Minor',
      'value',
      count(*) filter (
        where
          severity = 'minor'
          and status <> 'closed'
      ),
      'variant',
      'info'
    ),
    json_build_object(
      'label',
      'Major',
      'value',
      count(*) filter (
        where
          severity = 'major'
          and status <> 'closed'
      ),
      'variant',
      'warning'
    ),
    json_build_object(
      'label',
      'Critical',
      'value',
      count(*) filter (
        where
          severity = 'critical'
          and status <> 'closed'
      ),
      'variant',
      'destructive'
    )
  ) as breakdown
from
  quality.nonconformances;

comment on view quality.open_nonconformance_breakdown is '{"type": "dashboard_widget", "name": "Open Nonconformances", "description": "Open issues, by severity", "widget_type": "card_5"}';

create or replace view quality.quality_metrics_grid
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Open Audits',
      'value',
      (
        select
          count(*)
        from
          quality.audits
        where
          status in ('planned', 'scheduled', 'in_progress')
      )
    ),
    json_build_object(
      'label',
      'Overdue Equipment',
      'value',
      (
        select
          count(*)
        from
          quality.equipment
        where
          is_overdue
      )
    ),
    json_build_object(
      'label',
      'Docs Due Review',
      'value',
      (
        select
          count(*)
        from
          quality.documents
        where
          next_review_date <= current_date
          and status = 'active'
      )
    ),
    json_build_object(
      'label',
      'Open Complaints',
      'value',
      (
        select
          count(*)
        from
          quality.customer_complaints
        where
          status in ('open', 'investigating')
      )
    )
  ) as metrics;

comment on view quality.quality_metrics_grid is '{"type": "dashboard_widget", "name": "Quality At A Glance", "description": "The four headline counts", "widget_type": "card_6"}';

create or replace view quality.recent_capas
with
  (security_invoker = true) as
select
  capa_number,
  title,
  status,
  due_date,
  '/quality/resource/capas/' || id || '/detail' as link
from
  quality.capas
order by
  created_at desc
limit
  10;

comment on view quality.recent_capas is '{"type": "dashboard_widget", "name": "Recent CAPAs", "description": "The most recently opened CAPAs", "widget_type": "table_1"}';

create or replace view quality.findings_by_audit
with
  (security_invoker = true) as
select
  a.audit_number as audit,
  count(f.id) as findings,
  count(f.id) filter (
    where
      f.status <> 'closed'
  ) as open_findings,
  '/quality/resource/audits/' || a.id || '/detail' as link
from
  quality.audits a
  left join quality.audit_findings f on f.audit_id = a.id
group by
  a.id,
  a.audit_number
order by
  findings desc
limit
  10;

comment on view quality.findings_by_audit is '{"type": "dashboard_widget", "name": "Findings By Audit", "description": "Total and still-open findings, by audit", "widget_type": "table_2"}';

create or replace view quality.overdue_equipment_alert
with
  (security_invoker = true) as
select
  name as title,
  equipment_number || ' — due ' || next_calibration_due as description,
  'triangle-alert' as icon,
  'destructive' as variant,
  '/quality/resource/equipment/' || id || '/detail' as link
from
  quality.equipment
where
  is_overdue
order by
  next_calibration_due asc
limit
  10;

comment on view quality.overdue_equipment_alert is '{"type": "dashboard_widget", "name": "Overdue Calibration", "description": "Equipment past its calibration due date", "widget_type": "list_1"}';

create or replace view quality.documents_due_review_alert
with
  (security_invoker = true) as
select
  title,
  document_number as description,
  'clock' as icon,
  'warning' as variant,
  '/quality/resource/documents/' || id || '/detail' as link
from
  quality.documents
where
  next_review_date <= current_date + 30
  and status = 'active'
order by
  next_review_date asc
limit
  10;

comment on view quality.documents_due_review_alert is '{"type": "dashboard_widget", "name": "Documents Due For Review", "description": "Active documents whose review date is within 30 days", "widget_type": "list_2"}';

create or replace view quality.recent_capa_activity
with
  (security_invoker = true) as
select
  u.name as actor,
  case
    when e.event_type = 'created' then 'opened'
    when e.event_type = 'action_completed' then 'completed an action on'
    when e.event_type = 'closed' then 'closed'
    when e.event_type = 'verified' then 'verified'
    else 'updated'
  end as action,
  c.capa_number as entity,
  to_char(e.occurred_at, 'Mon DD, YYYY') as date,
  '/quality/resource/capas/' || c.id || '/detail' as link
from
  quality.capa_events e
  join quality.capas c on c.id = e.capa_id
  left join quality.users u on u.id = e.actor_id
order by
  e.occurred_at desc
limit
  5;

comment on view quality.recent_capa_activity is '{"type": "dashboard_widget", "name": "Recent CAPA Activity", "description": "The latest events across every CAPA", "widget_type": "list_3"}';

create or replace view quality.top_processes_by_nc
with
  (security_invoker = true) as
select
  name,
  open_nonconformance_count as value,
  code as label,
  '/quality/resource/processes/' || id || '/detail' as link
from
  quality.processes
where
  open_nonconformance_count > 0
order by
  value desc
limit
  5;

comment on view quality.top_processes_by_nc is '{"type": "dashboard_widget", "name": "Processes With Open Issues", "description": "Ranked by open nonconformance count", "widget_type": "list_4"}';

do $$
declare
  v text;
begin
  foreach v in array array[
    'quality.open_capas_count',
    'quality.capa_action_comparison',
    'quality.finding_closure_rate',
    'quality.capa_pipeline_progress',
    'quality.open_nonconformance_breakdown',
    'quality.quality_metrics_grid',
    'quality.recent_capas',
    'quality.findings_by_audit',
    'quality.overdue_equipment_alert',
    'quality.documents_due_review_alert',
    'quality.recent_capa_activity',
    'quality.top_processes_by_nc'
  ]
  loop
    execute format('revoke all on %s from public, anon, authenticated, service_role;', v);
    execute format('grant select on %s to "x-admin", "qa-manager", "quality-auditor";', v);
  end loop;
end;
$$;

-- ================================================================
-- Charts
-- ================================================================
create or replace view quality.nc_by_source_pie
with
  (security_invoker = true) as
select
  source::text as label,
  count(*) as value
from
  quality.nonconformances
group by
  source;

comment on view quality.nc_by_source_pie is '{"type": "chart", "name": "Nonconformances By Source", "description": "Where issues are coming from", "chart_type": "pie"}';

create or replace view quality.capas_by_process_bar
with
  (security_invoker = true) as
select
  p.name as label,
  count(c.id) as total,
  count(c.id) filter (
    where
      c.status = 'closed'
  ) as closed
from
  quality.processes p
  left join quality.capas c on c.process_id = p.id
group by
  p.name
order by
  total desc;

comment on view quality.capas_by_process_bar is '{"type": "chart", "name": "CAPAs By Process", "description": "Total and closed CAPAs per process", "chart_type": "bar"}';

create or replace view quality.monthly_nc_trend_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', created_at), 'Mon YYYY') as date,
  count(*) as opened
from
  quality.nonconformances
group by
  date_trunc('month', created_at)
order by
  date_trunc('month', created_at);

comment on view quality.monthly_nc_trend_line is '{"type": "chart", "name": "Monthly Nonconformances", "description": "Nonconformances opened, by month", "chart_type": "line"}';

create or replace view quality.capa_opened_closed_area
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', created_at), 'Mon YYYY') as date,
  count(*) as opened,
  count(*) filter (
    where
      status = 'closed'
  ) as closed
from
  quality.capas
group by
  date_trunc('month', created_at)
order by
  date_trunc('month', created_at);

comment on view quality.capa_opened_closed_area is '{"type": "chart", "name": "CAPAs Opened vs Closed", "description": "Monthly CAPA volume against how much has actually closed", "chart_type": "area"}';

create or replace view quality.risk_scores_radar
with
  (security_invoker = true) as
select
  category::text as metric,
  avg(severity) as severity,
  avg(occurrence) as occurrence,
  avg(detection) as detection
from
  quality.risk_assessments
group by
  category;

comment on view quality.risk_scores_radar is '{"type": "chart", "name": "Risk Scores By Category", "description": "Average severity, occurrence and detection per risk category", "chart_type": "radar"}';

do $$
declare
  v text;
begin
  foreach v in array array[
    'quality.nc_by_source_pie',
    'quality.capas_by_process_bar',
    'quality.monthly_nc_trend_line',
    'quality.capa_opened_closed_area',
    'quality.risk_scores_radar'
  ]
  loop
    execute format('revoke all on %s from public, anon, authenticated, service_role;', v);
    execute format('grant select on %s to "x-admin", "qa-manager", "quality-auditor";', v);
  end loop;
end;
$$;

-- ================================================================
-- Reports
-- ================================================================
create or replace view quality.capas_report
with
  (security_invoker = true) as
select
  c.id,
  c.capa_number,
  c.title,
  c.capa_type,
  c.source,
  c.status,
  c.priority,
  p.name as process,
  u1.name as owner,
  u2.name as opened_by,
  c.due_date,
  c.action_count,
  c.completed_action_count,
  c.effectiveness_result,
  c.closed_at
from
  quality.capas c
  left join quality.processes p on p.id = c.process_id
  left join quality.users u1 on u1.id = c.owner_id
  left join quality.users u2 on u2.id = c.opened_by;

comment on view quality.capas_report is '{"type": "report", "name": "CAPAs", "description": "Every CAPA with its process, owner and verification outcome — the management review document.", "template": true}';

revoke all on quality.capas_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on quality.capas_report to "x-admin",
  "qa-manager",
  "quality-auditor";

create or replace view quality.audit_findings_report
with
  (security_invoker = true) as
select
  f.id,
  a.audit_number,
  a.audit_type,
  f.finding_number,
  f.severity,
  f.clause_reference,
  f.description,
  f.status,
  f.due_date,
  f.closed_at,
  count(c.id) as capa_count
from
  quality.audit_findings f
  join quality.audits a on a.id = f.audit_id
  left join quality.capas c on c.source_audit_finding_id = f.id
group by
  f.id,
  a.audit_number,
  a.audit_type;

comment on view quality.audit_findings_report is '{"type": "report", "name": "Audit Findings", "description": "Every finding across every audit, with how many CAPAs it produced."}';

revoke all on quality.audit_findings_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on quality.audit_findings_report to "x-admin",
  "qa-manager",
  "quality-auditor";

-- Heavy monthly rollup — a materialized view instead of a live report.
create materialized view quality.quality_kpi_rollup as
select
  months.month,
  coalesce(nc.opened, 0) as nonconformances_opened,
  coalesce(capa.opened, 0) as capas_opened,
  coalesce(capa.closed, 0) as capas_closed,
  coalesce(finding.raised, 0) as findings_raised,
  coalesce(finding.closed, 0) as findings_closed
from
  (
    select
      generate_series(
        date_trunc(
          'month',
          least(
            (
              select
                min(created_at)
              from
                quality.nonconformances
            ),
            (
              select
                min(created_at)
              from
                quality.capas
            ),
            current_timestamp
          )
        ),
        date_trunc('month', current_timestamp),
        interval '1 month'
      )::date as month
  ) months
  left join (
    select
      date_trunc('month', created_at)::date as month,
      count(*) as opened
    from quality.nonconformances
    group by
      1
  ) nc using (month)
  left join (
    select
      date_trunc('month', created_at)::date as month,
      count(*) as opened,
      count(*) filter (
        where
          status = 'closed'
      ) as closed
    from quality.capas
    group by
      1
  ) capa using (month)
  left join (
    select
      date_trunc('month', created_at)::date as month,
      count(*) as raised,
      count(*) filter (
        where
          status = 'closed'
      ) as closed
    from quality.audit_findings
    group by
      1
  ) finding using (month);

create unique index idx_qual_kpi_rollup_month on quality.quality_kpi_rollup (month);

comment on materialized view quality.quality_kpi_rollup is '{"type": "report", "name": "Quality KPI Trend", "description": "Nonconformances, CAPAs and findings opened and closed, by month. Refresh with: refresh materialized view concurrently quality.quality_kpi_rollup;"}';

revoke all on quality.quality_kpi_rollup
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on quality.quality_kpi_rollup to "x-admin",
  "qa-manager",
  "quality-auditor";

-- ================================================================
-- Templates (bulk insert)
-- ================================================================
create or replace view quality.standard_document_categories_template
with
  (security_invoker = true) as
select
  *
from
  (
    values
      ('POL'::varchar(20), 'Policies'::varchar(160)),
      ('PROC', 'Procedures'),
      ('WI', 'Work Instructions'),
      ('FORM', 'Forms'),
      ('QM', 'Quality Manual'),
      ('EXT', 'External Standards'),
      ('REC', 'Records')
  ) as t (code, name);

comment on view quality.standard_document_categories_template is '{
    "type": "template",
    "name": "Standard Document Category Set",
    "description": "A sensible starting document taxonomy for a fresh install. Apply to quality.document_categories.",
    "target_table": "document_categories"
}';

revoke all on quality.standard_document_categories_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on quality.standard_document_categories_template to "x-admin";

create or replace view quality.annual_audit_schedule_template
with
  (security_invoker = true) as
select
  'internal'::quality.audit_type as audit_type,
  p.id as process_id,
  'Annual internal audit — ' || p.name as scope,
  (current_date + 90) as planned_date
from
  quality.processes p
where
  p.is_active
  and not exists (
    select
      1
    from
      quality.audits a
    where
      a.process_id = p.id
      and a.planned_date between current_date and current_date + 90
  );

comment on view quality.annual_audit_schedule_template is '{
    "type": "template",
    "name": "Audit Schedule Gap-Fill",
    "description": "A draft internal audit, 90 days out, for every active process with nothing already planned. Apply to quality.audits.",
    "target_table": "audits"
}';

revoke all on quality.annual_audit_schedule_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on quality.annual_audit_schedule_template to "x-admin",
  "qa-manager";

-- ================================================================
-- Custom forms
-- ================================================================
create or replace function quality.raise_capa_from_finding (
  p_finding_id uuid,
  p_capa_type quality.capa_type,
  p_title varchar,
  p_description text default null,
  p_process_id uuid default null,
  p_owner_id uuid default null,
  p_due_date date default null
) returns quality.capas language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_capa quality.capas;
begin
  insert into quality.capas (
    capa_type, source, source_audit_finding_id, process_id, title, description, owner_id, due_date
  )
  values (
    p_capa_type, 'audit_finding', p_finding_id, p_process_id, p_title, p_description, p_owner_id, p_due_date
  )
  returning * into v_capa;

  return v_capa;
end;
$$;

comment on function quality.raise_capa_from_finding (
  uuid, quality.capa_type, varchar, text, uuid, uuid, date
) is '{
    "type": "form",
    "resource": "audit_findings",
    "name": "Raise CAPA",
    "description": "Open a corrective/preventive action against this finding.",
    "icon": "ClipboardList",
    "success_message": "CAPA raised",
    "fields": {
        "sections": [
            {"id": "capa", "title": "CAPA", "fields": ["p_finding_id", "p_capa_type", "p_title", "p_description"]},
            {"id": "assignment", "title": "Assignment", "fields": ["p_process_id", "p_owner_id", "p_due_date"]}
        ],
        "relations": {
            "p_finding_id": {"table": "audit_findings", "column": "id", "display": ["finding_number", "description"]},
            "p_process_id": {"table": "processes", "column": "id", "display": ["code", "name"]},
            "p_owner_id": {"table": "users", "column": "id", "display": ["name", "email"]}
        }
    }
}';

create or replace function quality.raise_capa_from_nonconformance (
  p_nonconformance_id uuid,
  p_capa_type quality.capa_type,
  p_title varchar,
  p_description text default null,
  p_process_id uuid default null,
  p_owner_id uuid default null,
  p_due_date date default null
) returns quality.capas language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_capa quality.capas;
begin
  insert into quality.capas (
    capa_type, source, source_nonconformance_id, process_id, title, description, owner_id, due_date
  )
  values (
    p_capa_type, 'nonconformance', p_nonconformance_id, p_process_id, p_title, p_description, p_owner_id, p_due_date
  )
  returning * into v_capa;

  return v_capa;
end;
$$;

comment on function quality.raise_capa_from_nonconformance (
  uuid, quality.capa_type, varchar, text, uuid, uuid, date
) is '{
    "type": "form",
    "resource": "nonconformances",
    "name": "Raise CAPA",
    "description": "Open a corrective/preventive action against this nonconformance.",
    "icon": "ClipboardList",
    "success_message": "CAPA raised",
    "fields": {
        "sections": [
            {"id": "capa", "title": "CAPA", "fields": ["p_nonconformance_id", "p_capa_type", "p_title", "p_description"]},
            {"id": "assignment", "title": "Assignment", "fields": ["p_process_id", "p_owner_id", "p_due_date"]}
        ],
        "relations": {
            "p_nonconformance_id": {"table": "nonconformances", "column": "id", "display": ["nc_number", "title"]},
            "p_process_id": {"table": "processes", "column": "id", "display": ["code", "name"]},
            "p_owner_id": {"table": "users", "column": "id", "display": ["name", "email"]}
        }
    }
}';

create or replace function quality.log_calibration (
  p_equipment_id uuid,
  p_calibrated_on date,
  p_result quality.calibration_result,
  p_next_due_date date,
  p_vendor varchar default null,
  p_notes varchar default null
) returns quality.calibration_records language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_record quality.calibration_records;
begin
  insert into quality.calibration_records (
    equipment_id, calibrated_on, performed_by, vendor, result, next_due_date, notes
  )
  values (
    p_equipment_id, p_calibrated_on, (select auth.uid ()), p_vendor, p_result, p_next_due_date, p_notes
  )
  returning * into v_record;

  return v_record;
end;
$$;

comment on function quality.log_calibration (
  uuid, date, quality.calibration_result, date, varchar, varchar
) is '{
    "type": "form",
    "resource": "equipment",
    "name": "Log Calibration",
    "description": "Record a calibration event and roll the due date forward.",
    "icon": "History",
    "success_message": "Calibration logged",
    "fields": {
        "sections": [
            {"id": "calibration", "title": "Calibration", "fields": ["p_equipment_id", "p_calibrated_on", "p_result", "p_vendor"]},
            {"id": "outcome", "title": "Outcome", "fields": ["p_next_due_date", "p_notes"]}
        ],
        "relations": {
            "p_equipment_id": {"table": "equipment", "column": "id", "display": ["equipment_number", "name"]}
        }
    }
}';

do $$
declare
  f text;
begin
  foreach f in array array[
    'quality.raise_capa_from_finding(uuid, quality.capa_type, varchar, text, uuid, uuid, date)',
    'quality.raise_capa_from_nonconformance(uuid, quality.capa_type, varchar, text, uuid, uuid, date)',
    'quality.log_calibration(uuid, date, quality.calibration_result, date, varchar, varchar)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role;', f);
  end loop;
end;
$$;

grant
execute on function quality.raise_capa_from_finding (
  uuid, quality.capa_type, varchar, text, uuid, uuid, date
) to "x-admin",
"qa-manager",
"quality-auditor";

grant
execute on function quality.raise_capa_from_nonconformance (
  uuid, quality.capa_type, varchar, text, uuid, uuid, date
) to "x-admin",
"qa-manager",
"quality-auditor";

grant
execute on function quality.log_calibration (
  uuid, date, quality.calibration_result, date, varchar, varchar
) to "x-admin",
"qa-manager",
"quality-auditor";

-- ================================================================
-- Row actions
-- ================================================================
create or replace function quality.submit_document_for_review (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update quality.document_versions
  set status = 'in_review'
  where id = p_id
    and status = 'draft';
end;
$$;

comment on function quality.submit_document_for_review (uuid) is '{
    "type": "action",
    "resource": "document_versions",
    "name": "Submit For Review",
    "description": "Send this draft for review.",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Sent for review"
}';

create or replace function quality.approve_document_version (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update quality.document_versions
  set status = 'approved'
  where id = p_id
    and status = 'in_review';
end;
$$;

comment on function quality.approve_document_version (uuid) is '{
    "type": "action",
    "resource": "document_versions",
    "name": "Approve",
    "description": "Approve this revision. Does not publish it yet.",
    "icon": "BadgeCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "in_review"}],
    "success_message": "Version approved"
}';

create or replace function quality.publish_document_version (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update quality.document_versions
  set status = 'effective'
  where id = p_id
    and status = 'approved';
end;
$$;

comment on function quality.publish_document_version (uuid) is '{
    "type": "action",
    "resource": "document_versions",
    "name": "Publish",
    "description": "Make this the effective version. Whatever was effective before it is superseded automatically.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "approved"}],
    "success_message": "Version published"
}';

create or replace function quality.obsolete_document_version (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update quality.document_versions
  set status = 'obsolete'
  where id = p_id
    and status in ('effective', 'superseded');
end;
$$;

comment on function quality.obsolete_document_version (uuid) is '{
    "type": "action",
    "resource": "document_versions",
    "name": "Obsolete",
    "description": "Withdraw this revision entirely.",
    "icon": "Archive",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "in", "value": ["effective", "superseded"]}],
    "success_message": "Version made obsolete"
}';

create or replace function quality.acknowledge_document (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  insert into quality.document_acknowledgements (document_version_id, user_id)
  values (p_id, (select auth.uid ()))
  on conflict (document_version_id, user_id) do nothing;
end;
$$;

comment on function quality.acknowledge_document (uuid) is '{
    "type": "action",
    "resource": "document_versions",
    "name": "Acknowledge",
    "description": "Confirm you have read and understood this version.",
    "icon": "BadgeCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "effective"}],
    "success_message": "Acknowledged"
}';

create or replace function quality.start_audit (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update quality.audits
  set status = 'in_progress',
    actual_start_date = coalesce(actual_start_date, current_date)
  where id = p_id
    and status in ('planned', 'scheduled');
end;
$$;

comment on function quality.start_audit (uuid) is '{
    "type": "action",
    "resource": "audits",
    "name": "Start",
    "description": "Begin fieldwork on this audit.",
    "icon": "Play",
    "visible": [{"id": "status", "operator": "in", "value": ["planned", "scheduled"]}],
    "success_message": "Audit started"
}';

create or replace function quality.complete_audit (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if exists (
    select 1
    from quality.audit_checklist_items
    where audit_id = p_id
      and response = 'pending'
  ) then
    raise exception 'Every checklist item needs a response before the audit can be completed.';
  end if;

  update quality.audits
  set status = 'completed',
    actual_end_date = coalesce(actual_end_date, current_date)
  where id = p_id
    and status = 'in_progress';
end;
$$;

comment on function quality.complete_audit (uuid) is '{
    "type": "action",
    "resource": "audits",
    "name": "Complete",
    "description": "Close out fieldwork. Refused while any checklist item is still unanswered.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "in_progress"}],
    "success_message": "Audit completed"
}';

create or replace function quality.close_finding (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update quality.audit_findings
  set status = 'closed'
  where id = p_id
    and status in ('open', 'capa_raised');
end;
$$;

comment on function quality.close_finding (uuid) is '{
    "type": "action",
    "resource": "audit_findings",
    "name": "Close",
    "description": "Close this finding. Major and critical findings are refused without a linked CAPA.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "in", "value": ["open", "capa_raised"]}],
    "success_message": "Finding closed"
}';

create or replace function quality.complete_capa_action (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update quality.capa_actions
  set status = 'completed'
  where id = p_id
    and status in ('open', 'in_progress', 'overdue');
end;
$$;

comment on function quality.complete_capa_action (uuid) is '{
    "type": "action",
    "resource": "capa_actions",
    "name": "Complete",
    "description": "Mark this action done.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "in", "value": ["open", "in_progress", "overdue"]}],
    "success_message": "Action completed"
}';

create or replace function quality.verify_capa_effectiveness (
  p_id uuid,
  p_result quality.effectiveness_result,
  p_notes varchar
) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update quality.capas
  set effectiveness_result = p_result,
    verification_notes = p_notes,
    effectiveness_check_date = current_date,
    status = case
      when p_result = 'effective' then 'verified'::quality.capa_status
      else status
    end
  where id = p_id
    and status in ('pending_verification', 'verified');
end;
$$;

comment on function quality.verify_capa_effectiveness (
  uuid, quality.effectiveness_result, varchar
) is '{
    "type": "action",
    "resource": "capas",
    "name": "Verify Effectiveness",
    "description": "Record whether the actions taken actually worked.",
    "icon": "Search",
    "action_type": "picker",
    "visible": [{"id": "status", "operator": "eq", "value": "pending_verification"}],
    "success_message": "Effectiveness recorded"
}';

create or replace function quality.close_capa (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update quality.capas
  set status = 'closed'
  where id = p_id
    and status = 'verified';
end;
$$;

comment on function quality.close_capa (uuid) is '{
    "type": "action",
    "resource": "capas",
    "name": "Close",
    "description": "Close the CAPA. Refused unless every action is complete and effectiveness has been verified.",
    "icon": "Archive",
    "visible": [{"id": "status", "operator": "eq", "value": "verified"}],
    "success_message": "CAPA closed"
}';

do $$
declare
  f text;
begin
  foreach f in array array[
    'quality.submit_document_for_review(uuid)',
    'quality.approve_document_version(uuid)',
    'quality.publish_document_version(uuid)',
    'quality.obsolete_document_version(uuid)',
    'quality.acknowledge_document(uuid)',
    'quality.start_audit(uuid)',
    'quality.complete_audit(uuid)',
    'quality.close_finding(uuid)',
    'quality.complete_capa_action(uuid)',
    'quality.verify_capa_effectiveness(uuid, quality.effectiveness_result, varchar)',
    'quality.close_capa(uuid)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role;', f);
  end loop;
end;
$$;

grant
execute on function quality.submit_document_for_review (uuid) to "x-admin",
"qa-manager";

grant
execute on function quality.approve_document_version (uuid) to "x-admin",
"qa-manager";

grant
execute on function quality.publish_document_version (uuid) to "x-admin",
"qa-manager";

grant
execute on function quality.obsolete_document_version (uuid) to "x-admin",
"qa-manager";

grant
execute on function quality.acknowledge_document (uuid) to "x-admin",
"qa-manager",
"quality-auditor",
"user";

grant
execute on function quality.start_audit (uuid) to "x-admin",
"qa-manager",
"quality-auditor";

grant
execute on function quality.complete_audit (uuid) to "x-admin",
"qa-manager",
"quality-auditor";

grant
execute on function quality.close_finding (uuid) to "x-admin",
"qa-manager",
"quality-auditor";

grant
execute on function quality.complete_capa_action (uuid) to "x-admin",
"qa-manager",
"quality-auditor",
"user";

grant
execute on function quality.verify_capa_effectiveness (
  uuid, quality.effectiveness_result, varchar
) to "x-admin",
"qa-manager";

grant
execute on function quality.close_capa (uuid) to "x-admin",
"qa-manager";

----------------------------------------------------------------
-- Private document storage
--
-- Controlled document files already live in the uploads bucket
-- behind the document_versions.file column. This bucket is for
-- everything else that needs to be evidence — audit reports,
-- calibration certificates — gated the same way: if your role
-- cannot read the owning table, it cannot read the file either.
----------------------------------------------------------------
insert into
  storage.buckets (id, name, public)
values
  ('quality-documents', 'quality-documents', false)
on conflict (id) do nothing;

drop policy if exists quality_documents_read on storage.objects;

create policy quality_documents_read on storage.objects for
select
  to authenticated using (
    bucket_id = 'quality-documents'
    and (
      has_table_privilege (current_user, 'quality.audits', 'select')
      or has_table_privilege (current_user, 'quality.equipment', 'select')
    )
  );

drop policy if exists quality_documents_insert on storage.objects;

create policy quality_documents_insert on storage.objects for insert to authenticated
with
  check (
    bucket_id = 'quality-documents'
    and (
      has_table_privilege (current_user, 'quality.audits', 'insert')
      or has_table_privilege (current_user, 'quality.equipment', 'insert')
    )
  );

drop policy if exists quality_documents_update on storage.objects;

create policy quality_documents_update on storage.objects
for update
  to authenticated using (
    bucket_id = 'quality-documents'
    and has_table_privilege (current_user, 'quality.audits', 'update')
  );

drop policy if exists quality_documents_delete on storage.objects;

create policy quality_documents_delete on storage.objects for delete to authenticated using (
  bucket_id = 'quality-documents'
  and has_table_privilege (current_user, 'quality.audits', 'delete')
);

----------------------------------------------------------------
-- App configuration
----------------------------------------------------------------
insert into
  supasheet.configs (key, value, description, is_public)
values
  (
    'quality.default_review_cycle_months',
    '12',
    'Default document review cycle when none is specified',
    false
  ),
  (
    'quality.capa_default_due_days',
    '30',
    'Default number of days to complete a CAPA once opened',
    false
  ),
  (
    'quality.calibration_reminder_days',
    '30',
    'How far ahead of a calibration due date equipment moves to the ''due'' state',
    false
  ),
  (
    'quality.finding_capa_required_severities',
    '["major", "critical"]',
    'Finding severities that cannot close without a linked CAPA',
    true
  )
on conflict (key) do nothing;

-- ================================================================
-- Refresh the metadata catalog — must be last
-- ================================================================
select
  supasheet.refresh_metadata ();
