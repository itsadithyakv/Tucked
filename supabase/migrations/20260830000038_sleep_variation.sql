-- 0038 sleep, the rest of s. 33.1 — back-to-sleep and the written direction
-- that varies it, plus the findings a sleeping room produces.
--
-- What was already here: sleep CHECKS were gated (under 24 months, infant,
-- toddler or family rooms only) and the check cadence lives in room settings.
-- What was NOT here, despite the compliance map claiming it: back-to-sleep
-- itself. `position` was free text in the care log payload — the domain package
-- validated it as an enum and the database validated nothing — and a two-month
-- old could be recorded face-down with no note and no objection.
--
-- THE LINE THIS MODULE DRAWS, and it is the whole design:
--
--   PLACING a child is an act. It is regulated, and it can be refused.
--   FINDING a child somewhere is an observation. It is never refused.
--
-- s. 33.1 is about how a child is PLACED for sleep. So nap_start is where the
-- rule bites and where a write can fail. A sleep check records what an educator
-- saw when they walked to the crib — and babies roll. Refusing to record a
-- child found on their front would not make the child safer; it would delete
-- the only evidence that anyone noticed. So a check always writes, and the
-- system raises the finding instead of swallowing the fact.

-- ── the payload, validated on both faces ────────────────────────────────────
-- packages/domain/src/careLogSchemas.ts has always had
-- position: z.enum(['back','side','front']).optional(). The database checked
-- nothing. Two faces of one schema, and only one of them was load-bearing.
create or replace function app.validate_care_log_payload(p_type public.care_log_type, p jsonb)
returns boolean
language sql immutable
as $$
  select case p_type
    when 'meal' then
      p ? 'meal' and p ->> 'meal' in ('breakfast', 'lunch', 'snack_am', 'snack_pm')
      and p ? 'eaten' and p ->> 'eaten' in ('none', 'some', 'most', 'all')
    when 'bottle' then
      p ? 'amount_ml' and jsonb_typeof(p -> 'amount_ml') = 'number'
      and p ? 'kind' and p ->> 'kind' in ('breast_milk', 'formula', 'milk', 'water')
    when 'nap_start' then
      -- how the child was PLACED. Optional in the payload because a four year
      -- old on a cot has no regulated sleep position; required by the rules
      -- trigger for the children s. 33.1 actually names.
      not (p ? 'position') or p ->> 'position' in ('back', 'side', 'front')
    when 'nap_end' then true
    when 'sleep_check' then
      p ? 'breathing_ok' and jsonb_typeof(p -> 'breathing_ok') = 'boolean'
      and (not (p ? 'position') or p ->> 'position' in ('back', 'side', 'front'))
      -- did the educator move the child back? A check that found a baby off
      -- their back and says nothing about what happened next is half a record.
      and (not (p ? 'repositioned') or jsonb_typeof(p -> 'repositioned') = 'boolean')
    when 'diaper' then
      p ? 'kind' and p ->> 'kind' in ('wet', 'soiled', 'both', 'dry')
    when 'toilet' then
      p ? 'kind' and p ->> 'kind' in ('urine', 'bm', 'attempt', 'accident')
    when 'outdoor' then
      (p ? 'minutes' and jsonb_typeof(p -> 'minutes') = 'number')
      or p ? 'skipped_reason'
    when 'health_observation' then
      p ? 'observation' and length(p ->> 'observation') > 0
    when 'activity' then
      p ? 'description' and length(p ->> 'description') > 0
    when 'note' then
      p ? 'text' and length(p ->> 'text') > 0
    when 'photo' then
      p ? 'storage_path' and p ? 'captured_at'
  end
$$;

-- ── the written direction ───────────────────────────────────────────────────
-- Shaped after outdoor_exemption (s. 47), which has proved itself: a source,
-- the instruction in the words it was given in, dates, and an end rather than
-- an edit. One difference matters, and it is the regulation's difference.
create table public.sleep_direction (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  source text not null check (source in ('physician', 'parent')),
  -- 'position' varies how the child is placed. 'rest' is everything else a
  -- family asks for — does not nap, wake by two, needs the blue blanket.
  kind text not null check (kind in ('position', 'rest')),
  -- for kind = 'position': what this direction permits, over and above back.
  permitted_positions text[],
  practitioner text,
  provided_by uuid references public.person (id),
  instruction text not null,
  starts_on date not null default current_date,
  ends_on date,
  recorded_by uuid not null references public.person (id),
  ended_at timestamptz,
  ended_by uuid references public.person (id),
  created_at timestamptz not null default now(),
  constraint sleep_direction_dates check (ends_on is null or ends_on >= starts_on),

  -- THE REGULATION, as a constraint rather than as a habit. s. 33.1 varies
  -- back-to-sleep on a PHYSICIAN's written recommendation. A parent may ask for
  -- a great many things about their child's rest and the centre should hear all
  -- of them, but a parent cannot authorise a baby onto their front. The schema
  -- will not store the row, so no screen can offer it and no import can smuggle
  -- it in.
  constraint only_a_physician_varies_sleep_position
    check (kind <> 'position' or source = 'physician'),
  constraint position_direction_names_the_positions
    check ((kind = 'position') = (permitted_positions is not null)),
  constraint permitted_positions_are_real
    check (
      permitted_positions is null
      or (
        array_length(permitted_positions, 1) >= 1
        and permitted_positions <@ array['back', 'side', 'front']
      )
    )
);

create index sleep_direction_live on public.sleep_direction (child_id)
  where ended_at is null;

create or replace function app.sleep_direction_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(trim(new.instruction), '') = '' then
      raise exception 'record the written direction — that is the whole of it';
    end if;
    if new.source = 'physician' and coalesce(trim(coalesce(new.practitioner, '')), '') = '' then
      raise exception 'a physician''s direction names the physician';
    end if;
    if new.source = 'parent' then
      if new.provided_by is null then
        raise exception 'a parent''s direction names the parent who gave it';
      end if;
      if not exists (
        select 1 from public.child_household ch
        join public.household_member hm on hm.household_id = ch.household_id
        where ch.child_id = new.child_id
          and hm.person_id = new.provided_by
          and hm.revoked_at is null
          and hm.can_consent
      ) then
        raise exception 'the direction must come from a consenting household member';
      end if;
    end if;
    if not exists (
      select 1 from public.child c
      where c.id = new.child_id and c.centre_id = new.centre_id
    ) then
      raise exception 'that child is not enrolled at this centre';
    end if;
  end if;
  return new;
end;
$$;

create trigger sleep_direction_rules
  before insert on public.sleep_direction
  for each row execute function app.sleep_direction_rules();

alter table public.sleep_direction enable row level security;

create policy sleep_direction_select on public.sleep_direction
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = sleep_direction.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
-- Writes via RPCs only.

create trigger sleep_direction_no_delete before delete on public.sleep_direction
  for each row execute function app.block_mutation();
create trigger sleep_direction_audit after insert or update on public.sleep_direction
  for each row execute function app.audit_row();

-- ── what a child may be placed in, on a given day ───────────────────────────
-- Back is always in the set. A direction ADDS positions; it can never remove
-- back, because back is never the unsafe answer and no note should be able to
-- make it one.
create or replace function app.permitted_sleep_positions(p_child uuid, p_on date)
returns text[]
language sql stable security definer
set search_path = public
as $$
  select array(
    select distinct pos
    from (
      select 'back'::text as pos
      union all
      select unnest(sd.permitted_positions)
      from public.sleep_direction sd
      where sd.child_id = p_child
        and sd.kind = 'position'
        and sd.ended_at is null
        and sd.starts_on <= p_on
        and (sd.ends_on is null or sd.ends_on >= p_on)
    ) s
  )
$$;

-- ── the rule, at the moment of placing ──────────────────────────────────────
-- This replaces app.care_log_rules(), which 0006 wrote and 0022 AMENDED — a
-- rewrite based on the 0006 text silently drops the s. 72(5) anonymisation
-- escape hatch 0022 added, and the retention sweep then fails on every child it
-- tries to anonymise. It did, on the first run of this migration. When
-- replacing a function, start from the database's current definition, not from
-- the migration that first created it.
create or replace function app.care_log_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  tz text;
  dob date;
  preset public.age_group_preset;
  pos text;
  allowed text[];
begin
  if tg_op = 'UPDATE' then
    if app.is_anonymising() then
      return new; -- retention anonymisation only; s. 72(5)
    end if;
    raise exception 'care logs are never updated; record a correction';
  end if;

  select c.timezone into tz from public.centre c where c.id = new.centre_id;
  new.log_date := (new.logged_at at time zone tz)::date;

  select ch.date_of_birth into dob from public.child ch
  where ch.id = new.child_id and ch.centre_id = new.centre_id;
  if dob is null then
    raise exception 'child is not enrolled at this centre';
  end if;

  if not app.validate_care_log_payload(new.log_type, new.payload) then
    raise exception 'invalid payload for care log type %', new.log_type;
  end if;

  -- s. 33.1: direct visual sleep checks are for children under 24 months in
  -- infant, toddler or family rooms; recording one elsewhere is an error, so
  -- the record can never *appear* to satisfy a rule that does not apply.
  if new.log_type = 'sleep_check' then
    select ag.preset into preset
    from public.room r join public.age_group ag on ag.id = r.age_group_id
    where r.id = new.room_id;
    if preset not in ('infant', 'toddler', 'family') then
      raise exception 'sleep checks apply to infant, toddler or family rooms only';
    end if;
    if dob + interval '24 months' <= new.log_date then
      raise exception 'sleep checks apply to children under 24 months';
    end if;
  end if;

  -- s. 33.1 back-to-sleep. A child under 12 months is PLACED on their back
  -- unless their physician has recommended otherwise in writing. This is the
  -- one sleep write that can be refused, because it is the one that is an act
  -- rather than an observation.
  --
  -- A correction is still allowed through: a nap wrongly recorded must be
  -- correctable to what actually happened, and a register that cannot state a
  -- breach is worth less than one that can.
  if new.log_type = 'nap_start'
     and new.correction_of is null
     and dob + interval '12 months' > new.log_date then
    pos := new.payload ->> 'position';
    if pos is null then
      raise exception
        'record how % was placed for sleep (back, side or front) — under 12 months it is the regulated fact',
        (select split_part(c.full_name, ' ', 1) from public.child c where c.id = new.child_id);
    end if;
    allowed := app.permitted_sleep_positions(new.child_id, new.log_date);
    if not (pos = any (allowed)) then
      raise exception
        'under 12 months, % is placed on their back unless a physician has recommended otherwise in writing. Record the physician''s direction first.',
        (select split_part(c.full_name, ' ', 1) from public.child c where c.id = new.child_id);
    end if;
  end if;

  if new.correction_of is not null and not exists (
    select 1 from public.care_log cl
    where cl.id = new.correction_of and cl.child_id = new.child_id
  ) then
    raise exception 'correction must reference a log for the same child';
  end if;

  return new;
end;
$$;

-- ── the findings a sleeping room produces ───────────────────────────────────
-- Derived, not recorded. There is no human input here beyond what the log
-- already holds, so a view cannot drift from the logs the way a table could.

-- A check that found a child under 12 months off their back, with nothing on
-- file permitting it. Not a breach in itself — babies roll, and the educator
-- who saw it and wrote it down did the right thing. It is a fact the day owes
-- the record, and the supervisor should see it before an inspector does.
create view public.sleep_position_finding
with (security_invoker = on) as
select
  cl.id as care_log_id,
  cl.centre_id,
  cl.child_id,
  c.full_name,
  cl.room_id,
  cl.log_date,
  cl.logged_at,
  cl.payload ->> 'position' as found_position,
  coalesce((cl.payload ->> 'repositioned')::boolean, false) as repositioned,
  cl.recorded_by
from public.care_log cl
join public.child c on c.id = cl.child_id
where cl.log_type = 'sleep_check'
  and cl.payload ->> 'position' is not null
  and cl.payload ->> 'position' <> 'back'
  and c.date_of_birth + interval '12 months' > cl.log_date
  and not exists (
    select 1 from public.care_log corr where corr.correction_of = cl.id
  )
  and not (cl.payload ->> 'position' = any (
    app.permitted_sleep_positions(cl.child_id, cl.log_date)
  ));

-- s. 33.1: toddler and preschool rest periods are no longer than two hours.
-- A child who slept longer slept longer — the fact is not editable and the
-- nap_end is not refusable. The day records it and says so.
create view public.long_rest_finding
with (security_invoker = on) as
with naps as (
  select
    cl.centre_id,
    cl.child_id,
    cl.room_id,
    cl.log_date,
    cl.logged_at as started_at,
    lead(cl.logged_at) over (
      partition by cl.child_id, cl.log_date order by cl.logged_at, cl.id
    ) as next_at,
    lead(cl.log_type) over (
      partition by cl.child_id, cl.log_date order by cl.logged_at, cl.id
    ) as next_type
  from public.care_log cl
  where cl.log_type in ('nap_start', 'nap_end')
    and not exists (
      select 1 from public.care_log corr where corr.correction_of = cl.id
    )
)
select
  n.centre_id,
  n.child_id,
  c.full_name,
  n.room_id,
  n.log_date,
  n.started_at,
  n.next_at as ended_at,
  (extract(epoch from (n.next_at - n.started_at)) / 60)::integer as minutes
from naps n
join public.child c on c.id = n.child_id
join public.room r on r.id = n.room_id
join public.age_group ag on ag.id = r.age_group_id
where n.next_type = 'nap_end'
  and ag.preset in ('toddler', 'preschool')
  and n.next_at - n.started_at > interval '2 hours';

-- ── the day's record hears about both (s. 37) ───────────────────────────────
create or replace function app.sleep_cross_reference()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  first_name text;
  pos text;
  minutes integer;
  started timestamptz;
  preset public.age_group_preset;
begin
  select split_part(c.full_name, ' ', 1) into first_name
  from public.child c where c.id = new.child_id;

  if new.log_type = 'sleep_check' then
    pos := new.payload ->> 'position';
    if pos is not null and pos <> 'back'
       and not (pos = any (app.permitted_sleep_positions(new.child_id, new.log_date)))
       and exists (
         select 1 from public.child c
         where c.id = new.child_id
           and c.date_of_birth + interval '12 months' > new.log_date
       )
    then
      perform app.dwr_append_ref(
        new.centre_id,
        new.log_date,
        jsonb_build_object(
          'type', 'sleep_position',
          'care_log_id', new.id,
          'note', first_name || ' was found on their ' || pos ||
                  ' at a sleep check — under 12 months, with no physician''s direction on file' ||
                  case
                    when coalesce((new.payload ->> 'repositioned')::boolean, false)
                      then ', and was placed back.'
                    else '. The record does not say whether they were repositioned.'
                  end
        )
      );
    end if;
  end if;

  -- a rest period that ran past two hours, noted when it ends
  if new.log_type = 'nap_end' then
    select ag.preset into preset
    from public.room r join public.age_group ag on ag.id = r.age_group_id
    where r.id = new.room_id;

    if preset in ('toddler', 'preschool') then
      select cl.logged_at into started
      from public.care_log cl
      where cl.child_id = new.child_id
        and cl.log_date = new.log_date
        and cl.log_type = 'nap_start'
        and cl.logged_at <= new.logged_at
        and not exists (select 1 from public.care_log x where x.correction_of = cl.id)
      order by cl.logged_at desc
      limit 1;

      if started is not null then
        minutes := (extract(epoch from (new.logged_at - started)) / 60)::integer;
        if minutes > 120 then
          perform app.dwr_append_ref(
            new.centre_id,
            new.log_date,
            jsonb_build_object(
              'type', 'long_rest',
              'care_log_id', new.id,
              'note', first_name || ' rested ' || minutes ||
                      ' minutes — s. 33.1 sets the rest period at no longer than two hours.'
            )
          );
        end if;
      end if;
    end if;
  end if;

  return new;
end;
$$;

create trigger sleep_cross_reference
  after insert on public.care_log
  for each row execute function app.sleep_cross_reference();

-- ── write RPCs ──────────────────────────────────────────────────────────────
create or replace function public.record_sleep_direction(
  p_centre uuid,
  p_child uuid,
  p_source text,
  p_kind text,
  p_instruction text,
  p_positions text[],
  p_practitioner text,
  p_parent uuid,
  -- a note is often dated before it reaches the centre
  p_starts_on date,
  p_ends_on date,
  p_recorder uuid,
  p_pin text
) returns public.sleep_direction
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.sleep_direction;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);

  -- one live direction per child PER KIND: a physician's position note and a
  -- family's rest preference are different things and do not replace each
  -- other. Recording a new one of the same kind ends the one it supersedes.
  update public.sleep_direction
  set ended_at = now(), ended_by = recorder
  where child_id = p_child and kind = p_kind and ended_at is null;

  insert into public.sleep_direction (
    centre_id, child_id, source, kind, permitted_positions, practitioner,
    provided_by, instruction, starts_on, ends_on, recorded_by
  ) values (
    p_centre, p_child, p_source, p_kind,
    case when p_kind = 'position' then p_positions else null end,
    nullif(trim(coalesce(p_practitioner, '')), ''),
    p_parent, trim(p_instruction), coalesce(p_starts_on, current_date), p_ends_on, recorder
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.end_sleep_direction(
  p_direction uuid,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  dir public.sleep_direction;
  recorder uuid;
begin
  select * into dir from public.sleep_direction where id = p_direction;
  if dir.id is null then
    raise exception 'no such sleep direction';
  end if;
  recorder := app.resolve_recorder(dir.centre_id, p_recorder, p_pin);
  update public.sleep_direction
  set ended_at = now(), ended_by = recorder
  where id = p_direction and ended_at is null;
end;
$$;

-- ── what the room device asks before it lets an educator lay a baby down ────
-- The nap board calls this so the screen can offer the right positions rather
-- than offering all three and rejecting two of them after the tap.
create or replace function public.sleep_placement_options(p_child uuid, p_on date default null)
returns table (
  child_id uuid,
  under_twelve_months boolean,
  positions text[],
  direction_id uuid,
  direction_source text,
  direction_instruction text,
  practitioner text
)
language sql stable security definer
set search_path = public
as $$
  select
    c.id,
    c.date_of_birth + interval '12 months' > coalesce(p_on, current_date),
    app.permitted_sleep_positions(c.id, coalesce(p_on, current_date)),
    sd.id,
    sd.source,
    sd.instruction,
    sd.practitioner
  from public.child c
  left join public.sleep_direction sd
    on sd.child_id = c.id
   and sd.kind = 'position'
   and sd.ended_at is null
   and sd.starts_on <= coalesce(p_on, current_date)
   and (sd.ends_on is null or sd.ends_on >= coalesce(p_on, current_date))
  where c.id = p_child
    and c.centre_id in (select app.care_centre_ids());
$$;
