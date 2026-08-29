-- pgTAP: stories, Now/Later notifications, messaging audiences, credentials,
-- retention clocks.

begin;

create extension if not exists pgtap with schema extensions;

select plan(14);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '16000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sup@fs.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '16000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent@fs.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '16000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'other@fs.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('26000000-0000-4000-8000-000000000001', 'FS Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('30100000-0000-4000-8000-000000000001', '26000000-0000-4000-8000-000000000001', 'FS Centre', 'FS-1', '1 FS St, Toronto', '07:30', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('30200000-0000-4000-8000-000000000001', '30100000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('30300000-0000-4000-8000-000000000001', '30100000-0000-4000-8000-000000000001', '30200000-0000-4000-8000-000000000001', 'Preschool room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('46000000-0000-4000-8000-000000000001', '16000000-0000-4000-8000-000000000001', 'Sup FS', 'sup@fs.local'),
  ('46000000-0000-4000-8000-000000000002', '16000000-0000-4000-8000-000000000002', 'Parent FS', 'parent@fs.local'),
  ('46000000-0000-4000-8000-000000000003', '16000000-0000-4000-8000-000000000003', 'Other FS', 'other@fs.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('46000000-0000-4000-8000-000000000001', '30100000-0000-4000-8000-000000000001', 'supervisor', true),
  ('46000000-0000-4000-8000-000000000002', '30100000-0000-4000-8000-000000000001', 'family_adult', false),
  ('46000000-0000-4000-8000-000000000003', '30100000-0000-4000-8000-000000000001', 'family_adult', false);
insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('46000000-0000-4000-8000-000000000001', '30100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('66000000-0000-4000-8000-000000000001', '30100000-0000-4000-8000-000000000001', 'FS Child', '2022-06-01', '2026-01-05', '30300000-0000-4000-8000-000000000001');
insert into public.household (id, centre_id, name) values
  ('56000000-0000-4000-8000-000000000001', '30100000-0000-4000-8000-000000000001', 'FS Household');
insert into public.child_household (child_id, household_id, centre_id) values
  ('66000000-0000-4000-8000-000000000001', '56000000-0000-4000-8000-000000000001', '30100000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_message) values
  ('56000000-0000-4000-8000-000000000001', '46000000-0000-4000-8000-000000000002', '30100000-0000-4000-8000-000000000001', 'parent', true, true);

-- ── story publish + notifications ───────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"16000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$select public.publish_story('66000000-0000-4000-8000-000000000001', current_date,
      'We spent the morning outside — the leaf pile was a hit. Lunch went well, and rest time was quiet.',
      'Lovely day. Ask about the leaf fort.',
      '46000000-0000-4000-8000-000000000001', '4242')$$,
  'story_published_at_pickup'
);

select is(
  (select count(*) from public.notification where event_type = 'story' and channel = 'later'),
  1::bigint,
  'story_creates_one_later_notification_per_adult'
);

select lives_ok(
  $$select public.publish_story('66000000-0000-4000-8000-000000000001', current_date,
      'updated draft', 'Lovely day. Ask about the leaf fort.',
      '46000000-0000-4000-8000-000000000001', '4242')$$,
  'story_republish_is_idempotent'
);

select is(
  (select count(*) from public.notification where event_type = 'story'),
  1::bigint,
  'exactly_one_story_push_per_day'
);

select is(
  (select count(*) from public.create_now_alert('66000000-0000-4000-8000-000000000001', 'illness_sent_home',
     'FS Child has a fever of 38.9°C', 'Please call FS Centre at (416) 555-0100 to arrange pickup.',
     '46000000-0000-4000-8000-000000000001', '4242')),
  1::bigint,
  'now_alert_reaches_every_viewing_adult'
);

-- ── as the parent ───────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"16000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select is(
  (select count(*) from public.story),
  1::bigint,
  'parent_sees_published_story'
);

select lives_ok(
  $$select public.acknowledge_notification((select id from public.notification where channel = 'now' and recipient_person_id = '46000000-0000-4000-8000-000000000002'))$$,
  'now_alert_acknowledged_by_recipient'
);

select lives_ok(
  $$insert into public.message_thread (centre_id, child_id, audience, created_by)
    values ('30100000-0000-4000-8000-000000000001', '66000000-0000-4000-8000-000000000001', 'supervisor', '46000000-0000-4000-8000-000000000002')$$,
  'parent_starts_thread_choosing_supervisor_audience'
);

select lives_ok(
  $$insert into public.message (centre_id, thread_id, sender_person_id, body)
    values ('30100000-0000-4000-8000-000000000001',
            (select id from public.message_thread limit 1),
            '46000000-0000-4000-8000-000000000002',
            'Maya will be picked up by her grandmother today.')$$,
  'parent_sends_message'
);

-- ── the unrelated adult sees nothing ────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"16000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select is((select count(*) from public.story), 0::bigint, 'unrelated_adult_sees_no_stories');
select is((select count(*) from public.message_thread), 0::bigint, 'unrelated_adult_sees_no_threads');
select is(
  (select count(*) from public.notification),
  0::bigint,
  'unrelated_adult_has_no_notifications'
);

-- ── credentials + retention (as supervisor / owner) ─────────────────────────
select set_config('request.jwt.claims', '{"sub":"16000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$insert into public.credential (centre_id, person_id, credential_type, issued_on, expires_on, recorded_by)
    values ('30100000-0000-4000-8000-000000000001', '46000000-0000-4000-8000-000000000001', 'vsc',
            (current_date - interval '4 years 11 months')::date, (current_date + 30)::date,
            '46000000-0000-4000-8000-000000000001')$$,
  's60_supervisor_records_vsc'
);

reset role;

select is(
  (select expiry_state from public.credential_status
   where credential_type = 'vsc' and centre_id = '30100000-0000-4000-8000-000000000001'),
  'expiring_soon',
  's60_vsc_five_year_renewal_flagged'
);

select * from finish();
rollback;
