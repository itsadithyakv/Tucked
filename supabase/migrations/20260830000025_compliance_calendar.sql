-- 0025 compliance calendar (Parts 4 and 10 + adjacent recurring duties).
-- Fire drills, alarm and equipment tests, playground inspections against
-- CSA Z614 (daily / monthly / annual), policy reviews — each one a recurring
-- task whose completion is a WRITTEN RECORD: PIN-signed, note required,
-- append-only, audited. Plus the repair log: a hazard is recorded with what
-- was restricted, stays loud until resolved, and lands in the daily written
-- record (s. 37) because a hazard is a safety matter.
--   * Every centre gets the standard task set automatically (trigger on
--     centre creation; this migration backfills existing centres).
--   * A recorded fire-drill headcount (0018) completes the monthly fire-drill
--     task by itself — one drill, one record, both registers agree.
--   * The schedule advances from the COMPLETION date, so a late inspection
--     does not silently shift the next one later than its cadence allows.

create table public.compliance_task (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  slug text not null,
  title text not null,
  regulation text not null,
  cadence text not null check (cadence in ('daily', 'weekly', 'monthly', 'quarterly', 'annual')),
  last_completed_on date,
  next_due_on date not null default current_date,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  unique (centre_id, slug)
);

create table public.compliance_completion (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  task_id uuid not null references public.compliance_task (id),
  completed_on date not null default current_date,
  -- the written record itself — what was done, what was found
  note text not null,
  evidence_path text,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now()
);

create index compliance_completion_task on public.compliance_completion (task_id, completed_on desc);

-- the repair log: hazards restricted until fixed (Part 10)
create table public.compliance_issue (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  task_id uuid references public.compliance_task (id),
  description text not null,
  restricted_area text,
  identified_on date not null default current_date,
  recorded_by uuid not null references public.person (id),
  resolved_at timestamptz,
  resolved_by uuid references public.person (id),
  resolved_note text,
  created_at timestamptz not null default now()
);

-- ── visibility: the whole care team sees the schedule and the hazards ───────
alter table public.compliance_task enable row level security;
alter table public.compliance_completion enable row level security;
alter table public.compliance_issue enable row level security;

create policy compliance_task_select on public.compliance_task
  for select using (centre_id in (select app.care_centre_ids()));
create policy compliance_completion_select on public.compliance_completion
  for select using (centre_id in (select app.care_centre_ids()));
create policy compliance_issue_select on public.compliance_issue
  for select using (centre_id in (select app.care_centre_ids()));
-- Writes via RPCs only.

create trigger compliance_completion_no_delete before delete on public.compliance_completion
  for each row execute function app.block_mutation();
create trigger compliance_issue_no_delete before delete on public.compliance_issue
  for each row execute function app.block_mutation();
create trigger compliance_task_audit after insert or update on public.compliance_task
  for each row execute function app.audit_row();
create trigger compliance_completion_audit after insert on public.compliance_completion
  for each row execute function app.audit_row();
create trigger compliance_issue_audit after insert or update on public.compliance_issue
  for each row execute function app.audit_row();

-- ── the standard task set ───────────────────────────────────────────────────
create or replace function app.seed_compliance_tasks(p_centre uuid)
returns void
language sql security definer
set search_path = public
as $$
  insert into public.compliance_task (centre_id, slug, title, regulation, cadence, active, notes) values
    (p_centre, 'fire_drill', 'Fire drill', 'Part 4', 'monthly', true,
     'Completes itself when a fire-drill headcount is recorded on the evacuation screen.'),
    (p_centre, 'fire_alarm_test', 'Fire alarm & equipment test', 'Part 4', 'monthly', true, null),
    (p_centre, 'fire_procedure_posting', 'Fire procedure approved by the fire chief & posted in every room', 'Part 4', 'annual', true, null),
    (p_centre, 'emergency_policy_review', 'Emergency management policy review (lockdown, evacuation, shelter)', 'Part 4', 'annual', true, null),
    (p_centre, 'playground_daily', 'Playground daily visual check', 'Part 10 / CSA Z614', 'daily', true, null),
    (p_centre, 'playground_monthly', 'Playground monthly inspection', 'Part 10 / CSA Z614', 'monthly', true, null),
    (p_centre, 'playground_annual', 'Playground annual inspection (certified inspector for fixed structures)', 'Part 10 / CSA Z614', 'annual', true, null),
    (p_centre, 'first_aid_kit_check', 'First-aid kit inspection (contents, locations, manual)', 'Part 10', 'monthly', true, null),
    (p_centre, 'water_temperature_check', 'Water temperature check (max 49°C where children reach)', 'Part 10', 'monthly', true, null),
    (p_centre, 'anaphylaxis_policy_review', 'Anaphylaxis policy annual staff review', 's. 39', 'annual', true, null),
    (p_centre, 'program_statement_review', 'Program statement annual review', 's. 46', 'annual', true, null),
    (p_centre, 'sleep_monitor_check', 'Electronic sleep monitors daily check', 's. 33.1', 'daily', false,
     'Activate only if the centre uses electronic sleep monitors — they never replace direct visual checks.')
  on conflict (centre_id, slug) do nothing;
$$;

create or replace function app.centre_seed_compliance()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  perform app.seed_compliance_tasks(new.id);
  return new;
end;
$$;

create trigger centre_seed_compliance
  after insert on public.centre
  for each row execute function app.centre_seed_compliance();

-- backfill every existing centre
select app.seed_compliance_tasks(c.id) from public.centre c;

-- ── schedule arithmetic ─────────────────────────────────────────────────────
create or replace function app.next_due(p_cadence text, p_from date)
returns date
language sql immutable
as $$
  select case p_cadence
    when 'daily' then p_from + 1
    when 'weekly' then p_from + 7
    when 'monthly' then (p_from + interval '1 month')::date
    when 'quarterly' then (p_from + interval '3 months')::date
    else (p_from + interval '1 year')::date
  end
$$;

create or replace function app.complete_task(p_task uuid, p_note text, p_completed_on date, p_recorder uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  task public.compliance_task;
begin
  select * into task from public.compliance_task where id = p_task;
  if task.id is null then raise exception 'compliance task not found'; end if;
  if coalesce(trim(p_note), '') = '' then
    raise exception 'the completion IS the written record — say what was done and what was found';
  end if;
  if p_completed_on > current_date then
    raise exception 'a completion cannot be dated in the future';
  end if;

  insert into public.compliance_completion (centre_id, task_id, completed_on, note, recorded_by)
  values (task.centre_id, p_task, p_completed_on, trim(p_note), p_recorder);

  update public.compliance_task
  set last_completed_on = p_completed_on,
      next_due_on = app.next_due(cadence, p_completed_on)
  where id = p_task;
end;
$$;

-- ── RPCs ────────────────────────────────────────────────────────────────────
create or replace function public.complete_compliance_task(
  p_task uuid,
  p_note text,
  p_completed_on date,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  task public.compliance_task;
  recorder uuid;
begin
  select * into task from public.compliance_task where id = p_task;
  if task.id is null then raise exception 'compliance task not found'; end if;
  recorder := app.resolve_recorder(task.centre_id, p_recorder, p_pin);
  perform app.complete_task(p_task, p_note, coalesce(p_completed_on, current_date), recorder);
end;
$$;

create or replace function public.record_compliance_issue(
  p_centre uuid,
  p_task uuid,
  p_description text,
  p_restricted_area text,
  p_recorder uuid,
  p_pin text
) returns public.compliance_issue
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.compliance_issue;
  tz text;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if coalesce(trim(p_description), '') = '' then
    raise exception 'describe the hazard';
  end if;

  insert into public.compliance_issue (centre_id, task_id, description, restricted_area, recorded_by)
  values (p_centre, p_task, trim(p_description), nullif(trim(coalesce(p_restricted_area, '')), ''), recorder)
  returning * into result;

  -- a hazard is a safety matter: it belongs in the daily written record
  select c.timezone into tz from public.centre c where c.id = p_centre;
  perform app.dwr_append_ref(
    p_centre,
    (now() at time zone tz)::date,
    jsonb_build_object(
      'type', 'premises_issue',
      'issue_id', result.id,
      'note', 'Premises hazard recorded — ' || trim(p_description)
        || coalesce(' (restricted: ' || result.restricted_area || ')', '')
    )
  );
  return result;
end;
$$;

create or replace function public.resolve_compliance_issue(
  p_issue uuid,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  issue public.compliance_issue;
  recorder uuid;
begin
  select * into issue from public.compliance_issue where id = p_issue;
  if issue.id is null then raise exception 'issue not found'; end if;
  recorder := app.resolve_recorder(issue.centre_id, p_recorder, p_pin);
  if issue.resolved_at is not null then raise exception 'already resolved'; end if;
  if coalesce(trim(p_note), '') = '' then
    raise exception 'say what was repaired or changed before lifting the restriction';
  end if;
  update public.compliance_issue
  set resolved_at = now(), resolved_by = recorder, resolved_note = trim(p_note)
  where id = p_issue;
end;
$$;

-- Supervisors switch optional tasks on and off (e.g. sleep monitors).
create or replace function public.set_compliance_task_active(
  p_task uuid,
  p_active boolean,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  task public.compliance_task;
  recorder uuid;
begin
  select * into task from public.compliance_task where id = p_task;
  if task.id is null then raise exception 'compliance task not found'; end if;
  recorder := app.resolve_recorder(task.centre_id, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = task.centre_id and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate')
  ) then
    raise exception 'only centre leadership changes the compliance schedule';
  end if;
  update public.compliance_task set active = p_active where id = p_task;
end;
$$;

-- ── one drill, one record: the headcount completes the task ─────────────────
create or replace function app.headcount_completes_drill()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  task_id uuid;
begin
  if new.kind = 'evacuation_drill' then
    select id into task_id from public.compliance_task
    where centre_id = new.centre_id and slug = 'fire_drill' and active;
    if task_id is not null then
      perform app.complete_task(
        task_id,
        'Fire drill — ' || new.counted || ' of ' || new.expected ||
          ' accounted for; see the headcount record for the muster.',
        current_date,
        new.recorded_by
      );
    end if;
  end if;
  return new;
end;
$$;

create trigger headcount_completes_drill
  after insert on public.headcount_check
  for each row execute function app.headcount_completes_drill();
