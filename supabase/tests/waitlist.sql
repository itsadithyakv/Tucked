-- pgTAP: the waiting list (s. 75.1). The load-bearing rules: no fee or
-- deposit can be charged for a place (the schema has nowhere to put one); a
-- family learns its own position and nothing about anyone else; the published
-- order is the actual order and nobody is quietly moved up; and a closed
-- enquiry's contact details are dropped after twelve months while the
-- fairness record survives.

begin;

create extension if not exists pgtap with schema extensions;

select plan(38);

-- ── fixture ─────────────────────────────────────────────────────────────────
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000e1', 'authenticated', 'authenticated', 'sup@wl.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000e2', 'authenticated', 'authenticated', 'edu@wl.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-4000-8000-0000000000e3', 'authenticated', 'authenticated', 'sib@wl.local', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.licensee (id, legal_name) values ('21300000-0000-4000-8000-000000000001', 'Waitlist Licensee');
insert into public.centre (id, licensee_id, name, licence_number, address, opens_at, closes_at) values
  ('31300000-0000-4000-8000-000000000001', '21300000-0000-4000-8000-000000000001', 'Waitlist Centre', 'WL-1', '1 Queue Lane, Toronto', '07:30', '18:00');

insert into public.person (id, auth_user_id, full_name, email) values
  ('41300000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000e1', 'Sup Queue', 'sup@wl.local'),
  ('41300000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000e2', 'Edu Queue', 'edu@wl.local'),
  ('41300000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-0000000000e3', 'Sib Parent', 'sib@wl.local');

insert into public.person_role (person_id, centre_id, role, qualified) values
  ('41300000-0000-4000-8000-000000000001', '31300000-0000-4000-8000-000000000001', 'supervisor', true),
  ('41300000-0000-4000-8000-000000000002', '31300000-0000-4000-8000-000000000001', 'rece', true),
  ('41300000-0000-4000-8000-000000000003', '31300000-0000-4000-8000-000000000001', 'family_adult', false);

insert into public.staff_pin (person_id, centre_id, pin_hash) values
  ('41300000-0000-4000-8000-000000000001', '31300000-0000-4000-8000-000000000001', extensions.crypt('4242', extensions.gen_salt('bf'))),
  ('41300000-0000-4000-8000-000000000002', '31300000-0000-4000-8000-000000000001', extensions.crypt('7171', extensions.gen_salt('bf')));

-- ── no fee, structurally ────────────────────────────────────────────────────
-- Not a policy we follow — a shape the schema cannot take. This fails the day
-- somebody adds a column that could hold a deposit.
select is(
  (select count(*) from information_schema.columns
   where table_schema = 'public'
     and table_name like 'waitlist%'
     and (column_name ~* 'fee|deposit|amount|price|payment|paid|charge|invoice'
          or data_type in ('money', 'numeric'))),
  0::bigint,
  's75_1_no_waitlist_column_can_hold_a_fee'
);

-- ── as the supervisor ───────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;

select throws_like(
  $$select public.join_waitlist('31300000-0000-4000-8000-000000000001', 'Past Child', '2024-05-01', 'toddler', (current_date - 10), 'A Parent', 'a@wl.local', null, 'general', null, '41300000-0000-4000-8000-000000000001', '4242')$$,
  '%start date in the past%',
  's75_1_a_start_date_in_the_past_is_not_a_place'
);

select throws_like(
  $$select public.join_waitlist('31300000-0000-4000-8000-000000000001', 'No Contact', '2024-05-01', 'toddler', (current_date + 60), 'A Parent', null, null, 'general', null, '41300000-0000-4000-8000-000000000001', '4242')$$,
  '%email or a phone number%',
  's75_1_a_contact_route_is_required'
);

select throws_like(
  $$select public.join_waitlist('31300000-0000-4000-8000-000000000001', 'Queue Jumper', '2024-05-01', 'toddler', (current_date + 60), 'A Parent', 'jump@wl.local', null, 'sibling', '  ', '41300000-0000-4000-8000-000000000001', '4242')$$,
  '%above the date order is recorded with a reason%',
  's75_1_placing_a_family_above_the_date_order_needs_a_reason'
);

select lives_ok(
  $$select public.join_waitlist('31300000-0000-4000-8000-000000000001', 'Ada Green', '2024-05-01', 'toddler', (current_date + 60), 'Nia Green', 'nia@wl.local', null, 'general', null, '41300000-0000-4000-8000-000000000001', '4242')$$,
  's75_1_first_family_joins_the_list'
);

select lives_ok(
  $$select public.join_waitlist('31300000-0000-4000-8000-000000000001', 'Bo Hill', '2024-07-14', 'toddler', (current_date + 90), 'Ken Hill', null, '416-555-0132', 'general', null, '41300000-0000-4000-8000-000000000001', '4242')$$,
  's75_1_second_family_joins_the_list'
);

-- a sibling of an enrolled child joins last and, per the published policy,
-- goes to the front — with the reason on the record
select lives_ok(
  $$select public.join_waitlist('31300000-0000-4000-8000-000000000001', 'Cy Frost', '2024-03-02', 'toddler', (current_date + 30), 'Sib Parent', 'sib@wl.local', null, 'sibling', 'Older sibling enrolled in the preschool room', '41300000-0000-4000-8000-000000000001', '4242')$$,
  's75_1_a_sibling_joins_the_list'
);

select results_eq(
  $$select child_name, list_position from public.waitlist_position order by list_position$$,
  $$values ('Cy Frost', 1), ('Ada Green', 2), ('Bo Hill', 3)$$,
  's75_1_position_follows_the_published_order'
);

-- an entry that has a person account here is tied to them
select is(
  (select contact_person_id from public.waitlist_entry where child_name = 'Cy Frost'),
  '41300000-0000-4000-8000-000000000003'::uuid,
  's75_1_an_entry_is_tied_to_a_parent_who_already_has_an_account'
);

-- ── the order cannot be fiddled with ────────────────────────────────────────
-- as the table owner, so RLS is not what is doing the refusing here
reset role;

select throws_like(
  $$update public.waitlist_entry set joined_at = now() - interval '1 year' where child_name = 'Bo Hill'$$,
  '%never moves%',
  's75_1_the_moment_a_family_joined_never_moves'
);

select throws_like(
  $$update public.waitlist_entry set priority = 'sibling' where child_name = 'Bo Hill'$$,
  '%recorded with a reason%',
  's75_1_priority_never_changes_without_a_reason'
);

-- ── as the educator: not their call ─────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000e2","role":"authenticated"}', true);

select throws_like(
  $$select public.set_waitlist_priority((select id from public.waitlist_entry where child_name = 'Bo Hill'), 'sibling', 'A friend of the family', '41300000-0000-4000-8000-000000000002', '7171')$$,
  '%only centre leadership%',
  's75_1_only_leadership_moves_a_family_up_the_list'
);

-- ── back to the supervisor ──────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);

select lives_ok(
  $$select public.set_waitlist_priority((select id from public.waitlist_entry where child_name = 'Bo Hill'), 'subsidy_referral', 'Referred by Toronto Children''s Services under the fee subsidy agreement', '41300000-0000-4000-8000-000000000001', '4242')$$,
  's75_1_leadership_records_a_subsidy_referral'
);

select is(
  (select detail from public.waitlist_event
   where event_type = 'priority_changed'
     and entry_id = (select id from public.waitlist_entry where child_name = 'Bo Hill')),
  'Moved to subsidy referral — Referred by Toronto Children''s Services under the fee subsidy agreement',
  's75_1_moving_a_family_up_is_on_the_permanent_record'
);

select results_eq(
  $$select child_name, list_position from public.waitlist_position order by list_position$$,
  $$values ('Cy Frost', 1), ('Bo Hill', 2), ('Ada Green', 3)$$,
  's75_1_the_list_reorders_by_the_published_rule'
);

-- ── the family's own view ───────────────────────────────────────────────────
-- fix the codes so the anonymous tests can quote them
reset role;
update public.waitlist_entry set access_code = 'CODEADA0' where child_name = 'Ada Green';
update public.waitlist_entry set access_code = 'CODECY00' where child_name = 'Cy Frost';

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select is(
  (select count(*) from public.waitlist_entry),
  0::bigint,
  's75_1_an_enquiring_family_never_reads_the_list'
);

select results_eq(
  $$select child_first_name, list_position, families_ahead, list_length
    from public.waitlist_self_check('CODEADA0')$$,
  $$values ('Ada', 3, 2, 3)$$,
  's75_1_a_family_reads_its_own_position_and_only_that'
);

select results_eq(
  $$select list_position from public.waitlist_self_check('code-ada0')$$,
  $$values (3)$$,
  's75_1_the_code_tolerates_dashes_and_lower_case'
);

select is(
  (select count(*) from public.waitlist_self_check('NOTACODE')),
  0::bigint,
  's75_1_a_wrong_code_reveals_nothing_at_all'
);

-- ── the same discretion for a family who does have an account ───────────────
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000e3","role":"authenticated"}', true);

-- The ranked view only ever ranks rows the caller can see, so a family
-- reading it would be told they are first every time. It refuses them.
select is(
  (select count(*) from public.waitlist_position),
  0::bigint,
  's75_1_a_family_is_never_told_they_are_first_by_a_view_that_cannot_see_the_list'
);

select results_eq(
  $$select child_name, list_position, families_ahead, list_length from public.my_waitlist_positions()$$,
  $$values ('Cy Frost', 1, 0, 3)$$,
  's75_1_a_signed_in_parent_sees_their_true_position'
);

-- ── offering a place ────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);

select throws_like(
  $$select public.offer_waitlist_place((select id from public.waitlist_entry where child_name = 'Cy Frost'), (current_date - 1), '41300000-0000-4000-8000-000000000001', '4242')$$,
  '%date in the future to respond by%',
  's75_1_an_offer_gives_the_family_a_date_to_answer_by'
);

select lives_ok(
  $$select public.offer_waitlist_place((select id from public.waitlist_entry where child_name = 'Cy Frost'), (current_date + 7), '41300000-0000-4000-8000-000000000001', '4242')$$,
  's75_1_a_place_is_offered_to_the_family_at_the_top'
);

select is(
  (select list_position from public.waitlist_position where child_name = 'Cy Frost'),
  1,
  's75_1_a_family_holding_an_offer_still_holds_its_place'
);

select throws_like(
  $$select public.record_waitlist_response((select id from public.waitlist_entry where child_name = 'Ada Green'), 'accepted', null, '41300000-0000-4000-8000-000000000001', '4242')$$,
  '%no offer outstanding%',
  's75_1_only_a_family_with_an_offer_can_answer_it'
);

select lives_ok(
  $$select public.record_waitlist_response((select id from public.waitlist_entry where child_name = 'Cy Frost'), 'accepted', 'Accepted by phone', '41300000-0000-4000-8000-000000000001', '4242')$$,
  's75_1_the_family_accepts_the_place'
);

select is(
  (select closed_at is not null from public.waitlist_entry where child_name = 'Cy Frost'),
  true,
  's75_1_accepting_closes_the_entry'
);

select results_eq(
  $$select child_name, list_position from public.waitlist_position order by list_position$$,
  $$values ('Bo Hill', 1), ('Ada Green', 2)$$,
  's75_1_an_accepted_family_leaves_the_open_list'
);

-- ── as the parent who does have an account ──────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"20000000-0000-4000-8000-0000000000e3","role":"authenticated"}', true);

select is(
  (select count(*) from public.waitlist_entry),
  1::bigint,
  's75_1_a_parent_with_an_account_sees_only_their_own_entry'
);

-- ── retention: keep the fairness record, drop the phone number ──────────────
reset role;

select throws_like(
  $$select app.anonymise_waitlist_entry((select id from public.waitlist_entry where child_name = 'Ada Green'))$$,
  '%never before%',
  's75_1_an_open_enquiry_is_never_anonymised'
);

select throws_like(
  $$select app.anonymise_waitlist_entry((select id from public.waitlist_entry where child_name = 'Cy Frost'))$$,
  '%never before%',
  's75_1_a_recently_closed_enquiry_is_never_anonymised'
);

update public.waitlist_entry
set closed_at = now() - interval '13 months'
where child_name = 'Cy Frost';

select lives_ok(
  $$select app.anonymise_waitlist_entry((select id from public.waitlist_entry where child_name = 'Cy Frost'))$$,
  's75_1_a_long_closed_enquiry_is_anonymised'
);

select results_eq(
  $$select contact_name, contact_email, contact_phone, contact_person_id, priority, status
    from public.waitlist_entry where child_name = 'Closed enquiry'$$,
  $$values ('Closed enquiry', null::text, null::text, null::uuid, 'sibling', 'accepted')$$,
  's75_1_anonymisation_keeps_the_fairness_record_and_drops_the_contact'
);

set local role anon;
select is(
  (select count(*) from public.waitlist_self_check('CODECY00')),
  0::bigint,
  's75_1_an_anonymised_code_stops_working'
);

-- ── the nightly sweep ───────────────────────────────────────────────────────
reset role;
select app.run_waitlist_sweep();

-- a family still waiting is untouched by it
select results_eq(
  $$select contact_name, anonymised_at is null from public.waitlist_entry where child_name = 'Ada Green'$$,
  $$values ('Nia Green', true)$$,
  's75_1_the_nightly_sweep_touches_nothing_that_is_not_due'
);

update public.waitlist_entry
set status = 'withdrawn', closed_at = now() - interval '13 months'
where child_name = 'Bo Hill';

select app.run_waitlist_sweep();

select is(
  (select count(*) from public.waitlist_entry
   where child_name = 'Bo Hill' or (contact_phone = '416-555-0132' and anonymised_at is null)),
  0::bigint,
  's75_1_the_nightly_sweep_anonymises_what_is_due'
);


-- ── nothing vanishes ────────────────────────────────────────────────────────
reset role;

select throws_like(
  $$delete from public.waitlist_entry where true$$,
  '%append-only%',
  's75_1_entries_are_never_deleted'
);

select throws_like(
  $$update public.waitlist_event set detail = 'Nothing to see' where true$$,
  '%append-only%',
  's75_1_the_history_of_the_list_is_never_rewritten'
);

select * from finish();
rollback;
