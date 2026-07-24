/*
 * -------------------------------------------------------
 * Section: Users
 * We create the schema for the users. Users are the top level entity in the Supabase Makerpublic. They can be team or personal users.
 * -------------------------------------------------------
 */
-- Users table
create table if not exists supasheet.users (
  id uuid unique not null default extensions.uuid_generate_v4 (),
  name varchar(255) not null,
  email varchar(320) unique,
  updated_at timestamp with time zone,
  created_at timestamp with time zone,
  created_by uuid references auth.users,
  updated_by uuid references auth.users,
  picture_url varchar(1000),
  public_data jsonb default '{}'::jsonb not null,
  primary key (id)
);

comment on table supasheet.users is '{
  "label": "Users",
  "icon": "UserIcon"
}';

-- Enable RLS on the users table
alter table supasheet.users enable row level security;

-- SELECT(users):
-- Users can read their own users
create policy users_read on supasheet.users for
select
  to authenticated using (
    (
      select
        auth.uid ()
    ) = id
  );

-- UPDATE(users):
-- Users can update their own users
create policy users_update on supasheet.users
for update
  to authenticated using (
    (
      select
        auth.uid ()
    ) = id
  )
with
  check (
    (
      select
        auth.uid ()
    ) = id
  );

-- Revoke all on users table from authenticated and service_role
revoke all on supasheet.users
from
  authenticated,
  service_role;

-- Function "supasheet.protect_user_fields"
-- Function to protect user fields from being updated by anyone
create or replace function supasheet.protect_user_fields () returns trigger as $$
begin
    if current_user in ('authenticated', 'anon') then
        if new.id <> old.id or new.email <> old.email then
            raise exception 'You do not have permission to update this field';

        end if;

    end if;

    return NEW;

end
$$ language plpgsql
set
  search_path = '';

-- trigger to protect user fields
create trigger protect_user_fields
before update on supasheet.users for each row
execute function supasheet.protect_user_fields ();

-- create a trigger to update the user email when the primary owner email is updated
create or replace function supasheet.handle_update_user_email () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
    update
        supasheet.users
    set email = new.email
    where id = new.id;

    return new;

end;

$$;

-- trigger the function every time a user email is updated only if the user is the primary owner of the user and
-- the user is personal user
create trigger "on_auth_user_updated"
after update of email on auth.users for each row
execute procedure supasheet.handle_update_user_email ();

-- Function "supasheet.new_user_created_setup"
-- Setup a new user user after user creation
create or replace function supasheet.new_user_created_setup () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
    user_name   text;
    picture_url text;
begin
    if new.raw_user_meta_data ->> 'name' is not null then
        user_name := new.raw_user_meta_data ->> 'name';

    end if;

    if user_name is null and new.email is not null then
        user_name := split_part(new.email, '@', 1);

    end if;

    if user_name is null then
        user_name := '';

    end if;

    if new.raw_user_meta_data ->> 'avatar_url' is not null then
        picture_url := new.raw_user_meta_data ->> 'avatar_url';
    else
        picture_url := null;
    end if;

    insert into supasheet.users(id,
                                name,
                                picture_url,
                                email,
                                created_at,
                                updated_at)
    values (new.id,
            user_name,
            picture_url,
            new.email,
            now(),
            now());

    return new;

end;

$$;

-- trigger the function every time a user is created
create trigger on_auth_user_created
after insert on auth.users for each row
execute procedure supasheet.new_user_created_setup ();

-- Backfill: populate supasheet.users with any pre-existing auth.users
-- (e.g. when this migration runs against a project that already has users)
insert into
  supasheet.users (
    id,
    name,
    picture_url,
    email,
    created_at,
    updated_at
  )
select
  au.id,
  coalesce(
    nullif(au.raw_user_meta_data ->> 'name', ''),
    nullif(split_part(au.email, '@', 1), ''),
    ''
  ),
  au.raw_user_meta_data ->> 'avatar_url',
  au.email,
  now(),
  now()
from
  auth.users au
where
  not exists (
    select
      1
    from
      supasheet.users u
    where
      u.id = au.id
  );

-- Function: get the storage filename as a UUID.
-- Useful if you want to name files with UUIDs related to an user
create or replace function supasheet.get_storage_filename_as_uuid (name text) returns uuid
set
  search_path = '' as $$
begin
    return replace(storage.filename(name), concat('.',
                                                  storage.extension(name)), '')::uuid;

end;

$$ language plpgsql;

grant
execute on function supasheet.get_storage_filename_as_uuid (text) to authenticated,
service_role;
