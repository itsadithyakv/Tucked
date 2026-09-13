import { describe, expect, it } from 'vitest';
import {
  addDaysISO,
  isoWeekdayOf,
  localDateISO,
  localMinutes,
  localWeekStartISO,
} from '../src/localDate';

const TORONTO = 'America/Toronto';

describe('the centre-local day', () => {
  it('local_date_is_still_today_at_8_30_pm_in_toronto', () => {
    // 00:30 UTC on the 13th is 20:30 EDT on the 12th — the evening a family
    // reads the story. The UTC date says the 13th, and asks for tomorrow.
    const evening = new Date('2026-09-13T00:30:00Z');
    expect(evening.toISOString().slice(0, 10)).toBe('2026-09-13');
    expect(localDateISO(TORONTO, evening)).toBe('2026-09-12');
  });

  it('local_date_rolls_an_hour_earlier_in_winter', () => {
    // EST is UTC−5, so 23:59 UTC on the 14th is already 18:59 local — and one
    // minute past midnight UTC is 19:01 on the 14th, still the 14th locally.
    expect(localDateISO(TORONTO, new Date('2026-01-15T00:01:00Z'))).toBe('2026-01-14');
  });

  it('local_date_agrees_with_utc_in_the_middle_of_the_day', () => {
    expect(localDateISO(TORONTO, new Date('2026-09-13T16:00:00Z'))).toBe('2026-09-13');
  });

  it('local_minutes_count_from_centre_midnight_not_utc_midnight', () => {
    expect(localMinutes(TORONTO, new Date('2026-09-13T13:30:00Z'))).toBe(9 * 60 + 30);
  });

  it('local_minutes_read_midnight_as_zero_not_twenty_four_hundred', () => {
    expect(localMinutes(TORONTO, new Date('2026-09-13T04:00:00Z'))).toBe(0);
  });

  it('local_day_survives_the_spring_forward_night', () => {
    // Clocks go forward at 02:00 EST (07:00 UTC) on 8 March 2026. Half an hour
    // before that is 01:30 EST — the night the local day is 23 hours long.
    expect(localDateISO(TORONTO, new Date('2026-03-08T06:30:00Z'))).toBe('2026-03-08');
  });
});

describe('calendar arithmetic without a clock', () => {
  it('add_days_crosses_a_month_and_a_year', () => {
    expect(addDaysISO('2026-12-30', 3)).toBe('2027-01-02');
    expect(addDaysISO('2026-03-01', -1)).toBe('2026-02-28');
  });

  it('iso_weekday_is_monday_one_sunday_seven', () => {
    expect(isoWeekdayOf('2026-09-07')).toBe(1);
    expect(isoWeekdayOf('2026-09-13')).toBe(7);
  });

  it('week_start_is_the_local_monday_even_on_a_sunday_evening', () => {
    // Sunday 13 September, 8:30 p.m. in Toronto — already Monday 14th in UTC,
    // which would have put the menu a week ahead.
    expect(localWeekStartISO(TORONTO, new Date('2026-09-14T00:30:00Z'))).toBe('2026-09-07');
  });
});
