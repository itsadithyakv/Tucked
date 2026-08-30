'use client';

/** Fees, the CWELCC cap, and CRA receipts. Tucked records money; it does not
 * move money — there is no card processing here and no parent-side payment
 * fee. The cap is enforced in the database, so a base fee above it cannot be
 * saved or charged, and nothing on this page can gate a regulated record: no
 * policy anywhere reads a balance. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

interface Schedule {
  id: string;
  age_group_preset: string;
  base_daily_fee: number;
  unfunded_daily_fee: number | null;
  effective_on: string;
}

interface Item {
  id: string;
  code: string;
  label: string;
  kind: string;
  amount: number;
  description: string;
  optional: boolean;
  active: boolean;
}

interface Balance {
  household_id: string;
  name: string;
  charged: number;
  credited: number;
  paid: number;
  balance: number;
}

interface Charge {
  id: string;
  household_id: string;
  child_id: string | null;
  kind: string;
  description: string;
  period_start: string;
  amount: number;
  unit_amount: number | null;
  cap_at_charge: number | null;
  eligible_at_charge: boolean | null;
  child: { full_name: string } | null;
}

interface Payment {
  id: string;
  household_id: string;
  amount: number;
  method: string;
  received_on: string;
  reference: string | null;
}

interface Receipt {
  id: string;
  household_id: string;
  tax_year: number;
  receipt_number: string;
  provider_name: string;
  provider_business_number: string | null;
  provider_address: string;
  payer_name: string;
  total_amount: number;
  issued_at: string;
  replaced_at: string | null;
}

interface ReceiptLine {
  receipt_id: string;
  child_name: string;
  child_date_of_birth: string | null;
  period_start: string;
  period_end: string;
  amount: number;
}

const money = (n: number | null | undefined) =>
  n === null || n === undefined ? '—' : `$${Number(n).toFixed(2)}`;

const GROUP: Record<string, string> = {
  infant: 'Infant',
  toddler: 'Toddler',
  preschool: 'Preschool',
  kindergarten: 'Kindergarten',
  primary_junior: 'Primary/junior',
  junior: 'Junior',
  family: 'Family age',
};

const METHOD: Record<string, string> = {
  pre_authorised_debit: 'Pre-authorised debit',
  e_transfer: 'e-Transfer',
  cheque: 'Cheque',
  cash: 'Cash',
  subsidy: 'Fee subsidy',
  other: 'Other',
};

export default function FeesPage() {
  const { centre, personId } = useConsole();
  const thisYear = new Date().getFullYear();
  const [cap, setCap] = useState<number | null>(null);
  const [schedules, setSchedules] = useState<Schedule[]>([]);
  const [items, setItems] = useState<Item[]>([]);
  const [balances, setBalances] = useState<Balance[]>([]);
  const [charges, setCharges] = useState<Charge[]>([]);
  const [payments, setPayments] = useState<Payment[]>([]);
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [lines, setLines] = useState<ReceiptLine[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [showReceipt, setShowReceipt] = useState<string | null>(null);
  const [year, setYear] = useState(thisYear - 1);
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.rpc('cwelcc_cap_today', { p_centre: centre.id }).then(({ data }) =>
      setCap(data === null || data === undefined ? null : Number(data)),
    );
    sb.from('fee_schedule')
      .select('id, age_group_preset, base_daily_fee, unfunded_daily_fee, effective_on')
      .eq('centre_id', centre.id)
      .order('effective_on', { ascending: false })
      .then(({ data }) => setSchedules((data as Schedule[]) ?? []));
    sb.from('fee_item')
      .select('id, code, label, kind, amount, description, optional, active')
      .eq('centre_id', centre.id)
      .order('label')
      .then(({ data }) => setItems((data as Item[]) ?? []));
    sb.from('household_balance')
      .select('household_id, name, charged, credited, paid, balance')
      .eq('centre_id', centre.id)
      .then(({ data }) =>
        setBalances(((data as Balance[]) ?? []).filter((b) => Number(b.charged) > 0)),
      );
    sb.from('fee_charge')
      .select('id, household_id, child_id, kind, description, period_start, amount, unit_amount, cap_at_charge, eligible_at_charge, child:child_id(full_name)')
      .eq('centre_id', centre.id)
      .order('period_start', { ascending: false })
      .limit(60)
      .then(({ data }) => setCharges((data as never) ?? []));
    sb.from('fee_payment')
      .select('id, household_id, amount, method, received_on, reference')
      .eq('centre_id', centre.id)
      .order('received_on', { ascending: false })
      .limit(40)
      .then(({ data }) => setPayments((data as Payment[]) ?? []));
    sb.from('cra_receipt')
      .select('*')
      .eq('centre_id', centre.id)
      .order('tax_year', { ascending: false })
      .then(({ data }) => setReceipts((data as Receipt[]) ?? []));
    sb.from('cra_receipt_line')
      .select('receipt_id, child_name, child_date_of_birth, period_start, period_end, amount')
      .eq('centre_id', centre.id)
      .then(({ data }) => setLines((data as ReceiptLine[]) ?? []));
  }, [centre.id]);

  useEffect(load, [load]);

  async function issue(householdId: string) {
    setNotice(null);
    const { error } = await getSupabase().rpc('issue_cra_receipt', {
      p_centre: centre.id,
      p_household: householdId,
      p_year: year,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    setNotice(error ? error.message : `Receipt issued for ${year}.`);
    load();
  }

  const owing = balances.filter((b) => Number(b.balance) > 0);
  const viewing = showReceipt ? receipts.find((r) => r.id === showReceipt) : null;

  return (
    <>
      <h1>Fees &amp; receipts</h1>
      {notice ? <section className="card"><p>{notice}</p></section> : null}

      <section className="card">
        <h2>What Tucked does with money</h2>
        <p className="muted">
          Tucked records what was billed and what arrived. It does not process payments, so there is no
          card fee and no parent-side charge for paying child care fees. Whatever a family owes,{' '}
          <strong>nothing here can hide or lock a record</strong> — no access rule anywhere reads a
          balance, and the database is tested for it.
        </p>
        <p>
          {centre.cwelcc_enrolled ? (
            <>
              <span className="pill ok">CWELCC</span> Base fees for eligible children are capped at{' '}
              <strong>{money(cap)}</strong> a day. A fee above the cap cannot be saved or charged.
            </>
          ) : (
            <>
              <span className="pill due">Not in CWELCC</span> The cap does not apply. The parent
              handbook must say so (s. 45).
            </>
          )}
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

      <section className="card">
        <h2>The fee schedule</h2>
        <table>
          <thead>
            <tr>
              <th>Age group</th>
              <th>Base fee (eligible)</th>
              <th>Unfunded fee</th>
              <th>From</th>
            </tr>
          </thead>
          <tbody>
            {schedules.map((s) => (
              <tr key={s.id}>
                <td>{GROUP[s.age_group_preset] ?? s.age_group_preset}</td>
                <td>
                  {money(s.base_daily_fee)}/day{' '}
                  {cap !== null && Number(s.base_daily_fee) <= cap ? (
                    <span className="pill ok">At or under the cap</span>
                  ) : null}
                </td>
                <td className="caption">{money(s.unfunded_daily_fee)}/day</td>
                <td className="caption">{fmtDate(s.effective_on)}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <ScheduleForm
          centreId={centre.id}
          personId={personId}
          pin={pin}
          onDone={(msg) => {
            setNotice(msg);
            setPin('');
            load();
          }}
        />

        <h3>Non-base fees</h3>
        <p className="muted">
          Every non-base fee is optional — the schema will not accept one that is a condition of
          enrolment, because that is the thing CWELCC forbids.
        </p>
        {items.map((i) => (
          <p key={i.id} style={{ margin: '4px 0' }}>
            <span className="pill ok">{i.kind === 'base' ? 'Base' : 'Optional'}</span>{' '}
            <strong>{i.label}</strong> {money(i.amount)} — <span className="muted">{i.description}</span>
          </p>
        ))}
      </section>

      <section className="card">
        <h2>Families</h2>
        {owing.length > 0 ? (
          <p className="muted">
            {owing.length} {owing.length === 1 ? 'family has' : 'families have'} an outstanding balance.
            Their children are signed in, their records are open, and their app works exactly as before.
          </p>
        ) : null}
        <table>
          <thead>
            <tr>
              <th>Household</th>
              <th>Charged</th>
              <th>Credited</th>
              <th>Paid</th>
              <th>Balance</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {balances.map((b) => (
              <tr key={b.household_id}>
                <td>{b.name}</td>
                <td className="caption">{money(b.charged)}</td>
                <td className="caption">{money(b.credited)}</td>
                <td className="caption">{money(b.paid)}</td>
                <td>
                  <strong>{money(b.balance)}</strong>
                </td>
                <td>
                  <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                    <button
                      className="quiet"
                      onClick={() => setSelected(selected === b.household_id ? null : b.household_id)}
                    >
                      Ledger
                    </button>
                    <button className="quiet" onClick={() => void issue(b.household_id)}>
                      Issue {year} receipt
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <label>
          Tax year
          <select value={year} onChange={(e) => setYear(Number(e.target.value))}>
            {[thisYear, thisYear - 1, thisYear - 2].map((y) => (
              <option key={y} value={y}>
                {y}
              </option>
            ))}
          </select>
        </label>
        {selected ? (
          <div style={{ marginTop: 10 }}>
            <h3>Ledger</h3>
            <div style={{ overflowX: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    <th>Period</th>
                    <th>What</th>
                    <th>Child</th>
                    <th>Per day</th>
                    <th>Amount</th>
                  </tr>
                </thead>
                <tbody>
                  {charges
                    .filter((c) => c.household_id === selected)
                    .map((c) => (
                      <tr key={c.id}>
                        <td className="caption">{fmtDate(c.period_start)}</td>
                        <td className="wrap">{c.description}</td>
                        <td className="caption">{c.child?.full_name ?? '—'}</td>
                        <td className="caption">
                          {money(c.unit_amount)}
                          {c.eligible_at_charge ? (
                            <> <span className="pill ok">CWELCC</span></>
                          ) : null}
                        </td>
                        <td>{money(c.amount)}</td>
                      </tr>
                    ))}
                  {payments
                    .filter((p) => p.household_id === selected)
                    .map((p) => (
                      <tr key={p.id}>
                        <td className="caption">{fmtDate(p.received_on)}</td>
                        <td className="wrap muted">
                          Payment — {METHOD[p.method]}
                          {p.reference ? ` (${p.reference})` : ''}
                        </td>
                        <td></td>
                        <td></td>
                        <td className="muted">−{money(p.amount)}</td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
          </div>
        ) : null}
      </section>

      <section className="card">
        <h2>CRA receipts</h2>
        <p className="muted">
          A receipt is issued from what the family actually <strong>paid</strong> in the year — not what
          they were billed — and split across their children by what each was charged. Once issued it
          never changes; a correction is a replacement receipt.
        </p>
        {receipts.length === 0 ? <p className="muted">No receipts issued yet.</p> : null}
        <table>
          <thead>
            <tr>
              <th>Number</th>
              <th>Year</th>
              <th>Payer</th>
              <th>Amount</th>
              <th>Issued</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {receipts.map((r) => (
              <tr key={r.id}>
                <td>{r.receipt_number}</td>
                <td>{r.tax_year}</td>
                <td>{r.payer_name}</td>
                <td>{money(r.total_amount)}</td>
                <td className="caption">
                  {fmtDate(r.issued_at)}
                  {r.replaced_at ? <> <span className="pill due">Replaced</span></> : null}
                </td>
                <td>
                  <button className="quiet" onClick={() => setShowReceipt(showReceipt === r.id ? null : r.id)}>
                    {showReceipt === r.id ? 'Hide' : 'Open'}
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      {viewing ? (
        <section className="card print-target">
          <div className="print-area">
            <h2>Receipt for child care expenses</h2>
            <p className="caption">
              Receipt {viewing.receipt_number} · tax year {viewing.tax_year} · issued{' '}
              {fmtDate(viewing.issued_at)}
            </p>
            <p>
              <strong>{viewing.provider_name}</strong>
              <br />
              {viewing.provider_address}
              <br />
              Business number: {viewing.provider_business_number ?? '—'}
            </p>
            <p>
              Received from <strong>{viewing.payer_name}</strong> the sum of{' '}
              <strong>{money(viewing.total_amount)}</strong> for child care services provided in{' '}
              {viewing.tax_year}:
            </p>
            <table>
              <thead>
                <tr>
                  <th>Child</th>
                  <th>Date of birth</th>
                  <th>Period</th>
                  <th>Amount</th>
                </tr>
              </thead>
              <tbody>
                {lines
                  .filter((l) => l.receipt_id === viewing.id)
                  .map((l, i) => (
                    <tr key={i}>
                      <td>{l.child_name}</td>
                      <td className="caption">
                        {l.child_date_of_birth ? fmtDate(l.child_date_of_birth) : '—'}
                      </td>
                      <td className="caption">
                        {fmtDate(l.period_start)} – {fmtDate(l.period_end)}
                      </td>
                      <td>{money(l.amount)}</td>
                    </tr>
                  ))}
              </tbody>
            </table>
            <p className="caption">
              Keep this receipt for your records. Child care expenses are claimed on your income tax
              return; the Canada Revenue Agency may ask to see it.
            </p>
          </div>
          <button type="button" className="quiet" onClick={() => window.print()}>
            Print the receipt
          </button>
        </section>
      ) : null}
    </>
  );
}

function ScheduleForm({
  centreId,
  personId,
  pin,
  onDone,
}: {
  centreId: string;
  personId: string;
  pin: string;
  onDone: (msg: string) => void;
}) {
  const [group, setGroup] = useState('preschool');
  const [base, setBase] = useState('');
  const [unfunded, setUnfunded] = useState('');

  async function submit() {
    const { error } = await getSupabase().rpc('set_fee_schedule', {
      p_centre: centreId,
      p_age_group: group,
      p_base_daily: Number(base),
      p_unfunded_daily: unfunded ? Number(unfunded) : null,
      p_effective_on: null,
      p_recorder: personId,
      p_pin: pin,
    });
    if (!error) {
      setBase('');
      setUnfunded('');
    }
    onDone(error ? error.message : 'Fee schedule saved, effective today.');
  }

  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap', marginTop: 8 }}>
      <label>
        Age group
        <select value={group} onChange={(e) => setGroup(e.target.value)}>
          {Object.entries(GROUP).map(([k, v]) => (
            <option key={k} value={k}>
              {v}
            </option>
          ))}
        </select>
      </label>
      <label>
        Base fee per day
        <input
          type="number"
          step="0.01"
          min="0"
          value={base}
          onChange={(e) => setBase(e.target.value)}
          placeholder="22.00"
        />
      </label>
      <label>
        Unfunded fee per day
        <input
          type="number"
          step="0.01"
          min="0"
          value={unfunded}
          onChange={(e) => setUnfunded(e.target.value)}
          placeholder="58.00"
        />
      </label>
      <button type="button" disabled={!base} onClick={() => void submit()}>
        Save the fee
      </button>
    </div>
  );
}
