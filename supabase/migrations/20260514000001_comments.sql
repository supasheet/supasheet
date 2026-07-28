create table if not exists supasheet.comments (
  id uuid default extensions.uuid_generate_v4 () primary key,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  deleted_at timestamptz,
  schema_name text not null,
  table_name text not null,
  record_id text not null,
  content text not null,
  created_by uuid references supasheet.users (id) on delete set null
);

create index idx_comments_record on supasheet.comments (schema_name, table_name, record_id);

create index idx_comments_created_by on supasheet.comments (created_by);

create index idx_comments_created_at on supasheet.comments (created_at);

create index idx_comments_deleted_at on supasheet.comments (deleted_at);

alter table supasheet.comments enable row level security;

create policy "Users can insert comments if they have select on the resource" on supasheet.comments for insert to authenticated
with
  check (
    created_by = (
      select
        auth.uid ()
    )
    and has_table_privilege(
      current_user,
      format('%I.%I', schema_name, table_name),
      'select'
    )
  );

create policy "Users can select comments if they have select on the resource" on supasheet.comments for
select
  to authenticated using (
    has_table_privilege(
      current_user,
      format('%I.%I', schema_name, table_name),
      'select'
    )
    and (
      deleted_at is null
      or created_by = (
        select
          auth.uid ()
      )
      or pg_has_role(current_user, 'x-admin', 'member')
    )
  );

create policy "Users can update their own comments" on supasheet.comments
for update
  to authenticated using (
    created_by = (
      select
        auth.uid ()
    )
    and deleted_at is null
  )
with
  check (
    created_by = (
      select
        auth.uid ()
    )
    and deleted_at is null
  );

create policy "Users can delete their own comments" on supasheet.comments for delete to authenticated using (
  created_by = (
    select
      auth.uid ()
  )
);

create or replace function supasheet.trg_soft_delete_comment () returns trigger language plpgsql security definer
set
  search_path = '' as $$
begin
    update supasheet.comments
    set    deleted_at = now()
    where  id = old.id
      and  deleted_at is null;

    return null;
end;
$$;

create trigger aa_soft_delete_comments before delete on supasheet.comments for each row
execute function supasheet.trg_soft_delete_comment ();

drop function if exists supasheet.get_comments (text, text, text);

create or replace function supasheet.get_comments (
  p_schema text,
  p_table text,
  p_record_id text,
  p_caller text default current_user
) returns table (
  id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  deleted_at timestamptz,
  schema_name text,
  table_name text,
  record_id text,
  content text,
  created_by uuid,
  created_by_name varchar(255),
  created_by_email varchar(320),
  created_by_picture_url varchar(1000)
) language sql security definer
set
  search_path = '' as $$
  select
    c.id,
    c.created_at,
    c.updated_at,
    c.deleted_at,
    c.schema_name,
    c.table_name,
    c.record_id,
    case when c.deleted_at is null then c.content else null end as content,
    c.created_by,
    u.name           as created_by_name,
    u.email          as created_by_email,
    u.picture_url    as created_by_picture_url
  from supasheet.comments c
  left join supasheet.users u
    on u.id = c.created_by
  where has_table_privilege(p_caller, format('%I.%I', p_schema, p_table), 'select')
    and c.schema_name = p_schema
    and c.table_name  = p_table
    and c.record_id   = p_record_id
  order by c.created_at asc;
$$;

grant
execute on function supasheet.get_comments (text, text, text, text) to authenticated;

grant
select
,
  insert,
update,
delete on supasheet.comments to authenticated;
