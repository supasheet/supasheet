-- Quality Seeder
-- ================================================================
-- Demo data for the quality (QMS) module. Apply
-- supabase/examples/20260808000000_quality.sql first:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260808000000_quality.sql \
--     -f supabase/examples/q_seed.sql
--
-- Five processes, a small document category tree, six controlled
-- documents walked through real revision history (one currently
-- effective after a full draft -> review -> approval -> publish
-- cycle, one superseded by its own second revision, one stuck mid
-- review), four audits including one completed with a major and a
-- minor finding, five nonconformances and three customer complaints
-- from a mix of sources, six CAPAs — one carried all the way through
-- to a verified close, one deliberately left one action short of
-- being closeable, five FMEA-style risk assessments, six pieces of
-- equipment (two already overdue for calibration, computed rather
-- than typed), and training records spanning completed, expired and
-- not-yet-started.
--
-- The file closes with three deliberate failures: publishing a
-- document version that skipped review, closing a major finding
-- with no CAPA against it, and closing a CAPA with an incomplete
-- action. None of those guards has a role-based override, so all
-- three are refused even though the seed runs as the postgres
-- superuser.
--
-- Dates are relative to `current_date`, so the monthly trend charts
-- and the calibration/review-due alerts have shape whenever this
-- runs.
--
-- Five users are seeded (`on conflict do nothing`, so this is safe
-- alongside supabase/seed.sql and the other examples):
--   d82fb03e-fb7a-424d-84ff-18e2791ce0b1  qms-director@supasheet.app (x-admin)
--   d82fb03e-fb7a-424d-84ff-18e2791ce0b2  qms-manager@supasheet.app  (qa-manager)
--   d82fb03e-fb7a-424d-84ff-18e2791ce0b3  lead-auditor@supasheet.app (quality-auditor)
--   d82fb03e-fb7a-424d-84ff-18e2791ce0b4  staff1@supasheet.app       (user)
--   d82fb03e-fb7a-424d-84ff-18e2791ce0b5  staff2@supasheet.app       (user)
--
-- Sign in as qms-manager@supasheet.app for the DAY-TO-DAY QUALITY
-- seat: document control, audit scheduling, CAPA disposition,
-- calibration and training.
-- lead-auditor@supasheet.app conducts audits and raises findings.
-- staff1@supasheet.app / staff2@supasheet.app are ordinary
-- employees: their own CAPA actions, training and document
-- acknowledgements.
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
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b1',
    'authenticated',
    'authenticated',
    'qms-director@supasheet.app',
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
    '{"sub": "d82fb03e-fb7a-424d-84ff-18e2791ce0b1", "email": "qms-director@supasheet.app", "name": "Elena Kowalski", "email_verified": false, "phone_verified": false}',
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
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'authenticated',
    'authenticated',
    'qms-manager@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "qa-manager"}',
    '{"sub": "d82fb03e-fb7a-424d-84ff-18e2791ce0b2", "email": "qms-manager@supasheet.app", "name": "Marcus Webb", "email_verified": false, "phone_verified": false}',
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
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b3',
    'authenticated',
    'authenticated',
    'lead-auditor@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "quality-auditor"}',
    '{"sub": "d82fb03e-fb7a-424d-84ff-18e2791ce0b3", "email": "lead-auditor@supasheet.app", "name": "Chidi Okonkwo", "email_verified": false, "phone_verified": false}',
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
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    'authenticated',
    'authenticated',
    'staff1@supasheet.app',
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
    '{"sub": "d82fb03e-fb7a-424d-84ff-18e2791ce0b4", "email": "staff1@supasheet.app", "name": "Grace Lindqvist", "email_verified": false, "phone_verified": false}',
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
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    'authenticated',
    'authenticated',
    'staff2@supasheet.app',
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
    '{"sub": "d82fb03e-fb7a-424d-84ff-18e2791ce0b5", "email": "staff2@supasheet.app", "name": "Sam Okafor", "email_verified": false, "phone_verified": false}',
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
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b1',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b1',
    '{"sub": "d82fb03e-fb7a-424d-84ff-18e2791ce0b1", "email": "qms-director@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'b1c1b03e-24a4-41a8-9742-1b5b4e2d8ab1'
  ),
  (
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    '{"sub": "d82fb03e-fb7a-424d-84ff-18e2791ce0b2", "email": "qms-manager@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'b1c1b03e-24a4-41a8-9742-1b5b4e2d8ab2'
  ),
  (
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b3',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b3',
    '{"sub": "d82fb03e-fb7a-424d-84ff-18e2791ce0b3", "email": "lead-auditor@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'b1c1b03e-24a4-41a8-9742-1b5b4e2d8ab3'
  ),
  (
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    '{"sub": "d82fb03e-fb7a-424d-84ff-18e2791ce0b4", "email": "staff1@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'b1c1b03e-24a4-41a8-9742-1b5b4e2d8ab4'
  ),
  (
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    '{"sub": "d82fb03e-fb7a-424d-84ff-18e2791ce0b5", "email": "staff2@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'b1c1b03e-24a4-41a8-9742-1b5b4e2d8ab5'
  )
on conflict do nothing;

----------------------------------------------------------------
-- Processes
----------------------------------------------------------------
insert into
  quality.processes (id, code, name, description, category, owner_id)
values
  (
    'a1000000-0000-0000-0000-000000000001',
    'DES',
    'Design & Development',
    'Product design and engineering change control.',
    'core',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2'
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    'PROD',
    'Production',
    'Manufacturing and assembly operations.',
    'core',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2'
  ),
  (
    'a1000000-0000-0000-0000-000000000003',
    'PUR',
    'Purchasing',
    'Supplier selection and incoming material control.',
    'support',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b1'
  ),
  (
    'a1000000-0000-0000-0000-000000000004',
    'CS',
    'Customer Service',
    'Order handling and complaint intake.',
    'support',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b3'
  ),
  (
    'a1000000-0000-0000-0000-000000000005',
    'MR',
    'Management Review',
    'Leadership review of the quality system.',
    'management',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b1'
  );

----------------------------------------------------------------
-- Document categories
----------------------------------------------------------------
insert into
  quality.document_categories (id, parent_id, code, name, description)
values
  (
    'a2000000-0000-0000-0000-000000000001',
    null,
    'POL',
    'Policies',
    'Top-level quality policy statements.'
  ),
  (
    'a2000000-0000-0000-0000-000000000002',
    null,
    'PROC',
    'Procedures',
    'How the quality system actually runs.'
  ),
  (
    'a2000000-0000-0000-0000-000000000003',
    'a2000000-0000-0000-0000-000000000002',
    'PROC-MFG',
    'Manufacturing Procedures',
    'Shop-floor level procedures.'
  ),
  (
    'a2000000-0000-0000-0000-000000000004',
    null,
    'WI',
    'Work Instructions',
    'Step-by-step task instructions.'
  ),
  (
    'a2000000-0000-0000-0000-000000000005',
    null,
    'FORM',
    'Forms',
    'Blank forms and templates.'
  ),
  (
    'a2000000-0000-0000-0000-000000000006',
    null,
    'QM',
    'Quality Manual',
    'The top-level quality manual.'
  );

----------------------------------------------------------------
-- Documents
----------------------------------------------------------------
insert into
  quality.documents (
    id,
    title,
    document_type,
    category_id,
    owner_id,
    department,
    review_cycle_months
  )
values
  (
    'a3000000-0000-0000-0000-000000000001',
    'Quality Manual',
    'quality_manual',
    'a2000000-0000-0000-0000-000000000006',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Quality',
    24
  ),
  (
    'a3000000-0000-0000-0000-000000000002',
    'Corrective Action Procedure',
    'procedure',
    'a2000000-0000-0000-0000-000000000002',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Quality',
    12
  ),
  (
    'a3000000-0000-0000-0000-000000000003',
    'Incoming Inspection Work Instruction',
    'work_instruction',
    'a2000000-0000-0000-0000-000000000004',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Purchasing',
    12
  ),
  (
    'a3000000-0000-0000-0000-000000000004',
    'Document Control Procedure',
    'procedure',
    'a2000000-0000-0000-0000-000000000002',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Quality',
    24
  ),
  (
    'a3000000-0000-0000-0000-000000000005',
    'Calibration Procedure',
    'procedure',
    'a2000000-0000-0000-0000-000000000003',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Quality',
    12
  ),
  (
    'a3000000-0000-0000-0000-000000000006',
    'Customer Complaint Form',
    'form',
    'a2000000-0000-0000-0000-000000000005',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Customer Service',
    36
  );

----------------------------------------------------------------
-- Document versions
----------------------------------------------------------------
insert into
  quality.document_versions (
    id,
    document_id,
    version_number,
    author_id,
    change_summary,
    created_at
  )
values
  (
    'a4000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    'A',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Initial release.',
    current_timestamp - interval '135 days'
  ),
  (
    'a4000000-0000-0000-0000-000000000002',
    'a3000000-0000-0000-0000-000000000002',
    'A',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Initial release.',
    current_timestamp - interval '100 days'
  ),
  (
    'a4000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000003',
    'A',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b3',
    'Initial release.',
    current_timestamp - interval '80 days'
  ),
  (
    'a4000000-0000-0000-0000-000000000004',
    'a3000000-0000-0000-0000-000000000004',
    'A',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Initial release.',
    current_timestamp - interval '20 days'
  ),
  (
    'a4000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000005',
    'A',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Initial draft.',
    current_timestamp - interval '5 days'
  ),
  (
    'a4000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000006',
    'A',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Initial release.',
    current_timestamp - interval '60 days'
  ),
  (
    'a4000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000001',
    'B',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Added supplier-caused nonconformance handling section.',
    current_timestamp - interval '18 days'
  );

-- Walk each version through the real workflow, so the guard and the
-- publish/supersede trigger both actually run.
-- Doc 1 v A: published, then superseded by v B below.
update quality.document_versions
set
  status = 'in_review',
  reviewer_id = 'd82fb03e-fb7a-424d-84ff-18e2791ce0b3'
where
  id = 'a4000000-0000-0000-0000-000000000001';

update quality.document_versions
set
  status = 'approved'
where
  id = 'a4000000-0000-0000-0000-000000000001';

update quality.document_versions
set
  status = 'effective',
  effective_date = current_date - 130
where
  id = 'a4000000-0000-0000-0000-000000000001';

update quality.document_versions
set
  approver_id = 'd82fb03e-fb7a-424d-84ff-18e2791ce0b1',
  approved_at = current_timestamp - interval '132 days'
where
  id = 'a4000000-0000-0000-0000-000000000001';

-- Doc 2 v A: published and still current.
update quality.document_versions
set
  status = 'in_review',
  reviewer_id = 'd82fb03e-fb7a-424d-84ff-18e2791ce0b3'
where
  id = 'a4000000-0000-0000-0000-000000000002';

update quality.document_versions
set
  status = 'approved'
where
  id = 'a4000000-0000-0000-0000-000000000002';

update quality.document_versions
set
  status = 'effective',
  effective_date = current_date - 95
where
  id = 'a4000000-0000-0000-0000-000000000002';

update quality.document_versions
set
  approver_id = 'd82fb03e-fb7a-424d-84ff-18e2791ce0b1',
  approved_at = current_timestamp - interval '97 days'
where
  id = 'a4000000-0000-0000-0000-000000000002';

-- Doc 3 v A: published and still current.
update quality.document_versions
set
  status = 'in_review',
  reviewer_id = 'd82fb03e-fb7a-424d-84ff-18e2791ce0b2'
where
  id = 'a4000000-0000-0000-0000-000000000003';

update quality.document_versions
set
  status = 'approved'
where
  id = 'a4000000-0000-0000-0000-000000000003';

update quality.document_versions
set
  status = 'effective',
  effective_date = current_date - 75
where
  id = 'a4000000-0000-0000-0000-000000000003';

update quality.document_versions
set
  approver_id = 'd82fb03e-fb7a-424d-84ff-18e2791ce0b1',
  approved_at = current_timestamp - interval '77 days'
where
  id = 'a4000000-0000-0000-0000-000000000003';

-- Doc 4 v A: mid-review, not yet published.
update quality.document_versions
set
  status = 'in_review',
  reviewer_id = 'd82fb03e-fb7a-424d-84ff-18e2791ce0b3'
where
  id = 'a4000000-0000-0000-0000-000000000004';

-- Doc 5 v A: left as a draft — nobody has submitted it yet.
-- (no transition — default status is already 'draft')
-- Doc 6 v A: published and still current.
update quality.document_versions
set
  status = 'in_review',
  reviewer_id = 'd82fb03e-fb7a-424d-84ff-18e2791ce0b3'
where
  id = 'a4000000-0000-0000-0000-000000000006';

update quality.document_versions
set
  status = 'approved'
where
  id = 'a4000000-0000-0000-0000-000000000006';

update quality.document_versions
set
  status = 'effective',
  effective_date = current_date - 55
where
  id = 'a4000000-0000-0000-0000-000000000006';

update quality.document_versions
set
  approver_id = 'd82fb03e-fb7a-424d-84ff-18e2791ce0b1',
  approved_at = current_timestamp - interval '57 days'
where
  id = 'a4000000-0000-0000-0000-000000000006';

-- Doc 1 v B: published — this is what actually exercises the
-- supersede rule, since v A above is still 'effective' at this point.
update quality.document_versions
set
  status = 'in_review',
  reviewer_id = 'd82fb03e-fb7a-424d-84ff-18e2791ce0b3'
where
  id = 'a4000000-0000-0000-0000-000000000007';

update quality.document_versions
set
  status = 'approved'
where
  id = 'a4000000-0000-0000-0000-000000000007';

update quality.document_versions
set
  status = 'effective',
  effective_date = current_date - 15
where
  id = 'a4000000-0000-0000-0000-000000000007';

update quality.document_versions
set
  approver_id = 'd82fb03e-fb7a-424d-84ff-18e2791ce0b1',
  approved_at = current_timestamp - interval '17 days'
where
  id = 'a4000000-0000-0000-0000-000000000007';

----------------------------------------------------------------
-- Document acknowledgements
----------------------------------------------------------------
insert into
  quality.document_acknowledgements (document_version_id, user_id, acknowledged_at)
values
  (
    'a4000000-0000-0000-0000-000000000007',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '14 days'
  ),
  (
    'a4000000-0000-0000-0000-000000000007',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    current_timestamp - interval '13 days'
  ),
  (
    'a4000000-0000-0000-0000-000000000007',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b3',
    current_timestamp - interval '12 days'
  ),
  (
    'a4000000-0000-0000-0000-000000000002',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '90 days'
  ),
  (
    'a4000000-0000-0000-0000-000000000006',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    current_timestamp - interval '50 days'
  );

----------------------------------------------------------------
-- Audits
----------------------------------------------------------------
insert into
  quality.audits (
    id,
    audit_type,
    process_id,
    lead_auditor_id,
    status,
    scope,
    standard_reference,
    planned_date,
    actual_start_date,
    actual_end_date
  )
values
  (
    'b1000000-0000-0000-0000-000000000001',
    'internal',
    'a1000000-0000-0000-0000-000000000001',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b3',
    'completed',
    'Design change control review',
    'ISO 9001:2015 Clause 8.3',
    current_date - 60,
    current_date - 58,
    current_date - 55
  ),
  (
    'b1000000-0000-0000-0000-000000000002',
    'supplier',
    'a1000000-0000-0000-0000-000000000003',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b3',
    'completed',
    'Prime Materials Inc. supplier quality audit',
    'AS9100 Clause 8.4',
    current_date - 40,
    current_date - 38,
    current_date - 36
  ),
  (
    'b1000000-0000-0000-0000-000000000003',
    'internal',
    'a1000000-0000-0000-0000-000000000002',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b3',
    'in_progress',
    'Production floor 5S and work instruction adherence',
    'ISO 9001:2015 Clause 7',
    current_date - 5,
    current_date - 3,
    null
  ),
  (
    'b1000000-0000-0000-0000-000000000004',
    'certification',
    'a1000000-0000-0000-0000-000000000005',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b1',
    'planned',
    'ISO 9001:2015 surveillance audit',
    'ISO 9001:2015 (full scope)',
    current_date + 30,
    null,
    null
  );

----------------------------------------------------------------
-- Audit checklist items
----------------------------------------------------------------
insert into
  quality.audit_checklist_items (
    id,
    audit_id,
    sequence_number,
    criteria,
    clause_reference,
    response,
    notes
  )
values
  (
    'b2000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000001',
    10,
    'Design inputs are documented before development starts.',
    '8.3.3',
    'conformant',
    null
  ),
  (
    'b2000000-0000-0000-0000-000000000002',
    'b1000000-0000-0000-0000-000000000001',
    20,
    'Design outputs are verified against inputs before release.',
    '8.3.5',
    'nonconformant',
    'No verification record found for ECN-2201.'
  ),
  (
    'b2000000-0000-0000-0000-000000000003',
    'b1000000-0000-0000-0000-000000000001',
    30,
    'Design changes are reviewed and approved before implementation.',
    '8.3.6',
    'nonconformant',
    'Change implemented on the line before an approval signature was on file.'
  ),
  (
    'b2000000-0000-0000-0000-000000000004',
    'b1000000-0000-0000-0000-000000000001',
    40,
    'A design history file is maintained per product.',
    '8.3.2',
    'observation',
    'File exists but is not indexed, so retrieval is slow.'
  ),
  (
    'b2000000-0000-0000-0000-000000000005',
    'b1000000-0000-0000-0000-000000000002',
    10,
    'Incoming material certificates of conformance are retained.',
    '8.4.2',
    'conformant',
    null
  ),
  (
    'b2000000-0000-0000-0000-000000000006',
    'b1000000-0000-0000-0000-000000000002',
    20,
    'Supplier corrective action responses arrive within 30 days.',
    '8.4.3',
    'nonconformant',
    'Last three responses averaged 45 days.'
  ),
  (
    'b2000000-0000-0000-0000-000000000007',
    'b1000000-0000-0000-0000-000000000003',
    10,
    '5S standards are visibly maintained at each station.',
    '7.1.4',
    'conformant',
    null
  ),
  (
    'b2000000-0000-0000-0000-000000000008',
    'b1000000-0000-0000-0000-000000000003',
    20,
    'Operators can locate the current work instruction at their station.',
    '7.5.3',
    'pending',
    null
  ),
  (
    'b2000000-0000-0000-0000-000000000009',
    'b1000000-0000-0000-0000-000000000003',
    30,
    'Calibrated tools in use carry a current calibration label.',
    '7.1.5',
    'pending',
    null
  );

----------------------------------------------------------------
-- Audit findings
----------------------------------------------------------------
insert into
  quality.audit_findings (
    id,
    audit_id,
    checklist_item_id,
    severity,
    clause_reference,
    description,
    due_date
  )
values
  (
    'b3000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000003',
    'major',
    '8.3.6',
    'Design change ECN-2210 was implemented on the production line before receiving documented approval.',
    current_date - 40
  ),
  (
    'b3000000-0000-0000-0000-000000000002',
    'b1000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000002',
    'minor',
    '8.3.5',
    'No design output verification record could be located for ECN-2201.',
    current_date - 35
  ),
  (
    'b3000000-0000-0000-0000-000000000003',
    'b1000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000004',
    'observation',
    '8.3.2',
    'The design history file exists but is not indexed, making retrieval slow.',
    null
  ),
  (
    'b3000000-0000-0000-0000-000000000004',
    'b1000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000006',
    'minor',
    '8.4.3',
    'Supplier corrective action responses from Prime Materials Inc. are averaging 45 days against a 30-day target.',
    current_date - 20
  );

-- The two minor/observation findings do not need a CAPA to close.
update quality.audit_findings
set
  status = 'closed'
where
  id = 'b3000000-0000-0000-0000-000000000002';

update quality.audit_findings
set
  status = 'closed'
where
  id = 'b3000000-0000-0000-0000-000000000003';

update quality.audit_findings
set
  status = 'closed'
where
  id = 'b3000000-0000-0000-0000-000000000004';

----------------------------------------------------------------
-- Nonconformances
----------------------------------------------------------------
insert into
  quality.nonconformances (
    id,
    source,
    process_id,
    reported_by,
    title,
    description,
    severity,
    status,
    root_cause,
    containment_action,
    created_at
  )
values
  (
    'c1000000-0000-0000-0000-000000000001',
    'internal_report',
    'a1000000-0000-0000-0000-000000000002',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    'Wrong torque spec used on fastener assembly line 2',
    'Operator applied the torque spec for the previous product revision.',
    'major',
    'capa_raised',
    'Work instruction WI-204 was not updated when the fastener spec changed on the last ECN.',
    'Line 2 stopped and the affected shift''s output quarantined pending rework.',
    current_timestamp - interval '25 days'
  ),
  (
    'c1000000-0000-0000-0000-000000000002',
    'supplier_issue',
    'a1000000-0000-0000-0000-000000000003',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Incoming batch PRM-2298 dimensions out of tolerance',
    'Incoming inspection rejected 12% of the batch for out-of-tolerance diameter.',
    'major',
    'under_investigation',
    null,
    'Batch placed on quality hold pending supplier root cause.',
    current_timestamp - interval '12 days'
  ),
  (
    'c1000000-0000-0000-0000-000000000003',
    'customer_complaint',
    'a1000000-0000-0000-0000-000000000004',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'Product shipped with missing accessory kit',
    'Shipment to Acme Robotics arrived without the mounting hardware kit.',
    'minor',
    'closed',
    'Packing checklist did not list the hardware kit as a separate scan item.',
    'Replacement kit shipped overnight.',
    current_timestamp - interval '45 days'
  ),
  (
    'c1000000-0000-0000-0000-000000000004',
    'inspection',
    'a1000000-0000-0000-0000-000000000002',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    'Surface finish defect detected on final inspection batch 4471',
    'Visible tooling marks on 3 of 50 units in the batch.',
    'minor',
    'open',
    null,
    null,
    current_timestamp - interval '6 days'
  ),
  (
    'c1000000-0000-0000-0000-000000000005',
    'other',
    'a1000000-0000-0000-0000-000000000001',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    'Drawing revision mismatch between ECN and released drawing',
    'The released drawing still shows revision C; the ECN was approved against revision D.',
    'minor',
    'open',
    null,
    null,
    current_timestamp - interval '2 days'
  );

update quality.nonconformances
set
  closed_at = current_timestamp - interval '40 days'
where
  id = 'c1000000-0000-0000-0000-000000000003';

----------------------------------------------------------------
-- Customer complaints
----------------------------------------------------------------
insert into
  quality.customer_complaints (
    id,
    customer_name,
    contact_email,
    product_or_service,
    description,
    severity,
    received_date,
    status,
    nonconformance_id,
    resolution,
    resolved_at,
    closed_at
  )
values
  (
    'c2000000-0000-0000-0000-000000000001',
    'Acme Robotics',
    'acme.qc@example.com',
    'Servo Bracket Assembly SB-200',
    'Received shipment missing the mounting hardware kit.',
    'minor',
    current_date - 46,
    'closed',
    'c1000000-0000-0000-0000-000000000003',
    'Replacement hardware kits shipped overnight; root cause traced to a packing checklist omission.',
    current_timestamp - interval '44 days',
    current_timestamp - interval '40 days'
  ),
  (
    'c2000000-0000-0000-0000-000000000002',
    'Meridian Aerospace',
    'quality@meridian.example',
    'Bracket Assembly Batch 4471',
    'Customer inspection found inconsistent surface finish on 3 of 50 units received.',
    'major',
    current_date - 7,
    'investigating',
    'c1000000-0000-0000-0000-000000000004',
    null,
    null,
    null
  ),
  (
    'c2000000-0000-0000-0000-000000000003',
    'Northfield Manufacturing',
    'procurement@northfield.example',
    'Custom Fixture Order',
    'Delivery arrived one week later than the confirmed ship date.',
    'minor',
    current_date - 3,
    'open',
    null,
    null,
    null,
    null
  );

----------------------------------------------------------------
-- CAPAs
----------------------------------------------------------------
insert into
  quality.capas (
    id,
    capa_type,
    source,
    source_audit_finding_id,
    source_nonconformance_id,
    source_complaint_id,
    process_id,
    title,
    description,
    priority,
    owner_id,
    opened_by,
    due_date,
    created_at
  )
values
  (
    'd1000000-0000-0000-0000-000000000001',
    'corrective',
    'audit_finding',
    'b3000000-0000-0000-0000-000000000001',
    null,
    null,
    'a1000000-0000-0000-0000-000000000001',
    'Enforce documented approval before implementing design changes on the line',
    'A design change was implemented on the production line before a documented approval was on file.',
    'high',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b3',
    current_date - 25,
    current_timestamp - interval '38 days'
  ),
  (
    'd1000000-0000-0000-0000-000000000002',
    'both',
    'nonconformance',
    null,
    'c1000000-0000-0000-0000-000000000001',
    null,
    'a1000000-0000-0000-0000-000000000002',
    'Correct fastener torque spec and prevent stale work instructions',
    'Line 2 used a superseded torque spec because the work instruction was not updated with the last ECN.',
    'critical',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_date - 10,
    current_timestamp - interval '24 days'
  ),
  (
    'd1000000-0000-0000-0000-000000000003',
    'corrective',
    'nonconformance',
    null,
    'c1000000-0000-0000-0000-000000000004',
    null,
    'a1000000-0000-0000-0000-000000000002',
    'Address tooling-mark surface defects on final inspection',
    'Tooling marks found on 3 of 50 units in batch 4471, flagged by both internal inspection and the customer.',
    'high',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date + 10,
    current_timestamp - interval '5 days'
  ),
  (
    'd1000000-0000-0000-0000-000000000004',
    'preventive',
    'management_review',
    null,
    null,
    null,
    'a1000000-0000-0000-0000-000000000005',
    'Increase internal audit frequency for Design & Development',
    'Management review noted design control findings recur; recommend quarterly audits of that process.',
    'medium',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_date + 20,
    current_timestamp - interval '10 days'
  ),
  (
    'd1000000-0000-0000-0000-000000000005',
    'preventive',
    'complaint',
    null,
    null,
    'c2000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000004',
    'Reduce complaint response time for shipping delays',
    'Northfield''s delivery ran a week late with no proactive notice — review the shipping delay escalation path.',
    'low',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date + 30,
    current_timestamp - interval '1 days'
  ),
  (
    'd1000000-0000-0000-0000-000000000006',
    'preventive',
    'other',
    null,
    null,
    null,
    'a1000000-0000-0000-0000-000000000003',
    'Investigate alternate supplier for grade A steel',
    'Duplicate of an initiative already underway in procurement — closing this one out.',
    'low',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date - 20,
    current_timestamp - interval '50 days'
  );

-- The major finding can close now that a CAPA has been raised against it.
update quality.audit_findings
set
  status = 'closed'
where
  id = 'b3000000-0000-0000-0000-000000000001';

update quality.capas
set
  status = 'cancelled'
where
  id = 'd1000000-0000-0000-0000-000000000006';

----------------------------------------------------------------
-- CAPA actions
----------------------------------------------------------------
insert into
  quality.capa_actions (
    id,
    capa_id,
    action_type,
    description,
    assigned_to,
    due_date,
    status
  )
values
  (
    'd2000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000001',
    'corrective',
    'Add a mandatory approval checkpoint in the ECN workflow before production release.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date - 30,
    'open'
  ),
  (
    'd2000000-0000-0000-0000-000000000002',
    'd1000000-0000-0000-0000-000000000001',
    'preventive',
    'Retrain production supervisors on the ECN approval requirement.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_date - 20,
    'open'
  ),
  (
    'd2000000-0000-0000-0000-000000000003',
    'd1000000-0000-0000-0000-000000000002',
    'containment',
    'Quarantine and rework line 2 output from the affected shift.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_date - 23,
    'open'
  ),
  (
    'd2000000-0000-0000-0000-000000000004',
    'd1000000-0000-0000-0000-000000000002',
    'corrective',
    'Update WI-204 torque specification to match the current ECN.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date - 15,
    'open'
  ),
  (
    'd2000000-0000-0000-0000-000000000005',
    'd1000000-0000-0000-0000-000000000003',
    'containment',
    'Segregate and 100% inspect the remaining batch 4471 units.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    current_date - 3,
    'open'
  ),
  (
    'd2000000-0000-0000-0000-000000000006',
    'd1000000-0000-0000-0000-000000000003',
    'corrective',
    'Adjust the tooling change interval on the line 2 CNC station.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date + 5,
    'in_progress'
  ),
  (
    'd2000000-0000-0000-0000-000000000007',
    'd1000000-0000-0000-0000-000000000004',
    'preventive',
    'Update the audit schedule to a quarterly cadence for the Design process.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date + 15,
    'open'
  );

update quality.capa_actions
set
  status = 'completed'
where
  id in (
    'd2000000-0000-0000-0000-000000000001',
    'd2000000-0000-0000-0000-000000000002',
    'd2000000-0000-0000-0000-000000000003',
    'd2000000-0000-0000-0000-000000000004',
    'd2000000-0000-0000-0000-000000000005'
  );

-- CAPA1: every action complete, effectiveness verified, closed for real.
update quality.capas
set
  status = 'root_cause_analysis',
  root_cause = 'The ECN workflow allowed production release before an approval signature was captured — a process gap, not an individual error.'
where
  id = 'd1000000-0000-0000-0000-000000000001';

update quality.capas
set
  status = 'action_planned'
where
  id = 'd1000000-0000-0000-0000-000000000001';

update quality.capas
set
  status = 'in_progress'
where
  id = 'd1000000-0000-0000-0000-000000000001';

update quality.capas
set
  status = 'pending_verification'
where
  id = 'd1000000-0000-0000-0000-000000000001';

update quality.capas
set
  effectiveness_result = 'effective',
  effectiveness_check_date = current_date - 5,
  verification_notes = 'No unapproved design changes observed in the two audits conducted since remediation.'
where
  id = 'd1000000-0000-0000-0000-000000000001';

update quality.capas
set
  status = 'verified'
where
  id = 'd1000000-0000-0000-0000-000000000001';

update quality.capas
set
  status = 'closed'
where
  id = 'd1000000-0000-0000-0000-000000000001';

-- CAPA2: every action complete, but left at pending_verification on
-- purpose — the effectiveness check has not been recorded yet, so
-- this is the row the third deliberate failure below tries to close.
update quality.capas
set
  status = 'root_cause_analysis'
where
  id = 'd1000000-0000-0000-0000-000000000002';

update quality.capas
set
  status = 'action_planned'
where
  id = 'd1000000-0000-0000-0000-000000000002';

update quality.capas
set
  status = 'in_progress'
where
  id = 'd1000000-0000-0000-0000-000000000002';

update quality.capas
set
  status = 'pending_verification'
where
  id = 'd1000000-0000-0000-0000-000000000002';

-- CAPA3: in progress, one action still open.
update quality.capas
set
  status = 'root_cause_analysis'
where
  id = 'd1000000-0000-0000-0000-000000000003';

update quality.capas
set
  status = 'action_planned'
where
  id = 'd1000000-0000-0000-0000-000000000003';

update quality.capas
set
  status = 'in_progress'
where
  id = 'd1000000-0000-0000-0000-000000000003';

-- A third, still-unresolved major finding — deliberately left open so
-- the "no serious finding closes without a CAPA" demonstration below
-- has something real to fail against, and so there is at least one
-- open major finding in the demo data.
update quality.audit_checklist_items
set
  response = 'nonconformant',
  notes = 'TW-004''s calibration label expired 20 days ago.'
where
  id = 'b2000000-0000-0000-0000-000000000009';

insert into
  quality.audit_findings (
    id,
    audit_id,
    checklist_item_id,
    severity,
    clause_reference,
    description,
    due_date
  )
values
  (
    'b3000000-0000-0000-0000-000000000005',
    'b1000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000009',
    'major',
    '7.1.5',
    'Torque wrench TW-004''s calibration label expired 20 days before this audit; unclear which measurements taken since are valid.',
    current_date + 10
  );

----------------------------------------------------------------
-- Risk assessments
----------------------------------------------------------------
insert into
  quality.risk_assessments (
    id,
    title,
    description,
    category,
    process_id,
    severity,
    occurrence,
    detection,
    mitigation_plan,
    owner_id,
    status,
    review_date,
    capa_id
  )
values
  (
    'e1000000-0000-0000-0000-000000000001',
    'ECN approval bypass risk',
    'A design change reaches production before its approval is on file.',
    'process',
    'a1000000-0000-0000-0000-000000000001',
    8,
    4,
    3,
    'Mandatory approval checkpoint added to the ECN workflow.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'mitigating',
    current_date + 60,
    'd1000000-0000-0000-0000-000000000001'
  ),
  (
    'e1000000-0000-0000-0000-000000000002',
    'Single-source dependency for grade A steel',
    'Prime Materials Inc. is the only qualified source for a critical raw material.',
    'supplier',
    'a1000000-0000-0000-0000-000000000003',
    7,
    5,
    6,
    'Qualify a second source; track via the procurement RFQ process.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'identified',
    current_date + 30,
    null
  ),
  (
    'e1000000-0000-0000-0000-000000000003',
    'Surface finish defects from CNC tooling wear',
    'Tooling wear on the line 2 CNC station produces visible marks past a certain run length.',
    'product',
    'a1000000-0000-0000-0000-000000000002',
    5,
    6,
    4,
    'Shorten the tooling change interval and add an in-process surface check.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    'mitigating',
    current_date + 15,
    'd1000000-0000-0000-0000-000000000003'
  ),
  (
    'e1000000-0000-0000-0000-000000000004',
    'Calibration lapse on critical measuring equipment',
    'A due date can pass unnoticed if nobody happens to open the equipment record.',
    'compliance',
    'a1000000-0000-0000-0000-000000000002',
    6,
    3,
    5,
    'Automate calibration due-date alerts to equipment custodians.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'accepted',
    current_date + 90,
    null
  ),
  (
    'e1000000-0000-0000-0000-000000000005',
    'Ergonomic strain on assembly line 2',
    'Repetitive motion at the line 2 fastening station flagged in the last safety walk.',
    'safety',
    'a1000000-0000-0000-0000-000000000002',
    4,
    4,
    7,
    'Schedule a formal ergonomic assessment.',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'identified',
    current_date + 45,
    null
  );

----------------------------------------------------------------
-- Equipment
----------------------------------------------------------------
insert into
  quality.equipment (
    id,
    name,
    category,
    serial_number,
    location,
    custodian_id,
    calibration_frequency_days
  )
values
  (
    'f1000000-0000-0000-0000-000000000001',
    'Digital Caliper #12',
    'measuring_device',
    'CAL-DC-0012',
    'Line 2 QC Station',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    365
  ),
  (
    'f1000000-0000-0000-0000-000000000002',
    'Torque Wrench #4',
    'measuring_device',
    'TW-004',
    'Line 2 Assembly',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    180
  ),
  (
    'f1000000-0000-0000-0000-000000000003',
    'Coordinate Measuring Machine',
    'test_equipment',
    'CMM-01',
    'Metrology Lab',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    365
  ),
  (
    'f1000000-0000-0000-0000-000000000004',
    'Surface Roughness Tester',
    'test_equipment',
    'SRT-02',
    'Metrology Lab',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    365
  ),
  (
    'f1000000-0000-0000-0000-000000000005',
    'Injection Mold Tool Set A',
    'production_tooling',
    'MOLD-A',
    'Production Floor',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    730
  ),
  (
    'f1000000-0000-0000-0000-000000000006',
    'Calibration Reference Standard',
    'calibration_standard',
    'REF-STD-01',
    'Metrology Lab',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    365
  );

----------------------------------------------------------------
-- Calibration records — these drive equipment.status reactively
-- through the rollup trigger, the same way a real calibration event
-- would.
----------------------------------------------------------------
insert into
  quality.calibration_records (
    equipment_id,
    calibrated_on,
    performed_by,
    vendor,
    result,
    next_due_date,
    notes
  )
values
  (
    'f1000000-0000-0000-0000-000000000001',
    current_date - 370,
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    null,
    'pass',
    current_date - 5,
    'Annual calibration.'
  ),
  (
    'f1000000-0000-0000-0000-000000000002',
    current_date - 200,
    null,
    'Precision Cal Services',
    'pass',
    current_date - 20,
    'Semi-annual calibration.'
  ),
  (
    'f1000000-0000-0000-0000-000000000003',
    current_date - 300,
    null,
    'MetroCal Labs',
    'pass',
    current_date + 65,
    'Annual calibration, full traceability report on file.'
  ),
  (
    'f1000000-0000-0000-0000-000000000004',
    current_date - 340,
    null,
    'MetroCal Labs',
    'adjusted',
    current_date + 25,
    'Minor drift found and corrected.'
  ),
  (
    'f1000000-0000-0000-0000-000000000005',
    current_date - 100,
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    null,
    'pass',
    current_date + 630,
    'Biennial tooling verification.'
  ),
  (
    'f1000000-0000-0000-0000-000000000006',
    current_date - 50,
    null,
    'MetroCal Labs',
    'pass',
    current_date + 315,
    'Reference standard recertified.'
  );

-- Taken out of service for an unrelated repair — a manual override
-- that the reactive status trigger leaves alone.
update quality.equipment
set
  status = 'out_of_service'
where
  id = 'f1000000-0000-0000-0000-000000000006';

----------------------------------------------------------------
-- Training courses
----------------------------------------------------------------
insert into
  quality.training_courses (
    id,
    code,
    title,
    category,
    related_document_id,
    is_mandatory,
    validity_months
  )
values
  (
    'a6000000-0000-0000-0000-000000000001',
    'QMS-101',
    'Quality Management System Awareness',
    'Quality',
    'a3000000-0000-0000-0000-000000000001',
    true,
    24
  ),
  (
    'a6000000-0000-0000-0000-000000000002',
    'CAPA-101',
    'Root Cause Analysis & CAPA Fundamentals',
    'Quality',
    null,
    false,
    null
  ),
  (
    'a6000000-0000-0000-0000-000000000003',
    'CAL-101',
    'Calibration Procedure Training',
    'Metrology',
    'a3000000-0000-0000-0000-000000000005',
    true,
    12
  ),
  (
    'a6000000-0000-0000-0000-000000000004',
    'DOC-101',
    'Document Control Procedure Training',
    'Quality',
    'a3000000-0000-0000-0000-000000000004',
    true,
    12
  );

----------------------------------------------------------------
-- Training records
----------------------------------------------------------------
insert into
  quality.training_records (
    id,
    course_id,
    user_id,
    assigned_by,
    assigned_on,
    due_date,
    completed_on,
    score,
    notes
  )
values
  (
    'a7000000-0000-0000-0000-000000000001',
    'a6000000-0000-0000-0000-000000000001',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date - 110,
    current_date - 100,
    current_date - 100,
    92,
    null
  ),
  (
    'a7000000-0000-0000-0000-000000000002',
    'a6000000-0000-0000-0000-000000000001',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date - 105,
    current_date - 95,
    current_date - 95,
    88,
    null
  ),
  (
    'a7000000-0000-0000-0000-000000000003',
    'a6000000-0000-0000-0000-000000000002',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date - 5,
    current_date + 20,
    null,
    null,
    null
  ),
  (
    'a7000000-0000-0000-0000-000000000004',
    'a6000000-0000-0000-0000-000000000002',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date - 5,
    current_date + 15,
    null,
    null,
    null
  ),
  (
    'a7000000-0000-0000-0000-000000000005',
    'a6000000-0000-0000-0000-000000000003',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b4',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date - 410,
    current_date - 400,
    current_date - 400,
    85,
    'Due for a refresher.'
  ),
  (
    'a7000000-0000-0000-0000-000000000006',
    'a6000000-0000-0000-0000-000000000003',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date - 70,
    current_date - 60,
    current_date - 60,
    95,
    null
  ),
  (
    'a7000000-0000-0000-0000-000000000007',
    'a6000000-0000-0000-0000-000000000004',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b5',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date - 40,
    current_date - 30,
    current_date - 30,
    90,
    null
  ),
  (
    'a7000000-0000-0000-0000-000000000008',
    'a6000000-0000-0000-0000-000000000004',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b3',
    'd82fb03e-fb7a-424d-84ff-18e2791ce0b2',
    current_date - 3,
    current_date + 10,
    null,
    null,
    null
  );

update quality.training_records
set
  status = 'in_progress'
where
  id = 'a7000000-0000-0000-0000-000000000004';

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
    update quality.document_versions
    set status = 'effective'
    where id = 'a4000000-0000-0000-0000-000000000005'; -- Calibration Procedure v A, still a draft
    raise exception 'GUARD FAILED: a draft document version was published without review or approval.';
  exception
    when others then
      raise notice 'Guard confirmed: %', sqlerrm;
  end;
end;
$$;

do $$
begin
  begin
    update quality.audit_findings
    set status = 'closed'
    where id = 'b3000000-0000-0000-0000-000000000005'; -- major finding, no CAPA raised yet
    raise exception 'GUARD FAILED: a major finding closed with no CAPA against it.';
  exception
    when others then
      raise notice 'Guard confirmed: %', sqlerrm;
  end;
end;
$$;

do $$
begin
  begin
    update quality.capas
    set status = 'closed'
    where id = 'd1000000-0000-0000-0000-000000000002'; -- actions done, effectiveness still pending
    raise exception 'GUARD FAILED: a CAPA closed before its effectiveness check came back effective.';
  exception
    when others then
      raise notice 'Guard confirmed: %', sqlerrm;
  end;
end;
$$;

refresh materialized view quality.quality_kpi_rollup;
