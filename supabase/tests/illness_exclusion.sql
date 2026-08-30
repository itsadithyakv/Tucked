-- pgTAP: illness, exclusion and return (s. 36), and the public-health duties.
-- The load-bearing rules: a child sent home is separated and the separation is
-- recorded; the return criteria come from the centre's own illness policy
-- rather than being typed freehand; AN EXCLUDED CHILD CANNOT BE SIGNED IN, at
-- SQL level; clearing them is a signed judgment, and coming back early needs a
-- written reason; every attempt to reach a family is kept; and an order from
-- the public health unit reaches the program advisor inside two business days.

begin;

create extension if not exists pgtap with schema extensions;

select plan(38);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000c1', 'authenticated', 'authenticated', 'sup@ill.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000c2', 'authenticated', 'authenticated', 'edu@ill.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000c3', 'authenticated', 'authenticated', 'parent@ill.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('21500000-0000-4000-8000-000000000001', 'Illness Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('31500000-0000-4000-8000-000000000001', '21500000-0000-4000-8000-000000000001', 'Illness Centre', 'IL-1', '1 Health St, Toronto', '07:30', '18:00');

insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('32500000-0000-4000-8000-000000000001', '31500000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('33500000-0000-4000-8000-000000000001', '31500000-0000-4000-8000-000000000001', '32500000-0000-4000-8000-000000000001', 'Willow room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('41500000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000c1', 'Sup Health', 'sup@ill.local'),
  ('41500000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000c2', 'Edu Health', 'edu@ill.local'),
  ('41500000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-0000000000c3', 'Parent Health', 'parent@ill.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('41500000-0000-4000-8000-000000000001', '31500000-0000-4000-8000-000000000001', 'supervisor', true),
  ('41500000-0000-4000-8000-000000000002', '31500000-0000-4000-8000-000000000001', 'rece', true),
  ('41500000-0000-4000-8000-000000000003', '31500000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('41500000-0000-4000-8000-000000000001', '31500000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('41500000-0000-4000-8000-000000000002', '31500000-0000-4000-8000-000000000001', extensions.crypt('7171', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('51500000-0000-4000-8000-000000000001', '31500000-0000-4000-8000-000000000001', 'Health Household');
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('61500000-0000-4000-8000-000000000001', '31500000-0000-4000-8000-000000000001', 'Pip Health', (current_date - interval '4 years')::date, '2026-01-05', '33500000-0000-4000-8000-000000000001'),
  ('61500000-0000-4000-8000-000000000002', '31500000-0000-4000-8000-000000000001', 'Sol Health', (current_date - interval '3 years')::date, '2026-01-05', '33500000-0000-4000-8000-000000000001');
insert into public.child_household (child_id, household_id, centre_id) values
  ('61500000-0000-4000-8000-000000000001', '51500000-0000-4000-8000-000000000001', '31500000-0000-4000-8000-000000000001'),
  ('61500000-0000-4000-8000-000000000002', '51500000-0000-4000-8000-000000000001', '31500000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('51500000-0000-4000-8000-000000000001', '41500000-0000-4000-8000-000000000003', '31500000-0000-4000-8000-000000000001', 'parent', true, true);

-- ── the policy is data, and every centre starts with one ────────────────────
select cmp_ok(
  (select count(*) from public.illness_policy where centre_id = '31500000-0000-4000-8000-000000000001'),
  '>=', 9::bigint,
  's36_every_centre_starts_with_an_illness_policy'
);

select is(
  (select return_criteria from public.illness_policy
   where centre_id = '31500000-0000-4000-8000-000000000001' and symptom = 'vomiting'),
  'Twenty-four hours since the last episode, and eating and drinking normally.',
  's36_the_policy_says_when_a_child_may_come_back'
);

-- ── as the educator: the day it happens ─────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000c2","role":"authenticated"}', true);
set local role authenticated;

-- the child is here
select lives_ok(
  $$select public.record_attendance('31500000-0000-4000-8000-000000000001', '61500000-0000-4000-8000-000000000001', 'arrive', '33500000-0000-4000-8000-000000000001', now() - interval '3 hours', '41500000-0000-4000-8000-000000000002', '7171')$$,
  's36_child_signed_in_before_becoming_unwell'
);

select throws_like(
  $$select public.record_illness('31500000-0000-4000-8000-000000000001', '61500000-0000-4000-8000-000000000001', 'vomiting', 'Twice since lunch', '  ', '41500000-0000-4000-8000-000000000002', '7171')$$,
  '%separates them from the others%',
  's36_where_the_child_waits_is_part_of_the_record'
);

select throws_like(
  $$select public.record_illness('31500000-0000-4000-8000-000000000001', '61500000-0000-4000-8000-000000000001', 'the_dreaded_lurgy', 'Poorly', 'Quiet corner', '41500000-0000-4000-8000-000000000002', '7171')$$,
  '%not in this centre''s illness policy%',
  's36_the_symptom_comes_from_the_policy_not_from_imagination'
);

select lives_ok(
  $$select public.record_illness('31500000-0000-4000-8000-000000000001', '61500000-0000-4000-8000-000000000001', 'vomiting', 'Twice since lunch, no fever', 'The quiet corner of the office, in sight of the supervisor', '41500000-0000-4000-8000-000000000002', '7171')$$,
  's36_the_child_is_separated_and_the_exclusion_recorded'
);

select results_eq(
  $$select return_criteria, separation_place is not null, separated_at is not null
    from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'$$,
  $$values ('Twenty-four hours since the last episode, and eating and drinking normally.', true, true)$$,
  's36_the_return_criteria_are_copied_from_the_policy'
);

select is(
  (select count(*) from public.daily_written_record
   where centre_id = '31500000-0000-4000-8000-000000000001'
     and refs::text like '%illness_exclusion%'),
  1::bigint,
  's37_a_child_sent_home_unwell_is_in_the_daily_record'
);

select throws_like(
  $$select public.record_illness('31500000-0000-4000-8000-000000000001', '61500000-0000-4000-8000-000000000001', 'fever', 'Also warm', 'Office', '41500000-0000-4000-8000-000000000002', '7171')$$,
  '%already excluded%',
  's36_a_child_is_excluded_once_at_a_time'
);

-- ── reaching the family: the attempts count, not just the success ───────────
select throws_like(
  $$select public.record_illness_contact((select id from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'), 'phone', null, '  ', 'no_answer', null, '41500000-0000-4000-8000-000000000002', '7171')$$,
  '%who was contacted%',
  's36_an_attempt_names_who_was_tried'
);

select lives_ok(
  $$select public.record_illness_contact((select id from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'), 'phone', '41500000-0000-4000-8000-000000000003', null, 'no_answer', 'Rang twice, no answer', '41500000-0000-4000-8000-000000000002', '7171')$$,
  's36_a_failed_attempt_is_still_recorded'
);

select is(
  (select parent_reached_at from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'),
  null,
  's36_an_unanswered_call_is_not_a_parent_reached'
);

-- urgent, and nobody could be reached
select throws_like(
  $$select public.record_illness_practitioner((select id from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'), '   ', 'Advice', '41500000-0000-4000-8000-000000000002', '7171')$$,
  '%name the physician or registered nurse%',
  's36_the_practitioner_who_saw_the_child_is_named'
);

select lives_ok(
  $$select public.record_illness_practitioner((select id from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'), 'RN J. Whitefeather, Telehealth Ontario', 'Fluids and rest; seek care if unable to keep fluids down.', '41500000-0000-4000-8000-000000000002', '7171')$$,
  's36_an_urgent_case_records_who_saw_the_child'
);

select lives_ok(
  $$select public.record_illness_contact((select id from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'), 'phone', '41500000-0000-4000-8000-000000000003', null, 'reached', 'On the way', '41500000-0000-4000-8000-000000000002', '7171')$$,
  's36_the_family_is_reached_in_the_end'
);

select isnt(
  (select parent_reached_at from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'),
  null,
  's36_reaching_the_family_is_on_the_record'
);

select is(
  (select count(*) from public.health_exclusion_contact),
  2::bigint,
  's36_every_attempt_is_kept_not_just_the_last'
);

-- the child goes home: a depart is never blocked
select lives_ok(
  $$select public.record_attendance('31500000-0000-4000-8000-000000000001', '61500000-0000-4000-8000-000000000001', 'depart', '33500000-0000-4000-8000-000000000001', now(), '41500000-0000-4000-8000-000000000002', '7171')$$,
  's36_going_home_is_never_blocked'
);

-- ── the block that makes exclusion mean something ───────────────────────────
select throws_like(
  $$select public.record_attendance('31500000-0000-4000-8000-000000000001', '61500000-0000-4000-8000-000000000001', 'arrive', '33500000-0000-4000-8000-000000000001', now(), '41500000-0000-4000-8000-000000000002', '7171')$$,
  '%sign-in blocked%',
  's36_an_excluded_child_cannot_be_signed_in'
);

-- and the refusal tells the educator what has to be true first
select throws_like(
  $$select public.record_attendance('31500000-0000-4000-8000-000000000001', '61500000-0000-4000-8000-000000000001', 'arrive', '33500000-0000-4000-8000-000000000001', now(), '41500000-0000-4000-8000-000000000002', '7171')$$,
  '%Twenty-four hours since the last episode%',
  's36_the_refusal_says_what_has_to_be_true_first'
);

-- a sibling is untouched by it
select lives_ok(
  $$select public.record_attendance('31500000-0000-4000-8000-000000000001', '61500000-0000-4000-8000-000000000002', 'arrive', '33500000-0000-4000-8000-000000000001', now(), '41500000-0000-4000-8000-000000000002', '7171')$$,
  's36_only_the_excluded_child_is_blocked'
);

-- ── clearing the child is a signed judgment ─────────────────────────────────
select throws_like(
  $$select public.clear_for_return((select id from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'), '   ', null, '41500000-0000-4000-8000-000000000002', '7171')$$,
  '%that note is the clearance%',
  's36_clearing_a_child_says_how_the_criteria_were_met'
);

select throws_like(
  $$select public.clear_for_return((select id from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'), 'Looks fine to me', null, '41500000-0000-4000-8000-000000000002', '7171')$$,
  '%record why they may come back sooner%',
  's36_coming_back_early_needs_a_written_reason'
);

select lives_ok(
  $$select public.clear_for_return((select id from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'), 'No further episodes; eating and drinking normally.', 'Physician''s note: gastroenteritis resolved, may return.', '41500000-0000-4000-8000-000000000002', '7171')$$,
  's36_an_early_return_with_a_physicians_note_is_allowed'
);

select results_eq(
  $$select cleared_by, early_return_reason is not null
    from public.health_exclusion where child_id = '61500000-0000-4000-8000-000000000001'$$,
  $$values ('41500000-0000-4000-8000-000000000002'::uuid, true)$$,
  's36_the_clearance_names_who_made_the_call'
);

select lives_ok(
  $$select public.record_attendance('31500000-0000-4000-8000-000000000001', '61500000-0000-4000-8000-000000000001', 'arrive', '33500000-0000-4000-8000-000000000001', now(), '41500000-0000-4000-8000-000000000002', '7171')$$,
  's36_a_cleared_child_walks_back_in'
);

-- ── the policy is the licensee's ────────────────────────────────────────────
select throws_like(
  $$select public.set_illness_policy('31500000-0000-4000-8000-000000000001', 'fever', null, 'Whenever', 0, true, '41500000-0000-4000-8000-000000000002', '7171')$$,
  '%developed with the public health unit%',
  's36_only_leadership_changes_the_illness_policy'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000c1","role":"authenticated"}', true);

select lives_ok(
  $$select public.set_illness_policy('31500000-0000-4000-8000-000000000001', 'fever', 'Excluded at 38 °C or above.', 'Forty-eight hours with no fever, per Toronto Public Health advice.', 48, true, '41500000-0000-4000-8000-000000000001', '4242')$$,
  's36_leadership_tunes_the_policy_with_public_health'
);

-- ── the public-health duties and their clock ────────────────────────────────
select lives_ok(
  $$select public.record_public_health_notification('31500000-0000-4000-8000-000000000001', 'outbreak', 'Gastroenteritis', 'Three children in the Willow room with vomiting in 48 hours.', 'Toronto Public Health', now(), 'TPH-2026-4417', null, null, '41500000-0000-4000-8000-000000000001', '4242')$$,
  's36_an_outbreak_notification_to_public_health_is_recorded'
);

select lives_ok(
  $$select public.record_public_health_notification('31500000-0000-4000-8000-000000000001', 'order_received', 'Gastroenteritis', 'Direction to exclude symptomatic children and enhance cleaning.', 'Toronto Public Health', null, 'TPH-2026-4417', now(), 'Exclude for 48 hours after the last symptom; twice-daily disinfection of high-touch surfaces.', '41500000-0000-4000-8000-000000000001', '4242')$$,
  's36_an_order_from_the_unit_is_kept_on_file'
);

-- two business days, computed with the same arithmetic the CCLS clock uses
select is(
  (select advisor_due_on from public.public_health_notification where kind = 'order_received'),
  app.add_business_days('CA-ON', current_date, 2),
  's36_an_order_reaches_the_program_advisor_within_two_business_days'
);

select throws_like(
  $$select public.close_public_health_notification((select id from public.public_health_notification where kind = 'order_received'), '41500000-0000-4000-8000-000000000001', '4242')$$,
  '%before closing this%',
  's36_an_order_is_never_closed_before_the_advisor_has_it'
);

select lives_ok(
  $$select public.forward_to_program_advisor((select id from public.public_health_notification where kind = 'order_received'), 'Emailed to the Toronto licensing office, ack 2026-08-30', '41500000-0000-4000-8000-000000000001', '4242')$$,
  's36_the_order_goes_to_the_program_advisor'
);

select lives_ok(
  $$select public.close_public_health_notification((select id from public.public_health_notification where kind = 'order_received'), '41500000-0000-4000-8000-000000000001', '4242')$$,
  's36_and_then_it_can_be_closed'
);

-- ── as the family ───────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000c3","role":"authenticated"}', true);

select is(
  (select count(*) from public.health_exclusion),
  1::bigint,
  's36_a_family_sees_their_own_childs_exclusion'
);

select is(
  (select count(*) from public.health_exclusion_contact),
  0::bigint,
  's36_a_family_never_sees_the_centres_contact_notes'
);

-- the alert reached the parent, as a Now item they have to acknowledge
select results_eq(
  $$select channel::text, requires_acknowledgement, body like '%quiet corner%'
    from public.notification where event_type = 'illness_sent_home'$$,
  $$values ('now', true, true)$$,
  's36_the_family_is_told_now_and_told_where_the_child_is'
);

-- ── nothing vanishes ────────────────────────────────────────────────────────
reset role;

select throws_like(
  $$delete from public.health_exclusion where true$$,
  '%append-only%',
  's36_exclusions_are_never_deleted'
);

select * from finish();
rollback;
