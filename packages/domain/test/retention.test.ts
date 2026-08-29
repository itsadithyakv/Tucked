import { describe, expect, it } from 'vitest';
import { mayAnonymise, retentionEndsAt } from '../src/retention';

describe('s. 72(5) and O. Reg. 138/15 s. 27.1 — retention', () => {
  const discharge = new Date('2026-08-29T00:00:00Z');

  it('s72_5_childrens_record_three_years_after_discharge', () => {
    expect(retentionEndsAt('childrens_record', discharge).toISOString().slice(0, 10)).toBe(
      '2029-08-29',
    );
  });

  it('s72_5_attendance_three_years', () => {
    expect(retentionEndsAt('attendance', discharge).getFullYear()).toBe(2029);
  });

  it('reg138_financial_six_years', () => {
    expect(retentionEndsAt('financial', discharge).getFullYear()).toBe(2032);
  });

  it('s72_5_never_purge_before_the_period', () => {
    expect(mayAnonymise('childrens_record', discharge, new Date('2029-08-28T00:00:00Z'))).toBe(
      false,
    );
    expect(mayAnonymise('childrens_record', discharge, new Date('2029-08-29T00:00:00Z'))).toBe(
      true,
    );
    expect(mayAnonymise('financial', discharge, new Date('2031-12-31T00:00:00Z'))).toBe(false);
  });
});
