# Per-Record Comments

Threaded comments on any record, stored centrally in `supasheet.comments` (`schema_name`, `table_name`, `record_id`, `content`, `created_by`). No per-table schema objects are needed, and no separate grant to seed — comment access on a resource follows that resource's `select` grant.

## Enable comments on a table

Nothing to do. Any role that holds `select` on `app.tickets` can already read
and post comments about `app.tickets` records — there's no separate
comment-specific grant to add.

A Comments link appears automatically at `/$schema/resource/$resource/$id/comment` once a caller's native role has `select` on the target table. Nothing goes in the table comment JSON.

## How it's enforced

- INSERT policy on `supasheet.comments` requires `created_by = auth.uid()` **and** `has_table_privilege(current_user, format('%I.%I', schema_name, table_name), 'select')`.
- Reading goes through `supasheet.get_comments(p_schema, p_table, p_record_id)` (security definer) which enforces the same `has_table_privilege` check and joins author name/email/picture.
- UPDATE/DELETE are limited to the comment's author.

If a resource needs comment access *narrower* than its select grant (e.g. a
role can view records but shouldn't be able to comment), that's a deliberate
departure from the standard mechanism and needs its own dedicated check —
most modules don't need this.

## Optional: notify on new comments

Pair with the notifications system via a trigger on the central table. Use
`supasheet.get_users_with_table_privilege()` to resolve recipients from
native-role grants:

```sql
create or replace function app.trg_ticket_comments_notify () returns trigger as $$
begin
  if new.schema_name = 'app' and new.table_name = 'tickets' then
    perform supasheet.create_notification(
      'ticket_commented',
      'New comment on ticket',
      left(new.content, 140),
      supasheet.get_users_with_table_privilege('app', 'tickets', 'update'),
      jsonb_build_object('record_id', new.record_id),
      '/app/resource/tickets/' || new.record_id || '/comment'
    );
  end if;
  return new;
end;
$$ language plpgsql security definer
set search_path = '';

create trigger ticket_comments_notify
after insert on supasheet.comments
for each row execute function app.trg_ticket_comments_notify ();
```

## Authoritative sources

- `supabase/migrations/20260514000001_comments.sql` — table, RLS, `get_comments`
- `supabase/migrations/20251006051303_notifications.sql` — `get_users_with_table_privilege`
- `supabase/demo.sql` — grant sets per table (comment access follows `select`)
