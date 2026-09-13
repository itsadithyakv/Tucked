/**
 * Safe arrival (s. 50) and sleep-check scheduling (s. 33.1) — pure timing
 * logic shared by the room device (offline) and the pg_cron sweep.
 */

/** What a family told the centre today (absence_notice, migration 0040). */
export interface AbsenceNotice {
  childId: string;
  kind: 'absent' | 'late';
  /** For 'late': when the family expects to arrive, in minutes since
   *  centre-local midnight. Null for 'absent'. */
  expectedMinutes: number | null;
}

export interface SafeArrivalInput {
  expectedChildIds: string[]; // enrolled, not discharged, expected today
  arrivedChildIds: string[];
  markedAbsentChildIds: string[];
  alreadyPromptedChildIds: string[];
  /** Notices families have given today. Optional: a device that has not
   *  loaded them chases exactly as it did before notices existed. */
  notices?: AbsenceNotice[];
  /** Minutes since the centre-local midnight. */
  nowMinutes: number;
  cutoffMinutes: number;
}

/** Children staff must be prompted to follow up on: expected, past the
 * cut-off, not arrived, not marked absent, not already being chased — and not
 * already explained by their family, to the extent a notice explains them. */
export function safeArrivalDue(input: SafeArrivalInput): string[] {
  if (input.nowMinutes < input.cutoffMinutes) return [];
  const seen = new Set([
    ...input.arrivedChildIds,
    ...input.markedAbsentChildIds,
    ...input.alreadyPromptedChildIds,
  ]);
  const notices = new Map((input.notices ?? []).map((n) => [n.childId, n]));
  return input.expectedChildIds.filter((id) => {
    if (seen.has(id)) return false;
    const notice = notices.get(id);
    return notice ? stillNeedsAChase(notice, input.nowMinutes) : true;
  });
}

/**
 * How long past the time a family gave for "running late" before the room goes
 * back to treating the child as unexplained.
 *
 * Fifteen minutes. The family app offers "about 15 minutes", "about 30" and
 * "about an hour", and "about" deserves some slack — so does a parking space.
 * It is short on purpose: a late promise that is not kept is precisely the
 * moment s. 50 is written for, and a call a quarter of an hour after the time
 * the family themselves named is a check-in, not a nag.
 */
export const LATE_NOTICE_GRACE_MINUTES = 15;

/**
 * A family has told the centre something about this child, and the child has
 * not arrived. Does an educator still need to go and phone them?
 *
 * This is the whole safety question behind parent notices. s. 50 exists
 * because an expected child who silently does not arrive might be in trouble —
 * a notice is the family ANSWERING that question in advance. But "running
 * late" is a promise about the future, and a promise that is not kept is
 * precisely the situation the regulation is worried about.
 *
 * The rule:
 *   - "Not coming today" answers the question outright. No call.
 *   - "Running late" is trusted until the time the family gave, plus
 *     LATE_NOTICE_GRACE_MINUTES. After that the child is back on the chase
 *     list: a broken promise is not an explanation, it is a new question.
 *   - The promise runs from the FAMILY's time, never from the cutoff. A parent
 *     who said 9:15 has not earned until 9:45 because the centre happens to
 *     start chasing at 9:30 — at 9:40 they are 25 minutes past what they said.
 *   - A late notice with no time explains nothing. The database forbids one
 *     (late_notice_says_when); a stale device cache is not the database.
 *
 * Only ever asked at or after the cutoff — safeArrivalDue returns nobody before
 * it — which is why the cutoff is not a parameter here. Returning true means
 * "put this child on the chase list": what every child got before notices
 * existed, and the answer whenever this function is unsure.
 */
export function stillNeedsAChase(notice: AbsenceNotice, nowMinutes: number): boolean {
  if (notice.kind === 'absent') return false;
  if (notice.expectedMinutes === null) return true;
  return nowMinutes >= notice.expectedMinutes + LATE_NOTICE_GRACE_MINUTES;
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
