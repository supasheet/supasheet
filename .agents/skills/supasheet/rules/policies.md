---
name: supasheet/policies
description: >-
  Authoring RLS policies: which clauses each command takes, permissive vs
  restrictive, combining has_permission with ownership, and performance rules.
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

Every policy is `to authenticated` and checks the matching app permission:

```sql
create policy tickets_update on app.tickets for
update to authenticated using (supasheet.has_permission ('app.tickets:update'))
with
  check (supasheet.has_permission ('app.tickets:update'));
```

Never check `auth.jwt() ->> 'role'` — roles live in `supasheet.user_roles`, not the JWT.

## Common patterns

```sql
-- permission + ownership (users see only their rows)
using (
  user_id = auth.uid ()
  and supasheet.has_permission ('app.tickets:select')
)
-- permission OR ownership (owners always see theirs; permission holders see all)
using (
  user_id = auth.uid ()
  or supasheet.has_permission ('app.tickets:select')
)
-- role-based
using (supasheet.has_role ('admin'))
-- row-state condition (e.g. only drafts are editable)
using (
  status = 'draft'
  and supasheet.has_permission ('app.invoices:update')
)
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
- `supasheet.has_permission()` is `stable security definer` — safe and cached per statement.
- Policies don't replace grants: `revoke all` + explicit `grant` still gate the operation before RLS runs.
- RLS on views: views use `security_invoker = true` so the _base table's_ policies apply — don't write policies on views.
