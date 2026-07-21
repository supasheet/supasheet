---
name: supasheet/reports
description: >-
  Report views: denormalized read-only tables with CSV/Excel export,
  registered via a type:report comment, select-only permission.
type: sub-skill
requires:
  - supasheet
---

# Reports

A report = a view whose comment is `{"type": "report", "name": ..., "description": ...}` (those three keys only). Discovered by `supasheet.get_reports()`; renders as a filterable, exportable table at `/$schema/report/$name` for callers whose native role holds `select` on the view.

## Full recipe

```sql
create
or replace view app.tickets_report
with
  (security_invoker = true) as
select
  t.id,
  t.title,
  t.status,
  u.name as owner,
  count(c.id) as comment_count,
  t.created_at
from
  app.tickets t
  left join app.users u on u.id = t.user_id -- replica view, not supasheet.users
  left join app.ticket_comments c on c.ticket_id = t.id
group by
  t.id,
  u.name;

revoke all on app.tickets_report
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on app.tickets_report to "x-admin",
  "user";

comment on view app.tickets_report is '{"type": "report", "name": "Tickets Report", "description": "Tickets with owner and comment rollups"}';

select
  supasheet.refresh_metadata ();
```

## Rules

- Suffix names with `_report`: `clients_report`, `team_utilization_report`.
- Denormalize: join names in (via same-schema replica views), roll up child counts/sums with `count(distinct ...)` and `sum(...) filter (where ...)`.
- Reports are read-only — `select` grant only.
- Always `security_invoker = true` so the viewer's RLS applies.
- Column headers can be renamed with column comments on the view: `comment on column app.tickets_report.owner is '{"name": "Owner"}';`
- Heavy reports → materialized view instead (same comment shape); see `rules/materialized-views.md`.
- Sources: `supabase/demo.sql` (`clients_report`, `projects_report`, `invoices_report`, `team_utilization_report`); `supasheet.get_reports()` in `supabase/migrations/20250707035445_reports.sql`.
