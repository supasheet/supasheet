---
name: supasheet/materialized-views
description: >-
  Creating materialized views as resources or heavy reports: no
  security_invoker, unique index for concurrent refresh, catalog vs data
  refresh distinction.
type: sub-skill
requires:
  - supasheet
---

# Materialized Views

Materialized views are first-class read-only resources: same comment JSON shape as tables/views, discovered via `supasheet.get_materialized_views()`, `:select` permission only. Use them for expensive aggregations (heavy reports, precomputed rollups).

## Creation pattern

Materialized views do **not** support `security_invoker` — they store data computed with the creator's rights, and access is controlled purely by grants + the `:select` permission:

```sql
create materialized view app.revenue_rollup as
select
  date_trunc('month', issue_date)::date as month,
  sum(total) as revenue,
  count(*) as invoices
from app.invoices
where status = 'paid'
group by 1;

-- unique index REQUIRED for concurrent refresh
create unique index idx_app_revenue_rollup_month on app.revenue_rollup (month);

revoke all on app.revenue_rollup from public, anon, authenticated, service_role;
grant select on app.revenue_rollup to authenticated;

alter type supasheet.app_permission add value if not exists 'app.revenue_rollup:select';
-- (committed enum block)

comment on materialized view app.revenue_rollup is '{"type": "report", "name": "Revenue Rollup", "description": "Monthly paid revenue"}';

insert into supasheet.role_permissions (role, permission)
values ('x-admin', 'app.revenue_rollup:select')
on conflict (role, permission) do nothing;

select supasheet.refresh_metadata ();
```

The comment can alternatively use the resource shape (`{"icon": ..., "display": "block", "views": [...]}`) to surface it as a browsable read-only resource, or `chart` / `dashboard_widget` types.

## Two different refreshes — don't confuse them

| Command                                                        | Refreshes                                                       |
| -------------------------------------------------------------- | --------------------------------------------------------------- |
| `select supasheet.refresh_metadata();`                         | the **catalog** (which resources exist, their comments/columns) |
| `refresh materialized view [concurrently] app.revenue_rollup;` | the **data** inside your matview                                |

Creating a matview needs both (catalog once, data on your schedule). `concurrently` avoids locking readers but requires the unique index above.

Schedule data refreshes with `pg_cron` if available, or trigger them from application events.

## Redefining

`create or replace` does not exist for materialized views — drop and recreate (grants, comment, and indexes must be reapplied):

```sql
drop materialized view if exists app.revenue_rollup cascade;

-- then recreate everything above
```
