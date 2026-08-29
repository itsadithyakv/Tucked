'use client';

/** s. 72(3): per age group, every child with actual arrival and departure
 * times or "absent" — the record the program advisor asks for first. */

import { useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtTime, useConsole } from '@/lib/console';

interface Row {
  child_id: string;
  child: { full_name: string } | null;
  room: { name: string } | null;
  event_type: string;
  actual_time: string;
  recorded_by_person: { full_name: string } | null;
  correction_of: string | null;
  correction_reason: string | null;
}

export default function AttendancePage() {
  const { centre } = useConsole();
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [rows, setRows] = useState<Row[]>([]);

  useEffect(() => {
    getSupabase()
      .from('attendance_event')
      .select(
        'child_id, event_type, actual_time, correction_of, correction_reason, child:child_id(full_name), room:room_id(name), recorded_by_person:recorded_by(full_name)',
      )
      .eq('centre_id', centre.id)
      .eq('attendance_date', date)
      .order('actual_time')
      .then(({ data }) => setRows((data as never) ?? []));
  }, [centre.id, date]);

  function downloadCsv() {
    const esc = (v: string) => `"${v.replace(/"/g, '""')}"`;
    const lines = [
      ['Child', 'Room', 'Event', 'Actual time', 'Recorded by', 'Correction reason'].join(','),
      ...rows.map((r) =>
        [
          esc(r.child?.full_name ?? ''),
          esc(r.room?.name ?? ''),
          esc(r.event_type),
          esc(fmtTime(r.actual_time, centre.timezone)),
          esc(r.recorded_by_person?.full_name ?? ''),
          esc(r.correction_of ? (r.correction_reason ?? '') : ''),
        ].join(','),
      ),
    ];
    const blob = new Blob([lines.join('\n')], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `attendance-${centre.licence_number}-${date}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  }

  return (
    <>
      <h1>Attendance</h1>
      <div className="toolbar">
        <label className="inline">
          Day
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </label>
        <button className="quiet" onClick={downloadCsv}>
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
              <th>Child</th>
              <th>Room</th>
              <th>Event</th>
              <th>Actual time</th>
              <th>Recorded by</th>
              <th>Correction</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr key={i}>
                <td>{r.child?.full_name}</td>
                <td>{r.room?.name ?? '—'}</td>
                <td>{r.event_type.replace('_', ' ')}</td>
                <td>{fmtTime(r.actual_time, centre.timezone)}</td>
                <td className="muted">{r.recorded_by_person?.full_name}</td>
                <td className="muted">{r.correction_of ? r.correction_reason : ''}</td>
              </tr>
            ))}
            {rows.length === 0 ? (
              <tr>
                <td colSpan={6} className="muted">
                  No attendance recorded for this day.
                </td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </div>
    </>
  );
}
