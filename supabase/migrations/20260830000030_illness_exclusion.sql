-- 0030 illness, exclusion and return, and the public-health duties (s. 36).
-- The rules this schema holds:
--
--   * A child who becomes unwell is SEPARATED from the others, the parent is
--     contacted, and the child goes home — and every part of that is recorded,
--     including the attempts when the parent could not be reached. If it is
--     urgent and no parent can be reached, the child is seen by a physician or
--     an RN, and that is recorded too.
--   * EXCLUSION AND RETURN FOLLOW THE CENTRE'S ILLNESS POLICY, developed with
--     the local public health unit. That policy is data: illness_policy holds
--     one row per symptom with its exclusion note and its return criteria,
--     auto-seeded with the standard set and editable by leadership. The
--     criteria on an exclusion are copied from the policy rather than typed
--     freehand, so two educators on two days give the same family the same
--     answer.
--   * AN EXCLUDED CHILD CANNOT BE SIGNED IN. That is enforced in SQL, in the
--     same trigger as the s. 50 restricted-person block — not in the app,
--     where a busy morning can talk its way past it. It is never a lockout:
--     any care-staff member can clear the child with a PIN, and clearing is a
--     recorded judgment that the return criteria were met. Returning before
--     the policy's date is allowed and demands a written reason (a
--     physician's note usually), because a rule nobody can override is a rule
--     people work around.
--   * The public-health half of s. 36 has its own clocks: an order or
--     direction from the public health unit goes to the program advisor
--     within TWO business days, and an enforcement action within ONE. Both
--     are computed with the same business-day arithmetic the serious
--     occurrence clock uses, and both are chased by cron.
--   * Every exclusion is summarised in the daily written record (s. 37).

-- ── the centre's illness policy ─────────────────────────────────────────────
create table public.illness_policy (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  symptom text not null,
  label text not null,
  exclusion_note text not null,
  return_criteria text not null,
  -- how long after onset the policy says the child may come back; 0 where the
  -- criteria are a judgment rather than a clock
  min_exclusion_hours integer not null default 0 check (min_exclusion_hours >= 0),
  -- symptoms the local public health unit wants to hear about
  notify_public_health boolean not null default false,
  active boolean not null default true,
  updated_by uuid references public.person (id),
  updated_at timestamptz not null default now(),
  unique (centre_id, symptom)
);

-- The standard Ontario set. A centre edits these with its public health unit;
-- the point is that a new centre is never starting from a blank page.
create or replace function app.seed_illness_policy(p_centre uuid)
returns void
language sql security definer
set search_path = public
as $$
  insert into public.illness_policy
    (centre_id, symptom, label, exclusion_note, return_criteria, min_exclusion_hours, notify_public_health)
  values
    (p_centre, 'fever', 'Fever',
     'Excluded when the temperature is 38 °C or above, or the child is unwell with it.',
     'Twenty-four hours with no fever and without fever-reducing medication, and well enough to take part in the day.',
     24, false),
    (p_centre, 'vomiting', 'Vomiting',
     'Excluded after two episodes, or one with other symptoms.',
     'Twenty-four hours since the last episode, and eating and drinking normally.', 24, true),
    (p_centre, 'diarrhoea', 'Diarrhoea',
     'Excluded after two loose stools, or one that cannot be contained in a diaper or the toilet.',
     'Twenty-four hours since the last episode, and eating and drinking normally.', 24, true),
    (p_centre, 'rash_undiagnosed', 'Undiagnosed rash',
     'Excluded when a new rash appears with a fever or the child is unwell.',
     'Assessed by a physician or nurse practitioner, with a note saying the child may return.', 0, false),
    (p_centre, 'conjunctivitis', 'Conjunctivitis (pink eye)',
     'Excluded when the eye is discharging.',
     'Twenty-four hours after treatment starts, or a note from a physician saying it is not infectious.', 24, false),
    (p_centre, 'persistent_cough', 'Persistent cough or difficulty breathing',
     'Excluded when the child cannot take part comfortably, or needs more care than the room can give.',
     'Breathing comfortably and able to take part in the day, indoors and out.', 0, false),
    (p_centre, 'unusual_lethargy', 'Unusual lethargy or irritability',
     'Excluded when the child is not themselves and needs more care than the room can give.',
     'Back to themselves and able to take part in the day.', 0, false),
    (p_centre, 'head_lice', 'Head lice',
     'The child stays for the rest of the day; the family is told at pickup.',
     'After the first treatment; no exclusion for nits alone.', 0, false),
    (p_centre, 'suspected_communicable', 'Suspected communicable disease',
     'Excluded immediately and the public health unit is notified.',
     'As directed by the public health unit, in writing.', 0, true)
  on conflict (centre_id, symptom) do nothing
$$;

create or replace function app.centre_seed_illness_policy()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  perform app.seed_illness_policy(new.id);
  return new;
end;
$$;

create trigger centre_seed_illness_policy
  after insert on public.centre
  for each row execute function app.centre_seed_illness_policy();

-- existing centres get the standard set too
do $$
declare c record;
begin
  for c in select id from public.centre loop
    perform app.seed_illness_policy(c.id);
  end loop;
end;
$$;

-- ── the exclusion record ────────────────────────────────────────────────────
create table public.health_exclusion (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  symptom text not null,
  detail text,
  onset_at timestamptz not null default clock_timestamp(),
  -- s. 36: separated from the other children, and where they waited
  separated_at timestamptz,
  separation_place text,
  -- the first time we actually reached somebody
  parent_reached_at timestamptz,
  -- urgent, and no parent could be reached: seen by a physician or an RN
  practitioner_seen text,
  practitioner_seen_at timestamptz,
  practitioner_advice text,
  -- copied from the policy at the time, so the record says what the family
  -- was actually told even if the policy changes later
  exclusion_reason text not null,
  return_criteria text not null,
  may_return_at timestamptz,
  -- the return
  returned_at timestamptz,
  cleared_by uuid references public.person (id),
  clearance_note text,
  early_return_reason text,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default clock_timestamp()
);

-- a child is excluded once at a time
create unique index health_exclusion_one_open_per_child
  on public.health_exclusion (child_id) where returned_at is null;

create index health_exclusion_recent on public.health_exclusion (centre_id, onset_at desc);

-- Every attempt to reach the family, not just the successful one: "if not
-- possible" is only a defence if the attempts are on the record.
create table public.health_exclusion_contact (
  id uuid primary key default gen_random_uuid(),
  exclusion_id uuid not null references public.health_exclusion (id),
  centre_id uuid not null references public.centre (id),
  attempted_at timestamptz not null default clock_timestamp(),
  method text not null check (method in ('phone', 'in_app', 'in_person', 'emergency_contact')),
  person_id uuid references public.person (id),
  named text,
  outcome text not null check (outcome in ('reached', 'no_answer', 'left_message', 'unavailable')),
  note text,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default clock_timestamp()
);

create index health_exclusion_contact_parent on public.health_exclusion_contact (exclusion_id, attempted_at);

-- ── the public-health duties ────────────────────────────────────────────────
create table public.public_health_notification (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  kind text not null check (kind in (
    'communicable_disease', 'outbreak', 'order_received', 'enforcement_action'
  )),
  disease text,
  summary text not null,
  unit_name text not null,
  -- when we told the public health unit (for a disease or an outbreak)
  notified_at timestamptz,
  reference text,
  -- when their order, direction or enforcement action reached us
  order_received_at timestamptz,
  order_summary text,
  -- s. 36: to the program advisor within two business days; one for an
  -- enforcement action. Computed, never typed.
  advisor_due_on date,
  advisor_forwarded_at timestamptz,
  advisor_reference text,
  deadline_warning_sent_at timestamptz,
  overdue_notice_sent_at timestamptz,
  closed_at timestamptz,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now()
);

create index public_health_open on public.public_health_notification (centre_id)
  where closed_at is null;

-- ── rules ───────────────────────────────────────────────────────────────────
create or replace function app.health_exclusion_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.child ch where ch.id = new.child_id and ch.centre_id = new.centre_id) then
      raise exception 'child is not enrolled at this centre';
    end if;
    if coalesce(trim(new.exclusion_reason), '') = '' or coalesce(trim(new.return_criteria), '') = '' then
      raise exception 'an exclusion records why the child was sent home and what has to be true before they come back';
    end if;
    if new.onset_at > clock_timestamp() then
      raise exception 'a child cannot have become unwell in the future';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    -- what the family was told is fixed; only the unfolding day is written
    if row(new.centre_id, new.child_id, new.symptom, new.onset_at,
           new.exclusion_reason, new.return_criteria, new.recorded_by)
       is distinct from
       row(old.centre_id, old.child_id, old.symptom, old.onset_at,
           old.exclusion_reason, old.return_criteria, old.recorded_by) then
      raise exception 'the reason and the return criteria are what the family was told; they are never rewritten';
    end if;
    if old.returned_at is not null then
      raise exception 'this exclusion is closed; record a new one if the child is unwell again';
    end if;
  end if;
  return new;
end;
$$;

create trigger health_exclusion_rules
  before insert or update on public.health_exclusion
  for each row execute function app.health_exclusion_rules();

create or replace function app.public_health_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  juris text;
  received date;
begin
  if tg_op = 'INSERT' then
    select c.jurisdiction_code into juris from public.centre c where c.id = new.centre_id;
    if new.kind in ('order_received', 'enforcement_action') then
      received := (coalesce(new.order_received_at, now()))::date;
      new.order_received_at := coalesce(new.order_received_at, now());
      -- an enforcement action is one business day; an order is two
      new.advisor_due_on := app.add_business_days(
        juris, received, case when new.kind = 'enforcement_action' then 1 else 2 end
      );
    end if;
  end if;

  if tg_op = 'UPDATE' and new.closed_at is not null and old.closed_at is null then
    if new.advisor_due_on is not null and new.advisor_forwarded_at is null then
      raise exception 'send the order to the program advisor before closing this — that is the duty, not the paperwork';
    end if;
  end if;
  return new;
end;
$$;

create trigger public_health_rules
  before insert or update on public.public_health_notification
  for each row execute function app.public_health_rules();

-- ── an excluded child is not signed in ──────────────────────────────────────
-- Extends the attendance trigger with the s. 36 block, beside the s. 50
-- restricted-person block: both are refusals the app cannot talk its way past.
create or replace function app.attendance_event_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  tz text;
  excl public.health_exclusion;
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

  -- s. 36 exclusion block. A correction may still be recorded: the register
  -- must always be able to say what actually happened.
  if new.event_type = 'arrive' and new.correction_of is null then
    select * into excl from public.health_exclusion
    where child_id = new.child_id and returned_at is null;
    if excl.id is not null then
      raise exception 'sign-in blocked: % is excluded (%). Before they come back: %',
        (select split_part(ch.full_name, ' ', 1) from public.child ch where ch.id = new.child_id),
        excl.exclusion_reason,
        excl.return_criteria;
    end if;
  end if;

  return new;
end;
$$;

-- ── visibility ──────────────────────────────────────────────────────────────
alter table public.illness_policy enable row level security;
alter table public.health_exclusion enable row level security;
alter table public.health_exclusion_contact enable row level security;
alter table public.public_health_notification enable row level security;

-- The illness policy is for families as much as staff: it is the answer to
-- "when can she come back?"
create policy illness_policy_select on public.illness_policy
  for select using (centre_id in (select app.member_centre_ids()));

create policy health_exclusion_select on public.health_exclusion
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = health_exclusion.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );

-- The attempts to reach a family are the centre's own record, and they may
-- name other people; staff only.
create policy health_exclusion_contact_select on public.health_exclusion_contact
  for select using (centre_id in (select app.care_centre_ids()));

create policy public_health_notification_select on public.public_health_notification
  for select using (centre_id in (select app.care_centre_ids()));
-- Writes via RPCs only.

create trigger health_exclusion_no_delete before delete on public.health_exclusion
  for each row execute function app.block_mutation();
create trigger health_exclusion_contact_no_change before update or delete on public.health_exclusion_contact
  for each row execute function app.block_mutation();
create trigger public_health_no_delete before delete on public.public_health_notification
  for each row execute function app.block_mutation();
create trigger health_exclusion_audit after insert or update on public.health_exclusion
  for each row execute function app.audit_row();
create trigger health_exclusion_contact_audit after insert on public.health_exclusion_contact
  for each row execute function app.audit_row();
create trigger public_health_audit after insert or update on public.public_health_notification
  for each row execute function app.audit_row();
create trigger illness_policy_audit after insert or update on public.illness_policy
  for each row execute function app.audit_row();

-- s. 37: a child sent home unwell belongs in the day's record.
create or replace function app.health_exclusion_cross_reference()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  tz text;
begin
  select c.timezone into tz from public.centre c where c.id = new.centre_id;
  perform app.dwr_append_ref(
    new.centre_id,
    (new.onset_at at time zone tz)::date,
    jsonb_build_object(
      'type', 'illness_exclusion',
      'exclusion_id', new.id,
      'note', (select split_part(ch.full_name, ' ', 1) from public.child ch where ch.id = new.child_id)
              || ' sent home unwell — ' || new.exclusion_reason
    )
  );
  return new;
end;
$$;

create trigger health_exclusion_cross_reference
  after insert on public.health_exclusion
  for each row execute function app.health_exclusion_cross_reference();

-- ── who is out, and until when ──────────────────────────────────────────────
create view public.exclusion_status
with (security_invoker = on) as
select
  e.*,
  ch.full_name,
  (e.returned_at is null) as is_open,
  (e.may_return_at is not null and now() >= e.may_return_at) as criteria_date_passed,
  (select count(*) from public.health_exclusion_contact c where c.exclusion_id = e.id) as contact_attempts
from public.health_exclusion e
join public.child ch on ch.id = e.child_id;

-- ── RPCs ────────────────────────────────────────────────────────────────────
-- The whole of "a child became unwell", recorded at the time it happens: the
-- symptom, where they were separated to, and the exclusion that follows from
-- the centre's own policy. The family is alerted in the same breath.
create or replace function public.record_illness(
  p_centre uuid,
  p_child uuid,
  p_symptom text,
  p_detail text,
  p_separation_place text,
  p_recorder uuid,
  p_pin text
) returns public.health_exclusion
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  policy public.illness_policy;
  result public.health_exclusion;
  first_name text;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);

  select * into policy from public.illness_policy
  where centre_id = p_centre and symptom = p_symptom and active;
  if policy.id is null then
    raise exception 'that symptom is not in this centre''s illness policy';
  end if;
  if coalesce(trim(coalesce(p_separation_place, '')), '') = '' then
    raise exception 'record where the child is waiting — s. 36 separates them from the others';
  end if;
  if exists (select 1 from public.health_exclusion where child_id = p_child and returned_at is null) then
    raise exception 'this child is already excluded and has not been cleared to return';
  end if;

  select split_part(ch.full_name, ' ', 1) into first_name from public.child ch where ch.id = p_child;

  insert into public.health_exclusion (
    centre_id, child_id, symptom, detail, separated_at, separation_place,
    exclusion_reason, return_criteria, may_return_at, recorded_by
  ) values (
    p_centre, p_child, p_symptom, nullif(trim(coalesce(p_detail, '')), ''),
    clock_timestamp(), trim(p_separation_place),
    policy.label || ' — ' || policy.exclusion_note,
    policy.return_criteria,
    case when policy.min_exclusion_hours > 0
      then clock_timestamp() + make_interval(hours => policy.min_exclusion_hours)
      else null end,
    recorder
  ) returning * into result;

  -- the family needs to know now, not in the evening summary
  insert into public.notification (
    centre_id, child_id, recipient_person_id, channel, event_type, title, body,
    requires_acknowledgement, created_by, ref_id
  )
  select
    p_centre, p_child, hm.person_id, 'now', 'illness_sent_home',
    first_name || ' is unwell',
    first_name || ' has ' || lower(policy.label) ||
      ' and is resting in ' || trim(p_separation_place) ||
      '. Please call the centre to arrange pickup. Before coming back: ' || policy.return_criteria,
    true, recorder, result.id
  from public.child_household chh
  join public.household_member hm on hm.household_id = chh.household_id
  where chh.child_id = p_child and hm.revoked_at is null and hm.can_view;

  return result;
end;
$$;

-- Every attempt, reached or not.
create or replace function public.record_illness_contact(
  p_exclusion uuid,
  p_method text,
  p_person uuid,
  p_named text,
  p_outcome text,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns public.health_exclusion_contact
language plpgsql security definer
set search_path = public
as $$
declare
  excl public.health_exclusion;
  recorder uuid;
  result public.health_exclusion_contact;
begin
  select * into excl from public.health_exclusion where id = p_exclusion;
  if excl.id is null then raise exception 'exclusion not found'; end if;
  recorder := app.resolve_recorder(excl.centre_id, p_recorder, p_pin);
  if p_person is null and coalesce(trim(coalesce(p_named, '')), '') = '' then
    raise exception 'record who was contacted';
  end if;

  insert into public.health_exclusion_contact (
    exclusion_id, centre_id, method, person_id, named, outcome, note, recorded_by
  ) values (
    p_exclusion, excl.centre_id, p_method, p_person,
    nullif(trim(coalesce(p_named, '')), ''), p_outcome,
    nullif(trim(coalesce(p_note, '')), ''), recorder
  ) returning * into result;

  if p_outcome = 'reached' and excl.parent_reached_at is null then
    update public.health_exclusion set parent_reached_at = result.attempted_at where id = p_exclusion;
  end if;
  return result;
end;
$$;

-- Urgent, and nobody could be reached: a physician or an RN saw the child.
create or replace function public.record_illness_practitioner(
  p_exclusion uuid,
  p_practitioner text,
  p_advice text,
  p_recorder uuid,
  p_pin text
) returns public.health_exclusion
language plpgsql security definer
set search_path = public
as $$
declare
  excl public.health_exclusion;
  recorder uuid;
begin
  select * into excl from public.health_exclusion where id = p_exclusion;
  if excl.id is null then raise exception 'exclusion not found'; end if;
  recorder := app.resolve_recorder(excl.centre_id, p_recorder, p_pin);
  if coalesce(trim(coalesce(p_practitioner, '')), '') = '' then
    raise exception 'name the physician or registered nurse who saw the child';
  end if;

  update public.health_exclusion
  set practitioner_seen = trim(p_practitioner),
      practitioner_seen_at = clock_timestamp(),
      practitioner_advice = nullif(trim(coalesce(p_advice, '')), '')
  where id = p_exclusion
  returning * into excl;
  return excl;
end;
$$;

-- The child may come back. This is a judgment, and it is signed: somebody
-- says the criteria were met, and their name is on it. Coming back before the
-- policy's date is allowed and needs a written reason.
create or replace function public.clear_for_return(
  p_exclusion uuid,
  p_note text,
  p_early_reason text,
  p_recorder uuid,
  p_pin text
) returns public.health_exclusion
language plpgsql security definer
set search_path = public
as $$
declare
  excl public.health_exclusion;
  recorder uuid;
begin
  select * into excl from public.health_exclusion where id = p_exclusion;
  if excl.id is null then raise exception 'exclusion not found'; end if;
  recorder := app.resolve_recorder(excl.centre_id, p_recorder, p_pin);
  if excl.returned_at is not null then raise exception 'this child has already been cleared'; end if;
  if coalesce(trim(coalesce(p_note, '')), '') = '' then
    raise exception 'say how the return criteria were met — that note is the clearance';
  end if;
  if excl.may_return_at is not null and now() < excl.may_return_at
     and coalesce(trim(coalesce(p_early_reason, '')), '') = '' then
    raise exception 'the policy says not before % — record why they may come back sooner (a physician''s note, usually)',
      to_char(excl.may_return_at, 'Mon FMDD HH24:MI');
  end if;

  update public.health_exclusion
  set returned_at = clock_timestamp(),
      cleared_by = recorder,
      clearance_note = trim(p_note),
      early_return_reason = nullif(trim(coalesce(p_early_reason, '')), '')
  where id = p_exclusion
  returning * into excl;
  return excl;
end;
$$;

create or replace function public.set_illness_policy(
  p_centre uuid,
  p_symptom text,
  p_exclusion_note text,
  p_return_criteria text,
  p_min_hours integer,
  p_active boolean,
  p_recorder uuid,
  p_pin text
) returns public.illness_policy
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.illness_policy;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate')
  ) then
    raise exception 'the illness policy is the licensee''s, developed with the public health unit';
  end if;
  if coalesce(trim(coalesce(p_return_criteria, '')), '') = '' then
    raise exception 'every symptom needs its return criteria — that is what families are told';
  end if;

  update public.illness_policy
  set exclusion_note = coalesce(nullif(trim(coalesce(p_exclusion_note, '')), ''), exclusion_note),
      return_criteria = trim(p_return_criteria),
      min_exclusion_hours = coalesce(p_min_hours, min_exclusion_hours),
      active = coalesce(p_active, active),
      updated_by = recorder,
      updated_at = now()
  where centre_id = p_centre and symptom = p_symptom
  returning * into result;
  if result.id is null then raise exception 'that symptom is not in this centre''s policy'; end if;
  return result;
end;
$$;

-- ── the public-health duties ────────────────────────────────────────────────
create or replace function public.record_public_health_notification(
  p_centre uuid,
  p_kind text,
  p_disease text,
  p_summary text,
  p_unit text,
  p_notified_at timestamptz,
  p_reference text,
  p_order_received_at timestamptz,
  p_order_summary text,
  p_recorder uuid,
  p_pin text
) returns public.public_health_notification
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.public_health_notification;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if coalesce(trim(coalesce(p_summary, '')), '') = '' or coalesce(trim(coalesce(p_unit, '')), '') = '' then
    raise exception 'record what happened and which public health unit it involves';
  end if;

  insert into public.public_health_notification (
    centre_id, kind, disease, summary, unit_name, notified_at, reference,
    order_received_at, order_summary, recorded_by
  ) values (
    p_centre, p_kind, nullif(trim(coalesce(p_disease, '')), ''), trim(p_summary),
    trim(p_unit), p_notified_at, nullif(trim(coalesce(p_reference, '')), ''),
    p_order_received_at, nullif(trim(coalesce(p_order_summary, '')), ''), recorder
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.forward_to_program_advisor(
  p_notification uuid,
  p_reference text,
  p_recorder uuid,
  p_pin text
) returns public.public_health_notification
language plpgsql security definer
set search_path = public
as $$
declare
  n public.public_health_notification;
  recorder uuid;
begin
  select * into n from public.public_health_notification where id = p_notification;
  if n.id is null then raise exception 'notification not found'; end if;
  recorder := app.resolve_recorder(n.centre_id, p_recorder, p_pin);
  if n.advisor_due_on is null then
    raise exception 'there is no order here to forward';
  end if;
  if n.advisor_forwarded_at is not null then
    raise exception 'this order has already gone to the program advisor';
  end if;
  if coalesce(trim(coalesce(p_reference, '')), '') = '' then
    raise exception 'record how it was sent — the evidence is the point';
  end if;

  update public.public_health_notification
  set advisor_forwarded_at = now(), advisor_reference = trim(p_reference)
  where id = p_notification
  returning * into n;
  return n;
end;
$$;

create or replace function public.close_public_health_notification(
  p_notification uuid,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  n public.public_health_notification;
begin
  select * into n from public.public_health_notification where id = p_notification;
  if n.id is null then raise exception 'notification not found'; end if;
  perform app.resolve_recorder(n.centre_id, p_recorder, p_pin);
  if n.closed_at is not null then raise exception 'already closed'; end if;
  update public.public_health_notification set closed_at = now() where id = p_notification;
end;
$$;

-- The two-business-day clock, chased the way the CCLS clock is.
create or replace function app.public_health_reminders()
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  n record;
begin
  for n in
    select * from public.public_health_notification
    where closed_at is null
      and advisor_due_on is not null
      and advisor_forwarded_at is null
      and (
        (deadline_warning_sent_at is null and current_date >= advisor_due_on - 1)
        or (overdue_notice_sent_at is null and current_date > advisor_due_on)
      )
  loop
    insert into public.notification (
      centre_id, recipient_person_id, channel, event_type, title, body,
      requires_acknowledgement, ref_id
    )
    select
      n.centre_id, pr.person_id, 'now', 'public_health_order',
      case when current_date > n.advisor_due_on
        then 'Public health order OVERDUE to the program advisor'
        else 'Public health order due to the program advisor' end,
      'The ' || replace(n.kind, '_', ' ') || ' from ' || n.unit_name ||
      ' must reach the program advisor by ' || to_char(n.advisor_due_on, 'FMDD Mon YYYY') ||
      '. The app never sends it for you.',
      true, n.id
    from public.person_role pr
    where pr.centre_id = n.centre_id and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate');

    update public.public_health_notification
    set deadline_warning_sent_at = coalesce(deadline_warning_sent_at, now()),
        overdue_notice_sent_at = case when current_date > advisor_due_on
          then coalesce(overdue_notice_sent_at, now()) else overdue_notice_sent_at end
    where id = n.id;
  end loop;
end;
$$;

select cron.schedule('public-health-clock', '20 8 * * *', $$select app.public_health_reminders()$$);
