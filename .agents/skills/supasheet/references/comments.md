# Per-Record Comments

Threaded comments on any record, stored centrally in `supasheet.comments` (`schema_name`, `table_name`, `record_id`, `content`, `created_by`). No per-table schema objects are needed — enabling comments is purely a permission grant.

## Enable comments on a table

```sql
-- 1. Permission value (committed enum block)
alter type supasheet.app_permission add value if not exists 'app.tickets:comment';

-- 2. Seed roles that may read AND post comments
insert into supasheet.role_permissions (role, permission) values
  ('user', 'app.tickets:comment'),
  ('x-admin', 'app.tickets:comment')
on conflict (role, permission) do nothing;
```

That's it. A Comments link appears automatically at `/$schema/resource/$resource/$id/comment` for permission holders. Nothing goes in the table comment JSON.

## How it's enforced

- INSERT policy on `supasheet.comments` requires `created_by = auth.uid()` **and** the caller holds `<schema_name>.<table_name>:comment`.
- Reading goes through `supasheet.get_comments(p_schema, p_table, p_record_id)` (security definer) which enforces the same permission and joins author name/email/picture.
- UPDATE/DELETE are limited to the comment's author.

## Optional: notify on new comments

Pair with the notifications system via a trigger on the central table:

```sql
create or replace function app.trg_ticket_comments_notify () returns trigger as $$
begin
  if new.schema_name = 'app' and new.table_name = 'tickets' then
    perform supasheet.create_notification(
      'ticket_commented',
      'New comment on ticket',
      left(new.content, 140),
      supasheet.get_users_with_permission('app.tickets:update'),
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
- `supabase/demo.sql` — `:comment` permission values + role seeding per table
