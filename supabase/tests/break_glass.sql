-- pgTAP: s. 82(2) break-glass — staff and Ministry can always get in. The
-- properties that matter: the elevation is PIN-signed with a real reason,
-- READ-ONLY, loud (supervisors alerted, audit written), self-expiring, and
-- closable; and platform admins can always restore supervisor continuity.

begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '1d000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sup@bg.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1d000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rece@bg.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1d000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'parent@bg.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1d000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'admin@bg.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.platform_admin (email, added_by) values ('admin@bg.local', 'pgtap fixture');

insert into public.licensee (id, legal_name) values ('2d000000-0000-4000-8000-000000000001', 'BG Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('3d100000-0000-4000-8000-000000000001', '2d000000-0000-4000-8000-000000000001', 'BG Centre', 'BG-1', '1 BG St, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('4d000000-0000-4000-8000-000000000001', '1d000000-0000-4000-8000-000000000001', 'Sup BG', 'sup@bg.local'),
  ('4d000000-0000-4000-8000-000000000002', '1d000000-0000-4000-8000-000000000002', 'Rece BG', 'rece@bg.local'),
  ('4d000000-0000-4000-8000-000000000003', '1d000000-0000-4000-8000-000000000003', 'Parent BG', 'parent@bg.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('4d000000-0000-4000-8000-000000000001', '3d100000-0000-4000-8000-000000000001', 'supervisor', true),
  ('4d000000-0000-4000-8000-000000000002', '3d100000-0000-4000-8000-000000000001', 'rece', true),
  ('4d000000-0000-4000-8000-000000000003', '3d100000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('4d000000-0000-4000-8000-000000000001', '3d100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('4d000000-0000-4000-8000-000000000002', '3d100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

-- the supervisor-locked inspection surfaces a program advisor asks for
insert into public.credential (centre_id, person_id, credential_type, issued_on, expires_on, recorded_by)
values ('3d100000-0000-4000-8000-000000000001', '4d000000-0000-4000-8000-000000000001', 'vsc',
        (current_date - interval '1 year')::date, (current_date + interval '4 years')::date,
        '4d000000-0000-4000-8000-000000000001');

insert into public.serious_occurrence (centre_id, category, occurred_at, aware_at, description, reported_by)
values ('3d100000-0000-4000-8000-000000000001', 'unplanned_disruption', now() - interval '2 days', now() - interval '2 days',
        'Furnace failure closed the centre for one afternoon.', '4d000000-0000-4000-8000-000000000001');

-- ── as the RECE, before: the locked surfaces are locked ─────────────────────
select set_config('request.jwt.claims', '{"sub":"1d000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select is(
  (select count(*) from public.credential where person_id = '4d000000-0000-4000-8000-000000000001'),
  0::bigint,
  's82_2_staff_files_locked_before_break_glass'
);
select is((select count(*) from public.serious_occurrence), 0::bigint, 's82_2_occurrences_locked_before');
select is((select count(*) from public.audit_event), 0::bigint, 's82_2_audit_trail_locked_before');

select throws_like(
  $$select public.open_break_glass('3d100000-0000-4000-8000-000000000001', 'help', '4d000000-0000-4000-8000-000000000002', '4242')$$,
  '%needs a real reason%',
  's82_2_reason_required'
);

select lives_ok(
  $$select public.open_break_glass('3d100000-0000-4000-8000-000000000001',
    'Program advisor on site for a licensing visit; the supervisor is in hospital and unreachable.',
    '4d000000-0000-4000-8000-000000000002', '4242')$$,
  's82_2_care_staff_opens_break_glass'
);

select throws_ok(
  $$select public.open_break_glass('3d100000-0000-4000-8000-000000000001',
    'Second attempt while one is already running for this person.',
    '4d000000-0000-4000-8000-000000000002', '4242')$$,
  'you already have emergency access open',
  's82_2_no_stacking'
);

-- the inspection surfaces open, read-only
select is(
  (select count(*) from public.credential where person_id = '4d000000-0000-4000-8000-000000000001'),
  1::bigint,
  's82_2_staff_files_readable_during_break_glass'
);
select is((select count(*) from public.serious_occurrence), 1::bigint, 's82_2_occurrences_readable');
select ok((select count(*) > 0 from public.audit_event), 's82_2_audit_trail_readable');

-- …but READ-ONLY: no write anywhere is unlocked by it
select throws_ok(
  $$select public.file_serious_occurrence_ccls(
    (select id from public.serious_occurrence limit 1), 'SO-X', now(),
    '4d000000-0000-4000-8000-000000000002', '4242')$$,
  'serious occurrences are recorded by the supervisor, a designate, or the licensee',
  's82_2_break_glass_grants_no_writes'
);

-- ── the parent cannot open one ──────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1d000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select throws_ok(
  $$select public.open_break_glass('3d100000-0000-4000-8000-000000000001',
    'A parent should never be able to do this, however good the reason.',
    '4d000000-0000-4000-8000-000000000003', '4242')$$,
  'not authorised for this centre',
  's82_2_families_cannot_break_glass'
);

-- ── expiry and close ────────────────────────────────────────────────────────
reset role;
update public.break_glass_access set expires_at = now() - interval '1 minute'
  where person_id = '4d000000-0000-4000-8000-000000000002' and closed_at is null;

select set_config('request.jwt.claims', '{"sub":"1d000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*) from public.serious_occurrence), 0::bigint, 's82_2_access_expires_by_itself');

select lives_ok(
  $$select public.open_break_glass('3d100000-0000-4000-8000-000000000001',
    'Second inspection day; the supervisor is still away and records are needed again.',
    '4d000000-0000-4000-8000-000000000002', '4242')$$,
  's82_2_reopen_after_expiry'
);

-- the supervisor closes it early — and was alerted to BOTH opens
select set_config('request.jwt.claims', '{"sub":"1d000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select is(
  (select count(*) from public.notification
   where event_type = 'break_glass' and recipient_person_id = '4d000000-0000-4000-8000-000000000001'),
  2::bigint,
  's82_2_supervisor_alerted_on_every_open'
);

select lives_ok(
  $$select public.close_break_glass(
    (select id from public.break_glass_access where closed_at is null and expires_at > now()),
    '4d000000-0000-4000-8000-000000000001', '4242')$$,
  's82_2_leadership_closes_early'
);

select set_config('request.jwt.claims', '{"sub":"1d000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select is((select count(*) from public.serious_occurrence), 0::bigint, 's82_2_closed_means_closed');

-- the record of emergency access itself is permanent
select set_config('request.jwt.claims', '{"sub":"1d000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is((select count(*) from public.break_glass_access), 2::bigint, 's82_2_every_break_glass_on_permanent_record');

-- ── continuity: platform admin restores a supervisor ────────────────────────
select set_config('request.jwt.claims', '{"sub":"1d000000-0000-4000-8000-000000000004","role":"authenticated","email":"admin@bg.local"}', true);

select lives_ok(
  $$select public.admin_grant_supervisor('3d100000-0000-4000-8000-000000000001', 'Nadia Reyes', 'nadia@bg.example')$$,
  's82_2_platform_admin_restores_continuity'
);

select is(
  (select count(*) from public.person_role pr join public.person p on p.id = pr.person_id
   where pr.centre_id = '3d100000-0000-4000-8000-000000000001' and pr.role = 'supervisor'
     and pr.active and lower(p.email) = 'nadia@bg.example'),
  1::bigint,
  's82_2_new_supervisor_invited_and_active'
);

select * from finish();
rollback;
