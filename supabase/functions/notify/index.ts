/**
 * notify — hands pending notifications to Expo's push service.
 *
 * This function is deliberately a dumb pipe. WHICH notifications get pushed is
 * a product promise (every Now alert; of the Later feed only the daily story,
 * at most one per person per day) and that promise lives in the database as
 * app.notifications_to_push, where pgTAP can hold it to account. Nothing here
 * decides anything.
 *
 * What it does own is honesty about the send:
 *   - a notification is marked pushed ONLY if Expo accepted that exact message;
 *   - anything else records the reason and stays pending for the next run;
 *   - DeviceNotRegistered retires the token instead of failing forever.
 *
 * Called every two minutes by pg_cron → pg_net (see migration 0033), or by
 * hand in development:
 *   supabase functions serve notify
 *   curl -X POST http://127.0.0.1:54321/functions/v1/notify \
 *        -H "x-tucked-push-secret: <app_setting.push_shared_secret>"
 */

import { createClient } from 'npm:@supabase/supabase-js@2';

// Overridable so the send path — ticket handling, retirement of dead tokens —
// can be exercised against a stub instead of Expo's live service.
const EXPO_PUSH_URL = Deno.env.get('EXPO_PUSH_URL') ?? 'https://exp.host/--/api/v2/push/send';
const BATCH = 100;

interface Pending {
  notification_id: string;
  person_id: string;
  channel: string;
  event_type: string;
  title: string;
  body: string;
  token: string;
  platform: string | null;
}

interface Ticket {
  status: 'ok' | 'error';
  id?: string;
  message?: string;
  details?: { error?: string };
}

Deno.serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // The dispatcher holds a purpose-limited secret, not the service-role key,
  // so this endpoint cannot be triggered by any signed-in user who happens to
  // find the URL.
  const expected = Deno.env.get('PUSH_SHARED_SECRET');
  if (expected && req.headers.get('x-tucked-push-secret') !== expected) {
    return Response.json({ error: 'forbidden' }, { status: 403 });
  }

  const { data, error } = await supabase.rpc('notifications_to_push', { p_limit: 200 });
  if (error) return Response.json({ error: error.message }, { status: 500 });
  const pending = (data ?? []) as Pending[];
  if (pending.length === 0) return Response.json({ pending: 0, sent: 0, failed: 0 });

  const sentIds = new Set<string>();
  const failed: { id: string; error: string }[] = [];
  const deadTokens: { token: string; reason: string }[] = [];

  for (let i = 0; i < pending.length; i += BATCH) {
    const chunk = pending.slice(i, i + BATCH);
    const messages = chunk.map((n) => ({
      to: n.token,
      title: n.title,
      body: n.body,
      sound: n.channel === 'now' ? 'default' : undefined,
      priority: n.channel === 'now' ? 'high' : 'default',
      channelId: n.channel, // the Android channels the app creates on first run
      interruptionLevel: n.channel === 'now' ? 'timeSensitive' : 'active',
      data: { eventType: n.event_type, notificationId: n.notification_id },
    }));

    let tickets: Ticket[] | null = null;
    let transportError: string | null = null;
    try {
      const res = await fetch(EXPO_PUSH_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify(messages),
      });
      if (!res.ok) {
        transportError = `Expo returned ${res.status} ${res.statusText}`;
      } else {
        const payload = await res.json();
        tickets = (payload?.data ?? null) as Ticket[] | null;
        if (!tickets) transportError = 'Expo returned no tickets';
      }
    } catch (e) {
      transportError = e instanceof Error ? e.message : String(e);
    }

    if (transportError || !tickets) {
      // The whole chunk is unsent. Nothing here is marked as pushed.
      for (const n of chunk) failed.push({ id: n.notification_id, error: transportError! });
      continue;
    }

    tickets.forEach((ticket, idx) => {
      const n = chunk[idx];
      if (!n) return;
      if (ticket.status === 'ok') {
        sentIds.add(n.notification_id);
        return;
      }
      const detail = ticket.details?.error ?? ticket.message ?? 'rejected by Expo';
      failed.push({ id: n.notification_id, error: detail });
      if (ticket.details?.error === 'DeviceNotRegistered') {
        deadTokens.push({ token: n.token, reason: 'DeviceNotRegistered' });
      }
    });
  }

  // A notification can have several devices. It counts as sent if ANY of them
  // was accepted; only the ones with no accepted device are failures — and
  // each is counted ONCE, however many devices refused it. Counting per
  // message would burn a two-device parent's five retries in two runs.
  const failureByNotification = new Map<string, string>();
  for (const f of failed) {
    if (sentIds.has(f.id) || failureByNotification.has(f.id)) continue;
    failureByNotification.set(f.id, f.error);
  }
  const uniqueDeadTokens = new Map(deadTokens.map((t) => [t.token, t.reason]));

  if (sentIds.size > 0) {
    await supabase.rpc('mark_push_sent', { p_ids: [...sentIds] });
  }
  for (const [id, message] of failureByNotification) {
    await supabase.rpc('mark_push_failed', { p_id: id, p_error: message });
  }
  for (const [token, reason] of uniqueDeadTokens) {
    await supabase.rpc('revoke_push_token', { p_token: token, p_reason: reason });
  }

  return Response.json({
    messages: pending.length,
    sent: sentIds.size,
    failed: failureByNotification.size,
    tokensRetired: uniqueDeadTokens.size,
  });
});
