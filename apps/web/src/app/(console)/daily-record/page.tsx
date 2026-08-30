'use client';

/** s. 37: the daily written record. The draft is composed from the day's own
 * records — attendance, outdoor minutes, menu substitutions, sleep checks,
 * medication, headcounts, and every incident quoted in the words the trigger
 * wrote at the time. Deterministic, never generated (§9.14). The supervisor
 * reads it, edits it if they want to, and closes it as a named human. */

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
  const [preview, setPreview] = useState<string | null>(null);
  const [touched, setTouched] = useState(false);
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
        if (open) {
          setFinalText((cur) => cur || open.draft_text);
          // what the day reads like RIGHT NOW, without touching what is stored
          void getSupabase()
            .rpc('daily_record_preview', { p_centre: centre.id, p_date: open.record_date })
            .then(({ data }) => setPreview((data as string | null) ?? null));
        }
      });
  }, [centre.id]);

  useEffect(load, [load]);

  async function regenerate(id: string) {
    setNotice(null);
    const { error } = await getSupabase().rpc('regenerate_daily_record_draft', {
      p_record: id,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    if (error) {
      setNotice(error.message);
      return;
    }
    if (preview) setFinalText(preview);
    setTouched(false);
    setNotice('Redrafted from the day as it stands now.');
    load();
  }

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
            <p className="muted">
              Drafted from the day&apos;s own records. Read it, change anything that needs changing,
              and close it — your words are what gets kept.
            </p>
            {preview && preview !== finalText ? (
              <p>
                <span className="pill due">Moved on</span> The day has changed since this draft was
                written.{' '}
                {touched
                  ? 'Redrafting will replace what you have typed.'
                  : 'Redraft to pick up what has happened since.'}
              </p>
            ) : null}
            <label>
              Today&apos;s entry
              <textarea
                value={finalText}
                onChange={(e) => {
                  setFinalText(e.target.value);
                  setTouched(true);
                }}
                rows={16}
                style={{ fontFamily: 'inherit' }}
              />
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
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              <button onClick={() => closeRecord(r.id)}>Close today&apos;s record</button>
              <button type="button" className="quiet" onClick={() => void regenerate(r.id)}>
                Redraft from the day
              </button>
            </div>
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
                  <td className="wrap" style={{ whiteSpace: 'pre-wrap' }}>{r.final_text}</td>
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
