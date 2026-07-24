create schema if not exists hostel;

grant usage on schema hostel to authenticated;

----------------------------------------------------------------
-- Enums + permissions (must commit before use)
----------------------------------------------------------------
begin;

create type hostel.gender as enum('male', 'female', 'co_ed');

create type hostel.room_type as enum('single', 'double', 'triple', 'quad', 'dormitory');

create type hostel.room_status as enum(
  'available',
  'occupied',
  'maintenance',
  'reserved'
);

create type hostel.allocation_status as enum('pending', 'active', 'ended', 'terminated');

create type hostel.payment_status as enum('pending', 'paid', 'overdue', 'refunded');

create type hostel.payment_method as enum(
  'cash',
  'bank_transfer',
  'credit_card',
  'upi',
  'cheque'
);

create type hostel.complaint_category as enum(
  'plumbing',
  'electrical',
  'cleaning',
  'security',
  'food',
  'internet',
  'furniture',
  'other'
);

create type hostel.complaint_priority as enum('low', 'medium', 'high', 'urgent');

create type hostel.complaint_status as enum(
  'open',
  'in_progress',
  'resolved',
  'closed',
  'rejected'
);

create type hostel.visitor_status as enum('checked_in', 'checked_out');

commit;

----------------------------------------------------------------
-- Hostels table
----------------------------------------------------------------
create table hostel.hostels (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(50) unique,
  name varchar(255) not null,
  description supasheet.RICH_TEXT,
  gender hostel.gender not null default 'co_ed',
  address text,
  city varchar(100),
  state varchar(100),
  pincode varchar(20),
  contact_phone supasheet.TEL,
  contact_email supasheet.EMAIL,
  warden_id uuid references supasheet.users (id) on delete set null,
  total_rooms integer not null default 0,
  total_capacity integer not null default 0,
  image supasheet.file,
  active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hostel.hostels.gender is '{
    "values": {
        "male": {
            "variant": "info",
            "icon": "Mars"
        },
        "female": {
            "variant": "info",
            "icon": "Venus"
        },
        "co_ed": {
            "variant": "secondary",
            "icon": "Users"
        }
    }
}';

comment on table hostel.hostels is '{
    "icon": "Building2",
    "display": "block",
    "primary_view": "gallery",
    "views": [
        {
            "id": "gallery",
            "name": "Hostel Gallery",
            "type": "gallery",
            "cover": "image",
            "title": "name",
            "description": "description",
            "badge": "gender"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Identity",
                "fields": [
                    "name",
                    "code",
                    "description",
                    "image"
                ]
            },
            {
                "id": "config",
                "title": "Configuration",
                "fields": [
                    "gender",
                    "total_rooms",
                    "total_capacity",
                    "active"
                ]
            },
            {
                "id": "location",
                "title": "Location",
                "fields": [
                    "address",
                    "city",
                    "state",
                    "pincode"
                ]
            },
            {
                "id": "contact",
                "title": "Contact",
                "description": "Warden and contact information",
                "fields": [
                    "warden_id",
                    "contact_phone",
                    "contact_email"
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
                "on": "warden_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column hostel.hostels.image is '{"accept": "image/*"}';

revoke all on table hostel.hostels
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hostel.hostels to "x-admin";

create index idx_hostel_hostels_code on hostel.hostels (code);

create index idx_hostel_hostels_warden_id on hostel.hostels (warden_id);

create index idx_hostel_hostels_active on hostel.hostels (active)
where
  active = true;

alter table hostel.hostels enable row level security;

create policy hostels_select on hostel.hostels for
select
  to authenticated using (true);

create policy hostels_insert on hostel.hostels for insert to authenticated
with
  check (true);

create policy hostels_update on hostel.hostels
for update
  to authenticated using (true)
with
  check (true);

create policy hostels_delete on hostel.hostels for delete to authenticated using (true);

----------------------------------------------------------------
-- Rooms table
----------------------------------------------------------------
create table hostel.rooms (
  id uuid primary key default extensions.uuid_generate_v4 (),
  hostel_id uuid not null references hostel.hostels (id) on delete cascade,
  room_number varchar(50) not null,
  floor integer not null default 0,
  type hostel.room_type not null default 'double',
  capacity integer not null default 2,
  occupied integer not null default 0,
  monthly_rent numeric(10, 2) not null default 0,
  security_deposit numeric(10, 2) not null default 0,
  status hostel.room_status not null default 'available',
  amenities varchar(100) [],
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (hostel_id, room_number)
);

comment on column hostel.rooms.type is '{
    "values": {
        "single": {
            "variant": "info",
            "icon": "User"
        },
        "double": {
            "variant": "info",
            "icon": "Users"
        },
        "triple": {
            "variant": "secondary",
            "icon": "Users"
        },
        "quad": {
            "variant": "secondary",
            "icon": "Users"
        },
        "dormitory": {
            "variant": "outline",
            "icon": "BedDouble"
        }
    }
}';

comment on column hostel.rooms.status is '{
    "progress": false,
    "values": {
        "available": {
            "variant": "success",
            "icon": "CircleCheck"
        },
        "occupied": {
            "variant": "info",
            "icon": "BedDouble"
        },
        "maintenance": {
            "variant": "warning",
            "icon": "Wrench"
        },
        "reserved": {
            "variant": "outline",
            "icon": "Bookmark"
        }
    }
}';

comment on table hostel.rooms is '{
    "icon": "BedDouble",
    "display": "block",
    "views": [
        {
            "id": "status",
            "name": "Rooms By Status",
            "type": "kanban",
            "group": "status",
            "title": "room_number",
            "description": "notes",
            "badge": "type"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Identity",
                "fields": [
                    "hostel_id",
                    "room_number",
                    "floor"
                ]
            },
            {
                "id": "config",
                "title": "Configuration",
                "fields": [
                    "type",
                    "capacity",
                    "occupied",
                    "status"
                ]
            },
            {
                "id": "pricing",
                "title": "Pricing",
                "fields": [
                    "monthly_rent",
                    "security_deposit"
                ]
            },
            {
                "id": "extras",
                "title": "Extras",
                "collapsible": true,
                "fields": [
                    "amenities",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "room_number",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "hostels",
                "on": "hostel_id",
                "columns": [
                    "name",
                    "code"
                ]
            }
        ]
    }
}';

revoke all on table hostel.rooms
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hostel.rooms to "x-admin";

create index idx_hostel_rooms_hostel_id on hostel.rooms (hostel_id);

create index idx_hostel_rooms_status on hostel.rooms (status);

create index idx_hostel_rooms_type on hostel.rooms (type);

alter table hostel.rooms enable row level security;

create policy rooms_select on hostel.rooms for
select
  to authenticated using (true);

create policy rooms_insert on hostel.rooms for insert to authenticated
with
  check (true);

create policy rooms_update on hostel.rooms
for update
  to authenticated using (true)
with
  check (true);

create policy rooms_delete on hostel.rooms for delete to authenticated using (true);

----------------------------------------------------------------
-- Residents table
----------------------------------------------------------------
create table hostel.residents (
  id uuid primary key default extensions.uuid_generate_v4 (),
  user_id uuid references supasheet.users (id) on delete set null,
  enrollment_no varchar(50) unique,
  name varchar(255) not null,
  email supasheet.EMAIL,
  phone supasheet.TEL,
  gender hostel.gender,
  date_of_birth date,
  course varchar(150),
  year_of_study integer,
  institution varchar(255),
  address text,
  city varchar(100),
  state varchar(100),
  pincode varchar(20),
  guardian_name varchar(255),
  guardian_phone supasheet.TEL,
  guardian_relation varchar(100),
  photo supasheet.file,
  id_document supasheet.file,
  active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table hostel.residents is '{
    "icon": "GraduationCap",
    "display": "block",
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Identity",
                "fields": [
                    "name",
                    "enrollment_no",
                    "user_id",
                    "photo"
                ]
            },
            {
                "id": "personal",
                "title": "Personal",
                "fields": [
                    "gender",
                    "date_of_birth",
                    "email",
                    "phone"
                ]
            },
            {
                "id": "academic",
                "title": "Academic",
                "fields": [
                    "course",
                    "year_of_study",
                    "institution"
                ]
            },
            {
                "id": "guardian",
                "title": "Guardian / Emergency Contact",
                "fields": [
                    "guardian_name",
                    "guardian_relation",
                    "guardian_phone"
                ]
            },
            {
                "id": "address",
                "title": "Permanent Address",
                "collapsible": true,
                "fields": [
                    "address",
                    "city",
                    "state",
                    "pincode"
                ]
            },
            {
                "id": "documents",
                "title": "Documents",
                "collapsible": true,
                "fields": [
                    "id_document",
                    "active"
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

comment on column hostel.residents.photo is '{"accept": "image/*"}';

comment on column hostel.residents.id_document is '{"accept": "image/*,application/pdf"}';

revoke all on table hostel.residents
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hostel.residents to "x-admin";

create index idx_hostel_residents_user_id on hostel.residents (user_id);

create index idx_hostel_residents_enrollment_no on hostel.residents (enrollment_no);

create index idx_hostel_residents_active on hostel.residents (active)
where
  active = true;

alter table hostel.residents enable row level security;

create policy residents_select on hostel.residents for
select
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
  );

create policy residents_insert on hostel.residents for insert to authenticated
with
  check (true);

create policy residents_update on hostel.residents
for update
  to authenticated using (true)
with
  check (true);

create policy residents_delete on hostel.residents for delete to authenticated using (true);

----------------------------------------------------------------
-- Allocations table
----------------------------------------------------------------
create table hostel.allocations (
  id uuid primary key default extensions.uuid_generate_v4 (),
  allocation_no varchar(50) unique,
  resident_id uuid not null references hostel.residents (id) on delete cascade,
  room_id uuid not null references hostel.rooms (id) on delete restrict,
  bed_number integer,
  start_date date not null default current_date,
  end_date date,
  monthly_rent numeric(10, 2) not null default 0,
  security_deposit numeric(10, 2) not null default 0,
  status hostel.allocation_status not null default 'pending',
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hostel.allocations.status is '{
    "progress": true,
    "values": {
        "pending": {
            "variant": "warning",
            "icon": "Clock"
        },
        "active": {
            "variant": "success",
            "icon": "CircleCheck"
        },
        "ended": {
            "variant": "secondary",
            "icon": "CircleStop"
        },
        "terminated": {
            "variant": "destructive",
            "icon": "XCircle"
        }
    }
}';

comment on table hostel.allocations is '{
    "icon": "ClipboardList",
    "display": "block",
    "views": [
        {
            "id": "status",
            "name": "Allocations By Status",
            "type": "kanban",
            "group": "status",
            "title": "allocation_no",
            "description": "notes",
            "date": "start_date",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Allocation Calendar",
            "type": "calendar",
            "title": "allocation_no",
            "badge": "status",
            "start_date": "start_date",
            "end_date": "end_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Allocation",
                "fields": [
                    "allocation_no",
                    "resident_id",
                    "room_id",
                    "bed_number"
                ]
            },
            {
                "id": "term",
                "title": "Term",
                "fields": [
                    "start_date",
                    "end_date",
                    "status"
                ]
            },
            {
                "id": "amounts",
                "title": "Amounts",
                "fields": [
                    "monthly_rent",
                    "security_deposit"
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
        ],
        "quick_create": [
            "resident_id",
            "room_id",
            "start_date"
        ],
        "lookups": {
            "room_id": {
                "fill": [
                    {
                        "source_column": "monthly_rent",
                        "target_column": "monthly_rent"
                    },
                    {
                        "source_column": "security_deposit",
                        "target_column": "security_deposit"
                    }
                ]
            }
        }
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
                "table": "residents",
                "on": "resident_id",
                "columns": [
                    "name",
                    "enrollment_no"
                ]
            },
            {
                "table": "rooms",
                "on": "room_id",
                "columns": [
                    "room_number",
                    "type"
                ]
            }
        ]
    }
}';

revoke all on table hostel.allocations
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hostel.allocations to "x-admin";

create index idx_hostel_allocations_resident_id on hostel.allocations (resident_id);

create index idx_hostel_allocations_room_id on hostel.allocations (room_id);

create index idx_hostel_allocations_status on hostel.allocations (status);

create index idx_hostel_allocations_start_date on hostel.allocations (start_date desc);

alter table hostel.allocations enable row level security;

create policy allocations_select on hostel.allocations for
select
  to authenticated using (
    exists (
      select
        1
      from
        hostel.residents r
      where
        r.id = hostel.allocations.resident_id
        and r.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy allocations_insert on hostel.allocations for insert to authenticated
with
  check (true);

create policy allocations_update on hostel.allocations
for update
  to authenticated using (true)
with
  check (true);

create policy allocations_delete on hostel.allocations for delete to authenticated using (true);

----------------------------------------------------------------
-- Payments table
----------------------------------------------------------------
create table hostel.payments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  receipt_no varchar(50) unique,
  allocation_id uuid not null references hostel.allocations (id) on delete cascade,
  resident_id uuid not null references hostel.residents (id) on delete cascade,
  period_month date not null,
  amount numeric(10, 2) not null default 0,
  late_fee numeric(10, 2) not null default 0,
  total numeric(10, 2) not null default 0,
  due_date date not null,
  paid_date date,
  status hostel.payment_status not null default 'pending',
  method hostel.payment_method,
  reference varchar(100),
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hostel.payments.status is '{
    "progress": true,
    "values": {
        "pending": {
            "variant": "warning",
            "icon": "Clock"
        },
        "paid": {
            "variant": "success",
            "icon": "CircleCheck"
        },
        "overdue": {
            "variant": "destructive",
            "icon": "AlertTriangle"
        },
        "refunded": {
            "variant": "outline",
            "icon": "RotateCcw"
        }
    }
}';

comment on column hostel.payments.method is '{
    "values": {
        "cash": {
            "variant": "outline",
            "icon": "Banknote"
        },
        "bank_transfer": {
            "variant": "info",
            "icon": "Landmark"
        },
        "credit_card": {
            "variant": "info",
            "icon": "CreditCard"
        },
        "upi": {
            "variant": "info",
            "icon": "Smartphone"
        },
        "cheque": {
            "variant": "outline",
            "icon": "FileText"
        }
    }
}';

comment on table hostel.payments is '{
    "icon": "CreditCard",
    "display": "block",
    "views": [
        {
            "id": "status",
            "name": "Payments By Status",
            "type": "kanban",
            "group": "status",
            "title": "receipt_no",
            "description": "notes",
            "date": "due_date",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Payment Calendar",
            "type": "calendar",
            "title": "receipt_no",
            "badge": "status",
            "start_date": "due_date"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Payment",
                "fields": [
                    "receipt_no",
                    "resident_id",
                    "allocation_id",
                    "period_month"
                ]
            },
            {
                "id": "amounts",
                "title": "Amounts",
                "fields": [
                    "amount",
                    "late_fee",
                    "total"
                ]
            },
            {
                "id": "schedule",
                "title": "Schedule",
                "fields": [
                    "due_date",
                    "paid_date",
                    "status"
                ]
            },
            {
                "id": "method",
                "title": "Method",
                "fields": [
                    "method",
                    "reference"
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
        ],
        "behavior": {
            "paid_date": {
                "visible": [
                    {
                        "id": "status",
                        "operator": "eq",
                        "value": "paid"
                    }
                ]
            },
            "reference": {
                "visible": [
                    {
                        "id": "method",
                        "operator": "in",
                        "value": ["bank_transfer", "credit_card", "upi", "cheque"]
                    }
                ]
            }
        }
    },
    "query": {
        "sort": [
            {
                "id": "due_date",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "allocations",
                "on": "allocation_id",
                "columns": [
                    "allocation_no"
                ]
            },
            {
                "table": "residents",
                "on": "resident_id",
                "columns": [
                    "name",
                    "enrollment_no"
                ]
            }
        ]
    }
}';

revoke all on table hostel.payments
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hostel.payments to "x-admin";

create index idx_hostel_payments_allocation_id on hostel.payments (allocation_id);

create index idx_hostel_payments_resident_id on hostel.payments (resident_id);

create index idx_hostel_payments_status on hostel.payments (status);

create index idx_hostel_payments_due_date on hostel.payments (due_date desc);

create index idx_hostel_payments_period_month on hostel.payments (period_month desc);

alter table hostel.payments enable row level security;

create policy payments_select on hostel.payments for
select
  to authenticated using (
    exists (
      select
        1
      from
        hostel.residents r
      where
        r.id = hostel.payments.resident_id
        and r.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy payments_insert on hostel.payments for insert to authenticated
with
  check (true);

create policy payments_update on hostel.payments
for update
  to authenticated using (true)
with
  check (true);

create policy payments_delete on hostel.payments for delete to authenticated using (true);

----------------------------------------------------------------
-- Complaints table
----------------------------------------------------------------
create table hostel.complaints (
  id uuid primary key default extensions.uuid_generate_v4 (),
  ticket_no varchar(50) unique,
  resident_id uuid references hostel.residents (id) on delete set null,
  room_id uuid references hostel.rooms (id) on delete set null,
  hostel_id uuid references hostel.hostels (id) on delete set null,
  category hostel.complaint_category not null default 'other',
  priority hostel.complaint_priority not null default 'medium',
  status hostel.complaint_status not null default 'open',
  title varchar(255) not null,
  description supasheet.RICH_TEXT,
  assigned_to uuid references supasheet.users (id) on delete set null,
  resolution text,
  resolved_at timestamptz,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hostel.complaints.priority is '{
    "values": {
        "low": {
            "variant": "secondary",
            "icon": "Minus"
        },
        "medium": {
            "variant": "info",
            "icon": "Equal"
        },
        "high": {
            "variant": "warning",
            "icon": "TrendingUp"
        },
        "urgent": {
            "variant": "destructive",
            "icon": "AlertTriangle"
        }
    }
}';

comment on column hostel.complaints.status is '{
    "progress": true,
    "values": {
        "open": {
            "variant": "warning",
            "icon": "Clock"
        },
        "in_progress": {
            "variant": "info",
            "icon": "Loader"
        },
        "resolved": {
            "variant": "success",
            "icon": "CircleCheck"
        },
        "closed": {
            "variant": "secondary",
            "icon": "CircleStop"
        },
        "rejected": {
            "variant": "destructive",
            "icon": "XCircle"
        }
    }
}';

comment on column hostel.complaints.category is '{
    "values": {
        "plumbing": {"variant": "info", "icon": "Droplet"},
        "electrical": {"variant": "warning", "icon": "Zap"},
        "cleaning": {"variant": "secondary", "icon": "Sparkles"},
        "security": {"variant": "destructive", "icon": "Shield"},
        "food": {"variant": "info", "icon": "Utensils"},
        "internet": {"variant": "info", "icon": "Wifi"},
        "furniture": {"variant": "secondary", "icon": "Sofa"},
        "other": {"variant": "outline", "icon": "Circle"}
    }
}';

comment on table hostel.complaints is '{
    "icon": "MessageSquareWarning",
    "display": "block",
    "views": [
        {
            "id": "status",
            "name": "Complaints By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "description",
            "date": "created_at",
            "badge": "priority"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Ticket",
                "fields": [
                    "ticket_no",
                    "title",
                    "description"
                ]
            },
            {
                "id": "context",
                "title": "Context",
                "fields": [
                    "resident_id",
                    "room_id",
                    "hostel_id"
                ]
            },
            {
                "id": "triage",
                "title": "Triage",
                "fields": [
                    "category",
                    "priority",
                    "status",
                    "assigned_to"
                ]
            },
            {
                "id": "resolution",
                "title": "Resolution",
                "collapsible": true,
                "fields": [
                    "resolution",
                    "resolved_at"
                ]
            }
        ],
        "behavior": {
            "resolution": {
                "visible": [
                    {
                        "id": "status",
                        "operator": "in",
                        "value": ["resolved", "closed"]
                    }
                ]
            },
            "resolved_at": {
                "visible": [
                    {
                        "id": "status",
                        "operator": "in",
                        "value": ["resolved", "closed"]
                    }
                ]
            }
        },
        "lookups": {
            "room_id": {
                "filter": [
                    {
                        "source_column": "hostel_id",
                        "target_column": "hostel_id"
                    }
                ]
            }
        }
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
                "table": "residents",
                "on": "resident_id",
                "columns": [
                    "name",
                    "enrollment_no"
                ]
            },
            {
                "table": "rooms",
                "on": "room_id",
                "columns": [
                    "room_number"
                ]
            },
            {
                "table": "hostels",
                "on": "hostel_id",
                "columns": [
                    "name",
                    "code"
                ]
            },
            {
                "table": "users",
                "on": "assigned_to",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

revoke all on table hostel.complaints
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hostel.complaints to "x-admin";

create index idx_hostel_complaints_resident_id on hostel.complaints (resident_id);

create index idx_hostel_complaints_room_id on hostel.complaints (room_id);

create index idx_hostel_complaints_hostel_id on hostel.complaints (hostel_id);

create index idx_hostel_complaints_status on hostel.complaints (status);

create index idx_hostel_complaints_priority on hostel.complaints (priority);

create index idx_hostel_complaints_assigned_to on hostel.complaints (assigned_to);

create index idx_hostel_complaints_created_at on hostel.complaints (created_at desc);

alter table hostel.complaints enable row level security;

create policy complaints_select on hostel.complaints for
select
  to authenticated using (
    exists (
      select
        1
      from
        hostel.residents r
      where
        r.id = hostel.complaints.resident_id
        and r.user_id = (
          select
            auth.uid ()
        )
    )
    or assigned_to = (
      select
        auth.uid ()
    )
  );

create policy complaints_insert on hostel.complaints for insert to authenticated
with
  check (true);

create policy complaints_update on hostel.complaints
for update
  to authenticated using (true)
with
  check (true);

create policy complaints_delete on hostel.complaints for delete to authenticated using (true);

----------------------------------------------------------------
-- Visitors table
----------------------------------------------------------------
create table hostel.visitors (
  id uuid primary key default extensions.uuid_generate_v4 (),
  resident_id uuid not null references hostel.residents (id) on delete cascade,
  name varchar(255) not null,
  phone supasheet.TEL,
  relation varchar(100),
  purpose text,
  id_proof varchar(100),
  check_in timestamptz not null default current_timestamp,
  check_out timestamptz,
  status hostel.visitor_status not null default 'checked_in',
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column hostel.visitors.status is '{
    "progress": true,
    "values": {
        "checked_in": {
            "variant": "info",
            "icon": "LogIn"
        },
        "checked_out": {
            "variant": "success",
            "icon": "LogOut"
        }
    }
}';

comment on table hostel.visitors is '{
    "icon": "UserCheck",
    "display": "block",
    "views": [
        {
            "id": "calendar",
            "name": "Visitor Calendar",
            "type": "calendar",
            "title": "name",
            "badge": "status",
            "start_date": "check_in",
            "end_date": "check_out"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Visitor",
                "fields": [
                    "name",
                    "phone",
                    "relation",
                    "id_proof"
                ]
            },
            {
                "id": "context",
                "title": "Context",
                "fields": [
                    "resident_id",
                    "purpose"
                ]
            },
            {
                "id": "log",
                "title": "Check-in / Check-out",
                "fields": [
                    "check_in",
                    "check_out",
                    "status"
                ]
            }
        ],
        "behavior": {
            "check_out": {
                "visible": [
                    {
                        "id": "status",
                        "operator": "eq",
                        "value": "checked_out"
                    }
                ]
            }
        }
    },
    "query": {
        "sort": [
            {
                "id": "check_in",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "residents",
                "on": "resident_id",
                "columns": [
                    "name",
                    "enrollment_no"
                ]
            }
        ]
    }
}';

revoke all on table hostel.visitors
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table hostel.visitors to "x-admin";

create index idx_hostel_visitors_resident_id on hostel.visitors (resident_id);

create index idx_hostel_visitors_status on hostel.visitors (status);

create index idx_hostel_visitors_check_in on hostel.visitors (check_in desc);

alter table hostel.visitors enable row level security;

create policy visitors_select on hostel.visitors for
select
  to authenticated using (
    exists (
      select
        1
      from
        hostel.residents r
      where
        r.id = hostel.visitors.resident_id
        and r.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy visitors_insert on hostel.visitors for insert to authenticated
with
  check (true);

create policy visitors_update on hostel.visitors
for update
  to authenticated using (true)
with
  check (true);

create policy visitors_delete on hostel.visitors for delete to authenticated using (true);

----------------------------------------------------------------
-- Users mirror (for Postgrest joins)
----------------------------------------------------------------
create or replace view hostel.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on hostel.users
from
  authenticated,
  service_role;

grant
select
  on hostel.users to "x-admin";

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view hostel.occupancy_report
with
  (security_invoker = true) as
select
  h.id as hostel_id,
  h.code,
  h.name as hostel,
  h.gender,
  count(r.id) as total_rooms,
  coalesce(sum(r.capacity), 0) as total_capacity,
  coalesce(sum(r.occupied), 0) as total_occupied,
  case
    when coalesce(sum(r.capacity), 0) > 0 then round(
      (
        sum(r.occupied)::numeric / sum(r.capacity)::numeric
      ) * 100,
      1
    )
    else 0
  end as occupancy_percent,
  count(r.id) filter (
    where
      r.status = 'available'
  ) as available_rooms,
  count(r.id) filter (
    where
      r.status = 'maintenance'
  ) as maintenance_rooms
from
  hostel.hostels h
  left join hostel.rooms r on r.hostel_id = h.id
group by
  h.id
order by
  occupancy_percent desc;

revoke all on hostel.occupancy_report
from
  authenticated,
  service_role;

grant
select
  on hostel.occupancy_report to "x-admin";

comment on view hostel.occupancy_report is '{"type": "report", "name": "Occupancy Report", "description": "Per-hostel room and bed utilization"}';

create or replace view hostel.payment_report
with
  (security_invoker = true) as
select
  p.id,
  p.receipt_no,
  res.name as resident,
  res.enrollment_no,
  a.allocation_no,
  p.period_month,
  p.amount,
  p.late_fee,
  p.total,
  p.due_date,
  p.paid_date,
  p.status,
  p.method,
  p.reference,
  p.created_at
from
  hostel.payments p
  join hostel.residents res on res.id = p.resident_id
  join hostel.allocations a on a.id = p.allocation_id
order by
  p.due_date desc;

revoke all on hostel.payment_report
from
  authenticated,
  service_role;

grant
select
  on hostel.payment_report to "x-admin";

comment on view hostel.payment_report is '{"type": "report", "name": "Payment Report", "description": "All resident payments with status and method"}';

create or replace view hostel.complaint_report
with
  (security_invoker = true) as
select
  c.id,
  c.ticket_no,
  c.title,
  c.category,
  c.priority,
  c.status,
  h.name as hostel,
  rm.room_number,
  res.name as resident,
  u.name as assigned,
  c.created_at,
  c.resolved_at,
  case
    when c.resolved_at is not null then extract(
      epoch
      from
        (c.resolved_at - c.created_at)
    ) / 3600
  end as resolution_hours
from
  hostel.complaints c
  left join hostel.hostels h on h.id = c.hostel_id
  left join hostel.rooms rm on rm.id = c.room_id
  left join hostel.residents res on res.id = c.resident_id
  left join supasheet.users u on u.id = c.assigned_to
order by
  c.created_at desc;

revoke all on hostel.complaint_report
from
  authenticated,
  service_role;

grant
select
  on hostel.complaint_report to "x-admin";

comment on view hostel.complaint_report is '{"type": "report", "name": "Complaint Report", "description": "Tickets with category, priority, status, and resolution time"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- Card1: total revenue
create or replace view hostel.revenue_summary
with
  (security_invoker = true) as
select
  coalesce(sum(total), 0) as value,
  'credit-card' as icon,
  'collected revenue' as label
from
  hostel.payments
where
  status = 'paid';

revoke all on hostel.revenue_summary
from
  authenticated,
  service_role;

grant
select
  on hostel.revenue_summary to "x-admin";

-- Card2: occupancy rate (occupied vs available capacity)
create or replace view hostel.occupancy_rate
with
  (security_invoker = true) as
select
  coalesce(sum(occupied), 0) as primary,
  greatest(
    coalesce(sum(capacity), 0) - coalesce(sum(occupied), 0),
    0
  ) as secondary,
  'Occupied' as primary_label,
  'Vacant' as secondary_label
from
  hostel.rooms;

revoke all on hostel.occupancy_rate
from
  authenticated,
  service_role;

grant
select
  on hostel.occupancy_rate to "x-admin";

-- Card3: active complaints with resolution rate
create or replace view hostel.active_complaints
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status in ('open', 'in_progress')
  ) as value,
  case
    when count(*) > 0 then round(
      (
        count(*) filter (
          where
            status = 'resolved'
        )::numeric / count(*)::numeric
      ) * 100,
      1
    )
    else 0
  end as percent
from
  hostel.complaints;

revoke all on hostel.active_complaints
from
  authenticated,
  service_role;

grant
select
  on hostel.active_complaints to "x-admin";

-- Card4: pending payments alert
create or replace view hostel.pending_payments
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status in ('pending', 'overdue')
  ) as current,
  count(*) as total,
  json_build_array(
    json_build_object(
      'label',
      'Overdue',
      'value',
      count(*) filter (
        where
          status = 'overdue'
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
      'Paid',
      'value',
      count(*) filter (
        where
          status = 'paid'
      )
    )
  ) as segments
from
  hostel.payments;

revoke all on hostel.pending_payments
from
  authenticated,
  service_role;

grant
select
  on hostel.pending_payments to "x-admin";

-- Table1: recent allocations
create or replace view hostel.recent_allocations
with
  (security_invoker = true) as
select
  a.allocation_no,
  res.name as resident,
  rm.room_number,
  h.name as hostel,
  a.status,
  to_char(a.start_date, 'MM/DD') as start_date
from
  hostel.allocations a
  join hostel.residents res on res.id = a.resident_id
  join hostel.rooms rm on rm.id = a.room_id
  join hostel.hostels h on h.id = rm.hostel_id
order by
  a.created_at desc
limit
  10;

revoke all on hostel.recent_allocations
from
  authenticated,
  service_role;

grant
select
  on hostel.recent_allocations to "x-admin";

-- Table2: top hostels by occupancy
create or replace view hostel.top_hostels
with
  (security_invoker = true) as
select
  h.name as hostel,
  h.code,
  h.gender,
  coalesce(sum(r.capacity), 0) as capacity,
  coalesce(sum(r.occupied), 0) as occupied,
  case
    when coalesce(sum(r.capacity), 0) > 0 then round(
      (
        sum(r.occupied)::numeric / sum(r.capacity)::numeric
      ) * 100,
      1
    )
    else 0
  end as occupancy_percent
from
  hostel.hostels h
  left join hostel.rooms r on r.hostel_id = h.id
group by
  h.id,
  h.name,
  h.code,
  h.gender
order by
  occupancy_percent desc
limit
  10;

revoke all on hostel.top_hostels
from
  authenticated,
  service_role;

grant
select
  on hostel.top_hostels to "x-admin";

comment on view hostel.revenue_summary is '{"type": "dashboard_widget", "name": "Collected Revenue", "description": "Total paid payments collected", "widget_type": "card_1"}';

comment on view hostel.occupancy_rate is '{"type": "dashboard_widget", "name": "Occupancy", "description": "Occupied vs vacant beds", "widget_type": "card_2"}';

comment on view hostel.active_complaints is '{"type": "dashboard_widget", "name": "Active Complaints", "description": "Open complaints with overall resolution rate", "widget_type": "card_3"}';

comment on view hostel.pending_payments is '{"type": "dashboard_widget", "name": "Payment Status", "description": "Pending and overdue payment breakdown", "widget_type": "card_4"}';

comment on view hostel.recent_allocations is '{"type": "dashboard_widget", "name": "Recent Allocations", "description": "Latest room allocations", "widget_type": "table_1"}';

comment on view hostel.top_hostels is '{"type": "dashboard_widget", "name": "Top Hostels", "description": "Hostels ranked by occupancy", "widget_type": "table_2"}';

----------------------------------------------------------------
-- Chart views
----------------------------------------------------------------
-- Pie: rooms by status
create or replace view hostel.room_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  hostel.rooms
group by
  status;

revoke all on hostel.room_status_pie
from
  authenticated,
  service_role;

grant
select
  on hostel.room_status_pie to "x-admin";

-- Line: monthly revenue collected (last 6 months)
create or replace view hostel.revenue_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', period_month), 'Mon YYYY') as date,
  count(*) filter (
    where
      status = 'paid'
  ) as paid_count,
  coalesce(
    sum(total) filter (
      where
        status = 'paid'
    ),
    0
  ) as revenue
from
  hostel.payments
where
  period_month >= (current_date - interval '6 months')
group by
  date_trunc('month', period_month)
order by
  date_trunc('month', period_month);

revoke all on hostel.revenue_line
from
  authenticated,
  service_role;

grant
select
  on hostel.revenue_line to "x-admin";

-- Bar: complaints by category
create or replace view hostel.complaints_category_bar
with
  (security_invoker = true) as
select
  category::text as label,
  count(*) as total,
  count(*) filter (
    where
      status in ('resolved', 'closed')
  ) as resolved
from
  hostel.complaints
group by
  category
order by
  total desc;

revoke all on hostel.complaints_category_bar
from
  authenticated,
  service_role;

grant
select
  on hostel.complaints_category_bar to "x-admin";

-- Radar: occupancy metrics by hostel
create or replace view hostel.occupancy_metrics_radar
with
  (security_invoker = true) as
select
  h.name as metric,
  coalesce(sum(r.capacity), 0) as capacity,
  coalesce(sum(r.occupied), 0) as occupied,
  count(r.id) as rooms
from
  hostel.hostels h
  left join hostel.rooms r on r.hostel_id = h.id
group by
  h.id,
  h.name
order by
  h.name;

revoke all on hostel.occupancy_metrics_radar
from
  authenticated,
  service_role;

grant
select
  on hostel.occupancy_metrics_radar to "x-admin";

comment on view hostel.room_status_pie is '{"type": "chart", "name": "Rooms by Status", "description": "Current room status breakdown", "chart_type": "pie"}';

comment on view hostel.revenue_line is '{"type": "chart", "name": "Monthly Revenue", "description": "Revenue trend over the last 6 months", "chart_type": "line"}';

comment on view hostel.complaints_category_bar is '{"type": "chart", "name": "Complaints by Category", "description": "Complaint volume grouped by category", "chart_type": "bar"}';

comment on view hostel.occupancy_metrics_radar is '{"type": "chart", "name": "Occupancy Metrics", "description": "Capacity vs occupied beds per hostel", "chart_type": "radar"}';

----------------------------------------------------------------
-- Audit triggers
----------------------------------------------------------------
create trigger audit_hostel_hostels_insert
after insert on hostel.hostels for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_hostels_update
after update on hostel.hostels for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_hostels_delete
before delete on hostel.hostels for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_rooms_insert
after insert on hostel.rooms for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_rooms_update
after update on hostel.rooms for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_rooms_delete
before delete on hostel.rooms for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_residents_insert
after insert on hostel.residents for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_residents_update
after update on hostel.residents for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_residents_delete
before delete on hostel.residents for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_allocations_insert
after insert on hostel.allocations for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_allocations_update
after update on hostel.allocations for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_allocations_delete
before delete on hostel.allocations for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_payments_insert
after insert on hostel.payments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_payments_update
after update on hostel.payments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_payments_delete
before delete on hostel.payments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_complaints_insert
after insert on hostel.complaints for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_complaints_update
after update on hostel.complaints for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_complaints_delete
before delete on hostel.complaints for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_visitors_insert
after insert on hostel.visitors for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_visitors_update
after update on hostel.visitors for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_hostel_visitors_delete
before delete on hostel.visitors for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Room occupancy maintenance
-- Keep rooms.occupied in sync as allocations move between active/inactive states.
----------------------------------------------------------------
create or replace function hostel.trg_allocation_sync_room () returns trigger as $$
declare
    v_new_active boolean;
    v_old_active boolean;
begin
    v_new_active := (tg_op in ('INSERT', 'UPDATE')) and new.status = 'active';
    v_old_active := (tg_op in ('UPDATE', 'DELETE')) and old.status = 'active';

    if tg_op = 'INSERT' and v_new_active then
        update hostel.rooms
           set occupied = occupied + 1,
               status = case
                   when occupied + 1 >= capacity then 'occupied'::hostel.room_status
                   else status
               end
         where id = new.room_id;
    elsif tg_op = 'DELETE' and v_old_active then
        update hostel.rooms
           set occupied = greatest(occupied - 1, 0),
               status = case
                   when status = 'occupied' and (occupied - 1) < capacity then 'available'::hostel.room_status
                   else status
               end
         where id = old.room_id;
    elsif tg_op = 'UPDATE' then
        if v_old_active and not v_new_active then
            update hostel.rooms
               set occupied = greatest(occupied - 1, 0),
                   status = case
                       when status = 'occupied' and (occupied - 1) < capacity then 'available'::hostel.room_status
                       else status
                   end
             where id = old.room_id;
        elsif not v_old_active and v_new_active then
            update hostel.rooms
               set occupied = occupied + 1,
                   status = case
                       when occupied + 1 >= capacity then 'occupied'::hostel.room_status
                       else status
                   end
             where id = new.room_id;
        elsif v_old_active and v_new_active and old.room_id is distinct from new.room_id then
            update hostel.rooms
               set occupied = greatest(occupied - 1, 0),
                   status = case
                       when status = 'occupied' and (occupied - 1) < capacity then 'available'::hostel.room_status
                       else status
                   end
             where id = old.room_id;
            update hostel.rooms
               set occupied = occupied + 1,
                   status = case
                       when occupied + 1 >= capacity then 'occupied'::hostel.room_status
                       else status
                   end
             where id = new.room_id;
        end if;
    end if;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists allocations_sync_room on hostel.allocations;

create trigger allocations_sync_room
after insert or update or delete on hostel.allocations for each row
execute function hostel.trg_allocation_sync_room ();

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
-- Allocation trigger:
--   * INSERT  → notify the resident + everyone who can manage allocations
--   * status updates → notify the resident
create or replace function hostel.trg_allocations_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_resident   hostel.residents%rowtype;
    v_type       text;
    v_title      text;
    v_body       text;
    v_ref        text;
begin
    select * into v_resident from hostel.residents where id = new.resident_id;
    v_ref := coalesce(new.allocation_no, new.id::text);

    if tg_op = 'INSERT' then
        v_type  := 'allocation_created';
        v_title := 'New room allocation';
        v_body  := 'Allocation ' || v_ref || ' was created for ' || coalesce(v_resident.name, 'a resident') || '.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('hostel', 'allocations', 'select') || array[v_resident.user_id],
            null
        );
    elsif new.status is distinct from old.status then
        v_type  := 'allocation_status_changed';
        v_title := 'Allocation status updated';
        v_body  := 'Allocation ' || v_ref || ' is now ' || new.status::text || '.';
        v_recipients := array_remove(array[v_resident.user_id], null);
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'allocation_id', new.id,
            'allocation_no', new.allocation_no,
            'status',        new.status,
            'resident_id',   new.resident_id,
            'room_id',       new.room_id
        ),
        '/hostel/resource/allocations/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists allocations_notify on hostel.allocations;

create trigger allocations_notify
after insert or update of status on hostel.allocations for each row
execute function hostel.trg_allocations_notify ();

-- Payment trigger:
--   * INSERT (status pending/overdue) → notify the resident
--   * status update to overdue → notify the resident + payments managers
--   * status update to paid → notify the resident
create or replace function hostel.trg_payments_notify () returns trigger as $$
declare
    v_resident   hostel.residents%rowtype;
    v_recipients uuid[];
    v_type       text;
    v_title      text;
    v_body       text;
    v_ref        text;
begin
    select * into v_resident from hostel.residents where id = new.resident_id;
    v_ref := coalesce(new.receipt_no, new.id::text);

    if tg_op = 'INSERT' then
        v_type  := 'payment_created';
        v_title := 'Payment due';
        v_body  := 'Payment ' || v_ref || ' of ' || new.total::text || ' is due on ' || new.due_date::text || '.';
        v_recipients := array_remove(array[v_resident.user_id], null);
    elsif new.status is distinct from old.status and new.status = 'overdue' then
        v_type  := 'payment_overdue';
        v_title := 'Payment overdue';
        v_body  := 'Payment ' || v_ref || ' is now overdue.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('hostel', 'payments', 'update') || array[v_resident.user_id],
            null
        );
    elsif new.status is distinct from old.status and new.status = 'paid' then
        v_type  := 'payment_paid';
        v_title := 'Payment received';
        v_body  := 'Payment ' || v_ref || ' has been marked as paid.';
        v_recipients := array_remove(array[v_resident.user_id], null);
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'payment_id',   new.id,
            'receipt_no',   new.receipt_no,
            'amount',       new.total,
            'status',       new.status,
            'due_date',     new.due_date,
            'resident_id',  new.resident_id
        ),
        '/hostel/resource/payments/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists payments_notify on hostel.payments;

create trigger payments_notify
after insert or update of status on hostel.payments for each row
execute function hostel.trg_payments_notify ();

-- Complaint trigger:
--   * INSERT → notify complaint managers
--   * status / assignment updates → notify resident + assignee
create or replace function hostel.trg_complaints_notify () returns trigger as $$
declare
    v_resident   hostel.residents%rowtype;
    v_recipients uuid[];
    v_type       text;
    v_title      text;
    v_body       text;
    v_ref        text;
begin
    if new.resident_id is not null then
        select * into v_resident from hostel.residents where id = new.resident_id;
    end if;
    v_ref := coalesce(new.ticket_no, new.id::text);

    if tg_op = 'INSERT' then
        v_type  := 'complaint_submitted';
        v_title := 'New complaint submitted';
        v_body  := 'Ticket ' || v_ref || ' (' || new.priority::text || '): ' || new.title;
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('hostel', 'complaints', 'update'),
            null
        );
    elsif new.status is distinct from old.status then
        v_type  := 'complaint_status_changed';
        v_title := 'Complaint status updated';
        v_body  := 'Ticket ' || v_ref || ' is now ' || new.status::text || '.';
        v_recipients := array_remove(
            array[v_resident.user_id, new.assigned_to],
            null
        );
    elsif new.assigned_to is distinct from old.assigned_to and new.assigned_to is not null then
        v_type  := 'complaint_assigned';
        v_title := 'Complaint assigned';
        v_body  := 'Ticket ' || v_ref || ' has been assigned to you.';
        v_recipients := array_remove(array[new.assigned_to], null);
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'complaint_id', new.id,
            'ticket_no',    new.ticket_no,
            'category',     new.category,
            'priority',     new.priority,
            'status',       new.status
        ),
        '/hostel/resource/complaints/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists complaints_notify on hostel.complaints;

create trigger complaints_notify
after insert or update of status,
assigned_to on hostel.complaints for each row
execute function hostel.trg_complaints_notify ();

----------------------------------------------------------------
-- Template: Monthly Payments
-- Apply to hostel.payments to seed pending payment entries for
-- all currently active allocations at the start of each billing
-- month. Columns are a subset of hostel.payments — id,
-- receipt_no, paid_date, method, reference, and notes are
-- intentionally omitted (auto-generated or optional).
----------------------------------------------------------------
create or replace view hostel.monthly_payment_template
with
  (security_invoker = true) as
select
  a.id as allocation_id,
  a.resident_id,
  date_trunc('month', current_date)::date as period_month,
  a.monthly_rent as amount,
  0::numeric(10, 2) as late_fee,
  a.monthly_rent as total,
  (
    date_trunc('month', current_date) + interval '10 days'
  )::date as due_date,
  'pending'::hostel.payment_status as status
from
  hostel.allocations a
where
  a.status = 'active';

revoke all on hostel.monthly_payment_template
from
  authenticated,
  service_role;

grant
select
  on hostel.monthly_payment_template to "x-admin";

comment on view hostel.monthly_payment_template is '{"type": "template", "name": "Monthly Payment Template", "description": "Pending payment entries for all active allocations. Apply to hostel.payments to seed a new billing month.", "target_table": "payments"}';
