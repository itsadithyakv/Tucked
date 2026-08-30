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
  BookMarked,
  BookOpen,
  CalendarCheck,
  DoorOpen,
  UtensilsCrossed,
  HeartPulse,
  Home,
  LogOut,
  Menu,
  MessageCircle,
  Moon,
  PanelLeftClose,
  PanelLeftOpen,
  Pill,
  Receipt,
  Siren,
  Stethoscope,
  Sun,
  Users,
  UserPlus,
} from 'lucide-react';
import { enCA } from '@tucked/domain';
import { getSupabase } from '@/lib/supabase';
import { ConsoleProvider, useConsole } from '@/lib/console';
import { Sparkles, clickPulse, sparkleBurst } from '@/ui/sparkles';

/** One fixed icon per regulated concept (design-language §8). */
const NAV = [
  { href: '/', label: 'Today', Icon: Home },
  { href: '/attendance', label: 'Attendance', Icon: DoorOpen },
  { href: '/daily-record', label: 'Daily written record', Icon: BookOpen },
  { href: '/accidents', label: 'Accident reports', Icon: Bandage },
  { href: '/serious-occurrences', label: 'Serious occurrences', Icon: Siren },
  { href: '/plans', label: 'Plans & allergies', Icon: HeartPulse },
  { href: '/illness', label: 'Illness & exclusions', Icon: Stethoscope },
  { href: '/menus', label: 'Menus', Icon: UtensilsCrossed },
  { href: '/outdoor', label: 'Outdoor play', Icon: Sun },
  { href: '/medication', label: 'Medication', Icon: Pill },
  { href: '/sleep-checks', label: 'Sleep checks', Icon: Moon },
  { href: '/children', label: "Children's records", Icon: Users },
  { href: '/messages', label: 'Messages', Icon: MessageCircle },
  { href: '/staff', label: 'Staff files', Icon: BadgeCheck },
  { href: '/fees', label: 'Fees & receipts', Icon: Receipt },
  { href: '/handbook', label: 'Parent handbook', Icon: BookMarked },
  { href: '/waitlist', label: 'Waiting list', Icon: UserPlus },
  { href: '/compliance', label: 'Compliance calendar', Icon: CalendarCheck },
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

  // Every click blooms a soft pulse; interactive things add sparkles — small
  // for everyday taps, a full burst for primary presses. Serious zones (Now
  // content) and text fields stay quiet, and the helpers refuse to spawn
  // under prefers-reduced-motion.
  useEffect(() => {
    function onClick(e: MouseEvent) {
      const el = e.target instanceof Element ? e.target : null;
      if (!el) return;
      if (el.closest('input, textarea, select, .backdrop')) return;
      clickPulse(e.clientX, e.clientY);
      const card = el.closest('.card, section');
      const serious = card?.querySelector('.pill.now') != null;
      if (serious) return;
      const button = el.closest('button');
      if (button && !button.matches('.quiet, .side-toggle, .side-signout, .menu-button')) {
        sparkleBurst(e.clientX, e.clientY, 8);
      } else if (el.closest('a, button, .tile, [role="button"]')) {
        sparkleBurst(e.clientX, e.clientY, 4);
      }
    }
    document.addEventListener('click', onClick);
    return () => document.removeEventListener('click', onClick);
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
        <Sparkles count={3}>
          <Image className="mark" src="/tucked-mark.png" alt="Tucked" width={96} height={96} priority />
        </Sparkles>
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
