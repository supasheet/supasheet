# Creating a New Resource (Table / Module)

The complete, ordered checklist for adding a table (or a whole schema module) to Supasheet. Follow every step — missing grants, permissions, or the final metadata refresh are the most common failure modes.

## 0. Migration file

```
supabase/migrations/<YYYYMMDDHHMMSS>_<module>.sql
```

Requires the base Supasheet migrations (`supabase/migrations/*`) to already be applied.

## 1. Schema

One Postgres schema per business domain (`crm`, `desk`, `hr`, …). `public` works too for simple projects.

```sql
create schema if not exists app;

grant usage on schema app to authenticated;
```

## 2. Enums + permission values (must commit before use)

Postgres cannot use an enum value in the same transaction that added it, so wrap enum DDL in an explicit `begin; ... commit;` block at the top of the migration.

```sql
begin;

create type app.ticket_status as enum('open', 'in_progress', 'resolved', 'closed');

-- One permission value per resource+action. Actions: select/insert/update/delete/audit/comment.
alter type supasheet.app_permission add value if not exists 'app.tickets:select';
alter type supasheet.app_permission add value if not exists 'app.tickets:insert';
alter type supasheet.app_permission add value if not exists 'app.tickets:update';
alter type supasheet.app_permission add value if not exists 'app.tickets:delete';
alter type supasheet.app_permission add value if not exists 'app.tickets:audit';
alter type supasheet.app_permission add value if not exists 'app.tickets:comment';

-- Views (reports/widgets/charts) only need :select
alter type supasheet.app_permission add value if not exists 'app.tickets_report:select';

-- Replica users view (see step 3)
alter type supasheet.app_permission add value if not exists 'app.users:select';

commit;
```

## 3. Replica users view (required per schema)

PostgREST resolves joins within a single schema, so FKs to `supasheet.users` cannot be embedded directly. Create a same-name replica view in your schema. The FK constraints still reference the real table — a FK can never target a view.

```sql
create or replace view app.users
with (security_invoker = true) as
select * from supasheet.users;

revoke all on app.users from public, anon, authenticated, service_role;

grant select on app.users to authenticated;
```

Apply the same pattern for any other cross-schema table you need to join/lookup.

## 4. Table

Use `supasheet.*` domain types for rich UI columns (see `data-types.md`) and attach JSON comments (see `table-metadata.md`).

```sql
create table app.tickets (
  id uuid primary key default extensions.uuid_generate_v4 (),
  title varchar(255) not null,
  description supasheet.RICH_TEXT,
  status app.ticket_status not null default 'open',
  attachment supasheet.file,
  user_id uuid default auth.uid () references supasheet.users (id) on delete set null,
  created_at timestamptz default current_timestamp,
  updated_at timestamptz default current_timestamp
);

comment on table app.tickets is '{
    "icon": "Ticket",
    "display": "block",
    "query": {
        "sort": [{"id": "created_at", "desc": true}],
        "join": [{"table": "users", "on": "user_id", "columns": ["name", "email"]}]
    }
}';

comment on column app.tickets.status is '{
    "enums": {
        "open":        {"variant": "info", "icon": "CircleDot"},
        "in_progress": {"variant": "warning", "icon": "Loader"},
        "resolved":    {"variant": "success", "icon": "CheckCircle2"},
        "closed":      {"variant": "secondary", "icon": "XCircle"}
    }
}';

comment on column app.tickets.attachment is '{"accept": "*", "maxFiles": 5}';
```

## 5. Grants (revoke first, then grant exactly what's needed)

```sql
revoke all on table app.tickets from public, anon, authenticated, service_role;

grant select, insert, update, delete on table app.tickets to authenticated;
```

Variants: junction tables get `select, insert, delete` (no update); singletons get `select, insert, update` (no delete); report/widget/chart views get `select` only.

## 6. Row Level Security

Every policy checks `supasheet.has_permission()`. Add `user_id = auth.uid() and ...` when rows are owner-scoped.

```sql
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

## 7. Indexes

Index FK columns, filtered columns (status/enums), and default-sort columns.

```sql
create index idx_app_tickets_user_id on app.tickets (user_id);
create index idx_app_tickets_status on app.tickets (status);
create index idx_app_tickets_created_at on app.tickets (created_at desc);
```

## 8. Triggers (optional but standard)

- Audit logging → see `audit-logs.md`
- Notifications → see `notifications.md`
- `updated_at` maintenance: `supasheet.set_updated_at()` / `supasheet.set_updated_by()` are available.

## 9. Seed role permissions

Nothing is visible until a role holds the permission. `x-admin` conventionally gets everything; `user` gets a reduced set (typically no delete/audit).

```sql
insert into supasheet.role_permissions (role, permission) values
  ('x-admin', 'app.tickets:select'),
  ('x-admin', 'app.tickets:insert'),
  ('x-admin', 'app.tickets:update'),
  ('x-admin', 'app.tickets:delete'),
  ('x-admin', 'app.tickets:audit'),
  ('x-admin', 'app.tickets:comment'),
  ('x-admin', 'app.users:select'),
  ('user', 'app.tickets:select'),
  ('user', 'app.tickets:insert'),
  ('user', 'app.tickets:update'),
  ('user', 'app.tickets:comment'),
  ('user', 'app.users:select')
on conflict (role, permission) do nothing;
```

## 10. Refresh the metadata catalog (always last)

`supasheet.tables/columns/views/materialized_views` are materialized views. They do NOT refresh automatically — every migration that touches DDL, comments, or enums must end with:

```sql
select supasheet.refresh_metadata ();
```

## 11. Expose the schema to PostgREST

`supabase/config.toml` — add the schema to BOTH arrays (the `supasheet` schema must always stay listed):

```toml
[api]
schemas = ["public", "graphql_public", "supasheet", "app"]
extra_search_path = ["public", "extensions", "supasheet", "app"]
```

Then `npx supabase stop && npx supabase start` (local) or set "Exposed schemas" in Project Settings → Data API (cloud).

## 12. Regenerate TypeScript types

```bash
npx supabase gen types typescript --local --schema public --schema supasheet --schema app > src/lib/database.types.ts
```

## Variants

### Junction table (many-to-many)

Insert/delete only, hidden from the sidebar, rendered inline on the parent detail page:

```sql
comment on table app.ticket_watchers is '{
    "icon": "UserPlus",
    "inline_form": true,
    "display": "none",
    "query": {
        "join": [
            {"table": "tickets", "on": "ticket_id", "columns": ["title", "status"]},
            {"table": "users", "on": "user_id", "columns": ["name", "email"]}
        ]
    }
}';
```

Grant `select, insert, delete` only; add only `:select`, `:insert`, `:delete` permissions; add a `unique (ticket_id, user_id)` constraint.

### Singleton (settings table)

```sql
comment on table app.settings is '{"icon": "Settings", "display": "block", "singleton": true, ...}';
```

Grant `select, insert, update` only (no delete permission, no delete grant). The UI opens the single record directly.

### Materialized view resource

Same comment shape as tables, `:select` only. Needs a unique index for `refresh materialized view concurrently`. Remember: `supasheet.refresh_metadata()` refreshes the *catalog*; `refresh materialized view app.my_mv` refreshes the *data*.

## Authoritative sources

- `supabase/demo.sql` — full worked module (clients/projects/tasks/invoices), including junction (`project_members`) and singleton (`workspace_settings`).
- `supabase/examples/*.sql` — per-domain modules; `supabase/examples/apply.sh` applies them.
- `supabase/config.toml` — commented-out arrays show how example schemas are enabled.
