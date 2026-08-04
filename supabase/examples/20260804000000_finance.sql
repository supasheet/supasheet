-- ================================================================
-- Supasheet Example — "Finance" (general ledger and working capital)
-- ================================================================
-- A production-shaped finance back office: a chart of accounts and
-- cost centres, fiscal periods that lock, a double-entry journal,
-- receivables and payables with allocations, bank accounts and
-- reconciliation, employee expense claims, budgets against actuals,
-- and fixed assets with depreciation.
--
-- Demo data lives in supabase/examples/f_seed.sql — apply this file
-- first, then that one.
--
-- What makes this one different from the other examples: a ledger
-- has integrity rules that are not negotiable, and they are enforced
-- here rather than described.
--
--   - DOUBLE ENTRY. A journal cannot be posted unless its debits
--     equal its credits to the cent.
--   - PERIOD LOCKING. Nothing can be posted into a closed or locked
--     period, and closing a period with unposted drafts in it fails.
--   - IMMUTABILITY. A posted journal and its lines cannot be edited
--     or deleted by anyone, including the controller. The only way
--     back is a reversing entry, which is itself a journal.
--   - ALLOCATION LIMITS. A receipt cannot be allocated beyond the
--     invoice balance, and an invoice cannot be over-collected.
--   - Balances are derived from POSTED lines only, so a draft can
--     never move a number anybody reports on.
--
-- Everything the other modules cover is here too:
--   - Native-role RBAC with two custom roles ("accountant" and
--     "finance-auditor" — the finance-auditor holds SELECT on everything
--     and INSERT, UPDATE or DELETE on nothing, which is exactly what an audit
--     seat is)
--   - The "user" role is the EMPLOYEE submitting expense claims, and
--     sees only their own
--   - All six view layouts, every widget and chart contract, reports
--     with a Handlebars print template, a precomputed materialized
--     view surfaced as a browsable resource, templates, row actions,
--     four custom form shapes, notifications, audit logging,
--     per-resource comments, supasheet.configs entries and a private
--     `finance-documents` storage bucket for invoices and receipts
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260804000000_finance.sql \
--     -f supabase/examples/f_seed.sql
--
-- Requires the base Supasheet migrations. Add "finance" to
-- config.toml's `api.schemas` and `api.extra_search_path`, then
-- restart Supabase.
--
-- Not idempotent: re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists finance;

-------------------------------------------------------------------
-- Roles
--
--   x-admin     financial controller: everything, including closing
--               periods and posting adjustments
--   accountant  day-to-day finance: raises invoices and bills, takes
--               payments, drafts and posts journals, closes a period
--               once it is clean; cannot reopen a locked one and
--               cannot delete a journal
--   finance-auditor  read-only across the whole schema. No insert, no
--               update, no delete, anywhere — the grant list is the
--               entire control
--   user        THE EMPLOYEE: submits expense claims and sees their
--               own, plus the cost centres they can code them to
--
-- Assign a user to a custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "accountant"}'
--   where email = 'finance@example.com';
-------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'user') then
    create role "user" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'admin') then
    create role "admin" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'accountant') then
    create role "accountant" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'finance-auditor') then
    create role "finance-auditor" nologin;
  end if;
end;
$$;

grant "user",
"admin",
"accountant",
"finance-auditor" to authenticator;

grant authenticated to "user",
"admin",
"accountant",
"finance-auditor";

grant usage on schema finance to "x-admin",
"accountant",
"finance-auditor",
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
-- Enums
----------------------------------------------------------------
begin;

create type finance.account_type as enum(
  'asset',
  'liability',
  'equity',
  'revenue',
  'expense'
);

create type finance.normal_balance as enum('debit', 'credit');

create type finance.period_status as enum('future', 'open', 'closed', 'locked');

create type finance.journal_status as enum('draft', 'posted', 'reversed');

create type finance.journal_source as enum(
  'manual',
  'invoice',
  'bill',
  'receipt',
  'payment',
  'expense',
  'depreciation',
  'fx_revaluation',
  'opening_balance'
);

create type finance.journal_event_type as enum(
  'created',
  'line_changed',
  'posted',
  'reversed',
  'record_updated'
);

create type finance.invoice_status as enum(
  'draft',
  'sent',
  'partially_paid',
  'paid',
  'overdue',
  'void'
);

create type finance.bill_status as enum(
  'draft',
  'awaiting_approval',
  'approved',
  'partially_paid',
  'paid',
  'void'
);

create type finance.payment_method as enum(
  'bank_transfer',
  'card',
  'direct_debit',
  'cheque',
  'cash',
  'offset'
);

create type finance.payment_direction as enum('inbound', 'outbound');

create type finance.expense_status as enum(
  'draft',
  'submitted',
  'approved',
  'rejected',
  'reimbursed'
);

create type finance.expense_category as enum(
  'travel',
  'accommodation',
  'meals',
  'software',
  'hardware',
  'training',
  'entertainment',
  'other'
);

create type finance.bank_transaction_status as enum(
  'unreconciled',
  'matched',
  'reconciled',
  'ignored'
);

create type finance.asset_status as enum('in_service', 'idle', 'disposed', 'written_off');

create type finance.depreciation_method as enum('straight_line', 'reducing_balance', 'none');

create type finance.budget_status as enum('draft', 'approved', 'locked');

create type finance.customer_status as enum('active', 'on_hold', 'closed');

commit;

----------------------------------------------------------------
-- Users replica view
----------------------------------------------------------------
create or replace view finance.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on finance.users
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on finance.users to "x-admin",
  "accountant",
  "finance-auditor",
  "user";

----------------------------------------------------------------
-- Role helpers
----------------------------------------------------------------
create or replace function finance.is_finance_staff () returns boolean language sql stable
set
  search_path = '' as $$
  select pg_has_role(current_user, 'x-admin', 'member')
      or pg_has_role(current_user, 'accountant', 'member')
      or pg_has_role(current_user, 'finance-auditor', 'member');
$$;

revoke all on function finance.is_finance_staff ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.is_finance_staff () to "x-admin",
"accountant",
"finance-auditor",
"user";

----------------------------------------------------------------
-- Fiscal periods
--
-- The gate every posting goes through. A period that is closed or
-- locked will not accept a journal, and that check lives in one
-- function so invoices, bills, expenses and manual entries all hit
-- the same rule.
----------------------------------------------------------------
create table finance.fiscal_periods (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(80) not null,
  fiscal_year integer not null,
  period_number integer not null,
  starts_on date not null,
  ends_on date not null,
  status finance.period_status not null default 'future',
  closed_on date,
  closed_by uuid references supasheet.users (id) on delete set null,
  journal_count integer not null default 0,
  posted_total numeric(16, 2) not null default 0,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (fiscal_year, period_number),
  constraint periods_dates_ordered check (ends_on >= starts_on),
  constraint periods_number_range check (period_number between 1 and 12)
);

comment on column finance.fiscal_periods.status is '{
    "progress": true,
    "values": {
        "future": {"variant": "secondary", "icon": "CalendarClock"},
        "open": {"variant": "success", "icon": "LockOpen"},
        "closed": {"variant": "warning", "icon": "Lock"},
        "locked": {"variant": "destructive", "icon": "ShieldCheck"}
    }
}';

comment on table finance.fiscal_periods is '{
    "icon": "CalendarRange",
    "name": "Periods",
    "description": "The accounting calendar. Postings are only accepted into an open period.",
    "collapsible_group": "Ledger",
    "display": "block",
    "primary_view": "gantt",
    "detail": {
        "header": {"title": "name", "badges": ["status", "fiscal_year"]},
        "tabs": ["journals", "budgets"]
    },
    "views": [
        {
            "id": "gantt",
            "name": "Financial Year",
            "type": "gantt",
            "title": "name",
            "start_date": "starts_on",
            "end_date": "ends_on",
            "group": "status",
            "badge": "status"
        },
        {
            "id": "list",
            "name": "All Periods",
            "type": "list",
            "title": "name",
            "description": "code",
            "field_1": "status",
            "field_2": "posted_total"
        }
    ],
    "filter_presets": [
        {"id": "open", "name": "Open", "filters": [{"id": "status", "value": "open", "operator": "eq"}]},
        {"id": "closed", "name": "Closed", "filters": [{"id": "status", "value": ["closed", "locked"], "operator": "in"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "starts_on", "ends_on"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "fiscal_year", "period_number"]},
            {"id": "window", "title": "Window", "fields": ["starts_on", "ends_on", "status"]},
            {"id": "closure", "title": "Closure", "fields": {"read": ["closed_on", "closed_by", "journal_count", "posted_total"]}},
            {"id": "extras", "title": "Note", "collapsible": true, "fields": ["note"]}
        ]
    },
    "query": {
        "sort": [{"id": "starts_on", "desc": true}]
    }
}';

comment on column finance.fiscal_periods.posted_total is '{"name": "Posted", "aggregate": "sum"}';

revoke all on table finance.fiscal_periods
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
delete on table finance.fiscal_periods to "x-admin";

-- The accountant runs the close; only the controller can undo a lock,
-- which finance.periods_guard () enforces on the way through.
grant
select
,
update on table finance.fiscal_periods to "accountant";

grant
select
  on table finance.fiscal_periods to "finance-auditor";

create index idx_fin_periods_status on finance.fiscal_periods (status);

create index idx_fin_periods_window on finance.fiscal_periods (starts_on, ends_on);

alter table finance.fiscal_periods enable row level security;

create policy periods_select on finance.fiscal_periods for
select
  to authenticated using (true);

create policy periods_insert on finance.fiscal_periods for insert to authenticated
with
  check (true);

create policy periods_update on finance.fiscal_periods
for update
  to authenticated using (true)
with
  check (true);

create policy periods_delete on finance.fiscal_periods for delete to authenticated using (true);

-- Which period does this date fall in, and will it accept a posting?
create or replace function finance.period_for_date (p_date date) returns uuid language sql stable security definer
set
  search_path = '' as $$
  select id from finance.fiscal_periods where p_date between starts_on and ends_on limit 1;
$$;

revoke all on function finance.period_for_date (date)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.period_for_date (date) to "x-admin",
"accountant",
"finance-auditor",
"user";

----------------------------------------------------------------
-- Cost centres (self-referencing tree)
----------------------------------------------------------------
create table finance.cost_centers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  parent_id uuid references finance.cost_centers (id) on delete set null,
  code varchar(20) not null unique,
  name varchar(160) not null,
  description text,
  owner_email supasheet.EMAIL,
  is_active boolean not null default true,
  annual_budget numeric(16, 2) not null default 0,
  actual_spend numeric(16, 2) not null default 0,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint cost_centers_not_own_parent check (id <> parent_id)
);

comment on table finance.cost_centers is '{
    "icon": "Network",
    "name": "Cost Centres",
    "description": "Where spend is coded to, arranged as a tree.",
    "collapsible_group": "Ledger",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["code", "is_active"]},
        "tabs": ["journal_lines", "budgets", "expense_claims", "cost_centers"]
    },
    "views": [
        {
            "id": "tree",
            "name": "Cost Centre Tree",
            "type": "tree",
            "parent": "parent_id",
            "title": "name",
            "secondary": "code"
        },
        {
            "id": "list",
            "name": "All Cost Centres",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "code",
            "field_2": "actual_spend"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "overspent", "name": "Over Budget", "filters": [{"id": "actual_spend", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "parent_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "parent_id"]},
            {"id": "ownership", "title": "Ownership", "fields": ["owner_email", "is_active", "color"]},
            {"id": "money", "title": "Money", "fields": ["annual_budget"]},
            {"id": "actuals", "title": "Actuals", "fields": {"read": ["actual_spend"]}}
        ]
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "cost_centers", "on": "parent_id", "alias": "parent", "columns": ["name", "code"]}]
    }
}';

comment on column finance.cost_centers.annual_budget is '{"name": "Budget", "aggregate": "sum"}';

comment on column finance.cost_centers.actual_spend is '{"name": "Actual", "aggregate": "sum"}';

revoke all on table finance.cost_centers
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
delete on table finance.cost_centers to "x-admin";

grant
select
,
  insert,
update on table finance.cost_centers to "accountant";

grant
select
  on table finance.cost_centers to "finance-auditor",
  "user";

create index idx_fin_cost_centers_parent_id on finance.cost_centers (parent_id);

alter table finance.cost_centers enable row level security;

create policy cost_centers_select on finance.cost_centers for
select
  to authenticated using (true);

create policy cost_centers_insert on finance.cost_centers for insert to authenticated
with
  check (true);

create policy cost_centers_update on finance.cost_centers
for update
  to authenticated using (true)
with
  check (true);

create policy cost_centers_delete on finance.cost_centers for delete to authenticated using (true);

----------------------------------------------------------------
-- Chart of accounts (self-referencing tree)
----------------------------------------------------------------
create table finance.accounts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  parent_id uuid references finance.accounts (id) on delete set null,
  code varchar(20) not null unique,
  name varchar(160) not null,
  description text,
  account_type finance.account_type not null,
  normal_balance finance.normal_balance not null default 'debit',
  is_postable boolean not null default true,
  is_active boolean not null default true,
  is_bank_account boolean not null default false,
  currency varchar(3) not null default 'USD',
  opening_balance numeric(16, 2) not null default 0,
  debit_total numeric(16, 2) not null default 0,
  credit_total numeric(16, 2) not null default 0,
  current_balance numeric(16, 2) not null default 0,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint accounts_not_own_parent check (id <> parent_id)
);

comment on column finance.accounts.account_type is '{
    "progress": false,
    "values": {
        "asset": {"variant": "info", "icon": "Landmark"},
        "liability": {"variant": "warning", "icon": "CreditCard"},
        "equity": {"variant": "default", "icon": "PiggyBank"},
        "revenue": {"variant": "success", "icon": "TrendingUp"},
        "expense": {"variant": "destructive", "icon": "TrendingDown"}
    }
}';

comment on table finance.accounts is '{
    "icon": "BookOpen",
    "name": "Chart of Accounts",
    "description": "Every account money can sit in, arranged as a tree. Only postable leaves accept journal lines.",
    "collapsible_group": "Ledger",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["account_type", "is_postable"]},
        "tabs": ["journal_lines", "accounts", "budgets"]
    },
    "views": [
        {
            "id": "tree",
            "name": "Account Tree",
            "type": "tree",
            "parent": "parent_id",
            "title": "name",
            "secondary": "code"
        },
        {
            "id": "list",
            "name": "All Accounts",
            "type": "list",
            "title": "name",
            "description": "code",
            "field_1": "account_type",
            "field_2": "current_balance"
        }
    ],
    "filter_presets": [
        {"id": "postable", "name": "Postable", "filters": [{"id": "is_postable", "value": "true", "operator": "eq"}]},
        {"id": "pnl", "name": "P&L Accounts", "filters": [{"id": "account_type", "value": ["revenue", "expense"], "operator": "in"}]},
        {"id": "balance_sheet", "name": "Balance Sheet", "filters": [{"id": "account_type", "value": ["asset", "liability", "equity"], "operator": "in"}]},
        {"id": "with_balance", "name": "Non-zero", "filters": [{"id": "current_balance", "value": "0", "operator": "neq"}]}
    ],
    "links": [
        {"id": "trial_balance", "name": "Trial Balance", "url": "/finance/report/trial_balance", "icon": "Scale", "description": "Debits and credits by account, and the proof they agree"}
    ],
    "fields": {
        "quick_create": ["code", "name", "account_type"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "parent_id"]},
            {"id": "classification", "title": "Classification", "fields": ["account_type", "normal_balance", "currency", "is_bank_account"]},
            {"id": "posting", "title": "Posting", "fields": ["is_postable", "is_active", "opening_balance", "color"]},
            {"id": "balances", "title": "Balances", "fields": {"read": ["debit_total", "credit_total", "current_balance"]}}
        ],
        "behavior": {
            "is_bank_account": {"visible": [{"id": "account_type", "operator": "eq", "value": "asset"}]},
            "opening_balance": {"read_only": [{"id": "is_postable", "operator": "eq", "value": "false"}]}
        }
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "accounts", "on": "parent_id", "alias": "parent", "columns": ["code", "name"]}]
    }
}';

comment on column finance.accounts.current_balance is '{"name": "Balance", "aggregate": "sum"}';

comment on column finance.accounts.debit_total is '{"name": "Debits", "aggregate": "sum"}';

comment on column finance.accounts.credit_total is '{"name": "Credits", "aggregate": "sum"}';

revoke all on table finance.accounts
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
delete on table finance.accounts to "x-admin";

grant
select
,
  insert,
update on table finance.accounts to "accountant";

grant
select
  on table finance.accounts to "finance-auditor",
  "user";

create index idx_fin_accounts_parent_id on finance.accounts (parent_id);

create index idx_fin_accounts_type on finance.accounts (account_type);

create index idx_fin_accounts_postable on finance.accounts (code)
where
  is_postable
  and is_active;

alter table finance.accounts enable row level security;

create policy accounts_select on finance.accounts for
select
  to authenticated using (true);

create policy accounts_insert on finance.accounts for insert to authenticated
with
  check (true);

create policy accounts_update on finance.accounts
for update
  to authenticated using (true)
with
  check (true);

create policy accounts_delete on finance.accounts for delete to authenticated using (true);

----------------------------------------------------------------
-- Tax rates and exchange rates
----------------------------------------------------------------
create table finance.tax_rates (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(120) not null,
  rate supasheet.PERCENTAGE not null default 0,
  account_id uuid references finance.accounts (id) on delete set null,
  input_account_id uuid references finance.accounts (id) on delete set null,
  is_recoverable boolean not null default true,
  is_active boolean not null default true,
  country varchar(120),
  effective_from date not null default current_date,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint tax_rate_range check (
    rate >= 0
    and rate <= 100
  )
);

comment on table finance.tax_rates is '{
    "icon": "Percent",
    "name": "Tax Rates",
    "description": "VAT and sales tax codes, and the account each posts to.",
    "collapsible_group": "Configuration",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "name", "badges": ["rate", "is_active"]}},
    "views": [
        {"id": "list", "name": "Rates", "type": "list", "title": "name", "description": "country", "field_1": "code", "field_2": "rate"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "country", "effective_from"]},
            {"id": "rate", "title": "Rate", "fields": ["rate", "is_recoverable", "is_active"]},
            {"id": "posting", "title": "Posting", "fields": ["account_id", "input_account_id"]}
        ]
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "accounts", "on": "account_id", "columns": ["code", "name"]}]
    }
}';

revoke all on table finance.tax_rates
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
delete on table finance.tax_rates to "x-admin";

grant
select
,
  insert,
update on table finance.tax_rates to "accountant";

grant
select
  on table finance.tax_rates to "finance-auditor",
  "user";

alter table finance.tax_rates enable row level security;

create policy tax_rates_select on finance.tax_rates for
select
  to authenticated using (true);

create policy tax_rates_insert on finance.tax_rates for insert to authenticated
with
  check (true);

create policy tax_rates_update on finance.tax_rates
for update
  to authenticated using (true)
with
  check (true);

create policy tax_rates_delete on finance.tax_rates for delete to authenticated using (true);

create table finance.exchange_rates (
  id uuid primary key default extensions.uuid_generate_v4 (),
  base_currency varchar(3) not null default 'USD',
  quote_currency varchar(3) not null,
  rate numeric(16, 8) not null,
  rate_date date not null default current_date,
  source varchar(60) not null default 'manual',
  created_at timestamptz default current_timestamp,
  unique (base_currency, quote_currency, rate_date),
  constraint fx_rate_positive check (rate > 0)
);

comment on table finance.exchange_rates is '{
    "icon": "ArrowRightLeft",
    "name": "FX Rates",
    "description": "Daily rates used to translate foreign currency documents.",
    "collapsible_group": "Configuration",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "quote_currency", "badges": ["rate"]}},
    "views": [
        {"id": "list", "name": "Rates", "type": "list", "title": "quote_currency", "description": "source", "field_1": "rate", "field_2": "rate_date"},
        {"id": "calendar", "name": "By Day", "type": "calendar", "title": "quote_currency", "badge": "source", "start_date": "rate_date", "read_only": true}
    ],
    "fields": {
        "sections": [
            {"id": "pair", "title": "Pair", "fields": ["base_currency", "quote_currency", "rate_date"]},
            {"id": "rate", "title": "Rate", "fields": ["rate", "source"]}
        ]
    },
    "query": {
        "sort": [{"id": "rate_date", "desc": true}]
    }
}';

revoke all on table finance.exchange_rates
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
delete on table finance.exchange_rates to "x-admin";

grant
select
,
  insert on table finance.exchange_rates to "accountant";

grant
select
  on table finance.exchange_rates to "finance-auditor";

create index idx_fin_fx_date on finance.exchange_rates (rate_date desc);

alter table finance.exchange_rates enable row level security;

create policy fx_select on finance.exchange_rates for
select
  to authenticated using (true);

create policy fx_insert on finance.exchange_rates for insert to authenticated
with
  check (true);

create policy fx_update on finance.exchange_rates
for update
  to authenticated using (true)
with
  check (true);

create policy fx_delete on finance.exchange_rates for delete to authenticated using (true);

----------------------------------------------------------------
-- Journals (the general ledger)
--
-- A journal is a draft until it balances and its period is open.
-- Once posted it is immutable: the guards below refuse every update
-- and delete, for every role, and the only correction is a reversing
-- journal.
----------------------------------------------------------------
create sequence if not exists finance.journal_number_seq;

create table finance.journals (
  id uuid primary key default extensions.uuid_generate_v4 (),
  journal_number varchar(30) not null unique default (
    'JE-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('finance.journal_number_seq')::text,
      6,
      '0'
    )
  ),
  period_id uuid references finance.fiscal_periods (id) on delete restrict,
  entry_date date not null default current_date,
  status finance.journal_status not null default 'draft',
  source finance.journal_source not null default 'manual',
  memo varchar(300) not null,
  reference varchar(80),
  currency varchar(3) not null default 'USD',
  total_debit numeric(16, 2) not null default 0,
  total_credit numeric(16, 2) not null default 0,
  line_count integer not null default 0,
  is_balanced boolean not null default false,
  reverses_journal_id uuid references finance.journals (id) on delete set null,
  reversed_by_journal_id uuid references finance.journals (id) on delete set null,
  posted_at timestamptz,
  posted_by uuid references supasheet.users (id) on delete set null,
  attachments supasheet.file,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint journals_totals_non_negative check (
    total_debit >= 0
    and total_credit >= 0
  )
);

comment on column finance.journals.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "posted": {"variant": "success", "icon": "BookCheck"},
        "reversed": {"variant": "warning", "icon": "Undo2"}
    }
}';

comment on column finance.journals.source is '{
    "progress": false,
    "values": {
        "manual": {"variant": "secondary", "icon": "PenLine"},
        "invoice": {"variant": "success", "icon": "FileText"},
        "bill": {"variant": "warning", "icon": "Receipt"},
        "receipt": {"variant": "success", "icon": "BadgeDollarSign"},
        "payment": {"variant": "info", "icon": "Banknote"},
        "expense": {"variant": "default", "icon": "Wallet"},
        "depreciation": {"variant": "secondary", "icon": "TrendingDown"},
        "fx_revaluation": {"variant": "info", "icon": "ArrowRightLeft"},
        "opening_balance": {"variant": "default", "icon": "Flag"}
    }
}';

comment on table finance.journals is '{
    "icon": "BookText",
    "name": "Journals",
    "description": "Every entry in the general ledger. Posted entries cannot be edited — reverse them instead.",
    "collapsible_group": "Ledger",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "journal_number", "badges": ["status", "source", "is_balanced"]},
        "tabs": ["journal_lines"],
        "timelines": ["journal_events"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Posting Board",
            "type": "kanban",
            "group": "status",
            "title": "memo",
            "description": "reference",
            "date": "entry_date",
            "badge": "source"
        },
        {
            "id": "calendar",
            "name": "Ledger Calendar",
            "type": "calendar",
            "title": "memo",
            "badge": "status",
            "start_date": "entry_date",
            "read_only": true
        },
        {
            "id": "list",
            "name": "All Journals",
            "type": "list",
            "title": "journal_number",
            "description": "memo",
            "field_1": "status",
            "field_2": "total_debit"
        }
    ],
    "filter_presets": [
        {"id": "drafts", "name": "Unposted", "filters": [{"id": "status", "value": "draft", "operator": "eq"}]},
        {"id": "unbalanced", "name": "Out Of Balance", "filters": [{"id": "is_balanced", "value": "false", "operator": "eq"}]},
        {"id": "posted", "name": "Posted", "filters": [{"id": "status", "value": "posted", "operator": "eq"}]},
        {"id": "manual", "name": "Manual Entries", "filters": [{"id": "source", "value": "manual", "operator": "eq"}]}
    ],
    "links": [
        {"id": "trial_balance", "name": "Trial Balance", "url": "/finance/report/trial_balance", "icon": "Scale", "description": "The proof that the ledger agrees with itself"},
        {"id": "gl", "name": "General Ledger", "url": "/finance/report/general_ledger", "icon": "BookText", "description": "Every posted line, by account"}
    ],
    "fields": {
        "quick_create": ["entry_date", "memo", "source"],
        "sections": [
            {"id": "entry", "title": "Entry", "fields": ["entry_date", "memo", "reference", "source", "currency"]},
            {"id": "period", "title": "Period", "fields": {"read": ["period_id", "status"]}},
            {"id": "totals", "title": "Totals", "fields": {"read": ["line_count", "total_debit", "total_credit", "is_balanced"]}},
            {"id": "reversal", "title": "Reversal", "fields": {"read": ["reverses_journal_id", "reversed_by_journal_id"]}},
            {"id": "audit", "title": "Posting", "fields": {"read": ["posted_at", "posted_by"]}},
            {"id": "extras", "title": "Attachments", "collapsible": true, "fields": ["attachments"]}
        ]
    },
    "query": {
        "sort": [{"id": "entry_date", "desc": true}],
        "join": [
            {"table": "fiscal_periods", "on": "period_id", "columns": ["code", "status"]},
            {"table": "users", "on": "posted_by", "alias": "poster", "columns": ["name", "email"]}
        ]
    }
}';

comment on column finance.journals.total_debit is '{"name": "Debit", "aggregate": "sum"}';

comment on column finance.journals.total_credit is '{"name": "Credit", "aggregate": "sum"}';

comment on column finance.journals.attachments is '{"accept": "*", "max_files": 5, "max_size": 10485760}';

revoke all on table finance.journals
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
delete on table finance.journals to "x-admin";

grant
select
,
  insert,
update on table finance.journals to "accountant";

grant
select
  on table finance.journals to "finance-auditor";

revoke all on sequence finance.journal_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence finance.journal_number_seq to "x-admin",
"accountant";

create index idx_fin_journals_period_id on finance.journals (period_id);

create index idx_fin_journals_status on finance.journals (status);

create index idx_fin_journals_entry_date on finance.journals (entry_date desc);

create index idx_fin_journals_source on finance.journals (source);

create index idx_fin_journals_unposted on finance.journals (entry_date)
where
  status = 'draft';

alter table finance.journals enable row level security;

create policy journals_select on finance.journals for
select
  to authenticated using (true);

create policy journals_insert on finance.journals for insert to authenticated
with
  check (true);

create policy journals_update on finance.journals
for update
  to authenticated using (true)
with
  check (true);

create policy journals_delete on finance.journals for delete to authenticated using (true);

----------------------------------------------------------------
-- Journal lines (the debits and credits themselves)
----------------------------------------------------------------
create table finance.journal_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  journal_id uuid not null references finance.journals (id) on delete cascade,
  account_id uuid not null references finance.accounts (id) on delete restrict,
  cost_center_id uuid references finance.cost_centers (id) on delete set null,
  line_number integer not null default 1,
  description varchar(300),
  debit numeric(16, 2) not null default 0,
  credit numeric(16, 2) not null default 0,
  tax_rate_id uuid references finance.tax_rates (id) on delete set null,
  created_at timestamptz default current_timestamp,
  constraint lines_amounts_non_negative check (
    debit >= 0
    and credit >= 0
  ),
  -- The rule that makes a line a line: one side or the other, never
  -- both, never neither.
  constraint lines_one_side_only check (
    (
      debit > 0
      and credit = 0
    )
    or (
      credit > 0
      and debit = 0
    )
  )
);

comment on table finance.journal_lines is '{
    "icon": "Rows3",
    "name": "Journal Lines",
    "description": "One debit or one credit each. Never both.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["journal_id", "line_number", "account_id", "cost_center_id"]},
            {"id": "amounts", "title": "Amounts", "fields": ["debit", "credit", "tax_rate_id"]},
            {"id": "detail", "title": "Detail", "fields": ["description"]}
        ],
        "lookups": {
            "account_id": {"filter": [{"source_column": "currency", "target_column": "currency"}]}
        }
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "journals", "on": "journal_id", "columns": ["journal_number", "status", "entry_date"]},
            {"table": "accounts", "on": "account_id", "columns": ["code", "name", "account_type"]},
            {"table": "cost_centers", "on": "cost_center_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column finance.journal_lines.debit is '{"aggregate": "sum"}';

comment on column finance.journal_lines.credit is '{"aggregate": "sum"}';

revoke all on table finance.journal_lines
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
delete on table finance.journal_lines to "x-admin",
"accountant";

grant
select
  on table finance.journal_lines to "finance-auditor";

create index idx_fin_lines_journal_id on finance.journal_lines (journal_id);

create index idx_fin_lines_account_id on finance.journal_lines (account_id);

create index idx_fin_lines_cost_center_id on finance.journal_lines (cost_center_id);

alter table finance.journal_lines enable row level security;

create policy lines_select on finance.journal_lines for
select
  to authenticated using (true);

create policy lines_insert on finance.journal_lines for insert to authenticated
with
  check (true);

create policy lines_update on finance.journal_lines
for update
  to authenticated using (true)
with
  check (true);

create policy lines_delete on finance.journal_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Journal events (trigger-populated timeline)
----------------------------------------------------------------
create table finance.journal_events (
  id uuid primary key default extensions.uuid_generate_v4 (),
  journal_id uuid not null references finance.journals (id) on delete cascade,
  event_type finance.journal_event_type not null,
  title varchar(255) not null,
  metadata jsonb,
  actor_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  occurred_at timestamptz not null default current_timestamp
);

comment on column finance.journal_events.event_type is '{
    "progress": false,
    "values": {
        "created": {"variant": "info", "icon": "Sparkles"},
        "line_changed": {"variant": "secondary", "icon": "Rows3"},
        "posted": {"variant": "success", "icon": "BookCheck"},
        "reversed": {"variant": "warning", "icon": "Undo2"},
        "record_updated": {"variant": "secondary", "icon": "RefreshCw"}
    }
}';

comment on table finance.journal_events is '{
    "icon": "History",
    "name": "Journal History",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "event", "title": "Event", "fields": ["journal_id", "event_type", "title", "metadata", "actor_id", "occurred_at"]}
        ]
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [{"table": "users", "on": "actor_id", "alias": "actor", "columns": ["name", "email"]}]
    }
}';

revoke all on table finance.journal_events
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on table finance.journal_events to "x-admin",
  "accountant",
  "finance-auditor";

create index idx_fin_journal_events_journal_id on finance.journal_events (journal_id);

create index idx_fin_journal_events_occurred_at on finance.journal_events (occurred_at desc);

alter table finance.journal_events enable row level security;

create policy journal_events_select on finance.journal_events for
select
  to authenticated using (true);

----------------------------------------------------------------
-- Customers (receivables) and vendors (payables)
----------------------------------------------------------------
create table finance.customers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(200) not null,
  legal_name varchar(200),
  email supasheet.EMAIL,
  phone supasheet.TEL,
  website supasheet.URL,
  tax_number varchar(60),
  status finance.customer_status not null default 'active',
  payment_terms_days integer not null default 30,
  credit_limit numeric(16, 2) not null default 0,
  currency varchar(3) not null default 'USD',
  billing_address text,
  country varchar(120),
  receivable_account_id uuid references finance.accounts (id) on delete set null,
  logo supasheet.AVATAR,
  -- How confident credit control is of being paid, which is a
  -- judgement rather than a number the ledger can derive.
  credit_rating supasheet.RATING,
  invoiced_total numeric(16, 2) not null default 0,
  paid_total numeric(16, 2) not null default 0,
  outstanding_total numeric(16, 2) not null default 0,
  overdue_total numeric(16, 2) not null default 0,
  oldest_due_date date,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint customers_terms_non_negative check (
    payment_terms_days >= 0
    and credit_limit >= 0
  )
);

comment on column finance.customers.status is '{
    "progress": false,
    "values": {
        "active": {"variant": "success", "icon": "CircleCheck"},
        "on_hold": {"variant": "warning", "icon": "PauseCircle"},
        "closed": {"variant": "secondary", "icon": "Archive"}
    }
}';

comment on table finance.customers is '{
    "icon": "Building2",
    "description": "Who owes us money, and how much of it is late.",
    "collapsible_group": "Receivables",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["status", "outstanding_total"]},
        "tabs": ["invoices", "payments"]
    },
    "views": [
        {"id": "list", "name": "All Customers", "type": "list", "title": "name", "description": "code", "field_1": "outstanding_total", "field_2": "overdue_total"},
        {"id": "gallery", "name": "Account Cards", "type": "gallery", "cover": "logo", "title": "name", "description": "country", "badge": "status"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "name", "description": "code", "date": "oldest_due_date", "badge": "currency"}
    ],
    "filter_presets": [
        {"id": "poor_credit", "name": "Weak Credit", "filters": [{"id": "credit_rating", "value": "3", "operator": "lte"}]},
        {"id": "owing", "name": "Owing", "filters": [{"id": "outstanding_total", "value": "0", "operator": "gt"}]},
        {"id": "overdue", "name": "Overdue", "filters": [{"id": "overdue_total", "value": "0", "operator": "gt"}]},
        {"id": "on_hold", "name": "On Hold", "filters": [{"id": "status", "value": "on_hold", "operator": "eq"}]}
    ],
    "links": [
        {"id": "aged_receivables", "name": "Aged Receivables", "url": "/finance/report/aged_receivables", "icon": "Clock", "description": "What is owed, and how late it is"}
    ],
    "fields": {
        "quick_create": ["code", "name", "email", "payment_terms_days"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": {"create": ["code", "name", "legal_name", "tax_number"], "update": ["name", "legal_name", "tax_number", "status", "logo"], "read": ["code", "name", "legal_name", "tax_number", "status", "logo"]}},
            {"id": "contact", "title": "Contact", "fields": ["email", "phone", "website", "billing_address", "country"]},
            {"id": "terms", "title": "Terms", "fields": ["payment_terms_days", "credit_limit", "currency", "receivable_account_id", "credit_rating"]},
            {"id": "position", "title": "Position", "fields": {"read": ["invoiced_total", "paid_total", "outstanding_total", "overdue_total", "oldest_due_date"]}},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [{"table": "accounts", "on": "receivable_account_id", "columns": ["code", "name"]}]
    }
}';

comment on column finance.customers.logo is '{"accept": "image/*", "max_size": 1048576}';

comment on column finance.customers.credit_rating is '{"name": "Credit Confidence"}';

comment on column finance.customers.outstanding_total is '{"name": "Outstanding", "aggregate": "sum"}';

comment on column finance.customers.overdue_total is '{"name": "Overdue", "aggregate": "sum"}';

revoke all on table finance.customers
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
delete on table finance.customers to "x-admin";

grant
select
,
  insert,
update on table finance.customers to "accountant";

grant
select
  on table finance.customers to "finance-auditor";

create unique index idx_fin_customers_name on finance.customers (lower(name));

create index idx_fin_customers_status on finance.customers (status);

alter table finance.customers enable row level security;

create policy customers_select on finance.customers for
select
  to authenticated using (true);

create policy customers_insert on finance.customers for insert to authenticated
with
  check (true);

create policy customers_update on finance.customers
for update
  to authenticated using (true)
with
  check (true);

create policy customers_delete on finance.customers for delete to authenticated using (true);

create table finance.vendors (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(200) not null,
  email supasheet.EMAIL,
  phone supasheet.TEL,
  website supasheet.URL,
  tax_number varchar(60),
  is_active boolean not null default true,
  payment_terms_days integer not null default 30,
  currency varchar(3) not null default 'USD',
  bank_details varchar(200),
  country varchar(120),
  payable_account_id uuid references finance.accounts (id) on delete set null,
  default_expense_account_id uuid references finance.accounts (id) on delete set null,
  logo supasheet.AVATAR,
  service_rating supasheet.RATING,
  billed_total numeric(16, 2) not null default 0,
  paid_total numeric(16, 2) not null default 0,
  outstanding_total numeric(16, 2) not null default 0,
  notes supasheet.RICH_TEXT,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint vendors_terms_non_negative check (payment_terms_days >= 0)
);

comment on table finance.vendors is '{
    "icon": "Truck",
    "description": "Who we owe money to.",
    "collapsible_group": "Payables",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["is_active", "outstanding_total"]},
        "tabs": ["bills", "payments"]
    },
    "views": [
        {"id": "list", "name": "All Vendors", "type": "list", "title": "name", "description": "code", "field_1": "outstanding_total", "field_2": "payment_terms_days"},
        {"id": "gallery", "name": "Supplier Cards", "type": "gallery", "cover": "logo", "title": "name", "description": "country", "badge": "service_rating"}
    ],
    "filter_presets": [
        {"id": "poor_service", "name": "Poor Service", "filters": [{"id": "service_rating", "value": "3", "operator": "lte"}]},
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "owing", "name": "We Owe", "filters": [{"id": "outstanding_total", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "email"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": {"create": ["code", "name", "tax_number"], "update": ["name", "tax_number", "is_active", "logo"], "read": ["code", "name", "tax_number", "is_active", "logo"]}},
            {"id": "contact", "title": "Contact", "fields": ["email", "phone", "website", "country", "bank_details"]},
            {"id": "terms", "title": "Terms", "fields": ["payment_terms_days", "currency", "payable_account_id", "default_expense_account_id"]},
            {"id": "performance", "title": "Performance", "fields": ["service_rating"]},
            {"id": "position", "title": "Position", "fields": {"read": ["billed_total", "paid_total", "outstanding_total"]}},
            {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]}
        ]
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [{"table": "accounts", "on": "default_expense_account_id", "alias": "expense_account", "columns": ["code", "name"]}]
    }
}';

comment on column finance.vendors.logo is '{"accept": "image/*", "max_size": 1048576}';

comment on column finance.vendors.outstanding_total is '{"name": "Outstanding", "aggregate": "sum"}';

revoke all on table finance.vendors
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
delete on table finance.vendors to "x-admin";

grant
select
,
  insert,
update on table finance.vendors to "accountant";

grant
select
  on table finance.vendors to "finance-auditor";

create unique index idx_fin_vendors_name on finance.vendors (lower(name));

alter table finance.vendors enable row level security;

create policy vendors_select on finance.vendors for
select
  to authenticated using (true);

create policy vendors_insert on finance.vendors for insert to authenticated
with
  check (true);

create policy vendors_update on finance.vendors
for update
  to authenticated using (true)
with
  check (true);

create policy vendors_delete on finance.vendors for delete to authenticated using (true);

----------------------------------------------------------------
-- Invoices and their lines
----------------------------------------------------------------
create sequence if not exists finance.invoice_number_seq;

create table finance.invoices (
  id uuid primary key default extensions.uuid_generate_v4 (),
  invoice_number varchar(30) not null unique default (
    'INV-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('finance.invoice_number_seq')::text,
      5,
      '0'
    )
  ),
  customer_id uuid not null references finance.customers (id) on delete restrict,
  status finance.invoice_status not null default 'draft',
  issue_date date not null default current_date,
  due_date date not null default (current_date + 30),
  period_id uuid references finance.fiscal_periods (id) on delete set null,
  journal_id uuid references finance.journals (id) on delete set null,
  currency varchar(3) not null default 'USD',
  exchange_rate numeric(16, 8) not null default 1,
  subtotal numeric(16, 2) not null default 0,
  tax_total numeric(16, 2) not null default 0,
  total numeric(16, 2) not null default 0,
  paid_total numeric(16, 2) not null default 0,
  balance_due numeric(16, 2) not null default 0,
  days_overdue integer not null default 0,
  purchase_order varchar(60),
  notes supasheet.RICH_TEXT,
  terms supasheet.RICH_TEXT,
  sent_at timestamptz,
  paid_at timestamptz,
  voided_reason varchar(300),
  document supasheet.file,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint invoices_dates_ordered check (due_date >= issue_date),
  constraint invoices_money_non_negative check (
    subtotal >= 0
    and tax_total >= 0
    and total >= 0
    and paid_total >= 0
  ),
  constraint invoices_not_overcollected check (paid_total <= total)
);

comment on column finance.invoices.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "sent": {"variant": "info", "icon": "Send"},
        "partially_paid": {"variant": "warning", "icon": "CircleDollarSign"},
        "paid": {"variant": "success", "icon": "BadgeDollarSign"},
        "overdue": {"variant": "destructive", "icon": "Clock"},
        "void": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table finance.invoices is '{
    "icon": "FileText",
    "description": "What we have billed, and what is still outstanding.",
    "collapsible_group": "Receivables",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "invoice_number", "badges": ["status", "balance_due"]},
        "tabs": ["invoice_lines", "payment_allocations"]
    },
    "views": [
        {"id": "kanban", "name": "Collections Board", "type": "kanban", "group": "status", "title": "invoice_number", "description": "purchase_order", "date": "due_date", "badge": "currency"},
        {"id": "calendar", "name": "Due Dates", "type": "calendar", "title": "invoice_number", "badge": "status", "start_date": "issue_date", "end_date": "due_date"},
        {"id": "list", "name": "All Invoices", "type": "list", "title": "invoice_number", "description": "notes", "field_1": "status", "field_2": "balance_due"}
    ],
    "filter_presets": [
        {"id": "outstanding", "name": "Outstanding", "filters": [{"id": "status", "value": ["sent", "partially_paid", "overdue"], "operator": "in"}]},
        {"id": "overdue", "name": "Overdue", "filters": [{"id": "status", "value": "overdue", "operator": "eq"}]},
        {"id": "drafts", "name": "Drafts", "filters": [{"id": "status", "value": "draft", "operator": "eq"}]},
        {"id": "long_overdue", "name": "60 Days+", "filters": [{"id": "days_overdue", "value": "60", "operator": "gte"}]}
    ],
    "links": [
        {"id": "aged", "name": "Aged Receivables", "url": "/finance/report/aged_receivables", "icon": "Clock", "description": "The collections list, bucketed by age"}
    ],
    "fields": {
        "quick_create": ["customer_id", "issue_date", "due_date"],
        "sections": [
            {"id": "header", "title": "Invoice", "fields": ["customer_id", "issue_date", "due_date", "purchase_order"]},
            {"id": "money", "title": "Money", "fields": {"create": ["currency", "exchange_rate"], "update": ["currency", "exchange_rate"], "read": ["currency", "subtotal", "tax_total", "total", "paid_total", "balance_due"]}},
            {"id": "state", "title": "State", "fields": ["status", "voided_reason"]},
            {"id": "posting", "title": "Posting", "fields": {"read": ["period_id", "journal_id", "days_overdue", "sent_at", "paid_at"]}},
            {"id": "extras", "title": "Terms & document", "collapsible": true, "fields": ["terms", "notes", "document"]}
        ],
        "behavior": {
            "voided_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "void"}],
                "required": [{"id": "status", "operator": "eq", "value": "void"}]
            },
            "exchange_rate": {"visible": [{"id": "currency", "operator": "neq", "value": "USD"}]}
        },
        "lookups": {
            "customer_id": {
                "fill": [
                    {"source_column": "currency", "target_column": "currency"},
                    {"source_column": "terms", "target_column": "notes"}
                ]
            }
        }
    },
    "query": {
        "sort": [{"id": "issue_date", "desc": true}],
        "join": [
            {"table": "customers", "on": "customer_id", "columns": ["code", "name", "status"]},
            {"table": "journals", "on": "journal_id", "columns": ["journal_number", "status"]}
        ]
    }
}';

comment on column finance.invoices.total is '{"aggregate": "sum"}';

comment on column finance.invoices.balance_due is '{"name": "Balance", "aggregate": "sum"}';

comment on column finance.invoices.days_overdue is '{"name": "Days Overdue", "aggregate": "max"}';

comment on column finance.invoices.document is '{"accept": ".pdf", "max_files": 3, "max_size": 10485760}';

revoke all on table finance.invoices
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
delete on table finance.invoices to "x-admin";

grant
select
,
  insert,
update on table finance.invoices to "accountant";

grant
select
  on table finance.invoices to "finance-auditor";

revoke all on sequence finance.invoice_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence finance.invoice_number_seq to "x-admin",
"accountant";

create index idx_fin_invoices_customer_id on finance.invoices (customer_id);

create index idx_fin_invoices_status on finance.invoices (status);

create index idx_fin_invoices_due_date on finance.invoices (due_date);

create index idx_fin_invoices_open on finance.invoices (due_date)
where
  status in ('sent', 'partially_paid', 'overdue');

alter table finance.invoices enable row level security;

create policy invoices_select on finance.invoices for
select
  to authenticated using (true);

create policy invoices_insert on finance.invoices for insert to authenticated
with
  check (true);

create policy invoices_update on finance.invoices
for update
  to authenticated using (true)
with
  check (true);

create policy invoices_delete on finance.invoices for delete to authenticated using (true);

create table finance.invoice_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  invoice_id uuid not null references finance.invoices (id) on delete cascade,
  account_id uuid references finance.accounts (id) on delete set null,
  cost_center_id uuid references finance.cost_centers (id) on delete set null,
  tax_rate_id uuid references finance.tax_rates (id) on delete set null,
  line_number integer not null default 1,
  description varchar(300) not null,
  quantity numeric(12, 3) not null default 1,
  unit_price numeric(16, 4) not null default 0,
  discount_percent supasheet.PERCENTAGE not null default 0,
  net_amount numeric(16, 2) not null default 0,
  tax_amount numeric(16, 2) not null default 0,
  line_total numeric(16, 2) not null default 0,
  created_at timestamptz default current_timestamp,
  constraint invoice_lines_quantity_positive check (quantity > 0),
  constraint invoice_lines_price_non_negative check (unit_price >= 0),
  constraint invoice_lines_discount_range check (
    discount_percent >= 0
    and discount_percent <= 100
  )
);

comment on table finance.invoice_lines is '{
    "icon": "Rows3",
    "name": "Invoice Lines",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["invoice_id", "line_number", "description"]},
            {"id": "pricing", "title": "Pricing", "fields": ["quantity", "unit_price", "discount_percent", "tax_rate_id"]},
            {"id": "coding", "title": "Coding", "fields": ["account_id", "cost_center_id"]},
            {"id": "totals", "title": "Totals", "fields": {"read": ["net_amount", "tax_amount", "line_total"]}}
        ]
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "invoices", "on": "invoice_id", "columns": ["invoice_number", "status"]},
            {"table": "accounts", "on": "account_id", "columns": ["code", "name"]},
            {"table": "tax_rates", "on": "tax_rate_id", "columns": ["code", "rate"]}
        ]
    }
}';

comment on column finance.invoice_lines.line_total is '{"name": "Line Total", "aggregate": "sum"}';

revoke all on table finance.invoice_lines
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
delete on table finance.invoice_lines to "x-admin",
"accountant";

grant
select
  on table finance.invoice_lines to "finance-auditor";

create index idx_fin_invoice_lines_invoice_id on finance.invoice_lines (invoice_id);

alter table finance.invoice_lines enable row level security;

create policy invoice_lines_select on finance.invoice_lines for
select
  to authenticated using (true);

create policy invoice_lines_insert on finance.invoice_lines for insert to authenticated
with
  check (true);

create policy invoice_lines_update on finance.invoice_lines
for update
  to authenticated using (true)
with
  check (true);

create policy invoice_lines_delete on finance.invoice_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Bills and their lines (payables)
----------------------------------------------------------------
create sequence if not exists finance.bill_number_seq;

create table finance.bills (
  id uuid primary key default extensions.uuid_generate_v4 (),
  bill_number varchar(30) not null unique default (
    'BILL-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('finance.bill_number_seq')::text, 5, '0')
  ),
  vendor_id uuid not null references finance.vendors (id) on delete restrict,
  vendor_reference varchar(80),
  status finance.bill_status not null default 'draft',
  issue_date date not null default current_date,
  due_date date not null default (current_date + 30),
  period_id uuid references finance.fiscal_periods (id) on delete set null,
  journal_id uuid references finance.journals (id) on delete set null,
  currency varchar(3) not null default 'USD',
  subtotal numeric(16, 2) not null default 0,
  tax_total numeric(16, 2) not null default 0,
  total numeric(16, 2) not null default 0,
  paid_total numeric(16, 2) not null default 0,
  balance_due numeric(16, 2) not null default 0,
  approved_by uuid references supasheet.users (id) on delete set null,
  approved_at timestamptz,
  paid_at timestamptz,
  notes supasheet.RICH_TEXT,
  document supasheet.file,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint bills_dates_ordered check (due_date >= issue_date),
  constraint bills_money_non_negative check (
    subtotal >= 0
    and tax_total >= 0
    and total >= 0
    and paid_total >= 0
  ),
  constraint bills_not_overpaid check (paid_total <= total)
);

comment on column finance.bills.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "awaiting_approval": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "info", "icon": "CircleCheck"},
        "partially_paid": {"variant": "warning", "icon": "CircleDollarSign"},
        "paid": {"variant": "success", "icon": "BadgeDollarSign"},
        "void": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table finance.bills is '{
    "icon": "Receipt",
    "description": "What suppliers have billed us, and what is approved to pay.",
    "collapsible_group": "Payables",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "bill_number", "badges": ["status", "balance_due"]},
        "tabs": ["bill_lines", "payment_allocations"]
    },
    "views": [
        {"id": "kanban", "name": "Approval Board", "type": "kanban", "group": "status", "title": "bill_number", "description": "vendor_reference", "date": "due_date", "badge": "currency"},
        {"id": "calendar", "name": "Payment Run", "type": "calendar", "title": "bill_number", "badge": "status", "start_date": "due_date"},
        {"id": "list", "name": "All Bills", "type": "list", "title": "bill_number", "description": "vendor_reference", "field_1": "status", "field_2": "balance_due"}
    ],
    "filter_presets": [
        {"id": "to_approve", "name": "To Approve", "filters": [{"id": "status", "value": "awaiting_approval", "operator": "eq"}]},
        {"id": "to_pay", "name": "To Pay", "filters": [{"id": "status", "value": ["approved", "partially_paid"], "operator": "in"}]},
        {"id": "paid", "name": "Paid", "filters": [{"id": "status", "value": "paid", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["vendor_id", "vendor_reference", "issue_date"],
        "sections": [
            {"id": "header", "title": "Bill", "fields": ["vendor_id", "vendor_reference", "issue_date", "due_date"]},
            {"id": "money", "title": "Money", "fields": {"create": ["currency"], "update": ["currency"], "read": ["currency", "subtotal", "tax_total", "total", "paid_total", "balance_due"]}},
            {"id": "approval", "title": "Approval", "fields": ["status"]},
            {"id": "posting", "title": "Posting", "fields": {"read": ["period_id", "journal_id", "approved_by", "approved_at", "paid_at"]}},
            {"id": "extras", "title": "Notes & document", "collapsible": true, "fields": ["notes", "document"]}
        ],
        "lookups": {
            "vendor_id": {"fill": [{"source_column": "currency", "target_column": "currency"}]}
        }
    },
    "query": {
        "sort": [{"id": "due_date", "desc": false}],
        "join": [
            {"table": "vendors", "on": "vendor_id", "columns": ["code", "name"]},
            {"table": "journals", "on": "journal_id", "columns": ["journal_number", "status"]}
        ]
    }
}';

comment on column finance.bills.total is '{"aggregate": "sum"}';

comment on column finance.bills.balance_due is '{"name": "Balance", "aggregate": "sum"}';

comment on column finance.bills.document is '{"accept": ".pdf,.png,.jpg", "max_files": 3, "max_size": 10485760}';

revoke all on table finance.bills
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
delete on table finance.bills to "x-admin";

grant
select
,
  insert,
update on table finance.bills to "accountant";

grant
select
  on table finance.bills to "finance-auditor";

revoke all on sequence finance.bill_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence finance.bill_number_seq to "x-admin",
"accountant";

create index idx_fin_bills_vendor_id on finance.bills (vendor_id);

create index idx_fin_bills_status on finance.bills (status);

create index idx_fin_bills_due_date on finance.bills (due_date);

alter table finance.bills enable row level security;

create policy bills_select on finance.bills for
select
  to authenticated using (true);

create policy bills_insert on finance.bills for insert to authenticated
with
  check (true);

create policy bills_update on finance.bills
for update
  to authenticated using (true)
with
  check (true);

create policy bills_delete on finance.bills for delete to authenticated using (true);

create table finance.bill_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  bill_id uuid not null references finance.bills (id) on delete cascade,
  account_id uuid references finance.accounts (id) on delete set null,
  cost_center_id uuid references finance.cost_centers (id) on delete set null,
  tax_rate_id uuid references finance.tax_rates (id) on delete set null,
  line_number integer not null default 1,
  description varchar(300) not null,
  quantity numeric(12, 3) not null default 1,
  unit_price numeric(16, 4) not null default 0,
  net_amount numeric(16, 2) not null default 0,
  tax_amount numeric(16, 2) not null default 0,
  line_total numeric(16, 2) not null default 0,
  created_at timestamptz default current_timestamp,
  constraint bill_lines_quantity_positive check (quantity > 0),
  constraint bill_lines_price_non_negative check (unit_price >= 0)
);

comment on table finance.bill_lines is '{
    "icon": "Rows3",
    "name": "Bill Lines",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["bill_id", "line_number", "description"]},
            {"id": "pricing", "title": "Pricing", "fields": ["quantity", "unit_price", "tax_rate_id"]},
            {"id": "coding", "title": "Coding", "fields": ["account_id", "cost_center_id"]},
            {"id": "totals", "title": "Totals", "fields": {"read": ["net_amount", "tax_amount", "line_total"]}}
        ]
    },
    "query": {
        "sort": [{"id": "line_number", "desc": false}],
        "join": [
            {"table": "bills", "on": "bill_id", "columns": ["bill_number", "status"]},
            {"table": "accounts", "on": "account_id", "columns": ["code", "name"]},
            {"table": "cost_centers", "on": "cost_center_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column finance.bill_lines.line_total is '{"name": "Line Total", "aggregate": "sum"}';

revoke all on table finance.bill_lines
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
delete on table finance.bill_lines to "x-admin",
"accountant";

grant
select
  on table finance.bill_lines to "finance-auditor";

create index idx_fin_bill_lines_bill_id on finance.bill_lines (bill_id);

alter table finance.bill_lines enable row level security;

create policy bill_lines_select on finance.bill_lines for
select
  to authenticated using (true);

create policy bill_lines_insert on finance.bill_lines for insert to authenticated
with
  check (true);

create policy bill_lines_update on finance.bill_lines
for update
  to authenticated using (true)
with
  check (true);

create policy bill_lines_delete on finance.bill_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Payments and allocations
--
-- One payments table for both directions. What a payment settles is
-- an allocation, not a foreign key, because a single receipt often
-- clears several invoices and a single invoice is often cleared by
-- several receipts.
----------------------------------------------------------------
create sequence if not exists finance.payment_number_seq;

create table finance.payments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  payment_number varchar(30) not null unique default (
    'PAY-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('finance.payment_number_seq')::text,
      5,
      '0'
    )
  ),
  direction finance.payment_direction not null default 'inbound',
  customer_id uuid references finance.customers (id) on delete set null,
  vendor_id uuid references finance.vendors (id) on delete set null,
  bank_account_id uuid,
  method finance.payment_method not null default 'bank_transfer',
  payment_date date not null default current_date,
  period_id uuid references finance.fiscal_periods (id) on delete set null,
  journal_id uuid references finance.journals (id) on delete set null,
  currency varchar(3) not null default 'USD',
  amount numeric(16, 2) not null,
  allocated_total numeric(16, 2) not null default 0,
  unallocated_total numeric(16, 2) not null default 0,
  reference varchar(80),
  note varchar(300),
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint payments_amount_positive check (amount > 0),
  -- A receipt belongs to a customer, a payment to a vendor. Never
  -- both, never neither.
  constraint payments_one_counterparty check (
    (
      direction = 'inbound'
      and customer_id is not null
      and vendor_id is null
    )
    or (
      direction = 'outbound'
      and vendor_id is not null
      and customer_id is null
    )
  )
);

comment on column finance.payments.direction is '{
    "progress": false,
    "values": {
        "inbound": {"variant": "success", "icon": "ArrowDownToLine"},
        "outbound": {"variant": "warning", "icon": "ArrowUpFromLine"}
    }
}';

comment on table finance.payments is '{
    "icon": "Banknote",
    "description": "Money in and money out, and how much of each is still unallocated.",
    "collapsible_group": "Cash",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "payment_number", "badges": ["direction", "method"]},
        "tabs": ["payment_allocations"]
    },
    "views": [
        {"id": "list", "name": "All Payments", "type": "list", "title": "payment_number", "description": "reference", "field_1": "direction", "field_2": "amount"},
        {"id": "calendar", "name": "Cash Calendar", "type": "calendar", "title": "payment_number", "badge": "direction", "start_date": "payment_date"},
        {"id": "kanban", "name": "By Method", "type": "kanban", "group": "method", "title": "payment_number", "description": "reference", "date": "payment_date", "badge": "direction"}
    ],
    "filter_presets": [
        {"id": "receipts", "name": "Receipts", "filters": [{"id": "direction", "value": "inbound", "operator": "eq"}]},
        {"id": "payments", "name": "Payments Out", "filters": [{"id": "direction", "value": "outbound", "operator": "eq"}]},
        {"id": "unallocated", "name": "Unallocated", "filters": [{"id": "unallocated_total", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["direction", "amount", "payment_date", "method"],
        "sections": [
            {"id": "payment", "title": "Payment", "fields": ["direction", "payment_date", "method", "amount", "currency"]},
            {"id": "counterparty", "title": "Counterparty", "fields": ["customer_id", "vendor_id", "bank_account_id"]},
            {"id": "reference", "title": "Reference", "fields": ["reference", "note"]},
            {"id": "allocation", "title": "Allocation", "fields": {"read": ["allocated_total", "unallocated_total", "period_id", "journal_id"]}}
        ],
        "behavior": {
            "customer_id": {
                "visible": [{"id": "direction", "operator": "eq", "value": "inbound"}],
                "required": [{"id": "direction", "operator": "eq", "value": "inbound"}]
            },
            "vendor_id": {
                "visible": [{"id": "direction", "operator": "eq", "value": "outbound"}],
                "required": [{"id": "direction", "operator": "eq", "value": "outbound"}]
            }
        }
    },
    "query": {
        "sort": [{"id": "payment_date", "desc": true}],
        "join": [
            {"table": "customers", "on": "customer_id", "columns": ["code", "name"]},
            {"table": "vendors", "on": "vendor_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column finance.payments.amount is '{"aggregate": "sum"}';

comment on column finance.payments.unallocated_total is '{"name": "Unallocated", "aggregate": "sum"}';

revoke all on table finance.payments
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
delete on table finance.payments to "x-admin";

grant
select
,
  insert,
update on table finance.payments to "accountant";

grant
select
  on table finance.payments to "finance-auditor";

revoke all on sequence finance.payment_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence finance.payment_number_seq to "x-admin",
"accountant";

create index idx_fin_payments_customer_id on finance.payments (customer_id);

create index idx_fin_payments_vendor_id on finance.payments (vendor_id);

create index idx_fin_payments_date on finance.payments (payment_date desc);

alter table finance.payments enable row level security;

create policy payments_select on finance.payments for
select
  to authenticated using (true);

create policy payments_insert on finance.payments for insert to authenticated
with
  check (true);

create policy payments_update on finance.payments
for update
  to authenticated using (true)
with
  check (true);

create policy payments_delete on finance.payments for delete to authenticated using (true);

create table finance.payment_allocations (
  id uuid primary key default extensions.uuid_generate_v4 (),
  payment_id uuid not null references finance.payments (id) on delete cascade,
  invoice_id uuid references finance.invoices (id) on delete cascade,
  bill_id uuid references finance.bills (id) on delete cascade,
  amount numeric(16, 2) not null,
  allocated_on date not null default current_date,
  note varchar(200),
  created_at timestamptz default current_timestamp,
  constraint allocations_amount_positive check (amount > 0),
  constraint allocations_one_document check (
    (
      invoice_id is not null
      and bill_id is null
    )
    or (
      bill_id is not null
      and invoice_id is null
    )
  )
);

comment on table finance.payment_allocations is '{
    "icon": "Link",
    "name": "Allocations",
    "description": "Which payment settles which document, and for how much.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "allocation", "title": "Allocation", "fields": ["payment_id", "invoice_id", "bill_id", "amount", "allocated_on"]},
            {"id": "extras", "title": "Note", "fields": ["note"]}
        ]
    },
    "query": {
        "sort": [{"id": "allocated_on", "desc": true}],
        "join": [
            {"table": "payments", "on": "payment_id", "columns": ["payment_number", "direction", "amount"]},
            {"table": "invoices", "on": "invoice_id", "columns": ["invoice_number", "balance_due"]},
            {"table": "bills", "on": "bill_id", "columns": ["bill_number", "balance_due"]}
        ]
    }
}';

comment on column finance.payment_allocations.amount is '{"aggregate": "sum"}';

revoke all on table finance.payment_allocations
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
delete on table finance.payment_allocations to "x-admin",
"accountant";

grant
select
  on table finance.payment_allocations to "finance-auditor";

create index idx_fin_alloc_payment_id on finance.payment_allocations (payment_id);

create index idx_fin_alloc_invoice_id on finance.payment_allocations (invoice_id);

create index idx_fin_alloc_bill_id on finance.payment_allocations (bill_id);

alter table finance.payment_allocations enable row level security;

create policy allocations_select on finance.payment_allocations for
select
  to authenticated using (true);

create policy allocations_insert on finance.payment_allocations for insert to authenticated
with
  check (true);

create policy allocations_update on finance.payment_allocations
for update
  to authenticated using (true)
with
  check (true);

create policy allocations_delete on finance.payment_allocations for delete to authenticated using (true);

----------------------------------------------------------------
-- Bank accounts and statement lines
----------------------------------------------------------------
create table finance.bank_accounts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(20) not null unique,
  name varchar(160) not null,
  bank_name varchar(160),
  account_number varchar(60),
  iban varchar(60),
  swift varchar(20),
  currency varchar(3) not null default 'USD',
  gl_account_id uuid references finance.accounts (id) on delete set null,
  opening_balance numeric(16, 2) not null default 0,
  statement_balance numeric(16, 2) not null default 0,
  ledger_balance numeric(16, 2) not null default 0,
  unreconciled_count integer not null default 0,
  is_active boolean not null default true,
  is_primary boolean not null default false,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table finance.bank_accounts is '{
    "icon": "Landmark",
    "name": "Bank Accounts",
    "description": "Where the cash actually sits, and how far the statement is from the ledger.",
    "collapsible_group": "Cash",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["currency", "is_primary"]},
        "tabs": ["bank_transactions", "payments"]
    },
    "views": [
        {"id": "list", "name": "All Accounts", "type": "list", "title": "name", "description": "bank_name", "field_1": "currency", "field_2": "statement_balance"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "unreconciled", "name": "Needs Reconciling", "filters": [{"id": "unreconciled_count", "value": "0", "operator": "gt"}]}
    ],
    "fields": {
        "quick_create": ["code", "name", "currency"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "bank_name", "is_active", "is_primary"]},
            {"id": "details", "title": "Details", "fields": ["account_number", "iban", "swift", "currency"]},
            {"id": "posting", "title": "Posting", "fields": ["gl_account_id", "opening_balance"]},
            {"id": "position", "title": "Position", "fields": {"read": ["statement_balance", "ledger_balance", "unreconciled_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "accounts", "on": "gl_account_id", "columns": ["code", "name"]}]
    }
}';

comment on column finance.bank_accounts.statement_balance is '{"name": "Statement", "aggregate": "sum"}';

comment on column finance.bank_accounts.ledger_balance is '{"name": "Ledger", "aggregate": "sum"}';

revoke all on table finance.bank_accounts
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
delete on table finance.bank_accounts to "x-admin";

grant
select
,
  insert,
update on table finance.bank_accounts to "accountant";

grant
select
  on table finance.bank_accounts to "finance-auditor";

create unique index idx_fin_bank_primary on finance.bank_accounts (is_primary)
where
  is_primary;

alter table finance.bank_accounts enable row level security;

create policy bank_accounts_select on finance.bank_accounts for
select
  to authenticated using (true);

create policy bank_accounts_insert on finance.bank_accounts for insert to authenticated
with
  check (true);

create policy bank_accounts_update on finance.bank_accounts
for update
  to authenticated using (true)
with
  check (true);

create policy bank_accounts_delete on finance.bank_accounts for delete to authenticated using (true);

alter table finance.payments
add constraint payments_bank_account_fk foreign key (bank_account_id) references finance.bank_accounts (id) on delete set null;

create index idx_fin_payments_bank_account_id on finance.payments (bank_account_id);

create table finance.bank_transactions (
  id uuid primary key default extensions.uuid_generate_v4 (),
  bank_account_id uuid not null references finance.bank_accounts (id) on delete cascade,
  transaction_date date not null default current_date,
  value_date date,
  description varchar(300) not null,
  counterparty varchar(200),
  reference varchar(120),
  amount numeric(16, 2) not null,
  running_balance numeric(16, 2),
  status finance.bank_transaction_status not null default 'unreconciled',
  matched_payment_id uuid references finance.payments (id) on delete set null,
  matched_journal_id uuid references finance.journals (id) on delete set null,
  reconciled_on date,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint bank_tx_amount_not_zero check (amount <> 0)
);

comment on column finance.bank_transactions.status is '{
    "progress": true,
    "values": {
        "unreconciled": {"variant": "warning", "icon": "CircleDashed"},
        "matched": {"variant": "info", "icon": "Link"},
        "reconciled": {"variant": "success", "icon": "CircleCheck"},
        "ignored": {"variant": "secondary", "icon": "Ban"}
    }
}';

comment on table finance.bank_transactions is '{
    "icon": "ArrowLeftRight",
    "name": "Bank Statement",
    "description": "Statement lines, and whether each one has been matched to the ledger.",
    "collapsible_group": "Cash",
    "display": "block",
    "inline_form": true,
    "primary_view": "kanban",
    "detail": {"header": {"title": "description", "badges": ["status", "amount"]}},
    "views": [
        {"id": "kanban", "name": "Reconciliation", "type": "kanban", "group": "status", "title": "description", "description": "counterparty", "date": "transaction_date", "badge": "amount"},
        {"id": "calendar", "name": "By Day", "type": "calendar", "title": "description", "badge": "status", "start_date": "transaction_date", "read_only": true},
        {"id": "list", "name": "All Lines", "type": "list", "title": "description", "description": "counterparty", "field_1": "amount", "field_2": "transaction_date"}
    ],
    "filter_presets": [
        {"id": "unreconciled", "name": "Unreconciled", "filters": [{"id": "status", "value": "unreconciled", "operator": "eq"}]},
        {"id": "money_in", "name": "Money In", "filters": [{"id": "amount", "value": "0", "operator": "gt"}]},
        {"id": "money_out", "name": "Money Out", "filters": [{"id": "amount", "value": "0", "operator": "lt"}]}
    ],
    "fields": {
        "quick_create": ["bank_account_id", "transaction_date", "description", "amount"],
        "sections": [
            {"id": "line", "title": "Statement line", "fields": ["bank_account_id", "transaction_date", "value_date", "description", "counterparty", "reference"]},
            {"id": "amount", "title": "Amount", "fields": ["amount", "running_balance"]},
            {"id": "matching", "title": "Matching", "fields": ["status", "matched_payment_id", "matched_journal_id", "reconciled_on", "note"]}
        ],
        "behavior": {
            "matched_payment_id": {"visible": [{"id": "status", "operator": "in", "value": ["matched", "reconciled"]}]},
            "reconciled_on": {"visible": [{"id": "status", "operator": "eq", "value": "reconciled"}]}
        }
    },
    "query": {
        "sort": [{"id": "transaction_date", "desc": true}],
        "join": [
            {"table": "bank_accounts", "on": "bank_account_id", "columns": ["code", "name", "currency"]},
            {"table": "payments", "on": "matched_payment_id", "alias": "payment", "columns": ["payment_number", "amount"]}
        ]
    }
}';

comment on column finance.bank_transactions.amount is '{"aggregate": "sum"}';

revoke all on table finance.bank_transactions
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
delete on table finance.bank_transactions to "x-admin",
"accountant";

grant
select
  on table finance.bank_transactions to "finance-auditor";

create index idx_fin_bank_tx_account_id on finance.bank_transactions (bank_account_id);

create index idx_fin_bank_tx_status on finance.bank_transactions (status);

create index idx_fin_bank_tx_date on finance.bank_transactions (transaction_date desc);

create index idx_fin_bank_tx_open on finance.bank_transactions (bank_account_id, transaction_date)
where
  status = 'unreconciled';

alter table finance.bank_transactions enable row level security;

create policy bank_tx_select on finance.bank_transactions for
select
  to authenticated using (true);

create policy bank_tx_insert on finance.bank_transactions for insert to authenticated
with
  check (true);

create policy bank_tx_update on finance.bank_transactions
for update
  to authenticated using (true)
with
  check (true);

create policy bank_tx_delete on finance.bank_transactions for delete to authenticated using (true);

----------------------------------------------------------------
-- Expense claims (the one place an ordinary employee writes)
----------------------------------------------------------------
create sequence if not exists finance.claim_number_seq;

create table finance.expense_claims (
  id uuid primary key default extensions.uuid_generate_v4 (),
  claim_number varchar(30) not null unique default (
    'EXP-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('finance.claim_number_seq')::text, 5, '0')
  ),
  claimant_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  claimant_name varchar(200),
  cost_center_id uuid references finance.cost_centers (id) on delete set null,
  status finance.expense_status not null default 'draft',
  title varchar(200) not null,
  purpose varchar(300),
  currency varchar(3) not null default 'USD',
  total_amount numeric(16, 2) not null default 0,
  reimbursable_amount numeric(16, 2) not null default 0,
  line_count integer not null default 0,
  period_id uuid references finance.fiscal_periods (id) on delete set null,
  journal_id uuid references finance.journals (id) on delete set null,
  submitted_at timestamptz,
  approved_by uuid references supasheet.users (id) on delete set null,
  approved_at timestamptz,
  rejected_reason varchar(300),
  reimbursed_on date,
  -- Submission to money in the bank. The one number a claimant judges
  -- the finance team on, and the only genuine duration in the schema.
  time_to_reimburse supasheet.DURATION,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint claims_amounts_non_negative check (
    total_amount >= 0
    and reimbursable_amount >= 0
  )
);

comment on column finance.expense_claims.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "submitted": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "info", "icon": "CircleCheck"},
        "rejected": {"variant": "destructive", "icon": "CircleX"},
        "reimbursed": {"variant": "success", "icon": "BadgeDollarSign"}
    }
}';

comment on table finance.expense_claims is '{
    "icon": "Wallet",
    "name": "Expense Claims",
    "description": "What people have spent on the company card or their own.",
    "collapsible_group": "Payables",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "title", "badges": ["status", "total_amount"]},
        "tabs": ["expense_lines"]
    },
    "views": [
        {"id": "kanban", "name": "Approval Board", "type": "kanban", "group": "status", "title": "title", "description": "purpose", "date": "submitted_at", "badge": "currency"},
        {"id": "list", "name": "All Claims", "type": "list", "title": "title", "description": "purpose", "field_1": "status", "field_2": "total_amount"}
    ],
    "filter_presets": [
        {"id": "to_approve", "name": "To Approve", "filters": [{"id": "status", "value": "submitted", "operator": "eq"}]},
        {"id": "to_pay", "name": "To Reimburse", "filters": [{"id": "status", "value": "approved", "operator": "eq"}]},
        {"id": "mine", "name": "Drafts", "filters": [{"id": "status", "value": "draft", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["title", "purpose", "cost_center_id"],
        "sections": [
            {"id": "claim", "title": "Claim", "fields": ["title", "purpose", "cost_center_id", "currency"]},
            {"id": "state", "title": "State", "fields": ["status", "rejected_reason"]},
            {"id": "totals", "title": "Totals", "fields": {"read": ["line_count", "total_amount", "reimbursable_amount"]}},
            {"id": "audit", "title": "Trail", "fields": {"read": ["claimant_name", "submitted_at", "approved_by", "approved_at", "reimbursed_on", "time_to_reimburse", "journal_id"]}}
        ],
        "behavior": {
            "rejected_reason": {
                "visible": [{"id": "status", "operator": "eq", "value": "rejected"}],
                "required": [{"id": "status", "operator": "eq", "value": "rejected"}]
            }
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "users", "on": "claimant_id", "alias": "claimant", "columns": ["name", "email"]},
            {"table": "cost_centers", "on": "cost_center_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column finance.expense_claims.time_to_reimburse is '{"name": "Time To Reimburse"}';

comment on column finance.expense_claims.total_amount is '{"name": "Total", "aggregate": "sum"}';

revoke all on table finance.expense_claims
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
delete on table finance.expense_claims to "x-admin";

grant
select
,
  insert,
update on table finance.expense_claims to "accountant";

grant
select
  on table finance.expense_claims to "finance-auditor";

grant
select
,
  insert,
update on table finance.expense_claims to "user";

revoke all on sequence finance.claim_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence finance.claim_number_seq to "x-admin",
"accountant",
"user";

create index idx_fin_claims_claimant_id on finance.expense_claims (claimant_id);

create index idx_fin_claims_status on finance.expense_claims (status);

alter table finance.expense_claims enable row level security;

-- An employee sees their own claims and nothing else; finance sees
-- the lot.
create policy claims_select on finance.expense_claims for
select
  to authenticated using (
    finance.is_finance_staff ()
    or claimant_id = (
      select
        auth.uid ()
    )
  );

create policy claims_insert on finance.expense_claims for insert to authenticated
with
  check (
    finance.is_finance_staff ()
    or claimant_id = (
      select
        auth.uid ()
    )
  );

create policy claims_update on finance.expense_claims
for update
  to authenticated using (
    finance.is_finance_staff ()
    or claimant_id = (
      select
        auth.uid ()
    )
  )
with
  check (true);

create policy claims_delete on finance.expense_claims for delete to authenticated using (true);

create table finance.expense_lines (
  id uuid primary key default extensions.uuid_generate_v4 (),
  claim_id uuid not null references finance.expense_claims (id) on delete cascade,
  account_id uuid references finance.accounts (id) on delete set null,
  tax_rate_id uuid references finance.tax_rates (id) on delete set null,
  category finance.expense_category not null default 'other',
  spent_on date not null default current_date,
  merchant varchar(160),
  description varchar(300) not null,
  net_amount numeric(16, 2) not null default 0,
  tax_amount numeric(16, 2) not null default 0,
  gross_amount numeric(16, 2) not null default 0,
  is_reimbursable boolean not null default true,
  has_receipt boolean not null default false,
  receipt supasheet.file,
  created_at timestamptz default current_timestamp,
  constraint expense_lines_amounts_non_negative check (
    net_amount >= 0
    and tax_amount >= 0
  )
);

comment on column finance.expense_lines.category is '{
    "progress": false,
    "values": {
        "travel": {"variant": "info", "icon": "Plane"},
        "accommodation": {"variant": "default", "icon": "House"},
        "meals": {"variant": "warning", "icon": "Utensils"},
        "software": {"variant": "secondary", "icon": "Laptop"},
        "hardware": {"variant": "secondary", "icon": "HardDrive"},
        "training": {"variant": "success", "icon": "GraduationCap"},
        "entertainment": {"variant": "warning", "icon": "PartyPopper"},
        "other": {"variant": "secondary", "icon": "Ellipsis"}
    }
}';

comment on table finance.expense_lines is '{
    "icon": "ReceiptText",
    "name": "Expense Lines",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "line", "title": "Line", "fields": ["claim_id", "spent_on", "category", "merchant", "description"]},
            {"id": "amounts", "title": "Amounts", "fields": ["net_amount", "tax_amount", "tax_rate_id", "is_reimbursable"]},
            {"id": "coding", "title": "Coding", "fields": ["account_id"]},
            {"id": "evidence", "title": "Evidence", "fields": ["receipt", "has_receipt"]}
        ],
        "behavior": {
            "receipt": {"required": [{"id": "is_reimbursable", "operator": "eq", "value": "true"}]}
        }
    },
    "query": {
        "sort": [{"id": "spent_on", "desc": true}],
        "join": [
            {"table": "expense_claims", "on": "claim_id", "columns": ["claim_number", "status"]},
            {"table": "accounts", "on": "account_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column finance.expense_lines.gross_amount is '{"name": "Gross", "aggregate": "sum"}';

comment on column finance.expense_lines.receipt is '{"accept": ".pdf,.png,.jpg", "max_files": 3, "max_size": 5242880}';

revoke all on table finance.expense_lines
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
delete on table finance.expense_lines to "x-admin",
"accountant";

grant
select
  on table finance.expense_lines to "finance-auditor";

grant
select
,
  insert,
update,
delete on table finance.expense_lines to "user";

create index idx_fin_expense_lines_claim_id on finance.expense_lines (claim_id);

alter table finance.expense_lines enable row level security;

create policy expense_lines_select on finance.expense_lines for
select
  to authenticated using (
    finance.is_finance_staff ()
    or exists (
      select
        1
      from
        finance.expense_claims c
      where
        c.id = claim_id
        and c.claimant_id = (
          select
            auth.uid ()
        )
    )
  );

create policy expense_lines_insert on finance.expense_lines for insert to authenticated
with
  check (true);

create policy expense_lines_update on finance.expense_lines
for update
  to authenticated using (true)
with
  check (true);

create policy expense_lines_delete on finance.expense_lines for delete to authenticated using (true);

----------------------------------------------------------------
-- Budgets and fixed assets
----------------------------------------------------------------
create table finance.budgets (
  id uuid primary key default extensions.uuid_generate_v4 (),
  fiscal_year integer not null,
  period_id uuid references finance.fiscal_periods (id) on delete cascade,
  account_id uuid not null references finance.accounts (id) on delete cascade,
  cost_center_id uuid references finance.cost_centers (id) on delete cascade,
  status finance.budget_status not null default 'draft',
  budget_amount numeric(16, 2) not null default 0,
  actual_amount numeric(16, 2) not null default 0,
  variance_amount numeric(16, 2) not null default 0,
  variance_percent supasheet.PERCENTAGE,
  note varchar(300),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (
    fiscal_year,
    period_id,
    account_id,
    cost_center_id
  )
);

comment on table finance.budgets is '{
    "icon": "ChartNoAxesColumn",
    "description": "What was planned, what actually happened, and the gap.",
    "collapsible_group": "Planning",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "fiscal_year", "badges": ["status", "variance_percent"]}},
    "views": [
        {"id": "list", "name": "Budget vs Actual", "type": "list", "title": "fiscal_year", "description": "note", "field_1": "budget_amount", "field_2": "variance_amount"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "note", "description": "fiscal_year", "date": "created_at", "badge": "status"}
    ],
    "filter_presets": [
        {"id": "over", "name": "Over Budget", "filters": [{"id": "variance_amount", "value": "0", "operator": "lt"}]},
        {"id": "approved", "name": "Approved", "filters": [{"id": "status", "value": "approved", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["fiscal_year", "account_id", "budget_amount"],
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["fiscal_year", "period_id", "account_id", "cost_center_id"]},
            {"id": "amounts", "title": "Amounts", "fields": ["budget_amount", "status", "note"]},
            {"id": "variance", "title": "Variance", "fields": {"read": ["actual_amount", "variance_amount", "variance_percent"]}}
        ]
    },
    "query": {
        "sort": [{"id": "fiscal_year", "desc": true}],
        "join": [
            {"table": "accounts", "on": "account_id", "columns": ["code", "name", "account_type"]},
            {"table": "cost_centers", "on": "cost_center_id", "columns": ["code", "name"]},
            {"table": "fiscal_periods", "on": "period_id", "columns": ["code", "status"]}
        ]
    }
}';

comment on column finance.budgets.budget_amount is '{"name": "Budget", "aggregate": "sum"}';

comment on column finance.budgets.actual_amount is '{"name": "Actual", "aggregate": "sum"}';

comment on column finance.budgets.variance_amount is '{"name": "Variance", "aggregate": "sum"}';

revoke all on table finance.budgets
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
delete on table finance.budgets to "x-admin";

grant
select
,
  insert,
update on table finance.budgets to "accountant";

grant
select
  on table finance.budgets to "finance-auditor";

create index idx_fin_budgets_account_id on finance.budgets (account_id);

create index idx_fin_budgets_cost_center_id on finance.budgets (cost_center_id);

alter table finance.budgets enable row level security;

create policy budgets_select on finance.budgets for
select
  to authenticated using (true);

create policy budgets_insert on finance.budgets for insert to authenticated
with
  check (true);

create policy budgets_update on finance.budgets
for update
  to authenticated using (true)
with
  check (true);

create policy budgets_delete on finance.budgets for delete to authenticated using (true);

create table finance.fixed_assets (
  id uuid primary key default extensions.uuid_generate_v4 (),
  asset_code varchar(30) not null unique,
  name varchar(200) not null,
  description text,
  category varchar(80),
  status finance.asset_status not null default 'in_service',
  depreciation_method finance.depreciation_method not null default 'straight_line',
  asset_account_id uuid references finance.accounts (id) on delete set null,
  depreciation_account_id uuid references finance.accounts (id) on delete set null,
  cost_center_id uuid references finance.cost_centers (id) on delete set null,
  purchase_date date not null default current_date,
  in_service_date date,
  purchase_cost numeric(16, 2) not null default 0,
  residual_value numeric(16, 2) not null default 0,
  useful_life_months integer not null default 36,
  accumulated_depreciation numeric(16, 2) not null default 0,
  net_book_value numeric(16, 2) not null default 0,
  monthly_depreciation numeric(16, 2) not null default 0,
  last_depreciated_on date,
  disposal_date date,
  disposal_proceeds numeric(16, 2),
  serial_number varchar(80),
  location varchar(160),
  photo supasheet.file,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint assets_cost_non_negative check (
    purchase_cost >= 0
    and residual_value >= 0
  ),
  constraint assets_residual_within_cost check (residual_value <= purchase_cost),
  constraint assets_life_positive check (useful_life_months > 0)
);

comment on column finance.fixed_assets.status is '{
    "progress": true,
    "values": {
        "in_service": {"variant": "success", "icon": "CircleCheck"},
        "idle": {"variant": "secondary", "icon": "PauseCircle"},
        "disposed": {"variant": "warning", "icon": "PackageX"},
        "written_off": {"variant": "destructive", "icon": "TriangleAlert"}
    }
}';

comment on table finance.fixed_assets is '{
    "icon": "Boxes",
    "name": "Fixed Assets",
    "description": "The asset register, its depreciation and its net book value.",
    "collapsible_group": "Planning",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "name", "badges": ["status", "net_book_value"]}},
    "views": [
        {"id": "list", "name": "Register", "type": "list", "title": "name", "description": "category", "field_1": "purchase_cost", "field_2": "net_book_value"},
        {"id": "gallery", "name": "Asset Photos", "type": "gallery", "cover": "photo", "title": "name", "description": "location", "badge": "status"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "name", "description": "category", "date": "purchase_date", "badge": "depreciation_method"},
        {"id": "gantt", "name": "Useful Life", "type": "gantt", "title": "name", "start_date": "purchase_date", "end_date": "disposal_date", "group": "status", "badge": "category"}
    ],
    "filter_presets": [
        {"id": "in_service", "name": "In Service", "filters": [{"id": "status", "value": "in_service", "operator": "eq"}]},
        {"id": "fully_depreciated", "name": "Fully Depreciated", "filters": [{"id": "net_book_value", "value": "0", "operator": "lte"}]}
    ],
    "fields": {
        "quick_create": ["asset_code", "name", "purchase_cost", "purchase_date"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["asset_code", "name", "description", "category", "serial_number", "location", "photo"]},
            {"id": "acquisition", "title": "Acquisition", "fields": ["purchase_date", "in_service_date", "purchase_cost", "residual_value"]},
            {"id": "depreciation", "title": "Depreciation", "fields": ["depreciation_method", "useful_life_months", "asset_account_id", "depreciation_account_id", "cost_center_id"]},
            {"id": "position", "title": "Position", "fields": {"read": ["monthly_depreciation", "accumulated_depreciation", "net_book_value", "last_depreciated_on"]}},
            {"id": "disposal", "title": "Disposal", "fields": ["status", "disposal_date", "disposal_proceeds"]}
        ],
        "behavior": {
            "disposal_date": {"visible": [{"id": "status", "operator": "in", "value": ["disposed", "written_off"]}], "required": [{"id": "status", "operator": "eq", "value": "disposed"}]},
            "disposal_proceeds": {"visible": [{"id": "status", "operator": "eq", "value": "disposed"}]},
            "useful_life_months": {"visible": [{"id": "depreciation_method", "operator": "neq", "value": "none"}]}
        }
    },
    "query": {
        "sort": [{"id": "asset_code", "desc": false}],
        "join": [
            {"table": "accounts", "on": "asset_account_id", "alias": "asset_account", "columns": ["code", "name"]},
            {"table": "cost_centers", "on": "cost_center_id", "columns": ["code", "name"]}
        ]
    }
}';

comment on column finance.fixed_assets.photo is '{"accept": "image/*", "max_files": 4, "max_size": 5242880}';

comment on column finance.fixed_assets.purchase_cost is '{"name": "Cost", "aggregate": "sum"}';

comment on column finance.fixed_assets.net_book_value is '{"name": "NBV", "aggregate": "sum"}';

comment on column finance.fixed_assets.accumulated_depreciation is '{"name": "Accum. Dep.", "aggregate": "sum"}';

revoke all on table finance.fixed_assets
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
delete on table finance.fixed_assets to "x-admin";

grant
select
,
  insert,
update on table finance.fixed_assets to "accountant";

grant
select
  on table finance.fixed_assets to "finance-auditor";

create index idx_fin_assets_status on finance.fixed_assets (status);

alter table finance.fixed_assets enable row level security;

create policy assets_select on finance.fixed_assets for
select
  to authenticated using (true);

create policy assets_insert on finance.fixed_assets for insert to authenticated
with
  check (true);

create policy assets_update on finance.fixed_assets
for update
  to authenticated using (true)
with
  check (true);

create policy assets_delete on finance.fixed_assets for delete to authenticated using (true);

----------------------------------------------------------------
-- Finance settings (singleton)
----------------------------------------------------------------
create table finance.finance_settings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  company_name varchar(200) not null default 'Supasheet',
  logo supasheet.file,
  base_currency varchar(3) not null default 'USD',
  fiscal_year_start_month integer not null default 1,
  default_payment_terms_days integer not null default 30,
  default_tax_rate_id uuid references finance.tax_rates (id) on delete set null,
  receivable_account_id uuid references finance.accounts (id) on delete set null,
  payable_account_id uuid references finance.accounts (id) on delete set null,
  bank_account_id uuid references finance.bank_accounts (id) on delete set null,
  expense_clearing_account_id uuid references finance.accounts (id) on delete set null,
  retained_earnings_account_id uuid references finance.accounts (id) on delete set null,
  auto_post_invoices boolean not null default true,
  require_receipt_over numeric(10, 2) not null default 25,
  overdue_reminder_days integer not null default 7,
  timezone varchar(100) not null default 'UTC',
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint settings_month_range check (fiscal_year_start_month between 1 and 12)
);

comment on table finance.finance_settings is '{
    "icon": "Settings",
    "name": "Finance Settings",
    "description": "The accounts and policy every posting routine reads.",
    "collapsible_group": "Configuration",
    "display": "block",
    "singleton": true,
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["company_name", "logo", "base_currency", "fiscal_year_start_month", "timezone"]},
            {"id": "control", "title": "Control accounts", "fields": ["receivable_account_id", "payable_account_id", "bank_account_id", "expense_clearing_account_id", "retained_earnings_account_id"]},
            {"id": "policy", "title": "Policy", "fields": ["default_payment_terms_days", "default_tax_rate_id", "auto_post_invoices", "require_receipt_over", "overdue_reminder_days"]}
        ]
    },
    "query": {
        "join": [{"table": "accounts", "on": "receivable_account_id", "alias": "ar_account", "columns": ["code", "name"]}]
    }
}';

comment on column finance.finance_settings.logo is '{"accept": "image/*", "max_size": 2097152}';

revoke all on table finance.finance_settings
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update on table finance.finance_settings to "x-admin";

grant
select
  on table finance.finance_settings to "accountant",
  "finance-auditor";

alter table finance.finance_settings enable row level security;

create policy settings_select on finance.finance_settings for
select
  to authenticated using (true);

create policy settings_insert on finance.finance_settings for insert to authenticated
with
  check (true);

create policy settings_update on finance.finance_settings
for update
  to authenticated using (true)
with
  check (true);

----------------------------------------------------------------
-- Shared helpers
----------------------------------------------------------------
create or replace function finance.set_updated_at () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  new.updated_at := current_timestamp;
  return new;
end;
$$;

-- The singleton settings row, or nothing if the module has not been
-- configured yet. Every posting routine reads its control accounts
-- from here rather than hard-coding a code like '1100'.
create or replace function finance.settings () returns finance.finance_settings language sql stable security definer
set
  search_path = '' as $$
  select * from finance.finance_settings limit 1;
$$;

-- Posted rows are immutable to people. They are not immutable to this
-- module: a reversal has to stamp the original, and the maintenance
-- routines have to move rollups. Those paths open this transaction-local
-- flag, do their work and close it again, so the guards below can tell
-- "the module did this" from "a human did this".
create or replace function finance.posted_write_allowed () returns boolean language sql stable
set
  search_path = '' as $$
  select coalesce(current_setting('finance.allow_posted_write', true), 'off') = 'on';
$$;

create or replace function finance.assert_period_open (p_period_id uuid, p_what text) returns void language plpgsql stable security definer
set
  search_path = '' as $$
declare
  v_status finance.period_status;
  v_code varchar(20);
begin
  if p_period_id is null then
    return;
  end if;

  select status, code into v_status, v_code
  from finance.fiscal_periods
  where id = p_period_id;

  if v_status is null then
    return;
  end if;

  if v_status <> 'open' then
    raise exception '% into period % is not allowed: the period is %.', p_what, v_code, v_status
      using hint = 'Reopen the period, or date the entry into a period that is open.';
  end if;
end;
$$;

-- Every account from p_id down. The chart is small and read far more
-- often than it changes, so a recursive walk is cheaper than keeping a
-- denormalised path column honest.
create or replace function finance.account_subtree (p_id uuid) returns setof uuid language sql stable security definer
set
  search_path = '' as $$
  with recursive sub as (
    select p_id as id
    union all
    select a.id from finance.accounts a join sub s on a.parent_id = s.id
  )
  select id from sub;
$$;

-- Balances are derived from POSTED lines only, and a parent carries the
-- whole subtree beneath it, so the chart reads like a trial balance at
-- any level. Drafts never move a number anybody reports on.
--
-- A reversed journal still counts. Reversing does not erase an entry,
-- it books an equal and opposite one; both sides stay in the ledger and
-- cancel each other, which is exactly what an auditor expects to find.
create or replace function finance.recalc_account_balances (p_account_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_account_ids is null or cardinality(p_account_ids) = 0 then
    return;
  end if;

  with recursive targets as (
    select distinct x.id
    from unnest(p_account_ids) as x (id)
    where x.id is not null
    union
    select a.parent_id
    from finance.accounts a
      join targets t on a.id = t.id
    where a.parent_id is not null
  )
  update finance.accounts a
  set debit_total = s.d,
    credit_total = s.c,
    current_balance = a.opening_balance + case
      when a.normal_balance = 'debit' then s.d - s.c
      else s.c - s.d
    end,
    updated_at = current_timestamp
  from targets t
    cross join lateral (
      select coalesce(sum(l.debit), 0) as d, coalesce(sum(l.credit), 0) as c
      from finance.journal_lines l
        join finance.journals j on j.id = l.journal_id
      where j.status <> 'draft'
        and l.account_id in (select finance.account_subtree (t.id))
    ) s
  where a.id = t.id
    and (a.debit_total, a.credit_total) is distinct from (s.d, s.c);
end;
$$;

create or replace function finance.recalc_period_totals (p_period_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_period_ids is null or cardinality(p_period_ids) = 0 then
    return;
  end if;

  update finance.fiscal_periods p
  set journal_count = s.n,
    posted_total = s.amount,
    updated_at = current_timestamp
  from (select distinct x.id from unnest(p_period_ids) as x (id) where x.id is not null) t
    cross join lateral (
      select count(*) as n, coalesce(sum(j.total_debit), 0) as amount
      from finance.journals j
      where j.period_id = t.id
        and j.status <> 'draft'
    ) s
  where p.id = t.id
    and (p.journal_count, p.posted_total) is distinct from (s.n::integer, s.amount);
end;
$$;

create or replace function finance.log_journal_event (
  p_journal_id uuid,
  p_type finance.journal_event_type,
  p_title text,
  p_metadata jsonb default '{}'::jsonb
) returns void language sql security definer
set
  search_path = '' as $$
  insert into finance.journal_events (journal_id, event_type, title, metadata, actor_id)
  values (p_journal_id, p_type, left(p_title, 200), coalesce(p_metadata, '{}'::jsonb), auth.uid ());
$$;

revoke all on function finance.settings ()
from
  public;

revoke all on function finance.recalc_account_balances (uuid[])
from
  public;

revoke all on function finance.recalc_period_totals (uuid[])
from
  public;

revoke all on function finance.log_journal_event (uuid, finance.journal_event_type, text, jsonb)
from
  public;

grant
execute on function finance.settings () to "x-admin",
"accountant",
"finance-auditor";

grant
execute on function finance.account_subtree (uuid) to "x-admin",
"accountant",
"finance-auditor";

grant
execute on function finance.assert_period_open (uuid, text) to "x-admin",
"accountant";

----------------------------------------------------------------
-- Period locking
----------------------------------------------------------------
create or replace function finance.periods_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_drafts integer;
begin
  if new.status is distinct from old.status then
    if new.status in ('closed', 'locked') and old.status = 'open' then
      select count(*) into v_drafts
      from finance.journals
      where period_id = new.id
        and status = 'draft';

      if v_drafts > 0 then
        raise exception 'Period % still has % unposted draft journal(s).', new.code, v_drafts
          using hint = 'Post them or move them to another period before closing.';
      end if;

      new.closed_on := coalesce(new.closed_on, current_date);
      new.closed_by := coalesce(new.closed_by, auth.uid ());
    end if;

    -- Locked is the end of the line. Only the controller can undo it,
    -- and doing so is an event somebody should have to explain.
    if old.status = 'locked'
      and new.status <> 'locked'
      and not pg_has_role(current_user, 'x-admin', 'member') then
      raise exception 'Period % is locked and only the controller can reopen it.', new.code;
    end if;

    if new.status = 'open' then
      new.closed_on := null;
      new.closed_by := null;
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_periods_guard
before update on finance.fiscal_periods for each row
execute function finance.periods_guard ();

create trigger trg_periods_updated_at
before update on finance.fiscal_periods for each row
execute function finance.set_updated_at ();

----------------------------------------------------------------
-- Journals: the four ledger rules live here
----------------------------------------------------------------
create or replace function finance.journals_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.period_id := coalesce(new.period_id, finance.period_for_date (new.entry_date));

    if new.status = 'posted' then
      raise exception 'A journal cannot be created already posted.'
        using hint = 'Create the draft, add its lines, then post it.';
    end if;

    perform finance.assert_period_open (new.period_id, 'Dating a journal');
    return new;
  end if;

  -- IMMUTABILITY. Once a journal is posted it is history. The only way
  -- back is a reversing entry, which is itself a journal that anybody
  -- reading the ledger can see.
  if old.status <> 'draft'
    and pg_trigger_depth() = 1
    and not finance.posted_write_allowed () then
    raise exception 'Journal % is % and cannot be edited.', old.journal_number, old.status
      using hint = 'Reverse it instead — the reversal is itself an entry.';
  end if;

  if new.entry_date is distinct from old.entry_date then
    new.period_id := finance.period_for_date (new.entry_date);
  end if;

  if new.status = 'posted' and old.status = 'draft' then
    if coalesce(new.line_count, 0) < 2 then
      raise exception 'Journal % needs at least two lines before it can be posted.', new.journal_number;
    end if;

    -- DOUBLE ENTRY, to the cent.
    if not new.is_balanced then
      raise exception 'Journal % does not balance: debits %, credits %.',
        new.journal_number, new.total_debit, new.total_credit;
    end if;

    -- PERIOD LOCKING.
    perform finance.assert_period_open (new.period_id, 'Posting a journal');

    new.posted_at := coalesce(new.posted_at, current_timestamp);
    new.posted_by := coalesce(new.posted_by, auth.uid ());
  end if;

  if new.status = 'draft' and old.status <> 'draft' then
    raise exception 'Journal % cannot be returned to draft once posted.', old.journal_number;
  end if;

  return new;
end;
$$;

create trigger trg_journals_guard
before insert or update on finance.journals for each row
execute function finance.journals_guard ();

create or replace function finance.journals_delete_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  if old.status <> 'draft' and not finance.posted_write_allowed () then
    raise exception 'Journal % is % and cannot be deleted.', old.journal_number, old.status
      using hint = 'Reverse it instead.';
  end if;

  return old;
end;
$$;

create trigger trg_journals_delete_guard
before delete on finance.journals for each row
execute function finance.journals_delete_guard ();

create trigger trg_journals_updated_at
before update on finance.journals for each row
execute function finance.set_updated_at ();

create or replace function finance.journals_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_accounts uuid[];
begin
  if tg_op = 'INSERT' then
    perform finance.log_journal_event (
      new.id, 'created', 'Draft journal ' || new.journal_number || ' created',
      jsonb_build_object('source', new.source, 'entry_date', new.entry_date)
    );
    perform finance.recalc_period_totals (array[new.period_id]);
    return new;
  end if;

  if tg_op = 'DELETE' then
    perform finance.recalc_period_totals (array[old.period_id]);
    return old;
  end if;

  if new.status is distinct from old.status then
    if new.status = 'posted' then
      perform finance.log_journal_event (
        new.id, 'posted', 'Posted ' || new.journal_number,
        jsonb_build_object('total', new.total_debit, 'lines', new.line_count)
      );
    elsif new.status = 'reversed' then
      perform finance.log_journal_event (
        new.id, 'reversed', 'Reversed ' || new.journal_number,
        jsonb_build_object('reversed_by', new.reversed_by_journal_id)
      );
    end if;

    -- Posting (or reversing) is the only thing that can move an account
    -- balance, so this is the only place that has to recompute them.
    select array_agg(distinct l.account_id) into v_accounts
    from finance.journal_lines l
    where l.journal_id = new.id
      and l.account_id is not null;

    perform finance.recalc_account_balances (v_accounts);
    perform finance.recalc_period_totals (array[new.period_id, old.period_id]);
  elsif new.period_id is distinct from old.period_id then
    perform finance.recalc_period_totals (array[new.period_id, old.period_id]);
  end if;

  return new;
end;
$$;

create trigger trg_journals_after_change
after insert or delete or update on finance.journals for each row
execute function finance.journals_after_change ();

----------------------------------------------------------------
-- Journal lines
----------------------------------------------------------------
create or replace function finance.journal_lines_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_journal finance.journals;
  v_row finance.journal_lines;
begin
  v_row := coalesce(new, old);

  select * into v_journal from finance.journals where id = v_row.journal_id;

  if v_journal.status <> 'draft' and not finance.posted_write_allowed () then
    raise exception 'Journal % is % — its lines cannot be changed.',
      v_journal.journal_number, v_journal.status
      using hint = 'Reverse the entry and re-enter it.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  if new.line_number is null then
    select coalesce(max(line_number), 0) + 1 into new.line_number
    from finance.journal_lines
    where journal_id = new.journal_id;
  end if;

  new.debit := round(coalesce(new.debit, 0), 2);
  new.credit := round(coalesce(new.credit, 0), 2);

  return new;
end;
$$;

create trigger trg_journal_lines_guard
before insert or delete or update on finance.journal_lines for each row
execute function finance.journal_lines_guard ();

create or replace function finance.journal_lines_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_journal_id uuid;
  v_debit numeric(16, 2);
  v_credit numeric(16, 2);
  v_count integer;
begin
  v_journal_id := coalesce(new.journal_id, old.journal_id);

  select coalesce(sum(debit), 0), coalesce(sum(credit), 0), count(*)
  into v_debit, v_credit, v_count
  from finance.journal_lines
  where journal_id = v_journal_id;

  -- Guarded so a multi-line insert does not write the same totals five
  -- times and leave five identical rows in the audit log.
  update finance.journals
  set total_debit = v_debit,
    total_credit = v_credit,
    line_count = v_count,
    is_balanced = (v_debit = v_credit and v_debit > 0)
  where id = v_journal_id
    and (total_debit, total_credit, line_count) is distinct from (v_debit, v_credit, v_count);

  if found then
    perform finance.log_journal_event (
      v_journal_id, 'line_changed', 'Lines updated: ' || v_count || ' line(s), ' || v_debit || ' Dr / ' || v_credit || ' Cr',
      jsonb_build_object('debit', v_debit, 'credit', v_credit, 'balanced', v_debit = v_credit)
    );
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_journal_lines_rollup
after insert or delete or update on finance.journal_lines for each row
execute function finance.journal_lines_rollup ();

----------------------------------------------------------------
-- Sales ledger: invoices, their lines, and what they do to the
-- customer's position
----------------------------------------------------------------
create or replace function finance.invoice_lines_compute () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_rate real;
begin
  if new.line_number is null then
    select coalesce(max(line_number), 0) + 1 into new.line_number
    from finance.invoice_lines
    where invoice_id = new.invoice_id;
  end if;

  new.net_amount := round(
    coalesce(new.quantity, 0) * coalesce(new.unit_price, 0)
      * (1 - coalesce(new.discount_percent, 0)::numeric / 100),
    2
  );

  select rate into v_rate from finance.tax_rates where id = new.tax_rate_id;

  new.tax_amount := round(new.net_amount * coalesce(v_rate, 0)::numeric / 100, 2);
  new.line_total := new.net_amount + new.tax_amount;

  return new;
end;
$$;

create trigger trg_invoice_lines_compute
before insert or update on finance.invoice_lines for each row
execute function finance.invoice_lines_compute ();

create or replace function finance.invoice_lines_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_status finance.invoice_status;
  v_number varchar(30);
begin
  select status, invoice_number into v_status, v_number
  from finance.invoices
  where id = coalesce(new.invoice_id, old.invoice_id);

  -- A line can only be touched while the invoice is still a draft.
  -- After that the invoice has been sent to a customer and, if the
  -- module posted it, sits behind a posted journal.
  if v_status is not null and v_status <> 'draft' then
    raise exception 'Invoice % has been issued — its lines cannot be changed.', v_number
      using hint = 'Void it and raise a credit, or issue a new invoice.';
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_invoice_lines_guard
before insert or delete or update on finance.invoice_lines for each row
execute function finance.invoice_lines_guard ();

create or replace function finance.invoice_lines_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_invoice_id uuid;
  v_net numeric(16, 2);
  v_tax numeric(16, 2);
begin
  v_invoice_id := coalesce(new.invoice_id, old.invoice_id);

  select coalesce(sum(net_amount), 0), coalesce(sum(tax_amount), 0)
  into v_net, v_tax
  from finance.invoice_lines
  where invoice_id = v_invoice_id;

  update finance.invoices
  set subtotal = v_net,
    tax_total = v_tax,
    total = v_net + v_tax
  where id = v_invoice_id
    and (subtotal, tax_total) is distinct from (v_net, v_tax);

  return coalesce(new, old);
end;
$$;

create trigger trg_invoice_lines_rollup
after insert or delete or update on finance.invoice_lines for each row
execute function finance.invoice_lines_rollup ();

create or replace function finance.invoices_derive () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_terms integer;
begin
  if new.due_date is null then
    select payment_terms_days into v_terms
    from finance.customers
    where id = new.customer_id;

    new.due_date := new.issue_date + coalesce(
      v_terms,
      (finance.settings ()).default_payment_terms_days,
      30
    );
  end if;

  new.period_id := coalesce(new.period_id, finance.period_for_date (new.issue_date));

  -- A void invoice is not owed. Leaving the arithmetic answer in
  -- balance_due would put cancelled paper into every total that sums
  -- the column.
  new.balance_due := case
    when new.status = 'void' then 0
    else new.total - new.paid_total
  end;

  -- Only draft and void are choices. Everything between them is a
  -- consequence of the money, so the board and the aging report can
  -- never disagree with the ledger.
  if new.status not in ('draft', 'void') then
    if new.total > 0 and new.paid_total >= new.total then
      new.status := 'paid';
      new.paid_at := coalesce(new.paid_at, current_timestamp);
    elsif new.due_date < current_date then
      -- Lateness outranks partial payment. An invoice half paid three
      -- months after it fell due is a collections problem, and calling
      -- it "partially paid" is how it stops being chased.
      new.status := 'overdue';
      new.paid_at := null;
    elsif new.paid_total > 0 then
      new.status := 'partially_paid';
      new.paid_at := null;
    else
      new.status := 'sent';
      new.paid_at := null;
    end if;

    new.sent_at := coalesce(new.sent_at, current_timestamp);
  end if;

  new.days_overdue := case
    when new.status in ('draft', 'void', 'paid') then 0
    when new.due_date < current_date then (current_date - new.due_date)
    else 0
  end;

  if new.status = 'void' then
    if coalesce(new.voided_reason, '') = '' then
      raise exception 'Voiding invoice % needs a reason.', new.invoice_number;
    end if;

    if new.paid_total > 0 then
      raise exception 'Invoice % has % already collected against it and cannot be voided.',
        new.invoice_number, new.paid_total
        using hint = 'Refund or reallocate the receipt first.';
    end if;
  end if;

  if tg_op = 'UPDATE' and old.status = 'void' and new.status <> 'void' then
    raise exception 'Invoice % is void and cannot be reopened.', old.invoice_number;
  end if;

  return new;
end;
$$;

create trigger trg_invoices_derive
before insert or update on finance.invoices for each row
execute function finance.invoices_derive ();

create trigger trg_invoices_updated_at
before update on finance.invoices for each row
execute function finance.set_updated_at ();

-- Turn an issued invoice into a journal: debit the customer's
-- receivable control account, credit the income each line was coded to,
-- credit the tax collected. Returns the journal, or null when the chart
-- has not been wired up enough to post anything.
create or replace function finance.post_invoice (p_invoice_id uuid) returns uuid language plpgsql security definer
set
  search_path = '' as $$
declare
  v_invoice finance.invoices;
  v_settings finance.finance_settings;
  v_ar uuid;
  v_journal_id uuid;
  v_uncoded integer;
begin
  select * into v_invoice from finance.invoices where id = p_invoice_id;

  if v_invoice.id is null then
    raise exception 'Invoice % does not exist.', p_invoice_id;
  end if;

  if v_invoice.journal_id is not null then
    return v_invoice.journal_id;
  end if;

  if v_invoice.status in ('draft', 'void') then
    raise exception 'Invoice % is % and has nothing to post.', v_invoice.invoice_number, v_invoice.status;
  end if;

  if v_invoice.total <= 0 then
    return null;
  end if;

  v_settings := finance.settings ();

  select coalesce(c.receivable_account_id, v_settings.receivable_account_id)
  into v_ar
  from finance.customers c
  where c.id = v_invoice.customer_id;

  if v_ar is null then
    return null;
  end if;

  select count(*) into v_uncoded
  from finance.invoice_lines
  where invoice_id = p_invoice_id
    and account_id is null;

  if v_uncoded > 0 then
    raise exception 'Invoice % has % line(s) with no income account.', v_invoice.invoice_number, v_uncoded
      using hint = 'Code every line before issuing the invoice.';
  end if;

  insert into finance.journals (period_id, entry_date, source, memo, reference, currency)
  values (
    v_invoice.period_id,
    v_invoice.issue_date,
    'invoice',
    'Invoice ' || v_invoice.invoice_number,
    v_invoice.invoice_number,
    v_invoice.currency
  )
  returning id into v_journal_id;

  insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
  values (v_journal_id, v_ar, 1, 'Receivable — ' || v_invoice.invoice_number, v_invoice.total, 0);

  insert into finance.journal_lines (journal_id, account_id, cost_center_id, line_number, description, debit, credit)
  select v_journal_id,
    l.account_id,
    (array_agg(l.cost_center_id order by l.line_number))[1],
    1 + row_number() over (order by l.account_id),
    'Income — ' || v_invoice.invoice_number,
    0,
    sum(l.net_amount)
  from finance.invoice_lines l
  where l.invoice_id = p_invoice_id
  group by l.account_id
  having sum(l.net_amount) <> 0;

  insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
  select v_journal_id,
    coalesce(t.account_id, v_ar),
    100 + row_number() over (order by t.id),
    'Tax — ' || coalesce(t.code, 'n/a'),
    0,
    sum(l.tax_amount)
  from finance.invoice_lines l
    left join finance.tax_rates t on t.id = l.tax_rate_id
  where l.invoice_id = p_invoice_id
  group by t.id, t.account_id, t.code
  having sum(l.tax_amount) <> 0;

  update finance.journals set status = 'posted' where id = v_journal_id;

  update finance.invoices set journal_id = v_journal_id where id = p_invoice_id;

  return v_journal_id;
end;
$$;

create or replace function finance.invoices_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_settings finance.finance_settings;
begin
  if tg_op = 'UPDATE'
    and old.status = 'draft'
    and new.status not in ('draft', 'void')
    and new.journal_id is null then
    v_settings := finance.settings ();

    if coalesce(v_settings.auto_post_invoices, false) then
      perform finance.post_invoice (new.id);
    end if;
  end if;

  perform finance.recalc_customer_position (
    array[new.customer_id, case when tg_op = 'UPDATE' then old.customer_id end]
  );

  return new;
end;
$$;

create or replace function finance.invoices_after_delete () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  perform finance.recalc_customer_position (array[old.customer_id]);
  return old;
end;
$$;

create or replace function finance.recalc_customer_position (p_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  update finance.customers c
  set invoiced_total = s.invoiced,
    paid_total = s.collected,
    outstanding_total = s.outstanding,
    overdue_total = s.overdue,
    oldest_due_date = s.oldest,
    updated_at = current_timestamp
  from (select distinct x.id from unnest(p_ids) as x (id) where x.id is not null) t
    cross join lateral (
      select coalesce(sum(i.total) filter (where i.status <> 'void'), 0) as invoiced,
        coalesce(sum(i.paid_total) filter (where i.status <> 'void'), 0) as collected,
        coalesce(sum(i.balance_due) filter (where i.status not in ('void', 'draft')), 0) as outstanding,
        coalesce(sum(i.balance_due) filter (where i.status = 'overdue'), 0) as overdue,
        min(i.due_date) filter (where i.balance_due > 0 and i.status not in ('void', 'draft')) as oldest
      from finance.invoices i
      where i.customer_id = t.id
    ) s
  where c.id = t.id
    and (c.invoiced_total, c.paid_total, c.outstanding_total, c.overdue_total, c.oldest_due_date)
      is distinct from (s.invoiced, s.collected, s.outstanding, s.overdue, s.oldest);
end;
$$;

create trigger trg_invoices_after_change
after insert or update on finance.invoices for each row
execute function finance.invoices_after_change ();

create trigger trg_invoices_after_delete
after delete on finance.invoices for each row
execute function finance.invoices_after_delete ();

create trigger trg_customers_updated_at
before update on finance.customers for each row
execute function finance.set_updated_at ();

----------------------------------------------------------------
-- Purchase ledger: bills mirror invoices, with an approval step in
-- front of them because money leaving needs a second pair of eyes
----------------------------------------------------------------
create or replace function finance.bill_lines_compute () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_rate real;
begin
  if new.line_number is null then
    select coalesce(max(line_number), 0) + 1 into new.line_number
    from finance.bill_lines
    where bill_id = new.bill_id;
  end if;

  new.net_amount := round(coalesce(new.quantity, 0) * coalesce(new.unit_price, 0), 2);

  select rate into v_rate from finance.tax_rates where id = new.tax_rate_id;

  new.tax_amount := round(new.net_amount * coalesce(v_rate, 0)::numeric / 100, 2);
  new.line_total := new.net_amount + new.tax_amount;

  return new;
end;
$$;

create trigger trg_bill_lines_compute
before insert or update on finance.bill_lines for each row
execute function finance.bill_lines_compute ();

create or replace function finance.bill_lines_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_bill_id uuid;
  v_net numeric(16, 2);
  v_tax numeric(16, 2);
  v_status finance.bill_status;
  v_number varchar(30);
begin
  v_bill_id := coalesce(new.bill_id, old.bill_id);

  select coalesce(sum(net_amount), 0), coalesce(sum(tax_amount), 0)
  into v_net, v_tax
  from finance.bill_lines
  where bill_id = v_bill_id;

  update finance.bills
  set subtotal = v_net,
    tax_total = v_tax,
    total = v_net + v_tax
  where id = v_bill_id
    and (subtotal, tax_total) is distinct from (v_net, v_tax);

  return coalesce(new, old);
end;
$$;

create or replace function finance.bill_lines_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_status finance.bill_status;
  v_number varchar(30);
begin
  select status, bill_number into v_status, v_number
  from finance.bills
  where id = coalesce(new.bill_id, old.bill_id);

  if v_status in ('paid', 'void') then
    raise exception 'Bill % is % — its lines cannot be changed.', v_number, v_status;
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_bill_lines_guard
before insert or delete or update of account_id,
cost_center_id,
tax_rate_id,
description,
quantity,
unit_price on finance.bill_lines for each row
execute function finance.bill_lines_guard ();

create trigger trg_bill_lines_rollup
after insert or delete or update on finance.bill_lines for each row
execute function finance.bill_lines_rollup ();

create or replace function finance.bills_derive () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_terms integer;
begin
  if new.due_date is null then
    select payment_terms_days into v_terms from finance.vendors where id = new.vendor_id;

    new.due_date := new.issue_date + coalesce(
      v_terms,
      (finance.settings ()).default_payment_terms_days,
      30
    );
  end if;

  new.period_id := coalesce(new.period_id, finance.period_for_date (new.issue_date));
  new.balance_due := new.total - new.paid_total;

  if tg_op = 'UPDATE' then
    -- Approving a bill is the control. Because this trigger runs as
    -- INVOKER, current_user is the person clicking, not the owner of
    -- the function, so pg_has_role actually means something here.
    if new.status = 'approved' and old.status <> 'approved' then
      if not (
        pg_has_role(current_user, 'accountant', 'member')
        or pg_has_role(current_user, 'x-admin', 'member')
      ) then
        raise exception 'Only finance staff can approve bill %.', new.bill_number;
      end if;

      new.approved_by := coalesce(new.approved_by, auth.uid ());
      new.approved_at := coalesce(new.approved_at, current_timestamp);
    end if;

    if new.status = 'void' and old.paid_total > 0 then
      raise exception 'Bill % has % paid against it and cannot be voided.', new.bill_number, old.paid_total;
    end if;
  end if;

  if new.status not in ('draft', 'awaiting_approval', 'void') then
    if new.total > 0 and new.paid_total >= new.total then
      new.status := 'paid';
      new.paid_at := coalesce(new.paid_at, current_timestamp);
    elsif new.paid_total > 0 then
      new.status := 'partially_paid';
      new.paid_at := null;
    else
      new.status := 'approved';
      new.paid_at := null;
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_bills_derive
before insert or update on finance.bills for each row
execute function finance.bills_derive ();

create trigger trg_bills_updated_at
before update on finance.bills for each row
execute function finance.set_updated_at ();

create or replace function finance.post_bill (p_bill_id uuid) returns uuid language plpgsql security definer
set
  search_path = '' as $$
declare
  v_bill finance.bills;
  v_settings finance.finance_settings;
  v_ap uuid;
  v_journal_id uuid;
begin
  select * into v_bill from finance.bills where id = p_bill_id;

  if v_bill.id is null then
    raise exception 'Bill % does not exist.', p_bill_id;
  end if;

  if v_bill.journal_id is not null then
    return v_bill.journal_id;
  end if;

  if v_bill.status in ('draft', 'awaiting_approval', 'void') then
    raise exception 'Bill % is % — approve it before posting.', v_bill.bill_number, v_bill.status;
  end if;

  if v_bill.total <= 0 then
    return null;
  end if;

  v_settings := finance.settings ();

  select coalesce(v.payable_account_id, v_settings.payable_account_id)
  into v_ap
  from finance.vendors v
  where v.id = v_bill.vendor_id;

  if v_ap is null then
    return null;
  end if;

  insert into finance.journals (period_id, entry_date, source, memo, reference, currency)
  values (
    v_bill.period_id,
    v_bill.issue_date,
    'bill',
    'Bill ' || v_bill.bill_number,
    coalesce(v_bill.vendor_reference, v_bill.bill_number),
    v_bill.currency
  )
  returning id into v_journal_id;

  insert into finance.journal_lines (journal_id, account_id, cost_center_id, line_number, description, debit, credit)
  select v_journal_id,
    coalesce(l.account_id, v_ap),
    (array_agg(l.cost_center_id order by l.line_number))[1],
    row_number() over (order by coalesce(l.account_id, v_ap)),
    'Expense — ' || v_bill.bill_number,
    sum(l.net_amount),
    0
  from finance.bill_lines l
  where l.bill_id = p_bill_id
  group by coalesce(l.account_id, v_ap)
  having sum(l.net_amount) <> 0;

  -- Tax paid on a purchase is an asset to reclaim, not a reduction of
  -- the tax owed on sales. The two only net off at the return, so each
  -- side gets its own account and stays legible until then.
  insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
  select v_journal_id,
    coalesce(t.input_account_id, t.account_id, v_ap),
    100 + row_number() over (order by t.id),
    'Input tax — ' || coalesce(t.code, 'n/a'),
    sum(l.tax_amount),
    0
  from finance.bill_lines l
    left join finance.tax_rates t on t.id = l.tax_rate_id
  where l.bill_id = p_bill_id
  group by t.id, t.input_account_id, t.account_id, t.code
  having sum(l.tax_amount) <> 0;

  insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
  values (v_journal_id, v_ap, 200, 'Payable — ' || v_bill.bill_number, 0, v_bill.total);

  update finance.journals set status = 'posted' where id = v_journal_id;

  update finance.bills set journal_id = v_journal_id where id = p_bill_id;

  return v_journal_id;
end;
$$;

create or replace function finance.recalc_vendor_position (p_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  update finance.vendors v
  set billed_total = s.billed,
    paid_total = s.paid,
    outstanding_total = s.outstanding,
    updated_at = current_timestamp
  from (select distinct x.id from unnest(p_ids) as x (id) where x.id is not null) t
    cross join lateral (
      select coalesce(sum(b.total) filter (where b.status <> 'void'), 0) as billed,
        coalesce(sum(b.paid_total) filter (where b.status <> 'void'), 0) as paid,
        coalesce(sum(b.balance_due) filter (where b.status in ('approved', 'partially_paid')), 0) as outstanding
      from finance.bills b
      where b.vendor_id = t.id
    ) s
  where v.id = t.id
    and (v.billed_total, v.paid_total, v.outstanding_total)
      is distinct from (s.billed, s.paid, s.outstanding);
end;
$$;

create or replace function finance.bills_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if tg_op = 'UPDATE'
    and old.status in ('draft', 'awaiting_approval')
    and new.status not in ('draft', 'awaiting_approval', 'void')
    and new.journal_id is null
    and coalesce((finance.settings ()).auto_post_invoices, false) then
    perform finance.post_bill (new.id);
  end if;

  perform finance.recalc_vendor_position (
    array[new.vendor_id, case when tg_op = 'UPDATE' then old.vendor_id end]
  );

  return new;
end;
$$;

create or replace function finance.bills_after_delete () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  perform finance.recalc_vendor_position (array[old.vendor_id]);
  return old;
end;
$$;

create trigger trg_bills_after_change
after insert or update on finance.bills for each row
execute function finance.bills_after_change ();

create trigger trg_bills_after_delete
after delete on finance.bills for each row
execute function finance.bills_after_delete ();

create trigger trg_vendors_updated_at
before update on finance.vendors for each row
execute function finance.set_updated_at ();

create trigger trg_accounts_updated_at
before update on finance.accounts for each row
execute function finance.set_updated_at ();

create trigger trg_cost_centers_updated_at
before update on finance.cost_centers for each row
execute function finance.set_updated_at ();

create trigger trg_tax_rates_updated_at
before update on finance.tax_rates for each row
execute function finance.set_updated_at ();

----------------------------------------------------------------
-- Cash: payments, allocations, and the bank
----------------------------------------------------------------
create or replace function finance.payments_derive () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  new.period_id := coalesce(new.period_id, finance.period_for_date (new.payment_date));
  new.unallocated_total := new.amount - new.allocated_total;

  if new.bank_account_id is null then
    select bank_account_id into new.bank_account_id from finance.finance_settings limit 1;
  end if;

  if new.allocated_total > new.amount then
    raise exception 'Payment % is allocated (%) beyond its own value (%).',
      new.payment_number, new.allocated_total, new.amount;
  end if;

  return new;
end;
$$;

create trigger trg_payments_derive
before insert or update on finance.payments for each row
execute function finance.payments_derive ();

create trigger trg_payments_updated_at
before update on finance.payments for each row
execute function finance.set_updated_at ();

-- ALLOCATION LIMITS. A receipt cannot be spread further than it is
-- worth, and a document cannot be settled beyond its balance. Both
-- checks run before the row lands, so neither side can drift.
create or replace function finance.allocations_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_payment finance.payments;
  v_other numeric(16, 2);
  v_doc_total numeric(16, 2);
  v_doc_paid numeric(16, 2);
  v_doc_label varchar(30);
begin
  select * into v_payment from finance.payments where id = new.payment_id;

  if v_payment.id is null then
    raise exception 'Allocation refers to a payment that does not exist.';
  end if;

  if v_payment.direction = 'inbound' and new.invoice_id is null then
    raise exception 'Receipt % can only be allocated to an invoice.', v_payment.payment_number;
  end if;

  if v_payment.direction = 'outbound' and new.bill_id is null then
    raise exception 'Payment % can only be allocated to a bill.', v_payment.payment_number;
  end if;

  select coalesce(sum(amount), 0) into v_other
  from finance.payment_allocations
  where payment_id = new.payment_id
    and id is distinct from new.id;

  if v_other + new.amount > v_payment.amount then
    raise exception 'Payment % has only % left to allocate, not %.',
      v_payment.payment_number, v_payment.amount - v_other, new.amount
      using hint = 'Split the allocation, or record a larger payment.';
  end if;

  if new.invoice_id is not null then
    select total, paid_total, invoice_number into v_doc_total, v_doc_paid, v_doc_label
    from finance.invoices
    where id = new.invoice_id;
  else
    select total, paid_total, bill_number into v_doc_total, v_doc_paid, v_doc_label
    from finance.bills
    where id = new.bill_id;
  end if;

  select coalesce(sum(amount), 0) into v_other
  from finance.payment_allocations
  where id is distinct from new.id
    and (
      (new.invoice_id is not null and invoice_id = new.invoice_id)
      or (new.bill_id is not null and bill_id = new.bill_id)
    );

  if v_other + new.amount > v_doc_total then
    raise exception 'Document % is worth % and already has % against it — % would over-settle it.',
      v_doc_label, v_doc_total, v_other, new.amount;
  end if;

  return new;
end;
$$;

create trigger trg_allocations_guard
before insert or update on finance.payment_allocations for each row
execute function finance.allocations_guard ();

create or replace function finance.allocations_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_row finance.payment_allocations;
  v_total numeric(16, 2);
begin
  v_row := coalesce(new, old);

  select coalesce(sum(amount), 0) into v_total
  from finance.payment_allocations
  where payment_id = v_row.payment_id;

  update finance.payments
  set allocated_total = v_total,
    unallocated_total = amount - v_total
  where id = v_row.payment_id
    and allocated_total is distinct from v_total;

  if v_row.invoice_id is not null then
    select coalesce(sum(amount), 0) into v_total
    from finance.payment_allocations
    where invoice_id = v_row.invoice_id;

    update finance.invoices
    set paid_total = v_total
    where id = v_row.invoice_id
      and paid_total is distinct from v_total;
  end if;

  if v_row.bill_id is not null then
    select coalesce(sum(amount), 0) into v_total
    from finance.payment_allocations
    where bill_id = v_row.bill_id;

    update finance.bills
    set paid_total = v_total
    where id = v_row.bill_id
      and paid_total is distinct from v_total;
  end if;

  -- The old row's payment too, in case an allocation was moved.
  if tg_op = 'UPDATE' and new.payment_id is distinct from old.payment_id then
    select coalesce(sum(amount), 0) into v_total
    from finance.payment_allocations
    where payment_id = old.payment_id;

    update finance.payments
    set allocated_total = v_total,
      unallocated_total = amount - v_total
    where id = old.payment_id;
  end if;

  return v_row;
end;
$$;

create trigger trg_allocations_rollup
after insert or delete or update on finance.payment_allocations for each row
execute function finance.allocations_rollup ();

-- A receipt debits the bank and credits the receivable control account;
-- a payment out does the reverse against payables.
create or replace function finance.post_payment (p_payment_id uuid) returns uuid language plpgsql security definer
set
  search_path = '' as $$
declare
  v_payment finance.payments;
  v_settings finance.finance_settings;
  v_bank uuid;
  v_control uuid;
  v_journal_id uuid;
begin
  select * into v_payment from finance.payments where id = p_payment_id;

  if v_payment.id is null then
    raise exception 'Payment % does not exist.', p_payment_id;
  end if;

  if v_payment.journal_id is not null then
    return v_payment.journal_id;
  end if;

  v_settings := finance.settings ();

  select coalesce(b.gl_account_id, v_settings.bank_account_id)
  into v_bank
  from finance.bank_accounts b
  where b.id = v_payment.bank_account_id;

  if v_payment.direction = 'inbound' then
    select coalesce(c.receivable_account_id, v_settings.receivable_account_id)
    into v_control
    from finance.customers c
    where c.id = v_payment.customer_id;
  else
    select coalesce(v.payable_account_id, v_settings.payable_account_id)
    into v_control
    from finance.vendors v
    where v.id = v_payment.vendor_id;
  end if;

  if v_bank is null or v_control is null then
    return null;
  end if;

  insert into finance.journals (period_id, entry_date, source, memo, reference, currency)
  values (
    v_payment.period_id,
    v_payment.payment_date,
    (
      case when v_payment.direction = 'inbound' then 'receipt' else 'payment' end
    )::finance.journal_source,
    case when v_payment.direction = 'inbound' then 'Receipt ' else 'Payment ' end || v_payment.payment_number,
    coalesce(v_payment.reference, v_payment.payment_number),
    v_payment.currency
  )
  returning id into v_journal_id;

  if v_payment.direction = 'inbound' then
    insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
    values
      (v_journal_id, v_bank, 1, 'Bank — ' || v_payment.payment_number, v_payment.amount, 0),
      (v_journal_id, v_control, 2, 'Receivable cleared — ' || v_payment.payment_number, 0, v_payment.amount);
  else
    insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
    values
      (v_journal_id, v_control, 1, 'Payable cleared — ' || v_payment.payment_number, v_payment.amount, 0),
      (v_journal_id, v_bank, 2, 'Bank — ' || v_payment.payment_number, 0, v_payment.amount);
  end if;

  update finance.journals set status = 'posted' where id = v_journal_id;

  update finance.payments set journal_id = v_journal_id where id = p_payment_id;

  return v_journal_id;
end;
$$;

create or replace function finance.payments_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT'
    and new.journal_id is null
    and coalesce((finance.settings ()).auto_post_invoices, false) then
    perform finance.post_payment (new.id);
  end if;

  perform finance.recalc_customer_position (array[new.customer_id]);
  perform finance.recalc_vendor_position (array[new.vendor_id]);
  perform finance.recalc_bank_position (array[new.bank_account_id]);

  return new;
end;
$$;

create trigger trg_payments_after_change
after insert or update on finance.payments for each row
execute function finance.payments_after_change ();

-- Two balances that are meant to disagree. The STATEMENT side is what
-- the bank says happened; the LEDGER side is the balance of the
-- general ledger account behind it. Reconciliation is the work of
-- closing the gap, so deriving both from one source would make the
-- whole board pointless.
create or replace function finance.recalc_bank_position (p_ids uuid[]) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then
    return;
  end if;

  update finance.bank_accounts b
  set statement_balance = b.opening_balance + s.statement_movement,
    ledger_balance = b.opening_balance + s.ledger_movement,
    unreconciled_count = s.unreconciled,
    updated_at = current_timestamp
  from (select distinct x.id from unnest(p_ids) as x (id) where x.id is not null) t
    cross join lateral (
      select coalesce(
          (
            select sum(tx.amount)
            from finance.bank_transactions tx
            where tx.bank_account_id = t.id
              and tx.status <> 'ignored'
          ),
          0
        ) as statement_movement,
        coalesce(
          (
            select sum(l.debit - l.credit)
            from finance.journal_lines l
              join finance.journals j on j.id = l.journal_id
              join finance.bank_accounts b2 on b2.id = t.id
            where j.status <> 'draft'
              and l.account_id = b2.gl_account_id
          ),
          0
        ) as ledger_movement,
        coalesce(
          (
            select count(*)
            from finance.bank_transactions tx
            where tx.bank_account_id = t.id
              and tx.status = 'unreconciled'
          ),
          0
        )::integer as unreconciled
    ) s
  where b.id = t.id
    and (b.statement_balance, b.ledger_balance, b.unreconciled_count)
      is distinct from (
        b.opening_balance + s.statement_movement,
        b.opening_balance + s.ledger_movement,
        s.unreconciled
      );
end;
$$;

create or replace function finance.bank_transactions_derive () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  new.value_date := coalesce(new.value_date, new.transaction_date);

  if new.matched_payment_id is not null and new.status = 'unreconciled' then
    new.status := 'matched';
  end if;

  if new.status = 'reconciled' then
    new.reconciled_on := coalesce(new.reconciled_on, current_date);
  else
    new.reconciled_on := null;
  end if;

  return new;
end;
$$;

create trigger trg_bank_tx_derive
before insert or update on finance.bank_transactions for each row
execute function finance.bank_transactions_derive ();

create trigger trg_bank_tx_updated_at
before update on finance.bank_transactions for each row
execute function finance.set_updated_at ();

create or replace function finance.bank_transactions_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  perform finance.recalc_bank_position (
    array[
      (coalesce(new, old)).bank_account_id,
      case when tg_op = 'UPDATE' then old.bank_account_id end
    ]
  );

  return coalesce(new, old);
end;
$$;

create trigger trg_bank_tx_rollup
after insert or delete or update on finance.bank_transactions for each row
execute function finance.bank_transactions_rollup ();

create trigger trg_bank_accounts_updated_at
before update on finance.bank_accounts for each row
execute function finance.set_updated_at ();

----------------------------------------------------------------
-- Expense claims
----------------------------------------------------------------
create or replace function finance.expense_lines_compute () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_rate real;
  v_threshold numeric(10, 2);
begin
  if new.tax_rate_id is not null and coalesce(new.tax_amount, 0) = 0 then
    select rate into v_rate from finance.tax_rates where id = new.tax_rate_id;
    new.tax_amount := round(coalesce(new.net_amount, 0) * coalesce(v_rate, 0)::numeric / 100, 2);
  end if;

  new.gross_amount := coalesce(new.net_amount, 0) + coalesce(new.tax_amount, 0);
  new.has_receipt := new.receipt is not null;

  v_threshold := coalesce((finance.settings ()).require_receipt_over, 25);

  if new.is_reimbursable and new.gross_amount > v_threshold and not new.has_receipt then
    raise exception 'A receipt is required for anything over %; "%" is %.',
      v_threshold, new.description, new.gross_amount;
  end if;

  return new;
end;
$$;

create trigger trg_expense_lines_compute
before insert or update on finance.expense_lines for each row
execute function finance.expense_lines_compute ();

create or replace function finance.expense_lines_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_claim_id uuid;
  v_total numeric(16, 2);
  v_reimbursable numeric(16, 2);
  v_count integer;
  v_status finance.expense_status;
  v_number varchar(30);
begin
  v_claim_id := coalesce(new.claim_id, old.claim_id);

  select coalesce(sum(gross_amount), 0),
    coalesce(sum(gross_amount) filter (where is_reimbursable), 0),
    count(*)
  into v_total, v_reimbursable, v_count
  from finance.expense_lines
  where claim_id = v_claim_id;

  update finance.expense_claims
  set total_amount = v_total,
    reimbursable_amount = v_reimbursable,
    line_count = v_count
  where id = v_claim_id
    and (total_amount, reimbursable_amount, line_count)
      is distinct from (v_total, v_reimbursable, v_count);

  return coalesce(new, old);
end;
$$;

-- A decided claim is fixed. The check lives in its own BEFORE trigger,
-- scoped to the columns that actually change what was claimed, so
-- housekeeping on a row (backfilling a timestamp, attaching a missing
-- receipt reference) is not mistaken for altering the claim itself.
-- Putting it in the rollup instead would make an AFTER trigger — whose
-- job is arithmetic — the enforcer of a business rule.
create or replace function finance.expense_lines_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_status finance.expense_status;
  v_number varchar(30);
begin
  select status, claim_number into v_status, v_number
  from finance.expense_claims
  where id = coalesce(new.claim_id, old.claim_id);

  if v_status in ('approved', 'reimbursed') then
    raise exception 'Claim % is % — its lines are fixed.', v_number, v_status
      using hint = 'Raise a new claim for anything that was missed.';
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_expense_lines_guard
before insert or delete or update of account_id,
tax_rate_id,
category,
spent_on,
merchant,
description,
net_amount,
tax_amount,
is_reimbursable,
receipt on finance.expense_lines for each row
execute function finance.expense_lines_guard ();

create trigger trg_expense_lines_rollup
after insert or delete or update on finance.expense_lines for each row
execute function finance.expense_lines_rollup ();

create or replace function finance.expense_claims_guard () returns trigger language plpgsql security invoker
set
  search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.claimant_id := coalesce(new.claimant_id, auth.uid ());
    new.period_id := coalesce(new.period_id, finance.period_for_date (current_date));

    if new.status <> 'draft' then
      raise exception 'A claim starts as a draft.';
    end if;

    return new;
  end if;

  if new.status is distinct from old.status then
    -- Nobody approves their own spending, and only finance can approve
    -- anybody's. INVOKER, again, so current_user is the person.
    if new.status in ('approved', 'rejected') then
      if not (
        pg_has_role(current_user, 'accountant', 'member')
        or pg_has_role(current_user, 'x-admin', 'member')
      ) then
        raise exception 'Only finance staff can decide claim %.', new.claim_number;
      end if;

      if old.status <> 'submitted' then
        raise exception 'Claim % is % — only a submitted claim can be decided.', new.claim_number, old.status;
      end if;

      new.approved_by := coalesce(new.approved_by, auth.uid ());
      new.approved_at := coalesce(new.approved_at, current_timestamp);
    end if;

    if new.status = 'submitted' then
      if coalesce(old.line_count, 0) = 0 then
        raise exception 'Claim % has no lines to submit.', new.claim_number;
      end if;

      new.submitted_at := coalesce(new.submitted_at, current_timestamp);
    end if;

    if new.status = 'rejected' and coalesce(new.rejected_reason, '') = '' then
      raise exception 'Rejecting claim % needs a reason the claimant can act on.', new.claim_number;
    end if;

    if new.status = 'reimbursed' then
      if old.status <> 'approved' then
        raise exception 'Claim % must be approved before it is reimbursed.', new.claim_number;
      end if;

      new.reimbursed_on := coalesce(new.reimbursed_on, current_date);

      new.time_to_reimburse := case
        when new.submitted_at is null then null
        else greatest(
          extract(
            epoch
            from
              (new.reimbursed_on::timestamptz - new.submitted_at)
          )::bigint,
          0
        )
      end;
    end if;

    if old.status = 'reimbursed' then
      raise exception 'Claim % has been paid and is closed.', old.claim_number;
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_expense_claims_guard
before insert or update on finance.expense_claims for each row
execute function finance.expense_claims_guard ();

create trigger trg_expense_claims_updated_at
before update on finance.expense_claims for each row
execute function finance.set_updated_at ();

create or replace function finance.post_expense_claim (p_claim_id uuid) returns uuid language plpgsql security definer
set
  search_path = '' as $$
declare
  v_claim finance.expense_claims;
  v_settings finance.finance_settings;
  v_clearing uuid;
  v_journal_id uuid;
begin
  select * into v_claim from finance.expense_claims where id = p_claim_id;

  if v_claim.id is null then
    raise exception 'Claim % does not exist.', p_claim_id;
  end if;

  if v_claim.journal_id is not null then
    return v_claim.journal_id;
  end if;

  if v_claim.status not in ('approved', 'reimbursed') then
    raise exception 'Claim % is % and cannot be posted.', v_claim.claim_number, v_claim.status;
  end if;

  v_settings := finance.settings ();
  v_clearing := coalesce(v_settings.expense_clearing_account_id, v_settings.payable_account_id);

  if v_clearing is null or v_claim.total_amount <= 0 then
    return null;
  end if;

  insert into finance.journals (entry_date, source, memo, reference, currency)
  values (
    coalesce(v_claim.reimbursed_on, current_date),
    'expense',
    'Expense claim ' || v_claim.claim_number,
    v_claim.claim_number,
    v_claim.currency
  )
  returning id into v_journal_id;

  insert into finance.journal_lines (journal_id, account_id, cost_center_id, line_number, description, debit, credit)
  select v_journal_id,
    coalesce(l.account_id, v_clearing),
    v_claim.cost_center_id,
    row_number() over (order by coalesce(l.account_id, v_clearing)),
    'Expenses — ' || v_claim.claim_number,
    sum(l.gross_amount),
    0
  from finance.expense_lines l
  where l.claim_id = p_claim_id
  group by coalesce(l.account_id, v_clearing)
  having sum(l.gross_amount) <> 0;

  insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
  values (v_journal_id, v_clearing, 100, 'Owed to claimant — ' || v_claim.claim_number, 0, v_claim.total_amount);

  update finance.journals set status = 'posted' where id = v_journal_id;

  update finance.expense_claims set journal_id = v_journal_id where id = p_claim_id;

  return v_journal_id;
end;
$$;

create or replace function finance.expense_claims_after_change () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = 'reimbursed'
    and old.status is distinct from 'reimbursed'
    and new.journal_id is null then
    perform finance.post_expense_claim (new.id);
  end if;

  return new;
end;
$$;

create trigger trg_expense_claims_after_change
after update on finance.expense_claims for each row
execute function finance.expense_claims_after_change ();

----------------------------------------------------------------
-- Budgets and depreciation
----------------------------------------------------------------
create or replace function finance.recalc_budget_actuals (p_account_ids uuid[] default null) returns void language plpgsql security definer
set
  search_path = '' as $$
begin
  update finance.budgets b
  set actual_amount = s.actual,
    variance_amount = b.budget_amount - s.actual,
    variance_percent = case
      when b.budget_amount = 0 then null
      else round(((b.budget_amount - s.actual) / b.budget_amount) * 100, 2)::real
    end,
    updated_at = current_timestamp
  from (
      select id
      from finance.budgets
      where p_account_ids is null
        or account_id = any (p_account_ids)
    ) t
    cross join lateral (
      select coalesce(sum(l.debit - l.credit), 0) as actual
      from finance.budgets bb
        join finance.journal_lines l on l.account_id in (select finance.account_subtree (bb.account_id))
        join finance.journals j on j.id = l.journal_id and j.status <> 'draft'
        join finance.fiscal_periods p on p.id = j.period_id
      where bb.id = t.id
        and p.fiscal_year = bb.fiscal_year
        and (bb.period_id is null or j.period_id = bb.period_id)
        and (bb.cost_center_id is null or l.cost_center_id = bb.cost_center_id)
    ) s
  where b.id = t.id
    -- Comparing the variance too, not just the actual. A budget with no
    -- spend against it has an unchanged actual of zero, so guarding on
    -- the actual alone skipped the row and left variance_amount at its
    -- default of zero — which the report renders as "on plan" when what
    -- it means is "entirely unspent".
    and (b.actual_amount, b.variance_amount)
      is distinct from (s.actual, b.budget_amount - s.actual);
end;
$$;

create or replace function finance.journals_budget_sync () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_accounts uuid[];
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  select array_agg(distinct l.account_id) into v_accounts
  from finance.journal_lines l
  where l.journal_id = new.id
    and l.account_id is not null;

  perform finance.recalc_budget_actuals (v_accounts);

  return new;
end;
$$;

create trigger trg_journals_budget_sync
after update on finance.journals for each row
execute function finance.journals_budget_sync ();

create or replace function finance.journals_bank_sync () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_banks uuid[];
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  select array_agg(distinct b.id) into v_banks
  from finance.journal_lines l
    join finance.bank_accounts b on b.gl_account_id = l.account_id
  where l.journal_id = new.id;

  perform finance.recalc_bank_position (v_banks);

  return new;
end;
$$;

create trigger trg_journals_bank_sync
after update on finance.journals for each row
execute function finance.journals_bank_sync ();

create trigger trg_budgets_updated_at
before update on finance.budgets for each row
execute function finance.set_updated_at ();

create or replace function finance.assets_derive () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  new.in_service_date := coalesce(new.in_service_date, new.purchase_date);

  new.monthly_depreciation := case
    when new.depreciation_method = 'none' then 0
    when new.depreciation_method = 'reducing_balance' then round(
      greatest(new.purchase_cost - new.accumulated_depreciation - new.residual_value, 0)
        * (2.0 / new.useful_life_months),
      2
    )
    else round((new.purchase_cost - new.residual_value) / new.useful_life_months, 2)
  end;

  new.net_book_value := new.purchase_cost - new.accumulated_depreciation;

  if new.status in ('disposed', 'written_off') then
    new.monthly_depreciation := 0;
  end if;

  if new.status = 'disposed' and new.disposal_date is null then
    raise exception 'Disposing of % needs a disposal date.', new.asset_code;
  end if;

  return new;
end;
$$;

create trigger trg_assets_derive
before insert or update on finance.fixed_assets for each row
execute function finance.assets_derive ();

create trigger trg_assets_updated_at
before update on finance.fixed_assets for each row
execute function finance.set_updated_at ();

create trigger trg_settings_updated_at
before update on finance.finance_settings for each row
execute function finance.set_updated_at ();

----------------------------------------------------------------
-- Row actions
----------------------------------------------------------------
create or replace function finance.post_journal (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update finance.journals set status = 'posted' where id = p_id;
end;
$$;

comment on function finance.post_journal (uuid) is '{
    "type": "action",
    "resource": "journals",
    "name": "Post",
    "description": "Commit this entry to the ledger. It cannot be edited afterwards.",
    "confirm": {"title": "Post this journal?", "description": "Posting writes the entry to the ledger. It cannot be edited or deleted afterwards — the only way back is a reversing entry."},
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Journal posted"
}';

revoke all on function finance.post_journal (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.post_journal (uuid) to "x-admin",
"accountant";

-- Reversing does not delete anything. It books the mirror image of the
-- original into today''s period, posts it, and marks the original as
-- reversed. Both entries stay in the ledger and cancel out — which is
-- the whole point.
create or replace function finance.reverse_journal (p_id uuid, p_reason varchar default null) returns uuid language plpgsql security definer
set
  search_path = '' as $$
declare
  v_source finance.journals;
  v_period uuid;
  v_new uuid;
begin
  select * into v_source from finance.journals where id = p_id;

  if v_source.id is null then
    raise exception 'Journal % does not exist.', p_id;
  end if;

  if v_source.status <> 'posted' then
    raise exception 'Journal % is % — only a posted entry can be reversed.',
      v_source.journal_number, v_source.status;
  end if;

  v_period := finance.period_for_date (current_date);
  perform finance.assert_period_open (v_period, 'Reversing a journal');

  insert into finance.journals (
    period_id, entry_date, source, memo, reference, currency, reverses_journal_id
  )
  values (
    v_period,
    current_date,
    v_source.source,
    'Reversal of ' || v_source.journal_number || coalesce(' — ' || p_reason, ''),
    v_source.reference,
    v_source.currency,
    v_source.id
  )
  returning id into v_new;

  insert into finance.journal_lines (
    journal_id, account_id, cost_center_id, line_number, description, debit, credit, tax_rate_id
  )
  select v_new,
    l.account_id,
    l.cost_center_id,
    l.line_number,
    'Reversal — ' || coalesce(l.description, v_source.journal_number),
    l.credit,
    l.debit,
    l.tax_rate_id
  from finance.journal_lines l
  where l.journal_id = p_id;

  update finance.journals set status = 'posted' where id = v_new;

  perform set_config('finance.allow_posted_write', 'on', true);

  update finance.journals
  set status = 'reversed',
    reversed_by_journal_id = v_new
  where id = p_id;

  perform set_config('finance.allow_posted_write', 'off', true);

  return v_new;
end;
$$;

comment on function finance.reverse_journal (uuid, varchar) is '{
    "type": "action",
    "resource": "journals",
    "name": "Reverse",
    "description": "Book the mirror image of this entry into the current period.",
    "confirm": {"title": "Reverse this journal?", "description": "This books an equal and opposite entry into the current period. Both entries stay in the ledger."},
    "icon": "Undo2",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "eq", "value": "posted"}],
    "success_message": "Reversing entry posted"
}';

revoke all on function finance.reverse_journal (uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.reverse_journal (uuid, varchar) to "x-admin",
"accountant";

create or replace function finance.issue_invoice (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update finance.invoices set status = 'sent' where id = p_id;
end;
$$;

comment on function finance.issue_invoice (uuid) is '{
    "type": "action",
    "resource": "invoices",
    "name": "Issue",
    "description": "Send the invoice and raise the receivable.",
    "confirm": {"title": "Issue this invoice?", "description": "Issuing posts the invoice to the ledger and raises the receivable. Its lines cannot be changed afterwards."},
    "icon": "Send",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Invoice issued"
}';

revoke all on function finance.issue_invoice (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.issue_invoice (uuid) to "x-admin",
"accountant";

create or replace function finance.void_invoice (p_id uuid, p_reason varchar) returns void language plpgsql security definer
set
  search_path = '' as $$
declare
  v_journal uuid;
begin
  select journal_id into v_journal from finance.invoices where id = p_id;

  if v_journal is not null then
    perform finance.reverse_journal (v_journal, 'Invoice voided: ' || p_reason);
  end if;

  update finance.invoices
  set status = 'void',
    voided_reason = p_reason
  where id = p_id;
end;
$$;

comment on function finance.void_invoice (uuid, varchar) is '{
    "type": "action",
    "resource": "invoices",
    "name": "Void",
    "description": "Cancel the invoice and reverse whatever it posted.",
    "confirm": {"title": "Void this invoice?", "description": "The invoice is cancelled and anything it posted is reversed. This cannot be undone."},
    "icon": "Ban",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "sent", "overdue"]}],
    "success_message": "Invoice voided"
}';

revoke all on function finance.void_invoice (uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.void_invoice (uuid, varchar) to "x-admin",
"accountant";

create or replace function finance.approve_bill (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update finance.bills set status = 'approved' where id = p_id;
end;
$$;

comment on function finance.approve_bill (uuid) is '{
    "type": "action",
    "resource": "bills",
    "name": "Approve",
    "description": "Approve the bill for payment and post it to the ledger.",
    "confirm": {"title": "Approve this bill?", "description": "Approving posts the bill to the ledger and commits the payable."},
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "awaiting_approval"]}],
    "success_message": "Bill approved"
}';

revoke all on function finance.approve_bill (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.approve_bill (uuid) to "x-admin",
"accountant";

create or replace function finance.submit_claim (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update finance.expense_claims set status = 'submitted' where id = p_id;
end;
$$;

comment on function finance.submit_claim (uuid) is '{
    "type": "action",
    "resource": "expense_claims",
    "name": "Submit",
    "description": "Send this claim to finance.",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Claim submitted"
}';

revoke all on function finance.submit_claim (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.submit_claim (uuid) to "x-admin",
"accountant",
"user";

create or replace function finance.approve_claim (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update finance.expense_claims set status = 'approved' where id = p_id;
end;
$$;

comment on function finance.approve_claim (uuid) is '{
    "type": "action",
    "resource": "expense_claims",
    "name": "Approve",
    "description": "Approve the claim for reimbursement.",
    "icon": "ThumbsUp",
    "visible": [{"id": "status", "operator": "eq", "value": "submitted"}],
    "success_message": "Claim approved"
}';

revoke all on function finance.approve_claim (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.approve_claim (uuid) to "x-admin",
"accountant";

create or replace function finance.reject_claim (p_id uuid, p_reason varchar) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update finance.expense_claims
  set status = 'rejected',
    rejected_reason = p_reason
  where id = p_id;
end;
$$;

comment on function finance.reject_claim (uuid, varchar) is '{
    "type": "action",
    "resource": "expense_claims",
    "name": "Reject",
    "description": "Send the claim back with a reason.",
    "confirm": {"title": "Reject this claim?", "description": "The claimant is notified and will have to raise a new claim."},
    "icon": "ThumbsDown",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "eq", "value": "submitted"}],
    "success_message": "Claim rejected"
}';

revoke all on function finance.reject_claim (uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.reject_claim (uuid, varchar) to "x-admin",
"accountant";

create or replace function finance.reimburse_claim (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update finance.expense_claims set status = 'reimbursed' where id = p_id;
end;
$$;

comment on function finance.reimburse_claim (uuid) is '{
    "type": "action",
    "resource": "expense_claims",
    "name": "Mark reimbursed",
    "description": "Record the payment and post the claim to the ledger.",
    "confirm": {"title": "Mark this claim reimbursed?", "description": "This posts the claim to the ledger and closes it. A reimbursed claim cannot be reopened."},
    "icon": "BadgeDollarSign",
    "visible": [{"id": "status", "operator": "eq", "value": "approved"}],
    "success_message": "Claim reimbursed"
}';

revoke all on function finance.reimburse_claim (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.reimburse_claim (uuid) to "x-admin",
"accountant";

create or replace function finance.close_period (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update finance.fiscal_periods set status = 'closed' where id = p_id;
end;
$$;

comment on function finance.close_period (uuid) is '{
    "type": "action",
    "resource": "fiscal_periods",
    "name": "Close",
    "description": "Close the period. Fails if any draft journal is still sitting in it.",
    "confirm": {"title": "Close this period?", "description": "Nothing further can be posted into it until somebody reopens it."},
    "icon": "Lock",
    "visible": [{"id": "status", "operator": "eq", "value": "open"}],
    "success_message": "Period closed"
}';

revoke all on function finance.close_period (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.close_period (uuid) to "x-admin",
"accountant";

create or replace function finance.reopen_period (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update finance.fiscal_periods set status = 'open' where id = p_id;
end;
$$;

comment on function finance.reopen_period (uuid) is '{
    "type": "action",
    "resource": "fiscal_periods",
    "name": "Reopen",
    "description": "Reopen a closed period so late entries can be posted.",
    "confirm": {"title": "Reopen this period?", "description": "Reopening a closed period lets entries be posted into a month that has already been reported on."},
    "icon": "LockOpen",
    "variant": "secondary",
    "visible": [{"id": "status", "operator": "in", "value": ["closed", "locked"]}],
    "success_message": "Period reopened"
}';

revoke all on function finance.reopen_period (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.reopen_period (uuid) to "x-admin";

create or replace function finance.set_transaction_status (
  p_id uuid,
  p_status finance.bank_transaction_status
) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update finance.bank_transactions set status = p_status where id = p_id;
end;
$$;

comment on function finance.set_transaction_status (uuid, finance.bank_transaction_status) is '{
    "type": "action",
    "resource": "bank_transactions",
    "name": "Set status",
    "icon": "ArrowRightLeft",
    "action_type": "picker"
}';

revoke all on function finance.set_transaction_status (uuid, finance.bank_transaction_status)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.set_transaction_status (uuid, finance.bank_transaction_status) to "x-admin",
"accountant";

----------------------------------------------------------------
-- Forms
----------------------------------------------------------------
-- Take money in and apply it to the oldest open invoices first, which
-- is what almost every receipt actually means. Returns the payment so
-- the UI can drop straight onto its detail page.
create or replace function finance.record_receipt (
  p_customer_id uuid,
  p_amount numeric,
  p_payment_date date default current_date,
  p_bank_account_id uuid default null,
  p_method finance.payment_method default 'bank_transfer',
  p_reference varchar default null
) returns setof finance.payments language plpgsql security definer
set
  search_path = '' as $$
declare
  v_payment_id uuid;
  v_left numeric(16, 2);
  v_take numeric(16, 2);
  v_invoice record;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'A receipt needs a positive amount.';
  end if;

  insert into finance.payments (
    direction, customer_id, bank_account_id, amount, payment_date, method, reference
  )
  values (
    'inbound',
    p_customer_id,
    coalesce(p_bank_account_id, (finance.settings ()).bank_account_id),
    p_amount,
    p_payment_date,
    p_method,
    p_reference
  )
  returning id into v_payment_id;

  v_left := p_amount;

  for v_invoice in
    select id, balance_due
    from finance.invoices
    where customer_id = p_customer_id
      and status in ('sent', 'partially_paid', 'overdue')
      and balance_due > 0
    order by due_date, issue_date
  loop
    exit when v_left <= 0;

    v_take := least(v_left, v_invoice.balance_due);

    insert into finance.payment_allocations (payment_id, invoice_id, amount, allocated_on)
    values (v_payment_id, v_invoice.id, v_take, p_payment_date);

    v_left := v_left - v_take;
  end loop;

  return query
  select * from finance.payments where id = v_payment_id;
end;
$$;

comment on function finance.record_receipt (
  uuid,
  numeric,
  date,
  uuid,
  finance.payment_method,
  varchar
) is '{
    "type": "form",
    "resource": "customers",
    "name": "Record a receipt",
    "description": "Bank the money and apply it to the oldest open invoices first. Anything left over stays unallocated.",
    "icon": "ArrowDownToLine",
    "success_message": "Receipt recorded",
    "fields": {
        "sections": [
            {"id": "who", "title": "Who paid", "fields": ["p_customer_id", "p_amount"]},
            {"id": "how", "title": "How", "fields": ["p_payment_date", "p_bank_account_id", "p_method", "p_reference"]}
        ],
        "relations": {
            "p_customer_id": {"table": "customers", "column": "id", "display": ["name", "code"]},
            "p_bank_account_id": {"table": "bank_accounts", "column": "id", "display": ["name", "code"]}
        }
    }
}';

revoke all on function finance.record_receipt (
  uuid,
  numeric,
  date,
  uuid,
  finance.payment_method,
  varchar
)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.record_receipt (
  uuid,
  numeric,
  date,
  uuid,
  finance.payment_method,
  varchar
) to "x-admin",
"accountant";

-- The two-line entry that makes up most of a bookkeeper''s day.
create or replace function finance.quick_entry (
  p_entry_date date,
  p_debit_account_id uuid,
  p_credit_account_id uuid,
  p_amount numeric,
  p_memo varchar,
  p_cost_center_id uuid default null,
  p_post boolean default true
) returns uuid language plpgsql security definer
set
  search_path = '' as $$
declare
  v_journal_id uuid;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'An entry needs a positive amount.';
  end if;

  if p_debit_account_id = p_credit_account_id then
    raise exception 'The debit and the credit have to land on different accounts.';
  end if;

  insert into finance.journals (entry_date, source, memo)
  values (p_entry_date, 'manual', p_memo)
  returning id into v_journal_id;

  insert into finance.journal_lines (journal_id, account_id, cost_center_id, line_number, description, debit, credit)
  values
    (v_journal_id, p_debit_account_id, p_cost_center_id, 1, p_memo, round(p_amount, 2), 0),
    (v_journal_id, p_credit_account_id, p_cost_center_id, 2, p_memo, 0, round(p_amount, 2));

  if p_post then
    update finance.journals set status = 'posted' where id = v_journal_id;
  end if;

  return v_journal_id;
end;
$$;

comment on function finance.quick_entry (date, uuid, uuid, numeric, varchar, uuid, boolean) is '{
    "type": "form",
    "resource": "journals",
    "name": "Quick entry",
    "description": "One debit, one credit, balanced by construction. Leave it as a draft if somebody else has to review it.",
    "icon": "Zap",
    "success_message": "Entry created",
    "fields": {
        "sections": [
            {"id": "entry", "title": "Entry", "fields": ["p_entry_date", "p_memo", "p_amount"]},
            {"id": "coding", "title": "Coding", "fields": ["p_debit_account_id", "p_credit_account_id", "p_cost_center_id"]},
            {"id": "options", "title": "Options", "fields": ["p_post"]}
        ],
        "relations": {
            "p_debit_account_id": {"table": "accounts", "column": "id", "display": ["code", "name"]},
            "p_credit_account_id": {"table": "accounts", "column": "id", "display": ["code", "name"]},
            "p_cost_center_id": {"table": "cost_centers", "column": "id", "display": ["code", "name"]}
        }
    }
}';

revoke all on function finance.quick_entry (date, uuid, uuid, numeric, varchar, uuid, boolean)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.quick_entry (date, uuid, uuid, numeric, varchar, uuid, boolean) to "x-admin",
"accountant";

create or replace function finance.open_fiscal_year (p_year integer, p_open_first boolean default true) returns setof finance.fiscal_periods language plpgsql security definer
set
  search_path = '' as $$
declare
  v_month integer;
  v_start date;
begin
  if exists (select 1 from finance.fiscal_periods where fiscal_year = p_year) then
    raise exception 'Fiscal year % already has periods.', p_year;
  end if;

  for v_month in 1..12 loop
    v_start := make_date(p_year, v_month, 1);

    insert into finance.fiscal_periods (
      code, name, fiscal_year, period_number, starts_on, ends_on, status
    )
    values (
      p_year || '-' || lpad(v_month::text, 2, '0'),
      to_char(v_start, 'FMMonth YYYY'),
      p_year,
      v_month,
      v_start,
      (v_start + interval '1 month - 1 day')::date,
      (
        case
          when p_open_first and v_month = 1 then 'open'
          else 'future'
        end
      )::finance.period_status
    );
  end loop;

  return query
  select * from finance.fiscal_periods where fiscal_year = p_year order by period_number;
end;
$$;

comment on function finance.open_fiscal_year (integer, boolean) is '{
    "type": "form",
    "resource": "fiscal_periods",
    "name": "Open a fiscal year",
    "description": "Create all twelve periods for a year in one go.",
    "icon": "CalendarPlus",
    "success_message": "Fiscal year created",
    "fields": {
        "sections": [
            {"id": "year", "title": "Year", "fields": ["p_year", "p_open_first"]}
        ]
    }
}';

revoke all on function finance.open_fiscal_year (integer, boolean)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.open_fiscal_year (integer, boolean) to "x-admin";

-- Depreciation is the one journal nobody wants to type. Walk the
-- register, take a month off every asset that still has book value, and
-- book the whole thing as a single entry.
create or replace function finance.run_depreciation (
  p_period_id uuid,
  p_post boolean default true,
  out journal_number varchar,
  out asset_count integer,
  out total_depreciation numeric
) language plpgsql security definer
set
  search_path = '' as $$
declare
  v_period finance.fiscal_periods;
  v_journal_id uuid;
  v_settings finance.finance_settings;
  v_asset record;
  v_charge numeric(16, 2);
  v_line integer := 0;
begin
  select * into v_period from finance.fiscal_periods where id = p_period_id;

  if v_period.id is null then
    raise exception 'Period % does not exist.', p_period_id;
  end if;

  perform finance.assert_period_open (p_period_id, 'Running depreciation');

  v_settings := finance.settings ();
  asset_count := 0;
  total_depreciation := 0;

  insert into finance.journals (period_id, entry_date, source, memo)
  values (p_period_id, v_period.ends_on, 'depreciation', 'Depreciation for ' || v_period.code)
  returning id into v_journal_id;

  for v_asset in
    select *
    from finance.fixed_assets
    where status = 'in_service'
      and depreciation_method <> 'none'
      and net_book_value > residual_value
      and in_service_date <= v_period.ends_on
      and (last_depreciated_on is null or last_depreciated_on < v_period.starts_on)
    order by asset_code
  loop
    v_charge := least(
      v_asset.monthly_depreciation,
      v_asset.net_book_value - v_asset.residual_value
    );

    continue when v_charge <= 0;

    v_line := v_line + 1;

    insert into finance.journal_lines (journal_id, account_id, cost_center_id, line_number, description, debit, credit)
    values (
      v_journal_id,
      coalesce(v_asset.depreciation_account_id, v_settings.expense_clearing_account_id),
      v_asset.cost_center_id,
      v_line,
      'Depreciation — ' || v_asset.name,
      v_charge,
      0
    );

    v_line := v_line + 1;

    insert into finance.journal_lines (journal_id, account_id, cost_center_id, line_number, description, debit, credit)
    values (
      v_journal_id,
      coalesce(v_asset.asset_account_id, v_settings.expense_clearing_account_id),
      v_asset.cost_center_id,
      v_line,
      'Accumulated depreciation — ' || v_asset.name,
      0,
      v_charge
    );

    update finance.fixed_assets
    set accumulated_depreciation = accumulated_depreciation + v_charge,
      last_depreciated_on = v_period.ends_on
    where id = v_asset.id;

    asset_count := asset_count + 1;
    total_depreciation := total_depreciation + v_charge;
  end loop;

  if asset_count = 0 then
    delete from finance.journals where id = v_journal_id;
    journal_number := null;
    return;
  end if;

  if p_post then
    update finance.journals set status = 'posted' where id = v_journal_id;
  end if;

  select j.journal_number into journal_number from finance.journals j where j.id = v_journal_id;
end;
$$;

comment on function finance.run_depreciation (uuid, boolean) is '{
    "type": "form",
    "resource": "fixed_assets",
    "name": "Run depreciation",
    "description": "Charge one month against every asset still carrying book value and post it as a single entry.",
    "icon": "TrendingDown",
    "success_message": "Depreciation run complete",
    "fields": {
        "sections": [
            {"id": "run", "title": "Run", "fields": ["p_period_id", "p_post"]}
        ],
        "relations": {
            "p_period_id": {"table": "fiscal_periods", "column": "id", "display": ["code", "name"]}
        }
    }
}';

revoke all on function finance.run_depreciation (uuid, boolean)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.run_depreciation (uuid, boolean) to "x-admin",
"accountant";

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view finance.trial_balance_report
with
  (security_invoker = true) as
select
  a.id,
  a.code,
  a.name as account,
  a.account_type,
  a.normal_balance,
  coalesce(p.code, '—') as parent,
  a.opening_balance,
  a.debit_total,
  a.credit_total,
  case
    when a.debit_total - a.credit_total > 0 then a.debit_total - a.credit_total
    else 0
  end as debit_balance,
  case
    when a.credit_total - a.debit_total > 0 then a.credit_total - a.debit_total
    else 0
  end as credit_balance,
  a.current_balance,
  a.is_postable
from
  finance.accounts a
  left join finance.accounts p on p.id = a.parent_id
where
  a.is_active
order by
  a.code;

comment on view finance.trial_balance_report is '{"type": "report", "name": "Trial Balance", "description": "Every account with its debit and credit position. If the two columns disagree, something is wrong."}';

create or replace view finance.profit_and_loss_report
with
  (security_invoker = true) as
select
  a.id,
  a.code,
  a.name as account,
  a.account_type,
  coalesce(p.code || ' ' || p.name, '—') as grouping,
  case
    when a.account_type = 'revenue' then a.credit_total - a.debit_total
    else 0
  end as income,
  case
    when a.account_type = 'expense' then a.debit_total - a.credit_total
    else 0
  end as expense,
  case
    when a.account_type = 'revenue' then a.credit_total - a.debit_total
    else - (a.debit_total - a.credit_total)
  end as contribution
from
  finance.accounts a
  left join finance.accounts p on p.id = a.parent_id
where
  a.account_type in ('revenue', 'expense')
  and a.is_active
  and a.is_postable
order by
  a.account_type desc,
  a.code;

comment on view finance.profit_and_loss_report is '{"type": "report", "name": "Profit and Loss", "description": "Income and expense by account, and what each one contributes to the bottom line."}';

create or replace view finance.balance_sheet_report
with
  (security_invoker = true) as
select
  a.id,
  a.code,
  a.name as account,
  a.account_type,
  case a.account_type
    when 'asset' then 'Assets'
    when 'liability' then 'Liabilities'
    else 'Equity'
  end as section,
  a.opening_balance,
  -- A contra account carries its balance on the opposite side to the
  -- section it sits in — accumulated depreciation is an asset account
  -- with a credit balance, recoverable tax a liability with a debit
  -- one. Presented at face value they would inflate their own section
  -- and the statement would not balance, so each is signed against
  -- the side its section actually belongs on.
  case
    when (
      a.account_type = 'asset'
      and a.normal_balance = 'debit'
    )
    or (
      a.account_type in ('liability', 'equity')
      and a.normal_balance = 'credit'
    ) then a.current_balance
    else - a.current_balance
  end as balance,
  round(
    100.0 * a.current_balance / nullif(
      sum(a.current_balance) filter (
        where
          a.account_type = 'asset'
      ) over (),
      0
    ),
    2
  ) as share_of_assets
from
  finance.accounts a
where
  a.account_type in ('asset', 'liability', 'equity')
  and a.is_active
  and a.is_postable
order by
  a.account_type,
  a.code;

comment on view finance.balance_sheet_report is '{"type": "report", "name": "Balance Sheet", "description": "What the business owns, owes and is worth."}';

create or replace view finance.receivables_aging_report
with
  (security_invoker = true) as
select
  i.id,
  i.invoice_number,
  c.code as customer_code,
  c.name as customer,
  i.status,
  i.issue_date,
  i.due_date,
  i.currency,
  i.total,
  i.paid_total,
  i.balance_due,
  i.days_overdue,
  case
    when i.balance_due <= 0 then 'settled'
    when i.days_overdue = 0 then 'current'
    when i.days_overdue <= 30 then '1-30'
    when i.days_overdue <= 60 then '31-60'
    when i.days_overdue <= 90 then '61-90'
    else '90+'
  end as bucket,
  coalesce(i.purchase_order, '—') as purchase_order
from
  finance.invoices i
  join finance.customers c on c.id = i.customer_id
where
  i.status not in ('draft', 'void')
order by
  i.days_overdue desc,
  i.due_date;

comment on view finance.receivables_aging_report is '{"type": "report", "name": "Receivables Aging", "description": "Who owes what, and for how long they have owed it", "template": true}';

create or replace view finance.payables_aging_report
with
  (security_invoker = true) as
select
  b.id,
  b.bill_number,
  v.code as vendor_code,
  v.name as vendor,
  b.status,
  b.issue_date,
  b.due_date,
  b.currency,
  b.total,
  b.paid_total,
  b.balance_due,
  greatest(current_date - b.due_date, 0) as days_overdue,
  case
    when b.balance_due <= 0 then 'settled'
    when b.due_date >= current_date then 'not due'
    when current_date - b.due_date <= 30 then '1-30'
    when current_date - b.due_date <= 60 then '31-60'
    else '60+'
  end as bucket,
  coalesce(b.vendor_reference, '—') as vendor_reference
from
  finance.bills b
  join finance.vendors v on v.id = b.vendor_id
where
  b.status not in ('draft', 'void')
order by
  b.due_date;

comment on view finance.payables_aging_report is '{"type": "report", "name": "Payables Aging", "description": "What is owed out, and when it falls due"}';

create or replace view finance.general_ledger_report
with
  (security_invoker = true) as
select
  l.id,
  j.journal_number,
  j.entry_date,
  fp.code as period,
  j.status as journal_status,
  j.source,
  a.code as account_code,
  a.name as account,
  a.account_type,
  coalesce(cc.code, '—') as cost_center,
  coalesce(l.description, j.memo) as narrative,
  l.debit,
  l.credit,
  l.debit - l.credit as movement,
  coalesce(j.reference, '—') as reference
from
  finance.journal_lines l
  join finance.journals j on j.id = l.journal_id
  left join finance.accounts a on a.id = l.account_id
  left join finance.cost_centers cc on cc.id = l.cost_center_id
  left join finance.fiscal_periods fp on fp.id = j.period_id
where
  j.status <> 'draft'
order by
  j.entry_date desc,
  j.journal_number,
  l.line_number;

comment on view finance.general_ledger_report is '{"type": "report", "name": "General Ledger", "description": "Every posted line, in date order. The book of record."}';

create or replace view finance.cash_movement_report
with
  (security_invoker = true) as
select
  p.id,
  p.payment_number,
  p.payment_date,
  p.direction,
  p.method,
  coalesce(c.name, v.name, '—') as counterparty,
  coalesce(ba.name, '—') as bank_account,
  p.currency,
  case
    when p.direction = 'inbound' then p.amount
    else 0
  end as money_in,
  case
    when p.direction = 'outbound' then p.amount
    else 0
  end as money_out,
  p.allocated_total,
  p.unallocated_total,
  coalesce(p.reference, '—') as reference
from
  finance.payments p
  left join finance.customers c on c.id = p.customer_id
  left join finance.vendors v on v.id = p.vendor_id
  left join finance.bank_accounts ba on ba.id = p.bank_account_id
order by
  p.payment_date desc;

comment on view finance.cash_movement_report is '{"type": "report", "name": "Cash Movement", "description": "Money in and money out, with whatever is still unallocated"}';

create or replace view finance.budget_variance_report
with
  (security_invoker = true) as
select
  b.id,
  b.fiscal_year,
  coalesce(fp.code, 'Full year') as period,
  a.code as account_code,
  a.name as account,
  a.account_type,
  coalesce(cc.code, 'All') as cost_center,
  b.status,
  b.budget_amount,
  b.actual_amount,
  b.variance_amount,
  b.variance_percent,
  case
    when b.variance_amount < 0 then 'over'
    when b.variance_amount = 0 then 'on plan'
    else 'under'
  end as verdict
from
  finance.budgets b
  join finance.accounts a on a.id = b.account_id
  left join finance.cost_centers cc on cc.id = b.cost_center_id
  left join finance.fiscal_periods fp on fp.id = b.period_id
order by
  b.variance_amount;

comment on view finance.budget_variance_report is '{"type": "report", "name": "Budget vs Actual", "description": "Where spending has run ahead of plan"}';

create or replace view finance.expense_claim_report
with
  (security_invoker = true) as
select
  l.id,
  ec.claim_number,
  coalesce(u.name, ec.claimant_name, 'Unknown') as claimant,
  ec.status as claim_status,
  coalesce(cc.code, '—') as cost_center,
  l.spent_on,
  l.category,
  coalesce(l.merchant, '—') as merchant,
  l.description,
  l.net_amount,
  l.tax_amount,
  l.gross_amount,
  l.is_reimbursable,
  l.has_receipt
from
  finance.expense_lines l
  join finance.expense_claims ec on ec.id = l.claim_id
  left join finance.users u on u.id = ec.claimant_id
  left join finance.cost_centers cc on cc.id = ec.cost_center_id
order by
  l.spent_on desc;

comment on view finance.expense_claim_report is '{"type": "report", "name": "Expense Detail", "description": "Every expense line, who spent it and whether a receipt came with it"}';

create or replace view finance.tax_summary_report
with
  (security_invoker = true) as
select
  t.id,
  t.code,
  t.name as tax_rate,
  t.rate,
  t.country,
  t.is_recoverable,
  coalesce(sales.net, 0) as sales_net,
  coalesce(sales.tax, 0) as tax_collected,
  coalesce(purchases.net, 0) as purchases_net,
  coalesce(purchases.tax, 0) as tax_paid,
  coalesce(sales.tax, 0) - coalesce(purchases.tax, 0) as net_tax_due
from
  finance.tax_rates t
  left join lateral (
    select
      sum(il.net_amount) as net,
      sum(il.tax_amount) as tax
    from
      finance.invoice_lines il
      join finance.invoices i on i.id = il.invoice_id
    where
      il.tax_rate_id = t.id
      and i.status not in ('draft', 'void')
  ) sales on true
  left join lateral (
    select
      sum(bl.net_amount) as net,
      sum(bl.tax_amount) as tax
    from
      finance.bill_lines bl
      join finance.bills b on b.id = bl.bill_id
    where
      bl.tax_rate_id = t.id
      and b.status not in ('draft', 'awaiting_approval', 'void')
  ) purchases on true
order by
  t.code;

comment on view finance.tax_summary_report is '{"type": "report", "name": "Tax Summary", "description": "Tax collected on sales against tax paid on purchases, per rate"}';

revoke all on finance.trial_balance_report,
finance.profit_and_loss_report,
finance.balance_sheet_report,
finance.receivables_aging_report,
finance.payables_aging_report,
finance.general_ledger_report,
finance.cash_movement_report,
finance.budget_variance_report,
finance.expense_claim_report,
finance.tax_summary_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on finance.trial_balance_report,
  finance.profit_and_loss_report,
  finance.balance_sheet_report,
  finance.receivables_aging_report,
  finance.payables_aging_report,
  finance.general_ledger_report,
  finance.cash_movement_report,
  finance.budget_variance_report,
  finance.expense_claim_report,
  finance.tax_summary_report to "x-admin",
  "accountant",
  "finance-auditor";

----------------------------------------------------------------
-- Views and a materialized view surfaced as browsable resources
----------------------------------------------------------------
-- Everything still owed, in both directions, in one list. The people
-- chasing money do not care whether it is an invoice or a bill — they
-- care what is open and how late it is.
create or replace view finance.open_items
with
  (security_invoker = true) as
select
  i.id,
  'receivable' as side,
  i.invoice_number as document,
  c.name as counterparty,
  i.status::text as status,
  i.issue_date,
  i.due_date,
  i.currency,
  i.total,
  i.balance_due,
  i.days_overdue,
  '/finance/resource/invoices/' || i.id || '/detail' as link
from
  finance.invoices i
  join finance.customers c on c.id = i.customer_id
where
  i.status in ('sent', 'partially_paid', 'overdue')
  and i.balance_due > 0
union all
select
  b.id,
  'payable' as side,
  b.bill_number as document,
  v.name as counterparty,
  b.status::text as status,
  b.issue_date,
  b.due_date,
  b.currency,
  b.total,
  b.balance_due,
  greatest(current_date - b.due_date, 0) as days_overdue,
  '/finance/resource/bills/' || b.id || '/detail' as link
from
  finance.bills b
  join finance.vendors v on v.id = b.vendor_id
where
  b.status in ('approved', 'partially_paid')
  and b.balance_due > 0;

comment on view finance.open_items is '{
    "icon": "ListChecks",
    "name": "Open Items",
    "description": "Everything still owed in either direction, oldest first.",
    "collapsible_group": "Insights",
    "display": "block",
    "primary_view": "list",
    "views": [
        {"id": "list", "name": "Open Items", "type": "list", "title": "document", "description": "counterparty", "field_1": "balance_due", "field_2": "days_overdue"},
        {"id": "kanban", "name": "By Side", "type": "kanban", "group": "side", "title": "document", "description": "counterparty", "date": "due_date", "badge": "status", "read_only": true},
        {"id": "calendar", "name": "Due Dates", "type": "calendar", "title": "document", "badge": "side", "start_date": "due_date", "read_only": true}
    ],
    "filter_presets": [
        {"id": "receivables", "name": "Owed To Us", "filters": [{"id": "side", "value": "receivable", "operator": "eq"}]},
        {"id": "payables", "name": "Owed By Us", "filters": [{"id": "side", "value": "payable", "operator": "eq"}]},
        {"id": "late", "name": "Overdue", "filters": [{"id": "days_overdue", "value": "0", "operator": "gt"}]}
    ],
    "query": {"sort": [{"id": "due_date", "desc": false}]}
}';

comment on column finance.open_items.balance_due is '{"aggregate": "sum"}';

-- Twelve months of shape, precomputed. Charts read this instead of
-- walking every posted line every time somebody opens the dashboard.
-- Refresh with:
--   refresh materialized view concurrently finance.monthly_performance;
create materialized view finance.monthly_performance as
select
  fp.id,
  fp.code as period,
  fp.fiscal_year,
  fp.period_number,
  fp.starts_on,
  fp.status::text as period_status,
  coalesce(
    sum(l.credit - l.debit) filter (
      where
        a.account_type = 'revenue'
    ),
    0
  ) as revenue,
  coalesce(
    sum(l.debit - l.credit) filter (
      where
        a.account_type = 'expense'
    ),
    0
  ) as expenses,
  coalesce(
    sum(l.credit - l.debit) filter (
      where
        a.account_type = 'revenue'
    ),
    0
  ) - coalesce(
    sum(l.debit - l.credit) filter (
      where
        a.account_type = 'expense'
    ),
    0
  ) as net_result,
  coalesce(
    (
      select
        sum(p.amount)
      from
        finance.payments p
      where
        p.period_id = fp.id
        and p.direction = 'inbound'
    ),
    0
  ) as cash_in,
  coalesce(
    (
      select
        sum(p.amount)
      from
        finance.payments p
      where
        p.period_id = fp.id
        and p.direction = 'outbound'
    ),
    0
  ) as cash_out,
  coalesce(
    (
      select
        sum(i.total)
      from
        finance.invoices i
      where
        i.period_id = fp.id
        and i.status not in ('draft', 'void')
    ),
    0
  ) as invoiced,
  count(distinct j.id) as journal_count
from
  finance.fiscal_periods fp
  left join finance.journals j on j.period_id = fp.id
  and j.status <> 'draft'
  left join finance.journal_lines l on l.journal_id = j.id
  left join finance.accounts a on a.id = l.account_id
group by
  fp.id,
  fp.code,
  fp.fiscal_year,
  fp.period_number,
  fp.starts_on,
  fp.status;

-- Concurrent refresh needs a unique index; without one the dashboard
-- would lock every reader out for the length of the rebuild.
create unique index idx_fin_monthly_performance_id on finance.monthly_performance (id);

create index idx_fin_monthly_performance_start on finance.monthly_performance (starts_on);

comment on materialized view finance.monthly_performance is '{
    "icon": "ChartNoAxesCombined",
    "name": "Monthly Performance",
    "description": "Precomputed revenue, cost and cash per period. Refresh with: refresh materialized view concurrently finance.monthly_performance;",
    "collapsible_group": "Insights",
    "display": "block",
    "primary_view": "list",
    "views": [
        {"id": "list", "name": "By Period", "type": "list", "title": "period", "description": "period_status", "field_1": "revenue", "field_2": "net_result"}
    ],
    "filter_presets": [
        {"id": "loss", "name": "Loss-making Months", "filters": [{"id": "net_result", "value": "0", "operator": "lt"}]},
        {"id": "open", "name": "Open Periods", "filters": [{"id": "period_status", "value": "open", "operator": "eq"}]}
    ],
    "query": {"sort": [{"id": "starts_on", "desc": true}]}
}';

comment on column finance.monthly_performance.revenue is '{"aggregate": "sum"}';

comment on column finance.monthly_performance.expenses is '{"aggregate": "sum"}';

comment on column finance.monthly_performance.net_result is '{"name": "Net", "aggregate": "sum"}';

revoke all on finance.open_items,
finance.monthly_performance
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on finance.open_items,
  finance.monthly_performance to "x-admin",
  "accountant",
  "finance-auditor";

----------------------------------------------------------------
-- Dashboard widgets
----------------------------------------------------------------
create or replace view finance.cash_on_hand
with
  (security_invoker = true) as
select
  round(coalesce(sum(ledger_balance), 0), 2) as value,
  'landmark' as icon,
  'across all bank accounts' as label
from
  finance.bank_accounts
where
  is_active;

create or replace view finance.overdue_receivables_count
with
  (security_invoker = true) as
select
  round(coalesce(sum(balance_due), 0), 2) as value,
  'triangle-alert' as icon,
  'overdue and unpaid' as label
from
  finance.invoices
where
  status = 'overdue';

create or replace view finance.claims_awaiting_decision
with
  (security_invoker = true) as
select
  count(*) as value,
  'wallet' as icon,
  'claims waiting on finance' as label
from
  finance.expense_claims
where
  status = 'submitted';

create or replace view finance.unreconciled_lines_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'arrow-left-right' as icon,
  'statement lines to match' as label
from
  finance.bank_transactions
where
  status = 'unreconciled';

create or replace view finance.cash_in_out_split
with
  (security_invoker = true) as
select
  round(
    coalesce(
      sum(amount) filter (
        where
          direction = 'inbound'
      ),
      0
    ),
    2
  ) as primary,
  round(
    coalesce(
      sum(amount) filter (
        where
          direction = 'outbound'
      ),
      0
    ),
    2
  ) as secondary,
  'In (90d)' as primary_label,
  'Out (90d)' as secondary_label
from
  finance.payments
where
  payment_date >= current_date - 90;

create or replace view finance.invoiced_vs_collected
with
  (security_invoker = true) as
select
  round(coalesce(sum(invoiced_total), 0), 2) as primary,
  round(coalesce(sum(paid_total), 0), 2) as secondary,
  'Invoiced' as primary_label,
  'Collected' as secondary_label
from
  finance.customers;

create or replace view finance.collection_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * coalesce(sum(paid_total), 0) / nullif(sum(total), 0),
    1
  ) as percent
from
  finance.invoices
where
  status not in ('draft', 'void');

create or replace view finance.budget_consumed_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * coalesce(sum(actual_amount), 0) / nullif(sum(budget_amount), 0),
    1
  ) as percent
from
  finance.budgets
where
  fiscal_year = extract(
    year
    from
      current_date
  );

create or replace view finance.receivables_by_age
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      days_overdue = 0
  ) as current,
  count(*) as total,
  json_build_array(
    json_build_object(
      'label',
      'Current',
      'value',
      count(*) filter (
        where
          days_overdue = 0
      )
    ),
    json_build_object(
      'label',
      '1-30',
      'value',
      count(*) filter (
        where
          days_overdue between 1 and 30
      )
    ),
    json_build_object(
      'label',
      '31-60',
      'value',
      count(*) filter (
        where
          days_overdue between 31 and 60
      )
    ),
    json_build_object(
      'label',
      '60+',
      'value',
      count(*) filter (
        where
          days_overdue > 60
      )
    )
  ) as segments
from
  finance.invoices
where
  status in ('sent', 'partially_paid', 'overdue')
  and balance_due > 0;

create or replace view finance.ledger_position_overview
with
  (security_invoker = true) as
select
  count(*) as value,
  'Postable accounts' as label,
  'book-open' as icon,
  json_build_array(
    json_build_object(
      'label',
      'Assets',
      'value',
      round(
        coalesce(
          sum(current_balance) filter (
            where
              account_type = 'asset'
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
      'Liabilities',
      'value',
      round(
        coalesce(
          sum(current_balance) filter (
            where
              account_type = 'liability'
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
      'Revenue',
      'value',
      round(
        coalesce(
          sum(current_balance) filter (
            where
              account_type = 'revenue'
          ),
          0
        ),
        0
      ),
      'variant',
      'success'
    ),
    json_build_object(
      'label',
      'Expenses',
      'value',
      round(
        coalesce(
          sum(current_balance) filter (
            where
              account_type = 'expense'
          ),
          0
        ),
        0
      ),
      'variant',
      'destructive'
    )
  ) as breakdown
from
  finance.accounts
where
  is_postable
  and is_active;

create or replace view finance.finance_pulse
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Draft journals',
      'value',
      (
        select
          count(*)
        from
          finance.journals
        where
          status = 'draft'
      ),
      'icon',
      'file-pen'
    ),
    json_build_object(
      'label',
      'Open periods',
      'value',
      (
        select
          count(*)
        from
          finance.fiscal_periods
        where
          status = 'open'
      ),
      'icon',
      'calendar-range'
    ),
    json_build_object(
      'label',
      'Receivable',
      'value',
      (
        select
          round(coalesce(sum(outstanding_total), 0), 0)
        from
          finance.customers
      ),
      'icon',
      'file-text'
    ),
    json_build_object(
      'label',
      'Payable',
      'value',
      (
        select
          round(coalesce(sum(outstanding_total), 0), 0)
        from
          finance.vendors
      ),
      'icon',
      'receipt'
    ),
    json_build_object(
      'label',
      'Unallocated cash',
      'value',
      (
        select
          round(coalesce(sum(unallocated_total), 0), 0)
        from
          finance.payments
      ),
      'icon',
      'banknote'
    ),
    json_build_object(
      'label',
      'Assets in service',
      'value',
      (
        select
          count(*)
        from
          finance.fixed_assets
        where
          status = 'in_service'
      ),
      'icon',
      'boxes'
    )
  ) as metrics;

create or replace view finance.invoices_due_next
with
  (security_invoker = true) as
select
  i.invoice_number,
  c.name as customer,
  i.balance_due,
  to_char(i.due_date, 'Mon DD') as due,
  i.days_overdue,
  '/finance/resource/invoices/' || i.id || '/detail' as link
from
  finance.invoices i
  join finance.customers c on c.id = i.customer_id
where
  i.status in ('sent', 'partially_paid', 'overdue')
  and i.balance_due > 0
order by
  i.due_date
limit
  10;

create or replace view finance.bills_to_pay
with
  (security_invoker = true) as
select
  b.bill_number,
  v.name as vendor,
  b.balance_due,
  to_char(b.due_date, 'Mon DD') as due,
  b.status,
  '/finance/resource/bills/' || b.id || '/detail' as link
from
  finance.bills b
  join finance.vendors v on v.id = b.vendor_id
where
  b.status in ('approved', 'partially_paid')
  and b.balance_due > 0
order by
  b.due_date
limit
  10;

create or replace view finance.customer_scorecard
with
  (security_invoker = true) as
select
  c.name as customer,
  c.invoiced_total as invoiced,
  c.paid_total as collected,
  c.outstanding_total as outstanding,
  c.overdue_total as overdue,
  '/finance/resource/customers/' || c.id || '/detail' as link
from
  finance.customers c
where
  c.invoiced_total > 0
order by
  c.outstanding_total desc,
  c.invoiced_total desc
limit
  10;

create or replace view finance.journals_awaiting_posting
with
  (security_invoker = true) as
select
  j.journal_number || ' — ' || coalesce(j.memo, 'No memo') as title,
  j.line_count || ' line(s), ' || j.total_debit || ' Dr' as description,
  'file-pen' as icon,
  case
    when j.is_balanced then 'warning'
    else 'destructive'
  end as variant,
  '/finance/resource/journals/' || j.id || '/detail' as link
from
  finance.journals j
where
  j.status = 'draft'
order by
  j.entry_date
limit
  10;

create or replace view finance.overdue_watchlist
with
  (security_invoker = true) as
select
  c.name as title,
  i.invoice_number as description,
  'triangle-alert' as icon,
  'destructive' as variant,
  i.balance_due::text as field_1,
  i.days_overdue || ' days' as field_2,
  '/finance/resource/invoices/' || i.id || '/detail' as link
from
  finance.invoices i
  join finance.customers c on c.id = i.customer_id
where
  i.status = 'overdue'
order by
  i.days_overdue desc
limit
  10;

create or replace view finance.recent_ledger_activity
with
  (security_invoker = true) as
select
  coalesce(u.name, 'System') as actor,
  case e.event_type
    when 'created' then 'drafted'
    when 'posted' then 'posted'
    when 'reversed' then 'reversed'
    when 'line_changed' then 'edited'
    else 'updated'
  end as action,
  j.journal_number as entity,
  to_char(e.occurred_at, 'Mon DD, YYYY') as date,
  '/finance/resource/journals/' || j.id || '/detail' as link
from
  finance.journal_events e
  join finance.journals j on j.id = e.journal_id
  left join finance.users u on u.id = e.actor_id
order by
  e.occurred_at desc
limit
  10;

create or replace view finance.top_revenue_customers
with
  (security_invoker = true) as
select
  c.name,
  c.invoiced_total as value,
  coalesce(c.country, c.currency) as label,
  '/finance/resource/customers/' || c.id || '/detail' as link
from
  finance.customers c
where
  c.invoiced_total > 0
order by
  c.invoiced_total desc
limit
  10;

revoke all on finance.cash_on_hand,
finance.overdue_receivables_count,
finance.claims_awaiting_decision,
finance.unreconciled_lines_count,
finance.cash_in_out_split,
finance.invoiced_vs_collected,
finance.collection_rate,
finance.budget_consumed_rate,
finance.receivables_by_age,
finance.ledger_position_overview,
finance.finance_pulse,
finance.invoices_due_next,
finance.bills_to_pay,
finance.customer_scorecard,
finance.journals_awaiting_posting,
finance.overdue_watchlist,
finance.recent_ledger_activity,
finance.top_revenue_customers
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on finance.cash_on_hand,
  finance.overdue_receivables_count,
  finance.claims_awaiting_decision,
  finance.unreconciled_lines_count,
  finance.cash_in_out_split,
  finance.invoiced_vs_collected,
  finance.collection_rate,
  finance.budget_consumed_rate,
  finance.receivables_by_age,
  finance.ledger_position_overview,
  finance.finance_pulse,
  finance.invoices_due_next,
  finance.bills_to_pay,
  finance.customer_scorecard,
  finance.journals_awaiting_posting,
  finance.overdue_watchlist,
  finance.recent_ledger_activity,
  finance.top_revenue_customers to "x-admin",
  "accountant",
  "finance-auditor";

comment on view finance.cash_on_hand is '{"type": "dashboard_widget", "name": "Cash On Hand", "description": "What the ledger says is in the bank", "widget_type": "card_1"}';

comment on view finance.overdue_receivables_count is '{"type": "dashboard_widget", "name": "Overdue", "description": "Money owed past its due date", "widget_type": "card_1", "resource": "invoices"}';

comment on view finance.claims_awaiting_decision is '{"type": "dashboard_widget", "name": "Claims To Decide", "description": "Expense claims sitting with finance", "widget_type": "card_1", "resource": "expense_claims"}';

comment on view finance.unreconciled_lines_count is '{"type": "dashboard_widget", "name": "To Reconcile", "description": "Statement lines with no match yet", "widget_type": "card_1", "resource": "bank_transactions"}';

comment on view finance.cash_in_out_split is '{"type": "dashboard_widget", "name": "Cash In vs Out", "description": "Ninety days of movement", "widget_type": "card_2"}';

comment on view finance.invoiced_vs_collected is '{"type": "dashboard_widget", "name": "Invoiced vs Collected", "description": "How much of what was billed has actually landed", "widget_type": "card_2", "resource": "customers"}';

comment on view finance.collection_rate is '{"type": "dashboard_widget", "name": "Collection Rate", "description": "Share of issued invoices collected", "widget_type": "card_3"}';

comment on view finance.budget_consumed_rate is '{"type": "dashboard_widget", "name": "Budget Consumed", "description": "Actual against plan for the current year", "widget_type": "card_3", "resource": "budgets"}';

comment on view finance.receivables_by_age is '{"type": "dashboard_widget", "name": "Receivables By Age", "description": "How the open invoices are aging", "widget_type": "card_4"}';

comment on view finance.ledger_position_overview is '{"type": "dashboard_widget", "name": "Ledger Position", "description": "The chart of accounts at a glance", "widget_type": "card_5"}';

comment on view finance.finance_pulse is '{"type": "dashboard_widget", "name": "Finance Pulse", "description": "Drafts, periods, positions and cash in one row", "widget_type": "card_6"}';

comment on view finance.invoices_due_next is '{"type": "dashboard_widget", "name": "Due Next", "description": "The invoices to chase first", "widget_type": "table_1", "resource": "invoices", "url": "/finance/resource/invoices"}';

comment on view finance.bills_to_pay is '{"type": "dashboard_widget", "name": "Bills To Pay", "description": "Approved bills waiting on a payment run", "widget_type": "table_1", "url": "/finance/resource/bills"}';

comment on view finance.customer_scorecard is '{"type": "dashboard_widget", "name": "Customer Scorecard", "description": "Invoiced, collected and still owed per customer", "widget_type": "table_2", "url": "/finance/resource/customers"}';

comment on view finance.journals_awaiting_posting is '{"type": "dashboard_widget", "name": "Drafts To Post", "description": "Entries that have not reached the ledger yet", "widget_type": "list_1", "url": "/finance/resource/journals"}';

comment on view finance.overdue_watchlist is '{"type": "dashboard_widget", "name": "Overdue Watchlist", "description": "The latest invoices, worst first", "widget_type": "list_2", "url": "/finance/resource/invoices"}';

comment on view finance.recent_ledger_activity is '{"type": "dashboard_widget", "name": "Recent Activity", "description": "What has happened to the ledger lately", "widget_type": "list_3", "url": "/finance/resource/journals"}';

comment on view finance.top_revenue_customers is '{"type": "dashboard_widget", "name": "Top Customers", "description": "Ranked by lifetime invoiced value", "widget_type": "list_4", "url": "/finance/resource/customers"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
create or replace view finance.revenue_vs_expense_bar
with
  (security_invoker = true) as
select
  to_char(starts_on, 'Mon YY') as label,
  round(revenue, 0) as revenue,
  round(expenses, 0) as expenses
from
  finance.monthly_performance
where
  starts_on >= (current_date - interval '12 months')
order by
  starts_on;

create or replace view finance.net_result_line
with
  (security_invoker = true) as
select
  to_char(starts_on, 'Mon YY') as date,
  round(net_result, 0) as net_result,
  round(revenue, 0) as revenue
from
  finance.monthly_performance
where
  starts_on >= (current_date - interval '12 months')
order by
  starts_on;

create or replace view finance.cash_flow_area
with
  (security_invoker = true) as
select
  to_char(starts_on, 'Mon YY') as date,
  round(cash_in, 0) as cash_in,
  round(cash_out, 0) as cash_out,
  round(cash_in - cash_out, 0) as net_cash
from
  finance.monthly_performance
where
  starts_on >= (current_date - interval '12 months')
order by
  starts_on;

create or replace view finance.receivables_aging_pie
with
  (security_invoker = true) as
select
  case
    when days_overdue = 0 then 'Current'
    when days_overdue <= 30 then '1-30 days'
    when days_overdue <= 60 then '31-60 days'
    when days_overdue <= 90 then '61-90 days'
    else '90+ days'
  end as label,
  round(sum(balance_due), 0) as value
from
  finance.invoices
where
  status in ('sent', 'partially_paid', 'overdue')
  and balance_due > 0
group by
  1
having
  sum(balance_due) > 0;

create or replace view finance.expense_by_category_pie
with
  (security_invoker = true) as
select
  initcap(replace(l.category::text, '_', ' ')) as label,
  round(sum(l.gross_amount), 0) as value
from
  finance.expense_lines l
  join finance.expense_claims c on c.id = l.claim_id
where
  c.status in ('approved', 'reimbursed')
group by
  1
having
  sum(l.gross_amount) > 0;

create or replace view finance.top_customers_bar
with
  (security_invoker = true) as
select
  c.name as label,
  round(c.invoiced_total, 0) as invoiced,
  round(c.paid_total, 0) as collected,
  round(c.outstanding_total, 0) as outstanding
from
  finance.customers c
where
  c.invoiced_total > 0
order by
  c.invoiced_total desc
limit
  10;

create or replace view finance.budget_vs_actual_bar
with
  (security_invoker = true) as
select
  coalesce(cc.code, a.code) as label,
  round(sum(b.budget_amount), 0) as budget,
  round(sum(b.actual_amount), 0) as actual
from
  finance.budgets b
  join finance.accounts a on a.id = b.account_id
  left join finance.cost_centers cc on cc.id = b.cost_center_id
where
  b.fiscal_year = extract(
    year
    from
      current_date
  )
group by
  1
order by
  sum(b.budget_amount) desc
limit
  12;

create or replace view finance.payment_method_pie
with
  (security_invoker = true) as
select
  initcap(replace(method::text, '_', ' ')) as label,
  round(sum(amount), 0) as value
from
  finance.payments
group by
  1
having
  sum(amount) > 0;

create or replace view finance.financial_health_radar
with
  (security_invoker = true) as
select
  'Collection' as label,
  round(
    100.0 * coalesce(sum(paid_total), 0) / nullif(sum(total), 0),
    0
  ) as score
from
  finance.invoices
where
  status not in ('draft', 'void')
union all
select
  'Reconciliation',
  round(
    100.0 * count(*) filter (
      where
        status in ('reconciled', 'ignored')
    ) / nullif(count(*), 0),
    0
  )
from
  finance.bank_transactions
union all
select
  'On-time payables',
  round(
    100.0 * count(*) filter (
      where
        status = 'paid'
        and paid_at::date <= due_date
    ) / nullif(
      count(*) filter (
        where
          status = 'paid'
      ),
      0
    ),
    0
  )
from
  finance.bills
union all
select
  'Budget discipline',
  round(
    100.0 * count(*) filter (
      where
        variance_amount >= 0
    ) / nullif(count(*), 0),
    0
  )
from
  finance.budgets
union all
select
  'Period hygiene',
  round(
    100.0 * count(*) filter (
      where
        status in ('closed', 'locked')
    ) / nullif(
      count(*) filter (
        where
          starts_on < date_trunc('month', current_date)
      ),
      0
    ),
    0
  )
from
  finance.fiscal_periods
where
  starts_on < date_trunc('month', current_date);

revoke all on finance.revenue_vs_expense_bar,
finance.net_result_line,
finance.cash_flow_area,
finance.receivables_aging_pie,
finance.expense_by_category_pie,
finance.top_customers_bar,
finance.budget_vs_actual_bar,
finance.payment_method_pie,
finance.financial_health_radar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on finance.revenue_vs_expense_bar,
  finance.net_result_line,
  finance.cash_flow_area,
  finance.receivables_aging_pie,
  finance.expense_by_category_pie,
  finance.top_customers_bar,
  finance.budget_vs_actual_bar,
  finance.payment_method_pie,
  finance.financial_health_radar to "x-admin",
  "accountant",
  "finance-auditor";

comment on view finance.revenue_vs_expense_bar is '{"type": "chart", "name": "Revenue vs Expenses", "description": "Twelve months of income against cost", "chart_type": "bar", "format": "currency"}';

comment on view finance.net_result_line is '{"type": "chart", "name": "Net Result", "description": "What is left after everything else", "chart_type": "line", "format": "currency"}';

comment on view finance.cash_flow_area is '{"type": "chart", "name": "Cash Flow", "description": "Money in, money out and the net position", "chart_type": "area", "format": "currency"}';

comment on view finance.receivables_aging_pie is '{"type": "chart", "name": "Receivables Aging", "description": "How the open balance is distributed by age", "chart_type": "pie", "format": "currency", "resource": "invoices"}';

comment on view finance.expense_by_category_pie is '{"type": "chart", "name": "Expenses By Category", "description": "Where approved claims are going", "chart_type": "pie", "format": "currency", "resource": "expense_claims"}';

comment on view finance.top_customers_bar is '{"type": "chart", "name": "Top Customers", "description": "Invoiced, collected and still outstanding", "chart_type": "bar", "format": "currency", "resource": "customers"}';

comment on view finance.budget_vs_actual_bar is '{"type": "chart", "name": "Budget vs Actual", "description": "Plan against reality by cost centre", "chart_type": "bar", "format": "currency", "resource": "budgets"}';

comment on view finance.payment_method_pie is '{"type": "chart", "name": "Payment Methods", "description": "How money actually moves", "chart_type": "pie", "format": "currency", "resource": "payments"}';

comment on view finance.financial_health_radar is '{"type": "chart", "name": "Financial Health", "description": "Five housekeeping measures, scored out of a hundred", "chart_type": "radar"}';

----------------------------------------------------------------
-- Templates
--
-- A template is a view whose columns line up with a target table.
-- Applying it inserts the rows it produces. Each one is written so a
-- second application is a no-op rather than a unique-violation.
----------------------------------------------------------------
create or replace view finance.chart_of_accounts_template
with
  (security_invoker = true) as
select
  t.code,
  t.name,
  t.account_type,
  t.normal_balance,
  t.is_postable,
  t.is_bank_account,
  t.description
from
  (
    values
      (
        '1010',
        'Bank — Operating',
        'asset',
        'debit',
        true,
        true,
        'The main current account'
      ),
      (
        '1020',
        'Bank — Savings',
        'asset',
        'debit',
        true,
        true,
        'Reserve cash'
      ),
      (
        '1100',
        'Accounts Receivable',
        'asset',
        'debit',
        true,
        false,
        'Money owed by customers'
      ),
      (
        '1200',
        'Prepayments',
        'asset',
        'debit',
        true,
        false,
        'Costs paid ahead of the period they belong to'
      ),
      (
        '1500',
        'Fixed Assets — Cost',
        'asset',
        'debit',
        true,
        false,
        'What the asset register cost'
      ),
      (
        '1590',
        'Accumulated Depreciation',
        'asset',
        'credit',
        true,
        false,
        'Contra-asset against the register'
      ),
      (
        '2100',
        'Accounts Payable',
        'liability',
        'credit',
        true,
        false,
        'Money owed to suppliers'
      ),
      (
        '2200',
        'Sales Tax Payable',
        'liability',
        'credit',
        true,
        false,
        'Tax collected on sales'
      ),
      (
        '2210',
        'Input Tax Recoverable',
        'liability',
        'debit',
        true,
        false,
        'Tax paid on purchases'
      ),
      (
        '2300',
        'Accruals',
        'liability',
        'credit',
        true,
        false,
        'Costs incurred but not yet billed'
      ),
      (
        '3000',
        'Share Capital',
        'equity',
        'credit',
        true,
        false,
        'Paid-in capital'
      ),
      (
        '3900',
        'Retained Earnings',
        'equity',
        'credit',
        true,
        false,
        'Accumulated result carried forward'
      ),
      (
        '4000',
        'Product Revenue',
        'revenue',
        'credit',
        true,
        false,
        'Licence and subscription income'
      ),
      (
        '4100',
        'Services Revenue',
        'revenue',
        'credit',
        true,
        false,
        'Consulting and implementation'
      ),
      (
        '4900',
        'Other Income',
        'revenue',
        'credit',
        true,
        false,
        'Anything that is not the main trade'
      ),
      (
        '5000',
        'Cost of Sales',
        'expense',
        'debit',
        true,
        false,
        'Direct cost of delivering revenue'
      ),
      (
        '6000',
        'Salaries and Wages',
        'expense',
        'debit',
        true,
        false,
        'Payroll'
      ),
      (
        '6100',
        'Travel and Subsistence',
        'expense',
        'debit',
        true,
        false,
        'Getting there and staying there'
      ),
      (
        '6200',
        'Software and Subscriptions',
        'expense',
        'debit',
        true,
        false,
        'Tools the business runs on'
      ),
      (
        '6300',
        'Marketing',
        'expense',
        'debit',
        true,
        false,
        'Demand generation'
      ),
      (
        '6400',
        'Professional Fees',
        'expense',
        'debit',
        true,
        false,
        'Legal, audit and advisory'
      ),
      (
        '6500',
        'Depreciation',
        'expense',
        'debit',
        true,
        false,
        'Wear on the asset register'
      ),
      (
        '6900',
        'Other Operating Costs',
        'expense',
        'debit',
        true,
        false,
        'Everything else'
      )
  ) as t (
    code,
    name,
    account_type,
    normal_balance,
    is_postable,
    is_bank_account,
    description
  )
where
  not exists (
    select
      1
    from
      finance.accounts a
    where
      a.code = t.code
  );

comment on view finance.chart_of_accounts_template is '{"type": "template", "name": "Standard Chart of Accounts", "description": "Twenty-three accounts covering assets, liabilities, equity, income and cost. Apply to finance.accounts to get a working ledger from nothing.", "target_table": "accounts"}';

create or replace view finance.tax_rates_template
with
  (security_invoker = true) as
select
  t.code,
  t.name,
  t.rate,
  t.country,
  t.is_recoverable
from
  (
    values
      ('STD-20', 'Standard rate 20%', 20.0, 'GB', true),
      ('RED-5', 'Reduced rate 5%', 5.0, 'GB', true),
      ('ZERO', 'Zero rated', 0.0, 'GB', true),
      ('EXEMPT', 'Exempt', 0.0, 'GB', false),
      ('US-NONE', 'No sales tax', 0.0, 'US', false),
      ('EU-21', 'EU standard 21%', 21.0, 'NL', true)
  ) as t (code, name, rate, country, is_recoverable)
where
  not exists (
    select
      1
    from
      finance.tax_rates r
    where
      r.code = t.code
  );

comment on view finance.tax_rates_template is '{"type": "template", "name": "Common Tax Rates", "description": "The handful of rates most businesses need. Apply to finance.tax_rates.", "target_table": "tax_rates"}';

create or replace view finance.cost_centers_template
with
  (security_invoker = true) as
select
  t.code,
  t.name,
  t.description,
  t.annual_budget
from
  (
    values
      (
        'ENG',
        'Engineering',
        'Product development',
        1200000
      ),
      (
        'SALES',
        'Sales',
        'New business and account management',
        900000
      ),
      (
        'MKT',
        'Marketing',
        'Demand generation and brand',
        400000
      ),
      (
        'CS',
        'Customer Success',
        'Onboarding, support and renewals',
        350000
      ),
      (
        'GA',
        'General and Administrative',
        'Finance, legal, people and facilities',
        500000
      )
  ) as t (code, name, description, annual_budget)
where
  not exists (
    select
      1
    from
      finance.cost_centers c
    where
      c.code = t.code
  );

comment on view finance.cost_centers_template is '{"type": "template", "name": "Default Cost Centres", "description": "Five departments with indicative annual budgets. Apply to finance.cost_centers.", "target_table": "cost_centers"}';

revoke all on finance.chart_of_accounts_template,
finance.tax_rates_template,
finance.cost_centers_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on finance.chart_of_accounts_template,
  finance.tax_rates_template,
  finance.cost_centers_template to "x-admin";

----------------------------------------------------------------
-- Maintenance
--
-- Nothing in a database wakes up on its own. An invoice does not
-- become overdue because time passed; it becomes overdue because
-- something touched it. This is the routine that does the touching —
-- point pg_cron at it, or run it from the SQL editor.
----------------------------------------------------------------
create or replace function finance.run_daily_maintenance (
  out invoices_aged integer,
  out budgets_refreshed integer,
  out periods_opened integer
) language plpgsql security definer
set
  search_path = '' as $$
begin
  -- Touching the row is enough: the BEFORE trigger recomputes status
  -- and days_overdue from the due date and the money.
  with aged as (
    update finance.invoices
    set updated_at = current_timestamp
    where status in ('sent', 'partially_paid', 'overdue')
      and balance_due > 0
      and (
        due_date < current_date
        or days_overdue <> greatest(current_date - due_date, 0)
      )
    returning 1
  )
  select count(*) into invoices_aged from aged;

  perform finance.recalc_budget_actuals ();

  select count(*) into budgets_refreshed from finance.budgets;

  -- A period that has arrived should be open for posting.
  with opened as (
    update finance.fiscal_periods
    set status = 'open'
    where status = 'future'
      and starts_on <= current_date
    returning 1
  )
  select count(*) into periods_opened from opened;

  refresh materialized view concurrently finance.monthly_performance;
end;
$$;

revoke all on function finance.run_daily_maintenance ()
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function finance.run_daily_maintenance () to "x-admin";

----------------------------------------------------------------
-- Audit triggers (INSERT/UPDATE fire AFTER, DELETE must fire BEFORE)
--
-- finance.journal_events is left out: it is already a trail.
----------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'fiscal_periods', 'cost_centers', 'accounts', 'tax_rates', 'exchange_rates',
    'journals', 'journal_lines', 'customers', 'vendors', 'invoices',
    'invoice_lines', 'bills', 'bill_lines', 'payments', 'payment_allocations',
    'bank_accounts', 'bank_transactions', 'expense_claims', 'expense_lines',
    'budgets', 'fixed_assets'
  ]
  loop
    execute format(
      'create trigger audit_finance_%1$s_insert after insert on finance.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
    execute format(
      'create trigger audit_finance_%1$s_update after update on finance.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
    execute format(
      'create trigger audit_finance_%1$s_delete before delete on finance.%1$I for each row execute function supasheet.audit_trigger_function ();',
      t
    );
  end loop;
end;
$$;

create trigger audit_finance_finance_settings_insert
after insert on finance.finance_settings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_finance_settings_update
after update on finance.finance_settings for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
--
-- Recipients are resolved from privileges, not from a hard-coded list
-- of people. "Whoever can approve a claim" is exactly "whoever can
-- update finance.expense_claims", so a change to the grants changes
-- who gets told, with no second place to remember.
----------------------------------------------------------------
create or replace function finance.trg_claim_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if tg_op = 'UPDATE' and new.status is not distinct from old.status then
        return new;
    end if;

    if new.status = 'submitted' then
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('finance', 'expense_claims', 'update'),
            new.claimant_id
        );

        if array_length(v_recipients, 1) is null then
            return new;
        end if;

        perform supasheet.create_notification(
            'finance_claim_submitted',
            'Expense claim to review',
            coalesce(new.claimant_name, 'Someone') || ' submitted ' || new.claim_number
              || ' for ' || new.total_amount || ' ' || new.currency,
            v_recipients,
            jsonb_build_object('claim_id', new.id, 'amount', new.total_amount),
            '/finance/resource/expense_claims/' || new.id::text || '/detail'
        );
    elsif new.status in ('approved', 'rejected', 'reimbursed') and new.claimant_id is not null then
        perform supasheet.create_notification(
            'finance_claim_' || new.status,
            'Your claim was ' || new.status,
            new.claim_number || ' — ' || coalesce(new.rejected_reason, new.title),
            array[new.claimant_id],
            jsonb_build_object('claim_id', new.id, 'status', new.status),
            '/finance/resource/expense_claims/' || new.id::text || '/detail'
        );
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger claim_notify
after insert or update of status on finance.expense_claims for each row
execute function finance.trg_claim_notify ();

create or replace function finance.trg_invoice_overdue_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_customer   text;
begin
    if new.status <> 'overdue' or old.status = 'overdue' then
        return new;
    end if;

    v_recipients := supasheet.get_users_with_table_privilege('finance', 'invoices', 'update');

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    select name into v_customer from finance.customers where id = new.customer_id;

    perform supasheet.create_notification(
        'finance_invoice_overdue',
        'Invoice overdue',
        new.invoice_number || ' for ' || coalesce(v_customer, 'a customer')
          || ' is ' || new.days_overdue || ' day(s) late — ' || new.balance_due || ' outstanding',
        v_recipients,
        jsonb_build_object('invoice_id', new.id, 'balance_due', new.balance_due),
        '/finance/resource/invoices/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger invoice_overdue_notify
after update of status on finance.invoices for each row
execute function finance.trg_invoice_overdue_notify ();

create or replace function finance.trg_bill_approval_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_vendor     text;
begin
    if new.status <> 'awaiting_approval'
       or (tg_op = 'UPDATE' and old.status = 'awaiting_approval') then
        return new;
    end if;

    v_recipients := supasheet.get_users_with_table_privilege('finance', 'bills', 'update');

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    select name into v_vendor from finance.vendors where id = new.vendor_id;

    perform supasheet.create_notification(
        'finance_bill_awaiting_approval',
        'Bill needs approval',
        new.bill_number || ' from ' || coalesce(v_vendor, 'a supplier')
          || ' for ' || new.total || ' ' || new.currency,
        v_recipients,
        jsonb_build_object('bill_id', new.id, 'total', new.total),
        '/finance/resource/bills/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger bill_approval_notify
after insert or update of status on finance.bills for each row
execute function finance.trg_bill_approval_notify ();

create or replace function finance.trg_period_closed_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.status not in ('closed', 'locked') or old.status = new.status then
        return new;
    end if;

    v_recipients := supasheet.get_users_with_table_privilege('finance', 'journals', 'insert');

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'finance_period_closed',
        'Period ' || new.code || ' is ' || new.status,
        'Nothing further can be posted into ' || new.name || '. '
          || new.journal_count || ' journal(s) totalling ' || new.posted_total || ' were posted.',
        v_recipients,
        jsonb_build_object('period_id', new.id, 'status', new.status),
        '/finance/resource/fiscal_periods/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger period_closed_notify
after update of status on finance.fiscal_periods for each row
execute function finance.trg_period_closed_notify ();

create or replace function finance.trg_finance_comments_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.schema_name <> 'finance'
       or new.table_name not in ('journals', 'invoices', 'bills', 'expense_claims', 'budgets') then
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('finance', new.table_name, 'update'),
        new.created_by
    );

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'finance_comment_added',
        'New comment on ' || new.table_name,
        left(new.content, 140),
        v_recipients,
        jsonb_build_object('record_id', new.record_id, 'table_name', new.table_name),
        '/finance/resource/' || new.table_name || '/' || new.record_id::text || '/comment'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists finance_comments_notify on supasheet.comments;

create trigger finance_comments_notify
after insert on supasheet.comments for each row
execute function finance.trg_finance_comments_notify ();

----------------------------------------------------------------
-- Private document storage
--
-- Signed invoices, supplier bills and expense receipts are evidence.
-- They get their own private bucket, and the policies delegate to the
-- same table privileges the rest of the module uses: if your role
-- cannot read finance.invoices, it cannot read the PDF behind one
-- either.
----------------------------------------------------------------
insert into
  storage.buckets (id, name, public)
values
  ('finance-documents', 'finance-documents', false)
on conflict (id) do nothing;

drop policy if exists finance_documents_read on storage.objects;

create policy finance_documents_read on storage.objects for
select
  to authenticated using (
    bucket_id = 'finance-documents'
    and (
      has_table_privilege(current_user, 'finance.invoices', 'select')
      or has_table_privilege(current_user, 'finance.expense_lines', 'select')
    )
  );

drop policy if exists finance_documents_insert on storage.objects;

create policy finance_documents_insert on storage.objects for insert to authenticated
with
  check (
    bucket_id = 'finance-documents'
    and (
      has_table_privilege(current_user, 'finance.invoices', 'insert')
      or has_table_privilege(current_user, 'finance.expense_lines', 'insert')
    )
  );

drop policy if exists finance_documents_update on storage.objects;

create policy finance_documents_update on storage.objects
for update
  to authenticated using (
    bucket_id = 'finance-documents'
    and has_table_privilege(current_user, 'finance.invoices', 'update')
  );

drop policy if exists finance_documents_delete on storage.objects;

create policy finance_documents_delete on storage.objects for delete to authenticated using (
  bucket_id = 'finance-documents'
  and has_table_privilege(current_user, 'finance.invoices', 'delete')
);

----------------------------------------------------------------
-- App configuration
--
-- supasheet.configs is the key-value table the app shell reads. Writes
-- are revoked from every client role by design: values change by
-- migration, which is exactly what this is.
----------------------------------------------------------------
insert into
  supasheet.configs (key, value, description, is_public)
values
  (
    'finance.base_currency',
    '"USD"',
    'Currency every report is presented in',
    true
  ),
  (
    'finance.fiscal_year_start_month',
    '1',
    'Month the fiscal year begins (1 = January)',
    false
  ),
  (
    'finance.default_payment_terms_days',
    '30',
    'Payment terms applied when a customer has none of their own',
    false
  ),
  (
    'finance.receipt_required_over',
    '25',
    'Expense lines above this value must carry a receipt',
    true
  ),
  (
    'finance.close_reminder_day',
    '5',
    'Day of the month the period-close reminder goes out',
    false
  )
on conflict (key) do update
set
  value = excluded.value,
  description = excluded.description,
  is_public = excluded.is_public;

----------------------------------------------------------------
-- Refresh the metadata catalog (materialized views — NOT automatic)
----------------------------------------------------------------
select
  supasheet.refresh_metadata ();
