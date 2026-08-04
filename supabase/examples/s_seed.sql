-- Store Seeder
-- ================================================================
-- Demo data for the store (ecommerce / order management) module.
-- Apply supabase/examples/20260802000000_store.sql first:
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f supabase/examples/20260802000000_store.sql \
--     -f supabase/examples/s_seed.sql
--
-- Volume: 3 warehouses, 8 brands, 14 categories (three levels deep),
-- 28 products with cost records and 48 variants, ~6,100 units of
-- opening stock received across 88 stock lines, 36 customers with 45
-- addresses, 6 discount campaigns, and 72 orders spanning twelve
-- months with 144 lines, 63 payments, 53 shipments, 9 returns and 90
-- reviews. The triggers derive the whole stock ledger (208
-- movements), every rollup, and 408 order-history events on top of
-- that.
--
-- Dates are all relative to `current_date` / `current_timestamp`, so
-- the dashboards, the 14-day sales chart, the weekly channel area
-- chart, the promotion gantt and the monthly trading rollup all have
-- shape whenever this is run.
--
-- WHY THIS FILE WALKS ITS ORDERS
--
-- Stock in this module is derived, not typed: `on_hand` comes from
-- an append-only ledger, `reserved` comes from confirmed orders, and
-- `available` is what is left. Inserting an order that is already
-- `completed` would produce a receipt with no ledger entry behind
-- it — the numbers would simply not add up, and the reservation and
-- fulfilment machinery would never be exercised.
--
-- So stock is received first, and then the orders are walked:
-- confirmed (which reserves), paid, shipped (which releases the
-- reservation and books the goods out through the ledger), and
-- completed. Cancellations release their stock. Returns come back in
-- and are refunded through the payment ledger. Everything the
-- storefront shows is a consequence of those movements.
--
-- Five hardcoded users are seeded first so this file can run
-- independently of supabase/seed.sql (`on conflict do nothing`, so
-- it is also safe to run after supabase/seed.sql has created the
-- first three):
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b8  superadmin@supasheet.app (x-admin)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0c1  merch@supasheet.app      (merchandiser)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b9  ops@supasheet.app        (fulfillment)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b4  user@supasheet.app       (user / customer)
--   b73eb03e-fb7a-424d-84ff-18e2791ce0b1  user1@supasheet.app      (user / customer)
--
-- Sign in as merch@supasheet.app to run the catalogue (products,
-- pricing, promotions, review moderation, and the only seat besides
-- the owner that can see cost and margin), as ops@supasheet.app to
-- run the warehouse (orders, dispatch, stock, returns — no cost, and
-- no way to rewrite the ledger), and as user@supasheet.app to see
-- the module from a SHOPPER's seat: that login is wired to the
-- customer Ada Lovelace, and sees only her own orders, addresses,
-- returns and reviews plus the published catalogue.
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    'authenticated',
    'authenticated',
    'merch@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "merchandiser"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0c1", "email": "merch@supasheet.app", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b9',
    'authenticated',
    'authenticated',
    'ops@supasheet.app',
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
    '{"provider": "email", "providers": ["email"], "role": "fulfillment"}',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b9", "email": "ops@supasheet.app", "email_verified": false, "phone_verified": false}',
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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0c1", "email": "merch@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ac1'
  ),
  (
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b9',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b9',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b9", "email": "ops@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ac9'
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
on conflict do nothing;

----------------------------------------------------------------
-- Store settings (singleton)
--
-- Seeded first: the order, shipment and review triggers all read
-- their policy from here (stock reservation on confirm, the default
-- location, and whether reviews are auto-approved).
----------------------------------------------------------------
insert into
  store.store_settings (
    id,
    store_name,
    brand_color,
    support_email,
    support_phone,
    default_currency,
    default_tax_rate,
    prices_include_tax,
    free_shipping_threshold,
    standard_shipping_rate,
    low_stock_threshold,
    reserve_stock_on_confirm,
    auto_approve_reviews,
    return_window_days,
    order_prefix,
    timezone
  )
values
  (
    'eb000000-0000-0000-0000-000000000001',
    'Supasheet Store',
    '#111827',
    'help@supasheet.store',
    '+1-555-0100',
    'USD',
    8.5,
    false,
    150.00,
    9.95,
    5,
    true,
    false,
    30,
    'ORD',
    'UTC'
  );

----------------------------------------------------------------
-- Warehouses
----------------------------------------------------------------
insert into
  store.warehouses (
    id,
    code,
    name,
    address_line_1,
    city,
    region,
    postal_code,
    country,
    contact_email,
    contact_phone,
    is_active,
    is_default,
    fulfillment_priority,
    handling_time
  )
values
  (
    'd1000000-0000-0000-0000-000000000001',
    'MAIN',
    'Newark Fulfilment Centre',
    '4400 Dock Street',
    'Newark',
    'New Jersey',
    '07105',
    'United States',
    'newark@supasheet.store',
    '+1-555-0111',
    true,
    true,
    10,
    86400000
  ),
  (
    'd1000000-0000-0000-0000-000000000002',
    'WEST',
    'Reno Overflow',
    '900 Warehouse Row',
    'Reno',
    'Nevada',
    '89506',
    'United States',
    'reno@supasheet.store',
    '+1-555-0122',
    true,
    false,
    20,
    172800000
  ),
  (
    'd1000000-0000-0000-0000-000000000003',
    'EU1',
    'Rotterdam Hub',
    'Havenweg 12',
    'Rotterdam',
    'Zuid-Holland',
    '3011',
    'Netherlands',
    'rotterdam@supasheet.store',
    '+31-10-555-0133',
    true,
    false,
    30,
    172800000
  );

----------------------------------------------------------------
-- Brands
----------------------------------------------------------------
insert into
  store.brands (
    id,
    name,
    slug,
    description,
    website,
    support_email,
    country,
    is_active,
    sort_order,
    color
  )
values
  (
    'd2000000-0000-0000-0000-000000000001',
    'Aurora Audio',
    'aurora-audio',
    'Studio-grade headphones and monitors.',
    'https://auroraaudio.test',
    'hello@auroraaudio.test',
    'United States',
    true,
    10,
    '#6366f1'
  ),
  (
    'd2000000-0000-0000-0000-000000000002',
    'Northwind Tech',
    'northwind-tech',
    'Laptops, docks and the parts inside them.',
    'https://northwindtech.test',
    'hello@northwindtech.test',
    'United States',
    true,
    20,
    '#0ea5e9'
  ),
  (
    'd2000000-0000-0000-0000-000000000003',
    'Lumen Optics',
    'lumen-optics',
    'Cameras, lenses and lighting.',
    'https://lumenoptics.test',
    'hello@lumenoptics.test',
    'Germany',
    true,
    30,
    '#f59e0b'
  ),
  (
    'd2000000-0000-0000-0000-000000000004',
    'Kestrel Outdoors',
    'kestrel-outdoors',
    'Packs, tents and things that survive rain.',
    'https://kestreloutdoors.test',
    'hello@kestreloutdoors.test',
    'Canada',
    true,
    40,
    '#22c55e'
  ),
  (
    'd2000000-0000-0000-0000-000000000005',
    'Vellum Paper Co',
    'vellum-paper-co',
    'Notebooks, pens and desk goods.',
    'https://vellumpaperco.test',
    'hello@vellumpaperco.test',
    'Japan',
    true,
    50,
    '#ec4899'
  ),
  (
    'd2000000-0000-0000-0000-000000000006',
    'Terra Kitchen',
    'terra-kitchen',
    'Cookware built to be handed down.',
    'https://terrakitchen.test',
    'hello@terrakitchen.test',
    'Italy',
    true,
    60,
    '#ef4444'
  ),
  (
    'd2000000-0000-0000-0000-000000000007',
    'Halcyon Home',
    'halcyon-home',
    'Lighting and small furniture.',
    'https://halcyonhome.test',
    'hello@halcyonhome.test',
    'Denmark',
    true,
    70,
    '#14b8a6'
  ),
  (
    'd2000000-0000-0000-0000-000000000008',
    'Vertex Fitness',
    'vertex-fitness',
    'Home gym equipment.',
    'https://vertexfitness.test',
    'hello@vertexfitness.test',
    'United Kingdom',
    true,
    80,
    '#8b5cf6'
  );

----------------------------------------------------------------
-- Categories (three levels: department -> aisle -> shelf)
----------------------------------------------------------------
insert into
  store.categories (
    id,
    parent_id,
    name,
    slug,
    description,
    is_active,
    show_in_menu,
    sort_order,
    seo_title
  )
values
  (
    'd3000000-0000-0000-0000-000000000001',
    null,
    'Audio',
    'audio',
    'Headphones, speakers and everything that makes a noise.',
    true,
    true,
    10,
    'Audio — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-000000000002',
    'd3000000-0000-0000-0000-000000000001',
    'Headphones',
    'headphones',
    'Over-ear, on-ear and in-ear.',
    true,
    false,
    11,
    'Headphones — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-000000000003',
    'd3000000-0000-0000-0000-000000000002',
    'Studio Monitors',
    'studio-monitors',
    'What the mix is actually checked on.',
    true,
    false,
    12,
    'Studio Monitors — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-000000000004',
    'd3000000-0000-0000-0000-000000000001',
    'Speakers',
    'speakers',
    'Desktop and bookshelf.',
    true,
    false,
    13,
    'Speakers — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-000000000005',
    null,
    'Computing',
    'computing',
    'Laptops, docks and the parts inside them.',
    true,
    true,
    20,
    'Computing — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-000000000006',
    'd3000000-0000-0000-0000-000000000005',
    'Laptops',
    'laptops',
    'Portable machines.',
    true,
    false,
    21,
    'Laptops — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-000000000007',
    'd3000000-0000-0000-0000-000000000005',
    'Accessories',
    'accessories',
    'Docks, hubs and cables.',
    true,
    false,
    22,
    'Accessories — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-000000000008',
    null,
    'Photography',
    'photography',
    'Cameras, lenses and lighting.',
    true,
    true,
    30,
    'Photography — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-000000000009',
    'd3000000-0000-0000-0000-000000000008',
    'Lenses',
    'lenses',
    'Glass for every mount.',
    true,
    false,
    31,
    'Lenses — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-00000000000a',
    null,
    'Outdoors',
    'outdoors',
    'Packs, tents and rain.',
    true,
    true,
    40,
    'Outdoors — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-00000000000b',
    null,
    'Home & Kitchen',
    'home--kitchen',
    'Cookware, lighting and small furniture.',
    true,
    true,
    50,
    'Home & Kitchen — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-00000000000c',
    'd3000000-0000-0000-0000-00000000000b',
    'Cookware',
    'cookware',
    'Pans that outlive the kitchen.',
    true,
    false,
    51,
    'Cookware — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-00000000000d',
    null,
    'Stationery',
    'stationery',
    'Notebooks, pens and desk goods.',
    true,
    true,
    60,
    'Stationery — Supasheet Store'
  ),
  (
    'd3000000-0000-0000-0000-00000000000e',
    null,
    'Fitness',
    'fitness',
    'Home gym equipment.',
    true,
    true,
    70,
    'Fitness — Supasheet Store'
  );

----------------------------------------------------------------
-- Discounts
--
-- used_count, redemption_rate and revenue_influenced are rollups:
-- the orders further down fill them in.
----------------------------------------------------------------
insert into
  store.discounts (
    id,
    code,
    name,
    description,
    discount_type,
    status,
    value,
    minimum_spend,
    usage_limit,
    usage_limit_per_customer,
    category_id,
    starts_on,
    ends_on,
    is_active,
    color
  )
values
  (
    'd9000000-0000-0000-0000-000000000001',
    'WELCOME10',
    'Welcome 10%',
    'First order discount for new accounts.',
    'percentage',
    'active',
    10,
    0,
    500,
    1,
    null,
    current_date - 300,
    current_date + 60,
    true,
    '#22c55e'
  ),
  (
    'd9000000-0000-0000-0000-000000000002',
    'FREESHIP',
    'Free shipping weekend',
    'Carriage on us, any basket.',
    'free_shipping',
    'active',
    0,
    0,
    null,
    2,
    null,
    current_date - 10,
    current_date + 4,
    true,
    '#0ea5e9'
  ),
  (
    'd9000000-0000-0000-0000-000000000003',
    'AUDIO20',
    'Audio department 20%',
    'Twenty percent off anything that makes a noise.',
    'percentage',
    'active',
    20,
    100,
    200,
    1,
    'd3000000-0000-0000-0000-000000000001',
    current_date - 25,
    current_date + 20,
    true,
    '#6366f1'
  ),
  (
    'd9000000-0000-0000-0000-000000000004',
    'SPRING25',
    'Spring sale',
    'Twenty-five off orders over 200.',
    'fixed_amount',
    'expired',
    25,
    200,
    300,
    1,
    null,
    current_date - 210,
    current_date - 150,
    true,
    '#f59e0b'
  ),
  (
    'd9000000-0000-0000-0000-000000000005',
    'BLACKFRIDAY',
    'Black Friday 30%',
    'The one everybody waits for.',
    'percentage',
    'expired',
    30,
    0,
    1000,
    1,
    null,
    current_date - 120,
    current_date - 112,
    true,
    '#111827'
  ),
  (
    'd9000000-0000-0000-0000-000000000006',
    'LAUNCH15',
    'Launch week 15%',
    'Scheduled for the next range launch.',
    'percentage',
    'scheduled',
    15,
    50,
    400,
    1,
    'd3000000-0000-0000-0000-000000000005',
    current_date + 14,
    current_date + 45,
    true,
    '#ec4899'
  );

----------------------------------------------------------------
-- Products
--
-- slug, published_at, variant_count and inventory_quantity are all
-- derived: store.trg_products_apply_defaults slugifies the name and
-- stamps publication, and the variants and stock ledger below roll
-- the counters up.
----------------------------------------------------------------
insert into
  store.products (
    id,
    name,
    brand_id,
    category_id,
    product_type,
    status,
    short_description,
    description,
    price,
    compare_at_price,
    currency,
    tax_rate,
    weight_grams,
    requires_shipping,
    is_featured,
    option_1_name,
    option_2_name,
    seo_title,
    tags,
    user_id,
    created_at
  )
values
  (
    'd4000000-0000-0000-0000-000000000001',
    'Aurora A1 Studio Headphones',
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000002',
    'variant',
    'active',
    'Headphones from Aurora.',
    '<p>Aurora A1 Studio Headphones. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    299.0,
    null,
    'USD',
    8.5,
    337,
    true,
    true,
    'Colour',
    null,
    'Aurora A1 Studio Headphones — Supasheet Store',
    '{"aurora"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '388 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000002',
    'Aurora A3 Reference Monitors',
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000003',
    'variant',
    'active',
    'Monitors from Aurora.',
    '<p>Aurora A3 Reference Monitors. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    749.0,
    null,
    'USD',
    8.5,
    474,
    true,
    true,
    'Finish',
    null,
    'Aurora A3 Reference Monitors — Supasheet Store',
    '{"aurora"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '376 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000003',
    'Aurora Nomad Wireless',
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000002',
    'variant',
    'active',
    'Wireless from Aurora.',
    '<p>Aurora Nomad Wireless. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    199.0,
    null,
    'USD',
    8.5,
    611,
    true,
    false,
    'Colour',
    null,
    'Aurora Nomad Wireless — Supasheet Store',
    '{"aurora"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '364 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000004',
    'Aurora Desk Speaker Pair',
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000004',
    'simple',
    'active',
    'Pair from Aurora.',
    '<p>Aurora Desk Speaker Pair. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    349.0,
    null,
    'USD',
    8.5,
    748,
    true,
    false,
    null,
    null,
    'Aurora Desk Speaker Pair — Supasheet Store',
    '{"aurora"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '352 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000005',
    'Aurora In-Ear Pro',
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000002',
    'variant',
    'active',
    'Pro from Aurora.',
    '<p>Aurora In-Ear Pro. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    129.0,
    154.8,
    'USD',
    8.5,
    885,
    true,
    false,
    'Size',
    null,
    'Aurora In-Ear Pro — Supasheet Store',
    '{"aurora"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '340 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000006',
    'Northwind Slate 14',
    'd2000000-0000-0000-0000-000000000002',
    'd3000000-0000-0000-0000-000000000006',
    'variant',
    'active',
    '14 from Northwind.',
    '<p>Northwind Slate 14. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    1499.0,
    null,
    'USD',
    8.5,
    1022,
    true,
    true,
    'Memory',
    'Storage',
    'Northwind Slate 14 — Supasheet Store',
    '{"northwind"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '328 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000007',
    'Northwind Slate 16',
    'd2000000-0000-0000-0000-000000000002',
    'd3000000-0000-0000-0000-000000000006',
    'variant',
    'active',
    '16 from Northwind.',
    '<p>Northwind Slate 16. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    1899.0,
    null,
    'USD',
    8.5,
    1159,
    true,
    false,
    'Memory',
    'Storage',
    'Northwind Slate 16 — Supasheet Store',
    '{"northwind"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '316 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000008',
    'Northwind Dock 8-Port',
    'd2000000-0000-0000-0000-000000000002',
    'd3000000-0000-0000-0000-000000000007',
    'simple',
    'active',
    '8-Port from Northwind.',
    '<p>Northwind Dock 8-Port. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    189.0,
    null,
    'USD',
    8.5,
    1296,
    true,
    false,
    null,
    null,
    'Northwind Dock 8-Port — Supasheet Store',
    '{"northwind"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '304 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000009',
    'Northwind USB-C Cable 2m',
    'd2000000-0000-0000-0000-000000000002',
    'd3000000-0000-0000-0000-000000000007',
    'variant',
    'active',
    '2m from Northwind.',
    '<p>Northwind USB-C Cable 2m. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    24.0,
    null,
    'USD',
    8.5,
    1433,
    true,
    false,
    'Colour',
    null,
    'Northwind USB-C Cable 2m — Supasheet Store',
    '{"northwind"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '292 days'
  ),
  (
    'd4000000-0000-0000-0000-00000000000a',
    'Northwind Travel Charger',
    'd2000000-0000-0000-0000-000000000002',
    'd3000000-0000-0000-0000-000000000007',
    'simple',
    'active',
    'Charger from Northwind.',
    '<p>Northwind Travel Charger. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    79.0,
    94.8,
    'USD',
    8.5,
    1570,
    true,
    false,
    null,
    null,
    'Northwind Travel Charger — Supasheet Store',
    '{"northwind"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '280 days'
  ),
  (
    'd4000000-0000-0000-0000-00000000000b',
    'Lumen 35mm f/1.8',
    'd2000000-0000-0000-0000-000000000003',
    'd3000000-0000-0000-0000-000000000009',
    'variant',
    'active',
    'f/1.8 from Lumen.',
    '<p>Lumen 35mm f/1.8. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    449.0,
    null,
    'USD',
    8.5,
    1707,
    true,
    false,
    'Mount',
    null,
    'Lumen 35mm f/1.8 — Supasheet Store',
    '{"lumen"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '268 days'
  ),
  (
    'd4000000-0000-0000-0000-00000000000c',
    'Lumen 85mm f/1.4',
    'd2000000-0000-0000-0000-000000000003',
    'd3000000-0000-0000-0000-000000000009',
    'variant',
    'active',
    'f/1.4 from Lumen.',
    '<p>Lumen 85mm f/1.4. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    899.0,
    null,
    'USD',
    8.5,
    1844,
    true,
    true,
    'Mount',
    null,
    'Lumen 85mm f/1.4 — Supasheet Store',
    '{"lumen"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '256 days'
  ),
  (
    'd4000000-0000-0000-0000-00000000000d',
    'Lumen Field Light Kit',
    'd2000000-0000-0000-0000-000000000003',
    'd3000000-0000-0000-0000-000000000008',
    'simple',
    'active',
    'Kit from Lumen.',
    '<p>Lumen Field Light Kit. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    329.0,
    null,
    'USD',
    8.5,
    1981,
    true,
    false,
    null,
    null,
    'Lumen Field Light Kit — Supasheet Store',
    '{"lumen"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '244 days'
  ),
  (
    'd4000000-0000-0000-0000-00000000000e',
    'Lumen Carbon Tripod',
    'd2000000-0000-0000-0000-000000000003',
    'd3000000-0000-0000-0000-000000000008',
    'simple',
    'active',
    'Tripod from Lumen.',
    '<p>Lumen Carbon Tripod. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    279.0,
    null,
    'USD',
    8.5,
    2118,
    true,
    false,
    null,
    null,
    'Lumen Carbon Tripod — Supasheet Store',
    '{"lumen"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '232 days'
  ),
  (
    'd4000000-0000-0000-0000-00000000000f',
    'Kestrel Ridge 45 Pack',
    'd2000000-0000-0000-0000-000000000004',
    'd3000000-0000-0000-0000-00000000000a',
    'variant',
    'active',
    'Pack from Kestrel.',
    '<p>Kestrel Ridge 45 Pack. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    239.0,
    286.8,
    'USD',
    8.5,
    2255,
    true,
    false,
    'Colour',
    null,
    'Kestrel Ridge 45 Pack — Supasheet Store',
    '{"kestrel"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '220 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000010',
    'Kestrel Two-Person Tent',
    'd2000000-0000-0000-0000-000000000004',
    'd3000000-0000-0000-0000-00000000000a',
    'simple',
    'active',
    'Tent from Kestrel.',
    '<p>Kestrel Two-Person Tent. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    479.0,
    null,
    'USD',
    8.5,
    2392,
    true,
    false,
    null,
    null,
    'Kestrel Two-Person Tent — Supasheet Store',
    '{"kestrel"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '208 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000011',
    'Kestrel Rain Shell',
    'd2000000-0000-0000-0000-000000000004',
    'd3000000-0000-0000-0000-00000000000a',
    'variant',
    'active',
    'Shell from Kestrel.',
    '<p>Kestrel Rain Shell. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    189.0,
    null,
    'USD',
    8.5,
    2529,
    true,
    false,
    'Size',
    null,
    'Kestrel Rain Shell — Supasheet Store',
    '{"kestrel"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '196 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000012',
    'Vellum Hardcover Notebook',
    'd2000000-0000-0000-0000-000000000005',
    'd3000000-0000-0000-0000-00000000000d',
    'variant',
    'active',
    'Notebook from Vellum.',
    '<p>Vellum Hardcover Notebook. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    28.0,
    null,
    'USD',
    8.5,
    2666,
    true,
    false,
    'Colour',
    null,
    'Vellum Hardcover Notebook — Supasheet Store',
    '{"vellum"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '184 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000013',
    'Vellum Fountain Pen',
    'd2000000-0000-0000-0000-000000000005',
    'd3000000-0000-0000-0000-00000000000d',
    'simple',
    'active',
    'Pen from Vellum.',
    '<p>Vellum Fountain Pen. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    89.0,
    null,
    'USD',
    8.5,
    2803,
    true,
    false,
    null,
    null,
    'Vellum Fountain Pen — Supasheet Store',
    '{"vellum"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '172 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000014',
    'Vellum Desk Mat',
    'd2000000-0000-0000-0000-000000000005',
    'd3000000-0000-0000-0000-00000000000d',
    'simple',
    'active',
    'Mat from Vellum.',
    '<p>Vellum Desk Mat. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    64.0,
    76.8,
    'USD',
    8.5,
    2940,
    true,
    false,
    null,
    null,
    'Vellum Desk Mat — Supasheet Store',
    '{"vellum"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '160 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000015',
    'Terra 28cm Skillet',
    'd2000000-0000-0000-0000-000000000006',
    'd3000000-0000-0000-0000-00000000000c',
    'simple',
    'active',
    'Skillet from Terra.',
    '<p>Terra 28cm Skillet. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    159.0,
    null,
    'USD',
    8.5,
    3077,
    true,
    true,
    null,
    null,
    'Terra 28cm Skillet — Supasheet Store',
    '{"terra"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '148 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000016',
    'Terra Dutch Oven 5L',
    'd2000000-0000-0000-0000-000000000006',
    'd3000000-0000-0000-0000-00000000000c',
    'variant',
    'active',
    '5L from Terra.',
    '<p>Terra Dutch Oven 5L. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    289.0,
    null,
    'USD',
    8.5,
    214,
    true,
    false,
    'Colour',
    null,
    'Terra Dutch Oven 5L — Supasheet Store',
    '{"terra"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '136 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000017',
    'Terra Knife Block Set',
    'd2000000-0000-0000-0000-000000000006',
    'd3000000-0000-0000-0000-00000000000c',
    'simple',
    'active',
    'Set from Terra.',
    '<p>Terra Knife Block Set. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    349.0,
    null,
    'USD',
    8.5,
    351,
    true,
    false,
    null,
    null,
    'Terra Knife Block Set — Supasheet Store',
    '{"terra"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '124 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000018',
    'Halcyon Arc Floor Lamp',
    'd2000000-0000-0000-0000-000000000007',
    'd3000000-0000-0000-0000-00000000000b',
    'variant',
    'active',
    'Lamp from Halcyon.',
    '<p>Halcyon Arc Floor Lamp. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    419.0,
    null,
    'USD',
    8.5,
    488,
    true,
    false,
    'Finish',
    null,
    'Halcyon Arc Floor Lamp — Supasheet Store',
    '{"halcyon"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '112 days'
  ),
  (
    'd4000000-0000-0000-0000-000000000019',
    'Halcyon Table Lamp',
    'd2000000-0000-0000-0000-000000000007',
    'd3000000-0000-0000-0000-00000000000b',
    'simple',
    'active',
    'Lamp from Halcyon.',
    '<p>Halcyon Table Lamp. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    189.0,
    226.8,
    'USD',
    8.5,
    625,
    true,
    false,
    null,
    null,
    'Halcyon Table Lamp — Supasheet Store',
    '{"halcyon"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '100 days'
  ),
  (
    'd4000000-0000-0000-0000-00000000001a',
    'Vertex Adjustable Dumbbells',
    'd2000000-0000-0000-0000-000000000008',
    'd3000000-0000-0000-0000-00000000000e',
    'simple',
    'active',
    'Dumbbells from Vertex.',
    '<p>Vertex Adjustable Dumbbells. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    599.0,
    null,
    'USD',
    8.5,
    762,
    true,
    false,
    null,
    null,
    'Vertex Adjustable Dumbbells — Supasheet Store',
    '{"vertex"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '88 days'
  ),
  (
    'd4000000-0000-0000-0000-00000000001b',
    'Aurora A5 Prototype',
    'd2000000-0000-0000-0000-000000000001',
    'd3000000-0000-0000-0000-000000000002',
    'variant',
    'draft',
    'Prototype from Aurora.',
    '<p>Aurora A5 Prototype. Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    899.0,
    null,
    'USD',
    8.5,
    899,
    true,
    false,
    'Colour',
    null,
    'Aurora A5 Prototype — Supasheet Store',
    '{"aurora"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '76 days'
  ),
  (
    'd4000000-0000-0000-0000-00000000001c',
    'Northwind Slate 13 (2023)',
    'd2000000-0000-0000-0000-000000000002',
    'd3000000-0000-0000-0000-000000000006',
    'simple',
    'archived',
    '(2023) from Northwind.',
    '<p>Northwind Slate 13 (2023). Built to be used every day and to keep working after it has been.</p><p>Ships from our Newark or Rotterdam warehouse depending on where you are.</p>',
    1199.0,
    null,
    'USD',
    8.5,
    1036,
    true,
    false,
    null,
    null,
    'Northwind Slate 13 (2023) — Supasheet Store',
    '{"northwind"}',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0c1',
    current_timestamp - interval '64 days'
  );

----------------------------------------------------------------
-- Product costs (the 1:1 extension only the owner and merchandising
-- can read)
----------------------------------------------------------------
insert into
  store.product_costs (
    id,
    product_id,
    unit_cost,
    last_purchase_price,
    margin_percent,
    supplier_name,
    supplier_sku,
    lead_time_days,
    minimum_order_quantity
  )
values
  (
    'd6000000-0000-0000-0000-000000000001',
    'd4000000-0000-0000-0000-000000000001',
    118.0,
    115.64,
    60.5,
    'Pacific Sourcing',
    'SUP-1007',
    10,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000002',
    'd4000000-0000-0000-0000-000000000002',
    310.0,
    303.8,
    58.6,
    'Hansa Import',
    'SUP-1014',
    13,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000003',
    'd4000000-0000-0000-0000-000000000003',
    74.0,
    72.52,
    62.8,
    'Atlas Components',
    'SUP-1021',
    16,
    10
  ),
  (
    'd6000000-0000-0000-0000-000000000004',
    'd4000000-0000-0000-0000-000000000004',
    140.0,
    137.2,
    59.9,
    'Kestrel Direct',
    'SUP-1028',
    19,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000005',
    'd4000000-0000-0000-0000-000000000005',
    44.0,
    43.12,
    65.9,
    'Meridian Trading',
    'SUP-1035',
    22,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000006',
    'd4000000-0000-0000-0000-000000000006',
    940.0,
    921.2,
    37.3,
    'Pacific Sourcing',
    'SUP-1042',
    25,
    10
  ),
  (
    'd6000000-0000-0000-0000-000000000007',
    'd4000000-0000-0000-0000-000000000007',
    1180.0,
    1156.4,
    37.9,
    'Hansa Import',
    'SUP-1049',
    28,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000008',
    'd4000000-0000-0000-0000-000000000008',
    72.0,
    70.56,
    61.9,
    'Atlas Components',
    'SUP-1056',
    31,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000009',
    'd4000000-0000-0000-0000-000000000009',
    6.0,
    5.88,
    75.0,
    'Kestrel Direct',
    'SUP-1063',
    34,
    10
  ),
  (
    'd6000000-0000-0000-0000-00000000000a',
    'd4000000-0000-0000-0000-00000000000a',
    28.0,
    27.44,
    64.6,
    'Meridian Trading',
    'SUP-1070',
    7,
    1
  ),
  (
    'd6000000-0000-0000-0000-00000000000b',
    'd4000000-0000-0000-0000-00000000000b',
    205.0,
    200.9,
    54.3,
    'Pacific Sourcing',
    'SUP-1077',
    10,
    1
  ),
  (
    'd6000000-0000-0000-0000-00000000000c',
    'd4000000-0000-0000-0000-00000000000c',
    430.0,
    421.4,
    52.2,
    'Hansa Import',
    'SUP-1084',
    13,
    10
  ),
  (
    'd6000000-0000-0000-0000-00000000000d',
    'd4000000-0000-0000-0000-00000000000d',
    138.0,
    135.24,
    58.1,
    'Atlas Components',
    'SUP-1091',
    16,
    1
  ),
  (
    'd6000000-0000-0000-0000-00000000000e',
    'd4000000-0000-0000-0000-00000000000e',
    102.0,
    99.96,
    63.4,
    'Kestrel Direct',
    'SUP-1098',
    19,
    1
  ),
  (
    'd6000000-0000-0000-0000-00000000000f',
    'd4000000-0000-0000-0000-00000000000f',
    88.0,
    86.24,
    63.2,
    'Meridian Trading',
    'SUP-1105',
    22,
    10
  ),
  (
    'd6000000-0000-0000-0000-000000000010',
    'd4000000-0000-0000-0000-000000000010',
    198.0,
    194.04,
    58.7,
    'Pacific Sourcing',
    'SUP-1112',
    25,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000011',
    'd4000000-0000-0000-0000-000000000011',
    66.0,
    64.68,
    65.1,
    'Hansa Import',
    'SUP-1119',
    28,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000012',
    'd4000000-0000-0000-0000-000000000012',
    7.5,
    7.35,
    73.2,
    'Atlas Components',
    'SUP-1126',
    31,
    10
  ),
  (
    'd6000000-0000-0000-0000-000000000013',
    'd4000000-0000-0000-0000-000000000013',
    31.0,
    30.38,
    65.2,
    'Kestrel Direct',
    'SUP-1133',
    34,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000014',
    'd4000000-0000-0000-0000-000000000014',
    22.0,
    21.56,
    65.6,
    'Meridian Trading',
    'SUP-1140',
    7,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000015',
    'd4000000-0000-0000-0000-000000000015',
    58.0,
    56.84,
    63.5,
    'Pacific Sourcing',
    'SUP-1147',
    10,
    10
  ),
  (
    'd6000000-0000-0000-0000-000000000016',
    'd4000000-0000-0000-0000-000000000016',
    112.0,
    109.76,
    61.2,
    'Hansa Import',
    'SUP-1154',
    13,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000017',
    'd4000000-0000-0000-0000-000000000017',
    145.0,
    142.1,
    58.5,
    'Atlas Components',
    'SUP-1161',
    16,
    1
  ),
  (
    'd6000000-0000-0000-0000-000000000018',
    'd4000000-0000-0000-0000-000000000018',
    168.0,
    164.64,
    59.9,
    'Kestrel Direct',
    'SUP-1168',
    19,
    10
  ),
  (
    'd6000000-0000-0000-0000-000000000019',
    'd4000000-0000-0000-0000-000000000019',
    71.0,
    69.58,
    62.4,
    'Meridian Trading',
    'SUP-1175',
    22,
    1
  ),
  (
    'd6000000-0000-0000-0000-00000000001a',
    'd4000000-0000-0000-0000-00000000001a',
    268.0,
    262.64,
    55.3,
    'Pacific Sourcing',
    'SUP-1182',
    25,
    1
  ),
  (
    'd6000000-0000-0000-0000-00000000001b',
    'd4000000-0000-0000-0000-00000000001b',
    390.0,
    382.2,
    56.6,
    'Hansa Import',
    'SUP-1189',
    28,
    10
  ),
  (
    'd6000000-0000-0000-0000-00000000001c',
    'd4000000-0000-0000-0000-00000000001c',
    760.0,
    744.8,
    36.6,
    'Atlas Components',
    'SUP-1196',
    31,
    1
  );

----------------------------------------------------------------
-- Variants
--
-- price, weight and the readable name are left out where the parent
-- already answers them: store.trg_variants_apply_defaults falls back
-- to the product, builds the label from the options, and makes the
-- first variant of each product its default.
----------------------------------------------------------------
insert into
  store.product_variants (
    id,
    product_id,
    sku,
    option_1,
    option_2,
    price,
    barcode,
    is_active,
    position
  )
values
  (
    'd5000000-0000-0000-0000-000000000001',
    'd4000000-0000-0000-0000-000000000001',
    'AA-001-BLK',
    'Black',
    null,
    299.0,
    '500000007919',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000002',
    'd4000000-0000-0000-0000-000000000001',
    'AA-001-SLV',
    'Silver',
    null,
    299.0,
    '500000015838',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-000000000003',
    'd4000000-0000-0000-0000-000000000001',
    'AA-001-MNB',
    'Midnight Blue',
    null,
    309.0,
    '500000023757',
    true,
    3
  ),
  (
    'd5000000-0000-0000-0000-000000000004',
    'd4000000-0000-0000-0000-000000000002',
    'AA-002-WAL',
    'Walnut',
    null,
    749.0,
    '500000031676',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000005',
    'd4000000-0000-0000-0000-000000000002',
    'AA-002-CHR',
    'Charcoal',
    null,
    749.0,
    '500000039595',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-000000000006',
    'd4000000-0000-0000-0000-000000000003',
    'AN-003-BLK',
    'Black',
    null,
    199.0,
    '500000047514',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000007',
    'd4000000-0000-0000-0000-000000000003',
    'AN-003-SND',
    'Sand',
    null,
    199.0,
    '500000055433',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-000000000008',
    'd4000000-0000-0000-0000-000000000004',
    'AD-004-STD',
    null,
    null,
    349.0,
    '500000063352',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000009',
    'd4000000-0000-0000-0000-000000000005',
    'AI-005-S',
    'Small',
    null,
    129.0,
    '500000071271',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000000a',
    'd4000000-0000-0000-0000-000000000005',
    'AI-005-M',
    'Medium',
    null,
    129.0,
    '500000079190',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-00000000000b',
    'd4000000-0000-0000-0000-000000000005',
    'AI-005-L',
    'Large',
    null,
    129.0,
    '500000087109',
    true,
    3
  ),
  (
    'd5000000-0000-0000-0000-00000000000c',
    'd4000000-0000-0000-0000-000000000006',
    'NS-006-16512',
    '16GB',
    '512GB',
    1499.0,
    '500000095028',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000000d',
    'd4000000-0000-0000-0000-000000000006',
    'NS-006-321TB',
    '32GB',
    '1TB',
    1899.0,
    '500000102947',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-00000000000e',
    'd4000000-0000-0000-0000-000000000007',
    'NS-007-321TB',
    '32GB',
    '1TB',
    1899.0,
    '500000110866',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000000f',
    'd4000000-0000-0000-0000-000000000007',
    'NS-007-642TB',
    '64GB',
    '2TB',
    2499.0,
    '500000118785',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-000000000010',
    'd4000000-0000-0000-0000-000000000008',
    'ND-008-STD',
    null,
    null,
    189.0,
    '500000126704',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000011',
    'd4000000-0000-0000-0000-000000000009',
    'NU-009-BLK',
    'Black',
    null,
    24.0,
    '500000134623',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000012',
    'd4000000-0000-0000-0000-000000000009',
    'NU-009-WHT',
    'White',
    null,
    24.0,
    '500000142542',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-000000000013',
    'd4000000-0000-0000-0000-00000000000a',
    'NT-010-STD',
    null,
    null,
    79.0,
    '500000150461',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000014',
    'd4000000-0000-0000-0000-00000000000b',
    'L3-011-E',
    'E-mount',
    null,
    449.0,
    '500000158380',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000015',
    'd4000000-0000-0000-0000-00000000000b',
    'L3-011-RF',
    'RF-mount',
    null,
    449.0,
    '500000166299',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-000000000016',
    'd4000000-0000-0000-0000-00000000000b',
    'L3-011-Z',
    'Z-mount',
    null,
    449.0,
    '500000174218',
    true,
    3
  ),
  (
    'd5000000-0000-0000-0000-000000000017',
    'd4000000-0000-0000-0000-00000000000c',
    'L8-012-E',
    'E-mount',
    null,
    899.0,
    '500000182137',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000018',
    'd4000000-0000-0000-0000-00000000000c',
    'L8-012-RF',
    'RF-mount',
    null,
    899.0,
    '500000190056',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-000000000019',
    'd4000000-0000-0000-0000-00000000000d',
    'LF-013-STD',
    null,
    null,
    329.0,
    '500000197975',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000001a',
    'd4000000-0000-0000-0000-00000000000e',
    'LC-014-STD',
    null,
    null,
    279.0,
    '500000205894',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000001b',
    'd4000000-0000-0000-0000-00000000000f',
    'KR-015-MOS',
    'Moss',
    null,
    239.0,
    '500000213813',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000001c',
    'd4000000-0000-0000-0000-00000000000f',
    'KR-015-SLT',
    'Slate',
    null,
    239.0,
    '500000221732',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-00000000001d',
    'd4000000-0000-0000-0000-000000000010',
    'KT-016-STD',
    null,
    null,
    479.0,
    '500000229651',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000001e',
    'd4000000-0000-0000-0000-000000000011',
    'KR-017-S',
    'S',
    null,
    189.0,
    '500000237570',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000001f',
    'd4000000-0000-0000-0000-000000000011',
    'KR-017-M',
    'M',
    null,
    189.0,
    '500000245489',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-000000000020',
    'd4000000-0000-0000-0000-000000000011',
    'KR-017-L',
    'L',
    null,
    189.0,
    '500000253408',
    true,
    3
  ),
  (
    'd5000000-0000-0000-0000-000000000021',
    'd4000000-0000-0000-0000-000000000011',
    'KR-017-XL',
    'XL',
    null,
    189.0,
    '500000261327',
    true,
    4
  ),
  (
    'd5000000-0000-0000-0000-000000000022',
    'd4000000-0000-0000-0000-000000000012',
    'VH-018-NVY',
    'Navy',
    null,
    28.0,
    '500000269246',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000023',
    'd4000000-0000-0000-0000-000000000012',
    'VH-018-OXB',
    'Oxblood',
    null,
    28.0,
    '500000277165',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-000000000024',
    'd4000000-0000-0000-0000-000000000012',
    'VH-018-FST',
    'Forest',
    null,
    28.0,
    '500000285084',
    true,
    3
  ),
  (
    'd5000000-0000-0000-0000-000000000025',
    'd4000000-0000-0000-0000-000000000013',
    'VF-019-STD',
    null,
    null,
    89.0,
    '500000293003',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000026',
    'd4000000-0000-0000-0000-000000000014',
    'VD-020-STD',
    null,
    null,
    64.0,
    '500000300922',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000027',
    'd4000000-0000-0000-0000-000000000015',
    'T2-021-STD',
    null,
    null,
    159.0,
    '500000308841',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000028',
    'd4000000-0000-0000-0000-000000000016',
    'TD-022-CRM',
    'Cream',
    null,
    289.0,
    '500000316760',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000029',
    'd4000000-0000-0000-0000-000000000016',
    'TD-022-INK',
    'Ink',
    null,
    289.0,
    '500000324679',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-00000000002a',
    'd4000000-0000-0000-0000-000000000017',
    'TK-023-STD',
    null,
    null,
    349.0,
    '500000332598',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000002b',
    'd4000000-0000-0000-0000-000000000018',
    'HA-024-BRS',
    'Brass',
    null,
    419.0,
    '500000340517',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000002c',
    'd4000000-0000-0000-0000-000000000018',
    'HA-024-BLK',
    'Black',
    null,
    419.0,
    '500000348436',
    true,
    2
  ),
  (
    'd5000000-0000-0000-0000-00000000002d',
    'd4000000-0000-0000-0000-000000000019',
    'HT-025-STD',
    null,
    null,
    189.0,
    '500000356355',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000002e',
    'd4000000-0000-0000-0000-00000000001a',
    'VA-026-STD',
    null,
    null,
    599.0,
    '500000364274',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-00000000002f',
    'd4000000-0000-0000-0000-00000000001b',
    'AA-027-BLK',
    'Black',
    null,
    899.0,
    '500000372193',
    true,
    1
  ),
  (
    'd5000000-0000-0000-0000-000000000030',
    'd4000000-0000-0000-0000-00000000001c',
    'NS-028-STD',
    null,
    null,
    1199.0,
    '500000380112',
    true,
    1
  );

----------------------------------------------------------------
-- Opening stock
--
-- Everything the store sells arrives the same way it would in real
-- life: as a goods-in movement. store.trg_inventory_movements_apply
-- creates the level row on first receipt and keeps on_hand in step,
-- and the level rolls up to the variant and then to the product.
----------------------------------------------------------------
insert into
  store.inventory_movements (
    variant_id,
    warehouse_id,
    movement_type,
    quantity,
    unit_cost,
    reference,
    note,
    occurred_at
  )
values
  (
    'd5000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    73,
    118.0,
    'PO-OPEN-001',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000002',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    86,
    118.0,
    'PO-OPEN-001',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000002',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    34,
    118.0,
    'PO-OPEN-001',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000003',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    99,
    118.0,
    'PO-OPEN-001',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000003',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    30,
    118.0,
    'PO-OPEN-001',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000004',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    112,
    310.0,
    'PO-OPEN-002',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000004',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    48,
    310.0,
    'PO-OPEN-002',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000005',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    125,
    310.0,
    'PO-OPEN-002',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000006',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    138,
    74.0,
    'PO-OPEN-003',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000006',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    22,
    74.0,
    'PO-OPEN-003',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000006',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    15,
    74.0,
    'PO-OPEN-003',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000007',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    71,
    74.0,
    'PO-OPEN-003',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000008',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    84,
    140.0,
    'PO-OPEN-004',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000008',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    36,
    140.0,
    'PO-OPEN-004',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000009',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    97,
    44.0,
    'PO-OPEN-005',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000009',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    30,
    44.0,
    'PO-OPEN-005',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000000a',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    110,
    44.0,
    'PO-OPEN-005',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000000a',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    50,
    44.0,
    'PO-OPEN-005',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000000b',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    123,
    44.0,
    'PO-OPEN-005',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000000c',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    136,
    940.0,
    'PO-OPEN-006',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000000c',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    24,
    940.0,
    'PO-OPEN-006',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000000c',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    15,
    940.0,
    'PO-OPEN-006',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000000d',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    69,
    940.0,
    'PO-OPEN-006',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000000e',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    82,
    1180.0,
    'PO-OPEN-007',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000000e',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    38,
    1180.0,
    'PO-OPEN-007',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000000f',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    95,
    1180.0,
    'PO-OPEN-007',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000000f',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    30,
    1180.0,
    'PO-OPEN-007',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000010',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    108,
    72.0,
    'PO-OPEN-008',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000010',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    52,
    72.0,
    'PO-OPEN-008',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000011',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    121,
    6.0,
    'PO-OPEN-009',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000012',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    134,
    6.0,
    'PO-OPEN-009',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000012',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    26,
    6.0,
    'PO-OPEN-009',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000012',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    15,
    6.0,
    'PO-OPEN-009',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000013',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    67,
    28.0,
    'PO-OPEN-010',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000014',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    80,
    205.0,
    'PO-OPEN-011',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000014',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    40,
    205.0,
    'PO-OPEN-011',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000015',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    93,
    205.0,
    'PO-OPEN-011',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000015',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    30,
    205.0,
    'PO-OPEN-011',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000016',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    106,
    205.0,
    'PO-OPEN-011',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000016',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    54,
    205.0,
    'PO-OPEN-011',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000017',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    119,
    430.0,
    'PO-OPEN-012',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000018',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    132,
    430.0,
    'PO-OPEN-012',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000018',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    28,
    430.0,
    'PO-OPEN-012',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000018',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    15,
    430.0,
    'PO-OPEN-012',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000019',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    65,
    138.0,
    'PO-OPEN-013',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000001a',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    78,
    102.0,
    'PO-OPEN-014',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000001a',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    42,
    102.0,
    'PO-OPEN-014',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000001b',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    91,
    88.0,
    'PO-OPEN-015',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000001b',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    30,
    88.0,
    'PO-OPEN-015',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000001c',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    104,
    88.0,
    'PO-OPEN-015',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000001c',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    56,
    88.0,
    'PO-OPEN-015',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000001d',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    117,
    198.0,
    'PO-OPEN-016',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000001e',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    130,
    66.0,
    'PO-OPEN-017',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000001e',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    30,
    66.0,
    'PO-OPEN-017',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000001e',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    15,
    66.0,
    'PO-OPEN-017',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000001f',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    63,
    66.0,
    'PO-OPEN-017',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000020',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    76,
    66.0,
    'PO-OPEN-017',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000020',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    44,
    66.0,
    'PO-OPEN-017',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000021',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    89,
    66.0,
    'PO-OPEN-017',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000021',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    30,
    66.0,
    'PO-OPEN-017',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000022',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    102,
    7.5,
    'PO-OPEN-018',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000022',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    58,
    7.5,
    'PO-OPEN-018',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000023',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    115,
    7.5,
    'PO-OPEN-018',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000024',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    128,
    7.5,
    'PO-OPEN-018',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000024',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    32,
    7.5,
    'PO-OPEN-018',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000024',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    15,
    7.5,
    'PO-OPEN-018',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000025',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    61,
    31.0,
    'PO-OPEN-019',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000026',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    74,
    22.0,
    'PO-OPEN-020',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000026',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    46,
    22.0,
    'PO-OPEN-020',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000027',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    87,
    58.0,
    'PO-OPEN-021',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000027',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    30,
    58.0,
    'PO-OPEN-021',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000028',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    100,
    112.0,
    'PO-OPEN-022',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000028',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    20,
    112.0,
    'PO-OPEN-022',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000029',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    113,
    112.0,
    'PO-OPEN-022',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000002a',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    126,
    145.0,
    'PO-OPEN-023',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000002a',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    34,
    145.0,
    'PO-OPEN-023',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000002a',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    15,
    145.0,
    'PO-OPEN-023',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000002b',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    139,
    168.0,
    'PO-OPEN-024',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000002c',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    72,
    168.0,
    'PO-OPEN-024',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000002c',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    48,
    168.0,
    'PO-OPEN-024',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000002d',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    85,
    71.0,
    'PO-OPEN-025',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000002d',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    30,
    71.0,
    'PO-OPEN-025',
    'Opening stock',
    current_timestamp - interval '320 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000002e',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    98,
    268.0,
    'PO-OPEN-026',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000002e',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    22,
    268.0,
    'PO-OPEN-026',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-00000000002f',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    111,
    390.0,
    'PO-OPEN-027',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000030',
    'd1000000-0000-0000-0000-000000000001',
    'receipt',
    124,
    760.0,
    'PO-OPEN-028',
    'Opening stock',
    current_timestamp - interval '330 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000030',
    'd1000000-0000-0000-0000-000000000002',
    'receipt',
    36,
    760.0,
    'PO-OPEN-028',
    'Opening stock',
    current_timestamp - interval '325 days'
  ),
  (
    'd5000000-0000-0000-0000-000000000030',
    'd1000000-0000-0000-0000-000000000003',
    'receipt',
    15,
    760.0,
    'PO-OPEN-028',
    'Opening stock',
    current_timestamp - interval '320 days'
  );

-- Replenishment policy. The levels themselves were created by the
-- receipts above; this is the ops team saying when to reorder.
update store.inventory_levels l
set
  reorder_point = case
    when (l.on_hand % 7) = 0 then 40
    when (l.on_hand % 3) = 0 then 25
    else 10
  end,
  reorder_quantity = 50,
  bin_location = 'A-' || lpad(((l.on_hand % 20) + 1)::text, 2, '0') || '-' || lpad(((l.on_hand % 9) + 1)::text, 2, '0');

----------------------------------------------------------------
-- Customers
--
-- `name` is derived from first and last by
-- store.trg_customers_apply_defaults, and order_count, total_spent
-- and average_order_value are rollups the orders below fill in.
--
-- Two of them are wired to a login: Ada Lovelace is
-- user@supasheet.app and Marcus Feld is user1@supasheet.app. Signed
-- in as either, the module becomes a storefront account page.
----------------------------------------------------------------
insert into
  store.customers (
    id,
    email,
    first_name,
    last_name,
    phone,
    customer_group,
    status,
    accepts_marketing,
    country,
    preferred_currency,
    tags,
    user_id,
    created_at
  )
values
  (
    'd7000000-0000-0000-0000-000000000001',
    'ada.lovelace@example.test',
    'Ada',
    'Lovelace',
    '+1-555-2007',
    'registered',
    'active',
    true,
    'United States',
    'USD',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    current_timestamp - interval '391 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000002',
    'marcus.feld@example.test',
    'Marcus',
    'Feld',
    '+1-555-2014',
    'registered',
    'active',
    true,
    'United States',
    'USD',
    null,
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    current_timestamp - interval '382 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000003',
    'ines.sommer@example.test',
    'Ines',
    'Sommer',
    '+1-555-2021',
    'registered',
    'active',
    false,
    'United States',
    'USD',
    null,
    null,
    current_timestamp - interval '373 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000004',
    'tomas.doyle@example.test',
    'Tomas',
    'Doyle',
    '+1-555-2028',
    'registered',
    'active',
    true,
    'Canada',
    'USD',
    null,
    null,
    current_timestamp - interval '364 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000005',
    'yuki.diaz@example.test',
    'Yuki',
    'Diaz',
    '+1-555-2035',
    'registered',
    'active',
    true,
    'United Kingdom',
    'EUR',
    null,
    null,
    current_timestamp - interval '355 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000006',
    'nadia.zhang@example.test',
    'Nadia',
    'Zhang',
    '+1-555-2042',
    'registered',
    'active',
    false,
    'Germany',
    'EUR',
    null,
    null,
    current_timestamp - interval '346 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000007',
    'owen.osei@example.test',
    'Owen',
    'Osei',
    '+1-555-2049',
    'registered',
    'active',
    true,
    'Netherlands',
    'EUR',
    null,
    null,
    current_timestamp - interval '337 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000008',
    'priya.tanaka@example.test',
    'Priya',
    'Tanaka',
    '+1-555-2056',
    'registered',
    'active',
    true,
    'Spain',
    'EUR',
    null,
    null,
    current_timestamp - interval '328 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000009',
    'lars.marino@example.test',
    'Lars',
    'Marino',
    '+1-555-2063',
    'registered',
    'active',
    false,
    'Italy',
    'EUR',
    null,
    null,
    current_timestamp - interval '319 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000000a',
    'sofia.bauer@example.test',
    'Sofia',
    'Bauer',
    '+1-555-2070',
    'registered',
    'active',
    true,
    'Sweden',
    'EUR',
    null,
    null,
    current_timestamp - interval '310 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000000b',
    'ben.petrov@example.test',
    'Ben',
    'Petrov',
    '+1-555-2077',
    'registered',
    'active',
    true,
    'Australia',
    'USD',
    null,
    null,
    current_timestamp - interval '301 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000000c',
    'clara.serrano@example.test',
    'Clara',
    'Serrano',
    '+1-555-2084',
    'registered',
    'active',
    false,
    'United States',
    'USD',
    null,
    null,
    current_timestamp - interval '292 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000000d',
    'diego.popescu@example.test',
    'Diego',
    'Popescu',
    '+1-555-2091',
    'registered',
    'active',
    true,
    'United States',
    'USD',
    null,
    null,
    current_timestamp - interval '283 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000000e',
    'emma.rossi@example.test',
    'Emma',
    'Rossi',
    '+1-555-2098',
    'registered',
    'active',
    true,
    'United States',
    'USD',
    null,
    null,
    current_timestamp - interval '274 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000000f',
    'felix.vidal@example.test',
    'Felix',
    'Vidal',
    '+1-555-2105',
    'registered',
    'active',
    false,
    'United States',
    'USD',
    null,
    null,
    current_timestamp - interval '265 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000010',
    'greta.nilsen@example.test',
    'Greta',
    'Nilsen',
    '+1-555-2112',
    'registered',
    'active',
    true,
    'Canada',
    'USD',
    null,
    null,
    current_timestamp - interval '256 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000011',
    'hugo.lindqvist@example.test',
    'Hugo',
    'Lindqvist',
    '+1-555-2119',
    'registered',
    'active',
    true,
    'United Kingdom',
    'EUR',
    null,
    null,
    current_timestamp - interval '247 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000012',
    'iris.weiss@example.test',
    'Iris',
    'Weiss',
    '+1-555-2126',
    'registered',
    'active',
    false,
    'Germany',
    'EUR',
    null,
    null,
    current_timestamp - interval '238 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000013',
    'jonas.ivanova@example.test',
    'Jonas',
    'Ivanova',
    '+1-555-2133',
    'registered',
    'active',
    true,
    'Netherlands',
    'EUR',
    null,
    null,
    current_timestamp - interval '229 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000014',
    'kira.aziz@example.test',
    'Kira',
    'Aziz',
    '+1-555-2140',
    'member',
    'active',
    true,
    'Spain',
    'EUR',
    null,
    null,
    current_timestamp - interval '220 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000015',
    'liam.hart@example.test',
    'Liam',
    'Hart',
    '+1-555-2147',
    'member',
    'active',
    false,
    'Italy',
    'EUR',
    null,
    null,
    current_timestamp - interval '211 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000016',
    'mona.barros@example.test',
    'Mona',
    'Barros',
    '+1-555-2154',
    'member',
    'active',
    true,
    'Sweden',
    'EUR',
    null,
    null,
    current_timestamp - interval '202 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000017',
    'noah.raman@example.test',
    'Noah',
    'Raman',
    '+1-555-2161',
    'member',
    'active',
    true,
    'Australia',
    'USD',
    null,
    null,
    current_timestamp - interval '193 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000018',
    'olga.reyes@example.test',
    'Olga',
    'Reyes',
    '+1-555-2168',
    'member',
    'active',
    false,
    'United States',
    'USD',
    null,
    null,
    current_timestamp - interval '184 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000019',
    'pablo.novotny@example.test',
    'Pablo',
    'Novotny',
    '+1-555-2175',
    'member',
    'active',
    true,
    'United States',
    'USD',
    null,
    null,
    current_timestamp - interval '175 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000001a',
    'rosa.klein@example.test',
    'Rosa',
    'Klein',
    '+1-555-2182',
    'member',
    'active',
    true,
    'United States',
    'USD',
    null,
    null,
    current_timestamp - interval '166 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000001b',
    'sven.sundar@example.test',
    'Sven',
    'Sundar',
    '+1-555-2189',
    'member',
    'active',
    false,
    'United States',
    'USD',
    null,
    null,
    current_timestamp - interval '157 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000001c',
    'tara.kowalski@example.test',
    'Tara',
    'Kowalski',
    '+1-555-2196',
    'vip',
    'active',
    true,
    'Canada',
    'USD',
    '{"vip"}',
    null,
    current_timestamp - interval '148 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000001d',
    'umar.feld@example.test',
    'Umar',
    'Feld',
    '+1-555-2203',
    'vip',
    'inactive',
    true,
    'United Kingdom',
    'EUR',
    '{"vip"}',
    null,
    current_timestamp - interval '139 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000001e',
    'vera.brennan@example.test',
    'Vera',
    'Brennan',
    '+1-555-2210',
    'vip',
    'active',
    false,
    'Germany',
    'EUR',
    '{"vip"}',
    null,
    current_timestamp - interval '130 days'
  ),
  (
    'd7000000-0000-0000-0000-00000000001f',
    'wei.novak@example.test',
    'Wei',
    'Novak',
    '+1-555-2217',
    'vip',
    'inactive',
    true,
    'Netherlands',
    'EUR',
    '{"vip"}',
    null,
    current_timestamp - interval '121 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000020',
    'yara.moreau@example.test',
    'Yara',
    'Moreau',
    '+1-555-2224',
    'wholesale',
    'active',
    true,
    'Spain',
    'EUR',
    null,
    null,
    current_timestamp - interval '112 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000021',
    'zoe.farah@example.test',
    'Zoe',
    'Farah',
    '+1-555-2231',
    'wholesale',
    'blocked',
    false,
    'Italy',
    'EUR',
    null,
    null,
    current_timestamp - interval '103 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000022',
    'adam.berg@example.test',
    'Adam',
    'Berg',
    '+1-555-2238',
    'guest',
    'active',
    true,
    'Sweden',
    'EUR',
    null,
    null,
    current_timestamp - interval '94 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000023',
    'bella.saleh@example.test',
    'Bella',
    'Saleh',
    '+1-555-2245',
    'guest',
    'active',
    true,
    'Australia',
    'USD',
    null,
    null,
    current_timestamp - interval '85 days'
  ),
  (
    'd7000000-0000-0000-0000-000000000024',
    'cyrus.lovelace@example.test',
    'Cyrus',
    'Lovelace',
    '+1-555-2252',
    'registered',
    'active',
    false,
    'United States',
    'USD',
    null,
    null,
    current_timestamp - interval '76 days'
  );

----------------------------------------------------------------
-- Addresses
----------------------------------------------------------------
insert into
  store.addresses (
    id,
    customer_id,
    address_type,
    label,
    first_name,
    last_name,
    address_line_1,
    city,
    region,
    postal_code,
    country,
    phone,
    is_default
  )
values
  (
    'd8000000-0000-0000-0000-000000000001',
    'd7000000-0000-0000-0000-000000000001',
    'shipping',
    'Home',
    'Ada',
    'Haddad',
    '13 Feld Street',
    'Chicago',
    'IL',
    '60601',
    'United States',
    '+1-555-2007',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000002',
    'd7000000-0000-0000-0000-000000000002',
    'shipping',
    'Home',
    'Marcus',
    'Carter',
    '16 Barros Street',
    'Austin',
    'TX',
    '73301',
    'United States',
    '+1-555-2014',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000003',
    'd7000000-0000-0000-0000-000000000003',
    'shipping',
    'Home',
    'Ines',
    'Sommer',
    '19 Vidal Street',
    'Portland',
    'OR',
    '97201',
    'United States',
    '+1-555-2021',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000004',
    'd7000000-0000-0000-0000-000000000004',
    'shipping',
    'Home',
    'Tomas',
    'Doyle',
    '22 Tanaka Street',
    'Toronto',
    'ON',
    'M5H',
    'Canada',
    '+1-555-2028',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000005',
    'd7000000-0000-0000-0000-000000000004',
    'billing',
    'Billing',
    'Tomas',
    'Doyle',
    'PO Box 104',
    'Toronto',
    'ON',
    'M5H',
    'Canada',
    '+1-555-2028',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000006',
    'd7000000-0000-0000-0000-000000000005',
    'shipping',
    'Home',
    'Yuki',
    'Diaz',
    '25 Haddad Street',
    'London',
    null,
    'EC1A',
    'United Kingdom',
    '+1-555-2035',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000007',
    'd7000000-0000-0000-0000-000000000006',
    'shipping',
    'Home',
    'Nadia',
    'Zhang',
    '28 Brennan Street',
    'Berlin',
    null,
    '10115',
    'Germany',
    '+1-555-2042',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000008',
    'd7000000-0000-0000-0000-000000000007',
    'shipping',
    'Home',
    'Owen',
    'Osei',
    '31 Raman Street',
    'Amsterdam',
    null,
    '1011',
    'Netherlands',
    '+1-555-2049',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000009',
    'd7000000-0000-0000-0000-000000000008',
    'shipping',
    'Home',
    'Priya',
    'Tanaka',
    '34 Nilsen Street',
    'Madrid',
    null,
    '28001',
    'Spain',
    '+1-555-2056',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000000a',
    'd7000000-0000-0000-0000-000000000008',
    'billing',
    'Billing',
    'Priya',
    'Tanaka',
    'PO Box 108',
    'Madrid',
    null,
    '28001',
    'Spain',
    '+1-555-2056',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000000b',
    'd7000000-0000-0000-0000-000000000009',
    'shipping',
    'Home',
    'Lars',
    'Marino',
    '37 Marino Street',
    'Milan',
    null,
    '20121',
    'Italy',
    '+1-555-2063',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000000c',
    'd7000000-0000-0000-0000-00000000000a',
    'shipping',
    'Home',
    'Sofia',
    'Bauer',
    '40 Carter Street',
    'Stockholm',
    null,
    '111 20',
    'Sweden',
    '+1-555-2070',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000000d',
    'd7000000-0000-0000-0000-00000000000b',
    'shipping',
    'Home',
    'Ben',
    'Petrov',
    '43 Novak Street',
    'Sydney',
    'NSW',
    '2000',
    'Australia',
    '+1-555-2077',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000000e',
    'd7000000-0000-0000-0000-00000000000c',
    'shipping',
    'Home',
    'Clara',
    'Serrano',
    '46 Reyes Street',
    'New York',
    'NY',
    '10001',
    'United States',
    '+1-555-2084',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000000f',
    'd7000000-0000-0000-0000-00000000000c',
    'billing',
    'Billing',
    'Clara',
    'Serrano',
    'PO Box 112',
    'New York',
    'NY',
    '10001',
    'United States',
    '+1-555-2084',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000010',
    'd7000000-0000-0000-0000-00000000000d',
    'shipping',
    'Home',
    'Diego',
    'Popescu',
    '49 Lindqvist Street',
    'Chicago',
    'IL',
    '60601',
    'United States',
    '+1-555-2091',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000011',
    'd7000000-0000-0000-0000-00000000000e',
    'shipping',
    'Home',
    'Emma',
    'Rossi',
    '52 Bauer Street',
    'Austin',
    'TX',
    '73301',
    'United States',
    '+1-555-2098',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000012',
    'd7000000-0000-0000-0000-00000000000f',
    'shipping',
    'Home',
    'Felix',
    'Vidal',
    '55 Sommer Street',
    'Portland',
    'OR',
    '97201',
    'United States',
    '+1-555-2105',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000013',
    'd7000000-0000-0000-0000-000000000010',
    'shipping',
    'Home',
    'Greta',
    'Nilsen',
    '58 Moreau Street',
    'Toronto',
    'ON',
    'M5H',
    'Canada',
    '+1-555-2112',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000014',
    'd7000000-0000-0000-0000-000000000010',
    'billing',
    'Billing',
    'Greta',
    'Nilsen',
    'PO Box 116',
    'Toronto',
    'ON',
    'M5H',
    'Canada',
    '+1-555-2112',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000015',
    'd7000000-0000-0000-0000-000000000011',
    'shipping',
    'Home',
    'Hugo',
    'Lindqvist',
    '61 Novotny Street',
    'London',
    null,
    'EC1A',
    'United Kingdom',
    '+1-555-2119',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000016',
    'd7000000-0000-0000-0000-000000000012',
    'shipping',
    'Home',
    'Iris',
    'Weiss',
    '64 Weiss Street',
    'Berlin',
    null,
    '10115',
    'Germany',
    '+1-555-2126',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000017',
    'd7000000-0000-0000-0000-000000000013',
    'shipping',
    'Home',
    'Jonas',
    'Ivanova',
    '67 Petrov Street',
    'Amsterdam',
    null,
    '1011',
    'Netherlands',
    '+1-555-2133',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000018',
    'd7000000-0000-0000-0000-000000000014',
    'shipping',
    'Home',
    'Kira',
    'Aziz',
    '70 Doyle Street',
    'Madrid',
    null,
    '28001',
    'Spain',
    '+1-555-2140',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000019',
    'd7000000-0000-0000-0000-000000000014',
    'billing',
    'Billing',
    'Kira',
    'Aziz',
    'PO Box 120',
    'Madrid',
    null,
    '28001',
    'Spain',
    '+1-555-2140',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000001a',
    'd7000000-0000-0000-0000-000000000015',
    'shipping',
    'Home',
    'Liam',
    'Hart',
    '73 Farah Street',
    'Milan',
    null,
    '20121',
    'Italy',
    '+1-555-2147',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000001b',
    'd7000000-0000-0000-0000-000000000016',
    'shipping',
    'Home',
    'Mona',
    'Barros',
    '76 Klein Street',
    'Stockholm',
    null,
    '111 20',
    'Sweden',
    '+1-555-2154',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000001c',
    'd7000000-0000-0000-0000-000000000017',
    'shipping',
    'Home',
    'Noah',
    'Raman',
    '79 Ivanova Street',
    'Sydney',
    'NSW',
    '2000',
    'Australia',
    '+1-555-2161',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000001d',
    'd7000000-0000-0000-0000-000000000018',
    'shipping',
    'Home',
    'Olga',
    'Reyes',
    '82 Serrano Street',
    'New York',
    'NY',
    '10001',
    'United States',
    '+1-555-2168',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000001e',
    'd7000000-0000-0000-0000-000000000018',
    'billing',
    'Billing',
    'Olga',
    'Reyes',
    'PO Box 124',
    'New York',
    'NY',
    '10001',
    'United States',
    '+1-555-2168',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000001f',
    'd7000000-0000-0000-0000-000000000019',
    'shipping',
    'Home',
    'Pablo',
    'Novotny',
    '85 Diaz Street',
    'Chicago',
    'IL',
    '60601',
    'United States',
    '+1-555-2175',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000020',
    'd7000000-0000-0000-0000-00000000001a',
    'shipping',
    'Home',
    'Rosa',
    'Klein',
    '88 Berg Street',
    'Austin',
    'TX',
    '73301',
    'United States',
    '+1-555-2182',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000021',
    'd7000000-0000-0000-0000-00000000001b',
    'shipping',
    'Home',
    'Sven',
    'Sundar',
    '91 Sundar Street',
    'Portland',
    'OR',
    '97201',
    'United States',
    '+1-555-2189',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000022',
    'd7000000-0000-0000-0000-00000000001c',
    'shipping',
    'Home',
    'Tara',
    'Kowalski',
    '94 Aziz Street',
    'Toronto',
    'ON',
    'M5H',
    'Canada',
    '+1-555-2196',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000023',
    'd7000000-0000-0000-0000-00000000001c',
    'billing',
    'Billing',
    'Tara',
    'Kowalski',
    'PO Box 128',
    'Toronto',
    'ON',
    'M5H',
    'Canada',
    '+1-555-2196',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000024',
    'd7000000-0000-0000-0000-00000000001d',
    'shipping',
    'Home',
    'Umar',
    'Feld',
    '97 Popescu Street',
    'London',
    null,
    'EC1A',
    'United Kingdom',
    '+1-555-2203',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000025',
    'd7000000-0000-0000-0000-00000000001e',
    'shipping',
    'Home',
    'Vera',
    'Brennan',
    '100 Zhang Street',
    'Berlin',
    null,
    '10115',
    'Germany',
    '+1-555-2210',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000026',
    'd7000000-0000-0000-0000-00000000001f',
    'shipping',
    'Home',
    'Wei',
    'Novak',
    '103 Saleh Street',
    'Amsterdam',
    null,
    '1011',
    'Netherlands',
    '+1-555-2217',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000027',
    'd7000000-0000-0000-0000-000000000020',
    'shipping',
    'Home',
    'Yara',
    'Moreau',
    '106 Kowalski Street',
    'Madrid',
    null,
    '28001',
    'Spain',
    '+1-555-2224',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000028',
    'd7000000-0000-0000-0000-000000000020',
    'billing',
    'Billing',
    'Yara',
    'Moreau',
    'PO Box 132',
    'Madrid',
    null,
    '28001',
    'Spain',
    '+1-555-2224',
    true
  ),
  (
    'd8000000-0000-0000-0000-000000000029',
    'd7000000-0000-0000-0000-000000000021',
    'shipping',
    'Home',
    'Zoe',
    'Farah',
    '109 Hart Street',
    'Milan',
    null,
    '20121',
    'Italy',
    '+1-555-2231',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000002a',
    'd7000000-0000-0000-0000-000000000022',
    'shipping',
    'Home',
    'Adam',
    'Berg',
    '112 Rossi Street',
    'Stockholm',
    null,
    '111 20',
    'Sweden',
    '+1-555-2238',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000002b',
    'd7000000-0000-0000-0000-000000000023',
    'shipping',
    'Home',
    'Bella',
    'Saleh',
    '115 Osei Street',
    'Sydney',
    'NSW',
    '2000',
    'Australia',
    '+1-555-2245',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000002c',
    'd7000000-0000-0000-0000-000000000024',
    'shipping',
    'Home',
    'Cyrus',
    'Lovelace',
    '118 Lovelace Street',
    'New York',
    'NY',
    '10001',
    'United States',
    '+1-555-2252',
    true
  ),
  (
    'd8000000-0000-0000-0000-00000000002d',
    'd7000000-0000-0000-0000-000000000024',
    'billing',
    'Billing',
    'Cyrus',
    'Lovelace',
    'PO Box 136',
    'New York',
    'NY',
    '10001',
    'United States',
    '+1-555-2252',
    true
  );

-- Point each customer at their default addresses.
update store.customers c
set
  default_shipping_address_id = (
    select
      a.id
    from
      store.addresses a
    where
      a.customer_id = c.id
      and a.address_type = 'shipping'
    order by
      a.created_at
    limit
      1
  ),
  default_billing_address_id = (
    select
      a.id
    from
      store.addresses a
    where
      a.customer_id = c.id
      and a.address_type = 'billing'
    order by
      a.created_at
    limit
      1
  );

----------------------------------------------------------------
-- Orders
--
-- Every order is inserted as `pending` with a backdated placed_at,
-- and then walked forward in cohorts below. Nothing here sets a
-- money column: store.trg_order_items_rollup and
-- store.trg_orders_apply_defaults compute the subtotal, the tax, the
-- discount and the grand total from the lines and the code.
----------------------------------------------------------------
insert into
  store.orders (
    id,
    customer_id,
    email,
    channel,
    shipping_total,
    discount_id,
    shipping_address_id,
    billing_address_id,
    customer_note,
    placed_at,
    created_at
  )
select
  v.id,
  v.customer_id,
  c.email,
  v.channel,
  v.shipping_total,
  v.discount_id,
  c.default_shipping_address_id,
  c.default_billing_address_id,
  v.customer_note,
  v.placed_at,
  v.placed_at
from
  (
    values
      (
        'da000000-0000-0000-0000-000000000001'::uuid,
        'd7000000-0000-0000-0000-000000000008'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '9 days'
      ),
      (
        'da000000-0000-0000-0000-000000000002'::uuid,
        'd7000000-0000-0000-0000-00000000000f'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '10 days'
      ),
      (
        'da000000-0000-0000-0000-000000000003'::uuid,
        'd7000000-0000-0000-0000-000000000016'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '11 days'
      ),
      (
        'da000000-0000-0000-0000-000000000004'::uuid,
        'd7000000-0000-0000-0000-00000000001d'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        'd9000000-0000-0000-0000-000000000001'::uuid,
        null::text,
        current_timestamp - interval '13 days'
      ),
      (
        'da000000-0000-0000-0000-000000000005'::uuid,
        'd7000000-0000-0000-0000-000000000024'::uuid,
        'web'::store.sales_channel,
        0::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '15 days'
      ),
      (
        'da000000-0000-0000-0000-000000000006'::uuid,
        'd7000000-0000-0000-0000-000000000007'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '17 days'
      ),
      (
        'da000000-0000-0000-0000-000000000007'::uuid,
        'd7000000-0000-0000-0000-00000000000e'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '21 days'
      ),
      (
        'da000000-0000-0000-0000-000000000008'::uuid,
        'd7000000-0000-0000-0000-000000000015'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        'd9000000-0000-0000-0000-000000000001'::uuid,
        null::text,
        current_timestamp - interval '24 days'
      ),
      (
        'da000000-0000-0000-0000-000000000009'::uuid,
        'd7000000-0000-0000-0000-00000000001c'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '28 days'
      ),
      (
        'da000000-0000-0000-0000-00000000000a'::uuid,
        'd7000000-0000-0000-0000-000000000023'::uuid,
        'mobile_app'::store.sales_channel,
        0::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '32 days'
      ),
      (
        'da000000-0000-0000-0000-00000000000b'::uuid,
        'd7000000-0000-0000-0000-000000000006'::uuid,
        'mobile_app'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        'Please leave with the concierge.'::text,
        current_timestamp - interval '36 days'
      ),
      (
        'da000000-0000-0000-0000-00000000000c'::uuid,
        'd7000000-0000-0000-0000-00000000000d'::uuid,
        'mobile_app'::store.sales_channel,
        9.95::numeric,
        'd9000000-0000-0000-0000-000000000001'::uuid,
        null::text,
        current_timestamp - interval '41 days'
      ),
      (
        'da000000-0000-0000-0000-00000000000d'::uuid,
        'd7000000-0000-0000-0000-000000000014'::uuid,
        'mobile_app'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '46 days'
      ),
      (
        'da000000-0000-0000-0000-00000000000e'::uuid,
        'd7000000-0000-0000-0000-00000000001b'::uuid,
        'marketplace'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '52 days'
      ),
      (
        'da000000-0000-0000-0000-00000000000f'::uuid,
        'd7000000-0000-0000-0000-000000000022'::uuid,
        'marketplace'::store.sales_channel,
        0::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '58 days'
      ),
      (
        'da000000-0000-0000-0000-000000000010'::uuid,
        'd7000000-0000-0000-0000-000000000005'::uuid,
        'marketplace'::store.sales_channel,
        9.95::numeric,
        'd9000000-0000-0000-0000-000000000001'::uuid,
        null::text,
        current_timestamp - interval '64 days'
      ),
      (
        'da000000-0000-0000-0000-000000000011'::uuid,
        'd7000000-0000-0000-0000-00000000000c'::uuid,
        'pos'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '70 days'
      ),
      (
        'da000000-0000-0000-0000-000000000012'::uuid,
        'd7000000-0000-0000-0000-000000000013'::uuid,
        'pos'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '77 days'
      ),
      (
        'da000000-0000-0000-0000-000000000013'::uuid,
        'd7000000-0000-0000-0000-00000000001a'::uuid,
        'phone'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '84 days'
      ),
      (
        'da000000-0000-0000-0000-000000000014'::uuid,
        'd7000000-0000-0000-0000-000000000001'::uuid,
        'web'::store.sales_channel,
        0::numeric,
        'd9000000-0000-0000-0000-000000000001'::uuid,
        null::text,
        current_timestamp - interval '91 days'
      ),
      (
        'da000000-0000-0000-0000-000000000015'::uuid,
        'd7000000-0000-0000-0000-000000000004'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '98 days'
      ),
      (
        'da000000-0000-0000-0000-000000000016'::uuid,
        'd7000000-0000-0000-0000-00000000000b'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        'Please leave with the concierge.'::text,
        current_timestamp - interval '106 days'
      ),
      (
        'da000000-0000-0000-0000-000000000017'::uuid,
        'd7000000-0000-0000-0000-000000000012'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '114 days'
      ),
      (
        'da000000-0000-0000-0000-000000000018'::uuid,
        'd7000000-0000-0000-0000-000000000019'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        'd9000000-0000-0000-0000-000000000001'::uuid,
        null::text,
        current_timestamp - interval '122 days'
      ),
      (
        'da000000-0000-0000-0000-000000000019'::uuid,
        'd7000000-0000-0000-0000-000000000020'::uuid,
        'web'::store.sales_channel,
        0::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '131 days'
      ),
      (
        'da000000-0000-0000-0000-00000000001a'::uuid,
        'd7000000-0000-0000-0000-000000000003'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '139 days'
      ),
      (
        'da000000-0000-0000-0000-00000000001b'::uuid,
        'd7000000-0000-0000-0000-00000000000a'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '148 days'
      ),
      (
        'da000000-0000-0000-0000-00000000001c'::uuid,
        'd7000000-0000-0000-0000-000000000011'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        'd9000000-0000-0000-0000-000000000001'::uuid,
        null::text,
        current_timestamp - interval '158 days'
      ),
      (
        'da000000-0000-0000-0000-00000000001d'::uuid,
        'd7000000-0000-0000-0000-000000000018'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '167 days'
      ),
      (
        'da000000-0000-0000-0000-00000000001e'::uuid,
        'd7000000-0000-0000-0000-00000000001f'::uuid,
        'mobile_app'::store.sales_channel,
        0::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '177 days'
      ),
      (
        'da000000-0000-0000-0000-00000000001f'::uuid,
        'd7000000-0000-0000-0000-000000000002'::uuid,
        'mobile_app'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '187 days'
      ),
      (
        'da000000-0000-0000-0000-000000000020'::uuid,
        'd7000000-0000-0000-0000-000000000009'::uuid,
        'mobile_app'::store.sales_channel,
        9.95::numeric,
        'd9000000-0000-0000-0000-000000000001'::uuid,
        null::text,
        current_timestamp - interval '197 days'
      ),
      (
        'da000000-0000-0000-0000-000000000021'::uuid,
        'd7000000-0000-0000-0000-000000000010'::uuid,
        'mobile_app'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        'Please leave with the concierge.'::text,
        current_timestamp - interval '207 days'
      ),
      (
        'da000000-0000-0000-0000-000000000022'::uuid,
        'd7000000-0000-0000-0000-000000000017'::uuid,
        'marketplace'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '218 days'
      ),
      (
        'da000000-0000-0000-0000-000000000023'::uuid,
        'd7000000-0000-0000-0000-00000000001e'::uuid,
        'marketplace'::store.sales_channel,
        0::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '229 days'
      ),
      (
        'da000000-0000-0000-0000-000000000024'::uuid,
        'd7000000-0000-0000-0000-000000000001'::uuid,
        'marketplace'::store.sales_channel,
        0::numeric,
        'd9000000-0000-0000-0000-000000000002'::uuid,
        null::text,
        current_timestamp - interval '240 days'
      ),
      (
        'da000000-0000-0000-0000-000000000025'::uuid,
        'd7000000-0000-0000-0000-000000000008'::uuid,
        'pos'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '251 days'
      ),
      (
        'da000000-0000-0000-0000-000000000026'::uuid,
        'd7000000-0000-0000-0000-00000000000f'::uuid,
        'pos'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '263 days'
      ),
      (
        'da000000-0000-0000-0000-000000000027'::uuid,
        'd7000000-0000-0000-0000-000000000016'::uuid,
        'phone'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '275 days'
      ),
      (
        'da000000-0000-0000-0000-000000000028'::uuid,
        'd7000000-0000-0000-0000-00000000001d'::uuid,
        'web'::store.sales_channel,
        0::numeric,
        'd9000000-0000-0000-0000-000000000002'::uuid,
        null::text,
        current_timestamp - interval '287 days'
      ),
      (
        'da000000-0000-0000-0000-000000000029'::uuid,
        'd7000000-0000-0000-0000-000000000024'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '299 days'
      ),
      (
        'da000000-0000-0000-0000-00000000002a'::uuid,
        'd7000000-0000-0000-0000-000000000007'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '311 days'
      ),
      (
        'da000000-0000-0000-0000-00000000002b'::uuid,
        'd7000000-0000-0000-0000-00000000000e'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '324 days'
      ),
      (
        'da000000-0000-0000-0000-00000000002c'::uuid,
        'd7000000-0000-0000-0000-000000000015'::uuid,
        'web'::store.sales_channel,
        0::numeric,
        'd9000000-0000-0000-0000-000000000002'::uuid,
        'Please leave with the concierge.'::text,
        current_timestamp - interval '337 days'
      ),
      (
        'da000000-0000-0000-0000-00000000002d'::uuid,
        'd7000000-0000-0000-0000-00000000001c'::uuid,
        'web'::store.sales_channel,
        0::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '350 days'
      ),
      (
        'da000000-0000-0000-0000-00000000002e'::uuid,
        'd7000000-0000-0000-0000-000000000023'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '5 days'
      ),
      (
        'da000000-0000-0000-0000-00000000002f'::uuid,
        'd7000000-0000-0000-0000-000000000006'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '6 days'
      ),
      (
        'da000000-0000-0000-0000-000000000030'::uuid,
        'd7000000-0000-0000-0000-00000000000d'::uuid,
        'web'::store.sales_channel,
        0::numeric,
        'd9000000-0000-0000-0000-000000000002'::uuid,
        null::text,
        current_timestamp - interval '9 days'
      ),
      (
        'da000000-0000-0000-0000-000000000031'::uuid,
        'd7000000-0000-0000-0000-000000000014'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '13 days'
      ),
      (
        'da000000-0000-0000-0000-000000000032'::uuid,
        'd7000000-0000-0000-0000-00000000001b'::uuid,
        'mobile_app'::store.sales_channel,
        0::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '19 days'
      ),
      (
        'da000000-0000-0000-0000-000000000033'::uuid,
        'd7000000-0000-0000-0000-000000000022'::uuid,
        'mobile_app'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '25 days'
      ),
      (
        'da000000-0000-0000-0000-000000000034'::uuid,
        'd7000000-0000-0000-0000-000000000005'::uuid,
        'mobile_app'::store.sales_channel,
        0::numeric,
        'd9000000-0000-0000-0000-000000000002'::uuid,
        null::text,
        current_timestamp - interval '32 days'
      ),
      (
        'da000000-0000-0000-0000-000000000035'::uuid,
        'd7000000-0000-0000-0000-00000000000c'::uuid,
        'mobile_app'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '40 days'
      ),
      (
        'da000000-0000-0000-0000-000000000036'::uuid,
        'd7000000-0000-0000-0000-000000000013'::uuid,
        'marketplace'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '2 days'
      ),
      (
        'da000000-0000-0000-0000-000000000037'::uuid,
        'd7000000-0000-0000-0000-00000000001a'::uuid,
        'marketplace'::store.sales_channel,
        0::numeric,
        null::uuid,
        'Please leave with the concierge.'::text,
        current_timestamp - interval '3 days'
      ),
      (
        'da000000-0000-0000-0000-000000000038'::uuid,
        'd7000000-0000-0000-0000-000000000001'::uuid,
        'marketplace'::store.sales_channel,
        9.95::numeric,
        'd9000000-0000-0000-0000-000000000003'::uuid,
        null::text,
        current_timestamp - interval '7 days'
      ),
      (
        'da000000-0000-0000-0000-000000000039'::uuid,
        'd7000000-0000-0000-0000-000000000004'::uuid,
        'pos'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '12 days'
      ),
      (
        'da000000-0000-0000-0000-00000000003a'::uuid,
        'd7000000-0000-0000-0000-00000000000b'::uuid,
        'pos'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '18 days'
      ),
      (
        'da000000-0000-0000-0000-00000000003b'::uuid,
        'd7000000-0000-0000-0000-000000000012'::uuid,
        'phone'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '25 days'
      ),
      (
        'da000000-0000-0000-0000-00000000003c'::uuid,
        'd7000000-0000-0000-0000-000000000019'::uuid,
        'web'::store.sales_channel,
        0::numeric,
        'd9000000-0000-0000-0000-000000000002'::uuid,
        null::text,
        current_timestamp - interval '1 days'
      ),
      (
        'da000000-0000-0000-0000-00000000003d'::uuid,
        'd7000000-0000-0000-0000-000000000020'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '2 days'
      ),
      (
        'da000000-0000-0000-0000-00000000003e'::uuid,
        'd7000000-0000-0000-0000-000000000003'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '3 days'
      ),
      (
        'da000000-0000-0000-0000-00000000003f'::uuid,
        'd7000000-0000-0000-0000-00000000000a'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '6 days'
      ),
      (
        'da000000-0000-0000-0000-000000000040'::uuid,
        'd7000000-0000-0000-0000-000000000011'::uuid,
        'web'::store.sales_channel,
        0::numeric,
        'd9000000-0000-0000-0000-000000000002'::uuid,
        null::text,
        current_timestamp - interval '9 days'
      ),
      (
        'da000000-0000-0000-0000-000000000041'::uuid,
        'd7000000-0000-0000-0000-000000000018'::uuid,
        'web'::store.sales_channel,
        0::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '4 days'
      ),
      (
        'da000000-0000-0000-0000-000000000042'::uuid,
        'd7000000-0000-0000-0000-00000000001f'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        'Please leave with the concierge.'::text,
        current_timestamp - interval '13 days'
      ),
      (
        'da000000-0000-0000-0000-000000000043'::uuid,
        'd7000000-0000-0000-0000-000000000002'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '34 days'
      ),
      (
        'da000000-0000-0000-0000-000000000044'::uuid,
        'd7000000-0000-0000-0000-000000000009'::uuid,
        'web'::store.sales_channel,
        0::numeric,
        'd9000000-0000-0000-0000-000000000002'::uuid,
        null::text,
        current_timestamp - interval '65 days'
      ),
      (
        'da000000-0000-0000-0000-000000000045'::uuid,
        'd7000000-0000-0000-0000-000000000010'::uuid,
        'web'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '103 days'
      ),
      (
        'da000000-0000-0000-0000-000000000046'::uuid,
        'd7000000-0000-0000-0000-000000000017'::uuid,
        'mobile_app'::store.sales_channel,
        0::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '148 days'
      ),
      (
        'da000000-0000-0000-0000-000000000047'::uuid,
        'd7000000-0000-0000-0000-00000000001e'::uuid,
        'mobile_app'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '201 days'
      ),
      (
        'da000000-0000-0000-0000-000000000048'::uuid,
        'd7000000-0000-0000-0000-000000000001'::uuid,
        'mobile_app'::store.sales_channel,
        9.95::numeric,
        null::uuid,
        null::text,
        current_timestamp - interval '260 days'
      )
  ) as v (
    id,
    customer_id,
    channel,
    shipping_total,
    discount_id,
    customer_note,
    placed_at
  )
  join store.customers c on c.id = v.customer_id;

----------------------------------------------------------------
-- Order lines
--
-- product_name, sku, unit_price, tax and the line total are all left
-- to store.trg_order_items_apply_defaults, which snapshots the
-- variant exactly as the storefront would.
----------------------------------------------------------------
insert into
  store.order_items (id, order_id, variant_id, quantity, position)
values
  (
    'db000000-0000-0000-0000-000000000001',
    'da000000-0000-0000-0000-000000000001',
    'd5000000-0000-0000-0000-000000000006',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000002',
    'da000000-0000-0000-0000-000000000001',
    'd5000000-0000-0000-0000-000000000011',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000003',
    'da000000-0000-0000-0000-000000000002',
    'd5000000-0000-0000-0000-00000000000b',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000004',
    'da000000-0000-0000-0000-000000000002',
    'd5000000-0000-0000-0000-000000000016',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000005',
    'da000000-0000-0000-0000-000000000002',
    'd5000000-0000-0000-0000-000000000021',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000006',
    'da000000-0000-0000-0000-000000000003',
    'd5000000-0000-0000-0000-000000000010',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000007',
    'da000000-0000-0000-0000-000000000004',
    'd5000000-0000-0000-0000-000000000015',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000008',
    'da000000-0000-0000-0000-000000000004',
    'd5000000-0000-0000-0000-000000000020',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000009',
    'da000000-0000-0000-0000-000000000005',
    'd5000000-0000-0000-0000-00000000001a',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000000a',
    'da000000-0000-0000-0000-000000000005',
    'd5000000-0000-0000-0000-000000000025',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000000b',
    'da000000-0000-0000-0000-000000000005',
    'd5000000-0000-0000-0000-000000000002',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-00000000000c',
    'da000000-0000-0000-0000-000000000006',
    'd5000000-0000-0000-0000-00000000001f',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000000d',
    'da000000-0000-0000-0000-000000000007',
    'd5000000-0000-0000-0000-000000000024',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000000e',
    'da000000-0000-0000-0000-000000000007',
    'd5000000-0000-0000-0000-000000000001',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000000f',
    'da000000-0000-0000-0000-000000000008',
    'd5000000-0000-0000-0000-000000000029',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000010',
    'da000000-0000-0000-0000-000000000008',
    'd5000000-0000-0000-0000-000000000006',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000011',
    'da000000-0000-0000-0000-000000000008',
    'd5000000-0000-0000-0000-000000000011',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000012',
    'da000000-0000-0000-0000-000000000009',
    'd5000000-0000-0000-0000-00000000002e',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000013',
    'da000000-0000-0000-0000-00000000000a',
    'd5000000-0000-0000-0000-000000000005',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000014',
    'da000000-0000-0000-0000-00000000000a',
    'd5000000-0000-0000-0000-000000000010',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000015',
    'da000000-0000-0000-0000-00000000000b',
    'd5000000-0000-0000-0000-00000000000a',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000016',
    'da000000-0000-0000-0000-00000000000b',
    'd5000000-0000-0000-0000-000000000015',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000017',
    'da000000-0000-0000-0000-00000000000b',
    'd5000000-0000-0000-0000-000000000020',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000018',
    'da000000-0000-0000-0000-00000000000c',
    'd5000000-0000-0000-0000-00000000000f',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000019',
    'da000000-0000-0000-0000-00000000000d',
    'd5000000-0000-0000-0000-000000000014',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000001a',
    'da000000-0000-0000-0000-00000000000d',
    'd5000000-0000-0000-0000-00000000001f',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000001b',
    'da000000-0000-0000-0000-00000000000e',
    'd5000000-0000-0000-0000-000000000019',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000001c',
    'da000000-0000-0000-0000-00000000000e',
    'd5000000-0000-0000-0000-000000000024',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000001d',
    'da000000-0000-0000-0000-00000000000e',
    'd5000000-0000-0000-0000-000000000001',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-00000000001e',
    'da000000-0000-0000-0000-00000000000f',
    'd5000000-0000-0000-0000-00000000001e',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000001f',
    'da000000-0000-0000-0000-000000000010',
    'd5000000-0000-0000-0000-000000000023',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000020',
    'da000000-0000-0000-0000-000000000010',
    'd5000000-0000-0000-0000-00000000002e',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000021',
    'da000000-0000-0000-0000-000000000011',
    'd5000000-0000-0000-0000-000000000028',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000022',
    'da000000-0000-0000-0000-000000000011',
    'd5000000-0000-0000-0000-000000000005',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000023',
    'da000000-0000-0000-0000-000000000011',
    'd5000000-0000-0000-0000-000000000010',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000024',
    'da000000-0000-0000-0000-000000000012',
    'd5000000-0000-0000-0000-00000000002d',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000025',
    'da000000-0000-0000-0000-000000000013',
    'd5000000-0000-0000-0000-000000000004',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000026',
    'da000000-0000-0000-0000-000000000013',
    'd5000000-0000-0000-0000-00000000000f',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000027',
    'da000000-0000-0000-0000-000000000014',
    'd5000000-0000-0000-0000-000000000009',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000028',
    'da000000-0000-0000-0000-000000000014',
    'd5000000-0000-0000-0000-000000000014',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000029',
    'da000000-0000-0000-0000-000000000014',
    'd5000000-0000-0000-0000-00000000001f',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-00000000002a',
    'da000000-0000-0000-0000-000000000015',
    'd5000000-0000-0000-0000-00000000000e',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000002b',
    'da000000-0000-0000-0000-000000000016',
    'd5000000-0000-0000-0000-000000000013',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000002c',
    'da000000-0000-0000-0000-000000000016',
    'd5000000-0000-0000-0000-00000000001e',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000002d',
    'da000000-0000-0000-0000-000000000017',
    'd5000000-0000-0000-0000-000000000018',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000002e',
    'da000000-0000-0000-0000-000000000017',
    'd5000000-0000-0000-0000-000000000023',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000002f',
    'da000000-0000-0000-0000-000000000017',
    'd5000000-0000-0000-0000-00000000002e',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000030',
    'da000000-0000-0000-0000-000000000018',
    'd5000000-0000-0000-0000-00000000001d',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000031',
    'da000000-0000-0000-0000-000000000019',
    'd5000000-0000-0000-0000-000000000022',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000032',
    'da000000-0000-0000-0000-000000000019',
    'd5000000-0000-0000-0000-00000000002d',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000033',
    'da000000-0000-0000-0000-00000000001a',
    'd5000000-0000-0000-0000-000000000027',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000034',
    'da000000-0000-0000-0000-00000000001a',
    'd5000000-0000-0000-0000-000000000004',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000035',
    'da000000-0000-0000-0000-00000000001a',
    'd5000000-0000-0000-0000-00000000000f',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000036',
    'da000000-0000-0000-0000-00000000001b',
    'd5000000-0000-0000-0000-00000000002c',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000037',
    'da000000-0000-0000-0000-00000000001c',
    'd5000000-0000-0000-0000-000000000003',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000038',
    'da000000-0000-0000-0000-00000000001c',
    'd5000000-0000-0000-0000-00000000000e',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000039',
    'da000000-0000-0000-0000-00000000001d',
    'd5000000-0000-0000-0000-000000000008',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000003a',
    'da000000-0000-0000-0000-00000000001d',
    'd5000000-0000-0000-0000-000000000013',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000003b',
    'da000000-0000-0000-0000-00000000001d',
    'd5000000-0000-0000-0000-00000000001e',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-00000000003c',
    'da000000-0000-0000-0000-00000000001e',
    'd5000000-0000-0000-0000-00000000000d',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000003d',
    'da000000-0000-0000-0000-00000000001f',
    'd5000000-0000-0000-0000-000000000012',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000003e',
    'da000000-0000-0000-0000-00000000001f',
    'd5000000-0000-0000-0000-00000000001d',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000003f',
    'da000000-0000-0000-0000-000000000020',
    'd5000000-0000-0000-0000-000000000017',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000040',
    'da000000-0000-0000-0000-000000000020',
    'd5000000-0000-0000-0000-000000000022',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000041',
    'da000000-0000-0000-0000-000000000020',
    'd5000000-0000-0000-0000-00000000002d',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000042',
    'da000000-0000-0000-0000-000000000021',
    'd5000000-0000-0000-0000-00000000001c',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000043',
    'da000000-0000-0000-0000-000000000022',
    'd5000000-0000-0000-0000-000000000021',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000044',
    'da000000-0000-0000-0000-000000000022',
    'd5000000-0000-0000-0000-00000000002c',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000045',
    'da000000-0000-0000-0000-000000000023',
    'd5000000-0000-0000-0000-000000000026',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000046',
    'da000000-0000-0000-0000-000000000023',
    'd5000000-0000-0000-0000-000000000003',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000047',
    'da000000-0000-0000-0000-000000000023',
    'd5000000-0000-0000-0000-00000000000e',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000048',
    'da000000-0000-0000-0000-000000000024',
    'd5000000-0000-0000-0000-00000000002b',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000049',
    'da000000-0000-0000-0000-000000000025',
    'd5000000-0000-0000-0000-000000000002',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000004a',
    'da000000-0000-0000-0000-000000000025',
    'd5000000-0000-0000-0000-00000000000d',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000004b',
    'da000000-0000-0000-0000-000000000026',
    'd5000000-0000-0000-0000-000000000007',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000004c',
    'da000000-0000-0000-0000-000000000026',
    'd5000000-0000-0000-0000-000000000012',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000004d',
    'da000000-0000-0000-0000-000000000026',
    'd5000000-0000-0000-0000-00000000001d',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-00000000004e',
    'da000000-0000-0000-0000-000000000027',
    'd5000000-0000-0000-0000-00000000000c',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000004f',
    'da000000-0000-0000-0000-000000000028',
    'd5000000-0000-0000-0000-000000000011',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000050',
    'da000000-0000-0000-0000-000000000028',
    'd5000000-0000-0000-0000-00000000001c',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000051',
    'da000000-0000-0000-0000-000000000029',
    'd5000000-0000-0000-0000-000000000016',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000052',
    'da000000-0000-0000-0000-000000000029',
    'd5000000-0000-0000-0000-000000000021',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000053',
    'da000000-0000-0000-0000-000000000029',
    'd5000000-0000-0000-0000-00000000002c',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000054',
    'da000000-0000-0000-0000-00000000002a',
    'd5000000-0000-0000-0000-00000000001b',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000055',
    'da000000-0000-0000-0000-00000000002b',
    'd5000000-0000-0000-0000-000000000020',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000056',
    'da000000-0000-0000-0000-00000000002b',
    'd5000000-0000-0000-0000-00000000002b',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000057',
    'da000000-0000-0000-0000-00000000002c',
    'd5000000-0000-0000-0000-000000000025',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000058',
    'da000000-0000-0000-0000-00000000002c',
    'd5000000-0000-0000-0000-000000000002',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000059',
    'da000000-0000-0000-0000-00000000002c',
    'd5000000-0000-0000-0000-00000000000d',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-00000000005a',
    'da000000-0000-0000-0000-00000000002d',
    'd5000000-0000-0000-0000-00000000002a',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000005b',
    'da000000-0000-0000-0000-00000000002e',
    'd5000000-0000-0000-0000-000000000001',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000005c',
    'da000000-0000-0000-0000-00000000002e',
    'd5000000-0000-0000-0000-00000000000c',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000005d',
    'da000000-0000-0000-0000-00000000002f',
    'd5000000-0000-0000-0000-000000000006',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000005e',
    'da000000-0000-0000-0000-00000000002f',
    'd5000000-0000-0000-0000-000000000011',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000005f',
    'da000000-0000-0000-0000-00000000002f',
    'd5000000-0000-0000-0000-00000000001c',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000060',
    'da000000-0000-0000-0000-000000000030',
    'd5000000-0000-0000-0000-00000000000b',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000061',
    'da000000-0000-0000-0000-000000000031',
    'd5000000-0000-0000-0000-000000000010',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000062',
    'da000000-0000-0000-0000-000000000031',
    'd5000000-0000-0000-0000-00000000001b',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000063',
    'da000000-0000-0000-0000-000000000032',
    'd5000000-0000-0000-0000-000000000015',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000064',
    'da000000-0000-0000-0000-000000000032',
    'd5000000-0000-0000-0000-000000000020',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000065',
    'da000000-0000-0000-0000-000000000032',
    'd5000000-0000-0000-0000-00000000002b',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000066',
    'da000000-0000-0000-0000-000000000033',
    'd5000000-0000-0000-0000-00000000001a',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000067',
    'da000000-0000-0000-0000-000000000034',
    'd5000000-0000-0000-0000-00000000001f',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000068',
    'da000000-0000-0000-0000-000000000034',
    'd5000000-0000-0000-0000-00000000002a',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000069',
    'da000000-0000-0000-0000-000000000035',
    'd5000000-0000-0000-0000-000000000024',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000006a',
    'da000000-0000-0000-0000-000000000035',
    'd5000000-0000-0000-0000-000000000001',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000006b',
    'da000000-0000-0000-0000-000000000035',
    'd5000000-0000-0000-0000-00000000000c',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-00000000006c',
    'da000000-0000-0000-0000-000000000036',
    'd5000000-0000-0000-0000-000000000029',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000006d',
    'da000000-0000-0000-0000-000000000037',
    'd5000000-0000-0000-0000-00000000002e',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000006e',
    'da000000-0000-0000-0000-000000000037',
    'd5000000-0000-0000-0000-00000000000b',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000006f',
    'da000000-0000-0000-0000-000000000038',
    'd5000000-0000-0000-0000-000000000005',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000070',
    'da000000-0000-0000-0000-000000000038',
    'd5000000-0000-0000-0000-000000000010',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000071',
    'da000000-0000-0000-0000-000000000038',
    'd5000000-0000-0000-0000-00000000001b',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000072',
    'da000000-0000-0000-0000-000000000039',
    'd5000000-0000-0000-0000-00000000000a',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000073',
    'da000000-0000-0000-0000-00000000003a',
    'd5000000-0000-0000-0000-00000000000f',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000074',
    'da000000-0000-0000-0000-00000000003a',
    'd5000000-0000-0000-0000-00000000001a',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000075',
    'da000000-0000-0000-0000-00000000003b',
    'd5000000-0000-0000-0000-000000000014',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000076',
    'da000000-0000-0000-0000-00000000003b',
    'd5000000-0000-0000-0000-00000000001f',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000077',
    'da000000-0000-0000-0000-00000000003b',
    'd5000000-0000-0000-0000-00000000002a',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000078',
    'da000000-0000-0000-0000-00000000003c',
    'd5000000-0000-0000-0000-000000000019',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000079',
    'da000000-0000-0000-0000-00000000003d',
    'd5000000-0000-0000-0000-00000000001e',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000007a',
    'da000000-0000-0000-0000-00000000003d',
    'd5000000-0000-0000-0000-000000000029',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000007b',
    'da000000-0000-0000-0000-00000000003e',
    'd5000000-0000-0000-0000-000000000023',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000007c',
    'da000000-0000-0000-0000-00000000003e',
    'd5000000-0000-0000-0000-00000000002e',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000007d',
    'da000000-0000-0000-0000-00000000003e',
    'd5000000-0000-0000-0000-00000000000b',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-00000000007e',
    'da000000-0000-0000-0000-00000000003f',
    'd5000000-0000-0000-0000-000000000028',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000007f',
    'da000000-0000-0000-0000-000000000040',
    'd5000000-0000-0000-0000-00000000002d',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000080',
    'da000000-0000-0000-0000-000000000040',
    'd5000000-0000-0000-0000-00000000000a',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000081',
    'da000000-0000-0000-0000-000000000041',
    'd5000000-0000-0000-0000-000000000004',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000082',
    'da000000-0000-0000-0000-000000000041',
    'd5000000-0000-0000-0000-00000000000f',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000083',
    'da000000-0000-0000-0000-000000000041',
    'd5000000-0000-0000-0000-00000000001a',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000084',
    'da000000-0000-0000-0000-000000000042',
    'd5000000-0000-0000-0000-000000000009',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000085',
    'da000000-0000-0000-0000-000000000043',
    'd5000000-0000-0000-0000-00000000000e',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000086',
    'da000000-0000-0000-0000-000000000043',
    'd5000000-0000-0000-0000-000000000019',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000087',
    'da000000-0000-0000-0000-000000000044',
    'd5000000-0000-0000-0000-000000000013',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-000000000088',
    'da000000-0000-0000-0000-000000000044',
    'd5000000-0000-0000-0000-00000000001e',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-000000000089',
    'da000000-0000-0000-0000-000000000044',
    'd5000000-0000-0000-0000-000000000029',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-00000000008a',
    'da000000-0000-0000-0000-000000000045',
    'd5000000-0000-0000-0000-000000000018',
    1,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000008b',
    'da000000-0000-0000-0000-000000000046',
    'd5000000-0000-0000-0000-00000000001d',
    2,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000008c',
    'da000000-0000-0000-0000-000000000046',
    'd5000000-0000-0000-0000-000000000028',
    3,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000008d',
    'da000000-0000-0000-0000-000000000047',
    'd5000000-0000-0000-0000-000000000022',
    3,
    1
  ),
  (
    'db000000-0000-0000-0000-00000000008e',
    'da000000-0000-0000-0000-000000000047',
    'd5000000-0000-0000-0000-00000000002d',
    1,
    2
  ),
  (
    'db000000-0000-0000-0000-00000000008f',
    'da000000-0000-0000-0000-000000000047',
    'd5000000-0000-0000-0000-00000000000a',
    2,
    3
  ),
  (
    'db000000-0000-0000-0000-000000000090',
    'da000000-0000-0000-0000-000000000048',
    'd5000000-0000-0000-0000-000000000027',
    1,
    1
  );

----------------------------------------------------------------
-- The order walk
--
-- Confirming is what reserves stock, so it has to happen against the
-- real inventory: if any line could not be served the whole
-- statement would fail, which is exactly the behaviour we want to
-- prove is live.
----------------------------------------------------------------
-- confirmed — this reserves stock (59 orders)
update store.orders
set
  status = 'confirmed'
where
  id in (
    'da000000-0000-0000-0000-000000000001',
    'da000000-0000-0000-0000-000000000002',
    'da000000-0000-0000-0000-000000000003',
    'da000000-0000-0000-0000-000000000004',
    'da000000-0000-0000-0000-000000000005',
    'da000000-0000-0000-0000-000000000006',
    'da000000-0000-0000-0000-000000000007',
    'da000000-0000-0000-0000-000000000008',
    'da000000-0000-0000-0000-000000000009',
    'da000000-0000-0000-0000-00000000000a',
    'da000000-0000-0000-0000-00000000000b',
    'da000000-0000-0000-0000-00000000000c',
    'da000000-0000-0000-0000-00000000000d',
    'da000000-0000-0000-0000-00000000000e',
    'da000000-0000-0000-0000-00000000000f',
    'da000000-0000-0000-0000-000000000010',
    'da000000-0000-0000-0000-000000000011',
    'da000000-0000-0000-0000-000000000012',
    'da000000-0000-0000-0000-000000000013',
    'da000000-0000-0000-0000-000000000014',
    'da000000-0000-0000-0000-000000000015',
    'da000000-0000-0000-0000-000000000016',
    'da000000-0000-0000-0000-000000000017',
    'da000000-0000-0000-0000-000000000018',
    'da000000-0000-0000-0000-000000000019',
    'da000000-0000-0000-0000-00000000001a',
    'da000000-0000-0000-0000-00000000001b',
    'da000000-0000-0000-0000-00000000001c',
    'da000000-0000-0000-0000-00000000001d',
    'da000000-0000-0000-0000-00000000001e',
    'da000000-0000-0000-0000-00000000001f',
    'da000000-0000-0000-0000-000000000020',
    'da000000-0000-0000-0000-000000000021',
    'da000000-0000-0000-0000-000000000022',
    'da000000-0000-0000-0000-000000000023',
    'da000000-0000-0000-0000-000000000024',
    'da000000-0000-0000-0000-000000000025',
    'da000000-0000-0000-0000-000000000026',
    'da000000-0000-0000-0000-000000000027',
    'da000000-0000-0000-0000-000000000028',
    'da000000-0000-0000-0000-000000000029',
    'da000000-0000-0000-0000-00000000002a',
    'da000000-0000-0000-0000-00000000002b',
    'da000000-0000-0000-0000-00000000002c',
    'da000000-0000-0000-0000-00000000002d',
    'da000000-0000-0000-0000-00000000002e',
    'da000000-0000-0000-0000-00000000002f',
    'da000000-0000-0000-0000-000000000030',
    'da000000-0000-0000-0000-000000000031',
    'da000000-0000-0000-0000-000000000032',
    'da000000-0000-0000-0000-000000000033',
    'da000000-0000-0000-0000-000000000034',
    'da000000-0000-0000-0000-000000000035',
    'da000000-0000-0000-0000-000000000036',
    'da000000-0000-0000-0000-000000000037',
    'da000000-0000-0000-0000-000000000038',
    'da000000-0000-0000-0000-000000000039',
    'da000000-0000-0000-0000-00000000003a',
    'da000000-0000-0000-0000-00000000003b'
  );

-- Payment. Captured in full, against the total the triggers worked
-- out, and backdated to the day after the order was placed.
insert into
  store.payments (
    order_id,
    method,
    state,
    amount,
    currency,
    gateway,
    transaction_reference,
    processed_at,
    card_brand,
    card_last_four
  )
select
  o.id,
  (
    array[
      'card',
      'card',
      'card',
      'paypal',
      'wallet',
      'bank_transfer'
    ]
  ) [1 + (abs(hashtext (o.id::text)) % 6)]::store.payment_method,
  'captured',
  o.grand_total,
  o.currency,
  'stripe',
  'ch_' || upper(left(replace(o.id::text, '-', ''), 16)),
  o.placed_at + interval '4 hours',
  (array['visa', 'mastercard', 'amex']) [1 + (abs(hashtext (o.id::text)) % 3)],
  lpad(
    ((abs(hashtext (o.id::text)) % 9000) + 1000)::text,
    4,
    '0'
  )
from
  store.orders o
where
  o.id in (
    'da000000-0000-0000-0000-000000000001',
    'da000000-0000-0000-0000-000000000002',
    'da000000-0000-0000-0000-000000000003',
    'da000000-0000-0000-0000-000000000004',
    'da000000-0000-0000-0000-000000000005',
    'da000000-0000-0000-0000-000000000006',
    'da000000-0000-0000-0000-000000000007',
    'da000000-0000-0000-0000-000000000008',
    'da000000-0000-0000-0000-000000000009',
    'da000000-0000-0000-0000-00000000000a',
    'da000000-0000-0000-0000-00000000000b',
    'da000000-0000-0000-0000-00000000000c',
    'da000000-0000-0000-0000-00000000000d',
    'da000000-0000-0000-0000-00000000000e',
    'da000000-0000-0000-0000-00000000000f',
    'da000000-0000-0000-0000-000000000010',
    'da000000-0000-0000-0000-000000000011',
    'da000000-0000-0000-0000-000000000012',
    'da000000-0000-0000-0000-000000000013',
    'da000000-0000-0000-0000-000000000014',
    'da000000-0000-0000-0000-000000000015',
    'da000000-0000-0000-0000-000000000016',
    'da000000-0000-0000-0000-000000000017',
    'da000000-0000-0000-0000-000000000018',
    'da000000-0000-0000-0000-000000000019',
    'da000000-0000-0000-0000-00000000001a',
    'da000000-0000-0000-0000-00000000001b',
    'da000000-0000-0000-0000-00000000001c',
    'da000000-0000-0000-0000-00000000001d',
    'da000000-0000-0000-0000-00000000001e',
    'da000000-0000-0000-0000-00000000001f',
    'da000000-0000-0000-0000-000000000020',
    'da000000-0000-0000-0000-000000000021',
    'da000000-0000-0000-0000-000000000022',
    'da000000-0000-0000-0000-000000000023',
    'da000000-0000-0000-0000-000000000024',
    'da000000-0000-0000-0000-000000000025',
    'da000000-0000-0000-0000-000000000026',
    'da000000-0000-0000-0000-000000000027',
    'da000000-0000-0000-0000-000000000028',
    'da000000-0000-0000-0000-000000000029',
    'da000000-0000-0000-0000-00000000002a',
    'da000000-0000-0000-0000-00000000002b',
    'da000000-0000-0000-0000-00000000002c',
    'da000000-0000-0000-0000-00000000002d',
    'da000000-0000-0000-0000-00000000002e',
    'da000000-0000-0000-0000-00000000002f',
    'da000000-0000-0000-0000-000000000030',
    'da000000-0000-0000-0000-000000000031',
    'da000000-0000-0000-0000-000000000032',
    'da000000-0000-0000-0000-000000000033',
    'da000000-0000-0000-0000-000000000034',
    'da000000-0000-0000-0000-000000000035',
    'da000000-0000-0000-0000-000000000036',
    'da000000-0000-0000-0000-000000000037',
    'da000000-0000-0000-0000-000000000038',
    'da000000-0000-0000-0000-000000000039',
    'da000000-0000-0000-0000-00000000003a',
    'da000000-0000-0000-0000-00000000003b'
  );

-- Dispatch. Creating the shipment is what releases the reservation,
-- books the goods out of the warehouse through the ledger and moves
-- the order to fulfilled — so these are inserted with a real
-- shipped_at rather than being backdated afterwards.
insert into
  store.shipments (
    order_id,
    warehouse_id,
    status,
    carrier,
    service_level,
    tracking_number,
    tracking_url,
    shipping_cost,
    package_count,
    shipped_at,
    estimated_delivery_on,
    delivered_at
  )
select
  o.id,
  (
    select
      oi.warehouse_id
    from
      store.order_items oi
    where
      oi.order_id = o.id
      and oi.warehouse_id is not null
    limit
      1
  ),
  case
    when v.delivered then 'delivered'::store.shipment_status
    else 'in_transit'::store.shipment_status
  end,
  (array['DHL', 'UPS', 'FedEx', 'Royal Mail']) [1 + (abs(hashtext (o.id::text)) % 4)],
  case
    when (abs(hashtext (o.id::text)) % 4) = 0 then 'Express'
    else 'Standard'
  end,
  'TRK' || upper(left(replace(o.id::text, '-', ''), 12)),
  'https://track.example.test/' || upper(left(replace(o.id::text, '-', ''), 12)),
  o.shipping_total,
  1,
  o.placed_at + interval '2 days',
  (o.placed_at + interval '6 days')::date,
  case
    when v.delivered then o.placed_at + interval '5 days'
    else null
  end
from
  store.orders o
  join (
    values
      (
        'da000000-0000-0000-0000-000000000001'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000002'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000003'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000004'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000005'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000006'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000007'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000008'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000009'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000000a'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000000b'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000000c'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000000d'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000000e'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000000f'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000010'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000011'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000012'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000013'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000014'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000015'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000016'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000017'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000018'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000019'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000001a'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000001b'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000001c'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000001d'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000001e'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000001f'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000020'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000021'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000022'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000023'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000024'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000025'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000026'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000027'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000028'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-000000000029'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000002a'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000002b'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000002c'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000002d'::uuid,
        true
      ),
      (
        'da000000-0000-0000-0000-00000000002e'::uuid,
        false
      ),
      (
        'da000000-0000-0000-0000-00000000002f'::uuid,
        false
      ),
      (
        'da000000-0000-0000-0000-000000000030'::uuid,
        false
      ),
      (
        'da000000-0000-0000-0000-000000000031'::uuid,
        false
      ),
      (
        'da000000-0000-0000-0000-000000000032'::uuid,
        false
      ),
      (
        'da000000-0000-0000-0000-000000000033'::uuid,
        false
      ),
      (
        'da000000-0000-0000-0000-000000000034'::uuid,
        false
      ),
      (
        'da000000-0000-0000-0000-000000000035'::uuid,
        false
      )
  ) as v (id, delivered) on v.id = o.id;

-- completed (45 orders)
update store.orders
set
  status = 'completed'
where
  id in (
    'da000000-0000-0000-0000-000000000001',
    'da000000-0000-0000-0000-000000000002',
    'da000000-0000-0000-0000-000000000003',
    'da000000-0000-0000-0000-000000000004',
    'da000000-0000-0000-0000-000000000005',
    'da000000-0000-0000-0000-000000000006',
    'da000000-0000-0000-0000-000000000007',
    'da000000-0000-0000-0000-000000000008',
    'da000000-0000-0000-0000-000000000009',
    'da000000-0000-0000-0000-00000000000a',
    'da000000-0000-0000-0000-00000000000b',
    'da000000-0000-0000-0000-00000000000c',
    'da000000-0000-0000-0000-00000000000d',
    'da000000-0000-0000-0000-00000000000e',
    'da000000-0000-0000-0000-00000000000f',
    'da000000-0000-0000-0000-000000000010',
    'da000000-0000-0000-0000-000000000011',
    'da000000-0000-0000-0000-000000000012',
    'da000000-0000-0000-0000-000000000013',
    'da000000-0000-0000-0000-000000000014',
    'da000000-0000-0000-0000-000000000015',
    'da000000-0000-0000-0000-000000000016',
    'da000000-0000-0000-0000-000000000017',
    'da000000-0000-0000-0000-000000000018',
    'da000000-0000-0000-0000-000000000019',
    'da000000-0000-0000-0000-00000000001a',
    'da000000-0000-0000-0000-00000000001b',
    'da000000-0000-0000-0000-00000000001c',
    'da000000-0000-0000-0000-00000000001d',
    'da000000-0000-0000-0000-00000000001e',
    'da000000-0000-0000-0000-00000000001f',
    'da000000-0000-0000-0000-000000000020',
    'da000000-0000-0000-0000-000000000021',
    'da000000-0000-0000-0000-000000000022',
    'da000000-0000-0000-0000-000000000023',
    'da000000-0000-0000-0000-000000000024',
    'da000000-0000-0000-0000-000000000025',
    'da000000-0000-0000-0000-000000000026',
    'da000000-0000-0000-0000-000000000027',
    'da000000-0000-0000-0000-000000000028',
    'da000000-0000-0000-0000-000000000029',
    'da000000-0000-0000-0000-00000000002a',
    'da000000-0000-0000-0000-00000000002b',
    'da000000-0000-0000-0000-00000000002c',
    'da000000-0000-0000-0000-00000000002d'
  );

-- Cancellations. The reason is mandatory, and cancelling releases
-- every reservation the order was holding.
update store.orders o
set
  status = 'cancelled',
  cancel_reason = v.reason
from
  (
    values
      (
        'da000000-0000-0000-0000-000000000041'::uuid,
        'Customer changed their mind before dispatch.'
      ),
      (
        'da000000-0000-0000-0000-000000000042'::uuid,
        'Payment could not be taken.'
      ),
      (
        'da000000-0000-0000-0000-000000000043'::uuid,
        'Duplicate of an earlier order.'
      ),
      (
        'da000000-0000-0000-0000-000000000044'::uuid,
        'Item no longer wanted after a delay.'
      ),
      (
        'da000000-0000-0000-0000-000000000045'::uuid,
        'Address could not be verified.'
      ),
      (
        'da000000-0000-0000-0000-000000000046'::uuid,
        'Customer found it cheaper elsewhere.'
      ),
      (
        'da000000-0000-0000-0000-000000000047'::uuid,
        'Customer changed their mind before dispatch.'
      ),
      (
        'da000000-0000-0000-0000-000000000048'::uuid,
        'Payment could not be taken.'
      )
  ) as v (id, reason)
where
  o.id = v.id;

----------------------------------------------------------------
-- Age the order lifecycle stamps
--
-- The walk above ran just now, so confirmed_at, completed_at and
-- cancelled_at all carry this second. Each one is moved onto the
-- day it would actually have happened, relative to when the order
-- was placed.
----------------------------------------------------------------
update store.orders
set
  confirmed_at = case
    when confirmed_at is not null then placed_at + interval '3 hours'
  end,
  completed_at = case
    when completed_at is not null then placed_at + interval '6 days'
  end,
  cancelled_at = case
    when cancelled_at is not null then placed_at + interval '1 day'
  end,
  updated_at = placed_at + interval '6 days'
where
  confirmed_at is not null
  or completed_at is not null
  or cancelled_at is not null;

----------------------------------------------------------------
-- Returns
--
-- Nine completed orders come back. The rows are built from the
-- orders themselves rather than hand-written, so every return line
-- points at a line that was really bought — which is what the
-- store.trg_return_items_guard check is there to enforce.
----------------------------------------------------------------
insert into
  store.return_requests (
    id,
    order_id,
    customer_id,
    reason,
    customer_comment,
    restock,
    requested_at,
    created_at
  )
select
  (
    'de000000-0000-0000-0000-' || lpad(
      row_number() over (
        order by
          o.placed_at
      )::text,
      12,
      '0'
    )
  )::uuid,
  o.id,
  o.customer_id,
  (
    array[
      'damaged',
      'wrong_item',
      'not_as_described',
      'no_longer_needed',
      'late_delivery'
    ]
  ) [1 + (abs(hashtext (o.id::text)) % 5)]::store.return_reason,
  (
    array[
      'Arrived with a cracked housing.',
      'This is not the variant I ordered.',
      'The colour is nothing like the photos.',
      'Changed my mind, unopened.',
      'Turned up two weeks after the date I was given.'
    ]
  ) [1 + (abs(hashtext (o.id::text)) % 5)],
  (abs(hashtext (o.id::text)) % 4) <> 0,
  o.placed_at + interval '9 days',
  o.placed_at + interval '9 days'
from
  store.orders o
where
  o.status = 'completed'
  and (abs(hashtext (o.id::text)) % 5) = 0
limit
  9;

-- One line per return, always the first line of the order and never
-- more than was actually bought.
insert into
  store.return_items (
    return_id,
    order_item_id,
    quantity,
    reason,
    condition_note,
    restock
  )
select
  r.id,
  oi.id,
  1,
  r.reason,
  case
    when r.reason = 'damaged' then 'Housing cracked in transit; not resellable.'
    else 'Returned sealed and in original packaging.'
  end,
  r.reason <> 'damaged'
from
  store.return_requests r
  join lateral (
    select
      oi.id
    from
      store.order_items oi
    where
      oi.order_id = r.order_id
    order by
      oi.position
    limit
      1
  ) oi on true;

-- Six of the nine have been received; four of those refunded. Both
-- transitions do real work: receiving restocks anything marked
-- restockable, refunding books the money back through the payment
-- ledger and moves the order's payment status.
update store.return_requests
set
  status = 'received'
where
  id in (
    select
      id
    from
      store.return_requests
    order by
      requested_at
    limit
      6
  );

update store.return_requests
set
  status = 'refunded'
where
  id in (
    select
      id
    from
      store.return_requests
    where
      status = 'received'
    order by
      requested_at
    limit
      4
  );

-- One was turned down, and one is still sitting on the desk.
update store.return_requests
set
  status = 'rejected',
  rejected_reason = 'Outside the 30 day window and shows heavy use.'
where
  id in (
    select
      id
    from
      store.return_requests
    where
      status = 'requested'
    order by
      requested_at desc
    limit
      1
  );

-- Age the return stamps and the restock movements they generated.
update store.return_requests
set
  approved_at = case
    when approved_at is not null then requested_at + interval '1 day'
  end,
  received_at = case
    when received_at is not null then requested_at + interval '4 days'
  end,
  refunded_at = case
    when refunded_at is not null then requested_at + interval '5 days'
  end,
  updated_at = requested_at + interval '5 days'
where
  approved_at is not null
  or received_at is not null
  or refunded_at is not null;

update store.inventory_movements m
set
  occurred_at = r.received_at
from
  store.return_requests r
where
  m.movement_type = 'return'
  and m.reference = r.rma_number
  and r.received_at is not null;

----------------------------------------------------------------
-- Reviews
--
-- Written by customers who actually bought the product, so
-- store.trg_reviews_apply_defaults marks every one of them a
-- verified purchase and links it back to the order it came from.
-- One review per customer per product is enforced by a partial
-- unique index, which is why this selects DISTINCT ON that pair.
----------------------------------------------------------------
insert into
  store.reviews (
    product_id,
    customer_id,
    order_id,
    rating,
    title,
    body,
    status,
    helpful_count,
    created_at
  )
select distinct
  on (v.product_id, o.customer_id) v.product_id,
  o.customer_id,
  o.id,
  (array[5, 5, 5, 4, 4, 4, 3, 2, 1]) [
    1 + (
      abs(hashtext (o.id::text || v.product_id::text)) % 9
    )
  ],
  (
    array[
      'Exactly what I wanted',
      'Worth the money',
      'Good, with one caveat',
      'Does the job',
      'Better than the one it replaced',
      'Not quite right for me',
      'Disappointed',
      'Would buy again'
    ]
  ) [1 + (abs(hashtext (v.product_id::text)) % 8)],
  (
    array[
      'Turned up quickly and has been in daily use since. No complaints at all.',
      'Build quality is genuinely better than the price suggests. Packaging was excellent too.',
      'Very good overall, though the instructions could be clearer for first-time setup.',
      'Does what it says. Nothing surprising either way, which is what I wanted.',
      'Replaced a much more expensive one and honestly cannot tell the difference.',
      'Fine product, just not the right size for my setup. That is on me, not them.',
      'Stopped working properly after a fortnight. Support were quick to respond.',
      'Second one I have bought. Says everything really.'
    ]
  ) [1 + (abs(hashtext (o.id::text)) % 8)],
  case
    when (
      abs(hashtext (o.id::text || v.product_id::text)) % 11
    ) = 0 then 'pending'::store.review_status
    when (
      abs(hashtext (o.id::text || v.product_id::text)) % 23
    ) = 0 then 'rejected'::store.review_status
    else 'approved'::store.review_status
  end,
  (abs(hashtext (o.id::text)) % 40),
  o.placed_at + interval '12 days'
from
  store.orders o
  join store.order_items oi on oi.order_id = o.id
  join store.product_variants v on v.id = oi.variant_id
where
  o.status = 'completed'
order by
  v.product_id,
  o.customer_id,
  o.placed_at;

-- A rejected review needs its reason, and the merchandising team has
-- replied to a few of the critical ones.
update store.reviews
set
  rejected_reason = 'Off topic — the review is about the courier, not the product.'
where
  status = 'rejected';

update store.reviews
set
  merchant_response = 'Sorry to hear that — support have been in touch and a replacement is on its way.',
  responded_at = created_at + interval '2 days'
where
  status = 'approved'
  and rating <= 2;

----------------------------------------------------------------
-- Age the order history
--
-- Every event above was filed by a trigger during this seed run, so
-- they all share one timestamp and the timeline tabs read as a
-- single block. Each is moved onto the moment it describes.
--
-- actor_id gets the same treatment: a seed has no session, so the
-- column default auth.uid() resolved to null. Staff-side events are
-- attributed to the warehouse login and customer-side ones to the
-- shopper where there is one.
----------------------------------------------------------------
update store.order_events e
set
  occurred_at = case e.event_type
    when 'created' then o.placed_at
    when 'confirmed' then o.placed_at + interval '3 hours'
    when 'paid' then o.placed_at + interval '4 hours'
    when 'shipped' then o.placed_at + interval '2 days'
    when 'fulfilled' then o.placed_at + interval '2 days' + interval '5 minutes'
    when 'delivered' then o.placed_at + interval '5 days'
    when 'cancelled' then o.placed_at + interval '1 day'
    when 'return_requested' then o.placed_at + interval '9 days'
    when 'refunded' then o.placed_at + interval '14 days'
    else o.placed_at + interval '1 day'
  end,
  actor_id = coalesce(
    e.actor_id,
    case
      when e.event_type in ('created', 'return_requested') then c.user_id
      else 'b73eb03e-fb7a-424d-84ff-18e2791ce0b9'::uuid
    end
  )
from
  store.orders o
  join store.customers c on c.id = o.customer_id
where
  o.id = e.order_id;

----------------------------------------------------------------
-- Push a few lines below their reorder point
--
-- Trading alone has not eaten far enough into the opening stock to
-- make anything look short, so a handful of lines are written down
-- to what a real shelf looks like after a busy month. These are
-- damage and stocktake movements, not edits: the ledger stays the
-- only way stock ever moves.
----------------------------------------------------------------
insert into
  store.inventory_movements (
    variant_id,
    warehouse_id,
    movement_type,
    quantity,
    reference,
    note,
    occurred_at
  )
select
  l.variant_id,
  l.warehouse_id,
  'stocktake',
  greatest(
    l.reserved,
    greatest(
      0,
      l.reorder_point - 3 - (abs(hashtext (l.id::text)) % 4)
    )
  ),
  'COUNT-' || to_char(current_date, 'YYYYMM'),
  'Cycle count correction',
  current_timestamp - interval '2 days'
from
  store.inventory_levels l
where
  l.reorder_point > 0
  and (abs(hashtext (l.id::text)) % 7) = 0;

----------------------------------------------------------------
-- Run the nightly maintenance once
--
-- This is the function a pg_cron job would call: it ages discount
-- windows and recomputes the low-stock flags. Running it here proves
-- the seeded state is exactly what the scheduled job would produce.
----------------------------------------------------------------
select
  store.refresh_store_state () as rows_aged;

----------------------------------------------------------------
-- Populate the materialized view report's data. (This is the DATA
-- refresh — the CATALOG refresh, supasheet.refresh_metadata(), runs
-- at the end of the schema file and is not needed again here.)
----------------------------------------------------------------
refresh materialized view store.sales_rollup;
