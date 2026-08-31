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
  const [immMissing, setImmMissing] = useState(0);
  const [calOverdue, setCalOverdue] = useState(0);
  const [openHazards, setOpenHazards] = useState(0);
  const [menuGap, setMenuGap] = useState<string | null>(null);
  const [staleOffers, setStaleOffers] = useState(0);
  const [outdoorShort, setOutdoorShort] = useState<string[]>([]);
  const [unreached, setUnreached] = useState(0);
  const [noDevice, setNoDevice] = useState<string[]>([]);
  const [stuckPush, setStuckPush] = useState(0);
  const [neverArrived, setNeverArrived] = useState<{ recipient_name: string; title: string; why: string | null }[]>([]);
  const [phDue, setPhDue] = useState(0);
  const [policyGaps, setPolicyGaps] = useState<{ people: number; unpublished: number }>({ people: 0, unpublished: 0 });
  const [handbook, setHandbook] = useState<{ issued: boolean; missing: number; outstanding: number }>({
    issued: true,
    missing: 0,
    outstanding: 0,
  });

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

    // s. 42: the menu must cover the current AND the following week
    (async () => {
      const monday = (weeksAhead: number) => {
        const d = new Date();
        const u = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        u.setUTCDate(u.getUTCDate() - ((u.getUTCDay() || 7) - 1) + weeksAhead * 7);
        return u.toISOString().slice(0, 10);
      };
      const { data } = await sb
        .from('menu_week')
        .select('week_start, status')
        .eq('centre_id', centre.id)
        .eq('status', 'posted')
        .in('week_start', [monday(0), monday(1)]);
      const postedWeeks = new Set((data ?? []).map((w) => w.week_start));
      const missing = [monday(0), monday(1)].filter((m) => !postedWeeks.has(m));
      setMenuGap(
        missing.length === 2
          ? 'no menu is posted for this week or next'
          : missing.length === 1
            ? (missing[0] === monday(0) ? "this week's menu is not posted" : "next week's menu is not posted")
            : null,
      );
    })();

    sb.from('compliance_task')
      .select('id', { count: 'exact', head: true })
      .eq('centre_id', centre.id)
      .eq('active', true)
      .lt('next_due_on', today)
      .then(({ count }) => setCalOverdue(count ?? 0));
    sb.from('compliance_issue')
      .select('id', { count: 'exact', head: true })
      .eq('centre_id', centre.id)
      .is('resolved_at', null)
      .then(({ count }) => setOpenHazards(count ?? 0));

    (async () => {
      const [{ data: activeKids }, { data: immRows }] = await Promise.all([
        sb.from('child').select('id').eq('centre_id', centre.id).is('discharge_date', null),
        sb.from('current_immunisation').select('child_id').eq('centre_id', centre.id),
      ]);
      const covered = new Set((immRows ?? []).map((r) => r.child_id));
      setImmMissing((activeKids ?? []).filter((k) => !covered.has(k.id)).length);
    })();

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

    // A Now alert with no phone to land on, and one the transport could not
    // get out after five tries. Neither is a compliance duty; both are the
    // difference between an alert existing and an alert arriving.
    sb.from('undeliverable_now_alerts')
      .select('recipient_name')
      .eq('centre_id', centre.id)
      .then(({ data }) =>
        setNoDevice([...new Set(((data as { recipient_name: string }[]) ?? []).map((r) => r.recipient_name))]),
      );
    sb.from('stuck_push_alerts')
      .select('id', { count: 'exact', head: true })
      .eq('centre_id', centre.id)
      .then(({ count }) => setStuckPush(count ?? 0));
    // Expo accepted it and then told us it never landed
    sb.from('push_never_arrived')
      .select('recipient_name, title, why')
      .eq('centre_id', centre.id)
      .limit(5)
      .then(({ data }) => setNeverArrived((data as never) ?? []));

    // s. 36: a child sent home whose family we have not actually reached yet
    sb.from('health_exclusion')
      .select('id', { count: 'exact', head: true })
      .eq('centre_id', centre.id)
      .is('returned_at', null)
      .is('parent_reached_at', null)
      .then(({ count }) => setUnreached(count ?? 0));

    // s. 46: who has not read the program statement and the prohibited
    // practices — the question a program advisor actually asks
    sb.rpc('policy_attestation_gaps', { p_centre: centre.id }).then(({ data }) => {
      const rows = (data as { person_id: string; state: string }[]) ?? [];
      setPolicyGaps({
        people: new Set(rows.filter((r) => r.state === 'never_read' || r.state === 'due_again').map((r) => r.person_id)).size,
        unpublished: new Set(rows.filter((r) => r.state === 'not_published').map((r) => (r as unknown as { policy_key: string }).policy_key)).size,
      });
    });

    // s. 36: a public health order still owed to the program advisor
    sb.from('public_health_notification')
      .select('id', { count: 'exact', head: true })
      .eq('centre_id', centre.id)
      .is('closed_at', null)
      .is('advisor_forwarded_at', null)
      .not('advisor_due_on', 'is', null)
      .then(({ count }) => setPhDue(count ?? 0));

    // s. 47: a room short of its two hours with no reason recorded. Only worth
    // raising once the day is winding down — before that it is simply not done yet.
    (async () => {
      const [{ data: roomRows }, { data: dayRows }, { data: shortRows }] = await Promise.all([
        sb.from('room').select('id, name').eq('centre_id', centre.id),
        sb.from('outdoor_day').select('room_id, minutes').eq('centre_id', centre.id).eq('outdoor_date', today),
        sb.from('outdoor_shortfall').select('room_id').eq('centre_id', centre.id).eq('outdoor_date', today),
      ]);
      const excused = new Set((shortRows ?? []).map((s) => s.room_id));
      const minutes = new Map((dayRows ?? []).map((d) => [d.room_id, d.minutes as number]));
      setOutdoorShort(
        (roomRows ?? [])
          .filter((r) => (minutes.get(r.id) ?? 0) < 120 && !excused.has(r.id))
          .map((r) => r.name),
      );
    })();

    // s. 75.1: a place offered and never answered holds up the family behind
    sb.from('waitlist_entry')
      .select('id', { count: 'exact', head: true })
      .eq('centre_id', centre.id)
      .eq('status', 'offered')
      .lt('respond_by', today)
      .then(({ count }) => setStaleOffers(count ?? 0));

    (async () => {
      const [{ count: issued }, { data: missingRows }, { count: outstanding }] = await Promise.all([
        sb.from('handbook_version').select('id', { count: 'exact', head: true }).eq('centre_id', centre.id),
        sb.rpc('handbook_missing_sections', { p_centre: centre.id }),
        sb.from('handbook_outstanding').select('person_id', { count: 'exact', head: true }).eq('centre_id', centre.id),
      ]);
      setHandbook({
        issued: (issued ?? 0) > 0,
        missing: ((missingRows as { key: string }[]) ?? []).length,
        outstanding: outstanding ?? 0,
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
        {openHazards > 0 ? (
          <p>
            <span className="pill now">Now</span> {openHazards} premises hazard{openHazards === 1 ? '' : 's'} on the
            repair log — restricted until fixed — <Link href="/compliance">repair log</Link>
          </p>
        ) : null}
        {calOverdue > 0 ? (
          <p>
            <span className="pill due">Due</span> {calOverdue} compliance task{calOverdue === 1 ? '' : 's'} overdue
            (drills, tests, inspections) — <Link href="/compliance">compliance calendar</Link>
          </p>
        ) : null}
        {menuGap ? (
          <p>
            <span className="pill due">Due</span> Menus (s. 42): {menuGap} — <Link href="/menus">plan and post</Link>
          </p>
        ) : null}
        {noDevice.length > 0 ? (
          <p>
            <span className="pill due">Due</span> An urgent alert is waiting in the app for{' '}
            {noDevice.slice(0, 3).join(', ')}
            {noDevice.length > 3 ? ` and ${noDevice.length - 3} others` : ''}, who {noDevice.length === 1 ? 'has' : 'have'}{' '}
            no phone signed in — so it will not ring. Call them.
          </p>
        ) : null}
        {neverArrived.length > 0 ? (
          <p>
            <span className="pill now">Now</span>{' '}
            {neverArrived.length === 1
              ? `"${neverArrived[0]!.title}" was sent to ${neverArrived[0]!.recipient_name}'s phone and never arrived`
              : `${neverArrived.length} alerts were sent and never arrived`}
            {neverArrived[0]?.why ? ` (${neverArrived[0].why})` : ''}.{' '}
            {neverArrived.length === 1 ? 'It is' : 'They are'} still in the app — but nobody has been
            alerted. Call them.
          </p>
        ) : null}
        {stuckPush > 0 ? (
          <p>
            <span className="pill now">Now</span> {stuckPush} alert{stuckPush === 1 ? '' : 's'} could not
            be delivered to a phone after five tries. {stuckPush === 1 ? 'It is' : 'They are'} still in
            the family&apos;s app — but do not assume anyone saw {stuckPush === 1 ? 'it' : 'them'}.
          </p>
        ) : null}
        {unreached > 0 ? (
          <p>
            <span className="pill now">Now</span> {unreached} child
            {unreached === 1 ? '' : 'ren'} sent home unwell whose family has not been reached (s. 36) —{' '}
            <Link href="/illness">keep trying, and record the attempts</Link>
          </p>
        ) : null}
        {policyGaps.unpublished > 0 ? (
          <p>
            <span className="pill now">Now</span> {policyGaps.unpublished}{' '}
            {policyGaps.unpublished === 1 ? 'policy the centre must hold has' : 'policies the centre must hold have'}{' '}
            not been written — <Link href="/policies">policies</Link>
          </p>
        ) : null}
        {policyGaps.people > 0 ? (
          <p>
            <span className="pill due">Due</span> {policyGaps.people}{' '}
            {policyGaps.people === 1 ? 'person has' : 'people have'} not read a policy that applies to
            them (s. 46) — <Link href="/policies">who has not read what</Link>
          </p>
        ) : null}
        {phDue > 0 ? (
          <p>
            <span className="pill due">Due</span> {phDue} public health order
            {phDue === 1 ? '' : 's'} still to reach the program advisor (s. 36) —{' '}
            <Link href="/illness">illness &amp; exclusions</Link>
          </p>
        ) : null}
        {outdoorShort.length > 0 ? (
          <p>
            <span className="pill due">Due</span> Outdoor play (s. 47) is under two hours today in{' '}
            {outdoorShort.join(', ')} — record the time outside, or why the day was short —{' '}
            <Link href="/outdoor">outdoor play</Link>
          </p>
        ) : null}
        {staleOffers > 0 ? (
          <p>
            <span className="pill due">Due</span> {staleOffers} waiting-list{' '}
            {staleOffers === 1 ? 'offer has' : 'offers have'} passed the date the family was asked to
            answer by — the family behind them is waiting — <Link href="/waitlist">waiting list</Link>
          </p>
        ) : null}
        {!handbook.issued ? (
          <p>
            <span className="pill due">Due</span> No parent handbook has been issued (s. 45)
            {handbook.missing > 0 ? ` — ${handbook.missing} section${handbook.missing === 1 ? '' : 's'} still to write` : ''} —{' '}
            <Link href="/handbook">write and issue it</Link>
          </p>
        ) : handbook.outstanding > 0 ? (
          <p>
            <span className="pill due">Due</span> {handbook.outstanding} parent
            {handbook.outstanding === 1 ? ' has' : 's have'} not acknowledged the current handbook (s. 45) —{' '}
            <Link href="/handbook">who has it</Link>
          </p>
        ) : null}
        {immMissing > 0 ? (
          <p>
            <span className="pill due">Due</span> {immMissing} child{immMissing === 1 ? '' : 'ren'} with no
            immunisation record or exemption on file (s. 35) — <Link href="/children">children&apos;s records</Link>
          </p>
        ) : null}
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
