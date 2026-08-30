-- 0029 outdoor play (s. 47). The rules this schema holds:
--
--   * Two hours outdoors for a child in care six hours or more, weather
--     permitting; thirty minutes for a shorter day. Those numbers are DATA,
--     keyed by jurisdiction, so another province is a row and nothing here
--     changes. The age floor is a column for the same reason.
--   * Minutes are MEASURED, NOT TYPED. The room device records when the group
--     went out and when it came in; the total is arithmetic on two clock
--     times. Nobody types "120" at 5 p.m., which is the same discipline
--     attendance already uses (s. 72(3)) and the reason the number means
--     anything to an inspector.
--   * "Weather permitting" is the licensee's evidence, so a short day needs a
--     recorded reason, and that reason is cross-referenced into the daily
--     written record (s. 37) like any other exception.
--   * A child kept indoors needs a WRITTEN INSTRUCTION from a physician or a
--     parent — the same rule medication authorisations and individualised
--     plans use. Staff cannot excuse a child on their own.
--   * The regulation is about each CHILD, not each room. A child who arrives
--     at one o'clock did not get the morning block, and outdoor_by_child says
--     so: it intersects the room's outdoor periods with that child's own
--     attendance. A room-level number alone would quietly overstate it.
--
-- NOTE FOR REGULATORY REVIEW: the 18-month age floor below follows the
-- summary in references/tucked-ontario-requirements.md. Confirm it against
-- the s. 47 text before a real inspection; it is one row to change.

-- ── the rule pack ───────────────────────────────────────────────────────────
create table public.outdoor_requirement (
  jurisdiction_code text not null references public.jurisdiction (code),
  key text not null,
  min_minutes integer not null check (min_minutes >= 0),
  -- applies to a child in care at least this long on the day
  care_hours_min numeric not null,
  -- and at least this old
  age_months_min integer not null default 0,
  regulation text not null,
  note text not null,
  primary key (jurisdiction_code, key)
);

insert into public.outdoor_requirement
  (jurisdiction_code, key, min_minutes, care_hours_min, age_months_min, regulation, note) values
  ('CA-ON', 'full_day', 120, 6, 18, 'O. Reg. 137/15 s. 47',
   'Two hours of outdoor play each day for a child in care six hours or more, weather permitting.'),
  ('CA-ON', 'short_day', 30, 0, 18, 'O. Reg. 137/15 s. 47',
   'Thirty minutes of outdoor play for a shorter day, such as before- and after-school care.');

alter table public.outdoor_requirement enable row level security;
create policy outdoor_requirement_select on public.outdoor_requirement for select using (true);

-- What this centre owes a child of this age in care this long today.
create or replace function app.outdoor_required_minutes(
  p_centre uuid,
  p_hours_in_care numeric,
  p_age_months integer
) returns integer
language sql stable security definer
set search_path = public
as $$
  select coalesce(max(r.min_minutes), 0)
  from public.outdoor_requirement r
  join public.centre c on c.jurisdiction_code = r.jurisdiction_code
  where c.id = p_centre
    and p_hours_in_care >= r.care_hours_min
    and p_age_months >= r.age_months_min
$$;

-- ── the periods themselves ──────────────────────────────────────────────────
create table public.outdoor_period (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  room_id uuid not null references public.room (id),
  outdoor_date date not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  -- what it was actually like out there; part of the "weather permitting"
  -- record, and the reason a short day is defensible
  weather text check (weather in (
    'fine', 'cloudy', 'rain', 'snow', 'extreme_cold', 'extreme_heat', 'wind', 'poor_air'
  )),
  recorded_by uuid not null references public.person (id),
  ended_by uuid references public.person (id),
  created_at timestamptz not null default now(),
  constraint outdoor_period_ends_after_it_starts
    check (ended_at is null or ended_at > started_at)
);

-- one group cannot be outside twice at once
create unique index outdoor_period_one_open_per_room
  on public.outdoor_period (room_id) where ended_at is null;

create index outdoor_period_day on public.outdoor_period (centre_id, outdoor_date);

-- The reason a day fell short. "Weather permitting" is a defence, and a
-- defence needs to have been written down at the time.
create table public.outdoor_shortfall (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  room_id uuid not null references public.room (id),
  outdoor_date date not null,
  reason text not null,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now(),
  unique (room_id, outdoor_date)
);

-- s. 47: a child is kept in only on a physician's or a parent's WRITTEN
-- instruction. Staff never excuse a child on their own.
create table public.outdoor_exemption (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  source text not null check (source in ('physician', 'parent')),
  practitioner text,
  provided_by uuid references public.person (id),
  instruction text not null,
  starts_on date not null default current_date,
  ends_on date,
  recorded_by uuid not null references public.person (id),
  ended_at timestamptz,
  ended_by uuid references public.person (id),
  created_at timestamptz not null default now(),
  constraint outdoor_exemption_dates check (ends_on is null or ends_on >= starts_on)
);

create index outdoor_exemption_live on public.outdoor_exemption (child_id) where ended_at is null;

-- ── rules ───────────────────────────────────────────────────────────────────
create or replace function app.outdoor_period_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  tz text;
begin
  select c.timezone into tz from public.centre c where c.id = new.centre_id;

  if tg_op = 'INSERT' then
    if new.started_at > clock_timestamp() then
      raise exception 'outdoor time is recorded when the group goes out, not ahead of it';
    end if;
    new.outdoor_date := (new.started_at at time zone tz)::date;
    if not exists (select 1 from public.room r where r.id = new.room_id and r.centre_id = new.centre_id) then
      raise exception 'that room is not at this centre';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    -- an ended period is a finished measurement and never moves
    if old.ended_at is not null then
      raise exception 'this outdoor period is already closed; record a new one';
    end if;
    if new.started_at is distinct from old.started_at then
      raise exception 'the time the group went out is never edited';
    end if;
    if new.ended_at is not null and new.ended_at > clock_timestamp() then
      raise exception 'outdoor time is recorded when the group comes in, not ahead of it';
    end if;
  end if;
  return new;
end;
$$;

create trigger outdoor_period_rules
  before insert or update on public.outdoor_period
  for each row execute function app.outdoor_period_rules();

create or replace function app.outdoor_exemption_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(trim(new.instruction), '') = '' then
      raise exception 'record the written instruction — that is the whole of the exemption';
    end if;
    if new.source = 'physician' and coalesce(trim(coalesce(new.practitioner, '')), '') = '' then
      raise exception 'a physician''s instruction names the physician';
    end if;
    if new.source = 'parent' then
      if new.provided_by is null then
        raise exception 'a parent''s instruction names the parent who gave it';
      end if;
      if not exists (
        select 1 from public.child_household ch
        join public.household_member hm on hm.household_id = ch.household_id
        where ch.child_id = new.child_id
          and hm.person_id = new.provided_by
          and hm.revoked_at is null
          and hm.can_consent
      ) then
        raise exception 'the instruction must come from a consenting household member';
      end if;
    end if;
  end if;
  return new;
end;
$$;

create trigger outdoor_exemption_rules
  before insert on public.outdoor_exemption
  for each row execute function app.outdoor_exemption_rules();

-- ── visibility ──────────────────────────────────────────────────────────────
alter table public.outdoor_period enable row level security;
alter table public.outdoor_shortfall enable row level security;
alter table public.outdoor_exemption enable row level security;

-- The day outside is part of the family's day: parents see it.
create policy outdoor_period_select on public.outdoor_period
  for select using (centre_id in (select app.member_centre_ids()));

create policy outdoor_shortfall_select on public.outdoor_shortfall
  for select using (centre_id in (select app.member_centre_ids()));

create policy outdoor_exemption_select on public.outdoor_exemption
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = outdoor_exemption.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
-- Writes via RPCs only.

create trigger outdoor_period_no_delete before delete on public.outdoor_period
  for each row execute function app.block_mutation();
create trigger outdoor_shortfall_no_change before update or delete on public.outdoor_shortfall
  for each row execute function app.block_mutation();
create trigger outdoor_exemption_no_delete before delete on public.outdoor_exemption
  for each row execute function app.block_mutation();
create trigger outdoor_period_audit after insert or update on public.outdoor_period
  for each row execute function app.audit_row();
create trigger outdoor_shortfall_audit after insert on public.outdoor_shortfall
  for each row execute function app.audit_row();
create trigger outdoor_exemption_audit after insert or update on public.outdoor_exemption
  for each row execute function app.audit_row();

-- s. 37: a day that fell short belongs in the daily written record, with the
-- reason it fell short, like any other exception.
create or replace function app.outdoor_shortfall_cross_reference()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  room_name text;
begin
  select r.name into room_name from public.room r where r.id = new.room_id;
  perform app.dwr_append_ref(
    new.centre_id,
    new.outdoor_date,
    jsonb_build_object(
      'type', 'outdoor_shortfall',
      'shortfall_id', new.id,
      'note', 'Outdoor play short of the two hours in ' || coalesce(room_name, 'a room') ||
              ' — ' || new.reason
    )
  );
  return new;
end;
$$;

create trigger outdoor_shortfall_cross_reference
  after insert on public.outdoor_shortfall
  for each row execute function app.outdoor_shortfall_cross_reference();

-- ── the room's day ──────────────────────────────────────────────────────────
-- Minutes are the sum of measured periods. An open period counts up to now,
-- so the room device can show a live total.
create view public.outdoor_day
with (security_invoker = on) as
select
  p.centre_id,
  p.room_id,
  p.outdoor_date,
  sum(
    extract(epoch from (coalesce(p.ended_at, now()) - p.started_at)) / 60
  )::integer as minutes,
  count(*)::integer as periods,
  bool_or(p.ended_at is null) as outside_now,
  max(p.weather) as weather
from public.outdoor_period p
group by p.centre_id, p.room_id, p.outdoor_date;

-- ── each child's day (the one the regulation actually asks about) ───────────
-- A child gets credit only for the outdoor periods that overlap their own
-- attendance in that room. Corrected attendance rows are ignored, the same
-- way the attendance register ignores them.
create or replace function public.outdoor_by_child(p_centre uuid, p_date date)
returns table (
  child_id uuid,
  full_name text,
  room_id uuid,
  hours_in_care numeric,
  -- the day the child will actually have had: while they are still here, the
  -- hours so far plus the hours left before the centre closes. Asking only
  -- "how long have they been here so far" would tell a supervisor at 3 p.m.
  -- that a full-day child is owed thirty minutes and has met it.
  hours_expected numeric,
  minutes_outside integer,
  required_minutes integer,
  short_by integer,
  exempt boolean,
  exemption_note text
)
language sql stable security definer
set search_path = public
as $$
  with live as (
    select ae.*
    from public.attendance_event ae
    where ae.centre_id = p_centre
      and ae.attendance_date = p_date
      and ae.event_type in ('arrive', 'room_transfer', 'depart')
      and not exists (
        select 1 from public.attendance_event c where c.correction_of = ae.id
      )
  ),
  spans as (
    -- every column reference here is qualified on purpose: this function's
    -- RETURNS TABLE names (child_id, room_id, …) are in scope as parameters
    -- and would otherwise shadow the columns, silently grouping every child
    -- under a null id
    select
      l.child_id,
      l.room_id,
      l.event_type,
      l.actual_time as in_at,
      lead(l.actual_time) over (partition by l.child_id order by l.actual_time, l.id) as out_at
    from live l
  ),
  present as (
    -- one row per stretch a child spent in a room; an open stretch runs to now
    select
      s.child_id, s.room_id, s.in_at,
      coalesce(s.out_at, now()) as out_at,
      s.out_at is null as still_here
    from spans s
    where s.event_type in ('arrive', 'room_transfer')
  ),
  in_care as (
    select
      p.child_id,
      sum(extract(epoch from (p.out_at - p.in_at)) / 3600) as hours,
      bool_or(p.still_here) as still_here
    from present p group by p.child_id
  ),
  basis as (
    -- what the day will amount to, so the requirement does not creep upward
    -- through the afternoon
    select
      ic.child_id,
      ic.hours,
      case
        when ic.still_here then least(
          ic.hours + greatest(
            extract(epoch from (
              ((p_date::timestamp + c.closes_at) at time zone c.timezone) - now()
            )) / 3600, 0),
          -- never more than the centre is open: a child cannot be in care
          -- longer than the day itself
          extract(epoch from (c.closes_at - c.opens_at)) / 3600)
        else ic.hours
      end as expected
    from in_care ic
    cross join public.centre c
    where c.id = p_centre
  ),
  outside as (
    select
      pr.child_id,
      sum(
        greatest(
          extract(epoch from (
            least(pr.out_at, coalesce(op.ended_at, now())) - greatest(pr.in_at, op.started_at)
          )) / 60,
          0
        )
      ) as minutes
    from present pr
    join public.outdoor_period op
      on op.room_id = pr.room_id and op.outdoor_date = p_date
    group by pr.child_id
  )
  select
    ch.id,
    ch.full_name,
    (select pr.room_id from present pr where pr.child_id = ch.id order by pr.in_at desc limit 1),
    round(b.hours::numeric, 2),
    round(b.expected::numeric, 2),
    coalesce(o.minutes, 0)::integer,
    app.outdoor_required_minutes(
      p_centre,
      b.expected::numeric,
      (extract(year from age(p_date, ch.date_of_birth)) * 12
        + extract(month from age(p_date, ch.date_of_birth)))::integer
    ),
    greatest(
      app.outdoor_required_minutes(
        p_centre,
        b.expected::numeric,
        (extract(year from age(p_date, ch.date_of_birth)) * 12
          + extract(month from age(p_date, ch.date_of_birth)))::integer
      ) - coalesce(o.minutes, 0),
      0
    )::integer,
    ex.id is not null,
    ex.instruction
  from basis b
  join public.child ch on ch.id = b.child_id
  left join outside o on o.child_id = ch.id
  left join lateral (
    select e.id, e.instruction
    from public.outdoor_exemption e
    where e.child_id = ch.id
      and e.ended_at is null
      and e.starts_on <= p_date
      and (e.ends_on is null or e.ends_on >= p_date)
    limit 1
  ) ex on true
  order by ch.full_name
$$;

-- ── RPCs ────────────────────────────────────────────────────────────────────
-- "We're going out." One tap, at the door, at the time.
create or replace function public.start_outdoor_period(
  p_centre uuid,
  p_room uuid,
  p_weather text,
  p_recorder uuid,
  p_pin text
) returns public.outdoor_period
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.outdoor_period;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if exists (select 1 from public.outdoor_period where room_id = p_room and ended_at is null) then
    raise exception 'this room is already outside — record coming in first';
  end if;

  insert into public.outdoor_period (centre_id, room_id, outdoor_date, started_at, weather, recorded_by)
  values (p_centre, p_room, current_date, clock_timestamp(), nullif(trim(coalesce(p_weather, '')), ''), recorder)
  returning * into result;
  return result;
end;
$$;

-- "We're back in." The minutes are the difference between two clock times and
-- nobody ever typed them.
create or replace function public.end_outdoor_period(
  p_room uuid,
  p_recorder uuid,
  p_pin text
) returns public.outdoor_period
language plpgsql security definer
set search_path = public
as $$
declare
  period public.outdoor_period;
  recorder uuid;
begin
  select * into period from public.outdoor_period where room_id = p_room and ended_at is null;
  if period.id is null then raise exception 'this room is not outside'; end if;
  recorder := app.resolve_recorder(period.centre_id, p_recorder, p_pin);

  -- clock_timestamp, not now(): the measurement is the wall clock, not the
  -- moment this transaction happened to begin
  update public.outdoor_period
  set ended_at = clock_timestamp(), ended_by = recorder
  where id = period.id
  returning * into period;
  return period;
end;
$$;

create or replace function public.record_outdoor_shortfall(
  p_centre uuid,
  p_room uuid,
  p_date date,
  p_reason text,
  p_recorder uuid,
  p_pin text
) returns public.outdoor_shortfall
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.outdoor_shortfall;
  on_date date := coalesce(p_date, current_date);
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if coalesce(trim(coalesce(p_reason, '')), '') = '' then
    raise exception 'say why the day was short — "weather permitting" is only a defence if it was written down';
  end if;
  if on_date > current_date then
    raise exception 'a day that has not happened yet cannot have fallen short';
  end if;

  insert into public.outdoor_shortfall (centre_id, room_id, outdoor_date, reason, recorded_by)
  values (p_centre, p_room, on_date, trim(p_reason), recorder)
  returning * into result;
  return result;
end;
$$;

create or replace function public.record_outdoor_exemption(
  p_centre uuid,
  p_child uuid,
  p_source text,
  p_instruction text,
  p_practitioner text,
  p_parent uuid,
  -- a note is often dated before it reaches the centre
  p_starts_on date,
  p_ends_on date,
  p_recorder uuid,
  p_pin text
) returns public.outdoor_exemption
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.outdoor_exemption;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);

  -- one live instruction per child
  update public.outdoor_exemption
  set ended_at = now(), ended_by = recorder
  where child_id = p_child and ended_at is null;

  insert into public.outdoor_exemption (
    centre_id, child_id, source, practitioner, provided_by, instruction,
    starts_on, ends_on, recorded_by
  ) values (
    p_centre, p_child, p_source, nullif(trim(coalesce(p_practitioner, '')), ''),
    p_parent, trim(p_instruction), coalesce(p_starts_on, current_date), p_ends_on, recorder
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.end_outdoor_exemption(
  p_exemption uuid,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  ex public.outdoor_exemption;
  recorder uuid;
begin
  select * into ex from public.outdoor_exemption where id = p_exemption;
  if ex.id is null then raise exception 'exemption not found'; end if;
  recorder := app.resolve_recorder(ex.centre_id, p_recorder, p_pin);
  if ex.ended_at is not null then raise exception 'already ended'; end if;
  update public.outdoor_exemption set ended_at = now(), ended_by = recorder where id = p_exemption;
end;
$$;

-- ── the daily written record now carries the measured number ────────────────
create or replace function app.dwr_skeleton(p_centre uuid, p_date date)
returns text
language sql stable security definer
set search_path = public
as $$
  select format(
    'Attendance: %s children present. Staff on shift: %s. Outdoor play: %s. Nothing further recorded.',
    (select count(distinct ae.child_id) from public.attendance_event ae
     where ae.centre_id = p_centre and ae.attendance_date = p_date and ae.event_type = 'arrive'),
    (select count(distinct ss.person_id) from public.staff_shift ss
     where ss.centre_id = p_centre and ss.shift_date = p_date),
    coalesce(
      (select string_agg(r.name || ' ' || d.minutes || ' min', ', ' order by r.name)
       from public.outdoor_day d
       join public.room r on r.id = d.room_id
       where d.centre_id = p_centre and d.outdoor_date = p_date),
      'none recorded')
  )
$$;
