/**
 * Zod schemas for the Phase 0 entities. These mirror the Supabase migrations —
 * names are final (build prompt §4); change both together.
 * Clients pre-validate with these as a courtesy; the database re-enforces.
 */

import { z } from 'zod';
import { AGE_GROUP_IDS } from './ageGroups';

export const provinceSchema = z.enum(['ON', 'MB', 'QC']);

export const roleIdSchema = z.enum([
  'licensee_admin',
  'supervisor',
  'designate',
  'rece',
  'staff',
  'student',
  'volunteer',
  'resource_consultant',
  'family_adult',
]);
export type RoleId = z.infer<typeof roleIdSchema>;

export const licenseeSchema = z.object({
  id: z.string().uuid(),
  legalName: z.string().min(1),
});

export const centreSchema = z.object({
  id: z.string().uuid(),
  licenseeId: z.string().uuid(),
  name: z.string().min(1),
  licenceNumber: z.string().min(1),
  province: provinceSchema,
  timezone: z.string().min(1), // IANA, e.g. America/Toronto — attendance is day-bounded in this zone
  address: z.string().min(1),
  serviceSystemManager: z.string().nullable(), // e.g. Toronto Children's Services
  cwelccEnrolled: z.boolean(),
  opensAt: z.string().regex(/^\d{2}:\d{2}$/), // local time HH:MM
  closesAt: z.string().regex(/^\d{2}:\d{2}$/),
});

export const ageGroupConfigSchema = z.object({
  id: z.string().uuid(),
  centreId: z.string().uuid(),
  ageGroupId: z.enum(AGE_GROUP_IDS),
  licensedCapacity: z.number().int().positive(),
});

export const roomSchema = z.object({
  id: z.string().uuid(),
  centreId: z.string().uuid(),
  ageGroupConfigId: z.string().uuid(),
  name: z.string().min(1),
});

/** Global per human (decision 2026-08-29): one login, roles are centre-scoped. */
export const personSchema = z.object({
  id: z.string().uuid(),
  fullName: z.string().min(1),
  email: z.string().email().nullable(),
  phone: z.string().nullable(),
});

export const personRoleSchema = z.object({
  id: z.string().uuid(),
  personId: z.string().uuid(),
  centreId: z.string().uuid(),
  role: roleIdSchema,
  /** RECE registration or age-group qualification — drives qualified counts. */
  qualified: z.boolean(),
  active: z.boolean(),
});

export const householdSchema = z.object({
  id: z.string().uuid(),
  centreId: z.string().uuid(),
  name: z.string().min(1), // e.g. "Osei household"
});

export const childSchema = z.object({
  id: z.string().uuid(),
  centreId: z.string().uuid(),
  fullName: z.string().min(1),
  dateOfBirth: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  admissionDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  dischargeDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .nullable(),
  currentRoomId: z.string().uuid().nullable(),
  attendsSchool: z.boolean(),
});

/** A child may belong to more than one household (separated parents). */
export const childHouseholdSchema = z.object({
  childId: z.string().uuid(),
  householdId: z.string().uuid(),
});

export const householdMemberSchema = z.object({
  id: z.string().uuid(),
  householdId: z.string().uuid(),
  personId: z.string().uuid(),
  relationship: z.string().min(1), // parent, grandparent, nanny…
  canView: z.boolean(),
  canMessage: z.boolean(),
  canPickup: z.boolean(),
  canConsent: z.boolean(),
  canBill: z.boolean(),
  revokedAt: z.string().nullable(),
});

export type Licensee = z.infer<typeof licenseeSchema>;
export type Centre = z.infer<typeof centreSchema>;
export type AgeGroupConfig = z.infer<typeof ageGroupConfigSchema>;
export type Room = z.infer<typeof roomSchema>;
export type Person = z.infer<typeof personSchema>;
export type PersonRole = z.infer<typeof personRoleSchema>;
export type Household = z.infer<typeof householdSchema>;
export type Child = z.infer<typeof childSchema>;
export type ChildHousehold = z.infer<typeof childHouseholdSchema>;
export type HouseholdMember = z.infer<typeof householdMemberSchema>;
