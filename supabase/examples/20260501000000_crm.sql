create schema if not exists crm;

grant usage on schema crm to authenticated;

----------------------------------------------------------------
-- Enums
----------------------------------------------------------------
create type crm.company_type as enum(
  'customer',
  'prospect',
  'partner',
  'vendor',
  'other'
);

create type crm.contact_status as enum('lead', 'prospect', 'customer', 'inactive');

create type crm.lead_source as enum(
  'website',
  'referral',
  'event',
  'cold_outreach',
  'inbound',
  'other'
);

create type crm.deal_stage as enum(
  'prospecting',
  'qualified',
  'proposal',
  'negotiation',
  'won',
  'lost'
);

create type crm.deal_priority as enum('low', 'medium', 'high', 'critical');

create type crm.activity_type as enum('call', 'email', 'meeting', 'note', 'task');

create type crm.activity_status as enum(
  'pending',
  'in_progress',
  'completed',
  'cancelled'
);

----------------------------------------------------------------
-- Users mirror view
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
  authenticated,
  service_role;

grant
select
  on crm.users to "x-admin";

----------------------------------------------------------------
-- Companies
----------------------------------------------------------------
create table crm.companies (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(500) not null,
  legal_name varchar(500),
  type crm.company_type default 'prospect',
  industry varchar(255),
  website supasheet.URL,
  phone supasheet.TEL,
  email supasheet.EMAIL,
  description supasheet.RICH_TEXT,
  logo supasheet.file,
  cover supasheet.file,
  address text,
  city varchar(255),
  country varchar(255),
  employee_count integer,
  annual_revenue numeric(14, 2),
  tags varchar(500) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column crm.companies.type is '{
    "progress": false,
    "values": {
        "customer": {
            "variant": "success",
            "icon": "BadgeCheck"
        },
        "prospect": {
            "variant": "info",
            "icon": "Target"
        },
        "partner": {
            "variant": "secondary",
            "icon": "Handshake"
        },
        "vendor": {
            "variant": "warning",
            "icon": "Truck"
        },
        "other": {
            "variant": "outline",
            "icon": "CircleEllipsis"
        }
    }
}';

comment on table crm.companies is '{
    "icon": "Building2",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Companies By Type",
            "type": "kanban",
            "group": "type",
            "title": "name",
            "description": "industry",
            "date": "created_at",
            "badge": "type"
        },
        {
            "id": "gallery",
            "name": "Company Gallery",
            "type": "gallery",
            "cover": "logo",
            "title": "name",
            "description": "industry",
            "badge": "type"
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
                    "type",
                    "industry",
                    "logo",
                    "cover",
                    "description"
                ]
            },
            {
                "id": "contact",
                "title": "Contact",
                "fields": [
                    "website",
                    "phone",
                    "email"
                ]
            },
            {
                "id": "location",
                "title": "Location",
                "fields": [
                    "address",
                    "city",
                    "country"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "employee_count",
                    "annual_revenue",
                    "tags",
                    "color"
                ]
            },
            {
                "id": "extras",
                "title": "Notes",
                "collapsible": true,
                "fields": [
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

comment on column crm.companies.logo is '{"accept":"image/*"}';

comment on column crm.companies.cover is '{"accept":"image/*"}';

revoke all on table crm.companies
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table crm.companies to "x-admin";

create index idx_crm_companies_user_id on crm.companies (user_id);

create index idx_crm_companies_type on crm.companies (type);

create index idx_crm_companies_industry on crm.companies (industry);

create index idx_crm_companies_country on crm.companies (country);

create index idx_crm_companies_created_at on crm.companies (created_at desc);

alter table crm.companies enable row level security;

create policy companies_select on crm.companies for
select
  to authenticated using (true);

create policy companies_insert on crm.companies for insert to authenticated
with
  check (true);

create policy companies_update on crm.companies
for update
  to authenticated using (true)
with
  check (true);

create policy companies_delete on crm.companies for delete to authenticated using (true);

----------------------------------------------------------------
-- Contacts
----------------------------------------------------------------
create table crm.contacts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  first_name varchar(255) not null,
  last_name varchar(255),
  email supasheet.EMAIL,
  phone supasheet.TEL,
  mobile supasheet.TEL,
  job_title varchar(255),
  department varchar(255),
  status crm.contact_status default 'lead',
  lead_source crm.lead_source default 'other',
  avatar supasheet.AVATAR,
  bio supasheet.RICH_TEXT,
  linkedin_url supasheet.URL,
  twitter_url supasheet.URL,
  tags varchar(500) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column crm.contacts.status is '{
    "progress": true,
    "values": {
        "lead": {
            "variant": "warning",
            "icon": "Sprout"
        },
        "prospect": {
            "variant": "info",
            "icon": "UserCog"
        },
        "customer": {
            "variant": "success",
            "icon": "UserCheck"
        },
        "inactive": {
            "variant": "outline",
            "icon": "UserMinus"
        }
    }
}';

comment on column crm.contacts.lead_source is '{
    "progress": false,
    "values": {
        "website": {
            "variant": "info",
            "icon": "Globe"
        },
        "referral": {
            "variant": "success",
            "icon": "Share2"
        },
        "event": {
            "variant": "warning",
            "icon": "CalendarDays"
        },
        "cold_outreach": {
            "variant": "outline",
            "icon": "Mail"
        },
        "inbound": {
            "variant": "success",
            "icon": "Inbox"
        },
        "other": {
            "variant": "secondary",
            "icon": "CircleEllipsis"
        }
    }
}';

comment on table crm.contacts is '{
    "icon": "Contact",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Contacts By Status",
            "type": "kanban",
            "group": "status",
            "title": "first_name",
            "description": "job_title",
            "date": "created_at",
            "badge": "lead_source"
        },
        {
            "id": "gallery",
            "name": "Contact Gallery",
            "type": "gallery",
            "cover": "avatar",
            "title": "first_name",
            "description": "job_title",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Identity",
                "fields": [
                    "first_name",
                    "last_name",
                    "avatar",
                    "bio"
                ]
            },
            {
                "id": "contact",
                "title": "Contact",
                "fields": [
                    "email",
                    "phone",
                    "mobile"
                ]
            },
            {
                "id": "work",
                "title": "Work",
                "fields": [
                    "job_title",
                    "department",
                    "status",
                    "lead_source"
                ]
            },
            {
                "id": "social",
                "title": "Social",
                "fields": [
                    "linkedin_url",
                    "twitter_url"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "tags"
                ]
            },
            {
                "id": "extras",
                "title": "Notes",
                "collapsible": true,
                "fields": [
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "first_name",
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

comment on column crm.contacts.avatar is '{"accept":"image/*"}';

revoke all on table crm.contacts
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table crm.contacts to "x-admin";

create index idx_crm_contacts_user_id on crm.contacts (user_id);

create index idx_crm_contacts_status on crm.contacts (status);

create index idx_crm_contacts_lead_source on crm.contacts (lead_source);

create index idx_crm_contacts_email on crm.contacts (email);

create index idx_crm_contacts_created_at on crm.contacts (created_at desc);

alter table crm.contacts enable row level security;

create policy contacts_select on crm.contacts for
select
  to authenticated using (true);

create policy contacts_insert on crm.contacts for insert to authenticated
with
  check (true);

create policy contacts_update on crm.contacts
for update
  to authenticated using (true)
with
  check (true);

create policy contacts_delete on crm.contacts for delete to authenticated using (true);

----------------------------------------------------------------
-- Contact ↔ Company junction (many-to-many)
----------------------------------------------------------------
create table crm.contact_companies (
  id uuid primary key default extensions.uuid_generate_v4 (),
  contact_id uuid not null references crm.contacts (id) on delete cascade,
  company_id uuid not null references crm.companies (id) on delete cascade,
  role varchar(255),
  is_primary boolean default false,
  start_date date,
  end_date date,
  created_at timestamptz default current_timestamp,
  unique (contact_id, company_id)
);

-- One primary employer per contact at a time
create unique index idx_crm_contact_companies_one_primary on crm.contact_companies (contact_id)
where
  is_primary = true;

create index idx_crm_contact_companies_contact_id on crm.contact_companies (contact_id);

create index idx_crm_contact_companies_company_id on crm.contact_companies (company_id);

comment on table crm.contact_companies is '{
    "icon": "Briefcase",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "contact_id",
                    "company_id",
                    "is_primary"
                ]
            },
            {
                "id": "details",
                "title": "Details",
                "fields": [
                    "role",
                    "start_date",
                    "end_date"
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
                "table": "contacts",
                "on": "contact_id",
                "columns": [
                    "first_name",
                    "last_name",
                    "email"
                ]
            },
            {
                "table": "companies",
                "on": "company_id",
                "columns": [
                    "name",
                    "industry"
                ]
            }
        ]
    }
}';

revoke all on table crm.contact_companies
from
  authenticated,
  service_role;

grant
select
,
  insert,
  delete on table crm.contact_companies to "x-admin";

alter table crm.contact_companies enable row level security;

create policy contact_companies_select on crm.contact_companies for
select
  to authenticated using (true);

create policy contact_companies_insert on crm.contact_companies for insert to authenticated
with
  check (true);

create policy contact_companies_delete on crm.contact_companies for delete to authenticated using (true);

----------------------------------------------------------------
-- Deals
----------------------------------------------------------------
create table crm.deals (
  id uuid primary key default extensions.uuid_generate_v4 (),
  title varchar(500) not null,
  description supasheet.RICH_TEXT,
  cover supasheet.file,
  stage crm.deal_stage default 'prospecting',
  priority crm.deal_priority default 'medium',
  value numeric(14, 2),
  currency varchar(3) default 'USD',
  probability supasheet.PERCENTAGE,
  expected_close_date timestamptz,
  closed_at timestamptz,
  company_id uuid references crm.companies (id) on delete set null,
  primary_contact_id uuid references crm.contacts (id) on delete set null,
  attachments supasheet.file,
  tags varchar(500) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column crm.deals.stage is '{
    "progress": true,
    "values": {
        "prospecting": {
            "variant": "outline",
            "icon": "Search"
        },
        "qualified": {
            "variant": "info",
            "icon": "CheckCircle2"
        },
        "proposal": {
            "variant": "warning",
            "icon": "FileText"
        },
        "negotiation": {
            "variant": "warning",
            "icon": "MessagesSquare"
        },
        "won": {
            "variant": "success",
            "icon": "Trophy"
        },
        "lost": {
            "variant": "destructive",
            "icon": "XCircle"
        }
    }
}';

comment on column crm.deals.priority is '{
    "progress": false,
    "values": {
        "low": {
            "variant": "outline",
            "icon": "CircleArrowDown"
        },
        "medium": {
            "variant": "info",
            "icon": "CircleMinus"
        },
        "high": {
            "variant": "warning",
            "icon": "CircleArrowUp"
        },
        "critical": {
            "variant": "destructive",
            "icon": "Flame"
        }
    }
}';

comment on table crm.deals is '{
    "icon": "Handshake",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Deals By Stage",
            "type": "kanban",
            "group": "stage",
            "title": "title",
            "description": "description",
            "date": "expected_close_date",
            "badge": "priority"
        },
        {
            "id": "calendar",
            "name": "Deal Pipeline",
            "type": "calendar",
            "title": "title",
            "badge": "stage",
            "start_date": "created_at",
            "end_date": "expected_close_date"
        },
        {
            "id": "gallery",
            "name": "Deal Gallery",
            "type": "gallery",
            "cover": "cover",
            "title": "title",
            "description": "description",
            "badge": "stage"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "title",
                    "description",
                    "cover"
                ]
            },
            {
                "id": "pipeline",
                "title": "Pipeline",
                "fields": [
                    "stage",
                    "priority",
                    "probability",
                    "expected_close_date",
                    "closed_at"
                ]
            },
            {
                "id": "financial",
                "title": "Financial",
                "fields": [
                    "value",
                    "currency"
                ]
            },
            {
                "id": "relations",
                "title": "Relations",
                "fields": [
                    "company_id",
                    "primary_contact_id"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "tags",
                    "color"
                ]
            },
            {
                "id": "extras",
                "title": "Attachments & notes",
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
                "id": "expected_close_date",
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
            },
            {
                "table": "companies",
                "on": "company_id",
                "columns": [
                    "name",
                    "industry"
                ]
            },
            {
                "table": "contacts",
                "on": "primary_contact_id",
                "columns": [
                    "first_name",
                    "last_name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column crm.deals.cover is '{"accept":"image/*"}';

comment on column crm.deals.attachments is '{"accept":"*", "max_files": 999}';

revoke all on table crm.deals
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table crm.deals to "x-admin";

create index idx_crm_deals_user_id on crm.deals (user_id);

create index idx_crm_deals_company_id on crm.deals (company_id);

create index idx_crm_deals_primary_contact_id on crm.deals (primary_contact_id);

create index idx_crm_deals_stage on crm.deals (stage);

create index idx_crm_deals_priority on crm.deals (priority);

create index idx_crm_deals_expected_close_date on crm.deals (expected_close_date);

create index idx_crm_deals_created_at on crm.deals (created_at desc);

alter table crm.deals enable row level security;

create policy deals_select on crm.deals for
select
  to authenticated using (true);

create policy deals_insert on crm.deals for insert to authenticated
with
  check (true);

create policy deals_update on crm.deals
for update
  to authenticated using (true)
with
  check (true);

create policy deals_delete on crm.deals for delete to authenticated using (true);

----------------------------------------------------------------
-- Activities
----------------------------------------------------------------
create table crm.activities (
  id uuid primary key default extensions.uuid_generate_v4 (),
  subject varchar(500) not null,
  body supasheet.RICH_TEXT,
  type crm.activity_type default 'note',
  status crm.activity_status default 'pending',
  scheduled_at timestamptz,
  completed_at timestamptz,
  duration supasheet.DURATION,
  deal_id uuid references crm.deals (id) on delete cascade,
  contact_id uuid references crm.contacts (id) on delete cascade,
  company_id uuid references crm.companies (id) on delete cascade,
  attachments supasheet.file,
  tags varchar(500) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column crm.activities.type is '{
    "progress": false,
    "values": {
        "call": {
            "variant": "info",
            "icon": "Phone"
        },
        "email": {
            "variant": "info",
            "icon": "Mail"
        },
        "meeting": {
            "variant": "warning",
            "icon": "Users"
        },
        "note": {
            "variant": "outline",
            "icon": "StickyNote"
        },
        "task": {
            "variant": "secondary",
            "icon": "CheckSquare"
        }
    }
}';

comment on column crm.activities.status is '{
    "progress": true,
    "values": {
        "pending": {
            "variant": "warning",
            "icon": "Clock"
        },
        "in_progress": {
            "variant": "info",
            "icon": "Loader"
        },
        "completed": {
            "variant": "success",
            "icon": "CircleCheck"
        },
        "cancelled": {
            "variant": "destructive",
            "icon": "XCircle"
        }
    }
}';

comment on table crm.activities is '{
    "icon": "Activity",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Activities By Status",
            "type": "kanban",
            "group": "status",
            "title": "subject",
            "description": "body",
            "date": "scheduled_at",
            "badge": "type"
        },
        {
            "id": "calendar",
            "name": "Activity Calendar",
            "type": "calendar",
            "title": "subject",
            "badge": "status",
            "start_date": "scheduled_at",
            "end_date": "completed_at"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "subject",
                    "body",
                    "type"
                ]
            },
            {
                "id": "schedule",
                "title": "Schedule",
                "fields": [
                    "status",
                    "scheduled_at",
                    "completed_at",
                    "duration"
                ]
            },
            {
                "id": "relations",
                "title": "Relations",
                "fields": [
                    "deal_id",
                    "contact_id",
                    "company_id"
                ]
            },
            {
                "id": "extras",
                "title": "Attachments & notes",
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
                "id": "scheduled_at",
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
                "table": "deals",
                "on": "deal_id",
                "columns": [
                    "title",
                    "stage"
                ]
            },
            {
                "table": "contacts",
                "on": "contact_id",
                "columns": [
                    "first_name",
                    "last_name",
                    "email"
                ]
            },
            {
                "table": "companies",
                "on": "company_id",
                "columns": [
                    "name",
                    "industry"
                ]
            }
        ]
    }
}';

comment on column crm.activities.attachments is '{"accept":"*", "max_files": 999}';

revoke all on table crm.activities
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table crm.activities to "x-admin";

create index idx_crm_activities_user_id on crm.activities (user_id);

create index idx_crm_activities_deal_id on crm.activities (deal_id);

create index idx_crm_activities_contact_id on crm.activities (contact_id);

create index idx_crm_activities_company_id on crm.activities (company_id);

create index idx_crm_activities_type on crm.activities (type);

create index idx_crm_activities_status on crm.activities (status);

create index idx_crm_activities_scheduled_at on crm.activities (scheduled_at desc);

alter table crm.activities enable row level security;

create policy activities_select on crm.activities for
select
  to authenticated using (true);

create policy activities_insert on crm.activities for insert to authenticated
with
  check (true);

create policy activities_update on crm.activities
for update
  to authenticated using (true)
with
  check (true);

create policy activities_delete on crm.activities for delete to authenticated using (true);

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view crm.companies_report
with
  (security_invoker = true) as
select
  c.id,
  c.name,
  c.legal_name,
  c.type,
  c.industry,
  c.country,
  c.employee_count,
  c.annual_revenue,
  u.name as owner,
  count(distinct cc.contact_id) as contact_count,
  count(distinct d.id) as deal_count,
  coalesce(
    sum(d.value) filter (
      where
        d.stage = 'won'
    ),
    0
  ) as won_value,
  coalesce(
    sum(d.value) filter (
      where
        d.stage not in ('won', 'lost')
    ),
    0
  ) as open_pipeline,
  c.created_at,
  c.updated_at
from
  crm.companies c
  left join supasheet.users u on u.id = c.user_id
  left join crm.contact_companies cc on cc.company_id = c.id
  left join crm.deals d on d.company_id = c.id
group by
  c.id,
  u.name;

revoke all on crm.companies_report
from
  authenticated,
  service_role;

grant
select
  on crm.companies_report to "x-admin";

comment on view crm.companies_report is '{"type": "report", "name": "Companies Report", "description": "All companies with deal and contact rollups"}';

create or replace view crm.contacts_report
with
  (security_invoker = true) as
select
  ct.id,
  ct.first_name,
  ct.last_name,
  ct.email,
  ct.phone,
  ct.job_title,
  ct.status,
  ct.lead_source,
  co.name as primary_company,
  cc.role as primary_role,
  u.name as owner,
  count(distinct d.id) as deal_count,
  coalesce(
    sum(d.value) filter (
      where
        d.stage = 'won'
    ),
    0
  ) as won_value,
  ct.created_at,
  ct.updated_at
from
  crm.contacts ct
  left join supasheet.users u on u.id = ct.user_id
  left join crm.contact_companies cc on cc.contact_id = ct.id
  and cc.is_primary = true
  left join crm.companies co on co.id = cc.company_id
  left join crm.deals d on d.primary_contact_id = ct.id
group by
  ct.id,
  co.name,
  cc.role,
  u.name;

revoke all on crm.contacts_report
from
  authenticated,
  service_role;

grant
select
  on crm.contacts_report to "x-admin";

comment on view crm.contacts_report is '{"type": "report", "name": "Contacts Report", "description": "Contacts with primary company and deal stats"}';

create or replace view crm.deals_report
with
  (security_invoker = true) as
select
  d.id,
  d.title,
  d.stage,
  d.priority,
  d.value,
  d.currency,
  d.probability,
  d.expected_close_date,
  d.closed_at,
  co.name as company,
  co.industry,
  ct.first_name || coalesce(' ' || ct.last_name, '') as primary_contact,
  ct.email as primary_contact_email,
  u.name as owner,
  count(a.id) as activity_count,
  d.created_at,
  d.updated_at
from
  crm.deals d
  left join crm.companies co on co.id = d.company_id
  left join crm.contacts ct on ct.id = d.primary_contact_id
  left join supasheet.users u on u.id = d.user_id
  left join crm.activities a on a.deal_id = d.id
group by
  d.id,
  co.name,
  co.industry,
  ct.first_name,
  ct.last_name,
  ct.email,
  u.name;

revoke all on crm.deals_report
from
  authenticated,
  service_role;

grant
select
  on crm.deals_report to "x-admin";

comment on view crm.deals_report is '{"type": "report", "name": "Deals Report", "description": "Full deal list with related company, contact, and activity data"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: count of open deals
create or replace view crm.deal_pipeline_summary
with
  (security_invoker = true) as
select
  count(*) as value,
  'handshake' as icon,
  'open deals' as label
from
  crm.deals
where
  stage not in ('won', 'lost');

revoke all on crm.deal_pipeline_summary
from
  authenticated,
  service_role;

grant
select
  on crm.deal_pipeline_summary to "x-admin";

-- card_2: won vs lost
create or replace view crm.deal_win_rate
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      stage = 'won'
  ) as primary,
  count(*) filter (
    where
      stage = 'lost'
  ) as secondary,
  'Won' as primary_label,
  'Lost' as secondary_label
from
  crm.deals;

revoke all on crm.deal_win_rate
from
  authenticated,
  service_role;

grant
select
  on crm.deal_win_rate to "x-admin";

-- card_3: pipeline value + win %
create or replace view crm.pipeline_value
with
  (security_invoker = true) as
select
  coalesce(
    sum(value) filter (
      where
        stage not in ('won', 'lost')
    ),
    0
  ) as value,
  case
    when count(*) filter (
      where
        stage in ('won', 'lost')
    ) > 0 then round(
      (
        count(*) filter (
          where
            stage = 'won'
        )::numeric / count(*) filter (
          where
            stage in ('won', 'lost')
        )::numeric
      ) * 100,
      1
    )
    else 0
  end as percent
from
  crm.deals;

revoke all on crm.pipeline_value
from
  authenticated,
  service_role;

grant
select
  on crm.pipeline_value to "x-admin";

-- card_4: deal health (at-risk breakdown)
create or replace view crm.deal_health
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      stage not in ('won', 'lost')
      and (
        priority in ('high', 'critical')
        or (
          expected_close_date is not null
          and expected_close_date < current_timestamp
        )
      )
  ) as current,
  count(*) filter (
    where
      stage not in ('won', 'lost')
  ) as total,
  json_build_array(
    json_build_object(
      'label',
      'Critical',
      'value',
      count(*) filter (
        where
          stage not in ('won', 'lost')
          and priority = 'critical'
      )
    ),
    json_build_object(
      'label',
      'High',
      'value',
      count(*) filter (
        where
          stage not in ('won', 'lost')
          and priority = 'high'
      )
    ),
    json_build_object(
      'label',
      'Overdue',
      'value',
      count(*) filter (
        where
          stage not in ('won', 'lost')
          and expected_close_date is not null
          and expected_close_date < current_timestamp
      )
    )
  ) as segments
from
  crm.deals;

revoke all on crm.deal_health
from
  authenticated,
  service_role;

grant
select
  on crm.deal_health to "x-admin";

-- table_1: recent deals
create or replace view crm.recent_deals
with
  (security_invoker = true) as
select
  title,
  stage,
  coalesce(value::text, '0') as amount,
  to_char(created_at, 'MM/DD') as date
from
  crm.deals
order by
  created_at desc
limit
  10;

revoke all on crm.recent_deals
from
  authenticated,
  service_role;

grant
select
  on crm.recent_deals to "x-admin";

-- table_2: top companies by pipeline value
create or replace view crm.top_companies
with
  (security_invoker = true) as
select
  co.name as company,
  co.industry,
  count(d.id) as deals,
  coalesce(sum(d.value), 0) as pipeline
from
  crm.companies co
  left join crm.deals d on d.company_id = co.id
group by
  co.id,
  co.name,
  co.industry
order by
  pipeline desc nulls last
limit
  10;

revoke all on crm.top_companies
from
  authenticated,
  service_role;

grant
select
  on crm.top_companies to "x-admin";

comment on view crm.deal_pipeline_summary is '{"type": "dashboard_widget", "name": "Open Deals", "description": "Count of deals not yet won or lost", "widget_type": "card_1"}';

comment on view crm.deal_win_rate is '{"type": "dashboard_widget", "name": "Win vs Lost", "description": "Closed deal outcomes", "widget_type": "card_2"}';

comment on view crm.pipeline_value is '{"type": "dashboard_widget", "name": "Pipeline Value", "description": "Open pipeline value and win rate", "widget_type": "card_3"}';

comment on view crm.deal_health is '{"type": "dashboard_widget", "name": "Pipeline Health", "description": "At-risk open deals breakdown", "widget_type": "card_4"}';

comment on view crm.recent_deals is '{"type": "dashboard_widget", "name": "Recent Deals", "description": "Latest 10 deals", "widget_type": "table_1"}';

comment on view crm.top_companies is '{"type": "dashboard_widget", "name": "Top Companies", "description": "Top 10 companies by pipeline value", "widget_type": "table_2"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: deals by stage
create or replace view crm.deals_by_stage_pie
with
  (security_invoker = true) as
select
  stage::text as label,
  count(*) as value
from
  crm.deals
group by
  stage
order by
  case stage
    when 'prospecting' then 1
    when 'qualified' then 2
    when 'proposal' then 3
    when 'negotiation' then 4
    when 'won' then 5
    when 'lost' then 6
  end;

revoke all on crm.deals_by_stage_pie
from
  authenticated,
  service_role;

grant
select
  on crm.deals_by_stage_pie to "x-admin";

-- Bar: deals by company
create or replace view crm.deals_by_company_bar
with
  (security_invoker = true) as
select
  co.name as label,
  count(d.id) as total,
  count(d.id) filter (
    where
      d.stage = 'won'
  ) as won
from
  crm.companies co
  left join crm.deals d on d.company_id = co.id
group by
  co.id,
  co.name
having
  count(d.id) > 0
order by
  count(d.id) desc
limit
  10;

revoke all on crm.deals_by_company_bar
from
  authenticated,
  service_role;

grant
select
  on crm.deals_by_company_bar to "x-admin";

-- Line: weekly pipeline trend (last 8 weeks)
create or replace view crm.pipeline_trend_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('week', created_at), 'Mon DD') as date,
  count(*) as deals,
  coalesce(sum(value), 0)::bigint as pipeline
from
  crm.deals
where
  created_at >= current_date - interval '8 weeks'
group by
  date_trunc('week', created_at)
order by
  date_trunc('week', created_at);

revoke all on crm.pipeline_trend_line
from
  authenticated,
  service_role;

grant
select
  on crm.pipeline_trend_line to "x-admin";

-- Radar: activity metrics by type
create or replace view crm.activity_metrics_radar
with
  (security_invoker = true) as
select
  type::text as metric,
  count(*) as total,
  count(*) filter (
    where
      status = 'completed'
  ) as completed,
  count(*) filter (
    where
      status = 'pending'
  ) as pending
from
  crm.activities
group by
  type;

revoke all on crm.activity_metrics_radar
from
  authenticated,
  service_role;

grant
select
  on crm.activity_metrics_radar to "x-admin";

comment on view crm.deals_by_stage_pie is '{"type": "chart", "name": "Deals By Stage", "description": "Deal count grouped by pipeline stage", "chart_type": "pie"}';

comment on view crm.deals_by_company_bar is '{"type": "chart", "name": "Deals By Company", "description": "Top 10 companies by deal count", "chart_type": "bar"}';

comment on view crm.pipeline_trend_line is '{"type": "chart", "name": "Pipeline Trend", "description": "Weekly deal count and pipeline value over 8 weeks", "chart_type": "line"}';

comment on view crm.activity_metrics_radar is '{"type": "chart", "name": "Activity Metrics", "description": "Activity counts across types and statuses", "chart_type": "radar"}';

----------------------------------------------------------------
-- Audit triggers
----------------------------------------------------------------
create trigger audit_crm_companies_insert
after insert on crm.companies for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_companies_update
after update on crm.companies for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_companies_delete
before delete on crm.companies for each row
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

create trigger audit_crm_contact_companies_insert
after insert on crm.contact_companies for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_contact_companies_delete
before delete on crm.contact_companies for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_deals_insert
after insert on crm.deals for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_deals_update
after update on crm.deals for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_crm_deals_delete
before delete on crm.deals for each row
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

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
-- Companies: notify everyone with crm.companies:select on creation or type change
create or replace function crm.trg_companies_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type       text;
    v_title      text;
    v_body       text;
begin
    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('crm', 'companies', 'select') || array[new.user_id],
        null
    );

    if tg_op = 'INSERT' then
        v_type  := 'crm_company_created';
        v_title := 'New company';
        v_body  := 'Company "' || new.name || '" was added.';
    elsif new.type is distinct from old.type then
        v_type  := 'crm_company_type_changed';
        v_title := 'Company type updated';
        v_body  := 'Company "' || new.name || '" is now a ' || new.type::text || '.';
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object('company_id', new.id, 'type', new.type),
        '/crm/resource/companies/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists companies_notify on crm.companies;

create trigger companies_notify
after insert or update of type on crm.companies for each row
execute function crm.trg_companies_notify ();

-- Deals: notify on creation, stage change, and value change
create or replace function crm.trg_deals_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type       text;
    v_title      text;
    v_body       text;
begin
    if tg_op = 'INSERT' then
        v_type  := 'crm_deal_created';
        v_title := 'New deal';
        v_body  := 'Deal "' || new.title || '" was created.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('crm', 'deals', 'select') || array[new.user_id],
            null
        );
    elsif new.stage is distinct from old.stage then
        v_type  := 'crm_deal_stage_changed';
        v_title := 'Deal stage updated';
        v_body  := 'Deal "' || new.title || '" moved to ' || new.stage::text || '.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('crm', 'deals', 'select') || array[new.user_id],
            null
        );
    elsif new.value is distinct from old.value then
        v_type  := 'crm_deal_value_changed';
        v_title := 'Deal value updated';
        v_body  := 'Deal "' || new.title || '" value is now ' || coalesce(new.value::text, '0') || '.';
        v_recipients := array_remove(array[new.user_id], null);
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'deal_id',           new.id,
            'company_id',        new.company_id,
            'primary_contact_id', new.primary_contact_id,
            'stage',             new.stage,
            'value',             new.value
        ),
        '/crm/resource/deals/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists deals_notify on crm.deals;

create trigger deals_notify
after insert or update of stage,
value on crm.deals for each row
execute function crm.trg_deals_notify ();

-- Activities: notify owner + parent deal owner + parent contact owner on insert/status change
create or replace function crm.trg_activities_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_deal_owner uuid;
    v_contact_owner uuid;
    v_type       text;
    v_title      text;
    v_body       text;
begin
    if new.deal_id is not null then
        select user_id into v_deal_owner from crm.deals where id = new.deal_id;
    end if;
    if new.contact_id is not null then
        select user_id into v_contact_owner from crm.contacts where id = new.contact_id;
    end if;

    v_recipients := array_remove(
        array[new.user_id, v_deal_owner, v_contact_owner],
        null
    );

    if tg_op = 'INSERT' then
        v_type  := 'crm_activity_created';
        v_title := 'New activity';
        v_body  := 'Activity "' || new.subject || '" was logged.';
    elsif new.status is distinct from old.status then
        v_type  := 'crm_activity_status_changed';
        v_title := 'Activity status updated';
        v_body  := 'Activity "' || new.subject || '" is now ' || new.status::text || '.';
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'activity_id', new.id,
            'deal_id',     new.deal_id,
            'contact_id',  new.contact_id,
            'company_id',  new.company_id,
            'type',        new.type,
            'status',      new.status
        ),
        '/crm/resource/activities/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists activities_notify on crm.activities;

create trigger activities_notify
after insert or update of status on crm.activities for each row
execute function crm.trg_activities_notify ();
