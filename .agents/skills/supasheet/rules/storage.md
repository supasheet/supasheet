---
name: supasheet/storage
description: >-
  Storage rules: FILE/AVATAR columns backed by the uploads bucket with
  permission-derived paths, and custom buckets with their own RLS.
type: sub-skill
requires:
  - supasheet
---

# Storage

## FILE / AVATAR columns — zero extra storage work

Files uploaded via a `supasheet.FILE` or `supasheet.AVATAR` column go to the `uploads` bucket at `uploads/<schema>/<table>/<column>/<filename>`. Access is derived from the owning table's permissions automatically (`:select` to read, `:insert` to upload, etc.). The complete work for a file column:

```sql
alter table app.tickets
add column attachments supasheet.file;

comment on column app.tickets.attachments is '{"accept": "*", "maxFiles": 10, "maxSize": 10485760}';

select
  supasheet.refresh_metadata ();
```

- `supasheet.FILE` = array of `{name, type, size, url, last_modified}` (multi-file); `supasheet.AVATAR` = single object rendered as a circular avatar.
- Constraints live in the column comment: `accept` (default `"*"`), `maxSize` bytes (default 5242880), `maxFiles` (default 1).
- Exception path: `uploads/auth/<uid>/...` (profile pictures) is owner-based, no table permission required.

## Pre-configured buckets

| Bucket     | Access                                                    |
| ---------- | --------------------------------------------------------- |
| `uploads`  | permission-gated per table/column (above)                 |
| `public`   | read anyone; write any authenticated; update/delete owner |
| `personal` | owner-only everything                                     |

Any bucket a user can SELECT appears in the file browser at `/storage/$bucketId`.

## Custom buckets

Insert the bucket, then write `storage.objects` policies — reuse `supasheet.has_permission()` to stay consistent with the rest of the app:

```sql
insert into storage.buckets (id, name, public)
values ('contracts', 'contracts', false)
on conflict (id) do nothing;

create policy contracts_read on storage.objects for select to authenticated
  using (bucket_id = 'contracts' and supasheet.has_permission ('app.contracts:select'));

create policy contracts_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'contracts' and supasheet.has_permission ('app.contracts:insert'));

create policy contracts_delete on storage.objects for delete to authenticated
  using (bucket_id = 'contracts' and owner_id = (select auth.uid ()::text));
```

Sources: `supabase/migrations/20251005041214_general_storage.sql`, `supabase/migrations/20251005051303_uploads.sql`. File-type details: `references/data-types.md`.
