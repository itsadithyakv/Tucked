-- pgTAP: s. 72(1) record items and s. 73 consent — enrolment must complete
-- with every optional consent declined.

begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '15000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sup@ec.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '15000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent@ec.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('25000000-0000-4000-8000-000000000001', 'EC Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('3d000000-0000-4000-8000-000000000001', '25000000-0000-4000-8000-000000000001', 'EC Centre', 'EC-1', '1 EC St, Toronto', '07:30', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('3e000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('3f000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000001', 'Preschool room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('45000000-0000-4000-8000-000000000001', '15000000-0000-4000-8000-000000000001', 'Sup EC', 'sup@ec.local'),
  ('45000000-0000-4000-8000-000000000002', '15000000-0000-4000-8000-000000000002', 'Parent EC', 'parent@ec.local');
insert into public.person_role (person_id, centre_id, role, qualified) values
  ('45000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', 'supervisor', true),
  ('45000000-0000-4000-8000-000000000002', '3d000000-0000-4000-8000-000000000001', 'family_adult', false);
insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('45000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('65000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', 'EC Child', '2022-06-01', '2026-01-05', '3f000000-0000-4000-8000-000000000001');
insert into public.household (id, centre_id, name) values
  ('55000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001', 'EC Household');
insert into public.child_household (child_id, household_id, centre_id) values
  ('65000000-0000-4000-8000-000000000001', '55000000-0000-4000-8000-000000000001', '3d000000-0000-4000-8000-000000000001');
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('55000000-0000-4000-8000-000000000001', '45000000-0000-4000-8000-000000000002', '3d000000-0000-4000-8000-000000000001', 'parent', true, true);

-- ── as the parent (the invite flow) ─────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"15000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select is(
  public.enrolment_complete('65000000-0000-4000-8000-000000000001'),
  false,
  's72_1_enrolment_incomplete_until_items_answered'
);

select throws_ok(
  $$select public.complete_record_item('65000000-0000-4000-8000-000000000001', 'application', 'missing', '{}')$$,
  'an item is completed as provided, not applicable, or parent declined — never blank',
  's72_1_never_blank'
);

-- Complete every item: mostly provided; discharge is n/a while enrolled;
-- medication instructions declined by the parent — a recorded refusal counts.
select lives_ok(
  $$
  select public.complete_record_item('65000000-0000-4000-8000-000000000001', t,
    case t
      when 'discharge' then 'not_applicable'::public.record_item_status
      when 'medication_instructions' then 'parent_declined'::public.record_item_status
      else 'provided'::public.record_item_status
    end,
    case t
      when 'health_immunisation' then '{"allergies": ["peanut"], "conditions": [], "immunisation": "up to date"}'::jsonb
      else '{"note": "completed in test"}'::jsonb
    end)
  from unnest(enum_range(null::public.record_item_type)) as t
  $$,
  's72_1_parent_completes_all_items'
);

select is(
  (select count(*) from public.child_record_item
   where child_id = '65000000-0000-4000-8000-000000000001' and status = 'missing'),
  0::bigint,
  's72_1_no_item_left_blank'
);

-- still incomplete: required-for-care consent not yet given
select is(
  public.enrolment_complete('65000000-0000-4000-8000-000000000001'),
  false,
  's73_care_consent_still_required'
);

-- grant the one required consent, DECLINE every optional one
select lives_ok(
  $$
  select public.give_consent('65000000-0000-4000-8000-000000000001', t,
    'enrolment', case when t = 'care_required' then 'granted' else 'declined' end)
  from unnest(enum_range(null::public.consent_type)) as t
  $$,
  's73_all_optional_consents_declined'
);

select is(
  public.enrolment_complete('65000000-0000-4000-8000-000000000001'),
  true,
  's73_enrolment_completes_with_every_optional_consent_declined'
);

-- a consent decision can be reversed later; the old row is superseded, kept
select lives_ok(
  $$select public.give_consent('65000000-0000-4000-8000-000000000001', 'photo_internal', 'newsletter photos', 'granted')$$,
  's73_consent_reversible_later'
);

select is(
  (select count(*) from public.consent
   where child_id = '65000000-0000-4000-8000-000000000001' and consent_type = 'photo_internal'),
  2::bigint,
  's73_superseded_consent_rows_are_kept'
);

-- ── supervisor verifies ─────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"15000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select is(
  (select count(*) from public.verify_child_record('65000000-0000-4000-8000-000000000001', '45000000-0000-4000-8000-000000000001', '4242')),
  (select count(*) from unnest(enum_range(null::public.record_item_type)))::bigint,
  's72_1_supervisor_verifies_every_item'
);

-- ── owner: nothing deletable ────────────────────────────────────────────────
reset role;

select throws_like(
  $$delete from public.consent where true$$,
  '%append-only%',
  'never_consent_rows_deleted'
);

select * from finish();
rollback;
