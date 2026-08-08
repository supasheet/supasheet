---
name: supasheet/forms
description: >-
  Custom forms backed by a SQL function: type:form comment, multi-field/
  multi-section UI with relation pickers, listed on a resource's overview
  page, result rendering for object/set returns.
type: sub-skill
requires:
  - supasheet
---

# Custom Forms

A custom form = a SQL function whose comment is `{"type": "form", "resource": ..., "name": ..., ...}`. Discovered by `supasheet.get_forms()`, it's listed as a card on the **target resource's overview page** (`/$schema/resource/$resource`) and opens at `/$schema/resource/$resource/form/$function_name`, where Supasheet renders the function's own arguments as a full form — sections, relation (FK-style) pickers, everything the standard create form supports — then calls the function via RPC on submit.

Use this instead of a row action (a `{"type": "action"}`-tagged function that attaches a button to a resource's _rows_ and auto-fills its arguments from the current record) when the operation needs **more than one or two auto-filled/row-derived arguments** — e.g. picking an unrelated record, entering several free-text/numeric fields, or logging a new record from a different resource's page. Row actions auto-fill from the current row and only support a single enum picker; forms show a full field UI for arbitrary parameters and aren't tied to any specific row.

## Full recipe

```sql
create or replace function demo.log_time_entry (
  p_task_id uuid,
  p_team_member_id uuid,
  p_duration supasheet.DURATION,
  p_is_billable boolean default true,
  p_notes text default null
) returns uuid language plpgsql security invoker
set search_path = '' as $$
declare
  v_id uuid;
begin
  insert into demo.time_entries (task_id, team_member_id, duration, is_billable, notes)
  values (p_task_id, p_team_member_id, p_duration, p_is_billable, p_notes)
  returning id into v_id;

  return v_id;
end;
$$;

comment on function demo.log_time_entry (uuid, uuid, supasheet.DURATION, boolean, text) is '{
    "type": "form",
    "resource": "tasks",
    "name": "Log time",
    "description": "Record time spent on a task without leaving the board.",
    "icon": "Clock",
    "success_message": "Time entry logged",
    "fields": {
        "sections": [
            {"id": "entry", "title": "Entry", "fields": ["p_task_id", "p_team_member_id"]},
            {"id": "duration", "title": "Duration", "fields": ["p_duration", "p_is_billable", "p_notes"]}
        ],
        "relations": {
            "p_task_id": {"table": "tasks", "column": "id", "display": ["title", "status"]},
            "p_team_member_id": {"table": "team_members", "column": "id", "display": ["name", "avatar"]}
        }
    }
}';

revoke all on function demo.log_time_entry (uuid, uuid, supasheet.DURATION, boolean, text)
from public, authenticated, service_role;

grant execute on function demo.log_time_entry (uuid, uuid, supasheet.DURATION, boolean, text)
to "x-admin", "user";

select supasheet.refresh_metadata ();
```

## Comment keys

```json
{
  "type": "form",
  "resource": "tasks",
  "name": "Log time",
  "description": "Optional helper text under the form title",
  "icon": "Clock",
  "success_message": "Time entry logged",
  "fields": {
    "sections": [
      {
        "id": "entry",
        "title": "Entry",
        "fields": ["p_task_id", "p_team_member_id"]
      }
    ],
    "behavior": {
      "p_notes": { "...": "same FieldBehavior shape as table column comments" }
    },
    "lookups": {
      "p_task_id": { "...": "same LookupConfig shape as table column comments" }
    },
    "relations": {
      "p_task_id": {
        "schema": "demo",
        "table": "tasks",
        "column": "id",
        "display": ["title", "status"]
      }
    }
  }
}
```

- `resource` — the table/view name (no schema prefix) whose overview page lists this form. Independent of the schema the function itself lives in.
- `fields.sections` / `fields.behavior` / `fields.lookups` reuse the exact shapes documented in `references/table-metadata.md` for table column comments — the form is rendered by the same `ResourceFormLayout` component as a normal create form.
- `fields.relations` is form-specific: for each parameter, `{table, column?, display}` turns it into an FK-style picker against `table` (defaults: same schema as `resource`, `column: "id"`). This is how a function parameter with no real foreign key gets a searchable relation picker in the UI.

## Argument naming

Parameters are matched to field metadata by stripping a leading `p_`: `p_task_id` → field `task_id` unless `fields.behavior`/`fields.lookups` overrides it, and its display label defaults to `Task id` → override with `behavior`/column-style `name` in the section fields list if needed. Every parameter without a `default` in the SQL signature is required in the form.

## Result rendering

- If the function `returns void` (or nothing meaningfully object-shaped), Supasheet toasts `success_message` and navigates back to the resource.
- If it returns a **single row** (a table row type or `out` parameters), the UI renders the created/returned record as a detail card instead of navigating away — see `demo.create_project_for_client`.
- If it returns `setof <row>` or `table(...)`, the UI renders the rows as a table — useful for bulk-generate/preview operations that don't just insert one row, e.g. `demo.generate_invoice_items_from_tasks` (inserts and returns multiple invoice items) or `demo.preview_team_billables` (pure read, no writes at all — a form can be used purely for parameterized reporting).

## Rules

- `security invoker` unless the form must cross a permission boundary the caller doesn't have — same rule as actions/policies.
- `REVOKE ALL` then `GRANT EXECUTE` directly to the specific roles that should see the form card — visibility is `has_function_privilege`-driven, no separate permission flag.
- Keep the function focused on one operation; validate with `RAISE EXCEPTION` (surfaced as an error toast) rather than silently no-op-ing.
- A form doesn't have to write anything — it's equally valid as a parameterized read/report UI (`preview_team_billables`).
- Sources: `supabase/demo.sql` (`log_time_entry`, `create_project_for_client`, `generate_invoice_items_from_tasks`, `preview_team_billables`); `supasheet.get_forms` / `supasheet.get_form_fields` in `supabase/migrations/99999999999999_meta.sql`; `src/hooks/use-custom-form.ts`, `src/components/resource/custom-form.tsx` for the client-side rendering contract.
