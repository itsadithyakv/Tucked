-- 0015: accident reports notify the family AUTOMATICALLY (database trigger,
-- not app goodwill) — a Now alert per viewing household adult, carrying the
-- report id so one acknowledgement closes both records. Acknowledging the
-- report (the s. 36(4) evidence) also settles the recipient's alert.

alter table public.notification
  add column ref_id uuid; -- what the alert is about (accident report, …)

create or replace function app.accident_notify()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.notification (
    centre_id, child_id, recipient_person_id, channel, event_type,
    title, body, requires_acknowledgement, created_by, ref_id
  )
  select
    new.centre_id, new.child_id, hm.person_id, 'now', 'accident_report',
    'Accident report for ' || split_part(ch.full_name, ' ', 1),
    'Please read the report and acknowledge that you received your copy.',
    true, new.completed_by, new.id
  from public.child ch
  join public.child_household chh on chh.child_id = ch.id
  join public.household_member hm on hm.household_id = chh.household_id
  where ch.id = new.child_id
    and hm.revoked_at is null
    and hm.can_view;
  return new;
end;
$$;

create trigger accident_notify
  after insert on public.accident_report
  for each row execute function app.accident_notify();

-- Acknowledging the report also acknowledges this parent's alert about it.
create or replace function public.acknowledge_accident_report(p_report uuid)
returns public.accident_report
language plpgsql security definer
set search_path = public
as $$
declare
  result public.accident_report;
  me uuid;
begin
  select * into result from public.accident_report where id = p_report;
  if result.id is null then raise exception 'report not found'; end if;
  me := app.current_person_id();
  if not exists (
    select 1 from public.child_household ch
    join public.household_member hm on hm.household_id = ch.household_id
    where ch.child_id = result.child_id
      and hm.person_id = me
      and hm.revoked_at is null
      and hm.can_view
  ) then
    raise exception 'only a household member of this child may acknowledge' using errcode = '42501';
  end if;
  if result.parent_ack_at is null then
    update public.accident_report
    set parent_ack_person_id = me, parent_ack_at = now()
    where id = p_report
    returning * into result;
  end if;
  update public.notification
  set acknowledged_at = coalesce(acknowledged_at, now()),
      delivered_at = coalesce(delivered_at, now())
  where ref_id = p_report and recipient_person_id = me;
  return result;
end;
$$;
