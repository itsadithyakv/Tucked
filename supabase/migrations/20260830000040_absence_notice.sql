-- 0040 a family can say "not today" or "running late" before anybody phones.
--
-- Playground, Brightwheel and Procare all have this, and the reason is plain.
-- Without it, s. 50 safe arrival works like this: at the cutoff the room lists
-- every expected child who has not arrived, and an educator phones each family
-- — at work, mid-meeting — to learn that Maya has a cold, which her mother
-- knew at 6 a.m. That is neither calm for parents nor boring for operators.
--
-- WHAT A NOTICE IS, AND IS NOT.
--
-- It is NOT attendance. s. 72(3) is the legal register — arrivals, departures,
-- absences, actual times — and it stays staff-recorded, PIN-signed, exactly as
-- before. A family cannot write to it and this migration does not let them.
--
-- It IS the explanation s. 50 asks a centre to go and get. A child the family
-- has already accounted for is not an unexplained absence, so the room device
-- can stop treating them as one. HOW MUCH the chase list should trust a notice
-- — especially "running late", which is exactly the case where something might
-- be wrong — is decided in packages/domain/src/safeArrival.ts, beside the rest
-- of the timing logic the room device runs offline.
--
-- Quiet by default: a notice pushes to nobody. It appears on the room board.

create table public.absence_notice (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  -- the centre-local day the notice is about
  notice_date date not null,
  kind text not null check (kind in ('absent', 'late')),
  -- for 'late': roughly when the family expects to arrive, centre-local
  expected_at time,
  -- Optional, and short. A family owes the centre no diagnosis to keep a child
  -- home; "unwell" is a complete answer.
  reason text,
  given_by uuid not null references public.person (id),
  given_at timestamptz not null default clock_timestamp(),
  withdrawn_at timestamptz,
  constraint late_notice_says_when check ((kind = 'late') = (expected_at is not null)),
  constraint notice_reason_is_short check (reason is null or length(reason) <= 280)
);

-- one live notice per child per day: "late" then "actually not coming" replaces
create unique index absence_notice_one_live_per_day
  on public.absence_notice (child_id, notice_date)
  where withdrawn_at is null;

create index absence_notice_centre_day on public.absence_notice (centre_id, notice_date)
  where withdrawn_at is null;

create or replace function app.absence_notice_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    if old.withdrawn_at is not null then
      raise exception 'this notice was already withdrawn';
    end if;
    if (new.centre_id, new.child_id, new.notice_date, new.kind, new.expected_at,
        new.reason, new.given_by, new.given_at)
       is distinct from
       (old.centre_id, old.child_id, old.notice_date, old.kind, old.expected_at,
        old.reason, old.given_by, old.given_at) then
      raise exception 'a notice is never edited; give a new one and it replaces this';
    end if;
  end if;
  return new;
end;
$$;

create trigger absence_notice_rules
  before update on public.absence_notice
  for each row execute function app.absence_notice_rules();

alter table public.absence_notice enable row level security;

-- the room sees every notice at its centre; a family sees its own children's
create policy absence_notice_select on public.absence_notice
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = absence_notice.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
-- Writes via RPCs only.

create trigger absence_notice_no_delete before delete on public.absence_notice
  for each row execute function app.block_mutation();
create trigger absence_notice_audit after insert or update on public.absence_notice
  for each row execute function app.audit_row();

-- ── a family adult tells the centre ─────────────────────────────────────────
create or replace function public.report_absence(
  p_child uuid,
  p_date date,
  p_kind text,
  p_expected_at time default null,
  p_reason text default null
) returns public.absence_notice
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := app.current_person_id();
  kid public.child;
  local_today date;
  result public.absence_notice;
begin
  select * into kid from public.child where id = p_child;
  if kid.id is null then
    raise exception 'child not found';
  end if;

  -- any adult who can see the child's day may say they are not coming — the
  -- same people who would otherwise be phoned
  if me is null or not exists (
    select 1 from public.child_household ch
    join public.household_member hm on hm.household_id = ch.household_id
    where ch.child_id = p_child
      and hm.person_id = me
      and hm.revoked_at is null
      and hm.can_view
  ) then
    raise exception 'only a family adult of this child can tell the centre';
  end if;

  select (now() at time zone c.timezone)::date into local_today
  from public.centre c where c.id = kid.centre_id;

  if p_date < local_today then
    raise exception 'a notice is about today or a day ahead, not a day that has passed';
  end if;
  if p_kind = 'late' and p_date <> local_today then
    raise exception 'running late is about today — for another day, say they are not coming';
  end if;
  if p_kind = 'late' and p_expected_at is null then
    raise exception 'say roughly when you expect to arrive';
  end if;

  -- a child who is already here is the room's to talk about, not the app's
  if p_date = local_today and exists (
    select 1 from public.attendance_event ae
    where ae.child_id = p_child
      and ae.attendance_date = local_today
      and ae.event_type = 'arrive'
      and not exists (select 1 from public.attendance_event c where c.correction_of = ae.id)
  ) then
    raise exception '% is already signed in today — tell the room directly',
      split_part(kid.full_name, ' ', 1);
  end if;

  -- a new notice replaces the day's live one: "late" becomes "not coming"
  update public.absence_notice
  set withdrawn_at = clock_timestamp()
  where child_id = p_child and notice_date = p_date and withdrawn_at is null;

  insert into public.absence_notice (
    centre_id, child_id, notice_date, kind, expected_at, reason, given_by
  ) values (
    kid.centre_id, p_child, p_date, p_kind,
    case when p_kind = 'late' then p_expected_at end,
    nullif(trim(coalesce(p_reason, '')), ''),
    me
  ) returning * into result;
  return result;
end;
$$;

-- ── and can take it back ────────────────────────────────────────────────────
create or replace function public.withdraw_absence_notice(p_notice uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid := app.current_person_id();
  n public.absence_notice;
begin
  select * into n from public.absence_notice where id = p_notice;
  if n.id is null then
    raise exception 'notice not found';
  end if;
  if me is null or not exists (
    select 1 from public.child_household ch
    join public.household_member hm on hm.household_id = ch.household_id
    where ch.child_id = n.child_id
      and hm.person_id = me
      and hm.revoked_at is null
      and hm.can_view
  ) then
    raise exception 'only a family adult of this child can withdraw it';
  end if;
  update public.absence_notice set withdrawn_at = clock_timestamp()
  where id = p_notice and withdrawn_at is null;
end;
$$;
