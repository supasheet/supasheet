create schema if not exists lms;

grant usage on schema lms to authenticated;

----------------------------------------------------------------
-- Enums + permissions (must commit before use)
----------------------------------------------------------------
begin;

create type lms.course_status as enum('draft', 'published', 'coming_soon', 'archived');

create type lms.course_difficulty as enum('beginner', 'intermediate', 'advanced', 'expert');

create type lms.module_status as enum('draft', 'published', 'hidden');

create type lms.lesson_type as enum(
  'video',
  'article',
  'quiz',
  'assignment',
  'live_session',
  'reading',
  'download'
);

create type lms.lesson_status as enum('draft', 'published', 'hidden');

create type lms.enrollment_status as enum(
  'active',
  'completed',
  'paused',
  'dropped',
  'expired'
);

create type lms.progress_status as enum(
  'not_started',
  'in_progress',
  'completed',
  'skipped'
);

create type lms.assignment_type as enum(
  'quiz',
  'essay',
  'project',
  'peer_review',
  'practical'
);

create type lms.submission_status as enum(
  'draft',
  'submitted',
  'graded',
  'returned',
  'late'
);

create type lms.certificate_status as enum('issued', 'revoked', 'expired');

create type lms.path_status as enum('draft', 'published', 'archived');

commit;

----------------------------------------------------------------
-- Users mirror view
----------------------------------------------------------------
create or replace view lms.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on lms.users
from
  authenticated,
  service_role;

grant
select
  on lms.users to "x-admin";

----------------------------------------------------------------
-- Courses
----------------------------------------------------------------
create table lms.courses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(50) unique not null,
  title varchar(500) not null,
  subtitle varchar(500),
  status lms.course_status default 'draft',
  difficulty lms.course_difficulty default 'beginner',
  category varchar(255),
  description supasheet.RICH_TEXT,
  learning_objectives text,
  prerequisites text,
  cover supasheet.file,
  promo_video supasheet.URL,
  instructor_user_id uuid references supasheet.users (id) on delete set null,
  co_instructor_name varchar(255),
  duration_minutes integer,
  language varchar(50) default 'en',
  price numeric(10, 2) default 0,
  currency varchar(3) default 'USD',
  is_free boolean default true,
  rating supasheet.RATING,
  enrollment_count integer default 0,
  completion_count integer default 0,
  published_at timestamptz,
  archived_at timestamptz,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column lms.courses.status is '{
    "progress": true,
    "values": {
        "draft":       {"variant": "outline",     "icon": "FileEdit"},
        "published":   {"variant": "success",     "icon": "CircleCheck"},
        "coming_soon": {"variant": "info",        "icon": "Clock"},
        "archived":    {"variant": "destructive", "icon": "Archive"}
    }
}';

comment on column lms.courses.difficulty is '{
    "progress": true,
    "values": {
        "beginner":     {"variant": "success",     "icon": "Sprout"},
        "intermediate": {"variant": "info",        "icon": "TreePine"},
        "advanced":     {"variant": "warning",     "icon": "Trees"},
        "expert":       {"variant": "destructive", "icon": "Mountain"}
    }
}';

comment on table lms.courses is '{
    "icon": "BookOpen",
    "display": "block",
    "primary_view": "gallery",
    "views": [
        {
            "id": "gallery",
            "name": "Course Catalog",
            "type": "gallery",
            "cover": "cover",
            "title": "title",
            "description": "subtitle",
            "badge": "difficulty"
        },
        {
            "id": "kanban",
            "name": "Courses By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "category",
            "date": "published_at",
            "badge": "difficulty"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "code",
                    "title",
                    "subtitle",
                    "status",
                    "difficulty",
                    "category",
                    "cover",
                    "promo_video"
                ]
            },
            {
                "id": "content",
                "title": "Content",
                "fields": [
                    "description",
                    "learning_objectives",
                    "prerequisites",
                    "duration_minutes",
                    "language"
                ]
            },
            {
                "id": "instructor",
                "title": "Instructor",
                "fields": [
                    "instructor_user_id",
                    "co_instructor_name"
                ]
            },
            {
                "id": "pricing",
                "title": "Pricing",
                "fields": [
                    "price",
                    "currency",
                    "is_free"
                ]
            },
            {
                "id": "metrics",
                "title": "Metrics",
                "fields": [
                    "rating",
                    "enrollment_count",
                    "completion_count",
                    "published_at",
                    "archived_at"
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
                "id": "title",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "users",
                "on": "instructor_user_id",
                "alias": "instructor_user",
                "columns": [
                    "name",
                    "email"
                ]
            },
            {
                "table": "users",
                "on": "user_id",
                "alias": "user",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column lms.courses.cover is '{"accept":"image/*"}';

revoke all on table lms.courses
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table lms.courses to "x-admin";

create index idx_lms_courses_user_id on lms.courses (user_id);

create index idx_lms_courses_instructor on lms.courses (instructor_user_id);

create index idx_lms_courses_status on lms.courses (status);

create index idx_lms_courses_difficulty on lms.courses (difficulty);

create index idx_lms_courses_category on lms.courses (category);

create index idx_lms_courses_published_at on lms.courses (published_at desc);

alter table lms.courses enable row level security;

create policy courses_select on lms.courses for
select
  to authenticated using (true);

create policy courses_insert on lms.courses for insert to authenticated
with
  check (true);

create policy courses_update on lms.courses
for update
  to authenticated using (true)
with
  check (true);

create policy courses_delete on lms.courses for delete to authenticated using (true);

----------------------------------------------------------------
-- Modules (course sections)
----------------------------------------------------------------
create table lms.modules (
  id uuid primary key default extensions.uuid_generate_v4 (),
  course_id uuid not null references lms.courses (id) on delete cascade,
  sequence_number integer default 0,
  title varchar(500) not null,
  description supasheet.RICH_TEXT,
  status lms.module_status default 'draft',
  duration_minutes integer,
  cover supasheet.file,
  tags varchar(255) [],
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column lms.modules.status is '{
    "progress": true,
    "values": {
        "draft":     {"variant": "outline", "icon": "FileEdit"},
        "published": {"variant": "success", "icon": "CircleCheck"},
        "hidden":    {"variant": "secondary","icon": "EyeOff"}
    }
}';

comment on table lms.modules is '{
    "icon": "Layers",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Modules By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "description",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "course_id",
                    "sequence_number"
                ]
            },
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "title",
                    "status",
                    "description",
                    "duration_minutes"
                ]
            },
            {
                "id": "extras",
                "title": "Tags, Cover & Notes",
                "collapsible": true,
                "fields": [
                    "cover",
                    "tags",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "sequence_number",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "courses",
                "on": "course_id",
                "columns": [
                    "code",
                    "title"
                ]
            }
        ]
    }
}';

comment on column lms.modules.cover is '{"accept":"image/*"}';

revoke all on table lms.modules
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table lms.modules to "x-admin";

create index idx_lms_modules_course_id on lms.modules (course_id);

create index idx_lms_modules_status on lms.modules (status);

alter table lms.modules enable row level security;

create policy modules_select on lms.modules for
select
  to authenticated using (true);

create policy modules_insert on lms.modules for insert to authenticated
with
  check (true);

create policy modules_update on lms.modules
for update
  to authenticated using (true)
with
  check (true);

create policy modules_delete on lms.modules for delete to authenticated using (true);

----------------------------------------------------------------
-- Lessons (content items)
----------------------------------------------------------------
create table lms.lessons (
  id uuid primary key default extensions.uuid_generate_v4 (),
  module_id uuid not null references lms.modules (id) on delete cascade,
  sequence_number integer default 0,
  title varchar(500) not null,
  type lms.lesson_type default 'video',
  status lms.lesson_status default 'draft',
  description supasheet.RICH_TEXT,
  body supasheet.RICH_TEXT,
  video_url supasheet.URL,
  video_duration_seconds integer,
  attachments supasheet.file,
  download supasheet.file,
  is_preview boolean default false,
  is_required boolean default true,
  estimated_minutes integer,
  tags varchar(255) [],
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column lms.lessons.type is '{
    "progress": false,
    "values": {
        "video":        {"variant": "info",      "icon": "Play"},
        "article":      {"variant": "secondary", "icon": "FileText"},
        "quiz":         {"variant": "warning",   "icon": "ListChecks"},
        "assignment":   {"variant": "warning",   "icon": "ClipboardList"},
        "live_session": {"variant": "success",   "icon": "Video"},
        "reading":      {"variant": "info",      "icon": "BookOpen"},
        "download":     {"variant": "outline",   "icon": "Download"}
    }
}';

comment on column lms.lessons.status is '{
    "progress": true,
    "values": {
        "draft":     {"variant": "outline",  "icon": "FileEdit"},
        "published": {"variant": "success",  "icon": "CircleCheck"},
        "hidden":    {"variant": "secondary","icon": "EyeOff"}
    }
}';

comment on table lms.lessons is '{
    "icon": "Play",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Lessons By Type",
            "type": "kanban",
            "group": "type",
            "title": "title",
            "description": "description",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "module_id",
                    "sequence_number"
                ]
            },
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "title",
                    "type",
                    "status",
                    "description"
                ]
            },
            {
                "id": "content",
                "title": "Content",
                "fields": [
                    "body",
                    "video_url",
                    "video_duration_seconds",
                    "attachments",
                    "download"
                ]
            },
            {
                "id": "settings",
                "title": "Settings",
                "fields": [
                    "is_preview",
                    "is_required",
                    "estimated_minutes"
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
                "id": "sequence_number",
                "desc": false
            }
        ],
        "join": [
            {
                "table": "modules",
                "on": "module_id",
                "columns": [
                    "title",
                    "sequence_number"
                ]
            }
        ]
    }
}';

comment on column lms.lessons.attachments is '{"accept":"*", "max_files": 10}';

comment on column lms.lessons.download is '{"accept":"*", "max_files": 5}';

revoke all on table lms.lessons
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table lms.lessons to "x-admin";

create index idx_lms_lessons_module_id on lms.lessons (module_id);

create index idx_lms_lessons_type on lms.lessons (type);

create index idx_lms_lessons_status on lms.lessons (status);

alter table lms.lessons enable row level security;

create policy lessons_select on lms.lessons for
select
  to authenticated using (true);

create policy lessons_insert on lms.lessons for insert to authenticated
with
  check (true);

create policy lessons_update on lms.lessons
for update
  to authenticated using (true)
with
  check (true);

create policy lessons_delete on lms.lessons for delete to authenticated using (true);

----------------------------------------------------------------
-- Enrollments
----------------------------------------------------------------
create table lms.enrollments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  course_id uuid not null references lms.courses (id) on delete cascade,
  learner_user_id uuid not null references supasheet.users (id) on delete cascade,
  learner_name varchar(500),
  learner_email supasheet.EMAIL,
  status lms.enrollment_status default 'active',
  enrolled_at timestamptz default current_timestamp,
  started_at timestamptz,
  completed_at timestamptz,
  expires_at timestamptz,
  progress_pct numeric(5, 2) default 0,
  last_accessed_at timestamptz,
  time_spent_minutes integer default 0,
  final_score supasheet.PERCENTAGE,
  issued_certificate_id uuid,
  learning_path_id uuid,
  notes text,
  tags varchar(255) [],
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (course_id, learner_user_id)
);

comment on column lms.enrollments.status is '{
    "progress": true,
    "values": {
        "active":    {"variant": "info",        "icon": "Play"},
        "completed": {"variant": "success",     "icon": "CircleCheck"},
        "paused":    {"variant": "warning",     "icon": "PauseCircle"},
        "dropped":   {"variant": "destructive", "icon": "XCircle"},
        "expired":   {"variant": "outline",     "icon": "Clock"}
    }
}';

comment on table lms.enrollments is '{
    "icon": "GraduationCap",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Enrollments By Status",
            "type": "kanban",
            "group": "status",
            "title": "learner_name",
            "description": "learner_email",
            "date": "enrolled_at",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Enrollment Calendar",
            "type": "calendar",
            "title": "learner_name",
            "badge": "status",
            "start_date": "enrolled_at",
            "end_date": "completed_at"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "course_id",
                    "learner_user_id",
                    "learner_name",
                    "learner_email",
                    "learning_path_id"
                ]
            },
            {
                "id": "status",
                "title": "Status",
                "fields": [
                    "status",
                    "enrolled_at",
                    "started_at",
                    "completed_at",
                    "expires_at"
                ]
            },
            {
                "id": "progress",
                "title": "Progress",
                "fields": [
                    "progress_pct",
                    "last_accessed_at",
                    "time_spent_minutes",
                    "final_score",
                    "issued_certificate_id"
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
                "id": "enrolled_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "courses",
                "on": "course_id",
                "columns": [
                    "code",
                    "title"
                ]
            },
            {
                "table": "users",
                "on": "learner_user_id",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

revoke all on table lms.enrollments
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table lms.enrollments to "x-admin";

create index idx_lms_enrollments_user_id on lms.enrollments (user_id);

create index idx_lms_enrollments_course_id on lms.enrollments (course_id);

create index idx_lms_enrollments_learner on lms.enrollments (learner_user_id);

create index idx_lms_enrollments_status on lms.enrollments (status);

create index idx_lms_enrollments_enrolled_at on lms.enrollments (enrolled_at desc);

create index idx_lms_enrollments_learning_path_id on lms.enrollments (learning_path_id);

alter table lms.enrollments enable row level security;

create policy enrollments_select on lms.enrollments for
select
  to authenticated using (true);

create policy enrollments_insert on lms.enrollments for insert to authenticated
with
  check (true);

create policy enrollments_update on lms.enrollments
for update
  to authenticated using (true)
with
  check (true);

create policy enrollments_delete on lms.enrollments for delete to authenticated using (true);

----------------------------------------------------------------
-- Lesson progress (per-lesson tracking)
----------------------------------------------------------------
create table lms.lesson_progress (
  id uuid primary key default extensions.uuid_generate_v4 (),
  enrollment_id uuid not null references lms.enrollments (id) on delete cascade,
  lesson_id uuid not null references lms.lessons (id) on delete cascade,
  status lms.progress_status default 'not_started',
  started_at timestamptz,
  completed_at timestamptz,
  last_position_seconds integer default 0,
  time_spent_seconds integer default 0,
  score supasheet.PERCENTAGE,
  attempts integer default 0,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (enrollment_id, lesson_id)
);

comment on column lms.lesson_progress.status is '{
    "progress": true,
    "values": {
        "not_started": {"variant": "outline",   "icon": "Circle"},
        "in_progress": {"variant": "warning",   "icon": "Loader"},
        "completed":   {"variant": "success",   "icon": "CircleCheck"},
        "skipped":     {"variant": "secondary", "icon": "SkipForward"}
    }
}';

comment on table lms.lesson_progress is '{
    "icon": "TrendingUp",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Progress By Status",
            "type": "kanban",
            "group": "status",
            "title": "notes",
            "description": "notes",
            "date": "started_at",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "enrollment_id",
                    "lesson_id"
                ]
            },
            {
                "id": "status",
                "title": "Status",
                "fields": [
                    "status",
                    "started_at",
                    "completed_at"
                ]
            },
            {
                "id": "playback",
                "title": "Playback",
                "fields": [
                    "last_position_seconds",
                    "time_spent_seconds",
                    "score",
                    "attempts"
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
                "id": "updated_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "enrollments",
                "on": "enrollment_id",
                "columns": [
                    "learner_name",
                    "status"
                ]
            },
            {
                "table": "lessons",
                "on": "lesson_id",
                "columns": [
                    "title",
                    "type"
                ]
            }
        ]
    }
}';

revoke all on table lms.lesson_progress
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table lms.lesson_progress to "x-admin";

create index idx_lms_lesson_progress_enrollment_id on lms.lesson_progress (enrollment_id);

create index idx_lms_lesson_progress_lesson_id on lms.lesson_progress (lesson_id);

create index idx_lms_lesson_progress_status on lms.lesson_progress (status);

alter table lms.lesson_progress enable row level security;

create policy lesson_progress_select on lms.lesson_progress for
select
  to authenticated using (true);

create policy lesson_progress_insert on lms.lesson_progress for insert to authenticated
with
  check (true);

create policy lesson_progress_update on lms.lesson_progress
for update
  to authenticated using (true)
with
  check (true);

create policy lesson_progress_delete on lms.lesson_progress for delete to authenticated using (true);

----------------------------------------------------------------
-- Assignments
----------------------------------------------------------------
create table lms.assignments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  course_id uuid not null references lms.courses (id) on delete cascade,
  lesson_id uuid references lms.lessons (id) on delete set null,
  title varchar(500) not null,
  type lms.assignment_type default 'quiz',
  description supasheet.RICH_TEXT,
  instructions text,
  max_score integer default 100,
  passing_score integer default 70,
  time_limit_minutes integer,
  attempts_allowed integer default 1,
  open_at timestamptz,
  due_at timestamptz,
  rubric text,
  attachments supasheet.file,
  is_published boolean default false,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column lms.assignments.type is '{
    "progress": false,
    "values": {
        "quiz":        {"variant": "info",      "icon": "ListChecks"},
        "essay":       {"variant": "warning",   "icon": "FileText"},
        "project":     {"variant": "warning",   "icon": "Hammer"},
        "peer_review": {"variant": "secondary", "icon": "Users"},
        "practical":   {"variant": "success",   "icon": "Wrench"}
    }
}';

comment on table lms.assignments is '{
    "icon": "ClipboardList",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Assignments By Type",
            "type": "kanban",
            "group": "type",
            "title": "title",
            "description": "description",
            "date": "due_at",
            "badge": "type"
        },
        {
            "id": "calendar",
            "name": "Assignment Calendar",
            "type": "calendar",
            "title": "title",
            "badge": "type",
            "start_date": "open_at",
            "end_date": "due_at"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "course_id",
                    "lesson_id"
                ]
            },
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "title",
                    "type",
                    "description",
                    "instructions"
                ]
            },
            {
                "id": "grading",
                "title": "Grading",
                "fields": [
                    "max_score",
                    "passing_score",
                    "attempts_allowed",
                    "rubric"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "time_limit_minutes",
                    "open_at",
                    "due_at"
                ]
            },
            {
                "id": "publishing",
                "title": "Publishing",
                "fields": [
                    "is_published",
                    "tags",
                    "color"
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
                "id": "due_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "courses",
                "on": "course_id",
                "columns": [
                    "code",
                    "title"
                ]
            },
            {
                "table": "lessons",
                "on": "lesson_id",
                "columns": [
                    "title",
                    "type"
                ]
            }
        ]
    }
}';

comment on column lms.assignments.attachments is '{"accept":"*", "max_files": 10}';

revoke all on table lms.assignments
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table lms.assignments to "x-admin";

create index idx_lms_assignments_user_id on lms.assignments (user_id);

create index idx_lms_assignments_course_id on lms.assignments (course_id);

create index idx_lms_assignments_lesson_id on lms.assignments (lesson_id);

create index idx_lms_assignments_type on lms.assignments (type);

create index idx_lms_assignments_due_at on lms.assignments (due_at desc);

alter table lms.assignments enable row level security;

create policy assignments_select on lms.assignments for
select
  to authenticated using (true);

create policy assignments_insert on lms.assignments for insert to authenticated
with
  check (true);

create policy assignments_update on lms.assignments
for update
  to authenticated using (true)
with
  check (true);

create policy assignments_delete on lms.assignments for delete to authenticated using (true);

----------------------------------------------------------------
-- Submissions
----------------------------------------------------------------
create table lms.submissions (
  id uuid primary key default extensions.uuid_generate_v4 (),
  submission_number varchar(50) unique not null,
  assignment_id uuid not null references lms.assignments (id) on delete cascade,
  enrollment_id uuid references lms.enrollments (id) on delete set null,
  learner_user_id uuid references supasheet.users (id) on delete set null,
  learner_name varchar(500),
  status lms.submission_status default 'draft',
  submitted_at timestamptz,
  graded_at timestamptz,
  returned_at timestamptz,
  attempt_number integer default 1,
  score numeric(6, 2),
  max_score integer default 100,
  is_passing boolean,
  response_text text,
  attachments supasheet.file,
  grader_user_id uuid references supasheet.users (id) on delete set null,
  feedback text,
  rubric_scores jsonb,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column lms.submissions.status is '{
    "progress": true,
    "values": {
        "draft":     {"variant": "outline",     "icon": "FileEdit"},
        "submitted": {"variant": "info",        "icon": "Send"},
        "graded":    {"variant": "success",     "icon": "BadgeCheck"},
        "returned":  {"variant": "warning",     "icon": "Undo2"},
        "late":      {"variant": "destructive", "icon": "AlertTriangle"}
    }
}';

comment on table lms.submissions is '{
    "icon": "FileCheck",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Submissions By Status",
            "type": "kanban",
            "group": "status",
            "title": "submission_number",
            "description": "learner_name",
            "date": "submitted_at",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "submission_number",
                    "assignment_id",
                    "enrollment_id",
                    "status"
                ]
            },
            {
                "id": "learner",
                "title": "Learner",
                "fields": [
                    "learner_user_id",
                    "learner_name"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "submitted_at",
                    "graded_at",
                    "returned_at",
                    "attempt_number"
                ]
            },
            {
                "id": "grading",
                "title": "Grading",
                "fields": [
                    "score",
                    "max_score",
                    "is_passing",
                    "grader_user_id",
                    "rubric_scores",
                    "feedback"
                ]
            },
            {
                "id": "response",
                "title": "Response",
                "fields": [
                    "response_text",
                    "attachments"
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
                "id": "submitted_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "assignments",
                "on": "assignment_id",
                "columns": [
                    "title",
                    "type"
                ]
            },
            {
                "table": "enrollments",
                "on": "enrollment_id",
                "columns": [
                    "learner_name",
                    "status"
                ]
            },
            {
                "table": "users",
                "on": "learner_user_id",
                "alias": "learner_user",
                "columns": [
                    "name",
                    "email"
                ]
            },
            {
                "table": "users",
                "on": "grader_user_id",
                "alias": "grader_user",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column lms.submissions.attachments is '{"accept":"*", "max_files": 10}';

revoke all on table lms.submissions
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table lms.submissions to "x-admin";

create index idx_lms_submissions_user_id on lms.submissions (user_id);

create index idx_lms_submissions_assignment_id on lms.submissions (assignment_id);

create index idx_lms_submissions_enrollment_id on lms.submissions (enrollment_id);

create index idx_lms_submissions_learner on lms.submissions (learner_user_id);

create index idx_lms_submissions_grader on lms.submissions (grader_user_id);

create index idx_lms_submissions_status on lms.submissions (status);

create index idx_lms_submissions_submitted_at on lms.submissions (submitted_at desc);

alter table lms.submissions enable row level security;

create policy submissions_select on lms.submissions for
select
  to authenticated using (true);

create policy submissions_insert on lms.submissions for insert to authenticated
with
  check (true);

create policy submissions_update on lms.submissions
for update
  to authenticated using (true)
with
  check (true);

create policy submissions_delete on lms.submissions for delete to authenticated using (true);

----------------------------------------------------------------
-- Certificates
----------------------------------------------------------------
create table lms.certificates (
  id uuid primary key default extensions.uuid_generate_v4 (),
  certificate_number varchar(100) unique not null,
  course_id uuid references lms.courses (id) on delete set null,
  enrollment_id uuid references lms.enrollments (id) on delete set null,
  learning_path_id uuid,
  learner_user_id uuid not null references supasheet.users (id) on delete cascade,
  learner_name varchar(500),
  title varchar(500) not null,
  description supasheet.RICH_TEXT,
  status lms.certificate_status default 'issued',
  issued_at timestamptz default current_timestamp,
  expires_at timestamptz,
  revoked_at timestamptz,
  revocation_reason text,
  final_score supasheet.PERCENTAGE,
  grade varchar(10),
  document supasheet.file,
  verification_url supasheet.URL,
  issuer_user_id uuid references supasheet.users (id) on delete set null,
  issuer_organization varchar(500),
  tags varchar(255) [],
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column lms.certificates.status is '{
    "progress": true,
    "values": {
        "issued":  {"variant": "success",     "icon": "BadgeCheck"},
        "revoked": {"variant": "destructive", "icon": "XCircle"},
        "expired": {"variant": "outline",     "icon": "Clock"}
    }
}';

comment on table lms.certificates is '{
    "icon": "Award",
    "display": "block",
    "primary_view": "kanban",
    "views": [
        {
            "id": "kanban",
            "name": "Certificates By Status",
            "type": "kanban",
            "group": "status",
            "title": "learner_name",
            "description": "title",
            "date": "issued_at",
            "badge": "status"
        },
        {
            "id": "calendar",
            "name": "Certificate Calendar",
            "type": "calendar",
            "title": "learner_name",
            "badge": "status",
            "start_date": "issued_at",
            "end_date": "expires_at"
        },
        {
            "id": "gallery",
            "name": "Certificate Wall",
            "type": "gallery",
            "cover": "document",
            "title": "learner_name",
            "description": "title",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "certificate_number",
                    "title",
                    "status",
                    "description"
                ]
            },
            {
                "id": "link",
                "title": "Link",
                "fields": [
                    "course_id",
                    "enrollment_id",
                    "learning_path_id",
                    "learner_user_id",
                    "learner_name"
                ]
            },
            {
                "id": "timing",
                "title": "Timing",
                "fields": [
                    "issued_at",
                    "expires_at",
                    "revoked_at",
                    "revocation_reason"
                ]
            },
            {
                "id": "grade",
                "title": "Grade",
                "fields": [
                    "final_score",
                    "grade"
                ]
            },
            {
                "id": "issuer",
                "title": "Issuer",
                "fields": [
                    "issuer_user_id",
                    "issuer_organization",
                    "verification_url"
                ]
            },
            {
                "id": "extras",
                "title": "Document, Tags & Notes",
                "collapsible": true,
                "fields": [
                    "document",
                    "tags",
                    "notes"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "issued_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "courses",
                "on": "course_id",
                "columns": [
                    "code",
                    "title"
                ]
            },
            {
                "table": "users",
                "on": "learner_user_id",
                "alias": "learner_user",
                "columns": [
                    "name",
                    "email"
                ]
            },
            {
                "table": "users",
                "on": "issuer_user_id",
                "alias": "issuer_user",
                "columns": [
                    "name",
                    "email"
                ]
            }
        ]
    }
}';

comment on column lms.certificates.document is '{"accept":"application/pdf,image/*", "max_files": 1}';

revoke all on table lms.certificates
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table lms.certificates to "x-admin";

create index idx_lms_certificates_user_id on lms.certificates (user_id);

create index idx_lms_certificates_course_id on lms.certificates (course_id);

create index idx_lms_certificates_enrollment_id on lms.certificates (enrollment_id);

create index idx_lms_certificates_learner on lms.certificates (learner_user_id);

create index idx_lms_certificates_issuer on lms.certificates (issuer_user_id);

create index idx_lms_certificates_status on lms.certificates (status);

create index idx_lms_certificates_issued_at on lms.certificates (issued_at desc);

alter table lms.certificates enable row level security;

create policy certificates_select on lms.certificates for
select
  to authenticated using (true);

create policy certificates_insert on lms.certificates for insert to authenticated
with
  check (true);

create policy certificates_update on lms.certificates
for update
  to authenticated using (true)
with
  check (true);

create policy certificates_delete on lms.certificates for delete to authenticated using (true);

----------------------------------------------------------------
-- Learning paths (curated multi-course sequences)
----------------------------------------------------------------
create table lms.learning_paths (
  id uuid primary key default extensions.uuid_generate_v4 (),
  code varchar(50) unique not null,
  title varchar(500) not null,
  subtitle varchar(500),
  status lms.path_status default 'draft',
  difficulty lms.course_difficulty default 'beginner',
  category varchar(255),
  description supasheet.RICH_TEXT,
  learning_objectives text,
  cover supasheet.file,
  -- Ordered list of course IDs (jsonb to keep flexibility)
  course_sequence jsonb,
  estimated_minutes integer,
  enrollment_count integer default 0,
  completion_count integer default 0,
  published_at timestamptz,
  archived_at timestamptz,
  tags varchar(255) [],
  color supasheet.COLOR,
  notes text,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column lms.learning_paths.status is '{
    "progress": true,
    "values": {
        "draft":     {"variant": "outline",     "icon": "FileEdit"},
        "published": {"variant": "success",     "icon": "CircleCheck"},
        "archived":  {"variant": "destructive", "icon": "Archive"}
    }
}';

comment on table lms.learning_paths is '{
    "icon": "Route",
    "display": "block",
    "primary_view": "gallery",
    "views": [
        {
            "id": "gallery",
            "name": "Learning Paths",
            "type": "gallery",
            "cover": "cover",
            "title": "title",
            "description": "subtitle",
            "badge": "difficulty"
        },
        {
            "id": "kanban",
            "name": "Paths By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "category",
            "badge": "difficulty"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "summary",
                "title": "Summary",
                "fields": [
                    "code",
                    "title",
                    "subtitle",
                    "status",
                    "difficulty",
                    "category",
                    "cover"
                ]
            },
            {
                "id": "content",
                "title": "Content",
                "fields": [
                    "description",
                    "learning_objectives",
                    "course_sequence",
                    "estimated_minutes"
                ]
            },
            {
                "id": "metrics",
                "title": "Metrics",
                "fields": [
                    "enrollment_count",
                    "completion_count",
                    "published_at",
                    "archived_at"
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
                "id": "title",
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

comment on column lms.learning_paths.cover is '{"accept":"image/*"}';

revoke all on table lms.learning_paths
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table lms.learning_paths to "x-admin";

create index idx_lms_paths_user_id on lms.learning_paths (user_id);

create index idx_lms_paths_status on lms.learning_paths (status);

create index idx_lms_paths_category on lms.learning_paths (category);

alter table lms.learning_paths enable row level security;

create policy learning_paths_select on lms.learning_paths for
select
  to authenticated using (true);

create policy learning_paths_insert on lms.learning_paths for insert to authenticated
with
  check (true);

create policy learning_paths_update on lms.learning_paths
for update
  to authenticated using (true)
with
  check (true);

create policy learning_paths_delete on lms.learning_paths for delete to authenticated using (true);

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view lms.courses_report
with
  (security_invoker = true) as
select
  c.id,
  c.code,
  c.title,
  c.status,
  c.difficulty,
  c.category,
  c.duration_minutes,
  u.name as instructor,
  count(distinct e.id) as enrollments,
  count(distinct e.id) filter (
    where
      e.status = 'completed'
  ) as completions,
  case
    when count(distinct e.id) > 0 then round(
      (
        count(distinct e.id) filter (
          where
            e.status = 'completed'
        )::numeric / count(distinct e.id)::numeric
      ) * 100,
      1
    )
    else 0
  end as completion_rate_pct,
  avg(e.final_score) as avg_score,
  c.rating,
  c.published_at,
  c.created_at
from
  lms.courses c
  left join supasheet.users u on u.id = c.instructor_user_id
  left join lms.enrollments e on e.course_id = c.id
group by
  c.id,
  u.name;

revoke all on lms.courses_report
from
  authenticated,
  service_role;

grant
select
  on lms.courses_report to "x-admin";

comment on view lms.courses_report is '{"type": "report", "name": "Courses Report", "description": "Courses with enrollment counts, completion rate, and avg score"}';

create or replace view lms.enrollments_report
with
  (security_invoker = true) as
select
  e.id,
  c.code as course_code,
  c.title as course_title,
  coalesce(e.learner_name, u.name) as learner,
  e.learner_email,
  e.status,
  e.progress_pct,
  e.time_spent_minutes,
  e.final_score,
  e.enrolled_at,
  e.started_at,
  e.completed_at,
  e.last_accessed_at,
  case
    when e.status = 'completed' then null
    when e.last_accessed_at is null then null
    else extract(
      day
      from
        (current_timestamp - e.last_accessed_at)
    )::int
  end as days_since_last_access,
  e.created_at
from
  lms.enrollments e
  left join lms.courses c on c.id = e.course_id
  left join supasheet.users u on u.id = e.learner_user_id;

revoke all on lms.enrollments_report
from
  authenticated,
  service_role;

grant
select
  on lms.enrollments_report to "x-admin";

comment on view lms.enrollments_report is '{"type": "report", "name": "Enrollments Report", "description": "Enrollments with progress and recency metrics"}';

create or replace view lms.learner_progress_report
with
  (security_invoker = true) as
select
  e.id as enrollment_id,
  coalesce(e.learner_name, u.name) as learner,
  e.learner_email,
  c.title as course,
  count(lp.id) as lessons_tracked,
  count(lp.id) filter (
    where
      lp.status = 'completed'
  ) as lessons_completed,
  count(lp.id) filter (
    where
      lp.status = 'in_progress'
  ) as lessons_in_progress,
  coalesce(sum(lp.time_spent_seconds) / 60, 0) as minutes_spent,
  avg(lp.score) filter (
    where
      lp.score is not null
  ) as avg_lesson_score,
  e.progress_pct,
  e.status as enrollment_status,
  e.last_accessed_at
from
  lms.enrollments e
  left join lms.courses c on c.id = e.course_id
  left join supasheet.users u on u.id = e.learner_user_id
  left join lms.lesson_progress lp on lp.enrollment_id = e.id
group by
  e.id,
  u.name,
  c.title;

revoke all on lms.learner_progress_report
from
  authenticated,
  service_role;

grant
select
  on lms.learner_progress_report to "x-admin";

comment on view lms.learner_progress_report is '{"type": "report", "name": "Learner Progress", "description": "Per-learner per-course progress with lesson rollups"}';

create or replace view lms.assignment_grades_report
with
  (security_invoker = true) as
select
  s.id,
  s.submission_number,
  a.title as assignment,
  a.type as assignment_type,
  c.title as course,
  coalesce(s.learner_name, u.name) as learner,
  s.status,
  s.attempt_number,
  s.score,
  s.max_score,
  case
    when s.max_score > 0 then round((s.score / s.max_score) * 100, 1)
    else null
  end as score_pct,
  s.is_passing,
  s.submitted_at,
  s.graded_at,
  g.name as grader,
  case
    when s.status = 'graded' then 0
    when s.submitted_at is null then null
    else extract(
      day
      from
        (current_timestamp - s.submitted_at)
    )::int
  end as days_pending_grading
from
  lms.submissions s
  left join lms.assignments a on a.id = s.assignment_id
  left join lms.courses c on c.id = a.course_id
  left join supasheet.users u on u.id = s.learner_user_id
  left join supasheet.users g on g.id = s.grader_user_id;

revoke all on lms.assignment_grades_report
from
  authenticated,
  service_role;

grant
select
  on lms.assignment_grades_report to "x-admin";

comment on view lms.assignment_grades_report is '{"type": "report", "name": "Assignment Grades", "description": "Submissions with scores and grading aging"}';

create or replace view lms.certificates_register
with
  (security_invoker = true) as
select
  cert.id,
  cert.certificate_number,
  cert.title,
  coalesce(cert.learner_name, u.name) as learner,
  c.title as course,
  cert.status,
  cert.issued_at,
  cert.expires_at,
  case
    when cert.expires_at is null then null
    else (cert.expires_at::date - current_date)::int
  end as days_to_expiry,
  cert.final_score,
  cert.grade,
  i.name as issuer,
  cert.issuer_organization,
  cert.created_at
from
  lms.certificates cert
  left join lms.courses c on c.id = cert.course_id
  left join supasheet.users u on u.id = cert.learner_user_id
  left join supasheet.users i on i.id = cert.issuer_user_id;

revoke all on lms.certificates_register
from
  authenticated,
  service_role;

grant
select
  on lms.certificates_register to "x-admin";

comment on view lms.certificates_register is '{"type": "report", "name": "Certificates Register", "description": "Issued certificates with expiry tracking"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: active enrollments count
create or replace view lms.active_enrollments
with
  (security_invoker = true) as
select
  count(*) as value,
  'graduation-cap' as icon,
  'active enrollments' as label
from
  lms.enrollments
where
  status = 'active';

revoke all on lms.active_enrollments
from
  authenticated,
  service_role;

grant
select
  on lms.active_enrollments to "x-admin";

-- card_2: completed vs in-progress
create or replace view lms.completion_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'completed'
  ) as primary,
  count(*) filter (
    where
      status = 'active'
  ) as secondary,
  'Completed' as primary_label,
  'In progress' as secondary_label
from
  lms.enrollments;

revoke all on lms.completion_split
from
  authenticated,
  service_role;

grant
select
  on lms.completion_split to "x-admin";

-- card_3: total minutes invested + completion rate %
create or replace view lms.completion_rate_summary
with
  (security_invoker = true) as
select
  coalesce(sum(time_spent_minutes), 0)::numeric(14, 2) as value,
  case
    when count(*) filter (
      where
        status in ('completed', 'dropped', 'expired')
    ) > 0 then round(
      (
        count(*) filter (
          where
            status = 'completed'
        )::numeric / count(*) filter (
          where
            status in ('completed', 'dropped', 'expired')
        )::numeric
      ) * 100,
      1
    )
    else 0
  end as percent
from
  lms.enrollments;

revoke all on lms.completion_rate_summary
from
  authenticated,
  service_role;

grant
select
  on lms.completion_rate_summary to "x-admin";

-- card_4: LMS health (overdue assignments, stale enrollments, expiring certs, late submissions)
create or replace view lms.lms_health
with
  (security_invoker = true) as
with
  metrics as (
    select
      (
        select
          count(*)
        from
          lms.assignments
        where
          is_published = true
          and due_at is not null
          and due_at < current_timestamp
      ) as overdue_assignments,
      (
        select
          count(*)
        from
          lms.enrollments
        where
          status = 'active'
          and (
            last_accessed_at is null
            or last_accessed_at < current_timestamp - interval '30 days'
          )
      ) as stale_enrollments,
      (
        select
          count(*)
        from
          lms.certificates
        where
          status = 'issued'
          and expires_at is not null
          and expires_at <= current_timestamp + interval '60 days'
          and expires_at >= current_timestamp
      ) as expiring_certs,
      (
        select
          count(*)
        from
          lms.submissions
        where
          status = 'late'
      ) as late_submissions,
      (
        select
          count(*)
        from
          lms.enrollments
        where
          status = 'active'
      ) as active_total
  )
select
  (
    overdue_assignments + stale_enrollments + expiring_certs + late_submissions
  ) as current,
  active_total as total,
  json_build_array(
    json_build_object(
      'label',
      'Overdue assignments',
      'value',
      overdue_assignments
    ),
    json_build_object(
      'label',
      'Stale enrollments',
      'value',
      stale_enrollments
    ),
    json_build_object(
      'label',
      'Expiring certs',
      'value',
      expiring_certs
    ),
    json_build_object(
      'label',
      'Late submissions',
      'value',
      late_submissions
    )
  ) as segments
from
  metrics;

revoke all on lms.lms_health
from
  authenticated,
  service_role;

grant
select
  on lms.lms_health to "x-admin";

-- table_1: recent enrollments
create or replace view lms.recent_enrollments
with
  (security_invoker = true) as
select
  coalesce(e.learner_name, '') as learner,
  coalesce(c.title, '') as course,
  coalesce(e.status::text, '') as status,
  to_char(e.enrolled_at, 'MM/DD') as date
from
  lms.enrollments e
  left join lms.courses c on c.id = e.course_id
order by
  e.enrolled_at desc
limit
  10;

revoke all on lms.recent_enrollments
from
  authenticated,
  service_role;

grant
select
  on lms.recent_enrollments to "x-admin";

-- table_2: top courses by enrollment
create or replace view lms.top_courses
with
  (security_invoker = true) as
select
  c.title as course,
  coalesce(c.category, '') as category,
  count(e.id) as enrollments,
  count(e.id) filter (
    where
      e.status = 'completed'
  )::bigint as completions
from
  lms.courses c
  left join lms.enrollments e on e.course_id = c.id
group by
  c.id,
  c.title,
  c.category
order by
  enrollments desc nulls last
limit
  10;

revoke all on lms.top_courses
from
  authenticated,
  service_role;

grant
select
  on lms.top_courses to "x-admin";

comment on view lms.active_enrollments is '{"type": "dashboard_widget", "name": "Active Enrollments", "description": "Count of currently active enrollments", "widget_type": "card_1"}';

comment on view lms.completion_split is '{"type": "dashboard_widget", "name": "Completed vs In Progress", "description": "Enrollment status split", "widget_type": "card_2"}';

comment on view lms.completion_rate_summary is '{"type": "dashboard_widget", "name": "Time Invested", "description": "Total learner minutes and completion rate", "widget_type": "card_3"}';

comment on view lms.lms_health is '{"type": "dashboard_widget", "name": "LMS Health", "description": "Overdue assignments, stale enrollments, expiring certs and late submissions", "widget_type": "card_4"}';

comment on view lms.recent_enrollments is '{"type": "dashboard_widget", "name": "Recent Enrollments", "description": "Latest 10 enrollments", "widget_type": "table_1"}';

comment on view lms.top_courses is '{"type": "dashboard_widget", "name": "Top Courses", "description": "Top 10 courses by enrollment", "widget_type": "table_2"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: courses by category
create or replace view lms.courses_by_category_pie
with
  (security_invoker = true) as
select
  coalesce(category, 'Uncategorized') as label,
  count(*) as value
from
  lms.courses
where
  status = 'published'
group by
  category
order by
  count(*) desc;

revoke all on lms.courses_by_category_pie
from
  authenticated,
  service_role;

grant
select
  on lms.courses_by_category_pie to "x-admin";

-- Bar: enrollments by course (active vs completed)
create or replace view lms.enrollments_by_course_bar
with
  (security_invoker = true) as
select
  c.title as label,
  count(e.id) filter (
    where
      e.status = 'active'
  )::bigint as active,
  count(e.id) filter (
    where
      e.status = 'completed'
  )::bigint as completed
from
  lms.courses c
  left join lms.enrollments e on e.course_id = c.id
group by
  c.id,
  c.title
having
  count(e.id) > 0
order by
  count(e.id) desc
limit
  10;

revoke all on lms.enrollments_by_course_bar
from
  authenticated,
  service_role;

grant
select
  on lms.enrollments_by_course_bar to "x-admin";

-- Line: weekly enrollment trend (last 12 weeks)
create or replace view lms.enrollment_trend_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('week', enrolled_at), 'Mon DD') as date,
  count(*)::bigint as enrolled,
  count(*) filter (
    where
      completed_at is not null
      and completed_at <= current_timestamp
  )::bigint as completed
from
  lms.enrollments
where
  enrolled_at >= current_date - interval '12 weeks'
group by
  date_trunc('week', enrolled_at)
order by
  date_trunc('week', enrolled_at);

revoke all on lms.enrollment_trend_line
from
  authenticated,
  service_role;

grant
select
  on lms.enrollment_trend_line to "x-admin";

-- Radar: lesson type metrics
create or replace view lms.lesson_type_metrics_radar
with
  (security_invoker = true) as
select
  l.type::text as metric,
  count(distinct l.id) as lessons,
  count(lp.id) filter (
    where
      lp.status = 'completed'
  )::bigint as completed_progress,
  count(lp.id) filter (
    where
      lp.status = 'in_progress'
  )::bigint as active_progress
from
  lms.lessons l
  left join lms.lesson_progress lp on lp.lesson_id = l.id
group by
  l.type;

revoke all on lms.lesson_type_metrics_radar
from
  authenticated,
  service_role;

grant
select
  on lms.lesson_type_metrics_radar to "x-admin";

comment on view lms.courses_by_category_pie is '{"type": "chart", "name": "Courses By Category", "description": "Published course count per category", "chart_type": "pie"}';

comment on view lms.enrollments_by_course_bar is '{"type": "chart", "name": "Enrollments By Course", "description": "Active vs completed enrollments per course", "chart_type": "bar"}';

comment on view lms.enrollment_trend_line is '{"type": "chart", "name": "Enrollment Trend", "description": "Weekly enrollments and completions over 12 weeks", "chart_type": "line"}';

comment on view lms.lesson_type_metrics_radar is '{"type": "chart", "name": "Lesson Type Metrics", "description": "Lesson counts and learner progress by lesson type", "chart_type": "radar"}';

----------------------------------------------------------------
-- Audit triggers
----------------------------------------------------------------
create trigger audit_lms_courses_insert
after insert on lms.courses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_courses_update
after update on lms.courses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_courses_delete
before delete on lms.courses for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_modules_insert
after insert on lms.modules for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_modules_update
after update on lms.modules for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_modules_delete
before delete on lms.modules for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_lessons_insert
after insert on lms.lessons for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_lessons_update
after update on lms.lessons for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_lessons_delete
before delete on lms.lessons for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_enrollments_insert
after insert on lms.enrollments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_enrollments_update
after update on lms.enrollments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_enrollments_delete
before delete on lms.enrollments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_lesson_progress_insert
after insert on lms.lesson_progress for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_lesson_progress_update
after update on lms.lesson_progress for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_lesson_progress_delete
before delete on lms.lesson_progress for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_assignments_insert
after insert on lms.assignments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_assignments_update
after update on lms.assignments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_assignments_delete
before delete on lms.assignments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_submissions_insert
after insert on lms.submissions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_submissions_update
after update on lms.submissions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_submissions_delete
before delete on lms.submissions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_certificates_insert
after insert on lms.certificates for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_certificates_update
after update on lms.certificates for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_certificates_delete
before delete on lms.certificates for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_paths_insert
after insert on lms.learning_paths for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_paths_update
after update on lms.learning_paths for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_paths_delete
before delete on lms.learning_paths for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
-- Enrollments: notify learner on creation, completion, and instructor on completion
create or replace function lms.trg_enrollments_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_course_title text;
    v_instructor uuid;
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if new.course_id is not null then
        select title, instructor_user_id into v_course_title, v_instructor
          from lms.courses where id = new.course_id;
    end if;

    if tg_op = 'INSERT' then
        v_type  := 'lms_enrollment_created';
        v_title := 'Enrolled in course';
        v_body  := coalesce(new.learner_name, 'A learner') ||
                   ' enrolled in "' || coalesce(v_course_title, 'a course') || '".';
        v_recipients := array_remove(
            array[new.learner_user_id, v_instructor, new.user_id],
            null
        );
    elsif new.status is distinct from old.status and new.status in ('completed', 'dropped', 'expired') then
        v_type  := 'lms_enrollment_' || new.status::text;
        v_title := 'Enrollment ' || new.status::text;
        v_body  := coalesce(new.learner_name, 'A learner') ||
                   ' is now ' || new.status::text || ' in "' || coalesce(v_course_title, 'a course') || '".';
        v_recipients := array_remove(
            array[new.learner_user_id, v_instructor],
            null
        );
    else
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'enrollment_id',   new.id,
            'course_id',       new.course_id,
            'learner_user_id', new.learner_user_id,
            'status',          new.status,
            'progress_pct',    new.progress_pct,
            'final_score',     new.final_score
        ),
        '/lms/resource/enrollments/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists enrollments_notify on lms.enrollments;

create trigger enrollments_notify
after insert or update of status on lms.enrollments for each row
execute function lms.trg_enrollments_notify ();

-- Submissions: notify learner on grading
create or replace function lms.trg_submissions_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_assignment_title text;
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if tg_op <> 'UPDATE' then
        return new;
    end if;
    if new.status is not distinct from old.status then
        return new;
    end if;
    if new.status not in ('graded', 'returned') then
        return new;
    end if;

    if new.assignment_id is not null then
        select title into v_assignment_title from lms.assignments where id = new.assignment_id;
    end if;

    v_recipients := array_remove(
        array[new.learner_user_id, new.user_id],
        null
    );

    v_type  := 'lms_submission_' || new.status::text;
    v_title := 'Submission ' || new.status::text;
    v_body  := 'Submission ' || new.submission_number ||
               ' for "' || coalesce(v_assignment_title, 'assignment') || '"' ||
               coalesce(' scored ' || new.score::text || '/' || new.max_score::text, '') ||
               '. Status: ' || new.status::text || '.';

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'submission_id',   new.id,
            'assignment_id',   new.assignment_id,
            'enrollment_id',   new.enrollment_id,
            'status',          new.status,
            'score',           new.score,
            'is_passing',      new.is_passing
        ),
        '/lms/resource/submissions/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists submissions_notify on lms.submissions;

create trigger submissions_notify
after update of status on lms.submissions for each row
execute function lms.trg_submissions_notify ();

-- Certificates: notify learner on issuance and revocation
create or replace function lms.trg_certificates_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type   text;
    v_title  text;
    v_body   text;
begin
    if tg_op = 'INSERT' then
        if new.status <> 'issued' then
            return new;
        end if;
        v_type  := 'lms_certificate_issued';
        v_title := 'Certificate issued';
        v_body  := 'Congratulations — certificate "' || new.title || '" was issued to ' ||
                   coalesce(new.learner_name, 'learner') || '.';
    elsif new.status is distinct from old.status and new.status in ('revoked', 'expired') then
        v_type  := 'lms_certificate_' || new.status::text;
        v_title := 'Certificate ' || new.status::text;
        v_body  := 'Certificate ' || new.certificate_number || ' (' || new.title || ') is now ' || new.status::text || '.';
    else
        return new;
    end if;

    v_recipients := array_remove(
        array[new.learner_user_id, new.issuer_user_id, new.user_id],
        null
    );

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'certificate_id',  new.id,
            'course_id',       new.course_id,
            'enrollment_id',   new.enrollment_id,
            'learner_user_id', new.learner_user_id,
            'status',          new.status,
            'issued_at',       new.issued_at,
            'expires_at',      new.expires_at
        ),
        '/lms/resource/certificates/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists certificates_notify on lms.certificates;

create trigger certificates_notify
after insert or update of status on lms.certificates for each row
execute function lms.trg_certificates_notify ();
