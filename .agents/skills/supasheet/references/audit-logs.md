# Audit Logs

Row-level change history via the generic `supasheet.audit_trigger_function()`. Every audited change lands in `supasheet.audit_logs` (operation, actor, role, old/new data, `changed_fields` delta).

## Enable auditing on a table (two steps)

### 1. Attach the triggers

INSERT/UPDATE fire `AFTER`; DELETE must fire `BEFORE` (so the row still exists when captured):

```sql
create trigger audit_tickets_insert after insert on app.tickets for each row execute function supasheet.audit_trigger_function ();

create trigger audit_tickets_update after
update on app.tickets for each row execute function supasheet.audit_trigger_function ();

create trigger audit_tickets_delete before delete on app.tickets for each row execute function supasheet.audit_trigger_function ();
```

If the primary key column is not `id`, pass its name as a trigger argument (read via `TG_ARGV[0]`):

```sql
... execute function supasheet.audit_trigger_function ('ticket_no');
```

### 2. Nothing to grant per table

The per-record Audit tab (`/$schema/resource/$resource/$id/audit`) has no
per-table permission to seed — `supasheet.get_audit_logs()` gates access with
a single central check: `pg_has_role(current_user, 'x-admin', 'member')`.
Attaching the triggers above is the entire setup; the tab shows up for
x-admin automatically on any audited table.

If a specific table needs a _different_ role to see its audit trail (not
x-admin), that's a deliberate one-off — edit the `pg_has_role` check inside
`supasheet.get_audit_logs()` in `20250928062812_audit_logs.sql`, since it's
shared across every table rather than seeded per resource.

## Related pieces

- The `supasheet.audit_logs` table itself: rows are visible to their own
  `created_by`, plus x-admin sees all (`pg_has_role(current_user, 'x-admin',
'member')`) — this gates the **global** Core → Audit Logs page.
- Read helper: `supasheet.get_audit_logs(p_schema, p_table, p_record_id)` —
  security definer, gates on the same x-admin check, joins actor name/email/picture.
- Manual/system events can be written with `supasheet.create_audit_log(p_operation, p_schema_name, p_table_name, p_record_id, p_old_data, p_new_data, p_metadata)`.
- `changed_fields` stores only the delta between old and new — no need to trim payloads yourself.

## Conventions

- Trigger names: `audit_<table>_insert` / `_update` / `_delete` (demo prefixes the schema too: `audit_demo_tasks_insert`).
- Audit high-value tables (business records); skip noisy ones (junction rows are optional).
- The per-record Audit tab is x-admin-only by default across the whole app —
  it's a single shared check, not a per-table setting.

## Authoritative sources

- `supabase/migrations/20250928062812_audit_logs.sql` — table, `create_audit_log`, `audit_trigger_function`, `get_audit_logs`
- `supabase/demo.sql` — `audit_demo_*` trigger set
- `supabase/examples/20251005100000_desk.sql` — `audit_tasks_*`, `audit_projects_*`
