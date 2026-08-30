'use client';

/** Platform admin shell: its own gate (platform_admin by email — no person or
 * centre required), deliberately outside the supervisor console. Admins manage
 * tenancy and billing; the console manages care. The two never mix. */

import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import Image from 'next/image';
import type { Session } from '@supabase/supabase-js';
import { LogOut } from 'lucide-react';
import { getSupabase } from '@/lib/supabase';

export default function AdminLayout({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [isAdmin, setIsAdmin] = useState<boolean | null>(null);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    const sb = getSupabase();
    sb.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setReady(true);
    });
    const { data: sub } = sb.auth.onAuthStateChange((_e, s) => {
      setSession(s);
      setIsAdmin(null);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    if (!session) return;
    getSupabase()
      .rpc('is_platform_admin')
      .then(({ data }) => setIsAdmin(data === true));
  }, [session]);

  async function signIn(e: React.FormEvent) {
    e.preventDefault();
    setNotice(null);
    const { error } = await getSupabase().auth.signInWithPassword({ email: email.trim(), password });
    if (error) setNotice('That sign-in did not work.');
  }

  if (!ready) return <main />;

  if (!session) {
    return (
      <main className="signin">
        <Image className="mark" src="/tucked-mark.png" alt="Tucked" width={96} height={96} priority />
        <form className="card" onSubmit={signIn}>
          <h2>Platform sign in</h2>
          <label>
            Email
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="username" required />
          </label>
          <label>
            Password
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required />
          </label>
          <button type="submit">Sign in</button>
          {notice ? <p className="muted">{notice}</p> : null}
        </form>
        <p className="caption">Founders only — this is the tenancy and billing surface, not a centre console.</p>
      </main>
    );
  }

  if (isAdmin === null) return <main />;

  if (!isAdmin) {
    return (
      <main className="signin">
        <div className="card">
          <h2>Not a platform admin</h2>
          <p className="muted">
            {session.user.email} is not on the platform admin list. Centre staff sign in at the console home page.
          </p>
          <button type="button" onClick={() => getSupabase().auth.signOut()}>
            Sign out
          </button>
        </div>
      </main>
    );
  }

  return (
    <main style={{ maxWidth: 1080, margin: '0 auto', padding: '24px 20px 64px' }}>
        <header style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 8 }}>
          <Image src="/tucked-mark.png" alt="" width={40} height={40} priority />
          <div style={{ flex: 1 }}>
            <h1 style={{ margin: 0 }}>Tucked platform</h1>
            <p className="caption" style={{ margin: 0 }}>{session.user.email}</p>
          </div>
          <button type="button" className="quiet" onClick={() => getSupabase().auth.signOut()}>
            <LogOut size={16} aria-hidden style={{ verticalAlign: '-2px', marginRight: 6 }} />
            Sign out
          </button>
        </header>
        {children}
    </main>
  );
}
