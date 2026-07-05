---
name: supasheet/triggers
description: >-
  Trigger conventions: audit triggers (timing rules, naming), notification
  triggers (security definer), business triggers (rollups, updated_at), and
  trigger function structure.
type: sub-skill
requires:
  - supasheet
---

# Triggers

Four standard trigger families in Supasheet, in order of frequency:

## 1. Audit triggers

One per event, calling the shared `supasheet.audit_trigger_function()`. **DELETE must be BEFORE; INSERT/UPDATE are AFTER**:

```sql
create trigger audit_app_tickets_insert after insert on app.tickets for each row execute function supasheet.audit_trigger_function ();

create trigger audit_app_tickets_update after
update on app.tickets for each row execute function supasheet.audit_trigger_function ();

create trigger audit_app_tickets_delete before delete on app.tickets for each row execute function supasheet.audit_trigger_function ();
```

- Naming: `audit_<schema>_<table>_<event>` (or `audit_<table>_<event>`).
- Non-`id` primary key: pass the column name — `execute function supasheet.audit_trigger_function ('ticket_no')`.
- Pair with the `<schema>.<table>:audit` permission so the Audit tab appears — see `references/audit-logs.md`.

## 2. Notification triggers

Trigger functions that call `supasheet.create_notification()` **must** be `security definer set search_path = ''` (the helper is service_role-only). Fire on specific columns and de-dupe with `is distinct from`:

```sql
create or replace function app.trg_tickets_notify () returns trigger as $$
begin
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    perform supasheet.create_notification(
      'ticket_status_changed',
      'Ticket status: ' || new.title,
      'Status is now ' || new.status || '.',
      array_remove(array[new.user_id, new.assignee_id], null),
      jsonb_build_object('ticket_id', new.id),
      '/app/resource/tickets/' || new.id::text || '/detail'
    );
  end if;
  return new;
end;
$$ language plpgsql security definer
set search_path = '';

create trigger tickets_notify
after insert or update of status, assignee_id on app.tickets
for each row execute function app.trg_tickets_notify ();
```

Details and recipient resolvers: `references/notifications.md`.

## 3. Business triggers (rollups, derived state)

Keep parent totals in sync with children (`security definer set search_path = ''`, fire on all three events, resolve the parent id with `coalesce(new.x, old.x)`):

```sql
create or replace function app.trg_order_items_recalc () returns trigger as $$
declare
  v_order_id uuid := coalesce(new.order_id, old.order_id);
begin
  update app.orders o
  set total = (select coalesce(sum(line_total), 0) from app.order_items where order_id = v_order_id),
      updated_at = current_timestamp
  where o.id = v_order_id;
  return coalesce(new, old);
end;
$$ language plpgsql security definer
set search_path = '';

create trigger order_items_recalc
after insert or update or delete on app.order_items
for each row execute function app.trg_order_items_recalc ();
```

## 4. Maintenance triggers

Built-ins ready to attach:

```sql
create trigger tickets_updated_at before
update on app.tickets for each row execute function supasheet.set_updated_at ();

create trigger tickets_updated_by before
update on app.tickets for each row execute function supasheet.set_updated_by ();
```

## General rules

- Anatomy: `create trigger <name> {before|after} <event> [or <event>...] [of <columns>] on <table> for each {row|statement} [when (<cond>)] execute function <fn>();`
- Redefining: `drop trigger if exists <name> on <table>;` then `create trigger` (or `create or replace trigger` on Postgres 14+).
- Trigger functions that touch other tables or supasheet helpers: `security definer set search_path = ''` and fully-qualify every object.
- Return `new` for before-insert/update, `coalesce(new, old)` for mixed-event functions.
- Notifications/audit run synchronously in the transaction — keep them cheap.
