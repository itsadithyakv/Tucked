-- 0011 the calm family surface: one story per child per day, Now/Later
-- notification records with delivery + acknowledgement evidence, device push
-- tokens, messaging with an explicit audience, photos (dated, consent-aware).

-- ── stories ─────────────────────────────────────────────────────────────────
create table public.story (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  story_date date not null,
  draft_text text not null default '',
  educator_note text, -- the human's words always sit on top, untouched
  published_at timestamptz,
  published_by uuid references public.person (id),
  created_at timestamptz not null default now(),
  unique (child_id, story_date)
);

create table public.story_read (
  story_id uuid not null references public.story (id),
  person_id uuid not null references public.person (id),
  read_at timestamptz not null default now(),
  primary key (story_id, person_id)
);

alter table public.story enable row level security;
alter table public.story_read enable row level security;

-- Families see published stories of their children; staff see all (incl. drafts).
create policy story_select on public.story
  for select using (
    centre_id in (select app.care_centre_ids())
    or (
      published_at is not null
      and exists (
        select 1 from public.child_household ch
        where ch.child_id = story.child_id
          and ch.household_id in (select app.my_viewable_household_ids())
      )
    )
  );
create policy story_read_select on public.story_read
  for select using (
    person_id = app.current_person_id()
    or exists (
      select 1 from public.story s
      where s.id = story_read.story_id and s.centre_id in (select app.care_centre_ids())
    )
  );
create policy story_read_insert on public.story_read
  for insert with check (person_id = app.current_person_id());

-- ── notifications (Now / Later) ─────────────────────────────────────────────
create type public.notification_channel as enum ('now', 'later');

create table public.notification (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid references public.child (id),
  recipient_person_id uuid not null references public.person (id),
  channel public.notification_channel not null,
  event_type text not null,
  title text not null,
  body text not null,
  requires_acknowledgement boolean not null default false,
  created_by uuid references public.person (id),
  created_at timestamptz not null default now(),
  pushed_at timestamptz,
  delivered_at timestamptz,
  acknowledged_at timestamptz
);

create index notification_recipient on public.notification (recipient_person_id, created_at desc);
create index notification_unacked_now on public.notification (centre_id)
  where channel = 'now' and acknowledged_at is null;

alter table public.notification enable row level security;

-- Recipients see their own; supervisors see the centre's unacknowledged Now
-- items (the exceptions home).
create policy notification_select on public.notification
  for select using (
    recipient_person_id = app.current_person_id()
    or app.has_role(centre_id, array['supervisor', 'licensee_admin']::public.role_id[])
  );

create trigger notification_audit
  after insert or update on public.notification
  for each row execute function app.audit_row();

-- ── device push tokens (person-scoped, self-managed) ────────────────────────
create table public.device_push_token (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.person (id),
  token text not null unique,
  platform text check (platform in ('ios', 'android')),
  updated_at timestamptz not null default now()
);

alter table public.device_push_token enable row level security;
create policy push_token_own on public.device_push_token
  for all using (person_id = app.current_person_id())
  with check (person_id = app.current_person_id());

-- ── messaging with a visible audience ───────────────────────────────────────
create table public.message_thread (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  -- the parent CHOOSES who reads it, and the choice is shown on every message
  audience text not null check (audience in ('teacher', 'supervisor', 'both')),
  created_by uuid not null references public.person (id),
  created_at timestamptz not null default now()
);

create table public.message (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  thread_id uuid not null references public.message_thread (id),
  sender_person_id uuid not null references public.person (id),
  body text not null,
  sent_at timestamptz not null default now()
);

alter table public.message_thread enable row level security;
alter table public.message enable row level security;

create or replace function app.can_see_thread(t public.message_thread)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select
    -- family: a messaging member of the child's household
    exists (
      select 1 from public.child_household ch
      join public.household_member hm on hm.household_id = ch.household_id
      join public.person p on p.id = hm.person_id
      where ch.child_id = t.child_id
        and p.auth_user_id = auth.uid()
        and hm.revoked_at is null
        and hm.can_message
    )
    -- staff: supervisors always; room staff when the audience includes them
    or (
      t.audience in ('teacher', 'both')
      and t.centre_id in (select app.care_centre_ids())
    )
    or app.has_role(t.centre_id, array['supervisor', 'designate', 'licensee_admin']::public.role_id[])
$$;

create policy thread_select on public.message_thread
  for select using (app.can_see_thread(message_thread));
create policy thread_insert on public.message_thread
  for insert with check (
    created_by = app.current_person_id() and app.can_see_thread(message_thread)
  );

create policy message_select on public.message
  for select using (
    exists (select 1 from public.message_thread t where t.id = message.thread_id and app.can_see_thread(t))
  );
create policy message_insert on public.message
  for insert with check (
    sender_person_id = app.current_person_id()
    and exists (select 1 from public.message_thread t where t.id = message.thread_id and app.can_see_thread(t))
  );

-- ── photos ──────────────────────────────────────────────────────────────────
create table public.photo (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  care_log_id uuid references public.care_log (id),
  storage_path text not null, -- photos/{centre_id}/{child_id}/{uuid}.jpg
  captured_at timestamptz not null, -- EXIF capture time survives; the rest is stripped
  uploaded_by uuid not null references public.person (id),
  created_at timestamptz not null default now()
);

alter table public.photo enable row level security;

create policy photo_select on public.photo
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = photo.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );

-- ── RPCs ────────────────────────────────────────────────────────────────────
-- Publish the day's story (upsert): the generated draft + the educator's note.
create or replace function public.publish_story(
  p_child uuid,
  p_date date,
  p_draft text,
  p_educator_note text,
  p_recorder uuid,
  p_pin text
) returns public.story
language plpgsql security definer
set search_path = public
as $$
declare
  centre uuid;
  recorder uuid;
  result public.story;
begin
  select ch.centre_id into centre from public.child ch where ch.id = p_child;
  if centre is null then raise exception 'child not found'; end if;
  recorder := app.resolve_recorder(centre, p_recorder, p_pin);
  insert into public.story (centre_id, child_id, story_date, draft_text, educator_note, published_at, published_by)
  values (centre, p_child, p_date, p_draft, p_educator_note, now(), recorder)
  on conflict (child_id, story_date)
  do update set draft_text = excluded.draft_text,
                educator_note = excluded.educator_note,
                published_at = coalesce(public.story.published_at, now()),
                published_by = excluded.published_by
  returning * into result;

  -- One Later notification per household adult: the single daily story push.
  insert into public.notification (centre_id, child_id, recipient_person_id, channel, event_type, title, body, created_by)
  select centre, p_child, hm.person_id, 'later', 'story',
         'Today''s story', 'The day''s story is ready.', recorder
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

-- A Now alert (illness, injury follow-up, pickup problem, emergency…) for
-- every viewing household adult. The push itself is the Edge function's job;
-- these rows are the record and drive acknowledgement tracking.
create or replace function public.create_now_alert(
  p_child uuid,
  p_event_type text,
  p_title text,
  p_body text,
  p_recorder uuid,
  p_pin text
) returns setof public.notification
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
  return query
  insert into public.notification (centre_id, child_id, recipient_person_id, channel, event_type, title, body, requires_acknowledgement, created_by)
  select centre, p_child, hm.person_id, 'now', p_event_type, p_title, p_body, true, recorder
  from public.child_household ch
  join public.household_member hm on hm.household_id = ch.household_id
  where ch.child_id = p_child and hm.revoked_at is null and hm.can_view
  returning *;
end;
$$;

create or replace function public.acknowledge_notification(p_notification uuid)
returns public.notification
language plpgsql security definer
set search_path = public
as $$
declare
  result public.notification;
begin
  select * into result from public.notification where id = p_notification;
  if result.id is null then raise exception 'notification not found'; end if;
  if result.recipient_person_id <> app.current_person_id() then
    raise exception 'only the recipient may acknowledge' using errcode = '42501';
  end if;
  if result.acknowledged_at is null then
    update public.notification set acknowledged_at = now(), delivered_at = coalesce(delivered_at, now())
    where id = p_notification
    returning * into result;
  end if;
  return result;
end;
$$;
