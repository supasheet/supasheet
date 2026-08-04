-- ================================================================
-- Supasheet Example — "Blog" (editorial CMS / publication)
-- ================================================================
-- The schema for a complete publishing operation: a contributor
-- roster with mentorship, a category taxonomy, tags, multi-part
-- series, planned content campaigns, the post pipeline itself with
-- revisions and an activity feed, reader comments with moderation,
-- daily traffic metrics, newsletter subscribers and issues.
--
-- Demo data lives in supabase/examples/b_seed.sql — apply this file
-- first, then that one.
--
-- Feature coverage:
--   - Native-role RBAC with TWO custom roles ("editor", "author")
--     alongside the built-in "x-admin"/"user" — CREATE ROLE + GRANT,
--     no permissions table
--   - Row Level Security, including ownership-scoped resources
--     (blog.posts: authors see their own drafts plus everything
--     published; blog.post_comments: readers see approved comments
--     plus their own) via pg_has_role()
--   - Column-level GRANT: an author may update only their own
--     profile fields on blog.authors
--   - All column data types: URL, TEL, EMAIL, RICH_TEXT, COLOR,
--     PERCENTAGE, DURATION, RATING, file, AVATAR, enums, arrays
--   - All six view layouts: kanban (posts, comments, campaigns),
--     calendar (posts, newsletter_issues), gallery (posts, authors,
--     series), list (tags, categories, subscribers, …), tree
--     (categories, author mentorship, threaded comments), gantt
--     (content_campaigns roadmap)
--   - Field sections, filter presets, quick_create, conditional
--     field behavior, lookup fill + lookup filter, resource links
--   - Singleton resource (blog_settings)
--   - 1:1 extension record (author_billing — x-admin only)
--   - Many-to-many junction with inline form (post_tags)
--   - One-to-many detail lines with business triggers that keep
--     parent rollups in sync (post_revisions -> posts.revision_count,
--     post_comments -> posts.comment_count, post_metrics_daily ->
--     posts.view_count, posts -> series.published_parts and
--     content_campaigns.published_posts/progress, post_tags ->
--     tags.usage_count)
--   - Detail page "tabs" allowlist + "timelines" (post_events, a
--     trigger-populated, read-only activity feed)
--   - Row actions backed by SQL functions (publish, unpublish,
--     schedule, feature, approve/spam a comment, send an issue,
--     plus an enum picker for status)
--   - Custom forms backed by SQL functions, each returning a
--     different shape: submit_post_revision (scalar uuid, on
--     "posts"), draft_series_part (single object via OUT params, on
--     "series"), bulk_reassign_posts (setof blog.posts, on
--     "authors"), preview_category_performance (setof rows via an
--     explicit table(...) list, on "categories")
--   - Templates (bulk insert via supasheet.apply_template): one
--     static (default_categories_template) and two dynamic
--     (content_refresh_template, weekly_digest_template)
--   - Reports, including one with an HTML/Handlebars print template
--     (posts_report -> supabase/examples/templates/posts_report.hbs)
--     and a MATERIALIZED VIEW report (post_traffic_rollup)
--   - Dashboard widgets: every contract (card_1..card_6, table_1,
--     table_2, list_1..list_4), global and resource-scoped
--   - Charts: every contract (pie, bar, line, area, radar), global
--     and resource-scoped
--   - Notifications (post lifecycle, review requests, comment
--     moderation, newsletter sends, and a comment-notify pairing on
--     supasheet.comments)
--   - Audit logging and per-resource comments
--   - Column footer aggregates via the `aggregate` column comment key
--
-- Apply directly against a local Supabase Postgres instance, e.g.:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260731000000_blog.sql \
--     -f supabase/examples/b_seed.sql
--
-- Requires the base Supasheet migrations (supabase/migrations/*) to
-- already be applied. Also add "blog" to config.toml's `api.schemas`
-- and `api.extra_search_path` so PostgREST exposes it, then restart
-- Supabase.
--
-- Not idempotent: `create schema` / `create type` / `create table`
-- fail on a second run. Re-run `npx supabase db reset` first.
-- ================================================================
create schema if not exists blog;

-------------------------------------------------------------------
-- Roles
--
-- "x-admin" ships with the base migrations. "user" and "admin" are
-- the optional built-in tiers (created in supabase/seed.sql), and
-- "editor"/"author" are custom roles specific to this module — a
-- custom role is nothing more than `create role ... nologin` plus
-- grants.
--
--   x-admin  publisher: full control over everything, including
--            contributor payout terms
--   editor   editorial staff: commissions, reviews, schedules and
--            publishes posts, moderates comments, runs the
--            newsletter; cannot delete records and never sees
--            author billing
--   author   contributor: writes and submits their own posts, files
--            revisions, maintains their own profile; cannot publish
--   user     reader: reads published posts, comments (pending
--            moderation), subscribes to the newsletter
--
-- Assign a user to a custom role with:
--   update auth.users
--   set raw_app_meta_data = raw_app_meta_data || '{"role": "editor"}'
--   where email = 'editor@supasheet.app';
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

  if not exists (select 1 from pg_roles where rolname = 'editor') then
    create role "editor" nologin;
  end if;

  if not exists (select 1 from pg_roles where rolname = 'author') then
    create role "author" nologin;
  end if;
end;
$$;

-- Let PostgREST SET ROLE into each role...
grant "user",
"admin",
"editor",
"author" to authenticator;

-- ...and let `to authenticated` policies still apply to them.
grant authenticated to "user",
"admin",
"editor",
"author";

-- Schema usage is granted per native role, never to `authenticated`.
grant usage on schema blog to "x-admin",
"editor",
"author",
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

create type blog.post_status as enum(
  'idea',
  'draft',
  'in_review',
  'scheduled',
  'published',
  'archived'
);

create type blog.post_type as enum(
  'article',
  'tutorial',
  'news',
  'interview',
  'changelog'
);

create type blog.post_visibility as enum('public', 'members', 'paid');

create type blog.post_event_type as enum(
  'created',
  'status_changed',
  'assigned',
  'scheduled',
  'published',
  'revision_added',
  'comment_added',
  'record_updated'
);

create type blog.revision_kind as enum('autosave', 'manual', 'editorial');

create type blog.author_level as enum(
  'contributor',
  'staff_writer',
  'senior_writer',
  'editor',
  'editor_in_chief'
);

create type blog.author_status as enum('active', 'on_leave', 'alumni');

create type blog.comment_status as enum('pending', 'approved', 'spam', 'rejected');

create type blog.series_status as enum('planning', 'ongoing', 'complete');

create type blog.campaign_status as enum(
  'planned',
  'active',
  'paused',
  'completed',
  'cancelled'
);

create type blog.newsletter_status as enum(
  'draft',
  'scheduled',
  'sending',
  'sent',
  'cancelled'
);

create type blog.subscriber_status as enum(
  'pending',
  'subscribed',
  'unsubscribed',
  'bounced'
);

create type blog.subscriber_plan as enum('free', 'member', 'paid');

create type blog.subscriber_source as enum(
  'organic',
  'post',
  'referral',
  'import',
  'campaign',
  'api'
);

commit;

----------------------------------------------------------------
-- Users replica view
--
-- FKs point at the real supasheet.users table, but PostgREST cannot
-- embed across schemas — every app schema needs a same-name replica
-- view so `query.join` on a user column resolves.
----------------------------------------------------------------
create or replace view blog.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on blog.users
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.users to "x-admin",
  "editor",
  "author",
  "user";

----------------------------------------------------------------
-- Categories (self-referencing taxonomy — tree view)
----------------------------------------------------------------
create table blog.categories (
  id uuid primary key default extensions.uuid_generate_v4 (),
  parent_id uuid references blog.categories (id) on delete set null,
  name varchar(255) not null unique,
  slug varchar(255) not null unique,
  description text,
  color supasheet.COLOR,
  is_featured boolean not null default false,
  sort_order integer not null default 0,
  seo_title varchar(255),
  seo_description varchar(500),
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table blog.categories is '{
    "icon": "FolderTree",
    "collapsible_group": "Taxonomy",
    "display": "block",
    "primary_view": "tree",
    "detail": {
        "header": {"title": "name", "badges": ["is_featured"]},
        "tabs": ["posts", "categories"]
    },
    "views": [
        {
            "id": "tree",
            "name": "Taxonomy",
            "type": "tree",
            "parent": "parent_id",
            "title": "name",
            "secondary": "slug"
        },
        {
            "id": "list",
            "name": "All Categories",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "slug",
            "field_2": "sort_order"
        }
    ],
    "filter_presets": [
        {"id": "featured", "name": "Featured", "filters": [{"id": "is_featured", "value": "true", "operator": "eq"}]},
        {"id": "top_level", "name": "Top Level", "filters": [{"id": "parent_id", "value": "null", "operator": "is"}]}
    ],
    "fields": {
        "quick_create": ["name", "slug", "parent_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "slug", "description", "parent_id"]},
            {"id": "editorial", "title": "Editorial", "fields": ["lead_editor_id", "is_featured", "sort_order", "color"]},
            {"id": "seo", "title": "SEO", "collapsible": true, "fields": ["seo_title", "seo_description"]}
        ]
    },
    "query": {
        "sort": [{"id": "sort_order", "desc": false}],
        "join": [{"table": "categories", "on": "parent_id", "alias": "parent", "columns": ["name", "slug"]}]
    }
}';

revoke all on table blog.categories
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
delete on table blog.categories to "x-admin";

grant
select
,
  insert,
update on table blog.categories to "editor";

grant
select
  on table blog.categories to "author",
  "user";

create index idx_blog_categories_parent_id on blog.categories (parent_id);

create index idx_blog_categories_slug on blog.categories (slug);

create index idx_blog_categories_sort_order on blog.categories (sort_order);

alter table blog.categories enable row level security;

create policy categories_select on blog.categories for
select
  to authenticated using (true);

create policy categories_insert on blog.categories for insert to authenticated
with
  check (true);

create policy categories_update on blog.categories
for update
  to authenticated using (true)
with
  check (true);

create policy categories_delete on blog.categories for delete to authenticated using (true);

----------------------------------------------------------------
-- Tags (flat keyword taxonomy, linked to posts through post_tags)
----------------------------------------------------------------
create table blog.tags (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(100) not null unique,
  slug varchar(100) not null unique,
  description varchar(500),
  color supasheet.COLOR,
  usage_count integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table blog.tags is '{
    "icon": "Tags",
    "collapsible_group": "Taxonomy",
    "display": "block",
    "primary_view": "list",
    "detail": {
        "header": {"title": "name", "badges": ["is_active"]},
        "tabs": ["post_tags"]
    },
    "views": [
        {
            "id": "list",
            "name": "All Tags",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "usage_count",
            "field_2": "is_active"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "is_active", "value": "true", "operator": "eq"}]},
        {"id": "unused", "name": "Unused", "filters": [{"id": "usage_count", "value": "0", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["name", "slug"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "slug", "description", "color"]},
            {"id": "state", "title": "State", "fields": {"create": ["is_active"], "update": ["is_active"], "read": ["is_active", "usage_count"]}}
        ]
    },
    "query": {
        "sort": [{"id": "usage_count", "desc": true}]
    }
}';

comment on column blog.tags.usage_count is '{"name": "Posts", "icon": "Hash", "aggregate": "sum"}';

revoke all on table blog.tags
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
delete on table blog.tags to "x-admin";

grant
select
,
  insert,
update on table blog.tags to "editor";

grant
select
  on table blog.tags to "author",
  "user";

create index idx_blog_tags_slug on blog.tags (slug);

create index idx_blog_tags_usage_count on blog.tags (usage_count desc);

alter table blog.tags enable row level security;

create policy tags_select on blog.tags for
select
  to authenticated using (true);

create policy tags_insert on blog.tags for insert to authenticated
with
  check (true);

create policy tags_update on blog.tags
for update
  to authenticated using (true)
with
  check (true);

create policy tags_delete on blog.tags for delete to authenticated using (true);

----------------------------------------------------------------
-- Authors (the contributor roster; mentorship org chart via
-- mentor_id, gallery directory via the AVATAR column)
----------------------------------------------------------------
create table blog.authors (
  id uuid primary key default extensions.uuid_generate_v4 (),
  user_id uuid references supasheet.users (id) on delete set null,
  mentor_id uuid references blog.authors (id) on delete set null,
  display_name varchar(255) not null,
  avatar supasheet.AVATAR,
  email supasheet.EMAIL,
  phone supasheet.TEL,
  website supasheet.URL,
  job_title varchar(255),
  level blog.author_level not null default 'contributor',
  status blog.author_status not null default 'active',
  tagline varchar(500),
  bio supasheet.RICH_TEXT,
  twitter_handle varchar(100),
  github_handle varchar(100),
  joined_on date,
  monthly_target integer not null default 2,
  is_accepting_assignments boolean not null default true,
  average_rating supasheet.RATING,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column blog.authors.level is '{
    "progress": true,
    "values": {
        "contributor": {"variant": "secondary", "icon": "PenLine"},
        "staff_writer": {"variant": "info", "icon": "PenTool"},
        "senior_writer": {"variant": "default", "icon": "Feather"},
        "editor": {"variant": "success", "icon": "UserCog"},
        "editor_in_chief": {"variant": "warning", "icon": "Crown"}
    }
}';

comment on column blog.authors.status is '{
    "progress": false,
    "values": {
        "active": {"variant": "success", "icon": "CircleCheck"},
        "on_leave": {"variant": "warning", "icon": "Coffee"},
        "alumni": {"variant": "secondary", "icon": "Archive"}
    }
}';

comment on table blog.authors is '{
    "icon": "UserPen",
    "collapsible_group": "Newsroom",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "display_name", "badges": ["level", "status"]},
        "tabs": ["posts", "post_revisions", "content_campaigns", "series", "author_billing"]
    },
    "views": [
        {
            "id": "gallery",
            "name": "Contributor Directory",
            "type": "gallery",
            "cover": "avatar",
            "title": "display_name",
            "description": "tagline",
            "badge": "level"
        },
        {
            "id": "tree",
            "name": "Mentorship",
            "type": "tree",
            "parent": "mentor_id",
            "title": "display_name",
            "secondary": "job_title"
        },
        {
            "id": "list",
            "name": "Roster",
            "type": "list",
            "title": "display_name",
            "description": "job_title",
            "field_1": "level",
            "field_2": "status"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "available", "name": "Taking Assignments", "filters": [{"id": "is_accepting_assignments", "value": "true", "operator": "eq"}]},
        {"id": "editors", "name": "Editors", "filters": [{"id": "level", "value": ["editor", "editor_in_chief"], "operator": "in"}]}
    ],
    "links": [
        {"id": "authors_report", "name": "Contributor Performance", "url": "/blog/report/authors_report", "icon": "BarChart3", "description": "Output, traffic and reader rating per contributor"}
    ],
    "fields": {
        "quick_create": ["display_name", "email", "level", "job_title"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["display_name", "avatar", "job_title", "tagline"]},
            {"id": "contact", "title": "Contact", "fields": ["email", "phone", "website", "user_id"]},
            {"id": "editorial", "title": "Editorial", "fields": ["level", "status", "mentor_id", "monthly_target", "is_accepting_assignments"]},
            {"id": "social", "title": "Social", "collapsible": true, "fields": ["twitter_handle", "github_handle"]},
            {"id": "extras", "title": "Bio", "collapsible": true, "fields": ["bio", "joined_on", "color"]},
            {"id": "reception", "title": "Reception", "fields": {"read": ["average_rating"]}}
        ],
        "behavior": {
            "is_accepting_assignments": {"visible": [{"id": "status", "operator": "eq", "value": "active"}]},
            "mentor_id": {"visible": [{"id": "level", "operator": "in", "value": ["contributor", "staff_writer"]}]}
        }
    },
    "query": {
        "sort": [{"id": "display_name", "desc": false}],
        "join": [
            {"table": "users", "on": "user_id", "columns": ["name", "email"]},
            {"table": "authors", "on": "mentor_id", "alias": "mentor", "columns": ["display_name", "job_title"]}
        ]
    }
}';

comment on column blog.authors.avatar is '{"accept": "image/*", "max_size": 2097152}';

comment on column blog.authors.monthly_target is '{"name": "Posts / Month", "aggregate": "sum"}';

comment on column blog.authors.average_rating is '{"name": "Reader Rating", "aggregate": "avg"}';

revoke all on table blog.authors
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
delete on table blog.authors to "x-admin";

grant
select
,
  insert,
update on table blog.authors to "editor";

grant
select
  on table blog.authors to "author",
  "user";

-- Column-level grant: a contributor maintains their own public
-- profile, but level/status/targets stay with the editorial team.
grant
update (
  display_name,
  avatar,
  tagline,
  bio,
  website,
  phone,
  twitter_handle,
  github_handle,
  is_accepting_assignments,
  color
) on table blog.authors to "author";

create index idx_blog_authors_user_id on blog.authors (user_id);

create index idx_blog_authors_mentor_id on blog.authors (mentor_id);

create index idx_blog_authors_level on blog.authors (level);

create index idx_blog_authors_status on blog.authors (status);

alter table blog.authors enable row level security;

create policy authors_select on blog.authors for
select
  to authenticated using (true);

create policy authors_insert on blog.authors for insert to authenticated
with
  check (true);

-- Contributors may only edit the row that maps to their own login;
-- editors and the publisher may edit anyone.
create policy authors_update on blog.authors
for update
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'editor', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy authors_delete on blog.authors for delete to authenticated using (true);

-- Categories gained a section editor only after authors existed —
-- adding the FK afterwards is the normal pattern for a circular
-- reference.
alter table blog.categories
add column lead_editor_id uuid references blog.authors (id) on delete set null;

create index idx_blog_categories_lead_editor_id on blog.categories (lead_editor_id);

----------------------------------------------------------------
-- Author billing (1:1 extension — a unique, not-null FK keeps
-- payout terms off the public contributor record; the UI renders it
-- as a single embedded record on the author's detail page, not a
-- list. Granted to x-admin only, so editors never see rates.)
----------------------------------------------------------------
create table blog.author_billing (
  id uuid primary key default extensions.uuid_generate_v4 (),
  author_id uuid not null references blog.authors (id) on delete cascade,
  payout_email supasheet.EMAIL,
  payout_method varchar(50) not null default 'bank_transfer',
  currency varchar(10) not null default 'USD',
  rate_per_word numeric(8, 4),
  flat_rate_per_post numeric(10, 2),
  tax_reference varchar(100),
  contract supasheet.file,
  last_paid_on date,
  lifetime_payout numeric(12, 2) not null default 0,
  notes text,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp,
  unique (author_id)
);

comment on table blog.author_billing is '{
    "icon": "Banknote",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "contributor", "title": "Contributor", "fields": ["author_id", "payout_email", "payout_method", "currency"]},
            {"id": "rates", "title": "Rates", "fields": ["rate_per_word", "flat_rate_per_post", "tax_reference"]},
            {"id": "history", "title": "History", "fields": ["last_paid_on", "lifetime_payout"]},
            {"id": "extras", "title": "Contract & notes", "collapsible": true, "fields": ["contract", "notes"]}
        ]
    },
    "query": {
        "join": [{"table": "authors", "on": "author_id", "columns": ["display_name", "level"]}]
    }
}';

comment on column blog.author_billing.contract is '{"accept": ".pdf", "max_files": 3, "max_size": 10485760}';

comment on column blog.author_billing.lifetime_payout is '{"aggregate": "sum"}';

revoke all on table blog.author_billing
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
delete on table blog.author_billing to "x-admin";

create index idx_blog_author_billing_author_id on blog.author_billing (author_id);

create index idx_blog_author_billing_last_paid_on on blog.author_billing (last_paid_on);

alter table blog.author_billing enable row level security;

create policy author_billing_select on blog.author_billing for
select
  to authenticated using (true);

create policy author_billing_insert on blog.author_billing for insert to authenticated
with
  check (true);

create policy author_billing_update on blog.author_billing
for update
  to authenticated using (true)
with
  check (true);

create policy author_billing_delete on blog.author_billing for delete to authenticated using (true);

----------------------------------------------------------------
-- Series (multi-part story arcs — gallery of covers)
----------------------------------------------------------------
create table blog.series (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null unique,
  slug varchar(255) not null unique,
  description text,
  cover supasheet.file,
  curator_id uuid references blog.authors (id) on delete set null,
  status blog.series_status not null default 'planning',
  planned_parts integer not null default 0,
  published_parts integer not null default 0,
  starts_on date,
  ends_on date,
  is_featured boolean not null default false,
  color supasheet.COLOR,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column blog.series.status is '{
    "progress": true,
    "values": {
        "planning": {"variant": "secondary", "icon": "PencilRuler"},
        "ongoing": {"variant": "info", "icon": "Loader"},
        "complete": {"variant": "success", "icon": "CircleCheck"}
    }
}';

comment on table blog.series is '{
    "icon": "Library",
    "collapsible_group": "Content",
    "display": "block",
    "primary_view": "gallery",
    "detail": {
        "header": {"title": "name", "badges": ["status", "is_featured"]},
        "tabs": ["posts"]
    },
    "views": [
        {
            "id": "gallery",
            "name": "Series Shelf",
            "type": "gallery",
            "cover": "cover",
            "title": "name",
            "description": "description",
            "badge": "status"
        },
        {
            "id": "list",
            "name": "All Series",
            "type": "list",
            "title": "name",
            "description": "description",
            "field_1": "published_parts",
            "field_2": "planned_parts"
        }
    ],
    "filter_presets": [
        {"id": "ongoing", "name": "Ongoing", "filters": [{"id": "status", "value": "ongoing", "operator": "eq"}]},
        {"id": "featured", "name": "Featured", "filters": [{"id": "is_featured", "value": "true", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["name", "slug", "curator_id"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "slug", "description", "cover"]},
            {"id": "plan", "title": "Plan", "fields": ["curator_id", "status", "planned_parts", "starts_on", "ends_on"]},
            {"id": "progress", "title": "Progress", "fields": {"read": ["published_parts"]}},
            {"id": "extras", "title": "Presentation", "collapsible": true, "fields": ["is_featured", "color"]}
        ],
        "behavior": {
            "ends_on": {"visible": [{"id": "status", "operator": "neq", "value": "planning"}]}
        }
    },
    "query": {
        "sort": [{"id": "name", "desc": false}],
        "join": [{"table": "authors", "on": "curator_id", "alias": "curator", "columns": ["display_name", "avatar"]}]
    }
}';

comment on column blog.series.cover is '{"accept": "image/*", "max_size": 5242880}';

comment on column blog.series.published_parts is '{"name": "Published", "aggregate": "sum"}';

revoke all on table blog.series
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
delete on table blog.series to "x-admin";

grant
select
,
  insert,
update on table blog.series to "editor";

grant
select
  on table blog.series to "author",
  "user";

create index idx_blog_series_curator_id on blog.series (curator_id);

create index idx_blog_series_status on blog.series (status);

alter table blog.series enable row level security;

create policy series_select on blog.series for
select
  to authenticated using (true);

create policy series_insert on blog.series for insert to authenticated
with
  check (true);

create policy series_update on blog.series
for update
  to authenticated using (true)
with
  check (true);

create policy series_delete on blog.series for delete to authenticated using (true);

----------------------------------------------------------------
-- Content campaigns (planned pushes — the gantt roadmap)
----------------------------------------------------------------
create table blog.content_campaigns (
  id uuid primary key default extensions.uuid_generate_v4 (),
  name varchar(255) not null,
  goal text,
  brief supasheet.RICH_TEXT,
  owner_id uuid references blog.authors (id) on delete set null,
  status blog.campaign_status not null default 'planned',
  start_on date not null default current_date,
  end_on date not null default (current_date + 30),
  progress supasheet.PERCENTAGE not null default 0,
  target_posts integer not null default 5,
  published_posts integer not null default 0,
  budget numeric(12, 2),
  channel varchar(100),
  color supasheet.COLOR,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column blog.content_campaigns.status is '{
    "progress": true,
    "values": {
        "planned": {"variant": "secondary", "icon": "CalendarClock"},
        "active": {"variant": "info", "icon": "Rocket"},
        "paused": {"variant": "warning", "icon": "PauseCircle"},
        "completed": {"variant": "success", "icon": "CircleCheck"},
        "cancelled": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on table blog.content_campaigns is '{
    "icon": "Megaphone",
    "name": "Campaigns",
    "collapsible_group": "Planning",
    "display": "block",
    "primary_view": "gantt",
    "detail": {
        "header": {"title": "name", "badges": ["status", "channel"]},
        "tabs": ["posts"]
    },
    "views": [
        {
            "id": "gantt",
            "name": "Roadmap",
            "type": "gantt",
            "title": "name",
            "start_date": "start_on",
            "end_date": "end_on",
            "group": "status",
            "progress": "progress",
            "badge": "status"
        },
        {
            "id": "kanban",
            "name": "By Stage",
            "type": "kanban",
            "group": "status",
            "title": "name",
            "description": "goal",
            "date": "end_on",
            "badge": "channel"
        },
        {
            "id": "list",
            "name": "All Campaigns",
            "type": "list",
            "title": "name",
            "description": "goal",
            "field_1": "status",
            "field_2": "end_on"
        }
    ],
    "filter_presets": [
        {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
        {"id": "upcoming", "name": "Upcoming", "filters": [{"id": "status", "value": "planned", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["name", "owner_id", "start_on", "end_on"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["name", "goal", "brief", "channel"]},
            {"id": "plan", "title": "Plan", "fields": ["owner_id", "status", "start_on", "end_on", "target_posts", "budget"]},
            {"id": "progress", "title": "Progress", "fields": {"update": ["progress"], "read": ["progress", "published_posts"]}},
            {"id": "extras", "title": "Presentation", "collapsible": true, "fields": ["color"]}
        ],
        "behavior": {
            "budget": {"read_only": [{"id": "status", "operator": "in", "value": ["completed", "cancelled"]}]}
        }
    },
    "query": {
        "sort": [{"id": "start_on", "desc": false}],
        "join": [
            {"table": "authors", "on": "owner_id", "alias": "owner", "columns": ["display_name", "avatar"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column blog.content_campaigns.progress is '{"name": "Progress", "aggregate": "avg"}';

comment on column blog.content_campaigns.budget is '{"aggregate": "sum"}';

revoke all on table blog.content_campaigns
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
delete on table blog.content_campaigns to "x-admin";

grant
select
,
  insert,
update on table blog.content_campaigns to "editor";

grant
select
  on table blog.content_campaigns to "author";

create index idx_blog_content_campaigns_owner_id on blog.content_campaigns (owner_id);

create index idx_blog_content_campaigns_status on blog.content_campaigns (status);

create index idx_blog_content_campaigns_start_on on blog.content_campaigns (start_on);

create index idx_blog_content_campaigns_end_on on blog.content_campaigns (end_on);

alter table blog.content_campaigns enable row level security;

create policy content_campaigns_select on blog.content_campaigns for
select
  to authenticated using (true);

create policy content_campaigns_insert on blog.content_campaigns for insert to authenticated
with
  check (true);

create policy content_campaigns_update on blog.content_campaigns
for update
  to authenticated using (true)
with
  check (true);

create policy content_campaigns_delete on blog.content_campaigns for delete to authenticated using (true);

----------------------------------------------------------------
-- Posts (the core resource)
----------------------------------------------------------------
create sequence if not exists blog.post_number_seq;

create table blog.posts (
  id uuid primary key default extensions.uuid_generate_v4 (),
  reference varchar(30) not null unique default (
    'POST-' || to_char(current_date, 'YYYY') || '-' || lpad(nextval('blog.post_number_seq')::text, 5, '0')
  ),
  title varchar(500) not null,
  -- Nullable on purpose: blog.trg_posts_apply_defaults() slugifies
  -- the title whenever the field is left empty.
  slug varchar(255) unique,
  excerpt varchar(500),
  body supasheet.RICH_TEXT,
  cover supasheet.file,
  attachments supasheet.file,
  author_id uuid references blog.authors (id) on delete set null,
  editor_id uuid references blog.authors (id) on delete set null,
  category_id uuid references blog.categories (id) on delete set null,
  series_id uuid references blog.series (id) on delete set null,
  campaign_id uuid references blog.content_campaigns (id) on delete set null,
  status blog.post_status not null default 'draft',
  post_type blog.post_type not null default 'article',
  visibility blog.post_visibility not null default 'public',
  series_part integer,
  review_notes text,
  scheduled_for timestamptz,
  published_at timestamptz,
  archived_at timestamptz,
  is_featured boolean not null default false,
  is_pinned boolean not null default false,
  allow_comments boolean not null default true,
  word_count integer not null default 0,
  reading_time supasheet.DURATION not null default 0,
  view_count integer not null default 0,
  unique_visitor_count integer not null default 0,
  like_count integer not null default 0,
  comment_count integer not null default 0,
  share_count integer not null default 0,
  revision_count integer not null default 0,
  completion_rate supasheet.PERCENTAGE,
  average_rating supasheet.RATING,
  seo_title varchar(255),
  seo_description varchar(500),
  canonical_url supasheet.URL,
  keywords varchar(500) [],
  color supasheet.COLOR,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column blog.posts.status is '{
    "progress": true,
    "values": {
        "idea": {"variant": "secondary", "icon": "Lightbulb"},
        "draft": {"variant": "default", "icon": "FilePen"},
        "in_review": {"variant": "warning", "icon": "Eye"},
        "scheduled": {"variant": "info", "icon": "CalendarClock"},
        "published": {"variant": "success", "icon": "Globe"},
        "archived": {"variant": "secondary", "icon": "Archive"}
    }
}';

comment on column blog.posts.post_type is '{
    "progress": false,
    "values": {
        "article": {"variant": "default", "icon": "Newspaper"},
        "tutorial": {"variant": "info", "icon": "GraduationCap"},
        "news": {"variant": "warning", "icon": "Radio"},
        "interview": {"variant": "success", "icon": "Mic"},
        "changelog": {"variant": "secondary", "icon": "ListChecks"}
    }
}';

comment on column blog.posts.visibility is '{
    "progress": false,
    "icon_only": true,
    "values": {
        "public": {"variant": "success", "icon": "Globe"},
        "members": {"variant": "info", "icon": "Users"},
        "paid": {"variant": "warning", "icon": "Lock"}
    }
}';

comment on table blog.posts is '{
    "icon": "Newspaper",
    "collapsible_group": "Content",
    "display": "block",
    "primary_view": "kanban",
    "detail": {
        "header": {"title": "title", "badges": ["status", "post_type", "visibility"]},
        "tabs": ["post_comments", "post_revisions", "post_tags", "post_metrics_daily"],
        "timelines": ["post_events"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Editorial Board",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "excerpt",
            "date": "scheduled_for",
            "badge": "post_type"
        },
        {
            "id": "calendar",
            "name": "Publishing Calendar",
            "type": "calendar",
            "title": "title",
            "badge": "status",
            "start_date": "scheduled_for",
            "end_date": "published_at"
        },
        {
            "id": "gallery",
            "name": "Magazine",
            "type": "gallery",
            "cover": "cover",
            "title": "title",
            "description": "excerpt",
            "badge": "status"
        },
        {
            "id": "list",
            "name": "All Posts",
            "type": "list",
            "title": "title",
            "description": "excerpt",
            "field_1": "status",
            "field_2": "published_at"
        }
    ],
    "filter_presets": [
        {"id": "my_drafts", "name": "Drafts", "filters": [{"id": "status", "value": ["idea", "draft"], "operator": "in"}]},
        {"id": "in_review", "name": "In Review", "filters": [{"id": "status", "value": "in_review", "operator": "eq"}]},
        {"id": "scheduled", "name": "Scheduled", "filters": [{"id": "status", "value": "scheduled", "operator": "eq"}]},
        {"id": "published", "name": "Published", "filters": [{"id": "status", "value": "published", "operator": "eq"}]},
        {"id": "featured", "name": "Featured", "filters": [{"id": "is_featured", "value": "true", "operator": "eq"}]},
        {"id": "unassigned", "name": "No Editor", "filters": [{"id": "editor_id", "value": "null", "operator": "is"}]},
        {"id": "premium", "name": "Members & Paid", "filters": [{"id": "visibility", "value": ["members", "paid"], "operator": "in"}]}
    ],
    "links": [
        {"id": "posts_report", "name": "Post Report", "url": "/blog/report/posts_report", "icon": "FileText", "description": "Full post export with author, category and traffic context"},
        {"id": "engagement_report", "name": "Engagement", "url": "/blog/report/engagement_report", "icon": "Activity", "description": "Views, reads, comments and shares per post"}
    ],
    "fields": {
        "quick_create": ["title", "post_type", "category_id", "author_id"],
        "sections": [
            {"id": "content", "title": "Content", "fields": ["title", "slug", "excerpt", "body", "cover"]},
            {"id": "classification", "title": "Classification", "fields": ["post_type", "category_id", "series_id", "series_part", "campaign_id"]},
            {"id": "people", "title": "People", "fields": ["author_id", "editor_id"]},
            {"id": "workflow", "title": "Workflow", "fields": ["status", "visibility", "review_notes", "scheduled_for"]},
            {"id": "publishing", "title": "Publishing", "fields": {"update": ["published_at", "archived_at"], "read": ["published_at", "archived_at"]}},
            {"id": "reach", "title": "Reach", "fields": {"read": ["view_count", "unique_visitor_count", "like_count", "comment_count", "share_count", "completion_rate", "average_rating"]}},
            {"id": "effort", "title": "Effort", "fields": {"read": ["word_count", "reading_time", "revision_count"]}},
            {"id": "seo", "title": "SEO", "collapsible": true, "fields": ["seo_title", "seo_description", "canonical_url", "keywords"]},
            {"id": "extras", "title": "Attachments & presentation", "collapsible": true, "fields": ["attachments", "is_featured", "is_pinned", "allow_comments", "color"]}
        ],
        "behavior": {
            "review_notes": {
                "visible": [{"id": "status", "operator": "eq", "value": "in_review"}],
                "required": [{"id": "status", "operator": "eq", "value": "in_review"}]
            },
            "scheduled_for": {
                "visible": [{"id": "status", "operator": "in", "value": ["scheduled", "published"]}],
                "required": [{"id": "status", "operator": "eq", "value": "scheduled"}]
            },
            "published_at": {"visible": [{"id": "status", "operator": "in", "value": ["published", "archived"]}]},
            "archived_at": {"visible": [{"id": "status", "operator": "eq", "value": "archived"}]},
            "series_part": {"visible": [{"id": "series_id", "operator": "not.is", "value": "null"}]},
            "slug": {"read_only": [{"id": "status", "operator": "in", "value": ["published", "archived"]}]}
        },
        "lookups": {
            "category_id": {"fill": [{"source_column": "editor_id", "target_column": "lead_editor_id"}]},
            "series_id": {"filter": [{"source_column": "author_id", "target_column": "curator_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "users", "on": "user_id", "columns": ["name", "email"]},
            {"table": "authors", "on": "author_id", "alias": "author", "columns": ["display_name", "avatar"]},
            {"table": "authors", "on": "editor_id", "alias": "editor", "columns": ["display_name", "avatar"]},
            {"table": "categories", "on": "category_id", "columns": ["name", "slug"]},
            {"table": "series", "on": "series_id", "columns": ["name", "status"]},
            {"table": "content_campaigns", "on": "campaign_id", "alias": "campaign", "columns": ["name", "status"]}
        ]
    }
}';

comment on column blog.posts.reference is '{"name": "Ref", "icon": "Hash"}';

comment on column blog.posts.cover is '{"accept": "image/*", "max_size": 5242880}';

comment on column blog.posts.attachments is '{"accept": "*", "max_files": 10, "max_size": 10485760}';

comment on column blog.posts.reading_time is '{"name": "Read Time", "aggregate": "avg"}';

comment on column blog.posts.word_count is '{"name": "Words", "aggregate": "sum"}';

comment on column blog.posts.view_count is '{"name": "Views", "aggregate": "sum"}';

comment on column blog.posts.unique_visitor_count is '{"name": "Visitors", "aggregate": "sum"}';

comment on column blog.posts.comment_count is '{"name": "Comments", "aggregate": "sum"}';

comment on column blog.posts.completion_rate is '{"name": "Read Through", "aggregate": "avg"}';

comment on column blog.posts.average_rating is '{"name": "Rating", "aggregate": "avg"}';

revoke all on table blog.posts
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
delete on table blog.posts to "x-admin";

grant
select
,
  insert,
update on table blog.posts to "editor";

-- Contributors write and submit their own work; RLS narrows which
-- rows they may touch.
grant
select
,
  insert,
update on table blog.posts to "author";

grant
select
  on table blog.posts to "user";

-- The `reference` default calls nextval(), so every role that can
-- insert a post also needs usage on the backing sequence.
revoke all on sequence blog.post_number_seq
from
  public,
  anon,
  authenticated,
  service_role;

grant usage on sequence blog.post_number_seq to "x-admin",
"editor",
"author";

create index idx_blog_posts_author_id on blog.posts (author_id);

create index idx_blog_posts_editor_id on blog.posts (editor_id);

create index idx_blog_posts_category_id on blog.posts (category_id);

create index idx_blog_posts_series_id on blog.posts (series_id);

create index idx_blog_posts_campaign_id on blog.posts (campaign_id);

create index idx_blog_posts_status on blog.posts (status);

create index idx_blog_posts_post_type on blog.posts (post_type);

create index idx_blog_posts_visibility on blog.posts (visibility);

create index idx_blog_posts_slug on blog.posts (slug);

create index idx_blog_posts_scheduled_for on blog.posts (scheduled_for);

create index idx_blog_posts_published_at on blog.posts (published_at desc);

create index idx_blog_posts_user_id on blog.posts (user_id);

create index idx_blog_posts_created_at on blog.posts (created_at desc);

alter table blog.posts enable row level security;

-- Readers only ever reach published posts; contributors additionally
-- see everything they filed themselves; editors and the publisher see
-- the whole pipeline. Grants already decided who may attempt the
-- operation — this decides which rows.
create policy posts_select on blog.posts for
select
  to authenticated using (
    status = 'published'
    or user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'editor', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  );

create policy posts_insert on blog.posts for insert to authenticated
with
  check (true);

-- A contributor may keep editing their own post until the desk takes
-- it over; editors and the publisher may edit anything.
create policy posts_update on blog.posts
for update
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'editor', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  )
with
  check (true);

create policy posts_delete on blog.posts for delete to authenticated using (true);

----------------------------------------------------------------
-- Post tags (many-to-many posts <-> tags, inline form)
----------------------------------------------------------------
create table blog.post_tags (
  id uuid primary key default extensions.uuid_generate_v4 (),
  post_id uuid not null references blog.posts (id) on delete cascade,
  tag_id uuid not null references blog.tags (id) on delete cascade,
  created_at timestamptz default current_timestamp,
  unique (post_id, tag_id)
);

comment on table blog.post_tags is '{
    "icon": "Tag",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "link", "title": "Tag", "fields": ["post_id", "tag_id"]}
        ]
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "posts", "on": "post_id", "columns": ["reference", "title", "status"]},
            {"table": "tags", "on": "tag_id", "columns": ["name", "slug", "color"]}
        ]
    }
}';

revoke all on table blog.post_tags
from
  public,
  anon,
  authenticated,
  service_role;

-- Junction table: no update grant, only link/unlink.
grant
select
,
  insert,
  delete on table blog.post_tags to "x-admin",
  "editor",
  "author";

grant
select
  on table blog.post_tags to "user";

create index idx_blog_post_tags_post_id on blog.post_tags (post_id);

create index idx_blog_post_tags_tag_id on blog.post_tags (tag_id);

alter table blog.post_tags enable row level security;

create policy post_tags_select on blog.post_tags for
select
  to authenticated using (true);

create policy post_tags_insert on blog.post_tags for insert to authenticated
with
  check (true);

create policy post_tags_delete on blog.post_tags for delete to authenticated using (true);

----------------------------------------------------------------
-- Post revisions (version history — rendered as a tab on the post
-- detail page)
----------------------------------------------------------------
create table blog.post_revisions (
  id uuid primary key default extensions.uuid_generate_v4 (),
  post_id uuid not null references blog.posts (id) on delete cascade,
  version integer not null,
  kind blog.revision_kind not null default 'manual',
  title varchar(500),
  body supasheet.RICH_TEXT,
  change_summary varchar(500),
  word_count integer not null default 0,
  editor_id uuid references blog.authors (id) on delete set null,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  unique (post_id, version)
);

comment on column blog.post_revisions.kind is '{
    "progress": false,
    "values": {
        "autosave": {"variant": "secondary", "icon": "Save"},
        "manual": {"variant": "info", "icon": "PenLine"},
        "editorial": {"variant": "warning", "icon": "SquarePen"}
    }
}';

comment on table blog.post_revisions is '{
    "icon": "GitCompare",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "revision", "title": "Revision", "fields": ["post_id", "kind", "change_summary"]},
            {"id": "content", "title": "Content", "fields": ["title", "body"]},
            {"id": "meta", "title": "Meta", "fields": {"read": ["version", "word_count", "editor_id"]}}
        ]
    },
    "query": {
        "sort": [{"id": "version", "desc": true}],
        "join": [
            {"table": "posts", "on": "post_id", "columns": ["reference", "title", "status"]},
            {"table": "authors", "on": "editor_id", "alias": "revision_editor", "columns": ["display_name", "avatar"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column blog.post_revisions.word_count is '{"name": "Words", "aggregate": "max"}';

revoke all on table blog.post_revisions
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
delete on table blog.post_revisions to "x-admin";

grant
select
,
  insert on table blog.post_revisions to "editor",
  "author";

create index idx_blog_post_revisions_post_id on blog.post_revisions (post_id);

create index idx_blog_post_revisions_editor_id on blog.post_revisions (editor_id);

create index idx_blog_post_revisions_created_at on blog.post_revisions (created_at desc);

alter table blog.post_revisions enable row level security;

create policy post_revisions_select on blog.post_revisions for
select
  to authenticated using (true);

create policy post_revisions_insert on blog.post_revisions for insert to authenticated
with
  check (true);

create policy post_revisions_update on blog.post_revisions
for update
  to authenticated using (true)
with
  check (true);

create policy post_revisions_delete on blog.post_revisions for delete to authenticated using (true);

----------------------------------------------------------------
-- Post events (system-generated activity timeline for a single
-- post — display: none, never browsable on its own; surfaced only
-- as the "post_events" timeline tab on that post's detail page)
----------------------------------------------------------------
create table blog.post_events (
  id uuid primary key default extensions.uuid_generate_v4 (),
  post_id uuid not null references blog.posts (id) on delete cascade,
  event_type blog.post_event_type not null,
  title varchar(255) not null,
  metadata jsonb,
  actor_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  occurred_at timestamptz not null default current_timestamp
);

comment on column blog.post_events.event_type is '{
    "progress": false,
    "values": {
        "created": {"variant": "info", "icon": "Sparkles"},
        "status_changed": {"variant": "default", "icon": "ArrowRightLeft"},
        "assigned": {"variant": "secondary", "icon": "UserCog"},
        "scheduled": {"variant": "info", "icon": "CalendarClock"},
        "published": {"variant": "success", "icon": "Globe"},
        "revision_added": {"variant": "warning", "icon": "GitCommitHorizontal"},
        "comment_added": {"variant": "default", "icon": "MessageCircle"},
        "record_updated": {"variant": "secondary", "icon": "RefreshCw"}
    }
}';

comment on table blog.post_events is '{
    "icon": "History",
    "display": "none",
    "fields": {
        "sections": [
            {"id": "event", "title": "Event", "fields": ["post_id", "event_type", "title", "metadata", "actor_id", "occurred_at"]}
        ]
    },
    "query": {
        "sort": [{"id": "occurred_at", "desc": true}],
        "join": [{"table": "users", "on": "actor_id", "alias": "actor", "columns": ["name", "email"]}]
    }
}';

revoke all on table blog.post_events
from
  public,
  anon,
  authenticated,
  service_role;

-- Select only — the feed is read-only by design (granting insert
-- would add a "New entry" button above the timeline).
grant
select
  on table blog.post_events to "x-admin",
  "editor",
  "author";

create index idx_blog_post_events_post_id on blog.post_events (post_id);

create index idx_blog_post_events_occurred_at on blog.post_events (occurred_at desc);

alter table blog.post_events enable row level security;

create policy post_events_select on blog.post_events for
select
  to authenticated using (true);

----------------------------------------------------------------
-- Post comments (threaded reader discussion with a moderation
-- queue — kanban by status, tree by thread)
----------------------------------------------------------------
create table blog.post_comments (
  id uuid primary key default extensions.uuid_generate_v4 (),
  post_id uuid not null references blog.posts (id) on delete cascade,
  parent_id uuid references blog.post_comments (id) on delete cascade,
  author_name varchar(255) not null,
  author_email supasheet.EMAIL,
  author_website supasheet.URL,
  body text not null,
  status blog.comment_status not null default 'pending',
  rejection_reason varchar(500),
  is_pinned boolean not null default false,
  like_count integer not null default 0,
  reported_count integer not null default 0,
  moderated_by_id uuid references blog.authors (id) on delete set null,
  moderated_at timestamptz,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column blog.post_comments.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "warning", "icon": "Hourglass"},
        "approved": {"variant": "success", "icon": "CircleCheck"},
        "spam": {"variant": "destructive", "icon": "ShieldAlert"},
        "rejected": {"variant": "secondary", "icon": "CircleX"}
    }
}';

comment on table blog.post_comments is '{
    "icon": "MessagesSquare",
    "name": "Comments",
    "collapsible_group": "Engagement",
    "display": "block",
    "primary_view": "kanban",
    "inline_form": true,
    "detail": {
        "header": {"title": "author_name", "badges": ["status", "is_pinned"]},
        "tabs": ["post_comments"]
    },
    "views": [
        {
            "id": "kanban",
            "name": "Moderation Queue",
            "type": "kanban",
            "group": "status",
            "title": "author_name",
            "description": "body",
            "date": "created_at",
            "badge": "status"
        },
        {
            "id": "tree",
            "name": "Threads",
            "type": "tree",
            "parent": "parent_id",
            "title": "author_name",
            "secondary": "body"
        },
        {
            "id": "list",
            "name": "All Comments",
            "type": "list",
            "title": "author_name",
            "description": "body",
            "field_1": "status",
            "field_2": "created_at"
        }
    ],
    "filter_presets": [
        {"id": "pending", "name": "Awaiting Moderation", "filters": [{"id": "status", "value": "pending", "operator": "eq"}]},
        {"id": "reported", "name": "Reported", "filters": [{"id": "reported_count", "value": "0", "operator": "gt"}]},
        {"id": "spam", "name": "Spam", "filters": [{"id": "status", "value": "spam", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["post_id", "author_name", "body"],
        "sections": [
            {"id": "comment", "title": "Comment", "fields": ["post_id", "parent_id", "body"]},
            {"id": "commenter", "title": "Commenter", "fields": ["author_name", "author_email", "author_website"]},
            {"id": "moderation", "title": "Moderation", "fields": ["status", "rejection_reason", "is_pinned"]},
            {"id": "audit", "title": "Moderation trail", "fields": {"read": ["moderated_by_id", "moderated_at", "like_count", "reported_count"]}}
        ],
        "behavior": {
            "rejection_reason": {
                "visible": [{"id": "status", "operator": "in", "value": ["rejected", "spam"]}],
                "required": [{"id": "status", "operator": "eq", "value": "rejected"}]
            },
            "is_pinned": {"visible": [{"id": "status", "operator": "eq", "value": "approved"}]}
        },
        "lookups": {
            "parent_id": {"filter": [{"source_column": "post_id", "target_column": "post_id"}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "posts", "on": "post_id", "columns": ["reference", "title", "status"]},
            {"table": "authors", "on": "moderated_by_id", "alias": "moderator", "columns": ["display_name", "avatar"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column blog.post_comments.like_count is '{"aggregate": "sum"}';

comment on column blog.post_comments.reported_count is '{"name": "Reports", "aggregate": "sum"}';

revoke all on table blog.post_comments
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
delete on table blog.post_comments to "x-admin";

grant
select
,
  insert,
update on table blog.post_comments to "editor";

grant
select
  on table blog.post_comments to "author";

grant
select
,
  insert on table blog.post_comments to "user";

create index idx_blog_post_comments_post_id on blog.post_comments (post_id);

create index idx_blog_post_comments_parent_id on blog.post_comments (parent_id);

create index idx_blog_post_comments_status on blog.post_comments (status);

create index idx_blog_post_comments_user_id on blog.post_comments (user_id);

create index idx_blog_post_comments_created_at on blog.post_comments (created_at desc);

alter table blog.post_comments enable row level security;

-- Readers see the approved thread plus whatever they wrote
-- themselves; the desk sees the full moderation queue.
create policy post_comments_select on blog.post_comments for
select
  to authenticated using (
    status = 'approved'
    or user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'editor', 'member')
    or pg_has_role(current_user, 'author', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  );

create policy post_comments_insert on blog.post_comments for insert to authenticated
with
  check (true);

create policy post_comments_update on blog.post_comments
for update
  to authenticated using (true)
with
  check (true);

create policy post_comments_delete on blog.post_comments for delete to authenticated using (true);

----------------------------------------------------------------
-- Post metrics (one traffic row per post per day — the source the
-- posts rollups and the traffic charts read from)
----------------------------------------------------------------
create table blog.post_metrics_daily (
  id uuid primary key default extensions.uuid_generate_v4 (),
  post_id uuid not null references blog.posts (id) on delete cascade,
  day date not null default current_date,
  views integer not null default 0,
  unique_visitors integer not null default 0,
  reads integer not null default 0,
  average_time supasheet.DURATION not null default 0,
  referrer varchar(255),
  subscriber_signups integer not null default 0,
  created_at timestamptz default current_timestamp,
  unique (post_id, day)
);

comment on table blog.post_metrics_daily is '{
    "icon": "ChartNoAxesColumn",
    "name": "Traffic",
    "inline_form": true,
    "display": "none",
    "fields": {
        "sections": [
            {"id": "period", "title": "Period", "fields": ["post_id", "day", "referrer"]},
            {"id": "traffic", "title": "Traffic", "fields": ["views", "unique_visitors", "reads", "average_time", "subscriber_signups"]}
        ]
    },
    "query": {
        "sort": [{"id": "day", "desc": true}],
        "join": [{"table": "posts", "on": "post_id", "columns": ["reference", "title", "status"]}]
    }
}';

comment on column blog.post_metrics_daily.views is '{"aggregate": "sum"}';

comment on column blog.post_metrics_daily.unique_visitors is '{"name": "Visitors", "aggregate": "sum"}';

comment on column blog.post_metrics_daily.reads is '{"aggregate": "sum"}';

comment on column blog.post_metrics_daily.average_time is '{"name": "Avg Time", "aggregate": "avg"}';

revoke all on table blog.post_metrics_daily
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
delete on table blog.post_metrics_daily to "x-admin";

grant
select
,
  insert,
update on table blog.post_metrics_daily to "editor";

grant
select
  on table blog.post_metrics_daily to "author";

create index idx_blog_post_metrics_daily_post_id on blog.post_metrics_daily (post_id);

create index idx_blog_post_metrics_daily_day on blog.post_metrics_daily (day desc);

alter table blog.post_metrics_daily enable row level security;

create policy post_metrics_daily_select on blog.post_metrics_daily for
select
  to authenticated using (true);

create policy post_metrics_daily_insert on blog.post_metrics_daily for insert to authenticated
with
  check (true);

create policy post_metrics_daily_update on blog.post_metrics_daily
for update
  to authenticated using (true)
with
  check (true);

create policy post_metrics_daily_delete on blog.post_metrics_daily for delete to authenticated using (true);

----------------------------------------------------------------
-- Subscribers (the newsletter list)
----------------------------------------------------------------
create table blog.subscribers (
  id uuid primary key default extensions.uuid_generate_v4 (),
  email supasheet.EMAIL not null unique,
  name varchar(255),
  status blog.subscriber_status not null default 'pending',
  plan blog.subscriber_plan not null default 'free',
  source blog.subscriber_source not null default 'organic',
  referred_by_post_id uuid references blog.posts (id) on delete set null,
  country varchar(255),
  interests varchar(500) [],
  subscribed_at timestamptz,
  unsubscribed_at timestamptz,
  last_opened_at timestamptz,
  open_count integer not null default 0,
  click_count integer not null default 0,
  lifetime_value numeric(10, 2) not null default 0,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column blog.subscribers.status is '{
    "progress": true,
    "values": {
        "pending": {"variant": "warning", "icon": "MailQuestion"},
        "subscribed": {"variant": "success", "icon": "MailCheck"},
        "unsubscribed": {"variant": "secondary", "icon": "MailX"},
        "bounced": {"variant": "destructive", "icon": "MailWarning"}
    }
}';

comment on column blog.subscribers.plan is '{
    "progress": true,
    "values": {
        "free": {"variant": "secondary", "icon": "Gift"},
        "member": {"variant": "info", "icon": "Users"},
        "paid": {"variant": "success", "icon": "CreditCard"}
    }
}';

comment on table blog.subscribers is '{
    "icon": "Mails",
    "collapsible_group": "Audience",
    "display": "block",
    "primary_view": "list",
    "detail": {"header": {"title": "email", "badges": ["status", "plan"]}},
    "views": [
        {
            "id": "list",
            "name": "Mailing List",
            "type": "list",
            "title": "email",
            "description": "name",
            "field_1": "plan",
            "field_2": "status"
        },
        {
            "id": "kanban",
            "name": "By Plan",
            "type": "kanban",
            "group": "plan",
            "title": "email",
            "description": "name",
            "date": "subscribed_at",
            "badge": "status"
        }
    ],
    "filter_presets": [
        {"id": "subscribed", "name": "Subscribed", "filters": [{"id": "status", "value": "subscribed", "operator": "eq"}]},
        {"id": "paying", "name": "Paying", "filters": [{"id": "plan", "value": ["member", "paid"], "operator": "in"}]},
        {"id": "bounced", "name": "Bounced", "filters": [{"id": "status", "value": "bounced", "operator": "eq"}]}
    ],
    "fields": {
        "quick_create": ["email", "name", "plan"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["email", "name", "country"]},
            {"id": "subscription", "title": "Subscription", "fields": ["status", "plan", "source", "referred_by_post_id", "interests"]},
            {"id": "lifecycle", "title": "Lifecycle", "fields": {"update": ["subscribed_at", "unsubscribed_at"], "read": ["subscribed_at", "unsubscribed_at", "last_opened_at"]}},
            {"id": "engagement", "title": "Engagement", "fields": {"read": ["open_count", "click_count", "lifetime_value"]}}
        ],
        "behavior": {
            "unsubscribed_at": {"visible": [{"id": "status", "operator": "eq", "value": "unsubscribed"}]},
            "referred_by_post_id": {"visible": [{"id": "source", "operator": "eq", "value": "post"}]}
        }
    },
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [
            {"table": "posts", "on": "referred_by_post_id", "alias": "referrer_post", "columns": ["reference", "title"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';

comment on column blog.subscribers.lifetime_value is '{"name": "LTV", "aggregate": "sum"}';

comment on column blog.subscribers.open_count is '{"aggregate": "sum"}';

revoke all on table blog.subscribers
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
delete on table blog.subscribers to "x-admin";

grant
select
,
  insert,
update on table blog.subscribers to "editor";

-- A reader can sign themselves up and see their own row only.
grant
select
,
  insert on table blog.subscribers to "user";

create index idx_blog_subscribers_status on blog.subscribers (status);

create index idx_blog_subscribers_plan on blog.subscribers (plan);

create index idx_blog_subscribers_referred_by_post_id on blog.subscribers (referred_by_post_id);

create index idx_blog_subscribers_user_id on blog.subscribers (user_id);

create index idx_blog_subscribers_created_at on blog.subscribers (created_at desc);

alter table blog.subscribers enable row level security;

create policy subscribers_select on blog.subscribers for
select
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'editor', 'member')
    or pg_has_role(current_user, 'x-admin', 'member')
  );

create policy subscribers_insert on blog.subscribers for insert to authenticated
with
  check (true);

create policy subscribers_update on blog.subscribers
for update
  to authenticated using (true)
with
  check (true);

create policy subscribers_delete on blog.subscribers for delete to authenticated using (true);

----------------------------------------------------------------
-- Newsletter issues (what actually lands in the inbox)
----------------------------------------------------------------
create table blog.newsletter_issues (
  id uuid primary key default extensions.uuid_generate_v4 (),
  title varchar(255) not null,
  subject varchar(255) not null,
  preview_text varchar(255),
  body supasheet.RICH_TEXT,
  status blog.newsletter_status not null default 'draft',
  audience blog.subscriber_plan not null default 'free',
  featured_post_id uuid references blog.posts (id) on delete set null,
  author_id uuid references blog.authors (id) on delete set null,
  scheduled_for timestamptz,
  sent_at timestamptz,
  recipient_count integer not null default 0,
  open_rate supasheet.PERCENTAGE,
  click_rate supasheet.PERCENTAGE,
  unsubscribe_count integer not null default 0,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on column blog.newsletter_issues.status is '{
    "progress": true,
    "values": {
        "draft": {"variant": "secondary", "icon": "FilePen"},
        "scheduled": {"variant": "info", "icon": "CalendarClock"},
        "sending": {"variant": "warning", "icon": "Send"},
        "sent": {"variant": "success", "icon": "MailCheck"},
        "cancelled": {"variant": "destructive", "icon": "CircleX"}
    }
}';

comment on table blog.newsletter_issues is '{
    "icon": "Mail",
    "name": "Newsletter",
    "collapsible_group": "Audience",
    "display": "block",
    "primary_view": "calendar",
    "detail": {"header": {"title": "title", "badges": ["status", "audience"]}},
    "views": [
        {
            "id": "calendar",
            "name": "Send Calendar",
            "type": "calendar",
            "title": "title",
            "badge": "status",
            "start_date": "scheduled_for",
            "end_date": "sent_at"
        },
        {
            "id": "kanban",
            "name": "Pipeline",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "subject",
            "date": "scheduled_for",
            "badge": "audience"
        },
        {
            "id": "list",
            "name": "All Issues",
            "type": "list",
            "title": "title",
            "description": "subject",
            "field_1": "status",
            "field_2": "sent_at"
        }
    ],
    "filter_presets": [
        {"id": "scheduled", "name": "Scheduled", "filters": [{"id": "status", "value": "scheduled", "operator": "eq"}]},
        {"id": "sent", "name": "Sent", "filters": [{"id": "status", "value": "sent", "operator": "eq"}]}
    ],
    "links": [
        {"id": "newsletter_report", "name": "Newsletter Performance", "url": "/blog/report/newsletter_report", "icon": "Activity", "description": "Reach, opens and clicks per issue"}
    ],
    "fields": {
        "quick_create": ["title", "subject", "audience"],
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["title", "subject", "preview_text"]},
            {"id": "content", "title": "Content", "fields": ["body", "featured_post_id"]},
            {"id": "send", "title": "Send", "fields": ["status", "audience", "author_id", "scheduled_for"]},
            {"id": "results", "title": "Results", "fields": {"read": ["sent_at", "recipient_count", "open_rate", "click_rate", "unsubscribe_count"]}}
        ],
        "behavior": {
            "scheduled_for": {
                "visible": [{"id": "status", "operator": "in", "value": ["scheduled", "sending", "sent"]}],
                "required": [{"id": "status", "operator": "eq", "value": "scheduled"}]
            }
        },
        "lookups": {
            "featured_post_id": {"fill": [{"source_column": "preview_text", "target_column": "excerpt"}]}
        }
    },
    "query": {
        "sort": [{"id": "scheduled_for", "desc": true}],
        "join": [
            {"table": "posts", "on": "featured_post_id", "alias": "featured_post", "columns": ["reference", "title"]},
            {"table": "authors", "on": "author_id", "alias": "sender", "columns": ["display_name", "avatar"]}
        ]
    }
}';

comment on column blog.newsletter_issues.recipient_count is '{"name": "Recipients", "aggregate": "sum"}';

comment on column blog.newsletter_issues.open_rate is '{"name": "Open Rate", "aggregate": "avg"}';

comment on column blog.newsletter_issues.click_rate is '{"name": "Click Rate", "aggregate": "avg"}';

revoke all on table blog.newsletter_issues
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
delete on table blog.newsletter_issues to "x-admin";

grant
select
,
  insert,
update on table blog.newsletter_issues to "editor";

grant
select
  on table blog.newsletter_issues to "author";

create index idx_blog_newsletter_issues_status on blog.newsletter_issues (status);

create index idx_blog_newsletter_issues_featured_post_id on blog.newsletter_issues (featured_post_id);

create index idx_blog_newsletter_issues_author_id on blog.newsletter_issues (author_id);

create index idx_blog_newsletter_issues_scheduled_for on blog.newsletter_issues (scheduled_for desc);

alter table blog.newsletter_issues enable row level security;

create policy newsletter_issues_select on blog.newsletter_issues for
select
  to authenticated using (true);

create policy newsletter_issues_insert on blog.newsletter_issues for insert to authenticated
with
  check (true);

create policy newsletter_issues_update on blog.newsletter_issues
for update
  to authenticated using (true)
with
  check (true);

create policy newsletter_issues_delete on blog.newsletter_issues for delete to authenticated using (true);

----------------------------------------------------------------
-- Blog settings (singleton — one row only, no delete grant)
----------------------------------------------------------------
create table blog.blog_settings (
  id uuid primary key default extensions.uuid_generate_v4 (),
  blog_name varchar(255) not null default 'Supasheet Blog',
  tagline varchar(255),
  description text,
  logo supasheet.file,
  brand_color supasheet.COLOR default '#6366f1',
  site_url supasheet.URL,
  contact_email supasheet.EMAIL,
  default_category_id uuid references blog.categories (id) on delete set null,
  posts_per_page integer not null default 10,
  comments_enabled boolean not null default true,
  moderation_required boolean not null default true,
  newsletter_enabled boolean not null default true,
  default_visibility blog.post_visibility not null default 'public',
  twitter_url supasheet.URL,
  github_url supasheet.URL,
  footer_text text,
  timezone varchar(100) not null default 'UTC',
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table blog.blog_settings is '{
    "icon": "Settings",
    "name": "Blog Settings",
    "collapsible_group": "Planning",
    "display": "block",
    "singleton": true,
    "fields": {
        "sections": [
            {"id": "identity", "title": "Identity", "fields": ["blog_name", "tagline", "description", "logo", "brand_color"]},
            {"id": "content", "title": "Content", "fields": ["default_category_id", "default_visibility", "posts_per_page", "footer_text"]},
            {"id": "engagement", "title": "Engagement", "fields": ["comments_enabled", "moderation_required", "newsletter_enabled"]},
            {"id": "contact", "title": "Contact & social", "collapsible": true, "fields": ["site_url", "contact_email", "twitter_url", "github_url", "timezone"]}
        ],
        "behavior": {
            "moderation_required": {"visible": [{"id": "comments_enabled", "operator": "eq", "value": "true"}]}
        }
    },
    "query": {
        "join": [{"table": "categories", "on": "default_category_id", "columns": ["name", "slug"]}]
    }
}';

comment on column blog.blog_settings.logo is '{"accept": "image/*", "max_size": 2097152}';

revoke all on table blog.blog_settings
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
update on table blog.blog_settings to "x-admin";

grant
select
  on table blog.blog_settings to "editor",
  "author";

alter table blog.blog_settings enable row level security;

create policy blog_settings_select on blog.blog_settings for
select
  to authenticated using (true);

create policy blog_settings_insert on blog.blog_settings for insert to authenticated
with
  check (true);

create policy blog_settings_update on blog.blog_settings
for update
  to authenticated using (true)
with
  check (true);

----------------------------------------------------------------
-- Business triggers
----------------------------------------------------------------
-- Derive the slug, word count, reading time and lifecycle stamps
-- directly from the post's own state.
create or replace function blog.trg_posts_apply_defaults () returns trigger as $$
declare
    v_slug text;
    v_words integer;
begin
    -- Slug: generated from the title whenever the field is left empty,
    -- de-duplicated with the post's own reference number.
    if new.slug is null or btrim(new.slug) = '' then
        v_slug := btrim(regexp_replace(lower(btrim(new.title)), '[^a-z0-9]+', '-', 'g'), '-');

        if v_slug = '' then
            v_slug := 'post';
        end if;

        v_slug := left(v_slug, 200);

        if exists (
            select 1 from blog.posts p where p.slug = v_slug and p.id <> new.id
        ) then
            v_slug := v_slug || '-' || right(new.reference, 5);
        end if;

        new.slug := v_slug;
    end if;

    -- Effort figures follow the body: ~200 words a minute, stored as
    -- milliseconds because supasheet.DURATION renders "4m" from ms.
    v_words := coalesce(
        array_length(
            regexp_split_to_array(btrim(coalesce(new.body, '')), '\s+'),
            1
        ),
        0
    );

    if btrim(coalesce(new.body, '')) = '' then
        v_words := 0;
    end if;

    new.word_count := v_words;
    new.reading_time := (ceil(v_words / 200.0) * 60000)::bigint;

    if tg_op = 'INSERT' then
        -- An unassigned post inherits its category's section editor.
        if new.editor_id is null and new.category_id is not null then
            select lead_editor_id into new.editor_id
            from blog.categories
            where id = new.category_id;
        end if;

        if new.status = 'published' then
            new.published_at := coalesce(new.published_at, current_timestamp);
        end if;
    else
        if new.status = 'published' and old.status <> 'published' then
            new.published_at := coalesce(new.published_at, current_timestamp);
        end if;

        if new.status = 'archived' and old.status <> 'archived' then
            new.archived_at := coalesce(new.archived_at, current_timestamp);
        end if;

        -- Pulling a live post back into the pipeline clears the stamps.
        if old.status = 'published' and new.status not in ('published', 'archived') then
            new.published_at := null;
        end if;

        if new.status <> 'archived' then
            new.archived_at := null;
        end if;

        if new.status <> 'in_review' then
            new.review_notes := null;
        end if;
    end if;

    -- Everything that went out has a slot on the publishing calendar,
    -- even when it was published straight from a draft.
    if new.status in ('published', 'archived') then
        new.scheduled_for := coalesce(new.scheduled_for, new.published_at);
    end if;

    if new.series_id is null then
        new.series_part := null;
    end if;

    new.updated_at := current_timestamp;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger posts_apply_defaults
before insert or update on blog.posts for each row
execute function blog.trg_posts_apply_defaults ();

-- Timeline: one event per meaningful editorial change. Scoped to the
-- workflow columns so the traffic and comment rollups below never
-- flood the feed.
create or replace function blog.trg_posts_log_event () returns trigger as $$
begin
    if tg_op = 'INSERT' then
        insert into blog.post_events (post_id, event_type, title, metadata, actor_id)
        values (
            new.id,
            'created',
            'Post ' || new.reference || ' created',
            jsonb_build_object('post_type', new.post_type, 'status', new.status),
            new.user_id
        );
        return new;
    end if;

    if new.status = 'published' and old.status <> 'published' then
        insert into blog.post_events (post_id, event_type, title, metadata)
        values (
            new.id,
            'published',
            'Published: ' || new.title,
            jsonb_build_object('published_at', new.published_at, 'visibility', new.visibility)
        );
    elsif new.status = 'scheduled' and old.status <> 'scheduled' then
        insert into blog.post_events (post_id, event_type, title, metadata)
        values (
            new.id,
            'scheduled',
            'Scheduled for ' || to_char(new.scheduled_for, 'Mon DD, YYYY HH24:MI'),
            jsonb_build_object('scheduled_for', new.scheduled_for)
        );
    elsif new.status is distinct from old.status then
        insert into blog.post_events (post_id, event_type, title, metadata)
        values (
            new.id,
            'status_changed',
            'Status changed to ' || new.status,
            jsonb_build_object('from', old.status, 'to', new.status)
        );
    elsif new.editor_id is distinct from old.editor_id
       or new.author_id is distinct from old.author_id then
        insert into blog.post_events (post_id, event_type, title, metadata)
        values (
            new.id,
            'assigned',
            'Byline or desk changed',
            jsonb_build_object(
                'author_from', old.author_id, 'author_to', new.author_id,
                'editor_from', old.editor_id, 'editor_to', new.editor_id
            )
        );
    else
        insert into blog.post_events (post_id, event_type, title)
        values (new.id, 'record_updated', 'Post updated');
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger posts_log_event
after insert or update of status,
author_id,
editor_id,
scheduled_for,
published_at,
is_featured on blog.posts for each row
execute function blog.trg_posts_log_event ();

-- Keep every parent rollup that hangs off a post in sync: the part
-- counter on its series, the delivery counter and progress bar on its
-- campaign, and the reader rating on its byline.
create or replace function blog.trg_posts_rollup_parents () returns trigger as $$
declare
    v_series uuid[] := '{}';
    v_campaigns uuid[] := '{}';
    v_authors uuid[] := '{}';
    v_id uuid;
begin
    -- OLD is only populated on UPDATE/DELETE, NEW only on INSERT/UPDATE:
    -- collect both sides so a moved post decrements its old parent and
    -- increments the new one in the same statement.
    if tg_op <> 'INSERT' then
        v_series := v_series || old.series_id;
        v_campaigns := v_campaigns || old.campaign_id;
        v_authors := v_authors || old.author_id;
    end if;

    if tg_op <> 'DELETE' then
        v_series := v_series || new.series_id;
        v_campaigns := v_campaigns || new.campaign_id;
        v_authors := v_authors || new.author_id;
    end if;

    v_series := array_remove(v_series, null);
    v_campaigns := array_remove(v_campaigns, null);
    v_authors := array_remove(v_authors, null);

    foreach v_id in array v_series loop
        update blog.series s
        set published_parts = (
            select count(*)
            from blog.posts p
            where p.series_id = v_id and p.status = 'published'
        )
        where s.id = v_id;
    end loop;

    foreach v_id in array v_campaigns loop
        update blog.content_campaigns c
        set published_posts = sub.published,
            progress = least(
                100,
                round(100.0 * sub.published / greatest(c.target_posts, 1))
            )::real
        from (
            select count(*) filter (where p.status = 'published') as published
            from blog.posts p
            where p.campaign_id = v_id
        ) as sub
        where c.id = v_id;
    end loop;

    foreach v_id in array v_authors loop
        update blog.authors a
        set average_rating = (
            select round(avg(p.average_rating)::numeric, 2)
            from blog.posts p
            where p.author_id = v_id
              and p.status = 'published'
              and p.average_rating is not null
        )
        where a.id = v_id;
    end loop;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger posts_rollup_parents
after insert or update of status,
series_id,
campaign_id,
author_id,
average_rating or delete on blog.posts for each row
execute function blog.trg_posts_rollup_parents ();

-- Revisions number themselves per post and carry their own word count.
create or replace function blog.trg_post_revisions_before () returns trigger as $$
begin
    if new.version is null or new.version = 0 then
        select coalesce(max(version), 0) + 1 into new.version
        from blog.post_revisions
        where post_id = new.post_id;
    end if;

    if new.word_count = 0 and btrim(coalesce(new.body, '')) <> '' then
        new.word_count := coalesce(
            array_length(regexp_split_to_array(btrim(new.body), '\s+'), 1),
            0
        );
    end if;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger post_revisions_before
before insert on blog.post_revisions for each row
execute function blog.trg_post_revisions_before ();

-- A new revision bumps the parent counter and lands on the timeline.
create or replace function blog.trg_post_revisions_after () returns trigger as $$
begin
    update blog.posts
    set revision_count = (
        select count(*) from blog.post_revisions where post_id = new.post_id
    )
    where id = new.post_id;

    insert into blog.post_events (post_id, event_type, title, metadata, actor_id)
    values (
        new.post_id,
        'revision_added',
        'Revision v' || new.version || ' saved',
        jsonb_build_object(
            'version', new.version,
            'kind', new.kind,
            'summary', new.change_summary,
            'word_count', new.word_count
        ),
        new.user_id
    );

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger post_revisions_after
after insert on blog.post_revisions for each row
execute function blog.trg_post_revisions_after ();

-- Moderation stamps: auto-approve when the blog is configured to skip
-- moderation, and record who cleared everything else.
create or replace function blog.trg_post_comments_before () returns trigger as $$
declare
    v_moderation_required boolean;
begin
    if tg_op = 'INSERT' then
        select moderation_required into v_moderation_required
        from blog.blog_settings
        order by created_at asc
        limit 1;

        if coalesce(v_moderation_required, true) = false then
            new.status := 'approved';
        end if;
    end if;

    if new.status <> 'pending' and (tg_op = 'INSERT' or new.status is distinct from old.status) then
        new.moderated_at := coalesce(new.moderated_at, current_timestamp);

        if new.moderated_by_id is null then
            select id into new.moderated_by_id
            from blog.authors
            where user_id = auth.uid ()
            limit 1;
        end if;
    end if;

    if new.status <> 'rejected' and new.status <> 'spam' then
        new.rejection_reason := null;
    end if;

    new.updated_at := current_timestamp;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger post_comments_before
before insert or update on blog.post_comments for each row
execute function blog.trg_post_comments_before ();

-- Only approved comments count towards the post's public counter.
create or replace function blog.trg_post_comments_rollup () returns trigger as $$
declare
    v_post_id uuid := coalesce(new.post_id, old.post_id);
begin
    update blog.posts
    set comment_count = (
        select count(*)
        from blog.post_comments
        where post_id = v_post_id and status = 'approved'
    )
    where id = v_post_id;

    if tg_op = 'INSERT' then
        insert into blog.post_events (post_id, event_type, title, metadata, actor_id)
        values (
            v_post_id,
            'comment_added',
            'Comment from ' || new.author_name,
            jsonb_build_object('comment_id', new.id, 'status', new.status),
            new.user_id
        );
    end if;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger post_comments_rollup
after insert or update or delete on blog.post_comments for each row
execute function blog.trg_post_comments_rollup ();

-- Traffic rollup: the post carries the totals its daily rows add up to.
create or replace function blog.trg_post_metrics_rollup () returns trigger as $$
declare
    v_post_id uuid := coalesce(new.post_id, old.post_id);
begin
    update blog.posts p
    set view_count = coalesce(sub.views, 0),
        unique_visitor_count = coalesce(sub.visitors, 0),
        completion_rate = case
            when coalesce(sub.views, 0) = 0 then null
            else round(100.0 * coalesce(sub.reads, 0) / sub.views, 1)::real
        end
    from (
        select
            sum(views) as views,
            sum(unique_visitors) as visitors,
            sum(reads) as reads
        from blog.post_metrics_daily
        where post_id = v_post_id
    ) as sub
    where p.id = v_post_id;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger post_metrics_rollup
after insert or update or delete on blog.post_metrics_daily for each row
execute function blog.trg_post_metrics_rollup ();

-- Tag popularity follows the junction table.
create or replace function blog.trg_post_tags_usage () returns trigger as $$
declare
    v_tag_id uuid := coalesce(new.tag_id, old.tag_id);
begin
    update blog.tags
    set usage_count = (
        select count(*) from blog.post_tags where tag_id = v_tag_id
    )
    where id = v_tag_id;

    return coalesce(new, old);
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger post_tags_usage
after insert or delete on blog.post_tags for each row
execute function blog.trg_post_tags_usage ();

-- Sending an issue stamps the send time and freezes the audience size.
create or replace function blog.trg_newsletter_issues_before () returns trigger as $$
begin
    if tg_op = 'UPDATE' and new.status = 'sent' and old.status <> 'sent' then
        new.sent_at := coalesce(new.sent_at, current_timestamp);

        if new.recipient_count = 0 then
            select count(*) into new.recipient_count
            from blog.subscribers
            where status = 'subscribed'
              and (
                new.audience = 'free'
                or (new.audience = 'member' and plan in ('member', 'paid'))
                or (new.audience = 'paid' and plan = 'paid')
              );
        end if;
    end if;

    new.updated_at := current_timestamp;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger newsletter_issues_before
before insert or update on blog.newsletter_issues for each row
execute function blog.trg_newsletter_issues_before ();

-- Subscription lifecycle stamps.
create or replace function blog.trg_subscribers_before () returns trigger as $$
begin
    if new.status = 'subscribed' and (tg_op = 'INSERT' or old.status <> 'subscribed') then
        new.subscribed_at := coalesce(new.subscribed_at, current_timestamp);
        new.unsubscribed_at := null;
    end if;

    if new.status = 'unsubscribed' and (tg_op = 'INSERT' or old.status <> 'unsubscribed') then
        new.unsubscribed_at := coalesce(new.unsubscribed_at, current_timestamp);
    end if;

    new.updated_at := current_timestamp;

    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

create trigger subscribers_before
before insert or update on blog.subscribers for each row
execute function blog.trg_subscribers_before ();

-- Keep updated_at fresh on the remaining editable tables.
create trigger categories_set_updated_at
before update on blog.categories for each row
execute function supasheet.set_updated_at ();

create trigger tags_set_updated_at
before update on blog.tags for each row
execute function supasheet.set_updated_at ();

create trigger authors_set_updated_at
before update on blog.authors for each row
execute function supasheet.set_updated_at ();

create trigger author_billing_set_updated_at
before update on blog.author_billing for each row
execute function supasheet.set_updated_at ();

create trigger series_set_updated_at
before update on blog.series for each row
execute function supasheet.set_updated_at ();

create trigger content_campaigns_set_updated_at
before update on blog.content_campaigns for each row
execute function supasheet.set_updated_at ();

create trigger blog_settings_set_updated_at
before update on blog.blog_settings for each row
execute function supasheet.set_updated_at ();

----------------------------------------------------------------
-- Row action: publish a post
----------------------------------------------------------------
create or replace function blog.publish_post (
  p_id uuid,
  p_published_at timestamptz default null
) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_status blog.post_status;
  v_body text;
begin
  select status, body into v_status, v_body from blog.posts where id = p_id;

  if v_status is null then
    raise exception 'Post not found';
  end if;

  if v_status = 'published' then
    raise exception 'Post is already published';
  end if;

  if btrim(coalesce(v_body, '')) = '' then
    raise exception 'A post needs a body before it can be published';
  end if;

  update blog.posts
  set status = 'published',
      published_at = coalesce(p_published_at, current_timestamp)
  where id = p_id;
end;
$$;

comment on function blog.publish_post (uuid, timestamptz) is '{
    "type": "action",
    "resource": "posts",
    "name": "Publish",
    "description": "Take this post live and stamp its publication time",
    "icon": "Globe",
    "visible": [{"id": "status", "operator": "not.in", "value": ["published", "archived"]}],
    "confirm": {"title": "Publish this post?", "description": "It becomes readable by everyone the visibility setting allows, and subscribers can be notified."},
    "success_message": "Post published"
}';

revoke all on function blog.publish_post (uuid, timestamptz)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.publish_post (uuid, timestamptz) to "x-admin",
"editor";

----------------------------------------------------------------
-- Row action: pull a live post back into the pipeline
----------------------------------------------------------------
create or replace function blog.unpublish_post (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update blog.posts
  set status = 'draft'
  where id = p_id
    and status = 'published';

  if not found then
    raise exception 'Only published posts can be unpublished';
  end if;
end;
$$;

comment on function blog.unpublish_post (uuid) is '{
    "type": "action",
    "resource": "posts",
    "name": "Unpublish",
    "description": "Return a live post to draft for another editing pass",
    "icon": "EyeOff",
    "variant": "secondary",
    "visible": [{"id": "status", "operator": "eq", "value": "published"}],
    "confirm": {"title": "Unpublish this post?", "description": "Readers lose access until it is published again."},
    "success_message": "Post unpublished"
}';

revoke all on function blog.unpublish_post (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.unpublish_post (uuid) to "x-admin",
"editor";

----------------------------------------------------------------
-- Row action: queue a post for a future slot
----------------------------------------------------------------
create or replace function blog.schedule_post (
  p_id uuid,
  p_scheduled_for timestamptz default null
) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_slot timestamptz := coalesce(p_scheduled_for, current_timestamp + interval '1 day');
begin
  if v_slot <= current_timestamp then
    raise exception 'A post can only be scheduled into the future';
  end if;

  update blog.posts
  set status = 'scheduled',
      scheduled_for = v_slot
  where id = p_id
    and status in ('idea', 'draft', 'in_review');

  if not found then
    raise exception 'Only ideas, drafts and posts in review can be scheduled';
  end if;
end;
$$;

comment on function blog.schedule_post (uuid, timestamptz) is '{
    "type": "action",
    "resource": "posts",
    "name": "Schedule",
    "description": "Queue this post for its publication slot",
    "icon": "CalendarClock",
    "visible": [{"id": "status", "operator": "in", "value": ["idea", "draft", "in_review"]}],
    "success_message": "Post scheduled"
}';

revoke all on function blog.schedule_post (uuid, timestamptz)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.schedule_post (uuid, timestamptz) to "x-admin",
"editor";

----------------------------------------------------------------
-- Row action: put a post on the front page
----------------------------------------------------------------
create or replace function blog.feature_post (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update blog.posts
  set is_featured = true
  where id = p_id
    and status = 'published'
    and not is_featured;

  if not found then
    raise exception 'Only published posts that are not already featured can be featured';
  end if;
end;
$$;

comment on function blog.feature_post (uuid) is '{
    "type": "action",
    "resource": "posts",
    "name": "Feature",
    "description": "Pin this post to the front page rail",
    "icon": "Star",
    "visible": [{"id": "is_featured", "operator": "eq", "value": "false"}],
    "success_message": "Post featured"
}';

revoke all on function blog.feature_post (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.feature_post (uuid) to "x-admin",
"editor";

----------------------------------------------------------------
-- Row action: move a post through the pipeline (enum value-picker)
----------------------------------------------------------------
create or replace function blog.set_post_status (p_id uuid, p_status blog.post_status) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update blog.posts set status = p_status where id = p_id;
end;
$$;

comment on function blog.set_post_status (uuid, blog.post_status) is '{
    "type": "action",
    "resource": "posts",
    "name": "Set status",
    "icon": "ArrowRightLeft",
    "action_type": "picker"
}';

revoke all on function blog.set_post_status (uuid, blog.post_status)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.set_post_status (uuid, blog.post_status) to "x-admin",
"editor";

----------------------------------------------------------------
-- Row action: clear a comment for publication
----------------------------------------------------------------
create or replace function blog.approve_comment (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update blog.post_comments
  set status = 'approved'
  where id = p_id
    and status <> 'approved';

  if not found then
    raise exception 'Comment not found or already approved';
  end if;
end;
$$;

comment on function blog.approve_comment (uuid) is '{
    "type": "action",
    "resource": "post_comments",
    "name": "Approve",
    "description": "Publish this comment under the post",
    "icon": "CircleCheck",
    "visible": [{"id": "status", "operator": "neq", "value": "approved"}],
    "success_message": "Comment approved"
}';

revoke all on function blog.approve_comment (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.approve_comment (uuid) to "x-admin",
"editor";

----------------------------------------------------------------
-- Row action: bin a comment as spam
----------------------------------------------------------------
create or replace function blog.mark_comment_spam (
  p_id uuid,
  p_reason varchar default 'Flagged as spam'
) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  update blog.post_comments
  set status = 'spam',
      rejection_reason = p_reason
  where id = p_id
    and status <> 'spam';

  if not found then
    raise exception 'Comment not found or already marked as spam';
  end if;
end;
$$;

comment on function blog.mark_comment_spam (uuid, varchar) is '{
    "type": "action",
    "resource": "post_comments",
    "name": "Mark as spam",
    "description": "Remove this comment from the thread and remember the sender",
    "icon": "ShieldAlert",
    "variant": "destructive",
    "visible": [{"id": "status", "operator": "neq", "value": "spam"}],
    "confirm": {"title": "Mark this comment as spam?", "description": "It disappears from the post immediately."},
    "success_message": "Comment marked as spam"
}';

revoke all on function blog.mark_comment_spam (uuid, varchar)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.mark_comment_spam (uuid, varchar) to "x-admin",
"editor";

----------------------------------------------------------------
-- Row action: send a newsletter issue
----------------------------------------------------------------
create or replace function blog.send_newsletter_issue (p_id uuid) returns void language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_status blog.newsletter_status;
begin
  select status into v_status from blog.newsletter_issues where id = p_id;

  if v_status is null then
    raise exception 'Issue not found';
  end if;

  if v_status in ('sent', 'sending') then
    raise exception 'Issue is already %', v_status;
  end if;

  -- The BEFORE trigger stamps sent_at and freezes the audience size.
  update blog.newsletter_issues
  set status = 'sent'
  where id = p_id;
end;
$$;

comment on function blog.send_newsletter_issue (uuid) is '{
    "type": "action",
    "resource": "newsletter_issues",
    "name": "Send now",
    "description": "Deliver this issue to every subscriber in the selected audience",
    "icon": "Send",
    "visible": [{"id": "status", "operator": "in", "value": ["draft", "scheduled"]}],
    "confirm": {"title": "Send this issue?", "description": "Delivery cannot be undone once it starts."},
    "success_message": "Issue sent"
}';

revoke all on function blog.send_newsletter_issue (uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.send_newsletter_issue (uuid) to "x-admin",
"editor";

----------------------------------------------------------------
-- Custom form: save a revision of a post (listed on the "posts"
-- resource overview). Returns a scalar uuid — the UI toasts and
-- refreshes.
----------------------------------------------------------------
create or replace function blog.submit_post_revision (
  p_post_id uuid,
  p_change_summary varchar,
  p_body text default null,
  p_title varchar default null,
  p_kind blog.revision_kind default 'manual',
  p_editor_id uuid default null,
  p_apply boolean default false
) returns uuid language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_post blog.posts%rowtype;
  v_id uuid;
begin
  select * into v_post from blog.posts where id = p_post_id;

  if v_post.id is null then
    raise exception 'Post not found';
  end if;

  insert into blog.post_revisions (post_id, kind, title, body, change_summary, editor_id)
  values (
    p_post_id,
    p_kind,
    coalesce(p_title, v_post.title),
    coalesce(p_body, v_post.body),
    p_change_summary,
    p_editor_id
  )
  returning id into v_id;

  -- Optionally roll the revision straight onto the live record.
  if p_apply then
    update blog.posts
    set title = coalesce(p_title, title),
        body = coalesce(p_body, body)
    where id = p_post_id;
  end if;

  return v_id;
end;
$$;

comment on function blog.submit_post_revision (
  uuid,
  varchar,
  text,
  varchar,
  blog.revision_kind,
  uuid,
  boolean
) is '{
    "type": "form",
    "resource": "posts",
    "name": "Save revision",
    "description": "Snapshot the current draft with a change note, optionally applying the edit.",
    "icon": "GitCommitHorizontal",
    "success_message": "Revision saved",
    "fields": {
        "sections": [
            {"id": "target", "title": "Post", "fields": ["p_post_id", "p_kind", "p_editor_id"]},
            {"id": "change", "title": "Change", "fields": ["p_change_summary", "p_title", "p_body", "p_apply"]}
        ],
        "relations": {
            "p_post_id": {"table": "posts", "column": "id", "display": ["reference", "title"]},
            "p_editor_id": {"table": "authors", "column": "id", "display": ["display_name", "job_title"]}
        }
    }
}';

revoke all on function blog.submit_post_revision (
  uuid,
  varchar,
  text,
  varchar,
  blog.revision_kind,
  uuid,
  boolean
)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.submit_post_revision (
  uuid,
  varchar,
  text,
  varchar,
  blog.revision_kind,
  uuid,
  boolean
) to "x-admin",
"editor",
"author";

----------------------------------------------------------------
-- Custom form: commission the next part of a series (listed on the
-- "series" resource overview). Returns a single object row via
-- explicit OUT parameters — the UI renders the created record as a
-- detail card.
----------------------------------------------------------------
create or replace function blog.draft_series_part (
  p_series_id uuid,
  p_title varchar,
  p_author_id uuid default null,
  p_post_type blog.post_type default 'article',
  p_scheduled_for timestamptz default null,
  out post_id uuid,
  out reference varchar,
  out title varchar,
  out slug varchar,
  out series_part integer,
  out status blog.post_status,
  out scheduled_for timestamptz
) language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_series blog.series%rowtype;
  v_next_part integer;
  v_post blog.posts%rowtype;
begin
  select * into v_series from blog.series where id = p_series_id;

  if v_series.id is null then
    raise exception 'Series not found';
  end if;

  if v_series.status = 'complete' then
    raise exception 'Series % is already complete', v_series.name;
  end if;

  select coalesce(max(p.series_part), 0) + 1 into v_next_part
  from blog.posts p
  where p.series_id = p_series_id;

  insert into blog.posts (
    title, author_id, editor_id, series_id, series_part,
    post_type, status, scheduled_for
  )
  values (
    p_title,
    coalesce(p_author_id, v_series.curator_id),
    v_series.curator_id,
    p_series_id,
    v_next_part,
    p_post_type,
    case when p_scheduled_for is null then 'draft'::blog.post_status else 'scheduled'::blog.post_status end,
    p_scheduled_for
  )
  returning * into v_post;

  post_id := v_post.id;
  reference := v_post.reference;
  title := v_post.title;
  slug := v_post.slug;
  series_part := v_post.series_part;
  status := v_post.status;
  scheduled_for := v_post.scheduled_for;
end;
$$;

comment on function blog.draft_series_part (uuid, varchar, uuid, blog.post_type, timestamptz) is '{
    "type": "form",
    "resource": "series",
    "name": "Draft next part",
    "description": "Open the next numbered instalment of this series, pre-wired to its curator.",
    "icon": "BookPlus",
    "success_message": "Instalment drafted",
    "fields": {
        "sections": [
            {"id": "series", "title": "Series", "fields": ["p_series_id", "p_author_id"]},
            {"id": "post", "title": "Post", "fields": ["p_title", "p_post_type", "p_scheduled_for"]}
        ],
        "relations": {
            "p_series_id": {"table": "series", "column": "id", "display": ["name", "status"]},
            "p_author_id": {"table": "authors", "column": "id", "display": ["display_name", "job_title"]}
        }
    }
}';

revoke all on function blog.draft_series_part (uuid, varchar, uuid, blog.post_type, timestamptz)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.draft_series_part (uuid, varchar, uuid, blog.post_type, timestamptz) to "x-admin",
"editor";

----------------------------------------------------------------
-- Custom form: hand a departing contributor's unpublished queue to
-- someone else (listed on the "authors" resource overview). Returns
-- setof blog.posts — the UI renders the moved rows as a table.
----------------------------------------------------------------
create or replace function blog.bulk_reassign_posts (p_from_author_id uuid, p_to_author_id uuid) returns setof blog.posts language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_from_author_id = p_to_author_id then
    raise exception 'Source and target contributor must differ';
  end if;

  if not exists (select 1 from blog.authors where id = p_to_author_id and status = 'active') then
    raise exception 'The receiving contributor must be active';
  end if;

  return query
  update blog.posts
  set author_id = p_to_author_id
  where author_id = p_from_author_id
    and status not in ('published', 'archived')
  returning *;
end;
$$;

comment on function blog.bulk_reassign_posts (uuid, uuid) is '{
    "type": "form",
    "resource": "authors",
    "name": "Reassign drafts",
    "description": "Move every unpublished post from one contributor to another.",
    "icon": "ArrowRightLeft",
    "success_message": "Drafts reassigned",
    "fields": {
        "sections": [
            {"id": "handover", "title": "Handover", "fields": ["p_from_author_id", "p_to_author_id"]}
        ],
        "relations": {
            "p_from_author_id": {"table": "authors", "column": "id", "display": ["display_name", "job_title"]},
            "p_to_author_id": {"table": "authors", "column": "id", "display": ["display_name", "job_title"]}
        }
    }
}';

revoke all on function blog.bulk_reassign_posts (uuid, uuid)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.bulk_reassign_posts (uuid, uuid) to "x-admin";

----------------------------------------------------------------
-- Custom form: how a category is performing, contributor by
-- contributor (listed on the "categories" resource overview). Pure
-- computation — no writes. Returns setof rows via an explicit
-- table(...) column list.
----------------------------------------------------------------
create or replace function blog.preview_category_performance (
  p_category_id uuid,
  p_include_unpublished boolean default false
) returns table (
  contributor varchar,
  posts bigint,
  published bigint,
  total_views bigint,
  average_read_through numeric,
  average_rating numeric
) language plpgsql security invoker
set
  search_path = '' as $$
begin
  return query
  select
    a.display_name,
    count(p.id) as posts,
    count(p.id) filter (where p.status = 'published') as published,
    coalesce(sum(p.view_count), 0)::bigint as total_views,
    round(avg(p.completion_rate)::numeric, 1) as average_read_through,
    round(avg(p.average_rating)::numeric, 2) as average_rating
  from blog.authors a
  join blog.posts p
    on p.author_id = a.id
   and p.category_id = p_category_id
   and (p_include_unpublished or p.status = 'published')
  group by a.id, a.display_name
  order by total_views desc, a.display_name;
end;
$$;

comment on function blog.preview_category_performance (uuid, boolean) is '{
    "type": "form",
    "resource": "categories",
    "name": "Preview performance",
    "description": "See output, traffic and reader rating per contributor inside this category.",
    "icon": "Gauge",
    "success_message": "Performance calculated",
    "fields": {
        "sections": [
            {"id": "scope", "title": "Scope", "fields": ["p_category_id", "p_include_unpublished"]}
        ],
        "relations": {
            "p_category_id": {"table": "categories", "column": "id", "display": ["name", "slug"]}
        }
    }
}';

revoke all on function blog.preview_category_performance (uuid, boolean)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function blog.preview_category_performance (uuid, boolean) to "x-admin",
"editor";

----------------------------------------------------------------
-- Templates (bulk insert payloads applied via supasheet.apply_template)
--
--   select supasheet.apply_template('blog', '<template_view>', 'posts');
--
-- Only column names present on BOTH the view and the target table
-- are copied; everything else falls back to the target's defaults.
----------------------------------------------------------------
-- Static: the taxonomy every new blog starts with, ready to stamp
-- onto blog.categories. `apply_template` has no dedupe of its own, so
-- the view filters out slugs that already exist — applying it twice
-- is a no-op instead of a unique-constraint error.
create or replace view blog.default_categories_template
with
  (security_invoker = true) as
select
  t.name,
  t.slug,
  t.description,
  t.sort_order
from
  (
    values
      (
        'News'::varchar(255),
        'news'::varchar(255),
        'Product and company announcements'::text,
        10
      ),
      (
        'Tutorials',
        'tutorials',
        'Step-by-step guides and how-tos',
        20
      ),
      (
        'Engineering',
        'engineering',
        'Deep dives into how things are built',
        30
      ),
      (
        'Interviews',
        'interviews',
        'Conversations with people we learn from',
        40
      ),
      (
        'Changelog',
        'changelog',
        'What shipped, release by release',
        50
      )
  ) as t (name, slug, description, sort_order)
where
  not exists (
    select
      1
    from
      blog.categories c
    where
      c.slug = t.slug
      or c.name = t.name
  );

revoke all on blog.default_categories_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.default_categories_template to "x-admin",
  "editor";

comment on view blog.default_categories_template is '{"type": "template", "name": "Default Categories", "description": "The five categories a fresh blog starts with. Apply to blog.categories, then assign section editors.", "target_table": "categories"}';

-- Dynamic: a refresh draft for every evergreen post that has aged out
-- of date, carrying its original byline and desk.
create or replace view blog.content_refresh_template
with
  (security_invoker = true) as
select
  ('Refresh: ' || p.title)::varchar(500) as title,
  p.author_id,
  p.editor_id,
  p.category_id,
  p.series_id,
  'article'::blog.post_type as post_type,
  'draft'::blog.post_status as status,
  p.visibility,
  (
    'Original published ' || to_char(p.published_at, 'Mon DD, YYYY') || ' — refresh the examples and screenshots.'
  )::varchar(500) as excerpt,
  p.keywords
from
  blog.posts p
where
  p.status = 'published'
  and p.published_at < current_timestamp - interval '12 months'
  and p.view_count > 0;

revoke all on blog.content_refresh_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.content_refresh_template to "x-admin",
  "editor";

comment on view blog.content_refresh_template is '{"type": "template", "name": "Content Refresh Drafts", "description": "A refresh draft for every post older than a year that still draws traffic. Apply to blog.posts.", "target_table": "posts"}';

-- Dynamic: one draft newsletter issue per published post that has not
-- been featured in an issue yet.
create or replace view blog.weekly_digest_template
with
  (security_invoker = true) as
select
  ('Digest: ' || p.title)::varchar(255) as title,
  ('New on the blog — ' || p.title)::varchar(255) as subject,
  left(coalesce(p.excerpt, p.title), 255)::varchar(255) as preview_text,
  p.id as featured_post_id,
  p.author_id,
  'draft'::blog.newsletter_status as status,
  case
    when p.visibility = 'public' then 'free'::blog.subscriber_plan
    else 'member'::blog.subscriber_plan
  end as audience
from
  blog.posts p
where
  p.status = 'published'
  and p.published_at >= current_timestamp - interval '7 days'
  and not exists (
    select
      1
    from
      blog.newsletter_issues n
    where
      n.featured_post_id = p.id
  );

revoke all on blog.weekly_digest_template
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.weekly_digest_template to "x-admin",
  "editor";

comment on view blog.weekly_digest_template is '{"type": "template", "name": "Weekly Digest Issues", "description": "A draft newsletter issue for every post published in the last seven days that has not been mailed yet. Apply to blog.newsletter_issues.", "target_table": "newsletter_issues"}';

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view blog.posts_report
with
  (security_invoker = true) as
select
  p.id,
  p.reference,
  p.title,
  p.slug,
  p.status,
  p.post_type,
  p.visibility,
  c.name as category,
  s.name as series,
  cp.name as campaign,
  a.display_name as author,
  e.display_name as editor,
  p.published_at,
  p.word_count,
  round(p.reading_time / 60000.0, 1) as reading_minutes,
  p.view_count,
  p.unique_visitor_count,
  p.comment_count,
  p.share_count,
  p.completion_rate,
  p.average_rating,
  p.revision_count,
  (
    select
      string_agg(
        t.name,
        ', '
        order by
          t.name
      )
    from
      blog.post_tags pt
      join blog.tags t on t.id = pt.tag_id
    where
      pt.post_id = p.id
  ) as tags,
  p.created_at
from
  blog.posts p
  left join blog.categories c on c.id = p.category_id
  left join blog.series s on s.id = p.series_id
  left join blog.content_campaigns cp on cp.id = p.campaign_id
  left join blog.authors a on a.id = p.author_id
  left join blog.authors e on e.id = p.editor_id;

revoke all on blog.posts_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.posts_report to "x-admin",
  "editor";

-- `template: true` means a Handlebars HTML file has been uploaded to
-- the `report-templates` bucket at the deterministic key
-- `blog/posts_report.hbs` (one template per report). Upload
-- supabase/examples/templates/posts_report.hbs there as-is (as
-- "x-admin") to enable the "Print Report" button on this report.
comment on view blog.posts_report is '{"type": "report", "name": "Post Report", "description": "Every post with byline, taxonomy, traffic and engagement context", "template": true}';

create or replace view blog.authors_report
with
  (security_invoker = true) as
select
  a.id,
  a.display_name as author,
  a.job_title,
  a.level,
  a.status,
  m.display_name as mentor,
  count(p.id) as posts,
  count(p.id) filter (
    where
      p.status = 'published'
  ) as published,
  count(p.id) filter (
    where
      p.status in ('idea', 'draft', 'in_review')
  ) as in_pipeline,
  coalesce(sum(p.view_count), 0) as total_views,
  coalesce(sum(p.comment_count), 0) as total_comments,
  round(avg(p.completion_rate)::numeric, 1) as average_read_through,
  round(avg(p.average_rating)::numeric, 2) as average_rating,
  coalesce(sum(p.word_count), 0) as total_words,
  (
    select
      count(*)
    from
      blog.post_revisions r
    where
      r.editor_id = a.id
  ) as revisions_filed,
  a.monthly_target,
  a.joined_on
from
  blog.authors a
  left join blog.authors m on m.id = a.mentor_id
  left join blog.posts p on p.author_id = a.id
group by
  a.id,
  a.display_name,
  a.job_title,
  a.level,
  a.status,
  m.display_name,
  a.monthly_target,
  a.joined_on;

revoke all on blog.authors_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.authors_report to "x-admin",
  "editor";

comment on view blog.authors_report is '{"type": "report", "name": "Contributor Performance", "description": "Output, traffic, engagement and reader rating per contributor"}';

create or replace view blog.categories_report
with
  (security_invoker = true) as
select
  c.id,
  c.name as category,
  c.slug,
  parent.name as parent_category,
  e.display_name as lead_editor,
  count(p.id) as posts,
  count(p.id) filter (
    where
      p.status = 'published'
  ) as published,
  count(distinct p.author_id) as contributors,
  coalesce(sum(p.view_count), 0) as total_views,
  coalesce(sum(p.comment_count), 0) as total_comments,
  round(avg(p.average_rating)::numeric, 2) as average_rating,
  max(p.published_at) as last_published_at
from
  blog.categories c
  left join blog.categories parent on parent.id = c.parent_id
  left join blog.authors e on e.id = c.lead_editor_id
  left join blog.posts p on p.category_id = c.id
group by
  c.id,
  c.name,
  c.slug,
  parent.name,
  e.display_name;

revoke all on blog.categories_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.categories_report to "x-admin",
  "editor";

comment on view blog.categories_report is '{"type": "report", "name": "Category Report", "description": "Volume, reach and freshness per category"}';

create or replace view blog.engagement_report
with
  (security_invoker = true) as
select
  p.id,
  p.reference,
  p.title,
  p.status,
  a.display_name as author,
  c.name as category,
  p.published_at,
  p.view_count,
  p.unique_visitor_count,
  coalesce(m.reads, 0) as reads,
  p.completion_rate,
  p.comment_count,
  count(cm.id) filter (
    where
      cm.status = 'pending'
  ) as comments_awaiting_moderation,
  p.like_count,
  p.share_count,
  coalesce(m.signups, 0) as subscriber_signups,
  round(p.reading_time / 60000.0, 1) as reading_minutes,
  p.average_rating
from
  blog.posts p
  left join blog.authors a on a.id = p.author_id
  left join blog.categories c on c.id = p.category_id
  left join blog.post_comments cm on cm.post_id = p.id
  left join (
    select
      post_id,
      sum(reads) as reads,
      sum(subscriber_signups) as signups
    from
      blog.post_metrics_daily
    group by
      post_id
  ) m on m.post_id = p.id
where
  p.status in ('published', 'archived')
group by
  p.id,
  p.reference,
  p.title,
  p.status,
  a.display_name,
  c.name,
  m.reads,
  m.signups;

revoke all on blog.engagement_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.engagement_report to "x-admin",
  "editor";

comment on view blog.engagement_report is '{"type": "report", "name": "Engagement Report", "description": "Views, read-through, comments, shares and signups per published post"}';

create or replace view blog.newsletter_report
with
  (security_invoker = true) as
select
  n.id,
  n.title,
  n.subject,
  n.status,
  n.audience,
  s.display_name as sender,
  p.title as featured_post,
  n.scheduled_for,
  n.sent_at,
  n.recipient_count,
  n.open_rate,
  n.click_rate,
  n.unsubscribe_count,
  round(
    100.0 * n.unsubscribe_count / nullif(n.recipient_count, 0),
    2
  ) as churn_rate
from
  blog.newsletter_issues n
  left join blog.authors s on s.id = n.author_id
  left join blog.posts p on p.id = n.featured_post_id;

revoke all on blog.newsletter_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.newsletter_report to "x-admin",
  "editor";

comment on view blog.newsletter_report is '{"type": "report", "name": "Newsletter Performance", "description": "Reach, opens, clicks and churn per issue"}';

----------------------------------------------------------------
-- Materialized view report (precomputed monthly rollup)
--
-- Two different refreshes — don't confuse them:
--   select supasheet.refresh_metadata();            -- the catalog
--   refresh materialized view concurrently
--     blog.post_traffic_rollup;                     -- the data
----------------------------------------------------------------
create materialized view blog.post_traffic_rollup as
select
  to_char(date_trunc('month', p.published_at), 'YYYY-MM') as month,
  count(*) as posts_published,
  count(distinct p.author_id) as contributors,
  coalesce(sum(p.view_count), 0) as views,
  coalesce(sum(p.unique_visitor_count), 0) as visitors,
  coalesce(sum(p.comment_count), 0) as comments,
  coalesce(sum(p.share_count), 0) as shares,
  round(avg(p.completion_rate)::numeric, 1) as average_read_through,
  round(avg(p.average_rating)::numeric, 2) as average_rating,
  round(avg(p.word_count)::numeric, 0) as average_words
from
  blog.posts p
where
  p.published_at is not null
group by
  date_trunc('month', p.published_at)
order by
  date_trunc('month', p.published_at) desc;

-- Unique index is REQUIRED for `refresh ... concurrently`.
create unique index idx_blog_post_traffic_rollup_month on blog.post_traffic_rollup (month);

revoke all on blog.post_traffic_rollup
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.post_traffic_rollup to "x-admin",
  "editor";

comment on materialized view blog.post_traffic_rollup is '{"type": "report", "name": "Monthly Traffic Rollup", "description": "Precomputed monthly publishing volume, reach and engagement figures"}';

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- card_1: live posts
create or replace view blog.published_posts_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'newspaper' as icon,
  'published posts' as label
from
  blog.posts
where
  status = 'published';

revoke all on blog.published_posts_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.published_posts_count to "x-admin",
  "editor";

-- card_2: what is live vs what is still moving
create or replace view blog.pipeline_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'published'
  ) as primary,
  count(*) filter (
    where
      status in ('idea', 'draft', 'in_review', 'scheduled')
  ) as secondary,
  'Published' as primary_label,
  'In Pipeline' as secondary_label
from
  blog.posts;

revoke all on blog.pipeline_split
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.pipeline_split to "x-admin",
  "editor";

-- card_3: how much of the plan actually shipped on time
create or replace view blog.on_time_publishing_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(
    100.0 * count(*) filter (
      where
        published_at <= scheduled_for + interval '1 hour'
    ) / nullif(count(*), 0),
    1
  ) as percent
from
  blog.posts
where
  status = 'published'
  and scheduled_for is not null
  and published_at is not null;

revoke all on blog.on_time_publishing_rate
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.on_time_publishing_rate to "x-admin",
  "editor";

-- card_4: where the desk's work sits across the pipeline
create or replace view blog.editorial_pipeline_progress
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status in ('published', 'archived')
  ) as current,
  count(*) as total,
  json_build_array(
    json_build_object(
      'label',
      'Ideas',
      'value',
      count(*) filter (
        where
          status = 'idea'
      )
    ),
    json_build_object(
      'label',
      'Drafting',
      'value',
      count(*) filter (
        where
          status = 'draft'
      )
    ),
    json_build_object(
      'label',
      'In review',
      'value',
      count(*) filter (
        where
          status = 'in_review'
      )
    ),
    json_build_object(
      'label',
      'Scheduled',
      'value',
      count(*) filter (
        where
          status = 'scheduled'
      )
    ),
    json_build_object(
      'label',
      'Live',
      'value',
      count(*) filter (
        where
          status in ('published', 'archived')
      )
    )
  ) as segments
from
  blog.posts;

revoke all on blog.editorial_pipeline_progress
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.editorial_pipeline_progress to "x-admin",
  "editor";

-- card_5: headline total plus a ranked breakdown of that SAME pool
create or replace view blog.posts_by_type_overview
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'published'
  ) as value,
  'Published Posts' as label,
  'library-big' as icon,
  json_build_array(
    json_build_object(
      'label',
      'Articles',
      'value',
      count(*) filter (
        where
          post_type = 'article'
          and status = 'published'
      ),
      'variant',
      'default'
    ),
    json_build_object(
      'label',
      'Tutorials',
      'value',
      count(*) filter (
        where
          post_type = 'tutorial'
          and status = 'published'
      ),
      'variant',
      'info'
    ),
    json_build_object(
      'label',
      'News',
      'value',
      count(*) filter (
        where
          post_type = 'news'
          and status = 'published'
      ),
      'variant',
      'warning'
    ),
    json_build_object(
      'label',
      'Interviews',
      'value',
      count(*) filter (
        where
          post_type = 'interview'
          and status = 'published'
      ),
      'variant',
      'success'
    ),
    json_build_object(
      'label',
      'Changelog',
      'value',
      count(*) filter (
        where
          post_type = 'changelog'
          and status = 'published'
      ),
      'variant',
      'secondary'
    )
  ) as breakdown
from
  blog.posts;

revoke all on blog.posts_by_type_overview
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.posts_by_type_overview to "x-admin",
  "editor";

-- card_6: full-width metric grid
create or replace view blog.blog_pulse
with
  (security_invoker = true) as
select
  json_build_array(
    json_build_object(
      'label',
      'Published 30d',
      'value',
      count(*) filter (
        where
          published_at >= current_timestamp - interval '30 days'
      ),
      'icon',
      'newspaper'
    ),
    json_build_object(
      'label',
      'Scheduled',
      'value',
      count(*) filter (
        where
          status = 'scheduled'
      ),
      'icon',
      'calendar-clock'
    ),
    json_build_object(
      'label',
      'In review',
      'value',
      count(*) filter (
        where
          status = 'in_review'
      ),
      'icon',
      'eye'
    ),
    json_build_object(
      'label',
      'Views 30d',
      'value',
      (
        select
          coalesce(sum(views), 0)
        from
          blog.post_metrics_daily
        where
          day >= current_date - 30
      ),
      'icon',
      'chart-line'
    ),
    json_build_object(
      'label',
      'Comments to clear',
      'value',
      (
        select
          count(*)
        from
          blog.post_comments
        where
          status = 'pending'
      ),
      'icon',
      'message-circle'
    ),
    json_build_object(
      'label',
      'Subscribers',
      'value',
      (
        select
          count(*)
        from
          blog.subscribers
        where
          status = 'subscribed'
      ),
      'icon',
      'mails'
    )
  ) as metrics
from
  blog.posts;

revoke all on blog.blog_pulse
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.blog_pulse to "x-admin",
  "editor";

-- table_1: latest posts
create or replace view blog.recent_posts
with
  (security_invoker = true) as
select
  p.reference,
  p.title,
  p.status,
  a.display_name as author,
  p.created_at::date as created,
  '/blog/resource/posts/' || p.id || '/detail' as link
from
  blog.posts p
  left join blog.authors a on a.id = p.author_id
order by
  p.created_at desc
limit
  10;

revoke all on blog.recent_posts
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.recent_posts to "x-admin",
  "editor";

-- table_1: what goes out next (pairs with Recent Posts)
create or replace view blog.upcoming_schedule
with
  (security_invoker = true) as
select
  p.title,
  p.post_type,
  a.display_name as author,
  to_char(p.scheduled_for, 'Mon DD, HH24:MI') as slot,
  '/blog/resource/posts/' || p.id || '/detail' as link
from
  blog.posts p
  left join blog.authors a on a.id = p.author_id
where
  p.status = 'scheduled'
  and p.scheduled_for >= current_timestamp
order by
  p.scheduled_for asc
limit
  10;

revoke all on blog.upcoming_schedule
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.upcoming_schedule to "x-admin",
  "editor";

-- table_2: category rollup
create or replace view blog.category_performance
with
  (security_invoker = true) as
select
  c.name as category,
  count(p.id) as posts,
  count(p.id) filter (
    where
      p.status = 'published'
  ) as published,
  coalesce(sum(p.view_count), 0) as views,
  coalesce(sum(p.comment_count), 0) as comments,
  '/blog/resource/categories/' || c.id || '/detail' as link
from
  blog.categories c
  left join blog.posts p on p.category_id = c.id
group by
  c.id,
  c.name
order by
  views desc
limit
  10;

revoke all on blog.category_performance
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.category_performance to "x-admin",
  "editor";

-- list_1: what the desk has to read today
create or replace view blog.posts_awaiting_review
with
  (security_invoker = true) as
select
  p.title,
  coalesce(a.display_name, 'Unassigned') || ' · ' || p.post_type as description,
  'eye' as icon,
  'warning' as variant,
  '/blog/resource/posts/' || p.id || '/detail' as link
from
  blog.posts p
  left join blog.authors a on a.id = p.author_id
where
  p.status = 'in_review'
order by
  p.updated_at asc
limit
  10;

revoke all on blog.posts_awaiting_review
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.posts_awaiting_review to "x-admin",
  "editor";

-- list_2: evergreen posts that have aged out (wider list)
create or replace view blog.stale_posts
with
  (security_invoker = true) as
select
  p.title,
  coalesce(c.name, 'Uncategorised') as description,
  'clock-alert' as icon,
  'destructive' as variant,
  p.view_count as field_1,
  to_char(p.published_at, 'Mon YYYY') as field_2,
  '/blog/resource/posts/' || p.id || '/detail' as link
from
  blog.posts p
  left join blog.categories c on c.id = p.category_id
where
  p.status = 'published'
  and p.published_at < current_timestamp - interval '12 months'
order by
  p.view_count desc
limit
  10;

revoke all on blog.stale_posts
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.stale_posts to "x-admin",
  "editor";

-- list_3: newsroom activity feed (avatar initials derived client-side
-- from `actor`)
create or replace view blog.recent_blog_activity
with
  (security_invoker = true) as
select
  coalesce(u.name, u.email, 'Someone') as actor,
  case e.event_type
    when 'created' then 'started'
    when 'published' then 'published'
    when 'scheduled' then 'scheduled'
    when 'revision_added' then 'revised'
    when 'comment_added' then 'received a comment on'
    when 'assigned' then 'reassigned'
    when 'status_changed' then 'moved'
    else 'updated'
  end as action,
  p.title as entity,
  to_char(e.occurred_at, 'Mon DD, YYYY') as date,
  '/blog/resource/posts/' || p.id || '/detail' as link
from
  blog.post_events e
  join blog.posts p on p.id = e.post_id
  left join blog.users u on u.id = e.actor_id
order by
  e.occurred_at desc
limit
  10;

revoke all on blog.recent_blog_activity
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.recent_blog_activity to "x-admin",
  "editor";

-- list_4: leaderboard of the most-read contributors
create or replace view blog.top_authors
with
  (security_invoker = true) as
select
  a.display_name as name,
  coalesce(sum(p.view_count), 0) as value,
  a.job_title as label,
  '/blog/resource/authors/' || a.id || '/detail' as link
from
  blog.authors a
  join blog.posts p on p.author_id = a.id
where
  p.status = 'published'
group by
  a.id,
  a.display_name,
  a.job_title
order by
  value desc
limit
  10;

revoke all on blog.top_authors
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.top_authors to "x-admin",
  "editor";

-- card_1: moderation queue — shown on the post_comments resource page
create or replace view blog.pending_comments_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'message-circle-warning' as icon,
  'comments awaiting moderation' as label
from
  blog.post_comments
where
  status = 'pending';

revoke all on blog.pending_comments_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.pending_comments_count to "x-admin",
  "editor";

-- card_2: paying vs free list — shown on the subscribers resource page
create or replace view blog.subscriber_plan_split
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      plan in ('member', 'paid')
  ) as primary,
  count(*) filter (
    where
      plan = 'free'
  ) as secondary,
  'Paying' as primary_label,
  'Free' as secondary_label
from
  blog.subscribers
where
  status = 'subscribed';

revoke all on blog.subscriber_plan_split
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.subscriber_plan_split to "x-admin",
  "editor";

-- card_3: inbox performance — shown on the newsletter_issues page
create or replace view blog.newsletter_open_rate
with
  (security_invoker = true) as
select
  count(*) as value,
  round(coalesce(avg(open_rate), 0)::numeric, 1) as percent
from
  blog.newsletter_issues
where
  status = 'sent';

revoke all on blog.newsletter_open_rate
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.newsletter_open_rate to "x-admin",
  "editor";

-- card_1: campaigns in flight — shown on the campaigns resource page
create or replace view blog.active_campaigns_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'megaphone' as icon,
  'active campaigns' as label
from
  blog.content_campaigns
where
  status = 'active';

revoke all on blog.active_campaigns_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.active_campaigns_count to "x-admin",
  "editor";

comment on view blog.published_posts_count is '{"type": "dashboard_widget", "name": "Published Posts", "description": "Everything currently live on the blog", "widget_type": "card_1"}';

comment on view blog.pipeline_split is '{"type": "dashboard_widget", "name": "Pipeline Split", "description": "Published posts vs work still in flight", "widget_type": "card_2"}';

comment on view blog.on_time_publishing_rate is '{"type": "dashboard_widget", "name": "On-Time Publishing", "description": "Share of scheduled posts that went out on their slot", "widget_type": "card_3"}';

comment on view blog.editorial_pipeline_progress is '{"type": "dashboard_widget", "name": "Editorial Pipeline", "description": "Where the desk''s work sits across the pipeline", "widget_type": "card_4"}';

comment on view blog.posts_by_type_overview is '{"type": "dashboard_widget", "name": "Published By Format", "description": "Live posts broken down by format", "widget_type": "card_5"}';

comment on view blog.blog_pulse is '{"type": "dashboard_widget", "name": "Blog Pulse", "description": "Headline publishing and audience metrics at a glance", "widget_type": "card_6"}';

comment on view blog.recent_posts is '{"type": "dashboard_widget", "name": "Recent Posts", "description": "Latest 10 posts filed", "widget_type": "table_1", "resource": "posts", "url": "/blog/resource/posts"}';

comment on view blog.upcoming_schedule is '{"type": "dashboard_widget", "name": "Up Next", "description": "Posts queued for their publication slot", "widget_type": "table_1", "url": "/blog/resource/posts"}';

comment on view blog.category_performance is '{"type": "dashboard_widget", "name": "Category Performance", "description": "Volume, reach and discussion per category", "widget_type": "table_2", "url": "/blog/resource/categories"}';

comment on view blog.posts_awaiting_review is '{"type": "dashboard_widget", "name": "Awaiting Review", "description": "Posts sitting with the desk", "widget_type": "list_1", "url": "/blog/resource/posts"}';

comment on view blog.stale_posts is '{"type": "dashboard_widget", "name": "Ageing Content", "description": "Popular posts that are over a year old", "widget_type": "list_2", "url": "/blog/resource/posts"}';

comment on view blog.recent_blog_activity is '{"type": "dashboard_widget", "name": "Newsroom Activity", "description": "Latest movements across the editorial board", "widget_type": "list_3", "url": "/blog/resource/posts"}';

comment on view blog.top_authors is '{"type": "dashboard_widget", "name": "Most Read", "description": "Contributors ranked by lifetime views", "widget_type": "list_4", "url": "/blog/resource/authors"}';

comment on view blog.pending_comments_count is '{"type": "dashboard_widget", "name": "Awaiting Moderation", "description": "Comments queued for a decision", "widget_type": "card_1", "resource": "post_comments"}';

comment on view blog.subscriber_plan_split is '{"type": "dashboard_widget", "name": "Audience Mix", "description": "Paying members vs free subscribers", "widget_type": "card_2", "resource": "subscribers"}';

comment on view blog.newsletter_open_rate is '{"type": "dashboard_widget", "name": "Average Open Rate", "description": "How the last issues performed in the inbox", "widget_type": "card_3", "resource": "newsletter_issues"}';

comment on view blog.active_campaigns_count is '{"type": "dashboard_widget", "name": "Active Campaigns", "description": "Campaigns currently running", "widget_type": "card_1", "resource": "content_campaigns"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: posts by pipeline status
create or replace view blog.posts_by_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  blog.posts
group by
  status;

revoke all on blog.posts_by_status_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.posts_by_status_pie to "x-admin",
  "editor";

-- Bar: output and reach by category
create or replace view blog.posts_by_category_bar
with
  (security_invoker = true) as
select
  c.name as label,
  count(p.id) as posts,
  count(p.id) filter (
    where
      p.status = 'published'
  ) as published,
  coalesce(sum(p.view_count), 0) as views
from
  blog.categories c
  left join blog.posts p on p.category_id = c.id
group by
  c.id,
  c.name
order by
  posts desc;

revoke all on blog.posts_by_category_bar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.posts_by_category_bar to "x-admin",
  "editor";

-- Line: drafted vs published over the last 14 days
create or replace view blog.publishing_volume_line
with
  (security_invoker = true) as
  -- Scalar subqueries rather than two joins: joining posts twice would
  -- multiply drafted rows by published rows on the same day.
select
  to_char(d.day, 'Mon DD') as date,
  (
    select
      count(*)
    from
      blog.posts p
    where
      date_trunc('day', p.created_at) = d.day
  ) as drafted,
  (
    select
      count(*)
    from
      blog.posts p
    where
      date_trunc('day', p.published_at) = d.day
  ) as published
from
  generate_series(current_date - 13, current_date, interval '1 day') as d (day)
order by
  d.day;

revoke all on blog.publishing_volume_line
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.publishing_volume_line to "x-admin",
  "editor";

-- Area: weekly traffic composition over the last 8 weeks
create or replace view blog.traffic_composition_area
with
  (security_invoker = true) as
select
  to_char(date_trunc('week', m.day), 'Mon DD') as date,
  coalesce(sum(m.views), 0) as views,
  coalesce(sum(m.unique_visitors), 0) as visitors,
  coalesce(sum(m.reads), 0) as reads
from
  blog.post_metrics_daily m
where
  m.day >= current_date - 56
group by
  date_trunc('week', m.day)
order by
  date_trunc('week', m.day);

revoke all on blog.traffic_composition_area
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.traffic_composition_area to "x-admin",
  "editor";

-- Radar: output profile per contributor
create or replace view blog.author_scorecard_radar
with
  (security_invoker = true) as
select
  a.display_name as metric,
  count(p.id) as posts,
  count(p.id) filter (
    where
      p.status = 'published'
  ) as published,
  coalesce(round(avg(p.average_rating)::numeric, 2), 0) as rating
from
  blog.authors a
  left join blog.posts p on p.author_id = a.id
where
  a.status = 'active'
group by
  a.id,
  a.display_name
order by
  posts desc;

revoke all on blog.author_scorecard_radar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.author_scorecard_radar to "x-admin",
  "editor";

-- Pie: published posts by format — shown on the posts resource page
create or replace view blog.posts_by_type_pie
with
  (security_invoker = true) as
select
  post_type::text as label,
  count(*) as value
from
  blog.posts
where
  status = 'published'
group by
  post_type;

revoke all on blog.posts_by_type_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.posts_by_type_pie to "x-admin",
  "editor";

-- Pie: audience by plan — shown on the subscribers resource page
create or replace view blog.subscribers_by_plan_pie
with
  (security_invoker = true) as
select
  plan::text as label,
  count(*) as value
from
  blog.subscribers
where
  status = 'subscribed'
group by
  plan;

revoke all on blog.subscribers_by_plan_pie
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.subscribers_by_plan_pie to "x-admin",
  "editor";

-- Bar: moderation outcomes — shown on the comments resource page
create or replace view blog.comments_by_status_bar
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as comments,
  coalesce(sum(like_count), 0) as likes
from
  blog.post_comments
group by
  status
order by
  comments desc;

revoke all on blog.comments_by_status_bar
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.comments_by_status_bar to "x-admin",
  "editor";

-- Line: inbox performance per issue — shown on the newsletter page
create or replace view blog.newsletter_performance_line
with
  (security_invoker = true) as
select
  to_char(date_trunc('day', sent_at), 'Mon DD') as date,
  round(avg(open_rate)::numeric, 1) as open_rate,
  round(avg(click_rate)::numeric, 1) as click_rate
from
  blog.newsletter_issues
where
  status = 'sent'
  and sent_at is not null
group by
  date_trunc('day', sent_at)
order by
  date_trunc('day', sent_at);

revoke all on blog.newsletter_performance_line
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on blog.newsletter_performance_line to "x-admin",
  "editor";

comment on view blog.posts_by_status_pie is '{"type": "chart", "name": "Posts By Status", "description": "Post count grouped by pipeline status", "chart_type": "pie"}';

comment on view blog.posts_by_category_bar is '{"type": "chart", "name": "Posts By Category", "description": "Output, publication and reach per category", "chart_type": "bar"}';

comment on view blog.publishing_volume_line is '{"type": "chart", "name": "Publishing Volume", "description": "Posts drafted vs published over 14 days", "chart_type": "line"}';

comment on view blog.traffic_composition_area is '{"type": "chart", "name": "Traffic Composition", "description": "Weekly views, visitors and reads over 8 weeks", "chart_type": "area"}';

comment on view blog.author_scorecard_radar is '{"type": "chart", "name": "Contributor Scorecard", "description": "Output and reader rating per active contributor", "chart_type": "radar"}';

comment on view blog.posts_by_type_pie is '{"type": "chart", "name": "Published By Format", "description": "How the live catalogue splits across formats", "chart_type": "pie", "resource": "posts"}';

comment on view blog.subscribers_by_plan_pie is '{"type": "chart", "name": "Subscribers By Plan", "description": "Distribution of the list across plans", "chart_type": "pie", "resource": "subscribers"}';

comment on view blog.comments_by_status_bar is '{"type": "chart", "name": "Moderation Outcomes", "description": "Comments and likes by moderation status", "chart_type": "bar", "resource": "post_comments"}';

comment on view blog.newsletter_performance_line is '{"type": "chart", "name": "Inbox Performance", "description": "Open and click rate per send", "chart_type": "line", "resource": "newsletter_issues"}';

----------------------------------------------------------------
-- Audit triggers (INSERT/UPDATE fire AFTER, DELETE must fire BEFORE
-- so the row still exists when it is captured)
--
-- blog.post_events and blog.post_metrics_daily are deliberately left
-- out: the first is already an audit trail, the second is
-- machine-written traffic data that would swamp the log.
----------------------------------------------------------------
create trigger audit_blog_categories_insert
after insert on blog.categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_categories_update
after update on blog.categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_categories_delete
before delete on blog.categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_tags_insert
after insert on blog.tags for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_tags_update
after update on blog.tags for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_tags_delete
before delete on blog.tags for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_authors_insert
after insert on blog.authors for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_authors_update
after update on blog.authors for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_authors_delete
before delete on blog.authors for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_author_billing_insert
after insert on blog.author_billing for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_author_billing_update
after update on blog.author_billing for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_author_billing_delete
before delete on blog.author_billing for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_series_insert
after insert on blog.series for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_series_update
after update on blog.series for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_series_delete
before delete on blog.series for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_content_campaigns_insert
after insert on blog.content_campaigns for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_content_campaigns_update
after update on blog.content_campaigns for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_content_campaigns_delete
before delete on blog.content_campaigns for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_posts_insert
after insert on blog.posts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_posts_update
after update on blog.posts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_posts_delete
before delete on blog.posts for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_post_tags_insert
after insert on blog.post_tags for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_post_tags_delete
before delete on blog.post_tags for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_post_revisions_insert
after insert on blog.post_revisions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_post_revisions_update
after update on blog.post_revisions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_post_revisions_delete
before delete on blog.post_revisions for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_post_comments_insert
after insert on blog.post_comments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_post_comments_update
after update on blog.post_comments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_post_comments_delete
before delete on blog.post_comments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_subscribers_insert
after insert on blog.subscribers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_subscribers_update
after update on blog.subscribers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_subscribers_delete
before delete on blog.subscribers for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_newsletter_issues_insert
after insert on blog.newsletter_issues for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_newsletter_issues_update
after update on blog.newsletter_issues for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_newsletter_issues_delete
before delete on blog.newsletter_issues for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_blog_settings_insert
after insert on blog.blog_settings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_blog_settings_update
after update on blog.blog_settings for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
--
-- supasheet.create_notification() is service_role-only, so every
-- caller below is a `security definer set search_path = ''` trigger.
----------------------------------------------------------------
-- Posts: filing, review requests, assignment, scheduling, publication
create or replace function blog.trg_posts_notify () returns trigger as $$
declare
    v_recipients   uuid[];
    v_author_user  uuid;
    v_editor_user  uuid;
    v_type         text;
    v_title        text;
    v_body         text;
begin
    if new.author_id is not null then
        select user_id into v_author_user from blog.authors where id = new.author_id;
    end if;

    if new.editor_id is not null then
        select user_id into v_editor_user from blog.authors where id = new.editor_id;
    end if;

    if tg_op = 'INSERT' then
        v_type  := 'blog_post_created';
        v_title := 'New post filed';
        v_body  := new.reference || ': ' || new.title;
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('blog', 'posts', 'delete') || array[v_editor_user],
            null
        );
    elsif new.status = 'in_review' and old.status <> 'in_review' then
        v_type  := 'blog_post_review_requested';
        v_title := 'Review requested';
        v_body  := new.title || ' is ready for the desk.';
        v_recipients := array_remove(
            supasheet.get_users_with_table_privilege('blog', 'posts', 'delete') || array[v_editor_user],
            null
        );
    elsif new.status = 'published' and old.status <> 'published' then
        v_type  := 'blog_post_published';
        v_title := 'Post published';
        v_body  := new.title || ' is live.';
        v_recipients := array_remove(
            array[v_author_user, v_editor_user, new.user_id],
            null
        );
    elsif new.status = 'scheduled' and old.status <> 'scheduled' then
        v_type  := 'blog_post_scheduled';
        v_title := 'Post scheduled';
        v_body  := new.title || ' goes out ' || to_char(new.scheduled_for, 'Mon DD, YYYY HH24:MI') || '.';
        v_recipients := array_remove(array[v_author_user, v_editor_user], null);
    elsif new.editor_id is distinct from old.editor_id then
        v_type  := 'blog_post_assigned';
        v_title := 'Post assigned to you';
        v_body  := new.reference || ': ' || new.title;
        v_recipients := array_remove(array[v_editor_user], null);
    else
        return new;
    end if;

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'post_id',   new.id,
            'reference', new.reference,
            'status',    new.status,
            'post_type', new.post_type,
            'author_id', new.author_id
        ),
        '/blog/resource/posts/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists posts_notify on blog.posts;

create trigger posts_notify
after insert or update of status,
editor_id on blog.posts for each row
execute function blog.trg_posts_notify ();

-- Comments: tell the desk what needs moderating, and the byline when
-- a comment goes live under their post.
create or replace function blog.trg_post_comments_notify () returns trigger as $$
declare
    v_recipients  uuid[];
    v_author_user uuid;
    v_post        blog.posts%rowtype;
    v_type        text;
    v_title       text;
    v_body        text;
begin
    select * into v_post from blog.posts where id = new.post_id;

    if v_post.id is null then
        return new;
    end if;

    if v_post.author_id is not null then
        select user_id into v_author_user from blog.authors where id = v_post.author_id;
    end if;

    if tg_op = 'INSERT' and new.status = 'pending' then
        v_type  := 'blog_comment_pending';
        v_title := 'Comment awaiting moderation';
        v_body  := new.author_name || ' on "' || v_post.title || '"';
        v_recipients := supasheet.get_users_with_table_privilege('blog', 'post_comments', 'update');
    elsif new.status = 'approved' and (tg_op = 'INSERT' or old.status <> 'approved') then
        v_type  := 'blog_comment_approved';
        v_title := 'New comment on your post';
        v_body  := new.author_name || ': ' || left(new.body, 120);
        v_recipients := array_remove(array[v_author_user], null);
    else
        return new;
    end if;

    v_recipients := array_remove(v_recipients, new.user_id);

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'post_id',    new.post_id,
            'comment_id', new.id,
            'status',     new.status
        ),
        '/blog/resource/posts/' || new.post_id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists post_comments_notify on blog.post_comments;

create trigger post_comments_notify
after insert or update of status on blog.post_comments for each row
execute function blog.trg_post_comments_notify ();

-- Newsletter: the desk hears when an issue is queued or has landed.
create or replace function blog.trg_newsletter_issues_notify () returns trigger as $$
declare
    v_recipients uuid[];
    v_type       text;
    v_title      text;
    v_body       text;
begin
    if new.status = 'scheduled' and old.status <> 'scheduled' then
        v_type  := 'blog_newsletter_scheduled';
        v_title := 'Issue scheduled';
        v_body  := new.title || ' goes out ' || to_char(new.scheduled_for, 'Mon DD, YYYY HH24:MI') || '.';
    elsif new.status = 'sent' and old.status <> 'sent' then
        v_type  := 'blog_newsletter_sent';
        v_title := 'Issue sent';
        v_body  := new.title || ' reached ' || new.recipient_count || ' subscribers.';
    else
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('blog', 'newsletter_issues', 'update') || array[new.user_id],
        null
    );

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        v_type, v_title, v_body, v_recipients,
        jsonb_build_object(
            'issue_id',  new.id,
            'status',    new.status,
            'audience',  new.audience,
            'recipients', new.recipient_count
        ),
        '/blog/resource/newsletter_issues/' || new.id::text || '/detail'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists newsletter_issues_notify on blog.newsletter_issues;

create trigger newsletter_issues_notify
after update of status on blog.newsletter_issues for each row
execute function blog.trg_newsletter_issues_notify ();

-- Comments: pair the per-record comment system with notifications.
-- The trigger lives on the CENTRAL supasheet.comments table and
-- filters down to this schema's tables.
create or replace function blog.trg_blog_comments_notify () returns trigger as $$
declare
    v_recipients uuid[];
begin
    if new.schema_name <> 'blog' or new.table_name not in ('posts', 'content_campaigns') then
        return new;
    end if;

    v_recipients := array_remove(
        supasheet.get_users_with_table_privilege('blog', new.table_name, 'update'),
        new.created_by
    );

    if array_length(v_recipients, 1) is null then
        return new;
    end if;

    perform supasheet.create_notification(
        'blog_comment_added',
        'New comment on ' || new.table_name,
        left(new.content, 140),
        v_recipients,
        jsonb_build_object('record_id', new.record_id, 'table_name', new.table_name),
        '/blog/resource/' || new.table_name || '/' || new.record_id::text || '/comment'
    );
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists blog_comments_notify on supasheet.comments;

create trigger blog_comments_notify
after insert on supasheet.comments for each row
execute function blog.trg_blog_comments_notify ();

----------------------------------------------------------------
-- Refresh the metadata catalog (materialized views — NOT automatic)
----------------------------------------------------------------
select
  supasheet.refresh_metadata ();
