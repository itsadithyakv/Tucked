-- 0012 staff credential ledger (ss. 53–64 — the free wedge) + retention clocks
-- (s. 72(5), O. Reg. 138/15) + private storage buckets with path-scoped RLS.

-- ── credentials ─────────────────────────────────────────────────────────────
create type public.credential_type as enum (
  'rece_registration', 'first_aid_cpr', 'vsc', 'offence_declaration',
  'health_assessment', 'immunisation', 'training'
);

create table public.credential (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  person_id uuid not null references public.person (id),
  credential_type public.credential_type not null,
  issued_on date,
  expires_on date,
  evidence_path text,
  notes text,
  recorded_by uuid references public.person (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index credential_expiry on public.credential (centre_id, expires_on);

alter table public.credential enable row level security;

-- Staff see their own file; supervisors see and manage the centre's ledger.
create policy credential_select on public.credential
  for select using (
    person_id = app.current_person_id()
    or app.has_role(centre_id, array['supervisor', 'designate', 'licensee_admin']::public.role_id[])
  );
create policy credential_write on public.credential
  for insert with check (app.has_role(centre_id, array['supervisor', 'designate', 'licensee_admin']::public.role_id[]));
create policy credential_update on public.credential
  for update using (app.has_role(centre_id, array['supervisor', 'designate', 'licensee_admin']::public.role_id[]))
  with check (app.has_role(centre_id, array['supervisor', 'designate', 'licensee_admin']::public.role_id[]));

create trigger credential_audit
  after insert or update on public.credential
  for each row execute function app.audit_row();
create trigger credential_no_delete
  before delete on public.credential
  for each row execute function app.block_mutation();

-- VSC 5-year renewal (s. 60): expiry view the exceptions home reads.
create or replace view public.credential_status
with (security_invoker = true)
as
select
  c.*,
  case
    when c.expires_on is null then 'no_expiry'
    when c.expires_on < current_date then 'expired'
    when c.expires_on < current_date + 60 then 'expiring_soon'
    else 'current'
  end as expiry_state
from public.credential c;

-- ── retention clocks ────────────────────────────────────────────────────────
create table public.retention_clock (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  subject_table text not null,
  subject_id text not null,
  kind text not null check (kind in ('childrens_record', 'attendance', 'financial')),
  starts_at date not null,
  purge_after date not null, -- anonymise only AFTER this date, never before
  anonymised_at timestamptz,
  created_at timestamptz not null default now(),
  unique (subject_table, subject_id, kind)
);

alter table public.retention_clock enable row level security;
create policy retention_select on public.retention_clock
  for select using (app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[]));

-- Discharge starts the 3-year clocks (children's record + attendance).
create or replace function app.child_discharge_clocks()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.discharge_date is not null and old.discharge_date is null then
    insert into public.retention_clock (centre_id, subject_table, subject_id, kind, starts_at, purge_after)
    values
      (new.centre_id, 'child', new.id::text, 'childrens_record', new.discharge_date, new.discharge_date + interval '3 years'),
      (new.centre_id, 'attendance_event', new.id::text, 'attendance', new.discharge_date, new.discharge_date + interval '3 years')
    on conflict (subject_table, subject_id, kind) do nothing;
  end if;
  return new;
end;
$$;

create trigger child_discharge_clocks
  after update on public.child
  for each row execute function app.child_discharge_clocks();

-- Scheduled sweep: nothing is EVER touched before purge_after. Rows past due
-- are only counted for now — the anonymisation routine itself ships well
-- before any real clock can mature (3 years), behind its own audit trail.
create or replace function app.run_retention_sweep()
returns integer
language sql security definer
set search_path = public
as $$
  select count(*)::integer from public.retention_clock
  where purge_after <= current_date and anonymised_at is null
$$;

select cron.schedule('retention-sweep', '30 2 * * *', $$select app.run_retention_sweep()$$);

-- ── storage buckets ─────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('photos', 'photos', false), ('evidence', 'evidence', false)
on conflict (id) do nothing;

-- photos/{centre_id}/{child_id}/{uuid}.jpg
create policy photos_staff_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'photos'
    and (split_part(name, '/', 1))::uuid in (select app.care_centre_ids())
  );

create policy photos_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'photos'
    and (
      (split_part(name, '/', 1))::uuid in (select app.care_centre_ids())
      or exists (
        select 1 from public.child_household ch
        where ch.child_id = (split_part(name, '/', 2))::uuid
          and ch.household_id in (select app.my_viewable_household_ids())
      )
    )
  );

-- evidence/{centre_id}/... — staff only, both directions
create policy evidence_staff_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'evidence'
    and (split_part(name, '/', 1))::uuid in (select app.care_centre_ids())
  );

create policy evidence_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'evidence'
    and (split_part(name, '/', 1))::uuid in (select app.care_centre_ids())
  );
