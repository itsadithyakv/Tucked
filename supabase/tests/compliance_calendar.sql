-- pgTAP: Parts 4 & 10 compliance calendar — every centre gets the standard
-- schedule automatically, completions are PIN-signed written records that
-- advance the cadence from the completion date, a recorded fire-drill
-- headcount completes the drill task by itself, and hazards stay on the
-- repair log (and in the DWR) until someone says what was fixed.

begin;

create extension if not exists pgtap with schema extensions;

select plan(17);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '1f000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sup@cal.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1f000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rece@cal.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1f000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'parent@cal.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('2f000000-0000-4000-8000-000000000001', 'Cal Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('3f100000-0000-4000-8000-000000000001', '2f000000-0000-4000-8000-000000000001', 'Cal Centre', 'CAL-1', '1 Cal St, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('4f000000-0000-4000-8000-000000000001', '1f000000-0000-4000-8000-000000000001', 'Sup Cal', 'sup@cal.local'),
  ('4f000000-0000-4000-8000-000000000002', '1f000000-0000-4000-8000-000000000002', 'Rece Cal', 'rece@cal.local'),
  ('4f000000-0000-4000-8000-000000000003', '1f000000-0000-4000-8000-000000000003', 'Parent Cal', 'parent@cal.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('4f000000-0000-4000-8000-000000000001', '3f100000-0000-4000-8000-000000000001', 'supervisor', true),
  ('4f000000-0000-4000-8000-000000000002', '3f100000-0000-4000-8000-000000000001', 'rece', true),
  ('4f000000-0000-4000-8000-000000000003', '3f100000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('4f000000-0000-4000-8000-000000000001', '3f100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('4f000000-0000-4000-8000-000000000002', '3f100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

-- ── the schedule arrives with the centre ────────────────────────────────────
select is(
  (select count(*) from public.compliance_task where centre_id = '3f100000-0000-4000-8000-000000000001'),
  12::bigint,
  'part4_10_every_centre_gets_the_standard_schedule'
);

select is(
  (select active from public.compliance_task
   where centre_id = '3f100000-0000-4000-8000-000000000001' and slug = 'sleep_monitor_check'),
  false,
  's33_1_monitor_check_off_until_monitors_exist'
);

-- ── as the RECE (the daily playground check is a staff job) ─────────────────
select set_config('request.jwt.claims', '{"sub":"1f000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select ok(
  (select count(*) > 0 from public.compliance_task where centre_id = '3f100000-0000-4000-8000-000000000001'),
  'part10_care_staff_see_the_schedule'
);

select throws_like(
  $$select public.complete_compliance_task(
    (select id from public.compliance_task where centre_id = '3f100000-0000-4000-8000-000000000001' and slug = 'playground_daily'),
    '  ', null, '4f000000-0000-4000-8000-000000000002', '4242')$$,
  '%IS the written record%',
  'part10_completion_note_never_blank'
);

select throws_like(
  $$select public.complete_compliance_task(
    (select id from public.compliance_task where centre_id = '3f100000-0000-4000-8000-000000000001' and slug = 'playground_daily'),
    'x', (current_date + 1), '4f000000-0000-4000-8000-000000000002', '4242')$$,
  '%future%',
  'part10_no_future_dated_completions'
);

select lives_ok(
  $$select public.complete_compliance_task(
    (select id from public.compliance_task where centre_id = '3f100000-0000-4000-8000-000000000001' and slug = 'playground_daily'),
    'Walked the playground before opening; surfaces clear, no loose hardware, gate latch working.',
    null, '4f000000-0000-4000-8000-000000000002', '4242')$$,
  'part10_daily_playground_check_recorded'
);

select is(
  (select next_due_on from public.compliance_task
   where centre_id = '3f100000-0000-4000-8000-000000000001' and slug = 'playground_daily'),
  (current_date + 1),
  'part10_daily_cadence_advances_one_day'
);

select lives_ok(
  $$select public.complete_compliance_task(
    (select id from public.compliance_task where centre_id = '3f100000-0000-4000-8000-000000000001' and slug = 'fire_alarm_test'),
    'Alarm sounded on test; all pull stations checked; extinguisher gauges green.',
    null, '4f000000-0000-4000-8000-000000000002', '4242')$$,
  'part4_alarm_test_recorded'
);

select is(
  (select next_due_on from public.compliance_task
   where centre_id = '3f100000-0000-4000-8000-000000000001' and slug = 'fire_alarm_test'),
  (current_date + interval '1 month')::date,
  'part4_monthly_cadence_advances_one_month'
);

-- a fire-drill headcount completes the drill task by itself
select lives_ok(
  $$select public.record_headcount('3f100000-0000-4000-8000-000000000001', null, 'evacuation_drill', 9, 9, '[]'::jsonb, 'monthly drill', '4f000000-0000-4000-8000-000000000002', '4242')$$,
  'part4_drill_headcount_recorded'
);

select is(
  (select count(*) from public.compliance_completion cc
   join public.compliance_task t on t.id = cc.task_id
   where t.slug = 'fire_drill' and t.centre_id = '3f100000-0000-4000-8000-000000000001'),
  1::bigint,
  'part4_drill_headcount_completes_the_drill_task'
);

-- the repair log: hazard recorded, restricted, into the DWR, then resolved
select lives_ok(
  $$select public.record_compliance_issue('3f100000-0000-4000-8000-000000000001',
    (select id from public.compliance_task where centre_id = '3f100000-0000-4000-8000-000000000001' and slug = 'playground_daily'),
    'Swing chain worn through at the top link', 'Both swings taped off and out of use',
    '4f000000-0000-4000-8000-000000000002', '4242')$$,
  'part10_hazard_recorded_with_restriction'
);

select is(
  (select count(*)
   from public.daily_written_record dwr, jsonb_array_elements(dwr.refs) ref
   where dwr.centre_id = '3f100000-0000-4000-8000-000000000001'
     and ref ->> 'type' = 'premises_issue'),
  1::bigint,
  's37_hazard_cross_referenced_into_dwr'
);

select throws_like(
  $$select public.set_compliance_task_active(
    (select id from public.compliance_task where centre_id = '3f100000-0000-4000-8000-000000000001' and slug = 'sleep_monitor_check'),
    true, '4f000000-0000-4000-8000-000000000002', '4242')$$,
  '%centre leadership%',
  'part4_10_only_leadership_changes_the_schedule'
);

select lives_ok(
  $$select public.resolve_compliance_issue(
    (select id from public.compliance_issue where centre_id = '3f100000-0000-4000-8000-000000000001'),
    'Chain replaced by the contractor; both swings re-checked and reopened.',
    '4f000000-0000-4000-8000-000000000002', '4242')$$,
  'part10_hazard_resolved_with_what_was_fixed'
);

-- ── as the parent: none of this is a family surface ─────────────────────────
select set_config('request.jwt.claims', '{"sub":"1f000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select is(
  (select count(*) from public.compliance_task),
  0::bigint,
  'part4_10_families_see_no_schedule'
);

-- ── as owner: written records stay written ──────────────────────────────────
reset role;

select throws_like(
  $$delete from public.compliance_completion where true$$,
  '%append-only%',
  'never_completion_records_deleted'
);

select * from finish();
rollback;
