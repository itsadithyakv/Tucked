-- 0005 attendance & safe arrival/dismissal (s. 72(3), s. 50) + staff shifts +
-- staff PINs + pickup authorisations/restrictions (needed here: the restricted-
-- pickup block runs at SQL level on sign-out).
--
-- Write model: regulated writes go through SECURITY DEFINER RPCs that verify
-- the recording staff member's PIN — "the PIN is who logged it". Tables have
-- NO client insert/update policies; triggers re-enforce every rule as defence
-- in depth. Regulated rows are never updated or deleted: corrections are new
-- rows referencing the original.

-- ── centre: safe-arrival cutoff ─────────────────────────────────────────────
alter table public.centre
  add column safe_arrival_cutoff time not null default '09:30';

-- ── staff PINs ──────────────────────────────────────────────────────────────
create table public.staff_pin (
  person_id uuid not null references public.person (id),
  centre_id uuid not null references public.centre (id),
  pin_hash text not null,
  updated_at timestamptz not null default now(),
  primary key (person_id, centre_id)
);
alter table public.staff_pin enable row level security;
-- No policies at all: the hash never reaches a client. RPCs verify it.

create or replace function app.verify_pin(p_person uuid, p_centre uuid, p_pin text)
returns boolean
language sql stable security definer
set search_path = public, extensions
as $$
  select exists (
    select 1 from public.staff_pin sp
    where sp.person_id = p_person
      and sp.centre_id = p_centre
      and sp.pin_hash = extensions.crypt(p_pin, sp.pin_hash)
  )
$$;

-- Caller must hold a care role in the centre; the PIN names the recorder.
create or replace function app.resolve_recorder(p_centre uuid, p_recorder uuid, p_pin text)
returns uuid
language plpgsql stable security definer
set search_path = public
as $$
begin
  if not (p_centre in (select app.care_centre_ids())) then
    raise exception 'not authorised for this centre' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = p_recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate', 'rece', 'staff')
  ) then
    raise exception 'recorder has no care role at this centre' using errcode = '42501';
  end if;
  if not app.verify_pin(p_recorder, p_centre, p_pin) then
    raise exception 'invalid staff PIN' using errcode = '28000';
  end if;
  return p_recorder;
end;
$$;

create or replace function public.set_staff_pin(p_person uuid, p_centre uuid, p_pin text)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if p_pin !~ '^\d{4,6}$' then
    raise exception 'PIN must be 4-6 digits';
  end if;
  -- A supervisor/licensee admin sets any staff PIN; staff may set their own.
  if not (
    app.has_role(p_centre, array['supervisor', 'licensee_admin']::public.role_id[])
    or p_person = app.current_person_id()
  ) then
    raise exception 'not authorised to set this PIN' using errcode = '42501';
  end if;
  insert into public.staff_pin (person_id, centre_id, pin_hash)
  values (p_person, p_centre, extensions.crypt(p_pin, extensions.gen_salt('bf')))
  on conflict (person_id, centre_id)
  do update set pin_hash = excluded.pin_hash, updated_at = now();
end;
$$;

-- ── pickup authorisations & restrictions (s. 50) ────────────────────────────
create table public.pickup_authorisation (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  person_id uuid references public.person (id),
  named_person text, -- authorised pickup without an account
  photo_path text,
  pickup_pin text,
  active_from date,
  active_until date,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint pickup_person_or_name check (person_id is not null or named_person is not null)
);

create table public.pickup_restriction (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  restricted_person_id uuid references public.person (id),
  restricted_person_name text not null,
  court_order_reference text,
  document_path text,
  staff_note text not null, -- the explanation staff see; NEVER shown to the restricted person
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

alter table public.pickup_authorisation enable row level security;
alter table public.pickup_restriction enable row level security;

create policy pickup_auth_select on public.pickup_authorisation
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = pickup_authorisation.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
create policy pickup_auth_write on public.pickup_authorisation
  for insert with check (app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[]));
create policy pickup_auth_update on public.pickup_authorisation
  for update using (app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[]))
  with check (app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[]));

-- Restrictions: care staff only. Family adults never see them — including, by
-- construction, the restricted person (s. 50; build prompt §4).
create policy pickup_restriction_select on public.pickup_restriction
  for select using (centre_id in (select app.care_centre_ids()));
create policy pickup_restriction_write on public.pickup_restriction
  for insert with check (app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[]));
create policy pickup_restriction_update on public.pickup_restriction
  for update using (app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[]))
  with check (app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[]));

-- ── attendance (s. 72(3)) ───────────────────────────────────────────────────
create type public.attendance_event_type as enum ('arrive', 'depart', 'absent', 'room_transfer');

create table public.attendance_event (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  room_id uuid references public.room (id),
  event_type public.attendance_event_type not null,
  actual_time timestamptz not null, -- captured at the event, never typed later
  attendance_date date not null,    -- derived: centre-local day (day-bounded, decision 2026-08-29)
  recorded_by uuid not null references public.person (id),
  device_id text,
  offline_recorded_at timestamptz,
  offline_synced_at timestamptz,
  correction_of uuid references public.attendance_event (id),
  correction_reason text,
  released_to_person_id uuid references public.person (id),
  released_to_name text,
  created_at timestamptz not null default now(),
  constraint attendance_room_required
    check (event_type = 'absent' or room_id is not null),
  constraint attendance_correction_needs_reason
    check ((correction_of is null) = (correction_reason is null)),
  constraint attendance_release_only_on_depart
    check (event_type = 'depart' or (released_to_person_id is null and released_to_name is null))
);

create index attendance_event_day on public.attendance_event (centre_id, attendance_date);
create index attendance_event_child_day on public.attendance_event (child_id, attendance_date);

create table public.staff_shift (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  person_id uuid not null references public.person (id),
  room_id uuid references public.room (id),
  shift_date date not null,
  in_at timestamptz not null,
  out_at timestamptz,
  counted_in_ratio boolean not null default false, -- derived by trigger, never client-set
  recorded_by uuid references public.person (id),
  created_at timestamptz not null default now(),
  constraint shift_out_after_in check (out_at is null or out_at > in_at)
);

create table public.safe_arrival_check (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  check_date date not null,
  prompted_at timestamptz not null default now(),
  contacted_via text,        -- phone, message…
  outcome text,              -- reached parent: child sick / late / no answer, escalated…
  recorded_by uuid references public.person (id),
  resolved_at timestamptz,
  unique (child_id, check_date)
);

alter table public.attendance_event enable row level security;
alter table public.staff_shift enable row level security;
alter table public.safe_arrival_check enable row level security;

-- Reads: care staff see their centre; a viewing household member sees their own
-- child's attendance (part of the parent's s. 72 record access).
create policy attendance_select on public.attendance_event
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = attendance_event.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
create policy staff_shift_select on public.staff_shift
  for select using (centre_id in (select app.care_centre_ids()));
create policy safe_arrival_select on public.safe_arrival_check
  for select using (centre_id in (select app.care_centre_ids()));
-- No insert/update/delete policies: writes go through the RPCs below.

-- ── rule triggers (defence in depth) ────────────────────────────────────────
create or replace function app.attendance_event_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  tz text;
begin
  select c.timezone into tz from public.centre c where c.id = new.centre_id;
  new.attendance_date := (new.actual_time at time zone tz)::date;

  if tg_op = 'UPDATE' then
    raise exception 'attendance events are never updated; record a correction';
  end if;

  -- child belongs to this centre
  if not exists (select 1 from public.child ch where ch.id = new.child_id and ch.centre_id = new.centre_id) then
    raise exception 'child is not enrolled at this centre';
  end if;

  -- depart requires a same-day arrive (s. 72(3))
  if new.event_type = 'depart' and not exists (
    select 1 from public.attendance_event ae
    where ae.child_id = new.child_id
      and ae.attendance_date = new.attendance_date
      and ae.event_type = 'arrive'
  ) then
    raise exception 'depart requires a same-day arrive';
  end if;

  -- corrections reference the same child
  if new.correction_of is not null and not exists (
    select 1 from public.attendance_event ae
    where ae.id = new.correction_of and ae.child_id = new.child_id
  ) then
    raise exception 'correction must reference an event for the same child';
  end if;

  -- restricted person hard block (s. 50) — at SQL level, not just the app
  if new.event_type = 'depart' and new.released_to_person_id is not null and exists (
    select 1 from public.pickup_restriction pr
    where pr.child_id = new.child_id
      and pr.restricted_person_id = new.released_to_person_id
      and pr.revoked_at is null
  ) then
    raise exception 'release blocked: this person is restricted for this child';
  end if;

  return new;
end;
$$;

create trigger attendance_event_rules
  before insert or update on public.attendance_event
  for each row execute function app.attendance_event_rules();

create trigger attendance_event_no_delete
  before delete on public.attendance_event
  for each row execute function app.block_mutation();

create or replace function app.staff_shift_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  -- counted_in_ratio is derived, never trusted from the caller: volunteers,
  -- students and resource consultants are NEVER counted (ss. 8; §9.14).
  new.counted_in_ratio := exists (
    select 1 from public.person_role pr
    where pr.person_id = new.person_id
      and pr.centre_id = new.centre_id
      and pr.active
      and pr.role in ('supervisor', 'designate', 'rece', 'staff')
  );
  return new;
end;
$$;

create trigger staff_shift_rules
  before insert or update on public.staff_shift
  for each row execute function app.staff_shift_rules();

create trigger attendance_event_audit
  after insert on public.attendance_event
  for each row execute function app.audit_row();
create trigger staff_shift_audit
  after insert or update on public.staff_shift
  for each row execute function app.audit_row();
create trigger pickup_restriction_audit
  after insert or update on public.pickup_restriction
  for each row execute function app.audit_row();

-- ── write RPCs ──────────────────────────────────────────────────────────────
create or replace function public.record_attendance(
  p_centre uuid,
  p_child uuid,
  p_event_type public.attendance_event_type,
  p_room uuid,
  p_actual_time timestamptz,
  p_recorder uuid,
  p_pin text,
  p_released_to_person uuid default null,
  p_released_to_name text default null,
  p_offline_recorded_at timestamptz default null,
  p_device text default null,
  p_correction_of uuid default null,
  p_correction_reason text default null
) returns public.attendance_event
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.attendance_event;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  insert into public.attendance_event (
    centre_id, child_id, room_id, event_type, actual_time, attendance_date,
    recorded_by, device_id, offline_recorded_at, offline_synced_at,
    correction_of, correction_reason, released_to_person_id, released_to_name
  ) values (
    p_centre, p_child, p_room, p_event_type, p_actual_time, '1970-01-01',
    recorder, p_device, p_offline_recorded_at,
    case when p_offline_recorded_at is null then null else now() end,
    p_correction_of, p_correction_reason, p_released_to_person, p_released_to_name
  ) returning * into result;

  -- room moves keep one continuous history and update the child's current room
  if p_event_type in ('arrive', 'room_transfer') then
    update public.child set current_room_id = p_room where id = p_child;
  end if;
  return result;
end;
$$;

create or replace function public.record_staff_shift(
  p_centre uuid,
  p_person uuid,
  p_room uuid,
  p_in_at timestamptz,
  p_recorder uuid,
  p_pin text
) returns public.staff_shift
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.staff_shift;
  tz text;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  select c.timezone into tz from public.centre c where c.id = p_centre;
  insert into public.staff_shift (centre_id, person_id, room_id, shift_date, in_at, recorded_by)
  values (p_centre, p_person, p_room, (p_in_at at time zone tz)::date, p_in_at, recorder)
  returning * into result;
  return result;
end;
$$;

create or replace function public.close_staff_shift(
  p_shift uuid,
  p_out_at timestamptz,
  p_recorder uuid,
  p_pin text
) returns public.staff_shift
language plpgsql security definer
set search_path = public
as $$
declare
  result public.staff_shift;
begin
  select * into result from public.staff_shift where id = p_shift;
  if result.id is null then
    raise exception 'shift not found';
  end if;
  perform app.resolve_recorder(result.centre_id, p_recorder, p_pin);
  update public.staff_shift set out_at = p_out_at where id = p_shift
  returning * into result;
  return result;
end;
$$;

create or replace function public.record_safe_arrival_outcome(
  p_centre uuid,
  p_child uuid,
  p_date date,
  p_contacted_via text,
  p_outcome text,
  p_recorder uuid,
  p_pin text
) returns public.safe_arrival_check
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.safe_arrival_check;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  insert into public.safe_arrival_check (centre_id, child_id, check_date, contacted_via, outcome, recorded_by, resolved_at)
  values (p_centre, p_child, p_date, p_contacted_via, p_outcome, recorder, now())
  on conflict (child_id, check_date)
  do update set contacted_via = excluded.contacted_via,
                outcome = excluded.outcome,
                recorded_by = excluded.recorded_by,
                resolved_at = now()
  returning * into result;
  return result;
end;
$$;
