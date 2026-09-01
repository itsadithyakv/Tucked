'use client';

/** s. 75.1: a family learns where it stands without learning anything about
 * any other child or family. No account, no sign-in — an enquiring family is
 * not a user of ours, and making them create one to see a number would be the
 * "ask your administrator" pattern in another costume. The code is the whole
 * of the authorisation, and the answer is one row about them. */

import { useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { ThemeToggle } from '@/ui/ThemeToggle';

interface Position {
  centre_name: string;
  child_first_name: string;
  age_group: string;
  status: string;
  list_position: number;
  families_ahead: number;
  list_length: number;
  joined_on: string;
  desired_start_on: string;
  respond_by: string | null;
}

const GROUP_LABEL: Record<string, string> = {
  infant: 'infant',
  toddler: 'toddler',
  preschool: 'preschool',
  kindergarten: 'kindergarten',
  primary_junior: 'primary/junior',
  junior: 'junior',
  family: 'family age',
};

function fmt(iso: string): string {
  return new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString('en-CA', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  });
}

export default function WaitingListPage() {
  const [code, setCode] = useState('');
  const [result, setResult] = useState<Position | null>(null);
  const [notFound, setNotFound] = useState(false);
  const [busy, setBusy] = useState(false);

  async function check() {
    setBusy(true);
    setNotFound(false);
    setResult(null);
    const { data } = await getSupabase().rpc('waitlist_self_check', { p_code: code });
    const rows = (data as Position[]) ?? [];
    setResult(rows[0] ?? null);
    setNotFound(rows.length === 0);
    setBusy(false);
  }

  return (
    <main style={{ maxWidth: 620, margin: '0 auto', padding: '48px 20px' }}>
      <div className="top-bar">
        <ThemeToggle />
      </div>
      <h1>Your place on the waiting list</h1>
      <section className="card">
        <p className="muted">
          Enter the code your centre gave you. It shows you your own position and nothing about any
          other family — and it costs nothing to be on the list.
        </p>
        <form
          onSubmit={(e) => {
            e.preventDefault();
            void check();
          }}
          style={{ display: 'flex', gap: 8, alignItems: 'end', flexWrap: 'wrap' }}
        >
          <label style={{ flex: 1, minWidth: 220 }}>
            Your code
            <input
              value={code}
              onChange={(e) => setCode(e.target.value)}
              placeholder="A1B2-C3D4"
              autoComplete="off"
              spellCheck={false}
            />
          </label>
          <button type="submit" disabled={busy || code.trim().length === 0}>
            {busy ? 'Checking…' : 'Check my place'}
          </button>
        </form>
      </section>

      {notFound ? (
        <section className="card">
          <p>
            We could not find that code. Check it against the one your centre gave you — or call
            them and they will read it out again.
          </p>
        </section>
      ) : null}

      {result ? (
        <section className="card">
          <h2>
            {result.child_first_name} is number {result.list_position} on the{' '}
            {GROUP_LABEL[result.age_group] ?? result.age_group} list
          </h2>
          <p>
            {result.families_ahead === 0
              ? 'There is nobody ahead of you.'
              : `${result.families_ahead} ${result.families_ahead === 1 ? 'family is' : 'families are'} ahead of you, out of ${result.list_length} waiting.`}
          </p>
          {result.status === 'offered' ? (
            <p>
              <span className="pill now">A place has been offered</span>{' '}
              {result.respond_by
                ? `Please let ${result.centre_name} know by ${fmt(result.respond_by)}.`
                : ''}
            </p>
          ) : null}
          <p className="muted">
            On the list at {result.centre_name} since {fmt(result.joined_on)}, hoping to start{' '}
            {fmt(result.desired_start_on)}.
          </p>
          <p className="muted">
            Places are offered in the order set out in the centre&apos;s waiting-list policy, which
            is in the parent handbook. A position can move when a family ahead of you takes a place
            or withdraws, or when a child with priority under that policy joins.
          </p>
        </section>
      ) : null}

      <p className="caption" style={{ marginTop: 24 }}>
        There is never a fee or a deposit to be placed on a waiting list in Ontario (O. Reg. 137/15,
        s. 75.1). If you are asked for one, you do not have to pay it.
      </p>
    </main>
  );
}
