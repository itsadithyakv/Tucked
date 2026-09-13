'use client';

/** The child's record (s. 72(1)) in one inspectable view, with two exports:
 * the full record, and the s. 72(6) subset the medical officer of health may
 * inspect and copy — items 2, 3, 8 and 9 exactly, nothing more.
 *
 * Each item carries its documents: the signed page, not just the word
 * "provided". Attaching one re-opens that item's verification (0042). */

import { useCallback, useEffect, useRef, useState } from 'react';
import { useParams } from 'next/navigation';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, fmtTime, useConsole } from '@/lib/console';

interface RecordDoc {
  id: string;
  item_type: string;
  storage_path: string;
  file_name: string;
  uploaded_at: string;
  uploaded_via: 'staff' | 'family';
  superseded_at: string | null;
  by: { full_name: string } | null;
}

interface Child {
  id: string;
  full_name: string;
  date_of_birth: string;
  admission_date: string;
  discharge_date: string | null;
  room: { name: string } | null;
}

interface Item {
  item_type: string;
  status: string;
  content: Record<string, unknown>;
  verified_at: string | null;
  verified_by_person: { full_name: string } | null;
}

interface Consent {
  consent_type: string;
  status: string;
  granted_at: string;
  revoked_at: string | null;
  granted_by_person: { full_name: string } | null;
}

interface Symptom {
  logged_at: string;
  payload: { observation?: string; parent_reported?: string; symptoms?: string[] };
  by: { full_name: string } | null;
}

const ITEM_LABELS: Record<string, { label: string; moh: boolean }> = {
  application: { label: '1 · Signed application for enrolment', moh: false },
  identity: { label: '2 · Name, date of birth, home address', moh: true },
  parent_contacts: { label: "3 · Parents' names, addresses, phone numbers", moh: true },
  emergency_contact: { label: '4 · Emergency contact during care hours', moh: false },
  release_persons: { label: '5 · Persons the child may be released to', moh: false },
  admission: { label: '6 · Date of admission', moh: false },
  discharge: { label: '7 · Date of discharge', moh: false },
  health_immunisation: { label: '8 · Health history, conditions, immunisation', moh: true },
  symptoms_log: { label: '9 · Ill-health symptoms log', moh: true },
  medication_instructions: { label: '10 · Medication instructions', moh: false },
  care_instructions: { label: '11 · Diet / rest / activity instructions', moh: false },
};

function flat(content: Record<string, unknown>): string {
  const entries = Object.entries(content).filter(([, v]) => v !== null && v !== '');
  if (entries.length === 0) return '';
  return entries
    .map(([k, v]) => `${k.replace(/_/g, ' ')}: ${Array.isArray(v) ? v.join(', ') : String(v)}`)
    .join(' · ');
}

export default function ChildRecordPage() {
  const params = useParams<{ id: string }>();
  const { centre, personId } = useConsole();
  const [child, setChild] = useState<Child | null>(null);
  const [docs, setDocs] = useState<RecordDoc[]>([]);
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);
  const [items, setItems] = useState<Item[]>([]);
  const [consents, setConsents] = useState<Consent[]>([]);
  const [symptoms, setSymptoms] = useState<Symptom[]>([]);
  const [immunisation, setImmunisation] = useState<{
    status: string;
    detail: string | null;
    practitioner: string | null;
    notarised_on: string | null;
    effective_on: string;
  } | null>(null);
  const [mohMode, setMohMode] = useState(false);

  const loadDocs = useCallback(() => {
    getSupabase()
      .from('child_record_document')
      .select('id, item_type, storage_path, file_name, uploaded_at, uploaded_via, superseded_at, by:uploaded_by(full_name)')
      .eq('child_id', params.id)
      .order('uploaded_at', { ascending: false })
      .then(({ data }) => setDocs((data as never as RecordDoc[]) ?? []));
  }, [params.id]);

  useEffect(loadDocs, [loadDocs]);

  async function openDocument(path: string) {
    const { data, error } = await getSupabase().storage.from('evidence').createSignedUrl(path, 60);
    if (error || !data) {
      setNotice(error?.message ?? 'Could not open that file.');
      return;
    }
    window.open(data.signedUrl, '_blank', 'noopener');
  }

  useEffect(() => {
    const sb = getSupabase();
    sb.from('child')
      .select('id, full_name, date_of_birth, admission_date, discharge_date, room:current_room_id(name)')
      .eq('id', params.id)
      .maybeSingle()
      .then(({ data }) => setChild(data as never));
    sb.from('child_record_item')
      .select('item_type, status, content, verified_at, verified_by_person:verified_by(full_name)')
      .eq('child_id', params.id)
      .then(({ data }) => setItems((data as never) ?? []));
    sb.from('consent')
      .select('consent_type, status, granted_at, revoked_at, granted_by_person:granted_by(full_name)')
      .eq('child_id', params.id)
      .is('revoked_at', null)
      .order('consent_type')
      .then(({ data }) => setConsents((data as never) ?? []));
    sb.from('care_log')
      .select('logged_at, payload, by:recorded_by(full_name)')
      .eq('child_id', params.id)
      .eq('log_type', 'health_observation')
      .order('logged_at', { ascending: false })
      .limit(30)
      .then(({ data }) => setSymptoms((data as never) ?? []));
    sb.from('current_immunisation')
      .select('status, detail, practitioner, notarised_on, effective_on')
      .eq('child_id', params.id)
      .maybeSingle()
      .then(({ data }) => setImmunisation((data as never) ?? null));
  }, [params.id]);

  function printMoh() {
    setMohMode(true);
    setTimeout(() => {
      window.print();
      setMohMode(false);
    }, 60);
  }

  if (!child) return null;

  const orderedItems = Object.keys(ITEM_LABELS)
    .map((key) => ({ key, item: items.find((i) => i.item_type === key) }))
    .filter(({ key }) => !mohMode || ITEM_LABELS[key]!.moh);

  return (
    <>
      <h1>{child.full_name}</h1>
      {mohMode ? (
        <p className="muted">
          Prepared for the medical officer of health under s. 72(6) — items 2, 3, 8 and 9 only.
        </p>
      ) : null}
      <div className="toolbar">
        <button className="quiet" onClick={() => window.print()}>
          Print full record
        </button>
        <button className="quiet" onClick={printMoh}>
          Medical officer copy (s. 72(6))
        </button>
        <label className="inline">
          Staff PIN (to attach)
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
        <h2>Child</h2>
        <p className="muted">
          Born {fmtDate(child.date_of_birth)} · {child.room?.name ?? 'no room'} · admitted{' '}
          {fmtDate(child.admission_date)}
          {child.discharge_date ? ` · discharged ${fmtDate(child.discharge_date)}` : ''}
        </p>
      </section>
      <section className="card">
        <h2>Children&apos;s record (s. 72(1))</h2>
        <table>
          <thead>
            <tr>
              <th>Item</th>
              <th>Status</th>
              <th>Content</th>
              <th>Documents</th>
              <th>Verified</th>
            </tr>
          </thead>
          <tbody>
            {orderedItems.map(({ key, item }) => (
              <tr key={key}>
                <td>{ITEM_LABELS[key]!.label}</td>
                <td>
                  <span className={`pill ${item && item.status !== 'missing' ? 'ok' : 'due'}`}>
                    {(item?.status ?? 'missing').replace(/_/g, ' ')}
                  </span>
                </td>
                <td className="wrap muted">{item ? flat(item.content) : ''}</td>
                <td className="wrap">
                  {(() => {
                    const mine = docs.filter((d) => d.item_type === key);
                    const live = mine.filter((d) => !d.superseded_at);
                    const replaced = mine.length - live.length;
                    return (
                      <>
                        {live.map((d) => (
                          <div key={d.id}>
                            <button type="button" className="link" onClick={() => void openDocument(d.storage_path)}>
                              {d.file_name}
                            </button>
                            <span className="caption">
                              {' '}
                              {d.uploaded_via === 'family' ? 'from the family' : d.by?.full_name ?? 'staff'}, {fmtDate(d.uploaded_at)}
                            </span>
                          </div>
                        ))}
                        {replaced > 0 ? (
                          <span className="caption">{`${replaced} earlier cop${replaced === 1 ? 'y' : 'ies'} kept`}</span>
                        ) : null}
                        {mohMode ? null : (
                          <AttachDocument
                            centreId={centre.id}
                            childId={child.id}
                            itemType={key}
                            replaces={live[0]?.id ?? null}
                            recorderId={personId}
                            pin={pin}
                            onDone={(message) => {
                              setNotice(message);
                              loadDocs();
                            }}
                          />
                        )}
                      </>
                    );
                  })()}
                </td>
                <td className="caption">
                  {item?.verified_at ? `${item.verified_by_person?.full_name}, ${fmtDate(item.verified_at)}` : '—'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
      <section className="card">
        <h2>Immunisation (s. 35 — part of item 8)</h2>
        {immunisation ? (
          <p>
            <span className="pill ok">{immunisation.status.replace(/_/g, ' ')}</span>{' '}
            {immunisation.detail}
            {immunisation.practitioner ? ` — signed by ${immunisation.practitioner}` : ''}
            {immunisation.notarised_on ? ` — notarised ${fmtDate(immunisation.notarised_on)}` : ''}{' '}
            <span className="caption">effective {fmtDate(immunisation.effective_on)}</span>
          </p>
        ) : (
          <p>
            <span className="pill due">Nothing on file</span>{' '}
            <span className="muted">No immunisation record, exemption form, or school attendance noted yet.</span>
          </p>
        )}
      </section>
      {mohMode || (
        <section className="card">
          <h2>Consents (s. 73 — optional consents never gate enrolment)</h2>
          {consents.map((c) => (
            <p key={c.consent_type}>
              <span className={`pill ${c.status === 'granted' ? 'ok' : 'due'}`}>{c.status}</span>{' '}
              {c.consent_type.replace(/_/g, ' ')}{' '}
              <span className="caption">
                by {c.granted_by_person?.full_name}, {fmtDate(c.granted_at)}
              </span>
            </p>
          ))}
          {consents.length === 0 ? <p className="muted">No consent decisions recorded yet.</p> : null}
        </section>
      )}
      <section className="card">
        <h2>Symptoms log (item 9)</h2>
        <table>
          <thead>
            <tr>
              <th>When</th>
              <th>Observation</th>
              <th>Parent reported</th>
              <th>By</th>
            </tr>
          </thead>
          <tbody>
            {symptoms.map((s, i) => (
              <tr key={i}>
                <td>
                  {fmtDate(s.logged_at)} {fmtTime(s.logged_at, centre.timezone)}
                </td>
                <td className="wrap">
                  {s.payload.observation}
                  {s.payload.symptoms?.length ? ` — ${s.payload.symptoms.join(', ')}` : ''}
                </td>
                <td className="wrap muted">{s.payload.parent_reported ?? ''}</td>
                <td className="muted">{s.by?.full_name}</td>
              </tr>
            ))}
            {symptoms.length === 0 ? (
              <tr>
                <td colSpan={4} className="muted">
                  No ill-health observations recorded.
                </td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </section>
    </>
  );
}

/** Attach a PDF or an image to one item of the record. The bytes land in the
 * child's own folder first; attach_record_document then refuses anything that
 * did not arrive, and re-opens the item's verification. */
function AttachDocument({
  centreId,
  childId,
  itemType,
  replaces,
  recorderId,
  pin,
  onDone,
}: {
  centreId: string;
  childId: string;
  itemType: string;
  replaces: string | null;
  recorderId: string;
  pin: string;
  onDone: (message: string) => void;
}) {
  const ref = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);

  async function upload(file: File) {
    if (file.size > 20 * 1024 * 1024) {
      onDone('That file is over 20 MB — scan it smaller, or split it.');
      return;
    }
    if (pin.length < 4) {
      onDone('Enter your staff PIN first — the record says who attached it.');
      return;
    }
    setBusy(true);
    const sb = getSupabase();
    const ext = file.name.includes('.') ? file.name.split('.').pop()!.toLowerCase() : 'pdf';
    // a fresh name every time: a replacement must never collide with the copy it replaces
    const path = `${centreId}/child/${childId}/${crypto.randomUUID()}.${ext}`;
    const contentType = file.type || 'application/pdf';
    const { error: upErr } = await sb.storage.from('evidence').upload(path, file, { upsert: false, contentType });
    if (upErr) {
      setBusy(false);
      onDone(upErr.message);
      return;
    }
    const { error } = await sb.rpc('attach_record_document', {
      p_child: childId,
      p_item: itemType,
      p_storage_path: path,
      p_file_name: file.name,
      p_content_type: contentType,
      p_size_bytes: file.size,
      p_note: null,
      p_replaces: replaces,
      p_recorder: recorderId,
      p_pin: pin,
    });
    setBusy(false);
    onDone(
      error
        ? error.message
        : `${file.name} attached${replaces ? ' — the earlier copy is kept' : ''}. This item needs verifying again.`,
    );
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
      {/* Text-weight, not a clay button: eleven identical buttons down this
          column outweighed the documents themselves. */}
      <button type="button" className="link" disabled={busy} onClick={() => ref.current?.click()}>
        {busy ? 'Uploading…' : replaces ? 'Replace' : 'Attach a document'}
      </button>
    </>
  );
}
