# Table Comment Metadata (the UI configuration language)

A table's `COMMENT` is a JSON object that configures its entire UI: sidebar visibility, alternate views, form layout, filters, conditional fields, and lookups. The TypeScript source of truth is `TableMetadata` in `src/lib/database-meta.types.ts`.

## Full shape

```jsonc
{
  "display": "block", // "block" = show in sidebar, "none" = hidden (URL/inline only)
  "name": "Tickets", // override display name
  "description": "...",
  "icon": "Ticket", // Lucide React icon name
  "collapsible_group": "Support", // sidebar collapsible section this resource is grouped under
  "singleton": false, // true = settings-style single record
  "inline_form": false, // true = editable section on parent detail page (junction/line-item tables)
  "primary_view": "kanban", // id of default view (omit = sheet/table view)
  "views": [/* ViewLayout[] */],
  "filter_presets": [/* FilterPreset[] */],
  "links": [/* ResourceLink[] */],
  "fields": {/* see Fields */},
  "query": {/* see Query */},
  "detail": {/* see Detail — table-only, views have no detail page */},
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

## Links

Quick-link shortcuts shown on the resource landing page — to an external dashboard/doc, or to another resource/report/route in the app:

```json
"links": [
    {"id": "docs", "name": "Runbook", "url": "https://wiki.example.com/support-runbook", "icon": "BookOpen"},
    {"id": "billing", "name": "Billing Report", "url": "/demo/report/billing-summary", "description": "MRR and churn by plan"}
]
```

`url` starting with a scheme (e.g. `https://`) opens in a new tab; anything else (e.g. `/schema/resource/...`) is treated as an internal app route and navigated client-side.

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

Keyed by the local FK field. `fill` copies columns from the picked record into local form fields; `filter` restricts the dropdown by another local field's value. `source_column`/`target_column` follow the same direction as `Relationship.source_column_name`/`target_column_name`: `source_column` is always on this table's own form, `target_column` is always on the lookup table being referenced. The lookup target must be reachable in the same schema (use replica views for cross-schema).

```json
"lookups": {
    "service_id": {
        "fill": [
            {"source_column": "unit_price", "target_column": "default_rate"},
            {"source_column": "description", "target_column": "name"}
        ]
    },
    "project_id": {
        "filter": [{"source_column": "client_id", "target_column": "client_id"}]
    }
}
```

(`filter` reads: when the local `client_id` field changes, only offer projects whose `client_id` matches.)

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

## Detail

Table-only — view resources have no detail page. Configures the detail page's heading and which related-table tabs it shows (not the fields in the page body — that's `fields.sections`):

```json
"detail": {
    "header": {"title": "name", "badges": ["status", "tags"]},
    "tabs": ["tasks", "milestones", "invoices"]
}
```

- `header.title` names a column whose value renders as the page heading (falls back to the primary key when empty).
- `header.badges` names columns rendered as badges next to the heading.
- `tabs` allowlists which related tables (by FK) appear as tabs. Entries are the related table's own name, unless a `query.join[].alias` is configured for it (then use the alias instead). Omit to show all related tables. Does not affect the Audit/Comments pages (those are permission-driven).

## Special table modes

- **Singleton**: `"singleton": true` — UI opens the single row directly (settings tables). Don't grant/permit `:delete`.
- **Inline form**: `"inline_form": true` + `"display": "none"` — table renders as an editable section on its parent's detail page (parent detected via FK). Used for junction tables and line items (see `demo.invoice_items`, `demo.project_members`).

## Gotchas

- Comments must be valid JSON — the app `JSON.parse`s them. Multi-line string literals are fine in SQL; for tooling that mangles quotes use dollar-quoting: `comment on table t is $$ {...} $$;`.
- After changing any comment, run `select supasheet.refresh_metadata();`.
- View (non-table) resources use the same base shape (`display`, `name`, `icon`, `views`, `filter_presets`, `links`, `fields.sections`) but no form-specific keys — unless tagged `{"type": "report" | "chart" | "dashboard_widget" | "template"}`, which routes them to those features instead.

## Authoritative sources

- `src/lib/database-meta.types.ts` — `TableMetadata`, `ViewLayout`, `FieldSection`, `FieldBehavior`, `LookupConfig`, `QueryConfig`, `FilterPreset`, `ResourceLink`
- `supabase/demo.sql` — rich real examples: `demo.clients` (kanban+gallery, sections, presets), `demo.tasks` (behavior, quick_create, tree), `demo.invoices` (lookup filter, tabs), `demo.invoice_items` (inline_form, lookup fill), `demo.workspace_settings` (singleton)
