-- 0024 immunisation registry (s. 35; feeds s. 72(1) item 8 and the s. 72(6)
-- medical-officer-of-health export). A child not yet in school must be
-- immunised per the local medical officer of health, or hold one of the two
-- standard exemption forms. The Ontario details the schema enforces:
--   * A medical exemption is signed by a physician or nurse practitioner —
--     the practitioner is named, always.
--   * A conscience/religious exemption must be NOTARISED — the notarisation
--     date is required, always.
--   * "Attends school" is only for school-age children (44 months is the
--     kindergarten floor from Schedule 1) — an infant can never be waved
--     through on it.
--   * The registry is an append-only ledger: status changes add a row (the
--     MOH schedule has age milestones, records update over time); the
--     current status is the latest row; history is never rewritten.

create table public.immunisation_record (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  status text not null check (status in
    ('immunised', 'medical_exemption', 'conscience_exemption', 'attends_school')),
  -- what is on file: "record per Toronto Public Health schedule to the
  -- 18-month visit", "Statement of Medical Exemption re MMR", …
  detail text,
  -- medical exemption: the physician / nurse practitioner who signed
  practitioner text,
  -- conscience/religious exemption: when it was notarised
  notarised_on date,
  effective_on date not null default current_date,
  evidence_path text,
  recorded_by uuid not null references public.person (id),
  -- clock_timestamp, not now(): two rows in one transaction must still order
  -- as a ledger, so "latest wins" is never a tie
  created_at timestamptz not null default clock_timestamp()
);

create index immunisation_child_latest on public.immunisation_record (child_id, created_at desc);

create or replace function app.immunisation_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  dob date;
begin
  if tg_op = 'UPDATE' then
    raise exception 'immunisation records are never edited; record the new status';
  end if;

  select ch.date_of_birth into dob from public.child ch
  where ch.id = new.child_id and ch.centre_id = new.centre_id;
  if dob is null then
    raise exception 'child is not enrolled at this centre';
  end if;

  if new.status = 'immunised' and coalesce(trim(new.detail), '') = '' then
    raise exception 'say what record is on file (which schedule, to which visit)';
  end if;
  if new.status = 'medical_exemption' and coalesce(trim(new.practitioner), '') = '' then
    raise exception 'a medical exemption names the physician or nurse practitioner who signed it';
  end if;
  if new.status = 'conscience_exemption' and new.notarised_on is null then
    raise exception 'a conscience or religious exemption must be notarised — record the notarisation date';
  end if;
  if new.status = 'attends_school' and dob + interval '44 months' > new.effective_on then
    raise exception '"attends school" applies to school-age children — this child is under 44 months';
  end if;

  return new;
end;
$$;

create trigger immunisation_rules
  before insert or update on public.immunisation_record
  for each row execute function app.immunisation_rules();

alter table public.immunisation_record enable row level security;

create policy immunisation_select on public.immunisation_record
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = immunisation_record.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
-- Writes via the RPC only.

create trigger immunisation_no_delete before delete on public.immunisation_record
  for each row execute function app.block_mutation();
create trigger immunisation_audit after insert on public.immunisation_record
  for each row execute function app.audit_row();

-- The current status per child: the latest ledger row wins.
create view public.current_immunisation
with (security_invoker = on) as
select distinct on (child_id)
  centre_id, child_id, status, detail, practitioner, notarised_on,
  effective_on, recorded_by, created_at
from public.immunisation_record
order by child_id, created_at desc;

create or replace function public.record_immunisation(
  p_centre uuid,
  p_child uuid,
  p_status text,
  p_detail text,
  p_practitioner text,
  p_notarised_on date,
  p_recorder uuid,
  p_pin text
) returns public.immunisation_record
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.immunisation_record;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  insert into public.immunisation_record (
    centre_id, child_id, status, detail, practitioner, notarised_on, recorded_by
  ) values (
    p_centre, p_child, p_status,
    nullif(trim(coalesce(p_detail, '')), ''),
    nullif(trim(coalesce(p_practitioner, '')), ''),
    p_notarised_on, recorder
  ) returning * into result;
  return result;
end;
$$;
