import { createContext, useContext, useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from './supabase';

export interface RoleRow {
  role: string;
  centre_id: string;
  qualified: boolean;
}

export interface Profile {
  personId: string;
  fullName: string;
  roles: RoleRow[];
  /** 'room' when any workforce role exists, else 'family'. */
  mode: 'room' | 'family';
}

interface AuthState {
  session: Session | null;
  profile: Profile | null;
  loading: boolean;
}

const AuthContext = createContext<AuthState>({ session: null, profile: null, loading: true });

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({ session: null, profile: null, loading: true });

  useEffect(() => {
    let cancelled = false;

    async function loadProfile(session: Session | null) {
      if (!session) {
        if (!cancelled) setState({ session: null, profile: null, loading: false });
        return;
      }
      const { data: person } = await supabase
        .from('person')
        .select('id, full_name')
        .eq('auth_user_id', session.user.id)
        .maybeSingle();
      const { data: roles } = person
        ? await supabase
            .from('person_role')
            .select('role, centre_id, qualified')
            .eq('person_id', person.id)
            .eq('active', true)
        : { data: [] };
      const roleRows: RoleRow[] = roles ?? [];
      const profile: Profile | null = person
        ? {
            personId: person.id,
            fullName: person.full_name,
            roles: roleRows,
            mode: roleRows.some((r) => r.role !== 'family_adult') ? 'room' : 'family',
          }
        : null;
      if (!cancelled) setState({ session, profile, loading: false });
    }

    supabase.auth.getSession().then(({ data }) => loadProfile(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      loadProfile(session);
    });
    return () => {
      cancelled = true;
      sub.subscription.unsubscribe();
    };
  }, []);

  return <AuthContext.Provider value={state}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthState {
  return useContext(AuthContext);
}
