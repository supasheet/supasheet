---
name: supasheet/roles-permissions
description: >-
  Managing roles and permissions: native Postgres roles, the grant matrix,
  custom roles, the Custom Access Token Hook, and pg_has_role checks for
  capabilities that aren't a real Postgres privilege.
type: sub-skill
requires:
  - supasheet
---

# Roles & Permissions

Authorization is DB-backed, but there is **no permissions table**. Roles are
real `CREATE ROLE ... nologin` Postgres roles; access is real `GRANT`s.
`auth.users.raw_app_meta_data->>'role'` holds one role name per user, copied
into the JWT's top-level `role` claim by `supasheet.custom_access_token()` —
PostgREST reads that claim and does `SET ROLE` for the request, so
`current_user` during any query/RLS check *is* the caller's active role. This
is deliberate: deriving the active role from the JWT is exactly the intended
mechanism here (unlike a typical Supabase RLS setup where `auth.jwt() ->>
'role'` is a smell — here it's what the whole model rests on).

## Granting access to a resource

There's no permission string to seed. Grant directly to the roles that need
it, after revoking the defaults:

```sql
revoke all on table app.tickets
from
  public,
  anon,
  authenticated,
  service_role;

grant select, insert, update, delete on table app.tickets to "x-admin";

grant select, insert, update on table app.tickets to "user";
```

Grants are **additive, not subtractive** and **not inherited** between
unrelated roles — always `revoke all` first, and spell out each role's grants
explicitly rather than relying on one role being a superset of another.

## Seeding matrix (grant edition)

Same shape as before, just grants instead of table rows:

| Resource kind            | x-admin                        | user                                       |
| ------------------------ | ------------------------------- | ------------------------------------------- |
| Table                    | select, insert, update, delete | select, insert, update (usually no delete) |
| Junction table           | select, insert, delete         | select, insert, delete                     |
| Singleton                | select, insert, update         | select (update if end-users may edit)      |
| Widget/chart/report view | select                          | select                                     |
| Replica users view       | select                          | select                                     |

A resource with no `select` grant to any role is invisible — the sidebar,
dashboards, charts, and reports all derive visibility live from
`has_table_privilege`/`has_column_privilege` for `current_user` (see
`supasheet.get_tables()`/`get_views()`/`get_schemas()`/`get_permissions()` in
`99999999999999_meta.sql`).

## Roles

Built-in: `user` (default on sign-up, no grants until you add them), `admin`
(empty middle tier), `x-admin` (super-admin — always keep at least one).

```sql
-- custom role — just CREATE ROLE, no enum to extend first
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'manager') then
    create role "manager" nologin;
  end if;
end;
$$;

grant "manager" to authenticator; -- lets PostgREST SET ROLE into it
grant authenticated to "manager"; -- so `to authenticated` policies still apply

-- then grant it access per resource, same as any other role
grant select, insert, update on table app.tickets to "manager";
```

Assigning a user to a role: `update auth.users set raw_app_meta_data =
raw_app_meta_data || jsonb_build_object('role', 'manager') where id =
'<user-uuid>';` (or the `admin-set-user-role` edge function, x-admin only).
**Takes effect on next login/token refresh only** — an already-issued JWT
keeps its old role claim until it's refreshed.

## Capabilities that aren't a real grant

The per-record Audit tab, comments, and user-management actions
(invite/ban/generate_link/select_all) have no native Postgres privilege to
grant. These are written as a direct `pg_has_role(current_user, '<role>',
'member')` check at the point of use — an RLS policy, a discovery function, or
an edge function — not a lookup table:

```sql
-- audit_logs "view all" override
create policy "x-admin can view all audit logs" on supasheet.audit_logs for select
  to authenticated using (pg_has_role (current_user, 'x-admin', 'member'));
```

Comments are the one exception: commenting on a record requires `select` on
the underlying resource (native grant), matching the old convention where
`:comment` was always seeded alongside `:select` for the same roles.

`supasheet.has_role(requested_role text)` wraps `pg_has_role(current_user,
requested_role, 'member')` — use it from RLS/RPCs; the client-side
equivalent is the `useHasRole(role)` hook (backed by the same RPC), for gating
UI elements tied to one of these non-grantable capabilities.

## How it all connects

- Grants (`grant select on ...`) decide who can attempt an operation at the
  SQL level.
- RLS decides row visibility — usually `using (true)` (grants already did the
  real gating) or an ownership check, plus `pg_has_role(...)` for admin-style
  row overrides.
- `supasheet.get_schemas()/get_tables()/get_views()/get_permissions()` build
  the UI nav and the `useHasPermission()` hook's data straight from grants —
  no seeding step, no missing row to remember.

Deep-dive (the Custom Access Token Hook, `custom_access_token()` internals,
`whoami()`, user-management edge functions): `references/rbac.md`.
