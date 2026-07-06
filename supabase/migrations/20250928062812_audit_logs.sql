begin;

alter type supasheet.app_permission
add value 'supasheet.audit_logs:select';

alter type supasheet.app_permission
add value 'supasheet.audit_logs:select_all';

commit;

create table if not exists supasheet.audit_logs (
  id UUID default extensions.uuid_generate_v4 () primary key,
  created_at TIMESTAMPTZ default NOW() not null,
  operation TEXT not null,
  schema_name TEXT not null,
  table_name TEXT not null,
  record_id TEXT,
  created_by UUID references supasheet.users (id) on delete set null,
  role supasheet.app_role,
  user_type TEXT not null check (user_type in ('system', 'real_user')) default 'real_user',
  metadata JSONB default '{}'::JSONB,
  old_data JSONB,
  new_data JSONB,
  changed_fields text[],
  is_error BOOLEAN default false,
  error_message TEXT,
  error_code TEXT
);

comment on table supasheet.audit_logs is '{
  "label": "Audit Logs",
  "icon": "ScrollTextIcon"
}';

create index idx_audit_logs_created_at on supasheet.audit_logs (created_at desc);

create index idx_audit_logs_created_by on supasheet.audit_logs (created_by);

create index idx_audit_logs_role on supasheet.audit_logs (role);

create index idx_audit_logs_operation on supasheet.audit_logs (operation);

create index idx_audit_logs_schema_table on supasheet.audit_logs (schema_name, table_name);

create index idx_audit_logs_record_id on supasheet.audit_logs (record_id);

create index idx_audit_logs_user_type on supasheet.audit_logs (user_type);

create index idx_audit_logs_is_error on supasheet.audit_logs (is_error)
where
  is_error = true;

create index idx_audit_logs_metadata on supasheet.audit_logs using GIN (metadata);

create or replace function supasheet.create_audit_log (
  p_operation TEXT,
  p_schema_name TEXT,
  p_table_name TEXT,
  p_record_id TEXT default null,
  p_old_data JSONB default null,
  p_new_data JSONB default null,
  p_metadata JSONB default '{}'::JSONB
) RETURNS UUID as $$
DECLARE
    v_audit_id       UUID;
    v_user_id        UUID;
    v_user_role      supasheet.app_role;
    v_changed_fields TEXT[];
    v_stored_old     JSONB;
    v_stored_new     JSONB;
BEGIN
    v_user_id := auth.uid();

    SELECT ur.role INTO v_user_role
    FROM supasheet.user_roles ur
    WHERE ur.user_id = v_user_id
    LIMIT 1;

    IF p_operation = 'UPDATE' AND p_old_data IS NOT NULL AND p_new_data IS NOT NULL THEN
        -- Identify changed fields; FULL OUTER JOIN handles keys added or removed between old and new
        SELECT ARRAY_AGG(DISTINCT key) INTO v_changed_fields
        FROM (
            SELECT COALESCE(o.key, n.key) AS key
            FROM jsonb_each(p_old_data) o
            FULL OUTER JOIN jsonb_each(p_new_data) n USING (key)
            WHERE o.value IS DISTINCT FROM n.value
        ) diff;

        -- Store only the delta (changed keys), not full row snapshots
        SELECT jsonb_object_agg(key, value) INTO v_stored_old
        FROM jsonb_each(p_old_data)
        WHERE key = ANY(v_changed_fields);

        SELECT jsonb_object_agg(key, value) INTO v_stored_new
        FROM jsonb_each(p_new_data)
        WHERE key = ANY(v_changed_fields);
    ELSE
        v_stored_old := p_old_data;
        v_stored_new := p_new_data;
    END IF;

    INSERT INTO supasheet.audit_logs (
        operation,
        schema_name,
        table_name,
        record_id,
        created_by,
        role,
        user_type,
        old_data,
        new_data,
        changed_fields,
        metadata
    ) VALUES (
        p_operation,
        p_schema_name,
        p_table_name,
        p_record_id,
        v_user_id,
        v_user_role,
        CASE WHEN v_user_id IS NULL THEN 'system' ELSE 'real_user' END,
        v_stored_old,
        v_stored_new,
        v_changed_fields,
        p_metadata
    ) RETURNING id INTO v_audit_id;

    RETURN v_audit_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
set
  search_path = '';

create or replace function supasheet.audit_trigger_function () RETURNS TRIGGER as $$
DECLARE
    v_pk_column  TEXT := COALESCE(NULLIF(TG_ARGV[0], ''), 'id');
    v_old_data   JSONB;
    v_new_data   JSONB;
    v_operation  TEXT;
    v_record_id  TEXT;
BEGIN
    v_operation := TG_OP;

    IF TG_OP = 'DELETE' THEN
        v_old_data  := to_jsonb(OLD);
        v_new_data  := NULL;
        v_record_id := v_old_data ->> v_pk_column;
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_data  := to_jsonb(OLD);
        v_new_data  := to_jsonb(NEW);
        v_record_id := v_new_data ->> v_pk_column;
    ELSIF TG_OP = 'INSERT' THEN
        v_old_data  := NULL;
        v_new_data  := to_jsonb(NEW);
        v_record_id := v_new_data ->> v_pk_column;
    END IF;

    
    PERFORM supasheet.create_audit_log(
        v_operation,
        TG_TABLE_SCHEMA,
        TG_TABLE_NAME,
        v_record_id,
        v_old_data,
        v_new_data,
        jsonb_build_object(
            'trigger_name', TG_NAME,
            'trigger_when', TG_WHEN,
            'trigger_level', TG_LEVEL
        )
    );

    
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
set
  search_path = '';

grant
select
  on supasheet.audit_logs to authenticated;

alter table supasheet.audit_logs ENABLE row LEVEL SECURITY;

create policy "Users can view their own audit logs" on supasheet.audit_logs for
select
  to authenticated using (
    created_by = (
      select
        auth.uid ()
    )
    and supasheet.has_permission ('supasheet.audit_logs:select')
  );

create policy "Users can view all audit logs" on supasheet.audit_logs for
select
  to authenticated using (
    supasheet.has_permission ('supasheet.audit_logs:select_all')
  );

insert into
  supasheet.role_permissions (role, permission)
values
  ('x-admin', 'supasheet.audit_logs:select');

insert into
  supasheet.role_permissions (role, permission)
values
  ('x-admin', 'supasheet.audit_logs:select_all');

insert into
  supasheet.role_permissions (role, permission)
values
  ('user', 'supasheet.audit_logs:select');

-- ─────────────────────────────────────────────
-- get_audit_logs
-- Returns audit log rows for a given schema.table
-- (and optionally a single record_id), gated on the
-- caller holding the schema.table:audit permission.
-- security invoker — RLS on audit_logs still applies.
-- ─────────────────────────────────────────────
create or replace function supasheet.get_audit_logs (
  p_schema text,
  p_table text,
  p_record_id text default null
) returns table (
  id uuid,
  created_at timestamptz,
  operation text,
  schema_name text,
  table_name text,
  record_id text,
  created_by uuid,
  role supasheet.app_role,
  user_type text,
  metadata jsonb,
  old_data jsonb,
  new_data jsonb,
  changed_fields text[],
  is_error boolean,
  error_message text,
  error_code text,
  created_by_name varchar(255),
  created_by_email varchar(320),
  created_by_picture_url varchar(1000)
) language sql security definer
set
  search_path = '' as $$
    select
        al.id,
        al.created_at,
        al.operation,
        al.schema_name,
        al.table_name,
        al.record_id,
        al.created_by,
        al.role,
        al.user_type,
        al.metadata,
        al.old_data,
        al.new_data,
        al.changed_fields,
        al.is_error,
        al.error_message,
        al.error_code,
        u.name          as created_by_name,
        u.email         as created_by_email,
        u.picture_url   as created_by_picture_url
    from supasheet.audit_logs al
    inner join supasheet.role_permissions rp
        on rp.permission::text = p_schema || '.' || p_table || ':audit'
    inner join supasheet.user_roles ur
        on ur.role = rp.role
    left join supasheet.users u
        on u.id = al.created_by
    where ur.user_id = (select auth.uid())
      and al.schema_name = p_schema
      and al.table_name  = p_table
      and (p_record_id is null or al.record_id = p_record_id)
    order by al.created_at desc;
$$;

grant
execute on function supasheet.get_audit_logs (text, text, text) to authenticated;
