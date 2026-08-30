-- 0018 headcount checks — the supervision layer (s. 11 adult supervision;
-- Part 4 written drill records; the Manual's transition/face-to-name
-- expectations). Distinct from s. 72(3) attendance BY DESIGN: sessions and
-- transitions never create arrive/depart events (those record only real
-- arrivals and departures, captured at the event). A headcount records that
-- a named person counted faces against the list at a moment that matters:
-- heading outside, coming back in, a spot check, a drill, a real evacuation.

create table public.headcount_check (
  id uuid primary key default gen_random_uuid(),
  centre_id uuid not null references public.centre (id),
  room_id uuid references public.room (id), -- null = whole centre (evacuations)
  kind text not null check (kind in ('transition_out', 'transition_in', 'spot', 'evacuation_drill', 'evacuation')),
  expected integer not null,
  counted integer not null,
  -- snapshot of anyone NOT accounted for at the moment of the count —
  -- [{child_id, full_name}]; empty when everyone was counted
  missing jsonb not null default '[]'::jsonb,
  note text,
  recorded_by uuid not null references public.person (id),
  device_id text,
  offline_recorded_at timestamptz,
  offline_synced_at timestamptz,
  created_at timestamptz not null default now()
);

create index headcount_centre_recent on public.headcount_check (centre_id, created_at desc);

alter table public.headcount_check enable row level security;

create policy headcount_select on public.headcount_check
  for select using (centre_id in (select app.care_centre_ids()));
-- Writes via the RPC only.

create trigger headcount_audit
  after insert on public.headcount_check
  for each row execute function app.audit_row();

create trigger headcount_no_delete
  before delete on public.headcount_check
  for each row execute function app.block_mutation();

-- Evacuations and drills belong in the daily written record (s. 37).
create or replace function app.headcount_cross_reference()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  tz text;
begin
  if new.kind in ('evacuation_drill', 'evacuation') then
    select c.timezone into tz from public.centre c where c.id = new.centre_id;
    perform app.dwr_append_ref(
      new.centre_id,
      (new.created_at at time zone tz)::date,
      jsonb_build_object(
        'type', new.kind,
        'headcount_id', new.id,
        'note', initcap(replace(new.kind, '_', ' ')) || ' — ' || new.counted || ' of ' || new.expected || ' accounted for'
      )
    );
  end if;
  return new;
end;
$$;

create trigger headcount_cross_reference
  after insert on public.headcount_check
  for each row execute function app.headcount_cross_reference();

create or replace function public.record_headcount(
  p_centre uuid,
  p_room uuid,
  p_kind text,
  p_expected integer,
  p_counted integer,
  p_missing jsonb,
  p_note text,
  p_recorder uuid,
  p_pin text,
  p_offline_recorded_at timestamptz default null,
  p_device text default null
) returns public.headcount_check
language plpgsql security definer
set search_path = public
as $$
declare
  recorder uuid;
  result public.headcount_check;
begin
  recorder := app.resolve_recorder(p_centre, p_recorder, p_pin);
  insert into public.headcount_check (
    centre_id, room_id, kind, expected, counted, missing, note,
    recorded_by, device_id, offline_recorded_at, offline_synced_at
  ) values (
    p_centre, p_room, p_kind, p_expected, p_counted, coalesce(p_missing, '[]'::jsonb), p_note,
    recorder, p_device, p_offline_recorded_at,
    case when p_offline_recorded_at is null then null else now() end
  ) returning * into result;
  return result;
end;
$$;
