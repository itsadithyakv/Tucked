-- pgTAP: the daily written record drafts itself (s. 37). The load-bearing
-- rules: the draft is arithmetic over the day's own records and never a
-- model's summary (§9.14); the incidents are QUOTED from the cross-references
-- the triggers wrote at the time, so the summary and the reference can never
-- disagree; a quiet day says so in one line; and a closed record never changes,
-- not even to regenerate its draft.

begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-000000000091', 'authenticated', 'authenticated', 'sup@dwr.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-000000000092', 'authenticated', 'authenticated', 'edu@dwr.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('21900000-0000-4000-8000-000000000001', 'Record Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('31900000-0000-4000-8000-000000000001', '21900000-0000-4000-8000-000000000001', 'Record Centre', 'DWR-1', '7 Ledger Row, Toronto', '07:30', '18:00');

insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('32900000-0000-4000-8000-000000000001', '31900000-0000-4000-8000-000000000001', 'toddler', 15);
insert into public.room (id, centre_id, age_group_id, name) values
  ('33900000-0000-4000-8000-000000000001', '31900000-0000-4000-8000-000000000001', '32900000-0000-4000-8000-000000000001', 'Birch room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('41900000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000091', 'Sup Record', 'sup@dwr.local'),
  ('41900000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000092', 'Edu Record', 'edu@dwr.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('41900000-0000-4000-8000-000000000001', '31900000-0000-4000-8000-000000000001', 'supervisor', true),
  ('41900000-0000-4000-8000-000000000002', '31900000-0000-4000-8000-000000000001', 'rece', true);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('41900000-0000-4000-8000-000000000001', '31900000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('41900000-0000-4000-8000-000000000002', '31900000-0000-4000-8000-000000000001', extensions.crypt('7171', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('51900000-0000-4000-8000-000000000001', '31900000-0000-4000-8000-000000000001', 'Record Household');
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('61900000-0000-4000-8000-000000000001', '31900000-0000-4000-8000-000000000001', 'Bo Record', (current_date - interval '14 months')::date, '2026-01-05', '33900000-0000-4000-8000-000000000001'),
  ('61900000-0000-4000-8000-000000000002', '31900000-0000-4000-8000-000000000001', 'Wren Record', (current_date - interval '14 months')::date, '2026-01-05', '33900000-0000-4000-8000-000000000001');
insert into public.child_household (child_id, household_id, centre_id) values
  ('61900000-0000-4000-8000-000000000001', '51900000-0000-4000-8000-000000000001', '31900000-0000-4000-8000-000000000001'),
  ('61900000-0000-4000-8000-000000000002', '51900000-0000-4000-8000-000000000001', '31900000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('51900000-0000-4000-8000-000000000001', '41900000-0000-4000-8000-000000000001', '31900000-0000-4000-8000-000000000001', 'parent', true, true);

-- ── a day with nothing on it ────────────────────────────────────────────────
select alike(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  to_char(current_date, 'FMDay FMDD FMMonth YYYY') || ' — Record Centre%',
  's37_the_draft_is_headed_with_the_day_and_the_centre'
);

-- to_char pads Day and Month to nine characters unless you ask it not to
select ok(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date) not like '%  %',
  's37_the_header_has_no_padded_whitespace_in_it'
);

select alike(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  '%0 children attended and 0 staff on shift.%',
  's37_an_empty_day_still_states_the_numbers'
);

select alike(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  '%uneventful day%',
  's37_a_quiet_day_says_so_in_one_line'
);

-- ── the day fills in ────────────────────────────────────────────────────────
insert into public.staff_shift (centre_id, person_id, room_id, shift_date, in_at, recorded_by)
values ('31900000-0000-4000-8000-000000000001', '41900000-0000-4000-8000-000000000002', '33900000-0000-4000-8000-000000000001', current_date, now() - interval '5 hours', '41900000-0000-4000-8000-000000000001');

insert into public.attendance_event (centre_id, child_id, room_id, event_type, actual_time, attendance_date, recorded_by) values
  ('31900000-0000-4000-8000-000000000001', '61900000-0000-4000-8000-000000000001', '33900000-0000-4000-8000-000000000001', 'arrive', now() - interval '4 hours', current_date, '41900000-0000-4000-8000-000000000002');
insert into public.attendance_event (centre_id, child_id, room_id, event_type, actual_time, attendance_date, recorded_by) values
  ('31900000-0000-4000-8000-000000000001', '61900000-0000-4000-8000-000000000002', null, 'absent', now() - interval '4 hours', current_date, '41900000-0000-4000-8000-000000000002');

select alike(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  '%1 child attended and 1 staff member on shift. 1 child was marked absent.%',
  's37_one_of_something_never_reads_as_1_childs'
);

-- outdoor, written straight in because these are past measurements
alter table public.outdoor_period disable trigger outdoor_period_rules;
insert into public.outdoor_period (centre_id, room_id, outdoor_date, started_at, ended_at, weather, recorded_by, ended_by)
values ('31900000-0000-4000-8000-000000000001', '33900000-0000-4000-8000-000000000001', current_date,
        now() - interval '3 hours', now() - interval '1 hour', 'fine',
        '41900000-0000-4000-8000-000000000002', '41900000-0000-4000-8000-000000000002');
alter table public.outdoor_period enable trigger outdoor_period_rules;

select alike(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  '%Outdoor play: Birch room 2 h 00.%',
  's47_the_measured_outdoor_minutes_appear_in_the_days_record'
);

select alike(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  '%Meals were served as the posted menu.%',
  's42_a_day_with_no_substitution_says_the_menu_was_followed'
);

insert into public.menu_substitution (centre_id, served_on, meal, planned, served, reason, recorded_by)
values ('31900000-0000-4000-8000-000000000001', current_date, 'snack_pm', 'Apple slices and cheese', 'Yogurt and berries', 'Cheese ran out', '41900000-0000-4000-8000-000000000002');

select alike(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  '%snack pm — Yogurt and berries instead of Apple slices and cheese (Cheese ran out)%',
  's42_a_substitution_is_named_in_the_days_record'
);

-- sleep
insert into public.care_log (centre_id, child_id, room_id, log_type, logged_at, payload, recorded_by) values
  ('31900000-0000-4000-8000-000000000001', '61900000-0000-4000-8000-000000000001', '33900000-0000-4000-8000-000000000001', 'nap_start', now() - interval '2 hours', '{}'::jsonb, '41900000-0000-4000-8000-000000000002'),
  ('31900000-0000-4000-8000-000000000001', '61900000-0000-4000-8000-000000000001', '33900000-0000-4000-8000-000000000001', 'sleep_check', now() - interval '100 minutes', '{"breathing_ok":true,"position":"back"}'::jsonb, '41900000-0000-4000-8000-000000000002'),
  ('31900000-0000-4000-8000-000000000001', '61900000-0000-4000-8000-000000000001', '33900000-0000-4000-8000-000000000001', 'sleep_check', now() - interval '80 minutes', '{"breathing_ok":true,"position":"back"}'::jsonb, '41900000-0000-4000-8000-000000000002');

select alike(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  '%Sleep: 1 rest period, with 2 direct visual checks recorded.%',
  's33_1_the_sleep_checks_are_counted_into_the_days_record'
);

-- a headcount
insert into public.headcount_check (centre_id, room_id, kind, expected, counted, recorded_by)
values ('31900000-0000-4000-8000-000000000001', '33900000-0000-4000-8000-000000000001', 'transition_out', 1, 1, '41900000-0000-4000-8000-000000000002');

select alike(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  '%Face-to-name headcounts: 1 recorded.%',
  's11_the_headcounts_are_counted_too'
);

-- ── the incidents are quoted, not re-derived ────────────────────────────────
insert into public.accident_report (centre_id, child_id, occurred_at, occurred_date, location, description, injury, severity, first_aid, completed_by)
values ('31900000-0000-4000-8000-000000000001', '61900000-0000-4000-8000-000000000001', now() - interval '90 minutes', current_date,
        'Birch room', 'Tripped on the mat', 'Grazed knee', 'minor', 'Cleaned and a plaster', '41900000-0000-4000-8000-000000000002');

select alike(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  '%Recorded during the day:%',
  's37_the_day_grows_a_list_of_what_happened'
);

select is(
  (select count(*) from unnest(string_to_array(
     app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date), E'\n')) l
   where l like '• %'),
  1::bigint,
  's37_the_accident_appears_exactly_once'
);

-- the bullet is the cross-reference's own sentence, character for character
select ok(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date) like
    ('%• ' || (select ref ->> 'note'
              from public.daily_written_record d, lateral jsonb_array_elements(d.refs) ref
              where d.centre_id = '31900000-0000-4000-8000-000000000001'
                and d.record_date = current_date and d.room_id is null
              limit 1) || '%'),
  's37_the_summary_quotes_the_cross_reference_word_for_word'
);

select ok(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date) not like '%uneventful%',
  's37_and_a_day_with_an_accident_is_not_uneventful'
);

-- ── regenerating ────────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-000000000091","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$select public.regenerate_daily_record_draft(
      (select id from public.daily_written_record
       where centre_id = '31900000-0000-4000-8000-000000000001' and record_date = current_date and room_id is null),
      '41900000-0000-4000-8000-000000000001', '4242')$$,
  's37_the_supervisor_can_recompose_the_draft'
);

select alike(
  (select draft_text from public.daily_written_record
   where centre_id = '31900000-0000-4000-8000-000000000001' and record_date = current_date and room_id is null),
  '%Accident — see child''s file%',
  's37_and_the_stored_draft_now_holds_the_day'
);

-- the preview never touches what is stored
select lives_ok(
  $$select public.daily_record_preview('31900000-0000-4000-8000-000000000001', current_date)$$,
  's37_a_preview_is_available_without_saving_anything'
);

select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-000000000092","role":"authenticated"}', true);

select is(
  public.daily_record_preview('31900000-0000-4000-8000-000000000001', current_date),
  null,
  's37_the_room_team_does_not_preview_the_centres_day'
);

-- ── a closed day never changes ──────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-000000000091","role":"authenticated"}', true);

select lives_ok(
  $$select public.close_daily_record(
      (select id from public.daily_written_record
       where centre_id = '31900000-0000-4000-8000-000000000001' and record_date = current_date and room_id is null),
      'Checked and confirmed. ' || (select draft_text from public.daily_written_record
        where centre_id = '31900000-0000-4000-8000-000000000001' and record_date = current_date and room_id is null),
      '41900000-0000-4000-8000-000000000001', '4242')$$,
  's37_the_human_closes_the_day'
);

select throws_like(
  $$select public.regenerate_daily_record_draft(
      (select id from public.daily_written_record
       where centre_id = '31900000-0000-4000-8000-000000000001' and record_date = current_date and room_id is null),
      '41900000-0000-4000-8000-000000000001', '4242')$$,
  '%never changes%',
  's37_and_a_closed_record_cannot_even_be_redrafted'
);

-- ── never AI ────────────────────────────────────────────────────────────────
-- The composer is arithmetic over the day's own rows: the same day composed
-- twice is the same text, character for character.
select is(
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  app.dwr_compose('31900000-0000-4000-8000-000000000001', current_date),
  'never_the_daily_record_draft_is_deterministic_not_generated'
);

select * from finish();
rollback;
