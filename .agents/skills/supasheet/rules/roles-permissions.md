---
name: supasheet/roles-permissions
description: >-
  Managing roles and permissions: permission string format, enum extension
  rules, role_permissions seeding matrix, user_roles assignment, custom roles.
type: sub-skill
requires:
  - supasheet
---

# Roles & Permissions

Authorization is DB-backed: `supasheet.app_role` + `supasheet.app_permission` enums, `supasheet.user_roles` + `supasheet.role_permissions` tables, checked by `supasheet.has_permission()` / `has_role()`. Never derive roles from the JWT.

## Permission strings

Format: `"<schema>.<resource>:<action>"`.

| Action                         | Applies to              | Grants access to                                                |
| ------------------------------ | ----------------------- | --------------------------------------------------------------- |
| `select`                       | tables, views, matviews | reading; also controls sidebar/dashboard/chart/report discovery |
| `insert` / `update` / `delete` | tables, updatable views | writes                                                          |
| `audit`                        | tables                  | the per-record Audit tab                                        |
| `comment`                      | tables                  | reading + posting record comments                               |

Adding values — always `if not exists`, always in a committed transaction **before** any statement uses them:

```sql
begin;

alter type supasheet.app_permission add value if not exists 'app.tickets:select';

-- ...
commit;
```

## Seeding matrix

Every resource is invisible until a role holds its `:select`. Conventional split:

| Resource kind            | x-admin                                        | user                                                      |
| ------------------------ | ---------------------------------------------- | --------------------------------------------------------- |
| Table                    | select, insert, update, delete, audit, comment | select, insert, update, comment (usually no delete/audit) |
| Junction table           | select, insert, delete                         | select, insert, delete                                    |
| Singleton                | select, insert, update                         | select (update if end-users may edit)                     |
| Widget/chart/report view | select                                         | select                                                    |
| Replica users view       | select                                         | select                                                    |

```sql
insert into
  supasheet.role_permissions (role, permission)
values
  ('x-admin', 'app.tickets:select'),
  ('x-admin', 'app.tickets:insert'),
  ('x-admin', 'app.tickets:update'),
  ('x-admin', 'app.tickets:delete'),
  ('x-admin', 'app.tickets:audit'),
  ('x-admin', 'app.tickets:comment'),
  ('user', 'app.tickets:select'),
  ('user', 'app.tickets:insert') on conflict (role, permission) do nothing;
```

Revoking = deleting the row from `role_permissions` (or via the Roles UI).

## Roles

Built-in: `user` (default on sign-up, no permissions), `admin` (empty middle tier), `x-admin` (super-admin, manages roles/permissions — always keep at least one).

```sql
-- custom role (committed block)
begin;

alter type supasheet.app_role add value if not exists 'manager';

commit;

-- assign (users may hold multiple roles)
insert into
  supasheet.user_roles (user_id, role)
values
  ('<user-uuid>', 'manager') on conflict (user_id, role) do nothing;
```

Change the default sign-up role by `create or replace`-ing `supasheet.new_account_created_setup()`.

## How it all connects

- RLS policies call `has_permission()` → row access.
- Grants (`grant select on ...`) → SQL-level access; both must pass.
- `supasheet.get_schemas()/get_tables()/get_views()/get_nav_items()` build the UI nav from `role_permissions` — a missing `:select` seed hides the resource even if grants/RLS would allow it.

Deep-dive (function definitions, x-admin bootstrap, user management permissions like `invite`/`ban`): `references/rbac.md`.
