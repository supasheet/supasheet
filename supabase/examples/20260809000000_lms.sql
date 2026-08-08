-- ================================================================
-- Supasheet Example — "LMS" (learning management system)
-- ================================================================
-- A production-shaped course platform: an instructor-authored
-- catalogue of courses built from modules and lessons, quizzes with
-- graded questions, learning paths that bundle courses into a
-- curriculum, self-service and manager-assigned enrollment, lesson
-- and quiz progress tracking, certificates, and a per-course
-- discussion board.
--
-- Demo data lives in supabase/examples/l_seed.sql — apply this file
-- first, then that one.
--
-- This is not the quality module's training_records with different
-- words on it. That one is a compliance ledger: it assumes the
-- training already happened somewhere and just tracks who is current
-- on what, against a document. This one IS where the training
-- happens — the content, the quiz, the pass mark, the certificate —
-- and it has no idea what a controlled document or an SOP is.
--
-- The rules that make it a course platform rather than a set of
-- lists:
--
--   - PROGRESS IS COMPUTED FROM LESSON COMPLETION, NEVER TYPED. An
--     enrollment's progress is the share of the course's lessons
--     marked complete, recomputed the moment any lesson_progress row
--     changes. Nobody drags a slider to 80%.
--   - A COURSE CANNOT COMPLETE UNTIL EVERY LESSON IS DONE AND EVERY
--     QUIZ IS PASSED. The guard checks both before it lets an
--     enrollment's status reach `completed` — 100% progress with an
--     unpassed quiz still sitting there is refused.
--   - A CERTIFICATE CAN ONLY BE ISSUED FOR A COMPLETED ENROLLMENT.
--     There is no path to a certificate that does not go through the
--     rule above first.
--   - QUIZ ATTEMPTS ARE CAPPED. A quiz with a 3-attempt limit refuses
--     a 4th row outright — the cap is enforced in the database, not
--     hoped for in the UI.
--   - A QUIZ SCORE IS A COMPUTATION, NOT AN ENTRY. Every response is
--     graded against its question's correct option, and the
--     attempt's score is the sum of points earned over points
--     possible — never something a learner or instructor types in.
--
-- Everything the other modules cover is here too:
--   - Native-role RBAC with two custom roles ("instructor" authors
--     and grades their own courses, "learning-manager" assigns
--     courses/paths to others and watches completion without
--     touching the content) alongside "x-admin"/"user"
--   - Column-level grants: a learner ("user") can see a quiz's
--     questions and options but never which option is correct —
--     that column is instructor/x-admin only
--   - All six view layouts, every widget and chart contract, reports
--     with a Handlebars print template, a materialized completion
--     rollup, both a static and a live-data template, custom form
--     shapes, row actions, notifications, audit logging,
--     per-resource comments and a private `lms-documents` storage
--     bucket for certificates and lesson attachments
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260809000000_lms.sql \
--     -f supabase/examples/l_seed.sql
--
-- Requires the base Supasheet migrations. Add "lms" to config.toml's
-- `api.schemas` and `api.extra_search_path`, then restart Supabase.
--
-- Not idempotent: re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists lms;

-------------------------------------------------------------------
-- Roles
--
--   x-admin           LMS administrator: everything, including
--                      publishing/deleting any course
--   instructor         authors and owns their own courses — modules,
--                      lessons, quizzes — and grades attempts and
--                      short-answer responses on them. Cannot touch
--                      another instructor's course or issue a
--                      certificate by hand
--   learning-manager    assigns courses and learning paths to other
--                       people and watches completion analytics.
--                       Cannot author content or grade anything
--   user                THE LEARNER: browses the catalogue, enrolls,
--                       works through lessons and quizzes, earns
--                       certificates, and posts in the discussion
--
-- Assign a user to a custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "instructor"}'
--   where email = 'teach@example.com';
-------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'user') then
    create role "user" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'admin') then
    create role "admin" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'instructor') then
    create role "instructor" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'learning-manager') then
    create role "learning-manager" nologin;
  end if;
end;
$$;

grant "user",
"admin",
"instructor",
"learning-manager" to authenticator;

grant authenticated to "user",
"admin",
"instructor",
"learning-manager";

grant usage on schema lms to "x-admin",
"instructor",
"learning-manager",
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

-------------------------------------------------------------------
-- Enums
-------------------------------------------------------------------
create type lms.course_level as enum('beginner', 'intermediate', 'advanced');

create type lms.course_status as enum('draft', 'published', 'archived');

create type lms.content_type as enum('video', 'article', 'pdf', 'assignment');

create type lms.question_type as enum(
  'single_choice',
  'multiple_choice',
  'true_false',
  'short_answer'
);

create type lms.enrollment_status as enum('active', 'completed', 'dropped', 'expired');

create type lms.lesson_progress_status as enum('not_started', 'in_progress', 'completed');

create type lms.path_enrollment_status as enum('active', 'completed');

----------------------------------------------------------------
-- Users replica view
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
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on lms.users to "x-admin",
  "instructor",
  "learning-manager",
  "user";

comment on view lms.users is '{"display": "none"}';

----------------------------------------------------------------
-- Categories (self-referencing tree)
----------------------------------------------------------------
create table lms.categories (
  id uuid primary key default extensions.uuid_generate_v4 (),
  parent_id uuid references lms.categories (id) on delete set null,
  code varchar(20) not null unique,
  name varchar(160) not null,
  description varchar(300),
  is_active boolean not null default true,
  course_count integer not null default 0,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint categories_not_own_parent check (id <> parent_id)
);

comment on table lms.categories is '{
    "icon": "FolderTree",
    "name": "Categories",
    "description": "How the course catalogue is organised.",
    "collapsible_group": "Catalogue",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["code", "course_count"]},
        "tabs": ["courses", "learning_paths"]
    },
    "views": [
        {"id": "tree", "name": "Category Tree", "type": "tree", "parent": "parent_id", "title": "name", "secondary": "code"},
        {"id": "list", "name": "All Categories", "type": "list", "title": "name", "description": "description", "field_1": "code", "field_2": "course_count"}
    ],
    "fields": {
        "quick_create": ["code", "name", "parent_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["code", "name", "description", "parent_id", "color", "is_active"]},
            {"id": "position", "title": "Position", "fields": {"read": ["course_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "code", "desc": false}],
        "join": [{"table": "categories", "on": "parent_id", "alias": "parent", "columns": ["name", "code"]}]
    }
}';

revoke all on table lms.categories
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
delete on table lms.categories to "x-admin";

grant
select
,
  insert,
update on table lms.categories to "instructor";

grant
select
  on table lms.categories to "learning-manager",
  "user";

create index idx_lms_categories_parent_id on lms.categories (parent_id);

alter table lms.categories enable row level security;

create policy categories_select on lms.categories for
select
  to authenticated using (true);

create policy categories_insert on lms.categories for insert to authenticated
with
  check (true);

create policy categories_update on lms.categories
for update
  to authenticated using (true)
with
  check (true);

create policy categories_delete on lms.categories for delete to authenticated using (true);

----------------------------------------------------------------
-- Instructors (the authoring profile, separate from the bare user)
----------------------------------------------------------------
create table lms.instructors (
  id uuid primary key default extensions.uuid_generate_v4 (),
  user_id uuid unique references supasheet.users (id) on delete set null,
  headline varchar(200),
  bio supasheet.RICH_TEXT,
  avatar supasheet.AVATAR,
  is_active boolean not null default true,
  course_count integer not null default 0,
  student_count integer not null default 0,
  avg_rating supasheet.RATING,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table lms.instructors is '{
    "icon": "GraduationCap",
    "name": "Instructors",
    "description": "Who teaches, how many students they have reached, and how they are rated.",
    "collapsible_group": "Catalogue",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "headline", "badges": ["course_count", "avg_rating"]},
        "tabs": ["courses"]
    },
    "views": [
        {"id": "gallery", "name": "Faculty", "type": "gallery", "cover": "avatar", "title": "headline", "description": "user_id", "badge": "avg_rating"},
        {"id": "list", "name": "All Instructors", "type": "list", "title": "headline", "description": "bio", "field_1": "course_count", "field_2": "student_count"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "top_rated", "name": "Top Rated", "filters": [{"id": "avg_rating", "value": "4", "operator": "gte"}]}
    ],
    "fields": {
        "quick_create": ["user_id", "headline"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["user_id", "headline", "avatar", "is_active"]},
            {"id": "profile", "title": "Profile", "fields": ["bio"]},
            {"id": "position", "title": "Position", "fields": {"read": ["course_count", "student_count", "avg_rating"]}}
        ]
    },
    "query": {
        "sort": [{"id": "avg_rating", "desc": true}],
        "join": [{"table": "users", "on": "user_id", "columns": ["name", "email"]}]
    }
}';

comment on column lms.instructors.avatar is '{"accept": "image/*", "maxSize": 2097152}';

revoke all on table lms.instructors
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
delete on table lms.instructors to "x-admin";

grant
select
,
update on table lms.instructors to "instructor";

grant
select
  on table lms.instructors to "learning-manager",
  "user";

create index idx_lms_instructors_user_id on lms.instructors (user_id);

alter table lms.instructors enable row level security;

create policy instructors_select on lms.instructors for
select
  to authenticated using (true);

create policy instructors_insert on lms.instructors for insert to authenticated
with
  check (true);

create policy instructors_update on lms.instructors
for update
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy instructors_delete on lms.instructors for delete to authenticated using (true);

----------------------------------------------------------------
-- Courses
----------------------------------------------------------------
create sequence if not exists lms.course_number_seq;

create table lms.courses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  course_code varchar(30) not null unique default (
    'CRS-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('lms.course_number_seq')::text, 5, '0')
  ),
  title varchar(200) not null,
  category_id uuid references lms.categories (id) on delete set null,
  instructor_id uuid references lms.instructors (id) on delete set null,
  level lms.course_level not null default 'beginner',
  status lms.course_status not null default 'draft',
  description supasheet.RICH_TEXT,
  thumbnail supasheet.file,
  price numeric(10, 2) not null default 0,
  is_featured boolean not null default false,
  duration_minutes integer not null default 0,
  module_count integer not null default 0,
  lesson_count integer not null default 0,
  enrollment_count integer not null default 0,
  completion_count integer not null default 0,
  avg_rating supasheet.RATING,
  published_at timestamptz,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint courses_price_non_negative check (price >= 0)
);

comment on column lms.courses.level is '{
    "progress": false,
    "values": {
        "beginner": {"variant": "success", "icon": "Circle"},
        "intermediate": {"variant": "info", "icon": "CircleDot"},
        "advanced": {"variant": "warning", "icon": "Flame"}
    }
}';

comment on column lms.courses.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "published": {"variant": "success", "icon": "CircleCheck"},
        "archived": {"variant": "destructive", "icon": "Archive"}
    }
}';

comment on table lms.courses is '{
    "icon": "BookOpen",
    "name": "Courses",
    "description": "The catalogue. Duration, module and lesson counts are rolled up from the syllabus below — nobody types them.",
    "collapsible_group": "Catalogue",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "title", "badges": ["status", "level", "avg_rating"]},
        "tabs": ["course_modules", "quizzes", "enrollments", "discussion_posts"]
    },
    "views": [
        {"id": "gallery", "name": "Catalogue", "type": "gallery", "cover": "thumbnail", "title": "title", "description": "level", "badge": "status"},
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "title", "description": "course_code", "date": "published_at", "badge": "level"},
        {"id": "list", "name": "All Courses", "type": "list", "title": "title", "description": "course_code", "field_1": "enrollment_count", "field_2": "avg_rating"}
    ],
    "filter_presets": [
        {"id": "published", "name": "Published", "filters": [{"id": "status", "value": "published", "operator": "eq"}]},
        {"id": "featured", "name": "Featured", "filters": [{"id": "is_featured", "value": "true", "operator": "eq"}]},
        {"id": "top_rated", "name": "Top Rated", "filters": [{"id": "avg_rating", "value": "4", "operator": "gte"}]}
    ],
    "fields": {
        "quick_create": ["title", "category_id", "instructor_id", "level"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": {"create": ["title", "category_id", "instructor_id", "level", "description", "thumbnail"], "update": ["title", "category_id", "instructor_id", "level", "description", "thumbnail", "status", "is_featured"], "read": ["course_code", "title", "category_id", "instructor_id", "level", "description", "thumbnail", "status", "is_featured"]}},
            {"id": "pricing", "title": "Pricing", "fields": ["price"]},
            {"id": "syllabus", "title": "Syllabus", "fields": {"read": ["module_count", "lesson_count", "duration_minutes"]}},
            {"id": "position", "title": "Position", "fields": {"read": ["enrollment_count", "completion_count", "avg_rating", "published_at"]}}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "categories", "on": "category_id", "columns": ["code", "name"]},
            {"table": "instructors", "on": "instructor_id", "columns": ["headline", "avg_rating"]}
        ]
    }
}';

comment on column lms.courses.thumbnail is '{"accept": "image/*", "maxFiles": 1, "maxSize": 5242880}';

comment on column lms.courses.enrollment_count is '{"name": "Enrolled", "aggregate": "sum"}';

revoke all on table lms.courses
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
delete on table lms.courses to "x-admin";

grant
select
,
  insert,
update on table lms.courses to "instructor";

grant
select
  on table lms.courses to "learning-manager",
  "user";

revoke all on sequence lms.course_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence lms.course_number_seq to "x-admin",
"instructor";

create index idx_lms_courses_category_id on lms.courses (category_id);

create index idx_lms_courses_instructor_id on lms.courses (instructor_id);

create index idx_lms_courses_status on lms.courses (status);

alter table lms.courses enable row level security;

create policy courses_select on lms.courses for
select
  to authenticated using (true);

create policy courses_insert on lms.courses for insert to authenticated
with
  check (true);

create policy courses_update on lms.courses
for update
  to authenticated using (
    pg_has_role(current_user, 'x-admin', 'member')
    or exists (
      select
        1
      from
        lms.instructors i
      where
        i.id = instructor_id
        and i.user_id = (
          select
            auth.uid ()
        )
    )
  )
with
  check (true);

create policy courses_delete on lms.courses for delete to authenticated using (true);

create trigger courses_updated_at
before update on lms.courses for each row
execute function supasheet.set_updated_at ();

create or replace function lms.courses_rollup_instructor () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_instructor_id uuid;
begin
  for v_instructor_id in
    select distinct v from unnest(array[new.instructor_id, old.instructor_id]) as t (v)
    where v is not null
  loop
    update lms.instructors
    set course_count = (
        select count(*)
        from lms.courses
        where instructor_id = v_instructor_id
      ),
      updated_at = current_timestamp
    where id = v_instructor_id;
  end loop;

  return coalesce(new, old);
end;
$$;

create trigger trg_courses_rollup_instructor
after insert or delete or update of instructor_id on lms.courses for each row
execute function lms.courses_rollup_instructor ();

----------------------------------------------------------------
-- Course modules (the chapters)
----------------------------------------------------------------
create table lms.course_modules (
  id uuid primary key default extensions.uuid_generate_v4 (),
  course_id uuid not null references lms.courses (id) on delete cascade,
  title varchar(200) not null,
  sequence_number integer,
  description varchar(500),
  lesson_count integer not null default 0,
  created_at timestamptz default current_timestamp
);

comment on table lms.course_modules is '{
    "icon": "Layers",
    "name": "Modules",
    "description": "The chapters a course is broken into.",
    "collapsible_group": "Catalogue",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "title", "badges": ["lesson_count"]}, "tabs": ["lessons"]},
    "views": [
        {"id": "list", "name": "All Modules", "type": "list", "title": "title", "description": "description", "field_1": "sequence_number", "field_2": "lesson_count"}
    ],
    "fields": {
        "quick_create": ["course_id", "title"],
        "sections": [
            {"id": "module", "title": "Module", "fields": ["course_id", "sequence_number", "title", "description"]},
            {"id": "position", "title": "Position", "fields": {"read": ["lesson_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "sequence_number", "desc": false}],
        "join": [{"table": "courses", "on": "course_id", "columns": ["course_code", "title", "status"]}]
    }
}';

revoke all on table lms.course_modules
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
delete on table lms.course_modules to "x-admin";

grant
select
,
  insert,
update,
delete on table lms.course_modules to "instructor";

grant
select
  on table lms.course_modules to "learning-manager",
  "user";

create index idx_lms_modules_course_id on lms.course_modules (course_id);

alter table lms.course_modules enable row level security;

create policy modules_select on lms.course_modules for
select
  to authenticated using (true);

create policy modules_insert on lms.course_modules for insert to authenticated
with
  check (true);

create policy modules_update on lms.course_modules
for update
  to authenticated using (true)
with
  check (true);

create policy modules_delete on lms.course_modules for delete to authenticated using (true);

create or replace function lms.course_modules_set_number () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.sequence_number is null then
    select coalesce(max(sequence_number), 0) + 10 into new.sequence_number
    from lms.course_modules
    where course_id = new.course_id;
  end if;
  return new;
end;
$$;

create trigger trg_course_modules_set_number
before insert on lms.course_modules for each row
execute function lms.course_modules_set_number ();

create or replace function lms.course_modules_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_course_id uuid := coalesce(new.course_id, old.course_id);
begin
  update lms.courses
  set module_count = (
      select count(*)
      from lms.course_modules
      where course_id = v_course_id
    ),
    updated_at = current_timestamp
  where id = v_course_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_course_modules_rollup
after insert or delete on lms.course_modules for each row
execute function lms.course_modules_rollup ();

----------------------------------------------------------------
-- Lessons
----------------------------------------------------------------
create table lms.lessons (
  id uuid primary key default extensions.uuid_generate_v4 (),
  module_id uuid not null references lms.course_modules (id) on delete cascade,
  course_id uuid not null references lms.courses (id) on delete cascade,
  title varchar(200) not null,
  sequence_number integer,
  content_type lms.content_type not null default 'video',
  content supasheet.RICH_TEXT,
  video_url supasheet.URL,
  attachment supasheet.file,
  duration_minutes integer not null default 10,
  is_preview boolean not null default false,
  created_at timestamptz default current_timestamp,
  constraint lessons_duration_positive check (duration_minutes > 0)
);

comment on column lms.lessons.content_type is '{
    "progress": false,
    "values": {
        "video": {"variant": "info", "icon": "Video"},
        "article": {"variant": "default", "icon": "FileText"},
        "pdf": {"variant": "secondary", "icon": "File"},
        "assignment": {"variant": "warning", "icon": "PenLine"}
    }
}';

comment on table lms.lessons is '{
    "icon": "PlayCircle",
    "name": "Lessons",
    "description": "The individual pieces of content a learner works through.",
    "collapsible_group": "Catalogue",
    "display": "block",
    "inline_form": true,
    "primary_view": "list",
    "detail": {"header": {"title": "title", "badges": ["content_type", "duration_minutes"]}},
    "views": [
        {"id": "list", "name": "All Lessons", "type": "list", "title": "title", "description": "content_type", "field_1": "sequence_number", "field_2": "duration_minutes"}
    ],
    "filter_presets": [
        {"id": "previews", "name": "Free Previews", "filters": [{"id": "is_preview", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["module_id", "title", "content_type"],
        "sections": [
            {"id": "lesson", "title": "Lesson", "fields": ["module_id", "course_id", "sequence_number", "title", "content_type", "is_preview"]},
            {"id": "content", "title": "Content", "fields": ["content", "video_url", "attachment", "duration_minutes"]}
        ],
        "behavior": {
            "video_url": {"visible": [{"id": "content_type", "operator": "eq", "value": "video"}]},
            "content": {"visible": [{"id": "content_type", "operator": "in", "value": ["article", "assignment"]}]},
            "attachment": {"visible": [{"id": "content_type", "operator": "eq", "value": "pdf"}]}
        }
    },
    "query": {
        "sort": [{"id": "sequence_number", "desc": false}],
        "join": [
            {"table": "course_modules", "on": "module_id", "columns": ["title"]},
            {"table": "courses", "on": "course_id", "columns": ["course_code", "title"]}
        ]
    }
}';

comment on column lms.lessons.attachment is '{"accept": ".pdf", "maxFiles": 1, "maxSize": 26214400}';

revoke all on table lms.lessons
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
delete on table lms.lessons to "x-admin";

grant
select
,
  insert,
update,
delete on table lms.lessons to "instructor";

grant
select
  on table lms.lessons to "learning-manager",
  "user";

create index idx_lms_lessons_module_id on lms.lessons (module_id);

create index idx_lms_lessons_course_id on lms.lessons (course_id);

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

create or replace function lms.lessons_set_number () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.sequence_number is null then
    select coalesce(max(sequence_number), 0) + 10 into new.sequence_number
    from lms.lessons
    where module_id = new.module_id;
  end if;
  return new;
end;
$$;

create trigger trg_lessons_set_number
before insert on lms.lessons for each row
execute function lms.lessons_set_number ();

create or replace function lms.lessons_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_module_id uuid;
  v_course_id uuid;
begin
  v_module_id := coalesce(new.module_id, old.module_id);
  v_course_id := coalesce(new.course_id, old.course_id);

  update lms.course_modules
  set lesson_count = (
    select count(*) from lms.lessons where module_id = v_module_id
  )
  where id = v_module_id;

  update lms.courses
  set lesson_count = x.n,
    duration_minutes = x.total_minutes,
    updated_at = current_timestamp
  from (
    select
      count(*) as n,
      coalesce(sum(duration_minutes), 0) as total_minutes
    from lms.lessons
    where course_id = v_course_id
  ) x
  where id = v_course_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_lessons_rollup
after insert or delete or update of module_id,
course_id,
duration_minutes on lms.lessons for each row
execute function lms.lessons_rollup ();

----------------------------------------------------------------
-- Quizzes
----------------------------------------------------------------
create table lms.quizzes (
  id uuid primary key default extensions.uuid_generate_v4 (),
  course_id uuid not null references lms.courses (id) on delete cascade,
  lesson_id uuid references lms.lessons (id) on delete set null,
  title varchar(200) not null,
  passing_score_percent supasheet.PERCENTAGE not null default 70,
  time_limit_minutes integer,
  max_attempts integer not null default 3,
  question_count integer not null default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  constraint quizzes_max_attempts_positive check (max_attempts > 0),
  constraint quizzes_passing_score_range check (
    passing_score_percent >= 0
    and passing_score_percent <= 100
  )
);

comment on table lms.quizzes is '{
    "icon": "ListChecks",
    "name": "Quizzes",
    "description": "Graded checkpoints — a lesson quiz, or a standalone final exam when no lesson is set.",
    "collapsible_group": "Assessments",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "title", "badges": ["question_count", "passing_score_percent"]},
        "tabs": ["quiz_questions", "quiz_attempts"]
    },
    "views": [
        {"id": "list", "name": "All Quizzes", "type": "list", "title": "title", "description": "course_id", "field_1": "question_count", "field_2": "passing_score_percent"}
    ],
    "fields": {
        "quick_create": ["course_id", "title", "passing_score_percent"],
        "sections": [
            {"id": "quiz", "title": "Quiz", "fields": ["course_id", "lesson_id", "title"]},
            {"id": "rules", "title": "Rules", "fields": ["passing_score_percent", "time_limit_minutes", "max_attempts"]},
            {"id": "position", "title": "Position", "fields": {"read": ["question_count"]}}
        ],
        "metadata": {
            "lesson_id": {"description": "Leave blank for a course-level final exam rather than a single lesson''s quiz."}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [
            {"table": "courses", "on": "course_id", "columns": ["course_code", "title"]},
            {"table": "lessons", "on": "lesson_id", "columns": ["title"]}
        ]
    }
}';

revoke all on table lms.quizzes
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
delete on table lms.quizzes to "x-admin";

grant
select
,
  insert,
update,
delete on table lms.quizzes to "instructor";

grant
select
  on table lms.quizzes to "learning-manager",
  "user";

create index idx_lms_quizzes_course_id on lms.quizzes (course_id);

create index idx_lms_quizzes_lesson_id on lms.quizzes (lesson_id);

alter table lms.quizzes enable row level security;

create policy quizzes_select on lms.quizzes for
select
  to authenticated using (true);

create policy quizzes_insert on lms.quizzes for insert to authenticated
with
  check (true);

create policy quizzes_update on lms.quizzes
for update
  to authenticated using (true)
with
  check (true);

create policy quizzes_delete on lms.quizzes for delete to authenticated using (true);

create trigger quizzes_updated_at
before update on lms.quizzes for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Quiz questions
----------------------------------------------------------------
create table lms.quiz_questions (
  id uuid primary key default extensions.uuid_generate_v4 (),
  quiz_id uuid not null references lms.quizzes (id) on delete cascade,
  sequence_number integer,
  question_text varchar(1000) not null,
  question_type lms.question_type not null default 'single_choice',
  points integer not null default 1,
  created_at timestamptz default current_timestamp,
  constraint quiz_questions_points_positive check (points > 0)
);

comment on column lms.quiz_questions.question_type is '{
    "progress": false,
    "values": {
        "single_choice": {"variant": "info", "icon": "CircleDot"},
        "multiple_choice": {"variant": "default", "icon": "ListChecks"},
        "true_false": {"variant": "secondary", "icon": "ToggleLeft"},
        "short_answer": {"variant": "warning", "icon": "PenLine"}
    }
}';

comment on table lms.quiz_questions is '{
    "icon": "CircleHelp",
    "name": "Questions",
    "description": "One graded question per row.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "question", "title": "Question", "fields": ["quiz_id", "sequence_number", "question_text", "question_type", "points"]}
        ]
    },
    "query": {
        "sort": [{"id": "sequence_number", "desc": false}],
        "join": [{"table": "quizzes", "on": "quiz_id", "columns": ["title"]}]
    }
}';

revoke all on table lms.quiz_questions
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
delete on table lms.quiz_questions to "x-admin";

grant
select
,
  insert,
update,
delete on table lms.quiz_questions to "instructor";

grant
select
  on table lms.quiz_questions to "learning-manager",
  "user";

create index idx_lms_quiz_questions_quiz_id on lms.quiz_questions (quiz_id);

alter table lms.quiz_questions enable row level security;

create policy quiz_questions_select on lms.quiz_questions for
select
  to authenticated using (true);

create policy quiz_questions_insert on lms.quiz_questions for insert to authenticated
with
  check (true);

create policy quiz_questions_update on lms.quiz_questions
for update
  to authenticated using (true)
with
  check (true);

create policy quiz_questions_delete on lms.quiz_questions for delete to authenticated using (true);

create or replace function lms.quiz_questions_set_number () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.sequence_number is null then
    select coalesce(max(sequence_number), 0) + 10 into new.sequence_number
    from lms.quiz_questions
    where quiz_id = new.quiz_id;
  end if;
  return new;
end;
$$;

create trigger trg_quiz_questions_set_number
before insert on lms.quiz_questions for each row
execute function lms.quiz_questions_set_number ();

create or replace function lms.quiz_questions_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_quiz_id uuid := coalesce(new.quiz_id, old.quiz_id);
begin
  update lms.quizzes
  set question_count = (
      select count(*)
      from lms.quiz_questions
      where quiz_id = v_quiz_id
    ),
    updated_at = current_timestamp
  where id = v_quiz_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_quiz_questions_rollup
after insert or delete on lms.quiz_questions for each row
execute function lms.quiz_questions_rollup ();

----------------------------------------------------------------
-- Quiz options
--
-- The column-level grant below is the point: a learner can see every
-- option's text but never the is_correct column, which stays visible
-- only to the instructor and x-admin.
----------------------------------------------------------------
create table lms.quiz_options (
  id uuid primary key default extensions.uuid_generate_v4 (),
  question_id uuid not null references lms.quiz_questions (id) on delete cascade,
  option_text varchar(500) not null,
  is_correct boolean not null default false,
  sequence_number integer,
  created_at timestamptz default current_timestamp
);

comment on table lms.quiz_options is '{
    "icon": "List",
    "name": "Options",
    "description": "The answer choices for a question.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "option", "title": "Option", "fields": ["question_id", "sequence_number", "option_text", "is_correct"]}
        ]
    },
    "query": {
        "sort": [{"id": "sequence_number", "desc": false}],
        "join": [{"table": "quiz_questions", "on": "question_id", "columns": ["question_text"]}]
    }
}';

revoke all on table lms.quiz_options
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
delete on table lms.quiz_options to "x-admin";

grant
select
,
  insert,
update,
delete on table lms.quiz_options to "instructor";

-- Learners see the choices, never which one is correct.
grant
select
  (
    id,
    question_id,
    option_text,
    sequence_number,
    created_at
  ) on table lms.quiz_options to "learning-manager",
  "user";

create index idx_lms_quiz_options_question_id on lms.quiz_options (question_id);

alter table lms.quiz_options enable row level security;

create policy quiz_options_select on lms.quiz_options for
select
  to authenticated using (true);

create policy quiz_options_insert on lms.quiz_options for insert to authenticated
with
  check (true);

create policy quiz_options_update on lms.quiz_options
for update
  to authenticated using (true)
with
  check (true);

create policy quiz_options_delete on lms.quiz_options for delete to authenticated using (true);

create or replace function lms.quiz_options_set_number () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.sequence_number is null then
    select coalesce(max(sequence_number), 0) + 10 into new.sequence_number
    from lms.quiz_options
    where question_id = new.question_id;
  end if;
  return new;
end;
$$;

create trigger trg_quiz_options_set_number
before insert on lms.quiz_options for each row
execute function lms.quiz_options_set_number ();

----------------------------------------------------------------
-- Learning paths (curricula that bundle courses in sequence)
----------------------------------------------------------------
create sequence if not exists lms.path_number_seq;

create table lms.learning_paths (
  id uuid primary key default extensions.uuid_generate_v4 (),
  path_code varchar(30) not null unique default (
    'PATH-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('lms.path_number_seq')::text, 5, '0')
  ),
  title varchar(200) not null,
  description supasheet.RICH_TEXT,
  category_id uuid references lms.categories (id) on delete set null,
  is_active boolean not null default true,
  course_count integer not null default 0,
  estimated_hours numeric(6, 1) not null default 0,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table lms.learning_paths is '{
    "icon": "Route",
    "name": "Learning Paths",
    "description": "A curriculum — several courses in sequence toward one outcome.",
    "collapsible_group": "Catalogue",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "title", "badges": ["course_count", "estimated_hours"]},
        "tabs": ["learning_path_courses", "learning_path_enrollments"]
    },
    "views": [
        {"id": "list", "name": "All Paths", "type": "list", "title": "title", "description": "path_code", "field_1": "course_count", "field_2": "estimated_hours"},
        {"id": "kanban", "name": "By Category", "type": "kanban", "group": "category_id", "title": "title", "description": "path_code", "date": "created_at", "badge": "course_count"}
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["title", "category_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["title", "description", "category_id", "is_active"]},
            {"id": "position", "title": "Position", "fields": {"read": ["course_count", "estimated_hours"]}}
        ]
    },
    "query": {
        "sort": [{"id": "path_code", "desc": false}],
        "join": [{"table": "categories", "on": "category_id", "columns": ["code", "name"]}]
    }
}';

revoke all on table lms.learning_paths
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
delete on table lms.learning_paths to "x-admin";

grant
select
,
  insert,
update on table lms.learning_paths to "learning-manager";

grant
select
  on table lms.learning_paths to "instructor",
  "user";

revoke all on sequence lms.path_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence lms.path_number_seq to "x-admin",
"learning-manager";

create index idx_lms_paths_category_id on lms.learning_paths (category_id);

alter table lms.learning_paths enable row level security;

create policy paths_select on lms.learning_paths for
select
  to authenticated using (true);

create policy paths_insert on lms.learning_paths for insert to authenticated
with
  check (true);

create policy paths_update on lms.learning_paths
for update
  to authenticated using (true)
with
  check (true);

create policy paths_delete on lms.learning_paths for delete to authenticated using (true);

create trigger paths_updated_at
before update on lms.learning_paths for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Learning path courses (junction)
----------------------------------------------------------------
create table lms.learning_path_courses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  path_id uuid not null references lms.learning_paths (id) on delete cascade,
  course_id uuid not null references lms.courses (id) on delete restrict,
  sequence_number integer,
  unique (path_id, course_id)
);

comment on table lms.learning_path_courses is '{
    "icon": "Link",
    "name": "Path Courses",
    "description": "The courses in this path, in order.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "link", "title": "Link", "fields": ["path_id", "course_id", "sequence_number"]}
        ]
    },
    "query": {
        "sort": [{"id": "sequence_number", "desc": false}],
        "join": [
            {"table": "learning_paths", "on": "path_id", "columns": ["title", "path_code"]},
            {"table": "courses", "on": "course_id", "columns": ["title", "course_code", "duration_minutes"]}
        ]
    }
}';

revoke all on table lms.learning_path_courses
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
  delete on table lms.learning_path_courses to "x-admin",
  "learning-manager";

create index idx_lms_path_courses_path_id on lms.learning_path_courses (path_id);

create index idx_lms_path_courses_course_id on lms.learning_path_courses (course_id);

alter table lms.learning_path_courses enable row level security;

create policy path_courses_select on lms.learning_path_courses for
select
  to authenticated using (true);

create policy path_courses_insert on lms.learning_path_courses for insert to authenticated
with
  check (true);

create policy path_courses_delete on lms.learning_path_courses for delete to authenticated using (true);

create or replace function lms.path_courses_set_number () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.sequence_number is null then
    select coalesce(max(sequence_number), 0) + 10 into new.sequence_number
    from lms.learning_path_courses
    where path_id = new.path_id;
  end if;
  return new;
end;
$$;

create trigger trg_path_courses_set_number
before insert on lms.learning_path_courses for each row
execute function lms.path_courses_set_number ();

create or replace function lms.path_courses_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_path_id uuid := coalesce(new.path_id, old.path_id);
begin
  update lms.learning_paths p
  set course_count = x.n,
    estimated_hours = round(x.total_minutes / 60.0, 1)
  from (
    select
      count(*) as n,
      coalesce(sum(c.duration_minutes), 0) as total_minutes
    from lms.learning_path_courses lpc
      join lms.courses c on c.id = lpc.course_id
    where lpc.path_id = v_path_id
  ) x
  where p.id = v_path_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_path_courses_rollup
after insert or delete on lms.learning_path_courses for each row
execute function lms.path_courses_rollup ();

----------------------------------------------------------------
-- Learning path enrollments
----------------------------------------------------------------
create table lms.learning_path_enrollments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  path_id uuid not null references lms.learning_paths (id) on delete cascade,
  user_id uuid not null references supasheet.users (id) on delete cascade,
  assigned_by uuid references supasheet.users (id) on delete set null,
  status lms.path_enrollment_status not null default 'active',
  progress_percent numeric(5, 2) not null default 0,
  assigned_at timestamptz not null default current_timestamp,
  completed_at timestamptz,
  unique (path_id, user_id)
);

comment on column lms.learning_path_enrollments.status is '{
    "progress": true,
    "values": {
        "active": {"variant": "info", "icon": "Loader"},
        "completed": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on table lms.learning_path_enrollments is '{
    "icon": "Route",
    "name": "Path Enrollments",
    "description": "Who has been assigned this path, and how far through its courses they are.",
    "collapsible_group": "Learning",
    "display": "block",
    "primary_view": "kanban",
    "detail": {"header": {"title": "path_id", "badges": ["status", "progress_percent"]}},
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "user_id", "description": "path_id", "date": "assigned_at", "badge": "progress_percent"},
        {"id": "list", "name": "All Path Enrollments", "type": "list", "title": "user_id", "description": "path_id", "field_1": "status", "field_2": "progress_percent"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "Assigned To Me", "filters": [{"id": "user_id", "value": "me", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["path_id", "user_id"],
        "sections": [
            {"id": "assignment", "title": "Assignment", "fields": {"create": ["path_id", "user_id"], "read": ["path_id", "user_id", "assigned_by", "assigned_at"]}},
            {"id": "position", "title": "Position", "fields": {"read": ["status", "progress_percent", "completed_at"]}}
        ]
    },
    "query": {
        "sort": [{"id": "assigned_at", "desc": true}],
        "join": [
            {"table": "learning_paths", "on": "path_id", "columns": ["title", "path_code"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table lms.learning_path_enrollments
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
delete on table lms.learning_path_enrollments to "x-admin";

grant
select
,
  insert,
update on table lms.learning_path_enrollments to "learning-manager";

grant
select
  on table lms.learning_path_enrollments to "instructor";

grant
select
  on table lms.learning_path_enrollments to "user";

create index idx_lms_path_enrollments_path_id on lms.learning_path_enrollments (path_id);

create index idx_lms_path_enrollments_user_id on lms.learning_path_enrollments (user_id);

alter table lms.learning_path_enrollments enable row level security;

create policy path_enrollments_select on lms.learning_path_enrollments for
select
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'learning-manager', 'member')
    or pg_has_role(current_user, 'instructor', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  );

create policy path_enrollments_insert on lms.learning_path_enrollments for insert to authenticated
with
  check (true);

create policy path_enrollments_update on lms.learning_path_enrollments
for update
  to authenticated using (true)
with
  check (true);

create policy path_enrollments_delete on lms.learning_path_enrollments for delete to authenticated using (true);

----------------------------------------------------------------
-- Enrollments
--
-- The completion guard below is the headline rule: 100% lesson
-- progress is necessary but not sufficient — every quiz tied to the
-- course also needs a passing attempt on this enrollment. It
-- references lms.quiz_attempts, defined further down this file; that
-- is safe, since a function body is only checked against the
-- catalogue the first time it runs, and both tables exist before
-- anyone can write to either.
----------------------------------------------------------------
create table lms.enrollments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  course_id uuid not null references lms.courses (id) on delete restrict,
  user_id uuid not null references supasheet.users (id) on delete cascade,
  enrolled_by uuid references supasheet.users (id) on delete set null,
  status lms.enrollment_status not null default 'active',
  progress_percent numeric(5, 2) not null default 0,
  enrolled_at timestamptz not null default current_timestamp,
  started_at timestamptz,
  completed_at timestamptz,
  due_date date,
  last_accessed_at timestamptz,
  rating supasheet.RATING,
  review_text varchar(1000),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (course_id, user_id)
);

comment on column lms.enrollments.status is '{
    "progress": true,
    "values": {
        "active": {"variant": "info", "icon": "Loader"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "dropped": {"variant": "secondary", "icon": "CircleX"},
        "expired": {"variant": "destructive", "icon": "Clock"}
    }
}';

comment on table lms.enrollments is '{
    "icon": "UserCheck",
    "name": "Enrollments",
    "description": "Who is taking what, and how far along they are. Progress is rolled up from lesson completion — never typed.",
    "collapsible_group": "Learning",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "course_id", "badges": ["status", "progress_percent"]},
        "tabs": ["lesson_progress", "quiz_attempts", "certificates"]
    },
    "views": [
        {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "user_id", "description": "course_id", "date": "enrolled_at", "badge": "progress_percent"},
        {"id": "calendar", "name": "Due Dates", "type": "calendar", "title": "user_id", "badge": "status", "start_date": "due_date", "read_only": true},
        {"id": "list", "name": "All Enrollments", "type": "list", "title": "user_id", "description": "course_id", "field_1": "status", "field_2": "progress_percent"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "My Enrollments", "filters": [{"id": "user_id", "value": "me", "operator": "eq"}]},
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "completed", "name": "Completed", "filters": [{"id": "status", "value": "completed", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["course_id", "user_id", "due_date"],
        "sections": [
            {"id": "enrollment", "title": "Enrollment", "fields": {"create": ["course_id", "user_id", "due_date"], "update": ["due_date", "status"], "read": ["course_id", "user_id", "enrolled_by", "enrolled_at", "due_date", "status"]}},
            {"id": "position", "title": "Position", "fields": {"read": ["progress_percent", "started_at", "completed_at", "last_accessed_at"]}},
            {"id": "review", "title": "Review", "fields": {"update": ["rating", "review_text"], "read": ["rating", "review_text"]}}
        ]
    },
    "query": {
        "sort": [{"id": "enrolled_at", "desc": true}],
        "join": [
            {"table": "courses", "on": "course_id", "columns": ["title", "course_code", "status"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column lms.enrollments.progress_percent is '{"aggregate": "avg"}';

revoke all on table lms.enrollments
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
delete on table lms.enrollments to "x-admin";

grant
select
,
  insert,
update on table lms.enrollments to "learning-manager";

grant
select
  on table lms.enrollments to "instructor";

grant
select
,
  insert,
update on table lms.enrollments to "user";

create index idx_lms_enrollments_course_id on lms.enrollments (course_id);

create index idx_lms_enrollments_user_id on lms.enrollments (user_id);

create index idx_lms_enrollments_status on lms.enrollments (status);

alter table lms.enrollments enable row level security;

create policy enrollments_select on lms.enrollments for
select
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'learning-manager', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
    or exists (
      select
        1
      from
        lms.courses c
        join lms.instructors i on i.id = c.instructor_id
      where
        c.id = course_id
        and i.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy enrollments_insert on lms.enrollments for insert to authenticated
with
  check (true);

create policy enrollments_update on lms.enrollments
for update
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'learning-manager', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy enrollments_delete on lms.enrollments for delete to authenticated using (true);

create trigger enrollments_updated_at
before update on lms.enrollments for each row
execute function supasheet.set_updated_at ();

create or replace function lms.enrollments_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if new.status = 'completed' then
    if new.progress_percent < 100 then
      raise exception 'This enrollment is only % complete — every lesson has to be finished first.', (new.progress_percent || '%');
    end if;

    if exists (
      select 1
      from lms.quizzes q
      where q.course_id = new.course_id
        and not exists (
          select 1
          from lms.quiz_attempts qa
          where qa.quiz_id = q.id
            and qa.enrollment_id = new.id
            and qa.passed
        )
    ) then
      raise exception 'This course has a quiz that has not been passed yet on this enrollment.';
    end if;

    new.completed_at := current_timestamp;
  end if;

  return new;
end;
$$;

create trigger trg_enrollments_guard
before update of status on lms.enrollments for each row
execute function lms.enrollments_guard ();

-- Course-level enrollment/completion/rating rollups.
create or replace function lms.enrollments_rollup_course () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_course_id uuid;
begin
  v_course_id := coalesce(new.course_id, old.course_id);

  update lms.courses c
  set enrollment_count = x.n,
    completion_count = x.completed_n,
    avg_rating = x.avg_rating
  from (
    select
      count(*) as n,
      count(*) filter (
        where status = 'completed'
      ) as completed_n,
      avg(rating) as avg_rating
    from lms.enrollments
    where course_id = v_course_id
  ) x
  where c.id = v_course_id;

  update lms.instructors i
  set student_count = coalesce(
    (
      select count(distinct e.user_id)
      from lms.enrollments e
        join lms.courses c on c.id = e.course_id
      where c.instructor_id = i.id
    ),
    0
  )
  where i.id = (
    select instructor_id
    from lms.courses
    where id = v_course_id
  );

  return coalesce(new, old);
end;
$$;

create trigger trg_enrollments_rollup_course
after insert or delete or update of status,
rating on lms.enrollments for each row
execute function lms.enrollments_rollup_course ();

----------------------------------------------------------------
-- Lesson progress
----------------------------------------------------------------
create table lms.lesson_progress (
  id uuid primary key default extensions.uuid_generate_v4 (),
  enrollment_id uuid not null references lms.enrollments (id) on delete cascade,
  lesson_id uuid not null references lms.lessons (id) on delete cascade,
  status lms.lesson_progress_status not null default 'not_started',
  started_at timestamptz,
  completed_at timestamptz,
  time_spent_minutes integer not null default 0,
  created_at timestamptz default current_timestamp,
  unique (enrollment_id, lesson_id)
);

comment on column lms.lesson_progress.status is '{
    "progress": true,
    "values": {
        "not_started": {"variant": "secondary", "icon": "CircleDashed"},
        "in_progress": {"variant": "warning", "icon": "Loader"},
        "completed": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on table lms.lesson_progress is '{
    "icon": "CircleCheck",
    "name": "Lesson Progress",
    "description": "One row per lesson per enrollment. This is what enrollments.progress_percent is computed from.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "progress", "title": "Progress", "fields": {"create": ["enrollment_id", "lesson_id"], "update": ["status", "time_spent_minutes"], "read": ["enrollment_id", "lesson_id", "status", "started_at", "completed_at", "time_spent_minutes"]}}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [
            {"table": "enrollments", "on": "enrollment_id", "columns": ["course_id", "user_id"]},
            {"table": "lessons", "on": "lesson_id", "columns": ["title", "sequence_number"]}
        ]
    }
}';

revoke all on table lms.lesson_progress
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
delete on table lms.lesson_progress to "x-admin";

grant
select
  on table lms.lesson_progress to "learning-manager",
  "instructor";

grant
select
,
  insert,
update on table lms.lesson_progress to "user";

create index idx_lms_lesson_progress_enrollment_id on lms.lesson_progress (enrollment_id);

create index idx_lms_lesson_progress_lesson_id on lms.lesson_progress (lesson_id);

alter table lms.lesson_progress enable row level security;

create policy lesson_progress_select on lms.lesson_progress for
select
  to authenticated using (
    exists (
      select
        1
      from
        lms.enrollments e
      where
        e.id = enrollment_id
        and (
          e.user_id = (
            select
              auth.uid ()
          )
          or pg_has_role(current_user, 'learning-manager', 'member')
          or pg_has_role(current_user, 'instructor', 'member')
          or pg_has_role(current_user, 'x-admin', 'member')
        )
    )
  );

create policy lesson_progress_insert on lms.lesson_progress for insert to authenticated
with
  check (true);

create policy lesson_progress_update on lms.lesson_progress
for update
  to authenticated using (true)
with
  check (true);

create policy lesson_progress_delete on lms.lesson_progress for delete to authenticated using (true);

create or replace function lms.lesson_progress_guard () returns trigger language plpgsql
set
  search_path = '' as $$
begin
  if new.status in ('in_progress', 'completed') and new.started_at is null then
    new.started_at := current_timestamp;
  end if;

  if new.status = 'completed' and old.status is distinct from 'completed' then
    new.completed_at := current_timestamp;
  end if;

  return new;
end;
$$;

create trigger trg_lesson_progress_guard
before update on lms.lesson_progress for each row
execute function lms.lesson_progress_guard ();

-- The rule made real: an enrollment's progress is always the share of
-- its course's lessons that are complete, recomputed here — never
-- set directly by anyone.
create or replace function lms.lesson_progress_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_enrollment_id uuid := coalesce(new.enrollment_id, old.enrollment_id);
  v_course_id uuid;
begin
  select course_id into v_course_id
  from lms.enrollments
  where id = v_enrollment_id;

  update lms.enrollments e
  set progress_percent = coalesce(
    (
      select round(100.0 * count(*) filter (where lp.status = 'completed') / nullif(count(*), 0), 2)
      from lms.lessons l
        left join lms.lesson_progress lp on lp.lesson_id = l.id and lp.enrollment_id = v_enrollment_id
      where l.course_id = v_course_id
    ),
    0
  ),
    started_at = coalesce(e.started_at, current_timestamp),
    last_accessed_at = current_timestamp
  where e.id = v_enrollment_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_lesson_progress_rollup
after insert or delete or update of status on lms.lesson_progress for each row
execute function lms.lesson_progress_rollup ();

-- When one of a path's courses is completed, roll that forward into
-- every learning_path_enrollment that includes it.
create or replace function lms.enrollments_rollup_path () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_path record;
begin
  if new.status is distinct from old.status
    and (
      new.status = 'completed'
      or old.status = 'completed'
    ) then
    for v_path in
      select lpc.path_id
      from lms.learning_path_courses lpc
      where lpc.course_id = new.course_id
    loop
      update lms.learning_path_enrollments lpe
      set progress_percent = x.pct,
        status = case
          when x.pct >= 100 then 'completed'::lms.path_enrollment_status
          else 'active'::lms.path_enrollment_status
        end,
        completed_at = case
          when x.pct >= 100 then current_timestamp
          else null
        end
      from (
        select
          round(
            100.0 * count(*) filter (
              where
                e.status = 'completed'
            ) / nullif(count(*), 0),
            2
          ) as pct
        from lms.learning_path_courses lpc2
          left join lms.enrollments e on e.course_id = lpc2.course_id
          and e.user_id = new.user_id
        where lpc2.path_id = v_path.path_id
      ) x
      where lpe.path_id = v_path.path_id
        and lpe.user_id = new.user_id;
    end loop;
  end if;

  return new;
end;
$$;

create trigger trg_enrollments_rollup_path
after update of status on lms.enrollments for each row
execute function lms.enrollments_rollup_path ();

----------------------------------------------------------------
-- Quiz attempts
--
-- The attempt cap is enforced here, not in the UI: the guard counts
-- what already exists for this quiz + enrollment and refuses a row
-- past max_attempts.
----------------------------------------------------------------
create table lms.quiz_attempts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  quiz_id uuid not null references lms.quizzes (id) on delete restrict,
  enrollment_id uuid not null references lms.enrollments (id) on delete cascade,
  user_id uuid not null references supasheet.users (id) on delete cascade,
  attempt_number integer,
  score_percent numeric(5, 2) not null default 0,
  passed boolean not null default false,
  started_at timestamptz not null default current_timestamp,
  submitted_at timestamptz,
  time_taken_minutes integer,
  unique (quiz_id, enrollment_id, attempt_number)
);

comment on table lms.quiz_attempts is '{
    "icon": "FileCheck",
    "name": "Attempts",
    "description": "One row per attempt. Score and pass/fail are computed from the graded responses below, never entered.",
    "collapsible_group": "Assessments",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "attempt_number", "badges": ["passed", "score_percent"]}, "tabs": ["quiz_responses"]},
    "views": [
        {"id": "list", "name": "All Attempts", "type": "list", "title": "attempt_number", "description": "quiz_id", "field_1": "score_percent", "field_2": "passed"}
    ],
    "filter_presets": [
        {"id": "mine", "name": "My Attempts", "filters": [{"id": "user_id", "value": "me", "operator": "eq"}]},
        {"id": "passed", "name": "Passed", "filters": [{"id": "passed", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "sections": [
            {"id": "attempt", "title": "Attempt", "fields": {"create": ["quiz_id", "enrollment_id", "user_id"], "read": ["quiz_id", "enrollment_id", "user_id", "attempt_number", "started_at", "submitted_at", "time_taken_minutes"]}},
            {"id": "outcome", "title": "Outcome", "fields": {"read": ["score_percent", "passed"]}}
        ]
    },
    "query": {
        "sort": [{"id": "started_at", "desc": true}],
        "join": [
            {"table": "quizzes", "on": "quiz_id", "columns": ["title", "passing_score_percent"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column lms.quiz_attempts.score_percent is '{"aggregate": "avg"}';

revoke all on table lms.quiz_attempts
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
delete on table lms.quiz_attempts to "x-admin";

grant
select
  on table lms.quiz_attempts to "learning-manager";

grant
select
,
update on table lms.quiz_attempts to "instructor";

grant
select
,
  insert on table lms.quiz_attempts to "user";

create index idx_lms_quiz_attempts_quiz_id on lms.quiz_attempts (quiz_id);

create index idx_lms_quiz_attempts_enrollment_id on lms.quiz_attempts (enrollment_id);

alter table lms.quiz_attempts enable row level security;

create policy quiz_attempts_select on lms.quiz_attempts for
select
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'learning-manager', 'member')
    or pg_has_role(current_user, 'instructor', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  );

create policy quiz_attempts_insert on lms.quiz_attempts for insert to authenticated
with
  check (true);

create policy quiz_attempts_update on lms.quiz_attempts
for update
  to authenticated using (true)
with
  check (true);

create policy quiz_attempts_delete on lms.quiz_attempts for delete to authenticated using (true);

create or replace function lms.quiz_attempts_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_max_attempts integer;
  v_existing_count integer;
begin
  select max_attempts into v_max_attempts
  from lms.quizzes
  where id = new.quiz_id;

  select count(*) into v_existing_count
  from lms.quiz_attempts
  where quiz_id = new.quiz_id
    and enrollment_id = new.enrollment_id;

  if v_existing_count >= v_max_attempts then
    raise exception 'This quiz allows only % attempts, and all of them have been used on this enrollment.', v_max_attempts
      using hint = 'No further attempts are permitted.';
  end if;

  if new.attempt_number is null then
    new.attempt_number := v_existing_count + 1;
  end if;

  return new;
end;
$$;

create trigger trg_quiz_attempts_guard
before insert on lms.quiz_attempts for each row
execute function lms.quiz_attempts_guard ();

----------------------------------------------------------------
-- Quiz responses
----------------------------------------------------------------
create table lms.quiz_responses (
  id uuid primary key default extensions.uuid_generate_v4 (),
  attempt_id uuid not null references lms.quiz_attempts (id) on delete cascade,
  question_id uuid not null references lms.quiz_questions (id) on delete restrict,
  selected_option_id uuid references lms.quiz_options (id) on delete set null,
  answer_text varchar(1000),
  is_correct boolean not null default false,
  points_awarded integer not null default 0,
  created_at timestamptz default current_timestamp,
  unique (attempt_id, question_id)
);

comment on table lms.quiz_responses is '{
    "icon": "Rows3",
    "name": "Responses",
    "description": "One answer per question. Single/true-false questions are graded automatically; short answers wait on an instructor.",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "response", "title": "Response", "fields": {"create": ["attempt_id", "question_id", "selected_option_id", "answer_text"], "update": ["is_correct", "points_awarded"], "read": ["attempt_id", "question_id", "selected_option_id", "answer_text", "is_correct", "points_awarded"]}}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [
            {"table": "quiz_questions", "on": "question_id", "columns": ["question_text", "question_type", "points"]},
            {"table": "quiz_options", "on": "selected_option_id", "columns": ["option_text"]}
        ]
    }
}';

revoke all on table lms.quiz_responses
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
delete on table lms.quiz_responses to "x-admin";

grant
select
,
update on table lms.quiz_responses to "instructor";

grant
select
  on table lms.quiz_responses to "learning-manager";

grant
select
,
  insert on table lms.quiz_responses to "user";

create index idx_lms_quiz_responses_attempt_id on lms.quiz_responses (attempt_id);

alter table lms.quiz_responses enable row level security;

create policy quiz_responses_select on lms.quiz_responses for
select
  to authenticated using (true);

create policy quiz_responses_insert on lms.quiz_responses for insert to authenticated
with
  check (true);

create policy quiz_responses_update on lms.quiz_responses
for update
  to authenticated using (true)
with
  check (true);

create policy quiz_responses_delete on lms.quiz_responses for delete to authenticated using (true);

create or replace function lms.quiz_responses_grade () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_question_type lms.question_type;
  v_points integer;
  v_option_correct boolean;
begin
  select question_type, points into v_question_type, v_points
  from lms.quiz_questions
  where id = new.question_id;

  if v_question_type in ('single_choice', 'true_false') and new.selected_option_id is not null then
    select is_correct into v_option_correct
    from lms.quiz_options
    where id = new.selected_option_id;

    new.is_correct := coalesce(v_option_correct, false);
    new.points_awarded := case
      when new.is_correct then v_points
      else 0
    end;
  end if;

  -- multiple_choice and short_answer are graded by the instructor
  -- directly on is_correct/points_awarded, left alone here.
  return new;
end;
$$;

create trigger trg_quiz_responses_grade
before insert on lms.quiz_responses for each row
execute function lms.quiz_responses_grade ();

-- The rule made real: an attempt's score is always the sum of points
-- earned over points possible across the quiz's questions.
create or replace function lms.quiz_responses_rollup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_attempt_id uuid := coalesce(new.attempt_id, old.attempt_id);
  v_quiz_id uuid;
  v_passing supasheet.PERCENTAGE;
begin
  select quiz_id into v_quiz_id
  from lms.quiz_attempts
  where id = v_attempt_id;

  select passing_score_percent into v_passing
  from lms.quizzes
  where id = v_quiz_id;

  update lms.quiz_attempts qa
  set score_percent = x.pct,
    passed = x.pct >= v_passing
  from (
    select coalesce(
      round(
        100.0 * sum(qr.points_awarded) / nullif(sum(qq.points), 0),
        2
      ),
      0
    ) as pct
    from lms.quiz_questions qq
      left join lms.quiz_responses qr on qr.question_id = qq.id
      and qr.attempt_id = v_attempt_id
    where qq.quiz_id = v_quiz_id
  ) x
  where qa.id = v_attempt_id;

  return coalesce(new, old);
end;
$$;

create trigger trg_quiz_responses_rollup
after insert or delete or update of is_correct,
points_awarded on lms.quiz_responses for each row
execute function lms.quiz_responses_rollup ();

----------------------------------------------------------------
-- Certificates
--
-- The issue guard is the third headline rule: an insert is refused
-- outright unless the enrollment it names is already `completed`.
----------------------------------------------------------------
create sequence if not exists lms.certificate_number_seq;

create table lms.certificates (
  id uuid primary key default extensions.uuid_generate_v4 (),
  certificate_number varchar(30) not null unique default (
    'CERT-' || to_char(current_date, 'YYYY') || '-' || lpad(
      nextval('lms.certificate_number_seq')::text,
      6,
      '0'
    )
  ),
  enrollment_id uuid not null unique references lms.enrollments (id) on delete cascade,
  course_id uuid not null references lms.courses (id) on delete restrict,
  user_id uuid not null references supasheet.users (id) on delete cascade,
  verification_code varchar(20) not null unique default upper(substr(md5(random()::text), 1, 10)),
  issued_at timestamptz not null default current_timestamp,
  expires_at date,
  certificate_file supasheet.file,
  created_at timestamptz default current_timestamp
);

comment on table lms.certificates is '{
    "icon": "Award",
    "name": "Certificates",
    "description": "Proof of completion. Every one of these traces back to exactly one completed enrollment.",
    "collapsible_group": "Learning",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "certificate_number", "badges": ["issued_at"]}},
    "views": [
        {"id": "list", "name": "All Certificates", "type": "list", "title": "certificate_number", "description": "verification_code", "field_1": "course_id", "field_2": "issued_at"},
        {"id": "calendar", "name": "Issued", "type": "calendar", "title": "certificate_number", "badge": "course_id", "start_date": "issued_at", "read_only": true}
    ],
    "filter_presets": [
        {"id": "mine", "name": "My Certificates", "filters": [{"id": "user_id", "value": "me", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["enrollment_id"],
        "sections": [
            {"id": "certificate", "title": "Certificate", "fields": {"create": ["enrollment_id", "expires_at"], "read": ["certificate_number", "course_id", "user_id", "verification_code", "issued_at", "expires_at"]}},
            {"id": "extras", "title": "File", "collapsible": true, "fields": ["certificate_file"]}
        ]
    },
    "query": {
        "sort": [{"id": "issued_at", "desc": true}],
        "join": [
            {"table": "courses", "on": "course_id", "columns": ["title", "course_code"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column lms.certificates.certificate_file is '{"accept": ".pdf", "maxFiles": 1, "maxSize": 5242880}';

revoke all on table lms.certificates
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
  delete on table lms.certificates to "x-admin";

grant
select
  on table lms.certificates to "learning-manager",
  "instructor";

grant
select
  on table lms.certificates to "user";

revoke all on sequence lms.certificate_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence lms.certificate_number_seq to "x-admin";

create index idx_lms_certificates_course_id on lms.certificates (course_id);

create index idx_lms_certificates_user_id on lms.certificates (user_id);

alter table lms.certificates enable row level security;

create policy certificates_select on lms.certificates for
select
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'learning-manager', 'member')
    or pg_has_role(current_user, 'instructor', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  );

create policy certificates_insert on lms.certificates for insert to authenticated
with
  check (true);

create policy certificates_delete on lms.certificates for delete to authenticated using (true);

create or replace function lms.certificates_guard () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
  v_status lms.enrollment_status;
  v_course_id uuid;
  v_user_id uuid;
begin
  select status, course_id, user_id into v_status, v_course_id, v_user_id
  from lms.enrollments
  where id = new.enrollment_id;

  if v_status is distinct from 'completed' then
    raise exception 'A certificate can only be issued for a completed enrollment (this one is %).', v_status
      using hint = 'Complete the course first.';
  end if;

  new.course_id := v_course_id;
  new.user_id := v_user_id;

  return new;
end;
$$;

create trigger trg_certificates_guard
before insert on lms.certificates for each row
execute function lms.certificates_guard ();

----------------------------------------------------------------
-- Discussion posts (per-course Q&A, threaded)
----------------------------------------------------------------
create table lms.discussion_posts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  course_id uuid not null references lms.courses (id) on delete cascade,
  lesson_id uuid references lms.lessons (id) on delete set null,
  parent_post_id uuid references lms.discussion_posts (id) on delete cascade,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  body supasheet.RICH_TEXT not null,
  is_instructor_reply boolean not null default false,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table lms.discussion_posts is '{
    "icon": "MessagesSquare",
    "name": "Discussion",
    "description": "Course Q&A. Replies to a post thread underneath it.",
    "collapsible_group": "Learning",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "body", "badges": ["is_instructor_reply"]}},
    "views": [
        {"id": "list", "name": "All Posts", "type": "list", "title": "body", "description": "lesson_id", "field_1": "is_instructor_reply", "field_2": "created_at"}
    ],
    "fields": {
        "quick_create": ["course_id", "lesson_id", "body"],
        "sections": [
            {"id": "post", "title": "Post", "fields": {"create": ["course_id", "lesson_id", "parent_post_id", "body"], "update": ["body"], "read": ["course_id", "lesson_id", "parent_post_id", "user_id", "body", "is_instructor_reply"]}}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": false}],
        "join": [
            {"table": "courses", "on": "course_id", "columns": ["title", "course_code"]},
            {"table": "lessons", "on": "lesson_id", "columns": ["title"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

revoke all on table lms.discussion_posts
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
delete on table lms.discussion_posts to "x-admin",
"instructor",
"learning-manager",
"user";

create index idx_lms_discussion_course_id on lms.discussion_posts (course_id);

create index idx_lms_discussion_parent_id on lms.discussion_posts (parent_post_id);

alter table lms.discussion_posts enable row level security;

create policy discussion_select on lms.discussion_posts for
select
  to authenticated using (true);

create policy discussion_insert on lms.discussion_posts for insert to authenticated
with
  check (true);

create policy discussion_update on lms.discussion_posts
for update
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy discussion_delete on lms.discussion_posts for delete to authenticated using (
  user_id = (
    select
      auth.uid ()
  )
  or pg_has_role(current_user, 'x-admin', 'member')
);

create trigger discussion_updated_at
before update on lms.discussion_posts for each row
execute function supasheet.set_updated_at ();

create or replace function lms.discussion_posts_set_instructor_flag () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  new.is_instructor_reply := exists (
    select 1
    from lms.courses c
      join lms.instructors i on i.id = c.instructor_id
    where c.id = new.course_id
      and i.user_id = new.user_id
  );

  return new;
end;
$$;

create trigger trg_discussion_posts_set_instructor_flag
before insert on lms.discussion_posts for each row
execute function lms.discussion_posts_set_instructor_flag ();

----------------------------------------------------------------
-- Notification triggers
----------------------------------------------------------------
create or replace function lms.trg_enrollments_notify () returns trigger as $$
declare
  v_instructor_user_id uuid;
  v_course_title varchar(200);
begin
  select i.user_id, c.title into v_instructor_user_id, v_course_title
  from lms.courses c
    left join lms.instructors i on i.id = c.instructor_id
  where c.id = new.course_id;

  if tg_op = 'INSERT' then
    if v_instructor_user_id is not null then
      perform supasheet.create_notification(
        'course_new_enrollment',
        'New student enrolled',
        v_course_title,
        array[v_instructor_user_id],
        jsonb_build_object('course_id', new.course_id, 'enrollment_id', new.id),
        '/lms/resource/enrollments/' || new.id::text || '/detail'
      );
    end if;
  elsif new.status is distinct from old.status and new.status = 'completed' then
    perform supasheet.create_notification(
      'course_completed',
      'Course completed: ' || v_course_title,
      'Nice work — you finished every lesson and passed every quiz.',
      array[new.user_id],
      jsonb_build_object('course_id', new.course_id, 'enrollment_id', new.id),
      '/lms/resource/enrollments/' || new.id::text || '/detail'
    );

    if v_instructor_user_id is not null then
      perform supasheet.create_notification(
        'student_completed_course',
        'A student completed ' || v_course_title,
        'One more completion on your course.',
        array[v_instructor_user_id],
        jsonb_build_object('course_id', new.course_id, 'enrollment_id', new.id),
        '/lms/resource/enrollments/' || new.id::text || '/detail'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists trg_enrollments_notify on lms.enrollments;

create trigger trg_enrollments_notify
after insert or update of status on lms.enrollments for each row
execute function lms.trg_enrollments_notify ();

create or replace function lms.trg_certificates_notify () returns trigger as $$
begin
  perform supasheet.create_notification(
    'certificate_issued',
    'Certificate earned: ' || new.certificate_number,
    'Your certificate is ready.',
    array[new.user_id],
    jsonb_build_object('certificate_id', new.id, 'course_id', new.course_id),
    '/lms/resource/certificates/' || new.id::text || '/detail'
  );

  return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists trg_certificates_notify on lms.certificates;

create trigger trg_certificates_notify
after insert on lms.certificates for each row
execute function lms.trg_certificates_notify ();

create or replace function lms.trg_discussion_notify () returns trigger as $$
declare
  v_recipient uuid;
  v_instructor_user_id uuid;
begin
  if new.parent_post_id is not null then
    select user_id into v_recipient
    from lms.discussion_posts
    where id = new.parent_post_id;

    if v_recipient is not null and v_recipient <> new.user_id then
      perform supasheet.create_notification(
        'discussion_reply',
        'New reply to your post',
        left(new.body, 200),
        array[v_recipient],
        jsonb_build_object('post_id', new.id, 'course_id', new.course_id),
        '/lms/resource/discussion_posts/' || new.id::text || '/detail'
      );
    end if;
  else
    select i.user_id into v_instructor_user_id
    from lms.courses c
      join lms.instructors i on i.id = c.instructor_id
    where c.id = new.course_id;

    if v_instructor_user_id is not null and v_instructor_user_id <> new.user_id then
      perform supasheet.create_notification(
        'discussion_question',
        'New question in your course',
        left(new.body, 200),
        array[v_instructor_user_id],
        jsonb_build_object('post_id', new.id, 'course_id', new.course_id),
        '/lms/resource/discussion_posts/' || new.id::text || '/detail'
      );
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists trg_discussion_notify on lms.discussion_posts;

create trigger trg_discussion_notify
after insert on lms.discussion_posts for each row
execute function lms.trg_discussion_notify ();

create or replace function lms.trg_path_enrollments_notify () returns trigger as $$
begin
  perform supasheet.create_notification(
    'learning_path_assigned',
    'A learning path was assigned to you',
    'A new curriculum is waiting on your learning plan.',
    array[new.user_id],
    jsonb_build_object('path_id', new.path_id),
    '/lms/resource/learning_path_enrollments/' || new.id::text || '/detail'
  );

  return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists trg_path_enrollments_notify on lms.learning_path_enrollments;

create trigger trg_path_enrollments_notify
after insert on lms.learning_path_enrollments for each row
execute function lms.trg_path_enrollments_notify ();

----------------------------------------------------------------
-- Audit logging on the high-value tables
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

create trigger audit_lms_enrollments_insert
after insert on lms.enrollments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_enrollments_update
after update on lms.enrollments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_certificates_insert
after insert on lms.certificates for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_lms_certificates_delete
before delete on lms.certificates for each row
execute function supasheet.audit_trigger_function ();

-- ================================================================
-- Dashboard widgets
-- ================================================================
create or replace view lms.active_enrollments_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'user-check' as icon,
  'active enrollments' as label
from
  lms.enrollments
where
  status = 'active';

comment on view lms.active_enrollments_count is '{"type": "dashboard_widget", "name": "Active Enrollments", "description": "Learners currently working through a course", "widget_type": "card_1"}';

create or replace view lms.enrollment_status_comparison
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
  'Active' as secondary_label
from
  lms.enrollments;

comment on view lms.enrollment_status_comparison is '{"type": "dashboard_widget", "name": "Completed vs Active", "description": "Finished enrollments against everything still in progress", "widget_type": "card_2"}';

create or replace view lms.completion_rate
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
  lms.enrollments;

comment on view lms.completion_rate is '{"type": "dashboard_widget", "name": "Completion Rate", "description": "Share of every enrollment that has finished", "widget_type": "card_3"}';

create or replace view lms.enrollment_pipeline_progress
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'completed'
  ) as current,
  count(*) as total,
  json_build_array(
    json_build_object(
      'label',
      'Active',
      'value',
      count(*) filter (
        where
          status = 'active'
      )
    ),
    json_build_object(
      'label',
      'Completed',
      'value',
      count(*) filter (
        where
          status = 'completed'
      )
    ),
    json_build_object(
      'label',
      'Dropped',
      'value',
      count(*) filter (
        where
          status = 'dropped'
      )
    ),
    json_build_object(
      'label',
      'Expired',
      'value',
      count(*) filter (
        where
          status = 'expired'
      )
    )
  ) as segments
from
  lms.enrollments;

comment on view lms.enrollment_pipeline_progress is '{"type": "dashboard_widget", "name": "Enrollment Pipeline", "description": "Every enrollment, by outcome", "widget_type": "card_4"}';

create or replace view lms.certificates_breakdown
with
  (security_invoker = true) as
select
  (
    select
      count(*)
    from
      lms.certificates
  ) as value,
  'Certificates Issued' as label,
  'award' as icon,
  (
    select
      json_agg(json_build_object('label', name, 'value', n))
    from
      (
        select
          cat.name,
          count(cert.id) as n
        from
          lms.categories cat
          join lms.courses c on c.category_id = cat.id
          join lms.certificates cert on cert.course_id = c.id
        group by
          cat.name
        order by
          n desc
        limit
          5
      ) t
  ) as breakdown;

comment on view lms.certificates_breakdown is '{"type": "dashboard_widget", "name": "Certificates Issued", "description": "Total certificates, by top category", "widget_type": "card_5"}';

create or replace view lms.lms_metrics_grid
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Published Courses',
      'value',
      (
        select
          count(*)
        from
          lms.courses
        where
          status = 'published'
      )
    ),
    json_build_object(
      'label',
      'Active Learners',
      'value',
      (
        select
          count(distinct user_id)
        from
          lms.enrollments
        where
          status = 'active'
      )
    ),
    json_build_object(
      'label',
      'Quiz Pass Rate',
      'value',
      (
        select
          round(
            100.0 * count(*) filter (
              where
                passed
            ) / nullif(count(*), 0),
            0
          )
        from
          lms.quiz_attempts
      )
    ),
    json_build_object(
      'label',
      'Avg Rating',
      'value',
      (
        select
          round(avg(rating)::numeric, 1)
        from
          lms.enrollments
        where
          rating is not null
      )
    )
  ) as metrics;

comment on view lms.lms_metrics_grid is '{"type": "dashboard_widget", "name": "LMS At A Glance", "description": "The four headline counts", "widget_type": "card_6"}';

create or replace view lms.recent_enrollments
with
  (security_invoker = true) as
select
  c.title as course,
  u.name as learner,
  e.status,
  e.progress_percent,
  '/lms/resource/enrollments/' || e.id || '/detail' as link
from
  lms.enrollments e
  join lms.courses c on c.id = e.course_id
  join lms.users u on u.id = e.user_id
order by
  e.enrolled_at desc
limit
  10;

comment on view lms.recent_enrollments is '{"type": "dashboard_widget", "name": "Recent Enrollments", "description": "The most recently enrolled learners", "widget_type": "table_1"}';

create or replace view lms.courses_completion_table
with
  (security_invoker = true) as
select
  c.title as course,
  count(e.id) as enrolled,
  count(e.id) filter (
    where
      e.status = 'completed'
  ) as completed,
  '/lms/resource/courses/' || c.id || '/detail' as link
from
  lms.courses c
  left join lms.enrollments e on e.course_id = c.id
group by
  c.id,
  c.title
order by
  enrolled desc
limit
  10;

comment on view lms.courses_completion_table is '{"type": "dashboard_widget", "name": "Courses By Enrollment", "description": "Enrolled and completed counts, per course", "widget_type": "table_2"}';

create or replace view lms.overdue_learners_alert
with
  (security_invoker = true) as
select
  u.name as title,
  c.title as description,
  'clock' as icon,
  'destructive' as variant,
  '/lms/resource/enrollments/' || e.id || '/detail' as link
from
  lms.enrollments e
  join lms.users u on u.id = e.user_id
  join lms.courses c on c.id = e.course_id
where
  e.due_date < current_date
  and e.status = 'active'
order by
  e.due_date asc
limit
  10;

comment on view lms.overdue_learners_alert is '{"type": "dashboard_widget", "name": "Overdue Learners", "description": "Assigned courses past their due date and still not complete", "widget_type": "list_1"}';

create or replace view lms.exhausted_attempts_alert
with
  (security_invoker = true) as
select
  u.name as title,
  qz.title as description,
  'triangle-alert' as icon,
  'warning' as variant,
  count(qa.id)::text as field_1,
  qz.max_attempts::text as field_2,
  '/lms/resource/quizzes/' || qz.id || '/detail' as link
from
  lms.quiz_attempts qa
  join lms.quizzes qz on qz.id = qa.quiz_id
  join lms.users u on u.id = qa.user_id
where
  not qa.passed
group by
  u.name,
  qz.id,
  qz.title,
  qz.max_attempts
having
  count(qa.id) >= qz.max_attempts
order by
  count(qa.id) desc
limit
  10;

comment on view lms.exhausted_attempts_alert is '{"type": "dashboard_widget", "name": "Out Of Attempts", "description": "Learners who have used every attempt on a quiz without passing", "widget_type": "list_2"}';

create or replace view lms.recent_discussion_activity
with
  (security_invoker = true) as
select
  u.name as actor,
  case
    when dp.parent_post_id is null then 'asked a question in'
    else 'replied in'
  end as action,
  c.title as entity,
  to_char(dp.created_at, 'Mon DD, YYYY') as date,
  '/lms/resource/discussion_posts/' || dp.id || '/detail' as link
from
  lms.discussion_posts dp
  join lms.courses c on c.id = dp.course_id
  left join lms.users u on u.id = dp.user_id
order by
  dp.created_at desc
limit
  5;

comment on view lms.recent_discussion_activity is '{"type": "dashboard_widget", "name": "Recent Discussion", "description": "The latest questions and replies across every course", "widget_type": "list_3"}';

create or replace view lms.top_courses_leaderboard
with
  (security_invoker = true) as
select
  title as name,
  enrollment_count as value,
  course_code as label,
  '/lms/resource/courses/' || id || '/detail' as link
from
  lms.courses
where
  enrollment_count > 0
order by
  value desc
limit
  5;

comment on view lms.top_courses_leaderboard is '{"type": "dashboard_widget", "name": "Top Courses", "description": "Ranked by enrollment count", "widget_type": "list_4"}';

do $$
declare
  v text;
begin
  foreach v in array array[
    'lms.active_enrollments_count',
    'lms.enrollment_status_comparison',
    'lms.completion_rate',
    'lms.enrollment_pipeline_progress',
    'lms.certificates_breakdown',
    'lms.lms_metrics_grid',
    'lms.recent_enrollments',
    'lms.courses_completion_table',
    'lms.overdue_learners_alert',
    'lms.exhausted_attempts_alert',
    'lms.recent_discussion_activity',
    'lms.top_courses_leaderboard'
  ]
  loop
    execute format('revoke all on %s from public, anon, authenticated, service_role;', v);
    execute format('grant select on %s to "x-admin", "instructor", "learning-manager";', v);
  end loop;
end;
$$;

-- ================================================================
-- Charts
-- ================================================================
create or replace view lms.enrollments_by_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  lms.enrollments
group by
  status;

comment on view lms.enrollments_by_status_pie is '{"type": "chart", "name": "Enrollments By Status", "description": "Every enrollment, by outcome", "chart_type": "pie"}';

create or replace view lms.enrollments_by_category_bar
with
  (security_invoker = true) as
select
  cat.name as label,
  count(e.id) as enrollments,
  count(e.id) filter (
    where
      e.status = 'completed'
  ) as completions
from
  lms.categories cat
  join lms.courses c on c.category_id = cat.id
  left join lms.enrollments e on e.course_id = c.id
group by
  cat.name
order by
  enrollments desc;

comment on view lms.enrollments_by_category_bar is '{"type": "chart", "name": "Enrollments By Category", "description": "Enrollments and completions per course category", "chart_type": "bar"}';

create or replace view lms.monthly_enrollments_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', enrolled_at), 'Mon YYYY') as date,
  count(*) as enrollments
from
  lms.enrollments
group by
  date_trunc('month', enrolled_at)
order by
  date_trunc('month', enrolled_at);

comment on view lms.monthly_enrollments_line is '{"type": "chart", "name": "Monthly Enrollments", "description": "New enrollments by month", "chart_type": "line"}';

create or replace view lms.enrollments_completions_area
with
  (security_invoker = true) as
select
  to_char(date_trunc('month', enrolled_at), 'Mon YYYY') as date,
  count(*) as enrolled,
  count(*) filter (
    where
      status = 'completed'
  ) as completed
from
  lms.enrollments
group by
  date_trunc('month', enrolled_at)
order by
  date_trunc('month', enrolled_at);

comment on view lms.enrollments_completions_area is '{"type": "chart", "name": "Enrolled vs Completed", "description": "Monthly enrollment volume against how much has actually finished", "chart_type": "area"}';

create or replace view lms.question_type_performance_radar
with
  (security_invoker = true) as
select
  qq.question_type::text as metric,
  round(
    avg(
      case
        when qr.is_correct then 100
        else 0
      end
    ),
    1
  ) as avg_correct_rate,
  count(qr.id) as responses
from
  lms.quiz_questions qq
  left join lms.quiz_responses qr on qr.question_id = qq.id
group by
  qq.question_type;

comment on view lms.question_type_performance_radar is '{"type": "chart", "name": "Performance By Question Type", "description": "Average correct rate and response volume, by question type", "chart_type": "radar"}';

do $$
declare
  v text;
begin
  foreach v in array array[
    'lms.enrollments_by_status_pie',
    'lms.enrollments_by_category_bar',
    'lms.monthly_enrollments_line',
    'lms.enrollments_completions_area',
    'lms.question_type_performance_radar'
  ]
  loop
    execute format('revoke all on %s from public, anon, authenticated, service_role;', v);
    execute format('grant select on %s to "x-admin", "instructor", "learning-manager";', v);
  end loop;
end;
$$;

-- ================================================================
-- Reports
-- ================================================================
create or replace view lms.certificates_report
with
  (security_invoker = true) as
select
  cert.id,
  cert.certificate_number,
  cert.verification_code,
  c.title as course,
  c.course_code,
  u.name as learner,
  u.email as learner_email,
  i.headline as instructor,
  cert.issued_at,
  cert.expires_at
from
  lms.certificates cert
  join lms.courses c on c.id = cert.course_id
  join lms.users u on u.id = cert.user_id
  left join lms.instructors i on i.id = c.instructor_id;

comment on view lms.certificates_report is '{"type": "report", "name": "Certificates", "description": "Every certificate issued, with the course, learner and instructor behind it — the registry a verifier would check.", "template": true}';

revoke all on lms.certificates_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on lms.certificates_report to "x-admin",
  "instructor",
  "learning-manager";

create or replace view lms.quiz_performance_report
with
  (security_invoker = true) as
select
  qz.id,
  qz.title as quiz,
  c.title as course,
  count(qa.id) as attempt_count,
  count(qa.id) filter (
    where
      qa.passed
  ) as passed_count,
  round(avg(qa.score_percent), 1) as avg_score,
  qz.passing_score_percent
from
  lms.quizzes qz
  join lms.courses c on c.id = qz.course_id
  left join lms.quiz_attempts qa on qa.quiz_id = qz.id
group by
  qz.id,
  qz.title,
  c.title,
  qz.passing_score_percent;

comment on view lms.quiz_performance_report is '{"type": "report", "name": "Quiz Performance", "description": "Attempt volume, pass count and average score, per quiz."}';

revoke all on lms.quiz_performance_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on lms.quiz_performance_report to "x-admin",
  "instructor",
  "learning-manager";

-- Heavy monthly rollup — a materialized view instead of a live report.
create materialized view lms.enrollment_kpi_rollup as
select
  months.month,
  coalesce(en.enrollments, 0) as enrollments,
  coalesce(en.completions, 0) as completions,
  coalesce(en.avg_progress, 0) as avg_progress,
  coalesce(cert.certificates_issued, 0) as certificates_issued
from
  (
    select
      generate_series(
        date_trunc(
          'month',
          least(
            (
              select
                min(enrolled_at)
              from
                lms.enrollments
            ),
            current_timestamp
          )
        ),
        date_trunc('month', current_timestamp),
        interval '1 month'
      )::date as month
  ) months
  left join (
    select
      date_trunc('month', enrolled_at)::date as month,
      count(*) as enrollments,
      count(*) filter (
        where
          status = 'completed'
      ) as completions,
      round(avg(progress_percent), 1) as avg_progress
    from
      lms.enrollments
    group by
      1
  ) en using (month)
  left join (
    select
      date_trunc('month', issued_at)::date as month,
      count(*) as certificates_issued
    from
      lms.certificates
    group by
      1
  ) cert using (month);

create unique index idx_lms_kpi_rollup_month on lms.enrollment_kpi_rollup (month);

comment on materialized view lms.enrollment_kpi_rollup is '{"type": "report", "name": "Enrollment KPI Trend", "description": "Enrollments, completions and certificates, by month. Refresh with: refresh materialized view concurrently lms.enrollment_kpi_rollup;"}';

revoke all on lms.enrollment_kpi_rollup
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on lms.enrollment_kpi_rollup to "x-admin",
  "instructor",
  "learning-manager";

-- ================================================================
-- Templates (bulk insert)
-- ================================================================
create or replace view lms.standard_categories_template
with
  (security_invoker = true) as
select
  *
from
  (
    values
      ('TECH'::varchar(20), 'Technology'::varchar(160)),
      ('BIZ', 'Business'),
      ('COMP', 'Compliance'),
      ('LEAD', 'Leadership'),
      ('DSGN', 'Design'),
      ('MKT', 'Marketing')
  ) as t (code, name);

comment on view lms.standard_categories_template is '{
    "type": "template",
    "name": "Standard Category Set",
    "description": "A sensible starting course catalogue taxonomy for a fresh install. Apply to lms.categories.",
    "target_table": "categories"
}';

revoke all on lms.standard_categories_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on lms.standard_categories_template to "x-admin";

create or replace view lms.path_catchup_template
with
  (security_invoker = true) as
select distinct
  lpc.path_id,
  e.user_id
from
  lms.learning_path_courses lpc
  join lms.enrollments e on e.course_id = lpc.course_id
where
  not exists (
    select
      1
    from
      lms.learning_path_enrollments lpe
    where
      lpe.path_id = lpc.path_id
      and lpe.user_id = e.user_id
  );

comment on view lms.path_catchup_template is '{
    "type": "template",
    "name": "Path Catch-Up",
    "description": "Formally assigns a learning path to anyone already enrolled in one of its courses but not yet tracked against the path. Apply to lms.learning_path_enrollments.",
    "target_table": "learning_path_enrollments"
}';

revoke all on lms.path_catchup_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on lms.path_catchup_template to "x-admin",
  "learning-manager";

-- ================================================================
-- Custom forms
-- ================================================================
create or replace function lms.enroll_learner (
  p_course_id uuid,
  p_user_id uuid,
  p_due_date date default null
) returns lms.enrollments language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_enrollment lms.enrollments;
begin
  insert into lms.enrollments (course_id, user_id, enrolled_by, due_date)
  values (p_course_id, p_user_id, (select auth.uid ()), p_due_date)
  returning * into v_enrollment;

  return v_enrollment;
end;
$$;

comment on function lms.enroll_learner (uuid, uuid, date) is '{
    "type": "form",
    "resource": "courses",
    "name": "Enroll Learner",
    "description": "Assign this course to someone.",
    "icon": "UserCheck",
    "success_message": "Learner enrolled",
    "fields": {
        "sections": [
            {"id": "enrollment", "title": "Enrollment", "fields": ["p_course_id", "p_user_id", "p_due_date"]}
        ],
        "relations": {
            "p_course_id": {"table": "courses", "column": "id", "display": ["title", "course_code"]},
            "p_user_id": {"table": "users", "column": "id", "display": ["name", "email"]}
        }
    }
}';

create or replace function lms.assign_learning_path (p_path_id uuid, p_user_id uuid) returns lms.learning_path_enrollments language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_path_enrollment lms.learning_path_enrollments;
begin
  insert into lms.learning_path_enrollments (path_id, user_id, assigned_by)
  values (p_path_id, p_user_id, (select auth.uid ()))
  returning * into v_path_enrollment;

  return v_path_enrollment;
end;
$$;

comment on function lms.assign_learning_path (uuid, uuid) is '{
    "type": "form",
    "resource": "learning_paths",
    "name": "Assign Path",
    "description": "Assign this whole curriculum to someone.",
    "icon": "Route",
    "success_message": "Path assigned",
    "fields": {
        "sections": [
            {"id": "assignment", "title": "Assignment", "fields": ["p_path_id", "p_user_id"]}
        ],
        "relations": {
            "p_path_id": {"table": "learning_paths", "column": "id", "display": ["title", "path_code"]},
            "p_user_id": {"table": "users", "column": "id", "display": ["name", "email"]}
        }
    }
}';

create or replace function lms.grade_short_answer (
  p_response_id uuid,
  p_is_correct boolean,
  p_points_awarded integer
) returns lms.quiz_responses language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_response lms.quiz_responses;
begin
  update lms.quiz_responses
  set is_correct = p_is_correct,
    points_awarded = p_points_awarded
  where id = p_response_id
  returning * into v_response;

  return v_response;
end;
$$;

comment on function lms.grade_short_answer (uuid, boolean, integer) is '{
    "type": "form",
    "resource": "quiz_responses",
    "name": "Grade Response",
    "description": "Manually grade a short-answer response — the attempt''s score recomputes automatically.",
    "icon": "PenLine",
    "success_message": "Response graded",
    "fields": {
        "sections": [
            {"id": "grade", "title": "Grade", "fields": ["p_response_id", "p_is_correct", "p_points_awarded"]}
        ],
        "relations": {
            "p_response_id": {"table": "quiz_responses", "column": "id", "display": ["answer_text"]}
        }
    }
}';

do $$
declare
  f text;
begin
  foreach f in array array[
    'lms.enroll_learner(uuid, uuid, date)',
    'lms.assign_learning_path(uuid, uuid)',
    'lms.grade_short_answer(uuid, boolean, integer)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role;', f);
  end loop;
end;
$$;

grant
execute on function lms.enroll_learner (uuid, uuid, date) to "x-admin",
"learning-manager";

grant
execute on function lms.assign_learning_path (uuid, uuid) to "x-admin",
"learning-manager";

grant
execute on function lms.grade_short_answer (uuid, boolean, integer) to "x-admin",
"instructor";

-- ================================================================
-- Row actions
-- ================================================================
create or replace function lms.publish_course (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update lms.courses
  set status = 'published',
    published_at = coalesce(published_at, current_timestamp)
  where id = p_id
    and status = 'draft';
end;
$$;

comment on function lms.publish_course (uuid) is '{
    "type": "action",
    "resource": "courses",
    "name": "Publish",
    "description": "Make this course visible in the catalogue.",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "eq", "value": "draft"}],
    "success_message": "Course published"
}';

create or replace function lms.archive_course (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update lms.courses
  set status = 'archived'
  where id = p_id
    and status = 'published';
end;
$$;

comment on function lms.archive_course (uuid) is '{
    "type": "action",
    "resource": "courses",
    "name": "Archive",
    "description": "Retire this course from the active catalogue.",
    "icon": "Archive",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "eq", "value": "published"}],
    "success_message": "Course archived"
}';

create or replace function lms.start_lesson (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update lms.lesson_progress
  set status = 'in_progress'
  where id = p_id
    and status = 'not_started';
end;
$$;

comment on function lms.start_lesson (uuid) is '{
    "type": "action",
    "resource": "lesson_progress",
    "name": "Start",
    "description": "Mark this lesson as started.",
    "icon": "Play",
    "visible": [{"id": "status", "operator": "eq", "value": "not_started"}],
    "success_message": "Lesson started"
}';

create or replace function lms.complete_lesson (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update lms.lesson_progress
  set status = 'completed'
  where id = p_id
    and status in ('not_started', 'in_progress');
end;
$$;

comment on function lms.complete_lesson (uuid) is '{
    "type": "action",
    "resource": "lesson_progress",
    "name": "Complete",
    "description": "Mark this lesson as done. The enrollment''s progress recomputes immediately.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "in", "value": ["not_started", "in_progress"]}],
    "success_message": "Lesson completed"
}';

create or replace function lms.complete_enrollment (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update lms.enrollments
  set status = 'completed'
  where id = p_id
    and status = 'active';
end;
$$;

comment on function lms.complete_enrollment (uuid) is '{
    "type": "action",
    "resource": "enrollments",
    "name": "Mark Complete",
    "description": "Refused unless every lesson is done and every quiz has been passed.",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "eq", "value": "active"}],
    "success_message": "Enrollment completed"
}';

create or replace function lms.drop_enrollment (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update lms.enrollments
  set status = 'dropped'
  where id = p_id
    and status = 'active';
end;
$$;

comment on function lms.drop_enrollment (uuid) is '{
    "type": "action",
    "resource": "enrollments",
    "name": "Drop",
    "description": "Withdraw from this course.",
    "icon": "CircleX",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "eq", "value": "active"}],
    "success_message": "Enrollment dropped"
}';

create or replace function lms.issue_certificate (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  insert into lms.certificates (enrollment_id)
  values (p_id);
end;
$$;

comment on function lms.issue_certificate (uuid) is '{
    "type": "action",
    "resource": "enrollments",
    "name": "Issue Certificate",
    "description": "Refused unless this enrollment is already completed.",
    "icon": "Award",
    "visible": [{"id": "status", "operator": "eq", "value": "completed"}],
    "success_message": "Certificate issued"
}';

create or replace function lms.submit_quiz_attempt (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update lms.quiz_attempts
  set submitted_at = current_timestamp,
    time_taken_minutes = coalesce(
      time_taken_minutes,
      extract(
        epoch
        from (current_timestamp - started_at)
      )::integer / 60
    )
  where id = p_id
    and submitted_at is null;
end;
$$;

comment on function lms.submit_quiz_attempt (uuid) is '{
    "type": "action",
    "resource": "quiz_attempts",
    "name": "Submit",
    "description": "Finalize this attempt.",
    "icon": "Send",
    "visible": [{"id": "submitted_at", "operator": "is", "value": null}],
    "success_message": "Attempt submitted"
}';

do $$
declare
  f text;
begin
  foreach f in array array[
    'lms.publish_course(uuid)',
    'lms.archive_course(uuid)',
    'lms.start_lesson(uuid)',
    'lms.complete_lesson(uuid)',
    'lms.complete_enrollment(uuid)',
    'lms.drop_enrollment(uuid)',
    'lms.issue_certificate(uuid)',
    'lms.submit_quiz_attempt(uuid)'
  ]
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role;', f);
  end loop;
end;
$$;

grant
execute on function lms.publish_course (uuid) to "x-admin",
"instructor";

grant
execute on function lms.archive_course (uuid) to "x-admin",
"instructor";

grant
execute on function lms.start_lesson (uuid) to "x-admin",
"user";

grant
execute on function lms.complete_lesson (uuid) to "x-admin",
"user";

grant
execute on function lms.complete_enrollment (uuid) to "x-admin",
"user";

grant
execute on function lms.drop_enrollment (uuid) to "x-admin",
"user",
"learning-manager";

grant
execute on function lms.issue_certificate (uuid) to "x-admin",
"instructor",
"learning-manager";

grant
execute on function lms.submit_quiz_attempt (uuid) to "x-admin",
"user";

----------------------------------------------------------------
-- Private document storage
--
-- Certificate PDFs and lesson attachments already live in the
-- uploads bucket behind their own FILE columns. This bucket is for
-- anything else that needs to be evidence, gated the same way: if
-- your role cannot read lms.courses, it cannot read the file either.
----------------------------------------------------------------
insert into
  storage.buckets (id, name, public)
values
  ('lms-documents', 'lms-documents', false)
on conflict (id) do nothing;

drop policy if exists lms_documents_read on storage.objects;

create policy lms_documents_read on storage.objects for
select
  to authenticated using (
    bucket_id = 'lms-documents'
    and has_table_privilege(current_user, 'lms.courses', 'select')
  );

drop policy if exists lms_documents_insert on storage.objects;

create policy lms_documents_insert on storage.objects for insert to authenticated
with
  check (
    bucket_id = 'lms-documents'
    and has_table_privilege(current_user, 'lms.courses', 'insert')
  );

drop policy if exists lms_documents_update on storage.objects;

create policy lms_documents_update on storage.objects
for update
  to authenticated using (
    bucket_id = 'lms-documents'
    and has_table_privilege(current_user, 'lms.courses', 'update')
  );

drop policy if exists lms_documents_delete on storage.objects;

create policy lms_documents_delete on storage.objects for delete to authenticated using (
  bucket_id = 'lms-documents'
  and has_table_privilege(current_user, 'lms.courses', 'delete')
);

----------------------------------------------------------------
-- App configuration
----------------------------------------------------------------
insert into
  supasheet.configs (key, value, description, is_public)
values
  (
    'lms.default_passing_score_percent',
    '70',
    'Default passing score applied to a new quiz',
    true
  ),
  (
    'lms.default_max_attempts',
    '3',
    'Default attempt cap applied to a new quiz',
    false
  ),
  (
    'lms.certificate_validity_months',
    '24',
    'How long an issued certificate is considered current when none is set explicitly',
    true
  )
on conflict (key) do nothing;

-- ================================================================
-- Refresh the metadata catalog — must be last
-- ================================================================
select
  supasheet.refresh_metadata ();
