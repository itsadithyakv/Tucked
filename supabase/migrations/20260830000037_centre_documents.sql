-- 0037 the documents that live on the premises (Licensing Manual; ss. 36, 68,
-- Parts 4 and 10). The licence, the last Ministry inspection, the fire and
-- public health inspections, the annual playground report, the insurance.
--
-- This is the first thing a program advisor asks to see and the last thing a
-- centre can find, because it is a lever-arch file in a cupboard. It is also
-- the same shape as the staff file: a private bucket, an immutable upload, a
-- supersede rather than an overwrite, and — the part that matters — a list of
-- what is MISSING rather than a tidy list of what happens to be there.
--
-- A LATENT BUG FIXED ON THE WAY IN. The evidence bucket policies cast the
-- path's second segment straight to uuid: `(split_part(name,'/',2))::uuid`.
-- Every path so far has been {centre}/{person}/…, so it worked. A centre-level
-- path — or any stray object — would have raised "invalid input syntax for
-- type uuid" and taken the whole policy evaluation down with it, which for an
-- RLS policy means the query errors rather than returning nothing. Parsing is
-- now done by a helper that returns null instead of throwing.

create or replace function app.path_uuid(p_name text, p_segment integer)
returns uuid
language sql immutable
as $fn$
  select case
    when split_part(p_name, '/', p_segment) ~
      '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then split_part(p_name, '/', p_segment)::uuid
    else null
  end
$fn$;

-- ── what a centre must be able to put its hands on ──────────────────────────
create table public.centre_document_spec (
  id uuid primary key default gen_random_uuid(),
  jurisdiction_code text not null references public.jurisdiction (code),
  key text not null,
  label text not null,
  regulation text not null,
  note text not null,
  -- must be held on the premises; the gap list is built from these
  required boolean not null default true,
  -- how often a fresh one is expected, where the document itself has no date
  renew_months integer,
  ordinal integer not null,
  unique (jurisdiction_code, key)
);

insert into public.centre_document_spec
  (jurisdiction_code, key, label, regulation, note, required, renew_months, ordinal) values
  ('CA-ON', 'licence', 'Licence', 'CCEYA s. 20; O. Reg. 137/15 s. 75',
   'The current licence, posted where parents can see it, with its conditions.', true, null, 1),
  ('CA-ON', 'ministry_inspection', 'Ministry inspection report', 'CCEYA s. 66',
   'The most recent licensing inspection summary, kept on the premises and posted.', true, null, 2),
  ('CA-ON', 'fire_inspection', 'Fire inspection report', 'O. Reg. 137/15 s. 68',
   'The fire department''s most recent inspection, and the approved fire safety plan.', true, 12, 3),
  ('CA-ON', 'public_health_inspection', 'Public health inspection report', 'O. Reg. 137/15 s. 36',
   'The public health unit''s most recent inspection of the premises.', true, 12, 4),
  ('CA-ON', 'playground_inspection', 'Annual playground inspection', 'O. Reg. 137/15 s. 24; CSA Z614',
   'The annual inspection by a qualified inspector, with any deficiencies and what was done.', true, 12, 5),
  ('CA-ON', 'insurance', 'Certificate of insurance', 'CCEYA s. 21',
   'Current liability insurance for the premises and the programme.', true, 12, 6),
  ('CA-ON', 'floor_plan', 'Approved floor plan', 'O. Reg. 137/15 s. 15',
   'The floor plan as approved, showing each room and its licensed capacity.', false, null, 7),
  ('CA-ON', 'other', 'Other', 'Not a regulated document',
   'Anything else an advisor may ask for.', false, null, 8);

alter table public.centre_document_spec enable row level security;
create policy centre_document_spec_select on public.centre_document_spec for select using (true);

-- ── the documents ───────────────────────────────────────────────────────────
create table public.centre_document (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  kind text not null,
  title text not null,
  -- who issued it, and their reference
  issued_by text,
  issued_on date,
  reference text,
  expires_on date,
  storage_path text not null unique,
  file_name text not null,
  content_type text not null,
  size_bytes integer check (size_bytes is null or size_bytes > 0),
  note text,
  uploaded_by uuid not null references public.person (id),
  uploaded_at timestamptz not null default now(),
  -- replaced, never overwritten: the report an advisor saw last year is still
  -- the report they saw
  superseded_at timestamptz,
  superseded_by uuid references public.centre_document (id),
  created_at timestamptz not null default now(),
  constraint centre_document_dates check (expires_on is null or issued_on is null or expires_on >= issued_on)
);

create index centre_document_live on public.centre_document (centre_id, kind)
  where superseded_at is null;

create or replace function app.centre_document_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $fn$
begin
  if tg_op = 'INSERT' then
    -- the path is the access control, so it has to be the real one
    if new.storage_path not like (new.centre_id::text || '/centre/%') then
      raise exception 'a centre document lives at {centre}/centre/… and nowhere else';
    end if;
    if coalesce(trim(new.title), '') = '' or coalesce(trim(new.file_name), '') = '' then
      raise exception 'a document needs a title and its file name';
    end if;
    if not exists (
      select 1 from public.centre_document_spec s
      join public.centre c on c.jurisdiction_code = s.jurisdiction_code
      where c.id = new.centre_id and s.key = new.kind
    ) then
      raise exception 'there is no document kind "%" in this jurisdiction', new.kind;
    end if;
    if new.issued_on is not null and new.issued_on > current_date then
      raise exception 'an inspection report cannot have been issued in the future';
    end if;
  end if;
  if tg_op = 'UPDATE' and old.superseded_at is not null then
    raise exception 'this document has already been replaced';
  end if;
  return new;
end;
$fn$;

create trigger centre_document_rules
  before insert or update on public.centre_document
  for each row execute function app.centre_document_rules();

alter table public.centre_document enable row level security;

-- On the premises means available to the people on the premises. Every care
-- role reads them; families do not, because insurance certificates and floor
-- plans are not theirs.
create policy centre_document_select on public.centre_document
  for select using (centre_id in (select app.care_centre_ids()));

create trigger centre_document_no_delete before delete on public.centre_document
  for each row execute function app.block_mutation();
create trigger centre_document_audit after insert or update on public.centre_document
  for each row execute function app.audit_row();

-- ── the bucket, parsed safely ───────────────────────────────────────────────
drop policy if exists evidence_write on storage.objects;
drop policy if exists evidence_read on storage.objects;

-- evidence/{centre_id}/{person_id}/…  a staff file
-- evidence/{centre_id}/centre/…       a document on the premises
create policy evidence_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'evidence'
    and app.has_role(
      app.path_uuid(name, 1),
      array['supervisor', 'designate', 'licensee_admin']::public.role_id[]
    )
  );

create policy evidence_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'evidence'
    and (
      -- a document on the premises: anyone with a care role there
      (split_part(name, '/', 2) = 'centre'
        and app.path_uuid(name, 1) in (select app.care_centre_ids()))
      -- your own staff file
      or app.path_uuid(name, 2) = app.current_person_id()
      -- leadership holds the centre's staff files
      or app.has_role(
        app.path_uuid(name, 1),
        array['supervisor', 'designate', 'licensee_admin']::public.role_id[]
      )
    )
  );

-- ── what is missing ─────────────────────────────────────────────────────────
create or replace function public.centre_document_gaps(p_centre uuid)
returns table (
  kind text,
  label text,
  regulation text,
  note text,
  state text,
  issued_on date,
  expires_on date,
  title text
)
language sql stable security definer
set search_path = public
as $fn$
  select
    s.key, s.label, s.regulation, s.note,
    case
      when d.id is null then 'missing'
      when d.expires_on is not null and d.expires_on < current_date then 'expired'
      when d.expires_on is not null and d.expires_on < current_date + 60 then 'expiring_soon'
      when s.renew_months is not null and d.issued_on is not null
        and d.issued_on < current_date - make_interval(months => s.renew_months) then 'out_of_date'
      else 'current'
    end,
    d.issued_on, d.expires_on, d.title
  from public.centre_document_spec s
  join public.centre c on c.jurisdiction_code = s.jurisdiction_code
  left join lateral (
    select cd.* from public.centre_document cd
    where cd.centre_id = p_centre and cd.kind = s.key and cd.superseded_at is null
    order by cd.issued_on desc nulls last, cd.uploaded_at desc
    limit 1
  ) d on true
  where c.id = p_centre and s.required
  order by s.ordinal
$fn$;

-- ── RPCs ────────────────────────────────────────────────────────────────────
create or replace function public.attach_centre_document(
  p_centre uuid,
  p_kind text,
  p_title text,
  p_issued_by text,
  p_issued_on date,
  p_reference text,
  p_expires_on date,
  p_storage_path text,
  p_file_name text,
  p_content_type text,
  p_size_bytes integer,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns public.centre_document
language plpgsql security definer
set search_path = public
as $fn$
declare
  recorder uuid;
  result public.centre_document;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate')
  ) then
    raise exception 'the centre''s records are kept by centre leadership';
  end if;

  -- a newer document of the same kind supersedes the last, so the file shows
  -- the current position and the history both
  update public.centre_document
  set superseded_at = now()
  where centre_id = p_centre and kind = p_kind and superseded_at is null;

  insert into public.centre_document (
    centre_id, kind, title, issued_by, issued_on, reference, expires_on,
    storage_path, file_name, content_type, size_bytes, note, uploaded_by
  ) values (
    p_centre, p_kind, trim(p_title), nullif(trim(coalesce(p_issued_by, '')), ''),
    p_issued_on, nullif(trim(coalesce(p_reference, '')), ''), p_expires_on,
    p_storage_path, trim(p_file_name), p_content_type, p_size_bytes,
    nullif(trim(coalesce(p_note, '')), ''), recorder
  ) returning * into result;
  return result;
end;
$fn$;
