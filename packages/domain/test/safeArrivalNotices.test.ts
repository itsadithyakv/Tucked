import { describe, expect, it } from 'vitest';
import { LATE_NOTICE_GRACE_MINUTES, safeArrivalDue, stillNeedsAChase } from '../src/safeArrival';

/** Minutes since centre-local midnight. */
const at = (h: number, m = 0) => h * 60 + m;

describe('s. 50 — what a family has already told the centre', () => {
  it('s50_not_coming_today_answers_the_question', () => {
    expect(stillNeedsAChase({ childId: 'a', kind: 'absent', expectedMinutes: null }, at(9, 40))).toBe(false);
  });

  it('s50_running_late_is_trusted_until_the_time_the_family_gave', () => {
    expect(stillNeedsAChase({ childId: 'a', kind: 'late', expectedMinutes: at(10, 15) }, at(9, 40))).toBe(false);
  });

  it('s50_and_through_the_grace_window_but_not_a_minute_past_it', () => {
    const notice = { childId: 'a', kind: 'late' as const, expectedMinutes: at(10, 15) };
    expect(stillNeedsAChase(notice, at(10, 15) + LATE_NOTICE_GRACE_MINUTES - 1)).toBe(false);
    expect(stillNeedsAChase(notice, at(10, 15) + LATE_NOTICE_GRACE_MINUTES)).toBe(true);
  });

  it('s50_a_promise_made_for_before_the_cutoff_is_measured_from_the_promise', () => {
    // Said 9:15; the centre starts chasing at 9:30; it is 9:40. The family is
    // 25 minutes past their own time, and the cutoff buys them nothing extra.
    expect(stillNeedsAChase({ childId: 'a', kind: 'late', expectedMinutes: at(9, 15) }, at(9, 40))).toBe(true);
  });

  it('s50_a_late_notice_with_no_time_explains_nothing', () => {
    expect(stillNeedsAChase({ childId: 'a', kind: 'late', expectedMinutes: null }, at(9, 40))).toBe(true);
  });
});

describe('s. 50 — the chase list with notices', () => {
  const base = {
    expectedChildIds: ['home', 'late', 'silent'],
    arrivedChildIds: [],
    markedAbsentChildIds: [],
    alreadyPromptedChildIds: [],
    cutoffMinutes: at(9, 30),
    notices: [
      { childId: 'home', kind: 'absent' as const, expectedMinutes: null },
      { childId: 'late', kind: 'late' as const, expectedMinutes: at(10, 15) },
    ],
  };

  it('s50_only_the_unexplained_child_is_chased_while_the_promise_holds', () => {
    expect(safeArrivalDue({ ...base, nowMinutes: at(9, 40) })).toEqual(['silent']);
  });

  it('s50_a_broken_promise_puts_the_child_back_on_the_list', () => {
    expect(safeArrivalDue({ ...base, nowMinutes: at(10, 30) })).toEqual(['late', 'silent']);
  });

  it('s50_a_notice_never_starts_a_chase_before_the_cutoff', () => {
    // An 8:00 "running late" is long broken by 9:00 — and still nobody is
    // chased before the centre's own cutoff.
    const early = { ...base, notices: [{ childId: 'late', kind: 'late' as const, expectedMinutes: at(8) }] };
    expect(safeArrivalDue({ ...early, nowMinutes: at(9) })).toEqual([]);
  });

  it('s50_a_device_that_has_not_loaded_notices_chases_as_it_always_did', () => {
    const { notices: _ignored, ...withoutNotices } = base;
    void _ignored;
    expect(safeArrivalDue({ ...withoutNotices, nowMinutes: at(9, 40) })).toEqual(['home', 'late', 'silent']);
  });
});
