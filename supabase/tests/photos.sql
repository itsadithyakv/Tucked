-- pgTAP: photos, and the consent families gave, enforced at capture AND at read.
--
-- The cast: Maya and Noah are siblings (one household). Liam's family declined
-- group photos. Ava's family agreed to everything, then withdraws group consent
-- mid-suite. Zoe's family has made no decision at all. Eli is discharged and
-- anonymised at the end. Kofi is Maya's other parent AND an educator here — the
-- dual-role adult whose family screen must not get the staff answer.

begin;

create extension if not exists pgtap with schema extensions;

select plan(37);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '1b000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rece@ph.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1b000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'maya@ph.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1b000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'liam@ph.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1b000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'ava@ph.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1b000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'zoe@ph.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1b000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'eli@ph.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('2b000000-0000-4000-8000-000000000001', 'PH Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, timezone, opens_at, closes_at) values
  ('3b100000-0000-4000-8000-000000000001', '2b000000-0000-4000-8000-000000000001', 'PH Centre', 'PH-1', '1 PH St, Toronto', 'America/Toronto', '07:00', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('3b200000-0000-4000-8000-000000000001', '3b100000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('3b300000-0000-4000-8000-000000000001', '3b100000-0000-4000-8000-000000000001', '3b200000-0000-4000-8000-000000000001', 'Preschool room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('4b000000-0000-4000-8000-000000000001', '1b000000-0000-4000-8000-000000000001', 'Rece PH', 'rece@ph.local'),
  ('4b000000-0000-4000-8000-000000000002', '1b000000-0000-4000-8000-000000000002', 'Maya Parent', 'maya@ph.local'),
  ('4b000000-0000-4000-8000-000000000003', '1b000000-0000-4000-8000-000000000003', 'Liam Parent', 'liam@ph.local'),
  ('4b000000-0000-4000-8000-000000000004', '1b000000-0000-4000-8000-000000000004', 'Ava Parent', 'ava@ph.local'),
  ('4b000000-0000-4000-8000-000000000005', '1b000000-0000-4000-8000-000000000005', 'Zoe Parent', 'zoe@ph.local'),
  ('4b000000-0000-4000-8000-000000000006', '1b000000-0000-4000-8000-000000000006', 'Eli Parent', 'eli@ph.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('4b000000-0000-4000-8000-000000000001', '3b100000-0000-4000-8000-000000000001', 'rece', true),
  ('4b000000-0000-4000-8000-000000000002', '3b100000-0000-4000-8000-000000000001', 'family_adult', false),
  ('4b000000-0000-4000-8000-000000000003', '3b100000-0000-4000-8000-000000000001', 'family_adult', false),
  ('4b000000-0000-4000-8000-000000000004', '3b100000-0000-4000-8000-000000000001', 'family_adult', false),
  ('4b000000-0000-4000-8000-000000000005', '3b100000-0000-4000-8000-000000000001', 'family_adult', false),
  ('4b000000-0000-4000-8000-000000000006', '3b100000-0000-4000-8000-000000000001', 'family_adult', false);
insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('4b000000-0000-4000-8000-000000000001', '3b100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('6b000000-0000-4000-8000-000000000001', '3b100000-0000-4000-8000-000000000001', 'Maya Osei', '2022-03-01', '2024-01-08', '3b300000-0000-4000-8000-000000000001'),
  ('6b000000-0000-4000-8000-000000000002', '3b100000-0000-4000-8000-000000000001', 'Liam Tremblay', '2022-05-01', '2024-01-08', '3b300000-0000-4000-8000-000000000001'),
  ('6b000000-0000-4000-8000-000000000003', '3b100000-0000-4000-8000-000000000001', 'Ava Chen', '2022-07-01', '2024-01-08', '3b300000-0000-4000-8000-000000000001'),
  ('6b000000-0000-4000-8000-000000000004', '3b100000-0000-4000-8000-000000000001', 'Zoe Okafor', '2022-09-01', '2024-01-08', '3b300000-0000-4000-8000-000000000001'),
  ('6b000000-0000-4000-8000-000000000005', '3b100000-0000-4000-8000-000000000001', 'Noah Osei', '2022-03-01', '2024-01-08', '3b300000-0000-4000-8000-000000000001'),
  ('6b000000-0000-4000-8000-000000000006', '3b100000-0000-4000-8000-000000000001', 'Eli Brandt', '2018-02-01', '2020-01-06', '3b300000-0000-4000-8000-000000000001');

insert into public.household (id, centre_id, name) values
  ('5b000000-0000-4000-8000-000000000001', '3b100000-0000-4000-8000-000000000001', 'Osei household'),
  ('5b000000-0000-4000-8000-000000000002', '3b100000-0000-4000-8000-000000000001', 'Tremblay household'),
  ('5b000000-0000-4000-8000-000000000003', '3b100000-0000-4000-8000-000000000001', 'Chen household'),
  ('5b000000-0000-4000-8000-000000000004', '3b100000-0000-4000-8000-000000000001', 'Okafor household'),
  ('5b000000-0000-4000-8000-000000000005', '3b100000-0000-4000-8000-000000000001', 'Brandt household');
insert into public.child_household (child_id, household_id, centre_id) values
  ('6b000000-0000-4000-8000-000000000001', '5b000000-0000-4000-8000-000000000001', '3b100000-0000-4000-8000-000000000001'),
  ('6b000000-0000-4000-8000-000000000005', '5b000000-0000-4000-8000-000000000001', '3b100000-0000-4000-8000-000000000001'),
  ('6b000000-0000-4000-8000-000000000002', '5b000000-0000-4000-8000-000000000002', '3b100000-0000-4000-8000-000000000001'),
  ('6b000000-0000-4000-8000-000000000003', '5b000000-0000-4000-8000-000000000003', '3b100000-0000-4000-8000-000000000001'),
  ('6b000000-0000-4000-8000-000000000004', '5b000000-0000-4000-8000-000000000004', '3b100000-0000-4000-8000-000000000001'),
  ('6b000000-0000-4000-8000-000000000006', '5b000000-0000-4000-8000-000000000005', '3b100000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('5b000000-0000-4000-8000-000000000001', '4b000000-0000-4000-8000-000000000002', '3b100000-0000-4000-8000-000000000001', 'parent', true, true),
  ('5b000000-0000-4000-8000-000000000002', '4b000000-0000-4000-8000-000000000003', '3b100000-0000-4000-8000-000000000001', 'parent', true, true),
  ('5b000000-0000-4000-8000-000000000003', '4b000000-0000-4000-8000-000000000004', '3b100000-0000-4000-8000-000000000001', 'parent', true, true),
  ('5b000000-0000-4000-8000-000000000004', '4b000000-0000-4000-8000-000000000005', '3b100000-0000-4000-8000-000000000001', 'parent', true, true),
  ('5b000000-0000-4000-8000-000000000005', '4b000000-0000-4000-8000-000000000006', '3b100000-0000-4000-8000-000000000001', 'parent', true, true);

-- Kofi: Maya and Noah's other parent, who also works in the preschool room
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '1b000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'kofi@ph.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());
insert into public.person (id, auth_user_id, full_name, email) values
  ('4b000000-0000-4000-8000-000000000007', '1b000000-0000-4000-8000-000000000007', 'Kofi Osei', 'kofi@ph.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('4b000000-0000-4000-8000-000000000007', '3b100000-0000-4000-8000-000000000001', 'rece', true),
  ('4b000000-0000-4000-8000-000000000007', '3b100000-0000-4000-8000-000000000001', 'family_adult', false);
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('5b000000-0000-4000-8000-000000000001', '4b000000-0000-4000-8000-000000000007', '3b100000-0000-4000-8000-000000000001', 'parent', true, true);

-- Zoe's family has decided nothing, which is not a yes.
insert into public.consent (centre_id, child_id, consent_type, purpose, status, granted_by) values
  ('3b100000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000001', 'photo_internal', 'Photos shared with you in the app', 'granted', '4b000000-0000-4000-8000-000000000002'),
  ('3b100000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000001', 'photo_group', 'Your child appearing in group photos', 'granted', '4b000000-0000-4000-8000-000000000002'),
  ('3b100000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000005', 'photo_internal', 'Photos shared with you in the app', 'granted', '4b000000-0000-4000-8000-000000000002'),
  ('3b100000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000005', 'photo_group', 'Your child appearing in group photos', 'declined', '4b000000-0000-4000-8000-000000000002'),
  ('3b100000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000002', 'photo_internal', 'Photos shared with you in the app', 'granted', '4b000000-0000-4000-8000-000000000003'),
  ('3b100000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000002', 'photo_group', 'Your child appearing in group photos', 'declined', '4b000000-0000-4000-8000-000000000003'),
  ('3b100000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000003', 'photo_internal', 'Photos shared with you in the app', 'granted', '4b000000-0000-4000-8000-000000000004'),
  ('3b100000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000003', 'photo_group', 'Your child appearing in group photos', 'granted', '4b000000-0000-4000-8000-000000000004'),
  ('3b100000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000006', 'photo_internal', 'Photos shared with you in the app', 'granted', '4b000000-0000-4000-8000-000000000006'),
  ('3b100000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000006', 'photo_group', 'Your child appearing in group photos', 'granted', '4b000000-0000-4000-8000-000000000006');

-- The device uploads before it records. Photo 09 never arrives. The last object
-- sits at a path that is not a uuid, which used to crash every read in the bucket.
insert into storage.objects (bucket_id, name) values
  ('photos', '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000001/full.jpg'),
  ('photos', '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000002/full.jpg'),
  ('photos', '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000003/full.jpg'),
  ('photos', '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000004/full.jpg'),
  ('photos', '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000007/full.jpg'),
  ('photos', '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000008/full.jpg'),
  ('photos', 'not-a-uuid/stray.jpg');

-- ── as the RECE: capture ────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

-- 1
select lives_ok(
  $$select public.record_photo('3b100000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000001', array['6b000000-0000-4000-8000-000000000001']::uuid[], now(), 2560, 1920, 700000, null, '4b000000-0000-4000-8000-000000000001', '4242')$$,
  'photo_a_solo_photo_of_a_child_whose_family_agreed'
);

-- 2
select is(
  (select storage_path from public.photo where id = '7b000000-0000-4000-8000-000000000001'),
  '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000001/full.jpg',
  'photo_lives_at_the_path_its_own_id_decides'
);

-- 3
select throws_ok(
  $$select public.record_photo('3b100000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000009', array['6b000000-0000-4000-8000-000000000001']::uuid[], now(), null, null, null, null, '4b000000-0000-4000-8000-000000000001', '4242')$$,
  'the photo has not finished uploading — try again',
  'photo_a_row_never_points_at_bytes_that_never_arrived'
);

-- 4
select throws_ok(
  $$select public.record_photo('3b100000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000009', '{}'::uuid[], now(), null, null, null, null, '4b000000-0000-4000-8000-000000000001', '4242')$$,
  'say who is in the photo — a photo with nobody tagged reaches no family',
  'photo_a_photo_names_who_is_in_it'
);

-- 5
select throws_like(
  $$select public.record_photo('3b100000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000005', array['6b000000-0000-4000-8000-000000000004']::uuid[], now(), null, null, null, null, '4b000000-0000-4000-8000-000000000001', '4242')$$,
  '%Zoe''s family has not agreed to photos in the app%',
  'photo_no_decision_on_file_is_not_a_yes'
);

-- 6
select throws_like(
  $$select public.record_photo('3b100000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000006', array['6b000000-0000-4000-8000-000000000001','6b000000-0000-4000-8000-000000000002']::uuid[], now(), null, null, null, null, '4b000000-0000-4000-8000-000000000001', '4242')$$,
  '%Liam''s family has not agreed to group photos%',
  'photo_the_educator_hears_who_cannot_be_in_a_group_photo_by_name'
);

-- 7
select lives_ok(
  $$select public.record_photo('3b100000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000003', array['6b000000-0000-4000-8000-000000000002']::uuid[], now(), null, null, null, null, '4b000000-0000-4000-8000-000000000001', '4242')$$,
  'photo_declining_group_photos_still_allows_a_photo_on_their_own'
);

-- 8
select lives_ok(
  $$select public.record_photo('3b100000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000004', array['6b000000-0000-4000-8000-000000000001','6b000000-0000-4000-8000-000000000005']::uuid[], now(), null, null, null, null, '4b000000-0000-4000-8000-000000000001', '4242')$$,
  'photo_two_siblings_are_not_a_group_photo'
);

-- 9
select lives_ok(
  $$select public.record_photo('3b100000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000002', array['6b000000-0000-4000-8000-000000000001','6b000000-0000-4000-8000-000000000003']::uuid[], now(), null, null, null, 'Building the block tower', '4b000000-0000-4000-8000-000000000001', '4242')$$,
  'photo_a_group_photo_when_every_family_agreed'
);

-- 10
select is(
  (select count(*)::integer from public.care_log
   where log_type = 'photo' and payload ->> 'photo_id' = '7b000000-0000-4000-8000-000000000002'),
  2,
  'photo_each_child_in_it_gets_a_line_in_their_day'
);

-- 11
select lives_ok(
  $$select public.record_photo('3b100000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000007', array['6b000000-0000-4000-8000-000000000006']::uuid[], now(), null, null, null, null, '4b000000-0000-4000-8000-000000000001', '4242')$$,
  'photo_eli_on_his_own'
);

-- 12
select lives_ok(
  $$select public.record_photo('3b100000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000008', array['6b000000-0000-4000-8000-000000000001','6b000000-0000-4000-8000-000000000006']::uuid[], now(), null, null, null, null, '4b000000-0000-4000-8000-000000000001', '4242')$$,
  'photo_maya_and_eli_together'
);

-- ── as Maya's parent: read ──────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

-- 13
select is(
  (select count(*)::integer from public.photo where id in (
    '7b000000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000002',
    '7b000000-0000-4000-8000-000000000004', '7b000000-0000-4000-8000-000000000008')),
  4,
  'photo_a_family_sees_their_own_childs_photos_including_group_ones'
);

-- 14
select is(
  (select count(*)::integer from public.photo where id = '7b000000-0000-4000-8000-000000000003'),
  0,
  'photo_a_family_never_sees_another_familys_solo_photo'
);

-- 15
select is(
  (select count(*)::integer from public.photo_subject where photo_id = '7b000000-0000-4000-8000-000000000002'),
  1,
  'photo_a_family_sees_which_child_is_theirs_not_who_else_is_tagged'
);

-- 16
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'photos' and name = '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000002/full.jpg'),
  1,
  'photo_the_file_follows_the_same_rule_as_the_row'
);

-- 17
select lives_ok(
  $$select count(*) from storage.objects where bucket_id = 'photos'$$,
  'photo_a_path_that_is_not_a_uuid_no_longer_breaks_every_read'
);

-- 18
select throws_ok(
  $$select public.record_photo('3b100000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000009', array['6b000000-0000-4000-8000-000000000001']::uuid[], now(), null, null, null, null, '4b000000-0000-4000-8000-000000000002', '4242')$$,
  'not authorised for this centre',
  'photo_a_family_adult_cannot_record_a_photo'
);

-- ── as Liam's parent ────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

-- 19
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'photos' and name = '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000002/full.jpg'),
  0,
  'photo_another_family_cannot_fetch_the_file_either'
);

-- ── Ava's family withdraws group consent ────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000004","role":"authenticated"}', true);

-- 20
select lives_ok(
  $$select public.give_consent('6b000000-0000-4000-8000-000000000003', 'photo_group', 'Your child appearing in group photos', 'declined')$$,
  'photo_a_family_withdraws_group_consent'
);

-- 21
select is(
  (select count(*)::integer from public.photo where id = '7b000000-0000-4000-8000-000000000002'),
  1,
  'photo_their_own_family_still_sees_the_group_photo'
);

select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

-- 22
select is(
  (select count(*)::integer from public.photo where id = '7b000000-0000-4000-8000-000000000002'),
  0,
  'photo_and_it_leaves_every_other_familys_gallery_at_once'
);

-- 23
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'photos' and name = '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000002/full.jpg'),
  0,
  'photo_and_the_file_with_it'
);

-- ── as the RECE: taking one down ────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

-- 24
select throws_ok(
  $$select public.withdraw_photo('7b000000-0000-4000-8000-000000000001', '  ', '4b000000-0000-4000-8000-000000000001', '4242')$$,
  'say why it is coming down — the wrong child tagged, a family asked, …',
  'photo_a_withdrawal_says_why'
);

-- 25
select lives_ok(
  $$select public.withdraw_photo('7b000000-0000-4000-8000-000000000001', 'the wrong child was tagged', '4b000000-0000-4000-8000-000000000001', '4242')$$,
  'photo_an_educator_takes_a_photo_down'
);

-- 26
select throws_ok(
  $$select public.withdraw_photo('7b000000-0000-4000-8000-000000000001', 'again', '4b000000-0000-4000-8000-000000000001', '4242')$$,
  'this photo is already withdrawn',
  'photo_a_photo_is_withdrawn_once'
);

select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

-- 27
select is(
  (select count(*)::integer from public.photo where id = '7b000000-0000-4000-8000-000000000001'),
  0,
  'photo_a_withdrawn_photo_is_gone_from_the_family'
);

-- ── past RLS ────────────────────────────────────────────────────────────────
reset role;

-- 28
select throws_ok(
  $$update public.photo set caption = 'edited' where id = '7b000000-0000-4000-8000-000000000004'$$,
  'a photo is never edited; withdraw it and take another',
  'photo_a_photo_is_never_edited'
);

-- 29: Maya's photos today are 01 (withdrawn), 02 (hidden — Ava withdrew group
-- consent), 04 and 08. The story promises the two her family can open.
select alike(
  app.story_compose('6b000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date),
  '%2 new photos%',
  'story_counts_only_the_photos_the_family_can_open'
);

-- ── retention ───────────────────────────────────────────────────────────────
update public.child set discharge_date = (current_date - interval '4 years')::date
  where id = '6b000000-0000-4000-8000-000000000006';

-- 30
select lives_ok(
  $$select app.anonymise_child('6b000000-0000-4000-8000-000000000006')$$,
  'photo_retention_anonymises_a_child_in_photos'
);

-- 31
select is(
  (select count(*)::integer from public.photo
   where id in ('7b000000-0000-4000-8000-000000000007', '7b000000-0000-4000-8000-000000000008')
     and withdrawn_at is not null),
  2,
  'photo_every_photo_the_child_is_in_is_withdrawn_group_photos_too'
);

-- 32
select is(
  (select withdrawn_at from public.photo where id = '7b000000-0000-4000-8000-000000000004'),
  null::timestamptz,
  'photo_photos_without_that_child_are_untouched'
);

-- 33
select is(
  (select count(*)::integer from storage.objects
   where bucket_id = 'photos' and name in (
     '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000007/full.jpg',
     '3b100000-0000-4000-8000-000000000001/p/7b000000-0000-4000-8000-000000000008/full.jpg')),
  0,
  'photo_and_their_files_are_deleted'
);

-- ── a parent who also works here: the family answer, not the staff one ─────
-- By now Maya's photos are 01 (taken down), 02 (hidden: Ava's family withdrew
-- group consent), 04 (live, with her brother) and 08 (withdrawn with Eli).
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000007","role":"authenticated"}', true);

-- 34
select is(
  (select count(*)::integer from public.photo where id in (
    '7b000000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000002',
    '7b000000-0000-4000-8000-000000000008')),
  3,
  'photo_a_plain_select_gives_a_dual_role_parent_the_staff_answer'
);

-- 35
select is(
  (select count(*)::integer from public.family_photos(
    '6b000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date)),
  1,
  'photo_family_photos_gives_the_family_answer_instead'
);

-- 36
select is(
  (select count(*)::integer from public.family_photos(
    '6b000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date) f
   where f.id in ('7b000000-0000-4000-8000-000000000001', '7b000000-0000-4000-8000-000000000002',
                  '7b000000-0000-4000-8000-000000000008')),
  0,
  'photo_so_no_withdrawn_or_consent_hidden_photo_reaches_their_family_screen'
);

-- 37
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select is(
  (select count(*)::integer from public.family_photos(
    '6b000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date)),
  0,
  'photo_another_family_asking_about_a_child_that_is_not_theirs_gets_nothing'
);

select * from finish();
rollback;
