'use client';

/** Photos: the day's photos as the rooms took them, who is in each, and the
 * one action a supervisor needs — taking a photo down, with the reason.
 *
 * Consent is not re-implemented here. record_photo refused every child whose
 * family had not agreed, and the storage policy decides, per viewer, who may
 * open each file; this screen shows the centre's own view of the record. */

import { useCallback, useEffect, useState } from 'react';
import { addDaysISO, localDateISO } from '@tucked/domain';
import { getSupabase } from '@/lib/supabase';
import { fmtTime, useConsole } from '@/lib/console';

interface PhotoRow {
  id: string;
  storage_path: string;
  captured_at: string;
  caption: string | null;
  withdrawn_at: string | null;
  withdrawn_reason: string | null;
  by: { full_name: string } | null;
  subjects: { child: { full_name: string } | null }[];
}

export default function PhotosPage() {
  const { centre, personId } = useConsole();
  const [date, setDate] = useState(() => localDateISO(centre.timezone));
  const [rows, setRows] = useState<PhotoRow[]>([]);
  const [urls, setUrls] = useState<Map<string, string>>(new Map());
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(async () => {
    const sb = getSupabase();
    // a UTC window a day either side, then the centre-local day on this side —
    // the day a photo belongs to is the centre's, not UTC's
    const { data } = await sb
      .from('photo')
      .select(
        'id, storage_path, captured_at, caption, withdrawn_at, withdrawn_reason, by:uploaded_by(full_name), subjects:photo_subject(child:child_id(full_name))',
      )
      .eq('centre_id', centre.id)
      .gte('captured_at', `${addDaysISO(date, -1)}T00:00:00Z`)
      .lt('captured_at', `${addDaysISO(date, 2)}T00:00:00Z`)
      .order('captured_at');
    const day = ((data as never as PhotoRow[]) ?? []).filter(
      (p) => localDateISO(centre.timezone, new Date(p.captured_at)) === date,
    );
    setRows(day);
    const live = day.filter((p) => !p.withdrawn_at).map((p) => p.storage_path);
    if (live.length === 0) {
      setUrls(new Map());
      return;
    }
    const { data: signed } = await sb.storage.from('photos').createSignedUrls(live, 600);
    const next = new Map<string, string>();
    for (const s of signed ?? []) {
      // a path the storage policy refused comes back with no URL
      if (s.path && s.signedUrl) next.set(s.path, s.signedUrl);
    }
    setUrls(next);
  }, [centre.id, centre.timezone, date]);

  useEffect(() => {
    void load();
  }, [load]);

  async function takeDown(photo: PhotoRow) {
    const { error } = await getSupabase().rpc('withdraw_photo', {
      p_photo: photo.id,
      p_reason: reasons[photo.id] ?? '',
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    setNotice(error ? error.message : 'Photo taken down. No family can open it now.');
    if (!error) void load();
  }

  const live = rows.filter((p) => !p.withdrawn_at);

  return (
    <>
      <h1>Photos</h1>
      <div className="toolbar">
        <label className="inline">
          Day
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </label>
        <label className="inline">
          Staff PIN
          <input
            type="password"
            inputMode="numeric"
            maxLength={6}
            autoComplete="off"
            value={pin}
            onChange={(e) => setPin(e.target.value)}
          />
        </label>
      </div>

      {notice ? <p className="muted">{notice}</p> : null}

      <section className="card">
        <p className="muted">
          A photo only ever reaches families who are allowed to see it: a child whose family has not
          agreed to photos cannot be tagged, and a group photo disappears from other families&apos;
          galleries the moment any family in it withdraws consent. Taking a photo down hides it from
          every family and keeps the reason.
        </p>
        <p className="caption">
          {live.length === 0
            ? 'No photos taken on this day.'
            : `${live.length} photo${live.length === 1 ? '' : 's'} on this day${rows.length > live.length ? `, ${rows.length - live.length} taken down` : ''}.`}
        </p>
      </section>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: 12 }}>
        {rows.map((p) => {
          const names = p.subjects.map((s) => s.child?.full_name).filter(Boolean).join(', ');
          return (
            <section key={p.id} className="card">
              {p.withdrawn_at ? (
                <p>
                  <span className="pill due">Taken down</span> {p.withdrawn_reason}
                </p>
              ) : urls.has(p.storage_path) ? (
                /* A plain img, not next/image: the optimizer would fetch and cache
                   a private photo of a child on the server. Signed URLs expire in
                   ten minutes and are fetched by this browser only. */
                <img
                  src={urls.get(p.storage_path)}
                  alt={p.caption ?? `Photo of ${names}`}
                  style={{ width: '100%', aspectRatio: '4 / 3', objectFit: 'cover', borderRadius: 16 }}
                />
              ) : (
                <p className="muted">The file could not be opened.</p>
              )}
              <p style={{ margin: 0 }}>
                <strong>{names || 'Nobody tagged'}</strong>
              </p>
              <p className="caption" style={{ margin: 0 }}>
                {fmtTime(p.captured_at, centre.timezone)} · {p.by?.full_name ?? '—'}
                {p.caption ? ` · ${p.caption}` : ''}
              </p>
              {p.withdrawn_at ? null : (
                <div style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap' }}>
                  <label style={{ flex: 1, minWidth: 160 }}>
                    Why it is coming down
                    <input
                      value={reasons[p.id] ?? ''}
                      onChange={(e) => setReasons((r) => ({ ...r, [p.id]: e.target.value }))}
                      placeholder="Wrong child tagged"
                    />
                  </label>
                  <button
                    type="button"
                    className="quiet"
                    disabled={!(reasons[p.id] ?? '').trim() || pin.length < 4}
                    onClick={() => void takeDown(p)}
                  >
                    Take down
                  </button>
                </div>
              )}
            </section>
          );
        })}
      </div>
    </>
  );
}
