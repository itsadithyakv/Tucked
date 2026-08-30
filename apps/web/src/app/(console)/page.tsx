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

interface BreakGlass {
  id: string;
  person_id: string;
  reason: string;
  expires_at: string;
  closed_at: string | null;
  person: { full_name: string } | null;
}

export default function ExceptionsHome() {
  const { centre } = useConsole();
  const [unclosed, setUnclosed] = useState<number | null>(null);
  const [unacked, setUnacked] = useState<{ id: string; title: string; created_at: string }[]>([]);
  const [expiring, setExpiring] = useState<{ id: string; credential_type: string; expires_on: string; person: { full_name: string } | null }[]>([]);
  const [rooms, setRooms] = useState<RoomPresence[]>([]);
  const [planInfo, setPlanInfo] = useState<PlanInfo | null>(null);
  const [openOccurrences, setOpenOccurrences] = useState<
    { id: string; category: string; ccls_deadline_at: string; ccls_filed_at: string | null }[]
  >([]);
  const [planFlags, setPlanFlags] = useState<{ drafts: number; reviewsOverdue: number; policyMissing: boolean }>({
    drafts: 0,
    reviewsOverdue: 0,
    policyMissing: false,
  });
  const [breakGlass, setBreakGlass] = useState<BreakGlass[]>([]);
  const [bgTick, setBgTick] = useState(0);

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

    sb.from('serious_occurrence')
      .select('id, category, ccls_deadline_at, ccls_filed_at')
      .eq('centre_id', centre.id)
      .neq('status', 'closed')
      .order('ccls_deadline_at')
      .then(({ data }) => setOpenOccurrences((data as never) ?? []));

    sb.from('break_glass_access')
      .select('id, person_id, reason, expires_at, closed_at, person:person_id(full_name)')
      .eq('centre_id', centre.id)
      .is('closed_at', null)
      .gt('expires_at', new Date().toISOString())
      .then(({ data }) => setBreakGlass((data as never) ?? []));

    (async () => {
      const [{ data: livePlans }, { data: centreRow }] = await Promise.all([
        sb.from('individualised_plan').select('status, review_due_on').eq('centre_id', centre.id).in('status', ['draft', 'active']),
        sb.from('centre').select('anaphylaxis_policy').eq('id', centre.id).maybeSingle(),
      ]);
      setPlanFlags({
        drafts: (livePlans ?? []).filter((p) => p.status === 'draft').length,
        reviewsOverdue: (livePlans ?? []).filter((p) => p.status === 'active' && p.review_due_on && p.review_due_on < today).length,
        policyMissing: !(centreRow?.anaphylaxis_policy ?? '').trim(),
      });
    })();

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
  }, [centre.id, bgTick]);

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

      <BreakGlassCard active={breakGlass} onChanged={() => setBgTick((n) => n + 1)} />

      <section className="card">
        <h2>Needs attention</h2>
        {breakGlass.map((bg) => (
          <p key={bg.id}>
            <span className="pill now">Now</span> Emergency read-only access open: {bg.person?.full_name} —{' '}
            “{bg.reason}” — expires {fmtTime(bg.expires_at, centre.timezone)} (s. 82(2), audited)
          </p>
        ))}
        {openOccurrences.map((o) => {
          const overdue = !o.ccls_filed_at && new Date(o.ccls_deadline_at).getTime() < Date.now();
          return (
            <p key={o.id}>
              <span className={`pill ${o.ccls_filed_at ? 'due' : 'now'}`}>{o.ccls_filed_at ? 'Open' : overdue ? 'OVERDUE' : 'Now'}</span>{' '}
              Serious occurrence ({o.category.replace(/_/g, ' ')}) —{' '}
              {o.ccls_filed_at
                ? 'filed in CCLS, posting or closure outstanding'
                : `CCLS deadline ${fmtTime(o.ccls_deadline_at, centre.timezone)}`}{' '}
              — <Link href="/serious-occurrences">work it</Link>
            </p>
          );
        })}
        {planFlags.policyMissing ? (
          <p>
            <span className="pill now">Now</span> No anaphylaxis policy on file (s. 39 requires one even with no
            allergic children) — <Link href="/plans">write it</Link>
          </p>
        ) : null}
        {planFlags.drafts > 0 ? (
          <p>
            <span className="pill due">Due</span> {planFlags.drafts} individualised plan{planFlags.drafts === 1 ? '' : 's'} awaiting
            parent agreement — <Link href="/plans">plans</Link>
          </p>
        ) : null}
        {planFlags.reviewsOverdue > 0 ? (
          <p>
            <span className="pill due">Due</span> {planFlags.reviewsOverdue} plan review{planFlags.reviewsOverdue === 1 ? '' : 's'} overdue
            (annual) — <Link href="/plans">plans</Link>
          </p>
        ) : null}
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

/** s. 82(2): non-supervisors can open a 24-hour READ-ONLY emergency access to
 * the inspection registers when a program advisor is on site and the
 * supervisor cannot be reached. Loud, audited, closable, never writable. */
function BreakGlassCard({ active, onChanged }: { active: BreakGlass[]; onChanged: () => void }) {
  const { centre, personId, roles } = useConsole();
  const [reason, setReason] = useState('');
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const isLeadership = roles.some((r) => ['supervisor', 'licensee_admin', 'designate'].includes(r));
  const mine = active.find((bg) => bg.person_id === personId);
  if (isLeadership && !mine) return null;

  async function call(fn: 'open_break_glass' | 'close_break_glass', args: Record<string, unknown>) {
    setNotice(null);
    const { error } = await getSupabase().rpc(fn, { ...args, p_recorder: personId, p_pin: pin });
    if (error) setNotice(error.message);
    else {
      setPin('');
      setReason('');
      onChanged();
    }
  }

  if (mine) {
    return (
      <section className="card">
        <h2>Emergency records access active</h2>
        <p>
          <span className="pill now">Read-only</span> You can read the inspection registers (audit trail, serious
          occurrences, staff files, retention clocks) until {fmtDate(mine.expires_at)}{' '}
          {new Date(mine.expires_at).toLocaleTimeString('en-CA', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: centre.timezone })}.
          Every supervisor has been alerted and everything is audited. Close it when the visit is over.
        </p>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
          <label className="inline">
            Staff PIN
            <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" />
          </label>
          <button type="button" className="quiet" onClick={() => void call('close_break_glass', { p_access: mine.id })}>
            Close emergency access
          </button>
        </div>
        {notice ? <p className="muted">{notice}</p> : null}
      </section>
    );
  }

  return (
    <section className="card">
      <h2>Emergency records access (s. 82(2))</h2>
      <p className="muted">
        A program advisor or public health official needs the records and no supervisor can be reached? Open
        read-only access to the inspection registers. It announces itself to every supervisor, lands in the
        audit trail, and expires after 24 hours.
      </p>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
        <label style={{ flex: 1, minWidth: 260 }}>
          Why (who needs the records, and why the supervisor cannot provide them)
          <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Program advisor on site; supervisor unreachable…" />
        </label>
        <label className="inline">
          Staff PIN
          <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" />
        </label>
        <button type="button" onClick={() => void call('open_break_glass', { p_centre: centre.id, p_reason: reason })}>
          Open emergency access
        </button>
      </div>
      {notice ? <p className="muted">{notice}</p> : null}
    </section>
  );
}
