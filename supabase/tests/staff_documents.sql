-- pgTAP: staff files (ss. 53–64) — the documents and the rules that say what
-- is missing. The load-bearing rules: a staff file is not a shared drive (a
-- colleague never reads your police check); the requirements are jurisdiction
-- and role data, so the file reports absence rather than only presence; the
-- s. 60 vulnerable-sector arithmetic is derived, not typed; and a document is
-- superseded rather than overwritten or deleted.

begin;

create extension if not exists pgtap with schema extensions;

select plan(34);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000b1', 'authenticated', 'authenticated', 'sup@sf.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000b2', 'authenticated', 'authenticated', 'edu@sf.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000b3', 'authenticated', 'authenticated', 'vol@sf.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('21700000-0000-4000-8000-000000000001', 'Staff File Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('31700000-0000-4000-8000-000000000001', '21700000-0000-4000-8000-000000000001', 'Staff File Centre', 'SF-1', '3 Cabinet Way, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('41700000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000b1', 'Sup File', 'sup@sf.local'),
  ('41700000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000b2', 'Edu File', 'edu@sf.local'),
  ('41700000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-0000000000b3', 'Vol File', 'vol@sf.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('41700000-0000-4000-8000-000000000001', '31700000-0000-4000-8000-000000000001', 'supervisor', true),
  ('41700000-0000-4000-8000-000000000002', '31700000-0000-4000-8000-000000000001', 'rece', true),
  ('41700000-0000-4000-8000-000000000003', '31700000-0000-4000-8000-000000000001', 'volunteer', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('41700000-0000-4000-8000-000000000001', '31700000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('41700000-0000-4000-8000-000000000002', '31700000-0000-4000-8000-000000000001', extensions.crypt('7171', extensions.gen_salt('bf')));

-- ── the requirements are data ───────────────────────────────────────────────
select is(
  (select count(*) from public.staff_requirement where jurisdiction_code = 'CA-ON'),
  6::bigint,
  's53_what_a_staff_file_must_hold_is_jurisdiction_data'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000b1","role":"authenticated"}', true);
set local role authenticated;

select is(
  (select count(*) from public.staff_file_gaps('31700000-0000-4000-8000-000000000001')
   where full_name = 'Vol File' and requirement_key = 'first_aid_cpr'),
  0::bigint,
  's58_a_volunteer_is_never_in_ratio_so_never_needs_first_aid'
);

select is(
  (select count(*) from public.staff_file_gaps('31700000-0000-4000-8000-000000000001')
   where full_name = 'Vol File' and requirement_key in ('vsc', 'health_assessment')),
  2::bigint,
  's57_but_a_volunteer_does_need_a_police_check_and_a_health_assessment'
);

select is(
  (select count(*) from public.staff_file_gaps('31700000-0000-4000-8000-000000000001')
   where state = 'missing'),
  16::bigint,
  's53_an_empty_file_reports_every_absence'
);

-- ── the s. 60 arithmetic ────────────────────────────────────────────────────
select throws_like(
  $$select public.record_credential('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', 'vsc', (current_date - 30), null, (current_date - 40), null, null, null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  '%names the police service%',
  's60_a_vulnerable_sector_check_names_the_police_service'
);

select throws_like(
  $$select public.record_credential('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', 'vsc', (current_date - 30), null, null, 'Toronto Police Service', null, null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  '%date the police service conducted%',
  's60_and_the_date_it_was_actually_conducted'
);

select throws_like(
  $$select public.record_credential('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', 'vsc', (current_date - 30), null, (current_date - 300), 'Toronto Police Service', null, null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  '%more than six months old when it was obtained%',
  's60_a_stale_check_is_refused'
);

select throws_like(
  $$select public.record_credential('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', 'vsc', (current_date - 300), null, (current_date - 30), 'Toronto Police Service', null, null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  '%cannot have been conducted after it was obtained%',
  's60_and_so_is_a_check_from_the_future'
);

select lives_ok(
  $$select public.record_credential('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', 'vsc', (current_date - 30), (current_date + 3650), (current_date - 60), 'Toronto Police Service', null, null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  's60_a_good_check_is_recorded'
);

-- ten years was typed; five is what the regulation says, so five is what is stored
select is(
  (select expires_on from public.credential
   where person_id = '41700000-0000-4000-8000-000000000002' and credential_type = 'vsc'),
  (current_date - 30 + interval '5 years')::date,
  's60_the_fifth_anniversary_is_derived_not_typed'
);

select is(
  (select state from public.staff_file_gaps('31700000-0000-4000-8000-000000000001')
   where full_name = 'Edu File' and requirement_key = 'vsc'),
  'current',
  's60_and_the_gap_closes'
);

-- ── offence declarations ────────────────────────────────────────────────────
select throws_like(
  $$select public.record_credential('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', 'offence_declaration', current_date, null, null, null, null, null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  '%says which year it covers%',
  's61_an_offence_declaration_names_its_year'
);

-- the year the VSC was obtained needs no declaration; an earlier year does
select is(
  (select count(*) from public.offence_declaration_gaps('31700000-0000-4000-8000-000000000001')
   where full_name = 'Edu File' and missing_year = extract(year from current_date)::int),
  0::bigint,
  's61_the_year_of_a_vulnerable_sector_check_needs_no_declaration'
);

select lives_ok(
  $$select public.record_credential('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000003', 'offence_declaration', current_date, null, null, null, extract(year from current_date)::int, null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  's61_a_declaration_is_recorded_for_the_year_it_covers'
);

select is(
  (select expires_on from public.credential
   where person_id = '41700000-0000-4000-8000-000000000003' and credential_type = 'offence_declaration'),
  make_date(extract(year from current_date)::int, 12, 31),
  's61_a_declaration_runs_to_the_end_of_its_year'
);

select is(
  (select count(*) from public.offence_declaration_gaps('31700000-0000-4000-8000-000000000001')
   where full_name = 'Vol File'),
  0::bigint,
  's61_and_that_year_is_no_longer_a_gap'
);

-- ── first aid ───────────────────────────────────────────────────────────────
select throws_like(
  $$select public.record_credential('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', 'first_aid_cpr', (current_date - 30), null, null, null, null, null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  '%record the date this expires%',
  's58_first_aid_without_a_date_is_not_a_record'
);

select lives_ok(
  $$select public.record_credential('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', 'first_aid_cpr', (current_date - 1100), (current_date - 5), null, null, null, 'Canadian Red Cross', '41700000-0000-4000-8000-000000000001', '4242')$$,
  's58_an_expired_certificate_is_still_recorded'
);

select is(
  (select state from public.staff_file_gaps('31700000-0000-4000-8000-000000000001')
   where full_name = 'Edu File' and requirement_key = 'first_aid_cpr'),
  'expired',
  's58_and_the_file_says_it_has_expired'
);

-- ── the documents ───────────────────────────────────────────────────────────
select throws_like(
  $$select public.attach_staff_document('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', null, 'credential_evidence', 'somewhere/else/cert.pdf', 'cert.pdf', 'application/pdf', 1024, null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  '%and nowhere else%',
  's53_a_staff_document_lives_under_its_own_person'
);

select throws_like(
  $$select public.attach_staff_document('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000003', (select id from public.credential where person_id = '41700000-0000-4000-8000-000000000002' and credential_type = 'vsc'), 'credential_evidence', '31700000-0000-4000-8000-000000000001/41700000-0000-4000-8000-000000000003/a.pdf', 'a.pdf', 'application/pdf', 1024, null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  '%belongs to somebody else%',
  's53_a_document_cannot_be_filed_against_another_persons_credential'
);

select lives_ok(
  $$select public.attach_staff_document('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', (select id from public.credential where person_id = '41700000-0000-4000-8000-000000000002' and credential_type = 'vsc'), 'credential_evidence', '31700000-0000-4000-8000-000000000001/41700000-0000-4000-8000-000000000002/vsc.pdf', 'vsc-2026.pdf', 'application/pdf', 240512, null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  's53_the_certificate_is_attached_to_the_credential'
);

select is(
  (select has_document from public.staff_file_gaps('31700000-0000-4000-8000-000000000001')
   where full_name = 'Edu File' and requirement_key = 'vsc'),
  true,
  's53_and_the_file_shows_the_evidence_is_there'
);

-- ── a staff file is not a shared drive ──────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000b2","role":"authenticated"}', true);

select is(
  (select count(*) from public.staff_document),
  1::bigint,
  's53_you_can_read_your_own_file'
);

select throws_like(
  $$select public.attach_staff_document('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', null, 'other', '31700000-0000-4000-8000-000000000001/41700000-0000-4000-8000-000000000002/b.pdf', 'b.pdf', 'application/pdf', 100, null, '41700000-0000-4000-8000-000000000002', '7171')$$,
  '%kept by centre leadership%',
  's53_but_you_do_not_keep_it_yourself'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000b3","role":"authenticated"}', true);

select is(
  (select count(*) from public.staff_document),
  0::bigint,
  's53_a_colleague_never_reads_your_police_check'
);

-- the bucket agrees with the table
select is(
  (select count(*) from pg_policies
   where schemaname = 'storage' and tablename = 'objects' and policyname = 'evidence_read'
     and qual like '%has_role%'),
  1::bigint,
  's53_the_bucket_policy_is_scoped_to_leadership_and_the_subject'
);

-- ── superseding, never overwriting ──────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000b1","role":"authenticated"}', true);

select lives_ok(
  $$select public.supersede_staff_document((select id from public.staff_document limit 1), null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  's53_a_document_is_replaced_rather_than_edited'
);

select throws_like(
  $$select public.supersede_staff_document((select id from public.staff_document limit 1), null, '41700000-0000-4000-8000-000000000001', '4242')$$,
  '%already replaced%',
  's53_and_only_once'
);

reset role;

select throws_like(
  $$delete from public.staff_document where true$$,
  '%append-only%',
  's53_staff_documents_are_never_deleted'
);

-- ── a newer credential supersedes the last, and the history survives ────────
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000b1","role":"authenticated"}', true);

select lives_ok(
  $$select public.record_credential('31700000-0000-4000-8000-000000000001', '41700000-0000-4000-8000-000000000002', 'first_aid_cpr', current_date, (current_date + 1095), null, null, null, 'Canadian Red Cross, renewed', '41700000-0000-4000-8000-000000000001', '4242')$$,
  's58_the_renewal_is_recorded'
);

select is(
  (select count(*) from public.credential
   where person_id = '41700000-0000-4000-8000-000000000002'
     and credential_type = 'first_aid_cpr' and superseded_at is null),
  1::bigint,
  's58_only_one_first_aid_certificate_is_live'
);

select is(
  (select count(*) from public.credential
   where person_id = '41700000-0000-4000-8000-000000000002' and credential_type = 'first_aid_cpr'),
  2::bigint,
  's58_and_the_expired_one_is_still_in_the_file'
);

select is(
  (select state from public.staff_file_gaps('31700000-0000-4000-8000-000000000001')
   where full_name = 'Edu File' and requirement_key = 'first_aid_cpr'),
  'current',
  's58_the_file_reads_from_the_live_certificate'
);

select * from finish();
rollback;
