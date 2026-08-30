'use client';

/** Exceptions home (build prompt §3.1): today's exceptions only — unclosed
 * daily record, unacknowledged Now items, expiring credentials, safe-arrival
 * follow-ups, live per-room presence. */

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, fmtTime, useConsole } from '@/lib/console';
import { Sparkles } from '@/ui/sparkles';

interface RoomPresence {
  id: string;
  name: string;
  present: number;
  staff: number;
}

interface PlanInfo {
  status: string;
  pilot_ends_on: string | null;
  plan: { name: string; description: string | null } | null;
}

export default function ExceptionsHome() {
  const { centre } = useConsole();
  const [unclosed, setUnclosed] = useState<number | null>(null);
  const [unacked, setUnacked] = useState<{ id: string; title: string; created_at: string }[]>([]);
  const [expiring, setExpiring] = useState<{ id: string; credential_type: string; expires_on: string; person: { full_name: string } | null }[]>([]);
  const [rooms, setRooms] = useState<RoomPresence[]>([]);
  const [planInfo, setPlanInfo] = useState<PlanInfo | null>(null);

  useEffect(() => {
    const sb = getSupabase();
    const today = new Date().toISOString().slice(0, 10);

    sb.from('daily_written_record')
      .select('id', { count: 'exact', head: true })
      .eq('centre_id', centre.id)
      .is('closed_at', null)
      .then(({ count }) => setUnclosed(count ?? 0));

    sb.from('notification')
      .select('id, title, created_at')
      .eq('centre_id', centre.id)
      .eq('channel', 'now')
      .is('acknowledged_at', null)
      .order('created_at', { ascending: false })
      .limit(10)
      .then(({ data }) => setUnacked(data ?? []));

    sb.from('centre_subscription')
      .select('status, pilot_ends_on, plan:plan_code(name, description)')
      .eq('centre_id', centre.id)
      .maybeSingle()
      .then(({ data }) => setPlanInfo((data as never as PlanInfo) ?? null));

    sb.from('credential_status')
      .select('id, credential_type, expires_on, person:person_id(full_name)')
      .eq('centre_id', centre.id)
      .in('expiry_state', ['expired', 'expiring_soon'])
      .order('expires_on')
      .then(({ data }) => setExpiring((data as never) ?? []));

    (async () => {
      const [{ data: roomRows }, { data: events }, { data: shifts }] = await Promise.all([
        sb.from('room').select('id, name').eq('centre_id', centre.id).order('name'),
        sb
          .from('attendance_event')
          .select('child_id, room_id, event_type')
          .eq('centre_id', centre.id)
          .eq('attendance_date', today)
          .order('actual_time'),
        sb.from('staff_shift').select('room_id, counted_in_ratio, out_at').eq('centre_id', centre.id).eq('shift_date', today),
      ]);
      const present = new Map<string, Set<string>>();
      for (const e of events ?? []) {
        if (e.event_type === 'arrive' || e.event_type === 'room_transfer') {
          for (const set of present.values()) set.delete(e.child_id);
          present.set(e.room_id, (present.get(e.room_id) ?? new Set()).add(e.child_id));
        } else if (e.event_type === 'depart') {
          present.get(e.room_id)?.delete(e.child_id);
        }
      }
      setRooms(
        (roomRows ?? []).map((r) => ({
          id: r.id,
          name: r.name,
          present: present.get(r.id)?.size ?? 0,
          staff: (shifts ?? []).filter((s) => s.room_id === r.id && s.counted_in_ratio && !s.out_at).length,
        })),
      );
    })();
  }, [centre.id]);

  return (
    <>
      <h1>Today</h1>
      <section className="cards-row">
        {rooms.map((r, i) => (
          <div className={`card tile ${['tile-mist', 'tile-mint', 'tile-sand'][i % 3]}`} key={r.id}>
            <h2>{r.name}</h2>
            <p className="stat">{r.present}</p>
            <p className="muted">children present · {r.staff} staff in ratio</p>
          </div>
        ))}
      </section>

      <section className="card">
        <h2>Needs attention</h2>
        {unclosed !== null && unclosed > 0 ? (
          <p>
            <span className="pill due">Due</span> {unclosed} daily written record{unclosed === 1 ? '' : 's'} not yet
            closed — <Link href="/daily-record">review and close</Link>
          </p>
        ) : (
          <p className="muted">
            <Sparkles>
              <span className="pill ok">Done</span>
            </Sparkles>{' '}
            Every daily written record is closed.
          </p>
        )}
        {expiring.length > 0 ? (
          expiring.map((c) => (
            <p key={c.id}>
              <span className="pill due">Due</span> {c.person?.full_name}: {c.credential_type.replace(/_/g, ' ')}{' '}
              expires {c.expires_on} — <Link href="/staff">staff files</Link>
            </p>
          ))
        ) : (
          <p className="muted">
            <Sparkles>
              <span className="pill ok">Done</span>
            </Sparkles>{' '}
            No credentials expiring in the next 60 days.
          </p>
        )}
      </section>

      <section className="card">
        <h2>Unacknowledged Now alerts</h2>
        {unacked.length === 0 ? (
          <p className="muted">Every urgent alert has been acknowledged by a family member.</p>
        ) : (
          unacked.map((n) => (
            <p key={n.id}>
              <span className="pill now">Now</span> {n.title}{' '}
              <span className="caption">sent {fmtTime(n.created_at, centre.timezone)}</span>
            </p>
          ))
        )}
      </section>

      {planInfo ? (
        <section className="card">
          <h2>Plan &amp; billing</h2>
          <p>
            <span className={`pill ${planInfo.status === 'past_due' ? 'due' : planInfo.status === 'cancelled' ? 'now' : 'ok'}`}>
              {planInfo.status.replace('_', ' ')}
            </span>{' '}
            {planInfo.plan?.name ?? 'Plan'}
            {planInfo.pilot_ends_on ? ` — pilot until ${fmtDate(planInfo.pilot_ends_on)}` : ''}
          </p>
          {planInfo.plan?.description ? <p className="muted">{planInfo.plan.description}</p> : null}
          <p className="caption">
            Whatever happens with billing, your regulated records are never hidden or locked — that is enforced
            in the database, not policy.
          </p>
        </section>
      ) : null}
    </>
  );
}
