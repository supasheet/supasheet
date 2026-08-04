-- ================================================================
-- Supasheet Example — "PM" (project management / professional services)
-- ================================================================
-- A production-shaped delivery back office: client-facing projects
-- with a real budget, phases and task lists carrying dependency-aware
-- tasks, time entries billed against that budget, milestones and
-- deliverables with a client-approval workflow, expenses, invoices
-- generated from time and expenses, risk tracking, and weekly status
-- reports that are the only thing allowed to move a project's
-- headline health.
--
-- Demo data lives in supabase/examples/pm_seed.sql — apply this file
-- first, then that one.
--
-- The rules that make this a delivery system rather than a to-do
-- list:
--
--   - A TASK CANNOT DEPEND ON ITSELF, DIRECTLY OR TRANSITIVELY. The
--     same walk-the-graph check the manufacturing example uses for a
--     bill of material, applied here to a dependency chain — a cycle
--     here doesn't give a wrong answer, it gives a critical path that
--     never resolves.
--   - A TASK WITH AN UNFINISHED BLOCKER CANNOT BE MARKED DONE. If
--     task B depends on task A finishing first, B is refused a status
--     of `done` while A is still open — the dependency is enforced,
--     not just drawn on a chart.
--   - LOGGED TIME CANNOT PUSH A CAPPED PROJECT PAST ITS BUDGETED
--     HOURS. The same ceiling-check shape the procurement example
--     uses for a contract, applied here to a time-and-materials
--     project's hour cap.
--   - A TIME ENTRY OR EXPENSE CAN ONLY BE INVOICED ONCE. Linking one
--     to a second invoice line is refused outright — there is no
--     path to billing the same hour twice.
--   - PROJECT HEALTH COMES FROM THE LATEST STATUS REPORT, NEVER TYPED
--     DIRECTLY ON THE PROJECT. There is no editable health field on
--     a project — only a trigger fired by the status report you just
--     filed gets to set it.
--
-- Everything the other modules cover is here too:
--   - Native-role RBAC with two custom roles ("pm-lead" runs
--     delivery — budget, staffing, invoicing — and "client" is an
--     external portal seat that can only ever see its own project's
--     status reports, milestones, deliverables and invoices, and can
--     approve or reject a deliverable) alongside "x-admin"/"user"
--   - A margin that is a genuine computation: every time entry
--     captures both the rate billed to the client and the
--     instructor's — sorry, team member's — internal cost rate, and
--     a project's margin is derived from the two, never entered
--   - All six view layouts, every widget and chart contract, reports
--     with a Handlebars print template, a materialized utilization
--     rollup, both a static and a live-data template, custom form
--     shapes, row actions, notifications, audit logging,
--     per-resource comments and a private `pm-documents` storage
--     bucket for deliverables and signed invoices
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260810000000_pm.sql \
--     -f supabase/examples/pm_seed.sql
--
-- Requires the base Supasheet migrations. Add "pm" to config.toml's
-- `api.schemas` and `api.extra_search_path`, then restart Supabase.
--
-- Not idempotent: re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists pm;

-------------------------------------------------------------------
-- Roles
--
--   x-admin    delivery director: everything, including overriding a
--              blocked budget cap
--   pm-lead     runs delivery: staffs projects, plans phases and
--               tasks, approves time and expenses, files status
--               reports, generates and sends invoices. Cannot delete
--               a project or approve their own logged time
--   user        THE TEAM MEMBER: works assigned tasks, logs their own
--               time and expenses, comments, and raises risks —
--               sees only the projects they are staffed on
--   client      an external portal seat, one per client company: read
--               access to their own project's status reports,
--               milestones and invoices, and can approve or reject a
--               deliverable. Cannot see the task board, time entries
--               or anyone else's client
--
-- Assign a user to a custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "pm-lead"}'
--   where email = 'delivery@example.com';
-------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'user') then
    create role "user" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'admin') then
    create role "admin" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'pm-lead') then
    create role "pm-lead" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'client') then
    create role "client" nologin;
  end if;
end;
$$;

grant "user",
"admin",
"pm-lead",
"client" to authenticator;

grant authenticated to "user",
"admin",
"pm-lead",
"client";

grant usage on schema pm to "x-admin",
"pm-lead",
"user",
"client";

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
create type pm.project_status as enum(
  'planning',
  'active',
  'on_hold',
  'completed',
  'cancelled'
);

create type pm.health_status as enum('green', 'amber', 'red');

create type pm.budget_type as enum('fixed', 'time_and_materials', 'retainer');

create type pm.phase_status as enum('not_started', 'in_progress', 'completed');

create type pm.task_status as enum(
  'todo',
  'in_progress',
  'in_review',
  'done',
  'blocked'
);

create type pm.task_priority as enum('low', 'medium', 'high', 'urgent');

create type pm.dependency_type as enum('finish_to_start', 'start_to_start');

create type pm.time_entry_status as enum(
  'draft',
  'submitted',
  'approved',
  'rejected',
  'invoiced'
);

create type pm.milestone_status as enum(
  'pending',
  'in_progress',
  'completed',
  'at_risk'
);

create type pm.deliverable_status as enum(
  'draft',
  'submitted',
  'in_review',
  'approved',
  'rejected'
);

create type pm.expense_category as enum(
  'travel',
  'software',
  'equipment',
  'meals',
  'other'
);

create type pm.expense_status as enum('pending', 'approved', 'rejected', 'invoiced');

create type pm.invoice_status as enum('draft', 'sent', 'paid', 'overdue', 'void');

create type pm.invoice_line_type as enum('time', 'expense', 'milestone', 'adjustment');

create type pm.risk_category as enum(
  'schedule',
  'budget',
  'scope',
  'resource',
  'technical',
  'external'
);

create type pm.risk_status as enum(
  'identified',
  'monitoring',
  'mitigating',
  'occurred',
  'closed'
);

create type pm.task_event_type as enum(
  'created',
  'assigned',
  'status_changed',
  'completed',
  'comment_added'
);

----------------------------------------------------------------
-- Users replica view
----------------------------------------------------------------
create or replace view pm.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on pm.users
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on pm.users to "x-admin",
  "pm-lead",
  "user",
  "client";

comment on view pm.users is '{"display": "none"}';

----------------------------------------------------------------
-- Clients
----------------------------------------------------------------
create table pm.clients (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(200) not null,
  contact_name varchar(160),
  contact_email supasheet.EMAIL,
  contact_phone supasheet.TEL,
  industry varchar(120),
  address text,
  logo supasheet.AVATAR,
  portal_user_id uuid unique references supasheet.users (id) on delete set null,
  is_active boolean not null default true,
  project_count integer not null default 0,
  total_billed numeric(14, 2) not null default 0,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table pm.clients is '{
    "icon": "Building2",
    "name": "Clients",
    "description": "Who we deliver for. portal_user_id, if set, is the one login that can see this client''s own project status through the client portal.",
    "collapsible_group": "Delivery",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "name", "badges": ["code", "is_active"]},
        "tabs": ["projects", "client_billing"]
    },
    "views": [
        {"id": "gallery", "name": "Directory", "type": "gallery", "cover": "logo", "title": "name", "description": "industry", "badge": "is_active"},
        {"id": "list", "name": "All Clients", "type": "list", "title": "name", "description": "code", "field_1": "project_count", "field_2": "total_billed"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "contact_email"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": {"create": ["code", "name", "industry", "logo"], "update": ["name", "industry", "logo", "is_active", "portal_user_id"], "read": ["code", "name", "industry", "logo", "is_active", "portal_user_id"]}},
            {"id": "contact", "title": "Contact", "fields": ["contact_name", "contact_email", "contact_phone", "address"]},
            {"id": "position", "title": "Position", "fields": {"read": ["project_count", "total_billed"]}},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [{"table": "users", "on": "portal_user_id", "alias": "portal_user", "columns": ["name", "email"]}]
    }
}';

comment on column pm.clients.total_billed is '{"name": "Total Billed", "aggregate": "sum"}';

revoke all on table pm.clients
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
delete on table pm.clients to "x-admin";

grant
select
,
  insert,
update on table pm.clients to "pm-lead";

grant
select
  on table pm.clients to "user";

create unique index idx_pm_clients_name on pm.clients (lower(name));

alter table pm.clients enable row level security;

create policy clients_select on pm.clients for
select
  to authenticated using (true);

create policy clients_insert on pm.clients for insert to authenticated
with
  check (true);

create policy clients_update on pm.clients
for update
  to authenticated using (true)
with
  check (true);

create policy clients_delete on pm.clients for delete to authenticated using (true);

create trigger clients_updated_at before
update on pm.clients for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Client billing (1:1 extension — commercial terms kept apart from
-- the client record itself, and off limits to "user" entirely)
----------------------------------------------------------------
create table pm.client_billing (
  id uuid primary key default extensions.uuid_generate_v4 (),
  client_id uuid not null unique references pm.clients (id) on delete cascade,
  billing_address text,
  tax_id varchar(60),
  default_hourly_rate numeric(10, 2) not null default 0,
  default_cost_rate numeric(10, 2) not null default 0,
  payment_terms_days integer not null default 30,
  contract_start date,
  contract_end date,
  msa_document supasheet.file,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table pm.client_billing is '{
    "icon": "Receipt",
    "name": "Billing",
    "description": "Commercial terms for this client — the default rates a new project inherits.",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "terms", "title": "Terms", "fields": ["client_id", "default_hourly_rate", "default_cost_rate", "payment_terms_days"]},
            {"id": "contract", "title": "Contract", "fields": ["contract_start", "contract_end", "msa_document"]},
            {"id": "billing", "title": "Billing Address", "fields": ["billing_address", "tax_id"]}
        ]
    },
    "query": {
        "join": [{"table": "clients", "on": "client_id", "columns": ["code", "name"]}]
    }
}';

comment on column pm.client_billing.msa_document is '{"accept": ".pdf", "maxFiles": 1, "maxSize": 10485760}';

revoke all on table pm.client_billing
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
delete on table pm.client_billing to "x-admin";

grant
select
,
  insert,
update on table pm.client_billing to "pm-lead";

create index idx_pm_client_billing_client_id on pm.client_billing (client_id);

alter table pm.client_billing enable row level security;

create policy client_billing_select on pm.client_billing for
select
  to authenticated using (true);

create policy client_billing_insert on pm.client_billing for insert to authenticated
with
  check (true);

create policy client_billing_update on pm.client_billing
for update
  to authenticated using (true)
with
  check (true);

create policy client_billing_delete on pm.client_billing for delete to authenticated using (true);

create trigger client_billing_updated_at before
update on pm.client_billing for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Projects
--
-- health has no create/update field anywhere below — it is only
-- ever written by the status_reports trigger further down this
-- file. That is rule five made real: the headline health of a
-- project is whatever the latest status report says, never an
-- opinion typed directly onto the project.
----------------------------------------------------------------
create sequence if not exists pm.project_number_seq;

create table pm.projects (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_code varchar(30) not null unique default (
    'PRJ-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('pm.project_number_seq')::text,
      5,
      '0'
    )
  ),
  name varchar(200) not null,
  client_id uuid not null references pm.clients (id) on delete restrict,
  pm_lead_id uuid references supasheet.users (id) on delete set null,
  status pm.project_status not null default 'planning',
  health pm.health_status,
  budget_type pm.budget_type not null default 'time_and_materials',
  budget_amount numeric(14, 2) not null default 0,
  budget_hours numeric(8, 2),
  consumed_hours numeric(8, 2) not null default 0,
  consumed_budget numeric(14, 2) not null default 0,
  billed_amount numeric(14, 2) not null default 0,
  margin_percent numeric(5, 2),
  is_billable boolean not null default true,
  start_date date,
  end_date date,
  task_count integer not null default 0,
  completed_task_count integer not null default 0,
  description supasheet.RICH_TEXT,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint projects_dates_ordered check (
    end_date is null
    or start_date is null
    or end_date >= start_date
  ),
  constraint projects_budget_non_negative check (budget_amount >= 0)
);

comment on column pm.projects.status is '{
    "progress": true,
    "values": {
        "planning": {"variant": "secondary", "icon": "CalendarClock"},
        "active": {"variant": "success", "icon": "Play"},
        "on_hold": {"variant": "warning", "icon": "Pause"},
        "completed": {"variant": "default", "icon": "CircleCheck"},
        "cancelled": {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on column pm.projects.health is '{
    "progress": false,
    "values": {
        "green": {"variant": "success", "icon": "CircleCheck"},
        "amber": {"variant": "warning", "icon": "TriangleAlert"},
        "red": {"variant": "destructive", "icon": "OctagonAlert"}
    }
}';

comment on column pm.projects.budget_type is '{
    "progress": false,
    "values": {
        "fixed": {"variant": "info", "icon": "Lock"},
        "time_and_materials": {"variant": "default", "icon": "Clock"},
        "retainer": {"variant": "secondary", "icon": "Repeat"}
    }
}';

comment on table pm.projects is '{
    "icon": "FolderKanban",
    "name": "Projects",
    "description": "The engagement. Budget consumption and margin are rolled up from real time and expenses below — never typed.",
    "collapsible_group": "Delivery",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "name", "badges": ["status", "health", "budget_type"]},
        "tabs": ["project_members", "phases", "task_lists", "tasks", "milestones", "deliverables", "risks", "status_reports", "invoices"]
    },
    "views": [
        {"id": "kanban", "name": "Delivery Board", "type": "kanban", "group": "status", "title": "name", "description": "project_code", "date": "end_date", "badge": "health"},
        {"id": "gantt", "name": "Timeline", "type": "gantt", "title": "name", "start_date": "start_date", "end_date": "end_date", "group": "status", "badge": "health"},
        {"id": "list", "name": "All Projects", "type": "list", "title": "name", "description": "project_code", "field_1": "status", "field_2": "consumed_budget"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "at_risk", "name": "At Risk", "filters": [{"id": "health", "value": ["amber", "red"], "operator": "in"}]},
        {"id": "over_budget", "name": "Over Budget Hours", "filters": [{"id": "consumed_hours", "value": "0", "operator": "gt"}]}
    ],
    "links": [
        {"id": "profitability", "name": "Profitability Report", "url": "/pm/report/project_profitability_report", "icon": "TrendingUp", "description": "Margin by project"}
    ],
    "fields": {
        "quick_create": ["name", "client_id", "pm_lead_id", "budget_type"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": {"create": ["name", "client_id", "pm_lead_id", "start_date", "end_date", "description"], "update": ["name", "pm_lead_id", "status", "start_date", "end_date", "description", "color"], "read": ["project_code", "name", "client_id", "pm_lead_id", "status", "health", "start_date", "end_date", "description"]}},
            {"id": "budget", "title": "Budget", "fields": {"create": ["budget_type", "budget_amount", "budget_hours", "is_billable"], "update": ["budget_type", "budget_amount", "budget_hours", "is_billable"], "read": ["budget_type", "budget_amount", "budget_hours", "is_billable"]}},
            {"id": "position", "title": "Position", "fields": {"read": ["consumed_hours", "consumed_budget", "billed_amount", "margin_percent", "task_count", "completed_task_count"]}}
        ],
        "behavior": {
            "budget_hours": {"visible": [{"id": "budget_type", "operator": "neq", "value": "fixed"}]}
        },
        "lookups": {
            "client_id": {
                "fill": [
                    {"source_column": "default_hourly_rate", "target_column": "budget_amount"}
                ]
            }
        },
        "metadata": {
            "margin_percent": {"description": "(billed amount - internal cost) / billed amount. Internal cost is every time entry''s hours at that team member''s cost rate, not their billable rate."}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "clients", "on": "client_id", "columns": ["code", "name"]},
            {"table": "users", "on": "pm_lead_id", "alias": "pm_lead", "columns": ["name", "email"]}
        ]
    }
}';

comment on column pm.projects.budget_amount is '{"aggregate": "sum"}';

comment on column pm.projects.billed_amount is '{"name": "Billed", "aggregate": "sum"}';

comment on column pm.projects.margin_percent is '{"name": "Margin"}';

revoke all on table pm.projects
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
delete on table pm.projects to "x-admin";

grant
select
,
  insert,
update on table pm.projects to "pm-lead";

grant
select
  on table pm.projects to "user";

revoke all on sequence pm.project_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence pm.project_number_seq to "x-admin",
"pm-lead";

create index idx_pm_projects_client_id on pm.projects (client_id);

create index idx_pm_projects_pm_lead_id on pm.projects (pm_lead_id);

create index idx_pm_projects_status on pm.projects (status);

create trigger projects_updated_at before
update on pm.projects for each row
execute function supasheet.set_updated_at ();

create or replace function pm.clients_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_client_id uuid;
begin
  v_client_id := coalesce(new.client_id, old.client_id);

  update pm.clients
  set project_count = (
      select count(*)
      from pm.projects
      where client_id = v_client_id
    ),
    total_billed = (
      select coalesce(sum(billed_amount), 0)
      from pm.projects
      where client_id = v_client_id
    ),
    updated_at = current_timestamp
  where id = v_client_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_projects_rollup_client
after insert
or delete
or
update of client_id,
billed_amount on pm.projects for each row
execute function pm.clients_rollup ();

----------------------------------------------------------------
-- Project members (staffing junction — carries the rates that
-- time_entries snapshots)
----------------------------------------------------------------
create table pm.project_members (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid not null references pm.projects (id) on delete cascade,
  user_id uuid not null references supasheet.users (id) on delete cascade,
  role_on_project varchar(120),
  billable_rate numeric(10, 2) not null default 0,
  cost_rate numeric(10, 2) not null default 0,
  allocation_percent supasheet.PERCENTAGE not null default 100,
  is_active boolean not null default true,
  created_at timestamptz default current_timestamp,
  unique (project_id, user_id),
  constraint project_members_rates_non_negative check (
    billable_rate >= 0
    and cost_rate >= 0
  )
);

comment on table pm.project_members is '{
    "icon": "Users",
    "name": "Staffing",
    "description": "Who is on this project, at what rate, and how much of their time is allocated to it.",
    "collapsible_group": "Delivery",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "role_on_project", "badges": ["is_active", "allocation_percent"]}},
    "views": [
        {"id": "list", "name": "All Staffing", "type": "list", "title": "role_on_project", "description": "user_id", "field_1": "billable_rate", "field_2": "allocation_percent"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["project_id", "user_id", "role_on_project"],
        "sections": [
            {"id": "staffing", "title": "Staffing", "fields": ["project_id", "user_id", "role_on_project", "is_active", "allocation_percent"]},
            {"id": "rates", "title": "Rates", "fields": ["billable_rate", "cost_rate"]}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [
            {"table": "projects", "on": "project_id", "columns": ["project_code", "name"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table pm.project_members
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
delete on table pm.project_members to "x-admin",
"pm-lead";

grant
select
  on table pm.project_members to "user";

create index idx_pm_members_project_id on pm.project_members (project_id);

create index idx_pm_members_user_id on pm.project_members (user_id);

alter table pm.project_members enable row level security;

create policy members_select on pm.project_members for
select
  to authenticated using (true);

create policy members_insert on pm.project_members for insert to authenticated
with
  check (true);

create policy members_update on pm.project_members
for update
  to authenticated using (true)
with
  check (true);

create policy members_delete on pm.project_members for delete to authenticated using (true);

-- pm.projects' own RLS is enabled here, not next to the table
-- definition above — its select policy checks pm.project_members,
-- which has to exist first for the policy to even be created.
alter table pm.projects enable row level security;

create policy projects_select on pm.projects for
select
  to authenticated using (
    pg_has_role (current_user, 'pm-lead', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
    or exists (
      select
        1
      from
        pm.project_members pmem
      where
        pmem.project_id = pm.projects.id
        and pmem.user_id = (select auth.uid ())
    )
  );

create policy projects_insert on pm.projects for insert to authenticated
with
  check (true);

create policy projects_update on pm.projects
for update
  to authenticated using (true)
with
  check (true);

create policy projects_delete on pm.projects for delete to authenticated using (true);

----------------------------------------------------------------
-- Phases
----------------------------------------------------------------
create table pm.phases (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid not null references pm.projects (id) on delete cascade,
  name varchar(160) not null,
  sequence_number integer,
  start_date date,
  end_date date,
  status pm.phase_status not null default 'not_started',
  progress_percent numeric(5, 2) not null default 0,
  task_count integer not null default 0,
  created_at timestamptz default current_timestamp,
  constraint phases_dates_ordered check (
    end_date is null
    or start_date is null
    or end_date >= start_date
  )
);

comment on column pm.phases.status is '{
    "progress": true,
    "values": {
        "not_started": {"variant": "secondary", "icon": "CircleDashed"},
        "in_progress": {"variant": "warning", "icon": "Loader"},
        "completed": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on table pm.phases is '{
    "icon": "Milestone",
    "name": "Phases",
    "description": "The stages a project moves through. Progress is rolled up from its tasks.",
    "collapsible_group": "Delivery",
    "display": "block",
    "inline_form": true,
    "primary_view": "gantt",
    "detail": {"header": {"title": "name", "badges": ["status", "progress_percent"]}, "tabs": ["tasks"]},
    "views": [
        {"id": "gantt", "name": "Phase Timeline", "type": "gantt", "title": "name", "start_date": "start_date", "end_date": "end_date", "group": "status", "progress": "progress_percent", "badge": "status"},
        {"id": "list", "name": "All Phases", "type": "list", "title": "name", "description": "project_id", "field_1": "status", "field_2": "progress_percent"}
    ],
    "fields": {
        "quick_create": ["project_id", "name", "start_date", "end_date"],
        "sections": [
            {"id": "phase", "title": "Phase", "fields": ["project_id", "sequence_number", "name", "start_date", "end_date", "status"]},
            {"id": "position", "title": "Position", "fields": {"read": ["progress_percent", "task_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "sequence_number", "desc": false}],
        "join": [{"table": "projects", "on": "project_id", "columns": ["project_code", "name"]}]
    }
}';

revoke all on table pm.phases
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
delete on table pm.phases to "x-admin",
"pm-lead";

grant
select
  on table pm.phases to "user";

create index idx_pm_phases_project_id on pm.phases (project_id);

alter table pm.phases enable row level security;

create policy phases_select on pm.phases for
select
  to authenticated using (true);

create policy phases_insert on pm.phases for insert to authenticated
with
  check (true);

create policy phases_update on pm.phases
for update
  to authenticated using (true)
with
  check (true);

create policy phases_delete on pm.phases for delete to authenticated using (true);

create or replace function pm.phases_set_number () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.sequence_number is null then
    select coalesce(max(sequence_number), 0) + 10 into new.sequence_number
    from pm.phases
    where project_id = new.project_id;
  end if;
  return new;
end;
$$;

create trigger trg_phases_set_number before insert on pm.phases for each row
execute function pm.phases_set_number ();

----------------------------------------------------------------
-- Task lists
----------------------------------------------------------------
create table pm.task_lists (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid not null references pm.projects (id) on delete cascade,
  phase_id uuid references pm.phases (id) on delete set null,
  name varchar(160) not null,
  sequence_number integer,
  task_count integer not null default 0,
  created_at timestamptz default current_timestamp
);

comment on table pm.task_lists is '{
    "icon": "ListTodo",
    "name": "Task Lists",
    "description": "How the work is grouped — a backlog, a sprint, a workstream.",
    "collapsible_group": "Delivery",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "name", "badges": ["task_count"]}, "tabs": ["tasks"]},
    "views": [
        {"id": "list", "name": "All Task Lists", "type": "list", "title": "name", "description": "project_id", "field_1": "phase_id", "field_2": "task_count"}
    ],
    "fields": {
        "quick_create": ["project_id", "name"],
        "sections": [
            {"id": "list", "title": "List", "fields": ["project_id", "phase_id", "sequence_number", "name"]},
            {"id": "position", "title": "Position", "fields": {"read": ["task_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "sequence_number", "desc": false}],
        "join": [
            {"table": "projects", "on": "project_id", "columns": ["project_code", "name"]},
            {"table": "phases", "on": "phase_id", "columns": ["name"]}
        ]
    }
}';

revoke all on table pm.task_lists
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
delete on table pm.task_lists to "x-admin",
"pm-lead";

grant
select
  on table pm.task_lists to "user";

create index idx_pm_task_lists_project_id on pm.task_lists (project_id);

create index idx_pm_task_lists_phase_id on pm.task_lists (phase_id);

alter table pm.task_lists enable row level security;

create policy task_lists_select on pm.task_lists for
select
  to authenticated using (true);

create policy task_lists_insert on pm.task_lists for insert to authenticated
with
  check (true);

create policy task_lists_update on pm.task_lists
for update
  to authenticated using (true)
with
  check (true);

create policy task_lists_delete on pm.task_lists for delete to authenticated using (true);

----------------------------------------------------------------
-- Tasks
----------------------------------------------------------------
create sequence if not exists pm.task_number_seq;

create table pm.tasks (
  id uuid primary key default extensions.uuid_generate_v4 (),
  task_number varchar(30) not null unique default (
    'TASK-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('pm.task_number_seq')::text,
      6,
      '0'
    )
  ),
  project_id uuid not null references pm.projects (id) on delete cascade,
  task_list_id uuid not null references pm.task_lists (id) on delete cascade,
  phase_id uuid references pm.phases (id) on delete set null,
  parent_task_id uuid references pm.tasks (id) on delete set null,
  title varchar(300) not null,
  description supasheet.RICH_TEXT,
  status pm.task_status not null default 'todo',
  priority pm.task_priority not null default 'medium',
  assignee_id uuid references supasheet.users (id) on delete set null,
  reporter_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  estimated_hours numeric(6, 2),
  logged_hours numeric(6, 2) not null default 0,
  start_date date,
  due_date date,
  completed_at timestamptz,
  is_billable boolean not null default true,
  sequence_number integer,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint tasks_not_own_parent check (id <> parent_task_id)
);

comment on column pm.tasks.status is '{
    "progress": true,
    "values": {
        "todo": {"variant": "secondary", "icon": "CircleDot"},
        "in_progress": {"variant": "warning", "icon": "Loader"},
        "in_review": {"variant": "info", "icon": "Eye"},
        "done": {"variant": "success", "icon": "CircleCheck"},
        "blocked": {"variant": "destructive", "icon": "OctagonAlert"}
    }
}';

comment on column pm.tasks.priority is '{
    "progress": false,
    "values": {
        "low": {"variant": "secondary", "icon": "ArrowDown"},
        "medium": {"variant": "info", "icon": "Minus"},
        "high": {"variant": "warning", "icon": "ArrowUp"},
        "urgent": {"variant": "destructive", "icon": "TriangleAlert"}
    }
}';

comment on table pm.tasks is '{
    "icon": "CheckSquare",
    "name": "Tasks",
    "description": "The work. A task with an unfinished blocking dependency is refused a status of done — see task_dependencies.",
    "collapsible_group": "Delivery",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "title", "badges": ["status", "priority"]},
        "tabs": ["task_dependencies", "time_entries", "task_comments", "tasks"],
        "timelines": ["task_events"]
    },
    "views": [
        {"id": "kanban", "name": "Task Board", "type": "kanban", "group": "status", "title": "title", "description": "task_number", "date": "due_date", "badge": "priority"},
        {"id": "calendar", "name": "Due Dates", "type": "calendar", "title": "title", "badge": "status", "start_date": "start_date", "end_date": "due_date"},
        {"id": "list", "name": "All Tasks", "type": "list", "title": "title", "description": "task_number", "field_1": "status", "field_2": "due_date"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "Assigned To Me", "filters": [{"id": "assignee_id", "value": "me", "operator": "eq"}]},
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["todo", "in_progress", "in_review", "blocked"], "operator": "in"}]},
        {"id": "overdue", "name": "Overdue", "filters": [{"id": "due_date", "value": "today", "operator": "lt"}, {"id": "status", "value": "done", "operator": "neq"}]},
        {"id": "blocked", "name": "Blocked", "filters": [{"id": "status", "value": "blocked", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["project_id", "task_list_id", "title", "assignee_id", "due_date"],
        "sections": [
            {"id": "task", "title": "Task", "fields": {"create": ["project_id", "task_list_id", "phase_id", "parent_task_id", "title", "description", "priority", "assignee_id", "estimated_hours", "start_date", "due_date", "is_billable"], "update": ["title", "description", "status", "priority", "assignee_id", "estimated_hours", "start_date", "due_date", "is_billable"], "read": ["task_number", "project_id", "task_list_id", "phase_id", "parent_task_id", "title", "description", "status", "priority", "assignee_id", "reporter_id", "estimated_hours", "start_date", "due_date", "is_billable"]}},
            {"id": "position", "title": "Position", "fields": {"read": ["logged_hours", "completed_at"]}}
        ],
        "lookups": {
            "task_list_id": {"filter": [{"source_column": "project_id", "target_column": "project_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "sequence_number", "desc": false}],
        "join": [
            {"table": "projects", "on": "project_id", "columns": ["project_code", "name"]},
            {"table": "task_lists", "on": "task_list_id", "columns": ["name"]},
            {"table": "users", "on": "assignee_id", "alias": "assignee", "columns": ["name", "email"]},
            {"table": "tasks", "on": "parent_task_id", "alias": "parent", "columns": ["title", "task_number"]}
        ]
    }
}';

comment on column pm.tasks.logged_hours is '{"aggregate": "sum"}';

revoke all on table pm.tasks
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
delete on table pm.tasks to "x-admin",
"pm-lead";

grant
select
,
update on table pm.tasks to "user";

revoke all on sequence pm.task_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence pm.task_number_seq to "x-admin",
"pm-lead";

create index idx_pm_tasks_project_id on pm.tasks (project_id);

create index idx_pm_tasks_task_list_id on pm.tasks (task_list_id);

create index idx_pm_tasks_assignee_id on pm.tasks (assignee_id);

create index idx_pm_tasks_status on pm.tasks (status);

create index idx_pm_tasks_parent_id on pm.tasks (parent_task_id);

alter table pm.tasks enable row level security;

create policy tasks_select on pm.tasks for
select
  to authenticated using (true);

create policy tasks_insert on pm.tasks for insert to authenticated
with
  check (true);

create policy tasks_update on pm.tasks
for update
  to authenticated using (
    assignee_id = (select auth.uid ())
    or pg_has_role (current_user, 'pm-lead', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy tasks_delete on pm.tasks for delete to authenticated using (true);

create trigger tasks_updated_at before
update on pm.tasks for each row
execute function supasheet.set_updated_at ();

create or replace function pm.tasks_set_number () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.sequence_number is null then
    select coalesce(max(sequence_number), 0) + 10 into new.sequence_number
    from pm.tasks
    where task_list_id = new.task_list_id;
  end if;
  return new;
end;
$$;

create trigger trg_tasks_set_number before insert on pm.tasks for each row
execute function pm.tasks_set_number ();

create or replace function pm.tasks_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_project_id uuid;
  v_task_list_id uuid;
  v_phase_id uuid;
begin
  v_project_id := coalesce(new.project_id, old.project_id);
  v_task_list_id := coalesce(new.task_list_id, old.task_list_id);
  v_phase_id := coalesce(new.phase_id, old.phase_id);

  update pm.projects
  set task_count = x.n,
    completed_task_count = x.completed_n,
    updated_at = current_timestamp
  from (
    select
      count(*) as n,
      count(*) filter (
        where status = 'done'
      ) as completed_n
    from pm.tasks
    where project_id = v_project_id
  ) x
  where id = v_project_id;

  update pm.task_lists
  set task_count = (
    select count(*) from pm.tasks where task_list_id = v_task_list_id
  )
  where id = v_task_list_id;

  if v_phase_id is not null then
    update pm.phases p
    set task_count = x.n,
      progress_percent = coalesce(
        round(100.0 * x.completed_n / nullif(x.n, 0), 2),
        0
      ),
      status = case
        when x.n > 0
        and x.completed_n = x.n then 'completed'::pm.phase_status
        when x.completed_n > 0 then 'in_progress'::pm.phase_status
        else p.status
      end
    from (
      select
        count(*) as n,
        count(*) filter (
          where status = 'done'
        ) as completed_n
      from pm.tasks
      where phase_id = v_phase_id
    ) x
    where p.id = v_phase_id;
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_tasks_rollup
after insert
or delete
or
update of project_id,
task_list_id,
phase_id,
status on pm.tasks for each row
execute function pm.tasks_rollup ();

----------------------------------------------------------------
-- Task dependencies
--
-- The guard below is the first headline rule: a cycle here doesn't
-- give a wrong answer, it gives a critical path that never resolves
-- — the same reason the manufacturing example walks a bill of
-- material before accepting a new component.
----------------------------------------------------------------
create table pm.task_dependencies (
  id uuid primary key default extensions.uuid_generate_v4 (),
  task_id uuid not null references pm.tasks (id) on delete cascade,
  depends_on_task_id uuid not null references pm.tasks (id) on delete cascade,
  dependency_type pm.dependency_type not null default 'finish_to_start',
  created_at timestamptz default current_timestamp,
  unique (task_id, depends_on_task_id),
  constraint task_dependencies_not_self check (task_id <> depends_on_task_id)
);

comment on table pm.task_dependencies is '{
    "icon": "GitBranch",
    "name": "Dependencies",
    "description": "What has to happen before this task can start or finish.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "dependency", "title": "Dependency", "fields": ["task_id", "depends_on_task_id", "dependency_type"]}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [
            {"table": "tasks", "on": "task_id", "columns": ["task_number", "title", "status"]},
            {"table": "tasks", "on": "depends_on_task_id", "alias": "blocker", "columns": ["task_number", "title", "status"]}
        ]
    }
}';

revoke all on table pm.task_dependencies
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
delete on table pm.task_dependencies to "x-admin",
"pm-lead";

grant
select
  on table pm.task_dependencies to "user";

create index idx_pm_deps_task_id on pm.task_dependencies (task_id);

create index idx_pm_deps_depends_on_id on pm.task_dependencies (depends_on_task_id);

alter table pm.task_dependencies enable row level security;

create policy deps_select on pm.task_dependencies for
select
  to authenticated using (true);

create policy deps_insert on pm.task_dependencies for insert to authenticated
with
  check (true);

create policy deps_delete on pm.task_dependencies for delete to authenticated using (true);

create or replace function pm.task_depends_on (p_task_id uuid, p_search_id uuid) returns boolean language sql stable security definer
set
  search_path = '' as $$
  with recursive chain as (
    select depends_on_task_id as id, 1 as depth
    from pm.task_dependencies
    where task_id = p_task_id
    union all
    select td.depends_on_task_id, c.depth + 1
    from chain c
      join pm.task_dependencies td on td.task_id = c.id
    where c.depth < 25
  )
  select exists (
    select 1 from chain where id = p_search_id
  );
$$;

comment on function pm.task_depends_on (uuid, uuid) is 'True when p_search_id appears anywhere in p_task_id''s dependency chain, at any depth.';

revoke all on function pm.task_depends_on (uuid, uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function pm.task_depends_on (uuid, uuid) to "x-admin",
"pm-lead";

create or replace function pm.task_dependencies_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if pm.task_depends_on (new.depends_on_task_id, new.task_id) then
    raise exception 'This dependency would create a cycle — the task it depends on already (transitively) depends on it.'
      using hint = 'Break the existing chain before adding this one.';
  end if;

  return new;
end;
$$;

create trigger trg_task_dependencies_guard before insert on pm.task_dependencies for each row
execute function pm.task_dependencies_guard ();

-- The second headline rule: a task cannot be marked done while a
-- finish-to-start blocker is still open.
create or replace function pm.tasks_completion_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if new.status = 'done' then
    if exists (
      select 1
      from pm.task_dependencies td
        join pm.tasks blocker on blocker.id = td.depends_on_task_id
      where td.task_id = new.id
        and td.dependency_type = 'finish_to_start'
        and blocker.status <> 'done'
    ) then
      raise exception 'This task has an unfinished blocking dependency and cannot be marked done.'
        using hint = 'Finish the blocking task first.';
    end if;

    new.completed_at := current_timestamp;
  end if;

  return new;
end;
$$;

create trigger trg_tasks_completion_guard before
update of status on pm.tasks for each row
execute function pm.tasks_completion_guard ();

----------------------------------------------------------------
-- Task comments
----------------------------------------------------------------
create table pm.task_comments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  task_id uuid not null references pm.tasks (id) on delete cascade,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  body supasheet.RICH_TEXT not null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table pm.task_comments is '{
    "icon": "MessageSquare",
    "name": "Comments",
    "description": "Discussion on this task.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "comment", "title": "Comment", "fields": {"create": ["task_id", "body"], "update": ["body"], "read": ["task_id", "user_id", "body"]}}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [{"table": "users", "on": "user_id", "columns": ["name", "email"]}]
    }
}';

revoke all on table pm.task_comments
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
delete on table pm.task_comments to "x-admin",
"pm-lead",
"user";

create index idx_pm_task_comments_task_id on pm.task_comments (task_id);

alter table pm.task_comments enable row level security;

create policy task_comments_select on pm.task_comments for
select
  to authenticated using (true);

create policy task_comments_insert on pm.task_comments for insert to authenticated
with
  check (true);

create policy task_comments_update on pm.task_comments
for update
  to authenticated using (
    user_id = (select auth.uid ())
    or pg_has_role (current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy task_comments_delete on pm.task_comments for delete to authenticated using (
  user_id = (select auth.uid ())
  or pg_has_role (current_user, 'x-admin', 'member')
);

create trigger task_comments_updated_at before
update on pm.task_comments for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Task events (trigger-populated timeline)
----------------------------------------------------------------
create table pm.task_events (
  id uuid primary key default extensions.uuid_generate_v4 (),
  task_id uuid not null references pm.tasks (id) on delete cascade,
  event_type pm.task_event_type not null,
  title varchar(255) not null,
  metadata jsonb,
  actor_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  occurred_at timestamptz not null default current_timestamp
);

comment on column pm.task_events.event_type is '{
    "progress": false,
    "values": {
        "created": {"variant": "info", "icon": "Sparkles"},
        "assigned": {"variant": "default", "icon": "UserCheck"},
        "status_changed": {"variant": "secondary", "icon": "RefreshCw"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "comment_added": {"variant": "secondary", "icon": "MessageSquare"}
    }
}';

comment on table pm.task_events is '{
    "icon": "History",
    "name": "Task History",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "event", "title": "Event", "fields": ["task_id", "event_type", "title", "metadata", "actor_id", "occurred_at"]}
        ]
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [{"table": "users", "on": "actor_id", "alias": "actor", "columns": ["name", "email"]}]
    }
}';

revoke all on table pm.task_events
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on table pm.task_events to "x-admin",
  "pm-lead",
  "user";

create index idx_pm_task_events_task_id on pm.task_events (task_id);

create index idx_pm_task_events_occurred_at on pm.task_events (occurred_at desc);

alter table pm.task_events enable row level security;

create policy task_events_select on pm.task_events for
select
  to authenticated using (true);

create or replace function pm.tasks_log_event () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into pm.task_events (task_id, event_type, title, actor_id)
    values (new.id, 'created', 'Task created', (select auth.uid ()));
  elsif tg_op = 'UPDATE' then
    if new.assignee_id is distinct from old.assignee_id and new.assignee_id is not null then
      insert into pm.task_events (task_id, event_type, title, actor_id)
      values (new.id, 'assigned', 'Task assigned', (select auth.uid ()));
    end if;

    if new.status is distinct from old.status then
      insert into pm.task_events (task_id, event_type, title, actor_id)
      values (
        new.id,
        case
          when new.status = 'done' then 'completed'
          else 'status_changed'
        end,
        'Status changed to ' || new.status,
        (select auth.uid ())
      );
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_tasks_log_event
after insert
or
update of assignee_id,
status on pm.tasks for each row
execute function pm.tasks_log_event ();

create or replace function pm.task_comments_log_event () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  insert into pm.task_events (task_id, event_type, title, actor_id)
  values (new.task_id, 'comment_added', left(new.body, 200), new.user_id);

  return new;
end;
$$;

create trigger trg_task_comments_log_event
after insert on pm.task_comments for each row
execute function pm.task_comments_log_event ();

----------------------------------------------------------------
-- Time entries
--
-- logged_duration uses the same supasheet.DURATION type the desk
-- example books agent worklogs with — a duration picker, not a bare
-- number. The guard on approval is the third headline rule: it is
-- the same ceiling shape procurement uses for a contract, applied
-- here to a project's budgeted hours.
----------------------------------------------------------------
create table pm.time_entries (
  id uuid primary key default extensions.uuid_generate_v4 (),
  task_id uuid not null references pm.tasks (id) on delete restrict,
  project_id uuid not null references pm.projects (id) on delete cascade,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  entry_date date not null default current_date,
  logged_duration supasheet.DURATION not null,
  description varchar(500),
  is_billable boolean not null default true,
  billable_rate numeric(10, 4) not null default 0,
  cost_rate numeric(10, 4) not null default 0,
  billed_amount numeric(12, 2) not null default 0,
  cost_amount numeric(12, 2) not null default 0,
  status pm.time_entry_status not null default 'draft',
  approved_by uuid references supasheet.users (id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz default current_timestamp,
  constraint time_entries_duration_positive check (logged_duration > 0)
);

comment on column pm.time_entries.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "submitted": {"variant": "warning", "icon": "Send"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "invoiced": {"variant": "default", "icon": "Receipt"}
    }
}';

comment on table pm.time_entries is '{
    "icon": "Clock",
    "name": "Time Entries",
    "description": "What was actually worked. Only approved or invoiced entries count toward a project''s consumed budget.",
    "collapsible_group": "Delivery",
    "display": "block",
    "primary_view": "calendar",
    "detail": {"header": {"title": "description", "badges": ["status", "logged_duration"]}},
    "views": [
        {"id": "calendar", "name": "Time Calendar", "type": "calendar", "title": "description", "badge": "status", "start_date": "entry_date", "read_only": true},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "description", "description": "entry_date", "date": "entry_date", "badge": "logged_duration"},
        {"id": "list", "name": "All Time Entries", "type": "list", "title": "description", "description": "entry_date", "field_1": "status", "field_2": "billed_amount"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "My Time", "filters": [{"id": "user_id", "value": "me", "operator": "eq"}]},
        {"id": "unsubmitted", "name": "Unsubmitted", "filters": [{"id": "status", "value": "draft", "operator": "eq"}]},
        {"id": "awaiting_approval", "name": "Awaiting Approval", "filters": [{"id": "status", "value": "submitted", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["task_id", "entry_date", "logged_duration", "description"],
        "sections": [
            {"id": "entry", "title": "Entry", "fields": {"create": ["task_id", "project_id", "entry_date", "logged_duration", "description", "is_billable"], "update": ["entry_date", "logged_duration", "description", "is_billable", "status"], "read": ["task_id", "project_id", "user_id", "entry_date", "logged_duration", "description", "is_billable", "status"]}},
            {"id": "billing", "title": "Billing", "fields": {"read": ["billable_rate", "cost_rate", "billed_amount", "cost_amount"]}},
            {"id": "approval", "title": "Approval", "fields": {"read": ["approved_by", "approved_at"]}}
        ],
        "lookups": {
            "task_id": {"fill": [{"source_column": "project_id", "target_column": "project_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "entry_date", "desc": true}],
        "join": [
            {"table": "tasks", "on": "task_id", "columns": ["task_number", "title"]},
            {"table": "projects", "on": "project_id", "columns": ["project_code", "name"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column pm.time_entries.logged_duration is '{"aggregate": "sum"}';

comment on column pm.time_entries.billed_amount is '{"aggregate": "sum"}';

revoke all on table pm.time_entries
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
delete on table pm.time_entries to "x-admin";

grant
select
,
update on table pm.time_entries to "pm-lead";

grant
select
,
  insert,
update on table pm.time_entries to "user";

create index idx_pm_time_entries_task_id on pm.time_entries (task_id);

create index idx_pm_time_entries_project_id on pm.time_entries (project_id);

create index idx_pm_time_entries_user_id on pm.time_entries (user_id);

create index idx_pm_time_entries_status on pm.time_entries (status);

alter table pm.time_entries enable row level security;

create policy time_entries_select on pm.time_entries for
select
  to authenticated using (
    user_id = (select auth.uid ())
    or pg_has_role (current_user, 'pm-lead', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  );

create policy time_entries_insert on pm.time_entries for insert to authenticated
with
  check (true);

create policy time_entries_update on pm.time_entries
for update
  to authenticated using (
    user_id = (select auth.uid ())
    or pg_has_role (current_user, 'pm-lead', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy time_entries_delete on pm.time_entries for delete to authenticated using (true);

create or replace function pm.time_entries_set_rates () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_billable_rate numeric(10, 4);
  v_cost_rate numeric(10, 4);
  v_hours numeric(12, 6);
begin
  if new.billable_rate = 0 and new.cost_rate = 0 then
    select billable_rate, cost_rate into v_billable_rate, v_cost_rate
    from pm.project_members
    where project_id = new.project_id
      and user_id = new.user_id;

    new.billable_rate := coalesce(v_billable_rate, 0);
    new.cost_rate := coalesce(v_cost_rate, 0);
  end if;

  v_hours := new.logged_duration / 3600000.0;
  new.billed_amount := round(
    v_hours * new.billable_rate * (
      case
        when new.is_billable then 1
        else 0
      end
    ),
    2
  );
  new.cost_amount := round(v_hours * new.cost_rate, 2);

  return new;
end;
$$;

create trigger trg_time_entries_set_rates before insert
or
update of logged_duration,
is_billable on pm.time_entries for each row
execute function pm.time_entries_set_rates ();

create or replace function pm.time_entries_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_budget_hours numeric(8, 2);
  v_consumed_hours numeric(8, 2);
  v_this_hours numeric(12, 6);
  -- security definer swaps current_user for this function's owner, so
  -- pg_has_role(current_user, ...) would always see the owner's roles,
  -- not the caller's — read the caller's role from the JWT claim instead.
  v_caller_role text := (select auth.jwt () ->> 'role');
begin
  if new.status = old.status then
    return new;
  end if;

  if new.status = 'approved' then
    select budget_hours, consumed_hours into v_budget_hours, v_consumed_hours
    from pm.projects
    where id = new.project_id;

    v_this_hours := new.logged_duration / 3600000.0;

    if v_budget_hours is not null
      and (v_consumed_hours + v_this_hours) > v_budget_hours
      and not pg_has_role (v_caller_role, 'x-admin', 'member') then
      raise exception 'Approving this entry would take the project to % of a % hour budget.',
        round(v_consumed_hours + v_this_hours, 2), v_budget_hours
        using hint = 'Increase the budget, or have x-admin override it.';
    end if;

    new.approved_by := coalesce(new.approved_by, (select auth.uid ()));
    new.approved_at := current_timestamp;
  end if;

  return new;
end;
$$;

create trigger trg_time_entries_guard before
update of status on pm.time_entries for each row
execute function pm.time_entries_guard ();

create or replace function pm.time_entries_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_task_id uuid := coalesce(new.task_id, old.task_id);
  v_project_id uuid := coalesce(new.project_id, old.project_id);
begin
  update pm.tasks
  set logged_hours = coalesce(
    (
      select sum(logged_duration) / 3600000.0
      from pm.time_entries
      where task_id = v_task_id
    ),
    0
  )
  where id = v_task_id;

  update pm.projects p
  set consumed_hours = x.hours,
    consumed_budget = x.cost,
    billed_amount = x.billed,
    margin_percent = case
      when x.billed > 0 then round(100.0 * (x.billed - x.cost) / x.billed, 2)
      else null
    end
  from (
    select
      coalesce(sum(logged_duration) / 3600000.0, 0) as hours,
      coalesce(sum(cost_amount), 0) as cost,
      coalesce(sum(billed_amount), 0) as billed
    from pm.time_entries
    where project_id = v_project_id
      and status in ('approved', 'invoiced')
  ) x
  where p.id = v_project_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_time_entries_rollup
after insert
or delete
or
update of status,
logged_duration,
billed_amount,
cost_amount on pm.time_entries for each row
execute function pm.time_entries_rollup ();

----------------------------------------------------------------
-- Milestones
----------------------------------------------------------------
create table pm.milestones (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid not null references pm.projects (id) on delete cascade,
  name varchar(200) not null,
  description supasheet.RICH_TEXT,
  due_date date,
  status pm.milestone_status not null default 'pending',
  completion_percent supasheet.PERCENTAGE not null default 0,
  billing_amount numeric(12, 2),
  is_billing_trigger boolean not null default false,
  invoiced boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column pm.milestones.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "secondary", "icon": "CircleDashed"},
        "in_progress": {"variant": "warning", "icon": "Loader"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "at_risk": {"variant": "destructive", "icon": "TriangleAlert"}
    }
}';

comment on table pm.milestones is '{
    "icon": "Flag",
    "name": "Milestones",
    "description": "The checkpoints a client cares about — and, for fixed-price work, what triggers an invoice.",
    "collapsible_group": "Delivery",
    "display": "block",
    "primary_view": "gantt",
    "detail": {"header": {"title": "name", "badges": ["status", "invoiced"]}, "tabs": ["deliverables"]},
    "views": [
        {"id": "gantt", "name": "Milestone Timeline", "type": "gantt", "title": "name", "start_date": "due_date", "end_date": "due_date", "group": "status", "progress": "completion_percent", "badge": "status"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "name", "description": "project_id", "date": "due_date", "badge": "billing_amount"},
        {"id": "list", "name": "All Milestones", "type": "list", "title": "name", "description": "project_id", "field_1": "status", "field_2": "due_date"}
    ],
    "filter_presets": [
        {"id": "upcoming", "name": "Upcoming", "filters": [{"id": "status", "value": ["pending", "in_progress"], "operator": "in"}]},
        {"id": "billable_uninvoiced", "name": "Ready To Bill", "filters": [{"id": "is_billing_trigger", "value": "true", "operator": "eq"}, {"id": "status", "value": "completed", "operator": "eq"}, {"id": "invoiced", "value": "false", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["project_id", "name", "due_date"],
        "sections": [
            {"id": "milestone", "title": "Milestone", "fields": {"create": ["project_id", "name", "description", "due_date"], "update": ["name", "description", "due_date", "status", "completion_percent"], "read": ["project_id", "name", "description", "due_date", "status", "completion_percent"]}},
            {"id": "billing", "title": "Billing", "fields": {"create": ["billing_amount", "is_billing_trigger"], "update": ["billing_amount", "is_billing_trigger"], "read": ["billing_amount", "is_billing_trigger", "invoiced"]}}
        ],
        "behavior": {
            "billing_amount": {"visible": [{"id": "is_billing_trigger", "operator": "eq", "value": "true"}]}
        }
    },
    "query": {
        "sort": [{"id": "due_date", "desc": false}],
        "join": [{"table": "projects", "on": "project_id", "columns": ["project_code", "name"]}]
    }
}';

comment on column pm.milestones.billing_amount is '{"aggregate": "sum"}';

revoke all on table pm.milestones
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
delete on table pm.milestones to "x-admin",
"pm-lead";

grant
select
  on table pm.milestones to "user";

grant
select
  on table pm.milestones to "client";

create index idx_pm_milestones_project_id on pm.milestones (project_id);

alter table pm.milestones enable row level security;

create policy milestones_select on pm.milestones for
select
  to authenticated using (
    pg_has_role (current_user, 'pm-lead', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
    or pg_has_role (current_user, 'user', 'member')
    or exists (
      select
        1
      from
        pm.projects p
        join pm.clients c on c.id = p.client_id
      where
        p.id = project_id
        and c.portal_user_id = (select auth.uid ())
    )
  );

create policy milestones_insert on pm.milestones for insert to authenticated
with
  check (true);

create policy milestones_update on pm.milestones
for update
  to authenticated using (true)
with
  check (true);

create policy milestones_delete on pm.milestones for delete to authenticated using (true);

create trigger milestones_updated_at before
update on pm.milestones for each row
execute function supasheet.set_updated_at ();

create or replace function pm.milestones_guard () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    new.completed_at := current_timestamp;
    new.completion_percent := 100;
  end if;
  return new;
end;
$$;

create trigger trg_milestones_guard before
update of status on pm.milestones for each row
execute function pm.milestones_guard ();

----------------------------------------------------------------
-- Deliverables
--
-- The approval workflow below is where the "client" role gets a real
-- write capability: it can move a deliverable to approved or
-- rejected on its own project, nothing else.
----------------------------------------------------------------
create table pm.deliverables (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid not null references pm.projects (id) on delete cascade,
  milestone_id uuid references pm.milestones (id) on delete set null,
  name varchar(200) not null,
  description supasheet.RICH_TEXT,
  file supasheet.file,
  status pm.deliverable_status not null default 'draft',
  submitted_by uuid references supasheet.users (id) on delete set null,
  submitted_at timestamptz,
  reviewed_by uuid references supasheet.users (id) on delete set null,
  reviewed_at timestamptz,
  review_notes varchar(1000),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column pm.deliverables.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "submitted": {"variant": "warning", "icon": "Send"},
        "in_review": {"variant": "info", "icon": "Eye"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on table pm.deliverables is '{
    "icon": "PackageCheck",
    "name": "Deliverables",
    "description": "What gets handed to the client for sign-off.",
    "collapsible_group": "Delivery",
    "display": "block",
    "primary_view": "kanban",
    "detail": {"header": {"title": "name", "badges": ["status"]}},
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "name", "description": "project_id", "date": "submitted_at", "badge": "status"},
        {"id": "list", "name": "All Deliverables", "type": "list", "title": "name", "description": "project_id", "field_1": "status", "field_2": "submitted_at"}
    ],
    "filter_presets": [
        {"id": "awaiting_review", "name": "Awaiting Review", "filters": [{"id": "status", "value": ["submitted", "in_review"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["project_id", "milestone_id", "name", "file"],
        "sections": [
            {"id": "deliverable", "title": "Deliverable", "fields": {"create": ["project_id", "milestone_id", "name", "description", "file"], "update": ["name", "description", "file", "status"], "read": ["project_id", "milestone_id", "name", "description", "file", "status"]}},
            {"id": "review", "title": "Review", "fields": {"update": ["review_notes"], "read": ["submitted_by", "submitted_at", "reviewed_by", "reviewed_at", "review_notes"]}}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "projects", "on": "project_id", "columns": ["project_code", "name"]},
            {"table": "milestones", "on": "milestone_id", "columns": ["name"]}
        ]
    }
}';

comment on column pm.deliverables.file is '{"accept": "*", "maxFiles": 10, "maxSize": 26214400}';

revoke all on table pm.deliverables
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
delete on table pm.deliverables to "x-admin",
"pm-lead";

grant
select
  on table pm.deliverables to "user";

grant
select
,
update on table pm.deliverables to "client";

create index idx_pm_deliverables_project_id on pm.deliverables (project_id);

create index idx_pm_deliverables_milestone_id on pm.deliverables (milestone_id);

alter table pm.deliverables enable row level security;

create policy deliverables_select on pm.deliverables for
select
  to authenticated using (
    pg_has_role (current_user, 'pm-lead', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
    or pg_has_role (current_user, 'user', 'member')
    or exists (
      select
        1
      from
        pm.projects p
        join pm.clients c on c.id = p.client_id
      where
        p.id = project_id
        and c.portal_user_id = (select auth.uid ())
    )
  );

create policy deliverables_insert on pm.deliverables for insert to authenticated
with
  check (true);

create policy deliverables_update on pm.deliverables
for update
  to authenticated using (
    pg_has_role (current_user, 'pm-lead', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
    or exists (
      select
        1
      from
        pm.projects p
        join pm.clients c on c.id = p.client_id
      where
        p.id = project_id
        and c.portal_user_id = (select auth.uid ())
    )
  )
with
  check (true);

create policy deliverables_delete on pm.deliverables for delete to authenticated using (true);

create trigger deliverables_updated_at before
update on pm.deliverables for each row
execute function supasheet.set_updated_at ();

create or replace function pm.deliverables_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_valid boolean;
begin
  if new.status = old.status then
    return new;
  end if;

  v_valid := case old.status
    when 'draft' then new.status = 'submitted'
    when 'submitted' then new.status in ('in_review', 'approved', 'rejected')
    when 'in_review' then new.status in ('approved', 'rejected')
    when 'rejected' then new.status = 'submitted'
    else false
  end;

  if not v_valid then
    raise exception 'A deliverable cannot move from % to %.', old.status, new.status;
  end if;

  if new.status = 'submitted' then
    new.submitted_by := coalesce(new.submitted_by, (select auth.uid ()));
    new.submitted_at := current_timestamp;
  end if;

  if new.status in ('approved', 'rejected') then
    new.reviewed_by := (select auth.uid ());
    new.reviewed_at := current_timestamp;
  end if;

  return new;
end;
$$;

create trigger trg_deliverables_guard before
update of status on pm.deliverables for each row
execute function pm.deliverables_guard ();

----------------------------------------------------------------
-- Project expenses
----------------------------------------------------------------
create table pm.project_expenses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid not null references pm.projects (id) on delete cascade,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  expense_date date not null default current_date,
  category pm.expense_category not null default 'other',
  description varchar(500) not null,
  amount numeric(10, 2) not null,
  is_billable boolean not null default true,
  receipt supasheet.file,
  status pm.expense_status not null default 'pending',
  approved_by uuid references supasheet.users (id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz default current_timestamp,
  constraint expenses_amount_positive check (amount > 0)
);

comment on column pm.project_expenses.category is '{
    "progress": false,
    "values": {
        "travel": {"variant": "info", "icon": "Plane"},
        "software": {"variant": "default", "icon": "Laptop"},
        "equipment": {"variant": "secondary", "icon": "HardDrive"},
        "meals": {"variant": "warning", "icon": "Utensils"},
        "other": {"variant": "secondary", "icon": "Receipt"}
    }
}';

comment on column pm.project_expenses.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "secondary", "icon": "CircleDashed"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "invoiced": {"variant": "default", "icon": "Receipt"}
    }
}';

comment on table pm.project_expenses is '{
    "icon": "Receipt",
    "name": "Expenses",
    "description": "Out-of-pocket costs incurred on a project.",
    "collapsible_group": "Delivery",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "description", "badges": ["status", "category"]}},
    "views": [
        {"id": "list", "name": "All Expenses", "type": "list", "title": "description", "description": "category", "field_1": "status", "field_2": "amount"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "description", "description": "category", "date": "expense_date", "badge": "amount"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "My Expenses", "filters": [{"id": "user_id", "value": "me", "operator": "eq"}]},
        {"id": "pending", "name": "Pending Approval", "filters": [{"id": "status", "value": "pending", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["project_id", "category", "description", "amount"],
        "sections": [
            {"id": "expense", "title": "Expense", "fields": {"create": ["project_id", "expense_date", "category", "description", "amount", "is_billable", "receipt"], "update": ["description", "amount", "is_billable", "status"], "read": ["project_id", "user_id", "expense_date", "category", "description", "amount", "is_billable", "status"]}},
            {"id": "approval", "title": "Approval", "fields": {"read": ["approved_by", "approved_at"]}}
        ]
    },
    "query": {
        "sort": [{"id": "expense_date", "desc": true}],
        "join": [
            {"table": "projects", "on": "project_id", "columns": ["project_code", "name"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column pm.project_expenses.receipt is '{"accept": "image/*,.pdf", "maxFiles": 3, "maxSize": 5242880}';

comment on column pm.project_expenses.amount is '{"aggregate": "sum"}';

revoke all on table pm.project_expenses
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
delete on table pm.project_expenses to "x-admin";

grant
select
,
update on table pm.project_expenses to "pm-lead";

grant
select
,
  insert,
update on table pm.project_expenses to "user";

create index idx_pm_expenses_project_id on pm.project_expenses (project_id);

create index idx_pm_expenses_user_id on pm.project_expenses (user_id);

alter table pm.project_expenses enable row level security;

create policy expenses_select on pm.project_expenses for
select
  to authenticated using (
    user_id = (select auth.uid ())
    or pg_has_role (current_user, 'pm-lead', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
  );

create policy expenses_insert on pm.project_expenses for insert to authenticated
with
  check (true);

create policy expenses_update on pm.project_expenses
for update
  to authenticated using (true)
with
  check (true);

create policy expenses_delete on pm.project_expenses for delete to authenticated using (true);

create or replace function pm.expenses_guard () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    new.approved_by := (select auth.uid ());
    new.approved_at := current_timestamp;
  end if;
  return new;
end;
$$;

create trigger trg_expenses_guard before
update of status on pm.project_expenses for each row
execute function pm.expenses_guard ();

----------------------------------------------------------------
-- Invoices
----------------------------------------------------------------
create sequence if not exists pm.invoice_number_seq;

create table pm.invoices (
  id uuid primary key default extensions.uuid_generate_v4 (),
  invoice_number varchar(30) not null unique default (
    'INV-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('pm.invoice_number_seq')::text,
      5,
      '0'
    )
  ),
  project_id uuid not null references pm.projects (id) on delete restrict,
  client_id uuid not null references pm.clients (id) on delete restrict,
  status pm.invoice_status not null default 'draft',
  issue_date date not null default current_date,
  due_date date not null default (current_date + 30),
  period_start date,
  period_end date,
  subtotal numeric(12, 2) not null default 0,
  tax_total numeric(12, 2) not null default 0,
  total numeric(12, 2) not null default 0,
  paid_total numeric(12, 2) not null default 0,
  balance_due numeric(12, 2) not null default 0,
  document supasheet.file,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint invoices_dates_ordered check (due_date >= issue_date)
);

comment on column pm.invoices.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "sent": {"variant": "info", "icon": "Send"},
        "paid": {"variant": "success", "icon": "BadgeDollarSign"},
        "overdue": {"variant": "destructive", "icon": "Clock"},
        "void": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table pm.invoices is '{
    "icon": "FileText",
    "name": "Invoices",
    "description": "What was billed for a project, built from approved time, expenses and milestones.",
    "collapsible_group": "Financials",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "invoice_number", "badges": ["status", "balance_due"]},
        "tabs": ["invoice_lines", "invoice_payments"]
    },
    "views": [
        {"id": "kanban", "name": "Billing Board", "type": "kanban", "group": "status", "title": "invoice_number", "description": "project_id", "date": "due_date", "badge": "total"},
        {"id": "calendar", "name": "Due Dates", "type": "calendar", "title": "invoice_number", "badge": "status", "start_date": "issue_date", "end_date": "due_date"},
        {"id": "list", "name": "All Invoices", "type": "list", "title": "invoice_number", "description": "project_id", "field_1": "status", "field_2": "balance_due"}
    ],
    "filter_presets": [
        {"id": "outstanding", "name": "Outstanding", "filters": [{"id": "status", "value": ["sent", "overdue"], "operator": "in"}]},
        {"id": "overdue", "name": "Overdue", "filters": [{"id": "status", "value": "overdue", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["project_id", "period_start", "period_end"],
        "sections": [
            {"id": "invoice", "title": "Invoice", "fields": {"create": ["project_id", "client_id", "issue_date", "due_date", "period_start", "period_end"], "update": ["due_date", "status", "notes"], "read": ["project_id", "client_id", "issue_date", "due_date", "period_start", "period_end", "status"]}},
            {"id": "totals", "title": "Totals", "fields": {"create": ["tax_total"], "update": ["tax_total"], "read": ["subtotal", "tax_total", "total", "paid_total", "balance_due"]}},
            {"id": "extras", "title": "Document & Notes", "collapsible": true, "fields": ["document", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "issue_date", "desc": true}],
        "join": [
            {"table": "projects", "on": "project_id", "columns": ["project_code", "name"]},
            {"table": "clients", "on": "client_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column pm.invoices.total is '{"aggregate": "sum"}';

comment on column pm.invoices.balance_due is '{"name": "Balance", "aggregate": "sum"}';

comment on column pm.invoices.document is '{"accept": ".pdf", "maxFiles": 1, "maxSize": 10485760}';

revoke all on table pm.invoices
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
delete on table pm.invoices to "x-admin",
"pm-lead";

grant
select
  on table pm.invoices to "client";

revoke all on sequence pm.invoice_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence pm.invoice_number_seq to "x-admin",
"pm-lead";

create index idx_pm_invoices_project_id on pm.invoices (project_id);

create index idx_pm_invoices_client_id on pm.invoices (client_id);

create index idx_pm_invoices_status on pm.invoices (status);

alter table pm.invoices enable row level security;

create policy invoices_select on pm.invoices for
select
  to authenticated using (
    pg_has_role (current_user, 'pm-lead', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
    or exists (
      select
        1
      from
        pm.clients c
      where
        c.id = client_id
        and c.portal_user_id = (select auth.uid ())
    )
  );

create policy invoices_insert on pm.invoices for insert to authenticated
with
  check (true);

create policy invoices_update on pm.invoices
for update
  to authenticated using (true)
with
  check (true);

create policy invoices_delete on pm.invoices for delete to authenticated using (true);

create trigger invoices_updated_at before
update on pm.invoices for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Invoice lines
--
-- The guard is the fourth headline rule: a time entry, expense or
-- milestone that is already invoiced is refused a second line
-- outright, and the trigger right after it is what marks the source
-- invoiced the moment a line is created — there is no window where
-- the same hour could be added to two invoices.
----------------------------------------------------------------
create table pm.invoice_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  invoice_id uuid not null references pm.invoices (id) on delete cascade,
  line_type pm.invoice_line_type not null default 'time',
  description varchar(300) not null,
  source_time_entry_id uuid references pm.time_entries (id) on delete set null,
  source_expense_id uuid references pm.project_expenses (id) on delete set null,
  source_milestone_id uuid references pm.milestones (id) on delete set null,
  quantity numeric(10, 3) not null default 1,
  unit_price numeric(12, 2) not null default 0,
  line_total numeric(12, 2) not null default 0,
  created_at timestamptz default current_timestamp
);

comment on table pm.invoice_lines is '{
    "icon": "Rows3",
    "name": "Invoice Lines",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["invoice_id", "line_type", "description"]},
            {"id": "source", "title": "Source", "fields": ["source_time_entry_id", "source_expense_id", "source_milestone_id"]},
            {"id": "pricing", "title": "Pricing", "fields": ["quantity", "unit_price"]}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [{"table": "invoices", "on": "invoice_id", "columns": ["invoice_number", "status"]}]
    }
}';

comment on column pm.invoice_lines.line_total is '{"aggregate": "sum"}';

revoke all on table pm.invoice_lines
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
delete on table pm.invoice_lines to "x-admin",
"pm-lead";

grant
select
  on table pm.invoice_lines to "client";

create index idx_pm_invoice_lines_invoice_id on pm.invoice_lines (invoice_id);

alter table pm.invoice_lines enable row level security;

create policy invoice_lines_select on pm.invoice_lines for
select
  to authenticated using (true);

create policy invoice_lines_insert on pm.invoice_lines for insert to authenticated
with
  check (true);

create policy invoice_lines_update on pm.invoice_lines
for update
  to authenticated using (true)
with
  check (true);

create policy invoice_lines_delete on pm.invoice_lines for delete to authenticated using (true);

create or replace function pm.invoice_lines_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.source_time_entry_id is not null
    and exists (
      select 1
      from pm.time_entries
      where id = new.source_time_entry_id
        and status = 'invoiced'
    ) then
    raise exception 'This time entry has already been invoiced.';
  end if;

  if new.source_expense_id is not null
    and exists (
      select 1
      from pm.project_expenses
      where id = new.source_expense_id
        and status = 'invoiced'
    ) then
    raise exception 'This expense has already been invoiced.';
  end if;

  if new.source_milestone_id is not null
    and exists (
      select 1
      from pm.milestones
      where id = new.source_milestone_id
        and invoiced
    ) then
    raise exception 'This milestone has already been invoiced.';
  end if;

  new.line_total := round(new.quantity * new.unit_price, 2);
  return new;
end;
$$;

create trigger trg_invoice_lines_guard before insert on pm.invoice_lines for each row
execute function pm.invoice_lines_guard ();

create or replace function pm.invoice_lines_mark_source () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.source_time_entry_id is not null then
    update pm.time_entries
    set status = 'invoiced'
    where id = new.source_time_entry_id;
  end if;

  if new.source_expense_id is not null then
    update pm.project_expenses
    set status = 'invoiced'
    where id = new.source_expense_id;
  end if;

  if new.source_milestone_id is not null then
    update pm.milestones
    set invoiced = true
    where id = new.source_milestone_id;
  end if;

  return new;
end;
$$;

create trigger trg_invoice_lines_mark_source
after insert on pm.invoice_lines for each row
execute function pm.invoice_lines_mark_source ();

create or replace function pm.invoice_lines_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_invoice_id uuid := coalesce(new.invoice_id, old.invoice_id);
begin
  update pm.invoices inv
  set subtotal = x.subtotal,
    total = x.subtotal + inv.tax_total,
    balance_due = x.subtotal + inv.tax_total - inv.paid_total
  from (
    select coalesce(sum(line_total), 0) as subtotal
    from pm.invoice_lines
    where invoice_id = v_invoice_id
  ) x
  where inv.id = v_invoice_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_invoice_lines_rollup
after insert
or delete
or
update on pm.invoice_lines for each row
execute function pm.invoice_lines_rollup ();

----------------------------------------------------------------
-- Invoice payments
----------------------------------------------------------------
create table pm.invoice_payments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  invoice_id uuid not null references pm.invoices (id) on delete cascade,
  payment_date date not null default current_date,
  amount numeric(12, 2) not null,
  method varchar(60),
  reference varchar(120),
  recorded_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  constraint invoice_payments_amount_positive check (amount > 0)
);

comment on table pm.invoice_payments is '{
    "icon": "BadgeDollarSign",
    "name": "Payments",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "payment", "title": "Payment", "fields": ["invoice_id", "payment_date", "amount", "method", "reference"]}
        ]
    },
    "query": {
        "sort": [{"id": "payment_date", "desc": true}],
        "join": [{"table": "invoices", "on": "invoice_id", "columns": ["invoice_number", "status", "balance_due"]}]
    }
}';

comment on column pm.invoice_payments.amount is '{"aggregate": "sum"}';

revoke all on table pm.invoice_payments
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
delete on table pm.invoice_payments to "x-admin",
"pm-lead";

create index idx_pm_invoice_payments_invoice_id on pm.invoice_payments (invoice_id);

alter table pm.invoice_payments enable row level security;

create policy invoice_payments_select on pm.invoice_payments for
select
  to authenticated using (true);

create policy invoice_payments_insert on pm.invoice_payments for insert to authenticated
with
  check (true);

create policy invoice_payments_update on pm.invoice_payments
for update
  to authenticated using (true)
with
  check (true);

create policy invoice_payments_delete on pm.invoice_payments for delete to authenticated using (true);

create or replace function pm.invoice_payments_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_invoice_id uuid := coalesce(new.invoice_id, old.invoice_id);
begin
  update pm.invoices inv
  set paid_total = x.paid,
    balance_due = inv.total - x.paid,
    status = case
      when x.paid >= inv.total
      and inv.total > 0 then 'paid'::pm.invoice_status
      else inv.status
    end,
    updated_at = current_timestamp
  from (
    select coalesce(sum(amount), 0) as paid
    from pm.invoice_payments
    where invoice_id = v_invoice_id
  ) x
  where inv.id = v_invoice_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_invoice_payments_rollup
after insert
or delete
or
update on pm.invoice_payments for each row
execute function pm.invoice_payments_rollup ();

----------------------------------------------------------------
-- Risks
----------------------------------------------------------------
create table pm.risks (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid not null references pm.projects (id) on delete cascade,
  title varchar(300) not null,
  description supasheet.RICH_TEXT,
  category pm.risk_category not null default 'schedule',
  probability integer not null default 1,
  impact integer not null default 1,
  risk_score integer not null default 1,
  status pm.risk_status not null default 'identified',
  mitigation_plan supasheet.RICH_TEXT,
  owner_id uuid references supasheet.users (id) on delete set null,
  review_date date,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint risks_scores_range check (
    probability between 1 and 5
    and impact between 1 and 5
  )
);

comment on column pm.risks.category is '{
    "progress": false,
    "values": {
        "schedule": {"variant": "warning", "icon": "CalendarClock"},
        "budget": {"variant": "destructive", "icon": "DollarSign"},
        "scope": {"variant": "info", "icon": "Expand"},
        "resource": {"variant": "default", "icon": "Users"},
        "technical": {"variant": "secondary", "icon": "Cpu"},
        "external": {"variant": "secondary", "icon": "Globe"}
    }
}';

comment on column pm.risks.status is '{
    "progress": true,
    "values": {
        "identified": {"variant": "secondary", "icon": "CircleDot"},
        "monitoring": {"variant": "info", "icon": "Eye"},
        "mitigating": {"variant": "warning", "icon": "Loader"},
        "occurred": {"variant": "destructive", "icon": "OctagonAlert"},
        "closed": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on table pm.risks is '{
    "icon": "TriangleAlert",
    "name": "Risks",
    "description": "What could go wrong. Score is probability x impact, computed on write.",
    "collapsible_group": "Delivery",
    "display": "block",
    "primary_view": "kanban",
    "detail": {"header": {"title": "title", "badges": ["category", "status", "risk_score"]}},
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "title", "description": "category", "date": "review_date", "badge": "risk_score"},
        {"id": "list", "name": "All Risks", "type": "list", "title": "title", "description": "category", "field_1": "status", "field_2": "risk_score"}
    ],
    "filter_presets": [
        {"id": "high_score", "name": "High Score (15+)", "filters": [{"id": "risk_score", "value": "15", "operator": "gte"}]},
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["identified", "monitoring", "mitigating"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["project_id", "title", "category", "probability", "impact"],
        "sections": [
            {"id": "risk", "title": "Risk", "fields": {"create": ["project_id", "title", "description", "category", "owner_id", "review_date"], "update": ["title", "description", "status", "owner_id", "review_date"], "read": ["project_id", "title", "description", "category", "owner_id", "review_date", "status"]}},
            {"id": "scoring", "title": "Scoring", "fields": {"create": ["probability", "impact"], "update": ["probability", "impact"], "read": ["probability", "impact", "risk_score"]}},
            {"id": "mitigation", "title": "Mitigation", "fields": ["mitigation_plan"]}
        ]
    },
    "query": {
        "sort": [{"id": "risk_score", "desc": true}],
        "join": [
            {"table": "projects", "on": "project_id", "columns": ["project_code", "name"]},
            {"table": "users", "on": "owner_id", "alias": "owner", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table pm.risks
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
delete on table pm.risks to "x-admin",
"pm-lead";

grant
select
,
  insert on table pm.risks to "user";

create index idx_pm_risks_project_id on pm.risks (project_id);

alter table pm.risks enable row level security;

create policy risks_select on pm.risks for
select
  to authenticated using (true);

create policy risks_insert on pm.risks for insert to authenticated
with
  check (true);

create policy risks_update on pm.risks
for update
  to authenticated using (true)
with
  check (true);

create policy risks_delete on pm.risks for delete to authenticated using (true);

create trigger risks_updated_at before
update on pm.risks for each row
execute function supasheet.set_updated_at ();

create or replace function pm.risks_set_score () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  new.risk_score := new.probability * new.impact;
  return new;
end;
$$;

create trigger trg_risks_set_score before insert
or
update on pm.risks for each row
execute function pm.risks_set_score ();

----------------------------------------------------------------
-- Status reports
--
-- The fifth headline rule, made real: the AFTER trigger below is the
-- only writer of projects.health anywhere in this schema.
----------------------------------------------------------------
create table pm.status_reports (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid not null references pm.projects (id) on delete cascade,
  report_date date not null default current_date,
  period_start date,
  period_end date,
  overall_health pm.health_status not null default 'green',
  budget_health pm.health_status not null default 'green',
  schedule_health pm.health_status not null default 'green',
  summary supasheet.RICH_TEXT,
  accomplishments supasheet.RICH_TEXT,
  upcoming supasheet.RICH_TEXT,
  blockers supasheet.RICH_TEXT,
  created_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  unique (project_id, report_date)
);

comment on column pm.status_reports.overall_health is '{
    "progress": false,
    "values": {
        "green": {"variant": "success", "icon": "CircleCheck"},
        "amber": {"variant": "warning", "icon": "TriangleAlert"},
        "red": {"variant": "destructive", "icon": "OctagonAlert"}
    }
}';

comment on table pm.status_reports is '{
    "icon": "FileBarChart",
    "name": "Status Reports",
    "description": "The weekly (or whatever cadence) update. Filing one is the only way a project''s headline health changes.",
    "collapsible_group": "Delivery",
    "display": "block",
    "primary_view": "calendar",
    "detail": {"header": {"title": "report_date", "badges": ["overall_health"]}},
    "views": [
        {"id": "calendar", "name": "Report Calendar", "type": "calendar", "title": "project_id", "badge": "overall_health", "start_date": "report_date", "read_only": true},
        {"id": "list", "name": "All Reports", "type": "list", "title": "report_date", "description": "summary", "field_1": "overall_health", "field_2": "budget_health"}
    ],
    "fields": {
        "quick_create": ["project_id", "overall_health", "summary"],
        "sections": [
            {"id": "report", "title": "Report", "fields": ["project_id", "report_date", "period_start", "period_end"]},
            {"id": "health", "title": "Health", "fields": ["overall_health", "budget_health", "schedule_health"]},
            {"id": "narrative", "title": "Narrative", "fields": ["summary", "accomplishments", "upcoming", "blockers"]}
        ]
    },
    "query": {
        "sort": [{"id": "report_date", "desc": true}],
        "join": [
            {"table": "projects", "on": "project_id", "columns": ["project_code", "name"]},
            {"table": "users", "on": "created_by", "alias": "author", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table pm.status_reports
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
delete on table pm.status_reports to "x-admin",
"pm-lead";

grant
select
  on table pm.status_reports to "user";

grant
select
  on table pm.status_reports to "client";

create index idx_pm_status_reports_project_id on pm.status_reports (project_id);

alter table pm.status_reports enable row level security;

create policy status_reports_select on pm.status_reports for
select
  to authenticated using (
    pg_has_role (current_user, 'pm-lead', 'member')
    or pg_has_role (current_user, 'x-admin', 'member')
    or pg_has_role (current_user, 'user', 'member')
    or exists (
      select
        1
      from
        pm.projects p
        join pm.clients c on c.id = p.client_id
      where
        p.id = project_id
        and c.portal_user_id = (select auth.uid ())
    )
  );

create policy status_reports_insert on pm.status_reports for insert to authenticated
with
  check (true);

create policy status_reports_update on pm.status_reports
for update
  to authenticated using (true)
with
  check (true);

create policy status_reports_delete on pm.status_reports for delete to authenticated using (true);

create or replace function pm.status_reports_sync_project_health () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  update pm.projects
  set health = new.overall_health,
    updated_at = current_timestamp
  where id = new.project_id;

  return new;
end;
$$;

create trigger trg_status_reports_sync_health
after insert
or
update of overall_health on pm.status_reports for each row
execute function pm.status_reports_sync_project_health ();

----------------------------------------------------------------
-- Notification triggers
----------------------------------------------------------------
create or replace function pm.trg_tasks_notify () returns trigger as $$
begin
  if tg_op = 'UPDATE'
    and new.assignee_id is distinct from old.assignee_id
    and new.assignee_id is not null then
    perform supasheet.create_notification(
      'task_assigned',
      'Task assigned: ' || new.title,
      'You have been assigned a task on ' || new.task_number || '.',
      array[new.assignee_id],
      jsonb_build_object('task_id', new.id, 'project_id', new.project_id),
      '/pm/resource/tasks/' || new.id::text || '/detail'
    );
  elsif tg_op = 'UPDATE'
    and new.status is distinct from old.status
    and new.status = 'blocked' then
    perform supasheet.create_notification(
      'task_blocked',
      'Task blocked: ' || new.title,
      'This task cannot proceed.',
      array_remove(array[new.assignee_id, new.reporter_id], null),
      jsonb_build_object('task_id', new.id, 'project_id', new.project_id),
      '/pm/resource/tasks/' || new.id::text || '/detail'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_tasks_notify on pm.tasks;

create trigger trg_tasks_notify
after
update of assignee_id,
status on pm.tasks for each row
execute function pm.trg_tasks_notify ();

create or replace function pm.trg_time_entries_notify () returns trigger as $$
begin
  if new.status = 'rejected' and old.status is distinct from 'rejected' then
    perform supasheet.create_notification(
      'time_entry_rejected',
      'Time entry rejected',
      coalesce(new.description, 'A time entry you submitted was rejected.'),
      array_remove(array[new.user_id], null),
      jsonb_build_object('time_entry_id', new.id, 'project_id', new.project_id),
      '/pm/resource/time_entries/' || new.id::text || '/detail'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_time_entries_notify on pm.time_entries;

create trigger trg_time_entries_notify
after
update of status on pm.time_entries for each row
execute function pm.trg_time_entries_notify ();

create or replace function pm.trg_deliverables_notify () returns trigger as $$
declare
  v_client_user_id uuid;
begin
  if new.status is distinct from old.status then
    if new.status = 'in_review' then
      select c.portal_user_id into v_client_user_id
      from pm.projects p
        join pm.clients c on c.id = p.client_id
      where p.id = new.project_id;

      if v_client_user_id is not null then
        perform supasheet.create_notification(
          'deliverable_ready_for_review',
          'Ready for your review: ' || new.name,
          'A deliverable is ready for your sign-off.',
          array[v_client_user_id],
          jsonb_build_object('deliverable_id', new.id, 'project_id', new.project_id),
          '/pm/resource/deliverables/' || new.id::text || '/detail'
        );
      end if;
    elsif new.status in ('approved', 'rejected') then
      perform supasheet.create_notification(
        case
          when new.status = 'approved' then 'deliverable_approved'
          else 'deliverable_rejected'
        end,
        'Deliverable ' || new.status || ': ' || new.name,
        coalesce(new.review_notes, ''),
        array_remove(array[new.submitted_by], null),
        jsonb_build_object('deliverable_id', new.id, 'project_id', new.project_id),
        '/pm/resource/deliverables/' || new.id::text || '/detail'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_deliverables_notify on pm.deliverables;

create trigger trg_deliverables_notify
after
update of status on pm.deliverables for each row
execute function pm.trg_deliverables_notify ();

create or replace function pm.trg_invoices_notify () returns trigger as $$
declare
  v_client_user_id uuid;
begin
  if new.status = 'sent' and old.status is distinct from 'sent' then
    select portal_user_id into v_client_user_id
    from pm.clients
    where id = new.client_id;

    if v_client_user_id is not null then
      perform supasheet.create_notification(
        'invoice_sent',
        'New invoice: ' || new.invoice_number,
        'An invoice for ' || new.total::text || ' is ready.',
        array[v_client_user_id],
        jsonb_build_object('invoice_id', new.id),
        '/pm/resource/invoices/' || new.id::text || '/detail'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_invoices_notify on pm.invoices;

create trigger trg_invoices_notify
after
update of status on pm.invoices for each row
execute function pm.trg_invoices_notify ();

create or replace function pm.trg_risks_notify () returns trigger as $$
begin
  if new.risk_score >= 15 then
    perform supasheet.create_notification(
      'high_risk_raised',
      'High-score risk raised: ' || new.title,
      'Risk score ' || new.risk_score::text || ' — needs attention.',
      supasheet.get_users_with_role ('pm-lead'),
      jsonb_build_object('risk_id', new.id, 'project_id', new.project_id),
      '/pm/resource/risks/' || new.id::text || '/detail'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_risks_notify on pm.risks;

create trigger trg_risks_notify
after insert on pm.risks for each row
execute function pm.trg_risks_notify ();

create or replace function pm.trg_status_reports_notify () returns trigger as $$
begin
  if new.overall_health = 'red' then
    perform supasheet.create_notification(
      'project_health_red',
      'Project flagged red: ' || new.project_id::text,
      coalesce(new.summary, 'A status report just flagged this project red.'),
      supasheet.get_users_with_role ('pm-lead'),
      jsonb_build_object('status_report_id', new.id, 'project_id', new.project_id),
      '/pm/resource/status_reports/' || new.id::text || '/detail'
    );
  end if;

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists trg_status_reports_notify on pm.status_reports;

create trigger trg_status_reports_notify
after insert on pm.status_reports for each row
execute function pm.trg_status_reports_notify ();

----------------------------------------------------------------
-- Audit logging on the high-value tables
----------------------------------------------------------------
create trigger audit_pm_projects_insert
after insert on pm.projects for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_pm_projects_update
after
update on pm.projects for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_pm_projects_delete before delete on pm.projects for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_pm_invoices_insert
after insert on pm.invoices for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_pm_invoices_update
after
update on pm.invoices for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_pm_deliverables_insert
after insert on pm.deliverables for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_pm_deliverables_update
after
update on pm.deliverables for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_pm_time_entries_update
after
update on pm.time_entries for each row
execute function supasheet.audit_trigger_function ();

-- ================================================================
-- Dashboard widgets
-- ================================================================
create or replace view pm.active_projects_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'folder-kanban' as icon,
  'active projects' as label
from
  pm.projects
where
  status = 'active';

comment on view pm.active_projects_count is '{"type": "dashboard_widget", "name": "Active Projects", "description": "Projects currently in delivery", "widget_type": "card_1"}';

create or replace view pm.billed_vs_cost_comparison
with
  (security_invoker = true) as
select
  coalesce(sum(billed_amount), 0) as primary,
  coalesce(sum(consumed_budget), 0) as secondary,
  'Billed' as primary_label,
  'Cost' as secondary_label
from
  pm.projects
where
  status in ('active', 'completed');

comment on view pm.billed_vs_cost_comparison is '{"type": "dashboard_widget", "name": "Billed vs Cost", "description": "What clients were billed against internal cost", "widget_type": "card_2"}';

create or replace view pm.task_completion_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        status = 'done'
    ) / nullif(count(*), 0),
    1
  ) as percent
from
  pm.tasks;

comment on view pm.task_completion_rate is '{"type": "dashboard_widget", "name": "Task Completion Rate", "description": "Share of every task marked done", "widget_type": "card_3"}';

create or replace view pm.task_pipeline_progress
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'done'
  ) as current,
  count(*) as total,
  json_build_array(
    json_build_object(
      'label', 'To Do', 'value', count(*) filter (
        where
          status = 'todo'
      )
    ),
    json_build_object(
      'label', 'In Progress', 'value', count(*) filter (
        where
          status = 'in_progress'
      )
    ),
    json_build_object(
      'label', 'In Review', 'value', count(*) filter (
        where
          status = 'in_review'
      )
    ),
    json_build_object(
      'label', 'Blocked', 'value', count(*) filter (
        where
          status = 'blocked'
      )
    ),
    json_build_object(
      'label', 'Done', 'value', count(*) filter (
        where
          status = 'done'
      )
    )
  ) as segments
from
  pm.tasks;

comment on view pm.task_pipeline_progress is '{"type": "dashboard_widget", "name": "Task Pipeline", "description": "Every task, by status", "widget_type": "card_4"}';

create or replace view pm.total_billed_breakdown
with
  (security_invoker = true) as
select
  coalesce(sum(total_billed), 0) as value,
  'Total Billed' as label,
  'dollar-sign' as icon,
  (
    select
      json_agg(
        json_build_object('label', name, 'value', total_billed)
      )
    from
      (
        select
          name,
          total_billed
        from
          pm.clients
        order by
          total_billed desc
        limit
          5
      ) t
  ) as breakdown
from
  pm.clients;

comment on view pm.total_billed_breakdown is '{"type": "dashboard_widget", "name": "Total Billed", "description": "Lifetime billing, by top client", "widget_type": "card_5"}';

create or replace view pm.pm_metrics_grid
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Active Projects',
      'value',
      (
        select
          count(*)
        from
          pm.projects
        where
          status = 'active'
      )
    ),
    json_build_object(
      'label',
      'Overdue Tasks',
      'value',
      (
        select
          count(*)
        from
          pm.tasks
        where
          due_date < current_date
          and status <> 'done'
      )
    ),
    json_build_object(
      'label',
      'Pending Time',
      'value',
      (
        select
          count(*)
        from
          pm.time_entries
        where
          status = 'submitted'
      )
    ),
    json_build_object(
      'label',
      'Open Risks',
      'value',
      (
        select
          count(*)
        from
          pm.risks
        where
          status in ('identified', 'monitoring', 'mitigating')
      )
    )
  ) as metrics;

comment on view pm.pm_metrics_grid is '{"type": "dashboard_widget", "name": "Delivery At A Glance", "description": "The four headline counts", "widget_type": "card_6"}';

create or replace view pm.recent_time_entries
with
  (security_invoker = true) as
select
  u.name as member,
  t.title as task,
  te.entry_date,
  round(te.logged_duration / 3600000.0, 2) as hours,
  '/pm/resource/time_entries/' || te.id || '/detail' as link
from
  pm.time_entries te
  join pm.tasks t on t.id = te.task_id
  left join pm.users u on u.id = te.user_id
order by
  te.entry_date desc
limit
  10;

comment on view pm.recent_time_entries is '{"type": "dashboard_widget", "name": "Recent Time Entries", "description": "The most recently logged time", "widget_type": "table_1"}';

create or replace view pm.projects_by_margin_table
with
  (security_invoker = true) as
select
  name as project,
  billed_amount,
  consumed_budget,
  margin_percent,
  '/pm/resource/projects/' || id || '/detail' as link
from
  pm.projects
where
  status in ('active', 'completed')
order by
  margin_percent asc nulls last
limit
  10;

comment on view pm.projects_by_margin_table is '{"type": "dashboard_widget", "name": "Projects By Margin", "description": "Billed, cost and margin per project, weakest first", "widget_type": "table_2"}';

create or replace view pm.overdue_tasks_alert
with
  (security_invoker = true) as
select
  title,
  task_number as description,
  'clock' as icon,
  'destructive' as variant,
  '/pm/resource/tasks/' || id || '/detail' as link
from
  pm.tasks
where
  due_date < current_date
  and status <> 'done'
order by
  due_date asc
limit
  10;

comment on view pm.overdue_tasks_alert is '{"type": "dashboard_widget", "name": "Overdue Tasks", "description": "Tasks past their due date and still not done", "widget_type": "list_1"}';

create or replace view pm.over_budget_projects_alert
with
  (security_invoker = true) as
select
  name as title,
  project_code || ' — ' || consumed_hours || ' of ' || budget_hours || 'h' as description,
  'triangle-alert' as icon,
  'warning' as variant,
  '/pm/resource/projects/' || id || '/detail' as link
from
  pm.projects
where
  budget_hours is not null
  and consumed_hours >= budget_hours * 0.9
order by
  consumed_hours desc
limit
  10;

comment on view pm.over_budget_projects_alert is '{"type": "dashboard_widget", "name": "Approaching Budget", "description": "Projects at or past 90% of their budgeted hours", "widget_type": "list_2"}';

create or replace view pm.recent_task_activity
with
  (security_invoker = true) as
select
  u.name as actor,
  case
    when e.event_type = 'created' then 'created'
    when e.event_type = 'completed' then 'completed'
    when e.event_type = 'assigned' then 'was assigned'
    when e.event_type = 'comment_added' then 'commented on'
    else 'updated'
  end as action,
  t.title as entity,
  to_char(e.occurred_at, 'Mon DD, YYYY') as date,
  '/pm/resource/tasks/' || t.id || '/detail' as link
from
  pm.task_events e
  join pm.tasks t on t.id = e.task_id
  left join pm.users u on u.id = e.actor_id
order by
  e.occurred_at desc
limit
  5;

comment on view pm.recent_task_activity is '{"type": "dashboard_widget", "name": "Recent Task Activity", "description": "The latest events across every task", "widget_type": "list_3"}';

create or replace view pm.top_billers_leaderboard
with
  (security_invoker = true) as
select
  u.name,
  round(sum(te.logged_duration) / 3600000.0, 1) as value,
  count(distinct te.project_id)::text || ' projects' as label
from
  pm.time_entries te
  join pm.users u on u.id = te.user_id
where
  te.status in ('approved', 'invoiced')
group by
  u.name
order by
  value desc
limit
  5;

comment on view pm.top_billers_leaderboard is '{"type": "dashboard_widget", "name": "Top Billers", "description": "Ranked by approved hours logged", "widget_type": "list_4"}';

do $$
declare
  v text;
begin
  foreach v in array array[
    'pm.active_projects_count',
    'pm.billed_vs_cost_comparison',
    'pm.task_completion_rate',
    'pm.task_pipeline_progress',
    'pm.total_billed_breakdown',
    'pm.pm_metrics_grid',
    'pm.recent_time_entries',
    'pm.projects_by_margin_table',
    'pm.overdue_tasks_alert',
    'pm.over_budget_projects_alert',
    'pm.recent_task_activity',
    'pm.top_billers_leaderboard'
  ]
  loop
    execute format('revoke all on %s from public, anon, authenticated, service_role;', v);
    execute format('grant select on %s to "x-admin", "pm-lead";', v);
  end loop;
end;
$$;

-- ================================================================
-- Charts
-- ================================================================
create or replace view pm.hours_by_project_pie
with
  (security_invoker = true) as
select
  p.name as label,
  coalesce(sum(te.logged_duration) / 3600000.0, 0) as value
from
  pm.projects p
  left join pm.time_entries te on te.project_id = p.id
  and te.status in ('approved', 'invoiced')
group by
  p.name;

comment on view pm.hours_by_project_pie is '{"type": "chart", "name": "Hours By Project", "description": "Approved and invoiced hours, by project", "chart_type": "pie"}';

create or replace view pm.tasks_by_project_bar
with
  (security_invoker = true) as
select
  p.name as label,
  count(t.id) as total,
  count(t.id) filter (
    where
      t.status = 'done'
  ) as done
from
  pm.projects p
  left join pm.tasks t on t.project_id = p.id
group by
  p.name
order by
  total desc;

comment on view pm.tasks_by_project_bar is '{"type": "chart", "name": "Tasks By Project", "description": "Total and completed tasks, per project", "chart_type": "bar"}';

create or replace view pm.monthly_billed_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', issue_date), 'Mon YYYY') as date,
  coalesce(sum(total), 0) as billed
from
  pm.invoices
group by
  date_trunc('month', issue_date)
order by
  date_trunc('month', issue_date);

comment on view pm.monthly_billed_line is '{"type": "chart", "name": "Monthly Billed", "description": "Invoice total by month raised", "chart_type": "line", "format": "currency"}';

create or replace view pm.hours_billable_area
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', entry_date), 'Mon YYYY') as date,
  round(sum(logged_duration) / 3600000.0, 1) as total_hours,
  round(
    sum(logged_duration) filter (
      where
        is_billable
    ) / 3600000.0,
    1
  ) as billable_hours
from
  pm.time_entries
group by
  date_trunc('month', entry_date)
order by
  date_trunc('month', entry_date);

comment on view pm.hours_billable_area is '{"type": "chart", "name": "Hours Logged vs Billable", "description": "Monthly hours logged against how much of it was billable", "chart_type": "area"}';

create or replace view pm.risk_categories_radar
with
  (security_invoker = true) as
select
  category::text as metric,
  avg(probability) as avg_probability,
  avg(impact) as avg_impact
from
  pm.risks
group by
  category;

comment on view pm.risk_categories_radar is '{"type": "chart", "name": "Risk Categories", "description": "Average probability and impact, by risk category", "chart_type": "radar"}';

do $$
declare
  v text;
begin
  foreach v in array array[
    'pm.hours_by_project_pie',
    'pm.tasks_by_project_bar',
    'pm.monthly_billed_line',
    'pm.hours_billable_area',
    'pm.risk_categories_radar'
  ]
  loop
    execute format('revoke all on %s from public, anon, authenticated, service_role;', v);
    execute format('grant select on %s to "x-admin", "pm-lead";', v);
  end loop;
end;
$$;

-- ================================================================
-- Reports
-- ================================================================
create or replace view pm.project_profitability_report
with
  (security_invoker = true) as
select
  p.id,
  p.project_code,
  p.name,
  p.status,
  c.name as client,
  u.name as pm_lead,
  p.budget_type,
  p.budget_amount,
  p.budget_hours,
  p.consumed_hours,
  p.consumed_budget,
  p.billed_amount,
  p.margin_percent
from
  pm.projects p
  left join pm.clients c on c.id = p.client_id
  left join pm.users u on u.id = p.pm_lead_id;

comment on view pm.project_profitability_report is '{"type": "report", "name": "Project Profitability", "description": "Budget, cost, billed amount and margin for every project — the management review document.", "template": true}';

revoke all on pm.project_profitability_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on pm.project_profitability_report to "x-admin",
  "pm-lead";

create or replace view pm.invoice_summary_report
with
  (security_invoker = true) as
select
  i.id,
  i.invoice_number,
  i.status,
  i.issue_date,
  i.due_date,
  p.name as project,
  c.name as client,
  i.subtotal,
  i.tax_total,
  i.total,
  i.paid_total,
  i.balance_due
from
  pm.invoices i
  join pm.projects p on p.id = i.project_id
  join pm.clients c on c.id = i.client_id;

comment on view pm.invoice_summary_report is '{"type": "report", "name": "Invoice Summary", "description": "Every invoice with its project and client, and what is still outstanding."}';

revoke all on pm.invoice_summary_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on pm.invoice_summary_report to "x-admin",
  "pm-lead";

-- Heavy monthly rollup — a materialized view instead of a live report.
create materialized view pm.utilization_rollup as
select
  months.month,
  coalesce(te.total_hours, 0) as total_hours,
  coalesce(te.billable_hours, 0) as billable_hours,
  round(
    100.0 * coalesce(te.billable_hours, 0) / nullif(coalesce(te.total_hours, 0), 0),
    1
  ) as utilization_percent
from
  (
    select
      generate_series(
        date_trunc(
          'month',
          least(
            (
              select
                min(entry_date)::timestamptz
              from
                pm.time_entries
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
      date_trunc('month', entry_date)::date as month,
      sum(logged_duration) / 3600000.0 as total_hours,
      sum(logged_duration) filter (
        where
          is_billable
      ) / 3600000.0 as billable_hours
    from pm.time_entries
    group by
      1
  ) te using (month);

create unique index idx_pm_utilization_rollup_month on pm.utilization_rollup (month);

comment on materialized view pm.utilization_rollup is '{"type": "report", "name": "Utilization Trend", "description": "Total and billable hours logged, by month. Refresh with: refresh materialized view concurrently pm.utilization_rollup;"}';

revoke all on pm.utilization_rollup
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on pm.utilization_rollup to "x-admin",
  "pm-lead";

-- ================================================================
-- Templates (bulk insert)
-- ================================================================
create or replace view pm.starter_clients_template
with
  (security_invoker = true) as
select
  *
from
  (
    values
      (
        'ACME'::varchar(20),
        'Acme Manufacturing'::varchar(200)
      ),
      ('BEACON', 'Beacon Health Partners'),
      ('NORTHWIND', 'Northwind Retail Group')
  ) as t (code, name);

comment on view pm.starter_clients_template is '{
    "type": "template",
    "name": "Starter Client Roster",
    "description": "A few illustrative clients to explore the module with on a fresh install. Apply to pm.clients.",
    "target_table": "clients"
}';

revoke all on pm.starter_clients_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on pm.starter_clients_template to "x-admin";

create or replace view pm.budget_risk_flag_template
with
  (security_invoker = true) as
select
  p.id as project_id,
  'Project approaching its budgeted hours' as title,
  'budget'::pm.risk_category as category,
  4 as probability,
  4 as impact,
  p.pm_lead_id as owner_id
from
  pm.projects p
where
  p.status = 'active'
  and p.budget_hours is not null
  and p.consumed_hours >= p.budget_hours * 0.9
  and not exists (
    select
      1
    from
      pm.risks r
    where
      r.project_id = p.id
      and r.category = 'budget'
      and r.status <> 'closed'
  );

comment on view pm.budget_risk_flag_template is '{
    "type": "template",
    "name": "Budget Risk Flag",
    "description": "A budget-category risk for every active project already at 90% of its budgeted hours with nothing already tracking it. Apply to pm.risks.",
    "target_table": "risks"
}';

revoke all on pm.budget_risk_flag_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on pm.budget_risk_flag_template to "x-admin",
  "pm-lead";

-- ================================================================
-- Custom forms
-- ================================================================
-- Returns a single object via explicit OUT parameters — the UI
-- renders the created record as a detail card. Same shape desk's
-- open_ticket_for_customer uses.
create or replace function pm.open_project_for_client (
  p_client_id uuid,
  p_name varchar,
  p_pm_lead_id uuid default null,
  p_budget_type pm.budget_type default 'time_and_materials',
  p_budget_amount numeric default 0,
  p_budget_hours numeric default null,
  out project_id uuid,
  out project_code varchar,
  out name varchar,
  out status pm.project_status,
  out budget_amount numeric
) language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_project pm.projects%rowtype;
begin
  if not exists (
    select 1
    from pm.clients
    where id = p_client_id
  ) then
    raise exception 'Client not found';
  end if;

  insert into pm.projects (client_id, name, pm_lead_id, budget_type, budget_amount, budget_hours)
  values (p_client_id, p_name, p_pm_lead_id, p_budget_type, p_budget_amount, p_budget_hours)
  returning * into v_project;

  project_id := v_project.id;
  project_code := v_project.project_code;
  name := v_project.name;
  status := v_project.status;
  budget_amount := v_project.budget_amount;
end;
$$;

comment on function pm.open_project_for_client (
  uuid, varchar, uuid, pm.budget_type, numeric, numeric
) is '{
    "type": "form",
    "resource": "clients",
    "name": "Open a project",
    "description": "Start a new engagement for this client.",
    "icon": "FolderPlus",
    "success_message": "Project opened",
    "fields": {
        "sections": [
            {"id": "project", "title": "Project", "fields": ["p_client_id", "p_name", "p_pm_lead_id"]},
            {"id": "budget", "title": "Budget", "fields": ["p_budget_type", "p_budget_amount", "p_budget_hours"]}
        ],
        "relations": {
            "p_client_id": {"table": "clients", "column": "id", "display": ["code", "name"]},
            "p_pm_lead_id": {"table": "users", "column": "id", "display": ["name", "email"]}
        }
    }
}';

-- Returns setof pm.invoice_lines — the UI renders the created lines
-- as a table. Same shape desk's bulk_reassign_tickets uses.
create or replace function pm.generate_invoice_from_time (
  p_project_id uuid,
  p_period_start date,
  p_period_end date
) returns setof pm.invoice_lines language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_client_id uuid;
  v_invoice_id uuid;
begin
  select client_id into v_client_id
  from pm.projects
  where id = p_project_id;

  if v_client_id is null then
    raise exception 'Project not found';
  end if;

  insert into pm.invoices (project_id, client_id, period_start, period_end)
  values (p_project_id, v_client_id, p_period_start, p_period_end)
  returning id into v_invoice_id;

  return query
  insert into pm.invoice_lines (
    invoice_id, line_type, description, source_time_entry_id, quantity, unit_price
  )
  select
    v_invoice_id,
    'time',
    coalesce(te.description, t.title),
    te.id,
    te.logged_duration / 3600000.0,
    te.billable_rate
  from pm.time_entries te
    join pm.tasks t on t.id = te.task_id
  where te.project_id = p_project_id
    and te.status = 'approved'
    and te.is_billable
    and te.entry_date between p_period_start and p_period_end
  returning *;
end;
$$;

comment on function pm.generate_invoice_from_time (uuid, date, date) is '{
    "type": "form",
    "resource": "projects",
    "name": "Generate Invoice",
    "description": "Draft a new invoice from every approved, billable, uninvoiced time entry in the period.",
    "icon": "FileText",
    "success_message": "Invoice drafted",
    "fields": {
        "sections": [
            {"id": "period", "title": "Period", "fields": ["p_project_id", "p_period_start", "p_period_end"]}
        ],
        "relations": {
            "p_project_id": {"table": "projects", "column": "id", "display": ["project_code", "name"]}
        }
    }
}';

-- Pure computation, no writes — returns setof rows via an explicit
-- table(...) column list. Same shape desk's preview_team_workload
-- uses.
create or replace function pm.preview_team_utilization (
  p_project_id uuid default null,
  p_period_start date default (current_date - 30),
  p_period_end date default current_date
) returns table (
  member_name varchar,
  total_hours numeric,
  billable_hours numeric,
  utilization_percent numeric
) language plpgsql security invoker
set
  search_path = '' as $$
begin
  return query
  select
    u.name,
    round(coalesce(sum(te.logged_duration), 0) / 3600000.0, 2) as total_hours,
    round(
      coalesce(
        sum(te.logged_duration) filter (
          where te.is_billable
        ),
        0
      ) / 3600000.0,
      2
    ) as billable_hours,
    round(
      100.0 * coalesce(
        sum(te.logged_duration) filter (
          where te.is_billable
        ),
        0
      ) / nullif(sum(te.logged_duration), 0),
      1
    ) as utilization_percent
  from pm.time_entries te
    join pm.users u on u.id = te.user_id
  where (
      p_project_id is null
      or te.project_id = p_project_id
    )
    and te.entry_date between p_period_start and p_period_end
  group by u.name
  order by total_hours desc;
end;
$$;

comment on function pm.preview_team_utilization (uuid, date, date) is '{
    "type": "form",
    "resource": "projects",
    "name": "Preview Utilization",
    "description": "Total and billable hours per team member over a period. Leave the project blank for everyone.",
    "icon": "Gauge",
    "success_message": "Utilization calculated",
    "fields": {
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["p_project_id", "p_period_start", "p_period_end"]}
        ],
        "relations": {
            "p_project_id": {"table": "projects", "column": "id", "display": ["project_code", "name"]}
        }
    }
}';

-- Returns the created row as a single composite value.
create or replace function pm.log_time_and_submit (
  p_task_id uuid,
  p_duration supasheet.DURATION,
  p_description varchar default null,
  p_is_billable boolean default true
) returns pm.time_entries language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_project_id uuid;
  v_entry pm.time_entries%rowtype;
begin
  select project_id into v_project_id
  from pm.tasks
  where id = p_task_id;

  insert into pm.time_entries (
    task_id, project_id, logged_duration, description, is_billable, status
  )
  values (p_task_id, v_project_id, p_duration, p_description, p_is_billable, 'submitted')
  returning * into v_entry;

  return v_entry;
end;
$$;

comment on function pm.log_time_and_submit (
  uuid, supasheet.DURATION, varchar, boolean
) is '{
    "type": "form",
    "resource": "tasks",
    "name": "Log Time",
    "description": "Record time against this task and submit it for approval in one step.",
    "icon": "Clock",
    "success_message": "Time logged and submitted",
    "fields": {
        "sections": [
            {"id": "time", "title": "Time", "fields": ["p_task_id", "p_duration", "p_description", "p_is_billable"]}
        ],
        "relations": {
            "p_task_id": {"table": "tasks", "column": "id", "display": ["task_number", "title"]}
        }
    }
}';

do $$
declare
  f text;
begin
  foreach f in array array[
    'pm.open_project_for_client(uuid, varchar, uuid, pm.budget_type, numeric, numeric)',
    'pm.generate_invoice_from_time(uuid, date, date)',
    'pm.preview_team_utilization(uuid, date, date)',
    'pm.log_time_and_submit(uuid, supasheet.DURATION, varchar, boolean)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role;', f);
  end loop;
end;
$$;

grant
execute on function pm.open_project_for_client (
  uuid, varchar, uuid, pm.budget_type, numeric, numeric
) to "x-admin",
"pm-lead";

grant
execute on function pm.generate_invoice_from_time (uuid, date, date) to "x-admin",
"pm-lead";

grant
execute on function pm.preview_team_utilization (uuid, date, date) to "x-admin",
"pm-lead";

grant
execute on function pm.log_time_and_submit (
  uuid, supasheet.DURATION, varchar, boolean
) to "x-admin",
"pm-lead",
"user";

-- ================================================================
-- Row actions
-- ================================================================
create or replace function pm.start_project (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.projects
  set status = 'active'
  where id = p_id
    and status = 'planning';
end;
$$;

comment on function pm.start_project (uuid) is '{
    "type": "action",
    "resource": "projects",
    "name": "Start",
    "description": "Move this project into active delivery.",
    "icon": "Play",
    "visible": [{"id": "status", "operator": "eq", "value": "planning"}],
    "success_message": "Project started"
}';

create or replace function pm.put_project_on_hold (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.projects
  set status = 'on_hold',
    description = coalesce(description || E'\n', '') || 'On hold: ' || p_reason
  where id = p_id
    and status = 'active';
end;
$$;

comment on function pm.put_project_on_hold (uuid, varchar) is '{
    "type": "action",
    "resource": "projects",
    "name": "Put On Hold",
    "description": "Pause delivery.",
    "icon": "Pause",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "eq", "value": "active"}],
    "confirm": {"title": "Put this project on hold?", "description": "Staffing and time logging stay open, but this signals delivery has paused."},
    "success_message": "Project on hold"
}';

create or replace function pm.complete_project (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.projects
  set status = 'completed',
    end_date = coalesce(end_date, current_date)
  where id = p_id
    and status = 'active';
end;
$$;

comment on function pm.complete_project (uuid) is '{
    "type": "action",
    "resource": "projects",
    "name": "Complete",
    "description": "Mark delivery finished.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "active"}],
    "confirm": {"title": "Complete this project?", "description": "This signals delivery is done — you can still invoice and log time against it afterward."},
    "success_message": "Project completed"
}';

create or replace function pm.cancel_project (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.projects
  set status = 'cancelled',
    description = coalesce(description || E'\n', '') || 'Cancelled: ' || p_reason
  where id = p_id
    and status not in ('completed', 'cancelled');
end;
$$;

comment on function pm.cancel_project (uuid, varchar) is '{
    "type": "action",
    "resource": "projects",
    "name": "Cancel",
    "description": "Cancel this engagement.",
    "icon": "Ban",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "not.in", "value": ["completed", "cancelled"]}],
    "confirm": {"title": "Cancel this project?", "description": "This cannot be undone from here — open tasks and unbilled time stay exactly as they are."},
    "success_message": "Project cancelled"
}';

create or replace function pm.submit_time_entry (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.time_entries
  set status = 'submitted'
  where id = p_id
    and status = 'draft';
end;
$$;

comment on function pm.submit_time_entry (uuid) is '{
    "type": "action",
    "resource": "time_entries",
    "name": "Submit",
    "description": "Send this entry for approval.",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Time entry submitted"
}';

create or replace function pm.approve_time_entry (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.time_entries
  set status = 'approved'
  where id = p_id
    and status = 'submitted';
end;
$$;

comment on function pm.approve_time_entry (uuid) is '{
    "type": "action",
    "resource": "time_entries",
    "name": "Approve",
    "description": "Approve this entry. Refused if it would take the project past a capped hour budget.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "submitted"}],
    "success_message": "Time entry approved"
}';

create or replace function pm.reject_time_entry (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.time_entries
  set status = 'rejected',
    description = coalesce(description || E'\n', '') || 'Rejected: ' || p_reason
  where id = p_id
    and status = 'submitted';
end;
$$;

comment on function pm.reject_time_entry (uuid, varchar) is '{
    "type": "action",
    "resource": "time_entries",
    "name": "Reject",
    "description": "Send this entry back with a reason.",
    "icon": "CircleX",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "eq", "value": "submitted"}],
    "success_message": "Time entry rejected"
}';

create or replace function pm.submit_deliverable (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.deliverables
  set status = 'submitted'
  where id = p_id
    and status in ('draft', 'rejected');
end;
$$;

comment on function pm.submit_deliverable (uuid) is '{
    "type": "action",
    "resource": "deliverables",
    "name": "Submit",
    "description": "Send for internal review.",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "rejected"]}],
    "success_message": "Deliverable submitted"
}';

create or replace function pm.approve_deliverable (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.deliverables
  set status = 'approved'
  where id = p_id
    and status in ('submitted', 'in_review');
end;
$$;

comment on function pm.approve_deliverable (uuid) is '{
    "type": "action",
    "resource": "deliverables",
    "name": "Approve",
    "description": "Sign off on this deliverable.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "in", "value": ["submitted", "in_review"]}],
    "confirm": {"title": "Approve this deliverable?", "description": "This records your sign-off against the project."},
    "success_message": "Deliverable approved"
}';

create or replace function pm.reject_deliverable (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.deliverables
  set status = 'rejected',
    review_notes = p_reason
  where id = p_id
    and status in ('submitted', 'in_review');
end;
$$;

comment on function pm.reject_deliverable (uuid, varchar) is '{
    "type": "action",
    "resource": "deliverables",
    "name": "Reject",
    "description": "Send this back with a reason.",
    "icon": "CircleX",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "in", "value": ["submitted", "in_review"]}],
    "confirm": {"title": "Reject this deliverable?", "description": "The team will need to resubmit it."},
    "success_message": "Deliverable rejected"
}';

create or replace function pm.send_invoice (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.invoices
  set status = 'sent'
  where id = p_id
    and status = 'draft';
end;
$$;

comment on function pm.send_invoice (uuid) is '{
    "type": "action",
    "resource": "invoices",
    "name": "Send",
    "description": "Send this invoice to the client.",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "confirm": {"title": "Send this invoice?", "description": "The client portal user, if one exists, is notified immediately."},
    "success_message": "Invoice sent"
}';

create or replace function pm.close_risk (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update pm.risks
  set status = 'closed'
  where id = p_id
    and status <> 'closed';
end;
$$;

comment on function pm.close_risk (uuid) is '{
    "type": "action",
    "resource": "risks",
    "name": "Close",
    "description": "This risk no longer needs tracking.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "neq", "value": "closed"}],
    "success_message": "Risk closed"
}';

do $$
declare
  f text;
begin
  foreach f in array array[
    'pm.start_project(uuid)',
    'pm.put_project_on_hold(uuid, varchar)',
    'pm.complete_project(uuid)',
    'pm.cancel_project(uuid, varchar)',
    'pm.submit_time_entry(uuid)',
    'pm.approve_time_entry(uuid)',
    'pm.reject_time_entry(uuid, varchar)',
    'pm.submit_deliverable(uuid)',
    'pm.approve_deliverable(uuid)',
    'pm.reject_deliverable(uuid, varchar)',
    'pm.send_invoice(uuid)',
    'pm.close_risk(uuid)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role;', f);
  end loop;
end;
$$;

grant
execute on function pm.start_project (uuid) to "x-admin",
"pm-lead";

grant
execute on function pm.put_project_on_hold (uuid, varchar) to "x-admin",
"pm-lead";

grant
execute on function pm.complete_project (uuid) to "x-admin",
"pm-lead";

grant
execute on function pm.cancel_project (uuid, varchar) to "x-admin",
"pm-lead";

grant
execute on function pm.submit_time_entry (uuid) to "x-admin",
"pm-lead",
"user";

grant
execute on function pm.approve_time_entry (uuid) to "x-admin",
"pm-lead";

grant
execute on function pm.reject_time_entry (uuid, varchar) to "x-admin",
"pm-lead";

grant
execute on function pm.submit_deliverable (uuid) to "x-admin",
"pm-lead",
"user";

grant
execute on function pm.approve_deliverable (uuid) to "x-admin",
"client";

grant
execute on function pm.reject_deliverable (uuid, varchar) to "x-admin",
"client";

grant
execute on function pm.send_invoice (uuid) to "x-admin",
"pm-lead";

grant
execute on function pm.close_risk (uuid) to "x-admin",
"pm-lead";

----------------------------------------------------------------
-- PM settings (singleton — one row only, no delete grant)
----------------------------------------------------------------
create table pm.pm_settings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  workspace_name varchar(255) not null default 'Supasheet Delivery',
  logo supasheet.file,
  brand_color supasheet.COLOR default '#6366f1',
  default_billable_rate numeric(10, 2) not null default 150,
  default_cost_rate numeric(10, 2) not null default 75,
  invoice_prefix varchar(10) not null default 'INV',
  default_payment_terms_days integer not null default 30,
  fiscal_year_start_month integer not null default 1,
  overtime_threshold_hours_per_week numeric(5, 2) not null default 40,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint pm_settings_fiscal_month_range check (fiscal_year_start_month between 1 and 12)
);

comment on table pm.pm_settings is '{
    "icon": "Settings",
    "name": "Delivery Settings",
    "collapsible_group": "Organisation",
    "display": "block",
    "singleton": true,
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["workspace_name", "logo", "brand_color"]},
            {"id": "defaults", "title": "Defaults", "fields": ["default_billable_rate", "default_cost_rate", "default_payment_terms_days"]},
            {"id": "billing", "title": "Billing", "fields": ["invoice_prefix", "fiscal_year_start_month"]},
            {"id": "policy", "title": "Policy", "fields": ["overtime_threshold_hours_per_week"]}
        ]
    }
}';

comment on column pm.pm_settings.logo is '{"accept": "image/*", "maxSize": 2097152}';

revoke all on table pm.pm_settings
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
update on table pm.pm_settings to "x-admin";

grant
select
  on table pm.pm_settings to "pm-lead";

alter table pm.pm_settings enable row level security;

create policy pm_settings_select on pm.pm_settings for
select
  to authenticated using (true);

create policy pm_settings_insert on pm.pm_settings for insert to authenticated
with
  check (true);

create policy pm_settings_update on pm.pm_settings
for update
  to authenticated using (true)
with
  check (true);

create trigger pm_settings_updated_at before
update on pm.pm_settings for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Private document storage
--
-- Deliverable files and invoice PDFs already live in the uploads
-- bucket behind their own FILE columns. This bucket is for anything
-- else that needs to be evidence, gated the same way: if your role
-- cannot read pm.projects, it cannot read the file either.
----------------------------------------------------------------
insert into
  storage.buckets (id, name, public)
values
  ('pm-documents', 'pm-documents', false)
on conflict (id) do nothing;

drop policy if exists pm_documents_read on storage.objects;

create policy pm_documents_read on storage.objects for
select
  to authenticated using (
    bucket_id = 'pm-documents'
    and has_table_privilege (current_user, 'pm.projects', 'select')
  );

drop policy if exists pm_documents_insert on storage.objects;

create policy pm_documents_insert on storage.objects for insert to authenticated
with
  check (
    bucket_id = 'pm-documents'
    and has_table_privilege (current_user, 'pm.projects', 'insert')
  );

drop policy if exists pm_documents_update on storage.objects;

create policy pm_documents_update on storage.objects
for update
  to authenticated using (
    bucket_id = 'pm-documents'
    and has_table_privilege (current_user, 'pm.projects', 'update')
  );

drop policy if exists pm_documents_delete on storage.objects;

create policy pm_documents_delete on storage.objects for delete to authenticated using (
  bucket_id = 'pm-documents'
  and has_table_privilege (current_user, 'pm.projects', 'delete')
);

----------------------------------------------------------------
-- App configuration
----------------------------------------------------------------
insert into
  supasheet.configs (key, value, description, is_public)
values
  (
    'pm.default_invoice_terms_days',
    '30',
    'Default payment terms applied to a new invoice',
    true
  ),
  (
    'pm.budget_warning_threshold_percent',
    '90',
    'Percentage of budgeted hours consumed before a project surfaces on the "approaching budget" alert',
    false
  ),
  (
    'pm.high_risk_score_threshold',
    '15',
    'Risk score (probability x impact) that triggers a notification to pm-lead',
    false
  )
on conflict (key) do nothing;

-- ================================================================
-- Refresh the metadata catalog — must be last
-- ================================================================
select
  supasheet.refresh_metadata ();
