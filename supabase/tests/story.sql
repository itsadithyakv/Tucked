-- pgTAP: the daily story — the composer's voice, publishing at pick-up, the
-- nightly floor, and the one rule that outranks all of them: a story must
-- never stop a child going home.
--
-- The three voice tests at the top are ported from packages/domain's
-- buildStory(), which nothing called and which has been deleted. The words
-- they assert are the words the family reads; they are the reason the composer
-- moved rather than being rewritten.

begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '18000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rece@st.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '18000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent@st.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('28000000-0000-4000-8000-000000000001', 'ST Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, timezone, opens_at, closes_at) values
  ('38000000-0000-4000-8000-000000000001', '28000000-0000-4000-8000-000000000001', 'ST Centre', 'ST-1', '1 ST St, Toronto', 'America/Toronto', '07:00', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('39000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', 'toddler', 15);
insert into public.room (id, centre_id, age_group_id, name) values
  ('3a000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', '39000000-0000-4000-8000-000000000001', 'Toddler room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('48000000-0000-4000-8000-000000000001', '18000000-0000-4000-8000-000000000001', 'Rece ST', 'rece@st.local'),
  ('48000000-0000-4000-8000-000000000002', '18000000-0000-4000-8000-000000000002', 'Parent ST', 'parent@st.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('48000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', 'rece', true),
  ('48000000-0000-4000-8000-000000000002', '38000000-0000-4000-8000-000000000001', 'family_adult', false);
insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('48000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('68000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', 'Maya Osei', (current_date - interval '2 years')::date, '2026-01-05', '3a000000-0000-4000-8000-000000000001'),
  ('68000000-0000-4000-8000-000000000002', '38000000-0000-4000-8000-000000000001', 'Theo Ward', (current_date - interval '2 years')::date, '2026-01-05', '3a000000-0000-4000-8000-000000000001');

insert into public.household (id, centre_id, name) values
  ('58000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', 'Osei household');
insert into public.child_household (child_id, household_id, centre_id) values
  ('68000000-0000-4000-8000-000000000001', '58000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('58000000-0000-4000-8000-000000000001', '48000000-0000-4000-8000-000000000002', '38000000-0000-4000-8000-000000000001', 'parent', true, true);

-- Anchored to the centre's local day, never to now() — a fixture that says
-- "two hours ago" crosses local midnight at 01:00.
create or replace function pg_temp.local_at(p_time text) returns timestamptz
language sql stable as $$
  select (((now() at time zone 'America/Toronto')::date + p_time::time)
          at time zone 'America/Toronto')
$$;

-- ── the composer's voice (ported from buildStory) ───────────────────────────
insert into public.care_log (centre_id, child_id, room_id, log_type, logged_at, log_date, payload, recorded_by)
values
  ('38000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', 'activity',   pg_temp.local_at('10:00'), '1970-01-01', '{"description":"Maya loved the leaf pile"}', '48000000-0000-4000-8000-000000000001'),
  ('38000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', 'meal',       pg_temp.local_at('11:50'), '1970-01-01', '{"meal":"lunch","eaten":"most"}', '48000000-0000-4000-8000-000000000001'),
  ('38000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', 'nap_start',  pg_temp.local_at('12:40'), '1970-01-01', '{}', '48000000-0000-4000-8000-000000000001'),
  ('38000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', 'nap_end',    pg_temp.local_at('14:10'), '1970-01-01', '{}', '48000000-0000-4000-8000-000000000001'),
  ('38000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', 'photo',      pg_temp.local_at('14:20'), '1970-01-01', '{"storage_path":"a.jpg","captured_at":"x"}', '48000000-0000-4000-8000-000000000001'),
  ('38000000-0000-4000-8000-000000000001', '68000000-0000-4000-8000-000000000001', '3a000000-0000-4000-8000-000000000001', 'photo',      pg_temp.local_at('14:21'), '1970-01-01', '{"storage_path":"b.jpg","captured_at":"x"}', '48000000-0000-4000-8000-000000000001');

select alike(
  app.story_compose('68000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date),
  '%Maya ate most of lunch.%',
  'story_reads_like_a_letter'
);

select alike(
  app.story_compose('68000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date),
  '%12:40 p.m. to 2:10 p.m.%',
  'story_uses_12_hour_times_a_family_reads'
);

select alike(
  app.story_compose('68000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date),
  '%2 new photos%',
  'story_counts_the_photos'
);

select unalike(
  app.story_compose('68000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date),
  '%!%',
  'story_voice_never_exclaims'
);

select alike(
  app.story_compose('68000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date),
  'Today Maya enjoyed Maya loved the leaf pile.%',
  'story_opens_with_the_day_rather_than_a_meal'
);

select unalike(
  app.story_compose('68000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date),
  '%..%',
  'story_never_double_stops_after_a_time_because_a_m_already_ends_in_one'
);

select is(
  app.story_compose('68000000-0000-4000-8000-000000000002', (now() at time zone 'America/Toronto')::date),
  'Theo had a steady, quiet day with us.',
  'story_quiet_day_still_says_something_kind'
);

select is(
  app.twelve_hour(pg_temp.local_at('00:05'), 'America/Toronto'),
  '12:05 a.m.',
  'twelve_hour_midnight_boundary'
);

select is(
  app.twelve_hour(pg_temp.local_at('12:00'), 'America/Toronto'),
  '12:00 p.m.',
  'twelve_hour_noon_boundary'
);

select is(
  app.twelve_hour(pg_temp.local_at('18:30'), 'America/Toronto'),
  '6:30 p.m.',
  'twelve_hour_evening'
);

select is(
  app.story_compose('68000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date),
  app.story_compose('68000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date),
  'story_is_deterministic_not_generated'
);

-- ── publishing at pick-up ───────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"18000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$select public.record_attendance('38000000-0000-4000-8000-000000000001','68000000-0000-4000-8000-000000000001','arrive','3a000000-0000-4000-8000-000000000001', pg_temp.local_at('08:00'), '48000000-0000-4000-8000-000000000001','4242')$$,
  'a_child_arrives'
);

select is(
  (select count(*)::integer from public.story where child_id = '68000000-0000-4000-8000-000000000001'),
  0,
  'arriving_publishes_nothing_the_day_has_not_happened_yet'
);

select lives_ok(
  $$select public.record_attendance('38000000-0000-4000-8000-000000000001','68000000-0000-4000-8000-000000000001','depart','3a000000-0000-4000-8000-000000000001', pg_temp.local_at('16:30'), '48000000-0000-4000-8000-000000000001','4242')$$,
  'the_child_goes_home'
);

select isnt(
  (select published_at from public.story where child_id = '68000000-0000-4000-8000-000000000001'),
  null::timestamptz,
  'and_the_story_publishes_at_pick_up_which_is_what_the_screen_promises'
);

select alike(
  (select draft_text from public.story where child_id = '68000000-0000-4000-8000-000000000001'),
  '%Maya ate most of lunch.%',
  'the_published_draft_is_the_composed_day'
);

-- Counted as postgres on purpose. The fan-out is a server-side fact, and no
-- client role is meant to see it: notification_select shows a row only to its
-- recipient or to centre leadership, so the RECE who signed the child out
-- cannot count the parent's notifications and should not be able to.
reset role;
select is(
  (select count(*)::integer from public.notification
   where event_type = 'story' and channel = 'later'
     and child_id = '68000000-0000-4000-8000-000000000001'),
  1,
  'one_later_notification_per_viewing_adult'
);
set local role authenticated;

-- ── the educator's words sit on top ─────────────────────────────────────────
select lives_ok(
  $$select public.save_story_note('68000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date,
      'Ask her about the leaf fort.', '48000000-0000-4000-8000-000000000001', '4242')$$,
  'an_educator_adds_a_note_after_the_story_has_gone'
);

select is(
  (select educator_note from public.story where child_id = '68000000-0000-4000-8000-000000000001'),
  'Ask her about the leaf fort.',
  'the_note_is_kept'
);

reset role;
select is(
  (select count(*)::integer from public.notification where event_type = 'story'
     and child_id = '68000000-0000-4000-8000-000000000001'),
  1,
  'and_adding_it_does_not_push_a_second_time_that_day'
);
set local role authenticated;

-- a recomposition must never wipe the human's words
select lives_ok(
  $$select public.publish_story('68000000-0000-4000-8000-000000000001', (now() at time zone 'America/Toronto')::date,
      '48000000-0000-4000-8000-000000000001', '4242')$$,
  'republishing_is_idempotent'
);

select is(
  (select educator_note from public.story where child_id = '68000000-0000-4000-8000-000000000001'),
  'Ask her about the leaf fort.',
  'republishing_never_overwrites_the_educators_words'
);

-- ── a story must never stop a child going home ──────────────────────────────
-- The publish trigger runs inside the sign-out transaction. If composing can
-- fail, a departure must still complete: a late story is a disappointment, a
-- sign-out that will not complete is an incident.
create or replace function pg_temp.break_the_composer() returns void
language plpgsql as $$
begin
  execute $fn$
    create or replace function app.story_compose(p_child uuid, p_date date)
    returns text language plpgsql stable as $broken$
    begin
      raise exception 'the composer is broken';
    end;
    $broken$;
  $fn$;
end;
$$;

reset role;
select pg_temp.break_the_composer();
set local role authenticated;

select lives_ok(
  $$select public.record_attendance('38000000-0000-4000-8000-000000000001','68000000-0000-4000-8000-000000000002','arrive','3a000000-0000-4000-8000-000000000001', pg_temp.local_at('08:05'), '48000000-0000-4000-8000-000000000001','4242')$$,
  'a_second_child_arrives'
);

select lives_ok(
  $$select public.record_attendance('38000000-0000-4000-8000-000000000001','68000000-0000-4000-8000-000000000002','depart','3a000000-0000-4000-8000-000000000001', pg_temp.local_at('16:45'), '48000000-0000-4000-8000-000000000001','4242')$$,
  'a_broken_composer_never_blocks_a_child_going_home'
);

select is(
  (select count(*)::integer from public.story where child_id = '68000000-0000-4000-8000-000000000002'),
  0,
  'the_story_is_simply_missing_and_the_sweep_will_pick_it_up'
);

-- ── the nightly floor ───────────────────────────────────────────────────────
reset role;
-- The sweep is the AFTER-CLOSING floor, so it deliberately does nothing while
-- a centre is still open. Move closing into the past to exercise it — a test
-- that only passed after 6 p.m. would be a worse test than a slow one.
-- opens_at < closes_at is a constraint (no overnight care in v1), so both move.
-- 00:01–00:02 is the narrowest window that has already passed at any hour a
-- person is realistically running this suite.
update public.centre set opens_at = '00:01', closes_at = '00:02'
where id = '38000000-0000-4000-8000-000000000001';

-- put the real composer back, then let the sweep catch what the trigger lost
create or replace function app.story_compose(p_child uuid, p_date date)
returns text language sql stable security definer set search_path = public as $$
  select split_part(c.full_name, ' ', 1) || ' had a steady, quiet day with us.'
  from public.child c where c.id = p_child
$$;

select ok(
  app.publish_daily_stories() >= 1,
  'the_sweep_publishes_for_a_child_whose_sign_out_never_produced_one'
);

select isnt(
  (select published_at from public.story where child_id = '68000000-0000-4000-8000-000000000002'),
  null::timestamptz,
  'a_forgotten_sign_out_costs_a_family_a_late_story_not_no_story'
);

select is(
  (select published_by from public.story where child_id = '68000000-0000-4000-8000-000000000002'),
  null::uuid,
  'a_story_the_database_published_names_nobody_because_nobody_wrote_it'
);

-- ── the family ──────────────────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"18000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select is(
  (select count(*)::integer from public.story),
  1,
  'a_parent_sees_their_own_childs_published_story_and_no_other'
);

select * from finish();
rollback;
