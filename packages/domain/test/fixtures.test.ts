import { describe, expect, it } from 'vitest';
import { buildMapleLeaf } from '../src/fixtures/mapleLeaf';
import {
  centreSchema,
  childSchema,
  householdMemberSchema,
  personRoleSchema,
} from '../src/schemas';
import { AGE_GROUPS } from '../src/ageGroups';

const REF = new Date('2026-08-29T12:00:00Z');

describe('Maple Leaf Early Learning fixture', () => {
  const f = buildMapleLeaf(REF);

  it('deterministic_same_input_same_output', () => {
    expect(buildMapleLeaf(REF)).toEqual(buildMapleLeaf(REF));
  });

  it('forty_children_across_three_rooms', () => {
    expect(f.children).toHaveLength(40);
    expect(f.rooms).toHaveLength(3);
    const byRoom = new Map<string, number>();
    for (const c of f.children) {
      byRoom.set(c.currentRoomId!, (byRoom.get(c.currentRoomId!) ?? 0) + 1);
    }
    expect([...byRoom.values()].sort((a, b) => a - b)).toEqual([10, 15, 15]);
  });

  it('room_counts_respect_schedule_1_max_group_sizes', () => {
    for (const cfg of f.ageGroupConfigs) {
      expect(cfg.licensedCapacity).toBeLessThanOrEqual(AGE_GROUPS[cfg.ageGroupId].maxGroupSize);
    }
  });

  it('children_age_correctly_for_their_rooms_at_reference_date', () => {
    const roomsById = new Map(f.rooms.map((r) => [r.id, r]));
    const cfgById = new Map(f.ageGroupConfigs.map((c) => [c.id, c]));
    for (const child of f.children) {
      const cfg = cfgById.get(roomsById.get(child.currentRoomId!)!.ageGroupConfigId)!;
      const [lo, hi] = AGE_GROUPS[cfg.ageGroupId].ageRangeMonths;
      const dob = new Date(child.dateOfBirth);
      const ageMonths =
        (REF.getFullYear() - dob.getFullYear()) * 12 + (REF.getMonth() - dob.getMonth());
      expect(ageMonths, `${child.fullName} in ${cfg.ageGroupId}`).toBeGreaterThanOrEqual(lo);
      expect(ageMonths, `${child.fullName} in ${cfg.ageGroupId}`).toBeLessThan(hi);
    }
  });

  it('nine_staff_including_never_counted_roles', () => {
    const staffRoles = f.personRoles.filter((r) => r.role !== 'family_adult');
    expect(staffRoles).toHaveLength(9);
    const roles = staffRoles.map((r) => r.role);
    expect(roles).toContain('supervisor');
    expect(roles).toContain('student');
    expect(roles).toContain('volunteer');
    expect(roles.filter((r) => r === 'rece')).toHaveLength(5);
  });

  it('one_child_belongs_to_two_households', () => {
    const counts = new Map<string, number>();
    for (const ch of f.childHouseholds) counts.set(ch.childId, (counts.get(ch.childId) ?? 0) + 1);
    const multi = [...counts.values()].filter((n) => n > 1);
    expect(multi).toEqual([2]);
  });

  it('second_household_parent_has_reduced_permissions', () => {
    const jordan = f.people.find((p) => p.email === 'jordan.coparent@family.example')!;
    const membership = f.householdMembers.find((m) => m.personId === jordan.id)!;
    expect(membership.canView).toBe(true);
    expect(membership.canPickup).toBe(false);
    expect(membership.canBill).toBe(false);
  });

  it('siblings_share_a_household', () => {
    const counts = new Map<string, number>();
    for (const ch of f.childHouseholds) {
      counts.set(ch.householdId, (counts.get(ch.householdId) ?? 0) + 1);
    }
    expect([...counts.values()].some((n) => n >= 2)).toBe(true);
  });

  it('demo_logins_exist_for_all_three_roles', () => {
    const emails = new Set(f.people.map((p) => p.email));
    expect(emails.has('supervisor@mapleleaf.example')).toBe(true);
    expect(emails.has('educator@mapleleaf.example')).toBe(true);
    expect(emails.has('parent@mapleleaf.example')).toBe(true);
  });

  it('every_row_validates_against_its_schema', () => {
    expect(() => centreSchema.parse(f.centre)).not.toThrow();
    for (const c of f.children) expect(() => childSchema.parse(c)).not.toThrow();
    for (const r of f.personRoles) expect(() => personRoleSchema.parse(r)).not.toThrow();
    for (const m of f.householdMembers) expect(() => householdMemberSchema.parse(m)).not.toThrow();
  });

  it('centre_is_toronto_day_bounded_ontario', () => {
    expect(f.centre.timezone).toBe('America/Toronto');
    expect(f.centre.province).toBe('ON');
    expect(f.centre.cwelccEnrolled).toBe(true);
  });
});
