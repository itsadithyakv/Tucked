/**
 * notify — pushes pending notification rows through Expo's push service.
 *
 * Now channel: always pushed, high priority, sound on (Android channel 'now',
 * iOS time-sensitive). Later channel: ONLY the daily story is pushed — the one
 * scheduled push per child per day; everything else waits quietly in-app.
 *
 * Invoke on a schedule (pg_cron -> net.http_post in cloud) or manually in dev:
 *   supabase functions serve notify
 *   curl -X POST http://127.0.0.1:54321/functions/v1/notify
 *
 * Rows without a registered device still get pushed_at set: in-app delivery
 * is the fallback and the row itself is the record.
 */

import { createClient } from 'npm:@supabase/supabase-js@2';

const EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send';

Deno.serve(async () => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: pending, error } = await supabase
    .from('notification')
    .select('id, recipient_person_id, channel, event_type, title, body')
    .is('pushed_at', null)
    .limit(200);
  if (error) return Response.json({ error: error.message }, { status: 500 });

  const toPush = (pending ?? []).filter(
    (n) => n.channel === 'now' || (n.channel === 'later' && n.event_type === 'story'),
  );
  const recipients = [...new Set(toPush.map((n) => n.recipient_person_id))];
  const { data: tokens } = recipients.length
    ? await supabase.from('device_push_token').select('person_id, token').in('person_id', recipients)
    : { data: [] };
  const tokensByPerson = new Map<string, string[]>();
  for (const t of tokens ?? []) {
    tokensByPerson.set(t.person_id, [...(tokensByPerson.get(t.person_id) ?? []), t.token]);
  }

  const messages = toPush.flatMap((n) =>
    (tokensByPerson.get(n.recipient_person_id) ?? []).map((to) => ({
      to,
      title: n.title,
      body: n.body,
      sound: n.channel === 'now' ? 'default' : undefined,
      priority: n.channel === 'now' ? 'high' : 'default',
      channelId: n.channel, // Android channels 'now' / 'later'
      interruptionLevel: n.channel === 'now' ? 'timeSensitive' : 'active',
      data: { eventType: n.event_type, notificationId: n.id },
    })),
  );

  let sent = 0;
  for (let i = 0; i < messages.length; i += 100) {
    const chunk = messages.slice(i, i + 100);
    const res = await fetch(EXPO_PUSH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(chunk),
    });
    if (res.ok) sent += chunk.length;
  }

  const ids = toPush.map((n) => n.id);
  if (ids.length) {
    await supabase.from('notification').update({ pushed_at: new Date().toISOString() }).in('id', ids);
  }

  return Response.json({ pending: pending?.length ?? 0, pushed: ids.length, deviceMessages: sent });
});
