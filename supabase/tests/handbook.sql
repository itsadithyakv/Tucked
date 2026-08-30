-- pgTAP: the parent handbook (s. 45). The load-bearing rules: the required
-- section list is jurisdiction data (so another province is rows, not code);
-- a handbook cannot be issued with a section missing; a published version is
-- immutable and never deleted; sections the product already holds are read
-- from the live record rather than typed; and acknowledgement is per parent
-- per version, resetting when a new version is issued.

begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', 'sup@hb.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated', 'edu@hb.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated', 'parent@hb.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated', 'aunt@hb.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('21200000-0000-4000-8000-000000000001', 'Handbook Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at, cwelcc_enrolled) values
  ('31200000-0000-4000-8000-000000000001', '21200000-0000-4000-8000-000000000001', 'Handbook Centre', 'HB-1', '1 Handbook Rd, Toronto', '07:00', '18:00', false);

insert into public.person (id, auth_user_id, full_name, email) values
  ('41200000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-00000000000a', 'Sup Handbook', 'sup@hb.local'),
  ('41200000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-00000000000b', 'Edu Handbook', 'edu@hb.local'),
  ('41200000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-00000000000c', 'Parent Handbook', 'parent@hb.local'),
  ('41200000-0000-4000-8000-000000000004', '20000000-0000-4000-8000-00000000000d', 'Aunt Handbook', 'aunt@hb.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('41200000-0000-4000-8000-000000000001', '31200000-0000-4000-8000-000000000001', 'supervisor', true),
  ('41200000-0000-4000-8000-000000000002', '31200000-0000-4000-8000-000000000001', 'rece', true),
  ('41200000-0000-4000-8000-000000000003', '31200000-0000-4000-8000-000000000001', 'family_adult', false),
  ('41200000-0000-4000-8000-000000000004', '31200000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('41200000-0000-4000-8000-000000000001', '31200000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('41200000-0000-4000-8000-000000000002', '31200000-0000-4000-8000-000000000001', extensions.crypt('7171', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('51200000-0000-4000-8000-000000000001', '31200000-0000-4000-8000-000000000001', 'Handbook Household');
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date) values
  ('61200000-0000-4000-8000-000000000001', '31200000-0000-4000-8000-000000000001', 'Robin Handbook', '2023-04-02', '2026-01-05');
insert into public.child_household (child_id, household_id, centre_id) values
  ('61200000-0000-4000-8000-000000000001', '51200000-0000-4000-8000-000000000001', '31200000-0000-4000-8000-000000000001');
-- the parent may consent; the aunt is a viewer only
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('51200000-0000-4000-8000-000000000001', '41200000-0000-4000-8000-000000000003', '31200000-0000-4000-8000-000000000001', 'parent', true, true),
  ('51200000-0000-4000-8000-000000000001', '41200000-0000-4000-8000-000000000004', '31200000-0000-4000-8000-000000000001', 'other', true, false);

-- ── the required list is data, not code ─────────────────────────────────────
select is(
  (select count(*) from public.handbook_section_spec where jurisdiction_code = 'CA-ON'),
  14::bigint,
  's45_required_sections_are_jurisdiction_data'
);

-- ── as the supervisor ───────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;

select throws_like(
  $$select public.save_handbook_section('31200000-0000-4000-8000-000000000001', 'nap_policy', 'Something', '41200000-0000-4000-8000-000000000001', '4242')$$,
  '%no section "nap_policy"%',
  's45_unknown_section_refused'
);

select throws_like(
  $$select public.save_handbook_section('31200000-0000-4000-8000-000000000001', 'fees', '   ', '41200000-0000-4000-8000-000000000001', '4242')$$,
  '%never blank%',
  's45_section_is_never_blank'
);

select throws_like(
  $$select public.save_handbook_section('31200000-0000-4000-8000-000000000001', 'anaphylaxis', 'We have a policy.', '41200000-0000-4000-8000-000000000001', '4242')$$,
  '%edited on Plans & allergies%',
  's45_anaphylaxis_policy_is_never_retyped_into_the_handbook'
);

-- the CWELCC statement is generated, so it is never one of the missing ones
select is(
  (select count(*) from public.handbook_missing_sections('31200000-0000-4000-8000-000000000001')),
  13::bigint,
  's45_cwelcc_statement_is_written_from_the_centre_record'
);

select throws_like(
  $$select public.publish_handbook('31200000-0000-4000-8000-000000000001', null, '41200000-0000-4000-8000-000000000001', '4242')$$,
  '%still missing%',
  's45_incomplete_handbook_is_never_issued'
);

select lives_ok(
  $$select public.save_handbook_section('31200000-0000-4000-8000-000000000001', v.key, v.body, '41200000-0000-4000-8000-000000000001', '4242')
    from (values
      ('services_and_age_groups', 'Infant, toddler and preschool programs, full day.'),
      ('hours_and_holidays', 'Open 07:00 to 18:00, Monday to Friday. Closed on all statutory holidays.'),
      ('fees', 'Base fee $22.00 per day. Late pickup $1.00 per minute.'),
      ('admission_and_discharge', 'Admission in waiting-list order. Two weeks written notice on either side.'),
      ('off_premises', 'Neighbourhood walks daily; written consent for anything further.'),
      ('volunteers_and_students', 'Volunteers and students are never left alone with children and are never counted in ratios.'),
      ('payment', 'Pre-authorised debit on the first business day of each month.'),
      ('refunds', 'Fees are refunded for centre closures beyond five consecutive days.'),
      ('safe_arrival_and_dismissal', 'Children are released only to a person on the authorised list, with photo identification confirmed.'),
      ('waiting_list', 'No fee or deposit is charged. Families are told their position on request.'),
      ('issues_and_concerns', 'Raise a concern with the room educator, then the supervisor. A response within two business days.'),
      ('program_statement', 'Our program is grounded in How Does Learning Happen? Prohibited practices are listed in full.')
    ) as v(key, body)$$,
  's45_sections_written_by_the_centre'
);

-- the anaphylaxis policy lives on the centre (s. 39) — writing it there
-- completes the handbook section
update public.centre
set anaphylaxis_policy = 'Epinephrine auto-injectors are stored unlocked in each room. All staff are trained annually.'
where id = '31200000-0000-4000-8000-000000000001';

select is(
  (select count(*) from public.handbook_missing_sections('31200000-0000-4000-8000-000000000001')),
  0::bigint,
  's45_handbook_complete_once_every_section_is_written'
);

-- ── issuing it is a leadership act ──────────────────────────────────────────
select throws_like(
  $$select public.publish_handbook('31200000-0000-4000-8000-000000000001', null, '41200000-0000-4000-8000-000000000002', '7171')$$,
  '%only centre leadership%',
  's45_only_leadership_issues_the_handbook'
);

select lives_ok(
  $$select public.publish_handbook('31200000-0000-4000-8000-000000000001', null, '41200000-0000-4000-8000-000000000001', '4242')$$,
  's45_first_handbook_issued'
);

select is(
  (select count(*) from public.handbook_version_section vs
   join public.handbook_version v on v.id = vs.handbook_version_id where v.version = 1),
  14::bigint,
  's45_issued_handbook_carries_every_required_section'
);

select is(
  (select vs.body from public.handbook_version_section vs
   join public.handbook_version v on v.id = vs.handbook_version_id
   where v.version = 1 and vs.section_key = 'anaphylaxis'),
  'Epinephrine auto-injectors are stored unlocked in each room. All staff are trained annually.',
  's45_anaphylaxis_section_is_the_live_policy'
);

select alike(
  (select vs.body from public.handbook_version_section vs
   join public.handbook_version v on v.id = vs.handbook_version_id
   where v.version = 1 and vs.section_key = 'cwelcc'),
  '%does not participate in the Canada-Wide%',
  's45_cwelcc_section_cannot_contradict_the_record'
);

select throws_like(
  $$select public.publish_handbook('31200000-0000-4000-8000-000000000001', 'No changes really', '41200000-0000-4000-8000-000000000001', '4242')$$,
  '%nothing has changed%',
  's45_identical_handbook_is_never_reissued'
);

-- the centre joins CWELCC: the generated sentence changes, so the handbook has
-- genuinely changed and must be re-issued
update public.centre set cwelcc_enrolled = true where id = '31200000-0000-4000-8000-000000000001';

select throws_like(
  $$select public.publish_handbook('31200000-0000-4000-8000-000000000001', '  ', '41200000-0000-4000-8000-000000000001', '4242')$$,
  '%say what changed%',
  's45_reissue_tells_families_what_changed'
);

select lives_ok(
  $$select public.publish_handbook('31200000-0000-4000-8000-000000000001', 'We have joined CWELCC — base fees are now capped.', '41200000-0000-4000-8000-000000000001', '4242')$$,
  's45_second_version_issued'
);

select alike(
  (select vs.body from public.handbook_version_section vs
   join public.handbook_version v on v.id = vs.handbook_version_id
   where v.version = 2 and vs.section_key = 'cwelcc'),
  '%participates in the Canada-Wide%',
  's45_new_version_carries_the_new_fact'
);

-- ── who still has to be given it ────────────────────────────────────────────
select is(
  (select count(*) from public.handbook_outstanding),
  1::bigint,
  's45_outstanding_lists_the_consenting_parent_only'
);

-- ── as the parent ───────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-00000000000c","role":"authenticated"}', true);

select is(
  (select count(*) from public.handbook_content),
  0::bigint,
  's45_families_never_see_the_working_draft'
);

select is(
  (select count(*) from public.handbook_version_section),
  28::bigint,
  's45_families_read_every_issued_handbook'
);

select is(
  (select count(*) from public.notification
   where event_type = 'handbook_issued' and requires_acknowledgement),
  2::bigint,
  's45_each_issue_asks_the_parent_to_acknowledge'
);

select lives_ok(
  $$select public.acknowledge_handbook(
      (select id from public.handbook_version where version = 2))$$,
  's45_parent_acknowledges_in_the_app'
);

select is(
  (select count(*) from public.notification
   where event_type = 'handbook_issued' and acknowledged_at is null),
  1::bigint,
  's45_acknowledging_clears_only_that_version'
);

-- ── as the aunt: a viewer is not a guardian ─────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-00000000000d","role":"authenticated"}', true);

select throws_like(
  $$select public.acknowledge_handbook(
      (select id from public.handbook_version where version = 2))$$,
  '%only a consenting household adult%',
  's45_a_household_viewer_cannot_acknowledge_for_the_family'
);

-- ── back as the supervisor: the evidence ────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-00000000000a","role":"authenticated"}', true);

select is(
  (select count(*) from public.handbook_outstanding),
  0::bigint,
  's45_acknowledged_family_drops_off_the_outstanding_list'
);

select throws_like(
  $$select public.record_handbook_acknowledgement(
      (select id from public.handbook_version where version = 2),
      '41200000-0000-4000-8000-000000000003', now(),
      '41200000-0000-4000-8000-000000000001', '4242')$$,
  '%already acknowledged%',
  's45_one_acknowledgement_per_parent_per_version'
);

select throws_like(
  $$select public.record_handbook_acknowledgement(
      (select id from public.handbook_version where version = 1),
      '41200000-0000-4000-8000-000000000004', now(),
      '41200000-0000-4000-8000-000000000001', '4242')$$,
  '%consenting household member%',
  's45_paper_acknowledgement_must_come_from_a_guardian'
);

-- ── as owner: the issued handbook is the artefact, and it never moves ───────
reset role;

select throws_like(
  $$update public.handbook_version_section set body = 'Quietly reworded' where true$$,
  '%never edited%',
  's45_issued_handbook_is_never_edited'
);

select throws_like(
  $$delete from public.handbook_version where true$$,
  '%append-only%',
  's45_issued_handbook_is_never_deleted'
);

select * from finish();
rollback;
