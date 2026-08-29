'use client';

/** s. 36(4): the accident register with delivery evidence — who acknowledged,
 * and when. Unacknowledged reports stand out. */

import { useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { downloadCsv, fmtDate, fmtTime, useConsole } from '@/lib/console';

interface Report {
  id: string;
  occurred_at: string;
  occurred_date: string;
  location: string;
  description: string;
  injury: string;
  severity: string;
  first_aid: string;
  head_injury: boolean;
  concussion_watch_note: string | null;
  child: { full_name: string } | null;
  completed_by_person: { full_name: string } | null;
  ack_person: { full_name: string } | null;
  parent_ack_at: string | null;
}

export default function AccidentsPage() {
  const { centre } = useConsole();
  const [reports, setReports] = useState<Report[]>([]);

  useEffect(() => {
    getSupabase()
      .from('accident_report')
      .select(
        'id, occurred_at, occurred_date, location, description, injury, severity, first_aid, head_injury, concussion_watch_note, parent_ack_at, child:child_id(full_name), completed_by_person:completed_by(full_name), ack_person:parent_ack_person_id(full_name)',
      )
      .eq('centre_id', centre.id)
      .order('occurred_at', { ascending: false })
      .limit(50)
      .then(({ data }) => setReports((data as never) ?? []));
  }, [centre.id]);

  return (
    <>
      <h1>Accident reports</h1>
      <div className="toolbar">
        <button
          className="quiet"
          onClick={() =>
            downloadCsv(
              `accident-reports-${centre.licence_number}.csv`,
              ['Date', 'Time', 'Child', 'Location', 'What happened', 'Injury', 'Severity', 'First aid', 'Head injury', 'Completed by', 'Acknowledged by', 'Acknowledged at'],
              reports.map((r) => [
                fmtDate(r.occurred_date),
                fmtTime(r.occurred_at, centre.timezone),
                r.child?.full_name,
                r.location,
                r.description,
                r.injury,
                r.severity.replace('_', ' '),
                r.first_aid,
                r.head_injury ? 'yes' : 'no',
                r.completed_by_person?.full_name,
                r.ack_person?.full_name ?? 'NOT ACKNOWLEDGED',
                r.parent_ack_at ? `${fmtDate(r.parent_ack_at)} ${fmtTime(r.parent_ack_at, centre.timezone)}` : '',
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
      {reports.map((r) => (
        <section className="card" key={r.id}>
          <h2>
            {r.child?.full_name} — {fmtDate(r.occurred_date)}, {fmtTime(r.occurred_at, centre.timezone)}
            {r.head_injury ? <span className="pill now">Head injury</span> : null}
          </h2>
          <p>
            <strong>{r.location}.</strong> {r.description}
          </p>
          <p className="muted">
            Injury: {r.injury} ({r.severity.replace('_', ' ')}). First aid: {r.first_aid}.
          </p>
          {r.concussion_watch_note ? <p className="muted">Concussion watch: {r.concussion_watch_note}</p> : null}
          <p className="caption">Completed by {r.completed_by_person?.full_name}</p>
          {r.parent_ack_at ? (
            <p>
              <span className="pill ok">Delivered</span> Acknowledged by {r.ack_person?.full_name},{' '}
              {fmtDate(r.parent_ack_at)} {fmtTime(r.parent_ack_at, centre.timezone)}
            </p>
          ) : (
            <p>
              <span className="pill due">Awaiting acknowledgement</span> The family has not yet confirmed receipt.
            </p>
          )}
        </section>
      ))}
      {reports.length === 0 ? <p className="muted">No accident reports on file.</p> : null}
    </>
  );
}
