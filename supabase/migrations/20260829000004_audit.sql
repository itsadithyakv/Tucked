-- 0004 audit: append-only audit_event on every regulated write (references
-- only — never photos or free-text health details). Phase 0 audits role
-- changes; every regulated table added in Phase 1 attaches the same trigger.
-- The block-mutation trigger holds for EVERY role including service_role:
-- required records must never be deletable by anyone (never-do list §9.14).

create table public.audit_event (
  id bigint generated always as identity primary key,
  centre_id uuid,
  table_name text not null,
  row_id text not null,
  action text not null check (action in ('insert', 'update', 'delete')),
  actor_person_id uuid,
  auth_user_id uuid,
  at timestamptz not null default now(),
  summary jsonb
);

create index audit_event_centre_at on public.audit_event (centre_id, at desc);

alter table public.audit_event enable row level security;

-- Supervisors and licensee admins may read their centre's trail. Nobody
-- (client-side) may write directly; rows arrive only via triggers.
create policy audit_select on public.audit_event
  for select using (
    centre_id is not null
    and app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[])
  );

create or replace function app.block_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'audit_event is append-only';
end;
$$;

create trigger audit_event_append_only
  before update or delete on public.audit_event
  for each row execute function app.block_mutation();

-- Generic audit trigger. SECURITY DEFINER so it can insert regardless of the
-- caller's RLS scope.
create or replace function app.audit_row()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  rec record;
  centre uuid;
begin
  rec := coalesce(new, old);
  begin
    centre := rec.centre_id;
  exception when undefined_column then
    centre := null;
  end;
  insert into public.audit_event (centre_id, table_name, row_id, action, actor_person_id, auth_user_id, summary)
  values (
    centre,
    tg_table_name,
    rec.id::text,
    lower(tg_op),
    app.current_person_id(),
    auth.uid(),
    null
  );
  return rec;
end;
$$;

create trigger person_role_audit
  after insert or update or delete on public.person_role
  for each row execute function app.audit_row();
