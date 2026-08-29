/**
 * Province and room presets — build prompt §5.
 * The province preset changes the age-group table, retention periods, forms,
 * terminology and language. Ontario is live; Manitoba and Quebec are typed
 * stubs so the shape exists from day one.
 * Room presets change which care-log types the room device offers.
 */

import type { AgeGroupId } from './ageGroups';

export type Province = 'ON' | 'MB' | 'QC';

export interface ProvincePreset {
  province: Province;
  implemented: boolean;
  language: 'en-CA' | 'fr-CA';
  retentionYears: { childrensRecord: number; attendance: number; financial: number };
  regulatorName: string;
  seriousOccurrenceSystem: string | null;
}

export const PROVINCE_PRESETS: Record<Province, ProvincePreset> = {
  ON: {
    province: 'ON',
    implemented: true,
    language: 'en-CA',
    retentionYears: { childrensRecord: 3, attendance: 3, financial: 6 },
    regulatorName: 'Ontario Ministry of Education',
    seriousOccurrenceSystem: 'CCLS',
  },
  MB: {
    province: 'MB',
    implemented: false, // Phase 3 — attendance retention 2 years, different forms
    language: 'en-CA',
    retentionYears: { childrensRecord: 2, attendance: 2, financial: 6 },
    regulatorName: 'Manitoba Early Learning and Child Care',
    seriousOccurrenceSystem: null,
  },
  QC: {
    province: 'QC',
    implemented: false, // Phase 3 — French-first, Law 25 workflows
    language: 'fr-CA',
    retentionYears: { childrensRecord: 3, attendance: 3, financial: 6 },
    regulatorName: 'Ministère de la Famille',
    seriousOccurrenceSystem: null,
  },
};

export const CARE_LOG_TYPES = [
  'meal',
  'bottle',
  'nap_start',
  'nap_end',
  'sleep_check',
  'diaper',
  'toilet',
  'outdoor',
  'health_observation',
  'activity',
  'note',
  'photo',
] as const;

export type CareLogType = (typeof CARE_LOG_TYPES)[number];

export interface RoomPreset {
  ageGroupId: AgeGroupId;
  careLogTypes: readonly CareLogType[];
  /** Timed direct-visual sleep checks (s. 33.1) prompted by the room device. */
  timedSleepChecks: boolean;
  /** Back-to-sleep rule surface (under 12 months). */
  backToSleep: boolean;
  /** Toddler/preschool rest period cap in minutes (s. 33.1: no longer than 2 h). */
  restMaxMinutes: number | null;
  /** Kindergarten/school-age before/after programs: no naps. */
  beforeAfterOnly: boolean;
}

const COMMON: readonly CareLogType[] = [
  'meal',
  'outdoor',
  'health_observation',
  'activity',
  'note',
  'photo',
];

export const ROOM_PRESETS: Record<AgeGroupId, RoomPreset> = {
  infant: {
    ageGroupId: 'infant',
    careLogTypes: [...COMMON, 'bottle', 'diaper', 'nap_start', 'nap_end', 'sleep_check'],
    timedSleepChecks: true,
    backToSleep: true,
    restMaxMinutes: null,
    beforeAfterOnly: false,
  },
  toddler: {
    ageGroupId: 'toddler',
    careLogTypes: [...COMMON, 'diaper', 'toilet', 'nap_start', 'nap_end', 'sleep_check'],
    timedSleepChecks: true, // for children under 24 months in the room
    backToSleep: false,
    restMaxMinutes: 120,
    beforeAfterOnly: false,
  },
  preschool: {
    ageGroupId: 'preschool',
    careLogTypes: [...COMMON, 'toilet', 'nap_start', 'nap_end'],
    timedSleepChecks: false,
    backToSleep: false,
    restMaxMinutes: 120,
    beforeAfterOnly: false,
  },
  kindergarten: {
    ageGroupId: 'kindergarten',
    careLogTypes: COMMON,
    timedSleepChecks: false,
    backToSleep: false,
    restMaxMinutes: null,
    beforeAfterOnly: true,
  },
  primary_junior: {
    ageGroupId: 'primary_junior',
    careLogTypes: COMMON,
    timedSleepChecks: false,
    backToSleep: false,
    restMaxMinutes: null,
    beforeAfterOnly: true,
  },
  junior: {
    ageGroupId: 'junior',
    careLogTypes: COMMON,
    timedSleepChecks: false,
    backToSleep: false,
    restMaxMinutes: null,
    beforeAfterOnly: true,
  },
  family: {
    ageGroupId: 'family',
    careLogTypes: [...COMMON, 'bottle', 'diaper', 'toilet', 'nap_start', 'nap_end', 'sleep_check'],
    timedSleepChecks: true, // under-24-month rules apply per child
    backToSleep: true,
    restMaxMinutes: 120,
    beforeAfterOnly: false,
  },
};

/**
 * s. 33.1: direct visual sleep checks are required for every sleeping child
 * UNDER 24 MONTHS in infant, toddler or family groups — a per-child rule, not
 * a per-room one. Enforced again at the database layer.
 */
export function sleepCheckRequired(ageMonths: number, roomAgeGroup: AgeGroupId): boolean {
  if (ageMonths >= 24) return false;
  return roomAgeGroup === 'infant' || roomAgeGroup === 'toddler' || roomAgeGroup === 'family';
}
