-- pgTAP: reviewing individualised plans (0043). The regulation sets no review
-- frequency; a plan must stay up to date, and the centre chooses how often it
-- checks. The load-bearing rules: the clock is the centre's interval counted
-- in the centre's calendar; a review that changes nothing moves the clock and
-- touches nothing else; "changes needed" never moves it; only an adult who can
-- consent reviews for the family; reviews are append-only and anonymised at
-- s. 72(5) like the plan itself.

begin;

create extension if not exists pgtap with schema extensions;

select plan(50);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '1d430000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sup@review.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1d430000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'hana@review.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1d430000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'aunt@review.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1d430000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'olu@review.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('2d430000-0000-4000-8000-000000000001', 'Review Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('3d430000-0000-4000-8000-000000000001', '2d430000-0000-4000-8000-000000000001', 'Review Centre', 'REV-1', '1 Review St, Toronto', '07:30', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('3d430000-0000-4000-8000-000000000002', '3d430000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('3d430000-0000-4000-8000-000000000003', '3d430000-0000-4000-8000-000000000001', '3d430000-0000-4000-8000-000000000002', 'Review Room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('5d430000-0000-4000-8000-000000000001', '1d430000-0000-4000-8000-000000000001', 'Sade Review', 'sup@review.local'),
  ('5d430000-0000-4000-8000-000000000002', '1d430000-0000-4000-8000-000000000002', 'Hana Aziz', 'hana@review.local'),
  ('5d430000-0000-4000-8000-000000000003', '1d430000-0000-4000-8000-000000000003', 'Aunt Aziz', 'aunt@review.local'),
  ('5d430000-0000-4000-8000-000000000004', '1d430000-0000-4000-8000-000000000004', 'Olu Berg', 'olu@review.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('5d430000-0000-4000-8000-000000000001', '3d430000-0000-4000-8000-000000000001', 'supervisor', true),
  ('5d430000-0000-4000-8000-000000000002', '3d430000-0000-4000-8000-000000000001', 'family_adult', false),
  ('5d430000-0000-4000-8000-000000000003', '3d430000-0000-4000-8000-000000000001', 'family_adult', false),
  ('5d430000-0000-4000-8000-000000000004', '3d430000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('5d430000-0000-4000-8000-000000000001', '3d430000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('6d430000-0000-4000-8000-000000000001', '3d430000-0000-4000-8000-000000000001', 'Aziz Household'),
  ('6d430000-0000-4000-8000-000000000002', '3d430000-0000-4000-8000-000000000001', 'Berg Household');
-- Mila (Aziz) and Otto (Berg). Otto's dates allow a matured retention clock at the end.
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('7d430000-0000-4000-8000-000000000001', '3d430000-0000-4000-8000-000000000001', 'Mila Aziz', '2023-03-15', '2026-01-05', '3d430000-0000-4000-8000-000000000003'),
  ('7d430000-0000-4000-8000-000000000002', '3d430000-0000-4000-8000-000000000001', 'Otto Berg', '2020-02-01', '2021-01-05', '3d430000-0000-4000-8000-000000000003');
insert into public.child_household (child_id, household_id, centre_id) values
  ('7d430000-0000-4000-8000-000000000001', '6d430000-0000-4000-8000-000000000001', '3d430000-0000-4000-8000-000000000001'),
  ('7d430000-0000-4000-8000-000000000002', '6d430000-0000-4000-8000-000000000002', '3d430000-0000-4000-8000-000000000001');
-- Hana consents; the aunt can view but not consent; Olu consents for Otto only
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('6d430000-0000-4000-8000-000000000001', '5d430000-0000-4000-8000-000000000002', '3d430000-0000-4000-8000-000000000001', 'parent', true, true),
  ('6d430000-0000-4000-8000-000000000001', '5d430000-0000-4000-8000-000000000003', '3d430000-0000-4000-8000-000000000001', 'other', true, false),
  ('6d430000-0000-4000-8000-000000000002', '5d430000-0000-4000-8000-000000000004', '3d430000-0000-4000-8000-000000000001', 'parent', true, true);

-- ── the centre's own interval ───────────────────────────────────────────────
select throws_ok(
  $$update public.centre set plan_review_months = 0 where id = '3d430000-0000-4000-8000-000000000001'$$,
  '23514', null,
  'plan_review_interval_must_be_between_one_and_twenty_four_months'
);

update public.centre set plan_review_months = 6 where id = '3d430000-0000-4000-8000-000000000001';

-- ── plans: A (Mila, anaphylaxis) agreed in app; M (Mila, medical) left a
-- draft; S (Otto, special needs) agreed on signed paper ten days ago ──────────
select set_config('request.jwt.claims', '{"sub":"1d430000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$select public.upsert_individualised_plan('3d430000-0000-4000-8000-000000000001','7d430000-0000-4000-8000-000000000001','anaphylaxis','Anaphylaxis — peanut', array['peanuts'], 'Hives, wheeze', 'EpiPen, 911, family', null, 'EpiPen in the go-bag', null, null, 'Hana Aziz (parent)', '5d430000-0000-4000-8000-000000000001', '4242')$$,
  'fixture_anaphylaxis_plan_recorded'
);
select lives_ok(
  $$select public.upsert_individualised_plan('3d430000-0000-4000-8000-000000000001','7d430000-0000-4000-8000-000000000001','medical_needs','Asthma', null, null, 'Two puffs via spacer; 911 if no relief', null, null, null, null, 'Hana Aziz (parent)', '5d430000-0000-4000-8000-000000000001', '4242')$$,
  'fixture_medical_plan_left_as_a_draft'
);
select lives_ok(
  $$select public.upsert_individualised_plan('3d430000-0000-4000-8000-000000000001','7d430000-0000-4000-8000-000000000002','special_needs','Speech delay', null, null, null, null, null, 'Picture schedule; extra transition warnings', null, 'Olu Berg (parent), speech-language pathologist', '5d430000-0000-4000-8000-000000000001', '4242')$$,
  'fixture_special_needs_plan_recorded'
);

select throws_like(
  $$select public.record_plan_review((select id from public.individualised_plan where plan_type = 'medical_needs'), '5d430000-0000-4000-8000-000000000002', null, 'in_person', 'still_accurate', null, '5d430000-0000-4000-8000-000000000001', '4242')$$,
  '%still awaiting agreement%',
  'review_a_draft_is_refused'
);

select set_config('request.jwt.claims', '{"sub":"1d430000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select lives_ok(
  $$select public.agree_individualised_plan((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1))$$,
  'fixture_hana_agrees_in_app'
);
select is(
  (select review_due_on from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1),
  ((now() at time zone 'America/Toronto')::date + interval '6 months')::date,
  'clock_is_the_centres_interval_from_the_centre_local_day_of_agreement'
);

select set_config('request.jwt.claims', '{"sub":"1d430000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select lives_ok(
  $$select public.record_plan_agreement((select id from public.individualised_plan where plan_type = 'special_needs'), '5d430000-0000-4000-8000-000000000004', now() - interval '10 days', '5d430000-0000-4000-8000-000000000001', '4242')$$,
  'fixture_signed_paper_dated_ten_days_ago'
);
select is(
  (select review_due_on from public.individualised_plan where plan_type = 'special_needs'),
  (((now() - interval '10 days') at time zone 'America/Toronto')::date + interval '6 months')::date,
  'signed_paper_clock_starts_on_the_day_it_was_signed_not_the_day_it_was_typed'
);
select throws_like(
  $$select public.record_plan_agreement((select id from public.individualised_plan where plan_type = 'medical_needs'), '5d430000-0000-4000-8000-000000000002', now() + interval '2 days', '5d430000-0000-4000-8000-000000000001', '4242')$$,
  '%once it has been signed%',
  'signed_paper_dated_in_the_future_is_refused'
);

-- ── the due list ────────────────────────────────────────────────────────────
reset role;
update public.individualised_plan
  set review_due_on = (now() at time zone 'America/Toronto')::date - 3
  where plan_type = 'anaphylaxis' and version = 1;
update public.individualised_plan
  set review_due_on = (now() at time zone 'America/Toronto')::date + 20
  where plan_type = 'special_needs';
set local role authenticated;

select is(
  (select state from public.plan_reviews_due('3d430000-0000-4000-8000-000000000001')
   where plan_id = (select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1)),
  'overdue',
  'due_list_marks_a_passed_date_overdue'
);
select is(
  (select state from public.plan_reviews_due('3d430000-0000-4000-8000-000000000001')
   where plan_id = (select id from public.individualised_plan where plan_type = 'special_needs')),
  'due_soon',
  'due_list_warns_thirty_days_before'
);
select is(
  (select count(*) from public.plan_reviews_due('3d430000-0000-4000-8000-000000000001')
   where plan_id = (select id from public.individualised_plan where plan_type = 'medical_needs')),
  0::bigint,
  'due_list_leaves_drafts_to_the_agreement_flag'
);

-- ── what staff cannot record ────────────────────────────────────────────────
select throws_like(
  $$select public.record_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), '5d430000-0000-4000-8000-000000000003', null, 'in_person', 'still_accurate', null, '5d430000-0000-4000-8000-000000000001', '4242')$$,
  '%adult who can consent%',
  'review_with_an_adult_who_cannot_consent_is_refused'
);
select throws_like(
  $$select public.record_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), '5d430000-0000-4000-8000-000000000002', (now() at time zone 'America/Toronto')::date + 1, 'in_person', 'still_accurate', null, '5d430000-0000-4000-8000-000000000001', '4242')$$,
  '%in the future%',
  'review_dated_tomorrow_is_refused'
);
select throws_like(
  $$select public.record_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), '5d430000-0000-4000-8000-000000000002', (now() at time zone 'America/Toronto')::date - 30, 'in_person', 'still_accurate', null, '5d430000-0000-4000-8000-000000000001', '4242')$$,
  '%before the agreement%',
  'review_dated_before_the_agreement_is_refused'
);
select throws_like(
  $$select public.record_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), '5d430000-0000-4000-8000-000000000002', null, 'in_app', 'still_accurate', null, '5d430000-0000-4000-8000-000000000001', '4242')$$,
  '%the family answers for themselves%',
  'staff_cannot_record_an_in_app_answer'
);
select throws_like(
  $$select public.record_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), '5d430000-0000-4000-8000-000000000002', null, 'phone', 'changes_needed', '  ', '5d430000-0000-4000-8000-000000000001', '4242')$$,
  '%say what has changed%',
  'changes_needed_must_say_what_changed'
);
select throws_ok(
  $$select public.record_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), '5d430000-0000-4000-8000-000000000002', null, 'phone', 'still_accurate', null, '5d430000-0000-4000-8000-000000000001', '0000')$$,
  '28000', null,
  'review_needs_a_valid_staff_pin'
);

-- ── a review that changes nothing ───────────────────────────────────────────
select lives_ok(
  $$select public.record_plan_review((select id from public.individualised_plan where plan_type = 'special_needs'), '5d430000-0000-4000-8000-000000000004', (now() at time zone 'America/Toronto')::date - 5, 'in_person', 'still_accurate', 'Went through it with Olu at pickup; supports unchanged', '5d430000-0000-4000-8000-000000000001', '4242')$$,
  'staff_record_a_review_held_in_person'
);
select is(
  (select review_due_on from public.individualised_plan where plan_type = 'special_needs'),
  (((now() at time zone 'America/Toronto')::date - 5) + interval '6 months')::date,
  'still_accurate_moves_the_clock_from_the_day_of_the_review'
);
select ok(
  (select count(*) = 1 and bool_and(status = 'active' and version = 1)
   from public.individualised_plan where plan_type = 'special_needs'),
  'a_review_that_changes_nothing_makes_no_new_version'
);
select is(
  (select count(*) from public.notification
   where event_type = 'plan_agreement' and recipient_person_id = '5d430000-0000-4000-8000-000000000004'),
  1::bigint,
  'a_review_asks_nobody_to_agree_again'
);
select lives_ok(
  $$select public.record_plan_review((select id from public.individualised_plan where plan_type = 'special_needs'), '5d430000-0000-4000-8000-000000000004', (now() at time zone 'America/Toronto')::date - 8, 'phone', 'still_accurate', null, '5d430000-0000-4000-8000-000000000001', '4242')$$,
  'a_backdated_phone_review_is_recorded'
);
select is(
  (select review_due_on from public.individualised_plan where plan_type = 'special_needs'),
  (((now() at time zone 'America/Toronto')::date - 5) + interval '6 months')::date,
  'a_backdated_review_never_winds_the_clock_back'
);
select is(
  (select count(*) from public.plan_reviews_due('3d430000-0000-4000-8000-000000000001')
   where plan_id = (select id from public.individualised_plan where plan_type = 'special_needs')),
  0::bigint,
  'a_reviewed_plan_leaves_the_due_list'
);

-- ── changes needed ──────────────────────────────────────────────────────────
select lives_ok(
  $$select public.record_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), '5d430000-0000-4000-8000-000000000002', null, 'phone', 'changes_needed', 'New allergist letter mentions sesame', '5d430000-0000-4000-8000-000000000001', '4242')$$,
  'staff_record_that_the_plan_needs_changes'
);
select is(
  (select review_due_on from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1),
  (now() at time zone 'America/Toronto')::date - 3,
  'changes_needed_does_not_move_the_clock'
);
select is(
  (select state from public.plan_reviews_due('3d430000-0000-4000-8000-000000000001')
   where plan_id = (select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1)),
  'changes_needed',
  'due_list_says_changes_are_waiting_on_a_new_version'
);

-- ── asking the family in the app ────────────────────────────────────────────
select is(
  public.request_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), '5d430000-0000-4000-8000-000000000001', '4242'),
  1,
  'request_asks_only_the_adults_who_can_consent'
);
select is(
  public.request_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), '5d430000-0000-4000-8000-000000000001', '4242'),
  0,
  'asking_twice_does_not_nag'
);
select throws_like(
  $$select public.request_plan_review((select id from public.individualised_plan where plan_type = 'medical_needs'), '5d430000-0000-4000-8000-000000000001', '4242')$$,
  '%only a plan in practice%',
  'request_for_a_draft_is_refused'
);

-- the aunt can read Mila's review, and cannot answer one
select set_config('request.jwt.claims', '{"sub":"1d430000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select throws_ok(
  $$select public.answer_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), true)$$,
  '42501', null,
  'an_adult_who_cannot_consent_cannot_answer'
);
select is(
  (select count(*) from public.individualised_plan_review),
  1::bigint,
  'a_household_viewer_reads_their_childs_reviews'
);

-- Olu reads Otto's reviews only, and was never asked about Otto's plan
select set_config('request.jwt.claims', '{"sub":"1d430000-0000-4000-8000-000000000004","role":"authenticated"}', true);
select is(
  (select count(*) from public.individualised_plan_review),
  2::bigint,
  'another_family_reads_only_their_own_childs_reviews'
);
select throws_like(
  $$select public.answer_plan_review((select id from public.individualised_plan where plan_type = 'special_needs'), true)$$,
  '%has not asked you%',
  'a_family_cannot_answer_a_review_nobody_asked_for'
);
select is(
  (select count(*) from public.plan_reviews_due('3d430000-0000-4000-8000-000000000001')),
  0::bigint,
  'a_parent_reads_no_centre_due_list'
);

-- Hana answers
select set_config('request.jwt.claims', '{"sub":"1d430000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select throws_like(
  $$select public.answer_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), false, '')$$,
  '%say what has changed%',
  'the_family_saying_something_changed_must_say_what'
);
select lives_ok(
  $$select public.answer_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), true, 'That letter was about her brother. Nothing has changed for Mila.')$$,
  'hana_confirms_the_plan_is_still_right'
);
select ok(
  (select method = 'in_app' and outcome = 'still_accurate'
          and reviewed_with = '5d430000-0000-4000-8000-000000000002'
          and recorded_by = '5d430000-0000-4000-8000-000000000002'
   from public.individualised_plan_review
   where plan_id = (select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1)
   order by created_at desc limit 1),
  'the_family_answer_is_named_and_marked_in_app'
);
select is(
  (select review_due_on from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1),
  ((now() at time zone 'America/Toronto')::date + interval '6 months')::date,
  'the_family_confirming_moves_the_clock'
);
select is(
  (select count(*) from public.notification
   where event_type = 'plan_review' and recipient_person_id = '5d430000-0000-4000-8000-000000000002'
     and acknowledged_at is null),
  0::bigint,
  'answering_clears_the_request'
);

-- ── back to the supervisor ──────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1d430000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is(
  (select count(*) from public.plan_reviews_due('3d430000-0000-4000-8000-000000000001')
   where plan_id = (select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1)),
  0::bigint,
  'a_later_accurate_review_clears_changes_needed'
);
select lives_ok(
  $$select public.upsert_individualised_plan('3d430000-0000-4000-8000-000000000001','7d430000-0000-4000-8000-000000000001','anaphylaxis','Anaphylaxis — peanut and sesame', array['peanuts','sesame'], 'Hives, wheeze', 'EpiPen, 911, family', null, 'EpiPen in the go-bag', null, null, 'Hana Aziz (parent)', '5d430000-0000-4000-8000-000000000001', '4242')$$,
  'fixture_a_new_version_supersedes_plan_a'
);
select throws_like(
  $$select public.record_plan_review((select id from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1), '5d430000-0000-4000-8000-000000000002', null, 'in_person', 'still_accurate', null, '5d430000-0000-4000-8000-000000000001', '4242')$$,
  '%no longer in practice%',
  'a_superseded_version_cannot_be_reviewed'
);

-- ── as owner: append-only where RLS does not apply ──────────────────────────
reset role;
select throws_like(
  $$update public.individualised_plan_review set note = 'edited' where true$$,
  '%never edited%',
  'never_a_review_edited'
);
select throws_like(
  $$delete from public.individualised_plan_review where true$$,
  '%append-only%',
  'never_a_review_deleted'
);

-- s. 72(5): Otto discharged four years ago, so his clock has matured
update public.child set discharge_date = (current_date - interval '4 years')::date
  where id = '7d430000-0000-4000-8000-000000000002';
select lives_ok(
  $$select app.anonymise_child('7d430000-0000-4000-8000-000000000002')$$,
  'retention_anonymises_a_child_with_plan_reviews'
);
select is(
  (select count(*) from public.individualised_plan_review
   where child_id = '7d430000-0000-4000-8000-000000000002'
     and note is not null and note <> '[anonymised]'),
  0::bigint,
  'retention_leaves_no_review_note_behind'
);
select is(
  (select count(*) from public.individualised_plan_review
   where child_id = '7d430000-0000-4000-8000-000000000002'),
  2::bigint,
  'retention_keeps_that_the_reviews_happened'
);

select * from finish();
rollback;
