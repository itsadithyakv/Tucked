-- pgTAP: the documents that live on the premises. The load-bearing rules: the
-- list is of what is MISSING, not what happens to be there; a document is
-- superseded rather than overwritten, so the report an advisor saw last year
-- is still that report; the whole room team can read them, because "on the
-- premises" means available to the people on the premises; and the bucket path
-- is parsed safely, because a policy that throws takes the query down with it.

begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000d7', 'authenticated', 'authenticated', 'sup@cd.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000d8', 'authenticated', 'authenticated', 'edu@cd.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000d9', 'authenticated', 'authenticated', 'parent@cd.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('22200000-0000-4000-8000-000000000001', 'Premises Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('32200000-0000-4000-8000-000000000001', '22200000-0000-4000-8000-000000000001', 'Premises Centre', 'CD-1', '6 Cupboard Court, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('42200000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000d7', 'Sup Premises', 'sup@cd.local'),
  ('42200000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000d8', 'Edu Premises', 'edu@cd.local'),
  ('42200000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-0000000000d9', 'Parent Premises', 'parent@cd.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('42200000-0000-4000-8000-000000000001', '32200000-0000-4000-8000-000000000001', 'supervisor', true),
  ('42200000-0000-4000-8000-000000000002', '32200000-0000-4000-8000-000000000001', 'rece', true),
  ('42200000-0000-4000-8000-000000000003', '32200000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('42200000-0000-4000-8000-000000000001', '32200000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('42200000-0000-4000-8000-000000000002', '32200000-0000-4000-8000-000000000001', extensions.crypt('7171', extensions.gen_salt('bf')));

-- ── the path parser never throws ────────────────────────────────────────────
-- The old policies cast split_part(name,'/',2) straight to uuid. A path whose
-- second segment is the word "centre" — or anything else — raised, and an RLS
-- policy that raises takes the query with it rather than returning no rows.
select is(
  app.path_uuid('32200000-0000-4000-8000-000000000001/centre/report.pdf', 2),
  null,
  'premises_a_non_uuid_path_segment_parses_to_null_rather_than_throwing'
);

select is(
  app.path_uuid('32200000-0000-4000-8000-000000000001/centre/report.pdf', 1),
  '32200000-0000-4000-8000-000000000001'::uuid,
  'premises_and_a_real_one_still_parses'
);

select is(
  app.path_uuid('nonsense', 1),
  null,
  'premises_so_does_a_path_that_is_not_a_path_at_all'
);

-- ── the list is of what is missing ──────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000d7","role":"authenticated"}', true);
set local role authenticated;

select is(
  (select count(*) from public.centre_document_gaps('32200000-0000-4000-8000-000000000001')),
  6::bigint,
  'premises_six_documents_are_required_on_the_premises'
);

select is(
  (select count(*) from public.centre_document_gaps('32200000-0000-4000-8000-000000000001')
   where state = 'missing'),
  6::bigint,
  'premises_an_empty_cupboard_reports_every_absence'
);

select is(
  (select count(*) from public.centre_document_gaps('32200000-0000-4000-8000-000000000001')
   where kind = 'floor_plan'),
  0::bigint,
  'premises_a_document_that_is_not_required_is_not_a_gap'
);

-- ── attaching ───────────────────────────────────────────────────────────────
select throws_like(
  $$select public.attach_centre_document('32200000-0000-4000-8000-000000000001', 'fire_inspection', 'Fire inspection', 'Toronto Fire Services', current_date, 'TFS-2026-1', null, 'somewhere/else/report.pdf', 'report.pdf', 'application/pdf', 1024, null, '42200000-0000-4000-8000-000000000001', '4242')$$,
  '%and nowhere else%',
  'premises_a_document_lives_under_its_own_centre'
);

select throws_like(
  $$select public.attach_centre_document('32200000-0000-4000-8000-000000000001', 'vibes_report', 'Vibes', null, current_date, null, null, '32200000-0000-4000-8000-000000000001/centre/a.pdf', 'a.pdf', 'application/pdf', 1024, null, '42200000-0000-4000-8000-000000000001', '4242')$$,
  '%no document kind "vibes_report"%',
  'premises_the_kinds_are_jurisdiction_data'
);

select throws_like(
  $$select public.attach_centre_document('32200000-0000-4000-8000-000000000001', 'fire_inspection', 'Fire inspection', 'Toronto Fire Services', (current_date + 30), null, null, '32200000-0000-4000-8000-000000000001/centre/b.pdf', 'b.pdf', 'application/pdf', 1024, null, '42200000-0000-4000-8000-000000000001', '4242')$$,
  '%issued in the future%',
  'premises_an_inspection_cannot_have_happened_next_month'
);

select lives_ok(
  $$select public.attach_centre_document('32200000-0000-4000-8000-000000000001', 'fire_inspection', 'Annual fire inspection', 'Toronto Fire Services', (current_date - 30), 'TFS-2026-4417', null, '32200000-0000-4000-8000-000000000001/centre/fire-2026.pdf', 'fire-inspection-2026.pdf', 'application/pdf', 184000, 'No deficiencies.', '42200000-0000-4000-8000-000000000001', '4242')$$,
  'premises_the_fire_inspection_is_filed'
);

select is(
  (select state from public.centre_document_gaps('32200000-0000-4000-8000-000000000001')
   where kind = 'fire_inspection'),
  'current',
  'premises_and_the_gap_closes'
);

-- an old one is out of date rather than quietly acceptable
select lives_ok(
  $$select public.attach_centre_document('32200000-0000-4000-8000-000000000001', 'public_health_inspection', 'Public health inspection', 'Toronto Public Health', (current_date - 500), 'TPH-2025-9', null, '32200000-0000-4000-8000-000000000001/centre/tph-2025.pdf', 'tph-2025.pdf', 'application/pdf', 90000, null, '42200000-0000-4000-8000-000000000001', '4242')$$,
  'premises_last_years_public_health_report_is_filed'
);

select is(
  (select state from public.centre_document_gaps('32200000-0000-4000-8000-000000000001')
   where kind = 'public_health_inspection'),
  'out_of_date',
  'premises_but_a_report_older_than_its_renewal_period_says_so'
);

-- an expiring certificate is flagged before it lapses
select lives_ok(
  $$select public.attach_centre_document('32200000-0000-4000-8000-000000000001', 'insurance', 'Liability insurance', 'Northbridge', (current_date - 300), 'POL-99', (current_date + 20), '32200000-0000-4000-8000-000000000001/centre/insurance.pdf', 'insurance.pdf', 'application/pdf', 40000, null, '42200000-0000-4000-8000-000000000001', '4242')$$,
  'premises_the_insurance_certificate_is_filed'
);

select is(
  (select state from public.centre_document_gaps('32200000-0000-4000-8000-000000000001')
   where kind = 'insurance'),
  'expiring_soon',
  'premises_and_is_flagged_before_it_lapses_not_after'
);

-- ── superseded, never overwritten ───────────────────────────────────────────
select lives_ok(
  $$select public.attach_centre_document('32200000-0000-4000-8000-000000000001', 'fire_inspection', 'Annual fire inspection', 'Toronto Fire Services', (current_date - 2), 'TFS-2026-5001', null, '32200000-0000-4000-8000-000000000001/centre/fire-2026b.pdf', 'fire-inspection-2026-follow-up.pdf', 'application/pdf', 190000, 'Deficiency from last time cleared.', '42200000-0000-4000-8000-000000000001', '4242')$$,
  'premises_a_newer_report_replaces_the_last'
);

select is(
  (select count(*) from public.centre_document
   where kind = 'fire_inspection' and superseded_at is null),
  1::bigint,
  'premises_only_one_fire_inspection_is_live'
);

select is(
  (select count(*) from public.centre_document where kind = 'fire_inspection'),
  2::bigint,
  'premises_and_the_one_the_advisor_saw_last_time_is_still_there'
);

select is(
  (select title from public.centre_document_gaps('32200000-0000-4000-8000-000000000001')
   where kind = 'fire_inspection'),
  'Annual fire inspection',
  'premises_the_gap_list_reads_from_the_live_one'
);

-- ── who can see the cupboard ────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000d8","role":"authenticated"}', true);

select is(
  (select count(*) from public.centre_document),
  4::bigint,
  'premises_on_the_premises_means_the_room_team_can_read_them_too'
);

select throws_like(
  $$select public.attach_centre_document('32200000-0000-4000-8000-000000000001', 'licence', 'Licence', 'Ministry', current_date, null, null, '32200000-0000-4000-8000-000000000001/centre/lic.pdf', 'lic.pdf', 'application/pdf', 1000, null, '42200000-0000-4000-8000-000000000002', '7171')$$,
  '%kept by centre leadership%',
  'premises_but_an_educator_does_not_file_them'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000d9","role":"authenticated"}', true);

select is(
  (select count(*) from public.centre_document),
  0::bigint,
  'premises_and_a_family_never_sees_the_insurance_certificate'
);

-- ── nothing vanishes ────────────────────────────────────────────────────────
reset role;

select throws_like(
  $$delete from public.centre_document where true$$,
  '%append-only%',
  'premises_documents_are_never_deleted'
);

select * from finish();
rollback;
