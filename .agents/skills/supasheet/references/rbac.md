# RBAC: Roles, Permissions, and RLS

Authorization is database-backed. Roles and permissions live in tables and are checked at query time — **never** read roles from the JWT (`auth.jwt() ->> 'role'` is wrong here).

## The pieces (base migration `20250523000822_roles.sql`)

```sql
create type supasheet.app_role as enum('x-admin', 'admin', 'user');
create type supasheet.app_permission as enum( ...'<schema>.<resource>:<action>' strings... );

supasheet.user_roles       (user_id uuid → supasheet.users, role app_role, unique(user_id, role))
supasheet.role_permissions (role app_role, permission app_permission, unique(role, permission))

supasheet.has_permission(p supasheet.app_permission) returns boolean  -- stable, security definer
supasheet.has_role(r supasheet.app_role) returns boolean
```

`has_permission` returns true when any of the caller's roles holds the permission. Users can hold multiple roles.

## Built-in roles

- `user` — default; auto-assigned on sign-up; no permissions until you seed them.
- `admin` — intermediate; nothing built in.
- `x-admin` — super-admin; seeded with all `supasheet.*` permissions; the only role that manages roles/permissions. Always keep at least one x-admin.

## Adding permission values

Permission format: `"<schema>.<resource>:<action>"`. Actions: `select`, `insert`, `update`, `delete`, `audit`, `comment` (base schema also uses `invite`, `ban`, `generate_link` for user management).

Enum values must be committed before first use — put all `alter type` statements in an explicit block at the top of the migration:

```sql
begin;
alter type supasheet.app_permission add value if not exists 'app.tickets:select';
alter type supasheet.app_permission add value if not exists 'app.tickets:insert';
-- use `add value if not exists` when re-runnable migrations matter
commit;
```

## Canonical RLS policy set

Grants gate the operation at the SQL level; RLS + `has_permission` gate it per-user. Both are required.

```sql
revoke all on table app.tickets from public, anon, authenticated, service_role;
grant select, insert, update, delete on table app.tickets to authenticated;

alter table app.tickets enable row level security;

create policy tickets_select on app.tickets for select to authenticated
  using (supasheet.has_permission ('app.tickets:select'));

create policy tickets_insert on app.tickets for insert to authenticated
  with check (supasheet.has_permission ('app.tickets:insert'));

create policy tickets_update on app.tickets for update to authenticated
  using (supasheet.has_permission ('app.tickets:update'))
  with check (supasheet.has_permission ('app.tickets:update'));

create policy tickets_delete on app.tickets for delete to authenticated
  using (supasheet.has_permission ('app.tickets:delete'));
```

Owner-scoped variant — combine permission with ownership:

```sql
using (user_id = auth.uid () and supasheet.has_permission ('app.tickets:select'))
```

## Seeding

```sql
-- grant permissions to roles
insert into supasheet.role_permissions (role, permission) values
  ('x-admin', 'app.tickets:select'), ('x-admin', 'app.tickets:insert'),
  ('x-admin', 'app.tickets:update'), ('x-admin', 'app.tickets:delete'),
  ('user', 'app.tickets:select'), ('user', 'app.tickets:insert')
on conflict (role, permission) do nothing;

-- assign roles to users
insert into supasheet.user_roles (user_id, role)
values ('<user-uuid>', 'admin')
on conflict (user_id, role) do nothing;
```

## Custom roles

```sql
begin;
alter type supasheet.app_role add value if not exists 'manager';
commit;
-- then seed role_permissions for 'manager'
```

Default role for new sign-ups is assigned by `supasheet.new_account_created_setup()` — `create or replace` it to change the default from `'user'`.

## Rules of thumb

- Every resource needs its `:select` permission seeded to at least one role, or it's invisible (sidebar, dashboards, charts, and reports all derive from `role_permissions` — see `supasheet.get_tables()` / `get_views()` / `get_schemas()`).
- Views (reports/widgets/charts) need only `:select`. Junction tables: no `:update`. Singletons: no `:delete`.
- Always reference `supasheet.users(id)` in FKs, never `auth.users(id)`.
- Permission-per-resource is deliberate: it powers both RLS and UI discovery, so keep names exactly `"<schema>.<name>:<action>"`.

## Authoritative sources

- `supabase/migrations/20250523000822_roles.sql` — enums, tables, `has_permission`/`has_role`, x-admin seeding
- `supabase/migrations/99999999999999_meta.sql` — permission-aware discovery functions
- `supabase/demo.sql` — full per-role seeding block near the end
