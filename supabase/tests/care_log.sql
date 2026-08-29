-- pgTAP: care log — s. 33.1 sleep checks, s. 32 health observation, payload
-- validation, bulk entry, family scoping.

begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

-- ── fixture: one centre, toddler + preschool rooms, three children ──────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '12000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rece@cl.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '12000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent@cl.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('22000000-0000-4000-8000-000000000001', 'CL Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('34000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000001', 'CL Centre', 'CL-1', '1 CL St, Toronto', '07:30', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('35000000-0000-4000-8000-000000000001', '34000000-0000-4000-8000-000000000001', 'toddler', 15),
  ('35000000-0000-4000-8000-000000000002', '34000000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('36000000-0000-4000-8000-000000000001', '34000000-0000-4000-8000-000000000001', '35000000-0000-4000-8000-000000000001', 'Toddler room'),
  ('36000000-0000-4000-8000-000000000002', '34000000-0000-4000-8000-000000000001', '35000000-0000-4000-8000-000000000002', 'Preschool room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('42000000-0000-4000-8000-000000000001', '12000000-0000-4000-8000-000000000001', 'Rece CL', 'rece@cl.local'),
  ('42000000-0000-4000-8000-000000000002', '12000000-0000-4000-8000-000000000002', 'Parent CL', 'parent@cl.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('42000000-0000-4000-8000-000000000001', '34000000-0000-4000-8000-000000000001', 'rece', true),
  ('42000000-0000-4000-8000-000000000002', '34000000-0000-4000-8000-000000000001', 'family_adult', false);
insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('42000000-0000-4000-8000-000000000001', '34000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

-- young toddler (18 mo), old toddler (25 mo), preschooler (4 y)
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('62000000-0000-4000-8000-000000000001', '34000000-0000-4000-8000-000000000001', 'Young Toddler', (current_date - interval '18 months')::date, '2026-01-05', '36000000-0000-4000-8000-000000000001'),
  ('62000000-0000-4000-8000-000000000002', '34000000-0000-4000-8000-000000000001', 'Old Toddler', (current_date - interval '25 months')::date, '2026-01-05', '36000000-0000-4000-8000-000000000001'),
  ('62000000-0000-4000-8000-000000000003', '34000000-0000-4000-8000-000000000001', 'Preschooler', (current_date - interval '4 years')::date, '2026-01-05', '36000000-0000-4000-8000-000000000002');

insert into public.household (id, centre_id, name) values
  ('52000000-0000-4000-8000-000000000001', '34000000-0000-4000-8000-000000000001', 'CL Household');
insert into public.child_household (child_id, household_id, centre_id) values
  ('62000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000001', '34000000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view) values
  ('52000000-0000-4000-8000-000000000001', '42000000-0000-4000-8000-000000000002', '34000000-0000-4000-8000-000000000001', 'parent', true);

-- ── as the RECE ─────────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$select public.record_care_log('34000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001','36000000-0000-4000-8000-000000000001','sleep_check', now(), '{"breathing_ok": true, "position": "back"}', '42000000-0000-4000-8000-000000000001', '4242')$$,
  's33_1_sleep_check_under_24m_in_toddler_room_ok'
);

select throws_ok(
  $$select public.record_care_log('34000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002','36000000-0000-4000-8000-000000000001','sleep_check', now(), '{"breathing_ok": true}', '42000000-0000-4000-8000-000000000001', '4242')$$,
  'sleep checks apply to children under 24 months',
  's33_1_sleep_check_rejected_at_24_months_plus'
);

select throws_ok(
  $$select public.record_care_log('34000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000003','36000000-0000-4000-8000-000000000002','sleep_check', now(), '{"breathing_ok": true}', '42000000-0000-4000-8000-000000000001', '4242')$$,
  'sleep checks apply to infant, toddler or family rooms only',
  's33_1_sleep_check_rejected_in_preschool_room'
);

select throws_ok(
  $$select public.record_care_log('34000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001','36000000-0000-4000-8000-000000000001','meal', now(), '{"meal": "lunch"}', '42000000-0000-4000-8000-000000000001', '4242')$$,
  'invalid payload for care log type meal',
  'payload_meal_requires_eaten'
);

select lives_ok(
  $$select public.record_care_log('34000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001','36000000-0000-4000-8000-000000000001','health_observation', now(), '{"observation": "settled on arrival", "parent_reported": "restless night"}', '42000000-0000-4000-8000-000000000001', '4242')$$,
  's32_health_observation_with_parent_report'
);

select is(
  (select count(*) from public.record_care_log_bulk(
    '34000000-0000-4000-8000-000000000001',
    array['62000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002']::uuid[],
    '36000000-0000-4000-8000-000000000001','meal', now(), '{"meal": "lunch", "eaten": "most"}',
    '42000000-0000-4000-8000-000000000001', '4242')),
  2::bigint,
  'bulk_meal_logs_whole_room'
);

select lives_ok(
  $$select public.record_care_log('34000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001','36000000-0000-4000-8000-000000000001','outdoor', now(), '{"skipped_reason": "freezing rain", "minutes": 0}', '42000000-0000-4000-8000-000000000001', '4242')$$,
  's46_outdoor_skip_records_weather_reason'
);

select is(
  (select count(*) from public.care_log),
  5::bigint,
  'rece_sees_all_centre_logs'
);

-- ── as the parent: own child's logs only ────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select is(
  (select count(*) from public.care_log),
  4::bigint,
  's72_parent_sees_own_childs_logs_only'
);

select is(
  (select count(*) from public.care_log where child_id <> '62000000-0000-4000-8000-000000000001'),
  0::bigint,
  's72_no_other_childrens_logs_leak'
);

-- ── owner: immutability and audit ───────────────────────────────────────────
reset role;

select throws_ok(
  $$update public.care_log set payload = '{}' where log_type = 'meal'$$,
  'care logs are never updated; record a correction',
  'care_log_no_updates_only_corrections'
);

select is(
  (select count(*) from public.audit_event where table_name = 'care_log'),
  5::bigint,
  'audit_every_care_log_write'
);

select * from finish();
rollback;
