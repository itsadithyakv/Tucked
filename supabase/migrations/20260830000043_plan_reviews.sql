-- 0043 individualised plan reviews, and a correction about what the law asks.
--
-- WHAT THIS REPO SAID, AND WHAT IS TRUE
--   Since 0021 the schema has set review_due_on a year after a parent agrees,
--   the console called it "(annual)", and the references said ss. 39, 39.1 and
--   52 require an annual review. The Child Care Centre Licensing Manual does
--   not say that. s. 52's compliance indicator asks for an UP-TO-DATE
--   individualized support plan; for s. 39.1 the manual's best practice is that
--   the parent handbook tells families how often the centre reviews and updates
--   plans. No fixed frequency appears in the regulation. The interval is the
--   centre's own commitment, so it is now the centre's setting (default 12
--   months), and nothing on screen cites a section for it.
--
-- WHAT WAS MISSING
--   A review that changes nothing had nowhere to go. The only way to move an
--   overdue clock was a new plan version, which supersedes the plan and sends
--   the family an agreement request for words they have already agreed to.
--   Staying up to date is the real duty, and "we went through it with the
--   family on 3 September and nothing has changed" is exactly its evidence.
--
-- WHAT THIS MIGRATION HOLDS
--   individualised_plan_review: one review of one ACTIVE plan version, held
--   with an adult who can consent for the child. Append-only.
--     still_accurate  the clock moves to reviewed_on + the centre's interval.
--                     The plan, its version and its agreement are untouched.
--                     A backdated review never winds the clock back behind a
--                     later one.
--     changes_needed  the clock does NOT move, and the note must say what
--                     changed. The plan is flagged until a new version
--                     supersedes it (which goes to the family to agree, as it
--                     always has) or a later review finds it accurate after all.
--   Two ways a review happens, and the record says which:
--     staff record one held in person, by phone or on signed paper (PIN);
--     staff ask in the app, and a consenting adult answers for the family.
--   plan_reviews_due(centre) reads the clock in the CENTRE's calendar: changes
--   waiting on a new version, overdue, or due within 30 days.
--
-- ALSO FIXED
--   Both agreement RPCs started the clock from current_date, the database's UTC
--   date, which is already tomorrow from 8 p.m. in a Toronto summer. A signed
--   paper recorded with an earlier agreed date also started its year from the
--   day it was typed in rather than the day it was signed, and a signed paper
--   could be dated in the future. The clock now counts from the centre-local
--   day of the agreement, and a future agreement date is refused.

-- ── the centre's own schedule ───────────────────────────────────────────────
alter table public.centre
  add column plan_review_months integer not null default 12
    constraint plan_review_months_sane check (plan_review_months between 1 and 24);

comment on column public.centre.plan_review_months is
  'How often this centre reviews each individualised plan with the family: its own commitment, told to families in the handbook. The regulation sets no fixed frequency.';

-- The centre's calendar day for an instant. Every date column in this schema
-- is centre-local; current_date is UTC's.
create or replace function app.centre_date(p_centre uuid, p_at timestamptz)
returns date
language sql stable security definer
set search_path = public
as $$
  select (p_at at time zone c.timezone)::date from public.centre c where c.id = p_centre
$$;

create or replace function app.next_plan_review(p_centre uuid, p_from date)
returns date
language sql stable security definer
set search_path = public
as $$
  select (p_from + make_interval(months => c.plan_review_months))::date
  from public.centre c where c.id = p_centre
$$;

-- ── reviews ─────────────────────────────────────────────────────────────────
create table public.individualised_plan_review (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  plan_id uuid not null references public.individualised_plan (id),
  reviewed_on date not null,
  outcome text not null check (outcome in ('still_accurate', 'changes_needed')),
  -- the adult from the family the plan was gone through with
  reviewed_with uuid not null references public.person (id),
  method text not null check (method in ('in_app', 'in_person', 'phone', 'signed_paper')),
  note text check (note is null or length(note) <= 1000),
  -- set by the rules below, never by a caller
  next_review_on date,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default clock_timestamp(),
  constraint plan_review_clock_follows_outcome
    check ((outcome = 'still_accurate') = (next_review_on is not null)),
  constraint plan_review_changes_are_described
    check (outcome <> 'changes_needed' or length(trim(coalesce(note, ''))) > 0)
);

create index individualised_plan_review_plan
  on public.individualised_plan_review (plan_id, reviewed_on desc, created_at desc);

create or replace function app.plan_review_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  plan public.individualised_plan;
begin
  if tg_op = 'UPDATE' then
    -- s. 72(5): the retention anonymiser is the one thing allowed to rewrite
    if app.is_anonymising() then
      return new;
    end if;
    raise exception 'a plan review is never edited; record another review';
  end if;

  select * into plan from public.individualised_plan where id = new.plan_id;
  if plan.id is null then
    raise exception 'plan not found';
  end if;
  if new.child_id <> plan.child_id or new.centre_id <> plan.centre_id then
    raise exception 'a review belongs to its plan''s own child and centre';
  end if;
  if plan.status = 'draft' then
    raise exception 'this plan is still awaiting agreement; a plan is reviewed once it is in practice';
  end if;
  if plan.status <> 'active' then
    raise exception 'this plan version is no longer in practice; review the current one';
  end if;

  if new.reviewed_on > app.centre_date(plan.centre_id, now()) then
    raise exception 'a review is recorded once it has happened; % is in the future', new.reviewed_on;
  end if;
  if new.reviewed_on < app.centre_date(plan.centre_id, plan.parent_agreed_at) then
    raise exception 'a review cannot come before the agreement it reviews';
  end if;
  if not app.is_consenting_member(new.reviewed_with, plan.child_id) then
    raise exception 'a plan is reviewed with an adult who can consent for this child';
  end if;
  if new.outcome = 'changes_needed' and coalesce(trim(new.note), '') = '' then
    raise exception 'say what has changed; the next version is written from it';
  end if;

  new.next_review_on := case
    when new.outcome = 'still_accurate' then app.next_plan_review(plan.centre_id, new.reviewed_on)
  end;
  return new;
end;
$$;

create trigger individualised_plan_review_rules
  before insert or update on public.individualised_plan_review
  for each row execute function app.plan_review_rules();

-- An accurate plan's clock follows its latest review, never an earlier one.
create or replace function app.plan_review_moves_clock()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.outcome = 'still_accurate' then
    update public.individualised_plan p
    set review_due_on = new.next_review_on
    where p.id = new.plan_id
      and not exists (
        select 1 from public.individualised_plan_review r
        where r.plan_id = new.plan_id
          and r.id <> new.id
          and r.outcome = 'still_accurate'
          and r.reviewed_on > new.reviewed_on
      );
  end if;
  return null;
end;
$$;

create trigger individualised_plan_review_moves_clock
  after insert on public.individualised_plan_review
  for each row execute function app.plan_review_moves_clock();

create trigger individualised_plan_review_no_delete before delete on public.individualised_plan_review
  for each row execute function app.block_mutation();
create trigger individualised_plan_review_audit after insert or update on public.individualised_plan_review
  for each row execute function app.audit_row();

alter table public.individualised_plan_review enable row level security;

-- the same people who can read the plan
create policy individualised_plan_review_select on public.individualised_plan_review
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = individualised_plan_review.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
-- Writes via RPCs only.

-- ── staff record a review held with the family ──────────────────────────────
create or replace function public.record_plan_review(
  p_plan uuid,
  p_reviewed_with uuid,
  p_reviewed_on date,
  p_method text,
  p_outcome text,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns public.individualised_plan_review
language plpgsql security definer
set search_path = public
as $$
declare
  plan public.individualised_plan;
  recorder uuid;
  result public.individualised_plan_review;
begin
  select * into plan from public.individualised_plan where id = p_plan;
  if plan.id is null then raise exception 'plan not found'; end if;
  recorder := app.resolve_recorder(plan.centre_id, p_recorder, p_pin);
  if coalesce(p_method, '') not in ('in_person', 'phone', 'signed_paper') then
    raise exception 'staff record a review held in person, by phone or on signed paper; in the app, the family answers for themselves';
  end if;

  insert into public.individualised_plan_review (
    centre_id, child_id, plan_id, reviewed_on, outcome, reviewed_with, method, note, recorded_by
  ) values (
    plan.centre_id, plan.child_id, plan.id,
    coalesce(p_reviewed_on, app.centre_date(plan.centre_id, now())),
    p_outcome, p_reviewed_with, p_method, nullif(trim(coalesce(p_note, '')), ''), recorder
  ) returning * into result;
  return result;
end;
$$;

-- ── or ask the family in the app ────────────────────────────────────────────
-- Returns how many adults were newly asked; someone already asked and not yet
-- answered is not asked again.
create or replace function public.request_plan_review(
  p_plan uuid,
  p_recorder uuid,
  p_pin text
) returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  plan public.individualised_plan;
  recorder uuid;
  asked integer;
begin
  select * into plan from public.individualised_plan where id = p_plan;
  if plan.id is null then raise exception 'plan not found'; end if;
  recorder := app.resolve_recorder(plan.centre_id, p_recorder, p_pin);
  if plan.status <> 'active' then
    raise exception 'only a plan in practice is reviewed; a draft is still awaiting agreement';
  end if;

  insert into public.notification (
    centre_id, child_id, recipient_person_id, channel, event_type, title, body,
    requires_acknowledgement, created_by, ref_id
  )
  select distinct
    plan.centre_id, plan.child_id, hm.person_id, 'now'::public.notification_channel, 'plan_review',
    'Is ' || split_part(ch.full_name, ' ', 1) || '''s ' || replace(plan.plan_type, '_', ' ') || ' plan still right?',
    'The centre is reviewing the plan. Read it through and tell them whether anything has changed.',
    true, recorder, plan.id
  from public.child ch
  join public.child_household chh on chh.child_id = ch.id
  join public.household_member hm on hm.household_id = chh.household_id
  where ch.id = plan.child_id
    and hm.revoked_at is null
    and hm.can_consent
    and not exists (
      select 1 from public.notification n
      where n.ref_id = plan.id
        and n.event_type = 'plan_review'
        and n.recipient_person_id = hm.person_id
        and n.acknowledged_at is null
    );
  get diagnostics asked = row_count;

  if asked = 0 and not exists (
    select 1 from public.child_household chh
    join public.household_member hm on hm.household_id = chh.household_id
    where chh.child_id = plan.child_id and hm.revoked_at is null and hm.can_consent
  ) then
    raise exception 'nobody in this family can consent in the app; record a review held in person instead';
  end if;
  return asked;
end;
$$;

create or replace function public.answer_plan_review(
  p_plan uuid,
  p_still_accurate boolean,
  p_note text default null
) returns public.individualised_plan_review
language plpgsql security definer
set search_path = public
as $$
declare
  plan public.individualised_plan;
  me uuid := app.current_person_id();
  result public.individualised_plan_review;
begin
  select * into plan from public.individualised_plan where id = p_plan;
  if plan.id is null then raise exception 'plan not found'; end if;
  if me is null or not app.is_consenting_member(me, plan.child_id) then
    raise exception 'only an adult who can consent for this child can answer for the family'
      using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.notification n
    where n.ref_id = plan.id and n.event_type = 'plan_review' and n.recipient_person_id = me
  ) then
    raise exception 'the centre has not asked you to review this plan';
  end if;
  if p_still_accurate is null then
    raise exception 'say whether the plan is still right';
  end if;

  insert into public.individualised_plan_review (
    centre_id, child_id, plan_id, reviewed_on, outcome, reviewed_with, method, note, recorded_by
  ) values (
    plan.centre_id, plan.child_id, plan.id, app.centre_date(plan.centre_id, now()),
    case when p_still_accurate then 'still_accurate' else 'changes_needed' end,
    me, 'in_app', nullif(trim(coalesce(p_note, '')), ''), me
  ) returning * into result;

  update public.notification
  set acknowledged_at = now(), delivered_at = coalesce(delivered_at, now())
  where ref_id = plan.id
    and event_type = 'plan_review'
    and recipient_person_id = me
    and acknowledged_at is null;

  return result;
end;
$$;

-- ── what needs a review ─────────────────────────────────────────────────────
-- Care staff only; anyone else gets an empty list. Every column is qualified:
-- the RETURNS TABLE names are in scope here too.
create or replace function public.plan_reviews_due(p_centre uuid)
returns table (
  plan_id uuid,
  child_id uuid,
  full_name text,
  plan_type text,
  version integer,
  review_due_on date,
  state text,
  last_reviewed_on date,
  last_note text
)
language sql stable security definer
set search_path = public
as $$
  with live as (
    select p.id, p.child_id, p.plan_type, p.version, p.review_due_on,
           app.centre_date(p.centre_id, now()) as today
    from public.individualised_plan p
    where p.centre_id = p_centre
      and p.status = 'active'
      and p_centre in (select app.care_centre_ids())
  ),
  latest as (
    select distinct on (r.plan_id) r.plan_id, r.reviewed_on, r.outcome, r.note
    from public.individualised_plan_review r
    join live l on l.id = r.plan_id
    order by r.plan_id, r.reviewed_on desc, r.created_at desc
  ),
  judged as (
    select
      l.id, l.child_id, ch.full_name, l.plan_type, l.version, l.review_due_on,
      case
        when lt.outcome = 'changes_needed' then 'changes_needed'
        when l.review_due_on < l.today then 'overdue'
        when l.review_due_on <= l.today + 30 then 'due_soon'
      end as state,
      lt.reviewed_on, lt.note
    from live l
    join public.child ch on ch.id = l.child_id
    left join latest lt on lt.plan_id = l.id
  )
  select j.id, j.child_id, j.full_name, j.plan_type, j.version, j.review_due_on,
         j.state, j.reviewed_on, j.note
  from judged j
  where j.state is not null
  order by case j.state when 'changes_needed' then 1 when 'overdue' then 2 else 3 end,
           j.review_due_on
$$;

-- -- replaced: public.agree_individualised_plan (from 20260830000021_individualised_plans.sql) --
-- Copied from the live definition by a generator and edited only where
-- this migration says; every other line is what 20260830000021 left.
create or replace function public.agree_individualised_plan(p_plan uuid)
returns public.individualised_plan
language plpgsql security definer
set search_path = public
as $$
declare
  plan public.individualised_plan;
  me uuid;
begin
  select * into plan from public.individualised_plan where id = p_plan;
  if plan.id is null then raise exception 'plan not found'; end if;
  me := app.current_person_id();
  if me is null or not exists (
    select 1 from public.child_household ch
    join public.household_member hm on hm.household_id = ch.household_id
    where ch.child_id = plan.child_id
      and hm.person_id = me and hm.revoked_at is null and hm.can_consent
  ) then
    raise exception 'only a consenting household adult can agree to this plan';
  end if;
  if plan.status <> 'draft' then
    raise exception 'this plan version is not awaiting agreement';
  end if;

  update public.individualised_plan
  set status = 'active', parent_agreed_at = now(), parent_agreed_by = me,
      agreement_method = 'in_app',
      review_due_on = app.next_plan_review(plan.centre_id, app.centre_date(plan.centre_id, now()))
  where id = p_plan
  returning * into plan;

  update public.notification
  set acknowledged_at = now()
  where ref_id = p_plan and recipient_person_id = me and acknowledged_at is null;

  return plan;
end;
$$;

-- -- replaced: public.record_plan_agreement (from 20260830000021_individualised_plans.sql) --
-- Copied from the live definition by a generator and edited only where
-- this migration says; every other line is what 20260830000021 left.
create or replace function public.record_plan_agreement(
  p_plan uuid,
  p_parent uuid,
  p_agreed_at timestamptz,
  p_recorder uuid,
  p_pin text
) returns public.individualised_plan
language plpgsql security definer
set search_path = public
as $$
declare
  plan public.individualised_plan;
  recorder uuid;
begin
  select * into plan from public.individualised_plan where id = p_plan;
  if plan.id is null then raise exception 'plan not found'; end if;
  recorder := app.resolve_recorder(plan.centre_id, p_recorder, p_pin);
  if not exists (
    select 1 from public.child_household ch
    join public.household_member hm on hm.household_id = ch.household_id
    where ch.child_id = plan.child_id
      and hm.person_id = p_parent and hm.revoked_at is null and hm.can_consent
  ) then
    raise exception 'the agreement must come from a consenting household member';
  end if;
  if plan.status <> 'draft' then
    raise exception 'this plan version is not awaiting agreement';
  end if;
  if p_agreed_at > now() then
    raise exception 'an agreement is recorded once it has been signed — that date is in the future';
  end if;

  update public.individualised_plan
  set status = 'active', parent_agreed_at = coalesce(p_agreed_at, now()),
      parent_agreed_by = p_parent, agreement_method = 'signed_paper',
      review_due_on = app.next_plan_review(plan.centre_id, app.centre_date(plan.centre_id, coalesce(p_agreed_at, now())))
  where id = p_plan
  returning * into plan;
  return plan;
end;
$$;

-- -- replaced: app.anonymise_child (from 20260830000042_child_record_documents.sql) --
-- Copied from the live definition by a generator and edited only where
-- this migration says; every other line is what 20260830000042 left.
create or replace function app.anonymise_child(p_child uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  ch public.child;
  clock public.retention_clock;
  token text;
begin
  select * into ch from public.child where id = p_child;
  if ch.id is null then raise exception 'child not found'; end if;
  if ch.discharge_date is null then
    raise exception 'never: this child is not discharged — no retention clock is running';
  end if;

  select * into clock from public.retention_clock
  where subject_table = 'child' and subject_id = p_child::text and kind = 'childrens_record';
  if clock.id is null then
    raise exception 'never: no retention clock exists for this child';
  end if;
  if clock.purge_after > current_date then
    raise exception 'never: the retention period has not ended (kept until %)', clock.purge_after;
  end if;
  if clock.anonymised_at is not null then
    return; -- already done; idempotent
  end if;

  -- the flag the immutability triggers honour, for this transaction only
  perform set_config('app.anonymising', 'on', true);
  token := 'Anonymised child ' || left(p_child::text, 8);

  update public.child
  set full_name = token,
      date_of_birth = make_date(extract(year from date_of_birth)::int, 1, 1),
      photo_path = null
  where id = p_child;

  -- the s. 72(1) items hold parents' names, addresses, phones — gone
  update public.child_record_item
  set content = '{"anonymised": true}'::jsonb
  where child_id = p_child;

  -- free text out of care logs; structured facts (meal, minutes…) survive
  update public.care_log
  set payload = (payload - 'note' - 'text' - 'observation' - 'description' - 'parent_report')
                || '{"anonymised": true}'::jsonb
  where child_id = p_child
    and payload ?| array['note', 'text', 'observation', 'description', 'parent_report'];

  update public.accident_report
  set description = '[anonymised]', injury = '[anonymised]', first_aid = '[anonymised]',
      concussion_watch_note = case when concussion_watch_note is null then null else '[anonymised]' end
  where child_id = p_child;

  update public.individualised_plan
  set condition = '[anonymised]', allergens = '{}',
      signs = case when signs is null then null else '[anonymised]' end,
      emergency_procedure = case when emergency_procedure is null then null else '[anonymised]' end,
      exposure_reduction = case when exposure_reduction is null then null else '[anonymised]' end,
      devices_instructions = case when devices_instructions is null then null else '[anonymised]' end,
      supports = case when supports is null then null else '[anonymised]' end,
      evacuation_procedure = case when evacuation_procedure is null then null else '[anonymised]' end,
      developed_with = '[anonymised]' -- names the parents
  where child_id = p_child;

  update public.dietary_restriction set note = null where child_id = p_child;

  update public.story
  set draft_text = '[anonymised]',
      educator_note = case when educator_note is null then null else '[anonymised]' end
  where child_id = p_child;

  update public.notification
  set title = '[anonymised]', body = '[anonymised]'
  where child_id = p_child;

  -- face-to-name snapshots in headcounts carry the name; keep the count
  update public.headcount_check hc
  set missing = (
    select coalesce(jsonb_agg(
      case when m ->> 'child_id' = p_child::text
        then jsonb_set(m, '{full_name}', to_jsonb(token))
        else m end), '[]'::jsonb)
    from jsonb_array_elements(hc.missing) m
  )
  where hc.missing @> jsonb_build_array(jsonb_build_object('child_id', p_child::text));

  -- Photos leave entirely: the profile photo, and every gallery photo this
  -- child is in. A GROUP photo goes too, whole. Other families lose that
  -- picture, and the discharged child's face does not outlive their record —
  -- which is the side of that trade s. 72(5) is on. (0041 replaced the 0022
  -- delete, which matched gallery paths by child id and so would have missed
  -- every photo stored under photos/{centre}/p/{photo}/.)
  update public.photo p
  set withdrawn_at = clock_timestamp(),
      withdrawn_reason = 'retention: a child in this photo was anonymised (s. 72(5))'
  where p.withdrawn_at is null
    and exists (
      select 1 from public.photo_subject s where s.photo_id = p.id and s.child_id = p_child
    );

  -- the storage guard against accidental SQL deletes recognises the same
  -- explicit-intent pattern
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects
  where bucket_id = 'photos'
    and (
      split_part(name, '/', 2) = p_child::text
      or (
        split_part(name, '/', 2) = 'p'
        and app.path_uuid(name, 3) in (
          select s.photo_id from public.photo_subject s where s.child_id = p_child
        )
      )
    );
  perform set_config('storage.allow_delete_query', 'false', true);

  -- s. 72(1) documents (0042). The files go; the row that says a document
  -- existed survives and keeps no name — a scanned application carries the
  -- child's and the parents' names in its file name as often as in its pages.
  update public.child_record_document
  set file_name = '[anonymised]',
      note = case when note is null then null else '[anonymised]' end
  where child_id = p_child;

  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects
  where bucket_id = 'evidence'
    and split_part(name, '/', 2) = 'child'
    and app.path_uuid(name, 3) = p_child;
  perform set_config('storage.allow_delete_query', 'false', true);

  -- plan reviews (0043): the note says what changed about a child's health,
  -- and usually who said so. The rows that say a review happened survive.
  update public.individualised_plan_review
  set note = case when note is null then null else '[anonymised]' end
  where child_id = p_child;

  update public.retention_clock
  set anonymised_at = now()
  where subject_id = p_child::text and subject_table in ('child', 'attendance_event');

  insert into public.audit_event (centre_id, table_name, row_id, action, summary)
  values (ch.centre_id, 'retention_clock', p_child::text, 'update',
          jsonb_build_object('action', 'anonymised', 'kind', 'childrens_record',
                             'purge_after', clock.purge_after));

  -- close the hatch immediately — not at transaction end
  perform set_config('app.anonymising', '', true);
end;
$$;
