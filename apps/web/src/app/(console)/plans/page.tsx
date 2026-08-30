'use client';

/** ss. 39, 39.1, 52: individualised plans — anaphylaxis, medical needs,
 * special needs. New plans start as drafts and go active only once a parent
 * agreement is recorded (in-app or signed paper). s. 43(3): the allergy and
 * food-restriction list, printable per room and for the kitchen. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

const TYPE_LABELS: Record<string, string> = {
  anaphylaxis: 'Anaphylaxis',
  medical_needs: 'Medical needs',
  special_needs: 'Special needs',
};

interface Plan {
  id: string;
  child_id: string;
  plan_type: string;
  version: number;
  condition: string;
  allergens: string[];
  signs: string | null;
  emergency_procedure: string | null;
  exposure_reduction: string | null;
  devices_instructions: string | null;
  supports: string | null;
  evacuation_procedure: string | null;
  developed_with: string;
  status: string;
  parent_agreed_at: string | null;
  agreement_method: string | null;
  review_due_on: string | null;
  child: { full_name: string } | null;
  agreed_person: { full_name: string } | null;
}

interface ChildRow {
  id: string;
  full_name: string;
  room: { name: string } | null;
}

interface Restriction {
  id: string;
  child_id: string;
  kind: string;
  substance: string;
  note: string | null;
  child: { full_name: string } | null;
}

interface ListRow {
  child_id: string;
  full_name: string;
  current_room_id: string | null;
  kind: string;
  item: string;
  emergency_procedure: string | null;
}

export default function PlansPage() {
  const { centre, personId } = useConsole();
  const [plans, setPlans] = useState<Plan[]>([]);
  const [children, setChildren] = useState<ChildRow[]>([]);
  const [restrictions, setRestrictions] = useState<Restriction[]>([]);
  const [list, setList] = useState<ListRow[]>([]);
  const [rooms, setRooms] = useState<{ id: string; name: string }[]>([]);
  const [policy, setPolicy] = useState<string>('');
  const [policySaved, setPolicySaved] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.from('individualised_plan')
      .select(
        'id, child_id, plan_type, version, condition, allergens, signs, emergency_procedure, exposure_reduction, devices_instructions, supports, evacuation_procedure, developed_with, status, parent_agreed_at, agreement_method, review_due_on, child:child_id(full_name), agreed_person:parent_agreed_by(full_name)',
      )
      .eq('centre_id', centre.id)
      .in('status', ['draft', 'active'])
      .order('created_at', { ascending: false })
      .then(({ data }) => setPlans((data as never) ?? []));
    sb.from('child')
      .select('id, full_name, room:current_room_id(name)')
      .eq('centre_id', centre.id)
      .is('discharge_date', null)
      .order('full_name')
      .then(({ data }) => setChildren((data as never) ?? []));
    sb.from('dietary_restriction')
      .select('id, child_id, kind, substance, note, child:child_id(full_name)')
      .eq('centre_id', centre.id)
      .is('ended_at', null)
      .then(({ data }) => setRestrictions((data as never) ?? []));
    sb.from('allergy_list')
      .select('child_id, full_name, current_room_id, kind, item, emergency_procedure')
      .eq('centre_id', centre.id)
      .order('full_name')
      .then(({ data }) => setList((data as ListRow[]) ?? []));
    sb.from('room').select('id, name').eq('centre_id', centre.id).order('name')
      .then(({ data }) => setRooms(data ?? []));
    sb.from('centre').select('anaphylaxis_policy').eq('id', centre.id).maybeSingle()
      .then(({ data }) => setPolicy(data?.anaphylaxis_policy ?? ''));
  }, [centre.id]);

  useEffect(load, [load]);

  async function savePolicy() {
    const { error } = await getSupabase()
      .from('centre')
      .update({ anaphylaxis_policy: policy.trim() || null })
      .eq('id', centre.id);
    setPolicySaved(!error);
    setNotice(error ? error.message : null);
  }

  return (
    <>
      <h1>Individualised plans</h1>
      {notice ? <section className="card"><p>{notice}</p></section> : null}

      <section className="card">
        <h2>Anaphylaxis policy (s. 39 — required even with no allergic children)</h2>
        {!policy.trim() ? (
          <p><span className="pill now">Now</span> No anaphylaxis policy on file — every centre must have one.</p>
        ) : null}
        <textarea value={policy} onChange={(e) => { setPolicy(e.target.value); setPolicySaved(false); }} rows={3} />
        <p>
          <button type="button" onClick={() => void savePolicy()}>Save policy</button>{' '}
          {policySaved ? <span className="pill ok">Saved</span> : null}
        </p>
      </section>

      <PlanForm centreId={centre.id} personId={personId} children={children} onDone={() => { setNotice('Plan recorded as a draft — the family has been asked to agree.'); load(); }} />

      <section className="card">
        <h2>Live plans</h2>
        {plans.length === 0 ? <p className="muted">No individualised plans yet.</p> : null}
        {plans.map((p) => (
          <PlanRow key={p.id} p={p} personId={personId} onChanged={load} />
        ))}
      </section>

      <RestrictionForm centreId={centre.id} personId={personId} children={children} restrictions={restrictions} onDone={load} />

      <section className="card" id="allergy-list-print">
        <h2>Allergy &amp; food-restriction list (s. 43(3))</h2>
        <p className="muted">
          Post a copy in every cooking or serving area and every play room. Print, date, and replace whenever it
          changes — this list is always the live truth.
        </p>
        <p><button type="button" onClick={() => window.print()}>Print the list</button></p>
        <div className="print-area">
          <h3>{centre.name} — allergy &amp; food-restriction list · {fmtDate(new Date().toISOString())}</h3>
          {rooms.map((r) => {
            const roomRows = list.filter((l) => l.current_room_id === r.id);
            return (
              <div key={r.id}>
                <h4>{r.name}</h4>
                {roomRows.length === 0 ? (
                  <p className="muted">No allergies or restrictions in this room.</p>
                ) : (
                  <table>
                    <thead><tr><th>Child</th><th>Allergy / restriction</th><th>Emergency</th></tr></thead>
                    <tbody>
                      {roomRows.map((l, i) => (
                        <tr key={i}>
                          <td>{l.full_name}</td>
                          <td>
                            {l.kind === 'anaphylaxis' ? <strong>ANAPHYLAXIS — {l.item}</strong> : `${l.item} (${l.kind.replace('_', ' ')})`}
                          </td>
                          <td className="wrap">{l.emergency_procedure ?? '—'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            );
          })}
        </div>
      </section>
    </>
  );
}

function PlanForm({
  centreId,
  personId,
  children,
  onDone,
}: {
  centreId: string;
  personId: string;
  children: ChildRow[];
  onDone: () => void;
}) {
  const [childId, setChildId] = useState('');
  const [type, setType] = useState('anaphylaxis');
  const [condition, setCondition] = useState('');
  const [allergens, setAllergens] = useState('');
  const [signs, setSigns] = useState('');
  const [emergency, setEmergency] = useState('');
  const [exposure, setExposure] = useState('');
  const [devices, setDevices] = useState('');
  const [supports, setSupports] = useState('');
  const [evacuation, setEvacuation] = useState('');
  const [developedWith, setDevelopedWith] = useState('');
  const [pin, setPin] = useState('');
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const { error: err } = await getSupabase().rpc('upsert_individualised_plan', {
      p_centre: centreId,
      p_child: childId,
      p_type: type,
      p_condition: condition,
      p_allergens: allergens.split(',').map((s) => s.trim()).filter(Boolean),
      p_signs: signs,
      p_emergency: emergency,
      p_exposure: exposure,
      p_devices: devices,
      p_supports: supports,
      p_evacuation: evacuation,
      p_developed_with: developedWith,
      p_recorder: personId,
      p_pin: pin,
    });
    if (err) { setError(err.message); return; }
    setCondition(''); setAllergens(''); setSigns(''); setEmergency(''); setExposure('');
    setDevices(''); setSupports(''); setEvacuation(''); setDevelopedWith(''); setPin('');
    onDone();
  }

  return (
    <section className="card">
      <h2>New plan (or new version — the old one is kept, superseded)</h2>
      <form onSubmit={submit} style={{ display: 'grid', gap: 10 }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 10 }}>
          <label>
            Child
            <select value={childId} onChange={(e) => setChildId(e.target.value)} required>
              <option value="">Choose…</option>
              {children.map((c) => <option key={c.id} value={c.id}>{c.full_name}</option>)}
            </select>
          </label>
          <label>
            Plan type
            <select value={type} onChange={(e) => setType(e.target.value)}>
              {Object.entries(TYPE_LABELS).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
            </select>
          </label>
          <label>
            Condition
            <input value={condition} onChange={(e) => setCondition(e.target.value)} placeholder="Anaphylaxis — peanut allergy" required />
          </label>
          <label>
            Developed with (parent + professionals)
            <input value={developedWith} onChange={(e) => setDevelopedWith(e.target.value)} placeholder="Alex Osei (parent), Dr. Patel" required />
          </label>
        </div>
        {type === 'anaphylaxis' ? (
          <label>
            Allergens (comma-separated)
            <input value={allergens} onChange={(e) => setAllergens(e.target.value)} placeholder="peanuts, tree nuts" />
          </label>
        ) : null}
        {type !== 'special_needs' ? (
          <>
            <label>
              Signs of a reaction / episode
              <textarea value={signs} onChange={(e) => setSigns(e.target.value)} rows={2} />
            </label>
            <label>
              Emergency procedure
              <textarea value={emergency} onChange={(e) => setEmergency(e.target.value)} rows={2} />
            </label>
            <label>
              Exposure reduction / avoidance
              <textarea value={exposure} onChange={(e) => setExposure(e.target.value)} rows={2} />
            </label>
            <label>
              Devices &amp; where they live (EpiPen, inhaler…)
              <textarea value={devices} onChange={(e) => setDevices(e.target.value)} rows={2} />
            </label>
          </>
        ) : null}
        {type !== 'anaphylaxis' ? (
          <label>
            Supports &amp; strategies
            <textarea value={supports} onChange={(e) => setSupports(e.target.value)} rows={2} />
          </label>
        ) : null}
        <label>
          Evacuation / field-trip procedure
          <textarea value={evacuation} onChange={(e) => setEvacuation(e.target.value)} rows={2} />
        </label>
        <label className="inline">
          Staff PIN
          <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" required />
        </label>
        <div><button type="submit">Record plan — ask the family to agree</button></div>
        {error ? <p className="muted">{error}</p> : null}
      </form>
    </section>
  );
}

function PlanRow({
  p,
  personId,
  onChanged,
}: {
  p: Plan;
  personId: string;
  onChanged: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [pin, setPin] = useState('');
  const [paperParent, setPaperParent] = useState('');
  const [members, setMembers] = useState<{ person_id: string; full_name: string }[]>([]);
  const [error, setError] = useState<string | null>(null);

  const reviewOverdue = p.status === 'active' && p.review_due_on !== null && p.review_due_on < new Date().toISOString().slice(0, 10);

  useEffect(() => {
    if (!open || p.status !== 'draft') return;
    // consenting adults for the signed-paper path
    getSupabase()
      .from('child_household')
      .select('household:household_id(household_member(person_id, can_consent, revoked_at, person:person_id(full_name)))')
      .eq('child_id', p.child_id)
      .then(({ data }) => {
        const rows =
          ((data as never as { household: { household_member: { person_id: string; can_consent: boolean; revoked_at: string | null; person: { full_name: string } | null }[] } | null }[]) ?? [])
            .flatMap((r) => r.household?.household_member ?? [])
            .filter((m) => m.can_consent && !m.revoked_at && m.person)
            .map((m) => ({ person_id: m.person_id, full_name: m.person!.full_name }));
        setMembers(rows);
        setPaperParent((cur) => cur || rows[0]?.person_id || '');
      });
  }, [open, p.child_id, p.status]);

  async function call(fn: string, args: Record<string, unknown>, done: string) {
    setError(null);
    const { error: err } = await getSupabase().rpc(fn, { ...args, p_recorder: personId, p_pin: pin });
    if (err) setError(err.message);
    else { setError(done); setPin(''); onChanged(); }
  }

  return (
    <div style={{ borderTop: '1px solid var(--line, #dbe4f0)', padding: '10px 0' }}>
      <p style={{ margin: 0 }}>
        <strong>{p.child?.full_name}</strong> · {TYPE_LABELS[p.plan_type]} v{p.version} — {p.condition}{' '}
        {p.status === 'draft' ? (
          <span className="pill due">Awaiting agreement</span>
        ) : reviewOverdue ? (
          <span className="pill now">Review overdue</span>
        ) : (
          <span className="pill ok">Active</span>
        )}
      </p>
      <p className="muted" style={{ margin: '2px 0 0' }}>
        {p.parent_agreed_at
          ? `Agreed ${fmtDate(p.parent_agreed_at)} by ${p.agreed_person?.full_name} (${p.agreement_method === 'in_app' ? 'in app' : 'signed paper'}) · review due ${fmtDate(p.review_due_on)}`
          : 'The family has been asked to agree in the app — or record a signed paper below.'}
        {' '}· developed with {p.developed_with}
      </p>
      <p style={{ margin: '6px 0 0' }}>
        <button type="button" className="quiet" onClick={() => setOpen(!open)}>{open ? 'Close' : 'Details'}</button>
      </p>
      {open ? (
        <div style={{ background: 'var(--mist, #eef4fc)', borderRadius: 12, padding: 12, display: 'grid', gap: 6 }}>
          {p.allergens.length > 0 ? <p style={{ margin: 0 }}><strong>Allergens:</strong> {p.allergens.join(', ')}</p> : null}
          {p.signs ? <p style={{ margin: 0 }}><strong>Signs:</strong> {p.signs}</p> : null}
          {p.emergency_procedure ? <p style={{ margin: 0 }}><strong>Emergency:</strong> {p.emergency_procedure}</p> : null}
          {p.exposure_reduction ? <p style={{ margin: 0 }}><strong>Exposure reduction:</strong> {p.exposure_reduction}</p> : null}
          {p.devices_instructions ? <p style={{ margin: 0 }}><strong>Devices:</strong> {p.devices_instructions}</p> : null}
          {p.supports ? <p style={{ margin: 0 }}><strong>Supports:</strong> {p.supports}</p> : null}
          {p.evacuation_procedure ? <p style={{ margin: 0 }}><strong>Evacuation:</strong> {p.evacuation_procedure}</p> : null}
          {p.status === 'draft' ? (
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
              <label>
                Signed paper from
                <select value={paperParent} onChange={(e) => setPaperParent(e.target.value)}>
                  {members.map((m) => <option key={m.person_id} value={m.person_id}>{m.full_name}</option>)}
                </select>
              </label>
              <label>PIN<input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" /></label>
              <button type="button" onClick={() => void call('record_plan_agreement', { p_plan: p.id, p_parent: paperParent, p_agreed_at: new Date().toISOString() }, 'Signed paper recorded — the plan is active.')}>Record signed paper</button>
            </div>
          ) : (
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
              <label>PIN<input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" /></label>
              <button type="button" className="quiet" onClick={() => void call('end_individualised_plan', { p_plan: p.id, p_note: 'ended from console' }, 'Plan ended (kept on file).')}>End plan</button>
            </div>
          )}
          {error ? <p className="muted">{error}</p> : null}
        </div>
      ) : null}
    </div>
  );
}

function RestrictionForm({
  centreId,
  personId,
  children,
  restrictions,
  onDone,
}: {
  centreId: string;
  personId: string;
  children: ChildRow[];
  restrictions: Restriction[];
  onDone: () => void;
}) {
  const [childId, setChildId] = useState('');
  const [kind, setKind] = useState('allergy');
  const [substance, setSubstance] = useState('');
  const [note, setNote] = useState('');
  const [pin, setPin] = useState('');
  const [error, setError] = useState<string | null>(null);

  async function add() {
    setError(null);
    const { error: err } = await getSupabase().rpc('record_dietary_restriction', {
      p_centre: centreId, p_child: childId, p_kind: kind, p_substance: substance,
      p_note: note, p_recorder: personId, p_pin: pin,
    });
    if (err) { setError(err.message); return; }
    setSubstance(''); setNote(''); setPin('');
    onDone();
  }

  async function end(id: string) {
    setError(null);
    const { error: err } = await getSupabase().rpc('end_dietary_restriction', {
      p_restriction: id, p_recorder: personId, p_pin: pin,
    });
    setError(err ? err.message : null);
    onDone();
  }

  return (
    <section className="card">
      <h2>Dietary restrictions &amp; non-anaphylactic allergies</h2>
      {restrictions.map((r) => (
        <p key={r.id} style={{ margin: '4px 0' }}>
          {r.child?.full_name} — {r.substance} <span className="caption">({r.kind.replace('_', ' ')}{r.note ? ` · ${r.note}` : ''})</span>{' '}
          <button type="button" className="quiet" onClick={() => void end(r.id)}>End (PIN below)</button>
        </p>
      ))}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
        <label>
          Child
          <select value={childId} onChange={(e) => setChildId(e.target.value)}>
            <option value="">Choose…</option>
            {children.map((c) => <option key={c.id} value={c.id}>{c.full_name}</option>)}
          </select>
        </label>
        <label>
          Kind
          <select value={kind} onChange={(e) => setKind(e.target.value)}>
            <option value="allergy">allergy</option>
            <option value="intolerance">intolerance</option>
            <option value="food_restriction">food restriction</option>
          </select>
        </label>
        <label>Substance / restriction<input value={substance} onChange={(e) => setSubstance(e.target.value)} placeholder="Eggs" /></label>
        <label>Note<input value={note} onChange={(e) => setNote(e.target.value)} /></label>
        <label>PIN<input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" /></label>
        <button type="button" onClick={() => void add()}>Add</button>
      </div>
      {error ? <p className="muted">{error}</p> : null}
    </section>
  );
}
