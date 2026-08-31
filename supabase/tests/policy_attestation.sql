-- pgTAP: policies staff must have read (s. 46 and the policies a centre holds).
-- The load-bearing rules: an attestation is against a VERSION, because "Dara
-- has read the program statement" is worthless if nobody can say which one;
-- modifying a policy resets everyone, which is the wording of s. 46(3) and the
-- thing a centre forgets; the program statement follows the handbook by
-- itself so the two cannot drift; and who must read what is role data, so a
-- volunteer is asked for the supervision policy and not the medication one.

begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000c7', 'authenticated', 'authenticated', 'sup@pol.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000c8', 'authenticated', 'authenticated', 'edu@pol.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000c9', 'authenticated', 'authenticated', 'vol@pol.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name, business_number) values
  ('22100000-0000-4000-8000-000000000001', 'Policy Licensee', '80099 8877 RP0001');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('32100000-0000-4000-8000-000000000001', '22100000-0000-4000-8000-000000000001', 'Policy Centre', 'POL-1', '4 Statement Way, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('42100000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000c7', 'Sup Policy', 'sup@pol.local'),
  ('42100000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000c8', 'Edu Policy', 'edu@pol.local'),
  ('42100000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-0000000000c9', 'Vol Policy', 'vol@pol.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('42100000-0000-4000-8000-000000000001', '32100000-0000-4000-8000-000000000001', 'supervisor', true),
  ('42100000-0000-4000-8000-000000000002', '32100000-0000-4000-8000-000000000001', 'rece', true),
  ('42100000-0000-4000-8000-000000000003', '32100000-0000-4000-8000-000000000001', 'volunteer', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('42100000-0000-4000-8000-000000000001', '32100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('42100000-0000-4000-8000-000000000002', '32100000-0000-4000-8000-000000000001', extensions.crypt('7171', extensions.gen_salt('bf')));

-- ── who must read what is role data ─────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000c7","role":"authenticated"}', true);
set local role authenticated;

select is(
  (select count(*) from public.policy_attestation_gaps('32100000-0000-4000-8000-000000000001')
   where full_name = 'Vol Policy' and policy_key = 'staff_training'),
  0::bigint,
  's46_a_volunteer_is_not_asked_to_read_the_staff_training_policy'
);

select is(
  (select count(*) from public.policy_attestation_gaps('32100000-0000-4000-8000-000000000001')
   where full_name = 'Vol Policy' and policy_key in ('program_statement', 'prohibited_practices', 'volunteer_student_supervision')),
  3::bigint,
  's46_but_is_asked_for_the_statement_the_prohibited_practices_and_the_supervision_policy'
);

select is(
  (select distinct state from public.policy_attestation_gaps('32100000-0000-4000-8000-000000000001')),
  'not_published',
  's46_a_centre_that_has_published_nothing_says_so_rather_than_looking_compliant'
);

-- ── publishing ──────────────────────────────────────────────────────────────
select throws_like(
  $$select public.publish_policy('32100000-0000-4000-8000-000000000001', 'prohibited_practices', '   ', null, '42100000-0000-4000-8000-000000000001', '4242')$$,
  '%not a policy%',
  's46_a_policy_with_no_words_is_not_a_policy'
);

select throws_like(
  $$select public.publish_policy('32100000-0000-4000-8000-000000000001', 'nap_time_vibes', 'Something', null, '42100000-0000-4000-8000-000000000001', '4242')$$,
  '%no policy "nap_time_vibes"%',
  's46_a_policy_outside_the_jurisdictions_set_is_refused'
);

select lives_ok(
  $$select public.publish_policy('32100000-0000-4000-8000-000000000001', 'prohibited_practices',
      'Corporal punishment; deliberate harsh or degrading measures; depriving a child of basic needs; locking exits for confinement; using a locked room to confine a child.',
      null, '42100000-0000-4000-8000-000000000001', '4242')$$,
  's48_the_prohibited_practices_are_published'
);

select throws_like(
  $$select public.publish_policy('32100000-0000-4000-8000-000000000001', 'prohibited_practices',
      'Corporal punishment; deliberate harsh or degrading measures; depriving a child of basic needs; locking exits for confinement; using a locked room to confine a child.',
      null, '42100000-0000-4000-8000-000000000001', '4242')$$,
  '%word for word%',
  's46_republishing_the_same_words_never_asks_anyone_to_read_it_again'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000c8","role":"authenticated"}', true);

select throws_like(
  $$select public.publish_policy('32100000-0000-4000-8000-000000000001', 'staff_training', 'Anything', null, '42100000-0000-4000-8000-000000000002', '7171')$$,
  '%the licensee''s to publish%',
  's46_an_educator_does_not_publish_the_centres_policies'
);

-- ── attesting ───────────────────────────────────────────────────────────────
select is(
  (select state from public.policy_attestation_gaps('32100000-0000-4000-8000-000000000001')
   where full_name = 'Edu Policy' and policy_key = 'prohibited_practices'),
  'never_read',
  's48_before_anyone_reads_it_the_file_says_so_plainly'
);

select lives_ok(
  $$select public.attest_policy((select id from public.policy_version where policy_key = 'prohibited_practices'))$$,
  's48_the_educator_confirms_they_have_read_it'
);

select is(
  (select state from public.policy_attestation_gaps('32100000-0000-4000-8000-000000000001')
   where full_name = 'Edu Policy' and policy_key = 'prohibited_practices'),
  'current',
  's48_and_the_gap_closes'
);

select is(
  (select method from public.policy_attestation
   where person_id = '42100000-0000-4000-8000-000000000002'),
  'in_app',
  's48_a_person_confirming_for_themselves_is_the_strongest_evidence'
);

-- attesting twice is not two records
select lives_ok(
  $$select public.attest_policy((select id from public.policy_version where policy_key = 'prohibited_practices'))$$,
  's48_reading_it_twice_is_not_an_error'
);

select is(
  (select count(*) from public.policy_attestation where person_id = '42100000-0000-4000-8000-000000000002'),
  1::bigint,
  's48_but_it_is_still_one_record'
);

-- ── a modification resets everyone ──────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000c7","role":"authenticated"}', true);

select lives_ok(
  $$select public.publish_policy('32100000-0000-4000-8000-000000000001', 'prohibited_practices',
      'Corporal punishment; deliberate harsh or degrading measures; depriving a child of basic needs; locking exits for confinement; using a locked room to confine a child. Any staff member who witnesses one reports it to the supervisor the same day.',
      'Added the reporting duty.', '42100000-0000-4000-8000-000000000001', '4242')$$,
  's46_a_modified_policy_is_a_new_version'
);

select is(
  (select state from public.policy_attestation_gaps('32100000-0000-4000-8000-000000000001')
   where full_name = 'Edu Policy' and policy_key = 'prohibited_practices'),
  'never_read',
  's46_and_everyone_who_read_the_old_one_has_to_read_it_again'
);

select is(
  (select count(*) from public.policy_version where policy_key = 'prohibited_practices' and superseded_at is null),
  1::bigint,
  's46_only_one_version_is_ever_live'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000c8","role":"authenticated"}', true);

select throws_like(
  $$select public.attest_policy((select id from public.policy_version
      where policy_key = 'prohibited_practices' and superseded_at is not null))$$,
  '%read the current one%',
  's46_nobody_can_attest_to_a_version_that_has_been_replaced'
);

-- the earlier attestation is still on the record — it was true when it was made
select is(
  (select count(*) from public.policy_attestation
   where person_id = '42100000-0000-4000-8000-000000000002'),
  1::bigint,
  's46_the_old_attestation_is_kept_because_it_was_true_when_it_was_made'
);

-- ── the program statement follows the handbook ──────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000c7","role":"authenticated"}', true);

update public.centre
set anaphylaxis_policy = 'Epinephrine auto-injectors are stored unlocked in each room.'
where id = '32100000-0000-4000-8000-000000000001';

select lives_ok(
  $$select public.save_handbook_section('32100000-0000-4000-8000-000000000001', v.key, v.body, '42100000-0000-4000-8000-000000000001', '4242')
    from (values
      ('services_and_age_groups', 'Infant, toddler and preschool, full day.'),
      ('hours_and_holidays', 'Open 07:30 to 18:00, closed on statutory holidays.'),
      ('fees', 'Base fee $22.00 per day.'),
      ('admission_and_discharge', 'Two weeks written notice on either side.'),
      ('off_premises', 'Neighbourhood walks daily.'),
      ('volunteers_and_students', 'Never alone with children, never in ratio.'),
      ('payment', 'Pre-authorised debit monthly.'),
      ('refunds', 'Refunded for closures beyond five days.'),
      ('safe_arrival_and_dismissal', 'Released only to an authorised person.'),
      ('waiting_list', 'No fee to join.'),
      ('issues_and_concerns', 'Room educator first, then the supervisor.'),
      ('program_statement', 'Grounded in How Does Learning Happen? Prohibited practices listed in full.')
    ) as v(key, body)$$,
  's45_the_handbook_is_written'
);

select lives_ok(
  $$select public.publish_handbook('32100000-0000-4000-8000-000000000001', null, '42100000-0000-4000-8000-000000000001', '4242')$$,
  's45_and_issued'
);

select results_eq(
  $$select version, body from public.policy_version
    where policy_key = 'program_statement' and superseded_at is null$$,
  $$values (1, 'Grounded in How Does Learning Happen? Prohibited practices listed in full.')$$,
  's46_issuing_the_handbook_publishes_the_program_statement_nobody_has_to_remember'
);

-- changing it in the handbook is a modification under s. 46(3)
select lives_ok(
  $$select public.save_handbook_section('32100000-0000-4000-8000-000000000001', 'program_statement',
      'Grounded in How Does Learning Happen? Prohibited practices listed in full, and reviewed with every new educator on their first day.',
      '42100000-0000-4000-8000-000000000001', '4242')$$,
  's45_the_statement_is_rewritten'
);

select lives_ok(
  $$select public.publish_handbook('32100000-0000-4000-8000-000000000001', 'The program statement now names the first-day review.', '42100000-0000-4000-8000-000000000001', '4242')$$,
  's45_and_the_handbook_reissued'
);

select is(
  (select version from public.policy_version
   where policy_key = 'program_statement' and superseded_at is null),
  2,
  's46_a_changed_statement_becomes_a_new_policy_version_by_itself'
);

select alike(
  (select summary from public.policy_version
   where policy_key = 'program_statement' and superseded_at is null),
  '%Everyone reviews it again%',
  's46_and_says_why_everyone_is_being_asked_again'
);

-- an unchanged statement does not make busywork
select lives_ok(
  $$select public.publish_policy('32100000-0000-4000-8000-000000000001', 'staff_training', 'Every educator completes annual training in first aid, anaphylaxis and the program statement.', null, '42100000-0000-4000-8000-000000000001', '4242')$$,
  's63_another_policy_is_published'
);

reset role;

select throws_like(
  $$update public.policy_version set body = 'Quietly reworded' where policy_key = 'staff_training'$$,
  '%never edited%',
  's46_a_published_policy_is_never_edited'
);

select throws_like(
  $$delete from public.policy_attestation where true$$,
  '%append-only%',
  's46_an_attestation_is_never_deleted'
);

select * from finish();
rollback;
