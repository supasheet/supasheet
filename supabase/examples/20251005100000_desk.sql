-- ================================================================
-- Supasheet Example — "Desk" (customer support / helpdesk)
-- ================================================================
-- The schema for a complete support organisation: customers and
-- their contacts, support teams and agents, SLA policies, a ticket
-- pipeline, threaded replies and internal notes, worklogs, CSAT
-- surveys, known problems, and a knowledge base.
--
-- Demo data lives in supabase/examples/d_seed.sql — apply this file
-- first, then that one.
--
-- Feature coverage:
--   - Native-role RBAC, including a CUSTOM role ("agent") alongside
--     the built-in "x-admin"/"user" — CREATE ROLE + GRANT, no
--     permissions table
--   - Row Level Security, including an ownership-scoped resource
--     (desk.tickets: requesters see only their own, agents/admins
--     see everything) via pg_has_role()
--   - All column data types: URL, TEL, EMAIL, RICH_TEXT, COLOR,
--     PERCENTAGE, DURATION, RATING, file, AVATAR, enums, arrays
--   - All six view layouts: kanban (tickets), calendar (tickets),
--     gallery (articles, agents, customers), list (sla_policies,
--     canned_responses, articles), tree (categories, agents org
--     chart), gantt (problems roadmap)
--   - Field sections, filter presets, quick_create, conditional
--     field behavior, lookup fill + lookup filter, resource links
--   - Singleton resource (desk_settings)
--   - 1:1 extension record (customer_billing)
--   - Many-to-many junction with inline form (ticket_watchers)
--   - One-to-many detail lines with business triggers that keep
--     parent rollups in sync (worklogs -> tickets.time_spent,
--     satisfaction_surveys -> tickets.satisfaction_score,
--     ticket_messages -> tickets.first_response_at)
--   - Detail page "tabs" allowlist + "timelines" (ticket_events,
--     a trigger-populated, read-only activity feed)
--   - Row actions backed by SQL functions (resolve, reopen,
--     escalate, publish, plus an enum picker for priority)
--   - Custom forms backed by SQL functions, each returning a
--     different shape: log_ticket_work (scalar uuid, on "tickets"),
--     open_ticket_for_customer (single object via OUT params, on
--     "customers"), bulk_reassign_tickets (setof desk.tickets, on
--     "agents"), preview_team_workload (setof rows via an explicit
--     table(...) list, on "teams")
--   - Templates (bulk insert via supasheet.apply_template): one
--     static (onboarding_tickets_template) and one dynamic
--     (sla_followup_template)
--   - Reports, including one with an HTML/Handlebars print template
--     (tickets_report -> supabase/examples/templates/tickets_report.hbs)
--     and a MATERIALIZED VIEW report (ticket_volume_rollup)
--   - Dashboard widgets: every contract (card_1..card_6, table_1,
--     table_2, list_1..list_4), global and resource-scoped
--   - Charts: every contract (pie, bar, line, area, radar), global
--     and resource-scoped
--   - Notifications (ticket lifecycle, SLA breach, problem updates,
--     and a comment-notify pairing on supasheet.comments)
--   - Audit logging and per-resource comments
--   - Column footer aggregates via the `aggregate` column comment key
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20251005100000_desk.sql \
--     -f supabase/examples/d_seed.sql
--
-- Requires the base Supasheet migrations (supabase/migrations/*) to
-- already be applied. Also add "desk" to config.toml's `api.schemas`
-- and `api.extra_search_path` so PostgREST exposes it, then restart
-- Supabase.
--
-- Not idempotent: `create schema` / `create type` / `create table`
-- fail on a second run. Re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists desk;

-------------------------------------------------------------------
-- Roles
--
-- "x-admin" ships with the base migrations. "user" and "admin" are
-- the optional built-in tiers (created in supabase/seed.sql), and
-- "agent" is a custom role specific to this module — a custom role
-- is nothing more than `create role ... nologin` plus grants.
--
--   x-admin  desk manager: full control over everything
--   agent    support staff: works tickets, cannot delete records
--            and cannot see customer billing
--   user     requester/end customer: files tickets, replies to their
--            own, reads the public knowledge base
--
-- Assign a user to the custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "agent"}'
--   where email = 'agent@supasheet.app';
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

  if not exists (select 1 from pg_roles where rolname = 'agent') then
    create role "agent" nologin;
  end if;
end;
$$;

-- Let PostgREST SET ROLE into each role...
grant "user",
"admin",
"agent" to authenticator;

-- ...and let `to authenticated` policies still apply to them.
grant authenticated to "user",
"admin",
"agent";

-- Schema usage is granted per native role, never to `authenticated`.
grant usage on schema desk to "x-admin",
"agent",
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

create type desk.ticket_status as enum(
  'new',
  'open',
  'pending',
  'on_hold',
  'resolved',
  'closed'
);

create type desk.ticket_priority as enum('low', 'normal', 'high', 'urgent');

create type desk.ticket_channel as enum('email', 'web', 'phone', 'chat', 'api');

create type desk.ticket_type as enum(
  'question',
  'incident',
  'problem',
  'feature_request',
  'task'
);

create type desk.ticket_event_type as enum(
  'created',
  'status_changed',
  'assigned',
  'priority_changed',
  'escalated',
  'sla_breached',
  'reply_added',
  'record_updated'
);

create type desk.message_kind as enum('public_reply', 'internal_note', 'system');

create type desk.agent_seniority as enum(
  'associate',
  'specialist',
  'senior',
  'lead',
  'manager'
);

create type desk.agent_availability as enum('available', 'busy', 'away', 'offline');

create type desk.customer_tier as enum('free', 'starter', 'business', 'enterprise');

create type desk.customer_health as enum('healthy', 'watch', 'at_risk', 'churned');

create type desk.problem_status as enum(
  'identified',
  'investigating',
  'fix_in_progress',
  'monitoring',
  'resolved'
);

create type desk.problem_impact as enum('minor', 'moderate', 'major', 'critical');

create type desk.article_status as enum('draft', 'in_review', 'published', 'archived');

create type desk.survey_sentiment as enum('detractor', 'passive', 'promoter');

commit;

----------------------------------------------------------------
-- Users replica view
--
-- FKs point at the real supasheet.users table, but PostgREST cannot
-- embed across schemas — every app schema needs a same-name replica
-- view so `query.join` on a user column resolves.
----------------------------------------------------------------
create or replace view desk.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on desk.users
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.users to "x-admin",
  "agent",
  "user";

----------------------------------------------------------------
-- Teams (support queues)
----------------------------------------------------------------
create table desk.teams (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null unique,
  description text,
  mailbox supasheet.EMAIL,
  business_hours varchar(100) not null default '09:00-17:00',
  timezone varchar(100) not null default 'UTC',
  is_active boolean not null default true,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table desk.teams is '{
    "icon": "UsersRound",
    "collapsible_group": "Organisation",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["is_active"]},
        "tabs": ["agents", "tickets", "canned_responses"]
    },
    "views": [
        {
            "id": "list",
            "name": "All Teams",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "business_hours",
            "field_2": "timezone"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "description", "color"]},
            {"id": "routing", "title": "Routing", "fields": ["mailbox", "is_active"]},
            {"id": "coverage", "title": "Coverage", "fields": ["business_hours", "timezone"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}]
    }
}';

revoke all on table desk.teams
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
delete on table desk.teams to "x-admin";

grant
select
  on table desk.teams to "agent";

create index idx_desk_teams_is_active on desk.teams (is_active);

alter table desk.teams enable row level security;

create policy teams_select on desk.teams for
select
  to authenticated using (true);

create policy teams_insert on desk.teams for insert to authenticated
with
  check (true);

create policy teams_update on desk.teams
for update
  to authenticated using (true)
with
  check (true);

create policy teams_delete on desk.teams for delete to authenticated using (true);

----------------------------------------------------------------
-- SLA policies (response/resolution targets per priority)
----------------------------------------------------------------
create table desk.sla_policies (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null unique,
  description text,
  priority desk.ticket_priority not null default 'normal',
  first_response_minutes integer not null default 240,
  resolution_minutes integer not null default 1440,
  business_hours_only boolean not null default true,
  escalate_to_team_id uuid references desk.teams (id) on delete set null,
  is_default boolean not null default false,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column desk.sla_policies.priority is '{
    "progress": true,
    "values": {
        "low": {"variant": "outline", "icon": "ArrowDown"},
        "normal": {"variant": "info", "icon": "Minus"},
        "high": {"variant": "warning", "icon": "ArrowUp"},
        "urgent": {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on table desk.sla_policies is '{
    "icon": "Timer",
    "collapsible_group": "Organisation",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["priority", "is_default"]},
        "tabs": ["tickets"]
    },
    "views": [
        {
            "id": "list",
            "name": "Policies",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "priority",
            "field_2": "resolution_minutes"
        }
    ],
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "description", "priority", "color"]},
            {"id": "targets", "title": "Targets", "fields": ["first_response_minutes", "resolution_minutes", "business_hours_only"]},
            {"id": "escalation", "title": "Escalation", "fields": ["escalate_to_team_id", "is_default"]}
        ]
    },
    "query": {
        "sort": [{"id": "resolution_minutes", "desc": false}],
        "join": [{"table": "teams", "on": "escalate_to_team_id", "columns": ["name", "mailbox"]}]
    }
}';

comment on column desk.sla_policies.first_response_minutes is '{"name": "First Response (min)", "aggregate": "avg"}';

comment on column desk.sla_policies.resolution_minutes is '{"name": "Resolution (min)", "aggregate": "avg"}';

revoke all on table desk.sla_policies
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
delete on table desk.sla_policies to "x-admin";

grant
select
  on table desk.sla_policies to "agent",
  "user";

create index idx_desk_sla_policies_priority on desk.sla_policies (priority);

create index idx_desk_sla_policies_escalate_to_team_id on desk.sla_policies (escalate_to_team_id);

alter table desk.sla_policies enable row level security;

create policy sla_policies_select on desk.sla_policies for
select
  to authenticated using (true);

create policy sla_policies_insert on desk.sla_policies for insert to authenticated
with
  check (true);

create policy sla_policies_update on desk.sla_policies
for update
  to authenticated using (true)
with
  check (true);

create policy sla_policies_delete on desk.sla_policies for delete to authenticated using (true);

----------------------------------------------------------------
-- Agents (support staff, org chart via manager_id)
----------------------------------------------------------------
create table desk.agents (
  id uuid primary key default extensions.uuid_generate_v4 (),
  user_id uuid references supasheet.users (id) on delete set null,
  team_id uuid references desk.teams (id) on delete set null,
  manager_id uuid references desk.agents (id) on delete set null,
  name varchar(255) not null,
  avatar supasheet.AVATAR,
  email supasheet.EMAIL,
  phone supasheet.TEL,
  job_title varchar(255),
  seniority desk.agent_seniority not null default 'associate',
  availability desk.agent_availability not null default 'available',
  bio supasheet.RICH_TEXT,
  signature text,
  hire_date date,
  max_open_tickets integer not null default 20,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column desk.agents.seniority is '{
    "progress": true,
    "values": {
        "associate": {"variant": "outline", "icon": "User"},
        "specialist": {"variant": "info", "icon": "UserCheck"},
        "senior": {"variant": "default", "icon": "UserStar"},
        "lead": {"variant": "success", "icon": "UserCog"},
        "manager": {"variant": "secondary", "icon": "Crown"}
    }
}';

comment on column desk.agents.availability is '{
    "progress": false,
    "values": {
        "available": {"variant": "success", "icon": "CircleCheck"},
        "busy": {"variant": "warning", "icon": "Loader"},
        "away": {"variant": "secondary", "icon": "Coffee"},
        "offline": {"variant": "outline", "icon": "PowerOff"}
    }
}';

comment on table desk.agents is '{
    "icon": "Headset",
    "collapsible_group": "Organisation",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["seniority", "availability"]},
        "tabs": ["tickets", "worklogs", "articles"]
    },
    "views": [
        {
            "id": "tree",
            "name": "Support Org Chart",
            "type": "tree",
            "parent": "manager_id",
            "title": "name",
            "secondary": "job_title"
        },
        {
            "id": "gallery",
            "name": "Agent Directory",
            "type": "gallery",
            "cover": "avatar",
            "title": "name",
            "description": "job_title",
            "badge": "availability"
        },
        {
            "id": "list",
            "name": "Roster",
            "type": "list",
            "title": "name",
            "description": "job_title",
            "field_1": "seniority",
            "field_2": "availability"
        }
    ],
    "filter_presets": [
        {"id": "available", "name": "Available", "filters": [{"id": "availability", "value": "available", "operator": "eq"}]},
        {"id": "leads", "name": "Leads & Managers", "filters": [{"id": "seniority", "value": ["lead", "manager"], "operator": "in"}]}
    ],
    "links": [
        {"id": "agents_report", "name": "Agent Performance", "url": "/desk/report/agents_report", "icon": "BarChart3", "description": "Ticket load, resolution and CSAT per agent"}
    ],
    "fields": {
        "quick_create": ["name", "email", "team_id", "job_title"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "avatar", "job_title", "seniority"]},
            {"id": "contact", "title": "Contact", "fields": ["email", "phone", "user_id"]},
            {"id": "assignment", "title": "Assignment", "fields": ["team_id", "manager_id", "availability", "max_open_tickets"]},
            {"id": "extras", "title": "Bio & signature", "collapsible": true, "fields": ["bio", "signature", "hire_date", "color"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [
            {"table": "users", "on": "user_id", "columns": ["name", "email"]},
            {"table": "teams", "on": "team_id", "columns": ["name", "color"]},
            {"table": "agents", "on": "manager_id", "alias": "manager", "columns": ["name", "job_title"]}
        ]
    }
}';

comment on column desk.agents.avatar is '{"accept": "image/*", "max_size": 2097152}';

comment on column desk.agents.max_open_tickets is '{"name": "Capacity", "aggregate": "sum"}';

revoke all on table desk.agents
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
delete on table desk.agents to "x-admin";

grant
select
,
update on table desk.agents to "agent";

create index idx_desk_agents_user_id on desk.agents (user_id);

create index idx_desk_agents_team_id on desk.agents (team_id);

create index idx_desk_agents_manager_id on desk.agents (manager_id);

create index idx_desk_agents_availability on desk.agents (availability);

create index idx_desk_agents_seniority on desk.agents (seniority);

alter table desk.agents enable row level security;

create policy agents_select on desk.agents for
select
  to authenticated using (true);

create policy agents_insert on desk.agents for insert to authenticated
with
  check (true);

create policy agents_update on desk.agents
for update
  to authenticated using (true)
with
  check (true);

create policy agents_delete on desk.agents for delete to authenticated using (true);

-- Teams gained a lead only after agents existed — adding the FK
-- afterwards is the normal pattern for a circular reference.
alter table desk.teams
add column lead_agent_id uuid references desk.agents (id) on delete set null;

create index idx_desk_teams_lead_agent_id on desk.teams (lead_agent_id);

----------------------------------------------------------------
-- Customers (accounts that raise tickets)
----------------------------------------------------------------
create table desk.customers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null,
  logo supasheet.file,
  website supasheet.URL,
  support_email supasheet.EMAIL,
  phone supasheet.TEL,
  tier desk.customer_tier not null default 'free',
  health desk.customer_health not null default 'healthy',
  industry varchar(255),
  country varchar(255),
  account_manager_id uuid references desk.agents (id) on delete set null,
  sla_policy_id uuid references desk.sla_policies (id) on delete set null,
  contract_value numeric(12, 2),
  onboarded_on date,
  tags varchar(500) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column desk.customers.tier is '{
    "progress": true,
    "values": {
        "free": {"variant": "outline", "icon": "Gift"},
        "starter": {"variant": "info", "icon": "Rocket"},
        "business": {"variant": "default", "icon": "Building2"},
        "enterprise": {"variant": "success", "icon": "Landmark"}
    }
}';

comment on column desk.customers.health is '{
    "progress": false,
    "values": {
        "healthy": {"variant": "success", "icon": "HeartPulse"},
        "watch": {"variant": "info", "icon": "Eye"},
        "at_risk": {"variant": "warning", "icon": "TriangleAlert"},
        "churned": {"variant": "destructive", "icon": "UserMinus"}
    }
}';

comment on table desk.customers is '{
    "icon": "Building2",
    "collapsible_group": "Accounts",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "name", "badges": ["tier", "health", "tags"]},
        "tabs": ["contacts", "tickets", "customer_billing"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Accounts By Health",
            "type": "kanban",
            "group": "health",
            "title": "name",
            "description": "industry",
            "date": "onboarded_on",
            "badge": "tier"
        },
        {
            "id": "gallery",
            "name": "Account Gallery",
            "type": "gallery",
            "cover": "logo",
            "title": "name",
            "description": "industry",
            "badge": "tier"
        }
    ],
    "filter_presets": [
        {"id": "at_risk", "name": "At Risk", "filters": [{"id": "health", "value": ["at_risk", "churned"], "operator": "in"}]},
        {"id": "enterprise", "name": "Enterprise", "filters": [{"id": "tier", "value": "enterprise", "operator": "eq"}]},
        {"id": "healthy", "name": "Healthy", "filters": [{"id": "health", "value": "healthy", "operator": "eq"}]}
    ],
    "links": [
        {"id": "customers_report", "name": "Account Report", "url": "/desk/report/customers_report", "icon": "BarChart3", "description": "Ticket volume and CSAT per account"}
    ],
    "fields": {
        "quick_create": ["name", "tier", "industry", "account_manager_id"],
        "sections": [
            {"id": "profile", "title": "Profile", "fields": ["name", "logo", "industry", "country"]},
            {"id": "contact", "title": "Contact", "fields": ["website", "support_email", "phone"]},
            {"id": "commercial", "title": "Commercial", "fields": ["tier", "health", "contract_value", "onboarded_on"]},
            {"id": "support", "title": "Support", "fields": ["account_manager_id", "sla_policy_id"]},
            {"id": "extras", "title": "Notes & tags", "collapsible": true, "fields": ["tags", "color", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [
            {"table": "users", "on": "user_id", "columns": ["name", "email"]},
            {"table": "agents", "on": "account_manager_id", "alias": "account_manager", "columns": ["name", "avatar"]},
            {"table": "sla_policies", "on": "sla_policy_id", "columns": ["name", "priority"]}
        ]
    }
}';

comment on column desk.customers.logo is '{"accept": "image/*", "max_size": 2097152}';

comment on column desk.customers.contract_value is '{"aggregate": "sum"}';

revoke all on table desk.customers
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
delete on table desk.customers to "x-admin";

grant
select
,
  insert,
update on table desk.customers to "agent";

create index idx_desk_customers_tier on desk.customers (tier);

create index idx_desk_customers_health on desk.customers (health);

create index idx_desk_customers_account_manager_id on desk.customers (account_manager_id);

create index idx_desk_customers_sla_policy_id on desk.customers (sla_policy_id);

create index idx_desk_customers_user_id on desk.customers (user_id);

create index idx_desk_customers_created_at on desk.customers (created_at desc);

alter table desk.customers enable row level security;

create policy customers_select on desk.customers for
select
  to authenticated using (true);

create policy customers_insert on desk.customers for insert to authenticated
with
  check (true);

create policy customers_update on desk.customers
for update
  to authenticated using (true)
with
  check (true);

create policy customers_delete on desk.customers for delete to authenticated using (true);

----------------------------------------------------------------
-- Customer billing (1:1 extension — a unique, not-null FK keeps
-- commercially sensitive data off the main account record; the UI
-- renders it as a single embedded record on the customer's detail
-- page, not a list. Granted to x-admin only, so agents never see it.)
----------------------------------------------------------------
create table desk.customer_billing (
  id uuid primary key default extensions.uuid_generate_v4 (),
  customer_id uuid not null references desk.customers (id) on delete cascade,
  billing_email supasheet.EMAIL,
  billing_address text,
  tax_id varchar(100),
  payment_terms varchar(50) not null default 'net_30',
  purchase_order_ref varchar(100),
  renewal_date date,
  auto_renew boolean not null default true,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (customer_id)
);

comment on table desk.customer_billing is '{
    "icon": "CreditCard",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "account", "title": "Account", "fields": ["customer_id", "billing_email", "billing_address"]},
            {"id": "terms", "title": "Terms", "fields": ["payment_terms", "purchase_order_ref", "tax_id"]},
            {"id": "renewal", "title": "Renewal", "fields": ["renewal_date", "auto_renew"]},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "join": [{"table": "customers", "on": "customer_id", "columns": ["name", "tier"]}]
    }
}';

revoke all on table desk.customer_billing
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
delete on table desk.customer_billing to "x-admin";

create index idx_desk_customer_billing_customer_id on desk.customer_billing (customer_id);

create index idx_desk_customer_billing_renewal_date on desk.customer_billing (renewal_date);

alter table desk.customer_billing enable row level security;

create policy customer_billing_select on desk.customer_billing for
select
  to authenticated using (true);

create policy customer_billing_insert on desk.customer_billing for insert to authenticated
with
  check (true);

create policy customer_billing_update on desk.customer_billing
for update
  to authenticated using (true)
with
  check (true);

create policy customer_billing_delete on desk.customer_billing for delete to authenticated using (true);

----------------------------------------------------------------
-- Contacts (people at a customer account)
----------------------------------------------------------------
create table desk.contacts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  customer_id uuid not null references desk.customers (id) on delete cascade,
  name varchar(255) not null,
  avatar supasheet.AVATAR,
  email supasheet.EMAIL not null,
  phone supasheet.TEL,
  job_title varchar(255),
  preferred_channel desk.ticket_channel not null default 'email',
  timezone varchar(100),
  is_primary boolean not null default false,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (customer_id, email)
);

comment on column desk.contacts.preferred_channel is '{
    "progress": false,
    "values": {
        "email": {"variant": "info", "icon": "Mail"},
        "web": {"variant": "default", "icon": "Globe"},
        "phone": {"variant": "warning", "icon": "Phone"},
        "chat": {"variant": "success", "icon": "MessageCircle"},
        "api": {"variant": "secondary", "icon": "Code2"}
    }
}';

comment on table desk.contacts is '{
    "icon": "Contact",
    "collapsible_group": "Accounts",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "name", "badges": ["preferred_channel", "is_primary"]},
        "tabs": ["tickets"]
    },
    "views": [
        {
            "id": "gallery",
            "name": "Contact Cards",
            "type": "gallery",
            "cover": "avatar",
            "title": "name",
            "description": "job_title",
            "badge": "preferred_channel"
        },
        {
            "id": "list",
            "name": "All Contacts",
            "type": "list",
            "title": "name",
            "description": "email",
            "field_1": "job_title",
            "field_2": "preferred_channel"
        }
    ],
    "filter_presets": [
        {"id": "primary", "name": "Primary Contacts", "filters": [{"id": "is_primary", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["name", "email", "customer_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "avatar", "job_title", "customer_id"]},
            {"id": "contact", "title": "Contact", "fields": ["email", "phone", "preferred_channel", "timezone"]},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["is_primary", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [{"table": "customers", "on": "customer_id", "columns": ["name", "tier"]}]
    }
}';

comment on column desk.contacts.avatar is '{"accept": "image/*", "max_size": 2097152}';

revoke all on table desk.contacts
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
delete on table desk.contacts to "x-admin";

grant
select
,
  insert,
update on table desk.contacts to "agent";

create index idx_desk_contacts_customer_id on desk.contacts (customer_id);

create index idx_desk_contacts_email on desk.contacts (email);

create index idx_desk_contacts_is_primary on desk.contacts (is_primary);

alter table desk.contacts enable row level security;

create policy contacts_select on desk.contacts for
select
  to authenticated using (true);

create policy contacts_insert on desk.contacts for insert to authenticated
with
  check (true);

create policy contacts_update on desk.contacts
for update
  to authenticated using (true)
with
  check (true);

create policy contacts_delete on desk.contacts for delete to authenticated using (true);

----------------------------------------------------------------
-- Categories (self-referencing taxonomy — tree view)
----------------------------------------------------------------
create table desk.categories (
  id uuid primary key default extensions.uuid_generate_v4 (),
  parent_id uuid references desk.categories (id) on delete cascade,
  name varchar(255) not null,
  slug varchar(255) not null unique,
  description text,
  default_team_id uuid references desk.teams (id) on delete set null,
  color supasheet.COLOR,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table desk.categories is '{
    "icon": "FolderTree",
    "collapsible_group": "Organisation",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["is_active"]},
        "tabs": ["tickets", "articles", "canned_responses"]
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
            "id": "list",
            "name": "All Categories",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "slug",
            "field_2": "sort_order"
        }
    ],
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "slug", "parent_id", "description"]},
            {"id": "routing", "title": "Routing", "fields": ["default_team_id", "is_active"]},
            {"id": "display", "title": "Display", "fields": ["color", "sort_order"]}
        ]
    },
    "query": {
        "sort": [{"id": "sort_order", "desc": false}],
        "join": [
            {"table": "categories", "on": "parent_id", "alias": "parent", "columns": ["name", "slug"]},
            {"table": "teams", "on": "default_team_id", "columns": ["name", "color"]}
        ]
    }
}';

revoke all on table desk.categories
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
delete on table desk.categories to "x-admin";

grant
select
  on table desk.categories to "agent",
  "user";

create index idx_desk_categories_parent_id on desk.categories (parent_id);

create index idx_desk_categories_default_team_id on desk.categories (default_team_id);

create index idx_desk_categories_sort_order on desk.categories (sort_order);

alter table desk.categories enable row level security;

create policy categories_select on desk.categories for
select
  to authenticated using (true);

create policy categories_insert on desk.categories for insert to authenticated
with
  check (true);

create policy categories_update on desk.categories
for update
  to authenticated using (true)
with
  check (true);

create policy categories_delete on desk.categories for delete to authenticated using (true);

----------------------------------------------------------------
-- Problems (known issues behind recurring tickets — gantt roadmap)
----------------------------------------------------------------
create table desk.problems (
  id uuid primary key default extensions.uuid_generate_v4 (),
  title varchar(255) not null,
  summary text,
  description supasheet.RICH_TEXT,
  status desk.problem_status not null default 'identified',
  impact desk.problem_impact not null default 'moderate',
  owner_id uuid references desk.agents (id) on delete set null,
  category_id uuid references desk.categories (id) on delete set null,
  started_on date not null default current_date,
  target_resolution_on date,
  resolved_on date,
  progress supasheet.PERCENTAGE not null default 0,
  workaround text,
  root_cause supasheet.RICH_TEXT,
  affected_customers integer not null default 0,
  tags varchar(500) [],
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column desk.problems.status is '{
    "progress": true,
    "values": {
        "identified": {"variant": "outline", "icon": "Search"},
        "investigating": {"variant": "info", "icon": "Microscope"},
        "fix_in_progress": {"variant": "warning", "icon": "Wrench"},
        "monitoring": {"variant": "default", "icon": "Activity"},
        "resolved": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on column desk.problems.impact is '{
    "progress": false,
    "values": {
        "minor": {"variant": "outline", "icon": "ArrowDown"},
        "moderate": {"variant": "info", "icon": "Minus"},
        "major": {"variant": "warning", "icon": "ArrowUp"},
        "critical": {"variant": "destructive", "icon": "Siren"}
    }
}';

comment on table desk.problems is '{
    "icon": "Bug",
    "collapsible_group": "Support",
    "display": "block",
    "primary_view": "gantt",
    "detail": {
        "header": {"title": "title", "badges": ["status", "impact", "tags"]},
        "tabs": ["tickets"]
    },
    "views": [
        {
            "id": "gantt",
            "name": "Problem Roadmap",
            "type": "gantt",
            "group": "status",
            "title": "title",
            "start_date": "started_on",
            "end_date": "target_resolution_on",
            "progress": "progress",
            "badge": "impact"
        },
        {
            "id": "kanban",
            "name": "Problems By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "summary",
            "date": "target_resolution_on",
            "badge": "impact"
        },
        {
            "id": "calendar",
            "name": "Target Dates",
            "type": "calendar",
            "title": "title",
            "badge": "status",
            "start_date": "started_on",
            "end_date": "target_resolution_on",
            "read_only": true
        }
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": "resolved", "operator": "neq"}]},
        {"id": "critical", "name": "Critical", "filters": [{"id": "impact", "value": ["major", "critical"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["title", "impact", "owner_id", "target_resolution_on"],
        "sections": [
            {"id": "overview", "title": "Overview", "fields": ["title", "summary", "description", "category_id"]},
            {"id": "status", "title": "Status", "fields": ["status", "impact", "progress", "owner_id"]},
            {"id": "schedule", "title": "Schedule", "fields": ["started_on", "target_resolution_on", "resolved_on"]},
            {"id": "analysis", "title": "Analysis", "collapsible": true, "fields": ["workaround", "root_cause", "affected_customers", "tags"]}
        ],
        "behavior": {
            "resolved_on": {
                "visible": [{"id": "status", "operator": "eq", "value": "resolved"}],
                "required": [{"id": "status", "operator": "eq", "value": "resolved"}]
            },
            "root_cause": {
                "visible": [{"id": "status", "operator": "in", "value": ["monitoring", "resolved"]}]
            }
        }
    },
    "query": {
        "sort": [{"id": "target_resolution_on", "desc": false}],
        "join": [
            {"table": "agents", "on": "owner_id", "alias": "owner", "columns": ["name", "avatar"]},
            {"table": "categories", "on": "category_id", "columns": ["name", "slug"]}
        ]
    }
}';

comment on column desk.problems.affected_customers is '{"aggregate": "sum"}';

comment on column desk.problems.progress is '{"aggregate": "avg"}';

revoke all on table desk.problems
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
delete on table desk.problems to "x-admin";

grant
select
,
  insert,
update on table desk.problems to "agent";

create index idx_desk_problems_status on desk.problems (status);

create index idx_desk_problems_impact on desk.problems (impact);

create index idx_desk_problems_owner_id on desk.problems (owner_id);

create index idx_desk_problems_category_id on desk.problems (category_id);

create index idx_desk_problems_target_resolution_on on desk.problems (target_resolution_on);

alter table desk.problems enable row level security;

create policy problems_select on desk.problems for
select
  to authenticated using (true);

create policy problems_insert on desk.problems for insert to authenticated
with
  check (true);

create policy problems_update on desk.problems
for update
  to authenticated using (true)
with
  check (true);

create policy problems_delete on desk.problems for delete to authenticated using (true);

----------------------------------------------------------------
-- Tickets (the core resource)
----------------------------------------------------------------
create sequence if not exists desk.ticket_number_seq;

create table desk.tickets (
  id uuid primary key default extensions.uuid_generate_v4 (),
  reference varchar(30) not null unique default (
    'TKT-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('desk.ticket_number_seq')::text, 5, '0')
  ),
  subject varchar(500) not null,
  description supasheet.RICH_TEXT,
  customer_id uuid references desk.customers (id) on delete set null,
  contact_id uuid references desk.contacts (id) on delete set null,
  category_id uuid references desk.categories (id) on delete set null,
  team_id uuid references desk.teams (id) on delete set null,
  assignee_id uuid references desk.agents (id) on delete set null,
  problem_id uuid references desk.problems (id) on delete set null,
  sla_policy_id uuid references desk.sla_policies (id) on delete set null,
  status desk.ticket_status not null default 'new',
  priority desk.ticket_priority not null default 'normal',
  channel desk.ticket_channel not null default 'email',
  ticket_type desk.ticket_type not null default 'question',
  on_hold_reason text,
  due_at timestamptz,
  first_response_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  reopen_count integer not null default 0,
  is_escalated boolean not null default false,
  sla_breached boolean not null default false,
  time_spent supasheet.DURATION not null default 0,
  satisfaction_score supasheet.RATING,
  attachments supasheet.file,
  tags varchar(500) [],
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column desk.tickets.status is '{
    "progress": true,
    "values": {
        "new": {"variant": "info", "icon": "Inbox"},
        "open": {"variant": "default", "icon": "CircleDot"},
        "pending": {"variant": "warning", "icon": "Hourglass"},
        "on_hold": {"variant": "secondary", "icon": "PauseCircle"},
        "resolved": {"variant": "success", "icon": "CircleCheck"},
        "closed": {"variant": "outline", "icon": "Archive"}
    }
}';

comment on column desk.tickets.priority is '{
    "progress": false,
    "icon_only": true,
    "values": {
        "low": {"variant": "outline", "icon": "ArrowDown"},
        "normal": {"variant": "info", "icon": "Minus"},
        "high": {"variant": "warning", "icon": "ArrowUp"},
        "urgent": {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on column desk.tickets.channel is '{
    "progress": false,
    "values": {
        "email": {"variant": "info", "icon": "Mail"},
        "web": {"variant": "default", "icon": "Globe"},
        "phone": {"variant": "warning", "icon": "Phone"},
        "chat": {"variant": "success", "icon": "MessageCircle"},
        "api": {"variant": "secondary", "icon": "Code2"}
    }
}';

comment on column desk.tickets.ticket_type is '{
    "progress": false,
    "values": {
        "question": {"variant": "info", "icon": "CircleHelp"},
        "incident": {"variant": "destructive", "icon": "Siren"},
        "problem": {"variant": "warning", "icon": "Bug"},
        "feature_request": {"variant": "default", "icon": "Lightbulb"},
        "task": {"variant": "outline", "icon": "ListTodo"}
    }
}';

comment on table desk.tickets is '{
    "icon": "Ticket",
    "collapsible_group": "Support",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "subject", "badges": ["status", "priority", "tags"]},
        "tabs": ["ticket_messages", "worklogs", "satisfaction_surveys", "ticket_watchers"],
        "timelines": ["ticket_events"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Support Board",
            "type": "kanban",
            "group": "status",
            "title": "subject",
            "description": "description",
            "date": "due_at",
            "badge": "priority"
        },
        {
            "id": "calendar",
            "name": "Due Dates",
            "type": "calendar",
            "title": "subject",
            "badge": "status",
            "start_date": "created_at",
            "end_date": "due_at",
            "read_only": true
        },
        {
            "id": "list",
            "name": "Queue",
            "type": "list",
            "title": "subject",
            "description": "reference",
            "field_1": "status",
            "field_2": "due_at"
        }
    ],
    "filter_presets": [
        {"id": "unassigned", "name": "Unassigned", "filters": [{"id": "assignee_id", "value": "null", "operator": "is"}]},
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["new", "open", "pending"], "operator": "in"}]},
        {"id": "escalated", "name": "Escalated", "filters": [{"id": "is_escalated", "value": "true", "operator": "eq"}]},
        {"id": "breached", "name": "SLA Breached", "filters": [{"id": "sla_breached", "value": "true", "operator": "eq"}]},
        {"id": "urgent", "name": "Urgent", "filters": [{"id": "priority", "value": ["high", "urgent"], "operator": "in"}]}
    ],
    "links": [
        {"id": "tickets_report", "name": "Ticket Report", "url": "/desk/report/tickets_report", "icon": "FileText", "description": "Full ticket export with account and agent context"},
        {"id": "sla_report", "name": "SLA Compliance", "url": "/desk/report/sla_compliance_report", "icon": "Timer", "description": "First response and resolution against target"}
    ],
    "fields": {
        "quick_create": ["subject", "customer_id", "contact_id", "priority", "category_id"],
        "sections": [
            {"id": "request", "title": "Request", "fields": ["subject", "description", "ticket_type", "channel"]},
            {"id": "requester", "title": "Requester", "fields": ["customer_id", "contact_id"]},
            {"id": "routing", "title": "Routing", "fields": ["category_id", "team_id", "assignee_id", "problem_id"]},
            {"id": "state", "title": "State", "fields": ["status", "priority", "is_escalated"]},
            {"id": "hold", "title": "On hold", "fields": ["on_hold_reason"]},
            {"id": "sla", "title": "SLA", "fields": {"create": ["sla_policy_id", "due_at"], "update": ["sla_policy_id", "due_at"], "read": ["sla_policy_id", "due_at", "first_response_at", "sla_breached"]}},
            {"id": "closure", "title": "Closure", "fields": {"update": ["resolved_at", "closed_at"], "read": ["resolved_at", "closed_at", "reopen_count"]}},
            {"id": "effort", "title": "Effort & feedback", "fields": {"update": ["time_spent"], "read": ["time_spent", "satisfaction_score"]}},
            {"id": "extras", "title": "Attachments & tags", "collapsible": true, "fields": ["attachments", "tags"]}
        ],
        "behavior": {
            "on_hold_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "on_hold"}],
                "required": [{"id": "status", "operator": "eq", "value": "on_hold"}]
            },
            "resolved_at": {"visible": [{"id": "status", "operator": "in", "value": ["resolved", "closed"]}]},
            "closed_at": {"visible": [{"id": "status", "operator": "eq", "value": "closed"}]},
            "due_at": {"read_only": [{"id": "status", "operator": "in", "value": ["resolved", "closed"]}]}
        },
        "lookups": {
            "contact_id": {"filter": [{"source_column": "customer_id", "target_column": "customer_id"}]},
            "sla_policy_id": {"fill": [{"source_column": "priority", "target_column": "priority"}]},
            "category_id": {"fill": [{"source_column": "team_id", "target_column": "default_team_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "users", "on": "user_id", "columns": ["name", "email"]},
            {"table": "customers", "on": "customer_id", "columns": ["name", "tier"]},
            {"table": "contacts", "on": "contact_id", "columns": ["name", "email"]},
            {"table": "agents", "on": "assignee_id", "alias": "assignee", "columns": ["name", "avatar"]},
            {"table": "teams", "on": "team_id", "columns": ["name", "color"]},
            {"table": "categories", "on": "category_id", "columns": ["name", "slug"]}
        ]
    }
}';

comment on column desk.tickets.attachments is '{"accept": "*", "max_files": 10, "max_size": 10485760}';

comment on column desk.tickets.time_spent is '{"name": "Time Spent", "aggregate": "sum"}';

comment on column desk.tickets.satisfaction_score is '{"name": "CSAT", "aggregate": "avg"}';

comment on column desk.tickets.reference is '{"name": "Ref", "icon": "Hash"}';

revoke all on table desk.tickets
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
delete on table desk.tickets to "x-admin";

grant
select
,
  insert,
update on table desk.tickets to "agent";

-- Requesters may file tickets and edit only the request fields.
grant
select
,
  insert on table desk.tickets to "user";

grant
update (subject, description, attachments, tags) on table desk.tickets to "user";

-- The `reference` default calls nextval(), so every role that can
-- insert a ticket also needs usage on the backing sequence.
revoke all on sequence desk.ticket_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence desk.ticket_number_seq to "x-admin",
"agent",
"user";

create index idx_desk_tickets_customer_id on desk.tickets (customer_id);

create index idx_desk_tickets_contact_id on desk.tickets (contact_id);

create index idx_desk_tickets_category_id on desk.tickets (category_id);

create index idx_desk_tickets_team_id on desk.tickets (team_id);

create index idx_desk_tickets_assignee_id on desk.tickets (assignee_id);

create index idx_desk_tickets_problem_id on desk.tickets (problem_id);

create index idx_desk_tickets_sla_policy_id on desk.tickets (sla_policy_id);

create index idx_desk_tickets_status on desk.tickets (status);

create index idx_desk_tickets_priority on desk.tickets (priority);

create index idx_desk_tickets_channel on desk.tickets (channel);

create index idx_desk_tickets_due_at on desk.tickets (due_at);

create index idx_desk_tickets_user_id on desk.tickets (user_id);

create index idx_desk_tickets_created_at on desk.tickets (created_at desc);

alter table desk.tickets enable row level security;

-- Ownership-scoped reads: a plain "user" sees only the tickets they
-- filed; agents and desk admins see the whole queue. Grants already
-- decided who may attempt the operation — this decides which rows.
create policy tickets_select on desk.tickets for
select
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'agent', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  );

create policy tickets_insert on desk.tickets for insert to authenticated
with
  check (true);

create policy tickets_update on desk.tickets
for update
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'agent', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy tickets_delete on desk.tickets for delete to authenticated using (true);

----------------------------------------------------------------
-- Ticket messages (threaded replies and internal notes — rendered
-- as a tab on the ticket detail page)
----------------------------------------------------------------
create table desk.ticket_messages (
  id uuid primary key default extensions.uuid_generate_v4 (),
  ticket_id uuid not null references desk.tickets (id) on delete cascade,
  author_agent_id uuid references desk.agents (id) on delete set null,
  author_contact_id uuid references desk.contacts (id) on delete set null,
  kind desk.message_kind not null default 'public_reply',
  body supasheet.RICH_TEXT not null,
  attachments supasheet.file,
  is_first_response boolean not null default false,
  sent_at timestamptz not null default current_timestamp,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp
);

comment on column desk.ticket_messages.kind is '{
    "progress": false,
    "values": {
        "public_reply": {"variant": "info", "icon": "Send"},
        "internal_note": {"variant": "warning", "icon": "StickyNote"},
        "system": {"variant": "outline", "icon": "Bot"}
    }
}';

comment on table desk.ticket_messages is '{
    "icon": "MessagesSquare",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "message", "title": "Message", "fields": ["ticket_id", "kind", "body"]},
            {"id": "author", "title": "Author", "fields": ["author_agent_id", "author_contact_id", "sent_at"]},
            {"id": "extras", "title": "Attachments", "collapsible": true, "fields": ["attachments"]}
        ],
        "behavior": {
            "author_contact_id": {"visible": [{"id": "kind", "operator": "eq", "value": "public_reply"}]}
        }
    },
    "query": {
        "sort": [{"id": "sent_at", "desc": false}],
        "join": [
            {"table": "tickets", "on": "ticket_id", "columns": ["reference", "subject", "status"]},
            {"table": "agents", "on": "author_agent_id", "alias": "agent_author", "columns": ["name", "avatar"]},
            {"table": "contacts", "on": "author_contact_id", "alias": "contact_author", "columns": ["name", "email"]}
        ]
    }
}';

comment on column desk.ticket_messages.attachments is '{"accept": "*", "max_files": 5, "max_size": 10485760}';

revoke all on table desk.ticket_messages
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
delete on table desk.ticket_messages to "x-admin";

grant
select
,
  insert,
update on table desk.ticket_messages to "agent";

grant
select
,
  insert on table desk.ticket_messages to "user";

create index idx_desk_ticket_messages_ticket_id on desk.ticket_messages (ticket_id);

create index idx_desk_ticket_messages_author_agent_id on desk.ticket_messages (author_agent_id);

create index idx_desk_ticket_messages_sent_at on desk.ticket_messages (sent_at desc);

alter table desk.ticket_messages enable row level security;

-- Internal notes stay internal: requesters only ever see public replies.
create policy ticket_messages_select on desk.ticket_messages for
select
  to authenticated using (
    kind <> 'internal_note'
    or pg_has_role(current_user, 'agent', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  );

create policy ticket_messages_insert on desk.ticket_messages for insert to authenticated
with
  check (true);

create policy ticket_messages_update on desk.ticket_messages
for update
  to authenticated using (true)
with
  check (true);

create policy ticket_messages_delete on desk.ticket_messages for delete to authenticated using (true);

----------------------------------------------------------------
-- Ticket events (system-generated activity timeline for a single
-- ticket — display: none, never browsable on its own; surfaced only
-- as the "ticket_events" timeline tab on that ticket's detail page)
----------------------------------------------------------------
create table desk.ticket_events (
  id uuid primary key default extensions.uuid_generate_v4 (),
  ticket_id uuid not null references desk.tickets (id) on delete cascade,
  event_type desk.ticket_event_type not null,
  title varchar(255) not null,
  metadata jsonb,
  actor_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  occurred_at timestamptz not null default current_timestamp
);

comment on column desk.ticket_events.event_type is '{
    "progress": false,
    "values": {
        "created": {"variant": "info", "icon": "Sparkles"},
        "status_changed": {"variant": "default", "icon": "ArrowRightLeft"},
        "assigned": {"variant": "secondary", "icon": "UserCog"},
        "priority_changed": {"variant": "warning", "icon": "Flag"},
        "escalated": {"variant": "destructive", "icon": "Siren"},
        "sla_breached": {"variant": "destructive", "icon": "TimerOff"},
        "reply_added": {"variant": "success", "icon": "Send"},
        "record_updated": {"variant": "outline", "icon": "RefreshCw"}
    }
}';

comment on table desk.ticket_events is '{
    "icon": "History",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "event", "title": "Event", "fields": ["ticket_id", "event_type", "title", "metadata", "actor_id", "occurred_at"]}
        ]
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [{"table": "users", "on": "actor_id", "alias": "actor", "columns": ["name", "email"]}]
    }
}';

revoke all on table desk.ticket_events
from
  public,
  anon,
  authenticated,
  service_role;

-- Select only — the feed is read-only by design (granting insert
-- would add a "New entry" button above the timeline).
grant
select
  on table desk.ticket_events to "x-admin",
  "agent";

create index idx_desk_ticket_events_ticket_id on desk.ticket_events (ticket_id);

create index idx_desk_ticket_events_occurred_at on desk.ticket_events (occurred_at desc);

alter table desk.ticket_events enable row level security;

create policy ticket_events_select on desk.ticket_events for
select
  to authenticated using (true);

----------------------------------------------------------------
-- Ticket watchers (many-to-many tickets <-> agents, inline form)
----------------------------------------------------------------
create table desk.ticket_watchers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  ticket_id uuid not null references desk.tickets (id) on delete cascade,
  agent_id uuid not null references desk.agents (id) on delete cascade,
  reason varchar(255),
  created_at timestamptz default current_timestamp,
  unique (ticket_id, agent_id)
);

comment on table desk.ticket_watchers is '{
    "icon": "Eye",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "link", "title": "Watcher", "fields": ["ticket_id", "agent_id", "reason"]}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "tickets", "on": "ticket_id", "columns": ["reference", "subject"]},
            {"table": "agents", "on": "agent_id", "columns": ["name", "avatar", "job_title"]}
        ]
    }
}';

revoke all on table desk.ticket_watchers
from
  public,
  anon,
  authenticated,
  service_role;

-- Junction table: no update grant, only link/unlink.
grant
select
,
  insert,
  delete on table desk.ticket_watchers to "x-admin",
  "agent";

create index idx_desk_ticket_watchers_ticket_id on desk.ticket_watchers (ticket_id);

create index idx_desk_ticket_watchers_agent_id on desk.ticket_watchers (agent_id);

alter table desk.ticket_watchers enable row level security;

create policy ticket_watchers_select on desk.ticket_watchers for
select
  to authenticated using (true);

create policy ticket_watchers_insert on desk.ticket_watchers for insert to authenticated
with
  check (true);

create policy ticket_watchers_delete on desk.ticket_watchers for delete to authenticated using (true);

----------------------------------------------------------------
-- Worklogs (agent time booked against a ticket)
----------------------------------------------------------------
create table desk.worklogs (
  id uuid primary key default extensions.uuid_generate_v4 (),
  ticket_id uuid not null references desk.tickets (id) on delete cascade,
  agent_id uuid references desk.agents (id) on delete set null,
  logged_on date not null default current_date,
  duration supasheet.DURATION not null,
  is_billable boolean not null default false,
  activity varchar(255),
  notes text,
  created_at timestamptz default current_timestamp
);

comment on table desk.worklogs is '{
    "icon": "Clock",
    "collapsible_group": "Support",
    "display": "block",
    "detail": {"header": {"title": "activity", "badges": ["is_billable"]}},
    "fields": {
        "quick_create": ["ticket_id", "agent_id", "duration"],
        "sections": [
            {"id": "entry", "title": "Entry", "fields": ["ticket_id", "agent_id", "logged_on"]},
            {"id": "effort", "title": "Effort", "fields": ["duration", "is_billable", "activity"]},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "logged_on", "desc": true}],
        "join": [
            {"table": "tickets", "on": "ticket_id", "columns": ["reference", "subject", "status"]},
            {"table": "agents", "on": "agent_id", "columns": ["name", "avatar"]}
        ]
    }
}';

comment on column desk.worklogs.duration is '{"aggregate": "sum"}';

revoke all on table desk.worklogs
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
delete on table desk.worklogs to "x-admin";

grant
select
,
  insert,
update on table desk.worklogs to "agent";

create index idx_desk_worklogs_ticket_id on desk.worklogs (ticket_id);

create index idx_desk_worklogs_agent_id on desk.worklogs (agent_id);

create index idx_desk_worklogs_logged_on on desk.worklogs (logged_on desc);

alter table desk.worklogs enable row level security;

create policy worklogs_select on desk.worklogs for
select
  to authenticated using (true);

create policy worklogs_insert on desk.worklogs for insert to authenticated
with
  check (true);

create policy worklogs_update on desk.worklogs
for update
  to authenticated using (true)
with
  check (true);

create policy worklogs_delete on desk.worklogs for delete to authenticated using (true);

----------------------------------------------------------------
-- Satisfaction surveys (CSAT — one per resolved ticket)
----------------------------------------------------------------
create table desk.satisfaction_surveys (
  id uuid primary key default extensions.uuid_generate_v4 (),
  ticket_id uuid not null references desk.tickets (id) on delete cascade,
  contact_id uuid references desk.contacts (id) on delete set null,
  rating supasheet.RATING not null,
  sentiment desk.survey_sentiment,
  comment text,
  responded_at timestamptz not null default current_timestamp,
  created_at timestamptz default current_timestamp,
  unique (ticket_id)
);

comment on column desk.satisfaction_surveys.sentiment is '{
    "progress": true,
    "values": {
        "detractor": {"variant": "destructive", "icon": "ThumbsDown"},
        "passive": {"variant": "warning", "icon": "Meh"},
        "promoter": {"variant": "success", "icon": "ThumbsUp"}
    }
}';

comment on table desk.satisfaction_surveys is '{
    "icon": "Star",
    "collapsible_group": "Support",
    "display": "block",
    "detail": {"header": {"title": "comment", "badges": ["sentiment"]}},
    "filter_presets": [
        {"id": "detractors", "name": "Detractors", "filters": [{"id": "sentiment", "value": "detractor", "operator": "eq"}]},
        {"id": "promoters", "name": "Promoters", "filters": [{"id": "sentiment", "value": "promoter", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "response", "title": "Response", "fields": ["ticket_id", "contact_id", "rating"]},
            {"id": "feedback", "title": "Feedback", "fields": {"create": ["comment"], "update": ["comment", "responded_at"], "read": ["sentiment", "comment", "responded_at"]}}
        ]
    },
    "query": {
        "sort": [{"id": "responded_at", "desc": true}],
        "join": [
            {"table": "tickets", "on": "ticket_id", "columns": ["reference", "subject"]},
            {"table": "contacts", "on": "contact_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column desk.satisfaction_surveys.rating is '{"aggregate": "avg"}';

revoke all on table desk.satisfaction_surveys
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
delete on table desk.satisfaction_surveys to "x-admin";

grant
select
  on table desk.satisfaction_surveys to "agent";

grant
select
,
  insert on table desk.satisfaction_surveys to "user";

create index idx_desk_satisfaction_surveys_ticket_id on desk.satisfaction_surveys (ticket_id);

create index idx_desk_satisfaction_surveys_contact_id on desk.satisfaction_surveys (contact_id);

create index idx_desk_satisfaction_surveys_sentiment on desk.satisfaction_surveys (sentiment);

alter table desk.satisfaction_surveys enable row level security;

create policy satisfaction_surveys_select on desk.satisfaction_surveys for
select
  to authenticated using (true);

create policy satisfaction_surveys_insert on desk.satisfaction_surveys for insert to authenticated
with
  check (true);

create policy satisfaction_surveys_update on desk.satisfaction_surveys
for update
  to authenticated using (true)
with
  check (true);

create policy satisfaction_surveys_delete on desk.satisfaction_surveys for delete to authenticated using (true);

----------------------------------------------------------------
-- Knowledge base articles (gallery is the natural default — a
-- visual grid of help content, like a public help centre)
----------------------------------------------------------------
create table desk.articles (
  id uuid primary key default extensions.uuid_generate_v4 (),
  title varchar(255) not null,
  slug varchar(255) not null unique,
  summary text,
  body supasheet.RICH_TEXT,
  cover supasheet.file,
  category_id uuid references desk.categories (id) on delete set null,
  author_id uuid references desk.agents (id) on delete set null,
  status desk.article_status not null default 'draft',
  is_public boolean not null default false,
  published_at date,
  view_count integer not null default 0,
  helpful_count integer not null default 0,
  average_rating supasheet.RATING,
  tags varchar(500) [],
  color supasheet.COLOR,
  sort_order integer not null default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column desk.articles.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "outline", "icon": "FileEdit"},
        "in_review": {"variant": "warning", "icon": "Eye"},
        "published": {"variant": "success", "icon": "Globe"},
        "archived": {"variant": "secondary", "icon": "Archive"}
    }
}';

comment on table desk.articles is '{
    "icon": "BookOpen",
    "collapsible_group": "Knowledge",
    "display": "block",
    "primary_view": "gallery",
    "detail": {"header": {"title": "title", "badges": ["status", "tags"]}},
    "views": [
        {
            "id": "gallery",
            "name": "Help Centre",
            "type": "gallery",
            "cover": "cover",
            "title": "title",
            "description": "summary",
            "badge": "status"
        },
        {
            "id": "list",
            "name": "All Articles",
            "type": "list",
            "title": "title",
            "description": "summary",
            "field_1": "status",
            "field_2": "published_at"
        },
        {
            "id": "kanban",
            "name": "Editorial Board",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "summary",
            "date": "published_at",
            "badge": "status"
        }
    ],
    "filter_presets": [
        {"id": "published", "name": "Published", "filters": [{"id": "status", "value": "published", "operator": "eq"}]},
        {"id": "drafts", "name": "Drafts", "filters": [{"id": "status", "value": ["draft", "in_review"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["title", "slug", "category_id", "author_id"],
        "sections": [
            {"id": "overview", "title": "Overview", "fields": ["title", "slug", "cover", "category_id", "author_id"]},
            {"id": "content", "title": "Content", "fields": ["summary", "body"]},
            {"id": "publishing", "title": "Publishing", "fields": ["status", "is_public", "published_at", "sort_order"]},
            {"id": "engagement", "title": "Engagement", "fields": {"read": ["view_count", "helpful_count", "average_rating"]}},
            {"id": "extras", "title": "Tags", "collapsible": true, "fields": ["tags", "color"]}
        ],
        "behavior": {
            "published_at": {
                "visible": [{"id": "status", "operator": "eq", "value": "published"}],
                "required": [{"id": "status", "operator": "eq", "value": "published"}]
            }
        }
    },
    "query": {
        "sort": [{"id": "sort_order", "desc": false}],
        "join": [
            {"table": "categories", "on": "category_id", "columns": ["name", "slug"]},
            {"table": "agents", "on": "author_id", "alias": "author", "columns": ["name", "avatar"]}
        ]
    }
}';

comment on column desk.articles.cover is '{"accept": "image/*", "max_size": 5242880}';

comment on column desk.articles.view_count is '{"aggregate": "sum"}';

comment on column desk.articles.average_rating is '{"aggregate": "avg"}';

revoke all on table desk.articles
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
delete on table desk.articles to "x-admin";

grant
select
,
  insert,
update on table desk.articles to "agent";

grant
select
  on table desk.articles to "user";

create index idx_desk_articles_category_id on desk.articles (category_id);

create index idx_desk_articles_author_id on desk.articles (author_id);

create index idx_desk_articles_status on desk.articles (status);

create index idx_desk_articles_is_public on desk.articles (is_public);

create index idx_desk_articles_sort_order on desk.articles (sort_order);

alter table desk.articles enable row level security;

-- Requesters only ever reach published, public articles.
create policy articles_select on desk.articles for
select
  to authenticated using (
    (
      status = 'published'
      and is_public
    )
    or pg_has_role(current_user, 'agent', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  );

create policy articles_insert on desk.articles for insert to authenticated
with
  check (true);

create policy articles_update on desk.articles
for update
  to authenticated using (true)
with
  check (true);

create policy articles_delete on desk.articles for delete to authenticated using (true);

----------------------------------------------------------------
-- Canned responses (reusable reply snippets)
----------------------------------------------------------------
create table desk.canned_responses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  title varchar(255) not null,
  shortcut varchar(50) not null unique,
  body supasheet.RICH_TEXT not null,
  category_id uuid references desk.categories (id) on delete set null,
  team_id uuid references desk.teams (id) on delete set null,
  usage_count integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table desk.canned_responses is '{
    "icon": "MessageSquareQuote",
    "collapsible_group": "Knowledge",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "title", "badges": ["is_active"]}},
    "views": [
        {
            "id": "list",
            "name": "Snippets",
            "type": "list",
            "title": "title",
            "description": "shortcut",
            "field_1": "usage_count",
            "field_2": "is_active"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["title", "shortcut", "is_active"]},
            {"id": "content", "title": "Content", "fields": ["body"]},
            {"id": "scope", "title": "Scope", "fields": ["category_id", "team_id"]},
            {"id": "usage", "title": "Usage", "fields": {"read": ["usage_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "usage_count", "desc": true}],
        "join": [
            {"table": "categories", "on": "category_id", "columns": ["name", "slug"]},
            {"table": "teams", "on": "team_id", "columns": ["name", "color"]}
        ]
    }
}';

comment on column desk.canned_responses.usage_count is '{"aggregate": "sum"}';

revoke all on table desk.canned_responses
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
delete on table desk.canned_responses to "x-admin";

grant
select
,
  insert,
update on table desk.canned_responses to "agent";

create index idx_desk_canned_responses_category_id on desk.canned_responses (category_id);

create index idx_desk_canned_responses_team_id on desk.canned_responses (team_id);

create index idx_desk_canned_responses_is_active on desk.canned_responses (is_active);

alter table desk.canned_responses enable row level security;

create policy canned_responses_select on desk.canned_responses for
select
  to authenticated using (true);

create policy canned_responses_insert on desk.canned_responses for insert to authenticated
with
  check (true);

create policy canned_responses_update on desk.canned_responses
for update
  to authenticated using (true)
with
  check (true);

create policy canned_responses_delete on desk.canned_responses for delete to authenticated using (true);

----------------------------------------------------------------
-- Desk settings (singleton — one row only, no delete grant)
----------------------------------------------------------------
create table desk.desk_settings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  workspace_name varchar(255) not null default 'Supasheet Desk',
  logo supasheet.file,
  brand_color supasheet.COLOR default '#0ea5e9',
  support_email supasheet.EMAIL,
  reply_from_name varchar(255) not null default 'Support Team',
  default_sla_policy_id uuid references desk.sla_policies (id) on delete set null,
  auto_close_after_days integer not null default 7,
  satisfaction_survey_enabled boolean not null default true,
  business_hours varchar(100) not null default '09:00-17:00',
  timezone varchar(100) not null default 'UTC',
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table desk.desk_settings is '{
    "icon": "Settings",
    "name": "Desk Settings",
    "collapsible_group": "Organisation",
    "display": "block",
    "singleton": true,
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["workspace_name", "logo", "brand_color"]},
            {"id": "email", "title": "Outbound email", "fields": ["support_email", "reply_from_name"]},
            {"id": "policy", "title": "Policy", "fields": ["default_sla_policy_id", "auto_close_after_days", "satisfaction_survey_enabled"]},
            {"id": "coverage", "title": "Coverage", "fields": ["business_hours", "timezone"]}
        ]
    },
    "query": {
        "join": [{"table": "sla_policies", "on": "default_sla_policy_id", "columns": ["name", "priority"]}]
    }
}';

comment on column desk.desk_settings.logo is '{"accept": "image/*", "max_size": 2097152}';

revoke all on table desk.desk_settings
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
update on table desk.desk_settings to "x-admin";

grant
select
  on table desk.desk_settings to "agent";

alter table desk.desk_settings enable row level security;

create policy desk_settings_select on desk.desk_settings for
select
  to authenticated using (true);

create policy desk_settings_insert on desk.desk_settings for insert to authenticated
with
  check (true);

create policy desk_settings_update on desk.desk_settings
for update
  to authenticated using (true)
with
  check (true);

----------------------------------------------------------------
-- Business triggers
----------------------------------------------------------------
-- Derive the SLA due date, closure timestamps, reopen counter and
-- breach flag directly from the ticket's own state.
create or replace function desk.trg_tickets_apply_defaults () returns trigger as $$
declare
    v_resolution_minutes integer;
begin
    if tg_op = 'INSERT' then
        if new.sla_policy_id is null then
            -- Tightest matching policy wins when several share a
            -- priority; the default policy always wins outright.
            select id into new.sla_policy_id
            from desk.sla_policies
            where priority = new.priority
            order by is_default desc, resolution_minutes asc, name asc
            limit 1;
        end if;

        if new.due_at is null and new.sla_policy_id is not null then
            select resolution_minutes into v_resolution_minutes
            from desk.sla_policies
            where id = new.sla_policy_id;

            new.due_at := coalesce(new.created_at, current_timestamp)
                        + make_interval(mins => coalesce(v_resolution_minutes, 1440));
        end if;

        if new.team_id is null and new.category_id is not null then
            select default_team_id into new.team_id
            from desk.categories
            where id = new.category_id;
        end if;
    else
        -- Resolution / closure stamps
        if new.status in ('resolved', 'closed') and old.status not in ('resolved', 'closed') then
            new.resolved_at := coalesce(new.resolved_at, current_timestamp);
        end if;

        if new.status = 'closed' and old.status <> 'closed' then
            new.closed_at := coalesce(new.closed_at, current_timestamp);
        end if;

        -- Reopening clears the closure stamps and bumps the counter
        if old.status in ('resolved', 'closed') and new.status not in ('resolved', 'closed') then
            new.reopen_count := old.reopen_count + 1;
            new.resolved_at := null;
            new.closed_at := null;
        end if;

        if new.status <> 'on_hold' then
            new.on_hold_reason := null;
        end if;
    end if;

    -- A ticket is breached once it passes its due date without being resolved.
    new.sla_breached := new.due_at is not null
                    and new.status not in ('resolved', 'closed')
                    and new.due_at < current_timestamp;

    new.updated_at := current_timestamp;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger tickets_apply_defaults
before insert or update on desk.tickets for each row
execute function desk.trg_tickets_apply_defaults ();

-- Stamp the first agent reply onto the parent ticket, move a "new"
-- ticket into "open", and log the reply on the timeline.
create or replace function desk.trg_ticket_messages_after () returns trigger as $$
declare
    v_ticket desk.tickets%rowtype;
begin
    select * into v_ticket from desk.tickets where id = new.ticket_id;

    if v_ticket.id is null then
        return new;
    end if;

    if new.kind = 'public_reply' and new.author_agent_id is not null then
        if v_ticket.first_response_at is null then
            update desk.tickets
            set first_response_at = new.sent_at,
                status = case when status = 'new' then 'open'::desk.ticket_status else status end
            where id = new.ticket_id;

            update desk.ticket_messages set is_first_response = true where id = new.id;
        end if;
    end if;

    insert into desk.ticket_events (ticket_id, event_type, title, metadata, actor_id, occurred_at)
    values (
        new.ticket_id,
        'reply_added',
        case new.kind
            when 'internal_note' then 'Internal note added'
            when 'system' then 'System message'
            else 'Reply sent'
        end,
        jsonb_build_object('kind', new.kind, 'message_id', new.id),
        new.user_id,
        new.sent_at
    );

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger ticket_messages_after
after insert on desk.ticket_messages for each row
execute function desk.trg_ticket_messages_after ();

-- Keep tickets.time_spent in sync with its worklogs.
create or replace function desk.trg_worklogs_rollup () returns trigger as $$
declare
    v_ticket_id uuid := coalesce(new.ticket_id, old.ticket_id);
begin
    update desk.tickets
    set time_spent = coalesce((
            select sum(duration) from desk.worklogs where ticket_id = v_ticket_id
        ), 0)
    where id = v_ticket_id;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger worklogs_rollup
after insert or update or delete on desk.worklogs for each row
execute function desk.trg_worklogs_rollup ();

-- Derive CSAT sentiment and mirror the score onto the ticket.
create or replace function desk.trg_satisfaction_rollup () returns trigger as $$
begin
    new.sentiment := case
        when new.rating >= 4 then 'promoter'::desk.survey_sentiment
        when new.rating >= 3 then 'passive'::desk.survey_sentiment
        else 'detractor'::desk.survey_sentiment
    end;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger satisfaction_sentiment
before insert or update of rating on desk.satisfaction_surveys for each row
execute function desk.trg_satisfaction_rollup ();

create or replace function desk.trg_satisfaction_apply_to_ticket () returns trigger as $$
begin
    update desk.tickets
    set satisfaction_score = new.rating
    where id = new.ticket_id;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger satisfaction_apply_to_ticket
after insert or update of rating on desk.satisfaction_surveys for each row
execute function desk.trg_satisfaction_apply_to_ticket ();

-- Timeline: one event per meaningful ticket change.
create or replace function desk.trg_tickets_log_event () returns trigger as $$
begin
    if tg_op = 'INSERT' then
        insert into desk.ticket_events (ticket_id, event_type, title, metadata, actor_id)
        values (
            new.id,
            'created',
            'Ticket ' || new.reference || ' created',
            jsonb_build_object('channel', new.channel, 'priority', new.priority),
            new.user_id
        );
        return new;
    end if;

    if new.is_escalated and not old.is_escalated then
        insert into desk.ticket_events (ticket_id, event_type, title, metadata)
        values (new.id, 'escalated', 'Ticket escalated', jsonb_build_object('priority', new.priority));
    elsif new.sla_breached and not old.sla_breached then
        insert into desk.ticket_events (ticket_id, event_type, title, metadata)
        values (new.id, 'sla_breached', 'SLA target missed', jsonb_build_object('due_at', new.due_at));
    elsif new.status is distinct from old.status then
        insert into desk.ticket_events (ticket_id, event_type, title, metadata)
        values (
            new.id,
            'status_changed',
            'Status changed to ' || new.status,
            jsonb_build_object('from', old.status, 'to', new.status)
        );
    elsif new.assignee_id is distinct from old.assignee_id then
        insert into desk.ticket_events (ticket_id, event_type, title, metadata)
        values (
            new.id,
            'assigned',
            'Assignee changed',
            jsonb_build_object('from', old.assignee_id, 'to', new.assignee_id)
        );
    elsif new.priority is distinct from old.priority then
        insert into desk.ticket_events (ticket_id, event_type, title, metadata)
        values (
            new.id,
            'priority_changed',
            'Priority changed to ' || new.priority,
            jsonb_build_object('from', old.priority, 'to', new.priority)
        );
    else
        insert into desk.ticket_events (ticket_id, event_type, title)
        values (new.id, 'record_updated', 'Ticket updated');
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger tickets_log_event
after insert or update on desk.tickets for each row
execute function desk.trg_tickets_log_event ();

-- Keep updated_at fresh on the remaining editable tables.
create trigger teams_set_updated_at
before update on desk.teams for each row
execute function supasheet.set_updated_at ();

create trigger sla_policies_set_updated_at
before update on desk.sla_policies for each row
execute function supasheet.set_updated_at ();

create trigger agents_set_updated_at
before update on desk.agents for each row
execute function supasheet.set_updated_at ();

create trigger customers_set_updated_at
before update on desk.customers for each row
execute function supasheet.set_updated_at ();

create trigger customer_billing_set_updated_at
before update on desk.customer_billing for each row
execute function supasheet.set_updated_at ();

create trigger contacts_set_updated_at
before update on desk.contacts for each row
execute function supasheet.set_updated_at ();

create trigger categories_set_updated_at
before update on desk.categories for each row
execute function supasheet.set_updated_at ();

create trigger problems_set_updated_at
before update on desk.problems for each row
execute function supasheet.set_updated_at ();

create trigger articles_set_updated_at
before update on desk.articles for each row
execute function supasheet.set_updated_at ();

create trigger canned_responses_set_updated_at
before update on desk.canned_responses for each row
execute function supasheet.set_updated_at ();

create trigger desk_settings_set_updated_at
before update on desk.desk_settings for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Row action: resolve a ticket
----------------------------------------------------------------
create or replace function desk.resolve_ticket (p_id uuid, p_resolution text default null) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_status desk.ticket_status;
begin
  select status into v_status from desk.tickets where id = p_id;

  if v_status is null then
    raise exception 'Ticket not found';
  end if;

  if v_status in ('resolved', 'closed') then
    raise exception 'Ticket is already %', v_status;
  end if;

  update desk.tickets
  set status = 'resolved',
      resolved_at = current_timestamp
  where id = p_id;

  if p_resolution is not null then
    insert into desk.ticket_messages (ticket_id, kind, body)
    values (p_id, 'system', p_resolution);
  end if;
end;
$$;

comment on function desk.resolve_ticket (uuid, text) is '{
    "type": "action",
    "resource": "tickets",
    "name": "Resolve",
    "description": "Mark this ticket as resolved and stamp the resolution time",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "not.in", "value": ["resolved", "closed"]}],
    "confirm": {"title": "Resolve this ticket?", "description": "The requester will be asked to rate the interaction."},
    "success_message": "Ticket resolved"
}';

revoke all on function desk.resolve_ticket (uuid, text)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function desk.resolve_ticket (uuid, text) to "x-admin",
"agent";

----------------------------------------------------------------
-- Row action: reopen a resolved/closed ticket
----------------------------------------------------------------
create or replace function desk.reopen_ticket (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update desk.tickets
  set status = 'open'
  where id = p_id
    and status in ('resolved', 'closed');

  if not found then
    raise exception 'Only resolved or closed tickets can be reopened';
  end if;
end;
$$;

comment on function desk.reopen_ticket (uuid) is '{
    "type": "action",
    "resource": "tickets",
    "name": "Reopen",
    "description": "Put a resolved or closed ticket back into the queue",
    "icon": "RotateCcw",
    "visible": [{"id": "status", "operator": "in", "value": ["resolved", "closed"]}],
    "success_message": "Ticket reopened"
}';

revoke all on function desk.reopen_ticket (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function desk.reopen_ticket (uuid) to "x-admin",
"agent";

----------------------------------------------------------------
-- Row action: escalate a ticket to its SLA policy's escalation team
----------------------------------------------------------------
create or replace function desk.escalate_ticket (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_team_id uuid;
begin
  select p.escalate_to_team_id into v_team_id
  from desk.tickets t
  left join desk.sla_policies p on p.id = t.sla_policy_id
  where t.id = p_id;

  update desk.tickets
  set is_escalated = true,
      priority = 'urgent',
      team_id = coalesce(v_team_id, team_id)
  where id = p_id
    and not is_escalated;

  if not found then
    raise exception 'Ticket not found or already escalated';
  end if;
end;
$$;

comment on function desk.escalate_ticket (uuid) is '{
    "type": "action",
    "resource": "tickets",
    "name": "Escalate",
    "description": "Raise to urgent and route to the escalation team",
    "icon": "Siren",
    "variant": "destructive",
    "visible": [{"id": "is_escalated", "operator": "eq", "value": "false"}],
    "confirm": {"title": "Escalate this ticket?", "description": "Priority becomes urgent and the escalation team is notified."},
    "success_message": "Ticket escalated"
}';

revoke all on function desk.escalate_ticket (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function desk.escalate_ticket (uuid) to "x-admin",
"agent";

----------------------------------------------------------------
-- Row action: set a ticket's priority (enum value-picker)
----------------------------------------------------------------
create or replace function desk.set_ticket_priority (p_id uuid, p_priority desk.ticket_priority) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update desk.tickets set priority = p_priority where id = p_id;
end;
$$;

comment on function desk.set_ticket_priority (uuid, desk.ticket_priority) is '{
    "type": "action",
    "resource": "tickets",
    "name": "Set priority",
    "icon": "Flag",
    "action_type": "picker"
}';

revoke all on function desk.set_ticket_priority (uuid, desk.ticket_priority)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function desk.set_ticket_priority (uuid, desk.ticket_priority) to "x-admin",
"agent";

----------------------------------------------------------------
-- Row action: publish a knowledge base article
----------------------------------------------------------------
create or replace function desk.publish_article (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update desk.articles
  set status = 'published',
      is_public = true,
      published_at = coalesce(published_at, current_date)
  where id = p_id
    and status <> 'published';

  if not found then
    raise exception 'Article not found or already published';
  end if;
end;
$$;

comment on function desk.publish_article (uuid) is '{
    "type": "action",
    "resource": "articles",
    "name": "Publish",
    "description": "Make this article visible in the public help centre",
    "icon": "Globe",
    "visible": [{"id": "status", "operator": "neq", "value": "published"}],
    "success_message": "Article published"
}';

revoke all on function desk.publish_article (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function desk.publish_article (uuid) to "x-admin",
"agent";

----------------------------------------------------------------
-- Custom form: log work against a ticket (listed on the "tickets"
-- resource overview). Returns a scalar uuid — the UI toasts and
-- refreshes.
----------------------------------------------------------------
create or replace function desk.log_ticket_work (
  p_ticket_id uuid,
  p_agent_id uuid,
  p_duration supasheet.DURATION,
  p_is_billable boolean default false,
  p_activity varchar default null,
  p_notes text default null
) returns uuid language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_id uuid;
begin
  insert into desk.worklogs (ticket_id, agent_id, duration, is_billable, activity, notes)
  values (p_ticket_id, p_agent_id, p_duration, p_is_billable, p_activity, p_notes)
  returning id into v_id;

  return v_id;
end;
$$;

comment on function desk.log_ticket_work (
  uuid,
  uuid,
  supasheet.DURATION,
  boolean,
  varchar,
  text
) is '{
    "type": "form",
    "resource": "tickets",
    "name": "Log work",
    "description": "Book time against a ticket without leaving the board.",
    "icon": "Clock",
    "success_message": "Work logged",
    "fields": {
        "sections": [
            {"id": "entry", "title": "Entry", "fields": ["p_ticket_id", "p_agent_id"]},
            {"id": "effort", "title": "Effort", "fields": ["p_duration", "p_is_billable", "p_activity", "p_notes"]}
        ],
        "relations": {
            "p_ticket_id": {"table": "tickets", "column": "id", "display": ["reference", "subject"]},
            "p_agent_id": {"table": "agents", "column": "id", "display": ["name", "job_title"]}
        }
    }
}';

revoke all on function desk.log_ticket_work (
  uuid,
  uuid,
  supasheet.DURATION,
  boolean,
  varchar,
  text
)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function desk.log_ticket_work (
  uuid,
  uuid,
  supasheet.DURATION,
  boolean,
  varchar,
  text
) to "x-admin",
"agent";

----------------------------------------------------------------
-- Custom form: open a ticket on behalf of a customer (listed on the
-- "customers" resource overview). Returns a single object row via
-- explicit OUT parameters — the UI renders the created record as a
-- detail card.
----------------------------------------------------------------
create or replace function desk.open_ticket_for_customer (
  p_customer_id uuid,
  p_subject varchar,
  p_contact_id uuid default null,
  p_category_id uuid default null,
  p_priority desk.ticket_priority default 'normal',
  p_description text default null,
  out ticket_id uuid,
  out reference varchar,
  out subject varchar,
  out customer_id uuid,
  out status desk.ticket_status,
  out priority desk.ticket_priority,
  out due_at timestamptz
) language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_ticket desk.tickets%rowtype;
begin
  if not exists (select 1 from desk.customers where id = p_customer_id) then
    raise exception 'Customer not found';
  end if;

  insert into desk.tickets (customer_id, contact_id, category_id, subject, description, priority, channel)
  values (p_customer_id, p_contact_id, p_category_id, p_subject, p_description, p_priority, 'phone')
  returning * into v_ticket;

  ticket_id := v_ticket.id;
  reference := v_ticket.reference;
  subject := v_ticket.subject;
  customer_id := v_ticket.customer_id;
  status := v_ticket.status;
  priority := v_ticket.priority;
  due_at := v_ticket.due_at;
end;
$$;

comment on function desk.open_ticket_for_customer (
  uuid,
  varchar,
  uuid,
  uuid,
  desk.ticket_priority,
  text
) is '{
    "type": "form",
    "resource": "customers",
    "name": "Open a ticket",
    "description": "File a ticket on behalf of this account — e.g. after a phone call.",
    "icon": "TicketPlus",
    "success_message": "Ticket opened",
    "fields": {
        "sections": [
            {"id": "account", "title": "Account", "fields": ["p_customer_id", "p_contact_id"]},
            {"id": "request", "title": "Request", "fields": ["p_subject", "p_description", "p_category_id", "p_priority"]}
        ],
        "relations": {
            "p_customer_id": {"table": "customers", "column": "id", "display": ["name", "tier"]},
            "p_contact_id": {"table": "contacts", "column": "id", "display": ["name", "email"]},
            "p_category_id": {"table": "categories", "column": "id", "display": ["name"]}
        }
    }
}';

revoke all on function desk.open_ticket_for_customer (
  uuid,
  varchar,
  uuid,
  uuid,
  desk.ticket_priority,
  text
)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function desk.open_ticket_for_customer (
  uuid,
  varchar,
  uuid,
  uuid,
  desk.ticket_priority,
  text
) to "x-admin",
"agent";

----------------------------------------------------------------
-- Custom form: hand a departing agent's open queue to someone else
-- (listed on the "agents" resource overview). Returns
-- setof desk.tickets — the UI renders the moved rows as a table.
----------------------------------------------------------------
create or replace function desk.bulk_reassign_tickets (p_from_agent_id uuid, p_to_agent_id uuid) returns setof desk.tickets language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_from_agent_id = p_to_agent_id then
    raise exception 'Source and target agent must differ';
  end if;

  return query
  update desk.tickets
  set assignee_id = p_to_agent_id
  where assignee_id = p_from_agent_id
    and status not in ('resolved', 'closed')
  returning *;
end;
$$;

comment on function desk.bulk_reassign_tickets (uuid, uuid) is '{
    "type": "form",
    "resource": "agents",
    "name": "Reassign queue",
    "description": "Move every open ticket from one agent to another.",
    "icon": "ArrowRightLeft",
    "success_message": "Queue reassigned",
    "fields": {
        "sections": [
            {"id": "handover", "title": "Handover", "fields": ["p_from_agent_id", "p_to_agent_id"]}
        ],
        "relations": {
            "p_from_agent_id": {"table": "agents", "column": "id", "display": ["name", "job_title"]},
            "p_to_agent_id": {"table": "agents", "column": "id", "display": ["name", "job_title"]}
        }
    }
}';

revoke all on function desk.bulk_reassign_tickets (uuid, uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function desk.bulk_reassign_tickets (uuid, uuid) to "x-admin";

----------------------------------------------------------------
-- Custom form: preview a team's current workload (listed on the
-- "teams" resource overview). Pure computation — no writes.
-- Returns setof rows via an explicit table(...) column list.
----------------------------------------------------------------
create or replace function desk.preview_team_workload (
  p_team_id uuid,
  p_include_resolved boolean default false
) returns table (
  agent_name varchar,
  open_tickets bigint,
  breached_tickets bigint,
  hours_logged numeric,
  average_csat numeric
) language plpgsql security invoker
set
  search_path = '' as $$
begin
  return query
  select
    a.name,
    count(t.id) filter (where t.status not in ('resolved', 'closed')) as open_tickets,
    count(t.id) filter (where t.sla_breached) as breached_tickets,
    -- Scalar subquery: joining worklogs would multiply each entry
    -- by the number of tickets the agent is on.
    (select round(coalesce(sum(w.duration), 0) / 1000.0 / 3600.0, 2)
       from desk.worklogs w where w.agent_id = a.id) as hours_logged,
    round(avg(t.satisfaction_score)::numeric, 2) as average_csat
  from desk.agents a
  left join desk.tickets t
    on t.assignee_id = a.id
   and (p_include_resolved or t.status not in ('resolved', 'closed'))
  where a.team_id = p_team_id
  group by a.id, a.name
  order by open_tickets desc, a.name;
end;
$$;

comment on function desk.preview_team_workload (uuid, boolean) is '{
    "type": "form",
    "resource": "teams",
    "name": "Preview workload",
    "description": "See open ticket load, breaches and logged hours per agent on this team.",
    "icon": "Gauge",
    "success_message": "Workload calculated",
    "fields": {
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["p_team_id", "p_include_resolved"]}
        ],
        "relations": {
            "p_team_id": {"table": "teams", "column": "id", "display": ["name"]}
        }
    }
}';

revoke all on function desk.preview_team_workload (uuid, boolean)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function desk.preview_team_workload (uuid, boolean) to "x-admin",
"agent";

----------------------------------------------------------------
-- Templates (bulk insert payloads applied via supasheet.apply_template)
--
--   select supasheet.apply_template('desk', '<template_view>', 'tickets');
--
-- Only column names present on BOTH the view and the target table
-- are copied; everything else falls back to the target's defaults.
----------------------------------------------------------------
-- Static: the standard checklist raised for every new enterprise
-- account, ready to stamp onto desk.tickets.
create or replace view desk.onboarding_tickets_template
with
  (security_invoker = true) as
select
  *
from
  (
    values
      (
        'Kick-off call with the account team'::varchar(500),
        'task'::desk.ticket_type,
        'normal'::desk.ticket_priority,
        'web'::desk.ticket_channel
      ),
      (
        'Collect SSO metadata and configure login',
        'task',
        'high',
        'web'
      ),
      (
        'Provision sandbox environment',
        'task',
        'normal',
        'web'
      ),
      (
        'Walk through the admin console',
        'question',
        'low',
        'web'
      ),
      (
        'Schedule the 30-day health check',
        'task',
        'low',
        'web'
      )
  ) as t (subject, ticket_type, priority, channel);

revoke all on desk.onboarding_tickets_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.onboarding_tickets_template to "x-admin",
  "agent";

comment on view desk.onboarding_tickets_template is '{"type": "template", "name": "Enterprise Onboarding Tickets", "description": "The five standard onboarding tasks raised for a new enterprise account. Apply to desk.tickets, then assign the account and owner.", "target_table": "tickets"}';

-- Dynamic: one follow-up ticket per breached, still-open ticket.
create or replace view desk.sla_followup_template
with
  (security_invoker = true) as
select
  ('Follow-up: ' || t.reference || ' missed its SLA')::varchar(500) as subject,
  t.customer_id,
  t.contact_id,
  t.category_id,
  t.team_id,
  t.assignee_id,
  'task'::desk.ticket_type as ticket_type,
  'high'::desk.ticket_priority as priority,
  'web'::desk.ticket_channel as channel,
  (current_timestamp + interval '1 day') as due_at
from
  desk.tickets t
where
  t.sla_breached
  and t.status not in ('resolved', 'closed');

revoke all on desk.sla_followup_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.sla_followup_template to "x-admin";

comment on view desk.sla_followup_template is '{"type": "template", "name": "SLA Breach Follow-ups", "description": "A high-priority follow-up ticket for every open ticket that has already blown its SLA. Apply to desk.tickets.", "target_table": "tickets"}';

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view desk.tickets_report
with
  (security_invoker = true) as
select
  t.id,
  t.reference,
  t.subject,
  t.status,
  t.priority,
  t.channel,
  t.ticket_type,
  c.name as customer,
  c.tier as customer_tier,
  ct.name as contact,
  cat.name as category,
  tm.name as team,
  a.name as assignee,
  t.created_at,
  t.first_response_at,
  t.resolved_at,
  t.due_at,
  t.sla_breached,
  round(coalesce(t.time_spent, 0) / 1000.0 / 3600.0, 2) as hours_logged,
  t.satisfaction_score,
  count(m.id) filter (
    where
      m.kind = 'public_reply'
  ) as reply_count
from
  desk.tickets t
  left join desk.customers c on c.id = t.customer_id
  left join desk.contacts ct on ct.id = t.contact_id
  left join desk.categories cat on cat.id = t.category_id
  left join desk.teams tm on tm.id = t.team_id
  left join desk.agents a on a.id = t.assignee_id
  left join desk.ticket_messages m on m.ticket_id = t.id
group by
  t.id,
  c.name,
  c.tier,
  ct.name,
  cat.name,
  tm.name,
  a.name;

revoke all on desk.tickets_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.tickets_report to "x-admin",
  "agent";

-- `template: true` means a Handlebars HTML file has been uploaded to
-- the `report-templates` bucket at the deterministic key
-- `desk/tickets_report.hbs` (one template per report). Upload
-- supabase/examples/templates/tickets_report.hbs there as-is (as
-- "x-admin") to enable the "Print Report" button on this report.
comment on view desk.tickets_report is '{"type": "report", "name": "Ticket Report", "description": "Every ticket with account, routing, SLA and CSAT context", "template": true}';

create or replace view desk.agents_report
with
  (security_invoker = true) as
select
  a.id,
  a.name,
  a.job_title,
  a.seniority,
  a.availability,
  tm.name as team,
  count(distinct t.id) as tickets_assigned,
  count(distinct t.id) filter (
    where
      t.status not in ('resolved', 'closed')
  ) as tickets_open,
  count(distinct t.id) filter (
    where
      t.status in ('resolved', 'closed')
  ) as tickets_closed,
  count(distinct t.id) filter (
    where
      t.sla_breached
  ) as tickets_breached,
  -- Scalar subquery, not a join: joining worklogs here would
  -- multiply each worklog by the agent's ticket count.
  (
    select
      round(coalesce(sum(w.duration), 0) / 1000.0 / 3600.0, 2)
    from
      desk.worklogs w
    where
      w.agent_id = a.id
  ) as hours_logged,
  round(avg(t.satisfaction_score)::numeric, 2) as average_csat
from
  desk.agents a
  left join desk.tickets t on t.assignee_id = a.id
  left join desk.teams tm on tm.id = a.team_id
group by
  a.id,
  tm.name;

revoke all on desk.agents_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.agents_report to "x-admin",
  "agent";

comment on view desk.agents_report is '{"type": "report", "name": "Agent Performance", "description": "Ticket load, closure rate, logged hours and CSAT per agent"}';

create or replace view desk.customers_report
with
  (security_invoker = true) as
select
  c.id,
  c.name,
  c.tier,
  c.health,
  c.industry,
  c.country,
  c.contract_value,
  am.name as account_manager,
  count(distinct ct.id) as contact_count,
  count(distinct t.id) as ticket_count,
  count(distinct t.id) filter (
    where
      t.status not in ('resolved', 'closed')
  ) as tickets_open,
  count(distinct t.id) filter (
    where
      t.sla_breached
  ) as tickets_breached,
  round(avg(t.satisfaction_score)::numeric, 2) as average_csat,
  c.onboarded_on
from
  desk.customers c
  left join desk.agents am on am.id = c.account_manager_id
  left join desk.contacts ct on ct.customer_id = c.id
  left join desk.tickets t on t.customer_id = c.id
group by
  c.id,
  am.name;

revoke all on desk.customers_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.customers_report to "x-admin",
  "agent";

comment on view desk.customers_report is '{"type": "report", "name": "Account Report", "description": "Ticket volume, breaches and satisfaction per customer account"}';

create or replace view desk.sla_compliance_report
with
  (security_invoker = true) as
select
  p.id,
  p.name as policy,
  p.priority,
  p.first_response_minutes,
  p.resolution_minutes,
  count(t.id) as tickets,
  count(t.id) filter (
    where
      t.first_response_at is not null
      and t.first_response_at <= t.created_at + make_interval(mins => p.first_response_minutes)
  ) as first_response_met,
  count(t.id) filter (
    where
      t.resolved_at is not null
      and t.resolved_at <= t.created_at + make_interval(mins => p.resolution_minutes)
  ) as resolution_met,
  count(t.id) filter (
    where
      t.sla_breached
  ) as breached,
  round(
    100.0 * count(t.id) filter (
      where
        t.resolved_at is not null
        and t.resolved_at <= t.created_at + make_interval(mins => p.resolution_minutes)
    ) / nullif(count(t.id), 0),
    1
  ) as resolution_compliance_pct
from
  desk.sla_policies p
  left join desk.tickets t on t.sla_policy_id = p.id
group by
  p.id;

revoke all on desk.sla_compliance_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.sla_compliance_report to "x-admin",
  "agent";

comment on view desk.sla_compliance_report is '{"type": "report", "name": "SLA Compliance", "description": "First response and resolution against target, per policy"}';

----------------------------------------------------------------
-- Materialized view report (precomputed monthly rollup)
--
-- Two different refreshes — don't confuse them:
--   select supasheet.refresh_metadata();            -- the catalog
--   refresh materialized view concurrently
--     desk.ticket_volume_rollup;                    -- the data
----------------------------------------------------------------
create materialized view desk.ticket_volume_rollup as
select
  date_trunc('month', created_at)::date as month,
  count(*) as tickets_created,
  count(*) filter (
    where
      status in ('resolved', 'closed')
  ) as tickets_closed,
  count(*) filter (
    where
      sla_breached
  ) as tickets_breached,
  count(*) filter (
    where
      is_escalated
  ) as tickets_escalated,
  round(avg(satisfaction_score)::numeric, 2) as average_csat,
  round(
    avg(
      extract(
        epoch
        from
          (first_response_at - created_at)
      ) / 60.0
    )::numeric,
    1
  ) as avg_first_response_minutes
from
  desk.tickets
group by
  1;

-- Unique index is REQUIRED for `refresh ... concurrently`.
create unique index idx_desk_ticket_volume_rollup_month on desk.ticket_volume_rollup (month);

revoke all on desk.ticket_volume_rollup
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.ticket_volume_rollup to "x-admin",
  "agent";

comment on materialized view desk.ticket_volume_rollup is '{"type": "report", "name": "Monthly Volume Rollup", "description": "Precomputed monthly ticket volume, closure, breach and CSAT figures"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: open tickets
create or replace view desk.open_tickets_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'ticket' as icon,
  'open tickets' as label
from
  desk.tickets
where
  status not in ('resolved', 'closed');

revoke all on desk.open_tickets_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.open_tickets_count to "x-admin",
  "agent";

-- card_2: resolved vs open
create or replace view desk.ticket_resolution_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status in ('resolved', 'closed')
  ) as primary,
  count(*) filter (
    where
      status not in ('resolved', 'closed')
  ) as secondary,
  'Resolved' as primary_label,
  'Open' as secondary_label
from
  desk.tickets;

revoke all on desk.ticket_resolution_split
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.ticket_resolution_split to "x-admin",
  "agent";

-- card_3: SLA compliance rate
create or replace view desk.sla_compliance_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        not sla_breached
    ) / nullif(count(*), 0),
    1
  ) as percent
from
  desk.tickets;

revoke all on desk.sla_compliance_rate
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.sla_compliance_rate to "x-admin",
  "agent";

-- card_4: backlog progress across the pipeline
create or replace view desk.ticket_backlog_progress
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status in ('resolved', 'closed')
  ) as current,
  count(*) as total,
  json_build_array(
    json_build_object(
      'label',
      'New',
      'value',
      count(*) filter (
        where
          status = 'new'
      )
    ),
    json_build_object(
      'label',
      'Open',
      'value',
      count(*) filter (
        where
          status = 'open'
      )
    ),
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
      'On hold',
      'value',
      count(*) filter (
        where
          status = 'on_hold'
      )
    ),
    json_build_object(
      'label',
      'Resolved',
      'value',
      count(*) filter (
        where
          status in ('resolved', 'closed')
      )
    )
  ) as segments
from
  desk.tickets;

revoke all on desk.ticket_backlog_progress
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.ticket_backlog_progress to "x-admin",
  "agent";

-- card_5: headline total plus a ranked breakdown of that SAME pool
create or replace view desk.ticket_priority_overview
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status not in ('resolved', 'closed')
  ) as value,
  'Open Tickets' as label,
  'inbox' as icon,
  json_build_array(
    json_build_object(
      'label',
      'Urgent',
      'value',
      count(*) filter (
        where
          priority = 'urgent'
          and status not in ('resolved', 'closed')
      ),
      'variant',
      'destructive'
    ),
    json_build_object(
      'label',
      'High',
      'value',
      count(*) filter (
        where
          priority = 'high'
          and status not in ('resolved', 'closed')
      ),
      'variant',
      'warning'
    ),
    json_build_object(
      'label',
      'Normal',
      'value',
      count(*) filter (
        where
          priority = 'normal'
          and status not in ('resolved', 'closed')
      ),
      'variant',
      'info'
    ),
    json_build_object(
      'label',
      'Low',
      'value',
      count(*) filter (
        where
          priority = 'low'
          and status not in ('resolved', 'closed')
      ),
      'variant',
      'secondary'
    )
  ) as breakdown
from
  desk.tickets;

revoke all on desk.ticket_priority_overview
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.ticket_priority_overview to "x-admin",
  "agent";

-- card_6: full-width metric grid
create or replace view desk.desk_pulse
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Unassigned',
      'value',
      count(*) filter (
        where
          assignee_id is null
          and status not in ('resolved', 'closed')
      ),
      'icon',
      'user-round-x'
    ),
    json_build_object(
      'label',
      'Escalated',
      'value',
      count(*) filter (
        where
          is_escalated
      ),
      'icon',
      'siren'
    ),
    json_build_object(
      'label',
      'Breached',
      'value',
      count(*) filter (
        where
          sla_breached
      ),
      'icon',
      'timer-off'
    ),
    json_build_object(
      'label',
      'Resolved 7d',
      'value',
      count(*) filter (
        where
          resolved_at >= current_timestamp - interval '7 days'
      ),
      'icon',
      'circle-check'
    ),
    json_build_object(
      'label',
      'Avg CSAT',
      'value',
      coalesce(round(avg(satisfaction_score)::numeric, 2), 0),
      'icon',
      'star'
    ),
    json_build_object(
      'label',
      'Hours logged',
      'value',
      (
        select
          round(coalesce(sum(duration), 0) / 1000.0 / 3600.0, 1)
        from
          desk.worklogs
      ),
      'icon',
      'clock'
    )
  ) as metrics
from
  desk.tickets;

revoke all on desk.desk_pulse
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.desk_pulse to "x-admin",
  "agent";

-- table_1: latest tickets
create or replace view desk.recent_tickets
with
  (security_invoker = true) as
select
  t.reference,
  t.subject,
  t.status,
  t.priority,
  to_char(t.created_at, 'Mon DD') as created,
  '/desk/resource/tickets/' || t.id || '/detail' as link
from
  desk.tickets t
order by
  t.created_at desc
limit
  10;

revoke all on desk.recent_tickets
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.recent_tickets to "x-admin",
  "agent";

-- table_1: tickets closest to breaching (pairs with Recent Tickets)
create or replace view desk.breaching_soon
with
  (security_invoker = true) as
select
  t.reference,
  t.subject,
  t.priority,
  to_char(t.due_at, 'Mon DD HH24:MI') as due,
  '/desk/resource/tickets/' || t.id || '/detail' as link
from
  desk.tickets t
where
  t.status not in ('resolved', 'closed')
  and t.due_at is not null
order by
  t.due_at asc
limit
  10;

revoke all on desk.breaching_soon
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.breaching_soon to "x-admin",
  "agent";

-- table_2: team performance rollup
create or replace view desk.team_performance
with
  (security_invoker = true) as
select
  tm.name as team,
  count(t.id) as tickets,
  count(t.id) filter (
    where
      t.status not in ('resolved', 'closed')
  ) as open,
  count(t.id) filter (
    where
      t.sla_breached
  ) as breached,
  coalesce(round(avg(t.satisfaction_score)::numeric, 2), 0) as csat,
  '/desk/resource/teams/' || tm.id || '/detail' as link
from
  desk.teams tm
  left join desk.tickets t on t.team_id = tm.id
group by
  tm.id,
  tm.name
order by
  tickets desc
limit
  10;

revoke all on desk.team_performance
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.team_performance to "x-admin",
  "agent";

-- list_1: escalated tickets
create or replace view desk.escalated_tickets
with
  (security_invoker = true) as
select
  t.subject as title,
  coalesce(c.name, 'Unknown account') || ' · ' || t.reference as description,
  'siren' as icon,
  'destructive' as variant,
  '/desk/resource/tickets/' || t.id || '/detail' as link
from
  desk.tickets t
  left join desk.customers c on c.id = t.customer_id
where
  t.is_escalated
  and t.status not in ('resolved', 'closed')
order by
  t.updated_at desc
limit
  10;

revoke all on desk.escalated_tickets
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.escalated_tickets to "x-admin",
  "agent";

-- list_2: overdue tickets (wider list with two extra fields)
create or replace view desk.overdue_tickets
with
  (security_invoker = true) as
select
  t.subject as title,
  coalesce(a.name, 'Unassigned') as description,
  'timer-off' as icon,
  case
    when t.priority in ('urgent', 'high') then 'destructive'
    else 'warning'
  end as variant,
  t.priority::text as field_1,
  to_char(t.due_at, 'MM/DD') as field_2,
  '/desk/resource/tickets/' || t.id || '/detail' as link
from
  desk.tickets t
  left join desk.agents a on a.id = t.assignee_id
where
  t.sla_breached
  and t.status not in ('resolved', 'closed')
order by
  t.due_at asc
limit
  10;

revoke all on desk.overdue_tickets
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.overdue_tickets to "x-admin",
  "agent";

-- list_3: activity feed (avatar initials derived client-side from `actor`)
create or replace view desk.recent_desk_activity
with
  (security_invoker = true) as
select
  coalesce(a.name, 'System') as actor,
  case
    when t.status in ('resolved', 'closed') then 'resolved'
    when t.is_escalated then 'escalated'
    when t.status = 'pending' then 'is waiting on'
    else 'updated'
  end as action,
  t.subject as entity,
  to_char(t.updated_at, 'Mon DD, HH24:MI') as date,
  '/desk/resource/tickets/' || t.id || '/detail' as link
from
  desk.tickets t
  left join desk.agents a on a.id = t.assignee_id
order by
  t.updated_at desc
limit
  8;

revoke all on desk.recent_desk_activity
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.recent_desk_activity to "x-admin",
  "agent";

-- list_4: leaderboard of top closers
create or replace view desk.top_agents
with
  (security_invoker = true) as
select
  a.name,
  count(t.id) as value,
  a.job_title as label,
  case
    when a.availability = 'available' then 'success'
    else 'info'
  end as variant,
  '/desk/resource/agents/' || a.id || '/detail' as link
from
  desk.agents a
  join desk.tickets t on t.assignee_id = a.id
where
  t.status in ('resolved', 'closed')
group by
  a.id,
  a.name,
  a.job_title,
  a.availability
order by
  value desc
limit
  5;

revoke all on desk.top_agents
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.top_agents to "x-admin",
  "agent";

-- card_1: unassigned queue — shown on the tickets resource page
create or replace view desk.unassigned_tickets_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'user-round-x' as icon,
  'unassigned tickets' as label
from
  desk.tickets
where
  assignee_id is null
  and status not in ('resolved', 'closed');

revoke all on desk.unassigned_tickets_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.unassigned_tickets_count to "x-admin",
  "agent";

-- card_2: accounts at risk vs healthy — shown on the customers resource page
create or replace view desk.account_health_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      health = 'healthy'
  ) as primary,
  count(*) filter (
    where
      health in ('at_risk', 'churned')
  ) as secondary,
  'Healthy' as primary_label,
  'At risk' as secondary_label
from
  desk.customers;

revoke all on desk.account_health_split
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.account_health_split to "x-admin",
  "agent";

-- card_3: agent availability — shown on the agents resource page
create or replace view desk.agent_availability_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        availability = 'available'
    ) / nullif(count(*), 0),
    1
  ) as percent
from
  desk.agents;

revoke all on desk.agent_availability_rate
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.agent_availability_rate to "x-admin",
  "agent";

-- card_1: published articles — shown on the articles resource page
create or replace view desk.published_articles_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'book-open' as icon,
  'published articles' as label
from
  desk.articles
where
  status = 'published';

revoke all on desk.published_articles_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.published_articles_count to "x-admin",
  "agent";

comment on view desk.open_tickets_count is '{"type": "dashboard_widget", "name": "Open Tickets", "description": "Tickets not yet resolved or closed", "widget_type": "card_1"}';

comment on view desk.ticket_resolution_split is '{"type": "dashboard_widget", "name": "Resolution Split", "description": "Resolved vs still-open tickets", "widget_type": "card_2"}';

comment on view desk.sla_compliance_rate is '{"type": "dashboard_widget", "name": "SLA Compliance", "description": "Share of tickets still inside their SLA", "widget_type": "card_3"}';

comment on view desk.ticket_backlog_progress is '{"type": "dashboard_widget", "name": "Backlog Progress", "description": "Where the queue sits across the pipeline", "widget_type": "card_4"}';

comment on view desk.ticket_priority_overview is '{"type": "dashboard_widget", "name": "Priority Overview", "description": "Open tickets broken down by priority", "widget_type": "card_5"}';

comment on view desk.desk_pulse is '{"type": "dashboard_widget", "name": "Desk Pulse", "description": "Headline support metrics at a glance", "widget_type": "card_6"}';

comment on view desk.recent_tickets is '{"type": "dashboard_widget", "name": "Recent Tickets", "description": "Latest 10 tickets", "widget_type": "table_1", "resource": "tickets", "url": "/desk/resource/tickets"}';

comment on view desk.breaching_soon is '{"type": "dashboard_widget", "name": "Breaching Soon", "description": "Open tickets closest to their SLA deadline", "widget_type": "table_1"}';

comment on view desk.team_performance is '{"type": "dashboard_widget", "name": "Team Performance", "description": "Volume, breaches and CSAT per team", "widget_type": "table_2", "url": "/desk/resource/teams"}';

comment on view desk.escalated_tickets is '{"type": "dashboard_widget", "name": "Escalations", "description": "Escalated tickets still in the queue", "widget_type": "list_1", "url": "/desk/resource/tickets"}';

comment on view desk.overdue_tickets is '{"type": "dashboard_widget", "name": "Overdue", "description": "Tickets past their SLA deadline", "widget_type": "list_2", "url": "/desk/resource/tickets"}';

comment on view desk.recent_desk_activity is '{"type": "dashboard_widget", "name": "Recent Activity", "description": "Latest ticket movements across the desk", "widget_type": "list_3", "url": "/desk/resource/tickets"}';

comment on view desk.top_agents is '{"type": "dashboard_widget", "name": "Top Closers", "description": "Agents ranked by tickets closed", "widget_type": "list_4", "url": "/desk/resource/agents"}';

comment on view desk.unassigned_tickets_count is '{"type": "dashboard_widget", "name": "Unassigned", "description": "Open tickets with no assignee", "widget_type": "card_1", "resource": "tickets"}';

comment on view desk.account_health_split is '{"type": "dashboard_widget", "name": "Account Health", "description": "Healthy accounts vs accounts at risk", "widget_type": "card_2", "resource": "customers"}';

comment on view desk.agent_availability_rate is '{"type": "dashboard_widget", "name": "Agent Availability", "description": "Share of the roster currently available", "widget_type": "card_3", "resource": "agents"}';

comment on view desk.published_articles_count is '{"type": "dashboard_widget", "name": "Published Articles", "description": "Live knowledge base articles", "widget_type": "card_1", "resource": "articles"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: tickets by status
create or replace view desk.tickets_by_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  desk.tickets
group by
  status;

revoke all on desk.tickets_by_status_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.tickets_by_status_pie to "x-admin",
  "agent";

-- Bar: volume and breaches by category
create or replace view desk.tickets_by_category_bar
with
  (security_invoker = true) as
select
  c.name as label,
  count(t.id) as tickets,
  count(t.id) filter (
    where
      t.status in ('resolved', 'closed')
  ) as resolved,
  count(t.id) filter (
    where
      t.sla_breached
  ) as breached
from
  desk.categories c
  left join desk.tickets t on t.category_id = c.id
group by
  c.id,
  c.name
order by
  tickets desc
limit
  10;

revoke all on desk.tickets_by_category_bar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.tickets_by_category_bar to "x-admin",
  "agent";

-- Line: daily created vs resolved over the last 14 days
create or replace view desk.ticket_volume_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('day', created_at), 'Mon DD') as date,
  count(*) as created,
  count(*) filter (
    where
      status in ('resolved', 'closed')
  ) as resolved
from
  desk.tickets
where
  created_at >= current_date - interval '14 days'
group by
  date_trunc('day', created_at)
order by
  date_trunc('day', created_at);

revoke all on desk.ticket_volume_line
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.ticket_volume_line to "x-admin",
  "agent";

-- Area: weekly backlog composition over the last 8 weeks
create or replace view desk.ticket_backlog_area
with
  (security_invoker = true) as
select
  to_char(date_trunc('week', created_at), 'Mon DD') as date,
  count(*) filter (
    where
      status in ('new', 'open')
  ) as active,
  count(*) filter (
    where
      status in ('pending', 'on_hold')
  ) as waiting,
  count(*) filter (
    where
      status in ('resolved', 'closed')
  ) as done
from
  desk.tickets
where
  created_at >= current_date - interval '8 weeks'
group by
  date_trunc('week', created_at)
order by
  date_trunc('week', created_at);

revoke all on desk.ticket_backlog_area
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.ticket_backlog_area to "x-admin",
  "agent";

-- Radar: workload per team
create or replace view desk.team_workload_radar
with
  (security_invoker = true) as
select
  tm.name as metric,
  count(t.id) as tickets,
  count(t.id) filter (
    where
      t.status not in ('resolved', 'closed')
  ) as open,
  count(t.id) filter (
    where
      t.sla_breached
  ) as breached
from
  desk.teams tm
  left join desk.tickets t on t.team_id = tm.id
group by
  tm.id,
  tm.name;

revoke all on desk.team_workload_radar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.team_workload_radar to "x-admin",
  "agent";

-- Pie: tickets by channel — shown on the tickets resource page
create or replace view desk.tickets_by_channel_pie
with
  (security_invoker = true) as
select
  channel::text as label,
  count(*) as value
from
  desk.tickets
group by
  channel;

revoke all on desk.tickets_by_channel_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.tickets_by_channel_pie to "x-admin",
  "agent";

-- Pie: accounts by tier — shown on the customers resource page
create or replace view desk.customers_by_tier_pie
with
  (security_invoker = true) as
select
  tier::text as label,
  count(*) as value
from
  desk.customers
group by
  tier;

revoke all on desk.customers_by_tier_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.customers_by_tier_pie to "x-admin",
  "agent";

-- Bar: knowledge base pipeline — shown on the articles resource page
create or replace view desk.articles_by_status_bar
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as articles,
  coalesce(sum(view_count), 0) as views
from
  desk.articles
group by
  status;

revoke all on desk.articles_by_status_bar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.articles_by_status_bar to "x-admin",
  "agent";

-- Radar: CSAT and load per agent — shown on the agents resource page
create or replace view desk.agent_scorecard_radar
with
  (security_invoker = true) as
select
  a.name as metric,
  count(t.id) as tickets,
  coalesce(round(avg(t.satisfaction_score)::numeric, 2), 0) as csat
from
  desk.agents a
  left join desk.tickets t on t.assignee_id = a.id
group by
  a.id,
  a.name;

revoke all on desk.agent_scorecard_radar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on desk.agent_scorecard_radar to "x-admin",
  "agent";

comment on view desk.tickets_by_status_pie is '{"type": "chart", "name": "Tickets By Status", "description": "Ticket count grouped by pipeline status", "chart_type": "pie"}';

comment on view desk.tickets_by_category_bar is '{"type": "chart", "name": "Tickets By Category", "description": "Volume, resolution and breaches per category", "chart_type": "bar"}';

comment on view desk.ticket_volume_line is '{"type": "chart", "name": "Daily Volume", "description": "Tickets created vs resolved over 14 days", "chart_type": "line"}';

comment on view desk.ticket_backlog_area is '{"type": "chart", "name": "Backlog Composition", "description": "Weekly backlog split across active, waiting and done", "chart_type": "area"}';

comment on view desk.team_workload_radar is '{"type": "chart", "name": "Team Workload", "description": "Ticket load per support team", "chart_type": "radar"}';

comment on view desk.tickets_by_channel_pie is '{"type": "chart", "name": "Tickets By Channel", "description": "Where requests come in from", "chart_type": "pie", "resource": "tickets"}';

comment on view desk.customers_by_tier_pie is '{"type": "chart", "name": "Accounts By Tier", "description": "Distribution of accounts across plans", "chart_type": "pie", "resource": "customers"}';

comment on view desk.articles_by_status_bar is '{"type": "chart", "name": "Knowledge Pipeline", "description": "Articles and views by editorial status", "chart_type": "bar", "resource": "articles"}';

comment on view desk.agent_scorecard_radar is '{"type": "chart", "name": "Agent Scorecard", "description": "Ticket load and CSAT per agent", "chart_type": "radar", "resource": "agents"}';

----------------------------------------------------------------
-- Audit triggers (INSERT/UPDATE fire AFTER, DELETE must fire BEFORE
-- so the row still exists when it is captured)
----------------------------------------------------------------
create trigger audit_desk_teams_insert
after insert on desk.teams for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_teams_update
after update on desk.teams for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_teams_delete
before delete on desk.teams for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_sla_policies_insert
after insert on desk.sla_policies for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_sla_policies_update
after update on desk.sla_policies for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_sla_policies_delete
before delete on desk.sla_policies for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_agents_insert
after insert on desk.agents for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_agents_update
after update on desk.agents for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_agents_delete
before delete on desk.agents for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_customers_insert
after insert on desk.customers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_customers_update
after update on desk.customers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_customers_delete
before delete on desk.customers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_customer_billing_insert
after insert on desk.customer_billing for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_customer_billing_update
after update on desk.customer_billing for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_customer_billing_delete
before delete on desk.customer_billing for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_contacts_insert
after insert on desk.contacts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_contacts_update
after update on desk.contacts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_contacts_delete
before delete on desk.contacts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_categories_insert
after insert on desk.categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_categories_update
after update on desk.categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_categories_delete
before delete on desk.categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_problems_insert
after insert on desk.problems for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_problems_update
after update on desk.problems for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_problems_delete
before delete on desk.problems for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_tickets_insert
after insert on desk.tickets for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_tickets_update
after update on desk.tickets for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_tickets_delete
before delete on desk.tickets for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_ticket_messages_insert
after insert on desk.ticket_messages for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_ticket_messages_update
after update on desk.ticket_messages for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_ticket_messages_delete
before delete on desk.ticket_messages for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_ticket_watchers_insert
after insert on desk.ticket_watchers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_ticket_watchers_delete
before delete on desk.ticket_watchers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_worklogs_insert
after insert on desk.worklogs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_worklogs_update
after update on desk.worklogs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_worklogs_delete
before delete on desk.worklogs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_satisfaction_surveys_insert
after insert on desk.satisfaction_surveys for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_satisfaction_surveys_update
after update on desk.satisfaction_surveys for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_satisfaction_surveys_delete
before delete on desk.satisfaction_surveys for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_articles_insert
after insert on desk.articles for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_articles_update
after update on desk.articles for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_articles_delete
before delete on desk.articles for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_canned_responses_insert
after insert on desk.canned_responses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_canned_responses_update
after update on desk.canned_responses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_canned_responses_delete
before delete on desk.canned_responses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_desk_settings_insert
after insert on desk.desk_settings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_desk_desk_settings_update
after update on desk.desk_settings for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
--
-- supasheet.create_notification() is service_role-only, so every
-- caller below is a `security definer set search_path = ''` trigger.
----------------------------------------------------------------
-- Tickets: creation, assignment, status change, escalation, breach
create or replace function desk.trg_tickets_notify () returns trigger as $$
declare
    v_recipients     uuid[];
    v_assignee_user  uuid;
    v_type           text;
    v_title          text;
    v_body           text;
begin
    if new.assignee_id is not null then
        select user_id into v_assignee_user from desk.agents where id = new.assignee_id;
    end if;

    if tg_op = 'INSERT' then
        v_type  := 'desk_ticket_created';
        v_title := 'New ticket';
        v_body  := new.reference || ': ' || new.subject;
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('desk', 'tickets', 'update') || array[new.user_id],
            null
        );
    elsif new.is_escalated and not old.is_escalated then
        v_type  := 'desk_ticket_escalated';
        v_title := 'Ticket escalated';
        v_body  := new.reference || ' was escalated to urgent.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('desk', 'tickets', 'update') || array[v_assignee_user],
            null
        );
    elsif new.sla_breached and not old.sla_breached then
        v_type  := 'desk_ticket_sla_breached';
        v_title := 'SLA breached';
        v_body  := new.reference || ' has passed its resolution target.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('desk', 'tickets', 'update') || array[v_assignee_user],
            null
        );
    elsif new.assignee_id is distinct from old.assignee_id then
        v_type  := 'desk_ticket_assigned';
        v_title := 'Ticket assigned to you';
        v_body  := new.reference || ': ' || new.subject;
        v_recipients := array_remove(array[v_assignee_user], null);
    elsif new.status is distinct from old.status then
        v_type  := 'desk_ticket_status_changed';
        v_title := 'Ticket status updated';
        v_body  := new.reference || ' is now ' || new.status::text || '.';
        v_recipients := array_remove(array[new.user_id, v_assignee_user], null);
    else
        return new;
    end if;

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'ticket_id',   new.id,
            'reference',   new.reference,
            'status',      new.status,
            'priority',    new.priority,
            'customer_id', new.customer_id
        ),
        '/desk/resource/tickets/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists tickets_notify on desk.tickets;

create trigger tickets_notify
after insert or update of status,
assignee_id,
is_escalated,
sla_breached on desk.tickets for each row
execute function desk.trg_tickets_notify ();

-- Problems: notify the desk when a known issue lands or changes state
create or replace function desk.trg_problems_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type       text;
    v_title      text;
    v_body       text;
begin
    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('desk', 'problems', 'update') || array[new.user_id],
        null
    );

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    if tg_op = 'INSERT' then
        v_type  := 'desk_problem_created';
        v_title := 'New known issue';
        v_body  := new.title || ' (' || new.impact::text || ' impact).';
    elsif new.status is distinct from old.status then
        v_type  := 'desk_problem_status_changed';
        v_title := 'Known issue updated';
        v_body  := new.title || ' is now ' || new.status::text || '.';
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object('problem_id', new.id, 'status', new.status, 'impact', new.impact),
        '/desk/resource/problems/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists problems_notify on desk.problems;

create trigger problems_notify
after insert or update of status on desk.problems for each row
execute function desk.trg_problems_notify ();

-- Comments: pair the per-record comment system with notifications.
-- The trigger lives on the CENTRAL supasheet.comments table and
-- filters down to this schema's tables.
create or replace function desk.trg_desk_comments_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.schema_name <> 'desk' or new.table_name not in ('tickets', 'problems') then
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('desk', new.table_name, 'update'),
        new.created_by
    );

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'desk_comment_added',
        'New comment on ' || new.table_name,
        left(new.content, 140),
        v_recipients,
        jsonb_build_object('record_id', new.record_id, 'table_name', new.table_name),
        '/desk/resource/' || new.table_name || '/' || new.record_id::text || '/comment'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists desk_comments_notify on supasheet.comments;

create trigger desk_comments_notify
after insert on supasheet.comments for each row
execute function desk.trg_desk_comments_notify ();

----------------------------------------------------------------
-- Refresh the metadata catalog (materialized views — NOT automatic)
----------------------------------------------------------------
select
  supasheet.refresh_metadata ();
