-- ================================================================
-- Supasheet Example — "HR" (people operations)
-- ================================================================
-- A production-shaped HR system: offices and a department tree, a
-- levelling framework and job catalogue, the employee record with an
-- org chart, compensation and documents, leave with balances and
-- approvals, timesheets, performance cycles with reviews and goals,
-- training, recruitment from opening to offer, and onboarding.
--
-- Demo data lives in supabase/examples/h_seed.sql — apply this file
-- first, then that one.
--
-- Feature coverage (this module deliberately picks up the three
-- Supasheet features the desk/blog/crm/store examples do not use):
--   - A CUSTOM STORAGE BUCKET (`hr-documents`, private) with
--     storage.objects policies driven by table privileges, because
--     contracts and right-to-work scans must not sit in the shared
--     uploads bucket
--   - supasheet.configs entries, the key-value settings the app
--     shell reads
--   - A plain VIEW and a MATERIALIZED VIEW surfaced as browsable
--     read-only RESOURCES (org chart, team directory, headcount
--     snapshot) rather than only as reports
--
-- Everything the other examples cover is here too:
--   - Native-role RBAC with two custom roles ("people_manager",
--     "recruiter") alongside "x-admin"/"user"
--   - RLS built on the org chart itself: a RECURSIVE reports-to walk
--     means a line manager sees their whole sub-tree and nobody
--     else's, resolved through STABLE SECURITY DEFINER helpers
--   - The "user" role is THE EMPLOYEE: their own record, leave,
--     timesheets, goals and reviews, and the public directory
--   - Column-level GRANT so an employee maintains their own contact
--     details but not their job title or salary band
--   - Compensation and documents in 1:1 / restricted tables rather
--     than behind column-level SELECT grants
--   - All column data types: URL, TEL, EMAIL, RICH_TEXT, COLOR,
--     PERCENTAGE, DURATION, RATING, file, AVATAR, enums, arrays
--   - All six view layouts: kanban (leave, candidates, reviews),
--     calendar (leave, holidays, interviews), gallery (directory,
--     courses), list (levels, positions, balances), tree (department
--     hierarchy, org chart), gantt (performance cycles, openings)
--   - Field sections, filter presets, quick_create, conditional
--     behavior, lookup fill + filter, resource links, a default
--     query.filter, and a fields.metadata override
--   - Singleton (hr_settings), 1:1 extension (employee_compensation),
--     junction with inline form (training_enrollments)
--   - Rollups: leave taken against balance, timesheet hours against
--     the week, goal progress against the review, headcount against
--     the department
--   - Guards that raise: no leave without balance, no overlapping
--     leave, no self-approval, no negative timesheet day, no review
--     outside its cycle, no offer above the band
--   - Detail tabs + timelines (employee_events)
--   - Row actions, four custom form shapes, templates, reports with
--     a Handlebars print template, every widget and chart contract,
--     notifications, audit logging and per-resource comments
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260803000000_hr.sql \
--     -f supabase/examples/h_seed.sql
--
-- Requires the base Supasheet migrations (supabase/migrations/*) to
-- already be applied. Also add "hr" to config.toml's `api.schemas`
-- and `api.extra_search_path` so PostgREST exposes it, then restart
-- Supabase.
--
-- Not idempotent: `create schema` / `create type` / `create table`
-- fail on a second run. Re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists hr;

-------------------------------------------------------------------
-- Roles
--
--   x-admin         people operations: everything, including
--                   compensation and documents
--   people_manager  line manager: their own reporting tree — approve
--                   leave, run reviews, see team timesheets; never
--                   sees pay outside their own record
--   recruiter       talent: openings, candidates, interviews and
--                   offers; no access to existing employee data
--                   beyond the directory
--   user            THE EMPLOYEE: their own record, leave,
--                   timesheets, goals and reviews, plus the company
--                   directory and the holiday calendar
--
-- Assign a user to a custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "people_manager"}'
--   where email = 'manager@example.com';
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

  if not exists (select 1 from pg_roles where rolname = 'people_manager') then
    create role "people_manager" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'recruiter') then
    create role "recruiter" nologin;
  end if;
end;
$$;

-- Let PostgREST SET ROLE into each role...
grant "user",
"admin",
"people_manager",
"recruiter" to authenticator;

-- ...and let `to authenticated` policies still apply to them.
grant authenticated to "user",
"admin",
"people_manager",
"recruiter";

-- Schema usage is granted per native role, never to `authenticated`.
grant usage on schema hr to "x-admin",
"people_manager",
"recruiter",
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

create type hr.employment_status as enum(
  'applicant',
  'onboarding',
  'active',
  'on_leave',
  'notice_period',
  'terminated'
);

create type hr.employment_type as enum(
  'full_time',
  'part_time',
  'contractor',
  'intern',
  'apprentice'
);

create type hr.work_mode as enum('onsite', 'hybrid', 'remote');

create type hr.termination_reason as enum(
  'resignation',
  'end_of_contract',
  'redundancy',
  'dismissal',
  'retirement',
  'mutual_agreement'
);

create type hr.job_family as enum(
  'engineering',
  'product',
  'design',
  'sales',
  'marketing',
  'operations',
  'finance',
  'people',
  'support'
);

create type hr.job_change_type as enum(
  'hire',
  'promotion',
  'lateral_move',
  'salary_change',
  'manager_change',
  'location_change',
  'contract_change',
  'termination'
);

create type hr.employee_event_type as enum(
  'hired',
  'onboarded',
  'promoted',
  'transferred',
  'leave_taken',
  'review_completed',
  'goal_closed',
  'training_completed',
  'terminated',
  'record_updated'
);

create type hr.leave_unit as enum('day', 'hour');

create type hr.leave_status as enum(
  'draft',
  'pending',
  'approved',
  'rejected',
  'cancelled',
  'taken'
);

create type hr.timesheet_status as enum('draft', 'submitted', 'approved', 'rejected');

create type hr.review_cycle_status as enum(
  'planned',
  'self_assessment',
  'manager_review',
  'calibration',
  'closed'
);

create type hr.review_status as enum(
  'not_started',
  'self_assessment',
  'manager_review',
  'shared',
  'acknowledged'
);

create type hr.performance_rating as enum(
  'below',
  'developing',
  'meets',
  'exceeds',
  'outstanding'
);

create type hr.goal_status as enum(
  'draft',
  'active',
  'at_risk',
  'achieved',
  'missed',
  'cancelled'
);

create type hr.course_format as enum(
  'elearning',
  'workshop',
  'conference',
  'certification',
  'mentoring'
);

create type hr.enrollment_status as enum(
  'enrolled',
  'in_progress',
  'completed',
  'failed',
  'withdrawn'
);

create type hr.opening_status as enum('draft', 'open', 'on_hold', 'filled', 'cancelled');

create type hr.candidate_stage as enum(
  'applied',
  'screening',
  'interviewing',
  'offer',
  'hired',
  'rejected',
  'withdrawn'
);

create type hr.interview_kind as enum(
  'phone_screen',
  'technical',
  'system_design',
  'culture',
  'panel',
  'final'
);

create type hr.interview_outcome as enum('strong_yes', 'yes', 'mixed', 'no', 'strong_no');

create type hr.document_kind as enum(
  'contract',
  'offer_letter',
  'identification',
  'right_to_work',
  'certification',
  'payslip',
  'performance',
  'other'
);

create type hr.onboarding_status as enum(
  'pending',
  'in_progress',
  'done',
  'blocked',
  'skipped'
);

commit;

----------------------------------------------------------------
-- Users replica view
----------------------------------------------------------------
create or replace view hr.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on hr.users
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.users to "x-admin",
  "people_manager",
  "recruiter",
  "user";

----------------------------------------------------------------
-- App configuration
--
-- supasheet.configs is the key-value table the app shell reads.
-- Writes are revoked from every client role by design: values change
-- by migration, which is exactly what this is.
----------------------------------------------------------------
insert into
  supasheet.configs (key, value, description, is_public)
values
  (
    'hr.leave_year_start_month',
    '1',
    'Month the leave year rolls over (1 = January)',
    false
  ),
  (
    'hr.probation_months',
    '6',
    'Default probation length for a new hire',
    false
  ),
  (
    'hr.working_week',
    '{"days": 5, "hours_per_day": 8, "timesheets_required": true}',
    'Standard working pattern used by leave and timesheet maths',
    false
  ),
  (
    'hr.features',
    '{"self_service_leave": true, "peer_reviews": false, "referral_bonus": true}',
    'People-module feature flags',
    false
  )
on conflict (key) do update
set
  value = excluded.value,
  description = excluded.description,
  is_public = excluded.is_public;

----------------------------------------------------------------
-- Locations
----------------------------------------------------------------
create table hr.locations (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(160) not null,
  address_line_1 varchar(200),
  city varchar(120),
  region varchar(120),
  postal_code varchar(40),
  country varchar(120) not null,
  timezone varchar(100) not null default 'UTC',
  working_hours varchar(60) not null default '09:00-17:00',
  is_headquarters boolean not null default false,
  is_active boolean not null default true,
  capacity integer,
  headcount integer not null default 0,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint locations_capacity_non_negative check (
    capacity is null
    or capacity >= 0
  )
);

comment on table hr.locations is '{
    "icon": "MapPin",
    "description": "Offices and the working patterns attached to them.",
    "collapsible_group": "Organisation",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["country", "is_headquarters"]},
        "tabs": ["employees", "holidays", "job_openings"]
    },
    "views": [
        {
            "id": "list",
            "name": "Offices",
            "type": "list",
            "title": "name",
            "description": "city",
            "field_1": "country",
            "field_2": "headcount"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "city", "country"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "is_headquarters", "is_active", "color"]},
            {"id": "address", "title": "Address", "fields": ["address_line_1", "city", "region", "postal_code", "country"]},
            {"id": "working", "title": "Working pattern", "fields": ["timezone", "working_hours", "capacity"]},
            {"id": "occupancy", "title": "Occupancy", "fields": {"read": ["headcount"]}}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}]
    }
}';

comment on column hr.locations.headcount is '{"name": "Headcount", "aggregate": "sum"}';

revoke all on table hr.locations
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
delete on table hr.locations to "x-admin";

grant
select
  on table hr.locations to "people_manager",
  "recruiter",
  "user";

create index idx_hr_locations_is_active on hr.locations (is_active);

alter table hr.locations enable row level security;

create policy locations_select on hr.locations for
select
  to authenticated using (true);

create policy locations_insert on hr.locations for insert to authenticated
with
  check (true);

create policy locations_update on hr.locations
for update
  to authenticated using (true)
with
  check (true);

create policy locations_delete on hr.locations for delete to authenticated using (true);

----------------------------------------------------------------
-- Departments (self-referencing; head_id lands after employees)
----------------------------------------------------------------
create table hr.departments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  parent_id uuid references hr.departments (id) on delete set null,
  code varchar(20) not null unique,
  name varchar(160) not null,
  description text,
  cost_centre varchar(40),
  annual_budget numeric(14, 2) not null default 0,
  headcount integer not null default 0,
  open_positions integer not null default 0,
  is_active boolean not null default true,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint departments_not_own_parent check (id <> parent_id),
  constraint departments_budget_non_negative check (annual_budget >= 0)
);

comment on table hr.departments is '{
    "icon": "Network",
    "description": "The department tree, its budget and its headcount.",
    "collapsible_group": "Organisation",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["code", "is_active"]},
        "tabs": ["employees", "positions", "departments", "job_openings"]
    },
    "views": [
        {
            "id": "tree",
            "name": "Department Tree",
            "type": "tree",
            "parent": "parent_id",
            "title": "name",
            "secondary": "code"
        },
        {
            "id": "list",
            "name": "All Departments",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "headcount",
            "field_2": "annual_budget"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "hiring", "name": "Hiring", "filters": [{"id": "open_positions", "value": "0", "operator": "gt"}]}
    ],
    "links": [
        {"id": "headcount", "name": "Headcount Report", "url": "/hr/report/headcount_report", "icon": "Users", "description": "Headcount, cost and attrition by department"}
    ],
    "fields": {
        "quick_create": ["code", "name", "parent_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "parent_id"]},
            {"id": "leadership", "title": "Leadership", "fields": ["head_id", "cost_centre", "is_active", "color"]},
            {"id": "budget", "title": "Budget", "fields": ["annual_budget"]},
            {"id": "size", "title": "Size", "fields": {"read": ["headcount", "open_positions"]}}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [{"table": "departments", "on": "parent_id", "alias": "parent", "columns": ["name", "code"]}]
    }
}';

comment on column hr.departments.annual_budget is '{"name": "Budget", "aggregate": "sum"}';

comment on column hr.departments.headcount is '{"name": "Headcount", "aggregate": "sum"}';

revoke all on table hr.departments
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
delete on table hr.departments to "x-admin";

grant
select
  on table hr.departments to "people_manager",
  "recruiter",
  "user";

create index idx_hr_departments_parent_id on hr.departments (parent_id);

alter table hr.departments enable row level security;

create policy departments_select on hr.departments for
select
  to authenticated using (true);

create policy departments_insert on hr.departments for insert to authenticated
with
  check (true);

create policy departments_update on hr.departments
for update
  to authenticated using (true)
with
  check (true);

create policy departments_delete on hr.departments for delete to authenticated using (true);

----------------------------------------------------------------
-- Job levels (the levelling framework the salary bands hang off)
----------------------------------------------------------------
create table hr.job_levels (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(10) not null unique,
  name varchar(120) not null,
  description text,
  rank integer not null,
  band_min numeric(12, 2) not null default 0,
  band_mid numeric(12, 2) not null default 0,
  band_max numeric(12, 2) not null default 0,
  is_management boolean not null default false,
  expectations supasheet.RICH_TEXT,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint job_levels_band_ordered check (
    band_min <= band_mid
    and band_mid <= band_max
  ),
  constraint job_levels_rank_positive check (rank > 0)
);

comment on table hr.job_levels is '{
    "icon": "Layers",
    "name": "Job Levels",
    "description": "The levelling framework: one row per level, with its salary band.",
    "collapsible_group": "Organisation",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["code", "is_management"]},
        "tabs": ["positions", "employees"]
    },
    "views": [
        {
            "id": "list",
            "name": "Framework",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "code",
            "field_2": "band_mid"
        }
    ],
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "rank", "description", "is_management", "color"]},
            {"id": "band", "title": "Salary band", "fields": ["band_min", "band_mid", "band_max"]},
            {"id": "expectations", "title": "Expectations", "collapsible": true, "fields": ["expectations"]}
        ]
    },
    "query": {
        "sort": [{"id": "rank", "desc": false}]
    }
}';

comment on column hr.job_levels.band_mid is '{"name": "Band Midpoint", "aggregate": "avg"}';

revoke all on table hr.job_levels
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
delete on table hr.job_levels to "x-admin";

grant
select
  on table hr.job_levels to "people_manager",
  "recruiter";

create index idx_hr_job_levels_rank on hr.job_levels (rank);

alter table hr.job_levels enable row level security;

create policy job_levels_select on hr.job_levels for
select
  to authenticated using (true);

create policy job_levels_insert on hr.job_levels for insert to authenticated
with
  check (true);

create policy job_levels_update on hr.job_levels
for update
  to authenticated using (true)
with
  check (true);

create policy job_levels_delete on hr.job_levels for delete to authenticated using (true);

----------------------------------------------------------------
-- Positions (the job catalogue employees and openings both point at)
----------------------------------------------------------------
create table hr.positions (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(30) not null unique,
  title varchar(160) not null,
  job_family hr.job_family not null default 'operations',
  level_id uuid references hr.job_levels (id) on delete set null,
  department_id uuid references hr.departments (id) on delete set null,
  summary text,
  responsibilities supasheet.RICH_TEXT,
  is_active boolean not null default true,
  filled_count integer not null default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hr.positions.job_family is '{
    "progress": false,
    "values": {
        "engineering": {"variant": "info", "icon": "Code2"},
        "product": {"variant": "default", "icon": "Lightbulb"},
        "design": {"variant": "secondary", "icon": "Palette"},
        "sales": {"variant": "success", "icon": "Handshake"},
        "marketing": {"variant": "warning", "icon": "Megaphone"},
        "operations": {"variant": "secondary", "icon": "Settings"},
        "finance": {"variant": "default", "icon": "Calculator"},
        "people": {"variant": "info", "icon": "Users"},
        "support": {"variant": "success", "icon": "LifeBuoy"}
    }
}';

comment on table hr.positions is '{
    "icon": "BriefcaseBusiness",
    "description": "The job catalogue: every role that exists, whether or not it is filled.",
    "collapsible_group": "Organisation",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "title", "badges": ["job_family", "is_active"]},
        "tabs": ["employees", "job_openings"]
    },
    "views": [
        {
            "id": "list",
            "name": "Catalogue",
            "type": "list",
            "title": "title",
            "description": "summary",
            "field_1": "job_family",
            "field_2": "filled_count"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "engineering", "name": "Engineering", "filters": [{"id": "job_family", "value": "engineering", "operator": "eq"}]},
        {"id": "vacant", "name": "Nobody In Seat", "filters": [{"id": "filled_count", "value": "0", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["code", "title", "job_family", "department_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "title", "job_family", "is_active"]},
            {"id": "placement", "title": "Placement", "fields": ["department_id", "level_id"]},
            {"id": "detail", "title": "Detail", "fields": ["summary", "responsibilities"]},
            {"id": "occupancy", "title": "Occupancy", "fields": {"read": ["filled_count"]}}
        ],
        "lookups": {
            "level_id": {"filter": [{"source_column": "job_family", "target_column": "job_family"}]}
        }
    },
    "query": {
        "sort": [{"id": "title", "desc": false}],
        "join": [
            {"table": "departments", "on": "department_id", "columns": ["name", "code"]},
            {"table": "job_levels", "on": "level_id", "columns": ["code", "name", "band_mid"]}
        ]
    }
}';

revoke all on table hr.positions
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
delete on table hr.positions to "x-admin";

grant
select
  on table hr.positions to "people_manager",
  "recruiter",
  "user";

create index idx_hr_positions_department_id on hr.positions (department_id);

create index idx_hr_positions_level_id on hr.positions (level_id);

create index idx_hr_positions_job_family on hr.positions (job_family);

alter table hr.positions enable row level security;

create policy positions_select on hr.positions for
select
  to authenticated using (true);

create policy positions_insert on hr.positions for insert to authenticated
with
  check (true);

create policy positions_update on hr.positions
for update
  to authenticated using (true)
with
  check (true);

create policy positions_delete on hr.positions for delete to authenticated using (true);

----------------------------------------------------------------
-- Employees (the core record and the org chart)
----------------------------------------------------------------
create sequence if not exists hr.employee_number_seq;

create table hr.employees (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_number varchar(20) not null unique default (
    'EMP-' || lpad(nextval('hr.employee_number_seq')::text, 5, '0')
  ),
  user_id uuid references supasheet.users (id) on delete set null,
  manager_id uuid references hr.employees (id) on delete set null,
  department_id uuid references hr.departments (id) on delete set null,
  location_id uuid references hr.locations (id) on delete set null,
  position_id uuid references hr.positions (id) on delete set null,
  level_id uuid references hr.job_levels (id) on delete set null,
  first_name varchar(120) not null,
  last_name varchar(120) not null,
  preferred_name varchar(120),
  name varchar(255),
  avatar supasheet.AVATAR,
  work_email supasheet.EMAIL not null,
  personal_email supasheet.EMAIL,
  phone supasheet.TEL,
  linkedin_url supasheet.URL,
  employment_status hr.employment_status not null default 'onboarding',
  employment_type hr.employment_type not null default 'full_time',
  work_mode hr.work_mode not null default 'hybrid',
  fte supasheet.PERCENTAGE not null default 100,
  weekly_hours numeric(5, 2) not null default 40,
  hire_date date not null default current_date,
  probation_end_date date,
  notice_given_on date,
  termination_date date,
  termination_reason hr.termination_reason,
  date_of_birth date,
  nationality varchar(120),
  emergency_contact_name varchar(160),
  emergency_contact_phone supasheet.TEL,
  emergency_contact_relationship varchar(60),
  bio supasheet.RICH_TEXT,
  skills varchar(500) [],
  tenure_months integer not null default 0,
  direct_report_count integer not null default 0,
  leave_days_taken numeric(6, 2) not null default 0,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint employees_not_own_manager check (id <> manager_id),
  constraint employees_fte_range check (
    fte > 0
    and fte <= 100
  ),
  constraint employees_termination_after_hire check (
    termination_date is null
    or termination_date >= hire_date
  ),
  constraint employees_termination_has_reason check (
    termination_date is null
    or termination_reason is not null
  )
);

comment on column hr.employees.employment_status is '{
    "progress": true,
    "values": {
        "applicant": {"variant": "secondary", "icon": "UserSearch"},
        "onboarding": {"variant": "info", "icon": "UserPlus"},
        "active": {"variant": "success", "icon": "UserCheck"},
        "on_leave": {"variant": "warning", "icon": "Plane"},
        "notice_period": {"variant": "warning", "icon": "Clock"},
        "terminated": {"variant": "destructive", "icon": "UserMinus"}
    }
}';

comment on column hr.employees.employment_type is '{
    "progress": false,
    "values": {
        "full_time": {"variant": "success", "icon": "Briefcase"},
        "part_time": {"variant": "info", "icon": "Clock"},
        "contractor": {"variant": "warning", "icon": "FileSignature"},
        "intern": {"variant": "secondary", "icon": "GraduationCap"},
        "apprentice": {"variant": "secondary", "icon": "Hammer"}
    }
}';

comment on column hr.employees.work_mode is '{
    "progress": false,
    "icon_only": true,
    "values": {
        "onsite": {"variant": "default", "icon": "Building2"},
        "hybrid": {"variant": "info", "icon": "Shuffle"},
        "remote": {"variant": "success", "icon": "House"}
    }
}';

comment on table hr.employees is '{
    "icon": "Users",
    "description": "Everyone who works here, and who they report to.",
    "collapsible_group": "People",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["employment_status", "employment_type", "work_mode"]},
        "tabs": ["leave_requests", "timesheet_entries", "goals", "performance_reviews", "training_enrollments", "employee_documents", "job_changes", "employees", "employee_compensation"],
        "timelines": ["employee_events"]
    },
    "views": [
        {
            "id": "tree",
            "name": "Org Chart",
            "type": "tree",
            "parent": "manager_id",
            "title": "name",
            "secondary": "work_email"
        },
        {
            "id": "gallery",
            "name": "Directory",
            "type": "gallery",
            "cover": "avatar",
            "title": "name",
            "description": "work_email",
            "badge": "employment_status"
        },
        {
            "id": "list",
            "name": "All Employees",
            "type": "list",
            "title": "name",
            "description": "work_email",
            "field_1": "employment_status",
            "field_2": "hire_date"
        },
        {
            "id": "kanban",
            "name": "By Status",
            "type": "kanban",
            "group": "employment_status",
            "title": "name",
            "description": "work_email",
            "date": "hire_date",
            "badge": "employment_type"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "employment_status", "value": "active", "operator": "eq"}]},
        {"id": "onboarding", "name": "Onboarding", "filters": [{"id": "employment_status", "value": "onboarding", "operator": "eq"}]},
        {"id": "leavers", "name": "Leavers", "filters": [{"id": "employment_status", "value": ["notice_period", "terminated"], "operator": "in"}]},
        {"id": "managers", "name": "Managers", "filters": [{"id": "direct_report_count", "value": "0", "operator": "gt"}]},
        {"id": "remote", "name": "Remote", "filters": [{"id": "work_mode", "value": "remote", "operator": "eq"}]}
    ],
    "links": [
        {"id": "headcount", "name": "Headcount Report", "url": "/hr/report/headcount_report", "icon": "Users", "description": "Headcount, cost and attrition by department"},
        {"id": "handbook", "name": "Employee Handbook", "url": "https://example.com/handbook", "icon": "BookOpen", "description": "Policies, benefits and the bits nobody reads until they need to"}
    ],
    "fields": {
        "quick_create": ["first_name", "last_name", "work_email", "position_id"],
        "metadata": ["created_at", "updated_at"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["first_name", "last_name", "preferred_name", "avatar", "employee_number"]},
            {"id": "contact", "title": "Contact", "fields": ["work_email", "personal_email", "phone", "linkedin_url"]},
            {"id": "role", "title": "Role", "fields": ["position_id", "level_id", "department_id", "location_id", "manager_id"]},
            {"id": "terms", "title": "Terms", "fields": ["employment_status", "employment_type", "work_mode", "fte", "weekly_hours"]},
            {"id": "dates", "title": "Dates", "fields": ["hire_date", "probation_end_date"]},
            {"id": "leaving", "title": "Leaving", "fields": ["notice_given_on", "termination_date", "termination_reason"]},
            {"id": "personal", "title": "Personal", "collapsible": true, "fields": ["date_of_birth", "nationality", "emergency_contact_name", "emergency_contact_phone", "emergency_contact_relationship"]},
            {"id": "profile", "title": "Profile", "collapsible": true, "fields": ["bio", "skills", "color"]},
            {"id": "derived", "title": "Service", "fields": {"read": ["tenure_months", "direct_report_count", "leave_days_taken"]}}
        ],
        "behavior": {
            "notice_given_on": {"visible": [{"id": "employment_status", "operator": "in", "value": ["notice_period", "terminated"]}]},
            "termination_date": {"visible": [{"id": "employment_status", "operator": "eq", "value": "terminated"}], "required": [{"id": "employment_status", "operator": "eq", "value": "terminated"}]},
            "termination_reason": {"visible": [{"id": "employment_status", "operator": "eq", "value": "terminated"}], "required": [{"id": "employment_status", "operator": "eq", "value": "terminated"}]},
            "probation_end_date": {"visible": [{"id": "employment_status", "operator": "in", "value": ["onboarding", "active"]}]},
            "weekly_hours": {"read_only": [{"id": "employment_type", "operator": "eq", "value": "contractor"}]}
        },
        "lookups": {
            "position_id": {
                "fill": [
                    {"source_column": "level_id", "target_column": "level_id"},
                    {"source_column": "department_id", "target_column": "department_id"}
                ]
            },
            "manager_id": {"filter": [{"source_column": "department_id", "target_column": "department_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "filter": [{"id": "employment_status", "value": "terminated", "operator": "neq"}],
        "join": [
            {"table": "employees", "on": "manager_id", "alias": "manager", "columns": ["name", "work_email"]},
            {"table": "departments", "on": "department_id", "columns": ["name", "code"]},
            {"table": "locations", "on": "location_id", "columns": ["name", "country"]},
            {"table": "positions", "on": "position_id", "columns": ["title", "job_family"]},
            {"table": "job_levels", "on": "level_id", "columns": ["code", "name"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column hr.employees.avatar is '{"accept": "image/*", "max_size": 2097152}';

comment on column hr.employees.fte is '{"name": "FTE", "aggregate": "sum"}';

comment on column hr.employees.tenure_months is '{"name": "Tenure (months)", "aggregate": "avg"}';

comment on column hr.employees.leave_days_taken is '{"name": "Leave Taken", "aggregate": "sum"}';

comment on column hr.employees.employee_number is '{"name": "No.", "icon": "Hash"}';

revoke all on table hr.employees
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
delete on table hr.employees to "x-admin";

grant
select
  on table hr.employees to "people_manager",
  "recruiter",
  "user";

-- An employee keeps their own contact details and profile current;
-- job title, level, manager and dates belong to HR.
grant
update (
  preferred_name,
  avatar,
  personal_email,
  phone,
  linkedin_url,
  emergency_contact_name,
  emergency_contact_phone,
  emergency_contact_relationship,
  bio,
  skills,
  color
) on table hr.employees to "user";

revoke all on sequence hr.employee_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence hr.employee_number_seq to "x-admin";

create unique index idx_hr_employees_work_email_unique on hr.employees (lower(work_email));

create unique index idx_hr_employees_user_unique on hr.employees (user_id)
where
  user_id is not null;

create index idx_hr_employees_manager_id on hr.employees (manager_id);

create index idx_hr_employees_department_id on hr.employees (department_id);

create index idx_hr_employees_location_id on hr.employees (location_id);

create index idx_hr_employees_position_id on hr.employees (position_id);

create index idx_hr_employees_status on hr.employees (employment_status);

create index idx_hr_employees_hire_date on hr.employees (hire_date);

-- The directory query: everyone still here, by name.
create index idx_hr_employees_directory on hr.employees (name)
where
  employment_status <> 'terminated';

----------------------------------------------------------------
-- Identity helpers
--
-- Every self-service and line-manager policy below needs to answer
-- one of three questions: which employee is this login, is the
-- caller HR, and does the caller manage this person. The third walks
-- the org chart recursively, which is why it has to be a SECURITY
-- DEFINER function: the walk reads hr.employees, and hr.employees is
-- itself under a policy that calls this function.
----------------------------------------------------------------
create or replace function hr.current_employee_id () returns uuid language sql stable security definer
set
  search_path = '' as $$
  select id from hr.employees where user_id = auth.uid () limit 1;
$$;

revoke all on function hr.current_employee_id ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.current_employee_id () to "x-admin",
"people_manager",
"recruiter",
"user";

create or replace function hr.is_hr_staff () returns boolean language sql stable
set
  search_path = '' as $$
  select pg_has_role(current_user, 'x-admin', 'member');
$$;

revoke all on function hr.is_hr_staff ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.is_hr_staff () to "x-admin",
"people_manager",
"recruiter",
"user";

-- Does the caller sit anywhere above this person in the org chart?
-- One recursive walk up the manager chain, capped so a bad edge can
-- never spin.
create or replace function hr.manages (p_employee_id uuid) returns boolean language sql stable security definer
set
  search_path = '' as $$
  with recursive chain as (
    select e.id, e.manager_id, 1 as depth
    from hr.employees e
    where e.id = p_employee_id
    union all
    select e.id, e.manager_id, c.depth + 1
    from hr.employees e
    join chain c on e.id = c.manager_id
    where c.depth < 12
  )
  select exists (
    select 1
    from chain c
    where c.manager_id = hr.current_employee_id ()
  );
$$;

revoke all on function hr.manages (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.manages (uuid) to "x-admin",
"people_manager",
"recruiter",
"user";

alter table hr.employees enable row level security;

-- The directory is company-wide, but a leaver drops out of it: only
-- HR, their old manager and the person themselves keep seeing the
-- record.
create policy employees_select on hr.employees for
select
  to authenticated using (
    employment_status <> 'terminated'
    or hr.is_hr_staff ()
    or id = hr.current_employee_id ()
    or hr.manages (id)
  );

create policy employees_insert on hr.employees for insert to authenticated
with
  check (true);

create policy employees_update on hr.employees
for update
  to authenticated using (
    hr.is_hr_staff ()
    or id = hr.current_employee_id ()
  )
with
  check (true);

create policy employees_delete on hr.employees for delete to authenticated using (true);

-- Departments gained a head only after the roster existed.
alter table hr.departments
add column head_id uuid references hr.employees (id) on delete set null;

create index idx_hr_departments_head_id on hr.departments (head_id);

----------------------------------------------------------------
-- Compensation (1:1 extension — x-admin only, never granted to a
-- line manager, a recruiter or the employee themselves)
----------------------------------------------------------------
create table hr.employee_compensation (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_id uuid not null references hr.employees (id) on delete cascade,
  base_salary numeric(12, 2) not null default 0,
  currency varchar(3) not null default 'USD',
  pay_frequency varchar(20) not null default 'monthly',
  bonus_target supasheet.PERCENTAGE not null default 0,
  equity_units integer not null default 0,
  allowance numeric(12, 2) not null default 0,
  compa_ratio supasheet.PERCENTAGE,
  effective_from date not null default current_date,
  next_review_on date,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (employee_id),
  constraint compensation_non_negative check (
    base_salary >= 0
    and allowance >= 0
    and equity_units >= 0
    and bonus_target >= 0
    and bonus_target <= 100
  )
);

comment on table hr.employee_compensation is '{
    "icon": "Banknote",
    "name": "Compensation",
    "description": "Pay, bonus and equity. Visible to people operations only.",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "employee", "title": "Employee", "fields": ["employee_id", "currency", "pay_frequency", "effective_from"]},
            {"id": "pay", "title": "Pay", "fields": ["base_salary", "allowance", "bonus_target", "equity_units"]},
            {"id": "position", "title": "Position in band", "fields": {"read": ["compa_ratio"]}},
            {"id": "review", "title": "Review", "fields": ["next_review_on", "notes"]}
        ]
    },
    "query": {
        "join": [{"table": "employees", "on": "employee_id", "columns": ["name", "employee_number"]}]
    }
}';

comment on column hr.employee_compensation.base_salary is '{"name": "Base Salary", "aggregate": "sum"}';

comment on column hr.employee_compensation.compa_ratio is '{"name": "Compa Ratio", "aggregate": "avg"}';

revoke all on table hr.employee_compensation
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
delete on table hr.employee_compensation to "x-admin";

create index idx_hr_compensation_employee_id on hr.employee_compensation (employee_id);

alter table hr.employee_compensation enable row level security;

create policy compensation_select on hr.employee_compensation for
select
  to authenticated using (true);

create policy compensation_insert on hr.employee_compensation for insert to authenticated
with
  check (true);

create policy compensation_update on hr.employee_compensation
for update
  to authenticated using (true)
with
  check (true);

create policy compensation_delete on hr.employee_compensation for delete to authenticated using (true);

----------------------------------------------------------------
-- Employee documents
--
-- These live in their own private bucket rather than the shared
-- `uploads` one — see the storage section at the end of this file
-- for the bucket and its policies.
----------------------------------------------------------------
create table hr.employee_documents (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_id uuid not null references hr.employees (id) on delete cascade,
  document_kind hr.document_kind not null default 'other',
  title varchar(200) not null,
  file supasheet.file,
  issued_on date,
  expires_on date,
  is_confidential boolean not null default true,
  requires_signature boolean not null default false,
  signed_on date,
  note varchar(500),
  uploaded_by uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint documents_expiry_after_issue check (
    expires_on is null
    or issued_on is null
    or expires_on >= issued_on
  )
);

comment on column hr.employee_documents.document_kind is '{
    "progress": false,
    "values": {
        "contract": {"variant": "default", "icon": "FileSignature"},
        "offer_letter": {"variant": "info", "icon": "FileText"},
        "identification": {"variant": "warning", "icon": "IdCard"},
        "right_to_work": {"variant": "destructive", "icon": "ShieldCheck"},
        "certification": {"variant": "success", "icon": "Award"},
        "payslip": {"variant": "secondary", "icon": "Receipt"},
        "performance": {"variant": "info", "icon": "ChartNoAxesColumn"},
        "other": {"variant": "secondary", "icon": "File"}
    }
}';

comment on table hr.employee_documents is '{
    "icon": "FolderLock",
    "name": "Documents",
    "description": "Contracts, right-to-work evidence and certifications.",
    "display": "none",
    "inline_form": true,
    "fields": {
        "sections": [
            {"id": "document", "title": "Document", "fields": ["employee_id", "document_kind", "title", "file"]},
            {"id": "validity", "title": "Validity", "fields": ["issued_on", "expires_on", "is_confidential"]},
            {"id": "signature", "title": "Signature", "fields": ["requires_signature", "signed_on"]},
            {"id": "extras", "title": "Note", "collapsible": true, "fields": ["note"]}
        ],
        "behavior": {
            "signed_on": {"visible": [{"id": "requires_signature", "operator": "eq", "value": "true"}]},
            "expires_on": {"visible": [{"id": "document_kind", "operator": "in", "value": ["identification", "right_to_work", "certification"]}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "employees", "on": "employee_id", "columns": ["name", "employee_number"]},
            {"table": "users", "on": "uploaded_by", "alias": "uploader", "columns": ["name", "email"]}
        ]
    }
}';

comment on column hr.employee_documents.file is '{"accept": ".pdf,.png,.jpg", "max_files": 5, "max_size": 10485760}';

revoke all on table hr.employee_documents
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
delete on table hr.employee_documents to "x-admin";

-- An employee can see their own paperwork, and nothing else.
grant
select
  on table hr.employee_documents to "user";

create index idx_hr_documents_employee_id on hr.employee_documents (employee_id);

create index idx_hr_documents_kind on hr.employee_documents (document_kind);

create index idx_hr_documents_expiring on hr.employee_documents (expires_on)
where
  expires_on is not null;

alter table hr.employee_documents enable row level security;

create policy documents_select on hr.employee_documents for
select
  to authenticated using (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
  );

create policy documents_insert on hr.employee_documents for insert to authenticated
with
  check (true);

create policy documents_update on hr.employee_documents
for update
  to authenticated using (true)
with
  check (true);

create policy documents_delete on hr.employee_documents for delete to authenticated using (true);

----------------------------------------------------------------
-- Job changes (the employment history behind every promotion,
-- transfer and pay change)
----------------------------------------------------------------
create table hr.job_changes (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_id uuid not null references hr.employees (id) on delete cascade,
  change_type hr.job_change_type not null default 'promotion',
  effective_date date not null default current_date,
  from_position_id uuid references hr.positions (id) on delete set null,
  to_position_id uuid references hr.positions (id) on delete set null,
  from_level_id uuid references hr.job_levels (id) on delete set null,
  to_level_id uuid references hr.job_levels (id) on delete set null,
  from_department_id uuid references hr.departments (id) on delete set null,
  to_department_id uuid references hr.departments (id) on delete set null,
  from_manager_id uuid references hr.employees (id) on delete set null,
  to_manager_id uuid references hr.employees (id) on delete set null,
  salary_change_percent supasheet.PERCENTAGE,
  reason varchar(300),
  note text,
  approved_by uuid references hr.employees (id) on delete set null,
  created_at timestamptz default current_timestamp
);

comment on column hr.job_changes.change_type is '{
    "progress": false,
    "values": {
        "hire": {"variant": "success", "icon": "UserPlus"},
        "promotion": {"variant": "success", "icon": "TrendingUp"},
        "lateral_move": {"variant": "info", "icon": "ArrowLeftRight"},
        "salary_change": {"variant": "warning", "icon": "Banknote"},
        "manager_change": {"variant": "secondary", "icon": "UserCog"},
        "location_change": {"variant": "info", "icon": "MapPin"},
        "contract_change": {"variant": "secondary", "icon": "FileSignature"},
        "termination": {"variant": "destructive", "icon": "UserMinus"}
    }
}';

comment on table hr.job_changes is '{
    "icon": "GitCompare",
    "name": "Job Changes",
    "description": "Every promotion, transfer and contract change, with its effective date.",
    "collapsible_group": "People",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "reason", "badges": ["change_type"]}},
    "views": [
        {
            "id": "list",
            "name": "History",
            "type": "list",
            "title": "reason",
            "description": "note",
            "field_1": "change_type",
            "field_2": "effective_date"
        },
        {
            "id": "calendar",
            "name": "Effective Dates",
            "type": "calendar",
            "title": "reason",
            "badge": "change_type",
            "start_date": "effective_date",
            "read_only": true
        }
    ],
    "filter_presets": [
        {"id": "promotions", "name": "Promotions", "filters": [{"id": "change_type", "value": "promotion", "operator": "eq"}]},
        {"id": "moves", "name": "Moves", "filters": [{"id": "change_type", "value": ["lateral_move", "manager_change", "location_change"], "operator": "in"}]}
    ],
    "fields": {
        "sections": [
            {"id": "change", "title": "Change", "fields": ["employee_id", "change_type", "effective_date", "reason"]},
            {"id": "role", "title": "Role", "fields": ["from_position_id", "to_position_id", "from_level_id", "to_level_id"]},
            {"id": "placement", "title": "Placement", "fields": ["from_department_id", "to_department_id", "from_manager_id", "to_manager_id"]},
            {"id": "pay", "title": "Pay", "fields": ["salary_change_percent"]},
            {"id": "extras", "title": "Note", "collapsible": true, "fields": ["note", "approved_by"]}
        ],
        "behavior": {
            "salary_change_percent": {"visible": [{"id": "change_type", "operator": "in", "value": ["promotion", "salary_change", "contract_change"]}]}
        }
    },
    "query": {
        "sort": [{"id": "effective_date", "desc": true}],
        "join": [
            {"table": "employees", "on": "employee_id", "columns": ["name", "employee_number"]},
            {"table": "positions", "on": "to_position_id", "alias": "new_position", "columns": ["title"]},
            {"table": "employees", "on": "approved_by", "alias": "approver", "columns": ["name"]}
        ]
    }
}';

revoke all on table hr.job_changes
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
delete on table hr.job_changes to "x-admin";

grant
select
  on table hr.job_changes to "people_manager";

create index idx_hr_job_changes_employee_id on hr.job_changes (employee_id);

create index idx_hr_job_changes_effective_date on hr.job_changes (effective_date desc);

alter table hr.job_changes enable row level security;

create policy job_changes_select on hr.job_changes for
select
  to authenticated using (
    hr.is_hr_staff ()
    or hr.manages (employee_id)
  );

create policy job_changes_insert on hr.job_changes for insert to authenticated
with
  check (true);

create policy job_changes_update on hr.job_changes
for update
  to authenticated using (true)
with
  check (true);

create policy job_changes_delete on hr.job_changes for delete to authenticated using (true);

----------------------------------------------------------------
-- Employee events (trigger-populated timeline)
----------------------------------------------------------------
create table hr.employee_events (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_id uuid not null references hr.employees (id) on delete cascade,
  event_type hr.employee_event_type not null,
  title varchar(255) not null,
  metadata jsonb,
  actor_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  occurred_at timestamptz not null default current_timestamp
);

comment on column hr.employee_events.event_type is '{
    "progress": false,
    "values": {
        "hired": {"variant": "success", "icon": "UserPlus"},
        "onboarded": {"variant": "success", "icon": "CircleCheck"},
        "promoted": {"variant": "success", "icon": "TrendingUp"},
        "transferred": {"variant": "info", "icon": "ArrowLeftRight"},
        "leave_taken": {"variant": "warning", "icon": "Plane"},
        "review_completed": {"variant": "default", "icon": "ClipboardCheck"},
        "goal_closed": {"variant": "info", "icon": "Target"},
        "training_completed": {"variant": "success", "icon": "GraduationCap"},
        "terminated": {"variant": "destructive", "icon": "UserMinus"},
        "record_updated": {"variant": "secondary", "icon": "RefreshCw"}
    }
}';

comment on table hr.employee_events is '{
    "icon": "History",
    "name": "Employee History",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "event", "title": "Event", "fields": ["employee_id", "event_type", "title", "metadata", "actor_id", "occurred_at"]}
        ]
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [{"table": "users", "on": "actor_id", "alias": "actor", "columns": ["name", "email"]}]
    }
}';

revoke all on table hr.employee_events
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on table hr.employee_events to "x-admin",
  "people_manager";

create index idx_hr_employee_events_employee_id on hr.employee_events (employee_id);

create index idx_hr_employee_events_occurred_at on hr.employee_events (occurred_at desc);

alter table hr.employee_events enable row level security;

create policy employee_events_select on hr.employee_events for
select
  to authenticated using (
    hr.is_hr_staff ()
    or hr.manages (employee_id)
  );

----------------------------------------------------------------
-- Leave types
----------------------------------------------------------------
create table hr.leave_types (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(120) not null,
  description text,
  unit hr.leave_unit not null default 'day',
  default_allowance numeric(6, 2) not null default 0,
  accrues_monthly boolean not null default false,
  is_paid boolean not null default true,
  requires_approval boolean not null default true,
  requires_evidence boolean not null default false,
  max_consecutive_days integer,
  carry_over_limit numeric(6, 2) not null default 0,
  counts_towards_service boolean not null default true,
  is_active boolean not null default true,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint leave_types_allowance_non_negative check (
    default_allowance >= 0
    and carry_over_limit >= 0
  )
);

comment on table hr.leave_types is '{
    "icon": "CalendarHeart",
    "name": "Leave Types",
    "description": "Annual, sick, parental and the rules attached to each.",
    "collapsible_group": "Time",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["unit", "is_paid"]},
        "tabs": ["leave_balances", "leave_requests"]
    },
    "views": [
        {
            "id": "list",
            "name": "Policies",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "default_allowance",
            "field_2": "is_paid"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "paid", "name": "Paid", "filters": [{"id": "is_paid", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "default_allowance"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "unit", "color"]},
            {"id": "entitlement", "title": "Entitlement", "fields": ["default_allowance", "accrues_monthly", "carry_over_limit", "max_consecutive_days"]},
            {"id": "rules", "title": "Rules", "fields": ["is_paid", "requires_approval", "requires_evidence", "counts_towards_service", "is_active"]}
        ],
        "behavior": {
            "carry_over_limit": {"visible": [{"id": "unit", "operator": "eq", "value": "day"}]}
        }
    },
    "query": {
        "sort": [{"id": "name", "desc": false}]
    }
}';

revoke all on table hr.leave_types
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
delete on table hr.leave_types to "x-admin";

grant
select
  on table hr.leave_types to "people_manager",
  "user";

alter table hr.leave_types enable row level security;

create policy leave_types_select on hr.leave_types for
select
  to authenticated using (true);

create policy leave_types_insert on hr.leave_types for insert to authenticated
with
  check (true);

create policy leave_types_update on hr.leave_types
for update
  to authenticated using (true)
with
  check (true);

create policy leave_types_delete on hr.leave_types for delete to authenticated using (true);

----------------------------------------------------------------
-- Leave balances (one row per employee per type per leave year)
----------------------------------------------------------------
create table hr.leave_balances (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_id uuid not null references hr.employees (id) on delete cascade,
  leave_type_id uuid not null references hr.leave_types (id) on delete cascade,
  leave_year integer not null default extract(
    year
    from
      current_date
  ),
  entitlement numeric(6, 2) not null default 0,
  carried_over numeric(6, 2) not null default 0,
  accrued numeric(6, 2) not null default 0,
  taken numeric(6, 2) not null default 0,
  pending numeric(6, 2) not null default 0,
  remaining numeric(6, 2) not null default 0,
  expires_on date,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (employee_id, leave_type_id, leave_year),
  constraint balances_non_negative check (
    entitlement >= 0
    and carried_over >= 0
    and taken >= 0
    and pending >= 0
  )
);

comment on table hr.leave_balances is '{
    "icon": "Scale",
    "name": "Leave Balances",
    "description": "Entitlement, what has been taken and what is left, per leave year.",
    "collapsible_group": "Time",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "leave_year", "badges": ["remaining"]}},
    "views": [
        {
            "id": "list",
            "name": "Balances",
            "type": "list",
            "title": "leave_year",
            "description": "employee_id",
            "field_1": "taken",
            "field_2": "remaining"
        }
    ],
    "filter_presets": [
        {"id": "current", "name": "This Year", "filters": [{"id": "leave_year", "value": "2026", "operator": "eq"}]},
        {"id": "exhausted", "name": "Exhausted", "filters": [{"id": "remaining", "value": "0", "operator": "lte"}]}
    ],
    "fields": {
        "quick_create": ["employee_id", "leave_type_id", "entitlement"],
        "sections": [
            {"id": "who", "title": "Who", "fields": ["employee_id", "leave_type_id", "leave_year", "expires_on"]},
            {"id": "entitlement", "title": "Entitlement", "fields": ["entitlement", "carried_over", "accrued"]},
            {"id": "usage", "title": "Usage", "fields": {"read": ["taken", "pending", "remaining"]}}
        ]
    },
    "query": {
        "sort": [{"id": "leave_year", "desc": true}],
        "join": [
            {"table": "employees", "on": "employee_id", "columns": ["name", "employee_number"]},
            {"table": "leave_types", "on": "leave_type_id", "columns": ["name", "code", "color"]}
        ]
    }
}';

comment on column hr.leave_balances.remaining is '{"name": "Remaining", "aggregate": "sum"}';

comment on column hr.leave_balances.taken is '{"aggregate": "sum"}';

revoke all on table hr.leave_balances
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
delete on table hr.leave_balances to "x-admin";

grant
select
  on table hr.leave_balances to "people_manager",
  "user";

create index idx_hr_leave_balances_employee_id on hr.leave_balances (employee_id);

create index idx_hr_leave_balances_type on hr.leave_balances (leave_type_id);

alter table hr.leave_balances enable row level security;

create policy leave_balances_select on hr.leave_balances for
select
  to authenticated using (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
    or hr.manages (employee_id)
  );

create policy leave_balances_insert on hr.leave_balances for insert to authenticated
with
  check (true);

create policy leave_balances_update on hr.leave_balances
for update
  to authenticated using (true)
with
  check (true);

create policy leave_balances_delete on hr.leave_balances for delete to authenticated using (true);

----------------------------------------------------------------
-- Leave requests (the approval workflow)
----------------------------------------------------------------
create table hr.leave_requests (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_id uuid not null references hr.employees (id) on delete cascade,
  leave_type_id uuid not null references hr.leave_types (id) on delete restrict,
  status hr.leave_status not null default 'draft',
  start_date date not null default current_date,
  end_date date not null default current_date,
  is_half_day boolean not null default false,
  working_days numeric(6, 2) not null default 0,
  reason varchar(500),
  evidence supasheet.file,
  approver_id uuid references hr.employees (id) on delete set null,
  submitted_at timestamptz,
  decided_at timestamptz,
  decision_note varchar(500),
  cancelled_at timestamptz,
  handover_note text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint leave_dates_ordered check (end_date >= start_date),
  constraint leave_days_non_negative check (working_days >= 0)
);

comment on column hr.leave_requests.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "pending": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "cancelled": {"variant": "secondary", "icon": "Ban"},
        "taken": {"variant": "info", "icon": "Plane"}
    }
}';

comment on table hr.leave_requests is '{
    "icon": "Plane",
    "name": "Leave",
    "description": "Time off: requested, approved and taken.",
    "collapsible_group": "Time",
    "display": "block",
    "primary_view": "calendar",
    "detail": {"header": {"title": "reason", "badges": ["status", "working_days"]}},
    "views": [
        {
            "id": "calendar",
            "name": "Leave Calendar",
            "type": "calendar",
            "title": "reason",
            "badge": "status",
            "start_date": "start_date",
            "end_date": "end_date"
        },
        {
            "id": "kanban",
            "name": "Approvals",
            "type": "kanban",
            "group": "status",
            "title": "reason",
            "description": "handover_note",
            "date": "start_date",
            "badge": "leave_type_id"
        },
        {
            "id": "list",
            "name": "All Requests",
            "type": "list",
            "title": "reason",
            "description": "decision_note",
            "field_1": "status",
            "field_2": "working_days"
        }
    ],
    "filter_presets": [
        {"id": "pending", "name": "Awaiting Approval", "filters": [{"id": "status", "value": "pending", "operator": "eq"}]},
        {"id": "approved", "name": "Approved", "filters": [{"id": "status", "value": ["approved", "taken"], "operator": "in"}]},
        {"id": "long", "name": "A Week Or More", "filters": [{"id": "working_days", "value": "5", "operator": "gte"}]}
    ],
    "links": [
        {"id": "leave_report", "name": "Leave Report", "url": "/hr/report/leave_report", "icon": "CalendarRange", "description": "Entitlement, taken and remaining across the company"}
    ],
    "fields": {
        "quick_create": ["employee_id", "leave_type_id", "start_date", "end_date"],
        "sections": [
            {"id": "request", "title": "Request", "fields": ["employee_id", "leave_type_id", "start_date", "end_date", "is_half_day"]},
            {"id": "context", "title": "Context", "fields": ["reason", "handover_note", "evidence"]},
            {"id": "decision", "title": "Decision", "fields": ["status", "approver_id", "decision_note"]},
            {"id": "computed", "title": "Computed", "fields": {"read": ["working_days", "submitted_at", "decided_at", "cancelled_at"]}}
        ],
        "behavior": {
            "decision_note": {
                "visible": [{"id": "status", "operator": "in", "value": ["approved", "rejected"]}],
                "required": [{"id": "status", "operator": "eq", "value": "rejected"}]
            },
            "evidence": {"visible": [{"id": "status", "operator": "not.eq", "value": "draft"}]},
            "is_half_day": {"visible": [{"id": "start_date", "operator": "not.is", "value": "null"}]}
        },
        "lookups": {
            "leave_type_id": {"fill": [{"source_column": "reason", "target_column": "name"}]}
        }
    },
    "query": {
        "sort": [{"id": "start_date", "desc": true}],
        "join": [
            {"table": "employees", "on": "employee_id", "columns": ["name", "employee_number", "avatar"]},
            {"table": "leave_types", "on": "leave_type_id", "columns": ["name", "code", "color"]},
            {"table": "employees", "on": "approver_id", "alias": "approver", "columns": ["name"]}
        ]
    }
}';

comment on column hr.leave_requests.working_days is '{"name": "Days", "aggregate": "sum"}';

comment on column hr.leave_requests.evidence is '{"accept": ".pdf,.png,.jpg", "max_files": 3, "max_size": 5242880}';

revoke all on table hr.leave_requests
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
delete on table hr.leave_requests to "x-admin";

grant
select
,
update on table hr.leave_requests to "people_manager";

grant
select
,
  insert,
update on table hr.leave_requests to "user";

create index idx_hr_leave_requests_employee_id on hr.leave_requests (employee_id);

create index idx_hr_leave_requests_type on hr.leave_requests (leave_type_id);

create index idx_hr_leave_requests_status on hr.leave_requests (status);

create index idx_hr_leave_requests_dates on hr.leave_requests (start_date, end_date);

-- The approval queue, oldest first.
create index idx_hr_leave_requests_pending on hr.leave_requests (approver_id, submitted_at)
where
  status = 'pending';

alter table hr.leave_requests enable row level security;

create policy leave_requests_select on hr.leave_requests for
select
  to authenticated using (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
    or hr.manages (employee_id)
  );

create policy leave_requests_insert on hr.leave_requests for insert to authenticated
with
  check (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
  );

create policy leave_requests_update on hr.leave_requests
for update
  to authenticated using (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
    or hr.manages (employee_id)
  )
with
  check (true);

create policy leave_requests_delete on hr.leave_requests for delete to authenticated using (true);

----------------------------------------------------------------
-- Public holidays (per location, so a remote team in another
-- country gets its own calendar)
----------------------------------------------------------------
create table hr.holidays (
  id uuid primary key default extensions.uuid_generate_v4 (),
  location_id uuid references hr.locations (id) on delete cascade,
  name varchar(160) not null,
  holiday_date date not null,
  is_working_day boolean not null default false,
  is_company_wide boolean not null default false,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  unique (location_id, holiday_date, name)
);

comment on table hr.holidays is '{
    "icon": "CalendarDays",
    "description": "Public and company holidays, per office.",
    "collapsible_group": "Time",
    "display": "block",
    "inline_form": true,
    "primary_view": "calendar",
    "detail": {"header": {"title": "name", "badges": ["is_company_wide"]}},
    "views": [
        {
            "id": "calendar",
            "name": "Holiday Calendar",
            "type": "calendar",
            "title": "name",
            "badge": "is_company_wide",
            "start_date": "holiday_date"
        },
        {
            "id": "list",
            "name": "All Holidays",
            "type": "list",
            "title": "name",
            "description": "note",
            "field_1": "holiday_date",
            "field_2": "is_company_wide"
        }
    ],
    "filter_presets": [
        {"id": "company", "name": "Company-wide", "filters": [{"id": "is_company_wide", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["name", "holiday_date", "location_id"],
        "sections": [
            {"id": "holiday", "title": "Holiday", "fields": ["name", "holiday_date", "location_id"]},
            {"id": "rules", "title": "Rules", "fields": ["is_company_wide", "is_working_day", "note"]}
        ],
        "behavior": {
            "location_id": {"visible": [{"id": "is_company_wide", "operator": "eq", "value": "false"}]}
        }
    },
    "query": {
        "sort": [{"id": "holiday_date", "desc": false}],
        "join": [{"table": "locations", "on": "location_id", "columns": ["name", "country"]}]
    }
}';

revoke all on table hr.holidays
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
delete on table hr.holidays to "x-admin";

grant
select
  on table hr.holidays to "people_manager",
  "recruiter",
  "user";

create index idx_hr_holidays_date on hr.holidays (holiday_date);

create index idx_hr_holidays_location_id on hr.holidays (location_id);

alter table hr.holidays enable row level security;

create policy holidays_select on hr.holidays for
select
  to authenticated using (true);

create policy holidays_insert on hr.holidays for insert to authenticated
with
  check (true);

create policy holidays_update on hr.holidays
for update
  to authenticated using (true)
with
  check (true);

create policy holidays_delete on hr.holidays for delete to authenticated using (true);

----------------------------------------------------------------
-- Timesheet entries (one row per person per day)
----------------------------------------------------------------
create table hr.timesheet_entries (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_id uuid not null references hr.employees (id) on delete cascade,
  work_date date not null default current_date,
  status hr.timesheet_status not null default 'draft',
  hours_worked numeric(5, 2) not null default 0,
  overtime_hours numeric(5, 2) not null default 0,
  break_duration supasheet.DURATION not null default 0,
  project_code varchar(40),
  task_note varchar(300),
  is_billable boolean not null default false,
  approver_id uuid references hr.employees (id) on delete set null,
  submitted_at timestamptz,
  approved_at timestamptz,
  rejection_note varchar(300),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (employee_id, work_date, project_code),
  constraint timesheet_hours_sane check (
    hours_worked >= 0
    and hours_worked <= 24
    and overtime_hours >= 0
    and overtime_hours <= 12
  )
);

comment on column hr.timesheet_entries.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "submitted": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on table hr.timesheet_entries is '{
    "icon": "Clock",
    "name": "Timesheets",
    "description": "Hours worked, day by day.",
    "collapsible_group": "Time",
    "display": "block",
    "inline_form": true,
    "primary_view": "calendar",
    "detail": {"header": {"title": "task_note", "badges": ["status", "hours_worked"]}},
    "views": [
        {
            "id": "calendar",
            "name": "Timesheet Calendar",
            "type": "calendar",
            "title": "task_note",
            "badge": "status",
            "start_date": "work_date"
        },
        {
            "id": "kanban",
            "name": "Approvals",
            "type": "kanban",
            "group": "status",
            "title": "task_note",
            "description": "project_code",
            "date": "work_date",
            "badge": "is_billable"
        },
        {
            "id": "list",
            "name": "All Entries",
            "type": "list",
            "title": "task_note",
            "description": "project_code",
            "field_1": "work_date",
            "field_2": "hours_worked"
        }
    ],
    "filter_presets": [
        {"id": "submitted", "name": "Awaiting Approval", "filters": [{"id": "status", "value": "submitted", "operator": "eq"}]},
        {"id": "billable", "name": "Billable", "filters": [{"id": "is_billable", "value": "true", "operator": "eq"}]},
        {"id": "overtime", "name": "With Overtime", "filters": [{"id": "overtime_hours", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["employee_id", "work_date", "hours_worked"],
        "sections": [
            {"id": "day", "title": "Day", "fields": ["employee_id", "work_date", "project_code", "is_billable"]},
            {"id": "hours", "title": "Hours", "fields": ["hours_worked", "overtime_hours", "break_duration"]},
            {"id": "note", "title": "Note", "fields": ["task_note"]},
            {"id": "approval", "title": "Approval", "fields": ["status", "approver_id", "rejection_note"]},
            {"id": "stamps", "title": "Stamps", "fields": {"read": ["submitted_at", "approved_at"]}}
        ],
        "behavior": {
            "rejection_note": {
                "visible": [{"id": "status", "operator": "eq", "value": "rejected"}],
                "required": [{"id": "status", "operator": "eq", "value": "rejected"}]
            },
            "overtime_hours": {"read_only": [{"id": "status", "operator": "in", "value": ["approved", "rejected"]}]}
        }
    },
    "query": {
        "sort": [{"id": "work_date", "desc": true}],
        "join": [
            {"table": "employees", "on": "employee_id", "columns": ["name", "employee_number"]},
            {"table": "employees", "on": "approver_id", "alias": "approver", "columns": ["name"]}
        ]
    }
}';

comment on column hr.timesheet_entries.hours_worked is '{"name": "Hours", "aggregate": "sum"}';

comment on column hr.timesheet_entries.overtime_hours is '{"name": "Overtime", "aggregate": "sum"}';

revoke all on table hr.timesheet_entries
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
delete on table hr.timesheet_entries to "x-admin";

grant
select
,
update on table hr.timesheet_entries to "people_manager";

grant
select
,
  insert,
update,
delete on table hr.timesheet_entries to "user";

create index idx_hr_timesheets_employee_id on hr.timesheet_entries (employee_id);

create index idx_hr_timesheets_work_date on hr.timesheet_entries (work_date desc);

create index idx_hr_timesheets_status on hr.timesheet_entries (status);

alter table hr.timesheet_entries enable row level security;

create policy timesheets_select on hr.timesheet_entries for
select
  to authenticated using (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
    or hr.manages (employee_id)
  );

create policy timesheets_insert on hr.timesheet_entries for insert to authenticated
with
  check (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
  );

create policy timesheets_update on hr.timesheet_entries
for update
  to authenticated using (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
    or hr.manages (employee_id)
  )
with
  check (true);

create policy timesheets_delete on hr.timesheet_entries for delete to authenticated using (
  hr.is_hr_staff ()
  or employee_id = hr.current_employee_id ()
);

----------------------------------------------------------------
-- Performance cycles (the review calendar — a gantt roadmap)
----------------------------------------------------------------
create table hr.performance_cycles (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(160) not null unique,
  status hr.review_cycle_status not null default 'planned',
  period_start date not null,
  period_end date not null,
  self_assessment_due date,
  manager_review_due date,
  calibration_on date,
  progress supasheet.PERCENTAGE not null default 0,
  participant_count integer not null default 0,
  completed_count integer not null default 0,
  instructions supasheet.RICH_TEXT,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint cycles_period_ordered check (period_end >= period_start)
);

comment on column hr.performance_cycles.status is '{
    "progress": true,
    "values": {
        "planned": {"variant": "secondary", "icon": "CalendarClock"},
        "self_assessment": {"variant": "info", "icon": "PenLine"},
        "manager_review": {"variant": "warning", "icon": "ClipboardCheck"},
        "calibration": {"variant": "default", "icon": "Scale"},
        "closed": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on table hr.performance_cycles is '{
    "icon": "CalendarRange",
    "name": "Review Cycles",
    "description": "Review periods and the deadlines inside them.",
    "collapsible_group": "Performance",
    "display": "block",
    "primary_view": "gantt",
    "detail": {
        "header": {"title": "name", "badges": ["status"]},
        "tabs": ["performance_reviews", "goals"]
    },
    "views": [
        {
            "id": "gantt",
            "name": "Cycle Roadmap",
            "type": "gantt",
            "title": "name",
            "start_date": "period_start",
            "end_date": "period_end",
            "group": "status",
            "progress": "progress",
            "badge": "status"
        },
        {
            "id": "list",
            "name": "All Cycles",
            "type": "list",
            "title": "name",
            "description": "instructions",
            "field_1": "status",
            "field_2": "progress"
        }
    ],
    "filter_presets": [
        {"id": "live", "name": "Live", "filters": [{"id": "status", "value": ["self_assessment", "manager_review", "calibration"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["name", "period_start", "period_end"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "status", "color"]},
            {"id": "period", "title": "Period", "fields": ["period_start", "period_end"]},
            {"id": "deadlines", "title": "Deadlines", "fields": ["self_assessment_due", "manager_review_due", "calibration_on"]},
            {"id": "instructions", "title": "Instructions", "collapsible": true, "fields": ["instructions"]},
            {"id": "progress", "title": "Progress", "fields": {"read": ["participant_count", "completed_count", "progress"]}}
        ]
    },
    "query": {
        "sort": [{"id": "period_start", "desc": true}]
    }
}';

comment on column hr.performance_cycles.progress is '{"name": "Complete", "aggregate": "avg"}';

revoke all on table hr.performance_cycles
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
delete on table hr.performance_cycles to "x-admin";

grant
select
  on table hr.performance_cycles to "people_manager",
  "user";

alter table hr.performance_cycles enable row level security;

create policy cycles_select on hr.performance_cycles for
select
  to authenticated using (true);

create policy cycles_insert on hr.performance_cycles for insert to authenticated
with
  check (true);

create policy cycles_update on hr.performance_cycles
for update
  to authenticated using (true)
with
  check (true);

create policy cycles_delete on hr.performance_cycles for delete to authenticated using (true);

----------------------------------------------------------------
-- Performance reviews
----------------------------------------------------------------
create table hr.performance_reviews (
  id uuid primary key default extensions.uuid_generate_v4 (),
  cycle_id uuid not null references hr.performance_cycles (id) on delete cascade,
  employee_id uuid not null references hr.employees (id) on delete cascade,
  reviewer_id uuid references hr.employees (id) on delete set null,
  status hr.review_status not null default 'not_started',
  rating hr.performance_rating,
  overall_score supasheet.RATING,
  self_assessment supasheet.RICH_TEXT,
  manager_comment supasheet.RICH_TEXT,
  strengths varchar(500),
  development_areas varchar(500),
  promotion_recommended boolean not null default false,
  self_submitted_at timestamptz,
  shared_at timestamptz,
  acknowledged_at timestamptz,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (cycle_id, employee_id)
);

comment on column hr.performance_reviews.status is '{
    "progress": true,
    "values": {
        "not_started": {"variant": "secondary", "icon": "Circle"},
        "self_assessment": {"variant": "info", "icon": "PenLine"},
        "manager_review": {"variant": "warning", "icon": "ClipboardCheck"},
        "shared": {"variant": "default", "icon": "Send"},
        "acknowledged": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on column hr.performance_reviews.rating is '{
    "progress": true,
    "values": {
        "below": {"variant": "destructive", "icon": "TrendingDown"},
        "developing": {"variant": "warning", "icon": "Sprout"},
        "meets": {"variant": "info", "icon": "Check"},
        "exceeds": {"variant": "success", "icon": "TrendingUp"},
        "outstanding": {"variant": "success", "icon": "Star"}
    }
}';

comment on table hr.performance_reviews is '{
    "icon": "ClipboardCheck",
    "name": "Reviews",
    "description": "One review per person per cycle, from self-assessment to acknowledgement.",
    "collapsible_group": "Performance",
    "display": "block",
    "primary_view": "kanban",
    "detail": {"header": {"title": "employee_id", "badges": ["status", "rating"]}},
    "views": [
        {
            "id": "kanban",
            "name": "Review Board",
            "type": "kanban",
            "group": "status",
            "title": "strengths",
            "description": "development_areas",
            "date": "shared_at",
            "badge": "rating"
        },
        {
            "id": "list",
            "name": "All Reviews",
            "type": "list",
            "title": "strengths",
            "description": "development_areas",
            "field_1": "status",
            "field_2": "rating"
        }
    ],
    "filter_presets": [
        {"id": "outstanding", "name": "Top Rated", "filters": [{"id": "rating", "value": ["exceeds", "outstanding"], "operator": "in"}]},
        {"id": "promotion", "name": "Promotion Recommended", "filters": [{"id": "promotion_recommended", "value": "true", "operator": "eq"}]},
        {"id": "open", "name": "Not Finished", "filters": [{"id": "status", "value": ["not_started", "self_assessment", "manager_review"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["cycle_id", "employee_id", "reviewer_id"],
        "sections": [
            {"id": "who", "title": "Who", "fields": ["cycle_id", "employee_id", "reviewer_id", "status"]},
            {"id": "self", "title": "Self assessment", "fields": ["self_assessment"]},
            {"id": "manager", "title": "Manager review", "fields": ["manager_comment", "strengths", "development_areas"]},
            {"id": "outcome", "title": "Outcome", "fields": ["rating", "overall_score", "promotion_recommended"]},
            {"id": "stamps", "title": "Stamps", "fields": {"read": ["self_submitted_at", "shared_at", "acknowledged_at"]}}
        ],
        "behavior": {
            "rating": {"required": [{"id": "status", "operator": "in", "value": ["shared", "acknowledged"]}]},
            "manager_comment": {"visible": [{"id": "status", "operator": "not.in", "value": ["not_started", "self_assessment"]}]}
        },
        "lookups": {
            "employee_id": {"fill": [{"source_column": "reviewer_id", "target_column": "manager_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "performance_cycles", "on": "cycle_id", "columns": ["name", "status"]},
            {"table": "employees", "on": "employee_id", "columns": ["name", "employee_number", "avatar"]},
            {"table": "employees", "on": "reviewer_id", "alias": "reviewer", "columns": ["name"]}
        ]
    }
}';

comment on column hr.performance_reviews.overall_score is '{"name": "Score", "aggregate": "avg"}';

revoke all on table hr.performance_reviews
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
delete on table hr.performance_reviews to "x-admin";

grant
select
,
  insert,
update on table hr.performance_reviews to "people_manager";

grant
select
,
update on table hr.performance_reviews to "user";

create index idx_hr_reviews_cycle_id on hr.performance_reviews (cycle_id);

create index idx_hr_reviews_employee_id on hr.performance_reviews (employee_id);

create index idx_hr_reviews_reviewer_id on hr.performance_reviews (reviewer_id);

create index idx_hr_reviews_status on hr.performance_reviews (status);

alter table hr.performance_reviews enable row level security;

-- A review is between the employee, their manager and HR. Nobody
-- else sees it, ever.
create policy reviews_select on hr.performance_reviews for
select
  to authenticated using (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
    or reviewer_id = hr.current_employee_id ()
    or hr.manages (employee_id)
  );

create policy reviews_insert on hr.performance_reviews for insert to authenticated
with
  check (true);

create policy reviews_update on hr.performance_reviews
for update
  to authenticated using (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
    or reviewer_id = hr.current_employee_id ()
    or hr.manages (employee_id)
  )
with
  check (true);

create policy reviews_delete on hr.performance_reviews for delete to authenticated using (true);

----------------------------------------------------------------
-- Goals (cascading objectives — parent_goal_id makes the tree)
----------------------------------------------------------------
create table hr.goals (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_id uuid references hr.employees (id) on delete cascade,
  cycle_id uuid references hr.performance_cycles (id) on delete set null,
  parent_goal_id uuid references hr.goals (id) on delete set null,
  title varchar(200) not null,
  description text,
  status hr.goal_status not null default 'draft',
  progress supasheet.PERCENTAGE not null default 0,
  weight supasheet.PERCENTAGE not null default 100,
  target_value numeric(14, 2),
  current_value numeric(14, 2),
  unit varchar(40),
  starts_on date not null default current_date,
  due_on date,
  closed_on date,
  outcome_note varchar(500),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint goals_not_own_parent check (id <> parent_goal_id),
  constraint goals_progress_range check (
    progress >= 0
    and progress <= 100
  ),
  constraint goals_dates_ordered check (
    due_on is null
    or due_on >= starts_on
  )
);

comment on column hr.goals.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "active": {"variant": "info", "icon": "Target"},
        "at_risk": {"variant": "warning", "icon": "TriangleAlert"},
        "achieved": {"variant": "success", "icon": "CircleCheck"},
        "missed": {"variant": "destructive", "icon": "CircleX"},
        "cancelled": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table hr.goals is '{
    "icon": "Target",
    "description": "Objectives, cascading from company level down to the individual.",
    "collapsible_group": "Performance",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "title", "badges": ["status", "progress"]},
        "tabs": ["goals"]
    },
    "views": [
        {
            "id": "tree",
            "name": "Objective Tree",
            "type": "tree",
            "parent": "parent_goal_id",
            "title": "title",
            "secondary": "status"
        },
        {
            "id": "kanban",
            "name": "By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "description",
            "date": "due_on",
            "badge": "progress"
        },
        {
            "id": "gantt",
            "name": "Timeline",
            "type": "gantt",
            "title": "title",
            "start_date": "starts_on",
            "end_date": "due_on",
            "group": "status",
            "progress": "progress",
            "badge": "status"
        },
        {
            "id": "list",
            "name": "All Goals",
            "type": "list",
            "title": "title",
            "description": "description",
            "field_1": "status",
            "field_2": "progress"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": ["active", "at_risk"], "operator": "in"}]},
        {"id": "at_risk", "name": "At Risk", "filters": [{"id": "status", "value": "at_risk", "operator": "eq"}]},
        {"id": "company", "name": "Company Level", "filters": [{"id": "employee_id", "value": "null", "operator": "is"}]}
    ],
    "fields": {
        "quick_create": ["title", "employee_id", "due_on"],
        "sections": [
            {"id": "goal", "title": "Goal", "fields": ["title", "description", "employee_id", "parent_goal_id", "cycle_id"]},
            {"id": "measure", "title": "Measure", "fields": ["target_value", "current_value", "unit", "weight"]},
            {"id": "schedule", "title": "Schedule", "fields": ["status", "starts_on", "due_on", "progress"]},
            {"id": "closure", "title": "Closure", "fields": ["closed_on", "outcome_note"]}
        ],
        "behavior": {
            "outcome_note": {
                "visible": [{"id": "status", "operator": "in", "value": ["achieved", "missed", "cancelled"]}],
                "required": [{"id": "status", "operator": "eq", "value": "missed"}]
            },
            "current_value": {"visible": [{"id": "target_value", "operator": "not.is", "value": "null"}]}
        }
    },
    "query": {
        "sort": [{"id": "due_on", "desc": false}],
        "join": [
            {"table": "employees", "on": "employee_id", "columns": ["name", "avatar"]},
            {"table": "goals", "on": "parent_goal_id", "alias": "parent_goal", "columns": ["title", "status"]},
            {"table": "performance_cycles", "on": "cycle_id", "columns": ["name"]}
        ]
    }
}';

comment on column hr.goals.progress is '{"name": "Progress", "aggregate": "avg"}';

revoke all on table hr.goals
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
delete on table hr.goals to "x-admin";

grant
select
,
  insert,
update on table hr.goals to "people_manager";

grant
select
,
  insert,
update on table hr.goals to "user";

create index idx_hr_goals_employee_id on hr.goals (employee_id);

create index idx_hr_goals_parent_id on hr.goals (parent_goal_id);

create index idx_hr_goals_cycle_id on hr.goals (cycle_id);

create index idx_hr_goals_status on hr.goals (status);

alter table hr.goals enable row level security;

-- Company-level goals (no owner) are visible to everybody; a
-- personal goal belongs to its owner, their chain and HR.
create policy goals_select on hr.goals for
select
  to authenticated using (
    employee_id is null
    or hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
    or hr.manages (employee_id)
  );

create policy goals_insert on hr.goals for insert to authenticated
with
  check (true);

create policy goals_update on hr.goals
for update
  to authenticated using (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
    or hr.manages (employee_id)
  )
with
  check (true);

create policy goals_delete on hr.goals for delete to authenticated using (true);

----------------------------------------------------------------
-- Training courses and enrollments
----------------------------------------------------------------
create table hr.training_courses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(30) not null unique,
  title varchar(200) not null,
  format hr.course_format not null default 'elearning',
  provider varchar(160),
  description supasheet.RICH_TEXT,
  cover supasheet.file,
  course_url supasheet.URL,
  duration supasheet.DURATION not null default 0,
  cost numeric(10, 2) not null default 0,
  currency varchar(3) not null default 'USD',
  is_mandatory boolean not null default false,
  renewal_months integer,
  average_rating supasheet.RATING,
  enrollment_count integer not null default 0,
  completion_count integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint courses_cost_non_negative check (cost >= 0)
);

comment on column hr.training_courses.format is '{
    "progress": false,
    "values": {
        "elearning": {"variant": "info", "icon": "MonitorPlay"},
        "workshop": {"variant": "default", "icon": "Users"},
        "conference": {"variant": "warning", "icon": "Tent"},
        "certification": {"variant": "success", "icon": "Award"},
        "mentoring": {"variant": "secondary", "icon": "Handshake"}
    }
}';

comment on table hr.training_courses is '{
    "icon": "GraduationCap",
    "name": "Training",
    "description": "The learning catalogue, mandatory and optional.",
    "collapsible_group": "Development",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "title", "badges": ["format", "is_mandatory"]},
        "tabs": ["training_enrollments"]
    },
    "views": [
        {
            "id": "gallery",
            "name": "Course Catalogue",
            "type": "gallery",
            "cover": "cover",
            "title": "title",
            "description": "provider",
            "badge": "format"
        },
        {
            "id": "list",
            "name": "All Courses",
            "type": "list",
            "title": "title",
            "description": "provider",
            "field_1": "format",
            "field_2": "enrollment_count"
        }
    ],
    "filter_presets": [
        {"id": "mandatory", "name": "Mandatory", "filters": [{"id": "is_mandatory", "value": "true", "operator": "eq"}]},
        {"id": "certifications", "name": "Certifications", "filters": [{"id": "format", "value": "certification", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["code", "title", "format"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "title", "format", "provider", "cover"]},
            {"id": "detail", "title": "Detail", "fields": ["description", "course_url", "duration"]},
            {"id": "policy", "title": "Policy", "fields": ["is_mandatory", "renewal_months", "cost", "currency", "is_active"]},
            {"id": "uptake", "title": "Uptake", "fields": {"read": ["enrollment_count", "completion_count", "average_rating"]}}
        ],
        "behavior": {
            "renewal_months": {"visible": [{"id": "format", "operator": "eq", "value": "certification"}]}
        }
    },
    "query": {
        "sort": [{"id": "title", "desc": false}]
    }
}';

comment on column hr.training_courses.cover is '{"accept": "image/*", "max_size": 5242880}';

comment on column hr.training_courses.cost is '{"aggregate": "sum"}';

comment on column hr.training_courses.duration is '{"name": "Length", "aggregate": "avg"}';

revoke all on table hr.training_courses
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
delete on table hr.training_courses to "x-admin";

grant
select
  on table hr.training_courses to "people_manager",
  "user";

alter table hr.training_courses enable row level security;

create policy courses_select on hr.training_courses for
select
  to authenticated using (true);

create policy courses_insert on hr.training_courses for insert to authenticated
with
  check (true);

create policy courses_update on hr.training_courses
for update
  to authenticated using (true)
with
  check (true);

create policy courses_delete on hr.training_courses for delete to authenticated using (true);

create table hr.training_enrollments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  course_id uuid not null references hr.training_courses (id) on delete cascade,
  employee_id uuid not null references hr.employees (id) on delete cascade,
  status hr.enrollment_status not null default 'enrolled',
  enrolled_on date not null default current_date,
  started_on date,
  completed_on date,
  expires_on date,
  score supasheet.PERCENTAGE,
  rating supasheet.RATING,
  certificate supasheet.file,
  feedback varchar(500),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (course_id, employee_id),
  constraint enrollment_score_range check (
    score is null
    or (
      score >= 0
      and score <= 100
    )
  )
);

comment on column hr.training_enrollments.status is '{
    "progress": true,
    "values": {
        "enrolled": {"variant": "secondary", "icon": "UserPlus"},
        "in_progress": {"variant": "info", "icon": "Loader"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "failed": {"variant": "destructive", "icon": "CircleX"},
        "withdrawn": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table hr.training_enrollments is '{
    "icon": "BookOpenCheck",
    "name": "Enrollments",
    "description": "Who is on which course, and how it went.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "enrollment", "title": "Enrollment", "fields": ["course_id", "employee_id", "status", "enrolled_on"]},
            {"id": "progress", "title": "Progress", "fields": ["started_on", "completed_on", "expires_on", "score"]},
            {"id": "feedback", "title": "Feedback", "fields": ["rating", "feedback", "certificate"]}
        ],
        "behavior": {
            "score": {"visible": [{"id": "status", "operator": "in", "value": ["completed", "failed"]}]},
            "certificate": {"visible": [{"id": "status", "operator": "eq", "value": "completed"}]}
        }
    },
    "query": {
        "sort": [{"id": "enrolled_on", "desc": true}],
        "join": [
            {"table": "training_courses", "on": "course_id", "columns": ["title", "format"]},
            {"table": "employees", "on": "employee_id", "columns": ["name", "employee_number"]}
        ]
    }
}';

comment on column hr.training_enrollments.score is '{"aggregate": "avg"}';

revoke all on table hr.training_enrollments
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
delete on table hr.training_enrollments to "x-admin";

grant
select
,
  insert on table hr.training_enrollments to "people_manager";

grant
select
,
  insert,
update on table hr.training_enrollments to "user";

create index idx_hr_enrollments_course_id on hr.training_enrollments (course_id);

create index idx_hr_enrollments_employee_id on hr.training_enrollments (employee_id);

alter table hr.training_enrollments enable row level security;

create policy enrollments_select on hr.training_enrollments for
select
  to authenticated using (
    hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
    or hr.manages (employee_id)
  );

create policy enrollments_insert on hr.training_enrollments for insert to authenticated
with
  check (true);

create policy enrollments_update on hr.training_enrollments
for update
  to authenticated using (true)
with
  check (true);

create policy enrollments_delete on hr.training_enrollments for delete to authenticated using (true);

----------------------------------------------------------------
-- Job openings (recruitment — the gantt of what is being hired)
----------------------------------------------------------------
create table hr.job_openings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(30) not null unique,
  title varchar(200) not null,
  position_id uuid references hr.positions (id) on delete set null,
  department_id uuid references hr.departments (id) on delete set null,
  location_id uuid references hr.locations (id) on delete set null,
  hiring_manager_id uuid references hr.employees (id) on delete set null,
  recruiter_id uuid references hr.employees (id) on delete set null,
  status hr.opening_status not null default 'draft',
  employment_type hr.employment_type not null default 'full_time',
  work_mode hr.work_mode not null default 'hybrid',
  headcount integer not null default 1,
  filled_count integer not null default 0,
  salary_min numeric(12, 2),
  salary_max numeric(12, 2),
  description supasheet.RICH_TEXT,
  opened_on date not null default current_date,
  target_start_on date,
  closed_on date,
  close_reason varchar(300),
  applicant_count integer not null default 0,
  progress supasheet.PERCENTAGE not null default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint openings_headcount_positive check (headcount > 0),
  constraint openings_salary_band_ordered check (
    salary_min is null
    or salary_max is null
    or salary_max >= salary_min
  ),
  constraint openings_target_after_open check (
    target_start_on is null
    or target_start_on >= opened_on
  )
);

comment on column hr.job_openings.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "open": {"variant": "success", "icon": "DoorOpen"},
        "on_hold": {"variant": "warning", "icon": "PauseCircle"},
        "filled": {"variant": "info", "icon": "UserCheck"},
        "cancelled": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on table hr.job_openings is '{
    "icon": "DoorOpen",
    "name": "Job Openings",
    "description": "Approved headcount that is actively being recruited for.",
    "collapsible_group": "Recruitment",
    "display": "block",
    "primary_view": "gantt",
    "detail": {
        "header": {"title": "title", "badges": ["status", "employment_type", "work_mode"]},
        "tabs": ["candidates"]
    },
    "views": [
        {
            "id": "gantt",
            "name": "Hiring Plan",
            "type": "gantt",
            "title": "title",
            "start_date": "opened_on",
            "end_date": "target_start_on",
            "group": "status",
            "progress": "progress",
            "badge": "employment_type"
        },
        {
            "id": "kanban",
            "name": "By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "code",
            "date": "target_start_on",
            "badge": "work_mode"
        },
        {
            "id": "list",
            "name": "All Openings",
            "type": "list",
            "title": "title",
            "description": "code",
            "field_1": "status",
            "field_2": "applicant_count"
        }
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": "open", "operator": "eq"}]},
        {"id": "stalled", "name": "No Applicants", "filters": [{"id": "applicant_count", "value": "0", "operator": "eq"}]},
        {"id": "on_hold", "name": "On Hold", "filters": [{"id": "status", "value": "on_hold", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["code", "title", "department_id", "headcount"],
        "sections": [
            {"id": "role", "title": "Role", "fields": ["code", "title", "position_id", "department_id", "location_id"]},
            {"id": "terms", "title": "Terms", "fields": ["employment_type", "work_mode", "headcount", "salary_min", "salary_max"]},
            {"id": "ownership", "title": "Ownership", "fields": ["hiring_manager_id", "recruiter_id", "status"]},
            {"id": "dates", "title": "Dates", "fields": ["opened_on", "target_start_on", "closed_on", "close_reason"]},
            {"id": "advert", "title": "Advert", "collapsible": true, "fields": ["description"]},
            {"id": "progress", "title": "Progress", "fields": {"read": ["applicant_count", "filled_count", "progress"]}}
        ],
        "behavior": {
            "close_reason": {
                "visible": [{"id": "status", "operator": "in", "value": ["filled", "cancelled"]}],
                "required": [{"id": "status", "operator": "eq", "value": "cancelled"}]
            },
            "closed_on": {"visible": [{"id": "status", "operator": "in", "value": ["filled", "cancelled"]}]}
        },
        "lookups": {
            "position_id": {
                "fill": [
                    {"source_column": "department_id", "target_column": "department_id"},
                    {"source_column": "title", "target_column": "title"}
                ]
            }
        }
    },
    "query": {
        "sort": [{"id": "opened_on", "desc": true}],
        "join": [
            {"table": "departments", "on": "department_id", "columns": ["name", "code"]},
            {"table": "locations", "on": "location_id", "columns": ["name", "country"]},
            {"table": "employees", "on": "hiring_manager_id", "alias": "hiring_manager", "columns": ["name"]},
            {"table": "employees", "on": "recruiter_id", "alias": "recruiter", "columns": ["name"]}
        ]
    }
}';

comment on column hr.job_openings.applicant_count is '{"name": "Applicants", "aggregate": "sum"}';

revoke all on table hr.job_openings
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
delete on table hr.job_openings to "x-admin";

grant
select
,
  insert,
update on table hr.job_openings to "recruiter";

grant
select
  on table hr.job_openings to "people_manager",
  "user";

create index idx_hr_openings_department_id on hr.job_openings (department_id);

create index idx_hr_openings_status on hr.job_openings (status);

create index idx_hr_openings_recruiter_id on hr.job_openings (recruiter_id);

alter table hr.job_openings enable row level security;

create policy openings_select on hr.job_openings for
select
  to authenticated using (true);

create policy openings_insert on hr.job_openings for insert to authenticated
with
  check (true);

create policy openings_update on hr.job_openings
for update
  to authenticated using (true)
with
  check (true);

create policy openings_delete on hr.job_openings for delete to authenticated using (true);

----------------------------------------------------------------
-- Candidates (the hiring pipeline)
----------------------------------------------------------------
create table hr.candidates (
  id uuid primary key default extensions.uuid_generate_v4 (),
  opening_id uuid not null references hr.job_openings (id) on delete cascade,
  first_name varchar(120) not null,
  last_name varchar(120) not null,
  name varchar(255),
  email supasheet.EMAIL not null,
  phone supasheet.TEL,
  linkedin_url supasheet.URL,
  stage hr.candidate_stage not null default 'applied',
  source varchar(80),
  current_company varchar(160),
  current_title varchar(160),
  years_experience integer,
  expected_salary numeric(12, 2),
  resume supasheet.file,
  rating supasheet.RATING,
  referred_by_id uuid references hr.employees (id) on delete set null,
  applied_on date not null default current_date,
  offer_amount numeric(12, 2),
  offer_sent_on date,
  decision_on date,
  rejection_reason varchar(300),
  notes supasheet.RICH_TEXT,
  interview_count integer not null default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint candidates_experience_sane check (
    years_experience is null
    or (
      years_experience >= 0
      and years_experience <= 60
    )
  )
);

comment on column hr.candidates.stage is '{
    "progress": true,
    "values": {
        "applied": {"variant": "secondary", "icon": "Inbox"},
        "screening": {"variant": "info", "icon": "PhoneCall"},
        "interviewing": {"variant": "default", "icon": "Users"},
        "offer": {"variant": "warning", "icon": "FileSignature"},
        "hired": {"variant": "success", "icon": "UserCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "withdrawn": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table hr.candidates is '{
    "icon": "UserSearch",
    "description": "Everyone in the pipeline, from application to offer.",
    "collapsible_group": "Recruitment",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "name", "badges": ["stage", "rating"]},
        "tabs": ["interviews"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Hiring Pipeline",
            "type": "kanban",
            "group": "stage",
            "title": "name",
            "description": "current_title",
            "date": "applied_on",
            "badge": "source"
        },
        {
            "id": "list",
            "name": "All Candidates",
            "type": "list",
            "title": "name",
            "description": "current_company",
            "field_1": "stage",
            "field_2": "applied_on"
        }
    ],
    "filter_presets": [
        {"id": "live", "name": "Live", "filters": [{"id": "stage", "value": ["applied", "screening", "interviewing", "offer"], "operator": "in"}]},
        {"id": "offers", "name": "At Offer", "filters": [{"id": "stage", "value": "offer", "operator": "eq"}]},
        {"id": "referrals", "name": "Referrals", "filters": [{"id": "referred_by_id", "value": "null", "operator": "not.is"}]},
        {"id": "strong", "name": "Rated 4+", "filters": [{"id": "rating", "value": "4", "operator": "gte"}]}
    ],
    "links": [
        {"id": "hiring_report", "name": "Hiring Report", "url": "/hr/report/hiring_report", "icon": "UserSearch", "description": "Funnel, time to hire and source effectiveness"}
    ],
    "fields": {
        "quick_create": ["first_name", "last_name", "email", "opening_id"],
        "sections": [
            {"id": "person", "title": "Person", "fields": ["first_name", "last_name", "email", "phone", "linkedin_url"]},
            {"id": "application", "title": "Application", "fields": ["opening_id", "stage", "source", "referred_by_id", "applied_on", "resume"]},
            {"id": "background", "title": "Background", "fields": ["current_company", "current_title", "years_experience", "expected_salary"]},
            {"id": "assessment", "title": "Assessment", "fields": ["rating", "notes"]},
            {"id": "offer", "title": "Offer", "fields": ["offer_amount", "offer_sent_on", "decision_on"]},
            {"id": "rejection", "title": "Rejection", "fields": ["rejection_reason"]},
            {"id": "progress", "title": "Progress", "fields": {"read": ["interview_count"]}}
        ],
        "behavior": {
            "offer_amount": {"visible": [{"id": "stage", "operator": "in", "value": ["offer", "hired"]}], "required": [{"id": "stage", "operator": "eq", "value": "offer"}]},
            "offer_sent_on": {"visible": [{"id": "stage", "operator": "in", "value": ["offer", "hired"]}]},
            "rejection_reason": {
                "visible": [{"id": "stage", "operator": "in", "value": ["rejected", "withdrawn"]}],
                "required": [{"id": "stage", "operator": "eq", "value": "rejected"}]
            }
        },
        "lookups": {
            "opening_id": {"fill": [{"source_column": "expected_salary", "target_column": "salary_max"}]}
        }
    },
    "query": {
        "sort": [{"id": "applied_on", "desc": true}],
        "join": [
            {"table": "job_openings", "on": "opening_id", "columns": ["code", "title", "status"]},
            {"table": "employees", "on": "referred_by_id", "alias": "referrer", "columns": ["name"]}
        ]
    }
}';

comment on column hr.candidates.resume is '{"accept": ".pdf,.doc,.docx", "max_files": 3, "max_size": 10485760}';

comment on column hr.candidates.expected_salary is '{"name": "Expected", "aggregate": "avg"}';

comment on column hr.candidates.rating is '{"aggregate": "avg"}';

revoke all on table hr.candidates
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
delete on table hr.candidates to "x-admin";

grant
select
,
  insert,
update on table hr.candidates to "recruiter";

grant
select
  on table hr.candidates to "people_manager";

create unique index idx_hr_candidates_opening_email on hr.candidates (opening_id, lower(email));

create index idx_hr_candidates_opening_id on hr.candidates (opening_id);

create index idx_hr_candidates_stage on hr.candidates (stage);

create index idx_hr_candidates_applied_on on hr.candidates (applied_on desc);

alter table hr.candidates enable row level security;

create policy candidates_select on hr.candidates for
select
  to authenticated using (true);

create policy candidates_insert on hr.candidates for insert to authenticated
with
  check (true);

create policy candidates_update on hr.candidates
for update
  to authenticated using (true)
with
  check (true);

create policy candidates_delete on hr.candidates for delete to authenticated using (true);

----------------------------------------------------------------
-- Interviews
----------------------------------------------------------------
create table hr.interviews (
  id uuid primary key default extensions.uuid_generate_v4 (),
  candidate_id uuid not null references hr.candidates (id) on delete cascade,
  interviewer_id uuid references hr.employees (id) on delete set null,
  kind hr.interview_kind not null default 'phone_screen',
  scheduled_at timestamptz not null default current_timestamp,
  duration supasheet.DURATION not null default 3600000,
  meeting_url supasheet.URL,
  location varchar(160),
  outcome hr.interview_outcome,
  score supasheet.RATING,
  feedback supasheet.RICH_TEXT,
  is_completed boolean not null default false,
  completed_at timestamptz,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hr.interviews.kind is '{
    "progress": true,
    "values": {
        "phone_screen": {"variant": "secondary", "icon": "PhoneCall"},
        "technical": {"variant": "info", "icon": "Code2"},
        "system_design": {"variant": "default", "icon": "Network"},
        "culture": {"variant": "success", "icon": "Users"},
        "panel": {"variant": "warning", "icon": "UsersRound"},
        "final": {"variant": "success", "icon": "Flag"}
    }
}';

comment on column hr.interviews.outcome is '{
    "progress": true,
    "values": {
        "strong_yes": {"variant": "success", "icon": "ThumbsUp"},
        "yes": {"variant": "success", "icon": "Check"},
        "mixed": {"variant": "warning", "icon": "Scale"},
        "no": {"variant": "destructive", "icon": "X"},
        "strong_no": {"variant": "destructive", "icon": "ThumbsDown"}
    }
}';

comment on table hr.interviews is '{
    "icon": "CalendarCheck",
    "description": "The interview schedule and the scorecards that come out of it.",
    "collapsible_group": "Recruitment",
    "display": "block",
    "inline_form": true,
    "primary_view": "calendar",
    "detail": {"header": {"title": "kind", "badges": ["outcome", "score"]}},
    "views": [
        {
            "id": "calendar",
            "name": "Interview Schedule",
            "type": "calendar",
            "title": "location",
            "badge": "kind",
            "start_date": "scheduled_at"
        },
        {
            "id": "kanban",
            "name": "By Outcome",
            "type": "kanban",
            "group": "outcome",
            "title": "location",
            "description": "feedback",
            "date": "scheduled_at",
            "badge": "kind"
        },
        {
            "id": "list",
            "name": "All Interviews",
            "type": "list",
            "title": "location",
            "description": "feedback",
            "field_1": "kind",
            "field_2": "scheduled_at"
        }
    ],
    "filter_presets": [
        {"id": "upcoming", "name": "Not Yet Done", "filters": [{"id": "is_completed", "value": "false", "operator": "eq"}]},
        {"id": "positive", "name": "Positive", "filters": [{"id": "outcome", "value": ["strong_yes", "yes"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["candidate_id", "kind", "scheduled_at", "interviewer_id"],
        "sections": [
            {"id": "schedule", "title": "Schedule", "fields": ["candidate_id", "kind", "interviewer_id", "scheduled_at", "duration"]},
            {"id": "where", "title": "Where", "fields": ["meeting_url", "location"]},
            {"id": "scorecard", "title": "Scorecard", "fields": ["is_completed", "outcome", "score", "feedback"]},
            {"id": "stamps", "title": "Stamps", "fields": {"read": ["completed_at"]}}
        ],
        "behavior": {
            "outcome": {
                "visible": [{"id": "is_completed", "operator": "eq", "value": "true"}],
                "required": [{"id": "is_completed", "operator": "eq", "value": "true"}]
            },
            "score": {"visible": [{"id": "is_completed", "operator": "eq", "value": "true"}]},
            "feedback": {"required": [{"id": "is_completed", "operator": "eq", "value": "true"}]}
        }
    },
    "query": {
        "sort": [{"id": "scheduled_at", "desc": true}],
        "join": [
            {"table": "candidates", "on": "candidate_id", "columns": ["name", "stage"]},
            {"table": "employees", "on": "interviewer_id", "alias": "interviewer", "columns": ["name", "avatar"]}
        ]
    }
}';

comment on column hr.interviews.score is '{"aggregate": "avg"}';

comment on column hr.interviews.duration is '{"name": "Length", "aggregate": "avg"}';

revoke all on table hr.interviews
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
delete on table hr.interviews to "x-admin";

grant
select
,
  insert,
update on table hr.interviews to "recruiter";

grant
select
,
update on table hr.interviews to "people_manager";

create index idx_hr_interviews_candidate_id on hr.interviews (candidate_id);

create index idx_hr_interviews_interviewer_id on hr.interviews (interviewer_id);

create index idx_hr_interviews_scheduled_at on hr.interviews (scheduled_at desc);

alter table hr.interviews enable row level security;

create policy interviews_select on hr.interviews for
select
  to authenticated using (true);

create policy interviews_insert on hr.interviews for insert to authenticated
with
  check (true);

create policy interviews_update on hr.interviews
for update
  to authenticated using (true)
with
  check (true);

create policy interviews_delete on hr.interviews for delete to authenticated using (true);

----------------------------------------------------------------
-- Onboarding tasks (the checklist a new starter gets — and the
-- target of the onboarding template further down)
----------------------------------------------------------------
create table hr.onboarding_tasks (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_id uuid references hr.employees (id) on delete cascade,
  title varchar(200) not null,
  description text,
  category varchar(60) not null default 'general',
  status hr.onboarding_status not null default 'pending',
  owner_id uuid references hr.employees (id) on delete set null,
  offset_days integer not null default 0,
  due_on date,
  completed_at timestamptz,
  is_blocking boolean not null default false,
  sort_order integer not null default 0,
  note varchar(500),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hr.onboarding_tasks.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "secondary", "icon": "Circle"},
        "in_progress": {"variant": "info", "icon": "Loader"},
        "done": {"variant": "success", "icon": "CircleCheck"},
        "blocked": {"variant": "destructive", "icon": "TriangleAlert"},
        "skipped": {"variant": "secondary", "icon": "SkipForward"}
    }
}';

comment on table hr.onboarding_tasks is '{
    "icon": "ListChecks",
    "name": "Onboarding",
    "description": "The checklist every new starter works through in their first month.",
    "collapsible_group": "People",
    "display": "block",
    "inline_form": true,
    "primary_view": "kanban",
    "detail": {"header": {"title": "title", "badges": ["status", "category"]}},
    "views": [
        {
            "id": "kanban",
            "name": "Onboarding Board",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "description",
            "date": "due_on",
            "badge": "category"
        },
        {
            "id": "calendar",
            "name": "Due Dates",
            "type": "calendar",
            "title": "title",
            "badge": "status",
            "start_date": "due_on"
        },
        {
            "id": "list",
            "name": "All Tasks",
            "type": "list",
            "title": "title",
            "description": "description",
            "field_1": "status",
            "field_2": "due_on"
        }
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": ["pending", "in_progress", "blocked"], "operator": "in"}]},
        {"id": "blocking", "name": "Blocking", "filters": [{"id": "is_blocking", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["title", "employee_id", "due_on"],
        "sections": [
            {"id": "task", "title": "Task", "fields": ["title", "description", "category", "is_blocking", "sort_order"]},
            {"id": "assignment", "title": "Assignment", "fields": ["employee_id", "owner_id", "status", "due_on", "offset_days"]},
            {"id": "closure", "title": "Closure", "fields": ["note"]},
            {"id": "stamps", "title": "Stamps", "fields": {"read": ["completed_at"]}}
        ],
        "behavior": {
            "note": {"visible": [{"id": "status", "operator": "in", "value": ["blocked", "skipped", "done"]}], "required": [{"id": "status", "operator": "eq", "value": "blocked"}]}
        }
    },
    "query": {
        "sort": [{"id": "sort_order", "desc": false}],
        "join": [
            {"table": "employees", "on": "employee_id", "columns": ["name", "employee_number", "hire_date"]},
            {"table": "employees", "on": "owner_id", "alias": "owner", "columns": ["name"]}
        ]
    }
}';

revoke all on table hr.onboarding_tasks
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
delete on table hr.onboarding_tasks to "x-admin";

grant
select
,
  insert,
update on table hr.onboarding_tasks to "people_manager";

grant
select
,
update on table hr.onboarding_tasks to "user";

create index idx_hr_onboarding_employee_id on hr.onboarding_tasks (employee_id);

create index idx_hr_onboarding_status on hr.onboarding_tasks (status);

create index idx_hr_onboarding_due_on on hr.onboarding_tasks (due_on);

alter table hr.onboarding_tasks enable row level security;

create policy onboarding_select on hr.onboarding_tasks for
select
  to authenticated using (
    employee_id is null
    or hr.is_hr_staff ()
    or employee_id = hr.current_employee_id ()
    or hr.manages (employee_id)
    or owner_id = hr.current_employee_id ()
  );

create policy onboarding_insert on hr.onboarding_tasks for insert to authenticated
with
  check (true);

create policy onboarding_update on hr.onboarding_tasks
for update
  to authenticated using (true)
with
  check (true);

create policy onboarding_delete on hr.onboarding_tasks for delete to authenticated using (true);

----------------------------------------------------------------
-- HR settings (singleton — one row only, no delete grant)
----------------------------------------------------------------
create table hr.hr_settings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  company_name varchar(200) not null default 'Supasheet',
  logo supasheet.file,
  brand_color supasheet.COLOR default '#0f766e',
  people_email supasheet.EMAIL,
  default_location_id uuid references hr.locations (id) on delete set null,
  leave_year_start_month integer not null default 1,
  default_annual_leave numeric(6, 2) not null default 25,
  probation_months integer not null default 6,
  notice_period_days integer not null default 30,
  standard_weekly_hours numeric(5, 2) not null default 40,
  timesheets_required boolean not null default true,
  self_service_leave boolean not null default true,
  auto_approve_leave_under_days numeric(4, 2) not null default 0,
  review_frequency_months integer not null default 6,
  currency varchar(3) not null default 'USD',
  timezone varchar(100) not null default 'UTC',
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint settings_month_range check (leave_year_start_month between 1 and 12),
  constraint settings_positive check (
    default_annual_leave >= 0
    and probation_months >= 0
    and notice_period_days >= 0
    and standard_weekly_hours > 0
  )
);

comment on table hr.hr_settings is '{
    "icon": "Settings",
    "name": "HR Settings",
    "description": "Company-wide people policy the triggers read from.",
    "collapsible_group": "Configuration",
    "display": "block",
    "singleton": true,
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["company_name", "logo", "brand_color", "people_email", "default_location_id"]},
            {"id": "leave", "title": "Leave policy", "fields": ["leave_year_start_month", "default_annual_leave", "self_service_leave", "auto_approve_leave_under_days"]},
            {"id": "contract", "title": "Contract defaults", "fields": ["probation_months", "notice_period_days", "standard_weekly_hours", "timesheets_required"]},
            {"id": "performance", "title": "Performance", "fields": ["review_frequency_months"]},
            {"id": "locale", "title": "Locale", "collapsible": true, "fields": ["currency", "timezone"]}
        ],
        "behavior": {
            "auto_approve_leave_under_days": {"visible": [{"id": "self_service_leave", "operator": "eq", "value": "true"}]}
        }
    },
    "query": {
        "join": [{"table": "locations", "on": "default_location_id", "columns": ["name", "country"]}]
    }
}';

comment on column hr.hr_settings.logo is '{"accept": "image/*", "max_size": 2097152}';

revoke all on table hr.hr_settings
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update on table hr.hr_settings to "x-admin";

grant
select
  on table hr.hr_settings to "people_manager",
  "recruiter",
  "user";

alter table hr.hr_settings enable row level security;

create policy hr_settings_select on hr.hr_settings for
select
  to authenticated using (true);

create policy hr_settings_insert on hr.hr_settings for insert to authenticated
with
  check (true);

create policy hr_settings_update on hr.hr_settings
for update
  to authenticated using (true)
with
  check (true);

----------------------------------------------------------------
-- Employee triggers
----------------------------------------------------------------
-- The display name, the derived service figures, and the one guard
-- an org chart cannot live without: a manager may not report, however
-- indirectly, to their own report.
--
-- SECURITY INVOKER on purpose — it only reads hr.employees and
-- hr.hr_settings, both readable by every role that can write here.
create or replace function hr.trg_employees_apply_defaults () returns trigger as $$
declare
    v_probation integer;
    v_cursor uuid;
    v_depth integer := 0;
begin
    new.name := btrim(coalesce(nullif(new.preferred_name, ''), new.first_name) || ' ' || new.last_name);
    new.work_email := lower(btrim(new.work_email));

    -- Walk up from the proposed manager. If we meet this employee on
    -- the way, the edge would close a loop and the org chart (and the
    -- recursive RLS helper) would never terminate cleanly.
    if new.manager_id is not null
       and (tg_op = 'INSERT' or new.manager_id is distinct from old.manager_id) then
        v_cursor := new.manager_id;

        while v_cursor is not null and v_depth < 20 loop
            if v_cursor = new.id then
                raise exception 'That reporting line is circular: % already reports to this person.',
                    new.name using errcode = 'check_violation';
            end if;

            select manager_id into v_cursor from hr.employees where id = v_cursor;
            v_depth := v_depth + 1;
        end loop;
    end if;

    if tg_op = 'INSERT' and new.probation_end_date is null then
        select probation_months into v_probation
        from hr.hr_settings
        order by created_at asc
        limit 1;

        new.probation_end_date := new.hire_date + make_interval(months => coalesce(v_probation, 6));
    end if;

    -- Service, in whole months, from the hire date to the leaving
    -- date or today.
    new.tenure_months := greatest(
        0,
        (
            extract(year from age(coalesce(new.termination_date, current_date), new.hire_date)) * 12
            + extract(month from age(coalesce(new.termination_date, current_date), new.hire_date))
        )::integer
    );

    if new.employment_status = 'terminated' then
        new.termination_date := coalesce(new.termination_date, current_date);
    else
        new.termination_date := null;
        new.termination_reason := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security invoker
set
  search_path = '';

create trigger employees_apply_defaults
before insert or update on hr.employees for each row
execute function hr.trg_employees_apply_defaults ();

-- Headcount rolls up to the manager, the department, the location
-- and the position.
create or replace function hr.trg_employees_rollup () returns trigger as $$
declare
    v_managers uuid[] := '{}';
    v_departments uuid[] := '{}';
    v_locations uuid[] := '{}';
    v_positions uuid[] := '{}';
    v_id uuid;
begin
    if tg_op <> 'INSERT' then
        v_managers := v_managers || old.manager_id;
        v_departments := v_departments || old.department_id;
        v_locations := v_locations || old.location_id;
        v_positions := v_positions || old.position_id;
    end if;

    if tg_op <> 'DELETE' then
        v_managers := v_managers || new.manager_id;
        v_departments := v_departments || new.department_id;
        v_locations := v_locations || new.location_id;
        v_positions := v_positions || new.position_id;
    end if;

    foreach v_id in array array_remove(v_managers, null) loop
        update hr.employees e
        set direct_report_count = (
            select count(*) from hr.employees r
            where r.manager_id = v_id and r.employment_status <> 'terminated'
        )
        where e.id = v_id
          and e.direct_report_count is distinct from (
            select count(*) from hr.employees r
            where r.manager_id = v_id and r.employment_status <> 'terminated'
          );
    end loop;

    foreach v_id in array array_remove(v_departments, null) loop
        update hr.departments d
        set headcount = sub.people
        from (
            select count(*) as people from hr.employees e
            where e.department_id = v_id and e.employment_status <> 'terminated'
        ) sub
        where d.id = v_id and d.headcount is distinct from sub.people;
    end loop;

    foreach v_id in array array_remove(v_locations, null) loop
        update hr.locations l
        set headcount = sub.people
        from (
            select count(*) as people from hr.employees e
            where e.location_id = v_id and e.employment_status <> 'terminated'
        ) sub
        where l.id = v_id and l.headcount is distinct from sub.people;
    end loop;

    foreach v_id in array array_remove(v_positions, null) loop
        update hr.positions p
        set filled_count = sub.people
        from (
            select count(*) as people from hr.employees e
            where e.position_id = v_id and e.employment_status <> 'terminated'
        ) sub
        where p.id = v_id and p.filled_count is distinct from sub.people;
    end loop;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger employees_rollup
after insert or update of manager_id,
department_id,
location_id,
position_id,
employment_status or delete on hr.employees for each row
execute function hr.trg_employees_rollup ();

create or replace function hr.trg_employees_log_event () returns trigger as $$
begin
    if tg_op = 'INSERT' then
        insert into hr.employee_events (employee_id, event_type, title, metadata, actor_id)
        values (
            new.id,
            'hired',
            new.name || ' joined',
            jsonb_build_object('hire_date', new.hire_date, 'employment_type', new.employment_type),
            auth.uid ()
        );
        return new;
    end if;

    if new.employment_status = 'terminated' and old.employment_status <> 'terminated' then
        insert into hr.employee_events (employee_id, event_type, title, metadata)
        values (
            new.id,
            'terminated',
            new.name || ' left',
            jsonb_build_object('termination_date', new.termination_date, 'reason', new.termination_reason)
        );
    elsif new.employment_status = 'active' and old.employment_status = 'onboarding' then
        insert into hr.employee_events (employee_id, event_type, title, metadata)
        values (new.id, 'onboarded', 'Onboarding complete', jsonb_build_object('probation_end', new.probation_end_date));
    elsif new.level_id is distinct from old.level_id then
        insert into hr.employee_events (employee_id, event_type, title, metadata)
        values (
            new.id,
            'promoted',
            'Level changed',
            jsonb_build_object('from', old.level_id, 'to', new.level_id)
        );
    elsif new.department_id is distinct from old.department_id
       or new.manager_id is distinct from old.manager_id then
        insert into hr.employee_events (employee_id, event_type, title, metadata)
        values (
            new.id,
            'transferred',
            'Team or reporting line changed',
            jsonb_build_object('department', new.department_id, 'manager', new.manager_id)
        );
    else
        insert into hr.employee_events (employee_id, event_type, title)
        values (new.id, 'record_updated', 'Record updated');
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger employees_log_event
after insert or update of employment_status,
level_id,
department_id,
manager_id,
position_id on hr.employees for each row
execute function hr.trg_employees_log_event ();

----------------------------------------------------------------
-- Leave triggers
----------------------------------------------------------------
-- Working days between two dates: weekends out, and any holiday that
-- applies to this employee's office out too. This is the number every
-- balance in the module is denominated in, so it lives in one
-- function rather than being recomputed by each caller.
create or replace function hr.working_days_between (p_employee_id uuid, p_start date, p_end date) returns numeric language sql stable security definer
set
  search_path = '' as $$
  select count(*)::numeric
  from generate_series(p_start, p_end, interval '1 day') as d (day)
  where extract(isodow from d.day) < 6
    and not exists (
      select 1
      from hr.holidays h
      left join hr.employees e on e.id = p_employee_id
      where h.holiday_date = d.day::date
        and not h.is_working_day
        and (h.is_company_wide or h.location_id = e.location_id)
    );
$$;

revoke all on function hr.working_days_between (uuid, date, date)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.working_days_between (uuid, date, date) to "x-admin",
"people_manager",
"user";

-- Everything a leave request has to be true about itself: a real
-- length, no overlap with leave already booked, enough balance to
-- cover it, and nobody signing off their own time away.
create or replace function hr.trg_leave_apply_defaults () returns trigger as $$
declare
    v_days numeric(6, 2);
    v_type hr.leave_types%rowtype;
    v_balance hr.leave_balances%rowtype;
    v_committed numeric(6, 2);
begin
    select * into v_type from hr.leave_types where id = new.leave_type_id;

    v_days := hr.working_days_between(new.employee_id, new.start_date, new.end_date);

    if new.is_half_day then
        if new.start_date <> new.end_date then
            raise exception 'A half day has to start and end on the same day.'
                using errcode = 'check_violation';
        end if;

        v_days := 0.5;
    end if;

    new.working_days := v_days;

    if v_days <= 0 then
        raise exception 'That range contains no working days.' using errcode = 'check_violation';
    end if;

    if v_type.max_consecutive_days is not null and v_days > v_type.max_consecutive_days then
        raise exception '% allows at most % consecutive days; this request is %.',
            v_type.name, v_type.max_consecutive_days, v_days
            using errcode = 'check_violation';
    end if;

    -- No double booking.
    if new.status not in ('rejected', 'cancelled')
       and exists (
        select 1
        from hr.leave_requests r
        where r.employee_id = new.employee_id
          and r.id <> new.id
          and r.status in ('pending', 'approved', 'taken')
          and r.start_date <= new.end_date
          and r.end_date >= new.start_date
       ) then
        raise exception 'This overlaps leave that is already booked.' using errcode = 'check_violation';
    end if;

    -- Balance check, once the request actually counts against it.
    if new.status in ('pending', 'approved', 'taken') and v_type.default_allowance > 0 then
        select * into v_balance
        from hr.leave_balances b
        where b.employee_id = new.employee_id
          and b.leave_type_id = new.leave_type_id
          and b.leave_year = extract(year from new.start_date);

        if v_balance.id is null then
            raise exception 'No % balance exists for % — create one before booking.',
                v_type.name, extract(year from new.start_date)
                using errcode = 'check_violation';
        end if;

        select coalesce(sum(r.working_days), 0) into v_committed
        from hr.leave_requests r
        where r.employee_id = new.employee_id
          and r.leave_type_id = new.leave_type_id
          and r.id <> new.id
          and r.status in ('pending', 'approved', 'taken')
          and extract(year from r.start_date) = extract(year from new.start_date);

        if v_committed + v_days > v_balance.entitlement + v_balance.carried_over then
            raise exception 'Not enough % left: % day(s) of % already committed, this asks for another %.',
                v_type.name, v_committed, v_balance.entitlement + v_balance.carried_over, v_days
                using errcode = 'check_violation';
        end if;
    end if;

    -- Stamps and the self-approval guard.
    if new.status = 'pending' and (tg_op = 'INSERT' or old.status <> 'pending') then
        new.submitted_at := coalesce(new.submitted_at, current_timestamp);
    end if;

    if new.status in ('approved', 'rejected') and (tg_op = 'INSERT' or old.status not in ('approved', 'rejected')) then
        if new.approver_id is not null and new.approver_id = new.employee_id then
            raise exception 'Leave cannot be approved by the person taking it.'
                using errcode = 'check_violation';
        end if;

        new.decided_at := coalesce(new.decided_at, current_timestamp);
    end if;

    if new.status = 'cancelled' and (tg_op = 'INSERT' or old.status <> 'cancelled') then
        new.cancelled_at := coalesce(new.cancelled_at, current_timestamp);
    end if;

    if new.status not in ('approved', 'rejected') then
        new.decision_note := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger leave_apply_defaults
before insert or update on hr.leave_requests for each row
execute function hr.trg_leave_apply_defaults ();

-- Balances follow the requests: pending is what is asked for,
-- taken is what has been approved, remaining is what is left.
create or replace function hr.trg_leave_rollup () returns trigger as $$
declare
    v_employee uuid := coalesce(new.employee_id, old.employee_id);
    v_type uuid := coalesce(new.leave_type_id, old.leave_type_id);
    v_year integer := extract(year from coalesce(new.start_date, old.start_date));
begin
    update hr.leave_balances b
    set taken = sub.taken,
        pending = sub.pending
    from (
        select
            coalesce(sum(r.working_days) filter (where r.status in ('approved', 'taken')), 0) as taken,
            coalesce(sum(r.working_days) filter (where r.status = 'pending'), 0) as pending
        from hr.leave_requests r
        where r.employee_id = v_employee
          and r.leave_type_id = v_type
          and extract(year from r.start_date) = v_year
    ) sub
    where b.employee_id = v_employee
      and b.leave_type_id = v_type
      and b.leave_year = v_year
      and (b.taken, b.pending) is distinct from (sub.taken, sub.pending);

    update hr.employees e
    set leave_days_taken = sub.days
    from (
        select coalesce(sum(r.working_days), 0) as days
        from hr.leave_requests r
        where r.employee_id = v_employee
          and r.status in ('approved', 'taken')
          and extract(year from r.start_date) = extract(year from current_date)
    ) sub
    where e.id = v_employee
      and e.leave_days_taken is distinct from sub.days;

    if tg_op <> 'DELETE' and new.status in ('approved', 'taken')
       and (tg_op = 'INSERT' or old.status not in ('approved', 'taken')) then
        insert into hr.employee_events (employee_id, event_type, title, metadata)
        values (
            new.employee_id,
            'leave_taken',
            new.working_days || ' day(s) approved',
            jsonb_build_object('from', new.start_date, 'to', new.end_date, 'request_id', new.id)
        );
    end if;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger leave_rollup
after insert or update or delete on hr.leave_requests for each row
execute function hr.trg_leave_rollup ();

create or replace function hr.trg_leave_balances_derive () returns trigger as $$
begin
    new.remaining := (new.entitlement + new.carried_over + new.accrued) - new.taken - new.pending;
    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger leave_balances_derive
before insert or update on hr.leave_balances for each row
execute function hr.trg_leave_balances_derive ();

----------------------------------------------------------------
-- Timesheet triggers
----------------------------------------------------------------
create or replace function hr.trg_timesheets_apply_defaults () returns trigger as $$
begin
    if new.work_date > current_date then
        raise exception 'You cannot book hours against a day that has not happened yet.'
            using errcode = 'check_violation';
    end if;

    if new.status = 'submitted' and (tg_op = 'INSERT' or old.status <> 'submitted') then
        new.submitted_at := coalesce(new.submitted_at, current_timestamp);
    end if;

    if new.status = 'approved' and (tg_op = 'INSERT' or old.status <> 'approved') then
        if new.approver_id is not null and new.approver_id = new.employee_id then
            raise exception 'A timesheet cannot be approved by the person who filed it.'
                using errcode = 'check_violation';
        end if;

        new.approved_at := coalesce(new.approved_at, current_timestamp);
    end if;

    if new.status <> 'rejected' then
        new.rejection_note := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger timesheets_apply_defaults
before insert or update on hr.timesheet_entries for each row
execute function hr.trg_timesheets_apply_defaults ();

----------------------------------------------------------------
-- Performance triggers
----------------------------------------------------------------
create or replace function hr.trg_reviews_apply_defaults () returns trigger as $$
declare
    v_cycle hr.performance_cycles%rowtype;
begin
    select * into v_cycle from hr.performance_cycles where id = new.cycle_id;

    if v_cycle.status = 'closed' and pg_trigger_depth() = 1 and not hr.is_hr_staff() then
        raise exception 'Cycle % is closed; its reviews can no longer be edited.', v_cycle.name
            using errcode = 'check_violation';
    end if;

    if new.status = 'self_assessment' and (tg_op = 'INSERT' or old.status <> 'self_assessment') then
        new.self_submitted_at := coalesce(new.self_submitted_at, current_timestamp);
    end if;

    if new.status = 'shared' and (tg_op = 'INSERT' or old.status <> 'shared') then
        if new.rating is null then
            raise exception 'A review cannot be shared without a rating.' using errcode = 'check_violation';
        end if;

        new.shared_at := coalesce(new.shared_at, current_timestamp);
    end if;

    if new.status = 'acknowledged' and (tg_op = 'INSERT' or old.status <> 'acknowledged') then
        new.acknowledged_at := coalesce(new.acknowledged_at, current_timestamp);
        new.shared_at := coalesce(new.shared_at, current_timestamp);
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security invoker
set
  search_path = '';

create trigger reviews_apply_defaults
before insert or update on hr.performance_reviews for each row
execute function hr.trg_reviews_apply_defaults ();

create or replace function hr.trg_reviews_rollup_cycle () returns trigger as $$
declare
    v_cycle uuid := coalesce(new.cycle_id, old.cycle_id);
begin
    update hr.performance_cycles c
    set participant_count = sub.total,
        completed_count = sub.done,
        progress = case when sub.total > 0 then round(100.0 * sub.done / sub.total)::real else 0 end
    from (
        select
            count(*) as total,
            count(*) filter (where r.status = 'acknowledged') as done
        from hr.performance_reviews r
        where r.cycle_id = v_cycle
    ) sub
    where c.id = v_cycle
      and (c.participant_count, c.completed_count) is distinct from (sub.total, sub.done);

    if tg_op <> 'DELETE' and new.status = 'acknowledged'
       and (tg_op = 'INSERT' or old.status <> 'acknowledged') then
        insert into hr.employee_events (employee_id, event_type, title, metadata)
        values (
            new.employee_id,
            'review_completed',
            'Review closed: ' || coalesce(new.rating::text, 'unrated'),
            jsonb_build_object('cycle_id', new.cycle_id, 'rating', new.rating, 'score', new.overall_score)
        );
    end if;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger reviews_rollup_cycle
after insert or update or delete on hr.performance_reviews for each row
execute function hr.trg_reviews_rollup_cycle ();

-- A parent objective is only as done as the children underneath it.
create or replace function hr.trg_goals_apply_defaults () returns trigger as $$
begin
    if new.target_value is not null and new.target_value > 0 and new.current_value is not null then
        new.progress := least(100, greatest(0, round(100.0 * new.current_value / new.target_value)))::real;
    end if;

    if new.progress >= 100 and new.status = 'active' then
        new.status := 'achieved';
    end if;

    if new.status in ('achieved', 'missed', 'cancelled') then
        new.closed_on := coalesce(new.closed_on, current_date);
    else
        new.closed_on := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger goals_apply_defaults
before insert or update on hr.goals for each row
execute function hr.trg_goals_apply_defaults ();

create or replace function hr.trg_goals_rollup_parent () returns trigger as $$
declare
    v_parents uuid[] := '{}';
    v_id uuid;
begin
    if tg_op <> 'INSERT' then
        v_parents := v_parents || old.parent_goal_id;
    end if;

    if tg_op <> 'DELETE' then
        v_parents := v_parents || new.parent_goal_id;
    end if;

    foreach v_id in array array_remove(v_parents, null) loop
        update hr.goals g
        set progress = sub.progress
        from (
            select coalesce(round(sum(c.progress * c.weight) / nullif(sum(c.weight), 0)), 0)::real as progress
            from hr.goals c
            where c.parent_goal_id = v_id
              and c.status <> 'cancelled'
        ) sub
        where g.id = v_id
          and g.progress is distinct from sub.progress;
    end loop;

    if tg_op <> 'DELETE' and new.employee_id is not null and new.status in ('achieved', 'missed')
       and (tg_op = 'INSERT' or old.status not in ('achieved', 'missed')) then
        insert into hr.employee_events (employee_id, event_type, title, metadata)
        values (
            new.employee_id,
            'goal_closed',
            new.title || ' — ' || new.status,
            jsonb_build_object('goal_id', new.id, 'progress', new.progress)
        );
    end if;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger goals_rollup_parent
after insert or update of progress,
weight,
status,
parent_goal_id or delete on hr.goals for each row
execute function hr.trg_goals_rollup_parent ();

----------------------------------------------------------------
-- Training triggers
----------------------------------------------------------------
create or replace function hr.trg_enrollments_apply_defaults () returns trigger as $$
declare
    v_course hr.training_courses%rowtype;
begin
    select * into v_course from hr.training_courses where id = new.course_id;

    if new.status = 'in_progress' and new.started_on is null then
        new.started_on := current_date;
    end if;

    if new.status in ('completed', 'failed') then
        new.completed_on := coalesce(new.completed_on, current_date);

        if new.status = 'completed' and v_course.renewal_months is not null then
            new.expires_on := coalesce(
                new.expires_on,
                new.completed_on + make_interval(months => v_course.renewal_months)
            );
        end if;
    else
        new.completed_on := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger enrollments_apply_defaults
before insert or update on hr.training_enrollments for each row
execute function hr.trg_enrollments_apply_defaults ();

create or replace function hr.trg_enrollments_rollup () returns trigger as $$
declare
    v_course uuid := coalesce(new.course_id, old.course_id);
begin
    update hr.training_courses c
    set enrollment_count = sub.total,
        completion_count = sub.done,
        average_rating = sub.rating
    from (
        select
            count(*) as total,
            count(*) filter (where e.status = 'completed') as done,
            round(avg(e.rating)::numeric, 2)::real as rating
        from hr.training_enrollments e
        where e.course_id = v_course
    ) sub
    where c.id = v_course
      and (c.enrollment_count, c.completion_count, c.average_rating)
          is distinct from (sub.total, sub.done, sub.rating);

    if tg_op <> 'DELETE' and new.status = 'completed'
       and (tg_op = 'INSERT' or old.status <> 'completed') then
        insert into hr.employee_events (employee_id, event_type, title, metadata)
        values (
            new.employee_id,
            'training_completed',
            'Completed a course',
            jsonb_build_object('course_id', new.course_id, 'score', new.score)
        );
    end if;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger enrollments_rollup
after insert or update or delete on hr.training_enrollments for each row
execute function hr.trg_enrollments_rollup ();

----------------------------------------------------------------
-- Recruitment triggers
----------------------------------------------------------------
create or replace function hr.trg_candidates_apply_defaults () returns trigger as $$
declare
    v_opening hr.job_openings%rowtype;
begin
    new.name := btrim(new.first_name || ' ' || new.last_name);
    new.email := lower(btrim(new.email));

    select * into v_opening from hr.job_openings where id = new.opening_id;

    -- An offer above the advertised band is a conversation with
    -- finance, not a field edit.
    if new.stage in ('offer', 'hired')
       and new.offer_amount is not null
       and v_opening.salary_max is not null
       and new.offer_amount > v_opening.salary_max then
        raise exception 'Offer of % is above the % band maximum of % for this opening.',
            new.offer_amount, v_opening.title, v_opening.salary_max
            using errcode = 'check_violation';
    end if;

    if new.stage = 'offer' and (tg_op = 'INSERT' or old.stage <> 'offer') then
        new.offer_sent_on := coalesce(new.offer_sent_on, current_date);
    end if;

    if new.stage in ('hired', 'rejected', 'withdrawn')
       and (tg_op = 'INSERT' or old.stage not in ('hired', 'rejected', 'withdrawn')) then
        new.decision_on := coalesce(new.decision_on, current_date);
    end if;

    if new.stage not in ('rejected', 'withdrawn') then
        new.rejection_reason := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger candidates_apply_defaults
before insert or update on hr.candidates for each row
execute function hr.trg_candidates_apply_defaults ();

create or replace function hr.trg_candidates_rollup_opening () returns trigger as $$
declare
    v_opening uuid := coalesce(new.opening_id, old.opening_id);
begin
    update hr.job_openings o
    set applicant_count = sub.applicants,
        filled_count = sub.hired,
        progress = case when o.headcount > 0 then least(100, round(100.0 * sub.hired / o.headcount))::real else 0 end,
        status = case
            when sub.hired >= o.headcount and o.status = 'open' then 'filled'::hr.opening_status
            else o.status
        end
    from (
        select
            count(*) as applicants,
            count(*) filter (where c.stage = 'hired') as hired
        from hr.candidates c
        where c.opening_id = v_opening
    ) sub
    where o.id = v_opening
      and (o.applicant_count, o.filled_count) is distinct from (sub.applicants, sub.hired);

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger candidates_rollup_opening
after insert or update of stage,
opening_id or delete on hr.candidates for each row
execute function hr.trg_candidates_rollup_opening ();

create or replace function hr.trg_interviews_after () returns trigger as $$
declare
    v_candidate uuid := coalesce(new.candidate_id, old.candidate_id);
begin
    update hr.candidates c
    set interview_count = sub.total
    from (
        select count(*) as total from hr.interviews i where i.candidate_id = v_candidate
    ) sub
    where c.id = v_candidate and c.interview_count is distinct from sub.total;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger interviews_after
after insert or delete on hr.interviews for each row
execute function hr.trg_interviews_after ();

create or replace function hr.trg_interviews_apply_defaults () returns trigger as $$
begin
    if new.is_completed and (tg_op = 'INSERT' or not old.is_completed) then
        new.completed_at := coalesce(new.completed_at, current_timestamp);
    elsif not new.is_completed then
        new.completed_at := null;
        new.outcome := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger interviews_apply_defaults
before insert or update on hr.interviews for each row
execute function hr.trg_interviews_apply_defaults ();

----------------------------------------------------------------
-- Onboarding triggers
----------------------------------------------------------------
-- A checklist item is dated from the person's start date, which is
-- what makes the onboarding template below work: the template only
-- carries an offset, and the trigger turns it into a real due date.
create or replace function hr.trg_onboarding_apply_defaults () returns trigger as $$
declare
    v_hire_date date;
begin
    if new.due_on is null and new.employee_id is not null then
        select hire_date into v_hire_date from hr.employees where id = new.employee_id;

        if v_hire_date is not null then
            new.due_on := v_hire_date + new.offset_days;
        end if;
    end if;

    if new.status = 'done' and (tg_op = 'INSERT' or old.status <> 'done') then
        new.completed_at := coalesce(new.completed_at, current_timestamp);
    elsif new.status <> 'done' then
        new.completed_at := null;
    end if;

    new.updated_at := current_timestamp;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger onboarding_apply_defaults
before insert or update on hr.onboarding_tasks for each row
execute function hr.trg_onboarding_apply_defaults ();

----------------------------------------------------------------
-- Scheduled maintenance
--
-- Tenure, leave-balance remainders and opening progress all age on
-- their own. Run nightly:
--
--   select cron.schedule(
--     'hr-refresh-state', '15 0 * * *',
--     $job$ select hr.refresh_people_state(); $job$
--   );
----------------------------------------------------------------
create or replace function hr.refresh_people_state () returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
  v_tenure integer;
  v_balances integer;
begin
  update hr.employees
  set tenure_months = greatest(
    0,
    (
      extract(year from age(coalesce(termination_date, current_date), hire_date)) * 12
      + extract(month from age(coalesce(termination_date, current_date), hire_date))
    )::integer
  )
  where tenure_months is distinct from greatest(
    0,
    (
      extract(year from age(coalesce(termination_date, current_date), hire_date)) * 12
      + extract(month from age(coalesce(termination_date, current_date), hire_date))
    )::integer
  );

  get diagnostics v_tenure = row_count;

  update hr.leave_balances
  set remaining = (entitlement + carried_over + accrued) - taken - pending
  where remaining is distinct from ((entitlement + carried_over + accrued) - taken - pending);

  get diagnostics v_balances = row_count;

  -- Approved leave that has now been taken.
  update hr.leave_requests
  set status = 'taken'
  where status = 'approved'
    and end_date < current_date;

  return v_tenure + v_balances;
end;
$$;

revoke all on function hr.refresh_people_state ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.refresh_people_state () to "x-admin";

-- Keep updated_at fresh on the tables without a defaults trigger.
create trigger locations_set_updated_at
before update on hr.locations for each row
execute function supasheet.set_updated_at ();

create trigger departments_set_updated_at
before update on hr.departments for each row
execute function supasheet.set_updated_at ();

create trigger job_levels_set_updated_at
before update on hr.job_levels for each row
execute function supasheet.set_updated_at ();

create trigger positions_set_updated_at
before update on hr.positions for each row
execute function supasheet.set_updated_at ();

create trigger compensation_set_updated_at
before update on hr.employee_compensation for each row
execute function supasheet.set_updated_at ();

create trigger documents_set_updated_at
before update on hr.employee_documents for each row
execute function supasheet.set_updated_at ();

create trigger leave_types_set_updated_at
before update on hr.leave_types for each row
execute function supasheet.set_updated_at ();

create trigger cycles_set_updated_at
before update on hr.performance_cycles for each row
execute function supasheet.set_updated_at ();

create trigger courses_set_updated_at
before update on hr.training_courses for each row
execute function supasheet.set_updated_at ();

create trigger openings_set_updated_at
before update on hr.job_openings for each row
execute function supasheet.set_updated_at ();

create trigger hr_settings_set_updated_at
before update on hr.hr_settings for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Row actions: leave
----------------------------------------------------------------
create or replace function hr.approve_leave (p_id uuid, p_note varchar default null) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_me uuid := hr.current_employee_id ();
begin
  update hr.leave_requests
  set status = 'approved',
      approver_id = coalesce(v_me, approver_id),
      decision_note = p_note
  where id = p_id
    and status = 'pending';

  if not found then
    raise exception 'Request not found or not awaiting a decision';
  end if;
end;
$$;

comment on function hr.approve_leave (uuid, varchar) is '{
    "type": "action",
    "resource": "leave_requests",
    "name": "Approve",
    "description": "Approve this request and draw it down from the balance",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "pending"}],
    "success_message": "Leave approved"
}';

revoke all on function hr.approve_leave (uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.approve_leave (uuid, varchar) to "x-admin",
"people_manager";

create or replace function hr.reject_leave (p_id uuid, p_note varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if btrim(coalesce(p_note, '')) = '' then
    raise exception 'Say why the request was declined';
  end if;

  update hr.leave_requests
  set status = 'rejected',
      approver_id = coalesce(hr.current_employee_id (), approver_id),
      decision_note = p_note
  where id = p_id
    and status = 'pending';

  if not found then
    raise exception 'Request not found or not awaiting a decision';
  end if;
end;
$$;

comment on function hr.reject_leave (uuid, varchar) is '{
    "type": "action",
    "resource": "leave_requests",
    "name": "Decline",
    "description": "Decline this request with a reason",
    "icon": "CircleX",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "eq", "value": "pending"}],
    "success_message": "Leave declined"
}';

revoke all on function hr.reject_leave (uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.reject_leave (uuid, varchar) to "x-admin",
"people_manager";

create or replace function hr.cancel_leave (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_start date;
begin
  select start_date into v_start from hr.leave_requests where id = p_id;

  if v_start is null then
    raise exception 'Request not found';
  end if;

  if v_start < current_date then
    raise exception 'Leave that has already started cannot be cancelled — speak to people operations';
  end if;

  update hr.leave_requests
  set status = 'cancelled'
  where id = p_id
    and status in ('draft', 'pending', 'approved');

  if not found then
    raise exception 'Request cannot be cancelled from its current state';
  end if;
end;
$$;

comment on function hr.cancel_leave (uuid) is '{
    "type": "action",
    "resource": "leave_requests",
    "name": "Cancel",
    "description": "Withdraw this request and give the days back",
    "icon": "Ban",
    "variant": "secondary",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "pending", "approved"]}],
    "success_message": "Leave cancelled"
}';

revoke all on function hr.cancel_leave (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.cancel_leave (uuid) to "x-admin",
"people_manager",
"user";

----------------------------------------------------------------
-- Row actions: timesheets and reviews
----------------------------------------------------------------
create or replace function hr.approve_timesheet (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update hr.timesheet_entries
  set status = 'approved',
      approver_id = coalesce(hr.current_employee_id (), approver_id)
  where id = p_id
    and status = 'submitted';

  if not found then
    raise exception 'Entry not found or not submitted';
  end if;
end;
$$;

comment on function hr.approve_timesheet (uuid) is '{
    "type": "action",
    "resource": "timesheet_entries",
    "name": "Approve",
    "description": "Sign off these hours",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "submitted"}],
    "success_message": "Timesheet approved"
}';

revoke all on function hr.approve_timesheet (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.approve_timesheet (uuid) to "x-admin",
"people_manager";

create or replace function hr.share_review (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_review hr.performance_reviews%rowtype;
begin
  select * into v_review from hr.performance_reviews where id = p_id;

  if v_review.id is null then
    raise exception 'Review not found';
  end if;

  if v_review.rating is null then
    raise exception 'Set a rating before sharing the review';
  end if;

  update hr.performance_reviews set status = 'shared' where id = p_id;
end;
$$;

comment on function hr.share_review (uuid) is '{
    "type": "action",
    "resource": "performance_reviews",
    "name": "Share",
    "description": "Release the review to the employee",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "in", "value": ["manager_review", "self_assessment"]}],
    "confirm": {"title": "Share this review?", "description": "The employee can read it from this moment on."},
    "success_message": "Review shared"
}';

revoke all on function hr.share_review (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.share_review (uuid) to "x-admin",
"people_manager";

create or replace function hr.acknowledge_review (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update hr.performance_reviews
  set status = 'acknowledged'
  where id = p_id
    and status = 'shared';

  if not found then
    raise exception 'Review not found or not yet shared';
  end if;
end;
$$;

comment on function hr.acknowledge_review (uuid) is '{
    "type": "action",
    "resource": "performance_reviews",
    "name": "Acknowledge",
    "description": "Confirm you have read and discussed this review",
    "icon": "ThumbsUp",
    "visible": [{"id": "status", "operator": "eq", "value": "shared"}],
    "success_message": "Review acknowledged"
}';

revoke all on function hr.acknowledge_review (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.acknowledge_review (uuid) to "x-admin",
"people_manager",
"user";

----------------------------------------------------------------
-- Row actions: people and recruitment
----------------------------------------------------------------
create or replace function hr.set_candidate_stage (p_id uuid, p_stage hr.candidate_stage) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_stage = 'rejected' then
    raise exception 'Use the "Reject" action so the reason is captured';
  end if;

  update hr.candidates set stage = p_stage where id = p_id;
end;
$$;

comment on function hr.set_candidate_stage (uuid, hr.candidate_stage) is '{
    "type": "action",
    "resource": "candidates",
    "name": "Move stage",
    "icon": "ArrowRightLeft",
    "action_type": "picker"
}';

revoke all on function hr.set_candidate_stage (uuid, hr.candidate_stage)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.set_candidate_stage (uuid, hr.candidate_stage) to "x-admin",
"recruiter";

create or replace function hr.reject_candidate (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'Say why the candidate was not taken forward';
  end if;

  update hr.candidates
  set stage = 'rejected',
      rejection_reason = p_reason
  where id = p_id
    and stage not in ('hired', 'rejected', 'withdrawn');

  if not found then
    raise exception 'Candidate not found or already decided';
  end if;
end;
$$;

comment on function hr.reject_candidate (uuid, varchar) is '{
    "type": "action",
    "resource": "candidates",
    "name": "Reject",
    "description": "Close this application with a reason",
    "icon": "CircleX",
    "variant": "destructive",
    "visible": [{"id": "stage", "operator": "not.in", "value": ["hired", "rejected", "withdrawn"]}],
    "success_message": "Candidate rejected"
}';

revoke all on function hr.reject_candidate (uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.reject_candidate (uuid, varchar) to "x-admin",
"recruiter";

create or replace function hr.complete_onboarding_task (p_id uuid, p_note varchar default null) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update hr.onboarding_tasks
  set status = 'done',
      note = coalesce(p_note, note)
  where id = p_id
    and status <> 'done';

  if not found then
    raise exception 'Task not found or already done';
  end if;
end;
$$;

comment on function hr.complete_onboarding_task (uuid, varchar) is '{
    "type": "action",
    "resource": "onboarding_tasks",
    "name": "Mark done",
    "description": "Tick this off the checklist",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "neq", "value": "done"}],
    "success_message": "Task completed"
}';

revoke all on function hr.complete_onboarding_task (uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.complete_onboarding_task (uuid, varchar) to "x-admin",
"people_manager",
"user";

create or replace function hr.terminate_employee (
  p_id uuid,
  p_reason hr.termination_reason,
  p_last_day date default null
) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_reports integer;
begin
  select count(*) into v_reports
  from hr.employees
  where manager_id = p_id and employment_status <> 'terminated';

  if v_reports > 0 then
    raise exception 'This person still has % direct report(s) — move them first.', v_reports;
  end if;

  update hr.employees
  set employment_status = 'terminated',
      termination_reason = p_reason,
      termination_date = coalesce(p_last_day, current_date)
  where id = p_id
    and employment_status <> 'terminated';

  if not found then
    raise exception 'Employee not found or already a leaver';
  end if;

  -- Anything still booked in the future is released.
  update hr.leave_requests
  set status = 'cancelled'
  where employee_id = p_id
    and status in ('pending', 'approved')
    and start_date > current_date;
end;
$$;

comment on function hr.terminate_employee (uuid, hr.termination_reason, date) is '{
    "type": "action",
    "resource": "employees",
    "name": "Record leaver",
    "description": "Close the employment record and release future leave",
    "icon": "UserMinus",
    "variant": "destructive",
    "visible": [{"id": "employment_status", "operator": "neq", "value": "terminated"}],
    "confirm": {"title": "Record this person as a leaver?", "description": "Future leave is cancelled and they drop out of the directory."},
    "success_message": "Leaver recorded"
}';

revoke all on function hr.terminate_employee (uuid, hr.termination_reason, date)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.terminate_employee (uuid, hr.termination_reason, date) to "x-admin";

----------------------------------------------------------------
-- Custom form: book time off (listed on the "employees" resource
-- overview). Returns a scalar uuid.
----------------------------------------------------------------
create or replace function hr.request_leave (
  p_employee_id uuid,
  p_leave_type_id uuid,
  p_start_date date,
  p_end_date date,
  p_is_half_day boolean default false,
  p_reason varchar default null,
  p_handover_note text default null
) returns uuid language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_id uuid;
  v_manager uuid;
  v_auto numeric(4, 2);
  v_days numeric(6, 2);
begin
  select manager_id into v_manager from hr.employees where id = p_employee_id;

  select auto_approve_leave_under_days into v_auto
  from hr.hr_settings
  order by created_at asc
  limit 1;

  v_days := hr.working_days_between(p_employee_id, p_start_date, p_end_date);

  insert into hr.leave_requests (
    employee_id, leave_type_id, start_date, end_date, is_half_day,
    reason, handover_note, approver_id, status
  )
  values (
    p_employee_id,
    p_leave_type_id,
    p_start_date,
    p_end_date,
    p_is_half_day,
    p_reason,
    p_handover_note,
    v_manager,
    -- Short requests can clear themselves if the company allows it.
    case
      when coalesce(v_auto, 0) > 0 and v_days <= v_auto then 'approved'::hr.leave_status
      else 'pending'::hr.leave_status
    end
  )
  returning id into v_id;

  return v_id;
end;
$$;

comment on function hr.request_leave (uuid, uuid, date, date, boolean, varchar, text) is '{
    "type": "form",
    "resource": "employees",
    "name": "Book time off",
    "description": "Raise a leave request. Working days, weekends and public holidays are worked out for you.",
    "icon": "Plane",
    "success_message": "Leave requested",
    "fields": {
        "sections": [
            {"id": "who", "title": "Who", "fields": ["p_employee_id", "p_leave_type_id"]},
            {"id": "when", "title": "When", "fields": ["p_start_date", "p_end_date", "p_is_half_day"]},
            {"id": "context", "title": "Context", "fields": ["p_reason", "p_handover_note"]}
        ],
        "relations": {
            "p_employee_id": {"table": "employees", "column": "id", "display": ["name", "employee_number"]},
            "p_leave_type_id": {"table": "leave_types", "column": "id", "display": ["name", "code"]}
        }
    }
}';

revoke all on function hr.request_leave (uuid, uuid, date, date, boolean, varchar, text)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.request_leave (uuid, uuid, date, date, boolean, varchar, text) to "x-admin",
"people_manager",
"user";

----------------------------------------------------------------
-- Custom form: turn a hired candidate into an employee (listed on
-- the "job_openings" resource overview). Returns a single object row
-- via explicit OUT parameters.
----------------------------------------------------------------
create or replace function hr.onboard_candidate (
  p_candidate_id uuid,
  p_hire_date date,
  p_manager_id uuid default null,
  p_location_id uuid default null,
  p_employment_type hr.employment_type default 'full_time',
  out employee_id uuid,
  out employee_number varchar,
  out name varchar,
  out work_email varchar,
  out hire_date date,
  out probation_end_date date,
  out onboarding_tasks integer
) language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_candidate hr.candidates%rowtype;
  v_opening hr.job_openings%rowtype;
  v_employee hr.employees%rowtype;
  v_tasks integer;
begin
  select * into v_candidate from hr.candidates where id = p_candidate_id;

  if v_candidate.id is null then
    raise exception 'Candidate not found';
  end if;

  if v_candidate.stage <> 'hired' then
    raise exception 'Move % to hired before onboarding them', v_candidate.name;
  end if;

  select * into v_opening from hr.job_openings where id = v_candidate.opening_id;

  insert into hr.employees (
    first_name, last_name, work_email, personal_email, phone,
    manager_id, department_id, location_id, position_id,
    employment_status, employment_type, work_mode, hire_date
  )
  values (
    v_candidate.first_name,
    v_candidate.last_name,
    lower(v_candidate.first_name || '.' || v_candidate.last_name || '@supasheet.test'),
    v_candidate.email,
    v_candidate.phone,
    coalesce(p_manager_id, v_opening.hiring_manager_id),
    v_opening.department_id,
    coalesce(p_location_id, v_opening.location_id),
    v_opening.position_id,
    'onboarding',
    p_employment_type,
    coalesce(v_opening.work_mode, 'hybrid'),
    p_hire_date
  )
  returning * into v_employee;

  -- Stamp the standard checklist onto the new starter. The
  -- onboarding trigger turns each offset into a real due date.
  insert into hr.onboarding_tasks (employee_id, title, description, category, offset_days, is_blocking, sort_order)
  select
    v_employee.id, t.title, t.description, t.category, t.offset_days, t.is_blocking, t.sort_order
  from hr.onboarding_tasks t
  where t.employee_id is null;

  get diagnostics v_tasks = row_count;

  employee_id := v_employee.id;
  employee_number := v_employee.employee_number;
  name := v_employee.name;
  work_email := v_employee.work_email;
  hire_date := v_employee.hire_date;
  probation_end_date := v_employee.probation_end_date;
  onboarding_tasks := v_tasks;
end;
$$;

comment on function hr.onboard_candidate (uuid, date, uuid, uuid, hr.employment_type) is '{
    "type": "form",
    "resource": "job_openings",
    "name": "Onboard hire",
    "description": "Turn a hired candidate into an employee record and stamp the onboarding checklist onto them.",
    "icon": "UserPlus",
    "success_message": "New starter created",
    "fields": {
        "sections": [
            {"id": "candidate", "title": "Candidate", "fields": ["p_candidate_id", "p_hire_date"]},
            {"id": "placement", "title": "Placement", "fields": ["p_manager_id", "p_location_id", "p_employment_type"]}
        ],
        "relations": {
            "p_candidate_id": {"table": "candidates", "column": "id", "display": ["name", "stage"]},
            "p_manager_id": {"table": "employees", "column": "id", "display": ["name", "employee_number"]},
            "p_location_id": {"table": "locations", "column": "id", "display": ["code", "name"]}
        }
    }
}';

revoke all on function hr.onboard_candidate (uuid, date, uuid, uuid, hr.employment_type)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.onboard_candidate (uuid, date, uuid, uuid, hr.employment_type) to "x-admin";

----------------------------------------------------------------
-- Custom form: put a whole team on a course (listed on the
-- "training_courses" resource overview). Returns
-- setof hr.training_enrollments.
----------------------------------------------------------------
create or replace function hr.bulk_enroll_team (
  p_course_id uuid,
  p_manager_id uuid,
  p_include_indirect boolean default false
) returns setof hr.training_enrollments language plpgsql security invoker
set
  search_path = '' as $$
begin
  return query
  with recursive team as (
    select e.id, 1 as depth
    from hr.employees e
    where e.manager_id = p_manager_id
      and e.employment_status <> 'terminated'
    union all
    select e.id, t.depth + 1
    from hr.employees e
    join team t on e.manager_id = t.id
    where p_include_indirect and t.depth < 8 and e.employment_status <> 'terminated'
  )
  insert into hr.training_enrollments (course_id, employee_id, status)
  select p_course_id, t.id, 'enrolled'
  from team t
  where not exists (
    select 1 from hr.training_enrollments x
    where x.course_id = p_course_id and x.employee_id = t.id
  )
  returning *;
end;
$$;

comment on function hr.bulk_enroll_team (uuid, uuid, boolean) is '{
    "type": "form",
    "resource": "training_courses",
    "name": "Enroll a team",
    "description": "Put a manager''s whole team on this course, skipping anybody already enrolled.",
    "icon": "Users",
    "success_message": "Team enrolled",
    "fields": {
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["p_course_id", "p_manager_id", "p_include_indirect"]}
        ],
        "relations": {
            "p_course_id": {"table": "training_courses", "column": "id", "display": ["code", "title"]},
            "p_manager_id": {"table": "employees", "column": "id", "display": ["name", "employee_number"]}
        }
    }
}';

revoke all on function hr.bulk_enroll_team (uuid, uuid, boolean)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.bulk_enroll_team (uuid, uuid, boolean) to "x-admin",
"people_manager";

----------------------------------------------------------------
-- Custom form: who is off, and when (listed on the "departments"
-- resource overview). Pure computation — returns setof rows via an
-- explicit table(...) column list.
----------------------------------------------------------------
create or replace function hr.preview_team_leave (
  p_department_id uuid,
  p_from date default current_date,
  p_to date default (current_date + 60)
) returns table (
  employee varchar,
  entitlement numeric,
  taken numeric,
  remaining numeric,
  days_booked_in_window numeric,
  next_absence date,
  returns_on date
) language plpgsql security invoker
set
  search_path = '' as $$
begin
  return query
  select
    e.name,
    coalesce(sum(b.entitlement + b.carried_over), 0) as entitlement,
    coalesce(sum(b.taken), 0) as taken,
    coalesce(sum(b.remaining), 0) as remaining,
    coalesce((
      select sum(r.working_days)
      from hr.leave_requests r
      where r.employee_id = e.id
        and r.status in ('approved', 'taken')
        and r.start_date between p_from and p_to
    ), 0) as days_booked_in_window,
    (
      select min(r.start_date)
      from hr.leave_requests r
      where r.employee_id = e.id
        and r.status in ('pending', 'approved')
        and r.start_date >= p_from
    ) as next_absence,
    (
      select min(r.end_date)
      from hr.leave_requests r
      where r.employee_id = e.id
        and r.status in ('pending', 'approved')
        and r.start_date >= p_from
    ) as returns_on
  from hr.employees e
  left join hr.leave_balances b
    on b.employee_id = e.id
   and b.leave_year = extract(year from current_date)
  where e.department_id = p_department_id
    and e.employment_status <> 'terminated'
  group by e.id, e.name
  order by days_booked_in_window desc, e.name;
end;
$$;

comment on function hr.preview_team_leave (uuid, date, date) is '{
    "type": "form",
    "resource": "departments",
    "name": "Leave outlook",
    "description": "Entitlement, days left and who is away in the window, for everyone in this department.",
    "icon": "CalendarRange",
    "success_message": "Leave outlook calculated",
    "fields": {
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["p_department_id", "p_from", "p_to"]}
        ],
        "relations": {
            "p_department_id": {"table": "departments", "column": "id", "display": ["name", "code"]}
        }
    }
}';

revoke all on function hr.preview_team_leave (uuid, date, date)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function hr.preview_team_leave (uuid, date, date) to "x-admin",
"people_manager";

----------------------------------------------------------------
-- Templates (bulk insert payloads applied via supasheet.apply_template)
----------------------------------------------------------------
-- Static: the checklist every new starter gets. Applied to
-- hr.onboarding_tasks with no employee, these rows become the master
-- list that hr.onboard_candidate copies onto each new hire.
create or replace view hr.onboarding_tasks_template
with
  (security_invoker = true) as
select
  t.title,
  t.description,
  t.category,
  t.offset_days,
  t.is_blocking,
  t.sort_order
from
  (
    values
      (
        'Send the contract and right-to-work request'::varchar(200),
        'Issue the contract for signature and collect right-to-work evidence before day one.'::text,
        'compliance'::varchar(60),
        -14,
        true,
        10
      ),
      (
        'Order laptop and access badge',
        'Raise the IT ticket so the kit is on the desk before they arrive.',
        'equipment',
        -7,
        true,
        20
      ),
      (
        'Create accounts and add to the right groups',
        'Email, chat, code and the tools their team actually uses.',
        'access',
        -2,
        true,
        30
      ),
      (
        'Day one welcome and office tour',
        'Meet the team, find the coffee, learn the fire exits.',
        'welcome',
        0,
        false,
        40
      ),
      (
        'Payroll and benefits enrolment',
        'Bank details, pension and benefits elections.',
        'payroll',
        1,
        true,
        50
      ),
      (
        'Assign a buddy and book the first one-to-one',
        'Someone outside their reporting line to ask the silly questions.',
        'welcome',
        2,
        false,
        60
      ),
      (
        'Complete mandatory training',
        'Security awareness, data protection and the code of conduct.',
        'compliance',
        14,
        true,
        70
      ),
      (
        'Set first-quarter goals',
        'Three objectives, agreed with their manager.',
        'performance',
        21,
        false,
        80
      ),
      (
        'Thirty day check-in',
        'How is it going, honestly.',
        'welcome',
        30,
        false,
        90
      ),
      (
        'Probation review',
        'Confirm the probation outcome in writing.',
        'performance',
        90,
        true,
        100
      )
  ) as t (
    title,
    description,
    category,
    offset_days,
    is_blocking,
    sort_order
  )
where
  not exists (
    select
      1
    from
      hr.onboarding_tasks o
    where
      o.employee_id is null
      and o.title = t.title
  );

revoke all on hr.onboarding_tasks_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.onboarding_tasks_template to "x-admin";

comment on view hr.onboarding_tasks_template is '{"type": "template", "name": "Onboarding Checklist", "description": "The ten standard onboarding tasks. Apply to hr.onboarding_tasks to create the master checklist that every new hire is given a copy of.", "target_table": "onboarding_tasks"}';

-- Dynamic: next leave year, for everyone still here, carrying over
-- whatever the policy allows.
create or replace view hr.next_year_balances_template
with
  (security_invoker = true) as
select
  e.id as employee_id,
  lt.id as leave_type_id,
  (
    extract(
      year
      from
        current_date
    ) + 1
  )::integer as leave_year,
  case
    when e.fte < 100 then round((lt.default_allowance * e.fte / 100)::numeric, 1)
    else lt.default_allowance
  end as entitlement,
  least(coalesce(b.remaining, 0), lt.carry_over_limit) as carried_over
from
  hr.employees e
  cross join hr.leave_types lt
  left join hr.leave_balances b on b.employee_id = e.id
  and b.leave_type_id = lt.id
  and b.leave_year = extract(
    year
    from
      current_date
  )
where
  e.employment_status <> 'terminated'
  and lt.is_active
  and lt.default_allowance > 0
  and not exists (
    select
      1
    from
      hr.leave_balances x
    where
      x.employee_id = e.id
      and x.leave_type_id = lt.id
      and x.leave_year = extract(
        year
        from
          current_date
      ) + 1
  );

revoke all on hr.next_year_balances_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.next_year_balances_template to "x-admin";

comment on view hr.next_year_balances_template is '{"type": "template", "name": "Next Year Leave Balances", "description": "A fresh balance for every active employee and leave type, pro-rated for part-timers and carrying over up to the policy limit. Apply to hr.leave_balances at the leave-year rollover.", "target_table": "leave_balances"}';

-- Dynamic: open a review for everyone who should be in the live
-- cycle but is not yet.
create or replace view hr.cycle_reviews_template
with
  (security_invoker = true) as
select
  c.id as cycle_id,
  e.id as employee_id,
  e.manager_id as reviewer_id,
  'not_started'::hr.review_status as status
from
  hr.performance_cycles c
  cross join hr.employees e
where
  c.status in ('self_assessment', 'manager_review')
  and e.employment_status = 'active'
  and e.hire_date <= c.period_start
  and not exists (
    select
      1
    from
      hr.performance_reviews r
    where
      r.cycle_id = c.id
      and r.employee_id = e.id
  );

revoke all on hr.cycle_reviews_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.cycle_reviews_template to "x-admin";

comment on view hr.cycle_reviews_template is '{"type": "template", "name": "Open Cycle Reviews", "description": "A review for every active employee who joined before the cycle started and does not have one yet. Apply to hr.performance_reviews when a cycle opens.", "target_table": "performance_reviews"}';

----------------------------------------------------------------
-- Views as resources
--
-- Not every resource has to be a table. These two are plain views
-- with the same comment JSON shape a table uses, so they show up in
-- the sidebar and get their own layouts — read-only by construction,
-- because a view with no INSTEAD OF trigger cannot be written to.
----------------------------------------------------------------
create or replace view hr.org_chart
with
  (security_invoker = true) as
select
  e.id,
  e.manager_id,
  e.name,
  e.employee_number,
  e.work_email,
  e.avatar,
  p.title as job_title,
  d.name as department,
  l.name as location,
  jl.code as level,
  e.employment_status,
  e.direct_report_count,
  e.tenure_months,
  m.name as reports_to
from
  hr.employees e
  left join hr.employees m on m.id = e.manager_id
  left join hr.positions p on p.id = e.position_id
  left join hr.departments d on d.id = e.department_id
  left join hr.locations l on l.id = e.location_id
  left join hr.job_levels jl on jl.id = e.level_id
where
  e.employment_status <> 'terminated';

revoke all on hr.org_chart
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.org_chart to "x-admin",
  "people_manager",
  "recruiter",
  "user";

comment on view hr.org_chart is '{
    "icon": "Network",
    "name": "Org Chart",
    "description": "Everyone still with the company, arranged by who reports to whom.",
    "collapsible_group": "People",
    "display": "block",
    "primary_view": "tree",
    "views": [
        {
            "id": "tree",
            "name": "Reporting Lines",
            "type": "tree",
            "parent": "manager_id",
            "title": "name",
            "secondary": "job_title"
        },
        {
            "id": "list",
            "name": "Flat List",
            "type": "list",
            "title": "name",
            "description": "job_title",
            "field_1": "department",
            "field_2": "reports_to"
        }
    ],
    "filter_presets": [
        {"id": "managers", "name": "Managers", "filters": [{"id": "direct_report_count", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "sections": [
            {"id": "person", "title": "Person", "fields": ["name", "employee_number", "work_email", "job_title", "level"]},
            {"id": "placement", "title": "Placement", "fields": ["department", "location", "reports_to", "direct_report_count"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}]
    }
}';

create or replace view hr.team_directory
with
  (security_invoker = true) as
select
  e.id,
  e.name,
  e.avatar,
  e.work_email,
  e.phone,
  p.title as job_title,
  p.job_family,
  d.name as department,
  l.name as location,
  l.country,
  e.work_mode,
  e.skills,
  e.bio,
  e.hire_date,
  e.tenure_months
from
  hr.employees e
  left join hr.positions p on p.id = e.position_id
  left join hr.departments d on d.id = e.department_id
  left join hr.locations l on l.id = e.location_id
where
  e.employment_status in ('active', 'on_leave', 'onboarding');

revoke all on hr.team_directory
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.team_directory to "x-admin",
  "people_manager",
  "recruiter",
  "user";

comment on view hr.team_directory is '{
    "icon": "Contact",
    "name": "Directory",
    "description": "The company directory — who does what, and where.",
    "collapsible_group": "People",
    "display": "block",
    "primary_view": "gallery",
    "views": [
        {
            "id": "gallery",
            "name": "Faces",
            "type": "gallery",
            "cover": "avatar",
            "title": "name",
            "description": "job_title",
            "badge": "department"
        },
        {
            "id": "list",
            "name": "Contact List",
            "type": "list",
            "title": "name",
            "description": "job_title",
            "field_1": "department",
            "field_2": "work_email"
        }
    ],
    "filter_presets": [
        {"id": "remote", "name": "Remote", "filters": [{"id": "work_mode", "value": "remote", "operator": "eq"}]},
        {"id": "engineering", "name": "Engineering", "filters": [{"id": "job_family", "value": "engineering", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "person", "title": "Person", "fields": ["name", "job_title", "department", "location", "work_mode"]},
            {"id": "contact", "title": "Contact", "fields": ["work_email", "phone"]},
            {"id": "about", "title": "About", "collapsible": true, "fields": ["bio", "skills", "hire_date", "tenure_months"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}]
    }
}';

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view hr.headcount_report
with
  (security_invoker = true) as
select
  d.id,
  d.name as department,
  d.code,
  parent.name as parent_department,
  head.name as department_head,
  d.headcount,
  count(e.id) filter (
    where
      e.employment_status = 'active'
  ) as active,
  count(e.id) filter (
    where
      e.employment_status = 'onboarding'
  ) as onboarding,
  count(e.id) filter (
    where
      e.employment_status in ('notice_period', 'terminated')
  ) as leaving,
  count(e.id) filter (
    where
      e.employment_type = 'contractor'
  ) as contractors,
  round(avg(e.tenure_months), 1) as average_tenure_months,
  round(sum(e.fte)::numeric / 100, 2) as total_fte,
  d.annual_budget,
  d.open_positions,
  (
    select
      count(*)
    from
      hr.job_openings o
    where
      o.department_id = d.id
      and o.status = 'open'
  ) as live_openings
from
  hr.departments d
  left join hr.departments parent on parent.id = d.parent_id
  left join hr.employees head on head.id = d.head_id
  left join hr.employees e on e.department_id = d.id
group by
  d.id,
  d.name,
  d.code,
  parent.name,
  head.name,
  d.headcount,
  d.annual_budget,
  d.open_positions;

revoke all on hr.headcount_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.headcount_report to "x-admin",
  "people_manager";

-- `template: true` — upload supabase/examples/templates/headcount_report.hbs
-- to the `report-templates` bucket at key `hr/headcount_report.hbs`
-- (as "x-admin") to enable the "Print Report" button.
comment on view hr.headcount_report is '{"type": "report", "name": "Headcount Report", "description": "Headcount, tenure, FTE and open roles by department", "template": true}';

create or replace view hr.leave_report
with
  (security_invoker = true) as
select
  b.id,
  e.name as employee,
  e.employee_number,
  d.name as department,
  m.name as manager,
  lt.name as leave_type,
  b.leave_year,
  b.entitlement,
  b.carried_over,
  b.taken,
  b.pending,
  b.remaining,
  case
    when (b.entitlement + b.carried_over) > 0 then round(
      100.0 * b.taken / (b.entitlement + b.carried_over),
      1
    )
    else 0
  end as used_percent,
  (
    select
      count(*)
    from
      hr.leave_requests r
    where
      r.employee_id = b.employee_id
      and r.leave_type_id = b.leave_type_id
      and extract(
        year
        from
          r.start_date
      ) = b.leave_year
  ) as request_count,
  (
    select
      min(r.start_date)
    from
      hr.leave_requests r
    where
      r.employee_id = b.employee_id
      and r.status in ('pending', 'approved')
      and r.start_date >= current_date
  ) as next_absence
from
  hr.leave_balances b
  join hr.employees e on e.id = b.employee_id
  join hr.leave_types lt on lt.id = b.leave_type_id
  left join hr.departments d on d.id = e.department_id
  left join hr.employees m on m.id = e.manager_id;

revoke all on hr.leave_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.leave_report to "x-admin",
  "people_manager";

comment on view hr.leave_report is '{"type": "report", "name": "Leave Report", "description": "Entitlement, taken, pending and remaining per person and leave type"}';

create or replace view hr.performance_report
with
  (security_invoker = true) as
select
  r.id,
  c.name as cycle,
  c.status as cycle_status,
  e.name as employee,
  e.employee_number,
  d.name as department,
  jl.code as level,
  rev.name as reviewer,
  r.status,
  r.rating,
  r.overall_score,
  r.promotion_recommended,
  r.self_submitted_at,
  r.shared_at,
  r.acknowledged_at,
  (
    select
      count(*)
    from
      hr.goals g
    where
      g.employee_id = r.employee_id
      and g.cycle_id = r.cycle_id
  ) as goals_set,
  (
    select
      round(avg(g.progress)::numeric, 0)
    from
      hr.goals g
    where
      g.employee_id = r.employee_id
      and g.cycle_id = r.cycle_id
  ) as average_goal_progress
from
  hr.performance_reviews r
  join hr.performance_cycles c on c.id = r.cycle_id
  join hr.employees e on e.id = r.employee_id
  left join hr.employees rev on rev.id = r.reviewer_id
  left join hr.departments d on d.id = e.department_id
  left join hr.job_levels jl on jl.id = e.level_id;

revoke all on hr.performance_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.performance_report to "x-admin";

comment on view hr.performance_report is '{"type": "report", "name": "Performance Report", "description": "Ratings, progress and promotion recommendations per cycle"}';

create or replace view hr.hiring_report
with
  (security_invoker = true) as
select
  o.id,
  o.code,
  o.title,
  d.name as department,
  l.name as location,
  o.status,
  o.headcount,
  o.filled_count,
  o.applicant_count,
  count(c.id) filter (
    where
      c.stage = 'screening'
  ) as screening,
  count(c.id) filter (
    where
      c.stage = 'interviewing'
  ) as interviewing,
  count(c.id) filter (
    where
      c.stage = 'offer'
  ) as at_offer,
  count(c.id) filter (
    where
      c.stage = 'hired'
  ) as hired,
  count(c.id) filter (
    where
      c.stage = 'rejected'
  ) as rejected,
  round(
    100.0 * count(c.id) filter (
      where
        c.stage = 'hired'
    ) / nullif(count(c.id), 0),
    1
  ) as conversion_rate,
  round(
    avg(c.decision_on - c.applied_on) filter (
      where
        c.stage = 'hired'
    ),
    1
  ) as average_days_to_hire,
  o.opened_on,
  o.target_start_on,
  hm.name as hiring_manager
from
  hr.job_openings o
  left join hr.departments d on d.id = o.department_id
  left join hr.locations l on l.id = o.location_id
  left join hr.employees hm on hm.id = o.hiring_manager_id
  left join hr.candidates c on c.opening_id = o.id
group by
  o.id,
  o.code,
  o.title,
  d.name,
  l.name,
  o.status,
  o.headcount,
  o.filled_count,
  o.applicant_count,
  o.opened_on,
  o.target_start_on,
  hm.name;

revoke all on hr.hiring_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.hiring_report to "x-admin",
  "recruiter";

comment on view hr.hiring_report is '{"type": "report", "name": "Hiring Report", "description": "Funnel, conversion and time to hire per opening"}';

create or replace view hr.training_report
with
  (security_invoker = true) as
select
  c.id,
  c.code,
  c.title as course,
  c.format,
  c.provider,
  c.is_mandatory,
  c.enrollment_count,
  c.completion_count,
  round(
    100.0 * c.completion_count / nullif(c.enrollment_count, 0),
    1
  ) as completion_rate,
  c.average_rating,
  round(avg(e.score)::numeric, 1) as average_score,
  round(c.cost * c.enrollment_count, 2) as total_spend,
  count(e.id) filter (
    where
      e.expires_on is not null
      and e.expires_on < current_date + 90
  ) as expiring_soon
from
  hr.training_courses c
  left join hr.training_enrollments e on e.course_id = c.id
group by
  c.id,
  c.code,
  c.title,
  c.format,
  c.provider,
  c.is_mandatory,
  c.enrollment_count,
  c.completion_count,
  c.average_rating,
  c.cost;

revoke all on hr.training_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.training_report to "x-admin",
  "people_manager";

comment on view hr.training_report is '{"type": "report", "name": "Training Report", "description": "Uptake, completion, spend and expiring certifications per course"}';

----------------------------------------------------------------
-- Materialized view AS A RESOURCE
--
-- Not a report this time: the comment uses the resource shape, so
-- the monthly headcount snapshot appears in the sidebar with its own
-- list layout and filter presets. Materialized views cannot take
-- security_invoker, so access is grants only.
----------------------------------------------------------------
create materialized view hr.headcount_snapshot as
select
  to_char(m.month, 'YYYY-MM') as month,
  m.month::date as month_start,
  count(*) filter (
    where
      e.hire_date <= (m.month + interval '1 month - 1 day')::date
      and (
        e.termination_date is null
        or e.termination_date > (m.month + interval '1 month - 1 day')::date
      )
  ) as headcount,
  count(*) filter (
    where
      date_trunc('month', e.hire_date) = m.month
  ) as joiners,
  count(*) filter (
    where
      date_trunc('month', e.termination_date) = m.month
  ) as leavers,
  round(
    100.0 * count(*) filter (
      where
        date_trunc('month', e.termination_date) = m.month
    ) / nullif(
      count(*) filter (
        where
          e.hire_date <= (m.month + interval '1 month - 1 day')::date
          and (
            e.termination_date is null
            or e.termination_date > (m.month + interval '1 month - 1 day')::date
          )
      ),
      0
    ),
    2
  ) as attrition_rate
from
  generate_series(
    date_trunc('month', current_date) - interval '11 months',
    date_trunc('month', current_date),
    interval '1 month'
  ) as m (month)
  cross join hr.employees e
group by
  m.month
order by
  m.month desc;

create unique index idx_hr_headcount_snapshot_month on hr.headcount_snapshot (month);

revoke all on hr.headcount_snapshot
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.headcount_snapshot to "x-admin",
  "people_manager";

comment on materialized view hr.headcount_snapshot is '{
    "icon": "ChartNoAxesCombined",
    "name": "Headcount Snapshot",
    "description": "Precomputed monthly headcount, joiners, leavers and attrition. Refresh with: refresh materialized view concurrently hr.headcount_snapshot;",
    "collapsible_group": "Insights",
    "display": "block",
    "primary_view": "list",
    "views": [
        {
            "id": "list",
            "name": "By Month",
            "type": "list",
            "title": "month",
            "description": "headcount",
            "field_1": "joiners",
            "field_2": "leavers"
        }
    ],
    "filter_presets": [
        {"id": "attrition", "name": "Months With Leavers", "filters": [{"id": "leavers", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "sections": [
            {"id": "period", "title": "Period", "fields": ["month", "month_start"]},
            {"id": "movement", "title": "Movement", "fields": ["headcount", "joiners", "leavers", "attrition_rate"]}
        ]
    },
    "query": {
        "sort": [{"id": "month", "desc": true}]
    }
}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
create or replace view hr.headcount_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'users' as icon,
  'people employed' as label
from
  hr.employees
where
  employment_status not in ('terminated', 'applicant');

create or replace view hr.joiners_leavers_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      hire_date >= current_date - 90
  ) as primary,
  count(*) filter (
    where
      termination_date >= current_date - 90
  ) as secondary,
  'Joined (90d)' as primary_label,
  'Left (90d)' as secondary_label
from
  hr.employees;

create or replace view hr.leave_utilisation_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * coalesce(sum(taken), 0) / nullif(sum(entitlement + carried_over), 0),
    1
  ) as percent
from
  hr.leave_balances
where
  leave_year = extract(
    year
    from
      current_date
  );

create or replace view hr.workforce_progress
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      employment_status = 'active'
  ) as current,
  count(*) filter (
    where
      employment_status <> 'terminated'
  ) as total,
  json_build_array(
    json_build_object(
      'label',
      'Onboarding',
      'value',
      count(*) filter (
        where
          employment_status = 'onboarding'
      )
    ),
    json_build_object(
      'label',
      'Active',
      'value',
      count(*) filter (
        where
          employment_status = 'active'
      )
    ),
    json_build_object(
      'label',
      'On leave',
      'value',
      count(*) filter (
        where
          employment_status = 'on_leave'
      )
    ),
    json_build_object(
      'label',
      'Notice',
      'value',
      count(*) filter (
        where
          employment_status = 'notice_period'
      )
    )
  ) as segments
from
  hr.employees;

create or replace view hr.headcount_by_family_overview
with
  (security_invoker = true) as
select
  count(e.id) as value,
  'Headcount' as label,
  'users' as icon,
  json_build_array(
    json_build_object(
      'label',
      'Engineering',
      'value',
      count(e.id) filter (
        where
          p.job_family = 'engineering'
      ),
      'variant',
      'info'
    ),
    json_build_object(
      'label',
      'Sales',
      'value',
      count(e.id) filter (
        where
          p.job_family = 'sales'
      ),
      'variant',
      'success'
    ),
    json_build_object(
      'label',
      'Operations',
      'value',
      count(e.id) filter (
        where
          p.job_family = 'operations'
      ),
      'variant',
      'secondary'
    ),
    json_build_object(
      'label',
      'Everything else',
      'value',
      count(e.id) filter (
        where
          p.job_family not in ('engineering', 'sales', 'operations')
          or p.job_family is null
      ),
      'variant',
      'default'
    )
  ) as breakdown
from
  hr.employees e
  left join hr.positions p on p.id = e.position_id
where
  e.employment_status not in ('terminated', 'applicant');

create or replace view hr.people_pulse
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Headcount',
      'value',
      count(*) filter (
        where
          employment_status not in ('terminated', 'applicant')
      ),
      'icon',
      'users'
    ),
    json_build_object(
      'label',
      'Onboarding',
      'value',
      count(*) filter (
        where
          employment_status = 'onboarding'
      ),
      'icon',
      'user-plus'
    ),
    json_build_object(
      'label',
      'Avg tenure (mo)',
      'value',
      round(
        coalesce(
          avg(tenure_months) filter (
            where
              employment_status <> 'terminated'
          ),
          0
        )
      ),
      'icon',
      'clock'
    ),
    json_build_object(
      'label',
      'Leave pending',
      'value',
      (
        select
          count(*)
        from
          hr.leave_requests
        where
          status = 'pending'
      ),
      'icon',
      'plane'
    ),
    json_build_object(
      'label',
      'Open roles',
      'value',
      (
        select
          count(*)
        from
          hr.job_openings
        where
          status = 'open'
      ),
      'icon',
      'door-open'
    ),
    json_build_object(
      'label',
      'Reviews due',
      'value',
      (
        select
          count(*)
        from
          hr.performance_reviews
        where
          status in (
            'not_started',
            'self_assessment',
            'manager_review'
          )
      ),
      'icon',
      'clipboard-check'
    )
  ) as metrics
from
  hr.employees;

create or replace view hr.recent_joiners
with
  (security_invoker = true) as
select
  e.name,
  p.title as job_title,
  d.name as department,
  to_char(e.hire_date, 'Mon DD') as started,
  '/hr/resource/employees/' || e.id || '/detail' as link
from
  hr.employees e
  left join hr.positions p on p.id = e.position_id
  left join hr.departments d on d.id = e.department_id
where
  e.hire_date >= current_date - 90
order by
  e.hire_date desc
limit
  10;

create or replace view hr.upcoming_absences
with
  (security_invoker = true) as
select
  e.name,
  lt.name as leave_type,
  r.working_days as days,
  to_char(r.start_date, 'Mon DD') as starts,
  '/hr/resource/leave_requests/' || r.id || '/detail' as link
from
  hr.leave_requests r
  join hr.employees e on e.id = r.employee_id
  join hr.leave_types lt on lt.id = r.leave_type_id
where
  r.status in ('approved', 'pending')
  and r.start_date >= current_date
order by
  r.start_date asc
limit
  10;

create or replace view hr.department_scorecard
with
  (security_invoker = true) as
select
  d.name as department,
  d.headcount,
  count(o.id) filter (
    where
      o.status = 'open'
  ) as open_roles,
  round(avg(e.tenure_months), 0) as avg_tenure,
  round(coalesce(sum(b.taken), 0), 1) as leave_taken,
  '/hr/resource/departments/' || d.id || '/detail' as link
from
  hr.departments d
  left join hr.employees e on e.department_id = d.id
  and e.employment_status <> 'terminated'
  left join hr.job_openings o on o.department_id = d.id
  left join hr.leave_balances b on b.employee_id = e.id
  and b.leave_year = extract(
    year
    from
      current_date
  )
group by
  d.id,
  d.name,
  d.headcount
order by
  d.headcount desc
limit
  10;

create or replace view hr.leave_approval_queue
with
  (security_invoker = true) as
select
  e.name || ' — ' || lt.name as title,
  r.working_days || ' day(s) from ' || to_char(r.start_date, 'Mon DD') as description,
  'plane' as icon,
  'warning' as variant,
  '/hr/resource/leave_requests/' || r.id || '/detail' as link
from
  hr.leave_requests r
  join hr.employees e on e.id = r.employee_id
  join hr.leave_types lt on lt.id = r.leave_type_id
where
  r.status = 'pending'
order by
  r.submitted_at asc
limit
  10;

create or replace view hr.probation_watchlist
with
  (security_invoker = true) as
select
  e.name as title,
  coalesce(d.name, 'No department') as description,
  'circle-alert' as icon,
  'destructive' as variant,
  e.employment_status as field_1,
  to_char(e.probation_end_date, 'Mon DD') as field_2,
  '/hr/resource/employees/' || e.id || '/detail' as link
from
  hr.employees e
  left join hr.departments d on d.id = e.department_id
where
  e.probation_end_date is not null
  and e.probation_end_date between current_date - 7 and current_date  + 30
  and e.employment_status in ('onboarding', 'active')
order by
  e.probation_end_date asc
limit
  10;

create or replace view hr.recent_people_activity
with
  (security_invoker = true) as
select
  coalesce(u.name, 'People ops') as actor,
  case ev.event_type
    when 'hired' then 'welcomed'
    when 'onboarded' then 'onboarded'
    when 'promoted' then 'promoted'
    when 'transferred' then 'moved'
    when 'leave_taken' then 'booked leave for'
    when 'review_completed' then 'closed a review for'
    when 'training_completed' then 'trained'
    when 'terminated' then 'offboarded'
    else 'updated'
  end as action,
  e.name as entity,
  to_char(ev.occurred_at, 'Mon DD, YYYY') as date,
  '/hr/resource/employees/' || e.id || '/detail' as link
from
  hr.employee_events ev
  join hr.employees e on e.id = ev.employee_id
  left join hr.users u on u.id = ev.actor_id
order by
  ev.occurred_at desc
limit
  10;

create or replace view hr.longest_serving
with
  (security_invoker = true) as
select
  e.name,
  e.tenure_months as value,
  coalesce(p.title, 'No position') as label,
  '/hr/resource/employees/' || e.id || '/detail' as link
from
  hr.employees e
  left join hr.positions p on p.id = e.position_id
where
  e.employment_status <> 'terminated'
order by
  e.tenure_months desc
limit
  10;

create or replace view hr.open_roles_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'door-open' as icon,
  'open roles' as label
from
  hr.job_openings
where
  status = 'open';

create or replace view hr.review_completion_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'acknowledged'
  ) as primary,
  count(*) filter (
    where
      status <> 'acknowledged'
  ) as secondary,
  'Complete' as primary_label,
  'Outstanding' as secondary_label
from
  hr.performance_reviews;

create or replace view hr.training_completion_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        status = 'completed'
    ) / nullif(count(*), 0),
    1
  ) as percent
from
  hr.training_enrollments;

create or replace view hr.pending_timesheets_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'clock' as icon,
  'timesheets awaiting approval' as label
from
  hr.timesheet_entries
where
  status = 'submitted';

revoke all on hr.headcount_count,
hr.joiners_leavers_split,
hr.leave_utilisation_rate,
hr.workforce_progress,
hr.headcount_by_family_overview,
hr.people_pulse,
hr.recent_joiners,
hr.upcoming_absences,
hr.department_scorecard,
hr.leave_approval_queue,
hr.probation_watchlist,
hr.recent_people_activity,
hr.longest_serving,
hr.open_roles_count,
hr.review_completion_split,
hr.training_completion_rate,
hr.pending_timesheets_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.headcount_count,
  hr.joiners_leavers_split,
  hr.leave_utilisation_rate,
  hr.workforce_progress,
  hr.headcount_by_family_overview,
  hr.people_pulse,
  hr.recent_joiners,
  hr.upcoming_absences,
  hr.department_scorecard,
  hr.leave_approval_queue,
  hr.probation_watchlist,
  hr.recent_people_activity,
  hr.longest_serving,
  hr.review_completion_split,
  hr.training_completion_rate,
  hr.pending_timesheets_count to "x-admin",
  "people_manager";

grant
select
  on hr.open_roles_count to "x-admin",
  "people_manager",
  "recruiter";

comment on view hr.headcount_count is '{"type": "dashboard_widget", "name": "Headcount", "description": "Everyone currently employed", "widget_type": "card_1"}';

comment on view hr.joiners_leavers_split is '{"type": "dashboard_widget", "name": "Joiners vs Leavers", "description": "Movement over the last quarter", "widget_type": "card_2"}';

comment on view hr.leave_utilisation_rate is '{"type": "dashboard_widget", "name": "Leave Utilisation", "description": "Share of entitlement taken this leave year", "widget_type": "card_3"}';

comment on view hr.workforce_progress is '{"type": "dashboard_widget", "name": "Workforce", "description": "Where the headcount sits across employment states", "widget_type": "card_4"}';

comment on view hr.headcount_by_family_overview is '{"type": "dashboard_widget", "name": "Headcount By Function", "description": "Where the people are", "widget_type": "card_5"}';

comment on view hr.people_pulse is '{"type": "dashboard_widget", "name": "People Pulse", "description": "Headcount, leave, hiring and reviews at a glance", "widget_type": "card_6"}';

comment on view hr.recent_joiners is '{"type": "dashboard_widget", "name": "Recent Joiners", "description": "Everyone who started in the last 90 days", "widget_type": "table_1", "resource": "employees", "url": "/hr/resource/employees"}';

comment on view hr.upcoming_absences is '{"type": "dashboard_widget", "name": "Who Is Off Next", "description": "Approved and pending leave coming up", "widget_type": "table_1", "url": "/hr/resource/leave_requests"}';

comment on view hr.department_scorecard is '{"type": "dashboard_widget", "name": "Department Scorecard", "description": "Headcount, hiring and leave by department", "widget_type": "table_2", "url": "/hr/resource/departments"}';

comment on view hr.leave_approval_queue is '{"type": "dashboard_widget", "name": "Leave To Approve", "description": "Requests waiting on a decision", "widget_type": "list_1", "url": "/hr/resource/leave_requests"}';

comment on view hr.probation_watchlist is '{"type": "dashboard_widget", "name": "Probation Reviews Due", "description": "Probation periods ending in the next month", "widget_type": "list_2", "url": "/hr/resource/employees"}';

comment on view hr.recent_people_activity is '{"type": "dashboard_widget", "name": "Recent Activity", "description": "The latest movements across the people record", "widget_type": "list_3", "url": "/hr/resource/employees"}';

comment on view hr.longest_serving is '{"type": "dashboard_widget", "name": "Longest Serving", "description": "People ranked by months of service", "widget_type": "list_4", "url": "/hr/resource/employees"}';

comment on view hr.open_roles_count is '{"type": "dashboard_widget", "name": "Open Roles", "description": "Requisitions actively being recruited", "widget_type": "card_1", "resource": "job_openings"}';

comment on view hr.review_completion_split is '{"type": "dashboard_widget", "name": "Review Completion", "description": "Acknowledged reviews vs outstanding", "widget_type": "card_2", "resource": "performance_reviews"}';

comment on view hr.training_completion_rate is '{"type": "dashboard_widget", "name": "Training Completion", "description": "Share of enrollments finished", "widget_type": "card_3", "resource": "training_courses"}';

comment on view hr.pending_timesheets_count is '{"type": "dashboard_widget", "name": "Timesheets To Approve", "description": "Submitted entries awaiting sign-off", "widget_type": "card_1", "resource": "timesheet_entries"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
create or replace view hr.headcount_by_department_pie
with
  (security_invoker = true) as
select
  d.name as label,
  count(e.id) as value
from
  hr.departments d
  left join hr.employees e on e.department_id = d.id
  and e.employment_status <> 'terminated'
group by
  d.id,
  d.name
having
  count(e.id) > 0;

create or replace view hr.leave_by_type_bar
with
  (security_invoker = true) as
select
  lt.name as label,
  round(
    coalesce(sum(b.entitlement + b.carried_over), 0),
    1
  ) as entitlement,
  round(coalesce(sum(b.taken), 0), 1) as taken,
  round(coalesce(sum(b.remaining), 0), 1) as remaining
from
  hr.leave_types lt
  left join hr.leave_balances b on b.leave_type_id = lt.id
  and b.leave_year = extract(
    year
    from
      current_date
  )
group by
  lt.id,
  lt.name
order by
  taken desc;

create or replace view hr.headcount_trend_line
with
  (security_invoker = true) as
select
  to_char(month_start, 'Mon YY') as date,
  headcount,
  joiners,
  leavers
from
  hr.headcount_snapshot
order by
  month_start;

create or replace view hr.absence_composition_area
with
  (security_invoker = true) as
select
  to_char(date_trunc('week', r.start_date), 'Mon DD') as date,
  round(
    coalesce(
      sum(r.working_days) filter (
        where
          lt.code = 'AL'
      ),
      0
    ),
    1
  ) as annual_leave,
  round(
    coalesce(
      sum(r.working_days) filter (
        where
          lt.code = 'SICK'
      ),
      0
    ),
    1
  ) as sickness,
  round(
    coalesce(
      sum(r.working_days) filter (
        where
          lt.code not in ('AL', 'SICK')
      ),
      0
    ),
    1
  ) as other
from
  hr.leave_requests r
  join hr.leave_types lt on lt.id = r.leave_type_id
where
  r.status in ('approved', 'taken')
  and r.start_date >= current_date - 84
group by
  date_trunc('week', r.start_date)
order by
  date_trunc('week', r.start_date);

create or replace view hr.department_scorecard_radar
with
  (security_invoker = true) as
select
  d.name as metric,
  d.headcount,
  count(o.id) filter (
    where
      o.status = 'open'
  ) as open_roles,
  coalesce(round(avg(e.tenure_months)), 0) as avg_tenure
from
  hr.departments d
  left join hr.employees e on e.department_id = d.id
  and e.employment_status <> 'terminated'
  left join hr.job_openings o on o.department_id = d.id
group by
  d.id,
  d.name,
  d.headcount
order by
  d.headcount desc;

create or replace view hr.employees_by_type_pie
with
  (security_invoker = true) as
select
  employment_type::text as label,
  count(*) as value
from
  hr.employees
where
  employment_status <> 'terminated'
group by
  employment_type;

create or replace view hr.candidates_by_stage_pie
with
  (security_invoker = true) as
select
  stage::text as label,
  count(*) as value
from
  hr.candidates
group by
  stage;

create or replace view hr.reviews_by_rating_bar
with
  (security_invoker = true) as
select
  coalesce(rating::text, 'unrated') as label,
  count(*) as reviews,
  count(*) filter (
    where
      promotion_recommended
  ) as promotions
from
  hr.performance_reviews
group by
  rating
order by
  reviews desc;

create or replace view hr.training_uptake_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', e.enrolled_on), 'Mon YY') as date,
  count(*) as enrolled,
  count(*) filter (
    where
      e.status = 'completed'
  ) as completed
from
  hr.training_enrollments e
where
  e.enrolled_on >= current_date - 365
group by
  date_trunc('month', e.enrolled_on)
order by
  date_trunc('month', e.enrolled_on);

revoke all on hr.headcount_by_department_pie,
hr.leave_by_type_bar,
hr.headcount_trend_line,
hr.absence_composition_area,
hr.department_scorecard_radar,
hr.employees_by_type_pie,
hr.candidates_by_stage_pie,
hr.reviews_by_rating_bar,
hr.training_uptake_line
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on hr.headcount_by_department_pie,
  hr.leave_by_type_bar,
  hr.headcount_trend_line,
  hr.absence_composition_area,
  hr.department_scorecard_radar,
  hr.employees_by_type_pie,
  hr.reviews_by_rating_bar,
  hr.training_uptake_line to "x-admin",
  "people_manager";

grant
select
  on hr.candidates_by_stage_pie to "x-admin",
  "recruiter";

comment on view hr.headcount_by_department_pie is '{"type": "chart", "name": "Headcount By Department", "description": "Where the people sit", "chart_type": "pie"}';

comment on view hr.leave_by_type_bar is '{"type": "chart", "name": "Leave By Type", "description": "Entitlement, taken and remaining per policy", "chart_type": "bar"}';

comment on view hr.headcount_trend_line is '{"type": "chart", "name": "Headcount Trend", "description": "Headcount, joiners and leavers over twelve months", "chart_type": "line"}';

comment on view hr.absence_composition_area is '{"type": "chart", "name": "Absence Composition", "description": "Weekly days off split by reason", "chart_type": "area"}';

comment on view hr.department_scorecard_radar is '{"type": "chart", "name": "Department Scorecard", "description": "Size, hiring and tenure per department", "chart_type": "radar"}';

comment on view hr.employees_by_type_pie is '{"type": "chart", "name": "Employment Types", "description": "Permanent, part time and contract mix", "chart_type": "pie", "resource": "employees"}';

comment on view hr.candidates_by_stage_pie is '{"type": "chart", "name": "Pipeline By Stage", "description": "Where candidates are in the funnel", "chart_type": "pie", "resource": "candidates"}';

comment on view hr.reviews_by_rating_bar is '{"type": "chart", "name": "Rating Distribution", "description": "Review ratings and promotion recommendations", "chart_type": "bar", "resource": "performance_reviews"}';

comment on view hr.training_uptake_line is '{"type": "chart", "name": "Training Uptake", "description": "Enrollments against completions by month", "chart_type": "line", "resource": "training_courses"}';

----------------------------------------------------------------
-- Audit triggers (INSERT/UPDATE fire AFTER, DELETE must fire BEFORE)
--
-- hr.employee_events is left out: it is already an audit trail.
----------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'locations', 'departments', 'job_levels', 'positions', 'employees',
    'employee_compensation', 'employee_documents', 'job_changes',
    'leave_types', 'leave_balances', 'leave_requests', 'holidays',
    'timesheet_entries', 'performance_cycles', 'performance_reviews',
    'goals', 'training_courses', 'training_enrollments', 'job_openings',
    'candidates', 'interviews', 'onboarding_tasks'
  ]
  loop
    execute format(
      'create trigger audit_hr_%1$s_insert after insert on hr.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
    execute format(
      'create trigger audit_hr_%1$s_update after update on hr.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
    execute format(
      'create trigger audit_hr_%1$s_delete before delete on hr.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
  end loop;
end;
$$;

create trigger audit_hr_hr_settings_insert
after insert on hr.hr_settings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_hr_settings_update
after update on hr.hr_settings for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
--
-- "People operations" resolves as everyone who can update
-- hr.employees — held by "x-admin" alone. Line managers are found
-- through the org chart instead: a request notifies the approver on
-- it, which is the manager the request was raised against.
----------------------------------------------------------------
create or replace function hr.trg_leave_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_employee   text;
    v_approver   uuid;
    v_owner      uuid;
    v_type       text;
    v_title      text;
    v_body       text;
begin
    select e.name, e.user_id into v_employee, v_owner from hr.employees e where e.id = new.employee_id;

    if new.approver_id is not null then
        select e.user_id into v_approver from hr.employees e where e.id = new.approver_id;
    end if;

    if new.status = 'pending' and (tg_op = 'INSERT' or old.status <> 'pending') then
        v_type  := 'hr_leave_requested';
        v_title := 'Leave request to approve';
        v_body  := v_employee || ' has asked for ' || new.working_days || ' day(s) from ' || to_char(new.start_date, 'Mon DD') || '.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('hr', 'employees', 'update') || array[v_approver],
            null
        );
    elsif new.status in ('approved', 'rejected') and old.status <> new.status then
        v_type  := 'hr_leave_' || new.status;
        v_title := case when new.status = 'approved' then 'Leave approved' else 'Leave declined' end;
        v_body  := new.working_days || ' day(s) from ' || to_char(new.start_date, 'Mon DD')
                   || coalesce(' — ' || new.decision_note, '');
        v_recipients := array_remove(array[v_owner], null);
    else
        return new;
    end if;

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object('request_id', new.id, 'employee_id', new.employee_id, 'days', new.working_days),
        '/hr/resource/leave_requests/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists leave_notify on hr.leave_requests;

create trigger leave_notify
after insert or update of status on hr.leave_requests for each row
execute function hr.trg_leave_notify ();

create or replace function hr.trg_reviews_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.status <> 'shared' or (tg_op = 'UPDATE' and old.status = 'shared') then
        return new;
    end if;

    select array_remove(array[e.user_id], null) into v_recipients
    from hr.employees e
    where e.id = new.employee_id;

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'hr_review_shared',
        'Your review is ready',
        'Your manager has shared your review. Have a read, then acknowledge it.',
        v_recipients,
        jsonb_build_object('review_id', new.id, 'cycle_id', new.cycle_id, 'rating', new.rating),
        '/hr/resource/performance_reviews/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists reviews_notify on hr.performance_reviews;

create trigger reviews_notify
after insert or update of status on hr.performance_reviews for each row
execute function hr.trg_reviews_notify ();

create or replace function hr.trg_onboarding_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_employee   text;
begin
    if tg_op = 'UPDATE' or new.employee_id is null then
        return new;
    end if;

    select e.name into v_employee from hr.employees e where e.id = new.employee_id;

    select array_remove(array[owner.user_id], null) into v_recipients
    from hr.employees owner
    where owner.id = new.owner_id;

    if array_length(v_recipients, 1) is null then
        v_recipients := supasheet.get_users_with_table_privilege('hr', 'employees', 'update');
    end if;

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'hr_onboarding_task',
        'Onboarding task assigned',
        new.title || coalesce(' — for ' || v_employee, ''),
        v_recipients,
        jsonb_build_object('task_id', new.id, 'employee_id', new.employee_id, 'due_on', new.due_on),
        '/hr/resource/onboarding_tasks/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists onboarding_notify on hr.onboarding_tasks;

create trigger onboarding_notify
after insert on hr.onboarding_tasks for each row
execute function hr.trg_onboarding_notify ();

create or replace function hr.trg_hr_comments_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.schema_name <> 'hr'
       or new.table_name not in ('employees', 'candidates', 'job_openings', 'performance_reviews') then
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('hr', new.table_name, 'update'),
        new.created_by
    );

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'hr_comment_added',
        'New comment on ' || new.table_name,
        left(new.content, 140),
        v_recipients,
        jsonb_build_object('record_id', new.record_id, 'table_name', new.table_name),
        '/hr/resource/' || new.table_name || '/' || new.record_id::text || '/comment'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists hr_comments_notify on supasheet.comments;

create trigger hr_comments_notify
after insert on supasheet.comments for each row
execute function hr.trg_hr_comments_notify ();

----------------------------------------------------------------
-- Private document storage
--
-- Contracts and right-to-work scans do not belong in the shared
-- `uploads` bucket, so this module brings its own. The policies
-- delegate to the same table privileges the rest of the module uses:
-- if your role cannot read hr.employee_documents, it cannot read the
-- objects behind them either, and there is only one place to change
-- that decision.
--
-- The bucket is private (public = false), so every read goes through
-- a signed URL.
----------------------------------------------------------------
insert into
  storage.buckets (id, name, public)
values
  ('hr-documents', 'hr-documents', false)
on conflict (id) do nothing;

drop policy if exists hr_documents_read on storage.objects;

create policy hr_documents_read on storage.objects for
select
  to authenticated using (
    bucket_id = 'hr-documents'
    and has_table_privilege(current_user, 'hr.employee_documents', 'select')
  );

drop policy if exists hr_documents_insert on storage.objects;

create policy hr_documents_insert on storage.objects for insert to authenticated
with
  check (
    bucket_id = 'hr-documents'
    and has_table_privilege(current_user, 'hr.employee_documents', 'insert')
  );

drop policy if exists hr_documents_update on storage.objects;

create policy hr_documents_update on storage.objects
for update
  to authenticated using (
    bucket_id = 'hr-documents'
    and has_table_privilege(current_user, 'hr.employee_documents', 'update')
  );

drop policy if exists hr_documents_delete on storage.objects;

create policy hr_documents_delete on storage.objects for delete to authenticated using (
  bucket_id = 'hr-documents'
  and has_table_privilege(current_user, 'hr.employee_documents', 'delete')
);

----------------------------------------------------------------
-- Refresh the metadata catalog (materialized views — NOT automatic)
----------------------------------------------------------------
select
  supasheet.refresh_metadata ();
