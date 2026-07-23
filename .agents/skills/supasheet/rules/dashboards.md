---
name: supasheet/dashboards
description: >-
  Dashboard widget views: the twelve widget_type contracts (card_1..card_6,
  table_1, table_2, list_1..list_4) with required output columns and starter SQL.
type: sub-skill
requires:
  - supasheet
---

# Dashboard Widgets

A widget = a view whose comment is `{"type": "dashboard_widget", "name": ..., "description": ..., "widget_type": ...}`. Discovered by `supasheet.get_widgets()`; shown on `/$schema/dashboard` to callers whose native role holds `select` on the view.

## Widget contracts (exact required columns)

| widget_type | Renders                  | Required columns                                                                                       |
| ----------- | ------------------------ | --------------------------------------------------------------------------------------------------------- |
| `card_1`    | single metric            | `value` (number), `icon` (lucide slug, kebab-case), `label` (string)                                    |
| `card_2`    | comparison                | `primary`, `secondary` (numbers), `primary_label`, `secondary_label` (strings)                          |
| `card_3`    | metric + percent          | `value` (number), `percent` (0–100)                                                                     |
| `card_4`    | progress                  | `current` (subset), `total`, `segments` (JSON array of `{label, value}`)                                |
| `card_5`    | headline + ranked breakdown, 2x width | `value`, `label`, `icon` (headline stat, same shape as `card_1`); `breakdown` (JSON array of `{label, value, variant?}`, rendered as a ranked list with per-item bars) — one total from a single table, sliced by one dimension of that same total |
| `card_6`    | metric grid, 4x width (full row) | `metrics` (JSON array of `{label, value, trend?, icon?}`, 4–6 items)                                    |
| `table_1`   | flat list (narrow table)  | any flat columns, `order by` + `limit 10`; optional `link` (row href — excluded from rendered columns, makes the whole row clickable) |
| `table_2`   | aggregated table (wide)   | grouped/joined query with computed columns, `limit 10`; optional `link` (same as `table_1`)             |
| `list_1`    | alert/feed list (narrow)  | `title` (string); optional `description`, `icon` (lucide slug), `variant` (default/secondary/success/warning/destructive/info), `link` (row href) |
| `list_2`    | alert/feed list (wide)    | same as `list_1` plus optional `field_1`, `field_2` (extra values shown before the chevron)              |
| `list_3`    | activity feed, avatar per row (narrow) | `actor` (string, avatar initials derived from it, bold), `action` (string, plain text), `entity` (string, bold); optional `date` (right-aligned), `link` — one row per event: "`actor` `action` `entity`" |
| `list_4`    | ranked leaderboard, avatar per row (narrow) | `name` (string), `value` (number); optional `label` (subtext), `variant` (bar color, same palette as `card_5`), `link` — order the query by `value desc`; no rank number is rendered, just a relative bar against the top value |

## Starter SQL per type

```sql
-- card_1
select count(*) as value, 'activity' as icon, 'total records' as label
from app.tickets;

-- card_2
select
  count(*) filter (where status = 'open')   as primary,
  count(*) filter (where status = 'closed') as secondary,
  'Open'   as primary_label,
  'Closed' as secondary_label
from app.tickets;

-- card_3
select
  count(*) as value,
  round(100.0 * count(*) filter (where status = 'resolved') / nullif(count(*), 0), 1) as percent
from app.tickets;

-- card_4
select
  count(*) filter (where status = 'open') as current,
  count(*) as total,
  json_build_array(
    json_build_object('label', 'Open', 'value', count(*) filter (where status = 'open')),
    json_build_object('label', 'Resolved', 'value', count(*) filter (where status = 'resolved'))
  ) as segments
from app.tickets;

-- card_5 (2x the width of card_1 — a headline total plus a ranked breakdown
-- of that SAME total, from one table, one query, no joins)
select
  count(*) filter (where status not in ('resolved', 'closed')) as value,
  'Open Tickets' as label,
  'inbox' as icon,
  json_build_array(
    json_build_object('label', 'Low', 'value', count(*) filter (where priority = 'low' and status not in ('resolved', 'closed')), 'variant', 'secondary'),
    json_build_object('label', 'Medium', 'value', count(*) filter (where priority = 'medium' and status not in ('resolved', 'closed')), 'variant', 'info'),
    json_build_object('label', 'High', 'value', count(*) filter (where priority = 'high' and status not in ('resolved', 'closed')), 'variant', 'warning'),
    json_build_object('label', 'Critical', 'value', count(*) filter (where priority = 'critical' and status not in ('resolved', 'closed')), 'variant', 'destructive')
  ) as breakdown
from app.tickets;

-- card_6 (4x the width of card_1, full row — for 4-6 related metrics in one card)
select
  json_build_array(
    json_build_object('label', 'Open', 'value', count(*) filter (where status = 'open')),
    json_build_object('label', 'In Progress', 'value', count(*) filter (where status = 'in_progress'), 'trend', 12.4),
    json_build_object('label', 'Resolved', 'value', count(*) filter (where status = 'resolved')),
    json_build_object('label', 'Avg Response', 'value', '2.4h')
  ) as metrics
from app.tickets;

-- list_3 (activity feed, narrow — one total activity source, ordered newest
-- first; avatar initials are derived client-side from `actor`, no image needed)
select
  tm.name as actor,
  case
    when t.status = 'done' then 'completed'
    when t.status = 'in_review' then 'submitted for review'
    else 'updated'
  end as action,
  t.title as entity,
  to_char(t.updated_at, 'Mon DD, YYYY') as date,
  '/app/resource/tickets/' || t.id || '/detail' as link
from app.tickets t
join app.team_members tm on tm.id = t.assignee_id
order by t.updated_at desc
limit 5;

-- list_4 (leaderboard — ranked by `value` and row order alone, no index
-- column needed; bars are relative to the top row)
select
  tm.name,
  count(*) as value,
  tm.job_title as label,
  '/app/resource/team_members/' || tm.id || '/detail' as link
from app.tickets t
join app.team_members tm on tm.id = t.assignee_id
where t.status = 'done'
group by tm.id, tm.name, tm.job_title
order by value desc
limit 5;

-- table_1 (link is optional — makes each row click-through)
select
  title,
  status,
  created_at::date as date,
  '/app/resource/tickets/' || id || '/detail' as link
from app.tickets
order by created_at desc
limit 10;

-- table_2 (link is optional, same as table_1)
select
  p.name as project,
  count(*) as total,
  count(*) filter (where t.status = 'done') as done,
  '/app/resource/projects/' || p.id || '/detail' as link
from app.tasks t join app.projects p on p.id = t.project_id
group by p.id, p.name
order by total desc
limit 10;

-- list_1
select
  title,
  assignee || ' · ' || reason as description,
  'triangle-alert' as icon,
  'warning' as variant,
  '/app/resource/tickets/' || id || '/detail' as link
from app.tickets
where status = 'blocked'
order by updated_at desc
limit 10;

-- list_2 (adds field_1 / field_2 for extra columns before the chevron)
select
  title,
  assignee as description,
  'circle-alert' as icon,
  'destructive' as variant,
  priority as field_1,
  to_char(due_date, 'MM/DD') as field_2,
  '/app/resource/tickets/' || id || '/detail' as link
from app.tickets
where status not in ('done', 'cancelled')
order by due_date asc nulls last
limit 10;
```

## Full recipe

```sql
create view app.open_tickets_count
with
  (security_invoker = true) as
select
  count(*) as value,
  'ticket' as icon,
  'open tickets' as label
from
  app.tickets
where
  status = 'open';

revoke all on app.open_tickets_count
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
  on app.open_tickets_count to "x-admin",
  "user";

comment on view app.open_tickets_count is '{"type": "dashboard_widget", "name": "Open Tickets", "description": "Tickets currently open", "widget_type": "card_1"}';

select
  supasheet.refresh_metadata ();
```

## Rules

- Name views by what they show: `open_tickets_count`, `revenue_summary`, `recent_tasks`, `top_clients`.
- Always `security_invoker = true` — the widget respects the viewer's RLS.
- `select` is the only grant a widget needs; grant to `anon` only for intentionally public dashboards.
- Widgets are per-schema — they appear on that schema's dashboard.
- Sources: `supabase/demo.sql` (`active_projects_count`, `task_completion`, `revenue_summary`, `project_health`, `recent_tasks`, `top_clients`, `task_alerts`, `recent_invoices`, `task_velocity`, `client_snapshot`, `task_board_overview`, `recent_task_activity`, `top_task_closers`); `supasheet.get_widgets()` in `supabase/migrations/20250707023128_dashboards.sql`.
