'use client';

/** s. 33.1 sleep: the per-child timestamped direct visual checks a program
 * advisor asks to see, the written directions that vary back-to-sleep, and the
 * two findings a sleeping room produces.
 *
 * The distinction this screen exists to make visible: PLACING a child is an act
 * the database can refuse, and FINDING a child somewhere is an observation it
 * never refuses. So nothing here is an error message — a finding is a fact that
 * has already been written down, surfaced so a supervisor meets it before an
 * inspector does. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { downloadCsv, fmtDate, fmtTime, useConsole } from '@/lib/console';

interface CheckRow {
  logged_at: string;
  payload: { breathing_ok?: boolean; position?: string; repositioned?: boolean };
  child: { full_name: string } | null;
  room: { name: string } | null;
  by: { full_name: string } | null;
}

interface PositionFinding {
  care_log_id: string;
  full_name: string;
  logged_at: string;
  found_position: string;
  repositioned: boolean;
}

interface LongRest {
  child_id: string;
  full_name: string;
  started_at: string;
  ended_at: string;
  minutes: number;
}

interface Direction {
  id: string;
  child_id: string;
  source: string;
  kind: string;
  permitted_positions: string[] | null;
  practitioner: string | null;
  instruction: string;
  starts_on: string;
  ends_on: string | null;
  child: { full_name: string } | null;
  parent: { full_name: string } | null;
}

export default function SleepChecksPage() {
  const { centre, personId } = useConsole();
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [rows, setRows] = useState<CheckRow[]>([]);
  const [positionFindings, setPositionFindings] = useState<PositionFinding[]>([]);
  const [longRests, setLongRests] = useState<LongRest[]>([]);
  const [directions, setDirections] = useState<Direction[]>([]);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.from('care_log')
      .select(
        'logged_at, payload, child:child_id(full_name), room:room_id(name), by:recorded_by(full_name)',
      )
      .eq('centre_id', centre.id)
      .eq('log_type', 'sleep_check')
      .eq('log_date', date)
      .order('logged_at')
      .then(({ data }) => setRows((data as never) ?? []));

    sb.from('sleep_position_finding')
      .select('care_log_id, full_name, logged_at, found_position, repositioned')
      .eq('centre_id', centre.id)
      .eq('log_date', date)
      .order('logged_at')
      .then(({ data }) => setPositionFindings((data as never) ?? []));

    sb.from('long_rest_finding')
      .select('child_id, full_name, started_at, ended_at, minutes')
      .eq('centre_id', centre.id)
      .eq('log_date', date)
      .order('minutes', { ascending: false })
      .then(({ data }) => setLongRests((data as never) ?? []));

    sb.from('sleep_direction')
      .select(
        'id, child_id, source, kind, permitted_positions, practitioner, instruction, starts_on, ends_on, child:child_id(full_name), parent:provided_by(full_name)',
      )
      .eq('centre_id', centre.id)
      .is('ended_at', null)
      .order('starts_on', { ascending: false })
      .then(({ data }) => setDirections((data as never) ?? []));
  }, [centre.id, date]);

  useEffect(load, [load]);

  return (
    <>
      <h1>Sleep</h1>
      <div className="toolbar">
        <label className="inline">
          Day
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </label>
        <button
          className="quiet"
          onClick={() =>
            downloadCsv(
              `sleep-checks-${centre.licence_number}-${date}.csv`,
              ['Time', 'Child', 'Room', 'Breathing OK', 'Position', 'Repositioned', 'By'],
              rows.map((r) => [
                fmtTime(r.logged_at, centre.timezone),
                r.child?.full_name,
                r.room?.name,
                r.payload.breathing_ok ? 'yes' : 'INTERVENTION',
                r.payload.position ?? '',
                r.payload.repositioned === undefined ? '' : r.payload.repositioned ? 'yes' : 'no',
                r.by?.full_name,
              ]),
            )
          }
        >
          Download CSV
        </button>
        <button className="quiet" onClick={() => window.print()}>
          Print / save PDF
        </button>
      </div>

      {notice ? <p className="muted">{notice}</p> : null}

      {positionFindings.length > 0 || longRests.length > 0 ? (
        <section className="card">
          <h2>What the day is owed</h2>
          <p className="muted">
            Both of these are already in the day&apos;s written record. Nothing here needs undoing —
            it needs reading.
          </p>
          {positionFindings.map((f) => (
            <p key={f.care_log_id} style={{ margin: '4px 0' }}>
              <span className="pill now">Off their back</span> <strong>{f.full_name}</strong> was
              found on their {f.found_position} at{' '}
              {fmtTime(f.logged_at, centre.timezone)} — under 12 months, with no physician&apos;s
              direction on file.{' '}
              <span className="caption">
                {f.repositioned
                  ? 'Placed back.'
                  : 'The record does not say whether they were repositioned.'}
              </span>
            </p>
          ))}
          {longRests.map((r) => (
            <p key={`${r.child_id}-${r.started_at}`} style={{ margin: '4px 0' }}>
              <span className="pill due">Rest over two hours</span> <strong>{r.full_name}</strong>{' '}
              rested {r.minutes} minutes, {fmtTime(r.started_at, centre.timezone)} to{' '}
              {fmtTime(r.ended_at, centre.timezone)}.{' '}
              <span className="caption">s. 33.1 sets the rest period at no longer than two hours.</span>
            </p>
          ))}
        </section>
      ) : null}

      <section className="card">
        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Child</th>
              <th>Room</th>
              <th>Check</th>
              <th>By</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr key={i}>
                <td>{fmtTime(r.logged_at, centre.timezone)}</td>
                <td>{r.child?.full_name}</td>
                <td>{r.room?.name}</td>
                <td>
                  {r.payload.breathing_ok ? (
                    <span className="pill ok">Breathing OK</span>
                  ) : (
                    <span className="pill now">Intervention</span>
                  )}{' '}
                  {r.payload.position ? (
                    <span className="caption">
                      on {r.payload.position}
                      {r.payload.repositioned ? ', placed back' : ''}
                    </span>
                  ) : null}
                </td>
                <td className="muted">{r.by?.full_name}</td>
              </tr>
            ))}
            {rows.length === 0 ? (
              <tr>
                <td colSpan={5} className="muted">
                  No sleep checks recorded for this day.
                </td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </section>

      <DirectionsCard
        centreId={centre.id}
        personId={personId}
        directions={directions}
        onDone={(msg) => {
          setNotice(msg);
          load();
        }}
      />

      <p className="caption">
        Direct visual checks apply to every sleeping child under 24 months in infant, toddler and
        family rooms. Electronic monitors never replace them. A child under 12 months is placed on
        their back unless their physician has recommended otherwise in writing — the app will not
        record any other placement without that direction on file.
      </p>
    </>
  );
}

const POSITIONS = ['side', 'front'] as const;

function DirectionsCard({
  centreId,
  personId,
  directions,
  onDone,
}: {
  centreId: string;
  personId: string;
  directions: Direction[];
  onDone: (message: string) => void;
}) {
  const [kids, setKids] = useState<{ id: string; full_name: string }[]>([]);
  const [parents, setParents] = useState<{ person_id: string; full_name: string }[]>([]);
  const [childId, setChildId] = useState('');
  const [kind, setKind] = useState<'position' | 'rest'>('position');
  const [positions, setPositions] = useState<string[]>(['side']);
  const [practitioner, setPractitioner] = useState('');
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
      .then(({ data }) => setKids((data as never) ?? []));
  }, [centreId]);

  useEffect(() => {
    if (!childId) {
      setParents([]);
      return;
    }
    getSupabase()
      .from('child_household')
      .select(
        'household:household_id(household_member(person_id, can_consent, revoked_at, person:person_id(full_name)))',
      )
      .eq('child_id', childId)
      .then(({ data }) => {
        const rows = (
          (data as never as {
            household: {
              household_member: {
                person_id: string;
                can_consent: boolean;
                revoked_at: string | null;
                person: { full_name: string } | null;
              }[];
            } | null;
          }[]) ?? []
        )
          .flatMap((r) => r.household?.household_member ?? [])
          .filter((m) => m.can_consent && !m.revoked_at && m.person)
          .map((m) => ({ person_id: m.person_id, full_name: m.person!.full_name }));
        setParents(rows);
        setParentId(rows[0]?.person_id ?? '');
      });
  }, [childId]);

  async function submit() {
    const { error } = await getSupabase().rpc('record_sleep_direction', {
      p_centre: centreId,
      p_child: childId,
      // Only a physician can vary a sleep position, so the source is not a
      // choice here: it follows from what is being recorded. The database
      // refuses the other combination anyway (see the check constraint on
      // sleep_direction) — this just declines to offer it.
      p_source: kind === 'position' ? 'physician' : 'parent',
      p_kind: kind,
      p_instruction: instruction,
      p_positions: kind === 'position' ? positions : null,
      p_practitioner: kind === 'position' ? practitioner : null,
      p_parent: kind === 'rest' ? parentId : null,
      p_starts_on: null,
      p_ends_on: endsOn || null,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    if (!error) setInstruction('');
    onDone(error ? error.message : 'Written direction recorded.');
  }

  const position = directions.filter((d) => d.kind === 'position');
  const rest = directions.filter((d) => d.kind === 'rest');

  return (
    <section className="card">
      <h2>Written sleep directions (s. 33.1)</h2>
      <p className="muted">
        A child under 12 months sleeps on their back. Only a physician can vary that, and only in
        writing. A family can ask for anything else about their child&apos;s rest, and the centre
        should hear it — but a family cannot authorise a position, so the app does not offer it.
      </p>

      {position.map((d) => (
        <p key={d.id} style={{ margin: '4px 0' }}>
          <span className="pill ok">Physician</span> <strong>{d.child?.full_name}</strong> may be
          placed on their {(d.permitted_positions ?? []).join(' or ')} — {d.instruction}{' '}
          <span className="caption">
            from {d.practitioner}, from {fmtDate(d.starts_on)}
            {d.ends_on ? ` to ${fmtDate(d.ends_on)}` : ''}
          </span>
        </p>
      ))}
      {rest.map((d) => (
        <p key={d.id} style={{ margin: '4px 0' }}>
          <span className="pill">Family</span> <strong>{d.child?.full_name}</strong> — {d.instruction}{' '}
          <span className="caption">
            from {d.parent?.full_name}, from {fmtDate(d.starts_on)}
            {d.ends_on ? ` to ${fmtDate(d.ends_on)}` : ''}
          </span>
        </p>
      ))}
      {directions.length === 0 ? (
        <p className="muted">Nothing on file. Every child sleeps on their back.</p>
      ) : null}

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
          This is
          <select value={kind} onChange={(e) => setKind(e.target.value as 'position' | 'rest')}>
            <option value="position">A physician&apos;s sleep position direction</option>
            <option value="rest">A family&apos;s request about rest</option>
          </select>
        </label>
        {kind === 'position' ? (
          <>
            <label>
              Physician
              <input
                value={practitioner}
                onChange={(e) => setPractitioner(e.target.value)}
                placeholder="Dr. R. Mensah, MD"
              />
            </label>
            <label>
              Also permitted
              <select
                value={positions[0] ?? 'side'}
                onChange={(e) => setPositions([e.target.value])}
              >
                {POSITIONS.map((p) => (
                  <option key={p} value={p}>
                    On their {p}
                  </option>
                ))}
              </select>
            </label>
          </>
        ) : (
          <label>
            Asked by
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
            placeholder={
              kind === 'position'
                ? 'Side-lying permitted for reflux; back at all other times'
                : 'Please wake her by 2:30'
            }
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
        <button
          type="button"
          disabled={
            !childId ||
            !instruction.trim() ||
            (kind === 'position' ? !practitioner.trim() : !parentId)
          }
          onClick={() => void submit()}
        >
          Record
        </button>
      </div>
    </section>
  );
}
