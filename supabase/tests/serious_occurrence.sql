-- pgTAP: s. 38 serious occurrences — the 24-hour CCLS clock, evidence of the
-- human filing, the anonymised 10-business-day posting (weekends AND Ontario
-- statutory holidays excluded), the CYFSA duty for abuse/neglect allegations,
-- supervisor-only visibility, and the reminder cron.

begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '1a000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sup@so.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1a000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rece@so.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1a000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'parent@so.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('2a000000-0000-4000-8000-000000000001', 'SO Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('3d000000-0000-4000-8000-000000000001', '2a000000-0000-4000-8000-000000000001', 'SO Centre', 'SO-1', '1 SO St, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('4a000000-0000-4000-8000-000000000001', '1a000000-0000-4000-8000-000000000001', 'Sup SO', 'sup@so.local'),
  ('4a000000-0000-4000-8000-000000000002', '1a000000-0000-4000-8000-000000000002', 'Rece SO', 'rece@so.local'),
  ('4a000000-0000-4000-8000-000000000003', '1a000000-0000-4000-8000-000000000003', 'Parent SO', 'parent@so.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('4a000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', 'supervisor', true),
  ('4a000000-0000-4000-8000-000000000002', '3d000000-0000-4000-8000-000000000001', 'rece', true),
  ('4a000000-0000-4000-8000-000000000003', '3d000000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('4a000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('4a000000-0000-4000-8000-000000000002', '3d000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('5a000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', 'SO Household');
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date) values
  ('6a000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', 'Noah Tremblay', '2023-03-15', '2026-01-05'),
  -- enrolled but never attached to any occurrence — the guard must still
  -- protect this name, and the word "same" must not trip it
  ('6a000000-0000-4000-8000-000000000002', '3d000000-0000-4000-8000-000000000001', 'Sam Deng', '2023-06-20', '2026-01-05');
insert into public.child_household (child_id, household_id, centre_id) values
  ('6a000000-0000-4000-8000-000000000001', '5a000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view) values
  ('5a000000-0000-4000-8000-000000000001', '4a000000-0000-4000-8000-000000000003', '3d000000-0000-4000-8000-000000000001', 'parent', true);

-- ── as the supervisor ───────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1a000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$select public.record_serious_occurrence('3d000000-0000-4000-8000-000000000001', 'missing_unsupervised_child',
    now() - interval '2 hours', now() - interval '1 hour',
    'Child briefly unaccounted for during outdoor transition; found in the cubby room within four minutes.',
    'Headcount repeated, transition procedure reviewed with the team the same day.',
    array['6a000000-0000-4000-8000-000000000001']::uuid[], '4a000000-0000-4000-8000-000000000001', '4242')$$,
  's38_supervisor_records_occurrence'
);

select is(
  (select ccls_deadline_at - aware_at from public.serious_occurrence where category = 'missing_unsupervised_child'),
  interval '24 hours',
  's38_ccls_clock_is_24_hours_from_awareness'
);

select is(
  (select count(*)
   from public.daily_written_record dwr, jsonb_array_elements(dwr.refs) ref
   where dwr.centre_id = '3d000000-0000-4000-8000-000000000001'
     and ref ->> 'type' = 'serious_occurrence'),
  1::bigint,
  's37_occurrence_cross_referenced_into_dwr'
);

select throws_like(
  $$select public.file_serious_occurrence_ccls(
    (select id from public.serious_occurrence where category = 'missing_unsupervised_child'),
    '  ', now(), '4a000000-0000-4000-8000-000000000001', '4242')$$,
  '%cannot be blank%',
  's38_ccls_number_is_the_evidence_of_filing'
);

select throws_like(
  $$select public.close_serious_occurrence(
    (select id from public.serious_occurrence where category = 'missing_unsupervised_child'),
    null, '4a000000-0000-4000-8000-000000000001', '4242')$$,
  '%cannot close before the CCLS filing%',
  's38_no_close_before_filing'
);

select lives_ok(
  $$select public.file_serious_occurrence_ccls(
    (select id from public.serious_occurrence where category = 'missing_unsupervised_child'),
    'SO-2026-004417', now() - interval '30 minutes', '4a000000-0000-4000-8000-000000000001', '4242')$$,
  's38_human_files_and_records_it'
);

select is(
  (select (status = 'filed' and ccls_filed_by = '4a000000-0000-4000-8000-000000000001' and ccls_number = 'SO-2026-004417')
   from public.serious_occurrence where category = 'missing_unsupervised_child'),
  true,
  's38_filing_names_the_human_and_the_ccls_number'
);

select throws_like(
  $$select public.post_serious_occurrence_summary(
    (select id from public.serious_occurrence where category = 'missing_unsupervised_child'),
    'On August 30 Noah was briefly unaccounted for during a transition.', '2026-08-31',
    '4a000000-0000-4000-8000-000000000001', '4242')$$,
  '%must be anonymised%',
  's38_posting_rejected_when_it_names_a_child'
);

-- Sam was never attached to this occurrence — the guard protects every
-- enrolled child's name, not just the ones staff remembered to tick.
select throws_like(
  $$select public.post_serious_occurrence_summary(
    (select id from public.serious_occurrence where category = 'missing_unsupervised_child'),
    'A child was briefly unaccounted for and was found by Sam within minutes.', '2026-08-31',
    '4a000000-0000-4000-8000-000000000001', '4242')$$,
  '%must be anonymised%',
  's38_posting_guard_covers_unattached_children'
);

-- …but only as a whole word: "same" must not trip the child named Sam.
select lives_ok(
  $$select public.post_serious_occurrence_summary(
    (select id from public.serious_occurrence where category = 'missing_unsupervised_child'),
    'On August 30 a child was briefly unaccounted for during an outdoor transition and was found safe within minutes of the same transition. The Ministry was notified through CCLS. Procedures were reviewed with all staff.',
    '2026-08-31', '4a000000-0000-4000-8000-000000000001', '4242')$$,
  's38_anonymised_summary_posted_word_boundaries_hold'
);

-- 10 business days after Mon Aug 31 2026, skipping two weekends AND Labour Day
-- (Mon Sep 7): Sep 1,2,3,4, 8,9,10,11, 14,15 → the paper stays up through Sep 15.
select is(
  (select posting_ends_on from public.serious_occurrence_posting limit 1),
  '2026-09-15'::date,
  's38_ten_business_days_skip_weekends_and_labour_day'
);

select lives_ok(
  $$select public.close_serious_occurrence(
    (select id from public.serious_occurrence where category = 'missing_unsupervised_child'),
    'Ministry review complete, no follow-up required.', '4a000000-0000-4000-8000-000000000001', '4242')$$,
  's38_close_after_filing_and_posting'
);

-- ── an abuse/neglect allegation: different rules ────────────────────────────
select lives_ok(
  $$select public.record_serious_occurrence('3d000000-0000-4000-8000-000000000001', 'abuse_neglect_allegation',
    now() - interval '3 hours', now() - interval '2 hours',
    'Allegation received from a parent concerning conduct in the toddler room.',
    'Staff member placed on non-contact duties pending investigation.',
    array['6a000000-0000-4000-8000-000000000001']::uuid[], '4a000000-0000-4000-8000-000000000001', '4242')$$,
  'cyfsa_allegation_recorded'
);

select throws_ok(
  $$select public.post_serious_occurrence_summary(
    (select id from public.serious_occurrence where category = 'abuse_neglect_allegation'),
    'A serious occurrence was reported to the Ministry.', current_date,
    '4a000000-0000-4000-8000-000000000001', '4242')$$,
  'abuse or neglect allegations are never posted',
  'cyfsa_allegations_never_posted'
);

select lives_ok(
  $$select public.file_serious_occurrence_ccls(
    (select id from public.serious_occurrence where category = 'abuse_neglect_allegation'),
    'SO-2026-004418', now(), '4a000000-0000-4000-8000-000000000001', '4242')$$,
  'cyfsa_allegation_filed_in_ccls'
);

select throws_like(
  $$select public.close_serious_occurrence(
    (select id from public.serious_occurrence where category = 'abuse_neglect_allegation'),
    null, '4a000000-0000-4000-8000-000000000001', '4242')$$,
  '%Children''s Aid Society%',
  'cyfsa_no_close_without_cas_report'
);

select throws_ok(
  $$select public.record_cas_report(
    (select id from public.serious_occurrence where category = 'missing_unsupervised_child'),
    now(), 'called CAS', '4a000000-0000-4000-8000-000000000001', '4242')$$,
  'the CAS duty applies to abuse or neglect allegations',
  'cyfsa_cas_report_only_for_allegations'
);

select lives_ok(
  $$select public.record_cas_report(
    (select id from public.serious_occurrence where category = 'abuse_neglect_allegation'),
    now() - interval '90 minutes', 'Reported to Toronto CAS by the supervisor by phone; reference given.',
    '4a000000-0000-4000-8000-000000000001', '4242')$$,
  'cyfsa_cas_report_recorded'
);

select lives_ok(
  $$select public.close_serious_occurrence(
    (select id from public.serious_occurrence where category = 'abuse_neglect_allegation'),
    'CAS engaged; internal review complete.', '4a000000-0000-4000-8000-000000000001', '4242')$$,
  'cyfsa_allegation_closes_after_cas_and_ccls'
);

select lives_ok(
  $$select public.add_serious_occurrence_update(
    (select id from public.serious_occurrence where category = 'abuse_neglect_allegation'),
    'CAS confirmed file closed with no findings; update filed in CCLS.', 'ccls_update',
    '4a000000-0000-4000-8000-000000000001', '4242')$$,
  's38_updates_append_after_close'
);

-- ── as the RECE: leadership-only, invisible ─────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1a000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select throws_like(
  $$select public.record_serious_occurrence('3d000000-0000-4000-8000-000000000001', 'unplanned_disruption',
    now(), now(), 'x', null, null, '4a000000-0000-4000-8000-000000000002', '4242')$$,
  '%supervisor, a designate, or the licensee%',
  's38_rece_cannot_record_occurrences'
);

select is((select count(*) from public.serious_occurrence), 0::bigint, 's38_rece_sees_no_occurrences');

-- ── as the parent: nothing (the posting is anonymised paper, not the app) ───
select set_config('request.jwt.claims', '{"sub":"1a000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select is((select count(*) from public.serious_occurrence), 0::bigint, 's38_parents_see_no_occurrences');

-- ── as owner: the reminder clock and append-only ────────────────────────────
reset role;

-- one occurrence inside the 6-hour warning window, one already overdue
insert into public.serious_occurrence (id, centre_id, category, occurred_at, aware_at, description, reported_by) values
  ('7a000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', 'unplanned_disruption',
   now() - interval '23 hours', now() - interval '23 hours', 'Burst pipe closed the toddler room.', '4a000000-0000-4000-8000-000000000001'),
  ('7a000000-0000-4000-8000-000000000002', '3d000000-0000-4000-8000-000000000001', 'life_threatening_injury_illness',
   now() - interval '26 hours', now() - interval '25 hours', 'Anaphylactic reaction, EpiPen given, EMS transport.', '4a000000-0000-4000-8000-000000000001');

select app.serious_occurrence_reminders();
select app.serious_occurrence_reminders(); -- second run must not duplicate

select is(
  (select count(*) from public.notification
   where event_type = 'serious_occurrence' and ref_id = '7a000000-0000-4000-8000-000000000001'),
  1::bigint,
  's38_deadline_warning_sent_exactly_once'
);

select is(
  (select count(*) from public.notification
   where event_type = 'serious_occurrence' and ref_id = '7a000000-0000-4000-8000-000000000002'
     and title like '%OVERDUE%'),
  1::bigint,
  's38_overdue_notice_sent_exactly_once'
);

select throws_like(
  $$delete from public.serious_occurrence_update where true$$,
  '%append-only%',
  'never_occurrence_records_deleted'
);

-- The business-day math dies without holiday data: coverage must always
-- extend at least two years out. When this fails, extend the seed in 0020.
select ok(
  (select max(holiday_date) from public.statutory_holiday where jurisdiction_code = 'CA-ON')
    >= (current_date + interval '2 years')::date,
  'statutory_holiday_coverage_two_years_out'
);

select * from finish();
rollback;
