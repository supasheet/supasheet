---
name: supasheet/configuration
description: >-
  App configuration via the supasheet.configs key-value table: keys, jsonb
  values, is_public visibility, and write-by-migration rule.
type: sub-skill
requires:
  - supasheet
---

# App Configuration

`supasheet.configs` is a key-value table consumed by the app shell:

```
id | key text unique | value jsonb | description text | is_public boolean
```

## Rules

- Reads need no `role_permissions` entry — RLS handles it: `anon` sees only `is_public = true`, `authenticated` sees all rows.
- Writes are revoked from all client roles — change values **by migration** (or direct DB access), never through the API.
- Known keys consumed by the app: `app.name`, `app.description` (branding). Add your own namespaced keys (`app.*`, `<module>.*`) for feature flags or settings your SQL (or custom code) reads.

## Setting values

```sql
insert into
  supasheet.configs (key, value, description, is_public)
values
  (
    'app.name',
    '"Acme Ops"',
    'Application display name',
    true
  ),
  (
    'app.description',
    '"Internal operations console"',
    'Shown on the sign-in page',
    true
  ) on conflict (key) do
update
set
  value = excluded.value,
  description = excluded.description,
  is_public = excluded.is_public;
```

`value` is jsonb — strings must be JSON-encoded (`'"Acme Ops"'`), and structured values are fine:

```sql
insert into
  supasheet.configs (key, value, description, is_public)
values
  (
    'app.features',
    '{"exports": true, "beta_charts": false}',
    'Feature flags',
    false
  ) on conflict (key) do
update
set
  value = excluded.value;
```

## Module settings tables vs configs

- `supasheet.configs`: app-wide, admin-authored, changed by migration.
- A singleton table in your schema (`"singleton": true` comment): module settings that end-users with permission should edit through the UI. Prefer this for anything editable at runtime — see `references/table-metadata.md`.

Source: `supabase/migrations/20250405005132_configs.sql`.
