create schema if not exists blog;

grant usage on schema blog to authenticated;

----------------------------------------------------------------
-- Enums
----------------------------------------------------------------
create type blog.post_status as enum('draft', 'scheduled', 'published', 'archived');

create type blog.comment_status as enum('pending', 'approved', 'spam');

----------------------------------------------------------------
-- Blog Settings  (single resource — one row only)
----------------------------------------------------------------
create table if not exists blog.blog_settings (
  id uuid primary key default gen_random_uuid(),
  blog_name varchar(255) not null default 'My Blog',
  tagline varchar(500),
  description supasheet.rich_text,
  logo supasheet.file,
  posts_per_page integer not null default 10,
  allow_comments boolean not null default true,
  require_comment_approval boolean not null default true,
  footer_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table blog.blog_settings is '{
    "icon": "BookOpen",
    "name": "Blog Settings",
    "display": "block",
    "singleton": true,
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Identity",
                "fields": [
                    "blog_name",
                    "tagline",
                    "description",
                    "logo"
                ]
            },
            {
                "id": "content",
                "title": "Content",
                "fields": [
                    "posts_per_page",
                    "footer_text"
                ]
            },
            {
                "id": "comments",
                "title": "Comments",
                "fields": [
                    "allow_comments",
                    "require_comment_approval"
                ]
            }
        ]
    }
}';

comment on column blog.blog_settings.logo is '{"name": "Logo", "accept": "image/*", "max_size": 2097152}';

revoke all on table blog.blog_settings
from
  authenticated,
  service_role;

grant
select
,
  insert,
update on table blog.blog_settings to "x-admin";

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
-- Users mirror (for Postgrest joins from blog.* tables)
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
  authenticated,
  service_role;

grant
select
  on blog.users to "x-admin";

----------------------------------------------------------------
-- Authors
----------------------------------------------------------------
create table if not exists blog.authors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid default auth.uid () references supasheet.users (id) on delete cascade,
  display_name varchar(100),
  bio supasheet.RICH_TEXT,
  avatar supasheet.file,
  language varchar(2) not null default 'en',
  country varchar(2) not null default 'US',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, language, country)
);

comment on table blog.authors is '{
    "icon": "UserPen",
    "display": "block",
    "primary_view": "list",
    "views": [
        {
            "id": "list",
            "name": "Authors List",
            "type": "list",
            "title": "display_name",
            "description": "user.email",
            "field_1": "language",
            "field_2": "country"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "identity",
                "title": "Identity",
                "fields": [
                    "display_name",
                    "avatar",
                    "bio"
                ]
            },
            {
                "id": "locale",
                "title": "Locale",
                "fields": [
                    "language",
                    "country"
                ]
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "display_name",
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

comment on column blog.authors.avatar is '{"accept": "image/*"}';

revoke all on table blog.authors
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table blog.authors to "x-admin";

create index idx_blog_authors_user_id on blog.authors (user_id);

alter table blog.authors enable row level security;

create policy authors_select on blog.authors for
select
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
  );

create policy authors_insert on blog.authors for insert to authenticated
with
  check (
    user_id = (
      select
        auth.uid ()
    )
  );

create policy authors_update on blog.authors
for update
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
  )
with
  check (
    user_id = (
      select
        auth.uid ()
    )
  );

create policy authors_delete on blog.authors for delete to authenticated using (
  user_id = (
    select
      auth.uid ()
  )
);

----------------------------------------------------------------
-- Social links (one row per author)
----------------------------------------------------------------
create table if not exists blog.social_links (
  author_id uuid primary key references blog.authors (id) on delete cascade,
  website varchar(255),
  github varchar(255),
  twitter varchar(255),
  linkedin varchar(255)
);

comment on table blog.social_links is '{
    "display": "none",
    "icon": "Link",
    "inline_form": true
}';

revoke all on table blog.social_links
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table blog.social_links to "x-admin";

alter table blog.social_links enable row level security;

create policy social_links_select on blog.social_links for
select
  to authenticated using (
    exists (
      select
        1
      from
        blog.authors a
      where
        a.id = author_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy social_links_insert on blog.social_links for insert to authenticated
with
  check (
    exists (
      select
        1
      from
        blog.authors a
      where
        a.id = author_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy social_links_update on blog.social_links
for update
  to authenticated using (
    exists (
      select
        1
      from
        blog.authors a
      where
        a.id = author_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  )
with
  check (
    exists (
      select
        1
      from
        blog.authors a
      where
        a.id = author_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy social_links_delete on blog.social_links for delete to authenticated using (
  exists (
    select
      1
    from
      blog.authors a
    where
      a.id = author_id
      and a.user_id = (
        select
          auth.uid ()
      )
  )
);

----------------------------------------------------------------
-- Categories
----------------------------------------------------------------
create table if not exists blog.categories (
  id uuid primary key default gen_random_uuid(),
  name varchar(100) not null,
  slug varchar(120) not null unique,
  description text,
  color supasheet.color,
  icon varchar(50),
  user_id uuid references supasheet.users (id) on delete cascade
);

comment on table blog.categories is '{
    "icon": "ListCollapse",
    "display": "block",
    "fields": {
        "sections": [
            {
                "id": "details",
                "title": "Details",
                "fields": [
                    "name",
                    "slug",
                    "description"
                ]
            },
            {
                "id": "presentation",
                "title": "Presentation",
                "fields": [
                    "color",
                    "icon"
                ]
            },
            {
                "id": "ownership",
                "title": "Ownership",
                "description": "Leave user empty for global categories",
                "fields": [
                    "user_id"
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

revoke all on table blog.categories
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table blog.categories to "x-admin";

alter table blog.categories enable row level security;

create policy categories_select on blog.categories for
select
  to authenticated using (
    user_id is null
    or user_id = (
      select
        auth.uid ()
    )
  );

create policy categories_insert on blog.categories for insert to authenticated
with
  check (
    user_id = (
      select
        auth.uid ()
    )
  );

create policy categories_update on blog.categories
for update
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
  )
with
  check (
    user_id = (
      select
        auth.uid ()
    )
  );

create policy categories_delete on blog.categories for delete to authenticated using (
  user_id = (
    select
      auth.uid ()
  )
);

----------------------------------------------------------------
-- Posts
----------------------------------------------------------------
create table if not exists blog.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references blog.authors (id) on delete cascade,
  title varchar(255) not null,
  slug varchar(275) not null unique,
  excerpt varchar(500),
  content supasheet.RICH_TEXT not null,
  cover supasheet.file,
  status blog.post_status not null default 'draft',
  featured boolean not null default false,
  tags varchar(100) [],
  view_count bigint not null default 0,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column blog.posts.status is '{
    "progress": true,
    "values": {
        "draft": {
            "variant": "outline",
            "icon": "FileEdit"
        },
        "scheduled": {
            "variant": "warning",
            "icon": "Clock"
        },
        "published": {
            "variant": "success",
            "icon": "CircleCheck"
        },
        "archived": {
            "variant": "secondary",
            "icon": "Archive"
        }
    }
}';

comment on table blog.posts is '{
    "icon": "NotebookText",
    "display": "block",
    "primary_view": "gallery",
    "views": [
        {
            "id": "status",
            "name": "Posts By Status",
            "type": "kanban",
            "group": "status",
            "title": "title",
            "description": "excerpt",
            "date": "published_at",
            "badge": "featured"
        },
        {
            "id": "calendar",
            "name": "Publishing Calendar",
            "type": "calendar",
            "title": "title",
            "badge": "status",
            "start_date": "published_at"
        },
        {
            "id": "gallery",
            "name": "Post Gallery",
            "type": "gallery",
            "cover": "cover",
            "title": "title",
            "description": "excerpt",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "content",
                "title": "Content",
                "fields": [
                    "title",
                    "slug",
                    "excerpt",
                    "content",
                    "cover"
                ]
            },
            {
                "id": "publishing",
                "title": "Publishing",
                "description": "Status, schedule and visibility",
                "fields": [
                    "status",
                    "published_at",
                    "featured",
                    "tags"
                ]
            },
            {
                "id": "relations",
                "title": "Author",
                "fields": [
                    "author_id"
                ]
            },
            {
                "id": "metrics",
                "title": "Metrics",
                "collapsible": true,
                "fields": {
                    "read": [
                        "view_count"
                    ],
                    "update": [
                        "view_count"
                    ]
                }
            }
        ]
    },
    "query": {
        "sort": [
            {
                "id": "published_at",
                "desc": true
            }
        ],
        "join": [
            {
                "table": "authors",
                "on": "author_id",
                "columns": [
                    "display_name",
                    "user_id"
                ]
            }
        ]
    }
}';

comment on column blog.posts.cover is '{"accept": "image/*"}';

revoke all on table blog.posts
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table blog.posts to "x-admin";

create index idx_blog_posts_author_id on blog.posts (author_id);

create index idx_blog_posts_status on blog.posts (status);

create index idx_blog_posts_published_at on blog.posts (published_at desc);

create index idx_blog_posts_featured on blog.posts (featured)
where
  featured = true;

alter table blog.posts enable row level security;

-- Anyone with the permission can see published posts; authors always see their own
create policy posts_select on blog.posts for
select
  to authenticated using (
    published_at is not null
    or exists (
      select
        1
      from
        blog.authors a
      where
        a.id = author_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy posts_insert on blog.posts for insert to authenticated
with
  check (
    exists (
      select
        1
      from
        blog.authors a
      where
        a.id = author_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy posts_update on blog.posts
for update
  to authenticated using (
    exists (
      select
        1
      from
        blog.authors a
      where
        a.id = author_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  )
with
  check (
    exists (
      select
        1
      from
        blog.authors a
      where
        a.id = author_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy posts_delete on blog.posts for delete to authenticated using (
  exists (
    select
      1
    from
      blog.authors a
    where
      a.id = author_id
      and a.user_id = (
        select
          auth.uid ()
      )
  )
);

----------------------------------------------------------------
-- Post categories junction
----------------------------------------------------------------
create table if not exists blog.post_categories (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references blog.posts (id) on delete cascade,
  category_id uuid references blog.categories (id) on delete cascade,
  unique (post_id, category_id)
);

comment on table blog.post_categories is '{
    "display": "none",
    "icon": "Tags"
}';

revoke all on table blog.post_categories
from
  authenticated,
  service_role;

grant
select
,
  insert,
  delete on table blog.post_categories to "x-admin";

alter table blog.post_categories enable row level security;

create policy post_categories_select on blog.post_categories for
select
  to authenticated using (true);

create policy post_categories_insert on blog.post_categories for insert to authenticated
with
  check (
    exists (
      select
        1
      from
        blog.posts p
        join blog.authors a on a.id = p.author_id
      where
        p.id = post_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy post_categories_delete on blog.post_categories for delete to authenticated using (
  exists (
    select
      1
    from
      blog.posts p
      join blog.authors a on a.id = p.author_id
    where
      p.id = post_id
      and a.user_id = (
        select
          auth.uid ()
      )
  )
);

----------------------------------------------------------------
-- Comments (with threaded replies via parent_id)
----------------------------------------------------------------
create table if not exists blog.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references blog.posts (id) on delete cascade,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  parent_id uuid references blog.comments (id) on delete cascade,
  author_name varchar(100),
  author_email supasheet.email,
  content text not null,
  status blog.comment_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column blog.comments.status is '{
    "progress": false,
    "values": {
        "pending": {
            "variant": "warning",
            "icon": "Clock"
        },
        "approved": {
            "variant": "success",
            "icon": "CircleCheck"
        },
        "spam": {
            "variant": "destructive",
            "icon": "ShieldAlert"
        }
    }
}';

comment on table blog.comments is '{
    "icon": "MessageSquare",
    "display": "block",
    "views": [
        {
            "id": "moderation",
            "name": "Moderation Queue",
            "type": "kanban",
            "group": "status",
            "title": "author_name",
            "description": "content",
            "date": "created_at",
            "badge": "status"
        }
    ],
    "fields": {
        "sections": [
            {
                "id": "context",
                "title": "Context",
                "fields": [
                    "post_id",
                    "parent_id"
                ]
            },
            {
                "id": "author",
                "title": "Author",
                "fields": [
                    "author_name",
                    "author_email"
                ]
            },
            {
                "id": "body",
                "title": "Comment",
                "fields": [
                    "content",
                    "status"
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
                "table": "posts",
                "on": "post_id",
                "columns": [
                    "title",
                    "slug"
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

revoke all on table blog.comments
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table blog.comments to "x-admin";

create index idx_blog_comments_post_id on blog.comments (post_id);

create index idx_blog_comments_parent_id on blog.comments (parent_id);

create index idx_blog_comments_status on blog.comments (status);

create index idx_blog_comments_user_id on blog.comments (user_id);

alter table blog.comments enable row level security;

-- Approved comments are visible to anyone with the permission;
-- authors of the post and the comment author can see their own (any status)
create policy comments_select on blog.comments for
select
  to authenticated using (
    status = 'approved'
    or user_id = (
      select
        auth.uid ()
    )
    or exists (
      select
        1
      from
        blog.posts p
        join blog.authors a on a.id = p.author_id
      where
        p.id = post_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy comments_insert on blog.comments for insert to authenticated
with
  check (
    user_id = (
      select
        auth.uid ()
    )
  );

-- Comment authors edit their own; post authors moderate (e.g. flip to approved/spam)
create policy comments_update on blog.comments
for update
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or exists (
      select
        1
      from
        blog.posts p
        join blog.authors a on a.id = p.author_id
      where
        p.id = post_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  )
with
  check (
    user_id = (
      select
        auth.uid ()
    )
    or exists (
      select
        1
      from
        blog.posts p
        join blog.authors a on a.id = p.author_id
      where
        p.id = post_id
        and a.user_id = (
          select
            auth.uid ()
        )
    )
  );

create policy comments_delete on blog.comments for delete to authenticated using (
  user_id = (
    select
      auth.uid ()
  )
  or exists (
    select
      1
    from
      blog.posts p
      join blog.authors a on a.id = p.author_id
    where
      p.id = post_id
      and a.user_id = (
        select
          auth.uid ()
      )
  )
);

----------------------------------------------------------------
-- Dashboard widget views
----------------------------------------------------------------
-- Card1: count of published posts
create or replace view blog.posts_summary
with
  (security_invoker = true) as
select
  count(*) as value,
  'notebook-text' as icon,
  'published posts' as label
from
  blog.posts
where
  status = 'published';

revoke all on blog.posts_summary
from
  authenticated,
  service_role;

grant
select
  on blog.posts_summary to "x-admin";

comment on view blog.posts_summary is '{"type": "dashboard_widget", "name": "Published Posts", "description": "Total published posts", "widget_type": "card_1"}';

-- Card2: published vs draft+scheduled
create or replace view blog.posts_completion_rate
with
  (security_invoker = true) as
select
  count(*) filter (
    where
      status = 'published'
  ) as primary,
  count(*) filter (
    where
      status in ('draft', 'scheduled')
  ) as secondary,
  'Published' as primary_label,
  'In Progress' as secondary_label
from
  blog.posts;

revoke all on blog.posts_completion_rate
from
  authenticated,
  service_role;

grant
select
  on blog.posts_completion_rate to "x-admin";

comment on view blog.posts_completion_rate is '{"type": "dashboard_widget", "name": "Publishing Pipeline", "description": "Published vs draft/scheduled", "widget_type": "card_2"}';

-- Card3: total views with avg-percent
create or replace view blog.total_views
with
  (security_invoker = true) as
select
  coalesce(sum(view_count), 0) as value,
  case
    when count(*) filter (
      where
        status = 'published'
    ) > 0 then round(
      (
        coalesce(
          sum(view_count) filter (
            where
              status = 'published'
          ),
          0
        )::numeric / nullif(
          count(*) filter (
            where
              status = 'published'
          ),
          0
        )
      )::numeric,
      1
    )
    else 0
  end as percent
from
  blog.posts;

revoke all on blog.total_views
from
  authenticated,
  service_role;

grant
select
  on blog.total_views to "x-admin";

comment on view blog.total_views is '{"type": "dashboard_widget", "name": "Total Views", "description": "Lifetime views and avg per published post", "widget_type": "card_3"}';

-- Table1: latest 10 posts
create or replace view blog.recent_posts
with
  (security_invoker = true) as
select
  title,
  status,
  to_char(coalesce(published_at, created_at), 'Mon DD') as date
from
  blog.posts
order by
  coalesce(published_at, created_at) desc
limit
  10;

revoke all on blog.recent_posts
from
  authenticated,
  service_role;

grant
select
  on blog.recent_posts to "x-admin";

comment on view blog.recent_posts is '{"type": "dashboard_widget", "name": "Recent Posts", "description": "Latest activity across the blog", "widget_type": "table_1"}';

----------------------------------------------------------------
-- Charts
----------------------------------------------------------------
-- Pie: status distribution
create or replace view blog.posts_status_pie
with
  (security_invoker = true) as
select
  status::text as label,
  count(*) as value
from
  blog.posts
group by
  status;

revoke all on blog.posts_status_pie
from
  authenticated,
  service_role;

grant
select
  on blog.posts_status_pie to "x-admin";

comment on view blog.posts_status_pie is '{"type": "chart", "name": "Posts By Status", "description": "Distribution of posts across the lifecycle", "chart_type": "pie"}';

-- Line: posts per month over the last 6 months
create or replace view blog.posts_per_month_line
with
  (security_invoker = true) as
select
  to_char(
    date_trunc('month', coalesce(published_at, created_at)),
    'Mon YYYY'
  ) as date,
  count(*) as created,
  count(*) filter (
    where
      status = 'published'
  ) as published
from
  blog.posts
where
  coalesce(published_at, created_at) >= date_trunc('month', current_date - interval '5 months')
group by
  date_trunc('month', coalesce(published_at, created_at))
order by
  date_trunc('month', coalesce(published_at, created_at));

revoke all on blog.posts_per_month_line
from
  authenticated,
  service_role;

grant
select
  on blog.posts_per_month_line to "x-admin";

comment on view blog.posts_per_month_line is '{"type": "chart", "name": "Publishing Cadence", "description": "Posts created vs published per month", "chart_type": "line"}';

-- Bar: post count per category
create or replace view blog.posts_by_category_bar
with
  (security_invoker = true) as
select
  c.name as label,
  count(pc.post_id) as total,
  count(pc.post_id) filter (
    where
      p.status = 'published'
  ) as published
from
  blog.categories c
  left join blog.post_categories pc on pc.category_id = c.id
  left join blog.posts p on p.id = pc.post_id
group by
  c.id,
  c.name
order by
  count(pc.post_id) desc;

revoke all on blog.posts_by_category_bar
from
  authenticated,
  service_role;

grant
select
  on blog.posts_by_category_bar to "x-admin";

comment on view blog.posts_by_category_bar is '{"type": "chart", "name": "Posts By Category", "description": "Total and published posts per category", "chart_type": "bar"}';

----------------------------------------------------------------
-- Reports
----------------------------------------------------------------
create or replace view blog.posts_report
with
  (security_invoker = true) as
select
  p.id,
  p.title,
  p.slug,
  p.status,
  p.featured,
  p.view_count,
  p.published_at,
  p.created_at,
  coalesce(a.display_name, u.name) as author,
  array_remove(array_agg(distinct c.name), null) as categories
from
  blog.posts p
  left join blog.authors a on a.id = p.author_id
  left join supasheet.users u on u.id = a.user_id
  left join blog.post_categories pc on pc.post_id = p.id
  left join blog.categories c on c.id = pc.category_id
group by
  p.id,
  a.display_name,
  u.name;

revoke all on blog.posts_report
from
  authenticated,
  service_role;

grant
select
  on blog.posts_report to "x-admin";

comment on view blog.posts_report is '{"type": "report", "name": "Posts Report", "description": "Full post list with author and categories"}';

----------------------------------------------------------------
-- Audit triggers
----------------------------------------------------------------
create trigger audit_blog_blog_settings_insert
after insert on blog.blog_settings for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_blog_settings_update
after update on blog.blog_settings for each row
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

create trigger audit_blog_social_links_insert
after insert on blog.social_links for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_social_links_update
after update on blog.social_links for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_social_links_delete
before delete on blog.social_links for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_categories_insert
after insert on blog.categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_categories_update
after update on blog.categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_categories_delete
before delete on blog.categories for each row
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

create trigger audit_blog_post_categories_insert
after insert on blog.post_categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_post_categories_delete
before delete on blog.post_categories for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_comments_insert
after insert on blog.comments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_comments_update
after update on blog.comments for each row
execute function supasheet.audit_trigger_function ();

create trigger audit_blog_comments_delete
before delete on blog.comments for each row
execute function supasheet.audit_trigger_function ();

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------
-- Resolver: the supasheet user behind a post (post → author → user)
create or replace function blog.get_post_author_user_id (p_post_id uuid) returns uuid language plpgsql stable security definer
set
  search_path = '' as $$
begin
    return (
        select a.user_id
        from blog.posts p
        join blog.authors a on a.id = p.author_id
        where p.id = p_post_id
    );
end;
$$;

-- Post trigger: notify the author and post readers when a post is published
create or replace function blog.trg_posts_notify () returns trigger as $$
declare
    v_author_user uuid;
    v_recipients  uuid[];
begin
    if tg_op = 'UPDATE'
       and new.status = 'published'
       and old.status is distinct from 'published'
    then
        v_author_user := blog.get_post_author_user_id(new.id);
        v_recipients  := array_remove(
            supasheet.get_users_with_table_privilege('blog', 'posts', 'select') || array[v_author_user],
            null
        );

        perform supasheet.create_notification(
            'post_published',
            'Post published',
            '"' || new.title || '" was published.',
            v_recipients,
            jsonb_build_object(
                'post_id',   new.id,
                'slug',      new.slug,
                'author_id', new.author_id
            ),
            '/blog/resource/posts/' || new.id::text || '/detail'
        );
    end if;
    return new;
end;
$$ language plpgsql security definer
set
  search_path = '';

drop trigger if exists posts_notify on blog.posts;

create trigger posts_notify
after update of status on blog.posts for each row
execute function blog.trg_posts_notify ();

-- Comment trigger:
--   * INSERT          → notify the post's author (excluding the commenter)
--   * status update   → notify the commenter of the moderation decision
create or replace function blog.trg_comments_notify () returns trigger as $$
declare
    v_post        blog.posts%rowtype;
    v_author_user uuid;
    v_recipients  uuid[];
    v_type        text;
    v_title       text;
    v_body        text;
begin
    select * into v_post from blog.posts where id = new.post_id;
    v_author_user := blog.get_post_author_user_id(new.post_id);

    if tg_op = 'INSERT' then
        v_type       := 'comment_posted';
        v_title      := 'New comment';
        v_body       := 'New comment on "' || v_post.title || '" awaiting your review.';
        v_recipients := array_remove(array[v_author_user], new.user_id);
    elsif new.status is distinct from old.status and new.user_id is not null then
        v_type       := 'comment_' || new.status::text;
        v_title      := 'Comment ' || new.status::text;
        v_body       := 'Your comment on "' || v_post.title || '" was ' || new.status::text || '.';
        v_recipients := array_remove(array[new.user_id], null);
    else
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

drop trigger if exists comments_notify on blog.comments;

create trigger comments_notify
after insert or update of status on blog.comments for each row
execute function blog.trg_comments_notify ();
