-- 0020 serious occurrences (s. 38 + Licensing Manual). The most expensive
-- record in the regulation: report through CCLS within 24 HOURS of the
-- supervisor or licensee becoming aware ($2,000 penalty, escalating), post an
-- anonymised summary for 10 BUSINESS DAYS (weekends and Ontario statutory
-- holidays don't count), keep updating as information arrives. Rules held in
-- this schema:
--   * The app NEVER files to CCLS (§9.14): a named human files on the CCLS
--     website and then records here what was filed and when.
--   * The 24-hour clock runs from aware_at, computed in the database.
--   * Abuse/neglect allegations are NEVER posted (they identify people and
--     can prejudice an investigation) and cannot close without a recorded
--     Children's Aid Society report (CYFSA duty).
--   * The anonymised posting is rejected if it contains an involved child's
--     name. Business-day arithmetic uses the jurisdiction's statutory
--     holiday table.
--   * Supervisor/licensee eyes only: allegations may concern staff, so RECEs,
--     volunteers and parents never see these rows.

-- ── statutory holidays (jurisdiction-aware business-day arithmetic) ─────────
create table public.statutory_holiday (
  jurisdiction_code text not null references public.jurisdiction (code),
  holiday_date date not null,
  name text not null,
  primary key (jurisdiction_code, holiday_date)
);

alter table public.statutory_holiday enable row level security;
create policy statutory_holiday_select on public.statutory_holiday for select using (true);

-- Ontario ESA statutory holidays, 2026–2030. Extend before 2031 (a pgTAP
-- test fails when coverage runs out, so this cannot rot silently).
insert into public.statutory_holiday (jurisdiction_code, holiday_date, name) values
  ('CA-ON', '2026-01-01', 'New Year''s Day'),
  ('CA-ON', '2026-02-16', 'Family Day'),
  ('CA-ON', '2026-04-03', 'Good Friday'),
  ('CA-ON', '2026-05-18', 'Victoria Day'),
  ('CA-ON', '2026-07-01', 'Canada Day'),
  ('CA-ON', '2026-09-07', 'Labour Day'),
  ('CA-ON', '2026-10-12', 'Thanksgiving'),
  ('CA-ON', '2026-12-25', 'Christmas Day'),
  ('CA-ON', '2026-12-26', 'Boxing Day'),
  ('CA-ON', '2027-01-01', 'New Year''s Day'),
  ('CA-ON', '2027-02-15', 'Family Day'),
  ('CA-ON', '2027-03-26', 'Good Friday'),
  ('CA-ON', '2027-05-24', 'Victoria Day'),
  ('CA-ON', '2027-07-01', 'Canada Day'),
  ('CA-ON', '2027-09-06', 'Labour Day'),
  ('CA-ON', '2027-10-11', 'Thanksgiving'),
  ('CA-ON', '2027-12-25', 'Christmas Day'),
  ('CA-ON', '2027-12-26', 'Boxing Day'),
  ('CA-ON', '2028-01-01', 'New Year''s Day'),
  ('CA-ON', '2028-02-21', 'Family Day'),
  ('CA-ON', '2028-04-14', 'Good Friday'),
  ('CA-ON', '2028-05-22', 'Victoria Day'),
  ('CA-ON', '2028-07-01', 'Canada Day'),
  ('CA-ON', '2028-09-04', 'Labour Day'),
  ('CA-ON', '2028-10-09', 'Thanksgiving'),
  ('CA-ON', '2028-12-25', 'Christmas Day'),
  ('CA-ON', '2028-12-26', 'Boxing Day'),
  ('CA-ON', '2029-01-01', 'New Year''s Day'),
  ('CA-ON', '2029-02-19', 'Family Day'),
  ('CA-ON', '2029-03-30', 'Good Friday'),
  ('CA-ON', '2029-05-21', 'Victoria Day'),
  ('CA-ON', '2029-07-01', 'Canada Day'),
  ('CA-ON', '2029-09-03', 'Labour Day'),
  ('CA-ON', '2029-10-08', 'Thanksgiving'),
  ('CA-ON', '2029-12-25', 'Christmas Day'),
  ('CA-ON', '2029-12-26', 'Boxing Day'),
  ('CA-ON', '2030-01-01', 'New Year''s Day'),
  ('CA-ON', '2030-02-18', 'Family Day'),
  ('CA-ON', '2030-04-19', 'Good Friday'),
  ('CA-ON', '2030-05-20', 'Victoria Day'),
  ('CA-ON', '2030-07-01', 'Canada Day'),
  ('CA-ON', '2030-09-02', 'Labour Day'),
  ('CA-ON', '2030-10-14', 'Thanksgiving'),
  ('CA-ON', '2030-12-25', 'Christmas Day'),
  ('CA-ON', '2030-12-26', 'Boxing Day');

-- The date after p_days business days have elapsed following p_start.
create or replace function app.add_business_days(p_jurisdiction text, p_start date, p_days integer)
returns date
language plpgsql stable
as $$
declare
  d date := p_start;
  added integer := 0;
begin
  while added < p_days loop
    d := d + 1;
    if extract(isodow from d) < 6 and not exists (
      select 1 from public.statutory_holiday h
      where h.jurisdiction_code = p_jurisdiction and h.holiday_date = d
    ) then
      added := added + 1;
    end if;
  end loop;
  return d;
end;
$$;

-- ── the occurrence ──────────────────────────────────────────────────────────
create table public.serious_occurrence (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  category text not null check (category in (
    'death', 'abuse_neglect_allegation', 'life_threatening_injury_illness',
    'missing_unsupervised_child', 'unplanned_disruption'
  )),
  occurred_at timestamptz not null,
  -- when the supervisor or licensee became aware — the 24-hour clock starts HERE
  aware_at timestamptz not null,
  -- always aware_at + 24 hours; set by trigger on every insert path
  ccls_deadline_at timestamptz not null,
  description text not null,
  immediate_actions text,
  reported_by uuid not null references public.person (id),
  status text not null default 'open' check (status in ('open', 'filed', 'closed')),
  -- CCLS filing: recorded AFTER a named human files on the CCLS site
  ccls_number text,
  ccls_filed_at timestamptz,
  ccls_filed_by uuid references public.person (id),
  -- CCLS-down fallback: program advisor phoned/emailed within the 24 hours
  fallback_contacted_at timestamptz,
  fallback_note text,
  -- CYFSA duty (abuse/neglect only): the individual's CAS report, recorded
  cas_reported_at timestamptz,
  cas_reported_by uuid references public.person (id),
  cas_note text,
  closed_at timestamptz,
  closed_by uuid references public.person (id),
  closure_note text,
  -- one-shot reminder flags for the hourly cron
  deadline_warning_sent_at timestamptz,
  overdue_notice_sent_at timestamptz,
  created_at timestamptz not null default now(),
  constraint so_aware_not_before_occurred check (aware_at >= occurred_at)
);

-- The 24-hour clock is arithmetic, not opinion: whatever path inserts the
-- row, the deadline is aware_at + 24 hours.
create or replace function app.so_set_deadline()
returns trigger
language plpgsql
as $$
begin
  new.ccls_deadline_at := new.aware_at + interval '24 hours';
  return new;
end;
$$;

create trigger so_set_deadline
  before insert on public.serious_occurrence
  for each row execute function app.so_set_deadline();

create index serious_occurrence_centre_open
  on public.serious_occurrence (centre_id, ccls_deadline_at) where status = 'open';

create table public.serious_occurrence_child (
  serious_occurrence_id uuid not null references public.serious_occurrence (id),
  child_id uuid not null references public.child (id),
  centre_id uuid not null references public.centre (id),
  primary key (serious_occurrence_id, child_id)
);

create table public.serious_occurrence_update (
  id uuid primary key default gen_random_uuid(),
  serious_occurrence_id uuid not null references public.serious_occurrence (id),
  centre_id uuid not null references public.centre (id),
  -- 'ccls_update' = this update was also filed in CCLS at created_at
  update_type text not null default 'note' check (update_type in ('note', 'ccls_update')),
  note text not null,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now()
);

create table public.serious_occurrence_posting (
  id uuid primary key default gen_random_uuid(),
  serious_occurrence_id uuid not null references public.serious_occurrence (id),
  centre_id uuid not null references public.centre (id),
  version integer not null,
  summary text not null,
  posted_on date not null,
  -- keep the paper up through this date: 10 business days, holidays excluded
  posting_ends_on date not null,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now(),
  unique (serious_occurrence_id, version)
);

-- ── visibility: supervisor and licensee eyes only ───────────────────────────
alter table public.serious_occurrence enable row level security;
alter table public.serious_occurrence_child enable row level security;
alter table public.serious_occurrence_update enable row level security;
alter table public.serious_occurrence_posting enable row level security;

create policy so_select on public.serious_occurrence
  for select using (app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[]));
create policy so_child_select on public.serious_occurrence_child
  for select using (app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[]));
create policy so_update_select on public.serious_occurrence_update
  for select using (app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[]));
create policy so_posting_select on public.serious_occurrence_posting
  for select using (app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[]));
-- Writes via the RPCs below only.

-- ── append-only + audit ─────────────────────────────────────────────────────
create trigger so_no_delete before delete on public.serious_occurrence
  for each row execute function app.block_mutation();
create trigger so_update_no_delete before delete on public.serious_occurrence_update
  for each row execute function app.block_mutation();
create trigger so_posting_no_delete before delete on public.serious_occurrence_posting
  for each row execute function app.block_mutation();
create trigger so_child_no_delete before delete on public.serious_occurrence_child
  for each row execute function app.block_mutation();

create trigger so_audit after insert or update on public.serious_occurrence
  for each row execute function app.audit_row();
create trigger so_update_audit after insert on public.serious_occurrence_update
  for each row execute function app.audit_row();
create trigger so_posting_audit after insert on public.serious_occurrence_posting
  for each row execute function app.audit_row();

-- Every serious occurrence is summarised in the daily written record (s. 37).
create or replace function app.so_cross_reference()
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
    (new.occurred_at at time zone tz)::date,
    jsonb_build_object(
      'type', 'serious_occurrence',
      'serious_occurrence_id', new.id,
      'note', 'Serious occurrence (' || replace(new.category, '_', ' ') || ') — see the serious occurrence record'
    )
  );
  return new;
end;
$$;

create trigger so_cross_reference
  after insert on public.serious_occurrence
  for each row execute function app.so_cross_reference();

-- Recording, filing, posting and closing are leadership acts.
create or replace function app.resolve_so_recorder(p_centre uuid, p_recorder uuid, p_pin text)
returns uuid
language plpgsql stable security definer
set search_path = public
as $$
declare
  recorder uuid;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate')
  ) then
    raise exception 'serious occurrences are recorded by the supervisor, a designate, or the licensee'
      using errcode = '42501';
  end if;
  return recorder;
end;
$$;

-- ── RPCs ────────────────────────────────────────────────────────────────────
create or replace function public.record_serious_occurrence(
  p_centre uuid,
  p_category text,
  p_occurred_at timestamptz,
  p_aware_at timestamptz,
  p_description text,
  p_immediate_actions text,
  p_children uuid[],
  p_recorder uuid,
  p_pin text
) returns public.serious_occurrence
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.serious_occurrence;
  kid uuid;
begin
  recorder := app.resolve_so_recorder(p_centre, p_recorder, p_pin);
  if coalesce(trim(p_description), '') = '' then
    raise exception 'describe what happened — this record goes to the Ministry';
  end if;
  if p_occurred_at > now() or p_aware_at > now() then
    raise exception 'occurrence times cannot be in the future';
  end if;

  insert into public.serious_occurrence (
    centre_id, category, occurred_at, aware_at, description, immediate_actions, reported_by
  ) values (
    p_centre, p_category, p_occurred_at, p_aware_at, trim(p_description), nullif(trim(p_immediate_actions), ''), recorder
  ) returning * into result;

  foreach kid in array coalesce(p_children, '{}'::uuid[]) loop
    if not exists (select 1 from public.child ch where ch.id = kid and ch.centre_id = p_centre) then
      raise exception 'child % is not enrolled at this centre', kid;
    end if;
    insert into public.serious_occurrence_child (serious_occurrence_id, child_id, centre_id)
    values (result.id, kid, p_centre);
  end loop;

  return result;
end;
$$;

-- Records that a human ALREADY filed in CCLS — never files anything itself.
create or replace function public.file_serious_occurrence_ccls(
  p_occurrence uuid,
  p_ccls_number text,
  p_filed_at timestamptz,
  p_recorder uuid,
  p_pin text
) returns public.serious_occurrence
language plpgsql security definer
set search_path = public
as $$
declare
  so public.serious_occurrence;
  recorder uuid;
begin
  select * into so from public.serious_occurrence where id = p_occurrence;
  if so.id is null then raise exception 'serious occurrence not found'; end if;
  recorder := app.resolve_so_recorder(so.centre_id, p_recorder, p_pin);
  if coalesce(trim(p_ccls_number), '') = '' then
    raise exception 'the CCLS serious occurrence number is the evidence of filing — it cannot be blank';
  end if;
  if so.ccls_filed_at is not null then
    raise exception 'already filed in CCLS — record further information as an update';
  end if;
  if p_filed_at > now() then
    raise exception 'the filing time cannot be in the future';
  end if;
  if p_filed_at < so.aware_at then
    raise exception 'filed before the supervisor became aware — check the times';
  end if;

  update public.serious_occurrence
  set ccls_number = trim(p_ccls_number),
      ccls_filed_at = coalesce(p_filed_at, now()),
      ccls_filed_by = recorder,
      status = 'filed'
  where id = p_occurrence
  returning * into so;
  return so;
end;
$$;

-- CCLS is down: the program advisor was phoned or emailed within the 24 hours.
create or replace function public.record_serious_occurrence_fallback(
  p_occurrence uuid,
  p_contacted_at timestamptz,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  so public.serious_occurrence;
  recorder uuid;
begin
  select * into so from public.serious_occurrence where id = p_occurrence;
  if so.id is null then raise exception 'serious occurrence not found'; end if;
  recorder := app.resolve_so_recorder(so.centre_id, p_recorder, p_pin);
  if coalesce(trim(p_note), '') = '' then
    raise exception 'record who was contacted and how';
  end if;
  update public.serious_occurrence
  set fallback_contacted_at = coalesce(p_contacted_at, now()), fallback_note = trim(p_note)
  where id = p_occurrence;
end;
$$;

-- CYFSA duty to report to the Children's Aid Society (abuse/neglect only).
create or replace function public.record_cas_report(
  p_occurrence uuid,
  p_reported_at timestamptz,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  so public.serious_occurrence;
  recorder uuid;
begin
  select * into so from public.serious_occurrence where id = p_occurrence;
  if so.id is null then raise exception 'serious occurrence not found'; end if;
  recorder := app.resolve_so_recorder(so.centre_id, p_recorder, p_pin);
  if so.category <> 'abuse_neglect_allegation' then
    raise exception 'the CAS duty applies to abuse or neglect allegations';
  end if;
  update public.serious_occurrence
  set cas_reported_at = coalesce(p_reported_at, now()),
      cas_reported_by = recorder,
      cas_note = nullif(trim(coalesce(p_note, '')), '')
  where id = p_occurrence;
end;
$$;

create or replace function public.add_serious_occurrence_update(
  p_occurrence uuid,
  p_note text,
  p_type text,
  p_recorder uuid,
  p_pin text
) returns public.serious_occurrence_update
language plpgsql security definer
set search_path = public
as $$
declare
  so public.serious_occurrence;
  recorder uuid;
  result public.serious_occurrence_update;
begin
  select * into so from public.serious_occurrence where id = p_occurrence;
  if so.id is null then raise exception 'serious occurrence not found'; end if;
  recorder := app.resolve_so_recorder(so.centre_id, p_recorder, p_pin);
  if coalesce(trim(p_note), '') = '' then
    raise exception 'an update needs content';
  end if;
  insert into public.serious_occurrence_update (serious_occurrence_id, centre_id, update_type, note, recorded_by)
  values (p_occurrence, so.centre_id, coalesce(p_type, 'note'), trim(p_note), recorder)
  returning * into result;
  return result;
end;
$$;

-- Anonymised posting: never for abuse/neglect allegations; never containing an
-- involved child's name; up for 10 business days (statutory holidays excluded).
create or replace function public.post_serious_occurrence_summary(
  p_occurrence uuid,
  p_summary text,
  p_posted_on date,
  p_recorder uuid,
  p_pin text
) returns public.serious_occurrence_posting
language plpgsql security definer
set search_path = public
as $$
declare
  so public.serious_occurrence;
  recorder uuid;
  jur text;
  name_token text;
  result public.serious_occurrence_posting;
begin
  select * into so from public.serious_occurrence where id = p_occurrence;
  if so.id is null then raise exception 'serious occurrence not found'; end if;
  recorder := app.resolve_so_recorder(so.centre_id, p_recorder, p_pin);
  if so.category = 'abuse_neglect_allegation' then
    raise exception 'abuse or neglect allegations are never posted';
  end if;
  if coalesce(trim(p_summary), '') = '' then
    raise exception 'the posted summary cannot be blank';
  end if;

  -- The anonymisation guard checks EVERY enrolled child's name — not only the
  -- attached ones, because under stress staff forget checkboxes and a name in
  -- a public posting is a leak either way. Word-boundary matching, so a child
  -- named Sam does not block the word "same".
  for name_token in
    select distinct lower(t)
    from public.child ch,
    unnest(string_to_array(ch.full_name, ' ')) as t
    where ch.centre_id = so.centre_id and length(t) >= 3
  loop
    if lower(p_summary) ~ ('\m' || regexp_replace(name_token, '([^a-z0-9])', '\\\1', 'g') || '\M') then
      raise exception 'the posted summary must be anonymised — it contains a child''s name (%)', name_token;
    end if;
  end loop;

  select c.jurisdiction_code into jur from public.centre c where c.id = so.centre_id;

  insert into public.serious_occurrence_posting (
    serious_occurrence_id, centre_id, version, summary, posted_on, posting_ends_on, recorded_by
  ) values (
    p_occurrence, so.centre_id,
    coalesce((select max(version) from public.serious_occurrence_posting
              where serious_occurrence_id = p_occurrence), 0) + 1,
    trim(p_summary), coalesce(p_posted_on, current_date),
    app.add_business_days(jur, coalesce(p_posted_on, current_date), 10),
    recorder
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.close_serious_occurrence(
  p_occurrence uuid,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns public.serious_occurrence
language plpgsql security definer
set search_path = public
as $$
declare
  so public.serious_occurrence;
  recorder uuid;
begin
  select * into so from public.serious_occurrence where id = p_occurrence;
  if so.id is null then raise exception 'serious occurrence not found'; end if;
  recorder := app.resolve_so_recorder(so.centre_id, p_recorder, p_pin);
  if so.closed_at is not null then
    raise exception 'already closed';
  end if;
  if so.ccls_filed_at is null then
    raise exception 'cannot close before the CCLS filing is recorded';
  end if;
  if so.category = 'abuse_neglect_allegation' then
    if so.cas_reported_at is null then
      raise exception 'an abuse or neglect allegation cannot close without a recorded Children''s Aid Society report';
    end if;
  elsif not exists (
    select 1 from public.serious_occurrence_posting where serious_occurrence_id = p_occurrence
  ) then
    raise exception 'cannot close before the anonymised summary has been posted';
  end if;

  update public.serious_occurrence
  set status = 'closed', closed_at = now(), closed_by = recorder,
      closure_note = nullif(trim(coalesce(p_note, '')), '')
  where id = p_occurrence
  returning * into so;
  return so;
end;
$$;

-- ── the clock never relies on someone looking at a screen ───────────────────
-- Hourly: a Now alert to every supervisor/designate/licensee admin when an
-- unfiled occurrence has under 6 hours left, and again the moment it is
-- overdue. One of each, per occurrence.
create or replace function app.serious_occurrence_reminders()
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  so record;
begin
  for so in
    select * from public.serious_occurrence
    where status = 'open' and ccls_filed_at is null
      and (
        (deadline_warning_sent_at is null and now() >= ccls_deadline_at - interval '6 hours')
        or (overdue_notice_sent_at is null and now() >= ccls_deadline_at)
      )
  loop
    insert into public.notification (
      centre_id, recipient_person_id, channel, event_type, title, body,
      requires_acknowledgement, ref_id
    )
    select
      so.centre_id, pr.person_id, 'now', 'serious_occurrence',
      case when now() >= so.ccls_deadline_at
        then 'CCLS filing OVERDUE — serious occurrence'
        else 'CCLS filing due soon — serious occurrence' end,
      'The ' || replace(so.category, '_', ' ') || ' recorded ' ||
      to_char(so.aware_at, 'Mon FMDD HH24:MI') || ' must be filed in CCLS by ' ||
      to_char(so.ccls_deadline_at, 'Mon FMDD HH24:MI') || '. The app never files for you.',
      true, so.id
    from public.person_role pr
    where pr.centre_id = so.centre_id and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate');

    update public.serious_occurrence
    set deadline_warning_sent_at = coalesce(deadline_warning_sent_at, now()),
        overdue_notice_sent_at = case when now() >= ccls_deadline_at
          then coalesce(overdue_notice_sent_at, now()) else overdue_notice_sent_at end
    where id = so.id;
  end loop;
end;
$$;

select cron.schedule('serious-occurrence-clock', '15 * * * *', $$select app.serious_occurrence_reminders()$$);
