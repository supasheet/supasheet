-- ─────────────────────────────────────────────
-- Permissions
-- x-admin overrides the per-user RLS to view all notifications.
-- All other access is bounded by ownership (user_id = auth.uid()).
-- ─────────────────────────────────────────────
-- ─────────────────────────────────────────────
-- Tables
-- ─────────────────────────────────────────────
-- One row per notification event. Shared across all recipients.
create table if not exists supasheet.notifications (
  id uuid primary key default extensions.uuid_generate_v4 (),
  type text not null,
  title text not null,
  body text,
  link text,
  metadata jsonb default '{}'::jsonb not null,
  created_by uuid references supasheet.users (id) on delete set null,
  created_at timestamptz default now() not null
);

comment on table supasheet.notifications is '{
  "display": "none"
}';

create index idx_notifications_type on supasheet.notifications (type);

create index idx_notifications_created_at on supasheet.notifications (created_at desc);

create index idx_notifications_metadata on supasheet.notifications using gin (metadata);

-- Fan-out: one row per (notification, recipient) with per-user read state.
create table if not exists supasheet.user_notifications (
  id uuid primary key default extensions.uuid_generate_v4 (),
  notification_id uuid not null references supasheet.notifications (id) on delete cascade,
  user_id uuid not null references supasheet.users (id) on delete cascade,
  read_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz default now() not null,
  unique (user_id, notification_id)
);

comment on table supasheet.user_notifications is '{
  "display": "none"
}';

create index idx_user_notifications_user_id on supasheet.user_notifications (user_id);

create index idx_user_notifications_unread on supasheet.user_notifications (user_id, created_at desc)
where
  read_at is null
  and archived_at is null;

create index idx_user_notifications_created_at on supasheet.user_notifications (created_at desc);

-- ─────────────────────────────────────────────
-- Grants & RLS
-- ─────────────────────────────────────────────
revoke all on supasheet.notifications
from
  authenticated,
  service_role;

revoke all on supasheet.user_notifications
from
  authenticated,
  service_role;

grant
select
  on supasheet.notifications to authenticated,
  service_role;

grant
select
,
update,
delete on supasheet.user_notifications to authenticated,
service_role;

alter table supasheet.notifications enable row level security;

alter table supasheet.user_notifications enable row level security;

-- A user may read a notification only if they have a delivery row for it
create policy notifications_select on supasheet.notifications for
select
  to authenticated using (
    exists (
      select
        1
      from
        supasheet.user_notifications un
      where
        un.notification_id = supasheet.notifications.id
        and un.user_id = (
          select
            auth.uid ()
        )
    )
    or pg_has_role(current_user, 'x-admin', 'member')
  );

create policy user_notifications_select on supasheet.user_notifications for
select
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
    or pg_has_role(current_user, 'x-admin', 'member')
  );

-- Recipients can mark read/archived on their own deliveries
create policy user_notifications_update on supasheet.user_notifications
for update
  to authenticated using (
    user_id = (
      select
        auth.uid ()
    )
  )
with
  check (
    user_id = (
      select
        auth.uid ()
    )
  );

create policy user_notifications_delete on supasheet.user_notifications for delete to authenticated using (
  user_id = (
    select
      auth.uid ()
  )
);

-- ─────────────────────────────────────────────
-- Fan-out helper: insert 1 notification, N delivery rows
-- p_link is an optional in-app path the UI can navigate to
-- (e.g. /desk/resource/tasks/detail/<id>).
-- ─────────────────────────────────────────────
create or replace function supasheet.create_notification (
  p_type text,
  p_title text,
  p_body text,
  p_user_ids uuid[],
  p_metadata jsonb default '{}'::jsonb,
  p_link text default null
) returns uuid language plpgsql security definer
set
  search_path = '' as $$
declare
    v_id uuid;
begin
    if p_user_ids is null or array_length(p_user_ids, 1) is null then
        return null;
    end if;

    insert into supasheet.notifications (type, title, body, link, metadata, created_by)
    values (p_type, p_title, p_body, p_link, p_metadata, auth.uid())
    returning id into v_id;

    insert into supasheet.user_notifications (notification_id, user_id)
    select v_id, unnest(p_user_ids)
    on conflict (user_id, notification_id) do nothing;

    return v_id;
end;
$$;

-- create_notification is invoked only from SECURITY DEFINER triggers (e.g.
-- trg_user_roles_notify and the per-schema *_notify triggers), which run as the
-- function owner and therefore retain the right to call it. It must never be
-- reachable by client roles: any authenticated user granted execute could call
-- it directly via PostgREST and inject arbitrary notifications (spoofed
-- titles/bodies/links) to any user. Revoke every client-reachable role,
-- including the default PUBLIC grant; only server-only service_role keeps it.
revoke
execute on function supasheet.create_notification (text, text, text, uuid[], jsonb, text)
from
  public,
  anon,
  authenticated;

grant
execute on function supasheet.create_notification (text, text, text, uuid[], jsonb, text) to service_role;

-- ─────────────────────────────────────────────
-- Resolver helpers
-- Mirror your RLS rules: each resolver returns the
-- set of users who should see a notification about
-- a given record.
-- ─────────────────────────────────────────────
-- All users currently holding a given role.
create or replace function supasheet.get_users_with_role (p_role text) returns uuid[] language sql stable security definer
set
  search_path = '' as $$
    select coalesce(array_agg(id), '{}'::uuid[])
    from auth.users
    where raw_app_meta_data ->> 'role' = p_role
$$;

-- Resolver used only inside SECURITY DEFINER notification triggers, which run
-- as the owner and keep the right to call it. Exposing it to client roles lets
-- any authenticated user enumerate the members of any role (e.g. all x-admin
-- user ids) via PostgREST. Revoke every client-reachable role, including the
-- default PUBLIC grant; only server-only service_role keeps it.
revoke
execute on function supasheet.get_users_with_role (text)
from
  public,
  anon,
  authenticated;

grant
execute on function supasheet.get_users_with_role (text) to service_role;

-- All users whose assigned role currently holds the given table privilege.
create or replace function supasheet.get_users_with_table_privilege (
  p_schema text,
  p_table text,
  p_action text default 'select'
) returns uuid[] language sql stable security definer
set
  search_path = '' as $$
    select coalesce(array_agg(id), '{}'::uuid[])
    from auth.users
    where raw_app_meta_data ->> 'role' is not null
      and has_table_privilege(
        raw_app_meta_data ->> 'role',
        format('%I.%I', p_schema, p_table),
        p_action
      )
$$;

-- Resolver used only inside SECURITY DEFINER notification triggers, which run
-- as the owner and keep the right to call it. Exposing it to client roles lets
-- any authenticated user enumerate every holder of a table privilege via
-- PostgREST. Revoke every client-reachable role, including the default PUBLIC
-- grant; only server-only service_role keeps it.
revoke
execute on function supasheet.get_users_with_table_privilege (text, text, text)
from
  public,
  anon,
  authenticated;

grant
execute on function supasheet.get_users_with_table_privilege (text, text, text) to service_role;

-- ─────────────────────────────────────────────
-- Convenience helpers used by the UI
-- ─────────────────────────────────────────────
-- Mark every unread delivery for the current user as read.
create or replace function supasheet.mark_all_notifications_read () returns integer language plpgsql security definer
set
  search_path = '' as $$
declare
    v_count integer;
begin
    update supasheet.user_notifications
    set    read_at = now()
    where  user_id = auth.uid()
      and  read_at is null
      and  archived_at is null;

    get diagnostics v_count = row_count;
    return v_count;
end;
$$;

grant
execute on function supasheet.mark_all_notifications_read () to authenticated;

-- Count of unread, unarchived deliveries for the current user.
create or replace function supasheet.unread_notifications_count () returns integer language sql stable security definer
set
  search_path = '' as $$
    select count(*)::int
    from   supasheet.user_notifications
    where  user_id = auth.uid()
      and  read_at is null
      and  archived_at is null
$$;

grant
execute on function supasheet.unread_notifications_count () to authenticated;

-- ─────────────────────────────────────────────
-- Sample trigger: notify a user when their role changes
-- Demonstrates the resolver + create_notification pattern.
-- ─────────────────────────────────────────────
create or replace function supasheet.trg_user_role_changed_notify () returns trigger language plpgsql security definer
set
  search_path = '' as $$
declare
    v_role text := new.raw_app_meta_data ->> 'role';
begin
    if v_role is not null then
        perform supasheet.create_notification(
            'role_granted',
            'Role assigned',
            'You have been granted the "' || v_role || '" role.',
            array[new.id],
            jsonb_build_object('role', v_role, 'user_id', new.id)
        );
    end if;
    return new;
end;
$$;

create trigger user_role_changed_notify
after update of raw_app_meta_data on auth.users for each row when (
  old.raw_app_meta_data ->> 'role' is distinct from new.raw_app_meta_data ->> 'role'
)
execute function supasheet.trg_user_role_changed_notify ();
