-- 0022 retention anonymisation (s. 72(5): children's records 3 years after
-- discharge; O. Reg. 138/15 s. 27.1: financial records 6 years). The rules:
--   * NOTHING is touched before its clock matures — the anonymiser refuses,
--     even when called directly (never-do §9.14: no early deletion, ever).
--   * "Purge" means anonymise: the regulated record rows all SURVIVE
--     (attendance, care logs, accident reports, plans) — what disappears is
--     the child's identity: name, birth day/month, photos, parents' contact
--     content, and free text that could name them.
--   * Financial records (billing_event) are append-only and are simply never
--     deleted — the 6-year floor is satisfied by keeping them.
--   * The immutability triggers (care logs never updated, acknowledged
--     accident reports never change, plan content never edited) stay in force
--     for everyone; they recognise exactly one writer — the anonymiser —
--     via a transaction-local flag only it sets. Every scrub is audited.

create or replace function app.is_anonymising()
returns boolean
language sql stable
as $$ select coalesce(current_setting('app.anonymising', true), '') = 'on' $$;

-- ── the escape hatch, added to the three immutability triggers ──────────────
create or replace function app.care_log_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  tz text;
  dob date;
  preset public.age_group_preset;
begin
  if tg_op = 'UPDATE' then
    if app.is_anonymising() then
      return new; -- retention anonymisation only; s. 72(5)
    end if;
    raise exception 'care logs are never updated; record a correction';
  end if;

  select c.timezone into tz from public.centre c where c.id = new.centre_id;
  new.log_date := (new.logged_at at time zone tz)::date;

  select ch.date_of_birth into dob from public.child ch
  where ch.id = new.child_id and ch.centre_id = new.centre_id;
  if dob is null then
    raise exception 'child is not enrolled at this centre';
  end if;

  if not app.validate_care_log_payload(new.log_type, new.payload) then
    raise exception 'invalid payload for care log type %', new.log_type;
  end if;

  -- s. 33.1: direct visual sleep checks are for children under 24 months in
  -- infant, toddler or family rooms; recording one elsewhere is an error, so
  -- the record can never *appear* to satisfy a rule that does not apply.
  if new.log_type = 'sleep_check' then
    select ag.preset into preset
    from public.room r join public.age_group ag on ag.id = r.age_group_id
    where r.id = new.room_id;
    if preset not in ('infant', 'toddler', 'family') then
      raise exception 'sleep checks apply to infant, toddler or family rooms only';
    end if;
    if dob + interval '24 months' <= new.log_date then
      raise exception 'sleep checks apply to children under 24 months';
    end if;
  end if;

  if new.correction_of is not null and not exists (
    select 1 from public.care_log cl
    where cl.id = new.correction_of and cl.child_id = new.child_id
  ) then
    raise exception 'correction must reference a log for the same child';
  end if;

  return new;
end;
$$;

create or replace function app.accident_report_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  tz text;
begin
  if tg_op = 'INSERT' then
    select c.timezone into tz from public.centre c where c.id = new.centre_id;
    new.occurred_date := (new.occurred_at at time zone tz)::date;
    if not exists (select 1 from public.child ch where ch.id = new.child_id and ch.centre_id = new.centre_id) then
      raise exception 'child is not enrolled at this centre';
    end if;
    return new;
  end if;

  if app.is_anonymising() then
    return new; -- retention anonymisation only; s. 72(5)
  end if;

  -- The only permitted change to a report is the parent acknowledgement.
  if old.parent_ack_at is not null then
    raise exception 'an acknowledged accident report never changes';
  end if;
  if row(new.centre_id, new.child_id, new.occurred_at, new.occurred_date, new.location,
         new.description, new.injury, new.severity, new.first_aid, new.head_injury,
         new.concussion_watch_note, new.completed_by)
     is distinct from
     row(old.centre_id, old.child_id, old.occurred_at, old.occurred_date, old.location,
         old.description, old.injury, old.severity, old.first_aid, old.head_injury,
         old.concussion_watch_note, old.completed_by) then
    raise exception 'accident reports are never edited; only the parent acknowledgement may be added';
  end if;
  return new;
end;
$$;

create or replace function app.individualised_plan_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.child ch where ch.id = new.child_id and ch.centre_id = new.centre_id) then
      raise exception 'child is not enrolled at this centre';
    end if;
    if coalesce(trim(new.condition), '') = '' or coalesce(trim(new.developed_with), '') = '' then
      raise exception 'a plan names the condition and who it was developed with — never blank';
    end if;
    if new.plan_type = 'anaphylaxis' then
      if coalesce(array_length(new.allergens, 1), 0) = 0 then
        raise exception 'an anaphylaxis plan must name its allergens';
      end if;
      if coalesce(trim(new.signs), '') = '' or coalesce(trim(new.emergency_procedure), '') = '' then
        raise exception 'an anaphylaxis plan must describe the signs of a reaction and the emergency procedure';
      end if;
    elsif new.plan_type = 'medical_needs' then
      if coalesce(trim(new.emergency_procedure), '') = '' then
        raise exception 'a medical-needs plan must include its emergency procedure';
      end if;
    elsif new.plan_type = 'special_needs' then
      if coalesce(trim(new.supports), '') = '' then
        raise exception 'a special-needs plan must describe the supports and strategies';
      end if;
    end if;
  end if;

  -- s. 52: no implementation before agreement.
  if new.status = 'active' and new.parent_agreed_at is null then
    raise exception 'a plan cannot be active before a parent agreement is recorded';
  end if;

  if tg_op = 'UPDATE' and not app.is_anonymising() then
    -- plan content is immutable; only status/agreement/lifecycle fields move
    if row(new.centre_id, new.child_id, new.plan_type, new.version, new.condition,
           new.allergens, new.signs, new.emergency_procedure, new.exposure_reduction,
           new.devices_instructions, new.supports, new.evacuation_procedure,
           new.developed_with, new.recorded_by)
       is distinct from
       row(old.centre_id, old.child_id, old.plan_type, old.version, old.condition,
           old.allergens, old.signs, old.emergency_procedure, old.exposure_reduction,
           old.devices_instructions, old.supports, old.evacuation_procedure,
           old.developed_with, old.recorded_by) then
      raise exception 'plan content is never edited; record a new version that supersedes this one';
    end if;
  end if;
  return new;
end;
$$;

-- ── the anonymiser ──────────────────────────────────────────────────────────
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

  -- photos leave entirely (profile + gallery); the storage guard against
  -- accidental SQL deletes recognises the same explicit-intent pattern
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects
  where bucket_id = 'photos' and split_part(name, '/', 2) = p_child::text;
  perform set_config('storage.allow_delete_query', 'false', true);

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

-- ── the sweep grows teeth ───────────────────────────────────────────────────
-- Nightly (02:30, scheduled in 0012): anonymise every mature clock. Still
-- returns how many were processed. Rows before their date are never touched.
create or replace function app.run_retention_sweep()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  clock record;
  n integer := 0;
begin
  for clock in
    select subject_id from public.retention_clock
    where kind = 'childrens_record' and purge_after <= current_date and anonymised_at is null
  loop
    perform app.anonymise_child(clock.subject_id::uuid);
    n := n + 1;
  end loop;
  return n;
end;
$$;
