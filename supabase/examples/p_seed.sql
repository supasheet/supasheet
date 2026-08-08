-- Procurement Seeder
-- ================================================================
-- Demo data for the procurement (source-to-pay) module. Apply
-- supabase/examples/20260807000000_procurement.sql first:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260807000000_procurement.sql \
--     -f supabase/examples/p_seed.sql
--
-- Five departments, ten spend categories in a two-level tree, ten
-- suppliers spanning the whole status/risk spectrum (one preferred,
-- one on hold, one blacklisted, one still prospective), compliance
-- documents including two already expired, five contracts (one
-- expiring inside 30 days with auto-renew on, one already expired),
-- eight requisitions walked through drafting, a sequential approval
-- chain, conversion, rejection and cancellation, six purchase orders
-- carried from draft through sending, receiving — including one with
-- a damaged-goods rejection — invoicing and, for the fully-settled
-- one, payment and close. One invoice is deliberately left in
-- `discrepancy`: it was billed 10% over the order price, which is
-- outside its 2% tolerance, and the three-way match trigger refuses
-- to let it move to `approved`. Three RFQs show the sourcing side —
-- one fully awarded, one still open, one still a draft — plus
-- supplier performance reviews and a handful of tracked savings.
--
-- The file closes with two deliberate failures: a purchase order
-- against a blacklisted supplier, and one that would push a contract
-- over its ceiling. Both are caught and reported with RAISE NOTICE —
-- if either one silently succeeds, the guard trigger that is supposed
-- to stop it has regressed.
--
-- Dates are relative to `current_date`, so the monthly spend trend
-- and the requisition-approval charts have shape whenever this runs.
--
-- Five users are seeded (`on conflict do nothing`, so this is safe
-- alongside supabase/seed.sql and the other examples):
--   c9a1b03e-fb7a-424d-84ff-18e2791ce0a1  director@supasheet.app           (x-admin)
--   c9a1b03e-fb7a-424d-84ff-18e2791ce0a2  procurement-buyer@supasheet.app  (buyer)
--   c9a1b03e-fb7a-424d-84ff-18e2791ce0a3  approver@supasheet.app           (approver)
--   c9a1b03e-fb7a-424d-84ff-18e2791ce0a4  requester1@supasheet.app         (user)
--   c9a1b03e-fb7a-424d-84ff-18e2791ce0a5  requester2@supasheet.app         (user)
--
-- Sign in as procurement-buyer@supasheet.app for the DAY-TO-DAY PROCUREMENT seat:
-- sourcing, contracts, orders, receiving and invoice matching.
-- approver@supasheet.app is the BUDGET OWNER seat — requisitions and
-- orders waiting on a decision, and nothing else to edit.
-- requester1@supasheet.app / requester2@supasheet.app are ordinary
-- employees: their own requisitions and a redacted supplier
-- directory.
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
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    'authenticated',
    'authenticated',
    'director@supasheet.app',
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
    '{"sub": "c9a1b03e-fb7a-424d-84ff-18e2791ce0a1", "email": "director@supasheet.app", "name": "Priya Anand", "email_verified": false, "phone_verified": false}',
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
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'authenticated',
    'authenticated',
    'procurement-buyer@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "buyer"}',
    '{"sub": "c9a1b03e-fb7a-424d-84ff-18e2791ce0a2", "email": "procurement-buyer@supasheet.app", "name": "Jordan Wells", "email_verified": false, "phone_verified": false}',
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
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'authenticated',
    'authenticated',
    'approver@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "approver"}',
    '{"sub": "c9a1b03e-fb7a-424d-84ff-18e2791ce0a3", "email": "approver@supasheet.app", "name": "Sofia Marchetti", "email_verified": false, "phone_verified": false}',
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
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a4',
    'authenticated',
    'authenticated',
    'requester1@supasheet.app',
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
    '{"sub": "c9a1b03e-fb7a-424d-84ff-18e2791ce0a4", "email": "requester1@supasheet.app", "name": "Tom Delgado", "email_verified": false, "phone_verified": false}',
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
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a5',
    'authenticated',
    'authenticated',
    'requester2@supasheet.app',
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
    '{"sub": "c9a1b03e-fb7a-424d-84ff-18e2791ce0a5", "email": "requester2@supasheet.app", "name": "Amara Osei", "email_verified": false, "phone_verified": false}',
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
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    '{"sub": "c9a1b03e-fb7a-424d-84ff-18e2791ce0a1", "email": "director@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'a1b1b03e-24a4-41a8-9742-1b5b4e2d8aa1'
  ),
  (
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    '{"sub": "c9a1b03e-fb7a-424d-84ff-18e2791ce0a2", "email": "procurement-buyer@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'a1b1b03e-24a4-41a8-9742-1b5b4e2d8aa2'
  ),
  (
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    '{"sub": "c9a1b03e-fb7a-424d-84ff-18e2791ce0a3", "email": "approver@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'a1b1b03e-24a4-41a8-9742-1b5b4e2d8aa3'
  ),
  (
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a4',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a4',
    '{"sub": "c9a1b03e-fb7a-424d-84ff-18e2791ce0a4", "email": "requester1@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'a1b1b03e-24a4-41a8-9742-1b5b4e2d8aa4'
  ),
  (
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a5',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a5',
    '{"sub": "c9a1b03e-fb7a-424d-84ff-18e2791ce0a5", "email": "requester2@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    'a1b1b03e-24a4-41a8-9742-1b5b4e2d8aa5'
  )
on conflict do nothing;

----------------------------------------------------------------
-- Departments
----------------------------------------------------------------
insert into
  procurement.departments (
    id,
    code,
    name,
    description,
    budget_owner_id,
    cost_center_code,
    annual_budget,
    is_active,
    color
  )
values
  (
    'd1000000-0000-0000-0000-000000000001',
    'ENG',
    'Engineering',
    'Product engineering and developer tooling.',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'CC-100',
    250000,
    true,
    '#2563eb'
  ),
  (
    'd1000000-0000-0000-0000-000000000002',
    'MKT',
    'Marketing',
    'Brand, campaigns and events.',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'CC-200',
    120000,
    true,
    '#db2777'
  ),
  (
    'd1000000-0000-0000-0000-000000000003',
    'OPS',
    'Operations',
    'Facilities, logistics and day-to-day running.',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'CC-300',
    180000,
    true,
    '#16a34a'
  ),
  (
    'd1000000-0000-0000-0000-000000000004',
    'ITD',
    'Information Technology',
    'Internal systems and software licensing.',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    'CC-400',
    150000,
    true,
    '#7c3aed'
  ),
  (
    'd1000000-0000-0000-0000-000000000005',
    'FIN',
    'Finance',
    'Accounting, audit and treasury.',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    'CC-500',
    90000,
    true,
    '#ea580c'
  );

----------------------------------------------------------------
-- Categories
----------------------------------------------------------------
insert into
  procurement.categories (
    id,
    parent_id,
    code,
    name,
    description,
    default_approval_threshold,
    is_active,
    color
  )
values
  (
    'c1000000-0000-0000-0000-000000000001',
    null,
    'IT',
    'Information Technology',
    'Everything IT that is not broken out below.',
    3000,
    true,
    '#7c3aed'
  ),
  (
    'c1000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000001',
    'IT-HW',
    'Hardware',
    'Laptops, monitors, peripherals.',
    2000,
    true,
    '#8b5cf6'
  ),
  (
    'c1000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-000000000001',
    'IT-SW',
    'Software',
    'Licenses, SaaS subscriptions.',
    2500,
    true,
    '#a78bfa'
  ),
  (
    'c1000000-0000-0000-0000-000000000004',
    null,
    'FAC',
    'Facilities',
    'Office services and building upkeep.',
    1500,
    true,
    '#16a34a'
  ),
  (
    'c1000000-0000-0000-0000-000000000005',
    null,
    'MKT',
    'Marketing',
    'Campaigns, events, agency spend.',
    2000,
    true,
    '#db2777'
  ),
  (
    'c1000000-0000-0000-0000-000000000006',
    null,
    'PROF',
    'Professional Services',
    'Consulting, legal, audit.',
    5000,
    true,
    '#ea580c'
  ),
  (
    'c1000000-0000-0000-0000-000000000007',
    'c1000000-0000-0000-0000-000000000006',
    'PROF-CON',
    'Consulting',
    'Freelance and agency engagements.',
    5000,
    true,
    '#f97316'
  ),
  (
    'c1000000-0000-0000-0000-000000000008',
    null,
    'RAW',
    'Raw Materials',
    'Direct materials for production.',
    4000,
    true,
    '#b45309'
  ),
  (
    'c1000000-0000-0000-0000-000000000009',
    null,
    'LOG',
    'Logistics',
    'Freight, warehousing, distribution.',
    3000,
    true,
    '#0891b2'
  ),
  (
    'c1000000-0000-0000-0000-00000000000a',
    null,
    'MRO',
    'Maintenance, Repair & Operating',
    'Consumables that keep the building running.',
    1000,
    true,
    '#64748b'
  );

----------------------------------------------------------------
-- Suppliers
----------------------------------------------------------------
insert into
  procurement.suppliers (
    id,
    code,
    name,
    legal_name,
    category_id,
    status,
    risk_rating,
    is_preferred,
    tax_number,
    email,
    phone,
    website,
    address,
    country,
    currency,
    payment_terms_days,
    incoterms,
    bank_details,
    onboarded_on,
    notes
  )
values
  (
    'a1000000-0000-0000-0000-000000000001',
    'TSC001',
    'TechSupply Corp',
    'TechSupply Corporation Ltd',
    'c1000000-0000-0000-0000-000000000002',
    'active',
    'low',
    true,
    'US-TAX-88213',
    'sales@techsupply.example',
    '+1-415-555-0142',
    'https://techsupply.example',
    '400 Harbor Way, San Jose, CA',
    'United States',
    'USD',
    30,
    'DAP',
    'Chase •••• 4471',
    current_date - 720,
    'Long-standing hardware partner. Consistently on time.'
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    'CSS002',
    'CloudSoft Solutions',
    'CloudSoft Solutions Inc',
    'c1000000-0000-0000-0000-000000000003',
    'active',
    'low',
    true,
    'US-TAX-55019',
    'accounts@cloudsoft.example',
    '+1-206-555-0198',
    'https://cloudsoft.example',
    '88 Pike Street, Seattle, WA',
    'United States',
    'USD',
    30,
    null,
    'Wells Fargo •••• 2290',
    current_date - 540,
    'Collaboration suite vendor, annual licensing.'
  ),
  (
    'a1000000-0000-0000-0000-000000000003',
    'GOS003',
    'Global Office Supplies',
    'Global Office Supplies LLC',
    'c1000000-0000-0000-0000-000000000004',
    'active',
    'medium',
    false,
    'US-TAX-33012',
    'orders@globaloffice.example',
    '+1-312-555-0110',
    'https://globaloffice.example',
    '12 Wacker Drive, Chicago, IL',
    'United States',
    'USD',
    30,
    null,
    null,
    current_date - 400,
    null
  ),
  (
    'a1000000-0000-0000-0000-000000000004',
    'ACG004',
    'Apex Consulting Group',
    'Apex Consulting Group LLC',
    'c1000000-0000-0000-0000-000000000007',
    'active',
    'medium',
    false,
    'US-TAX-77654',
    'engagements@apexconsulting.example',
    '+1-617-555-0133',
    'https://apexconsulting.example',
    '9 Beacon Street, Boston, MA',
    'United States',
    'USD',
    45,
    null,
    'Citibank •••• 8801',
    current_date - 300,
    'Marketing and brand consulting.'
  ),
  (
    'a1000000-0000-0000-0000-000000000005',
    'RLC005',
    'Reliable Logistics Co',
    'Reliable Logistics Company',
    'c1000000-0000-0000-0000-000000000009',
    'active',
    'low',
    true,
    'US-TAX-44120',
    'dispatch@reliablelogistics.example',
    '+1-901-555-0177',
    'https://reliablelogistics.example',
    '210 Freight Yard Rd, Memphis, TN',
    'United States',
    'USD',
    30,
    'FOB',
    'US Bank •••• 5567',
    current_date - 650,
    'Primary freight partner, strong on-time record.'
  ),
  (
    'a1000000-0000-0000-0000-000000000006',
    'PRM006',
    'Prime Raw Materials',
    'Prime Raw Materials Inc',
    'c1000000-0000-0000-0000-000000000008',
    'active',
    'high',
    false,
    'US-TAX-99213',
    'sales@primerawmaterials.example',
    '+1-216-555-0166',
    'https://primerawmaterials.example',
    '77 Foundry Ave, Cleveland, OH',
    'United States',
    'USD',
    30,
    'FCA',
    'PNC •••• 1123',
    current_date - 900,
    'Single-source for grade A steel stock — concentration risk.'
  ),
  (
    'a1000000-0000-0000-0000-000000000007',
    'FFS007',
    'FixIt Facilities Services',
    'FixIt Facilities Services Inc',
    'c1000000-0000-0000-0000-000000000004',
    'on_hold',
    'high',
    false,
    'US-TAX-22087',
    'support@fixitfacilities.example',
    '+1-503-555-0155',
    null,
    '55 Industrial Loop, Portland, OR',
    'United States',
    'USD',
    30,
    null,
    null,
    current_date - 500,
    'On hold: repeated missed SLAs and an expired insurance certificate.'
  ),
  (
    'a1000000-0000-0000-0000-000000000008',
    'QPL008',
    'QuestionableParts Ltd',
    'QuestionableParts Limited',
    'c1000000-0000-0000-0000-000000000008',
    'blacklisted',
    'critical',
    false,
    'US-TAX-11209',
    'sales@questionableparts.example',
    '+1-330-555-0121',
    null,
    '3 Scrapyard Rd, Akron, OH',
    'United States',
    'USD',
    30,
    null,
    null,
    current_date - 800,
    'Blacklisted after repeated material quality failures on grade A stock.'
  ),
  (
    'a1000000-0000-0000-0000-000000000009',
    'NVI009',
    'NewVendor Innovations',
    'NewVendor Innovations Inc',
    'c1000000-0000-0000-0000-000000000003',
    'prospective',
    'medium',
    false,
    null,
    'hello@newvendorinnovations.example',
    '+1-512-555-0199',
    'https://newvendorinnovations.example',
    '5 Startup Row, Austin, TX',
    'United States',
    'USD',
    30,
    null,
    null,
    null,
    'Still being onboarded — no live orders yet.'
  ),
  (
    'a1000000-0000-0000-0000-00000000000a',
    'SGI010',
    'SecureGuard Insurance Brokers',
    'SecureGuard Insurance Brokers LLC',
    'c1000000-0000-0000-0000-000000000006',
    'active',
    'low',
    false,
    'US-TAX-66142',
    'broker@secureguard.example',
    '+1-212-555-0188',
    'https://secureguard.example',
    '1 Liberty Plaza, New York, NY',
    'United States',
    'USD',
    30,
    null,
    null,
    current_date - 250,
    null
  );

----------------------------------------------------------------
-- Supplier contacts
----------------------------------------------------------------
insert into
  procurement.supplier_contacts (
    id,
    supplier_id,
    name,
    title,
    email,
    phone,
    is_primary
  )
values
  (
    'a2000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000001',
    'Renee Ibarra',
    'Account Manager',
    'renee.ibarra@techsupply.example',
    '+1-415-555-0143',
    true
  ),
  (
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'Kofi Mensah',
    'Logistics Coordinator',
    'kofi.mensah@techsupply.example',
    '+1-415-555-0144',
    false
  ),
  (
    'a2000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000002',
    'Hana Suzuki',
    'Customer Success Lead',
    'hana.suzuki@cloudsoft.example',
    '+1-206-555-0199',
    true
  ),
  (
    'a2000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000004',
    'Marcus Delaney',
    'Engagement Partner',
    'marcus.delaney@apexconsulting.example',
    '+1-617-555-0134',
    true
  ),
  (
    'a2000000-0000-0000-0000-000000000005',
    'a1000000-0000-0000-0000-000000000005',
    'Priya Chandran',
    'Dispatch Manager',
    'priya.chandran@reliablelogistics.example',
    '+1-901-555-0178',
    true
  ),
  (
    'a2000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-000000000006',
    'Owen Bratton',
    'Sales Director',
    'owen.bratton@primerawmaterials.example',
    '+1-216-555-0167',
    true
  );

----------------------------------------------------------------
-- Supplier compliance documents
----------------------------------------------------------------
insert into
  procurement.supplier_documents (
    id,
    supplier_id,
    document_type,
    name,
    issued_on,
    expires_on,
    is_required,
    is_verified,
    verified_by
  )
values
  (
    'a3000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000001',
    'insurance',
    'General Liability Certificate',
    current_date - 165,
    current_date + 200,
    true,
    true,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2'
  ),
  (
    'a3000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'w9_tax_form',
    'W-9 Tax Form',
    current_date - 700,
    null,
    true,
    true,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2'
  ),
  (
    'a3000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000002',
    'quality_certification',
    'ISO 27001 Certificate',
    current_date - 400,
    current_date - 15,
    true,
    false,
    null
  ),
  (
    'a3000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000006',
    'insurance',
    'General Liability Certificate',
    current_date - 355,
    current_date + 10,
    true,
    true,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2'
  ),
  (
    'a3000000-0000-0000-0000-000000000005',
    'a1000000-0000-0000-0000-000000000006',
    'business_license',
    'State Business License',
    current_date - 900,
    current_date + 300,
    true,
    true,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2'
  ),
  (
    'a3000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-000000000007',
    'insurance',
    'General Liability Certificate',
    current_date - 420,
    current_date - 40,
    true,
    false,
    null
  ),
  (
    'a3000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000008',
    'quality_certification',
    'Material Test Reports Accreditation',
    current_date - 600,
    current_date - 200,
    true,
    false,
    null
  ),
  (
    'a3000000-0000-0000-0000-000000000008',
    'a1000000-0000-0000-0000-00000000000a',
    'nda',
    'Mutual NDA',
    current_date - 250,
    current_date + 365,
    false,
    true,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2'
  );

----------------------------------------------------------------
-- Contracts
----------------------------------------------------------------
insert into
  procurement.contracts (
    id,
    supplier_id,
    category_id,
    owner_id,
    contract_type,
    status,
    title,
    start_date,
    end_date,
    currency,
    ceiling_amount,
    auto_renew,
    renewal_notice_days,
    payment_terms_days
  )
values
  (
    'b1000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000002',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'blanket',
    'active',
    'Hardware Refresh Blanket Agreement FY26',
    current_date - 180,
    current_date + 20,
    'USD',
    100000,
    true,
    30,
    30
  ),
  (
    'b1000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000003',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'framework',
    'active',
    'Collaboration Suite Framework Agreement',
    current_date - 90,
    current_date + 275,
    'USD',
    60000,
    false,
    30,
    30
  ),
  (
    'b1000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000005',
    'c1000000-0000-0000-0000-000000000009',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'blanket',
    'active',
    'Freight & Distribution Blanket Agreement',
    current_date - 60,
    current_date + 305,
    'USD',
    40000,
    true,
    45,
    30
  ),
  (
    'b1000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000004',
    'c1000000-0000-0000-0000-000000000007',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'service',
    'active',
    'Marketing Consulting Services Agreement',
    current_date - 120,
    current_date + 245,
    'USD',
    80000,
    false,
    30,
    45
  ),
  (
    'b1000000-0000-0000-0000-000000000005',
    'a1000000-0000-0000-0000-000000000006',
    'c1000000-0000-0000-0000-000000000008',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'spot',
    'expired',
    'FY25 Raw Materials Spot Agreement',
    current_date - 400,
    current_date - 30,
    'USD',
    20000,
    false,
    30,
    30
  );

----------------------------------------------------------------
-- Requisitions
----------------------------------------------------------------
insert into
  procurement.purchase_requisitions (
    id,
    department_id,
    category_id,
    requester_id,
    priority,
    needed_by,
    justification,
    submitted_at,
    created_at
  )
values
  (
    'e1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000002',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a4',
    'high',
    current_date + 14,
    'Replace aging developer laptops before the Q3 onboarding wave.',
    current_timestamp - interval '89 days',
    current_timestamp - interval '90 days'
  ),
  (
    'e1000000-0000-0000-0000-000000000002',
    'd1000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000007',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a5',
    'normal',
    current_date + 20,
    'Freelance video editor engagement for the Q3 campaign.',
    current_timestamp - interval '59 days',
    current_timestamp - interval '60 days'
  ),
  (
    'e1000000-0000-0000-0000-000000000003',
    'd1000000-0000-0000-0000-000000000004',
    'c1000000-0000-0000-0000-000000000003',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a4',
    'normal',
    current_date + 25,
    'Annual renewal for the team collaboration suite, 50 seats.',
    current_timestamp - interval '39 days',
    current_timestamp - interval '40 days'
  ),
  (
    'e1000000-0000-0000-0000-000000000004',
    'd1000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-000000000009',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a5',
    'high',
    current_date + 15,
    'Q4 freight consolidation contract drawdown.',
    current_timestamp - interval '44 days',
    current_timestamp - interval '45 days'
  ),
  (
    'e1000000-0000-0000-0000-000000000005',
    'd1000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000005',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a5',
    'low',
    current_date + 40,
    'Trade show booth signage and swag for the fall conference.',
    null,
    current_timestamp - interval '5 days'
  ),
  (
    'e1000000-0000-0000-0000-000000000006',
    'd1000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000001',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a4',
    'normal',
    current_date + 21,
    'Adjustable standing desks for four new engineering hires.',
    current_timestamp - interval '8 days',
    current_timestamp - interval '8 days'
  ),
  (
    'e1000000-0000-0000-0000-000000000007',
    'd1000000-0000-0000-0000-000000000005',
    'c1000000-0000-0000-0000-000000000006',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a5',
    'normal',
    current_date + 10,
    'External audit readiness consulting engagement.',
    current_timestamp - interval '24 days',
    current_timestamp - interval '25 days'
  ),
  (
    'e1000000-0000-0000-0000-000000000008',
    'd1000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-00000000000a',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a5',
    'low',
    current_date + 5,
    'Replacement HVAC filters for building 2.',
    null,
    current_timestamp - interval '3 days'
  );

----------------------------------------------------------------
-- Requisition lines
----------------------------------------------------------------
insert into
  procurement.requisition_lines (
    id,
    requisition_id,
    category_id,
    suggested_supplier_id,
    description,
    quantity,
    uom,
    estimated_unit_price,
    needed_by
  )
values
  (
    'e2000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'Dell XPS 15 Developer Laptop',
    5,
    'EA',
    1800,
    current_date + 10
  ),
  (
    'e2000000-0000-0000-0000-000000000002',
    'e1000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'USB-C Docking Station',
    5,
    'EA',
    150,
    current_date + 10
  ),
  (
    'e2000000-0000-0000-0000-000000000003',
    'e1000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000004',
    'Video production & editing engagement',
    1,
    'EA',
    6000,
    current_date + 18
  ),
  (
    'e2000000-0000-0000-0000-000000000004',
    'e1000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000002',
    'CloudSoft Collaboration Suite — Annual License (50 seats)',
    1,
    'EA',
    18000,
    current_date + 20
  ),
  (
    'e2000000-0000-0000-0000-000000000005',
    'e1000000-0000-0000-0000-000000000004',
    'c1000000-0000-0000-0000-000000000009',
    'a1000000-0000-0000-0000-000000000005',
    'Freight consolidation services — Q4 block',
    1,
    'EA',
    25000,
    current_date + 10
  ),
  (
    'e2000000-0000-0000-0000-000000000006',
    'e1000000-0000-0000-0000-000000000005',
    'c1000000-0000-0000-0000-000000000005',
    null,
    'Trade show booth package',
    1,
    'EA',
    4200,
    current_date + 35
  ),
  (
    'e2000000-0000-0000-0000-000000000007',
    'e1000000-0000-0000-0000-000000000006',
    'c1000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000003',
    'Adjustable Standing Desk',
    4,
    'EA',
    450,
    current_date + 18
  ),
  (
    'e2000000-0000-0000-0000-000000000008',
    'e1000000-0000-0000-0000-000000000007',
    'c1000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-00000000000a',
    'Audit readiness consulting engagement',
    1,
    'EA',
    22000,
    current_date + 8
  ),
  (
    'e2000000-0000-0000-0000-000000000009',
    'e1000000-0000-0000-0000-000000000008',
    'c1000000-0000-0000-0000-00000000000a',
    'a1000000-0000-0000-0000-000000000003',
    'HVAC Filter 20x25x1',
    20,
    'EA',
    8,
    current_date + 4
  );

----------------------------------------------------------------
-- Requisition approvals
--
-- Chains are built the way procurement.submit_requisition() builds
-- them: one step against the department's budget owner, plus a
-- second, director-level step whenever the requisition is more than
-- three times its category's approval threshold.
----------------------------------------------------------------
insert into
  procurement.requisition_approvals (
    id,
    requisition_id,
    step_number,
    approver_id,
    status,
    threshold_amount,
    decided_by,
    decided_at
  )
values
  -- R1: 9750 > 3x IT-HW threshold (6000) — two steps, both approved
  (
    'e3000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000001',
    1,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'approved',
    2000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    current_timestamp - interval '85 days'
  ),
  (
    'e3000000-0000-0000-0000-000000000002',
    'e1000000-0000-0000-0000-000000000001',
    2,
    null,
    'approved',
    6000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    current_timestamp - interval '84 days'
  ),
  -- R2: 6000 < 3x Consulting threshold (15000) — one step
  (
    'e3000000-0000-0000-0000-000000000003',
    'e1000000-0000-0000-0000-000000000002',
    1,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'approved',
    5000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    current_timestamp - interval '58 days'
  ),
  -- R3: 18000 > 3x IT-SW threshold (7500) — two steps
  (
    'e3000000-0000-0000-0000-000000000004',
    'e1000000-0000-0000-0000-000000000003',
    1,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'approved',
    2500,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    current_timestamp - interval '38 days'
  ),
  (
    'e3000000-0000-0000-0000-000000000005',
    'e1000000-0000-0000-0000-000000000003',
    2,
    null,
    'approved',
    7500,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    current_timestamp - interval '37 days'
  ),
  -- R4: 25000 > 3x Logistics threshold (9000) — two steps
  (
    'e3000000-0000-0000-0000-000000000006',
    'e1000000-0000-0000-0000-000000000004',
    1,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'approved',
    3000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    current_timestamp - interval '43 days'
  ),
  (
    'e3000000-0000-0000-0000-000000000007',
    'e1000000-0000-0000-0000-000000000004',
    2,
    null,
    'approved',
    9000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    current_timestamp - interval '42 days'
  ),
  -- R6: still waiting on step one
  (
    'e3000000-0000-0000-0000-000000000008',
    'e1000000-0000-0000-0000-000000000006',
    1,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'pending',
    3000,
    null,
    null
  ),
  -- R7: step one approved, director-level step rejected — over budget
  (
    'e3000000-0000-0000-0000-000000000009',
    'e1000000-0000-0000-0000-000000000007',
    1,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'approved',
    5000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    current_timestamp - interval '23 days'
  ),
  (
    'e3000000-0000-0000-0000-00000000000a',
    'e1000000-0000-0000-0000-000000000007',
    2,
    null,
    'rejected',
    15000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    current_timestamp - interval '22 days'
  );

update procurement.purchase_requisitions
set
  rejected_reason = 'Deferred to next fiscal year — discretionary consulting budget is frozen for the remainder of Q3.'
where
  id = 'e1000000-0000-0000-0000-000000000007';

-- R8 was never submitted for approval — the requester withdrew it.
update procurement.purchase_requisitions
set
  status = 'cancelled'
where
  id = 'e1000000-0000-0000-0000-000000000008';

----------------------------------------------------------------
-- Purchase orders
----------------------------------------------------------------
insert into
  procurement.purchase_orders (
    id,
    supplier_id,
    requisition_id,
    contract_id,
    department_id,
    category_id,
    buyer_id,
    status,
    priority,
    order_date,
    expected_delivery_date,
    delivery_address,
    supplier_reference,
    sent_at,
    acknowledged_at,
    closed_at
  )
values
  (
    'f1000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000002',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'closed',
    'high',
    current_date - 80,
    current_date - 65,
    '400 Product Way, San Francisco, CA',
    'TSC-SO-8891',
    current_timestamp - interval '77 days',
    current_timestamp - interval '76 days',
    current_timestamp - interval '48 days'
  ),
  (
    'f1000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000004',
    'e1000000-0000-0000-0000-000000000002',
    'b1000000-0000-0000-0000-000000000004',
    'd1000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000007',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'received',
    'normal',
    current_date - 55,
    current_date - 40,
    '400 Product Way, San Francisco, CA',
    'ACG-ENG-2214',
    current_timestamp - interval '53 days',
    current_timestamp - interval '52 days',
    null
  ),
  (
    'f1000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000002',
    'e1000000-0000-0000-0000-000000000003',
    'b1000000-0000-0000-0000-000000000002',
    'd1000000-0000-0000-0000-000000000004',
    'c1000000-0000-0000-0000-000000000003',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'sent',
    'normal',
    current_date - 35,
    current_date + 5,
    '400 Product Way, San Francisco, CA',
    'CSS-REN-5510',
    current_timestamp - interval '32 days',
    null,
    null
  ),
  (
    'f1000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000005',
    'e1000000-0000-0000-0000-000000000004',
    'b1000000-0000-0000-0000-000000000003',
    'd1000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-000000000009',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'received',
    'high',
    current_date - 40,
    current_date - 20,
    '77 Distribution Center Dr, Memphis, TN',
    'RLC-Q4-330',
    current_timestamp - interval '38 days',
    current_timestamp - interval '37 days',
    null
  ),
  (
    'f1000000-0000-0000-0000-000000000005',
    'a1000000-0000-0000-0000-000000000001',
    null,
    'b1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000002',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'draft',
    'low',
    current_date - 10,
    current_date + 10,
    '400 Product Way, San Francisco, CA',
    null,
    null,
    null,
    null
  ),
  (
    'f1000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-000000000006',
    null,
    null,
    'd1000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-000000000008',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'received',
    'normal',
    current_date - 15,
    current_date - 5,
    '90 Production Plant Rd, Detroit, MI',
    'PRM-SO-6641',
    current_timestamp - interval '13 days',
    current_timestamp - interval '12 days',
    null
  );

----------------------------------------------------------------
-- Purchase order lines
----------------------------------------------------------------
insert into
  procurement.purchase_order_lines (
    id,
    po_id,
    requisition_line_id,
    category_id,
    description,
    quantity_ordered,
    uom,
    unit_price,
    needed_by
  )
values
  (
    'f2000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000002',
    'Dell XPS 15 Developer Laptop',
    5,
    'EA',
    1800,
    current_date - 65
  ),
  (
    'f2000000-0000-0000-0000-000000000002',
    'f1000000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000002',
    'USB-C Docking Station',
    5,
    'EA',
    150,
    current_date - 65
  ),
  (
    'f2000000-0000-0000-0000-000000000003',
    'f1000000-0000-0000-0000-000000000002',
    'e2000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-000000000007',
    'Video production & editing engagement',
    1,
    'EA',
    6000,
    current_date - 40
  ),
  (
    'f2000000-0000-0000-0000-000000000004',
    'f1000000-0000-0000-0000-000000000003',
    'e2000000-0000-0000-0000-000000000004',
    'c1000000-0000-0000-0000-000000000003',
    'CloudSoft Collaboration Suite — Annual License (50 seats)',
    1,
    'EA',
    18000,
    current_date + 5
  ),
  (
    'f2000000-0000-0000-0000-000000000005',
    'f1000000-0000-0000-0000-000000000004',
    'e2000000-0000-0000-0000-000000000005',
    'c1000000-0000-0000-0000-000000000009',
    'Freight consolidation services — Q4 block',
    1,
    'EA',
    25000,
    current_date - 20
  ),
  (
    'f2000000-0000-0000-0000-000000000006',
    'f1000000-0000-0000-0000-000000000005',
    null,
    'c1000000-0000-0000-0000-000000000002',
    'Wireless Mouse',
    10,
    'EA',
    25,
    current_date + 10
  ),
  (
    'f2000000-0000-0000-0000-000000000007',
    'f1000000-0000-0000-0000-000000000006',
    null,
    'c1000000-0000-0000-0000-000000000008',
    'Steel Rod Stock — Grade A',
    1000,
    'EA',
    4.5,
    current_date - 5
  ),
  (
    'f2000000-0000-0000-0000-000000000008',
    'f1000000-0000-0000-0000-000000000006',
    null,
    'c1000000-0000-0000-0000-000000000008',
    'Aluminum Sheet 4x8',
    500,
    'EA',
    12,
    current_date - 5
  );

update procurement.purchase_requisitions
set
  status = 'converted'
where
  id in (
    'e1000000-0000-0000-0000-000000000001',
    'e1000000-0000-0000-0000-000000000002',
    'e1000000-0000-0000-0000-000000000003',
    'e1000000-0000-0000-0000-000000000004'
  );

----------------------------------------------------------------
-- PO approvals
----------------------------------------------------------------
insert into
  procurement.po_approvals (
    id,
    po_id,
    step_number,
    approver_id,
    status,
    threshold_amount,
    decided_by,
    decided_at
  )
values
  (
    'f3000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000001',
    1,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'approved',
    2000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    current_timestamp - interval '79 days'
  ),
  (
    'f3000000-0000-0000-0000-000000000002',
    'f1000000-0000-0000-0000-000000000001',
    2,
    null,
    'approved',
    6000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    current_timestamp - interval '78 days'
  ),
  (
    'f3000000-0000-0000-0000-000000000003',
    'f1000000-0000-0000-0000-000000000002',
    1,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'approved',
    5000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    current_timestamp - interval '54 days'
  ),
  (
    'f3000000-0000-0000-0000-000000000004',
    'f1000000-0000-0000-0000-000000000003',
    1,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'approved',
    2500,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    current_timestamp - interval '34 days'
  ),
  (
    'f3000000-0000-0000-0000-000000000005',
    'f1000000-0000-0000-0000-000000000003',
    2,
    null,
    'approved',
    7500,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    current_timestamp - interval '33 days'
  ),
  (
    'f3000000-0000-0000-0000-000000000006',
    'f1000000-0000-0000-0000-000000000004',
    1,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'approved',
    3000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    current_timestamp - interval '39 days'
  ),
  (
    'f3000000-0000-0000-0000-000000000007',
    'f1000000-0000-0000-0000-000000000004',
    2,
    null,
    'approved',
    9000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a1',
    current_timestamp - interval '38 days'
  ),
  (
    'f3000000-0000-0000-0000-000000000008',
    'f1000000-0000-0000-0000-000000000006',
    1,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    'approved',
    4000,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a3',
    current_timestamp - interval '14 days'
  );

-- PO5 never left draft, then the requirement was superseded.
update procurement.purchase_orders
set
  status = 'cancelled',
  cancelled_reason = 'Requirement superseded by the upcoming hardware refresh contract renewal.'
where
  id = 'f1000000-0000-0000-0000-000000000005';

----------------------------------------------------------------
-- Goods receipts
----------------------------------------------------------------
insert into
  procurement.goods_receipts (
    id,
    purchase_order_id,
    received_by,
    received_on,
    status,
    delivery_note_reference,
    carrier
  )
values
  (
    'c2000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000001',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    current_date - 70,
    'posted',
    'DN-TSC-001',
    'FedEx Freight'
  ),
  (
    'c2000000-0000-0000-0000-000000000002',
    'f1000000-0000-0000-0000-000000000001',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    current_date - 60,
    'posted',
    'DN-TSC-002',
    'FedEx Freight'
  ),
  (
    'c2000000-0000-0000-0000-000000000003',
    'f1000000-0000-0000-0000-000000000002',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    current_date - 35,
    'posted',
    'DN-ACG-001',
    null
  ),
  (
    'c2000000-0000-0000-0000-000000000004',
    'f1000000-0000-0000-0000-000000000004',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    current_date - 25,
    'posted',
    'DN-RLC-001',
    'Reliable Logistics'
  ),
  (
    'c2000000-0000-0000-0000-000000000005',
    'f1000000-0000-0000-0000-000000000006',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    current_date - 6,
    'posted',
    'DN-PRM-001',
    'Prime Freight'
  );

----------------------------------------------------------------
-- Goods receipt lines
----------------------------------------------------------------
insert into
  procurement.goods_receipt_lines (
    id,
    receipt_id,
    po_line_id,
    quantity_received,
    quantity_accepted,
    quantity_rejected,
    condition,
    rejection_reason
  )
values
  (
    'c3000000-0000-0000-0000-000000000001',
    'c2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000001',
    3,
    3,
    0,
    'accepted',
    null
  ),
  (
    'c3000000-0000-0000-0000-000000000002',
    'c2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000002',
    5,
    5,
    0,
    'accepted',
    null
  ),
  (
    'c3000000-0000-0000-0000-000000000003',
    'c2000000-0000-0000-0000-000000000002',
    'f2000000-0000-0000-0000-000000000001',
    2,
    2,
    0,
    'accepted',
    null
  ),
  (
    'c3000000-0000-0000-0000-000000000004',
    'c2000000-0000-0000-0000-000000000003',
    'f2000000-0000-0000-0000-000000000003',
    1,
    1,
    0,
    'accepted',
    null
  ),
  (
    'c3000000-0000-0000-0000-000000000005',
    'c2000000-0000-0000-0000-000000000004',
    'f2000000-0000-0000-0000-000000000005',
    1,
    1,
    0,
    'accepted',
    null
  ),
  (
    'c3000000-0000-0000-0000-000000000006',
    'c2000000-0000-0000-0000-000000000005',
    'f2000000-0000-0000-0000-000000000007',
    1000,
    950,
    50,
    'damaged',
    'Water damage during transit — pallet wrap was compromised.'
  ),
  (
    'c3000000-0000-0000-0000-000000000007',
    'c2000000-0000-0000-0000-000000000005',
    'f2000000-0000-0000-0000-000000000008',
    500,
    500,
    0,
    'accepted',
    null
  );

----------------------------------------------------------------
-- Vendor invoices
--
-- INV1 matches exactly and is carried through to paid. INV3 matches
-- exactly and is approved but only partly paid. INV2 is billed 10%
-- over the order price on its only line — outside its 2% tolerance —
-- so the match trigger forces it to `discrepancy` and it is left
-- there deliberately: that is the three-way match rule working, not
-- an oversight.
----------------------------------------------------------------
insert into
  procurement.vendor_invoices (
    id,
    supplier_invoice_number,
    purchase_order_id,
    supplier_id,
    invoice_date,
    due_date,
    tolerance_percent
  )
values
  (
    'c4000000-0000-0000-0000-000000000001',
    'TSC-INV-3391',
    'f1000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000001',
    current_date - 58,
    current_date - 28,
    2
  ),
  (
    'c4000000-0000-0000-0000-000000000002',
    'ACG-2291',
    'f1000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000004',
    current_date - 30,
    current_date + 15,
    2
  ),
  (
    'c4000000-0000-0000-0000-000000000003',
    'RLC-Q4-330-INV',
    'f1000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000005',
    current_date - 20,
    current_date + 10,
    2
  );

insert into
  procurement.vendor_invoice_lines (
    id,
    invoice_id,
    po_line_id,
    description,
    quantity_invoiced,
    unit_price
  )
values
  (
    'c5000000-0000-0000-0000-000000000001',
    'c4000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000001',
    'Dell XPS 15 Developer Laptop',
    5,
    1800
  ),
  (
    'c5000000-0000-0000-0000-000000000002',
    'c4000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000002',
    'USB-C Docking Station',
    5,
    150
  ),
  (
    'c5000000-0000-0000-0000-000000000003',
    'c4000000-0000-0000-0000-000000000002',
    'f2000000-0000-0000-0000-000000000003',
    'Video production & editing engagement',
    1,
    6600
  ),
  (
    'c5000000-0000-0000-0000-000000000004',
    'c4000000-0000-0000-0000-000000000003',
    'f2000000-0000-0000-0000-000000000005',
    'Freight consolidation services — Q4 block',
    1,
    25000
  );

-- INV1: matched, approved, paid in full.
update procurement.vendor_invoices
set
  status = 'approved'
where
  id = 'c4000000-0000-0000-0000-000000000001';

update procurement.vendor_invoices
set
  approved_by = 'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
  approved_at = current_timestamp - interval '55 days'
where
  id = 'c4000000-0000-0000-0000-000000000001';

-- INV3: matched, approved, partially paid.
update procurement.vendor_invoices
set
  status = 'approved'
where
  id = 'c4000000-0000-0000-0000-000000000003';

update procurement.vendor_invoices
set
  approved_by = 'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
  approved_at = current_timestamp - interval '18 days'
where
  id = 'c4000000-0000-0000-0000-000000000003';

----------------------------------------------------------------
-- Invoice payments
----------------------------------------------------------------
insert into
  procurement.invoice_payments (
    id,
    invoice_id,
    payment_date,
    amount,
    method,
    reference,
    recorded_by
  )
values
  (
    'c6000000-0000-0000-0000-000000000001',
    'c4000000-0000-0000-0000-000000000001',
    current_date - 50,
    9750,
    'bank_transfer',
    'ACH-77102',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2'
  ),
  (
    'c6000000-0000-0000-0000-000000000002',
    'c4000000-0000-0000-0000-000000000003',
    current_date - 10,
    15000,
    'bank_transfer',
    'ACH-88213',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2'
  );

----------------------------------------------------------------
-- RFQs
----------------------------------------------------------------
insert into
  procurement.rfqs (
    id,
    category_id,
    buyer_id,
    status,
    title,
    description,
    issue_date,
    due_date
  )
values
  (
    'b2000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000008',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'sent',
    'Steel rod stock sourcing — FY26',
    'Annual sourcing event for grade A steel rod stock ahead of the FY26 production plan.',
    current_date - 50,
    current_date - 35
  ),
  (
    'b2000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000005',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'sent',
    'Video production partner for Q4 campaign',
    'Three 60-second spots for the Q4 brand campaign.',
    current_date - 20,
    current_date + 5
  ),
  (
    'b2000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-000000000003',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    'draft',
    'Evaluate alternative helpdesk software',
    'Still scoping requirements before this goes out.',
    current_date,
    current_date + 30
  );

insert into
  procurement.rfq_lines (
    id,
    rfq_id,
    description,
    quantity,
    uom,
    target_price
  )
values
  (
    'b3000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000001',
    'Steel Rod Stock — Grade A',
    1000,
    'EA',
    4.5
  ),
  (
    'b3000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000002',
    'Video production & editing — 3x 60s spots',
    3,
    'EA',
    1800
  );

insert into
  procurement.rfq_suppliers (id, rfq_id, supplier_id, invited_at)
values
  (
    'b4000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000006',
    current_timestamp - interval '50 days'
  ),
  (
    'b4000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000008',
    current_timestamp - interval '50 days'
  ),
  (
    'b4000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000004',
    current_timestamp - interval '20 days'
  ),
  (
    'b4000000-0000-0000-0000-000000000004',
    'b2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000009',
    current_timestamp - interval '20 days'
  );

insert into
  procurement.supplier_quotes (
    id,
    rfq_id,
    supplier_id,
    status,
    quote_reference,
    submitted_at,
    valid_until,
    lead_time_days,
    payment_terms_days,
    is_compliant
  )
values
  (
    'b5000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000006',
    'submitted',
    'PRM-Q-118',
    current_timestamp - interval '45 days',
    current_date - 15,
    14,
    30,
    true
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000008',
    'submitted',
    'QPL-Q-77',
    current_timestamp - interval '44 days',
    current_date - 14,
    10,
    30,
    true
  ),
  (
    'b5000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000004',
    'submitted',
    'ACG-Q-55',
    current_timestamp - interval '12 days',
    current_date + 18,
    21,
    45,
    true
  ),
  (
    'b5000000-0000-0000-0000-000000000004',
    'b2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000009',
    'invited',
    null,
    null,
    null,
    null,
    null,
    true
  );

insert into
  procurement.quote_lines (
    id,
    quote_id,
    rfq_line_id,
    quantity,
    unit_price,
    lead_time_days
  )
values
  (
    'b6000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000001',
    1000,
    4.4,
    14
  ),
  (
    'b6000000-0000-0000-0000-000000000002',
    'b5000000-0000-0000-0000-000000000002',
    'b3000000-0000-0000-0000-000000000001',
    1000,
    4.2,
    10
  ),
  (
    'b6000000-0000-0000-0000-000000000003',
    'b5000000-0000-0000-0000-000000000003',
    'b3000000-0000-0000-0000-000000000002',
    3,
    1800,
    21
  );

-- Award RFQ1 to Prime through the real form function — Prime's quote is
-- marked awarded, QuestionableParts' competing quote is auto-rejected,
-- even though it was the cheaper of the two.
select
  procurement.award_rfq (
    'b2000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000006',
    'Awarded to Prime despite the higher price — QuestionableParts has a pattern of material quality failures and was subsequently blacklisted.'
  );

----------------------------------------------------------------
-- Supplier performance reviews
----------------------------------------------------------------
insert into
  procurement.supplier_performance_reviews (
    id,
    supplier_id,
    reviewed_by,
    review_period,
    period_start,
    period_end,
    on_time_delivery_rate,
    quality_score,
    responsiveness_score,
    cost_competitiveness,
    comments
  )
values
  (
    'd2000000-0000-0000-0000-000000000001',
    'a1000000-0000-0000-0000-000000000001',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    '2026-Q1',
    current_date - 180,
    current_date - 90,
    95,
    4.8,
    4.5,
    3.5,
    'Consistently early. Pricing is fair but not the cheapest.'
  ),
  (
    'd2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    '2026-Q2',
    current_date - 89,
    current_date - 1,
    97,
    4.9,
    4.7,
    3.7,
    'Best quarter yet — zero delivery misses.'
  ),
  (
    'd2000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000002',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    '2026-Q1',
    current_date - 180,
    current_date - 90,
    92,
    4.6,
    4.8,
    4.0,
    'Support response times are excellent.'
  ),
  (
    'd2000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000005',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    '2026-Q1',
    current_date - 180,
    current_date - 90,
    88,
    4.2,
    4.0,
    4.2,
    'Reliable on standard lanes, slower during peak season.'
  ),
  (
    'd2000000-0000-0000-0000-000000000005',
    'a1000000-0000-0000-0000-000000000007',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    '2026-Q1',
    current_date - 180,
    current_date - 90,
    55,
    2.5,
    2.0,
    3.0,
    'Missed SLA repeatedly this quarter; recommend hold pending a corrective action plan.'
  ),
  (
    'd2000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-000000000004',
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    '2026-Q1',
    current_date - 180,
    current_date - 90,
    90,
    4.0,
    4.3,
    3.8,
    'Solid engagement delivery; one invoice discrepancy this quarter.'
  );

----------------------------------------------------------------
-- Cost savings
----------------------------------------------------------------
insert into
  procurement.cost_savings (
    id,
    category_id,
    supplier_id,
    contract_id,
    savings_type,
    baseline_amount,
    negotiated_amount,
    realized,
    recorded_by,
    recorded_on,
    notes
  )
values
  (
    'd3000000-0000-0000-0000-000000000001',
    'c1000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'b1000000-0000-0000-0000-000000000001',
    'hard_savings',
    12000,
    9750,
    true,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    current_date - 80,
    'Volume discount negotiated on the laptop refresh order.'
  ),
  (
    'd3000000-0000-0000-0000-000000000002',
    'c1000000-0000-0000-0000-000000000009',
    'a1000000-0000-0000-0000-000000000005',
    'b1000000-0000-0000-0000-000000000003',
    'cost_avoidance',
    30000,
    25000,
    true,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    current_date - 40,
    'Locked Q4 freight rates ahead of peak-season surcharges.'
  ),
  (
    'd3000000-0000-0000-0000-000000000003',
    'c1000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000004',
    null,
    'rebate',
    7000,
    6000,
    false,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    current_date - 55,
    'Pending year-end volume rebate confirmation.'
  ),
  (
    'd3000000-0000-0000-0000-000000000004',
    'c1000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000002',
    'b1000000-0000-0000-0000-000000000002',
    'hard_savings',
    20000,
    18000,
    true,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    current_date - 35,
    'Multi-year commitment discount on the collaboration suite renewal.'
  ),
  (
    'd3000000-0000-0000-0000-000000000005',
    'c1000000-0000-0000-0000-000000000008',
    'a1000000-0000-0000-0000-000000000006',
    null,
    'cost_avoidance',
    5000,
    4400,
    true,
    'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2',
    current_date - 33,
    'Running a competitive RFQ avoided a planned price increase.'
  );

----------------------------------------------------------------
-- Two deliberate failures
--
-- Both guards have no role-based override, so they refuse this even
-- though the seed runs as the postgres superuser. If either NOTICE
-- below does not appear, the corresponding trigger has regressed.
----------------------------------------------------------------
do $$
begin
  begin
    insert into procurement.purchase_orders (supplier_id, department_id, category_id, buyer_id)
    values (
      'a1000000-0000-0000-0000-000000000008', -- QuestionableParts Ltd — blacklisted
      'd1000000-0000-0000-0000-000000000003',
      'c1000000-0000-0000-0000-000000000008',
      'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2'
    );
    raise exception 'GUARD FAILED: an order against a blacklisted supplier was allowed.';
  exception
    when others then
      raise notice 'Guard confirmed: % ', sqlerrm;
  end;
end;
$$;

do $$
declare
  v_po_id uuid;
begin
  begin
    insert into procurement.purchase_orders (supplier_id, contract_id, department_id, category_id, buyer_id)
    values (
      'a1000000-0000-0000-0000-000000000005',
      'b1000000-0000-0000-0000-000000000003', -- Reliable Logistics blanket — ceiling 40000, 25000 already committed
      'd1000000-0000-0000-0000-000000000003',
      'c1000000-0000-0000-0000-000000000009',
      'c9a1b03e-fb7a-424d-84ff-18e2791ce0a2'
    )
    returning id into v_po_id;

    insert into procurement.purchase_order_lines (po_id, description, quantity_ordered, unit_price)
    values (v_po_id, 'Additional freight lane — would exceed contract ceiling', 1, 20000);

    raise exception 'GUARD FAILED: an order past the contract ceiling was allowed.';
  exception
    when others then
      raise notice 'Guard confirmed: %', sqlerrm;
  end;
end;
$$;

refresh materialized view procurement.spend_analysis;
