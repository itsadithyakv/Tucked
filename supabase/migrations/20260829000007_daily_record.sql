-- 0007 daily written record (s. 37): a dated entry every operating day, no
-- exceptions — drafts are created by the database itself (pg_cron), closing
-- requires a named human, records are never deleted and never change after
-- close. Default scope is per centre (decision 2026-08-29); per-room rows are
-- supported by the same table (room_id set).

create table public.daily_written_record (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  room_id uuid references public.room (id), -- null = whole-centre scope (default)
  record_date date not null,
  draft_text text not null default '',
  final_text text,
  closed_by uuid references public.person (id),
  closed_at timestamptz,
  refs jsonb not null default '[]'::jsonb, -- cross-references: accidents, drills, self-administered medication
  created_at timestamptz not null default now(),
  constraint dwr_closed_fields_together
    check ((closed_at is null) = (closed_by is null) and (closed_at is null) = (final_text is null))
);

create unique index dwr_one_per_scope_per_day
  on public.daily_written_record (centre_id, coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid), record_date);

alter table public.daily_written_record enable row level security;

create policy dwr_select on public.daily_written_record
  for select using (centre_id in (select app.care_centre_ids()));
-- Writes via RPCs and triggers only.

-- ── rules: immutable after close; never deleted ─────────────────────────────
create or replace function app.dwr_rules()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' and old.closed_at is not null then
    raise exception 'a closed daily written record never changes';
  end if;
  return new;
end;
$$;

create trigger dwr_rules
  before update on public.daily_written_record
  for each row execute function app.dwr_rules();

create trigger dwr_no_delete
  before delete on public.daily_written_record
  for each row execute function app.block_mutation();

create trigger dwr_audit
  after insert or update on public.daily_written_record
  for each row execute function app.audit_row();

-- ── draft creation ──────────────────────────────────────────────────────────
-- Skeleton draft with the day's hard numbers; the richer prose draft is
-- assembled client/Edge-side from care logs and saved via refresh below.
create or replace function app.dwr_skeleton(p_centre uuid, p_date date)
returns text
language sql stable security definer
set search_path = public
as $$
  select format(
    'Attendance: %s children present. Staff on shift: %s. Nothing further recorded.',
    (select count(distinct ae.child_id) from public.attendance_event ae
     where ae.centre_id = p_centre and ae.attendance_date = p_date and ae.event_type = 'arrive'),
    (select count(distinct ss.person_id) from public.staff_shift ss
     where ss.centre_id = p_centre and ss.shift_date = p_date)
  )
$$;

create or replace function public.ensure_daily_record(p_centre uuid, p_date date, p_room uuid default null)
returns public.daily_written_record
language plpgsql security definer
set search_path = public
as $$
declare
  result public.daily_written_record;
begin
  select * into result from public.daily_written_record
  where centre_id = p_centre and record_date = p_date
    and room_id is not distinct from p_room;
  if result.id is not null then
    return result;
  end if;
  insert into public.daily_written_record (centre_id, room_id, record_date, draft_text)
  values (p_centre, p_room, p_date, app.dwr_skeleton(p_centre, p_date))
  returning * into result;
  return result;
end;
$$;

-- Hourly cron: create today's draft for every centre once its local clock
-- passes 06:00 on a weekday. (Centre holiday calendars arrive in Phase 2.)
create or replace function app.create_daily_record_drafts()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  c record;
  created integer := 0;
  local_now timestamptz;
  local_date date;
begin
  for c in select id, timezone from public.centre loop
    local_now := now() at time zone c.timezone;
    local_date := local_now::date;
    if extract(isodow from local_date) between 1 and 5
       and local_now::time >= '06:00'
       and not exists (
         select 1 from public.daily_written_record d
         where d.centre_id = c.id and d.record_date = local_date and d.room_id is null
       ) then
      perform public.ensure_daily_record(c.id, local_date);
      created := created + 1;
    end if;
  end loop;
  return created;
end;
$$;

create extension if not exists pg_cron;
select cron.schedule('daily-record-drafts', '5 * * * *', $$select app.create_daily_record_drafts()$$);

-- ── close and refresh RPCs ──────────────────────────────────────────────────
create or replace function public.refresh_daily_record_draft(
  p_record uuid,
  p_draft text,
  p_recorder uuid,
  p_pin text
) returns public.daily_written_record
language plpgsql security definer
set search_path = public
as $$
declare
  result public.daily_written_record;
begin
  select * into result from public.daily_written_record where id = p_record;
  if result.id is null then raise exception 'record not found'; end if;
  perform app.resolve_recorder(result.centre_id, p_recorder, p_pin);
  update public.daily_written_record set draft_text = p_draft where id = p_record
  returning * into result;
  return result;
end;
$$;

-- Closing is the human act (s. 37): a named person confirms the day's entry.
-- "Uneventful" is a valid answer; an empty one is not.
create or replace function public.close_daily_record(
  p_record uuid,
  p_final_text text,
  p_recorder uuid,
  p_pin text
) returns public.daily_written_record
language plpgsql security definer
set search_path = public
as $$
declare
  result public.daily_written_record;
  recorder uuid;
begin
  select * into result from public.daily_written_record where id = p_record;
  if result.id is null then raise exception 'record not found'; end if;
  if result.closed_at is not null then
    raise exception 'a closed daily written record never changes';
  end if;
  if p_final_text is null or length(trim(p_final_text)) = 0 then
    raise exception 'the daily written record needs a written entry';
  end if;
  recorder := app.resolve_recorder(result.centre_id, p_recorder, p_pin);
  update public.daily_written_record
  set final_text = p_final_text, closed_by = recorder, closed_at = now()
  where id = p_record
  returning * into result;
  return result;
end;
$$;

-- Append a cross-reference (accidents, drills, self-administered medication
-- must be summarised — s. 37). Called by triggers on those tables.
create or replace function app.dwr_append_ref(p_centre uuid, p_date date, p_ref jsonb)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  rec public.daily_written_record;
begin
  rec := public.ensure_daily_record(p_centre, p_date);
  if rec.closed_at is null then
    update public.daily_written_record
    set refs = refs || jsonb_build_array(p_ref)
    where id = rec.id;
  else
    -- Arrived after close: it belongs to the next operating day's entry.
    rec := public.ensure_daily_record(p_centre, p_date + 1);
    update public.daily_written_record
    set refs = refs || jsonb_build_array(p_ref || jsonb_build_object('late_for', p_date::text))
    where id = rec.id;
  end if;
end;
$$;
