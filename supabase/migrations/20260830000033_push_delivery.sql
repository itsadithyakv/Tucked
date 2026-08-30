-- 0033 push delivery: actually getting a Now alert onto a phone.
--
-- Until this migration, every notification was created correctly and shown
-- correctly in the app, and nothing ever left the building. The Edge Function
-- that talks to Expo existed but nothing deployed or scheduled it. That was
-- the widest gap between what Tucked promises a parent and what it does.
--
-- What this changes:
--
--   * THE RULE LIVES IN THE DATABASE, NOT IN THE TRANSPORT. Which
--     notifications get pushed is a product promise — every Now alert, and of
--     the Later feed only the daily story, at most one per person per day —
--     so it belongs somewhere it can be tested, not inside a Deno file nobody
--     runs in CI. app.notifications_to_push is that rule. The Edge Function
--     is now a dumb pipe.
--   * A FAILED PUSH IS NEVER MARKED AS SENT. The old function set pushed_at
--     on everything it had tried, whether Expo accepted it or not — so a Now
--     alert about a sick child could be swallowed by one bad HTTP response
--     and never retried. Sent and failed are now separate outcomes, failures
--     carry the reason, and a notification is retried until it succeeds or
--     five attempts have gone by.
--   * A DEAD TOKEN IS RETIRED. Expo answers DeviceNotRegistered when an app
--     has been uninstalled; that token is revoked rather than pushed at
--     forever.
--   * NOBODY IS SILENTLY UNREACHABLE. A parent with no registered device is
--     not a failure and not a success — they simply have no phone attached,
--     and undeliverable_now_alerts says so out loud, because a Now alert
--     nobody can receive is an operational fact a supervisor needs.
--   * THE SCHEDULE SHIPS WITH THE SCHEMA. pg_cron calls the function every
--     two minutes through pg_net. It no-ops safely until an environment fills
--     in its two settings, so a local stack and a fresh branch stay quiet.

create extension if not exists pg_net;

-- ── environment settings ────────────────────────────────────────────────────
-- Two values per environment: where the function lives, and a shared secret
-- that is NOT the service-role key. The dispatcher holds a purpose-limited
-- credential so a leak of this table cannot read a single child's record.
create table public.app_setting (
  key text primary key,
  value text not null,
  note text,
  updated_at timestamptz not null default now()
);

alter table public.app_setting enable row level security;
-- No policies at all. Only SECURITY DEFINER functions and the service role
-- ever read this, exactly like staff_pin.

comment on table public.app_setting is
  'Per-environment wiring for background jobs. No RLS policy exists: nothing '
  'client-side reads this table. push_function_url and push_shared_secret are '
  'filled in per environment at deploy time; until they are, the push '
  'dispatcher no-ops.';

create or replace function app.setting(p_key text)
returns text
language sql stable security definer
set search_path = public
as $$ select value from public.app_setting where key = p_key $$;

-- ── what a push attempt leaves behind ───────────────────────────────────────
alter table public.notification
  add column push_attempts integer not null default 0,
  add column push_error text,
  add column last_push_attempt_at timestamptz;

alter table public.device_push_token
  add column revoked_at timestamptz,
  add column revoked_reason text;

create index device_push_token_live on public.device_push_token (person_id)
  where revoked_at is null;

-- ── the rule ────────────────────────────────────────────────────────────────
-- Every Now alert, always. Of the Later feed, only the daily story — and only
-- one story push per person per day, which is the whole of the quiet promise.
-- Now alerts come first, then oldest first, so a backlog cannot starve an
-- urgent one.
create or replace function app.notifications_to_push(p_limit integer default 200)
returns table (
  notification_id uuid,
  person_id uuid,
  channel text,
  event_type text,
  title text,
  body text,
  token text,
  platform text
)
language sql stable security definer
set search_path = public
as $$
  with eligible as (
    select n.*
    from public.notification n
    where n.pushed_at is null
      and n.push_attempts < 5
      -- a recipient with no live device must not consume the batch limit and
      -- starve somebody who does have a phone
      and exists (
        select 1 from public.device_push_token t
        where t.person_id = n.recipient_person_id and t.revoked_at is null
      )
      and (
        n.channel = 'now'
        or (
          n.channel = 'later' and n.event_type = 'story'
          -- one story push per person per day, and no others
          and not exists (
            select 1 from public.notification prev
            where prev.recipient_person_id = n.recipient_person_id
              and prev.event_type = 'story'
              and prev.pushed_at is not null
              and prev.pushed_at >= date_trunc('day', now())
          )
          and n.id = (
            select n2.id from public.notification n2
            where n2.recipient_person_id = n.recipient_person_id
              and n2.event_type = 'story' and n2.pushed_at is null
            order by n2.created_at desc limit 1
          )
        )
      )
    order by (n.channel = 'now') desc, n.created_at
    limit p_limit
  )
  select
    e.id, e.recipient_person_id, e.channel::text, e.event_type, e.title, e.body,
    t.token, t.platform
  from eligible e
  join public.device_push_token t
    on t.person_id = e.recipient_person_id and t.revoked_at is null
$$;

-- Handed to Expo and accepted.
create or replace function app.mark_push_sent(p_ids uuid[])
returns integer
language sql security definer
set search_path = public
as $$
  with done as (
    update public.notification
    set pushed_at = now(),
        push_error = null,
        last_push_attempt_at = now(),
        push_attempts = push_attempts + 1
    where id = any (p_ids) and pushed_at is null
    returning 1
  )
  select count(*)::integer from done
$$;

-- Refused, or the transport fell over. pushed_at stays null on purpose: this
-- will be tried again.
create or replace function app.mark_push_failed(p_id uuid, p_error text)
returns void
language sql security definer
set search_path = public
as $$
  update public.notification
  set push_attempts = push_attempts + 1,
      last_push_attempt_at = now(),
      push_error = left(coalesce(p_error, 'unknown error'), 500)
  where id = p_id and pushed_at is null
$$;

-- The app was uninstalled. Retire the token instead of pushing at it forever.
create or replace function app.revoke_push_token(p_token text, p_reason text)
returns void
language sql security definer
set search_path = public
as $$
  update public.device_push_token
  set revoked_at = now(), revoked_reason = left(coalesce(p_reason, 'unknown'), 200)
  where token = p_token and revoked_at is null
$$;

-- ── the transport's four calls, and nobody else's ───────────────────────────
-- PostgREST cannot see the app schema, so the Edge Function needs wrappers in
-- public. Every one of them is then REVOKED from anon and authenticated: these
-- read every centre's notifications and mark them delivered, so only the
-- service role — the function itself — may call them. Without the revoke,
-- Supabase's default grant would let any signed-in parent mark the whole
-- centre's alerts as pushed.
create or replace function public.notifications_to_push(p_limit integer default 200)
returns table (
  notification_id uuid, person_id uuid, channel text, event_type text,
  title text, body text, token text, platform text
)
language sql stable security definer
set search_path = public
as $$ select * from app.notifications_to_push(p_limit) $$;

create or replace function public.mark_push_sent(p_ids uuid[])
returns integer
language sql security definer
set search_path = public
as $$ select app.mark_push_sent(p_ids) $$;

create or replace function public.mark_push_failed(p_id uuid, p_error text)
returns void
language sql security definer
set search_path = public
as $$ select app.mark_push_failed(p_id, p_error) $$;

create or replace function public.revoke_push_token(p_token text, p_reason text)
returns void
language sql security definer
set search_path = public
as $$ select app.revoke_push_token(p_token, p_reason) $$;

-- FROM PUBLIC, not just from anon and authenticated: PostgreSQL grants EXECUTE
-- on a new function to PUBLIC, and both roles inherit it. Revoking only the
-- named roles leaves the door open, which is exactly what happened the first
-- time this was written.
revoke execute on function public.notifications_to_push(integer) from public, anon, authenticated;
revoke execute on function public.mark_push_sent(uuid[]) from public, anon, authenticated;
revoke execute on function public.mark_push_failed(uuid, text) from public, anon, authenticated;
revoke execute on function public.revoke_push_token(text, text) from public, anon, authenticated;

grant execute on function public.notifications_to_push(integer) to service_role;
grant execute on function public.mark_push_sent(uuid[]) to service_role;
grant execute on function public.mark_push_failed(uuid, text) to service_role;
grant execute on function public.revoke_push_token(text, text) to service_role;

-- ── nobody is silently unreachable ──────────────────────────────────────────
-- A Now alert to somebody with no live device. Not a failure — there is no
-- phone to fail at — but a supervisor should know that the alert about a
-- child is sitting in an app nobody has installed.
-- "Has this person got a phone attached?" is answered by a definer function on
-- purpose. A push token is private to its owner, so a security_invoker view
-- asking `not exists (… device_push_token …)` would find nothing for anybody
-- else and report the whole centre as unreachable. The notification rows stay
-- RLS-scoped to the caller; only the yes/no about a device is privileged.
create or replace function app.has_live_device(p_person uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.device_push_token t
    where t.person_id = p_person and t.revoked_at is null
  )
$$;

create view public.undeliverable_now_alerts
with (security_invoker = on) as
select
  n.id,
  n.centre_id,
  n.child_id,
  n.recipient_person_id,
  p.full_name as recipient_name,
  n.event_type,
  n.title,
  n.created_at
from public.notification n
join public.person p on p.id = n.recipient_person_id
where n.channel = 'now'
  and n.acknowledged_at is null
  and not app.has_live_device(n.recipient_person_id);

-- Alerts the transport could not get out: five attempts and still nothing.
create view public.stuck_push_alerts
with (security_invoker = on) as
select
  n.id, n.centre_id, n.recipient_person_id, n.channel, n.event_type, n.title,
  n.push_attempts, n.push_error, n.last_push_attempt_at, n.created_at
from public.notification n
where n.pushed_at is null and n.push_attempts >= 5;

-- ── the schedule ────────────────────────────────────────────────────────────
-- Calls the Edge Function through pg_net. Silent until an environment fills in
-- its settings, so a local stack, a preview branch and CI all stay quiet
-- rather than erroring every two minutes.
create or replace function app.dispatch_push()
returns text
language plpgsql security definer
set search_path = public
as $$
declare
  url text := app.setting('push_function_url');
  secret text := app.setting('push_shared_secret');
  waiting integer;
begin
  if url is null or secret is null then
    return 'not configured';
  end if;

  select count(*) into waiting from app.notifications_to_push(1);
  if waiting = 0 then
    return 'nothing waiting';
  end if;

  perform net.http_post(
    url := url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-tucked-push-secret', secret
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
  return 'dispatched';
end;
$$;

select cron.schedule('push-dispatch', '*/2 * * * *', $$select app.dispatch_push()$$);

-- ── wiring an environment (the whole deploy) ────────────────────────────────
--
--   1. Deploy the function, and give it the same secret the database will send:
--
--        supabase functions deploy notify
--        supabase secrets set PUSH_SHARED_SECRET="$(openssl rand -hex 24)"
--
--   2. Tell the dispatcher where it lives and what to send, as the service
--      role (no client can read or write app_setting):
--
--        insert into public.app_setting (key, value, note) values
--          ('push_function_url', 'https://<project-ref>.supabase.co/functions/v1/notify', 'set at deploy'),
--          ('push_shared_secret', '<the same secret>', 'set at deploy')
--        on conflict (key) do update set value = excluded.value, updated_at = now();
--
-- Until step 2 runs, app.dispatch_push() returns 'not configured' every two
-- minutes and nothing else happens. There is no half-configured state that
-- silently drops alerts.
--
-- To exercise the send path without touching Expo, point the function at a
-- stub: EXPO_PUSH_URL is read from the environment and defaults to the real
-- service.
