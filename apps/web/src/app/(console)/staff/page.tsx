'use client';

/** ss. 53–64: the staff file / credential ledger — the free wedge. Expiry
 * states surface before a program advisor ever has to ask. */

import { useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

interface Cred {
  id: string;
  credential_type: string;
  issued_on: string | null;
  expires_on: string | null;
  expiry_state: string;
  person: { id: string; full_name: string } | null;
}

interface StaffRole {
  role: string;
  qualified: boolean;
  person: { id: string; full_name: string } | null;
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

const STATE_PILL: Record<string, { label: string; cls: string }> = {
  current: { label: 'Current', cls: 'ok' },
  expiring_soon: { label: 'Expiring soon', cls: 'due' },
  expired: { label: 'Expired', cls: 'now' },
  no_expiry: { label: 'On file', cls: 'ok' },
};

export default function StaffPage() {
  const { centre } = useConsole();
  const [staff, setStaff] = useState<StaffRole[]>([]);
  const [creds, setCreds] = useState<Cred[]>([]);

  useEffect(() => {
    const sb = getSupabase();
    sb.from('person_role')
      .select('role, qualified, person:person_id(id, full_name)')
      .eq('centre_id', centre.id)
      .eq('active', true)
      .neq('role', 'family_adult')
      .then(({ data }) => setStaff((data as never) ?? []));
    sb.from('credential_status')
      .select('id, credential_type, issued_on, expires_on, expiry_state, person:person_id(id, full_name)')
      .eq('centre_id', centre.id)
      .order('expires_on')
      .then(({ data }) => setCreds((data as never) ?? []));
  }, [centre.id]);

  return (
    <>
      <h1>Staff files</h1>
      {staff.map((s) => {
        const personCreds = creds.filter((c) => c.person?.id === s.person?.id);
        return (
          <section className="card" key={s.person?.id ?? s.role}>
            <h2>
              {s.person?.full_name}{' '}
              <span className="caption">
                {s.role.replace(/_/g, ' ')}
                {s.qualified ? ' · qualified' : ''}
              </span>
            </h2>
            {personCreds.length === 0 ? (
              <p>
                <span className="pill due">No credentials on file</span>
              </p>
            ) : (
              personCreds.map((c) => {
                const pill = STATE_PILL[c.expiry_state] ?? STATE_PILL.no_expiry!;
                return (
                  <p key={c.id}>
                    <span className={`pill ${pill.cls}`}>{pill.label}</span>{' '}
                    {CRED_LABELS[c.credential_type] ?? c.credential_type}
                    {c.expires_on ? (
                      <span className="caption"> — expires {fmtDate(c.expires_on)}</span>
                    ) : null}
                  </p>
                );
              })
            )}
          </section>
        );
      })}
    </>
  );
}
