# Supasheet — Agent Instructions

Supasheet is a complete, opinionated open-source CMS platform built on Supabase
— auth (MFA, OAuth), user management, RBAC, auto-generated CRUD with
sheet/kanban/calendar/gallery views, dashboards, charts, reports, file storage,
and audit logs, all out of the box.

**Tech stack:** React 19 + Vite, TanStack Router (file-based) / Query / Form /
Table, shadcn/ui (Base UI variant), Tailwind CSS v4, Lexical, Recharts,
Supabase (Auth, Database, Storage, Edge Functions).

## The most important rule

**Features are implemented in SQL migrations, not app code.** New tables,
modules, alternate views (kanban/calendar/gallery/list/tree), dashboard widgets,
charts, reports, roles/permissions, RLS policies, notification and audit
triggers, and storage-backed columns are all pure SQL under
`supabase/migrations/`. Creating a table auto-generates its data table, forms,
and detail pages; JSON in table/column/view `COMMENT`s configures everything
else. If you find yourself writing React CRUD pages for a new resource, stop —
the app renders them automatically from the database schema.

Before any database or schema work, read
[`.agents/skills/supasheet/SKILL.md`](.agents/skills/supasheet/SKILL.md) and
follow its workflow. Then load the files matching your task:

- `.agents/skills/supasheet/rules/` — one file per feature area (tables, views,
  materialized-views, types, dashboards, charts, reports, templates, policies,
  triggers, roles-permissions, storage, configuration)
- `.agents/skills/supasheet/references/` — deep dives (new-resource walkthrough,
  table metadata JSON, data types, RBAC, notifications, audit logs, comments)

Agents with native skill support (e.g. Claude Code via `.claude/skills/`) load
this automatically; everyone else should read the files directly.

## Non-negotiables for SQL work

- Every migration that touches schema ends with `select supasheet.refresh_metadata();`
- New schemas must be added to `supabase/config.toml` under both `[api].schemas`
  and `[api].extra_search_path`
- RLS on every table. There's no permissions table — roles are real Postgres
  roles (`x-admin`/`admin`/`user`, `nologin`), access is real `GRANT`s, and the
  JWT's `role` claim (via a Custom Access Token Hook) drives PostgREST's
  `SET ROLE`. Most policies are just `using (true)` since grants already gate
  who can attempt the operation; use `pg_has_role(current_user, '<role>',
  'member')` for row-level admin overrides
- Revoke all default grants, then grant back exactly the intended operations
  directly to the specific native roles that should hold them — never to
  `authenticated` itself
- Custom roles are just `create role "<name>" nologin;` + grants — no enum to extend first
- After schema changes, regenerate types:
  `npx supabase gen types typescript --local --schema public --schema supasheet --schema <yours> > src/lib/database.types.ts`

Canonical examples to imitate: `supabase/demo.sql` (one module exercising every
feature) and `supabase/examples/*.sql` (14 domain modules with seeds).
`src/lib/database-meta.types.ts` defines every comment-JSON shape the UI parses.

## Project structure

App code changes are for the platform itself (new view types, UI components,
integrations) — not for adding resources. Import from `src/` using the `#/`
alias (not `@/`).

- `src/components/` — UI by feature module: `auth/`, `resource/`, `storage/`,
  `dashboard/`, `chart/`, `report/`, `audit-logs/`, `users/`, `account/`,
  `layouts/`, `editor/`, `data-table/`; shadcn/ui primitives in `ui/`
- `src/config/` — app-level constants (data table defaults, database config)
- `src/hooks/` — shared hooks (permissions, user, file upload, mobile, data table)
- `src/integrations/` — third-party setup (TanStack Query provider under `tanstack-query/`)
- `src/lib/` — utilities: formatting, field definitions, column builders, exports
- `src/lib/supabase/` — all backend logic: `client.ts`, `filter.ts`, and `data/`
  with query/mutation functions per domain (`auth.ts`, `resource.ts`, `users.ts`,
  `storage.ts`, `chart.ts`, `dashboard.ts`, `report.ts`, `security.ts`, ...)
- `src/routes/` — TanStack Router file-based pages:
  - `__root.tsx` (root layout/context), `index.tsx` (entry redirect)
  - `auth/` — sign-in, sign-up, MFA, forgot/update password
  - `account/` — profile, security, identities, roles & permissions
  - `core/` — `users/`, `audit_logs/`, `notifications/`
  - `storage/` — file browser per bucket (`$bucketId/`)
  - `$schema/` — dynamic schema module: `resource/$resource/` (list, `new`,
    `update/`, `detail/`, `kanban/`, `calendar/`, `gallery/`, `report`),
    `dashboard/`, `chart/`, `report/$report/`, `sql-editor/$snippet/`
- `supabase/` — `migrations/` (ordered SQL), `functions/` (admin-\* Deno edge
  functions for user operations), `examples/` (seed SQL)

## Data fetching pattern (routes)

Routes follow a two-layer pattern:

**Loader** — prefetches into the TanStack Query cache via `ensureQueryData`.
Does **not** return mutable data; only returns schema/metadata that never
changes (e.g. `tableSchema`, `columnsSchema`, `kanbanView`).

```ts
loader: async ({ context, params, deps }) => {
  // Guard: await and check, but don't return mutable data
  const record = await context.queryClient.ensureQueryData(dataQueryOptions(...))
  if (!record) throw notFound()

  // Prefetch mutable data into cache (fire and forget)
  context.queryClient.ensureQueryData(mutableDataQueryOptions(...))

  // Only return immutable schema/metadata
  return { tableSchema, columnsSchema }
}
```

**Component** — reads schema/metadata from `Route.useLoaderData()` and
subscribes to mutable data via `useSuspenseQuery`:

```ts
function RouteComponent() {
  const { tableSchema, columnsSchema } = Route.useLoaderData()
  const { data } = useSuspenseQuery(mutableDataQueryOptions(...))
}
```

**Why:** `useLoaderData()` is a static snapshot that only updates when the
loader re-runs. `useSuspenseQuery` subscribes to the TanStack Query cache, so
`queryClient.invalidateQueries(...)` after a mutation immediately refetches and
re-renders.

**Mutation invalidation** — after any mutation, invalidate by query key prefix:

```ts
queryClient.invalidateQueries({
  queryKey: ["supasheet", "resource-data", schema, resource],
})
```

## Commands

```bash
npm run dev          # dev server on :3000
npm run build        # production build
npm run test         # vitest
npm run lint         # eslint
npm run typecheck    # tsc --noEmit
npm run check        # prettier --write + eslint --fix

npx supabase start          # local Supabase stack
npx supabase migration up   # apply new migrations
npx supabase db reset       # replay all migrations + seed from scratch
```

Verify migrations against the local stack (`supabase start`) before considering
the task done.
