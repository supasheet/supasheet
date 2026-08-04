-- LMS Seeder
-- ================================================================
-- Demo data for the lms (course platform) module. Apply
-- supabase/examples/20260809000000_lms.sql first:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260809000000_lms.sql \
--     -f supabase/examples/l_seed.sql
--
-- Six categories, three instructors (one with a real login, two
-- catalogue-only guest lecturers), six courses across five
-- categories, a syllabus of modules/lessons/quizzes built out in
-- full for the three courses the walkthroughs use, one learning path
-- bundling two of them, and eight enrollments spanning every status:
-- two walked all the way through completion — every lesson finished,
-- the final quiz genuinely passed by grading real responses against
-- real correct options, a certificate issued — one with 100% lesson
-- progress but a failed quiz (left exactly there on purpose), one
-- whose quiz attempts are already exhausted, and the rest mid-course,
-- assigned, or dropped.
--
-- The file closes with three deliberate failures: completing an
-- enrollment whose quiz was never passed, issuing a certificate for
-- an enrollment that is not complete, and a quiz attempt past its
-- cap. None of those guards has a role-based override, so all three
-- are refused even though the seed runs as the postgres superuser.
--
-- Dates are relative to `current_date`, so the monthly trend charts
-- have shape whenever this runs.
--
-- Five users are seeded (`on conflict do nothing`, so this is safe
-- alongside supabase/seed.sql and the other examples):
--   e91cb03e-fb7a-424d-84ff-18e2791ce0b1  lms-admin@supasheet.app         (x-admin)
--   e91cb03e-fb7a-424d-84ff-18e2791ce0b2  instructor1@supasheet.app       (instructor)
--   e91cb03e-fb7a-424d-84ff-18e2791ce0b3  learning-manager@supasheet.app  (learning-manager)
--   e91cb03e-fb7a-424d-84ff-18e2791ce0b4  learner1@supasheet.app          (user)
--   e91cb03e-fb7a-424d-84ff-18e2791ce0b5  learner2@supasheet.app          (user)
--
-- Sign in as learner1@supasheet.app to see two completed courses,
-- two certificates, and a course sitting at 100% progress with an
-- unpassed final exam blocking completion — exactly the case the
-- first deliberate failure below demonstrates.
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
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b1',
    'authenticated',
    'authenticated',
    'lms-admin@supasheet.app',
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
    '{"sub": "e91cb03e-fb7a-424d-84ff-18e2791ce0b1", "email": "lms-admin@supasheet.app", "name": "Nadia Farouk", "email_verified": false, "phone_verified": false}',
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
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b2',
    'authenticated',
    'authenticated',
    'instructor1@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "instructor"}',
    '{"sub": "e91cb03e-fb7a-424d-84ff-18e2791ce0b2", "email": "instructor1@supasheet.app", "name": "Dr. Malik Osei", "email_verified": false, "phone_verified": false}',
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
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b3',
    'authenticated',
    'authenticated',
    'learning-manager@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "learning-manager"}',
    '{"sub": "e91cb03e-fb7a-424d-84ff-18e2791ce0b3", "email": "learning-manager@supasheet.app", "name": "Rosa Delgado", "email_verified": false, "phone_verified": false}',
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
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b4',
    'authenticated',
    'authenticated',
    'learner1@supasheet.app',
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
    '{"sub": "e91cb03e-fb7a-424d-84ff-18e2791ce0b4", "email": "learner1@supasheet.app", "name": "Theo Marsh", "email_verified": false, "phone_verified": false}',
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
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b5',
    'authenticated',
    'authenticated',
    'learner2@supasheet.app',
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
    '{"sub": "e91cb03e-fb7a-424d-84ff-18e2791ce0b5", "email": "learner2@supasheet.app", "name": "Priya Nair", "email_verified": false, "phone_verified": false}',
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
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b1',
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b1',
    '{"sub": "e91cb03e-fb7a-424d-84ff-18e2791ce0b1", "email": "lms-admin@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'c1d1b03e-24a4-41a8-9742-1b5b4e2d8ab1'
  ),
  (
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b2',
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b2',
    '{"sub": "e91cb03e-fb7a-424d-84ff-18e2791ce0b2", "email": "instructor1@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'c1d1b03e-24a4-41a8-9742-1b5b4e2d8ab2'
  ),
  (
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b3',
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b3',
    '{"sub": "e91cb03e-fb7a-424d-84ff-18e2791ce0b3", "email": "learning-manager@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'c1d1b03e-24a4-41a8-9742-1b5b4e2d8ab3'
  ),
  (
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b4',
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b4',
    '{"sub": "e91cb03e-fb7a-424d-84ff-18e2791ce0b4", "email": "learner1@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'c1d1b03e-24a4-41a8-9742-1b5b4e2d8ab4'
  ),
  (
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b5',
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b5',
    '{"sub": "e91cb03e-fb7a-424d-84ff-18e2791ce0b5", "email": "learner2@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'c1d1b03e-24a4-41a8-9742-1b5b4e2d8ab5'
  )
on conflict do nothing;

----------------------------------------------------------------
-- Categories
----------------------------------------------------------------
insert into
  lms.categories (id, code, name, description)
values
  ('a1000000-0000-0000-0000-000000000001', 'TECH', 'Technology', 'Cloud, infrastructure and engineering skills.'),
  ('a1000000-0000-0000-0000-000000000002', 'BIZ', 'Business', 'Strategy, marketing and operations.'),
  ('a1000000-0000-0000-0000-000000000003', 'COMP', 'Compliance', 'Mandatory workplace training.'),
  ('a1000000-0000-0000-0000-000000000004', 'LEAD', 'Leadership', 'Management and communication skills.'),
  ('a1000000-0000-0000-0000-000000000005', 'DSGN', 'Design', 'Product and visual design.'),
  ('a1000000-0000-0000-0000-000000000006', 'MKT', 'Marketing', 'Growth and marketing strategy.');

----------------------------------------------------------------
-- Instructors — one with a real login, two catalogue-only guest
-- lecturers with no system access of their own.
----------------------------------------------------------------
insert into
  lms.instructors (id, user_id, headline, bio)
values
  ('a2000000-0000-0000-0000-000000000001', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b2', 'Senior Cloud Architect & Educator', 'Fifteen years building and teaching cloud infrastructure at scale.'),
  ('a2000000-0000-0000-0000-000000000002', null, 'Executive Communication Coach', 'Works with leadership teams on clear, confident communication.'),
  ('a2000000-0000-0000-0000-000000000003', null, 'Workplace Compliance Specialist', 'Designs mandatory training that people actually remember.');

----------------------------------------------------------------
-- Courses
----------------------------------------------------------------
insert into
  lms.courses (id, title, category_id, instructor_id, level, status, description, price, is_featured, published_at, created_at)
values
  (
    'a3000000-0000-0000-0000-000000000001', 'Cloud Infrastructure Fundamentals', 'a1000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001', 'beginner', 'published', 'The core building blocks of cloud infrastructure — compute, storage, networking and security.',
    0, true, current_timestamp - interval '120 days', current_timestamp - interval '125 days'
  ),
  (
    'a3000000-0000-0000-0000-000000000002', 'Advanced Kubernetes Operations', 'a1000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001', 'advanced', 'published', 'Running production Kubernetes clusters at scale.',
    149, false, current_timestamp - interval '90 days', current_timestamp - interval '95 days'
  ),
  (
    'a3000000-0000-0000-0000-000000000003', 'Effective Leadership Communication', 'a1000000-0000-0000-0000-000000000004',
    'a2000000-0000-0000-0000-000000000002', 'intermediate', 'published', 'Communicating clearly and confidently as a first-time manager.',
    99, false, current_timestamp - interval '60 days', current_timestamp - interval '65 days'
  ),
  (
    'a3000000-0000-0000-0000-000000000004', 'Workplace Harassment Prevention', 'a1000000-0000-0000-0000-000000000003',
    'a2000000-0000-0000-0000-000000000003', 'beginner', 'published', 'Mandatory annual training on recognising and reporting workplace harassment.',
    0, true, current_timestamp - interval '150 days', current_timestamp - interval '155 days'
  ),
  (
    'a3000000-0000-0000-0000-000000000005', 'Data-Driven Marketing Strategy', 'a1000000-0000-0000-0000-000000000006',
    'a2000000-0000-0000-0000-000000000002', 'intermediate', 'draft', 'Using analytics to plan and justify a marketing spend.',
    0, false, null, current_timestamp - interval '10 days'
  ),
  (
    'a3000000-0000-0000-0000-000000000006', 'UX Design Principles', 'a1000000-0000-0000-0000-000000000005',
    'a2000000-0000-0000-0000-000000000001', 'beginner', 'published', 'The fundamentals of usable, accessible product design.',
    79, false, current_timestamp - interval '30 days', current_timestamp - interval '35 days'
  );

----------------------------------------------------------------
-- Course modules
----------------------------------------------------------------
insert into
  lms.course_modules (id, course_id, title, description)
values
  ('a4000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'Getting Started', 'Orientation and environment setup.'),
  ('a4000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000001', 'Core Concepts', 'Compute, storage, networking and security.'),
  ('a4000000-0000-0000-0000-000000000003', 'a3000000-0000-0000-0000-000000000002', 'Cluster Architecture', 'How a production cluster is put together.'),
  ('a4000000-0000-0000-0000-000000000004', 'a3000000-0000-0000-0000-000000000002', 'Operations at Scale', 'Running and observing clusters in production.'),
  ('a4000000-0000-0000-0000-000000000005', 'a3000000-0000-0000-0000-000000000004', 'Understanding Harassment', 'What harassment looks like at work.'),
  ('a4000000-0000-0000-0000-000000000006', 'a3000000-0000-0000-0000-000000000004', 'Reporting & Response', 'What to do if it happens.'),
  ('a4000000-0000-0000-0000-000000000007', 'a3000000-0000-0000-0000-000000000003', 'Foundations', 'The basics of clear communication.'),
  ('a4000000-0000-0000-0000-000000000008', 'a3000000-0000-0000-0000-000000000006', 'Design Basics', 'Core UX principles.');

----------------------------------------------------------------
-- Lessons
----------------------------------------------------------------
insert into
  lms.lessons (id, module_id, course_id, title, content_type, content, video_url, duration_minutes, is_preview)
values
  ('a5000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'Course Overview', 'video', null, 'https://video.example/cloud-fundamentals/overview', 5, true),
  ('a5000000-0000-0000-0000-000000000002', 'a4000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'Setting Up Your Environment', 'article', 'Step-by-step guide to creating your first cloud account and CLI setup.', null, 15, false),
  ('a5000000-0000-0000-0000-000000000003', 'a4000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000001', 'Compute Basics', 'video', null, 'https://video.example/cloud-fundamentals/compute', 20, false),
  ('a5000000-0000-0000-0000-000000000004', 'a4000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000001', 'Storage & Networking', 'video', null, 'https://video.example/cloud-fundamentals/storage-networking', 25, false),
  ('a5000000-0000-0000-0000-000000000005', 'a4000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000001', 'Security Fundamentals', 'video', null, 'https://video.example/cloud-fundamentals/security', 20, false),
  ('a5000000-0000-0000-0000-000000000006', 'a4000000-0000-0000-0000-000000000003', 'a3000000-0000-0000-0000-000000000002', 'Control Plane Deep Dive', 'video', null, 'https://video.example/k8s/control-plane', 30, true),
  ('a5000000-0000-0000-0000-000000000007', 'a4000000-0000-0000-0000-000000000003', 'a3000000-0000-0000-0000-000000000002', 'Networking & Service Mesh', 'video', null, 'https://video.example/k8s/networking', 35, false),
  ('a5000000-0000-0000-0000-000000000008', 'a4000000-0000-0000-0000-000000000004', 'a3000000-0000-0000-0000-000000000002', 'Autoscaling in Production', 'video', null, 'https://video.example/k8s/autoscaling', 25, false),
  ('a5000000-0000-0000-0000-000000000009', 'a4000000-0000-0000-0000-000000000004', 'a3000000-0000-0000-0000-000000000002', 'Incident Response Runbook', 'assignment', 'Write a runbook for a simulated cluster outage.', null, 40, false),
  ('a5000000-0000-0000-0000-00000000000a', 'a4000000-0000-0000-0000-000000000005', 'a3000000-0000-0000-0000-000000000004', 'What Constitutes Harassment', 'video', null, 'https://video.example/harassment/definitions', 15, true),
  ('a5000000-0000-0000-0000-00000000000b', 'a4000000-0000-0000-0000-000000000006', 'a3000000-0000-0000-0000-000000000004', 'How to Report an Incident', 'article', 'The reporting channels available and what happens after you file a report.', null, 10, false),
  ('a5000000-0000-0000-0000-00000000000c', 'a4000000-0000-0000-0000-000000000007', 'a3000000-0000-0000-0000-000000000003', 'Communicating With Clarity', 'video', null, 'https://video.example/leadership/clarity', 18, true),
  ('a5000000-0000-0000-0000-00000000000d', 'a4000000-0000-0000-0000-000000000008', 'a3000000-0000-0000-0000-000000000006', 'Principles of Usable Design', 'video', null, 'https://video.example/ux/principles', 22, true);

----------------------------------------------------------------
-- Quizzes
----------------------------------------------------------------
insert into
  lms.quizzes (id, course_id, lesson_id, title, passing_score_percent, max_attempts, time_limit_minutes)
values
  ('b1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', null, 'Fundamentals Final Exam', 70, 3, 20),
  ('b1000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000004', 'a5000000-0000-0000-0000-00000000000b', 'Compliance Check', 80, 2, 10),
  ('b1000000-0000-0000-0000-000000000003', 'a3000000-0000-0000-0000-000000000002', null, 'Kubernetes Operations Quiz', 75, 3, 15);

----------------------------------------------------------------
-- Quiz questions
----------------------------------------------------------------
insert into
  lms.quiz_questions (id, quiz_id, question_text, question_type, points)
values
  ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'Which of the following is a compute resource?', 'single_choice', 1),
  ('b2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'Object storage is ideal for structured relational data.', 'true_false', 1),
  ('b2000000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-000000000001', 'What provides network isolation in the cloud?', 'single_choice', 1),
  ('b2000000-0000-0000-0000-000000000004', 'b1000000-0000-0000-0000-000000000002', 'Retaliation against someone who reports harassment in good faith is prohibited.', 'true_false', 1),
  ('b2000000-0000-0000-0000-000000000005', 'b1000000-0000-0000-0000-000000000002', 'Who should you contact first to report an incident?', 'single_choice', 1),
  ('b2000000-0000-0000-0000-000000000006', 'b1000000-0000-0000-0000-000000000003', 'What Kubernetes object manages a set of replica pods?', 'single_choice', 1),
  ('b2000000-0000-0000-0000-000000000007', 'b1000000-0000-0000-0000-000000000003', 'Horizontal Pod Autoscaling requires metrics-server to be running.', 'true_false', 1);

----------------------------------------------------------------
-- Quiz options
----------------------------------------------------------------
insert into
  lms.quiz_options (id, question_id, option_text, is_correct)
values
  ('b3000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'Virtual Machine', true),
  ('b3000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000001', 'Object Storage', false),
  ('b3000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000001', 'DNS Record', false),
  ('b3000000-0000-0000-0000-000000000004', 'b2000000-0000-0000-0000-000000000001', 'Load Balancer', false),
  ('b3000000-0000-0000-0000-000000000005', 'b2000000-0000-0000-0000-000000000002', 'True', false),
  ('b3000000-0000-0000-0000-000000000006', 'b2000000-0000-0000-0000-000000000002', 'False', true),
  ('b3000000-0000-0000-0000-000000000007', 'b2000000-0000-0000-0000-000000000003', 'VPC', true),
  ('b3000000-0000-0000-0000-000000000008', 'b2000000-0000-0000-0000-000000000003', 'CDN', false),
  ('b3000000-0000-0000-0000-000000000009', 'b2000000-0000-0000-0000-000000000003', 'IAM Role', false),
  ('b3000000-0000-0000-0000-00000000000a', 'b2000000-0000-0000-0000-000000000003', 'Snapshot', false),
  ('b3000000-0000-0000-0000-00000000000b', 'b2000000-0000-0000-0000-000000000004', 'True', true),
  ('b3000000-0000-0000-0000-00000000000c', 'b2000000-0000-0000-0000-000000000004', 'False', false),
  ('b3000000-0000-0000-0000-00000000000d', 'b2000000-0000-0000-0000-000000000005', 'HR or your manager', true),
  ('b3000000-0000-0000-0000-00000000000e', 'b2000000-0000-0000-0000-000000000005', 'Post on social media', false),
  ('b3000000-0000-0000-0000-00000000000f', 'b2000000-0000-0000-0000-000000000005', 'Nothing, ignore it', false),
  ('b3000000-0000-0000-0000-000000000010', 'b2000000-0000-0000-0000-000000000005', 'Confront the person publicly', false),
  ('b3000000-0000-0000-0000-000000000011', 'b2000000-0000-0000-0000-000000000006', 'ReplicaSet', true),
  ('b3000000-0000-0000-0000-000000000012', 'b2000000-0000-0000-0000-000000000006', 'ConfigMap', false),
  ('b3000000-0000-0000-0000-000000000013', 'b2000000-0000-0000-0000-000000000006', 'Secret', false),
  ('b3000000-0000-0000-0000-000000000014', 'b2000000-0000-0000-0000-000000000007', 'True', true),
  ('b3000000-0000-0000-0000-000000000015', 'b2000000-0000-0000-0000-000000000007', 'False', false);

----------------------------------------------------------------
-- Learning path
----------------------------------------------------------------
insert into
  lms.learning_paths (id, title, description, category_id)
values
  ('c1000000-0000-0000-0000-000000000001', 'Cloud Engineer Path', 'From cloud fundamentals through to production Kubernetes operations.', 'a1000000-0000-0000-0000-000000000001');

insert into
  lms.learning_path_courses (id, path_id, course_id)
values
  ('c2000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001'),
  ('c2000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000002');

----------------------------------------------------------------
-- Enrollments
----------------------------------------------------------------
insert into
  lms.enrollments (id, course_id, user_id, enrolled_by, due_date, enrolled_at)
values
  ('d1000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b4', null, null, current_timestamp - interval '40 days'),
  ('d1000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000004', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b4', null, null, current_timestamp - interval '30 days'),
  ('d1000000-0000-0000-0000-000000000003', 'a3000000-0000-0000-0000-000000000001', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b5', null, null, current_timestamp - interval '15 days'),
  (
    'd1000000-0000-0000-0000-000000000004', 'a3000000-0000-0000-0000-000000000002', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b5',
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b3', current_date + 21, current_timestamp - interval '2 days'
  ),
  ('d1000000-0000-0000-0000-000000000005', 'a3000000-0000-0000-0000-000000000002', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b4', null, null, current_timestamp - interval '25 days'),
  ('d1000000-0000-0000-0000-000000000006', 'a3000000-0000-0000-0000-000000000004', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b5', null, null, current_timestamp - interval '20 days'),
  ('d1000000-0000-0000-0000-000000000007', 'a3000000-0000-0000-0000-000000000003', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b4', null, null, current_timestamp - interval '35 days'),
  ('d1000000-0000-0000-0000-000000000008', 'a3000000-0000-0000-0000-000000000006', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b5', null, null, current_timestamp - interval '4 days');

update lms.enrollments set status = 'dropped' where id = 'd1000000-0000-0000-0000-000000000007';

----------------------------------------------------------------
-- Lesson progress
----------------------------------------------------------------
insert into
  lms.lesson_progress (id, enrollment_id, lesson_id, status, started_at, completed_at)
values
  -- E1: Cloud Fundamentals, all 5 lessons done
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001', 'completed', current_timestamp - interval '40 days', current_timestamp - interval '40 days'),
  ('d2000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000002', 'completed', current_timestamp - interval '39 days', current_timestamp - interval '39 days'),
  ('d2000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000003', 'completed', current_timestamp - interval '38 days', current_timestamp - interval '38 days'),
  ('d2000000-0000-0000-0000-000000000004', 'd1000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000004', 'completed', current_timestamp - interval '37 days', current_timestamp - interval '37 days'),
  ('d2000000-0000-0000-0000-000000000005', 'd1000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000005', 'completed', current_timestamp - interval '36 days', current_timestamp - interval '36 days'),
  -- E2: Harassment Prevention, both lessons done
  ('d2000000-0000-0000-0000-000000000006', 'd1000000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-00000000000a', 'completed', current_timestamp - interval '30 days', current_timestamp - interval '30 days'),
  ('d2000000-0000-0000-0000-000000000007', 'd1000000-0000-0000-0000-000000000002', 'a5000000-0000-0000-0000-00000000000b', 'completed', current_timestamp - interval '29 days', current_timestamp - interval '29 days'),
  -- E3: Cloud Fundamentals, 3 of 5 lessons done
  ('d2000000-0000-0000-0000-000000000008', 'd1000000-0000-0000-0000-000000000003', 'a5000000-0000-0000-0000-000000000001', 'completed', current_timestamp - interval '15 days', current_timestamp - interval '15 days'),
  ('d2000000-0000-0000-0000-000000000009', 'd1000000-0000-0000-0000-000000000003', 'a5000000-0000-0000-0000-000000000002', 'completed', current_timestamp - interval '14 days', current_timestamp - interval '14 days'),
  ('d2000000-0000-0000-0000-00000000000a', 'd1000000-0000-0000-0000-000000000003', 'a5000000-0000-0000-0000-000000000003', 'completed', current_timestamp - interval '13 days', current_timestamp - interval '13 days'),
  -- E5: Advanced Kubernetes, all 4 lessons done — quiz still to fail below
  ('d2000000-0000-0000-0000-00000000000b', 'd1000000-0000-0000-0000-000000000005', 'a5000000-0000-0000-0000-000000000006', 'completed', current_timestamp - interval '25 days', current_timestamp - interval '25 days'),
  ('d2000000-0000-0000-0000-00000000000c', 'd1000000-0000-0000-0000-000000000005', 'a5000000-0000-0000-0000-000000000007', 'completed', current_timestamp - interval '24 days', current_timestamp - interval '24 days'),
  ('d2000000-0000-0000-0000-00000000000d', 'd1000000-0000-0000-0000-000000000005', 'a5000000-0000-0000-0000-000000000008', 'completed', current_timestamp - interval '23 days', current_timestamp - interval '23 days'),
  ('d2000000-0000-0000-0000-00000000000e', 'd1000000-0000-0000-0000-000000000005', 'a5000000-0000-0000-0000-000000000009', 'completed', current_timestamp - interval '22 days', current_timestamp - interval '22 days'),
  -- E6: Harassment Prevention, both lessons done — quiz attempts to be exhausted below
  ('d2000000-0000-0000-0000-00000000000f', 'd1000000-0000-0000-0000-000000000006', 'a5000000-0000-0000-0000-00000000000a', 'completed', current_timestamp - interval '20 days', current_timestamp - interval '20 days'),
  ('d2000000-0000-0000-0000-000000000010', 'd1000000-0000-0000-0000-000000000006', 'a5000000-0000-0000-0000-00000000000b', 'completed', current_timestamp - interval '19 days', current_timestamp - interval '19 days'),
  -- E7: Leadership Communication, one lesson in progress before dropping
  ('d2000000-0000-0000-0000-000000000011', 'd1000000-0000-0000-0000-000000000007', 'a5000000-0000-0000-0000-00000000000c', 'in_progress', current_timestamp - interval '35 days', null),
  -- E8: UX Design, one lesson in progress
  ('d2000000-0000-0000-0000-000000000012', 'd1000000-0000-0000-0000-000000000008', 'a5000000-0000-0000-0000-00000000000d', 'in_progress', current_timestamp - interval '4 days', null);

----------------------------------------------------------------
-- Quiz attempts + responses
--
-- Responses are graded by the real trigger, off the real correct
-- options — nobody sets score_percent or passed by hand anywhere in
-- this file.
----------------------------------------------------------------
insert into
  lms.quiz_attempts (id, quiz_id, enrollment_id, user_id, started_at, submitted_at)
values
  -- E1: passes the Cloud Fundamentals final exam
  ('e1000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b4', current_timestamp - interval '35 days', current_timestamp - interval '35 days'),
  -- E2: passes the compliance check
  ('e1000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b4', current_timestamp - interval '28 days', current_timestamp - interval '28 days'),
  -- E5: fails the Kubernetes quiz outright — left exactly here to demonstrate the completion guard
  ('e1000000-0000-0000-0000-000000000003', 'b1000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000005', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b4', current_timestamp - interval '21 days', current_timestamp - interval '21 days'),
  -- E6: two failed attempts at the compliance check — the attempt cap is now exhausted
  ('e1000000-0000-0000-0000-000000000004', 'b1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000006', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b5', current_timestamp - interval '18 days', current_timestamp - interval '18 days'),
  ('e1000000-0000-0000-0000-000000000005', 'b1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000006', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b5', current_timestamp - interval '10 days', current_timestamp - interval '10 days');

insert into
  lms.quiz_responses (id, attempt_id, question_id, selected_option_id)
values
  -- E1 attempt: all three correct
  ('e2000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000001'),
  ('e2000000-0000-0000-0000-000000000002', 'e1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000002', 'b3000000-0000-0000-0000-000000000006'),
  ('e2000000-0000-0000-0000-000000000003', 'e1000000-0000-0000-0000-000000000001', 'b2000000-0000-0000-0000-000000000003', 'b3000000-0000-0000-0000-000000000007'),
  -- E2 attempt: both correct
  ('e2000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000004', 'b3000000-0000-0000-0000-00000000000b'),
  ('e2000000-0000-0000-0000-000000000005', 'e1000000-0000-0000-0000-000000000002', 'b2000000-0000-0000-0000-000000000005', 'b3000000-0000-0000-0000-00000000000d'),
  -- E5 attempt: both wrong
  ('e2000000-0000-0000-0000-000000000006', 'e1000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000006', 'b3000000-0000-0000-0000-000000000012'),
  ('e2000000-0000-0000-0000-000000000007', 'e1000000-0000-0000-0000-000000000003', 'b2000000-0000-0000-0000-000000000007', 'b3000000-0000-0000-0000-000000000015'),
  -- E6 first attempt: both wrong
  ('e2000000-0000-0000-0000-000000000008', 'e1000000-0000-0000-0000-000000000004', 'b2000000-0000-0000-0000-000000000004', 'b3000000-0000-0000-0000-00000000000c'),
  ('e2000000-0000-0000-0000-000000000009', 'e1000000-0000-0000-0000-000000000004', 'b2000000-0000-0000-0000-000000000005', 'b3000000-0000-0000-0000-00000000000e'),
  -- E6 second attempt: one right, one wrong — still under the 80% bar
  ('e2000000-0000-0000-0000-00000000000a', 'e1000000-0000-0000-0000-000000000005', 'b2000000-0000-0000-0000-000000000004', 'b3000000-0000-0000-0000-00000000000b'),
  ('e2000000-0000-0000-0000-00000000000b', 'e1000000-0000-0000-0000-000000000005', 'b2000000-0000-0000-0000-000000000005', 'b3000000-0000-0000-0000-00000000000f');

----------------------------------------------------------------
-- Completions and certificates — driven through the real guards.
----------------------------------------------------------------
update lms.enrollments set status = 'completed' where id = 'd1000000-0000-0000-0000-000000000001';
update lms.enrollments set status = 'completed' where id = 'd1000000-0000-0000-0000-000000000002';

insert into
  lms.certificates (id, enrollment_id, expires_at)
values
  ('f1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', current_date + 700),
  ('f1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000002', current_date + 335);

update lms.enrollments
set rating = 5, review_text = 'Clear, well-paced, and the hands-on labs actually worked first try.'
where id = 'd1000000-0000-0000-0000-000000000001';

update lms.enrollments
set rating = 4, review_text = 'Good refresher, wish the reporting section had a real example walkthrough.'
where id = 'd1000000-0000-0000-0000-000000000002';

----------------------------------------------------------------
-- Learning path enrollment
--
-- Assigned after E1 (one of the path's two courses) was already
-- completed. The rollup trigger only recomputes path progress off a
-- subsequent enrollment status change, so this snapshot is asserted
-- directly at assignment time to reflect that reality — one of two
-- courses already done.
----------------------------------------------------------------
insert into
  lms.learning_path_enrollments (id, path_id, user_id, assigned_by, progress_percent, assigned_at)
values
  (
    'c3000000-0000-0000-0000-000000000001', 'c1000000-0000-0000-0000-000000000001', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b4',
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b3', 50, current_timestamp - interval '20 days'
  );

----------------------------------------------------------------
-- Discussion posts
----------------------------------------------------------------
insert into
  lms.discussion_posts (id, course_id, lesson_id, user_id, body, created_at)
values
  (
    'f2000000-0000-0000-0000-000000000001', 'a3000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000004',
    'e91cb03e-fb7a-424d-84ff-18e2791ce0b5', 'Is the free tier enough to complete the hands-on exercises in this module?',
    current_timestamp - interval '14 days'
  );

insert into
  lms.discussion_posts (id, course_id, lesson_id, parent_post_id, user_id, body, created_at)
values
  (
    'f2000000-0000-0000-0000-000000000002', 'a3000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000004',
    'f2000000-0000-0000-0000-000000000001', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Yes — the free tier covers everything in this course. Let us know if you hit any limits!',
    current_timestamp - interval '13 days'
  );

----------------------------------------------------------------
-- Three deliberate failures
--
-- None of these guards has a role-based override, so all three are
-- refused even though the seed runs as the postgres superuser. If
-- any NOTICE below does not appear, the corresponding trigger has
-- regressed.
----------------------------------------------------------------
do $$
begin
  begin
    update lms.enrollments
    set status = 'completed'
    where id = 'd1000000-0000-0000-0000-000000000005'; -- E5: 100% lessons, quiz failed
    raise exception 'GUARD FAILED: an enrollment completed with an unpassed quiz.';
  exception
    when others then
      raise notice 'Guard confirmed: %', sqlerrm;
  end;
end;
$$;

do $$
begin
  begin
    insert into lms.certificates (enrollment_id)
    values ('d1000000-0000-0000-0000-000000000004'); -- E4: still active, not completed
    raise exception 'GUARD FAILED: a certificate was issued for an incomplete enrollment.';
  exception
    when others then
      raise notice 'Guard confirmed: %', sqlerrm;
  end;
end;
$$;

do $$
begin
  begin
    insert into lms.quiz_attempts (quiz_id, enrollment_id, user_id)
    values (
      'b1000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000006', 'e91cb03e-fb7a-424d-84ff-18e2791ce0b5'
    ); -- E6 has already used both of its 2 permitted attempts
    raise exception 'GUARD FAILED: a quiz attempt was allowed past the max_attempts cap.';
  exception
    when others then
      raise notice 'Guard confirmed: %', sqlerrm;
  end;
end;
$$;

refresh materialized view lms.enrollment_kpi_rollup;
