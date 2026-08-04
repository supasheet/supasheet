-- Manufacturing Seeder
-- ================================================================
-- Demo data for the manufacturing (works orders and the shop floor)
-- module. Apply supabase/examples/20260806000000_manufacturing.sql
-- first:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260806000000_manufacturing.sql \
--     -f supabase/examples/m_seed.sql
--
-- WHY THIS FILE WALKS ITS RECORDS
--
-- Almost nothing in this schema can be written as final state. A
-- works order's yield, its actual hours and its efficiency are all
-- sums over the confirmations booked against it; the operation
-- statuses are what those confirmations set; the machine's
-- availability is runtime over runtime plus downtime. Typing any of
-- those in would produce a works order whose numbers do not follow
-- from anything.
--
-- So the orders here are raised, released — which is what freezes the
-- bill and the routing onto them — and then confirmed operation by
-- operation, in sequence, by operators certified on the work centre.
-- Every guard in the module is exercised on the way through rather
-- than worked around.
--
-- The bill of material is genuinely four levels deep, because a
-- two-level bill would not test the recursive cost roll-up, the cycle
-- check or the explosion at all.
--
-- Volume: 7 families, 51 products four levels deep, 28 bills over 82
-- lines, 28 routings over 74 steps, 8 work centres, 14 machines, 12
-- operators holding 29 certifications, 140 works orders carrying 562
-- frozen components and 333 operations, 314 shop-floor confirmations,
-- 130 downtime events, 81 maintenance jobs, 56 inspections over 220
-- measurements, and 62 non-conformances.
--
-- What that adds up to is meant to hold together, not just look
-- plausible. After this file runs:
--
--   - no bill contains itself at any depth
--   - every made part's standard cost equals its material plus labour
--     plus overhead, and no parent costs less than the components it
--     is built from
--   - nothing produced more than it started, and every order's actual
--     hours are the sum of the confirmations booked against it
--   - no operation was completed while an earlier one was still open,
--     and no confirmation was booked by somebody uncertified on that
--     work centre
--   - every scrapped unit carries a reason, every closed NCR carries
--     a root cause and a corrective action, and every machine with an
--     open downtime event reads as down
--
-- If a change to this file breaks one of those, the data is wrong
-- rather than merely different.
--
-- Dates are relative to `current_date`, so the schedule gantt, the
-- downtime timeline, the maintenance calendar and the twelve-month
-- output trend all have shape whenever this is run.
--
-- Four users are seeded (`on conflict do nothing`, so this is safe
-- alongside supabase/seed.sql and the other examples):
--   b73eb03e-fb7a-424d-84ff-18e2791ce0f1  production@supasheet.app (x-admin)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0f2  scheduler@supasheet.app  (production-planner)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0f3  shopfloor@supasheet.app  (operator)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0f4  qa@supasheet.app         (inspector)
--
-- Sign in as shopfloor@supasheet.app for the OPERATOR's seat: the
-- operations at the work centres they are certified on, and not one
-- column anywhere that says what any of it costs.
-- scheduler@supasheet.app owns the engineering data and the schedule
-- and cannot book a single unit. qa@supasheet.app is quality only.
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f1',
    'authenticated',
    'authenticated',
    'production@supasheet.app',
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
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0f1", "email": "production@supasheet.app", "name": "Harriet Vance", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f2',
    'authenticated',
    'authenticated',
    'scheduler@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "production-planner"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0f2", "email": "scheduler@supasheet.app", "name": "Omar Nazir", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f3',
    'authenticated',
    'authenticated',
    'shopfloor@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "operator"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0f3", "email": "shopfloor@supasheet.app", "name": "Lena Fischer", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f4',
    'authenticated',
    'authenticated',
    'qa@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "inspector"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0f4", "email": "qa@supasheet.app", "name": "Callum Reid", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f1',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f1',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0f1", "email": "production@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8af1'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f2',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f2',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0f2", "email": "scheduler@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8af2'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f3',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f3',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0f3", "email": "shopfloor@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8af3'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f4',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f4',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0f4", "email": "qa@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8af4'
  )
on conflict do nothing;

----------------------------------------------------------------
-- Settings and reference data
----------------------------------------------------------------
insert into
  manufacturing.manufacturing_settings (
    company_name,
    base_currency,
    default_overhead_rate_per_hour,
    working_hours_per_day,
    working_days_per_week,
    enforce_operation_sequence,
    enforce_certification,
    scrap_alert_threshold,
    ncr_escalation_days,
    timezone
  )
values
  (
    'Supasheet Engineering Ltd',
    'USD',
    42,
    16,
    5,
    true,
    true,
    4,
    14,
    'Europe/London'
  );

insert into
  manufacturing.product_families (id, code, name, description, color)
values
  (
    'b1000000-0000-0000-0000-000000000001',
    'FG',
    'Finished Goods',
    'Shipped to customers',
    '#10b981'
  ),
  (
    'b1000000-0000-0000-0000-000000000002',
    'SA',
    'Sub-assemblies',
    'Built to stock and consumed internally',
    '#6366f1'
  ),
  (
    'b1000000-0000-0000-0000-000000000003',
    'MC',
    'Machined Parts',
    'Made from bar, plate and castings',
    '#0ea5e9'
  ),
  (
    'b1000000-0000-0000-0000-000000000004',
    'FB',
    'Fabrications',
    'Welded and formed structures',
    '#f59e0b'
  ),
  (
    'b1000000-0000-0000-0000-000000000005',
    'RM',
    'Raw Material',
    'Bar, plate, castings and granulate',
    '#94a3b8'
  ),
  (
    'b1000000-0000-0000-0000-000000000006',
    'BO',
    'Bought-out Parts',
    'Purchased complete',
    '#a78bfa'
  ),
  (
    'b1000000-0000-0000-0000-000000000007',
    'CN',
    'Consumables and Packaging',
    'Used up or shipped with the goods',
    '#f472b6'
  );

----------------------------------------------------------------
-- Work centres
--
-- Two are flagged as bottlenecks, which is what a real shop looks
-- like: capacity is never evenly distributed.
----------------------------------------------------------------
insert into
  manufacturing.work_centers (
    id,
    code,
    name,
    work_center_type,
    capacity_hours_per_day,
    efficiency_percent,
    labour_rate_per_hour,
    overhead_rate_per_hour,
    queue_time_hours,
    is_bottleneck
  )
values
  (
    'b2000000-0000-0000-0000-000000000001',
    'WC-SAW',
    'Sawing',
    'fabrication',
    16,
    88,
    26.0,
    18.0,
    2,
    false
  ),
  (
    'b2000000-0000-0000-0000-000000000002',
    'WC-CNC',
    'CNC machining',
    'machining',
    20,
    82,
    38.0,
    32.0,
    8,
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000003',
    'WC-MILL',
    'Manual milling',
    'machining',
    16,
    78,
    32.0,
    24.0,
    4,
    false
  ),
  (
    'b2000000-0000-0000-0000-000000000004',
    'WC-WELD',
    'Welding',
    'fabrication',
    16,
    80,
    34.0,
    22.0,
    3,
    false
  ),
  (
    'b2000000-0000-0000-0000-000000000005',
    'WC-PAINT',
    'Paint and finishing',
    'finishing',
    8,
    75,
    28.0,
    20.0,
    12,
    false
  ),
  (
    'b2000000-0000-0000-0000-000000000006',
    'WC-ASM',
    'Assembly',
    'assembly',
    24,
    90,
    30.0,
    20.0,
    1,
    true
  ),
  (
    'b2000000-0000-0000-0000-000000000007',
    'WC-TEST',
    'Test and inspection',
    'inspection',
    16,
    85,
    36.0,
    16.0,
    2,
    false
  ),
  (
    'b2000000-0000-0000-0000-000000000008',
    'WC-PACK',
    'Packing',
    'packing',
    16,
    92,
    22.0,
    12.0,
    0,
    false
  );

----------------------------------------------------------------
-- Machines
----------------------------------------------------------------
insert into
  manufacturing.machines (
    id,
    work_center_id,
    code,
    name,
    manufacturer,
    model,
    serial_number,
    status,
    commissioned_on,
    service_interval_days,
    next_service_due
  )
values
  (
    'b3000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000002',
    'CNC-01',
    'Mazak QuickTurn 250',
    'Mazak',
    'QT250',
    'MZ-88213',
    'running',
    current_date - 840,
    90,
    current_date + -3
  ),
  (
    'b3000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000002',
    'CNC-02',
    'Mazak Integrex i200',
    'Mazak',
    'i200',
    'MZ-91044',
    'running',
    current_date - 900,
    90,
    current_date + 4
  ),
  (
    'b3000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000002',
    'CNC-03',
    'Haas VF-4',
    'Haas',
    'VF-4',
    'HS-33127',
    'running',
    current_date - 1020,
    90,
    current_date + 11
  ),
  (
    'b3000000-0000-0000-0000-000000000004',
    'b2000000-0000-0000-0000-000000000002',
    'CNC-04',
    'DMG Mori NLX 2500',
    'DMG Mori',
    'NLX2500',
    'DM-70551',
    'idle',
    current_date - 660,
    120,
    current_date + 18
  ),
  (
    'b3000000-0000-0000-0000-000000000005',
    'b2000000-0000-0000-0000-000000000001',
    'SAW-01',
    'Kasto bandsaw',
    'Kasto',
    'SBA260',
    'KS-11902',
    'running',
    current_date - 1320,
    180,
    current_date + 25
  ),
  (
    'b3000000-0000-0000-0000-000000000006',
    'b2000000-0000-0000-0000-000000000001',
    'SAW-02',
    'Behringer cold saw',
    'Behringer',
    'HBE320',
    'BH-40318',
    'idle',
    current_date - 1140,
    180,
    current_date + 32
  ),
  (
    'b3000000-0000-0000-0000-000000000007',
    'b2000000-0000-0000-0000-000000000003',
    'MILL-01',
    'Bridgeport mill',
    'Bridgeport',
    'Series I',
    'BP-20114',
    'running',
    current_date - 1560,
    120,
    current_date + 39
  ),
  (
    'b3000000-0000-0000-0000-000000000008',
    'b2000000-0000-0000-0000-000000000003',
    'MILL-02',
    'XYZ turret mill',
    'XYZ',
    'SMX2500',
    'XY-66201',
    'maintenance',
    current_date - 1440,
    120,
    current_date + 46
  ),
  (
    'b3000000-0000-0000-0000-000000000009',
    'b2000000-0000-0000-0000-000000000004',
    'WELD-01',
    'Fronius TIG bay',
    'Fronius',
    'MW3000',
    'FR-51120',
    'running',
    current_date - 780,
    90,
    current_date + 53
  ),
  (
    'b3000000-0000-0000-0000-000000000010',
    'b2000000-0000-0000-0000-000000000004',
    'WELD-02',
    'Kemppi MIG bay',
    'Kemppi',
    'X5',
    'KM-77803',
    'running',
    current_date - 720,
    90,
    current_date + 60
  ),
  (
    'b3000000-0000-0000-0000-000000000011',
    'b2000000-0000-0000-0000-000000000005',
    'PAINT-01',
    'Powder coat line',
    'Nordson',
    'Encore',
    'ND-13390',
    'idle',
    current_date - 900,
    180,
    current_date + 67
  ),
  (
    'b3000000-0000-0000-0000-000000000012',
    'b2000000-0000-0000-0000-000000000006',
    'ASM-01',
    'Assembly bench 1',
    'In-house',
    'Bench',
    'AS-00101',
    'running',
    current_date - 1800,
    365,
    current_date + 74
  ),
  (
    'b3000000-0000-0000-0000-000000000013',
    'b2000000-0000-0000-0000-000000000006',
    'ASM-02',
    'Assembly bench 2',
    'In-house',
    'Bench',
    'AS-00102',
    'running',
    current_date - 1800,
    365,
    current_date + 81
  ),
  (
    'b3000000-0000-0000-0000-000000000014',
    'b2000000-0000-0000-0000-000000000007',
    'TEST-01',
    'Hydrostatic test rig',
    'Hydratron',
    'HT500',
    'HY-90224',
    'running',
    current_date - 540,
    90,
    current_date + -2
  );

----------------------------------------------------------------
-- Products
--
-- Fifty-one parts arranged four levels deep — finished goods built
-- from sub-assemblies, built from machined parts, built from bar,
-- plate and castings. A two-level structure would exercise neither
-- the recursive cost roll-up nor the cycle check, which are the two
-- things this module is actually about.
--
-- Only bought parts carry a cost here. Everything made in-house has
-- its material, labour and overhead rolled up from the bill and the
-- routing at the bottom of this file.
----------------------------------------------------------------
insert into
  manufacturing.products (
    id,
    sku,
    name,
    family_id,
    product_type,
    status,
    uom,
    lot_size,
    yield_percent,
    material_cost,
    lead_time_days,
    drawing_number
  )
values
  (
    'b4000000-0000-0000-0000-000000000001',
    'FG-PUMP-100',
    'Centrifugal pump 100mm',
    'b1000000-0000-0000-0000-000000000001',
    'make',
    'active',
    'EA',
    10,
    96,
    0,
    4,
    'DRG-1001'
  ),
  (
    'b4000000-0000-0000-0000-000000000002',
    'FG-PUMP-150',
    'Centrifugal pump 150mm',
    'b1000000-0000-0000-0000-000000000001',
    'make',
    'active',
    'EA',
    6,
    95,
    0,
    5,
    'DRG-1002'
  ),
  (
    'b4000000-0000-0000-0000-000000000003',
    'FG-VALVE-50',
    'Gate valve 50mm',
    'b1000000-0000-0000-0000-000000000001',
    'make',
    'active',
    'EA',
    25,
    97,
    0,
    6,
    'DRG-1003'
  ),
  (
    'b4000000-0000-0000-0000-000000000004',
    'FG-VALVE-80',
    'Gate valve 80mm',
    'b1000000-0000-0000-0000-000000000001',
    'make',
    'active',
    'EA',
    20,
    97,
    0,
    7,
    'DRG-1004'
  ),
  (
    'b4000000-0000-0000-0000-000000000005',
    'FG-GEARBOX',
    'Gearbox unit GX-2',
    'b1000000-0000-0000-0000-000000000001',
    'make',
    'active',
    'EA',
    8,
    94,
    0,
    8,
    'DRG-1005'
  ),
  (
    'b4000000-0000-0000-0000-000000000006',
    'FG-ACTUATOR',
    'Electric actuator EA-1',
    'b1000000-0000-0000-0000-000000000001',
    'make',
    'active',
    'EA',
    15,
    96,
    0,
    9,
    'DRG-1006'
  ),
  (
    'b4000000-0000-0000-0000-000000000007',
    'SA-IMPELLER-100',
    'Impeller assembly 100',
    'b1000000-0000-0000-0000-000000000002',
    'make',
    'active',
    'EA',
    20,
    97,
    0,
    10,
    'DRG-1007'
  ),
  (
    'b4000000-0000-0000-0000-000000000008',
    'SA-IMPELLER-150',
    'Impeller assembly 150',
    'b1000000-0000-0000-0000-000000000002',
    'make',
    'active',
    'EA',
    12,
    97,
    0,
    11,
    'DRG-1008'
  ),
  (
    'b4000000-0000-0000-0000-000000000009',
    'SA-SHAFT-ASSY',
    'Shaft assembly',
    'b1000000-0000-0000-0000-000000000002',
    'make',
    'active',
    'EA',
    25,
    98,
    0,
    12,
    'DRG-1009'
  ),
  (
    'b4000000-0000-0000-0000-000000000010',
    'SA-BEARING-HSG',
    'Bearing housing assembly',
    'b1000000-0000-0000-0000-000000000002',
    'make',
    'active',
    'EA',
    20,
    97,
    0,
    13,
    'DRG-1010'
  ),
  (
    'b4000000-0000-0000-0000-000000000011',
    'SA-SEAL-KIT',
    'Seal kit',
    'b1000000-0000-0000-0000-000000000002',
    'make',
    'active',
    'EA',
    50,
    99,
    0,
    14,
    'DRG-1011'
  ),
  (
    'b4000000-0000-0000-0000-000000000012',
    'SA-VALVE-BODY-50',
    'Valve body assembly 50',
    'b1000000-0000-0000-0000-000000000002',
    'make',
    'active',
    'EA',
    30,
    96,
    0,
    3,
    'DRG-1012'
  ),
  (
    'b4000000-0000-0000-0000-000000000013',
    'SA-VALVE-BODY-80',
    'Valve body assembly 80',
    'b1000000-0000-0000-0000-000000000002',
    'make',
    'active',
    'EA',
    24,
    96,
    0,
    4,
    'DRG-1013'
  ),
  (
    'b4000000-0000-0000-0000-000000000014',
    'SA-STEM-ASSY',
    'Stem assembly',
    'b1000000-0000-0000-0000-000000000002',
    'make',
    'active',
    'EA',
    40,
    98,
    0,
    5,
    'DRG-1014'
  ),
  (
    'b4000000-0000-0000-0000-000000000015',
    'SA-GEAR-SET',
    'Gear set',
    'b1000000-0000-0000-0000-000000000002',
    'make',
    'active',
    'EA',
    16,
    95,
    0,
    6,
    'DRG-1015'
  ),
  (
    'b4000000-0000-0000-0000-000000000016',
    'SA-CONTROL-BOARD',
    'Control board assembly',
    'b1000000-0000-0000-0000-000000000002',
    'make',
    'active',
    'EA',
    20,
    97,
    0,
    7,
    'DRG-1016'
  ),
  (
    'b4000000-0000-0000-0000-000000000017',
    'MC-SHAFT',
    'Machined shaft',
    'b1000000-0000-0000-0000-000000000003',
    'make',
    'active',
    'EA',
    30,
    94,
    0,
    8,
    'DRG-1017'
  ),
  (
    'b4000000-0000-0000-0000-000000000018',
    'MC-IMPELLER-100',
    'Machined impeller 100',
    'b1000000-0000-0000-0000-000000000003',
    'make',
    'active',
    'EA',
    20,
    93,
    0,
    9,
    'DRG-1018'
  ),
  (
    'b4000000-0000-0000-0000-000000000019',
    'MC-IMPELLER-150',
    'Machined impeller 150',
    'b1000000-0000-0000-0000-000000000003',
    'make',
    'active',
    'EA',
    12,
    93,
    0,
    10,
    'DRG-1019'
  ),
  (
    'b4000000-0000-0000-0000-000000000020',
    'MC-HSG-BORE',
    'Bored housing',
    'b1000000-0000-0000-0000-000000000003',
    'make',
    'active',
    'EA',
    20,
    95,
    0,
    11,
    'DRG-1020'
  ),
  (
    'b4000000-0000-0000-0000-000000000021',
    'MC-FLANGE-50',
    'Machined flange 50',
    'b1000000-0000-0000-0000-000000000003',
    'make',
    'active',
    'EA',
    60,
    96,
    0,
    12,
    'DRG-1021'
  ),
  (
    'b4000000-0000-0000-0000-000000000022',
    'MC-FLANGE-80',
    'Machined flange 80',
    'b1000000-0000-0000-0000-000000000003',
    'make',
    'active',
    'EA',
    48,
    96,
    0,
    13,
    'DRG-1022'
  ),
  (
    'b4000000-0000-0000-0000-000000000023',
    'MC-STEM',
    'Machined stem',
    'b1000000-0000-0000-0000-000000000003',
    'make',
    'active',
    'EA',
    50,
    95,
    0,
    14,
    'DRG-1023'
  ),
  (
    'b4000000-0000-0000-0000-000000000024',
    'MC-GEAR-A',
    'Machined gear A',
    'b1000000-0000-0000-0000-000000000003',
    'make',
    'active',
    'EA',
    24,
    92,
    0,
    3,
    'DRG-1024'
  ),
  (
    'b4000000-0000-0000-0000-000000000025',
    'MC-GEAR-B',
    'Machined gear B',
    'b1000000-0000-0000-0000-000000000003',
    'make',
    'active',
    'EA',
    24,
    92,
    0,
    4,
    'DRG-1025'
  ),
  (
    'b4000000-0000-0000-0000-000000000026',
    'MC-END-CAP',
    'Machined end cap',
    'b1000000-0000-0000-0000-000000000003',
    'make',
    'active',
    'EA',
    80,
    97,
    0,
    5,
    'DRG-1026'
  ),
  (
    'b4000000-0000-0000-0000-000000000027',
    'FB-BASEPLATE',
    'Welded baseplate',
    'b1000000-0000-0000-0000-000000000004',
    'make',
    'active',
    'EA',
    12,
    95,
    0,
    6,
    'DRG-1027'
  ),
  (
    'b4000000-0000-0000-0000-000000000028',
    'FB-GUARD',
    'Welded guard',
    'b1000000-0000-0000-0000-000000000004',
    'make',
    'active',
    'EA',
    30,
    96,
    0,
    7,
    'DRG-1028'
  ),
  (
    'b4000000-0000-0000-0000-000000000029',
    'RM-BAR-316-40',
    'Stainless bar 316, 40mm',
    'b1000000-0000-0000-0000-000000000005',
    'buy',
    'active',
    'M',
    1,
    100,
    18.4,
    8,
    'DRG-1029'
  ),
  (
    'b4000000-0000-0000-0000-000000000030',
    'RM-BAR-316-25',
    'Stainless bar 316, 25mm',
    'b1000000-0000-0000-0000-000000000005',
    'buy',
    'active',
    'M',
    1,
    100,
    9.75,
    9,
    'DRG-1030'
  ),
  (
    'b4000000-0000-0000-0000-000000000031',
    'RM-PLATE-304-10',
    'Plate 304, 10mm',
    'b1000000-0000-0000-0000-000000000005',
    'buy',
    'active',
    'M',
    1,
    100,
    26.5,
    10,
    'DRG-1031'
  ),
  (
    'b4000000-0000-0000-0000-000000000032',
    'RM-CASTING-P100',
    'Pump casing casting 100',
    'b1000000-0000-0000-0000-000000000005',
    'buy',
    'active',
    'EA',
    1,
    100,
    42.0,
    11,
    'DRG-1032'
  ),
  (
    'b4000000-0000-0000-0000-000000000033',
    'RM-CASTING-P150',
    'Pump casing casting 150',
    'b1000000-0000-0000-0000-000000000005',
    'buy',
    'active',
    'EA',
    1,
    100,
    63.5,
    12,
    'DRG-1033'
  ),
  (
    'b4000000-0000-0000-0000-000000000034',
    'RM-CASTING-V50',
    'Valve body casting 50',
    'b1000000-0000-0000-0000-000000000005',
    'buy',
    'active',
    'EA',
    1,
    100,
    31.2,
    13,
    'DRG-1034'
  ),
  (
    'b4000000-0000-0000-0000-000000000035',
    'RM-CASTING-V80',
    'Valve body casting 80',
    'b1000000-0000-0000-0000-000000000005',
    'buy',
    'active',
    'EA',
    1,
    100,
    48.9,
    14,
    'DRG-1035'
  ),
  (
    'b4000000-0000-0000-0000-000000000036',
    'RM-BRONZE-BAR',
    'Bronze bar 50mm',
    'b1000000-0000-0000-0000-000000000005',
    'buy',
    'active',
    'M',
    1,
    100,
    34.8,
    3,
    'DRG-1036'
  ),
  (
    'b4000000-0000-0000-0000-000000000037',
    'BO-BEARING-6204',
    'Bearing 6204-2RS',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    4.2,
    4,
    'DRG-1037'
  ),
  (
    'b4000000-0000-0000-0000-000000000038',
    'BO-BEARING-6206',
    'Bearing 6206-2RS',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    7.85,
    5,
    'DRG-1038'
  ),
  (
    'b4000000-0000-0000-0000-000000000039',
    'BO-SEAL-25',
    'Shaft seal 25mm',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    3.4,
    6,
    'DRG-1039'
  ),
  (
    'b4000000-0000-0000-0000-000000000040',
    'BO-SEAL-40',
    'Shaft seal 40mm',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    5.1,
    7,
    'DRG-1040'
  ),
  (
    'b4000000-0000-0000-0000-000000000041',
    'BO-ORING-KIT',
    'O-ring kit',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    2.85,
    8,
    'DRG-1041'
  ),
  (
    'b4000000-0000-0000-0000-000000000042',
    'BO-MOTOR-1K5',
    'Motor 1.5kW IE3',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    178.0,
    9,
    'DRG-1042'
  ),
  (
    'b4000000-0000-0000-0000-000000000043',
    'BO-MOTOR-3K0',
    'Motor 3.0kW IE3',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    264.0,
    10,
    'DRG-1043'
  ),
  (
    'b4000000-0000-0000-0000-000000000044',
    'BO-PCB-CTRL',
    'Control PCB',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    96.5,
    11,
    'DRG-1044'
  ),
  (
    'b4000000-0000-0000-0000-000000000045',
    'BO-FASTENER-KIT',
    'Fastener kit',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    6.3,
    12,
    'DRG-1045'
  ),
  (
    'b4000000-0000-0000-0000-000000000046',
    'BO-GASKET-SET',
    'Gasket set',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    4.75,
    13,
    'DRG-1046'
  ),
  (
    'b4000000-0000-0000-0000-000000000047',
    'BO-COUPLING',
    'Flexible coupling',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    28.9,
    14,
    'DRG-1047'
  ),
  (
    'b4000000-0000-0000-0000-000000000048',
    'BO-HANDWHEEL',
    'Handwheel 200mm',
    'b1000000-0000-0000-0000-000000000006',
    'buy',
    'active',
    'EA',
    1,
    100,
    12.4,
    3,
    'DRG-1048'
  ),
  (
    'b4000000-0000-0000-0000-000000000049',
    'PK-CARTON-M',
    'Carton, medium',
    'b1000000-0000-0000-0000-000000000007',
    'buy',
    'active',
    'EA',
    1,
    100,
    1.85,
    4,
    'DRG-1049'
  ),
  (
    'b4000000-0000-0000-0000-000000000050',
    'PK-CRATE-L',
    'Crate, large',
    'b1000000-0000-0000-0000-000000000007',
    'buy',
    'active',
    'EA',
    1,
    100,
    14.6,
    5,
    'DRG-1050'
  ),
  (
    'b4000000-0000-0000-0000-000000000051',
    'CN-PAINT-EPOXY',
    'Epoxy paint, litre',
    'b1000000-0000-0000-0000-000000000007',
    'buy',
    'active',
    'L',
    1,
    100,
    9.2,
    6,
    'DRG-1051'
  );

----------------------------------------------------------------
-- Bills of material
--
-- One active bill per make part. The cycle check runs on every line
-- as it goes in, so this structure is proof the graph is acyclic
-- rather than an assertion that it is.
----------------------------------------------------------------
insert into
  manufacturing.boms (
    id,
    product_id,
    version,
    status,
    name,
    output_quantity,
    effective_from
  )
values
  (
    'b5000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000001',
    'A',
    'active',
    'FG-PUMP-100 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000002',
    'A',
    'active',
    'FG-PUMP-150 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000003',
    'b4000000-0000-0000-0000-000000000003',
    'A',
    'active',
    'FG-VALVE-50 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000004',
    'b4000000-0000-0000-0000-000000000004',
    'A',
    'active',
    'FG-VALVE-80 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000005',
    'b4000000-0000-0000-0000-000000000005',
    'A',
    'active',
    'FG-GEARBOX bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000006',
    'b4000000-0000-0000-0000-000000000006',
    'A',
    'active',
    'FG-ACTUATOR bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000007',
    'b4000000-0000-0000-0000-000000000007',
    'A',
    'active',
    'SA-IMPELLER-100 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000008',
    'b4000000-0000-0000-0000-000000000008',
    'A',
    'active',
    'SA-IMPELLER-150 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000009',
    'b4000000-0000-0000-0000-000000000009',
    'A',
    'active',
    'SA-SHAFT-ASSY bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000010',
    'b4000000-0000-0000-0000-000000000010',
    'A',
    'active',
    'SA-BEARING-HSG bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000011',
    'b4000000-0000-0000-0000-000000000011',
    'A',
    'active',
    'SA-SEAL-KIT bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000012',
    'b4000000-0000-0000-0000-000000000012',
    'A',
    'active',
    'SA-VALVE-BODY-50 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000013',
    'b4000000-0000-0000-0000-000000000013',
    'A',
    'active',
    'SA-VALVE-BODY-80 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000014',
    'b4000000-0000-0000-0000-000000000014',
    'A',
    'active',
    'SA-STEM-ASSY bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000015',
    'b4000000-0000-0000-0000-000000000015',
    'A',
    'active',
    'SA-GEAR-SET bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000016',
    'b4000000-0000-0000-0000-000000000016',
    'A',
    'active',
    'SA-CONTROL-BOARD bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000017',
    'b4000000-0000-0000-0000-000000000017',
    'A',
    'active',
    'MC-SHAFT bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000018',
    'b4000000-0000-0000-0000-000000000018',
    'A',
    'active',
    'MC-IMPELLER-100 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000019',
    'b4000000-0000-0000-0000-000000000019',
    'A',
    'active',
    'MC-IMPELLER-150 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000020',
    'b4000000-0000-0000-0000-000000000020',
    'A',
    'active',
    'MC-HSG-BORE bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000021',
    'b4000000-0000-0000-0000-000000000021',
    'A',
    'active',
    'MC-FLANGE-50 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000022',
    'b4000000-0000-0000-0000-000000000022',
    'A',
    'active',
    'MC-FLANGE-80 bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000023',
    'b4000000-0000-0000-0000-000000000023',
    'A',
    'active',
    'MC-STEM bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000024',
    'b4000000-0000-0000-0000-000000000024',
    'A',
    'active',
    'MC-GEAR-A bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000025',
    'b4000000-0000-0000-0000-000000000025',
    'A',
    'active',
    'MC-GEAR-B bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000026',
    'b4000000-0000-0000-0000-000000000026',
    'A',
    'active',
    'MC-END-CAP bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000027',
    'b4000000-0000-0000-0000-000000000027',
    'A',
    'active',
    'FB-BASEPLATE bill',
    1,
    current_date - 400
  ),
  (
    'b5000000-0000-0000-0000-000000000028',
    'b4000000-0000-0000-0000-000000000028',
    'A',
    'active',
    'FB-GUARD bill',
    1,
    current_date - 400
  );

insert into
  manufacturing.bom_lines (
    bom_id,
    component_product_id,
    line_number,
    quantity_per,
    scrap_percent,
    operation_sequence,
    issue_method
  )
values
  (
    'b5000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000007',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000009',
    20,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000010',
    30,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000011',
    40,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000042',
    50,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000027',
    60,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000047',
    70,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000045',
    80,
    1,
    2,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000049',
    90,
    1,
    0,
    30,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000008',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000009',
    20,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000010',
    30,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000011',
    40,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000043',
    50,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000027',
    60,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000047',
    70,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000045',
    80,
    1,
    2,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000050',
    90,
    1,
    0,
    30,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000003',
    'b4000000-0000-0000-0000-000000000012',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000003',
    'b4000000-0000-0000-0000-000000000014',
    20,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000003',
    'b4000000-0000-0000-0000-000000000048',
    30,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000003',
    'b4000000-0000-0000-0000-000000000046',
    40,
    1,
    1,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000003',
    'b4000000-0000-0000-0000-000000000045',
    50,
    1,
    2,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000003',
    'b4000000-0000-0000-0000-000000000049',
    60,
    1,
    0,
    30,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000004',
    'b4000000-0000-0000-0000-000000000013',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000004',
    'b4000000-0000-0000-0000-000000000014',
    20,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000004',
    'b4000000-0000-0000-0000-000000000048',
    30,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000004',
    'b4000000-0000-0000-0000-000000000046',
    40,
    1,
    1,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000004',
    'b4000000-0000-0000-0000-000000000045',
    50,
    1,
    2,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000004',
    'b4000000-0000-0000-0000-000000000049',
    60,
    1,
    0,
    30,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000005',
    'b4000000-0000-0000-0000-000000000015',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000005',
    'b4000000-0000-0000-0000-000000000020',
    20,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000005',
    'b4000000-0000-0000-0000-000000000026',
    30,
    2,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000005',
    'b4000000-0000-0000-0000-000000000037',
    40,
    4,
    1,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000005',
    'b4000000-0000-0000-0000-000000000039',
    50,
    2,
    1,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000005',
    'b4000000-0000-0000-0000-000000000045',
    60,
    1,
    2,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000005',
    'b4000000-0000-0000-0000-000000000049',
    70,
    1,
    0,
    30,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000006',
    'b4000000-0000-0000-0000-000000000016',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000006',
    'b4000000-0000-0000-0000-000000000042',
    20,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000006',
    'b4000000-0000-0000-0000-000000000026',
    30,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000006',
    'b4000000-0000-0000-0000-000000000028',
    40,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000006',
    'b4000000-0000-0000-0000-000000000045',
    50,
    1,
    2,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000006',
    'b4000000-0000-0000-0000-000000000049',
    60,
    1,
    0,
    30,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000007',
    'b4000000-0000-0000-0000-000000000018',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000007',
    'b4000000-0000-0000-0000-000000000045',
    20,
    1,
    2,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000008',
    'b4000000-0000-0000-0000-000000000019',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000008',
    'b4000000-0000-0000-0000-000000000045',
    20,
    1,
    2,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000009',
    'b4000000-0000-0000-0000-000000000017',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000009',
    'b4000000-0000-0000-0000-000000000037',
    20,
    2,
    1,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000009',
    'b4000000-0000-0000-0000-000000000039',
    30,
    1,
    1,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000010',
    'b4000000-0000-0000-0000-000000000020',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000010',
    'b4000000-0000-0000-0000-000000000038',
    20,
    2,
    1,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000010',
    'b4000000-0000-0000-0000-000000000040',
    30,
    1,
    1,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000011',
    'b4000000-0000-0000-0000-000000000041',
    10,
    1,
    0,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000011',
    'b4000000-0000-0000-0000-000000000039',
    20,
    2,
    1,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000012',
    'b4000000-0000-0000-0000-000000000034',
    10,
    1,
    2,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000012',
    'b4000000-0000-0000-0000-000000000021',
    20,
    2,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000012',
    'b4000000-0000-0000-0000-000000000051',
    30,
    0.3,
    5,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000013',
    'b4000000-0000-0000-0000-000000000035',
    10,
    1,
    2,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000013',
    'b4000000-0000-0000-0000-000000000022',
    20,
    2,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000013',
    'b4000000-0000-0000-0000-000000000051',
    30,
    0.5,
    5,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000014',
    'b4000000-0000-0000-0000-000000000023',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000014',
    'b4000000-0000-0000-0000-000000000041',
    20,
    1,
    1,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000015',
    'b4000000-0000-0000-0000-000000000024',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000015',
    'b4000000-0000-0000-0000-000000000025',
    20,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000015',
    'b4000000-0000-0000-0000-000000000037',
    30,
    2,
    1,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000016',
    'b4000000-0000-0000-0000-000000000044',
    10,
    1,
    0,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000016',
    'b4000000-0000-0000-0000-000000000045',
    20,
    1,
    2,
    10,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000017',
    'b4000000-0000-0000-0000-000000000029',
    10,
    1.2,
    5,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000018',
    'b4000000-0000-0000-0000-000000000032',
    10,
    1,
    3,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000019',
    'b4000000-0000-0000-0000-000000000033',
    10,
    1,
    3,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000020',
    'b4000000-0000-0000-0000-000000000032',
    10,
    1,
    2,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000021',
    'b4000000-0000-0000-0000-000000000031',
    10,
    0.8,
    8,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000022',
    'b4000000-0000-0000-0000-000000000031',
    10,
    1.2,
    8,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000023',
    'b4000000-0000-0000-0000-000000000030',
    10,
    0.6,
    6,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000024',
    'b4000000-0000-0000-0000-000000000029',
    10,
    0.9,
    10,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000025',
    'b4000000-0000-0000-0000-000000000036',
    10,
    0.7,
    10,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000026',
    'b4000000-0000-0000-0000-000000000030',
    10,
    0.3,
    5,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000027',
    'b4000000-0000-0000-0000-000000000031',
    10,
    2.5,
    6,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000027',
    'b4000000-0000-0000-0000-000000000051',
    20,
    0.4,
    5,
    30,
    'backflush'
  ),
  (
    'b5000000-0000-0000-0000-000000000028',
    'b4000000-0000-0000-0000-000000000031',
    10,
    0.8,
    6,
    10,
    'manual'
  ),
  (
    'b5000000-0000-0000-0000-000000000028',
    'b4000000-0000-0000-0000-000000000051',
    20,
    0.2,
    5,
    30,
    'backflush'
  );

----------------------------------------------------------------
-- Routings
--
-- Finished goods assemble, test and pack; sub-assemblies assemble and
-- check; machined parts saw, machine and deburr; fabrications cut,
-- weld and paint. Every routing ends on an inspection point, which is
-- what the quality module hangs off.
----------------------------------------------------------------
insert into
  manufacturing.routings (
    id,
    product_id,
    version,
    status,
    name,
    effective_from
  )
values
  (
    'b6000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000001',
    'A',
    'active',
    'FG-PUMP-100 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000002',
    'A',
    'active',
    'FG-PUMP-150 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000003',
    'b4000000-0000-0000-0000-000000000003',
    'A',
    'active',
    'FG-VALVE-50 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000004',
    'b4000000-0000-0000-0000-000000000004',
    'A',
    'active',
    'FG-VALVE-80 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000005',
    'b4000000-0000-0000-0000-000000000005',
    'A',
    'active',
    'FG-GEARBOX routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000006',
    'b4000000-0000-0000-0000-000000000006',
    'A',
    'active',
    'FG-ACTUATOR routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000007',
    'b4000000-0000-0000-0000-000000000007',
    'A',
    'active',
    'SA-IMPELLER-100 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000008',
    'b4000000-0000-0000-0000-000000000008',
    'A',
    'active',
    'SA-IMPELLER-150 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000009',
    'b4000000-0000-0000-0000-000000000009',
    'A',
    'active',
    'SA-SHAFT-ASSY routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000010',
    'b4000000-0000-0000-0000-000000000010',
    'A',
    'active',
    'SA-BEARING-HSG routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000011',
    'b4000000-0000-0000-0000-000000000011',
    'A',
    'active',
    'SA-SEAL-KIT routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000012',
    'b4000000-0000-0000-0000-000000000012',
    'A',
    'active',
    'SA-VALVE-BODY-50 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000013',
    'b4000000-0000-0000-0000-000000000013',
    'A',
    'active',
    'SA-VALVE-BODY-80 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000014',
    'b4000000-0000-0000-0000-000000000014',
    'A',
    'active',
    'SA-STEM-ASSY routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000015',
    'b4000000-0000-0000-0000-000000000015',
    'A',
    'active',
    'SA-GEAR-SET routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000016',
    'b4000000-0000-0000-0000-000000000016',
    'A',
    'active',
    'SA-CONTROL-BOARD routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000017',
    'b4000000-0000-0000-0000-000000000017',
    'A',
    'active',
    'MC-SHAFT routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000018',
    'b4000000-0000-0000-0000-000000000018',
    'A',
    'active',
    'MC-IMPELLER-100 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000019',
    'b4000000-0000-0000-0000-000000000019',
    'A',
    'active',
    'MC-IMPELLER-150 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000020',
    'b4000000-0000-0000-0000-000000000020',
    'A',
    'active',
    'MC-HSG-BORE routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000021',
    'b4000000-0000-0000-0000-000000000021',
    'A',
    'active',
    'MC-FLANGE-50 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000022',
    'b4000000-0000-0000-0000-000000000022',
    'A',
    'active',
    'MC-FLANGE-80 routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000023',
    'b4000000-0000-0000-0000-000000000023',
    'A',
    'active',
    'MC-STEM routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000024',
    'b4000000-0000-0000-0000-000000000024',
    'A',
    'active',
    'MC-GEAR-A routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000025',
    'b4000000-0000-0000-0000-000000000025',
    'A',
    'active',
    'MC-GEAR-B routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000026',
    'b4000000-0000-0000-0000-000000000026',
    'A',
    'active',
    'MC-END-CAP routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000027',
    'b4000000-0000-0000-0000-000000000027',
    'A',
    'active',
    'FB-BASEPLATE routing',
    current_date - 400
  ),
  (
    'b6000000-0000-0000-0000-000000000028',
    'b4000000-0000-0000-0000-000000000028',
    'A',
    'active',
    'FB-GUARD routing',
    current_date - 400
  );

insert into
  manufacturing.routing_operations (
    routing_id,
    work_center_id,
    sequence_number,
    name,
    setup_minutes,
    run_minutes_per_unit,
    move_minutes,
    is_inspection_point
  )
values
  (
    'b6000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    45,
    18,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Test and inspect',
    15,
    9,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000008',
    30,
    'Pack',
    5,
    4,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    45,
    18,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Test and inspect',
    15,
    9,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000008',
    30,
    'Pack',
    5,
    4,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    45,
    18,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Test and inspect',
    15,
    9,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000008',
    30,
    'Pack',
    5,
    4,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000004',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    45,
    18,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000004',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Test and inspect',
    15,
    9,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000004',
    'b2000000-0000-0000-0000-000000000008',
    30,
    'Pack',
    5,
    4,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000005',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    45,
    18,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000005',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Test and inspect',
    15,
    9,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000005',
    'b2000000-0000-0000-0000-000000000008',
    30,
    'Pack',
    5,
    4,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000006',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    45,
    18,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000006',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Test and inspect',
    15,
    9,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000006',
    'b2000000-0000-0000-0000-000000000008',
    30,
    'Pack',
    5,
    4,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000007',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    25,
    7,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000007',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Check',
    5,
    2,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000008',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    25,
    7,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000008',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Check',
    5,
    2,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000009',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    25,
    7,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000009',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Check',
    5,
    2,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000010',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    25,
    7,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000010',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Check',
    5,
    2,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000011',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    25,
    7,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000011',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Check',
    5,
    2,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000012',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    25,
    7,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000012',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Check',
    5,
    2,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000013',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    25,
    7,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000013',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Check',
    5,
    2,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000014',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    25,
    7,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000014',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Check',
    5,
    2,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000015',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    25,
    7,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000015',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Check',
    5,
    2,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000016',
    'b2000000-0000-0000-0000-000000000006',
    10,
    'Assemble',
    25,
    7,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000016',
    'b2000000-0000-0000-0000-000000000007',
    20,
    'Check',
    5,
    2,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000017',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut to length',
    15,
    2,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000017',
    'b2000000-0000-0000-0000-000000000002',
    20,
    'Machine',
    60,
    11,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000017',
    'b2000000-0000-0000-0000-000000000003',
    30,
    'Deburr and check',
    10,
    3,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000018',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut to length',
    15,
    2,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000018',
    'b2000000-0000-0000-0000-000000000002',
    20,
    'Machine',
    60,
    11,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000018',
    'b2000000-0000-0000-0000-000000000003',
    30,
    'Deburr and check',
    10,
    3,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000019',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut to length',
    15,
    2,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000019',
    'b2000000-0000-0000-0000-000000000002',
    20,
    'Machine',
    60,
    11,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000019',
    'b2000000-0000-0000-0000-000000000003',
    30,
    'Deburr and check',
    10,
    3,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000020',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut to length',
    15,
    2,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000020',
    'b2000000-0000-0000-0000-000000000002',
    20,
    'Machine',
    60,
    11,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000020',
    'b2000000-0000-0000-0000-000000000003',
    30,
    'Deburr and check',
    10,
    3,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000021',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut to length',
    15,
    2,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000021',
    'b2000000-0000-0000-0000-000000000002',
    20,
    'Machine',
    60,
    11,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000021',
    'b2000000-0000-0000-0000-000000000003',
    30,
    'Deburr and check',
    10,
    3,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000022',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut to length',
    15,
    2,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000022',
    'b2000000-0000-0000-0000-000000000002',
    20,
    'Machine',
    60,
    11,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000022',
    'b2000000-0000-0000-0000-000000000003',
    30,
    'Deburr and check',
    10,
    3,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000023',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut to length',
    15,
    2,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000023',
    'b2000000-0000-0000-0000-000000000002',
    20,
    'Machine',
    60,
    11,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000023',
    'b2000000-0000-0000-0000-000000000003',
    30,
    'Deburr and check',
    10,
    3,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000024',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut to length',
    15,
    2,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000024',
    'b2000000-0000-0000-0000-000000000002',
    20,
    'Machine',
    60,
    11,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000024',
    'b2000000-0000-0000-0000-000000000003',
    30,
    'Deburr and check',
    10,
    3,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000025',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut to length',
    15,
    2,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000025',
    'b2000000-0000-0000-0000-000000000002',
    20,
    'Machine',
    60,
    11,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000025',
    'b2000000-0000-0000-0000-000000000003',
    30,
    'Deburr and check',
    10,
    3,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000026',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut to length',
    15,
    2,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000026',
    'b2000000-0000-0000-0000-000000000002',
    20,
    'Machine',
    60,
    11,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000026',
    'b2000000-0000-0000-0000-000000000003',
    30,
    'Deburr and check',
    10,
    3,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000027',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut and form',
    20,
    5,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000027',
    'b2000000-0000-0000-0000-000000000004',
    20,
    'Weld',
    35,
    14,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000027',
    'b2000000-0000-0000-0000-000000000005',
    30,
    'Paint',
    30,
    6,
    5,
    true
  ),
  (
    'b6000000-0000-0000-0000-000000000028',
    'b2000000-0000-0000-0000-000000000001',
    10,
    'Cut and form',
    20,
    5,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000028',
    'b2000000-0000-0000-0000-000000000004',
    20,
    'Weld',
    35,
    14,
    5,
    false
  ),
  (
    'b6000000-0000-0000-0000-000000000028',
    'b2000000-0000-0000-0000-000000000005',
    30,
    'Paint',
    30,
    6,
    5,
    true
  );

----------------------------------------------------------------
-- Operators and certifications
--
-- Certifications are what the confirmation guard checks, so who is
-- signed off on what decides who can book work where. Nobody is
-- certified on everything.
----------------------------------------------------------------
insert into
  manufacturing.operators (
    id,
    badge_number,
    name,
    user_id,
    shift,
    hired_on,
    email
  )
values
  (
    'b7000000-0000-0000-0000-000000000001',
    'OP-1001',
    'Lena Fischer',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0f3',
    'day',
    current_date - 247,
    'lena.fischer@supasheet.app'
  ),
  (
    'b7000000-0000-0000-0000-000000000002',
    'OP-1002',
    'Marcus Bell',
    null,
    'day',
    current_date - 294,
    'marcus.bell@supasheet.app'
  ),
  (
    'b7000000-0000-0000-0000-000000000003',
    'OP-1003',
    'Aisha Kone',
    null,
    'day',
    current_date - 341,
    'aisha.kone@supasheet.app'
  ),
  (
    'b7000000-0000-0000-0000-000000000004',
    'OP-1004',
    'Tomas Nowak',
    null,
    'day',
    current_date - 388,
    'tomas.nowak@supasheet.app'
  ),
  (
    'b7000000-0000-0000-0000-000000000005',
    'OP-1005',
    'Grace Ofori',
    null,
    'late',
    current_date - 435,
    'grace.ofori@supasheet.app'
  ),
  (
    'b7000000-0000-0000-0000-000000000006',
    'OP-1006',
    'Dev Patel',
    null,
    'late',
    current_date - 482,
    'dev.patel@supasheet.app'
  ),
  (
    'b7000000-0000-0000-0000-000000000007',
    'OP-1007',
    'Ruth Cassidy',
    null,
    'late',
    current_date - 529,
    'ruth.cassidy@supasheet.app'
  ),
  (
    'b7000000-0000-0000-0000-000000000008',
    'OP-1008',
    'Jon Halvorsen',
    null,
    'night',
    current_date - 576,
    'jon.halvorsen@supasheet.app'
  ),
  (
    'b7000000-0000-0000-0000-000000000009',
    'OP-1009',
    'Ana Ruiz',
    null,
    'night',
    current_date - 623,
    'ana.ruiz@supasheet.app'
  ),
  (
    'b7000000-0000-0000-0000-000000000010',
    'OP-1010',
    'Piotr Zielinski',
    null,
    'day',
    current_date - 670,
    'piotr.zielinski@supasheet.app'
  ),
  (
    'b7000000-0000-0000-0000-000000000011',
    'OP-1011',
    'Chi Nguyen',
    null,
    'day',
    current_date - 717,
    'chi.nguyen@supasheet.app'
  ),
  (
    'b7000000-0000-0000-0000-000000000012',
    'OP-1012',
    'Sam Okafor',
    null,
    'late',
    current_date - 764,
    'sam.okafor@supasheet.app'
  );

insert into
  manufacturing.operator_certifications (
    operator_id,
    work_center_id,
    certified_on,
    expires_on,
    skill_level,
    assessed_by
  )
values
  (
    'b7000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000002',
    current_date - 161,
    null,
    2,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000003',
    current_date - 184,
    null,
    3,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000006',
    current_date - 207,
    null,
    4,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000001',
    'b2000000-0000-0000-0000-000000000007',
    current_date - 230,
    current_date + 47,
    5,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000002',
    current_date - 172,
    null,
    3,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000002',
    'b2000000-0000-0000-0000-000000000003',
    current_date - 195,
    null,
    4,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000006',
    current_date - 183,
    null,
    4,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000007',
    current_date - 206,
    current_date + 81,
    5,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000003',
    'b2000000-0000-0000-0000-000000000008',
    current_date - 229,
    null,
    1,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000004',
    'b2000000-0000-0000-0000-000000000001',
    current_date - 194,
    current_date + 98,
    5,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000004',
    'b2000000-0000-0000-0000-000000000004',
    current_date - 217,
    null,
    1,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000005',
    'b2000000-0000-0000-0000-000000000002',
    current_date - 205,
    null,
    1,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000005',
    'b2000000-0000-0000-0000-000000000006',
    current_date - 228,
    null,
    2,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000006',
    'b2000000-0000-0000-0000-000000000004',
    current_date - 216,
    null,
    2,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000006',
    'b2000000-0000-0000-0000-000000000005',
    current_date - 239,
    null,
    3,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000007',
    'b2000000-0000-0000-0000-000000000006',
    current_date - 227,
    null,
    3,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000007',
    'b2000000-0000-0000-0000-000000000007',
    current_date - 250,
    current_date + 149,
    4,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000008',
    'b2000000-0000-0000-0000-000000000001',
    current_date - 238,
    current_date + 166,
    4,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000008',
    'b2000000-0000-0000-0000-000000000002',
    current_date - 261,
    null,
    5,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000009',
    'b2000000-0000-0000-0000-000000000006',
    current_date - 249,
    null,
    5,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000009',
    'b2000000-0000-0000-0000-000000000008',
    current_date - 272,
    null,
    1,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000010',
    'b2000000-0000-0000-0000-000000000003',
    current_date - 260,
    null,
    1,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000010',
    'b2000000-0000-0000-0000-000000000004',
    current_date - 283,
    null,
    2,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000010',
    'b2000000-0000-0000-0000-000000000005',
    current_date - 306,
    current_date + 200,
    3,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000011',
    'b2000000-0000-0000-0000-000000000006',
    current_date - 271,
    null,
    2,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000011',
    'b2000000-0000-0000-0000-000000000007',
    current_date - 294,
    current_date + 217,
    3,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000012',
    'b2000000-0000-0000-0000-000000000001',
    current_date - 282,
    current_date + 234,
    3,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000012',
    'b2000000-0000-0000-0000-000000000002',
    current_date - 305,
    null,
    4,
    'Harriet Vance'
  ),
  (
    'b7000000-0000-0000-0000-000000000012',
    'b2000000-0000-0000-0000-000000000003',
    current_date - 328,
    null,
    5,
    'Harriet Vance'
  );

----------------------------------------------------------------
-- Defect codes
----------------------------------------------------------------
insert into
  manufacturing.defect_codes (id, code, name, description, severity, category)
values
  (
    'b8000000-0000-0000-0000-000000000001',
    'DIM-OUT',
    'Dimension out of tolerance',
    'Measured feature outside the drawing limits',
    'major',
    'Dimensional'
  ),
  (
    'b8000000-0000-0000-0000-000000000002',
    'SURF-SCR',
    'Surface scratch',
    'Cosmetic damage to a finished face',
    'minor',
    'Cosmetic'
  ),
  (
    'b8000000-0000-0000-0000-000000000003',
    'WELD-POR',
    'Weld porosity',
    'Gas inclusion visible in the weld',
    'major',
    'Process'
  ),
  (
    'b8000000-0000-0000-0000-000000000004',
    'MAT-WRONG',
    'Wrong material',
    'Part made from the wrong stock',
    'critical',
    'Material'
  ),
  (
    'b8000000-0000-0000-0000-000000000005',
    'ASM-MISS',
    'Missing component',
    'Assembly short of a component',
    'critical',
    'Assembly'
  ),
  (
    'b8000000-0000-0000-0000-000000000006',
    'FIN-RUN',
    'Paint run',
    'Finish applied too heavily',
    'minor',
    'Cosmetic'
  ),
  (
    'b8000000-0000-0000-0000-000000000007',
    'THR-DAM',
    'Damaged thread',
    'Thread stripped or crossed',
    'major',
    'Mechanical'
  ),
  (
    'b8000000-0000-0000-0000-000000000008',
    'LEAK',
    'Leak on test',
    'Failed pressure or leak test',
    'critical',
    'Functional'
  ),
  (
    'b8000000-0000-0000-0000-000000000009',
    'LBL-ERR',
    'Labelling error',
    'Wrong or missing identification',
    'minor',
    'Documentation'
  ),
  (
    'b8000000-0000-0000-0000-000000000010',
    'CONT',
    'Contamination',
    'Foreign matter present',
    'major',
    'Material'
  );

----------------------------------------------------------------
-- Inspection plans
--
-- What gets measured, and what counts as in specification. The
-- tolerance band is what the result trigger judges a measurement
-- against — a characteristic without one is left to the inspector.
----------------------------------------------------------------
insert into
  manufacturing.quality_characteristics (
    id,
    product_id,
    code,
    name,
    characteristic_type,
    unit,
    nominal_value,
    tolerance_lower,
    tolerance_upper,
    method,
    sample_size,
    is_critical
  )
values
  (
    'b9000000-0000-0000-0000-000000000001',
    'b4000000-0000-0000-0000-000000000001',
    'DIM-BORE',
    'Impeller bore',
    'dimensional',
    'mm',
    25.0,
    24.95,
    25.05,
    'Bore gauge',
    2,
    true
  ),
  (
    'b9000000-0000-0000-0000-000000000002',
    'b4000000-0000-0000-0000-000000000001',
    'PRESS',
    'Hydrostatic pressure',
    'functional',
    'bar',
    16.0,
    15.5,
    null,
    'Test rig',
    3,
    true
  ),
  (
    'b9000000-0000-0000-0000-000000000003',
    'b4000000-0000-0000-0000-000000000001',
    'FIN',
    'Paint finish',
    'visual',
    null,
    null,
    null,
    null,
    'Visual',
    1,
    false
  ),
  (
    'b9000000-0000-0000-0000-000000000004',
    'b4000000-0000-0000-0000-000000000002',
    'DIM-BORE',
    'Impeller bore',
    'dimensional',
    'mm',
    40.0,
    39.94,
    40.06,
    'Bore gauge',
    2,
    true
  ),
  (
    'b9000000-0000-0000-0000-000000000005',
    'b4000000-0000-0000-0000-000000000002',
    'PRESS',
    'Hydrostatic pressure',
    'functional',
    'bar',
    16.0,
    15.5,
    null,
    'Test rig',
    3,
    true
  ),
  (
    'b9000000-0000-0000-0000-000000000006',
    'b4000000-0000-0000-0000-000000000003',
    'SEAT',
    'Seat leak rate',
    'functional',
    'ml/min',
    0.0,
    null,
    2.0,
    'Leak test',
    1,
    true
  ),
  (
    'b9000000-0000-0000-0000-000000000007',
    'b4000000-0000-0000-0000-000000000003',
    'TORQUE',
    'Operating torque',
    'functional',
    'Nm',
    18.0,
    14.0,
    24.0,
    'Torque wrench',
    2,
    false
  ),
  (
    'b9000000-0000-0000-0000-000000000008',
    'b4000000-0000-0000-0000-000000000004',
    'SEAT',
    'Seat leak rate',
    'functional',
    'ml/min',
    0.0,
    null,
    3.0,
    'Leak test',
    3,
    true
  ),
  (
    'b9000000-0000-0000-0000-000000000009',
    'b4000000-0000-0000-0000-000000000005',
    'BACKLASH',
    'Gear backlash',
    'dimensional',
    'mm',
    0.12,
    0.08,
    0.18,
    'Dial indicator',
    1,
    true
  ),
  (
    'b9000000-0000-0000-0000-000000000010',
    'b4000000-0000-0000-0000-000000000005',
    'NOISE',
    'Running noise',
    'functional',
    'dB',
    68.0,
    null,
    75.0,
    'Sound meter',
    2,
    false
  ),
  (
    'b9000000-0000-0000-0000-000000000011',
    'b4000000-0000-0000-0000-000000000006',
    'STROKE',
    'Stroke length',
    'dimensional',
    'mm',
    50.0,
    49.5,
    50.5,
    'Vernier',
    3,
    true
  ),
  (
    'b9000000-0000-0000-0000-000000000012',
    'b4000000-0000-0000-0000-000000000017',
    'OD',
    'Outside diameter',
    'dimensional',
    'mm',
    39.98,
    39.96,
    40.0,
    'Micrometer',
    1,
    true
  ),
  (
    'b9000000-0000-0000-0000-000000000013',
    'b4000000-0000-0000-0000-000000000017',
    'RUNOUT',
    'Total runout',
    'dimensional',
    'mm',
    0.0,
    null,
    0.03,
    'Dial indicator',
    2,
    true
  ),
  (
    'b9000000-0000-0000-0000-000000000014',
    'b4000000-0000-0000-0000-000000000017',
    'RA',
    'Surface roughness',
    'material',
    'um',
    0.8,
    null,
    1.6,
    'Profilometer',
    3,
    false
  ),
  (
    'b9000000-0000-0000-0000-000000000015',
    'b4000000-0000-0000-0000-000000000024',
    'PCD',
    'Pitch circle diameter',
    'dimensional',
    'mm',
    62.5,
    62.45,
    62.55,
    'CMM',
    1,
    true
  ),
  (
    'b9000000-0000-0000-0000-000000000016',
    'b4000000-0000-0000-0000-000000000021',
    'THK',
    'Thickness',
    'dimensional',
    'mm',
    10.0,
    9.8,
    10.2,
    'Micrometer',
    2,
    false
  ),
  (
    'b9000000-0000-0000-0000-000000000017',
    'b4000000-0000-0000-0000-000000000021',
    'PCD',
    'Bolt circle',
    'dimensional',
    'mm',
    110.0,
    109.8,
    110.2,
    'CMM',
    3,
    true
  );

----------------------------------------------------------------
-- Roll the cost up before anything is planned
--
-- Works orders freeze the component costs onto themselves at release,
-- so the roll-up has to have happened first or every order would
-- carry zeros.
----------------------------------------------------------------
select
  manufacturing.roll_up_cost () as products_costed;

----------------------------------------------------------------
-- Who can book work here
--
-- The confirmation guard refuses an operator who is not certified on
-- the work centre, so the seed has to pick one who is rather than
-- turning the check off.
----------------------------------------------------------------
create or replace function pg_temp.certified_operator (p_work_center_id uuid, p_seed bigint) returns uuid language sql stable as $$
  select o.id
  from manufacturing.operators o
    join manufacturing.operator_certifications c on c.operator_id = o.id
  where c.work_center_id = p_work_center_id
    and o.is_active
    and (c.expires_on is null or c.expires_on >= current_date)
  order by (abs(hashtext (o.badge_number || p_seed::text)) % 1000000)
  limit 1;
$$;

create or replace function pg_temp.machine_for (p_work_center_id uuid, p_seed bigint) returns uuid language sql stable as $$
  select m.id
  from manufacturing.machines m
  where m.work_center_id = p_work_center_id
    and m.status <> 'retired'
  order by (abs(hashtext (m.code || p_seed::text)) % 1000000)
  limit 1;
$$;

----------------------------------------------------------------
-- Works orders
--
-- Raised, released — which is what freezes the bill and the routing
-- onto them — and then confirmed operation by operation, in sequence,
-- by somebody certified on the work centre. Every yield, efficiency
-- and actual hour in the finished dataset is a consequence of those
-- confirmations rather than a number written down.
--
-- The outcome is chosen from the order's AGE: old orders are closed,
-- recent ones are still being drafted, and the ones in between are on
-- the floor — which is what makes the shop-floor board worth opening.
----------------------------------------------------------------
do $$
declare
  v_order record;
  v_op record;
  v_product record;
  v_wo uuid;
  v_seed bigint;
  v_age integer;
  v_roll integer;
  v_planned date;
  v_running numeric(14, 3);
  v_scrap numeric(14, 3);
  v_good numeric(14, 3);
  v_operator uuid;
  v_machine uuid;
  v_when timestamptz;
  v_setup numeric(10, 2);
  v_run numeric(10, 2);
  v_eff numeric;
  i integer;
begin
  for i in 1..135 loop
    v_seed := abs(hashtext ('supasheet-mfg-wo-' || i::text));

    -- Finished goods and sub-assemblies are what gets ordered; the
    -- machined parts underneath them are made on their own orders too,
    -- but less often.
    select p.id, p.sku, p.lot_size, p.yield_percent
    into v_product
    from manufacturing.products p
    where p.product_type = 'make'
      and p.status = 'active'
      and (
        case
          when (v_seed % 10) < 5 then p.sku like 'FG-%'
          when (v_seed % 10) < 8 then p.sku like 'SA-%'
          else p.sku like 'MC-%' or p.sku like 'FB-%'
        end
      )
    order by (abs(hashtext (p.sku || i::text)) % 1000000)
    limit 1;

    continue when v_product.id is null;

    -- One cohort per month across the last year.
    v_planned := least(
      (
        date_trunc('month', current_date) - ((11 - ((i - 1) % 12)) || ' months')::interval
      )::date + (v_seed % 24)::integer,
      current_date
    );

    insert into manufacturing.production_orders (
      product_id, quantity_ordered, planned_start, planned_end, priority, sales_reference, status
    )
    values (
      v_product.id,
      greatest(round(v_product.lot_size * (0.5 + (v_seed % 200) / 100.0), 0), 1),
      v_planned,
      v_planned + 3 + (v_seed % 9)::integer,
      (array['low', 'normal', 'normal', 'normal', 'high', 'urgent'])[
        1 + (v_seed % 6)::integer
      ]::manufacturing.order_priority,
      'SO-' || lpad(((v_seed / 3) % 90000)::text, 5, '0'),
      'draft'
    )
    returning id into v_wo;

    v_age := current_date - v_planned;
    v_roll := ((v_seed / 7) % 100)::integer;

    -- Recent orders are still being written up.
    if v_age <= 20 and v_roll < 35 then
      continue;
    end if;

    update manufacturing.production_orders set status = 'planned' where id = v_wo;

    -- Planned but not yet let go to the floor.
    continue when v_age <= 25 and ((v_seed / 13) % 100)::integer < 45;

    update manufacturing.production_orders set status = 'released' where id = v_wo;

    -- Released, waiting on a machine.
    continue when v_age <= 30 and ((v_seed / 17) % 100)::integer < 40;

    select quantity_started into v_running from manufacturing.production_orders where id = v_wo;

    for v_op in
      select *
      from manufacturing.production_order_operations
      where production_order_id = v_wo
      order by sequence_number
    loop
      v_operator := pg_temp.certified_operator (v_op.work_center_id, v_seed + v_op.sequence_number);
      v_machine := pg_temp.machine_for (v_op.work_center_id, v_seed + v_op.sequence_number);

      continue when v_operator is null;

      -- A little is lost at each step, more on the machining ones.
      v_scrap := case
        when (abs(hashtext (v_op.id::text)) % 5) = 0
        then greatest(round(v_running * (0.01 + (abs(hashtext (v_op.id::text)) % 4) / 100.0), 0), 1)
        else 0
      end;

      v_scrap := least(v_scrap, greatest(v_running - 1, 0));
      v_good := v_running - v_scrap;

      -- Real time against standard: mostly close, sometimes well off.
      v_eff := 0.78 + ((abs(hashtext (v_op.id::text || 'eff')) % 55) / 100.0);
      v_setup := round(v_op.planned_setup_minutes * v_eff, 2);
      v_run := round(v_op.planned_run_minutes * v_eff, 2);

      v_when := (v_planned + v_op.sequence_number / 10)::timestamptz
        + interval '7 hours'
        + ((abs(hashtext (v_op.id::text)) % 480) || ' minutes')::interval;

      insert into manufacturing.production_confirmations (
        production_order_id, operation_id, operator_id, machine_id, confirmed_at,
        quantity_good, quantity_scrap, setup_minutes, run_minutes, scrap_reason, is_final
      )
      values (
        v_wo,
        v_op.id,
        v_operator,
        v_machine,
        least(v_when, current_timestamp),
        v_good,
        v_scrap,
        v_setup,
        v_run,
        case
          when v_scrap > 0 then (array[
            'Tooling wear — parts out of tolerance',
            'Material flaw found on inspection',
            'Setup error on the first pieces',
            'Handling damage at the bench',
            'Failed leak test'
          ]) [1 + (abs(hashtext (v_op.id::text)) % 5)]
          else null
        end,
        true
      );

      v_running := v_good;

      -- Some orders are still part way through the routing.
      exit when v_age <= 45 and (abs(hashtext (v_op.id::text || 'stop')) % 100) < 28;
    end loop;

    -- Only orders whose last operation actually finished are complete.
    if not exists (
      select 1
      from manufacturing.production_order_operations
      where production_order_id = v_wo
        and status <> 'completed'
    ) then
      update manufacturing.production_orders set status = 'completed' where id = v_wo;

      -- Only orders old enough to have been reviewed get closed off;
      -- closing everything would leave the completed column empty.
      if v_age > 70 and v_roll < 72 then
        update manufacturing.production_orders set status = 'closed' where id = v_wo;
      end if;
    end if;
  end loop;
end;
$$;

----------------------------------------------------------------
-- A few orders that never ran
----------------------------------------------------------------
do $$
declare
  v_wo uuid;
  v_product uuid;
  i integer;
begin
  for i in 1..5 loop
    select id into v_product
    from manufacturing.products
    where product_type = 'make'
      and status = 'active'
    order by (abs(hashtext (sku || 'cancel' || i::text)) % 1000000)
    limit 1;

    insert into manufacturing.production_orders (
      product_id, quantity_ordered, planned_start, planned_end, priority, sales_reference
    )
    values (
      v_product,
      10 * i,
      current_date - (30 * i),
      current_date - (30 * i) + 7,
      'normal',
      'SO-CANCELLED-' || i
    )
    returning id into v_wo;

    update manufacturing.production_orders
    set status = 'cancelled',
      cancelled_reason = (array[
        'Customer cancelled the sales order',
        'Superseded by a larger batch',
        'Engineering change pending — rebuild to the new revision'
      ]) [1 + (i % 3)]
    where id = v_wo;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Downtime
--
-- Every minute a machine could not run. Durations follow the reason:
-- a changeover is twenty minutes, a breakdown is most of a shift.
----------------------------------------------------------------
do $$
declare
  v_machine record;
  v_seed bigint;
  v_reason manufacturing.downtime_reason;
  v_start timestamptz;
  v_minutes integer;
  i integer;
begin
  for i in 1..130 loop
    v_seed := abs(hashtext ('supasheet-mfg-down-' || i::text));

    select m.id, m.work_center_id
    into v_machine
    from manufacturing.machines m
    where m.status <> 'retired'
    order by (abs(hashtext (m.code || i::text)) % 1000000)
    limit 1;

    v_reason := (array[
      'breakdown', 'changeover', 'changeover', 'material_shortage',
      'no_operator', 'quality_hold', 'planned_maintenance', 'tooling', 'tooling'
    ]) [1 + (v_seed % 9)::integer]::manufacturing.downtime_reason;

    v_minutes := case v_reason
      when 'breakdown' then 120 + (v_seed % 340)::integer
      when 'changeover' then 15 + (v_seed % 40)::integer
      when 'material_shortage' then 45 + (v_seed % 180)::integer
      when 'no_operator' then 60 + (v_seed % 120)::integer
      when 'quality_hold' then 30 + (v_seed % 150)::integer
      when 'planned_maintenance' then 90 + (v_seed % 240)::integer
      else 20 + (v_seed % 70)::integer
    end;

    v_start := least(
      (
        date_trunc('month', current_date) - ((11 - ((i - 1) % 12)) || ' months')::interval
      )::date + (v_seed % 25)::integer,
      current_date
    )::timestamptz + ((6 + (v_seed % 12)) || ' hours')::interval;

    insert into manufacturing.downtime_events (
      machine_id, work_center_id, reason, started_at, ended_at, reported_by, description, resolution
    )
    values (
      v_machine.id,
      v_machine.work_center_id,
      v_reason,
      v_start,
      -- The most recent handful are still open, which is what the
      -- "Still Down" preset and the machine status derive from.
      case
        when current_date - v_start::date <= 2 and (v_seed % 4) = 0 then null
        else v_start + (v_minutes || ' minutes')::interval
      end,
      (
        select id
        from manufacturing.operators
        order by (abs(hashtext (badge_number || i::text)) % 1000000)
        limit 1
      ),
      case v_reason
        when 'breakdown' then 'Spindle drive fault — machine stopped mid-cycle'
        when 'changeover' then 'Tooling changeover between works orders'
        when 'material_shortage' then 'Waiting on bar stock from the stores'
        when 'no_operator' then 'No certified operator on shift'
        when 'quality_hold' then 'Held pending inspection of the first-off'
        when 'planned_maintenance' then 'Scheduled service window'
        else 'Tool broke and had to be reground'
      end,
      case
        when (v_seed % 3) = 0 then 'Fixed on the day; no recurrence since.'
        else null
      end
    );
  end loop;
end;
$$;

----------------------------------------------------------------
-- Maintenance history
----------------------------------------------------------------
do $$
declare
  v_machine uuid;
  v_seed bigint;
  v_type manufacturing.maintenance_type;
  v_when date;
  v_id uuid;
  i integer;
begin
  for i in 1..80 loop
    v_seed := abs(hashtext ('supasheet-mfg-mnt-' || i::text));

    select id into v_machine
    from manufacturing.machines
    where status <> 'retired'
    order by (abs(hashtext (code || 'mnt' || i::text)) % 1000000)
    limit 1;

    v_type := (array['preventive', 'preventive', 'preventive', 'corrective', 'calibration', 'inspection'])[
      1 + (v_seed % 6)::integer
    ]::manufacturing.maintenance_type;

    v_when := least(
      (
        date_trunc('month', current_date) - ((11 - ((i - 1) % 12)) || ' months')::interval
      )::date + (v_seed % 26)::integer,
      current_date + 20
    );

    insert into manufacturing.maintenance_orders (
      machine_id, maintenance_type, scheduled_for, assigned_to, description, parts_used, cost
    )
    values (
      v_machine,
      v_type,
      v_when,
      (array['Dev Patel', 'Tomas Nowak', 'External contractor', 'Piotr Zielinski'])[
        1 + (v_seed % 4)::integer
      ],
      case v_type
        when 'preventive' then 'Routine service — lubrication, filters and belt check'
        when 'corrective' then 'Repair following a breakdown'
        when 'calibration' then 'Annual calibration against traceable standards'
        else 'Statutory inspection'
      end,
      case when (v_seed % 3) = 0 then 'Filter set, drive belt, coolant' else null end,
      round((80 + (v_seed % 900))::numeric, 2)
    )
    returning id into v_id;

    -- Anything in the past has been done; anything ahead is still on
    -- the board. The maintenance trigger flags overdue on its own.
    if v_when < current_date - 2 then
      update manufacturing.maintenance_orders
      set status = 'in_progress',
        started_at = v_when::timestamptz + interval '8 hours'
      where id = v_id;

      update manufacturing.maintenance_orders
      set status = 'completed',
        completed_at = v_when::timestamptz + interval '8 hours'
          + ((60 + (v_seed % 300)) || ' minutes')::interval,
        work_done = 'Service completed and the machine handed back to production.'
      where id = v_id
        and (v_seed % 11) <> 0;
    end if;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Inspection
--
-- Against the works orders that reached their inspection point, on
-- the products that have a plan. Measurements sit close to nominal
-- with a genuine tail outside the tolerance band — which is what
-- makes the pass rate mean something and what raises the NCRs below.
----------------------------------------------------------------
do $$
declare
  v_order record;
  v_char record;
  v_insp uuid;
  v_seed bigint;
  v_value numeric(14, 4);
  v_span numeric(14, 4);
  v_out boolean;
  v_sample integer;
begin
  for v_order in
    select o.id,
      o.order_number,
      o.product_id,
      o.quantity_produced,
      o.planned_end,
      (
        select op.id
        from manufacturing.production_order_operations op
        where op.production_order_id = o.id
          and op.is_inspection_point
        order by op.sequence_number desc
        limit 1
      ) as operation_id
    from manufacturing.production_orders o
    where o.status in ('completed', 'closed')
      and exists (
        select 1
        from manufacturing.quality_characteristics qc
        where qc.product_id = o.product_id
          and qc.is_active
      )
    order by o.planned_end
  loop
    v_seed := abs(hashtext ('insp-' || v_order.id::text));

    insert into manufacturing.inspections (
      production_order_id, operation_id, product_id, inspected_at,
      inspector_id, quantity_inspected, quantity_failed
    )
    values (
      v_order.id,
      v_order.operation_id,
      v_order.product_id,
      v_order.planned_end::timestamptz + interval '14 hours',
      'b73eb03e-fb7a-424d-84ff-18e2791ce0f4',
      greatest(round(v_order.quantity_produced * 0.1, 0), 1),
      0
    )
    returning id into v_insp;

    for v_char in
      select *
      from manufacturing.quality_characteristics
      where product_id = v_order.product_id
        and is_active
      order by code
    loop
      for v_sample in 1..v_char.sample_size loop
        if v_char.nominal_value is null then
          insert into manufacturing.inspection_results (
            inspection_id, characteristic_id, sample_number, text_value, is_within_spec
          )
          values (
            v_insp,
            v_char.id,
            v_sample,
            case
              when (abs(hashtext (v_insp::text || v_char.code || v_sample::text)) % 20) = 0
              then 'Minor blemish noted'
              else 'Conforms'
            end,
            (abs(hashtext (v_insp::text || v_char.code || v_sample::text)) % 20) <> 0
          );

          continue;
        end if;

        -- Roughly one measurement in nine lands outside the band.
        v_out := (abs(hashtext (v_insp::text || v_char.code || v_sample::text)) % 9) = 0;

        v_span := coalesce(
          nullif(coalesce(v_char.tolerance_upper, v_char.nominal_value) - v_char.nominal_value, 0),
          nullif(v_char.nominal_value - coalesce(v_char.tolerance_lower, v_char.nominal_value), 0),
          greatest(v_char.nominal_value * 0.02, 0.05)
        );

        v_value := round(
          v_char.nominal_value + v_span * case
            when v_out then 1.4 + (abs(hashtext (v_insp::text || v_char.code)) % 60) / 100.0
            else -0.6 + (abs(hashtext (v_insp::text || v_char.code || v_sample::text)) % 120) / 100.0
          end,
          4
        );

        insert into manufacturing.inspection_results (
          inspection_id, characteristic_id, sample_number, measured_value, defect_code_id
        )
        values (
          v_insp,
          v_char.id,
          v_sample,
          greatest(v_value, 0),
          case
            when v_out then (
              select id
              from manufacturing.defect_codes
              where code = 'DIM-OUT'
            )
            else null
          end
        );
      end loop;
    end loop;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Non-conformances
--
-- Raised off the inspections that failed, plus the ones the floor
-- reported directly. Older reports have been through the whole cycle;
-- recent ones are still open, which is what the NCR board is for.
----------------------------------------------------------------
do $$
declare
  v_insp record;
  v_ncr uuid;
  v_seed bigint;
  v_age integer;
  v_defect record;
  i integer := 0;
begin
  for v_insp in
    select ins.*, o.order_number, o.planned_end
    from manufacturing.inspections ins
      join manufacturing.production_orders o on o.id = ins.production_order_id
    where ins.result = 'fail'
    order by ins.inspected_at
  loop
    i := i + 1;
    v_seed := abs(hashtext ('ncr-' || v_insp.id::text));

    select * into v_defect
    from manufacturing.defect_codes
    order by (abs(hashtext (code || i::text)) % 1000000)
    limit 1;

    insert into manufacturing.nonconformances (
      production_order_id, inspection_id, product_id, defect_code_id, severity,
      quantity_affected, raised_at, raised_by, title, description, cost_impact
    )
    values (
      v_insp.production_order_id,
      v_insp.id,
      v_insp.product_id,
      v_defect.id,
      v_defect.severity,
      greatest(round(v_insp.quantity_inspected * 0.3, 0), 1),
      v_insp.inspected_at + interval '2 hours',
      'b73eb03e-fb7a-424d-84ff-18e2791ce0f4',
      v_defect.name || ' on ' || v_insp.inspection_number,
      'Raised from inspection ' || v_insp.inspection_number || ' against works order '
        || v_insp.order_number || '. ' || coalesce(v_defect.description, ''),
      round((40 + (v_seed % 900))::numeric, 2)
    )
    returning id into v_ncr;

    v_age := current_date - v_insp.inspected_at::date;

    continue when v_age <= 10;

    update manufacturing.nonconformances set status = 'investigating' where id = v_ncr;

    continue when v_age <= 25;

    update manufacturing.nonconformances
    set disposition = (array['rework', 'rework', 'scrap', 'use_as_is', 'regrade'])[
        1 + (v_seed % 5)::integer
      ]::manufacturing.ncr_disposition,
      status = 'dispositioned',
      dispositioned_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0f1',
      dispositioned_at = v_insp.inspected_at + interval '3 days'
    where id = v_ncr;

    continue when v_age <= 45 or (v_seed % 6) = 0;

    update manufacturing.nonconformances
    set root_cause = (array[
        'Tool offset drifted after the insert change and was not re-zeroed.',
        'Incoming casting was outside the supplier''s own drawing limits.',
        'Operator worked to a superseded revision of the drawing.',
        'Fixture clamp had worked loose over the batch.'
      ]) [1 + (v_seed % 4)::integer],
      corrective_action = (array[
        'Added a first-off check to the routing at this operation.',
        'Raised a supplier concern and added goods-in gauging.',
        'Withdrew the old revision from the cell and retrained the shift.',
        'Fixture added to the preventive maintenance schedule.'
      ]) [1 + (v_seed % 4)::integer],
      status = 'closed',
      closed_at = v_insp.inspected_at + interval '12 days'
    where id = v_ncr;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Non-conformances raised on the floor
--
-- Not everything is found by an inspector at the end. These come off
-- the bench and out of the cells, and the recent ones are still open
-- — which is the point of the board.
----------------------------------------------------------------
do $$
declare
  v_order record;
  v_defect record;
  v_ncr uuid;
  v_seed bigint;
  v_raised date;
  v_age integer;
  i integer;
begin
  for i in 1..42 loop
    v_seed := abs(hashtext ('supasheet-mfg-floorncr-' || i::text));

    select o.id, o.order_number, o.product_id, o.quantity_ordered
    into v_order
    from manufacturing.production_orders o
    where o.status in ('in_progress', 'completed', 'closed')
    order by (abs(hashtext (o.order_number || i::text)) % 1000000)
    limit 1;

    continue when v_order.id is null;

    select * into v_defect
    from manufacturing.defect_codes
    order by (abs(hashtext (code || 'floor' || i::text)) % 1000000)
    limit 1;

    v_raised := least(
      (
        date_trunc('month', current_date) - ((11 - ((i - 1) % 12)) || ' months')::interval
      )::date + (v_seed % 25)::integer,
      current_date
    );

    insert into manufacturing.nonconformances (
      production_order_id, product_id, defect_code_id, severity,
      quantity_affected, raised_at, raised_by, title, description, cost_impact
    )
    values (
      v_order.id,
      v_order.product_id,
      v_defect.id,
      v_defect.severity,
      greatest(round(v_order.quantity_ordered * 0.08, 0), 1),
      v_raised::timestamptz + interval '11 hours',
      'b73eb03e-fb7a-424d-84ff-18e2791ce0f3',
      v_defect.name || ' found at the bench',
      'Spotted during assembly on ' || v_order.order_number || '. ' || coalesce(v_defect.description, ''),
      round((25 + (v_seed % 600))::numeric, 2)
    )
    returning id into v_ncr;

    v_age := current_date - v_raised;

    continue when v_age <= 12;

    update manufacturing.nonconformances set status = 'investigating' where id = v_ncr;

    continue when v_age <= 30 or ((v_seed / 5) % 100)::integer < 20;

    update manufacturing.nonconformances
    set disposition = (array['rework', 'rework', 'scrap', 'use_as_is', 'return_to_supplier'])[
        1 + (v_seed % 5)::integer
      ]::manufacturing.ncr_disposition,
      status = 'dispositioned',
      dispositioned_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0f1',
      dispositioned_at = (v_raised + 4)::timestamptz + interval '10 hours'
    where id = v_ncr;

    continue when v_age <= 55 or ((v_seed / 7) % 100)::integer < 25;

    update manufacturing.nonconformances
    set root_cause = (array[
        'Batch of castings from a new supplier ran consistently oversize.',
        'Paint booth temperature drifted below the process window overnight.',
        'Assembly instruction did not call out the torque sequence.',
        'Gauge was out of calibration and passed parts it should have failed.'
      ]) [1 + (v_seed % 4)::integer],
      corrective_action = (array[
        'Supplier concern raised and first-article inspection reinstated.',
        'Booth temperature added to the shift start-up checks.',
        'Work instruction reissued with the torque sequence and a diagram.',
        'Gauge brought into the calibration schedule and re-verified.'
      ]) [1 + (v_seed % 4)::integer],
      status = 'closed',
      closed_at = (v_raised + 16)::timestamptz + interval '15 hours'
    where id = v_ncr;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Work in progress
--
-- An order that is in progress has somebody mid-operation on it. The
-- confirmation walk above leaves every operation either finished or
-- untouched, which is a floor where nobody is currently working —
-- so the next pending step on each open order is picked up here.
----------------------------------------------------------------
do $$
declare
  v_op record;
begin
  for v_op in
    select distinct on (op.production_order_id) op.id, op.work_center_id, op.production_order_id
    from manufacturing.production_order_operations op
      join manufacturing.production_orders o on o.id = op.production_order_id
    where o.status = 'in_progress'
      and op.status = 'pending'
    order by op.production_order_id, op.sequence_number
  loop
    update manufacturing.production_order_operations
    set status = case
      when (abs(hashtext (v_op.id::text)) % 5) = 0 then 'setup'::manufacturing.operation_status
      when (abs(hashtext (v_op.id::text)) % 7) = 0 then 'paused'::manufacturing.operation_status
      else 'running'::manufacturing.operation_status
    end,
      started_at = current_timestamp - ((abs(hashtext (v_op.id::text)) % 300) || ' minutes')::interval,
      assigned_operator_id = pg_temp.certified_operator (
        v_op.work_center_id,
        abs(hashtext (v_op.id::text))
      ),
      machine_id = pg_temp.machine_for (v_op.work_center_id, abs(hashtext (v_op.id::text)))
    where id = v_op.id;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Age the paperwork
--
-- The confirmations were already stamped with when the work happened,
-- because that is what the yields and the twelve-month trend are
-- built from. What is left is the documents around them, which all
-- carry the moment this file ran.
----------------------------------------------------------------
update manufacturing.production_orders
set
  created_at = planned_start::timestamptz + interval '8 hours',
  released_at = case
    when status in ('draft', 'planned') then null
    else planned_start::timestamptz + interval '9 hours'
  end,
  released_by = case
    when status in ('draft', 'planned') then null
    else 'b73eb03e-fb7a-424d-84ff-18e2791ce0f2'::uuid
  end,
  user_id = 'b73eb03e-fb7a-424d-84ff-18e2791ce0f2',
  closed_at = case
    when status = 'closed' then coalesce(actual_end, planned_end::timestamptz) + interval '3 days'
    else null
  end;

update manufacturing.production_order_operations op
set
  created_at = o.planned_start::timestamptz + interval '9 hours',
  assigned_operator_id = coalesce(
    op.assigned_operator_id,
    (
      select
        cf.operator_id
      from
        manufacturing.production_confirmations cf
      where
        cf.operation_id = op.id
      limit
        1
    )
  ),
  machine_id = coalesce(
    op.machine_id,
    (
      select
        cf.machine_id
      from
        manufacturing.production_confirmations cf
      where
        cf.operation_id = op.id
      limit
        1
    )
  )
from
  manufacturing.production_orders o
where
  o.id = op.production_order_id;

update manufacturing.production_confirmations
set
  created_at = confirmed_at;

update manufacturing.boms
set
  created_at = current_timestamp - interval '400 days',
  approved_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0f2',
  approved_at = current_timestamp - interval '399 days';

update manufacturing.routings
set
  created_at = current_timestamp - interval '400 days';

update manufacturing.products
set
  created_at = current_timestamp - interval '410 days';

update manufacturing.machines m
set
  created_at = m.commissioned_on::timestamptz,
  last_service_on = (
    select
      max(mo.completed_at)::date
    from
      manufacturing.maintenance_orders mo
    where
      mo.machine_id = m.id
      and mo.status = 'completed'
  );

update manufacturing.machines
set
  next_service_due = last_service_on + service_interval_days
where
  last_service_on is not null;

update manufacturing.inspections
set
  created_at = inspected_at;

update manufacturing.nonconformances
set
  created_at = raised_at;

----------------------------------------------------------------
-- Run the nightly maintenance once, then rebuild the snapshot.
--
-- This ages the overdue maintenance, expires the certifications that
-- have lapsed, raises preventive jobs for machines that are due, and
-- rolls the standard cost up again.
----------------------------------------------------------------
select
  *
from
  manufacturing.run_daily_maintenance ();

refresh materialized view manufacturing.production_summary;

select
  supasheet.refresh_metadata ();
