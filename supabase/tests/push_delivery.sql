-- pgTAP: push delivery. The rule about WHICH notifications reach a phone is a
-- product promise — every Now alert, and of the Later feed only the daily
-- story, at most one per person per day — so it is tested here rather than
-- left inside a Deno file nobody runs in CI. The other load-bearing rule: a
-- notification is marked pushed only when it was actually sent, because a
-- swallowed Now alert about a sick child is the worst bug this system can have.

begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000a1', 'authenticated', 'authenticated', 'sup@pn.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000a2', 'authenticated', 'authenticated', 'parent@pn.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000a3', 'authenticated', 'authenticated', 'nophone@pn.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('21800000-0000-4000-8000-000000000001', 'Push Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('31800000-0000-4000-8000-000000000001', '21800000-0000-4000-8000-000000000001', 'Push Centre', 'PN-1', '5 Signal St, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('41800000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000a1', 'Sup Push', 'sup@pn.local'),
  ('41800000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000a2', 'Parent Push', 'parent@pn.local'),
  ('41800000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-0000000000a3', 'No Phone', 'nophone@pn.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('41800000-0000-4000-8000-000000000001', '31800000-0000-4000-8000-000000000001', 'supervisor', true),
  ('41800000-0000-4000-8000-000000000002', '31800000-0000-4000-8000-000000000001', 'family_adult', false),
  ('41800000-0000-4000-8000-000000000003', '31800000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.household (id, centre_id, name) values
  ('51800000-0000-4000-8000-000000000001', '31800000-0000-4000-8000-000000000001', 'Push Household');
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date) values
  ('61800000-0000-4000-8000-000000000001', '31800000-0000-4000-8000-000000000001', 'Sig Push', '2023-03-03', '2026-01-05');
insert into public.child_household (child_id, household_id, centre_id) values
  ('61800000-0000-4000-8000-000000000001', '51800000-0000-4000-8000-000000000001', '31800000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('51800000-0000-4000-8000-000000000001', '41800000-0000-4000-8000-000000000002', '31800000-0000-4000-8000-000000000001', 'parent', true, true),
  ('51800000-0000-4000-8000-000000000001', '41800000-0000-4000-8000-000000000003', '31800000-0000-4000-8000-000000000001', 'parent', true, true);

-- one parent has two devices; the other has none
insert into public.device_push_token (person_id, token, platform) values
  ('41800000-0000-4000-8000-000000000002', 'ExponentPushToken[phone-one]', 'ios'),
  ('41800000-0000-4000-8000-000000000002', 'ExponentPushToken[tablet]', 'android');

-- ── the settings table is nobody's business ─────────────────────────────────
select is(
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'app_setting'),
  0::bigint,
  'push_the_settings_table_has_no_policy_so_no_client_reads_it'
);

select is(
  app.dispatch_push(),
  'not configured',
  'push_the_dispatcher_stays_quiet_until_an_environment_is_wired_up'
);

-- ── the rule: Now always ────────────────────────────────────────────────────
insert into public.notification (id, centre_id, child_id, recipient_person_id, channel, event_type, title, body, requires_acknowledgement)
values
  ('71800000-0000-4000-8000-000000000001', '31800000-0000-4000-8000-000000000001', '61800000-0000-4000-8000-000000000001', '41800000-0000-4000-8000-000000000002', 'now', 'illness_sent_home', 'Sig is unwell', 'Please call the centre.', true);

select is(
  (select count(*) from app.notifications_to_push()),
  2::bigint,
  'push_a_now_alert_goes_to_every_device_that_parent_has'
);

-- ── the rule: Later is quiet, except the one daily story ────────────────────
insert into public.notification (id, centre_id, child_id, recipient_person_id, channel, event_type, title, body)
values
  ('71800000-0000-4000-8000-000000000002', '31800000-0000-4000-8000-000000000001', '61800000-0000-4000-8000-000000000001', '41800000-0000-4000-8000-000000000002', 'later', 'handbook_issued', 'The parent handbook', 'Please read it.'),
  ('71800000-0000-4000-8000-000000000003', '31800000-0000-4000-8000-000000000001', '61800000-0000-4000-8000-000000000001', '41800000-0000-4000-8000-000000000002', 'later', 'story', 'Today''s story', 'The day''s story is ready.');

select is(
  (select count(*) from app.notifications_to_push() where event_type = 'handbook_issued'),
  0::bigint,
  'push_the_later_feed_never_buzzes_a_phone'
);

select is(
  (select count(*) from app.notifications_to_push() where event_type = 'story'),
  2::bigint,
  'push_except_the_one_daily_story'
);

-- a second story the same day is in-app only: one push per child per day
insert into public.notification (id, centre_id, child_id, recipient_person_id, channel, event_type, title, body)
values
  ('71800000-0000-4000-8000-000000000004', '31800000-0000-4000-8000-000000000001', '61800000-0000-4000-8000-000000000001', '41800000-0000-4000-8000-000000000002', 'later', 'story', 'A second story', 'Another one.');

select is(
  (select count(distinct notification_id) from app.notifications_to_push() where event_type = 'story'),
  1::bigint,
  'push_only_one_story_is_ever_queued_for_a_person'
);

-- ── Now first, so a backlog cannot starve an urgent alert ───────────────────
-- the limit is on notifications, not on messages: one alert to a parent with
-- two devices is two rows
select is(
  (select distinct channel from app.notifications_to_push(1)),
  'now',
  'push_a_now_alert_is_always_at_the_front_of_the_queue'
);

-- ── a parent with no phone ──────────────────────────────────────────────────
insert into public.notification (id, centre_id, child_id, recipient_person_id, channel, event_type, title, body, requires_acknowledgement)
values
  ('71800000-0000-4000-8000-000000000005', '31800000-0000-4000-8000-000000000001', '61800000-0000-4000-8000-000000000001', '41800000-0000-4000-8000-000000000003', 'now', 'illness_sent_home', 'Sig is unwell', 'Please call the centre.', true);

select is(
  (select count(*) from app.notifications_to_push() where person_id = '41800000-0000-4000-8000-000000000003'),
  0::bigint,
  'push_a_parent_with_no_device_is_not_queued'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;

-- A push token is private to its owner. If this view asked "does a token
-- exist?" under the caller's own RLS it would see none for anybody else and
-- report every parent as unreachable — so the question is asked by a definer
-- function instead. This test is that bug's tombstone.
select results_eq(
  $$select recipient_name from public.undeliverable_now_alerts
    where centre_id = '31800000-0000-4000-8000-000000000001'$$,
  $$values ('No Phone')$$,
  'push_the_supervisor_is_told_which_alert_has_nowhere_to_land_and_only_that_one'
);

reset role;

-- ── a failed push is NEVER marked as sent ───────────────────────────────────
select lives_ok(
  $$select app.mark_push_failed('71800000-0000-4000-8000-000000000001', 'Expo returned 503 Service Unavailable')$$,
  'push_a_transport_failure_is_recorded'
);

select results_eq(
  $$select pushed_at is null, push_attempts, push_error
    from public.notification where id = '71800000-0000-4000-8000-000000000001'$$,
  $$values (true, 1, 'Expo returned 503 Service Unavailable')$$,
  'push_and_the_alert_is_still_unsent_with_the_reason_on_it'
);

select is(
  (select count(*) from app.notifications_to_push() where notification_id = '71800000-0000-4000-8000-000000000001'),
  2::bigint,
  'push_a_failed_alert_comes_back_round_for_another_try'
);

-- five attempts is where we stop and say so out loud
update public.notification set push_attempts = 5 where id = '71800000-0000-4000-8000-000000000001';

select is(
  (select count(*) from app.notifications_to_push() where notification_id = '71800000-0000-4000-8000-000000000001'),
  0::bigint,
  'push_but_not_forever'
);

set local role authenticated;
select is(
  (select count(*) from public.stuck_push_alerts
   where centre_id = '31800000-0000-4000-8000-000000000001'),
  1::bigint,
  'push_and_a_stuck_alert_is_visible_rather_than_silently_dropped'
);
reset role;

-- ── a successful push ───────────────────────────────────────────────────────
select is(
  app.mark_push_sent(array['71800000-0000-4000-8000-000000000003']::uuid[]),
  1,
  'push_a_sent_story_is_marked_sent'
);

select is(
  (select count(*) from app.notifications_to_push() where event_type = 'story'),
  0::bigint,
  'push_and_the_days_story_quota_is_spent'
);

select is(
  app.mark_push_sent(array['71800000-0000-4000-8000-000000000003']::uuid[]),
  0,
  'push_marking_the_same_one_twice_changes_nothing'
);

-- ── a dead token is retired ─────────────────────────────────────────────────
select lives_ok(
  $$select app.revoke_push_token('ExponentPushToken[tablet]', 'DeviceNotRegistered')$$,
  'push_an_uninstalled_app_has_its_token_retired'
);

insert into public.notification (id, centre_id, child_id, recipient_person_id, channel, event_type, title, body)
values ('71800000-0000-4000-8000-000000000006', '31800000-0000-4000-8000-000000000001', '61800000-0000-4000-8000-000000000001', '41800000-0000-4000-8000-000000000002', 'now', 'accident_report', 'A bump', 'Details in the app.');

select is(
  (select count(*) from app.notifications_to_push() where notification_id = '71800000-0000-4000-8000-000000000006'),
  1::bigint,
  'push_and_is_never_pushed_at_again'
);

-- ── the transport's functions belong to the transport ───────────────────────
-- has_function_privilege, not a grants table: a grant to PUBLIC does not show
-- up as a grant to 'authenticated', so reading the catalogue by grantee name
-- reports success while the door is wide open. Ask the question the way the
-- planner asks it.
select is(
  (select count(*) from unnest(array[
     'public.notifications_to_push(integer)',
     'public.mark_push_sent(uuid[])',
     'public.mark_push_failed(uuid, text)',
     'public.revoke_push_token(text, text)'
   ]) fn
   where has_function_privilege('authenticated', fn, 'EXECUTE')
      or has_function_privilege('anon', fn, 'EXECUTE')),
  0::bigint,
  'push_no_signed_in_user_can_read_the_queue_or_mark_it_delivered'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);

select throws_ok(
  $$select public.mark_push_sent(array['71800000-0000-4000-8000-000000000006']::uuid[])$$,
  '42501',
  null,
  'push_and_a_parent_who_finds_the_function_is_refused'
);

reset role;

-- ── the dispatcher wakes up once it is wired ────────────────────────────────
insert into public.app_setting (key, value, note) values
  ('push_function_url', 'http://127.0.0.1:54321/functions/v1/notify', 'test'),
  ('push_shared_secret', 'a-test-secret', 'test');

select isnt(
  app.dispatch_push(),
  'not configured',
  'push_and_dispatches_once_the_environment_is_filled_in'
);

select * from finish();
rollback;
