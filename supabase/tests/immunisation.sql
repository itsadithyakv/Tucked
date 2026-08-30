-- pgTAP: s. 35 immunisation registry. What matters: a medical exemption
-- always names its physician/NP, a conscience/religious exemption is always
-- notarised, "attends school" never covers an infant, the ledger is
-- append-only with latest-wins, and parents see only their own child.

begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '1e000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sup@imm.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1e000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent@imm.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('2e000000-0000-4000-8000-000000000001', 'Imm Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('3e100000-0000-4000-8000-000000000001', '2e000000-0000-4000-8000-000000000001', 'Imm Centre', 'IMM-1', '1 Imm St, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('4e000000-0000-4000-8000-000000000001', '1e000000-0000-4000-8000-000000000001', 'Sup Imm', 'sup@imm.local'),
  ('4e000000-0000-4000-8000-000000000002', '1e000000-0000-4000-8000-000000000002', 'Parent Imm', 'parent@imm.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('4e000000-0000-4000-8000-000000000001', '3e100000-0000-4000-8000-000000000001', 'supervisor', true),
  ('4e000000-0000-4000-8000-000000000002', '3e100000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('4e000000-0000-4000-8000-000000000001', '3e100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('5e000000-0000-4000-8000-000000000001', '3e100000-0000-4000-8000-000000000001', 'Imm Household');
-- Nia: 18 months old (not in school). Skye: 5 years old (school age).
-- Remy: another household entirely.
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date) values
  ('6e000000-0000-4000-8000-000000000001', '3e100000-0000-4000-8000-000000000001', 'Nia Imm', (current_date - interval '18 months')::date, '2026-01-05'),
  ('6e000000-0000-4000-8000-000000000002', '3e100000-0000-4000-8000-000000000001', 'Skye Imm', (current_date - interval '5 years')::date, '2026-01-05'),
  ('6e000000-0000-4000-8000-000000000003', '3e100000-0000-4000-8000-000000000001', 'Remy Imm', (current_date - interval '3 years')::date, '2026-01-05');
insert into public.child_household (child_id, household_id, centre_id) values
  ('6e000000-0000-4000-8000-000000000001', '5e000000-0000-4000-8000-000000000001', '3e100000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view) values
  ('5e000000-0000-4000-8000-000000000001', '4e000000-0000-4000-8000-000000000002', '3e100000-0000-4000-8000-000000000001', 'parent', true);

-- ── as the supervisor ───────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1e000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select throws_like(
  $$select public.record_immunisation('3e100000-0000-4000-8000-000000000001','6e000000-0000-4000-8000-000000000001','immunised', '', null, null, '4e000000-0000-4000-8000-000000000001', '4242')$$,
  '%say what record is on file%',
  's35_immunised_needs_the_record_detail'
);

select throws_like(
  $$select public.record_immunisation('3e100000-0000-4000-8000-000000000001','6e000000-0000-4000-8000-000000000001','medical_exemption', 'MMR exemption', null, null, '4e000000-0000-4000-8000-000000000001', '4242')$$,
  '%names the physician or nurse practitioner%',
  's35_medical_exemption_names_the_practitioner'
);

select throws_like(
  $$select public.record_immunisation('3e100000-0000-4000-8000-000000000001','6e000000-0000-4000-8000-000000000001','conscience_exemption', 'religious belief', null, null, '4e000000-0000-4000-8000-000000000001', '4242')$$,
  '%must be notarised%',
  's35_conscience_exemption_must_be_notarised'
);

select throws_like(
  $$select public.record_immunisation('3e100000-0000-4000-8000-000000000001','6e000000-0000-4000-8000-000000000001','attends_school', null, null, null, '4e000000-0000-4000-8000-000000000001', '4242')$$,
  '%under 44 months%',
  's35_attends_school_never_covers_an_infant'
);

select lives_ok(
  $$select public.record_immunisation('3e100000-0000-4000-8000-000000000001','6e000000-0000-4000-8000-000000000001','immunised', 'Record per Toronto Public Health schedule to the 12-month visit', null, null, '4e000000-0000-4000-8000-000000000001', '4242')$$,
  's35_immunisation_record_on_file'
);

select lives_ok(
  $$select public.record_immunisation('3e100000-0000-4000-8000-000000000001','6e000000-0000-4000-8000-000000000001','medical_exemption', 'Statement of Medical Exemption re varicella', 'Dr. A. Okonkwo, NP', null, '4e000000-0000-4000-8000-000000000001', '4242')$$,
  's35_medical_exemption_recorded'
);

-- the ledger: both rows kept, the LATEST is the current status
select is(
  (select count(*) from public.immunisation_record where child_id = '6e000000-0000-4000-8000-000000000001'),
  2::bigint,
  's35_history_is_a_ledger'
);

select is(
  (select status from public.current_immunisation where child_id = '6e000000-0000-4000-8000-000000000001'),
  'medical_exemption',
  's35_current_status_is_the_latest_row'
);

select lives_ok(
  $$select public.record_immunisation('3e100000-0000-4000-8000-000000000001','6e000000-0000-4000-8000-000000000002','attends_school', 'JK at Maplewood PS', null, null, '4e000000-0000-4000-8000-000000000001', '4242')$$,
  's35_school_age_child_attends_school'
);

select throws_ok(
  $$insert into public.immunisation_record (centre_id, child_id, status, detail, recorded_by)
    values ('3e100000-0000-4000-8000-000000000001','6e000000-0000-4000-8000-000000000001','immunised','x','4e000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  's35_no_direct_client_writes'
);

-- ── as the parent: own child only ───────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1e000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select is(
  (select count(distinct child_id) from public.immunisation_record),
  1::bigint,
  's72_parent_sees_own_childs_immunisation_only'
);

-- ── as owner: append-only, audited ──────────────────────────────────────────
reset role;

select throws_like(
  $$update public.immunisation_record set detail = 'edited' where true$$,
  '%never edited%',
  'never_immunisation_rows_edited'
);

select throws_like(
  $$delete from public.immunisation_record where true$$,
  '%append-only%',
  'never_immunisation_rows_deleted'
);

select is(
  (select count(*) from public.audit_event
   where table_name = 'immunisation_record' and centre_id = '3e100000-0000-4000-8000-000000000001'),
  3::bigint,
  'audit_every_immunisation_write'
);

select * from finish();
rollback;
