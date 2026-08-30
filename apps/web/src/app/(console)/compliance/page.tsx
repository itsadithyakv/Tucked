'use client';

/** Parts 4 & 10: the compliance calendar — drills, alarm tests, playground
 * inspections, policy reviews, each completion a PIN-signed written record;
 * and the repair log, where a hazard stays loud (and restricted) until
 * someone records what was fixed. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

interface Task {
  id: string;
  slug: string;
  title: string;
  regulation: string;
  cadence: string;
  last_completed_on: string | null;
  next_due_on: string;
  active: boolean;
  notes: string | null;
}

interface Completion {
  id: string;
  task_id: string;
  completed_on: string;
  note: string;
  person: { full_name: string } | null;
}

interface Issue {
  id: string;
  description: string;
  restricted_area: string | null;
  identified_on: string;
  resolved_at: string | null;
  resolved_note: string | null;
  person: { full_name: string } | null;
  resolver: { full_name: string } | null;
}

function dueState(t: Task): { label: string; cls: string } {
  const today = new Date().toISOString().slice(0, 10);
  const soon = new Date(Date.now() + 7 * 86400_000).toISOString().slice(0, 10);
  if (t.next_due_on < today) return { label: `Overdue since ${fmtDate(t.next_due_on)}`, cls: 'now' };
  if (t.next_due_on <= soon) return { label: `Due ${fmtDate(t.next_due_on)}`, cls: 'due' };
  return { label: `Next ${fmtDate(t.next_due_on)}`, cls: 'ok' };
}

export default function CompliancePage() {
  const { centre, personId, roles } = useConsole();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [completions, setCompletions] = useState<Completion[]>([]);
  const [issues, setIssues] = useState<Issue[]>([]);
  const [notice, setNotice] = useState<string | null>(null);

  // complete-a-task form
  const [taskId, setTaskId] = useState('');
  const [note, setNote] = useState('');
  const [pin, setPin] = useState('');
  // hazard form
  const [hazardDesc, setHazardDesc] = useState('');
  const [hazardArea, setHazardArea] = useState('');
  const [hazardTask, setHazardTask] = useState('');
  // resolve + toggle share the same PIN field

  const isLeadership = roles.some((r) => ['supervisor', 'licensee_admin', 'designate'].includes(r));

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.from('compliance_task')
      .select('id, slug, title, regulation, cadence, last_completed_on, next_due_on, active, notes')
      .eq('centre_id', centre.id)
      .order('next_due_on')
      .then(({ data }) => setTasks((data as Task[]) ?? []));
    sb.from('compliance_completion')
      .select('id, task_id, completed_on, note, person:recorded_by(full_name)')
      .eq('centre_id', centre.id)
      .order('completed_on', { ascending: false })
      .limit(30)
      .then(({ data }) => setCompletions((data as never) ?? []));
    sb.from('compliance_issue')
      .select('id, description, restricted_area, identified_on, resolved_at, resolved_note, person:recorded_by(full_name), resolver:resolved_by(full_name)')
      .eq('centre_id', centre.id)
      .order('created_at', { ascending: false })
      .limit(30)
      .then(({ data }) => setIssues((data as never) ?? []));
  }, [centre.id]);

  useEffect(load, [load]);

  async function call(fn: string, args: Record<string, unknown>, done: string): Promise<boolean> {
    setNotice(null);
    const { error } = await getSupabase().rpc(fn, { ...args, p_recorder: personId, p_pin: pin });
    if (error) {
      setNotice(error.message);
      return false;
    }
    setNotice(done);
    setPin('');
    load();
    return true;
  }

  const activeTasks = tasks.filter((t) => t.active);
  const overdue = activeTasks.filter((t) => t.next_due_on < new Date().toISOString().slice(0, 10));
  const openIssues = issues.filter((i) => !i.resolved_at);
  const taskById = new Map(tasks.map((t) => [t.id, t]));

  return (
    <>
      <h1>Compliance calendar</h1>
      {notice ? <section className="card"><p>{notice}</p></section> : null}

      <section className="card">
        <h2>Schedule (Parts 4 &amp; 10 — every completion is the written record)</h2>
        {overdue.length > 0 ? (
          <p><span className="pill now">Now</span> {overdue.length} task{overdue.length === 1 ? '' : 's'} overdue.</p>
        ) : (
          <p className="muted">Nothing overdue — boring inspections are the goal.</p>
        )}
        <table>
          <thead>
            <tr>
              <th>Task</th>
              <th>Regulation</th>
              <th>Cadence</th>
              <th>Last done</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {tasks.map((t) => {
              const state = dueState(t);
              return (
                <tr key={t.id}>
                  <td className="wrap">
                    {t.title}
                    {t.notes ? <span className="caption"> — {t.notes}</span> : null}
                  </td>
                  <td className="caption">{t.regulation}</td>
                  <td>{t.cadence}</td>
                  <td>{t.last_completed_on ? fmtDate(t.last_completed_on) : '—'}</td>
                  <td>
                    {t.active ? (
                      <span className={`pill ${state.cls}`}>{state.label}</span>
                    ) : (
                      <span className="caption">off</span>
                    )}
                    {isLeadership ? (
                      <button
                        type="button"
                        className="quiet"
                        style={{ marginLeft: 8 }}
                        onClick={() => void call('set_compliance_task_active', { p_task: t.id, p_active: !t.active }, t.active ? 'Task switched off.' : 'Task switched on.')}
                      >
                        {t.active ? 'off' : 'on'}
                      </button>
                    ) : null}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </section>

      <section className="card">
        <h2>Record a completion</h2>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
          <label>
            Task
            <select value={taskId} onChange={(e) => setTaskId(e.target.value)}>
              <option value="">Choose…</option>
              {activeTasks.map((t) => <option key={t.id} value={t.id}>{t.title}</option>)}
            </select>
          </label>
          <label style={{ flex: 1, minWidth: 280 }}>
            What was done and what was found (this is the written record)
            <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="Alarm sounded on test; extinguisher gauges green…" />
          </label>
          <label className="inline">
            Staff PIN
            <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" />
          </label>
          <button
            type="button"
            onClick={() => void call('complete_compliance_task', { p_task: taskId, p_note: note, p_completed_on: null }, 'Recorded — the schedule has advanced.').then((ok) => ok && setNote(''))}
          >
            Record completion
          </button>
        </div>
      </section>

      <section className="card">
        <h2>Repair log (hazards restricted until fixed)</h2>
        {openIssues.map((i) => (
          <div key={i.id} style={{ borderTop: '1px solid var(--line, #dbe4f0)', padding: '8px 0' }}>
            <p style={{ margin: 0 }}>
              <span className="pill now">Open</span> {i.description}
              {i.restricted_area ? <strong> — {i.restricted_area}</strong> : null}{' '}
              <span className="caption">found {fmtDate(i.identified_on)} by {i.person?.full_name}</span>
            </p>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end', marginTop: 6 }}>
              <ResolveRow onResolve={(fixNote) => void call('resolve_compliance_issue', { p_issue: i.id, p_note: fixNote }, 'Hazard resolved — restriction lifted.')} />
            </div>
          </div>
        ))}
        {openIssues.length === 0 ? <p className="muted">No open hazards.</p> : null}
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end', marginTop: 8 }}>
          <label style={{ flex: 1, minWidth: 240 }}>
            New hazard
            <input value={hazardDesc} onChange={(e) => setHazardDesc(e.target.value)} placeholder="Swing chain worn at the top link" />
          </label>
          <label>
            What was restricted
            <input value={hazardArea} onChange={(e) => setHazardArea(e.target.value)} placeholder="Both swings taped off" />
          </label>
          <label>
            Related task (optional)
            <select value={hazardTask} onChange={(e) => setHazardTask(e.target.value)}>
              <option value="">—</option>
              {tasks.map((t) => <option key={t.id} value={t.id}>{t.title}</option>)}
            </select>
          </label>
          <button
            type="button"
            onClick={() => void call('record_compliance_issue', { p_centre: centre.id, p_task: hazardTask || null, p_description: hazardDesc, p_restricted_area: hazardArea }, 'Hazard recorded — it is in the daily written record too.').then((ok) => { if (ok) { setHazardDesc(''); setHazardArea(''); } })}
          >
            Record hazard
          </button>
        </div>
        {issues.filter((i) => i.resolved_at).slice(0, 5).map((i) => (
          <p key={i.id} className="muted" style={{ margin: '6px 0 0' }}>
            <span className="pill ok">Fixed</span> {i.description} — {i.resolved_note}{' '}
            <span className="caption">by {i.resolver?.full_name}, {fmtDate(i.resolved_at)}</span>
          </p>
        ))}
      </section>

      <section className="card">
        <h2>Recent written records</h2>
        <table>
          <thead>
            <tr>
              <th>Date</th>
              <th>Task</th>
              <th>Record</th>
              <th>By</th>
            </tr>
          </thead>
          <tbody>
            {completions.map((cpl) => (
              <tr key={cpl.id}>
                <td>{fmtDate(cpl.completed_on)}</td>
                <td className="wrap">{taskById.get(cpl.task_id)?.title ?? '—'}</td>
                <td className="wrap muted">{cpl.note}</td>
                <td className="caption">{cpl.person?.full_name}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </>
  );
}

function ResolveRow({ onResolve }: { onResolve: (note: string) => void }) {
  const [fixNote, setFixNote] = useState('');
  return (
    <>
      <label style={{ flex: 1, minWidth: 240 }}>
        What was repaired or changed
        <input value={fixNote} onChange={(e) => setFixNote(e.target.value)} placeholder="Chain replaced; swings re-checked and reopened" />
      </label>
      <button type="button" className="quiet" onClick={() => onResolve(fixNote)}>
        Resolve (PIN above)
      </button>
    </>
  );
}
