-- 0002 people: person (global — one login per human, decision 2026-08-29),
-- person_role (centre-scoped). Then the app.* RLS helpers and the read policies
-- for 0001 + 0002 tables. Helpers are SECURITY DEFINER so policy evaluation
-- never recurses through RLS on person/person_role themselves.

create type public.role_id as enum (
  'licensee_admin', 'supervisor', 'designate', 'rece', 'staff',
  'student', 'volunteer', 'resource_consultant', 'family_adult'
);

-- person is the one deliberate exception to "every table carries centre_id":
-- a human is global; their access to a centre is a person_role row.
create table public.person (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users (id) on delete set null,
  full_name text not null,
  email text,
  phone text,
  created_at timestamptz not null default now()
);

create unique index person_email_unique on public.person (lower(email)) where email is not null;

create table public.person_role (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.person (id),
  centre_id uuid not null references public.centre (id),
  role public.role_id not null,
  -- RECE registration / age-group qualification: drives qualified-staff counts.
  qualified boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (person_id, centre_id, role)
);

alter table public.person enable row level security;
alter table public.person_role enable row level security;

-- ── app helpers ─────────────────────────────────────────────────────────────
create schema if not exists app;
grant usage on schema app to authenticated, anon;

create or replace function app.current_person_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select id from public.person where auth_user_id = auth.uid()
$$;

-- Centres where I hold ANY active role (staff or family).
create or replace function app.member_centre_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select pr.centre_id
  from public.person_role pr
  join public.person p on p.id = pr.person_id
  where p.auth_user_id = auth.uid() and pr.active
$$;

-- Centres where I hold a role that gives access to children's data.
-- Students and volunteers are deliberately excluded: they are never alone with
-- children (ss. 53–64) and get no standing access to children's records.
create or replace function app.care_centre_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select pr.centre_id
  from public.person_role pr
  join public.person p on p.id = pr.person_id
  where p.auth_user_id = auth.uid() and pr.active
    and pr.role in ('licensee_admin', 'supervisor', 'designate', 'rece', 'staff')
$$;

-- Centres where I hold any non-family (workforce) role, incl. student/volunteer.
create or replace function app.staff_centre_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select pr.centre_id
  from public.person_role pr
  join public.person p on p.id = pr.person_id
  where p.auth_user_id = auth.uid() and pr.active and pr.role <> 'family_adult'
$$;

create or replace function app.has_role(target_centre uuid, roles public.role_id[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.person_role pr
    join public.person p on p.id = pr.person_id
    where p.auth_user_id = auth.uid()
      and pr.centre_id = target_centre
      and pr.active
      and pr.role = any (roles)
  )
$$;

-- ── policies: 0001 tables ───────────────────────────────────────────────────
create policy licensee_select on public.licensee
  for select using (
    exists (
      select 1 from public.centre c
      where c.licensee_id = licensee.id
        and c.id in (select app.member_centre_ids())
    )
  );

create policy centre_select on public.centre
  for select using (id in (select app.member_centre_ids()));

create policy centre_update on public.centre
  for update using (app.has_role(id, array['supervisor', 'licensee_admin']::public.role_id[]))
  with check (app.has_role(id, array['supervisor', 'licensee_admin']::public.role_id[]));

create policy age_group_select on public.age_group
  for select using (centre_id in (select app.member_centre_ids()));

create policy room_select on public.room
  for select using (centre_id in (select app.member_centre_ids()));

-- ── policies: 0002 tables ───────────────────────────────────────────────────
-- Self, plus workforce members of a centre where this person holds a role.
create policy person_select on public.person
  for select using (
    auth_user_id = auth.uid()
    or exists (
      select 1 from public.person_role pr
      where pr.person_id = person.id
        and pr.centre_id in (select app.staff_centre_ids())
    )
  );

create policy person_update_self on public.person
  for update using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());

create policy person_role_select on public.person_role
  for select using (
    person_id = app.current_person_id()
    or centre_id in (select app.staff_centre_ids())
  );

-- No insert/update/delete policies for person_role in Phase 0: role changes go
-- through the service role (seed now, supervised flows in Phase 1) and are audited.
