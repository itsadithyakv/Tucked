'use client';

/** s. 33.1: per-child timestamped direct visual checks — the printable sheet
 * a program advisor asks to see. */

import { useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { downloadCsv, fmtTime, useConsole } from '@/lib/console';

interface CheckRow {
  logged_at: string;
  payload: { breathing_ok?: boolean; position?: string };
  child: { full_name: string } | null;
  room: { name: string } | null;
  by: { full_name: string } | null;
}

export default function SleepChecksPage() {
  const { centre } = useConsole();
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [rows, setRows] = useState<CheckRow[]>([]);

  useEffect(() => {
    getSupabase()
      .from('care_log')
      .select('logged_at, payload, child:child_id(full_name), room:room_id(name), by:recorded_by(full_name)')
      .eq('centre_id', centre.id)
      .eq('log_type', 'sleep_check')
      .eq('log_date', date)
      .order('logged_at')
      .then(({ data }) => setRows((data as never) ?? []));
  }, [centre.id, date]);

  return (
    <>
      <h1>Sleep checks</h1>
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
              ['Time', 'Child', 'Room', 'Breathing OK', 'Position', 'By'],
              rows.map((r) => [
                fmtTime(r.logged_at, centre.timezone),
                r.child?.full_name,
                r.room?.name,
                r.payload.breathing_ok ? 'yes' : 'INTERVENTION',
                r.payload.position ?? '',
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
      <div className="card">
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
                  {r.payload.position ? <span className="caption">on {r.payload.position}</span> : null}
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
      </div>
      <p className="caption">
        Direct visual checks apply to every sleeping child under 24 months in infant, toddler and
        family rooms. Electronic monitors never replace them.
      </p>
    </>
  );
}
