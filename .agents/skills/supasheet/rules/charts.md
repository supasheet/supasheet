---
name: supasheet/charts
description: >-
  Chart views: the five chart_type contracts (pie, bar, line, area, radar)
  with required column shapes, date formatting for time series, and starter
  SQL.
type: sub-skill
requires:
  - supasheet
---

# Charts

A chart = a view whose comment is `{"type": "chart", "name": ..., "description": ..., "chart_type": ...}` (optional `"format": "currency"`). Discovered by `supasheet.get_charts()`; shown on `/$schema/chart` to callers whose native role holds `select` on the view.

## Chart contracts (exact column shapes)

| chart_type | Columns                                                       |
| ---------- | ------------------------------------------------------------- |
| `pie`      | exactly two: `label` (slice name), `value` (numeric size)     |
| `bar`      | `label` (x-axis category) + one or more numeric series        |
| `line`     | `date` (formatted period string) + one or more numeric series |
| `area`     | same as line: `date` + one or more numeric series             |
| `radar`    | `metric` (axis name) + one or more numeric series             |

Series column names become legend labels.

## Starter SQL per type

Time-series charts format the period as a string with `to_char(date_trunc(...))` — don't return raw timestamps:

```sql
-- pie
select status::text as label, count(*) as value
from app.tickets
group by status;

-- bar
select p.name as label,
       count(t.id) as total,
       count(t.id) filter (where t.status = 'done') as completed
from app.projects p left join app.tasks t on t.project_id = p.id
group by p.name
order by total desc;

-- line (daily)
select to_char(date_trunc('day', created_at), 'Mon DD') as date,
       count(*) as created,
       count(*) filter (where status = 'resolved') as resolved
from app.tickets
group by date_trunc('day', created_at)
order by date_trunc('day', created_at);

-- area (weekly, stacked series)
select to_char(date_trunc('week', created_at), 'Mon DD') as date,
       count(*) filter (where status = 'open') as open,
       count(*) filter (where status = 'resolved') as resolved
from app.tickets
group by date_trunc('week', created_at)
order by date_trunc('week', created_at);

-- radar
select tm.name as metric,
       count(t.id) as total,
       count(t.id) filter (where t.status = 'done') as completed
from app.team_members tm left join app.tasks t on t.assignee_id = tm.id
group by tm.name;
```

## Full recipe

```sql
create view app.tickets_by_status_pie
with (security_invoker = true) as
select status::text as label, count(*) as value
from app.tickets group by status;

revoke all on app.tickets_by_status_pie from public, anon, authenticated, service_role;
grant select on app.tickets_by_status_pie to "x-admin", "user";

comment on view app.tickets_by_status_pie is '{"type": "chart", "name": "Tickets By Status", "description": "Distribution across statuses", "chart_type": "pie"}';

select supasheet.refresh_metadata ();
```

## Rules

- Suffix names with the chart type: `revenue_trend_line`, `tasks_by_status_pie`, `projects_by_client_bar`, `signup_growth_area`, `team_workload_radar`.
- Always `security_invoker = true`; `select` is the only grant needed.
- Keep name/description in the comment JSON, never as extra SELECT columns.
- Money series: add `"format": "currency"` to the comment.
- Sources: `supabase/demo.sql` (`tasks_by_status_pie`, `projects_by_client_bar`, `revenue_trend_line`, `team_workload_radar`); `supasheet.get_charts()` in `supabase/migrations/20250707035446_charts.sql`.
