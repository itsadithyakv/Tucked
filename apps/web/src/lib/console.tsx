'use client';

/** Shared console plumbing: session + profile + centre context, formatting. */

import { createContext, useContext, useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { getSupabase } from './supabase';

export interface Centre {
  id: string;
  name: string;
  licence_number: string;
  timezone: string;
  cwelcc_enrolled: boolean;
  safe_arrival_cutoff: string;
}

export interface ConsoleCtx {
  session: Session;
  personId: string;
  fullName: string;
  roles: string[];
  centre: Centre;
}

const Ctx = createContext<ConsoleCtx | null>(null);

export function useConsole(): ConsoleCtx {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error('useConsole outside provider');
  return ctx;
}

export function ConsoleProvider({
  session,
  children,
}: {
  session: Session;
  children: ReactNode;
}) {
  const [ctx, setCtx] = useState<ConsoleCtx | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const sb = getSupabase();
      const { data: person } = await sb
        .from('person')
        .select('id, full_name')
        .eq('auth_user_id', session.user.id)
        .maybeSingle();
      if (!person) return;
      const [{ data: roles }, { data: centre }] = await Promise.all([
        sb.from('person_role').select('role').eq('person_id', person.id).eq('active', true),
        sb
          .from('centre')
          .select('id, name, licence_number, timezone, cwelcc_enrolled, safe_arrival_cutoff')
          .limit(1)
          .maybeSingle(),
      ]);
      if (!cancelled && centre) {
        setCtx({
          session,
          personId: person.id,
          fullName: person.full_name,
          roles: (roles ?? []).map((r) => r.role),
          centre,
        });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [session]);

  if (!ctx) return <main />;
  return <Ctx.Provider value={ctx}>{children}</Ctx.Provider>;
}

/** Staff read 24-hour times in the centre's zone (design-language §9). */
export function fmtTime(iso: string | null, tz: string): string {
  if (!iso) return '—';
  return new Intl.DateTimeFormat('en-CA', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
    timeZone: tz,
  }).format(new Date(iso));
}

export function fmtDate(iso: string | null): string {
  if (!iso) return '—';
  return new Intl.DateTimeFormat('en-CA', { day: 'numeric', month: 'short', year: 'numeric' }).format(
    new Date(`${iso.slice(0, 10)}T12:00:00`),
  );
}
