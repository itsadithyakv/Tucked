'use client';

/** s. 36: a child who becomes unwell is separated, the parent is contacted,
 * and the child goes home — all of it recorded, including the attempts that
 * went unanswered. Exclusion and return follow the centre's own illness
 * policy, developed with the public health unit, so the return criteria on
 * every exclusion are copied from that policy rather than typed freehand.
 * An excluded child cannot be signed in until somebody signs off that the
 * criteria were met; that refusal lives in the database, not in this page. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

interface Policy {
  id: string;
  symptom: string;
  label: string;
  exclusion_note: string;
  return_criteria: string;
  min_exclusion_hours: number;
  notify_public_health: boolean;
  active: boolean;
}

interface Exclusion {
  id: string;
  child_id: string;
  full_name: string;
  symptom: string;
  detail: string | null;
  onset_at: string;
  separation_place: string | null;
  parent_reached_at: string | null;
  practitioner_seen: string | null;
  practitioner_advice: string | null;
  exclusion_reason: string;
  return_criteria: string;
  may_return_at: string | null;
  returned_at: string | null;
  clearance_note: string | null;
  early_return_reason: string | null;
  is_open: boolean;
  criteria_date_passed: boolean;
  contact_attempts: number;
}

interface Contact {
  id: string;
  exclusion_id: string;
  attempted_at: string;
  method: string;
  outcome: string;
  note: string | null;
  person: { full_name: string } | null;
  named: string | null;
}

interface PhNotification {
  id: string;
  kind: string;
  disease: string | null;
  summary: string;
  unit_name: string;
  notified_at: string | null;
  reference: string | null;
  order_received_at: string | null;
  order_summary: string | null;
  advisor_due_on: string | null;
  advisor_forwarded_at: string | null;
  closed_at: string | null;
}

const OUTCOME: Record<string, string> = {
  reached: 'Reached',
  no_answer: 'No answer',
  left_message: 'Left a message',
  unavailable: 'Unavailable',
};

const KIND: Record<string, string> = {
  communicable_disease: 'Communicable disease',
  outbreak: 'Outbreak',
  order_received: 'Order or direction received',
  enforcement_action: 'Enforcement action',
};

function when(iso: string): string {
  return new Date(iso).toLocaleString('en-CA', {
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
}

export default function IllnessPage() {
  const { centre, personId } = useConsole();
  const [policy, setPolicy] = useState<Policy[]>([]);
  const [exclusions, setExclusions] = useState<Exclusion[]>([]);
  const [contacts, setContacts] = useState<Contact[]>([]);
  const [notifications, setNotifications] = useState<PhNotification[]>([]);
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);
  const [clearing, setClearing] = useState<Record<string, { note: string; early: string }>>({});

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.from('illness_policy')
      .select('id, symptom, label, exclusion_note, return_criteria, min_exclusion_hours, notify_public_health, active')
      .eq('centre_id', centre.id)
      .order('label')
      .then(({ data }) => setPolicy((data as Policy[]) ?? []));
    sb.from('exclusion_status')
      .select('*')
      .eq('centre_id', centre.id)
      .order('onset_at', { ascending: false })
      .limit(40)
      .then(({ data }) => setExclusions((data as Exclusion[]) ?? []));
    sb.from('health_exclusion_contact')
      .select('id, exclusion_id, attempted_at, method, outcome, note, named, person:person_id(full_name)')
      .eq('centre_id', centre.id)
      .order('attempted_at')
      .then(({ data }) => setContacts((data as never) ?? []));
    sb.from('public_health_notification')
      .select('*')
      .eq('centre_id', centre.id)
      .order('created_at', { ascending: false })
      .then(({ data }) => setNotifications((data as PhNotification[]) ?? []));
  }, [centre.id]);

  useEffect(load, [load]);

  const open = exclusions.filter((e) => e.is_open);
  const past = exclusions.filter((e) => !e.is_open);
  const today = new Date().toISOString().slice(0, 10);

  async function clear(e: Exclusion) {
    const draft = clearing[e.id] ?? { note: '', early: '' };
    setNotice(null);
    const { error } = await getSupabase().rpc('clear_for_return', {
      p_exclusion: e.id,
      p_note: draft.note,
      p_early_reason: draft.early || null,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    if (!error) setClearing((c) => ({ ...c, [e.id]: { note: '', early: '' } }));
    setNotice(error ? error.message : `${e.full_name} may come back.`);
    load();
  }

  async function forwardOrder(id: string, reference: string) {
    setNotice(null);
    const { error } = await getSupabase().rpc('forward_to_program_advisor', {
      p_notification: id,
      p_reference: reference,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    setNotice(error ? error.message : 'Recorded — the order has gone to the program advisor.');
    load();
  }

  return (
    <>
      <h1>Illness &amp; exclusions</h1>
      {notice ? <section className="card"><p>{notice}</p></section> : null}

      <section className="card">
        <h2>Children out unwell</h2>
        <p className="muted">
          An excluded child cannot be signed in — the database refuses it, and the refusal names what
          has to be true first. Clearing a child is a judgment somebody signs; coming back before the
          policy&apos;s date is allowed and asks for a written reason.
        </p>
        <label className="inline">
          Staff PIN (for the actions below)
          <input
            type="password"
            inputMode="numeric"
            value={pin}
            onChange={(e) => setPin(e.target.value)}
            maxLength={6}
            autoComplete="off"
          />
        </label>
        {open.length === 0 ? <p className="muted">Nobody is out unwell.</p> : null}
        {open.map((e) => {
          const draft = clearing[e.id] ?? { note: '', early: '' };
          const attempts = contacts.filter((c) => c.exclusion_id === e.id);
          return (
            <div key={e.id} style={{ borderTop: '1px solid var(--line)', paddingTop: 10, marginTop: 10 }}>
              <h3 style={{ marginBottom: 2 }}>
                {e.full_name}{' '}
                {e.criteria_date_passed || !e.may_return_at ? (
                  <span className="pill ok">May be ready</span>
                ) : (
                  <span className="pill due">Not before {when(e.may_return_at)}</span>
                )}
              </h3>
              <p className="caption">
                Unwell since {when(e.onset_at)} · separated to {e.separation_place ?? '—'}
              </p>
              <p className="wrap">{e.exclusion_reason}</p>
              {e.detail ? <p className="muted wrap">{e.detail}</p> : null}
              <p className="wrap">
                <strong>Before coming back:</strong> {e.return_criteria}
              </p>
              {e.practitioner_seen ? (
                <p className="muted wrap">
                  Seen by {e.practitioner_seen}
                  {e.practitioner_advice ? ` — ${e.practitioner_advice}` : ''}
                </p>
              ) : null}
              <p className="caption">
                {e.parent_reached_at
                  ? `Family reached ${when(e.parent_reached_at)}`
                  : 'Family NOT yet reached'}{' '}
                · {e.contact_attempts} attempt{e.contact_attempts === 1 ? '' : 's'}
              </p>
              {attempts.map((a) => (
                <p key={a.id} className="caption" style={{ margin: '2px 0' }}>
                  {when(a.attempted_at)} · {a.method.replace('_', ' ')} ·{' '}
                  {a.person?.full_name ?? a.named} — {OUTCOME[a.outcome]}
                  {a.note ? ` (${a.note})` : ''}
                </p>
              ))}
              <div style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap', marginTop: 6 }}>
                <label style={{ flex: 1, minWidth: 260 }}>
                  How the criteria were met
                  <input
                    value={draft.note}
                    onChange={(ev) =>
                      setClearing((c) => ({ ...c, [e.id]: { ...draft, note: ev.target.value } }))
                    }
                    placeholder="No further episodes; eating and drinking normally"
                  />
                </label>
                {!e.criteria_date_passed && e.may_return_at ? (
                  <label style={{ flex: 1, minWidth: 240 }}>
                    Why they may come back early
                    <input
                      value={draft.early}
                      onChange={(ev) =>
                        setClearing((c) => ({ ...c, [e.id]: { ...draft, early: ev.target.value } }))
                      }
                      placeholder="Physician's note: not infectious"
                    />
                  </label>
                ) : null}
                <button type="button" disabled={!draft.note.trim()} onClick={() => void clear(e)}>
                  Clear to return
                </button>
              </div>
            </div>
          );
        })}
      </section>

      <section className="card">
        <h2>Public health (s. 36)</h2>
        <p className="muted">
          An order or direction from the public health unit reaches the program advisor within two
          business days; an enforcement action within one. The clock below is computed from the day it
          arrived, skipping weekends and statutory holidays. Tucked never sends it for you.
        </p>
        {notifications.length === 0 ? <p className="muted">Nothing on file.</p> : null}
        {notifications.map((n) => {
          const overdue = n.advisor_due_on !== null && !n.advisor_forwarded_at && n.advisor_due_on < today;
          return (
            <div key={n.id} style={{ borderTop: '1px solid var(--line)', paddingTop: 10, marginTop: 10 }}>
              <h3 style={{ marginBottom: 2 }}>
                {KIND[n.kind] ?? n.kind}
                {n.disease ? ` — ${n.disease}` : ''}{' '}
                {n.closed_at ? (
                  <span className="pill ok">Closed</span>
                ) : overdue ? (
                  <span className="pill now">Advisor OVERDUE</span>
                ) : n.advisor_due_on && !n.advisor_forwarded_at ? (
                  <span className="pill due">To the advisor by {fmtDate(n.advisor_due_on)}</span>
                ) : (
                  <span className="pill ok">Open</span>
                )}
              </h3>
              <p className="caption">
                {n.unit_name}
                {n.reference ? ` · ${n.reference}` : ''}
                {n.notified_at ? ` · notified ${when(n.notified_at)}` : ''}
                {n.order_received_at ? ` · order received ${when(n.order_received_at)}` : ''}
              </p>
              <p className="wrap">{n.summary}</p>
              {n.order_summary ? <p className="muted wrap">{n.order_summary}</p> : null}
              {n.advisor_forwarded_at ? (
                <p className="caption">Sent to the program advisor {when(n.advisor_forwarded_at)}.</p>
              ) : n.advisor_due_on ? (
                <ForwardForm onSubmit={(ref) => void forwardOrder(n.id, ref)} />
              ) : null}
            </div>
          );
        })}
      </section>

      <section className="card">
        <h2>The centre&apos;s illness policy</h2>
        <p className="muted">
          Developed with the local public health unit. Every exclusion copies its return criteria from
          here, so two educators on two days give the same family the same answer.
        </p>
        <div style={{ overflowX: 'auto' }}>
          <table>
            <thead>
              <tr>
                <th>Symptom</th>
                <th>When a child is excluded</th>
                <th>Before they come back</th>
                <th>Earliest</th>
              </tr>
            </thead>
            <tbody>
              {policy.map((p) => (
                <tr key={p.id}>
                  <td className="wrap">
                    {p.label}
                    {p.notify_public_health ? <> <span className="pill due">Tell public health</span></> : null}
                  </td>
                  <td className="wrap muted">{p.exclusion_note}</td>
                  <td className="wrap">{p.return_criteria}</td>
                  <td className="caption">
                    {p.min_exclusion_hours > 0 ? `${p.min_exclusion_hours} h` : 'judgment'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {past.length > 0 ? (
        <section className="card">
          <h2>Earlier exclusions</h2>
          <table>
            <thead>
              <tr>
                <th>Child</th>
                <th>Unwell</th>
                <th>Back</th>
                <th>How the criteria were met</th>
              </tr>
            </thead>
            <tbody>
              {past.map((e) => (
                <tr key={e.id}>
                  <td>{e.full_name}</td>
                  <td className="caption">{when(e.onset_at)}</td>
                  <td className="caption">{e.returned_at ? when(e.returned_at) : ''}</td>
                  <td className="wrap muted">
                    {e.clearance_note}
                    {e.early_return_reason ? (
                      <div className="caption">Early return — {e.early_return_reason}</div>
                    ) : null}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      ) : null}
    </>
  );
}

function ForwardForm({ onSubmit }: { onSubmit: (reference: string) => void }) {
  const [reference, setReference] = useState('');
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap', marginTop: 6 }}>
      <label style={{ flex: 1, minWidth: 280 }}>
        How it was sent to the program advisor
        <input
          value={reference}
          onChange={(e) => setReference(e.target.value)}
          placeholder="Emailed to the Toronto licensing office, acknowledged 30 Aug"
        />
      </label>
      <button type="button" disabled={!reference.trim()} onClick={() => onSubmit(reference)}>
        Record
      </button>
    </div>
  );
}
