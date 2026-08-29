-- 0008 accident reports (s. 36(4)): child, completer, what/where/when, injury,
-- severity, first aid — and EVIDENCE the parent received a copy (in-app
-- acknowledgement with timestamp). Hard head hits are recorded even without
-- symptoms and carry a mandatory concussion-watch note. Every report
-- auto-cross-references into the daily written record ("see child's file").

create table public.accident_report (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  occurred_at timestamptz not null,
  occurred_date date not null, -- derived: centre-local day
  location text not null,
  description text not null,
  injury text not null,
  severity text not null check (severity in ('none_apparent', 'minor', 'moderate', 'serious')),
  first_aid text not null,
  head_injury boolean not null default false,
  concussion_watch_note text,
  completed_by uuid not null references public.person (id),
  parent_ack_person_id uuid references public.person (id),
  parent_ack_at timestamptz,
  device_id text,
  offline_recorded_at timestamptz,
  offline_synced_at timestamptz,
  created_at timestamptz not null default now(),
  constraint accident_head_injury_needs_watch_note
    check (not head_injury or concussion_watch_note is not null),
  constraint accident_ack_fields_together
    check ((parent_ack_at is null) = (parent_ack_person_id is null))
);

create index accident_report_centre_day on public.accident_report (centre_id, occurred_date);

alter table public.accident_report enable row level security;

-- Care staff see the centre's reports; household members see their own child's
-- (they must receive a copy — that is the point).
create policy accident_select on public.accident_report
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = accident_report.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
-- Writes via RPCs only.

create or replace function app.accident_report_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  tz text;
begin
  if tg_op = 'INSERT' then
    select c.timezone into tz from public.centre c where c.id = new.centre_id;
    new.occurred_date := (new.occurred_at at time zone tz)::date;
    if not exists (select 1 from public.child ch where ch.id = new.child_id and ch.centre_id = new.centre_id) then
      raise exception 'child is not enrolled at this centre';
    end if;
    return new;
  end if;

  -- The only permitted change to a report is the parent acknowledgement.
  if old.parent_ack_at is not null then
    raise exception 'an acknowledged accident report never changes';
  end if;
  if row(new.centre_id, new.child_id, new.occurred_at, new.occurred_date, new.location,
         new.description, new.injury, new.severity, new.first_aid, new.head_injury,
         new.concussion_watch_note, new.completed_by)
     is distinct from
     row(old.centre_id, old.child_id, old.occurred_at, old.occurred_date, old.location,
         old.description, old.injury, old.severity, old.first_aid, old.head_injury,
         old.concussion_watch_note, old.completed_by) then
    raise exception 'accident reports are never edited; only the parent acknowledgement may be added';
  end if;
  return new;
end;
$$;

create trigger accident_report_rules
  before insert or update on public.accident_report
  for each row execute function app.accident_report_rules();

create trigger accident_report_no_delete
  before delete on public.accident_report
  for each row execute function app.block_mutation();

create trigger accident_report_audit
  after insert or update on public.accident_report
  for each row execute function app.audit_row();

-- s. 37: every accident is summarised in the daily written record.
create or replace function app.accident_cross_reference()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  perform app.dwr_append_ref(
    new.centre_id,
    new.occurred_date,
    jsonb_build_object('type', 'accident', 'accident_report_id', new.id, 'note', 'Accident — see child''s file')
  );
  return new;
end;
$$;

create trigger accident_cross_reference
  after insert on public.accident_report
  for each row execute function app.accident_cross_reference();

-- ── RPCs ────────────────────────────────────────────────────────────────────
create or replace function public.record_accident_report(
  p_centre uuid,
  p_child uuid,
  p_occurred_at timestamptz,
  p_location text,
  p_description text,
  p_injury text,
  p_severity text,
  p_first_aid text,
  p_head_injury boolean,
  p_concussion_watch_note text,
  p_recorder uuid,
  p_pin text,
  p_offline_recorded_at timestamptz default null,
  p_device text default null
) returns public.accident_report
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.accident_report;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  insert into public.accident_report (
    centre_id, child_id, occurred_at, occurred_date, location, description,
    injury, severity, first_aid, head_injury, concussion_watch_note,
    completed_by, device_id, offline_recorded_at, offline_synced_at
  ) values (
    p_centre, p_child, p_occurred_at, '1970-01-01', p_location, p_description,
    p_injury, p_severity, p_first_aid, p_head_injury, p_concussion_watch_note,
    recorder, p_device, p_offline_recorded_at,
    case when p_offline_recorded_at is null then null else now() end
  ) returning * into result;
  return result;
end;
$$;

-- The parent's acknowledgement IS the s. 36(4) delivery evidence: only a
-- viewing household member of this child may acknowledge, as themselves.
create or replace function public.acknowledge_accident_report(p_report uuid)
returns public.accident_report
language plpgsql security definer
set search_path = public
as $$
declare
  result public.accident_report;
  me uuid;
begin
  select * into result from public.accident_report where id = p_report;
  if result.id is null then raise exception 'report not found'; end if;
  me := app.current_person_id();
  if not exists (
    select 1 from public.child_household ch
    join public.household_member hm on hm.household_id = ch.household_id
    where ch.child_id = result.child_id
      and hm.person_id = me
      and hm.revoked_at is null
      and hm.can_view
  ) then
    raise exception 'only a household member of this child may acknowledge' using errcode = '42501';
  end if;
  if result.parent_ack_at is not null then
    return result; -- already acknowledged; evidence stands
  end if;
  update public.accident_report
  set parent_ack_person_id = me, parent_ack_at = now()
  where id = p_report
  returning * into result;
  return result;
end;
$$;
