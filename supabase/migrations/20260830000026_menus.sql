-- 0026 menus and feeding instructions (Part 6, ss. 42–44). The rules this
-- schema holds:
--   * The menu for the CURRENT and the FOLLOWING week must be planned and
--     posted where parents can see them — so posted weeks are readable by
--     every centre member, families included, and the console flags a
--     missing week.
--   * Substitutions are noted AT THE TIME: once a week is posted its planned
--     items are frozen; a change on the day is a substitution row carrying
--     what was planned, what was served, why, and who recorded it. Never
--     future-dated, never backdated outside the posted week.
--   * Posted menus are kept 30 days — here they are kept permanently and
--     never deleted, which clears that floor by a wide margin.
--   * s. 44: infants are fed per the PARENT'S WRITTEN INSTRUCTIONS, and
--     special dietary arrangements follow written instructions too. The
--     instruction names the parent who gave it, and that parent must be a
--     consenting household member — the same rule medication authorisations
--     and individualised plans use.
-- Meal slots deliberately match care_log's enum, so the planned menu and the
-- "what was eaten" logs line up on one axis.

create table public.menu_week (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  week_start date not null,
  status text not null default 'draft' check (status in ('draft', 'posted')),
  posted_at timestamptz,
  posted_by uuid references public.person (id),
  created_by uuid not null references public.person (id),
  created_at timestamptz not null default now(),
  unique (centre_id, week_start),
  -- weeks start on Monday: ISO day-of-week 1
  constraint menu_week_starts_monday check (extract(isodow from week_start) = 1)
);

create table public.menu_item (
  id uuid primary key default gen_random_uuid(),
  menu_week_id uuid not null references public.menu_week (id),
  centre_id uuid not null references public.centre (id),
  day_of_week integer not null check (day_of_week between 1 and 7),
  meal text not null check (meal in ('breakfast', 'snack_am', 'lunch', 'snack_pm')),
  description text not null,
  created_at timestamptz not null default now(),
  unique (menu_week_id, day_of_week, meal)
);

-- "Substitutions noted at the time" (s. 42): the posted menu never changes;
-- the day's reality is recorded beside it.
create table public.menu_substitution (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  served_on date not null,
  meal text not null check (meal in ('breakfast', 'snack_am', 'lunch', 'snack_pm')),
  planned text,
  served text not null,
  reason text not null,
  recorded_by uuid not null references public.person (id),
  created_at timestamptz not null default now()
);

create index menu_substitution_recent on public.menu_substitution (centre_id, served_on desc);

-- s. 44: written instructions from the parent — infant feeding, or a special
-- dietary arrangement for any child.
create table public.feeding_instruction (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  child_id uuid not null references public.child (id),
  kind text not null check (kind in ('infant_feeding', 'special_diet')),
  instructions text not null,
  provided_by uuid not null references public.person (id),
  effective_on date not null default current_date,
  recorded_by uuid not null references public.person (id),
  ended_at timestamptz,
  ended_by uuid references public.person (id),
  created_at timestamptz not null default now()
);

create index feeding_instruction_child on public.feeding_instruction (child_id) where ended_at is null;

-- ── visibility ──────────────────────────────────────────────────────────────
alter table public.menu_week enable row level security;
alter table public.menu_item enable row level security;
alter table public.menu_substitution enable row level security;
alter table public.feeding_instruction enable row level security;

-- Posted menus are for everyone at the centre — that IS the posting (s. 42).
-- Drafts belong to the people planning them.
create policy menu_week_select on public.menu_week
  for select using (
    (status = 'posted' and centre_id in (select app.member_centre_ids()))
    or centre_id in (select app.care_centre_ids())
  );

create policy menu_item_select on public.menu_item
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.menu_week w
      where w.id = menu_item.menu_week_id
        and w.status = 'posted'
        and w.centre_id in (select app.member_centre_ids())
    )
  );

-- A substitution is part of the posted menu: parents see it too.
create policy menu_substitution_select on public.menu_substitution
  for select using (centre_id in (select app.member_centre_ids()));

create policy feeding_instruction_select on public.feeding_instruction
  for select using (
    centre_id in (select app.care_centre_ids())
    or exists (
      select 1 from public.child_household ch
      where ch.child_id = feeding_instruction.child_id
        and ch.household_id in (select app.my_viewable_household_ids())
    )
  );
-- Writes via RPCs only.

create trigger menu_week_no_delete before delete on public.menu_week
  for each row execute function app.block_mutation();
create trigger menu_substitution_no_delete before delete on public.menu_substitution
  for each row execute function app.block_mutation();
create trigger feeding_instruction_no_delete before delete on public.feeding_instruction
  for each row execute function app.block_mutation();
create trigger menu_week_audit after insert or update on public.menu_week
  for each row execute function app.audit_row();
create trigger menu_substitution_audit after insert on public.menu_substitution
  for each row execute function app.audit_row();
create trigger feeding_instruction_audit after insert or update on public.feeding_instruction
  for each row execute function app.audit_row();

-- A posted week is frozen: changes on the day are substitutions, not edits.
create or replace function app.menu_item_rules()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  wk public.menu_week;
begin
  select * into wk from public.menu_week where id = coalesce(new.menu_week_id, old.menu_week_id);
  if wk.status = 'posted' then
    raise exception 'this week is posted — record a substitution on the day instead of editing the menu';
  end if;
  if tg_op <> 'DELETE' and coalesce(trim(new.description), '') = '' then
    raise exception 'a menu item needs a description';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger menu_item_rules
  before insert or update or delete on public.menu_item
  for each row execute function app.menu_item_rules();

-- ── RPCs ────────────────────────────────────────────────────────────────────
create or replace function public.upsert_menu_item(
  p_centre uuid,
  p_week_start date,
  p_day integer,
  p_meal text,
  p_description text,
  p_recorder uuid,
  p_pin text
) returns public.menu_item
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  wk public.menu_week;
  result public.menu_item;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);

  select * into wk from public.menu_week where centre_id = p_centre and week_start = p_week_start;
  if wk.id is null then
    insert into public.menu_week (centre_id, week_start, created_by)
    values (p_centre, p_week_start, recorder)
    returning * into wk;
  end if;

  insert into public.menu_item (menu_week_id, centre_id, day_of_week, meal, description)
  values (wk.id, p_centre, p_day, p_meal, trim(p_description))
  on conflict (menu_week_id, day_of_week, meal)
    do update set description = excluded.description
  returning * into result;
  return result;
end;
$$;

create or replace function public.post_menu_week(
  p_centre uuid,
  p_week_start date,
  p_recorder uuid,
  p_pin text
) returns public.menu_week
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  wk public.menu_week;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  select * into wk from public.menu_week where centre_id = p_centre and week_start = p_week_start;
  if wk.id is null then raise exception 'no menu planned for that week yet'; end if;
  if wk.status = 'posted' then raise exception 'that week is already posted'; end if;
  if not exists (select 1 from public.menu_item where menu_week_id = wk.id) then
    raise exception 'there is nothing on this menu to post';
  end if;

  update public.menu_week
  set status = 'posted', posted_at = now(), posted_by = recorder
  where id = wk.id
  returning * into wk;
  return wk;
end;
$$;

create or replace function public.record_menu_substitution(
  p_centre uuid,
  p_served_on date,
  p_meal text,
  p_served text,
  p_reason text,
  p_recorder uuid,
  p_pin text
) returns public.menu_substitution
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  planned text;
  result public.menu_substitution;
  served_date date := coalesce(p_served_on, current_date);
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if coalesce(trim(p_served), '') = '' or coalesce(trim(p_reason), '') = '' then
    raise exception 'a substitution records what was served instead and why';
  end if;
  if served_date > current_date then
    raise exception 'substitutions are noted at the time — not before the day';
  end if;

  -- snapshot what the posted menu promised, so the pair reads together later
  select mi.description into planned
  from public.menu_item mi
  join public.menu_week w on w.id = mi.menu_week_id
  where w.centre_id = p_centre
    and w.week_start = date_trunc('week', served_date)::date
    and mi.day_of_week = extract(isodow from served_date)
    and mi.meal = p_meal;

  insert into public.menu_substitution (centre_id, served_on, meal, planned, served, reason, recorded_by)
  values (p_centre, served_date, p_meal, planned, trim(p_served), trim(p_reason), recorder)
  returning * into result;
  return result;
end;
$$;

create or replace function public.record_feeding_instruction(
  p_centre uuid,
  p_child uuid,
  p_kind text,
  p_instructions text,
  p_parent uuid,
  p_recorder uuid,
  p_pin text
) returns public.feeding_instruction
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.feeding_instruction;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  if coalesce(trim(p_instructions), '') = '' then
    raise exception 'record the parent''s written instructions';
  end if;
  -- s. 44: the instructions come FROM the parent, so name one who may consent
  if not exists (
    select 1 from public.child_household ch
    join public.household_member hm on hm.household_id = ch.household_id
    where ch.child_id = p_child
      and hm.person_id = p_parent
      and hm.revoked_at is null
      and hm.can_consent
  ) then
    raise exception 'feeding instructions must come from a consenting household member';
  end if;

  -- one live instruction per child and kind
  update public.feeding_instruction
  set ended_at = now(), ended_by = recorder
  where child_id = p_child and kind = p_kind and ended_at is null;

  insert into public.feeding_instruction (
    centre_id, child_id, kind, instructions, provided_by, recorded_by
  ) values (
    p_centre, p_child, p_kind, trim(p_instructions), p_parent, recorder
  ) returning * into result;
  return result;
end;
$$;

create or replace function public.end_feeding_instruction(
  p_instruction uuid,
  p_recorder uuid,
  p_pin text
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  fi public.feeding_instruction;
  recorder uuid;
begin
  select * into fi from public.feeding_instruction where id = p_instruction;
  if fi.id is null then raise exception 'instruction not found'; end if;
  recorder := app.resolve_recorder(fi.centre_id, p_recorder, p_pin);
  if fi.ended_at is not null then raise exception 'already ended'; end if;
  update public.feeding_instruction
  set ended_at = now(), ended_by = recorder
  where id = p_instruction;
end;
$$;
