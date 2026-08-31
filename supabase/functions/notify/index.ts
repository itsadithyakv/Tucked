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
const EXPO_RECEIPT_URL =
  Deno.env.get('EXPO_RECEIPT_URL') ?? 'https://exp.host/--/api/v2/push/getReceipts';
const BATCH = 100;
const RECEIPT_BATCH = 300;

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

interface Receipt {
  status: 'ok' | 'error';
  message?: string;
  details?: { error?: string };
}

/** Expo answers with a receipt a few minutes after it accepts a message. The
 * ticket said "we have it"; the receipt says what became of it. Reading them
 * is the difference between "sent" and "arrived". */
async function collectReceipts(
  supabase: ReturnType<typeof createClient>,
): Promise<{ checked: number; delivered: number; failed: number }> {
  const { data, error } = await supabase.rpc('push_tickets_awaiting_receipt', {
    p_limit: RECEIPT_BATCH,
  });
  if (error) return { checked: 0, delivered: 0, failed: 0 };
  const ids = ((data ?? []) as { expo_ticket_id: string }[]).map((r) => r.expo_ticket_id);
  if (ids.length === 0) return { checked: 0, delivered: 0, failed: 0 };

  let payload: Record<string, Receipt> | null = null;
  try {
    const res = await fetch(EXPO_RECEIPT_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ ids }),
    });
    if (res.ok) payload = (await res.json())?.data ?? null;
  } catch {
    // Leave them unchecked; the next run asks again. A receipt we could not
    // fetch must never be recorded as a delivery.
    return { checked: 0, delivered: 0, failed: 0 };
  }
  if (!payload) return { checked: 0, delivered: 0, failed: 0 };

  let delivered = 0;
  let failed = 0;
  for (const [ticketId, receipt] of Object.entries(payload)) {
    const detail = receipt.details?.error ?? receipt.message ?? null;
    await supabase.rpc('record_push_receipt', {
      p_expo_ticket_id: ticketId,
      p_status: receipt.status,
      p_error: receipt.status === 'ok' ? null : detail,
    });
    if (receipt.status === 'ok') delivered += 1;
    else failed += 1;
  }
  return { checked: Object.keys(payload).length, delivered, failed };
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

  // Every run does both jobs: hand over what is waiting, and collect the
  // receipts for what was handed over a few minutes ago.
  const receipts = await collectReceipts(supabase);

  const { data, error } = await supabase.rpc('notifications_to_push', { p_limit: 200 });
  if (error) return Response.json({ error: error.message }, { status: 500 });
  const pending = (data ?? []) as Pending[];
  if (pending.length === 0) {
    return Response.json({ messages: 0, sent: 0, failed: 0, tokensRetired: 0, receipts });
  }

  const sentIds = new Set<string>();
  const failed: { id: string; error: string }[] = [];
  const deadTokens: { token: string; reason: string }[] = [];
  // named apart from Expo's own `tickets` inside the loop below
  const accepted: { notification_id: string; token: string; expo_ticket_id: string }[] = [];

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
        if (ticket.id) {
          accepted.push({
            notification_id: n.notification_id,
            token: n.token,
            expo_ticket_id: ticket.id,
          });
        }
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
  if (accepted.length > 0) {
    await supabase.rpc('record_push_tickets', { p_tickets: accepted });
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
    receipts,
  });
});
