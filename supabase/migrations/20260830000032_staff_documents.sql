-- 0032 staff files: the documents themselves, and the rules that say which
-- ones are missing (Parts 8–9, ss. 53–64). What this migration changes:
--
--   * A STAFF FILE IS NOT A SHARED DRIVE. The evidence bucket shipped in 0012
--     let any care-staff member read any file in the centre — an educator
--     could open a colleague's police record check. That is fixed here: a
--     staff document is readable by its subject and by centre leadership, and
--     by nobody else. The credential rows were already scoped that way; the
--     files were not.
--   * THE FILE TELLS YOU WHAT IS MISSING. staff_requirement is a rule pack
--     keyed by jurisdiction and role, so the console can say "Dara has no
--     health assessment on file and is counted in ratio" rather than showing
--     a tidy list of the things that happen to be there. That is the whole
--     value of a staff file to a licensee, and it is what a program advisor
--     actually asks for.
--   * THE VSC RULES ARE ARITHMETIC, NOT TYPING. Five years from the date it
--     was obtained, derived and never entered by hand; the police check must
--     have been conducted no more than six months before it was obtained; and
--     an offence declaration is required for every year in which no vulnerable
--     sector check was obtained (s. 60).
--   * A DOCUMENT IS SUPERSEDED, NEVER OVERWRITTEN. The certificate an
--     inspector saw last year is still exactly the file they saw.

-- ── what each role must have on file ────────────────────────────────────────
create table public.staff_requirement (
  id uuid primary key default gen_random_uuid(),
  jurisdiction_code text not null references public.jurisdiction (code),
  key text not null,
  label text not null,
  credential_type public.credential_type not null,
  -- the roles this applies to; a volunteer needs a police check and a health
  -- assessment, but not first aid, because a volunteer is never in ratio
  applies_to public.role_id[] not null,
  regulation text not null,
  note text not null,
  -- null where the document does not expire
  renewal_years numeric,
  ordinal integer not null,
  unique (jurisdiction_code, key)
);

insert into public.staff_requirement
  (jurisdiction_code, key, label, credential_type, applies_to, regulation, note, renewal_years, ordinal) values
  ('CA-ON', 'vsc', 'Vulnerable sector check', 'vsc',
   array['licensee_admin','supervisor','designate','rece','staff','student','volunteer']::public.role_id[],
   'O. Reg. 137/15 s. 60',
   'Obtained before starting, conducted by a police service no more than six months before it was obtained, and renewed on or before the fifth anniversary.',
   5, 1),
  ('CA-ON', 'offence_declaration', 'Offence declaration', 'offence_declaration',
   array['licensee_admin','supervisor','designate','rece','staff','student','volunteer']::public.role_id[],
   'O. Reg. 137/15 s. 61',
   'Required for every year in which a vulnerable sector check was not obtained.',
   1, 2),
  ('CA-ON', 'first_aid_cpr', 'Standard first aid with infant and child CPR', 'first_aid_cpr',
   array['supervisor','designate','rece','staff']::public.role_id[],
   'O. Reg. 137/15 s. 58',
   'A WSIB-approved standard first aid course including infant and child CPR, for the supervisor and everyone who may be counted in ratio.',
   3, 3),
  ('CA-ON', 'rece_registration', 'College of Early Childhood Educators registration', 'rece_registration',
   array['supervisor','rece']::public.role_id[],
   'O. Reg. 137/15 ss. 54, 56',
   'Registration in good standing on the College''s public register.',
   1, 4),
  ('CA-ON', 'health_assessment', 'Health assessment', 'health_assessment',
   array['licensee_admin','supervisor','designate','rece','staff','student','volunteer']::public.role_id[],
   'O. Reg. 137/15 s. 57',
   'A health assessment before starting, for employees, volunteers and placement students.',
   null, 5),
  ('CA-ON', 'immunisation', 'Immunisation (or the objection form)', 'immunisation',
   array['licensee_admin','supervisor','designate','rece','staff','student','volunteer']::public.role_id[],
   'O. Reg. 137/15 s. 57',
   'Immunisation as directed by the local medical officer of health, or the signed objection.',
   null, 6);

alter table public.staff_requirement enable row level security;
create policy staff_requirement_select on public.staff_requirement for select using (true);

-- ── the credential rows learn the s. 60 rules ───────────────────────────────
alter table public.credential
  -- when the police service actually conducted the check, as distinct from
  -- when the centre obtained it
  add column checked_on date,
  add column police_service text,
  -- for an offence declaration: the year it covers
  add column declaration_year integer,
  add column superseded_at timestamptz;

create or replace function app.credential_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if new.credential_type = 'vsc' then
    if coalesce(trim(coalesce(new.police_service, '')), '') = '' then
      raise exception 'a vulnerable sector check names the police service that conducted it';
    end if;
    if new.issued_on is null then
      raise exception 'record the date the check was obtained';
    end if;
    if new.checked_on is null then
      raise exception 'record the date the police service conducted the check';
    end if;
    if new.checked_on > new.issued_on then
      raise exception 'the check cannot have been conducted after it was obtained';
    end if;
    -- s. 60: no more than six months old when obtained
    if new.checked_on < new.issued_on - interval '6 months' then
      raise exception 'that check was already more than six months old when it was obtained (conducted %, obtained %)',
        to_char(new.checked_on, 'FMDD Mon YYYY'), to_char(new.issued_on, 'FMDD Mon YYYY');
    end if;
    -- the fifth anniversary, derived rather than typed
    new.expires_on := (new.issued_on + interval '5 years')::date;

  elsif new.credential_type = 'offence_declaration' then
    if new.declaration_year is null then
      raise exception 'an offence declaration says which year it covers';
    end if;
    new.expires_on := make_date(new.declaration_year, 12, 31);

  elsif new.credential_type in ('first_aid_cpr', 'rece_registration') then
    if new.expires_on is null then
      raise exception 'record the date this expires — the whole point of the ledger is the date';
    end if;
  end if;
  return new;
end;
$$;

create trigger credential_rules
  before insert or update on public.credential
  for each row execute function app.credential_rules();

-- ── the documents ───────────────────────────────────────────────────────────
create table public.staff_document (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  person_id uuid not null references public.person (id),
  credential_id uuid references public.credential (id),
  kind text not null default 'credential_evidence'
    check (kind in ('credential_evidence', 'policy_acknowledgement', 'contract', 'other')),
  storage_path text not null unique,
  file_name text not null,
  content_type text not null,
  size_bytes integer check (size_bytes is null or size_bytes > 0),
  note text,
  uploaded_by uuid not null references public.person (id),
  uploaded_at timestamptz not null default now(),
  -- replaced, never overwritten: the certificate an inspector saw last year
  -- is still the file they saw
  superseded_at timestamptz,
  superseded_by uuid references public.staff_document (id),
  created_at timestamptz not null default now()
);

create index staff_document_person on public.staff_document (person_id) where superseded_at is null;

create or replace function app.staff_document_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    -- the path is the access control, so it has to be the real one
    if new.storage_path not like (new.centre_id::text || '/' || new.person_id::text || '/%') then
      raise exception 'a staff document lives at {centre}/{person}/… and nowhere else';
    end if;
    if coalesce(trim(new.file_name), '') = '' then
      raise exception 'a document needs its file name';
    end if;
    if new.credential_id is not null and not exists (
      select 1 from public.credential c
      where c.id = new.credential_id and c.person_id = new.person_id
    ) then
      raise exception 'that credential belongs to somebody else';
    end if;
  end if;
  if tg_op = 'UPDATE' and old.superseded_at is not null then
    raise exception 'this document has already been replaced';
  end if;
  return new;
end;
$$;

create trigger staff_document_rules
  before insert or update on public.staff_document
  for each row execute function app.staff_document_rules();

-- ── visibility ──────────────────────────────────────────────────────────────
alter table public.staff_document enable row level security;

-- Your own file, or the file of somebody whose file you are responsible for.
-- Not "anyone with a care role", which is what the bucket used to allow.
create policy staff_document_select on public.staff_document
  for select using (
    person_id = app.current_person_id()
    or app.has_role(centre_id, array['supervisor', 'designate', 'licensee_admin']::public.role_id[])
  );

create trigger staff_document_no_delete before delete on public.staff_document
  for each row execute function app.block_mutation();
create trigger staff_document_audit after insert or update on public.staff_document
  for each row execute function app.audit_row();

-- ── the bucket policies, tightened ──────────────────────────────────────────
-- 0012 scoped these to "any care staff at the centre". A police record check
-- is not a document the room team reads.
drop policy if exists evidence_staff_write on storage.objects;
drop policy if exists evidence_read on storage.objects;

-- evidence/{centre_id}/{person_id}/{uuid}.{ext}
create policy evidence_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'evidence'
    and app.has_role(
      (split_part(name, '/', 1))::uuid,
      array['supervisor', 'designate', 'licensee_admin']::public.role_id[]
    )
  );

create policy evidence_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'evidence'
    and (
      app.has_role(
        (split_part(name, '/', 1))::uuid,
        array['supervisor', 'designate', 'licensee_admin']::public.role_id[]
      )
      or (split_part(name, '/', 2))::uuid = app.current_person_id()
    )
  );

-- ── what is missing ─────────────────────────────────────────────────────────
-- The inspection-ready answer: for everyone with a workforce role, every
-- requirement that applies to them, and whether it is on file, expiring or
-- absent. Column references are qualified throughout because the RETURNS
-- TABLE names are in scope as parameters.
create or replace function public.staff_file_gaps(p_centre uuid)
returns table (
  person_id uuid,
  full_name text,
  role public.role_id,
  requirement_key text,
  requirement_label text,
  regulation text,
  note text,
  state text,
  expires_on date,
  has_document boolean
)
language sql stable security definer
set search_path = public
as $$
  with workforce as (
    select distinct on (pr.person_id, pr.role)
      pr.person_id, pr.role, p.full_name
    from public.person_role pr
    join public.person p on p.id = pr.person_id
    where pr.centre_id = p_centre and pr.active and pr.role <> 'family_adult'
  ),
  needed as (
    select w.person_id, w.full_name, w.role, r.*
    from workforce w
    join public.staff_requirement r on w.role = any (r.applies_to)
    join public.centre c on c.jurisdiction_code = r.jurisdiction_code
    where c.id = p_centre
  ),
  best as (
    select
      n.person_id, n.full_name, n.role, n.key, n.label, n.regulation, n.note, n.ordinal,
      (
        select cr.expires_on from public.credential cr
        where cr.person_id = n.person_id and cr.centre_id = p_centre
          and cr.credential_type = n.credential_type and cr.superseded_at is null
        order by cr.expires_on desc nulls last limit 1
      ) as best_expiry,
      exists (
        select 1 from public.credential cr
        where cr.person_id = n.person_id and cr.centre_id = p_centre
          and cr.credential_type = n.credential_type and cr.superseded_at is null
      ) as on_file,
      exists (
        select 1 from public.credential cr
        join public.staff_document d on d.credential_id = cr.id and d.superseded_at is null
        where cr.person_id = n.person_id and cr.centre_id = p_centre
          and cr.credential_type = n.credential_type
      ) as documented
    from needed n
  )
  select
    b.person_id, b.full_name, b.role, b.key, b.label, b.regulation, b.note,
    case
      when not b.on_file then 'missing'
      when b.best_expiry is null then 'on_file'
      when b.best_expiry < current_date then 'expired'
      when b.best_expiry < current_date + 60 then 'expiring_soon'
      else 'current'
    end,
    b.best_expiry,
    b.documented
  from best b
  order by b.full_name, b.ordinal
$$;

-- s. 61: an offence declaration for every year in which no VSC was obtained.
create or replace function public.offence_declaration_gaps(p_centre uuid)
returns table (person_id uuid, full_name text, missing_year integer)
language sql stable security definer
set search_path = public
as $$
  with workforce as (
    select distinct pr.person_id, p.full_name,
      -- the year they first appear in the file is where the duty starts
      least(
        extract(year from min(pr.created_at) over (partition by pr.person_id))::int,
        extract(year from current_date)::int
      ) as from_year
    from public.person_role pr
    join public.person p on p.id = pr.person_id
    where pr.centre_id = p_centre and pr.active and pr.role <> 'family_adult'
  ),
  years as (
    select w.person_id, w.full_name, y::int as yr
    from workforce w, generate_series(w.from_year, extract(year from current_date)::int) y
  )
  select y.person_id, y.full_name, y.yr
  from years y
  where not exists (
      select 1 from public.credential cr
      where cr.person_id = y.person_id and cr.centre_id = p_centre
        and cr.credential_type = 'vsc' and cr.superseded_at is null
        and extract(year from cr.issued_on) = y.yr
    )
    and not exists (
      select 1 from public.credential cr
      where cr.person_id = y.person_id and cr.centre_id = p_centre
        and cr.credential_type = 'offence_declaration' and cr.superseded_at is null
        and cr.declaration_year = y.yr
    )
  order by y.full_name, y.yr
$$;

-- ── RPCs ────────────────────────────────────────────────────────────────────
create or replace function public.record_credential(
  p_centre uuid,
  p_person uuid,
  p_type public.credential_type,
  p_issued_on date,
  p_expires_on date,
  p_checked_on date,
  p_police_service text,
  p_declaration_year integer,
  p_notes text,
  p_recorder uuid,
  p_pin text
) returns public.credential
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.credential;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate')
  ) then
    raise exception 'staff files are kept by centre leadership';
  end if;

  -- a newer record of the same kind supersedes the last, so the file shows
  -- the current position and the history both
  update public.credential
  set superseded_at = now()
  where centre_id = p_centre and person_id = p_person
    and credential_type = p_type and superseded_at is null
    and (p_type <> 'offence_declaration' or declaration_year = p_declaration_year);

  insert into public.credential (
    centre_id, person_id, credential_type, issued_on, expires_on, checked_on,
    police_service, declaration_year, notes, recorded_by
  ) values (
    p_centre, p_person, p_type, p_issued_on, p_expires_on, p_checked_on,
    nullif(trim(coalesce(p_police_service, '')), ''), p_declaration_year,
    nullif(trim(coalesce(p_notes, '')), ''), recorder
  ) returning * into result;
  return result;
end;
$$;

-- The row that says a file was uploaded. The upload itself goes straight to
-- storage from the browser; this records what it is and ties it to the
-- credential it evidences.
create or replace function public.attach_staff_document(
  p_centre uuid,
  p_person uuid,
  p_credential uuid,
  p_kind text,
  p_storage_path text,
  p_file_name text,
  p_content_type text,
  p_size_bytes integer,
  p_note text,
  p_recorder uuid,
  p_pin text
) returns public.staff_document
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.staff_document;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = p_centre and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate')
  ) then
    raise exception 'staff files are kept by centre leadership';
  end if;

  insert into public.staff_document (
    centre_id, person_id, credential_id, kind, storage_path, file_name,
    content_type, size_bytes, note, uploaded_by
  ) values (
    p_centre, p_person, p_credential, coalesce(p_kind, 'credential_evidence'),
    p_storage_path, trim(p_file_name), p_content_type, p_size_bytes,
    nullif(trim(coalesce(p_note, '')), ''), recorder
  ) returning * into result;

  -- keep the credential's convenience pointer in step
  if p_credential is not null then
    update public.credential set evidence_path = p_storage_path where id = p_credential;
  end if;
  return result;
end;
$$;

create or replace function public.supersede_staff_document(
  p_document uuid,
  p_replacement uuid,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  d public.staff_document;
begin
  select * into d from public.staff_document where id = p_document;
  if d.id is null then raise exception 'document not found'; end if;
  perform app.resolve_recorder(d.centre_id, p_recorder, p_pin);
  if d.superseded_at is not null then raise exception 'already replaced'; end if;

  update public.staff_document
  set superseded_at = now(), superseded_by = p_replacement
  where id = p_document;
end;
$$;
