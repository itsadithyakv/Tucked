/**
 * Licensed age groups — O. Reg. 137/15, Schedule 1.
 * These numbers are regulation, not configuration. Do not edit without citing
 * the amended Schedule; every value is pinned by a sched1_* test.
 */

export const AGE_GROUP_IDS = [
  'infant',
  'toddler',
  'preschool',
  'kindergarten',
  'primary_junior',
  'junior',
  'family',
] as const;

export type AgeGroupId = (typeof AGE_GROUP_IDS)[number];

export interface AgeGroupPreset {
  id: AgeGroupId;
  label: string;
  /** Inclusive lower bound, exclusive upper bound, in months. */
  ageRangeMonths: readonly [number, number];
  /** Staff : children, e.g. infant 3:10. */
  ratio: { staff: number; children: number };
  maxGroupSize: number;
  /**
   * Qualified-employee proportion of the staff required by ratio
   * (e.g. 1/3 = "one in three"). null = Schedule 1 lists none (family group).
   */
  qualifiedProportion: number | null;
  /** Preschool: 17+ children in the group ⇒ at least 2 qualified. */
  minQualifiedAt17Plus: boolean;
  /** Family age group: max 6 children under 24 months. */
  maxUnder24Months: number | null;
}

export const AGE_GROUPS: Record<AgeGroupId, AgeGroupPreset> = {
  infant: {
    id: 'infant',
    label: 'Infant',
    ageRangeMonths: [0, 18],
    ratio: { staff: 3, children: 10 },
    maxGroupSize: 10,
    qualifiedProportion: 1 / 3,
    minQualifiedAt17Plus: false,
    maxUnder24Months: null,
  },
  toddler: {
    id: 'toddler',
    label: 'Toddler',
    ageRangeMonths: [18, 30],
    ratio: { staff: 1, children: 5 },
    maxGroupSize: 15,
    qualifiedProportion: 1 / 3,
    minQualifiedAt17Plus: false,
    maxUnder24Months: null,
  },
  preschool: {
    id: 'preschool',
    label: 'Preschool',
    ageRangeMonths: [30, 72],
    ratio: { staff: 1, children: 8 },
    maxGroupSize: 24,
    qualifiedProportion: 2 / 3,
    minQualifiedAt17Plus: true,
    maxUnder24Months: null,
  },
  kindergarten: {
    id: 'kindergarten',
    label: 'Kindergarten',
    ageRangeMonths: [44, 84],
    ratio: { staff: 1, children: 13 },
    maxGroupSize: 26,
    qualifiedProportion: 1 / 2,
    minQualifiedAt17Plus: false,
    maxUnder24Months: null,
  },
  primary_junior: {
    id: 'primary_junior',
    label: 'Primary/junior school age',
    ageRangeMonths: [68, 156],
    ratio: { staff: 1, children: 15 },
    maxGroupSize: 30,
    qualifiedProportion: 1 / 2,
    minQualifiedAt17Plus: false,
    maxUnder24Months: null,
  },
  junior: {
    id: 'junior',
    label: 'Junior school age',
    ageRangeMonths: [108, 156],
    ratio: { staff: 1, children: 20 },
    maxGroupSize: 20,
    qualifiedProportion: 1,
    minQualifiedAt17Plus: false,
    maxUnder24Months: null,
  },
  family: {
    id: 'family',
    label: 'Family age group',
    ageRangeMonths: [0, 156],
    ratio: { staff: 1, children: 8 },
    maxGroupSize: 16,
    // TODO(reg): Schedule 1 lists no qualified-employee proportion for the
    // family age group; confirm with the Licensing Manual before Phase 1.
    qualifiedProportion: null,
    minQualifiedAt17Plus: false,
    maxUnder24Months: 6,
  },
};

/** All licensed age groups whose Schedule 1 range includes this age. Placement
 * within them is the centre's decision — ranges deliberately overlap. */
export function eligibleAgeGroups(ageMonths: number): AgeGroupPreset[] {
  return AGE_GROUP_IDS.map((id) => AGE_GROUPS[id]).filter(
    (g) => ageMonths >= g.ageRangeMonths[0] && ageMonths < g.ageRangeMonths[1],
  );
}
