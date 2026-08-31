-- pgTAP: delivery receipts. "Sent" meant Expo accepted the message; a receipt
-- is what actually became of it. The load-bearing rules: delivered_at is set
-- only by a receipt that came back ok; a receipt that came back error makes
-- the notification LOUD rather than leaving a supervisor to assume it rang;
-- a dead device found in a receipt retires its token like one found in a
-- ticket; and a ticket Expo never answers is closed off rather than asked
-- about forever.

begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000f7', 'authenticated', 'authenticated', 'sup@rc.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000f8', 'authenticated', 'authenticated', 'parent@rc.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('22000000-0000-4000-8000-000000000001', 'Receipt Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('32000000-0000-4000-8000-000000000001', '22000000-0000-4000-8000-000000000001', 'Receipt Centre', 'RC-1', '2 Ticket Row, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('42000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000f7', 'Sup Receipt', 'sup@rc.local'),
  ('42000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000f8', 'Parent Receipt', 'parent@rc.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('42000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000001', 'supervisor', true),
  ('42000000-0000-4000-8000-000000000002', '32000000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.household (id, centre_id, name) values
  ('52000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000001', 'Receipt Household');
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date) values
  ('62000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000001', 'Rye Receipt', '2023-05-05', '2026-01-05');
insert into public.child_household (child_id, household_id, centre_id) values
  ('62000000-0000-4000-8000-000000000001', '52000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('52000000-0000-4000-8000-000000000001', '42000000-0000-4000-8000-000000000002', '32000000-0000-4000-8000-000000000001', 'parent', true, true);

insert into public.device_push_token (person_id, token, platform) values
  ('42000000-0000-4000-8000-000000000002', 'ExponentPushToken[rc-phone]', 'ios'),
  ('42000000-0000-4000-8000-000000000002', 'ExponentPushToken[rc-old]', 'android');

-- two Now alerts, both already handed to Expo
insert into public.notification (id, centre_id, child_id, recipient_person_id, channel, event_type, title, body, requires_acknowledgement, pushed_at, push_attempts)
values
  ('72000000-0000-4000-8000-000000000001', '32000000-0000-4000-8000-000000000001', '62000000-0000-4000-8000-000000000001', '42000000-0000-4000-8000-000000000002', 'now', 'illness_sent_home', 'Rye is unwell', 'Please call the centre.', true, now() - interval '10 minutes', 1),
  ('72000000-0000-4000-8000-000000000002', '32000000-0000-4000-8000-000000000001', '62000000-0000-4000-8000-000000000001', '42000000-0000-4000-8000-000000000002', 'now', 'accident_report', 'A bump', 'Details in the app.', true, now() - interval '10 minutes', 1);

-- ── tickets are kept per notification and per device ────────────────────────
select is(
  app.record_push_tickets('[
    {"notification_id":"72000000-0000-4000-8000-000000000001","token":"ExponentPushToken[rc-phone]","expo_ticket_id":"tk-a1"},
    {"notification_id":"72000000-0000-4000-8000-000000000001","token":"ExponentPushToken[rc-old]","expo_ticket_id":"tk-a2"},
    {"notification_id":"72000000-0000-4000-8000-000000000002","token":"ExponentPushToken[rc-phone]","expo_ticket_id":"tk-b1"},
    {"notification_id":"72000000-0000-4000-8000-000000000002","token":"ExponentPushToken[rc-old]","expo_ticket_id":"tk-b2"}
  ]'::jsonb),
  4,
  'push_a_ticket_is_kept_for_every_accepted_message'
);

select is(
  app.record_push_tickets('[
    {"notification_id":"72000000-0000-4000-8000-000000000001","token":"ExponentPushToken[rc-phone]","expo_ticket_id":"tk-a1"}
  ]'::jsonb),
  0,
  'push_the_same_ticket_is_never_recorded_twice'
);

-- ── a receipt takes a few minutes to exist ──────────────────────────────────
select is(
  (select count(*) from app.push_tickets_awaiting_receipt()),
  0::bigint,
  'push_a_ticket_seconds_old_is_not_asked_about_yet'
);

update public.push_ticket set accepted_at = now() - interval '10 minutes';

select is(
  (select count(*) from app.push_tickets_awaiting_receipt()),
  4::bigint,
  'push_and_is_asked_about_once_expo_has_had_time'
);

-- ── it arrived ──────────────────────────────────────────────────────────────
select is(
  (select delivered_at from public.notification where id = '72000000-0000-4000-8000-000000000001'),
  null,
  'push_nothing_is_delivered_until_a_receipt_says_so'
);

select lives_ok(
  $$select app.record_push_receipt('tk-a1', 'ok', null)$$,
  'push_a_receipt_comes_back_ok'
);

select isnt(
  (select delivered_at from public.notification where id = '72000000-0000-4000-8000-000000000001'),
  null,
  'push_and_delivered_at_finally_means_something'
);

-- the other device's receipt for the same alert does not move the timestamp
select lives_ok(
  $$select app.record_push_receipt('tk-a2', 'error', 'DeviceNotRegistered')$$,
  'push_the_second_device_reports_separately'
);

select is(
  (select count(*) from public.notification
   where id = '72000000-0000-4000-8000-000000000001' and delivered_at is not null),
  1::bigint,
  'push_one_device_arriving_is_enough_for_the_alert_to_have_arrived'
);

-- ── a dead device found in a receipt is retired ─────────────────────────────
select results_eq(
  $$select revoked_at is not null, revoked_reason from public.device_push_token
    where token = 'ExponentPushToken[rc-old]'$$,
  $$values (true, 'DeviceNotRegistered (receipt)')$$,
  'push_a_dead_device_found_in_a_receipt_is_retired_like_one_found_in_a_ticket'
);

select is(
  (select revoked_at from public.device_push_token where token = 'ExponentPushToken[rc-phone]'),
  null,
  'push_and_the_working_device_is_left_alone'
);

-- ── it never arrived ────────────────────────────────────────────────────────
select lives_ok(
  $$select app.record_push_receipt('tk-b1', 'error', 'MessageTooBig'),
           app.record_push_receipt('tk-b2', 'error', 'DeviceNotRegistered')$$,
  'push_both_devices_report_failure_for_the_second_alert'
);

select is(
  (select delivered_at from public.notification where id = '72000000-0000-4000-8000-000000000002'),
  null,
  'push_an_alert_no_device_received_is_not_delivered'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000f7","role":"authenticated"}', true);
set local role authenticated;

-- push_ticket has RLS on and no policies. If this view asked "does a failed
-- ticket exist?" under the caller's own RLS it would see none and report that
-- everything arrived — the same trap undeliverable_now_alerts fell into. The
-- two ticket questions are answered by definer functions instead. Tombstone.
select ok(
  (select count(*) from public.push_ticket) = 0,
  'push_a_supervisor_cannot_see_the_transports_own_bookkeeping'
);

select results_eq(
  $$select title from public.push_never_arrived
    where centre_id = '32000000-0000-4000-8000-000000000001'$$,
  $$values ('A bump')$$,
  'push_the_supervisor_is_told_which_alert_never_landed_and_only_that_one'
);

select alike(
  (select why from public.push_never_arrived where centre_id = '32000000-0000-4000-8000-000000000001'),
  '%MessageTooBig%',
  'push_and_is_told_why'
);

reset role;

-- ── a ticket Expo never answers is closed off ───────────────────────────────
insert into public.push_ticket (notification_id, token, expo_ticket_id, accepted_at)
values ('72000000-0000-4000-8000-000000000001', 'ExponentPushToken[rc-phone]', 'tk-lost', now() - interval '2 days');

select is(
  (select count(*) from app.push_tickets_awaiting_receipt() where expo_ticket_id = 'tk-lost'),
  0::bigint,
  'push_a_day_old_ticket_is_never_asked_about_again'
);

select is(
  app.close_stale_push_tickets(),
  1,
  'push_it_is_closed_off_instead'
);

select is(
  (select receipt_error from public.push_ticket where expo_ticket_id = 'tk-lost'),
  'no receipt from Expo within 24 hours',
  'push_and_says_plainly_that_nothing_came_back'
);

-- ── the transport's calls, and nobody else's ────────────────────────────────
select is(
  (select count(*) from unnest(array[
     'public.record_push_tickets(jsonb)',
     'public.push_tickets_awaiting_receipt(integer)',
     'public.record_push_receipt(text, text, text)'
   ]) fn
   where has_function_privilege('authenticated', fn, 'EXECUTE')
      or has_function_privilege('anon', fn, 'EXECUTE')),
  0::bigint,
  'push_no_signed_in_user_can_mark_an_alert_delivered'
);

select * from finish();
rollback;
