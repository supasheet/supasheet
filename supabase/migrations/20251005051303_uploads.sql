set
  client_min_messages = WARNING;

-- Bucket
insert into
  storage.buckets (id, name, public)
values
  ('uploads', 'uploads', true)
on conflict do nothing;

-- Uploads bucket policies
drop policy IF exists enable_read_authenticated_uploads_bucket on storage.buckets;

create policy enable_read_authenticated_uploads_bucket on storage.buckets as PERMISSIVE for
select
  to authenticated using (name = 'uploads');

drop policy IF exists enable_read_authorized_uploads_objects on storage.objects;

create policy enable_read_authorized_uploads_objects on storage.objects as PERMISSIVE for
select
  to authenticated using (
    bucket_id = 'uploads'
    and (storage.foldername (name)) [1] != 'auth'
    and has_table_privilege(
      current_user,
      format('%I.%I', path_tokens[1], path_tokens[2]),
      'select'
    )
  );

drop policy IF exists enable_insert_authorized_uploads_objects on storage.objects;

create policy enable_insert_authorized_uploads_objects on storage.objects as PERMISSIVE for INSERT to authenticated
with
  check (
    bucket_id = 'uploads'
    and (storage.foldername (name)) [1] != 'auth'
    and has_table_privilege(
      current_user,
      format('%I.%I', path_tokens[1], path_tokens[2]),
      'insert'
    )
  );

drop policy IF exists enable_update_authorized_uploads_objects on storage.objects;

create policy enable_update_authorized_uploads_objects on storage.objects as PERMISSIVE
for update
  to authenticated using (
    bucket_id = 'uploads'
    and (storage.foldername (name)) [1] != 'auth'
    and has_table_privilege(
      current_user,
      format('%I.%I', path_tokens[1], path_tokens[2]),
      'update'
    )
  );

drop policy IF exists enable_delete_authorized_uploads_objects on storage.objects;

create policy enable_delete_authorized_uploads_objects on storage.objects as PERMISSIVE for DELETE to authenticated using (
  bucket_id = 'uploads'
  and (storage.foldername (name)) [1] != 'auth'
  and has_table_privilege(
    current_user,
    format('%I.%I', path_tokens[1], path_tokens[2]),
    'delete'
  )
);

-- Auth folder policy in uploads bucket (account avatar images)
drop policy IF exists enable_all_auth_uploads_objects on storage.objects;

create policy enable_all_auth_uploads_objects on storage.objects as PERMISSIVE for all to authenticated using (
  bucket_id = 'uploads'
  and (storage.foldername (name)) [1] = 'auth'
  and (storage.foldername (name)) [2] = (
    select
      auth.uid ()::text
  )
)
with
  check (
    bucket_id = 'uploads'
    and (storage.foldername (name)) [1] = 'auth'
    and (storage.foldername (name)) [2] = (
      select
        auth.uid ()::text
    )
  );
