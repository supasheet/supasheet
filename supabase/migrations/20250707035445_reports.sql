/*
 * -------------------------------------------------------
 * Section: Report
 * This migration creates the schema for reports.
 * -------------------------------------------------------
 */
drop function if exists supasheet.get_reports (text);

drop function if exists supasheet.get_reports (text, text);

create or replace function supasheet.get_reports (
  p_schema text default null,
  p_view_name text default null,
  p_caller text default current_user
) returns table (
  id bigint,
  schema text,
  name text,
  is_updatable boolean,
  comment text
) language sql security definer
set
  search_path = '' as $$
  select
    v.*
  from supasheet.views v
  where v.schema = p_schema
    and (p_view_name is null or v.name = p_view_name)
    and v.comment::jsonb ->> 'type' = 'report'
    and has_table_privilege(
      p_caller,
      v.id::oid,
      'select'
    );
$$;

revoke all on function supasheet.get_reports (text, text, text)
from
  anon,
  authenticated,
  service_role;

grant
execute on function supasheet.get_reports (text, text, text) to anon,
authenticated;

-- Report templates bucket
insert into
  storage.buckets (id, name, public)
values
  ('report-templates', 'report-templates', false)
on conflict do nothing;

drop policy IF exists enable_read_authenticated_report_templates_bucket on storage.buckets;

create policy enable_read_authenticated_report_templates_bucket on storage.buckets as PERMISSIVE for
select
  to authenticated using (name = 'report-templates');

drop policy IF exists enable_read_authorized_report_templates_objects on storage.objects;

create policy enable_read_authorized_report_templates_objects on storage.objects as PERMISSIVE for
select
  to authenticated using (
    bucket_id = 'report-templates'
    and path_tokens[2] like '%.hbs'
    and has_table_privilege(
      current_user,
      format('%I.%I', path_tokens[1], regexp_replace (path_tokens[2], '\.hbs$', '')),
      'select'
    )
  );

drop policy IF exists enable_write_admin_report_templates_objects on storage.objects;

create policy enable_write_admin_report_templates_objects on storage.objects as PERMISSIVE for all to authenticated using (
  bucket_id = 'report-templates'
  and path_tokens[2] like '%.hbs'
  and pg_has_role (current_user, 'x-admin', 'member')
)
with
  check (
    bucket_id = 'report-templates'
    and path_tokens[2] like '%.hbs'
    and pg_has_role (current_user, 'x-admin', 'member')
  );
