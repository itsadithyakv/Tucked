-- 0035 delivery receipts: the difference between "sent" and "arrived".
--
-- Migration 0033 recorded a notification as pushed when Expo ACCEPTED it. That
-- is a ticket, not a delivery. Expo hands back a receipt a few minutes later
-- saying what actually became of the message — the device had unregistered,
-- the payload was too big, the credentials were wrong, or it arrived. Without
-- reading the receipt, "sent" was our word for "handed over and hoped".
--
--   * A TICKET IS KEPT FOR EVERY ACCEPTED MESSAGE, per notification and per
--     device, so a receipt can be traced back to the phone it was about.
--   * delivered_at — a column that has sat unused since migration 0011 —
--     finally means something: the first receipt that comes back ok.
--   * A RECEIPT THAT COMES BACK ERROR IS LOUD. push_never_arrived lists
--     notifications we recorded as sent and Expo then told us never landed,
--     so a supervisor learns that an alert about a sick child did not ring
--     rather than assuming it did.
--   * DeviceNotRegistered in a receipt retires the token, exactly as it does
--     in a ticket. It is the commonest reason a push quietly dies.

create table public.push_ticket (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notification (id),
  token text not null,
  -- Expo's own id for the accepted message; the key its receipt comes back on
  expo_ticket_id text not null unique,
  accepted_at timestamptz not null default now(),
  receipt_checked_at timestamptz,
  receipt_status text check (receipt_status in ('ok', 'error')),
  receipt_error text,
  created_at timestamptz not null default now()
);

create index push_ticket_awaiting on public.push_ticket (accepted_at)
  where receipt_checked_at is null;
create index push_ticket_notification on public.push_ticket (notification_id);

alter table public.push_ticket enable row level security;
-- No policies. Like app_setting and staff_pin, this is the transport's own
-- bookkeeping: the service role reads it and nobody else.

create trigger push_ticket_no_delete before delete on public.push_ticket
  for each row execute function app.block_mutation();

-- ── recording what Expo said ────────────────────────────────────────────────
create or replace function app.record_push_tickets(p_tickets jsonb)
returns integer
language sql security definer
set search_path = public
as $fn$
  with inserted as (
    insert into public.push_ticket (notification_id, token, expo_ticket_id)
    select
      (t ->> 'notification_id')::uuid,
      t ->> 'token',
      t ->> 'expo_ticket_id'
    from jsonb_array_elements(p_tickets) t
    where coalesce(t ->> 'expo_ticket_id', '') <> ''
    on conflict (expo_ticket_id) do nothing
    returning 1
  )
  select count(*)::integer from inserted
$fn$;

-- Expo asks for a few minutes before a receipt exists, and keeps them for
-- about a day. Anything older than that will never have one, so it is closed
-- off rather than asked about forever.
create or replace function app.push_tickets_awaiting_receipt(p_limit integer default 300)
returns table (expo_ticket_id text)
language sql stable security definer
set search_path = public
as $fn$
  select t.expo_ticket_id
  from public.push_ticket t
  where t.receipt_checked_at is null
    and t.accepted_at < now() - interval '5 minutes'
    and t.accepted_at > now() - interval '23 hours'
  order by t.accepted_at
  limit p_limit
$fn$;

create or replace function app.record_push_receipt(
  p_expo_ticket_id text,
  p_status text,
  p_error text
) returns void
language plpgsql security definer
set search_path = public
as $fn$
declare
  ticket public.push_ticket;
begin
  select * into ticket from public.push_ticket where expo_ticket_id = p_expo_ticket_id;
  if ticket.id is null then return; end if;

  update public.push_ticket
  set receipt_checked_at = now(),
      receipt_status = p_status,
      receipt_error = left(nullif(coalesce(p_error, ''), ''), 300)
  where id = ticket.id;

  if p_status = 'ok' then
    -- the first receipt that comes back ok is the moment it arrived
    update public.notification
    set delivered_at = coalesce(delivered_at, now())
    where id = ticket.notification_id;
  elsif p_error = 'DeviceNotRegistered' then
    perform app.revoke_push_token(ticket.token, 'DeviceNotRegistered (receipt)');
  end if;
end;
$fn$;

-- Tickets Expo never produced a receipt for. Closed off so the transport does
-- not ask about them forever; the notification keeps whatever it had.
create or replace function app.close_stale_push_tickets()
returns integer
language sql security definer
set search_path = public
as $fn$
  with closed as (
    update public.push_ticket
    set receipt_checked_at = now(),
        receipt_status = 'error',
        receipt_error = 'no receipt from Expo within 24 hours'
    where receipt_checked_at is null
      and accepted_at <= now() - interval '23 hours'
    returning 1
  )
  select count(*)::integer from closed
$fn$;

select cron.schedule('push-ticket-sweep', '25 3 * * *', $cron$select app.close_stale_push_tickets()$cron$);

-- ── what did not arrive ─────────────────────────────────────────────────────
-- We said it was sent; Expo came back and said it was not.
--
-- The two questions about tickets are answered by SECURITY DEFINER functions,
-- not inline in the view. push_ticket has RLS on and no policies at all, so a
-- security_invoker view asking "does a failed ticket exist?" would see none
-- for anybody and quietly report that everything arrived. That is the same
-- trap undeliverable_now_alerts fell into in migration 0033 — a view that
-- reasons about the ABSENCE of rows must be able to see the whole table. The
-- notification rows themselves stay RLS-scoped to the caller.
create or replace function app.push_all_tickets_failed(p_notification uuid)
returns boolean
language sql stable security definer
set search_path = public
as $fn$
  select exists (
      select 1 from public.push_ticket t
      where t.notification_id = p_notification and t.receipt_status = 'error'
    )
    and not exists (
      select 1 from public.push_ticket t
      where t.notification_id = p_notification
        and t.receipt_status is distinct from 'error'
    )
$fn$;

create or replace function app.push_failure_reason(p_notification uuid)
returns text
language sql stable security definer
set search_path = public
as $fn$
  select string_agg(distinct t.receipt_error, '; ')
  from public.push_ticket t
  where t.notification_id = p_notification and t.receipt_error is not null
$fn$;

create view public.push_never_arrived
with (security_invoker = on) as
select
  n.id,
  n.centre_id,
  n.child_id,
  n.recipient_person_id,
  p.full_name as recipient_name,
  n.channel,
  n.event_type,
  n.title,
  n.pushed_at,
  app.push_failure_reason(n.id) as why
from public.notification n
join public.person p on p.id = n.recipient_person_id
where n.pushed_at is not null
  and n.delivered_at is null
  and n.acknowledged_at is null
  and app.push_all_tickets_failed(n.id);

-- ── the transport's calls, and nobody else's ────────────────────────────────
create or replace function public.record_push_tickets(p_tickets jsonb)
returns integer
language sql security definer
set search_path = public
as $fn$ select app.record_push_tickets(p_tickets) $fn$;

create or replace function public.push_tickets_awaiting_receipt(p_limit integer default 300)
returns table (expo_ticket_id text)
language sql stable security definer
set search_path = public
as $fn$ select * from app.push_tickets_awaiting_receipt(p_limit) $fn$;

create or replace function public.record_push_receipt(p_expo_ticket_id text, p_status text, p_error text)
returns void
language sql security definer
set search_path = public
as $fn$ select app.record_push_receipt(p_expo_ticket_id, p_status, p_error) $fn$;

-- FROM PUBLIC, because PostgreSQL grants EXECUTE to PUBLIC on a new function
-- and both anon and authenticated inherit it — migration 0033 learned that the
-- hard way, and its catalogue test passed while the door stood open.
revoke execute on function public.record_push_tickets(jsonb) from public, anon, authenticated;
revoke execute on function public.push_tickets_awaiting_receipt(integer) from public, anon, authenticated;
revoke execute on function public.record_push_receipt(text, text, text) from public, anon, authenticated;

grant execute on function public.record_push_tickets(jsonb) to service_role;
grant execute on function public.push_tickets_awaiting_receipt(integer) to service_role;
grant execute on function public.record_push_receipt(text, text, text) to service_role;
