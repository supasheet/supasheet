---
name: supasheet
description: Supasheet SQL conventions for implementing new features in this self-hosted admin panel. Use this skill when adding a new resource (table), module/schema, dashboard widget, chart, report, notification trigger, audit logging, comments, roles/permissions, RLS policies, or file/storage columns in a Supasheet project. Everything is done in SQL migrations — no app code.
license: MIT
metadata:
  author: supasheet
  version: "1.0.0"
  organization: Supasheet
  date: July 2026
  abstract: Complete guide to building Supasheet features purely in SQL — tables and views plus JSON comments drive the entire UI (data tables, forms, kanban/calendar/gallery/list/tree views, dashboards, charts, reports), while RBAC, RLS, audit logs, comments, and notifications are wired through the supasheet schema helpers.
---

# Supasheet SQL Development

Supasheet is a SQL-first admin panel built on Supabase. Creating a table auto-generates its data table, forms, and detail pages; JSON in table/column/view `COMMENT`s configures views, field sections, dashboards, charts, and reports. New features are implemented entirely in SQL migrations — no React/app code is needed or wanted.

## When to Apply

Use this skill whenever implementing anything in a Supasheet project's database: new tables/modules, alternate views (kanban/calendar/gallery/list/tree), dashboard widgets, charts, reports, notifications, audit logging, comments, permissions, or storage-backed columns.

## The Universal Workflow

Every feature follows the same migration shape. Order matters.

1. **Create a migration** — `supabase/migrations/<YYYYMMDDHHMMSS>_<name>.sql`.
2. **Create the schema** (one Postgres schema per domain) and `grant usage on schema <s> to authenticated;`.
3. **Add permission enum values in a committed block** — enum values must commit before they can be used:
   ```sql
   begin;
   alter type supasheet.app_permission add value if not exists '<schema>.<resource>:select';
   alter type supasheet.app_permission add value if not exists '<schema>.<resource>:insert';
   -- ...update/delete/audit/comment as needed, one per resource
   commit;
   ```
4. **Create tables/views** using Supasheet domain types (`supasheet.EMAIL`, `supasheet.FILE`, …) with JSON `COMMENT`s.
5. **Lock down grants** — `revoke all ... from public, anon, authenticated, service_role;` then `grant` exactly the intended operations to `authenticated`.
6. **Enable RLS** and add policies gated by `supasheet.has_permission('<schema>.<table>:<action>')`.
7. **Index** FK columns, filtered columns, and sort columns.
8. **Seed `supasheet.role_permissions`** so at least one role can see the resource.
9. **Attach triggers** — audit and/or notification triggers as needed.
10. **End the migration with `select supasheet.refresh_metadata();`** — the metadata catalog is materialized views and is NOT auto-refreshed.
11. **Expose the schema** in `supabase/config.toml` under BOTH `[api].schemas` and `[api].extra_search_path`, then restart Supabase.
12. **Regenerate types** — `npx supabase gen types typescript --local --schema public --schema supasheet --schema <yours> > src/lib/database.types.ts`.

## Critical Gotchas

- Permission strings are `"<schema>.<resource>:<action>"`; actions: `select`, `insert`, `update`, `delete`, `audit`, `comment` (plus `:select` for every widget/chart/report view).
- FKs must reference real tables (`references supasheet.users (id)`), but PostgREST cannot embed across schemas — every app schema needs a same-name **replica view**: `create view <schema>.users with (security_invoker = true) as select * from supasheet.users;`.
- All feature views are created `with (security_invoker = true)`.
- Table/column comments are JSON; keep them valid JSON (the UI parses them). Roles/permissions live in tables, never in the JWT.
- Junction tables: no `:update` permission, `"inline_form": true`, `"display": "none"`. Singletons: `"singleton": true`, no `:delete`.
- The audit DELETE trigger must be `BEFORE DELETE`; INSERT/UPDATE are `AFTER`.
- `supasheet.create_notification()` is service_role-only — call it from a `security definer set search_path = ''` trigger function.

## Rules (by feature area)

One rule file per feature area, mirroring how Supasheet organizes a schema (tables, views, materialized views, types, dashboard, chart, report) plus the cross-cutting core areas (roles, storage, configuration). Load the one matching what you're adding.

| Rule | Covers |
|---|---|
| [rules/tables.md](rules/tables.md) | Creating/altering tables: order of operations, grants, RLS set, constraints, indexes, FKs |
| [rules/views.md](rules/views.md) | Plain views, updatable `based_on` table views, replica views for cross-schema joins |
| [rules/materialized-views.md](rules/materialized-views.md) | Matviews as resources/reports; catalog vs data refresh |
| [rules/types.md](rules/types.md) | Custom enums, committed-transaction rule, enum badge comments, domain usage |
| [rules/dashboards.md](rules/dashboards.md) | Widget contracts card_1..card_4 / table_1 / table_2 with starter SQL |
| [rules/charts.md](rules/charts.md) | Chart contracts pie/bar/line/area/radar, date formatting, starter SQL |
| [rules/reports.md](rules/reports.md) | Report views: denormalized, select-only, exportable |
| [rules/templates.md](rules/templates.md) | Template views: bulk-insert payloads applied via supasheet.apply_template |
| [rules/policies.md](rules/policies.md) | RLS authoring: clauses per command, permissive vs restrictive, performance |
| [rules/triggers.md](rules/triggers.md) | Audit, notification, business (rollup), and maintenance triggers |
| [rules/roles-permissions.md](rules/roles-permissions.md) | Permission format, seeding matrix, custom roles |
| [rules/storage.md](rules/storage.md) | FILE/AVATAR columns, uploads bucket paths, custom buckets |
| [rules/configuration.md](rules/configuration.md) | supasheet.configs key-value settings |

## References (deep dives)

| Priority | File | When to load |
|---|---|---|
| High | [references/new-resource.md](references/new-resource.md) | New table, module, or schema — the full end-to-end worked example |
| High | [references/table-metadata.md](references/table-metadata.md) | The complete table comment JSON language: views, sections, presets, behavior, lookups, query, tabs, based_on |
| High | [references/data-types.md](references/data-types.md) | Domain type definitions and all column comment options |
| Medium | [references/rbac.md](references/rbac.md) | RBAC architecture: enums, tables, helper functions, bootstrap |
| Medium | [references/notifications.md](references/notifications.md) | create_notification internals, recipient resolvers, full trigger examples |
| Medium | [references/audit-logs.md](references/audit-logs.md) | audit_logs schema, TG_ARGV PK arg, global vs per-record permissions |
| Low | [references/comments.md](references/comments.md) | Per-record comments enablement and comment-notify pairing |

## Canonical In-Repo Examples

- `supabase/demo.sql` — one coherent module exercising every feature (RBAC, all view types, widgets, charts, reports, notifications, audit, seed data).
- `supabase/examples/*.sql` — 14 domain modules (desk, crm, hr, store, blog, …) with matching `*_seed.sql` files.
- `src/lib/database-meta.types.ts` — the TypeScript source of truth for every comment-JSON shape.
- `supabase/migrations/` — the supasheet base schema (types, RBAC, audit, notifications, comments, storage).
