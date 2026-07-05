---
name: supasheet/dashboards
description: >-
  Dashboard widget views: the six widget_type contracts (card_1..card_4,
  table_1, table_2) with required output columns and starter SQL.
type: sub-skill
requires:
  - supasheet
---

# Dashboard Widgets

A widget = a view whose comment is `{"type": "dashboard_widget", "name": ..., "description": ..., "widget_type": ...}`. Discovered by `supasheet.get_widgets()`; shown on `/$schema/dashboard` to users holding `:select`.

## Widget contracts (exact required columns)

| widget_type | Renders | Required columns |
|---|---|---|
| `card_1` | single metric | `value` (number), `icon` (lucide slug, kebab-case), `label` (string) |
| `card_2` | comparison | `primary`, `secondary` (numbers), `primary_label`, `secondary_label` (strings) |
| `card_3` | metric + percent | `value` (number), `percent` (0–100) |
| `card_4` | progress | `current` (subset), `total`, `segments` (JSON array of `{label, value}`) |
| `table_1` | flat list | any flat columns, `order by` + `limit 10` |
| `table_2` | aggregated table | grouped/joined query with computed columns, `limit 10` |

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

-- table_1
select title, status, created_at::date as date
from app.tickets
order by created_at desc
limit 10;

-- table_2
select p.name as project, count(*) as total, count(*) filter (where t.status = 'done') as done
from app.tasks t join app.projects p on p.id = t.project_id
group by p.name
order by total desc
limit 10;
```

## Full recipe

```sql
-- committed enum block:
alter type supasheet.app_permission add value if not exists 'app.open_tickets_count:select';

create view app.open_tickets_count
with (security_invoker = true) as
select count(*) as value, 'ticket' as icon, 'open tickets' as label
from app.tickets where status = 'open';

revoke all on app.open_tickets_count from public, anon, authenticated, service_role;
grant select on app.open_tickets_count to authenticated;

comment on view app.open_tickets_count is '{"type": "dashboard_widget", "name": "Open Tickets", "description": "Tickets currently open", "widget_type": "card_1"}';

insert into supasheet.role_permissions (role, permission) values
  ('x-admin', 'app.open_tickets_count:select'),
  ('user', 'app.open_tickets_count:select')
on conflict (role, permission) do nothing;

select supasheet.refresh_metadata ();
```

## Rules

- Name views by what they show: `open_tickets_count`, `revenue_summary`, `recent_tasks`, `top_clients`.
- Always `security_invoker = true` — the widget respects the viewer's RLS.
- `:select` is the only permission a widget needs; grant to `anon` only for intentionally public dashboards.
- Widgets are per-schema — they appear on that schema's dashboard.
- Sources: `supabase/demo.sql` (`active_projects_count`, `task_completion`, `revenue_summary`, `project_health`, `recent_tasks`, `top_clients`); `supasheet.get_widgets()` in `supabase/migrations/20250707023128_dashboards.sql`.
