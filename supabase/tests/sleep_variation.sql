-- pgTAP: s. 33.1 sleep — back-to-sleep at the moment of placing, the written
-- direction that varies it, and the findings a sleeping room produces.
--
-- The line under test throughout: PLACING can be refused, OBSERVING never can.

begin;

create extension if not exists pgtap with schema extensions;

select plan(40);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '13000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rece@sv.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '13000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent@sv.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '13000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'other@sv.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('23000000-0000-4000-8000-000000000001', 'SV Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, timezone, opens_at, closes_at) values
  ('33000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', 'SV Centre', 'SV-1', '1 SV St, Toronto', 'America/Toronto', '07:00', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('35300000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', 'infant', 10),
  ('35300000-0000-4000-8000-000000000002', '33000000-0000-4000-8000-000000000001', 'toddler', 15);
insert into public.room (id, centre_id, age_group_id, name) values
  ('36300000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', '35300000-0000-4000-8000-000000000001', 'Infant room'),
  ('36300000-0000-4000-8000-000000000002', '33000000-0000-4000-8000-000000000001', '35300000-0000-4000-8000-000000000002', 'Toddler room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('43000000-0000-4000-8000-000000000001', '13000000-0000-4000-8000-000000000001', 'Rece SV', 'rece@sv.local'),
  ('43000000-0000-4000-8000-000000000002', '13000000-0000-4000-8000-000000000002', 'Priya Sharma', 'parent@sv.local'),
  ('43000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003', 'Other Adult', 'other@sv.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('43000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', 'rece', true),
  ('43000000-0000-4000-8000-000000000002', '33000000-0000-4000-8000-000000000001', 'family_adult', false),
  ('43000000-0000-4000-8000-000000000003', '33000000-0000-4000-8000-000000000001', 'family_adult', false);
insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('43000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

-- a six-month-old (the rule applies) and an eighteen-month-old (it does not)
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('63000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', 'Amara Bell', (current_date - interval '6 months')::date, '2026-01-05', '36300000-0000-4000-8000-000000000001'),
  ('63000000-0000-4000-8000-000000000002', '33000000-0000-4000-8000-000000000001', 'Theo Ward', (current_date - interval '18 months')::date, '2026-01-05', '36300000-0000-4000-8000-000000000002');

insert into public.household (id, centre_id, name) values
  ('53000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001', 'Bell household');
insert into public.child_household (child_id, household_id, centre_id) values
  ('63000000-0000-4000-8000-000000000001', '53000000-0000-4000-8000-000000000001', '33000000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('53000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000002', '33000000-0000-4000-8000-000000000001', 'parent', true, true),
  ('53000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000003', '33000000-0000-4000-8000-000000000001', 'other', true, false);

-- ── as the RECE ─────────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"13000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

-- ── the payload, now validated on this face too ─────────────────────────────
select throws_ok(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','36300000-0000-4000-8000-000000000001','nap_start', now(), '{"position":"tummy"}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  'invalid payload for care log type nap_start',
  's33_1_nap_start_position_must_be_one_of_the_three'
);

select throws_ok(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','36300000-0000-4000-8000-000000000001','sleep_check', now(), '{"breathing_ok":true,"position":"tummy"}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  'invalid payload for care log type sleep_check',
  's33_1_sleep_check_position_must_be_one_of_the_three'
);

select throws_ok(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','36300000-0000-4000-8000-000000000001','sleep_check', now(), '{"breathing_ok":true,"repositioned":"yes"}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  'invalid payload for care log type sleep_check',
  's33_1_repositioned_is_a_boolean_not_a_word'
);

-- ── placing: the write that can be refused ──────────────────────────────────
select throws_like(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','36300000-0000-4000-8000-000000000001','nap_start', now(), '{}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  '%record how Amara was placed for sleep%',
  's33_1_under_12_months_a_nap_without_a_position_is_refused'
);

select lives_ok(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','36300000-0000-4000-8000-000000000001','nap_start', now(), '{"position":"back"}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  's33_1_back_is_always_allowed'
);

select throws_like(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','36300000-0000-4000-8000-000000000001','nap_start', now(), '{"position":"front"}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  '%unless a physician has recommended otherwise in writing%',
  's33_1_front_without_a_direction_is_refused'
);

-- over twelve months, the rule does not apply and the log carries no position.
-- Anchored to 08:00 centre-local rather than now(): this child's measured
-- noon-to-14:30 nap is asserted at the bottom of the file, and a now() nap
-- lands BETWEEN those two whenever the suite runs shortly after local noon —
-- which made the long-rest test read 149 minutes instead of 150, once a day,
-- for exactly as long as it took somebody to run the suite at lunchtime.
select lives_ok(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000002','36300000-0000-4000-8000-000000000002','nap_start', (((now() at time zone 'America/Toronto')::date + time '08:00') at time zone 'America/Toronto'), '{}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  's33_1_over_12_months_needs_no_recorded_position'
);

-- ── who may vary it ─────────────────────────────────────────────────────────
-- Through the RPC, which is the only way in: sleep_direction has no client
-- write policy, so a direct insert is refused by RLS before a CHECK constraint
-- is ever reached, and would prove nothing about the constraint.
select throws_ok(
  $$select public.record_sleep_direction('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','parent','position','she sleeps better on her front', array['front'], null, '43000000-0000-4000-8000-000000000002', null, null, '43000000-0000-4000-8000-000000000001','4242')$$,
  '23514',
  null,
  's33_1_a_parent_cannot_authorise_a_sleep_position'
);

select throws_ok(
  $$select public.record_sleep_direction('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','physician','position','x', array['upside_down'], 'Dr Chen', null, null, null, '43000000-0000-4000-8000-000000000001','4242')$$,
  '23514',
  null,
  's33_1_a_direction_cannot_permit_a_position_that_does_not_exist'
);

select throws_ok(
  $$select public.record_sleep_direction('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','physician','position','reflux', array['side'], null, null, null, null, '43000000-0000-4000-8000-000000000001','4242')$$,
  'a physician''s direction names the physician',
  's33_1_a_physicians_direction_names_the_physician'
);

select throws_ok(
  $$select public.record_sleep_direction('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','parent','rest','no nap after 2pm', null, null, '43000000-0000-4000-8000-000000000003', null, null, '43000000-0000-4000-8000-000000000001','4242')$$,
  'the direction must come from a consenting household member',
  's33_1_a_rest_request_comes_from_someone_who_may_consent'
);

select lives_ok(
  $$select public.record_sleep_direction('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','parent','rest','Wake her by 2pm or she will not settle at home.', null, null, '43000000-0000-4000-8000-000000000002', null, null, '43000000-0000-4000-8000-000000000001','4242')$$,
  's33_1_a_family_rest_request_is_recorded'
);

-- ── the physician's direction, and what it does and does not permit ─────────
select lives_ok(
  $$select public.record_sleep_direction('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','physician','position','Side-lying permitted for reflux; back at all other times.', array['side'], 'Dr Chen, Sick Kids', null, null, null, '43000000-0000-4000-8000-000000000001','4242')$$,
  's33_1_a_physicians_position_direction_is_recorded'
);

select lives_ok(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','36300000-0000-4000-8000-000000000001','nap_start', now(), '{"position":"side"}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  's33_1_the_direction_permits_exactly_what_it_says'
);

select throws_like(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','36300000-0000-4000-8000-000000000001','nap_start', now(), '{"position":"front"}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  '%unless a physician has recommended otherwise in writing%',
  's33_1_a_direction_for_side_does_not_permit_front'
);

select ok(
  'back' = any (app.permitted_sleep_positions('63000000-0000-4000-8000-000000000001', current_date)),
  's33_1_back_stays_permitted_even_under_a_direction_that_does_not_name_it'
);

select is(
  (select count(*)::integer from public.sleep_direction
   where child_id = '63000000-0000-4000-8000-000000000001' and ended_at is null),
  2,
  's33_1_a_position_note_and_a_rest_request_coexist'
);

-- a new direction of the same kind supersedes; the other kind is untouched
select lives_ok(
  $$select public.record_sleep_direction('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','physician','position','Back only from now on; reflux resolved.', array['back'], 'Dr Chen, Sick Kids', null, null, null, '43000000-0000-4000-8000-000000000001','4242')$$,
  's33_1_a_replacement_direction_is_recorded'
);

select is(
  (select count(*)::integer from public.sleep_direction
   where child_id = '63000000-0000-4000-8000-000000000001' and kind = 'position' and ended_at is null),
  1,
  's33_1_only_one_position_direction_is_live'
);

select is(
  (select count(*)::integer from public.sleep_direction
   where child_id = '63000000-0000-4000-8000-000000000001' and kind = 'rest' and ended_at is null),
  1,
  's33_1_superseding_a_position_note_leaves_the_family_request_alone'
);

select throws_like(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','36300000-0000-4000-8000-000000000001','nap_start', now(), '{"position":"side"}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  '%unless a physician has recommended otherwise in writing%',
  's33_1_the_superseded_direction_no_longer_permits_side'
);

-- ── dates ───────────────────────────────────────────────────────────────────
select lives_ok(
  $$select public.record_sleep_direction('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','physician','position','Side-lying, ended last week.', array['side'], 'Dr Chen', null, (current_date - 30), (current_date - 7), '43000000-0000-4000-8000-000000000001','4242')$$,
  's33_1_a_direction_can_be_recorded_with_a_past_window'
);

select ok(
  not ('side' = any (app.permitted_sleep_positions('63000000-0000-4000-8000-000000000001', current_date))),
  's33_1_a_direction_that_has_expired_permits_nothing'
);

select ok(
  'side' = any (app.permitted_sleep_positions('63000000-0000-4000-8000-000000000001', current_date - 10)),
  's33_1_but_it_did_permit_on_a_day_inside_its_window'
);

-- ── observing: the write that is never refused ──────────────────────────────
select lives_ok(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','36300000-0000-4000-8000-000000000001','sleep_check', now(), '{"breathing_ok":true,"position":"front","repositioned":true}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  's33_1_a_baby_found_on_their_front_is_always_recordable'
);

select is(
  (select count(*)::integer from public.sleep_position_finding
   where child_id = '63000000-0000-4000-8000-000000000001'),
  1,
  's33_1_and_it_surfaces_as_a_finding_rather_than_vanishing'
);

select is(
  (select found_position from public.sleep_position_finding
   where child_id = '63000000-0000-4000-8000-000000000001'),
  'front',
  's33_1_the_finding_says_what_was_seen'
);

select ok(
  (select repositioned from public.sleep_position_finding
   where child_id = '63000000-0000-4000-8000-000000000001'),
  's33_1_the_finding_says_whether_the_child_was_moved_back'
);

select ok(
  exists (
    select 1 from public.daily_written_record dwr, jsonb_array_elements(dwr.refs) r
    where dwr.centre_id = '33000000-0000-4000-8000-000000000001'
      and r ->> 'type' = 'sleep_position'
      and r ->> 'note' like '%Amara was found on their front%'
      and r ->> 'note' like '%was placed back%'
  ),
  's37_the_days_record_hears_about_the_sleep_position'
);

-- a check that matches a live direction is not a finding
select lives_ok(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','36300000-0000-4000-8000-000000000001','sleep_check', now(), '{"breathing_ok":true,"position":"back"}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  's33_1_a_check_finding_the_child_on_their_back_is_fine'
);

select is(
  (select count(*)::integer from public.sleep_position_finding
   where child_id = '63000000-0000-4000-8000-000000000001'),
  1,
  's33_1_and_it_adds_no_finding'
);

-- ── rest longer than two hours ──────────────────────────────────────────────
select lives_ok(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000002','36300000-0000-4000-8000-000000000002','nap_start', (((now() at time zone 'America/Toronto')::date + time '12:00') at time zone 'America/Toronto'), '{}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  's33_1_a_toddler_is_laid_down_at_noon'
);

select lives_ok(
  $$select public.record_care_log('33000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000002','36300000-0000-4000-8000-000000000002','nap_end', (((now() at time zone 'America/Toronto')::date + time '14:30') at time zone 'America/Toronto'), '{}', '43000000-0000-4000-8000-000000000001', '4242')$$,
  's33_1_and_wakes_two_and_a_half_hours_later_which_is_never_refused'
);

select is(
  (select minutes from public.long_rest_finding
   where child_id = '63000000-0000-4000-8000-000000000002'),
  150,
  's33_1_the_long_rest_is_measured_not_rounded_away'
);

select ok(
  exists (
    select 1 from public.daily_written_record dwr, jsonb_array_elements(dwr.refs) r
    where dwr.centre_id = '33000000-0000-4000-8000-000000000001'
      and r ->> 'type' = 'long_rest'
      and r ->> 'note' like '%Theo rested 150 minutes%'
  ),
  's37_the_days_record_hears_about_the_long_rest'
);

-- ── what the room device is told before the tap ─────────────────────────────
-- The nap board offers the positions this child may be placed in, so an
-- educator is never offered a choice the write will then refuse.
select is(
  (select positions from public.sleep_placement_options('63000000-0000-4000-8000-000000000001')),
  array['back'],
  's33_1_the_nap_board_offers_only_what_the_file_permits'
);

-- ── the record is never destroyed, at either layer ──────────────────────────
-- Two different mechanisms, and they fail differently. RLS gives the table no
-- delete policy, so a client's DELETE matches no rows and QUIETLY removes
-- nothing — no exception to catch, which is why this is asserted as a count
-- rather than as a throw.
select lives_ok(
  $$delete from public.sleep_direction where child_id = '63000000-0000-4000-8000-000000000001'$$,
  's33_1_a_clients_delete_raises_nothing_because_it_matches_nothing'
);

select is(
  (select count(*)::integer from public.sleep_direction
   where child_id = '63000000-0000-4000-8000-000000000001'),
  4,
  's33_1_and_every_direction_is_still_there'
);

-- The trigger is the backstop for everything that gets past RLS — a definer
-- function, a migration, the service role, a console at 2 a.m.
reset role;
select throws_ok(
  $$delete from public.sleep_direction where child_id = '63000000-0000-4000-8000-000000000001'$$,
  'audit_event is append-only',
  's33_1_and_a_delete_that_gets_past_rls_is_refused_outright'
);

-- ── the family sees their own child's directions ────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"13000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select ok(
  (select count(*) from public.sleep_direction
   where child_id = '63000000-0000-4000-8000-000000000001') > 0,
  's33_1_a_parent_reads_the_directions_on_file_for_their_own_child'
);

select * from finish();
rollback;
