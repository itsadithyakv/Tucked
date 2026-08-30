-- 0021 individualised plans (ss. 39, 39.1, 52) and the posted allergy and
-- food-restriction list (s. 43(3)). The rules held in this schema:
--   * An anaphylaxis plan names its allergens, the signs of a reaction, and
--     the emergency procedure — none of these can be blank (s. 39).
--   * A medical-needs plan always carries an emergency procedure (s. 39.1);
--     a special-needs plan always carries its supports (s. 52).
--   * s. 52: parental agreement BEFORE a plan is implemented — a plan cannot
--     become 'active' without a recorded agreement (in-app by a consenting
--     household adult, or a signed paper recorded by staff).
--   * Plan content is immutable once written: changes supersede with a new
--     version; nothing regulated is ever edited in place or deleted.
--   * The allergy list (s. 43(3)) is a live view over anaphylaxis plans and
--     dietary restrictions — printed per room and for the kitchen, and it
--     includes draft-plan allergens: a known allergy protects the child even
--     before the paperwork is signed.
--   * Plans are reviewed annually: review_due_on drives console exceptions.

-- s. 39(1): the centre needs an anaphylaxis policy even with zero allergic
-- children. Supervisors edit it in the console (centre_update policy).
alter table public.centre add column anaphylaxis_policy text;

-- ── individualised plans ────────────────────────────────────────────────────
create table public.individualised_plan (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  plan_type text not null check (plan_type in ('anaphylaxis', 'medical_needs', 'special_needs')),
  version integer not null,
  condition text not null,
  allergens text[] not null default '{}',
  signs text,
  emergency_procedure text,
  exposure_reduction text,
  devices_instructions text,
  supports text,
  evacuation_procedure text,
  -- who the plan was developed with (parent, physician, resource consultant…)
  developed_with text not null,
  status text not null default 'draft' check (status in ('draft', 'active', 'superseded', 'ended')),
  parent_agreed_at timestamptz,
  parent_agreed_by uuid references public.person (id),
  agreement_method text check (agreement_method in ('in_app', 'signed_paper')),
  review_due_on date,
  recorded_by uuid not null references public.person (id),
  superseded_at timestamptz,
  ended_at timestamptz,
  end_note text,
  created_at timestamptz not null default now(),
  unique (child_id, plan_type, version)
);

-- one live plan per child and type
create unique index individualised_plan_live
  on public.individualised_plan (child_id, plan_type) where status in ('draft', 'active');

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

  if tg_op = 'UPDATE' then
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

create trigger individualised_plan_rules
  before insert or update on public.individualised_plan
  for each row execute function app.individualised_plan_rules();

-- ── dietary restrictions (the non-anaphylactic half of the posted list) ─────
create table public.dietary_restriction (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  kind text not null check (kind in ('allergy', 'intolerance', 'food_restriction')),
  substance text not null,
  note text,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_by uuid references public.person (id)
);

-- ── visibility ──────────────────────────────────────────────────────────────
alter table public.individualised_plan enable row level security;
alter table public.dietary_restriction enable row level security;

-- Care staff need plans at hand in an emergency; parents see their own child's.
create policy individualised_plan_select on public.individualised_plan
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = individualised_plan.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );

create policy dietary_restriction_select on public.dietary_restriction
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = dietary_restriction.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
-- Writes via RPCs only.

create trigger individualised_plan_no_delete before delete on public.individualised_plan
  for each row execute function app.block_mutation();
create trigger dietary_restriction_no_delete before delete on public.dietary_restriction
  for each row execute function app.block_mutation();
create trigger individualised_plan_audit after insert or update on public.individualised_plan
  for each row execute function app.audit_row();
create trigger dietary_restriction_audit after insert or update on public.dietary_restriction
  for each row execute function app.audit_row();

-- ── the posted list (s. 43(3)) ──────────────────────────────────────────────
-- Live union of anaphylaxis-plan allergens (draft plans included: a known
-- allergy protects the child before the paperwork is signed) and un-ended
-- dietary restrictions. security_invoker: RLS of the underlying tables applies.
create view public.allergy_list
with (security_invoker = on) as
select
  p.centre_id,
  p.child_id,
  ch.full_name,
  ch.current_room_id,
  'anaphylaxis'::text as kind,
  a.allergen as item,
  p.emergency_procedure
from public.individualised_plan p
join public.child ch on ch.id = p.child_id
cross join lateral unnest(p.allergens) as a (allergen)
where p.plan_type = 'anaphylaxis' and p.status in ('draft', 'active')
union all
select
  dr.centre_id,
  dr.child_id,
  ch.full_name,
  ch.current_room_id,
  dr.kind,
  dr.substance || coalesce(' — ' || dr.note, '') as item,
  null as emergency_procedure
from public.dietary_restriction dr
join public.child ch on ch.id = dr.child_id
where dr.ended_at is null;

-- ── RPCs ────────────────────────────────────────────────────────────────────
-- New plan or new version: supersedes any live plan of the same type, starts
-- as a draft, and asks the consenting household adults to agree (Now alert).
create or replace function public.upsert_individualised_plan(
  p_centre uuid,
  p_child uuid,
  p_type text,
  p_condition text,
  p_allergens text[],
  p_signs text,
  p_emergency text,
  p_exposure text,
  p_devices text,
  p_supports text,
  p_evacuation text,
  p_developed_with text,
  p_recorder uuid,
  p_pin text
) returns public.individualised_plan
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  next_version integer;
  result public.individualised_plan;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);

  update public.individualised_plan
  set status = 'superseded', superseded_at = now()
  where child_id = p_child and plan_type = p_type and status in ('draft', 'active');

  select coalesce(max(version), 0) + 1 into next_version
  from public.individualised_plan where child_id = p_child and plan_type = p_type;

  insert into public.individualised_plan (
    centre_id, child_id, plan_type, version, condition, allergens, signs,
    emergency_procedure, exposure_reduction, devices_instructions, supports,
    evacuation_procedure, developed_with, recorded_by
  ) values (
    p_centre, p_child, p_type, next_version, trim(p_condition),
    coalesce(p_allergens, '{}'), nullif(trim(coalesce(p_signs, '')), ''),
    nullif(trim(coalesce(p_emergency, '')), ''), nullif(trim(coalesce(p_exposure, '')), ''),
    nullif(trim(coalesce(p_devices, '')), ''), nullif(trim(coalesce(p_supports, '')), ''),
    nullif(trim(coalesce(p_evacuation, '')), ''), trim(p_developed_with), recorder
  ) returning * into result;

  -- ask the consenting adults to agree, loudly
  insert into public.notification (
    centre_id, child_id, recipient_person_id, channel, event_type, title, body,
    requires_acknowledgement, created_by, ref_id
  )
  select
    p_centre, p_child, hm.person_id, 'now', 'plan_agreement',
    'Please review ' || split_part(ch.full_name, ' ', 1) || '''s ' ||
      replace(p_type, '_', ' ') || ' plan',
    'The plan needs your agreement before the centre puts it into practice.',
    true, recorder, result.id
  from public.child ch
  join public.child_household chh on chh.child_id = ch.id
  join public.household_member hm on hm.household_id = chh.household_id
  where ch.id = p_child and hm.revoked_at is null and hm.can_consent;

  return result;
end;
$$;

-- A parent agrees in the app — the strongest evidence, timestamped and named.
create or replace function public.agree_individualised_plan(p_plan uuid)
returns public.individualised_plan
language plpgsql security definer
set search_path = public
as $$
declare
  plan public.individualised_plan;
  me uuid;
begin
  select * into plan from public.individualised_plan where id = p_plan;
  if plan.id is null then raise exception 'plan not found'; end if;
  me := app.current_person_id();
  if me is null or not exists (
    select 1 from public.child_household ch
    join public.household_member hm on hm.household_id = ch.household_id
    where ch.child_id = plan.child_id
      and hm.person_id = me and hm.revoked_at is null and hm.can_consent
  ) then
    raise exception 'only a consenting household adult can agree to this plan';
  end if;
  if plan.status <> 'draft' then
    raise exception 'this plan version is not awaiting agreement';
  end if;

  update public.individualised_plan
  set status = 'active', parent_agreed_at = now(), parent_agreed_by = me,
      agreement_method = 'in_app', review_due_on = (current_date + interval '1 year')::date
  where id = p_plan
  returning * into plan;

  update public.notification
  set acknowledged_at = now()
  where ref_id = p_plan and recipient_person_id = me and acknowledged_at is null;

  return plan;
end;
$$;

-- Staff record a signed paper agreement (for families who don't use the app).
create or replace function public.record_plan_agreement(
  p_plan uuid,
  p_parent uuid,
  p_agreed_at timestamptz,
  p_recorder uuid,
  p_pin text
) returns public.individualised_plan
language plpgsql security definer
set search_path = public
as $$
declare
  plan public.individualised_plan;
  recorder uuid;
begin
  select * into plan from public.individualised_plan where id = p_plan;
  if plan.id is null then raise exception 'plan not found'; end if;
  recorder := app.resolve_recorder(plan.centre_id, p_recorder, p_pin);
  if not exists (
    select 1 from public.child_household ch
    join public.household_member hm on hm.household_id = ch.household_id
    where ch.child_id = plan.child_id
      and hm.person_id = p_parent and hm.revoked_at is null and hm.can_consent
  ) then
    raise exception 'the agreement must come from a consenting household member';
  end if;
  if plan.status <> 'draft' then
    raise exception 'this plan version is not awaiting agreement';
  end if;

  update public.individualised_plan
  set status = 'active', parent_agreed_at = coalesce(p_agreed_at, now()),
      parent_agreed_by = p_parent, agreement_method = 'signed_paper',
      review_due_on = (current_date + interval '1 year')::date
  where id = p_plan
  returning * into plan;
  return plan;
end;
$$;

create or replace function public.end_individualised_plan(
  p_plan uuid,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  plan public.individualised_plan;
begin
  select * into plan from public.individualised_plan where id = p_plan;
  if plan.id is null then raise exception 'plan not found'; end if;
  perform app.resolve_recorder(plan.centre_id, p_recorder, p_pin);
  if plan.status not in ('draft', 'active') then
    raise exception 'only a live plan can be ended';
  end if;
  update public.individualised_plan
  set status = 'ended', ended_at = now(), end_note = nullif(trim(coalesce(p_note, '')), '')
  where id = p_plan;
end;
$$;

create or replace function public.record_dietary_restriction(
  p_centre uuid,
  p_child uuid,
  p_kind text,
  p_substance text,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns public.dietary_restriction
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.dietary_restriction;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if coalesce(trim(p_substance), '') = '' then
    raise exception 'name the substance or restriction';
  end if;
  insert into public.dietary_restriction (centre_id, child_id, kind, substance, note, recorded_by)
  values (p_centre, p_child, p_kind, trim(p_substance), nullif(trim(coalesce(p_note, '')), ''), recorder)
  returning * into result;
  return result;
end;
$$;

create or replace function public.end_dietary_restriction(
  p_restriction uuid,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  r public.dietary_restriction;
  recorder uuid;
begin
  select * into r from public.dietary_restriction where id = p_restriction;
  if r.id is null then raise exception 'restriction not found'; end if;
  recorder := app.resolve_recorder(r.centre_id, p_recorder, p_pin);
  if r.ended_at is not null then raise exception 'already ended'; end if;
  update public.dietary_restriction
  set ended_at = now(), ended_by = recorder
  where id = p_restriction;
end;
$$;
