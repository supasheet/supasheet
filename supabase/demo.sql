-- ================================================================
-- Supasheet Demo — "Studio" (agency / project delivery workspace)
-- ================================================================
-- A single, unified schema + seed file that exercises every
-- Supasheet superpower in one coherent business domain: a small
-- creative/dev studio managing clients, staff, projects, tasks,
-- billable services, and invoices.
--
-- Feature coverage:
--   - Native-role RBAC (CREATE ROLE + GRANT, no permissions table)
--   - Row Level Security scoped to native roles via pg_has_role()
--   - All column data types: URL, TEL, EMAIL, RICH_TEXT, COLOR,
--     PERCENTAGE, DURATION, file, AVATAR, enums, arrays
--   - All view layouts: kanban, calendar, gallery, list, tree
--   - Field sections, filter presets, quick_create,
--     conditional field behavior, lookup fill + lookup filter
--   - Singleton resource (workspace_settings)
--   - Many-to-many junction with inline form (project_members)
--   - One-to-many detail lines with lookup-fill + a business
--     trigger that keeps parent totals in sync (invoice_items)
--   - Reports, dashboard widgets (card_1..6, table_1..2, list_1..4),
--     charts (pie/bar/line/radar)
--   - Notifications (fan-out on create/status change)
--   - Audit logging and per-resource comments
--   - Detail page "tabs" allowlist
--   - Row actions backed by SQL functions (publish, cancel, set
--     priority via enum picker, duplicate)
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/demo.sql
--
-- Requires the base Supasheet migrations (supabase/migrations/*)
-- to already be applied. Also add "demo" to config.toml's
-- `api.schemas` / `api.extra_search_path` so PostgREST exposes it.
-- ================================================================
create schema if not exists demo;

grant usage on schema demo to authenticated;

----------------------------------------------------------------
-- Enums + permissions (must commit before use)
----------------------------------------------------------------
begin;

create type demo.client_status as enum('lead', 'active', 'on_hold', 'churned');

create type demo.department as enum(
  'design',
  'engineering',
  'product',
  'marketing',
  'sales',
  'operations'
);

create type demo.employment_status as enum('active', 'on_leave', 'offboarded');

create type demo.project_status as enum(
  'planning',
  'active',
  'on_hold',
  'completed',
  'cancelled'
);

create type demo.priority_level as enum('low', 'medium', 'high', 'critical');

create type demo.milestone_status as enum('pending', 'in_progress', 'completed', 'missed');

create type demo.task_status as enum(
  'todo',
  'in_progress',
  'in_review',
  'blocked',
  'done',
  'cancelled'
);

create type demo.service_category as enum(
  'design',
  'development',
  'consulting',
  'marketing',
  'support'
);

create type demo.invoice_status as enum('draft', 'sent', 'paid', 'overdue', 'void');

create type demo.portfolio_category as enum(
  'web',
  'branding',
  'mobile',
  'product_design',
  'marketing'
);

commit;

----------------------------------------------------------------
-- Users mirror view
----------------------------------------------------------------
create or replace view demo.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on demo.users
from
  authenticated,
  service_role;

grant
select
  on demo.users to "x-admin",
  "user";

----------------------------------------------------------------
-- Clients
----------------------------------------------------------------
create table demo.clients (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null,
  logo supasheet.file,
  website supasheet.URL,
  email supasheet.EMAIL,
  phone supasheet.TEL,
  industry varchar(255),
  status demo.client_status not null default 'lead',
  address text,
  city varchar(255),
  country varchar(255),
  tags varchar(500) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column demo.clients.status is '{
    "progress": false,
    "enums": {
        "lead": {"variant": "info", "icon": "Sprout"},
        "active": {"variant": "success", "icon": "BadgeCheck"},
        "on_hold": {"variant": "warning", "icon": "PauseCircle"},
        "churned": {"variant": "destructive", "icon": "UserMinus"}
    }
}';

comment on table demo.clients is '{
    "icon": "Building2",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "title": "name",
        "badges": ["status", "tags"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Clients By Status",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "industry",
            "date": "created_at",
            "badge": "status"
        },
        {
            "id": "gallery",
            "name": "Client Gallery",
            "type": "gallery",
            "cover": "logo",
            "title": "name",
            "description": "industry",
            "badge": "status"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "leads", "name": "Leads", "filters": [{"id": "status", "value": "lead", "operator": "eq"}]},
        {"id": "at_risk", "name": "At Risk", "filters": [{"id": "status", "value": "on_hold", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "profile", "title": "Profile", "fields": ["name", "logo", "industry", "status"]},
            {"id": "contact", "title": "Contact", "fields": ["website", "email", "phone"]},
            {"id": "location", "title": "Location", "fields": ["address", "city", "country"]},
            {"id": "organization", "title": "Organization", "fields": ["tags", "color"]},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [{"table": "users", "on": "user_id", "columns": ["name", "email"]}]
    }
}';

comment on column demo.clients.logo is '{"accept":"image/*", "maxSize": 2097152}';

revoke all on table demo.clients
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table demo.clients to "x-admin";

grant
select
,
  insert,
update on table demo.clients to "user";

create index idx_demo_clients_user_id on demo.clients (user_id);

create index idx_demo_clients_status on demo.clients (status);

create index idx_demo_clients_industry on demo.clients (industry);

create index idx_demo_clients_country on demo.clients (country);

create index idx_demo_clients_created_at on demo.clients (created_at desc);

alter table demo.clients enable row level security;

create policy clients_select on demo.clients for
select
  to authenticated using (true);

create policy clients_insert on demo.clients for insert to authenticated
with
  check (true);

create policy clients_update on demo.clients
for update
  to authenticated using (true)
with
  check (true);

create policy clients_delete on demo.clients for delete to authenticated using (true);

----------------------------------------------------------------
-- Team members (staff directory, org hierarchy)
----------------------------------------------------------------
create table demo.team_members (
  id uuid primary key default extensions.uuid_generate_v4 (),
  user_id uuid references supasheet.users (id) on delete set null,
  manager_id uuid references demo.team_members (id) on delete set null,
  name varchar(255) not null,
  avatar supasheet.AVATAR,
  email supasheet.EMAIL,
  phone supasheet.TEL,
  job_title varchar(255),
  department demo.department not null default 'operations',
  employment_status demo.employment_status not null default 'active',
  bio supasheet.RICH_TEXT,
  hire_date date,
  hourly_rate numeric(10, 2),
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column demo.team_members.department is '{
    "progress": false,
    "enums": {
        "design": {"variant": "secondary", "icon": "Palette"},
        "engineering": {"variant": "info", "icon": "Code2"},
        "product": {"variant": "default", "icon": "Box"},
        "marketing": {"variant": "warning", "icon": "Megaphone"},
        "sales": {"variant": "success", "icon": "TrendingUp"},
        "operations": {"variant": "outline", "icon": "Settings2"}
    }
}';

comment on column demo.team_members.employment_status is '{
    "progress": false,
    "enums": {
        "active": {"variant": "success", "icon": "CircleCheck"},
        "on_leave": {"variant": "warning", "icon": "Palmtree"},
        "offboarded": {"variant": "destructive", "icon": "UserX"}
    }
}';

comment on table demo.team_members is '{
    "icon": "Users",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "title": "name",
        "badges": ["department", "employment_status"]
    },
    "views": [
        {
            "id": "tree",
            "name": "Org Chart",
            "type": "tree",
            "parent": "manager_id",
            "title": "name",
            "secondary": "job_title"
        },
        {
            "id": "gallery",
            "name": "Team Gallery",
            "type": "gallery",
            "cover": "avatar",
            "title": "name",
            "description": "job_title",
            "badge": "department"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "employment_status", "value": "active", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "avatar", "job_title", "department"]},
            {"id": "contact", "title": "Contact", "fields": ["email", "phone"]},
            {"id": "employment", "title": "Employment", "fields": ["employment_status", "manager_id", "hire_date", "hourly_rate"]},
            {"id": "extras", "title": "Bio", "collapsible": true, "fields": ["bio", "color"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [
            {"table": "users", "on": "user_id", "columns": ["name", "email"]},
            {"table": "team_members", "on": "manager_id", "alias": "manager", "columns": ["name", "job_title"]}
        ]
    }
}';

comment on column demo.team_members.avatar is '{"accept":"image/*"}';

revoke all on table demo.team_members
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table demo.team_members to "x-admin";

grant
select
  on table demo.team_members to "user";

create index idx_demo_team_members_user_id on demo.team_members (user_id);

create index idx_demo_team_members_manager_id on demo.team_members (manager_id);

create index idx_demo_team_members_department on demo.team_members (department);

create index idx_demo_team_members_employment_status on demo.team_members (employment_status);

alter table demo.team_members enable row level security;

create policy team_members_select on demo.team_members for
select
  to authenticated using (true);

create policy team_members_insert on demo.team_members for insert to authenticated
with
  check (true);

create policy team_members_update on demo.team_members
for update
  to authenticated using (true)
with
  check (true);

create policy team_members_delete on demo.team_members for delete to authenticated using (true);

----------------------------------------------------------------
-- Team member details (1:1 HR profile extension — a unique,
-- not-null FK to team_members keeps sensitive/rarely-needed data
-- off the main directory record; the UI renders it as a single
-- embedded record on the team member's detail page, not a list)
----------------------------------------------------------------
create table demo.team_member_details (
  id uuid primary key default extensions.uuid_generate_v4 (),
  team_member_id uuid not null references demo.team_members (id) on delete cascade,
  date_of_birth date,
  national_id varchar(100),
  tax_id varchar(100),
  address text,
  emergency_contact_name varchar(255),
  emergency_contact_phone supasheet.TEL,
  bank_name varchar(255),
  bank_account_number varchar(100),
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (team_member_id)
);

comment on table demo.team_member_details is '{
    "icon": "IdCard",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["team_member_id", "date_of_birth", "national_id", "tax_id", "address"]},
            {"id": "emergency", "title": "Emergency Contact", "fields": ["emergency_contact_name", "emergency_contact_phone"]},
            {"id": "banking", "title": "Banking", "fields": ["bank_name", "bank_account_number"]},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "join": [{"table": "team_members", "on": "team_member_id", "columns": ["name", "job_title", "avatar"]}]
    }
}';

revoke all on table demo.team_member_details
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table demo.team_member_details to "x-admin";

alter table demo.team_member_details enable row level security;

create policy team_member_details_select on demo.team_member_details for
select
  to authenticated using (true);

create policy team_member_details_insert on demo.team_member_details for insert to authenticated
with
  check (true);

create policy team_member_details_update on demo.team_member_details
for update
  to authenticated using (true)
with
  check (true);

create policy team_member_details_delete on demo.team_member_details for delete to authenticated using (true);

----------------------------------------------------------------
-- Projects
----------------------------------------------------------------
create table demo.projects (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null,
  client_id uuid references demo.clients (id) on delete set null,
  owner_id uuid references demo.team_members (id) on delete set null,
  description supasheet.RICH_TEXT,
  cover supasheet.file,
  status demo.project_status not null default 'planning',
  priority demo.priority_level not null default 'medium',
  budget numeric(12, 2),
  start_date date,
  due_date date,
  progress supasheet.PERCENTAGE default 0,
  tags varchar(500) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column demo.projects.status is '{
    "progress": true,
    "enums": {
        "planning": {"variant": "outline", "icon": "ClipboardList"},
        "active": {"variant": "info", "icon": "Play"},
        "on_hold": {"variant": "warning", "icon": "PauseCircle"},
        "completed": {"variant": "success", "icon": "CheckCircle2"},
        "cancelled": {"variant": "destructive", "icon": "XCircle"}
    }
}';

comment on column demo.projects.priority is '{
    "progress": false,
    "enums": {
        "low": {"variant": "outline", "icon": "ArrowDown"},
        "medium": {"variant": "info", "icon": "Minus"},
        "high": {"variant": "warning", "icon": "ArrowUp"},
        "critical": {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on table demo.projects is '{
    "icon": "FolderKanban",
    "display": "block",
    "primary_view": "kanban",
    "tabs": ["tasks", "milestones", "invoices", "project_members"],
    "detail": {
        "title": "name",
        "badges": ["status", "priority", "tags"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Projects By Status",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "notes",
            "date": "due_date",
            "badge": "priority"
        },
        {
            "id": "calendar",
            "name": "Project Timeline",
            "type": "calendar",
            "title": "name",
            "badge": "status",
            "start_date": "start_date",
            "end_date": "due_date"
        },
        {
            "id": "list",
            "name": "All Projects",
            "type": "list",
            "title": "name",
            "description": "status",
            "field_1": "status",
            "field_2": "due_date"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "high_priority", "name": "High Priority", "filters": [{"id": "priority", "value": ["high", "critical"], "operator": "in"}]},
        {"id": "completed", "name": "Completed", "filters": [{"id": "status", "value": "completed", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "overview", "title": "Overview", "fields": ["name", "client_id", "owner_id", "description", "cover"]},
            {"id": "status", "title": "Status", "fields": ["status", "priority", "progress"]},
            {"id": "schedule", "title": "Schedule", "fields": ["start_date", "due_date"]},
            {"id": "budgeting", "title": "Budgeting", "fields": ["budget"]},
            {"id": "organization", "title": "Organization", "fields": ["tags", "color"]},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "due_date", "desc": false}],
        "join": [
            {"table": "users", "on": "user_id", "columns": ["name", "email"]},
            {"table": "clients", "on": "client_id", "columns": ["name", "industry"]},
            {"table": "team_members", "on": "owner_id", "columns": ["name", "avatar", "job_title"]}
        ]
    }
}';

comment on column demo.projects.cover is '{"accept":"image/*"}';

revoke all on table demo.projects
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table demo.projects to "x-admin";

grant
select
,
  insert,
update on table demo.projects to "user";

create index idx_demo_projects_client_id on demo.projects (client_id);

create index idx_demo_projects_owner_id on demo.projects (owner_id);

create index idx_demo_projects_status on demo.projects (status);

create index idx_demo_projects_priority on demo.projects (priority);

create index idx_demo_projects_due_date on demo.projects (due_date);

create index idx_demo_projects_user_id on demo.projects (user_id);

create index idx_demo_projects_created_at on demo.projects (created_at desc);

alter table demo.projects enable row level security;

create policy projects_select on demo.projects for
select
  to authenticated using (true);

create policy projects_insert on demo.projects for insert to authenticated
with
  check (true);

create policy projects_update on demo.projects
for update
  to authenticated using (true)
with
  check (true);

create policy projects_delete on demo.projects for delete to authenticated using (true);

----------------------------------------------------------------
-- Row action: cancel a project
----------------------------------------------------------------
create or replace function demo.cancel_project (p_id uuid, p_reason text default null) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_status demo.project_status;
begin
  select status into v_status from demo.projects where id = p_id;

  if v_status in ('completed', 'cancelled') then
    raise exception 'Cannot cancel a % project', v_status;
  end if;

  update demo.projects
  set status = 'cancelled',
      notes = coalesce(notes || E'\n', '') || coalesce('Cancelled: ' || p_reason, 'Cancelled')
  where id = p_id;
end;
$$;

comment on function demo.cancel_project (uuid, text) is '{
    "type": "action",
    "resource": "projects",
    "name": "Cancel project",
    "description": "Mark this project as cancelled",
    "icon": "XCircle",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "not.in", "value": ["completed", "cancelled"]}],
    "confirm": {"title": "Cancel this project?", "description": "This sets the project status to cancelled."},
    "success_message": "Project cancelled"
}';

revoke all on function demo.cancel_project (uuid, text)
from
  public,
  authenticated,
  service_role;

grant
execute on function demo.cancel_project (uuid, text) to "x-admin",
"user";

----------------------------------------------------------------
-- Row action: set a project's priority (value-picker, no hardcoded value)
----------------------------------------------------------------
create or replace function demo.set_project_priority (p_id uuid, p_priority demo.priority_level) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update demo.projects set priority = p_priority where id = p_id;
end;
$$;

comment on function demo.set_project_priority (uuid, demo.priority_level) is '{
    "type": "action",
    "resource": "projects",
    "name": "Set priority",
    "icon": "Flag",
    "action_type": "picker"
}';

revoke all on function demo.set_project_priority (uuid, demo.priority_level)
from
  public,
  authenticated,
  service_role;

grant
execute on function demo.set_project_priority (uuid, demo.priority_level) to "x-admin",
"user";

----------------------------------------------------------------
-- Project ↔ Team member junction (many-to-many, inline form)
----------------------------------------------------------------
create table demo.project_members (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid not null references demo.projects (id) on delete cascade,
  team_member_id uuid not null references demo.team_members (id) on delete cascade,
  role_on_project varchar(255),
  allocation_percent supasheet.PERCENTAGE,
  created_at timestamptz default current_timestamp,
  unique (project_id, team_member_id)
);

comment on table demo.project_members is '{
    "icon": "UserPlus",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "link", "title": "Link", "fields": ["project_id", "team_member_id", "role_on_project"]},
            {"id": "details", "title": "Details", "fields": ["allocation_percent"]}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "projects", "on": "project_id", "columns": ["name", "status"]},
            {"table": "team_members", "on": "team_member_id", "columns": ["name", "job_title", "avatar"]}
        ]
    }
}';

revoke all on table demo.project_members
from
  authenticated,
  service_role;

grant
select
,
  insert,
  delete on table demo.project_members to "x-admin",
  "user";

create index idx_demo_project_members_project_id on demo.project_members (project_id);

create index idx_demo_project_members_team_member_id on demo.project_members (team_member_id);

alter table demo.project_members enable row level security;

create policy project_members_select on demo.project_members for
select
  to authenticated using (true);

create policy project_members_insert on demo.project_members for insert to authenticated
with
  check (true);

create policy project_members_delete on demo.project_members for delete to authenticated using (true);

----------------------------------------------------------------
-- Milestones
----------------------------------------------------------------
create table demo.milestones (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid not null references demo.projects (id) on delete cascade,
  title varchar(255) not null,
  description text,
  due_date date,
  status demo.milestone_status not null default 'pending',
  sort_order integer default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column demo.milestones.status is '{
    "progress": true,
    "enums": {
        "pending": {"variant": "outline", "icon": "Circle"},
        "in_progress": {"variant": "info", "icon": "Loader"},
        "completed": {"variant": "success", "icon": "CheckCircle2"},
        "missed": {"variant": "destructive", "icon": "AlertTriangle"}
    }
}';

comment on table demo.milestones is '{
    "icon": "Milestone",
    "display": "block",
    "primary_view": "calendar",
    "detail": {
        "title": "title",
        "badges": ["status"]
    },
    "views": [
        {
            "id": "calendar",
            "name": "Milestone Calendar",
            "type": "calendar",
            "title": "title",
            "badge": "status",
            "start_date": "due_date",
            "end_date": "due_date"
        },
        {
            "id": "kanban",
            "name": "Milestones By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "description",
            "date": "due_date"
        }
    ],
    "fields": {
        "sections": [
            {"id": "details", "title": "Details", "fields": ["project_id", "title", "description"]},
            {"id": "schedule", "title": "Schedule", "fields": ["status", "due_date", "sort_order"]}
        ]
    },
    "query": {
        "sort": [{"id": "due_date", "desc": false}],
        "join": [{"table": "projects", "on": "project_id", "columns": ["name", "status"]}]
    }
}';

revoke all on table demo.milestones
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table demo.milestones to "x-admin";

grant
select
,
  insert,
update on table demo.milestones to "user";

create index idx_demo_milestones_project_id on demo.milestones (project_id);

create index idx_demo_milestones_status on demo.milestones (status);

create index idx_demo_milestones_due_date on demo.milestones (due_date);

alter table demo.milestones enable row level security;

create policy milestones_select on demo.milestones for
select
  to authenticated using (true);

create policy milestones_insert on demo.milestones for insert to authenticated
with
  check (true);

create policy milestones_update on demo.milestones
for update
  to authenticated using (true)
with
  check (true);

create policy milestones_delete on demo.milestones for delete to authenticated using (true);

----------------------------------------------------------------
-- Tasks (kanban + tree for subtasks + calendar for due dates)
----------------------------------------------------------------
create table demo.tasks (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid references demo.projects (id) on delete cascade,
  milestone_id uuid references demo.milestones (id) on delete set null,
  parent_task_id uuid references demo.tasks (id) on delete cascade,
  assignee_id uuid references demo.team_members (id) on delete set null,
  title varchar(500) not null,
  description supasheet.RICH_TEXT,
  status demo.task_status not null default 'todo',
  priority demo.priority_level not null default 'medium',
  blocked_reason text,
  estimated_hours numeric(6, 2),
  due_date date,
  completed_at timestamptz,
  attachments supasheet.file,
  tags varchar(500) [],
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column demo.tasks.status is '{
    "progress": true,
    "enums": {
        "todo": {"variant": "outline", "icon": "Circle"},
        "in_progress": {"variant": "info", "icon": "Loader"},
        "in_review": {"variant": "warning", "icon": "Eye"},
        "blocked": {"variant": "destructive", "icon": "Ban"},
        "done": {"variant": "success", "icon": "CheckCircle2"},
        "cancelled": {"variant": "secondary", "icon": "XCircle"}
    }
}';

comment on column demo.tasks.priority is '{
    "progress": false,
    "iconOnly": true,
    "enums": {
        "low": {"variant": "outline", "icon": "ArrowDown"},
        "medium": {"variant": "info", "icon": "Minus"},
        "high": {"variant": "warning", "icon": "ArrowUp"},
        "critical": {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on table demo.tasks is '{
    "icon": "ListTodo",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "title": "title",
        "badges": ["status", "priority", "tags"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Tasks By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "description",
            "date": "due_date",
            "badge": "priority"
        },
        {
            "id": "tree",
            "name": "Task Breakdown",
            "type": "tree",
            "parent": "parent_task_id",
            "title": "title",
            "secondary": "status"
        },
        {
            "id": "calendar",
            "name": "Task Due Dates",
            "type": "calendar",
            "title": "title",
            "badge": "status",
            "start_date": "created_at",
            "end_date": "due_date"
        }
    ],
    "filter_presets": [
        {"id": "todo", "name": "To Do", "filters": [{"id": "status", "value": "todo", "operator": "eq"}]},
        {"id": "in_progress", "name": "In Progress", "filters": [{"id": "status", "value": "in_progress", "operator": "eq"}]},
        {"id": "blocked", "name": "Blocked", "filters": [{"id": "status", "value": "blocked", "operator": "eq"}]},
        {"id": "done", "name": "Done", "filters": [{"id": "status", "value": "done", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["title", "project_id", "assignee_id", "due_date", "priority"],
        "sections": [
            {"id": "summary", "title": "Summary", "fields": ["title", "description", "project_id", "milestone_id", "parent_task_id"]},
            {"id": "assignment", "title": "Assignment", "fields": ["assignee_id", "status", "priority"]},
            {"id": "blocker", "title": "Blocker", "fields": ["blocked_reason"]},
            {"id": "schedule", "title": "Schedule", "fields": ["due_date", "estimated_hours", "completed_at"]},
            {"id": "extras", "title": "Attachments & tags", "collapsible": true, "fields": ["attachments", "tags"]}
        ],
        "behavior": {
            "blocked_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "blocked"}],
                "required": [{"id": "status", "operator": "eq", "value": "blocked"}]
            },
            "completed_at": {
                "visible": [{"id": "status", "operator": "eq", "value": "done"}]
            }
        }
    },
    "query": {
        "sort": [{"id": "due_date", "desc": false}],
        "join": [
            {"table": "users", "on": "user_id", "columns": ["name", "email"]},
            {"table": "projects", "on": "project_id", "columns": ["name", "status"]},
            {"table": "milestones", "on": "milestone_id", "columns": ["title", "status"]},
            {"table": "team_members", "on": "assignee_id", "columns": ["name", "avatar", "job_title"]}
        ]
    }
}';

comment on column demo.tasks.attachments is '{"accept":"*", "maxFiles": 20}';

revoke all on table demo.tasks
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table demo.tasks to "x-admin";

grant
select
,
  insert,
update on table demo.tasks to "user";

create index idx_demo_tasks_project_id on demo.tasks (project_id);

create index idx_demo_tasks_milestone_id on demo.tasks (milestone_id);

create index idx_demo_tasks_parent_task_id on demo.tasks (parent_task_id);

create index idx_demo_tasks_assignee_id on demo.tasks (assignee_id);

create index idx_demo_tasks_status on demo.tasks (status);

create index idx_demo_tasks_priority on demo.tasks (priority);

create index idx_demo_tasks_due_date on demo.tasks (due_date);

create index idx_demo_tasks_user_id on demo.tasks (user_id);

create index idx_demo_tasks_created_at on demo.tasks (created_at desc);

alter table demo.tasks enable row level security;

create policy tasks_select on demo.tasks for
select
  to authenticated using (true);

create policy tasks_insert on demo.tasks for insert to authenticated
with
  check (true);

create policy tasks_update on demo.tasks
for update
  to authenticated using (true)
with
  check (true);

create policy tasks_delete on demo.tasks for delete to authenticated using (true);

----------------------------------------------------------------
-- Row action: duplicate a task
----------------------------------------------------------------
create or replace function demo.duplicate_task (p_id uuid) returns uuid language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_new_id uuid;
begin
  insert into demo.tasks (
    project_id, milestone_id, parent_task_id, assignee_id,
    title, description, status, priority, estimated_hours, tags
  )
  select
    project_id, milestone_id, parent_task_id, assignee_id,
    title || ' (copy)', description, 'todo', priority, estimated_hours, tags
  from demo.tasks
  where id = p_id
  returning id into v_new_id;

  if v_new_id is null then
    raise exception 'Task not found';
  end if;

  return v_new_id;
end;
$$;

comment on function demo.duplicate_task (uuid) is '{
    "type": "action",
    "resource": "tasks",
    "name": "Duplicate",
    "description": "Create a copy of this task as a new to-do",
    "icon": "Copy",
    "success_message": "Task duplicated"
}';

revoke all on function demo.duplicate_task (uuid)
from
  public,
  authenticated,
  service_role;

grant
execute on function demo.duplicate_task (uuid) to "x-admin",
"user";

----------------------------------------------------------------
-- Portfolio items (published case studies — gallery is the natural
-- default here: a visual grid of finished work, like a studio's
-- public portfolio page)
----------------------------------------------------------------
create table demo.portfolio_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  project_id uuid references demo.projects (id) on delete set null,
  client_id uuid references demo.clients (id) on delete set null,
  title varchar(255) not null,
  summary text,
  description supasheet.RICH_TEXT,
  cover supasheet.file,
  category demo.portfolio_category not null default 'web',
  external_url supasheet.URL,
  is_published boolean not null default true,
  published_at date,
  tags varchar(500) [],
  color supasheet.COLOR,
  sort_order integer default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column demo.portfolio_items.category is '{
    "progress": false,
    "enums": {
        "web": {"variant": "info", "icon": "Globe"},
        "branding": {"variant": "secondary", "icon": "Palette"},
        "mobile": {"variant": "success", "icon": "Smartphone"},
        "product_design": {"variant": "default", "icon": "Box"},
        "marketing": {"variant": "warning", "icon": "Megaphone"}
    }
}';

comment on table demo.portfolio_items is '{
    "icon": "Image",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "title": "title",
        "badges": ["category", "tags"]
    },
    "views": [
        {
            "id": "gallery",
            "name": "Portfolio Gallery",
            "type": "gallery",
            "cover": "cover",
            "title": "title",
            "description": "summary",
            "badge": "category"
        },
        {
            "id": "list",
            "name": "Case Studies List",
            "type": "list",
            "title": "title",
            "description": "summary",
            "field_1": "category",
            "field_2": "published_at"
        }
    ],
    "filter_presets": [
        {"id": "published", "name": "Published", "filters": [{"id": "is_published", "value": "true", "operator": "eq"}]},
        {"id": "draft", "name": "Drafts", "filters": [{"id": "is_published", "value": "false", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "overview", "title": "Overview", "fields": ["title", "cover", "category", "project_id", "client_id"]},
            {"id": "content", "title": "Content", "fields": ["summary", "description", "external_url"]},
            {"id": "publishing", "title": "Publishing", "fields": ["is_published", "published_at", "sort_order"]},
            {"id": "organization", "title": "Organization", "fields": ["tags", "color"]}
        ]
    },
    "query": {
        "sort": [{"id": "sort_order", "desc": false}],
        "join": [
            {"table": "projects", "on": "project_id", "columns": ["name", "status"]},
            {"table": "clients", "on": "client_id", "columns": ["name", "industry"]}
        ]
    }
}';

comment on column demo.portfolio_items.cover is '{"accept":"image/*", "maxSize": 5242880}';

revoke all on table demo.portfolio_items
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table demo.portfolio_items to "x-admin";

grant
select
,
  insert,
update on table demo.portfolio_items to "user";

create index idx_demo_portfolio_items_project_id on demo.portfolio_items (project_id);

create index idx_demo_portfolio_items_client_id on demo.portfolio_items (client_id);

create index idx_demo_portfolio_items_category on demo.portfolio_items (category);

create index idx_demo_portfolio_items_is_published on demo.portfolio_items (is_published);

create index idx_demo_portfolio_items_sort_order on demo.portfolio_items (sort_order);

alter table demo.portfolio_items enable row level security;

create policy portfolio_items_select on demo.portfolio_items for
select
  to authenticated using (true);

create policy portfolio_items_insert on demo.portfolio_items for insert to authenticated
with
  check (true);

create policy portfolio_items_update on demo.portfolio_items
for update
  to authenticated using (true)
with
  check (true);

create policy portfolio_items_delete on demo.portfolio_items for delete to authenticated using (true);

----------------------------------------------------------------
-- Row action: publish a portfolio item
----------------------------------------------------------------
create or replace function demo.publish_portfolio_item (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update demo.portfolio_items
  set is_published = true, published_at = current_date
  where id = p_id;

  if not found then
    raise exception 'Portfolio item not found';
  end if;
end;
$$;

comment on function demo.publish_portfolio_item (uuid) is '{
    "type": "action",
    "resource": "portfolio_items",
    "name": "Publish",
    "description": "Make this portfolio item visible on the public site",
    "icon": "Globe",
    "visible": [{"id": "is_published", "operator": "eq", "value": "false"}],
    "success_message": "Portfolio item published"
}';

revoke all on function demo.publish_portfolio_item (uuid)
from
  public,
  authenticated,
  service_role;

grant
execute on function demo.publish_portfolio_item (uuid) to "x-admin",
"user";

----------------------------------------------------------------
-- Services (billable catalog — list view)
----------------------------------------------------------------
create table demo.services (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null,
  description text,
  category demo.service_category not null default 'development',
  default_rate numeric(10, 2) not null default 0,
  unit varchar(20) not null default 'hour',
  is_active boolean not null default true,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column demo.services.category is '{
    "progress": false,
    "enums": {
        "design": {"variant": "secondary", "icon": "Palette"},
        "development": {"variant": "info", "icon": "Code2"},
        "consulting": {"variant": "default", "icon": "Lightbulb"},
        "marketing": {"variant": "warning", "icon": "Megaphone"},
        "support": {"variant": "success", "icon": "LifeBuoy"}
    }
}';

comment on table demo.services is '{
    "icon": "Wrench",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "title": "name",
        "badges": ["category"]
    },
    "views": [
        {
            "id": "list",
            "name": "Service Catalog",
            "type": "list",
            "title": "name",
            "description": "category",
            "field_1": "default_rate",
            "field_2": "unit"
        },
        {
            "id": "kanban",
            "name": "Services By Category",
            "type": "kanban",
            "group": "category",
            "title": "name",
            "description": "description"
        }
    ],
    "fields": {
        "sections": [
            {"id": "details", "title": "Details", "fields": ["name", "description", "category"]},
            {"id": "pricing", "title": "Pricing", "fields": ["default_rate", "unit", "is_active", "color"]}
        ]
    },
    "query": {"sort": [{"id": "name", "desc": false}]}
}';

revoke all on table demo.services
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table demo.services to "x-admin";

grant
select
  on table demo.services to "user";

create index idx_demo_services_category on demo.services (category);

create index idx_demo_services_is_active on demo.services (is_active);

alter table demo.services enable row level security;

create policy services_select on demo.services for
select
  to authenticated using (true);

create policy services_insert on demo.services for insert to authenticated
with
  check (true);

create policy services_update on demo.services
for update
  to authenticated using (true)
with
  check (true);

create policy services_delete on demo.services for delete to authenticated using (true);

----------------------------------------------------------------
-- Invoices
----------------------------------------------------------------
create sequence if not exists demo.invoice_number_seq;

create table demo.invoices (
  id uuid primary key default extensions.uuid_generate_v4 (),
  invoice_number varchar(50) not null unique default (
    'INV-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('demo.invoice_number_seq')::text, 4, '0')
  ),
  client_id uuid not null references demo.clients (id) on delete restrict,
  project_id uuid references demo.projects (id) on delete set null,
  status demo.invoice_status not null default 'draft',
  issue_date date not null default current_date,
  due_date date,
  currency varchar(3) not null default 'USD',
  subtotal numeric(12, 2) not null default 0,
  tax_rate supasheet.PERCENTAGE default 0,
  tax_amount numeric(12, 2) not null default 0,
  total numeric(12, 2) not null default 0,
  paid_at timestamptz,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column demo.invoices.status is '{
    "progress": true,
    "enums": {
        "draft": {"variant": "outline", "icon": "FileEdit"},
        "sent": {"variant": "info", "icon": "Send"},
        "paid": {"variant": "success", "icon": "CircleCheck"},
        "overdue": {"variant": "destructive", "icon": "AlertCircle"},
        "void": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table demo.invoices is '{
    "icon": "Receipt",
    "display": "block",
    "primary_view": "kanban",
    "tabs": ["invoice_items"],
    "detail": {
        "title": "invoice_number",
        "badges": ["status"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Invoices By Status",
            "type": "kanban",
            "group": "status",
            "title": "invoice_number",
            "description": "notes",
            "date": "due_date",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Invoice Due Dates",
            "type": "calendar",
            "title": "invoice_number",
            "badge": "status",
            "start_date": "issue_date",
            "end_date": "due_date"
        }
    ],
    "filter_presets": [
        {"id": "unpaid", "name": "Unpaid", "filters": [{"id": "status", "value": ["sent", "overdue"], "operator": "in"}]},
        {"id": "overdue", "name": "Overdue", "filters": [{"id": "status", "value": "overdue", "operator": "eq"}]},
        {"id": "paid", "name": "Paid", "filters": [{"id": "status", "value": "paid", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "details", "title": "Details", "fields": ["invoice_number", "client_id", "project_id", "status"]},
            {"id": "dates", "title": "Dates", "fields": ["issue_date", "due_date", "paid_at"]},
            {"id": "amounts", "title": "Amounts", "fields": ["currency", "subtotal", "tax_rate", "tax_amount", "total"]},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ],
        "behavior": {
            "paid_at": {"visible": [{"id": "status", "operator": "eq", "value": "paid"}]}
        },
        "lookups": {
            "project_id": {"filter": [{"on": "client_id", "column": "client_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "due_date", "desc": true}],
        "join": [
            {"table": "users", "on": "user_id", "columns": ["name", "email"]},
            {"table": "clients", "on": "client_id", "columns": ["name", "email"]},
            {"table": "projects", "on": "project_id", "columns": ["name", "status"]}
        ]
    }
}';

revoke all on table demo.invoices
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table demo.invoices to "x-admin";

grant
select
,
  insert,
update on table demo.invoices to "user";

create index idx_demo_invoices_client_id on demo.invoices (client_id);

create index idx_demo_invoices_project_id on demo.invoices (project_id);

create index idx_demo_invoices_status on demo.invoices (status);

create index idx_demo_invoices_issue_date on demo.invoices (issue_date);

create index idx_demo_invoices_due_date on demo.invoices (due_date);

create index idx_demo_invoices_user_id on demo.invoices (user_id);

alter table demo.invoices enable row level security;

create policy invoices_select on demo.invoices for
select
  to authenticated using (true);

create policy invoices_insert on demo.invoices for insert to authenticated
with
  check (true);

create policy invoices_update on demo.invoices
for update
  to authenticated using (true)
with
  check (true);

create policy invoices_delete on demo.invoices for delete to authenticated using (true);

----------------------------------------------------------------
-- Invoice line items (lookup fill from services catalog)
----------------------------------------------------------------
create table demo.invoice_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  invoice_id uuid not null references demo.invoices (id) on delete cascade,
  service_id uuid references demo.services (id) on delete set null,
  description varchar(500),
  quantity numeric(10, 2) not null default 1,
  unit_price numeric(10, 2) not null default 0,
  line_total numeric(12, 2) generated always as (quantity * unit_price) stored,
  sort_order integer default 0,
  created_at timestamptz default current_timestamp
);

comment on table demo.invoice_items is '{
    "icon": "ListPlus",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line item", "fields": ["service_id", "description"]},
            {"id": "pricing", "title": "Pricing", "fields": ["quantity", "unit_price", "line_total"]}
        ],
        "lookups": {
            "service_id": {
                "fill": [
                    {"target": "unit_price", "source": "default_rate"},
                    {"target": "description", "source": "name"}
                ]
            }
        }
    },
    "query": {
        "sort": [{"id": "sort_order", "desc": false}],
        "join": [
            {"table": "invoices", "on": "invoice_id", "columns": ["invoice_number", "status"]},
            {"table": "services", "on": "service_id", "columns": ["name", "category"]}
        ]
    }
}';

revoke all on table demo.invoice_items
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table demo.invoice_items to "x-admin",
"user";

create index idx_demo_invoice_items_invoice_id on demo.invoice_items (invoice_id);

create index idx_demo_invoice_items_service_id on demo.invoice_items (service_id);

alter table demo.invoice_items enable row level security;

create policy invoice_items_select on demo.invoice_items for
select
  to authenticated using (true);

create policy invoice_items_insert on demo.invoice_items for insert to authenticated
with
  check (true);

create policy invoice_items_update on demo.invoice_items
for update
  to authenticated using (true)
with
  check (true);

create policy invoice_items_delete on demo.invoice_items for delete to authenticated using (true);

-- Keep parent invoice totals in sync with its line items.
create or replace function demo.trg_invoice_items_recalc () returns trigger as $$
declare
    v_invoice_id uuid := coalesce(new.invoice_id, old.invoice_id);
    v_subtotal   numeric(12, 2);
    v_tax_rate   numeric;
    v_tax_amount numeric(12, 2);
begin
    select coalesce(sum(line_total), 0) into v_subtotal
    from demo.invoice_items
    where invoice_id = v_invoice_id;

    select coalesce(tax_rate, 0) into v_tax_rate
    from demo.invoices
    where id = v_invoice_id;

    v_tax_amount := round(v_subtotal * v_tax_rate / 100, 2);

    update demo.invoices
    set subtotal   = v_subtotal,
        tax_amount = v_tax_amount,
        total      = v_subtotal + v_tax_amount,
        updated_at = current_timestamp
    where id = v_invoice_id;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger invoice_items_recalc
after insert or update or delete on demo.invoice_items for each row
execute function demo.trg_invoice_items_recalc ();

----------------------------------------------------------------
-- Time entries (billable hours logged against tasks)
----------------------------------------------------------------
create table demo.time_entries (
  id uuid primary key default extensions.uuid_generate_v4 (),
  task_id uuid references demo.tasks (id) on delete cascade,
  team_member_id uuid references demo.team_members (id) on delete set null,
  entry_date date not null default current_date,
  duration supasheet.DURATION not null,
  is_billable boolean not null default true,
  notes text,
  created_at timestamptz default current_timestamp
);

comment on table demo.time_entries is '{
    "icon": "Clock",
    "display": "block",
    "fields": {
        "sections": [
            {"id": "entry", "title": "Entry", "fields": ["task_id", "team_member_id", "entry_date"]},
            {"id": "duration", "title": "Duration", "fields": ["duration", "is_billable", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "entry_date", "desc": true}],
        "join": [
            {"table": "tasks", "on": "task_id", "columns": ["title", "status"]},
            {"table": "team_members", "on": "team_member_id", "columns": ["name", "avatar"]}
        ]
    }
}';

revoke all on table demo.time_entries
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table demo.time_entries to "x-admin";

grant
select
,
  insert,
update on table demo.time_entries to "user";

create index idx_demo_time_entries_task_id on demo.time_entries (task_id);

create index idx_demo_time_entries_team_member_id on demo.time_entries (team_member_id);

create index idx_demo_time_entries_entry_date on demo.time_entries (entry_date desc);

alter table demo.time_entries enable row level security;

create policy time_entries_select on demo.time_entries for
select
  to authenticated using (true);

create policy time_entries_insert on demo.time_entries for insert to authenticated
with
  check (true);

create policy time_entries_update on demo.time_entries
for update
  to authenticated using (true)
with
  check (true);

create policy time_entries_delete on demo.time_entries for delete to authenticated using (true);

----------------------------------------------------------------
-- Workspace settings (singleton — one row only)
----------------------------------------------------------------
create table demo.workspace_settings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  workspace_name varchar(255) not null default 'My Studio',
  logo supasheet.file,
  primary_color supasheet.COLOR default '#6366f1',
  default_currency varchar(3) not null default 'USD',
  invoice_prefix varchar(20) not null default 'INV',
  support_email supasheet.EMAIL,
  timezone varchar(100) not null default 'UTC',
  fiscal_year_start date,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table demo.workspace_settings is '{
    "icon": "Settings",
    "name": "Workspace Settings",
    "display": "block",
    "singleton": true,
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["workspace_name", "logo", "primary_color"]},
            {"id": "billing", "title": "Billing", "fields": ["default_currency", "invoice_prefix", "fiscal_year_start"]},
            {"id": "contact", "title": "Contact", "fields": ["support_email", "timezone"]}
        ]
    }
}';

comment on column demo.workspace_settings.logo is '{"accept":"image/*", "maxSize": 2097152}';

revoke all on table demo.workspace_settings
from
  authenticated,
  service_role;

grant
select
,
  insert,
update on table demo.workspace_settings to "x-admin";

grant
select
  on table demo.workspace_settings to "user";

alter table demo.workspace_settings enable row level security;

create policy workspace_settings_select on demo.workspace_settings for
select
  to authenticated using (true);

create policy workspace_settings_insert on demo.workspace_settings for insert to authenticated
with
  check (true);

create policy workspace_settings_update on demo.workspace_settings
for update
  to authenticated using (true)
with
  check (true);

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view demo.clients_report
with
  (security_invoker = true) as
select
  c.id,
  c.name,
  c.industry,
  c.status,
  c.country,
  u.name as owner,
  count(distinct p.id) as project_count,
  count(distinct i.id) as invoice_count,
  coalesce(
    sum(i.total) filter (
      where
        i.status = 'paid'
    ),
    0
  ) as revenue_collected,
  coalesce(
    sum(i.total) filter (
      where
        i.status in ('sent', 'overdue')
    ),
    0
  ) as revenue_outstanding,
  c.created_at
from
  demo.clients c
  left join supasheet.users u on u.id = c.user_id
  left join demo.projects p on p.client_id = c.id
  left join demo.invoices i on i.client_id = c.id
group by
  c.id,
  u.name;

revoke all on demo.clients_report
from
  authenticated,
  service_role;

grant
select
  on demo.clients_report to "x-admin",
  "user";

comment on view demo.clients_report is '{"type": "report", "name": "Clients Report", "description": "Clients with project counts and invoice revenue rollups"}';

create or replace view demo.projects_report
with
  (security_invoker = true) as
select
  p.id,
  p.name,
  p.status,
  p.priority,
  p.budget,
  p.progress,
  p.due_date,
  c.name as client,
  tm.name as owner,
  count(distinct t.id) as task_count,
  count(distinct t.id) filter (
    where
      t.status = 'done'
  ) as tasks_done,
  coalesce(sum(te.duration), 0) as total_seconds_logged,
  p.created_at
from
  demo.projects p
  left join demo.clients c on c.id = p.client_id
  left join demo.team_members tm on tm.id = p.owner_id
  left join demo.tasks t on t.project_id = p.id
  left join demo.time_entries te on te.task_id = t.id
group by
  p.id,
  c.name,
  tm.name;

revoke all on demo.projects_report
from
  authenticated,
  service_role;

grant
select
  on demo.projects_report to "x-admin",
  "user";

comment on view demo.projects_report is '{"type": "report", "name": "Projects Report", "description": "Projects with client, owner, task, and logged-time rollups"}';

create or replace view demo.invoices_report
with
  (security_invoker = true) as
select
  i.id,
  i.invoice_number,
  i.status,
  i.issue_date,
  i.due_date,
  i.currency,
  i.total,
  c.name as client,
  p.name as project,
  count(ii.id) as item_count,
  i.created_at
from
  demo.invoices i
  left join demo.clients c on c.id = i.client_id
  left join demo.projects p on p.id = i.project_id
  left join demo.invoice_items ii on ii.invoice_id = i.id
group by
  i.id,
  c.name,
  p.name;

revoke all on demo.invoices_report
from
  authenticated,
  service_role;

grant
select
  on demo.invoices_report to "x-admin",
  "user";

comment on view demo.invoices_report is '{"type": "report", "name": "Invoices Report", "description": "Invoices with client, project, and line item counts"}';

create or replace view demo.team_utilization_report
with
  (security_invoker = true) as
select
  tm.id,
  tm.name,
  tm.department,
  tm.job_title,
  count(distinct t.id) as tasks_assigned,
  count(distinct t.id) filter (
    where
      t.status = 'done'
  ) as tasks_completed,
  count(distinct pm.project_id) as active_projects,
  coalesce(sum(te.duration), 0) as total_seconds_logged
from
  demo.team_members tm
  left join demo.tasks t on t.assignee_id = tm.id
  left join demo.project_members pm on pm.team_member_id = tm.id
  left join demo.time_entries te on te.team_member_id = tm.id
group by
  tm.id;

revoke all on demo.team_utilization_report
from
  authenticated,
  service_role;

grant
select
  on demo.team_utilization_report to "x-admin",
  "user";

comment on view demo.team_utilization_report is '{"type": "report", "name": "Team Utilization Report", "description": "Task load and logged hours per team member"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: count of active projects
create or replace view demo.active_projects_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'folder-kanban' as icon,
  'active projects' as label
from
  demo.projects
where
  status = 'active';

revoke all on demo.active_projects_count
from
  authenticated,
  service_role;

grant
select
  on demo.active_projects_count to "x-admin",
  "user";

-- card_2: task completion (done vs open)
create or replace view demo.task_completion
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'done'
  ) as primary,
  count(*) filter (
    where
      status not in ('done', 'cancelled')
  ) as secondary,
  'Done' as primary_label,
  'Open' as secondary_label
from
  demo.tasks;

revoke all on demo.task_completion
from
  authenticated,
  service_role;

grant
select
  on demo.task_completion to "x-admin",
  "user";

-- card_3: revenue collected + collection rate
create or replace view demo.revenue_summary
with
  (security_invoker = true) as
select
  coalesce(
    sum(total) filter (
      where
        status = 'paid'
    ),
    0
  ) as value,
  case
    when count(*) filter (
      where
        status in ('paid', 'sent', 'overdue')
    ) > 0 then round(
      (
        count(*) filter (
          where
            status = 'paid'
        )::numeric / count(*) filter (
          where
            status in ('paid', 'sent', 'overdue')
        )::numeric
      ) * 100,
      1
    )
    else 0
  end as percent
from
  demo.invoices;

revoke all on demo.revenue_summary
from
  authenticated,
  service_role;

grant
select
  on demo.revenue_summary to "x-admin",
  "user";

-- card_4: project health (at-risk breakdown)
create or replace view demo.project_health
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status not in ('completed', 'cancelled')
      and (
        priority in ('high', 'critical')
        or (
          due_date is not null
          and due_date < current_date
        )
      )
  ) as current,
  count(*) filter (
    where
      status not in ('completed', 'cancelled')
  ) as total,
  json_build_array(
    json_build_object(
      'label',
      'Critical',
      'value',
      count(*) filter (
        where
          status not in ('completed', 'cancelled')
          and priority = 'critical'
      )
    ),
    json_build_object(
      'label',
      'High',
      'value',
      count(*) filter (
        where
          status not in ('completed', 'cancelled')
          and priority = 'high'
      )
    ),
    json_build_object(
      'label',
      'Overdue',
      'value',
      count(*) filter (
        where
          status not in ('completed', 'cancelled')
          and due_date is not null
          and due_date < current_date
      )
    )
  ) as segments
from
  demo.projects;

revoke all on demo.project_health
from
  authenticated,
  service_role;

grant
select
  on demo.project_health to "x-admin",
  "user";

-- table_1: recent tasks
create or replace view demo.recent_tasks
with
  (security_invoker = true) as
select
  title,
  status,
  coalesce(due_date::text, 'no due date') as amount,
  to_char(created_at, 'MM/DD') as date,
  '/demo/resource/tasks/' || id || '/detail' as link
from
  demo.tasks
order by
  created_at desc
limit
  10;

revoke all on demo.recent_tasks
from
  authenticated,
  service_role;

grant
select
  on demo.recent_tasks to "x-admin",
  "user";

-- table_1: upcoming milestones (pairs with Recent Tasks to fill the row)
create or replace view demo.upcoming_milestones
with
  (security_invoker = true) as
select
  m.title,
  p.name as project,
  m.status,
  to_char(m.due_date, 'MM/DD') as date
from
  demo.milestones m
  left join demo.projects p on p.id = m.project_id
where
  m.status not in ('completed', 'missed')
  and m.due_date is not null
order by
  m.due_date asc
limit
  10;

revoke all on demo.upcoming_milestones
from
  authenticated,
  service_role;

grant
select
  on demo.upcoming_milestones to "x-admin",
  "user";

-- table_2: top clients by revenue
create or replace view demo.top_clients
with
  (security_invoker = true) as
select
  c.name as client,
  c.industry,
  count(i.id) as invoices,
  coalesce(sum(i.total), 0) as revenue,
  '/demo/resource/clients/' || c.id || '/detail' as link
from
  demo.clients c
  left join demo.invoices i on i.client_id = c.id
group by
  c.id,
  c.name,
  c.industry
having
  count(i.id) > 0
order by
  revenue desc nulls last
limit
  10;

revoke all on demo.top_clients
from
  authenticated,
  service_role;

grant
select
  on demo.top_clients to "x-admin",
  "user";

-- list_1: task alerts (blocked or overdue high/critical tasks)
create or replace view demo.task_alerts
with
  (security_invoker = true) as
select
  t.title,
  p.name || ' · ' || coalesce(
    t.blocked_reason,
    'due ' || to_char(t.due_date, 'MM/DD')
  ) as description,
  case
    when t.blocked_reason is not null then 'octagon-alert'
    when t.due_date < current_date then 'clock-alert'
    else 'triangle-alert'
  end as icon,
  case
    when t.blocked_reason is not null then 'destructive'
    when t.due_date < current_date then 'warning'
    else 'info'
  end as variant,
  '/demo/resource/tasks/' || t.id || '/detail' as link
from
  demo.tasks t
  left join demo.projects p on p.id = t.project_id
where
  t.status not in ('done', 'cancelled')
  and (
    t.blocked_reason is not null
    or t.priority in ('high', 'critical')
    or (
      t.due_date is not null
      and t.due_date < current_date
    )
  )
order by
  t.due_date asc nulls last
limit
  5;

revoke all on demo.task_alerts
from
  authenticated,
  service_role;

grant
select
  on demo.task_alerts to "x-admin",
  "user";

-- list_2: recent invoices (wider list with amount + due date fields)
create or replace view demo.recent_invoices
with
  (security_invoker = true) as
select
  i.invoice_number as title,
  c.name || ' · ' || initcap(i.status::text) as description,
  case
    when i.status = 'overdue' then 'circle-alert'
    when i.status = 'paid' then 'circle-check'
    else 'file-text'
  end as icon,
  case
    when i.status = 'overdue' then 'destructive'
    when i.status = 'paid' then 'success'
    else 'secondary'
  end as variant,
  to_char(i.total, 'FM$999,999,990.00') as field_1,
  coalesce('due ' || to_char(i.due_date, 'MM/DD/YY'), '—') as field_2,
  '/demo/resource/invoices/' || i.id || '/detail' as link
from
  demo.invoices i
  join demo.clients c on c.id = i.client_id
order by
  i.created_at desc
limit
  5;

revoke all on demo.recent_invoices
from
  authenticated,
  service_role;

grant
select
  on demo.recent_invoices to "x-admin",
  "user";

-- list_3: recent task activity (avatar feed, narrow — one activity source,
-- ordered newest first; avatar initials are derived client-side from `actor`)
create or replace view demo.recent_task_activity
with
  (security_invoker = true) as
select
  tm.name as actor,
  case
    when t.status = 'done' then 'completed'
    when t.status = 'in_review' then 'submitted for review on'
    when t.status = 'blocked' then 'flagged as blocked on'
    when t.status = 'in_progress' then 'started work on'
    else 'updated'
  end as action,
  t.title as entity,
  to_char(t.updated_at, 'Mon DD, YYYY') as date,
  '/demo/resource/tasks/' || t.id || '/detail' as link
from
  demo.tasks t
  join demo.team_members tm on tm.id = t.assignee_id
where
  t.status <> 'cancelled'
order by
  t.updated_at desc
limit
  5;

revoke all on demo.recent_task_activity
from
  authenticated,
  service_role;

grant
select
  on demo.recent_task_activity to "x-admin",
  "user";

-- list_4: top task closers (leaderboard, narrow — ranked by completed task
-- count; the bar for each row is relative to the top row's value)
create or replace view demo.top_task_closers
with
  (security_invoker = true) as
select
  tm.name,
  count(*) as value,
  tm.job_title as label,
  '/demo/resource/team_members/' || tm.id || '/detail' as link
from
  demo.tasks t
  join demo.team_members tm on tm.id = t.assignee_id
where
  t.status = 'done'
group by
  tm.id,
  tm.name,
  tm.job_title
order by
  value desc
limit
  5;

revoke all on demo.top_task_closers
from
  authenticated,
  service_role;

grant
select
  on demo.top_task_closers to "x-admin",
  "user";

-- card_5: task board overview (2x width — a headline total plus a single
-- ranked breakdown of that SAME pool, all from demo.tasks alone)
create or replace view demo.task_board_overview
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status not in ('done', 'cancelled')
  ) as value,
  'Open Tasks' as label,
  'list-checks' as icon,
  json_build_array(
    json_build_object(
      'label',
      'Low',
      'value',
      count(*) filter (
        where
          priority = 'low'
          and status not in ('done', 'cancelled')
      ),
      'variant',
      'secondary'
    ),
    json_build_object(
      'label',
      'Medium',
      'value',
      count(*) filter (
        where
          priority = 'medium'
          and status not in ('done', 'cancelled')
      ),
      'variant',
      'info'
    ),
    json_build_object(
      'label',
      'High',
      'value',
      count(*) filter (
        where
          priority = 'high'
          and status not in ('done', 'cancelled')
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
          priority = 'critical'
          and status not in ('done', 'cancelled')
      ),
      'variant',
      'destructive'
    )
  ) as breakdown
from
  demo.tasks;

revoke all on demo.task_board_overview
from
  authenticated,
  service_role;

grant
select
  on demo.task_board_overview to "x-admin",
  "user";

-- card_5: client snapshot (2x width — a headline total plus a single ranked
-- breakdown of that SAME pool, all from demo.clients alone)
create or replace view demo.client_snapshot
with
  (security_invoker = true) as
select
  count(*) as value,
  'Clients' as label,
  'building-2' as icon,
  json_build_array(
    json_build_object(
      'label',
      'Active',
      'value',
      count(*) filter (
        where
          status = 'active'
      ),
      'variant',
      'success'
    ),
    json_build_object(
      'label',
      'Leads',
      'value',
      count(*) filter (
        where
          status = 'lead'
      ),
      'variant',
      'info'
    ),
    json_build_object(
      'label',
      'On Hold',
      'value',
      count(*) filter (
        where
          status = 'on_hold'
      ),
      'variant',
      'warning'
    ),
    json_build_object(
      'label',
      'Churned',
      'value',
      count(*) filter (
        where
          status = 'churned'
      ),
      'variant',
      'secondary'
    )
  ) as breakdown
from
  demo.clients;

revoke all on demo.client_snapshot
from
  authenticated,
  service_role;

grant
select
  on demo.client_snapshot to "x-admin",
  "user";

-- card_6: task velocity (4x width, full row — related task counts in one card)
create or replace view demo.task_velocity
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Todo',
      'value',
      count(*) filter (
        where
          status = 'todo'
      ),
      'icon',
      'circle'
    ),
    json_build_object(
      'label',
      'In Progress',
      'value',
      count(*) filter (
        where
          status = 'in_progress'
      ),
      'icon',
      'loader-circle'
    ),
    json_build_object(
      'label',
      'Blocked',
      'value',
      count(*) filter (
        where
          blocked_reason is not null
          and status not in ('done', 'cancelled')
      ),
      'icon',
      'octagon-alert'
    ),
    json_build_object(
      'label',
      'Overdue',
      'value',
      count(*) filter (
        where
          due_date < current_date
          and status not in ('done', 'cancelled')
      ),
      'icon',
      'clock-alert'
    )
  ) as metrics
from
  demo.tasks;

revoke all on demo.task_velocity
from
  authenticated,
  service_role;

grant
select
  on demo.task_velocity to "x-admin",
  "user";

-- card_2: client pipeline (active vs lead) — shown on the clients resource page
create or replace view demo.client_pipeline
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'active'
  ) as primary,
  count(*) filter (
    where
      status = 'lead'
  ) as secondary,
  'Active' as primary_label,
  'Leads' as secondary_label
from
  demo.clients;

revoke all on demo.client_pipeline
from
  authenticated,
  service_role;

grant
select
  on demo.client_pipeline to "x-admin",
  "user";

-- card_3: project progress (active count + average completion) — shown on the projects resource page
create or replace view demo.project_progress
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'active'
  ) as value,
  coalesce(
    round(
      (
        avg(progress) filter (
          where
            status = 'active'
        )
      )::numeric,
      1
    ),
    0
  ) as percent
from
  demo.projects;

revoke all on demo.project_progress
from
  authenticated,
  service_role;

grant
select
  on demo.project_progress to "x-admin",
  "user";

-- card_1: outstanding invoice balance — shown on the invoices resource page
create or replace view demo.outstanding_balance
with
  (security_invoker = true) as
select
  coalesce(
    sum(total) filter (
      where
        status in ('sent', 'overdue')
    ),
    0
  ) as value,
  'receipt' as icon,
  'outstanding balance' as label
from
  demo.invoices;

revoke all on demo.outstanding_balance
from
  authenticated,
  service_role;

grant
select
  on demo.outstanding_balance to "x-admin",
  "user";

-- card_1: active team member count — shown on the team_members resource page
create or replace view demo.active_team_members_count
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      employment_status = 'active'
  ) as value,
  'users' as icon,
  'active team members' as label
from
  demo.team_members;

revoke all on demo.active_team_members_count
from
  authenticated,
  service_role;

grant
select
  on demo.active_team_members_count to "x-admin",
  "user";

comment on view demo.active_projects_count is '{"type": "dashboard_widget", "name": "Active Projects", "description": "Count of projects currently active", "widget_type": "card_1"}';

comment on view demo.task_completion is '{"type": "dashboard_widget", "name": "Task Completion", "description": "Done vs open tasks", "widget_type": "card_2"}';

comment on view demo.revenue_summary is '{"type": "dashboard_widget", "name": "Revenue Collected", "description": "Paid revenue and collection rate", "widget_type": "card_3"}';

comment on view demo.project_health is '{"type": "dashboard_widget", "name": "Project Health", "description": "At-risk open projects breakdown", "widget_type": "card_4"}';

comment on view demo.recent_tasks is '{"type": "dashboard_widget", "name": "Recent Tasks", "description": "Latest 10 tasks", "widget_type": "table_1", "resource": "tasks", "link": "/demo/resource/tasks"}';

comment on view demo.upcoming_milestones is '{"type": "dashboard_widget", "name": "Upcoming Milestones", "description": "Next 10 milestones due across active projects", "widget_type": "table_1"}';

comment on view demo.top_clients is '{"type": "dashboard_widget", "name": "Top Clients", "description": "Top 10 clients by invoiced revenue", "widget_type": "table_2", "link": "/demo/resource/clients"}';

comment on view demo.task_alerts is '{"type": "dashboard_widget", "name": "Task Alerts", "description": "Blocked or overdue high-priority tasks", "widget_type": "list_1", "link": "/demo/resource/tasks"}';

comment on view demo.recent_invoices is '{"type": "dashboard_widget", "name": "Recent Invoices", "description": "Latest invoices with amount and due date", "widget_type": "list_2", "link": "/demo/resource/invoices"}';

comment on view demo.recent_task_activity is '{"type": "dashboard_widget", "name": "Recent Activity", "description": "Latest task actions across the team", "widget_type": "list_3", "link": "/demo/resource/tasks"}';

comment on view demo.top_task_closers is '{"type": "dashboard_widget", "name": "Top Task Closers", "description": "Team members ranked by completed tasks", "widget_type": "list_4", "link": "/demo/resource/team_members"}';

comment on view demo.task_board_overview is '{"type": "dashboard_widget", "name": "Task Board Overview", "description": "Open tasks by priority", "widget_type": "card_5"}';

comment on view demo.client_snapshot is '{"type": "dashboard_widget", "name": "Client Snapshot", "description": "Clients by status", "widget_type": "card_5"}';

comment on view demo.task_velocity is '{"type": "dashboard_widget", "name": "Task Velocity", "description": "Tasks by workflow stage", "widget_type": "card_6"}';

comment on view demo.client_pipeline is '{"type": "dashboard_widget", "name": "Client Pipeline", "description": "Active clients vs. new leads", "widget_type": "card_2", "resource": "clients"}';

comment on view demo.project_progress is '{"type": "dashboard_widget", "name": "Project Progress", "description": "Active projects and their average completion", "widget_type": "card_3", "resource": "projects"}';

comment on view demo.outstanding_balance is '{"type": "dashboard_widget", "name": "Outstanding Balance", "description": "Unpaid total across sent and overdue invoices", "widget_type": "card_1", "resource": "invoices"}';

comment on view demo.active_team_members_count is '{"type": "dashboard_widget", "name": "Active Team Members", "description": "Count of staff currently active", "widget_type": "card_1", "resource": "team_members"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: tasks by status
create or replace view demo.tasks_by_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  demo.tasks
group by
  status
order by
  case status
    when 'todo' then 1
    when 'in_progress' then 2
    when 'in_review' then 3
    when 'blocked' then 4
    when 'done' then 5
    when 'cancelled' then 6
  end;

revoke all on demo.tasks_by_status_pie
from
  authenticated,
  service_role;

grant
select
  on demo.tasks_by_status_pie to "x-admin",
  "user";

-- Bar: projects by client
create or replace view demo.projects_by_client_bar
with
  (security_invoker = true) as
select
  c.name as label,
  count(p.id) as total,
  count(p.id) filter (
    where
      p.status = 'completed'
  ) as completed
from
  demo.clients c
  left join demo.projects p on p.client_id = c.id
group by
  c.id,
  c.name
having
  count(p.id) > 0
order by
  count(p.id) desc
limit
  10;

revoke all on demo.projects_by_client_bar
from
  authenticated,
  service_role;

grant
select
  on demo.projects_by_client_bar to "x-admin",
  "user";

-- Line: weekly invoiced revenue (last 8 weeks)
create or replace view demo.revenue_trend_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('week', issue_date), 'Mon DD') as date,
  count(*) as invoices,
  coalesce(sum(total), 0)::bigint as revenue
from
  demo.invoices
where
  issue_date >= current_date - interval '8 weeks'
group by
  date_trunc('week', issue_date)
order by
  date_trunc('week', issue_date);

revoke all on demo.revenue_trend_line
from
  authenticated,
  service_role;

grant
select
  on demo.revenue_trend_line to "x-admin",
  "user";

-- Radar: team workload by department
create or replace view demo.team_workload_radar
with
  (security_invoker = true) as
select
  tm.department::text as metric,
  count(t.id) as total,
  count(t.id) filter (
    where
      t.status = 'done'
  ) as completed,
  count(t.id) filter (
    where
      t.status = 'in_progress'
  ) as in_progress
from
  demo.team_members tm
  left join demo.tasks t on t.assignee_id = tm.id
group by
  tm.department;

revoke all on demo.team_workload_radar
from
  authenticated,
  service_role;

grant
select
  on demo.team_workload_radar to "x-admin",
  "user";

-- Pie: clients by status — shown on the clients resource page
create or replace view demo.clients_by_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  demo.clients
group by
  status;

revoke all on demo.clients_by_status_pie
from
  authenticated,
  service_role;

grant
select
  on demo.clients_by_status_pie to "x-admin",
  "user";

-- Bar: projects by priority — shown on the projects resource page
create or replace view demo.projects_by_priority_bar
with
  (security_invoker = true) as
select
  priority::text as label,
  count(*) as total,
  count(*) filter (
    where
      status = 'completed'
  ) as completed
from
  demo.projects
group by
  priority
order by
  case priority
    when 'critical' then 1
    when 'high' then 2
    when 'medium' then 3
    when 'low' then 4
  end;

revoke all on demo.projects_by_priority_bar
from
  authenticated,
  service_role;

grant
select
  on demo.projects_by_priority_bar to "x-admin",
  "user";

-- Pie: invoices by status — shown on the invoices resource page
create or replace view demo.invoices_by_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  demo.invoices
group by
  status;

revoke all on demo.invoices_by_status_pie
from
  authenticated,
  service_role;

grant
select
  on demo.invoices_by_status_pie to "x-admin",
  "user";

-- Pie: team by department — shown on the team_members resource page
create or replace view demo.team_by_department_pie
with
  (security_invoker = true) as
select
  department::text as label,
  count(*) as value
from
  demo.team_members
group by
  department;

revoke all on demo.team_by_department_pie
from
  authenticated,
  service_role;

grant
select
  on demo.team_by_department_pie to "x-admin",
  "user";

comment on view demo.tasks_by_status_pie is '{"type": "chart", "name": "Tasks By Status", "description": "Task count grouped by workflow status", "chart_type": "pie", "resource": "tasks"}';

comment on view demo.projects_by_client_bar is '{"type": "chart", "name": "Projects By Client", "description": "Top 10 clients by project count", "chart_type": "bar"}';

comment on view demo.revenue_trend_line is '{"type": "chart", "name": "Revenue Trend", "description": "Weekly invoice count and revenue over 8 weeks", "chart_type": "line"}';

comment on view demo.team_workload_radar is '{"type": "chart", "name": "Team Workload", "description": "Task load per department", "chart_type": "radar"}';

comment on view demo.clients_by_status_pie is '{"type": "chart", "name": "Clients By Status", "description": "Distribution of clients across lifecycle stages", "chart_type": "pie", "resource": "clients"}';

comment on view demo.projects_by_priority_bar is '{"type": "chart", "name": "Projects By Priority", "description": "Project counts and completions across priority levels", "chart_type": "bar", "resource": "projects"}';

comment on view demo.invoices_by_status_pie is '{"type": "chart", "name": "Invoices By Status", "description": "Invoice count across lifecycle statuses", "chart_type": "pie", "resource": "invoices"}';

comment on view demo.team_by_department_pie is '{"type": "chart", "name": "Team By Department", "description": "Headcount distribution across departments", "chart_type": "pie", "resource": "team_members"}';

----------------------------------------------------------------
-- Audit triggers
----------------------------------------------------------------
create trigger audit_demo_clients_insert
after insert on demo.clients for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_clients_update
after update on demo.clients for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_clients_delete
before delete on demo.clients for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_team_members_insert
after insert on demo.team_members for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_team_members_update
after update on demo.team_members for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_team_members_delete
before delete on demo.team_members for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_team_member_details_insert
after insert on demo.team_member_details for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_team_member_details_update
after update on demo.team_member_details for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_team_member_details_delete
before delete on demo.team_member_details for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_projects_insert
after insert on demo.projects for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_projects_update
after update on demo.projects for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_projects_delete
before delete on demo.projects for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_project_members_insert
after insert on demo.project_members for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_project_members_delete
before delete on demo.project_members for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_milestones_insert
after insert on demo.milestones for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_milestones_update
after update on demo.milestones for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_milestones_delete
before delete on demo.milestones for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_tasks_insert
after insert on demo.tasks for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_tasks_update
after update on demo.tasks for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_tasks_delete
before delete on demo.tasks for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_portfolio_items_insert
after insert on demo.portfolio_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_portfolio_items_update
after update on demo.portfolio_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_portfolio_items_delete
before delete on demo.portfolio_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_services_insert
after insert on demo.services for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_services_update
after update on demo.services for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_services_delete
before delete on demo.services for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_invoices_insert
after insert on demo.invoices for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_invoices_update
after update on demo.invoices for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_invoices_delete
before delete on demo.invoices for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_invoice_items_insert
after insert on demo.invoice_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_invoice_items_update
after update on demo.invoice_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_invoice_items_delete
before delete on demo.invoice_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_time_entries_insert
after insert on demo.time_entries for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_time_entries_update
after update on demo.time_entries for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_time_entries_delete
before delete on demo.time_entries for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_workspace_settings_insert
after insert on demo.workspace_settings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_demo_workspace_settings_update
after update on demo.workspace_settings for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
-- Projects: notify on creation or status change
create or replace function demo.trg_projects_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type       text;
    v_title      text;
    v_body       text;
begin
    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('demo', 'projects') || array[new.user_id],
        null
    );

    if tg_op = 'INSERT' then
        v_type  := 'demo_project_created';
        v_title := 'New project';
        v_body  := 'Project "' || new.name || '" was created.';
    elsif new.status is distinct from old.status then
        v_type  := 'demo_project_status_changed';
        v_title := 'Project status updated';
        v_body  := 'Project "' || new.name || '" is now ' || new.status::text || '.';
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object('project_id', new.id, 'status', new.status, 'client_id', new.client_id),
        '/demo/resource/projects/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists projects_notify on demo.projects;

create trigger projects_notify
after insert or update of status on demo.projects for each row
execute function demo.trg_projects_notify ();

-- Tasks: notify assignee on assignment and on status change
create or replace function demo.trg_tasks_notify () returns trigger as $$
declare
    v_recipients      uuid[];
    v_assignee_user   uuid;
    v_type            text;
    v_title           text;
    v_body            text;
begin
    if new.assignee_id is not null then
        select user_id into v_assignee_user from demo.team_members where id = new.assignee_id;
    end if;

    if tg_op = 'INSERT' then
        v_type  := 'demo_task_created';
        v_title := 'New task';
        v_body  := 'Task "' || new.title || '" was created.';
        v_recipients := array_remove(array[new.user_id, v_assignee_user], null);
    elsif new.assignee_id is distinct from old.assignee_id then
        v_type  := 'demo_task_assigned';
        v_title := 'Task assigned to you';
        v_body  := 'Task "' || new.title || '" was assigned to you.';
        v_recipients := array_remove(array[v_assignee_user], null);
    elsif new.status is distinct from old.status then
        v_type  := 'demo_task_status_changed';
        v_title := 'Task status updated';
        v_body  := 'Task "' || new.title || '" is now ' || new.status::text || '.';
        v_recipients := array_remove(array[new.user_id, v_assignee_user], null);
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'task_id',     new.id,
            'project_id',  new.project_id,
            'assignee_id', new.assignee_id,
            'status',      new.status
        ),
        '/demo/resource/tasks/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists tasks_notify on demo.tasks;

create trigger tasks_notify
after insert or update of assignee_id,
status on demo.tasks for each row
execute function demo.trg_tasks_notify ();

-- Invoices: notify on creation and when status flips to sent/overdue/paid
create or replace function demo.trg_invoices_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type       text;
    v_title      text;
    v_body       text;
begin
    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('demo', 'invoices') || array[new.user_id],
        null
    );

    if tg_op = 'INSERT' then
        v_type  := 'demo_invoice_created';
        v_title := 'New invoice';
        v_body  := 'Invoice ' || new.invoice_number || ' was created.';
    elsif new.status is distinct from old.status then
        v_type  := 'demo_invoice_status_changed';
        v_title := 'Invoice status updated';
        v_body  := 'Invoice ' || new.invoice_number || ' is now ' || new.status::text || '.';
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'invoice_id',   new.id,
            'client_id',    new.client_id,
            'status',       new.status,
            'total',        new.total
        ),
        '/demo/resource/invoices/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists invoices_notify on demo.invoices;

create trigger invoices_notify
after insert or update of status on demo.invoices for each row
execute function demo.trg_invoices_notify ();

-- ================================================================
-- SEED DATA
-- Uses three hardcoded users, seeded below so this file can be run
-- independently of supabase/seed.sql (on conflict do nothing, so it
-- is also safe to run after supabase/seed.sql has already created
-- these same users):
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b8  superadmin@supasheet.app (x-admin)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b1  user1@supasheet.app (user)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b4  user@supasheet.app (user)
-- ================================================================
----------------------------------------------------------------
-- Demo users
----------------------------------------------------------------
insert into
  "auth"."users" (
    "instance_id",
    "id",
    "aud",
    "role",
    "email",
    "encrypted_password",
    "email_confirmed_at",
    "invited_at",
    "confirmation_token",
    "confirmation_sent_at",
    "recovery_token",
    "recovery_sent_at",
    "email_change_token_new",
    "email_change",
    "email_change_sent_at",
    "last_sign_in_at",
    "raw_app_meta_data",
    "raw_user_meta_data",
    "is_super_admin",
    "created_at",
    "updated_at",
    "phone",
    "phone_confirmed_at",
    "phone_change",
    "phone_change_token",
    "phone_change_sent_at",
    "email_change_token_current",
    "email_change_confirm_status",
    "banned_until",
    "reauthentication_token",
    "reauthentication_sent_at",
    "is_sso_user",
    "deleted_at",
    "is_anonymous"
  )
values
  (
    '00000000-0000-0000-0000-000000000000',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    'authenticated',
    'authenticated',
    'superadmin@supasheet.app',
    '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
    '2024-04-20 08:38:00.860548+00',
    null,
    '',
    '2024-04-20 08:37:43.343769+00',
    '',
    null,
    '',
    '',
    null,
    '2024-04-20 08:38:00.93864+00',
    '{"provider": "email", "providers": ["email"], "role": "x-admin"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b8", "email": "superadmin@supasheet.app", "email_verified": false, "phone_verified": false}',
    null,
    '2024-04-20 08:37:43.3385+00',
    '2024-04-20 08:38:00.942809+00',
    null,
    null,
    '',
    '',
    null,
    '',
    0,
    null,
    '',
    null,
    false,
    null,
    false
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    'authenticated',
    'authenticated',
    'user@supasheet.app',
    '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
    '2024-04-20 08:38:00.860548+00',
    null,
    '',
    '2024-04-20 08:37:43.343769+00',
    '',
    null,
    '',
    '',
    null,
    '2024-04-20 08:38:00.93864+00',
    '{"provider": "email", "providers": ["email"], "role": "user"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b4", "email": "user@supasheet.app", "email_verified": false, "phone_verified": false}',
    null,
    '2024-04-20 08:37:43.3385+00',
    '2024-04-20 08:38:00.942809+00',
    null,
    null,
    '',
    '',
    null,
    '',
    0,
    null,
    '',
    null,
    false,
    null,
    false
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    'authenticated',
    'authenticated',
    'user1@supasheet.app',
    '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
    '2024-04-20 08:38:00.860548+00',
    null,
    '',
    '2024-04-20 08:37:43.343769+00',
    '',
    null,
    '',
    '',
    null,
    '2024-04-20 08:38:00.93864+00',
    '{"provider": "email", "providers": ["email"], "role": "user"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b1", "email": "user1@supasheet.app", "email_verified": false, "phone_verified": false}',
    null,
    '2024-04-20 08:37:43.3385+00',
    '2024-04-20 08:38:00.942809+00',
    null,
    null,
    '',
    '',
    null,
    '',
    0,
    null,
    '',
    null,
    false,
    null,
    false
  )
on conflict (id) do nothing;

insert into
  "auth"."identities" (
    "provider_id",
    "user_id",
    "identity_data",
    "provider",
    "last_sign_in_at",
    "created_at",
    "updated_at",
    "id"
  )
values
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b8", "email": "superadmin@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ab8'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b4", "email": "user@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ab1'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b1", "email": "user1@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8abd'
  )
on conflict (id) do nothing;

----------------------------------------------------------------
-- Workspace settings
----------------------------------------------------------------
insert into
  demo.workspace_settings (
    workspace_name,
    primary_color,
    default_currency,
    invoice_prefix,
    support_email,
    timezone,
    fiscal_year_start
  )
values
  (
    'Northstar Studio',
    '#6366f1',
    'USD',
    'INV',
    'billing@northstar.studio',
    'America/New_York',
    date_trunc('year', current_date)::date
  );

----------------------------------------------------------------
-- Clients
----------------------------------------------------------------
insert into
  demo.clients (
    id,
    name,
    website,
    email,
    phone,
    industry,
    status,
    address,
    city,
    country,
    tags,
    color,
    notes,
    user_id,
    created_at
  )
values
  (
    'c1a00000-0000-0000-0000-000000000001',
    'Acme Robotics',
    'https://acme-robotics.example.com',
    'hello@acme-robotics.example.com',
    '+1-415-555-0101',
    'Robotics',
    'active',
    '500 Factory Row',
    'San Jose',
    'USA',
    array['enterprise', 'priority'],
    '#f97316',
    'Long-standing client, quarterly retainer.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '220 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000002',
    'Blue Harbor Media',
    'https://blueharbor.example.com',
    'contact@blueharbor.example.com',
    '+1-212-555-0102',
    'Media & Publishing',
    'active',
    '88 Harbor Street',
    'Boston',
    'USA',
    array['media'],
    '#0ea5e9',
    'Brand refresh in progress.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '160 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000003',
    'Nimbus Health',
    'https://nimbushealth.example.com',
    'partnerships@nimbushealth.example.com',
    '+1-312-555-0103',
    'Healthcare',
    'active',
    '12 Cloud Plaza',
    'Chicago',
    'USA',
    array['healthcare', 'compliance'],
    '#22c55e',
    'HIPAA-adjacent project — see compliance notes doc.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '90 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000004',
    'Greenfield Retail',
    'https://greenfieldretail.example.com',
    'ops@greenfieldretail.example.com',
    '+1-206-555-0104',
    'Retail',
    'on_hold',
    '4 Market Square',
    'Seattle',
    'USA',
    array['retail'],
    '#eab308',
    'Paused pending their Q3 budget approval.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '130 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000005',
    'Solstice Finance',
    'https://solsticefinance.example.com',
    'hello@solsticefinance.example.com',
    '+1-646-555-0105',
    'Financial Services',
    'lead',
    null,
    'New York',
    'USA',
    array['fintech'],
    '#a855f7',
    'Inbound lead from referral, discovery call scheduled.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '12 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000006',
    'Copper Kettle Coffee Roasters',
    'https://copperkettle.example.com',
    'hello@copperkettle.example.com',
    '+1-503-555-0106',
    'Food & Beverage',
    'active',
    '21 Roast House Lane',
    'Portland',
    'USA',
    array['ecommerce', 'retainer'],
    '#b45309',
    'Runs seasonal campaigns; loves fast turnarounds.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '320 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000007',
    'Vantage Legal',
    'https://vantagelegal.example.com',
    'office@vantagelegal.example.com',
    '+1-303-555-0107',
    'Legal',
    'active',
    '900 Capitol Ave, Suite 410',
    'Denver',
    'USA',
    array['enterprise'],
    '#334155',
    'Strict review process — allow extra time for approvals.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '280 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000008',
    'Aurora Travel Co',
    'https://auroratravel.example.com',
    'team@auroratravel.example.com',
    '+354-555-0108',
    'Travel & Hospitality',
    'active',
    '3 Harborfront',
    'Reykjavik',
    'Iceland',
    array['international', 'priority'],
    '#06b6d4',
    'Booking app is their flagship investment this year.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '150 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000009',
    'Pixelforge Games',
    'https://pixelforge.example.com',
    'studio@pixelforge.example.com',
    '+1-512-555-0109',
    'Gaming',
    'active',
    '77 Arcade Blvd',
    'Austin',
    'USA',
    array['startup'],
    '#8b5cf6',
    'Indie studio gearing up for a fall title launch.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '95 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000010',
    'Meridian Logistics',
    'https://meridianlogistics.example.com',
    'info@meridianlogistics.example.com',
    '+31-10-555-0110',
    'Logistics',
    'active',
    'Havenstraat 12',
    'Rotterdam',
    'Netherlands',
    array['enterprise', 'international'],
    '#0f766e',
    'Fleet dashboard scoped after a successful pilot.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '60 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000011',
    'Juniper & Sage',
    'https://juniperandsage.example.com',
    'hi@juniperandsage.example.com',
    '+1-604-555-0111',
    'E-commerce',
    'lead',
    null,
    'Vancouver',
    'Canada',
    array['ecommerce'],
    '#16a34a',
    'Met at the spring trade show; wants a store redesign quote.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '30 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000012',
    'Halcyon Fitness',
    'https://halcyonfitness.example.com',
    'hello@halcyonfitness.example.com',
    '+1-305-555-0112',
    'Health & Fitness',
    'lead',
    '450 Ocean Drive',
    'Miami',
    'USA',
    array['mobile'],
    '#f43f5e',
    'Exploring a member app; budget conversation pending.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '21 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000013',
    'Northwind Analytics',
    'https://northwindanalytics.example.com',
    'contact@northwindanalytics.example.com',
    '+44-20-555-0113',
    'Data & Analytics',
    'lead',
    '1 Finsbury Square',
    'London',
    'United Kingdom',
    array['fintech', 'international'],
    '#2563eb',
    'Wants a rebrand ahead of their Series B announcement.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '18 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000014',
    'Terra Verde Landscaping',
    'https://terraverde.example.com',
    'office@terraverde.example.com',
    '+1-916-555-0114',
    'Landscaping',
    'lead',
    '88 Garden Way',
    'Sacramento',
    'USA',
    array['smb'],
    '#65a30d',
    'Referral from Greenfield Retail; needs a simple brochure site.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '7 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000015',
    'Cobalt Insurance',
    'https://cobaltinsurance.example.com',
    'digital@cobaltinsurance.example.com',
    '+1-860-555-0115',
    'Insurance',
    'on_hold',
    '200 Constitution Plaza',
    'Hartford',
    'USA',
    array['enterprise', 'compliance'],
    '#1d4ed8',
    'Claims redesign paused during their vendor security review.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '140 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000016',
    'Lumen Energy',
    'https://lumenenergy.example.com',
    'web@lumenenergy.example.com',
    '+1-713-555-0116',
    'Energy',
    'on_hold',
    '1200 Smith Street',
    'Houston',
    'USA',
    array['enterprise'],
    '#f59e0b',
    'Portal work paused after leadership change.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '110 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000017',
    'Papercrane Press',
    'https://papercranepress.example.com',
    'editors@papercranepress.example.com',
    '+61-3-555-0117',
    'Publishing',
    'churned',
    '5 Laneway Court',
    'Melbourne',
    'Australia',
    array['international'],
    '#9333ea',
    'Storefront delivered; moved maintenance in-house.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '420 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000018',
    'Quartz Hotels',
    'https://quartzhotels.example.com',
    'reservations@quartzhotels.example.com',
    '+971-4-555-0118',
    'Hospitality',
    'churned',
    'Marina Walk 9',
    'Dubai',
    'UAE',
    array['international'],
    '#64748b',
    'Booking widget shipped; group was acquired last winter.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '520 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000019',
    'Fairway Sports',
    'https://fairwaysports.example.com',
    'support@fairwaysports.example.com',
    '+1-816-555-0119',
    'Sporting Goods',
    'churned',
    '34 Stadium Parkway',
    'Kansas City',
    'USA',
    array['retail'],
    '#dc2626',
    'Audit completed; chose an off-the-shelf platform.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '240 days'
  ),
  (
    'c1a00000-0000-0000-0000-000000000020',
    'Brightside Daycare',
    'https://brightsidedaycare.example.com',
    'admin@brightsidedaycare.example.com',
    '+1-614-555-0120',
    'Education',
    'churned',
    '12 Sunny Lane',
    'Columbus',
    'USA',
    array['smb'],
    '#fbbf24',
    'Enrollment site cancelled mid-build due to funding.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '180 days'
  );

----------------------------------------------------------------
-- Team members (org chart: Priya -> {Jordan, Sam, Taylor, Morgan, Drew}; Jordan -> Casey; Sam -> Riley)
----------------------------------------------------------------
insert into
  demo.team_members (
    id,
    user_id,
    manager_id,
    name,
    email,
    phone,
    job_title,
    department,
    employment_status,
    hire_date,
    hourly_rate,
    color
  )
values
  (
    'ea000000-0000-0000-0000-000000000001',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    null,
    'Priya Sharma',
    'priya@northstar.studio',
    '+1-415-555-0201',
    'Studio Director',
    'operations',
    'active',
    current_date - interval '4 years',
    185.00,
    '#6366f1'
  ),
  (
    'ea000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    'ea000000-0000-0000-0000-000000000001',
    'Jordan Lee',
    'jordan@northstar.studio',
    '+1-415-555-0202',
    'Engineering Lead',
    'engineering',
    'active',
    current_date - interval '3 years',
    160.00,
    '#0ea5e9'
  ),
  (
    'ea000000-0000-0000-0000-000000000003',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    'ea000000-0000-0000-0000-000000000001',
    'Sam Rivera',
    'sam@northstar.studio',
    '+1-415-555-0203',
    'Design Lead',
    'design',
    'active',
    current_date - interval '3 years',
    155.00,
    '#f97316'
  ),
  (
    'ea000000-0000-0000-0000-000000000004',
    null,
    'ea000000-0000-0000-0000-000000000002',
    'Casey Morgan',
    'casey@northstar.studio',
    '+1-415-555-0204',
    'Senior Engineer',
    'engineering',
    'active',
    current_date - interval '2 years',
    130.00,
    '#0ea5e9'
  ),
  (
    'ea000000-0000-0000-0000-000000000005',
    null,
    'ea000000-0000-0000-0000-000000000003',
    'Riley Chen',
    'riley@northstar.studio',
    '+1-415-555-0205',
    'Product Designer',
    'design',
    'active',
    current_date - interval '18 months',
    120.00,
    '#f97316'
  ),
  (
    'ea000000-0000-0000-0000-000000000006',
    null,
    'ea000000-0000-0000-0000-000000000001',
    'Taylor Brooks',
    'taylor@northstar.studio',
    '+1-415-555-0206',
    'Marketing Manager',
    'marketing',
    'active',
    current_date - interval '2 years',
    110.00,
    '#eab308'
  ),
  (
    'ea000000-0000-0000-0000-000000000007',
    null,
    'ea000000-0000-0000-0000-000000000001',
    'Morgan Blake',
    'morgan@northstar.studio',
    '+1-415-555-0207',
    'Sales Executive',
    'sales',
    'active',
    current_date - interval '1 year',
    100.00,
    '#22c55e'
  ),
  (
    'ea000000-0000-0000-0000-000000000008',
    null,
    'ea000000-0000-0000-0000-000000000001',
    'Drew Ellis',
    'drew@northstar.studio',
    '+1-415-555-0208',
    'Support Specialist',
    'operations',
    'on_leave',
    current_date - interval '9 months',
    85.00,
    '#a855f7'
  ),
  (
    'ea000000-0000-0000-0000-000000000009',
    null,
    'ea000000-0000-0000-0000-000000000002',
    'Ava Thompson',
    'ava@northstar.studio',
    '+1-415-555-0209',
    'Frontend Engineer',
    'engineering',
    'active',
    current_date - interval '20 months',
    115.00,
    '#0ea5e9'
  ),
  (
    'ea000000-0000-0000-0000-000000000010',
    null,
    'ea000000-0000-0000-0000-000000000002',
    'Noah Kim',
    'noah@northstar.studio',
    '+1-415-555-0210',
    'Backend Engineer',
    'engineering',
    'active',
    current_date - interval '30 months',
    125.00,
    '#0ea5e9'
  ),
  (
    'ea000000-0000-0000-0000-000000000011',
    null,
    'ea000000-0000-0000-0000-000000000002',
    'Elena Petrova',
    'elena@northstar.studio',
    '+1-415-555-0211',
    'DevOps Engineer',
    'engineering',
    'active',
    current_date - interval '14 months',
    135.00,
    '#0ea5e9'
  ),
  (
    'ea000000-0000-0000-0000-000000000012',
    null,
    'ea000000-0000-0000-0000-000000000004',
    'Marcus Webb',
    'marcus@northstar.studio',
    '+1-415-555-0212',
    'QA Engineer',
    'engineering',
    'active',
    current_date - interval '10 months',
    95.00,
    '#0ea5e9'
  ),
  (
    'ea000000-0000-0000-0000-000000000013',
    null,
    'ea000000-0000-0000-0000-000000000003',
    'Ines Duarte',
    'ines@northstar.studio',
    '+1-415-555-0213',
    'Visual Designer',
    'design',
    'active',
    current_date - interval '26 months',
    105.00,
    '#f97316'
  ),
  (
    'ea000000-0000-0000-0000-000000000014',
    null,
    'ea000000-0000-0000-0000-000000000003',
    'Leo Nakamura',
    'leo@northstar.studio',
    '+1-415-555-0214',
    'UX Researcher',
    'design',
    'active',
    current_date - interval '8 months',
    115.00,
    '#f97316'
  ),
  (
    'ea000000-0000-0000-0000-000000000015',
    null,
    'ea000000-0000-0000-0000-000000000001',
    'Harper Quinn',
    'harper@northstar.studio',
    '+1-415-555-0215',
    'Product Manager',
    'product',
    'active',
    current_date - interval '3 years',
    145.00,
    '#6366f1'
  ),
  (
    'ea000000-0000-0000-0000-000000000016',
    null,
    'ea000000-0000-0000-0000-000000000015',
    'Omar Haddad',
    'omar@northstar.studio',
    '+1-415-555-0216',
    'Product Analyst',
    'product',
    'active',
    current_date - interval '7 months',
    90.00,
    '#6366f1'
  ),
  (
    'ea000000-0000-0000-0000-000000000017',
    null,
    'ea000000-0000-0000-0000-000000000006',
    'Sofia Rossi',
    'sofia@northstar.studio',
    '+1-415-555-0217',
    'Content Strategist',
    'marketing',
    'active',
    current_date - interval '16 months',
    95.00,
    '#eab308'
  ),
  (
    'ea000000-0000-0000-0000-000000000018',
    null,
    'ea000000-0000-0000-0000-000000000006',
    'Ben Carter',
    'ben@northstar.studio',
    '+1-415-555-0218',
    'SEO Specialist',
    'marketing',
    'on_leave',
    current_date - interval '13 months',
    90.00,
    '#eab308'
  ),
  (
    'ea000000-0000-0000-0000-000000000019',
    null,
    'ea000000-0000-0000-0000-000000000007',
    'Grace Osei',
    'grace@northstar.studio',
    '+1-415-555-0219',
    'Account Manager',
    'sales',
    'active',
    current_date - interval '22 months',
    100.00,
    '#22c55e'
  ),
  (
    'ea000000-0000-0000-0000-000000000020',
    null,
    'ea000000-0000-0000-0000-000000000002',
    'Felix Wagner',
    'felix@northstar.studio',
    '+1-415-555-0220',
    'Junior Engineer',
    'engineering',
    'offboarded',
    current_date - interval '2 years',
    75.00,
    '#0ea5e9'
  );

----------------------------------------------------------------
-- Team member details (1:1 — seeded for only the first five staff
-- so the UI shows both the linked form and the "add details" state)
----------------------------------------------------------------
insert into
  demo.team_member_details (
    team_member_id,
    date_of_birth,
    national_id,
    tax_id,
    address,
    emergency_contact_name,
    emergency_contact_phone,
    bank_name,
    bank_account_number
  )
values
  (
    'ea000000-0000-0000-0000-000000000001',
    '1985-03-14',
    'SSN-291-04-8821',
    'TAX-9911-2201',
    '452 Bryant St, San Francisco, CA',
    'Raj Sharma',
    '+1-415-555-0301',
    'First Republic Bank',
    '****4821'
  ),
  (
    'ea000000-0000-0000-0000-000000000002',
    '1990-07-22',
    'SSN-338-19-2201',
    'TAX-9911-2202',
    '118 Valencia St, San Francisco, CA',
    'Mia Lee',
    '+1-415-555-0302',
    'Chase Bank',
    '****7734'
  ),
  (
    'ea000000-0000-0000-0000-000000000003',
    '1992-11-05',
    'SSN-445-88-1190',
    'TAX-9911-2203',
    '77 Mission St, San Francisco, CA',
    'Diego Rivera',
    '+1-415-555-0303',
    'Bank of America',
    '****2290'
  ),
  (
    'ea000000-0000-0000-0000-000000000004',
    '1994-02-18',
    'SSN-556-23-4471',
    'TAX-9911-2204',
    '900 Folsom St, San Francisco, CA',
    'Alicia Morgan',
    '+1-415-555-0304',
    'Chase Bank',
    '****1005'
  ),
  (
    'ea000000-0000-0000-0000-000000000005',
    '1996-09-30',
    'SSN-667-77-3321',
    'TAX-9911-2205',
    '210 King St, San Francisco, CA',
    'Tommy Chen',
    '+1-415-555-0305',
    'Wells Fargo',
    '****6620'
  );

----------------------------------------------------------------
-- Projects
----------------------------------------------------------------
insert into
  demo.projects (
    id,
    name,
    client_id,
    owner_id,
    description,
    status,
    priority,
    budget,
    start_date,
    due_date,
    progress,
    tags,
    color,
    user_id,
    created_at
  )
values
  (
    'ec000000-0000-0000-0000-000000000001',
    'Acme Robotics — Website Relaunch',
    'c1a00000-0000-0000-0000-000000000001',
    'ea000000-0000-0000-0000-000000000002',
    'Full marketing site rebuild with a new product configurator.',
    'active',
    'high',
    48000.00,
    current_date - interval '45 days',
    current_date + interval '20 days',
    62,
    array['web', 'marketing'],
    '#f97316',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '46 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000002',
    'Blue Harbor — Brand Refresh',
    'c1a00000-0000-0000-0000-000000000002',
    'ea000000-0000-0000-0000-000000000003',
    'New visual identity, logo system, and editorial style guide.',
    'active',
    'medium',
    26000.00,
    current_date - interval '30 days',
    current_date + interval '35 days',
    40,
    array['branding'],
    '#0ea5e9',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '31 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000003',
    'Nimbus Health — Patient Portal',
    'c1a00000-0000-0000-0000-000000000003',
    'ea000000-0000-0000-0000-000000000002',
    'Secure patient-facing portal for appointments and records.',
    'planning',
    'critical',
    120000.00,
    current_date + interval '10 days',
    current_date + interval '150 days',
    5,
    array['healthcare', 'web-app'],
    '#22c55e',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '8 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000004',
    'Greenfield Retail — POS Rollout',
    'c1a00000-0000-0000-0000-000000000004',
    'ea000000-0000-0000-0000-000000000004',
    'In-store point-of-sale system rollout across 12 locations.',
    'on_hold',
    'medium',
    75000.00,
    current_date - interval '60 days',
    current_date + interval '90 days',
    25,
    array['retail', 'pos'],
    '#eab308',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '61 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000005',
    'Internal — Studio Ops Dashboard',
    null,
    'ea000000-0000-0000-0000-000000000001',
    'Internal tooling to track studio capacity and billing.',
    'completed',
    'low',
    8000.00,
    current_date - interval '120 days',
    current_date - interval '20 days',
    100,
    array['internal', 'tooling'],
    '#6366f1',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '121 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000006',
    'Copper Kettle — E-commerce Store',
    'c1a00000-0000-0000-0000-000000000006',
    'ea000000-0000-0000-0000-000000000009',
    'New online store with subscriptions and wholesale ordering.',
    'active',
    'high',
    32000.00,
    current_date - interval '40 days',
    current_date + interval '30 days',
    55,
    array['ecommerce', 'web'],
    '#b45309',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '41 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000007',
    'Vantage Legal — Client Portal',
    'c1a00000-0000-0000-0000-000000000007',
    'ea000000-0000-0000-0000-000000000004',
    'Secure portal for case status, documents, and billing.',
    'active',
    'medium',
    54000.00,
    current_date - interval '25 days',
    current_date + interval '60 days',
    30,
    array['web-app', 'portal'],
    '#334155',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '26 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000008',
    'Aurora Travel — Booking App',
    'c1a00000-0000-0000-0000-000000000008',
    'ea000000-0000-0000-0000-000000000002',
    'Cross-platform mobile app for tours and flight add-ons.',
    'active',
    'critical',
    95000.00,
    current_date - interval '70 days',
    current_date + interval '45 days',
    48,
    array['mobile', 'booking'],
    '#06b6d4',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '71 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000009',
    'Pixelforge — Launch Marketing Site',
    'c1a00000-0000-0000-0000-000000000009',
    'ea000000-0000-0000-0000-000000000009',
    'Teaser site and press kit for the fall title launch.',
    'active',
    'medium',
    21000.00,
    current_date - interval '15 days',
    current_date + interval '40 days',
    20,
    array['web', 'marketing'],
    '#8b5cf6',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '16 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000010',
    'Meridian — Fleet Tracking Dashboard',
    'c1a00000-0000-0000-0000-000000000010',
    'ea000000-0000-0000-0000-000000000010',
    'Real-time fleet map, alerts, and delivery analytics.',
    'planning',
    'high',
    88000.00,
    current_date + interval '5 days',
    current_date + interval '120 days',
    0,
    array['dashboard', 'analytics'],
    '#0f766e',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '9 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000011',
    'Northwind — Analytics Rebrand',
    'c1a00000-0000-0000-0000-000000000013',
    'ea000000-0000-0000-0000-000000000003',
    'Full rebrand ahead of the Series B announcement.',
    'planning',
    'medium',
    18000.00,
    current_date + interval '14 days',
    current_date + interval '75 days',
    0,
    array['branding'],
    '#2563eb',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '6 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000012',
    'Halcyon — Member App Discovery',
    'c1a00000-0000-0000-0000-000000000012',
    'ea000000-0000-0000-0000-000000000015',
    'Discovery sprint to scope a member-facing fitness app.',
    'planning',
    'low',
    12000.00,
    current_date + interval '20 days',
    current_date + interval '90 days',
    0,
    array['mobile', 'discovery'],
    '#f43f5e',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '4 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000013',
    'Cobalt — Claims Intake Redesign',
    'c1a00000-0000-0000-0000-000000000015',
    'ea000000-0000-0000-0000-000000000005',
    'Redesign of the claims intake flow for policyholders.',
    'on_hold',
    'medium',
    46000.00,
    current_date - interval '50 days',
    current_date + interval '80 days',
    15,
    array['ux', 'insurance'],
    '#1d4ed8',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '51 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000014',
    'Copper Kettle — Loyalty Program',
    'c1a00000-0000-0000-0000-000000000006',
    'ea000000-0000-0000-0000-000000000015',
    'Points and rewards program integrated with the store.',
    'completed',
    'medium',
    24000.00,
    current_date - interval '150 days',
    current_date - interval '60 days',
    100,
    array['ecommerce', 'loyalty'],
    '#b45309',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '151 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000015',
    'Vantage Legal — Brand Identity',
    'c1a00000-0000-0000-0000-000000000007',
    'ea000000-0000-0000-0000-000000000003',
    'Conservative-but-modern identity for the firm.',
    'completed',
    'low',
    15000.00,
    current_date - interval '200 days',
    current_date - interval '140 days',
    100,
    array['branding'],
    '#334155',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '201 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000016',
    'Quartz Hotels — Booking Widget',
    'c1a00000-0000-0000-0000-000000000018',
    'ea000000-0000-0000-0000-000000000004',
    'Embeddable room-booking widget for the hotel group sites.',
    'completed',
    'high',
    38000.00,
    current_date - interval '260 days',
    current_date - interval '170 days',
    100,
    array['web', 'booking'],
    '#64748b',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '261 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000017',
    'Papercrane — Digital Storefront',
    'c1a00000-0000-0000-0000-000000000017',
    'ea000000-0000-0000-0000-000000000002',
    'Direct-to-reader storefront with print-on-demand fulfilment.',
    'completed',
    'medium',
    42000.00,
    current_date - interval '320 days',
    current_date - interval '210 days',
    100,
    array['ecommerce'],
    '#9333ea',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '321 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000018',
    'Fairway Sports — Commerce Audit',
    'c1a00000-0000-0000-0000-000000000019',
    'ea000000-0000-0000-0000-000000000016',
    'Conversion and platform audit of the existing online store.',
    'completed',
    'low',
    9000.00,
    current_date - interval '120 days',
    current_date - interval '90 days',
    100,
    array['audit', 'ecommerce'],
    '#dc2626',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '121 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000019',
    'Lumen Energy — Customer Portal',
    'c1a00000-0000-0000-0000-000000000016',
    'ea000000-0000-0000-0000-000000000010',
    'Self-service billing and usage portal for customers.',
    'cancelled',
    'medium',
    60000.00,
    current_date - interval '100 days',
    current_date - interval '30 days',
    10,
    array['portal'],
    '#f59e0b',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '101 days'
  ),
  (
    'ec000000-0000-0000-0000-000000000020',
    'Brightside — Enrollment Site',
    'c1a00000-0000-0000-0000-000000000020',
    'ea000000-0000-0000-0000-000000000013',
    'Parent-facing enrollment and waitlist site.',
    'cancelled',
    'low',
    14000.00,
    current_date - interval '90 days',
    current_date - interval '45 days',
    5,
    array['web'],
    '#fbbf24',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '91 days'
  );

----------------------------------------------------------------
-- Project members
----------------------------------------------------------------
insert into
  demo.project_members (
    project_id,
    team_member_id,
    role_on_project,
    allocation_percent
  )
values
  (
    'ec000000-0000-0000-0000-000000000001',
    'ea000000-0000-0000-0000-000000000002',
    'Tech Lead',
    50
  ),
  (
    'ec000000-0000-0000-0000-000000000001',
    'ea000000-0000-0000-0000-000000000004',
    'Engineer',
    80
  ),
  (
    'ec000000-0000-0000-0000-000000000001',
    'ea000000-0000-0000-0000-000000000005',
    'Designer',
    30
  ),
  (
    'ec000000-0000-0000-0000-000000000002',
    'ea000000-0000-0000-0000-000000000003',
    'Design Lead',
    60
  ),
  (
    'ec000000-0000-0000-0000-000000000002',
    'ea000000-0000-0000-0000-000000000005',
    'Designer',
    40
  ),
  (
    'ec000000-0000-0000-0000-000000000002',
    'ea000000-0000-0000-0000-000000000006',
    'Marketing',
    20
  ),
  (
    'ec000000-0000-0000-0000-000000000003',
    'ea000000-0000-0000-0000-000000000002',
    'Tech Lead',
    40
  ),
  (
    'ec000000-0000-0000-0000-000000000003',
    'ea000000-0000-0000-0000-000000000004',
    'Engineer',
    50
  ),
  (
    'ec000000-0000-0000-0000-000000000004',
    'ea000000-0000-0000-0000-000000000004',
    'Engineer',
    30
  ),
  (
    'ec000000-0000-0000-0000-000000000005',
    'ea000000-0000-0000-0000-000000000001',
    'Sponsor',
    10
  ),
  (
    'ec000000-0000-0000-0000-000000000005',
    'ea000000-0000-0000-0000-000000000008',
    'Coordinator',
    20
  ),
  (
    'ec000000-0000-0000-0000-000000000006',
    'ea000000-0000-0000-0000-000000000009',
    'Frontend Engineer',
    60
  ),
  (
    'ec000000-0000-0000-0000-000000000006',
    'ea000000-0000-0000-0000-000000000013',
    'Designer',
    40
  ),
  (
    'ec000000-0000-0000-0000-000000000006',
    'ea000000-0000-0000-0000-000000000019',
    'Account Manager',
    10
  ),
  (
    'ec000000-0000-0000-0000-000000000007',
    'ea000000-0000-0000-0000-000000000004',
    'Tech Lead',
    50
  ),
  (
    'ec000000-0000-0000-0000-000000000007',
    'ea000000-0000-0000-0000-000000000010',
    'Backend Engineer',
    60
  ),
  (
    'ec000000-0000-0000-0000-000000000007',
    'ea000000-0000-0000-0000-000000000014',
    'UX Researcher',
    20
  ),
  (
    'ec000000-0000-0000-0000-000000000008',
    'ea000000-0000-0000-0000-000000000002',
    'Tech Lead',
    30
  ),
  (
    'ec000000-0000-0000-0000-000000000008',
    'ea000000-0000-0000-0000-000000000009',
    'Frontend Engineer',
    50
  ),
  (
    'ec000000-0000-0000-0000-000000000008',
    'ea000000-0000-0000-0000-000000000011',
    'DevOps Engineer',
    30
  ),
  (
    'ec000000-0000-0000-0000-000000000009',
    'ea000000-0000-0000-0000-000000000009',
    'Engineer',
    40
  ),
  (
    'ec000000-0000-0000-0000-000000000009',
    'ea000000-0000-0000-0000-000000000017',
    'Content Strategist',
    30
  ),
  (
    'ec000000-0000-0000-0000-000000000010',
    'ea000000-0000-0000-0000-000000000010',
    'Backend Lead',
    50
  ),
  (
    'ec000000-0000-0000-0000-000000000010',
    'ea000000-0000-0000-0000-000000000011',
    'DevOps Engineer',
    40
  ),
  (
    'ec000000-0000-0000-0000-000000000010',
    'ea000000-0000-0000-0000-000000000016',
    'Product Analyst',
    30
  ),
  (
    'ec000000-0000-0000-0000-000000000011',
    'ea000000-0000-0000-0000-000000000003',
    'Design Lead',
    40
  ),
  (
    'ec000000-0000-0000-0000-000000000011',
    'ea000000-0000-0000-0000-000000000013',
    'Designer',
    50
  ),
  (
    'ec000000-0000-0000-0000-000000000012',
    'ea000000-0000-0000-0000-000000000015',
    'Product Lead',
    30
  ),
  (
    'ec000000-0000-0000-0000-000000000012',
    'ea000000-0000-0000-0000-000000000014',
    'UX Researcher',
    40
  ),
  (
    'ec000000-0000-0000-0000-000000000013',
    'ea000000-0000-0000-0000-000000000005',
    'Designer',
    40
  ),
  (
    'ec000000-0000-0000-0000-000000000013',
    'ea000000-0000-0000-0000-000000000012',
    'QA Engineer',
    20
  ),
  (
    'ec000000-0000-0000-0000-000000000014',
    'ea000000-0000-0000-0000-000000000015',
    'Product Lead',
    40
  ),
  (
    'ec000000-0000-0000-0000-000000000014',
    'ea000000-0000-0000-0000-000000000009',
    'Engineer',
    50
  ),
  (
    'ec000000-0000-0000-0000-000000000015',
    'ea000000-0000-0000-0000-000000000003',
    'Design Lead',
    50
  ),
  (
    'ec000000-0000-0000-0000-000000000015',
    'ea000000-0000-0000-0000-000000000013',
    'Designer',
    60
  ),
  (
    'ec000000-0000-0000-0000-000000000016',
    'ea000000-0000-0000-0000-000000000004',
    'Tech Lead',
    60
  ),
  (
    'ec000000-0000-0000-0000-000000000016',
    'ea000000-0000-0000-0000-000000000012',
    'QA Engineer',
    30
  ),
  (
    'ec000000-0000-0000-0000-000000000017',
    'ea000000-0000-0000-0000-000000000002',
    'Tech Lead',
    40
  ),
  (
    'ec000000-0000-0000-0000-000000000017',
    'ea000000-0000-0000-0000-000000000010',
    'Backend Engineer',
    70
  ),
  (
    'ec000000-0000-0000-0000-000000000017',
    'ea000000-0000-0000-0000-000000000013',
    'Designer',
    30
  ),
  (
    'ec000000-0000-0000-0000-000000000018',
    'ea000000-0000-0000-0000-000000000016',
    'Analyst',
    60
  ),
  (
    'ec000000-0000-0000-0000-000000000018',
    'ea000000-0000-0000-0000-000000000019',
    'Account Manager',
    20
  ),
  (
    'ec000000-0000-0000-0000-000000000019',
    'ea000000-0000-0000-0000-000000000010',
    'Backend Engineer',
    30
  ),
  (
    'ec000000-0000-0000-0000-000000000019',
    'ea000000-0000-0000-0000-000000000011',
    'DevOps Engineer',
    20
  ),
  (
    'ec000000-0000-0000-0000-000000000020',
    'ea000000-0000-0000-0000-000000000013',
    'Designer',
    40
  ),
  (
    'ec000000-0000-0000-0000-000000000020',
    'ea000000-0000-0000-0000-000000000009',
    'Engineer',
    30
  );

----------------------------------------------------------------
-- Milestones
----------------------------------------------------------------
insert into
  demo.milestones (
    id,
    project_id,
    title,
    description,
    due_date,
    status,
    sort_order
  )
values
  (
    '5e000000-0000-0000-0000-000000000001',
    'ec000000-0000-0000-0000-000000000001',
    'Discovery & IA',
    'Stakeholder interviews, sitemap, content audit.',
    current_date - interval '25 days',
    'completed',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000002',
    'ec000000-0000-0000-0000-000000000001',
    'Design Handoff',
    'Final designs approved and handed to engineering.',
    current_date - interval '2 days',
    'completed',
    2
  ),
  (
    '5e000000-0000-0000-0000-000000000003',
    'ec000000-0000-0000-0000-000000000001',
    'Launch',
    'Production deploy and DNS cutover.',
    current_date + interval '20 days',
    'pending',
    3
  ),
  (
    '5e000000-0000-0000-0000-000000000004',
    'ec000000-0000-0000-0000-000000000002',
    'Logo Concepts',
    'Three logo directions presented to client.',
    current_date - interval '5 days',
    'completed',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000005',
    'ec000000-0000-0000-0000-000000000002',
    'Style Guide',
    'Full brand guidelines document delivered.',
    current_date + interval '15 days',
    'in_progress',
    2
  ),
  (
    '5e000000-0000-0000-0000-000000000006',
    'ec000000-0000-0000-0000-000000000003',
    'Requirements Sign-off',
    'Scope, compliance requirements, and success metrics agreed.',
    current_date + interval '15 days',
    'pending',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000007',
    'ec000000-0000-0000-0000-000000000003',
    'Architecture Approved',
    'Technical architecture reviewed with client security team.',
    current_date + interval '40 days',
    'pending',
    2
  ),
  (
    '5e000000-0000-0000-0000-000000000008',
    'ec000000-0000-0000-0000-000000000003',
    'Private Beta',
    'Portal live for a pilot group of patients.',
    current_date + interval '100 days',
    'pending',
    3
  ),
  (
    '5e000000-0000-0000-0000-000000000009',
    'ec000000-0000-0000-0000-000000000006',
    'Catalog Import',
    'All products, variants, and imagery migrated.',
    current_date - interval '20 days',
    'completed',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000010',
    'ec000000-0000-0000-0000-000000000006',
    'Checkout Flow',
    'Cart, payment, and subscription checkout complete.',
    current_date + interval '5 days',
    'in_progress',
    2
  ),
  (
    '5e000000-0000-0000-0000-000000000011',
    'ec000000-0000-0000-0000-000000000006',
    'Store Launch',
    'Public launch with the fall seasonal campaign.',
    current_date + interval '30 days',
    'pending',
    3
  ),
  (
    '5e000000-0000-0000-0000-000000000012',
    'ec000000-0000-0000-0000-000000000007',
    'Requirements Workshop',
    'Partners aligned on portal scope and phasing.',
    current_date - interval '10 days',
    'completed',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000013',
    'ec000000-0000-0000-0000-000000000007',
    'Portal MVP',
    'Case status and document sharing usable end to end.',
    current_date + interval '25 days',
    'in_progress',
    2
  ),
  (
    '5e000000-0000-0000-0000-000000000014',
    'ec000000-0000-0000-0000-000000000008',
    'Booking Engine Integration',
    'Availability and pricing feeds wired into the app.',
    current_date - interval '15 days',
    'completed',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000015',
    'ec000000-0000-0000-0000-000000000008',
    'Beta Release',
    'TestFlight / Play beta for the travel-agent group.',
    current_date + interval '10 days',
    'in_progress',
    2
  ),
  (
    '5e000000-0000-0000-0000-000000000016',
    'ec000000-0000-0000-0000-000000000008',
    'App Store Launch',
    'Public release in both stores.',
    current_date + interval '45 days',
    'pending',
    3
  ),
  (
    '5e000000-0000-0000-0000-000000000017',
    'ec000000-0000-0000-0000-000000000009',
    'Content Freeze',
    'All launch copy and press assets finalized.',
    current_date + interval '15 days',
    'pending',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000018',
    'ec000000-0000-0000-0000-000000000010',
    'Pilot Requirements',
    'Fleet pilot learnings turned into a scoped backlog.',
    current_date + interval '20 days',
    'pending',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000019',
    'ec000000-0000-0000-0000-000000000013',
    'Wireframes Review',
    'Intake wireframes reviewed with claims leadership.',
    current_date - interval '30 days',
    'missed',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000020',
    'ec000000-0000-0000-0000-000000000014',
    'Program Launch',
    'Loyalty program live for all store customers.',
    current_date - interval '60 days',
    'completed',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000021',
    'ec000000-0000-0000-0000-000000000015',
    'Identity Delivered',
    'Logo system, palette, and templates handed off.',
    current_date - interval '140 days',
    'completed',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000022',
    'ec000000-0000-0000-0000-000000000016',
    'Widget Live',
    'Booking widget embedded across all hotel sites.',
    current_date - interval '170 days',
    'completed',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000023',
    'ec000000-0000-0000-0000-000000000017',
    'Storefront Launch',
    'Direct-to-reader store open with full backlist.',
    current_date - interval '210 days',
    'completed',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000024',
    'ec000000-0000-0000-0000-000000000019',
    'Discovery Complete',
    'Portal discovery — project cancelled before build.',
    current_date - interval '45 days',
    'missed',
    1
  ),
  (
    '5e000000-0000-0000-0000-000000000025',
    'ec000000-0000-0000-0000-000000000002',
    'Rollout Assets',
    'Stationery, social kits, and template rollout.',
    current_date + interval '30 days',
    'pending',
    3
  );

----------------------------------------------------------------
-- Tasks (includes subtasks via parent_task_id for the tree view)
----------------------------------------------------------------
insert into
  demo.tasks (
    id,
    project_id,
    milestone_id,
    parent_task_id,
    assignee_id,
    title,
    description,
    status,
    priority,
    blocked_reason,
    estimated_hours,
    due_date,
    completed_at,
    tags,
    user_id,
    created_at
  )
values
  -- Acme Robotics — Website Relaunch
  (
    'a5000000-0000-0000-0000-000000000001',
    'ec000000-0000-0000-0000-000000000001',
    '5e000000-0000-0000-0000-000000000002',
    null,
    'ea000000-0000-0000-0000-000000000004',
    'Build product configurator',
    'Interactive 3D configurator for the robotics product line.',
    'in_progress',
    'high',
    null,
    40,
    current_date + interval '5 days',
    null,
    array['frontend'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '20 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000002',
    'ec000000-0000-0000-0000-000000000001',
    '5e000000-0000-0000-0000-000000000002',
    'a5000000-0000-0000-0000-000000000001',
    'ea000000-0000-0000-0000-000000000004',
    'Configurator: color + material step',
    'Sub-step of the configurator build.',
    'done',
    'medium',
    null,
    10,
    current_date - interval '3 days',
    current_timestamp - interval '3 days',
    array['frontend'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '18 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000003',
    'ec000000-0000-0000-0000-000000000001',
    '5e000000-0000-0000-0000-000000000002',
    'a5000000-0000-0000-0000-000000000001',
    'ea000000-0000-0000-0000-000000000004',
    'Configurator: pricing summary step',
    'Sub-step of the configurator build.',
    'in_progress',
    'medium',
    null,
    12,
    current_date + interval '4 days',
    null,
    array['frontend'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '17 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000004',
    'ec000000-0000-0000-0000-000000000001',
    '5e000000-0000-0000-0000-000000000003',
    null,
    'ea000000-0000-0000-0000-000000000002',
    'Set up production hosting',
    'Provision hosting and CI/CD for launch.',
    'blocked',
    'high',
    'Waiting on client to approve hosting vendor.',
    8,
    current_date + interval '10 days',
    null,
    array['devops'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '10 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000005',
    'ec000000-0000-0000-0000-000000000001',
    null,
    null,
    'ea000000-0000-0000-0000-000000000005',
    'Accessibility audit',
    'WCAG 2.1 AA pass on the new templates.',
    'todo',
    'medium',
    null,
    6,
    current_date + interval '18 days',
    null,
    array['a11y'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '5 days'
  ),
  -- Blue Harbor — Brand Refresh
  (
    'a5000000-0000-0000-0000-000000000006',
    'ec000000-0000-0000-0000-000000000002',
    '5e000000-0000-0000-0000-000000000004',
    null,
    'ea000000-0000-0000-0000-000000000005',
    'Design logo concept variations',
    'Three distinct directions for client review.',
    'done',
    'high',
    null,
    16,
    current_date - interval '6 days',
    current_timestamp - interval '5 days',
    array['branding'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '25 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000007',
    'ec000000-0000-0000-0000-000000000002',
    '5e000000-0000-0000-0000-000000000005',
    null,
    'ea000000-0000-0000-0000-000000000003',
    'Draft brand style guide',
    'Typography, color system, usage rules.',
    'in_review',
    'medium',
    null,
    20,
    current_date + interval '8 days',
    null,
    array['branding'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '12 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000008',
    'ec000000-0000-0000-0000-000000000002',
    '5e000000-0000-0000-0000-000000000005',
    null,
    'ea000000-0000-0000-0000-000000000006',
    'Plan launch announcement',
    'Coordinate press release and social rollout.',
    'todo',
    'low',
    null,
    5,
    current_date + interval '18 days',
    null,
    array['marketing'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '4 days'
  ),
  -- Nimbus Health — Patient Portal
  (
    'a5000000-0000-0000-0000-000000000009',
    'ec000000-0000-0000-0000-000000000003',
    '5e000000-0000-0000-0000-000000000006',
    null,
    'ea000000-0000-0000-0000-000000000002',
    'Compliance requirements workshop',
    'Confirm HIPAA-adjacent requirements with client legal.',
    'in_progress',
    'critical',
    null,
    12,
    current_date + interval '7 days',
    null,
    array['compliance'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '6 days'
  ),
  (
    'a5000000-0000-0000-0000-00000000000a',
    'ec000000-0000-0000-0000-000000000003',
    '5e000000-0000-0000-0000-000000000006',
    null,
    'ea000000-0000-0000-0000-000000000004',
    'Draft technical architecture',
    'Data model, auth strategy, hosting region.',
    'todo',
    'high',
    null,
    18,
    current_date + interval '12 days',
    null,
    array['architecture'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '3 days'
  ),
  -- Greenfield Retail — POS Rollout (on hold project)
  (
    'a5000000-0000-0000-0000-00000000000b',
    'ec000000-0000-0000-0000-000000000004',
    null,
    null,
    'ea000000-0000-0000-0000-000000000004',
    'Pilot store hardware install',
    'Install and test terminals at the pilot location.',
    'blocked',
    'medium',
    'Project on hold pending client budget approval.',
    24,
    current_date + interval '30 days',
    null,
    array['hardware'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '55 days'
  ),
  (
    'a5000000-0000-0000-0000-00000000000c',
    'ec000000-0000-0000-0000-000000000004',
    null,
    null,
    'ea000000-0000-0000-0000-000000000004',
    'Inventory sync integration',
    'Connect POS to existing inventory system.',
    'cancelled',
    'low',
    null,
    30,
    null,
    null,
    array['integration'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '50 days'
  ),
  -- Internal — Studio Ops Dashboard (completed project)
  (
    'a5000000-0000-0000-0000-00000000000d',
    'ec000000-0000-0000-0000-000000000005',
    null,
    null,
    'ea000000-0000-0000-0000-000000000008',
    'Ship capacity planning view',
    'Team allocation vs. logged hours dashboard.',
    'done',
    'medium',
    null,
    14,
    current_date - interval '25 days',
    current_timestamp - interval '22 days',
    array['internal'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '110 days'
  ),
  (
    'a5000000-0000-0000-0000-00000000000e',
    'ec000000-0000-0000-0000-000000000005',
    null,
    null,
    'ea000000-0000-0000-0000-000000000001',
    'Wire up billing export',
    'Monthly CSV export of paid invoices for accounting.',
    'done',
    'low',
    null,
    6,
    current_date - interval '21 days',
    current_timestamp - interval '20 days',
    array['internal'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '100 days'
  ),
  -- Copper Kettle — E-commerce Store
  (
    'a5000000-0000-0000-0000-00000000000f',
    'ec000000-0000-0000-0000-000000000006',
    '5e000000-0000-0000-0000-000000000010',
    null,
    'ea000000-0000-0000-0000-000000000009',
    'Build checkout flow',
    'Cart, one-time purchase, and subscription checkout.',
    'in_progress',
    'high',
    null,
    24,
    current_date + interval '4 days',
    null,
    array['frontend', 'ecommerce'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '14 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000010',
    'ec000000-0000-0000-0000-000000000006',
    '5e000000-0000-0000-0000-000000000010',
    'a5000000-0000-0000-0000-00000000000f',
    'ea000000-0000-0000-0000-000000000009',
    'Integrate payment provider',
    'Sub-step of the checkout build.',
    'in_progress',
    'high',
    null,
    10,
    current_date + interval '3 days',
    null,
    array['payments'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '12 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000011',
    'ec000000-0000-0000-0000-000000000006',
    '5e000000-0000-0000-0000-000000000010',
    'a5000000-0000-0000-0000-00000000000f',
    'ea000000-0000-0000-0000-000000000012',
    'Checkout QA test pass',
    'Sub-step of the checkout build.',
    'todo',
    'medium',
    null,
    8,
    current_date + interval '6 days',
    null,
    array['qa'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '10 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000012',
    'ec000000-0000-0000-0000-000000000006',
    '5e000000-0000-0000-0000-000000000009',
    null,
    'ea000000-0000-0000-0000-000000000010',
    'Import product catalog',
    'Migrate products, variants, and imagery from the old store.',
    'done',
    'medium',
    null,
    12,
    current_date - interval '22 days',
    current_timestamp - interval '21 days',
    array['data'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '35 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000013',
    'ec000000-0000-0000-0000-000000000006',
    '5e000000-0000-0000-0000-000000000011',
    null,
    'ea000000-0000-0000-0000-000000000017',
    'Write launch announcement',
    'Email and social copy for the store launch.',
    'todo',
    'low',
    null,
    4,
    current_date + interval '25 days',
    null,
    array['marketing'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '5 days'
  ),
  -- Vantage Legal — Client Portal
  (
    'a5000000-0000-0000-0000-000000000014',
    'ec000000-0000-0000-0000-000000000007',
    '5e000000-0000-0000-0000-000000000013',
    null,
    'ea000000-0000-0000-0000-000000000010',
    'Model case data schema',
    'Cases, parties, matters, and billing entities.',
    'in_progress',
    'high',
    null,
    16,
    current_date + interval '7 days',
    null,
    array['backend'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '15 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000015',
    'ec000000-0000-0000-0000-000000000007',
    '5e000000-0000-0000-0000-000000000013',
    null,
    'ea000000-0000-0000-0000-000000000004',
    'Set up document upload service',
    'Secure upload with virus scanning and retention rules.',
    'in_review',
    'medium',
    null,
    12,
    current_date + interval '5 days',
    null,
    array['backend', 'security'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '11 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000016',
    'ec000000-0000-0000-0000-000000000007',
    '5e000000-0000-0000-0000-000000000013',
    null,
    'ea000000-0000-0000-0000-000000000014',
    'Usability test intake flow',
    'Five moderated sessions with client-side paralegals.',
    'todo',
    'medium',
    null,
    8,
    current_date + interval '18 days',
    null,
    array['research'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '8 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000017',
    'ec000000-0000-0000-0000-000000000007',
    '5e000000-0000-0000-0000-000000000012',
    null,
    'ea000000-0000-0000-0000-000000000014',
    'Interview paralegal team',
    'Understand current intake and document workflows.',
    'done',
    'medium',
    null,
    6,
    current_date - interval '12 days',
    current_timestamp - interval '11 days',
    array['research'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '22 days'
  ),
  -- Aurora Travel — Booking App
  (
    'a5000000-0000-0000-0000-000000000018',
    'ec000000-0000-0000-0000-000000000008',
    '5e000000-0000-0000-0000-000000000015',
    null,
    'ea000000-0000-0000-0000-000000000009',
    'Build seat selection screen',
    'Interactive seat map with real-time availability.',
    'in_progress',
    'critical',
    null,
    20,
    current_date + interval '6 days',
    null,
    array['mobile', 'frontend'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '13 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000019',
    'ec000000-0000-0000-0000-000000000008',
    '5e000000-0000-0000-0000-000000000015',
    null,
    'ea000000-0000-0000-0000-000000000011',
    'Load test booking API',
    'Simulate peak-season booking traffic.',
    'blocked',
    'high',
    'Waiting on staging environment capacity increase.',
    10,
    current_date + interval '9 days',
    null,
    array['devops'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '10 days'
  ),
  (
    'a5000000-0000-0000-0000-00000000001a',
    'ec000000-0000-0000-0000-000000000008',
    '5e000000-0000-0000-0000-000000000014',
    null,
    'ea000000-0000-0000-0000-000000000010',
    'Integrate flight availability feed',
    'Normalize the partner airline availability feed.',
    'done',
    'critical',
    null,
    30,
    current_date - interval '16 days',
    current_timestamp - interval '15 days',
    array['backend', 'integration'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '45 days'
  ),
  (
    'a5000000-0000-0000-0000-00000000001b',
    'ec000000-0000-0000-0000-000000000008',
    '5e000000-0000-0000-0000-000000000016',
    null,
    'ea000000-0000-0000-0000-000000000017',
    'Draft app store listing copy',
    'Store descriptions, keywords, and screenshots plan.',
    'todo',
    'low',
    null,
    4,
    current_date + interval '35 days',
    null,
    array['marketing'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '3 days'
  ),
  -- Pixelforge — Launch Marketing Site
  (
    'a5000000-0000-0000-0000-00000000001c',
    'ec000000-0000-0000-0000-000000000009',
    '5e000000-0000-0000-0000-000000000017',
    null,
    'ea000000-0000-0000-0000-000000000013',
    'Design press kit page',
    'Downloadable art, logos, and fact sheet layout.',
    'in_progress',
    'medium',
    null,
    10,
    current_date + interval '8 days',
    null,
    array['design'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '9 days'
  ),
  (
    'a5000000-0000-0000-0000-00000000001d',
    'ec000000-0000-0000-0000-000000000009',
    '5e000000-0000-0000-0000-000000000017',
    null,
    'ea000000-0000-0000-0000-000000000017',
    'Write studio story page',
    'Founding story and team profiles for the site.',
    'todo',
    'medium',
    null,
    6,
    current_date + interval '12 days',
    null,
    array['content'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '6 days'
  ),
  -- Meridian — Fleet Tracking Dashboard
  (
    'a5000000-0000-0000-0000-00000000001e',
    'ec000000-0000-0000-0000-000000000010',
    '5e000000-0000-0000-0000-000000000018',
    null,
    'ea000000-0000-0000-0000-000000000016',
    'Compile pilot feedback report',
    'Synthesize dispatcher interviews from the pilot.',
    'in_progress',
    'high',
    null,
    12,
    current_date + interval '10 days',
    null,
    array['research'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '7 days'
  ),
  (
    'a5000000-0000-0000-0000-00000000001f',
    'ec000000-0000-0000-0000-000000000010',
    '5e000000-0000-0000-0000-000000000018',
    null,
    'ea000000-0000-0000-0000-000000000010',
    'Evaluate mapping providers',
    'Cost and latency comparison for live fleet maps.',
    'todo',
    'medium',
    null,
    8,
    current_date + interval '16 days',
    null,
    array['architecture'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '4 days'
  ),
  -- Northwind — Analytics Rebrand
  (
    'a5000000-0000-0000-0000-000000000020',
    'ec000000-0000-0000-0000-000000000011',
    null,
    null,
    'ea000000-0000-0000-0000-000000000013',
    'Moodboard exploration',
    'Three visual directions ahead of the kickoff.',
    'todo',
    'medium',
    null,
    8,
    current_date + interval '18 days',
    null,
    array['branding'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '2 days'
  ),
  -- Halcyon — Member App Discovery
  (
    'a5000000-0000-0000-0000-000000000021',
    'ec000000-0000-0000-0000-000000000012',
    null,
    null,
    'ea000000-0000-0000-0000-000000000014',
    'Plan member interviews',
    'Recruit and schedule 8 gym members for discovery calls.',
    'todo',
    'low',
    null,
    6,
    current_date + interval '24 days',
    null,
    array['research'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '2 days'
  ),
  -- Cobalt — Claims Intake Redesign (on hold)
  (
    'a5000000-0000-0000-0000-000000000022',
    'ec000000-0000-0000-0000-000000000013',
    '5e000000-0000-0000-0000-000000000019',
    null,
    'ea000000-0000-0000-0000-000000000005',
    'Claims intake wireframes',
    'End-to-end intake flow wireframes for review.',
    'blocked',
    'medium',
    'Client security review paused all vendor work.',
    14,
    current_date + interval '40 days',
    null,
    array['ux'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '40 days'
  ),
  -- Copper Kettle — Loyalty Program (completed)
  (
    'a5000000-0000-0000-0000-000000000023',
    'ec000000-0000-0000-0000-000000000014',
    '5e000000-0000-0000-0000-000000000020',
    null,
    'ea000000-0000-0000-0000-000000000009',
    'Build points redemption flow',
    'Earn and redeem points at checkout.',
    'done',
    'medium',
    null,
    18,
    current_date - interval '65 days',
    current_timestamp - interval '63 days',
    array['ecommerce'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '95 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000024',
    'ec000000-0000-0000-0000-000000000014',
    '5e000000-0000-0000-0000-000000000020',
    null,
    'ea000000-0000-0000-0000-000000000012',
    'Regression test loyalty rules',
    'Full pass on earn rates, tiers, and expiry rules.',
    'done',
    'medium',
    null,
    8,
    current_date - interval '61 days',
    current_timestamp - interval '60 days',
    array['qa'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '80 days'
  ),
  -- Vantage Legal — Brand Identity (completed)
  (
    'a5000000-0000-0000-0000-000000000025',
    'ec000000-0000-0000-0000-000000000015',
    '5e000000-0000-0000-0000-000000000021',
    null,
    'ea000000-0000-0000-0000-000000000013',
    'Deliver final logo package',
    'All lockups, favicons, and usage guidance.',
    'done',
    'medium',
    null,
    10,
    current_date - interval '142 days',
    current_timestamp - interval '141 days',
    array['branding'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '170 days'
  ),
  -- Quartz Hotels — Booking Widget (completed)
  (
    'a5000000-0000-0000-0000-000000000026',
    'ec000000-0000-0000-0000-000000000016',
    '5e000000-0000-0000-0000-000000000022',
    null,
    'ea000000-0000-0000-0000-000000000004',
    'Harden availability caching',
    'Cache invalidation for room availability spikes.',
    'done',
    'high',
    null,
    12,
    current_date - interval '172 days',
    current_timestamp - interval '171 days',
    array['backend', 'performance'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '210 days'
  ),
  -- Papercrane — Digital Storefront (completed)
  (
    'a5000000-0000-0000-0000-000000000027',
    'ec000000-0000-0000-0000-000000000017',
    '5e000000-0000-0000-0000-000000000023',
    null,
    'ea000000-0000-0000-0000-000000000010',
    'Migrate order history',
    'Import legacy orders into the new storefront.',
    'done',
    'medium',
    null,
    16,
    current_date - interval '212 days',
    current_timestamp - interval '211 days',
    array['data'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '250 days'
  ),
  -- Fairway Sports — Commerce Audit (completed)
  (
    'a5000000-0000-0000-0000-000000000028',
    'ec000000-0000-0000-0000-000000000018',
    null,
    null,
    'ea000000-0000-0000-0000-000000000016',
    'Analyze checkout funnel drop-off',
    'Quantify abandonment by step across 90 days of data.',
    'done',
    'medium',
    null,
    10,
    current_date - interval '100 days',
    current_timestamp - interval '98 days',
    array['analytics'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '115 days'
  ),
  (
    'a5000000-0000-0000-0000-000000000029',
    'ec000000-0000-0000-0000-000000000018',
    null,
    null,
    'ea000000-0000-0000-0000-000000000016',
    'Present audit findings',
    'Executive readout with prioritized recommendations.',
    'done',
    'low',
    null,
    4,
    current_date - interval '92 days',
    current_timestamp - interval '91 days',
    array['audit'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '105 days'
  ),
  -- Lumen Energy — Customer Portal (cancelled)
  (
    'a5000000-0000-0000-0000-00000000002a',
    'ec000000-0000-0000-0000-000000000019',
    '5e000000-0000-0000-0000-000000000024',
    null,
    'ea000000-0000-0000-0000-000000000011',
    'Provision portal infrastructure',
    'Environments and CI ahead of the build phase.',
    'cancelled',
    'medium',
    null,
    20,
    null,
    null,
    array['devops'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '90 days'
  ),
  -- Brightside — Enrollment Site (cancelled)
  (
    'a5000000-0000-0000-0000-00000000002b',
    'ec000000-0000-0000-0000-000000000020',
    null,
    null,
    'ea000000-0000-0000-0000-000000000013',
    'Enrollment form design',
    'Multi-step enrollment and waitlist form.',
    'cancelled',
    'low',
    null,
    8,
    null,
    null,
    array['design'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '80 days'
  ),
  -- Blue Harbor — Brand Refresh (extra rollout work)
  (
    'a5000000-0000-0000-0000-00000000002c',
    'ec000000-0000-0000-0000-000000000002',
    '5e000000-0000-0000-0000-000000000025',
    null,
    'ea000000-0000-0000-0000-000000000013',
    'Design social media kit',
    'Profile, cover, and post templates in the new identity.',
    'todo',
    'medium',
    null,
    8,
    current_date + interval '22 days',
    null,
    array['branding'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '3 days'
  ),
  -- Nimbus Health — Patient Portal (extra planning work)
  (
    'a5000000-0000-0000-0000-00000000002d',
    'ec000000-0000-0000-0000-000000000003',
    '5e000000-0000-0000-0000-000000000007',
    null,
    'ea000000-0000-0000-0000-000000000011',
    'Draft infrastructure security baseline',
    'Encryption, audit logging, and access review baseline.',
    'todo',
    'critical',
    null,
    10,
    current_date + interval '30 days',
    null,
    array['security'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '2 days'
  ),
  -- Acme Robotics — Website Relaunch (extra review work)
  (
    'a5000000-0000-0000-0000-00000000002e',
    'ec000000-0000-0000-0000-000000000001',
    '5e000000-0000-0000-0000-000000000003',
    null,
    'ea000000-0000-0000-0000-000000000012',
    'Cross-browser QA sweep',
    'Full regression across supported browsers before launch.',
    'in_review',
    'high',
    null,
    10,
    current_date + interval '14 days',
    null,
    array['qa'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '4 days'
  ),
  (
    'a5000000-0000-0000-0000-00000000002f',
    'ec000000-0000-0000-0000-000000000001',
    '5e000000-0000-0000-0000-000000000003',
    null,
    'ea000000-0000-0000-0000-000000000017',
    'Prepare launch blog post',
    'Case-study style announcement for the relaunch.',
    'todo',
    'low',
    null,
    4,
    current_date + interval '16 days',
    null,
    array['content'],
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '2 days'
  );

----------------------------------------------------------------
-- Portfolio items (published case studies)
----------------------------------------------------------------
insert into
  demo.portfolio_items (
    project_id,
    client_id,
    title,
    summary,
    category,
    external_url,
    is_published,
    published_at,
    tags,
    color,
    sort_order
  )
values
  (
    'ec000000-0000-0000-0000-000000000005',
    null,
    'Studio Ops Dashboard',
    'Internal capacity-planning tool that replaced a spreadsheet-based process.',
    'product_design',
    'https://northstar.studio/work/ops-dashboard',
    true,
    current_date - interval '18 days',
    array['internal', 'tooling'],
    '#6366f1',
    1
  ),
  (
    'ec000000-0000-0000-0000-000000000001',
    'c1a00000-0000-0000-0000-000000000001',
    'Acme Robotics Website',
    'A marketing site rebuild with an interactive product configurator.',
    'web',
    'https://acme-robotics.example.com',
    true,
    current_date - interval '3 days',
    array['web', 'configurator'],
    '#f97316',
    2
  ),
  (
    'ec000000-0000-0000-0000-000000000002',
    'c1a00000-0000-0000-0000-000000000002',
    'Blue Harbor Brand System',
    'A full visual identity refresh, from logo concepts to editorial style guide.',
    'branding',
    null,
    true,
    current_date - interval '5 days',
    array['branding'],
    '#0ea5e9',
    3
  ),
  (
    null,
    'c1a00000-0000-0000-0000-000000000003',
    'Nimbus Health Discovery',
    'Early concept work from the patient portal discovery phase.',
    'product_design',
    null,
    false,
    null,
    array['healthcare', 'concept'],
    '#22c55e',
    4
  ),
  (
    'ec000000-0000-0000-0000-000000000014',
    'c1a00000-0000-0000-0000-000000000006',
    'Copper Kettle Loyalty Program',
    'A points-and-rewards program woven into the coffee subscription experience.',
    'product_design',
    'https://northstar.studio/work/copper-kettle-loyalty',
    true,
    current_date - interval '55 days',
    array['ecommerce', 'loyalty'],
    '#b45309',
    5
  ),
  (
    'ec000000-0000-0000-0000-000000000015',
    'c1a00000-0000-0000-0000-000000000007',
    'Vantage Legal Identity',
    'A conservative-but-modern identity system for a growing law firm.',
    'branding',
    'https://northstar.studio/work/vantage-legal',
    true,
    current_date - interval '135 days',
    array['branding', 'identity'],
    '#334155',
    6
  ),
  (
    'ec000000-0000-0000-0000-000000000016',
    'c1a00000-0000-0000-0000-000000000018',
    'Quartz Hotels Booking Widget',
    'An embeddable booking widget serving a multi-property hotel group.',
    'web',
    'https://quartzhotels.example.com',
    true,
    current_date - interval '165 days',
    array['web', 'booking'],
    '#64748b',
    7
  ),
  (
    'ec000000-0000-0000-0000-000000000017',
    'c1a00000-0000-0000-0000-000000000017',
    'Papercrane Digital Storefront',
    'A direct-to-reader storefront with print-on-demand fulfilment.',
    'web',
    'https://papercranepress.example.com',
    true,
    current_date - interval '205 days',
    array['ecommerce', 'publishing'],
    '#9333ea',
    8
  ),
  (
    'ec000000-0000-0000-0000-000000000018',
    'c1a00000-0000-0000-0000-000000000019',
    'Fairway Sports Commerce Audit',
    'A conversion audit that reshaped an online sporting goods business.',
    'marketing',
    null,
    true,
    current_date - interval '85 days',
    array['audit', 'analytics'],
    '#dc2626',
    9
  ),
  (
    null,
    'c1a00000-0000-0000-0000-000000000001',
    'Acme Robotics Launch Campaign',
    'Product launch campaign spanning email, social, and landing pages.',
    'marketing',
    'https://northstar.studio/work/acme-launch',
    true,
    current_date - interval '300 days',
    array['campaign'],
    '#f97316',
    10
  ),
  (
    'ec000000-0000-0000-0000-000000000008',
    'c1a00000-0000-0000-0000-000000000008',
    'Aurora Travel Booking App',
    'Work-in-progress case study for the cross-platform booking app.',
    'mobile',
    null,
    false,
    null,
    array['mobile', 'travel'],
    '#06b6d4',
    11
  ),
  (
    null,
    'c1a00000-0000-0000-0000-000000000002',
    'Blue Harbor Editorial Design',
    'Editorial layouts and art direction for a media publisher.',
    'branding',
    null,
    true,
    current_date - interval '90 days',
    array['editorial'],
    '#0ea5e9',
    12
  ),
  (
    null,
    'c1a00000-0000-0000-0000-000000000003',
    'Nimbus Health Design Sprint',
    'A one-week design sprint that de-risked the patient portal concept.',
    'product_design',
    null,
    true,
    current_date - interval '70 days',
    array['healthcare', 'sprint'],
    '#22c55e',
    13
  ),
  (
    'ec000000-0000-0000-0000-000000000009',
    'c1a00000-0000-0000-0000-000000000009',
    'Pixelforge Teaser Site',
    'A cinematic teaser site counting down to the fall title launch.',
    'web',
    'https://pixelforge.example.com',
    true,
    current_date - interval '40 days',
    array['gaming', 'launch'],
    '#8b5cf6',
    14
  ),
  (
    'ec000000-0000-0000-0000-000000000010',
    'c1a00000-0000-0000-0000-000000000010',
    'Meridian Pilot Dashboard Concept',
    'Concept frames from the fleet tracking pilot — publish after launch.',
    'product_design',
    null,
    false,
    null,
    array['dashboard', 'concept'],
    '#0f766e',
    15
  ),
  (
    null,
    'c1a00000-0000-0000-0000-000000000012',
    'Halcyon Fitness App Concept',
    'Early member-app concepts from the discovery pitch.',
    'mobile',
    null,
    false,
    null,
    array['fitness', 'concept'],
    '#f43f5e',
    16
  ),
  (
    null,
    'c1a00000-0000-0000-0000-000000000016',
    'Lumen Energy Design Explorations',
    'Portal design explorations — engagement ended before build.',
    'product_design',
    null,
    false,
    null,
    array['portal', 'concept'],
    '#f59e0b',
    17
  ),
  (
    null,
    'c1a00000-0000-0000-0000-000000000011',
    'Juniper & Sage Store Concept',
    'Pitch concept for a botanical e-commerce experience.',
    'web',
    null,
    false,
    null,
    array['ecommerce', 'pitch'],
    '#16a34a',
    18
  ),
  (
    null,
    'c1a00000-0000-0000-0000-000000000004',
    'Greenfield Retail POS Concept',
    'In-store POS interface concepts from the rollout programme.',
    'product_design',
    null,
    true,
    current_date - interval '100 days',
    array['retail', 'pos'],
    '#eab308',
    19
  ),
  (
    null,
    'c1a00000-0000-0000-0000-000000000013',
    'Northwind Analytics Pitch',
    'The rebrand pitch deck that won the Series B engagement.',
    'marketing',
    null,
    true,
    current_date - interval '10 days',
    array['pitch', 'branding'],
    '#2563eb',
    20
  );

----------------------------------------------------------------
-- Services (billing catalog)
----------------------------------------------------------------
insert into
  demo.services (
    id,
    name,
    description,
    category,
    default_rate,
    unit,
    color
  )
values
  (
    '5ec00000-0000-0000-0000-000000000001',
    'Discovery Workshop',
    'Stakeholder alignment and requirements gathering.',
    'consulting',
    150.00,
    'hour',
    '#a855f7'
  ),
  (
    '5ec00000-0000-0000-0000-000000000002',
    'UI/UX Design',
    'Interface design, prototyping, and user testing.',
    'design',
    120.00,
    'hour',
    '#f97316'
  ),
  (
    '5ec00000-0000-0000-0000-000000000003',
    'Frontend Development',
    'Component implementation and integration work.',
    'development',
    140.00,
    'hour',
    '#0ea5e9'
  ),
  (
    '5ec00000-0000-0000-0000-000000000004',
    'Backend Development',
    'API, database, and infrastructure engineering.',
    'development',
    150.00,
    'hour',
    '#0ea5e9'
  ),
  (
    '5ec00000-0000-0000-0000-000000000005',
    'QA Testing',
    'Manual and automated test coverage.',
    'development',
    90.00,
    'hour',
    '#22c55e'
  ),
  (
    '5ec00000-0000-0000-0000-000000000006',
    'Content Strategy',
    'Messaging, copywriting, and editorial planning.',
    'marketing',
    110.00,
    'hour',
    '#eab308'
  ),
  (
    '5ec00000-0000-0000-0000-000000000007',
    'Brand Identity Package',
    'Logo system, color palette, and typography — fixed scope.',
    'design',
    2500.00,
    'project',
    '#f97316'
  ),
  (
    '5ec00000-0000-0000-0000-000000000008',
    'Support Retainer',
    'Ongoing maintenance and support hours.',
    'support',
    100.00,
    'hour',
    '#6366f1'
  );

insert into
  demo.services (
    id,
    name,
    description,
    category,
    default_rate,
    unit,
    is_active,
    color
  )
values
  (
    '5ec00000-0000-0000-0000-000000000009',
    'SEO Audit',
    'Technical and content SEO review with an action plan.',
    'marketing',
    1500.00,
    'project',
    true,
    '#eab308'
  ),
  (
    '5ec00000-0000-0000-0000-000000000010',
    'Mobile App Development',
    'Native and cross-platform mobile engineering.',
    'development',
    145.00,
    'hour',
    true,
    '#0ea5e9'
  ),
  (
    '5ec00000-0000-0000-0000-000000000011',
    'DevOps Retainer',
    'Infrastructure, CI/CD, and on-call support.',
    'support',
    1800.00,
    'month',
    true,
    '#6366f1'
  ),
  (
    '5ec00000-0000-0000-0000-000000000012',
    'Copywriting',
    'Web, product, and campaign copy.',
    'marketing',
    95.00,
    'hour',
    true,
    '#eab308'
  ),
  (
    '5ec00000-0000-0000-0000-000000000013',
    'Analytics Setup',
    'Tracking plan, dashboards, and event instrumentation.',
    'consulting',
    1200.00,
    'project',
    true,
    '#a855f7'
  ),
  (
    '5ec00000-0000-0000-0000-000000000014',
    'Design System Build',
    'Component library, tokens, and documentation — fixed scope.',
    'design',
    8000.00,
    'project',
    true,
    '#f97316'
  ),
  (
    '5ec00000-0000-0000-0000-000000000015',
    'Workshop Facilitation',
    'Discovery, design sprint, and alignment workshops.',
    'consulting',
    160.00,
    'hour',
    true,
    '#a855f7'
  ),
  (
    '5ec00000-0000-0000-0000-000000000016',
    'API Integration',
    'Third-party API and data feed integration work.',
    'development',
    135.00,
    'hour',
    true,
    '#0ea5e9'
  ),
  (
    '5ec00000-0000-0000-0000-000000000017',
    'Performance Audit',
    'Core Web Vitals and backend latency review.',
    'development',
    1600.00,
    'project',
    true,
    '#0ea5e9'
  ),
  (
    '5ec00000-0000-0000-0000-000000000018',
    'Accessibility Review',
    'WCAG 2.1 AA audit with remediation guidance.',
    'consulting',
    1400.00,
    'project',
    true,
    '#a855f7'
  ),
  (
    '5ec00000-0000-0000-0000-000000000019',
    'Email Campaign Setup',
    'Retired offering — folded into Content Strategy.',
    'marketing',
    900.00,
    'project',
    false,
    '#eab308'
  ),
  (
    '5ec00000-0000-0000-0000-000000000020',
    'Print Design',
    'Retired offering — no longer accepting print work.',
    'design',
    105.00,
    'hour',
    false,
    '#f97316'
  );

----------------------------------------------------------------
-- Invoices (subtotal/tax/total are recalculated by the
-- invoice_items_recalc trigger once line items are inserted below)
----------------------------------------------------------------
insert into
  demo.invoices (
    id,
    client_id,
    project_id,
    status,
    issue_date,
    due_date,
    tax_rate,
    paid_at,
    notes,
    user_id
  )
values
  (
    'ffa00000-0000-0000-0000-000000000001',
    'c1a00000-0000-0000-0000-000000000001',
    'ec000000-0000-0000-0000-000000000001',
    'paid',
    current_date - interval '40 days',
    current_date - interval '10 days',
    8,
    current_timestamp - interval '9 days',
    'Milestone 1 — Discovery & IA.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'
  ),
  (
    'ffa00000-0000-0000-0000-000000000002',
    'c1a00000-0000-0000-0000-000000000001',
    'ec000000-0000-0000-0000-000000000001',
    'sent',
    current_date - interval '5 days',
    current_date + interval '25 days',
    8,
    null,
    'Milestone 2 — Design Handoff.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'
  ),
  (
    'ffa00000-0000-0000-0000-000000000003',
    'c1a00000-0000-0000-0000-000000000002',
    'ec000000-0000-0000-0000-000000000002',
    'overdue',
    current_date - interval '35 days',
    current_date - interval '5 days',
    6.5,
    null,
    'Logo concepts + initial workshops.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1'
  ),
  (
    'ffa00000-0000-0000-0000-000000000004',
    'c1a00000-0000-0000-0000-000000000004',
    'ec000000-0000-0000-0000-000000000004',
    'draft',
    current_date - interval '2 days',
    current_date + interval '28 days',
    0,
    null,
    'Draft pending client sign-off — project on hold.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4'
  ),
  (
    'ffa00000-0000-0000-0000-000000000005',
    'c1a00000-0000-0000-0000-000000000001',
    null,
    'paid',
    current_date - interval '80 days',
    current_date - interval '50 days',
    8,
    current_timestamp - interval '48 days',
    'Quarterly support retainer.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'
  ),
  (
    'ffa00000-0000-0000-0000-000000000006',
    'c1a00000-0000-0000-0000-000000000003',
    'ec000000-0000-0000-0000-000000000003',
    'draft',
    current_date - interval '1 day',
    current_date + interval '29 days',
    0,
    null,
    'Discovery workshop deposit.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'
  ),
  (
    'ffa00000-0000-0000-0000-000000000007',
    'c1a00000-0000-0000-0000-000000000006',
    'ec000000-0000-0000-0000-000000000014',
    'paid',
    current_date - interval '140 days',
    current_date - interval '110 days',
    8,
    current_timestamp - interval '108 days',
    'Loyalty program — final invoice.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4'
  ),
  (
    'ffa00000-0000-0000-0000-000000000008',
    'c1a00000-0000-0000-0000-000000000007',
    'ec000000-0000-0000-0000-000000000015',
    'paid',
    current_date - interval '135 days',
    current_date - interval '105 days',
    6.5,
    current_timestamp - interval '104 days',
    'Brand identity — fixed fee.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'
  ),
  (
    'ffa00000-0000-0000-0000-000000000009',
    'c1a00000-0000-0000-0000-000000000018',
    'ec000000-0000-0000-0000-000000000016',
    'paid',
    current_date - interval '165 days',
    current_date - interval '135 days',
    0,
    current_timestamp - interval '130 days',
    'Booking widget delivery.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'
  ),
  (
    'ffa00000-0000-0000-0000-000000000010',
    'c1a00000-0000-0000-0000-000000000017',
    'ec000000-0000-0000-0000-000000000017',
    'paid',
    current_date - interval '205 days',
    current_date - interval '175 days',
    10,
    current_timestamp - interval '172 days',
    'Storefront launch balance.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1'
  ),
  (
    'ffa00000-0000-0000-0000-000000000011',
    'c1a00000-0000-0000-0000-000000000019',
    'ec000000-0000-0000-0000-000000000018',
    'paid',
    current_date - interval '84 days',
    current_date - interval '54 days',
    0,
    current_timestamp - interval '50 days',
    'Commerce audit engagement.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4'
  ),
  (
    'ffa00000-0000-0000-0000-000000000012',
    'c1a00000-0000-0000-0000-000000000006',
    'ec000000-0000-0000-0000-000000000006',
    'paid',
    current_date - interval '63 days',
    current_date - interval '33 days',
    8,
    current_timestamp - interval '30 days',
    'E-commerce build — sprint 1.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4'
  ),
  (
    'ffa00000-0000-0000-0000-000000000013',
    'c1a00000-0000-0000-0000-000000000008',
    'ec000000-0000-0000-0000-000000000008',
    'paid',
    current_date - interval '56 days',
    current_date - interval '26 days',
    0,
    current_timestamp - interval '20 days',
    'Booking app — milestone 1.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1'
  ),
  (
    'ffa00000-0000-0000-0000-000000000014',
    'c1a00000-0000-0000-0000-000000000007',
    'ec000000-0000-0000-0000-000000000007',
    'paid',
    current_date - interval '49 days',
    current_date - interval '19 days',
    6.5,
    current_timestamp - interval '15 days',
    'Client portal — discovery phase.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'
  ),
  (
    'ffa00000-0000-0000-0000-000000000015',
    'c1a00000-0000-0000-0000-000000000010',
    'ec000000-0000-0000-0000-000000000010',
    'paid',
    current_date - interval '42 days',
    current_date - interval '12 days',
    0,
    current_timestamp - interval '8 days',
    'Fleet dashboard pilot review.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'
  ),
  (
    'ffa00000-0000-0000-0000-000000000016',
    'c1a00000-0000-0000-0000-000000000006',
    'ec000000-0000-0000-0000-000000000006',
    'sent',
    current_date - interval '28 days',
    current_date + interval '2 days',
    8,
    null,
    'E-commerce build — sprint 2.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4'
  ),
  (
    'ffa00000-0000-0000-0000-000000000017',
    'c1a00000-0000-0000-0000-000000000008',
    'ec000000-0000-0000-0000-000000000008',
    'sent',
    current_date - interval '21 days',
    current_date + interval '9 days',
    0,
    null,
    'Booking app — milestone 2.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1'
  ),
  (
    'ffa00000-0000-0000-0000-000000000018',
    'c1a00000-0000-0000-0000-000000000009',
    'ec000000-0000-0000-0000-000000000009',
    'sent',
    current_date - interval '14 days',
    current_date + interval '16 days',
    8,
    null,
    'Marketing site — first sprint.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4'
  ),
  (
    'ffa00000-0000-0000-0000-000000000019',
    'c1a00000-0000-0000-0000-000000000007',
    'ec000000-0000-0000-0000-000000000007',
    'sent',
    current_date - interval '7 days',
    current_date + interval '23 days',
    6.5,
    null,
    'Client portal — sprint 1.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'
  ),
  (
    'ffa00000-0000-0000-0000-000000000020',
    'c1a00000-0000-0000-0000-000000000002',
    'ec000000-0000-0000-0000-000000000002',
    'overdue',
    current_date - interval '45 days',
    current_date - interval '15 days',
    6.5,
    null,
    'Style guide milestone.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1'
  ),
  (
    'ffa00000-0000-0000-0000-000000000021',
    'c1a00000-0000-0000-0000-000000000015',
    'ec000000-0000-0000-0000-000000000013',
    'overdue',
    current_date - interval '60 days',
    current_date - interval '30 days',
    0,
    null,
    'Claims redesign — phase 1 (project on hold).',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'
  ),
  (
    'ffa00000-0000-0000-0000-000000000022',
    'c1a00000-0000-0000-0000-000000000012',
    null,
    'draft',
    current_date - interval '1 day',
    current_date + interval '29 days',
    0,
    null,
    'Member app discovery proposal.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4'
  ),
  (
    'ffa00000-0000-0000-0000-000000000023',
    'c1a00000-0000-0000-0000-000000000013',
    'ec000000-0000-0000-0000-000000000011',
    'draft',
    current_date,
    current_date + interval '30 days',
    0,
    null,
    'Rebrand kickoff deposit.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'
  ),
  (
    'ffa00000-0000-0000-0000-000000000024',
    'c1a00000-0000-0000-0000-000000000016',
    'ec000000-0000-0000-0000-000000000019',
    'void',
    current_date - interval '75 days',
    current_date - interval '45 days',
    0,
    null,
    'Voided after the portal project was cancelled.',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4'
  );

----------------------------------------------------------------
-- Invoice line items (unit_price backfilled here to mirror what the
-- lookup-fill UI would populate from demo.services.default_rate)
----------------------------------------------------------------
insert into
  demo.invoice_items (
    invoice_id,
    service_id,
    description,
    quantity,
    unit_price,
    sort_order
  )
values
  -- ffa...001 (Acme, paid) — Discovery Workshop + UI/UX Design
  (
    'ffa00000-0000-0000-0000-000000000001',
    '5ec00000-0000-0000-0000-000000000001',
    'Discovery Workshop',
    20,
    150.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000001',
    '5ec00000-0000-0000-0000-000000000002',
    'UI/UX Design',
    40,
    120.00,
    2
  ),
  -- ffa...002 (Acme, sent) — Frontend Development
  (
    'ffa00000-0000-0000-0000-000000000002',
    '5ec00000-0000-0000-0000-000000000003',
    'Frontend Development',
    60,
    140.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000002',
    '5ec00000-0000-0000-0000-000000000005',
    'QA Testing',
    10,
    90.00,
    2
  ),
  -- ffa...003 (Blue Harbor, overdue) — Brand Identity Package
  (
    'ffa00000-0000-0000-0000-000000000003',
    '5ec00000-0000-0000-0000-000000000007',
    'Brand Identity Package',
    1,
    2500.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000003',
    '5ec00000-0000-0000-0000-000000000001',
    'Discovery Workshop',
    8,
    150.00,
    2
  ),
  -- ffa...004 (Greenfield, draft) — Backend Development
  (
    'ffa00000-0000-0000-0000-000000000004',
    '5ec00000-0000-0000-0000-000000000004',
    'Backend Development',
    15,
    150.00,
    1
  ),
  -- ffa...005 (Acme, paid) — Support Retainer
  (
    'ffa00000-0000-0000-0000-000000000005',
    '5ec00000-0000-0000-0000-000000000008',
    'Support Retainer',
    25,
    100.00,
    1
  ),
  -- ffa...006 (Nimbus, draft) — Discovery Workshop deposit
  (
    'ffa00000-0000-0000-0000-000000000006',
    '5ec00000-0000-0000-0000-000000000001',
    'Discovery Workshop',
    10,
    150.00,
    1
  ),
  -- ffa...007 (Copper Kettle loyalty, paid)
  (
    'ffa00000-0000-0000-0000-000000000007',
    '5ec00000-0000-0000-0000-000000000003',
    'Frontend Development',
    40,
    140.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000007',
    '5ec00000-0000-0000-0000-000000000002',
    'UI/UX Design',
    20,
    120.00,
    2
  ),
  -- ffa...008 (Vantage identity, paid)
  (
    'ffa00000-0000-0000-0000-000000000008',
    '5ec00000-0000-0000-0000-000000000007',
    'Brand Identity Package',
    1,
    2500.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000008',
    '5ec00000-0000-0000-0000-000000000012',
    'Copywriting',
    10,
    95.00,
    2
  ),
  -- ffa...009 (Quartz widget, paid)
  (
    'ffa00000-0000-0000-0000-000000000009',
    '5ec00000-0000-0000-0000-000000000004',
    'Backend Development',
    60,
    150.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000009',
    '5ec00000-0000-0000-0000-000000000005',
    'QA Testing',
    20,
    90.00,
    2
  ),
  -- ffa...010 (Papercrane storefront, paid)
  (
    'ffa00000-0000-0000-0000-000000000010',
    '5ec00000-0000-0000-0000-000000000003',
    'Frontend Development',
    80,
    140.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000010',
    '5ec00000-0000-0000-0000-000000000004',
    'Backend Development',
    50,
    150.00,
    2
  ),
  (
    'ffa00000-0000-0000-0000-000000000010',
    '5ec00000-0000-0000-0000-000000000005',
    'QA Testing',
    15,
    90.00,
    3
  ),
  -- ffa...011 (Fairway audit, paid)
  (
    'ffa00000-0000-0000-0000-000000000011',
    '5ec00000-0000-0000-0000-000000000013',
    'Analytics Setup',
    1,
    1200.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000011',
    '5ec00000-0000-0000-0000-000000000009',
    'SEO Audit',
    1,
    1500.00,
    2
  ),
  -- ffa...012 (Copper Kettle store sprint 1, paid)
  (
    'ffa00000-0000-0000-0000-000000000012',
    '5ec00000-0000-0000-0000-000000000003',
    'Frontend Development',
    40,
    140.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000012',
    '5ec00000-0000-0000-0000-000000000002',
    'UI/UX Design',
    15,
    120.00,
    2
  ),
  -- ffa...013 (Aurora milestone 1, paid)
  (
    'ffa00000-0000-0000-0000-000000000013',
    '5ec00000-0000-0000-0000-000000000010',
    'Mobile App Development',
    50,
    145.00,
    1
  ),
  -- ffa...014 (Vantage portal discovery, paid)
  (
    'ffa00000-0000-0000-0000-000000000014',
    '5ec00000-0000-0000-0000-000000000001',
    'Discovery Workshop',
    16,
    150.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000014',
    '5ec00000-0000-0000-0000-000000000002',
    'UI/UX Design',
    10,
    120.00,
    2
  ),
  -- ffa...015 (Meridian pilot review, paid)
  (
    'ffa00000-0000-0000-0000-000000000015',
    '5ec00000-0000-0000-0000-000000000015',
    'Workshop Facilitation',
    12,
    160.00,
    1
  ),
  -- ffa...016 (Copper Kettle store sprint 2, sent)
  (
    'ffa00000-0000-0000-0000-000000000016',
    '5ec00000-0000-0000-0000-000000000003',
    'Frontend Development',
    45,
    140.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000016',
    '5ec00000-0000-0000-0000-000000000005',
    'QA Testing',
    12,
    90.00,
    2
  ),
  -- ffa...017 (Aurora milestone 2, sent)
  (
    'ffa00000-0000-0000-0000-000000000017',
    '5ec00000-0000-0000-0000-000000000010',
    'Mobile App Development',
    60,
    145.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000017',
    '5ec00000-0000-0000-0000-000000000016',
    'API Integration',
    20,
    135.00,
    2
  ),
  -- ffa...018 (Pixelforge sprint 1, sent)
  (
    'ffa00000-0000-0000-0000-000000000018',
    '5ec00000-0000-0000-0000-000000000002',
    'UI/UX Design',
    25,
    120.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000018',
    '5ec00000-0000-0000-0000-000000000012',
    'Copywriting',
    12,
    95.00,
    2
  ),
  -- ffa...019 (Vantage portal sprint 1, sent)
  (
    'ffa00000-0000-0000-0000-000000000019',
    '5ec00000-0000-0000-0000-000000000004',
    'Backend Development',
    30,
    150.00,
    1
  ),
  -- ffa...020 (Blue Harbor style guide, overdue)
  (
    'ffa00000-0000-0000-0000-000000000020',
    '5ec00000-0000-0000-0000-000000000002',
    'UI/UX Design',
    30,
    120.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000020',
    '5ec00000-0000-0000-0000-000000000012',
    'Copywriting',
    8,
    95.00,
    2
  ),
  -- ffa...021 (Cobalt phase 1, overdue)
  (
    'ffa00000-0000-0000-0000-000000000021',
    '5ec00000-0000-0000-0000-000000000002',
    'UI/UX Design',
    24,
    120.00,
    1
  ),
  (
    'ffa00000-0000-0000-0000-000000000021',
    '5ec00000-0000-0000-0000-000000000001',
    'Discovery Workshop',
    6,
    150.00,
    2
  ),
  -- ffa...022 (Halcyon proposal, draft)
  (
    'ffa00000-0000-0000-0000-000000000022',
    '5ec00000-0000-0000-0000-000000000001',
    'Discovery Workshop',
    12,
    150.00,
    1
  ),
  -- ffa...023 (Northwind deposit, draft)
  (
    'ffa00000-0000-0000-0000-000000000023',
    '5ec00000-0000-0000-0000-000000000007',
    'Brand Identity Package',
    1,
    2500.00,
    1
  ),
  -- ffa...024 (Lumen, void)
  (
    'ffa00000-0000-0000-0000-000000000024',
    '5ec00000-0000-0000-0000-000000000004',
    'Backend Development',
    20,
    150.00,
    1
  );

----------------------------------------------------------------
-- Time entries
----------------------------------------------------------------
insert into
  demo.time_entries (
    task_id,
    team_member_id,
    entry_date,
    duration,
    is_billable,
    notes
  )
values
  (
    'a5000000-0000-0000-0000-000000000001',
    'ea000000-0000-0000-0000-000000000004',
    current_date - interval '18 days',
    14400,
    true,
    'Configurator scaffolding.'
  ),
  (
    'a5000000-0000-0000-0000-000000000001',
    'ea000000-0000-0000-0000-000000000004',
    current_date - interval '15 days',
    21600,
    true,
    '3D model integration.'
  ),
  (
    'a5000000-0000-0000-0000-000000000002',
    'ea000000-0000-0000-0000-000000000004',
    current_date - interval '10 days',
    18000,
    true,
    'Color + material step complete.'
  ),
  (
    'a5000000-0000-0000-0000-000000000003',
    'ea000000-0000-0000-0000-000000000004',
    current_date - interval '3 days',
    10800,
    true,
    'Pricing summary in progress.'
  ),
  (
    'a5000000-0000-0000-0000-000000000004',
    'ea000000-0000-0000-0000-000000000002',
    current_date - interval '9 days',
    7200,
    true,
    'Hosting vendor comparison.'
  ),
  (
    'a5000000-0000-0000-0000-000000000006',
    'ea000000-0000-0000-0000-000000000005',
    current_date - interval '20 days',
    28800,
    true,
    'Logo concept sketches.'
  ),
  (
    'a5000000-0000-0000-0000-000000000006',
    'ea000000-0000-0000-0000-000000000005',
    current_date - interval '18 days',
    25200,
    true,
    'Refined final concept direction.'
  ),
  (
    'a5000000-0000-0000-0000-000000000007',
    'ea000000-0000-0000-0000-000000000003',
    current_date - interval '11 days',
    21600,
    true,
    'Typography system draft.'
  ),
  (
    'a5000000-0000-0000-0000-000000000007',
    'ea000000-0000-0000-0000-000000000003',
    current_date - interval '6 days',
    18000,
    true,
    'Color system + usage rules.'
  ),
  (
    'a5000000-0000-0000-0000-000000000009',
    'ea000000-0000-0000-0000-000000000002',
    current_date - interval '5 days',
    14400,
    true,
    'Compliance workshop prep.'
  ),
  (
    'a5000000-0000-0000-0000-00000000000a',
    'ea000000-0000-0000-0000-000000000004',
    current_date - interval '2 days',
    10800,
    true,
    'Initial architecture notes.'
  ),
  (
    'a5000000-0000-0000-0000-00000000000d',
    'ea000000-0000-0000-0000-000000000008',
    current_date - interval '24 days',
    21600,
    false,
    'Internal tooling — non-billable.'
  ),
  (
    'a5000000-0000-0000-0000-00000000000e',
    'ea000000-0000-0000-0000-000000000001',
    current_date - interval '21 days',
    7200,
    false,
    'Internal tooling — non-billable.'
  ),
  (
    'a5000000-0000-0000-0000-00000000000f',
    'ea000000-0000-0000-0000-000000000009',
    current_date - interval '6 days',
    21600,
    true,
    'Checkout flow scaffolding.'
  ),
  (
    'a5000000-0000-0000-0000-00000000000f',
    'ea000000-0000-0000-0000-000000000009',
    current_date - interval '4 days',
    18000,
    true,
    'Cart state handling.'
  ),
  (
    'a5000000-0000-0000-0000-000000000010',
    'ea000000-0000-0000-0000-000000000009',
    current_date - interval '2 days',
    10800,
    true,
    'Payment provider sandbox integration.'
  ),
  (
    'a5000000-0000-0000-0000-000000000012',
    'ea000000-0000-0000-0000-000000000010',
    current_date - interval '23 days',
    14400,
    true,
    'Catalog import script.'
  ),
  (
    'a5000000-0000-0000-0000-000000000012',
    'ea000000-0000-0000-0000-000000000010',
    current_date - interval '21 days',
    7200,
    true,
    'Import cleanup and dedupe.'
  ),
  (
    'a5000000-0000-0000-0000-000000000014',
    'ea000000-0000-0000-0000-000000000010',
    current_date - interval '5 days',
    14400,
    true,
    'Case schema draft.'
  ),
  (
    'a5000000-0000-0000-0000-000000000015',
    'ea000000-0000-0000-0000-000000000004',
    current_date - interval '8 days',
    10800,
    true,
    'Upload service setup.'
  ),
  (
    'a5000000-0000-0000-0000-000000000015',
    'ea000000-0000-0000-0000-000000000004',
    current_date - interval '6 days',
    7200,
    true,
    'Virus scan hook.'
  ),
  (
    'a5000000-0000-0000-0000-000000000017',
    'ea000000-0000-0000-0000-000000000014',
    current_date - interval '13 days',
    9000,
    true,
    'Paralegal interviews.'
  ),
  (
    'a5000000-0000-0000-0000-000000000018',
    'ea000000-0000-0000-0000-000000000009',
    current_date - interval '3 days',
    21600,
    true,
    'Seat map rendering.'
  ),
  (
    'a5000000-0000-0000-0000-000000000019',
    'ea000000-0000-0000-0000-000000000011',
    current_date - interval '10 days',
    7200,
    true,
    'Load test scripts — blocked midway.'
  ),
  (
    'a5000000-0000-0000-0000-00000000001a',
    'ea000000-0000-0000-0000-000000000010',
    current_date - interval '18 days',
    25200,
    true,
    'Availability feed integration.'
  ),
  (
    'a5000000-0000-0000-0000-00000000001a',
    'ea000000-0000-0000-0000-000000000010',
    current_date - interval '16 days',
    14400,
    true,
    'Feed edge cases and retries.'
  ),
  (
    'a5000000-0000-0000-0000-00000000001c',
    'ea000000-0000-0000-0000-000000000013',
    current_date - interval '7 days',
    12600,
    true,
    'Press kit layout.'
  ),
  (
    'a5000000-0000-0000-0000-00000000001e',
    'ea000000-0000-0000-0000-000000000016',
    current_date - interval '9 days',
    10800,
    true,
    'Pilot feedback synthesis.'
  ),
  (
    'a5000000-0000-0000-0000-00000000001f',
    'ea000000-0000-0000-0000-000000000010',
    current_date - interval '1 day',
    5400,
    true,
    'Mapping provider comparison matrix.'
  ),
  (
    'a5000000-0000-0000-0000-000000000020',
    'ea000000-0000-0000-0000-000000000013',
    current_date - interval '2 days',
    5400,
    false,
    'Moodboard pulls — pre-kickoff research.'
  ),
  (
    'a5000000-0000-0000-0000-000000000022',
    'ea000000-0000-0000-0000-000000000005',
    current_date - interval '35 days',
    12600,
    true,
    'Intake wireframes v1.'
  ),
  (
    'a5000000-0000-0000-0000-000000000023',
    'ea000000-0000-0000-0000-000000000009',
    current_date - interval '66 days',
    21600,
    true,
    'Redemption flow build.'
  ),
  (
    'a5000000-0000-0000-0000-000000000024',
    'ea000000-0000-0000-0000-000000000012',
    current_date - interval '61 days',
    14400,
    true,
    'Loyalty regression pass.'
  ),
  (
    'a5000000-0000-0000-0000-000000000025',
    'ea000000-0000-0000-0000-000000000013',
    current_date - interval '143 days',
    18000,
    true,
    'Logo package production.'
  ),
  (
    'a5000000-0000-0000-0000-000000000026',
    'ea000000-0000-0000-0000-000000000004',
    current_date - interval '173 days',
    16200,
    true,
    'Caching hardening.'
  ),
  (
    'a5000000-0000-0000-0000-000000000027',
    'ea000000-0000-0000-0000-000000000010',
    current_date - interval '213 days',
    21600,
    true,
    'Order history migration.'
  ),
  (
    'a5000000-0000-0000-0000-000000000028',
    'ea000000-0000-0000-0000-000000000016',
    current_date - interval '100 days',
    18000,
    true,
    'Funnel analysis deep-dive.'
  ),
  (
    'a5000000-0000-0000-0000-000000000029',
    'ea000000-0000-0000-0000-000000000016',
    current_date - interval '92 days',
    7200,
    true,
    'Findings deck and readout.'
  ),
  (
    'a5000000-0000-0000-0000-00000000002e',
    'ea000000-0000-0000-0000-000000000012',
    current_date - interval '3 days',
    12600,
    true,
    'Browser matrix regression run.'
  ),
  (
    'a5000000-0000-0000-0000-000000000009',
    'ea000000-0000-0000-0000-000000000002',
    current_date - interval '4 days',
    10800,
    true,
    'Compliance workshop facilitation.'
  );

select
  supasheet.refresh_metadata ();
