-- pgTAP: RLS isolation for every Phase 0 table, tested per role including
-- "wrong centre", "removed household member" and "student/volunteer".
-- Run with: pnpm db:test  (supabase test db)

begin;

create extension if not exists pgtap with schema extensions;

select plan(16);

-- ── fixture: two centres, four identities ───────────────────────────────────
-- auth users (local-only insert; GoTrue is not involved in SQL tests)
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'staff-a@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent-a@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'revoked-a@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'volunteer-a@test.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values
  ('20000000-0000-4000-8000-000000000001', 'Centre A Licensee'),
  ('20000000-0000-4000-8000-000000000002', 'Centre B Licensee');

insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'Centre A', 'A-1', '1 A St, Toronto', '07:30', '18:00'),
  ('30000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'Centre B', 'B-1', '2 B St, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'Staff A', 'staff-a@test.local'),
  ('40000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'Parent A', 'parent-a@test.local'),
  ('40000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000003', 'Revoked A', 'revoked-a@test.local'),
  ('40000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000004', 'Volunteer A', 'volunteer-a@test.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'rece', true),
  ('40000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 'family_adult', false),
  ('40000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000001', 'family_adult', false),
  ('40000000-0000-4000-8000-000000000004', '30000000-0000-4000-8000-000000000001', 'volunteer', false);

insert into public.household (id, centre_id, name) values
  ('50000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'Household One'),
  ('50000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 'Household Two');

insert into public.child (id, centre_id, full_name, date_of_birth, admission_date) values
  ('60000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'Child One', '2024-05-01', '2026-01-05'),
  ('60000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 'Child Two', '2023-09-01', '2026-01-05'),
  ('60000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000002', 'Child B',   '2023-09-01', '2026-01-05');

insert into public.child_household (child_id, household_id, centre_id) values
  ('60000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000002', '50000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001');

insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, revoked_at) values
  ('50000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 'parent', true, null),
  ('50000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000001', 'parent', true, now());

-- ── rls is on everywhere ────────────────────────────────────────────────────
select is(
  (select count(*) from pg_tables where schemaname = 'public' and rowsecurity = false),
  0::bigint,
  'rls_enabled_on_every_public_table'
);

-- ── staff of centre A ───────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*) from public.centre), 1::bigint, 's_rls_staff_sees_only_own_centre');
select is((select count(*) from public.centre where id = '30000000-0000-4000-8000-000000000002'), 0::bigint, 's_rls_wrong_centre_invisible');
select is((select count(*) from public.child), 2::bigint, 's_rls_rece_sees_own_centre_children_only');
select is((select count(*) from public.household), 2::bigint, 's_rls_rece_sees_households');
select throws_ok(
  $$insert into public.room (centre_id, age_group_id, name) values ('30000000-0000-4000-8000-000000000002', gen_random_uuid(), 'Rogue room')$$,
  '42501',
  null,
  's_rls_no_client_writes_in_phase_0'
);
select is((select count(*) from public.audit_event), 0::bigint, 's_rls_audit_hidden_from_non_supervisors');

-- ── family adult ────────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select is((select count(*) from public.child), 1::bigint, 's72_parent_sees_own_children_only');
select is((select full_name from public.child limit 1), 'Child One', 's72_parent_child_is_theirs');
select is((select count(*) from public.person where full_name = 'Staff A'), 0::bigint, 's_rls_family_cannot_enumerate_staff');
select is((select count(*) from public.household), 1::bigint, 's_rls_family_sees_own_household_only');

-- ── removed household member ────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select is((select count(*) from public.child), 0::bigint, 's_rls_revoked_member_sees_no_children');
select is((select count(*) from public.household), 0::bigint, 's_rls_revoked_member_sees_no_household');

-- ── volunteer: never children's data ────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"10000000-0000-4000-8000-000000000004","role":"authenticated"}', true);

select is((select count(*) from public.child), 0::bigint, 's53_volunteer_sees_no_children');
select is((select count(*) from public.centre), 1::bigint, 's53_volunteer_still_sees_centre');

-- ── audit is append-only even for privileged roles ──────────────────────────
reset role;
select throws_like(
  $$delete from public.audit_event where true$$,
  '%append-only%',
  'never_audit_rows_deleted'
);

select * from finish();
rollback;
