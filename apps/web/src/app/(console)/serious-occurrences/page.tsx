'use client';

/** s. 38: serious occurrences. The 24-hour CCLS clock from awareness, the
 * named-human filing record (the app NEVER files to CCLS), the CCLS-down
 * fallback, the CYFSA CAS duty for allegations, updates as information
 * arrives, and the anonymised 10-business-day posting. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, fmtTime, useConsole, zonedToUtc } from '@/lib/console';

const CATEGORY_LABELS: Record<string, string> = {
  death: 'Death of a child',
  abuse_neglect_allegation: 'Abuse or neglect allegation',
  life_threatening_injury_illness: 'Life-threatening injury or illness',
  missing_unsupervised_child: 'Missing or unsupervised child',
  unplanned_disruption: 'Unplanned disruption of operations',
};

interface Occurrence {
  id: string;
  category: string;
  occurred_at: string;
  aware_at: string;
  ccls_deadline_at: string;
  description: string;
  immediate_actions: string | null;
  status: string;
  ccls_number: string | null;
  ccls_filed_at: string | null;
  ccls_filed_by_person: { full_name: string } | null;
  fallback_contacted_at: string | null;
  fallback_note: string | null;
  cas_reported_at: string | null;
  cas_note: string | null;
  closed_at: string | null;
  closed_by_person: { full_name: string } | null;
  closure_note: string | null;
  reported_by_person: { full_name: string } | null;
}

interface UpdateRow {
  id: string;
  serious_occurrence_id: string;
  update_type: string;
  note: string;
  created_at: string;
  recorded_by_person: { full_name: string } | null;
}

interface PostingRow {
  id: string;
  serious_occurrence_id: string;
  version: number;
  summary: string;
  posted_on: string;
  posting_ends_on: string;
}

interface ChildRow {
  id: string;
  full_name: string;
}

function clock(deadline: string, filedAt: string | null): { label: string; kind: 'ok' | 'due' | 'now' } {
  if (filedAt) return { label: 'Filed in CCLS', kind: 'ok' };
  const ms = new Date(deadline).getTime() - Date.now();
  const h = Math.floor(Math.abs(ms) / 3_600_000);
  const m = Math.floor((Math.abs(ms) % 3_600_000) / 60_000);
  if (ms <= 0) return { label: `OVERDUE by ${h}h ${m}m`, kind: 'now' };
  if (ms <= 6 * 3_600_000) return { label: `${h}h ${m}m left to file`, kind: 'now' };
  return { label: `${h}h ${m}m left to file`, kind: 'due' };
}

export default function SeriousOccurrencesPage() {
  const { centre, personId } = useConsole();
  const [rows, setRows] = useState<Occurrence[]>([]);
  const [updates, setUpdates] = useState<UpdateRow[]>([]);
  const [postings, setPostings] = useState<PostingRow[]>([]);
  const [children, setChildren] = useState<ChildRow[]>([]);
  const [open, setOpen] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [, forceTick] = useState(0);

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.from('serious_occurrence')
      .select(
        'id, category, occurred_at, aware_at, ccls_deadline_at, description, immediate_actions, status, ccls_number, ccls_filed_at, fallback_contacted_at, fallback_note, cas_reported_at, cas_note, closed_at, closure_note, ccls_filed_by_person:ccls_filed_by(full_name), closed_by_person:closed_by(full_name), reported_by_person:reported_by(full_name)',
      )
      .eq('centre_id', centre.id)
      .order('created_at', { ascending: false })
      .then(({ data }) => setRows((data as never) ?? []));
    sb.from('serious_occurrence_update')
      .select('id, serious_occurrence_id, update_type, note, created_at, recorded_by_person:recorded_by(full_name)')
      .eq('centre_id', centre.id)
      .order('created_at')
      .then(({ data }) => setUpdates((data as never) ?? []));
    sb.from('serious_occurrence_posting')
      .select('id, serious_occurrence_id, version, summary, posted_on, posting_ends_on')
      .eq('centre_id', centre.id)
      .order('version')
      .then(({ data }) => setPostings((data as never) ?? []));
    sb.from('child').select('id, full_name').eq('centre_id', centre.id).order('full_name')
      .then(({ data }) => setChildren((data as ChildRow[]) ?? []));
  }, [centre.id]);

  useEffect(load, [load]);

  // the countdown chips re-render every minute
  useEffect(() => {
    const t = setInterval(() => forceTick((n) => n + 1), 60_000);
    return () => clearInterval(t);
  }, []);

  const openRows = rows.filter((r) => r.status !== 'closed');
  const closedRows = rows.filter((r) => r.status === 'closed');

  return (
    <>
      <h1>Serious occurrences</h1>
      <section className="card">
        <p className="muted">
          Report through CCLS within <strong>24 hours</strong> of the supervisor or licensee becoming aware
          — Tucked runs the clock, reminds, and records what a named human filed; it never files for you.
          Post the anonymised summary for 10 business days (allegations of abuse or neglect are never posted).
        </p>
      </section>

      <RecordForm centre={centre.id} personId={personId} children={children} onDone={() => { setNotice('Serious occurrence recorded — the 24-hour CCLS clock is running.'); load(); }} />
      {notice ? <section className="card"><p>{notice}</p></section> : null}

      {openRows.map((r) => (
        <OccurrenceCard
          key={r.id}
          r={r}
          tz={centre.timezone}
          personId={personId}
          updates={updates.filter((u) => u.serious_occurrence_id === r.id)}
          postings={postings.filter((p) => p.serious_occurrence_id === r.id)}
          expanded={open === r.id}
          onToggle={() => setOpen(open === r.id ? null : r.id)}
          onChanged={load}
        />
      ))}

      {closedRows.length > 0 ? (
        <section className="card">
          <h2>Closed</h2>
          {closedRows.map((r) => (
            <div key={r.id} style={{ borderTop: '1px solid var(--line, #dbe4f0)', padding: '8px 0' }}>
              <p style={{ margin: 0 }}>
                <strong>{CATEGORY_LABELS[r.category] ?? r.category}</strong> · {fmtDate(r.occurred_at)}{' '}
                <span className="pill ok">Closed</span>{' '}
                <span className="caption">CCLS {r.ccls_number} · closed by {r.closed_by_person?.full_name}</span>
              </p>
              {r.closure_note ? <p className="muted" style={{ margin: '2px 0 0' }}>{r.closure_note}</p> : null}
            </div>
          ))}
        </section>
      ) : null}
    </>
  );
}

function RecordForm({
  centre,
  personId,
  children,
  onDone,
}: {
  centre: string;
  personId: string;
  children: ChildRow[];
  onDone: () => void;
}) {
  const { centre: c } = useConsole();
  const now = new Date();
  const localDate = now.toLocaleDateString('en-CA', { timeZone: c.timezone });
  const localTime = now.toLocaleTimeString('en-CA', { hour: '2-digit', minute: '2-digit', hour12: false, timeZone: c.timezone });
  const [category, setCategory] = useState('missing_unsupervised_child');
  const [occurred, setOccurred] = useState(`${localDate}T${localTime}`);
  const [aware, setAware] = useState(`${localDate}T${localTime}`);
  const [description, setDescription] = useState('');
  const [actions, setActions] = useState('');
  const [kids, setKids] = useState<Set<string>>(new Set());
  const [pin, setPin] = useState('');
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const [od, ot] = occurred.split('T');
    const [ad, at] = aware.split('T');
    const { error: err } = await getSupabase().rpc('record_serious_occurrence', {
      p_centre: centre,
      p_category: category,
      p_occurred_at: zonedToUtc(od!, ot!, c.timezone).toISOString(),
      p_aware_at: zonedToUtc(ad!, at!, c.timezone).toISOString(),
      p_description: description,
      p_immediate_actions: actions,
      p_children: [...kids],
      p_recorder: personId,
      p_pin: pin,
    });
    if (err) {
      setError(err.message);
      return;
    }
    setDescription('');
    setActions('');
    setKids(new Set());
    setPin('');
    onDone();
  }

  return (
    <section className="card">
      <h2>Record a serious occurrence</h2>
      <form onSubmit={submit} style={{ display: 'grid', gap: 10 }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 10 }}>
          <label>
            Category
            <select value={category} onChange={(e) => setCategory(e.target.value)}>
              {Object.entries(CATEGORY_LABELS).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select>
          </label>
          <label>
            When it occurred
            <input type="datetime-local" value={occurred} onChange={(e) => setOccurred(e.target.value)} required />
          </label>
          <label>
            When you became aware (starts the 24-hour clock)
            <input type="datetime-local" value={aware} onChange={(e) => setAware(e.target.value)} required />
          </label>
        </div>
        <label>
          What happened
          <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={3} required />
        </label>
        <label>
          Immediate actions taken
          <textarea value={actions} onChange={(e) => setActions(e.target.value)} rows={2} />
        </label>
        {children.length > 0 ? (
          <div>
            <p className="caption" style={{ margin: '0 0 4px' }}>Children involved (never appears in the public posting)</p>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {children.map((ch) => (
                <label key={ch.id} className="inline" style={{ display: 'inline-flex', alignItems: 'center', gap: 4 }}>
                  <input
                    type="checkbox"
                    checked={kids.has(ch.id)}
                    onChange={(e) => {
                      const next = new Set(kids);
                      if (e.target.checked) next.add(ch.id);
                      else next.delete(ch.id);
                      setKids(next);
                    }}
                  />
                  {ch.full_name}
                </label>
              ))}
            </div>
          </div>
        ) : null}
        <label className="inline">
          Staff PIN
          <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" required />
        </label>
        <div><button type="submit">Record — start the clock</button></div>
        {error ? <p className="muted">{error}</p> : null}
      </form>
    </section>
  );
}

function OccurrenceCard({
  r,
  tz,
  personId,
  updates,
  postings,
  expanded,
  onToggle,
  onChanged,
}: {
  r: Occurrence;
  tz: string;
  personId: string;
  updates: UpdateRow[];
  postings: PostingRow[];
  expanded: boolean;
  onToggle: () => void;
  onChanged: () => void;
}) {
  const c = clock(r.ccls_deadline_at, r.ccls_filed_at);
  const [pin, setPin] = useState('');
  const [ccls, setCcls] = useState('');
  const [fallbackNote, setFallbackNote] = useState('');
  const [casNote, setCasNote] = useState('');
  const [updateNote, setUpdateNote] = useState('');
  const [updateType, setUpdateType] = useState('note');
  const [summary, setSummary] = useState(
    `On ${fmtDate(r.occurred_at)}, a ${(CATEGORY_LABELS[r.category] ?? r.category).toLowerCase()} occurred at the centre.` +
      `${r.immediate_actions ? ` ${r.immediate_actions}` : ''}` +
      ' The Ministry of Education was notified through CCLS. No children or staff are identified in this notice.',
  );
  const [closeNote, setCloseNote] = useState('');
  const [error, setError] = useState<string | null>(null);

  async function call(fn: string, args: Record<string, unknown>, done: string) {
    setError(null);
    const { error: err } = await getSupabase().rpc(fn, { ...args, p_recorder: personId, p_pin: pin });
    if (err) setError(err.message);
    else {
      setError(done);
      setPin('');
      onChanged();
    }
  }

  const isAbuse = r.category === 'abuse_neglect_allegation';

  return (
    <section className="card">
      <h2>
        {CATEGORY_LABELS[r.category] ?? r.category}{' '}
        <span className={`pill ${c.kind}`}>{c.label}</span>
      </h2>
      <p className="muted">
        Occurred {fmtDate(r.occurred_at)} {fmtTime(r.occurred_at, tz)} · aware {fmtTime(r.aware_at, tz)} · CCLS
        deadline {fmtDate(r.ccls_deadline_at)} {fmtTime(r.ccls_deadline_at, tz)} · recorded by{' '}
        {r.reported_by_person?.full_name}
      </p>
      <p>{r.description}</p>
      {r.immediate_actions ? <p className="muted">Actions: {r.immediate_actions}</p> : null}
      {r.ccls_filed_at ? (
        <p>
          <span className="pill ok">Filed</span> CCLS {r.ccls_number} · {fmtDate(r.ccls_filed_at)}{' '}
          {fmtTime(r.ccls_filed_at, tz)} by {r.ccls_filed_by_person?.full_name}
        </p>
      ) : null}
      {r.fallback_contacted_at ? (
        <p className="muted">Program advisor contacted {fmtTime(r.fallback_contacted_at, tz)} — {r.fallback_note}</p>
      ) : null}
      {isAbuse ? (
        r.cas_reported_at ? (
          <p><span className="pill ok">CAS</span> Children&apos;s Aid report recorded {fmtDate(r.cas_reported_at)} {r.cas_note ? `— ${r.cas_note}` : ''}</p>
        ) : (
          <p><span className="pill now">CYFSA</span> Anyone with reasonable grounds must report to the Children&apos;s Aid Society themselves — record that call below. This duty is personal and cannot be delegated.</p>
        )
      ) : null}

      <p><button type="button" className="quiet" onClick={onToggle}>{expanded ? 'Close panel' : 'Work this occurrence'}</button></p>

      {expanded ? (
        <div style={{ display: 'grid', gap: 14 }}>
          {!r.ccls_filed_at ? (
            <div style={{ background: 'var(--mist, #eef4fc)', borderRadius: 12, padding: 12, display: 'grid', gap: 8 }}>
              <p style={{ margin: 0 }}><strong>Record the CCLS filing</strong> — file on the CCLS site first, then enter the serious occurrence number here.</p>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
                <label>CCLS number<input value={ccls} onChange={(e) => setCcls(e.target.value)} placeholder="SO-2026-…" /></label>
                <button type="button" onClick={() => void call('file_serious_occurrence_ccls', { p_occurrence: r.id, p_ccls_number: ccls, p_filed_at: new Date().toISOString() }, 'CCLS filing recorded.')}>I filed this in CCLS</button>
              </div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
                <label>CCLS down? Who you phoned/emailed<input value={fallbackNote} onChange={(e) => setFallbackNote(e.target.value)} placeholder="Phoned program advisor…" /></label>
                <button type="button" className="quiet" onClick={() => void call('record_serious_occurrence_fallback', { p_occurrence: r.id, p_contacted_at: new Date().toISOString(), p_note: fallbackNote }, 'Fallback contact recorded — file in CCLS when it is back.')}>Record fallback contact</button>
              </div>
            </div>
          ) : null}

          {isAbuse && !r.cas_reported_at ? (
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
              <label>CAS report note<input value={casNote} onChange={(e) => setCasNote(e.target.value)} placeholder="Who called, which CAS, reference…" /></label>
              <button type="button" onClick={() => void call('record_cas_report', { p_occurrence: r.id, p_reported_at: new Date().toISOString(), p_note: casNote }, 'CAS report recorded.')}>Record the CAS report</button>
            </div>
          ) : null}

          {!isAbuse ? (
            <div style={{ display: 'grid', gap: 8 }}>
              <p style={{ margin: 0 }}><strong>Anonymised posting</strong> — print and post in a conspicuous place; it must stay up for 10 business days (weekends and holidays don&apos;t count). Names are rejected automatically.</p>
              <textarea value={summary} onChange={(e) => setSummary(e.target.value)} rows={3} />
              <div><button type="button" onClick={() => void call('post_serious_occurrence_summary', { p_occurrence: r.id, p_summary: summary, p_posted_on: new Date().toLocaleDateString('en-CA', { timeZone: tz }) }, 'Posting recorded.')}>Posted today</button></div>
              {postings.map((p) => (
                <p key={p.id} className="muted" style={{ margin: 0 }}>
                  v{p.version} posted {fmtDate(p.posted_on)} — <strong>keep it up through {fmtDate(p.posting_ends_on)}</strong>. “{p.summary}”
                </p>
              ))}
            </div>
          ) : (
            <p className="muted">Abuse or neglect allegations are never posted publicly.</p>
          )}

          <div style={{ display: 'grid', gap: 8 }}>
            <p style={{ margin: 0 }}><strong>Updates</strong> — as information arrives, add it here and file it in CCLS too.</p>
            {updates.map((u) => (
              <p key={u.id} className="muted" style={{ margin: 0 }}>
                {fmtDate(u.created_at)} {fmtTime(u.created_at, tz)} · {u.note}{' '}
                <span className="caption">{u.update_type === 'ccls_update' ? 'filed in CCLS · ' : ''}by {u.recorded_by_person?.full_name}</span>
              </p>
            ))}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
              <label style={{ flex: 1, minWidth: 220 }}>New update<input value={updateNote} onChange={(e) => setUpdateNote(e.target.value)} /></label>
              <label>Type
                <select value={updateType} onChange={(e) => setUpdateType(e.target.value)}>
                  <option value="note">note</option>
                  <option value="ccls_update">also filed in CCLS</option>
                </select>
              </label>
              <button type="button" className="quiet" onClick={() => void call('add_serious_occurrence_update', { p_occurrence: r.id, p_note: updateNote, p_type: updateType }, 'Update added.')}>Add update</button>
            </div>
          </div>

          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
            <label style={{ flex: 1, minWidth: 220 }}>Closure note<input value={closeNote} onChange={(e) => setCloseNote(e.target.value)} placeholder="Ministry review complete…" /></label>
            <button type="button" className="quiet" onClick={() => void call('close_serious_occurrence', { p_occurrence: r.id, p_note: closeNote }, 'Occurrence closed.')}>Close occurrence</button>
          </div>

          <label className="inline">
            Staff PIN (signs whichever action you take)
            <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" />
          </label>
          {error ? <p className="muted">{error}</p> : null}
        </div>
      ) : null}
    </section>
  );
}
