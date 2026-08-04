-- Inventory Seeder
-- ================================================================
-- Demo data for the inventory (warehouse and stock control) module.
-- Apply supabase/examples/20260805000000_inventory.sql first:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260805000000_inventory.sql \
--     -f supabase/examples/i_seed.sql
--
-- Volume: 3 warehouses with 12 zones and 172 bins, 10 units of
-- measure, a 17-node category tree, 92 items across untracked, lot
-- and serial tracking, 14 suppliers with 176 catalogue entries and 60
-- alternate barcodes, 101 purchase orders carrying 427 lines, 90
-- goods receipts walked through dock and put-away, 72 lots, 295
-- serial numbers, 34 inter-site transfers, 58 internal requests, 279
-- pick lists over 572 lines, 34 cycle counts covering 1,538 count
-- lines, 40 adjustments — and 3,240 stock ledger movements underneath
-- all of it, across 633 bin balances.
--
-- What that adds up to is meant to hold together, not just look
-- plausible. After this file runs:
--
--   - the sum of the ledger equals the sum of every bin balance,
--     which equals the on-hand figure on every item
--   - no bin is negative, and no reservation outlives the stock it
--     was pointing at
--   - both halves of every transfer and put-away net to zero
--   - each lot's on-hand equals the bins it sits in, and each
--     serialised item's on-hand equals the count of its in-stock
--     serial numbers, each of which is in exactly one place
--   - received quantities on purchase order lines equal the receipt
--     lines booked against them
--   - allocated never exceeds on hand, and available is always the
--     difference
--
-- If a change to this file breaks one of those, the data is wrong
-- rather than merely different.
--
-- WHY THIS FILE WALKS ITS RECORDS
--
-- Stock cannot be written down. inventory.stock_levels has no INSERT
-- or UPDATE grant for anybody, and the ledger behind it takes writes
-- through one SECURITY DEFINER function and refuses UPDATE and DELETE
-- outright. So there is no shortcut available even if one were
-- wanted: every unit in this dataset arrived on a purchase order, was
-- booked onto a dock, was put away into a bin, and was then picked,
-- transferred, counted or written off from there.
--
-- That is also the only way to exercise what the module is for. Stock
-- inserted as a final balance would never test the negative-stock
-- refusal, the lot and serial requirements, the FEFO bin suggestion,
-- the allocation that makes reserved stock unavailable, or the
-- two-sided move that keeps a transfer from losing units in transit.
--
-- Dates are relative to `current_date`, so the throughput charts, the
-- expiry calendar, the arrivals gantt and the count schedule all have
-- shape whenever this is run.
--
-- Three users are seeded (`on conflict do nothing`, so this is safe
-- alongside supabase/seed.sql and the other examples):
--   b73eb03e-fb7a-424d-84ff-18e2791ce0e1  inventory@supasheet.app (x-admin)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0e2  floor@supasheet.app     (warehouse)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0e3  buyer@supasheet.app     (inventory-planner)
--
-- Sign in as floor@supasheet.app for the OPERATIVE's seat: every bin,
-- every movement, every pick — and not one column anywhere in the
-- schema that says what any of it cost. buyer@supasheet.app is the
-- PLANNER: items, suppliers, orders and prices, with no ability to
-- move a single unit. user1@supasheet.app is an ordinary requester.
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e1',
    'authenticated',
    'authenticated',
    'inventory@supasheet.app',
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
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0e1", "email": "inventory@supasheet.app", "name": "Ruth Adeyemi", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e2',
    'authenticated',
    'authenticated',
    'floor@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "warehouse"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0e2", "email": "floor@supasheet.app", "name": "Danny Kovac", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e3',
    'authenticated',
    'authenticated',
    'buyer@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "inventory-planner"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0e3", "email": "buyer@supasheet.app", "name": "Mei Tanaka", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e1',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e1',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0e1", "email": "inventory@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ae1'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e2',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e2',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0e2", "email": "floor@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ae2'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e3',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e3',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0e3", "email": "buyer@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ae3'
  )
on conflict do nothing;

----------------------------------------------------------------
-- Units of measure
----------------------------------------------------------------
insert into
  inventory.unit_of_measures (id, code, name, uom_type, decimal_places, is_base)
values
  (
    'a1000000-0000-0000-0000-000000000001',
    'EA',
    'Each',
    'quantity',
    0,
    true
  ),
  (
    'a1000000-0000-0000-0000-000000000002',
    'BOX',
    'Box',
    'quantity',
    0,
    false
  ),
  (
    'a1000000-0000-0000-0000-000000000003',
    'CASE',
    'Case',
    'quantity',
    0,
    false
  ),
  (
    'a1000000-0000-0000-0000-000000000004',
    'PLT',
    'Pallet',
    'quantity',
    0,
    false
  ),
  (
    'a1000000-0000-0000-0000-000000000005',
    'KG',
    'Kilogram',
    'weight',
    3,
    true
  ),
  (
    'a1000000-0000-0000-0000-000000000006',
    'G',
    'Gram',
    'weight',
    0,
    false
  ),
  (
    'a1000000-0000-0000-0000-000000000007',
    'L',
    'Litre',
    'volume',
    3,
    true
  ),
  (
    'a1000000-0000-0000-0000-000000000008',
    'ML',
    'Millilitre',
    'volume',
    0,
    false
  ),
  (
    'a1000000-0000-0000-0000-000000000009',
    'M',
    'Metre',
    'length',
    2,
    true
  ),
  (
    'a1000000-0000-0000-0000-000000000010',
    'ROLL',
    'Roll',
    'quantity',
    0,
    false
  );

----------------------------------------------------------------
-- Item categories
----------------------------------------------------------------
insert into
  inventory.item_categories (
    id,
    parent_id,
    code,
    name,
    description,
    default_count_frequency_days,
    color
  )
values
  (
    'a2000000-0000-0000-0000-000000000001',
    null,
    'RAW',
    'Raw Materials',
    'Inputs consumed in production',
    30,
    '#f59e0b'
  ),
  (
    'a2000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000001',
    'RAW-MET',
    'Metals',
    'Sheet, bar and extrusion',
    30,
    '#fbbf24'
  ),
  (
    'a2000000-0000-0000-0000-000000000003',
    'a2000000-0000-0000-0000-000000000001',
    'RAW-POL',
    'Polymers',
    'Granulate, sheet and film',
    60,
    '#fcd34d'
  ),
  (
    'a2000000-0000-0000-0000-000000000004',
    'a2000000-0000-0000-0000-000000000001',
    'RAW-CHM',
    'Chemicals',
    'Solvents, adhesives and coatings',
    30,
    '#f97316'
  ),
  (
    'a2000000-0000-0000-0000-000000000005',
    null,
    'ELEC',
    'Electronics',
    'Boards, cable and components',
    30,
    '#6366f1'
  ),
  (
    'a2000000-0000-0000-0000-000000000006',
    'a2000000-0000-0000-0000-000000000005',
    'ELE-PCB',
    'Printed Circuit Boards',
    'Populated and bare boards',
    30,
    '#818cf8'
  ),
  (
    'a2000000-0000-0000-0000-000000000007',
    'a2000000-0000-0000-0000-000000000005',
    'ELE-CBL',
    'Cable and Connectors',
    'Looms, connectors and glands',
    90,
    '#a5b4fc'
  ),
  (
    'a2000000-0000-0000-0000-000000000008',
    null,
    'FIN',
    'Finished Goods',
    'Ready to ship',
    30,
    '#10b981'
  ),
  (
    'a2000000-0000-0000-0000-000000000009',
    'a2000000-0000-0000-0000-000000000008',
    'FIN-SEN',
    'Sensors',
    'Assembled sensing units',
    30,
    '#34d399'
  ),
  (
    'a2000000-0000-0000-0000-000000000010',
    'a2000000-0000-0000-0000-000000000008',
    'FIN-CTL',
    'Controllers',
    'Control units and gateways',
    30,
    '#6ee7b7'
  ),
  (
    'a2000000-0000-0000-0000-000000000011',
    'a2000000-0000-0000-0000-000000000008',
    'FIN-ASY',
    'Sub-assemblies',
    'Modules built to stock',
    60,
    '#a7f3d0'
  ),
  (
    'a2000000-0000-0000-0000-000000000012',
    null,
    'PACK',
    'Packaging',
    'Cartons, labels and fillers',
    90,
    '#94a3b8'
  ),
  (
    'a2000000-0000-0000-0000-000000000013',
    null,
    'SPARE',
    'Spare Parts',
    'Maintenance and service stock',
    180,
    '#0ea5e9'
  ),
  (
    'a2000000-0000-0000-0000-000000000014',
    'a2000000-0000-0000-0000-000000000013',
    'SPR-ELE',
    'Electrical Spares',
    'Fuses, relays and drives',
    180,
    '#38bdf8'
  ),
  (
    'a2000000-0000-0000-0000-000000000015',
    'a2000000-0000-0000-0000-000000000013',
    'SPR-MEC',
    'Mechanical Spares',
    'Bearings, seals and belts',
    180,
    '#7dd3fc'
  ),
  (
    'a2000000-0000-0000-0000-000000000016',
    null,
    'CONS',
    'Consumables',
    'Used up rather than sold',
    180,
    '#a78bfa'
  ),
  (
    'a2000000-0000-0000-0000-000000000017',
    null,
    'TOOL',
    'Tools and Equipment',
    'Durable items issued to staff',
    365,
    '#f472b6'
  );

----------------------------------------------------------------
-- Warehouses
--
-- Every rollup column on this table is left at its default. The
-- ledger fills them in as stock arrives.
----------------------------------------------------------------
insert into
  inventory.warehouses (
    id,
    code,
    name,
    address,
    city,
    country,
    timezone,
    is_active,
    is_default,
    manager_id,
    contact_email,
    contact_phone
  )
values
  (
    'a4000000-0000-0000-0000-000000000001',
    'LON',
    'London Distribution Centre',
    'Unit 4, Barking Riverside',
    'London',
    'GB',
    'Europe/London',
    true,
    true,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e1',
    'lon.warehouse@supasheet.app',
    '+44 20 7946 2100'
  ),
  (
    'a4000000-0000-0000-0000-000000000002',
    'MAN',
    'Manchester Hub',
    'Trafford Park, Ashburton Road',
    'Manchester',
    'GB',
    'Europe/London',
    true,
    false,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e2',
    'man.warehouse@supasheet.app',
    '+44 161 496 2200'
  ),
  (
    'a4000000-0000-0000-0000-000000000003',
    'ROT',
    'Rotterdam Forward Store',
    'Waalhaven Oostzijde 85',
    'Rotterdam',
    'NL',
    'Europe/Amsterdam',
    true,
    false,
    null,
    'rot.warehouse@supasheet.app',
    '+31 10 271 2300'
  );

----------------------------------------------------------------
-- Zones
----------------------------------------------------------------
insert into
  inventory.zones (
    id,
    warehouse_id,
    code,
    name,
    zone_type,
    temperature_controlled,
    pick_sequence
  )
values
  (
    'a5000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    'IN',
    'Goods In',
    'inbound',
    false,
    10
  ),
  (
    'a5000000-0000-0000-0000-000000000002',
    'a4000000-0000-0000-0000-000000000001',
    'ST',
    'Storage',
    'storage',
    false,
    100
  ),
  (
    'a5000000-0000-0000-0000-000000000003',
    'a4000000-0000-0000-0000-000000000001',
    'CHL',
    'Chilled Storage',
    'storage',
    true,
    150
  ),
  (
    'a5000000-0000-0000-0000-000000000004',
    'a4000000-0000-0000-0000-000000000001',
    'OUT',
    'Despatch',
    'outbound',
    false,
    900
  ),
  (
    'a5000000-0000-0000-0000-000000000005',
    'a4000000-0000-0000-0000-000000000001',
    'QA',
    'Quarantine',
    'quarantine',
    false,
    950
  ),
  (
    'a5000000-0000-0000-0000-000000000006',
    'a4000000-0000-0000-0000-000000000002',
    'IN',
    'Goods In',
    'inbound',
    false,
    10
  ),
  (
    'a5000000-0000-0000-0000-000000000007',
    'a4000000-0000-0000-0000-000000000002',
    'ST',
    'Storage',
    'storage',
    false,
    100
  ),
  (
    'a5000000-0000-0000-0000-000000000008',
    'a4000000-0000-0000-0000-000000000002',
    'OUT',
    'Despatch',
    'outbound',
    false,
    900
  ),
  (
    'a5000000-0000-0000-0000-000000000009',
    'a4000000-0000-0000-0000-000000000002',
    'QA',
    'Quarantine',
    'quarantine',
    false,
    950
  ),
  (
    'a5000000-0000-0000-0000-000000000010',
    'a4000000-0000-0000-0000-000000000003',
    'IN',
    'Goods In',
    'inbound',
    false,
    10
  ),
  (
    'a5000000-0000-0000-0000-000000000011',
    'a4000000-0000-0000-0000-000000000003',
    'ST',
    'Storage',
    'storage',
    false,
    100
  ),
  (
    'a5000000-0000-0000-0000-000000000012',
    'a4000000-0000-0000-0000-000000000003',
    'OUT',
    'Despatch',
    'outbound',
    false,
    900
  );

----------------------------------------------------------------
-- Fixed locations
--
-- Docks, staging, quarantine and one in-transit bin per site. The
-- in-transit bins are what stop a transfer from losing units between
-- despatch and arrival.
----------------------------------------------------------------
insert into
  inventory.locations (
    id,
    warehouse_id,
    zone_id,
    code,
    location_type,
    pick_sequence,
    is_pickable,
    is_receiving,
    is_quarantine,
    is_in_transit
  )
values
  (
    'a6000000-0000-0000-0000-000000000001',
    'a4000000-0000-0000-0000-000000000001',
    'a5000000-0000-0000-0000-000000000001',
    'LON-DOCK',
    'dock',
    1,
    false,
    true,
    false,
    false
  ),
  (
    'a6000000-0000-0000-0000-000000000002',
    'a4000000-0000-0000-0000-000000000001',
    'a5000000-0000-0000-0000-000000000001',
    'LON-STAGE',
    'staging',
    5,
    false,
    false,
    false,
    false
  ),
  (
    'a6000000-0000-0000-0000-000000000003',
    'a4000000-0000-0000-0000-000000000001',
    'a5000000-0000-0000-0000-000000000005',
    'LON-QA',
    'bin',
    960,
    false,
    false,
    true,
    false
  ),
  (
    'a6000000-0000-0000-0000-000000000004',
    'a4000000-0000-0000-0000-000000000001',
    'a5000000-0000-0000-0000-000000000004',
    'LON-DESPATCH',
    'staging',
    900,
    false,
    false,
    false,
    false
  ),
  (
    'a6000000-0000-0000-0000-000000000005',
    'a4000000-0000-0000-0000-000000000001',
    'a5000000-0000-0000-0000-000000000001',
    'LON-TRANSIT',
    'staging',
    2,
    false,
    false,
    false,
    true
  ),
  (
    'a6000000-0000-0000-0000-000000000006',
    'a4000000-0000-0000-0000-000000000002',
    'a5000000-0000-0000-0000-000000000006',
    'MAN-DOCK',
    'dock',
    1,
    false,
    true,
    false,
    false
  ),
  (
    'a6000000-0000-0000-0000-000000000007',
    'a4000000-0000-0000-0000-000000000002',
    'a5000000-0000-0000-0000-000000000009',
    'MAN-QA',
    'bin',
    960,
    false,
    false,
    true,
    false
  ),
  (
    'a6000000-0000-0000-0000-000000000008',
    'a4000000-0000-0000-0000-000000000002',
    'a5000000-0000-0000-0000-000000000008',
    'MAN-DESPATCH',
    'staging',
    900,
    false,
    false,
    false,
    false
  ),
  (
    'a6000000-0000-0000-0000-000000000009',
    'a4000000-0000-0000-0000-000000000002',
    'a5000000-0000-0000-0000-000000000006',
    'MAN-TRANSIT',
    'staging',
    2,
    false,
    false,
    false,
    true
  ),
  (
    'a6000000-0000-0000-0000-000000000010',
    'a4000000-0000-0000-0000-000000000003',
    'a5000000-0000-0000-0000-000000000010',
    'ROT-DOCK',
    'dock',
    1,
    false,
    true,
    false,
    false
  ),
  (
    'a6000000-0000-0000-0000-000000000011',
    'a4000000-0000-0000-0000-000000000003',
    'a5000000-0000-0000-0000-000000000012',
    'ROT-DESPATCH',
    'staging',
    900,
    false,
    false,
    false,
    false
  ),
  (
    'a6000000-0000-0000-0000-000000000012',
    'a4000000-0000-0000-0000-000000000003',
    'a5000000-0000-0000-0000-000000000010',
    'ROT-TRANSIT',
    'staging',
    2,
    false,
    false,
    false,
    true
  );

-- Rack bins, generated rather than typed. Three aisles by four racks
-- by two levels by two positions in every storage zone, with pick
-- sequences already in walking order.
insert into
  inventory.locations (
    warehouse_id,
    zone_id,
    code,
    barcode,
    location_type,
    aisle,
    rack,
    level,
    position,
    pick_sequence,
    max_weight_kg
  )
select
  z.warehouse_id,
  z.id,
  w.code || '-' || z.code || '-' || a.aisle || lpad(r.rack::text, 2, '0') || '-' || l.level || p.position,
  -- The zone code is in the barcode because London has two storage
  -- zones, and A01-A1 exists in both of them.
  'BIN' || w.code || z.code || a.aisle || lpad(r.rack::text, 2, '0') || l.level || p.position,
  'bin',
  a.aisle,
  lpad(r.rack::text, 2, '0'),
  l.level,
  p.position,
  1000 + (ascii(a.aisle) - 64) * 1000 + r.rack * 100 + (ascii(l.level) - 64) * 10 + p.position::integer,
  case
    when l.level = 'A' then 900
    else 400
  end
from
  inventory.zones z
  join inventory.warehouses w on w.id = z.warehouse_id
  cross join (
    values
      ('A'),
      ('B'),
      ('C')
  ) as a (aisle)
  cross join generate_series(1, 4) as r (rack)
  cross join (
    values
      ('A'),
      ('B')
  ) as l (level)
  cross join (
    values
      ('1'),
      ('2')
  ) as p (position)
where
  z.zone_type = 'storage'
  -- The chilled zone is smaller: one aisle only.
  and (
    z.code <> 'CHL'
    or a.aisle = 'A'
  );

----------------------------------------------------------------
-- Suppliers
----------------------------------------------------------------
insert into
  inventory.suppliers (
    id,
    code,
    name,
    status,
    email,
    phone,
    website,
    contact_name,
    address,
    country,
    currency,
    payment_terms_days,
    default_lead_time_days,
    minimum_order_value,
    quality_rating
  )
values
  (
    'a7000000-0000-0000-0000-000000000001',
    'SUP-1001',
    'Northforge Metals',
    'active',
    'sales@northforge.co.uk',
    '+44 114 496 3101',
    'https://northforge.co.uk',
    'Iain Brodie',
    'Sheffield',
    'GB',
    'USD',
    30,
    21,
    2500,
    4.5
  ),
  (
    'a7000000-0000-0000-0000-000000000002',
    'SUP-1002',
    'Polymer Dynamics BV',
    'active',
    'orders@polymerdynamics.nl',
    '+31 10 271 3102',
    'https://polymerdynamics.nl',
    'Sanne de Vries',
    'Rotterdam',
    'NL',
    'USD',
    45,
    28,
    4000,
    4.0
  ),
  (
    'a7000000-0000-0000-0000-000000000003',
    'SUP-1003',
    'Kestrel Electronics',
    'active',
    'ap@kestrelelectronics.com',
    '+1 408 555 3103',
    'https://kestrelelectronics.com',
    'Priya Nadar',
    'San Jose',
    'US',
    'USD',
    30,
    35,
    1500,
    4.5
  ),
  (
    'a7000000-0000-0000-0000-000000000004',
    'SUP-1004',
    'Halcyon Chemicals',
    'active',
    'sales@halcyonchem.co.uk',
    '+44 151 496 3104',
    'https://halcyonchem.co.uk',
    'Tom Whitlock',
    'Runcorn',
    'GB',
    'USD',
    30,
    14,
    1200,
    3.5
  ),
  (
    'a7000000-0000-0000-0000-000000000005',
    'SUP-1005',
    'Meridian Cables',
    'active',
    'orders@meridiancables.de',
    '+49 211 3105',
    'https://meridiancables.de',
    'Jonas Krause',
    'Dusseldorf',
    'DE',
    'USD',
    30,
    18,
    900,
    4.0
  ),
  (
    'a7000000-0000-0000-0000-000000000006',
    'SUP-1006',
    'Ironwood Fixings',
    'active',
    'sales@ironwoodfixings.co.uk',
    '+44 121 496 3106',
    'https://ironwoodfixings.co.uk',
    'Sara Malik',
    'Birmingham',
    'GB',
    'USD',
    14,
    7,
    350,
    4.5
  ),
  (
    'a7000000-0000-0000-0000-000000000007',
    'SUP-1007',
    'Cascade Packaging',
    'active',
    'cs@cascadepack.com',
    '+1 503 555 3107',
    'https://cascadepack.com',
    'Bree Lawson',
    'Portland',
    'US',
    'USD',
    30,
    21,
    800,
    4.0
  ),
  (
    'a7000000-0000-0000-0000-000000000008',
    'SUP-1008',
    'Baltic Bearings OU',
    'active',
    'sales@balticbearings.ee',
    '+372 660 3108',
    'https://balticbearings.ee',
    'Kadri Tamm',
    'Tallinn',
    'EE',
    'USD',
    45,
    30,
    1100,
    3.5
  ),
  (
    'a7000000-0000-0000-0000-000000000009',
    'SUP-1009',
    'Vantage Instruments',
    'active',
    'orders@vantageinstruments.com',
    '+1 617 555 3109',
    'https://vantageinstruments.com',
    'Alan Reyes',
    'Boston',
    'US',
    'USD',
    30,
    42,
    5000,
    5.0
  ),
  (
    'a7000000-0000-0000-0000-000000000010',
    'SUP-1010',
    'Redline Adhesives',
    'on_hold',
    'sales@redlineadhesives.co.uk',
    '+44 1706 496 3110',
    'https://redlineadhesives.co.uk',
    'Gemma Foy',
    'Rochdale',
    'GB',
    'USD',
    30,
    14,
    600,
    2.5
  ),
  (
    'a7000000-0000-0000-0000-000000000011',
    'SUP-1011',
    'Aurora Enclosures',
    'active',
    'sales@auroraenclosures.pl',
    '+48 22 3111',
    'https://auroraenclosures.pl',
    'Marek Zielinski',
    'Warsaw',
    'PL',
    'USD',
    45,
    35,
    1800,
    4.0
  ),
  (
    'a7000000-0000-0000-0000-000000000012',
    'SUP-1012',
    'Summit Safety Supplies',
    'active',
    'orders@summitsafety.co.uk',
    '+44 191 496 3112',
    'https://summitsafety.co.uk',
    'Rob Aitken',
    'Newcastle',
    'GB',
    'USD',
    14,
    7,
    250,
    4.5
  ),
  (
    'a7000000-0000-0000-0000-000000000013',
    'SUP-1013',
    'Delta Tooling',
    'active',
    'sales@deltatooling.com',
    '+1 313 555 3113',
    'https://deltatooling.com',
    'Nina Okafor',
    'Detroit',
    'US',
    'USD',
    30,
    28,
    2200,
    4.0
  ),
  (
    'a7000000-0000-0000-0000-000000000014',
    'SUP-1014',
    'Orchard Labels',
    'inactive',
    'hello@orchardlabels.co.uk',
    '+44 1865 496 3114',
    'https://orchardlabels.co.uk',
    'Chris Vale',
    'Oxford',
    'GB',
    'USD',
    30,
    10,
    150,
    3.0
  );

----------------------------------------------------------------
-- Settings (singleton)
----------------------------------------------------------------
insert into
  inventory.inventory_settings (
    company_name,
    base_currency,
    default_warehouse_id,
    default_valuation_method,
    allow_negative_stock,
    enforce_fefo,
    adjustment_approval_threshold,
    expiry_warning_days,
    count_frequency_a_days,
    count_frequency_b_days,
    count_frequency_c_days,
    timezone
  )
values
  (
    'Supasheet Industrial Ltd',
    'USD',
    'a4000000-0000-0000-0000-000000000001',
    'average',
    false,
    true,
    750,
    45,
    30,
    90,
    180,
    'Europe/London'
  );

----------------------------------------------------------------
-- Items
--
-- Ninety-six lines across untracked, lot-tracked and serial-tracked
-- handling, because `tracking` is the column that decides what the
-- ledger will accept and a dataset that only exercised one value
-- would not test the module at all.
--
-- Every stock and cost column is left at its default. on_hand,
-- available, average_cost and the reorder flag are all put there by
-- movements further down.
----------------------------------------------------------------
insert into
  inventory.items (
    id,
    sku,
    name,
    category_id,
    uom_id,
    status,
    tracking,
    barcode,
    abc_class,
    standard_cost,
    reorder_point,
    reorder_quantity,
    max_stock,
    lead_time_days,
    shelf_life_days,
    requires_quarantine,
    hazard_class,
    weight_kg,
    volume_m3
  )
values
  (
    'a3000000-0000-0000-0000-000000000001',
    'SKU-1001',
    'Stainless sheet 1.0mm 1250x2500',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'none',
    '5011000137',
    'b',
    4.578,
    400,
    1200,
    3600,
    28,
    null,
    false,
    null,
    0.18,
    0.0011
  ),
  (
    'a3000000-0000-0000-0000-000000000002',
    'SKU-1002',
    'Stainless sheet 2.0mm 1250x2500',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'none',
    '5011000274',
    'c',
    3.612,
    400,
    1200,
    3600,
    35,
    null,
    false,
    null,
    0.31,
    0.0018
  ),
  (
    'a3000000-0000-0000-0000-000000000003',
    'SKU-1003',
    'Aluminium sheet 1.5mm',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'none',
    '5011000411',
    'a',
    5.166,
    400,
    1200,
    3600,
    14,
    null,
    false,
    null,
    0.44,
    0.0025
  ),
  (
    'a3000000-0000-0000-0000-000000000004',
    'SKU-1004',
    'Mild steel bar 12mm',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'none',
    '5011000548',
    'b',
    4.2,
    400,
    1200,
    3600,
    18,
    null,
    false,
    null,
    0.57,
    0.0032
  ),
  (
    'a3000000-0000-0000-0000-000000000005',
    'SKU-1005',
    'Aluminium extrusion 40x40',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'none',
    '5011000685',
    'c',
    3.234,
    400,
    1200,
    3600,
    7,
    null,
    false,
    null,
    0.7,
    0.0039
  ),
  (
    'a3000000-0000-0000-0000-000000000006',
    'SKU-1006',
    'Brass rod 8mm',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'none',
    '5011000822',
    'a',
    4.788,
    400,
    1200,
    3600,
    30,
    null,
    false,
    null,
    0.83,
    0.0046
  ),
  (
    'a3000000-0000-0000-0000-000000000007',
    'SKU-1007',
    'Copper busbar 20x3',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'none',
    '5011000959',
    'b',
    3.822,
    400,
    1200,
    3600,
    21,
    null,
    false,
    null,
    0.96,
    0.0053
  ),
  (
    'a3000000-0000-0000-0000-000000000008',
    'SKU-1008',
    'ABS granulate natural',
    'a2000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'lot',
    '5011001096',
    'c',
    3.968,
    300,
    900,
    2700,
    28,
    540,
    false,
    null,
    1.09,
    0.006
  ),
  (
    'a3000000-0000-0000-0000-000000000009',
    'SKU-1009',
    'Polycarbonate granulate clear',
    'a2000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'lot',
    '5011001233',
    'a',
    3.255,
    300,
    900,
    2700,
    35,
    540,
    false,
    null,
    1.22,
    0.0067
  ),
  (
    'a3000000-0000-0000-0000-000000000010',
    'SKU-1010',
    'Nylon 6 granulate',
    'a2000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'lot',
    '5011001370',
    'b',
    2.542,
    300,
    900,
    2700,
    14,
    540,
    true,
    null,
    1.35,
    0.0074
  ),
  (
    'a3000000-0000-0000-0000-000000000011',
    'SKU-1011',
    'TPE granulate shore 60',
    'a2000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'lot',
    '5011001507',
    'c',
    3.689,
    300,
    900,
    2700,
    18,
    540,
    false,
    null,
    1.48,
    0.0081
  ),
  (
    'a3000000-0000-0000-0000-000000000012',
    'SKU-1012',
    'PP granulate black',
    'a2000000-0000-0000-0000-000000000003',
    'a1000000-0000-0000-0000-000000000005',
    'active',
    'lot',
    '5011001644',
    'a',
    2.976,
    300,
    900,
    2700,
    7,
    540,
    false,
    null,
    1.61,
    0.0088
  ),
  (
    'a3000000-0000-0000-0000-000000000013',
    'SKU-1013',
    'Isopropyl alcohol 5L',
    'a2000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000007',
    'active',
    'lot',
    '5011001781',
    'b',
    8.322,
    60,
    200,
    600,
    30,
    365,
    false,
    'Flammable',
    1.74,
    0.0005
  ),
  (
    'a3000000-0000-0000-0000-000000000014',
    'SKU-1014',
    'Cleaning solvent 5L',
    'a2000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000007',
    'active',
    'lot',
    '5011001918',
    'c',
    12.54,
    60,
    200,
    600,
    21,
    365,
    false,
    'Flammable',
    1.87,
    0.0012
  ),
  (
    'a3000000-0000-0000-0000-000000000015',
    'SKU-1015',
    'Epoxy resin part A 5L',
    'a2000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000007',
    'active',
    'lot',
    '5011002055',
    'a',
    9.918,
    60,
    200,
    600,
    28,
    365,
    true,
    'Flammable',
    2.0,
    0.0019
  ),
  (
    'a3000000-0000-0000-0000-000000000016',
    'SKU-1016',
    'Epoxy hardener part B 2.5L',
    'a2000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000007',
    'active',
    'lot',
    '5011002192',
    'b',
    14.136,
    60,
    200,
    600,
    35,
    365,
    false,
    'Flammable',
    2.13,
    0.0026
  ),
  (
    'a3000000-0000-0000-0000-000000000017',
    'SKU-1017',
    'Conformal coating 1L',
    'a2000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000007',
    'active',
    'lot',
    '5011002329',
    'c',
    11.514,
    60,
    200,
    600,
    14,
    365,
    false,
    'Flammable',
    2.26,
    0.0033
  ),
  (
    'a3000000-0000-0000-0000-000000000018',
    'SKU-1018',
    'Degreaser concentrate 5L',
    'a2000000-0000-0000-0000-000000000004',
    'a1000000-0000-0000-0000-000000000007',
    'active',
    'lot',
    '5011002466',
    'a',
    8.892,
    60,
    200,
    600,
    18,
    365,
    false,
    'Flammable',
    2.39,
    0.004
  ),
  (
    'a3000000-0000-0000-0000-000000000019',
    'SKU-1019',
    'Sensor mainboard rev C',
    'a2000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'lot',
    '5011002603',
    'b',
    21.5625,
    120,
    400,
    1200,
    7,
    730,
    false,
    null,
    2.52,
    0.0047
  ),
  (
    'a3000000-0000-0000-0000-000000000020',
    'SKU-1020',
    'Gateway mainboard rev B',
    'a2000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'lot',
    '5011002740',
    'c',
    17.25,
    120,
    400,
    1200,
    30,
    730,
    true,
    null,
    2.65,
    0.0054
  ),
  (
    'a3000000-0000-0000-0000-000000000021',
    'SKU-1021',
    'Power board 24V',
    'a2000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'lot',
    '5011002877',
    'a',
    24.1875,
    120,
    400,
    1200,
    21,
    730,
    false,
    null,
    2.78,
    0.0061
  ),
  (
    'a3000000-0000-0000-0000-000000000022',
    'SKU-1022',
    'Interface board RS485',
    'a2000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'lot',
    '5011003014',
    'b',
    19.875,
    120,
    400,
    1200,
    28,
    730,
    false,
    null,
    2.91,
    0.0068
  ),
  (
    'a3000000-0000-0000-0000-000000000023',
    'SKU-1023',
    'Display driver board',
    'a2000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'lot',
    '5011003151',
    'c',
    15.5625,
    120,
    400,
    1200,
    35,
    730,
    false,
    null,
    3.04,
    0.0075
  ),
  (
    'a3000000-0000-0000-0000-000000000024',
    'SKU-1024',
    'Bare PCB 4-layer 100x80',
    'a2000000-0000-0000-0000-000000000006',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'lot',
    '5011003288',
    'a',
    22.5,
    120,
    400,
    1200,
    14,
    730,
    false,
    null,
    3.17,
    0.0082
  ),
  (
    'a3000000-0000-0000-0000-000000000025',
    'SKU-1025',
    'Cable 2-core 0.75mm screened',
    'a2000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000009',
    'active',
    'none',
    '5011003425',
    'b',
    1.3095,
    800,
    2500,
    7500,
    18,
    null,
    false,
    null,
    3.3,
    0.0089
  ),
  (
    'a3000000-0000-0000-0000-000000000026',
    'SKU-1026',
    'Cable 4-core 0.5mm',
    'a2000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000009',
    'active',
    'none',
    '5011003562',
    'c',
    0.999,
    800,
    2500,
    7500,
    7,
    null,
    false,
    null,
    3.43,
    0.0006
  ),
  (
    'a3000000-0000-0000-0000-000000000027',
    'SKU-1027',
    'Cable 8-core ribbon',
    'a2000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000009',
    'active',
    'none',
    '5011003699',
    'a',
    1.4985,
    800,
    2500,
    7500,
    30,
    null,
    false,
    null,
    3.56,
    0.0013
  ),
  (
    'a3000000-0000-0000-0000-000000000028',
    'SKU-1028',
    'Silicone cable 1.5mm HT',
    'a2000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000009',
    'active',
    'none',
    '5011003836',
    'b',
    1.188,
    800,
    2500,
    7500,
    21,
    null,
    false,
    null,
    3.69,
    0.002
  ),
  (
    'a3000000-0000-0000-0000-000000000029',
    'SKU-1029',
    'Cat6 patch cable 2m',
    'a2000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000009',
    'discontinued',
    'none',
    '5011003973',
    'c',
    1.6875,
    800,
    2500,
    7500,
    28,
    null,
    false,
    null,
    3.82,
    0.0027
  ),
  (
    'a3000000-0000-0000-0000-000000000030',
    'SKU-1030',
    'M12 connector 4-pin male',
    'a2000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011004110',
    'a',
    2.958,
    500,
    1500,
    4500,
    35,
    null,
    false,
    null,
    3.95,
    0.0034
  ),
  (
    'a3000000-0000-0000-0000-000000000031',
    'SKU-1031',
    'M12 connector 4-pin female',
    'a2000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011004247',
    'b',
    2.291,
    500,
    1500,
    4500,
    14,
    null,
    false,
    null,
    0.08,
    0.0041
  ),
  (
    'a3000000-0000-0000-0000-000000000032',
    'SKU-1032',
    'Cable gland M16',
    'a2000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011004384',
    'c',
    3.364,
    500,
    1500,
    4500,
    18,
    null,
    false,
    null,
    0.21,
    0.0048
  ),
  (
    'a3000000-0000-0000-0000-000000000033',
    'SKU-1033',
    'Cable gland M20',
    'a2000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011004521',
    'a',
    2.697,
    500,
    1500,
    4500,
    7,
    null,
    false,
    null,
    0.34,
    0.0055
  ),
  (
    'a3000000-0000-0000-0000-000000000034',
    'SKU-1034',
    'DIN rail terminal 2.5mm',
    'a2000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011004658',
    'b',
    3.77,
    500,
    1500,
    4500,
    30,
    null,
    false,
    null,
    0.47,
    0.0062
  ),
  (
    'a3000000-0000-0000-0000-000000000035',
    'SKU-1035',
    'Ferrule kit assorted',
    'a2000000-0000-0000-0000-000000000007',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011004795',
    'c',
    3.103,
    500,
    1500,
    4500,
    21,
    null,
    false,
    null,
    0.6,
    0.0069
  ),
  (
    'a3000000-0000-0000-0000-000000000036',
    'SKU-1036',
    'Temperature sensor TS-200',
    'a2000000-0000-0000-0000-000000000009',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'serial',
    '5011004932',
    'a',
    242.76,
    12,
    40,
    120,
    28,
    null,
    false,
    null,
    0.73,
    0.0076
  ),
  (
    'a3000000-0000-0000-0000-000000000037',
    'SKU-1037',
    'Pressure sensor PS-450',
    'a2000000-0000-0000-0000-000000000009',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'serial',
    '5011005069',
    'b',
    349.69,
    12,
    40,
    120,
    35,
    null,
    false,
    null,
    0.86,
    0.0083
  ),
  (
    'a3000000-0000-0000-0000-000000000038',
    'SKU-1038',
    'Vibration sensor VS-110',
    'a2000000-0000-0000-0000-000000000009',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'serial',
    '5011005206',
    'c',
    283.22,
    12,
    40,
    120,
    14,
    null,
    false,
    null,
    0.99,
    0.009
  ),
  (
    'a3000000-0000-0000-0000-000000000039',
    'SKU-1039',
    'Flow sensor FS-320',
    'a2000000-0000-0000-0000-000000000009',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'serial',
    '5011005343',
    'a',
    216.75,
    12,
    40,
    120,
    18,
    null,
    false,
    null,
    1.12,
    0.0007
  ),
  (
    'a3000000-0000-0000-0000-000000000040',
    'SKU-1040',
    'Edge controller EC-900',
    'a2000000-0000-0000-0000-000000000010',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'serial',
    '5011005480',
    'b',
    685.44,
    8,
    25,
    75,
    7,
    null,
    true,
    null,
    1.25,
    0.0014
  ),
  (
    'a3000000-0000-0000-0000-000000000041',
    'SKU-1041',
    'Gateway unit GW-500',
    'a2000000-0000-0000-0000-000000000010',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'serial',
    '5011005617',
    'c',
    544.68,
    8,
    25,
    75,
    30,
    null,
    false,
    null,
    1.38,
    0.0021
  ),
  (
    'a3000000-0000-0000-0000-000000000042',
    'SKU-1042',
    'PLC module PM-310',
    'a2000000-0000-0000-0000-000000000010',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'serial',
    '5011005754',
    'a',
    771.12,
    8,
    25,
    75,
    21,
    null,
    false,
    null,
    1.51,
    0.0028
  ),
  (
    'a3000000-0000-0000-0000-000000000043',
    'SKU-1043',
    'Sensor housing assembly',
    'a2000000-0000-0000-0000-000000000011',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011005891',
    'b',
    47.895,
    60,
    200,
    600,
    28,
    null,
    false,
    null,
    1.64,
    0.0035
  ),
  (
    'a3000000-0000-0000-0000-000000000044',
    'SKU-1044',
    'Controller backplate',
    'a2000000-0000-0000-0000-000000000011',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011006028',
    'c',
    37.2,
    60,
    200,
    600,
    35,
    null,
    false,
    null,
    1.77,
    0.0042
  ),
  (
    'a3000000-0000-0000-0000-000000000045',
    'SKU-1045',
    'Mounting bracket kit',
    'a2000000-0000-0000-0000-000000000011',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011006165',
    'a',
    54.405,
    60,
    200,
    600,
    14,
    null,
    false,
    null,
    1.9,
    0.0049
  ),
  (
    'a3000000-0000-0000-0000-000000000046',
    'SKU-1046',
    'Terminal block assembly',
    'a2000000-0000-0000-0000-000000000011',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011006302',
    'b',
    43.71,
    60,
    200,
    600,
    18,
    null,
    false,
    null,
    2.03,
    0.0056
  ),
  (
    'a3000000-0000-0000-0000-000000000047',
    'SKU-1047',
    'Cable loom 600mm',
    'a2000000-0000-0000-0000-000000000011',
    'a1000000-0000-0000-0000-000000000001',
    'draft',
    'none',
    '5011006439',
    'c',
    60.915,
    60,
    200,
    600,
    7,
    null,
    false,
    null,
    2.16,
    0.0063
  ),
  (
    'a3000000-0000-0000-0000-000000000048',
    'SKU-1048',
    'Antenna mount assembly',
    'a2000000-0000-0000-0000-000000000011',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011006576',
    'a',
    50.22,
    60,
    200,
    600,
    30,
    null,
    false,
    null,
    2.29,
    0.007
  ),
  (
    'a3000000-0000-0000-0000-000000000049',
    'SKU-1049',
    'Carton 300x200x150 single wall',
    'a2000000-0000-0000-0000-000000000012',
    'a1000000-0000-0000-0000-000000000003',
    'active',
    'none',
    '5011006713',
    'b',
    0.527,
    1200,
    4000,
    12000,
    21,
    null,
    false,
    null,
    2.42,
    0.0077
  ),
  (
    'a3000000-0000-0000-0000-000000000050',
    'SKU-1050',
    'Carton 400x300x200 double wall',
    'a2000000-0000-0000-0000-000000000012',
    'a1000000-0000-0000-0000-000000000003',
    'active',
    'none',
    '5011006850',
    'c',
    0.7564,
    1200,
    4000,
    12000,
    28,
    null,
    false,
    null,
    2.55,
    0.0084
  ),
  (
    'a3000000-0000-0000-0000-000000000051',
    'SKU-1051',
    'Bubble wrap roll 500mm',
    'a2000000-0000-0000-0000-000000000012',
    'a1000000-0000-0000-0000-000000000003',
    'active',
    'none',
    '5011006987',
    'a',
    0.6138,
    1200,
    4000,
    12000,
    35,
    null,
    false,
    null,
    2.68,
    0.0091
  ),
  (
    'a3000000-0000-0000-0000-000000000052',
    'SKU-1052',
    'Void fill paper roll',
    'a2000000-0000-0000-0000-000000000012',
    'a1000000-0000-0000-0000-000000000003',
    'active',
    'none',
    '5011007124',
    'b',
    0.4712,
    1200,
    4000,
    12000,
    14,
    null,
    false,
    null,
    2.81,
    0.0008
  ),
  (
    'a3000000-0000-0000-0000-000000000053',
    'SKU-1053',
    'Pallet wrap 500mm 20mu',
    'a2000000-0000-0000-0000-000000000012',
    'a1000000-0000-0000-0000-000000000003',
    'active',
    'none',
    '5011007261',
    'c',
    0.7006,
    1200,
    4000,
    12000,
    18,
    null,
    false,
    null,
    2.94,
    0.0015
  ),
  (
    'a3000000-0000-0000-0000-000000000054',
    'SKU-1054',
    'Fragile tape 48mm',
    'a2000000-0000-0000-0000-000000000012',
    'a1000000-0000-0000-0000-000000000003',
    'active',
    'none',
    '5011007398',
    'a',
    0.558,
    1200,
    4000,
    12000,
    7,
    null,
    false,
    null,
    3.07,
    0.0022
  ),
  (
    'a3000000-0000-0000-0000-000000000055',
    'SKU-1055',
    'Shipping label 100x150',
    'a2000000-0000-0000-0000-000000000012',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011007535',
    'b',
    0.1143,
    3000,
    10000,
    30000,
    30,
    null,
    false,
    null,
    3.2,
    0.0029
  ),
  (
    'a3000000-0000-0000-0000-000000000056',
    'SKU-1056',
    'Product label 40x20',
    'a2000000-0000-0000-0000-000000000012',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011007672',
    'c',
    0.0936,
    3000,
    10000,
    30000,
    21,
    null,
    false,
    null,
    3.33,
    0.0036
  ),
  (
    'a3000000-0000-0000-0000-000000000057',
    'SKU-1057',
    'Serial label 25x12',
    'a2000000-0000-0000-0000-000000000012',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011007809',
    'a',
    0.0729,
    3000,
    10000,
    30000,
    28,
    null,
    false,
    null,
    3.46,
    0.0043
  ),
  (
    'a3000000-0000-0000-0000-000000000058',
    'SKU-1058',
    'Hazard label class 3',
    'a2000000-0000-0000-0000-000000000012',
    'a1000000-0000-0000-0000-000000000001',
    'discontinued',
    'none',
    '5011007946',
    'b',
    0.1062,
    3000,
    10000,
    30000,
    35,
    null,
    false,
    null,
    3.59,
    0.005
  ),
  (
    'a3000000-0000-0000-0000-000000000059',
    'SKU-1059',
    'Fuse 10A ceramic',
    'a2000000-0000-0000-0000-000000000014',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011008083',
    'c',
    7.41,
    80,
    250,
    750,
    14,
    null,
    false,
    null,
    3.72,
    0.0057
  ),
  (
    'a3000000-0000-0000-0000-000000000060',
    'SKU-1060',
    'Relay 24V DPDT',
    'a2000000-0000-0000-0000-000000000014',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011008220',
    'a',
    5.616,
    80,
    250,
    750,
    18,
    null,
    false,
    null,
    3.85,
    0.0064
  ),
  (
    'a3000000-0000-0000-0000-000000000061',
    'SKU-1061',
    'Contactor 25A',
    'a2000000-0000-0000-0000-000000000014',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011008357',
    'b',
    8.502,
    80,
    250,
    750,
    7,
    null,
    false,
    null,
    3.98,
    0.0071
  ),
  (
    'a3000000-0000-0000-0000-000000000062',
    'SKU-1062',
    'Motor drive 0.75kW',
    'a2000000-0000-0000-0000-000000000014',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011008494',
    'c',
    6.708,
    80,
    250,
    750,
    30,
    null,
    false,
    null,
    0.11,
    0.0078
  ),
  (
    'a3000000-0000-0000-0000-000000000063',
    'SKU-1063',
    'MCB 16A type C',
    'a2000000-0000-0000-0000-000000000014',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011008631',
    'a',
    9.594,
    80,
    250,
    750,
    21,
    null,
    false,
    null,
    0.24,
    0.0085
  ),
  (
    'a3000000-0000-0000-0000-000000000064',
    'SKU-1064',
    'Surge arrester 24V',
    'a2000000-0000-0000-0000-000000000014',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011008768',
    'b',
    7.8,
    80,
    250,
    750,
    28,
    null,
    false,
    null,
    0.37,
    0.0092
  ),
  (
    'a3000000-0000-0000-0000-000000000065',
    'SKU-1065',
    'Deep groove bearing 6204',
    'a2000000-0000-0000-0000-000000000015',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011008905',
    'c',
    9.548,
    60,
    200,
    600,
    35,
    null,
    false,
    null,
    0.5,
    0.0009
  ),
  (
    'a3000000-0000-0000-0000-000000000066',
    'SKU-1066',
    'Deep groove bearing 6205',
    'a2000000-0000-0000-0000-000000000015',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011009042',
    'a',
    14.136,
    60,
    200,
    600,
    14,
    null,
    false,
    null,
    0.63,
    0.0016
  ),
  (
    'a3000000-0000-0000-0000-000000000067',
    'SKU-1067',
    'Shaft seal 25x40x7',
    'a2000000-0000-0000-0000-000000000015',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011009179',
    'b',
    11.284,
    60,
    200,
    600,
    18,
    null,
    false,
    null,
    0.76,
    0.0023
  ),
  (
    'a3000000-0000-0000-0000-000000000068',
    'SKU-1068',
    'Timing belt HTD 5M-450',
    'a2000000-0000-0000-0000-000000000015',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011009316',
    'c',
    15.872,
    60,
    200,
    600,
    7,
    null,
    false,
    null,
    0.89,
    0.003
  ),
  (
    'a3000000-0000-0000-0000-000000000069',
    'SKU-1069',
    'V-belt SPZ 1000',
    'a2000000-0000-0000-0000-000000000015',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011009453',
    'a',
    13.02,
    60,
    200,
    600,
    30,
    null,
    false,
    null,
    1.02,
    0.0037
  ),
  (
    'a3000000-0000-0000-0000-000000000070',
    'SKU-1070',
    'Linear rail block 15mm',
    'a2000000-0000-0000-0000-000000000015',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011009590',
    'b',
    10.168,
    60,
    200,
    600,
    21,
    null,
    false,
    null,
    1.15,
    0.0044
  ),
  (
    'a3000000-0000-0000-0000-000000000071',
    'SKU-1071',
    'Nitrile gloves box 100',
    'a2000000-0000-0000-0000-000000000016',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011009727',
    'c',
    4.1055,
    250,
    800,
    2400,
    28,
    null,
    false,
    null,
    1.28,
    0.0051
  ),
  (
    'a3000000-0000-0000-0000-000000000072',
    'SKU-1072',
    'Lint-free wipes pack 200',
    'a2000000-0000-0000-0000-000000000016',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011009864',
    'a',
    3.312,
    250,
    800,
    2400,
    35,
    null,
    false,
    null,
    1.41,
    0.0058
  ),
  (
    'a3000000-0000-0000-0000-000000000073',
    'SKU-1073',
    'Anti-static bag 200x300',
    'a2000000-0000-0000-0000-000000000016',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011010001',
    'b',
    2.5185,
    250,
    800,
    2400,
    14,
    null,
    false,
    null,
    1.54,
    0.0065
  ),
  (
    'a3000000-0000-0000-0000-000000000074',
    'SKU-1074',
    'Desiccant sachet 10g',
    'a2000000-0000-0000-0000-000000000016',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011010138',
    'c',
    3.795,
    250,
    800,
    2400,
    18,
    null,
    false,
    null,
    1.67,
    0.0072
  ),
  (
    'a3000000-0000-0000-0000-000000000075',
    'SKU-1075',
    'Thread lock 50ml',
    'a2000000-0000-0000-0000-000000000016',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011010275',
    'a',
    3.0015,
    250,
    800,
    2400,
    7,
    null,
    false,
    null,
    1.8,
    0.0079
  ),
  (
    'a3000000-0000-0000-0000-000000000076',
    'SKU-1076',
    'Solder wire 0.7mm 250g',
    'a2000000-0000-0000-0000-000000000016',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011010412',
    'b',
    4.278,
    250,
    800,
    2400,
    30,
    null,
    false,
    null,
    1.93,
    0.0086
  ),
  (
    'a3000000-0000-0000-0000-000000000077',
    'SKU-1077',
    'Torque screwdriver 1-6Nm',
    'a2000000-0000-0000-0000-000000000017',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011010549',
    'c',
    64.64,
    10,
    25,
    75,
    21,
    null,
    false,
    null,
    2.06,
    0.0093
  ),
  (
    'a3000000-0000-0000-0000-000000000078',
    'SKU-1078',
    'Crimp tool M12',
    'a2000000-0000-0000-0000-000000000017',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011010686',
    'a',
    49.92,
    10,
    25,
    75,
    28,
    null,
    false,
    null,
    2.19,
    0.001
  ),
  (
    'a3000000-0000-0000-0000-000000000079',
    'SKU-1079',
    'Digital multimeter',
    'a2000000-0000-0000-0000-000000000017',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011010823',
    'b',
    73.6,
    10,
    25,
    75,
    35,
    null,
    false,
    null,
    2.32,
    0.0017
  ),
  (
    'a3000000-0000-0000-0000-000000000080',
    'SKU-1080',
    'Heat gun 2000W',
    'a2000000-0000-0000-0000-000000000017',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011010960',
    'c',
    58.88,
    10,
    25,
    75,
    14,
    null,
    false,
    null,
    2.45,
    0.0024
  ),
  (
    'a3000000-0000-0000-0000-000000000081',
    'SKU-1081',
    'Label printer handheld',
    'a2000000-0000-0000-0000-000000000017',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011011097',
    'a',
    82.56,
    10,
    25,
    75,
    18,
    null,
    false,
    null,
    2.58,
    0.0031
  ),
  (
    'a3000000-0000-0000-0000-000000000082',
    'SKU-1082',
    'Barcode scanner corded',
    'a2000000-0000-0000-0000-000000000017',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011011234',
    'b',
    67.84,
    10,
    25,
    75,
    7,
    null,
    false,
    null,
    2.71,
    0.0038
  ),
  (
    'a3000000-0000-0000-0000-000000000083',
    'SKU-1083',
    'Service kit sensor range',
    'a2000000-0000-0000-0000-000000000013',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011011371',
    'c',
    18.509,
    40,
    120,
    360,
    30,
    null,
    false,
    null,
    2.84,
    0.0045
  ),
  (
    'a3000000-0000-0000-0000-000000000084',
    'SKU-1084',
    'Service kit controller range',
    'a2000000-0000-0000-0000-000000000013',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011011508',
    'a',
    26.76,
    40,
    120,
    360,
    21,
    null,
    false,
    null,
    2.97,
    0.0052
  ),
  (
    'a3000000-0000-0000-0000-000000000085',
    'SKU-1085',
    'Calibration weight set',
    'a2000000-0000-0000-0000-000000000013',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011011645',
    'b',
    21.631,
    40,
    120,
    360,
    28,
    null,
    false,
    null,
    3.1,
    0.0059
  ),
  (
    'a3000000-0000-0000-0000-000000000086',
    'SKU-1086',
    'Spare fan 40mm 24V',
    'a2000000-0000-0000-0000-000000000013',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011011782',
    'c',
    16.502,
    40,
    120,
    360,
    35,
    null,
    false,
    null,
    3.23,
    0.0066
  ),
  (
    'a3000000-0000-0000-0000-000000000087',
    'SKU-1087',
    'Screw M4x12 A2',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'discontinued',
    'none',
    '5011011919',
    'a',
    0.1554,
    5000,
    15000,
    45000,
    14,
    null,
    false,
    null,
    3.36,
    0.0073
  ),
  (
    'a3000000-0000-0000-0000-000000000088',
    'SKU-1088',
    'Screw M5x16 A2',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011012056',
    'b',
    0.1232,
    5000,
    15000,
    45000,
    18,
    null,
    false,
    null,
    3.49,
    0.008
  ),
  (
    'a3000000-0000-0000-0000-000000000089',
    'SKU-1089',
    'Washer M4 A2',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011012193',
    'c',
    0.175,
    5000,
    15000,
    45000,
    7,
    null,
    false,
    null,
    3.62,
    0.0087
  ),
  (
    'a3000000-0000-0000-0000-000000000090',
    'SKU-1090',
    'Nut M5 nyloc A2',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011012330',
    'a',
    0.1428,
    5000,
    15000,
    45000,
    30,
    null,
    false,
    null,
    3.75,
    0.0004
  ),
  (
    'a3000000-0000-0000-0000-000000000091',
    'SKU-1091',
    'Rivet 4x10 alu',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011012467',
    'b',
    0.1106,
    5000,
    15000,
    45000,
    21,
    null,
    false,
    null,
    3.88,
    0.0011
  ),
  (
    'a3000000-0000-0000-0000-000000000092',
    'SKU-1092',
    'Standoff M3x10 brass',
    'a2000000-0000-0000-0000-000000000002',
    'a1000000-0000-0000-0000-000000000001',
    'active',
    'none',
    '5011012604',
    'c',
    0.1624,
    5000,
    15000,
    45000,
    28,
    null,
    false,
    null,
    4.01,
    0.0018
  );

----------------------------------------------------------------
-- Supplier catalogue
--
-- Most items have a second source at a worse price and a longer lead
-- time, so the preferred-supplier flag has something to mean.
----------------------------------------------------------------
insert into
  inventory.supplier_items (
    id,
    supplier_id,
    item_id,
    supplier_sku,
    unit_price,
    lead_time_days,
    minimum_order_quantity,
    pack_size,
    is_preferred
  )
values
  (
    'a8000000-0000-0000-0000-000000000001',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000001',
    'NF-1001',
    4.578,
    28,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000002',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000001',
    'IF-1001',
    5.0358,
    35,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000003',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000002',
    'NF-1002',
    3.612,
    35,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000004',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000002',
    'IF-1002',
    4.0454,
    42,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000005',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000003',
    'NF-1003',
    5.166,
    14,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000006',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000003',
    'IF-1003',
    5.8892,
    21,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000007',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000004',
    'NF-1004',
    4.2,
    18,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000008',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000004',
    'IF-1004',
    4.872,
    25,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000009',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000005',
    'NF-1005',
    3.234,
    7,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000010',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000005',
    'IF-1005',
    3.5251,
    14,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000011',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000006',
    'NF-1006',
    4.788,
    30,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000012',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000006',
    'IF-1006',
    5.3147,
    37,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000013',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000007',
    'NF-1007',
    3.822,
    21,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000014',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000007',
    'IF-1007',
    4.3189,
    28,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000015',
    'a7000000-0000-0000-0000-000000000002',
    'a3000000-0000-0000-0000-000000000008',
    'PD-1008',
    3.968,
    28,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000016',
    'a7000000-0000-0000-0000-000000000002',
    'a3000000-0000-0000-0000-000000000009',
    'PD-1009',
    3.255,
    35,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000017',
    'a7000000-0000-0000-0000-000000000002',
    'a3000000-0000-0000-0000-000000000010',
    'PD-1010',
    2.542,
    14,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000018',
    'a7000000-0000-0000-0000-000000000002',
    'a3000000-0000-0000-0000-000000000011',
    'PD-1011',
    3.689,
    18,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000019',
    'a7000000-0000-0000-0000-000000000002',
    'a3000000-0000-0000-0000-000000000012',
    'PD-1012',
    2.976,
    7,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000020',
    'a7000000-0000-0000-0000-000000000004',
    'a3000000-0000-0000-0000-000000000013',
    'HC-1013',
    8.322,
    30,
    1,
    10,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000021',
    'a7000000-0000-0000-0000-000000000010',
    'a3000000-0000-0000-0000-000000000013',
    'RA-1013',
    9.2374,
    37,
    25,
    5,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000022',
    'a7000000-0000-0000-0000-000000000004',
    'a3000000-0000-0000-0000-000000000014',
    'HC-1014',
    12.54,
    21,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000023',
    'a7000000-0000-0000-0000-000000000010',
    'a3000000-0000-0000-0000-000000000014',
    'RA-1014',
    14.1702,
    28,
    25,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000024',
    'a7000000-0000-0000-0000-000000000004',
    'a3000000-0000-0000-0000-000000000015',
    'HC-1015',
    9.918,
    28,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000025',
    'a7000000-0000-0000-0000-000000000010',
    'a3000000-0000-0000-0000-000000000015',
    'RA-1015',
    11.4057,
    35,
    25,
    25,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000026',
    'a7000000-0000-0000-0000-000000000004',
    'a3000000-0000-0000-0000-000000000016',
    'HC-1016',
    14.136,
    35,
    1,
    10,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000027',
    'a7000000-0000-0000-0000-000000000010',
    'a3000000-0000-0000-0000-000000000016',
    'RA-1016',
    15.2669,
    42,
    25,
    5,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000028',
    'a7000000-0000-0000-0000-000000000004',
    'a3000000-0000-0000-0000-000000000017',
    'HC-1017',
    11.514,
    14,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000029',
    'a7000000-0000-0000-0000-000000000010',
    'a3000000-0000-0000-0000-000000000017',
    'RA-1017',
    12.6654,
    21,
    25,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000030',
    'a7000000-0000-0000-0000-000000000004',
    'a3000000-0000-0000-0000-000000000018',
    'HC-1018',
    8.892,
    18,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000031',
    'a7000000-0000-0000-0000-000000000010',
    'a3000000-0000-0000-0000-000000000018',
    'RA-1018',
    9.959,
    25,
    25,
    25,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000032',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000019',
    'KE-1019',
    21.5625,
    7,
    1,
    10,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000033',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000019',
    'VI-1019',
    24.5813,
    14,
    25,
    5,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000034',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000020',
    'KE-1020',
    17.25,
    30,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000035',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000020',
    'VI-1020',
    20.01,
    37,
    25,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000036',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000021',
    'KE-1021',
    24.1875,
    21,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000037',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000021',
    'VI-1021',
    26.3644,
    28,
    25,
    25,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000038',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000022',
    'KE-1022',
    19.875,
    28,
    1,
    10,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000039',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000022',
    'VI-1022',
    22.0613,
    35,
    25,
    5,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000040',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000023',
    'KE-1023',
    15.5625,
    35,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000041',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000023',
    'VI-1023',
    17.5856,
    42,
    25,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000042',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000024',
    'KE-1024',
    22.5,
    14,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000043',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000024',
    'VI-1024',
    25.875,
    21,
    25,
    25,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000044',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000025',
    'MC-1025',
    1.3095,
    18,
    1,
    10,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000045',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000025',
    'KE-1025',
    1.4143,
    25,
    25,
    5,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000046',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000026',
    'MC-1026',
    0.999,
    7,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000047',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000026',
    'KE-1026',
    1.0989,
    14,
    25,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000048',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000027',
    'MC-1027',
    1.4985,
    30,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000049',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000027',
    'KE-1027',
    1.6783,
    37,
    25,
    25,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000050',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000028',
    'MC-1028',
    1.188,
    21,
    1,
    10,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000051',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000028',
    'KE-1028',
    1.3543,
    28,
    25,
    5,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000052',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000029',
    'MC-1029',
    1.6875,
    28,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000053',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000029',
    'KE-1029',
    1.9575,
    35,
    25,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000054',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000030',
    'MC-1030',
    2.958,
    35,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000055',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000030',
    'KE-1030',
    3.2242,
    42,
    25,
    25,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000056',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000031',
    'MC-1031',
    2.291,
    14,
    1,
    10,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000057',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000031',
    'KE-1031',
    2.543,
    21,
    25,
    5,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000058',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000032',
    'MC-1032',
    3.364,
    18,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000059',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000032',
    'KE-1032',
    3.8013,
    25,
    25,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000060',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000033',
    'MC-1033',
    2.697,
    7,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000061',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000033',
    'KE-1033',
    3.1016,
    14,
    25,
    25,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000062',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000034',
    'MC-1034',
    3.77,
    30,
    1,
    10,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000063',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000034',
    'KE-1034',
    4.0716,
    37,
    25,
    5,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000064',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000035',
    'MC-1035',
    3.103,
    21,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000065',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000035',
    'KE-1035',
    3.4133,
    28,
    25,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000066',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000036',
    'VI-1036',
    242.76,
    28,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000067',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000036',
    'KE-1036',
    271.8912,
    35,
    25,
    25,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000068',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000037',
    'VI-1037',
    349.69,
    35,
    1,
    10,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000069',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000037',
    'KE-1037',
    398.6466,
    42,
    25,
    5,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000070',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000038',
    'VI-1038',
    283.22,
    14,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000071',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000038',
    'KE-1038',
    328.5352,
    21,
    25,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000072',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000039',
    'VI-1039',
    216.75,
    18,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000073',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000039',
    'KE-1039',
    236.2575,
    25,
    25,
    25,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000074',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000040',
    'VI-1040',
    685.44,
    7,
    1,
    10,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000075',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000041',
    'VI-1041',
    544.68,
    30,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000076',
    'a7000000-0000-0000-0000-000000000009',
    'a3000000-0000-0000-0000-000000000042',
    'VI-1042',
    771.12,
    21,
    1,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000077',
    'a7000000-0000-0000-0000-000000000011',
    'a3000000-0000-0000-0000-000000000043',
    'AE-1043',
    47.895,
    28,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000078',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000043',
    'NF-1043',
    54.6003,
    35,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000079',
    'a7000000-0000-0000-0000-000000000011',
    'a3000000-0000-0000-0000-000000000044',
    'AE-1044',
    37.2,
    35,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000080',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000044',
    'NF-1044',
    43.152,
    42,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000081',
    'a7000000-0000-0000-0000-000000000011',
    'a3000000-0000-0000-0000-000000000045',
    'AE-1045',
    54.405,
    14,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000082',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000045',
    'NF-1045',
    59.3015,
    21,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000083',
    'a7000000-0000-0000-0000-000000000011',
    'a3000000-0000-0000-0000-000000000046',
    'AE-1046',
    43.71,
    18,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000084',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000046',
    'NF-1046',
    48.5181,
    25,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000085',
    'a7000000-0000-0000-0000-000000000011',
    'a3000000-0000-0000-0000-000000000047',
    'AE-1047',
    60.915,
    7,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000086',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000047',
    'NF-1047',
    68.834,
    14,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000087',
    'a7000000-0000-0000-0000-000000000011',
    'a3000000-0000-0000-0000-000000000048',
    'AE-1048',
    50.22,
    30,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000088',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000048',
    'NF-1048',
    57.753,
    37,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000089',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000049',
    'CP-1049',
    0.527,
    21,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000090',
    'a7000000-0000-0000-0000-000000000014',
    'a3000000-0000-0000-0000-000000000049',
    'OL-1049',
    0.5692,
    28,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000091',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000050',
    'CP-1050',
    0.7564,
    28,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000092',
    'a7000000-0000-0000-0000-000000000014',
    'a3000000-0000-0000-0000-000000000050',
    'OL-1050',
    0.832,
    35,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000093',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000051',
    'CP-1051',
    0.6138,
    35,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000094',
    'a7000000-0000-0000-0000-000000000014',
    'a3000000-0000-0000-0000-000000000051',
    'OL-1051',
    0.6875,
    42,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000095',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000052',
    'CP-1052',
    0.4712,
    14,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000096',
    'a7000000-0000-0000-0000-000000000014',
    'a3000000-0000-0000-0000-000000000052',
    'OL-1052',
    0.5372,
    21,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000097',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000053',
    'CP-1053',
    0.7006,
    18,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000098',
    'a7000000-0000-0000-0000-000000000014',
    'a3000000-0000-0000-0000-000000000053',
    'OL-1053',
    0.8127,
    25,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000099',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000054',
    'CP-1054',
    0.558,
    7,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000100',
    'a7000000-0000-0000-0000-000000000014',
    'a3000000-0000-0000-0000-000000000054',
    'OL-1054',
    0.6082,
    14,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000101',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000055',
    'CP-1055',
    0.1143,
    30,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000102',
    'a7000000-0000-0000-0000-000000000014',
    'a3000000-0000-0000-0000-000000000055',
    'OL-1055',
    0.1269,
    37,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000103',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000056',
    'CP-1056',
    0.0936,
    21,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000104',
    'a7000000-0000-0000-0000-000000000014',
    'a3000000-0000-0000-0000-000000000056',
    'OL-1056',
    0.1058,
    28,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000105',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000057',
    'CP-1057',
    0.0729,
    28,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000106',
    'a7000000-0000-0000-0000-000000000014',
    'a3000000-0000-0000-0000-000000000057',
    'OL-1057',
    0.0838,
    35,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000107',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000058',
    'CP-1058',
    0.1062,
    35,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000108',
    'a7000000-0000-0000-0000-000000000014',
    'a3000000-0000-0000-0000-000000000058',
    'OL-1058',
    0.1147,
    42,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000109',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000059',
    'KE-1059',
    7.41,
    14,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000110',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000059',
    'MC-1059',
    8.151,
    21,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000111',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000060',
    'KE-1060',
    5.616,
    18,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000112',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000060',
    'MC-1060',
    6.2899,
    25,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000113',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000061',
    'KE-1061',
    8.502,
    7,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000114',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000061',
    'MC-1061',
    9.6923,
    14,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000115',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000062',
    'KE-1062',
    6.708,
    30,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000116',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000062',
    'MC-1062',
    7.7813,
    37,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000117',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000063',
    'KE-1063',
    9.594,
    21,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000118',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000063',
    'MC-1063',
    10.4575,
    28,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000119',
    'a7000000-0000-0000-0000-000000000003',
    'a3000000-0000-0000-0000-000000000064',
    'KE-1064',
    7.8,
    28,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000120',
    'a7000000-0000-0000-0000-000000000005',
    'a3000000-0000-0000-0000-000000000064',
    'MC-1064',
    8.658,
    35,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000121',
    'a7000000-0000-0000-0000-000000000008',
    'a3000000-0000-0000-0000-000000000065',
    'BB-1065',
    9.548,
    35,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000122',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000065',
    'IF-1065',
    10.7892,
    42,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000123',
    'a7000000-0000-0000-0000-000000000008',
    'a3000000-0000-0000-0000-000000000066',
    'BB-1066',
    14.136,
    14,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000124',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000066',
    'IF-1066',
    16.2564,
    21,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000125',
    'a7000000-0000-0000-0000-000000000008',
    'a3000000-0000-0000-0000-000000000067',
    'BB-1067',
    11.284,
    18,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000126',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000067',
    'IF-1067',
    12.1867,
    25,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000127',
    'a7000000-0000-0000-0000-000000000008',
    'a3000000-0000-0000-0000-000000000068',
    'BB-1068',
    15.872,
    7,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000128',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000068',
    'IF-1068',
    17.4592,
    14,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000129',
    'a7000000-0000-0000-0000-000000000008',
    'a3000000-0000-0000-0000-000000000069',
    'BB-1069',
    13.02,
    30,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000130',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000069',
    'IF-1069',
    14.5824,
    37,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000131',
    'a7000000-0000-0000-0000-000000000008',
    'a3000000-0000-0000-0000-000000000070',
    'BB-1070',
    10.168,
    21,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000132',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000070',
    'IF-1070',
    11.5915,
    28,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000133',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000071',
    'SS-1071',
    4.1055,
    28,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000134',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000071',
    'CP-1071',
    4.7624,
    35,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000135',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000072',
    'SS-1072',
    3.312,
    35,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000136',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000072',
    'CP-1072',
    3.6101,
    42,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000137',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000073',
    'SS-1073',
    2.5185,
    14,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000138',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000073',
    'CP-1073',
    2.7955,
    21,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000139',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000074',
    'SS-1074',
    3.795,
    18,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000140',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000074',
    'CP-1074',
    4.2884,
    25,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000141',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000075',
    'SS-1075',
    3.0015,
    7,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000142',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000075',
    'CP-1075',
    3.4517,
    14,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000143',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000076',
    'SS-1076',
    4.278,
    30,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000144',
    'a7000000-0000-0000-0000-000000000007',
    'a3000000-0000-0000-0000-000000000076',
    'CP-1076',
    4.6202,
    37,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000145',
    'a7000000-0000-0000-0000-000000000013',
    'a3000000-0000-0000-0000-000000000077',
    'DT-1077',
    64.64,
    21,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000146',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000077',
    'SS-1077',
    71.104,
    28,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000147',
    'a7000000-0000-0000-0000-000000000013',
    'a3000000-0000-0000-0000-000000000078',
    'DT-1078',
    49.92,
    28,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000148',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000078',
    'SS-1078',
    55.9104,
    35,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000149',
    'a7000000-0000-0000-0000-000000000013',
    'a3000000-0000-0000-0000-000000000079',
    'DT-1079',
    73.6,
    35,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000150',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000079',
    'SS-1079',
    83.904,
    42,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000151',
    'a7000000-0000-0000-0000-000000000013',
    'a3000000-0000-0000-0000-000000000080',
    'DT-1080',
    58.88,
    14,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000152',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000080',
    'SS-1080',
    68.3008,
    21,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000153',
    'a7000000-0000-0000-0000-000000000013',
    'a3000000-0000-0000-0000-000000000081',
    'DT-1081',
    82.56,
    18,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000154',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000081',
    'SS-1081',
    89.9904,
    25,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000155',
    'a7000000-0000-0000-0000-000000000013',
    'a3000000-0000-0000-0000-000000000082',
    'DT-1082',
    67.84,
    7,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000156',
    'a7000000-0000-0000-0000-000000000012',
    'a3000000-0000-0000-0000-000000000082',
    'SS-1082',
    75.3024,
    14,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000157',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000083',
    'IF-1083',
    18.509,
    30,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000158',
    'a7000000-0000-0000-0000-000000000008',
    'a3000000-0000-0000-0000-000000000083',
    'BB-1083',
    20.9152,
    37,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000159',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000084',
    'IF-1084',
    26.76,
    21,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000160',
    'a7000000-0000-0000-0000-000000000008',
    'a3000000-0000-0000-0000-000000000084',
    'BB-1084',
    30.774,
    28,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000161',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000085',
    'IF-1085',
    21.631,
    28,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000162',
    'a7000000-0000-0000-0000-000000000008',
    'a3000000-0000-0000-0000-000000000085',
    'BB-1085',
    23.3615,
    35,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000163',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000086',
    'IF-1086',
    16.502,
    35,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000164',
    'a7000000-0000-0000-0000-000000000008',
    'a3000000-0000-0000-0000-000000000086',
    'BB-1086',
    18.1522,
    42,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000165',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000087',
    'NF-1087',
    0.1554,
    14,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000166',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000087',
    'IF-1087',
    0.174,
    21,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000167',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000088',
    'NF-1088',
    0.1232,
    18,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000168',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000088',
    'IF-1088',
    0.1404,
    25,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000169',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000089',
    'NF-1089',
    0.175,
    7,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000170',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000089',
    'IF-1089',
    0.203,
    14,
    1,
    10,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000171',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000090',
    'NF-1090',
    0.1428,
    30,
    25,
    5,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000172',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000090',
    'IF-1090',
    0.1557,
    37,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000173',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000091',
    'NF-1091',
    0.1106,
    21,
    25,
    1,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000174',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000091',
    'IF-1091',
    0.1228,
    28,
    1,
    1,
    false
  ),
  (
    'a8000000-0000-0000-0000-000000000175',
    'a7000000-0000-0000-0000-000000000001',
    'a3000000-0000-0000-0000-000000000092',
    'NF-1092',
    0.1624,
    28,
    25,
    25,
    true
  ),
  (
    'a8000000-0000-0000-0000-000000000176',
    'a7000000-0000-0000-0000-000000000006',
    'a3000000-0000-0000-0000-000000000092',
    'IF-1092',
    0.1835,
    35,
    1,
    10,
    false
  );

----------------------------------------------------------------
-- Alternate barcodes
--
-- Case and pallet barcodes that scan to the same item.
----------------------------------------------------------------
insert into
  inventory.item_barcodes (item_id, barcode, pack_size, label)
select
  i.id,
  '52' || lpad(
    (abs(hashtext (i.sku || p.label)) % 99999999)::text,
    8,
    '0'
  ),
  p.pack,
  p.label
from
  inventory.items i
  cross join (
    values
      (10, 'Inner case of 10'),
      (100, 'Outer case of 100')
  ) as p (pack, label)
where
  (abs(hashtext (i.sku)) % 4) = 0;

----------------------------------------------------------------
-- Bin assignment
--
-- A home bin per item per site, chosen deterministically so the same
-- SKU keeps turning up in the same place across fifteen months of
-- receipts — which is what makes the pick sequences and the bin
-- utilisation report mean anything.
----------------------------------------------------------------
create or replace function pg_temp.home_bin (p_warehouse_id uuid, p_sku text) returns uuid language sql stable as $$
  select l.id
  from inventory.locations l
    join inventory.zones z on z.id = l.zone_id
  where l.warehouse_id = p_warehouse_id
    and z.zone_type = 'storage'
    and l.is_pickable
    and l.is_active
  order by (abs(hashtext (p_sku || l.code)) % 1000000)
  limit 1;
$$;

----------------------------------------------------------------
-- Opening stock
--
-- Fifteen months ago the sites were filled. One purchase order per
-- supplier, every active item on the order it is preferred from,
-- received in full and put away — because that is the only way stock
-- can enter this schema.
----------------------------------------------------------------
do $$
declare
  v_sup record;
  v_item record;
  v_po uuid;
  v_grn uuid;
  v_ordered date;
  v_site record;
  v_wh uuid;
  v_qty numeric(14, 3);
  v_line integer;
begin
  v_ordered := current_date - 450;

  for v_sup in
    select distinct s.id, s.code, s.default_lead_time_days
    from inventory.suppliers s
      join inventory.supplier_items si on si.supplier_id = s.id and si.is_preferred
    where s.status = 'active'
    order by s.code
  loop
    for v_site in
      select id, code from inventory.warehouses where is_active order by code
    loop
      v_wh := v_site.id;
      -- London stocks the full range; the other sites carry the
      -- fast-moving half.
      insert into inventory.purchase_orders (
        supplier_id, warehouse_id, ordered_on, expected_on, priority, supplier_reference, notes
      )
      values (
        v_sup.id,
        v_wh,
        v_ordered,
        v_ordered + v_sup.default_lead_time_days,
        'normal',
        'OPENING-' || v_sup.code,
        'Opening stock order at go-live.'
      )
      returning id into v_po;

      v_line := 0;

      for v_item in
        select i.id, i.sku, i.tracking, i.reorder_quantity, i.abc_class, si.unit_price
        from inventory.items i
          join inventory.supplier_items si on si.item_id = i.id
          and si.supplier_id = v_sup.id
          and si.is_preferred
        where i.status = 'active'
          and (
            v_wh = 'a4000000-0000-0000-0000-000000000001'::uuid
            or i.abc_class in ('a', 'b')
          )
        order by i.sku
      loop
        v_line := v_line + 1;

        v_qty := case
          when v_item.tracking = 'serial' then 12
          when v_wh = 'a4000000-0000-0000-0000-000000000001'::uuid then v_item.reorder_quantity
          else round(v_item.reorder_quantity * 0.45, 0)
        end;

        insert into inventory.purchase_order_lines (
          purchase_order_id, item_id, ordered_quantity, unit_price, expected_on
        )
        values (v_po, v_item.id, v_qty, v_item.unit_price, v_ordered + v_sup.default_lead_time_days);
      end loop;

      if v_line = 0 then
        delete from inventory.purchase_orders where id = v_po;
        continue;
      end if;

      update inventory.purchase_orders set status = 'submitted' where id = v_po;
      update inventory.purchase_orders set status = 'approved' where id = v_po;

      -- Book the whole order in and put it away.
      insert into inventory.receipts (
        purchase_order_id, warehouse_id, received_on, carrier, packing_slip, notes
      )
      values (
        v_po,
        v_wh,
        v_ordered + v_sup.default_lead_time_days,
        'Opening delivery',
        'PS-OPEN-' || v_sup.code,
        'Go-live stock build.'
      )
      returning id into v_grn;

      insert into inventory.receipt_lines (
        receipt_id, purchase_order_line_id, item_id, expected_quantity,
        received_quantity, unit_cost, lot_code, expires_on, put_away_location_id
      )
      select v_grn,
        pol.id,
        pol.item_id,
        pol.ordered_quantity,
        pol.ordered_quantity,
        pol.unit_price,
        -- The site code is in the lot code because the same item was
        -- bought into all three warehouses on the same day, and a lot
        -- code is unique per item.
        case
          when i.tracking = 'lot' then 'OPEN-' || v_site.code || '-' || right(i.sku, 4)
          else null
        end,
        case when i.shelf_life_days is not null then (v_ordered + i.shelf_life_days) else null end,
        pg_temp.home_bin (v_wh, i.sku)
      from inventory.purchase_order_lines pol
        join inventory.items i on i.id = pol.item_id
      where pol.purchase_order_id = v_po
      order by pol.line_number;

      update inventory.receipts set status = 'checking' where id = v_grn;
      update inventory.receipts set status = 'put_away' where id = v_grn;
    end loop;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Ongoing purchasing
--
-- Sixty-five orders spread across the fourteen months since. The
-- outcome is chosen from the order's AGE rather than its position in
-- the loop: old orders have landed, recent ones are still open, and
-- the ones in between are the interesting middle that makes the
-- arrivals board and the late-delivery figures worth looking at.
----------------------------------------------------------------
do $$
declare
  v_sup record;
  v_item record;
  v_po uuid;
  v_grn uuid;
  v_ordered date;
  v_expected date;
  v_received date;
  v_wh uuid;
  v_seed bigint;
  v_age integer;
  v_roll integer;
  v_lines integer;
  v_qty numeric(14, 3);
  v_short numeric(14, 3);
  i integer;
  k integer;
begin
  for i in 1..65 loop
    v_seed := abs(hashtext ('supasheet-inventory-po-' || i::text));

    select s.id, s.code, s.default_lead_time_days
    into v_sup
    from inventory.suppliers s
    where s.status = 'active'
    order by s.code
    offset (v_seed % 12)
    limit 1;

    select id into v_wh
    from inventory.warehouses
    where is_active
    order by case when (v_seed % 10) < 6 then code else 'ZZZ' end
    limit 1;

    -- One cohort per month, so no month is empty and none is a spike.
    v_ordered := least(
      (
        date_trunc('month', current_date) - ((13 - ((i - 1) % 14)) || ' months')::interval
      )::date + (v_seed % 26)::integer,
      current_date
    );
    v_expected := v_ordered + v_sup.default_lead_time_days;

    insert into inventory.purchase_orders (
      supplier_id, warehouse_id, ordered_on, expected_on, priority, supplier_reference, notes
    )
    values (
      v_sup.id,
      v_wh,
      v_ordered,
      v_expected,
      (array['low', 'normal', 'normal', 'normal', 'high', 'urgent'])[
        1 + (v_seed % 6)::integer
      ]::inventory.priority,
      'SO-' || lpad(((v_seed / 3) % 900000)::text, 6, '0'),
      case when (v_seed % 8) = 0 then 'Expedited against a shortage.' else null end
    )
    returning id into v_po;

    v_lines := 2 + (v_seed % 4)::integer;
    k := 0;

    for v_item in
      select i2.id, i2.sku, i2.tracking, i2.reorder_quantity, si.unit_price, si.pack_size
      from inventory.items i2
        join inventory.supplier_items si on si.item_id = i2.id and si.supplier_id = v_sup.id
      where i2.status = 'active'
      order by (abs(hashtext (i2.sku || i::text)) % 1000000)
      limit v_lines
    loop
      k := k + 1;

      v_qty := case
        when v_item.tracking = 'serial' then greatest(4, (v_seed / (k * 3)) % 14)
        else ceil(
          greatest(v_item.reorder_quantity * (0.4 + ((v_seed / (k * 7)) % 90) / 100.0), v_item.pack_size)
            / v_item.pack_size
        ) * v_item.pack_size
      end;

      insert into inventory.purchase_order_lines (
        purchase_order_id, item_id, ordered_quantity, unit_price, expected_on
      )
      values (v_po, v_item.id, v_qty, v_item.unit_price, v_expected);
    end loop;

    v_age := current_date - v_ordered;
    v_roll := ((v_seed / 11) % 100)::integer;

    -- The most recent orders have not been through approval yet.
    if v_age <= 20 and ((v_seed / 17) % 100)::integer < 45 then
      continue;
    end if;

    update inventory.purchase_orders set status = 'submitted' where id = v_po;

    if v_age <= 34 and ((v_seed / 19) % 100)::integer < 35 then
      continue;
    end if;

    if v_roll >= 92 then
      perform inventory.cancel_purchase_order (
        v_po,
        (array[
          'Superseded by a larger order',
          'Supplier could not commit to the date',
          'Demand withdrawn'
        ]) [1 + (v_seed % 3)::integer]
      );
      continue;
    end if;

    update inventory.purchase_orders set status = 'approved' where id = v_po;

    -- Nothing arrives before it was due.
    if v_expected > current_date then
      continue;
    end if;

    -- Suppliers run late in proportion to how good they are.
    v_received := least(
      v_expected + case
        when v_roll < 60 then 0
        when v_roll < 85 then (v_seed % 6)::integer
        else 5 + (v_seed % 14)::integer
      end,
      current_date
    );

    insert into inventory.receipts (
      purchase_order_id, warehouse_id, received_on, carrier, tracking_number, packing_slip
    )
    values (
      v_po,
      v_wh,
      v_received,
      (array['DPD', 'DHL', 'UPS', 'Palletways', 'Own transport'])[1 + (v_seed % 5)::integer],
      'TRK' || lpad(((v_seed / 7) % 99999999)::text, 8, '0'),
      'PS-' || lpad(((v_seed / 13) % 900000)::text, 6, '0')
    )
    returning id into v_grn;

    k := 0;

    -- Short deliveries are the norm on about one line in six.
    insert into inventory.receipt_lines (
      receipt_id, purchase_order_line_id, item_id, expected_quantity,
      received_quantity, rejected_quantity, unit_cost, lot_code, expires_on,
      put_away_location_id, note
    )
    select v_grn,
      pol.id,
      pol.item_id,
      pol.ordered_quantity,
      case
        when (abs(hashtext (pol.id::text)) % 6) = 0
        then greatest(round(pol.ordered_quantity * 0.85, 0), 1)
        else pol.ordered_quantity
      end,
      case
        when it.tracking <> 'serial' and (abs(hashtext (pol.id::text || 'rej')) % 14) = 0
        then greatest(round(pol.ordered_quantity * 0.04, 0), 1)
        else 0
      end,
      pol.unit_price,
      -- Batch date plus a slice of the order line id. A lot code is
      -- unique per item, and the same SKU is bought from the same
      -- supplier more than once a month.
      case
        when it.tracking = 'lot'
        then to_char(v_received, 'YYMMDD') || '-' || upper(substr(pol.id::text, 1, 4))
        else null
      end,
      case when it.shelf_life_days is not null then v_received + it.shelf_life_days else null end,
      pg_temp.home_bin (v_wh, it.sku),
      case
        when (abs(hashtext (pol.id::text)) % 6) = 0 then 'Short shipped — balance to follow.'
        else null
      end
    from inventory.purchase_order_lines pol
      join inventory.items it on it.id = pol.item_id
    where pol.purchase_order_id = v_po
    order by pol.line_number;

    update inventory.receipts set status = 'checking' where id = v_grn;

    -- Deliveries from the last few days are still on the dock.
    if current_date - v_received <= 2 and (v_seed % 3) = 0 then
      continue;
    end if;

    update inventory.receipts set status = 'put_away' where id = v_grn;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Inter-site transfers
--
-- London holds the range and feeds the other two. Each transfer ships
-- out of a bin into the destination's in-transit bin, and is booked
-- in from there — so a transfer on the road is stock the ledger can
-- still account for.
----------------------------------------------------------------
do $$
declare
  v_trf uuid;
  v_line record;
  v_seed bigint;
  v_to uuid;
  v_requested date;
  v_age integer;
  v_roll integer;
  i integer;
  k integer;
begin
  for i in 1..34 loop
    v_seed := abs(hashtext ('supasheet-inventory-transfer-' || i::text));

    v_to := case
      when (v_seed % 2) = 0 then 'a4000000-0000-0000-0000-000000000002'::uuid
      else 'a4000000-0000-0000-0000-000000000003'::uuid
    end;

    v_requested := least(
      (
        date_trunc('month', current_date) - ((11 - ((i - 1) % 12)) || ' months')::interval
      )::date + (v_seed % 24)::integer,
      current_date
    );

    insert into inventory.stock_transfers (
      from_warehouse_id, to_warehouse_id, requested_on, expected_on, priority, reason, notes
    )
    values (
      'a4000000-0000-0000-0000-000000000001',
      v_to,
      v_requested,
      v_requested + 3,
      (array['low', 'normal', 'normal', 'high'])[1 + (v_seed % 4)::integer]::inventory.priority,
      (array[
        'Rebalance after a run of orders',
        'Seasonal build at the forward store',
        'Cover a supplier delay',
        'Consolidate slow movers',
        'Support a customer trial'
      ]) [1 + ((v_seed / 3) % 5)::integer],
      case when (v_seed % 7) = 0 then 'Agreed with the site manager.' else null end
    )
    returning id into v_trf;

    k := 0;

    -- Only untracked and lot-tracked stock moves between sites in
    -- bulk; serialised units go out to customers, not sideways.
    for v_line in
      select sl.item_id, sl.lot_id, sl.location_id, sl.available, i2.tracking
      from inventory.stock_levels sl
        join inventory.items i2 on i2.id = sl.item_id
      where sl.warehouse_id = 'a4000000-0000-0000-0000-000000000001'
        and sl.available >= 40
        and i2.tracking <> 'serial'
        and i2.status = 'active'
      order by (abs(hashtext (sl.id::text || i::text)) % 1000000)
      limit 2 + (v_seed % 3)::integer
    loop
      k := k + 1;

      insert into inventory.stock_transfer_lines (
        transfer_id, item_id, lot_id, from_location_id, quantity
      )
      values (
        v_trf,
        v_line.item_id,
        v_line.lot_id,
        v_line.location_id,
        greatest(round(v_line.available * 0.12, 0), 5)
      );
    end loop;

    if k = 0 then
      delete from inventory.stock_transfers where id = v_trf;
      continue;
    end if;

    v_age := current_date - v_requested;
    v_roll := ((v_seed / 13) % 100)::integer;

    if v_age <= 25 and v_roll < 55 then
      continue;
    end if;

    if v_roll >= 95 then
      update inventory.stock_transfers set status = 'cancelled' where id = v_trf;
      continue;
    end if;

    update inventory.stock_transfers set status = 'in_transit' where id = v_trf;

    -- Anything shipped in the last few weeks is still on the road.
    continue when v_age <= 25;

    update inventory.stock_transfers set status = 'received' where id = v_trf;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Internal stock requests
--
-- The one table an ordinary user writes to. Raised as drafts, then
-- submitted and decided, so the approval guard and the requester's
-- own-rows-only policy are both exercised for real.
----------------------------------------------------------------
do $$
declare
  v_requesters uuid[] := array[
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1'::uuid,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4'::uuid,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'::uuid,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e1'::uuid,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e2'::uuid
  ];
  v_purposes text[] := array[
    'Production line changeover',
    'Maintenance callout kit',
    'Customer demonstration build',
    'Engineering prototype',
    'Field service van restock',
    'Trade show samples',
    'Quality laboratory testing',
    'Training rig assembly'
  ];
  v_req uuid;
  v_item record;
  v_who uuid;
  v_name text;
  v_created date;
  v_seed bigint;
  v_age integer;
  v_roll integer;
  i integer;
  k integer;
begin
  for i in 1..58 loop
    v_seed := abs(hashtext ('supasheet-inventory-request-' || i::text));
    v_who := v_requesters[1 + (v_seed % 5)::integer];

    v_created := current_date - case
      when i <= 18 then ((v_seed / 3) % 24)::integer
      else ((v_seed / 3) % 330)::integer
    end;

    select coalesce(u.name, split_part(u.email, '@', 1))
    into v_name
    from supasheet.users u
    where u.id = v_who;

    insert into inventory.stock_requests (
      requester_id, requester_name, warehouse_id, priority, needed_by, purpose,
      cost_centre, deliver_to
    )
    values (
      v_who,
      v_name,
      'a4000000-0000-0000-0000-000000000001',
      (array['low', 'normal', 'normal', 'high', 'urgent'])[
        1 + (v_seed % 5)::integer
      ]::inventory.priority,
      v_created + 3 + (v_seed % 9)::integer,
      v_purposes[1 + ((v_seed / 7) % 8)::integer],
      (array['CC-PROD', 'CC-ENG', 'CC-SERV', 'CC-QA', 'CC-SALES'])[1 + ((v_seed / 11) % 5)::integer],
      (array['Line 2', 'Workshop', 'Laboratory', 'Van 4', 'Demo room'])[1 + ((v_seed / 13) % 5)::integer]
    )
    returning id into v_req;

    k := 0;

    for v_item in
      select id, sku, available
      from inventory.items
      where status = 'active'
        and available >= 30
        -- A requester asks for a quantity. Serialised units are issued
        -- one at a time against a scanned serial, so they never appear
        -- on a requisition line.
        and tracking <> 'serial'
      order by (abs(hashtext (sku || i::text)) % 1000000)
      limit 1 + (v_seed % 4)::integer
    loop
      k := k + 1;

      insert into inventory.stock_request_lines (request_id, item_id, requested_quantity, note)
      values (
        v_req,
        v_item.id,
        greatest(round(v_item.available * 0.04, 0), 1),
        case when (v_seed % 11) = 0 then 'Needed for the morning shift.' else null end
      );
    end loop;

    if k = 0 then
      delete from inventory.stock_requests where id = v_req;
      continue;
    end if;

    v_age := current_date - v_created;
    v_roll := ((v_seed / 17) % 100)::integer;

    if v_age <= 6 and v_roll < 35 then
      continue;
    end if;

    update inventory.stock_requests
    set status = 'submitted',
      submitted_at = (v_created + 1)::timestamptz + interval '9 hours'
    where id = v_req;

    continue when v_age <= 12 and v_roll < 70;

    if v_roll >= 90 then
      update inventory.stock_requests
      set status = 'rejected',
        rejected_reason = (array[
          'Not enough free stock — reorder raised instead.',
          'Charge this to the project, not the cost centre.',
          'Duplicate of an earlier request.'
        ]) [1 + (v_seed % 3)::integer],
        decided_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0e2',
        decided_at = (v_created + 2)::timestamptz + interval '11 hours'
      where id = v_req;

      continue;
    end if;

    update inventory.stock_request_lines
    set approved_quantity = requested_quantity
    where request_id = v_req;

    update inventory.stock_requests
    set status = 'approved',
      decided_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0e2',
      decided_at = (v_created + 2)::timestamptz + interval '11 hours'
    where id = v_req;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Picking
--
-- Every approved request gets a pick, and the rest of the volume is
-- despatch work against customer orders. Bins are not chosen here:
-- the line trigger applies the FEFO rule and picks one, which is the
-- behaviour worth demonstrating.
----------------------------------------------------------------
do $$
declare
  v_req record;
  v_line record;
  v_pick uuid;
  v_seed bigint;
  v_age integer;
  v_roll integer;
  v_pickers uuid[] := array[
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e2'::uuid,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'::uuid,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0e1'::uuid
  ];
  i integer;
  k integer;
begin
  -- Picks raised against approved requests.
  for v_req in
    -- Age from submitted_at, not created_at. created_at is the moment
    -- THIS FILE ran, so every request would look raised today and no
    -- pick would ever get far enough to be dispatched.
    select r.*,
      (current_date - coalesce(r.submitted_at::date, current_date)) as age
    from inventory.stock_requests r
    where r.status = 'approved'
    order by r.submitted_at
  loop
    v_seed := abs(hashtext ('pick-req-' || v_req.id::text));

    insert into inventory.pick_lists (
      warehouse_id, request_id, priority, scheduled_for, assigned_to
    )
    values (
      v_req.warehouse_id,
      v_req.id,
      v_req.priority,
      least(coalesce(v_req.submitted_at::date, current_date) + 2, current_date),
      v_pickers[1 + (v_seed % 3)::integer]
    )
    returning id into v_pick;

    insert into inventory.pick_lines (pick_list_id, item_id, requested_quantity, request_line_id)
    select v_pick, rl.item_id, coalesce(rl.approved_quantity, rl.requested_quantity), rl.id
    from inventory.stock_request_lines rl
    where rl.request_id = v_req.id
    order by rl.line_number;

    v_roll := ((v_seed / 7) % 100)::integer;

    if v_req.age <= 2 and v_roll < 50 then
      continue;
    end if;

    update inventory.pick_lists set status = 'assigned' where id = v_pick;

    continue when v_req.age <= 3 and v_roll < 60;

    update inventory.pick_lists set status = 'picking' where id = v_pick;
    update inventory.pick_lists set status = 'picked' where id = v_pick;

    continue when v_roll >= 88;

    update inventory.pick_lists set status = 'dispatched' where id = v_pick;
  end loop;

  -- Despatch picks against customer orders, which live outside this
  -- module — the pick list is where they land.
  for i in 1..90 loop
    v_seed := abs(hashtext ('supasheet-inventory-pick-' || i::text));

    insert into inventory.pick_lists (
      warehouse_id, priority, scheduled_for, assigned_to, notes
    )
    values (
      'a4000000-0000-0000-0000-000000000001',
      (array['low', 'normal', 'normal', 'normal', 'high', 'urgent'])[
        1 + (v_seed % 6)::integer
      ]::inventory.priority,
      least(
        (
          date_trunc('month', current_date) - ((11 - ((i - 1) % 12)) || ' months')::interval
        )::date + (v_seed % 25)::integer,
        current_date
      ),
      v_pickers[1 + (v_seed % 3)::integer],
      'Customer order SO-' || lpad(((v_seed / 5) % 90000)::text, 5, '0')
    )
    returning id into v_pick;

    k := 0;

    for v_line in
      select i2.id, i2.sku, i2.available, i2.tracking
      from inventory.items i2
      where i2.status = 'active'
        and i2.available >= 25
        and i2.tracking <> 'serial'
      order by (abs(hashtext (i2.sku || 'pick' || i::text)) % 1000000)
      limit 2 + (v_seed % 4)::integer
    loop
      k := k + 1;

      insert into inventory.pick_lines (pick_list_id, item_id, requested_quantity)
      values (v_pick, v_line.id, greatest(round(v_line.available * 0.03, 0), 1));
    end loop;

    -- One pick in six also ships a serialised unit.
    if (v_seed % 6) = 0 then
      insert into inventory.pick_lines (pick_list_id, item_id, requested_quantity, location_id, serial_id)
      select v_pick, s.item_id, 1, s.location_id, s.id
      from inventory.serials s
        join inventory.locations l on l.id = s.location_id
      where s.status = 'in_stock'
        and l.warehouse_id = 'a4000000-0000-0000-0000-000000000001'
        and l.is_pickable
      order by (abs(hashtext (s.serial_number || i::text)) % 1000000)
      limit 1;

      k := k + 1;
    end if;

    if k = 0 then
      delete from inventory.pick_lists where id = v_pick;
      continue;
    end if;

    v_age := current_date - (select scheduled_for from inventory.pick_lists where id = v_pick);
    v_roll := ((v_seed / 11) % 100)::integer;

    if v_age <= 1 and v_roll < 45 then
      continue;
    end if;

    update inventory.pick_lists set status = 'assigned' where id = v_pick;

    continue when v_age <= 2 and v_roll < 55;

    update inventory.pick_lists set status = 'picking' where id = v_pick;

    continue when v_age = 0 and v_roll < 70;

    update inventory.pick_lists set status = 'picked' where id = v_pick;

    continue when v_roll >= 92;

    update inventory.pick_lists set status = 'dispatched' where id = v_pick;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Fast movers
--
-- Demand is not spread evenly across a range, and a dataset where it
-- is has an empty replenishment list — which is the one screen a
-- planner opens every morning. These are the lines that actually sell:
-- repeated despatch picks over the last few months that draw them
-- down past their reorder point, so the buying list has something
-- real on it rather than a flag somebody set by hand.
----------------------------------------------------------------
do $$
declare
  v_item record;
  v_pick uuid;
  v_seed bigint;
  v_when date;
  v_qty numeric(14, 3);
  v_avail numeric(14, 3);
  v_bin_avail numeric(14, 3);
  r integer;
begin
  -- Lines where London holds the bulk of the stock, so drawing London
  -- down actually moves the network position past the reorder point.
  for v_item in
    select i.id, i.sku, i.reorder_point
    from inventory.items i
    where i.status = 'active'
      and i.tracking <> 'serial'
      and i.available > i.reorder_point
      and i.reorder_point > 0
      and coalesce(
        (
          select sum(sl.available)
          from inventory.stock_levels sl
          where sl.item_id = i.id
            and sl.warehouse_id = 'a4000000-0000-0000-0000-000000000001'
        ),
        0
      ) > i.available * 0.6
    order by (abs(hashtext (i.sku || 'demand')) % 1000000)
    limit 26
  loop
    for r in 1..7 loop
      v_seed := abs(hashtext ('fastmover-' || v_item.sku || '-' || r::text));

      select available into v_avail from inventory.items where id = v_item.id;

      -- Stop once the line is genuinely short; a bin cannot go
      -- negative and there is no reason to try.
      exit when v_avail <= greatest(v_item.reorder_point * 0.55, 1);

      -- Size the pick against the BIN, not the item. Item availability
      -- is the whole network, and a pick raised at London for stock
      -- sitting in Rotterdam finds no bin that can cover it — the line
      -- ends up unsited and the pick ships nothing.
      select sl.available
      into v_bin_avail
      from inventory.stock_levels sl
        join inventory.locations l on l.id = sl.location_id
      where sl.item_id = v_item.id
        and sl.warehouse_id = 'a4000000-0000-0000-0000-000000000001'
        and l.is_pickable
        and l.is_active
      order by sl.available desc
      limit 1;

      exit when coalesce(v_bin_avail, 0) < 2;

      v_qty := greatest(round(v_bin_avail * 0.5, 0), 1);

      v_when := current_date - (10 + ((v_seed % 100)))::integer;

      insert into inventory.pick_lists (
        warehouse_id, priority, scheduled_for, assigned_to, notes
      )
      values (
        'a4000000-0000-0000-0000-000000000001',
        (array['normal', 'high', 'urgent'])[1 + (v_seed % 3)::integer]::inventory.priority,
        v_when,
        'b73eb03e-fb7a-424d-84ff-18e2791ce0e2',
        'Customer order SO-' || lpad(((v_seed / 3) % 90000)::text, 5, '0')
      )
      returning id into v_pick;

      insert into inventory.pick_lines (pick_list_id, item_id, requested_quantity)
      values (v_pick, v_item.id, v_qty);

      -- If no bin can cover it in one go the line is left unsited and
      -- the pick would ship nothing, so drop it rather than leave an
      -- empty pick on the board.
      if not exists (
        select 1 from inventory.pick_lines where pick_list_id = v_pick and location_id is not null
      ) then
        delete from inventory.pick_lists where id = v_pick;
        continue;
      end if;

      update inventory.pick_lists set status = 'assigned' where id = v_pick;
      update inventory.pick_lists set status = 'picking' where id = v_pick;
      update inventory.pick_lists set status = 'picked' where id = v_pick;
      update inventory.pick_lists set status = 'dispatched' where id = v_pick;
    end loop;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Cycle counting
--
-- Raised with inventory.plan_cycle_count (), which is the same form
-- the UI calls, so the sheets carry a line for every bin holding
-- stock in scope. Counted quantities are then set with a realistic
-- error rate and the sheet is posted — which writes the variance to
-- the ledger like any other movement.
----------------------------------------------------------------
do $$
declare
  v_count uuid;
  v_zone record;
  v_seed bigint;
  v_scheduled date;
  v_age integer;
  v_roll integer;
  i integer;
begin
  for i in 1..34 loop
    v_seed := abs(hashtext ('supasheet-inventory-count-' || i::text));

    select z.id, z.warehouse_id
    into v_zone
    from inventory.zones z
    where z.zone_type = 'storage'
    order by (abs(hashtext (z.code || z.warehouse_id::text || i::text)) % 1000000)
    limit 1;

    v_scheduled := least(
      (
        date_trunc('month', current_date) - ((11 - ((i - 1) % 12)) || ' months')::interval
      )::date + (v_seed % 24)::integer,
      current_date
    );

    -- Take the id from the form's own return value. Reading back the
    -- newest row by created_at does not work here: every count in this
    -- block is created inside one transaction, so they all share a
    -- timestamp and the tie breaks arbitrarily — occasionally onto a
    -- count that has already been posted.
    begin
      select c.id
      into v_count
      from inventory.plan_cycle_count (
        v_zone.warehouse_id,
        v_zone.id,
        case when (v_seed % 3) = 0 then 'a'::inventory.abc_class else null end,
        v_scheduled,
        (array['cycle', 'cycle', 'cycle', 'spot', 'full'])[
          1 + (v_seed % 5)::integer
        ]::inventory.count_type
      ) c;
    exception
      when others then
        -- Nothing in scope. A real planner would widen it; the seed
        -- just moves on.
        continue;
    end;

    update inventory.cycle_counts
    set counted_by = (array[
      'b73eb03e-fb7a-424d-84ff-18e2791ce0e2'::uuid,
      'b73eb03e-fb7a-424d-84ff-18e2791ce0b8'::uuid
    ]) [1 + (v_seed % 2)::integer]
    where id = v_count;

    v_age := current_date - v_scheduled;
    v_roll := ((v_seed / 7) % 100)::integer;

    -- Counts scheduled for the next few days have not started.
    if v_age <= 2 and v_roll < 55 then
      continue;
    end if;

    update inventory.cycle_counts
    set status = 'counting',
      started_at = v_scheduled::timestamptz + interval '8 hours'
    where id = v_count;

    -- About one line in seven disagrees with the record, which is
    -- roughly what a warehouse that counts regularly actually sees.
    update inventory.cycle_count_lines cl
    set counted_quantity = case
      when (abs(hashtext (cl.id::text)) % 7) = 0
      then greatest(cl.system_quantity - (1 + (abs(hashtext (cl.id::text)) % 6)), 0)
      when (abs(hashtext (cl.id::text || 'up')) % 23) = 0
      then cl.system_quantity + (1 + (abs(hashtext (cl.id::text)) % 4))
      else cl.system_quantity
    end,
      note = case
        when (abs(hashtext (cl.id::text)) % 7) = 0
        then (array[
          'Short against the record — recounted twice.',
          'Damaged units pulled from the bin.',
          'Possible mis-pick earlier in the week.'
        ]) [1 + (abs(hashtext (cl.id::text)) % 3)]
        else null
      end
    where cl.count_id = v_count;

    continue when v_age <= 5 and v_roll < 70;

    update inventory.cycle_counts set status = 'review' where id = v_count;

    continue when v_roll >= 90;

    update inventory.cycle_counts
    set status = 'posted',
      posted_at = (v_scheduled + 1)::timestamptz + interval '16 hours',
      posted_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0e1'
    where id = v_count;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Adjustments
--
-- The only sanctioned way to change stock without a physical event.
-- Value decides whether a second pair of eyes is needed, so the
-- approval threshold in settings is exercised both ways.
----------------------------------------------------------------
do $$
declare
  v_adj uuid;
  v_level record;
  v_seed bigint;
  v_when date;
  v_reason inventory.adjustment_reason;
  v_age integer;
  v_roll integer;
  v_qty numeric(14, 3);
  i integer;
  k integer;
begin
  for i in 1..40 loop
    v_seed := abs(hashtext ('supasheet-inventory-adjustment-' || i::text));

    v_reason := (array[
      'damage', 'damage', 'expiry', 'theft', 'found',
      'correction', 'correction', 'sample', 'scrap', 'rework'
    ]) [1 + (v_seed % 10)::integer]::inventory.adjustment_reason;

    v_when := least(
      (
        date_trunc('month', current_date) - ((11 - ((i - 1) % 12)) || ' months')::interval
      )::date + (v_seed % 25)::integer,
      current_date
    );

    insert into inventory.stock_adjustments (
      warehouse_id, reason, adjusted_on, reference, explanation
    )
    values (
      'a4000000-0000-0000-0000-000000000001',
      v_reason,
      v_when,
      'ADJ-REF-' || lpad(((v_seed / 5) % 90000)::text, 5, '0'),
      case v_reason
        when 'damage' then 'Pallet struck by a forklift in the aisle; units crushed beyond use.'
        when 'expiry' then 'Batch passed its expiry date before it could be consumed.'
        when 'theft' then 'Stock unaccounted for after a security review.'
        when 'found' then 'Units found behind a pallet during a bin tidy.'
        when 'correction' then 'Correcting a mis-keyed receipt quantity from last month.'
        when 'sample' then 'Units issued to the laboratory for destructive testing.'
        when 'scrap' then 'Failed inspection; scrapped rather than reworked.'
        else 'Returned to the line for rework after a build fault.'
      end
    )
    returning id into v_adj;

    k := 0;

    for v_level in
      select sl.item_id, sl.location_id, sl.lot_id, sl.on_hand
      from inventory.stock_levels sl
        join inventory.items i2 on i2.id = sl.item_id
      where sl.warehouse_id = 'a4000000-0000-0000-0000-000000000001'
        and sl.on_hand >= 12
        and i2.tracking <> 'serial'
      order by (abs(hashtext (sl.id::text || 'adj' || i::text)) % 1000000)
      limit 1 + (v_seed % 3)::integer
    loop
      k := k + 1;

      -- Found stock writes on; everything else writes off, and never
      -- more than the bin actually holds.
      v_qty := greatest(round(v_level.on_hand * 0.06, 0), 1);

      insert into inventory.stock_adjustment_lines (
        adjustment_id, item_id, location_id, lot_id, adjustment_quantity, note
      )
      values (
        v_adj,
        v_level.item_id,
        v_level.location_id,
        v_level.lot_id,
        case when v_reason = 'found' then v_qty else -least(v_qty, v_level.on_hand) end,
        case when (v_seed % 5) = 0 then 'Photographed before disposal.' else null end
      );
    end loop;

    if k = 0 then
      delete from inventory.stock_adjustments where id = v_adj;
      continue;
    end if;

    v_age := current_date - v_when;
    v_roll := ((v_seed / 11) % 100)::integer;

    if v_age <= 3 and v_roll < 40 then
      continue;
    end if;

    update inventory.stock_adjustments set status = 'pending_approval' where id = v_adj;

    continue when v_age <= 6 and v_roll < 55;

    if v_roll >= 92 then
      perform inventory.reject_adjustment (
        v_adj,
        (array[
          'Raise a cycle count first and adjust from the variance.',
          'No evidence attached for a write-off of this size.',
          'Wrong bin — the stock is one level up.'
        ]) [1 + (v_seed % 3)::integer]
      );
      continue;
    end if;

    update inventory.stock_adjustments
    set status = 'approved',
      approved_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0e1',
      approved_at = (v_when + 1)::timestamptz + interval '10 hours'
    where id = v_adj;

    continue when v_roll >= 86;

    update inventory.stock_adjustments set status = 'posted' where id = v_adj;
  end loop;
end;
$$;

----------------------------------------------------------------
-- Age the paperwork
--
-- The stock ledger is already dated correctly — every movement was
-- stamped with when the work happened, because an append-only table
-- cannot be corrected afterwards. What is left is the documents
-- around it, which all carry the moment this file ran.
----------------------------------------------------------------
update inventory.purchase_orders
set
  created_at = ordered_on::timestamptz + interval '9 hours',
  approved_at = case
    when status in ('draft', 'submitted') then null
    else (ordered_on + 1)::timestamptz + interval '11 hours'
  end,
  approved_by = case
    when status in ('draft', 'submitted') then null
    else 'b73eb03e-fb7a-424d-84ff-18e2791ce0e3'::uuid
  end,
  user_id = 'b73eb03e-fb7a-424d-84ff-18e2791ce0e3';

update inventory.receipts
set
  created_at = received_on::timestamptz + interval '8 hours',
  received_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0e2',
  put_away_at = case
    when status = 'put_away' then least(received_on + 1, current_date)::timestamptz + interval '14 hours'
    else null
  end;

update inventory.stock_transfers
set
  created_at = requested_on::timestamptz + interval '10 hours',
  requested_by = 'b73eb03e-fb7a-424d-84ff-18e2791ce0e2';

update inventory.stock_requests
set
  created_at = coalesce(
    submitted_at - interval '1 day',
    current_timestamp - interval '1 day'
  );

update inventory.pick_lists
set
  created_at = scheduled_for::timestamptz + interval '7 hours',
  started_at = case
    when status in ('picking', 'picked', 'dispatched') then scheduled_for::timestamptz + interval '9 hours'
    else null
  end,
  completed_at = case
    when status in ('picked', 'dispatched') then scheduled_for::timestamptz + interval '13 hours'
    else null
  end,
  dispatched_at = case
    when status = 'dispatched' then scheduled_for::timestamptz + interval '16 hours'
    else null
  end;

update inventory.cycle_counts
set
  created_at = scheduled_for::timestamptz + interval '7 hours';

update inventory.stock_adjustments
set
  created_at = adjusted_on::timestamptz + interval '9 hours',
  raised_by = coalesce(raised_by, 'b73eb03e-fb7a-424d-84ff-18e2791ce0e2'),
  posted_at = case
    when status = 'posted' then (adjusted_on + 1)::timestamptz + interval '12 hours'
    else null
  end;

-- Items and suppliers predate the first order they appear on.
update inventory.items i
set
  created_at = coalesce(
    (
      select
        min(po.ordered_on)
      from
        inventory.purchase_order_lines pol
        join inventory.purchase_orders po on po.id = pol.purchase_order_id
      where
        pol.item_id = i.id
    ) - 30,
    current_date - 480
  )::timestamptz + interval '10 hours';

update inventory.suppliers s
set
  created_at = coalesce(
    (
      select
        min(po.ordered_on)
      from
        inventory.purchase_orders po
      where
        po.supplier_id = s.id
    ) - 45,
    current_date - 480
  )::timestamptz + interval '10 hours';

----------------------------------------------------------------
-- Run the nightly maintenance once, then rebuild the snapshot.
--
-- This is what sets the ABC classes from what actually moved, ages
-- the expired lots and refreshes the throughput matview.
----------------------------------------------------------------
select
  *
from
  inventory.run_daily_maintenance ();

refresh materialized view inventory.movement_summary;

select
  supasheet.refresh_metadata ();
