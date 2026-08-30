import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import type { Session } from '@supabase/supabase-js';
import { registerForPush } from './push';
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
  /** A supervisor can also be a parent: both role kinds present. */
  dualRole: boolean;
}

interface AuthState {
  session: Session | null;
  profile: Profile | null;
  loading: boolean;
  /** Dual-role people can switch views; persisted per device. */
  viewMode: 'room' | 'family' | null;
  setViewMode: (mode: 'room' | 'family') => void;
}

const VIEW_KEY = 'tucked.viewMode.v1';

const AuthContext = createContext<AuthState>({
  session: null,
  profile: null,
  loading: true,
  viewMode: null,
  setViewMode: () => {},
});

export function AuthProvider({ children }: { children: ReactNode }) {
  const [base, setBase] = useState<{ session: Session | null; profile: Profile | null; loading: boolean }>({
    session: null,
    profile: null,
    loading: true,
  });
  const [viewMode, setViewModeState] = useState<'room' | 'family' | null>(null);

  useEffect(() => {
    AsyncStorage.getItem(VIEW_KEY)
      .then((v) => {
        if (v === 'room' || v === 'family') setViewModeState(v);
      })
      .catch(() => {});
  }, []);

  const setViewMode = useCallback((mode: 'room' | 'family') => {
    setViewModeState(mode);
    AsyncStorage.setItem(VIEW_KEY, mode).catch(() => {});
  }, []);

  useEffect(() => {
    let cancelled = false;

    async function loadProfile(session: Session | null) {
      if (!session) {
        if (!cancelled) setBase({ session: null, profile: null, loading: false });
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
      const hasWork = roleRows.some((r) => r.role !== 'family_adult');
      const hasFamily = roleRows.some((r) => r.role === 'family_adult');
      const profile: Profile | null = person
        ? {
            personId: person.id,
            fullName: person.full_name,
            roles: roleRows,
            mode: hasWork ? 'room' : 'family',
            dualRole: hasWork && hasFamily,
          }
        : null;
      if (!cancelled) setBase({ session, profile, loading: false });
      if (profile) void registerForPush(profile.personId);
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

  // The override only applies to people who genuinely hold both role kinds.
  const profile = base.profile
    ? {
        ...base.profile,
        mode:
          base.profile.dualRole && viewMode ? viewMode : base.profile.mode,
      }
    : null;

  return (
    <AuthContext.Provider value={{ ...base, profile, viewMode, setViewMode }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthState {
  return useContext(AuthContext);
}
