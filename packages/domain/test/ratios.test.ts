import { describe, expect, it } from 'vitest';
import type { RatioContext, StaffPresence } from '../src/ratios';
import {
  activeWindow,
  assessRoomRatio,
  minimumCentreStaff,
  reducedRatioAllowed,
  staffRequiredAtFullRatio,
  staffRequiredEffective,
} from '../src/ratios';

let n = 0;
function staff(
  role: StaffPresence['role'],
  qualified = true,
  onShift = true,
): StaffPresence {
  n += 1;
  return { personId: `p${n}`, role, qualified, onShift };
}

const CORE: RatioContext = { window: 'core', programHoursPerDay: 10.5, outdoors: false };
const REST: RatioContext = { window: 'rest', programHoursPerDay: 10.5, outdoors: false };

describe('s. 8 — full ratios', () => {
  it('s8_infant_ratio_3_to_10', () => {
    expect(staffRequiredAtFullRatio('infant', 10)).toBe(3);
    expect(staffRequiredAtFullRatio('infant', 7)).toBe(3);
    expect(staffRequiredAtFullRatio('infant', 6)).toBe(2);
    expect(staffRequiredAtFullRatio('infant', 0)).toBe(0);
  });

  it('s8_toddler_ratio_1_to_5', () => {
    expect(staffRequiredAtFullRatio('toddler', 15)).toBe(3);
    expect(staffRequiredAtFullRatio('toddler', 11)).toBe(3);
  });

  it('s8_preschool_ratio_1_to_8', () => {
    expect(staffRequiredAtFullRatio('preschool', 24)).toBe(3);
    expect(staffRequiredAtFullRatio('preschool', 9)).toBe(2);
  });
});

describe('s. 8 — who counts', () => {
  it('s8_volunteers_and_students_never_counted', () => {
    const a = assessRoomRatio(
      'toddler',
      5,
      [staff('volunteer'), staff('student'), staff('resource_consultant')],
      CORE,
    );
    expect(a.countedStaff).toBe(0);
    expect(a.issues).toContain('understaffed');
    expect(a.issues).toContain('no_adult_supervision');
  });

  it('s8_off_shift_staff_never_counted', () => {
    const a = assessRoomRatio('toddler', 5, [staff('rece', true, false), staff('rece')], CORE);
    expect(a.countedStaff).toBe(1);
    expect(a.compliant).toBe(true);
  });

  it('s8_supervisor_and_designate_count', () => {
    const a = assessRoomRatio('toddler', 10, [staff('supervisor'), staff('designate')], CORE);
    expect(a.countedStaff).toBe(2);
    expect(a.compliant).toBe(true);
  });
});

describe('s. 8(4)–(6) — reduced ratios', () => {
  it('s8_reduced_never_for_infants', () => {
    expect(reducedRatioAllowed('infant', REST)).toBe(false);
  });

  it('s8_reduced_never_outdoors', () => {
    expect(reducedRatioAllowed('toddler', { ...REST, outdoors: true })).toBe(false);
  });

  it('s8_reduced_never_in_core_hours', () => {
    expect(reducedRatioAllowed('toddler', CORE)).toBe(false);
  });

  it('s8_reduced_floor_toddler_1_to_8', () => {
    // 15 toddlers: full ratio needs 3; two-thirds allows 2; floor 1:8 also allows 2.
    const r = staffRequiredEffective('toddler', 15, REST);
    expect(r).toEqual({ required: 2, reduced: true });
  });

  it('s8_reduced_two_thirds_bound', () => {
    // 24 preschoolers: full 3, two-thirds 2, floor 1:12 also 2.
    expect(staffRequiredEffective('preschool', 24, REST)).toEqual({ required: 2, reduced: true });
    // 5 toddlers: full 1 — two-thirds of 1 is still 1; no reduction possible.
    expect(staffRequiredEffective('toddler', 5, REST)).toEqual({ required: 1, reduced: false });
  });

  it('s8_reduced_floor_beats_two_thirds_when_stricter', () => {
    // 30 kindergarteners: full ceil(30/13)=3; two-thirds → 2; floor 1:20 → 2.
    expect(staffRequiredEffective('kindergarten', 30, REST).required).toBe(2);
    // 23 toddlers (hypothetical over-size): full 5, two-thirds 4; floor ceil(23/8)=3 → max is 4.
    expect(staffRequiredEffective('toddler', 23, REST).required).toBe(4);
  });

  it('s8_under_6h_program_no_rest_reduction', () => {
    const shortRest: RatioContext = { window: 'rest', programHoursPerDay: 3, outdoors: false };
    expect(reducedRatioAllowed('toddler', shortRest)).toBe(false);
    const shortArrival: RatioContext = { window: 'arrival', programHoursPerDay: 3, outdoors: false };
    expect(reducedRatioAllowed('toddler', shortArrival)).toBe(true);
  });

  it('s8_family_and_junior_not_reduced_pending_reg_confirmation', () => {
    expect(reducedRatioAllowed('family', REST)).toBe(false);
    expect(reducedRatioAllowed('junior', REST)).toBe(false);
  });
});

describe('Schedule 1 — qualified staff', () => {
  it('sched1_toddler_one_in_three_qualified', () => {
    // 15 toddlers ⇒ 3 staff ⇒ 1 must be qualified.
    const a = assessRoomRatio(
      'toddler',
      15,
      [staff('rece'), staff('staff', false), staff('staff', false)],
      CORE,
    );
    expect(a.requiredQualified).toBe(1);
    expect(a.compliant).toBe(true);
  });

  it('sched1_preschool_17_plus_needs_two_qualified', () => {
    // 17 preschoolers ⇒ 3 staff; 2/3 rule says 2, and the 17+ rule pins ≥ 2.
    const shortfall = assessRoomRatio(
      'preschool',
      17,
      [staff('rece'), staff('staff', false), staff('staff', false)],
      CORE,
    );
    expect(shortfall.requiredQualified).toBe(2);
    expect(shortfall.issues).toContain('qualified_shortfall');

    const ok = assessRoomRatio(
      'preschool',
      17,
      [staff('rece'), staff('rece'), staff('staff', false)],
      CORE,
    );
    expect(ok.compliant).toBe(true);
  });

  it('sched1_group_size_flagged', () => {
    const a = assessRoomRatio('infant', 11, [staff('rece'), staff('rece'), staff('rece'), staff('rece')], CORE);
    expect(a.groupSizeOk).toBe(false);
    expect(a.issues).toContain('group_size_exceeded');
  });
});

describe('s. 8(3), s. 11 — minimum staffing and supervision', () => {
  it('s8_six_children_require_two_staff', () => {
    expect(minimumCentreStaff(6)).toBe(2);
    expect(minimumCentreStaff(5)).toBe(1);
    expect(minimumCentreStaff(0)).toBe(0);
  });
});

describe('ratio windows', () => {
  it('window_arrival_departure_6h_program', () => {
    expect(activeWindow(30, 600, 10.5, false)).toBe('arrival');
    expect(activeWindow(89, 600, 10.5, false)).toBe('arrival');
    expect(activeWindow(90, 600, 10.5, false)).toBe('core');
    expect(activeWindow(400, 59, 10.5, false)).toBe('departure');
    expect(activeWindow(400, 60, 10.5, false)).toBe('core');
  });

  it('window_30min_for_short_programs', () => {
    expect(activeWindow(29, 200, 3, false)).toBe('arrival');
    expect(activeWindow(30, 200, 3, false)).toBe('core');
    expect(activeWindow(100, 29, 3, false)).toBe('departure');
  });

  it('window_rest_is_declared_not_inferred', () => {
    expect(activeWindow(30, 600, 10.5, true)).toBe('rest');
  });
});
