'use client';

/** s. 75.1: the waiting list. Free to join — there is no field on this page or
 * in the schema that could hold a fee. Position is computed from the published
 * order (sibling, then subsidy referral, then the date the family joined), and
 * moving a family is a leadership act that always carries a reason and lands
 * on the permanent record. Each family gets a code that shows them their own
 * position and nothing about anybody else. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

interface Entry {
  id: string;
  child_name: string;
  child_date_of_birth: string;
  age_group_preset: string;
  desired_start_on: string;
  contact_name: string;
  contact_email: string | null;
  contact_phone: string | null;
  access_code: string;
  priority: string;
  priority_reason: string | null;
  status: string;
  joined_at: string;
  respond_by: string | null;
  list_position: number;
}

interface Closed {
  id: string;
  child_name: string;
  age_group_preset: string;
  status: string;
  closed_at: string | null;
  anonymised_at: string | null;
}

interface Event {
  id: string;
  entry_id: string;
  event_type: string;
  detail: string | null;
  created_at: string;
  person: { full_name: string } | null;
}

const GROUPS = [
  { key: 'infant', label: 'Infant' },
  { key: 'toddler', label: 'Toddler' },
  { key: 'preschool', label: 'Preschool' },
  { key: 'kindergarten', label: 'Kindergarten' },
  { key: 'primary_junior', label: 'Primary/junior' },
  { key: 'junior', label: 'Junior' },
  { key: 'family', label: 'Family age' },
];

const PRIORITY_LABEL: Record<string, string> = {
  sibling: 'Sibling',
  subsidy_referral: 'Subsidy referral',
  general: 'Date order',
};

/** The code is stored without separators; read it back in fours. */
function readableCode(code: string): string {
  return code.replace(/(.{4})(?=.)/g, '$1-');
}

export default function WaitlistPage() {
  const { centre, personId } = useConsole();
  const [open, setOpen] = useState<Entry[]>([]);
  const [closed, setClosed] = useState<Closed[]>([]);
  const [events, setEvents] = useState<Event[]>([]);
  const [showHistory, setShowHistory] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [pin, setPin] = useState('');

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.from('waitlist_position')
      .select(
        'id, child_name, child_date_of_birth, age_group_preset, desired_start_on, contact_name, contact_email, contact_phone, access_code, priority, priority_reason, status, joined_at, respond_by, list_position',
      )
      .eq('centre_id', centre.id)
      .order('age_group_preset')
      .order('list_position')
      .then(({ data }) => setOpen((data as Entry[]) ?? []));
    sb.from('waitlist_entry')
      .select('id, child_name, age_group_preset, status, closed_at, anonymised_at')
      .eq('centre_id', centre.id)
      .not('closed_at', 'is', null)
      .order('closed_at', { ascending: false })
      .limit(20)
      .then(({ data }) => setClosed((data as Closed[]) ?? []));
    sb.from('waitlist_event')
      .select('id, entry_id, event_type, detail, created_at, person:recorded_by(full_name)')
      .eq('centre_id', centre.id)
      .order('created_at', { ascending: false })
      .limit(200)
      .then(({ data }) => setEvents((data as never) ?? []));
  }, [centre.id]);

  useEffect(load, [load]);

  async function call(fn: string, args: Record<string, unknown>, ok: string) {
    setNotice(null);
    const { error } = await getSupabase().rpc(fn, { ...args, p_recorder: personId, p_pin: pin });
    setPin('');
    setNotice(error ? error.message : ok);
    load();
  }

  return (
    <>
      <h1>Waiting list</h1>
      {notice ? <section className="card"><p>{notice}</p></section> : null}

      <section className="card">
        <h2>How this list works (s. 75.1)</h2>
        <p className="muted">
          There is no fee or deposit to join — not as a matter of policy, but because there is nowhere
          in Tucked to record one. Places are offered in the order the centre publishes in the parent
          handbook: a sibling of an enrolled child, then a service-system-manager subsidy referral, then
          the date the family joined. Moving a family needs a reason, and the reason is kept.
        </p>
        <p className="muted">
          Every family is given a code. At <strong>/waiting-list</strong> the code shows them their own
          position and how many families are ahead — and nothing whatsoever about anyone else.
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
      </section>

      {GROUPS.filter((g) => open.some((e) => e.age_group_preset === g.key)).map((g) => {
        const rows = open.filter((e) => e.age_group_preset === g.key);
        return (
          <section className="card" key={g.key}>
            <h2>
              {g.label} <span className="pill ok">{rows.length} waiting</span>
            </h2>
            <div style={{ overflowX: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    <th>#</th>
                    <th>Child</th>
                    <th>Wants to start</th>
                    <th>Order</th>
                    <th>Joined</th>
                    <th>Contact</th>
                    <th>Their code</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((e) => (
                    <tr key={e.id}>
                      <td>
                        <strong>{e.list_position}</strong>
                      </td>
                      <td className="wrap">
                        {e.child_name}
                        {e.status === 'offered' ? (
                          <>
                            {' '}
                            <span className="pill due">
                              Offered · answer by {e.respond_by ? fmtDate(e.respond_by) : ''}
                            </span>
                          </>
                        ) : null}
                      </td>
                      <td>{fmtDate(e.desired_start_on)}</td>
                      <td className="wrap">
                        {PRIORITY_LABEL[e.priority]}
                        {e.priority_reason ? (
                          <div className="caption">{e.priority_reason}</div>
                        ) : null}
                      </td>
                      <td>{fmtDate(e.joined_at)}</td>
                      <td className="wrap caption">
                        {e.contact_name}
                        <div>{e.contact_email ?? e.contact_phone}</div>
                      </td>
                      <td className="caption">{readableCode(e.access_code)}</td>
                      <td>
                        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                          {e.status === 'waiting' ? (
                            <button
                              className="quiet"
                              onClick={() =>
                                void call(
                                  'offer_waitlist_place',
                                  {
                                    p_entry: e.id,
                                    p_respond_by: new Date(Date.now() + 7 * 864e5)
                                      .toISOString()
                                      .slice(0, 10),
                                  },
                                  `Place offered to ${e.child_name}.`,
                                )
                              }
                            >
                              Offer a place
                            </button>
                          ) : (
                            <>
                              <button
                                className="quiet"
                                onClick={() =>
                                  void call(
                                    'record_waitlist_response',
                                    { p_entry: e.id, p_response: 'accepted', p_note: null },
                                    `${e.child_name} accepted.`,
                                  )
                                }
                              >
                                Accepted
                              </button>
                              <button
                                className="quiet"
                                onClick={() =>
                                  void call(
                                    'record_waitlist_response',
                                    { p_entry: e.id, p_response: 'declined', p_note: null },
                                    `${e.child_name} declined.`,
                                  )
                                }
                              >
                                Declined
                              </button>
                            </>
                          )}
                          <button className="quiet" onClick={() => setShowHistory(showHistory === e.id ? null : e.id)}>
                            History
                          </button>
                        </div>
                        {showHistory === e.id ? (
                          <div style={{ marginTop: 6 }}>
                            {events
                              .filter((v) => v.entry_id === e.id)
                              .map((v) => (
                                <p key={v.id} className="caption" style={{ margin: '2px 0' }}>
                                  {fmtDate(v.created_at)} · {v.event_type.replace('_', ' ')}
                                  {v.detail ? ` — ${v.detail}` : ''}
                                  {v.person ? ` (${v.person.full_name})` : ''}
                                </p>
                              ))}
                            <PriorityForm
                              entry={e}
                              onSubmit={(priority, reason) =>
                                void call(
                                  'set_waitlist_priority',
                                  { p_entry: e.id, p_priority: priority, p_reason: reason },
                                  `${e.child_name} moved to ${PRIORITY_LABEL[priority]?.toLowerCase()}.`,
                                )
                              }
                            />
                          </div>
                        ) : null}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        );
      })}

      {open.length === 0 ? (
        <section className="card">
          <p className="muted">Nobody is waiting for a place right now.</p>
        </section>
      ) : null}

      <AddEnquiry
        centreId={centre.id}
        personId={personId}
        onDone={(msg) => {
          setNotice(msg);
          load();
        }}
      />

      {closed.length > 0 ? (
        <section className="card">
          <h2>Closed enquiries</h2>
          <p className="muted">
            Nothing is deleted, so the order families were admitted in stays auditable. Contact details
            are dropped twelve months after an enquiry closes — we have no reason to keep a stranger&apos;s
            phone number, and PIPEDA says not to.
          </p>
          <table>
            <thead>
              <tr>
                <th>Child</th>
                <th>Group</th>
                <th>Outcome</th>
                <th>Closed</th>
              </tr>
            </thead>
            <tbody>
              {closed.map((c) => (
                <tr key={c.id}>
                  <td>{c.child_name}</td>
                  <td className="caption">{c.age_group_preset.replace('_', '/')}</td>
                  <td>
                    {c.status}
                    {c.anonymised_at ? <span className="pill ok"> Contact dropped</span> : null}
                  </td>
                  <td>{c.closed_at ? fmtDate(c.closed_at) : ''}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      ) : null}
    </>
  );
}

function PriorityForm({
  entry,
  onSubmit,
}: {
  entry: Entry;
  onSubmit: (priority: string, reason: string) => void;
}) {
  const [priority, setPriority] = useState(entry.priority);
  const [reason, setReason] = useState('');

  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap', marginTop: 6 }}>
      <label>
        Order
        <select value={priority} onChange={(e) => setPriority(e.target.value)}>
          <option value="general">Date order</option>
          <option value="sibling">Sibling of an enrolled child</option>
          <option value="subsidy_referral">Subsidy referral</option>
        </select>
      </label>
      <label style={{ flex: 1, minWidth: 240 }}>
        Why (kept on the record)
        <input
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="Older sibling enrolled in the toddler room"
        />
      </label>
      <button type="button" disabled={!reason.trim()} onClick={() => onSubmit(priority, reason)}>
        Change the order
      </button>
    </div>
  );
}

function AddEnquiry({
  centreId,
  personId,
  onDone,
}: {
  centreId: string;
  personId: string;
  onDone: (msg: string) => void;
}) {
  const [childName, setChildName] = useState('');
  const [dob, setDob] = useState('');
  const [group, setGroup] = useState('infant');
  const [start, setStart] = useState('');
  const [contact, setContact] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [priority, setPriority] = useState('general');
  const [reason, setReason] = useState('');
  const [pin, setPin] = useState('');
  const [code, setCode] = useState<string | null>(null);

  async function submit() {
    const { data, error } = await getSupabase().rpc('join_waitlist', {
      p_centre: centreId,
      p_child_name: childName,
      p_child_dob: dob || null,
      p_age_group: group,
      p_desired_start: start || null,
      p_contact_name: contact,
      p_contact_email: email || null,
      p_contact_phone: phone || null,
      p_priority: priority,
      p_priority_reason: reason || null,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    if (error) {
      setCode(null);
      onDone(error.message);
      return;
    }
    const entry = data as { access_code: string } | null;
    setCode(entry?.access_code ?? null);
    setChildName('');
    setDob('');
    setStart('');
    setContact('');
    setEmail('');
    setPhone('');
    setReason('');
    onDone('Added to the list — give the family their code.');
  }

  return (
    <section className="card">
      <h2>Take an enquiry</h2>
      <p className="muted">
        No fee, no deposit, no holding payment. Give the family their code before they hang up — it is
        how they check their position later without having to ring back.
      </p>
      {code ? (
        <p>
          <span className="pill ok">Their code</span> <strong>{readableCode(code)}</strong> — they enter
          this at /waiting-list. Shown once here; it is on the list above too.
        </p>
      ) : null}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
        <label>
          Child&apos;s name
          <input value={childName} onChange={(e) => setChildName(e.target.value)} placeholder="Noor Haddad" />
        </label>
        <label>
          Date of birth
          <input type="date" value={dob} onChange={(e) => setDob(e.target.value)} />
        </label>
        <label>
          Age group
          <select value={group} onChange={(e) => setGroup(e.target.value)}>
            {GROUPS.map((g) => (
              <option key={g.key} value={g.key}>
                {g.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          Wants to start
          <input type="date" value={start} onChange={(e) => setStart(e.target.value)} />
        </label>
        <label>
          Contact
          <input value={contact} onChange={(e) => setContact(e.target.value)} placeholder="Rana Haddad" />
        </label>
        <label>
          Email
          <input value={email} onChange={(e) => setEmail(e.target.value)} placeholder="rana@example.com" />
        </label>
        <label>
          Phone
          <input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="416-555-0148" />
        </label>
        <label>
          Order
          <select value={priority} onChange={(e) => setPriority(e.target.value)}>
            <option value="general">Date order</option>
            <option value="sibling">Sibling of an enrolled child</option>
            <option value="subsidy_referral">Subsidy referral</option>
          </select>
        </label>
        {priority !== 'general' ? (
          <label style={{ flex: 1, minWidth: 240 }}>
            Why they go above date order
            <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Older sibling in the preschool room" />
          </label>
        ) : null}
        <label className="inline">
          Staff PIN
          <input
            type="password"
            inputMode="numeric"
            value={pin}
            onChange={(e) => setPin(e.target.value)}
            maxLength={6}
            autoComplete="off"
          />
        </label>
        <button type="button" onClick={() => void submit()}>
          Add to the list
        </button>
      </div>
    </section>
  );
}
