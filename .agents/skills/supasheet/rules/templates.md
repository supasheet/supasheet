---
name: supasheet/templates
description: >-
  Template views for bulk-inserting rows into a table: type:template comment,
  column-intersection contract of supasheet.apply_template, static vs dynamic
  templates.
type: sub-skill
requires:
  - supasheet
---

# Templates (Bulk Insert Views)

A template = a view whose comment is `{"type": "template", ...}`. Its rows are a ready-to-insert payload for a target table: the UI lists templates at `/$schema/template`, previews the rows, and "Apply" calls `supasheet.apply_template()` which bulk-inserts them.

## How apply works (the contract)

```sql
select supasheet.apply_template ('<schema>', '<template_view>', '<target_table>');
-- returns the number of rows inserted
```

- Inserts `insert into <schema>.<target> (<cols>) select <cols> from <schema>.<template_view>`.
- `<cols>` = the **intersection of column names** between the template view and the target table. Non-matching template columns are ignored; target columns absent from the template fall back to their defaults (ids, sequences, `created_at`, audit fields).
- Raises an error if zero columns match.
- Runs as `security invoker`: the caller needs `:select` on the template view AND insert grant + RLS `:insert` permission on the target table. Column matching goes through `supasheet.get_columns()`, which is also permission-gated.
- Re-applying inserts again — there is no dedupe. Design the template so repeats are safe (period-scoped rows, unique constraints on the target, or accept duplicates).

## Full recipe (dynamic template — computed from live data)

From `supabase/examples/20260606000000_hostel.sql`: seed a month of pending payments for all active allocations.

```sql
begin;
alter type supasheet.app_permission add value if not exists 'app.monthly_payment_template:select';
commit;

create or replace view app.monthly_payment_template
with (security_invoker = true) as
select
  a.id as allocation_id,
  a.resident_id,
  date_trunc('month', current_date)::date as period_month,
  a.monthly_rent as amount,
  0::numeric(10, 2) as late_fee,
  a.monthly_rent as total,
  (date_trunc('month', current_date) + interval '10 days')::date as due_date,
  'pending'::app.payment_status as status
from app.allocations a
where a.status = 'active';

revoke all on app.monthly_payment_template from public, anon, authenticated, service_role;
grant select on app.monthly_payment_template to authenticated;

comment on view app.monthly_payment_template is '{"type": "template", "name": "Monthly Payment Template", "description": "Pending payment entries for all active allocations. Apply to app.payments to seed a new billing month.", "target_table": "payments"}';

insert into supasheet.role_permissions (role, permission) values
  ('x-admin', 'app.monthly_payment_template:select')
on conflict (role, permission) do nothing;

select supasheet.refresh_metadata ();
```

## Static template (fixed seed set)

Fixed rows via `values` — e.g. a standard checklist to stamp onto projects:

```sql
create or replace view app.onboarding_tasks_template
with (security_invoker = true) as
select *
from (
  values
    ('Kickoff call'::varchar(500),        'todo'::app.task_status, 'high'::app.priority_level),
    ('Collect brand assets',              'todo',                  'medium'),
    ('Set up staging environment',        'todo',                  'medium'),
    ('Schedule weekly check-in',          'todo',                  'low')
) as t (title, status, priority);
```

## Comment keys

```json
{
  "type": "template",
  "name": "Monthly Payment Template",
  "description": "What applying this does",
  "caption": "optional short label",
  "target_table": "payments"
}
```

`target_table` (table name in the same schema, no schema prefix) pre-selects the target in the Apply dialog; the user can still pick another compatible table.

## Rules

- Column names AND types must line up with the target — cast literals explicitly (`0::numeric(10,2)`, `'pending'::app.payment_status`), since only name-matching columns are copied and type mismatches fail at insert time.
- Omit auto-generated/optional target columns (id, sequence-backed numbers, timestamps, audit fields) — defaults take over.
- Always `security_invoker = true`; `:select` permission + role seed like any feature view.
- Suffix names with `_template`.
- Sources: `supabase/migrations/20260506000001_templates.sql` (`get_templates`, `apply_template`), `supabase/examples/20260606000000_hostel.sql` (`monthly_payment_template`).
