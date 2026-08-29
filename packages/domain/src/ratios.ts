/**
 * Ratio and group-size engine — O. Reg. 137/15 ss. 8–11 + Schedule 1.
 * Pure functions; runs identically on the room tablet (offline), in Edge
 * Functions, and in test fixtures. Every rule here has a test named s8_* or s11_*.
 */

import type { AgeGroupId } from './ageGroups';
import { AGE_GROUPS } from './ageGroups';

/** Roles that may ever be counted in a ratio. Resource consultants, volunteers
 * and placement students are NEVER counted (s. 8; never-do list §9.14). */
const COUNTABLE_ROLES = new Set(['supervisor', 'designate', 'rece', 'staff']);

export type StaffRole =
  | 'supervisor'
  | 'designate'
  | 'rece'
  | 'staff'
  | 'student'
  | 'volunteer'
  | 'resource_consultant';

export interface StaffPresence {
  personId: string;
  role: StaffRole;
  /** RECE (or otherwise qualified for the age group) — drives qualified counts. */
  qualified: boolean;
  /** Only staff currently on shift in this room count. */
  onShift: boolean;
}

export type RatioWindow = 'core' | 'arrival' | 'departure' | 'rest';

export interface RatioContext {
  window: RatioWindow;
  /** Reduced ratios exist only for programs operating 6+ hours (s. 8(4)). */
  programHoursPerDay: number;
  /** Reduced ratios never apply outdoors (s. 8(6)). */
  outdoors: boolean;
}

export interface RatioAssessment {
  countedStaff: number;
  qualifiedStaff: number;
  /** Staff required at the full Schedule 1 ratio. */
  requiredStaff: number;
  /** Staff required after any lawful reduction (= requiredStaff when none applies). */
  requiredStaffEffective: number;
  reducedRatioApplied: boolean;
  requiredQualified: number;
  groupSizeOk: boolean;
  compliant: boolean;
  issues: string[];
}

/**
 * Maximum reduced ratios (children per one staff) during arrival/departure/rest
 * windows — s. 8(5). Groups absent from this table are not eligible for
 * reduction in this engine.
 * TODO(reg): confirm whether junior school age and family age groups have any
 * reduced-ratio allowance; the Licensing Manual tables list only these four.
 * Infants are never reduced (s. 8(5)).
 */
const REDUCED_FLOOR_CHILDREN_PER_STAFF: Partial<Record<AgeGroupId, number>> = {
  toddler: 8,
  preschool: 12,
  kindergarten: 20,
  primary_junior: 23,
};

export function staffRequiredAtFullRatio(ageGroupId: AgeGroupId, childrenPresent: number): number {
  const g = AGE_GROUPS[ageGroupId];
  if (childrenPresent <= 0) return 0;
  return Math.ceil((childrenPresent * g.ratio.staff) / g.ratio.children);
}

export function reducedRatioAllowed(ageGroupId: AgeGroupId, ctx: RatioContext): boolean {
  if (ctx.window === 'core') return false;
  if (ctx.outdoors) return false; // never outdoors, s. 8(6)
  if (ageGroupId === 'infant') return false; // never for infants, s. 8(5)
  if (!(ageGroupId in REDUCED_FLOOR_CHILDREN_PER_STAFF)) return false;
  if (ctx.programHoursPerDay < 6) {
    // Programs under 6 h get 30-minute arrival/departure windows only —
    // window classification is the caller's job via activeWindow(); rest
    // reduction requires a 6+ h program.
    return ctx.window !== 'rest';
  }
  return true;
}

export function staffRequiredEffective(
  ageGroupId: AgeGroupId,
  childrenPresent: number,
  ctx: RatioContext,
): { required: number; reduced: boolean } {
  const full = staffRequiredAtFullRatio(ageGroupId, childrenPresent);
  if (!reducedRatioAllowed(ageGroupId, ctx)) return { required: full, reduced: false };
  // Never below two-thirds of the ratio (s. 8(4))…
  const byTwoThirds = Math.ceil(full * (2 / 3));
  // …and never beyond the listed maximum reduced ratio (s. 8(5)).
  const floorChildren = REDUCED_FLOOR_CHILDREN_PER_STAFF[ageGroupId];
  const byFloor =
    floorChildren === undefined || childrenPresent <= 0
      ? full
      : Math.ceil(childrenPresent / floorChildren);
  const required = Math.max(byTwoThirds, byFloor);
  return { required, reduced: required < full };
}

export function countedStaff(staff: StaffPresence[]): StaffPresence[] {
  return staff.filter((s) => s.onShift && COUNTABLE_ROLES.has(s.role));
}

/** Qualified employees required for the staff the ratio demands (Schedule 1).
 * Preschool: 17+ children in the group ⇒ at least 2 qualified. */
export function qualifiedRequired(ageGroupId: AgeGroupId, requiredStaff: number, childrenPresent: number): number {
  const g = AGE_GROUPS[ageGroupId];
  if (g.qualifiedProportion === null) return 0;
  let n = Math.ceil(requiredStaff * g.qualifiedProportion);
  if (g.minQualifiedAt17Plus && childrenPresent >= 17) n = Math.max(n, 2);
  return n;
}

export function assessRoomRatio(
  ageGroupId: AgeGroupId,
  childrenPresent: number,
  staff: StaffPresence[],
  ctx: RatioContext,
): RatioAssessment {
  const g = AGE_GROUPS[ageGroupId];
  const counted = countedStaff(staff);
  const qualified = counted.filter((s) => s.qualified).length;
  const requiredFull = staffRequiredAtFullRatio(ageGroupId, childrenPresent);
  const { required: requiredEffective, reduced } = staffRequiredEffective(
    ageGroupId,
    childrenPresent,
    ctx,
  );
  const requiredQual = qualifiedRequired(ageGroupId, requiredFull, childrenPresent);
  const groupSizeOk = childrenPresent <= g.maxGroupSize;

  const issues: string[] = [];
  if (!groupSizeOk) issues.push('group_size_exceeded');
  if (counted.length < requiredEffective) issues.push('understaffed');
  if (qualified < requiredQual) issues.push('qualified_shortfall');
  if (childrenPresent > 0 && counted.length === 0) issues.push('no_adult_supervision'); // s. 11

  return {
    countedStaff: counted.length,
    qualifiedStaff: qualified,
    requiredStaff: requiredFull,
    requiredStaffEffective: requiredEffective,
    reducedRatioApplied: reduced,
    requiredQualified: requiredQual,
    groupSizeOk,
    compliant: issues.length === 0,
    issues,
  };
}

/** Centre-level minimum: where 6+ children are in attendance, at least 2 staff. */
export function minimumCentreStaff(childrenInAttendance: number): number {
  if (childrenInAttendance <= 0) return 0;
  return childrenInAttendance >= 6 ? 2 : 1;
}

/** Classify the current time into a ratio window from the centre's hours.
 * 6+ h programs: first 90 min / last 60 min; under 6 h: first and last 30 min.
 * Rest windows are declared by the room (nap time), not inferred from the clock. */
export function activeWindow(
  minutesSinceOpen: number,
  minutesUntilClose: number,
  programHoursPerDay: number,
  inDeclaredRest: boolean,
): RatioWindow {
  if (inDeclaredRest) return 'rest';
  const arrival = programHoursPerDay >= 6 ? 90 : 30;
  const departure = programHoursPerDay >= 6 ? 60 : 30;
  if (minutesSinceOpen >= 0 && minutesSinceOpen < arrival) return 'arrival';
  if (minutesUntilClose >= 0 && minutesUntilClose < departure) return 'departure';
  return 'core';
}
