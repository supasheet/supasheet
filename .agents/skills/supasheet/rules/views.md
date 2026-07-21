---
name: supasheet/views
description: >-
  Creating plain views: security_invoker, revoke/grant to native roles,
  replica views for cross-schema joins.
type: sub-skill
requires:
  - supasheet
---

# Views

Views serve three roles in Supasheet, all driven by their comment JSON:

| Role                                                        | Comment `type`                                       | Grant needed |
| ------------------------------------------------------------- | ---------------------------------------------------- | ------------- |
| Feature view (dashboard widget / chart / report / template) | `dashboard_widget` / `chart` / `report` / `template` | `select` only |
| Replica view (cross-schema embed fix)                       | none                                                  | `select` only |
| Plain resource view (read-only listing)                     | none                                                  | `select` only |

## Canonical creation pattern

Always `security_invoker = true` (the caller's RLS applies), always revoke-then-grant to specific native roles:

```sql
create view app.my_view
with (security_invoker = true) as
select ...;

revoke all on app.my_view from public, anon, authenticated, service_role;

grant select on app.my_view to "x-admin", "user";
-- grant to anon as well only for intentionally public data

comment on view app.my_view is '{...}';
```

Use `create or replace view` when redefining; note `or replace` cannot drop or reorder output columns — drop and recreate for that.

## Replica views (cross-schema joins)

PostgREST embeds only within one schema. For every cross-schema FK target you want to join/lookup (most commonly `supasheet.users`), create a same-name replica in your schema:

```sql
create
or replace view app.users
with
  (security_invoker = true) as
select
  *
from
  supasheet.users;

revoke all on app.users
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on app.users to "x-admin",
"user";
```

FK constraints still point at the real table — only `query.join`, `fields.lookups`, FK dropdowns, and view joins use the replica.

## Feature views

See `rules/dashboards.md`, `rules/charts.md`, `rules/reports.md`, and `rules/templates.md` for the comment contracts and required column shapes.

After any view DDL or comment change: `select supasheet.refresh_metadata();`
