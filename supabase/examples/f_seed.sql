-- Finance Seeder
-- ================================================================
-- Demo data for the finance (general ledger and working capital)
-- module. Apply supabase/examples/20260804000000_finance.sql first:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260804000000_finance.sql \
--     -f supabase/examples/f_seed.sql
--
-- Volume: 24 monthly fiscal periods, a 42-account chart three levels
-- deep, 7 cost centres, 6 tax rates, 76 exchange rates, 3 bank
-- accounts, 24 customers and 18 vendors, 150 sales invoices and 165
-- supplier bills walked through their whole lifecycle, 283 payments
-- across 278 allocations, 425 bank statement lines, 58 expense claims
-- from six employees, 35 budget lines, 14 fixed assets depreciated
-- month by month, and 750 journals carrying 2,266 lines — every one
-- of them balanced, and every balance in the chart of accounts put
-- there by one of them.
--
-- What that adds up to is meant to hold together, not just look
-- plausible. After this file runs:
--
--   - debits equal credits across the whole ledger, and in every
--     posted journal individually
--   - the balance sheet balances: assets less liabilities less equity
--     equals the profit and loss result, to the cent
--   - the receivables control account equals the open sales invoices
--     less the cash received on account that nobody has applied yet
--   - the payables control account equals the open supplier bills
--   - the fixed asset register agrees with 1500 and 1590
--   - for each bank account, statement balance less ledger balance
--     equals exactly the statement lines still unreconciled
--   - customer and vendor positions equal their own subledgers
--
-- And the three columns no trigger can compute are derived from that
-- history rather than invented, at the bottom of this file:
--
--   - credit_rating tracks how late an account actually pays and how
--     much of its balance is overdue right now
--   - credit_limit is set against the exposure the account has
--     actually run, so the limit bounds the trading rather than
--     trailing it
--   - service_rating reads off how long each supplier's paperwork
--     takes to clear approval, which is the only thing a purchase
--     ledger records about how a supplier behaves
--   - budgets sit either side of the run rate, so the variance report
--     has an over-budget column worth opening
--
-- If a change to this file breaks one of those, the data is wrong
-- rather than merely different.
--
-- WHY THIS FILE WALKS ITS RECORDS
--
-- A ledger is the extreme case of the pattern the other seeders use.
-- Nothing here can be written as final state: an invoice inserted as
-- `paid` would carry a balance nobody paid, no journal behind it, no
-- receipt to reconcile and no customer position. So invoices are
-- drafted, coded, issued (which posts them), then collected against;
-- bills are drafted, approved (which posts them), then paid; claims
-- are submitted, decided and reimbursed; depreciation is run one
-- period at a time in order.
--
-- Everything the dashboards, the aging report and the trial balance
-- show is a consequence of those transitions. The chart of accounts
-- has never been written to directly — every figure in it was put
-- there by a posted journal line.
--
-- Periods are created OPEN so the history can be posted into them,
-- and closed at the end in the order a real close happens: the oldest
-- eighteen months locked, the middle months closed, last month and
-- this month left open for work in progress.
--
-- Dates are relative to `current_date`, so the aging buckets, the
-- twelve-month revenue trend, the cash-flow chart and the period
-- board all have shape whenever this is run.
--
-- Three users are seeded (`on conflict do nothing`, so this is safe
-- alongside supabase/seed.sql and the other examples):
--   b73eb03e-fb7a-424d-84ff-18e2791ce0d1  controller@supasheet.app (x-admin)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0d2  accounts@supasheet.app   (accountant)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0d3  auditor@supasheet.app    (finance-auditor)
--
-- Sign in as accounts@supasheet.app for the DAY-TO-DAY FINANCE seat:
-- invoices to raise, bills to approve, claims to decide, statement
-- lines to match, and a ledger it cannot tamper with.
-- auditor@supasheet.app is the READ-ONLY seat — every report, every
-- balance, and not a single write anywhere in the schema.
-- user1@supasheet.app is an ordinary employee: their own expense
-- claims and nothing else.
--
-- Password for every seeded user: the shared bcrypt hash below.
--
-- Not idempotent beyond the auth rows. Run `npx supabase db reset`
-- to start over.
-- ================================================================
----------------------------------------------------------------
-- Users
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d1',
    'authenticated',
    'authenticated',
    'controller@supasheet.app',
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
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0d1", "email": "controller@supasheet.app", "name": "Diane Okafor", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d2',
    'authenticated',
    'authenticated',
    'accounts@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "accountant"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0d2", "email": "accounts@supasheet.app", "name": "Marcus Feld", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d3',
    'authenticated',
    'authenticated',
    'auditor@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "finance-auditor"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0d3", "email": "auditor@supasheet.app", "name": "Ines Duarte", "email_verified": false, "phone_verified": false}',
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
on conflict do nothing;

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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d1',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d1',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0d1", "email": "controller@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ad1'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d2',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d2',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0d2", "email": "accounts@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ad2'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d3',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d3',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0d3", "email": "auditor@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ad3'
  )
on conflict do nothing;

----------------------------------------------------------------
-- Fiscal periods
--
-- Two years of monthly periods either side of today, all created
-- OPEN. The history below has to be posted into them, and a period
-- that is already closed will not take a journal. They are closed at
-- the bottom of this file, which is also the order a real month-end
-- happens in.
----------------------------------------------------------------
insert into
  finance.fiscal_periods (
    id,
    code,
    name,
    fiscal_year,
    period_number,
    starts_on,
    ends_on,
    status,
    note
  )
select
  (
    'f1000000-0000-0000-0000-' || lpad(
      (
        row_number() over (
          order by
            m
        )
      )::text,
      12,
      '0'
    )
  )::uuid,
  to_char(m, 'YYYY-MM'),
  to_char(m, 'FMMonth YYYY'),
  extract(
    year
    from
      m
  )::integer,
  extract(
    month
    from
      m
  )::integer,
  m::date,
  (m + interval '1 month - 1 day')::date,
  'open',
  case
    when extract(
      month
      from
        m
    ) = 12 then 'Year end — audit pack due'
    else null
  end
from
  generate_series(
    date_trunc('month', current_date) - interval '18 months',
    date_trunc('month', current_date) + interval '5 months',
    interval '1 month'
  ) m;

----------------------------------------------------------------
-- Cost centres
----------------------------------------------------------------
insert into
  finance.cost_centers (
    id,
    parent_id,
    code,
    name,
    description,
    owner_email,
    annual_budget,
    color
  )
values
  (
    'f2000000-0000-0000-0000-000000000001',
    null,
    'ENG',
    'Engineering',
    'Product development and platform',
    'vp.engineering@supasheet.app',
    1450000,
    '#6366f1'
  ),
  (
    'f2000000-0000-0000-0000-000000000002',
    'f2000000-0000-0000-0000-000000000001',
    'ENG-PLAT',
    'Engineering — Platform',
    'Core services and infrastructure',
    'platform@supasheet.app',
    780000,
    '#818cf8'
  ),
  (
    'f2000000-0000-0000-0000-000000000003',
    'f2000000-0000-0000-0000-000000000001',
    'ENG-APP',
    'Engineering — Applications',
    'Customer-facing product teams',
    'apps@supasheet.app',
    670000,
    '#a5b4fc'
  ),
  (
    'f2000000-0000-0000-0000-000000000004',
    null,
    'SALES',
    'Sales',
    'New business and account management',
    'vp.sales@supasheet.app',
    920000,
    '#10b981'
  ),
  (
    'f2000000-0000-0000-0000-000000000005',
    null,
    'MKT',
    'Marketing',
    'Demand generation, brand and events',
    'marketing@supasheet.app',
    410000,
    '#f59e0b'
  ),
  (
    'f2000000-0000-0000-0000-000000000006',
    null,
    'CS',
    'Customer Success',
    'Onboarding, support and renewals',
    'success@supasheet.app',
    355000,
    '#06b6d4'
  ),
  (
    'f2000000-0000-0000-0000-000000000007',
    null,
    'GA',
    'General and Administrative',
    'Finance, legal, people and facilities',
    'controller@supasheet.app',
    520000,
    '#64748b'
  );

----------------------------------------------------------------
-- Chart of accounts
--
-- Three levels: five type headers, then postable accounts beneath
-- them. Opening balances are all zero — the balances the reports show
-- are put there by posted journals, starting with the opening entry
-- further down. Nothing writes to this table directly again.
----------------------------------------------------------------
insert into
  finance.accounts (
    id,
    parent_id,
    code,
    name,
    description,
    account_type,
    normal_balance,
    is_postable,
    is_bank_account,
    color
  )
values
  (
    'f3000000-0000-0000-0000-000000000001',
    null,
    '1',
    'Assets',
    'Everything the business owns',
    'asset',
    'debit',
    false,
    false,
    '#3b82f6'
  ),
  (
    'f3000000-0000-0000-0000-000000000002',
    'f3000000-0000-0000-0000-000000000001',
    '1010',
    'Bank — Operating',
    'The account the business runs on',
    'asset',
    'debit',
    true,
    true,
    '#3b82f6'
  ),
  (
    'f3000000-0000-0000-0000-000000000003',
    'f3000000-0000-0000-0000-000000000001',
    '1020',
    'Bank — Payroll',
    'Funded monthly, drawn down on pay day',
    'asset',
    'debit',
    true,
    true,
    '#3b82f6'
  ),
  (
    'f3000000-0000-0000-0000-000000000004',
    'f3000000-0000-0000-0000-000000000001',
    '1030',
    'Bank — Reserve',
    'Held against the tax bill',
    'asset',
    'debit',
    true,
    true,
    '#3b82f6'
  ),
  (
    'f3000000-0000-0000-0000-000000000005',
    'f3000000-0000-0000-0000-000000000001',
    '1100',
    'Accounts Receivable',
    'Invoiced and not yet collected',
    'asset',
    'debit',
    true,
    false,
    '#3b82f6'
  ),
  (
    'f3000000-0000-0000-0000-000000000006',
    'f3000000-0000-0000-0000-000000000001',
    '1200',
    'Prepayments',
    'Paid ahead of the period it belongs to',
    'asset',
    'debit',
    true,
    false,
    '#3b82f6'
  ),
  (
    'f3000000-0000-0000-0000-000000000007',
    'f3000000-0000-0000-0000-000000000001',
    '1500',
    'Fixed Assets — Cost',
    'What the asset register cost',
    'asset',
    'debit',
    true,
    false,
    '#3b82f6'
  ),
  (
    'f3000000-0000-0000-0000-000000000008',
    'f3000000-0000-0000-0000-000000000001',
    '1590',
    'Accumulated Depreciation',
    'Contra-asset against the register',
    'asset',
    'credit',
    true,
    false,
    '#3b82f6'
  ),
  (
    'f3000000-0000-0000-0000-000000000009',
    null,
    '2',
    'Liabilities',
    'Everything the business owes',
    'liability',
    'credit',
    false,
    false,
    '#f97316'
  ),
  (
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000009',
    '2100',
    'Accounts Payable',
    'Billed by suppliers and not yet paid',
    'liability',
    'credit',
    true,
    false,
    '#f97316'
  ),
  (
    'f3000000-0000-0000-0000-000000000011',
    'f3000000-0000-0000-0000-000000000009',
    '2150',
    'Expense Reimbursements Payable',
    'Owed back to staff',
    'liability',
    'credit',
    true,
    false,
    '#f97316'
  ),
  (
    'f3000000-0000-0000-0000-000000000012',
    'f3000000-0000-0000-0000-000000000009',
    '2200',
    'Sales Tax Payable',
    'Tax collected on sales',
    'liability',
    'credit',
    true,
    false,
    '#f97316'
  ),
  (
    'f3000000-0000-0000-0000-000000000013',
    'f3000000-0000-0000-0000-000000000009',
    '2210',
    'Input Tax Recoverable',
    'Tax paid on purchases',
    'liability',
    'debit',
    true,
    false,
    '#f97316'
  ),
  (
    'f3000000-0000-0000-0000-000000000014',
    'f3000000-0000-0000-0000-000000000009',
    '2300',
    'Accruals',
    'Incurred but not yet invoiced',
    'liability',
    'credit',
    true,
    false,
    '#f97316'
  ),
  (
    'f3000000-0000-0000-0000-000000000015',
    'f3000000-0000-0000-0000-000000000009',
    '2400',
    'Deferred Revenue',
    'Billed ahead of delivery',
    'liability',
    'credit',
    true,
    false,
    '#f97316'
  ),
  (
    'f3000000-0000-0000-0000-000000000016',
    null,
    '3',
    'Equity',
    'What the business is worth to its owners',
    'equity',
    'credit',
    false,
    false,
    '#8b5cf6'
  ),
  (
    'f3000000-0000-0000-0000-000000000017',
    'f3000000-0000-0000-0000-000000000016',
    '3000',
    'Share Capital',
    'Paid-in capital',
    'equity',
    'credit',
    true,
    false,
    '#8b5cf6'
  ),
  (
    'f3000000-0000-0000-0000-000000000018',
    'f3000000-0000-0000-0000-000000000016',
    '3900',
    'Retained Earnings',
    'Accumulated result carried forward',
    'equity',
    'credit',
    true,
    false,
    '#8b5cf6'
  ),
  (
    'f3000000-0000-0000-0000-000000000019',
    null,
    '4',
    'Revenue',
    'What the business sells',
    'revenue',
    'credit',
    false,
    false,
    '#10b981'
  ),
  (
    'f3000000-0000-0000-0000-000000000020',
    'f3000000-0000-0000-0000-000000000019',
    '4000',
    'Subscription Revenue',
    'Recurring platform licences',
    'revenue',
    'credit',
    true,
    false,
    '#10b981'
  ),
  (
    'f3000000-0000-0000-0000-000000000021',
    'f3000000-0000-0000-0000-000000000019',
    '4100',
    'Services Revenue',
    'Implementation and consulting',
    'revenue',
    'credit',
    true,
    false,
    '#10b981'
  ),
  (
    'f3000000-0000-0000-0000-000000000022',
    'f3000000-0000-0000-0000-000000000019',
    '4200',
    'Support Revenue',
    'Retainers and training',
    'revenue',
    'credit',
    true,
    false,
    '#10b981'
  ),
  (
    'f3000000-0000-0000-0000-000000000023',
    'f3000000-0000-0000-0000-000000000019',
    '4900',
    'Other Income',
    'Anything that is not the main trade',
    'revenue',
    'credit',
    true,
    false,
    '#10b981'
  ),
  (
    'f3000000-0000-0000-0000-000000000024',
    null,
    '5',
    'Cost of Sales',
    'The direct cost of delivering revenue',
    'expense',
    'debit',
    false,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000025',
    'f3000000-0000-0000-0000-000000000024',
    '5000',
    'Hosting and Infrastructure',
    'Cloud, CDN and data transfer',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000026',
    'f3000000-0000-0000-0000-000000000024',
    '5100',
    'Third-party Licences',
    'Software resold or embedded',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000027',
    'f3000000-0000-0000-0000-000000000024',
    '5200',
    'Delivery Payroll',
    'Consultants on billable work',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000028',
    null,
    '6',
    'Operating Expenses',
    'The cost of running the business',
    'expense',
    'debit',
    false,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000029',
    'f3000000-0000-0000-0000-000000000028',
    '6000',
    'Salaries and Wages',
    'Payroll',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000030',
    'f3000000-0000-0000-0000-000000000028',
    '6010',
    'Employer Taxes and Benefits',
    'On-costs',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000031',
    'f3000000-0000-0000-0000-000000000028',
    '6100',
    'Travel',
    'Getting there',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000032',
    'f3000000-0000-0000-0000-000000000028',
    '6110',
    'Accommodation',
    'Staying there',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000033',
    'f3000000-0000-0000-0000-000000000028',
    '6120',
    'Meals and Entertainment',
    'Client and team hospitality',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000034',
    'f3000000-0000-0000-0000-000000000028',
    '6200',
    'Software and Subscriptions',
    'The tools the business runs on',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000035',
    'f3000000-0000-0000-0000-000000000028',
    '6210',
    'Hardware',
    'Laptops, monitors and peripherals',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000036',
    'f3000000-0000-0000-0000-000000000028',
    '6300',
    'Marketing',
    'Demand generation',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000037',
    'f3000000-0000-0000-0000-000000000028',
    '6310',
    'Events and Conferences',
    'Stands, sponsorships and tickets',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000038',
    'f3000000-0000-0000-0000-000000000028',
    '6400',
    'Professional Fees',
    'Legal, audit and advisory',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000039',
    'f3000000-0000-0000-0000-000000000028',
    '6500',
    'Depreciation',
    'Wear on the asset register',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000040',
    'f3000000-0000-0000-0000-000000000028',
    '6600',
    'Rent and Facilities',
    'Offices and everything in them',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000041',
    'f3000000-0000-0000-0000-000000000028',
    '6700',
    'Training',
    'Courses, certifications and books',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  ),
  (
    'f3000000-0000-0000-0000-000000000042',
    'f3000000-0000-0000-0000-000000000028',
    '6900',
    'Other Operating Costs',
    'Everything else',
    'expense',
    'debit',
    true,
    false,
    '#ef4444'
  );

----------------------------------------------------------------
-- Tax rates
----------------------------------------------------------------
insert into
  finance.tax_rates (
    id,
    code,
    name,
    rate,
    account_id,
    input_account_id,
    is_recoverable,
    country,
    effective_from
  )
values
  (
    'f4000000-0000-0000-0000-000000000001',
    'STD-20',
    'UK standard rate 20%',
    20.0,
    'f3000000-0000-0000-0000-000000000012',
    'f3000000-0000-0000-0000-000000000013',
    true,
    'GB',
    current_date + -900
  ),
  (
    'f4000000-0000-0000-0000-000000000002',
    'RED-5',
    'UK reduced rate 5%',
    5.0,
    'f3000000-0000-0000-0000-000000000012',
    'f3000000-0000-0000-0000-000000000013',
    true,
    'GB',
    current_date + -900
  ),
  (
    'f4000000-0000-0000-0000-000000000003',
    'ZERO',
    'Zero rated',
    0.0,
    'f3000000-0000-0000-0000-000000000012',
    'f3000000-0000-0000-0000-000000000013',
    true,
    'GB',
    current_date + -900
  ),
  (
    'f4000000-0000-0000-0000-000000000004',
    'EXEMPT',
    'Exempt from tax',
    0.0,
    null,
    null,
    false,
    'GB',
    current_date + -900
  ),
  (
    'f4000000-0000-0000-0000-000000000005',
    'EU-21',
    'EU standard rate 21%',
    21.0,
    'f3000000-0000-0000-0000-000000000012',
    'f3000000-0000-0000-0000-000000000013',
    true,
    'NL',
    current_date + -900
  ),
  (
    'f4000000-0000-0000-0000-000000000006',
    'US-NONE',
    'No sales tax',
    0.0,
    null,
    null,
    false,
    'US',
    current_date + -900
  );

----------------------------------------------------------------
-- Exchange rates
--
-- Month-end rates against USD for the currencies the customer book
-- actually uses, wandering by a couple of percent each month rather
-- than sitting flat.
----------------------------------------------------------------
insert into
  finance.exchange_rates (
    base_currency,
    quote_currency,
    rate,
    rate_date,
    source
  )
select
  'USD',
  q.code,
  round(
    (
      q.base + (
        (
          abs(hashtext (q.code || to_char(m, 'YYYY-MM'))) % 900 - 450
        )::numeric / 10000
      )
    )::numeric,
    6
  ),
  (m + interval '1 month - 1 day')::date,
  'ecb'
from
  generate_series(
    date_trunc('month', current_date) - interval '18 months',
    date_trunc('month', current_date),
    interval '1 month'
  ) m
  cross join (
    values
      ('EUR', 0.9210),
      ('GBP', 0.7880),
      ('CAD', 1.3650),
      ('AUD', 1.5220)
  ) as q (code, base);

----------------------------------------------------------------
-- Bank accounts
--
-- Opening balances are zero here too. The cash the dashboard shows
-- arrives through the opening journal and every receipt and payment
-- after it.
----------------------------------------------------------------
insert into
  finance.bank_accounts (
    id,
    code,
    name,
    bank_name,
    account_number,
    iban,
    swift,
    currency,
    gl_account_id,
    opening_balance,
    is_active,
    is_primary
  )
values
  (
    'f5000000-0000-0000-0000-000000000001',
    'OPS',
    'Operating Account',
    'Northgate Commercial',
    '****4417',
    'GB29NWBK60161331926819',
    'NWBKGB2L',
    'USD',
    'f3000000-0000-0000-0000-000000000002',
    0,
    true,
    true
  ),
  (
    'f5000000-0000-0000-0000-000000000002',
    'PAY',
    'Payroll Account',
    'Northgate Commercial',
    '****4418',
    'GB29NWBK60161331926820',
    'NWBKGB2L',
    'USD',
    'f3000000-0000-0000-0000-000000000003',
    0,
    true,
    false
  ),
  (
    'f5000000-0000-0000-0000-000000000003',
    'RES',
    'Tax Reserve',
    'Meridian Savings',
    '****9902',
    'GB71MERI40051512345678',
    'MERIGB22',
    'USD',
    'f3000000-0000-0000-0000-000000000004',
    0,
    true,
    false
  );

----------------------------------------------------------------
-- Finance settings (singleton)
--
-- Every posting routine in the module reads its control accounts from
-- this row. Without it, invoices and bills would still be raised and
-- still be correct — they simply would not reach the ledger.
----------------------------------------------------------------
insert into
  finance.finance_settings (
    company_name,
    base_currency,
    fiscal_year_start_month,
    default_payment_terms_days,
    default_tax_rate_id,
    receivable_account_id,
    payable_account_id,
    bank_account_id,
    expense_clearing_account_id,
    retained_earnings_account_id,
    auto_post_invoices,
    require_receipt_over,
    overdue_reminder_days,
    timezone
  )
values
  (
    'Supasheet Software Ltd',
    'USD',
    1,
    30,
    'f4000000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000005',
    'f3000000-0000-0000-0000-000000000010',
    'f5000000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000011',
    'f3000000-0000-0000-0000-000000000018',
    true,
    25,
    7,
    'Europe/London'
  );

----------------------------------------------------------------
-- Customers
--
-- Terms vary because collection behaviour has to vary: the aging
-- report is only interesting if fourteen-day and sixty-day accounts
-- sit in it side by side. Every position column on this table
-- (invoiced, collected, outstanding, overdue, oldest due date) is
-- left at its default — a trigger fills them in as the invoices
-- below are raised and settled.
----------------------------------------------------------------
insert into
  finance.customers (
    id,
    code,
    name,
    legal_name,
    email,
    phone,
    website,
    tax_number,
    status,
    payment_terms_days,
    credit_limit,
    currency,
    country,
    billing_address,
    receivable_account_id,
    notes
  )
values
  (
    'f6000000-0000-0000-0000-000000000001',
    'C-1001',
    'Northwind Logistics',
    'Northwind Logistics Ltd',
    'ap@northwind-logistics.com',
    '+44 20 7946 0101',
    'https://northwind-logistics.com',
    'GB418273465',
    'active',
    30,
    150000,
    'USD',
    'GB',
    '12 Prospect Wharf, London E1W 3TJ',
    'f3000000-0000-0000-0000-000000000005',
    'Three-year platform contract, renews in March.'
  ),
  (
    'f6000000-0000-0000-0000-000000000002',
    'C-1002',
    'Helios Manufacturing',
    'Helios Manufacturing GmbH',
    'buchhaltung@helios-mfg.de',
    '+49 89 1234 5670',
    'https://helios-mfg.de',
    'DE811907980',
    'active',
    45,
    220000,
    'USD',
    'DE',
    'Landsberger Str. 44, 80339 Munich',
    'f3000000-0000-0000-0000-000000000005',
    'Pays reliably but always on day 45.'
  ),
  (
    'f6000000-0000-0000-0000-000000000003',
    'C-1003',
    'Cascade Health',
    'Cascade Health Systems Inc',
    'payables@cascadehealth.com',
    '+1 206 555 0142',
    'https://cascadehealth.com',
    'US-47-2938471',
    'active',
    30,
    300000,
    'USD',
    'US',
    '1201 Third Ave, Seattle WA 98101',
    'f3000000-0000-0000-0000-000000000005',
    'Largest account. Procurement requires a PO on every invoice.'
  ),
  (
    'f6000000-0000-0000-0000-000000000004',
    'C-1004',
    'Brightline Retail',
    'Brightline Retail plc',
    'finance@brightlineretail.co.uk',
    '+44 161 496 0202',
    'https://brightlineretail.co.uk',
    'GB552817364',
    'active',
    30,
    90000,
    'USD',
    'GB',
    'Piccadilly Place, Manchester M1 3BN',
    'f3000000-0000-0000-0000-000000000005',
    null
  ),
  (
    'f6000000-0000-0000-0000-000000000005',
    'C-1005',
    'Vertex Analytics',
    'Vertex Analytics BV',
    'crediteuren@vertex.nl',
    '+31 20 794 0303',
    'https://vertex-analytics.nl',
    'NL857382910B01',
    'active',
    30,
    120000,
    'USD',
    'NL',
    'Herengracht 182, 1016 BR Amsterdam',
    'f3000000-0000-0000-0000-000000000005',
    'Expanding seats every quarter.'
  ),
  (
    'f6000000-0000-0000-0000-000000000006',
    'C-1006',
    'Ironwood Construction',
    'Ironwood Construction LLC',
    'ap@ironwoodco.com',
    '+1 312 555 0177',
    'https://ironwoodco.com',
    'US-36-4471829',
    'active',
    60,
    80000,
    'USD',
    'US',
    '233 S Wacker Dr, Chicago IL 60606',
    'f3000000-0000-0000-0000-000000000005',
    'Sixty-day terms negotiated at signature.'
  ),
  (
    'f6000000-0000-0000-0000-000000000007',
    'C-1007',
    'Solstice Media',
    'Solstice Media Group',
    'accounts@solsticemedia.com',
    '+1 646 555 0188',
    'https://solsticemedia.com',
    'US-13-5561209',
    'active',
    30,
    60000,
    'USD',
    'US',
    '75 Varick St, New York NY 10013',
    'f3000000-0000-0000-0000-000000000005',
    null
  ),
  (
    'f6000000-0000-0000-0000-000000000008',
    'C-1008',
    'Kestrel Financial',
    'Kestrel Financial Services Ltd',
    'ap@kestrelfin.co.uk',
    '+44 20 7946 0404',
    'https://kestrelfin.co.uk',
    'GB663928471',
    'active',
    30,
    175000,
    'USD',
    'GB',
    '30 Fenchurch St, London EC3M 3BD',
    'f3000000-0000-0000-0000-000000000005',
    'Security review every renewal.'
  ),
  (
    'f6000000-0000-0000-0000-000000000009',
    'C-1009',
    'Aurora Biotech',
    'Aurora Biotech SA',
    'comptabilite@aurorabio.fr',
    '+33 1 70 39 0505',
    'https://aurorabio.fr',
    'FR40123456824',
    'active',
    45,
    140000,
    'USD',
    'FR',
    '18 Rue de la Paix, 75002 Paris',
    'f3000000-0000-0000-0000-000000000005',
    null
  ),
  (
    'f6000000-0000-0000-0000-000000000010',
    'C-1010',
    'Redwood Education',
    'Redwood Education Trust',
    'finance@redwoodedu.org',
    '+1 415 555 0199',
    'https://redwoodedu.org',
    'US-94-3012876',
    'active',
    30,
    45000,
    'USD',
    'US',
    '501 Mission St, San Francisco CA 94105',
    'f3000000-0000-0000-0000-000000000005',
    'Non-profit pricing, annual billing only.'
  ),
  (
    'f6000000-0000-0000-0000-000000000011',
    'C-1011',
    'Meridian Freight',
    'Meridian Freight Pty Ltd',
    'accounts@meridianfreight.com.au',
    '+61 2 8006 0606',
    'https://meridianfreight.com.au',
    'AU53004085616',
    'active',
    30,
    70000,
    'USD',
    'AU',
    '1 Farrer Pl, Sydney NSW 2000',
    'f3000000-0000-0000-0000-000000000005',
    null
  ),
  (
    'f6000000-0000-0000-0000-000000000012',
    'C-1012',
    'Halcyon Hotels',
    'Halcyon Hospitality Ltd',
    'ap@halcyonhotels.com',
    '+44 131 496 0707',
    'https://halcyonhotels.com',
    'GB774019283',
    'on_hold',
    30,
    55000,
    'USD',
    'GB',
    '20 Princes St, Edinburgh EH2 2AN',
    'f3000000-0000-0000-0000-000000000005',
    'On hold pending a disputed implementation invoice.'
  ),
  (
    'f6000000-0000-0000-0000-000000000013',
    'C-1013',
    'Quantum Robotics',
    'Quantum Robotics Inc',
    'payables@quantumrobotics.com',
    '+1 617 555 0210',
    'https://quantumrobotics.com',
    'US-04-3918274',
    'active',
    30,
    110000,
    'USD',
    'US',
    '245 Main St, Cambridge MA 02142',
    'f3000000-0000-0000-0000-000000000005',
    null
  ),
  (
    'f6000000-0000-0000-0000-000000000014',
    'C-1014',
    'Silverbirch Legal',
    'Silverbirch Legal LLP',
    'billing@silverbirchlegal.co.uk',
    '+44 20 7946 0811',
    'https://silverbirchlegal.co.uk',
    'GB889201736',
    'active',
    14,
    35000,
    'USD',
    'GB',
    '1 New Fetter Ln, London EC4A 1AN',
    'f3000000-0000-0000-0000-000000000005',
    'Fourteen-day terms; pays by return.'
  ),
  (
    'f6000000-0000-0000-0000-000000000015',
    'C-1015',
    'Pinnacle Energy',
    'Pinnacle Energy Corp',
    'ap@pinnacle-energy.com',
    '+1 713 555 0222',
    'https://pinnacle-energy.com',
    'US-76-2019384',
    'active',
    45,
    260000,
    'USD',
    'US',
    '1000 Louisiana St, Houston TX 77002',
    'f3000000-0000-0000-0000-000000000005',
    'Invoices route through a portal; expect delays.'
  ),
  (
    'f6000000-0000-0000-0000-000000000016',
    'C-1016',
    'Lakeview Insurance',
    'Lakeview Insurance Group',
    'accountspayable@lakeviewins.com',
    '+1 416 555 0233',
    'https://lakeviewins.ca',
    'CA-8472910RT',
    'active',
    30,
    95000,
    'USD',
    'CA',
    '200 Bay St, Toronto ON M5J 2J2',
    'f3000000-0000-0000-0000-000000000005',
    null
  ),
  (
    'f6000000-0000-0000-0000-000000000017',
    'C-1017',
    'Copperfield Foods',
    'Copperfield Foods Ltd',
    'finance@copperfieldfoods.co.uk',
    '+44 117 496 0944',
    'https://copperfieldfoods.co.uk',
    'GB901827364',
    'active',
    30,
    40000,
    'USD',
    'GB',
    'Temple Quay, Bristol BS1 6EG',
    'f3000000-0000-0000-0000-000000000005',
    null
  ),
  (
    'f6000000-0000-0000-0000-000000000018',
    'C-1018',
    'Nimbus Telecom',
    'Nimbus Telecom AB',
    'leverantorsfakturor@nimbus.se',
    '+46 8 505 0155',
    'https://nimbustelecom.se',
    'SE556677889901',
    'active',
    30,
    130000,
    'USD',
    'SE',
    'Sveavagen 44, 111 34 Stockholm',
    'f3000000-0000-0000-0000-000000000005',
    'Consolidated monthly billing.'
  ),
  (
    'f6000000-0000-0000-0000-000000000019',
    'C-1019',
    'Granite Mining',
    'Granite Mining Holdings',
    'ap@granitemining.com',
    '+61 8 6102 0166',
    'https://granitemining.com',
    'AU61009876543',
    'active',
    60,
    150000,
    'USD',
    'AU',
    '108 St Georges Tce, Perth WA 6000',
    'f3000000-0000-0000-0000-000000000005',
    null
  ),
  (
    'f6000000-0000-0000-0000-000000000020',
    'C-1020',
    'Fairmont Property',
    'Fairmont Property Partners',
    'accounts@fairmontproperty.co.uk',
    '+44 20 7946 1077',
    'https://fairmontproperty.co.uk',
    'GB112938475',
    'active',
    30,
    65000,
    'USD',
    'GB',
    '8 Bishopsgate, London EC2N 4BQ',
    'f3000000-0000-0000-0000-000000000005',
    null
  ),
  (
    'f6000000-0000-0000-0000-000000000021',
    'C-1021',
    'Sable Automotive',
    'Sable Automotive SpA',
    'fornitori@sableauto.it',
    '+39 02 8088 0188',
    'https://sableauto.it',
    'IT12345678903',
    'active',
    45,
    105000,
    'USD',
    'IT',
    'Via Torino 12, 20123 Milan',
    'f3000000-0000-0000-0000-000000000005',
    null
  ),
  (
    'f6000000-0000-0000-0000-000000000022',
    'C-1022',
    'Everest Consulting',
    'Everest Consulting Partners',
    'ap@everestconsulting.com',
    '+1 303 555 0299',
    'https://everestconsulting.com',
    'US-84-1029384',
    'active',
    30,
    50000,
    'USD',
    'US',
    '1601 Wewatta St, Denver CO 80202',
    'f3000000-0000-0000-0000-000000000005',
    'Reseller — margin agreed at 15%.'
  ),
  (
    'f6000000-0000-0000-0000-000000000023',
    'C-1023',
    'Thornbury Publishing',
    'Thornbury Publishing Ltd',
    'finance@thornburypublishing.co.uk',
    '+44 1865 496 0311',
    'https://thornburypublishing.co.uk',
    'GB223948576',
    'closed',
    30,
    20000,
    'USD',
    'GB',
    'Osney Mead, Oxford OX2 0EW',
    'f3000000-0000-0000-0000-000000000005',
    'Churned at renewal; kept for the audit trail.'
  ),
  (
    'f6000000-0000-0000-0000-000000000024',
    'C-1024',
    'Beacon Charities',
    'Beacon Charitable Foundation',
    'payments@beaconcharities.org',
    '+1 202 555 0322',
    'https://beaconcharities.org',
    'US-52-8817263',
    'active',
    30,
    25000,
    'USD',
    'US',
    '1100 G St NW, Washington DC 20005',
    'f3000000-0000-0000-0000-000000000005',
    'Charity rate; billed annually in advance.'
  );

----------------------------------------------------------------
-- Vendors
----------------------------------------------------------------
insert into
  finance.vendors (
    id,
    code,
    name,
    email,
    phone,
    website,
    tax_number,
    is_active,
    payment_terms_days,
    currency,
    country,
    payable_account_id,
    default_expense_account_id,
    notes
  )
values
  (
    'f7000000-0000-0000-0000-000000000001',
    'V-2001',
    'Cloudspan Infrastructure',
    'billing@cloudspan.com',
    '+1 206 555 0410',
    'https://cloudspan.com',
    'US-91-2837465',
    true,
    30,
    'USD',
    'US',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000025',
    'Primary cloud provider. Billed monthly in arrears.'
  ),
  (
    'f7000000-0000-0000-0000-000000000002',
    'V-2002',
    'Northgate Commercial Bank',
    'servicing@northgatebank.co.uk',
    '+44 20 7946 0501',
    'https://northgatebank.co.uk',
    'GB334857291',
    true,
    0,
    'USD',
    'GB',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000042',
    'Bank charges are direct debited.'
  ),
  (
    'f7000000-0000-0000-0000-000000000003',
    'V-2003',
    'Bellweather Legal',
    'accounts@bellweatherlegal.co.uk',
    '+44 20 7946 0512',
    'https://bellweatherlegal.co.uk',
    'GB445968302',
    true,
    30,
    'USD',
    'GB',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000038',
    'Retained for commercial contracts.'
  ),
  (
    'f7000000-0000-0000-0000-000000000004',
    'V-2004',
    'Ashcroft Audit',
    'billing@ashcroftaudit.com',
    '+44 20 7946 0523',
    'https://ashcroftaudit.com',
    'GB556079413',
    true,
    45,
    'USD',
    'GB',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000038',
    'Statutory audit, billed in three stages.'
  ),
  (
    'f7000000-0000-0000-0000-000000000005',
    'V-2005',
    'Pixelforge Design',
    'hello@pixelforge.studio',
    '+1 415 555 0534',
    'https://pixelforge.studio',
    'US-27-9384756',
    true,
    30,
    'USD',
    'US',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000036',
    null
  ),
  (
    'f7000000-0000-0000-0000-000000000006',
    'V-2006',
    'Atlas Office Group',
    'ar@atlasoffice.co.uk',
    '+44 20 7946 0545',
    'https://atlasoffice.co.uk',
    'GB667180524',
    true,
    30,
    'USD',
    'GB',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000040',
    'Landlord for the London office.'
  ),
  (
    'f7000000-0000-0000-0000-000000000007',
    'V-2007',
    'Brightwire Telecom',
    'billing@brightwire.com',
    '+1 312 555 0556',
    'https://brightwire.com',
    'US-38-1029384',
    true,
    30,
    'USD',
    'US',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000042',
    null
  ),
  (
    'f7000000-0000-0000-0000-000000000008',
    'V-2008',
    'Sentinel Security',
    'invoices@sentinelsec.com',
    '+1 703 555 0567',
    'https://sentinelsec.com',
    'US-54-2938475',
    true,
    30,
    'USD',
    'US',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000034',
    'Annual penetration test and monitoring.'
  ),
  (
    'f7000000-0000-0000-0000-000000000009',
    'V-2009',
    'Kirkwall Hardware',
    'sales@kirkwallhardware.co.uk',
    '+44 141 496 0578',
    'https://kirkwallhardware.co.uk',
    'GB778291635',
    true,
    14,
    'USD',
    'GB',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000035',
    'Laptops and monitors for new starters.'
  ),
  (
    'f7000000-0000-0000-0000-000000000010',
    'V-2010',
    'Meridian Travel Management',
    'accounts@meridiantravel.com',
    '+44 20 7946 0589',
    'https://meridiantravel.com',
    'GB889302746',
    true,
    14,
    'USD',
    'GB',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000031',
    'Books all company travel; billed fortnightly.'
  ),
  (
    'f7000000-0000-0000-0000-000000000011',
    'V-2011',
    'Foundry Recruitment',
    'finance@foundryrecruit.com',
    '+44 20 7946 0590',
    'https://foundryrecruit.com',
    'GB990413857',
    true,
    30,
    'USD',
    'GB',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000038',
    'Contingency fees on engineering hires.'
  ),
  (
    'f7000000-0000-0000-0000-000000000012',
    'V-2012',
    'Datastream Licensing',
    'ar@datastream.io',
    '+1 512 555 0601',
    'https://datastream.io',
    'US-65-3847562',
    true,
    30,
    'USD',
    'US',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000026',
    'Embedded analytics licence, billed quarterly.'
  ),
  (
    'f7000000-0000-0000-0000-000000000013',
    'V-2013',
    'Halewood Print',
    'accounts@halewoodprint.co.uk',
    '+44 151 496 0612',
    'https://halewoodprint.co.uk',
    'GB101524968',
    true,
    30,
    'USD',
    'GB',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000037',
    null
  ),
  (
    'f7000000-0000-0000-0000-000000000014',
    'V-2014',
    'Summit Conferences',
    'billing@summitconf.com',
    '+1 702 555 0623',
    'https://summitconf.com',
    'US-76-4958673',
    true,
    45,
    'USD',
    'US',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000037',
    'Annual user conference stand and sponsorship.'
  ),
  (
    'f7000000-0000-0000-0000-000000000015',
    'V-2015',
    'Corvus Insurance Brokers',
    'accounts@corvusbrokers.co.uk',
    '+44 20 7946 0634',
    'https://corvusbrokers.co.uk',
    'GB212635079',
    true,
    30,
    'USD',
    'GB',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000042',
    null
  ),
  (
    'f7000000-0000-0000-0000-000000000016',
    'V-2016',
    'Lantern Learning',
    'invoices@lanternlearning.com',
    '+1 617 555 0645',
    'https://lanternlearning.com',
    'US-87-5069784',
    true,
    30,
    'USD',
    'US',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000041',
    'Engineering training subscriptions.'
  ),
  (
    'f7000000-0000-0000-0000-000000000017',
    'V-2017',
    'Verity Payroll Services',
    'billing@veritypayroll.co.uk',
    '+44 20 7946 0656',
    'https://veritypayroll.co.uk',
    'GB323746180',
    true,
    14,
    'USD',
    'GB',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000030',
    'Runs payroll and files the returns.'
  ),
  (
    'f7000000-0000-0000-0000-000000000018',
    'V-2018',
    'Oldgate Facilities',
    'ar@oldgatefm.co.uk',
    '+44 20 7946 0667',
    'https://oldgatefm.co.uk',
    'GB434857291',
    false,
    30,
    'USD',
    'GB',
    'f3000000-0000-0000-0000-000000000010',
    'f3000000-0000-0000-0000-000000000040',
    'Replaced by Atlas Office Group last year.'
  );

----------------------------------------------------------------
-- Opening balances
--
-- The one journal that is allowed to appear from nowhere. Everything
-- after it has a document behind it.
----------------------------------------------------------------
do $$
declare
  v_journal uuid;
  v_date date;
begin
  v_date := (date_trunc('month', current_date) - interval '18 months')::date;

  insert into finance.journals (id, entry_date, source, memo, reference)
  values (
    'fe000000-0000-0000-0000-000000000001',
    v_date,
    'opening_balance',
    'Opening balances brought forward at go-live',
    'OB-0001'
  )
  returning id into v_journal;

  insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
  values
    (v_journal, 'f3000000-0000-0000-0000-000000000002', 1, 'Opening cash — operating', 640000, 0),
    (v_journal, 'f3000000-0000-0000-0000-000000000003', 2, 'Opening cash — payroll', 95000, 0),
    (v_journal, 'f3000000-0000-0000-0000-000000000004', 3, 'Opening cash — tax reserve', 180000, 0),
    (v_journal, 'f3000000-0000-0000-0000-000000000006', 4, 'Prepaid insurance and licences', 42000, 0),
    (v_journal, 'f3000000-0000-0000-0000-000000000017', 5, 'Share capital', 0, 750000),
    (v_journal, 'f3000000-0000-0000-0000-000000000018', 6, 'Retained earnings brought forward', 0, 207000);

  update finance.journals set status = 'posted' where id = v_journal;
end;
$$;

----------------------------------------------------------------
-- Sales invoices
--
-- Each one is drafted, coded line by line, then ISSUED — and issuing
-- is what posts it, because finance_settings.auto_post_invoices is
-- on. Nothing here sets a status directly except `void`, which is a
-- decision rather than a consequence.
--
-- The collection outcome is chosen from the invoice's AGE, not from
-- its position in the loop. Old invoices are mostly settled, recent
-- ones mostly are not, and the ones in between are the interesting
-- middle — which is what makes the aging report worth looking at.
----------------------------------------------------------------
do $$
declare
  v_desc text[] := array[
    'Platform subscription — annual',
    'Platform subscription — monthly',
    'Additional user seats',
    'Implementation services',
    'Data migration',
    'Custom integration',
    'Premium support retainer',
    'Onsite training workshop'
  ];
  v_codes text[] := array['4000', '4000', '4000', '4100', '4100', '4100', '4200', '4200'];
  v_price numeric[] := array[14400, 1200, 45, 1450, 8500, 11000, 1800, 2400];
  v_qtymax integer[] := array[3, 12, 120, 20, 3, 2, 4, 5];
  v_accts uuid[] := array[]::uuid[];
  v_sales uuid;
  v_success uuid;
  v_cust record;
  v_tax uuid;
  v_invoice uuid;
  v_issue date;
  v_due date;
  v_total numeric(16, 2);
  v_pay uuid;
  v_paydate date;
  v_take numeric(16, 2);
  v_seed bigint;
  v_roll integer;
  v_age integer;
  v_pct integer;
  v_lines integer;
  v_pick integer;
  v_month integer;
  i integer;
  k integer;
begin
  select id into v_sales from finance.cost_centers where code = 'SALES';
  select id into v_success from finance.cost_centers where code = 'CS';

  for k in 1..array_length(v_codes, 1) loop
    v_accts := v_accts || (select id from finance.accounts where code = v_codes[k]);
  end loop;

  for i in 1..150 loop
    v_seed := abs(hashtext ('supasheet-finance-invoice-' || i::text));

    select c.id, c.payment_terms_days, c.country, c.code
    into v_cust
    from finance.customers c
    where c.status <> 'closed'
    order by c.code
    offset (v_seed % 23)
    limit 1;

    -- One cohort per trading month rather than a uniform scatter over
    -- five hundred days. A scatter leaves some months with two
    -- invoices and others with fifteen, and a revenue trend built on
    -- that reads as a business in trouble rather than a seed with an
    -- uneven random draw.
    v_month := (i - 1) % 18;
    v_issue := least(
      (
        date_trunc('month', current_date) - ((17 - v_month) || ' months')::interval
      )::date + (v_seed % 28)::integer,
      current_date
    );
    v_due := v_issue + v_cust.payment_terms_days;

    select id into v_tax
    from finance.tax_rates
    where code = case
      when v_cust.country = 'GB' then 'STD-20'
      when v_cust.country in ('DE', 'NL', 'FR', 'IT', 'SE') then 'EU-21'
      when v_cust.country in ('US', 'CA') then 'US-NONE'
      else 'ZERO'
    end;

    insert into finance.invoices (
      customer_id, issue_date, due_date, currency, purchase_order, terms, notes
    )
    values (
      v_cust.id,
      v_issue,
      v_due,
      'USD',
      case
        when v_cust.code = 'C-1003' then 'PO-' || (48000 + (v_seed % 1800))::text
        when (v_seed % 5) = 0 then 'PO-' || (10000 + (v_seed % 8000))::text
        else null
      end,
      'Payable within ' || v_cust.payment_terms_days || ' days of the invoice date.',
      case when (v_seed % 7) = 0 then 'Raised against the signed order form.' else null end
    )
    returning id into v_invoice;

    v_lines := 1 + (v_seed % 3)::integer;

    for k in 1..v_lines loop
      v_pick := 1 + ((v_seed / (k * 11)) % 8)::integer;

      insert into finance.invoice_lines (
        invoice_id, account_id, cost_center_id, tax_rate_id, line_number,
        description, quantity, unit_price, discount_percent
      )
      values (
        v_invoice,
        v_accts[v_pick],
        case when v_pick <= 3 then v_sales else v_success end,
        v_tax,
        k,
        v_desc[v_pick],
        1 + ((v_seed / (k * 7)) % v_qtymax[v_pick])::integer,
        -- Prices drift up about 40% across the eighteen months, so the
        -- trend line slopes the way a growing business does.
        round(v_price[v_pick] * (0.74 + v_month * 0.022), 2),
        case when ((v_seed / (k * 13)) % 9) = 0 then 10 else 0 end
      );
    end loop;

    v_age := current_date - v_issue;
    v_roll := ((v_seed / 7) % 100)::integer;

    -- A handful of very recent invoices are still being written. This
    -- reads a DIFFERENT slice of the seed from the collection outcome
    -- below: sharing one roll would mean every invoice that would have
    -- been part paid got drafted instead, and the status would be
    -- unreachable.
    if v_age <= 9 and ((v_seed / 23) % 100)::integer < 45 then
      continue;
    end if;

    update finance.invoices set status = 'sent' where id = v_invoice;

    -- A few are cancelled, but only recent ones. Voiding reverses the
    -- original journal into the CURRENT period, because that is when
    -- the decision was made — so voiding a year-old invoice here would
    -- dump a large credit into this month and put a hole in the
    -- revenue trend that never happened.
    select total into v_total from finance.invoices where id = v_invoice;

    if v_roll >= 92 and v_age <= 60 and v_total < 25000 then
      perform finance.void_invoice (
        v_invoice,
        (array[
          'Duplicate of an earlier invoice',
          'Raised against the wrong entity',
          'Scope withdrawn before delivery'
        ]) [1 + (v_seed % 3)::integer]
      );
      continue;
    end if;

    v_pct := case
      when v_age > 120 then case when v_roll < 92 then 100 when v_roll < 97 then 50 else 0 end
      when v_age > 60 then case when v_roll < 80 then 100 when v_roll < 92 then 45 else 0 end
      when v_age > 30 then case when v_roll < 55 then 100 when v_roll < 75 then 40 else 0 end
      else case when v_roll < 25 then 100 when v_roll < 40 then 35 else 0 end
    end;

    if v_pct = 0 then
      continue;
    end if;

    if v_total <= 0 then
      continue;
    end if;

    v_take := round(v_total * v_pct / 100.0, 2);

    -- Good payers land near the due date, the rest drift past it.
    v_paydate := least(
      greatest(v_due + ((v_seed % 23) - 6)::integer, v_issue + 1),
      current_date
    );

    insert into finance.payments (
      direction, customer_id, bank_account_id, method, payment_date, amount, reference, note
    )
    values (
      'inbound',
      v_cust.id,
      'f5000000-0000-0000-0000-000000000001',
      (array['bank_transfer', 'bank_transfer', 'bank_transfer', 'card', 'direct_debit', 'cheque'])[
        1 + (v_seed % 6)::integer
      ]::finance.payment_method,
      v_paydate,
      v_take,
      'REF-' || lpad(((v_seed / 5) % 900000)::text, 6, '0'),
      case when v_pct < 100 then 'Part payment agreed with the customer.' else null end
    )
    returning id into v_pay;

    insert into finance.payment_allocations (payment_id, invoice_id, amount, allocated_on, note)
    values (
      v_pay,
      v_invoice,
      v_take,
      v_paydate,
      case when v_pct < 100 then 'Balance to follow.' else null end
    );
  end loop;
end;
$$;

----------------------------------------------------------------
-- Cash received on account
--
-- Money that arrived without a remittance advice. It sits
-- unallocated until somebody works out what it was for, which is
-- exactly what the "Unallocated" preset on the payments board is for.
----------------------------------------------------------------
insert into
  finance.payments (
    direction,
    customer_id,
    bank_account_id,
    method,
    payment_date,
    amount,
    reference,
    note
  )
select
  'inbound',
  c.id,
  'f5000000-0000-0000-0000-000000000001',
  'bank_transfer',
  current_date - ((abs(hashtext (c.code)) % 26) + 2),
  round(
    (900 + (abs(hashtext (c.code)) % 4200))::numeric,
    2
  ),
  'UNIDENTIFIED-' || right(c.code, 4),
  'Received without a remittance advice — allocation pending.'
from
  finance.customers c
where
  c.code in ('C-1002', 'C-1006', 'C-1011', 'C-1015', 'C-1019');

----------------------------------------------------------------
-- Supplier bills
--
-- Bills go through an approval step that invoices do not, because
-- money leaving needs a second pair of eyes. Approving is what posts
-- them; paying them is a separate act with its own journal.
----------------------------------------------------------------
do $$
declare
  v_vendor record;
  v_bill uuid;
  v_issue date;
  v_due date;
  v_total numeric(16, 2);
  v_pay uuid;
  v_paydate date;
  v_take numeric(16, 2);
  v_tax uuid;
  v_seed bigint;
  v_roll integer;
  v_age integer;
  v_pct integer;
  v_lines integer;
  v_cc uuid[];
  i integer;
  k integer;
begin
  select array_agg(id order by code) into v_cc
  from finance.cost_centers
  where code in ('ENG-PLAT', 'ENG-APP', 'SALES', 'MKT', 'CS', 'GA');

  for i in 1..75 loop
    v_seed := abs(hashtext ('supasheet-finance-bill-' || i::text));

    select v.id, v.payment_terms_days, v.country, v.default_expense_account_id, v.name
    into v_vendor
    from finance.vendors v
    where v.is_active
      -- The bank does not send an invoice; its charges arrive as
      -- direct debits on the statement further down.
      and v.code <> 'V-2002'
    order by v.code
    offset (v_seed % 16)
    limit 1;

    v_issue := least(
      (
        date_trunc('month', current_date) - ((17 - ((i - 1) % 18)) || ' months')::interval
      )::date + (v_seed % 27)::integer,
      current_date
    );
    v_due := v_issue + greatest(v_vendor.payment_terms_days, 7);

    select id into v_tax
    from finance.tax_rates
    where code = case when v_vendor.country = 'GB' then 'STD-20' else 'US-NONE' end;

    insert into finance.bills (
      vendor_id, vendor_reference, issue_date, due_date, currency, notes
    )
    values (
      v_vendor.id,
      'INV-' || upper(left(replace(v_vendor.name, ' ', ''), 4)) || '-' || lpad(((v_seed / 11) % 90000)::text, 5, '0'),
      v_issue,
      v_due,
      'USD',
      case when (v_seed % 9) = 0 then 'Checked against the purchase order before approval.' else null end
    )
    returning id into v_bill;

    v_lines := 1 + (v_seed % 2)::integer;

    for k in 1..v_lines loop
      insert into finance.bill_lines (
        bill_id, account_id, cost_center_id, tax_rate_id, line_number,
        description, quantity, unit_price
      )
      values (
        v_bill,
        v_vendor.default_expense_account_id,
        v_cc[1 + ((v_seed / (k * 5)) % array_length(v_cc, 1))::integer],
        v_tax,
        k,
        (array[
          'Monthly service charge',
          'Professional fees',
          'Licence renewal',
          'Materials and consumables',
          'Retainer'
        ]) [1 + ((v_seed / (k * 3)) % 5)::integer],
        1 + ((v_seed / (k * 7)) % 6)::integer,
        round((180 + ((v_seed / (k * 17)) % 2600))::numeric, 2)
      );
    end loop;

    v_age := current_date - v_issue;
    v_roll := ((v_seed / 7) % 100)::integer;

    -- Recent bills are still being checked. Each decision reads its own
    -- slice of the seed, so an early branch cannot make a later status
    -- unreachable.
    if v_age <= 6 and ((v_seed / 23) % 100)::integer < 50 then
      continue;
    end if;

    update finance.bills set status = 'awaiting_approval' where id = v_bill;

    -- A few are sitting in the approval queue right now.
    if v_age <= 35 and ((v_seed / 29) % 100)::integer < 35 then
      continue;
    end if;

    perform finance.approve_bill (v_bill);

    v_pct := case
      when v_age > 90 then case when v_roll < 94 then 100 when v_roll < 98 then 55 else 0 end
      when v_age > 45 then case when v_roll < 82 then 100 when v_roll < 92 then 45 else 0 end
      when v_age > 20 then case when v_roll < 50 then 100 when v_roll < 68 then 40 else 0 end
      else case when v_roll < 18 then 100 else 0 end
    end;

    if v_pct = 0 then
      continue;
    end if;

    select total into v_total from finance.bills where id = v_bill;

    if v_total <= 0 then
      continue;
    end if;

    v_take := round(v_total * v_pct / 100.0, 2);
    v_paydate := least(greatest(v_due - ((v_seed % 5))::integer, v_issue + 2), current_date);

    insert into finance.payments (
      direction, vendor_id, bank_account_id, method, payment_date, amount, reference
    )
    values (
      'outbound',
      v_vendor.id,
      'f5000000-0000-0000-0000-000000000001',
      (array['bank_transfer', 'bank_transfer', 'bank_transfer', 'direct_debit', 'card'])[
        1 + (v_seed % 5)::integer
      ]::finance.payment_method,
      v_paydate,
      v_take,
      'PAYRUN-' || to_char(v_paydate, 'YYYYMMDD')
    )
    returning id into v_pay;

    insert into finance.payment_allocations (payment_id, bill_id, amount, allocated_on)
    values (v_pay, v_bill, v_take, v_paydate);
  end loop;
end;
$$;

----------------------------------------------------------------
-- Recurring supplier bills
--
-- The costs that arrive on the same day every month and make up most
-- of the run rate: hosting, rent, telecoms, the payroll bureau and
-- the security retainer. Left to the random draw above, a SaaS
-- business would somehow spend less on servers than on printing.
--
-- The last two months are approved but not yet paid, so there is
-- something real on the payables board and in the payment run.
----------------------------------------------------------------
do $$
declare
  r record;
  m date;
  v_bill uuid;
  v_pay uuid;
  v_issue date;
  v_due date;
  v_amount numeric(16, 2);
  v_total numeric(16, 2);
  v_n integer;
  v_tax uuid;
begin
  for r in
    select *
    from (
      values
        ('V-2001', 'Cloud hosting, storage and data transfer', '5000', 16500, 420, 'ENG-PLAT'),
        ('V-2006', 'Office rent and service charge', '6600', 14500, 0, 'GA'),
        ('V-2007', 'Connectivity and telephony', '6900', 2400, 30, 'GA'),
        ('V-2017', 'Payroll bureau fee', '6010', 1850, 15, 'GA'),
        ('V-2008', 'Security monitoring retainer', '6200', 2900, 0, 'ENG-PLAT')
    ) as t (vendor_code, description, account_code, base, growth, cost_center)
  loop
    v_n := 0;

    for m in
      select d::date
      from generate_series(
        date_trunc('month', current_date) - interval '17 months',
        date_trunc('month', current_date),
        interval '1 month'
      ) d
      order by 1
    loop
      v_n := v_n + 1;
      v_issue := least(m + 4, current_date);

      continue when v_issue > current_date;

      select id into v_tax
      from finance.tax_rates
      where code = case
        when (select country from finance.vendors where code = r.vendor_code) = 'GB' then 'STD-20'
        else 'US-NONE'
      end;

      v_amount := r.base + (v_n * r.growth);
      v_due := v_issue + 30;

      insert into finance.bills (vendor_id, vendor_reference, issue_date, due_date, currency, notes)
      select v.id,
        upper(left(replace(v.name, ' ', ''), 4)) || '-' || to_char(m, 'YYYYMM'),
        v_issue,
        v_due,
        'USD',
        'Recurring monthly charge.'
      from finance.vendors v
      where v.code = r.vendor_code
      returning id into v_bill;

      insert into finance.bill_lines (
        bill_id, account_id, cost_center_id, tax_rate_id, line_number,
        description, quantity, unit_price
      )
      select v_bill,
        a.id,
        cc.id,
        v_tax,
        1,
        r.description || ' — ' || to_char(m, 'FMMonth YYYY'),
        1,
        v_amount
      from finance.accounts a
        cross join finance.cost_centers cc
      where a.code = r.account_code
        and cc.code = r.cost_center;

      update finance.bills set status = 'awaiting_approval' where id = v_bill;

      perform finance.approve_bill (v_bill);

      -- Everything older than two months has been through a payment
      -- run; the rest is what the payment run is for.
      continue when m > date_trunc('month', current_date) - interval '2 months';

      select total into v_total from finance.bills where id = v_bill;

      insert into finance.payments (
        direction, vendor_id, bank_account_id, method, payment_date, amount, reference
      )
      select 'outbound',
        v.id,
        'f5000000-0000-0000-0000-000000000001',
        'direct_debit',
        least(v_due, current_date),
        v_total,
        'DD-' || to_char(m, 'YYYYMM')
      from finance.vendors v
      where v.code = r.vendor_code
      returning id into v_pay;

      insert into finance.payment_allocations (payment_id, bill_id, amount, allocated_on)
      values (v_pay, v_bill, v_total, least(v_due, current_date));
    end loop;
  end loop;
end;
$$;

----------------------------------------------------------------
-- The month-end pack
--
-- The journals a bookkeeper actually types: payroll, funding the
-- payroll account from the operating one, releasing prepayments, and
-- moving subscription income into and out of deferred revenue. One
-- set per month, every one of them balanced by construction.
----------------------------------------------------------------
do $$
declare
  m date;
  v_journal uuid;
  v_gross numeric(16, 2);
  v_oncost numeric(16, 2);
  v_n integer := 0;
begin
  for m in
    select (d + interval '1 month - 1 day')::date
    from generate_series(
      date_trunc('month', current_date) - interval '17 months',
      date_trunc('month', current_date),
      interval '1 month'
    ) d
    order by 1
  loop
    -- This month's payroll has not run yet.
    continue when m > current_date;

    v_n := v_n + 1;
    v_gross := 72000 + (v_n * 900);
    v_oncost := round(v_gross * 0.22, 2);

    -- The monthly treasury sweep: fund the payroll account before
    -- drawing on it, and put money aside for the tax bill before it
    -- arrives. Both are moves between accounts the business already
    -- owns, so the entry nets to nothing in the profit and loss.
    insert into finance.journals (entry_date, source, memo, reference)
    values (m - 2, 'manual', 'Treasury sweep for ' || to_char(m, 'FMMonth YYYY'), 'TRF-' || to_char(m, 'YYYYMM'))
    returning id into v_journal;

    insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
    values
      (v_journal, 'f3000000-0000-0000-0000-000000000003', 1, 'Payroll funding in', v_gross + v_oncost, 0),
      (v_journal, 'f3000000-0000-0000-0000-000000000004', 2, 'Set aside against the tax bill', 16000, 0),
      (v_journal, 'f3000000-0000-0000-0000-000000000002', 3, 'Swept out of the operating account', 0, v_gross + v_oncost + 16000);

    update finance.journals set status = 'posted' where id = v_journal;

    insert into finance.journals (entry_date, source, memo, reference)
    values (m, 'manual', 'Payroll — ' || to_char(m, 'FMMonth YYYY'), 'PAY-' || to_char(m, 'YYYYMM'))
    returning id into v_journal;

    -- Split across the teams that carry the headcount. A single
    -- undifferentiated payroll line would post correctly and still
    -- leave every salary budget showing no spend at all.
    insert into finance.journal_lines (journal_id, account_id, cost_center_id, line_number, description, debit, credit)
    select v_journal,
      'f3000000-0000-0000-0000-000000000029',
      cc.id,
      row_number() over (order by t.code),
      'Salaries and wages — ' || cc.name,
      round(v_gross * t.share, 2),
      0
    from (
      values
        ('ENG-PLAT', 0.34),
        ('ENG-APP', 0.28),
        ('SALES', 0.22),
        ('GA', 0.16)
    ) as t (code, share)
      join finance.cost_centers cc on cc.code = t.code;

    insert into finance.journal_lines (journal_id, account_id, cost_center_id, line_number, description, debit, credit)
    select v_journal,
      'f3000000-0000-0000-0000-000000000030',
      cc.id,
      5,
      'Employer taxes and benefits',
      v_oncost,
      0
    from finance.cost_centers cc
    where cc.code = 'GA';

    insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
    values (v_journal, 'f3000000-0000-0000-0000-000000000003', 6, 'Paid from the payroll account', 0, v_gross + v_oncost);

    update finance.journals set status = 'posted' where id = v_journal;

    -- Release a slice of the insurance and licences paid up front at
    -- go-live, and roll the subscription deferral forward.
    insert into finance.journals (entry_date, source, memo, reference)
    values (m, 'manual', 'Prepayments and deferred revenue — ' || to_char(m, 'FMMonth YYYY'), 'ADJ-' || to_char(m, 'YYYYMM'))
    returning id into v_journal;

    insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
    values
      (v_journal, 'f3000000-0000-0000-0000-000000000034', 1, 'Prepaid licences released to cost', 2000, 0),
      (v_journal, 'f3000000-0000-0000-0000-000000000006', 2, 'Prepayment carried down', 0, 2000),
      (v_journal, 'f3000000-0000-0000-0000-000000000020', 3, 'Subscription billed ahead of delivery', 12000, 0),
      (v_journal, 'f3000000-0000-0000-0000-000000000015', 4, 'Deferred to future periods', 0, 12000),
      (v_journal, 'f3000000-0000-0000-0000-000000000015', 5, 'Prior deferral earned', 10500, 0),
      (v_journal, 'f3000000-0000-0000-0000-000000000020', 6, 'Released to subscription revenue', 0, 10500);

    update finance.journals set status = 'posted' where id = v_journal;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Tax returns
--
-- Quarterly, and computed from what was actually posted rather than
-- from a number typed in: output tax collected is cleared against
-- input tax recoverable, and the difference leaves the reserve
-- account. The current quarter is deliberately left open.
----------------------------------------------------------------
do $$
declare
  q record;
  v_journal uuid;
  v_output numeric(16, 2);
  v_input numeric(16, 2);
  v_net numeric(16, 2);
begin
  for q in
    select d::date as starts_on,
      (d + interval '3 months - 1 day')::date as ends_on
    from generate_series(
      date_trunc('quarter', current_date) - interval '18 months',
      date_trunc('quarter', current_date) - interval '3 months',
      interval '3 months'
    ) d
    order by 1
  loop
    -- What a return settles is the BALANCE standing on the control
    -- account, not that quarter's movement. Each settlement zeroes the
    -- account, so the next one naturally picks up only what has
    -- accrued since — and a late invoice posted into a quarter already
    -- returned is picked up too, instead of being silently dropped.
    select greatest(coalesce(sum(l.credit - l.debit), 0), 0)
    into v_output
    from finance.journal_lines l
      join finance.journals j on j.id = l.journal_id
    where j.status <> 'draft'
      and l.account_id = 'f3000000-0000-0000-0000-000000000012'
      and j.entry_date <= q.ends_on;

    select greatest(coalesce(sum(l.debit - l.credit), 0), 0)
    into v_input
    from finance.journal_lines l
      join finance.journals j on j.id = l.journal_id
    where j.status <> 'draft'
      and l.account_id = 'f3000000-0000-0000-0000-000000000013'
      and j.entry_date <= q.ends_on;

    v_net := v_output - v_input;

    continue when v_output = 0 and v_input = 0;

    insert into finance.journals (entry_date, source, memo, reference)
    values (
      least(q.ends_on + 30, current_date),
      'manual',
      'Tax return for the quarter to ' || to_char(q.ends_on, 'DD Mon YYYY'),
      'VAT-' || to_char(q.ends_on, 'YYYYMM')
    )
    returning id into v_journal;

    insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
    values
      (v_journal, 'f3000000-0000-0000-0000-000000000012', 1, 'Output tax cleared', v_output, 0),
      (v_journal, 'f3000000-0000-0000-0000-000000000013', 2, 'Input tax reclaimed', 0, v_input),
      (
        v_journal,
        'f3000000-0000-0000-0000-000000000004',
        3,
        case when v_net >= 0 then 'Paid from the tax reserve' else 'Refund into the tax reserve' end,
        case when v_net >= 0 then 0 else -v_net end,
        case when v_net >= 0 then v_net else 0 end
      );

    update finance.journals set status = 'posted' where id = v_journal;
  end loop;
end;
$$;

----------------------------------------------------------------
-- An accrual, and the reversal that unwinds it
--
-- This is the one place the immutability rule is visible from the
-- outside. The accrual was right at the year end and wrong the day
-- after, and the only way to undo a posted entry is to book its
-- mirror image — which is exactly what happens here.
----------------------------------------------------------------
do $$
declare
  v_journal uuid;
  v_accrual_date date;
begin
  v_accrual_date := (date_trunc('month', current_date) - interval '4 months' + interval '1 month - 1 day')::date;

  insert into finance.journals (entry_date, source, memo, reference)
  values (v_accrual_date, 'manual', 'Accrue estimated audit fee', 'ACC-0001')
  returning id into v_journal;

  insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
  values
    (v_journal, 'f3000000-0000-0000-0000-000000000038', 1, 'Estimated audit fee', 28000, 0),
    (v_journal, 'f3000000-0000-0000-0000-000000000014', 2, 'Accrued expenses', 0, 28000);

  update finance.journals set status = 'posted' where id = v_journal;

  perform finance.reverse_journal (
    v_journal,
    'Estimate superseded by the invoice from Ashcroft Audit'
  );
end;
$$;

----------------------------------------------------------------
-- Work in progress
--
-- Three drafts sitting in the current period. They are what the
-- "Drafts To Post" list on the dashboard is for, and they are why
-- the current period cannot be closed yet.
----------------------------------------------------------------
do $$
declare
  v_journal uuid;
begin
  insert into finance.journals (entry_date, source, memo, reference)
  values (current_date, 'manual', 'Accrue Q3 commission — awaiting the sales report', 'WIP-0001')
  returning id into v_journal;

  insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
  values
    (v_journal, 'f3000000-0000-0000-0000-000000000029', 1, 'Estimated commission', 34500, 0),
    (v_journal, 'f3000000-0000-0000-0000-000000000014', 2, 'Accrued commission', 0, 34500);

  insert into finance.journals (entry_date, source, memo, reference)
  values (current_date - 1, 'manual', 'Reclassify hosting spend to cost of sales', 'WIP-0002')
  returning id into v_journal;

  insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
  values
    (v_journal, 'f3000000-0000-0000-0000-000000000025', 1, 'Hosting reclassified in', 6400, 0),
    (v_journal, 'f3000000-0000-0000-0000-000000000042', 2, 'Reclassified out of other costs', 0, 6400);

  -- Left deliberately out of balance. The post guard will refuse it,
  -- which is the point: a draft is allowed to be wrong.
  insert into finance.journals (entry_date, source, memo, reference)
  values (current_date, 'manual', 'Office move costs — coding not agreed', 'WIP-0003')
  returning id into v_journal;

  insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
  values
    (v_journal, 'f3000000-0000-0000-0000-000000000040', 1, 'Fit-out and removals', 18750, 0),
    (v_journal, 'f3000000-0000-0000-0000-000000000010', 2, 'Supplier to be confirmed', 0, 12000);
end;
$$;

----------------------------------------------------------------
-- Expense claims
--
-- The one part of this module an ordinary employee writes to. Claims
-- are drafted, coded line by line, submitted, decided by finance and
-- then reimbursed — and it is the reimbursement, not the approval,
-- that posts them to the ledger.
--
-- Anything over the receipt threshold in finance_settings carries a
-- receipt, because the line trigger refuses it otherwise. That guard
-- is exercised here rather than worked around.
----------------------------------------------------------------
do $$
declare
  v_claimants uuid[] := array[
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1'::uuid,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4'::uuid,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'::uuid,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d1'::uuid,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d2'::uuid,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d3'::uuid
  ];
  v_titles text[] := array[
    'Customer visit — London',
    'Onsite implementation week',
    'Team offsite',
    'Industry conference',
    'Client dinner',
    'Home office equipment',
    'Certification course',
    'Partner workshop',
    'Recruiting day',
    'Quarterly business review travel'
  ];
  v_cats text[] := array['travel', 'accommodation', 'meals', 'software', 'hardware', 'training', 'entertainment', 'other'];
  v_codes text[] := array['6100', '6110', '6120', '6200', '6210', '6700', '6120', '6900'];
  v_low integer[] := array[45, 95, 12, 15, 45, 250, 60, 8];
  v_high integer[] := array[820, 340, 145, 290, 1400, 1750, 460, 175];
  v_merchants text[][] := array[
    array['Great Western Railway', 'Lufthansa', 'Uber', 'Eurostar', 'Delta Air Lines'],
    array['Premier Inn', 'Hilton Garden Inn', 'Citizen M', 'Marriott', 'Airbnb'],
    array['Pret A Manger', 'Dishoom', 'Le Pain Quotidien', 'Nando''s', 'Honest Burgers'],
    array['Figma', 'Notion', 'JetBrains', 'GitHub', '1Password'],
    array['Kirkwall Hardware', 'Apple Store', 'Dell', 'Logitech', 'Anker'],
    array['Lantern Learning', 'Coursera', 'O''Reilly', 'AWS Training', 'Pluralsight'],
    array['The Ivy', 'Hawksmoor', 'Ottolenghi', 'Bar Douro', 'Brat'],
    array['Royal Mail', 'DHL', 'WeWork', 'Ryman', 'Amazon Business']
  ];
  v_accts uuid[] := array[]::uuid[];
  v_cc uuid[];
  v_claim uuid;
  v_claimant uuid;
  v_name text;
  v_seed bigint;
  v_age integer;
  v_roll integer;
  v_lines integer;
  v_pick integer;
  v_net numeric(16, 2);
  v_created date;
  i integer;
  k integer;
begin
  for k in 1..array_length(v_codes, 1) loop
    v_accts := v_accts || (select id from finance.accounts where code = v_codes[k]);
  end loop;

  select array_agg(id order by code) into v_cc
  from finance.cost_centers
  where code in ('ENG-APP', 'SALES', 'MKT', 'CS', 'GA');

  for i in 1..58 loop
    v_seed := abs(hashtext ('supasheet-finance-claim-' || i::text));
    v_claimant := v_claimants[1 + (v_seed % 6)::integer];
    v_created := current_date - case
      when i <= 16 then ((v_seed / 3) % 26)::integer
      else ((v_seed / 3) % 300)::integer
    end;

    select coalesce(u.name, split_part(u.email, '@', 1))
    into v_name
    from supasheet.users u
    where u.id = v_claimant;

    insert into finance.expense_claims (
      claimant_id, claimant_name, cost_center_id, title, purpose, currency
    )
    values (
      v_claimant,
      v_name,
      v_cc[1 + (v_seed % array_length(v_cc, 1))::integer],
      v_titles[1 + ((v_seed / 7) % 10)::integer],
      (array[
        'Booked against the account plan.',
        'Agreed with the line manager before travel.',
        'Part of the quarterly plan.',
        'Approved in advance by the budget holder.'
      ]) [1 + ((v_seed / 11) % 4)::integer],
      'USD'
    )
    returning id into v_claim;

    v_lines := 2 + (v_seed % 4)::integer;

    for k in 1..v_lines loop
      v_pick := 1 + ((v_seed / (k * 13)) % 8)::integer;
      v_net := round(
        (v_low[v_pick] + ((v_seed / (k * 3)) % (v_high[v_pick] - v_low[v_pick])))::numeric,
        2
      );

      insert into finance.expense_lines (
        claim_id, account_id, category, spent_on, merchant, description,
        net_amount, tax_amount, is_reimbursable, receipt
      )
      values (
        v_claim,
        v_accts[v_pick],
        v_cats[v_pick]::finance.expense_category,
        v_created - ((v_seed / (k * 5)) % 9)::integer,
        v_merchants[v_pick][1 + ((v_seed / (k * 7)) % 5)::integer],
        initcap(replace(v_cats[v_pick], '_', ' ')) || ' — ' || v_titles[1 + ((v_seed / 7) % 10)::integer],
        v_net,
        case when v_pick in (4, 5) then round(v_net * 0.20, 2) else 0 end,
        true,
        -- The line trigger refuses anything over the threshold without
        -- one, so the receipt is attached where it is actually needed.
        case
          when v_net > 25 then array[
            row(
              'receipt-' || i || '-' || k || '.pdf',
              'application/pdf',
              (48000 + (v_seed % 260000))::bigint,
              'finance-documents/receipts/' || i || '-' || k || '.pdf',
              (v_created - ((v_seed / (k * 5)) % 9)::integer)::timestamp
            )::supasheet.file_object
          ]::supasheet.file
          else null
        end
      );
    end loop;

    v_age := current_date - v_created;
    v_roll := ((v_seed / 17) % 100)::integer;

    if v_age < 12 then
      if v_roll < 35 then
        continue;
      end if;

      update finance.expense_claims
      set status = 'submitted',
        submitted_at = (v_created + 1)::timestamptz + interval '10 hours'
      where id = v_claim;

      continue when v_roll < 90;

      update finance.expense_claims
      set status = 'approved',
        approved_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0d2',
        approved_at = (v_created + 3)::timestamptz + interval '14 hours'
      where id = v_claim;

      continue;
    end if;

    update finance.expense_claims
    set status = 'submitted',
      submitted_at = (v_created + 1)::timestamptz + interval '10 hours'
    where id = v_claim;

    if v_roll >= 93 then
      update finance.expense_claims
      set status = 'rejected',
        rejected_reason = (array[
          'No receipt for the largest line — please attach and resubmit.',
          'Entertainment over the per-head limit; split the personal portion out.',
          'Coded to the wrong cost centre.'
        ]) [1 + (v_seed % 3)::integer],
        approved_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0d2',
        approved_at = (v_created + 3)::timestamptz + interval '9 hours'
      where id = v_claim;

      continue;
    end if;

    update finance.expense_claims
    set status = 'approved',
      approved_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0d2',
      approved_at = (v_created + 3)::timestamptz + interval '14 hours'
    where id = v_claim;

    -- Claims older than a month have been through a reimbursement run.
    continue when v_age < 30 and v_roll < 40;

    update finance.expense_claims
    set status = 'reimbursed',
      reimbursed_on = least(v_created + 12, current_date)
    where id = v_claim;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Reimbursement runs
--
-- Approving a claim posts what is owed to the person; it does not pay
-- them. The money leaves in a monthly run, which is the only reason
-- 2150 Expense Reimbursements Payable ever carries a balance.
----------------------------------------------------------------
do $$
declare
  m date;
  v_journal uuid;
  v_amount numeric(16, 2);
begin
  for m in
    select d::date
    from generate_series(
      date_trunc('month', current_date) - interval '18 months',
      date_trunc('month', current_date),
      interval '1 month'
    ) d
    order by 1
  loop
    select coalesce(sum(total_amount), 0)
    into v_amount
    from finance.expense_claims
    where status = 'reimbursed'
      and reimbursed_on >= m
      and reimbursed_on < m + interval '1 month';

    continue when v_amount <= 0;

    insert into finance.journals (entry_date, source, memo, reference)
    values (
      least((m + interval '1 month - 1 day')::date, current_date),
      'expense',
      'Expense reimbursement run — ' || to_char(m, 'FMMonth YYYY'),
      'REIMB-' || to_char(m, 'YYYYMM')
    )
    returning id into v_journal;

    insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
    values
      (v_journal, 'f3000000-0000-0000-0000-000000000011', 1, 'Reimbursements cleared', v_amount, 0),
      (v_journal, 'f3000000-0000-0000-0000-000000000002', 2, 'Paid from the operating account', 0, v_amount);

    update finance.journals set status = 'posted' where id = v_journal;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Bank statement
--
-- One line per payment, plus the charges and interest that never
-- appear anywhere else. Lines older than three weeks have been
-- reconciled; the rest is the work sitting in front of whoever opens
-- the reconciliation board this morning.
--
-- The trigger promotes anything carrying a matched payment out of
-- `unreconciled` on its own, so the genuinely unmatched lines are the
-- bank''s own charges — which is exactly the pile that needs a human.
----------------------------------------------------------------
insert into
  finance.bank_transactions (
    bank_account_id,
    transaction_date,
    value_date,
    description,
    counterparty,
    reference,
    amount,
    status,
    matched_payment_id,
    matched_journal_id,
    reconciled_on
  )
select
  coalesce(
    p.bank_account_id,
    'f5000000-0000-0000-0000-000000000001'
  ),
  p.payment_date,
  p.payment_date + case
    when p.method = 'cheque' then 3
    else 0
  end,
  case
    when p.direction = 'inbound' then 'BACS CREDIT ' || upper(coalesce(c.name, 'CUSTOMER'))
    else 'BACS DEBIT ' || upper(coalesce(v.name, 'SUPPLIER'))
  end,
  coalesce(c.name, v.name),
  p.reference,
  case
    when p.direction = 'inbound' then p.amount
    else - p.amount
  end,
  case
    when p.payment_date < current_date - 21 then 'reconciled'
    else 'matched'
  end::finance.bank_transaction_status,
  p.id,
  p.journal_id,
  case
    when p.payment_date < current_date - 21 then p.payment_date + 2
    else null
  end
from
  finance.payments p
  left join finance.customers c on c.id = p.customer_id
  left join finance.vendors v on v.id = p.vendor_id;

-- Bank charges and credit interest, for the months already
-- reconciled. Reconciling a statement line is what creates the entry
-- behind it, so these exist as journals — and the internal-movement
-- lines below put them on the statement, rather than the statement
-- claiming a match to something that was never posted.
do $$
declare
  m date;
  v_journal uuid;
  v_interest numeric(16, 2);
begin
  for m in
    select d::date
    from generate_series(
      date_trunc('month', current_date) - interval '17 months',
      date_trunc('month', current_date) - interval '2 months',
      interval '1 month'
    ) d
    order by 1
  loop
    v_interest := round((140 + (abs(hashtext (to_char(m, 'YYYYMM'))) % 260))::numeric, 2);

    insert into finance.journals (entry_date, source, memo, reference)
    values (
      (m + interval '1 month - 1 day')::date,
      'manual',
      'Bank charges and interest — ' || to_char(m, 'FMMonth YYYY'),
      'BANK-' || to_char(m, 'YYYYMM')
    )
    returning id into v_journal;

    insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
    values
      (v_journal, 'f3000000-0000-0000-0000-000000000042', 1, 'ACCOUNT MAINTENANCE FEE', 85, 0),
      (v_journal, 'f3000000-0000-0000-0000-000000000002', 2, 'Charged to the operating account', 0, 85),
      (v_journal, 'f3000000-0000-0000-0000-000000000004', 3, 'CREDIT INTEREST', v_interest, 0),
      (v_journal, 'f3000000-0000-0000-0000-000000000023', 4, 'Interest earned on the reserve', 0, v_interest);

    update finance.journals set status = 'posted' where id = v_journal;
  end loop;
end;
$$;

-- And the pile that has NOT been dealt with: last month's charges,
-- the most recent interest, and seven one-off items nobody has coded.
-- None of these has a journal behind it, which is precisely why they
-- are still sitting on the reconciliation board.
insert into
  finance.bank_transactions (
    bank_account_id,
    transaction_date,
    description,
    counterparty,
    reference,
    amount,
    status,
    note
  )
select
  x.account_id::uuid,
  x.tx_date,
  x.description,
  x.counterparty,
  x.reference,
  x.amount,
  'unreconciled'::finance.bank_transaction_status,
  x.note
from
  (
    select
      'f5000000-0000-0000-0000-000000000001' as account_id,
      (m + interval '1 month - 1 day')::date as tx_date,
      'ACCOUNT MAINTENANCE FEE' as description,
      'Northgate Commercial' as counterparty,
      'CHG-' || to_char(m, 'YYYYMM') as reference,
      -85.00 as amount,
      null::varchar as note
    from
      generate_series(
        date_trunc('month', current_date) - interval '1 month',
        date_trunc('month', current_date) - interval '1 month',
        interval '1 month'
      ) m
    union all
    select
      'f5000000-0000-0000-0000-000000000003',
      (m + interval '1 month - 1 day')::date,
      'CREDIT INTEREST',
      'Meridian Savings',
      'INT-' || to_char(m, 'YYYYMM'),
      round(
        (
          140 + (abs(hashtext (to_char(m, 'YYYYMM'))) % 260)
        )::numeric,
        2
      ),
      null
    from
      generate_series(
        date_trunc('month', current_date) - interval '1 month',
        date_trunc('month', current_date) - interval '1 month',
        interval '1 month'
      ) m
    union all
    select
      'f5000000-0000-0000-0000-000000000001',
      current_date - v.days,
      v.description,
      v.counterparty,
      v.reference,
      v.amount,
      v.note
    from
      (
        values
          (
            4,
            'FASTER PAYMENT IN',
            'UNKNOWN REMITTER',
            'FP-884219',
            4820.00,
            'No remittance advice — chase the sender.'
          ),
          (
            9,
            'CARD PAYMENT',
            'ADOBE SYSTEMS',
            'CARD-7741',
            -239.00,
            'Card spend with no claim against it yet.'
          ),
          (
            11,
            'FASTER PAYMENT OUT',
            'HMRC',
            'HMRC-PAYE',
            -18400.00,
            'PAYE settlement — journal to follow.'
          ),
          (
            14,
            'DIRECT DEBIT',
            'CORVUS INSURANCE BROKERS',
            'DD-INSUR',
            -1145.00,
            null
          ),
          (
            18,
            'BANK GIRO CREDIT',
            'GRANITE MINING HOLDINGS',
            'BGC-20194',
            9600.00,
            'Possible early settlement — confirm the invoice.'
          ),
          (
            23,
            'FX FEE',
            'NORTHGATE COMMERCIAL',
            'FX-0091',
            -62.40,
            null
          ),
          (
            27,
            'RETURNED DIRECT DEBIT',
            'BRIGHTWIRE TELECOM',
            'DD-RTN-04',
            2400.00,
            'Represented the following week.'
          )
      ) as v (
        days,
        description,
        counterparty,
        reference,
        amount,
        note
      )
  ) x;

----------------------------------------------------------------
-- Fixed assets
--
-- Each asset is capitalised with its own journal — the cost lands on
-- 1500 rather than being written off to hardware — and then
-- depreciated one period at a time, in order, by the same routine the
-- "Run depreciation" form calls. The register and the ledger agree
-- because they are the same numbers.
----------------------------------------------------------------
do $$
declare
  r record;
  v_asset uuid;
  v_journal uuid;
  v_purchase date;
begin
  for r in
    select *
    from (
      values
        ('FA-0001', 'Engineering laptop fleet', 'IT equipment', 'straight_line', 48000, 0, 36, 17, 'ENG-PLAT', 'London HQ — 2nd floor', 'in_service'),
        ('FA-0002', 'Commercial laptop fleet', 'IT equipment', 'straight_line', 27500, 0, 36, 15, 'SALES', 'London HQ — 1st floor', 'in_service'),
        ('FA-0003', 'London office fit-out', 'Leasehold improvements', 'straight_line', 185000, 0, 120, 17, 'GA', 'London HQ', 'in_service'),
        ('FA-0004', 'Meeting room AV', 'Fixtures and fittings', 'straight_line', 22400, 0, 60, 16, 'GA', 'London HQ — 3rd floor', 'in_service'),
        ('FA-0005', 'Colocation server rack', 'IT equipment', 'reducing_balance', 64000, 4000, 48, 14, 'ENG-PLAT', 'Slough DC1', 'in_service'),
        ('FA-0006', 'Network refresh', 'IT equipment', 'straight_line', 18900, 0, 48, 12, 'ENG-PLAT', 'London HQ — comms room', 'in_service'),
        ('FA-0007', 'Desks and seating', 'Fixtures and fittings', 'straight_line', 41200, 0, 84, 17, 'GA', 'London HQ', 'in_service'),
        ('FA-0008', 'Company vehicle', 'Motor vehicles', 'reducing_balance', 38500, 9000, 60, 11, 'SALES', 'Field', 'in_service'),
        ('FA-0009', 'Exhibition stand', 'Marketing assets', 'straight_line', 26800, 0, 36, 9, 'MKT', 'Warehouse — Reading', 'in_service'),
        ('FA-0010', 'Security appliances', 'IT equipment', 'straight_line', 14600, 0, 36, 8, 'ENG-PLAT', 'Slough DC1', 'in_service'),
        ('FA-0011', 'Design workstations', 'IT equipment', 'straight_line', 19200, 0, 36, 6, 'ENG-APP', 'London HQ — 2nd floor', 'in_service'),
        ('FA-0012', 'Studio lighting and camera kit', 'Marketing assets', 'straight_line', 11300, 0, 48, 5, 'MKT', 'London HQ — studio', 'in_service'),
        ('FA-0013', 'Breakout and kitchen fit-out', 'Fixtures and fittings', 'straight_line', 16500, 0, 84, 4, 'GA', 'London HQ — ground floor', 'idle'),
        ('FA-0014', 'Legacy phone system', 'IT equipment', 'straight_line', 9800, 0, 60, 16, 'GA', 'Disposed', 'disposed')
    ) as t (
      asset_code, name, category, method, cost, residual,
      life_months, months_ago, cost_center, location, status
    )
  loop
    v_purchase := (date_trunc('month', current_date) - (r.months_ago || ' months')::interval + interval '9 days')::date;

    insert into finance.fixed_assets (
      asset_code, name, description, category, status, depreciation_method,
      asset_account_id, depreciation_account_id, cost_center_id,
      purchase_date, in_service_date, purchase_cost, residual_value,
      useful_life_months, serial_number, location, disposal_date, disposal_proceeds
    )
    select r.asset_code,
      r.name,
      'Capitalised on acquisition and depreciated monthly.',
      r.category,
      r.status::finance.asset_status,
      r.method::finance.depreciation_method,
      'f3000000-0000-0000-0000-000000000008',
      'f3000000-0000-0000-0000-000000000039',
      cc.id,
      v_purchase,
      v_purchase,
      r.cost,
      r.residual,
      r.life_months,
      'SN-' || upper(right(r.asset_code, 4)) || '-' || (10000 + abs(hashtext (r.asset_code)) % 89999)::text,
      r.location,
      case when r.status = 'disposed' then current_date - 40 else null end,
      case when r.status = 'disposed' then 1200 else null end
    from finance.cost_centers cc
    where cc.code = r.cost_center
    returning id into v_asset;

    insert into finance.journals (entry_date, source, memo, reference)
    values (v_purchase, 'manual', 'Capitalise ' || r.name, r.asset_code)
    returning id into v_journal;

    insert into finance.journal_lines (journal_id, account_id, cost_center_id, line_number, description, debit, credit)
    select v_journal,
      'f3000000-0000-0000-0000-000000000007',
      cc.id,
      1,
      r.name || ' — cost',
      r.cost,
      0
    from finance.cost_centers cc
    where cc.code = r.cost_center;

    insert into finance.journal_lines (journal_id, account_id, line_number, description, debit, credit)
    values (v_journal, 'f3000000-0000-0000-0000-000000000002', 2, 'Paid from the operating account', 0, r.cost);

    update finance.journals set status = 'posted' where id = v_journal;
  end loop;
end;
$$;

-- Depreciation, one period at a time and in order, because the
-- routine only charges an asset once per period and works out what it
-- owes from what it has already charged. Running the months out of
-- order would quietly produce a different answer.
do $$
declare
  p record;
begin
  for p in
    select id
    from finance.fiscal_periods
    where ends_on < current_date
    order by starts_on
  loop
    perform finance.run_depreciation (p.id, true);
  end loop;
end;
$$;

-- The internal movements: the opening balance, the treasury sweeps,
-- payroll leaving the payroll account, the tax returns leaving the
-- reserve and the reimbursement runs. Each hits a bank account in the
-- ledger, so each hits the statement too. Leaving them out would put
-- a permanent unexplained gap between the two sides of every
-- reconciliation, and the gap is supposed to mean something.
insert into
  finance.bank_transactions (
    bank_account_id,
    transaction_date,
    description,
    counterparty,
    reference,
    amount,
    status,
    matched_journal_id,
    reconciled_on
  )
select
  ba.id,
  j.entry_date,
  upper(coalesce(l.description, j.memo)),
  'Internal transfer',
  j.reference,
  l.debit - l.credit,
  case
    when j.entry_date < current_date - 21 then 'reconciled'
    else 'matched'
  end::finance.bank_transaction_status,
  j.id,
  case
    when j.entry_date < current_date - 21 then j.entry_date
    else null
  end
from
  finance.journal_lines l
  join finance.journals j on j.id = l.journal_id
  join finance.bank_accounts ba on ba.gl_account_id = l.account_id
where
  j.status <> 'draft'
  and j.source in ('manual', 'opening_balance', 'expense')
  and l.debit - l.credit <> 0;

----------------------------------------------------------------
-- Budgets
--
-- Set for the current fiscal year against the cost centres that
-- actually spend. The actuals are not typed in — they are recomputed
-- from posted lines, which is why some of these are already over.
----------------------------------------------------------------
insert into
  finance.budgets (
    fiscal_year,
    account_id,
    cost_center_id,
    status,
    budget_amount,
    note
  )
select
  extract(
    year
    from
      current_date
  )::integer,
  a.id,
  cc.id,
  'approved',
  b.amount,
  b.note
from
  (
    values
      (
        '5000',
        'ENG-PLAT',
        240000,
        'Cloud spend, assuming 30% growth in usage'
      ),
      (
        '5100',
        'ENG-PLAT',
        40000,
        'Embedded analytics licence'
      ),
      (
        '6000',
        'ENG-PLAT',
        520000,
        'Platform team payroll'
      ),
      (
        '6000',
        'ENG-APP',
        430000,
        'Application team payroll'
      ),
      (
        '6000',
        'SALES',
        340000,
        'Quota-carrying headcount'
      ),
      ('6000', 'GA', 210000, 'Finance, people and legal'),
      (
        '6010',
        'GA',
        190000,
        'Employer taxes and benefits'
      ),
      (
        '6100',
        'SALES',
        48000,
        'Customer visits and QBRs'
      ),
      ('6100', 'CS', 22000, 'Onboarding travel'),
      (
        '6110',
        'SALES',
        26000,
        'Accommodation on customer visits'
      ),
      ('6120', 'SALES', 18000, 'Client hospitality'),
      (
        '6200',
        'ENG-PLAT',
        72000,
        'Developer tooling and monitoring'
      ),
      (
        '6200',
        'ENG-APP',
        34000,
        'Design and collaboration tools'
      ),
      ('6200', 'GA', 26000, 'Finance and HR systems'),
      (
        '6210',
        'ENG-PLAT',
        45000,
        'Hardware refresh cycle'
      ),
      (
        '6210',
        'ENG-APP',
        28000,
        'Workstations for new starters'
      ),
      (
        '6300',
        'MKT',
        120000,
        'Paid acquisition and content'
      ),
      (
        '6310',
        'MKT',
        95000,
        'User conference and three trade shows'
      ),
      (
        '6400',
        'GA',
        110000,
        'Audit, legal and recruitment fees'
      ),
      (
        '6600',
        'GA',
        185000,
        'London HQ rent and service charge'
      ),
      (
        '6700',
        'ENG-PLAT',
        24000,
        'Certifications and conferences'
      ),
      ('6700', 'ENG-APP', 18000, 'Training budget'),
      (
        '6700',
        'CS',
        12000,
        'Product and support training'
      ),
      (
        '6900',
        'GA',
        60000,
        'Insurance, telephony and everything else'
      ),
      (
        '6900',
        'CS',
        15000,
        'Support tooling and sundries'
      )
  ) as b (account_code, cost_center_code, amount, note)
  join finance.accounts a on a.code = b.account_code
  join finance.cost_centers cc on cc.code = b.cost_center_code;

-- A draft next-year plan, so the board has something in every column.
insert into
  finance.budgets (
    fiscal_year,
    account_id,
    cost_center_id,
    status,
    budget_amount,
    note
  )
select
  extract(
    year
    from
      current_date
  )::integer + 1,
  a.id,
  cc.id,
  'draft',
  round(b.budget_amount * 1.12, 2),
  'First pass at next year — headcount plan not yet signed off'
from
  finance.budgets b
  join finance.accounts a on a.id = b.account_id
  join finance.cost_centers cc on cc.id = b.cost_center_id
where
  b.fiscal_year = extract(
    year
    from
      current_date
  )
  and a.code in ('5000', '6000', '6300', '6310', '6600');

-- Two company-wide lines. A budget with no cost centre captures every
-- team's spend on that account, which is the right shape for costs
-- nobody owns individually.
insert into
  finance.budgets (
    fiscal_year,
    account_id,
    cost_center_id,
    status,
    budget_amount,
    note
  )
select
  extract(
    year
    from
      current_date
  )::integer,
  a.id,
  null,
  'approved',
  b.amount,
  b.note
from
  (
    values
      (
        '6500',
        130000,
        'Depreciation across the whole register'
      ),
      (
        '5000',
        280000,
        'Total cloud spend, however it is coded'
      )
  ) as b (account_code, amount, note)
  join finance.accounts a on a.code = b.account_code;

select
  finance.recalc_budget_actuals () as budget_actuals_recomputed;

----------------------------------------------------------------
-- Age the history
--
-- Every journal above was posted during this seed run, so each one
-- carries today's timestamp. Each is moved onto the moment it
-- describes, and the timeline events that the triggers filed along
-- the way are moved with them — otherwise every entry in an
-- eighteen-month ledger would claim to have been made this morning.
--
-- Posted journals are immutable, so this is one of the two places
-- that opens finance.posted_write_allowed (). The other is the
-- reversal routine.
----------------------------------------------------------------
do $$
begin
  perform set_config('finance.allow_posted_write', 'on', true);

  update finance.journals
  set posted_at = entry_date::timestamptz + interval '16 hours',
    created_at = entry_date::timestamptz + interval '9 hours',
    posted_by = coalesce(
      posted_by,
      case
        when source in ('manual', 'opening_balance', 'depreciation')
        then 'b73eb03e-fb7a-424d-84ff-18e2791ce0d1'::uuid
        else 'b73eb03e-fb7a-424d-84ff-18e2791ce0d2'::uuid
      end
    )
  where status <> 'draft';

  perform set_config('finance.allow_posted_write', 'off', true);
end;
$$;

update finance.journals
set
  created_at = entry_date::timestamptz + interval '9 hours'
where
  status = 'draft';

update finance.journal_events e
set
  occurred_at = case e.event_type
    when 'created' then j.entry_date::timestamptz + interval '9 hours'
    when 'line_changed' then j.entry_date::timestamptz + interval '11 hours'
    when 'posted' then j.entry_date::timestamptz + interval '16 hours'
    else j.entry_date::timestamptz + interval '17 hours'
  end,
  actor_id = coalesce(
    e.actor_id,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0d2'::uuid
  )
from
  finance.journals j
where
  j.id = e.journal_id;

update finance.invoices
set
  created_at = issue_date::timestamptz + interval '10 hours',
  sent_at = case
    when status = 'draft' then null
    else issue_date::timestamptz + interval '15 hours'
  end,
  paid_at = case
    when status = 'paid' then (
      select
        max(a.allocated_on)::timestamptz + interval '12 hours'
      from
        finance.payment_allocations a
      where
        a.invoice_id = finance.invoices.id
    )
    else null
  end;

update finance.bills
set
  created_at = issue_date::timestamptz + interval '10 hours',
  -- Approval lag varies by supplier rather than being a flat two days
  -- for everybody. Some send a clean invoice against a purchase order
  -- and go through the same afternoon; others send a PDF with the
  -- wrong reference and sit in a queue for a week. That spread is the
  -- only signal in a purchase ledger that says anything about how a
  -- supplier is to deal with, and the service rating below is derived
  -- from it.
  approved_at = case
    when status in ('draft', 'awaiting_approval') then null
    else (
      issue_date + 1 + (abs(hashtext (vendor_id::text)) % 9) + (abs(hashtext (id::text)) % 3)
    )::timestamptz + interval '11 hours'
  end,
  approved_by = case
    when status in ('draft', 'awaiting_approval') then null
    else 'b73eb03e-fb7a-424d-84ff-18e2791ce0d2'::uuid
  end,
  paid_at = case
    when status = 'paid' then (
      select
        max(a.allocated_on)::timestamptz + interval '14 hours'
      from
        finance.payment_allocations a
      where
        a.bill_id = finance.bills.id
    )
    else null
  end;

update finance.payments
set
  created_at = payment_date::timestamptz + interval '12 hours',
  updated_at = payment_date::timestamptz + interval '12 hours';

update finance.payment_allocations
set
  created_at = allocated_on::timestamptz + interval '12 hours';

update finance.expense_claims
set
  created_at = coalesce(
    submitted_at - interval '1 day',
    current_timestamp - interval '2 days'
  ),
  updated_at = coalesce(
    reimbursed_on::timestamptz,
    approved_at,
    submitted_at,
    current_timestamp
  );

update finance.expense_lines l
set
  created_at = l.spent_on::timestamptz + interval '19 hours';

update finance.bank_transactions
set
  created_at = transaction_date::timestamptz + interval '6 hours',
  updated_at = transaction_date::timestamptz + interval '6 hours';

-- Customers and vendors predate the first invoice or bill they appear
-- on, rather than all arriving at go-live.
update finance.customers c
set
  created_at = coalesce(
    (
      select
        min(i.issue_date)
      from
        finance.invoices i
      where
        i.customer_id = c.id
    ) - 21,
    current_date - 400
  )::timestamptz + interval '10 hours';

update finance.vendors v
set
  created_at = coalesce(
    (
      select
        min(b.issue_date)
      from
        finance.bills b
      where
        b.vendor_id = v.id
    ) - 14,
    current_date - 400
  )::timestamptz + interval '10 hours';

----------------------------------------------------------------
-- Month end
--
-- Closing happens in the order it happens in real life, and only now
-- that everything has been posted. Anything older than a year is
-- locked and needs the controller to reopen; the months between then
-- and last month are closed; last month and this month stay open,
-- because last month is still being tidied and this month is still
-- happening.
--
-- The current period cannot be closed at all — it has three draft
-- journals in it, and the period guard will say so.
----------------------------------------------------------------
update finance.fiscal_periods
set
  status = 'future'
where
  starts_on > date_trunc('month', current_date)::date;

update finance.fiscal_periods
set
  status = 'closed',
  closed_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0d2'
where
  status = 'open'
  and ends_on < (
    date_trunc('month', current_date) - interval '1 month'
  )::date;

update finance.fiscal_periods
set
  status = 'locked'
where
  status = 'closed'
  and ends_on < (
    date_trunc('month', current_date) - interval '12 months'
  )::date;

update finance.fiscal_periods
set
  closed_on = ends_on + 8
where
  status in ('closed', 'locked');

----------------------------------------------------------------
-- Judgements, derived from what actually happened
--
-- Credit confidence, credit limits and supplier service are the three
-- columns in this schema that no trigger can compute — which is
-- exactly why they are easy to fill with noise. Filled with noise
-- they are worse than empty: the "Weak Credit" preset returns a
-- customer who has never paid late, and the credit limit sits below
-- the invoices being raised against it.
--
-- So they are set HERE, at the end, from the trading history the rest
-- of this file produced. A credit controller reviews an account on
-- exactly this evidence.
----------------------------------------------------------------
-- Credit confidence: how late they pay, how much is late right now,
-- and whether the account is in trouble. Five is "pays to terms,
-- nothing outstanding"; one is "we are chasing and not getting far".
update finance.customers c
set
  credit_rating = greatest(
    1.0,
    least(
      5.0,
      5.0 - coalesce(x.avg_days_late, 0) * 0.14 - case
        when c.overdue_total > 40000 then 1.6
        when c.overdue_total > 15000 then 0.9
        when c.overdue_total > 0 then 0.4
        else 0
      end - case c.status
        when 'closed' then 2.5
        when 'on_hold' then 1.5
        else 0
      end
    )
  )::real
from
  (
    select
      cu.id,
      (
        select
          avg(greatest(i.paid_at::date - i.due_date, 0))
        from
          finance.invoices i
        where
          i.customer_id = cu.id
          and i.status = 'paid'
      ) as avg_days_late
    from
      finance.customers cu
  ) x
where
  x.id = c.id;

-- Credit limits are reviewed against exposure, not invented. Each is
-- set to roughly twice the largest single invoice the account has
-- run, rounded to something a human would actually write down, and
-- floored so a dormant account still has a working limit.
--
-- A handful still breach: the accounts already in trouble keep the
-- limit they had before anybody noticed, which is why credit control
-- exists and why the over-limit customers are the same ones carrying
-- the overdue balances.
update finance.customers c
set
  credit_limit = case
    when c.status = 'active' then greatest(
      round(coalesce(x.biggest, 0) * 2.0 / 5000) * 5000,
      25000
    )
    else c.credit_limit
  end
from
  (
    select
      cu.id,
      (
        select
          max(i.total)
        from
          finance.invoices i
        where
          i.customer_id = cu.id
          and i.status <> 'void'
      ) as biggest
    from
      finance.customers cu
  ) x
where
  x.id = c.id;

-- Supplier service, read off the one thing a purchase ledger records
-- about how a supplier behaves: how long their paperwork takes to
-- clear approval. A supplier whose invoices go through the next day
-- scores well; one whose invoices sit in a query queue for a week
-- does not.
update finance.vendors v
set
  service_rating = greatest(
    1.0,
    least(5.0, 5.4 - coalesce(x.avg_lag, 3) * 0.38)
  )::real
from
  (
    select
      ve.id,
      (
        select
          avg(b.approved_at::date - b.issue_date)
        from
          finance.bills b
        where
          b.vendor_id = ve.id
          and b.approved_at is not null
      ) as avg_lag
    from
      finance.vendors ve
  ) x
where
  x.id = v.id;

-- Budgets are a plan made before the year started, so they sit near
-- the run rate rather than on top of it — some lines come in under,
-- some over, and the ones that are over are the point of the report.
-- Setting a round number unrelated to actual spend produced a budget
-- board on which nothing was ever overspent.
update finance.budgets b
set
  budget_amount = greatest(
    round(
      (
        b.actual_amount * (
          12.0 / greatest(
            extract(
              month
              from
                current_date
            ),
            1
          )
        )
      ) * (
        -- Spanning both sides of the run rate on purpose. A factor band
        -- sitting entirely above it produces a budget board on which
        -- nothing is ever overspent and the "Over Budget" preset opens
        -- an empty screen.
        0.40 + (abs(hashtext (b.id::text)) % 75)::numeric / 100.0
      ) / 500
    ) * 500,
    1000
  )
where
  b.fiscal_year = extract(
    year
    from
      current_date
  )
  and b.actual_amount > 0;

-- An account goes on hold because of how it behaves, not because a
-- seed picked it. The worst payer with real exposure is the one
-- credit control stopped — which is also why its recent invoices
-- predate the hold rather than contradicting it.
update finance.customers
set
  status = 'active'
where
  status = 'on_hold';

update finance.customers
set
  status = 'on_hold'
where
  id in (
    select
      id
    from
      finance.customers
    where
      status = 'active'
      and overdue_total > 0
    order by
      overdue_total desc
    limit
      2
  );

----------------------------------------------------------------
-- Run the nightly maintenance once, then rebuild the snapshot.
----------------------------------------------------------------
select
  *
from
  finance.run_daily_maintenance ();

refresh materialized view finance.monthly_performance;

select
  supasheet.refresh_metadata ();
