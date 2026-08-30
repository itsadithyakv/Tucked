-- pgTAP: fees, the CWELCC cap and CRA receipts. The load-bearing rules: the
-- cap is data and the database refuses a base fee above it; eligibility is
-- computed from the date of birth and cannot be ticked away; a non-base fee
-- that is a condition of enrolment is unrepresentable; MONEY NEVER GATES A
-- RECORD; a receipt is issued from what was received, snapshots the names so
-- it survives the children's-record anonymiser, and is redacted only after
-- the six years O. Reg. 138/15 s. 27.1 requires.

begin;

create extension if not exists pgtap with schema extensions;

select plan(43);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000d1', 'authenticated', 'authenticated', 'sup@fee.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000d2', 'authenticated', 'authenticated', 'edu@fee.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000d3', 'authenticated', 'authenticated', 'parent@fee.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000d4', 'authenticated', 'authenticated', 'other@fee.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('21600000-0000-4000-8000-000000000001', 'Fee Licensee Inc.');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at, cwelcc_enrolled) values
  ('31600000-0000-4000-8000-000000000001', '21600000-0000-4000-8000-000000000001', 'Fee Centre', 'FEE-1', '9 Ledger Lane, Toronto, ON', '07:30', '18:00', true);

insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('32600000-0000-4000-8000-000000000001', '31600000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('33600000-0000-4000-8000-000000000001', '31600000-0000-4000-8000-000000000001', '32600000-0000-4000-8000-000000000001', 'Ledger room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('41600000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000d1', 'Sup Ledger', 'sup@fee.local'),
  ('41600000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000d2', 'Edu Ledger', 'edu@fee.local'),
  ('41600000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-0000000000d3', 'Parent Ledger', 'parent@fee.local'),
  ('41600000-0000-4000-8000-000000000004', '20000000-0000-4000-8000-0000000000d4', 'Other Parent', 'other@fee.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('41600000-0000-4000-8000-000000000001', '31600000-0000-4000-8000-000000000001', 'licensee_admin', true),
  ('41600000-0000-4000-8000-000000000002', '31600000-0000-4000-8000-000000000001', 'rece', true),
  ('41600000-0000-4000-8000-000000000003', '31600000-0000-4000-8000-000000000001', 'family_adult', false),
  ('41600000-0000-4000-8000-000000000004', '31600000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('41600000-0000-4000-8000-000000000001', '31600000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('41600000-0000-4000-8000-000000000002', '31600000-0000-4000-8000-000000000001', extensions.crypt('7171', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('51600000-0000-4000-8000-000000000001', '31600000-0000-4000-8000-000000000001', 'Ledger Household'),
  ('51600000-0000-4000-8000-000000000002', '31600000-0000-4000-8000-000000000001', 'Other Household');
-- a preschooler and a school-age sibling, plus a child in the other household
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('61600000-0000-4000-8000-000000000001', '31600000-0000-4000-8000-000000000001', 'Wilf Ledger', (current_date - interval '3 years')::date, '2026-01-05', '33600000-0000-4000-8000-000000000001'),
  ('61600000-0000-4000-8000-000000000002', '31600000-0000-4000-8000-000000000001', 'Nell Ledger', (current_date - interval '8 years')::date, '2026-01-05', '33600000-0000-4000-8000-000000000001'),
  ('61600000-0000-4000-8000-000000000003', '31600000-0000-4000-8000-000000000001', 'Zed Other', (current_date - interval '3 years')::date, '2026-01-05', '33600000-0000-4000-8000-000000000001');
insert into public.child_household (child_id, household_id, centre_id) values
  ('61600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000001', '31600000-0000-4000-8000-000000000001'),
  ('61600000-0000-4000-8000-000000000002', '51600000-0000-4000-8000-000000000001', '31600000-0000-4000-8000-000000000001'),
  ('61600000-0000-4000-8000-000000000003', '51600000-0000-4000-8000-000000000002', '31600000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent, can_bill) values
  ('51600000-0000-4000-8000-000000000001', '41600000-0000-4000-8000-000000000003', '31600000-0000-4000-8000-000000000001', 'parent', true, true, true),
  ('51600000-0000-4000-8000-000000000002', '41600000-0000-4000-8000-000000000004', '31600000-0000-4000-8000-000000000001', 'parent', true, true, true);

-- ── the cap is data, and eligibility is arithmetic ──────────────────────────
select is(
  app.cwelcc_cap('31600000-0000-4000-8000-000000000001', '2026-08-30'),
  22.00::numeric,
  'cwelcc_the_cap_in_force_comes_from_the_parameter_table'
);

select is(
  app.cwelcc_cap('31600000-0000-4000-8000-000000000001', '2023-06-01'),
  12.00::numeric,
  'cwelcc_an_earlier_year_reads_the_cap_that_applied_then'
);

select ok(
  app.cwelcc_eligible('31600000-0000-4000-8000-000000000001', '61600000-0000-4000-8000-000000000001', current_date),
  'cwelcc_a_three_year_old_is_eligible'
);

select ok(
  not app.cwelcc_eligible('31600000-0000-4000-8000-000000000001', '61600000-0000-4000-8000-000000000002', current_date),
  'cwelcc_an_eight_year_old_is_not'
);

-- a child who turned six in May is still eligible in June, and not in July
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date) values
  ('61600000-0000-4000-8000-000000000004', '31600000-0000-4000-8000-000000000001', 'June Ledger', '2020-05-14', '2026-01-05');

select ok(
  app.cwelcc_eligible('31600000-0000-4000-8000-000000000001', '61600000-0000-4000-8000-000000000004', '2026-06-15'),
  'cwelcc_turning_six_before_the_june_cutoff_keeps_eligibility_to_the_cutoff'
);

select ok(
  not app.cwelcc_eligible('31600000-0000-4000-8000-000000000001', '61600000-0000-4000-8000-000000000004', '2026-07-01'),
  'cwelcc_and_it_ends_after_the_cutoff'
);

-- ── as the licensee ─────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000d1","role":"authenticated"}', true);
set local role authenticated;

select throws_like(
  $$select public.set_fee_schedule('31600000-0000-4000-8000-000000000001', 'preschool', 58.00, 58.00, current_date, '41600000-0000-4000-8000-000000000001', '4242')$$,
  '%cannot be more than $22.00 a day%',
  'cwelcc_a_base_fee_above_the_cap_is_refused'
);

select lives_ok(
  $$select public.set_fee_schedule('31600000-0000-4000-8000-000000000001', 'preschool', 22.00, 58.00, current_date, '41600000-0000-4000-8000-000000000001', '4242')$$,
  'cwelcc_the_capped_fee_is_saved'
);

select throws_like(
  $$select public.set_fee_item('31600000-0000-4000-8000-000000000001', 'trip', 'Field trip', 'non_base', 12.00, '  ', true, '41600000-0000-4000-8000-000000000001', '4242')$$,
  '%say what the fee is for%',
  'cwelcc_a_non_base_fee_explains_itself'
);

select lives_ok(
  $$select public.set_fee_item('31600000-0000-4000-8000-000000000001', 'trip', 'Field trip', 'non_base', 12.00, 'Optional outing to the conservation area; never a condition of attendance.', true, '41600000-0000-4000-8000-000000000001', '4242')$$,
  'cwelcc_an_optional_non_base_fee_is_recorded'
);

select is(
  (select optional from public.fee_item where code = 'trip'),
  true,
  'cwelcc_a_non_base_fee_is_optional_whatever_was_asked_for'
);

reset role;
select throws_like(
  $$insert into public.fee_item (centre_id, code, label, kind, amount, description, optional, recorded_by)
    values ('31600000-0000-4000-8000-000000000001', 'mandatory', 'Compulsory extra', 'non_base', 40.00, 'A condition of enrolment', false, '41600000-0000-4000-8000-000000000001')$$,
  '%non_base_fees_are_always_optional%',
  'cwelcc_a_compulsory_non_base_fee_cannot_even_be_written_down'
);
set local role authenticated;

-- ── charging ────────────────────────────────────────────────────────────────
select throws_like(
  $$select public.record_fee_charge('31600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000001', '61600000-0000-4000-8000-000000000001', 'base', 'August base fees', '2026-08-01', '2026-08-31', 21, 630.00, null, '41600000-0000-4000-8000-000000000001', '4242')$$,
  '%the CWELCC cap is $22.00%',
  'cwelcc_a_charge_over_the_cap_is_refused_even_when_the_schedule_was_right'
);

select lives_ok(
  $$select public.record_fee_charge('31600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000001', '61600000-0000-4000-8000-000000000001', 'base', 'August base fees', '2026-08-01', '2026-08-31', 21, 462.00, null, '41600000-0000-4000-8000-000000000001', '4242')$$,
  'cwelcc_the_capped_charge_goes_through'
);

select results_eq(
  $$select unit_amount, cap_at_charge, eligible_at_charge from public.fee_charge
    where child_id = '61600000-0000-4000-8000-000000000001'$$,
  $$values (22.00::numeric, 22.00::numeric, true)$$,
  'cwelcc_the_charge_records_the_cap_and_the_eligibility_that_applied'
);

-- the school-age sibling is not eligible, so the unfunded fee is allowed
select lives_ok(
  $$select public.record_fee_charge('31600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000001', '61600000-0000-4000-8000-000000000002', 'base', 'August before and after school', '2026-08-01', '2026-08-31', 21, 588.00, null, '41600000-0000-4000-8000-000000000001', '4242')$$,
  'cwelcc_an_ineligible_child_is_charged_the_unfunded_fee'
);

reset role;
select throws_like(
  $$update public.fee_charge set amount = 1.00 where true$$,
  '%never edited%',
  'oreg138_a_charge_is_never_edited'
);

select throws_like(
  $$delete from public.fee_charge where true$$,
  '%append-only%',
  'oreg138_a_charge_is_never_deleted'
);
set local role authenticated;

select lives_ok(
  $$select public.record_fee_credit('31600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000001', (select id from public.fee_charge where child_id = '61600000-0000-4000-8000-000000000002'), 56.00, 'Two closure days in August, refunded per the handbook.', '41600000-0000-4000-8000-000000000001', '4242')$$,
  'oreg138_a_mistake_is_a_credit_note_beside_the_charge'
);

select throws_like(
  $$select public.record_fee_payment('31600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000001', 100.00, 'e_transfer', (current_date + 1), null, '41600000-0000-4000-8000-000000000003', '41600000-0000-4000-8000-000000000001', '4242')$$,
  '%when it arrives, not before%',
  'oreg138_a_payment_is_recorded_when_it_arrives'
);

select lives_ok(
  $$select public.record_fee_payment('31600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000001', 800.00, 'pre_authorised_debit', '2026-08-03', 'PAD 2026-08', '41600000-0000-4000-8000-000000000003', '41600000-0000-4000-8000-000000000001', '4242')$$,
  'oreg138_a_payment_is_recorded'
);

select is(
  (select balance from public.household_balance where household_id = '51600000-0000-4000-8000-000000000001'),
  194.00::numeric,
  'oreg138_the_balance_is_charges_less_credits_less_payments'
);

-- ── §9.14: money never gates a record ───────────────────────────────────────
-- the family is 194 dollars behind, and nothing about the child changes
select is(
  (select count(*) from public.child where centre_id = '31600000-0000-4000-8000-000000000001'),
  4::bigint,
  'never_arrears_hide_a_child_from_the_centre'
);

select lives_ok(
  $$select public.record_attendance('31600000-0000-4000-8000-000000000001', '61600000-0000-4000-8000-000000000001', 'arrive', '33600000-0000-4000-8000-000000000001', now(), '41600000-0000-4000-8000-000000000001', '4242')$$,
  'never_arrears_block_a_child_being_signed_in'
);

-- and no policy anywhere consults the ledger
select is(
  (select count(*) from pg_policies
   where schemaname = 'public'
     and (qual like '%household_balance%' or qual like '%fee_payment%' or qual like '%fee_charge%')
     and tablename not in ('fee_charge', 'fee_credit', 'fee_payment', 'cra_receipt', 'cra_receipt_line')),
  0::bigint,
  'never_a_policy_anywhere_reads_the_ledger'
);

-- ── who can see the money ───────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000d2","role":"authenticated"}', true);

select is(
  (select count(*) from public.fee_charge),
  0::bigint,
  'pipeda_the_room_never_sees_what_a_family_pays'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000d3","role":"authenticated"}', true);

select is(
  (select count(*) from public.fee_charge),
  2::bigint,
  'pipeda_a_family_sees_its_own_ledger'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000d4","role":"authenticated"}', true);

select is(
  (select count(*) from public.fee_charge),
  0::bigint,
  'pipeda_and_never_another_familys'
);

-- ── the February one-tap ────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000d1","role":"authenticated"}', true);

select throws_like(
  $$select public.issue_cra_receipt('31600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000001', 2026, '41600000-0000-4000-8000-000000000001', '4242')$$,
  '%business number%',
  'cra_a_receipt_needs_the_licensees_business_number'
);

reset role;
update public.licensee set business_number = '80012 3456 RP0001', receipt_name = 'Fee Licensee Inc.'
where id = '21600000-0000-4000-8000-000000000001';
set local role authenticated;

select throws_like(
  $$select public.issue_cra_receipt('31600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000002', 2026, '41600000-0000-4000-8000-000000000001', '4242')$$,
  '%no payments were received%',
  'cra_a_family_that_paid_nothing_gets_no_receipt'
);

select lives_ok(
  $$select public.issue_cra_receipt('31600000-0000-4000-8000-000000000001', '51600000-0000-4000-8000-000000000001', 2026, '41600000-0000-4000-8000-000000000001', '4242')$$,
  'cra_the_receipt_is_issued'
);

select results_eq(
  $$select receipt_number, total_amount, payer_name, provider_business_number
    from public.cra_receipt where tax_year = 2026$$,
  $$values ('2026-0001', 800.00::numeric, 'Parent Ledger', '80012 3456 RP0001')$$,
  'cra_the_receipt_is_what_was_received_not_what_was_billed'
);

-- 800 split by what each child was charged: 462 and 588 of 1050
select results_eq(
  $$select child_name, amount from public.cra_receipt_line
    join public.cra_receipt r on r.id = receipt_id
    where r.tax_year = 2026 order by child_name$$,
  $$values ('Nell Ledger', 448.00::numeric), ('Wilf Ledger', 352.00::numeric)$$,
  'cra_payments_are_split_across_the_children_by_what_each_was_charged'
);

reset role;
select throws_like(
  $$update public.cra_receipt set total_amount = 9999.00 where true$$,
  '%never altered%',
  'cra_an_issued_receipt_is_never_altered'
);

-- the snapshot is the child's name AT ISSUE, so the three-year children's
-- record anonymiser cannot hollow out a six-year financial record
update public.child set full_name = 'Anonymised Child' where id = '61600000-0000-4000-8000-000000000001';
select is(
  (select count(*) from public.cra_receipt_line where child_name = 'Wilf Ledger'),
  1::bigint,
  'oreg138_the_receipt_snapshot_outlives_the_childs_record'
);

-- ── six years, and not a day before ─────────────────────────────────────────
select throws_like(
  $$select app.redact_cra_receipt((select id from public.cra_receipt where tax_year = 2026))$$,
  '%never redacted before%',
  'oreg138_a_financial_record_is_never_redacted_early'
);

update public.retention_clock set purge_after = current_date - 1
where subject_table = 'cra_receipt';

select lives_ok(
  $$select app.redact_cra_receipt((select id from public.cra_receipt where tax_year = 2026))$$,
  'oreg138_after_six_years_the_personal_information_goes'
);

select results_eq(
  $$select payer_name, total_amount from public.cra_receipt where tax_year = 2026$$,
  $$values ('Redacted after six years', 800.00::numeric)$$,
  'oreg138_the_amount_stays_and_the_names_go'
);

-- ── leaving CWELCC ──────────────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000d1","role":"authenticated"}', true);

select throws_like(
  $$select public.record_cwelcc_withdrawal('31600000-0000-4000-8000-000000000001', (current_date + 10), 'Costs', '41600000-0000-4000-8000-000000000001', '4242')$$,
  '%cwelcc_notice_is_thirty_days%',
  'cwelcc_leaving_takes_thirty_days_written_notice'
);

select lives_ok(
  $$select public.record_cwelcc_withdrawal('31600000-0000-4000-8000-000000000001', (current_date + 45), 'The licensee is not able to continue at the funded rate.', '41600000-0000-4000-8000-000000000001', '4242')$$,
  'cwelcc_a_notice_with_enough_warning_is_recorded'
);

select cmp_ok(
  (select count(*) from public.notification where event_type = 'cwelcc_withdrawal'),
  '>=', 4::bigint,
  'cwelcc_every_family_and_every_employee_is_told'
);

select lives_ok(
  $$select public.record_cwelcc_notice_delivery((select id from public.cwelcc_withdrawal_notice limit 1), '41600000-0000-4000-8000-000000000003', 'parent', 'signed_paper', '41600000-0000-4000-8000-000000000001', '4242')$$,
  'cwelcc_delivery_to_each_person_is_provable'
);

select throws_like(
  $$select public.record_cwelcc_notice_delivery((select id from public.cwelcc_withdrawal_notice limit 1), '41600000-0000-4000-8000-000000000003', 'parent', 'email', '41600000-0000-4000-8000-000000000001', '4242')$$,
  '%already been served%',
  'cwelcc_delivery_is_recorded_once_per_person'
);

select * from finish();
rollback;
