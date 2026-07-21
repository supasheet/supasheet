---
name: supasheet/policies
description: >-
  Authoring RLS policies: which clauses each command takes, permissive vs
  restrictive, keeping policies simple since grants do the real gating, and
  pg_has_role for row-level admin overrides.
type: sub-skill
requires:
  - supasheet
---

# RLS Policies

## Clause rules per command

| Command | `USING` | `WITH CHECK` |
| ------- | ------- | ------------ |
| SELECT  | ✓       | —            |
| INSERT  | —       | ✓            |
| UPDATE  | ✓       | ✓            |
| DELETE  | ✓       | —            |
| ALL     | ✓       | ✓            |

Getting this wrong is a syntax error (e.g. `USING` on INSERT). UPDATE should almost always repeat the same expression in both clauses.

## The Supasheet standard

`GRANT`s to specific native roles already decided who can attempt an
operation (see `rules/roles-permissions.md`) — RLS just needs to let those
rows through, `to authenticated`:

```sql
create policy tickets_update on app.tickets for
update to authenticated using (true)
with
  check (true);
```

The JWT's `role` claim _is_ meant to be read here (indirectly, via
PostgREST's `SET ROLE` → `current_user`) — that's the whole native-roles
model. What you should never do is re-implement a permission check by hand
from `auth.jwt()`; use `current_user`/`pg_has_role()`, which reflect the
already-verified active role.

## Common patterns

```sql
-- ownership (users see only their rows)
using (user_id = auth.uid ())
-- ownership OR admin override (owners always see theirs; x-admin sees all)
using (
  user_id = auth.uid ()
  or pg_has_role (current_user, 'x-admin', 'member')
)
-- role-based row override
using (pg_has_role (current_user, 'admin', 'member'))
-- row-state condition (e.g. only drafts are editable) — grants already
-- restrict who can UPDATE at all, this just restricts which rows
using (status = 'draft')
```

## Permissive vs restrictive

Default is `PERMISSIVE` (multiple policies OR together). Add a `RESTRICTIVE` policy to impose a mandatory AND-condition on top of the permissive ones:

```sql
create policy tickets_tenant_guard on app.tickets as restrictive for all to authenticated using (
  tenant_id = (
    select
      auth.uid ()
  )
);
```

## Performance

- Wrap volatile-per-row calls: `(select auth.uid ())` instead of `auth.uid ()` so the planner caches it per statement.
- `pg_has_role()` is a cheap catalog lookup — no need to wrap it in a subselect.
- Policies don't replace grants: `revoke all` + explicit `grant` to specific
  native roles still gate the operation before RLS runs — a role with no
  grant on a table gets zero rows regardless of what the policies say.
- RLS on views: views use `security_invoker = true` so the _base table's_ policies apply — don't write policies on views.
