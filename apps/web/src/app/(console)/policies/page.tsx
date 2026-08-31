'use client';

/** s. 46 and the policies a centre must hold. The value here is the same as
 * the staff file's: not the tidy list of policies that exist, but the list of
 * people who have not read them. An attestation is against a VERSION, and
 * modifying a policy resets everyone — which is the wording of s. 46(3) and
 * the thing a centre forgets. The program statement is not editable here: its
 * text is the handbook's, and issuing a handbook publishes it. */

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

interface Spec {
  key: string;
  label: string;
  regulation: string;
  note: string;
  review_months: number | null;
  sourced_from: string | null;
  ordinal: number;
}

interface Version {
  id: string;
  policy_key: string;
  version: number;
  body: string;
  summary: string | null;
  published_at: string;
  superseded_at: string | null;
}

interface Gap {
  person_id: string;
  full_name: string;
  role: string;
  policy_key: string;
  policy_label: string;
  regulation: string;
  state: string;
  version: number | null;
  attested_at: string | null;
}

const STATE: Record<string, { label: string; cls: string }> = {
  current: { label: 'Read', cls: 'ok' },
  never_read: { label: 'Not read', cls: 'now' },
  due_again: { label: 'Due again', cls: 'due' },
  not_published: { label: 'Not published', cls: 'now' },
};

export default function PoliciesPage() {
  const { centre, personId } = useConsole();
  const [specs, setSpecs] = useState<Spec[]>([]);
  const [versions, setVersions] = useState<Version[]>([]);
  const [gaps, setGaps] = useState<Gap[]>([]);
  const [drafts, setDrafts] = useState<Record<string, { body: string; summary: string }>>({});
  const [open, setOpen] = useState<string | null>(null);
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(() => {
    const sb = getSupabase();
    sb.from('policy_spec')
      .select('key, label, regulation, note, review_months, sourced_from, ordinal')
      .eq('jurisdiction_code', centre.jurisdiction_code)
      .order('ordinal')
      .then(({ data }) => setSpecs((data as Spec[]) ?? []));
    sb.from('policy_version')
      .select('id, policy_key, version, body, summary, published_at, superseded_at')
      .eq('centre_id', centre.id)
      .order('version', { ascending: false })
      .then(({ data }) => setVersions((data as Version[]) ?? []));
    sb.rpc('policy_attestation_gaps', { p_centre: centre.id }).then(({ data }) =>
      setGaps((data as Gap[]) ?? []),
    );
  }, [centre.id, centre.jurisdiction_code]);

  useEffect(load, [load]);

  const live = (key: string) => versions.find((v) => v.policy_key === key && !v.superseded_at);
  const outstanding = gaps.filter((g) => g.state !== 'current');
  const people = Array.from(new Map(gaps.map((g) => [g.person_id, g])).values());

  async function publish(key: string) {
    const draft = drafts[key] ?? { body: '', summary: '' };
    setNotice(null);
    const { error } = await getSupabase().rpc('publish_policy', {
      p_centre: centre.id,
      p_key: key,
      p_body: draft.body,
      p_summary: draft.summary || null,
      p_recorder: personId,
      p_pin: pin,
    });
    setPin('');
    if (!error) setDrafts((d) => ({ ...d, [key]: { body: '', summary: '' } }));
    setNotice(
      error ? error.message : 'Published — everyone it applies to has been asked to read it.',
    );
    load();
  }

  return (
    <>
      <h1>Policies &amp; attestations</h1>
      {notice ? <section className="card"><p>{notice}</p></section> : null}

      <section className="card">
        <h2>Who has not read what</h2>
        <p className="muted">
          s. 46 asks every employee, student and volunteer to review the program statement and the
          prohibited practices before they begin, at least once a year, and <strong>again whenever
          the statement changes</strong>. An attestation is recorded against the exact version they
          read, so &quot;we told everyone&quot; is never the answer.
        </p>
        {outstanding.length === 0 ? (
          <p className="muted">Everyone has read every policy that applies to them.</p>
        ) : (
          <p>
            <span className="pill now">{outstanding.length}</span> outstanding across {people.length}{' '}
            {people.length === 1 ? 'person' : 'people'}.
          </p>
        )}
        <label className="inline">
          Staff PIN (for publishing)
          <input
            type="password"
            inputMode="numeric"
            value={pin}
            onChange={(e) => setPin(e.target.value)}
            maxLength={6}
            autoComplete="off"
          />
        </label>
        {outstanding.length > 0 ? (
          <div style={{ overflowX: 'auto' }}>
            <table>
              <thead>
                <tr>
                  <th>Person</th>
                  <th>Policy</th>
                  <th>State</th>
                  <th>Regulation</th>
                </tr>
              </thead>
              <tbody>
                {outstanding.map((g) => {
                  const st = STATE[g.state] ?? { label: g.state, cls: 'due' };
                  return (
                    <tr key={`${g.person_id}-${g.policy_key}`}>
                      <td className="wrap">
                        {g.full_name} <span className="caption">{g.role.replace(/_/g, ' ')}</span>
                      </td>
                      <td className="wrap">{g.policy_label}</td>
                      <td>
                        <span className={`pill ${st.cls}`}>{st.label}</span>
                      </td>
                      <td className="caption">{g.regulation}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : null}
      </section>

      {specs.map((s) => {
        const v = live(s.key);
        const draft = drafts[s.key] ?? { body: '', summary: '' };
        const read = gaps.filter((g) => g.policy_key === s.key && g.state === 'current').length;
        const owed = gaps.filter((g) => g.policy_key === s.key).length;
        const isOpen = open === s.key;
        return (
          <section className="card" key={s.key}>
            <h2>
              {s.label}{' '}
              {v ? (
                <span className="pill ok">
                  v{v.version} · read by {read} of {owed}
                </span>
              ) : (
                <span className="pill now">Not published</span>
              )}
              <button className="quiet" style={{ marginLeft: 8 }} onClick={() => setOpen(isOpen ? null : s.key)}>
                {isOpen ? 'Close' : v ? 'Open' : 'Write it'}
              </button>
            </h2>
            <p className="caption">
              {s.regulation} · {s.note}
              {s.review_months ? ` Reviewed every ${s.review_months} months.` : ''}
            </p>
            {isOpen ? (
              <>
                {v ? (
                  <p className="wrap" style={{ whiteSpace: 'pre-wrap' }}>
                    {v.body}
                    <br />
                    <span className="caption">Published {fmtDate(v.published_at)}</span>
                  </p>
                ) : null}
                {s.sourced_from === 'handbook.program_statement' ? (
                  <p className="muted">
                    This one is not written here. Its text is the program statement in the{' '}
                    <Link href="/handbook">parent handbook</Link> (s. 45) — issuing a handbook
                    publishes it, and changing it there asks everyone to read it again. One statement,
                    not two that can disagree.
                  </p>
                ) : (
                  <div style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap', marginTop: 8 }}>
                    <label style={{ flex: 1, minWidth: 320 }}>
                      {v ? 'Replace it with' : 'Write the policy'}
                      <textarea
                        rows={5}
                        value={draft.body}
                        onChange={(e) =>
                          setDrafts((d) => ({ ...d, [s.key]: { ...draft, body: e.target.value } }))
                        }
                        style={{ fontFamily: 'inherit' }}
                      />
                    </label>
                    {v ? (
                      <label style={{ flex: 1, minWidth: 220 }}>
                        What changed
                        <input
                          value={draft.summary}
                          onChange={(e) =>
                            setDrafts((d) => ({ ...d, [s.key]: { ...draft, summary: e.target.value } }))
                          }
                          placeholder="Added the reporting duty"
                        />
                      </label>
                    ) : null}
                    <button type="button" disabled={!draft.body.trim()} onClick={() => void publish(s.key)}>
                      Publish
                    </button>
                  </div>
                )}
                {v ? (
                  <p className="caption">
                    Publishing a change asks everyone it applies to read it again — an attestation to
                    v{v.version} does not carry over.
                  </p>
                ) : null}
              </>
            ) : null}
          </section>
        );
      })}
    </>
  );
}
