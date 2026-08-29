-- 0009 medication (s. 40): written parent authorisation with dose AND a
-- schedule or specific symptoms ("as needed" alone is insufficient); original-
-- container checklist; one designated person; EVERY administration logged —
-- including blanket-authorised items (sunscreen, diaper cream, …); expired
-- medication never administered; self-administered doses summarised in the
-- daily written record (s. 37).

create type public.medication_kind as enum (
  'prescription', 'otc',
  -- blanket-authorised items — still logged on every administration
  'sunscreen', 'moisturiser', 'lip_balm', 'insect_repellent', 'hand_sanitiser', 'diaper_cream'
);

create or replace function app.medication_is_blanket(k public.medication_kind)
returns boolean
language sql immutable
as $$ select k not in ('prescription', 'otc') $$;

create table public.medication_authorisation (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  kind public.medication_kind not null,
  drug_name text not null,
  din text,
  dose text,
  schedule text,
  symptoms text,
  label_photo_path text,
  original_container_checked boolean not null default false,
  storage_instructions text,
  expiry_date date,
  designated_person_id uuid references public.person (id),
  parent_authorised_by uuid not null references public.person (id),
  parent_authorised_at timestamptz not null default now(),
  authorisation_evidence text not null, -- e.g. 'signed paper form on file', upload path
  recorded_by uuid not null references public.person (id),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  -- s. 40: non-blanket medication needs a dose AND a schedule or specific
  -- symptoms. "As needed" with neither is not an authorisation.
  constraint medication_needs_dose_and_schedule_or_symptoms
    check (
      app.medication_is_blanket(kind)
      or (dose is not null and (schedule is not null or symptoms is not null))
    )
);

create table public.medication_administration (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  authorisation_id uuid not null references public.medication_authorisation (id),
  administered_at timestamptz not null,
  administered_date date not null, -- derived: centre-local day
  dose_given text,
  outcome text,
  self_administered boolean not null default false,
  administered_by uuid not null references public.person (id),
  device_id text,
  offline_recorded_at timestamptz,
  offline_synced_at timestamptz,
  correction_of uuid references public.medication_administration (id),
  correction_reason text,
  created_at timestamptz not null default now(),
  constraint med_admin_correction_needs_reason
    check ((correction_of is null) = (correction_reason is null))
);

create index med_admin_child_day on public.medication_administration (child_id, administered_date);

alter table public.medication_authorisation enable row level security;
alter table public.medication_administration enable row level security;

create policy med_auth_select on public.medication_authorisation
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = medication_authorisation.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
create policy med_admin_select on public.medication_administration
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = medication_administration.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
-- Writes via RPCs only.

-- ── rules ───────────────────────────────────────────────────────────────────
create or replace function app.medication_authorisation_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if not exists (select 1 from public.child ch where ch.id = new.child_id and ch.centre_id = new.centre_id) then
      raise exception 'child is not enrolled at this centre';
    end if;
    -- the authorising parent must be a consenting household member of the child
    if not exists (
      select 1 from public.child_household ch
      join public.household_member hm on hm.household_id = ch.household_id
      where ch.child_id = new.child_id
        and hm.person_id = new.parent_authorised_by
        and hm.revoked_at is null
        and hm.can_consent
    ) then
      raise exception 'authorisation must come from a consenting household member';
    end if;
    return new;
  end if;
  -- Parent-signed content is immutable; the only permitted change is revocation.
  if row(new.centre_id, new.child_id, new.kind, new.drug_name, new.din, new.dose,
         new.schedule, new.symptoms, new.parent_authorised_by, new.parent_authorised_at,
         new.authorisation_evidence, new.recorded_by)
     is distinct from
     row(old.centre_id, old.child_id, old.kind, old.drug_name, old.din, old.dose,
         old.schedule, old.symptoms, old.parent_authorised_by, old.parent_authorised_at,
         old.authorisation_evidence, old.recorded_by) then
    raise exception 'a medication authorisation is never edited; revoke it and record a new one';
  end if;
  return new;
end;
$$;

create trigger medication_authorisation_rules
  before insert or update on public.medication_authorisation
  for each row execute function app.medication_authorisation_rules();

create or replace function app.medication_administration_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  tz text;
  auth public.medication_authorisation;
begin
  if tg_op = 'UPDATE' then
    raise exception 'medication administrations are never updated; record a correction';
  end if;

  select c.timezone into tz from public.centre c where c.id = new.centre_id;
  new.administered_date := (new.administered_at at time zone tz)::date;

  select * into auth from public.medication_authorisation a where a.id = new.authorisation_id;
  if auth.id is null or auth.child_id <> new.child_id or auth.centre_id <> new.centre_id then
    raise exception 'administration requires an authorisation for this child';
  end if;
  if auth.revoked_at is not null then
    raise exception 'authorisation has been revoked';
  end if;
  if auth.expiry_date is not null and auth.expiry_date < new.administered_date then
    raise exception 'medication is expired; do not administer';
  end if;
  return new;
end;
$$;

create trigger medication_administration_rules
  before insert or update on public.medication_administration
  for each row execute function app.medication_administration_rules();

create trigger med_auth_no_delete
  before delete on public.medication_authorisation
  for each row execute function app.block_mutation();
create trigger med_admin_no_delete
  before delete on public.medication_administration
  for each row execute function app.block_mutation();

create trigger med_auth_audit
  after insert or update on public.medication_authorisation
  for each row execute function app.audit_row();
create trigger med_admin_audit
  after insert on public.medication_administration
  for each row execute function app.audit_row();

-- s. 37: self-administered medication is summarised in the daily written record.
create or replace function app.med_admin_cross_reference()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.self_administered then
    perform app.dwr_append_ref(
      new.centre_id,
      new.administered_date,
      jsonb_build_object('type', 'self_administered_medication', 'administration_id', new.id)
    );
  end if;
  return new;
end;
$$;

create trigger med_admin_cross_reference
  after insert on public.medication_administration
  for each row execute function app.med_admin_cross_reference();

-- ── RPCs ────────────────────────────────────────────────────────────────────
create or replace function public.record_medication_authorisation(
  p_centre uuid,
  p_child uuid,
  p_kind public.medication_kind,
  p_drug_name text,
  p_din text,
  p_dose text,
  p_schedule text,
  p_symptoms text,
  p_label_photo_path text,
  p_container_checked boolean,
  p_storage text,
  p_expiry date,
  p_designated_person uuid,
  p_parent uuid,
  p_evidence text,
  p_recorder uuid,
  p_pin text
) returns public.medication_authorisation
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.medication_authorisation;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  insert into public.medication_authorisation (
    centre_id, child_id, kind, drug_name, din, dose, schedule, symptoms,
    label_photo_path, original_container_checked, storage_instructions,
    expiry_date, designated_person_id, parent_authorised_by,
    authorisation_evidence, recorded_by
  ) values (
    p_centre, p_child, p_kind, p_drug_name, p_din, p_dose, p_schedule, p_symptoms,
    p_label_photo_path, coalesce(p_container_checked, false), p_storage,
    p_expiry, p_designated_person, p_parent, p_evidence, recorder
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.revoke_medication_authorisation(
  p_authorisation uuid,
  p_recorder uuid,
  p_pin text
) returns public.medication_authorisation
language plpgsql security definer
set search_path = public
as $$
declare
  result public.medication_authorisation;
begin
  select * into result from public.medication_authorisation where id = p_authorisation;
  if result.id is null then raise exception 'authorisation not found'; end if;
  perform app.resolve_recorder(result.centre_id, p_recorder, p_pin);
  update public.medication_authorisation set revoked_at = now() where id = p_authorisation
  returning * into result;
  return result;
end;
$$;

create or replace function public.record_medication_administration(
  p_authorisation uuid,
  p_administered_at timestamptz,
  p_dose_given text,
  p_outcome text,
  p_recorder uuid,
  p_pin text,
  p_self_administered boolean default false,
  p_offline_recorded_at timestamptz default null,
  p_device text default null,
  p_correction_of uuid default null,
  p_correction_reason text default null
) returns public.medication_administration
language plpgsql security definer
set search_path = public
as $$
declare
  auth public.medication_authorisation;
  recorder uuid;
  result public.medication_administration;
begin
  select * into auth from public.medication_authorisation where id = p_authorisation;
  if auth.id is null then raise exception 'authorisation not found'; end if;
  recorder := app.resolve_recorder(auth.centre_id, p_recorder, p_pin);
  insert into public.medication_administration (
    centre_id, child_id, authorisation_id, administered_at, administered_date,
    dose_given, outcome, self_administered, administered_by, device_id,
    offline_recorded_at, offline_synced_at, correction_of, correction_reason
  ) values (
    auth.centre_id, auth.child_id, p_authorisation, p_administered_at, '1970-01-01',
    p_dose_given, p_outcome, coalesce(p_self_administered, false), recorder, p_device,
    p_offline_recorded_at,
    case when p_offline_recorded_at is null then null else now() end,
    p_correction_of, p_correction_reason
  ) returning * into result;
  return result;
end;
$$;
