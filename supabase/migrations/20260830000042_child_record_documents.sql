-- 0042 documents on the children's record (s. 72(1)).
--
-- s. 72(1) lists eleven items a centre keeps for every child, and Tucked has
-- tracked each one as a status since 0010 — provided, not applicable, parent
-- declined. A signed application existed as the WORD "provided". The signed
-- page did not exist anywhere, and it is the first thing a program advisor asks
-- to see. child_record_item.evidence_path has been in the schema since 0010 and
-- nothing has ever written it.
--
-- WHAT THIS MIGRATION HOLDS
--
--   A document is attached to one item of one child's record. It is replaced,
--   never overwritten: the form an advisor saw last year is still the file they
--   saw, the same rule staff files (0032) and premises documents (0037) follow.
--
--   Two people may attach one, and the record says which:
--     the centre — any care role, PIN-signed, for paper handed in at the door;
--     the family — an adult who may consent for this child, from the app.
--   An adult who can only VIEW a child's day cannot add to their legal record.
--
--   Any new document RE-OPENS VERIFICATION of that item. A supervisor verified
--   what was on file; this is not what was on file. complete_record_item has
--   always followed that rule for answers, and now documents do too.
--
--   Like a photo, the bytes land first and the row second: attaching refuses a
--   path whose object never arrived, and a path outside the child's own folder.
--
-- THE EVIDENCE BUCKET HAD NO LIMITS AT ALL. Photos got JPEG-only and 5 MB in
-- 0041; the bucket holding police checks and now signed forms accepted any type
-- at any size. It now takes PDF, JPEG and PNG — the three types every existing
-- upload surface already offered — up to 20 MB, which fits a multi-page scan.
--
-- RETENTION. A child's documents are s. 72 records, kept three years after
-- discharge (s. 72(5)) and then anonymised with everything else. The file is
-- deleted and the row keeps no name. app.anonymise_child is replaced below from
-- its live definition in 0041, edited in one block.
--
-- Same known gap as photos and staff files: a SQL delete removes the object's
-- row, not the bytes in the storage backend. Purge through the storage API is
-- a follow-up, and references/06 says so.

create table public.child_record_document (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  item_type public.record_item_type not null,
  storage_path text not null unique,
  file_name text not null check (length(trim(file_name)) > 0 and length(file_name) <= 200),
  content_type text not null check (content_type in ('application/pdf', 'image/jpeg', 'image/png')),
  size_bytes integer check (size_bytes is null or (size_bytes > 0 and size_bytes <= 20971520)),
  note text check (note is null or length(note) <= 500),
  uploaded_by uuid not null references public.person (id),
  uploaded_via text not null check (uploaded_via in ('staff', 'family')),
  uploaded_at timestamptz not null default clock_timestamp(),
  superseded_at timestamptz,
  superseded_by uuid references public.child_record_document (id),
  constraint record_document_superseded_together
    check ((superseded_at is null) = (superseded_by is null)),
  -- one place a record document can live: inside its own child's folder
  constraint record_document_path_is_the_childs
    check (storage_path like centre_id::text || '/child/' || child_id::text || '/%')
);

create index child_record_document_live
  on public.child_record_document (child_id, item_type)
  where superseded_at is null;

create or replace function app.child_record_document_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' then
    -- s. 72(5): the retention anonymiser is the one thing allowed to rewrite
    if app.is_anonymising() then
      return new;
    end if;
    if old.superseded_at is not null then
      raise exception 'this document has already been replaced';
    end if;
    if (new.id, new.centre_id, new.child_id, new.item_type, new.storage_path, new.file_name,
        new.content_type, new.size_bytes, new.note, new.uploaded_by, new.uploaded_via, new.uploaded_at)
       is distinct from
       (old.id, old.centre_id, old.child_id, old.item_type, old.storage_path, old.file_name,
        old.content_type, old.size_bytes, old.note, old.uploaded_by, old.uploaded_via, old.uploaded_at) then
      raise exception 'a record document is never edited; attach a new one that replaces it';
    end if;
  end if;
  return new;
end;
$$;

create trigger child_record_document_rules
  before update on public.child_record_document
  for each row execute function app.child_record_document_rules();

create trigger child_record_document_no_delete before delete on public.child_record_document
  for each row execute function app.block_mutation();
create trigger child_record_document_audit after insert or update on public.child_record_document
  for each row execute function app.audit_row();

alter table public.child_record_document enable row level security;

-- the same people who can read the record item it belongs to
create policy child_record_document_select on public.child_record_document
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = child_record_document.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
-- Writes via RPCs only.

-- ── the bucket ──────────────────────────────────────────────────────────────
update storage.buckets
set allowed_mime_types = array['application/pdf', 'image/jpeg', 'image/png'],
    file_size_limit = 20971520
where id = 'evidence';

-- Is p_child enrolled at p_centre? Parsed path segments arrive as maybe-null
-- uuids, so null in means false out rather than an error inside a policy.
create or replace function app.child_at_centre(p_child uuid, p_centre uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select p_child is not null and p_centre is not null and exists (
    select 1 from public.child c where c.id = p_child and c.centre_id = p_centre
  )
$$;

-- evidence/{centre}/{person}/…           a staff file          (0032)
-- evidence/{centre}/centre/…             a premises document   (0037)
-- evidence/{centre}/child/{child}/{file} a record document     (0042)
-- Replaced policies keep every earlier branch word for word and add the child
-- branches. Every segment goes through app.path_uuid, which never raises.
drop policy if exists evidence_write on storage.objects;
drop policy if exists evidence_read on storage.objects;

create policy evidence_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'evidence'
    and (
      -- staff files and premises documents: centre leadership (unchanged)
      app.has_role(
        app.path_uuid(name, 1),
        array['supervisor', 'designate', 'licensee_admin']::public.role_id[]
      )
      -- a record document: someone caring for children at that centre, or an
      -- adult who may consent for that child — and only into that child's folder
      or (
        split_part(name, '/', 2) = 'child'
        and split_part(name, '/', 4) <> ''
        and split_part(name, '/', 5) = ''
        and app.child_at_centre(app.path_uuid(name, 3), app.path_uuid(name, 1))
        and (
          app.path_uuid(name, 1) in (select app.care_centre_ids())
          or app.is_consenting_member(app.current_person_id(), app.path_uuid(name, 3))
        )
      )
    )
  );

create policy evidence_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'evidence'
    and (
      -- a document on the premises: anyone with a care role there (unchanged)
      (split_part(name, '/', 2) = 'centre'
        and app.path_uuid(name, 1) in (select app.care_centre_ids()))
      -- your own staff file (unchanged)
      or app.path_uuid(name, 2) = app.current_person_id()
      -- leadership holds the centre's staff files (unchanged)
      or app.has_role(
        app.path_uuid(name, 1),
        array['supervisor', 'designate', 'licensee_admin']::public.role_id[]
      )
      -- a child's record documents: the people caring for them…
      or (split_part(name, '/', 2) = 'child'
        and app.path_uuid(name, 1) in (select app.care_centre_ids()))
      -- …and the child's own family
      or (split_part(name, '/', 2) = 'child'
        and exists (
          select 1 from public.child_household ch
          where ch.child_id = app.path_uuid(name, 3)
            and ch.household_id in (select app.my_viewable_household_ids())
        ))
    )
  );

-- ── attaching a document ────────────────────────────────────────────────────
-- Staff pass a recorder and PIN; a family adult passes neither and is resolved
-- from their own session. The bytes must already be at the path.
create or replace function public.attach_record_document(
  p_child uuid,
  p_item public.record_item_type,
  p_storage_path text,
  p_file_name text,
  p_content_type text,
  p_size_bytes integer,
  p_note text default null,
  p_replaces uuid default null,
  p_recorder uuid default null,
  p_pin text default null
) returns public.child_record_document
language plpgsql security definer
set search_path = public
as $$
declare
  kid public.child;
  me uuid := app.current_person_id();
  who uuid;
  via text;
  prior public.child_record_document;
  result public.child_record_document;
begin
  select * into kid from public.child where id = p_child;
  if kid.id is null then
    raise exception 'child not found';
  end if;

  if p_recorder is not null then
    who := app.resolve_recorder(kid.centre_id, p_recorder, p_pin);
    via := 'staff';
  elsif me is not null and app.is_consenting_member(me, p_child) then
    who := me;
    via := 'family';
  else
    raise exception 'only the centre or an adult who can consent for this child may add to the record'
      using errcode = '42501';
  end if;

  if p_storage_path is null
     or p_storage_path not like kid.centre_id::text || '/child/' || p_child::text || '/%' then
    raise exception 'a record document lives at {centre}/child/{child}/… and nowhere else';
  end if;
  if coalesce(trim(p_file_name), '') = '' then
    raise exception 'a document needs its file name';
  end if;
  if not exists (
    select 1 from storage.objects o where o.bucket_id = 'evidence' and o.name = p_storage_path
  ) then
    raise exception 'the document has not finished uploading — try again';
  end if;

  if p_replaces is not null then
    select * into prior from public.child_record_document where id = p_replaces;
    if prior.id is null or prior.child_id <> p_child or prior.item_type <> p_item then
      raise exception 'that document is not on this item of this child''s record';
    end if;
    if prior.superseded_at is not null then
      raise exception 'this document has already been replaced';
    end if;
  end if;

  perform app.ensure_record_items(kid.centre_id, p_child);

  insert into public.child_record_document (
    centre_id, child_id, item_type, storage_path, file_name, content_type,
    size_bytes, note, uploaded_by, uploaded_via
  ) values (
    kid.centre_id, p_child, p_item, p_storage_path, trim(p_file_name), p_content_type,
    p_size_bytes, nullif(trim(coalesce(p_note, '')), ''), who, via
  ) returning * into result;

  if prior.id is not null then
    update public.child_record_document
    set superseded_at = clock_timestamp(), superseded_by = result.id
    where id = prior.id;
  end if;

  -- the item's pointer follows the newest document, and verification re-opens:
  -- a supervisor verified what was on file, and this is not what was on file
  update public.child_record_item
  set evidence_path = p_storage_path,
      updated_by = who,
      updated_at = now(),
      verified_by = null,
      verified_at = null
  where child_id = p_child and item_type = p_item;

  return result;
end;
$$;

-- ── replaced: app.anonymise_child (from 20260830000041_photos.sql) ─────────────
-- Copied from the live definition by a generator and edited in one block — the
-- record documents — so every other line, including the photo withdrawal and
-- the s. 72(5) anonymising escape hatch, is exactly what 0041 left.
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

  -- s. 72(1) documents (0042). The files go; the row that says a document
  -- existed survives and keeps no name — a scanned application carries the
  -- child's and the parents' names in its file name as often as in its pages.
  update public.child_record_document
  set file_name = '[anonymised]',
      note = case when note is null then null else '[anonymised]' end
  where child_id = p_child;

  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects
  where bucket_id = 'evidence'
    and split_part(name, '/', 2) = 'child'
    and app.path_uuid(name, 3) = p_child;
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
