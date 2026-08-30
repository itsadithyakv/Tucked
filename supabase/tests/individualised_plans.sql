-- pgTAP: individualised plans (ss. 39, 39.1, 52) and the posted allergy and
-- food-restriction list (s. 43(3)). The load-bearing rules: emergency content
-- can never be blank, no plan is active before a recorded parent agreement,
-- content is immutable (new versions supersede), and the allergy list stays
-- live and complete — draft plans included.

begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '1b000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sup@plan.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1b000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent@plan.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '1b000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'aunt@plan.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('2b000000-0000-4000-8000-000000000001', 'Plan Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('3e000000-0000-4000-8000-000000000001', '2b000000-0000-4000-8000-000000000001', 'Plan Centre', 'PLAN-1', '1 Plan St, Toronto', '07:30', '18:00');
insert into public.age_group (id, centre_id, preset, licensed_capacity) values
  ('3f000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000001', 'preschool', 24);
insert into public.room (id, centre_id, age_group_id, name) values
  ('4b000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000001', '3f000000-0000-4000-8000-000000000001', 'Plan Room');

insert into public.person (id, auth_user_id, full_name, email) values
  ('5b000000-0000-4000-8000-000000000001', '1b000000-0000-4000-8000-000000000001', 'Sup Plan', 'sup@plan.local'),
  ('5b000000-0000-4000-8000-000000000002', '1b000000-0000-4000-8000-000000000002', 'Parent Plan', 'parent@plan.local'),
  ('5b000000-0000-4000-8000-000000000003', '1b000000-0000-4000-8000-000000000003', 'Aunt Plan', 'aunt@plan.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('5b000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000001', 'supervisor', true),
  ('5b000000-0000-4000-8000-000000000002', '3e000000-0000-4000-8000-000000000001', 'family_adult', false),
  ('5b000000-0000-4000-8000-000000000003', '3e000000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('5b000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('6b000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000001', 'Plan Household');
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date, current_room_id) values
  ('7b000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000001', 'Mila Aziz', '2023-03-15', '2026-01-05', '4b000000-0000-4000-8000-000000000001'),
  ('7b000000-0000-4000-8000-000000000002', '3e000000-0000-4000-8000-000000000001', 'Otto Berg', '2023-05-15', '2026-01-05', '4b000000-0000-4000-8000-000000000001');
insert into public.child_household (child_id, household_id, centre_id) values
  ('7b000000-0000-4000-8000-000000000001', '6b000000-0000-4000-8000-000000000001', '3e000000-0000-4000-8000-000000000001');
-- the parent can consent; the aunt can view but NOT consent
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('6b000000-0000-4000-8000-000000000001', '5b000000-0000-4000-8000-000000000002', '3e000000-0000-4000-8000-000000000001', 'parent', true, true),
  ('6b000000-0000-4000-8000-000000000001', '5b000000-0000-4000-8000-000000000003', '3e000000-0000-4000-8000-000000000001', 'other', true, false);

-- ── as the supervisor ───────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select throws_like(
  $$select public.upsert_individualised_plan('3e000000-0000-4000-8000-000000000001','7b000000-0000-4000-8000-000000000001','anaphylaxis','Peanut allergy', '{}', 'Hives', 'EpiPen, 911, family', null, null, null, null, 'Parent Plan', '5b000000-0000-4000-8000-000000000001', '4242')$$,
  '%must name its allergens%',
  's39_anaphylaxis_plan_requires_allergens'
);

select throws_like(
  $$select public.upsert_individualised_plan('3e000000-0000-4000-8000-000000000001','7b000000-0000-4000-8000-000000000001','anaphylaxis','Peanut allergy', array['peanuts'], 'Hives', '', null, null, null, null, 'Parent Plan', '5b000000-0000-4000-8000-000000000001', '4242')$$,
  '%signs of a reaction and the emergency procedure%',
  's39_anaphylaxis_plan_requires_emergency_procedure'
);

select throws_like(
  $$select public.upsert_individualised_plan('3e000000-0000-4000-8000-000000000001','7b000000-0000-4000-8000-000000000001','medical_needs','Asthma', null, null, '', null, null, null, null, 'Parent Plan', '5b000000-0000-4000-8000-000000000001', '4242')$$,
  '%must include its emergency procedure%',
  's39_1_medical_plan_requires_emergency_procedure'
);

select throws_like(
  $$select public.upsert_individualised_plan('3e000000-0000-4000-8000-000000000001','7b000000-0000-4000-8000-000000000001','special_needs','Global developmental delay', null, null, null, null, null, '', null, 'Parent Plan', '5b000000-0000-4000-8000-000000000001', '4242')$$,
  '%must describe the supports%',
  's52_special_needs_plan_requires_supports'
);

select lives_ok(
  $$select public.upsert_individualised_plan('3e000000-0000-4000-8000-000000000001','7b000000-0000-4000-8000-000000000001','anaphylaxis','Anaphylaxis — peanut and egg allergy', array['peanuts','eggs'], 'Hives, facial swelling, wheeze', 'EpiPen to outer thigh, 911, family. Second dose after 5 minutes if needed.', 'Nut-free room; tables wiped', 'EpiPen in the room go-bag', null, null, 'Parent Plan (parent), Dr. Osei (allergist)', '5b000000-0000-4000-8000-000000000001', '4242')$$,
  's39_valid_anaphylaxis_plan_recorded'
);

select is(
  (select status from public.individualised_plan where child_id = '7b000000-0000-4000-8000-000000000001' and plan_type = 'anaphylaxis' and version = 1),
  'draft',
  's52_new_plan_starts_as_draft_awaiting_agreement'
);

select is(
  (select count(*) from public.notification
   where event_type = 'plan_agreement' and recipient_person_id = '5b000000-0000-4000-8000-000000000002'),
  1::bigint,
  's52_consenting_parent_asked_to_agree'
);

select is(
  (select count(*) from public.notification
   where event_type = 'plan_agreement' and recipient_person_id = '5b000000-0000-4000-8000-000000000003'),
  0::bigint,
  's52_non_consenting_member_not_asked'
);

-- the draft allergens already protect the child
select is(
  (select count(*) from public.allergy_list where child_id = '7b000000-0000-4000-8000-000000000001' and kind = 'anaphylaxis'),
  2::bigint,
  's43_3_draft_plan_allergens_already_on_the_list'
);

select lives_ok(
  $$select public.record_dietary_restriction('3e000000-0000-4000-8000-000000000001','7b000000-0000-4000-8000-000000000002','food_restriction','No pork','Family request','5b000000-0000-4000-8000-000000000001','4242')$$,
  's43_3_dietary_restriction_recorded'
);

select is(
  (select count(*) from public.allergy_list where centre_id = '3e000000-0000-4000-8000-000000000001'),
  3::bigint,
  's43_3_list_unions_plans_and_restrictions'
);

-- ── the parent agrees in-app ────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select lives_ok(
  $$select public.agree_individualised_plan((select id from public.individualised_plan where plan_type = 'anaphylaxis' and status = 'draft'))$$,
  's52_consenting_parent_agrees_in_app'
);

select is(
  (select (status = 'active' and parent_agreed_by = '5b000000-0000-4000-8000-000000000002' and agreement_method = 'in_app'
           and review_due_on = (current_date + interval '1 year')::date)
   from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1),
  true,
  's52_agreement_named_dated_and_review_scheduled'
);

-- ── the aunt (can_view, cannot consent) ─────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000003","role":"authenticated"}', true);

select is(
  (select count(*) from public.individualised_plan),
  1::bigint,
  's72_household_viewer_sees_the_childs_plan'
);

-- a second version to leave a draft for the aunt to (fail to) agree to
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select lives_ok(
  $$select public.upsert_individualised_plan('3e000000-0000-4000-8000-000000000001','7b000000-0000-4000-8000-000000000001','anaphylaxis','Anaphylaxis — peanut allergy (egg outgrown)', array['peanuts'], 'Hives, facial swelling, wheeze', 'EpiPen to outer thigh, 911, family.', null, 'EpiPen in the room go-bag', null, null, 'Parent Plan (parent), Dr. Osei (allergist)', '5b000000-0000-4000-8000-000000000001', '4242')$$,
  's39_new_version_supersedes'
);

select is(
  (select status from public.individualised_plan where plan_type = 'anaphylaxis' and version = 1),
  'superseded',
  's39_previous_version_kept_as_superseded'
);

select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select throws_ok(
  $$select public.agree_individualised_plan((select id from public.individualised_plan where plan_type = 'anaphylaxis' and status = 'draft'))$$,
  'only a consenting household adult can agree to this plan',
  's52_non_consenting_member_cannot_agree'
);

-- ── back as the supervisor: the signed-paper path ───────────────────────────
select set_config('request.jwt.claims', '{"sub":"1b000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select lives_ok(
  $$select public.record_plan_agreement((select id from public.individualised_plan where plan_type = 'anaphylaxis' and status = 'draft'), '5b000000-0000-4000-8000-000000000002', now(), '5b000000-0000-4000-8000-000000000001', '4242')$$,
  's52_signed_paper_agreement_recorded_by_staff'
);

-- ── as owner: immutability holds even where RLS does not apply ──────────────
reset role;

select throws_like(
  $$update public.individualised_plan set condition = 'edited' where plan_type = 'anaphylaxis' and version = 2$$,
  '%never edited%',
  'never_plan_content_edited'
);

select throws_like(
  $$delete from public.individualised_plan where true$$,
  '%append-only%',
  'never_plans_deleted'
);

select * from finish();
rollback;
