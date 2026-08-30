import { describe, expect, it } from 'vitest';
import { validateCareLogPayload } from '../src/careLogSchemas';
import { buildStory, twelveHour } from '../src/story';
import {
  nextSleepCheckDue,
  restOverCap,
  safeArrivalDue,
  sleepCheckOverdue,
} from '../src/safeArrival';

describe('care log payload schemas (mirror of app.validate_care_log_payload)', () => {
  it('payload_meal_requires_meal_and_eaten', () => {
    expect(validateCareLogPayload('meal', { meal: 'lunch' }).success).toBe(false);
    expect(validateCareLogPayload('meal', { meal: 'lunch', eaten: 'most' }).success).toBe(true);
  });

  it('payload_bottle_requires_amount_and_kind', () => {
    expect(validateCareLogPayload('bottle', { amount_ml: 120, kind: 'formula' }).success).toBe(true);
    expect(validateCareLogPayload('bottle', { kind: 'formula' }).success).toBe(false);
  });

  it('payload_sleep_check_requires_breathing_ok', () => {
    expect(validateCareLogPayload('sleep_check', { breathing_ok: true, position: 'back' }).success).toBe(true);
    expect(validateCareLogPayload('sleep_check', {}).success).toBe(false);
  });

  it('payload_outdoor_requires_minutes_or_reason', () => {
    expect(validateCareLogPayload('outdoor', { minutes: 45 }).success).toBe(true);
    expect(validateCareLogPayload('outdoor', { skipped_reason: 'freezing rain' }).success).toBe(true);
    expect(validateCareLogPayload('outdoor', {}).success).toBe(false);
  });

  it('s32_health_observation_requires_text', () => {
    expect(
      validateCareLogPayload('health_observation', {
        observation: 'settled on arrival',
        parent_reported: 'restless night',
      }).success,
    ).toBe(true);
    expect(validateCareLogPayload('health_observation', { observation: '' }).success).toBe(false);
  });
});

describe('the daily story', () => {
  it('story_reads_like_a_letter_with_12_hour_times', () => {
    const story = buildStory({
      childFirstName: 'Maya',
      meals: [{ meal: 'lunch', eaten: 'most' }],
      naps: [{ start: '12:40', end: '14:10' }],
      diapers: 3,
      outdoorMinutes: 90,
      outdoorSkippedReason: null,
      activities: ['Maya loved the leaf pile'],
      photoCount: 2,
    });
    expect(story).toContain('Maya ate most of lunch.');
    expect(story).toContain('12:40 p.m. to 2:10 p.m.');
    expect(story).toContain('2 new photos');
    expect(story).not.toContain('!'); // calm voice: no exclamation marks
  });

  it('story_quiet_day_still_says_something_kind', () => {
    const story = buildStory({
      childFirstName: 'Theo',
      meals: [],
      naps: [],
      diapers: 0,
      outdoorMinutes: 0,
      outdoorSkippedReason: null,
      activities: [],
      photoCount: 0,
    });
    expect(story).toBe('Theo had a steady, quiet day with us.');
  });

  it('twelve_hour_boundaries', () => {
    expect(twelveHour('00:05')).toBe('12:05 a.m.');
    expect(twelveHour('12:00')).toBe('12:00 p.m.');
    expect(twelveHour('18:30')).toBe('6:30 p.m.');
  });
});

describe('s. 50 — safe arrival', () => {
  const base = {
    expectedChildIds: ['a', 'b', 'c', 'd'],
    arrivedChildIds: ['a'],
    markedAbsentChildIds: ['b'],
    alreadyPromptedChildIds: ['c'],
    nowMinutes: 10 * 60,
    cutoffMinutes: 9 * 60 + 30,
  };

  it('s50_prompts_only_unaccounted_children_after_cutoff', () => {
    expect(safeArrivalDue(base)).toEqual(['d']);
  });

  it('s50_no_prompts_before_cutoff', () => {
    expect(safeArrivalDue({ ...base, nowMinutes: 9 * 60 })).toEqual([]);
  });
});

describe('s. 33.1 — sleep check scheduling', () => {
  const napStart = Date.parse('2026-08-29T12:40:00Z');

  it('s33_1_first_check_due_one_interval_after_nap_start', () => {
    expect(nextSleepCheckDue({ napStartAt: napStart, lastCheckAt: null, intervalMinutes: 15 })).toBe(
      napStart + 15 * 60_000,
    );
  });

  it('s33_1_subsequent_checks_from_last_check', () => {
    const last = napStart + 20 * 60_000;
    expect(nextSleepCheckDue({ napStartAt: napStart, lastCheckAt: last, intervalMinutes: 15 })).toBe(
      last + 15 * 60_000,
    );
    expect(sleepCheckOverdue({ napStartAt: napStart, lastCheckAt: last, intervalMinutes: 15 }, last + 16 * 60_000)).toBe(true);
  });

  it('s33_1_rest_cap_two_hours_flags', () => {
    expect(restOverCap(napStart, napStart + 121 * 60_000, 120)).toBe(true);
    expect(restOverCap(napStart, napStart + 119 * 60_000, 120)).toBe(false);
    expect(restOverCap(napStart, napStart + 500 * 60_000, null)).toBe(false); // infants: no cap
  });
});
