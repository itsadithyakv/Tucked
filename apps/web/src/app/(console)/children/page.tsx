'use client';

/** s. 72(1): the children's record checklist — every item's status per child,
 * never blank, with supervisor verification state. Discharged children stay
 * listed with their s. 72(5) retention clock: kept 3 years, then anonymised
 * automatically — never deleted. */

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { getSupabase } from '@/lib/supabase';
import { fmtDate, useConsole } from '@/lib/console';

interface Child {
  id: string;
  full_name: string;
  date_of_birth: string;
  discharge_date: string | null;
  room: { name: string } | null;
}

interface Clock {
  subject_id: string;
  purge_after: string;
  anonymised_at: string | null;
}

interface Immunisation {
  child_id: string;
  status: string;
  detail: string | null;
  practitioner: string | null;
  notarised_on: string | null;
}

const IMM_LABELS: Record<string, { label: string; cls: string }> = {
  immunised: { label: 'Immunised', cls: 'ok' },
  medical_exemption: { label: 'Medical exemption', cls: 'ok' },
  conscience_exemption: { label: 'Conscience exemption', cls: 'ok' },
  attends_school: { label: 'Attends school', cls: 'ok' },
};

interface Item {
  child_id: string;
  item_type: string;
  status: string;
  verified_at: string | null;
}

const ITEM_LABELS: Record<string, string> = {
  application: 'Signed application',
  identity: 'Name, DOB, address',
  parent_contacts: 'Parent contacts',
  emergency_contact: 'Emergency contact',
  release_persons: 'Release persons',
  admission: 'Admission date',
  discharge: 'Discharge date',
  health_immunisation: 'Health & immunisation',
  symptoms_log: 'Symptoms log',
  medication_instructions: 'Medication instructions',
  care_instructions: 'Diet / rest / activity',
};

export default function ChildrenPage() {
  const { centre } = useConsole();
  const [children, setChildren] = useState<Child[]>([]);
  const [items, setItems] = useState<Map<string, Item[]>>(new Map());
  const [clocks, setClocks] = useState<Map<string, Clock>>(new Map());
  const [immunisations, setImmunisations] = useState<Map<string, Immunisation>>(new Map());
  const [immTick, setImmTick] = useState(0);

  useEffect(() => {
    getSupabase()
      .from('current_immunisation')
      .select('child_id, status, detail, practitioner, notarised_on')
      .eq('centre_id', centre.id)
      .then(({ data }) =>
        setImmunisations(new Map(((data as Immunisation[]) ?? []).map((r) => [r.child_id, r]))),
      );
  }, [centre.id, immTick]);

  useEffect(() => {
    const sb = getSupabase();
    sb.from('child')
      .select('id, full_name, date_of_birth, discharge_date, room:current_room_id(name)')
      .eq('centre_id', centre.id)
      .order('full_name')
      .then(({ data }) => setChildren((data as never) ?? []));
    sb.from('retention_clock')
      .select('subject_id, purge_after, anonymised_at')
      .eq('centre_id', centre.id)
      .eq('kind', 'childrens_record')
      .then(({ data }) => setClocks(new Map(((data as Clock[]) ?? []).map((r) => [r.subject_id, r]))));
    sb.from('child_record_item')
      .select('child_id, item_type, status, verified_at')
      .eq('centre_id', centre.id)
      .then(({ data }) => {
        const map = new Map<string, Item[]>();
        for (const item of (data as never as Item[]) ?? []) {
          map.set(item.child_id, [...(map.get(item.child_id) ?? []), item]);
        }
        setItems(map);
      });
  }, [centre.id]);

  function recordState(childId: string) {
    const list = items.get(childId) ?? [];
    if (list.length === 0) return { label: 'Not started', cls: 'due' };
    const missing = list.filter((i) => i.status === 'missing').length;
    const unverified = list.filter((i) => i.status !== 'missing' && !i.verified_at).length;
    if (missing > 0) return { label: `${missing} item${missing === 1 ? '' : 's'} outstanding`, cls: 'due' };
    if (unverified > 0) return { label: 'Awaiting verification', cls: 'due' };
    return { label: 'Complete & verified', cls: 'ok' };
  }

  const activeChildren = children.filter((c) => !c.discharge_date);
  const missingImmunisation = activeChildren.filter((c) => !immunisations.has(c.id));

  return (
    <>
      <h1>Children&apos;s records</h1>

      <ImmunisationCard
        centreId={centre.id}
        children={activeChildren}
        missing={missingImmunisation}
        onDone={() => setImmTick((n) => n + 1)}
      />

      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Child</th>
              <th>Room</th>
              <th>Born</th>
              <th>Immunisation (s. 35)</th>
              <th>Record</th>
              <th>Items</th>
            </tr>
          </thead>
          <tbody>
            {children.map((c) => {
              const state = recordState(c.id);
              const list = items.get(c.id) ?? [];
              const clock = c.discharge_date ? clocks.get(c.id) : undefined;
              return (
                <tr key={c.id}>
                  <td>
                    <Link href={`/children/${c.id}`}>{c.full_name}</Link>
                  </td>
                  <td>{c.room?.name ?? '—'}</td>
                  <td>{c.date_of_birth}</td>
                  <td>
                    {(() => {
                      const imm = immunisations.get(c.id);
                      if (!imm) {
                        return c.discharge_date ? <span className="caption">—</span> : <span className="pill due">Nothing on file</span>;
                      }
                      const meta = IMM_LABELS[imm.status] ?? { label: imm.status, cls: 'due' };
                      return (
                        <span className={`pill ${meta.cls}`} title={[imm.detail, imm.practitioner, imm.notarised_on ? `notarised ${imm.notarised_on}` : null].filter(Boolean).join(' · ')}>
                          {meta.label}
                        </span>
                      );
                    })()}
                  </td>
                  <td>
                    {clock ? (
                      clock.anonymised_at ? (
                        <span className="pill ok">Anonymised (s. 72(5))</span>
                      ) : (
                        <span className="pill ok">
                          Discharged {fmtDate(c.discharge_date)} — retained until {fmtDate(clock.purge_after)}
                        </span>
                      )
                    ) : (
                      <span className={`pill ${state.cls}`}>{state.label}</span>
                    )}
                  </td>
                  <td className="caption wrap">
                    {list
                      .filter((i) => i.status !== 'missing')
                      .map((i) => `${ITEM_LABELS[i.item_type] ?? i.item_type}${i.status === 'provided' ? '' : ` (${i.status.replace(/_/g, ' ')})`}`)
                      .join(' · ')}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </>
  );
}

/** s. 35: the immunisation register — immunised per the local medical officer
 * of health, a physician/NP-signed medical exemption, a NOTARISED conscience
 * or religious exemption, or "attends school" for school-age children. The
 * form's required fields follow the chosen status; the database enforces the
 * same rules again. */
function ImmunisationCard({
  centreId,
  children,
  missing,
  onDone,
}: {
  centreId: string;
  children: Child[];
  missing: Child[];
  onDone: () => void;
}) {
  const { personId } = useConsole();
  const [childId, setChildId] = useState('');
  const [status, setStatus] = useState('immunised');
  const [detail, setDetail] = useState('');
  const [practitioner, setPractitioner] = useState('');
  const [notarisedOn, setNotarisedOn] = useState('');
  const [pin, setPin] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  async function submit() {
    setNotice(null);
    const { error } = await getSupabase().rpc('record_immunisation', {
      p_centre: centreId,
      p_child: childId,
      p_status: status,
      p_detail: detail,
      p_practitioner: practitioner,
      p_notarised_on: notarisedOn || null,
      p_recorder: personId,
      p_pin: pin,
    });
    if (error) {
      setNotice(error.message);
      return;
    }
    setNotice('Recorded — the register keeps the full history.');
    setDetail('');
    setPractitioner('');
    setNotarisedOn('');
    setPin('');
    onDone();
  }

  return (
    <section className="card">
      <h2>Immunisation (s. 35)</h2>
      {missing.length > 0 ? (
        <p>
          <span className="pill due">Due</span> {missing.length} enrolled child{missing.length === 1 ? ' has' : 'ren have'}{' '}
          no immunisation record or exemption on file:{' '}
          <span className="muted">{missing.map((c) => c.full_name).join(', ')}</span>
        </p>
      ) : (
        <p className="muted">Every enrolled child has an immunisation record, an exemption form, or attends school.</p>
      )}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, alignItems: 'end' }}>
        <label>
          Child
          <select value={childId} onChange={(e) => setChildId(e.target.value)}>
            <option value="">Choose…</option>
            {children.map((c) => <option key={c.id} value={c.id}>{c.full_name}</option>)}
          </select>
        </label>
        <label>
          Status
          <select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="immunised">Immunised (record on file)</option>
            <option value="medical_exemption">Medical exemption (physician/NP)</option>
            <option value="conscience_exemption">Conscience/religious exemption (notarised)</option>
            <option value="attends_school">Attends school</option>
          </select>
        </label>
        <label style={{ minWidth: 220 }}>
          What is on file
          <input value={detail} onChange={(e) => setDetail(e.target.value)} placeholder="Record per Toronto Public Health schedule…" />
        </label>
        {status === 'medical_exemption' ? (
          <label>
            Signed by (physician / NP)
            <input value={practitioner} onChange={(e) => setPractitioner(e.target.value)} placeholder="Dr. …" />
          </label>
        ) : null}
        {status === 'conscience_exemption' ? (
          <label>
            Notarised on
            <input type="date" value={notarisedOn} onChange={(e) => setNotarisedOn(e.target.value)} />
          </label>
        ) : null}
        <label className="inline">
          Staff PIN
          <input type="password" inputMode="numeric" value={pin} onChange={(e) => setPin(e.target.value)} maxLength={6} autoComplete="off" />
        </label>
        <button type="button" onClick={() => void submit()}>Record</button>
      </div>
      {notice ? <p className="muted">{notice}</p> : null}
    </section>
  );
}
