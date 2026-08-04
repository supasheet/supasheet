-- Blog Seeder
-- ================================================================
-- Demo data for the blog (editorial CMS / publication) module.
-- Apply supabase/examples/20260731000000_blog.sql first:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260731000000_blog.sql \
--     -f supabase/examples/b_seed.sql
--
-- Volume: 13 categories (three levels deep), 18 tags, 10
-- contributors, 5 payout records, 4 series, 5 campaigns, 46 posts
-- spread over the last twenty months, 76 tag links, 20 revisions, 42
-- reader comments, ~1,460 daily traffic rows, 32 subscribers and 8
-- newsletter issues. The triggers derive another 100-odd timeline
-- events on top of that.
--
-- Dates are all relative to `current_date` / `current_timestamp`, so
-- the dashboards, the 14-day line chart, the 8-week area chart, the
-- gantt roadmap and the monthly rollup all have shape whenever this
-- is run. Six posts are deliberately older than a year so the
-- "Ageing Content" widget and the content_refresh_template have
-- something to show.
--
-- Derived columns are left out of the inserts on purpose — the
-- module's triggers fill them exactly as they would in production:
-- word_count and reading_time from the body, comment_count from
-- approved comments, view_count / completion_rate from the daily
-- traffic rows, published_parts on series, published_posts and
-- progress on campaigns, usage_count on tags, revision_count on
-- posts, and every post_events timeline entry. Bodies here are two
-- or three paragraphs of demo prose rather than real articles, so
-- word_count lands in the tens and reading_time reads as a minute
-- across the board; paste real content in and both grow on their
-- own.
--
-- Five hardcoded users are seeded first so this file can run
-- independently of supabase/seed.sql (`on conflict do nothing`, so it
-- is also safe to run after supabase/seed.sql has created the first
-- three):
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b8  superadmin@supasheet.app (x-admin)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b2  editor@supasheet.app     (editor)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b3  author@supasheet.app     (author)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b1  user1@supasheet.app      (user)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b4  user@supasheet.app       (user)
--
-- Sign in as editor@supasheet.app to run the desk (full pipeline,
-- moderation queue, newsletter — but no payout terms), as
-- author@supasheet.app to see a contributor's seat (their own drafts
-- plus everything published, and only their own profile fields are
-- editable), and as user@supasheet.app for the reader view (published
-- posts and approved comments only — all enforced by RLS).
--
-- Password for every seeded user: the shared bcrypt hash below,
-- matching the rest of the Supasheet examples.
--
-- Not idempotent beyond the auth rows: re-running inserts duplicate
-- primary keys. Run `npx supabase db reset` to start over.
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    'authenticated',
    'authenticated',
    'superadmin@supasheet.app',
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
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b8", "email": "superadmin@supasheet.app", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    'authenticated',
    'authenticated',
    'editor@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "editor"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b2", "email": "editor@supasheet.app", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b3',
    'authenticated',
    'authenticated',
    'author@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "author"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b3", "email": "author@supasheet.app", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    'authenticated',
    'authenticated',
    'user@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "user"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b4", "email": "user@supasheet.app", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    'authenticated',
    'authenticated',
    'user1@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "user"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b1", "email": "user1@supasheet.app", "email_verified": false, "phone_verified": false}',
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
on conflict (id) do nothing;

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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b8", "email": "superadmin@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ab8'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b2", "email": "editor@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ab2'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b3',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b3',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b3", "email": "author@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ab3'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b4", "email": "user@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ab1'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b1", "email": "user1@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8abd'
  )
on conflict (id) do nothing;

----------------------------------------------------------------
-- Categories (three levels of nesting for the tree view;
-- lead_editor_id is backfilled after the authors insert)
----------------------------------------------------------------
insert into
  blog.categories (
    id,
    parent_id,
    name,
    slug,
    description,
    color,
    is_featured,
    sort_order,
    seo_title,
    seo_description
  )
values
  (
    'b1000000-0000-0000-0000-000000000001',
    null,
    'Engineering',
    'engineering',
    'How we build and run the product, in detail.',
    '#6366f1',
    true,
    10,
    'Engineering — Supasheet Blog',
    'Architecture, databases and the decisions behind them.'
  ),
  (
    'b1000000-0000-0000-0000-000000000002',
    'b1000000-0000-0000-0000-000000000001',
    'Databases',
    'databases',
    'Postgres, schema design and query performance.',
    '#4f46e5',
    true,
    11,
    'Databases — Supasheet Blog',
    'Postgres patterns, indexes and migrations.'
  ),
  (
    'b1000000-0000-0000-0000-000000000003',
    'b1000000-0000-0000-0000-000000000002',
    'Row Level Security',
    'row-level-security',
    'Policies, roles and grants — the third level of the tree.',
    '#4338ca',
    false,
    12,
    'Row Level Security — Supasheet Blog',
    'Everything about RLS in Postgres and Supabase.'
  ),
  (
    'b1000000-0000-0000-0000-000000000004',
    'b1000000-0000-0000-0000-000000000001',
    'Frontend',
    'frontend',
    'React, routing, state and the rendering layer.',
    '#0ea5e9',
    false,
    13,
    'Frontend — Supasheet Blog',
    'React 19, TanStack and the UI layer.'
  ),
  (
    'b1000000-0000-0000-0000-000000000005',
    'b1000000-0000-0000-0000-000000000001',
    'Security',
    'security',
    'Auth, permissions and keeping data where it belongs.',
    '#ef4444',
    false,
    14,
    'Security — Supasheet Blog',
    'Authentication, authorization and hardening.'
  ),
  (
    'b1000000-0000-0000-0000-000000000006',
    null,
    'Tutorials',
    'tutorials',
    'Step-by-step guides you can follow start to finish.',
    '#22c55e',
    true,
    20,
    'Tutorials — Supasheet Blog',
    'Hands-on guides for building with Supasheet.'
  ),
  (
    'b1000000-0000-0000-0000-000000000007',
    'b1000000-0000-0000-0000-000000000006',
    'Getting Started',
    'getting-started',
    'Your first hour with the platform.',
    '#16a34a',
    true,
    21,
    'Getting Started — Supasheet Blog',
    'Install, configure and ship your first resource.'
  ),
  (
    'b1000000-0000-0000-0000-000000000008',
    'b1000000-0000-0000-0000-000000000006',
    'Advanced Patterns',
    'advanced-patterns',
    'The techniques that show up once a project grows.',
    '#15803d',
    false,
    22,
    'Advanced Patterns — Supasheet Blog',
    'Triggers, rollups and multi-tenant modelling.'
  ),
  (
    'b1000000-0000-0000-0000-000000000009',
    null,
    'Product',
    'product',
    'What shipped, what is coming and why.',
    '#f59e0b',
    true,
    30,
    'Product — Supasheet Blog',
    'Roadmap, releases and product thinking.'
  ),
  (
    'b1000000-0000-0000-0000-00000000000a',
    'b1000000-0000-0000-0000-000000000009',
    'Changelog',
    'changelog',
    'Every release, in order.',
    '#d97706',
    false,
    31,
    'Changelog — Supasheet Blog',
    'Release notes for every version.'
  ),
  (
    'b1000000-0000-0000-0000-00000000000b',
    null,
    'Community',
    'community',
    'The people building on top of the platform.',
    '#ec4899',
    false,
    40,
    'Community — Supasheet Blog',
    'Guest posts, interviews and community projects.'
  ),
  (
    'b1000000-0000-0000-0000-00000000000c',
    'b1000000-0000-0000-0000-00000000000b',
    'Interviews',
    'interviews',
    'Conversations with people we learn from.',
    '#db2777',
    false,
    41,
    'Interviews — Supasheet Blog',
    'Long-form conversations with builders.'
  ),
  (
    'b1000000-0000-0000-0000-00000000000d',
    null,
    'Company',
    'company',
    'Hiring, culture and how the team works.',
    '#64748b',
    false,
    50,
    'Company — Supasheet Blog',
    'Team, hiring and how we operate.'
  );

----------------------------------------------------------------
-- Authors
--
-- Mentorship tree (the "Mentorship" tree view):
--   Grace -> {Ada, Alan}
--   Ada   -> {Katherine, Margaret}
--   Alan  -> {Barbara, Radia}
--   Katherine -> Linus,  Margaret -> Sofia,  Barbara -> Jae
--
-- Three of them map onto real logins: Grace is the publisher
-- (superadmin@), Ada is the editor (editor@) and Barbara is the
-- contributor (author@).
----------------------------------------------------------------
insert into
  blog.authors (
    id,
    user_id,
    mentor_id,
    display_name,
    email,
    phone,
    website,
    job_title,
    level,
    status,
    tagline,
    bio,
    twitter_handle,
    github_handle,
    joined_on,
    monthly_target,
    is_accepting_assignments,
    color
  )
values
  (
    'b3000000-0000-0000-0000-000000000001',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    null,
    'Grace Hopper',
    'grace@supasheet.app',
    '+1-202-555-0142',
    'https://supasheet.app/authors/grace',
    'Editor in Chief',
    'editor_in_chief',
    'active',
    'Runs the desk, still writes the hard ones.',
    '<p>Grace has been editing technical writing for fifteen years and still believes the best posts are the ones that cut a paragraph rather than add one.</p><p>She owns the publishing calendar and the standards that go with it.</p>',
    'gracehopper',
    'gracehopper',
    current_date - 1400,
    2,
    true,
    '#6366f1'
  ),
  (
    'b3000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    'b3000000-0000-0000-0000-000000000001',
    'Ada Lovelace',
    'ada@supasheet.app',
    '+44-20-7946-0958',
    'https://supasheet.app/authors/ada',
    'Engineering Editor',
    'editor',
    'active',
    'Databases, correctness, and long footnotes.',
    '<p>Ada edits everything that touches Postgres and reviews the query plans before the prose.</p>',
    'adalovelace',
    'adalovelace',
    current_date - 980,
    3,
    true,
    '#4f46e5'
  ),
  (
    'b3000000-0000-0000-0000-000000000003',
    null,
    'b3000000-0000-0000-0000-000000000001',
    'Alan Turing',
    'alan@supasheet.app',
    '+44-16-1234-5678',
    'https://supasheet.app/authors/alan',
    'Community Editor',
    'editor',
    'active',
    'Guest posts, interviews and the community rail.',
    '<p>Alan commissions from outside the team and runs the interview series.</p>',
    'alanturing',
    'alanturing',
    current_date - 760,
    2,
    true,
    '#0ea5e9'
  ),
  (
    'b3000000-0000-0000-0000-000000000004',
    null,
    'b3000000-0000-0000-0000-000000000002',
    'Katherine Johnson',
    'katherine@supasheet.app',
    '+1-757-555-0119',
    'https://supasheet.app/authors/katherine',
    'Senior Writer',
    'senior_writer',
    'active',
    'Explains hard things without making them longer.',
    '<p>Katherine writes the deep dives that get linked for years afterwards.</p>',
    'kjohnson',
    'kjohnson',
    current_date - 640,
    4,
    true,
    '#22c55e'
  ),
  (
    'b3000000-0000-0000-0000-000000000005',
    null,
    'b3000000-0000-0000-0000-000000000002',
    'Margaret Hamilton',
    'margaret@supasheet.app',
    '+1-617-555-0177',
    'https://supasheet.app/authors/margaret',
    'Senior Writer',
    'senior_writer',
    'active',
    'Ships the tutorials nobody else wants to write.',
    '<p>Margaret owns the getting-started track and rewrites it every release.</p>',
    'mhamilton',
    'mhamilton',
    current_date - 610,
    4,
    true,
    '#f59e0b'
  ),
  (
    'b3000000-0000-0000-0000-000000000006',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b3',
    'b3000000-0000-0000-0000-000000000003',
    'Barbara Liskov',
    'barbara@supasheet.app',
    '+1-415-555-0163',
    'https://supasheet.app/authors/barbara',
    'Staff Writer',
    'staff_writer',
    'active',
    'Substitution, abstraction, and good defaults.',
    '<p>Barbara joined from the community rail and now writes on staff.</p>',
    'bliskov',
    'bliskov',
    current_date - 420,
    3,
    true,
    '#ec4899'
  ),
  (
    'b3000000-0000-0000-0000-000000000007',
    null,
    'b3000000-0000-0000-0000-000000000003',
    'Radia Perlman',
    'radia@supasheet.app',
    '+1-206-555-0188',
    'https://supasheet.app/authors/radia',
    'Staff Writer',
    'staff_writer',
    'active',
    'Networks, protocols and the things underneath.',
    '<p>Radia covers the infrastructure layer and the occasional post-mortem.</p>',
    'rperlman',
    'rperlman',
    current_date - 380,
    3,
    true,
    '#14b8a6'
  ),
  (
    'b3000000-0000-0000-0000-000000000008',
    null,
    'b3000000-0000-0000-0000-000000000004',
    'Linus Chen',
    'linus@supasheet.app',
    '+65-6555-0122',
    null,
    'Contributor',
    'contributor',
    'active',
    'Weekend writer, weekday platform engineer.',
    '<p>Linus files one carefully researched post a month.</p>',
    'linuschen',
    'linuschen',
    current_date - 210,
    1,
    true,
    '#8b5cf6'
  ),
  (
    'b3000000-0000-0000-0000-000000000009',
    null,
    'b3000000-0000-0000-0000-000000000005',
    'Sofia Marin',
    'sofia@supasheet.app',
    '+34-91-555-0134',
    null,
    'Contributor',
    'contributor',
    'on_leave',
    'On sabbatical until the spring.',
    '<p>Sofia is away from the desk this quarter; her drafts are parked.</p>',
    'sofiamarin',
    null,
    current_date - 300,
    1,
    false,
    '#f97316'
  ),
  (
    'b3000000-0000-0000-0000-00000000000a',
    null,
    'b3000000-0000-0000-0000-000000000006',
    'Jae Park',
    'jae@supasheet.app',
    null,
    null,
    'Contributor',
    'contributor',
    'alumni',
    'Wrote the early tutorials, moved on in good standing.',
    '<p>Jae wrote the first version of the getting-started track.</p>',
    null,
    'jaepark',
    current_date - 900,
    0,
    false,
    '#64748b'
  );

-- Section editors: the categories now point back at the roster.
update blog.categories
set
  lead_editor_id = 'b3000000-0000-0000-0000-000000000002'
where
  id in (
    'b1000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000002',
    'b1000000-0000-0000-0000-000000000003'
  );

update blog.categories
set
  lead_editor_id = 'b3000000-0000-0000-0000-000000000001'
where
  id in (
    'b1000000-0000-0000-0000-000000000004',
    'b1000000-0000-0000-0000-000000000005',
    'b1000000-0000-0000-0000-000000000009',
    'b1000000-0000-0000-0000-00000000000a'
  );

update blog.categories
set
  lead_editor_id = 'b3000000-0000-0000-0000-000000000003'
where
  id in (
    'b1000000-0000-0000-0000-00000000000b',
    'b1000000-0000-0000-0000-00000000000c',
    'b1000000-0000-0000-0000-00000000000d'
  );

update blog.categories
set
  lead_editor_id = 'b3000000-0000-0000-0000-000000000002'
where
  id in (
    'b1000000-0000-0000-0000-000000000006',
    'b1000000-0000-0000-0000-000000000007',
    'b1000000-0000-0000-0000-000000000008'
  );

----------------------------------------------------------------
-- Author billing (1:1 — seeded for five of the ten contributors so
-- the UI shows both the linked record and the "add details" empty
-- state. Only the "x-admin" role can read this table at all.)
----------------------------------------------------------------
insert into
  blog.author_billing (
    id,
    author_id,
    payout_email,
    payout_method,
    currency,
    rate_per_word,
    flat_rate_per_post,
    tax_reference,
    last_paid_on,
    lifetime_payout,
    notes
  )
values
  (
    'b4000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000004',
    'katherine.payouts@supasheet.app',
    'bank_transfer',
    'USD',
    0.4200,
    null,
    'US-EIN-88-2213445',
    current_date - 12,
    18400.00,
    'Per-word rate, invoiced monthly.'
  ),
  (
    'b4000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000005',
    'margaret.payouts@supasheet.app',
    'bank_transfer',
    'USD',
    0.3800,
    null,
    'US-EIN-88-9930112',
    current_date - 12,
    16250.00,
    null
  ),
  (
    'b4000000-0000-0000-0000-000000000003',
    'b3000000-0000-0000-0000-000000000006',
    'barbara.payouts@supasheet.app',
    'paypal',
    'USD',
    null,
    650.00,
    null,
    current_date - 40,
    7800.00,
    'Flat rate per published post.'
  ),
  (
    'b4000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000007',
    'radia.payouts@supasheet.app',
    'bank_transfer',
    'USD',
    null,
    700.00,
    'US-EIN-77-1120098',
    current_date - 40,
    9100.00,
    null
  ),
  (
    'b4000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000008',
    'linus.payouts@supasheet.app',
    'wise',
    'SGD',
    null,
    500.00,
    null,
    current_date - 75,
    2000.00,
    'Contributor rate, paid on publication.'
  );

----------------------------------------------------------------
-- Blog settings (singleton)
----------------------------------------------------------------
insert into
  blog.blog_settings (
    id,
    blog_name,
    tagline,
    description,
    brand_color,
    site_url,
    contact_email,
    default_category_id,
    posts_per_page,
    comments_enabled,
    moderation_required,
    newsletter_enabled,
    default_visibility,
    twitter_url,
    github_url,
    footer_text,
    timezone
  )
values
  (
    'be000000-0000-0000-0000-000000000001',
    'The Supasheet Blog',
    'SQL-first software, written down',
    'Notes from the team building Supasheet: Postgres, permissions, and the parts of a product that never make the changelog.',
    '#6366f1',
    'https://supasheet.app/blog',
    'hello@supasheet.app',
    'b1000000-0000-0000-0000-000000000001',
    12,
    true,
    true,
    true,
    'public',
    'https://twitter.com/supasheet',
    'https://github.com/supasheet',
    '© Supasheet. Written by people who read the query plan.',
    'UTC'
  );

----------------------------------------------------------------
-- Tags
----------------------------------------------------------------
insert into
  blog.tags (id, name, slug, description, color, is_active)
values
  (
    'b2000000-0000-0000-0000-000000000001',
    'postgres',
    'postgres',
    'Anything that runs inside the database.',
    '#336791',
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000002',
    'rls',
    'rls',
    'Row Level Security policies and grants.',
    '#ef4444',
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000003',
    'supabase',
    'supabase',
    'Platform, CLI and edge functions.',
    '#3ecf8e',
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000004',
    'typescript',
    'typescript',
    'Types, generics and inference.',
    '#3178c6',
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000005',
    'react',
    'react',
    'Components, hooks and rendering.',
    '#61dafb',
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000006',
    'performance',
    'performance',
    'Making it faster, measured.',
    '#f59e0b',
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000007',
    'security',
    'security',
    'Auth, secrets and hardening.',
    '#dc2626',
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000008',
    'tutorial',
    'tutorial',
    'Follow along from start to finish.',
    '#22c55e',
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000009',
    'migrations',
    'migrations',
    'Schema change, safely.',
    '#8b5cf6',
    true
  ),
  (
    'b2000000-0000-0000-0000-00000000000a',
    'sql',
    'sql',
    'Queries, plans and indexes.',
    '#0ea5e9',
    true
  ),
  (
    'b2000000-0000-0000-0000-00000000000b',
    'api',
    'api',
    'PostgREST, endpoints and contracts.',
    '#14b8a6',
    true
  ),
  (
    'b2000000-0000-0000-0000-00000000000c',
    'design',
    'design',
    'Interface and interaction design.',
    '#ec4899',
    true
  ),
  (
    'b2000000-0000-0000-0000-00000000000d',
    'testing',
    'testing',
    'Confidence before deploy.',
    '#84cc16',
    true
  ),
  (
    'b2000000-0000-0000-0000-00000000000e',
    'deployment',
    'deployment',
    'Shipping to production.',
    '#f97316',
    true
  ),
  (
    'b2000000-0000-0000-0000-00000000000f',
    'open-source',
    'open-source',
    'Working in public.',
    '#64748b',
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000010',
    'product',
    'product',
    'Decisions and trade-offs.',
    '#eab308',
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000011',
    'community',
    'community',
    'People building alongside us.',
    '#a855f7',
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000012',
    'internals',
    'internals',
    'How the machinery actually works.',
    '#0f766e',
    false
  );

----------------------------------------------------------------
-- Series (published_parts is a rollup — the posts insert fills it)
----------------------------------------------------------------
insert into
  blog.series (
    id,
    name,
    slug,
    description,
    curator_id,
    status,
    planned_parts,
    starts_on,
    ends_on,
    is_featured,
    color
  )
values
  (
    'b5000000-0000-0000-0000-000000000001',
    'Postgres Internals',
    'postgres-internals',
    'A guided tour of the engine: MVCC, the planner, WAL and vacuum.',
    'b3000000-0000-0000-0000-000000000002',
    'ongoing',
    5,
    current_date - 150,
    current_date + 60,
    true,
    '#4f46e5'
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'Building Supasheet',
    'building-supasheet',
    'How the platform is put together, one subsystem at a time.',
    'b3000000-0000-0000-0000-000000000001',
    'ongoing',
    6,
    current_date - 220,
    current_date + 90,
    true,
    '#6366f1'
  ),
  (
    'b5000000-0000-0000-0000-000000000003',
    'RLS From Scratch',
    'rls-from-scratch',
    'Three parts, from the first policy to a full grant matrix.',
    'b3000000-0000-0000-0000-000000000003',
    'complete',
    3,
    current_date - 430,
    current_date - 330,
    false,
    '#ef4444'
  ),
  (
    'b5000000-0000-0000-0000-000000000004',
    'Frontend Foundations',
    'frontend-foundations',
    'Routing, data loading and forms, planned for next quarter.',
    'b3000000-0000-0000-0000-000000000004',
    'planning',
    4,
    current_date + 20,
    current_date + 140,
    false,
    '#0ea5e9'
  );

----------------------------------------------------------------
-- Content campaigns (published_posts and progress are rollups; the
-- date spread is what gives the gantt roadmap its shape)
----------------------------------------------------------------
insert into
  blog.content_campaigns (
    id,
    name,
    goal,
    brief,
    owner_id,
    status,
    start_on,
    end_on,
    target_posts,
    budget,
    channel,
    color,
    user_id,
    created_at
  )
values
  (
    'b6000000-0000-0000-0000-000000000001',
    'Launch Week',
    'One post a day for the release week.',
    '<p>Five deep dives and a changelog wrap-up, one per day, all pointing at the release notes.</p>',
    'b3000000-0000-0000-0000-000000000001',
    'active',
    current_date - 5,
    current_date + 2,
    6,
    4500.00,
    'blog + newsletter',
    '#6366f1',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '20 days'
  ),
  (
    'b6000000-0000-0000-0000-000000000002',
    'Q3 SEO Push',
    'Ten evergreen tutorials targeting the queries we lose.',
    '<p>Rewrite the getting-started track and add the eight tutorials the search console says we are missing.</p>',
    'b3000000-0000-0000-0000-000000000002',
    'active',
    current_date - 35,
    current_date + 30,
    10,
    9000.00,
    'organic search',
    '#22c55e',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '45 days'
  ),
  (
    'b6000000-0000-0000-0000-000000000003',
    'Community Spotlight',
    'Four guest posts and two interviews.',
    '<p>Commission from outside the team: two guest tutorials, two project write-ups, two interviews.</p>',
    'b3000000-0000-0000-0000-000000000003',
    'planned',
    current_date + 14,
    current_date + 60,
    6,
    3000.00,
    'community',
    '#ec4899',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '8 days'
  ),
  (
    'b6000000-0000-0000-0000-000000000004',
    'Spring Relaunch',
    'Refresh the whole engineering rail after the rewrite.',
    '<p>Three posts covering the new architecture, shipped alongside the spring release. One was later pulled, which is why the campaign closed short of its target.</p>',
    'b3000000-0000-0000-0000-000000000001',
    'completed',
    current_date - 150,
    current_date - 75,
    3,
    7500.00,
    'blog',
    '#8b5cf6',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '160 days'
  ),
  (
    'b6000000-0000-0000-0000-000000000005',
    'Docs Overhaul',
    'Pair every docs page with a worked example post.',
    '<p>Paused while the docs site migration finishes; resumes once the new structure lands.</p>',
    'b3000000-0000-0000-0000-000000000004',
    'paused',
    current_date - 50,
    current_date + 20,
    5,
    2500.00,
    'docs',
    '#f59e0b',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '60 days'
  );

----------------------------------------------------------------
-- Posts
--
-- word_count, reading_time, slug de-duplication, published_at /
-- archived_at stamping and every timeline event are all left to
-- blog.trg_posts_apply_defaults and blog.trg_posts_log_event, the
-- same way a real editor filing through the UI would get them.
--
-- Block 1 of 3 — the live pipeline: everything filed in the last two
-- weeks. This is what the editorial kanban, the 14-day volume chart
-- and the review/scheduled widgets read from.
----------------------------------------------------------------
insert into
  blog.posts (
    id,
    title,
    slug,
    excerpt,
    body,
    category_id,
    author_id,
    editor_id,
    series_id,
    series_part,
    campaign_id,
    status,
    post_type,
    visibility,
    review_notes,
    scheduled_for,
    published_at,
    is_featured,
    is_pinned,
    average_rating,
    keywords,
    user_id,
    created_at
  )
values
  (
    'b7000000-0000-0000-0000-000000000001',
    'Why Every Supasheet Feature Is a Migration',
    'why-every-feature-is-a-migration',
    'The whole product is configured from the database. Here is what that buys you, and what it costs.',
    '<p>Most admin panels ask you to describe your data twice: once in the schema and once again in application code. We decided the schema should be the only description that exists.</p><p>A table comment is JSON. The UI parses it and renders the kanban board, the field sections and the detail tabs from there. Adding a view type is a migration, not a pull request.</p><p>The cost is real: you write more SQL, and you learn what a grant actually does. The benefit is that the panel can never drift from the database it is pointed at.</p>',
    'b1000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000002',
    4,
    'b6000000-0000-0000-0000-000000000001',
    'draft',
    'article',
    'public',
    null,
    null,
    null,
    true,
    false,
    4.8,
    '{"architecture","sql","migrations"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '9 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000002',
    'Row Level Security Without the Footguns',
    'rls-without-the-footguns',
    'Six policies that look right, are wrong, and how to tell the difference before production does.',
    '<p>The most common RLS mistake is writing a policy that is never reached, because the grant underneath it already said no. The second most common is the reverse: a permissive policy on a table that every role can select from.</p><p>We walk through six real policies, show the query plan for each, and explain why wrapping auth.uid() in a scalar subquery changes the shape of the plan.</p>',
    'b1000000-0000-0000-0000-000000000003',
    'b3000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000002',
    null,
    null,
    'b6000000-0000-0000-0000-000000000001',
    'published',
    'article',
    'public',
    null,
    null,
    current_timestamp - interval '4 days',
    true,
    false,
    4.7,
    '{"rls","security","postgres"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '11 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000003',
    'The Grant Matrix, Explained',
    'the-grant-matrix-explained',
    'Roles are Postgres roles, permissions are grants. A walkthrough of the whole matrix.',
    '<p>There is no permissions table. A role is a real Postgres role, a permission is a real grant, and the JWT role claim drives SET ROLE inside PostgREST.</p><p>That means visibility is computed, not stored: if a role holds no select grant on a table, the resource simply is not there. This post lays out the full matrix for a four-role setup.</p>',
    'b1000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000007',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    'b6000000-0000-0000-0000-000000000001',
    'draft',
    'tutorial',
    'public',
    null,
    null,
    null,
    false,
    false,
    4.5,
    '{"security","rbac","postgres"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '13 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000004',
    'Shipping the Gantt View',
    'shipping-the-gantt-view',
    'The sixth view layout, and the three columns it needs from your table.',
    '<p>A gantt view needs a title, a start date and an end date. Give it a status column to group by and a numeric progress column, and the roadmap draws itself.</p><p>Everything else is metadata: which columns, in which order, under which name.</p>',
    'b1000000-0000-0000-0000-000000000009',
    'b3000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    'b6000000-0000-0000-0000-000000000001',
    'published',
    'changelog',
    'public',
    null,
    null,
    current_timestamp - interval '1 day',
    false,
    false,
    4.2,
    '{"product","views"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '5 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000000f',
    'Release 2.4: Gantt, Timelines and Row Actions',
    'release-2-4',
    'Everything that landed this cycle, with the migrations to copy.',
    '<p>Three things shipped: the gantt layout, timeline tabs backed by a trigger-populated event table, and row actions defined as SQL functions with a JSON comment.</p><p>Each one is a migration you can paste into your own project.</p>',
    'b1000000-0000-0000-0000-00000000000a',
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    'b6000000-0000-0000-0000-000000000001',
    'published',
    'changelog',
    'public',
    null,
    null,
    current_timestamp - interval '3 days',
    false,
    true,
    4.4,
    '{"release","changelog"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '4 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000005',
    'Kanban, Calendar, Gallery: Picking a Layout',
    'picking-a-layout',
    'Six layouts, one table. How to choose without guessing.',
    '<p>The sheet view always exists. Everything after that is a decision about what the reader is looking for: a pipeline, a date, a picture or a hierarchy.</p><p>This is a short decision tree, with the JSON for each case.</p>',
    'b1000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000006',
    'b3000000-0000-0000-0000-000000000003',
    null,
    null,
    null,
    'scheduled',
    'tutorial',
    'public',
    null,
    current_timestamp + interval '1 day' + interval '9 hours',
    null,
    false,
    false,
    null,
    '{"views","design"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b3',
    current_timestamp - interval '8 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000006',
    'Materialized Views as Reports',
    'materialized-views-as-reports',
    'When the query is too slow to run on every page load, precompute it.',
    '<p>A report is just a view with a JSON comment. When that view takes two seconds, make it materialized, add a unique index, and refresh it concurrently on a schedule.</p><p>The catalog refresh and the data refresh are different things, and confusing them is the most common mistake here.</p>',
    'b1000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000008',
    'b3000000-0000-0000-0000-000000000002',
    null,
    null,
    'b6000000-0000-0000-0000-000000000002',
    'scheduled',
    'article',
    'members',
    null,
    current_timestamp + interval '3 days' + interval '9 hours',
    null,
    false,
    false,
    null,
    '{"postgres","performance","reports"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '10 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000010',
    'How We Schedule the Publishing Calendar',
    'how-we-schedule',
    'A look at the desk from the inside: slots, buffers and the Friday rule.',
    '<p>Two slots a week, booked three weeks out, with one always held empty for whatever breaks.</p><p>The calendar view is the whole process. If it is not on the calendar it is not scheduled, and if it is not scheduled it is an idea.</p>',
    'b1000000-0000-0000-0000-00000000000d',
    'b3000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'scheduled',
    'article',
    'public',
    null,
    current_timestamp + interval '5 days' + interval '9 hours',
    null,
    false,
    false,
    null,
    '{"process","company"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '7 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000007',
    'A Field Guide to Postgres Triggers',
    'field-guide-to-postgres-triggers',
    'BEFORE, AFTER, per row, per statement — and when each one is the wrong choice.',
    '<p>Derived columns belong in a BEFORE trigger, because that is the only place you can change the row that is about to be written. Rollups belong in an AFTER trigger, because the row has to exist first.</p><p>Audit logging is the exception that catches everyone: the DELETE trigger has to fire BEFORE, or there is nothing left to capture.</p>',
    'b1000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000002',
    null,
    null,
    'b6000000-0000-0000-0000-000000000002',
    'in_review',
    'article',
    'public',
    'Strong draft. Needs a worked example for the statement-level case, and the audit note should move up to the top.',
    null,
    null,
    false,
    false,
    null,
    '{"postgres","triggers","internals"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '6 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000008',
    'What We Learned Rewriting the Data Table',
    'rewriting-the-data-table',
    'Virtualisation, column sizing and the footer aggregates nobody asked for but everybody uses.',
    '<p>The second version of the table is smaller than the first. Most of what we removed was configuration that could be derived from the column type.</p><p>The footer aggregates were a two-line feature that changed how people use the product.</p>',
    'b1000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000006',
    'b3000000-0000-0000-0000-000000000003',
    null,
    null,
    null,
    'in_review',
    'article',
    'public',
    'Cut the middle section, it repeats the intro. Otherwise ready.',
    null,
    null,
    false,
    false,
    null,
    '{"react","design","performance"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b3',
    current_timestamp - interval '12 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000009',
    'Multi-Tenant Modelling in One Schema',
    'multi-tenant-modelling',
    'One schema, one tenant column, and the policies that make it safe.',
    '<p>You do not need a schema per tenant. You need one column, one index and one policy that is impossible to forget.</p>',
    'b1000000-0000-0000-0000-000000000008',
    'b3000000-0000-0000-0000-000000000007',
    'b3000000-0000-0000-0000-000000000002',
    null,
    null,
    'b6000000-0000-0000-0000-000000000002',
    'draft',
    'article',
    'public',
    null,
    null,
    null,
    false,
    false,
    null,
    '{"postgres","rls","architecture"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '10 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000000a',
    'Indexes You Actually Need',
    'indexes-you-actually-need',
    'Foreign keys, filters and sorts. Everything else is speculation.',
    '<p>Three rules cover most tables: index every foreign key, index whatever the default sort uses, and index the columns your filter presets point at.</p>',
    'b1000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000008',
    'b3000000-0000-0000-0000-000000000002',
    null,
    null,
    'b6000000-0000-0000-0000-000000000002',
    'draft',
    'tutorial',
    'public',
    null,
    null,
    null,
    false,
    false,
    null,
    '{"postgres","performance","sql"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '13 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000000b',
    'Interview: Running Postgres at 40TB',
    'interview-postgres-at-40tb',
    'A conversation about vacuum, partitioning and what breaks first.',
    '<p>We sat down with a platform team running a single Postgres cluster past forty terabytes to ask what they would do differently.</p>',
    'b1000000-0000-0000-0000-00000000000c',
    'b3000000-0000-0000-0000-000000000003',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    'b6000000-0000-0000-0000-000000000003',
    'draft',
    'interview',
    'public',
    null,
    null,
    null,
    false,
    false,
    null,
    '{"postgres","interview","scale"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '4 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000000e',
    'Edge Functions for Admin Operations',
    'edge-functions-for-admin-operations',
    'The handful of things that cannot be a policy, and where they should live instead.',
    '<p>Creating a user, resetting a password, inviting a teammate: these need the service role, which means they cannot run in the browser.</p>',
    'b1000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000009',
    'b3000000-0000-0000-0000-000000000002',
    null,
    null,
    null,
    'draft',
    'article',
    'public',
    null,
    null,
    null,
    false,
    false,
    null,
    '{"supabase","security"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '14 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000000c',
    'The Case for SQL-First Admin Panels',
    'the-case-for-sql-first',
    'An opinion piece we have been circling for a while.',
    '<p>Rough outline only: the argument is that the schema already contains the product, and every layer above it is duplication waiting to drift.</p>',
    'b1000000-0000-0000-0000-000000000009',
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'idea',
    'article',
    'public',
    null,
    null,
    null,
    false,
    false,
    null,
    '{"product","opinion"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '3 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000000d',
    'Notifications Without a Queue',
    'notifications-without-a-queue',
    'What you can get away with when the database is already doing the work.',
    '<p>Idea: a trigger, a recipient resolver and a table. No broker, no worker, no retry logic until you actually need one.</p>',
    'b1000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000006',
    'b3000000-0000-0000-0000-000000000003',
    null,
    null,
    null,
    'idea',
    'article',
    'public',
    null,
    null,
    null,
    false,
    false,
    null,
    '{"postgres","notifications"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b3',
    current_timestamp - interval '2 days'
  );

----------------------------------------------------------------
-- Posts, block 2 of 3 — the last two months, all the way through the
-- pipeline. This is what fills the 8-week traffic area chart, the
-- series part counters and the "most read" leaderboard.
----------------------------------------------------------------
insert into
  blog.posts (
    id,
    title,
    slug,
    excerpt,
    body,
    category_id,
    author_id,
    editor_id,
    series_id,
    series_part,
    campaign_id,
    status,
    post_type,
    visibility,
    published_at,
    archived_at,
    is_featured,
    average_rating,
    keywords,
    user_id,
    created_at
  )
values
  (
    'b7000000-0000-0000-0000-000000000011',
    'Postgres Internals, Part 1: MVCC',
    'postgres-internals-mvcc',
    'Why your deleted rows are still there, and what that means for a busy table.',
    '<p>Every row you update is a new row. The old one stays until vacuum decides otherwise, and the visibility rules decide which version each transaction sees.</p><p>Once that clicks, bloat, long-running transactions and the occasional mysterious index scan all stop being mysterious.</p>',
    'b1000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000002',
    'b5000000-0000-0000-0000-000000000001',
    1,
    null,
    'draft',
    'article',
    'public',
    null,
    null,
    true,
    4.9,
    '{"postgres","internals","mvcc"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '58 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000012',
    'Postgres Internals, Part 2: Reading the Planner',
    'postgres-internals-planner',
    'EXPLAIN output, line by line, until it stops looking like noise.',
    '<p>The planner is a cost model, not an oracle. It guesses row counts from statistics and picks the cheapest plan it can find in the time it has.</p><p>Learning to read the estimate against the actual is the single highest-value database skill there is.</p>',
    'b1000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000002',
    'b5000000-0000-0000-0000-000000000001',
    2,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '36 days',
    null,
    false,
    4.8,
    '{"postgres","performance","internals"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '44 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000013',
    'Postgres Internals, Part 3: The Write-Ahead Log',
    'postgres-internals-wal',
    'Durability, replication and point-in-time recovery all come from one file stream.',
    '<p>The WAL is written before the data pages, which is what makes a crash survivable. It is also what replication reads, and what a restore replays.</p>',
    'b1000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000007',
    'b3000000-0000-0000-0000-000000000002',
    'b5000000-0000-0000-0000-000000000001',
    3,
    null,
    'published',
    'article',
    'members',
    current_timestamp - interval '22 days',
    null,
    false,
    4.6,
    '{"postgres","internals","wal"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '30 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000014',
    'Building Supasheet, Part 1: The Metadata Catalog',
    'building-supasheet-metadata-catalog',
    'The materialized views that let the UI ask the database what it looks like.',
    '<p>Four materialized views describe every table, column, view and function the caller is allowed to see. The panel renders from those, and nothing else.</p><p>They do not refresh themselves, which is why every migration ends with one particular function call.</p>',
    'b1000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000002',
    1,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '55 days',
    null,
    false,
    4.7,
    '{"architecture","postgres","internals"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '62 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000015',
    'Building Supasheet, Part 2: Comment-Driven UI',
    'building-supasheet-comment-driven-ui',
    'A table comment is JSON, and that JSON is the interface.',
    '<p>Sidebar entry, view layouts, field sections, filter presets, detail tabs: all of it lives in one JSON document attached to the table.</p><p>The trade-off is that a typo in the JSON is a silent fallback rather than a compile error, which is why the shape is documented as TypeScript types.</p>',
    'b1000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000002',
    2,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '41 days',
    null,
    false,
    4.5,
    '{"architecture","design","metadata"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '48 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000016',
    'Building Supasheet, Part 3: Auto-Generated Forms',
    'building-supasheet-forms',
    'Column types become inputs, sections become layout, conditions become behavior.',
    '<p>A form is a projection of the column list. The type picks the input, the comment picks the label, and the sections decide what the reader sees first.</p>',
    'b1000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000002',
    3,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '27 days',
    null,
    false,
    4.4,
    '{"forms","react","metadata"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '34 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000017',
    'Your First Resource in Ten Minutes',
    'your-first-resource',
    'One migration, one comment, one working CRUD screen.',
    '<p>Create the table, attach the JSON comment, grant the roles that should see it, refresh the catalog. That is the whole loop.</p><p>By the end you have a data table, a form, a detail page and an audit trail, none of which you wrote.</p>',
    'b1000000-0000-0000-0000-000000000007',
    'b3000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000002',
    null,
    null,
    'b6000000-0000-0000-0000-000000000002',
    'published',
    'tutorial',
    'public',
    current_timestamp - interval '14 days',
    null,
    true,
    4.9,
    '{"tutorial","getting-started","sql"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '21 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000018',
    'Seeding Demo Data That Looks Real',
    'seeding-demo-data',
    'Relative dates, deterministic noise, and letting the triggers do the derivation.',
    '<p>Good seed data is relative to today, never random in a way you cannot reproduce, and leaves every derived column to the triggers that own it.</p><p>Otherwise your demo drifts out of shape the week after you write it.</p>',
    'b1000000-0000-0000-0000-000000000008',
    'b3000000-0000-0000-0000-000000000008',
    'b3000000-0000-0000-0000-000000000002',
    null,
    null,
    'b6000000-0000-0000-0000-000000000002',
    'published',
    'tutorial',
    'public',
    current_timestamp - interval '18 days',
    null,
    false,
    4.3,
    '{"tutorial","sql","testing"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '25 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000019',
    'Custom Roles Are Just Postgres Roles',
    'custom-roles-are-postgres-roles',
    'CREATE ROLE, a few grants, and a claim in the JWT. There is no fourth step.',
    '<p>Adding an editor role to a project is two lines of SQL and a grant list. No enum to extend, no lookup table to seed, no cache to invalidate.</p>',
    'b1000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000007',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'published',
    'tutorial',
    'public',
    current_timestamp - interval '30 days',
    null,
    false,
    4.4,
    '{"rbac","security","postgres"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '37 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000001a',
    'Dashboard Widgets: The Twelve Contracts',
    'dashboard-widget-contracts',
    'Each widget type is a promise about the columns your view returns.',
    '<p>A card is a view that returns a value and a label. A leaderboard is a view that returns a name and a number, ordered. The contract is the whole API.</p>',
    'b1000000-0000-0000-0000-000000000009',
    'b3000000-0000-0000-0000-000000000006',
    'b3000000-0000-0000-0000-000000000003',
    null,
    null,
    null,
    'published',
    'tutorial',
    'public',
    current_timestamp - interval '25 days',
    null,
    false,
    4.2,
    '{"dashboards","sql","product"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b3',
    current_timestamp - interval '32 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000001b',
    'Reports That Print',
    'reports-that-print',
    'A denormalized view, a Handlebars file in a bucket, and a print button.',
    '<p>The report is a view. The template is an uploaded file whose name matches the view. The button appears when both exist.</p>',
    'b1000000-0000-0000-0000-000000000009',
    'b3000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'published',
    'article',
    'members',
    current_timestamp - interval '33 days',
    null,
    false,
    4.1,
    '{"reports","product"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '40 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000001c',
    'Interview: From Spreadsheet to Schema',
    'interview-spreadsheet-to-schema',
    'How one operations team moved eleven spreadsheets into one Postgres schema.',
    '<p>They started with a shared sheet and a colour convention. Eighteen months later they had a schema, a permission matrix and nobody editing production by hand.</p>',
    'b1000000-0000-0000-0000-00000000000c',
    'b3000000-0000-0000-0000-000000000003',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'published',
    'interview',
    'public',
    current_timestamp - interval '20 days',
    null,
    false,
    4.6,
    '{"interview","community","migration"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '28 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000001d',
    'Storage Columns and the Uploads Bucket',
    'storage-columns',
    'A file column is a composite type, and the bucket path is derived from the row.',
    '<p>Declaring a column as a file type gives you drag-and-drop upload, a preview and a delete, with the object key derived from the table and row it belongs to.</p>',
    'b1000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000006',
    'b3000000-0000-0000-0000-000000000003',
    null,
    null,
    null,
    'published',
    'tutorial',
    'public',
    current_timestamp - interval '45 days',
    null,
    false,
    4.0,
    '{"storage","supabase","tutorial"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b3',
    current_timestamp - interval '52 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000001e',
    'We Deleted the Permissions Table',
    'we-deleted-the-permissions-table',
    'The refactor that removed a whole subsystem and made the product simpler.',
    '<p>We had a permissions table, a role table, a join table and a cache. All four described something the database already knew.</p><p>Deleting them removed about two thousand lines and one entire class of bug: the panel saying yes while the database said no.</p>',
    'b1000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '52 days',
    null,
    true,
    4.9,
    '{"architecture","security","rbac"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '60 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000001f',
    'The Audit Log We Wanted',
    'the-audit-log-we-wanted',
    'Superseded by the release notes — kept for the trigger ordering discussion.',
    '<p>An early write-up of the audit design. The implementation has changed since, but the note about DELETE triggers having to fire BEFORE is still the part people get wrong.</p>',
    'b1000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000007',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'archived',
    'article',
    'public',
    current_timestamp - interval '60 days',
    current_timestamp - interval '5 days',
    false,
    3.8,
    '{"audit","postgres"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '66 days'
  );

----------------------------------------------------------------
-- Posts, block 3 of 3 — the historical tail, three to twenty months
-- back. This is what gives blog.post_traffic_rollup a month-by-month
-- shape; the six posts older than a year are what the "Ageing
-- Content" widget and blog.content_refresh_template pick up.
--
-- The last two rows deliberately leave `slug` null so
-- blog.trg_posts_apply_defaults slugifies the title instead.
----------------------------------------------------------------
insert into
  blog.posts (
    id,
    title,
    slug,
    excerpt,
    body,
    category_id,
    author_id,
    editor_id,
    series_id,
    series_part,
    campaign_id,
    status,
    post_type,
    visibility,
    published_at,
    archived_at,
    is_featured,
    average_rating,
    keywords,
    user_id,
    created_at
  )
values
  (
    'b7000000-0000-0000-0000-000000000020',
    'RLS From Scratch, Part 1: Your First Policy',
    'rls-from-scratch-first-policy',
    'Enable it, write one policy, and watch every query change shape.',
    '<p>Enabling row level security on a table denies everything by default. That is the correct starting point, and the reason the first policy you write should be the narrowest one you can live with.</p>',
    'b1000000-0000-0000-0000-000000000003',
    'b3000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000003',
    'b5000000-0000-0000-0000-000000000003',
    1,
    null,
    'published',
    'tutorial',
    'public',
    current_timestamp - interval '425 days',
    null,
    false,
    4.7,
    '{"rls","tutorial","security"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '432 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000021',
    'RLS From Scratch, Part 2: Roles and Grants',
    'rls-from-scratch-roles-and-grants',
    'The policy decides which rows. The grant decides whether you get to ask.',
    '<p>Policies filter rows; grants decide whether the statement runs at all. Most confusing RLS behaviour is actually a grant behaving exactly as configured.</p>',
    'b1000000-0000-0000-0000-000000000003',
    'b3000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000003',
    'b5000000-0000-0000-0000-000000000003',
    2,
    null,
    'published',
    'tutorial',
    'public',
    current_timestamp - interval '398 days',
    null,
    false,
    4.6,
    '{"rls","rbac","security"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '405 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000022',
    'RLS From Scratch, Part 3: The Full Matrix',
    'rls-from-scratch-full-matrix',
    'Four roles, nine tables, and a matrix you can actually review.',
    '<p>The final part builds the whole grant matrix for a four-role project and shows how to review it in one query rather than nine.</p>',
    'b1000000-0000-0000-0000-000000000003',
    'b3000000-0000-0000-0000-000000000007',
    'b3000000-0000-0000-0000-000000000003',
    'b5000000-0000-0000-0000-000000000003',
    3,
    null,
    'published',
    'tutorial',
    'public',
    current_timestamp - interval '372 days',
    null,
    false,
    4.5,
    '{"rls","rbac","sql"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '380 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000023',
    'Choosing Postgres for a CMS',
    'choosing-postgres-for-a-cms',
    'The database decision that made every later decision smaller.',
    '<p>Row level security, rich types, materialized views and functions with comments attached. Every feature we later shipped was already sitting in the database, waiting to be pointed at.</p>',
    'b1000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '560 days',
    null,
    true,
    4.8,
    '{"postgres","architecture","product"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '570 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000024',
    'The First Ten Migrations',
    'the-first-ten-migrations',
    'What the very first version of the schema looked like, mistakes included.',
    '<p>The first ten migrations set up types, users, roles, audit and storage. Two of them were wrong, and the fixes are more instructive than the originals.</p>',
    'b1000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-00000000000a',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '600 days',
    null,
    false,
    4.1,
    '{"migrations","history","sql"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '608 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000025',
    'Why We Do Not Use an ORM',
    'why-we-do-not-use-an-orm',
    'Not a purity argument. A consequence of the schema being the product.',
    '<p>When the schema is the source of truth for the interface, an object layer in front of it is a second, competing description. We removed the competition.</p>',
    'b1000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000002',
    null,
    null,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '480 days',
    null,
    false,
    4.3,
    '{"sql","architecture","opinion"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '488 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000026',
    'Release 1.0',
    'release-1-0',
    'The first stable version, and what we promised not to break.',
    '<p>Version one shipped with tables, forms, detail pages, dashboards and audit logs. The compatibility promise was about the comment JSON, not the code.</p>',
    'b1000000-0000-0000-0000-00000000000a',
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'published',
    'changelog',
    'public',
    current_timestamp - interval '520 days',
    null,
    false,
    4.0,
    '{"release","changelog","history"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '524 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000027',
    'Designing the Sheet View',
    'designing-the-sheet-view',
    'Making a data grid that a spreadsheet user can sit down in front of.',
    '<p>Keyboard navigation first, inline editing second, and column sizing that survives a reload. Everything else was negotiable.</p>',
    'b1000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '300 days',
    null,
    false,
    4.4,
    '{"design","react","product"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '308 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000028',
    'Testing Triggers with pgTAP',
    'testing-triggers-with-pgtap',
    'If the trigger owns the value, the test belongs in the database too.',
    '<p>Business logic in triggers needs tests next to the logic. pgTAP runs inside a transaction and rolls back, which makes it cheap enough to run on every push.</p>',
    'b1000000-0000-0000-0000-000000000008',
    'b3000000-0000-0000-0000-000000000008',
    'b3000000-0000-0000-0000-000000000002',
    null,
    null,
    null,
    'published',
    'tutorial',
    'public',
    current_timestamp - interval '240 days',
    null,
    false,
    4.2,
    '{"testing","postgres","triggers"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '248 days'
  ),
  (
    'b7000000-0000-0000-0000-000000000029',
    'A Year of Open Source',
    'a-year-of-open-source',
    'Issues, contributors, and the parts of the workflow we changed because of them.',
    '<p>The most useful contributions were not code. They were the twenty issues that all described the same missing view type in different words.</p>',
    'b1000000-0000-0000-0000-00000000000d',
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '200 days',
    null,
    true,
    4.7,
    '{"open-source","community","company"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '210 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000002a',
    'Guest Post: Building a Field Ops Tool',
    'guest-post-field-ops',
    'A community write-up: dispatch, offline notes and a very opinionated schema.',
    '<p>A guest post from a team that runs sixty field engineers off one schema, three roles and a kanban board.</p>',
    'b1000000-0000-0000-0000-00000000000b',
    'b3000000-0000-0000-0000-00000000000a',
    'b3000000-0000-0000-0000-000000000003',
    null,
    null,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '260 days',
    null,
    false,
    4.5,
    '{"community","guest-post"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '270 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000002b',
    'Deploying to the Edge',
    'deploying-to-the-edge',
    'Static bundle at the edge, database in one region, and the latency you actually feel.',
    '<p>Moving the bundle closer to the reader helps the first paint. It does nothing for the round trip to the database, which is where the time actually goes.</p>',
    'b1000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000007',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    null,
    'published',
    'article',
    'public',
    current_timestamp - interval '180 days',
    null,
    false,
    4.0,
    '{"deployment","performance"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '188 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000002c',
    'Spring Release: What Changed',
    'spring-release-what-changed',
    'The rewrite, in one page, with the migration order that made it survivable.',
    '<p>Eleven migrations, applied in one order, with a rollback plan for each. The order is the interesting part.</p>',
    'b1000000-0000-0000-0000-00000000000a',
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    'b6000000-0000-0000-0000-000000000004',
    'published',
    'changelog',
    'public',
    current_timestamp - interval '110 days',
    null,
    false,
    4.3,
    '{"release","migrations"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '118 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000002d',
    'Migrating 200 Tables Without Downtime',
    null,
    'Expand, backfill, contract — and a very boring deployment evening.',
    '<p>The pattern is always the same: add the new shape, backfill it, switch the readers, then drop the old shape in a later release.</p><p>The only interesting decision is how long you are willing to keep both.</p>',
    'b1000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000002',
    null,
    null,
    'b6000000-0000-0000-0000-000000000004',
    'published',
    'article',
    'public',
    current_timestamp - interval '95 days',
    null,
    true,
    4.8,
    '{"migrations","postgres","deployment"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '104 days'
  ),
  (
    'b7000000-0000-0000-0000-00000000002e',
    'Retiring the Old Dashboard',
    null,
    'Superseded by the widget contracts post. Kept for the migration notes.',
    '<p>The first dashboard was hand-built per project. It was replaced by twelve widget contracts, and this post only survives for the migration notes at the end.</p>',
    'b1000000-0000-0000-0000-000000000009',
    'b3000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    'b6000000-0000-0000-0000-000000000004',
    'archived',
    'article',
    'public',
    current_timestamp - interval '130 days',
    current_timestamp - interval '80 days',
    false,
    3.6,
    '{"dashboards","history"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '138 days'
  );

----------------------------------------------------------------
-- Walk three posts through the pipeline
--
-- Everything above is inserted in its final state, which only ever
-- fires the "created" timeline event. These three are filed as
-- drafts and then moved review -> scheduled -> published one step at
-- a time, so blog.trg_posts_log_event produces the status_changed,
-- scheduled and published entries too and their detail pages show a
-- full lifecycle instead of a single line.
--
-- The publication dates are the ones the rows would have carried if
-- they had been inserted as published: two days ago, six days ago
-- and fifty days ago.
----------------------------------------------------------------
update blog.posts
set
  status = 'in_review',
  review_notes = 'Read end to end. Two notes in the margin, otherwise ready to book a slot.'
where
  id in (
    'b7000000-0000-0000-0000-000000000001',
    'b7000000-0000-0000-0000-000000000003',
    'b7000000-0000-0000-0000-000000000011'
  );

update blog.posts
set
  status = 'scheduled',
  scheduled_for = case id
    when 'b7000000-0000-0000-0000-000000000001' then current_timestamp - interval '2 days'
    when 'b7000000-0000-0000-0000-000000000003' then current_timestamp - interval '6 days'
    else current_timestamp - interval '50 days'
  end
where
  id in (
    'b7000000-0000-0000-0000-000000000001',
    'b7000000-0000-0000-0000-000000000003',
    'b7000000-0000-0000-0000-000000000011'
  );

update blog.posts
set
  status = 'published',
  published_at = scheduled_for
where
  id in (
    'b7000000-0000-0000-0000-000000000001',
    'b7000000-0000-0000-0000-000000000003',
    'b7000000-0000-0000-0000-000000000011'
  );

-- One more handover so the "assigned" event type appears as well:
-- the data table rewrite goes to the editor in chief for the final
-- read.
update blog.posts
set
  editor_id = 'b3000000-0000-0000-0000-000000000001'
where
  id = 'b7000000-0000-0000-0000-000000000008';

----------------------------------------------------------------
-- Post tags (many-to-many junction)
--
-- blog.trg_post_tags_usage keeps blog.tags.usage_count in sync,
-- which is what the tag list view sorts by.
----------------------------------------------------------------
insert into
  blog.post_tags (id, post_id, tag_id)
values
  (
    'b8000000-0000-0000-0000-000000000001',
    'b7000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000002',
    'b7000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-00000000000a'
  ),
  (
    'b8000000-0000-0000-0000-000000000003',
    'b7000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000009'
  ),
  (
    'b8000000-0000-0000-0000-000000000004',
    'b7000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000002'
  ),
  (
    'b8000000-0000-0000-0000-000000000005',
    'b7000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000007'
  ),
  (
    'b8000000-0000-0000-0000-000000000006',
    'b7000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000007',
    'b7000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000007'
  ),
  (
    'b8000000-0000-0000-0000-000000000008',
    'b7000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000002'
  ),
  (
    'b8000000-0000-0000-0000-000000000009',
    'b7000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-00000000000a'
  ),
  (
    'b8000000-0000-0000-0000-00000000000a',
    'b7000000-0000-0000-0000-000000000004',
    'b2000000-0000-0000-0000-000000000010'
  ),
  (
    'b8000000-0000-0000-0000-00000000000b',
    'b7000000-0000-0000-0000-000000000004',
    'b2000000-0000-0000-0000-00000000000c'
  ),
  (
    'b8000000-0000-0000-0000-00000000000c',
    'b7000000-0000-0000-0000-00000000000f',
    'b2000000-0000-0000-0000-000000000010'
  ),
  (
    'b8000000-0000-0000-0000-00000000000d',
    'b7000000-0000-0000-0000-000000000005',
    'b2000000-0000-0000-0000-00000000000c'
  ),
  (
    'b8000000-0000-0000-0000-00000000000e',
    'b7000000-0000-0000-0000-000000000005',
    'b2000000-0000-0000-0000-000000000005'
  ),
  (
    'b8000000-0000-0000-0000-00000000000f',
    'b7000000-0000-0000-0000-000000000006',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000010',
    'b7000000-0000-0000-0000-000000000006',
    'b2000000-0000-0000-0000-000000000006'
  ),
  (
    'b8000000-0000-0000-0000-000000000011',
    'b7000000-0000-0000-0000-000000000007',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000012',
    'b7000000-0000-0000-0000-000000000007',
    'b2000000-0000-0000-0000-000000000012'
  ),
  (
    'b8000000-0000-0000-0000-000000000013',
    'b7000000-0000-0000-0000-000000000008',
    'b2000000-0000-0000-0000-000000000005'
  ),
  (
    'b8000000-0000-0000-0000-000000000014',
    'b7000000-0000-0000-0000-000000000008',
    'b2000000-0000-0000-0000-00000000000c'
  ),
  (
    'b8000000-0000-0000-0000-000000000015',
    'b7000000-0000-0000-0000-000000000008',
    'b2000000-0000-0000-0000-000000000006'
  ),
  (
    'b8000000-0000-0000-0000-000000000016',
    'b7000000-0000-0000-0000-000000000009',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000017',
    'b7000000-0000-0000-0000-000000000009',
    'b2000000-0000-0000-0000-000000000002'
  ),
  (
    'b8000000-0000-0000-0000-000000000018',
    'b7000000-0000-0000-0000-00000000000a',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000019',
    'b7000000-0000-0000-0000-00000000000a',
    'b2000000-0000-0000-0000-000000000006'
  ),
  (
    'b8000000-0000-0000-0000-00000000001a',
    'b7000000-0000-0000-0000-00000000000a',
    'b2000000-0000-0000-0000-00000000000a'
  ),
  (
    'b8000000-0000-0000-0000-00000000001b',
    'b7000000-0000-0000-0000-00000000000b',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-00000000001c',
    'b7000000-0000-0000-0000-00000000000b',
    'b2000000-0000-0000-0000-000000000011'
  ),
  (
    'b8000000-0000-0000-0000-00000000001d',
    'b7000000-0000-0000-0000-000000000011',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-00000000001e',
    'b7000000-0000-0000-0000-000000000011',
    'b2000000-0000-0000-0000-000000000012'
  ),
  (
    'b8000000-0000-0000-0000-00000000001f',
    'b7000000-0000-0000-0000-000000000012',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000020',
    'b7000000-0000-0000-0000-000000000012',
    'b2000000-0000-0000-0000-000000000006'
  ),
  (
    'b8000000-0000-0000-0000-000000000021',
    'b7000000-0000-0000-0000-000000000012',
    'b2000000-0000-0000-0000-000000000012'
  ),
  (
    'b8000000-0000-0000-0000-000000000022',
    'b7000000-0000-0000-0000-000000000013',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000023',
    'b7000000-0000-0000-0000-000000000013',
    'b2000000-0000-0000-0000-000000000012'
  ),
  (
    'b8000000-0000-0000-0000-000000000024',
    'b7000000-0000-0000-0000-000000000014',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000025',
    'b7000000-0000-0000-0000-000000000014',
    'b2000000-0000-0000-0000-00000000000a'
  ),
  (
    'b8000000-0000-0000-0000-000000000026',
    'b7000000-0000-0000-0000-000000000015',
    'b2000000-0000-0000-0000-00000000000c'
  ),
  (
    'b8000000-0000-0000-0000-000000000027',
    'b7000000-0000-0000-0000-000000000015',
    'b2000000-0000-0000-0000-000000000004'
  ),
  (
    'b8000000-0000-0000-0000-000000000028',
    'b7000000-0000-0000-0000-000000000016',
    'b2000000-0000-0000-0000-000000000005'
  ),
  (
    'b8000000-0000-0000-0000-000000000029',
    'b7000000-0000-0000-0000-000000000016',
    'b2000000-0000-0000-0000-000000000004'
  ),
  (
    'b8000000-0000-0000-0000-00000000002a',
    'b7000000-0000-0000-0000-000000000017',
    'b2000000-0000-0000-0000-000000000008'
  ),
  (
    'b8000000-0000-0000-0000-00000000002b',
    'b7000000-0000-0000-0000-000000000017',
    'b2000000-0000-0000-0000-00000000000a'
  ),
  (
    'b8000000-0000-0000-0000-00000000002c',
    'b7000000-0000-0000-0000-000000000017',
    'b2000000-0000-0000-0000-000000000003'
  ),
  (
    'b8000000-0000-0000-0000-00000000002d',
    'b7000000-0000-0000-0000-000000000018',
    'b2000000-0000-0000-0000-000000000008'
  ),
  (
    'b8000000-0000-0000-0000-00000000002e',
    'b7000000-0000-0000-0000-000000000018',
    'b2000000-0000-0000-0000-00000000000a'
  ),
  (
    'b8000000-0000-0000-0000-00000000002f',
    'b7000000-0000-0000-0000-000000000018',
    'b2000000-0000-0000-0000-00000000000d'
  ),
  (
    'b8000000-0000-0000-0000-000000000030',
    'b7000000-0000-0000-0000-000000000019',
    'b2000000-0000-0000-0000-000000000007'
  ),
  (
    'b8000000-0000-0000-0000-000000000031',
    'b7000000-0000-0000-0000-000000000019',
    'b2000000-0000-0000-0000-000000000002'
  ),
  (
    'b8000000-0000-0000-0000-000000000032',
    'b7000000-0000-0000-0000-000000000019',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000033',
    'b7000000-0000-0000-0000-00000000001a',
    'b2000000-0000-0000-0000-00000000000a'
  ),
  (
    'b8000000-0000-0000-0000-000000000034',
    'b7000000-0000-0000-0000-00000000001a',
    'b2000000-0000-0000-0000-000000000010'
  ),
  (
    'b8000000-0000-0000-0000-000000000035',
    'b7000000-0000-0000-0000-00000000001b',
    'b2000000-0000-0000-0000-000000000010'
  ),
  (
    'b8000000-0000-0000-0000-000000000036',
    'b7000000-0000-0000-0000-00000000001b',
    'b2000000-0000-0000-0000-00000000000a'
  ),
  (
    'b8000000-0000-0000-0000-000000000037',
    'b7000000-0000-0000-0000-00000000001c',
    'b2000000-0000-0000-0000-000000000011'
  ),
  (
    'b8000000-0000-0000-0000-000000000038',
    'b7000000-0000-0000-0000-00000000001d',
    'b2000000-0000-0000-0000-000000000003'
  ),
  (
    'b8000000-0000-0000-0000-000000000039',
    'b7000000-0000-0000-0000-00000000001d',
    'b2000000-0000-0000-0000-000000000008'
  ),
  (
    'b8000000-0000-0000-0000-00000000003a',
    'b7000000-0000-0000-0000-00000000001e',
    'b2000000-0000-0000-0000-000000000007'
  ),
  (
    'b8000000-0000-0000-0000-00000000003b',
    'b7000000-0000-0000-0000-00000000001e',
    'b2000000-0000-0000-0000-000000000002'
  ),
  (
    'b8000000-0000-0000-0000-00000000003c',
    'b7000000-0000-0000-0000-000000000020',
    'b2000000-0000-0000-0000-000000000002'
  ),
  (
    'b8000000-0000-0000-0000-00000000003d',
    'b7000000-0000-0000-0000-000000000020',
    'b2000000-0000-0000-0000-000000000008'
  ),
  (
    'b8000000-0000-0000-0000-00000000003e',
    'b7000000-0000-0000-0000-000000000021',
    'b2000000-0000-0000-0000-000000000002'
  ),
  (
    'b8000000-0000-0000-0000-00000000003f',
    'b7000000-0000-0000-0000-000000000021',
    'b2000000-0000-0000-0000-000000000007'
  ),
  (
    'b8000000-0000-0000-0000-000000000040',
    'b7000000-0000-0000-0000-000000000022',
    'b2000000-0000-0000-0000-000000000002'
  ),
  (
    'b8000000-0000-0000-0000-000000000041',
    'b7000000-0000-0000-0000-000000000022',
    'b2000000-0000-0000-0000-00000000000a'
  ),
  (
    'b8000000-0000-0000-0000-000000000042',
    'b7000000-0000-0000-0000-000000000023',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000043',
    'b7000000-0000-0000-0000-000000000023',
    'b2000000-0000-0000-0000-000000000010'
  ),
  (
    'b8000000-0000-0000-0000-000000000044',
    'b7000000-0000-0000-0000-000000000025',
    'b2000000-0000-0000-0000-00000000000a'
  ),
  (
    'b8000000-0000-0000-0000-000000000045',
    'b7000000-0000-0000-0000-000000000025',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000046',
    'b7000000-0000-0000-0000-000000000028',
    'b2000000-0000-0000-0000-00000000000d'
  ),
  (
    'b8000000-0000-0000-0000-000000000047',
    'b7000000-0000-0000-0000-000000000028',
    'b2000000-0000-0000-0000-000000000001'
  ),
  (
    'b8000000-0000-0000-0000-000000000048',
    'b7000000-0000-0000-0000-000000000029',
    'b2000000-0000-0000-0000-00000000000f'
  ),
  (
    'b8000000-0000-0000-0000-000000000049',
    'b7000000-0000-0000-0000-000000000029',
    'b2000000-0000-0000-0000-000000000011'
  ),
  (
    'b8000000-0000-0000-0000-00000000004a',
    'b7000000-0000-0000-0000-00000000002d',
    'b2000000-0000-0000-0000-000000000009'
  ),
  (
    'b8000000-0000-0000-0000-00000000004b',
    'b7000000-0000-0000-0000-00000000002d',
    'b2000000-0000-0000-0000-00000000000e'
  ),
  (
    'b8000000-0000-0000-0000-00000000004c',
    'b7000000-0000-0000-0000-00000000002d',
    'b2000000-0000-0000-0000-000000000001'
  );

----------------------------------------------------------------
-- Post revisions
--
-- `version` is set explicitly here: blog.trg_post_revisions_before
-- only numbers a revision when the column is left empty, and rows
-- inserted by the same statement cannot see each other. word_count
-- is left at zero so the trigger derives it from the body, and
-- blog.trg_post_revisions_after bumps posts.revision_count and files
-- a "revision_added" timeline entry for every row below.
----------------------------------------------------------------
insert into
  blog.post_revisions (
    id,
    post_id,
    version,
    kind,
    title,
    body,
    change_summary,
    editor_id,
    user_id,
    created_at
  )
values
  (
    'b9000000-0000-0000-0000-000000000001',
    'b7000000-0000-0000-0000-000000000001',
    1,
    'autosave',
    'Why Every Feature Is a Migration',
    '<p>First pass. The argument is that the schema already describes the product.</p>',
    'First draft, straight from the outline.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '8 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000002',
    'b7000000-0000-0000-0000-000000000001',
    2,
    'manual',
    'Why Every Supasheet Feature Is a Migration',
    '<p>Second pass with the cost section added, because the first version read as an advert.</p>',
    'Added the trade-offs section and fixed the title.',
    'b3000000-0000-0000-0000-000000000001',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '5 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000003',
    'b7000000-0000-0000-0000-000000000001',
    3,
    'editorial',
    'Why Every Supasheet Feature Is a Migration',
    '<p>Final editorial pass: tightened the opening and cut the third example.</p>',
    'Copy edit before publication.',
    'b3000000-0000-0000-0000-000000000001',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '2 days' - interval '3 hours'
  ),
  (
    'b9000000-0000-0000-0000-000000000004',
    'b7000000-0000-0000-0000-000000000002',
    1,
    'manual',
    'Row Level Security Without the Footguns',
    '<p>Draft with four policies. Two more were added after review.</p>',
    'Initial draft, four examples.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '9 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000005',
    'b7000000-0000-0000-0000-000000000002',
    2,
    'editorial',
    'Row Level Security Without the Footguns',
    '<p>Added the two missing policies and the query plan for each.</p>',
    'Two extra examples plus plans, per editor note.',
    'b3000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '5 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000006',
    'b7000000-0000-0000-0000-000000000007',
    1,
    'autosave',
    'A Field Guide to Postgres Triggers',
    '<p>Outline plus the BEFORE and AFTER sections.</p>',
    'Outline and first two sections.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '6 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000007',
    'b7000000-0000-0000-0000-000000000007',
    2,
    'manual',
    'A Field Guide to Postgres Triggers',
    '<p>Statement-level section drafted, audit note still at the bottom.</p>',
    'Added statement-level triggers.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '4 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000008',
    'b7000000-0000-0000-0000-000000000007',
    3,
    'editorial',
    'A Field Guide to Postgres Triggers',
    '<p>Editor pass ahead of the review note: examples reordered.</p>',
    'Reordered examples before sending to review.',
    'b3000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '2 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000009',
    'b7000000-0000-0000-0000-000000000008',
    1,
    'manual',
    'What We Learned Rewriting the Data Table',
    '<p>Long first draft with three case studies.</p>',
    'First draft.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b3',
    current_timestamp - interval '11 days'
  ),
  (
    'b9000000-0000-0000-0000-00000000000a',
    'b7000000-0000-0000-0000-000000000008',
    2,
    'manual',
    'What We Learned Rewriting the Data Table',
    '<p>Cut one case study and the benchmark table.</p>',
    'Trimmed by about a third.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b3',
    current_timestamp - interval '3 days'
  ),
  (
    'b9000000-0000-0000-0000-00000000000b',
    'b7000000-0000-0000-0000-000000000011',
    1,
    'manual',
    'Postgres Internals, Part 1: MVCC',
    '<p>Draft covering tuple versions and visibility.</p>',
    'First draft of part one.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '56 days'
  ),
  (
    'b9000000-0000-0000-0000-00000000000c',
    'b7000000-0000-0000-0000-000000000011',
    2,
    'editorial',
    'Postgres Internals, Part 1: MVCC',
    '<p>Added the vacuum section that the series needed for part three.</p>',
    'Vacuum section added for series continuity.',
    'b3000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '51 days'
  ),
  (
    'b9000000-0000-0000-0000-00000000000d',
    'b7000000-0000-0000-0000-000000000017',
    1,
    'autosave',
    'Your First Resource in Ten Minutes',
    '<p>Steps one to four, no screenshots yet.</p>',
    'Skeleton of the walkthrough.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '20 days'
  ),
  (
    'b9000000-0000-0000-0000-00000000000e',
    'b7000000-0000-0000-0000-000000000017',
    2,
    'manual',
    'Your First Resource in Ten Minutes',
    '<p>All steps written, timing checked end to end.</p>',
    'Completed all steps and verified the ten minute claim.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '17 days'
  ),
  (
    'b9000000-0000-0000-0000-00000000000f',
    'b7000000-0000-0000-0000-000000000017',
    3,
    'editorial',
    'Your First Resource in Ten Minutes',
    '<p>Editor pass: shorter sentences, one screenshot per step.</p>',
    'Copy edit and screenshots.',
    'b3000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '15 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000010',
    'b7000000-0000-0000-0000-00000000001e',
    1,
    'manual',
    'We Deleted the Permissions Table',
    '<p>The refactor write-up, before legal review of the numbers.</p>',
    'First draft with line counts.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '58 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000011',
    'b7000000-0000-0000-0000-00000000001e',
    2,
    'editorial',
    'We Deleted the Permissions Table',
    '<p>Rounded the numbers and added the migration order.</p>',
    'Numbers checked, migration order appended.',
    'b3000000-0000-0000-0000-000000000001',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '54 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000012',
    'b7000000-0000-0000-0000-00000000002d',
    1,
    'manual',
    'Migrating 200 Tables Without Downtime',
    '<p>Expand and contract, with the rollback plan per step.</p>',
    'First draft from the runbook.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '102 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000013',
    'b7000000-0000-0000-0000-00000000002d',
    2,
    'manual',
    'Migrating 200 Tables Without Downtime',
    '<p>Added the timing table from the actual deployment evening.</p>',
    'Real timings added after the deploy.',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '99 days'
  ),
  (
    'b9000000-0000-0000-0000-000000000014',
    'b7000000-0000-0000-0000-00000000002d',
    3,
    'editorial',
    'Migrating 200 Tables Without Downtime',
    '<p>Cut the vendor comparison, it dated the post.</p>',
    'Removed the vendor section.',
    'b3000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '96 days'
  );

----------------------------------------------------------------
-- Post comments
--
-- A mix of approved, pending, spam and rejected so the moderation
-- kanban has a column each, with three threads (parent_id set) for
-- the tree view. blog.trg_post_comments_before stamps the moderation
-- trail, and blog.trg_post_comments_rollup keeps
-- posts.comment_count at the approved count only.
--
-- The rows filed by user@supasheet.app include one still pending:
-- signed in as that reader you can see your own unapproved comment
-- and nobody else can, which is the post_comments RLS policy doing
-- its job.
----------------------------------------------------------------
insert into
  blog.post_comments (
    id,
    post_id,
    parent_id,
    author_name,
    author_email,
    author_website,
    body,
    status,
    rejection_reason,
    is_pinned,
    like_count,
    reported_count,
    moderated_by_id,
    user_id,
    created_at
  )
values
  (
    'ba000000-0000-0000-0000-000000000001',
    'b7000000-0000-0000-0000-000000000001',
    null,
    'Dana Okafor',
    'dana@example.com',
    'https://dana.example.com',
    'The point about drift is the one that landed for me. We keep a JSON config next to the schema and it is wrong about twice a month.',
    'approved',
    null,
    true,
    14,
    0,
    'b3000000-0000-0000-0000-000000000001',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '2 days' + interval '4 hours'
  ),
  (
    'ba000000-0000-0000-0000-000000000002',
    'b7000000-0000-0000-0000-000000000001',
    'ba000000-0000-0000-0000-000000000001',
    'Grace Hopper',
    'grace@supasheet.app',
    null,
    'That is exactly the failure mode we were trying to remove. The schema is the only copy now.',
    'approved',
    null,
    false,
    6,
    0,
    'b3000000-0000-0000-0000-000000000001',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '2 days' + interval '6 hours'
  ),
  (
    'ba000000-0000-0000-0000-000000000003',
    'b7000000-0000-0000-0000-000000000001',
    'ba000000-0000-0000-0000-000000000001',
    'Milo Fenn',
    'milo@example.com',
    null,
    'Does this hold up with more than one application reading the same database?',
    'approved',
    null,
    false,
    3,
    0,
    'b3000000-0000-0000-0000-000000000001',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '1 day' - interval '2 hours'
  ),
  (
    'ba000000-0000-0000-0000-000000000004',
    'b7000000-0000-0000-0000-000000000001',
    null,
    'anon',
    null,
    'https://cheap-backlinks.example.com',
    'Great post! Visit my site for the best SEO backlinks at unbeatable prices.',
    'spam',
    'Flagged as spam',
    false,
    0,
    3,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '1 day'
  ),
  (
    'ba000000-0000-0000-0000-000000000005',
    'b7000000-0000-0000-0000-000000000002',
    null,
    'Ines Barros',
    'ines@example.com',
    null,
    'The scalar subquery trick around auth.uid() cut one of our policies from 400ms to 12ms. Worth its own post.',
    'approved',
    null,
    true,
    22,
    0,
    'b3000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '4 days' + interval '3 hours'
  ),
  (
    'ba000000-0000-0000-0000-000000000006',
    'b7000000-0000-0000-0000-000000000002',
    'ba000000-0000-0000-0000-000000000005',
    'Ada Lovelace',
    'ada@supasheet.app',
    null,
    'Noted. It is on the calendar for next month, with the plans side by side.',
    'approved',
    null,
    false,
    9,
    0,
    'b3000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '4 days' + interval '5 hours'
  ),
  (
    'ba000000-0000-0000-0000-000000000007',
    'b7000000-0000-0000-0000-000000000002',
    null,
    'Tomas Vidal',
    'tomas@example.com',
    null,
    'Policy four is wrong for us because our tenants share a table. Is there a variant for that?',
    'approved',
    null,
    false,
    4,
    0,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '3 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000008',
    'b7000000-0000-0000-0000-000000000002',
    null,
    'Rhea Kapoor',
    'rhea@example.com',
    null,
    'Small typo in the third code block: the policy name does not match the table.',
    'pending',
    null,
    false,
    0,
    0,
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '6 hours'
  ),
  (
    'ba000000-0000-0000-0000-000000000009',
    'b7000000-0000-0000-0000-000000000003',
    null,
    'Sven Alberts',
    'sven@example.com',
    null,
    'We copied this matrix almost verbatim for a four role setup. It works.',
    'approved',
    null,
    false,
    11,
    0,
    'b3000000-0000-0000-0000-000000000001',
    null,
    current_timestamp - interval '5 days'
  ),
  (
    'ba000000-0000-0000-0000-00000000000a',
    'b7000000-0000-0000-0000-000000000003',
    null,
    'Priya Raman',
    'priya@example.com',
    null,
    'How do you handle a role that should see a table but only three of its columns?',
    'approved',
    null,
    false,
    5,
    0,
    'b3000000-0000-0000-0000-000000000001',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '4 days'
  ),
  (
    'ba000000-0000-0000-0000-00000000000b',
    'b7000000-0000-0000-0000-000000000003',
    'ba000000-0000-0000-0000-00000000000a',
    'Radia Perlman',
    'radia@supasheet.app',
    null,
    'Column level grants. Same syntax, you just list the columns after the operation.',
    'approved',
    null,
    false,
    8,
    0,
    'b3000000-0000-0000-0000-000000000001',
    null,
    current_timestamp - interval '4 days' + interval '2 hours'
  ),
  (
    'ba000000-0000-0000-0000-00000000000c',
    'b7000000-0000-0000-0000-000000000004',
    null,
    'Hugo Lindqvist',
    'hugo@example.com',
    null,
    'Any chance of a dependency arrow between bars? Otherwise this is exactly what we needed.',
    'approved',
    null,
    false,
    7,
    0,
    'b3000000-0000-0000-0000-000000000001',
    null,
    current_timestamp - interval '20 hours'
  ),
  (
    'ba000000-0000-0000-0000-00000000000d',
    'b7000000-0000-0000-0000-000000000004',
    null,
    'noreply',
    null,
    null,
    'FIRST!!! also check out my crypto channel',
    'spam',
    'Flagged as spam',
    false,
    0,
    5,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '18 hours'
  ),
  (
    'ba000000-0000-0000-0000-00000000000e',
    'b7000000-0000-0000-0000-00000000000f',
    null,
    'Lena Fischer',
    'lena@example.com',
    null,
    'Timeline tabs are the feature I did not know I wanted. Migrated two tables to them the same evening.',
    'approved',
    null,
    false,
    13,
    0,
    'b3000000-0000-0000-0000-000000000001',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '2 days' - interval '4 hours'
  ),
  (
    'ba000000-0000-0000-0000-00000000000f',
    'b7000000-0000-0000-0000-00000000000f',
    null,
    'Ben Ortiz',
    'ben@example.com',
    null,
    'Is the row action comment format documented anywhere outside this post?',
    'pending',
    null,
    false,
    0,
    0,
    null,
    null,
    current_timestamp - interval '10 hours'
  ),
  (
    'ba000000-0000-0000-0000-000000000010',
    'b7000000-0000-0000-0000-000000000011',
    null,
    'Otto Brandt',
    'otto@example.com',
    'https://ottobrandt.example.com',
    'Best explanation of tuple visibility I have read. Sent it to the whole team.',
    'approved',
    null,
    true,
    41,
    0,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '48 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000011',
    'b7000000-0000-0000-0000-000000000011',
    'ba000000-0000-0000-0000-000000000010',
    'Katherine Johnson',
    'katherine@supasheet.app',
    null,
    'Thank you. Part two goes into why the planner cares about all of this.',
    'approved',
    null,
    false,
    12,
    0,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '47 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000012',
    'b7000000-0000-0000-0000-000000000011',
    null,
    'Wei Zhang',
    'wei@example.com',
    null,
    'Would love a follow up on autovacuum tuning for very write heavy tables.',
    'approved',
    null,
    false,
    18,
    0,
    'b3000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '45 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000013',
    'b7000000-0000-0000-0000-000000000012',
    null,
    'Marta Silva',
    'marta@example.com',
    null,
    'The estimate versus actual framing finally made EXPLAIN readable for me.',
    'approved',
    null,
    false,
    16,
    0,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '34 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000014',
    'b7000000-0000-0000-0000-000000000012',
    null,
    'Deniz Aydin',
    'deniz@example.com',
    null,
    'Disagree on the index advice at the end, it depends heavily on the write ratio.',
    'approved',
    null,
    false,
    2,
    1,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '31 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000015',
    'b7000000-0000-0000-0000-000000000013',
    null,
    'Iris Novak',
    'iris@example.com',
    null,
    'Does the members-only visibility apply to the RSS feed as well?',
    'approved',
    null,
    false,
    3,
    0,
    'b3000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '20 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000016',
    'b7000000-0000-0000-0000-000000000014',
    null,
    'Felix Adeyemi',
    'felix@example.com',
    null,
    'The materialized view catalog is clever, but what is the refresh cost on a large schema?',
    'approved',
    null,
    false,
    9,
    0,
    'b3000000-0000-0000-0000-000000000001',
    null,
    current_timestamp - interval '53 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000017',
    'b7000000-0000-0000-0000-000000000014',
    'ba000000-0000-0000-0000-000000000016',
    'Grace Hopper',
    'grace@supasheet.app',
    null,
    'Milliseconds on a few hundred tables. It only runs at the end of a migration.',
    'approved',
    null,
    false,
    7,
    0,
    'b3000000-0000-0000-0000-000000000001',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '52 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000018',
    'b7000000-0000-0000-0000-000000000015',
    null,
    'Sara Lindholm',
    'sara@example.com',
    null,
    'A JSON schema or types package for the comment format would help a lot here.',
    'approved',
    null,
    false,
    15,
    0,
    'b3000000-0000-0000-0000-000000000001',
    null,
    current_timestamp - interval '39 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000019',
    'b7000000-0000-0000-0000-000000000016',
    null,
    'Peter Nagy',
    'peter@example.com',
    null,
    'Conditional field behavior removed about 300 lines of form code for us.',
    'approved',
    null,
    false,
    10,
    0,
    'b3000000-0000-0000-0000-000000000001',
    null,
    current_timestamp - interval '25 days'
  ),
  (
    'ba000000-0000-0000-0000-00000000001a',
    'b7000000-0000-0000-0000-000000000017',
    null,
    'Amara Diallo',
    'amara@example.com',
    null,
    'Timed myself: eleven minutes, and two of those were reading. Good title.',
    'approved',
    null,
    true,
    27,
    0,
    'b3000000-0000-0000-0000-000000000002',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '13 days'
  ),
  (
    'ba000000-0000-0000-0000-00000000001b',
    'b7000000-0000-0000-0000-000000000017',
    'ba000000-0000-0000-0000-00000000001a',
    'Margaret Hamilton',
    'margaret@supasheet.app',
    null,
    'That is the target. If it goes past fifteen we cut a step.',
    'approved',
    null,
    false,
    6,
    0,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '13 days' + interval '3 hours'
  ),
  (
    'ba000000-0000-0000-0000-00000000001c',
    'b7000000-0000-0000-0000-000000000017',
    null,
    'Guest',
    'guest@example.com',
    null,
    'Step six does not work on Windows. Please fix.',
    'rejected',
    'No detail provided after two follow-up requests.',
    false,
    0,
    0,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '12 days'
  ),
  (
    'ba000000-0000-0000-0000-00000000001d',
    'b7000000-0000-0000-0000-000000000018',
    null,
    'Nils Berger',
    'nils@example.com',
    null,
    'Deterministic noise instead of random() is the tip I came away with.',
    'approved',
    null,
    false,
    12,
    0,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '16 days'
  ),
  (
    'ba000000-0000-0000-0000-00000000001e',
    'b7000000-0000-0000-0000-000000000019',
    null,
    'Elif Demir',
    'elif@example.com',
    null,
    'We had a whole permissions service for this. Two lines of SQL instead.',
    'approved',
    null,
    false,
    19,
    0,
    'b3000000-0000-0000-0000-000000000001',
    null,
    current_timestamp - interval '28 days'
  ),
  (
    'ba000000-0000-0000-0000-00000000001f',
    'b7000000-0000-0000-0000-000000000019',
    null,
    'Jonas Weber',
    'jonas@example.com',
    null,
    'What happens to an active session when you change the role claim?',
    'pending',
    null,
    false,
    0,
    0,
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '2 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000020',
    'b7000000-0000-0000-0000-00000000001a',
    null,
    'Clara Mendes',
    'clara@example.com',
    null,
    'The leaderboard contract is my favourite. Two columns and it just draws.',
    'approved',
    null,
    false,
    8,
    0,
    'b3000000-0000-0000-0000-000000000003',
    null,
    current_timestamp - interval '23 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000021',
    'b7000000-0000-0000-0000-00000000001b',
    null,
    'Ravi Menon',
    'ravi@example.com',
    null,
    'Handlebars was a surprising choice but it does keep the template in the bucket rather than the bundle.',
    'approved',
    null,
    false,
    5,
    0,
    'b3000000-0000-0000-0000-000000000001',
    null,
    current_timestamp - interval '30 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000022',
    'b7000000-0000-0000-0000-00000000001c',
    null,
    'Yuki Tanaka',
    'yuki@example.com',
    null,
    'The part about deleting the colour convention made me laugh. We are still on the colours.',
    'approved',
    null,
    false,
    17,
    0,
    'b3000000-0000-0000-0000-000000000003',
    null,
    current_timestamp - interval '18 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000023',
    'b7000000-0000-0000-0000-00000000001d',
    null,
    'Anna Kowalski',
    'anna@example.com',
    null,
    'Does the file column clean up storage objects when the row is deleted?',
    'approved',
    null,
    false,
    6,
    0,
    'b3000000-0000-0000-0000-000000000003',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '43 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000024',
    'b7000000-0000-0000-0000-00000000001e',
    null,
    'Bruno Costa',
    'bruno@example.com',
    null,
    'Deleting a subsystem and shipping fewer lines is the most underrated release note there is.',
    'approved',
    null,
    true,
    33,
    0,
    'b3000000-0000-0000-0000-000000000001',
    null,
    current_timestamp - interval '50 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000025',
    'b7000000-0000-0000-0000-00000000001e',
    'ba000000-0000-0000-0000-000000000024',
    'Nadia Haddad',
    'nadia@example.com',
    null,
    'Agreed, though I would have kept a compatibility shim for one release.',
    'approved',
    null,
    false,
    4,
    0,
    'b3000000-0000-0000-0000-000000000001',
    null,
    current_timestamp - interval '49 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000026',
    'b7000000-0000-0000-0000-000000000020',
    null,
    'Karim Aziz',
    'karim@example.com',
    null,
    'Still the first link I send anyone who asks what RLS is.',
    'approved',
    null,
    false,
    24,
    0,
    'b3000000-0000-0000-0000-000000000003',
    null,
    current_timestamp - interval '380 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000027',
    'b7000000-0000-0000-0000-000000000023',
    null,
    'Erik Solberg',
    'erik@example.com',
    null,
    'Two years on, does this still hold? Curious whether anything changed your mind.',
    'pending',
    null,
    false,
    0,
    0,
    null,
    null,
    current_timestamp - interval '4 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000028',
    'b7000000-0000-0000-0000-000000000029',
    null,
    'Community Bot',
    null,
    'https://spam-metrics.example.com',
    'Boost your open source stars with our growth service, guaranteed results.',
    'spam',
    'Flagged as spam',
    false,
    0,
    7,
    'b3000000-0000-0000-0000-000000000003',
    null,
    current_timestamp - interval '190 days'
  ),
  (
    'ba000000-0000-0000-0000-000000000029',
    'b7000000-0000-0000-0000-00000000002d',
    null,
    'Ola Nilsen',
    'ola@example.com',
    null,
    'The timing table is the useful part. Everyone writes the theory, nobody publishes the clock.',
    'approved',
    null,
    true,
    29,
    0,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '90 days'
  ),
  (
    'ba000000-0000-0000-0000-00000000002a',
    'b7000000-0000-0000-0000-00000000002d',
    null,
    'Meera Pillai',
    'meera@example.com',
    null,
    'Would you do the contract phase in the same release next time, or still wait?',
    'rejected',
    'Duplicate of an earlier question, answered in the thread above.',
    false,
    0,
    0,
    'b3000000-0000-0000-0000-000000000002',
    null,
    current_timestamp - interval '88 days'
  );

----------------------------------------------------------------
-- Slipped slots
--
-- Publishing straight from a draft leaves scheduled_for equal to
-- published_at, which would make the "On-Time Publishing" widget
-- read a perfect 100%. Four posts here were booked for a slot and
-- went out two days late, so the widget reports a number a real desk
-- would recognise.
----------------------------------------------------------------
update blog.posts
set
  scheduled_for = published_at - interval '2 days'
where
  id in (
    'b7000000-0000-0000-0000-000000000013',
    'b7000000-0000-0000-0000-000000000016',
    'b7000000-0000-0000-0000-00000000001b',
    'b7000000-0000-0000-0000-00000000002c'
  );

----------------------------------------------------------------
-- Daily traffic
--
-- One row per published post per day for the last sixty days, which
-- is what the 8-week area chart, the "views 30d" pulse metric and
-- every view_count rollup read from. Generated rather than typed:
-- hand-writing eighteen hundred rows would be unreadable, and the
-- shape matters more than the individual numbers.
--
-- Traffic decays exponentially from the publication date and then
-- flattens into a long tail, so recent posts spike and older posts
-- keep a steady trickle. The noise term is hashtext() over the post
-- id and the day rather than random(), so the same seed file always
-- produces the same numbers.
--
-- blog.trg_post_metrics_rollup is disabled around the insert: with
-- it on, every one of these rows would fire its own aggregate and
-- its own posts UPDATE (and its own audit row). The single UPDATE
-- afterwards computes exactly what the trigger would have.
----------------------------------------------------------------
alter table blog.post_metrics_daily disable trigger post_metrics_rollup;

insert into
  blog.post_metrics_daily (
    post_id,
    day,
    views,
    unique_visitors,
    reads,
    average_time,
    referrer,
    subscriber_signups
  )
select
  p.id,
  d.day,
  v.views,
  greatest(1, round(v.views * 0.72))::integer,
  greatest(1, round(v.views * (0.30 + (h.n % 26) / 100.0)))::integer,
  (90 + (h.n % 240)) * 1000,
  (
    array[
      'organic search',
      'newsletter',
      'hacker news',
      'twitter',
      'referral',
      'direct'
    ]
  ) [1 + (h.n % 6)],
  case
    when v.views > 250 then (v.views / 200)::integer
    else 0
  end
from
  blog.posts p
  cross join lateral (
    select
      generate_series(
        greatest(p.published_at::date, current_date - 59),
        current_date,
        interval '1 day'
      )::date as day
  ) d
  cross join lateral (
    select
      (
        (
          hashtext (p.id::text || d.day::text)::bigint % 997
        ) + 997
      ) % 997 as n
  ) h
  cross join lateral (
    select
      greatest(
        3,
        round(
          (
            case
              when p.is_featured then 1400
              when p.visibility = 'public' then 620
              else 260
            end
          ) * (
            exp(- (d.day - p.published_at::date)::numeric / 12) + 0.06
          )
        )::integer + (h.n % 20)
      ) as views
  ) v
where
  p.status in ('published', 'archived')
  and p.published_at is not null
  and p.published_at::date <= current_date;

-- The rollup the trigger would have produced, in one statement.
update blog.posts p
set
  view_count = coalesce(m.views, 0),
  unique_visitor_count = coalesce(m.visitors, 0),
  completion_rate = case
    when coalesce(m.views, 0) = 0 then null
    else round(100.0 * coalesce(m.reads, 0) / m.views, 1)::real
  end
from
  (
    select
      post_id,
      sum(views) as views,
      sum(unique_visitors) as visitors,
      sum(reads) as reads
    from
      blog.post_metrics_daily
    group by
      post_id
  ) m
where
  m.post_id = p.id;

alter table blog.post_metrics_daily enable trigger post_metrics_rollup;

----------------------------------------------------------------
-- Subscribers
--
-- blog.trg_subscribers_before stamps subscribed_at and
-- unsubscribed_at, so the lifecycle dates below are only there
-- to give the list history; a fresh signup gets them for free.
-- The two rows tied to a login are what user@supasheet.app and
-- user1@supasheet.app see of the mailing list: their own row and
-- nothing else.
----------------------------------------------------------------
insert into
  blog.subscribers (
    id,
    email,
    name,
    status,
    plan,
    source,
    referred_by_post_id,
    country,
    interests,
    subscribed_at,
    unsubscribed_at,
    last_opened_at,
    open_count,
    click_count,
    lifetime_value,
    user_id,
    created_at
  )
values
  (
    'bc000000-0000-0000-0000-000000000001',
    'dana.okafor@example.com',
    'Dana Okafor',
    'subscribed',
    'paid',
    'post',
    'b7000000-0000-0000-0000-000000000001',
    'Nigeria',
    '{"engineering","postgres"}',
    current_timestamp - interval '210 days',
    null,
    current_timestamp - interval '2 days',
    148,
    52,
    240.00,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '210 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000002',
    'ines.barros@example.com',
    'Ines Barros',
    'subscribed',
    'paid',
    'organic',
    null,
    'Portugal',
    '{"postgres","security"}',
    current_timestamp - interval '320 days',
    null,
    current_timestamp - interval '3 days',
    201,
    77,
    360.00,
    null,
    current_timestamp - interval '320 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000003',
    'otto.brandt@example.com',
    'Otto Brandt',
    'subscribed',
    'paid',
    'post',
    'b7000000-0000-0000-0000-000000000011',
    'Germany',
    '{"internals","performance"}',
    current_timestamp - interval '150 days',
    null,
    current_timestamp - interval '4 days',
    96,
    41,
    180.00,
    null,
    current_timestamp - interval '150 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000004',
    'wei.zhang@example.com',
    'Wei Zhang',
    'subscribed',
    'paid',
    'referral',
    null,
    'Singapore',
    '{"postgres","tutorials"}',
    current_timestamp - interval '95 days',
    null,
    current_timestamp - interval '5 days',
    64,
    29,
    120.00,
    null,
    current_timestamp - interval '95 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000005',
    'amara.diallo@example.com',
    'Amara Diallo',
    'subscribed',
    'member',
    'post',
    'b7000000-0000-0000-0000-000000000017',
    'Senegal',
    '{"tutorials","getting-started"}',
    current_timestamp - interval '72 days',
    null,
    current_timestamp - interval '6 days',
    55,
    23,
    60.00,
    null,
    current_timestamp - interval '72 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000006',
    'marta.silva@example.com',
    'Marta Silva',
    'subscribed',
    'member',
    'organic',
    null,
    'Brazil',
    '{"performance","sql"}',
    current_timestamp - interval '188 days',
    null,
    current_timestamp - interval '7 days',
    102,
    38,
    60.00,
    null,
    current_timestamp - interval '188 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000007',
    'felix.adeyemi@example.com',
    'Felix Adeyemi',
    'subscribed',
    'member',
    'post',
    'b7000000-0000-0000-0000-000000000014',
    'Ghana',
    '{"architecture"}',
    current_timestamp - interval '140 days',
    null,
    current_timestamp - interval '8 days',
    71,
    26,
    60.00,
    null,
    current_timestamp - interval '140 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000008',
    'sara.lindholm@example.com',
    'Sara Lindholm',
    'subscribed',
    'member',
    'campaign',
    null,
    'Sweden',
    '{"design","product"}',
    current_timestamp - interval '118 days',
    null,
    current_timestamp - interval '9 days',
    83,
    31,
    60.00,
    null,
    current_timestamp - interval '118 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000009',
    'peter.nagy@example.com',
    'Peter Nagy',
    'subscribed',
    'member',
    'organic',
    null,
    'Hungary',
    '{"forms","react"}',
    current_timestamp - interval '101 days',
    null,
    current_timestamp - interval '10 days',
    49,
    17,
    60.00,
    null,
    current_timestamp - interval '101 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000000a',
    'elif.demir@example.com',
    'Elif Demir',
    'subscribed',
    'member',
    'post',
    'b7000000-0000-0000-0000-00000000001e',
    'Turkey',
    '{"security","rbac"}',
    current_timestamp - interval '164 days',
    null,
    current_timestamp - interval '11 days',
    90,
    35,
    60.00,
    null,
    current_timestamp - interval '164 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000000b',
    'bruno.costa@example.com',
    'Bruno Costa',
    'subscribed',
    'member',
    'organic',
    null,
    'Portugal',
    '{"architecture","product"}',
    current_timestamp - interval '133 days',
    null,
    current_timestamp - interval '12 days',
    77,
    28,
    60.00,
    null,
    current_timestamp - interval '133 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000000c',
    'ola.nilsen@example.com',
    'Ola Nilsen',
    'subscribed',
    'member',
    'post',
    'b7000000-0000-0000-0000-00000000002d',
    'Norway',
    '{"migrations","deployment"}',
    current_timestamp - interval '88 days',
    null,
    current_timestamp - interval '1 days',
    44,
    19,
    60.00,
    null,
    current_timestamp - interval '88 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000000d',
    'milo.fenn@example.com',
    'Milo Fenn',
    'subscribed',
    'free',
    'organic',
    null,
    'Ireland',
    '{"engineering"}',
    current_timestamp - interval '54 days',
    null,
    current_timestamp - interval '2 days',
    22,
    7,
    0.00,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '54 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000000e',
    'tomas.vidal@example.com',
    'Tomas Vidal',
    'subscribed',
    'free',
    'organic',
    null,
    'Spain',
    '{"rls","multi-tenant"}',
    current_timestamp - interval '61 days',
    null,
    current_timestamp - interval '3 days',
    28,
    9,
    0.00,
    null,
    current_timestamp - interval '61 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000000f',
    'rhea.kapoor@example.com',
    'Rhea Kapoor',
    'subscribed',
    'free',
    'post',
    'b7000000-0000-0000-0000-000000000002',
    'India',
    '{"rls","security"}',
    current_timestamp - interval '40 days',
    null,
    current_timestamp - interval '4 days',
    19,
    6,
    0.00,
    null,
    current_timestamp - interval '40 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000010',
    'sven.alberts@example.com',
    'Sven Alberts',
    'subscribed',
    'free',
    'organic',
    null,
    'Netherlands',
    '{"rbac"}',
    current_timestamp - interval '210 days',
    null,
    current_timestamp - interval '5 days',
    60,
    14,
    0.00,
    null,
    current_timestamp - interval '210 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000011',
    'priya.raman@example.com',
    'Priya Raman',
    'subscribed',
    'free',
    'referral',
    null,
    'India',
    '{"security","sql"}',
    current_timestamp - interval '175 days',
    null,
    current_timestamp - interval '6 days',
    52,
    11,
    0.00,
    null,
    current_timestamp - interval '175 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000012',
    'hugo.lindqvist@example.com',
    'Hugo Lindqvist',
    'subscribed',
    'free',
    'post',
    'b7000000-0000-0000-0000-000000000004',
    'Sweden',
    '{"product","views"}',
    current_timestamp - interval '25 days',
    null,
    current_timestamp - interval '7 days',
    11,
    4,
    0.00,
    null,
    current_timestamp - interval '25 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000013',
    'lena.fischer@example.com',
    'Lena Fischer',
    'subscribed',
    'free',
    'campaign',
    null,
    'Germany',
    '{"product","changelog"}',
    current_timestamp - interval '33 days',
    null,
    current_timestamp - interval '8 days',
    15,
    5,
    0.00,
    null,
    current_timestamp - interval '33 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000014',
    'yuki.tanaka@example.com',
    'Yuki Tanaka',
    'subscribed',
    'free',
    'post',
    'b7000000-0000-0000-0000-00000000001c',
    'Japan',
    '{"community","interviews"}',
    current_timestamp - interval '66 days',
    null,
    current_timestamp - interval '9 days',
    24,
    8,
    0.00,
    null,
    current_timestamp - interval '66 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000015',
    'anna.kowalski@example.com',
    'Anna Kowalski',
    'subscribed',
    'free',
    'organic',
    null,
    'Poland',
    '{"storage","supabase"}',
    current_timestamp - interval '49 days',
    null,
    current_timestamp - interval '10 days',
    20,
    6,
    0.00,
    null,
    current_timestamp - interval '49 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000016',
    'karim.aziz@example.com',
    'Karim Aziz',
    'subscribed',
    'free',
    'post',
    'b7000000-0000-0000-0000-000000000020',
    'Egypt',
    '{"rls","tutorials"}',
    current_timestamp - interval '380 days',
    null,
    current_timestamp - interval '11 days',
    118,
    27,
    0.00,
    null,
    current_timestamp - interval '380 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000017',
    'nils.berger@example.com',
    'Nils Berger',
    'subscribed',
    'free',
    'organic',
    null,
    'Austria',
    '{"testing","sql"}',
    current_timestamp - interval '92 days',
    null,
    current_timestamp - interval '12 days',
    31,
    10,
    0.00,
    null,
    current_timestamp - interval '92 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000018',
    'clara.mendes@example.com',
    'Clara Mendes',
    'subscribed',
    'free',
    'import',
    null,
    'Brazil',
    '{"dashboards"}',
    current_timestamp - interval '230 days',
    null,
    current_timestamp - interval '1 days',
    58,
    13,
    0.00,
    null,
    current_timestamp - interval '230 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000019',
    'ravi.menon@example.com',
    'Ravi Menon',
    'subscribed',
    'free',
    'import',
    null,
    'India',
    '{"reports"}',
    current_timestamp - interval '230 days',
    null,
    current_timestamp - interval '2 days',
    47,
    9,
    0.00,
    null,
    current_timestamp - interval '230 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000001a',
    'jonas.weber@example.com',
    'Jonas Weber',
    'pending',
    'free',
    'organic',
    null,
    'Germany',
    '{"rbac"}',
    null,
    null,
    null,
    0,
    0,
    0.00,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '2 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000001b',
    'erik.solberg@example.com',
    'Erik Solberg',
    'pending',
    'free',
    'post',
    'b7000000-0000-0000-0000-000000000023',
    'Norway',
    '{"postgres"}',
    null,
    null,
    null,
    0,
    0,
    0.00,
    null,
    current_timestamp - interval '3 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000001c',
    'iris.novak@example.com',
    'Iris Novak',
    'pending',
    'free',
    'api',
    null,
    'Slovenia',
    '{"internals"}',
    null,
    null,
    null,
    0,
    0,
    0.00,
    null,
    current_timestamp - interval '4 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000001d',
    'ben.ortiz@example.com',
    'Ben Ortiz',
    'unsubscribed',
    'free',
    'organic',
    null,
    'Mexico',
    '{"changelog"}',
    current_timestamp - interval '300 days',
    current_timestamp - interval '75 days',
    current_timestamp - interval '150 days',
    34,
    3,
    0.00,
    null,
    current_timestamp - interval '300 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000001e',
    'deniz.aydin@example.com',
    'Deniz Aydin',
    'unsubscribed',
    'member',
    'organic',
    null,
    'Turkey',
    '{"performance"}',
    current_timestamp - interval '420 days',
    current_timestamp - interval '105 days',
    current_timestamp - interval '210 days',
    151,
    44,
    120.00,
    null,
    current_timestamp - interval '420 days'
  ),
  (
    'bc000000-0000-0000-0000-00000000001f',
    'guest.account@example.com',
    'Guest Account',
    'bounced',
    'free',
    'import',
    null,
    'Unknown',
    null,
    current_timestamp - interval '260 days',
    null,
    current_timestamp - interval '130 days',
    2,
    0,
    0.00,
    null,
    current_timestamp - interval '260 days'
  ),
  (
    'bc000000-0000-0000-0000-000000000020',
    'old.address@example.com',
    'Former Reader',
    'bounced',
    'free',
    'import',
    null,
    'Unknown',
    '{"engineering"}',
    current_timestamp - interval '340 days',
    null,
    current_timestamp - interval '170 days',
    17,
    1,
    0.00,
    null,
    current_timestamp - interval '340 days'
  );

----------------------------------------------------------------
-- Backdate the activity feed
--
-- blog.trg_posts_log_event and friends stamp occurred_at with
-- current_timestamp, so straight after seeding every timeline entry
-- shares the same second and the feed reads as one block. Each event
-- is moved onto the date it describes instead: creation follows the
-- post, publication follows published_at, revisions follow the
-- revision, comments follow the comment.
--
-- actor_id gets the same treatment. In the app the column default
-- auth.uid() captures whoever made the change; a seed file has no
-- session, so the events are attributed to the account that filed
-- the post.
----------------------------------------------------------------
update blog.post_events e
set
  occurred_at = case e.event_type
    when 'created' then p.created_at
    when 'published' then p.published_at
    when 'status_changed' then p.created_at + interval '3 days'
    when 'scheduled' then p.created_at + interval '5 days'
    when 'assigned' then p.created_at + interval '1 day'
    when 'record_updated' then coalesce(p.published_at, p.updated_at) - interval '1 day'
    else e.occurred_at
  end,
  actor_id = coalesce(e.actor_id, p.user_id)
from
  blog.posts p
where
  p.id = e.post_id
  and e.event_type <> 'revision_added'
  and e.event_type <> 'comment_added';

update blog.post_events e
set
  occurred_at = r.created_at,
  actor_id = coalesce(e.actor_id, r.user_id)
from
  blog.post_revisions r
where
  r.post_id = e.post_id
  and e.event_type = 'revision_added'
  and (e.metadata ->> 'version')::integer = r.version;

update blog.post_events e
set
  occurred_at = c.created_at,
  actor_id = coalesce(e.actor_id, c.user_id)
from
  blog.post_comments c
where
  e.event_type = 'comment_added'
  and (e.metadata ->> 'comment_id')::uuid = c.id;

----------------------------------------------------------------
-- Newsletter issues
--
-- Five sent, two scheduled and one draft, so the send calendar, the
-- pipeline kanban and the open-rate widget all have something to
-- show. Inserting a row as `sent` keeps the figures below;
-- blog.trg_newsletter_issues_before only freezes the audience size
-- when an existing issue is moved to sent, which is what the "Send
-- now" row action does.
----------------------------------------------------------------
insert into
  blog.newsletter_issues (
    id,
    title,
    subject,
    preview_text,
    body,
    status,
    audience,
    featured_post_id,
    author_id,
    scheduled_for,
    sent_at,
    recipient_count,
    open_rate,
    click_rate,
    unsubscribe_count,
    user_id,
    created_at
  )
values
  (
    'bd000000-0000-0000-0000-000000000001',
    'Issue 12: The schema is the product',
    'Why every feature is a migration',
    'Plus: the gantt view, and what we cut from the release.',
    '<p>This week we published the long version of an argument we have been making internally for two years: if the schema describes the product, everything above it is a copy waiting to drift.</p><p>Also in this issue: the gantt layout, and three row actions you can paste into your own project.</p>',
    'sent',
    'free',
    'b7000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    current_timestamp - interval '3 days',
    current_timestamp - interval '3 days',
    26,
    58.4,
    21.2,
    1,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '6 days'
  ),
  (
    'bd000000-0000-0000-0000-000000000002',
    'Issue 11: Ten minutes to your first resource',
    'One migration, one working screen',
    'The walkthrough we time ourselves against.',
    '<p>The getting-started track has been rewritten end to end, and we timed it: eleven minutes, two of which are reading.</p>',
    'sent',
    'free',
    'b7000000-0000-0000-0000-000000000017',
    'b3000000-0000-0000-0000-000000000005',
    current_timestamp - interval '17 days',
    current_timestamp - interval '17 days',
    25,
    61.2,
    24.8,
    0,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '20 days'
  ),
  (
    'bd000000-0000-0000-0000-000000000003',
    'Issue 10: Reading the planner',
    'EXPLAIN, line by line',
    'Estimate versus actual, and what to do about the gap.',
    '<p>Part two of the internals series is out. If you have ever stared at EXPLAIN output and felt nothing, start here.</p>',
    'sent',
    'free',
    'b7000000-0000-0000-0000-000000000012',
    'b3000000-0000-0000-0000-000000000004',
    current_timestamp - interval '31 days',
    current_timestamp - interval '31 days',
    24,
    55.9,
    19.4,
    2,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '34 days'
  ),
  (
    'bd000000-0000-0000-0000-000000000004',
    'Issue 9: We deleted the permissions table',
    'Two thousand fewer lines',
    'The refactor that removed a subsystem.',
    '<p>Four tables described something the database already knew. Here is what happened when we deleted all four.</p>',
    'sent',
    'free',
    'b7000000-0000-0000-0000-00000000001e',
    'b3000000-0000-0000-0000-000000000001',
    current_timestamp - interval '45 days',
    current_timestamp - interval '45 days',
    23,
    64.1,
    27.3,
    1,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '48 days'
  ),
  (
    'bd000000-0000-0000-0000-000000000005',
    'Issue 8: Inside the metadata catalog',
    'How the panel knows what it looks like',
    'For members: the four views the whole UI reads from.',
    '<p>A members-only deep dive into the catalog: four materialized views, one refresh function, and the reason your migration has to call it.</p>',
    'sent',
    'member',
    'b7000000-0000-0000-0000-000000000014',
    'b3000000-0000-0000-0000-000000000001',
    current_timestamp - interval '59 days',
    current_timestamp - interval '59 days',
    13,
    71.5,
    33.0,
    0,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '62 days'
  ),
  (
    'bd000000-0000-0000-0000-000000000006',
    'Issue 13: Launch week wrap-up',
    'Everything that shipped this week',
    'Six posts, one release, and the migrations to copy.',
    '<p>Launch week in one email: the gantt view, timelines, row actions and the two tutorials that came with them.</p>',
    'scheduled',
    'free',
    'b7000000-0000-0000-0000-000000000004',
    'b3000000-0000-0000-0000-000000000001',
    current_timestamp + interval '4 days' + interval '8 hours',
    null,
    0,
    null,
    null,
    0,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8',
    current_timestamp - interval '2 days'
  ),
  (
    'bd000000-0000-0000-0000-000000000007',
    'Members: precomputing your reports',
    'When the view is too slow to run live',
    'Materialized views, unique indexes and concurrent refreshes.',
    '<p>A members deep dive on turning a slow report into a materialized one without anybody noticing the switch.</p>',
    'scheduled',
    'member',
    'b7000000-0000-0000-0000-000000000006',
    'b3000000-0000-0000-0000-000000000002',
    current_timestamp + interval '9 days' + interval '8 hours',
    null,
    0,
    null,
    null,
    0,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '1 day'
  ),
  (
    'bd000000-0000-0000-0000-000000000008',
    'Issue 14: Picking a layout',
    'Six views, one table',
    'Draft — needs the decision tree graphic before it goes out.',
    '<p>Outline only. The post it points at is still scheduled, so this one waits.</p>',
    'draft',
    'free',
    'b7000000-0000-0000-0000-000000000005',
    'b3000000-0000-0000-0000-000000000003',
    null,
    null,
    0,
    null,
    null,
    0,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '12 hours'
  );

----------------------------------------------------------------
-- Populate the materialized view report's data. (This is the DATA
-- refresh — the CATALOG refresh, supasheet.refresh_metadata(), runs
-- at the end of the schema file and is not needed again here.)
----------------------------------------------------------------
refresh materialized view blog.post_traffic_rollup;
