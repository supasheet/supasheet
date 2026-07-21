create schema if not exists finance;

grant usage on schema finance to authenticated;

----------------------------------------------------------------
-- Enums + permissions (must commit before use)
----------------------------------------------------------------
begin;

create type finance.account_type as enum(
  'asset',
  'liability',
  'equity',
  'revenue',
  'expense'
);

create type finance.invoice_status as enum(
  'draft',
  'sent',
  'paid',
  'overdue',
  'cancelled',
  'refunded'
);

create type finance.bill_status as enum(
  'draft',
  'pending',
  'approved',
  'paid',
  'overdue',
  'cancelled'
);

create type finance.expense_status as enum(
  'draft',
  'submitted',
  'approved',
  'rejected',
  'reimbursed'
);

create type finance.expense_category as enum(
  'travel',
  'meals',
  'lodging',
  'office',
  'software',
  'training',
  'marketing',
  'other'
);

create type finance.payment_method as enum(
  'bank_transfer',
  'credit_card',
  'check',
  'cash',
  'wire',
  'ach'
);

create type finance.payment_direction as enum('incoming', 'outgoing');

create type finance.payment_status as enum('pending', 'completed', 'failed', 'refunded');

create type finance.budget_period as enum('monthly', 'quarterly', 'annual');

create type finance.payroll_status as enum('draft', 'processing', 'completed', 'cancelled');

create type finance.payslip_status as enum('pending', 'issued', 'paid');

create type finance.journal_status as enum('draft', 'posted', 'reversed');

commit;

----------------------------------------------------------------
-- Users mirror view
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
  authenticated,
  service_role;

grant
select
  on finance.users to "x-admin";

----------------------------------------------------------------
-- Accounts (Chart of Accounts)
----------------------------------------------------------------
create table finance.accounts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(50) unique not null,
  name varchar(255) not null,
  type finance.account_type not null,
  parent_id uuid references finance.accounts (id) on delete set null,
  description supasheet.RICH_TEXT,
  currency varchar(3) default 'USD',
  opening_balance numeric(14, 2) default 0,
  current_balance numeric(14, 2) default 0,
  is_active boolean default true,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column finance.accounts.type is '{
    "progress": false,
    "enums": {
        "asset":     {"variant": "success",     "icon": "Landmark"},
        "liability": {"variant": "destructive", "icon": "AlertTriangle"},
        "equity":    {"variant": "info",        "icon": "PieChart"},
        "revenue":   {"variant": "success",     "icon": "TrendingUp"},
        "expense":   {"variant": "warning",     "icon": "TrendingDown"}
    }
}';

comment on table finance.accounts is '{
    "icon": "BookOpen",
    "display": "block",
    "group": "Operations",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Accounts By Type",
            "type": "kanban",
            "group": "type",
            "title": "name",
            "description": "code",
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
                    "type",
                    "description"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "parent_id",
                    "is_active",
                    "color"
                ]
            },
            {
                "id": "balances",
                "title": "Balances",
                "fields": [
                    "currency",
                    "opening_balance",
                    "current_balance"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "code",
                "desc": false
            }
        ]
    }
}';

revoke all on table finance.accounts
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table finance.accounts to "x-admin";

create index idx_finance_accounts_parent_id on finance.accounts (parent_id);

create index idx_finance_accounts_type on finance.accounts (type);

create index idx_finance_accounts_code on finance.accounts (code);

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
-- Vendors
----------------------------------------------------------------
create table finance.vendors (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(500) not null,
  legal_name varchar(500),
  code varchar(50) unique,
  website supasheet.URL,
  email supasheet.EMAIL,
  phone supasheet.TEL,
  address text,
  city varchar(255),
  country varchar(255),
  tax_id varchar(100),
  payment_terms varchar(100),
  logo supasheet.file,
  description supasheet.RICH_TEXT,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table finance.vendors is '{
    "icon": "Truck",
    "display": "block",
    "group": "Operations",
    "primary_view": "gallery",
    "views": [
        {
            "id": "gallery",
            "name": "Vendor Gallery",
            "type": "gallery",
            "cover": "logo",
            "title": "name",
            "description": "city",
            "badge": "country"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "name",
                    "legal_name",
                    "code",
                    "logo",
                    "description"
                ]
            },
            {
                "id": "contact",
                "title": "Contact",
                "fields": [
                    "website",
                    "email",
                    "phone"
                ]
            },
            {
                "id": "address",
                "title": "Address",
                "fields": [
                    "address",
                    "city",
                    "country"
                ]
            },
            {
                "id": "financial",
                "title": "Financial",
                "fields": [
                    "tax_id",
                    "payment_terms"
                ]
            },
            {
                "id": "extras",
                "title": "Tags & Notes",
                "collapsible": true,
                "fields": [
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
            }
        ]
    }
}';

comment on column finance.vendors.logo is '{"accept":"image/*"}';

revoke all on table finance.vendors
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table finance.vendors to "x-admin";

create index idx_finance_vendors_user_id on finance.vendors (user_id);

create index idx_finance_vendors_country on finance.vendors (country);

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
-- Invoices (Accounts Receivable)
----------------------------------------------------------------
create table finance.invoices (
  id uuid primary key default extensions.uuid_generate_v4 (),
  invoice_number varchar(50) unique not null,
  customer_name varchar(500) not null,
  customer_email supasheet.EMAIL,
  customer_address text,
  status finance.invoice_status default 'draft',
  issue_date date not null,
  due_date date,
  paid_date date,
  subtotal numeric(14, 2) default 0,
  tax numeric(14, 2) default 0,
  total numeric(14, 2) default 0,
  amount_paid numeric(14, 2) default 0,
  currency varchar(3) default 'USD',
  description supasheet.RICH_TEXT,
  line_items jsonb,
  revenue_account_id uuid references finance.accounts (id) on delete set null,
  attachments supasheet.file,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column finance.invoices.status is '{
    "progress": true,
    "enums": {
        "draft":     {"variant": "outline",     "icon": "FileEdit"},
        "sent":      {"variant": "info",        "icon": "Send"},
        "paid":      {"variant": "success",     "icon": "CircleCheck"},
        "overdue":   {"variant": "destructive", "icon": "AlertTriangle"},
        "cancelled": {"variant": "outline",     "icon": "Ban"},
        "refunded":  {"variant": "warning",     "icon": "RotateCcw"}
    }
}';

comment on table finance.invoices is '{
    "icon": "Receipt",
    "display": "block",
    "group": "Operations",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Invoices By Status",
            "type": "kanban",
            "group": "status",
            "title": "invoice_number",
            "description": "customer_name",
            "date": "due_date",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Invoice Calendar",
            "type": "calendar",
            "title": "invoice_number",
            "badge": "status",
            "start_date": "issue_date",
            "end_date": "due_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "invoice_number",
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
                    "customer_address"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "issue_date",
                    "due_date",
                    "paid_date"
                ]
            },
            {
                "id": "amounts",
                "title": "Amounts",
                "fields": [
                    "subtotal",
                    "tax",
                    "total",
                    "amount_paid",
                    "currency"
                ]
            },
            {
                "id": "accounting",
                "title": "Accounting",
                "fields": [
                    "revenue_account_id",
                    "line_items"
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
                "id": "issue_date",
                "desc": true
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
                "table": "accounts",
                "on": "revenue_account_id",
                "columns": [
                    "code",
                    "name"
                ]
            }
        ]
    }
}';

comment on column finance.invoices.attachments is '{"accept":"*", "maxFiles": 20}';

revoke all on table finance.invoices
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table finance.invoices to "x-admin";

create index idx_finance_invoices_user_id on finance.invoices (user_id);

create index idx_finance_invoices_status on finance.invoices (status);

create index idx_finance_invoices_issue_date on finance.invoices (issue_date desc);

create index idx_finance_invoices_due_date on finance.invoices (due_date);

create index idx_finance_invoices_customer_email on finance.invoices (customer_email);

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

----------------------------------------------------------------
-- Bills (Accounts Payable)
----------------------------------------------------------------
create table finance.bills (
  id uuid primary key default extensions.uuid_generate_v4 (),
  bill_number varchar(50) unique not null,
  vendor_id uuid references finance.vendors (id) on delete set null,
  status finance.bill_status default 'draft',
  issue_date date not null,
  due_date date,
  paid_date date,
  subtotal numeric(14, 2) default 0,
  tax numeric(14, 2) default 0,
  total numeric(14, 2) default 0,
  amount_paid numeric(14, 2) default 0,
  currency varchar(3) default 'USD',
  description supasheet.RICH_TEXT,
  line_items jsonb,
  expense_account_id uuid references finance.accounts (id) on delete set null,
  attachments supasheet.file,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column finance.bills.status is '{
    "progress": true,
    "enums": {
        "draft":     {"variant": "outline",     "icon": "FileEdit"},
        "pending":   {"variant": "warning",     "icon": "Clock"},
        "approved":  {"variant": "info",        "icon": "BadgeCheck"},
        "paid":      {"variant": "success",     "icon": "CircleCheck"},
        "overdue":   {"variant": "destructive", "icon": "AlertTriangle"},
        "cancelled": {"variant": "outline",     "icon": "Ban"}
    }
}';

comment on table finance.bills is '{
    "icon": "FileText",
    "display": "block",
    "group": "Operations",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Bills By Status",
            "type": "kanban",
            "group": "status",
            "title": "bill_number",
            "description": "description",
            "date": "due_date",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Bill Calendar",
            "type": "calendar",
            "title": "bill_number",
            "badge": "status",
            "start_date": "issue_date",
            "end_date": "due_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "bill_number",
                    "vendor_id",
                    "status",
                    "description"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "issue_date",
                    "due_date",
                    "paid_date"
                ]
            },
            {
                "id": "amounts",
                "title": "Amounts",
                "fields": [
                    "subtotal",
                    "tax",
                    "total",
                    "amount_paid",
                    "currency"
                ]
            },
            {
                "id": "accounting",
                "title": "Accounting",
                "fields": [
                    "expense_account_id",
                    "line_items"
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
                "id": "issue_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "vendors",
                "on": "vendor_id",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "accounts",
                "on": "expense_account_id",
                "columns": [
                    "code",
                    "name"
                ]
            },
            {
                "table": "users",
                "on": "user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column finance.bills.attachments is '{"accept":"*", "maxFiles": 20}';

revoke all on table finance.bills
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table finance.bills to "x-admin";

create index idx_finance_bills_user_id on finance.bills (user_id);

create index idx_finance_bills_vendor_id on finance.bills (vendor_id);

create index idx_finance_bills_status on finance.bills (status);

create index idx_finance_bills_issue_date on finance.bills (issue_date desc);

create index idx_finance_bills_due_date on finance.bills (due_date);

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

----------------------------------------------------------------
-- Expenses (employee expense claims)
----------------------------------------------------------------
create table finance.expenses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  expense_number varchar(50) unique not null,
  employee_name varchar(500) not null,
  employee_email supasheet.EMAIL,
  category finance.expense_category default 'other',
  status finance.expense_status default 'draft',
  amount numeric(14, 2) not null default 0,
  currency varchar(3) default 'USD',
  expense_date date not null,
  description supasheet.RICH_TEXT,
  merchant varchar(255),
  payment_method finance.payment_method,
  expense_account_id uuid references finance.accounts (id) on delete set null,
  receipt supasheet.file,
  attachments supasheet.file,
  reviewer_user_id uuid references supasheet.users (id) on delete set null,
  reviewed_at timestamptz,
  response text,
  reimbursed_at timestamptz,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column finance.expenses.status is '{
    "progress": true,
    "enums": {
        "draft":      {"variant": "outline",     "icon": "FileEdit"},
        "submitted":  {"variant": "info",        "icon": "Send"},
        "approved":   {"variant": "success",     "icon": "BadgeCheck"},
        "rejected":   {"variant": "destructive", "icon": "XCircle"},
        "reimbursed": {"variant": "success",     "icon": "CircleCheck"}
    }
}';

comment on column finance.expenses.category is '{
    "progress": false,
    "enums": {
        "travel":    {"variant": "info",      "icon": "Plane"},
        "meals":     {"variant": "warning",   "icon": "Utensils"},
        "lodging":   {"variant": "info",      "icon": "Hotel"},
        "office":    {"variant": "secondary", "icon": "Building"},
        "software":  {"variant": "info",      "icon": "Laptop"},
        "training":  {"variant": "success",   "icon": "GraduationCap"},
        "marketing": {"variant": "warning",   "icon": "Megaphone"},
        "other":     {"variant": "outline",   "icon": "CircleEllipsis"}
    }
}';

comment on column finance.expenses.payment_method is '{
    "progress": false,
    "enums": {
        "bank_transfer": {"variant": "info",     "icon": "Landmark"},
        "credit_card":   {"variant": "warning",  "icon": "CreditCard"},
        "check":         {"variant": "outline",  "icon": "FileSignature"},
        "cash":          {"variant": "success",  "icon": "Banknote"},
        "wire":          {"variant": "info",     "icon": "Globe"},
        "ach":           {"variant": "info",     "icon": "ArrowLeftRight"}
    }
}';

comment on table finance.expenses is '{
    "icon": "Wallet",
    "display": "block",
    "group": "Operations",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Expenses By Status",
            "type": "kanban",
            "group": "status",
            "title": "expense_number",
            "description": "merchant",
            "date": "expense_date",
            "badge": "category"
        },
        {
            "id": "calendar",
            "name": "Expense Calendar",
            "type": "calendar",
            "title": "expense_number",
            "badge": "status",
            "start_date": "expense_date",
            "end_date": "expense_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "expense_number",
                    "employee_name",
                    "employee_email",
                    "status",
                    "category"
                ]
            },
            {
                "id": "amount",
                "title": "Amount",
                "fields": [
                    "amount",
                    "currency",
                    "payment_method"
                ]
            },
            {
                "id": "details",
                "title": "Details",
                "fields": [
                    "expense_date",
                    "merchant",
                    "description",
                    "expense_account_id"
                ]
            },
            {
                "id": "review",
                "title": "Review",
                "fields": [
                    "reviewer_user_id",
                    "reviewed_at",
                    "response",
                    "reimbursed_at"
                ]
            },
            {
                "id": "extras",
                "title": "Receipt & Notes",
                "collapsible": true,
                "fields": [
                    "receipt",
                    "attachments",
                    "tags",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "expense_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "users",
                "on": "user_id",
                "alias": "user",
                "columns": [
                    "name",
                    "email"
                ]
            },
            {
                "table": "users",
                "on": "reviewer_user_id",
                "alias": "reviewer_user",
                "columns": [
                    "name",
                    "email"
                ]
            },
            {
                "table": "accounts",
                "on": "expense_account_id",
                "columns": [
                    "code",
                    "name"
                ]
            }
        ]
    }
}';

comment on column finance.expenses.receipt is '{"accept":"image/*,application/pdf", "maxFiles": 5}';

comment on column finance.expenses.attachments is '{"accept":"*", "maxFiles": 10}';

revoke all on table finance.expenses
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table finance.expenses to "x-admin";

create index idx_finance_expenses_user_id on finance.expenses (user_id);

create index idx_finance_expenses_reviewer_user_id on finance.expenses (reviewer_user_id);

create index idx_finance_expenses_status on finance.expenses (status);

create index idx_finance_expenses_category on finance.expenses (category);

create index idx_finance_expenses_expense_date on finance.expenses (expense_date desc);

alter table finance.expenses enable row level security;

create policy expenses_select on finance.expenses for
select
  to authenticated using (true);

create policy expenses_insert on finance.expenses for insert to authenticated
with
  check (true);

create policy expenses_update on finance.expenses
for update
  to authenticated using (true)
with
  check (true);

create policy expenses_delete on finance.expenses for delete to authenticated using (true);

----------------------------------------------------------------
-- Payments (incoming/outgoing)
----------------------------------------------------------------
create table finance.payments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  payment_number varchar(50) unique not null,
  direction finance.payment_direction not null default 'incoming',
  status finance.payment_status default 'pending',
  method finance.payment_method default 'bank_transfer',
  amount numeric(14, 2) not null default 0,
  currency varchar(3) default 'USD',
  payment_date date not null,
  reference_number varchar(255),
  party_name varchar(500),
  party_email supasheet.EMAIL,
  invoice_id uuid references finance.invoices (id) on delete set null,
  bill_id uuid references finance.bills (id) on delete set null,
  account_id uuid references finance.accounts (id) on delete set null,
  description supasheet.RICH_TEXT,
  attachments supasheet.file,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column finance.payments.direction is '{
    "progress": false,
    "enums": {
        "incoming": {"variant": "success",     "icon": "ArrowDownLeft"},
        "outgoing": {"variant": "destructive", "icon": "ArrowUpRight"}
    }
}';

comment on column finance.payments.status is '{
    "progress": true,
    "enums": {
        "pending":   {"variant": "warning",     "icon": "Clock"},
        "completed": {"variant": "success",     "icon": "CircleCheck"},
        "failed":    {"variant": "destructive", "icon": "XCircle"},
        "refunded":  {"variant": "outline",     "icon": "RotateCcw"}
    }
}';

comment on column finance.payments.method is '{
    "progress": false,
    "enums": {
        "bank_transfer": {"variant": "info",     "icon": "Landmark"},
        "credit_card":   {"variant": "warning",  "icon": "CreditCard"},
        "check":         {"variant": "outline",  "icon": "FileSignature"},
        "cash":          {"variant": "success",  "icon": "Banknote"},
        "wire":          {"variant": "info",     "icon": "Globe"},
        "ach":           {"variant": "info",     "icon": "ArrowLeftRight"}
    }
}';

comment on table finance.payments is '{
    "icon": "ArrowLeftRight",
    "display": "block",
    "group": "Operations",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Payments By Status",
            "type": "kanban",
            "group": "status",
            "title": "payment_number",
            "description": "party_name",
            "date": "payment_date",
            "badge": "direction"
        },
        {
            "id": "calendar",
            "name": "Payment Calendar",
            "type": "calendar",
            "title": "payment_number",
            "badge": "status",
            "start_date": "payment_date",
            "end_date": "payment_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "payment_number",
                    "direction",
                    "status",
                    "method"
                ]
            },
            {
                "id": "party",
                "title": "Party",
                "fields": [
                    "party_name",
                    "party_email"
                ]
            },
            {
                "id": "amount",
                "title": "Amount",
                "fields": [
                    "amount",
                    "currency",
                    "payment_date",
                    "reference_number"
                ]
            },
            {
                "id": "links",
                "title": "Links",
                "fields": [
                    "invoice_id",
                    "bill_id",
                    "account_id"
                ]
            },
            {
                "id": "extras",
                "title": "Description, Attachments & Notes",
                "collapsible": true,
                "fields": [
                    "description",
                    "attachments",
                    "tags",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "payment_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "invoices",
                "on": "invoice_id",
                "columns": [
                    "invoice_number",
                    "customer_name"
                ]
            },
            {
                "table": "bills",
                "on": "bill_id",
                "columns": [
                    "bill_number"
                ]
            },
            {
                "table": "accounts",
                "on": "account_id",
                "columns": [
                    "code",
                    "name"
                ]
            }
        ]
    }
}';

comment on column finance.payments.attachments is '{"accept":"*", "maxFiles": 10}';

revoke all on table finance.payments
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table finance.payments to "x-admin";

create index idx_finance_payments_user_id on finance.payments (user_id);

create index idx_finance_payments_invoice_id on finance.payments (invoice_id);

create index idx_finance_payments_bill_id on finance.payments (bill_id);

create index idx_finance_payments_account_id on finance.payments (account_id);

create index idx_finance_payments_status on finance.payments (status);

create index idx_finance_payments_direction on finance.payments (direction);

create index idx_finance_payments_payment_date on finance.payments (payment_date desc);

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

----------------------------------------------------------------
-- Budgets
----------------------------------------------------------------
create table finance.budgets (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(500) not null,
  period finance.budget_period default 'monthly',
  period_start date not null,
  period_end date not null,
  department varchar(255),
  account_id uuid references finance.accounts (id) on delete set null,
  amount numeric(14, 2) not null default 0,
  spent numeric(14, 2) default 0,
  currency varchar(3) default 'USD',
  description supasheet.RICH_TEXT,
  color supasheet.COLOR,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column finance.budgets.period is '{
    "progress": false,
    "enums": {
        "monthly":   {"variant": "info",      "icon": "Calendar"},
        "quarterly": {"variant": "warning",   "icon": "CalendarRange"},
        "annual":    {"variant": "success",   "icon": "CalendarDays"}
    }
}';

comment on table finance.budgets is '{
    "icon": "PiggyBank",
    "display": "block",
    "group": "Operations",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Budgets By Period",
            "type": "kanban",
            "group": "period",
            "title": "name",
            "description": "department",
            "date": "period_start",
            "badge": "period"
        },
        {
            "id": "calendar",
            "name": "Budget Calendar",
            "type": "calendar",
            "title": "name",
            "badge": "period",
            "start_date": "period_start",
            "end_date": "period_end"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "name",
                    "department",
                    "period",
                    "description"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "period_start",
                    "period_end"
                ]
            },
            {
                "id": "amounts",
                "title": "Amounts",
                "fields": [
                    "amount",
                    "spent",
                    "currency",
                    "account_id"
                ]
            },
            {
                "id": "extras",
                "title": "Tags & Notes",
                "collapsible": true,
                "fields": [
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
                "id": "period_start",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "accounts",
                "on": "account_id",
                "columns": [
                    "code",
                    "name"
                ]
            },
            {
                "table": "users",
                "on": "user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

revoke all on table finance.budgets
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table finance.budgets to "x-admin";

create index idx_finance_budgets_user_id on finance.budgets (user_id);

create index idx_finance_budgets_account_id on finance.budgets (account_id);

create index idx_finance_budgets_period on finance.budgets (period);

create index idx_finance_budgets_period_start on finance.budgets (period_start desc);

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

----------------------------------------------------------------
-- Payroll runs
----------------------------------------------------------------
create table finance.payroll_runs (
  id uuid primary key default extensions.uuid_generate_v4 (),
  run_number varchar(50) unique not null,
  period_start date not null,
  period_end date not null,
  pay_date date not null,
  status finance.payroll_status default 'draft',
  total_gross numeric(14, 2) default 0,
  total_deductions numeric(14, 2) default 0,
  total_tax numeric(14, 2) default 0,
  total_net numeric(14, 2) default 0,
  currency varchar(3) default 'USD',
  employee_count integer default 0,
  description supasheet.RICH_TEXT,
  attachments supasheet.file,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column finance.payroll_runs.status is '{
    "progress": true,
    "enums": {
        "draft":      {"variant": "outline",     "icon": "FileEdit"},
        "processing": {"variant": "info",        "icon": "Loader"},
        "completed":  {"variant": "success",     "icon": "CircleCheck"},
        "cancelled":  {"variant": "destructive", "icon": "Ban"}
    }
}';

comment on table finance.payroll_runs is '{
    "icon": "Banknote",
    "display": "block",
    "group": "Payroll",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Payroll Runs By Status",
            "type": "kanban",
            "group": "status",
            "title": "run_number",
            "description": "description",
            "date": "pay_date",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Payroll Calendar",
            "type": "calendar",
            "title": "run_number",
            "badge": "status",
            "start_date": "period_start",
            "end_date": "pay_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "run_number",
                    "status",
                    "description"
                ]
            },
            {
                "id": "period",
                "title": "Period",
                "fields": [
                    "period_start",
                    "period_end",
                    "pay_date"
                ]
            },
            {
                "id": "totals",
                "title": "Totals",
                "fields": [
                    "total_gross",
                    "total_deductions",
                    "total_tax",
                    "total_net",
                    "currency",
                    "employee_count"
                ]
            },
            {
                "id": "extras",
                "title": "Attachments & Notes",
                "collapsible": true,
                "fields": [
                    "attachments",
                    "tags",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "pay_date",
                "desc": true
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
            }
        ]
    }
}';

comment on column finance.payroll_runs.attachments is '{"accept":"*", "maxFiles": 20}';

revoke all on table finance.payroll_runs
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table finance.payroll_runs to "x-admin";

create index idx_finance_payroll_runs_user_id on finance.payroll_runs (user_id);

create index idx_finance_payroll_runs_status on finance.payroll_runs (status);

create index idx_finance_payroll_runs_pay_date on finance.payroll_runs (pay_date desc);

alter table finance.payroll_runs enable row level security;

create policy payroll_runs_select on finance.payroll_runs for
select
  to authenticated using (true);

create policy payroll_runs_insert on finance.payroll_runs for insert to authenticated
with
  check (true);

create policy payroll_runs_update on finance.payroll_runs
for update
  to authenticated using (true)
with
  check (true);

create policy payroll_runs_delete on finance.payroll_runs for delete to authenticated using (true);

----------------------------------------------------------------
-- Payslips
----------------------------------------------------------------
create table finance.payslips (
  id uuid primary key default extensions.uuid_generate_v4 (),
  payslip_number varchar(50) unique not null,
  run_id uuid not null references finance.payroll_runs (id) on delete cascade,
  employee_name varchar(500) not null,
  employee_email supasheet.EMAIL,
  employee_user_id uuid references supasheet.users (id) on delete set null,
  status finance.payslip_status default 'pending',
  currency varchar(3) default 'USD',
  base_salary numeric(14, 2) default 0,
  bonuses numeric(14, 2) default 0,
  overtime numeric(14, 2) default 0,
  gross_salary numeric(14, 2) default 0,
  tax_withheld numeric(14, 2) default 0,
  social_security numeric(14, 2) default 0,
  health_insurance numeric(14, 2) default 0,
  retirement numeric(14, 2) default 0,
  other_deductions numeric(14, 2) default 0,
  net_salary numeric(14, 2) default 0,
  hours_worked numeric(8, 2),
  payment_method finance.payment_method default 'bank_transfer',
  paid_at timestamptz,
  attachments supasheet.file,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column finance.payslips.status is '{
    "progress": true,
    "enums": {
        "pending": {"variant": "warning", "icon": "Clock"},
        "issued":  {"variant": "info",    "icon": "Send"},
        "paid":    {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on table finance.payslips is '{
    "icon": "FileSpreadsheet",
    "display": "block",
    "group": "Payroll",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Payslips By Status",
            "type": "kanban",
            "group": "status",
            "title": "payslip_number",
            "description": "employee_name",
            "date": "paid_at",
            "badge": "payment_method"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "payslip_number",
                    "run_id",
                    "status"
                ]
            },
            {
                "id": "employee",
                "title": "Employee",
                "fields": [
                    "employee_name",
                    "employee_email",
                    "employee_user_id"
                ]
            },
            {
                "id": "earnings",
                "title": "Earnings",
                "fields": [
                    "base_salary",
                    "bonuses",
                    "overtime",
                    "gross_salary",
                    "hours_worked",
                    "currency"
                ]
            },
            {
                "id": "deductions",
                "title": "Deductions",
                "fields": [
                    "tax_withheld",
                    "social_security",
                    "health_insurance",
                    "retirement",
                    "other_deductions"
                ]
            },
            {
                "id": "net",
                "title": "Net & Payment",
                "fields": [
                    "net_salary",
                    "payment_method",
                    "paid_at"
                ]
            },
            {
                "id": "extras",
                "title": "Attachments & Notes",
                "collapsible": true,
                "fields": [
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
                "table": "payroll_runs",
                "on": "run_id",
                "columns": [
                    "run_number",
                    "pay_date"
                ]
            },
            {
                "table": "users",
                "on": "employee_user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column finance.payslips.attachments is '{"accept":"*", "maxFiles": 10}';

revoke all on table finance.payslips
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table finance.payslips to "x-admin";

create index idx_finance_payslips_run_id on finance.payslips (run_id);

create index idx_finance_payslips_employee_user_id on finance.payslips (employee_user_id);

create index idx_finance_payslips_status on finance.payslips (status);

create index idx_finance_payslips_employee_email on finance.payslips (employee_email);

alter table finance.payslips enable row level security;

create policy payslips_select on finance.payslips for
select
  to authenticated using (true);

create policy payslips_insert on finance.payslips for insert to authenticated
with
  check (true);

create policy payslips_update on finance.payslips
for update
  to authenticated using (true)
with
  check (true);

create policy payslips_delete on finance.payslips for delete to authenticated using (true);

----------------------------------------------------------------
-- Journal entries (general ledger)
----------------------------------------------------------------
create table finance.journal_entries (
  id uuid primary key default extensions.uuid_generate_v4 (),
  entry_number varchar(50) unique not null,
  entry_date date not null,
  status finance.journal_status default 'draft',
  debit_account_id uuid references finance.accounts (id) on delete set null,
  credit_account_id uuid references finance.accounts (id) on delete set null,
  amount numeric(14, 2) not null default 0,
  currency varchar(3) default 'USD',
  description supasheet.RICH_TEXT,
  reference_type varchar(50),
  reference_id uuid,
  attachments supasheet.file,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column finance.journal_entries.status is '{
    "progress": true,
    "enums": {
        "draft":    {"variant": "outline",     "icon": "FileEdit"},
        "posted":   {"variant": "success",     "icon": "CircleCheck"},
        "reversed": {"variant": "destructive", "icon": "RotateCcw"}
    }
}';

comment on table finance.journal_entries is '{
    "icon": "BookText",
    "display": "block",
    "group": "Operations",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Entries By Status",
            "type": "kanban",
            "group": "status",
            "title": "entry_number",
            "description": "description",
            "date": "entry_date",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Entry Calendar",
            "type": "calendar",
            "title": "entry_number",
            "badge": "status",
            "start_date": "entry_date",
            "end_date": "entry_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "entry_number",
                    "entry_date",
                    "status",
                    "description"
                ]
            },
            {
                "id": "accounts",
                "title": "Accounts",
                "fields": [
                    "debit_account_id",
                    "credit_account_id",
                    "amount",
                    "currency"
                ]
            },
            {
                "id": "reference",
                "title": "Reference",
                "fields": [
                    "reference_type",
                    "reference_id"
                ]
            },
            {
                "id": "extras",
                "title": "Attachments & Notes",
                "collapsible": true,
                "fields": [
                    "attachments",
                    "tags",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "entry_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "accounts",
                "on": "debit_account_id",
                "alias": "debit_account",
                "columns": [
                    "code",
                    "name"
                ]
            },
            {
                "table": "accounts",
                "on": "credit_account_id",
                "alias": "credit_account",
                "columns": [
                    "code",
                    "name"
                ]
            },
            {
                "table": "users",
                "on": "user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column finance.journal_entries.attachments is '{"accept":"*", "maxFiles": 10}';

revoke all on table finance.journal_entries
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table finance.journal_entries to "x-admin";

create index idx_finance_journal_entries_user_id on finance.journal_entries (user_id);

create index idx_finance_journal_entries_debit_account_id on finance.journal_entries (debit_account_id);

create index idx_finance_journal_entries_credit_account_id on finance.journal_entries (credit_account_id);

create index idx_finance_journal_entries_status on finance.journal_entries (status);

create index idx_finance_journal_entries_entry_date on finance.journal_entries (entry_date desc);

alter table finance.journal_entries enable row level security;

create policy journal_entries_select on finance.journal_entries for
select
  to authenticated using (true);

create policy journal_entries_insert on finance.journal_entries for insert to authenticated
with
  check (true);

create policy journal_entries_update on finance.journal_entries
for update
  to authenticated using (true)
with
  check (true);

create policy journal_entries_delete on finance.journal_entries for delete to authenticated using (true);

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view finance.invoices_report
with
  (security_invoker = true) as
select
  i.id,
  i.invoice_number,
  i.customer_name,
  i.customer_email,
  i.status,
  i.issue_date,
  i.due_date,
  i.paid_date,
  i.total,
  i.amount_paid,
  (i.total - i.amount_paid) as amount_due,
  i.currency,
  case
    when i.status = 'paid' then 0
    when i.due_date is null then null
    else greatest(0, (current_date - i.due_date))::int
  end as days_overdue,
  a.code as revenue_account_code,
  a.name as revenue_account_name,
  u.name as owner,
  i.created_at,
  i.updated_at
from
  finance.invoices i
  left join finance.accounts a on a.id = i.revenue_account_id
  left join supasheet.users u on u.id = i.user_id;

revoke all on finance.invoices_report
from
  authenticated,
  service_role;

grant
select
  on finance.invoices_report to "x-admin";

comment on view finance.invoices_report is '{"type": "report", "name": "Invoices Report", "description": "All invoices with aging and account info"}';

create or replace view finance.bills_report
with
  (security_invoker = true) as
select
  b.id,
  b.bill_number,
  v.name as vendor,
  b.status,
  b.issue_date,
  b.due_date,
  b.paid_date,
  b.total,
  b.amount_paid,
  (b.total - b.amount_paid) as amount_due,
  b.currency,
  case
    when b.status = 'paid' then 0
    when b.due_date is null then null
    else greatest(0, (current_date - b.due_date))::int
  end as days_overdue,
  a.code as expense_account_code,
  a.name as expense_account_name,
  b.created_at,
  b.updated_at
from
  finance.bills b
  left join finance.vendors v on v.id = b.vendor_id
  left join finance.accounts a on a.id = b.expense_account_id;

revoke all on finance.bills_report
from
  authenticated,
  service_role;

grant
select
  on finance.bills_report to "x-admin";

comment on view finance.bills_report is '{"type": "report", "name": "Bills Report", "description": "All bills with vendor and aging info"}';

create or replace view finance.expenses_report
with
  (security_invoker = true) as
select
  e.id,
  e.expense_number,
  e.employee_name,
  e.employee_email,
  e.category,
  e.status,
  e.amount,
  e.currency,
  e.expense_date,
  e.merchant,
  e.payment_method,
  a.code as account_code,
  a.name as account_name,
  r.name as reviewer,
  e.reviewed_at,
  e.reimbursed_at,
  e.created_at
from
  finance.expenses e
  left join finance.accounts a on a.id = e.expense_account_id
  left join supasheet.users r on r.id = e.reviewer_user_id;

revoke all on finance.expenses_report
from
  authenticated,
  service_role;

grant
select
  on finance.expenses_report to "x-admin";

comment on view finance.expenses_report is '{"type": "report", "name": "Expenses Report", "description": "Employee expense claims with reviewer"}';

create or replace view finance.payroll_report
with
  (security_invoker = true) as
select
  ps.id,
  ps.payslip_number,
  pr.run_number,
  pr.pay_date,
  ps.employee_name,
  ps.employee_email,
  ps.status,
  ps.gross_salary,
  ps.tax_withheld,
  (
    ps.social_security + ps.health_insurance + ps.retirement + ps.other_deductions
  ) as total_deductions,
  ps.net_salary,
  ps.currency,
  ps.payment_method,
  ps.paid_at,
  ps.created_at
from
  finance.payslips ps
  left join finance.payroll_runs pr on pr.id = ps.run_id;

revoke all on finance.payroll_report
from
  authenticated,
  service_role;

grant
select
  on finance.payroll_report to "x-admin";

comment on view finance.payroll_report is '{"type": "report", "name": "Payroll Report", "description": "All payslips with payroll run info"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: total revenue (paid invoices) this year
create or replace view finance.revenue_summary
with
  (security_invoker = true) as
select
  coalesce(sum(total), 0) as value,
  'trending-up' as icon,
  'revenue (YTD)' as label
from
  finance.invoices
where
  status = 'paid'
  and issue_date >= date_trunc('year', current_date);

revoke all on finance.revenue_summary
from
  authenticated,
  service_role;

grant
select
  on finance.revenue_summary to "x-admin";

-- card_2: AR vs AP outstanding
create or replace view finance.ar_ap_split
with
  (security_invoker = true) as
select
  coalesce(
    sum(i.total - i.amount_paid) filter (
      where
        i.status in ('sent', 'overdue')
    ),
    0
  )::bigint as primary,
  coalesce(
    sum(b.total - b.amount_paid) filter (
      where
        b.status in ('pending', 'approved', 'overdue')
    ),
    0
  )::bigint as secondary,
  'Receivable' as primary_label,
  'Payable' as secondary_label
from
  finance.invoices i
  full outer join finance.bills b on false;

revoke all on finance.ar_ap_split
from
  authenticated,
  service_role;

grant
select
  on finance.ar_ap_split to "x-admin";

-- card_3: cash position (in - out, last 30d) + collection %
create or replace view finance.cash_position
with
  (security_invoker = true) as
select
  coalesce(
    sum(amount) filter (
      where
        direction = 'incoming'
        and status = 'completed'
    ),
    0
  ) - coalesce(
    sum(amount) filter (
      where
        direction = 'outgoing'
        and status = 'completed'
    ),
    0
  ) as value,
  case
    when count(*) filter (
      where
        direction = 'incoming'
    ) > 0 then round(
      (
        count(*) filter (
          where
            direction = 'incoming'
            and status = 'completed'
        )::numeric / count(*) filter (
          where
            direction = 'incoming'
        )::numeric
      ) * 100,
      1
    )
    else 0
  end as percent
from
  finance.payments
where
  payment_date >= current_date - interval '30 days';

revoke all on finance.cash_position
from
  authenticated,
  service_role;

grant
select
  on finance.cash_position to "x-admin";

-- card_4: financial health (overdue + at-risk)
create or replace view finance.financial_health
with
  (security_invoker = true) as
with
  metrics as (
    select
      (
        select
          count(*)
        from
          finance.invoices
        where
          status in ('sent', 'overdue')
          and due_date is not null
          and due_date < current_date
      ) as overdue_invoices,
      (
        select
          count(*)
        from
          finance.bills
        where
          status in ('pending', 'approved', 'overdue')
          and due_date is not null
          and due_date < current_date
      ) as overdue_bills,
      (
        select
          count(*)
        from
          finance.expenses
        where
          status = 'submitted'
          and expense_date < current_date - interval '7 days'
      ) as stale_expenses,
      (
        select
          count(*)
        from
          finance.invoices
        where
          status in ('sent', 'overdue', 'draft')
      ) as open_total
  )
select
  (overdue_invoices + overdue_bills + stale_expenses) as current,
  open_total as total,
  json_build_array(
    json_build_object(
      'label',
      'Overdue invoices',
      'value',
      overdue_invoices
    ),
    json_build_object('label', 'Overdue bills', 'value', overdue_bills),
    json_build_object(
      'label',
      'Stale expenses',
      'value',
      stale_expenses
    )
  ) as segments
from
  metrics;

revoke all on finance.financial_health
from
  authenticated,
  service_role;

grant
select
  on finance.financial_health to "x-admin";

-- table_1: recent invoices
create or replace view finance.recent_invoices
with
  (security_invoker = true) as
select
  invoice_number as number,
  customer_name as customer,
  coalesce(total::text, '0') as total,
  to_char(issue_date, 'MM/DD') as issued
from
  finance.invoices
order by
  issue_date desc
limit
  10;

revoke all on finance.recent_invoices
from
  authenticated,
  service_role;

grant
select
  on finance.recent_invoices to "x-admin";

-- table_2: top vendors by spend
create or replace view finance.top_vendors
with
  (security_invoker = true) as
select
  v.name as vendor,
  coalesce(v.country, '') as country,
  count(b.id) as bills,
  coalesce(sum(b.total), 0) as spend
from
  finance.vendors v
  left join finance.bills b on b.vendor_id = v.id
group by
  v.id,
  v.name,
  v.country
order by
  spend desc nulls last
limit
  10;

revoke all on finance.top_vendors
from
  authenticated,
  service_role;

grant
select
  on finance.top_vendors to "x-admin";

comment on view finance.revenue_summary is '{"type": "dashboard_widget", "name": "Revenue (YTD)", "description": "Sum of paid invoices this year", "widget_type": "card_1"}';

comment on view finance.ar_ap_split is '{"type": "dashboard_widget", "name": "AR vs AP", "description": "Outstanding receivables vs payables", "widget_type": "card_2"}';

comment on view finance.cash_position is '{"type": "dashboard_widget", "name": "Cash Position (30d)", "description": "Net cash flow and collection rate", "widget_type": "card_3"}';

comment on view finance.financial_health is '{"type": "dashboard_widget", "name": "Financial Health", "description": "Overdue and stale items", "widget_type": "card_4"}';

comment on view finance.recent_invoices is '{"type": "dashboard_widget", "name": "Recent Invoices", "description": "Latest 10 invoices", "widget_type": "table_1"}';

comment on view finance.top_vendors is '{"type": "dashboard_widget", "name": "Top Vendors", "description": "Top 10 vendors by spend", "widget_type": "table_2"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: invoices by status
create or replace view finance.invoices_by_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  finance.invoices
group by
  status
order by
  case status
    when 'draft' then 1
    when 'sent' then 2
    when 'paid' then 3
    when 'overdue' then 4
    when 'cancelled' then 5
    when 'refunded' then 6
  end;

revoke all on finance.invoices_by_status_pie
from
  authenticated,
  service_role;

grant
select
  on finance.invoices_by_status_pie to "x-admin";

-- Bar: monthly revenue (last 12 months)
create or replace view finance.revenue_by_month_bar
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', issue_date), 'Mon YY') as label,
  coalesce(
    sum(total) filter (
      where
        status = 'paid'
    ),
    0
  )::bigint as paid,
  coalesce(
    sum(total) filter (
      where
        status in ('sent', 'overdue')
    ),
    0
  )::bigint as outstanding
from
  finance.invoices
where
  issue_date >= current_date - interval '12 months'
group by
  date_trunc('month', issue_date)
order by
  date_trunc('month', issue_date);

revoke all on finance.revenue_by_month_bar
from
  authenticated,
  service_role;

grant
select
  on finance.revenue_by_month_bar to "x-admin";

-- Line: weekly cash flow trend (last 12 weeks)
create or replace view finance.cash_flow_trend_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('week', payment_date), 'Mon DD') as date,
  coalesce(
    sum(amount) filter (
      where
        direction = 'incoming'
        and status = 'completed'
    ),
    0
  )::bigint as inflow,
  coalesce(
    sum(amount) filter (
      where
        direction = 'outgoing'
        and status = 'completed'
    ),
    0
  )::bigint as outflow
from
  finance.payments
where
  payment_date >= current_date - interval '12 weeks'
group by
  date_trunc('week', payment_date)
order by
  date_trunc('week', payment_date);

revoke all on finance.cash_flow_trend_line
from
  authenticated,
  service_role;

grant
select
  on finance.cash_flow_trend_line to "x-admin";

-- Radar: expense categories
create or replace view finance.expense_categories_radar
with
  (security_invoker = true) as
select
  category::text as metric,
  count(*) as total,
  count(*) filter (
    where
      status in ('approved', 'reimbursed')
  ) as approved,
  count(*) filter (
    where
      status = 'submitted'
  ) as pending
from
  finance.expenses
group by
  category;

revoke all on finance.expense_categories_radar
from
  authenticated,
  service_role;

grant
select
  on finance.expense_categories_radar to "x-admin";

comment on view finance.invoices_by_status_pie is '{"type": "chart", "name": "Invoices By Status", "description": "Invoice count grouped by status", "chart_type": "pie"}';

comment on view finance.revenue_by_month_bar is '{"type": "chart", "name": "Revenue By Month", "description": "Paid vs outstanding revenue per month", "chart_type": "bar"}';

comment on view finance.cash_flow_trend_line is '{"type": "chart", "name": "Cash Flow Trend", "description": "Weekly inflow vs outflow over 12 weeks", "chart_type": "line"}';

comment on view finance.expense_categories_radar is '{"type": "chart", "name": "Expense Categories", "description": "Expense counts across categories and statuses", "chart_type": "radar"}';

----------------------------------------------------------------
-- Audit triggers
----------------------------------------------------------------
create trigger audit_finance_accounts_insert
after insert on finance.accounts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_accounts_update
after update on finance.accounts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_accounts_delete
before delete on finance.accounts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_vendors_insert
after insert on finance.vendors for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_vendors_update
after update on finance.vendors for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_vendors_delete
before delete on finance.vendors for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_invoices_insert
after insert on finance.invoices for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_invoices_update
after update on finance.invoices for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_invoices_delete
before delete on finance.invoices for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_bills_insert
after insert on finance.bills for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_bills_update
after update on finance.bills for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_bills_delete
before delete on finance.bills for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_expenses_insert
after insert on finance.expenses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_expenses_update
after update on finance.expenses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_expenses_delete
before delete on finance.expenses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_payments_insert
after insert on finance.payments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_payments_update
after update on finance.payments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_payments_delete
before delete on finance.payments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_budgets_insert
after insert on finance.budgets for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_budgets_update
after update on finance.budgets for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_budgets_delete
before delete on finance.budgets for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_payroll_runs_insert
after insert on finance.payroll_runs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_payroll_runs_update
after update on finance.payroll_runs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_payroll_runs_delete
before delete on finance.payroll_runs for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_payslips_insert
after insert on finance.payslips for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_payslips_update
after update on finance.payslips for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_payslips_delete
before delete on finance.payslips for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_journal_entries_insert
after insert on finance.journal_entries for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_journal_entries_update
after update on finance.journal_entries for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_finance_journal_entries_delete
before delete on finance.journal_entries for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
-- Invoices: notify owner + finance team on creation, paid, or overdue transitions
create or replace function finance.trg_invoices_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if tg_op = 'INSERT' then
        v_type  := 'finance_invoice_created';
        v_title := 'New invoice';
        v_body  := 'Invoice ' || new.invoice_number || ' for ' || new.customer_name || ' was created.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('finance', 'invoices', 'select') || array[new.user_id],
            null
        );
    elsif new.status is distinct from old.status and new.status in ('paid', 'overdue') then
        v_type  := 'finance_invoice_' || new.status::text;
        v_title := 'Invoice ' || new.status::text;
        v_body  := 'Invoice ' || new.invoice_number || ' is now ' || new.status::text || '.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('finance', 'invoices', 'select') || array[new.user_id],
            null
        );
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'invoice_id', new.id,
            'status',     new.status,
            'total',      new.total
        ),
        '/finance/resource/invoices/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists invoices_notify on finance.invoices;

create trigger invoices_notify
after insert or update of status on finance.invoices for each row
execute function finance.trg_invoices_notify ();

-- Expenses: notify reviewers on submission, employee on status change
create or replace function finance.trg_expenses_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if tg_op = 'INSERT' then
        if new.status <> 'submitted' then
            return new;
        end if;
        v_type  := 'finance_expense_submitted';
        v_title := 'New expense submitted';
        v_body  := new.employee_name || ' submitted ' || new.amount::text || ' ' || new.currency || ' for ' || new.category::text || '.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('finance', 'expenses', 'update') || array[new.reviewer_user_id],
            null
        );
    elsif new.status is distinct from old.status and new.status in ('approved', 'rejected', 'reimbursed') then
        v_type  := 'finance_expense_' || new.status::text;
        v_title := 'Expense ' || new.status::text;
        v_body  := 'Expense ' || new.expense_number || ' is now ' || new.status::text || '.';
        v_recipients := array_remove(array[new.user_id], null);
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'expense_id', new.id,
            'status',     new.status,
            'amount',     new.amount,
            'category',   new.category
        ),
        '/finance/resource/expenses/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists expenses_notify on finance.expenses;

create trigger expenses_notify
after insert or update of status on finance.expenses for each row
execute function finance.trg_expenses_notify ();

-- Payroll runs: notify finance team on completion
create or replace function finance.trg_payroll_runs_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.status is not distinct from old.status then
        return new;
    end if;
    if new.status <> 'completed' then
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('finance', 'payroll_runs', 'select') || array[new.user_id],
        null
    );

    perform supasheet.create_notification(
        'finance_payroll_completed',
        'Payroll run completed',
        'Payroll ' || new.run_number || ' (' || to_char(new.pay_date, 'YYYY-MM-DD') ||
            ') completed for ' || new.employee_count::text || ' employees, net ' ||
            new.total_net::text || ' ' || new.currency || '.',
        v_recipients,
        jsonb_build_object(
            'payroll_run_id', new.id,
            'pay_date',       new.pay_date,
            'total_net',      new.total_net,
            'employee_count', new.employee_count
        ),
        '/finance/resource/payroll_runs/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists payroll_runs_notify on finance.payroll_runs;

create trigger payroll_runs_notify
after update of status on finance.payroll_runs for each row
execute function finance.trg_payroll_runs_notify ();
