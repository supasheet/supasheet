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
    '{"provider": "email", "providers": ["email"]}',
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
  );

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
  );

insert into
  supasheet.user_roles (user_id, role)
values
  ('b73eb03e-fb7a-424d-84ff-18e2791ce0b8', 'x-admin');

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
    '{"provider": "email", "providers": ["email"]}',
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
  );

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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b4',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b4", "email": "user@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8ab1'
  );

insert into
  supasheet.user_roles (user_id, role)
values
  ('b73eb03e-fb7a-424d-84ff-18e2791ce0b4', 'user');

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
    '{"provider": "email", "providers": ["email"]}',
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
  );

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
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    'b73eb03e-fb7a-424d-84ff-18e2791ce0b1',
    '{"sub": "b73eb03e-fb7a-424d-84ff-18e2791ce0b1", "email": "user1@supasheet.app", "email_verified": false, "phone_verified": false}',
    'email',
    '2024-04-20 08:20:34.46275+00',
    '2024-04-20 08:20:34.462773+00',
    '2024-04-20 08:20:34.462773+00',
    '9bb58bad-24a4-41a8-9742-1b5b4e2d8abd'
  );

insert into
  supasheet.user_roles (user_id, role)
values
  ('b73eb03e-fb7a-424d-84ff-18e2791ce0b1', 'user');

-- Auth records for all 106 users from user_details
do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'john.doe@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "john.doe@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "john.doe@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'jane.smith@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "jane.smith@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "jane.smith@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'bob.johnson@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "bob.johnson@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "bob.johnson@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'alice.williams@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "alice.williams@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "alice.williams@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'charlie.brown@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "charlie.brown@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "charlie.brown@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'diana.prince@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "diana.prince@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "diana.prince@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'ethan.hunt@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "ethan.hunt@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "ethan.hunt@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'fiona.gallagher@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "fiona.gallagher@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "fiona.gallagher@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'george.lucas@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "george.lucas@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "george.lucas@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'hannah.montana@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "hannah.montana@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "hannah.montana@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'isaac.newton@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "isaac.newton@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "isaac.newton@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'julia.roberts@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "julia.roberts@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "julia.roberts@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'kevin.hart@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "kevin.hart@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "kevin.hart@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'laura.palmer@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "laura.palmer@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "laura.palmer@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'michael.scott@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "michael.scott@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "michael.scott@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'nancy.drew@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "nancy.drew@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "nancy.drew@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'oscar.wilde@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "oscar.wilde@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "oscar.wilde@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'patricia.lee@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "patricia.lee@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "patricia.lee@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'quincy.jones@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "quincy.jones@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "quincy.jones@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'rachel.green@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "rachel.green@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "rachel.green@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'sam.wilson@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "sam.wilson@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "sam.wilson@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'tina.fey@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "tina.fey@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "tina.fey@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'uma.thurman@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "uma.thurman@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "uma.thurman@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'victor.hugo@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "victor.hugo@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "victor.hugo@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;

do $$
DECLARE
    new_user_id uuid;
BEGIN
    -- Generate a new UUID
    new_user_id := extensions.uuid_generate_v4();

    -- Insert into auth.users
    INSERT INTO "auth"."users" ("instance_id", "id", "aud", "role", "email", "encrypted_password", "email_confirmed_at",
                                "invited_at", "confirmation_token", "confirmation_sent_at", "recovery_token",
                                "recovery_sent_at", "email_change_token_new", "email_change", "email_change_sent_at",
                                "last_sign_in_at", "raw_app_meta_data", "raw_user_meta_data", "is_super_admin",
                                "created_at", "updated_at", "phone", "phone_confirmed_at", "phone_change",
                                "phone_change_token", "phone_change_sent_at", "email_change_token_current",
                                "email_change_confirm_status", "banned_until", "reauthentication_token",
                                "reauthentication_sent_at", "is_sso_user", "deleted_at", "is_anonymous")
    VALUES ('00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated',
            'authenticated', 'wendy.williams@example.com', '$2a$10$/.78oHxqRLOcnyMeoqYulOcOWhyIeKoyaBYvZhQ0jhEFDtg1ddEPa',
            '2024-04-20 08:38:00.860548+00', NULL, '', '2024-04-20 08:37:43.343769+00', '', NULL, '', '', NULL,
            '2024-04-20 08:38:00.93864+00', '{"provider": "email", "providers": ["email"]}'::jsonb,
            ('{"sub": "' || new_user_id::text || '", "email": "wendy.williams@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            NULL, '2024-04-20 08:37:43.3385+00', '2024-04-20 08:38:00.942809+00', NULL, NULL, '', '', NULL, '', 0, NULL, '',
            NULL, false, NULL, false);

    -- Insert into auth.identities
    INSERT INTO "auth"."identities" ("provider_id", "user_id", "identity_data", "provider", "last_sign_in_at", "created_at",
                                     "updated_at", "id")
    VALUES (new_user_id, new_user_id,
            ('{"sub": "' || new_user_id::text || '", "email": "wendy.williams@example.com", "email_verified": true, "phone_verified": false}')::jsonb,
            'email', '2024-04-20 08:20:34.46275+00', '2024-04-20 08:20:34.462773+00', '2024-04-20 08:20:34.462773+00',
            extensions.uuid_generate_v4());

    -- Insert into user_roles
    INSERT INTO supasheet.user_roles(user_id, role) VALUES (new_user_id, 'user');
END $$;
