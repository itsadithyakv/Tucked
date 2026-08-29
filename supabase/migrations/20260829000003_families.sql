-- 0003 families: household ↔ child via child_household; household_member with
-- per-person permissions (the Brightwheel co-parent failure is why these are
-- per person and individually revocable). A child may belong to more than one
-- household (separated parents). Join tables carry centre_id too — the build
-- prompt's rule is every data table, and it keeps RLS non-recursive.

create table public.household (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  name text not null,
  created_at timestamptz not null default now()
);

create table public.child (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  full_name text not null,
  date_of_birth date not null,
  admission_date date not null,
  discharge_date date,
  current_room_id uuid references public.room (id),
  attends_school boolean not null default false,
  created_at timestamptz not null default now(),
  constraint child_discharge_after_admission
    check (discharge_date is null or discharge_date >= admission_date)
);

create table public.child_household (
  child_id uuid not null references public.child (id),
  household_id uuid not null references public.household (id),
  centre_id uuid not null references public.centre (id),
  primary key (child_id, household_id)
);

create table public.household_member (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.household (id),
  person_id uuid not null references public.person (id),
  centre_id uuid not null references public.centre (id),
  relationship text not null,
  can_view boolean not null default true,
  can_message boolean not null default true,
  can_pickup boolean not null default false,
  can_consent boolean not null default false,
  can_bill boolean not null default false,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  unique (household_id, person_id)
);

alter table public.household enable row level security;
alter table public.child enable row level security;
alter table public.child_household enable row level security;
alter table public.household_member enable row level security;

-- ── helpers ─────────────────────────────────────────────────────────────────
-- Households where I am an active (un-revoked) member.
create or replace function app.my_household_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select hm.household_id
  from public.household_member hm
  join public.person p on p.id = hm.person_id
  where p.auth_user_id = auth.uid() and hm.revoked_at is null
$$;

-- Households whose children I may view (can_view and not revoked).
create or replace function app.my_viewable_household_ids()
returns setof uuid
language sql stable security definer
set search_path = public
as $$
  select hm.household_id
  from public.household_member hm
  join public.person p on p.id = hm.person_id
  where p.auth_user_id = auth.uid() and hm.revoked_at is null and hm.can_view
$$;

-- ── policies ────────────────────────────────────────────────────────────────
create policy household_select on public.household
  for select using (
    centre_id in (select app.care_centre_ids())
    or id in (select app.my_household_ids())
  );

-- Children: care staff of the centre, or a viewing member of one of the
-- child's households. Parents' right of access to their child's record (s. 72)
-- is served by this view; students/volunteers get nothing.
create policy child_select on public.child
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = child.id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );

create policy child_household_select on public.child_household
  for select using (
    centre_id in (select app.care_centre_ids())
    or household_id in (select app.my_viewable_household_ids())
  );

create policy household_member_select on public.household_member
  for select using (
    centre_id in (select app.care_centre_ids())
    or person_id = app.current_person_id()
  );

-- No client write policies in Phase 0: enrolment flows arrive in Phase 1 and
-- write through supervised paths. The seed uses the service role.
