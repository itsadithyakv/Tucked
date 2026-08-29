'use client';

import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { Session } from '@supabase/supabase-js';
import {
  BadgeCheck,
  Bandage,
  BookOpen,
  DoorOpen,
  Home,
  LogOut,
  Menu,
  Moon,
  PanelLeftClose,
  PanelLeftOpen,
  Pill,
  Users,
} from 'lucide-react';
import { enCA } from '@tucked/domain';
import { getSupabase } from '@/lib/supabase';
import { ConsoleProvider, useConsole } from '@/lib/console';

/** One fixed icon per regulated concept (design-language §8). */
const NAV = [
  { href: '/', label: 'Today', Icon: Home },
  { href: '/attendance', label: 'Attendance', Icon: DoorOpen },
  { href: '/daily-record', label: 'Daily written record', Icon: BookOpen },
  { href: '/accidents', label: 'Accident reports', Icon: Bandage },
  { href: '/medication', label: 'Medication', Icon: Pill },
  { href: '/sleep-checks', label: 'Sleep checks', Icon: Moon },
  { href: '/children', label: "Children's records", Icon: Users },
  { href: '/staff', label: 'Staff files', Icon: BadgeCheck },
];

function readCollapsed(): boolean {
  try {
    return localStorage.getItem('tucked.sidebar') === 'collapsed';
  } catch {
    return false;
  }
}

function Shell({ children }: { children: ReactNode }) {
  const { fullName } = useConsole();
  const pathname = usePathname();
  const [pinned, setPinned] = useState(readCollapsed);
  const [narrow, setNarrow] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);

  // Laptop widths collapse automatically; hovering the rail peeks it open
  // (pure CSS). The pin toggle only exists on wide screens.
  useEffect(() => {
    const mq = window.matchMedia('(max-width: 1599px)');
    const apply = () => setNarrow(mq.matches);
    apply();
    mq.addEventListener('change', apply);
    return () => mq.removeEventListener('change', apply);
  }, []);

  const collapsed = narrow || pinned;

  function toggleCollapsed() {
    setPinned((c) => {
      try {
        localStorage.setItem('tucked.sidebar', c ? 'expanded' : 'collapsed');
      } catch {
        /* storage unavailable — the toggle still works for this visit */
      }
      return !c;
    });
  }

  // the drawer closes itself after navigation on small screens
  useEffect(() => setDrawerOpen(false), [pathname]);

  return (
    <div className={`console${collapsed ? ' collapsed' : ''}${drawerOpen ? ' drawer-open' : ''}`}>
      {drawerOpen ? (
        <button className="backdrop" aria-label="Close menu" onClick={() => setDrawerOpen(false)} />
      ) : null}
      <aside className="sidebar">
        <div className="side-panel">
          <div className="side-brand">
            <Image src="/tucked-mark.png" alt="" width={36} height={36} priority />
            <span className="brand-name">tucked</span>
          </div>
          <nav>
            {NAV.map(({ href, label, Icon }) => (
              <Link
                key={href}
                href={href}
                aria-current={pathname === href ? 'page' : undefined}
                title={collapsed ? label : undefined}
              >
                <Icon aria-hidden />
                <span className="side-label">{label}</span>
              </Link>
            ))}
          </nav>
          <div className="side-foot">
            <p className="side-user">{fullName}</p>
            <button
              type="button"
              className="side-toggle"
              onClick={toggleCollapsed}
              aria-expanded={!collapsed}
              title={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
            >
              {collapsed ? <PanelLeftOpen aria-hidden /> : <PanelLeftClose aria-hidden />}
              <span className="side-label">Collapse</span>
            </button>
            <button type="button" className="side-signout" onClick={() => getSupabase().auth.signOut()}>
              <LogOut aria-hidden />
              <span className="side-label">{enCA.auth.signOut}</span>
            </button>
          </div>
        </div>
      </aside>
      <main>
        <button
          type="button"
          className="menu-button"
          aria-label="Open menu"
          onClick={() => setDrawerOpen(true)}
        >
          <Menu aria-hidden />
        </button>
        {children}
      </main>
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
        <Image className="mark" src="/tucked-mark.png" alt="Tucked" width={96} height={96} priority />
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
