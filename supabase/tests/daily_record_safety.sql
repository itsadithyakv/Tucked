-- pgTAP: s. 37 daily written record + s. 36(4) accident reports.

begin;

create extension if not exists pgtap with schema extensions;

select plan(15);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '13000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sup@dr.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '13000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent@dr.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '13000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'other@dr.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('23000000-0000-4000-8000-000000000001', 'DR Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('37000000-0000-4000-8000-000000000001', '23000000-0000-4000-8000-000000000001', 'DR Centre', 'DR-1', '1 DR St, Toronto', '07:30', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('38000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('39000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000001', '38000000-0000-4000-8000-000000000001', 'Preschool room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('43000000-0000-4000-8000-000000000001', '13000000-0000-4000-8000-000000000001', 'Sup DR', 'sup@dr.local'),
  ('43000000-0000-4000-8000-000000000002', '13000000-0000-4000-8000-000000000002', 'Parent DR', 'parent@dr.local'),
  ('43000000-0000-4000-8000-000000000003', '13000000-0000-4000-8000-000000000003', 'Other Parent DR', 'other@dr.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('43000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000001', 'supervisor', true),
  ('43000000-0000-4000-8000-000000000002', '37000000-0000-4000-8000-000000000001', 'family_adult', false),
  ('43000000-0000-4000-8000-000000000003', '37000000-0000-4000-8000-000000000001', 'family_adult', false);
insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('43000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('63000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000001', 'DR Child', '2022-06-01', '2026-01-05', '39000000-0000-4000-8000-000000000001');
insert into public.household (id, centre_id, name) values
  ('53000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000001', 'DR Household');
insert into public.child_household (child_id, household_id, centre_id) values
  ('63000000-0000-4000-8000-000000000001', '53000000-0000-4000-8000-000000000001', '37000000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view) values
  ('53000000-0000-4000-8000-000000000001', '43000000-0000-4000-8000-000000000002', '37000000-0000-4000-8000-000000000001', 'parent', true);

-- ── s. 37 daily written record ──────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"13000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select lives_ok(
  $$select public.ensure_daily_record('37000000-0000-4000-8000-000000000001', current_date)$$,
  's37_draft_created_for_operating_day'
);

select is(
  (select count(*) from public.daily_written_record
   where centre_id = '37000000-0000-4000-8000-000000000001' and record_date = current_date),
  1::bigint,
  's37_ensure_is_idempotent_after_second_call'
);

select lives_ok(
  $$select public.ensure_daily_record('37000000-0000-4000-8000-000000000001', current_date)$$,
  's37_second_ensure_returns_existing'
);

select throws_ok(
  $$select public.close_daily_record(
      (select id from public.daily_written_record where centre_id = '37000000-0000-4000-8000-000000000001' and record_date = current_date),
      '   ', '43000000-0000-4000-8000-000000000001', '4242')$$,
  'the daily written record needs a written entry',
  's37_empty_entry_rejected'
);

-- an accident lands BEFORE close and must cross-reference into today's record
select lives_ok(
  $$select public.record_accident_report(
      '37000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001',
      now(), 'Playground', 'Fell from the climber', 'Bumped head on mat', 'minor',
      'Ice pack, comforted, observed', true, 'Watch for vomiting, drowsiness, unequal pupils for 24h',
      '43000000-0000-4000-8000-000000000001', '4242')$$,
  's36_4_accident_report_recorded'
);

select throws_like(
  $$select public.record_accident_report(
      '37000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001',
      now(), 'Playground', 'Fell again', 'Head bump', 'minor',
      'Ice pack', true, null,
      '43000000-0000-4000-8000-000000000001', '4242')$$,
  '%accident_head_injury_needs_watch_note%',
  's36_4_head_injury_requires_concussion_note'
);

select is(
  (select refs @> '[{"type": "accident"}]' from public.daily_written_record
   where centre_id = '37000000-0000-4000-8000-000000000001' and record_date = current_date),
  true,
  's37_accident_cross_referenced_into_daily_record'
);

select lives_ok(
  $$select public.close_daily_record(
      (select id from public.daily_written_record where centre_id = '37000000-0000-4000-8000-000000000001' and record_date = current_date),
      'Uneventful day apart from the recorded accident (see child''s file). Outdoor play both blocks.',
      '43000000-0000-4000-8000-000000000001', '4242')$$,
  's37_human_close_with_entry'
);

select is(
  (select closed_by from public.daily_written_record
   where centre_id = '37000000-0000-4000-8000-000000000001' and record_date = current_date),
  '43000000-0000-4000-8000-000000000001'::uuid,
  's37_close_names_the_human'
);

select throws_ok(
  $$select public.close_daily_record(
      (select id from public.daily_written_record where centre_id = '37000000-0000-4000-8000-000000000001' and record_date = current_date),
      'second thoughts', '43000000-0000-4000-8000-000000000001', '4242')$$,
  'a closed daily written record never changes',
  's37_closed_record_never_changes'
);

-- ── parent acknowledgement (the s. 36(4) evidence) ──────────────────────────
-- Capture the report id while the supervisor can see it: RLS hides it from the
-- unrelated parent, so their subquery would be empty (which is itself correct).
reset role;
create temporary table t_report on commit drop as
  select id from public.accident_report limit 1;
grant select on t_report to authenticated;
set local role authenticated;

select set_config('request.jwt.claims', '{"sub":"13000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select throws_ok(
  $$select public.acknowledge_accident_report((select id from t_report))$$,
  'only a household member of this child may acknowledge',
  's36_4_stranger_cannot_acknowledge'
);

select set_config('request.jwt.claims', '{"sub":"13000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select lives_ok(
  $$select public.acknowledge_accident_report((select id from t_report))$$,
  's36_4_parent_acknowledges_copy'
);

select is(
  (select parent_ack_person_id from public.accident_report limit 1),
  '43000000-0000-4000-8000-000000000002'::uuid,
  's36_4_acknowledgement_names_the_parent_with_timestamp'
);

-- ── owner: immutability ─────────────────────────────────────────────────────
reset role;

select throws_ok(
  $$update public.accident_report set description = 'edited later'$$,
  'an acknowledged accident report never changes',
  's36_4_acknowledged_report_never_changes'
);

select throws_like(
  $$delete from public.daily_written_record where true$$,
  '%append-only%',
  'never_daily_records_deleted'
);

select * from finish();
rollback;
