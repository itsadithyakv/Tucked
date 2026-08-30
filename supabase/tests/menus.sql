-- pgTAP: menus and feeding instructions (ss. 42–44). The load-bearing rules:
-- a posted menu is what parents see and is frozen (changes on the day are
-- substitutions, noted at the time, carrying what was planned), drafts stay
-- with staff, and infant/special-diet instructions come from a consenting
-- parent — never from staff alone.

begin;

create extension if not exists pgtap with schema extensions;

select plan(22);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'sup@menu.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'parent@menu.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'aunt@menu.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('21100000-0000-4000-8000-000000000001', 'Menu Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('31100000-0000-4000-8000-000000000001', '21100000-0000-4000-8000-000000000001', 'Menu Centre', 'MENU-1', '1 Menu St, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('41100000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'Sup Menu', 'sup@menu.local'),
  ('41100000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000002', 'Parent Menu', 'parent@menu.local'),
  ('41100000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000003', 'Aunt Menu', 'aunt@menu.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('41100000-0000-4000-8000-000000000001', '31100000-0000-4000-8000-000000000001', 'supervisor', true),
  ('41100000-0000-4000-8000-000000000002', '31100000-0000-4000-8000-000000000001', 'family_adult', false),
  ('41100000-0000-4000-8000-000000000003', '31100000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('41100000-0000-4000-8000-000000000001', '31100000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf')));

insert into public.household (id, centre_id, name) values
  ('51100000-0000-4000-8000-000000000001', '31100000-0000-4000-8000-000000000001', 'Menu Household');
insert into public.child (id, centre_id, full_name, date_of_birth, admission_date) values
  ('61100000-0000-4000-8000-000000000001', '31100000-0000-4000-8000-000000000001', 'Juno Menu', (current_date - interval '7 months')::date, '2026-01-05');
insert into public.child_household (child_id, household_id, centre_id) values
  ('61100000-0000-4000-8000-000000000001', '51100000-0000-4000-8000-000000000001', '31100000-0000-4000-8000-000000000001');
-- the parent may consent; the aunt may view only
insert into public.household_member (household_id, person_id, centre_id, relationship, can_view, can_consent) values
  ('51100000-0000-4000-8000-000000000001', '41100000-0000-4000-8000-000000000002', '31100000-0000-4000-8000-000000000001', 'parent', true, true),
  ('51100000-0000-4000-8000-000000000001', '41100000-0000-4000-8000-000000000003', '31100000-0000-4000-8000-000000000001', 'other', true, false);

-- ── as the supervisor: plan this week and next ──────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;

select throws_ok(
  $$select public.upsert_menu_item('31100000-0000-4000-8000-000000000001', (date_trunc('week', current_date) + interval '1 day')::date, 1, 'lunch', 'Pasta', '41100000-0000-4000-8000-000000000001', '4242')$$,
  '23514',
  null,
  's42_menu_weeks_start_on_monday'
);

select throws_like(
  $$select public.upsert_menu_item('31100000-0000-4000-8000-000000000001', date_trunc('week', current_date)::date, 1, 'lunch', '  ', '41100000-0000-4000-8000-000000000001', '4242')$$,
  '%needs a description%',
  's42_menu_item_never_blank'
);

select lives_ok(
  $$select public.upsert_menu_item('31100000-0000-4000-8000-000000000001', date_trunc('week', current_date)::date, extract(isodow from current_date)::int, 'lunch', 'Chicken and rice, steamed carrots, milk', '41100000-0000-4000-8000-000000000001', '4242')$$,
  's42_menu_planned_for_this_week'
);

select lives_ok(
  $$select public.upsert_menu_item('31100000-0000-4000-8000-000000000001', date_trunc('week', current_date)::date, extract(isodow from current_date)::int, 'snack_pm', 'Apple slices and cheese', '41100000-0000-4000-8000-000000000001', '4242')$$,
  's42_second_snack_planned'
);

select is(
  (select status from public.menu_week where week_start = date_trunc('week', current_date)::date),
  'draft',
  's42_new_week_starts_as_a_draft'
);

select throws_like(
  $$select public.post_menu_week('31100000-0000-4000-8000-000000000001', (date_trunc('week', current_date) + interval '2 weeks')::date, '41100000-0000-4000-8000-000000000001', '4242')$$,
  '%no menu planned for that week%',
  's42_cannot_post_an_unplanned_week'
);

select lives_ok(
  $$select public.post_menu_week('31100000-0000-4000-8000-000000000001', date_trunc('week', current_date)::date, '41100000-0000-4000-8000-000000000001', '4242')$$,
  's42_week_posted_where_parents_can_see_it'
);

select throws_like(
  $$select public.upsert_menu_item('31100000-0000-4000-8000-000000000001', date_trunc('week', current_date)::date, extract(isodow from current_date)::int, 'lunch', 'Something else entirely', '41100000-0000-4000-8000-000000000001', '4242')$$,
  '%record a substitution%',
  's42_posted_menu_is_frozen'
);

-- the following week is planned too (s. 42 wants both), still a draft
select lives_ok(
  $$select public.upsert_menu_item('31100000-0000-4000-8000-000000000001', (date_trunc('week', current_date) + interval '1 week')::date, 1, 'lunch', 'Shepherd''s pie with peas', '41100000-0000-4000-8000-000000000001', '4242')$$,
  's42_following_week_planned'
);

-- ── substitutions are noted at the time ─────────────────────────────────────
select throws_like(
  $$select public.record_menu_substitution('31100000-0000-4000-8000-000000000001', (current_date + 1), 'lunch', 'Soup', 'Delivery late', '41100000-0000-4000-8000-000000000001', '4242')$$,
  '%noted at the time%',
  's42_substitutions_never_recorded_ahead_of_the_day'
);

select throws_like(
  $$select public.record_menu_substitution('31100000-0000-4000-8000-000000000001', current_date, 'lunch', 'Soup and bread', '  ', '41100000-0000-4000-8000-000000000001', '4242')$$,
  '%what was served instead and why%',
  's42_substitution_needs_a_reason'
);

select lives_ok(
  $$select public.record_menu_substitution('31100000-0000-4000-8000-000000000001', current_date, 'lunch', 'Vegetable soup with bread and milk', 'Chicken delivery did not arrive', '41100000-0000-4000-8000-000000000001', '4242')$$,
  's42_substitution_recorded_on_the_day'
);

select is(
  (select planned from public.menu_substitution where served_on = current_date and meal = 'lunch'),
  'Chicken and rice, steamed carrots, milk',
  's42_substitution_snapshots_what_was_planned'
);

-- ── s. 44: written instructions from the parent ─────────────────────────────
select throws_like(
  $$select public.record_feeding_instruction('31100000-0000-4000-8000-000000000001', '61100000-0000-4000-8000-000000000001', 'infant_feeding', '120 ml expressed milk on waking', '41100000-0000-4000-8000-000000000003', '41100000-0000-4000-8000-000000000001', '4242')$$,
  '%consenting household member%',
  's44_instructions_come_from_a_consenting_parent'
);

select lives_ok(
  $$select public.record_feeding_instruction('31100000-0000-4000-8000-000000000001', '61100000-0000-4000-8000-000000000001', 'infant_feeding', '120 ml expressed milk on waking; purée at 11:30; no cow''s milk', '41100000-0000-4000-8000-000000000002', '41100000-0000-4000-8000-000000000001', '4242')$$,
  's44_infant_feeding_instructions_recorded'
);

select lives_ok(
  $$select public.record_feeding_instruction('31100000-0000-4000-8000-000000000001', '61100000-0000-4000-8000-000000000001', 'infant_feeding', '150 ml expressed milk on waking; purée at 11:30', '41100000-0000-4000-8000-000000000002', '41100000-0000-4000-8000-000000000001', '4242')$$,
  's44_updated_instructions_supersede'
);

select is(
  (select count(*) from public.feeding_instruction
   where child_id = '61100000-0000-4000-8000-000000000001' and ended_at is null),
  1::bigint,
  's44_one_live_instruction_per_child_and_kind'
);

-- ── as the parent: the posted menu IS the posting ───────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select is(
  (select count(*) from public.menu_item),
  2::bigint,
  's42_families_see_the_posted_menu'
);

select is(
  (select count(*) from public.menu_week),
  1::bigint,
  's42_families_never_see_next_weeks_draft'
);

select is(
  (select count(*) from public.menu_substitution),
  1::bigint,
  's42_families_see_the_days_substitution'
);

-- the aunt (view-only household member) sees the child's written instructions
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select is(
  (select count(*) from public.feeding_instruction where ended_at is null),
  1::bigint,
  's44_household_viewer_sees_the_instructions'
);

-- ── as owner: menus are kept, not deleted (30-day floor cleared) ────────────
reset role;

select throws_like(
  $$delete from public.menu_week where true$$,
  '%append-only%',
  's42_posted_menus_never_deleted'
);

select * from finish();
rollback;
