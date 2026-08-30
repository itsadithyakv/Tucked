'use client';

/** ss. 53–64: the staff file. Its value to a licensee is not the tidy list of
 * things that happen to be there — it is the list of things that are NOT. The
 * requirements come from a rule pack keyed by jurisdiction and role, so a
 * volunteer is asked for a police check and a health assessment but never for
 * first aid, and the page can say plainly what is missing before a program
 * advisor has to. Evidence lives in a private bucket readable only by the
 * person it is about and by centre leadership. */

import { useCallback, useEffect, useRef, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

interface Gap {
  person_id: string;
  full_name: string;
  role: string;
  requirement_key: string;
  requirement_label: string;
  regulation: string;
  note: string;
  state: string;
  expires_on: string | null;
  has_document: boolean;
}

interface Cred {
  id: string;
  person_id: string;
  credential_type: string;
  issued_on: string | null;
  expires_on: string | null;
  checked_on: string | null;
  police_service: string | null;
  declaration_year: number | null;
  notes: string | null;
  superseded_at: string | null;
}

interface Doc {
  id: string;
  person_id: string;
  credential_id: string | null;
  storage_path: string;
  file_name: string;
  content_type: string;
  size_bytes: number | null;
  uploaded_at: string;
  superseded_at: string | null;
}

interface DeclarationGap {
  person_id: string;
  full_name: string;
  missing_year: number;
}

const CRED_LABELS: Record<string, string> = {
  rece_registration: 'RECE registration',
  first_aid_cpr: 'First aid & infant/child CPR',
  vsc: 'Vulnerable sector check',
  offence_declaration: 'Offence declaration',
  health_assessment: 'Health assessment',
  immunisation: 'Immunisation',
  training: 'Training',
};

const STATE: Record<string, { label: string; cls: string }> = {
  current: { label: 'Current', cls: 'ok' },
  on_file: { label: 'On file', cls: 'ok' },
  expiring_soon: { label: 'Expiring soon', cls: 'due' },
  expired: { label: 'Expired', cls: 'now' },
  missing: { label: 'Missing', cls: 'now' },
};

export default function StaffPage() {
  const { centre, personId } = useConsole();
  const [gaps, setGaps] = useState<Gap[]>([]);
  const [creds, setCreds] = useState<Cred[]>([]);
  const [docs, setDocs] = useState<Doc[]>([]);
  const [declGaps, setDeclGaps] = useState<DeclarationGap[]>([]);
  const [open, setOpen] = useState<string | null>(null);
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.rpc('staff_file_gaps', { p_centre: centre.id }).then(({ data }) =>
      setGaps((data as Gap[]) ?? []),
    );
    sb.rpc('offence_declaration_gaps', { p_centre: centre.id }).then(({ data }) =>
      setDeclGaps((data as DeclarationGap[]) ?? []),
    );
    sb.from('credential')
      .select('id, person_id, credential_type, issued_on, expires_on, checked_on, police_service, declaration_year, notes, superseded_at')
      .eq('centre_id', centre.id)
      .order('issued_on', { ascending: false })
      .then(({ data }) => setCreds((data as Cred[]) ?? []));
    sb.from('staff_document')
      .select('id, person_id, credential_id, storage_path, file_name, content_type, size_bytes, uploaded_at, superseded_at')
      .eq('centre_id', centre.id)
      .then(({ data }) => setDocs((data as Doc[]) ?? []));
  }, [centre.id]);

  useEffect(load, [load]);

  const people = Array.from(new Map(gaps.map((g) => [g.person_id, g])).values());
  const missing = gaps.filter((g) => g.state === 'missing' || g.state === 'expired');

  async function openDocument(path: string) {
    const { data, error } = await getSupabase().storage.from('evidence').createSignedUrl(path, 60);
    if (error || !data) {
      setNotice(error?.message ?? 'Could not open that file.');
      return;
    }
    window.open(data.signedUrl, '_blank', 'noopener');
  }

  return (
    <>
      <h1>Staff files</h1>
      {notice ? <section className="card"><p>{notice}</p></section> : null}

      <section className="card">
        <h2>What is missing</h2>
        <p className="muted">
          Every requirement that applies to each person&apos;s role, and whether it is on file. A
          volunteer is asked for a police check and a health assessment, never for first aid, because a
          volunteer is never counted in ratio.
        </p>
        {missing.length === 0 ? (
          <p className="muted">Every required document is on file and current.</p>
        ) : (
          <p>
            <span className="pill now">{missing.length}</span> requirement
            {missing.length === 1 ? '' : 's'} missing or expired across {people.length} people.
          </p>
        )}
        {declGaps.length > 0 ? (
          <p>
            <span className="pill due">Due</span> {declGaps.length} offence declaration
            {declGaps.length === 1 ? '' : 's'} outstanding (s. 61 — one for every year without a
            vulnerable sector check):{' '}
            {declGaps.slice(0, 4).map((d) => `${d.full_name} ${d.missing_year}`).join(', ')}
            {declGaps.length > 4 ? ` and ${declGaps.length - 4} more` : ''}
          </p>
        ) : null}
        <label className="inline">
          Staff PIN (for the actions below)
          <input
            type="password"
            inputMode="numeric"
            value={pin}
            onChange={(e) => setPin(e.target.value)}
            maxLength={6}
            autoComplete="off"
          />
        </label>
      </section>

      {people.map((p) => {
        const rows = gaps.filter((g) => g.person_id === p.person_id);
        const worst = rows.some((r) => r.state === 'missing' || r.state === 'expired');
        const isOpen = open === p.person_id;
        return (
          <section className="card print-target" key={p.person_id}>
            <h2>
              {p.full_name}{' '}
              <span className="caption">{p.role.replace(/_/g, ' ')}</span>{' '}
              {worst ? (
                <span className="pill now">Incomplete</span>
              ) : (
                <span className="pill ok">Complete</span>
              )}
              <button
                className="quiet"
                style={{ marginLeft: 8 }}
                onClick={() => setOpen(isOpen ? null : p.person_id)}
              >
                {isOpen ? 'Close' : 'Open the file'}
              </button>
            </h2>
            {isOpen ? (
              <div className="print-area">
                <h3>{centre.name} — staff file for {p.full_name}</h3>
                <div style={{ overflowX: 'auto' }}>
                  <table>
                    <thead>
                      <tr>
                        <th>Requirement</th>
                        <th>State</th>
                        <th>Expires</th>
                        <th>Evidence</th>
                        <th>Regulation</th>
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((r) => {
                        const cred = creds.find(
                          (c) =>
                            c.person_id === p.person_id &&
                            c.superseded_at === null &&
                            c.credential_type ===
                              Object.keys(CRED_LABELS).find((k) => k === r.requirement_key),
                        );
                        const doc = docs.find(
                          (d) => d.credential_id === cred?.id && d.superseded_at === null,
                        );
                        const st = STATE[r.state] ?? { label: r.state, cls: 'due' };
                        return (
                          <tr key={r.requirement_key}>
                            <td className="wrap">
                              {r.requirement_label}
                              <div className="caption">{r.note}</div>
                            </td>
                            <td>
                              <span className={`pill ${st.cls}`}>{st.label}</span>
                            </td>
                            <td className="caption">
                              {r.expires_on ? fmtDate(r.expires_on) : '—'}
                            </td>
                            <td>
                              {doc ? (
                                <button className="quiet" onClick={() => void openDocument(doc.storage_path)}>
                                  {doc.file_name}
                                </button>
                              ) : cred ? (
                                <UploadButton
                                  centreId={centre.id}
                                  personId={p.person_id}
                                  credentialId={cred.id}
                                  recorderId={personId}
                                  pin={pin}
                                  busy={busy}
                                  setBusy={setBusy}
                                  onDone={(msg) => {
                                    setNotice(msg);
                                    setPin('');
                                    load();
                                  }}
                                />
                              ) : (
                                <span className="caption">record the date first</span>
                              )}
                            </td>
                            <td className="caption">{r.regulation}</td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
                <button type="button" className="quiet" onClick={() => window.print()}>
                  Print this staff file
                </button>
              </div>
            ) : (
              <p className="caption">
                {rows.filter((r) => r.state === 'missing').length} missing ·{' '}
                {rows.filter((r) => r.state === 'expired').length} expired ·{' '}
                {rows.filter((r) => r.state === 'expiring_soon').length} expiring soon
              </p>
            )}
            {isOpen ? (
              <CredentialForm
                centreId={centre.id}
                personId={p.person_id}
                recorderId={personId}
                pin={pin}
                onDone={(msg) => {
                  setNotice(msg);
                  setPin('');
                  load();
                }}
              />
            ) : null}
          </section>
        );
      })}
    </>
  );
}

function UploadButton({
  centreId,
  personId,
  credentialId,
  recorderId,
  pin,
  busy,
  setBusy,
  onDone,
}: {
  centreId: string;
  personId: string;
  credentialId: string;
  recorderId: string;
  pin: string;
  busy: boolean;
  setBusy: (b: boolean) => void;
  onDone: (msg: string) => void;
}) {
  const ref = useRef<HTMLInputElement>(null);

  async function upload(file: File) {
    if (file.size > 10 * 1024 * 1024) {
      onDone('That file is over 10 MB — scan it smaller, or split it.');
      return;
    }
    setBusy(true);
    const sb = getSupabase();
    const ext = file.name.includes('.') ? file.name.split('.').pop() : 'pdf';
    const path = `${centreId}/${personId}/${credentialId}.${ext}`;
    const { error: upErr } = await sb.storage
      .from('evidence')
      .upload(path, file, { upsert: false, contentType: file.type || 'application/pdf' });
    if (upErr) {
      setBusy(false);
      onDone(upErr.message);
      return;
    }
    const { error } = await sb.rpc('attach_staff_document', {
      p_centre: centreId,
      p_person: personId,
      p_credential: credentialId,
      p_kind: 'credential_evidence',
      p_storage_path: path,
      p_file_name: file.name,
      p_content_type: file.type || 'application/pdf',
      p_size_bytes: file.size,
      p_note: null,
      p_recorder: recorderId,
      p_pin: pin,
    });
    setBusy(false);
    onDone(error ? error.message : `${file.name} attached to the file.`);
  }

  return (
    <>
      <input
        ref={ref}
        type="file"
        accept="application/pdf,image/jpeg,image/png"
        style={{ display: 'none' }}
        onChange={(e) => {
          const file = e.target.files?.[0];
          if (file) void upload(file);
          e.target.value = '';
        }}
      />
      <button className="quiet" disabled={busy} onClick={() => ref.current?.click()}>
        {busy ? 'Uploading…' : 'Attach'}
      </button>
    </>
  );
}

function CredentialForm({
  centreId,
  personId,
  recorderId,
  pin,
  onDone,
}: {
  centreId: string;
  personId: string;
  recorderId: string;
  pin: string;
  onDone: (msg: string) => void;
}) {
  const [type, setType] = useState('vsc');
  const [issued, setIssued] = useState('');
  const [expires, setExpires] = useState('');
  const [checked, setChecked] = useState('');
  const [police, setPolice] = useState('');
  const [year, setYear] = useState(String(new Date().getFullYear()));
  const [notes, setNotes] = useState('');

  async function submit() {
    const { error } = await getSupabase().rpc('record_credential', {
      p_centre: centreId,
      p_person: personId,
      p_type: type,
      p_issued_on: issued || null,
      p_expires_on: expires || null,
      p_checked_on: type === 'vsc' ? checked || null : null,
      p_police_service: type === 'vsc' ? police || null : null,
      p_declaration_year: type === 'offence_declaration' ? Number(year) : null,
      p_notes: notes || null,
      p_recorder: recorderId,
      p_pin: pin,
    });
    if (!error) {
      setIssued('');
      setExpires('');
      setChecked('');
      setPolice('');
      setNotes('');
    }
    onDone(error ? error.message : 'Recorded on the file.');
  }

  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap', marginTop: 10 }}>
      <label>
        Record
        <select value={type} onChange={(e) => setType(e.target.value)}>
          {Object.entries(CRED_LABELS).map(([k, v]) => (
            <option key={k} value={k}>
              {v}
            </option>
          ))}
        </select>
      </label>
      <label>
        Obtained
        <input type="date" value={issued} onChange={(e) => setIssued(e.target.value)} />
      </label>
      {type === 'vsc' ? (
        <>
          <label>
            Conducted by the police on
            <input type="date" value={checked} onChange={(e) => setChecked(e.target.value)} />
          </label>
          <label>
            Police service
            <input value={police} onChange={(e) => setPolice(e.target.value)} placeholder="Toronto Police Service" />
          </label>
          <span className="caption" style={{ maxWidth: 220 }}>
            The five-year expiry is worked out from the date it was obtained — you never type it.
          </span>
        </>
      ) : type === 'offence_declaration' ? (
        <label>
          Year it covers
          <input type="number" value={year} onChange={(e) => setYear(e.target.value)} />
        </label>
      ) : (
        <label>
          Expires
          <input type="date" value={expires} onChange={(e) => setExpires(e.target.value)} />
        </label>
      )}
      <label style={{ flex: 1, minWidth: 200 }}>
        Note
        <input value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Canadian Red Cross" />
      </label>
      <button type="button" onClick={() => void submit()}>
        Record
      </button>
    </div>
  );
}
