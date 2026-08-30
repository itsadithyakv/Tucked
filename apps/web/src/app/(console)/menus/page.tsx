'use client';

/** Part 6 (ss. 42–44): the menu for this week and next, posted where parents
 * can see it; substitutions noted on the day beside what was planned; and the
 * written feeding instructions a parent gives for an infant or a special
 * diet. A posted week is frozen — the day's reality is a substitution. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

const MEALS = [
  { key: 'breakfast', label: 'Breakfast' },
  { key: 'snack_am', label: 'Morning snack' },
  { key: 'lunch', label: 'Lunch' },
  { key: 'snack_pm', label: 'Afternoon snack' },
] as const;

const DAYS = [
  { dow: 1, label: 'Monday' },
  { dow: 2, label: 'Tuesday' },
  { dow: 3, label: 'Wednesday' },
  { dow: 4, label: 'Thursday' },
  { dow: 5, label: 'Friday' },
];

interface Week {
  id: string;
  week_start: string;
  status: string;
  posted_at: string | null;
  posted_by_person: { full_name: string } | null;
}

interface Item {
  menu_week_id: string;
  day_of_week: number;
  meal: string;
  description: string;
}

interface Substitution {
  id: string;
  served_on: string;
  meal: string;
  planned: string | null;
  served: string;
  reason: string;
  person: { full_name: string } | null;
}

interface Instruction {
  id: string;
  child_id: string;
  kind: string;
  instructions: string;
  child: { full_name: string } | null;
  parent: { full_name: string } | null;
}

/** The Monday on or before a date, as an ISO date string. */
function mondayOf(base: Date, weeksAhead = 0): string {
  const d = new Date(Date.UTC(base.getFullYear(), base.getMonth(), base.getDate()));
  const dow = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() - (dow - 1) + weeksAhead * 7);
  return d.toISOString().slice(0, 10);
}

function cellKey(dow: number, meal: string) {
  return `${dow}:${meal}`;
}

export default function MenusPage() {
  const { centre, personId } = useConsole();
  const thisMonday = mondayOf(new Date());
  const nextMonday = mondayOf(new Date(), 1);

  const [weekStart, setWeekStart] = useState(thisMonday);
  const [weeks, setWeeks] = useState<Week[]>([]);
  const [items, setItems] = useState<Item[]>([]);
  const [grid, setGrid] = useState<Map<string, string>>(new Map());
  const [subs, setSubs] = useState<Substitution[]>([]);
  const [instructions, setInstructions] = useState<Instruction[]>([]);
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.from('menu_week')
      .select('id, week_start, status, posted_at, posted_by_person:posted_by(full_name)')
      .eq('centre_id', centre.id)
      .order('week_start', { ascending: false })
      .limit(8)
      .then(({ data }) => setWeeks((data as never) ?? []));
    sb.from('menu_item')
      .select('menu_week_id, day_of_week, meal, description')
      .eq('centre_id', centre.id)
      .then(({ data }) => setItems((data as Item[]) ?? []));
    sb.from('menu_substitution')
      .select('id, served_on, meal, planned, served, reason, person:recorded_by(full_name)')
      .eq('centre_id', centre.id)
      .order('served_on', { ascending: false })
      .limit(30)
      .then(({ data }) => setSubs((data as never) ?? []));
    sb.from('feeding_instruction')
      .select('id, child_id, kind, instructions, child:child_id(full_name), parent:provided_by(full_name)')
      .eq('centre_id', centre.id)
      .is('ended_at', null)
      .then(({ data }) => setInstructions((data as never) ?? []));
  }, [centre.id]);

  useEffect(load, [load]);

  const week = weeks.find((w) => w.week_start === weekStart);
  const posted = week?.status === 'posted';

  // the editable grid mirrors the week's saved items until the user types
  useEffect(() => {
    const next = new Map<string, string>();
    for (const i of items.filter((i) => i.menu_week_id === week?.id)) {
      next.set(cellKey(i.day_of_week, i.meal), i.description);
    }
    setGrid(next);
  }, [items, week?.id]);

  async function saveWeek() {
    setBusy(true);
    setNotice(null);
    const sb = getSupabase();
    const saved = items.filter((i) => i.menu_week_id === week?.id);
    let failure: string | null = null;
    for (const [key, description] of grid) {
      const [dowText, meal] = key.split(':');
      const dow = Number(dowText);
      const before = saved.find((i) => i.day_of_week === dow && i.meal === meal)?.description ?? '';
      if (description.trim() === before.trim() || description.trim() === '') continue;
      const { error } = await sb.rpc('upsert_menu_item', {
        p_centre: centre.id,
        p_week_start: weekStart,
        p_day: dow,
        p_meal: meal,
        p_description: description,
        p_recorder: personId,
        p_pin: pin,
      });
      if (error) {
        failure = error.message;
        break;
      }
    }
    setBusy(false);
    setPin('');
    setNotice(failure ?? 'Menu saved.');
    load();
  }

  async function post() {
    setNotice(null);
    const { error } = await getSupabase().rpc('post_menu_week', {
      p_centre: centre.id,
      p_week_start: weekStart,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    setNotice(error ? error.message : 'Posted — families can see this week now.');
    load();
  }

  const missingNext = !weeks.some((w) => w.week_start === nextMonday && w.status === 'posted');
  const missingThis = !weeks.some((w) => w.week_start === thisMonday && w.status === 'posted');

  return (
    <>
      <h1>Menus</h1>
      {notice ? <section className="card"><p>{notice}</p></section> : null}

      <section className="card">
        <h2>This week and next (s. 42)</h2>
        {missingThis || missingNext ? (
          <p>
            <span className="pill due">Due</span>{' '}
            {missingThis && missingNext
              ? 'Neither this week nor next week is posted.'
              : missingThis
                ? 'This week is not posted yet.'
                : 'Next week is not posted yet — the menu must cover the current and the following week.'}
          </p>
        ) : (
          <p className="muted">This week and next week are both planned and posted.</p>
        )}
        <div className="toolbar">
          <button className={weekStart === thisMonday ? '' : 'quiet'} onClick={() => setWeekStart(thisMonday)}>
            Week of {fmtDate(thisMonday)}
          </button>
          <button className={weekStart === nextMonday ? '' : 'quiet'} onClick={() => setWeekStart(nextMonday)}>
            Week of {fmtDate(nextMonday)}
          </button>
        </div>
      </section>

      <section className="card print-target" id="menu-print">
        <h2>
          Week of {fmtDate(weekStart)}{' '}
          {posted ? (
            <span className="pill ok">Posted {week?.posted_at ? fmtDate(week.posted_at) : ''}</span>
          ) : (
            <span className="pill due">Draft</span>
          )}
        </h2>
        {posted ? (
          <p className="muted">
            Posted by {week?.posted_by_person?.full_name}. A posted menu is frozen — record a substitution on
            the day if what is served changes.
          </p>
        ) : (
          <p className="muted">Type the week, save it, then post it where parents can see it.</p>
        )}
        <div className="print-area">
          <h3>{centre.name} — menu for the week of {fmtDate(weekStart)}</h3>
          <div style={{ overflowX: 'auto' }}>
            <table>
              <thead>
                <tr>
                  <th>Meal</th>
                  {DAYS.map((d) => <th key={d.dow}>{d.label}</th>)}
                </tr>
              </thead>
              <tbody>
                {MEALS.map((m) => (
                  <tr key={m.key}>
                    <td><strong>{m.label}</strong></td>
                    {DAYS.map((d) => {
                      const key = cellKey(d.dow, m.key);
                      const value = grid.get(key) ?? '';
                      return (
                        <td key={d.dow} className="wrap">
                          {posted ? (
                            value || <span className="caption">—</span>
                          ) : (
                            <input
                              value={value}
                              onChange={(e) => setGrid(new Map(grid).set(key, e.target.value))}
                              placeholder="—"
                              style={{ width: '100%' }}
                            />
                          )}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {subs.filter((s) => s.served_on >= weekStart).length > 0 ? (
            <div>
              <h4>Substitutions this week (noted at the time)</h4>
              {subs
                .filter((s) => s.served_on >= weekStart)
                .map((s) => (
                  <p key={s.id} className="muted" style={{ margin: '2px 0' }}>
                    {fmtDate(s.served_on)} · {s.meal.replace('_', ' ')} — served <strong>{s.served}</strong>
                    {s.planned ? ` instead of ${s.planned}` : ''} ({s.reason})
                  </p>
                ))}
            </div>
          ) : null}
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end', marginTop: 10 }}>
          <label className="inline">
            Staff PIN
            <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" />
          </label>
          {!posted ? (
            <>
              <button type="button" disabled={busy} onClick={() => void saveWeek()}>
                {busy ? 'Saving…' : 'Save menu'}
              </button>
              <button type="button" className="quiet" onClick={() => void post()}>Post this week</button>
            </>
          ) : (
            <button type="button" className="quiet" onClick={() => window.print()}>Print the posted menu</button>
          )}
        </div>
      </section>

      <SubstitutionCard
        centreId={centre.id}
        personId={personId}
        subs={subs}
        onDone={(msg) => { setNotice(msg); load(); }}
      />

      <FeedingCard
        centreId={centre.id}
        personId={personId}
        instructions={instructions}
        onDone={(msg) => { setNotice(msg); load(); }}
      />
    </>
  );
}

function SubstitutionCard({
  centreId,
  personId,
  subs,
  onDone,
}: {
  centreId: string;
  personId: string;
  subs: Substitution[];
  onDone: (msg: string) => void;
}) {
  const [meal, setMeal] = useState<string>('lunch');
  const [served, setServed] = useState('');
  const [reason, setReason] = useState('');
  const [pin, setPin] = useState('');

  async function submit() {
    const { error } = await getSupabase().rpc('record_menu_substitution', {
      p_centre: centreId,
      p_served_on: null,
      p_meal: meal,
      p_served: served,
      p_reason: reason,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    if (!error) {
      setServed('');
      setReason('');
    }
    onDone(error ? error.message : 'Substitution recorded on today’s menu.');
  }

  return (
    <section className="card">
      <h2>Record a substitution (today)</h2>
      <p className="muted">
        What was actually served, and why. The posted menu keeps its promise beside it — that pair is the record.
      </p>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
        <label>
          Meal
          <select value={meal} onChange={(e) => setMeal(e.target.value)}>
            {MEALS.map((m) => <option key={m.key} value={m.key}>{m.label}</option>)}
          </select>
        </label>
        <label style={{ flex: 1, minWidth: 220 }}>
          Served instead
          <input value={served} onChange={(e) => setServed(e.target.value)} placeholder="Vegetable soup with bread and milk" />
        </label>
        <label style={{ flex: 1, minWidth: 200 }}>
          Reason
          <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Delivery did not arrive" />
        </label>
        <label className="inline">
          Staff PIN
          <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" />
        </label>
        <button type="button" onClick={() => void submit()}>Record</button>
      </div>
      {subs.length > 0 ? (
        <table>
          <thead>
            <tr><th>Date</th><th>Meal</th><th>Planned</th><th>Served</th><th>Reason</th><th>By</th></tr>
          </thead>
          <tbody>
            {subs.map((s) => (
              <tr key={s.id}>
                <td>{fmtDate(s.served_on)}</td>
                <td>{s.meal.replace('_', ' ')}</td>
                <td className="wrap muted">{s.planned ?? '—'}</td>
                <td className="wrap">{s.served}</td>
                <td className="wrap muted">{s.reason}</td>
                <td className="caption">{s.person?.full_name}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
    </section>
  );
}

function FeedingCard({
  centreId,
  personId,
  instructions,
  onDone,
}: {
  centreId: string;
  personId: string;
  instructions: Instruction[];
  onDone: (msg: string) => void;
}) {
  const [children, setChildren] = useState<{ id: string; full_name: string }[]>([]);
  const [childId, setChildId] = useState('');
  const [kind, setKind] = useState('infant_feeding');
  const [text, setText] = useState('');
  const [parents, setParents] = useState<{ person_id: string; full_name: string }[]>([]);
  const [parentId, setParentId] = useState('');
  const [pin, setPin] = useState('');

  useEffect(() => {
    getSupabase()
      .from('child')
      .select('id, full_name')
      .eq('centre_id', centreId)
      .is('discharge_date', null)
      .order('full_name')
      .then(({ data }) => setChildren(data ?? []));
  }, [centreId]);

  useEffect(() => {
    if (!childId) {
      setParents([]);
      return;
    }
    getSupabase()
      .from('child_household')
      .select('household:household_id(household_member(person_id, can_consent, revoked_at, person:person_id(full_name)))')
      .eq('child_id', childId)
      .then(({ data }) => {
        const rows =
          ((data as never as { household: { household_member: { person_id: string; can_consent: boolean; revoked_at: string | null; person: { full_name: string } | null }[] } | null }[]) ?? [])
            .flatMap((r) => r.household?.household_member ?? [])
            .filter((m) => m.can_consent && !m.revoked_at && m.person)
            .map((m) => ({ person_id: m.person_id, full_name: m.person!.full_name }));
        setParents(rows);
        setParentId(rows[0]?.person_id ?? '');
      });
  }, [childId]);

  async function submit() {
    const { error } = await getSupabase().rpc('record_feeding_instruction', {
      p_centre: centreId,
      p_child: childId,
      p_kind: kind,
      p_instructions: text,
      p_parent: parentId,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    if (!error) setText('');
    onDone(error ? error.message : 'Written instructions recorded.');
  }

  return (
    <section className="card">
      <h2>Feeding &amp; special diet instructions (s. 44)</h2>
      <p className="muted">
        Infants are fed per the parent&apos;s written instructions, and special dietary arrangements follow written
        instructions too. These appear in the room on the staff device.
      </p>
      {instructions.map((i) => (
        <p key={i.id} style={{ margin: '4px 0' }}>
          <span className="pill ok">{i.kind === 'infant_feeding' ? 'Infant feeding' : 'Special diet'}</span>{' '}
          <strong>{i.child?.full_name}</strong> — {i.instructions}{' '}
          <span className="caption">from {i.parent?.full_name}</span>
        </p>
      ))}
      {instructions.length === 0 ? <p className="muted">No written feeding instructions on file.</p> : null}
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
            <option value="infant_feeding">Infant feeding</option>
            <option value="special_diet">Special diet</option>
          </select>
        </label>
        <label style={{ flex: 1, minWidth: 260 }}>
          The parent&apos;s written instructions
          <input value={text} onChange={(e) => setText(e.target.value)} placeholder="150 ml expressed milk on waking; purée at 11:30…" />
        </label>
        <label>
          Given by
          <select value={parentId} onChange={(e) => setParentId(e.target.value)}>
            {parents.map((p) => <option key={p.person_id} value={p.person_id}>{p.full_name}</option>)}
          </select>
        </label>
        <label className="inline">
          Staff PIN
          <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" />
        </label>
        <button type="button" onClick={() => void submit()}>Record</button>
      </div>
    </section>
  );
}
