-- 0023 break-glass access (s. 82(2)): electronic records are permitted only
-- if staff and Ministry officials can ALWAYS get in — "ask your admin to
-- unlock" is not an answer. Two failure modes, two mechanisms:
--
--   1. The supervisor is unavailable TODAY and a program advisor is standing
--      at the door: any care-staff member opens a break-glass — PIN-signed,
--      reason required, READ-ONLY, expires by itself after 24 hours, loudly
--      announced to every supervisor and written to the audit trail. It
--      unlocks exactly the inspection surfaces a supervisor can read (audit
--      trail, serious occurrences, staff credentials, retention clocks) and
--      grants no write anywhere. Billing stays out: inspectors audit care,
--      not money.
--   2. The supervisor is gone FOR GOOD (left, locked out of email, died):
--      a platform admin restores continuity with admin_grant_supervisor —
--      the same invite path as onboarding, audited, at the licensee's
--      request. Access is never lost permanently.

create table public.break_glass_access (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  person_id uuid not null references public.person (id),
  reason text not null,
  opened_at timestamptz not null default now(),
  expires_at timestamptz not null,
  closed_at timestamptz,
  closed_by uuid references public.person (id),
  created_at timestamptz not null default now()
);

create index break_glass_active on public.break_glass_access (centre_id, person_id)
  where closed_at is null;

alter table public.break_glass_access enable row level security;

-- Everyone at the centre can SEE that emergency access exists — transparency
-- is part of the deterrent. Writes via RPCs only.
create policy break_glass_select on public.break_glass_access
  for select using (centre_id in (select app.care_centre_ids()));

create trigger break_glass_audit
  after insert or update on public.break_glass_access
  for each row execute function app.audit_row();
create trigger break_glass_no_delete
  before delete on public.break_glass_access
  for each row execute function app.block_mutation();

create or replace function app.has_break_glass(p_centre uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.break_glass_access bg
    where bg.centre_id = p_centre
      and bg.person_id = app.current_person_id()
      and bg.closed_at is null
      and now() < bg.expires_at
  )
$$;

-- ── the read-only unlock: exactly the supervisor inspection surfaces ────────
create policy audit_break_glass_select on public.audit_event
  for select using (centre_id is not null and app.has_break_glass(centre_id));
create policy so_break_glass_select on public.serious_occurrence
  for select using (app.has_break_glass(centre_id));
create policy so_child_break_glass_select on public.serious_occurrence_child
  for select using (app.has_break_glass(centre_id));
create policy so_update_break_glass_select on public.serious_occurrence_update
  for select using (app.has_break_glass(centre_id));
create policy so_posting_break_glass_select on public.serious_occurrence_posting
  for select using (app.has_break_glass(centre_id));
create policy credential_break_glass_select on public.credential
  for select using (app.has_break_glass(centre_id));
create policy retention_break_glass_select on public.retention_clock
  for select using (app.has_break_glass(centre_id));
-- No insert/update/delete policy anywhere names has_break_glass: read-only by
-- construction, and pgTAP proves it stays that way.

-- ── RPCs ────────────────────────────────────────────────────────────────────
create or replace function public.open_break_glass(
  p_centre uuid,
  p_reason text,
  p_recorder uuid,
  p_pin text
) returns public.break_glass_access
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.break_glass_access;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if length(trim(coalesce(p_reason, ''))) < 10 then
    raise exception 'a break-glass needs a real reason — who needs the records and why the supervisor cannot provide them';
  end if;
  if exists (
    select 1 from public.break_glass_access
    where centre_id = p_centre and person_id = recorder
      and closed_at is null and now() < expires_at
  ) then
    raise exception 'you already have emergency access open';
  end if;

  insert into public.break_glass_access (centre_id, person_id, reason, expires_at)
  values (p_centre, recorder, trim(p_reason), now() + interval '24 hours')
  returning * into result;

  -- loud by design: every supervisor, designate and licensee admin is told
  insert into public.notification (
    centre_id, recipient_person_id, channel, event_type, title, body,
    requires_acknowledgement, created_by, ref_id
  )
  select
    p_centre, pr.person_id, 'now', 'break_glass',
    'Emergency records access opened',
    (select full_name from public.person where id = recorder) ||
      ' opened read-only emergency access (s. 82(2)). Reason: ' || trim(p_reason) ||
      '. It expires ' || to_char(result.expires_at, 'Mon FMDD HH24:MI') || ' or when you close it.',
    true, recorder, result.id
  from public.person_role pr
  where pr.centre_id = p_centre and pr.active
    and pr.role in ('licensee_admin', 'supervisor', 'designate')
    and pr.person_id <> recorder;

  return result;
end;
$$;

create or replace function public.close_break_glass(
  p_access uuid,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  bg public.break_glass_access;
  recorder uuid;
begin
  select * into bg from public.break_glass_access where id = p_access;
  if bg.id is null then raise exception 'break-glass record not found'; end if;
  recorder := app.resolve_recorder(bg.centre_id, p_recorder, p_pin);
  if bg.closed_at is not null then
    raise exception 'already closed';
  end if;
  -- the holder may close their own; otherwise centre leadership closes it
  if recorder <> bg.person_id and not exists (
    select 1 from public.person_role pr
    where pr.person_id = recorder and pr.centre_id = bg.centre_id and pr.active
      and pr.role in ('licensee_admin', 'supervisor', 'designate')
  ) then
    raise exception 'only the holder or centre leadership can close emergency access';
  end if;

  update public.break_glass_access
  set closed_at = now(), closed_by = recorder
  where id = p_access;
end;
$$;

-- ── continuity: the supervisor is gone for good ─────────────────────────────
-- Platform admins restore access at the licensee's request: find-or-invite a
-- person by email, grant (or reactivate) the supervisor role. They sign in
-- with a magic link; the 0019 trigger links them. person_role is audited.
create or replace function public.admin_grant_supervisor(
  p_centre uuid,
  p_full_name text,
  p_email text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_person uuid;
begin
  if not app.is_platform_admin() then
    raise exception 'platform admins only' using errcode = '42501';
  end if;
  if not exists (select 1 from public.centre where id = p_centre) then
    raise exception 'centre not found';
  end if;
  if p_email is null or position('@' in p_email) = 0 then
    raise exception 'a supervisor email is required — it is how they sign in';
  end if;

  select id into v_person from public.person where lower(email) = lower(p_email);
  if v_person is null then
    insert into public.person (full_name, email)
    values (p_full_name, lower(p_email))
    returning id into v_person;
  end if;

  insert into public.person_role (person_id, centre_id, role, qualified, active)
  values (v_person, p_centre, 'supervisor', true, true)
  on conflict (person_id, centre_id, role) do update set active = true;
end;
$$;
