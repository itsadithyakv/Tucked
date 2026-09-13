-- 0041 photos — and the consent families already gave, finally enforced.
--
-- Every competitor's core feature is the photo feed, and Tucked had the table,
-- the bucket, the consent types and a cost model for photos — and no way to
-- take one. Reading those pieces to build the feature found that the part that
-- matters most was never there:
--
--   PHOTO CONSENT WAS COLLECTED AND NEVER ENFORCED. The enrolment flow asks
--   every family for photo_internal, photo_group and photo_third_party (0010).
--   No policy, function or screen ever read them. The references said "a child
--   without group-photo consent is excluded"; nothing did the excluding.
--
--   A GROUP PHOTO COULD NOT BE REPRESENTED. photo.child_id was one child and the
--   path was photos/{centre}/{child}/…, so a picture of Maya AND Liam had
--   nowhere to record Liam — and so nowhere to ask whether Liam's family agreed
--   to Maya's family seeing him.
--
--   THE PHOTOS BUCKET STILL HAD THE LATENT CRASH 0037 fixed for evidence. Its
--   policies cast path segments with ::uuid, and a policy that raises fails the
--   whole query — any object at a non-uuid path would have broken every read.
--
-- WHAT THIS MIGRATION HOLDS
--
--   A photo is one image; photo_subject says who is in it. No row has ever been
--   written to photo — the seed creates none and no screen reads it — so the
--   reshape below destroys nothing.
--
--   Consent is checked TWICE, on purpose:
--     at capture — record_photo refuses a child whose family has not agreed, by
--       name, so the educator hears it before the photo exists; and
--     at read — in RLS AND in the storage policy, through one function. A family
--       who withdraws photo_group on Tuesday vanishes from other families'
--       galleries on Tuesday, with no cascade job to forget to run.
--
--   The read check is SECURITY DEFINER because it has to look at OTHER
--   families' consent rows, which a parent cannot SELECT. A security_invoker
--   version would see no consent for anyone else's child and hide every group
--   photo from everybody — the "reasoning about rows you cannot see" bug this
--   schema has already hit three times.
--
--   The rules, per child in a photo:
--     photo_internal — may be in a photo in the app at all. Without it the
--       child is never tagged, and any existing photo of them is hidden.
--     photo_group    — may be seen by a family that is not their own. Needed
--       only when someone else in the picture belongs to another household:
--       two siblings are not a group photo.
--     photo_third_party — sharing OUTSIDE the centre. Tucked has no such feature
--       and this migration does not add one. A family saving a photo of their
--       own child to their phone is "shared with you".
--   No decision on file is not a yes.
--
--   Photos are not s. 72 records, but they are personal information. A withdrawn
--   photo is hidden everywhere a family can reach and kept as a row with its
--   reason, so "who took it down, when, and why" survives.
--
-- WHAT IT DOES NOT DO — written down so nobody assumes otherwise
--
--   * Verify EXIF is gone. The device re-encodes through expo-image-manipulator,
--     which writes no EXIF; SQL cannot parse a JPEG to prove it. The bucket now
--     accepts image/jpeg only, capped at 5 MB, so a raw HEIC straight off a
--     phone camera cannot be uploaded — but a JPEG with metadata could be, by a
--     client that skipped the re-encode.
--   * Remove the FILE when a photo is withdrawn. Deleting a storage.objects row
--     in SQL does not delete the object from the storage backend; that needs the
--     storage API with the service role. Withdrawal hides; purge is a follow-up.
--     (0022's anonymiser has always deleted photos this way, with the same gap.)
--   * Queue offline. A photo is bytes, and the command queue carries commands.

-- ── the reshape ─────────────────────────────────────────────────────────────
drop policy if exists photo_select on public.photo;
alter table public.photo drop column child_id;
alter table public.photo drop column care_log_id;
alter table public.photo
  add column width integer check (width is null or width > 0),
  add column height integer check (height is null or height > 0),
  add column size_bytes integer check (size_bytes is null or size_bytes > 0),
  add column caption text check (caption is null or length(caption) <= 280),
  add column withdrawn_at timestamptz,
  add column withdrawn_by uuid references public.person (id),
  add column withdrawn_reason text,
  add constraint photo_withdrawal_says_why
    check ((withdrawn_at is null) = (withdrawn_reason is null)),
  -- one place a gallery photo can live, derived from its own id
  add constraint photo_path_is_its_own
    check (storage_path = centre_id::text || '/p/' || id::text || '/full.jpg'),
  add constraint photo_storage_path_unique unique (storage_path);

create table public.photo_subject (
  photo_id uuid not null references public.photo (id),
  child_id uuid not null references public.child (id),
  centre_id uuid not null references public.centre (id),
  primary key (photo_id, child_id)
);
create index photo_subject_child on public.photo_subject (child_id);

-- ── consent, as a question with one answer ──────────────────────────────────
-- The latest live decision of that type: not revoked, not expired. give_consent
-- revokes the previous decision when a new one is made, so there is at most one.
create or replace function app.consent_granted(p_child uuid, p_type public.consent_type)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce((
    select c.status = 'granted'
    from public.consent c
    where c.child_id = p_child
      and c.consent_type = p_type
      and c.revoked_at is null
      and (c.expires_at is null or c.expires_at > now())
    order by c.granted_at desc
    limit 1
  ), false)
$$;

-- Would this photo be visible to a family whose households are p_households?
-- The single definition of photo visibility; the two wrappers below only
-- decide whose households to ask about.
create or replace function app.photo_visible_to_households(p_photo uuid, p_households uuid[])
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.photo p
    where p.id = p_photo
      and p.withdrawn_at is null
      -- one of this family's children is in it
      and exists (
        select 1 from public.photo_subject s
        join public.child_household ch on ch.child_id = s.child_id
        where s.photo_id = p.id and ch.household_id = any (p_households)
      )
      -- every child in it may be in a photo in the app at all
      and not exists (
        select 1 from public.photo_subject s
        where s.photo_id = p.id and not app.consent_granted(s.child_id, 'photo_internal')
      )
      -- and every child from ANOTHER family may be seen by this one
      and not exists (
        select 1 from public.photo_subject s
        where s.photo_id = p.id
          and not app.consent_granted(s.child_id, 'photo_group')
          and not exists (
            select 1 from public.child_household ch
            where ch.child_id = s.child_id and ch.household_id = any (p_households)
          )
      )
  )
$$;

-- the signed-in family adult (RLS and the storage policy)
create or replace function app.photo_visible_to_family(p_photo uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select p_photo is not null
    and app.photo_visible_to_households(p_photo, array(select app.my_viewable_household_ids()))
$$;

-- a particular child's family (the story composer, which has no signed-in viewer)
create or replace function app.photo_visible_for_child(p_photo uuid, p_child uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select app.photo_visible_to_households(
    p_photo,
    array(select ch.household_id from public.child_household ch where ch.child_id = p_child)
  )
$$;

-- a profile photo: the child's own family, and only with photo_internal
create or replace function app.child_profile_visible_to_family(p_child uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select p_child is not null
    and app.consent_granted(p_child, 'photo_internal')
    and exists (
      select 1 from public.child_household ch
      where ch.child_id = p_child
        and ch.household_id in (select app.my_viewable_household_ids())
    )
$$;

-- ── rules ───────────────────────────────────────────────────────────────────
create or replace function app.photo_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    if old.withdrawn_at is not null then
      raise exception 'a withdrawn photo stays withdrawn';
    end if;
    if (new.id, new.centre_id, new.storage_path, new.captured_at, new.uploaded_by,
        new.width, new.height, new.size_bytes, new.caption)
       is distinct from
       (old.id, old.centre_id, old.storage_path, old.captured_at, old.uploaded_by,
        old.width, old.height, old.size_bytes, old.caption) then
      raise exception 'a photo is never edited; withdraw it and take another';
    end if;
  end if;
  return new;
end;
$$;

create trigger photo_rules
  before update on public.photo
  for each row execute function app.photo_rules();

create trigger photo_no_delete before delete on public.photo
  for each row execute function app.block_mutation();
-- who is in a photo is fixed: a wrong tag is a withdrawal and a new photo
create trigger photo_subject_no_change before update or delete on public.photo_subject
  for each row execute function app.block_mutation();
create trigger photo_audit after insert or update on public.photo
  for each row execute function app.audit_row();

-- ── visibility ──────────────────────────────────────────────────────────────
alter table public.photo_subject enable row level security;

create policy photo_select on public.photo
  for select using (
    centre_id in (select app.care_centre_ids())
    or app.photo_visible_to_family(id)
  );

-- A family sees who in a photo is THEIR child, never who else is tagged: the
-- picture shows another child's face, the tag would add their identity.
create policy photo_subject_select on public.photo_subject
  for select using (
    centre_id in (select app.care_centre_ids())
    or (
      app.photo_visible_to_family(photo_id)
      and exists (
        select 1 from public.child_household ch
        where ch.child_id = photo_subject.child_id
          and ch.household_id in (select app.my_viewable_household_ids())
      )
    )
  );
-- Writes via RPCs only.

-- ── the bucket ──────────────────────────────────────────────────────────────
-- JPEG only, because the device re-encodes every photo before upload; 5 MB,
-- because a re-encoded 2560 px photo is under one.
update storage.buckets
set file_size_limit = 5242880, allowed_mime_types = array['image/jpeg']
where id = 'photos';

drop policy if exists photos_staff_write on storage.objects;
drop policy if exists photos_read on storage.objects;

-- photos/{centre_id}/p/{photo_id}/full.jpg    a gallery photo
-- photos/{centre_id}/{child_id}/profile.jpg   a child's profile photo
-- Every segment is parsed with app.path_uuid, which returns null rather than
-- raising — a policy that raises fails every read in the bucket.
create policy photos_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'photos'
    and app.path_uuid(name, 1) in (select app.care_centre_ids())
    and (
      (split_part(name, '/', 2) = 'p'
        and app.path_uuid(name, 3) is not null
        and split_part(name, '/', 4) = 'full.jpg'
        and split_part(name, '/', 5) = '')
      or (app.path_uuid(name, 2) is not null
        and split_part(name, '/', 3) = 'profile.jpg'
        and split_part(name, '/', 4) = '')
    )
  );

create policy photos_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'photos'
    and (
      app.path_uuid(name, 1) in (select app.care_centre_ids())
      or (split_part(name, '/', 2) = 'p'
        and app.photo_visible_to_family(app.path_uuid(name, 3)))
      or (split_part(name, '/', 3) = 'profile.jpg'
        and app.child_profile_visible_to_family(app.path_uuid(name, 2)))
    )
  );

-- ── recording a photo ───────────────────────────────────────────────────────
-- The device uploads first, to the path its own id determines, then records.
-- Recording checks the bytes actually arrived, so a row never points at nothing.
create or replace function public.record_photo(
  p_centre uuid,
  p_photo uuid,
  p_subjects uuid[],
  p_captured_at timestamptz,
  p_width integer,
  p_height integer,
  p_size_bytes integer,
  p_caption text,
  p_recorder uuid,
  p_pin text
) returns public.photo
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  path text := p_centre::text || '/p/' || p_photo::text || '/full.jpg';
  subjects uuid[];
  kid uuid;
  first_name text;
  result public.photo;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);

  subjects := array(select distinct s from unnest(coalesce(p_subjects, '{}')) s where s is not null);
  if cardinality(subjects) = 0 then
    raise exception 'say who is in the photo — a photo with nobody tagged reaches no family';
  end if;

  foreach kid in array subjects loop
    select split_part(c.full_name, ' ', 1) into first_name
    from public.child c
    where c.id = kid and c.centre_id = p_centre and c.discharge_date is null;
    if first_name is null then
      raise exception 'a child tagged in this photo is not enrolled at this centre';
    end if;

    if not app.consent_granted(kid, 'photo_internal') then
      raise exception '%''s family has not agreed to photos in the app — leave % out of this one',
        first_name, first_name;
    end if;

    -- group consent only matters when someone from another household is in the
    -- picture: that is when a family who is not this child's will see them
    if not app.consent_granted(kid, 'photo_group') and exists (
      select 1 from unnest(subjects) as other(id)
      where other.id <> kid
        and exists (
          select 1 from public.child_household oh
          where oh.child_id = other.id
            and not exists (
              select 1 from public.child_household kh
              where kh.child_id = kid and kh.household_id = oh.household_id
            )
        )
    ) then
      raise exception '%''s family has not agreed to group photos — take % on their own, or leave them out',
        first_name, first_name;
    end if;
  end loop;

  if p_captured_at is null or p_captured_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'a photo is recorded after it is taken';
  end if;

  if not exists (
    select 1 from storage.objects o where o.bucket_id = 'photos' and o.name = path
  ) then
    raise exception 'the photo has not finished uploading — try again';
  end if;

  insert into public.photo (
    id, centre_id, storage_path, captured_at, uploaded_by, width, height, size_bytes, caption
  ) values (
    p_photo, p_centre, path, p_captured_at, recorder, p_width, p_height, p_size_bytes,
    nullif(trim(coalesce(p_caption, '')), '')
  ) returning * into result;

  insert into public.photo_subject (photo_id, child_id, centre_id)
  select p_photo, s, p_centre from unnest(subjects) s;

  -- a line in each child's day log, where the family reads "new photo"
  insert into public.care_log (
    centre_id, child_id, room_id, log_type, logged_at, log_date, payload, recorded_by
  )
  select p_centre, c.id, c.current_room_id, 'photo', p_captured_at, '1970-01-01',
         jsonb_build_object('storage_path', path, 'captured_at', p_captured_at, 'photo_id', p_photo),
         recorder
  from public.child c
  where c.id = any (subjects) and c.current_room_id is not null;

  return result;
end;
$$;

-- ── taking one down ─────────────────────────────────────────────────────────
create or replace function public.withdraw_photo(
  p_photo uuid,
  p_reason text,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  ph public.photo;
  recorder uuid;
begin
  select * into ph from public.photo where id = p_photo;
  if ph.id is null then
    raise exception 'photo not found';
  end if;
  recorder := app.resolve_recorder(ph.centre_id, p_recorder, p_pin);
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'say why it is coming down — the wrong child tagged, a family asked, …';
  end if;
  if ph.withdrawn_at is not null then
    raise exception 'this photo is already withdrawn';
  end if;
  update public.photo
  set withdrawn_at = clock_timestamp(), withdrawn_by = recorder, withdrawn_reason = trim(p_reason)
  where id = p_photo;
end;
$$;

-- ── what the room device shows before the shutter ───────────────────────────
-- Which children in a room can be in a photo at all, and which can be in a
-- group photo — so the tagging screen offers only what the write will accept.
create or replace function public.photo_consent_for_room(p_room uuid)
returns table (child_id uuid, full_name text, photos_ok boolean, group_ok boolean)
language sql stable security definer
set search_path = public
as $$
  select c.id, c.full_name,
         app.consent_granted(c.id, 'photo_internal'),
         app.consent_granted(c.id, 'photo_group')
  from public.child c
  where c.current_room_id = p_room
    and c.discharge_date is null
    and c.centre_id in (select app.care_centre_ids())
  order by c.full_name
$$;

-- ── what a FAMILY sees of their own child's photos ──────────────────────────
-- The family surface asks the family question explicitly. photo_select and the
-- photos_read storage policy both have a care-staff branch, so an adult who is
-- a parent AND an educator gets the STAFF answer from a plain select or a signed
-- URL — including a group photo another family has since withdrawn consent for
-- — on their personal family Home. RLS answers "may this person see the row";
-- a family screen needs "would this person's family see it". For dual-role
-- adults those differ, and this function answers the second.
create or replace function public.family_photos(p_child uuid, p_date date)
returns table (id uuid, storage_path text, captured_at timestamptz, caption text)
language sql stable security definer
set search_path = public
as $$
  select p.id, p.storage_path, p.captured_at, p.caption
  from public.photo p
  join public.photo_subject s on s.photo_id = p.id and s.child_id = p_child
  join public.centre ce on ce.id = p.centre_id
  where exists (
          select 1 from public.child_household ch
          where ch.child_id = p_child
            and ch.household_id in (select app.my_viewable_household_ids())
        )
    and (p.captured_at at time zone ce.timezone)::date = p_date
    and app.photo_visible_to_family(p.id)
  order by p.captured_at
$$;

-- ── replaced: app.anonymise_child (from20260830000022_retention_anonymise.sql) ─────────────
-- Extracted from that migration and edited in one block — the photos section —
-- so every other line is the live definition, including the s. 72(5)
-- anonymising escape hatch.
create or replace function app.anonymise_child(p_child uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  ch public.child;
  clock public.retention_clock;
  token text;
begin
  select * into ch from public.child where id = p_child;
  if ch.id is null then raise exception 'child not found'; end if;
  if ch.discharge_date is null then
    raise exception 'never: this child is not discharged — no retention clock is running';
  end if;

  select * into clock from public.retention_clock
  where subject_table = 'child' and subject_id = p_child::text and kind = 'childrens_record';
  if clock.id is null then
    raise exception 'never: no retention clock exists for this child';
  end if;
  if clock.purge_after > current_date then
    raise exception 'never: the retention period has not ended (kept until %)', clock.purge_after;
  end if;
  if clock.anonymised_at is not null then
    return; -- already done; idempotent
  end if;

  -- the flag the immutability triggers honour, for this transaction only
  perform set_config('app.anonymising', 'on', true);
  token := 'Anonymised child ' || left(p_child::text, 8);

  update public.child
  set full_name = token,
      date_of_birth = make_date(extract(year from date_of_birth)::int, 1, 1),
      photo_path = null
  where id = p_child;

  -- the s. 72(1) items hold parents' names, addresses, phones — gone
  update public.child_record_item
  set content = '{"anonymised": true}'::jsonb
  where child_id = p_child;

  -- free text out of care logs; structured facts (meal, minutes…) survive
  update public.care_log
  set payload = (payload - 'note' - 'text' - 'observation' - 'description' - 'parent_report')
                || '{"anonymised": true}'::jsonb
  where child_id = p_child
    and payload ?| array['note', 'text', 'observation', 'description', 'parent_report'];

  update public.accident_report
  set description = '[anonymised]', injury = '[anonymised]', first_aid = '[anonymised]',
      concussion_watch_note = case when concussion_watch_note is null then null else '[anonymised]' end
  where child_id = p_child;

  update public.individualised_plan
  set condition = '[anonymised]', allergens = '{}',
      signs = case when signs is null then null else '[anonymised]' end,
      emergency_procedure = case when emergency_procedure is null then null else '[anonymised]' end,
      exposure_reduction = case when exposure_reduction is null then null else '[anonymised]' end,
      devices_instructions = case when devices_instructions is null then null else '[anonymised]' end,
      supports = case when supports is null then null else '[anonymised]' end,
      evacuation_procedure = case when evacuation_procedure is null then null else '[anonymised]' end,
      developed_with = '[anonymised]' -- names the parents
  where child_id = p_child;

  update public.dietary_restriction set note = null where child_id = p_child;

  update public.story
  set draft_text = '[anonymised]',
      educator_note = case when educator_note is null then null else '[anonymised]' end
  where child_id = p_child;

  update public.notification
  set title = '[anonymised]', body = '[anonymised]'
  where child_id = p_child;

  -- face-to-name snapshots in headcounts carry the name; keep the count
  update public.headcount_check hc
  set missing = (
    select coalesce(jsonb_agg(
      case when m ->> 'child_id' = p_child::text
        then jsonb_set(m, '{full_name}', to_jsonb(token))
        else m end), '[]'::jsonb)
    from jsonb_array_elements(hc.missing) m
  )
  where hc.missing @> jsonb_build_array(jsonb_build_object('child_id', p_child::text));

  -- Photos leave entirely: the profile photo, and every gallery photo this
  -- child is in. A GROUP photo goes too, whole. Other families lose that
  -- picture, and the discharged child's face does not outlive their record —
  -- which is the side of that trade s. 72(5) is on. (0041 replaced the 0022
  -- delete, which matched gallery paths by child id and so would have missed
  -- every photo stored under photos/{centre}/p/{photo}/.)
  update public.photo p
  set withdrawn_at = clock_timestamp(),
      withdrawn_reason = 'retention: a child in this photo was anonymised (s. 72(5))'
  where p.withdrawn_at is null
    and exists (
      select 1 from public.photo_subject s where s.photo_id = p.id and s.child_id = p_child
    );

  -- the storage guard against accidental SQL deletes recognises the same
  -- explicit-intent pattern
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects
  where bucket_id = 'photos'
    and (
      split_part(name, '/', 2) = p_child::text
      or (
        split_part(name, '/', 2) = 'p'
        and app.path_uuid(name, 3) in (
          select s.photo_id from public.photo_subject s where s.child_id = p_child
        )
      )
    );
  perform set_config('storage.allow_delete_query', 'false', true);

  update public.retention_clock
  set anonymised_at = now()
  where subject_id = p_child::text and subject_table in ('child', 'attendance_event');

  insert into public.audit_event (centre_id, table_name, row_id, action, summary)
  values (ch.centre_id, 'retention_clock', p_child::text, 'update',
          jsonb_build_object('action', 'anonymised', 'kind', 'childrens_record',
                             'purge_after', clock.purge_after));

  -- close the hatch immediately — not at transaction end
  perform set_config('app.anonymising', '', true);
end;
$$;

-- ── replaced: app.story_compose (from20260830000039_story_publishing.sql) ─────────────
-- Extracted and edited in one block: the photo count now counts photos this
-- child's family can open.
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

  -- Photos this child's family can actually open: not withdrawn, and every
  -- child in the picture still consented. Counting care-log lines, as 0039
  -- did, would promise a family a photo that had been taken down for tagging
  -- the wrong child, or hidden because another family withdrew consent.
  select count(*)::integer into photos
  from public.photo p
  join public.photo_subject s on s.photo_id = p.id and s.child_id = p_child
  where p.withdrawn_at is null
    and (p.captured_at at time zone tz)::date = p_date
    and app.photo_visible_for_child(p.id, p_child);

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
    -- No full stop after a time: app.twelve_hour already ends in one, because
    -- "a.m." and "p.m." do. The TypeScript this was ported from appended one
    -- anyway and every family would have read "settled for a rest at 10:58
    -- a.m..", once a day, forever.
    parts := array_append(parts,
      case when n.ended is not null
        then 'Rest time went ' || app.twelve_hour(n.started, tz) || ' to ' || app.twelve_hour(n.ended, tz)
        else name || ' settled for a rest at ' || app.twelve_hour(n.started, tz)
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
