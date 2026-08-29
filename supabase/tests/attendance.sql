-- pgTAP: s. 72(3) attendance, s. 50 safe dismissal, ss. 8 shift counting,
-- PIN-verified write RPCs. Named for their regulation sections.

begin;

create extension if not exists pgtap with schema extensions;

select plan(18);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '11000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rece@att.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '11000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'vol@att.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '11000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'parent@att.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('21000000-0000-4000-8000-000000000001', 'Att Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('31000000-0000-4000-8000-000000000001', '21000000-0000-4000-8000-000000000001', 'Att Centre', 'ATT-1', '1 Att St, Toronto', '07:30', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('32000000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001', 'toddler', 15);
insert into public.room (id, centre_id, age_group_id, name) values
  ('33000000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000001', 'Toddler room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('41000000-0000-4000-8000-000000000001', '11000000-0000-4000-8000-000000000001', 'Rece Att', 'rece@att.local'),
  ('41000000-0000-4000-8000-000000000002', '11000000-0000-4000-8000-000000000002', 'Vol Att', 'vol@att.local'),
  ('41000000-0000-4000-8000-000000000003', '11000000-0000-4000-8000-000000000003', 'Parent Att', 'parent@att.local'),
  ('41000000-0000-4000-8000-000000000004', null, 'Restricted Ex', 'ex@att.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('41000000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001', 'rece', true),
  ('41000000-0000-4000-8000-000000000002', '31000000-0000-4000-8000-000000000001', 'volunteer', false),
  ('41000000-0000-4000-8000-000000000003', '31000000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('41000000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('51000000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001', 'Att Household');
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('61000000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001', 'Att Child', '2025-01-15', '2026-01-05', '33000000-0000-4000-8000-000000000001'),
  ('61000000-0000-4000-8000-000000000002', '31000000-0000-4000-8000-000000000001', 'Other Child', '2025-02-15', '2026-01-05', '33000000-0000-4000-8000-000000000001');
insert into public.child_household (child_id, household_id, centre_id) values
  ('61000000-0000-4000-8000-000000000001', '51000000-0000-4000-8000-000000000001', '31000000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view) values
  ('51000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000003', '31000000-0000-4000-8000-000000000001', 'parent', true);

insert into public.pickup_restriction (centre_id, child_id, restricted_person_id, restricted_person_name, staff_note) values
  ('31000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001', '41000000-0000-4000-8000-000000000004', 'Restricted Ex', 'Court order on file. Call the supervisor before any release discussion.');

-- ── as the RECE ─────────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select throws_ok(
  $$select public.record_attendance('31000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','depart','33000000-0000-4000-8000-000000000001', now(), '41000000-0000-4000-8000-000000000001', '4242')$$,
  'depart requires a same-day arrive',
  's72_depart_requires_same_day_arrive'
);

select lives_ok(
  $$select public.record_attendance('31000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','arrive','33000000-0000-4000-8000-000000000001', now(), '41000000-0000-4000-8000-000000000001', '4242')$$,
  's72_arrive_records_with_valid_pin'
);

select throws_ok(
  $$select public.record_attendance('31000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','arrive','33000000-0000-4000-8000-000000000001', now(), '41000000-0000-4000-8000-000000000001', '9999')$$,
  'invalid staff PIN',
  'pin_wrong_pin_rejected'
);

select throws_ok(
  $$select public.record_attendance('31000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','depart','33000000-0000-4000-8000-000000000001', now(), '41000000-0000-4000-8000-000000000001', '4242', '41000000-0000-4000-8000-000000000004')$$,
  'release blocked: this person is restricted for this child',
  's50_restricted_pickup_blocked_at_sql'
);

select lives_ok(
  $$select public.record_attendance('31000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','depart','33000000-0000-4000-8000-000000000001', now(), '41000000-0000-4000-8000-000000000001', '4242', '41000000-0000-4000-8000-000000000003')$$,
  's50_release_to_authorised_parent_ok'
);

select is(
  (select count(*) from public.attendance_event where actual_time is null),
  0::bigint,
  's72_actual_time_always_present'
);

select throws_ok(
  $$select public.record_attendance('31000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','arrive','33000000-0000-4000-8000-000000000001', now(), '41000000-0000-4000-8000-000000000001', '4242', null, null, null, null, '00000000-0000-4000-8000-000000000099', 'typo fix')$$,
  'correction must reference an event for the same child',
  's72_correction_must_reference_same_child'
);

select throws_ok(
  $$insert into public.staff_shift (centre_id, person_id, room_id, shift_date, in_at, counted_in_ratio)
    values ('31000000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000002','33000000-0000-4000-8000-000000000001', current_date, now(), true)$$,
  '42501',
  null,
  's8_no_direct_shift_inserts'
);

select lives_ok(
  $$select public.record_staff_shift('31000000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000002','33000000-0000-4000-8000-000000000001', now(), '41000000-0000-4000-8000-000000000001', '4242')$$,
  's8_volunteer_shift_recorded_via_rpc'
);

select is(
  (select counted_in_ratio from public.staff_shift where person_id = '41000000-0000-4000-8000-000000000002'),
  false,
  's8_volunteer_never_counted_in_ratio'
);

select lives_ok(
  $$select public.record_staff_shift('31000000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001', now(), '41000000-0000-4000-8000-000000000001', '4242')$$,
  's8_rece_shift_recorded_via_rpc'
);

select is(
  (select counted_in_ratio from public.staff_shift where person_id = '41000000-0000-4000-8000-000000000001'),
  true,
  's8_rece_counted_in_ratio'
);

-- ── as the volunteer: cannot record ─────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select throws_ok(
  $$select public.record_attendance('31000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000002','arrive','33000000-0000-4000-8000-000000000001', now(), '41000000-0000-4000-8000-000000000002', '4242')$$,
  'not authorised for this centre',
  's8_volunteer_cannot_record_attendance'
);

-- ── as the parent: own child's attendance only, no staff shifts ─────────────
select set_config('request.jwt.claims', '{"sub":"11000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select is(
  (select count(*) from public.attendance_event),
  2::bigint,
  's72_parent_sees_own_childs_attendance_only'
);

select is(
  (select count(*) from public.staff_shift),
  0::bigint,
  's72_parent_sees_no_staff_shifts'
);

-- ── as owner (bypasses RLS): audit written, and the triggers themselves hold ─
reset role;

select is(
  (select count(*) from public.audit_event
   where table_name = 'attendance_event' and centre_id = '31000000-0000-4000-8000-000000000001'),
  2::bigint,
  'audit_every_attendance_write'
);

select throws_ok(
  $$update public.attendance_event set actual_time = now() where event_type = 'arrive'$$,
  'attendance events are never updated; record a correction',
  's72_no_updates_only_corrections'
);

select throws_like(
  $$delete from public.attendance_event where true$$,
  '%append-only%',
  'never_attendance_rows_deleted'
);

select * from finish();
rollback;
