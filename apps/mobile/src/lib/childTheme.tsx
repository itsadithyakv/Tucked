/**
 * Per-child identity themes: parents rarely have more than five enrolled, so
 * each child owns one of five contrast-checked pastel worlds (Ivan is
 * sunshine, Lilly is blossom…) — assigned by stable alphabetical order, so
 * the colour never changes between sessions. Deep-on-wash all ≥ 4.5:1.
 */

import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { Platform } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as Haptics from 'expo-haptics';
import { useAuth } from './auth';
import { supabase } from './supabase';

export interface ChildTheme {
  name: string;
  wash: string;
  deep: string;
}

export const CHILD_THEMES: ChildTheme[] = [
  { name: 'sunshine', wash: '#FBE7B8', deep: '#8A5A00' },
  { name: 'blossom', wash: '#F8D7E5', deep: '#9C2F5E' },
  { name: 'sky', wash: '#CFE2FA', deep: '#1C5AB5' },
  { name: 'meadow', wash: '#C9EAD7', deep: '#177243' },
  { name: 'lilac', wash: '#E4DBF8', deep: '#5B3E9E' },
];

export interface ThemedChild {
  id: string;
  fullName: string;
  firstName: string;
  roomName: string | null;
  theme: ChildTheme;
}

interface FamilyCtx {
  children: ThemedChild[];
  selected: ThemedChild | null;
  /** True once the household list has actually loaded (guards empty states). */
  ready: boolean;
  select: (id: string) => void;
  /** Instagram-style: a quick double-tap jumps to the next child. */
  cycle: () => void;
  refresh: () => void;
}

const Ctx = createContext<FamilyCtx>({
  children: [],
  selected: null,
  ready: false,
  select: () => {},
  cycle: () => {},
  refresh: () => {},
});

const SELECTED_KEY = 'tucked.selectedChild.v1';

export function FamilyProvider({ children: node }: { children: ReactNode }) {
  const { profile } = useAuth();
  const personId = profile?.personId ?? null;
  const [kids, setKids] = useState<ThemedChild[]>([]);
  const [ready, setReady] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // The family surface shows YOUR household's children only — never the whole
  // centre, even for dual-role staff whose RLS can see every child.
  const refresh = useCallback(() => {
    if (!personId) return;
    void (async () => {
      const { data: memberships } = await supabase
        .from('household_member')
        .select('household_id')
        .eq('person_id', personId)
        .is('revoked_at', null);
      const householdIds = (memberships ?? []).map((m) => m.household_id as string);
      if (householdIds.length === 0) {
        setKids([]);
        setReady(true);
        return;
      }
      const { data } = await supabase
        .from('child_household')
        .select('child:child_id(id, full_name, room:current_room_id(name))')
        .in('household_id', householdIds);
      const rows = ((data as never as { child: { id: string; full_name: string; room: { name: string } | null } | null }[]) ?? [])
        .map((r) => r.child)
        .filter((c): c is NonNullable<typeof c> => c !== null);
      const unique = [...new Map(rows.map((c) => [c.id, c])).values()].sort((a, b) =>
        a.full_name.localeCompare(b.full_name),
      );
      setKids(
        unique.map((r, i) => ({
          id: r.id,
          fullName: r.full_name,
          firstName: r.full_name.split(' ')[0]!,
          roomName: r.room?.name ?? null,
          theme: CHILD_THEMES[i % CHILD_THEMES.length]!,
        })),
      );
      setReady(true);
    })();
  }, [personId]);

  useEffect(refresh, [refresh]);

  useEffect(() => {
    AsyncStorage.getItem(SELECTED_KEY)
      .then((v) => {
        if (v) setSelectedId(v);
      })
      .catch(() => {});
  }, []);

  const select = useCallback((id: string) => {
    setSelectedId(id);
    if (Platform.OS !== 'web') {
      void Haptics.selectionAsync().catch(() => {});
    }
    AsyncStorage.setItem(SELECTED_KEY, id).catch(() => {});
  }, []);

  const selected = kids.find((k) => k.id === selectedId) ?? kids[0] ?? null;

  const cycle = useCallback(() => {
    if (kids.length < 2 || !selected) return;
    const idx = kids.findIndex((k) => k.id === selected.id);
    select(kids[(idx + 1) % kids.length]!.id);
  }, [kids, selected, select]);

  return (
    <Ctx.Provider value={{ children: kids, selected, ready, select, cycle, refresh }}>
      {node}
    </Ctx.Provider>
  );
}

export function useFamily(): FamilyCtx {
  return useContext(Ctx);
}

/** Double-tap detector for the switcher avatar: two taps within 300 ms
 * cycles to the next child; a single tap (after the window) opens the picker. */
export function useTapOrDoubleTap(onSingle: () => void, onDouble: () => void) {
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  return () => {
    if (timer.current) {
      clearTimeout(timer.current);
      timer.current = null;
      onDouble();
    } else {
      timer.current = setTimeout(() => {
        timer.current = null;
        onSingle();
      }, 300);
    }
  };
}
