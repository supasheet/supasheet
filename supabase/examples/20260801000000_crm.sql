-- ================================================================
-- Supasheet Example — "CRM" (sales pipeline / revenue operations)
-- ================================================================
-- A production-shaped CRM: territories and a sales roster, accounts
-- and their contacts, inbound leads and their conversion, a product
-- catalogue, the opportunity pipeline with line items and quotes,
-- logged activities and follow-up tasks, marketing campaigns, and
-- the forecast that falls out of all of it.
--
-- Demo data lives in supabase/examples/c_seed.sql — apply this file
-- first, then that one.
--
-- Feature coverage:
--   - Native-role RBAC with TWO custom roles ("manager", "rep")
--     alongside the built-in "x-admin"/"user" — CREATE ROLE + GRANT,
--     no permissions table
--   - Row Level Security in three different shapes: read-anything /
--     edit-your-own (accounts, opportunities), owner-or-unassigned
--     (leads), and owner-only (tasks), all resolved through one
--     STABLE SECURITY DEFINER helper (crm.current_rep_id) so the
--     policies stay index-friendly
--   - Column-level GRANT: a rep maintains their own profile but not
--     their quota, and never touches compensation
--   - All column data types: URL, TEL, EMAIL, RICH_TEXT, COLOR,
--     PERCENTAGE, DURATION, RATING, file, AVATAR, enums, arrays
--   - All six view layouts: kanban (opportunities, leads, tasks),
--     calendar (activities, tasks), gallery (products, accounts),
--     list (territories, pipeline_stages, quotes), tree (territory
--     hierarchy, sales org chart, parent/child accounts, contact
--     reporting lines), gantt (campaigns, deal cycles)
--   - Field sections, filter presets, quick_create, conditional
--     field behavior, lookup fill + lookup filter, resource links
--   - Singleton resource (crm_settings)
--   - 1:1 extension record (rep_compensation — x-admin only)
--   - Many-to-many junction with inline form (opportunity_contacts,
--     the buying committee and its roles)
--   - One-to-many detail lines with business triggers that keep
--     parent rollups in sync (opportunity_line_items -> amount,
--     opportunities -> account and campaign rollups, activities ->
--     last_activity_at, leads -> campaign counters)
--   - Derived pipeline maths: stage drives probability and forecast
--     category, probability drives weighted_amount, stage changes
--     stamp stage_changed_at and days_in_stage
--   - Integrity guards that raise rather than corrupt: a closed deal
--     cannot be edited by a rep, its line items are frozen with it, a
--     lost deal needs a reason, a quote cannot total below zero, and
--     a deal cannot be won for nothing
--   - A pg_trigger_depth() check so those guards block real edits
--     without blocking the module's own rollups
--   - A nightly maintenance function (crm.refresh_deal_ages) for the
--     stored ages the kanban and the alert widgets filter on
--   - Detail page "tabs" allowlist + "timelines" (opportunity_events,
--     a trigger-populated, read-only activity feed)
--   - Row actions backed by SQL functions (win, lose, reopen, set
--     stage as an enum picker, convert a lead, disqualify a lead,
--     complete a task, generate a quote from the line items)
--   - Custom forms backed by SQL functions, each returning a
--     different shape: log_activity (scalar uuid, on "accounts"),
--     open_opportunity (single object via OUT params, on
--     "accounts"), bulk_reassign_owner (setof crm.opportunities, on
--     "sales_reps"), preview_territory_pipeline (setof rows via an
--     explicit table(...) list, on "territories")
--   - Templates (bulk insert via supasheet.apply_template): one
--     static (onboarding_tasks_template) and two dynamic
--     (renewal_opportunities_template, stale_deal_followup_template)
--   - Reports, including one with an HTML/Handlebars print template
--     (pipeline_report -> supabase/examples/templates/pipeline_report.hbs)
--     and a MATERIALIZED VIEW report (revenue_rollup)
--   - Dashboard widgets: every contract (card_1..card_6, table_1,
--     table_2, list_1..list_4), global and resource-scoped
--   - Charts: every contract (pie, bar, line, area, radar), global
--     and resource-scoped
--   - Notifications (deal won and lost, stage movement, ownership
--     changes, lead assignment, task due dates, quote acceptance,
--     and a comment-notify pairing on supasheet.comments)
--   - Audit logging and per-resource comments
--   - Column footer aggregates via the `aggregate` column comment key
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260801000000_crm.sql \
--     -f supabase/examples/c_seed.sql
--
-- Requires the base Supasheet migrations (supabase/migrations/*) to
-- already be applied. Also add "crm" to config.toml's `api.schemas`
-- and `api.extra_search_path` so PostgREST exposes it, then restart
-- Supabase.
--
-- Not idempotent: `create schema` / `create type` / `create table`
-- fail on a second run. Re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists crm;

-------------------------------------------------------------------
-- Roles
--
-- "x-admin" ships with the base migrations. "user" and "admin" are
-- the optional built-in tiers (created in supabase/seed.sql), and
-- "manager"/"rep" are custom roles specific to this module — a
-- custom role is nothing more than `create role ... nologin` plus
-- grants.
--
--   x-admin  revenue operations: full control, including territory
--            design, the product catalogue and compensation
--   manager  sales manager: the whole pipeline, forecast and roster;
--            never sees compensation, and deletes nothing except the
--            line items and committee links that make up a deal
--   rep      account executive: works their own book — reads the
--            pipeline, edits what they own
--   user     read-only internal seat (support, finance): accounts,
--            contacts, products and interaction history, no pipeline
--
-- Assign a user to a custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "rep"}'
--   where email = 'rep@supasheet.app';
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

  if not exists (select 1 from pg_roles where rolname = 'manager') then
    create role "manager" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'rep') then
    create role "rep" nologin;
  end if;
end;
$$;

-- Let PostgREST SET ROLE into each role...
grant "user",
"admin",
"manager",
"rep" to authenticator;

-- ...and let `to authenticated` policies still apply to them.
grant authenticated to "user",
"admin",
"manager",
"rep";

-- Schema usage is granted per native role, never to `authenticated`.
grant usage on schema crm to "x-admin",
"manager",
"rep",
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

create type crm.account_type as enum(
  'prospect',
  'customer',
  'partner',
  'reseller',
  'former_customer'
);

create type crm.account_tier as enum('smb', 'mid_market', 'enterprise', 'strategic');

create type crm.account_health as enum('healthy', 'watch', 'at_risk', 'churned');

create type crm.contact_role as enum(
  'economic_buyer',
  'champion',
  'influencer',
  'technical_evaluator',
  'gatekeeper',
  'end_user'
);

create type crm.lead_status as enum(
  'new',
  'working',
  'nurturing',
  'qualified',
  'unqualified',
  'converted'
);

create type crm.lead_rating as enum('cold', 'warm', 'hot');

create type crm.lead_source as enum(
  'website',
  'referral',
  'event',
  'outbound',
  'partner',
  'inbound_call',
  'campaign'
);

create type crm.opportunity_stage as enum(
  'qualification',
  'discovery',
  'proposal',
  'negotiation',
  'closed_won',
  'closed_lost'
);

create type crm.opportunity_type as enum('new_business', 'expansion', 'upsell', 'renewal');

create type crm.forecast_category as enum(
  'omitted',
  'pipeline',
  'best_case',
  'commit',
  'closed'
);

create type crm.opportunity_event_type as enum(
  'created',
  'stage_changed',
  'amount_changed',
  'owner_changed',
  'closed_won',
  'closed_lost',
  'reopened',
  'activity_logged',
  'quote_sent',
  'record_updated'
);

create type crm.activity_type as enum(
  'call',
  'email',
  'meeting',
  'demo',
  'site_visit',
  'note'
);

create type crm.activity_direction as enum('inbound', 'outbound');

create type crm.activity_outcome as enum(
  'connected',
  'left_message',
  'no_answer',
  'rescheduled',
  'completed'
);

create type crm.task_status as enum(
  'not_started',
  'in_progress',
  'waiting',
  'completed',
  'cancelled'
);

create type crm.priority_level as enum('low', 'normal', 'high', 'urgent');

create type crm.quote_status as enum(
  'draft',
  'sent',
  'accepted',
  'declined',
  'expired'
);

create type crm.product_family as enum(
  'platform',
  'add_on',
  'service',
  'support',
  'training'
);

create type crm.billing_frequency as enum('one_time', 'monthly', 'quarterly', 'annual');

create type crm.rep_level as enum(
  'sdr',
  'account_executive',
  'senior_ae',
  'manager',
  'director'
);

create type crm.rep_status as enum('active', 'onboarding', 'on_leave', 'departed');

create type crm.campaign_status as enum(
  'planned',
  'active',
  'paused',
  'completed',
  'cancelled'
);

create type crm.campaign_channel as enum(
  'email',
  'event',
  'webinar',
  'paid_search',
  'content',
  'partner',
  'outbound'
);

commit;

----------------------------------------------------------------
-- Users replica view
--
-- FKs point at the real supasheet.users table, but PostgREST cannot
-- embed across schemas — every app schema needs a same-name replica
-- view so `query.join` on a user column resolves.
----------------------------------------------------------------
create or replace view crm.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on crm.users
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.users to "x-admin",
  "manager",
  "rep",
  "user";

----------------------------------------------------------------
-- Territories (self-referencing sales geography — tree view;
-- manager_id is backfilled after the roster exists)
----------------------------------------------------------------
create table crm.territories (
  id uuid primary key default extensions.uuid_generate_v4 (),
  parent_id uuid references crm.territories (id) on delete set null,
  name varchar(255) not null unique,
  code varchar(20) not null unique,
  description text,
  region varchar(100),
  annual_quota numeric(14, 2) not null default 0,
  is_active boolean not null default true,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint territories_quota_non_negative check (annual_quota >= 0)
);

comment on table crm.territories is '{
    "icon": "Map",
    "collapsible_group": "Organisation",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["region", "is_active"]},
        "tabs": ["sales_reps", "accounts", "opportunities", "territories"]
    },
    "views": [
        {
            "id": "tree",
            "name": "Territory Hierarchy",
            "type": "tree",
            "parent": "parent_id",
            "title": "name",
            "secondary": "region"
        },
        {
            "id": "list",
            "name": "All Territories",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "code",
            "field_2": "annual_quota"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "top_level", "name": "Top Level", "filters": [{"id": "parent_id", "value": "null", "operator": "is"}]}
    ],
    "fields": {
        "quick_create": ["name", "code", "region"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "code", "description", "parent_id"]},
            {"id": "coverage", "title": "Coverage", "fields": ["region", "manager_id", "is_active", "color"]},
            {"id": "target", "title": "Target", "fields": ["annual_quota"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [{"table": "territories", "on": "parent_id", "alias": "parent", "columns": ["name", "code"]}]
    }
}';

comment on column crm.territories.annual_quota is '{"name": "Annual Quota", "aggregate": "sum"}';

revoke all on table crm.territories
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
delete on table crm.territories to "x-admin";

grant
select
,
update on table crm.territories to "manager";

grant
select
  on table crm.territories to "rep",
  "user";

create index idx_crm_territories_parent_id on crm.territories (parent_id);

create index idx_crm_territories_is_active on crm.territories (is_active);

alter table crm.territories enable row level security;

create policy territories_select on crm.territories for
select
  to authenticated using (true);

create policy territories_insert on crm.territories for insert to authenticated
with
  check (true);

create policy territories_update on crm.territories
for update
  to authenticated using (true)
with
  check (true);

create policy territories_delete on crm.territories for delete to authenticated using (true);

----------------------------------------------------------------
-- Sales reps (the roster; org chart via manager_id)
----------------------------------------------------------------
create table crm.sales_reps (
  id uuid primary key default extensions.uuid_generate_v4 (),
  user_id uuid references supasheet.users (id) on delete set null,
  manager_id uuid references crm.sales_reps (id) on delete set null,
  territory_id uuid references crm.territories (id) on delete set null,
  name varchar(255) not null,
  avatar supasheet.AVATAR,
  email supasheet.EMAIL not null,
  phone supasheet.TEL,
  job_title varchar(255),
  level crm.rep_level not null default 'account_executive',
  status crm.rep_status not null default 'active',
  annual_quota numeric(14, 2) not null default 0,
  hire_date date,
  is_accepting_leads boolean not null default true,
  linkedin_url supasheet.URL,
  bio supasheet.RICH_TEXT,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint sales_reps_quota_non_negative check (annual_quota >= 0),
  constraint sales_reps_not_own_manager check (id <> manager_id)
);

comment on column crm.sales_reps.level is '{
    "progress": true,
    "values": {
        "sdr": {"variant": "secondary", "icon": "PhoneCall"},
        "account_executive": {"variant": "info", "icon": "Briefcase"},
        "senior_ae": {"variant": "default", "icon": "BriefcaseBusiness"},
        "manager": {"variant": "success", "icon": "UserCog"},
        "director": {"variant": "warning", "icon": "Crown"}
    }
}';

comment on column crm.sales_reps.status is '{
    "progress": false,
    "values": {
        "active": {"variant": "success", "icon": "CircleCheck"},
        "onboarding": {"variant": "info", "icon": "GraduationCap"},
        "on_leave": {"variant": "warning", "icon": "Coffee"},
        "departed": {"variant": "secondary", "icon": "LogOut"}
    }
}';

comment on table crm.sales_reps is '{
    "icon": "Users",
    "name": "Sales Reps",
    "collapsible_group": "Organisation",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["level", "status"]},
        "tabs": ["accounts", "opportunities", "leads", "activities", "tasks", "rep_compensation"]
    },
    "views": [
        {
            "id": "tree",
            "name": "Sales Org",
            "type": "tree",
            "parent": "manager_id",
            "title": "name",
            "secondary": "job_title"
        },
        {
            "id": "gallery",
            "name": "Team Directory",
            "type": "gallery",
            "cover": "avatar",
            "title": "name",
            "description": "job_title",
            "badge": "status"
        },
        {
            "id": "list",
            "name": "Roster",
            "type": "list",
            "title": "name",
            "description": "job_title",
            "field_1": "level",
            "field_2": "annual_quota"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "taking_leads", "name": "Taking Leads", "filters": [{"id": "is_accepting_leads", "value": "true", "operator": "eq"}]},
        {"id": "leadership", "name": "Leadership", "filters": [{"id": "level", "value": ["manager", "director"], "operator": "in"}]}
    ],
    "links": [
        {"id": "rep_performance", "name": "Rep Performance", "url": "/crm/report/rep_performance_report", "icon": "BarChart3", "description": "Quota attainment, win rate and cycle length per rep"}
    ],
    "fields": {
        "quick_create": ["name", "email", "level", "territory_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "avatar", "job_title", "level"]},
            {"id": "contact", "title": "Contact", "fields": ["email", "phone", "linkedin_url", "user_id"]},
            {"id": "assignment", "title": "Assignment", "fields": ["territory_id", "manager_id", "status", "is_accepting_leads"]},
            {"id": "target", "title": "Target", "fields": ["annual_quota", "hire_date"]},
            {"id": "extras", "title": "Bio", "collapsible": true, "fields": ["bio", "color"]}
        ],
        "behavior": {
            "is_accepting_leads": {"visible": [{"id": "status", "operator": "eq", "value": "active"}]},
            "manager_id": {"visible": [{"id": "level", "operator": "not.in", "value": ["director"]}]}
        }
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [
            {"table": "users", "on": "user_id", "columns": ["name", "email"]},
            {"table": "territories", "on": "territory_id", "columns": ["name", "code"]},
            {"table": "sales_reps", "on": "manager_id", "alias": "manager", "columns": ["name", "job_title"]}
        ]
    }
}';

comment on column crm.sales_reps.avatar is '{"accept": "image/*", "max_size": 2097152}';

comment on column crm.sales_reps.annual_quota is '{"name": "Quota", "aggregate": "sum"}';

revoke all on table crm.sales_reps
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
delete on table crm.sales_reps to "x-admin";

grant
select
,
  insert,
update on table crm.sales_reps to "manager";

grant
select
  on table crm.sales_reps to "rep",
  "user";

-- Column-level grant: a rep keeps their own profile current, but the
-- quota, the level and the reporting line stay with the business.
grant
update (
  avatar,
  phone,
  job_title,
  linkedin_url,
  bio,
  is_accepting_leads,
  color
) on table crm.sales_reps to "rep";

create index idx_crm_sales_reps_user_id on crm.sales_reps (user_id);

create index idx_crm_sales_reps_manager_id on crm.sales_reps (manager_id);

create index idx_crm_sales_reps_territory_id on crm.sales_reps (territory_id);

create index idx_crm_sales_reps_status on crm.sales_reps (status);

-- One rep record per login: the ownership helper below assumes it.
create unique index idx_crm_sales_reps_user_unique on crm.sales_reps (user_id)
where
  user_id is not null;

alter table crm.sales_reps enable row level security;

create policy sales_reps_select on crm.sales_reps for
select
  to authenticated using (true);

create policy sales_reps_insert on crm.sales_reps for insert to authenticated
with
  check (true);

-- A rep may only edit the row that maps to their own login; managers
-- and revenue operations may edit anyone.
create policy sales_reps_update on crm.sales_reps
for update
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'manager', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy sales_reps_delete on crm.sales_reps for delete to authenticated using (true);

-- Territories gained a manager only after the roster existed —
-- adding the FK afterwards is the normal pattern for a circular
-- reference.
alter table crm.territories
add column manager_id uuid references crm.sales_reps (id) on delete set null;

create index idx_crm_territories_manager_id on crm.territories (manager_id);

----------------------------------------------------------------
-- Ownership helper
--
-- Every owner-scoped policy below needs "which rep record is this
-- login?". Doing that inline would mean a correlated subquery
-- against a table that is itself under RLS; a STABLE SECURITY
-- DEFINER function is evaluated once per statement, bypasses the
-- recursive policy check, and leaves the policy as a plain equality
-- the planner can use an index for.
----------------------------------------------------------------
create or replace function crm.current_rep_id () returns uuid language sql stable security definer
set
  search_path = '' as $$
  select id
  from crm.sales_reps
  where user_id = auth.uid ()
  limit 1;
$$;

revoke all on function crm.current_rep_id ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.current_rep_id () to "x-admin",
"manager",
"rep",
"user";

-- The same question, asked the other way round: may the caller reach
-- across the whole book of business?
create or replace function crm.is_sales_leadership () returns boolean language sql stable
set
  search_path = '' as $$
  select pg_has_role(current_user, 'manager', 'member')
      or pg_has_role(current_user, 'x-admin', 'member');
$$;

revoke all on function crm.is_sales_leadership ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.is_sales_leadership () to "x-admin",
"manager",
"rep",
"user";

----------------------------------------------------------------
-- Rep compensation (1:1 extension — a unique, not-null FK keeps pay
-- data off the roster record. Granted to x-admin only, so managers
-- and reps never see it.)
----------------------------------------------------------------
create table crm.rep_compensation (
  id uuid primary key default extensions.uuid_generate_v4 (),
  rep_id uuid not null references crm.sales_reps (id) on delete cascade,
  base_salary numeric(12, 2) not null default 0,
  variable_target numeric(12, 2) not null default 0,
  commission_rate supasheet.PERCENTAGE not null default 0,
  accelerator_rate supasheet.PERCENTAGE,
  accelerator_threshold supasheet.PERCENTAGE,
  currency varchar(3) not null default 'USD',
  contract supasheet.file,
  effective_from date not null default current_date,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (rep_id),
  constraint rep_compensation_rates_sane check (
    base_salary >= 0
    and variable_target >= 0
    and commission_rate >= 0
    and commission_rate <= 100
  )
);

comment on table crm.rep_compensation is '{
    "icon": "Banknote",
    "name": "Compensation",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "rep", "title": "Rep", "fields": ["rep_id", "effective_from", "currency"]},
            {"id": "pay", "title": "Pay", "fields": ["base_salary", "variable_target", "commission_rate"]},
            {"id": "accelerator", "title": "Accelerator", "fields": ["accelerator_threshold", "accelerator_rate"]},
            {"id": "extras", "title": "Contract & notes", "collapsible": true, "fields": ["contract", "notes"]}
        ],
        "behavior": {
            "accelerator_rate": {"required": [{"id": "accelerator_threshold", "operator": "not.is", "value": "null"}]}
        }
    },
    "query": {
        "join": [{"table": "sales_reps", "on": "rep_id", "columns": ["name", "level"]}]
    }
}';

comment on column crm.rep_compensation.contract is '{"accept": ".pdf", "max_files": 3, "max_size": 10485760}';

comment on column crm.rep_compensation.base_salary is '{"aggregate": "sum"}';

comment on column crm.rep_compensation.variable_target is '{"aggregate": "sum"}';

revoke all on table crm.rep_compensation
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
delete on table crm.rep_compensation to "x-admin";

create index idx_crm_rep_compensation_rep_id on crm.rep_compensation (rep_id);

alter table crm.rep_compensation enable row level security;

create policy rep_compensation_select on crm.rep_compensation for
select
  to authenticated using (true);

create policy rep_compensation_insert on crm.rep_compensation for insert to authenticated
with
  check (true);

create policy rep_compensation_update on crm.rep_compensation
for update
  to authenticated using (true)
with
  check (true);

create policy rep_compensation_delete on crm.rep_compensation for delete to authenticated using (true);

----------------------------------------------------------------
-- Accounts (companies — the record everything else hangs off)
----------------------------------------------------------------
create table crm.accounts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null,
  legal_name varchar(255),
  parent_account_id uuid references crm.accounts (id) on delete set null,
  owner_id uuid references crm.sales_reps (id) on delete set null,
  territory_id uuid references crm.territories (id) on delete set null,
  account_type crm.account_type not null default 'prospect',
  tier crm.account_tier not null default 'smb',
  health crm.account_health not null default 'healthy',
  health_score supasheet.PERCENTAGE,
  relationship_strength supasheet.RATING,
  website supasheet.URL,
  phone supasheet.TEL,
  industry varchar(120),
  employee_count integer,
  annual_revenue numeric(14, 2),
  billing_city varchar(120),
  billing_country varchar(120),
  logo supasheet.file,
  description supasheet.RICH_TEXT,
  tags varchar(500) [],
  customer_since date,
  churned_on date,
  churn_reason varchar(500),
  open_opportunity_count integer not null default 0,
  open_pipeline_amount numeric(14, 2) not null default 0,
  won_amount numeric(14, 2) not null default 0,
  last_activity_at timestamptz,
  color supasheet.COLOR,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint accounts_not_own_parent check (id <> parent_account_id),
  constraint accounts_employee_count_sane check (
    employee_count is null
    or employee_count >= 0
  ),
  constraint accounts_revenue_sane check (
    annual_revenue is null
    or annual_revenue >= 0
  )
);

comment on column crm.accounts.account_type is '{
    "progress": false,
    "values": {
        "prospect": {"variant": "secondary", "icon": "Search"},
        "customer": {"variant": "success", "icon": "Handshake"},
        "partner": {"variant": "info", "icon": "Link"},
        "reseller": {"variant": "default", "icon": "Store"},
        "former_customer": {"variant": "destructive", "icon": "UserMinus"}
    }
}';

comment on column crm.accounts.tier is '{
    "progress": true,
    "values": {
        "smb": {"variant": "secondary", "icon": "Building"},
        "mid_market": {"variant": "info", "icon": "Building2"},
        "enterprise": {"variant": "default", "icon": "Landmark"},
        "strategic": {"variant": "warning", "icon": "Crown"}
    }
}';

comment on column crm.accounts.health is '{
    "progress": true,
    "values": {
        "healthy": {"variant": "success", "icon": "HeartPulse"},
        "watch": {"variant": "info", "icon": "Eye"},
        "at_risk": {"variant": "warning", "icon": "TriangleAlert"},
        "churned": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on table crm.accounts is '{
    "icon": "Building2",
    "collapsible_group": "Customers",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "name", "badges": ["account_type", "tier", "health"]},
        "tabs": ["contacts", "opportunities", "activities", "tasks", "quotes", "accounts"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "By Health",
            "type": "kanban",
            "group": "health",
            "title": "name",
            "description": "industry",
            "date": "customer_since",
            "badge": "tier"
        },
        {
            "id": "gallery",
            "name": "Logos",
            "type": "gallery",
            "cover": "logo",
            "title": "name",
            "description": "industry",
            "badge": "account_type"
        },
        {
            "id": "tree",
            "name": "Corporate Structure",
            "type": "tree",
            "parent": "parent_account_id",
            "title": "name",
            "secondary": "billing_country"
        },
        {
            "id": "list",
            "name": "All Accounts",
            "type": "list",
            "title": "name",
            "description": "industry",
            "field_1": "tier",
            "field_2": "open_pipeline_amount"
        }
    ],
    "filter_presets": [
        {"id": "my_accounts", "name": "Customers", "filters": [{"id": "account_type", "value": "customer", "operator": "eq"}]},
        {"id": "prospects", "name": "Prospects", "filters": [{"id": "account_type", "value": "prospect", "operator": "eq"}]},
        {"id": "at_risk", "name": "At Risk", "filters": [{"id": "health", "value": ["at_risk", "churned"], "operator": "in"}]},
        {"id": "strategic", "name": "Enterprise & Strategic", "filters": [{"id": "tier", "value": ["enterprise", "strategic"], "operator": "in"}]},
        {"id": "unowned", "name": "Unassigned", "filters": [{"id": "owner_id", "value": "null", "operator": "is"}]}
    ],
    "links": [
        {"id": "account_report", "name": "Account Report", "url": "/crm/report/accounts_report", "icon": "FileText", "description": "Pipeline, revenue and engagement per account"}
    ],
    "fields": {
        "quick_create": ["name", "account_type", "owner_id", "industry"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "legal_name", "logo", "website", "phone"]},
            {"id": "classification", "title": "Classification", "fields": ["account_type", "tier", "industry", "employee_count", "annual_revenue"]},
            {"id": "ownership", "title": "Ownership", "fields": ["owner_id", "territory_id", "parent_account_id"]},
            {"id": "relationship", "title": "Relationship", "fields": ["health", "health_score", "relationship_strength", "customer_since"]},
            {"id": "churn", "title": "Churn", "fields": ["churned_on", "churn_reason"]},
            {"id": "address", "title": "Address", "collapsible": true, "fields": ["billing_city", "billing_country"]},
            {"id": "rollups", "title": "Pipeline", "fields": {"read": ["open_opportunity_count", "open_pipeline_amount", "won_amount", "last_activity_at"]}},
            {"id": "extras", "title": "Notes & tags", "collapsible": true, "fields": ["description", "tags", "color"]}
        ],
        "behavior": {
            "churned_on": {"visible": [{"id": "health", "operator": "eq", "value": "churned"}]},
            "churn_reason": {
                "visible": [{"id": "health", "operator": "eq", "value": "churned"}],
                "required": [{"id": "health", "operator": "eq", "value": "churned"}]
            },
            "customer_since": {"visible": [{"id": "account_type", "operator": "in", "value": ["customer", "former_customer"]}]}
        },
        "lookups": {
            "parent_account_id": {"fill": [{"source_column": "territory_id", "target_column": "territory_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [
            {"table": "sales_reps", "on": "owner_id", "alias": "owner", "columns": ["name", "avatar"]},
            {"table": "territories", "on": "territory_id", "columns": ["name", "code"]},
            {"table": "accounts", "on": "parent_account_id", "alias": "parent_account", "columns": ["name", "tier"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column crm.accounts.logo is '{"accept": "image/*", "max_size": 2097152}';

comment on column crm.accounts.annual_revenue is '{"name": "Annual Revenue", "aggregate": "sum"}';

comment on column crm.accounts.employee_count is '{"name": "Employees", "aggregate": "sum"}';

comment on column crm.accounts.open_pipeline_amount is '{"name": "Open Pipeline", "aggregate": "sum"}';

comment on column crm.accounts.won_amount is '{"name": "Closed Won", "aggregate": "sum"}';

comment on column crm.accounts.health_score is '{"name": "Health Score", "aggregate": "avg"}';

comment on column crm.accounts.relationship_strength is '{"name": "Relationship", "aggregate": "avg"}';

revoke all on table crm.accounts
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
delete on table crm.accounts to "x-admin";

grant
select
,
  insert,
update on table crm.accounts to "manager",
"rep";

grant
select
  on table crm.accounts to "user";

-- Case-insensitive dedupe: two "acme corp" records are the single
-- most expensive kind of mess in a CRM.
create unique index idx_crm_accounts_name_unique on crm.accounts (lower(name));

create index idx_crm_accounts_owner_id on crm.accounts (owner_id);

create index idx_crm_accounts_territory_id on crm.accounts (territory_id);

create index idx_crm_accounts_parent_account_id on crm.accounts (parent_account_id);

create index idx_crm_accounts_account_type on crm.accounts (account_type);

create index idx_crm_accounts_health on crm.accounts (health);

create index idx_crm_accounts_tier on crm.accounts (tier);

create index idx_crm_accounts_created_at on crm.accounts (created_at desc);

alter table crm.accounts enable row level security;

-- Read the whole book, edit your own: the pattern most sales teams
-- actually run. Leadership edits anything.
create policy accounts_select on crm.accounts for
select
  to authenticated using (true);

create policy accounts_insert on crm.accounts for insert to authenticated
with
  check (true);

create policy accounts_update on crm.accounts
for update
  to authenticated using (
    owner_id is null
    or owner_id = crm.current_rep_id ()
    or crm.is_sales_leadership ()
  )
with
  check (true);

create policy accounts_delete on crm.accounts for delete to authenticated using (true);

----------------------------------------------------------------
-- Contacts (people at an account; reporting lines via reports_to_id)
----------------------------------------------------------------
create table crm.contacts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  account_id uuid not null references crm.accounts (id) on delete cascade,
  reports_to_id uuid references crm.contacts (id) on delete set null,
  owner_id uuid references crm.sales_reps (id) on delete set null,
  first_name varchar(120) not null,
  last_name varchar(120) not null,
  -- Maintained by crm.trg_contacts_apply_defaults so joins, lookups
  -- and every display column have one field to point at.
  name varchar(255),
  email supasheet.EMAIL,
  phone supasheet.TEL,
  mobile supasheet.TEL,
  job_title varchar(255),
  department varchar(120),
  contact_role crm.contact_role not null default 'end_user',
  is_primary boolean not null default false,
  avatar supasheet.AVATAR,
  linkedin_url supasheet.URL,
  mailing_city varchar(120),
  mailing_country varchar(120),
  do_not_contact boolean not null default false,
  email_opt_out boolean not null default false,
  last_contacted_at timestamptz,
  birthday date,
  notes text,
  tags varchar(500) [],
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint contacts_not_own_manager check (id <> reports_to_id)
);

comment on column crm.contacts.contact_role is '{
    "progress": false,
    "values": {
        "economic_buyer": {"variant": "success", "icon": "BadgeDollarSign"},
        "champion": {"variant": "default", "icon": "Star"},
        "influencer": {"variant": "info", "icon": "Megaphone"},
        "technical_evaluator": {"variant": "secondary", "icon": "Wrench"},
        "gatekeeper": {"variant": "warning", "icon": "DoorClosed"},
        "end_user": {"variant": "secondary", "icon": "User"}
    }
}';

comment on table crm.contacts is '{
    "icon": "Contact",
    "collapsible_group": "Customers",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["contact_role", "is_primary"]},
        "tabs": ["activities", "tasks", "opportunity_contacts", "contacts"]
    },
    "views": [
        {
            "id": "list",
            "name": "All Contacts",
            "type": "list",
            "title": "name",
            "description": "job_title",
            "field_1": "contact_role",
            "field_2": "email"
        },
        {
            "id": "tree",
            "name": "Reporting Lines",
            "type": "tree",
            "parent": "reports_to_id",
            "title": "name",
            "secondary": "job_title"
        },
        {
            "id": "gallery",
            "name": "Directory",
            "type": "gallery",
            "cover": "avatar",
            "title": "name",
            "description": "job_title",
            "badge": "contact_role"
        }
    ],
    "filter_presets": [
        {"id": "primary", "name": "Primary", "filters": [{"id": "is_primary", "value": "true", "operator": "eq"}]},
        {"id": "buyers", "name": "Decision Makers", "filters": [{"id": "contact_role", "value": ["economic_buyer", "champion"], "operator": "in"}]},
        {"id": "contactable", "name": "Contactable", "filters": [{"id": "do_not_contact", "value": "false", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["first_name", "last_name", "account_id", "email"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["first_name", "last_name", "avatar", "job_title", "department"]},
            {"id": "account", "title": "Account", "fields": ["account_id", "reports_to_id", "owner_id", "contact_role", "is_primary"]},
            {"id": "contact", "title": "Contact details", "fields": ["email", "phone", "mobile", "linkedin_url"]},
            {"id": "consent", "title": "Consent", "fields": ["do_not_contact", "email_opt_out"]},
            {"id": "address", "title": "Address", "collapsible": true, "fields": ["mailing_city", "mailing_country", "birthday"]},
            {"id": "engagement", "title": "Engagement", "fields": {"read": ["last_contacted_at"]}},
            {"id": "extras", "title": "Notes & tags", "collapsible": true, "fields": ["notes", "tags"]}
        ],
        "behavior": {
            "email_opt_out": {"read_only": [{"id": "do_not_contact", "operator": "eq", "value": "true"}]}
        },
        "lookups": {
            "reports_to_id": {"filter": [{"source_column": "account_id", "target_column": "account_id"}]},
            "account_id": {"fill": [{"source_column": "owner_id", "target_column": "owner_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [
            {"table": "accounts", "on": "account_id", "columns": ["name", "tier"]},
            {"table": "sales_reps", "on": "owner_id", "alias": "owner", "columns": ["name", "avatar"]},
            {"table": "contacts", "on": "reports_to_id", "alias": "manager", "columns": ["name", "job_title"]}
        ]
    }
}';

comment on column crm.contacts.avatar is '{"accept": "image/*", "max_size": 2097152}';

comment on column crm.contacts.name is '{"name": "Full Name", "icon": "User"}';

revoke all on table crm.contacts
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
delete on table crm.contacts to "x-admin";

grant
select
,
  insert,
update on table crm.contacts to "manager",
"rep";

grant
select
  on table crm.contacts to "user";

-- One address per account, not one per database: the same person can
-- legitimately appear under two customers.
create unique index idx_crm_contacts_account_email_unique on crm.contacts (account_id, lower(email))
where
  email is not null;

-- At most one primary contact per account.
create unique index idx_crm_contacts_primary_unique on crm.contacts (account_id)
where
  is_primary;

create index idx_crm_contacts_account_id on crm.contacts (account_id);

create index idx_crm_contacts_owner_id on crm.contacts (owner_id);

create index idx_crm_contacts_reports_to_id on crm.contacts (reports_to_id);

create index idx_crm_contacts_contact_role on crm.contacts (contact_role);

create index idx_crm_contacts_name on crm.contacts (name);

alter table crm.contacts enable row level security;

create policy contacts_select on crm.contacts for
select
  to authenticated using (true);

create policy contacts_insert on crm.contacts for insert to authenticated
with
  check (true);

create policy contacts_update on crm.contacts
for update
  to authenticated using (
    owner_id is null
    or owner_id = crm.current_rep_id ()
    or crm.is_sales_leadership ()
  )
with
  check (true);

create policy contacts_delete on crm.contacts for delete to authenticated using (true);

----------------------------------------------------------------
-- Campaigns (marketing programmes — the gantt roadmap)
----------------------------------------------------------------
create table crm.campaigns (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null unique,
  code varchar(30) not null unique,
  status crm.campaign_status not null default 'planned',
  channel crm.campaign_channel not null default 'email',
  owner_id uuid references crm.sales_reps (id) on delete set null,
  description supasheet.RICH_TEXT,
  start_on date not null default current_date,
  end_on date not null default (current_date + 30),
  budget numeric(12, 2) not null default 0,
  actual_cost numeric(12, 2) not null default 0,
  target_leads integer not null default 0,
  leads_generated integer not null default 0,
  opportunities_created integer not null default 0,
  influenced_amount numeric(14, 2) not null default 0,
  progress supasheet.PERCENTAGE not null default 0,
  color supasheet.COLOR,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint campaigns_dates_ordered check (end_on >= start_on),
  constraint campaigns_money_non_negative check (
    budget >= 0
    and actual_cost >= 0
  )
);

comment on column crm.campaigns.status is '{
    "progress": true,
    "values": {
        "planned": {"variant": "secondary", "icon": "CalendarClock"},
        "active": {"variant": "info", "icon": "Rocket"},
        "paused": {"variant": "warning", "icon": "PauseCircle"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "cancelled": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on column crm.campaigns.channel is '{
    "progress": false,
    "values": {
        "email": {"variant": "info", "icon": "Mail"},
        "event": {"variant": "default", "icon": "Tent"},
        "webinar": {"variant": "success", "icon": "Video"},
        "paid_search": {"variant": "warning", "icon": "Search"},
        "content": {"variant": "secondary", "icon": "FileText"},
        "partner": {"variant": "info", "icon": "Handshake"},
        "outbound": {"variant": "default", "icon": "PhoneOutgoing"}
    }
}';

comment on table crm.campaigns is '{
    "icon": "Megaphone",
    "collapsible_group": "Demand",
    "display": "block",
    "primary_view": "gantt",
    "detail": {
        "header": {"title": "name", "badges": ["status", "channel"]},
        "tabs": ["leads", "opportunities"]
    },
    "views": [
        {
            "id": "gantt",
            "name": "Programme Calendar",
            "type": "gantt",
            "title": "name",
            "start_date": "start_on",
            "end_date": "end_on",
            "group": "status",
            "progress": "progress",
            "badge": "channel"
        },
        {
            "id": "kanban",
            "name": "By Stage",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "code",
            "date": "end_on",
            "badge": "channel"
        },
        {
            "id": "list",
            "name": "All Campaigns",
            "type": "list",
            "title": "name",
            "description": "code",
            "field_1": "status",
            "field_2": "influenced_amount"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "over_budget", "name": "Over Budget", "filters": [{"id": "status", "value": ["active", "completed"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["name", "code", "channel", "start_on"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "code", "channel", "description"]},
            {"id": "plan", "title": "Plan", "fields": ["owner_id", "status", "start_on", "end_on", "target_leads", "budget"]},
            {"id": "spend", "title": "Spend", "fields": ["actual_cost"]},
            {"id": "results", "title": "Results", "fields": {"read": ["leads_generated", "opportunities_created", "influenced_amount", "progress"]}},
            {"id": "extras", "title": "Presentation", "collapsible": true, "fields": ["color"]}
        ],
        "behavior": {
            "actual_cost": {"read_only": [{"id": "status", "operator": "in", "value": ["completed", "cancelled"]}]}
        }
    },
    "query": {
        "sort": [{"id": "start_on", "desc": true}],
        "join": [
            {"table": "sales_reps", "on": "owner_id", "alias": "owner", "columns": ["name", "avatar"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column crm.campaigns.budget is '{"aggregate": "sum"}';

comment on column crm.campaigns.actual_cost is '{"name": "Actual Cost", "aggregate": "sum"}';

comment on column crm.campaigns.influenced_amount is '{"name": "Influenced", "aggregate": "sum"}';

comment on column crm.campaigns.leads_generated is '{"name": "Leads", "aggregate": "sum"}';

revoke all on table crm.campaigns
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
delete on table crm.campaigns to "x-admin";

grant
select
,
  insert,
update on table crm.campaigns to "manager";

grant
select
  on table crm.campaigns to "rep";

create index idx_crm_campaigns_status on crm.campaigns (status);

create index idx_crm_campaigns_owner_id on crm.campaigns (owner_id);

create index idx_crm_campaigns_start_on on crm.campaigns (start_on);

create index idx_crm_campaigns_end_on on crm.campaigns (end_on);

alter table crm.campaigns enable row level security;

create policy campaigns_select on crm.campaigns for
select
  to authenticated using (true);

create policy campaigns_insert on crm.campaigns for insert to authenticated
with
  check (true);

create policy campaigns_update on crm.campaigns
for update
  to authenticated using (true)
with
  check (true);

create policy campaigns_delete on crm.campaigns for delete to authenticated using (true);

----------------------------------------------------------------
-- Leads (unqualified demand, before it becomes an account)
----------------------------------------------------------------
create sequence if not exists crm.lead_number_seq;

create table crm.leads (
  id uuid primary key default extensions.uuid_generate_v4 (),
  reference varchar(30) not null unique default (
    'LEAD-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('crm.lead_number_seq')::text, 5, '0')
  ),
  first_name varchar(120) not null,
  last_name varchar(120) not null,
  name varchar(255),
  company varchar(255) not null,
  job_title varchar(255),
  email supasheet.EMAIL,
  phone supasheet.TEL,
  website supasheet.URL,
  status crm.lead_status not null default 'new',
  rating crm.lead_rating not null default 'cold',
  source crm.lead_source not null default 'website',
  score supasheet.PERCENTAGE not null default 0,
  owner_id uuid references crm.sales_reps (id) on delete set null,
  campaign_id uuid references crm.campaigns (id) on delete set null,
  territory_id uuid references crm.territories (id) on delete set null,
  industry varchar(120),
  employee_count integer,
  estimated_value numeric(14, 2),
  country varchar(120),
  notes supasheet.RICH_TEXT,
  disqualified_reason varchar(500),
  last_contacted_at timestamptz,
  converted_at timestamptz,
  converted_account_id uuid references crm.accounts (id) on delete set null,
  converted_contact_id uuid references crm.contacts (id) on delete set null,
  tags varchar(500) [],
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint leads_score_range check (
    score >= 0
    and score <= 100
  ),
  constraint leads_value_non_negative check (
    estimated_value is null
    or estimated_value >= 0
  )
);

comment on column crm.leads.status is '{
    "progress": true,
    "values": {
        "new": {"variant": "info", "icon": "Sparkles"},
        "working": {"variant": "default", "icon": "PhoneCall"},
        "nurturing": {"variant": "secondary", "icon": "Sprout"},
        "qualified": {"variant": "success", "icon": "CircleCheck"},
        "unqualified": {"variant": "destructive", "icon": "CircleX"},
        "converted": {"variant": "success", "icon": "ArrowRightLeft"}
    }
}';

comment on column crm.leads.rating is '{
    "progress": true,
    "icon_only": true,
    "values": {
        "cold": {"variant": "secondary", "icon": "Snowflake"},
        "warm": {"variant": "warning", "icon": "Thermometer"},
        "hot": {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on column crm.leads.source is '{
    "progress": false,
    "values": {
        "website": {"variant": "info", "icon": "Globe"},
        "referral": {"variant": "success", "icon": "Handshake"},
        "event": {"variant": "default", "icon": "Tent"},
        "outbound": {"variant": "warning", "icon": "PhoneOutgoing"},
        "partner": {"variant": "info", "icon": "Link"},
        "inbound_call": {"variant": "default", "icon": "PhoneIncoming"},
        "campaign": {"variant": "secondary", "icon": "Megaphone"}
    }
}';

comment on table crm.leads is '{
    "icon": "UserPlus",
    "collapsible_group": "Demand",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "name", "badges": ["status", "rating", "source"]},
        "tabs": ["activities", "tasks"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Lead Queue",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "company",
            "date": "last_contacted_at",
            "badge": "rating"
        },
        {
            "id": "list",
            "name": "All Leads",
            "type": "list",
            "title": "name",
            "description": "company",
            "field_1": "status",
            "field_2": "score"
        }
    ],
    "filter_presets": [
        {"id": "mine", "name": "Unassigned", "filters": [{"id": "owner_id", "value": "null", "operator": "is"}]},
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["new", "working", "nurturing"], "operator": "in"}]},
        {"id": "hot", "name": "Hot", "filters": [{"id": "rating", "value": "hot", "operator": "eq"}]},
        {"id": "qualified", "name": "Qualified", "filters": [{"id": "status", "value": "qualified", "operator": "eq"}]},
        {"id": "high_score", "name": "Score 70+", "filters": [{"id": "score", "value": "70", "operator": "gte"}]}
    ],
    "fields": {
        "quick_create": ["first_name", "last_name", "company", "email", "source"],
        "sections": [
            {"id": "person", "title": "Person", "fields": ["first_name", "last_name", "job_title", "email", "phone"]},
            {"id": "company", "title": "Company", "fields": ["company", "website", "industry", "employee_count", "country"]},
            {"id": "qualification", "title": "Qualification", "fields": ["status", "rating", "score", "estimated_value"]},
            {"id": "routing", "title": "Routing", "fields": ["owner_id", "territory_id", "source", "campaign_id"]},
            {"id": "disqualification", "title": "Disqualification", "fields": ["disqualified_reason"]},
            {"id": "conversion", "title": "Conversion", "fields": {"read": ["converted_at", "converted_account_id", "converted_contact_id"]}},
            {"id": "extras", "title": "Notes & tags", "collapsible": true, "fields": ["notes", "tags", "last_contacted_at"]}
        ],
        "behavior": {
            "disqualified_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "unqualified"}],
                "required": [{"id": "status", "operator": "eq", "value": "unqualified"}]
            },
            "estimated_value": {"visible": [{"id": "status", "operator": "not.in", "value": ["new", "unqualified"]}]},
            "campaign_id": {"visible": [{"id": "source", "operator": "eq", "value": "campaign"}]},
            "score": {"read_only": [{"id": "status", "operator": "in", "value": ["converted", "unqualified"]}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "sales_reps", "on": "owner_id", "alias": "owner", "columns": ["name", "avatar"]},
            {"table": "campaigns", "on": "campaign_id", "columns": ["name", "channel"]},
            {"table": "territories", "on": "territory_id", "columns": ["name", "code"]},
            {"table": "accounts", "on": "converted_account_id", "alias": "converted_account", "columns": ["name", "tier"]}
        ]
    }
}';

comment on column crm.leads.score is '{"name": "Lead Score", "aggregate": "avg"}';

comment on column crm.leads.estimated_value is '{"name": "Est. Value", "aggregate": "sum"}';

comment on column crm.leads.reference is '{"name": "Ref", "icon": "Hash"}';

revoke all on table crm.leads
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
delete on table crm.leads to "x-admin";

grant
select
,
  insert,
update on table crm.leads to "manager",
"rep";

revoke all on sequence crm.lead_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence crm.lead_number_seq to "x-admin",
"manager",
"rep";

create index idx_crm_leads_owner_id on crm.leads (owner_id);

create index idx_crm_leads_campaign_id on crm.leads (campaign_id);

create index idx_crm_leads_territory_id on crm.leads (territory_id);

create index idx_crm_leads_status on crm.leads (status);

create index idx_crm_leads_rating on crm.leads (rating);

create index idx_crm_leads_created_at on crm.leads (created_at desc);

-- The queue every rep opens first: open leads, newest first.
create index idx_crm_leads_open_queue on crm.leads (owner_id, created_at desc)
where
  status in ('new', 'working', 'nurturing');

alter table crm.leads enable row level security;

-- Leads are worked, not browsed: you see your own and anything still
-- sitting in the unassigned pool. Leadership sees the lot.
create policy leads_select on crm.leads for
select
  to authenticated using (
    owner_id is null
    or owner_id = crm.current_rep_id ()
    or crm.is_sales_leadership ()
  );

create policy leads_insert on crm.leads for insert to authenticated
with
  check (true);

create policy leads_update on crm.leads
for update
  to authenticated using (
    owner_id is null
    or owner_id = crm.current_rep_id ()
    or crm.is_sales_leadership ()
  )
with
  check (true);

create policy leads_delete on crm.leads for delete to authenticated using (true);

----------------------------------------------------------------
-- Pipeline stages (the reference table the deal maths reads from —
-- change a probability here and every open deal follows)
----------------------------------------------------------------
create table crm.pipeline_stages (
  id uuid primary key default extensions.uuid_generate_v4 (),
  stage crm.opportunity_stage not null unique,
  name varchar(120) not null,
  description text,
  guidance supasheet.RICH_TEXT,
  sort_order integer not null default 0,
  default_probability supasheet.PERCENTAGE not null default 0,
  forecast_category crm.forecast_category not null default 'pipeline',
  is_closed boolean not null default false,
  is_won boolean not null default false,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint pipeline_stages_probability_range check (
    default_probability >= 0
    and default_probability <= 100
  ),
  constraint pipeline_stages_won_implies_closed check (
    not is_won
    or is_closed
  )
);

comment on table crm.pipeline_stages is '{
    "icon": "GitBranch",
    "name": "Pipeline Stages",
    "collapsible_group": "Configuration",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["forecast_category", "is_closed"]},
        "tabs": []
    },
    "views": [
        {
            "id": "list",
            "name": "Stages",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "default_probability",
            "field_2": "forecast_category"
        }
    ],
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["stage", "name", "description", "sort_order", "color"]},
            {"id": "maths", "title": "Forecast maths", "fields": ["default_probability", "forecast_category", "is_closed", "is_won"]},
            {"id": "playbook", "title": "Exit criteria", "collapsible": true, "fields": ["guidance"]}
        ],
        "behavior": {
            "is_won": {"visible": [{"id": "is_closed", "operator": "eq", "value": "true"}]}
        }
    },
    "query": {
        "sort": [{"id": "sort_order", "desc": false}]
    }
}';

comment on column crm.pipeline_stages.default_probability is '{"name": "Probability", "aggregate": "avg"}';

revoke all on table crm.pipeline_stages
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
delete on table crm.pipeline_stages to "x-admin";

grant
select
  on table crm.pipeline_stages to "manager",
  "rep",
  "user";

create index idx_crm_pipeline_stages_sort_order on crm.pipeline_stages (sort_order);

alter table crm.pipeline_stages enable row level security;

create policy pipeline_stages_select on crm.pipeline_stages for
select
  to authenticated using (true);

create policy pipeline_stages_insert on crm.pipeline_stages for insert to authenticated
with
  check (true);

create policy pipeline_stages_update on crm.pipeline_stages
for update
  to authenticated using (true)
with
  check (true);

create policy pipeline_stages_delete on crm.pipeline_stages for delete to authenticated using (true);

----------------------------------------------------------------
-- Products (the catalogue deals are priced from)
----------------------------------------------------------------
create table crm.products (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(40) not null unique,
  name varchar(255) not null,
  family crm.product_family not null default 'platform',
  description text,
  image supasheet.file,
  list_price numeric(12, 2) not null default 0,
  unit_cost numeric(12, 2),
  currency varchar(3) not null default 'USD',
  billing_frequency crm.billing_frequency not null default 'annual',
  minimum_term_months integer not null default 12,
  is_active boolean not null default true,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint products_price_non_negative check (list_price >= 0),
  constraint products_cost_non_negative check (
    unit_cost is null
    or unit_cost >= 0
  )
);

comment on column crm.products.family is '{
    "progress": false,
    "values": {
        "platform": {"variant": "default", "icon": "Box"},
        "add_on": {"variant": "info", "icon": "PackagePlus"},
        "service": {"variant": "warning", "icon": "Wrench"},
        "support": {"variant": "success", "icon": "LifeBuoy"},
        "training": {"variant": "secondary", "icon": "GraduationCap"}
    }
}';

comment on column crm.products.billing_frequency is '{
    "progress": false,
    "values": {
        "one_time": {"variant": "secondary", "icon": "Receipt"},
        "monthly": {"variant": "info", "icon": "CalendarDays"},
        "quarterly": {"variant": "default", "icon": "CalendarRange"},
        "annual": {"variant": "success", "icon": "CalendarCheck"}
    }
}';

comment on table crm.products is '{
    "icon": "Package",
    "collapsible_group": "Configuration",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "name", "badges": ["family", "is_active"]},
        "tabs": ["opportunity_line_items"]
    },
    "views": [
        {
            "id": "gallery",
            "name": "Catalogue",
            "type": "gallery",
            "cover": "image",
            "title": "name",
            "description": "description",
            "badge": "family"
        },
        {
            "id": "list",
            "name": "Price List",
            "type": "list",
            "title": "name",
            "description": "code",
            "field_1": "list_price",
            "field_2": "billing_frequency"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "platform", "name": "Platform", "filters": [{"id": "family", "value": "platform", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "family", "list_price"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "family", "description", "image"]},
            {"id": "pricing", "title": "Pricing", "fields": ["list_price", "unit_cost", "currency", "billing_frequency", "minimum_term_months"]},
            {"id": "state", "title": "State", "fields": ["is_active", "color"]}
        ]
    },
    "query": {
        "sort": [{"id": "code", "desc": false}]
    }
}';

comment on column crm.products.image is '{"accept": "image/*", "max_size": 5242880}';

comment on column crm.products.list_price is '{"name": "List Price", "aggregate": "avg"}';

revoke all on table crm.products
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
delete on table crm.products to "x-admin";

grant
select
,
  insert,
update on table crm.products to "manager";

grant
select
  on table crm.products to "rep",
  "user";

create index idx_crm_products_family on crm.products (family);

create index idx_crm_products_is_active on crm.products (is_active);

alter table crm.products enable row level security;

create policy products_select on crm.products for
select
  to authenticated using (true);

create policy products_insert on crm.products for insert to authenticated
with
  check (true);

create policy products_update on crm.products
for update
  to authenticated using (true)
with
  check (true);

create policy products_delete on crm.products for delete to authenticated using (true);

----------------------------------------------------------------
-- Opportunities (the pipeline — the core resource)
--
-- account_id is ON DELETE RESTRICT on purpose: deleting a company
-- that still has deals against it should fail loudly rather than
-- quietly orphan the revenue history.
----------------------------------------------------------------
create sequence if not exists crm.opportunity_number_seq;

create table crm.opportunities (
  id uuid primary key default extensions.uuid_generate_v4 (),
  reference varchar(30) not null unique default (
    'OPP-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('crm.opportunity_number_seq')::text,
      5,
      '0'
    )
  ),
  name varchar(255) not null,
  account_id uuid not null references crm.accounts (id) on delete restrict,
  primary_contact_id uuid references crm.contacts (id) on delete set null,
  owner_id uuid references crm.sales_reps (id) on delete set null,
  territory_id uuid references crm.territories (id) on delete set null,
  campaign_id uuid references crm.campaigns (id) on delete set null,
  source crm.lead_source not null default 'outbound',
  stage crm.opportunity_stage not null default 'qualification',
  opportunity_type crm.opportunity_type not null default 'new_business',
  forecast_category crm.forecast_category not null default 'pipeline',
  amount numeric(14, 2) not null default 0,
  currency varchar(3) not null default 'USD',
  probability supasheet.PERCENTAGE not null default 0,
  weighted_amount numeric(14, 2) not null default 0,
  opened_on date not null default current_date,
  expected_close_on date not null default (current_date + 30),
  actual_close_on date,
  stage_changed_at timestamptz not null default current_timestamp,
  days_in_stage integer not null default 0,
  closed_reason varchar(500),
  competitor varchar(255),
  next_step varchar(500),
  next_step_due_on date,
  is_key_deal boolean not null default false,
  description supasheet.RICH_TEXT,
  attachments supasheet.file,
  tags varchar(500) [],
  last_activity_at timestamptz,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint opportunities_amount_non_negative check (amount >= 0),
  constraint opportunities_probability_range check (
    probability >= 0
    and probability <= 100
  ),
  constraint opportunities_expected_close_after_open check (expected_close_on >= opened_on),
  constraint opportunities_actual_close_after_open check (
    actual_close_on is null
    or actual_close_on >= opened_on
  )
);

comment on column crm.opportunities.stage is '{
    "progress": true,
    "values": {
        "qualification": {"variant": "secondary", "icon": "Search"},
        "discovery": {"variant": "info", "icon": "Compass"},
        "proposal": {"variant": "default", "icon": "FileText"},
        "negotiation": {"variant": "warning", "icon": "Handshake"},
        "closed_won": {"variant": "success", "icon": "Trophy"},
        "closed_lost": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on column crm.opportunities.forecast_category is '{
    "progress": true,
    "values": {
        "omitted": {"variant": "secondary", "icon": "EyeOff"},
        "pipeline": {"variant": "info", "icon": "Filter"},
        "best_case": {"variant": "default", "icon": "TrendingUp"},
        "commit": {"variant": "warning", "icon": "HandCoins"},
        "closed": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on column crm.opportunities.opportunity_type is '{
    "progress": false,
    "values": {
        "new_business": {"variant": "default", "icon": "Sparkles"},
        "expansion": {"variant": "success", "icon": "TrendingUp"},
        "upsell": {"variant": "info", "icon": "ArrowUpRight"},
        "renewal": {"variant": "secondary", "icon": "RefreshCw"}
    }
}';

comment on table crm.opportunities is '{
    "icon": "Target",
    "name": "Opportunities",
    "collapsible_group": "Pipeline",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "name", "badges": ["stage", "forecast_category", "opportunity_type"]},
        "tabs": ["opportunity_line_items", "opportunity_contacts", "quotes", "activities", "tasks"],
        "timelines": ["opportunity_events"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Pipeline Board",
            "type": "kanban",
            "group": "stage",
            "title": "name",
            "description": "next_step",
            "date": "expected_close_on",
            "badge": "opportunity_type"
        },
        {
            "id": "gantt",
            "name": "Deal Cycles",
            "type": "gantt",
            "title": "name",
            "start_date": "opened_on",
            "end_date": "expected_close_on",
            "group": "stage",
            "progress": "probability",
            "badge": "forecast_category"
        },
        {
            "id": "calendar",
            "name": "Close Dates",
            "type": "calendar",
            "title": "name",
            "badge": "stage",
            "start_date": "expected_close_on",
            "read_only": true
        },
        {
            "id": "list",
            "name": "All Deals",
            "type": "list",
            "title": "name",
            "description": "next_step",
            "field_1": "stage",
            "field_2": "amount"
        }
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "stage", "value": ["qualification", "discovery", "proposal", "negotiation"], "operator": "in"}]},
        {"id": "commit", "name": "Commit", "filters": [{"id": "forecast_category", "value": "commit", "operator": "eq"}]},
        {"id": "key", "name": "Key Deals", "filters": [{"id": "is_key_deal", "value": "true", "operator": "eq"}]},
        {"id": "stalled", "name": "Stalled 30d+", "filters": [{"id": "days_in_stage", "value": "30", "operator": "gte"}]},
        {"id": "won", "name": "Won", "filters": [{"id": "stage", "value": "closed_won", "operator": "eq"}]},
        {"id": "lost", "name": "Lost", "filters": [{"id": "stage", "value": "closed_lost", "operator": "eq"}]}
    ],
    "links": [
        {"id": "pipeline_report", "name": "Pipeline Report", "url": "/crm/report/pipeline_report", "icon": "FileText", "description": "Every deal with account, owner and forecast context"},
        {"id": "forecast_report", "name": "Forecast", "url": "/crm/report/forecast_report", "icon": "TrendingUp", "description": "Weighted and committed revenue by rep and month"}
    ],
    "fields": {
        "quick_create": ["name", "account_id", "amount", "expected_close_on", "owner_id"],
        "sections": [
            {"id": "deal", "title": "Deal", "fields": ["name", "account_id", "primary_contact_id", "opportunity_type", "source"]},
            {"id": "value", "title": "Value", "fields": {"create": ["amount", "currency"], "update": ["amount", "currency"], "read": ["amount", "currency", "probability", "weighted_amount"]}},
            {"id": "forecast", "title": "Forecast", "fields": ["stage", "forecast_category", "expected_close_on", "is_key_deal"]},
            {"id": "ownership", "title": "Ownership", "fields": ["owner_id", "territory_id", "campaign_id"]},
            {"id": "next_step", "title": "Next step", "fields": ["next_step", "next_step_due_on"]},
            {"id": "closure", "title": "Closure", "fields": ["actual_close_on", "closed_reason", "competitor"]},
            {"id": "cycle", "title": "Cycle", "fields": {"read": ["opened_on", "stage_changed_at", "days_in_stage", "last_activity_at"]}},
            {"id": "extras", "title": "Detail", "collapsible": true, "fields": ["description", "attachments", "tags"]}
        ],
        "behavior": {
            "closed_reason": {
                "visible": [{"id": "stage", "operator": "in", "value": ["closed_won", "closed_lost"]}],
                "required": [{"id": "stage", "operator": "eq", "value": "closed_lost"}]
            },
            "competitor": {"visible": [{"id": "stage", "operator": "eq", "value": "closed_lost"}]},
            "actual_close_on": {"visible": [{"id": "stage", "operator": "in", "value": ["closed_won", "closed_lost"]}]},
            "next_step_due_on": {"visible": [{"id": "next_step", "operator": "not.is", "value": "null"}]},
            "expected_close_on": {"read_only": [{"id": "stage", "operator": "in", "value": ["closed_won", "closed_lost"]}]},
            "forecast_category": {"read_only": [{"id": "stage", "operator": "in", "value": ["closed_won", "closed_lost"]}]}
        },
        "lookups": {
            "account_id": {
                "fill": [
                    {"source_column": "owner_id", "target_column": "owner_id"},
                    {"source_column": "territory_id", "target_column": "territory_id"}
                ]
            },
            "primary_contact_id": {"filter": [{"source_column": "account_id", "target_column": "account_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "expected_close_on", "desc": false}],
        "join": [
            {"table": "accounts", "on": "account_id", "columns": ["name", "tier", "health"]},
            {"table": "contacts", "on": "primary_contact_id", "alias": "primary_contact", "columns": ["name", "email"]},
            {"table": "sales_reps", "on": "owner_id", "alias": "owner", "columns": ["name", "avatar"]},
            {"table": "territories", "on": "territory_id", "columns": ["name", "code"]},
            {"table": "campaigns", "on": "campaign_id", "columns": ["name", "channel"]}
        ]
    }
}';

comment on column crm.opportunities.reference is '{"name": "Ref", "icon": "Hash"}';

comment on column crm.opportunities.amount is '{"name": "Amount", "aggregate": "sum"}';

comment on column crm.opportunities.weighted_amount is '{"name": "Weighted", "aggregate": "sum"}';

comment on column crm.opportunities.probability is '{"name": "Probability", "aggregate": "avg"}';

comment on column crm.opportunities.days_in_stage is '{"name": "Days In Stage", "aggregate": "avg"}';

comment on column crm.opportunities.attachments is '{"accept": "*", "max_files": 10, "max_size": 10485760}';

revoke all on table crm.opportunities
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
delete on table crm.opportunities to "x-admin";

grant
select
,
  insert,
update on table crm.opportunities to "manager",
"rep";

revoke all on sequence crm.opportunity_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence crm.opportunity_number_seq to "x-admin",
"manager",
"rep";

create index idx_crm_opportunities_account_id on crm.opportunities (account_id);

create index idx_crm_opportunities_primary_contact_id on crm.opportunities (primary_contact_id);

create index idx_crm_opportunities_owner_id on crm.opportunities (owner_id);

create index idx_crm_opportunities_territory_id on crm.opportunities (territory_id);

create index idx_crm_opportunities_campaign_id on crm.opportunities (campaign_id);

create index idx_crm_opportunities_stage on crm.opportunities (stage);

create index idx_crm_opportunities_forecast_category on crm.opportunities (forecast_category);

create index idx_crm_opportunities_expected_close_on on crm.opportunities (expected_close_on);

create index idx_crm_opportunities_created_at on crm.opportunities (created_at desc);

-- The two queries the whole application runs constantly: "my open
-- pipeline" and "what closes this month". Partial indexes keep the
-- closed history out of both.
create index idx_crm_opportunities_open_by_owner on crm.opportunities (owner_id, expected_close_on)
where
  stage not in ('closed_won', 'closed_lost');

create index idx_crm_opportunities_open_by_account on crm.opportunities (account_id, stage)
where
  stage not in ('closed_won', 'closed_lost');

alter table crm.opportunities enable row level security;

-- The pipeline is visible to the whole sales floor; editing is
-- limited to the owner (plus leadership), and the trigger below
-- additionally freezes a deal once it is closed.
create policy opportunities_select on crm.opportunities for
select
  to authenticated using (true);

create policy opportunities_insert on crm.opportunities for insert to authenticated
with
  check (true);

create policy opportunities_update on crm.opportunities
for update
  to authenticated using (
    owner_id is null
    or owner_id = crm.current_rep_id ()
    or crm.is_sales_leadership ()
  )
with
  check (true);

create policy opportunities_delete on crm.opportunities for delete to authenticated using (true);

-- Leads point at the deal they became; the column lands here because
-- opportunities did not exist when the table was created.
alter table crm.leads
add column converted_opportunity_id uuid references crm.opportunities (id) on delete set null;

create index idx_crm_leads_converted_opportunity_id on crm.leads (converted_opportunity_id);

----------------------------------------------------------------
-- Opportunity line items (what is actually being sold — the deal
-- amount is the sum of these once any exist)
----------------------------------------------------------------
create table crm.opportunity_line_items (
  id uuid primary key default extensions.uuid_generate_v4 (),
  opportunity_id uuid not null references crm.opportunities (id) on delete cascade,
  product_id uuid not null references crm.products (id) on delete restrict,
  quantity integer not null default 1,
  unit_price numeric(12, 2) not null default 0,
  discount_percent supasheet.PERCENTAGE not null default 0,
  line_total numeric(14, 2) not null default 0,
  billing_frequency crm.billing_frequency not null default 'annual',
  term_months integer not null default 12,
  notes varchar(500),
  sort_order integer not null default 0,
  created_at timestamptz default current_timestamp,
  constraint line_items_quantity_positive check (quantity > 0),
  constraint line_items_price_non_negative check (unit_price >= 0),
  constraint line_items_discount_range check (
    discount_percent >= 0
    and discount_percent <= 100
  ),
  constraint line_items_term_positive check (term_months > 0)
);

comment on table crm.opportunity_line_items is '{
    "icon": "ListPlus",
    "name": "Line Items",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "product", "title": "Product", "fields": ["opportunity_id", "product_id", "quantity"]},
            {"id": "pricing", "title": "Pricing", "fields": ["unit_price", "discount_percent", "billing_frequency", "term_months"]},
            {"id": "total", "title": "Total", "fields": {"read": ["line_total"]}},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes", "sort_order"]}
        ],
        "lookups": {
            "product_id": {
                "fill": [
                    {"source_column": "unit_price", "target_column": "list_price"},
                    {"source_column": "billing_frequency", "target_column": "billing_frequency"},
                    {"source_column": "term_months", "target_column": "minimum_term_months"}
                ]
            }
        }
    },
    "query": {
        "sort": [{"id": "sort_order", "desc": false}],
        "join": [
            {"table": "opportunities", "on": "opportunity_id", "columns": ["reference", "name", "stage"]},
            {"table": "products", "on": "product_id", "columns": ["code", "name", "family"]}
        ]
    }
}';

comment on column crm.opportunity_line_items.line_total is '{"name": "Line Total", "aggregate": "sum"}';

comment on column crm.opportunity_line_items.quantity is '{"aggregate": "sum"}';

comment on column crm.opportunity_line_items.discount_percent is '{"name": "Discount", "aggregate": "avg"}';

revoke all on table crm.opportunity_line_items
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
delete on table crm.opportunity_line_items to "x-admin";

grant
select
,
  insert,
update,
delete on table crm.opportunity_line_items to "manager",
"rep";

create index idx_crm_line_items_opportunity_id on crm.opportunity_line_items (opportunity_id);

create index idx_crm_line_items_product_id on crm.opportunity_line_items (product_id);

alter table crm.opportunity_line_items enable row level security;

create policy line_items_select on crm.opportunity_line_items for
select
  to authenticated using (true);

create policy line_items_insert on crm.opportunity_line_items for insert to authenticated
with
  check (true);

create policy line_items_update on crm.opportunity_line_items
for update
  to authenticated using (true)
with
  check (true);

create policy line_items_delete on crm.opportunity_line_items for delete to authenticated using (true);

----------------------------------------------------------------
-- Opportunity contacts (the buying committee — many-to-many
-- contacts <-> opportunities, with the role each person plays)
----------------------------------------------------------------
create table crm.opportunity_contacts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  opportunity_id uuid not null references crm.opportunities (id) on delete cascade,
  contact_id uuid not null references crm.contacts (id) on delete cascade,
  contact_role crm.contact_role not null default 'influencer',
  is_decision_maker boolean not null default false,
  influence supasheet.RATING,
  notes varchar(500),
  created_at timestamptz default current_timestamp,
  unique (opportunity_id, contact_id)
);

comment on table crm.opportunity_contacts is '{
    "icon": "UsersRound",
    "name": "Buying Committee",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "link", "title": "Committee member", "fields": ["opportunity_id", "contact_id", "contact_role", "is_decision_maker", "influence", "notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "opportunities", "on": "opportunity_id", "columns": ["reference", "name", "stage"]},
            {"table": "contacts", "on": "contact_id", "columns": ["name", "job_title", "email"]}
        ]
    }
}';

comment on column crm.opportunity_contacts.influence is '{"name": "Influence", "aggregate": "avg"}';

revoke all on table crm.opportunity_contacts
from
  public,
  anon,
  authenticated,
  service_role;

-- Junction table: link and unlink, no update.
grant
select
,
  insert,
  delete on table crm.opportunity_contacts to "x-admin",
  "manager",
  "rep";

create index idx_crm_opportunity_contacts_opportunity_id on crm.opportunity_contacts (opportunity_id);

create index idx_crm_opportunity_contacts_contact_id on crm.opportunity_contacts (contact_id);

alter table crm.opportunity_contacts enable row level security;

create policy opportunity_contacts_select on crm.opportunity_contacts for
select
  to authenticated using (true);

create policy opportunity_contacts_insert on crm.opportunity_contacts for insert to authenticated
with
  check (true);

create policy opportunity_contacts_delete on crm.opportunity_contacts for delete to authenticated using (true);

----------------------------------------------------------------
-- Opportunity events (system-generated deal history — display:
-- none, never browsable on its own; surfaced only as the
-- "opportunity_events" timeline tab on the deal's detail page)
----------------------------------------------------------------
create table crm.opportunity_events (
  id uuid primary key default extensions.uuid_generate_v4 (),
  opportunity_id uuid not null references crm.opportunities (id) on delete cascade,
  event_type crm.opportunity_event_type not null,
  title varchar(255) not null,
  metadata jsonb,
  actor_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  occurred_at timestamptz not null default current_timestamp
);

comment on column crm.opportunity_events.event_type is '{
    "progress": false,
    "values": {
        "created": {"variant": "info", "icon": "Sparkles"},
        "stage_changed": {"variant": "default", "icon": "ArrowRightLeft"},
        "amount_changed": {"variant": "warning", "icon": "DollarSign"},
        "owner_changed": {"variant": "secondary", "icon": "UserCog"},
        "closed_won": {"variant": "success", "icon": "Trophy"},
        "closed_lost": {"variant": "destructive", "icon": "CircleX"},
        "reopened": {"variant": "warning", "icon": "RotateCcw"},
        "activity_logged": {"variant": "info", "icon": "PhoneCall"},
        "quote_sent": {"variant": "default", "icon": "FileText"},
        "record_updated": {"variant": "secondary", "icon": "RefreshCw"}
    }
}';

comment on table crm.opportunity_events is '{
    "icon": "History",
    "name": "Deal History",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "event", "title": "Event", "fields": ["opportunity_id", "event_type", "title", "metadata", "actor_id", "occurred_at"]}
        ]
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [{"table": "users", "on": "actor_id", "alias": "actor", "columns": ["name", "email"]}]
    }
}';

revoke all on table crm.opportunity_events
from
  public,
  anon,
  authenticated,
  service_role;

-- Select only — the deal history is evidence, not a scratchpad.
grant
select
  on table crm.opportunity_events to "x-admin",
  "manager",
  "rep";

create index idx_crm_opportunity_events_opportunity_id on crm.opportunity_events (opportunity_id);

create index idx_crm_opportunity_events_occurred_at on crm.opportunity_events (occurred_at desc);

alter table crm.opportunity_events enable row level security;

create policy opportunity_events_select on crm.opportunity_events for
select
  to authenticated using (true);

----------------------------------------------------------------
-- Quotes (a priced, dated offer generated from a deal)
----------------------------------------------------------------
create sequence if not exists crm.quote_number_seq;

create table crm.quotes (
  id uuid primary key default extensions.uuid_generate_v4 (),
  quote_number varchar(30) not null unique default (
    'Q-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('crm.quote_number_seq')::text, 4, '0')
  ),
  opportunity_id uuid not null references crm.opportunities (id) on delete cascade,
  account_id uuid references crm.accounts (id) on delete set null,
  owner_id uuid references crm.sales_reps (id) on delete set null,
  status crm.quote_status not null default 'draft',
  subtotal numeric(14, 2) not null default 0,
  discount_amount numeric(14, 2) not null default 0,
  tax_amount numeric(14, 2) not null default 0,
  total numeric(14, 2) not null default 0,
  currency varchar(3) not null default 'USD',
  valid_until date not null default (current_date + 30),
  terms text,
  document supasheet.file,
  sent_at timestamptz,
  accepted_at timestamptz,
  declined_reason varchar(500),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint quotes_amounts_non_negative check (
    subtotal >= 0
    and discount_amount >= 0
    and tax_amount >= 0
    and total >= 0
  )
);

comment on column crm.quotes.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "sent": {"variant": "info", "icon": "Send"},
        "accepted": {"variant": "success", "icon": "CircleCheck"},
        "declined": {"variant": "destructive", "icon": "CircleX"},
        "expired": {"variant": "warning", "icon": "TimerOff"}
    }
}';

comment on table crm.quotes is '{
    "icon": "ReceiptText",
    "collapsible_group": "Pipeline",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "quote_number", "badges": ["status", "total"]},
        "tabs": []
    },
    "views": [
        {
            "id": "list",
            "name": "All Quotes",
            "type": "list",
            "title": "quote_number",
            "description": "terms",
            "field_1": "status",
            "field_2": "total"
        },
        {
            "id": "kanban",
            "name": "By Status",
            "type": "kanban",
            "group": "status",
            "title": "quote_number",
            "description": "terms",
            "date": "valid_until",
            "badge": "status"
        }
    ],
    "filter_presets": [
        {"id": "open", "name": "Awaiting Decision", "filters": [{"id": "status", "value": "sent", "operator": "eq"}]},
        {"id": "accepted", "name": "Accepted", "filters": [{"id": "status", "value": "accepted", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["opportunity_id", "valid_until", "total"],
        "sections": [
            {"id": "deal", "title": "Deal", "fields": ["opportunity_id", "account_id", "owner_id"]},
            {"id": "amounts", "title": "Amounts", "fields": ["subtotal", "discount_amount", "tax_amount", "total", "currency"]},
            {"id": "validity", "title": "Validity", "fields": ["status", "valid_until"]},
            {"id": "decision", "title": "Decision", "fields": ["declined_reason"]},
            {"id": "audit", "title": "Trail", "fields": {"read": ["sent_at", "accepted_at"]}},
            {"id": "extras", "title": "Terms & document", "collapsible": true, "fields": ["terms", "document"]}
        ],
        "behavior": {
            "declined_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "declined"}],
                "required": [{"id": "status", "operator": "eq", "value": "declined"}]
            },
            "subtotal": {"read_only": [{"id": "status", "operator": "in", "value": ["accepted", "declined", "expired"]}]},
            "total": {"read_only": [{"id": "status", "operator": "in", "value": ["accepted", "declined", "expired"]}]}
        },
        "lookups": {
            "opportunity_id": {
                "fill": [
                    {"source_column": "account_id", "target_column": "account_id"},
                    {"source_column": "owner_id", "target_column": "owner_id"},
                    {"source_column": "currency", "target_column": "currency"}
                ]
            }
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "opportunities", "on": "opportunity_id", "columns": ["reference", "name", "stage"]},
            {"table": "accounts", "on": "account_id", "columns": ["name", "tier"]},
            {"table": "sales_reps", "on": "owner_id", "alias": "owner", "columns": ["name", "avatar"]}
        ]
    }
}';

comment on column crm.quotes.document is '{"accept": ".pdf", "max_files": 3, "max_size": 10485760}';

comment on column crm.quotes.total is '{"aggregate": "sum"}';

comment on column crm.quotes.subtotal is '{"aggregate": "sum"}';

comment on column crm.quotes.discount_amount is '{"name": "Discount", "aggregate": "sum"}';

revoke all on table crm.quotes
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
delete on table crm.quotes to "x-admin";

grant
select
,
  insert,
update on table crm.quotes to "manager",
"rep";

revoke all on sequence crm.quote_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence crm.quote_number_seq to "x-admin",
"manager",
"rep";

create index idx_crm_quotes_opportunity_id on crm.quotes (opportunity_id);

create index idx_crm_quotes_account_id on crm.quotes (account_id);

create index idx_crm_quotes_owner_id on crm.quotes (owner_id);

create index idx_crm_quotes_status on crm.quotes (status);

create index idx_crm_quotes_valid_until on crm.quotes (valid_until);

alter table crm.quotes enable row level security;

create policy quotes_select on crm.quotes for
select
  to authenticated using (true);

create policy quotes_insert on crm.quotes for insert to authenticated
with
  check (true);

create policy quotes_update on crm.quotes
for update
  to authenticated using (
    owner_id is null
    or owner_id = crm.current_rep_id ()
    or crm.is_sales_leadership ()
  )
with
  check (true);

create policy quotes_delete on crm.quotes for delete to authenticated using (true);

----------------------------------------------------------------
-- Activities (what actually happened — calls, emails, meetings)
--
-- An activity has to hang off something; the check constraint is
-- what stops orphaned "notes to self" accumulating in the log.
----------------------------------------------------------------
create table crm.activities (
  id uuid primary key default extensions.uuid_generate_v4 (),
  activity_type crm.activity_type not null default 'call',
  subject varchar(255) not null,
  notes supasheet.RICH_TEXT,
  account_id uuid references crm.accounts (id) on delete cascade,
  contact_id uuid references crm.contacts (id) on delete set null,
  opportunity_id uuid references crm.opportunities (id) on delete cascade,
  lead_id uuid references crm.leads (id) on delete cascade,
  owner_id uuid references crm.sales_reps (id) on delete set null,
  direction crm.activity_direction not null default 'outbound',
  outcome crm.activity_outcome,
  occurred_at timestamptz not null default current_timestamp,
  duration supasheet.DURATION not null default 0,
  location varchar(255),
  follow_up_on date,
  attachments supasheet.file,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  constraint activities_must_relate_to_something check (
    account_id is not null
    or contact_id is not null
    or opportunity_id is not null
    or lead_id is not null
  )
);

comment on column crm.activities.activity_type is '{
    "progress": false,
    "values": {
        "call": {"variant": "info", "icon": "Phone"},
        "email": {"variant": "secondary", "icon": "Mail"},
        "meeting": {"variant": "default", "icon": "Users"},
        "demo": {"variant": "success", "icon": "MonitorPlay"},
        "site_visit": {"variant": "warning", "icon": "MapPin"},
        "note": {"variant": "secondary", "icon": "StickyNote"}
    }
}';

comment on column crm.activities.outcome is '{
    "progress": false,
    "values": {
        "connected": {"variant": "success", "icon": "CircleCheck"},
        "left_message": {"variant": "info", "icon": "Voicemail"},
        "no_answer": {"variant": "warning", "icon": "PhoneMissed"},
        "rescheduled": {"variant": "secondary", "icon": "CalendarClock"},
        "completed": {"variant": "success", "icon": "Check"}
    }
}';

comment on table crm.activities is '{
    "icon": "PhoneCall",
    "collapsible_group": "Engagement",
    "display": "block",
    "primary_view": "calendar",
    "detail": {"header": {"title": "subject", "badges": ["activity_type", "outcome"]}},
    "views": [
        {
            "id": "calendar",
            "name": "Interaction Calendar",
            "type": "calendar",
            "title": "subject",
            "badge": "activity_type",
            "start_date": "occurred_at"
        },
        {
            "id": "kanban",
            "name": "By Channel",
            "type": "kanban",
            "group": "activity_type",
            "title": "subject",
            "description": "location",
            "date": "occurred_at",
            "badge": "direction"
        },
        {
            "id": "list",
            "name": "Interaction Log",
            "type": "list",
            "title": "subject",
            "description": "location",
            "field_1": "activity_type",
            "field_2": "occurred_at"
        }
    ],
    "filter_presets": [
        {"id": "meetings", "name": "Meetings & Demos", "filters": [{"id": "activity_type", "value": ["meeting", "demo"], "operator": "in"}]},
        {"id": "inbound", "name": "Inbound", "filters": [{"id": "direction", "value": "inbound", "operator": "eq"}]},
        {"id": "needs_follow_up", "name": "Needs Follow-up", "filters": [{"id": "follow_up_on", "value": "null", "operator": "not.is"}]}
    ],
    "fields": {
        "quick_create": ["subject", "activity_type", "account_id", "occurred_at"],
        "sections": [
            {"id": "what", "title": "What happened", "fields": ["subject", "activity_type", "direction", "outcome", "occurred_at", "duration"]},
            {"id": "who", "title": "Who it was with", "fields": ["account_id", "contact_id", "opportunity_id", "lead_id", "owner_id"]},
            {"id": "follow_up", "title": "Follow-up", "fields": ["follow_up_on", "location"]},
            {"id": "extras", "title": "Notes & attachments", "collapsible": true, "fields": ["notes", "attachments"]}
        ],
        "behavior": {
            "location": {"visible": [{"id": "activity_type", "operator": "in", "value": ["meeting", "site_visit", "demo"]}]},
            "duration": {"visible": [{"id": "activity_type", "operator": "not.in", "value": ["note", "email"]}]},
            "outcome": {"visible": [{"id": "activity_type", "operator": "not.eq", "value": "note"}]}
        },
        "lookups": {
            "contact_id": {"filter": [{"source_column": "account_id", "target_column": "account_id"}]},
            "opportunity_id": {"filter": [{"source_column": "account_id", "target_column": "account_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [
            {"table": "accounts", "on": "account_id", "columns": ["name", "tier"]},
            {"table": "contacts", "on": "contact_id", "columns": ["name", "job_title"]},
            {"table": "opportunities", "on": "opportunity_id", "columns": ["reference", "name", "stage"]},
            {"table": "leads", "on": "lead_id", "columns": ["name", "company"]},
            {"table": "sales_reps", "on": "owner_id", "alias": "owner", "columns": ["name", "avatar"]}
        ]
    }
}';

comment on column crm.activities.duration is '{"name": "Duration", "aggregate": "sum"}';

comment on column crm.activities.attachments is '{"accept": "*", "max_files": 5, "max_size": 10485760}';

revoke all on table crm.activities
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
delete on table crm.activities to "x-admin";

grant
select
,
  insert,
update on table crm.activities to "manager",
"rep";

grant
select
  on table crm.activities to "user";

create index idx_crm_activities_account_id on crm.activities (account_id);

create index idx_crm_activities_contact_id on crm.activities (contact_id);

create index idx_crm_activities_opportunity_id on crm.activities (opportunity_id);

create index idx_crm_activities_lead_id on crm.activities (lead_id);

create index idx_crm_activities_owner_id on crm.activities (owner_id);

create index idx_crm_activities_occurred_at on crm.activities (occurred_at desc);

create index idx_crm_activities_activity_type on crm.activities (activity_type);

alter table crm.activities enable row level security;

create policy activities_select on crm.activities for
select
  to authenticated using (true);

create policy activities_insert on crm.activities for insert to authenticated
with
  check (true);

create policy activities_update on crm.activities
for update
  to authenticated using (
    owner_id is null
    or owner_id = crm.current_rep_id ()
    or crm.is_sales_leadership ()
  )
with
  check (true);

create policy activities_delete on crm.activities for delete to authenticated using (true);

----------------------------------------------------------------
-- Tasks (what still has to happen)
----------------------------------------------------------------
create table crm.tasks (
  id uuid primary key default extensions.uuid_generate_v4 (),
  subject varchar(255) not null,
  description text,
  status crm.task_status not null default 'not_started',
  priority crm.priority_level not null default 'normal',
  owner_id uuid references crm.sales_reps (id) on delete set null,
  account_id uuid references crm.accounts (id) on delete cascade,
  contact_id uuid references crm.contacts (id) on delete set null,
  opportunity_id uuid references crm.opportunities (id) on delete cascade,
  lead_id uuid references crm.leads (id) on delete cascade,
  due_on date,
  reminder_at timestamptz,
  completed_at timestamptz,
  is_overdue boolean not null default false,
  outcome_notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column crm.tasks.status is '{
    "progress": true,
    "values": {
        "not_started": {"variant": "secondary", "icon": "Circle"},
        "in_progress": {"variant": "info", "icon": "Loader"},
        "waiting": {"variant": "warning", "icon": "Hourglass"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "cancelled": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on column crm.tasks.priority is '{
    "progress": false,
    "icon_only": true,
    "values": {
        "low": {"variant": "secondary", "icon": "ArrowDown"},
        "normal": {"variant": "info", "icon": "Minus"},
        "high": {"variant": "warning", "icon": "ArrowUp"},
        "urgent": {"variant": "destructive", "icon": "Flame"}
    }
}';

comment on table crm.tasks is '{
    "icon": "ListTodo",
    "collapsible_group": "Engagement",
    "display": "block",
    "primary_view": "kanban",
    "detail": {"header": {"title": "subject", "badges": ["status", "priority"]}},
    "views": [
        {
            "id": "kanban",
            "name": "Task Board",
            "type": "kanban",
            "group": "status",
            "title": "subject",
            "description": "description",
            "date": "due_on",
            "badge": "priority"
        },
        {
            "id": "calendar",
            "name": "Due Dates",
            "type": "calendar",
            "title": "subject",
            "badge": "priority",
            "start_date": "due_on"
        },
        {
            "id": "list",
            "name": "All Tasks",
            "type": "list",
            "title": "subject",
            "description": "description",
            "field_1": "status",
            "field_2": "due_on"
        }
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["not_started", "in_progress", "waiting"], "operator": "in"}]},
        {"id": "overdue", "name": "Overdue", "filters": [{"id": "is_overdue", "value": "true", "operator": "eq"}]},
        {"id": "urgent", "name": "High & Urgent", "filters": [{"id": "priority", "value": ["high", "urgent"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["subject", "due_on", "priority", "owner_id"],
        "sections": [
            {"id": "task", "title": "Task", "fields": ["subject", "description", "status", "priority"]},
            {"id": "related", "title": "Related to", "fields": ["account_id", "contact_id", "opportunity_id", "lead_id"]},
            {"id": "schedule", "title": "Schedule", "fields": ["owner_id", "due_on", "reminder_at"]},
            {"id": "closure", "title": "Closure", "fields": ["outcome_notes"]},
            {"id": "state", "title": "State", "fields": {"read": ["completed_at", "is_overdue"]}}
        ],
        "behavior": {
            "outcome_notes": {"visible": [{"id": "status", "operator": "in", "value": ["completed", "cancelled"]}]},
            "reminder_at": {"visible": [{"id": "status", "operator": "not.in", "value": ["completed", "cancelled"]}]}
        },
        "lookups": {
            "contact_id": {"filter": [{"source_column": "account_id", "target_column": "account_id"}]},
            "opportunity_id": {"filter": [{"source_column": "account_id", "target_column": "account_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "due_on", "desc": false}],
        "join": [
            {"table": "accounts", "on": "account_id", "columns": ["name", "tier"]},
            {"table": "contacts", "on": "contact_id", "columns": ["name", "job_title"]},
            {"table": "opportunities", "on": "opportunity_id", "columns": ["reference", "name", "stage"]},
            {"table": "sales_reps", "on": "owner_id", "alias": "owner", "columns": ["name", "avatar"]}
        ]
    }
}';

revoke all on table crm.tasks
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
delete on table crm.tasks to "x-admin";

grant
select
,
  insert,
update on table crm.tasks to "manager",
"rep";

create index idx_crm_tasks_owner_id on crm.tasks (owner_id);

create index idx_crm_tasks_account_id on crm.tasks (account_id);

create index idx_crm_tasks_opportunity_id on crm.tasks (opportunity_id);

create index idx_crm_tasks_lead_id on crm.tasks (lead_id);

create index idx_crm_tasks_status on crm.tasks (status);

create index idx_crm_tasks_due_on on crm.tasks (due_on);

-- "My open tasks, soonest first" is the query behind the task board,
-- the overdue widget and the daily digest.
create index idx_crm_tasks_open_by_owner on crm.tasks (owner_id, due_on)
where
  status in ('not_started', 'in_progress', 'waiting');

alter table crm.tasks enable row level security;

-- A task list is personal: you see your own and anything unassigned;
-- leadership sees the floor.
create policy tasks_select on crm.tasks for
select
  to authenticated using (
    owner_id is null
    or owner_id = crm.current_rep_id ()
    or crm.is_sales_leadership ()
  );

create policy tasks_insert on crm.tasks for insert to authenticated
with
  check (true);

create policy tasks_update on crm.tasks
for update
  to authenticated using (
    owner_id is null
    or owner_id = crm.current_rep_id ()
    or crm.is_sales_leadership ()
  )
with
  check (true);

create policy tasks_delete on crm.tasks for delete to authenticated using (true);

----------------------------------------------------------------
-- CRM settings (singleton — one row only, no delete grant)
----------------------------------------------------------------
create table crm.crm_settings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  company_name varchar(255) not null default 'Supasheet',
  logo supasheet.file,
  brand_color supasheet.COLOR default '#2563eb',
  default_currency varchar(3) not null default 'USD',
  fiscal_year_start_month integer not null default 1,
  default_territory_id uuid references crm.territories (id) on delete set null,
  lead_auto_assign boolean not null default true,
  lead_response_sla_hours integer not null default 24,
  stale_deal_days integer not null default 30,
  quote_validity_days integer not null default 30,
  default_close_horizon_days integer not null default 30,
  forecast_lock_day integer not null default 25,
  notification_email supasheet.EMAIL,
  timezone varchar(100) not null default 'UTC',
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint crm_settings_fiscal_month_range check (fiscal_year_start_month between 1 and 12),
  constraint crm_settings_windows_positive check (
    lead_response_sla_hours > 0
    and stale_deal_days > 0
    and quote_validity_days > 0
  )
);

comment on table crm.crm_settings is '{
    "icon": "Settings",
    "name": "CRM Settings",
    "collapsible_group": "Configuration",
    "display": "block",
    "singleton": true,
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["company_name", "logo", "brand_color", "notification_email"]},
            {"id": "finance", "title": "Finance", "fields": ["default_currency", "fiscal_year_start_month", "forecast_lock_day"]},
            {"id": "pipeline", "title": "Pipeline policy", "fields": ["default_close_horizon_days", "stale_deal_days", "quote_validity_days"]},
            {"id": "leads", "title": "Lead policy", "fields": ["lead_auto_assign", "lead_response_sla_hours", "default_territory_id"]},
            {"id": "locale", "title": "Locale", "collapsible": true, "fields": ["timezone"]}
        ],
        "behavior": {
            "lead_response_sla_hours": {"visible": [{"id": "lead_auto_assign", "operator": "eq", "value": "true"}]}
        }
    },
    "query": {
        "join": [{"table": "territories", "on": "default_territory_id", "columns": ["name", "code"]}]
    }
}';

comment on column crm.crm_settings.logo is '{"accept": "image/*", "max_size": 2097152}';

revoke all on table crm.crm_settings
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
update on table crm.crm_settings to "x-admin";

grant
select
  on table crm.crm_settings to "manager",
  "rep";

alter table crm.crm_settings enable row level security;

create policy crm_settings_select on crm.crm_settings for
select
  to authenticated using (true);

create policy crm_settings_insert on crm.crm_settings for insert to authenticated
with
  check (true);

create policy crm_settings_update on crm.crm_settings
for update
  to authenticated using (true)
with
  check (true);

----------------------------------------------------------------
-- Business triggers
----------------------------------------------------------------
-- Contacts carry a single display name so joins, lookups and every
-- "who was that?" column have one field to point at.
create or replace function crm.trg_contacts_apply_defaults () returns trigger as $$
begin
    new.name := btrim(new.first_name || ' ' || new.last_name);

    if new.do_not_contact then
        new.email_opt_out := true;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger contacts_apply_defaults
before insert or update on crm.contacts for each row
execute function crm.trg_contacts_apply_defaults ();

-- Leads get the same display name, plus routing: an unowned lead is
-- handed to the least-loaded rep who is taking work in that
-- territory, exactly once, at creation.
create or replace function crm.trg_leads_apply_defaults () returns trigger as $$
declare
    v_auto_assign boolean;
begin
    new.name := btrim(new.first_name || ' ' || new.last_name);

    if tg_op = 'INSERT' and new.owner_id is null then
        select lead_auto_assign into v_auto_assign
        from crm.crm_settings
        order by created_at asc
        limit 1;

        if coalesce(v_auto_assign, true) then
            select r.id into new.owner_id
            from crm.sales_reps r
            left join crm.leads l
              on l.owner_id = r.id
             and l.status in ('new', 'working', 'nurturing')
            where r.status = 'active'
              and r.is_accepting_leads
              and (new.territory_id is null or r.territory_id = new.territory_id)
            group by r.id, r.name
            order by count(l.id) asc, r.name asc
            limit 1;
        end if;
    end if;

    if new.status <> 'unqualified' then
        new.disqualified_reason := null;
    end if;

    if new.status = 'converted' then
        new.converted_at := coalesce(new.converted_at, current_timestamp);
    else
        new.converted_at := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger leads_apply_defaults
before insert or update on crm.leads for each row
execute function crm.trg_leads_apply_defaults ();

-- The deal maths, in one place: the stage decides the probability
-- and the forecast category, the probability decides the weighted
-- amount, and a stage change resets the clock.
--
-- The pipeline_stages table is the source of truth when it is
-- populated; the CASE fallbacks keep the module correct on a fresh
-- database that has not been seeded yet.
--
-- SECURITY INVOKER, unlike most triggers in this file, and
-- deliberately so: the closed-deal guard below asks whether the
-- CALLER is sales leadership. Inside a SECURITY DEFINER function
-- current_user is the function owner, so pg_has_role() would answer
-- for the owner (a superuser) and the guard would never fire. The
-- function only reads crm.pipeline_stages, which every role can
-- select from, so it needs no elevated privileges anyway.
create or replace function crm.trg_opportunities_apply_defaults () returns trigger as $$
declare
    v_probability real;
    v_forecast crm.forecast_category;
begin
    -- A closed deal is a record, not a working document. Anything
    -- reached from another trigger (rollups, activity stamps) runs at
    -- depth > 1 and is left alone.
    if tg_op = 'UPDATE'
       and pg_trigger_depth() = 1
       and old.stage in ('closed_won', 'closed_lost')
       and new.stage = old.stage
       and not crm.is_sales_leadership() then
        raise exception 'Opportunity % is closed and can no longer be edited. Ask sales leadership to reopen it first.', old.reference
            using errcode = 'check_violation';
    end if;

    if tg_op = 'INSERT' or new.stage is distinct from old.stage then
        select ps.default_probability, ps.forecast_category
        into v_probability, v_forecast
        from crm.pipeline_stages ps
        where ps.stage = new.stage;

        new.probability := coalesce(
            v_probability,
            case new.stage
                when 'qualification' then 10
                when 'discovery' then 25
                when 'proposal' then 50
                when 'negotiation' then 75
                when 'closed_won' then 100
                else 0
            end
        );

        new.forecast_category := coalesce(
            v_forecast,
            case new.stage
                when 'closed_won' then 'closed'::crm.forecast_category
                when 'closed_lost' then 'omitted'::crm.forecast_category
                when 'negotiation' then 'commit'::crm.forecast_category
                when 'proposal' then 'best_case'::crm.forecast_category
                else 'pipeline'::crm.forecast_category
            end
        );

        new.stage_changed_at := current_timestamp;
    elsif tg_op = 'INSERT' then
        new.stage_changed_at := coalesce(new.stage_changed_at, current_timestamp);
    end if;

    if tg_op = 'INSERT' then
        new.stage_changed_at := coalesce(new.stage_changed_at, current_timestamp);
    end if;

    -- Closure bookkeeping
    if new.stage in ('closed_won', 'closed_lost') then
        new.actual_close_on := coalesce(new.actual_close_on, current_date);
        new.probability := case when new.stage = 'closed_won' then 100 else 0 end;

        if new.stage = 'closed_lost' and btrim(coalesce(new.closed_reason, '')) = '' then
            raise exception 'Opportunity % cannot be marked lost without a reason.', new.reference
                using errcode = 'check_violation';
        end if;
    elsif tg_op = 'UPDATE' and old.stage in ('closed_won', 'closed_lost') then
        -- Reopened: clear the closure record so the deal reads clean.
        new.actual_close_on := null;
        new.closed_reason := null;
        new.competitor := null;
    end if;

    new.weighted_amount := round((new.amount * new.probability / 100)::numeric, 2);
    new.days_in_stage := greatest(0, current_date - new.stage_changed_at::date);
    new.updated_at := current_timestamp;

    return new;
end;
$$ language plpgsql security invoker
set
  search_path = '';

create trigger opportunities_apply_defaults
before insert or update on crm.opportunities for each row
execute function crm.trg_opportunities_apply_defaults ();

-- Deal history: one entry per thing a sales manager would ask about.
create or replace function crm.trg_opportunities_log_event () returns trigger as $$
begin
    if tg_op = 'INSERT' then
        insert into crm.opportunity_events (opportunity_id, event_type, title, metadata, actor_id)
        values (
            new.id,
            'created',
            'Opportunity ' || new.reference || ' created',
            jsonb_build_object('stage', new.stage, 'amount', new.amount, 'type', new.opportunity_type),
            new.user_id
        );
        return new;
    end if;

    if new.stage = 'closed_won' and old.stage <> 'closed_won' then
        insert into crm.opportunity_events (opportunity_id, event_type, title, metadata)
        values (
            new.id,
            'closed_won',
            'Won: ' || new.name,
            jsonb_build_object('amount', new.amount, 'closed_on', new.actual_close_on)
        );
    elsif new.stage = 'closed_lost' and old.stage <> 'closed_lost' then
        insert into crm.opportunity_events (opportunity_id, event_type, title, metadata)
        values (
            new.id,
            'closed_lost',
            'Lost: ' || new.name,
            jsonb_build_object('reason', new.closed_reason, 'competitor', new.competitor)
        );
    elsif old.stage in ('closed_won', 'closed_lost') and new.stage not in ('closed_won', 'closed_lost') then
        insert into crm.opportunity_events (opportunity_id, event_type, title, metadata)
        values (
            new.id,
            'reopened',
            'Reopened at ' || new.stage,
            jsonb_build_object('from', old.stage, 'to', new.stage)
        );
    elsif new.stage is distinct from old.stage then
        insert into crm.opportunity_events (opportunity_id, event_type, title, metadata)
        values (
            new.id,
            'stage_changed',
            'Stage moved to ' || new.stage,
            jsonb_build_object('from', old.stage, 'to', new.stage, 'days_in_previous_stage', old.days_in_stage)
        );
    elsif new.owner_id is distinct from old.owner_id then
        insert into crm.opportunity_events (opportunity_id, event_type, title, metadata)
        values (
            new.id,
            'owner_changed',
            'Owner changed',
            jsonb_build_object('from', old.owner_id, 'to', new.owner_id)
        );
    elsif new.amount is distinct from old.amount then
        insert into crm.opportunity_events (opportunity_id, event_type, title, metadata)
        values (
            new.id,
            'amount_changed',
            'Amount changed to ' || round(new.amount, 0),
            jsonb_build_object('from', old.amount, 'to', new.amount)
        );
    else
        insert into crm.opportunity_events (opportunity_id, event_type, title)
        values (new.id, 'record_updated', 'Opportunity updated');
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger opportunities_log_event
after insert or update of stage,
amount,
owner_id,
expected_close_on,
is_key_deal on crm.opportunities for each row
execute function crm.trg_opportunities_log_event ();

-- Account and campaign rollups follow every deal movement.
create or replace function crm.trg_opportunities_rollup () returns trigger as $$
declare
    v_accounts uuid[] := '{}';
    v_campaigns uuid[] := '{}';
    v_id uuid;
begin
    if tg_op <> 'INSERT' then
        v_accounts := v_accounts || old.account_id;
        v_campaigns := v_campaigns || old.campaign_id;
    end if;

    if tg_op <> 'DELETE' then
        v_accounts := v_accounts || new.account_id;
        v_campaigns := v_campaigns || new.campaign_id;
    end if;

    v_accounts := array_remove(v_accounts, null);
    v_campaigns := array_remove(v_campaigns, null);

    foreach v_id in array v_accounts loop
        update crm.accounts a
        set open_opportunity_count = sub.open_count,
            open_pipeline_amount = sub.open_amount,
            won_amount = sub.won_amount
        from (
            select
                count(*) filter (where o.stage not in ('closed_won', 'closed_lost')) as open_count,
                coalesce(sum(o.amount) filter (where o.stage not in ('closed_won', 'closed_lost')), 0) as open_amount,
                coalesce(sum(o.amount) filter (where o.stage = 'closed_won'), 0) as won_amount
            from crm.opportunities o
            where o.account_id = v_id
        ) as sub
        where a.id = v_id
          -- Same reasoning as the line-item rollup: a stage walk fires
          -- this repeatedly, and an UPDATE that changes nothing still
          -- costs a row version and an audit entry.
          and (a.open_opportunity_count, a.open_pipeline_amount, a.won_amount)
              is distinct from (sub.open_count, sub.open_amount, sub.won_amount);
    end loop;

    foreach v_id in array v_campaigns loop
        update crm.campaigns c
        set opportunities_created = sub.deals,
            influenced_amount = sub.influenced
        from (
            select
                count(*) as deals,
                coalesce(sum(o.amount) filter (where o.stage = 'closed_won'), 0) as influenced
            from crm.opportunities o
            where o.campaign_id = v_id
        ) as sub
        where c.id = v_id
          and (c.opportunities_created, c.influenced_amount)
              is distinct from (sub.deals, sub.influenced);
    end loop;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger opportunities_rollup
after insert or update of stage,
amount,
account_id,
campaign_id or delete on crm.opportunities for each row
execute function crm.trg_opportunities_rollup ();

-- Line items price themselves, and refuse to change on a closed
-- deal. SECURITY INVOKER for the same reason as the trigger above:
-- the guard asks about the caller, not the owner.
create or replace function crm.trg_line_items_apply_defaults () returns trigger as $$
declare
    v_stage crm.opportunity_stage;
    v_reference varchar(30);
begin
    select o.stage, o.reference into v_stage, v_reference
    from crm.opportunities o
    where o.id = new.opportunity_id;

    if v_stage in ('closed_won', 'closed_lost')
       and pg_trigger_depth() = 1
       and not crm.is_sales_leadership() then
        raise exception 'Opportunity % is closed; its line items are frozen.', v_reference
            using errcode = 'check_violation';
    end if;

    new.line_total := round(
        (new.quantity * new.unit_price * (1 - new.discount_percent / 100))::numeric,
        2
    );

    return new;
end;
$$ language plpgsql security invoker
set
  search_path = '';

create trigger line_items_apply_defaults
before insert or update on crm.opportunity_line_items for each row
execute function crm.trg_line_items_apply_defaults ();

-- Once a deal has line items, the line items ARE the amount.
-- Removing the last one leaves the deal at zero rather than silently
-- keeping a stale figure.
--
-- The `is distinct from` guard matters more than it looks: this is an
-- AFTER ROW trigger, so inserting five lines in one statement fires
-- it five times, and by then all five rows are visible — every call
-- computes the same total. Without the guard the deal would be
-- updated five times, filing four "record updated" history entries
-- and four audit rows that describe nothing.
create or replace function crm.trg_line_items_rollup () returns trigger as $$
declare
    v_opportunity_id uuid := coalesce(new.opportunity_id, old.opportunity_id);
    v_total numeric(14, 2);
begin
    select coalesce(sum(li.line_total), 0)
    into v_total
    from crm.opportunity_line_items li
    where li.opportunity_id = v_opportunity_id;

    update crm.opportunities
    set amount = v_total
    where id = v_opportunity_id
      and amount is distinct from v_total;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger line_items_rollup
after insert or update or delete on crm.opportunity_line_items for each row
execute function crm.trg_line_items_rollup ();

-- Every logged interaction touches the freshness stamps the health
-- widgets and the "no contact in 30 days" reports read from.
create or replace function crm.trg_activities_after () returns trigger as $$
begin
    if new.account_id is not null then
        update crm.accounts
        set last_activity_at = greatest(coalesce(last_activity_at, new.occurred_at), new.occurred_at)
        where id = new.account_id;
    end if;

    if new.opportunity_id is not null then
        update crm.opportunities
        set last_activity_at = greatest(coalesce(last_activity_at, new.occurred_at), new.occurred_at)
        where id = new.opportunity_id;

        insert into crm.opportunity_events (opportunity_id, event_type, title, metadata, actor_id, occurred_at)
        values (
            new.opportunity_id,
            'activity_logged',
            initcap(new.activity_type::text) || ': ' || new.subject,
            jsonb_build_object('activity_id', new.id, 'outcome', new.outcome, 'direction', new.direction),
            new.user_id,
            new.occurred_at
        );
    end if;

    if new.contact_id is not null then
        update crm.contacts
        set last_contacted_at = greatest(coalesce(last_contacted_at, new.occurred_at), new.occurred_at)
        where id = new.contact_id;
    end if;

    if new.lead_id is not null then
        update crm.leads
        set last_contacted_at = greatest(coalesce(last_contacted_at, new.occurred_at), new.occurred_at)
        where id = new.lead_id;
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger activities_after
after insert on crm.activities for each row
execute function crm.trg_activities_after ();

-- Campaign lead counters and the progress bar the gantt reads.
create or replace function crm.trg_leads_rollup_campaign () returns trigger as $$
declare
    v_campaigns uuid[] := '{}';
    v_id uuid;
begin
    if tg_op <> 'INSERT' then
        v_campaigns := v_campaigns || old.campaign_id;
    end if;

    if tg_op <> 'DELETE' then
        v_campaigns := v_campaigns || new.campaign_id;
    end if;

    v_campaigns := array_remove(v_campaigns, null);

    foreach v_id in array v_campaigns loop
        update crm.campaigns c
        set leads_generated = sub.leads,
            progress = case
                when c.target_leads > 0 then least(100, round(100.0 * sub.leads / c.target_leads))::real
                else 0
            end
        from (
            select count(*) as leads
            from crm.leads l
            where l.campaign_id = v_id
        ) as sub
        where c.id = v_id
          and c.leads_generated is distinct from sub.leads;
    end loop;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger leads_rollup_campaign
after insert or update of campaign_id or delete on crm.leads for each row
execute function crm.trg_leads_rollup_campaign ();

-- Quotes add up, and stamp themselves as they move.
create or replace function crm.trg_quotes_apply_defaults () returns trigger as $$
begin
    new.total := round((new.subtotal - new.discount_amount + new.tax_amount)::numeric, 2);

    if new.total < 0 then
        raise exception 'Quote % totals below zero; check the discount.', new.quote_number
            using errcode = 'check_violation';
    end if;

    if new.status = 'sent' and (tg_op = 'INSERT' or old.status <> 'sent') then
        new.sent_at := coalesce(new.sent_at, current_timestamp);
    end if;

    if new.status = 'accepted' and (tg_op = 'INSERT' or old.status <> 'accepted') then
        new.accepted_at := coalesce(new.accepted_at, current_timestamp);
        new.sent_at := coalesce(new.sent_at, current_timestamp);
    end if;

    if new.status <> 'declined' then
        new.declined_reason := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger quotes_apply_defaults
before insert or update on crm.quotes for each row
execute function crm.trg_quotes_apply_defaults ();

create or replace function crm.trg_quotes_log_event () returns trigger as $$
begin
    if new.status = old.status then
        return new;
    end if;

    if new.status in ('sent', 'accepted', 'declined') then
        insert into crm.opportunity_events (opportunity_id, event_type, title, metadata)
        values (
            new.opportunity_id,
            'quote_sent',
            'Quote ' || new.quote_number || ' ' || new.status,
            jsonb_build_object('quote_id', new.id, 'status', new.status, 'total', new.total)
        );
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger quotes_log_event
after update of status on crm.quotes for each row
execute function crm.trg_quotes_log_event ();

-- Task bookkeeping: completion stamps and the overdue flag the board
-- and the alert widget filter on.
create or replace function crm.trg_tasks_apply_defaults () returns trigger as $$
begin
    if new.status = 'completed' and (tg_op = 'INSERT' or old.status <> 'completed') then
        new.completed_at := coalesce(new.completed_at, current_timestamp);
    elsif new.status <> 'completed' then
        new.completed_at := null;
    end if;

    if new.status in ('completed', 'cancelled') then
        new.reminder_at := null;
    else
        new.outcome_notes := null;
    end if;

    new.is_overdue := new.due_on is not null
                  and new.due_on < current_date
                  and new.status not in ('completed', 'cancelled');

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger tasks_apply_defaults
before insert or update on crm.tasks for each row
execute function crm.trg_tasks_apply_defaults ();

----------------------------------------------------------------
-- Scheduled maintenance
--
-- days_in_stage and is_overdue are stored so the kanban, the filter
-- presets and the alert widgets can use an index instead of
-- recomputing per row — which means something has to age them when
-- nothing else touches the record. Run this nightly:
--
--   select cron.schedule(
--     'crm-refresh-ages', '5 0 * * *',
--     $job$ select crm.refresh_deal_ages(); $job$
--   );
----------------------------------------------------------------
create or replace function crm.refresh_deal_ages () returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_deals integer;
  v_tasks integer;
begin
  update crm.opportunities
  set days_in_stage = greatest(0, current_date - stage_changed_at::date)
  where stage not in ('closed_won', 'closed_lost')
    and days_in_stage is distinct from greatest(0, current_date - stage_changed_at::date);

  get diagnostics v_deals = row_count;

  update crm.tasks
  set is_overdue = true
  where not is_overdue
    and due_on is not null
    and due_on < current_date
    and status not in ('completed', 'cancelled');

  get diagnostics v_tasks = row_count;

  return v_deals + v_tasks;
end;
$$;

revoke all on function crm.refresh_deal_ages ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.refresh_deal_ages () to "x-admin";

-- Keep updated_at fresh on the tables without a defaults trigger.
create trigger territories_set_updated_at
before update on crm.territories for each row
execute function supasheet.set_updated_at ();

create trigger sales_reps_set_updated_at
before update on crm.sales_reps for each row
execute function supasheet.set_updated_at ();

create trigger rep_compensation_set_updated_at
before update on crm.rep_compensation for each row
execute function supasheet.set_updated_at ();

create trigger accounts_set_updated_at
before update on crm.accounts for each row
execute function supasheet.set_updated_at ();

create trigger campaigns_set_updated_at
before update on crm.campaigns for each row
execute function supasheet.set_updated_at ();

create trigger pipeline_stages_set_updated_at
before update on crm.pipeline_stages for each row
execute function supasheet.set_updated_at ();

create trigger products_set_updated_at
before update on crm.products for each row
execute function supasheet.set_updated_at ();

create trigger crm_settings_set_updated_at
before update on crm.crm_settings for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Row action: win a deal
----------------------------------------------------------------
create or replace function crm.win_opportunity (p_id uuid, p_close_on date default null) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_stage crm.opportunity_stage;
  v_amount numeric(14, 2);
begin
  select stage, amount into v_stage, v_amount from crm.opportunities where id = p_id;

  if v_stage is null then
    raise exception 'Opportunity not found';
  end if;

  if v_stage in ('closed_won', 'closed_lost') then
    raise exception 'Opportunity is already %', v_stage;
  end if;

  if coalesce(v_amount, 0) <= 0 then
    raise exception 'A deal cannot be won for nothing — set the amount or add line items first';
  end if;

  update crm.opportunities
  set stage = 'closed_won',
      actual_close_on = coalesce(p_close_on, current_date)
  where id = p_id;
end;
$$;

comment on function crm.win_opportunity (uuid, date) is '{
    "type": "action",
    "resource": "opportunities",
    "name": "Mark won",
    "description": "Close this deal as won and stamp the close date",
    "icon": "Trophy",
    "visible": [{"id": "stage", "operator": "not.in", "value": ["closed_won", "closed_lost"]}],
    "confirm": {"title": "Mark this deal as won?", "description": "The account rollups and the forecast update immediately, and the deal is frozen for editing."},
    "success_message": "Deal won"
}';

revoke all on function crm.win_opportunity (uuid, date)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.win_opportunity (uuid, date) to "x-admin",
"manager",
"rep";

----------------------------------------------------------------
-- Row action: lose a deal
----------------------------------------------------------------
create or replace function crm.lose_opportunity (
  p_id uuid,
  p_reason varchar,
  p_competitor varchar default null
) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'A lost deal needs a reason';
  end if;

  update crm.opportunities
  set stage = 'closed_lost',
      closed_reason = p_reason,
      competitor = coalesce(p_competitor, competitor),
      actual_close_on = current_date
  where id = p_id
    and stage not in ('closed_won', 'closed_lost');

  if not found then
    raise exception 'Opportunity not found or already closed';
  end if;
end;
$$;

comment on function crm.lose_opportunity (uuid, varchar, varchar) is '{
    "type": "action",
    "resource": "opportunities",
    "name": "Mark lost",
    "description": "Close this deal as lost, with the reason and the competitor",
    "icon": "CircleX",
    "variant": "destructive",
    "visible": [{"id": "stage", "operator": "not.in", "value": ["closed_won", "closed_lost"]}],
    "confirm": {"title": "Mark this deal as lost?", "description": "It leaves the forecast and is frozen for editing."},
    "success_message": "Deal marked lost"
}';

revoke all on function crm.lose_opportunity (uuid, varchar, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.lose_opportunity (uuid, varchar, varchar) to "x-admin",
"manager",
"rep";

----------------------------------------------------------------
-- Row action: reopen a closed deal (leadership only — this is the
-- escape hatch the freeze guard points people at)
----------------------------------------------------------------
create or replace function crm.reopen_opportunity (
  p_id uuid,
  p_stage crm.opportunity_stage default 'negotiation'
) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_stage in ('closed_won', 'closed_lost') then
    raise exception 'Reopen to an open stage, not %', p_stage;
  end if;

  update crm.opportunities
  set stage = p_stage
  where id = p_id
    and stage in ('closed_won', 'closed_lost');

  if not found then
    raise exception 'Opportunity not found or not closed';
  end if;
end;
$$;

comment on function crm.reopen_opportunity (uuid, crm.opportunity_stage) is '{
    "type": "action",
    "resource": "opportunities",
    "name": "Reopen",
    "description": "Put a closed deal back into the pipeline",
    "icon": "RotateCcw",
    "variant": "secondary",
    "visible": [{"id": "stage", "operator": "in", "value": ["closed_won", "closed_lost"]}],
    "confirm": {"title": "Reopen this deal?", "description": "It re-enters the forecast and the closure record is cleared."},
    "success_message": "Deal reopened"
}';

revoke all on function crm.reopen_opportunity (uuid, crm.opportunity_stage)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.reopen_opportunity (uuid, crm.opportunity_stage) to "x-admin",
"manager";

----------------------------------------------------------------
-- Row action: move a deal through the pipeline (enum value-picker)
----------------------------------------------------------------
create or replace function crm.set_opportunity_stage (p_id uuid, p_stage crm.opportunity_stage) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_stage = 'closed_lost' then
    raise exception 'Use the "Mark lost" action so the reason is captured';
  end if;

  update crm.opportunities set stage = p_stage where id = p_id;
end;
$$;

comment on function crm.set_opportunity_stage (uuid, crm.opportunity_stage) is '{
    "type": "action",
    "resource": "opportunities",
    "name": "Set stage",
    "icon": "ArrowRightLeft",
    "action_type": "picker"
}';

revoke all on function crm.set_opportunity_stage (uuid, crm.opportunity_stage)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.set_opportunity_stage (uuid, crm.opportunity_stage) to "x-admin",
"manager",
"rep";

----------------------------------------------------------------
-- Row action: convert a lead
--
-- The one piece of genuine CRM machinery: a lead becomes an account
-- (reused if the company is already on file), a contact and an open
-- opportunity, and the lead itself is retired with pointers to all
-- three.
----------------------------------------------------------------
create or replace function crm.convert_lead (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_lead crm.leads%rowtype;
  v_account_id uuid;
  v_contact_id uuid;
  v_opportunity_id uuid;
  v_horizon integer;
begin
  select * into v_lead from crm.leads where id = p_id;

  if v_lead.id is null then
    raise exception 'Lead not found';
  end if;

  if v_lead.status = 'converted' then
    raise exception 'Lead % has already been converted', v_lead.reference;
  end if;

  if v_lead.status = 'unqualified' then
    raise exception 'Lead % was disqualified; requalify it before converting', v_lead.reference;
  end if;

  select default_close_horizon_days into v_horizon
  from crm.crm_settings
  order by created_at asc
  limit 1;

  -- Reuse the account when the company is already on file.
  select id into v_account_id
  from crm.accounts
  where lower(name) = lower(btrim(v_lead.company));

  if v_account_id is null then
    insert into crm.accounts (
      name, owner_id, territory_id, account_type, industry,
      employee_count, website, description
    )
    values (
      btrim(v_lead.company),
      v_lead.owner_id,
      v_lead.territory_id,
      'prospect',
      v_lead.industry,
      v_lead.employee_count,
      v_lead.website,
      v_lead.notes
    )
    returning id into v_account_id;
  end if;

  insert into crm.contacts (
    account_id, owner_id, first_name, last_name, email, phone,
    job_title, contact_role
  )
  values (
    v_account_id,
    v_lead.owner_id,
    v_lead.first_name,
    v_lead.last_name,
    v_lead.email,
    v_lead.phone,
    v_lead.job_title,
    'champion'
  )
  returning id into v_contact_id;

  insert into crm.opportunities (
    name, account_id, primary_contact_id, owner_id, territory_id,
    campaign_id, source, stage, opportunity_type, amount,
    expected_close_on
  )
  values (
    btrim(v_lead.company) || ' — new business',
    v_account_id,
    v_contact_id,
    v_lead.owner_id,
    v_lead.territory_id,
    v_lead.campaign_id,
    v_lead.source,
    'qualification',
    'new_business',
    coalesce(v_lead.estimated_value, 0),
    current_date + coalesce(v_horizon, 30)
  )
  returning id into v_opportunity_id;

  update crm.leads
  set status = 'converted',
      converted_at = current_timestamp,
      converted_account_id = v_account_id,
      converted_contact_id = v_contact_id,
      converted_opportunity_id = v_opportunity_id
  where id = p_id;
end;
$$;

comment on function crm.convert_lead (uuid) is '{
    "type": "action",
    "resource": "leads",
    "name": "Convert",
    "description": "Turn this lead into an account, a contact and an open opportunity",
    "icon": "ArrowRightLeft",
    "visible": [{"id": "status", "operator": "not.in", "value": ["converted", "unqualified"]}],
    "confirm": {"title": "Convert this lead?", "description": "An account is created (or matched by company name), along with a contact and a qualification-stage deal."},
    "success_message": "Lead converted"
}';

revoke all on function crm.convert_lead (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.convert_lead (uuid) to "x-admin",
"manager",
"rep";

----------------------------------------------------------------
-- Row action: disqualify a lead
----------------------------------------------------------------
create or replace function crm.disqualify_lead (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'Say why the lead was disqualified';
  end if;

  update crm.leads
  set status = 'unqualified',
      disqualified_reason = p_reason
  where id = p_id
    and status not in ('converted', 'unqualified');

  if not found then
    raise exception 'Lead not found, already disqualified, or already converted';
  end if;
end;
$$;

comment on function crm.disqualify_lead (uuid, varchar) is '{
    "type": "action",
    "resource": "leads",
    "name": "Disqualify",
    "description": "Take this lead out of the queue with a reason",
    "icon": "UserX",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "not.in", "value": ["converted", "unqualified"]}],
    "success_message": "Lead disqualified"
}';

revoke all on function crm.disqualify_lead (uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.disqualify_lead (uuid, varchar) to "x-admin",
"manager",
"rep";

----------------------------------------------------------------
-- Row action: complete a task
----------------------------------------------------------------
create or replace function crm.complete_task (p_id uuid, p_notes text default null) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update crm.tasks
  set status = 'completed',
      outcome_notes = coalesce(p_notes, outcome_notes)
  where id = p_id
    and status not in ('completed', 'cancelled');

  if not found then
    raise exception 'Task not found or already closed';
  end if;
end;
$$;

comment on function crm.complete_task (uuid, text) is '{
    "type": "action",
    "resource": "tasks",
    "name": "Complete",
    "description": "Mark this task done and stamp the time",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "not.in", "value": ["completed", "cancelled"]}],
    "success_message": "Task completed"
}';

revoke all on function crm.complete_task (uuid, text)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.complete_task (uuid, text) to "x-admin",
"manager",
"rep";

----------------------------------------------------------------
-- Row action: generate a quote from the deal's line items
----------------------------------------------------------------
create or replace function crm.generate_quote (p_id uuid, p_valid_days integer default null) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_opportunity crm.opportunities%rowtype;
  v_subtotal numeric(14, 2);
  v_discount numeric(14, 2);
  v_validity integer;
begin
  select * into v_opportunity from crm.opportunities where id = p_id;

  if v_opportunity.id is null then
    raise exception 'Opportunity not found';
  end if;

  select
    coalesce(sum(li.quantity * li.unit_price), 0),
    coalesce(sum(li.quantity * li.unit_price) - sum(li.line_total), 0)
  into v_subtotal, v_discount
  from crm.opportunity_line_items li
  where li.opportunity_id = p_id;

  if v_subtotal <= 0 then
    raise exception 'Add line items before generating a quote';
  end if;

  select quote_validity_days into v_validity
  from crm.crm_settings
  order by created_at asc
  limit 1;

  insert into crm.quotes (
    opportunity_id, account_id, owner_id, status, subtotal,
    discount_amount, tax_amount, currency, valid_until, terms
  )
  values (
    p_id,
    v_opportunity.account_id,
    v_opportunity.owner_id,
    'draft',
    v_subtotal,
    v_discount,
    0,
    v_opportunity.currency,
    current_date + coalesce(p_valid_days, v_validity, 30),
    'Prices in ' || v_opportunity.currency || '. Valid until the date shown above.'
  );
end;
$$;

comment on function crm.generate_quote (uuid, integer) is '{
    "type": "action",
    "resource": "opportunities",
    "name": "Generate quote",
    "description": "Draft a quote from the line items on this deal",
    "icon": "ReceiptText",
    "visible": [{"id": "stage", "operator": "not.in", "value": ["closed_won", "closed_lost"]}],
    "success_message": "Quote drafted"
}';

revoke all on function crm.generate_quote (uuid, integer)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.generate_quote (uuid, integer) to "x-admin",
"manager",
"rep";

----------------------------------------------------------------
-- Row action: accept a quote
----------------------------------------------------------------
create or replace function crm.accept_quote (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_quote crm.quotes%rowtype;
begin
  select * into v_quote from crm.quotes where id = p_id;

  if v_quote.id is null then
    raise exception 'Quote not found';
  end if;

  if v_quote.status = 'accepted' then
    raise exception 'Quote % has already been accepted', v_quote.quote_number;
  end if;

  if v_quote.valid_until < current_date then
    raise exception 'Quote % expired on %', v_quote.quote_number, v_quote.valid_until;
  end if;

  update crm.quotes set status = 'accepted' where id = p_id;

  -- An accepted quote is the strongest buying signal there is: move
  -- the deal to negotiation if it is still earlier in the pipeline.
  update crm.opportunities
  set stage = 'negotiation'
  where id = v_quote.opportunity_id
    and stage in ('qualification', 'discovery', 'proposal');
end;
$$;

comment on function crm.accept_quote (uuid) is '{
    "type": "action",
    "resource": "quotes",
    "name": "Accept",
    "description": "Record the customer accepting this quote",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "sent"]}],
    "confirm": {"title": "Accept this quote?", "description": "The deal moves to negotiation if it is not there already."},
    "success_message": "Quote accepted"
}';

revoke all on function crm.accept_quote (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.accept_quote (uuid) to "x-admin",
"manager",
"rep";

----------------------------------------------------------------
-- Custom form: log an interaction (listed on the "accounts"
-- resource overview). Returns a scalar uuid — the UI toasts and
-- refreshes.
----------------------------------------------------------------
create or replace function crm.log_activity (
  p_account_id uuid,
  p_subject varchar,
  p_activity_type crm.activity_type default 'call',
  p_contact_id uuid default null,
  p_opportunity_id uuid default null,
  p_owner_id uuid default null,
  p_direction crm.activity_direction default 'outbound',
  p_outcome crm.activity_outcome default null,
  p_duration supasheet.DURATION default 0,
  p_notes text default null,
  p_follow_up_on date default null
) returns uuid language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_id uuid;
begin
  insert into crm.activities (
    account_id, contact_id, opportunity_id, owner_id, subject,
    activity_type, direction, outcome, duration, notes, follow_up_on
  )
  values (
    p_account_id,
    p_contact_id,
    p_opportunity_id,
    coalesce(p_owner_id, crm.current_rep_id ()),
    p_subject,
    p_activity_type,
    p_direction,
    p_outcome,
    p_duration,
    p_notes,
    p_follow_up_on
  )
  returning id into v_id;

  -- A follow-up date without a task is a promise nobody keeps.
  if p_follow_up_on is not null then
    insert into crm.tasks (subject, account_id, contact_id, opportunity_id, owner_id, due_on, priority)
    values (
      'Follow up: ' || p_subject,
      p_account_id,
      p_contact_id,
      p_opportunity_id,
      coalesce(p_owner_id, crm.current_rep_id ()),
      p_follow_up_on,
      'normal'
    );
  end if;

  return v_id;
end;
$$;

comment on function crm.log_activity (
  uuid,
  varchar,
  crm.activity_type,
  uuid,
  uuid,
  uuid,
  crm.activity_direction,
  crm.activity_outcome,
  supasheet.DURATION,
  text,
  date
) is '{
    "type": "form",
    "resource": "accounts",
    "name": "Log activity",
    "description": "Record a call, email or meeting — and raise the follow-up task with it.",
    "icon": "PhoneCall",
    "success_message": "Activity logged",
    "fields": {
        "sections": [
            {"id": "what", "title": "What happened", "fields": ["p_subject", "p_activity_type", "p_direction", "p_outcome", "p_duration"]},
            {"id": "who", "title": "Who with", "fields": ["p_account_id", "p_contact_id", "p_opportunity_id", "p_owner_id"]},
            {"id": "follow_up", "title": "Follow-up", "fields": ["p_follow_up_on", "p_notes"]}
        ],
        "relations": {
            "p_account_id": {"table": "accounts", "column": "id", "display": ["name", "tier"]},
            "p_contact_id": {"table": "contacts", "column": "id", "display": ["name", "job_title"]},
            "p_opportunity_id": {"table": "opportunities", "column": "id", "display": ["reference", "name"]},
            "p_owner_id": {"table": "sales_reps", "column": "id", "display": ["name", "job_title"]}
        }
    }
}';

revoke all on function crm.log_activity (
  uuid,
  varchar,
  crm.activity_type,
  uuid,
  uuid,
  uuid,
  crm.activity_direction,
  crm.activity_outcome,
  supasheet.DURATION,
  text,
  date
)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.log_activity (
  uuid,
  varchar,
  crm.activity_type,
  uuid,
  uuid,
  uuid,
  crm.activity_direction,
  crm.activity_outcome,
  supasheet.DURATION,
  text,
  date
) to "x-admin",
"manager",
"rep";

----------------------------------------------------------------
-- Custom form: open a new deal on an account (listed on the
-- "accounts" resource overview). Returns a single object row via
-- explicit OUT parameters — the UI renders the created record as a
-- detail card.
----------------------------------------------------------------
create or replace function crm.open_opportunity (
  p_account_id uuid,
  p_name varchar,
  p_amount numeric default 0,
  p_opportunity_type crm.opportunity_type default 'new_business',
  p_primary_contact_id uuid default null,
  p_owner_id uuid default null,
  p_expected_close_on date default null,
  out opportunity_id uuid,
  out reference varchar,
  out name varchar,
  out account_id uuid,
  out stage crm.opportunity_stage,
  out amount numeric,
  out probability real,
  out expected_close_on date
) language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_account crm.accounts%rowtype;
  v_horizon integer;
  v_opportunity crm.opportunities%rowtype;
begin
  select * into v_account from crm.accounts where id = p_account_id;

  if v_account.id is null then
    raise exception 'Account not found';
  end if;

  if v_account.health = 'churned' then
    raise exception 'Account % has churned — reactivate it before opening a new deal', v_account.name;
  end if;

  select default_close_horizon_days into v_horizon
  from crm.crm_settings
  order by created_at asc
  limit 1;

  insert into crm.opportunities (
    name, account_id, primary_contact_id, owner_id, territory_id,
    opportunity_type, amount, expected_close_on
  )
  values (
    p_name,
    p_account_id,
    p_primary_contact_id,
    coalesce(p_owner_id, v_account.owner_id, crm.current_rep_id ()),
    v_account.territory_id,
    p_opportunity_type,
    coalesce(p_amount, 0),
    coalesce(p_expected_close_on, current_date + coalesce(v_horizon, 30))
  )
  returning * into v_opportunity;

  opportunity_id := v_opportunity.id;
  reference := v_opportunity.reference;
  name := v_opportunity.name;
  account_id := v_opportunity.account_id;
  stage := v_opportunity.stage;
  amount := v_opportunity.amount;
  probability := v_opportunity.probability;
  expected_close_on := v_opportunity.expected_close_on;
end;
$$;

comment on function crm.open_opportunity (
  uuid,
  varchar,
  numeric,
  crm.opportunity_type,
  uuid,
  uuid,
  date
) is '{
    "type": "form",
    "resource": "accounts",
    "name": "Open a deal",
    "description": "Start a new opportunity against this account, pre-wired to its owner and territory.",
    "icon": "Target",
    "success_message": "Opportunity opened",
    "fields": {
        "sections": [
            {"id": "account", "title": "Account", "fields": ["p_account_id", "p_primary_contact_id", "p_owner_id"]},
            {"id": "deal", "title": "Deal", "fields": ["p_name", "p_opportunity_type", "p_amount", "p_expected_close_on"]}
        ],
        "relations": {
            "p_account_id": {"table": "accounts", "column": "id", "display": ["name", "tier"]},
            "p_primary_contact_id": {"table": "contacts", "column": "id", "display": ["name", "job_title"]},
            "p_owner_id": {"table": "sales_reps", "column": "id", "display": ["name", "job_title"]}
        }
    }
}';

revoke all on function crm.open_opportunity (
  uuid,
  varchar,
  numeric,
  crm.opportunity_type,
  uuid,
  uuid,
  date
)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.open_opportunity (
  uuid,
  varchar,
  numeric,
  crm.opportunity_type,
  uuid,
  uuid,
  date
) to "x-admin",
"manager",
"rep";

----------------------------------------------------------------
-- Custom form: hand a departing rep's book to someone else (listed
-- on the "sales_reps" resource overview). Returns
-- setof crm.opportunities — the UI renders the moved rows as a
-- table.
----------------------------------------------------------------
create or replace function crm.bulk_reassign_owner (
  p_from_rep_id uuid,
  p_to_rep_id uuid,
  p_include_accounts boolean default true
) returns setof crm.opportunities language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_from_rep_id = p_to_rep_id then
    raise exception 'Source and target rep must differ';
  end if;

  if not exists (
    select 1 from crm.sales_reps where id = p_to_rep_id and status = 'active'
  ) then
    raise exception 'The receiving rep must be active';
  end if;

  if p_include_accounts then
    update crm.accounts set owner_id = p_to_rep_id where owner_id = p_from_rep_id;
    update crm.contacts set owner_id = p_to_rep_id where owner_id = p_from_rep_id;
    update crm.leads
    set owner_id = p_to_rep_id
    where owner_id = p_from_rep_id
      and status in ('new', 'working', 'nurturing');
  end if;

  return query
  update crm.opportunities
  set owner_id = p_to_rep_id
  where owner_id = p_from_rep_id
    and stage not in ('closed_won', 'closed_lost')
  returning *;
end;
$$;

comment on function crm.bulk_reassign_owner (uuid, uuid, boolean) is '{
    "type": "form",
    "resource": "sales_reps",
    "name": "Reassign book",
    "description": "Move every open deal — and optionally the accounts, contacts and live leads — from one rep to another.",
    "icon": "ArrowRightLeft",
    "success_message": "Book reassigned",
    "fields": {
        "sections": [
            {"id": "handover", "title": "Handover", "fields": ["p_from_rep_id", "p_to_rep_id", "p_include_accounts"]}
        ],
        "relations": {
            "p_from_rep_id": {"table": "sales_reps", "column": "id", "display": ["name", "job_title"]},
            "p_to_rep_id": {"table": "sales_reps", "column": "id", "display": ["name", "job_title"]}
        }
    }
}';

revoke all on function crm.bulk_reassign_owner (uuid, uuid, boolean)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.bulk_reassign_owner (uuid, uuid, boolean) to "x-admin",
"manager";

----------------------------------------------------------------
-- Custom form: what a territory is carrying, rep by rep (listed on
-- the "territories" resource overview). Pure computation — no
-- writes. Returns setof rows via an explicit table(...) column list.
----------------------------------------------------------------
create or replace function crm.preview_territory_pipeline (
  p_territory_id uuid,
  p_include_closed boolean default false
) returns table (
  rep varchar,
  open_deals bigint,
  open_amount numeric,
  weighted_amount numeric,
  won_amount numeric,
  win_rate numeric,
  quota_attainment numeric
) language plpgsql security invoker
set
  search_path = '' as $$
begin
  return query
  select
    r.name,
    count(o.id) filter (where o.stage not in ('closed_won', 'closed_lost')) as open_deals,
    coalesce(sum(o.amount) filter (where o.stage not in ('closed_won', 'closed_lost')), 0) as open_amount,
    coalesce(sum(o.weighted_amount) filter (where o.stage not in ('closed_won', 'closed_lost')), 0) as weighted_amount,
    coalesce(sum(o.amount) filter (where o.stage = 'closed_won'), 0) as won_amount,
    round(
      100.0 * count(o.id) filter (where o.stage = 'closed_won')
      / nullif(count(o.id) filter (where o.stage in ('closed_won', 'closed_lost')), 0),
      1
    ) as win_rate,
    round(
      100.0 * coalesce(sum(o.amount) filter (where o.stage = 'closed_won'), 0)
      / nullif(r.annual_quota, 0),
      1
    ) as quota_attainment
  from crm.sales_reps r
  left join crm.opportunities o
    on o.owner_id = r.id
   and (p_include_closed or o.stage not in ('closed_won', 'closed_lost') or o.stage = 'closed_won')
  where r.territory_id = p_territory_id
  group by r.id, r.name, r.annual_quota
  order by open_amount desc, r.name;
end;
$$;

comment on function crm.preview_territory_pipeline (uuid, boolean) is '{
    "type": "form",
    "resource": "territories",
    "name": "Preview pipeline",
    "description": "Open pipeline, weighted forecast, win rate and quota attainment per rep in this territory.",
    "icon": "Gauge",
    "success_message": "Pipeline calculated",
    "fields": {
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["p_territory_id", "p_include_closed"]}
        ],
        "relations": {
            "p_territory_id": {"table": "territories", "column": "id", "display": ["name", "code"]}
        }
    }
}';

revoke all on function crm.preview_territory_pipeline (uuid, boolean)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function crm.preview_territory_pipeline (uuid, boolean) to "x-admin",
"manager",
"rep";

----------------------------------------------------------------
-- Templates (bulk insert payloads applied via supasheet.apply_template)
--
--   select supasheet.apply_template('crm', '<template_view>', 'tasks');
--
-- Only column names present on BOTH the view and the target table
-- are copied; everything else falls back to the target's defaults.
----------------------------------------------------------------
-- Static: the checklist every newly won customer gets. Apply to
-- crm.tasks, then set the account and the owner on the new rows.
create or replace view crm.onboarding_tasks_template
with
  (security_invoker = true) as
select
  *
from
  (
    values
      (
        'Send the welcome email and introduce the CSM'::varchar(255),
        'high'::crm.priority_level,
        1
      ),
      (
        'Book the kick-off call with the buying committee',
        'high',
        3
      ),
      (
        'Collect technical requirements and SSO metadata',
        'normal',
        7
      ),
      (
        'Provision the production workspace',
        'normal',
        10
      ),
      ('Run the admin training session', 'normal', 21),
      ('Schedule the 90-day business review', 'low', 90)
  ) as t (subject, priority, offset_days);

revoke all on crm.onboarding_tasks_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.onboarding_tasks_template to "x-admin",
  "manager",
  "rep";

comment on view crm.onboarding_tasks_template is '{"type": "template", "name": "Customer Onboarding Tasks", "description": "The six tasks every newly won customer gets. Apply to crm.tasks, then set the account and the owner.", "target_table": "tasks"}';

-- Dynamic: the next renewal for every customer whose won deal is
-- coming up on its anniversary and has nothing open against it yet.
create or replace view crm.renewal_opportunities_template
with
  (security_invoker = true) as
select
  (
    a.name || ' — renewal ' || to_char(o.actual_close_on + 365, 'YYYY')
  )::varchar(255) as name,
  o.account_id,
  o.primary_contact_id,
  o.owner_id,
  o.territory_id,
  o.amount,
  o.currency,
  'renewal'::crm.opportunity_type as opportunity_type,
  'qualification'::crm.opportunity_stage as stage,
  'referral'::crm.lead_source as source,
  (o.actual_close_on + 365) as expected_close_on
from
  crm.opportunities o
  join crm.accounts a on a.id = o.account_id
where
  o.stage = 'closed_won'
  and o.actual_close_on is not null
  and o.actual_close_on + 365 between current_date - 30 and current_date  + 90
  and a.health <> 'churned'
  and not exists (
    select
      1
    from
      crm.opportunities open_deal
    where
      open_deal.account_id = o.account_id
      and open_deal.opportunity_type = 'renewal'
      and open_deal.stage not in ('closed_won', 'closed_lost')
  );

revoke all on crm.renewal_opportunities_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.renewal_opportunities_template to "x-admin",
  "manager";

comment on view crm.renewal_opportunities_template is '{"type": "template", "name": "Upcoming Renewals", "description": "A renewal deal for every customer coming up on the anniversary of a won deal, skipping accounts that already have one open. Apply to crm.opportunities.", "target_table": "opportunities"}';

-- Dynamic: a chase task for every deal that has sat in the same
-- stage past the policy window.
create or replace view crm.stale_deal_followup_template
with
  (security_invoker = true) as
select
  (
    'Stalled ' || o.days_in_stage || ' days: ' || o.name
  )::varchar(255) as subject,
  (
    'This deal has not moved since ' || to_char(o.stage_changed_at, 'Mon DD, YYYY') || '. Confirm the next step or close it out.'
  )::text as description,
  o.account_id,
  o.primary_contact_id as contact_id,
  o.id as opportunity_id,
  o.owner_id,
  'high'::crm.priority_level as priority,
  current_date as due_on
from
  crm.opportunities o
where
  o.stage not in ('closed_won', 'closed_lost')
  and o.days_in_stage >= coalesce(
    (
      select
        s.stale_deal_days
      from
        crm.crm_settings s
      order by
        s.created_at asc
      limit
        1
    ),
    30
  );

revoke all on crm.stale_deal_followup_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.stale_deal_followup_template to "x-admin",
  "manager";

comment on view crm.stale_deal_followup_template is '{"type": "template", "name": "Stalled Deal Chasers", "description": "A high-priority chase task for every open deal that has sat in one stage past the policy window. Apply to crm.tasks.", "target_table": "tasks"}';

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view crm.pipeline_report
with
  (security_invoker = true) as
select
  o.id,
  o.reference,
  o.name,
  a.name as account,
  a.tier as account_tier,
  c.name as primary_contact,
  r.name as owner,
  t.name as territory,
  cp.name as campaign,
  o.stage,
  o.forecast_category,
  o.opportunity_type,
  o.amount,
  o.probability,
  o.weighted_amount,
  o.currency,
  o.opened_on,
  o.expected_close_on,
  o.actual_close_on,
  o.days_in_stage,
  case
    when o.actual_close_on is not null then o.actual_close_on - o.opened_on
    else current_date - o.opened_on
  end as age_days,
  o.closed_reason,
  o.competitor,
  o.next_step,
  o.last_activity_at,
  (
    select
      count(*)
    from
      crm.opportunity_line_items li
    where
      li.opportunity_id = o.id
  ) as line_items,
  o.created_at
from
  crm.opportunities o
  join crm.accounts a on a.id = o.account_id
  left join crm.contacts c on c.id = o.primary_contact_id
  left join crm.sales_reps r on r.id = o.owner_id
  left join crm.territories t on t.id = o.territory_id
  left join crm.campaigns cp on cp.id = o.campaign_id;

revoke all on crm.pipeline_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.pipeline_report to "x-admin",
  "manager",
  "rep";

-- `template: true` means a Handlebars HTML file has been uploaded to
-- the `report-templates` bucket at the deterministic key
-- `crm/pipeline_report.hbs` (one template per report). Upload
-- supabase/examples/templates/pipeline_report.hbs there as-is (as
-- "x-admin") to enable the "Print Report" button on this report.
comment on view crm.pipeline_report is '{"type": "report", "name": "Pipeline Report", "description": "Every deal with account, owner, forecast and cycle context", "template": true}';

create or replace view crm.forecast_report
with
  (security_invoker = true) as
select
  r.name as rep,
  t.name as territory,
  to_char(
    date_trunc('month', o.expected_close_on),
    'YYYY-MM'
  ) as close_month,
  count(*) as deals,
  coalesce(sum(o.amount), 0) as pipeline_amount,
  coalesce(sum(o.weighted_amount), 0) as weighted_amount,
  coalesce(
    sum(o.amount) filter (
      where
        o.forecast_category = 'commit'
    ),
    0
  ) as commit_amount,
  coalesce(
    sum(o.amount) filter (
      where
        o.forecast_category = 'best_case'
    ),
    0
  ) as best_case_amount,
  coalesce(
    sum(o.amount) filter (
      where
        o.stage = 'closed_won'
    ),
    0
  ) as closed_amount,
  r.annual_quota
from
  crm.opportunities o
  left join crm.sales_reps r on r.id = o.owner_id
  left join crm.territories t on t.id = o.territory_id
where
  o.stage <> 'closed_lost'
group by
  r.id,
  r.name,
  r.annual_quota,
  t.name,
  date_trunc('month', o.expected_close_on)
order by
  close_month,
  weighted_amount desc;

revoke all on crm.forecast_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.forecast_report to "x-admin",
  "manager";

comment on view crm.forecast_report is '{"type": "report", "name": "Forecast", "description": "Pipeline, weighted, commit and closed revenue by rep and close month"}';

create or replace view crm.win_loss_report
with
  (security_invoker = true) as
select
  o.id,
  o.reference,
  o.name,
  a.name as account,
  a.tier as account_tier,
  r.name as owner,
  o.opportunity_type,
  o.source,
  o.amount,
  o.stage,
  o.opened_on,
  o.actual_close_on,
  (o.actual_close_on - o.opened_on) as cycle_days,
  o.closed_reason,
  o.competitor,
  (
    select
      count(*)
    from
      crm.activities act
    where
      act.opportunity_id = o.id
  ) as activities_logged,
  (
    select
      count(*)
    from
      crm.opportunity_contacts oc
    where
      oc.opportunity_id = o.id
  ) as committee_size
from
  crm.opportunities o
  join crm.accounts a on a.id = o.account_id
  left join crm.sales_reps r on r.id = o.owner_id
where
  o.stage in ('closed_won', 'closed_lost');

revoke all on crm.win_loss_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.win_loss_report to "x-admin",
  "manager";

comment on view crm.win_loss_report is '{"type": "report", "name": "Win / Loss", "description": "Closed deals with cycle length, reason, competitor and engagement depth"}';

create or replace view crm.accounts_report
with
  (security_invoker = true) as
select
  a.id,
  a.name as account,
  a.account_type,
  a.tier,
  a.health,
  a.industry,
  a.billing_country as country,
  r.name as owner,
  t.name as territory,
  parent.name as parent_account,
  a.employee_count,
  a.annual_revenue,
  count(distinct c.id) as contacts,
  count(distinct o.id) as opportunities,
  count(distinct o.id) filter (
    where
      o.stage not in ('closed_won', 'closed_lost')
  ) as open_opportunities,
  a.open_pipeline_amount,
  a.won_amount,
  count(distinct act.id) as activities,
  a.last_activity_at,
  case
    when a.last_activity_at is null then null
    else current_date - a.last_activity_at::date
  end as days_since_contact,
  a.customer_since
from
  crm.accounts a
  left join crm.sales_reps r on r.id = a.owner_id
  left join crm.territories t on t.id = a.territory_id
  left join crm.accounts parent on parent.id = a.parent_account_id
  left join crm.contacts c on c.account_id = a.id
  left join crm.opportunities o on o.account_id = a.id
  left join crm.activities act on act.account_id = a.id
group by
  a.id,
  a.name,
  a.account_type,
  a.tier,
  a.health,
  a.industry,
  a.billing_country,
  r.name,
  t.name,
  parent.name;

revoke all on crm.accounts_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.accounts_report to "x-admin",
  "manager",
  "rep";

comment on view crm.accounts_report is '{"type": "report", "name": "Account Report", "description": "Coverage, pipeline, revenue and engagement per account"}';

create or replace view crm.rep_performance_report
with
  (security_invoker = true) as
select
  r.id,
  r.name as rep,
  r.level,
  r.status,
  t.name as territory,
  m.name as manager,
  r.annual_quota,
  count(o.id) filter (
    where
      o.stage not in ('closed_won', 'closed_lost')
  ) as open_deals,
  coalesce(
    sum(o.amount) filter (
      where
        o.stage not in ('closed_won', 'closed_lost')
    ),
    0
  ) as open_amount,
  coalesce(
    sum(o.weighted_amount) filter (
      where
        o.stage not in ('closed_won', 'closed_lost')
    ),
    0
  ) as weighted_amount,
  coalesce(
    sum(o.amount) filter (
      where
        o.stage = 'closed_won'
    ),
    0
  ) as won_amount,
  count(o.id) filter (
    where
      o.stage = 'closed_won'
  ) as won_deals,
  count(o.id) filter (
    where
      o.stage = 'closed_lost'
  ) as lost_deals,
  round(
    100.0 * count(o.id) filter (
      where
        o.stage = 'closed_won'
    ) / nullif(
      count(o.id) filter (
        where
          o.stage in ('closed_won', 'closed_lost')
      ),
      0
    ),
    1
  ) as win_rate,
  round(
    100.0 * coalesce(
      sum(o.amount) filter (
        where
          o.stage = 'closed_won'
      ),
      0
    ) / nullif(r.annual_quota, 0),
    1
  ) as quota_attainment,
  round(
    avg(o.actual_close_on - o.opened_on) filter (
      where
        o.stage = 'closed_won'
    ),
    1
  ) as average_cycle_days,
  (
    select
      count(*)
    from
      crm.activities act
    where
      act.owner_id = r.id
  ) as activities_logged
from
  crm.sales_reps r
  left join crm.territories t on t.id = r.territory_id
  left join crm.sales_reps m on m.id = r.manager_id
  left join crm.opportunities o on o.owner_id = r.id
group by
  r.id,
  r.name,
  r.level,
  r.status,
  r.annual_quota,
  t.name,
  m.name;

revoke all on crm.rep_performance_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.rep_performance_report to "x-admin",
  "manager";

comment on view crm.rep_performance_report is '{"type": "report", "name": "Rep Performance", "description": "Quota attainment, win rate, cycle length and activity per rep"}';

create or replace view crm.activity_report
with
  (security_invoker = true) as
select
  r.name as rep,
  act.activity_type,
  act.direction,
  count(*) as activities,
  count(*) filter (
    where
      act.outcome = 'connected'
  ) as connected,
  round(sum(act.duration) / 3600000.0, 1) as hours_logged,
  count(distinct act.account_id) as accounts_touched,
  count(distinct act.opportunity_id) as deals_touched,
  max(act.occurred_at) as last_activity_at
from
  crm.activities act
  left join crm.sales_reps r on r.id = act.owner_id
group by
  r.id,
  r.name,
  act.activity_type,
  act.direction
order by
  activities desc;

revoke all on crm.activity_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.activity_report to "x-admin",
  "manager";

comment on view crm.activity_report is '{"type": "report", "name": "Activity Report", "description": "Interaction volume, connect rate and time logged per rep and channel"}';

----------------------------------------------------------------
-- Materialized view report (precomputed monthly bookings)
--
-- Two different refreshes — don't confuse them:
--   select supasheet.refresh_metadata();            -- the catalog
--   refresh materialized view concurrently
--     crm.revenue_rollup;                           -- the data
----------------------------------------------------------------
create materialized view crm.revenue_rollup as
select
  to_char(date_trunc('month', o.actual_close_on), 'YYYY-MM') as month,
  count(*) filter (
    where
      o.stage = 'closed_won'
  ) as deals_won,
  count(*) filter (
    where
      o.stage = 'closed_lost'
  ) as deals_lost,
  coalesce(
    sum(o.amount) filter (
      where
        o.stage = 'closed_won'
    ),
    0
  ) as bookings,
  coalesce(
    sum(o.amount) filter (
      where
        o.stage = 'closed_lost'
    ),
    0
  ) as lost_amount,
  round(
    avg(o.amount) filter (
      where
        o.stage = 'closed_won'
    ),
    2
  ) as average_deal_size,
  round(
    avg(o.actual_close_on - o.opened_on) filter (
      where
        o.stage = 'closed_won'
    ),
    1
  ) as average_cycle_days,
  count(distinct o.owner_id) filter (
    where
      o.stage = 'closed_won'
  ) as reps_with_wins,
  round(
    100.0 * count(*) filter (
      where
        o.stage = 'closed_won'
    ) / nullif(count(*), 0),
    1
  ) as win_rate
from
  crm.opportunities o
where
  o.actual_close_on is not null
group by
  date_trunc('month', o.actual_close_on)
order by
  date_trunc('month', o.actual_close_on) desc;

-- Unique index is REQUIRED for `refresh ... concurrently`.
create unique index idx_crm_revenue_rollup_month on crm.revenue_rollup (month);

revoke all on crm.revenue_rollup
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.revenue_rollup to "x-admin",
  "manager";

comment on materialized view crm.revenue_rollup is '{"type": "report", "name": "Monthly Bookings", "description": "Precomputed monthly bookings, win rate, deal size and cycle length"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: open pipeline value
create or replace view crm.open_pipeline_value
with
  (security_invoker = true) as
select
  round(coalesce(sum(amount), 0), 0) as value,
  'target' as icon,
  'open pipeline' as label
from
  crm.opportunities
where
  stage not in ('closed_won', 'closed_lost');

revoke all on crm.open_pipeline_value
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.open_pipeline_value to "x-admin",
  "manager",
  "rep";

-- card_2: won against lost, this year
create or replace view crm.won_lost_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      stage = 'closed_won'
  ) as primary,
  count(*) filter (
    where
      stage = 'closed_lost'
  ) as secondary,
  'Won' as primary_label,
  'Lost' as secondary_label
from
  crm.opportunities
where
  actual_close_on >= date_trunc('year', current_date);

revoke all on crm.won_lost_split
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.won_lost_split to "x-admin",
  "manager",
  "rep";

-- card_3: win rate across everything closed
create or replace view crm.win_rate_card
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        stage = 'closed_won'
    ) / nullif(count(*), 0),
    1
  ) as percent
from
  crm.opportunities
where
  stage in ('closed_won', 'closed_lost');

revoke all on crm.win_rate_card
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.win_rate_card to "x-admin",
  "manager",
  "rep";

-- card_4: how the open pipeline splits across forecast categories
create or replace view crm.forecast_coverage_progress
with
  (security_invoker = true) as
select
  round(
    coalesce(
      sum(amount) filter (
        where
          forecast_category in ('commit', 'closed')
      ),
      0
    ),
    0
  ) as current,
  round(coalesce(sum(amount), 0), 0) as total,
  json_build_array(
    json_build_object(
      'label',
      'Pipeline',
      'value',
      round(
        coalesce(
          sum(amount) filter (
            where
              forecast_category = 'pipeline'
          ),
          0
        ),
        0
      )
    ),
    json_build_object(
      'label',
      'Best case',
      'value',
      round(
        coalesce(
          sum(amount) filter (
            where
              forecast_category = 'best_case'
          ),
          0
        ),
        0
      )
    ),
    json_build_object(
      'label',
      'Commit',
      'value',
      round(
        coalesce(
          sum(amount) filter (
            where
              forecast_category = 'commit'
          ),
          0
        ),
        0
      )
    ),
    json_build_object(
      'label',
      'Closed',
      'value',
      round(
        coalesce(
          sum(amount) filter (
            where
              forecast_category = 'closed'
          ),
          0
        ),
        0
      )
    )
  ) as segments
from
  crm.opportunities
where
  stage <> 'closed_lost';

revoke all on crm.forecast_coverage_progress
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.forecast_coverage_progress to "x-admin",
  "manager";

-- card_5: headline open pipeline plus a ranked breakdown by stage
create or replace view crm.pipeline_by_stage_overview
with
  (security_invoker = true) as
select
  round(
    coalesce(
      sum(amount) filter (
        where
          stage not in ('closed_won', 'closed_lost')
      ),
      0
    ),
    0
  ) as value,
  'Open Pipeline' as label,
  'target' as icon,
  json_build_array(
    json_build_object(
      'label',
      'Negotiation',
      'value',
      round(
        coalesce(
          sum(amount) filter (
            where
              stage = 'negotiation'
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
      'Proposal',
      'value',
      round(
        coalesce(
          sum(amount) filter (
            where
              stage = 'proposal'
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
      'Discovery',
      'value',
      round(
        coalesce(
          sum(amount) filter (
            where
              stage = 'discovery'
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
      'Qualification',
      'value',
      round(
        coalesce(
          sum(amount) filter (
            where
              stage = 'qualification'
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
  crm.opportunities;

revoke all on crm.pipeline_by_stage_overview
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.pipeline_by_stage_overview to "x-admin",
  "manager",
  "rep";

-- card_6: full-width metric grid
create or replace view crm.sales_pulse
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Open deals',
      'value',
      count(*) filter (
        where
          stage not in ('closed_won', 'closed_lost')
      ),
      'icon',
      'target'
    ),
    json_build_object(
      'label',
      'Commit',
      'value',
      round(
        coalesce(
          sum(amount) filter (
            where
              forecast_category = 'commit'
          ),
          0
        ),
        0
      ),
      'icon',
      'hand-coins'
    ),
    json_build_object(
      'label',
      'Won 30d',
      'value',
      round(
        coalesce(
          sum(amount) filter (
            where
              stage = 'closed_won'
              and actual_close_on >= current_date - 30
          ),
          0
        ),
        0
      ),
      'icon',
      'trophy'
    ),
    json_build_object(
      'label',
      'Avg deal',
      'value',
      round(
        coalesce(
          avg(amount) filter (
            where
              stage = 'closed_won'
          ),
          0
        ),
        0
      ),
      'icon',
      'dollar-sign'
    ),
    json_build_object(
      'label',
      'Stalled 30d+',
      'value',
      count(*) filter (
        where
          stage not in ('closed_won', 'closed_lost')
          and days_in_stage >= 30
      ),
      'icon',
      'timer-off'
    ),
    json_build_object(
      'label',
      'Open leads',
      'value',
      (
        select
          count(*)
        from
          crm.leads
        where
          status in ('new', 'working', 'nurturing')
      ),
      'icon',
      'user-plus'
    )
  ) as metrics
from
  crm.opportunities;

revoke all on crm.sales_pulse
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.sales_pulse to "x-admin",
  "manager";

-- table_1: what is meant to close this month
create or replace view crm.closing_this_month
with
  (security_invoker = true) as
select
  o.reference,
  o.name,
  a.name as account,
  o.stage,
  round(o.amount, 0) as amount,
  to_char(o.expected_close_on, 'Mon DD') as close_date,
  '/crm/resource/opportunities/' || o.id || '/detail' as link
from
  crm.opportunities o
  join crm.accounts a on a.id = o.account_id
where
  o.stage not in ('closed_won', 'closed_lost')
  and o.expected_close_on < date_trunc('month', current_date) + interval '1 month'
order by
  o.expected_close_on asc
limit
  10;

revoke all on crm.closing_this_month
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.closing_this_month to "x-admin",
  "manager",
  "rep";

-- table_1: the wins board (pairs with Closing This Month)
create or replace view crm.recent_wins
with
  (security_invoker = true) as
select
  o.name,
  a.name as account,
  r.name as owner,
  round(o.amount, 0) as amount,
  to_char(o.actual_close_on, 'Mon DD') as closed,
  '/crm/resource/opportunities/' || o.id || '/detail' as link
from
  crm.opportunities o
  join crm.accounts a on a.id = o.account_id
  left join crm.sales_reps r on r.id = o.owner_id
where
  o.stage = 'closed_won'
order by
  o.actual_close_on desc nulls last
limit
  10;

revoke all on crm.recent_wins
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.recent_wins to "x-admin",
  "manager",
  "rep";

-- table_2: the rep scorecard
create or replace view crm.rep_scorecard
with
  (security_invoker = true) as
select
  r.name as rep,
  count(o.id) filter (
    where
      o.stage not in ('closed_won', 'closed_lost')
  ) as open_deals,
  round(
    coalesce(
      sum(o.amount) filter (
        where
          o.stage not in ('closed_won', 'closed_lost')
      ),
      0
    ),
    0
  ) as open_amount,
  round(
    coalesce(
      sum(o.amount) filter (
        where
          o.stage = 'closed_won'
      ),
      0
    ),
    0
  ) as won_amount,
  round(
    100.0 * coalesce(
      sum(o.amount) filter (
        where
          o.stage = 'closed_won'
      ),
      0
    ) / nullif(r.annual_quota, 0),
    0
  ) as quota_pct,
  '/crm/resource/sales_reps/' || r.id || '/detail' as link
from
  crm.sales_reps r
  left join crm.opportunities o on o.owner_id = r.id
where
  r.status = 'active'
group by
  r.id,
  r.name,
  r.annual_quota
order by
  won_amount desc
limit
  10;

revoke all on crm.rep_scorecard
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.rep_scorecard to "x-admin",
  "manager";

-- list_1: deals that have stopped moving
create or replace view crm.stalled_deals
with
  (security_invoker = true) as
select
  o.name as title,
  a.name || ' · ' || o.days_in_stage || ' days in ' || o.stage as description,
  'timer-off' as icon,
  'warning' as variant,
  '/crm/resource/opportunities/' || o.id || '/detail' as link
from
  crm.opportunities o
  join crm.accounts a on a.id = o.account_id
where
  o.stage not in ('closed_won', 'closed_lost')
  and o.days_in_stage >= 21
order by
  o.days_in_stage desc
limit
  10;

revoke all on crm.stalled_deals
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.stalled_deals to "x-admin",
  "manager",
  "rep";

-- list_2: overdue follow-ups (wider list)
create or replace view crm.overdue_tasks
with
  (security_invoker = true) as
select
  t.subject as title,
  coalesce(a.name, l.company, 'No account') as description,
  'circle-alert' as icon,
  'destructive' as variant,
  t.priority as field_1,
  to_char(t.due_on, 'Mon DD') as field_2,
  '/crm/resource/tasks/' || t.id || '/detail' as link
from
  crm.tasks t
  left join crm.accounts a on a.id = t.account_id
  left join crm.leads l on l.id = t.lead_id
where
  t.is_overdue
order by
  t.due_on asc
limit
  10;

revoke all on crm.overdue_tasks
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.overdue_tasks to "x-admin",
  "manager",
  "rep";

-- list_3: the floor's activity feed
create or replace view crm.recent_sales_activity
with
  (security_invoker = true) as
select
  coalesce(r.name, 'Someone') as actor,
  case act.activity_type
    when 'call' then 'called'
    when 'email' then 'emailed'
    when 'meeting' then 'met with'
    when 'demo' then 'demoed to'
    when 'site_visit' then 'visited'
    else 'noted'
  end as action,
  coalesce(a.name, c.name, l.company, act.subject) as entity,
  to_char(act.occurred_at, 'Mon DD, YYYY') as date,
  case
    when act.opportunity_id is not null then '/crm/resource/opportunities/' || act.opportunity_id || '/detail'
    when act.account_id is not null then '/crm/resource/accounts/' || act.account_id || '/detail'
    else '/crm/resource/activities/' || act.id || '/detail'
  end as link
from
  crm.activities act
  left join crm.sales_reps r on r.id = act.owner_id
  left join crm.accounts a on a.id = act.account_id
  left join crm.contacts c on c.id = act.contact_id
  left join crm.leads l on l.id = act.lead_id
order by
  act.occurred_at desc
limit
  10;

revoke all on crm.recent_sales_activity
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.recent_sales_activity to "x-admin",
  "manager";

-- list_4: leaderboard by closed revenue
create or replace view crm.top_reps
with
  (security_invoker = true) as
select
  r.name,
  round(coalesce(sum(o.amount), 0), 0) as value,
  r.job_title as label,
  '/crm/resource/sales_reps/' || r.id || '/detail' as link
from
  crm.sales_reps r
  join crm.opportunities o on o.owner_id = r.id
where
  o.stage = 'closed_won'
group by
  r.id,
  r.name,
  r.job_title
order by
  value desc
limit
  10;

revoke all on crm.top_reps
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.top_reps to "x-admin",
  "manager";

-- card_1: the unassigned lead pool — shown on the leads resource page
create or replace view crm.unassigned_leads_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'user-plus' as icon,
  'unassigned leads' as label
from
  crm.leads
where
  owner_id is null
  and status in ('new', 'working', 'nurturing');

revoke all on crm.unassigned_leads_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.unassigned_leads_count to "x-admin",
  "manager",
  "rep";

-- card_2: healthy against at-risk — shown on the accounts page
create or replace view crm.account_health_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      health = 'healthy'
  ) as primary,
  count(*) filter (
    where
      health in ('watch', 'at_risk', 'churned')
  ) as secondary,
  'Healthy' as primary_label,
  'Needs Attention' as secondary_label
from
  crm.accounts;

revoke all on crm.account_health_split
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.account_health_split to "x-admin",
  "manager",
  "rep";

-- card_3: quote acceptance — shown on the quotes resource page
create or replace view crm.quote_acceptance_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        status = 'accepted'
    ) / nullif(
      count(*) filter (
        where
          status in ('accepted', 'declined', 'expired')
      ),
      0
    ),
    1
  ) as percent
from
  crm.quotes;

revoke all on crm.quote_acceptance_rate
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.quote_acceptance_rate to "x-admin",
  "manager",
  "rep";

-- card_1: open follow-ups — shown on the tasks resource page
create or replace view crm.open_tasks_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'list-todo' as icon,
  'open tasks' as label
from
  crm.tasks
where
  status in ('not_started', 'in_progress', 'waiting');

revoke all on crm.open_tasks_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.open_tasks_count to "x-admin",
  "manager",
  "rep";

comment on view crm.open_pipeline_value is '{"type": "dashboard_widget", "name": "Open Pipeline", "description": "Value of every deal still in play", "widget_type": "card_1"}';

comment on view crm.won_lost_split is '{"type": "dashboard_widget", "name": "Won vs Lost", "description": "Deals closed this year", "widget_type": "card_2"}';

comment on view crm.win_rate_card is '{"type": "dashboard_widget", "name": "Win Rate", "description": "Share of closed deals that were won", "widget_type": "card_3"}';

comment on view crm.forecast_coverage_progress is '{"type": "dashboard_widget", "name": "Forecast Coverage", "description": "How the pipeline splits across forecast categories", "widget_type": "card_4"}';

comment on view crm.pipeline_by_stage_overview is '{"type": "dashboard_widget", "name": "Pipeline By Stage", "description": "Open pipeline broken down by stage", "widget_type": "card_5"}';

comment on view crm.sales_pulse is '{"type": "dashboard_widget", "name": "Sales Pulse", "description": "Headline pipeline and bookings metrics at a glance", "widget_type": "card_6"}';

comment on view crm.closing_this_month is '{"type": "dashboard_widget", "name": "Closing This Month", "description": "Open deals due to close inside the current month", "widget_type": "table_1", "resource": "opportunities", "url": "/crm/resource/opportunities"}';

comment on view crm.recent_wins is '{"type": "dashboard_widget", "name": "Recent Wins", "description": "The last ten deals closed won", "widget_type": "table_1", "url": "/crm/resource/opportunities"}';

comment on view crm.rep_scorecard is '{"type": "dashboard_widget", "name": "Rep Scorecard", "description": "Open pipeline, bookings and quota attainment per rep", "widget_type": "table_2", "url": "/crm/resource/sales_reps"}';

comment on view crm.stalled_deals is '{"type": "dashboard_widget", "name": "Stalled Deals", "description": "Open deals that have not moved in three weeks", "widget_type": "list_1", "url": "/crm/resource/opportunities"}';

comment on view crm.overdue_tasks is '{"type": "dashboard_widget", "name": "Overdue Follow-ups", "description": "Tasks past their due date", "widget_type": "list_2", "url": "/crm/resource/tasks"}';

comment on view crm.recent_sales_activity is '{"type": "dashboard_widget", "name": "Recent Activity", "description": "Latest interactions logged across the floor", "widget_type": "list_3", "url": "/crm/resource/activities"}';

comment on view crm.top_reps is '{"type": "dashboard_widget", "name": "Top Reps", "description": "Reps ranked by closed revenue", "widget_type": "list_4", "url": "/crm/resource/sales_reps"}';

comment on view crm.unassigned_leads_count is '{"type": "dashboard_widget", "name": "Unassigned Leads", "description": "Leads waiting for an owner", "widget_type": "card_1", "resource": "leads"}';

comment on view crm.account_health_split is '{"type": "dashboard_widget", "name": "Account Health", "description": "Healthy accounts vs everything else", "widget_type": "card_2", "resource": "accounts"}';

comment on view crm.quote_acceptance_rate is '{"type": "dashboard_widget", "name": "Quote Acceptance", "description": "Share of decided quotes that were accepted", "widget_type": "card_3", "resource": "quotes"}';

comment on view crm.open_tasks_count is '{"type": "dashboard_widget", "name": "Open Tasks", "description": "Follow-ups still to do", "widget_type": "card_1", "resource": "tasks"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: open pipeline value by stage
create or replace view crm.deals_by_stage_pie
with
  (security_invoker = true) as
select
  stage::text as label,
  round(coalesce(sum(amount), 0), 0) as value
from
  crm.opportunities
where
  stage not in ('closed_won', 'closed_lost')
group by
  stage;

revoke all on crm.deals_by_stage_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.deals_by_stage_pie to "x-admin",
  "manager",
  "rep";

-- Bar: pipeline and bookings per rep
create or replace view crm.pipeline_by_rep_bar
with
  (security_invoker = true) as
select
  r.name as label,
  round(
    coalesce(
      sum(o.amount) filter (
        where
          o.stage not in ('closed_won', 'closed_lost')
      ),
      0
    ),
    0
  ) as open_pipeline,
  round(
    coalesce(
      sum(o.weighted_amount) filter (
        where
          o.stage not in ('closed_won', 'closed_lost')
      ),
      0
    ),
    0
  ) as weighted,
  round(
    coalesce(
      sum(o.amount) filter (
        where
          o.stage = 'closed_won'
      ),
      0
    ),
    0
  ) as booked
from
  crm.sales_reps r
  left join crm.opportunities o on o.owner_id = r.id
where
  r.status = 'active'
group by
  r.id,
  r.name
order by
  open_pipeline desc;

revoke all on crm.pipeline_by_rep_bar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.pipeline_by_rep_bar to "x-admin",
  "manager";

-- Line: deals created against deals won over the last 14 days
create or replace view crm.deal_flow_line
with
  (security_invoker = true) as
select
  to_char(d.day, 'Mon DD') as date,
  (
    select
      count(*)
    from
      crm.opportunities o
    where
      o.opened_on = d.day
  ) as opened,
  (
    select
      count(*)
    from
      crm.opportunities o
    where
      o.actual_close_on = d.day
      and o.stage = 'closed_won'
  ) as won,
  (
    select
      count(*)
    from
      crm.opportunities o
    where
      o.actual_close_on = d.day
      and o.stage = 'closed_lost'
  ) as lost
from
  generate_series(current_date - 13, current_date, interval '1 day') as d (day)
order by
  d.day;

revoke all on crm.deal_flow_line
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.deal_flow_line to "x-admin",
  "manager",
  "rep";

-- Area: how the open pipeline has been composed, week by week
create or replace view crm.pipeline_composition_area
with
  (security_invoker = true) as
select
  to_char(date_trunc('week', o.expected_close_on), 'Mon DD') as date,
  round(
    coalesce(
      sum(o.amount) filter (
        where
          o.forecast_category = 'pipeline'
      ),
      0
    ),
    0
  ) as pipeline,
  round(
    coalesce(
      sum(o.amount) filter (
        where
          o.forecast_category = 'best_case'
      ),
      0
    ),
    0
  ) as best_case,
  round(
    coalesce(
      sum(o.amount) filter (
        where
          o.forecast_category = 'commit'
      ),
      0
    ),
    0
  ) as commit_amount
from
  crm.opportunities o
where
  o.stage not in ('closed_won', 'closed_lost')
  and o.expected_close_on between current_date - 28 and current_date  + 84
group by
  date_trunc('week', o.expected_close_on)
order by
  date_trunc('week', o.expected_close_on);

revoke all on crm.pipeline_composition_area
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.pipeline_composition_area to "x-admin",
  "manager";

-- Radar: the shape of each rep's book
create or replace view crm.rep_scorecard_radar
with
  (security_invoker = true) as
select
  r.name as metric,
  count(o.id) filter (
    where
      o.stage not in ('closed_won', 'closed_lost')
  ) as open_deals,
  count(o.id) filter (
    where
      o.stage = 'closed_won'
  ) as won_deals,
  (
    select
      count(*)
    from
      crm.activities act
    where
      act.owner_id = r.id
  ) as activities
from
  crm.sales_reps r
  left join crm.opportunities o on o.owner_id = r.id
where
  r.status = 'active'
group by
  r.id,
  r.name
order by
  open_deals desc;

revoke all on crm.rep_scorecard_radar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.rep_scorecard_radar to "x-admin",
  "manager";

-- Pie: where leads come from — shown on the leads resource page
create or replace view crm.leads_by_source_pie
with
  (security_invoker = true) as
select
  source::text as label,
  count(*) as value
from
  crm.leads
group by
  source;

revoke all on crm.leads_by_source_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.leads_by_source_pie to "x-admin",
  "manager",
  "rep";

-- Pie: the book by segment — shown on the accounts resource page
create or replace view crm.accounts_by_tier_pie
with
  (security_invoker = true) as
select
  tier::text as label,
  count(*) as value
from
  crm.accounts
group by
  tier;

revoke all on crm.accounts_by_tier_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.accounts_by_tier_pie to "x-admin",
  "manager",
  "rep";

-- Bar: interaction mix — shown on the activities resource page
create or replace view crm.activities_by_type_bar
with
  (security_invoker = true) as
select
  activity_type::text as label,
  count(*) as activities,
  count(*) filter (
    where
      direction = 'inbound'
  ) as inbound,
  count(*) filter (
    where
      outcome = 'connected'
  ) as connected
from
  crm.activities
group by
  activity_type
order by
  activities desc;

revoke all on crm.activities_by_type_bar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.activities_by_type_bar to "x-admin",
  "manager",
  "rep";

-- Line: lead flow over the last 14 days — shown on the leads page
create or replace view crm.lead_flow_line
with
  (security_invoker = true) as
select
  to_char(d.day, 'Mon DD') as date,
  (
    select
      count(*)
    from
      crm.leads l
    where
      l.created_at::date = d.day
  ) as created,
  (
    select
      count(*)
    from
      crm.leads l
    where
      l.converted_at::date = d.day
  ) as converted
from
  generate_series(current_date - 13, current_date, interval '1 day') as d (day)
order by
  d.day;

revoke all on crm.lead_flow_line
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on crm.lead_flow_line to "x-admin",
  "manager",
  "rep";

comment on view crm.deals_by_stage_pie is '{"type": "chart", "name": "Pipeline By Stage", "description": "Open pipeline value grouped by stage", "chart_type": "pie", "format": "currency"}';

comment on view crm.pipeline_by_rep_bar is '{"type": "chart", "name": "Pipeline By Rep", "description": "Open, weighted and booked revenue per rep", "chart_type": "bar", "format": "currency"}';

comment on view crm.deal_flow_line is '{"type": "chart", "name": "Deal Flow", "description": "Deals opened, won and lost over 14 days", "chart_type": "line"}';

comment on view crm.pipeline_composition_area is '{"type": "chart", "name": "Forecast Composition", "description": "Weekly pipeline, best case and commit by close week", "chart_type": "area", "format": "currency"}';

comment on view crm.rep_scorecard_radar is '{"type": "chart", "name": "Rep Scorecard", "description": "Open deals, wins and activity per rep", "chart_type": "radar"}';

comment on view crm.leads_by_source_pie is '{"type": "chart", "name": "Leads By Source", "description": "Where demand comes from", "chart_type": "pie", "resource": "leads"}';

comment on view crm.accounts_by_tier_pie is '{"type": "chart", "name": "Accounts By Tier", "description": "How the book splits across segments", "chart_type": "pie", "resource": "accounts"}';

comment on view crm.activities_by_type_bar is '{"type": "chart", "name": "Interaction Mix", "description": "Activity volume, inbound share and connect rate by channel", "chart_type": "bar", "resource": "activities"}';

comment on view crm.lead_flow_line is '{"type": "chart", "name": "Lead Flow", "description": "Leads created and converted over 14 days", "chart_type": "line", "resource": "leads"}';

----------------------------------------------------------------
-- Audit triggers (INSERT/UPDATE fire AFTER, DELETE must fire BEFORE
-- so the row still exists when it is captured)
--
-- crm.opportunity_events is left out: it is already an audit trail.
----------------------------------------------------------------
create trigger audit_crm_territories_insert
after insert on crm.territories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_territories_update
after update on crm.territories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_territories_delete
before delete on crm.territories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_sales_reps_insert
after insert on crm.sales_reps for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_sales_reps_update
after update on crm.sales_reps for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_sales_reps_delete
before delete on crm.sales_reps for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_rep_compensation_insert
after insert on crm.rep_compensation for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_rep_compensation_update
after update on crm.rep_compensation for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_rep_compensation_delete
before delete on crm.rep_compensation for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_accounts_insert
after insert on crm.accounts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_accounts_update
after update on crm.accounts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_accounts_delete
before delete on crm.accounts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_contacts_insert
after insert on crm.contacts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_contacts_update
after update on crm.contacts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_contacts_delete
before delete on crm.contacts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_campaigns_insert
after insert on crm.campaigns for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_campaigns_update
after update on crm.campaigns for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_campaigns_delete
before delete on crm.campaigns for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_leads_insert
after insert on crm.leads for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_leads_update
after update on crm.leads for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_leads_delete
before delete on crm.leads for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_pipeline_stages_insert
after insert on crm.pipeline_stages for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_pipeline_stages_update
after update on crm.pipeline_stages for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_pipeline_stages_delete
before delete on crm.pipeline_stages for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_products_insert
after insert on crm.products for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_products_update
after update on crm.products for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_products_delete
before delete on crm.products for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_opportunities_insert
after insert on crm.opportunities for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_opportunities_update
after update on crm.opportunities for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_opportunities_delete
before delete on crm.opportunities for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_line_items_insert
after insert on crm.opportunity_line_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_line_items_update
after update on crm.opportunity_line_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_line_items_delete
before delete on crm.opportunity_line_items for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_opportunity_contacts_insert
after insert on crm.opportunity_contacts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_opportunity_contacts_delete
before delete on crm.opportunity_contacts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_quotes_insert
after insert on crm.quotes for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_quotes_update
after update on crm.quotes for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_quotes_delete
before delete on crm.quotes for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_activities_insert
after insert on crm.activities for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_activities_update
after update on crm.activities for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_activities_delete
before delete on crm.activities for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_tasks_insert
after insert on crm.tasks for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_tasks_update
after update on crm.tasks for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_tasks_delete
before delete on crm.tasks for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_crm_settings_insert
after insert on crm.crm_settings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_crm_settings_update
after update on crm.crm_settings for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
--
-- supasheet.create_notification() is service_role-only, so every
-- caller below is a `security definer set search_path = ''` trigger.
--
-- "Sales leadership" is resolved as everyone who can update
-- crm.territories: that grant is held by "manager" and "x-admin" but
-- not by "rep", which makes it a precise stand-in for the management
-- line without a second source of truth to keep in sync.
----------------------------------------------------------------
create or replace function crm.trg_opportunities_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_owner_user uuid;
    v_account    text;
    v_type       text;
    v_title      text;
    v_body       text;
begin
    if new.owner_id is not null then
        select user_id into v_owner_user from crm.sales_reps where id = new.owner_id;
    end if;

    select name into v_account from crm.accounts where id = new.account_id;

    if tg_op = 'INSERT' then
        v_type  := 'crm_opportunity_created';
        v_title := 'New opportunity';
        v_body  := new.reference || ': ' || new.name || ' (' || coalesce(v_account, 'no account') || ')';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('crm', 'territories', 'update') || array[v_owner_user],
            null
        );
    elsif new.stage = 'closed_won' and old.stage <> 'closed_won' then
        v_type  := 'crm_opportunity_won';
        v_title := 'Deal won';
        v_body  := coalesce(v_account, 'A deal') || ' — ' || new.name || ' closed at ' || round(new.amount, 0) || ' ' || new.currency || '.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('crm', 'territories', 'update') || array[v_owner_user],
            null
        );
    elsif new.stage = 'closed_lost' and old.stage <> 'closed_lost' then
        v_type  := 'crm_opportunity_lost';
        v_title := 'Deal lost';
        v_body  := new.reference || ': ' || coalesce(new.closed_reason, 'no reason recorded');
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('crm', 'territories', 'update') || array[v_owner_user],
            null
        );
    elsif new.owner_id is distinct from old.owner_id then
        v_type  := 'crm_opportunity_assigned';
        v_title := 'Deal assigned to you';
        v_body  := new.reference || ': ' || new.name;
        v_recipients := array_remove(array[v_owner_user], null);
    elsif new.stage is distinct from old.stage then
        v_type  := 'crm_opportunity_stage_changed';
        v_title := 'Deal moved stage';
        v_body  := new.reference || ' is now at ' || new.stage::text || '.';
        v_recipients := array_remove(array[v_owner_user], null);
    else
        return new;
    end if;

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'opportunity_id', new.id,
            'reference',      new.reference,
            'stage',          new.stage,
            'amount',         new.amount,
            'account_id',     new.account_id
        ),
        '/crm/resource/opportunities/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists opportunities_notify on crm.opportunities;

create trigger opportunities_notify
after insert or update of stage,
owner_id on crm.opportunities for each row
execute function crm.trg_opportunities_notify ();

-- Leads: tell a rep the moment something lands in their queue.
create or replace function crm.trg_leads_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_owner_user uuid;
begin
    if new.owner_id is null then
        return new;
    end if;

    if tg_op = 'UPDATE' and new.owner_id is not distinct from old.owner_id then
        return new;
    end if;

    select user_id into v_owner_user from crm.sales_reps where id = new.owner_id;
    v_recipients := array_remove(array[v_owner_user], null);

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'crm_lead_assigned',
        'New lead assigned to you',
        new.name || ' at ' || new.company || ' (' || new.source::text || ')',
        v_recipients,
        jsonb_build_object(
            'lead_id',   new.id,
            'reference', new.reference,
            'rating',    new.rating,
            'score',     new.score
        ),
        '/crm/resource/leads/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists leads_notify on crm.leads;

create trigger leads_notify
after insert or update of owner_id on crm.leads for each row
execute function crm.trg_leads_notify ();

-- Tasks: the assignee hears about it once, when it lands.
create or replace function crm.trg_tasks_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_owner_user uuid;
begin
    if new.owner_id is null or new.status in ('completed', 'cancelled') then
        return new;
    end if;

    if tg_op = 'UPDATE' and new.owner_id is not distinct from old.owner_id then
        return new;
    end if;

    select user_id into v_owner_user from crm.sales_reps where id = new.owner_id;
    v_recipients := array_remove(array[v_owner_user], null);

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'crm_task_assigned',
        'Task assigned to you',
        new.subject || coalesce(' — due ' || to_char(new.due_on, 'Mon DD'), ''),
        v_recipients,
        jsonb_build_object('task_id', new.id, 'priority', new.priority, 'due_on', new.due_on),
        '/crm/resource/tasks/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists tasks_notify on crm.tasks;

create trigger tasks_notify
after insert or update of owner_id on crm.tasks for each row
execute function crm.trg_tasks_notify ();

-- Quotes: a decision on a quote is news for the whole management line.
create or replace function crm.trg_quotes_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_owner_user uuid;
    v_type       text;
    v_title      text;
begin
    if new.status = old.status or new.status not in ('accepted', 'declined') then
        return new;
    end if;

    if new.owner_id is not null then
        select user_id into v_owner_user from crm.sales_reps where id = new.owner_id;
    end if;

    if new.status = 'accepted' then
        v_type  := 'crm_quote_accepted';
        v_title := 'Quote accepted';
    else
        v_type  := 'crm_quote_declined';
        v_title := 'Quote declined';
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('crm', 'territories', 'update') || array[v_owner_user],
        null
    );

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title,
        new.quote_number || ' — ' || round(new.total, 0) || ' ' || new.currency
          || coalesce(' (' || new.declined_reason || ')', ''),
        v_recipients,
        jsonb_build_object('quote_id', new.id, 'status', new.status, 'total', new.total),
        '/crm/resource/quotes/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists quotes_notify on crm.quotes;

create trigger quotes_notify
after update of status on crm.quotes for each row
execute function crm.trg_quotes_notify ();

-- Comments: pair the per-record comment system with notifications.
-- The trigger lives on the CENTRAL supasheet.comments table and
-- filters down to this schema's tables.
create or replace function crm.trg_crm_comments_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.schema_name <> 'crm' or new.table_name not in ('accounts', 'opportunities', 'leads') then
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('crm', new.table_name, 'update'),
        new.created_by
    );

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'crm_comment_added',
        'New comment on ' || new.table_name,
        left(new.content, 140),
        v_recipients,
        jsonb_build_object('record_id', new.record_id, 'table_name', new.table_name),
        '/crm/resource/' || new.table_name || '/' || new.record_id::text || '/comment'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists crm_comments_notify on supasheet.comments;

create trigger crm_comments_notify
after insert on supasheet.comments for each row
execute function crm.trg_crm_comments_notify ();

----------------------------------------------------------------
-- Refresh the metadata catalog (materialized views — NOT automatic)
----------------------------------------------------------------
select
  supasheet.refresh_metadata ();
