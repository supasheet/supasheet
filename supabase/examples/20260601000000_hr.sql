create schema if not exists hr;

grant usage on schema hr to authenticated;

----------------------------------------------------------------
-- Enums + permissions (must commit before use)
----------------------------------------------------------------
begin;

create type hr.employment_type as enum(
  'full_time',
  'part_time',
  'contract',
  'intern',
  'temporary'
);

create type hr.employment_status as enum(
  'active',
  'on_leave',
  'suspended',
  'terminated',
  'retired'
);

create type hr.leave_type as enum(
  'vacation',
  'sick',
  'personal',
  'maternity',
  'paternity',
  'bereavement',
  'unpaid'
);

create type hr.leave_status as enum('pending', 'approved', 'rejected', 'cancelled');

create type hr.review_status as enum('draft', 'in_review', 'completed', 'acknowledged');

create type hr.posting_status as enum('draft', 'open', 'on_hold', 'filled', 'cancelled');

create type hr.candidate_status as enum(
  'applied',
  'screening',
  'interview',
  'offer',
  'hired',
  'rejected',
  'withdrawn'
);

commit;

----------------------------------------------------------------
-- Users mirror view
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
  authenticated,
  service_role;

grant
select
  on hr.users to "x-admin";

----------------------------------------------------------------
-- Departments
----------------------------------------------------------------
create table hr.departments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null,
  code varchar(50) unique,
  description supasheet.RICH_TEXT,
  parent_id uuid references hr.departments (id) on delete set null,
  manager_id uuid, -- FK added after employees table is created
  color supasheet.COLOR,
  cover supasheet.file,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table hr.departments is '{
    "icon": "Building2",
    "display": "block",
    "primary_view": "tree",
    "views": [
        {
            "id": "tree",
            "name": "Org Tree",
            "type": "tree",
            "parent": "parent_id",
            "title": "name",
            "secondary": "code"
        },
        {
            "id": "gallery",
            "name": "Department Gallery",
            "type": "gallery",
            "cover": "cover",
            "title": "name",
            "description": "description",
            "badge": "code"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "name",
                    "code",
                    "description",
                    "cover"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "parent_id",
                    "manager_id",
                    "color"
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
        ]
    }
}';

comment on column hr.departments.cover is '{"accept":"image/*"}';

revoke all on table hr.departments
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hr.departments to "x-admin";

create index idx_hr_departments_parent_id on hr.departments (parent_id);

create index idx_hr_departments_manager_id on hr.departments (manager_id);

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
-- Positions
----------------------------------------------------------------
create table hr.positions (
  id uuid primary key default extensions.uuid_generate_v4 (),
  title varchar(255) not null,
  code varchar(50) unique,
  description supasheet.RICH_TEXT,
  department_id uuid references hr.departments (id) on delete set null,
  employment_type hr.employment_type default 'full_time',
  level varchar(50),
  min_salary numeric(12, 2),
  max_salary numeric(12, 2),
  currency varchar(3) default 'USD',
  tags varchar(255) [],
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hr.positions.employment_type is '{
    "progress": false,
    "values": {
        "full_time":  {"variant": "success",  "icon": "BriefcaseBusiness"},
        "part_time":  {"variant": "info",     "icon": "Clock"},
        "contract":   {"variant": "warning",  "icon": "FileSignature"},
        "intern":     {"variant": "secondary","icon": "GraduationCap"},
        "temporary":  {"variant": "outline",  "icon": "Hourglass"}
    }
}';

comment on table hr.positions is '{
    "icon": "Briefcase",
    "display": "block",
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "title",
                    "code",
                    "description",
                    "level"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "department_id",
                    "employment_type",
                    "tags"
                ]
            },
            {
                "id": "compensation",
                "title": "Compensation",
                "fields": [
                    "min_salary",
                    "max_salary",
                    "currency"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "title",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "departments",
                "on": "department_id",
                "columns": [
                    "name",
                    "code"
                ]
            }
        ]
    }
}';

revoke all on table hr.positions
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hr.positions to "x-admin";

create index idx_hr_positions_department_id on hr.positions (department_id);

create index idx_hr_positions_employment_type on hr.positions (employment_type);

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
-- Employees
----------------------------------------------------------------
create table hr.employees (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_number varchar(50) unique,
  first_name varchar(255) not null,
  last_name varchar(255),
  email supasheet.EMAIL,
  phone supasheet.TEL,
  mobile supasheet.TEL,
  avatar supasheet.AVATAR,
  bio supasheet.RICH_TEXT,
  department_id uuid references hr.departments (id) on delete set null,
  position_id uuid references hr.positions (id) on delete set null,
  manager_id uuid references hr.employees (id) on delete set null,
  employment_type hr.employment_type default 'full_time',
  employment_status hr.employment_status default 'active',
  hire_date date,
  termination_date date,
  birth_date date,
  salary numeric(12, 2),
  currency varchar(3) default 'USD',
  address text,
  city varchar(255),
  country varchar(255),
  emergency_contact varchar(255),
  emergency_phone supasheet.TEL,
  skills varchar(255) [],
  certifications text,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hr.employees.employment_status is '{
    "progress": true,
    "values": {
        "active":     {"variant": "success",     "icon": "UserCheck"},
        "on_leave":   {"variant": "warning",     "icon": "PalmTree"},
        "suspended":  {"variant": "destructive", "icon": "UserX"},
        "terminated": {"variant": "outline",     "icon": "UserMinus"},
        "retired":    {"variant": "secondary",   "icon": "Award"}
    }
}';

comment on column hr.employees.employment_type is '{
    "progress": false,
    "values": {
        "full_time":  {"variant": "success",  "icon": "BriefcaseBusiness"},
        "part_time":  {"variant": "info",     "icon": "Clock"},
        "contract":   {"variant": "warning",  "icon": "FileSignature"},
        "intern":     {"variant": "secondary","icon": "GraduationCap"},
        "temporary":  {"variant": "outline",  "icon": "Hourglass"}
    }
}';

comment on table hr.employees is '{
    "icon": "Users",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Employees By Status",
            "type": "kanban",
            "group": "employment_status",
            "title": "first_name",
            "description": "email",
            "date": "hire_date",
            "badge": "employment_type"
        },
        {
            "id": "gallery",
            "name": "Employee Directory",
            "type": "gallery",
            "cover": "avatar",
            "title": "first_name",
            "description": "email",
            "badge": "employment_status"
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
                    "employee_number",
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
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "department_id",
                    "position_id",
                    "manager_id",
                    "employment_type",
                    "employment_status"
                ]
            },
            {
                "id": "employment",
                "title": "Employment",
                "fields": [
                    "hire_date",
                    "termination_date"
                ]
            },
            {
                "id": "compensation",
                "title": "Compensation",
                "fields": [
                    "salary",
                    "currency"
                ]
            },
            {
                "id": "personal",
                "title": "Personal",
                "fields": [
                    "birth_date",
                    "address",
                    "city",
                    "country"
                ]
            },
            {
                "id": "emergency",
                "title": "Emergency Contact",
                "fields": [
                    "emergency_contact",
                    "emergency_phone"
                ]
            },
            {
                "id": "skills",
                "title": "Skills & Certifications",
                "fields": [
                    "skills",
                    "certifications",
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
            },
            {
                "table": "departments",
                "on": "department_id",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "positions",
                "on": "position_id",
                "columns": [
                    "title",
                    "level"
                ]
            }
        ]
    }
}';

comment on column hr.employees.avatar is '{"accept":"image/*"}';

revoke all on table hr.employees
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hr.employees to "x-admin";

create index idx_hr_employees_user_id on hr.employees (user_id);

create index idx_hr_employees_department_id on hr.employees (department_id);

create index idx_hr_employees_position_id on hr.employees (position_id);

create index idx_hr_employees_manager_id on hr.employees (manager_id);

create index idx_hr_employees_employment_status on hr.employees (employment_status);

create index idx_hr_employees_employment_type on hr.employees (employment_type);

create index idx_hr_employees_hire_date on hr.employees (hire_date desc);

alter table hr.employees enable row level security;

create policy employees_select on hr.employees for
select
  to authenticated using (true);

create policy employees_insert on hr.employees for insert to authenticated
with
  check (true);

create policy employees_update on hr.employees
for update
  to authenticated using (true)
with
  check (true);

create policy employees_delete on hr.employees for delete to authenticated using (true);

-- Now that hr.employees exists, link departments.manager_id
alter table hr.departments
add constraint hr_departments_manager_id_fkey foreign key (manager_id) references hr.employees (id) on delete set null;

----------------------------------------------------------------
-- Leave requests
----------------------------------------------------------------
create table hr.leave_requests (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_id uuid not null references hr.employees (id) on delete cascade,
  type hr.leave_type default 'vacation',
  status hr.leave_status default 'pending',
  start_date date not null,
  end_date date not null,
  days numeric(5, 1),
  reason supasheet.RICH_TEXT,
  response text,
  reviewer_id uuid references hr.employees (id) on delete set null,
  reviewed_at timestamptz,
  attachments supasheet.file,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hr.leave_requests.type is '{
    "progress": false,
    "values": {
        "vacation":    {"variant": "info",       "icon": "PalmTree"},
        "sick":        {"variant": "warning",    "icon": "Thermometer"},
        "personal":    {"variant": "secondary",  "icon": "User"},
        "maternity":   {"variant": "info",       "icon": "Baby"},
        "paternity":   {"variant": "info",       "icon": "Baby"},
        "bereavement": {"variant": "outline",    "icon": "Flower"},
        "unpaid":      {"variant": "outline",    "icon": "CircleSlash"}
    }
}';

comment on column hr.leave_requests.status is '{
    "progress": true,
    "values": {
        "pending":   {"variant": "warning",     "icon": "Clock"},
        "approved":  {"variant": "success",     "icon": "CircleCheck"},
        "rejected":  {"variant": "destructive", "icon": "XCircle"},
        "cancelled": {"variant": "outline",     "icon": "Ban"}
    }
}';

comment on table hr.leave_requests is '{
    "icon": "CalendarDays",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Leave Requests By Status",
            "type": "kanban",
            "group": "status",
            "title": "type",
            "description": "reason",
            "date": "start_date",
            "badge": "type"
        },
        {
            "id": "calendar",
            "name": "Leave Calendar",
            "type": "calendar",
            "title": "type",
            "badge": "status",
            "start_date": "start_date",
            "end_date": "end_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "employee_id",
                    "type",
                    "status"
                ]
            },
            {
                "id": "dates",
                "title": "Dates",
                "fields": [
                    "start_date",
                    "end_date",
                    "days"
                ]
            },
            {
                "id": "reason",
                "title": "Reason",
                "fields": [
                    "reason"
                ]
            },
            {
                "id": "review",
                "title": "Review",
                "fields": [
                    "reviewer_id",
                    "reviewed_at",
                    "response"
                ]
            },
            {
                "id": "extras",
                "title": "Attachments",
                "collapsible": true,
                "fields": [
                    "attachments"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "start_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "employees",
                "on": "employee_id",
                "alias": "employee",
                "columns": [
                    "first_name",
                    "last_name",
                    "email"
                ]
            },
            {
                "table": "employees",
                "on": "reviewer_id",
                "alias": "reviewer",
                "columns": [
                    "first_name",
                    "last_name"
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

comment on column hr.leave_requests.attachments is '{"accept":"*", "max_files": 10}';

revoke all on table hr.leave_requests
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hr.leave_requests to "x-admin";

create index idx_hr_leave_requests_employee_id on hr.leave_requests (employee_id);

create index idx_hr_leave_requests_reviewer_id on hr.leave_requests (reviewer_id);

create index idx_hr_leave_requests_status on hr.leave_requests (status);

create index idx_hr_leave_requests_type on hr.leave_requests (type);

create index idx_hr_leave_requests_start_date on hr.leave_requests (start_date desc);

alter table hr.leave_requests enable row level security;

create policy leave_requests_select on hr.leave_requests for
select
  to authenticated using (true);

create policy leave_requests_insert on hr.leave_requests for insert to authenticated
with
  check (true);

create policy leave_requests_update on hr.leave_requests
for update
  to authenticated using (true)
with
  check (true);

create policy leave_requests_delete on hr.leave_requests for delete to authenticated using (true);

----------------------------------------------------------------
-- Performance reviews
----------------------------------------------------------------
create table hr.performance_reviews (
  id uuid primary key default extensions.uuid_generate_v4 (),
  employee_id uuid not null references hr.employees (id) on delete cascade,
  reviewer_id uuid references hr.employees (id) on delete set null,
  period_start date not null,
  period_end date not null,
  rating supasheet.RATING,
  status hr.review_status default 'draft',
  summary supasheet.RICH_TEXT,
  strengths supasheet.RICH_TEXT,
  areas_for_improvement supasheet.RICH_TEXT,
  goals supasheet.RICH_TEXT,
  comments text,
  acknowledged_at timestamptz,
  attachments supasheet.file,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hr.performance_reviews.status is '{
    "progress": true,
    "values": {
        "draft":        {"variant": "outline",  "icon": "FileEdit"},
        "in_review":    {"variant": "info",     "icon": "Eye"},
        "completed":    {"variant": "success",  "icon": "CircleCheck"},
        "acknowledged": {"variant": "success",  "icon": "BadgeCheck"}
    }
}';

comment on table hr.performance_reviews is '{
    "icon": "ClipboardCheck",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Reviews By Status",
            "type": "kanban",
            "group": "status",
            "title": "summary",
            "description": "comments",
            "date": "period_end",
            "badge": "rating"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "employee_id",
                    "reviewer_id",
                    "status",
                    "rating"
                ]
            },
            {
                "id": "period",
                "title": "Review Period",
                "fields": [
                    "period_start",
                    "period_end",
                    "acknowledged_at"
                ]
            },
            {
                "id": "feedback",
                "title": "Feedback",
                "fields": [
                    "summary",
                    "strengths",
                    "areas_for_improvement",
                    "goals"
                ]
            },
            {
                "id": "extras",
                "title": "Comments & Attachments",
                "collapsible": true,
                "fields": [
                    "comments",
                    "attachments"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "period_end",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "employees",
                "on": "employee_id",
                "alias": "employee",
                "columns": [
                    "first_name",
                    "last_name",
                    "email"
                ]
            },
            {
                "table": "employees",
                "on": "reviewer_id",
                "alias": "reviewer",
                "columns": [
                    "first_name",
                    "last_name"
                ]
            }
        ]
    }
}';

comment on column hr.performance_reviews.attachments is '{"accept":"*", "max_files": 10}';

revoke all on table hr.performance_reviews
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hr.performance_reviews to "x-admin";

create index idx_hr_performance_reviews_employee_id on hr.performance_reviews (employee_id);

create index idx_hr_performance_reviews_reviewer_id on hr.performance_reviews (reviewer_id);

create index idx_hr_performance_reviews_status on hr.performance_reviews (status);

create index idx_hr_performance_reviews_period_end on hr.performance_reviews (period_end desc);

alter table hr.performance_reviews enable row level security;

create policy performance_reviews_select on hr.performance_reviews for
select
  to authenticated using (true);

create policy performance_reviews_insert on hr.performance_reviews for insert to authenticated
with
  check (true);

create policy performance_reviews_update on hr.performance_reviews
for update
  to authenticated using (true)
with
  check (true);

create policy performance_reviews_delete on hr.performance_reviews for delete to authenticated using (true);

----------------------------------------------------------------
-- Job postings
----------------------------------------------------------------
create table hr.job_postings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  title varchar(500) not null,
  description supasheet.RICH_TEXT,
  cover supasheet.file,
  department_id uuid references hr.departments (id) on delete set null,
  position_id uuid references hr.positions (id) on delete set null,
  status hr.posting_status default 'draft',
  employment_type hr.employment_type default 'full_time',
  location varchar(255),
  remote boolean default false,
  openings integer default 1,
  salary_min numeric(12, 2),
  salary_max numeric(12, 2),
  currency varchar(3) default 'USD',
  posted_at timestamptz,
  closes_at timestamptz,
  tags varchar(255) [],
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hr.job_postings.status is '{
    "progress": true,
    "values": {
        "draft":     {"variant": "outline",     "icon": "FileEdit"},
        "open":      {"variant": "success",     "icon": "CircleCheck"},
        "on_hold":   {"variant": "warning",     "icon": "PauseCircle"},
        "filled":    {"variant": "info",        "icon": "UserCheck"},
        "cancelled": {"variant": "destructive", "icon": "XCircle"}
    }
}';

comment on table hr.job_postings is '{
    "icon": "Megaphone",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Postings By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "location",
            "date": "closes_at",
            "badge": "employment_type"
        },
        {
            "id": "gallery",
            "name": "Job Board",
            "type": "gallery",
            "cover": "cover",
            "title": "title",
            "description": "location",
            "badge": "status"
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
                    "cover",
                    "status"
                ]
            },
            {
                "id": "organization",
                "title": "Organization",
                "fields": [
                    "department_id",
                    "position_id",
                    "employment_type"
                ]
            },
            {
                "id": "logistics",
                "title": "Logistics",
                "fields": [
                    "location",
                    "remote",
                    "openings"
                ]
            },
            {
                "id": "compensation",
                "title": "Compensation",
                "fields": [
                    "salary_min",
                    "salary_max",
                    "currency"
                ]
            },
            {
                "id": "schedule",
                "title": "Schedule",
                "fields": [
                    "posted_at",
                    "closes_at",
                    "tags"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "posted_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "departments",
                "on": "department_id",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "positions",
                "on": "position_id",
                "columns": [
                    "title"
                ]
            }
        ]
    }
}';

comment on column hr.job_postings.cover is '{"accept":"image/*"}';

revoke all on table hr.job_postings
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hr.job_postings to "x-admin";

create index idx_hr_job_postings_department_id on hr.job_postings (department_id);

create index idx_hr_job_postings_position_id on hr.job_postings (position_id);

create index idx_hr_job_postings_status on hr.job_postings (status);

create index idx_hr_job_postings_posted_at on hr.job_postings (posted_at desc);

alter table hr.job_postings enable row level security;

create policy job_postings_select on hr.job_postings for
select
  to authenticated using (true);

create policy job_postings_insert on hr.job_postings for insert to authenticated
with
  check (true);

create policy job_postings_update on hr.job_postings
for update
  to authenticated using (true)
with
  check (true);

create policy job_postings_delete on hr.job_postings for delete to authenticated using (true);

----------------------------------------------------------------
-- Candidates
----------------------------------------------------------------
create table hr.candidates (
  id uuid primary key default extensions.uuid_generate_v4 (),
  posting_id uuid references hr.job_postings (id) on delete set null,
  first_name varchar(255) not null,
  last_name varchar(255),
  email supasheet.EMAIL,
  phone supasheet.TEL,
  avatar supasheet.AVATAR,
  resume supasheet.file,
  cover_letter supasheet.RICH_TEXT,
  status hr.candidate_status default 'applied',
  source varchar(255),
  current_company varchar(255),
  current_title varchar(255),
  expected_salary numeric(12, 2),
  currency varchar(3) default 'USD',
  linkedin_url supasheet.URL,
  portfolio_url supasheet.URL,
  rating supasheet.RATING,
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hr.candidates.status is '{
    "progress": true,
    "values": {
        "applied":    {"variant": "outline",     "icon": "Inbox"},
        "screening":  {"variant": "info",        "icon": "Search"},
        "interview":  {"variant": "warning",     "icon": "MessagesSquare"},
        "offer":      {"variant": "info",        "icon": "FileText"},
        "hired":      {"variant": "success",     "icon": "BadgeCheck"},
        "rejected":   {"variant": "destructive", "icon": "XCircle"},
        "withdrawn":  {"variant": "outline",     "icon": "Ban"}
    }
}';

comment on table hr.candidates is '{
    "icon": "UserPlus",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Candidates By Stage",
            "type": "kanban",
            "group": "status",
            "title": "first_name",
            "description": "current_title",
            "date": "created_at",
            "badge": "source"
        },
        {
            "id": "gallery",
            "name": "Candidate Gallery",
            "type": "gallery",
            "cover": "avatar",
            "title": "first_name",
            "description": "current_title",
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
                    "cover_letter"
                ]
            },
            {
                "id": "contact",
                "title": "Contact",
                "fields": [
                    "email",
                    "phone",
                    "linkedin_url",
                    "portfolio_url"
                ]
            },
            {
                "id": "application",
                "title": "Application",
                "fields": [
                    "posting_id",
                    "status",
                    "source",
                    "resume",
                    "rating"
                ]
            },
            {
                "id": "current",
                "title": "Current Role",
                "fields": [
                    "current_company",
                    "current_title",
                    "expected_salary",
                    "currency"
                ]
            },
            {
                "id": "extras",
                "title": "Tags & Notes",
                "collapsible": true,
                "fields": [
                    "tags",
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
                "table": "job_postings",
                "on": "posting_id",
                "columns": [
                    "title",
                    "status"
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

comment on column hr.candidates.avatar is '{"accept":"image/*"}';

comment on column hr.candidates.resume is '{"accept":"application/pdf,.doc,.docx", "max_files": 1}';

revoke all on table hr.candidates
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hr.candidates to "x-admin";

create index idx_hr_candidates_posting_id on hr.candidates (posting_id);

create index idx_hr_candidates_status on hr.candidates (status);

create index idx_hr_candidates_email on hr.candidates (email);

create index idx_hr_candidates_created_at on hr.candidates (created_at desc);

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
-- Reports
----------------------------------------------------------------
create or replace view hr.employees_report
with
  (security_invoker = true) as
select
  e.id,
  e.employee_number,
  e.first_name,
  e.last_name,
  e.email,
  e.employment_type,
  e.employment_status,
  e.hire_date,
  e.salary,
  e.currency,
  d.name as department,
  p.title as position,
  m.first_name || coalesce(' ' || m.last_name, '') as manager,
  e.created_at,
  e.updated_at
from
  hr.employees e
  left join hr.departments d on d.id = e.department_id
  left join hr.positions p on p.id = e.position_id
  left join hr.employees m on m.id = e.manager_id;

revoke all on hr.employees_report
from
  authenticated,
  service_role;

grant
select
  on hr.employees_report to "x-admin";

comment on view hr.employees_report is '{"type": "report", "name": "Employees Report", "description": "All employees with department, position, and manager"}';

create or replace view hr.leave_requests_report
with
  (security_invoker = true) as
select
  lr.id,
  e.first_name || coalesce(' ' || e.last_name, '') as employee,
  e.email as employee_email,
  lr.type,
  lr.status,
  lr.start_date,
  lr.end_date,
  lr.days,
  r.first_name || coalesce(' ' || r.last_name, '') as reviewer,
  lr.reviewed_at,
  lr.created_at
from
  hr.leave_requests lr
  left join hr.employees e on e.id = lr.employee_id
  left join hr.employees r on r.id = lr.reviewer_id;

revoke all on hr.leave_requests_report
from
  authenticated,
  service_role;

grant
select
  on hr.leave_requests_report to "x-admin";

comment on view hr.leave_requests_report is '{"type": "report", "name": "Leave Requests Report", "description": "All leave requests with employee and reviewer"}';

create or replace view hr.performance_reviews_report
with
  (security_invoker = true) as
select
  pr.id,
  e.first_name || coalesce(' ' || e.last_name, '') as employee,
  e.email as employee_email,
  d.name as department,
  pr.period_start,
  pr.period_end,
  pr.rating,
  pr.status,
  r.first_name || coalesce(' ' || r.last_name, '') as reviewer,
  pr.acknowledged_at,
  pr.created_at
from
  hr.performance_reviews pr
  left join hr.employees e on e.id = pr.employee_id
  left join hr.departments d on d.id = e.department_id
  left join hr.employees r on r.id = pr.reviewer_id;

revoke all on hr.performance_reviews_report
from
  authenticated,
  service_role;

grant
select
  on hr.performance_reviews_report to "x-admin";

comment on view hr.performance_reviews_report is '{"type": "report", "name": "Performance Reviews Report", "description": "Performance reviews with employee and reviewer"}';

create or replace view hr.candidates_report
with
  (security_invoker = true) as
select
  c.id,
  c.first_name || coalesce(' ' || c.last_name, '') as candidate,
  c.email,
  c.status,
  c.source,
  jp.title as posting,
  c.current_company,
  c.current_title,
  c.expected_salary,
  c.currency,
  c.rating,
  c.created_at
from
  hr.candidates c
  left join hr.job_postings jp on jp.id = c.posting_id;

revoke all on hr.candidates_report
from
  authenticated,
  service_role;

grant
select
  on hr.candidates_report to "x-admin";

comment on view hr.candidates_report is '{"type": "report", "name": "Candidates Report", "description": "Candidates with linked job posting"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: total active headcount
create or replace view hr.headcount_summary
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      employment_status = 'active'
  ) as value,
  'users' as icon,
  'active employees' as label
from
  hr.employees;

revoke all on hr.headcount_summary
from
  authenticated,
  service_role;

grant
select
  on hr.headcount_summary to "x-admin";

-- card_2: active vs on leave
create or replace view hr.employee_status_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      employment_status = 'active'
  ) as primary,
  count(*) filter (
    where
      employment_status = 'on_leave'
  ) as secondary,
  'Active' as primary_label,
  'On Leave' as secondary_label
from
  hr.employees;

revoke all on hr.employee_status_split
from
  authenticated,
  service_role;

grant
select
  on hr.employee_status_split to "x-admin";

-- card_3: open postings + fill rate
create or replace view hr.open_positions_value
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'open'
  ) as value,
  case
    when count(*) filter (
      where
        status in ('filled', 'cancelled')
    ) > 0 then round(
      (
        count(*) filter (
          where
            status = 'filled'
        )::numeric / count(*) filter (
          where
            status in ('filled', 'cancelled')
        )::numeric
      ) * 100,
      1
    )
    else 0
  end as percent
from
  hr.job_postings;

revoke all on hr.open_positions_value
from
  authenticated,
  service_role;

grant
select
  on hr.open_positions_value to "x-admin";

-- card_4: attrition health
create or replace view hr.attrition_health
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      employment_status in ('terminated', 'retired')
      and termination_date is not null
      and termination_date >= current_date - interval '90 days'
  ) as current,
  count(*) as total,
  json_build_array(
    json_build_object(
      'label',
      'Terminated 90d',
      'value',
      count(*) filter (
        where
          employment_status = 'terminated'
          and termination_date is not null
          and termination_date >= current_date - interval '90 days'
      )
    ),
    json_build_object(
      'label',
      'On Leave',
      'value',
      count(*) filter (
        where
          employment_status = 'on_leave'
      )
    ),
    json_build_object(
      'label',
      'Suspended',
      'value',
      count(*) filter (
        where
          employment_status = 'suspended'
      )
    )
  ) as segments
from
  hr.employees;

revoke all on hr.attrition_health
from
  authenticated,
  service_role;

grant
select
  on hr.attrition_health to "x-admin";

-- table_1: recent hires
create or replace view hr.recent_hires
with
  (security_invoker = true) as
select
  first_name || coalesce(' ' || last_name, '') as name,
  coalesce(email, '') as email,
  coalesce(employment_type::text, '') as type,
  to_char(hire_date, 'MM/DD') as hired
from
  hr.employees
where
  hire_date is not null
order by
  hire_date desc
limit
  10;

revoke all on hr.recent_hires
from
  authenticated,
  service_role;

grant
select
  on hr.recent_hires to "x-admin";

-- table_2: top departments by headcount
create or replace view hr.top_departments
with
  (security_invoker = true) as
select
  d.name as department,
  coalesce(d.code, '') as code,
  count(e.id) as employees,
  coalesce(sum(e.salary), 0) as payroll
from
  hr.departments d
  left join hr.employees e on e.department_id = d.id
  and e.employment_status = 'active'
group by
  d.id,
  d.name,
  d.code
order by
  employees desc nulls last
limit
  10;

revoke all on hr.top_departments
from
  authenticated,
  service_role;

grant
select
  on hr.top_departments to "x-admin";

comment on view hr.headcount_summary is '{"type": "dashboard_widget", "name": "Headcount", "description": "Total active employees", "widget_type": "card_1"}';

comment on view hr.employee_status_split is '{"type": "dashboard_widget", "name": "Active vs On Leave", "description": "Employees split by current state", "widget_type": "card_2"}';

comment on view hr.open_positions_value is '{"type": "dashboard_widget", "name": "Open Positions", "description": "Open postings and fill rate", "widget_type": "card_3"}';

comment on view hr.attrition_health is '{"type": "dashboard_widget", "name": "Attrition Health", "description": "Recent terminations and at-risk states", "widget_type": "card_4"}';

comment on view hr.recent_hires is '{"type": "dashboard_widget", "name": "Recent Hires", "description": "Latest 10 hires by hire date", "widget_type": "table_1"}';

comment on view hr.top_departments is '{"type": "dashboard_widget", "name": "Top Departments", "description": "Top 10 departments by active headcount", "widget_type": "table_2"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: employees by department
create or replace view hr.employees_by_department_pie
with
  (security_invoker = true) as
select
  coalesce(d.name, 'Unassigned') as label,
  count(e.id) as value
from
  hr.employees e
  left join hr.departments d on d.id = e.department_id
where
  e.employment_status = 'active'
group by
  d.name
order by
  count(e.id) desc;

revoke all on hr.employees_by_department_pie
from
  authenticated,
  service_role;

grant
select
  on hr.employees_by_department_pie to "x-admin";

-- Bar: headcount by department (active vs on leave)
create or replace view hr.headcount_by_department_bar
with
  (security_invoker = true) as
select
  d.name as label,
  count(e.id) filter (
    where
      e.employment_status = 'active'
  ) as active,
  count(e.id) filter (
    where
      e.employment_status = 'on_leave'
  ) as on_leave
from
  hr.departments d
  left join hr.employees e on e.department_id = d.id
group by
  d.id,
  d.name
having
  count(e.id) > 0
order by
  count(e.id) desc
limit
  10;

revoke all on hr.headcount_by_department_bar
from
  authenticated,
  service_role;

grant
select
  on hr.headcount_by_department_bar to "x-admin";

-- Line: monthly hiring trend (last 12 months)
create or replace view hr.hiring_trend_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', hire_date), 'Mon YY') as date,
  count(*) as hires,
  count(*) filter (
    where
      employment_type = 'full_time'
  )::bigint as full_time
from
  hr.employees
where
  hire_date is not null
  and hire_date >= current_date - interval '12 months'
group by
  date_trunc('month', hire_date)
order by
  date_trunc('month', hire_date);

revoke all on hr.hiring_trend_line
from
  authenticated,
  service_role;

grant
select
  on hr.hiring_trend_line to "x-admin";

-- Radar: leave metrics by type
create or replace view hr.leave_metrics_radar
with
  (security_invoker = true) as
select
  type::text as metric,
  count(*) as total,
  count(*) filter (
    where
      status = 'approved'
  ) as approved,
  count(*) filter (
    where
      status = 'pending'
  ) as pending
from
  hr.leave_requests
group by
  type;

revoke all on hr.leave_metrics_radar
from
  authenticated,
  service_role;

grant
select
  on hr.leave_metrics_radar to "x-admin";

comment on view hr.employees_by_department_pie is '{"type": "chart", "name": "Employees By Department", "description": "Active employee headcount per department", "chart_type": "pie"}';

comment on view hr.headcount_by_department_bar is '{"type": "chart", "name": "Headcount By Department", "description": "Active vs on-leave headcount per department", "chart_type": "bar"}';

comment on view hr.hiring_trend_line is '{"type": "chart", "name": "Hiring Trend", "description": "Monthly hires over the last 12 months", "chart_type": "line"}';

comment on view hr.leave_metrics_radar is '{"type": "chart", "name": "Leave Metrics", "description": "Leave counts across types and statuses", "chart_type": "radar"}';

----------------------------------------------------------------
-- Audit triggers
----------------------------------------------------------------
create trigger audit_hr_departments_insert
after insert on hr.departments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_departments_update
after update on hr.departments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_departments_delete
before delete on hr.departments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_positions_insert
after insert on hr.positions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_positions_update
after update on hr.positions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_positions_delete
before delete on hr.positions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_employees_insert
after insert on hr.employees for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_employees_update
after update on hr.employees for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_employees_delete
before delete on hr.employees for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_leave_requests_insert
after insert on hr.leave_requests for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_leave_requests_update
after update on hr.leave_requests for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_leave_requests_delete
before delete on hr.leave_requests for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_performance_reviews_insert
after insert on hr.performance_reviews for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_performance_reviews_update
after update on hr.performance_reviews for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_performance_reviews_delete
before delete on hr.performance_reviews for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_job_postings_insert
after insert on hr.job_postings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_job_postings_update
after update on hr.job_postings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_job_postings_delete
before delete on hr.job_postings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_candidates_insert
after insert on hr.candidates for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_candidates_update
after update on hr.candidates for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hr_candidates_delete
before delete on hr.candidates for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
-- Leave requests: notify reviewer on creation, notify employee+owner on status change
create or replace function hr.trg_leave_requests_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_employee_user uuid;
    v_reviewer_user uuid;
    v_employee_name text;
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if new.employee_id is not null then
        select user_id, first_name || coalesce(' ' || last_name, '')
          into v_employee_user, v_employee_name
          from hr.employees where id = new.employee_id;
    end if;
    if new.reviewer_id is not null then
        select user_id into v_reviewer_user from hr.employees where id = new.reviewer_id;
    end if;

    if tg_op = 'INSERT' then
        v_type  := 'hr_leave_requested';
        v_title := 'New leave request';
        v_body  := coalesce(v_employee_name, 'An employee') || ' requested ' || new.type::text || ' leave.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('hr', 'leave_requests', 'update') || array[v_reviewer_user],
            null
        );
    elsif new.status is distinct from old.status then
        v_type  := 'hr_leave_status_changed';
        v_title := 'Leave request ' || new.status::text;
        v_body  := 'Leave request for ' || coalesce(v_employee_name, 'employee') || ' is now ' || new.status::text || '.';
        v_recipients := array_remove(array[v_employee_user, new.user_id], null);
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'leave_request_id', new.id,
            'employee_id',      new.employee_id,
            'type',             new.type,
            'status',           new.status
        ),
        '/hr/resource/leave_requests/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists leave_requests_notify on hr.leave_requests;

create trigger leave_requests_notify
after insert or update of status on hr.leave_requests for each row
execute function hr.trg_leave_requests_notify ();

-- Performance reviews: notify employee on completion
create or replace function hr.trg_performance_reviews_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_employee_user uuid;
    v_employee_name text;
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if new.status is not distinct from old.status then
        return new;
    end if;
    if new.status not in ('completed', 'acknowledged') then
        return new;
    end if;

    if new.employee_id is not null then
        select user_id, first_name || coalesce(' ' || last_name, '')
          into v_employee_user, v_employee_name
          from hr.employees where id = new.employee_id;
    end if;

    v_recipients := array_remove(array[v_employee_user], null);

    v_type  := 'hr_review_' || new.status::text;
    v_title := 'Performance review ' || new.status::text;
    v_body  := 'Review for ' || coalesce(v_employee_name, 'employee') ||
               ' (' || to_char(new.period_start, 'YYYY-MM-DD') ||
               ' – ' || to_char(new.period_end, 'YYYY-MM-DD') || ') is ' || new.status::text || '.';

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'review_id',   new.id,
            'employee_id', new.employee_id,
            'status',      new.status,
            'rating',      new.rating
        ),
        '/hr/resource/performance_reviews/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists performance_reviews_notify on hr.performance_reviews;

create trigger performance_reviews_notify
after update of status on hr.performance_reviews for each row
execute function hr.trg_performance_reviews_notify ();

-- Candidates: notify recruiters on creation and status change
create or replace function hr.trg_candidates_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type   text;
    v_title  text;
    v_body   text;
begin
    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('hr', 'candidates', 'update') || array[new.user_id],
        null
    );

    if tg_op = 'INSERT' then
        v_type  := 'hr_candidate_applied';
        v_title := 'New candidate';
        v_body  := new.first_name || coalesce(' ' || new.last_name, '') || ' applied.';
    elsif new.status is distinct from old.status then
        v_type  := 'hr_candidate_status_changed';
        v_title := 'Candidate stage updated';
        v_body  := new.first_name || coalesce(' ' || new.last_name, '') ||
                   ' moved to ' || new.status::text || '.';
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'candidate_id', new.id,
            'posting_id',   new.posting_id,
            'status',       new.status
        ),
        '/hr/resource/candidates/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists candidates_notify on hr.candidates;

create trigger candidates_notify
after insert or update of status on hr.candidates for each row
execute function hr.trg_candidates_notify ();
