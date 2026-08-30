-- 0028 waiting list (s. 75.1). Four rules, and the schema holds all four:
--
--   1. NO FEE AND NO DEPOSIT, ever, to be placed on the list. Not "we choose
--      not to charge" — there is nowhere in this schema to put a fee. No
--      amount, no deposit, no payment column exists on any waitlist table,
--      and a pgTAP test reads the catalogue to prove it stays that way.
--   2. A family learns its position WITHOUT LEARNING ANYONE ELSE'S. Each
--      entry carries an access code the family is given; waitlist_self_check
--      takes that code and returns their position and nothing about any other
--      child or family. RLS never lets one family read another's row.
--   3. THE PUBLISHED ORDER IS THE ACTUAL ORDER. Position is computed — never
--      stored, never hand-set — from the priority category and the moment the
--      family joined. The category can only be changed through an RPC that
--      demands a reason and writes an append-only event, so an inspector can
--      see that nobody was quietly moved up the list.
--   4. NOTHING VANISHES QUIETLY. Entries close (declined, withdrawn, enrolled)
--      instead of being deleted, so the fairness record survives. Contact
--      details are anonymised twelve months after closing by the nightly
--      sweep — the same escape hatch the children's-record anonymiser uses.
--      Keeping a stranger's phone number forever has no regulatory upside
--      (PIPEDA: collect and keep the minimum).
--
-- Joining is a staff act: the centre takes the enquiry and signs it with a
-- PIN. The self-serve half s. 75.1 actually requires is checking your
-- position, and that works with no account at all.

create table public.waitlist_entry (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_name text not null,
  child_date_of_birth date not null,
  age_group_preset public.age_group_preset not null,
  desired_start_on date not null,
  contact_name text not null,
  contact_email text,
  contact_phone text,
  -- an enquiring family usually has no account; if they are already a parent
  -- here (a sibling on the list) this links their entry to them
  contact_person_id uuid references public.person (id),
  -- the family's own key to their own position, and nobody else's
  access_code text not null unique,
  -- the categories the centre's published waiting-list policy names. The
  -- ranks in app.waitlist_rank MUST match the handbook text (s. 45).
  priority text not null default 'general'
    check (priority in ('sibling', 'subsidy_referral', 'general')),
  priority_reason text,
  status text not null default 'waiting'
    check (status in ('waiting', 'offered', 'accepted', 'declined', 'withdrawn', 'enrolled')),
  -- The position anchor: the moment the family joined, and it never moves.
  -- clock_timestamp, not now(): two families added in one transaction still
  -- joined in an order, and that order is their place in the queue.
  joined_at timestamptz not null default clock_timestamp(),
  offered_on date,
  respond_by date,
  closed_at timestamptz,
  -- set once the child is actually enrolled, so the list ties to the record
  child_id uuid references public.child (id),
  recorded_by uuid not null references public.person (id),
  anonymised_at timestamptz,
  created_at timestamptz not null default now(),
  -- a live enquiry can always be reached; an anonymised one deliberately
  -- cannot, which is the point of anonymising it
  constraint waitlist_entry_has_a_contact_route
    check (anonymised_at is not null or contact_email is not null or contact_phone is not null)
);

comment on table public.waitlist_entry is
  's. 75.1: no fee or deposit may be charged for a place on this list. There is '
  'deliberately no column here capable of holding money.';

create index waitlist_entry_open on public.waitlist_entry (centre_id, age_group_preset, joined_at)
  where status in ('waiting', 'offered');

-- Every move on the list, in order, with who and why.
create table public.waitlist_event (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.waitlist_entry (id),
  centre_id uuid not null references public.centre (id),
  event_type text not null check (event_type in (
    'joined', 'priority_changed', 'offered', 'accepted', 'declined', 'withdrawn', 'enrolled'
  )),
  detail text,
  recorded_by uuid references public.person (id),
  created_at timestamptz not null default clock_timestamp()
);

create index waitlist_event_entry on public.waitlist_event (entry_id, created_at);

-- The order the centre publishes, expressed once. Sibling of an enrolled
-- child, then a service-system-manager subsidy referral, then the date the
-- family joined — which is what the seeded handbook section says.
create or replace function app.waitlist_rank(p_priority text)
returns integer
language sql immutable
as $$
  select case p_priority
    when 'sibling' then 1
    when 'subsidy_referral' then 2
    else 3
  end
$$;

create or replace function app.normalise_waitlist_code(p_code text)
returns text
language sql immutable
as $$ select upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g')) $$;

create or replace function app.new_waitlist_code()
returns text
language sql volatile
set search_path = public
as $$ select upper(encode(extensions.gen_random_bytes(8), 'hex')) $$;

-- ── the rules that cannot be talked around ──────────────────────────────────
create or replace function app.waitlist_entry_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(trim(new.child_name), '') = '' or coalesce(trim(new.contact_name), '') = '' then
      raise exception 'a waiting-list entry names the child and who to contact';
    end if;
    if new.desired_start_on < current_date then
      raise exception 'a start date in the past is not a place on the list';
    end if;
  end if;

  if tg_op = 'UPDATE' and not app.is_anonymising() then
    -- the anchor never moves: it is what "in the order they joined" means
    if new.joined_at is distinct from old.joined_at then
      raise exception 'the moment a family joined is their place in the queue and never moves';
    end if;
    -- moving a family up (or down) is always explained
    if new.priority is distinct from old.priority
       and coalesce(trim(coalesce(new.priority_reason, '')), '') = '' then
      raise exception 'changing a family''s priority is recorded with a reason';
    end if;
  end if;

  -- closing states carry the moment they closed. "accepted" closes it too:
  -- the family is off the open list from the moment they say yes.
  if new.status in ('accepted', 'declined', 'withdrawn', 'enrolled') and new.closed_at is null then
    new.closed_at := now();
  end if;
  return new;
end;
$$;

create trigger waitlist_entry_rules
  before insert or update on public.waitlist_entry
  for each row execute function app.waitlist_entry_rules();

-- ── visibility ──────────────────────────────────────────────────────────────
alter table public.waitlist_entry enable row level security;
alter table public.waitlist_event enable row level security;

-- Care staff run the list. A family who already has an account here sees
-- their OWN entry — never anyone else's row, in any circumstance.
create policy waitlist_entry_select on public.waitlist_entry
  for select using (
    centre_id in (select app.care_centre_ids())
    or contact_person_id = app.current_person_id()
  );

create policy waitlist_event_select on public.waitlist_event
  for select using (centre_id in (select app.care_centre_ids()));
-- Writes via RPCs only. Families with no account read their position through
-- waitlist_self_check, which bypasses RLS by design and returns nothing about
-- anybody else.

create trigger waitlist_entry_no_delete before delete on public.waitlist_entry
  for each row execute function app.block_mutation();
create trigger waitlist_event_no_change before update or delete on public.waitlist_event
  for each row execute function app.block_mutation();
create trigger waitlist_entry_audit after insert or update on public.waitlist_entry
  for each row execute function app.audit_row();
create trigger waitlist_event_audit after insert on public.waitlist_event
  for each row execute function app.audit_row();

-- ── the list, in the published order ────────────────────────────────────────
-- Position is computed here and nowhere else — never stored, never hand-set.
-- Deliberately restricted to care staff: a window function only ranks the
-- rows the caller can see, so a family reading this view would be told they
-- are first every time. Families get their position from the two functions
-- below, which count the whole list without revealing any of it.
create view public.waitlist_position
with (security_invoker = on) as
select
  e.*,
  row_number() over (
    partition by e.centre_id, e.age_group_preset
    order by app.waitlist_rank(e.priority), e.joined_at, e.id
  )::integer as list_position
from public.waitlist_entry e
where e.status in ('waiting', 'offered')
  and e.centre_id in (select app.care_centre_ids());

-- ── RPCs ────────────────────────────────────────────────────────────────────
create or replace function public.join_waitlist(
  p_centre uuid,
  p_child_name text,
  p_child_dob date,
  p_age_group public.age_group_preset,
  p_desired_start date,
  p_contact_name text,
  p_contact_email text,
  p_contact_phone text,
  p_priority text,
  p_priority_reason text,
  p_recorder uuid,
  p_pin text
) returns public.waitlist_entry
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.waitlist_entry;
  linked uuid;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if coalesce(trim(coalesce(p_contact_email, '')), '') = ''
     and coalesce(trim(coalesce(p_contact_phone, '')), '') = '' then
    raise exception 'record an email or a phone number so the family can be reached';
  end if;
  if coalesce(p_priority, 'general') <> 'general'
     and coalesce(trim(coalesce(p_priority_reason, '')), '') = '' then
    raise exception 'a family placed above the date order is recorded with a reason';
  end if;

  -- if the contact is already a parent here, tie the entry to them so they
  -- can see their position in the app without a code
  select p.id into linked
  from public.person p
  join public.person_role pr on pr.person_id = p.id and pr.centre_id = p_centre and pr.active
  where lower(p.email) = lower(nullif(trim(coalesce(p_contact_email, '')), ''))
  limit 1;

  insert into public.waitlist_entry (
    centre_id, child_name, child_date_of_birth, age_group_preset, desired_start_on,
    contact_name, contact_email, contact_phone, contact_person_id, access_code,
    priority, priority_reason, recorded_by
  ) values (
    p_centre, trim(p_child_name), p_child_dob, p_age_group, p_desired_start,
    trim(p_contact_name), nullif(trim(coalesce(p_contact_email, '')), ''),
    nullif(trim(coalesce(p_contact_phone, '')), ''), linked, app.new_waitlist_code(),
    coalesce(p_priority, 'general'), nullif(trim(coalesce(p_priority_reason, '')), ''), recorder
  ) returning * into result;

  insert into public.waitlist_event (entry_id, centre_id, event_type, detail, recorded_by)
  values (result.id, p_centre, 'joined',
          'Added to the ' || p_age_group || ' list' ||
          coalesce(' — ' || result.priority_reason, ''), recorder);
  return result;
end;
$$;

-- Moving a family up the list is the act that most needs a witness, so it is
-- a leadership act and it always carries a reason.
create or replace function public.set_waitlist_priority(
  p_entry uuid,
  p_priority text,
  p_reason text,
  p_recorder uuid,
  p_pin text
) returns public.waitlist_entry
language plpgsql security definer
set search_path = public
as $$
declare
  entry public.waitlist_entry;
  recorder uuid;
begin
  select * into entry from public.waitlist_entry where id = p_entry;
  if entry.id is null then raise exception 'waiting-list entry not found'; end if;
  recorder := app.resolve_recorder(entry.centre_id, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = entry.centre_id and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate')
  ) then
    raise exception 'only centre leadership changes a family''s place on the list';
  end if;
  if coalesce(trim(coalesce(p_reason, '')), '') = '' then
    raise exception 'changing a family''s priority is recorded with a reason';
  end if;
  if entry.status not in ('waiting', 'offered') then
    raise exception 'this entry is closed';
  end if;

  update public.waitlist_entry
  set priority = p_priority, priority_reason = trim(p_reason)
  where id = p_entry
  returning * into entry;

  insert into public.waitlist_event (entry_id, centre_id, event_type, detail, recorded_by)
  values (p_entry, entry.centre_id, 'priority_changed',
          'Moved to ' || replace(p_priority, '_', ' ') || ' — ' || trim(p_reason), recorder);
  return entry;
end;
$$;

create or replace function public.offer_waitlist_place(
  p_entry uuid,
  p_respond_by date,
  p_recorder uuid,
  p_pin text
) returns public.waitlist_entry
language plpgsql security definer
set search_path = public
as $$
declare
  entry public.waitlist_entry;
  recorder uuid;
begin
  select * into entry from public.waitlist_entry where id = p_entry;
  if entry.id is null then raise exception 'waiting-list entry not found'; end if;
  recorder := app.resolve_recorder(entry.centre_id, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = entry.centre_id and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate')
  ) then
    raise exception 'only centre leadership offers a place';
  end if;
  if entry.status <> 'waiting' then
    raise exception 'only a waiting family can be offered a place';
  end if;
  if coalesce(p_respond_by, current_date) < current_date then
    raise exception 'give the family a date in the future to respond by';
  end if;

  update public.waitlist_entry
  set status = 'offered', offered_on = current_date,
      respond_by = coalesce(p_respond_by, current_date + 7)
  where id = p_entry
  returning * into entry;

  insert into public.waitlist_event (entry_id, centre_id, event_type, detail, recorded_by)
  values (p_entry, entry.centre_id, 'offered',
          'Place offered, to answer by ' || to_char(entry.respond_by, 'DD Mon YYYY'), recorder);
  return entry;
end;
$$;

create or replace function public.record_waitlist_response(
  p_entry uuid,
  p_response text,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns public.waitlist_entry
language plpgsql security definer
set search_path = public
as $$
declare
  entry public.waitlist_entry;
  recorder uuid;
begin
  select * into entry from public.waitlist_entry where id = p_entry;
  if entry.id is null then raise exception 'waiting-list entry not found'; end if;
  recorder := app.resolve_recorder(entry.centre_id, p_recorder, p_pin);
  if entry.status <> 'offered' then
    raise exception 'there is no offer outstanding for this family';
  end if;
  if p_response not in ('accepted', 'declined') then
    raise exception 'a family either accepts or declines the place';
  end if;

  update public.waitlist_entry
  set status = p_response
  where id = p_entry
  returning * into entry;

  insert into public.waitlist_event (entry_id, centre_id, event_type, detail, recorded_by)
  values (p_entry, entry.centre_id, p_response,
          nullif(trim(coalesce(p_note, '')), ''), recorder);
  return entry;
end;
$$;

create or replace function public.withdraw_waitlist_entry(
  p_entry uuid,
  p_reason text,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  entry public.waitlist_entry;
  recorder uuid;
begin
  select * into entry from public.waitlist_entry where id = p_entry;
  if entry.id is null then raise exception 'waiting-list entry not found'; end if;
  recorder := app.resolve_recorder(entry.centre_id, p_recorder, p_pin);
  if entry.status in ('withdrawn', 'enrolled') then
    raise exception 'this entry is already closed';
  end if;

  update public.waitlist_entry set status = 'withdrawn' where id = p_entry;
  insert into public.waitlist_event (entry_id, centre_id, event_type, detail, recorded_by)
  values (p_entry, entry.centre_id, 'withdrawn',
          nullif(trim(coalesce(p_reason, '')), ''), recorder);
end;
$$;

-- The family accepted and the child is now enrolled: tie the list to the
-- record so the admission order is auditable end to end.
create or replace function public.link_waitlist_enrolment(
  p_entry uuid,
  p_child uuid,
  p_recorder uuid,
  p_pin text
) returns public.waitlist_entry
language plpgsql security definer
set search_path = public
as $$
declare
  entry public.waitlist_entry;
  recorder uuid;
begin
  select * into entry from public.waitlist_entry where id = p_entry;
  if entry.id is null then raise exception 'waiting-list entry not found'; end if;
  recorder := app.resolve_recorder(entry.centre_id, p_recorder, p_pin);
  if not exists (select 1 from public.child ch where ch.id = p_child and ch.centre_id = entry.centre_id) then
    raise exception 'child is not enrolled at this centre';
  end if;

  update public.waitlist_entry
  set status = 'enrolled', child_id = p_child
  where id = p_entry
  returning * into entry;

  insert into public.waitlist_event (entry_id, centre_id, event_type, detail, recorded_by)
  values (p_entry, entry.centre_id, 'enrolled', 'Enrolled from the waiting list', recorder);
  return entry;
end;
$$;

-- ── the family's own view: their position, and nothing else ─────────────────
-- s. 75.1: a family learns where it stands without learning anything about
-- any other child or family. Callable with no account — an enquiring family
-- is not a user of ours, and making them create one to see a number would be
-- the "ask your admin" pattern in another costume.
create or replace function public.waitlist_self_check(p_code text)
returns table (
  centre_name text,
  child_first_name text,
  age_group text,
  status text,
  list_position integer,
  families_ahead integer,
  list_length integer,
  joined_on date,
  desired_start_on date,
  respond_by date
)
language sql stable security definer
set search_path = public
as $$
  with me as (
    select e.* from public.waitlist_entry e
    where e.access_code = app.normalise_waitlist_code(p_code)
      and e.anonymised_at is null
  ),
  open_list as (
    select e.id, e.priority, e.joined_at
    from public.waitlist_entry e, me
    where e.centre_id = me.centre_id
      and e.age_group_preset = me.age_group_preset
      and e.status in ('waiting', 'offered')
  ),
  ranked as (
    select o.id,
      row_number() over (order by app.waitlist_rank(o.priority), o.joined_at, o.id)::integer as list_position
    from open_list o
  )
  select
    c.name,
    split_part(me.child_name, ' ', 1),
    me.age_group_preset::text,
    me.status,
    r.list_position,
    greatest(coalesce(r.list_position, 1) - 1, 0)::integer,
    (select count(*)::integer from open_list),
    me.joined_at::date,
    me.desired_start_on,
    me.respond_by
  from me
  join public.centre c on c.id = me.centre_id
  left join ranked r on r.id = me.id
$$;

-- An enquiring family has no account, so this one function is reachable
-- without a session. It returns one row about the holder of the code and
-- nothing about anyone else — the code is the whole of the authorisation.
grant execute on function public.waitlist_self_check(text) to anon, authenticated;

-- The same answer for a family who IS already a parent here (a sibling on the
-- list): no code to keep, because being signed in is the authorisation. Same
-- shape, same discretion — their own row and a count, nothing else.
create or replace function public.my_waitlist_positions()
returns table (
  entry_id uuid,
  centre_name text,
  child_name text,
  age_group text,
  status text,
  list_position integer,
  families_ahead integer,
  list_length integer,
  joined_on date,
  desired_start_on date,
  respond_by date
)
language sql stable security definer
set search_path = public
as $$
  with me as (
    select e.* from public.waitlist_entry e
    where e.contact_person_id = app.current_person_id()
      and e.anonymised_at is null
      and e.status in ('waiting', 'offered')
  ),
  ranked as (
    select
      e.id, e.centre_id, e.age_group_preset,
      row_number() over (
        partition by e.centre_id, e.age_group_preset
        order by app.waitlist_rank(e.priority), e.joined_at, e.id
      )::integer as list_position,
      count(*) over (partition by e.centre_id, e.age_group_preset)::integer as list_length
    from public.waitlist_entry e
    where e.status in ('waiting', 'offered')
      and (e.centre_id, e.age_group_preset) in (select m.centre_id, m.age_group_preset from me m)
  )
  select
    me.id,
    c.name,
    me.child_name,
    me.age_group_preset::text,
    me.status,
    r.list_position,
    greatest(r.list_position - 1, 0)::integer,
    r.list_length,
    me.joined_at::date,
    me.desired_start_on,
    me.respond_by
  from me
  join public.centre c on c.id = me.centre_id
  join ranked r on r.id = me.id
$$;

-- ── retention: keep the fairness record, drop the stranger's phone number ───
create or replace function app.anonymise_waitlist_entry(p_entry uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  entry public.waitlist_entry;
begin
  select * into entry from public.waitlist_entry where id = p_entry;
  if entry.id is null then raise exception 'waiting-list entry not found'; end if;
  if entry.anonymised_at is not null then return; end if;
  if entry.closed_at is null or entry.closed_at > now() - interval '12 months' then
    raise exception 'a waiting-list entry is anonymised twelve months after it closes, never before';
  end if;

  perform set_config('app.anonymising', 'on', true);
  update public.waitlist_entry
  set child_name = 'Closed enquiry',
      -- the year is the only part of the birth date the fairness record needs
      child_date_of_birth = make_date(extract(year from entry.child_date_of_birth)::int, 1, 1),
      contact_name = 'Closed enquiry',
      contact_email = null,
      contact_phone = null,
      contact_person_id = null,
      access_code = 'CLOSED-' || replace(p_entry::text, '-', ''),
      anonymised_at = now()
  where id = p_entry;
  perform set_config('app.anonymising', '', true);
end;
$$;

-- Its own sweep, on its own schedule, returning its own count. Deliberately
-- NOT folded into app.run_retention_sweep: that function's number means
-- "children's records anonymised under s. 72(5)", and a number that means two
-- things at once is a number nobody can act on.
create or replace function app.run_waitlist_sweep()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  entry record;
  n integer := 0;
begin
  for entry in
    select id from public.waitlist_entry
    where anonymised_at is null
      and closed_at is not null
      and closed_at <= now() - interval '12 months'
  loop
    perform app.anonymise_waitlist_entry(entry.id);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- 02:45, just after the children's-record sweep at 02:30.
select cron.schedule('waitlist-sweep', '45 2 * * *', $$select app.run_waitlist_sweep()$$);
