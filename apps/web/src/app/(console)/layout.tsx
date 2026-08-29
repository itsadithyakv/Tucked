'use client';

import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { Session } from '@supabase/supabase-js';
import { enCA } from '@tucked/domain';
import { getSupabase } from '@/lib/supabase';
import { ConsoleProvider, useConsole } from '@/lib/console';

const NAV = [
  { href: '/', label: 'Today' },
  { href: '/attendance', label: 'Attendance' },
  { href: '/daily-record', label: 'Daily written record' },
  { href: '/accidents', label: 'Accident reports' },
  { href: '/medication', label: 'Medication' },
  { href: '/sleep-checks', label: 'Sleep checks' },
  { href: '/children', label: "Children's records" },
  { href: '/staff', label: 'Staff files' },
];

function Shell({ children }: { children: ReactNode }) {
  const { centre, fullName } = useConsole();
  const pathname = usePathname();
  return (
    <div className="console">
      <aside>
        <h1 className="brand">{centre.name}</h1>
        <p className="caption">Licence {centre.licence_number}</p>
        <nav>
          {NAV.map((item) => (
            <Link key={item.href} href={item.href} aria-current={pathname === item.href ? 'page' : undefined}>
              {item.label}
            </Link>
          ))}
        </nav>
        <div className="aside-foot">
          <p className="caption">{fullName}</p>
          <button className="quiet" onClick={() => getSupabase().auth.signOut()}>
            {enCA.auth.signOut}
          </button>
        </div>
      </aside>
      <main>{children}</main>
    </div>
  );
}

export default function ConsoleLayout({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    const sb = getSupabase();
    sb.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setReady(true);
    });
    const { data: sub } = sb.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => sub.subscription.unsubscribe();
  }, []);

  async function signIn(e: React.FormEvent) {
    e.preventDefault();
    setNotice(null);
    const { error } = await getSupabase().auth.signInWithPassword({ email: email.trim(), password });
    if (error) setNotice(enCA.errors.signInFailed);
  }

  if (!ready) return <main />;

  if (!session) {
    return (
      <main className="signin">
        <h1>Tucked console</h1>
        <form className="card" onSubmit={signIn}>
          <h2>{enCA.auth.staffSignInTitle}</h2>
          <label>
            Email
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="username" required />
          </label>
          <label>
            Password
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required />
          </label>
          <button type="submit">{enCA.auth.staffSignInAction}</button>
          {notice ? <p className="muted">{notice}</p> : null}
        </form>
        <p className="caption">Demo: supervisor@mapleleaf.example · tucked-demo (local stack only)</p>
      </main>
    );
  }

  return (
    <ConsoleProvider session={session}>
      <Shell>{children}</Shell>
    </ConsoleProvider>
  );
}
