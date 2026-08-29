-- 0001 tenancy: licensee → centre → age_group → room.
-- Every data table carries centre_id and is protected by RLS (build prompt §4).
-- RLS is enabled here with NO policies (deny-all for clients); policies land in
-- 0002 once the person tables the helper functions need exist. The service role
-- (seed, Edge Functions) bypasses RLS by design.

create type public.province as enum ('ON', 'MB', 'QC');

-- Schedule 1 licensed age groups. The numeric presets (ratios, group sizes)
-- live in packages/domain/src/ageGroups.ts; the database stores which preset a
-- group uses and its licensed capacity.
create type public.age_group_preset as enum (
  'infant', 'toddler', 'preschool', 'kindergarten', 'primary_junior', 'junior', 'family'
);

create table public.licensee (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null,
  created_at timestamptz not null default now()
);

create table public.centre (
  id uuid primary key default gen_random_uuid(),
  licensee_id uuid not null references public.licensee (id),
  name text not null,
  licence_number text not null,
  province public.province not null default 'ON',
  -- IANA zone. Attendance is day-bounded in this zone (decision 2026-08-29).
  timezone text not null default 'America/Toronto',
  address text not null,
  service_system_manager text,
  cwelcc_enrolled boolean not null default false,
  opens_at time not null,
  closes_at time not null,
  created_at timestamptz not null default now(),
  -- No overnight care in v1: open strictly before close on the same local day.
  constraint centre_day_bounded check (opens_at < closes_at)
);

create table public.age_group (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  preset public.age_group_preset not null,
  licensed_capacity integer not null check (licensed_capacity > 0),
  created_at timestamptz not null default now(),
  unique (centre_id, preset)
);

create table public.room (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  age_group_id uuid not null references public.age_group (id),
  name text not null,
  created_at timestamptz not null default now()
);

alter table public.licensee enable row level security;
alter table public.centre enable row level security;
alter table public.age_group enable row level security;
alter table public.room enable row level security;
