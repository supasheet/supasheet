# RBAC: Native Roles, Grants, and the Custom Access Token Hook

Authorization is database-backed, but with no `user_roles`/`role_permissions`
tables. Roles are real Postgres roles; access is real `GRANT`s; the JWT's
`role` claim (read by PostgREST to `SET ROLE`) *is* the mechanism — this is
one of the rare cases where deriving authorization from the JWT is correct,
because the claim only ever selects among roles that already have real,
independently-verified Postgres grants. Nothing sensitive is *decided* by the
claim itself.

## The pieces (base migration `20250523000822_roles.sql`)

```sql
-- real, nologin Postgres roles — no app-level enum wraps them, pg_roles is
-- the source of truth for which roles exist
create role "x-admin" nologin;
create role "admin" nologin;
create role "user" nologin;

grant "x-admin", "admin", "user" to authenticator;   -- lets PostgREST SET ROLE
grant authenticated to "x-admin", "admin", "user";   -- `to authenticated` policies still apply

supasheet.has_role(requested_role text) returns boolean           -- pg_has_role(current_user, requested_role, 'member')
supasheet.whoami() returns jsonb                                  -- { user_id, role, current_user } — debug/UI helper
supasheet.custom_access_token(event jsonb) returns jsonb          -- the Auth Hook (see below)
supasheet.assign_default_role() -- before insert on auth.users trigger, defaults role to 'user'
```

Neither `app_permission` nor `app_role` exist — there's nothing to validate a permission
string against, since grants are the source of truth.

## Built-in roles

- `user` — default; auto-assigned on sign-up by the `assign_default_role()`
  trigger; no grants until you add them.
- `admin` — intermediate; nothing built in.
- `x-admin` — super-admin; the only role with broad `supasheet.users` access
  and the target of every `pg_has_role`-based admin override. Always keep at
  least one x-admin.

## The Custom Access Token Hook

`supasheet.custom_access_token(event jsonb)` runs on every token
issuance/refresh (registered in `supabase/config.toml` under
`[auth.hook.custom_access_token]`). It reads
`event->'claims'->'app_metadata'->>'role'`, checks the value is a real row in
`pg_roles`, and if so copies it into the top-level `role` claim of the JWT.
PostgREST reads that claim and does `SET ROLE <claim>` for the request — that
`SET ROLE` is what makes `current_user` equal the caller's assigned role
everywhere else (RLS, `has_table_privilege`, `pg_has_role`).

Revoked from every client-reachable role — `supabase_auth_admin` only, never
reachable via the Data API.

If the role is missing/invalid, the claim is left untouched (falls back to
plain `authenticated`, which holds no grants — safe by default).

**Role changes only take effect on the next token issuance/refresh** — an
already-issued JWT keeps its old role until the client calls
`supabase.auth.refreshSession()` or logs in again.

## Canonical RLS + grant set

Grants gate the operation at the SQL level; RLS gates row visibility. Most
tables need only a trivial RLS policy since the grant already decided who can
attempt the operation:

```sql
revoke all on table app.tickets
from
  public,
  anon,
  authenticated,
  service_role;

grant select, insert, update, delete on table app.tickets to "x-admin";

grant select, insert, update on table app.tickets to "user";

alter table app.tickets enable row level security;

create policy tickets_select on app.tickets for select to authenticated using (true);

create policy tickets_insert on app.tickets for insert to authenticated with check (true);

create policy tickets_update on app.tickets for update to authenticated using (true) with check (true);

create policy tickets_delete on app.tickets for delete to authenticated using (true);
```

Owner-scoped variant — plain ownership, no permission check needed (the grant
already restricted which roles can even attempt the operation):

```sql
using (user_id = auth.uid ())
```

Admin-style row override — a specific role sees rows an ownership check would
otherwise hide, as an additional permissive policy:

```sql
create policy "x-admin can view all tickets" on app.tickets for select
  to authenticated using (pg_has_role (current_user, 'x-admin', 'member'));
```

## Assigning roles

```sql
-- one role per user, stored in auth.users, read by the Custom Access Token Hook
update auth.users
set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('role', 'admin')
where id = '<user-uuid>';
```

Client-facing equivalent: the `admin-set-user-role` edge function (x-admin
only, validates the role name, calls
`adminClient.auth.admin.updateUserById(userId, { app_metadata: { role } })`).
Never write to `user_metadata` for this — it's user-editable and therefore not
trustworthy for authorization.

## Custom roles

Just `CREATE ROLE` — there's no enum to extend first:

```sql
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'manager') then
    create role "manager" nologin;
  end if;
end;
$$;

grant "manager" to authenticator;
grant authenticated to "manager";

-- then grant it access per resource in whichever migrations need it
```

Default role for new sign-ups: `create or replace` `supasheet.assign_default_role()`
to change the default from `'user'`.

## Rules of thumb

- A resource needs a `select` grant to at least one role, or it's invisible —
  sidebar, dashboards, charts, and reports all derive visibility live from
  `has_table_privilege`/`has_column_privilege` (see `supasheet.get_tables()` /
  `get_views()` / `get_schemas()` / `get_permissions()`).
- Views (reports/widgets/charts) need only `select`. Junction tables: no
  `update` grant. Singletons: no `delete` grant.
- Always reference `supasheet.users(id)` in FKs, never `auth.users(id)`.
- Grants are per-resource and non-inheriting by convention — even when
  `x-admin` should clearly have everything `user` has, write it out
  explicitly rather than granting role membership between them. Keeps
  `grep`ing `to "<role>"` across a migration an accurate picture of what that
  role can do.
- Non-grantable capabilities (audit tab, invite/ban/generate_link/select_all)
  are `pg_has_role(current_user, '<role>', 'member')` checks written directly
  where they're needed — never a lookup table.

## Authoritative sources

- `supabase/migrations/20250523000822_roles.sql` — role creation, grants,
  `has_role`/`whoami`/`custom_access_token`, `assign_default_role` trigger
- `supabase/migrations/99999999999999_meta.sql` — grant-aware discovery
  functions
- `supabase/config.toml` — `[auth.hook.custom_access_token]` registration
- `supabase/demo.sql` — full per-table grant set for a real module
- `supabase/functions/_shared/admin.ts` — `requireRole()`, the edge-function
  equivalent of `pg_has_role`
