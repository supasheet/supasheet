---
name: supasheet/views
description: >-
  Creating plain views and updatable "based_on" table views: security_invoker,
  revoke/grant, permission values, replica views for cross-schema joins.
type: sub-skill
requires:
  - supasheet
---

# Views

Views serve four roles in Supasheet, all driven by their comment JSON:

| Role | Comment `type` | Permissions needed |
|---|---|---|
| Feature view (dashboard widget / chart / report / template) | `dashboard_widget` / `chart` / `report` / `template` | `:select` only |
| Updatable table view (restricted slice of a table) | none — has `"based_on"` key | `:select/:insert/:update/:delete` |
| Replica view (cross-schema embed fix) | none | `:select` only |
| Plain resource view (read-only listing) | none | `:select` only |

## Canonical creation pattern

Always `security_invoker = true` (the caller's RLS applies), always revoke-then-grant:

```sql
create view app.my_view
with (security_invoker = true) as
select ...;

revoke all on app.my_view from public, anon, authenticated, service_role;

grant select on app.my_view to authenticated;
-- grant to anon as well only for intentionally public data

alter type supasheet.app_permission add value if not exists 'app.my_view:select';
-- (in the committed enum block)

comment on view app.my_view is '{...}';

insert into supasheet.role_permissions (role, permission)
values ('x-admin', 'app.my_view:select'), ('user', 'app.my_view:select')
on conflict (role, permission) do nothing;
```

Use `create or replace view` when redefining; note `or replace` cannot drop or reorder output columns — drop and recreate for that.

## Updatable table views (`based_on`)

A view over a subset of a table's columns acts as a full sub-resource (own permissions, own sidebar entry, writable through PostgREST since simple single-table views are auto-updatable). Declare its parent with `based_on` so the UI reuses the table's form machinery:

```sql
create view app.ticket_triage
with (security_invoker = true) as
select id, title, status, priority from app.tickets;

revoke all on app.ticket_triage from public, anon, authenticated, service_role;
grant select, update on app.ticket_triage to authenticated;

-- permissions: add the actions this view should expose
alter type supasheet.app_permission add value if not exists 'app.ticket_triage:select';
alter type supasheet.app_permission add value if not exists 'app.ticket_triage:update';

comment on view app.ticket_triage is '{"based_on": "tickets", "name": "Triage", "description": "Status and priority only"}';
```

The comment accepts the full table-metadata shape on top of `based_on` (views, sections, presets — see `references/table-metadata.md`). RLS of the underlying table still applies via `security_invoker`.

Requirements for the app to treat it as a resource:

- The view must be **Postgres auto-updatable**: single base table, plain column list — no joins, aggregates, `distinct`, `group by`, or set operations.
- The view must **expose the base table's primary key** (or at least a unique column) — otherwise detail/create pages cannot resolve.
- Supasheet borrows the base table's column metadata (types, enum badges, lookups) filtered to the view's columns, and resolves detail-page relationship tabs against `based_on`.

## Replica views (cross-schema joins)

PostgREST embeds only within one schema. For every cross-schema FK target you want to join/lookup (most commonly `supasheet.users`), create a same-name replica in your schema:

```sql
create or replace view app.users
with (security_invoker = true) as
select * from supasheet.users;

revoke all on app.users from public, anon, authenticated, service_role;
grant select on app.users to authenticated;
-- plus 'app.users:select' permission value + role_permissions seed
```

FK constraints still point at the real table — only `query.join`, `fields.lookups`, FK dropdowns, and view joins use the replica.

## Feature views

See `rules/dashboards.md`, `rules/charts.md`, `rules/reports.md`, and `rules/templates.md` for the comment contracts and required column shapes.

After any view DDL or comment change: `select supasheet.refresh_metadata();`
