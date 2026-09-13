-- pgTAP: documents on the children's record (s. 72(1)) — who may attach one,
-- where the bytes must be, verification re-opening, replacement never
-- overwriting, the bucket's limits, and retention.
--
-- The cast: Amira's mother Hana may consent; her grandfather Omar can only view.
-- Ben belongs to another family. Cleo was discharged years ago.

begin;

create extension if not exists pgtap with schema extensions;

select plan(30);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '1c000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sup@rd.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1c000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rece@rd.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1c000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'hana@rd.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1c000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'omar@rd.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1c000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'ben@rd.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('2c000000-0000-4000-8000-000000000001', 'RD Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, timezone, opens_at, closes_at) values
  ('3c100000-0000-4000-8000-000000000001', '2c000000-0000-4000-8000-000000000001', 'RD Centre', 'RD-1', '1 RD St, Toronto', 'America/Toronto', '07:00', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('3c200000-0000-4000-8000-000000000001', '3c100000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('3c300000-0000-4000-8000-000000000001', '3c100000-0000-4000-8000-000000000001', '3c200000-0000-4000-8000-000000000001', 'Preschool room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('4c000000-0000-4000-8000-000000000001', '1c000000-0000-4000-8000-000000000001', 'Sup RD', 'sup@rd.local'),
  ('4c000000-0000-4000-8000-000000000002', '1c000000-0000-4000-8000-000000000002', 'Rece RD', 'rece@rd.local'),
  ('4c000000-0000-4000-8000-000000000003', '1c000000-0000-4000-8000-000000000003', 'Hana Haddad', 'hana@rd.local'),
  ('4c000000-0000-4000-8000-000000000004', '1c000000-0000-4000-8000-000000000004', 'Omar Haddad', 'omar@rd.local'),
  ('4c000000-0000-4000-8000-000000000005', '1c000000-0000-4000-8000-000000000005', 'Ben Parent', 'ben@rd.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('4c000000-0000-4000-8000-000000000001', '3c100000-0000-4000-8000-000000000001', 'supervisor', true),
  ('4c000000-0000-4000-8000-000000000002', '3c100000-0000-4000-8000-000000000001', 'rece', true),
  ('4c000000-0000-4000-8000-000000000003', '3c100000-0000-4000-8000-000000000001', 'family_adult', false),
  ('4c000000-0000-4000-8000-000000000004', '3c100000-0000-4000-8000-000000000001', 'family_adult', false),
  ('4c000000-0000-4000-8000-000000000005', '3c100000-0000-4000-8000-000000000001', 'family_adult', false);
insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('4c000000-0000-4000-8000-000000000001', '3c100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('4c000000-0000-4000-8000-000000000002', '3c100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('6c000000-0000-4000-8000-000000000001', '3c100000-0000-4000-8000-000000000001', 'Amira Haddad', '2022-04-01', '2024-01-08', '3c300000-0000-4000-8000-000000000001'),
  ('6c000000-0000-4000-8000-000000000002', '3c100000-0000-4000-8000-000000000001', 'Ben Lachance', '2022-06-01', '2024-01-08', '3c300000-0000-4000-8000-000000000001'),
  ('6c000000-0000-4000-8000-000000000003', '3c100000-0000-4000-8000-000000000001', 'Cleo Martin', '2017-02-01', '2019-01-07', '3c300000-0000-4000-8000-000000000001');

insert into public.household (id, centre_id, name) values
  ('5c000000-0000-4000-8000-000000000001', '3c100000-0000-4000-8000-000000000001', 'Haddad household'),
  ('5c000000-0000-4000-8000-000000000002', '3c100000-0000-4000-8000-000000000001', 'Lachance household');
insert into public.child_household (child_id, household_id, centre_id) values
  ('6c000000-0000-4000-8000-000000000001', '5c000000-0000-4000-8000-000000000001', '3c100000-0000-4000-8000-000000000001'),
  ('6c000000-0000-4000-8000-000000000002', '5c000000-0000-4000-8000-000000000002', '3c100000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('5c000000-0000-4000-8000-000000000001', '4c000000-0000-4000-8000-000000000003', '3c100000-0000-4000-8000-000000000001', 'parent', true, true),
  ('5c000000-0000-4000-8000-000000000001', '4c000000-0000-4000-8000-000000000004', '3c100000-0000-4000-8000-000000000001', 'grandparent', true, false),
  ('5c000000-0000-4000-8000-000000000002', '4c000000-0000-4000-8000-000000000005', '3c100000-0000-4000-8000-000000000001', 'parent', true, true);

-- the bytes land before the row
insert into storage.objects (bucket_id, name) values
  ('evidence', '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/application.jpg'),
  ('evidence', '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/application-signed.jpg'),
  ('evidence', '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/medication.pdf'),
  ('evidence', '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/medication-v2.pdf'),
  ('evidence', '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000003/cleo-application.pdf');

-- 1
select is(
  (select allowed_mime_types from storage.buckets where id = 'evidence'),
  array['application/pdf', 'image/jpeg', 'image/png'],
  's72_1_the_evidence_bucket_takes_pdf_jpeg_and_png_only'
);

-- ── as Hana, who may consent ────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1c000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;

-- 2
select lives_ok(
  $$select public.attach_record_document('6c000000-0000-4000-8000-000000000001', 'application',
      '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/application.jpg',
      'application.jpg', 'image/jpeg', 480000, 'Photo of the signed form')$$,
  's72_1_a_parent_attaches_the_signed_application_from_the_app'
);

-- 3
select is(
  (select uploaded_via from public.child_record_document
   where storage_path like '%/application.jpg'),
  'family',
  's72_1_the_record_says_the_family_attached_it'
);

-- 4
select is(
  (select evidence_path from public.child_record_item
   where child_id = '6c000000-0000-4000-8000-000000000001' and item_type = 'application'),
  '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/application.jpg',
  's72_1_the_record_item_points_at_its_document'
);

-- 5
select throws_ok(
  $$select public.attach_record_document('6c000000-0000-4000-8000-000000000001', 'identity',
      '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/never-arrived.pdf',
      'birth-certificate.pdf', 'application/pdf', 1000)$$,
  'the document has not finished uploading — try again',
  's72_1_a_row_never_points_at_bytes_that_never_arrived'
);

-- 6
select throws_ok(
  $$select public.attach_record_document('6c000000-0000-4000-8000-000000000001', 'identity',
      '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000002/sneaky.pdf',
      'sneaky.pdf', 'application/pdf', 1000)$$,
  'a record document lives at {centre}/child/{child}/… and nowhere else',
  's72_1_a_document_goes_in_its_own_childs_folder_and_nowhere_else'
);

-- 7
select throws_ok(
  $$select public.attach_record_document('6c000000-0000-4000-8000-000000000001', 'application',
      '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/application-signed.jpg',
      'application.txt', 'text/plain', 1000)$$,
  '23514',
  null,
  's72_1_a_record_document_is_a_pdf_or_an_image'
);

-- 8
select lives_ok(
  $$select public.attach_record_document('6c000000-0000-4000-8000-000000000001', 'application',
      '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/application-signed.jpg',
      'application-signed.jpg', 'image/jpeg', 510000, 'Clearer photo',
      (select id from public.child_record_document where storage_path like '%/application.jpg'))$$,
  's72_1_a_clearer_copy_replaces_the_first'
);

-- 9
select is(
  (select count(*)::integer from public.child_record_document
   where child_id = '6c000000-0000-4000-8000-000000000001' and item_type = 'application'),
  2,
  's72_1_and_the_replaced_one_is_kept_not_overwritten'
);

-- 10
select is(
  (select superseded_by from public.child_record_document where storage_path like '%/application.jpg'),
  (select id from public.child_record_document where storage_path like '%/application-signed.jpg'),
  's72_1_the_old_copy_says_what_replaced_it'
);

-- 11
select throws_ok(
  $$select public.attach_record_document('6c000000-0000-4000-8000-000000000001', 'application',
      '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/application.jpg',
      'again.jpg', 'image/jpeg', 1000, null,
      (select id from public.child_record_document where storage_path like '%/application.jpg'))$$,
  'this document has already been replaced',
  's72_1_a_replaced_document_is_replaced_once'
);

-- 12: the storage write policy lets a consenting parent into their own child's folder
select lives_ok(
  $$insert into storage.objects (bucket_id, name) values
      ('evidence', '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/care-instructions.jpg')$$,
  's72_1_a_consenting_parent_can_upload_into_their_childs_folder'
);

-- 13
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values
      ('evidence', '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000002/not-mine.jpg')$$,
  '42501',
  null,
  's72_1_but_not_into_another_familys'
);

-- 14
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values
      ('evidence', '3c100000-0000-4000-8000-000000000001/4c000000-0000-4000-8000-000000000003/cv.pdf')$$,
  '42501',
  null,
  's72_1_and_not_into_the_staff_files'
);

-- ── as Omar, who can see Amira's day but not consent for her ─────────────────
select set_config('request.jwt.claims', '{"sub":"1c000000-0000-4000-8000-000000000004","role":"authenticated"}', true);

-- 15
select throws_ok(
  $$select public.attach_record_document('6c000000-0000-4000-8000-000000000001', 'care_instructions',
      '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/care-instructions.jpg',
      'care.jpg', 'image/jpeg', 1000)$$,
  'only the centre or an adult who can consent for this child may add to the record',
  's72_1_an_adult_who_can_only_view_cannot_add_to_the_legal_record'
);

-- 16
select is(
  (select count(*)::integer from public.child_record_document where child_id = '6c000000-0000-4000-8000-000000000001'),
  2,
  's72_1_but_can_read_the_documents_on_their_grandchilds_record'
);

-- ── as Ben's parent, another family ─────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1c000000-0000-4000-8000-000000000005","role":"authenticated"}', true);

-- 17
select throws_ok(
  $$select public.attach_record_document('6c000000-0000-4000-8000-000000000001', 'care_instructions',
      '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/care-instructions.jpg',
      'care.jpg', 'image/jpeg', 1000)$$,
  'only the centre or an adult who can consent for this child may add to the record',
  's72_1_another_family_cannot_add_to_this_childs_record'
);

-- 18
select is(
  (select count(*)::integer from public.child_record_document where child_id = '6c000000-0000-4000-8000-000000000001'),
  0,
  's72_1_and_cannot_see_its_documents'
);

-- 19
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'evidence' and name like '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/%'),
  0,
  's72_1_nor_fetch_the_files'
);

-- ── as the RECE, with paper handed in at the door ───────────────────────────
select set_config('request.jwt.claims', '{"sub":"1c000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

-- 20
select lives_ok(
  $$select public.staff_record_item('6c000000-0000-4000-8000-000000000001', 'medication_instructions', 'provided', '{}'::jsonb,
      '4c000000-0000-4000-8000-000000000002', '4242')$$,
  'the_room_marks_the_medication_instructions_provided'
);

-- 21
select lives_ok(
  $$select public.attach_record_document('6c000000-0000-4000-8000-000000000001', 'medication_instructions',
      '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/medication.pdf',
      'medication-instructions.pdf', 'application/pdf', 220000, null, null,
      '4c000000-0000-4000-8000-000000000002', '4242')$$,
  's72_1_staff_attach_a_paper_form_with_their_pin'
);

-- 22
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'evidence' and name like '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/%'),
  5,
  's72_1_the_people_caring_for_a_child_can_open_their_record_documents'
);

-- ── verification re-opens ───────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1c000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

-- 23
select lives_ok(
  $$select public.verify_child_record('6c000000-0000-4000-8000-000000000001', '4c000000-0000-4000-8000-000000000001', '4242')$$,
  'the_supervisor_verifies_the_record'
);

-- 24
select isnt(
  (select verified_at from public.child_record_item
   where child_id = '6c000000-0000-4000-8000-000000000001' and item_type = 'medication_instructions'),
  null::timestamptz,
  'the_medication_instructions_are_verified'
);

-- 25
select lives_ok(
  $$select public.attach_record_document('6c000000-0000-4000-8000-000000000001', 'medication_instructions',
      '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000001/medication-v2.pdf',
      'medication-instructions-updated.pdf', 'application/pdf', 230000, 'Dose changed',
      (select id from public.child_record_document where storage_path like '%/medication.pdf'),
      '4c000000-0000-4000-8000-000000000001', '4242')$$,
  'an_updated_form_arrives'
);

-- 26
select is(
  (select verified_at from public.child_record_item
   where child_id = '6c000000-0000-4000-8000-000000000001' and item_type = 'medication_instructions'),
  null::timestamptz,
  's72_1_a_new_document_reopens_verification_because_it_is_not_what_was_verified'
);

-- ── past RLS ────────────────────────────────────────────────────────────────
reset role;

-- 27
select throws_ok(
  $$update public.child_record_document set note = 'edited' where storage_path like '%/medication-v2.pdf'$$,
  'a record document is never edited; attach a new one that replaces it',
  's72_1_a_record_document_is_never_edited'
);

-- ── retention (s. 72(5)) ────────────────────────────────────────────────────
insert into public.child_record_document (centre_id, child_id, item_type, storage_path, file_name, content_type, size_bytes, uploaded_by, uploaded_via)
values ('3c100000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000003', 'application',
        '3c100000-0000-4000-8000-000000000001/child/6c000000-0000-4000-8000-000000000003/cleo-application.pdf',
        'Cleo Martin - application.pdf', 'application/pdf', 90000, '4c000000-0000-4000-8000-000000000001', 'staff');
update public.child set discharge_date = (current_date - interval '4 years')::date
  where id = '6c000000-0000-4000-8000-000000000003';
select app.anonymise_child('6c000000-0000-4000-8000-000000000003');

-- 28
select is(
  (select file_name from public.child_record_document where child_id = '6c000000-0000-4000-8000-000000000003'),
  '[anonymised]',
  's72_5_an_anonymised_childs_documents_keep_no_name'
);

-- 29
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'evidence' and name like '%/child/6c000000-0000-4000-8000-000000000003/%'),
  0,
  's72_5_and_their_files_are_deleted'
);

-- 30
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'evidence' and name like '%/child/6c000000-0000-4000-8000-000000000001/%'),
  5,
  's72_5_while_every_other_childs_documents_are_untouched'
);

select * from finish();
rollback;
