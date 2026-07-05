# Table Comment Metadata (the UI configuration language)

A table's `COMMENT` is a JSON object that configures its entire UI: sidebar visibility, alternate views, form layout, filters, conditional fields, and lookups. The TypeScript source of truth is `TableMetadata` in `src/lib/database-meta.types.ts`.

## Full shape

```jsonc
{
  "display": "block", // "block" = show in sidebar, "none" = hidden (URL/inline only)
  "name": "Tickets", // override display name
  "description": "...",
  "icon": "Ticket", // Lucide React icon name
  "group": "Support", // sidebar grouping
  "singleton": false, // true = settings-style single record
  "inline_form": false, // true = editable section on parent detail page (junction/line-item tables)
  "primary_view": "kanban", // id of default view (omit = sheet/table view)
  "views": [
    /* ViewLayout[] */
  ],
  "filter_presets": [
    /* FilterPreset[] */
  ],
  "fields": {
    /* see Fields */
  },
  "query": {
    /* see Query */
  },
  "tabs": ["tasks", "invoices"], // allowlist of related-table tabs on the detail page
}
```

## Views

Each entry: `{ "id", "name", "type", ...type-specific hints }`. The sheet (table) view always exists. Column hints name columns of this table.

| type       | required                           | optional                            |
| ---------- | ---------------------------------- | ----------------------------------- |
| `kanban`   | `group` (enum col), `title`        | `description`, `badge`, `date`      |
| `calendar` | `title`, `start_date`              | `end_date`, `badge`                 |
| `gallery`  | `cover` (FILE/AVATAR col), `title` | `description`, `badge`              |
| `list`     | `title`                            | `description`, `field_1`, `field_2` |
| `tree`     | `parent` (self-FK col), `title`    | `secondary`                         |

```json
"views": [
    {"id": "kanban", "name": "By Status", "type": "kanban", "group": "status", "title": "title", "description": "description", "date": "due_date", "badge": "priority"},
    {"id": "calendar", "name": "Timeline", "type": "calendar", "title": "title", "badge": "status", "start_date": "start_date", "end_date": "due_date"},
    {"id": "gallery", "name": "Gallery", "type": "gallery", "cover": "logo", "title": "name", "description": "summary", "badge": "category"},
    {"id": "list", "name": "All", "type": "list", "title": "name", "description": "status", "field_1": "status", "field_2": "due_date"},
    {"id": "tree", "name": "Org Chart", "type": "tree", "parent": "manager_id", "title": "name", "secondary": "job_title"}
]
```

## Filter presets

One-click filter chips above the table:

```json
"filter_presets": [
    {"id": "active", "name": "Active", "filters": [{"id": "status", "value": "active", "operator": "eq"}]},
    {"id": "high", "name": "High Priority", "filters": [{"id": "priority", "value": ["high", "critical"], "operator": "in"}]}
]
```

## Fields

```jsonc
"fields": {
    "sections": [
        {"id": "overview", "title": "Overview", "fields": ["name", "client_id", "description"]},
        {"id": "extras", "title": "Notes", "collapsible": true, "fields": ["notes"]},
        // per-mode field lists (create | update | read):
        {"id": "adv", "title": "Advanced", "fields": {"create": ["status"], "update": ["status", "closed_at"]}}
    ],
    "metadata": ["created_at", "updated_at"],   // override system columns; default ["deleted_at","created_at","updated_at","created_by","updated_by"]
    "quick_create": ["title", "project_id", "assignee_id"],   // abbreviated quick-create form
    "duplicated": ["title", "description", "status", "tags"], // fields copied on "Duplicate record"
    "behavior": { /* conditional fields */ },
    "lookups":  { /* FK dropdown fill/filter */ }
}
```

Fields not listed in any section are hidden from the forms/detail page.

### Conditional behavior

Keyed by field name; `visible` / `required` / `read_only` each take conditions that must ALL match. Operators: `eq, neq, lt, lte, gt, gte, like, ilike, is, in, not.ilike, not.is, not.in`.

```json
"behavior": {
    "blocked_reason": {
        "visible":  [{"id": "status", "operator": "eq", "value": "blocked"}],
        "required": [{"id": "status", "operator": "eq", "value": "blocked"}]
    },
    "completed_at": {"visible": [{"id": "status", "operator": "eq", "value": "done"}]}
}
```

### Lookups (FK dropdowns)

Keyed by the local FK field. `fill` copies columns from the picked record into local form fields; `filter` restricts the dropdown by another local field's value. The lookup target must be reachable in the same schema (use replica views for cross-schema).

```json
"lookups": {
    "service_id": {
        "fill": [
            {"target": "unit_price", "source": "default_rate"},
            {"target": "description", "source": "name"}
        ]
    },
    "project_id": {
        "filter": [{"on": "client_id", "column": "client_id"}]
    }
}
```

(`filter` reads: when the local `client_id` changes, only offer projects whose `client_id` matches.)

## Query

Default list-view query configuration:

```json
"query": {
    "sort": [{"id": "due_date", "desc": false}],
    "filter": [{"id": "status", "value": "active", "operator": "eq"}],
    "join": [
        {"table": "users", "on": "user_id", "columns": ["name", "email"]},
        {"table": "team_members", "on": "manager_id", "alias": "manager", "columns": ["name"]}
    ],
    "select": ["id", "title", "status"]
}
```

- `join` embeds an already-FK-related, same-schema table into list rows (it does not create relationships). `alias` disambiguates multiple FKs to one table.
- No `between` operator — use paired `gte` + `lte` filters.
- Filter operators are type-dependent: text (`ilike, not.ilike, like, eq, neq, is, not.is`), numeric/date (`eq, neq, lt, lte, gt, gte, is, not.is`), enum (`eq, neq, is, not.is`), array (`in, not.in, is, not.is`), boolean (`is, not.is`), uuid (`eq, neq, is, not.is`).

## Tabs

`"tabs": ["tasks", "milestones", "invoices"]` — allowlist which related tables (by FK) appear as tabs on the detail page. Omit to show all related tables. Does not affect the Audit/Comments pages (those are permission-driven).

## Updatable table views (`based_on`)

A simple single-table view (subset of columns, no joins/aggregates) is auto-updatable through PostgREST and can act as a full sub-resource with its own permissions. Add `"based_on": "<table>"` so the UI reuses the parent table's form machinery; the rest of the table-metadata shape (views, sections, presets) applies on top:

```sql
create view app.ticket_triage
with
  (security_invoker = true) as
select
  id,
  title,
  status,
  priority
from
  app.tickets;

comment on view app.ticket_triage is '{"based_on": "tickets", "name": "Triage", "description": "Status and priority only"}';
```

Grant and permit only the actions the slice should expose (e.g. `select, update`). Use this for role-scoped subsets of wide tables. The view must be Postgres auto-updatable (single table, no joins/aggregates) and must expose the base table's primary key (or a unique column), or detail/create pages won't resolve. See `rules/views.md` for the full recipe.

## Special table modes

- **Singleton**: `"singleton": true` — UI opens the single row directly (settings tables). Don't grant/permit `:delete`.
- **Inline form**: `"inline_form": true` + `"display": "none"` — table renders as an editable section on its parent's detail page (parent detected via FK). Used for junction tables and line items (see `demo.invoice_items`, `demo.project_members`).

## Gotchas

- Comments must be valid JSON — the app `JSON.parse`s them. Multi-line string literals are fine in SQL; for tooling that mangles quotes use dollar-quoting: `comment on table t is $$ {...} $$;`.
- After changing any comment, run `select supasheet.refresh_metadata();`.
- View (non-table) resources use the same base shape (`display`, `name`, `icon`, `views`, `filter_presets`, `fields.sections`) but no form-specific keys — unless tagged `{"type": "report" | "chart" | "dashboard_widget"}`, which routes them to those features instead.

## Authoritative sources

- `src/lib/database-meta.types.ts` — `TableMetadata`, `ViewLayout`, `FieldSection`, `FieldBehavior`, `LookupConfig`, `QueryConfig`, `FilterPreset`
- `supabase/demo.sql` — rich real examples: `demo.clients` (kanban+gallery, sections, presets), `demo.tasks` (behavior, quick_create, duplicated, tree), `demo.invoices` (lookup filter, tabs), `demo.invoice_items` (inline_form, lookup fill), `demo.workspace_settings` (singleton)
