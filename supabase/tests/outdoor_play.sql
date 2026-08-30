-- pgTAP: outdoor play (s. 47). The load-bearing rules: minutes are measured
-- from two clock times and never typed; the requirement is jurisdiction data;
-- a short day carries a written reason that lands in the daily written record;
-- a child is kept in only on a physician's or a parent's written instruction;
-- and the per-child figure respects the child's own attendance, so a child who
-- arrived after the morning block is not credited with it.

begin;

create extension if not exists pgtap with schema extensions;

select plan(32);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000f1', 'authenticated', 'authenticated', 'sup@od.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000f2', 'authenticated', 'authenticated', 'parent@od.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000f3', 'authenticated', 'authenticated', 'aunt@od.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('21400000-0000-4000-8000-000000000001', 'Outdoor Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('31400000-0000-4000-8000-000000000001', '21400000-0000-4000-8000-000000000001', 'Outdoor Centre', 'OD-1', '1 Park Ave, Toronto', '07:30', '18:00');

insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('32400000-0000-4000-8000-000000000001', '31400000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('33400000-0000-4000-8000-000000000001', '31400000-0000-4000-8000-000000000001', '32400000-0000-4000-8000-000000000001', 'Maple room'),
  ('33400000-0000-4000-8000-000000000002', '31400000-0000-4000-8000-000000000001', '32400000-0000-4000-8000-000000000001', 'Cedar room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('41400000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000f1', 'Sup Outdoor', 'sup@od.local'),
  ('41400000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000f2', 'Parent Outdoor', 'parent@od.local'),
  ('41400000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-0000000000f3', 'Aunt Outdoor', 'aunt@od.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('41400000-0000-4000-8000-000000000001', '31400000-0000-4000-8000-000000000001', 'supervisor', true),
  ('41400000-0000-4000-8000-000000000002', '31400000-0000-4000-8000-000000000001', 'family_adult', false),
  ('41400000-0000-4000-8000-000000000003', '31400000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('41400000-0000-4000-8000-000000000001', '31400000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('51400000-0000-4000-8000-000000000001', '31400000-0000-4000-8000-000000000001', 'Outdoor Household');
-- an all-day child and a child who arrives after lunch, both preschool age
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('61400000-0000-4000-8000-000000000001', '31400000-0000-4000-8000-000000000001', 'Wren Field', (current_date - interval '4 years')::date, '2026-01-05', '33400000-0000-4000-8000-000000000001'),
  ('61400000-0000-4000-8000-000000000002', '31400000-0000-4000-8000-000000000001', 'Otto Field', (current_date - interval '3 years')::date, '2026-01-05', '33400000-0000-4000-8000-000000000001'),
  -- an infant, below the age floor in the rule pack
  ('61400000-0000-4000-8000-000000000003', '31400000-0000-4000-8000-000000000001', 'Baby Field', (current_date - interval '9 months')::date, '2026-01-05', '33400000-0000-4000-8000-000000000001');
insert into public.child_household (child_id, household_id, centre_id) values
  ('61400000-0000-4000-8000-000000000001', '51400000-0000-4000-8000-000000000001', '31400000-0000-4000-8000-000000000001'),
  ('61400000-0000-4000-8000-000000000002', '51400000-0000-4000-8000-000000000001', '31400000-0000-4000-8000-000000000001'),
  ('61400000-0000-4000-8000-000000000003', '51400000-0000-4000-8000-000000000001', '31400000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('51400000-0000-4000-8000-000000000001', '41400000-0000-4000-8000-000000000002', '31400000-0000-4000-8000-000000000001', 'parent', true, true),
  ('51400000-0000-4000-8000-000000000001', '41400000-0000-4000-8000-000000000003', '31400000-0000-4000-8000-000000000001', 'other', true, false);

-- Attendance for YESTERDAY, a day that is over in the centre's own timezone
-- whatever the clock says when this suite runs. Wren and the infant are there
-- all day; Otto arrives after lunch and so misses the morning block.
insert into public.attendance_event (centre_id, child_id, room_id, event_type, actual_time, attendance_date, recorded_by) values
  ('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000001', 'arrive', ((current_date - 1)::timestamp + time '08:00') at time zone 'America/Toronto', current_date - 1, '41400000-0000-4000-8000-000000000001'),
  ('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000001', 'depart', ((current_date - 1)::timestamp + time '17:00') at time zone 'America/Toronto', current_date - 1, '41400000-0000-4000-8000-000000000001'),
  ('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000003', '33400000-0000-4000-8000-000000000001', 'arrive', ((current_date - 1)::timestamp + time '08:00') at time zone 'America/Toronto', current_date - 1, '41400000-0000-4000-8000-000000000001'),
  ('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000003', '33400000-0000-4000-8000-000000000001', 'depart', ((current_date - 1)::timestamp + time '17:00') at time zone 'America/Toronto', current_date - 1, '41400000-0000-4000-8000-000000000001'),
  ('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000002', '33400000-0000-4000-8000-000000000001', 'arrive', ((current_date - 1)::timestamp + time '13:00') at time zone 'America/Toronto', current_date - 1, '41400000-0000-4000-8000-000000000001'),
  ('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000002', '33400000-0000-4000-8000-000000000001', 'depart', ((current_date - 1)::timestamp + time '17:00') at time zone 'America/Toronto', current_date - 1, '41400000-0000-4000-8000-000000000001');

-- ── the requirement is data ─────────────────────────────────────────────────
select is(
  app.outdoor_required_minutes('31400000-0000-4000-8000-000000000001', 8, 48),
  120,
  's47_two_hours_for_a_child_in_care_all_day'
);

select is(
  app.outdoor_required_minutes('31400000-0000-4000-8000-000000000001', 3, 48),
  30,
  's47_half_an_hour_for_a_short_day'
);

select is(
  app.outdoor_required_minutes('31400000-0000-4000-8000-000000000001', 8, 9),
  0,
  's47_the_age_floor_is_part_of_the_rule_pack'
);

-- ── as the supervisor: going out and coming in ──────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;

select throws_like(
  $$select public.end_outdoor_period('33400000-0000-4000-8000-000000000001', '41400000-0000-4000-8000-000000000001', '4242')$$,
  '%is not outside%',
  's47_cannot_come_in_from_a_walk_that_never_started'
);

select lives_ok(
  $$select public.start_outdoor_period('31400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000001', 'fine', '41400000-0000-4000-8000-000000000001', '4242')$$,
  's47_the_group_goes_out'
);

select throws_like(
  $$select public.start_outdoor_period('31400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000001', 'fine', '41400000-0000-4000-8000-000000000001', '4242')$$,
  '%already outside%',
  's47_a_room_is_never_outside_twice_at_once'
);

select is(
  (select outside_now from public.outdoor_day where room_id = '33400000-0000-4000-8000-000000000001'),
  true,
  's47_the_board_shows_the_room_is_outside'
);

select lives_ok(
  $$select public.end_outdoor_period('33400000-0000-4000-8000-000000000001', '41400000-0000-4000-8000-000000000001', '4242')$$,
  's47_the_group_comes_in'
);

-- ── the measurement is not typed ────────────────────────────────────────────
-- there is no parameter anywhere that accepts a number of minutes
select is(
  (select count(*)
   from information_schema.routines r
   join information_schema.parameters p
     on p.specific_schema = r.specific_schema and p.specific_name = r.specific_name
   where r.specific_schema = 'public'
     and r.routine_name in ('start_outdoor_period', 'end_outdoor_period')
     and p.parameter_name ~* 'minute|duration|length'),
  0::bigint,
  's47_no_one_can_type_the_number_of_minutes'
);

reset role;

select throws_like(
  $$update public.outdoor_period set started_at = now() - interval '6 hours' where room_id = '33400000-0000-4000-8000-000000000001'$$,
  '%already closed%',
  's47_a_finished_period_is_never_edited'
);

select throws_like(
  $$insert into public.outdoor_period (centre_id, room_id, outdoor_date, started_at, recorded_by)
    values ('31400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000001', current_date, now() + interval '1 hour', '41400000-0000-4000-8000-000000000001')$$,
  '%not ahead of it%',
  's47_outdoor_time_is_never_recorded_ahead_of_the_day'
);

select throws_like(
  $$delete from public.outdoor_period where true$$,
  '%append-only%',
  's47_outdoor_periods_are_never_deleted'
);

-- ── a measured morning and afternoon, so the arithmetic is checkable ────────
-- Yesterday: a 90-minute morning block from 09:00 and a 60-minute afternoon
-- block from 14:00. Wren (in at 08:00) gets both; Otto (in at 13:00) gets only
-- the afternoon. Written straight in, with the rules off, because these are
-- past measurements and the RPCs deliberately only record the present.
alter table public.outdoor_period disable trigger outdoor_period_rules;
alter table public.outdoor_period disable trigger outdoor_period_no_delete;
alter table public.outdoor_period disable trigger outdoor_period_audit;
delete from public.outdoor_period where true;
insert into public.outdoor_period (centre_id, room_id, outdoor_date, started_at, ended_at, weather, recorded_by, ended_by) values
  ('31400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000001', current_date - 1, ((current_date - 1)::timestamp + time '09:00') at time zone 'America/Toronto', ((current_date - 1)::timestamp + time '10:30') at time zone 'America/Toronto', 'fine', '41400000-0000-4000-8000-000000000001', '41400000-0000-4000-8000-000000000001'),
  ('31400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000001', current_date - 1, ((current_date - 1)::timestamp + time '14:00') at time zone 'America/Toronto', ((current_date - 1)::timestamp + time '15:00') at time zone 'America/Toronto', 'cloudy', '41400000-0000-4000-8000-000000000001', '41400000-0000-4000-8000-000000000001');
alter table public.outdoor_period enable trigger outdoor_period_rules;
alter table public.outdoor_period enable trigger outdoor_period_no_delete;
alter table public.outdoor_period enable trigger outdoor_period_audit;

select is(
  (select minutes from public.outdoor_day where room_id = '33400000-0000-4000-8000-000000000001' and outdoor_date = current_date - 1),
  150,
  's47_the_rooms_minutes_are_the_sum_of_the_measured_periods'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;

select results_eq(
  $$select full_name, minutes_outside, required_minutes, short_by
    from public.outdoor_by_child('31400000-0000-4000-8000-000000000001', current_date - 1)
    where full_name in ('Wren Field', 'Otto Field') order by full_name$$,
  $$values ('Otto Field', 60, 30, 0), ('Wren Field', 150, 120, 0)$$,
  's47_a_child_is_credited_only_with_the_time_they_were_actually_there'
);

-- the infant is below the age floor, so nothing is owed and nothing is short
select results_eq(
  $$select required_minutes, short_by from public.outdoor_by_child('31400000-0000-4000-8000-000000000001', current_date - 1)
    where full_name = 'Baby Field'$$,
  $$values (0, 0)$$,
  's47_an_infant_below_the_age_floor_is_owed_nothing'
);

-- A child still in the building is owed the day they will actually have had,
-- not the hours elapsed so far — otherwise the requirement creeps up through
-- the afternoon and a full-day child reads as "met" at three o'clock.
reset role;
insert into public.attendance_event (centre_id, child_id, room_id, event_type, actual_time, attendance_date, recorded_by)
values ('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000001', 'arrive', clock_timestamp() - interval '30 minutes', current_date, '41400000-0000-4000-8000-000000000001');
set local role authenticated;

select cmp_ok(
  (select required_minutes from public.outdoor_by_child('31400000-0000-4000-8000-000000000001', current_date)
   where full_name = 'Wren Field'),
  '=', 120,
  's47_a_child_still_here_is_owed_the_day_they_will_have_had'
);

-- ── a short day needs its reason, and the reason lands in the DWR ───────────
select throws_like(
  $$select public.record_outdoor_shortfall('31400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000002', current_date, '   ', '41400000-0000-4000-8000-000000000001', '4242')$$,
  '%written down%',
  's47_a_short_day_is_never_recorded_without_a_reason'
);

select throws_like(
  $$select public.record_outdoor_shortfall('31400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000002', (current_date + 1), 'Rain', '41400000-0000-4000-8000-000000000001', '4242')$$,
  '%has not happened yet%',
  's47_a_day_that_has_not_happened_cannot_have_fallen_short'
);

select lives_ok(
  $$select public.record_outdoor_shortfall('31400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000002', current_date, 'Environment Canada extreme cold warning, wind chill -31; the group stayed in.', '41400000-0000-4000-8000-000000000001', '4242')$$,
  's47_the_reason_a_day_was_short_is_recorded'
);

select is(
  (select count(*) from public.daily_written_record dwr
   where dwr.centre_id = '31400000-0000-4000-8000-000000000001'
     and dwr.record_date = current_date
     and dwr.refs::text like '%outdoor_shortfall%'),
  1::bigint,
  's37_outdoor_shortfall_cross_referenced_into_the_daily_record'
);

select throws_like(
  $$select public.record_outdoor_shortfall('31400000-0000-4000-8000-000000000001', '33400000-0000-4000-8000-000000000002', current_date, 'A different story', '41400000-0000-4000-8000-000000000001', '4242')$$,
  '%duplicate key%',
  's47_the_reason_is_recorded_once_and_not_revised'
);

reset role;
select throws_like(
  $$update public.outdoor_shortfall set reason = 'It was quite nice actually' where true$$,
  '%append-only%',
  's47_the_recorded_reason_is_never_rewritten'
);

-- ── keeping a child in needs a written instruction ──────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000f1","role":"authenticated"}', true);
set local role authenticated;

select throws_like(
  $$select public.record_outdoor_exemption('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000001', 'physician', 'Keep indoors', null, null, null, null, '41400000-0000-4000-8000-000000000001', '4242')$$,
  '%names the physician%',
  's47_a_physicians_instruction_names_the_physician'
);

select throws_like(
  $$select public.record_outdoor_exemption('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000001', 'parent', 'Keep indoors this week', null, null, null, null, '41400000-0000-4000-8000-000000000001', '4242')$$,
  '%names the parent%',
  's47_a_parents_instruction_names_the_parent'
);

select throws_like(
  $$select public.record_outdoor_exemption('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000001', 'parent', 'Keep indoors this week', null, '41400000-0000-4000-8000-000000000003', null, null, '41400000-0000-4000-8000-000000000001', '4242')$$,
  '%consenting household member%',
  's47_staff_cannot_keep_a_child_in_on_an_aunts_say_so'
);

select throws_like(
  $$select public.record_outdoor_exemption('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000001', 'parent', '   ', null, '41400000-0000-4000-8000-000000000002', null, null, '41400000-0000-4000-8000-000000000001', '4242')$$,
  '%the whole of the exemption%',
  's47_the_written_instruction_is_never_blank'
);

select lives_ok(
  $$select public.record_outdoor_exemption('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000001', 'physician', 'Indoors until the ear infection clears; may go out from Monday.', 'Dr. R. Mensah, MD', null, (current_date - 1), (current_date + 5), '41400000-0000-4000-8000-000000000001', '4242')$$,
  's47_a_physicians_written_instruction_is_recorded'
);

select results_eq(
  $$select exempt, exemption_note from public.outdoor_by_child('31400000-0000-4000-8000-000000000001', current_date - 1)
    where full_name = 'Wren Field'$$,
  $$values (true, 'Indoors until the ear infection clears; may go out from Monday.')$$,
  's47_the_childs_day_shows_the_instruction_that_keeps_them_in'
);

select lives_ok(
  $$select public.record_outdoor_exemption('31400000-0000-4000-8000-000000000001', '61400000-0000-4000-8000-000000000001', 'parent', 'Still coughing — please keep indoors tomorrow too.', null, '41400000-0000-4000-8000-000000000002', null, null, '41400000-0000-4000-8000-000000000001', '4242')$$,
  's47_a_newer_instruction_supersedes_the_last'
);

select is(
  (select count(*) from public.outdoor_exemption
   where child_id = '61400000-0000-4000-8000-000000000001' and ended_at is null),
  1::bigint,
  's47_one_live_instruction_per_child'
);

-- ── the family sees the day outside ─────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000f2","role":"authenticated"}', true);

select is(
  (select count(*) from public.outdoor_period),
  2::bigint,
  's47_families_see_the_time_their_children_spent_outside'
);

select is(
  (select count(*) from public.outdoor_exemption where ended_at is null),
  1::bigint,
  's47_a_family_sees_the_instruction_on_their_own_child'
);

select * from finish();
rollback;
