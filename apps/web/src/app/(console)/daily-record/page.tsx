'use client';

/** s. 37: the daily written record — review the auto-draft, write the final
 * entry, close as a named human with a PIN. Closed records are immutable. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, fmtTime, useConsole } from '@/lib/console';

interface Dwr {
  id: string;
  record_date: string;
  draft_text: string;
  final_text: string | null;
  closed_at: string | null;
  closed_by_person: { full_name: string } | null;
  refs: { type: string; note?: string }[];
}

export default function DailyRecordPage() {
  const { centre, personId } = useConsole();
  const [records, setRecords] = useState<Dwr[]>([]);
  const [finalText, setFinalText] = useState('');
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(() => {
    getSupabase()
      .from('daily_written_record')
      .select('id, record_date, draft_text, final_text, closed_at, refs, closed_by_person:closed_by(full_name)')
      .eq('centre_id', centre.id)
      .order('record_date', { ascending: false })
      .limit(30)
      .then(({ data }) => {
        const rows = (data as never as Dwr[]) ?? [];
        setRecords(rows);
        const open = rows.find((r) => !r.closed_at);
        if (open) setFinalText((cur) => cur || open.draft_text);
      });
  }, [centre.id]);

  useEffect(load, [load]);

  async function closeRecord(id: string) {
    setNotice(null);
    const { error } = await getSupabase().rpc('close_daily_record', {
      p_record: id,
      p_final_text: finalText,
      p_recorder: personId,
      p_pin: pin,
    });
    if (error) setNotice(error.message);
    else {
      setPin('');
      setNotice('Record closed.');
      load();
    }
  }

  return (
    <>
      <h1>Daily written record</h1>
      {records
        .filter((r) => !r.closed_at)
        .map((r) => (
          <section className="card" key={r.id}>
            <h2>
              {fmtDate(r.record_date)} <span className="pill due">Open</span>
            </h2>
            {r.refs.length > 0 ? (
              <p className="muted">
                Cross-references: {r.refs.map((ref) => ref.note ?? ref.type).join(' · ')}
              </p>
            ) : null}
            <label>
              Today&apos;s entry (drafted from the day&apos;s logs — confirm or edit)
              <textarea value={finalText} onChange={(e) => setFinalText(e.target.value)} rows={5} />
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
            <button onClick={() => closeRecord(r.id)}>Close today&apos;s record</button>
            {notice ? <p className="muted">{notice}</p> : null}
          </section>
        ))}
      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Date</th>
              <th>Entry</th>
              <th>Closed by</th>
              <th>Closed at</th>
            </tr>
          </thead>
          <tbody>
            {records
              .filter((r) => r.closed_at)
              .map((r) => (
                <tr key={r.id}>
                  <td>{fmtDate(r.record_date)}</td>
                  <td className="wrap">{r.final_text}</td>
                  <td>{r.closed_by_person?.full_name}</td>
                  <td>{fmtTime(r.closed_at, centre.timezone)}</td>
                </tr>
              ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
