-- pgTAP: headcount checks — the supervision layer (s. 11 supervision, Part 4
-- drill records). Sessions never write attendance; a headcount records that a
-- named person counted faces at a moment that matters, and drills/evacuations
-- cross-reference themselves into the daily written record (s. 37).

begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '18000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rece@hc.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '18000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'vol@hc.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '18000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'parent@hc.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('28000000-0000-4000-8000-000000000001', 'HC Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('38000000-0000-4000-8000-000000000001', '28000000-0000-4000-8000-000000000001', 'HC Centre', 'HC-1', '1 HC St, Toronto', '07:30', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('39000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('3a000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', '39000000-0000-4000-8000-000000000001', 'Preschool room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('48000000-0000-4000-8000-000000000001', '18000000-0000-4000-8000-000000000001', 'Rece HC', 'rece@hc.local'),
  ('48000000-0000-4000-8000-000000000002', '18000000-0000-4000-8000-000000000002', 'Vol HC', 'vol@hc.local'),
  ('48000000-0000-4000-8000-000000000003', '18000000-0000-4000-8000-000000000003', 'Parent HC', 'parent@hc.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('48000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', 'rece', true),
  ('48000000-0000-4000-8000-000000000002', '38000000-0000-4000-8000-000000000001', 'volunteer', false),
  ('48000000-0000-4000-8000-000000000003', '38000000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('48000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('58000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', 'HC Household');
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('68000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', 'HC Child', '2023-03-15', '2026-01-05', '3a000000-0000-4000-8000-000000000001');
insert into public.child_household (child_id, household_id, centre_id) values
  ('68000000-0000-4000-8000-000000000001', '58000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view) values
  ('58000000-0000-4000-8000-000000000001', '48000000-0000-4000-8000-000000000003', '38000000-0000-4000-8000-000000000001', 'parent', true);

-- ── as the RECE ─────────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"18000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$select public.record_headcount('38000000-0000-4000-8000-000000000001','3a000000-0000-4000-8000-000000000001','transition_out', 8, 7,
    '[{"child_id":"68000000-0000-4000-8000-000000000001","full_name":"HC Child"}]'::jsonb, 'washroom straggler', '48000000-0000-4000-8000-000000000001', '4242')$$,
  's11_transition_headcount_records_with_valid_pin'
);

select is(
  (select missing -> 0 ->> 'full_name' from public.headcount_check where kind = 'transition_out'),
  'HC Child',
  's11_missing_snapshot_names_the_child'
);

select throws_ok(
  $$select public.record_headcount('38000000-0000-4000-8000-000000000001','3a000000-0000-4000-8000-000000000001','spot', 8, 8, '[]'::jsonb, null, '48000000-0000-4000-8000-000000000001', '9999')$$,
  'invalid staff PIN',
  'pin_wrong_pin_rejected'
);

select throws_ok(
  $$select public.record_headcount('38000000-0000-4000-8000-000000000001','3a000000-0000-4000-8000-000000000001','recess', 8, 8, '[]'::jsonb, null, '48000000-0000-4000-8000-000000000001', '4242')$$,
  '23514',
  null,
  'only_the_five_headcount_kinds_exist'
);

select throws_ok(
  $$insert into public.headcount_check (centre_id, room_id, kind, expected, counted, recorded_by)
    values ('38000000-0000-4000-8000-000000000001','3a000000-0000-4000-8000-000000000001','spot', 8, 8, '48000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'no_direct_headcount_inserts'
);

select lives_ok(
  $$select public.record_headcount('38000000-0000-4000-8000-000000000001', null, 'evacuation_drill', 8, 8, '[]'::jsonb, 'monthly fire drill', '48000000-0000-4000-8000-000000000001', '4242')$$,
  'part4_drill_recorded_centre_wide'
);

-- ── as the volunteer: cannot record ─────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"18000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select throws_ok(
  $$select public.record_headcount('38000000-0000-4000-8000-000000000001','3a000000-0000-4000-8000-000000000001','spot', 8, 8, '[]'::jsonb, null, '48000000-0000-4000-8000-000000000002', '4242')$$,
  'not authorised for this centre',
  's11_volunteer_cannot_record_headcounts'
);

-- ── as the parent: supervision records are an operator surface ──────────────
select set_config('request.jwt.claims', '{"sub":"18000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select is(
  (select count(*) from public.headcount_check),
  0::bigint,
  's11_parents_never_see_headcounts'
);

-- ── as owner: cross-reference, audit, append-only ───────────────────────────
reset role;

select is(
  (select count(*)
   from public.daily_written_record dwr, jsonb_array_elements(dwr.refs) ref
   where dwr.centre_id = '38000000-0000-4000-8000-000000000001'
     and ref ->> 'type' = 'evacuation_drill'),
  1::bigint,
  's37_drill_cross_referenced_into_dwr'
);

select is(
  (select count(*) from public.audit_event
   where table_name = 'headcount_check' and centre_id = '38000000-0000-4000-8000-000000000001'),
  2::bigint,
  'audit_every_headcount_write'
);

select throws_like(
  $$delete from public.headcount_check where true$$,
  '%append-only%',
  'never_headcount_rows_deleted'
);

select * from finish();
rollback;
