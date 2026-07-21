---
name: supasheet/types
description: >-
  Custom enum types and supasheet domain types: schema-scoped enums, the
  committed-transaction rule for enum values, enum badge/progress column
  comments.
type: sub-skill
requires:
  - supasheet
---

# Types (Enums & Domains)

## Custom enums

Define enums **in your module's schema**, named after the column they back:

```sql
begin;

create type app.ticket_status as enum ('open', 'in_progress', 'resolved', 'closed');

create type app.priority_level as enum ('low', 'medium', 'high', 'critical');

commit;
```

Rules:

- All enum DDL (creates AND `alter type ... add value`) lives in an explicit `begin; ... commit;` block at the top of the migration — Postgres cannot use an enum value in the transaction that added it.
- Extending later: `alter type app.ticket_status add value if not exists 'archived';` (values can only be appended, never removed or reordered without recreating the type).
- Enum columns get a default: `status app.ticket_status not null default 'open'`.
- Index enum columns used in filters and kanban grouping.

## Enum column comments (badges & progress)

Every enum column should get a comment mapping values to badge variants/icons; add `"progress": true` for pipeline-like statuses (renders an ordered progress indicator):

```sql
comment on column app.tickets.status is '{
    "progress": true,
    "enums": {
        "open":        {"variant": "info",      "icon": "CircleDot"},
        "in_progress": {"variant": "warning",   "icon": "Loader"},
        "resolved":    {"variant": "success",   "icon": "CheckCircle2"},
        "closed":      {"variant": "secondary", "icon": "XCircle"}
    }
}';
```

Variants: `default` | `secondary` | `success` | `warning` | `destructive` | `info`. Icons are Lucide names.

## Supasheet domain types

Never redefine these — they ship in the base migrations. Use them for rich UI columns:

`supasheet.EMAIL`, `supasheet.TEL`, `supasheet.URL`, `supasheet.RICH_TEXT`, `supasheet.RATING` (0–5), `supasheet.PERCENTAGE`, `supasheet.DURATION` (bigint ms), `supasheet.COLOR`, `supasheet.FILE` (array), `supasheet.AVATAR` (single).

Full definitions, UI behavior, and file-column comment options: `references/data-types.md`.

## Enum vs FK lookup table

- Enum: fixed vocabulary, rendered as badges/kanban columns, changed only by migration.
- FK to a small table: user-editable vocabulary, needs its own resource + permissions.
  Prefer enums for statuses/priorities; prefer lookup tables when admins should manage the values.

After adding/altering types used by exposed tables: `select supasheet.refresh_metadata();`
