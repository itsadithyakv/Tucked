-- 0034 the daily written record actually drafts itself (s. 37).
--
-- The duty was already met: a dated entry exists for every operating day, the
-- incidents cross-reference themselves into it, and a named human closes it.
-- What did not exist was the DRAFT. app.dwr_skeleton wrote one line —
-- "Attendance: 39 children present. Staff on shift: 8. Nothing further
-- recorded." — and left the supervisor to write the day from memory at six in
-- the evening. That is the opposite of "boring inspections for operators".
--
-- What this changes:
--
--   * ONE COMPOSER, IN SQL. There was a second drafter in packages/domain
--     that nothing called; two implementations of the same prose is drift
--     waiting to happen, and the SQL one can see the whole day — outdoor
--     minutes, menu substitutions, sleep checks, medication, hazards — where
--     the other took nine hand-passed numbers. The composer is deterministic
--     and template-driven: NEVER AI (§9.14). A regulator reading this entry is
--     reading arithmetic over the day's records, not a model's summary.
--   * THE INCIDENTS ARE QUOTED, NOT RE-DERIVED. Accidents, drills, serious
--     occurrences, illness exclusions, hazards and short outdoor days already
--     write themselves into daily_written_record.refs as finished sentences,
--     at the moment they happen. The draft quotes those sentences verbatim
--     rather than reconstructing them, so the summary and the cross-reference
--     can never disagree.
--   * THE DRAFT IS RECOMPOSED, NEVER OVERWRITTEN IN PLACE. A supervisor's own
--     edits are theirs; regenerating is an explicit act, and it refuses once
--     the day is closed, because a closed record never changes.

create or replace function app.dwr_compose(p_centre uuid, p_date date)
returns text
language plpgsql stable security definer
set search_path = public
as $$
declare
  ctr public.centre;
  lines text[] := '{}';
  present integer;
  absent integer;
  staff integer;
  bit text;
  refs_text text;
  eventful boolean := false;
begin
  select * into ctr from public.centre where id = p_centre;
  if ctr.id is null then return null; end if;

  -- ── who was here ──────────────────────────────────────────────────────────
  select count(distinct ae.child_id) into present
  from public.attendance_event ae
  where ae.centre_id = p_centre and ae.attendance_date = p_date and ae.event_type = 'arrive';

  select count(distinct ae.child_id) into absent
  from public.attendance_event ae
  where ae.centre_id = p_centre and ae.attendance_date = p_date and ae.event_type = 'absent';

  select count(distinct ss.person_id) into staff
  from public.staff_shift ss
  where ss.centre_id = p_centre and ss.shift_date = p_date;

  lines := array_append(lines, format(
    '%s attended and %s on shift.%s',
    case when present = 1 then '1 child' else present || ' children' end,
    case when staff = 1 then '1 staff member' else staff || ' staff' end,
    case when absent > 0
      then ' ' || absent || case when absent = 1 then ' child was' else ' children were' end
           || ' marked absent.'
      else '' end
  ));

  -- ── outdoor play (s. 47) ──────────────────────────────────────────────────
  select string_agg(
           r.name || ' ' ||
           case when d.minutes >= 60
             then (d.minutes / 60) || ' h ' || lpad((d.minutes % 60)::text, 2, '0')
             else d.minutes || ' min' end,
           ', ' order by r.name)
    into bit
  from public.outdoor_day d
  join public.room r on r.id = d.room_id
  where d.centre_id = p_centre and d.outdoor_date = p_date;
  if bit is not null then
    lines := array_append(lines, 'Outdoor play: ' || bit || '.');
  end if;

  -- ── meals (ss. 42–44) ─────────────────────────────────────────────────────
  select string_agg(
           replace(s.meal, '_', ' ') || ' — ' || s.served ||
           coalesce(' instead of ' || s.planned, '') || ' (' || s.reason || ')',
           '; ' order by s.meal)
    into bit
  from public.menu_substitution s
  where s.centre_id = p_centre and s.served_on = p_date;
  lines := array_append(lines, case
    when bit is null then 'Meals were served as the posted menu.'
    else 'Meals followed the posted menu except: ' || bit || '.'
  end);

  -- ── sleep (s. 33.1) ───────────────────────────────────────────────────────
  select
    count(*) filter (where cl.log_type = 'nap_start'),
    count(*) filter (where cl.log_type = 'sleep_check')
  into present, absent -- reused as counters
  from public.care_log cl
  where cl.centre_id = p_centre and cl.log_date = p_date
    and cl.log_type in ('nap_start', 'sleep_check');
  if present > 0 or absent > 0 then
    lines := array_append(lines, format(
      'Sleep: %s rest %s, with %s direct visual %s recorded.',
      present, case when present = 1 then 'period' else 'periods' end,
      absent, case when absent = 1 then 'check' else 'checks' end
    ));
  end if;

  -- ── medication (s. 40) ────────────────────────────────────────────────────
  select
    count(*) filter (where not ma.self_administered),
    count(*) filter (where ma.self_administered)
  into present, absent
  from public.medication_administration ma
  where ma.centre_id = p_centre and ma.administered_date = p_date
    and ma.correction_of is null;
  if present > 0 or absent > 0 then
    lines := array_append(lines, format(
      'Medication: %s %s administered by staff%s. Every dose is in the medication log.',
      present, case when present = 1 then 'dose' else 'doses' end,
      case when absent > 0
        then ', ' || absent || case when absent = 1 then ' dose' else ' doses' end
             || ' self-administered'
        else '' end
    ));
  end if;

  -- ── supervision counts (s. 11) ────────────────────────────────────────────
  select count(*) into present
  from public.headcount_check h
  where h.centre_id = p_centre
    and (h.created_at at time zone ctr.timezone)::date = p_date;
  if present > 0 then
    lines := array_append(lines, format(
      'Face-to-name headcounts: %s recorded.', present
    ));
  end if;

  -- ── everything that happened, in the words it was recorded in ─────────────
  -- These sentences were written by the triggers at the moment of the event.
  -- Quoting them means the summary and the cross-reference can never disagree.
  select string_agg('• ' || (ref ->> 'note'), E'\n')
    into refs_text
  from public.daily_written_record d,
       lateral jsonb_array_elements(d.refs) ref
  where d.centre_id = p_centre and d.record_date = p_date and d.room_id is null
    and coalesce(ref ->> 'note', '') <> '';

  if refs_text is not null then
    eventful := true;
    lines := array_append(lines, '' || E'\n' || 'Recorded during the day:' || E'\n' || refs_text);
  end if;

  if not eventful then
    lines := array_append(lines, 'Nothing further to report — an uneventful day.');
  end if;

  return format(
    E'%s — %s\n\n%s',
    to_char(p_date, 'FMDay FMDD FMMonth YYYY'),
    ctr.name,
    array_to_string(lines, E'\n')
  );
end;
$$;

-- The 06:00 draft is still a skeleton by necessity: nothing has happened yet.
-- It now uses the same composer, so an early-morning read and a five-o'clock
-- read are the same shape.
create or replace function app.dwr_skeleton(p_centre uuid, p_date date)
returns text
language sql stable security definer
set search_path = public
as $$ select app.dwr_compose(p_centre, p_date) $$;

-- ── recompose on demand ─────────────────────────────────────────────────────
-- Explicit, because a supervisor's own edits are theirs. Refuses on a closed
-- day: a closed daily written record never changes (s. 37).
create or replace function public.regenerate_daily_record_draft(
  p_record uuid,
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
  if result.closed_at is not null then
    raise exception 'a closed daily written record never changes';
  end if;
  perform app.resolve_recorder(result.centre_id, p_recorder, p_pin);

  update public.daily_written_record
  set draft_text = app.dwr_compose(result.centre_id, result.record_date)
  where id = p_record
  returning * into result;
  return result;
end;
$$;

-- What the day would read like right now, without touching the stored draft —
-- so the console can show a live preview beside what was last saved.
create or replace function public.daily_record_preview(p_centre uuid, p_date date)
returns text
language sql stable security definer
set search_path = public
as $$
  select case
    when app.has_role(p_centre, array['supervisor', 'designate', 'licensee_admin']::public.role_id[])
      then app.dwr_compose(p_centre, p_date)
    else null
  end
$$;

-- ── one wording fix, now that these sentences are read in prose ─────────────
-- The illness cross-reference quoted the POLICY ("Vomiting — Excluded after
-- two episodes, or one with other symptoms.") where what the day's record
-- wants is what happened. The exclusion itself still holds the criteria; the
-- daily entry says who went home and why.
create or replace function app.health_exclusion_cross_reference()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  tz text;
  label text;
begin
  select c.timezone into tz from public.centre c where c.id = new.centre_id;
  select p.label into label from public.illness_policy p
  where p.centre_id = new.centre_id and p.symptom = new.symptom;

  perform app.dwr_append_ref(
    new.centre_id,
    (new.onset_at at time zone tz)::date,
    jsonb_build_object(
      'type', 'illness_exclusion',
      'exclusion_id', new.id,
      'note', (select split_part(ch.full_name, ' ', 1) from public.child ch where ch.id = new.child_id)
              || ' sent home unwell — ' || lower(coalesce(label, new.symptom))
              || coalesce(' (' || new.detail || ')', '')
              || '. Separated to ' || coalesce(new.separation_place, 'a quiet space') || '.'
    )
  );
  return new;
end;
$$;
