-- 0036 policies staff must have read, and the record that they did (s. 46 and
-- the policies ss. 45, 45.1, 57–64 and Part 4 require a centre to hold).
--
-- The gap this closes: a licensee could show an advisor the program statement,
-- and could show them the staff list, and had nothing at all connecting the
-- two. s. 46 requires every employee, student and volunteer to review the
-- program statement and the prohibited practices BEFORE they begin, ANNUALLY,
-- and AGAIN whenever the statement is modified. "We told everyone" is not a
-- record.
--
--   * THE POLICY SET IS JURISDICTION DATA, like the handbook sections and the
--     staff requirements before it, and it names WHO must attest — a
--     volunteer reviews the prohibited practices and the supervision policy,
--     not the medication policy.
--   * A POLICY IS VERSIONED AND IMMUTABLE ONCE PUBLISHED. An attestation is
--     against a VERSION, because "Dara has read the program statement" is
--     worthless if nobody can say which program statement.
--   * MODIFYING THE STATEMENT RESETS EVERYONE. Publishing a new version means
--     every attestation of the old one stops counting — which is the actual
--     wording of s. 46(3), and the thing a centre forgets.
--   * THE PROGRAM STATEMENT FOLLOWS THE HANDBOOK. Its authoritative text is
--     the s. 45 handbook section; issuing a handbook whose program statement
--     has changed publishes a new policy version automatically, so the two
--     can never drift and nobody has to remember.

-- ── what a centre's people must have read ───────────────────────────────────
create table public.policy_spec (
  id uuid primary key default gen_random_uuid(),
  jurisdiction_code text not null references public.jurisdiction (code),
  key text not null,
  label text not null,
  regulation text not null,
  note text not null,
  applies_to public.role_id[] not null,
  -- how often it must be reviewed again; null = only on change
  review_months integer,
  -- where the authoritative text lives, when it is not this table
  sourced_from text check (sourced_from in ('handbook.program_statement')),
  ordinal integer not null,
  unique (jurisdiction_code, key)
);

insert into public.policy_spec
  (jurisdiction_code, key, label, regulation, note, applies_to, review_months, sourced_from, ordinal) values
  ('CA-ON', 'program_statement', 'Program statement', 'O. Reg. 137/15 s. 46',
   'Reviewed before employment or placement begins, at least annually, and again whenever the statement is modified.',
   array['licensee_admin','supervisor','designate','rece','staff','student','volunteer']::public.role_id[],
   12, 'handbook.program_statement', 1),
  ('CA-ON', 'prohibited_practices', 'Prohibited practices', 'O. Reg. 137/15 s. 48',
   'The practices that are never permitted, reviewed on the same cycle as the program statement.',
   array['licensee_admin','supervisor','designate','rece','staff','student','volunteer']::public.role_id[],
   12, null, 2),
  ('CA-ON', 'volunteer_student_supervision', 'Supervision of volunteers and students', 'O. Reg. 137/15 s. 11(3)',
   'Volunteers and students are never left alone with a child and are never counted in ratio.',
   array['licensee_admin','supervisor','designate','rece','staff','student','volunteer']::public.role_id[],
   12, null, 3),
  ('CA-ON', 'police_record_check', 'Police record check policy', 'O. Reg. 137/15 ss. 60–62',
   'How checks are obtained, renewed and held, and what an offence declaration covers.',
   array['licensee_admin','supervisor','designate','rece','staff','student','volunteer']::public.role_id[],
   12, null, 4),
  ('CA-ON', 'staff_training', 'Staff training and development policy', 'O. Reg. 137/15 s. 63',
   'The training every person receives and how it is recorded.',
   array['licensee_admin','supervisor','designate','rece','staff']::public.role_id[],
   12, null, 5),
  ('CA-ON', 'safe_arrival_dismissal', 'Safe arrival and dismissal policy', 'O. Reg. 137/15 s. 50',
   'Who may collect a child, how identity is confirmed, and what happens when nobody comes.',
   array['licensee_admin','supervisor','designate','rece','staff']::public.role_id[],
   12, null, 6),
  ('CA-ON', 'serious_occurrence', 'Serious occurrence policy', 'O. Reg. 137/15 s. 38',
   'What must be reported, to whom, and inside what deadline.',
   array['licensee_admin','supervisor','designate','rece','staff']::public.role_id[],
   12, null, 7),
  ('CA-ON', 'emergency_management', 'Emergency management policy', 'O. Reg. 137/15 s. 68',
   'Evacuation, shelter in place, and where the group goes.',
   array['licensee_admin','supervisor','designate','rece','staff','student','volunteer']::public.role_id[],
   12, null, 8),
  ('CA-ON', 'parent_issues_and_concerns', 'Parent issues and concerns policy', 'O. Reg. 137/15 s. 45.1',
   'Who a parent raises a concern with, and the timeline for a response.',
   array['licensee_admin','supervisor','designate','rece','staff']::public.role_id[],
   12, null, 9);

alter table public.policy_spec enable row level security;
create policy policy_spec_select on public.policy_spec for select using (true);

-- ── the policies themselves, versioned ──────────────────────────────────────
create table public.policy_version (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  policy_key text not null,
  version integer not null,
  body text not null,
  -- what changed, for the people being asked to read it again
  summary text,
  published_at timestamptz not null default now(),
  published_by uuid references public.person (id),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (centre_id, policy_key, version)
);

create index policy_version_live on public.policy_version (centre_id, policy_key)
  where superseded_at is null;

-- The record that a named person read a named version on a named day.
create table public.policy_attestation (
  id uuid primary key default gen_random_uuid(),
  policy_version_id uuid not null references public.policy_version (id),
  centre_id uuid not null references public.centre (id),
  person_id uuid not null references public.person (id),
  method text not null check (method in ('in_app', 'signed_paper')),
  attested_at timestamptz not null default now(),
  -- null for in_app: the person themselves is the strongest evidence there is
  recorded_by uuid references public.person (id),
  created_at timestamptz not null default now(),
  unique (policy_version_id, person_id)
);

create index policy_attestation_person on public.policy_attestation (person_id, attested_at desc);

-- ── rules ───────────────────────────────────────────────────────────────────
create or replace function app.policy_version_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $fn$
begin
  if tg_op = 'INSERT' then
    if coalesce(trim(new.body), '') = '' then
      raise exception 'a policy with no words is not a policy';
    end if;
    if not exists (
      select 1 from public.policy_spec s
      join public.centre c on c.jurisdiction_code = s.jurisdiction_code
      where c.id = new.centre_id and s.key = new.policy_key
    ) then
      raise exception 'there is no policy "%" in this jurisdiction', new.policy_key;
    end if;
  end if;

  if tg_op = 'UPDATE' then
    -- Only the supersede marker moves. A version somebody has attested to is
    -- the version they read, for as long as the record is kept.
    if row(new.centre_id, new.policy_key, new.version, new.body, new.published_at, new.published_by)
       is distinct from
       row(old.centre_id, old.policy_key, old.version, old.body, old.published_at, old.published_by) then
      raise exception 'a published policy is never edited; publish a new version';
    end if;
  end if;
  return new;
end;
$fn$;

create trigger policy_version_rules
  before insert or update on public.policy_version
  for each row execute function app.policy_version_rules();

alter table public.policy_version enable row level security;
alter table public.policy_attestation enable row level security;

-- Everyone at the centre reads the policies — that is the point of them.
create policy policy_version_select on public.policy_version
  for select using (centre_id in (select app.member_centre_ids()));

-- You see your own attestations; leadership sees the centre's, because
-- leadership is who an advisor asks.
create policy policy_attestation_select on public.policy_attestation
  for select using (
    person_id = app.current_person_id()
    or app.has_role(centre_id, array['supervisor', 'designate', 'licensee_admin']::public.role_id[])
  );

create trigger policy_version_no_delete before delete on public.policy_version
  for each row execute function app.block_mutation();
create trigger policy_attestation_no_change before update or delete on public.policy_attestation
  for each row execute function app.block_mutation();
create trigger policy_version_audit after insert or update on public.policy_version
  for each row execute function app.audit_row();
create trigger policy_attestation_audit after insert on public.policy_attestation
  for each row execute function app.audit_row();

-- ── who still owes what ─────────────────────────────────────────────────────
-- For everyone with a workforce role, every policy that applies to their role,
-- and whether they have read the CURRENT version recently enough. Column
-- references are qualified because the RETURNS TABLE names are in scope.
create or replace function public.policy_attestation_gaps(p_centre uuid)
returns table (
  person_id uuid,
  full_name text,
  role public.role_id,
  policy_key text,
  policy_label text,
  regulation text,
  state text,
  version integer,
  attested_at timestamptz
)
language sql stable security definer
set search_path = public
as $fn$
  with workforce as (
    select distinct pr.person_id, pr.role, p.full_name
    from public.person_role pr
    join public.person p on p.id = pr.person_id
    where pr.centre_id = p_centre and pr.active and pr.role <> 'family_adult'
  ),
  needed as (
    select w.person_id, w.full_name, w.role, s.key, s.label, s.regulation,
           s.review_months, s.ordinal
    from workforce w
    join public.policy_spec s on w.role = any (s.applies_to)
    join public.centre c on c.jurisdiction_code = s.jurisdiction_code
    where c.id = p_centre
  ),
  current_version as (
    select v.policy_key, v.id, v.version
    from public.policy_version v
    where v.centre_id = p_centre and v.superseded_at is null
  )
  select
    n.person_id, n.full_name, n.role, n.key, n.label, n.regulation,
    case
      when cv.id is null then 'not_published'
      when a.id is null then 'never_read'
      when n.review_months is not null
        and a.attested_at < now() - make_interval(months => n.review_months) then 'due_again'
      else 'current'
    end,
    cv.version,
    a.attested_at
  from needed n
  left join current_version cv on cv.policy_key = n.key
  left join public.policy_attestation a
    on a.policy_version_id = cv.id and a.person_id = n.person_id
  order by n.full_name, n.ordinal
$fn$;

-- ── RPCs ────────────────────────────────────────────────────────────────────
create or replace function public.publish_policy(
  p_centre uuid,
  p_key text,
  p_body text,
  p_summary text,
  p_recorder uuid,
  p_pin text
) returns public.policy_version
language plpgsql security definer
set search_path = public
as $fn$
declare
  recorder uuid;
  previous public.policy_version;
  result public.policy_version;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate')
  ) then
    raise exception 'the centre''s policies are the licensee''s to publish';
  end if;

  select * into previous from public.policy_version
  where centre_id = p_centre and policy_key = p_key and superseded_at is null;

  if previous.id is not null and trim(previous.body) = trim(p_body) then
    raise exception 'that is word for word the policy already published — nobody needs to read it again';
  end if;

  insert into public.policy_version (centre_id, policy_key, version, body, summary, published_by)
  values (
    p_centre, p_key, coalesce(previous.version, 0) + 1, trim(p_body),
    nullif(trim(coalesce(p_summary, '')), ''), recorder
  ) returning * into result;

  if previous.id is not null then
    update public.policy_version set superseded_at = now() where id = previous.id;
  end if;

  -- s. 46(3): a modified statement is read again by everyone. The Later feed,
  -- not Now — it is important, not urgent.
  insert into public.notification (
    centre_id, recipient_person_id, channel, event_type, title, body,
    requires_acknowledgement, created_by, ref_id
  )
  select distinct
    p_centre, pr.person_id, 'later'::public.notification_channel, 'policy_published',
    (select s.label from public.policy_spec s
     join public.centre c on c.jurisdiction_code = s.jurisdiction_code
     where c.id = p_centre and s.key = p_key)
      || case when previous.id is null then '' else ' has changed' end,
    coalesce(result.summary, 'Please read it and confirm you have.'),
    true, recorder, result.id
  from public.person_role pr
  join public.policy_spec s
    on pr.role = any (s.applies_to) and s.key = p_key
  join public.centre c on c.id = p_centre and c.jurisdiction_code = s.jurisdiction_code
  where pr.centre_id = p_centre and pr.active and pr.role <> 'family_adult';

  return result;
end;
$fn$;

-- The person themselves, which is the only attestation worth much.
create or replace function public.attest_policy(p_version uuid)
returns public.policy_attestation
language plpgsql security definer
set search_path = public
as $fn$
declare
  v public.policy_version;
  me uuid;
  result public.policy_attestation;
begin
  select * into v from public.policy_version where id = p_version;
  if v.id is null then raise exception 'policy not found'; end if;
  me := app.current_person_id();
  if me is null or not exists (
    select 1 from public.person_role pr
    where pr.person_id = me and pr.centre_id = v.centre_id and pr.active
      and pr.role <> 'family_adult'
  ) then
    raise exception 'only somebody working at this centre attests to its policies';
  end if;
  if v.superseded_at is not null then
    raise exception 'that version has been replaced; read the current one';
  end if;

  insert into public.policy_attestation (policy_version_id, centre_id, person_id, method)
  values (p_version, v.centre_id, me, 'in_app')
  on conflict (policy_version_id, person_id) do nothing
  returning * into result;
  if result.id is null then
    select * into result from public.policy_attestation
    where policy_version_id = p_version and person_id = me;
  end if;

  update public.notification set acknowledged_at = now()
  where ref_id = p_version and recipient_person_id = me and acknowledged_at is null;
  return result;
end;
$fn$;

create or replace function public.record_policy_attestation(
  p_version uuid,
  p_person uuid,
  p_attested_at timestamptz,
  p_recorder uuid,
  p_pin text
) returns public.policy_attestation
language plpgsql security definer
set search_path = public
as $fn$
declare
  v public.policy_version;
  recorder uuid;
  result public.policy_attestation;
begin
  select * into v from public.policy_version where id = p_version;
  if v.id is null then raise exception 'policy not found'; end if;
  recorder := app.resolve_recorder(v.centre_id, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = p_person and pr.centre_id = v.centre_id and pr.active
      and pr.role <> 'family_adult'
  ) then
    raise exception 'that person does not work at this centre';
  end if;
  if coalesce(p_attested_at, now()) > now() then
    raise exception 'somebody cannot have read it tomorrow';
  end if;

  insert into public.policy_attestation (
    policy_version_id, centre_id, person_id, method, attested_at, recorded_by
  ) values (p_version, v.centre_id, p_person, 'signed_paper', coalesce(p_attested_at, now()), recorder)
  on conflict (policy_version_id, person_id) do nothing
  returning * into result;
  if result.id is null then
    raise exception 'that is already on their file';
  end if;
  return result;
end;
$fn$;

-- ── the program statement follows the handbook ──────────────────────────────
-- s. 45 makes the handbook's program statement the authoritative text, and
-- s. 46(3) makes a modification the trigger for everyone reading it again. So
-- issuing a handbook whose program statement has changed publishes a new
-- policy version by itself: the two can never drift, and nobody has to
-- remember to do it twice.
create or replace function app.handbook_syncs_program_statement()
returns trigger
language plpgsql security definer
set search_path = public
as $fn$
declare
  hb public.handbook_version;
  current_body text;
  next_version integer;
  new_id uuid;
begin
  if new.section_key <> 'program_statement' then return new; end if;
  if coalesce(trim(coalesce(new.body, '')), '') = '' then return new; end if;

  select * into hb from public.handbook_version where id = new.handbook_version_id;

  select v.body into current_body
  from public.policy_version v
  where v.centre_id = new.centre_id and v.policy_key = 'program_statement'
    and v.superseded_at is null;

  if current_body is not null and trim(current_body) = trim(new.body) then
    return new; -- unchanged: nobody reads it again
  end if;

  select coalesce(max(v.version), 0) + 1 into next_version
  from public.policy_version v
  where v.centre_id = new.centre_id and v.policy_key = 'program_statement';

  update public.policy_version set superseded_at = now()
  where centre_id = new.centre_id and policy_key = 'program_statement' and superseded_at is null;

  insert into public.policy_version (centre_id, policy_key, version, body, summary, published_by)
  values (
    new.centre_id, 'program_statement', next_version, trim(new.body),
    case when current_body is null
      then 'Published with the parent handbook.'
      else 'The program statement changed in handbook version ' || hb.version ||
           '. Everyone reviews it again (s. 46).' end,
    hb.published_by
  ) returning id into new_id;

  insert into public.notification (
    centre_id, recipient_person_id, channel, event_type, title, body,
    requires_acknowledgement, created_by, ref_id
  )
  select distinct
    new.centre_id, pr.person_id, 'later'::public.notification_channel, 'policy_published',
    case when current_body is null then 'Program statement' else 'The program statement has changed' end,
    'Please read it and confirm you have — s. 46 asks everyone to review it when it changes.',
    true, hb.published_by, new_id
  from public.person_role pr
  where pr.centre_id = new.centre_id and pr.active and pr.role <> 'family_adult';

  return new;
end;
$fn$;

-- On the SECTION, not the version: publish_handbook inserts the version row
-- first and its sections after, so a trigger on handbook_version would look
-- for a program statement that did not exist yet.
create trigger handbook_syncs_program_statement
  after insert on public.handbook_version_section
  for each row execute function app.handbook_syncs_program_statement();
