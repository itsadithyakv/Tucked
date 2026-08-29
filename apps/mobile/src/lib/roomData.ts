/**
 * Room-mode data: today's roster, attendance state, shifts, sleep state —
 * plus the evacuation cache, refreshed opportunistically and read with ZERO
 * network by the evacuation screen (s. 72(3): attendance must work off-site).
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import type { AgeGroupId } from '@tucked/domain';
import { supabase } from './supabase';

const EVAC_KEY = 'tucked.cache.evacuation.v1';

export interface CentreInfo {
  id: string;
  name: string;
  timezone: string;
  opens_at: string;
  closes_at: string;
  sleep_check_interval_minutes: number;
  safe_arrival_cutoff: string;
}

export interface RoomInfo {
  id: string;
  name: string;
  preset: AgeGroupId;
}

export interface ChildRow {
  id: string;
  full_name: string;
  date_of_birth: string;
  current_room_id: string | null;
}

export interface AttendanceRow {
  child_id: string;
  room_id: string | null;
  event_type: 'arrive' | 'depart' | 'absent' | 'room_transfer';
  actual_time: string;
}

export interface ShiftRow {
  person_id: string;
  room_id: string | null;
  counted_in_ratio: boolean;
  out_at: string | null;
  person: { full_name: string } | null;
}

export interface CareLogRow {
  child_id: string;
  log_type: string;
  logged_at: string;
}

export interface SafeArrivalRow {
  child_id: string;
  resolved_at: string | null;
}

export interface RoomDay {
  centre: CentreInfo;
  rooms: RoomInfo[];
  children: ChildRow[];
  attendance: AttendanceRow[];
  shifts: ShiftRow[];
  sleepLogs: CareLogRow[];
  safeChecks: SafeArrivalRow[];
  staff: { personId: string; fullName: string; role: string }[];
}

export async function loadRoomDay(): Promise<RoomDay | null> {
  const today = new Date().toISOString().slice(0, 10);
  const { data: centre } = await supabase
    .from('centre')
    .select('id, name, timezone, opens_at, closes_at, sleep_check_interval_minutes, safe_arrival_cutoff')
    .limit(1)
    .maybeSingle();
  if (!centre) return null;
  const [rooms, children, attendance, shifts, sleepLogs, safeChecks, staffRoles] = await Promise.all([
    supabase
      .from('room')
      .select('id, name, age_group:age_group_id(preset)')
      .eq('centre_id', centre.id)
      .order('name'),
    supabase
      .from('child')
      .select('id, full_name, date_of_birth, current_room_id')
      .eq('centre_id', centre.id)
      .is('discharge_date', null)
      .order('full_name'),
    supabase
      .from('attendance_event')
      .select('child_id, room_id, event_type, actual_time')
      .eq('centre_id', centre.id)
      .eq('attendance_date', today)
      .order('actual_time'),
    supabase
      .from('staff_shift')
      .select('person_id, room_id, counted_in_ratio, out_at, person:person_id(full_name)')
      .eq('centre_id', centre.id)
      .eq('shift_date', today),
    supabase
      .from('care_log')
      .select('child_id, log_type, logged_at')
      .eq('centre_id', centre.id)
      .eq('log_date', today)
      .in('log_type', ['nap_start', 'nap_end', 'sleep_check'])
      .order('logged_at'),
    supabase
      .from('safe_arrival_check')
      .select('child_id, resolved_at')
      .eq('centre_id', centre.id)
      .eq('check_date', today),
    supabase
      .from('person_role')
      .select('role, person:person_id(id, full_name)')
      .eq('centre_id', centre.id)
      .eq('active', true)
      .in('role', ['supervisor', 'designate', 'rece', 'staff']),
  ]);
  return {
    centre,
    rooms: ((rooms.data as never as { id: string; name: string; age_group: { preset: AgeGroupId } | null }[]) ?? []).map(
      (r) => ({ id: r.id, name: r.name, preset: r.age_group?.preset ?? 'preschool' }),
    ),
    children: children.data ?? [],
    attendance: (attendance.data as AttendanceRow[]) ?? [],
    shifts: (shifts.data as never as ShiftRow[]) ?? [],
    sleepLogs: (sleepLogs.data as CareLogRow[]) ?? [],
    safeChecks: (safeChecks.data as SafeArrivalRow[]) ?? [],
    staff: ((staffRoles.data as never as { role: string; person: { id: string; full_name: string } | null }[]) ?? [])
      .filter((r) => r.person)
      .map((r) => ({ personId: r.person!.id, fullName: r.person!.full_name, role: r.role })),
  };
}

/** Present child ids per room, replayed from the day's events in order. */
export function presentByRoom(attendance: AttendanceRow[]): Map<string, Set<string>> {
  const byRoom = new Map<string, Set<string>>();
  for (const e of attendance) {
    if (e.event_type === 'arrive' || e.event_type === 'room_transfer') {
      for (const set of byRoom.values()) set.delete(e.child_id);
      if (e.room_id) byRoom.set(e.room_id, (byRoom.get(e.room_id) ?? new Set()).add(e.child_id));
    } else if (e.event_type === 'depart' && e.room_id) {
      byRoom.get(e.room_id)?.delete(e.child_id);
    }
  }
  return byRoom;
}

// ── evacuation cache ────────────────────────────────────────────────────────

export interface EvacChild {
  id: string;
  fullName: string;
  roomName: string;
  present: boolean;
  allergies: string[];
  medications: string[];
  contacts: { name: string; phone: string | null; relationship: string }[];
}

export interface EvacCache {
  centreName: string;
  refreshedAt: string;
  children: EvacChild[];
}

export async function refreshEvacuationCache(day: RoomDay): Promise<EvacCache> {
  const [items, meds, members] = await Promise.all([
    supabase
      .from('child_record_item')
      .select('child_id, item_type, content')
      .eq('centre_id', day.centre.id)
      .in('item_type', ['health_immunisation', 'emergency_contact']),
    supabase
      .from('medication_authorisation')
      .select('child_id, drug_name, kind')
      .eq('centre_id', day.centre.id)
      .is('revoked_at', null),
    supabase
      .from('household_member')
      .select('household_id, relationship, person:person_id(full_name, phone)')
      .eq('centre_id', day.centre.id)
      .is('revoked_at', null),
  ]);
  const { data: links } = await supabase
    .from('child_household')
    .select('child_id, household_id')
    .eq('centre_id', day.centre.id);

  const presentSet = new Set<string>();
  for (const set of presentByRoom(day.attendance).values()) for (const id of set) presentSet.add(id);
  const roomName = new Map(day.rooms.map((r) => [r.id, r.name]));
  const membersByHousehold = new Map<string, { name: string; phone: string | null; relationship: string }[]>();
  for (const m of (members.data as never as { household_id: string; relationship: string; person: { full_name: string; phone: string | null } | null }[]) ?? []) {
    if (!m.person) continue;
    const list = membersByHousehold.get(m.household_id) ?? [];
    list.push({ name: m.person.full_name, phone: m.person.phone, relationship: m.relationship });
    membersByHousehold.set(m.household_id, list);
  }

  const cache: EvacCache = {
    centreName: day.centre.name,
    refreshedAt: new Date().toISOString(),
    children: day.children.map((ch) => {
      const health = (items.data ?? []).find(
        (i) => i.child_id === ch.id && i.item_type === 'health_immunisation',
      );
      const allergies = ((health?.content as { allergies?: string[] } | null)?.allergies ?? []).filter(Boolean);
      return {
        id: ch.id,
        fullName: ch.full_name,
        roomName: ch.current_room_id ? (roomName.get(ch.current_room_id) ?? '—') : '—',
        present: presentSet.has(ch.id),
        allergies,
        medications: (meds.data ?? []).filter((m) => m.child_id === ch.id).map((m) => m.drug_name),
        contacts: ((links?.filter((l) => l.child_id === ch.id) ?? []) as { household_id: string }[])
          .flatMap((l) => membersByHousehold.get(l.household_id) ?? [])
          .slice(0, 3),
      };
    }),
  };
  try {
    await AsyncStorage.setItem(EVAC_KEY, JSON.stringify(cache));
  } catch {
    /* cache write best-effort; the last good cache stays */
  }
  return cache;
}

export async function readEvacuationCache(): Promise<EvacCache | null> {
  try {
    const raw = await AsyncStorage.getItem(EVAC_KEY);
    return raw ? (JSON.parse(raw) as EvacCache) : null;
  } catch {
    return null;
  }
}
