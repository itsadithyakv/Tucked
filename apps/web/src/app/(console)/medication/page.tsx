'use client';

/** s. 40: authorisations (dose + schedule/symptoms) and the administration
 * log — blanket items included, because the regulation says they are. */

import { useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, fmtTime, useConsole } from '@/lib/console';

interface Auth {
  id: string;
  kind: string;
  drug_name: string;
  dose: string | null;
  schedule: string | null;
  symptoms: string | null;
  expiry_date: string | null;
  revoked_at: string | null;
  child: { full_name: string } | null;
  parent: { full_name: string } | null;
}

interface Admin {
  id: string;
  administered_at: string;
  dose_given: string | null;
  outcome: string | null;
  self_administered: boolean;
  child: { full_name: string } | null;
  by: { full_name: string } | null;
  authorisation: { drug_name: string; kind: string } | null;
}

export default function MedicationPage() {
  const { centre } = useConsole();
  const [auths, setAuths] = useState<Auth[]>([]);
  const [admins, setAdmins] = useState<Admin[]>([]);

  useEffect(() => {
    const sb = getSupabase();
    sb.from('medication_authorisation')
      .select(
        'id, kind, drug_name, dose, schedule, symptoms, expiry_date, revoked_at, child:child_id(full_name), parent:parent_authorised_by(full_name)',
      )
      .eq('centre_id', centre.id)
      .order('created_at', { ascending: false })
      .then(({ data }) => setAuths((data as never) ?? []));
    sb.from('medication_administration')
      .select(
        'id, administered_at, dose_given, outcome, self_administered, child:child_id(full_name), by:administered_by(full_name), authorisation:authorisation_id(drug_name, kind)',
      )
      .eq('centre_id', centre.id)
      .order('administered_at', { ascending: false })
      .limit(100)
      .then(({ data }) => setAdmins((data as never) ?? []));
  }, [centre.id]);

  return (
    <>
      <h1>Medication</h1>
      <section className="card">
        <h2>Authorisations</h2>
        <table>
          <thead>
            <tr>
              <th>Child</th>
              <th>Medication</th>
              <th>Dose</th>
              <th>Schedule / symptoms</th>
              <th>Expiry</th>
              <th>Authorised by</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {auths.map((a) => (
              <tr key={a.id}>
                <td>{a.child?.full_name}</td>
                <td>
                  {a.drug_name} <span className="caption">{a.kind.replace(/_/g, ' ')}</span>
                </td>
                <td>{a.dose ?? '—'}</td>
                <td>{a.schedule ?? a.symptoms ?? 'blanket'}</td>
                <td>{a.expiry_date ? fmtDate(a.expiry_date) : '—'}</td>
                <td className="muted">{a.parent?.full_name}</td>
                <td>
                  {a.revoked_at ? (
                    <span className="pill due">Revoked</span>
                  ) : (
                    <span className="pill ok">Active</span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
      <section className="card">
        <h2>Administration log</h2>
        <table>
          <thead>
            <tr>
              <th>When</th>
              <th>Child</th>
              <th>Medication</th>
              <th>Dose given</th>
              <th>Outcome</th>
              <th>By</th>
            </tr>
          </thead>
          <tbody>
            {admins.map((a) => (
              <tr key={a.id}>
                <td>{fmtTime(a.administered_at, centre.timezone)}</td>
                <td>{a.child?.full_name}</td>
                <td>
                  {a.authorisation?.drug_name}
                  {a.self_administered ? ' (self-administered)' : ''}
                </td>
                <td>{a.dose_given ?? '—'}</td>
                <td className="muted">{a.outcome ?? ''}</td>
                <td className="muted">{a.by?.full_name}</td>
              </tr>
            ))}
            {admins.length === 0 ? (
              <tr>
                <td colSpan={6} className="muted">
                  No administrations recorded.
                </td>
              </tr>
            ) : null}
          </tbody>
        </table>
      </section>
    </>
  );
}
