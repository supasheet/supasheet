-- Only "x-admin" is created here — it's the one custom role that core
-- migrations running after this one structurally depend on (this
-- file's own policies check it via pg_has_role, and audit_logs.sql
-- grants to it directly). "user" and "admin" are created in
-- supabase/seed.sql instead, along with every grant that targets them
-- specifically, since neither is needed by anything before seed.sql
-- runs.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'x-admin') then
    create role "x-admin" nologin;
  end if;
end;
$$;

grant "x-admin" to authenticator;

grant authenticated to "x-admin";

create or replace function supasheet.has_role (requested_role text) returns boolean language sql stable
set
  search_path = '' as $$
  select pg_has_role(current_user, requested_role, 'member');
$$;

grant
execute on function supasheet.has_role (text) to authenticated,
service_role;

create or replace function supasheet.get_roles () returns table (role text) language sql stable security definer
set
  search_path = '' as $$
  select r.rolname::text
  from pg_auth_members m
  join pg_roles a on a.oid = m.member and a.rolname = 'authenticator'
  join pg_roles r on r.oid = m.roleid
  where r.rolname not in ('anon', 'authenticated', 'service_role')
  order by r.rolname;
$$;

revoke all on function supasheet.get_roles ()
from
  anon,
  authenticated,
  service_role;

grant
execute on function supasheet.get_roles () to authenticated,
service_role;

create or replace function supasheet.whoami () returns jsonb language sql stable
set
  search_path = '' as $$
  select jsonb_build_object(
    'user_id', auth.uid(),
    'role', (select auth.jwt() ->> 'role'),
    'current_user', current_user::text
  );
$$;

grant
execute on function supasheet.whoami () to authenticated;

create or replace function supasheet.custom_access_token (event jsonb) returns jsonb language plpgsql stable
set
  search_path = '' as $$
declare
  claims jsonb;
  requested_role text;
begin
  claims := event -> 'claims';
  requested_role := event -> 'claims' -> 'app_metadata' ->> 'role';

  if requested_role is not null and exists (select 1 from pg_roles where rolname = requested_role) then
    claims := jsonb_set(claims, '{role}', to_jsonb(requested_role));
  end if;

  return jsonb_set(event, '{claims}', claims);
end;
$$;

grant usage on schema supasheet to supabase_auth_admin;

grant
execute on function supasheet.custom_access_token (jsonb) to supabase_auth_admin;

revoke
execute on function supasheet.custom_access_token (jsonb)
from
  public,
  anon,
  authenticated,
  service_role;

create or replace function supasheet.assign_default_role () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
  if new.raw_app_meta_data ->> 'role' is null then
    new.raw_app_meta_data := coalesce(new.raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', 'user');
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created_assign_role
before insert on auth.users for each row
execute function supasheet.assign_default_role ();

-- RLS is enabled on supasheet.users in 20250523000814_users.sql. The
-- grant to "user" on this table lives in supabase/seed.sql instead of
-- here, since "user" isn't created until seed.sql runs.
revoke all on table supasheet.users
from
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table supasheet.users to "x-admin";

grant
select
,
  insert,
update,
delete on table supasheet.users to service_role;

create policy "x-admin can view all users" on supasheet.users for
select
  to authenticated using (pg_has_role(current_user, 'x-admin', 'member'));

create policy "x-admin can insert users" on supasheet.users for insert to authenticated
with
  check (pg_has_role(current_user, 'x-admin', 'member'));

create policy "x-admin can update users" on supasheet.users
for update
  to authenticated using (pg_has_role(current_user, 'x-admin', 'member'));

create policy "x-admin can delete users" on supasheet.users for delete to authenticated using (pg_has_role(current_user, 'x-admin', 'member'));
