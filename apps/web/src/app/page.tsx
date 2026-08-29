'use client';

import { useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { enCA } from '@tucked/domain';
import { getSupabase } from '@/lib/supabase';

interface CentreRow {
  id: string;
  name: string;
  licence_number: string;
  cwelcc_enrolled: boolean;
}

interface RoomRow {
  id: string;
  name: string;
  child: { count: number }[];
}

/** Phase 0 console: staff sign-in and a placeholder home proving the seeded
 * centre flows through RLS to a supervisor session. */
export default function ConsoleHome() {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [notice, setNotice] = useState<string | null>(null);
  const [centre, setCentre] = useState<CentreRow | null>(null);
  const [rooms, setRooms] = useState<RoomRow[]>([]);
  const [staffCount, setStaffCount] = useState<number | null>(null);

  useEffect(() => {
    getSupabase().auth.getSession().then(({ data }) => {
      setSession(data.session);
      setReady(true);
    });
    const { data: sub } = getSupabase().auth.onAuthStateChange((_e, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session) {
      setCentre(null);
      return;
    }
    getSupabase()
      .from('centre')
      .select('id, name, licence_number, cwelcc_enrolled')
      .limit(1)
      .maybeSingle()
      .then(({ data }) => setCentre(data));
    getSupabase()
      .from('room')
      .select('id, name, child(count)')
      .order('name')
      .then(({ data }) => setRooms((data as unknown as RoomRow[]) ?? []));
    getSupabase()
      .from('person_role')
      .select('id', { count: 'exact', head: true })
      .neq('role', 'family_adult')
      .eq('active', true)
      .then(({ count }) => setStaffCount(count));
  }, [session]);

  async function signIn(e: React.FormEvent) {
    e.preventDefault();
    setNotice(null);
    const { error } = await getSupabase().auth.signInWithPassword({ email: email.trim(), password });
    if (error) setNotice(enCA.errors.signInFailed);
  }

  if (!ready) return <main />;

  if (!session) {
    return (
      <main>
        <h1>Tucked console</h1>
        <form className="card" onSubmit={signIn}>
          <h2>{enCA.auth.staffSignInTitle}</h2>
          <label>
            Email
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              autoComplete="username"
              required
            />
          </label>
          <label>
            Password
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
              required
            />
          </label>
          <button type="submit">{enCA.auth.staffSignInAction}</button>
          {notice ? <p className="muted">{notice}</p> : null}
        </form>
        <p className="caption">
          Demo: supervisor@mapleleaf.example · tucked-demo (local stack only)
        </p>
      </main>
    );
  }

  return (
    <main>
      <h1>{centre ? centre.name : 'Tucked console'}</h1>
      {centre ? (
        <section className="card">
          <h2>{enCA.terms.centre}</h2>
          <p className="muted">Licence {centre.licence_number}</p>
          <p className="muted">{centre.cwelcc_enrolled ? 'Enrolled in CWELCC' : 'Not enrolled in CWELCC'}</p>
          <p className="muted">{staffCount === null ? '' : `${staffCount} workforce roles on file`}</p>
        </section>
      ) : null}
      {rooms.map((room) => (
        <section className="card" key={room.id}>
          <h2>{room.name}</h2>
          <p className="muted">{`${room.child[0]?.count ?? 0} children enrolled`}</p>
        </section>
      ))}
      <button className="quiet" onClick={() => getSupabase().auth.signOut()}>
        {enCA.auth.signOut}
      </button>
    </main>
  );
}
