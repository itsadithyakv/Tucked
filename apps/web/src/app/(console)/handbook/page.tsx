'use client';

/** s. 45: the parent handbook. The required section list comes from the
 * jurisdiction, so this page is a checklist the regulator wrote. Two sections
 * are read from the live record rather than typed here — the anaphylaxis
 * policy (s. 39) and the CWELCC statement — so the handbook can never
 * contradict what the centre actually holds. Issuing it freezes it and asks
 * every family to acknowledge; the outstanding list is the evidence gap. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

interface Spec {
  key: string;
  ordinal: number;
  title: string;
  regulation: string;
  guidance: string;
  sourced_from: string | null;
}

interface Content {
  section_key: string;
  body: string;
  updated_at: string;
}

interface Version {
  id: string;
  version: number;
  summary: string | null;
  published_at: string;
  person: { full_name: string } | null;
}

interface VersionSection {
  handbook_version_id: string;
  section_key: string;
  ordinal: number;
  title: string;
  regulation: string;
  body: string;
}

interface Ack {
  person_id: string;
  method: string;
  acknowledged_at: string;
  handbook_version_id: string;
  person: { full_name: string } | null;
}

interface Outstanding {
  person_id: string;
  full_name: string;
  handbook_version_id: string;
}

const SOURCE_NOTE: Record<string, string> = {
  'centre.anaphylaxis_policy':
    'Read from the centre anaphylaxis policy on Plans & allergies — edit it there and it changes here.',
  'centre.cwelcc_enrolled':
    'The first line is written from the centre record, so it can never contradict it. Anything you add here follows it.',
};

export default function HandbookPage() {
  const { centre, personId } = useConsole();
  const [specs, setSpecs] = useState<Spec[]>([]);
  const [content, setContent] = useState<Content[]>([]);
  const [missing, setMissing] = useState<{ key: string; title: string }[]>([]);
  const [versions, setVersions] = useState<Version[]>([]);
  const [sections, setSections] = useState<VersionSection[]>([]);
  const [acks, setAcks] = useState<Ack[]>([]);
  const [outstanding, setOutstanding] = useState<Outstanding[]>([]);
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [pin, setPin] = useState('');
  const [summary, setSummary] = useState('');
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [showing, setShowing] = useState<string | null>(null);

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.from('handbook_section_spec')
      .select('key, ordinal, title, regulation, guidance, sourced_from')
      .eq('jurisdiction_code', centre.jurisdiction_code)
      .order('ordinal')
      .then(({ data }) => setSpecs((data as Spec[]) ?? []));
    sb.from('handbook_content')
      .select('section_key, body, updated_at')
      .eq('centre_id', centre.id)
      .then(({ data }) => setContent((data as Content[]) ?? []));
    sb.rpc('handbook_missing_sections', { p_centre: centre.id }).then(({ data }) =>
      setMissing((data as { key: string; title: string }[]) ?? []),
    );
    sb.from('handbook_version')
      .select('id, version, summary, published_at, person:published_by(full_name)')
      .eq('centre_id', centre.id)
      .order('version', { ascending: false })
      .then(({ data }) => setVersions((data as never) ?? []));
    sb.from('handbook_version_section')
      .select('handbook_version_id, section_key, ordinal, title, regulation, body')
      .eq('centre_id', centre.id)
      .order('ordinal')
      .then(({ data }) => setSections((data as VersionSection[]) ?? []));
    sb.from('handbook_acknowledgement')
      .select('person_id, method, acknowledged_at, handbook_version_id, person:person_id(full_name)')
      .eq('centre_id', centre.id)
      .order('acknowledged_at', { ascending: false })
      .then(({ data }) => setAcks((data as never) ?? []));
    sb.from('handbook_outstanding')
      .select('person_id, full_name, handbook_version_id')
      .eq('centre_id', centre.id)
      .then(({ data }) => setOutstanding((data as Outstanding[]) ?? []));
  }, [centre.id, centre.jurisdiction_code]);

  useEffect(load, [load]);

  const current = versions[0];
  const currentSections = sections.filter((s) => s.handbook_version_id === current?.id);
  const currentAcks = acks.filter((a) => a.handbook_version_id === current?.id);
  const viewing = showing ? versions.find((v) => v.id === showing) : null;

  function bodyOf(key: string): string {
    return drafts[key] ?? content.find((c) => c.section_key === key)?.body ?? '';
  }

  async function saveSection(key: string) {
    setBusy(true);
    setNotice(null);
    const { error } = await getSupabase().rpc('save_handbook_section', {
      p_centre: centre.id,
      p_key: key,
      p_body: bodyOf(key),
      p_recorder: personId,
      p_pin: pin,
    });
    setBusy(false);
    setPin('');
    setNotice(error ? error.message : 'Saved to the working draft — not issued yet.');
    if (!error) setDrafts((d) => ({ ...d, [key]: undefined as never }));
    load();
  }

  async function publish() {
    setBusy(true);
    setNotice(null);
    const { error } = await getSupabase().rpc('publish_handbook', {
      p_centre: centre.id,
      p_summary: summary,
      p_recorder: personId,
      p_pin: pin,
    });
    setBusy(false);
    setPin('');
    if (!error) setSummary('');
    setNotice(
      error ? error.message : 'Issued. Every family has been asked to read it and let you know.',
    );
    load();
  }

  return (
    <>
      <h1>Parent handbook</h1>
      {notice ? <section className="card"><p>{notice}</p></section> : null}

      <section className="card">
        <h2>Where it stands (s. 45)</h2>
        {!current ? (
          <p>
            <span className="pill due">Due</span> No handbook has been issued yet. Every family must be
            given one.
          </p>
        ) : (
          <p>
            <span className="pill ok">Version {current.version}</span> Issued{' '}
            {fmtDate(current.published_at)} by {current.person?.full_name}.
          </p>
        )}
        {missing.length > 0 ? (
          <p>
            <span className="pill due">Incomplete</span> {missing.length} section
            {missing.length === 1 ? '' : 's'} still to write: {missing.map((m) => m.title).join(', ')}.
            The handbook cannot be issued until every one is written.
          </p>
        ) : (
          <p className="muted">Every required section is written.</p>
        )}
        {current ? (
          outstanding.length > 0 ? (
            <p>
              <span className="pill due">Due</span> {outstanding.length}{' '}
              {outstanding.length === 1 ? 'parent has' : 'parents have'} not acknowledged version{' '}
              {current.version}
              {outstanding.length <= 4
                ? `: ${outstanding.map((o) => o.full_name).join(', ')}.`
                : ` — ${outstanding.slice(0, 3).map((o) => o.full_name).join(', ')} and ${outstanding.length - 3} others, listed below.`}
            </p>
          ) : (
            <p className="muted">
              Every parent of an enrolled child has acknowledged version {current.version}.
            </p>
          )
        ) : null}
      </section>

      <section className="card">
        <h2>The sections s. 45 requires</h2>
        <p className="muted">
          This list is the regulator&apos;s, not ours — it comes from the jurisdiction the centre runs
          under, so another province is a different list and nothing else changes.
        </p>
        {specs.map((s) => {
          const saved = content.find((c) => c.section_key === s.key);
          const sourced = s.sourced_from !== null;
          const readOnly = s.sourced_from === 'centre.anaphylaxis_policy';
          const isMissing = missing.some((m) => m.key === s.key);
          const published = currentSections.find((v) => v.section_key === s.key);
          const changed = published && published.body !== (bodyOf(s.key) || published.body);
          return (
            <div key={s.key} style={{ borderTop: '1px solid var(--line)', paddingTop: 10, marginTop: 10 }}>
              <h3 style={{ marginBottom: 2 }}>
                {s.ordinal}. {s.title}{' '}
                {isMissing ? <span className="pill due">Missing</span> : null}
                {sourced ? <span className="pill ok">From the record</span> : null}
              </h3>
              <p className="caption">{s.regulation}</p>
              <p className="muted">{s.guidance}</p>
              {sourced ? <p className="caption">{SOURCE_NOTE[s.sourced_from!]}</p> : null}
              {readOnly ? (
                <p className="wrap">{published?.body ?? <span className="muted">Not set yet.</span>}</p>
              ) : (
                <>
                  <textarea
                    rows={4}
                    value={bodyOf(s.key)}
                    onChange={(e) => setDrafts((d) => ({ ...d, [s.key]: e.target.value }))}
                    style={{ width: '100%' }}
                    placeholder={s.guidance}
                  />
                  <div style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap' }}>
                    <button type="button" className="quiet" disabled={busy} onClick={() => void saveSection(s.key)}>
                      Save section
                    </button>
                    {saved ? (
                      <span className="caption">Draft saved {fmtDate(saved.updated_at)}</span>
                    ) : null}
                    {changed ? <span className="caption">Differs from the issued handbook</span> : null}
                  </div>
                </>
              )}
            </div>
          );
        })}
      </section>

      <section className="card">
        <h2>Issue the handbook</h2>
        <p className="muted">
          Issuing freezes a copy that never changes, and asks every family to acknowledge it. An
          identical handbook is never re-issued — that would ask families to read the same thing twice.
        </p>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
          <label style={{ flex: 1, minWidth: 280 }}>
            What changed (families see this)
            <input
              value={summary}
              onChange={(e) => setSummary(e.target.value)}
              placeholder="Fees updated for September; new late pickup process."
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
          <button type="button" disabled={busy || missing.length > 0} onClick={() => void publish()}>
            {current ? 'Issue a new version' : 'Issue the handbook'}
          </button>
        </div>
      </section>

      {current ? (
        <section className="card print-target">
          <h2>
            Issued handbook{' '}
            <span className="pill ok">Version {viewing?.version ?? current.version}</span>
          </h2>
          {versions.length > 1 ? (
            <div className="toolbar">
              {versions.map((v) => (
                <button
                  key={v.id}
                  className={(showing ?? current.id) === v.id ? '' : 'quiet'}
                  onClick={() => setShowing(v.id)}
                >
                  v{v.version} · {fmtDate(v.published_at)}
                </button>
              ))}
            </div>
          ) : null}
          <div className="print-area">
            <h3>
              {centre.name} — parent handbook, version {viewing?.version ?? current.version}
            </h3>
            <p className="caption">
              Issued {fmtDate((viewing ?? current).published_at)}
              {(viewing ?? current).summary ? ` · ${(viewing ?? current).summary}` : ''}
            </p>
            {sections
              .filter((s) => s.handbook_version_id === (showing ?? current.id))
              .map((s) => (
                <div key={s.section_key} style={{ marginTop: 10 }}>
                  <h4 style={{ marginBottom: 2 }}>
                    {s.ordinal}. {s.title}
                  </h4>
                  <p className="caption">{s.regulation}</p>
                  <p className="wrap" style={{ whiteSpace: 'pre-wrap' }}>{s.body}</p>
                </div>
              ))}
          </div>
          <button type="button" className="quiet" onClick={() => window.print()}>
            Print the handbook
          </button>
        </section>
      ) : null}

      {current ? (
        <AcknowledgementCard
          versionId={current.id}
          version={current.version}
          personId={personId}
          acks={currentAcks}
          outstanding={outstanding}
          onDone={(msg) => {
            setNotice(msg);
            load();
          }}
        />
      ) : null}
    </>
  );
}

function AcknowledgementCard({
  versionId,
  version,
  personId,
  acks,
  outstanding,
  onDone,
}: {
  versionId: string;
  version: number;
  personId: string;
  acks: Ack[];
  outstanding: Outstanding[];
  onDone: (msg: string) => void;
}) {
  const [parentId, setParentId] = useState('');
  const [pin, setPin] = useState('');

  async function submit() {
    const { error } = await getSupabase().rpc('record_handbook_acknowledgement', {
      p_version: versionId,
      p_parent: parentId,
      p_acknowledged_at: null,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    onDone(error ? error.message : 'Recorded — that family has been given the handbook.');
  }

  return (
    <section className="card">
      <h2>Who has it (version {version})</h2>
      <p className="muted">
        Acknowledgement is the evidence a parent was given the handbook. Families acknowledge in the
        app; record a signed paper copy here for families who do not use it.
      </p>
      {outstanding.length > 0 ? (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
          <label style={{ minWidth: 220 }}>
            Signed paper from
            <select value={parentId} onChange={(e) => setParentId(e.target.value)}>
              <option value="">Choose…</option>
              {outstanding.map((o) => (
                <option key={o.person_id} value={o.person_id}>
                  {o.full_name}
                </option>
              ))}
            </select>
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
          <button type="button" disabled={!parentId} onClick={() => void submit()}>
            Record
          </button>
        </div>
      ) : null}
      <table>
        <thead>
          <tr>
            <th>Parent</th>
            <th>Acknowledged</th>
            <th>How</th>
          </tr>
        </thead>
        <tbody>
          {outstanding.map((o) => (
            <tr key={o.person_id}>
              <td>{o.full_name}</td>
              <td>
                <span className="pill due">Not yet</span>
              </td>
              <td className="caption">—</td>
            </tr>
          ))}
          {acks.map((a) => (
            <tr key={a.person_id}>
              <td>{a.person?.full_name}</td>
              <td>{fmtDate(a.acknowledged_at)}</td>
              <td className="caption">{a.method === 'in_app' ? 'In the app' : 'Signed paper'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}
