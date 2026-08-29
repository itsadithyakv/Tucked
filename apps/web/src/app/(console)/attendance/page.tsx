'use client';

/** s. 72(3): per age group, every child with actual arrival and departure
 * times or "absent". Times are captured at the event; late corrections are
 * NEW events carrying who/when/why — recorded here with the supervisor's PIN. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { downloadCsv, fmtTime, useConsole, zonedToUtc } from '@/lib/console';

interface Row {
  id: string;
  child_id: string;
  room_id: string | null;
  child: { full_name: string } | null;
  room: { name: string } | null;
  event_type: string;
  actual_time: string;
  recorded_by_person: { full_name: string } | null;
  correction_of: string | null;
  correction_reason: string | null;
}

export default function AttendancePage() {
  const { centre, personId } = useConsole();
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [rows, setRows] = useState<Row[]>([]);
  const [correcting, setCorrecting] = useState<Row | null>(null);
  const [newTime, setNewTime] = useState('');
  const [reason, setReason] = useState('');
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(() => {
    getSupabase()
      .from('attendance_event')
      .select(
        'id, child_id, room_id, event_type, actual_time, correction_of, correction_reason, child:child_id(full_name), room:room_id(name), recorded_by_person:recorded_by(full_name)',
      )
      .eq('centre_id', centre.id)
      .eq('attendance_date', date)
      .order('actual_time')
      .then(({ data }) => setRows((data as never) ?? []));
  }, [centre.id, date]);

  useEffect(load, [load]);

  async function submitCorrection() {
    if (!correcting || !newTime || !reason.trim() || !pin) return;
    setNotice(null);
    const { error } = await getSupabase().rpc('record_attendance', {
      p_centre: centre.id,
      p_child: correcting.child_id,
      p_event_type: correcting.event_type,
      p_room: correcting.room_id,
      p_actual_time: zonedToUtc(date, newTime, centre.timezone).toISOString(),
      p_recorder: personId,
      p_pin: pin,
      p_correction_of: correcting.id,
      p_correction_reason: reason.trim(),
    });
    if (error) setNotice(error.message);
    else {
      setCorrecting(null);
      setPin('');
      setReason('');
      load();
    }
  }

  return (
    <>
      <h1>Attendance</h1>
      <div className="toolbar">
        <label className="inline">
          Day
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </label>
        <button
          className="quiet"
          onClick={() =>
            downloadCsv(
              `attendance-${centre.licence_number}-${date}.csv`,
              ['Child', 'Room', 'Event', 'Actual time', 'Recorded by', 'Correction reason'],
              rows.map((r) => [
                r.child?.full_name,
                r.room?.name,
                r.event_type,
                fmtTime(r.actual_time, centre.timezone),
                r.recorded_by_person?.full_name,
                r.correction_of ? r.correction_reason : '',
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
      {correcting ? (
        <section className="card">
          <h2>
            Correct {correcting.event_type.replace('_', ' ')} — {correcting.child?.full_name}
          </h2>
          <p className="muted">
            The original stays on the record; the correction names who changed it, when, and why.
          </p>
          <div className="toolbar">
            <label className="inline">
              Corrected time
              <input type="time" value={newTime} onChange={(e) => setNewTime(e.target.value)} />
            </label>
            <label className="inline">
              Why
              <input
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder="e.g. arrival recorded late during a busy drop-off"
                size={40}
              />
            </label>
            <label className="inline">
              Staff PIN
              <input
                type="password"
                inputMode="numeric"
                maxLength={6}
                value={pin}
                onChange={(e) => setPin(e.target.value)}
                autoComplete="off"
              />
            </label>
            <button onClick={() => void submitCorrection()}>Record correction</button>
            <button className="quiet" onClick={() => setCorrecting(null)}>
              Cancel
            </button>
          </div>
          {notice ? <p className="muted">{notice}</p> : null}
        </section>
      ) : null}
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
              <th></th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id}>
                <td>{r.child?.full_name}</td>
                <td>{r.room?.name ?? '—'}</td>
                <td>{r.event_type.replace('_', ' ')}</td>
                <td>{fmtTime(r.actual_time, centre.timezone)}</td>
                <td className="muted">{r.recorded_by_person?.full_name}</td>
                <td className="muted">{r.correction_of ? r.correction_reason : ''}</td>
                <td>
                  {r.event_type !== 'room_transfer' ? (
                    <button
                      className="quiet small"
                      onClick={() => {
                        setNewTime(
                          new Intl.DateTimeFormat('en-CA', {
                            hour: '2-digit',
                            minute: '2-digit',
                            hour12: false,
                            timeZone: centre.timezone,
                          }).format(new Date(r.actual_time)),
                        );
                        setReason('');
                        setCorrecting(r);
                      }}
                    >
                      Correct
                    </button>
                  ) : null}
                </td>
              </tr>
            ))}
            {rows.length === 0 ? (
              <tr>
                <td colSpan={7} className="muted">
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
