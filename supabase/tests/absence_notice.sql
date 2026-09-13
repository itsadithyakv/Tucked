-- pgTAP: absence notices (s. 50 safe arrival) — a family can say "not today"
-- or "running late", and doing so NEVER touches the s. 72(3) legal register.

begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '1a000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rece@an.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1a000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent@an.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1a000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'stranger@an.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1a000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'revoked@an.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('2a000000-0000-4000-8000-000000000001', 'AN Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, timezone, opens_at, closes_at) values
  ('3a100000-0000-4000-8000-000000000001', '2a000000-0000-4000-8000-000000000001', 'AN Centre', 'AN-1', '1 AN St, Toronto', 'America/Toronto', '07:00', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('3a200000-0000-4000-8000-000000000001', '3a100000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('3a300000-0000-4000-8000-000000000001', '3a100000-0000-4000-8000-000000000001', '3a200000-0000-4000-8000-000000000001', 'Preschool room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('4a000000-0000-4000-8000-000000000001', '1a000000-0000-4000-8000-000000000001', 'Rece AN', 'rece@an.local'),
  ('4a000000-0000-4000-8000-000000000002', '1a000000-0000-4000-8000-000000000002', 'Nadia Karimi', 'parent@an.local'),
  ('4a000000-0000-4000-8000-000000000003', '1a000000-0000-4000-8000-000000000003', 'Other Parent', 'stranger@an.local'),
  ('4a000000-0000-4000-8000-000000000004', '1a000000-0000-4000-8000-000000000004', 'Former Partner', 'revoked@an.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('4a000000-0000-4000-8000-000000000001', '3a100000-0000-4000-8000-000000000001', 'rece', true),
  ('4a000000-0000-4000-8000-000000000002', '3a100000-0000-4000-8000-000000000001', 'family_adult', false),
  ('4a000000-0000-4000-8000-000000000003', '3a100000-0000-4000-8000-000000000001', 'family_adult', false),
  ('4a000000-0000-4000-8000-000000000004', '3a100000-0000-4000-8000-000000000001', 'family_adult', false);
insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('4a000000-0000-4000-8000-000000000001', '3a100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('6a000000-0000-4000-8000-000000000001', '3a100000-0000-4000-8000-000000000001', 'Samir Karimi', (current_date - interval '3 years')::date, '2026-01-05', '3a300000-0000-4000-8000-000000000001'),
  ('6a000000-0000-4000-8000-000000000002', '3a100000-0000-4000-8000-000000000001', 'Leila Karimi', (current_date - interval '4 years')::date, '2026-01-05', '3a300000-0000-4000-8000-000000000001'),
  ('6a000000-0000-4000-8000-000000000003', '3a100000-0000-4000-8000-000000000001', 'Other Child', (current_date - interval '3 years')::date, '2026-01-05', '3a300000-0000-4000-8000-000000000001');

insert into public.household (id, centre_id, name) values
  ('5a000000-0000-4000-8000-000000000001', '3a100000-0000-4000-8000-000000000001', 'Karimi household'),
  ('5a000000-0000-4000-8000-000000000002', '3a100000-0000-4000-8000-000000000001', 'Other household');
insert into public.child_household (child_id, household_id, centre_id) values
  ('6a000000-0000-4000-8000-000000000001', '5a000000-0000-4000-8000-000000000001', '3a100000-0000-4000-8000-000000000001'),
  ('6a000000-0000-4000-8000-000000000002', '5a000000-0000-4000-8000-000000000001', '3a100000-0000-4000-8000-000000000001'),
  ('6a000000-0000-4000-8000-000000000003', '5a000000-0000-4000-8000-000000000002', '3a100000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, revoked_at) values
  ('5a000000-0000-4000-8000-000000000001', '4a000000-0000-4000-8000-000000000002', '3a100000-0000-4000-8000-000000000001', 'parent', true, null),
  ('5a000000-0000-4000-8000-000000000002', '4a000000-0000-4000-8000-000000000003', '3a100000-0000-4000-8000-000000000001', 'parent', true, null),
  ('5a000000-0000-4000-8000-000000000001', '4a000000-0000-4000-8000-000000000004', '3a100000-0000-4000-8000-000000000001', 'parent', true, now() - interval '1 month');

-- ── as the parent ───────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1a000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$select public.report_absence('6a000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date, 'late', '10:15', 'dentist')$$,
  's50_a_parent_says_running_late'
);

select is(
  (select kind from public.absence_notice where child_id = '6a000000-0000-4000-8000-000000000001' and withdrawn_at is null),
  'late',
  's50_the_parent_sees_their_own_notice'
);

select throws_ok(
  $$select public.report_absence('6a000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date, 'late', null, null)$$,
  'say roughly when you expect to arrive',
  's50_running_late_says_when'
);

select throws_like(
  $$select public.report_absence('6a000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date + 1, 'late', '10:00', null)$$,
  '%running late is about today%',
  's50_running_late_is_only_about_today'
);

select throws_ok(
  $$select public.report_absence('6a000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date - 1, 'absent', null, null)$$,
  'a notice is about today or a day ahead, not a day that has passed',
  's50_a_notice_is_never_backdated'
);

-- "late" becomes "not coming": the new notice replaces, the old one survives
select lives_ok(
  $$select public.report_absence('6a000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date, 'absent', null, 'unwell')$$,
  's50_the_family_changes_their_mind'
);

select is(
  (select count(*)::integer from public.absence_notice where child_id = '6a000000-0000-4000-8000-000000000001' and withdrawn_at is null),
  1,
  's50_only_one_notice_is_live_for_the_day'
);

select is(
  (select kind from public.absence_notice where child_id = '6a000000-0000-4000-8000-000000000001' and withdrawn_at is null),
  'absent',
  's50_and_it_is_the_newest_one'
);

select is(
  (select count(*)::integer from public.absence_notice where child_id = '6a000000-0000-4000-8000-000000000001'),
  2,
  's50_the_replaced_notice_is_withdrawn_not_deleted'
);

select lives_ok(
  $$select public.report_absence('6a000000-0000-4000-8000-000000000002', (now() at time zone 'America/Toronto')::date + 3, 'absent', null, 'family trip')$$,
  's50_a_notice_can_be_given_days_ahead'
);

select throws_ok(
  $$select public.report_absence('6a000000-0000-4000-8000-000000000002', (now() at time zone 'America/Toronto')::date, 'absent', null, repeat('x', 281))$$,
  '23514',
  null,
  's50_a_reason_is_short_because_no_diagnosis_is_owed'
);

select lives_ok(
  $$select public.withdraw_absence_notice((select id from public.absence_notice where child_id = '6a000000-0000-4000-8000-000000000002' and withdrawn_at is null))$$,
  's50_a_parent_can_take_a_notice_back'
);

-- ── as another family ───────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1a000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select throws_ok(
  $$select public.report_absence('6a000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date, 'absent', null, null)$$,
  'only a family adult of this child can tell the centre',
  's50_another_family_cannot_speak_for_this_child'
);

select is(
  (select count(*)::integer from public.absence_notice where child_id = '6a000000-0000-4000-8000-000000000001'),
  0,
  's50_and_cannot_even_see_that_a_notice_exists'
);

-- ── as a revoked household member ───────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1a000000-0000-4000-8000-000000000004","role":"authenticated"}', true);

select throws_ok(
  $$select public.report_absence('6a000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date, 'absent', null, null)$$,
  'only a family adult of this child can tell the centre',
  's50_a_revoked_adult_cannot_either'
);

-- ── as the room ─────────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1a000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select is(
  (select count(*)::integer from public.absence_notice
   where centre_id = '3a100000-0000-4000-8000-000000000001'
     and notice_date = (now() at time zone 'America/Toronto')::date
     and withdrawn_at is null),
  1,
  's50_the_room_sees_todays_live_notices'
);

select lives_ok(
  $$select public.record_attendance('3a100000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000003', 'arrive', '3a300000-0000-4000-8000-000000000001', now(), '4a000000-0000-4000-8000-000000000001', '4242')$$,
  'a_child_arrives'
);

-- ── the other family, about a child already here ────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1a000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select throws_like(
  $$select public.report_absence('6a000000-0000-4000-8000-000000000003', (now() at time zone 'America/Toronto')::date, 'absent', null, null)$$,
  '%Other is already signed in today%',
  's50_a_child_who_is_here_is_the_rooms_to_talk_about'
);

-- ── the property that matters most ──────────────────────────────────────────
reset role;

select is(
  (select count(*)::integer from public.attendance_event
   where child_id in ('6a000000-0000-4000-8000-000000000001', '6a000000-0000-4000-8000-000000000002')),
  0,
  's72_3_a_notice_never_writes_to_the_legal_register'
);

select throws_ok(
  $$update public.absence_notice set reason = 'changed' where child_id = '6a000000-0000-4000-8000-000000000001' and withdrawn_at is null$$,
  'a notice is never edited; give a new one and it replaces this',
  's50_a_notice_is_never_edited_even_past_rls'
);

select * from finish();
rollback;
