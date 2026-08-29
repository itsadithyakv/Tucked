-- 0006 care log (daily sheets) — meals, bottles, naps, sleep checks (s. 33.1),
-- diapers/toileting, outdoor time, arrival health observation (s. 32),
-- activities, notes, photos. Same write model as attendance: PIN-verified
-- RPCs, append-only with corrections, audited, payload validated per type.

create type public.care_log_type as enum (
  'meal', 'bottle', 'nap_start', 'nap_end', 'sleep_check',
  'diaper', 'toilet', 'outdoor', 'health_observation', 'activity', 'note', 'photo'
);

create table public.care_log (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  room_id uuid not null references public.room (id),
  log_type public.care_log_type not null,
  logged_at timestamptz not null,
  log_date date not null, -- derived: centre-local day
  payload jsonb not null default '{}'::jsonb,
  recorded_by uuid not null references public.person (id),
  device_id text,
  offline_recorded_at timestamptz,
  offline_synced_at timestamptz,
  correction_of uuid references public.care_log (id),
  correction_reason text,
  created_at timestamptz not null default now(),
  constraint care_log_correction_needs_reason
    check ((correction_of is null) = (correction_reason is null))
);

create index care_log_child_day on public.care_log (child_id, log_date);
create index care_log_centre_day_type on public.care_log (centre_id, log_date, log_type);

alter table public.care_log enable row level security;

create policy care_log_select on public.care_log
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = care_log.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
-- No client write policies: RPCs only.

-- ── payload validation (mirrors packages/domain careLog schemas — change both) ─
create or replace function app.validate_care_log_payload(p_type public.care_log_type, p jsonb)
returns boolean
language sql immutable
as $$
  select case p_type
    when 'meal' then
      p ? 'meal' and p ->> 'meal' in ('breakfast', 'lunch', 'snack_am', 'snack_pm')
      and p ? 'eaten' and p ->> 'eaten' in ('none', 'some', 'most', 'all')
    when 'bottle' then
      p ? 'amount_ml' and jsonb_typeof(p -> 'amount_ml') = 'number'
      and p ? 'kind' and p ->> 'kind' in ('breast_milk', 'formula', 'milk', 'water')
    when 'nap_start' then true
    when 'nap_end' then true
    when 'sleep_check' then
      p ? 'breathing_ok' and jsonb_typeof(p -> 'breathing_ok') = 'boolean'
    when 'diaper' then
      p ? 'kind' and p ->> 'kind' in ('wet', 'soiled', 'both', 'dry')
    when 'toilet' then
      p ? 'kind' and p ->> 'kind' in ('urine', 'bm', 'attempt', 'accident')
    when 'outdoor' then
      (p ? 'minutes' and jsonb_typeof(p -> 'minutes') = 'number')
      or p ? 'skipped_reason'
    when 'health_observation' then
      p ? 'observation' and length(p ->> 'observation') > 0
    when 'activity' then
      p ? 'description' and length(p ->> 'description') > 0
    when 'note' then
      p ? 'text' and length(p ->> 'text') > 0
    when 'photo' then
      p ? 'storage_path' and p ? 'captured_at'
  end
$$;

-- ── rule trigger ────────────────────────────────────────────────────────────
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

create trigger care_log_rules
  before insert or update on public.care_log
  for each row execute function app.care_log_rules();

create trigger care_log_no_delete
  before delete on public.care_log
  for each row execute function app.block_mutation();

create trigger care_log_audit
  after insert on public.care_log
  for each row execute function app.audit_row();

-- ── write RPCs ──────────────────────────────────────────────────────────────
create or replace function public.record_care_log(
  p_centre uuid,
  p_child uuid,
  p_room uuid,
  p_type public.care_log_type,
  p_logged_at timestamptz,
  p_payload jsonb,
  p_recorder uuid,
  p_pin text,
  p_offline_recorded_at timestamptz default null,
  p_device text default null,
  p_correction_of uuid default null,
  p_correction_reason text default null
) returns public.care_log
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.care_log;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  insert into public.care_log (
    centre_id, child_id, room_id, log_type, logged_at, log_date, payload,
    recorded_by, device_id, offline_recorded_at, offline_synced_at,
    correction_of, correction_reason
  ) values (
    p_centre, p_child, p_room, p_type, p_logged_at, '1970-01-01', coalesce(p_payload, '{}'::jsonb),
    recorder, p_device, p_offline_recorded_at,
    case when p_offline_recorded_at is null then null else now() end,
    p_correction_of, p_correction_reason
  ) returning * into result;
  return result;
end;
$$;

-- Bulk per-room entry: one tap logs the same event for many children
-- ("log once, appears everywhere" — the educator time-saving wedge).
create or replace function public.record_care_log_bulk(
  p_centre uuid,
  p_children uuid[],
  p_room uuid,
  p_type public.care_log_type,
  p_logged_at timestamptz,
  p_payload jsonb,
  p_recorder uuid,
  p_pin text,
  p_offline_recorded_at timestamptz default null,
  p_device text default null
) returns setof public.care_log
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  kid uuid;
  result public.care_log;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  foreach kid in array p_children loop
    insert into public.care_log (
      centre_id, child_id, room_id, log_type, logged_at, log_date, payload,
      recorded_by, device_id, offline_recorded_at, offline_synced_at
    ) values (
      p_centre, kid, p_room, p_type, p_logged_at, '1970-01-01', coalesce(p_payload, '{}'::jsonb),
      recorder, p_device, p_offline_recorded_at,
      case when p_offline_recorded_at is null then null else now() end
    ) returning * into result;
    return next result;
  end loop;
end;
$$;
