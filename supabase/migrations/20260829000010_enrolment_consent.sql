-- 0010 children's record items (s. 72(1)) and consent (s. 73).
-- Every s. 72(1) item is a typed row whose status is provided /
-- not_applicable / parent_declined — never blank. Enrolment is complete when
-- every item has a non-missing status and the required-for-care consent is
-- granted; OPTIONAL consents can all be declined and enrolment still
-- completes (s. 73 — never a condition of enrolment).

create type public.record_item_type as enum (
  'application',            -- 1  signed application for enrolment
  'identity',               -- 2  name, date of birth, home address
  'parent_contacts',        -- 3  parents' names, addresses, phone numbers
  'emergency_contact',      -- 4  emergency address & phone during care hours
  'release_persons',        -- 5  persons the child may be released to
  'admission',              -- 6  date of admission
  'discharge',              -- 7  date of discharge (n/a while enrolled)
  'health_immunisation',    -- 8  health history, conditions, allergies; immunisation/exemption
  'symptoms_log',           -- 9  ongoing ill-health symptoms log
  'medication_instructions',-- 10 signed instructions for medication
  'care_instructions'       -- 11 signed diet / rest / activity instructions
);

create type public.record_item_status as enum ('missing', 'provided', 'not_applicable', 'parent_declined');

create table public.child_record_item (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  item_type public.record_item_type not null,
  status public.record_item_status not null default 'missing',
  content jsonb not null default '{}'::jsonb, -- structured value (e.g. allergies list feeds the evacuation screen)
  evidence_path text,
  updated_by uuid references public.person (id),
  updated_at timestamptz not null default now(),
  verified_by uuid references public.person (id), -- supervisor verification
  verified_at timestamptz,
  unique (child_id, item_type)
);

create type public.consent_type as enum (
  'care_required',          -- the one consent required for care itself
  'photo_internal', 'photo_group', 'photo_third_party', 'social_media',
  'field_trip', 'sunscreen_blanket', 'diaper_cream_blanket', 'data_sharing_professional'
);

create table public.consent (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  consent_type public.consent_type not null,
  purpose text not null,
  status text not null check (status in ('granted', 'declined')),
  granted_by uuid not null references public.person (id),
  granted_at timestamptz not null default now(),
  expires_at timestamptz, -- dated, time-limited consents (trips, events)
  revoked_at timestamptz,
  evidence text,
  created_at timestamptz not null default now()
);

create index consent_child_type on public.consent (child_id, consent_type);

create table public.enrolment_invite (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  household_id uuid not null references public.household (id),
  email text not null,
  token uuid not null default gen_random_uuid(),
  expires_at timestamptz not null default now() + interval '14 days',
  completed_at timestamptz,
  created_by uuid references public.person (id),
  created_at timestamptz not null default now()
);

alter table public.child_record_item enable row level security;
alter table public.consent enable row level security;
alter table public.enrolment_invite enable row level security;

create policy record_item_select on public.child_record_item
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = child_record_item.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
create policy consent_select on public.consent
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = consent.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
create policy invite_select on public.enrolment_invite
  for select using (centre_id in (select app.care_centre_ids()));
-- Writes via RPCs only.

create trigger record_item_audit
  after insert or update on public.child_record_item
  for each row execute function app.audit_row();
create trigger consent_audit
  after insert or update on public.consent
  for each row execute function app.audit_row();
create trigger record_item_no_delete
  before delete on public.child_record_item
  for each row execute function app.block_mutation();
create trigger consent_no_delete
  before delete on public.consent
  for each row execute function app.block_mutation();

-- ── helpers ─────────────────────────────────────────────────────────────────
create or replace function app.is_consenting_member(p_person uuid, p_child uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.child_household ch
    join public.household_member hm on hm.household_id = ch.household_id
    where ch.child_id = p_child
      and hm.person_id = p_person
      and hm.revoked_at is null
      and hm.can_consent
  )
$$;

-- s. 72(1) + s. 73: complete when all 11 items have a non-missing status and
-- required-for-care consent stands. Optional consents NEVER gate this.
create or replace function public.enrolment_complete(p_child uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select
    (select count(*) from public.child_record_item i
     where i.child_id = p_child and i.status <> 'missing')
      = (select count(*) from unnest(enum_range(null::public.record_item_type)))
    and exists (
      select 1 from public.consent c
      where c.child_id = p_child
        and c.consent_type = 'care_required'
        and c.status = 'granted'
        and c.revoked_at is null
    )
$$;

-- Seed the 11 item rows for a child (idempotent).
create or replace function app.ensure_record_items(p_centre uuid, p_child uuid)
returns void
language sql security definer
set search_path = public
as $$
  insert into public.child_record_item (centre_id, child_id, item_type)
  select p_centre, p_child, t
  from unnest(enum_range(null::public.record_item_type)) as t
  on conflict (child_id, item_type) do nothing
$$;

-- ── RPCs ────────────────────────────────────────────────────────────────────
-- A consenting household member completes their child's record (the invite
-- flow); staff may also record items (paper forms) with a PIN.
create or replace function public.complete_record_item(
  p_child uuid,
  p_item public.record_item_type,
  p_status public.record_item_status,
  p_content jsonb,
  p_evidence_path text default null
) returns public.child_record_item
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid;
  centre uuid;
  result public.child_record_item;
begin
  me := app.current_person_id();
  select ch.centre_id into centre from public.child ch where ch.id = p_child;
  if centre is null then raise exception 'child not found'; end if;
  if p_status = 'missing' then
    raise exception 'an item is completed as provided, not applicable, or parent declined — never blank';
  end if;
  if not app.is_consenting_member(me, p_child) then
    raise exception 'only a consenting household member may complete the record' using errcode = '42501';
  end if;
  perform app.ensure_record_items(centre, p_child);
  update public.child_record_item
  set status = p_status,
      content = coalesce(p_content, '{}'::jsonb),
      evidence_path = coalesce(p_evidence_path, evidence_path),
      updated_by = me,
      updated_at = now(),
      verified_by = null, -- any change re-opens verification
      verified_at = null
  where child_id = p_child and item_type = p_item
  returning * into result;
  return result;
end;
$$;

create or replace function public.staff_record_item(
  p_child uuid,
  p_item public.record_item_type,
  p_status public.record_item_status,
  p_content jsonb,
  p_recorder uuid,
  p_pin text,
  p_evidence_path text default null
) returns public.child_record_item
language plpgsql security definer
set search_path = public
as $$
declare
  centre uuid;
  recorder uuid;
  result public.child_record_item;
begin
  select ch.centre_id into centre from public.child ch where ch.id = p_child;
  if centre is null then raise exception 'child not found'; end if;
  if p_status = 'missing' then
    raise exception 'an item is completed as provided, not applicable, or parent declined — never blank';
  end if;
  recorder := app.resolve_recorder(centre, p_recorder, p_pin);
  perform app.ensure_record_items(centre, p_child);
  update public.child_record_item
  set status = p_status,
      content = coalesce(p_content, '{}'::jsonb),
      evidence_path = coalesce(p_evidence_path, evidence_path),
      updated_by = recorder,
      updated_at = now()
  where child_id = p_child and item_type = p_item
  returning * into result;
  return result;
end;
$$;

create or replace function public.verify_child_record(
  p_child uuid,
  p_recorder uuid,
  p_pin text
) returns setof public.child_record_item
language plpgsql security definer
set search_path = public
as $$
declare
  centre uuid;
  recorder uuid;
begin
  select ch.centre_id into centre from public.child ch where ch.id = p_child;
  if centre is null then raise exception 'child not found'; end if;
  recorder := app.resolve_recorder(centre, p_recorder, p_pin);
  if not app.has_role(centre, array['supervisor', 'designate', 'licensee_admin']::public.role_id[]) then
    raise exception 'verification is a supervisor action' using errcode = '42501';
  end if;
  return query
  update public.child_record_item
  set verified_by = recorder, verified_at = now()
  where child_id = p_child and status <> 'missing'
  returning *;
end;
$$;

create or replace function public.give_consent(
  p_child uuid,
  p_type public.consent_type,
  p_purpose text,
  p_status text,
  p_expires timestamptz default null
) returns public.consent
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid;
  centre uuid;
  result public.consent;
begin
  me := app.current_person_id();
  select ch.centre_id into centre from public.child ch where ch.id = p_child;
  if centre is null then raise exception 'child not found'; end if;
  if not app.is_consenting_member(me, p_child) then
    raise exception 'only a consenting household member may give or decline consent' using errcode = '42501';
  end if;
  -- a new decision supersedes the previous one for the same type
  update public.consent set revoked_at = now()
  where child_id = p_child and consent_type = p_type and revoked_at is null;
  insert into public.consent (centre_id, child_id, consent_type, purpose, status, granted_by, expires_at, evidence)
  values (centre, p_child, p_type, p_purpose, p_status, me, p_expires, 'in-app decision')
  returning * into result;
  return result;
end;
$$;

create or replace function public.revoke_consent(p_consent uuid)
returns public.consent
language plpgsql security definer
set search_path = public
as $$
declare
  me uuid;
  result public.consent;
begin
  select * into result from public.consent where id = p_consent;
  if result.id is null then raise exception 'consent not found'; end if;
  me := app.current_person_id();
  if not app.is_consenting_member(me, result.child_id) then
    raise exception 'only a consenting household member may revoke consent' using errcode = '42501';
  end if;
  update public.consent set revoked_at = now() where id = p_consent
  returning * into result;
  return result;
end;
$$;

create or replace function public.create_enrolment_invite(
  p_centre uuid,
  p_household uuid,
  p_email text,
  p_recorder uuid,
  p_pin text
) returns public.enrolment_invite
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.enrolment_invite;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  insert into public.enrolment_invite (centre_id, household_id, email, created_by)
  values (p_centre, p_household, p_email, recorder)
  returning * into result;
  return result;
end;
$$;
