-- 0039 the daily story actually reaches a family.
--
-- Everything about the story worked except the part that matters. The table,
-- the RLS, the one-per-person-per-day push rule in app.notifications_to_push,
-- the family Home tab that renders the educator's note above the draft — all
-- built, all tested. And `publish_story` had NO CALLER anywhere: not a screen,
-- not a cron, not a trigger. Every family would have opened the app each
-- evening to the empty state, which reads "The day's story arrives at pick-up
-- time." It never did.
--
-- WHERE THE COMPOSER LIVES. In SQL, here, for the same reason app.dwr_compose
-- does: the story is arithmetic over the day's own rows, and the thing that
-- composes it has to run when no client is present. packages/domain had a
-- buildStory() that nothing called — the identical situation as the daily
-- record's second drafter, which was deleted rather than kept in parallel.
-- Its voice is ported here line for line and its three tests are ported to
-- pgTAP. One implementation, not two.
--
-- WHEN IT PUBLISHES. At pick-up, because that is what the family screen has
-- always promised. A `depart` publishes that child's story — the day is
-- genuinely over for them, and the story lands as the parent is collecting.
-- A nightly sweep is the floor for a child whose departure was never
-- recorded, so a forgotten sign-out costs a family a late story rather than
-- no story.
--
-- WHAT NEVER HAPPENS. The story is a courtesy letter, not a regulated record,
-- so it may be composed and published with no human — §9.14's "a human closes
-- it" belongs to the DAILY WRITTEN RECORD, which is untouched here. And the
-- publish trigger can never block a departure; see app.story_on_depart.

-- ── 12-hour times, the way a family reads them ──────────────────────────────
create or replace function app.twelve_hour(p_at timestamptz, p_tz text)
returns text
language sql immutable
as $$
  select to_char(p_at at time zone p_tz, 'FMHH12:MI')
    || case when extract(hour from p_at at time zone p_tz) >= 12 then ' p.m.' else ' a.m.' end
$$;

-- ── the composer ────────────────────────────────────────────────────────────
-- One calm, specific letter, assembled from the day's own rows. Template
-- drafted and deterministic: the same day composes to the same words. No model
-- is involved, here or anywhere near a record.
create or replace function app.story_compose(p_child uuid, p_date date)
returns text
language plpgsql stable security definer
set search_path = public
as $$
declare
  tz text;
  centre uuid;
  name text;
  parts text[] := '{}';
  outdoor_minutes integer := 0;
  skipped text;
  acts text[];
  m record;
  n record;
  photos integer := 0;
  illness_reason text;
begin
  select c.centre_id, split_part(c.full_name, ' ', 1), ce.timezone
    into centre, name, tz
  from public.child c join public.centre ce on ce.id = c.centre_id
  where c.id = p_child;
  if name is null then
    return null;
  end if;

  -- Outdoor minutes come from the s. 47 measurement rather than being counted
  -- again here, so the story and the compliance record cannot disagree.
  select o.minutes_outside into outdoor_minutes
  from public.outdoor_by_child(centre, p_date) o
  where o.child_id = p_child;
  outdoor_minutes := coalesce(outdoor_minutes, 0);

  select s.reason into skipped
  from public.outdoor_shortfall s
  join public.attendance_event ae
    on ae.room_id = s.room_id and ae.child_id = p_child and ae.attendance_date = p_date
  where s.centre_id = centre and s.outdoor_date = p_date
  limit 1;

  select array_agg(cl.payload ->> 'description' order by cl.logged_at)
    into acts
  from public.care_log cl
  where cl.child_id = p_child and cl.log_date = p_date and cl.log_type = 'activity'
    and not exists (select 1 from public.care_log x where x.correction_of = cl.id);
  acts := coalesce(acts, '{}');

  select count(*)::integer into photos
  from public.care_log cl
  where cl.child_id = p_child and cl.log_date = p_date and cl.log_type = 'photo'
    and not exists (select 1 from public.care_log x where x.correction_of = cl.id);

  -- ── the opening line ──
  if outdoor_minutes > 0 then
    parts := array_append(parts,
      case when array_length(acts, 1) >= 1
        then 'We spent time outside today — ' || acts[1] || '.'
        else 'We spent ' || outdoor_minutes || ' minutes outside today.'
      end);
  elsif skipped is not null then
    parts := array_append(parts, 'We stayed in today (' || skipped || ').');
  elsif array_length(acts, 1) >= 1 then
    parts := array_append(parts, 'Today ' || name || ' enjoyed ' || acts[1] || '.');
  end if;

  -- ── meals, in the order they were eaten ──
  for m in
    select cl.payload ->> 'meal' as meal, cl.payload ->> 'eaten' as eaten
    from public.care_log cl
    where cl.child_id = p_child and cl.log_date = p_date and cl.log_type = 'meal'
      and not exists (select 1 from public.care_log x where x.correction_of = cl.id)
    order by cl.logged_at
  loop
    parts := array_append(parts,
      name || ' '
      || case m.eaten
           when 'none' then 'was not interested in'
           when 'some' then 'ate some of'
           when 'most' then 'ate most of'
           when 'all'  then 'finished'
         end
      || ' '
      || case m.meal
           when 'breakfast' then 'breakfast'
           when 'lunch' then 'lunch'
           when 'snack_am' then 'morning snack'
           when 'snack_pm' then 'afternoon snack'
         end
      || '.');
  end loop;

  -- ── rest ──
  for n in
    with naps as (
      select cl.logged_at, cl.log_type,
        lead(cl.logged_at) over (order by cl.logged_at, cl.id) as next_at,
        lead(cl.log_type) over (order by cl.logged_at, cl.id) as next_type
      from public.care_log cl
      where cl.child_id = p_child and cl.log_date = p_date
        and cl.log_type in ('nap_start', 'nap_end')
        and not exists (select 1 from public.care_log x where x.correction_of = cl.id)
    )
    select naps.logged_at as started,
           case when naps.next_type = 'nap_end' then naps.next_at end as ended
    from naps where naps.log_type = 'nap_start'
  loop
    parts := array_append(parts,
      case when n.ended is not null
        then 'Rest time went ' || app.twelve_hour(n.started, tz) || ' to ' || app.twelve_hour(n.ended, tz) || '.'
        else name || ' settled for a rest at ' || app.twelve_hour(n.started, tz) || '.'
      end);
  end loop;

  -- ── the rest of the day ──
  if array_length(acts, 1) > 1 then
    parts := array_append(parts,
      'Also today: ' || array_to_string(acts[2:array_length(acts, 1)], '; ') || '.');
  end if;

  if photos = 1 then
    parts := array_append(parts, 'There is one new photo from today.');
  elsif photos > 1 then
    parts := array_append(parts, 'There are ' || photos || ' new photos from today.');
  end if;

  -- ── a child who went home unwell ──
  -- Said plainly, and said LAST. The family already had a Now alert with the
  -- reason and what has to be true before the child comes back; a story that
  -- carried on as though the day had been ordinary would be worse than one
  -- that says what happened.
  select he.exclusion_reason into illness_reason
  from public.health_exclusion he
  where he.child_id = p_child
    and (he.onset_at at time zone tz)::date = p_date
  order by he.onset_at desc
  limit 1;

  if illness_reason is not null then
    parts := array_append(parts,
      name || ' went home unwell today (' || illness_reason
      || '). There is more in the alert we sent.');
  elsif array_length(parts, 1) is null then
    parts := array_append(parts, name || ' had a steady, quiet day with us.');
  end if;

  return array_to_string(parts, ' ');
end;
$$;

-- ── publishing ──────────────────────────────────────────────────────────────
-- The one implementation. The RPCs below and both automatic paths all land
-- here, so a story published by a cron and a story published by an educator
-- are the same row built the same way.
create or replace function app.publish_story_row(
  p_child uuid,
  p_date date,
  p_recorder uuid default null,
  p_note text default null,
  p_set_note boolean default false
) returns public.story
language plpgsql security definer
set search_path = public
as $$
declare
  centre uuid;
  result public.story;
begin
  select ch.centre_id into centre from public.child ch where ch.id = p_child;
  if centre is null then raise exception 'child not found'; end if;

  insert into public.story (
    centre_id, child_id, story_date, draft_text, educator_note, published_at, published_by
  ) values (
    centre, p_child, p_date, coalesce(app.story_compose(p_child, p_date), ''),
    case when p_set_note then p_note else null end, now(), p_recorder
  )
  on conflict (child_id, story_date) do update set
    draft_text = excluded.draft_text,
    -- the human's words are never overwritten by a recomposition; only an
    -- explicit note edit changes them
    educator_note = case when p_set_note then excluded.educator_note
                         else public.story.educator_note end,
    published_at = coalesce(public.story.published_at, now()),
    published_by = coalesce(excluded.published_by, public.story.published_by)
  returning * into result;

  -- One Later notification per viewing household adult: the single daily story
  -- push, and only if this is the first publish today.
  insert into public.notification (
    centre_id, child_id, recipient_person_id, channel, event_type, title, body, created_by
  )
  select centre, p_child, hm.person_id, 'later', 'story',
         'Today''s story', 'The day''s story is ready.', p_recorder
  from public.child_household ch
  join public.household_member hm on hm.household_id = ch.household_id
  where ch.child_id = p_child and hm.revoked_at is null and hm.can_view
    and not exists (
      select 1 from public.notification n
      where n.child_id = p_child and n.event_type = 'story'
        and n.recipient_person_id = hm.person_id
        and n.created_at::date = current_date
    );

  return result;
end;
$$;

-- ── at pick-up ──────────────────────────────────────────────────────────────
-- A departure publishes that child's story. The day is over for them and the
-- parent is standing at the door.
--
-- THIS TRIGGER CAN NEVER BLOCK A DEPARTURE. It runs inside the sign-out
-- transaction, and a child being released to their parent must not depend on
-- a story composing cleanly. Anything that goes wrong here is swallowed on
-- purpose and picked up by the nightly sweep instead — a late story is a
-- disappointment, a sign-out that will not complete is an incident.
create or replace function app.story_on_depart()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.event_type = 'depart' then
    begin
      perform app.publish_story_row(new.child_id, new.attendance_date, new.recorded_by);
    exception when others then
      raise notice 'story not published for % on %: %', new.child_id, new.attendance_date, sqlerrm;
    end;
  end if;
  return new;
end;
$$;

create trigger story_on_depart
  after insert on public.attendance_event
  for each row execute function app.story_on_depart();

-- ── the floor ───────────────────────────────────────────────────────────────
-- A child whose sign-out was never recorded still had a day. Once the centre
-- has closed, anyone who arrived today and has no published story gets one.
create or replace function app.publish_daily_stories()
returns integer
language plpgsql security definer
set search_path = public
as $$
declare
  c record;
  kid record;
  local_date date;
  published integer := 0;
begin
  for c in select id, timezone, closes_at from public.centre loop
    local_date := (now() at time zone c.timezone)::date;
    continue when (now() at time zone c.timezone)::time < c.closes_at;

    for kid in
      select distinct ae.child_id
      from public.attendance_event ae
      where ae.centre_id = c.id
        and ae.attendance_date = local_date
        and ae.event_type = 'arrive'
        and not exists (
          select 1 from public.attendance_event corr where corr.correction_of = ae.id
        )
        and not exists (
          select 1 from public.story s
          where s.child_id = ae.child_id and s.story_date = local_date
            and s.published_at is not null
        )
    loop
      begin
        perform app.publish_story_row(kid.child_id, local_date, null);
        published := published + 1;
      exception when others then
        raise notice 'story sweep skipped % on %: %', kid.child_id, local_date, sqlerrm;
      end;
    end loop;
  end loop;
  return published;
end;
$$;

select cron.schedule('daily-stories', '35 * * * *', $$select app.publish_daily_stories()$$);

-- ── what an educator can do ─────────────────────────────────────────────────
-- The note is the only part of the story a human writes, and it is the part a
-- family reads first. Saving one publishes the story if it has not gone yet,
-- so an educator writing at 3 p.m. does not have to also remember to publish.
create or replace function public.save_story_note(
  p_child uuid,
  p_date date,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns public.story
language plpgsql security definer
set search_path = public
as $$
declare
  centre uuid;
  recorder uuid;
begin
  select ch.centre_id into centre from public.child ch where ch.id = p_child;
  if centre is null then raise exception 'child not found'; end if;
  recorder := app.resolve_recorder(centre, p_recorder, p_pin);
  return app.publish_story_row(
    p_child, p_date, recorder, nullif(trim(coalesce(p_note, '')), ''), true
  );
end;
$$;

-- Publish now, without a note — the "send it early" button.
create or replace function public.publish_story(
  p_child uuid,
  p_date date,
  p_recorder uuid,
  p_pin text
) returns public.story
language plpgsql security definer
set search_path = public
as $$
declare
  centre uuid;
  recorder uuid;
begin
  select ch.centre_id into centre from public.child ch where ch.id = p_child;
  if centre is null then raise exception 'child not found'; end if;
  recorder := app.resolve_recorder(centre, p_recorder, p_pin);
  return app.publish_story_row(p_child, p_date, recorder);
end;
$$;

-- The six-argument version composed nothing and took the draft text from its
-- caller, which is why nothing could call it without duplicating the composer.
drop function if exists public.publish_story(uuid, date, text, text, uuid, text);

-- What the room device shows before anyone presses anything.
create or replace function public.story_preview(p_child uuid, p_date date)
returns text
language sql stable security definer
set search_path = public
as $$
  select app.story_compose(p_child, p_date)
  where exists (
    select 1 from public.child c
    where c.id = p_child and c.centre_id in (select app.care_centre_ids())
  )
$$;
