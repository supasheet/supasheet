-- PM Seeder
-- ================================================================
-- Demo data for the pm (project management / professional services)
-- module. Apply supabase/examples/20260810000000_pm.sql first:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260810000000_pm.sql \
--     -f supabase/examples/pm_seed.sql
--
-- Three clients (one with a live client-portal login), four projects
-- spanning every budget type and status, a phased task board with a
-- real dependency chain on the flagship project, time entries walked
-- through submit -> approve so the budget rollup is real, one
-- project deliberately run to 95% of its budgeted hours, two
-- milestones (one already invoiced), an invoice built from real
-- approved time and a real milestone with a partial payment against
-- it, two risks (one scoring high enough to notify), and two status
-- reports — the second is what actually turns the project amber,
-- since nothing else is allowed to.
--
-- The file closes with four deliberate failures: a task dependency
-- that would close a cycle, marking a task done while its blocker is
-- still open, approving a time entry that would push a capped
-- project over budget, and invoicing a time entry a second time.
-- None of those guards has a role-based override on the first two;
-- the budget one does (x-admin only) and is still refused here since
-- the seed intentionally does not invoke it.
--
-- Dates are relative to `current_date`, so the monthly trend charts
-- have shape whenever this runs.
--
-- Five users are seeded (`on conflict do nothing`, so this is safe
-- alongside supabase/seed.sql and the other examples):
--   f03db03e-fb7a-424d-84ff-18e2791ce0b1  delivery-director@supasheet.app (x-admin)
--   f03db03e-fb7a-424d-84ff-18e2791ce0b2  pm-lead1@supasheet.app          (pm-lead)
--   f03db03e-fb7a-424d-84ff-18e2791ce0b3  consultant1@supasheet.app       (user)
--   f03db03e-fb7a-424d-84ff-18e2791ce0b4  consultant2@supasheet.app       (user)
--   f03db03e-fb7a-424d-84ff-18e2791ce0b5  client-portal@supasheet.app     (client)
--
-- Sign in as pm-lead1@supasheet.app for the DAY-TO-DAY DELIVERY seat:
-- staffing, budget, invoicing, and the risk register.
-- client-portal@supasheet.app is Acme Robotics' own login — status
-- reports, milestones, deliverables and invoices for their projects
-- only, and the power to approve or reject a deliverable.
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
    'f03db03e-fb7a-424d-84ff-18e2791ce0b1',
    'authenticated',
    'authenticated',
    'delivery-director@supasheet.app',
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
    '{"sub": "f03db03e-fb7a-424d-84ff-18e2791ce0b1", "email": "delivery-director@supasheet.app", "name": "Vera Lindholm", "email_verified": false, "phone_verified": false}',
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
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    'authenticated',
    'authenticated',
    'pm-lead1@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "pm-lead"}',
    '{"sub": "f03db03e-fb7a-424d-84ff-18e2791ce0b2", "email": "pm-lead1@supasheet.app", "name": "Marcus Bell", "email_verified": false, "phone_verified": false}',
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
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    'authenticated',
    'authenticated',
    'consultant1@supasheet.app',
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
    '{"sub": "f03db03e-fb7a-424d-84ff-18e2791ce0b3", "email": "consultant1@supasheet.app", "name": "Ines Dubois", "email_verified": false, "phone_verified": false}',
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
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    'authenticated',
    'authenticated',
    'consultant2@supasheet.app',
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
    '{"sub": "f03db03e-fb7a-424d-84ff-18e2791ce0b4", "email": "consultant2@supasheet.app", "name": "Jonas Weber", "email_verified": false, "phone_verified": false}',
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
    'f03db03e-fb7a-424d-84ff-18e2791ce0b5',
    'authenticated',
    'authenticated',
    'client-portal@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "client"}',
    '{"sub": "f03db03e-fb7a-424d-84ff-18e2791ce0b5", "email": "client-portal@supasheet.app", "name": "Renee Castillo", "email_verified": false, "phone_verified": false}',
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
    'f03db03e-fb7a-424d-84ff-18e2791ce0b1',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b1',
    '{"sub": "f03db03e-fb7a-424d-84ff-18e2791ce0b1", "email": "delivery-director@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'd03eb03e-24a4-41a8-9742-1b5b4e2d8ab1'
  ),
  (
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    '{"sub": "f03db03e-fb7a-424d-84ff-18e2791ce0b2", "email": "pm-lead1@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'd03eb03e-24a4-41a8-9742-1b5b4e2d8ab2'
  ),
  (
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    '{"sub": "f03db03e-fb7a-424d-84ff-18e2791ce0b3", "email": "consultant1@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'd03eb03e-24a4-41a8-9742-1b5b4e2d8ab3'
  ),
  (
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    '{"sub": "f03db03e-fb7a-424d-84ff-18e2791ce0b4", "email": "consultant2@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'd03eb03e-24a4-41a8-9742-1b5b4e2d8ab4'
  ),
  (
    'f03db03e-fb7a-424d-84ff-18e2791ce0b5',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b5',
    '{"sub": "f03db03e-fb7a-424d-84ff-18e2791ce0b5", "email": "client-portal@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'd03eb03e-24a4-41a8-9742-1b5b4e2d8ab5'
  )
on conflict do nothing;

----------------------------------------------------------------
-- Clients
----------------------------------------------------------------
insert into
  pm.clients (
    id,
    code,
    name,
    contact_name,
    contact_email,
    industry,
    portal_user_id
  )
values
  (
    'a1000000-0000-0000-0000-000000000001',
    'ACME',
    'Acme Robotics',
    'Renee Castillo',
    'renee.castillo@acmerobotics.example',
    'Manufacturing',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b5'
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    'MERIDIAN',
    'Meridian Health',
    'David Osei',
    'david.osei@meridianhealth.example',
    'Healthcare',
    null
  ),
  (
    'a1000000-0000-0000-0000-000000000003',
    'NORTHWIND',
    'Northwind Retail',
    'Lucia Fontaine',
    'lucia.fontaine@northwindretail.example',
    'Retail',
    null
  );

insert into
  pm.client_billing (
    client_id,
    billing_address,
    default_hourly_rate,
    default_cost_rate,
    payment_terms_days
  )
values
  (
    'a1000000-0000-0000-0000-000000000001',
    '400 Foundry Way, Detroit, MI',
    175,
    90,
    30
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    '12 Harbor Health Blvd, Boston, MA',
    160,
    85,
    30
  ),
  (
    'a1000000-0000-0000-0000-000000000003',
    '88 Commerce St, Chicago, IL',
    150,
    80,
    45
  );

----------------------------------------------------------------
-- Projects
----------------------------------------------------------------
insert into
  pm.projects (
    id,
    name,
    client_id,
    pm_lead_id,
    status,
    budget_type,
    budget_amount,
    budget_hours,
    start_date,
    end_date,
    description
  )
values
  (
    'a2000000-0000-0000-0000-000000000001',
    'Robotics Fleet Management Platform',
    'a1000000-0000-0000-0000-000000000001',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    'active',
    'time_and_materials',
    150000,
    800,
    current_date - 70,
    current_date + 110,
    'A telemetry and fleet-management platform for Acme''s warehouse robots.'
  ),
  (
    'a2000000-0000-0000-0000-000000000002',
    'Patient Portal Redesign',
    'a1000000-0000-0000-0000-000000000002',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    'active',
    'fixed',
    80000,
    null,
    current_date - 40,
    current_date + 50,
    'A fixed-price redesign of the Meridian patient portal.'
  ),
  (
    'a2000000-0000-0000-0000-000000000003',
    'Inventory Sync Integration',
    'a1000000-0000-0000-0000-000000000001',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    'active',
    'time_and_materials',
    40000,
    200,
    current_date - 30,
    current_date + 30,
    'A connector syncing warehouse inventory counts with the new fleet platform.'
  ),
  (
    'a2000000-0000-0000-0000-000000000004',
    'Loyalty Program Pilot',
    'a1000000-0000-0000-0000-000000000003',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    'planning',
    'retainer',
    25000,
    null,
    null,
    null,
    'A pilot loyalty program for a handful of Northwind stores.'
  );

----------------------------------------------------------------
-- Project members
----------------------------------------------------------------
insert into
  pm.project_members (
    project_id,
    user_id,
    role_on_project,
    billable_rate,
    cost_rate,
    allocation_percent
  )
values
  (
    'a2000000-0000-0000-0000-000000000001',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    'Project Manager',
    200,
    100,
    30
  ),
  (
    'a2000000-0000-0000-0000-000000000001',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    'Senior Engineer',
    175,
    90,
    80
  ),
  (
    'a2000000-0000-0000-0000-000000000001',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    'Engineer',
    140,
    70,
    100
  ),
  (
    'a2000000-0000-0000-0000-000000000002',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    'Project Manager',
    200,
    100,
    20
  ),
  (
    'a2000000-0000-0000-0000-000000000002',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    'Product Designer',
    160,
    85,
    50
  ),
  (
    'a2000000-0000-0000-0000-000000000003',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    'Project Manager',
    200,
    100,
    10
  ),
  (
    'a2000000-0000-0000-0000-000000000003',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    'Integration Engineer',
    150,
    78,
    60
  ),
  (
    'a2000000-0000-0000-0000-000000000004',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    'Project Manager',
    200,
    100,
    10
  );

----------------------------------------------------------------
-- Phases
----------------------------------------------------------------
insert into
  pm.phases (
    id,
    project_id,
    name,
    start_date,
    end_date,
    status
  )
values
  (
    'a3000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001',
    'Discovery',
    current_date - 70,
    current_date - 45,
    'completed'
  ),
  (
    'a3000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000001',
    'Build',
    current_date - 44,
    current_date + 60,
    'in_progress'
  ),
  (
    'a3000000-0000-0000-0000-000000000003',
    'a2000000-0000-0000-0000-000000000001',
    'Launch',
    current_date + 61,
    current_date + 110,
    'not_started'
  );

----------------------------------------------------------------
-- Task lists
----------------------------------------------------------------
insert into
  pm.task_lists (id, project_id, phase_id, name)
values
  (
    'a4000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000002',
    'Fleet Telemetry Backlog'
  ),
  (
    'a4000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000002',
    null,
    'Sprint 1'
  ),
  (
    'a4000000-0000-0000-0000-000000000003',
    'a2000000-0000-0000-0000-000000000003',
    null,
    'Integration Work'
  );

----------------------------------------------------------------
-- Tasks
--
-- T1 -> T2 -> T3 -> T4 and T3 -> T5: a real dependency chain on the
-- flagship project, walked far enough that T3 is still open while T4
-- and T5 are waiting on it — exactly what the completion-guard
-- demonstration below needs.
----------------------------------------------------------------
insert into
  pm.tasks (
    id,
    project_id,
    task_list_id,
    phase_id,
    title,
    status,
    priority,
    assignee_id,
    estimated_hours,
    due_date
  )
values
  (
    'a5000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000002',
    'Design fleet telemetry schema',
    'done',
    'high',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    8,
    current_date - 40
  ),
  (
    'a5000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000002',
    'Implement telemetry ingestion API',
    'done',
    'high',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    16,
    current_date - 30
  ),
  (
    'a5000000-0000-0000-0000-000000000003',
    'a2000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000002',
    'Build fleet dashboard UI',
    'in_progress',
    'high',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    24,
    current_date + 5
  ),
  (
    'a5000000-0000-0000-0000-000000000004',
    'a2000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000002',
    'Write integration tests',
    'todo',
    'medium',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    12,
    current_date + 10
  ),
  (
    'a5000000-0000-0000-0000-000000000005',
    'a2000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000002',
    'Deploy to staging',
    'blocked',
    'medium',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    4,
    current_date + 12
  ),
  (
    'a5000000-0000-0000-0000-000000000006',
    'a2000000-0000-0000-0000-000000000003',
    'a4000000-0000-0000-0000-000000000003',
    null,
    'Build sync connector',
    'in_progress',
    'high',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    180,
    current_date + 8
  );

insert into
  pm.task_dependencies (task_id, depends_on_task_id)
values
  (
    'a5000000-0000-0000-0000-000000000002',
    'a5000000-0000-0000-0000-000000000001'
  ),
  (
    'a5000000-0000-0000-0000-000000000003',
    'a5000000-0000-0000-0000-000000000002'
  ),
  (
    'a5000000-0000-0000-0000-000000000004',
    'a5000000-0000-0000-0000-000000000003'
  ),
  (
    'a5000000-0000-0000-0000-000000000005',
    'a5000000-0000-0000-0000-000000000003'
  );

----------------------------------------------------------------
-- Task comments
----------------------------------------------------------------
insert into
  pm.task_comments (task_id, user_id, body)
values
  (
    'a5000000-0000-0000-0000-000000000003',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    'Client asked for a map view in addition to the list — can we scope that into this task or spin off a follow-up?'
  ),
  (
    'a5000000-0000-0000-0000-000000000003',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    'Spinning it off — map view will be its own task once this ships.'
  );

----------------------------------------------------------------
-- Time entries
--
-- P3's four approved entries below total 190 of its 200 budgeted
-- hours — close enough that the fourth deliberate failure at the
-- bottom of this file has something real to bump into.
----------------------------------------------------------------
insert into
  pm.time_entries (
    id,
    task_id,
    project_id,
    user_id,
    entry_date,
    logged_duration,
    description,
    status
  )
values
  (
    'a6000000-0000-0000-0000-000000000001',
    'a5000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    current_date - 38,
    28800000,
    'Schema design',
    'approved'
  ),
  (
    'a6000000-0000-0000-0000-000000000002',
    'a5000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000001',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    current_date - 28,
    57600000,
    'Ingestion API implementation',
    'approved'
  ),
  (
    'a6000000-0000-0000-0000-000000000003',
    'a5000000-0000-0000-0000-000000000003',
    'a2000000-0000-0000-0000-000000000001',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    current_date - 3,
    36000000,
    'Dashboard UI — list view',
    'approved'
  ),
  (
    'a6000000-0000-0000-0000-000000000004',
    'a5000000-0000-0000-0000-000000000003',
    'a2000000-0000-0000-0000-000000000001',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    current_date - 1,
    14400000,
    'Dashboard UI — filters',
    'submitted'
  ),
  (
    'a6000000-0000-0000-0000-000000000005',
    'a5000000-0000-0000-0000-000000000006',
    'a2000000-0000-0000-0000-000000000003',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    current_date - 28,
    162000000,
    'Week 1 sync connector work',
    'approved'
  ),
  (
    'a6000000-0000-0000-0000-000000000006',
    'a5000000-0000-0000-0000-000000000006',
    'a2000000-0000-0000-0000-000000000003',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    current_date - 21,
    162000000,
    'Week 2 sync connector work',
    'approved'
  ),
  (
    'a6000000-0000-0000-0000-000000000007',
    'a5000000-0000-0000-0000-000000000006',
    'a2000000-0000-0000-0000-000000000003',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    current_date - 14,
    180000000,
    'Week 3 sync connector work',
    'approved'
  ),
  (
    'a6000000-0000-0000-0000-000000000008',
    'a5000000-0000-0000-0000-000000000006',
    'a2000000-0000-0000-0000-000000000003',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
    current_date - 7,
    180000000,
    'Week 4 sync connector work',
    'approved'
  );

----------------------------------------------------------------
-- Milestones
----------------------------------------------------------------
insert into
  pm.milestones (
    id,
    project_id,
    name,
    due_date,
    status,
    completion_percent,
    billing_amount,
    is_billing_trigger
  )
values
  (
    'a7000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001',
    'Phase 1 Discovery Complete',
    current_date - 45,
    'completed',
    100,
    20000,
    true
  ),
  (
    'a7000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000001',
    'MVP Launch',
    current_date + 60,
    'pending',
    0,
    50000,
    true
  );

----------------------------------------------------------------
-- Deliverables
--
-- D1 is walked all the way through approval, with the client-portal
-- user as the actual reviewer. D2 is left sitting in in_review — the
-- live case a client-portal login would actually see waiting.
----------------------------------------------------------------
insert into
  pm.deliverables (
    id,
    project_id,
    milestone_id,
    name,
    submitted_by,
    created_at
  )
values
  (
    'a8000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001',
    'a7000000-0000-0000-0000-000000000001',
    'Discovery Report',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    current_timestamp - interval '48 days'
  ),
  (
    'a8000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000001',
    null,
    'Fleet Dashboard Prototype',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    current_timestamp - interval '4 days'
  );

update pm.deliverables
set
  status = 'submitted'
where
  id = 'a8000000-0000-0000-0000-000000000001';

update pm.deliverables
set
  status = 'in_review'
where
  id = 'a8000000-0000-0000-0000-000000000001';

update pm.deliverables
set
  status = 'approved'
where
  id = 'a8000000-0000-0000-0000-000000000001';

update pm.deliverables
set
  reviewed_by = 'f03db03e-fb7a-424d-84ff-18e2791ce0b5',
  reviewed_at = current_timestamp - interval '44 days'
where
  id = 'a8000000-0000-0000-0000-000000000001';

update pm.deliverables
set
  status = 'submitted'
where
  id = 'a8000000-0000-0000-0000-000000000002';

update pm.deliverables
set
  status = 'in_review'
where
  id = 'a8000000-0000-0000-0000-000000000002';

----------------------------------------------------------------
-- Expenses
----------------------------------------------------------------
insert into
  pm.project_expenses (
    project_id,
    user_id,
    expense_date,
    category,
    description,
    amount,
    status,
    approved_by,
    approved_at
  )
values
  (
    'a2000000-0000-0000-0000-000000000001',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    current_date - 35,
    'travel',
    'Client site visit flights',
    450,
    'approved',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    current_timestamp - interval '34 days'
  ),
  (
    'a2000000-0000-0000-0000-000000000001',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b3',
    current_date - 10,
    'software',
    'Design tool license renewal',
    99,
    'pending',
    null,
    null
  );

----------------------------------------------------------------
-- Invoice — built from the two approved time entries above and the
-- completed Discovery milestone, sent for real, and partly paid.
----------------------------------------------------------------
insert into
  pm.invoices (
    id,
    project_id,
    client_id,
    period_start,
    period_end,
    issue_date,
    due_date
  )
values
  (
    'a9000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000001',
    current_date - 45,
    current_date - 25,
    current_date - 24,
    current_date + 6
  );

insert into
  pm.invoice_lines (
    invoice_id,
    line_type,
    description,
    source_time_entry_id,
    quantity,
    unit_price
  )
values
  (
    'a9000000-0000-0000-0000-000000000001',
    'time',
    'Design fleet telemetry schema',
    'a6000000-0000-0000-0000-000000000001',
    8,
    175
  ),
  (
    'a9000000-0000-0000-0000-000000000001',
    'time',
    'Implement telemetry ingestion API',
    'a6000000-0000-0000-0000-000000000002',
    16,
    140
  );

insert into
  pm.invoice_lines (
    invoice_id,
    line_type,
    description,
    source_milestone_id,
    quantity,
    unit_price
  )
values
  (
    'a9000000-0000-0000-0000-000000000001',
    'milestone',
    'Phase 1 Discovery Complete — milestone billing',
    'a7000000-0000-0000-0000-000000000001',
    1,
    20000
  );

select
  pm.send_invoice ('a9000000-0000-0000-0000-000000000001');

insert into
  pm.invoice_payments (
    invoice_id,
    payment_date,
    amount,
    method,
    reference,
    recorded_by
  )
values
  (
    'a9000000-0000-0000-0000-000000000001',
    current_date - 15,
    10000,
    'bank_transfer',
    'ACH-55210',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2'
  );

----------------------------------------------------------------
-- Risks
----------------------------------------------------------------
insert into
  pm.risks (
    id,
    project_id,
    title,
    description,
    category,
    probability,
    impact,
    owner_id,
    review_date
  )
values
  (
    'aa000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000001',
    'Fleet telemetry data volume may exceed initial staging capacity',
    'Ingestion rates in the design doc were conservative; real device counts run higher.',
    'technical',
    3,
    4,
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date + 20
  ),
  (
    'aa000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000001',
    'Key engineer has planned leave during the launch window',
    'Jonas Weber has approved leave overlapping the current launch date.',
    'resource',
    4,
    4,
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date + 5
  );

----------------------------------------------------------------
-- Status reports
--
-- The second report is what actually moves the flagship project's
-- health to amber — there is no other way to change it.
----------------------------------------------------------------
insert into
  pm.status_reports (
    project_id,
    report_date,
    overall_health,
    budget_health,
    schedule_health,
    summary,
    blockers,
    created_by
  )
values
  (
    'a2000000-0000-0000-0000-000000000001',
    current_date - 20,
    'green',
    'green',
    'green',
    'Discovery complete, build phase underway on schedule.',
    null,
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2'
  ),
  (
    'a2000000-0000-0000-0000-000000000001',
    current_date - 2,
    'amber',
    'green',
    'amber',
    'Dashboard UI running slightly behind due to added map-view scope; the engineer-leave risk is now being actively monitored.',
    'Awaiting client sign-off on the dashboard prototype.',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2'
  ),
  (
    'a2000000-0000-0000-0000-000000000003',
    current_date - 1,
    'red',
    'red',
    'amber',
    'Inventory Sync Integration is at 95% of its budgeted hours with meaningful scope remaining.',
    'Need a budget increase or scope reduction decision from the client.',
    'f03db03e-fb7a-424d-84ff-18e2791ce0b2'
  );

----------------------------------------------------------------
-- Four deliberate failures
--
-- The first two guards have no role-based override and are refused
-- even though the seed runs as the postgres superuser. The budget
-- guard does allow an x-admin override — this block deliberately
-- does not use it, so it is refused too. The invoice guard has no
-- override at all.
----------------------------------------------------------------
do $$
begin
  begin
    insert into pm.task_dependencies (task_id, depends_on_task_id)
    values (
      'a5000000-0000-0000-0000-000000000001', -- T1 ("Design fleet telemetry schema")
      'a5000000-0000-0000-0000-000000000004'  -- T4, which already (transitively) depends on T1
    );
    raise exception 'GUARD FAILED: a cyclic task dependency was allowed.';
  exception
    when others then
      raise notice 'Guard confirmed: %', sqlerrm;
  end;
end;
$$;

do $$
begin
  begin
    update pm.tasks
    set status = 'done'
    where id = 'a5000000-0000-0000-0000-000000000004'; -- T4's blocker (T3) is still in_progress
    raise exception 'GUARD FAILED: a task completed with an unfinished blocking dependency.';
  exception
    when others then
      raise notice 'Guard confirmed: %', sqlerrm;
  end;
end;
$$;

-- The budget guard allows an x-admin override, and the postgres
-- superuser this seed runs as is itself a member of "x-admin" in a
-- fresh local stack — so bypassing it here would prove nothing. This
-- block genuinely switches to the "user" role (with consultant2's
-- own identity, since RLS scopes a "user" to their own entries) for
-- just this one statement, so the override path is not in play and
-- the guard actually has to earn its keep.
do $$
declare
  v_over_budget_entry uuid;
begin
  execute format('set local role %I', 'user');
  perform set_config('request.jwt.claims', '{"sub": "f03db03e-fb7a-424d-84ff-18e2791ce0b4", "role": "user"}', true);

  begin
    insert into pm.time_entries (task_id, project_id, user_id, entry_date, logged_duration, description, status)
    values (
      'a5000000-0000-0000-0000-000000000006', 'a2000000-0000-0000-0000-000000000003', 'f03db03e-fb7a-424d-84ff-18e2791ce0b4',
      current_date, 54000000, 'Additional connector work', 'submitted'
    )
    returning id into v_over_budget_entry;

    update pm.time_entries
    set status = 'approved'
    where id = v_over_budget_entry; -- 190 already consumed + 15 more would clear the 200h budget

    raise exception 'GUARD FAILED: a time entry was approved past its project''s budgeted hours.';
  exception
    when others then
      raise notice 'Guard confirmed: %', sqlerrm;
  end;
end;
$$;

do $$
begin
  begin
    insert into pm.invoice_lines (invoice_id, line_type, description, source_time_entry_id, quantity, unit_price)
    values (
      'a9000000-0000-0000-0000-000000000001', 'time', 'Design fleet telemetry schema (duplicate)',
      'a6000000-0000-0000-0000-000000000001', 8, 175
    ); -- this time entry is already on the invoice above
    raise exception 'GUARD FAILED: the same time entry was invoiced twice.';
  exception
    when others then
      raise notice 'Guard confirmed: %', sqlerrm;
  end;
end;
$$;

refresh materialized view pm.utilization_rollup;
