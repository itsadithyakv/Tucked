-- pgTAP: the platform layer — jurisdictions, platform admins, plans, billing,
-- pilot onboarding. Two rules matter more than the features:
--   1. Platform admins manage tenancy and money, NEVER children (PIPEDA
--      minimum-collection; they hold no care role and RLS shows them none).
--   2. Billing state never locks a regulated record (§9.14 never-do #1):
--      a cancelled subscription changes nothing for staff or parents.

begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '19000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'admin@platform.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '19000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'sup@platform.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.platform_admin (email, added_by) values ('admin@platform.local', 'pgtap fixture');

insert into public.licensee (id, legal_name) values ('29000000-0000-4000-8000-000000000001', 'Plat Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('39000000-0000-4000-8000-000000000001', '29000000-0000-4000-8000-000000000001', 'Plat Centre', 'PLAT-1', '1 Plat St, Toronto', '07:30', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('3b000000-0000-4000-8000-000000000001', '39000000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('3c000000-0000-4000-8000-000000000001', '39000000-0000-4000-8000-000000000001', '3b000000-0000-4000-8000-000000000001', 'Plat Room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('49000000-0000-4000-8000-000000000001', '19000000-0000-4000-8000-000000000002', 'Sup Plat', 'sup@platform.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('49000000-0000-4000-8000-000000000001', '39000000-0000-4000-8000-000000000001', 'supervisor', true);
insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('49000000-0000-4000-8000-000000000001', '39000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('69000000-0000-4000-8000-000000000001', '39000000-0000-4000-8000-000000000001', 'Plat Child', '2023-03-15', '2026-01-05', '3c000000-0000-4000-8000-000000000001');

insert into public.centre_subscription (centre_id, plan_code, status) values
  ('39000000-0000-4000-8000-000000000001', 'pilot', 'pilot');

-- ── as a platform admin (email claim carries the identity) ──────────────────
select set_config('request.jwt.claims', '{"sub":"19000000-0000-4000-8000-000000000001","role":"authenticated","email":"admin@platform.local"}', true);
set local role authenticated;

select ok(public.is_platform_admin(), 'platform_admin_recognised_by_email');

select lives_ok(
  $$select public.admin_create_centre('Sunrise Licensee Inc.', 'Sunrise Child Care', 'SUN-001', '9 Dawn Ave, Ottawa', 'CA-ON', 'America/Toronto', '07:00', '18:00', 'Priya Nair', 'priya@sunrise.example', 'pilot', '2026-12-01')$$,
  'platform_admin_creates_pilot_centre'
);

select is(
  (select count(*) from public.centre_subscription cs join public.centre c on c.id = cs.centre_id
   where c.name = 'Sunrise Child Care' and cs.plan_code = 'pilot' and cs.status = 'pilot'),
  1::bigint,
  'pilot_subscription_created_with_centre'
);

select is(
  (select count(*) from public.person_role pr join public.person p on p.id = pr.person_id
   join public.centre c on c.id = pr.centre_id
   where c.name = 'Sunrise Child Care' and pr.role = 'supervisor' and lower(p.email) = 'priya@sunrise.example'),
  1::bigint,
  'supervisor_invited_by_email'
);

select throws_ok(
  $$select public.admin_create_centre('QC Licensee', 'QC Centre', 'QC-1', '1 Rue, Montreal', 'CA-QC', null, null, null, 'Sup', 'sup@qc.example')$$,
  'jurisdiction CA-QC is not accepting centres yet',
  'planned_jurisdictions_reject_centres_until_implemented'
);

select is(
  (select count(*) from public.centre where name in ('Plat Centre', 'Sunrise Child Care')),
  2::bigint,
  'platform_admin_sees_all_centres'
);

-- The privacy line: tenancy yes, children never.
select is((select count(*) from public.child), 0::bigint, 'pipeda_platform_admin_sees_no_children');
select is((select count(*) from public.attendance_event), 0::bigint, 'pipeda_platform_admin_sees_no_attendance');
select is((select count(*) from public.household), 0::bigint, 'pipeda_platform_admin_sees_no_households');

select lives_ok(
  $$select public.admin_set_plan('39000000-0000-4000-8000-000000000001', 'standard', 'cancelled', null, 'stress test: billing must never lock records')$$,
  'platform_admin_changes_plan_and_status'
);

-- ── as the supervisor of the (now cancelled) centre ─────────────────────────
select set_config('request.jwt.claims', '{"sub":"19000000-0000-4000-8000-000000000002","role":"authenticated","email":"sup@platform.local"}', true);

select is(
  (select status from public.centre_subscription where centre_id = '39000000-0000-4000-8000-000000000001'),
  'cancelled',
  'supervisor_sees_own_subscription'
);

select throws_ok(
  $$select public.admin_create_centre('X', 'X', 'X-1', 'X St', 'CA-ON', null, null, null, 'X', 'x@x.example')$$,
  'platform admins only',
  'supervisors_cannot_use_admin_rpcs'
);

-- §9.14 never-do #1, proven: with the subscription CANCELLED the supervisor
-- still reads every record and still writes attendance.
select is((select count(*) from public.child), 1::bigint, 'never_cancelled_billing_hides_records');
select lives_ok(
  $$select public.record_attendance('39000000-0000-4000-8000-000000000001','69000000-0000-4000-8000-000000000001','arrive','3c000000-0000-4000-8000-000000000001', now(), '49000000-0000-4000-8000-000000000001', '4242')$$,
  'never_cancelled_billing_blocks_writes'
);

-- ── as owner: the invite link trigger, and the ledger is append-only ────────
reset role;

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '19000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'PRIYA@sunrise.example', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

select is(
  (select auth_user_id from public.person where lower(email) = 'priya@sunrise.example'),
  '19000000-0000-4000-8000-000000000003'::uuid,
  'magic_link_signup_links_invited_supervisor'
);

select throws_like(
  $$delete from public.billing_event where true$$,
  '%append-only%',
  'oreg138_billing_ledger_never_deleted'
);

select * from finish();
rollback;
