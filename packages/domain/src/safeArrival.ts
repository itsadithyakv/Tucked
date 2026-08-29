/**
 * Safe arrival (s. 50) and sleep-check scheduling (s. 33.1) — pure timing
 * logic shared by the room device (offline) and the pg_cron sweep.
 */

export interface SafeArrivalInput {
  expectedChildIds: string[]; // enrolled, not discharged, expected today
  arrivedChildIds: string[];
  markedAbsentChildIds: string[];
  alreadyPromptedChildIds: string[];
  /** Minutes since the centre-local midnight. */
  nowMinutes: number;
  cutoffMinutes: number;
}

/** Children staff must be prompted to follow up on: expected, past the
 * cut-off, not arrived, not marked absent, not already being chased. */
export function safeArrivalDue(input: SafeArrivalInput): string[] {
  if (input.nowMinutes < input.cutoffMinutes) return [];
  const seen = new Set([
    ...input.arrivedChildIds,
    ...input.markedAbsentChildIds,
    ...input.alreadyPromptedChildIds,
  ]);
  return input.expectedChildIds.filter((id) => !seen.has(id));
}

export interface SleepCheckState {
  napStartAt: number; // epoch ms
  lastCheckAt: number | null;
  intervalMinutes: number; // from the centre's sleep policy
}

/** When the next direct visual check is due (epoch ms). */
export function nextSleepCheckDue(state: SleepCheckState): number {
  const base = state.lastCheckAt ?? state.napStartAt;
  return base + state.intervalMinutes * 60_000;
}

export function sleepCheckOverdue(state: SleepCheckState, now: number): boolean {
  return now >= nextSleepCheckDue(state);
}

/** s. 33.1: toddler/preschool rest periods must not exceed two hours. */
export function restOverCap(napStartAt: number, now: number, capMinutes: number | null): boolean {
  if (capMinutes === null) return false;
  return now - napStartAt > capMinutes * 60_000;
}
