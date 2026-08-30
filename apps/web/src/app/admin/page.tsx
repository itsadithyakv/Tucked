'use client';

/** The platform surface: every daycare on Tucked with its jurisdiction, plan
 * and billing state; onboarding a new pilot; changing a plan; recording a
 * manual payment. This page sees tenancy and money only — RLS never shows a
 * platform admin a child, a family, or an attendance row. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate } from '@/lib/console';

interface CentreRow {
  id: string;
  name: string;
  licence_number: string;
  address: string;
  jurisdiction_code: string;
  created_at: string;
  licensee: { legal_name: string } | null;
}

interface SubRow {
  centre_id: string;
  plan_code: string;
  status: string;
  pilot_ends_on: string | null;
  notes: string | null;
}

interface PlanRow {
  code: string;
  name: string;
  description: string | null;
  price_per_child_cents: number;
  monthly_minimum_cents: number;
  active: boolean;
}

interface JurisdictionRow {
  code: string;
  name: string;
  rule_status: string;
  active: boolean;
}

interface SupervisorRow {
  centre_id: string;
  person: { full_name: string; email: string | null } | null;
}

interface BillingRow {
  id: string;
  centre_id: string;
  event_type: string;
  amount_cents: number | null;
  detail: string | null;
  recorded_by_email: string;
  created_at: string;
}

const STATUS_PILL: Record<string, string> = {
  pilot: 'ok',
  active: 'ok',
  past_due: 'due',
  cancelled: 'now',
};

function money(cents: number): string {
  return `$${(cents / 100).toFixed(cents % 100 === 0 ? 0 : 2)}`;
}

export default function PlatformHome() {
  const [centres, setCentres] = useState<CentreRow[]>([]);
  const [subs, setSubs] = useState<Map<string, SubRow>>(new Map());
  const [plans, setPlans] = useState<PlanRow[]>([]);
  const [jurisdictions, setJurisdictions] = useState<JurisdictionRow[]>([]);
  const [supervisors, setSupervisors] = useState<Map<string, SupervisorRow['person'][]>>(new Map());
  const [billing, setBilling] = useState<BillingRow[]>([]);
  const [open, setOpen] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // onboarding form
  const [form, setForm] = useState({
    licensee: '', centre: '', licence: '', address: '', jurisdiction: 'CA-ON',
    timezone: 'America/Toronto', opens: '07:30', closes: '18:00',
    supName: '', supEmail: '', plan: 'pilot', pilotEnds: '',
  });
  const [busy, setBusy] = useState(false);

  const refresh = useCallback(() => {
    const sb = getSupabase();
    sb.from('centre')
      .select('id, name, licence_number, address, jurisdiction_code, created_at, licensee:licensee_id(legal_name)')
      .order('created_at', { ascending: false })
      .then(({ data }) => setCentres((data as never) ?? []));
    sb.from('centre_subscription')
      .select('centre_id, plan_code, status, pilot_ends_on, notes')
      .then(({ data }) => setSubs(new Map(((data as SubRow[]) ?? []).map((s) => [s.centre_id, s]))));
    sb.from('plan').select('code, name, description, price_per_child_cents, monthly_minimum_cents, active')
      .order('monthly_minimum_cents')
      .then(({ data }) => setPlans((data as PlanRow[]) ?? []));
    sb.from('jurisdiction').select('code, name, rule_status, active').order('code')
      .then(({ data }) => setJurisdictions((data as JurisdictionRow[]) ?? []));
    sb.from('person_role')
      .select('centre_id, person:person_id(full_name, email)')
      .eq('role', 'supervisor')
      .eq('active', true)
      .then(({ data }) => {
        const map = new Map<string, SupervisorRow['person'][]>();
        for (const r of ((data as never as SupervisorRow[]) ?? [])) {
          map.set(r.centre_id, [...(map.get(r.centre_id) ?? []), r.person]);
        }
        setSupervisors(map);
      });
    sb.from('billing_event')
      .select('id, centre_id, event_type, amount_cents, detail, recorded_by_email, created_at')
      .order('created_at', { ascending: false })
      .limit(100)
      .then(({ data }) => setBilling((data as BillingRow[]) ?? []));
  }, []);

  useEffect(refresh, [refresh]);

  async function createCentre(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setNotice(null);
    const { error } = await getSupabase().rpc('admin_create_centre', {
      p_licensee_name: form.licensee.trim(),
      p_centre_name: form.centre.trim(),
      p_licence_number: form.licence.trim(),
      p_address: form.address.trim(),
      p_jurisdiction: form.jurisdiction,
      p_timezone: form.timezone.trim(),
      p_opens: form.opens,
      p_closes: form.closes,
      p_supervisor_name: form.supName.trim(),
      p_supervisor_email: form.supEmail.trim(),
      p_plan: form.plan,
      p_pilot_ends_on: form.pilotEnds || null,
    });
    setBusy(false);
    if (error) {
      setNotice(error.message);
      return;
    }
    setNotice(`${form.centre.trim()} is on Tucked. ${form.supName.trim()} signs in with a magic link to ${form.supEmail.trim()} — nothing to send them but the app link.`);
    setForm((f) => ({ ...f, licensee: '', centre: '', licence: '', address: '', supName: '', supEmail: '', pilotEnds: '' }));
    refresh();
  }

  async function setPlan(centreId: string, plan: string, status: string, pilotEnds: string, note: string) {
    const { error } = await getSupabase().rpc('admin_set_plan', {
      p_centre: centreId,
      p_plan: plan,
      p_status: status,
      p_pilot_ends_on: pilotEnds || null,
      p_note: note || null,
    });
    setNotice(error ? error.message : 'Plan updated.');
    refresh();
  }

  async function recordPayment(centreId: string, amount: string, note: string) {
    const cents = Math.round(parseFloat(amount) * 100);
    if (!Number.isFinite(cents) || cents <= 0) {
      setNotice('A payment needs a positive dollar amount.');
      return;
    }
    const { error } = await getSupabase().rpc('admin_record_payment', {
      p_centre: centreId,
      p_amount_cents: cents,
      p_note: note || null,
    });
    setNotice(error ? error.message : 'Payment recorded.');
    refresh();
  }

  return (
    <>
      {notice ? (
        <section className="card">
          <p>{notice}</p>
        </section>
      ) : null}

      <section className="card">
        <h2>Daycares on Tucked</h2>
        {centres.length === 0 ? <p className="muted">No centres yet — add the first pilot below.</p> : null}
        {centres.map((c) => {
          const sub = subs.get(c.id);
          const sups = supervisors.get(c.id) ?? [];
          const plan = plans.find((p) => p.code === sub?.plan_code);
          const events = billing.filter((b) => b.centre_id === c.id).slice(0, 5);
          return (
            <div key={c.id} style={{ borderTop: '1px solid var(--line, #dbe4f0)', padding: '12px 0' }}>
              <p style={{ margin: 0 }}>
                <strong>{c.name}</strong> <span className="caption">{c.licensee?.legal_name} · {c.licence_number} · {c.jurisdiction_code}</span>{' '}
                {sub ? <span className={`pill ${STATUS_PILL[sub.status] ?? 'due'}`}>{plan?.name ?? sub.plan_code} · {sub.status.replace('_', ' ')}</span> : null}
              </p>
              <p className="muted" style={{ margin: '4px 0 0' }}>
                {sups.length > 0
                  ? `Supervisor: ${sups.map((s) => `${s?.full_name}${s?.email ? ` (${s.email})` : ''}`).join(', ')}`
                  : 'No supervisor invited yet'}
                {sub?.pilot_ends_on ? ` · pilot until ${fmtDate(sub.pilot_ends_on)}` : ''}
              </p>
              <p style={{ margin: '6px 0 0' }}>
                <button type="button" className="quiet" onClick={() => setOpen(open === c.id ? null : c.id)}>
                  {open === c.id ? 'Close' : 'Manage plan & billing'}
                </button>
              </p>
              {open === c.id ? (
                <ManagePanel
                  sub={sub}
                  plans={plans}
                  onSetPlan={(plan, status, ends, note) => void setPlan(c.id, plan, status, ends, note)}
                  onPayment={(amount, note) => void recordPayment(c.id, amount, note)}
                  events={events}
                />
              ) : null}
            </div>
          );
        })}
      </section>

      <section className="card">
        <h2>Add a daycare</h2>
        <p className="muted">
          Creates the licensee, the centre, the pilot subscription, and invites the supervisor: they sign in
          with a magic link to their email — no password to create or send.
        </p>
        <form onSubmit={createCentre} style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: 12 }}>
          <label>
            Licensee (legal name)
            <input value={form.licensee} onChange={(e) => setForm({ ...form, licensee: e.target.value })} required />
          </label>
          <label>
            Centre name
            <input value={form.centre} onChange={(e) => setForm({ ...form, centre: e.target.value })} required />
          </label>
          <label>
            Licence number
            <input value={form.licence} onChange={(e) => setForm({ ...form, licence: e.target.value })} required />
          </label>
          <label>
            Address
            <input value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} required />
          </label>
          <label>
            Jurisdiction
            <select value={form.jurisdiction} onChange={(e) => setForm({ ...form, jurisdiction: e.target.value })}>
              {jurisdictions.map((j) => (
                <option key={j.code} value={j.code} disabled={!j.active || j.rule_status !== 'implemented'}>
                  {j.name} ({j.code}){j.rule_status !== 'implemented' ? ' — rule pack not built yet' : ''}
                </option>
              ))}
            </select>
          </label>
          <label>
            Timezone
            <input value={form.timezone} onChange={(e) => setForm({ ...form, timezone: e.target.value })} />
          </label>
          <label>
            Opens
            <input type="time" value={form.opens} onChange={(e) => setForm({ ...form, opens: e.target.value })} />
          </label>
          <label>
            Closes
            <input type="time" value={form.closes} onChange={(e) => setForm({ ...form, closes: e.target.value })} />
          </label>
          <label>
            Supervisor name
            <input value={form.supName} onChange={(e) => setForm({ ...form, supName: e.target.value })} required />
          </label>
          <label>
            Supervisor email
            <input type="email" value={form.supEmail} onChange={(e) => setForm({ ...form, supEmail: e.target.value })} required />
          </label>
          <label>
            Plan
            <select value={form.plan} onChange={(e) => setForm({ ...form, plan: e.target.value })}>
              {plans.filter((p) => p.active).map((p) => (
                <option key={p.code} value={p.code}>
                  {p.name}{p.price_per_child_cents > 0 ? ` — ${money(p.price_per_child_cents)}/child, min ${money(p.monthly_minimum_cents)}/mo` : ' — free'}
                </option>
              ))}
            </select>
          </label>
          <label>
            Pilot ends (optional)
            <input type="date" value={form.pilotEnds} onChange={(e) => setForm({ ...form, pilotEnds: e.target.value })} />
          </label>
          <div style={{ gridColumn: '1 / -1' }}>
            <button type="submit" disabled={busy}>{busy ? 'Creating…' : 'Add daycare'}</button>
          </div>
        </form>
      </section>

      <section className="card">
        <h2>Plans</h2>
        {plans.map((p) => (
          <p key={p.code} style={{ margin: '4px 0' }}>
            <strong>{p.name}</strong>{' '}
            {p.price_per_child_cents > 0
              ? `${money(p.price_per_child_cents)} per child per month, ${money(p.monthly_minimum_cents)} minimum`
              : 'Free'}{' '}
            <span className="caption">{p.description}</span>
          </p>
        ))}
        <p className="caption">
          Published CAD pricing, no per-staff fee, no setup fee, parents always free. A lapsed or cancelled plan
          never hides or locks a centre&apos;s records — that line is enforced in the database and proven by tests.
        </p>
      </section>
    </>
  );
}

function ManagePanel({
  sub,
  plans,
  onSetPlan,
  onPayment,
  events,
}: {
  sub: SubRow | undefined;
  plans: PlanRow[];
  onSetPlan: (plan: string, status: string, pilotEnds: string, note: string) => void;
  onPayment: (amount: string, note: string) => void;
  events: BillingRow[];
}) {
  const [plan, setPlanCode] = useState(sub?.plan_code ?? 'pilot');
  const [status, setStatus] = useState(sub?.status ?? 'pilot');
  const [pilotEnds, setPilotEnds] = useState(sub?.pilot_ends_on ?? '');
  const [note, setNote] = useState('');
  const [amount, setAmount] = useState('');
  const [payNote, setPayNote] = useState('');

  return (
    <div style={{ background: 'var(--mist, #eef4fc)', borderRadius: 12, padding: 12, marginTop: 8, display: 'grid', gap: 10 }}>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, alignItems: 'end' }}>
        <label>
          Plan
          <select value={plan} onChange={(e) => setPlanCode(e.target.value)}>
            {plans.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
          </select>
        </label>
        <label>
          Status
          <select value={status} onChange={(e) => setStatus(e.target.value)}>
            {['pilot', 'active', 'past_due', 'cancelled'].map((s) => <option key={s} value={s}>{s.replace('_', ' ')}</option>)}
          </select>
        </label>
        <label>
          Pilot ends
          <input type="date" value={pilotEnds} onChange={(e) => setPilotEnds(e.target.value)} />
        </label>
        <label>
          Note
          <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="why the change" />
        </label>
        <button type="button" onClick={() => onSetPlan(plan, status, pilotEnds, note)}>Save plan</button>
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, alignItems: 'end' }}>
        <label>
          Payment (CAD)
          <input inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="149.00" />
        </label>
        <label>
          Reference
          <input value={payNote} onChange={(e) => setPayNote(e.target.value)} placeholder="e-Transfer ref…" />
        </label>
        <button type="button" onClick={() => onPayment(amount, payNote)}>Record payment</button>
      </div>
      {events.length > 0 ? (
        <div>
          <p className="caption" style={{ margin: '0 0 4px' }}>Recent billing events</p>
          {events.map((b) => (
            <p key={b.id} className="muted" style={{ margin: '2px 0' }}>
              {fmtDate(b.created_at)} · {b.event_type.replace(/_/g, ' ')}
              {b.amount_cents ? ` · ${money(b.amount_cents)}` : ''}
              {b.detail ? ` · ${b.detail}` : ''} <span className="caption">by {b.recorded_by_email}</span>
            </p>
          ))}
        </div>
      ) : null}
    </div>
  );
}
