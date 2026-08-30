-- 0019 platform: jurisdictions, platform admins, plans & billing, pilot
-- onboarding. The platform layer manages TENANCY AND MONEY, never children:
-- platform admins can create centres and set plans but hold no care role, so
-- RLS never shows them a child, an attendance row, or a family. And billing
-- state never gates a regulated record (§9.14 never-do #1): no policy in this
-- schema reads centre_subscription — a lapsed plan changes nothing about what
-- staff and parents can see or write. pgTAP proves both.

-- ── jurisdictions ───────────────────────────────────────────────────────────
-- Which regulator's rule pack a centre runs under. Ontario (CA-ON) is the
-- implemented pack; other provinces/states are rows waiting for a rule pack
-- in packages/domain (presets.ts) and a compliance requirements document.
create table public.jurisdiction (
  code text primary key, -- ISO-3166-2, e.g. 'CA-ON', 'US-NY'
  country_code text not null,
  name text not null,
  kind text not null check (kind in ('province', 'territory', 'state')),
  rule_status text not null default 'planned' check (rule_status in ('implemented', 'planned')),
  -- active = platform admins may create centres here
  active boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.jurisdiction (code, country_code, name, kind, rule_status, active) values
  ('CA-ON', 'CA', 'Ontario', 'province', 'implemented', true),
  ('CA-MB', 'CA', 'Manitoba', 'province', 'planned', false),
  ('CA-QC', 'CA', 'Quebec', 'province', 'planned', false);

alter table public.centre
  add column jurisdiction_code text not null default 'CA-ON' references public.jurisdiction (code);

alter table public.jurisdiction enable row level security;
-- Reference data (no personal information); published pricing is a feature.
create policy jurisdiction_select on public.jurisdiction for select using (true);

-- ── platform admins ─────────────────────────────────────────────────────────
-- Keyed by email so an admin exists before their first sign-in. Founders are
-- seeded here; more are added only by an existing admin via RPC.
create table public.platform_admin (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  full_name text,
  active boolean not null default true,
  added_by text,
  created_at timestamptz not null default now()
);

create unique index platform_admin_email_lower on public.platform_admin (lower(email));

insert into public.platform_admin (email, added_by) values
  ('adithyakrishnan.vinod@gmail.com', 'migration 0019 (founder)'),
  ('simon.mathiasclg@gmail.com', 'migration 0019 (founder)');

create or replace function app.is_platform_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_admin pa
    where pa.active
      and lower(pa.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  )
$$;

-- PostgREST-callable wrapper (the app schema is not exposed over the API).
create or replace function public.is_platform_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$ select app.is_platform_admin() $$;

alter table public.platform_admin enable row level security;
create policy platform_admin_select on public.platform_admin
  for select using (app.is_platform_admin());

-- Platform admins see tenancy — and ONLY tenancy. No policy on child,
-- attendance_event, care_log, household… ever names is_platform_admin.
create policy licensee_platform_select on public.licensee
  for select using (app.is_platform_admin());
create policy centre_platform_select on public.centre
  for select using (app.is_platform_admin());

-- They may also see who runs each centre (supervisors and licensee admins by
-- name and email — workforce leadership, never families or children).
create policy person_platform_select on public.person
  for select using (
    app.is_platform_admin()
    and exists (
      select 1 from public.person_role pr
      where pr.person_id = person.id
        and pr.role in ('supervisor', 'licensee_admin')
    )
  );
create policy person_role_platform_select on public.person_role
  for select using (
    app.is_platform_admin() and role in ('supervisor', 'licensee_admin')
  );

-- ── plans ───────────────────────────────────────────────────────────────────
-- Published CAD pricing (business plan §9): flat per enrolled child, a
-- small-centre minimum, no per-staff fee, no setup fee, parents always free.
create table public.plan (
  code text primary key,
  name text not null,
  description text,
  price_per_child_cents integer not null default 0 check (price_per_child_cents >= 0),
  monthly_minimum_cents integer not null default 0 check (monthly_minimum_cents >= 0),
  currency text not null default 'CAD',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.plan (code, name, description, price_per_child_cents, monthly_minimum_cents) values
  ('pilot', 'Pilot', 'Free until your first licensing visit on Tucked, in exchange for feedback.', 0, 0),
  ('founding', 'Founding centre', 'Half price for the first year after a pilot converts — two referrals and permission to name you.', 200, 3900),
  ('standard', 'Standard', 'Flat per-child price, published. No per-staff fee, no setup fee, parents always free.', 400, 7900);

alter table public.plan enable row level security;
create policy plan_select on public.plan for select using (true);

-- ── subscriptions ───────────────────────────────────────────────────────────
create table public.centre_subscription (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null unique references public.centre (id),
  plan_code text not null references public.plan (code),
  status text not null default 'pilot' check (status in ('pilot', 'active', 'past_due', 'cancelled')),
  pilot_ends_on date,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.centre_subscription enable row level security;
create policy subscription_select on public.centre_subscription
  for select using (
    app.is_platform_admin()
    or app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[])
  );
-- Writes via admin RPCs only.

create trigger centre_subscription_audit
  after insert or update on public.centre_subscription
  for each row execute function app.audit_row();

-- ── billing ledger ──────────────────────────────────────────────────────────
-- Append-only: financial records are kept 6 years (O. Reg. 138/15 s. 27.1).
create table public.billing_event (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  event_type text not null check (event_type in
    ('subscription_created', 'plan_changed', 'status_changed', 'payment_recorded', 'note')),
  amount_cents integer,
  detail text,
  recorded_by_email text not null,
  created_at timestamptz not null default now()
);

create index billing_event_centre_at on public.billing_event (centre_id, created_at desc);

alter table public.billing_event enable row level security;
create policy billing_event_select on public.billing_event
  for select using (
    app.is_platform_admin()
    or app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[])
  );

create trigger billing_event_no_update
  before update on public.billing_event
  for each row execute function app.block_mutation();
create trigger billing_event_no_delete
  before delete on public.billing_event
  for each row execute function app.block_mutation();

-- ── pilot onboarding ────────────────────────────────────────────────────────
-- The invite is the person row: the admin records the supervisor's name and
-- email; the supervisor signs in with a magic link to that email and this
-- trigger connects their new auth user to the waiting person. No password is
-- ever created or sent by an admin.
create or replace function app.link_person_on_signup()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  update public.person
  set auth_user_id = new.id
  where auth_user_id is null
    and email is not null
    and lower(email) = lower(coalesce(new.email, ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.link_person_on_signup();

-- One call sets up a pilot daycare: licensee, centre, the supervisor's
-- invitation, and the subscription — atomically, admin-gated, audited.
create or replace function public.admin_create_centre(
  p_licensee_name text,
  p_centre_name text,
  p_licence_number text,
  p_address text,
  p_jurisdiction text,
  p_timezone text,
  p_opens time,
  p_closes time,
  p_supervisor_name text,
  p_supervisor_email text,
  p_plan text default 'pilot',
  p_pilot_ends_on date default null
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_licensee uuid;
  v_centre uuid;
  v_person uuid;
  v_admin text;
begin
  if not app.is_platform_admin() then
    raise exception 'platform admins only' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.jurisdiction j
    where j.code = p_jurisdiction and j.active and j.rule_status = 'implemented'
  ) then
    raise exception 'jurisdiction % is not accepting centres yet', p_jurisdiction;
  end if;
  if not exists (select 1 from public.plan where code = p_plan and active) then
    raise exception 'unknown plan %', p_plan;
  end if;
  if p_supervisor_email is null or position('@' in p_supervisor_email) = 0 then
    raise exception 'a supervisor email is required — it is how they sign in';
  end if;
  v_admin := lower(coalesce(auth.jwt() ->> 'email', 'service'));

  insert into public.licensee (legal_name) values (p_licensee_name) returning id into v_licensee;

  insert into public.centre (
    licensee_id, name, licence_number, address, jurisdiction_code, province,
    timezone, opens_at, closes_at
  ) values (
    v_licensee, p_centre_name, p_licence_number, p_address, p_jurisdiction,
    -- the legacy province column follows the jurisdiction while only
    -- Canadian provinces exist; it retires when the first US state lands
    (case p_jurisdiction when 'CA-MB' then 'MB' when 'CA-QC' then 'QC' else 'ON' end)::public.province,
    coalesce(nullif(p_timezone, ''), 'America/Toronto'),
    coalesce(p_opens, '07:30'::time), coalesce(p_closes, '18:00'::time)
  ) returning id into v_centre;

  select id into v_person from public.person where lower(email) = lower(p_supervisor_email);
  if v_person is null then
    insert into public.person (full_name, email)
    values (p_supervisor_name, lower(p_supervisor_email))
    returning id into v_person;
  end if;
  insert into public.person_role (person_id, centre_id, role, qualified)
  values (v_person, v_centre, 'supervisor', true);

  insert into public.centre_subscription (centre_id, plan_code, status, pilot_ends_on)
  values (v_centre, p_plan, case when p_plan = 'pilot' then 'pilot' else 'active' end, p_pilot_ends_on);

  insert into public.billing_event (centre_id, event_type, detail, recorded_by_email)
  values (
    v_centre, 'subscription_created',
    p_plan || coalesce(' · pilot until ' || p_pilot_ends_on::text, ''),
    v_admin
  );

  return v_centre;
end;
$$;

create or replace function public.admin_set_plan(
  p_centre uuid,
  p_plan text,
  p_status text,
  p_pilot_ends_on date default null,
  p_note text default null
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_admin text;
begin
  if not app.is_platform_admin() then
    raise exception 'platform admins only' using errcode = '42501';
  end if;
  if not exists (select 1 from public.plan where code = p_plan) then
    raise exception 'unknown plan %', p_plan;
  end if;
  if p_status not in ('pilot', 'active', 'past_due', 'cancelled') then
    raise exception 'unknown status %', p_status;
  end if;
  v_admin := lower(coalesce(auth.jwt() ->> 'email', 'service'));

  update public.centre_subscription
  set plan_code = p_plan,
      status = p_status,
      pilot_ends_on = p_pilot_ends_on,
      notes = coalesce(p_note, notes),
      updated_at = now()
  where centre_id = p_centre;
  if not found then
    raise exception 'centre % has no subscription', p_centre;
  end if;

  insert into public.billing_event (centre_id, event_type, detail, recorded_by_email)
  values (p_centre, 'plan_changed', p_plan || ' · ' || p_status || coalesce(' · ' || p_note, ''), v_admin);
end;
$$;

create or replace function public.admin_record_payment(
  p_centre uuid,
  p_amount_cents integer,
  p_note text default null
) returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not app.is_platform_admin() then
    raise exception 'platform admins only' using errcode = '42501';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'a payment needs a positive amount';
  end if;
  insert into public.billing_event (centre_id, event_type, amount_cents, detail, recorded_by_email)
  values (p_centre, 'payment_recorded', p_amount_cents, p_note,
          lower(coalesce(auth.jwt() ->> 'email', 'service')));
end;
$$;

create or replace function public.admin_add_platform_admin(
  p_email text,
  p_full_name text default null
) returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not app.is_platform_admin() then
    raise exception 'platform admins only' using errcode = '42501';
  end if;
  if p_email is null or position('@' in p_email) = 0 then
    raise exception 'an email address is required';
  end if;
  insert into public.platform_admin (email, full_name, added_by)
  values (lower(p_email), p_full_name, lower(coalesce(auth.jwt() ->> 'email', 'service')))
  on conflict do nothing;
end;
$$;
