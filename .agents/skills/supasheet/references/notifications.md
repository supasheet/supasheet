# Notifications

In-app notifications are created by calling `supasheet.create_notification()` from database triggers. It writes one row to `supasheet.notifications` and fans out one `supasheet.user_notifications` row per recipient (which tracks read/archived state). Never insert into those tables directly.

## The helper (service_role-only)

```sql
supasheet.create_notification(
  p_type     text,        -- machine tag, e.g. 'task_assigned'
  p_title    text,
  p_body     text,
  p_user_ids uuid[],      -- recipients; returns null if empty
  p_metadata jsonb  default '{}',
  p_link     text   default null   -- in-app path, e.g. '/app/resource/tickets/<id>/detail'
) returns uuid
```

Execution is granted only to `service_role`, so it **must** be called from a `security definer` trigger function with `set search_path = ''`.

### Recipient resolvers (also security definer, service_role-only)

```sql
supasheet.get_users_with_role('admin')                      -- returns uuid[]
supasheet.get_users_with_permission('app.tickets:update')   -- returns uuid[]
```

## Canonical trigger pattern

```sql
create or replace function app.trg_tickets_notify () returns trigger as $$
declare
  v_recipients uuid[];
  v_type text;
  v_title text;
  v_body text;
begin
  -- explicit recipients + de-dupe nulls
  v_recipients := array_remove(array[new.user_id, new.assignee_id], null);

  if tg_op = 'INSERT' then
    v_type := 'ticket_created';
    v_title := 'New ticket: ' || new.title;
    v_body := 'A new ticket was created.';
  elsif new.status is distinct from old.status then
    v_type := 'ticket_status_changed';
    v_title := 'Ticket status changed: ' || new.title;
    v_body := 'Status is now ' || new.status || '.';
  elsif new.assignee_id is distinct from old.assignee_id then
    v_type := 'ticket_assigned';
    v_title := 'Ticket assigned: ' || new.title;
    v_body := 'You were assigned a ticket.';
  else
    return new;   -- nothing notification-worthy changed
  end if;

  perform supasheet.create_notification(
    v_type,
    v_title,
    v_body,
    v_recipients,
    jsonb_build_object('ticket_id', new.id),
    '/app/resource/tickets/' || new.id::text || '/detail'
  );

  return new;
end;
$$ language plpgsql security definer
set search_path = '';

drop trigger if exists tickets_notify on app.tickets;

create trigger tickets_notify
after insert or update of status, assignee_id on app.tickets
for each row execute function app.trg_tickets_notify ();
```

## Best practices

- Fire `after insert or update of <specific columns>` — not on every update.
- Guard with `is distinct from` so no-op updates don't notify.
- Use `array_remove(..., null)` for nullable recipient columns; broadcast with `get_users_with_permission('<schema>.<table>:select')` when a whole group should know.
- `p_link` is an in-app route: `/<schema>/resource/<table>/<id>/detail`.
- Notifications run synchronously inside the trigger's transaction — keep them cheap.
- **No permissions needed for end users**: RLS on `user_notifications` already shows each user their own deliveries; `supasheet.unread_notifications_count()` / `mark_all_notifications_read()` are granted to `authenticated`. Only the admin browse pages need `supasheet.notifications:select` / `supasheet.user_notifications:select` (seeded for `x-admin` by the base migration).

## Authoritative sources

- `supabase/migrations/20251006051303_notifications.sql` — tables, `create_notification`, resolvers, sample `trg_user_roles_notify`
- `supabase/demo.sql` — `demo.trg_projects_notify`, `demo.trg_tasks_notify`, `demo.trg_invoices_notify`
- `supabase/examples/20251005100000_desk.sql` — `desk.trg_*_notify` set
