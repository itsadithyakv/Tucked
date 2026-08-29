import { describe, expect, it } from 'vitest';
import { PROVINCE_PRESETS, ROOM_PRESETS, sleepCheckRequired } from '../src/presets';

describe('s. 33.1 — sleep checks', () => {
  it('s33_1_direct_checks_under_24_months_in_infant_toddler_family', () => {
    expect(sleepCheckRequired(10, 'infant')).toBe(true);
    expect(sleepCheckRequired(20, 'toddler')).toBe(true);
    expect(sleepCheckRequired(20, 'family')).toBe(true);
  });

  it('s33_1_not_required_at_24_months_or_older', () => {
    expect(sleepCheckRequired(24, 'toddler')).toBe(false);
    expect(sleepCheckRequired(30, 'family')).toBe(false);
  });

  it('s33_1_not_required_outside_the_three_groups', () => {
    expect(sleepCheckRequired(20, 'preschool')).toBe(false);
    expect(sleepCheckRequired(20, 'kindergarten')).toBe(false);
  });

  it('s33_1_rest_capped_at_two_hours_toddler_preschool', () => {
    expect(ROOM_PRESETS.toddler.restMaxMinutes).toBe(120);
    expect(ROOM_PRESETS.preschool.restMaxMinutes).toBe(120);
  });
});

describe('room presets', () => {
  it('infant_room_logs_bottles_and_sleep_checks', () => {
    expect(ROOM_PRESETS.infant.careLogTypes).toContain('bottle');
    expect(ROOM_PRESETS.infant.careLogTypes).toContain('sleep_check');
    expect(ROOM_PRESETS.infant.backToSleep).toBe(true);
  });

  it('school_age_rooms_are_before_after_only_with_no_naps', () => {
    for (const id of ['kindergarten', 'primary_junior', 'junior'] as const) {
      expect(ROOM_PRESETS[id].beforeAfterOnly).toBe(true);
      expect(ROOM_PRESETS[id].careLogTypes).not.toContain('nap_start');
      expect(ROOM_PRESETS[id].careLogTypes).not.toContain('sleep_check');
    }
  });

  it('no_mood_log_type_exists_anywhere', () => {
    for (const preset of Object.values(ROOM_PRESETS)) {
      expect(preset.careLogTypes.some((t) => String(t).includes('mood'))).toBe(false);
    }
  });
});

describe('province presets', () => {
  it('ontario_is_the_only_implemented_province', () => {
    expect(PROVINCE_PRESETS.ON.implemented).toBe(true);
    expect(PROVINCE_PRESETS.MB.implemented).toBe(false);
    expect(PROVINCE_PRESETS.QC.implemented).toBe(false);
  });

  it('s72_5_ontario_retention_three_and_six_years', () => {
    expect(PROVINCE_PRESETS.ON.retentionYears).toEqual({
      childrensRecord: 3,
      attendance: 3,
      financial: 6,
    });
  });

  it('manitoba_attendance_retention_is_two_years', () => {
    expect(PROVINCE_PRESETS.MB.retentionYears.attendance).toBe(2);
  });

  it('quebec_is_french_first', () => {
    expect(PROVINCE_PRESETS.QC.language).toBe('fr-CA');
  });
});
