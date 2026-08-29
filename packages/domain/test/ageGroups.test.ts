import { describe, expect, it } from 'vitest';
import { AGE_GROUPS, AGE_GROUP_IDS, eligibleAgeGroups } from '../src/ageGroups';

/** Schedule 1 is regulation. Each value is pinned so an accidental edit fails loudly. */
describe('Schedule 1 age groups', () => {
  it('sched1_infant', () => {
    const g = AGE_GROUPS.infant;
    expect(g.ratio).toEqual({ staff: 3, children: 10 });
    expect(g.maxGroupSize).toBe(10);
    expect(g.qualifiedProportion).toBeCloseTo(1 / 3);
    expect(g.ageRangeMonths).toEqual([0, 18]);
  });

  it('sched1_toddler', () => {
    const g = AGE_GROUPS.toddler;
    expect(g.ratio).toEqual({ staff: 1, children: 5 });
    expect(g.maxGroupSize).toBe(15);
    expect(g.qualifiedProportion).toBeCloseTo(1 / 3);
  });

  it('sched1_preschool', () => {
    const g = AGE_GROUPS.preschool;
    expect(g.ratio).toEqual({ staff: 1, children: 8 });
    expect(g.maxGroupSize).toBe(24);
    expect(g.qualifiedProportion).toBeCloseTo(2 / 3);
    expect(g.minQualifiedAt17Plus).toBe(true);
  });

  it('sched1_kindergarten', () => {
    const g = AGE_GROUPS.kindergarten;
    expect(g.ratio).toEqual({ staff: 1, children: 13 });
    expect(g.maxGroupSize).toBe(26);
    expect(g.qualifiedProportion).toBeCloseTo(1 / 2);
  });

  it('sched1_primary_junior', () => {
    const g = AGE_GROUPS.primary_junior;
    expect(g.ratio).toEqual({ staff: 1, children: 15 });
    expect(g.maxGroupSize).toBe(30);
  });

  it('sched1_junior', () => {
    const g = AGE_GROUPS.junior;
    expect(g.ratio).toEqual({ staff: 1, children: 20 });
    expect(g.maxGroupSize).toBe(20);
    expect(g.qualifiedProportion).toBe(1);
  });

  it('sched1_family', () => {
    const g = AGE_GROUPS.family;
    expect(g.ratio).toEqual({ staff: 1, children: 8 });
    expect(g.maxGroupSize).toBe(16);
    expect(g.maxUnder24Months).toBe(6);
  });

  it('sched1_all_seven_groups_present', () => {
    expect(AGE_GROUP_IDS).toHaveLength(7);
  });

  it('eligible_groups_overlap_by_design', () => {
    // A 50-month-old may be placed in preschool, kindergarten or family.
    const ids = eligibleAgeGroups(50).map((g) => g.id);
    expect(ids).toContain('preschool');
    expect(ids).toContain('kindergarten');
    expect(ids).toContain('family');
    expect(ids).not.toContain('infant');
  });

  it('eligible_groups_infant_boundary', () => {
    expect(eligibleAgeGroups(17).map((g) => g.id)).toContain('infant');
    expect(eligibleAgeGroups(18).map((g) => g.id)).not.toContain('infant');
  });
});
