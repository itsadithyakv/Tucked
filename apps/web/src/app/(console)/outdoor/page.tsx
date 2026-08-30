'use client';

/** s. 47: two hours of outdoor play a day, weather permitting. The minutes on
 * this page were measured — the room device recorded when the group went out
 * and when it came in — so they are arithmetic on two clock times rather than
 * a number somebody typed at five o'clock. The per-child table is the one the
 * regulation actually asks about: a child who arrived at one o'clock did not
 * get the morning block. A short day carries its reason, and a child is kept
 * in only on a physician's or a parent's written instruction. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

interface Requirement {
  key: string;
  min_minutes: number;
  care_hours_min: number;
  age_months_min: number;
  regulation: string;
  note: string;
}

interface RoomDay {
  room_id: string;
  outdoor_date: string;
  minutes: number;
  periods: number;
  outside_now: boolean;
}

interface ChildDay {
  child_id: string;
  full_name: string;
  hours_in_care: number;
  hours_expected: number;
  minutes_outside: number;
  required_minutes: number;
  short_by: number;
  exempt: boolean;
  exemption_note: string | null;
}

interface Period {
  id: string;
  room_id: string;
  started_at: string;
  ended_at: string | null;
  weather: string | null;
}

interface Shortfall {
  id: string;
  room_id: string;
  outdoor_date: string;
  reason: string;
  person: { full_name: string } | null;
}

interface Exemption {
  id: string;
  child_id: string;
  source: string;
  practitioner: string | null;
  instruction: string;
  starts_on: string;
  ends_on: string | null;
  child: { full_name: string } | null;
  parent: { full_name: string } | null;
}

const WEATHER: Record<string, string> = {
  fine: 'Fine',
  cloudy: 'Cloudy',
  rain: 'Rain',
  snow: 'Snow',
  extreme_cold: 'Extreme cold',
  extreme_heat: 'Extreme heat',
  wind: 'Windy',
  poor_air: 'Poor air quality',
};

/** In the CENTRE's timezone, not the reader's: these are times a program
 * advisor will compare against the room's own clock. */
function hhmm(iso: string, tz: string): string {
  return new Date(iso).toLocaleTimeString('en-CA', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: tz,
  });
}

function duration(mins: number): string {
  if (mins < 60) return `${mins} min`;
  return `${Math.floor(mins / 60)} h ${String(mins % 60).padStart(2, '0')}`;
}

export default function OutdoorPage() {
  const { centre, personId } = useConsole();
  const today = new Date().toISOString().slice(0, 10);
  const [date, setDate] = useState(today);
  const [rooms, setRooms] = useState<{ id: string; name: string }[]>([]);
  const [requirements, setRequirements] = useState<Requirement[]>([]);
  const [days, setDays] = useState<RoomDay[]>([]);
  const [periods, setPeriods] = useState<Period[]>([]);
  const [children, setChildren] = useState<ChildDay[]>([]);
  const [shortfalls, setShortfalls] = useState<Shortfall[]>([]);
  const [exemptions, setExemptions] = useState<Exemption[]>([]);
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.from('room').select('id, name').eq('centre_id', centre.id).order('name')
      .then(({ data }) => setRooms(data ?? []));
    sb.from('outdoor_requirement')
      .select('key, min_minutes, care_hours_min, age_months_min, regulation, note')
      .eq('jurisdiction_code', centre.jurisdiction_code)
      .order('min_minutes', { ascending: false })
      .then(({ data }) => setRequirements((data as Requirement[]) ?? []));
    sb.from('outdoor_day')
      .select('room_id, outdoor_date, minutes, periods, outside_now')
      .eq('centre_id', centre.id)
      .eq('outdoor_date', date)
      .then(({ data }) => setDays((data as RoomDay[]) ?? []));
    sb.from('outdoor_period')
      .select('id, room_id, started_at, ended_at, weather')
      .eq('centre_id', centre.id)
      .eq('outdoor_date', date)
      .order('started_at')
      .then(({ data }) => setPeriods((data as Period[]) ?? []));
    sb.rpc('outdoor_by_child', { p_centre: centre.id, p_date: date })
      .then(({ data }) => setChildren((data as ChildDay[]) ?? []));
    sb.from('outdoor_shortfall')
      .select('id, room_id, outdoor_date, reason, person:recorded_by(full_name)')
      .eq('centre_id', centre.id)
      .eq('outdoor_date', date)
      .then(({ data }) => setShortfalls((data as never) ?? []));
    sb.from('outdoor_exemption')
      .select('id, child_id, source, practitioner, instruction, starts_on, ends_on, child:child_id(full_name), parent:provided_by(full_name)')
      .eq('centre_id', centre.id)
      .is('ended_at', null)
      .then(({ data }) => setExemptions((data as never) ?? []));
  }, [centre.id, centre.jurisdiction_code, date]);

  useEffect(load, [load]);

  const fullDay = requirements.find((r) => r.key === 'full_day')?.min_minutes ?? 120;

  async function saveShortfall(roomId: string) {
    setNotice(null);
    const { error } = await getSupabase().rpc('record_outdoor_shortfall', {
      p_centre: centre.id,
      p_room: roomId,
      p_date: date,
      p_reason: reasons[roomId] ?? '',
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    if (!error) setReasons((r) => ({ ...r, [roomId]: '' }));
    setNotice(error ? error.message : 'Recorded — it is in the daily written record too.');
    load();
  }

  const shortRooms = rooms.filter((r) => {
    const d = days.find((x) => x.room_id === r.id);
    return (d?.minutes ?? 0) < fullDay && !shortfalls.some((s) => s.room_id === r.id);
  });

  return (
    <>
      <h1>Outdoor play</h1>
      {notice ? <section className="card"><p>{notice}</p></section> : null}

      <section className="card">
        <h2>What the day owes (s. 47)</h2>
        {requirements.map((r) => (
          <p key={r.key} className="muted" style={{ margin: '2px 0' }}>
            <strong>{duration(r.min_minutes)}</strong> — {r.note}{' '}
            <span className="caption">{r.regulation}</span>
          </p>
        ))}
        <p className="muted">
          These minutes are measured, not typed: the room device records when the group went out and
          when it came in. Nobody enters a number at the end of the day, which is why this page means
          something to an inspector.
        </p>
        <div style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap' }}>
          <label>
            Day
            <input type="date" value={date} max={today} onChange={(e) => setDate(e.target.value)} />
          </label>
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
        </div>
      </section>

      <section className="card">
        <h2>By room — {fmtDate(date)}</h2>
        <table>
          <thead>
            <tr>
              <th>Room</th>
              <th>Outside</th>
              <th>Blocks</th>
              <th>Weather</th>
              <th>Against {duration(fullDay)}</th>
            </tr>
          </thead>
          <tbody>
            {rooms.map((r) => {
              const d = days.find((x) => x.room_id === r.id);
              const mins = d?.minutes ?? 0;
              const blocks = periods.filter((p) => p.room_id === r.id);
              const short = shortfalls.find((s) => s.room_id === r.id);
              return (
                <tr key={r.id}>
                  <td>{r.name}</td>
                  <td>
                    <strong>{duration(mins)}</strong>
                    {d?.outside_now ? <> <span className="pill ok">Outside now</span></> : null}
                  </td>
                  <td className="caption">
                    {blocks.length === 0
                      ? '—'
                      : blocks
                          .map(
                            (b) =>
                              `${hhmm(b.started_at, centre.timezone)}–${b.ended_at ? hhmm(b.ended_at, centre.timezone) : 'now'}`,
                          )
                          .join(', ')}
                  </td>
                  <td className="caption">
                    {blocks
                      .map((b) => (b.weather ? WEATHER[b.weather] : null))
                      .filter(Boolean)
                      .join(', ') || '—'}
                  </td>
                  <td className="wrap">
                    {mins >= fullDay ? (
                      <span className="pill ok">Met</span>
                    ) : short ? (
                      <>
                        <span className="pill ok">Reason recorded</span>{' '}
                        <span className="caption">{short.reason}</span>
                      </>
                    ) : (
                      <span className="pill due">Short by {duration(fullDay - mins)}</span>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </section>

      {shortRooms.length > 0 ? (
        <section className="card">
          <h2>Why the day was short</h2>
          <p className="muted">
            &quot;Weather permitting&quot; is a defence, and a defence only counts if it was written
            down. What you record here goes into the daily written record for the day (s. 37).
          </p>
          {shortRooms.map((r) => (
            <div key={r.id} style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap', marginTop: 6 }}>
              <label style={{ flex: 1, minWidth: 280 }}>
                {r.name}
                <input
                  value={reasons[r.id] ?? ''}
                  onChange={(e) => setReasons((x) => ({ ...x, [r.id]: e.target.value }))}
                  placeholder="Environment Canada extreme cold warning, wind chill −31"
                />
              </label>
              <button
                type="button"
                disabled={!(reasons[r.id] ?? '').trim()}
                onClick={() => void saveShortfall(r.id)}
              >
                Record
              </button>
            </div>
          ))}
        </section>
      ) : null}

      <section className="card">
        <h2>By child</h2>
        <p className="muted">
          The regulation is about each child, not each room. A child credited with less than the room
          got is a child who was not there for all of it.
        </p>
        <div style={{ overflowX: 'auto' }}>
          <table>
            <thead>
              <tr>
                <th>Child</th>
                <th>In care</th>
                <th>Day</th>
                <th>Outside</th>
                <th>Owed</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {children.map((c) => (
                <tr key={c.child_id}>
                  <td className="wrap">{c.full_name}</td>
                  <td className="caption">{Number(c.hours_in_care).toFixed(1)} h</td>
                  <td className="caption">
                    {Number(c.hours_expected) > Number(c.hours_in_care)
                      ? `${Number(c.hours_expected).toFixed(1)} h expected`
                      : 'gone home'}
                  </td>
                  <td>{duration(c.minutes_outside)}</td>
                  <td className="caption">
                    {c.required_minutes === 0 ? '—' : duration(c.required_minutes)}
                  </td>
                  <td className="wrap">
                    {c.exempt ? (
                      <>
                        <span className="pill ok">Kept in on instruction</span>{' '}
                        <span className="caption">{c.exemption_note}</span>
                      </>
                    ) : c.short_by > 0 ? (
                      <span className="pill due">Short by {duration(c.short_by)}</span>
                    ) : (
                      <span className="pill ok">Met</span>
                    )}
                  </td>
                </tr>
              ))}
              {children.length === 0 ? (
                <tr>
                  <td colSpan={6} className="muted">
                    No attendance recorded for this day.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </section>

      <ExemptionCard
        centreId={centre.id}
        personId={personId}
        exemptions={exemptions}
        onDone={(msg) => {
          setNotice(msg);
          load();
        }}
      />
    </>
  );
}

function ExemptionCard({
  centreId,
  personId,
  exemptions,
  onDone,
}: {
  centreId: string;
  personId: string;
  exemptions: Exemption[];
  onDone: (msg: string) => void;
}) {
  const [kids, setKids] = useState<{ id: string; full_name: string }[]>([]);
  const [childId, setChildId] = useState('');
  const [source, setSource] = useState('physician');
  const [practitioner, setPractitioner] = useState('');
  const [parents, setParents] = useState<{ person_id: string; full_name: string }[]>([]);
  const [parentId, setParentId] = useState('');
  const [instruction, setInstruction] = useState('');
  const [endsOn, setEndsOn] = useState('');
  const [pin, setPin] = useState('');

  useEffect(() => {
    getSupabase()
      .from('child')
      .select('id, full_name')
      .eq('centre_id', centreId)
      .is('discharge_date', null)
      .order('full_name')
      .then(({ data }) => setKids(data ?? []));
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
    const { error } = await getSupabase().rpc('record_outdoor_exemption', {
      p_centre: centreId,
      p_child: childId,
      p_source: source,
      p_instruction: instruction,
      p_practitioner: source === 'physician' ? practitioner : null,
      p_parent: source === 'parent' ? parentId : null,
      p_starts_on: null,
      p_ends_on: endsOn || null,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    if (!error) setInstruction('');
    onDone(error ? error.message : 'Written instruction recorded.');
  }

  return (
    <section className="card">
      <h2>Children kept indoors (s. 47)</h2>
      <p className="muted">
        A child stays in only on a physician&apos;s or a parent&apos;s written instruction. Staff cannot
        make that call on their own, and this is the record that it was not theirs to make.
      </p>
      {exemptions.map((e) => (
        <p key={e.id} style={{ margin: '4px 0' }}>
          <span className="pill ok">{e.source === 'physician' ? 'Physician' : 'Parent'}</span>{' '}
          <strong>{e.child?.full_name}</strong> — {e.instruction}{' '}
          <span className="caption">
            from {e.practitioner ?? e.parent?.full_name}, from {fmtDate(e.starts_on)}
            {e.ends_on ? ` to ${fmtDate(e.ends_on)}` : ''}
          </span>
        </p>
      ))}
      {exemptions.length === 0 ? <p className="muted">Nobody is being kept indoors.</p> : null}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
        <label>
          Child
          <select value={childId} onChange={(e) => setChildId(e.target.value)}>
            <option value="">Choose…</option>
            {kids.map((k) => (
              <option key={k.id} value={k.id}>
                {k.full_name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Instruction from
          <select value={source} onChange={(e) => setSource(e.target.value)}>
            <option value="physician">A physician</option>
            <option value="parent">A parent</option>
          </select>
        </label>
        {source === 'physician' ? (
          <label>
            Physician
            <input value={practitioner} onChange={(e) => setPractitioner(e.target.value)} placeholder="Dr. R. Mensah, MD" />
          </label>
        ) : (
          <label>
            Parent
            <select value={parentId} onChange={(e) => setParentId(e.target.value)}>
              {parents.map((p) => (
                <option key={p.person_id} value={p.person_id}>
                  {p.full_name}
                </option>
              ))}
            </select>
          </label>
        )}
        <label style={{ flex: 1, minWidth: 260 }}>
          What it says
          <input
            value={instruction}
            onChange={(e) => setInstruction(e.target.value)}
            placeholder="Indoors until the ear infection clears"
          />
        </label>
        <label>
          Until
          <input type="date" value={endsOn} onChange={(e) => setEndsOn(e.target.value)} />
        </label>
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
        <button type="button" disabled={!childId || !instruction.trim()} onClick={() => void submit()}>
          Record
        </button>
      </div>
    </section>
  );
}
