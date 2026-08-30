-- 0016: family adults can see the WORKFORCE of their centre by name (a parent
-- must know which educator wrote back), while other FAMILIES stay invisible
-- to them. Adults within one household see each other. Staff visibility is
-- unchanged. Definer helper avoids policy recursion into person/household_member.

create or replace function app.is_household_comember(p_person uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.household_member a
    join public.household_member b on b.household_id = a.household_id
    join public.person me on me.id = a.person_id
    where me.auth_user_id = auth.uid()
      and a.revoked_at is null
      and b.revoked_at is null
      and b.person_id = p_person
  )
$$;

-- Definer: does this person hold a workforce role at any centre the caller
-- belongs to? (person_role is RLS-filtered for families, so the check must
-- run as definer.)
create or replace function app.is_centre_workforce(p_person uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.person_role pr
    where pr.person_id = p_person
      and pr.active
      and pr.role <> 'family_adult'
      and pr.centre_id in (select app.member_centre_ids())
  )
$$;

drop policy person_select on public.person;

create policy person_select on public.person
  for select using (
    auth_user_id = auth.uid()
    -- workforce members of a centre see everyone with a role there
    or exists (
      select 1 from public.person_role pr
      where pr.person_id = person.id
        and pr.centre_id in (select app.staff_centre_ids())
    )
    -- any member (incl. family) sees the centre's workforce — never other families
    or app.is_centre_workforce(person.id)
    -- adults in my own household see each other
    or app.is_household_comember(person.id)
  );
