-- 0027 parent handbook (s. 45) and its acknowledgements. The rules this
-- schema holds:
--   * s. 45(1) lists what the handbook MUST contain. That list is data, not
--     code: handbook_section_spec is keyed by jurisdiction, so a Manitoba or
--     Quebec pack is a set of rows, and every rule below keeps working.
--   * A version cannot be published with a required section missing or blank.
--     That is the whole of s. 45 made mechanical — you cannot hand parents an
--     incomplete handbook.
--   * Published versions are IMMUTABLE. The handbook a parent acknowledged in
--     March is recoverable word-for-word in October, which is the only way an
--     acknowledgement means anything.
--   * Sections the product already holds are SOURCED from the live record, so
--     the handbook can never contradict it: the anaphylaxis policy is the
--     anaphylaxis policy (s. 39), and the CWELCC sentence is generated from
--     centre.cwelcc_enrolled rather than typed by hand.
--   * Acknowledgement is evidence of receipt, per parent per version. A new
--     version resets it; a family who enrols next week appears as outstanding
--     without anyone remembering to add them.
--   * It is never a gate. An unacknowledged handbook is an exception on the
--     supervisor's home page — it never blocks enrolment, attendance, or a
--     record (s. 73's spirit, and §9.14).

-- ── what the jurisdiction requires ──────────────────────────────────────────
create table public.handbook_section_spec (
  id uuid primary key default gen_random_uuid(),
  jurisdiction_code text not null references public.jurisdiction (code),
  key text not null,
  ordinal integer not null,
  title text not null,
  regulation text not null,
  -- what a complete answer contains, shown beside the editor
  guidance text not null,
  -- when the product already holds this fact, name where; publish reads it
  -- from there instead of trusting typed prose
  sourced_from text check (sourced_from in ('centre.anaphylaxis_policy', 'centre.cwelcc_enrolled')),
  unique (jurisdiction_code, key)
);

-- s. 45(1), in the order a parent reads them.
insert into public.handbook_section_spec (jurisdiction_code, key, ordinal, title, regulation, guidance, sourced_from) values
  ('CA-ON', 'services_and_age_groups', 1, 'Services and age groups',
   'O. Reg. 137/15 s. 45(1)',
   'The programs offered, the age groups served, and the rooms children move through.', null),
  ('CA-ON', 'hours_and_holidays', 2, 'Hours of operation and holiday closures',
   'O. Reg. 137/15 s. 45(1)',
   'Daily opening and closing times, and every day the centre is closed in the year.', null),
  ('CA-ON', 'fees', 3, 'Base fee and non-base fees',
   'O. Reg. 137/15 s. 45(1)',
   'The daily base fee per age group, and every non-base fee with what it is for.', null),
  ('CA-ON', 'cwelcc', 4, 'CWELCC enrolment',
   'O. Reg. 137/15 s. 45(1); CWELCC guidelines',
   'Whether the licensee participates in the Canada-Wide Early Learning and Child Care system. The first line is written from the centre record and cannot be contradicted here.',
   'centre.cwelcc_enrolled'),
  ('CA-ON', 'admission_and_discharge', 5, 'Admission and discharge policy',
   'O. Reg. 137/15 s. 45(1)',
   'How a child is admitted, the notice period on each side, and the circumstances in which a child is discharged.', null),
  ('CA-ON', 'off_premises', 6, 'Off-premises activities',
   'O. Reg. 137/15 s. 45(1)',
   'Walks, trips and how parents are told about them; supervision and attendance off site.', null),
  ('CA-ON', 'volunteers_and_students', 7, 'Supervision of volunteers and students',
   'O. Reg. 137/15 s. 45(1); s. 11(3)',
   'Volunteers and students are never left alone with children and are never counted in ratios — say so plainly.', null),
  ('CA-ON', 'payment', 8, 'Payment methods and schedule',
   'O. Reg. 137/15 s. 45(1)',
   'How and when fees are paid, and what happens when a payment is late.', null),
  ('CA-ON', 'refunds', 9, 'Refunds',
   'O. Reg. 137/15 s. 45(1)',
   'The circumstances in which fees are refunded, including absences and closures.', null),
  ('CA-ON', 'safe_arrival_and_dismissal', 10, 'Safe arrival and dismissal policy',
   'O. Reg. 137/15 s. 45(1); s. 50',
   'Who may collect a child, how identity is confirmed, what happens when a child is expected and does not arrive, late pickup, and when no authorised person is available.', null),
  ('CA-ON', 'waiting_list', 11, 'Waiting list policy',
   'O. Reg. 137/15 s. 45(1); s. 75.1',
   'The order children are admitted in, and how a family learns its position. No fee or deposit may be charged for a place on the list.', null),
  ('CA-ON', 'anaphylaxis', 12, 'Anaphylaxis policy',
   'O. Reg. 137/15 s. 45(1); s. 39',
   'The centre anaphylaxis policy. This is the live policy from Plans & allergies — edit it there and it changes here.',
   'centre.anaphylaxis_policy'),
  ('CA-ON', 'issues_and_concerns', 13, 'Parent issues and concerns policy',
   'O. Reg. 137/15 s. 45(1); s. 45.1',
   'Who a parent raises a concern with, the steps that follow, and the timeline for a response.', null),
  ('CA-ON', 'program_statement', 14, 'Program statement',
   'O. Reg. 137/15 s. 45(1); s. 46',
   'The centre program statement, consistent with How Does Learning Happen?, including the prohibited practices.', null);

alter table public.handbook_section_spec enable row level security;
-- Reference data: no personal information, and a centre being able to read the
-- checklist before it has written a word is the point.
create policy handbook_section_spec_select on public.handbook_section_spec for select using (true);

-- ── the working draft ───────────────────────────────────────────────────────
-- Freely editable: this is the desk, not the record. Nothing here is regulated
-- until it is published into a version.
create table public.handbook_content (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  section_key text not null,
  body text not null,
  updated_by uuid not null references public.person (id),
  updated_at timestamptz not null default now(),
  unique (centre_id, section_key)
);

-- ── the published handbook ──────────────────────────────────────────────────
create table public.handbook_version (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  version integer not null,
  -- what changed since the last issue, in words a parent understands
  summary text,
  published_at timestamptz not null default now(),
  published_by uuid not null references public.person (id),
  unique (centre_id, version)
);

create table public.handbook_version_section (
  id uuid primary key default gen_random_uuid(),
  handbook_version_id uuid not null references public.handbook_version (id),
  centre_id uuid not null references public.centre (id),
  section_key text not null,
  ordinal integer not null,
  title text not null,
  regulation text not null,
  body text not null,
  unique (handbook_version_id, section_key)
);

-- Evidence the parent was given it (s. 45): named, timestamped, per version.
create table public.handbook_acknowledgement (
  id uuid primary key default gen_random_uuid(),
  handbook_version_id uuid not null references public.handbook_version (id),
  centre_id uuid not null references public.centre (id),
  person_id uuid not null references public.person (id),
  method text not null check (method in ('in_app', 'signed_paper')),
  acknowledged_at timestamptz not null default now(),
  -- null for in_app: the parent themselves is the strongest evidence there is
  recorded_by uuid references public.person (id),
  created_at timestamptz not null default now(),
  unique (handbook_version_id, person_id)
);

-- ── visibility ──────────────────────────────────────────────────────────────
alter table public.handbook_content enable row level security;
alter table public.handbook_version enable row level security;
alter table public.handbook_version_section enable row level security;
alter table public.handbook_acknowledgement enable row level security;

-- The draft belongs to the people writing it.
create policy handbook_content_select on public.handbook_content
  for select using (centre_id in (select app.care_centre_ids()));

-- A published handbook is for everyone at the centre — that is what publishing
-- means. Families read it in the app; that IS the copy s. 45 requires.
create policy handbook_version_select on public.handbook_version
  for select using (centre_id in (select app.member_centre_ids()));

create policy handbook_version_section_select on public.handbook_version_section
  for select using (centre_id in (select app.member_centre_ids()));

-- Staff see the centre's acknowledgements (that is the evidence); a parent
-- sees their own.
create policy handbook_acknowledgement_select on public.handbook_acknowledgement
  for select using (
    centre_id in (select app.care_centre_ids())
    or person_id = app.current_person_id()
  );
-- Writes via RPCs only.

create trigger handbook_version_no_delete before delete on public.handbook_version
  for each row execute function app.block_mutation();
create trigger handbook_acknowledgement_no_delete before delete on public.handbook_acknowledgement
  for each row execute function app.block_mutation();
create trigger handbook_version_audit after insert on public.handbook_version
  for each row execute function app.audit_row();
create trigger handbook_acknowledgement_audit after insert on public.handbook_acknowledgement
  for each row execute function app.audit_row();

-- A published version is the artefact a parent acknowledged. It never moves.
create or replace function app.handbook_published_is_immutable()
returns trigger
language plpgsql
as $$
begin
  raise exception 'a published handbook is never edited — publish a new version instead';
end;
$$;

create trigger handbook_version_immutable
  before update on public.handbook_version
  for each row execute function app.handbook_published_is_immutable();
create trigger handbook_version_section_immutable
  before update or delete on public.handbook_version_section
  for each row execute function app.handbook_published_is_immutable();

-- ── who still needs it ──────────────────────────────────────────────────────
-- Every consenting adult of every enrolled child who has not acknowledged the
-- current version. New family next week? They appear here on their own.
create view public.handbook_outstanding
with (security_invoker = on) as
select distinct
  v.centre_id,
  v.id as handbook_version_id,
  v.version,
  hm.person_id,
  p.full_name
from public.handbook_version v
join public.child ch on ch.centre_id = v.centre_id and ch.discharge_date is null
join public.child_household chh on chh.child_id = ch.id
join public.household_member hm
  on hm.household_id = chh.household_id and hm.revoked_at is null and hm.can_consent
join public.person p on p.id = hm.person_id
where v.version = (
    select max(v2.version) from public.handbook_version v2 where v2.centre_id = v.centre_id
  )
  and not exists (
    select 1 from public.handbook_acknowledgement a
    where a.handbook_version_id = v.id and a.person_id = hm.person_id
  );

-- ── RPCs ────────────────────────────────────────────────────────────────────
-- Save a draft section. Sourced sections are read from their live home, so
-- there is nothing to type here and typing is refused rather than silently
-- discarded.
create or replace function public.save_handbook_section(
  p_centre uuid,
  p_key text,
  p_body text,
  p_recorder uuid,
  p_pin text
) returns public.handbook_content
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  spec public.handbook_section_spec;
  result public.handbook_content;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);

  select s.* into spec
  from public.handbook_section_spec s
  join public.centre c on c.jurisdiction_code = s.jurisdiction_code
  where c.id = p_centre and s.key = p_key;
  if spec.id is null then
    raise exception 'the handbook has no section "%" in this jurisdiction', p_key;
  end if;
  if spec.sourced_from = 'centre.anaphylaxis_policy' then
    raise exception 'the anaphylaxis policy is edited on Plans & allergies — the handbook reads it from there';
  end if;
  if coalesce(trim(p_body), '') = '' then
    raise exception 'a handbook section is never blank — s. 45 requires this content';
  end if;

  insert into public.handbook_content (centre_id, section_key, body, updated_by)
  values (p_centre, p_key, trim(p_body), recorder)
  on conflict (centre_id, section_key)
    do update set body = excluded.body, updated_by = excluded.updated_by, updated_at = now()
  returning * into result;
  return result;
end;
$$;

-- The body a section would publish with: the live record where one exists,
-- otherwise the centre's draft.
create or replace function app.handbook_section_body(p_centre uuid, p_key text)
returns text
language plpgsql stable security definer
set search_path = public
as $$
declare
  spec public.handbook_section_spec;
  ctr public.centre;
  draft text;
begin
  select s.* into spec
  from public.handbook_section_spec s
  join public.centre c on c.jurisdiction_code = s.jurisdiction_code
  where c.id = p_centre and s.key = p_key;
  select * into ctr from public.centre where id = p_centre;
  select body into draft from public.handbook_content where centre_id = p_centre and section_key = p_key;

  if spec.sourced_from = 'centre.anaphylaxis_policy' then
    return nullif(trim(coalesce(ctr.anaphylaxis_policy, '')), '');
  elsif spec.sourced_from = 'centre.cwelcc_enrolled' then
    -- The factual line is generated, so the handbook cannot claim an
    -- enrolment status the centre record does not hold.
    return case when ctr.cwelcc_enrolled
             then ctr.name || ' participates in the Canada-Wide Early Learning and Child Care ' ||
                  '(CWELCC) system. Base fees for eligible children are capped accordingly.'
             else ctr.name || ' does not participate in the Canada-Wide Early Learning and Child Care ' ||
                  '(CWELCC) system.'
           end
           || coalesce(E'\n\n' || nullif(trim(coalesce(draft, '')), ''), '');
  end if;
  return nullif(trim(coalesce(draft, '')), '');
end;
$$;

-- What is still missing before this handbook can be issued.
create or replace function public.handbook_missing_sections(p_centre uuid)
returns table (key text, title text, regulation text)
language sql stable security definer
set search_path = public
as $$
  select s.key, s.title, s.regulation
  from public.handbook_section_spec s
  join public.centre c on c.jurisdiction_code = s.jurisdiction_code
  where c.id = p_centre
    and coalesce(trim(app.handbook_section_body(p_centre, s.key)), '') = ''
  order by s.ordinal
$$;

-- Issue the handbook. Leadership only: it is the licensee's document.
create or replace function public.publish_handbook(
  p_centre uuid,
  p_summary text,
  p_recorder uuid,
  p_pin text
) returns public.handbook_version
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  missing text;
  next_version integer;
  previous public.handbook_version;
  unchanged boolean;
  result public.handbook_version;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate')
  ) then
    raise exception 'only centre leadership issues the parent handbook';
  end if;

  -- s. 45: every required section, or no handbook.
  select string_agg(title, ', ' order by key) into missing
  from public.handbook_missing_sections(p_centre);
  if missing is not null then
    raise exception 's. 45 requires every section before the handbook is issued — still missing: %', missing;
  end if;

  select * into previous
  from public.handbook_version where centre_id = p_centre
  order by version desc limit 1;

  if previous.id is not null then
    -- Re-issuing an identical handbook would ask every family to acknowledge
    -- a document they already have.
    select not exists (
      select s.key, app.handbook_section_body(p_centre, s.key) as body
      from public.handbook_section_spec s
      join public.centre c on c.jurisdiction_code = s.jurisdiction_code
      where c.id = p_centre
      except
      select vs.section_key, vs.body
      from public.handbook_version_section vs
      where vs.handbook_version_id = previous.id
    ) and not exists (
      select vs.section_key, vs.body
      from public.handbook_version_section vs
      where vs.handbook_version_id = previous.id
      except
      select s.key, app.handbook_section_body(p_centre, s.key)
      from public.handbook_section_spec s
      join public.centre c on c.jurisdiction_code = s.jurisdiction_code
      where c.id = p_centre
    ) into unchanged;
    if unchanged then
      raise exception 'nothing has changed since version % — there is no new handbook to issue', previous.version;
    end if;
    if coalesce(trim(coalesce(p_summary, '')), '') = '' then
      raise exception 'say what changed — every family is being asked to read this again';
    end if;
  end if;

  next_version := coalesce(previous.version, 0) + 1;

  insert into public.handbook_version (centre_id, version, summary, published_by)
  values (p_centre, next_version, nullif(trim(coalesce(p_summary, '')), ''), recorder)
  returning * into result;

  insert into public.handbook_version_section (
    handbook_version_id, centre_id, section_key, ordinal, title, regulation, body
  )
  select result.id, p_centre, s.key, s.ordinal, s.title, s.regulation,
         app.handbook_section_body(p_centre, s.key)
  from public.handbook_section_spec s
  join public.centre c on c.jurisdiction_code = s.jurisdiction_code
  where c.id = p_centre;

  -- Quiet, not urgent: the handbook belongs in the Later feed, and it asks to
  -- be acknowledged so the centre can show it was given.
  insert into public.notification (
    centre_id, recipient_person_id, channel, event_type, title, body,
    requires_acknowledgement, created_by, ref_id
  )
  select distinct
    p_centre, hm.person_id, 'later'::public.notification_channel, 'handbook_issued',
    case when next_version = 1
      then 'The parent handbook'
      else 'The parent handbook has been updated' end,
    coalesce(result.summary, 'Everything the centre asks you to know, in one place.') ||
      ' Please read it and let us know you have.',
    true, recorder, result.id
  from public.child ch
  join public.child_household chh on chh.child_id = ch.id
  join public.household_member hm
    on hm.household_id = chh.household_id and hm.revoked_at is null and hm.can_consent
  where ch.centre_id = p_centre and ch.discharge_date is null;

  return result;
end;
$$;

-- A parent says they have it. The strongest evidence: named, timestamped, and
-- made by the parent themselves.
create or replace function public.acknowledge_handbook(p_version uuid)
returns public.handbook_acknowledgement
language plpgsql security definer
set search_path = public
as $$
declare
  v public.handbook_version;
  me uuid;
  result public.handbook_acknowledgement;
begin
  select * into v from public.handbook_version where id = p_version;
  if v.id is null then raise exception 'handbook not found'; end if;
  me := app.current_person_id();
  if me is null or not exists (
    select 1 from public.child ch
    join public.child_household chh on chh.child_id = ch.id
    join public.household_member hm on hm.household_id = chh.household_id
    where ch.centre_id = v.centre_id and hm.person_id = me
      and hm.revoked_at is null and hm.can_consent
  ) then
    raise exception 'only a consenting household adult can acknowledge the handbook';
  end if;

  insert into public.handbook_acknowledgement (
    handbook_version_id, centre_id, person_id, method
  ) values (p_version, v.centre_id, me, 'in_app')
  on conflict (handbook_version_id, person_id) do nothing
  returning * into result;

  if result.id is null then
    select * into result from public.handbook_acknowledgement
    where handbook_version_id = p_version and person_id = me;
  end if;

  update public.notification
  set acknowledged_at = now()
  where ref_id = p_version and recipient_person_id = me and acknowledged_at is null;

  return result;
end;
$$;

-- Staff record a signed paper copy, for families who do not use the app.
create or replace function public.record_handbook_acknowledgement(
  p_version uuid,
  p_parent uuid,
  p_acknowledged_at timestamptz,
  p_recorder uuid,
  p_pin text
) returns public.handbook_acknowledgement
language plpgsql security definer
set search_path = public
as $$
declare
  v public.handbook_version;
  recorder uuid;
  result public.handbook_acknowledgement;
begin
  select * into v from public.handbook_version where id = p_version;
  if v.id is null then raise exception 'handbook not found'; end if;
  recorder := app.resolve_recorder(v.centre_id, p_recorder, p_pin);
  if not exists (
    select 1 from public.child ch
    join public.child_household chh on chh.child_id = ch.id
    join public.household_member hm on hm.household_id = chh.household_id
    where ch.centre_id = v.centre_id and hm.person_id = p_parent
      and hm.revoked_at is null and hm.can_consent
  ) then
    raise exception 'the acknowledgement must come from a consenting household member';
  end if;
  if coalesce(p_acknowledged_at, now()) > now() then
    raise exception 'an acknowledgement is recorded when it happens, not ahead of it';
  end if;

  insert into public.handbook_acknowledgement (
    handbook_version_id, centre_id, person_id, method, acknowledged_at, recorded_by
  ) values (
    p_version, v.centre_id, p_parent, 'signed_paper', coalesce(p_acknowledged_at, now()), recorder
  )
  on conflict (handbook_version_id, person_id)
    do nothing
  returning * into result;

  if result.id is null then
    raise exception 'that parent has already acknowledged this handbook';
  end if;

  update public.notification
  set acknowledged_at = now()
  where ref_id = p_version and recipient_person_id = p_parent and acknowledged_at is null;

  return result;
end;
$$;
