'use client';

/** s. 72(1): the children's record checklist — every item's status per child,
 * never blank, with supervisor verification state. */

import { useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { useConsole } from '@/lib/console';

interface Child {
  id: string;
  full_name: string;
  date_of_birth: string;
  room: { name: string } | null;
}

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

  useEffect(() => {
    const sb = getSupabase();
    sb.from('child')
      .select('id, full_name, date_of_birth, room:current_room_id(name)')
      .eq('centre_id', centre.id)
      .order('full_name')
      .then(({ data }) => setChildren((data as never) ?? []));
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

  return (
    <>
      <h1>Children&apos;s records</h1>
      <div className="card">
        <table>
          <thead>
            <tr>
              <th>Child</th>
              <th>Room</th>
              <th>Born</th>
              <th>Record</th>
              <th>Items</th>
            </tr>
          </thead>
          <tbody>
            {children.map((c) => {
              const state = recordState(c.id);
              const list = items.get(c.id) ?? [];
              return (
                <tr key={c.id}>
                  <td>{c.full_name}</td>
                  <td>{c.room?.name ?? '—'}</td>
                  <td>{c.date_of_birth}</td>
                  <td>
                    <span className={`pill ${state.cls}`}>{state.label}</span>
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
