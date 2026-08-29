-- pgTAP: s. 40 medication — authorisation strength, blanket-item logging,
-- expiry blocks, revocation, family scoping.

begin;

create extension if not exists pgtap with schema extensions;

select plan(13);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '14000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rece@med.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '14000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent@med.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('24000000-0000-4000-8000-000000000001', 'Med Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('3a000000-0000-4000-8000-000000000001', '24000000-0000-4000-8000-000000000001', 'Med Centre', 'MED-1', '1 Med St, Toronto', '07:30', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('3b000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', 'toddler', 15);
insert into public.room (id, centre_id, age_group_id, name) values
  ('3c000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', '3b000000-0000-4000-8000-000000000001', 'Toddler room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('44000000-0000-4000-8000-000000000001', '14000000-0000-4000-8000-000000000001', 'Rece Med', 'rece@med.local'),
  ('44000000-0000-4000-8000-000000000002', '14000000-0000-4000-8000-000000000002', 'Parent Med', 'parent@med.local'),
  ('44000000-0000-4000-8000-000000000003', null, 'NonConsent Adult', 'nc@med.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('44000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', 'rece', true),
  ('44000000-0000-4000-8000-000000000002', '3a000000-0000-4000-8000-000000000001', 'family_adult', false);
insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('44000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('64000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', 'Med Child', '2025-01-15', '2026-01-05', '3c000000-0000-4000-8000-000000000001'),
  ('64000000-0000-4000-8000-000000000002', '3a000000-0000-4000-8000-000000000001', 'Other Med Child', '2025-02-15', '2026-01-05', '3c000000-0000-4000-8000-000000000001');
insert into public.household (id, centre_id, name) values
  ('54000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', 'Med Household');
insert into public.child_household (child_id, household_id, centre_id) values
  ('64000000-0000-4000-8000-000000000001', '54000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('54000000-0000-4000-8000-000000000001', '44000000-0000-4000-8000-000000000002', '3a000000-0000-4000-8000-000000000001', 'parent', true, true),
  ('54000000-0000-4000-8000-000000000001', '44000000-0000-4000-8000-000000000003', '3a000000-0000-4000-8000-000000000001', 'grandparent', true, false);

-- ── as the RECE ─────────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"14000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select throws_like(
  $$select public.record_medication_authorisation(
      '3a000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001',
      'prescription','Amoxicillin','02243224', null, null, null,
      null, true, 'Fridge', (current_date + 30)::date, '44000000-0000-4000-8000-000000000001',
      '44000000-0000-4000-8000-000000000002', 'signed paper form on file',
      '44000000-0000-4000-8000-000000000001', '4242')$$,
  '%medication_needs_dose_and_schedule_or_symptoms%',
  's40_as_needed_alone_is_insufficient'
);

select lives_ok(
  $$select public.record_medication_authorisation(
      '3a000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001',
      'prescription','Amoxicillin','02243224', '5 ml', 'With lunch, daily', null,
      null, true, 'Fridge', (current_date + 30)::date, '44000000-0000-4000-8000-000000000001',
      '44000000-0000-4000-8000-000000000002', 'signed paper form on file',
      '44000000-0000-4000-8000-000000000001', '4242')$$,
  's40_dose_plus_schedule_authorised'
);

select throws_ok(
  $$select public.record_medication_authorisation(
      '3a000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001',
      'otc','Infant Tylenol', null, '2.5 ml', null, 'Fever above 38.5',
      null, true, 'Cupboard', null, null,
      '44000000-0000-4000-8000-000000000003', 'signed paper form on file',
      '44000000-0000-4000-8000-000000000001', '4242')$$,
  'authorisation must come from a consenting household member',
  's40_authoriser_must_hold_consent_permission'
);

select lives_ok(
  $$select public.record_medication_authorisation(
      '3a000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001',
      'diaper_cream','Zinc cream', null, null, null, null,
      null, true, 'Change table', null, null,
      '44000000-0000-4000-8000-000000000002', 'blanket consent on enrolment form',
      '44000000-0000-4000-8000-000000000001', '4242')$$,
  's40_blanket_item_authorised_without_dose'
);

reset role;
create temporary table t_auth on commit drop as
  select id, kind from public.medication_authorisation
  where centre_id = '3a000000-0000-4000-8000-000000000001';
grant select on t_auth to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"14000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$select public.record_medication_administration(
      (select id from t_auth where kind = 'diaper_cream'),
      now(), null, 'applied at change', '44000000-0000-4000-8000-000000000001', '4242')$$,
  's40_blanket_items_are_logged'
);

select lives_ok(
  $$select public.record_medication_administration(
      (select id from t_auth where kind = 'prescription'),
      now(), '5 ml', 'taken with lunch', '44000000-0000-4000-8000-000000000001', '4242')$$,
  's40_administration_logged_with_who_when_dose'
);

select is(
  (select count(*) from public.medication_administration),
  2::bigint,
  's40_every_administration_has_a_row'
);

-- revoke, then administration is blocked
select lives_ok(
  $$select public.revoke_medication_authorisation(
      (select id from t_auth where kind = 'prescription'),
      '44000000-0000-4000-8000-000000000001', '4242')$$,
  's40_authorisation_revocable'
);

select throws_ok(
  $$select public.record_medication_administration(
      (select id from t_auth where kind = 'prescription'),
      now(), '5 ml', 'again', '44000000-0000-4000-8000-000000000001', '4242')$$,
  'authorisation has been revoked',
  's40_no_administration_after_revocation'
);

-- expired medication is never administered
select lives_ok(
  $$select public.record_medication_authorisation(
      '3a000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001',
      'otc','Old Syrup', null, '2 ml', 'Morning', null,
      null, true, 'Cupboard', (current_date - 1)::date, null,
      '44000000-0000-4000-8000-000000000002', 'signed paper form on file',
      '44000000-0000-4000-8000-000000000001', '4242')$$,
  's40_expired_authorisation_can_be_recorded'
);

select throws_ok(
  $$select public.record_medication_administration(
      (select a.id from public.medication_authorisation a where a.drug_name = 'Old Syrup'),
      now(), '2 ml', null, '44000000-0000-4000-8000-000000000001', '4242')$$,
  'medication is expired; do not administer',
  's40_expired_medication_never_administered'
);

-- ── as the parent ───────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"14000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select is(
  (select count(distinct child_id) from public.medication_administration),
  1::bigint,
  's72_parent_sees_own_childs_medication_only'
);

-- ── owner: immutability ─────────────────────────────────────────────────────
reset role;

select throws_ok(
  $$update public.medication_administration set dose_given = '50 ml' where dose_given = '5 ml'$$,
  'medication administrations are never updated; record a correction',
  's40_administrations_never_edited'
);

select * from finish();
rollback;
