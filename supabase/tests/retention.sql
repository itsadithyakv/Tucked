-- pgTAP: s. 72(5) retention — anonymise AFTER 3 years post-discharge, never
-- before, never a hard delete. The regulated rows all survive; the identity
-- leaves: name, birth day/month, photos, record-item content, free text,
-- headcount name-snapshots. The immutability escape hatch opens only for the
-- anonymiser and closes behind it.

begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into public.licensee (id, legal_name) values ('2c000000-0000-4000-8000-000000000001', 'Ret Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('3c100000-0000-4000-8000-000000000001', '2c000000-0000-4000-8000-000000000001', 'Ret Centre', 'RET-1', '1 Ret St, Toronto', '07:30', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('3c200000-0000-4000-8000-000000000001', '3c100000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('3c300000-0000-4000-8000-000000000001', '3c100000-0000-4000-8000-000000000001', '3c200000-0000-4000-8000-000000000001', 'Ret Room');

insert into public.person (id, full_name, email) values
  ('4c000000-0000-4000-8000-000000000001', 'Staff Ret', 'staff@ret.local'),
  ('4c000000-0000-4000-8000-000000000002', 'Parent Ret', 'parent@ret.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('4c000000-0000-4000-8000-000000000001', '3c100000-0000-4000-8000-000000000001', 'rece', true);

-- A: discharged 4 years ago (clock matured 1 year ago). B: discharged 1 year
-- ago (immature). C: still enrolled (no clock at all).
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('6c000000-0000-4000-8000-000000000001', '3c100000-0000-4000-8000-000000000001', 'Ava Larsen', '2019-06-15', '2021-01-05', '3c300000-0000-4000-8000-000000000001'),
  ('6c000000-0000-4000-8000-000000000002', '3c100000-0000-4000-8000-000000000001', 'Bo Winter', '2022-04-10', '2024-01-05', '3c300000-0000-4000-8000-000000000001'),
  ('6c000000-0000-4000-8000-000000000003', '3c100000-0000-4000-8000-000000000001', 'Cy Holt', '2023-02-01', '2026-01-05', '3c300000-0000-4000-8000-000000000001');

-- discharge via UPDATE so the 0012 clock trigger fires
update public.child set discharge_date = (current_date - interval '4 years')::date
  where id = '6c000000-0000-4000-8000-000000000001';
update public.child set discharge_date = (current_date - interval '1 year')::date
  where id = '6c000000-0000-4000-8000-000000000002';

-- Ava's record set: everything the anonymiser must scrub or preserve
select app.ensure_record_items('3c100000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000001');
update public.child_record_item
  set content = '{"parents": "Lena Larsen, 44 Elm St, 416-555-0000"}'::jsonb
  where child_id = '6c000000-0000-4000-8000-000000000001';

insert into public.attendance_event (centre_id, child_id, room_id, event_type, actual_time, attendance_date, recorded_by)
values ('3c100000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000001', '3c300000-0000-4000-8000-000000000001', 'arrive', now() - interval '4 years 6 months', '1970-01-01', '4c000000-0000-4000-8000-000000000001');

insert into public.care_log (centre_id, child_id, room_id, log_type, logged_at, log_date, payload, recorded_by)
values ('3c100000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000001', '3c300000-0000-4000-8000-000000000001', 'note', now() - interval '4 years 6 months', '1970-01-01', '{"text": "Ava built a tall tower with Bo"}', '4c000000-0000-4000-8000-000000000001');

-- ACKNOWLEDGED accident report — the hardest lock the anonymiser must pass
insert into public.accident_report (centre_id, child_id, occurred_at, occurred_date, location, description, injury, severity, first_aid, head_injury, completed_by, parent_ack_at, parent_ack_person_id)
values ('3c100000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000001', now() - interval '4 years 6 months', '1970-01-01', 'Playground', 'Ava tripped over the planter', 'Scraped knee', 'minor', 'Cleaned and bandaged', false, '4c000000-0000-4000-8000-000000000001', now() - interval '4 years 6 months', '4c000000-0000-4000-8000-000000000002');

insert into public.individualised_plan (centre_id, child_id, plan_type, version, condition, allergens, signs, emergency_procedure, developed_with, status, ended_at, recorded_by)
values ('3c100000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000001', 'anaphylaxis', 1, 'Anaphylaxis — sesame (Ava Larsen)', array['sesame'], 'Hives', 'EpiPen, 911', 'Lena Larsen (parent)', 'ended', now() - interval '4 years', '4c000000-0000-4000-8000-000000000001');

insert into public.story (centre_id, child_id, story_date, draft_text, educator_note, published_at, published_by)
values ('3c100000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000001', (current_date - interval '4 years 6 months')::date, 'Ava loved the leaf pile', 'Ask Ava about it', now() - interval '4 years 6 months', '4c000000-0000-4000-8000-000000000001');

insert into public.notification (centre_id, child_id, recipient_person_id, channel, event_type, title, body)
values ('3c100000-0000-4000-8000-000000000001', '6c000000-0000-4000-8000-000000000001', '4c000000-0000-4000-8000-000000000002', 'later', 'story', 'Ava''s story', 'Ava had a lovely day.');

insert into public.headcount_check (centre_id, room_id, kind, expected, counted, missing, recorded_by)
values ('3c100000-0000-4000-8000-000000000001', '3c300000-0000-4000-8000-000000000001', 'spot', 8, 7, '[{"child_id": "6c000000-0000-4000-8000-000000000001", "full_name": "Ava Larsen"}]', '4c000000-0000-4000-8000-000000000001');

insert into storage.objects (bucket_id, name)
values ('photos', '3c100000-0000-4000-8000-000000000001/6c000000-0000-4000-8000-000000000001/profile.jpg');

-- ── the sweep ───────────────────────────────────────────────────────────────
select is(app.run_retention_sweep(), 1, 's72_5_sweep_anonymises_exactly_the_mature_clock');

select alike(
  (select full_name from public.child where id = '6c000000-0000-4000-8000-000000000001'),
  'Anonymised child %',
  's72_5_name_anonymised'
);

select is(
  (select date_of_birth from public.child where id = '6c000000-0000-4000-8000-000000000001'),
  '2019-01-01'::date,
  's72_5_birth_date_coarsened_to_year'
);

select is(
  (select count(*) from public.child_record_item
   where child_id = '6c000000-0000-4000-8000-000000000001' and content <> '{"anonymised": true}'::jsonb),
  0::bigint,
  's72_5_record_item_content_scrubbed'
);

select is(
  (select (payload ? 'text') or not (payload ? 'anonymised') from public.care_log
   where child_id = '6c000000-0000-4000-8000-000000000001'),
  false,
  's72_5_care_log_free_text_scrubbed'
);

select is(
  (select description from public.accident_report where child_id = '6c000000-0000-4000-8000-000000000001'),
  '[anonymised]',
  's72_5_acknowledged_accident_report_scrubbed_through_the_lock'
);

select is(
  (select (condition = '[anonymised]' and developed_with = '[anonymised]' and allergens = '{}')
   from public.individualised_plan where child_id = '6c000000-0000-4000-8000-000000000001'),
  true,
  's72_5_plan_text_and_parent_names_scrubbed'
);

select is(
  (select draft_text from public.story where child_id = '6c000000-0000-4000-8000-000000000001'),
  '[anonymised]',
  's72_5_story_scrubbed'
);

select is(
  (select title from public.notification where child_id = '6c000000-0000-4000-8000-000000000001'),
  '[anonymised]',
  's72_5_notification_scrubbed'
);

select alike(
  (select missing -> 0 ->> 'full_name' from public.headcount_check
   where centre_id = '3c100000-0000-4000-8000-000000000001'),
  'Anonymised child %',
  's72_5_headcount_name_snapshot_renamed'
);

-- the regulated record itself SURVIVES — identity gone, evidence intact
select is(
  (select count(*) from public.attendance_event where child_id = '6c000000-0000-4000-8000-000000000001'),
  1::bigint,
  'never_attendance_rows_deleted_by_retention'
);

select is(
  (select count(*) from storage.objects
   where bucket_id = 'photos' and split_part(name, '/', 2) = '6c000000-0000-4000-8000-000000000001'),
  0::bigint,
  's72_5_photos_deleted'
);

select is(
  (select count(*) from public.retention_clock
   where subject_id = '6c000000-0000-4000-8000-000000000001' and anonymised_at is not null),
  2::bigint,
  's72_5_both_clocks_marked_done'
);

select is(app.run_retention_sweep(), 0, 's72_5_sweep_idempotent');

select is(
  (select full_name from public.child where id = '6c000000-0000-4000-8000-000000000002'),
  'Bo Winter',
  'never_immature_clock_touched'
);

select throws_like(
  $$select app.anonymise_child('6c000000-0000-4000-8000-000000000002')$$,
  '%retention period has not ended%',
  'never_early_anonymisation_even_called_directly'
);

select throws_like(
  $$select app.anonymise_child('6c000000-0000-4000-8000-000000000003')$$,
  '%not discharged%',
  'never_enrolled_child_anonymised'
);

-- the hatch is CLOSED behind the anonymiser: immutability is back in force
select throws_ok(
  $$update public.care_log set payload = '{"text": "x"}' where child_id = '6c000000-0000-4000-8000-000000000001'$$,
  'care logs are never updated; record a correction',
  's72_5_escape_hatch_closes_behind_the_anonymiser'
);

select is(
  (select count(*) from public.audit_event
   where table_name = 'retention_clock'
     and row_id = '6c000000-0000-4000-8000-000000000001'
     and summary ->> 'action' = 'anonymised'),
  1::bigint,
  's72_5_anonymisation_audited'
);

select * from finish();
rollback;
