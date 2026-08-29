/**
 * Maple Leaf Early Learning — the synthetic demo centre (build prompt §8, Phase 0).
 * Deterministic: same input date ⇒ identical output, so the seed script and
 * tests share one source of truth. Ages are computed from the reference date so
 * the infant room always holds infants no matter when the demo is seeded.
 *
 * Shape: 1 licensee · 1 Toronto centre · infant (10) + toddler (15) +
 * preschool (15) rooms = 40 children · 9 staff (supervisor, 5 RECEs, 1 unqualified
 * staff, 1 placement student, 1 volunteer — the last two exist to prove they are
 * never counted in ratios) · ~30 households, including siblings sharing one
 * household and one child belonging to two households (separated parents).
 */

import type {
  AgeGroupConfig,
  Centre,
  Child,
  ChildHousehold,
  Household,
  HouseholdMember,
  Licensee,
  Person,
  PersonRole,
  Room,
} from '../schemas';

export interface MapleLeafFixture {
  licensee: Licensee;
  centre: Centre;
  ageGroupConfigs: AgeGroupConfig[];
  rooms: Room[];
  people: Person[];
  personRoles: PersonRole[];
  households: Household[];
  children: Child[];
  childHouseholds: ChildHousehold[];
  householdMembers: HouseholdMember[];
  /** The three demo logins the done-when criterion signs in as. */
  demoLogins: { supervisor: string; educator: string; parent: string };
}

let uuidCounter = 0;
function uuid(): string {
  uuidCounter += 1;
  return `00000000-0000-4000-8000-${uuidCounter.toString().padStart(12, '0')}`;
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function monthsBefore(reference: Date, months: number, dayOffset: number): Date {
  // Build from day 1 in UTC so short months never roll the date over (Aug 29
  // minus 18 months must not become Mar 1). Days are clamped to 1–28.
  const d = new Date(Date.UTC(reference.getUTCFullYear(), reference.getUTCMonth() - months, 1));
  d.setUTCDate(Math.max(1, Math.min(28, 1 + dayOffset)));
  return d;
}

const CHILD_FIRST = [
  'Maya', 'Liam', 'Aisha', 'Noah', 'Simran', 'Ethan', 'Zoe', 'Arjun', 'Olivia', 'Kai',
  'Amara', 'Lucas', 'Fatima', 'Theo', 'Ines', 'Ravi', 'Clara', 'Dmitri', 'Nia', 'Felix',
  'Hana', 'Marco', 'Priya', 'Owen', 'Leila', 'Jasper', 'Mei', 'Tomas', 'Ada', 'Kwame',
  'Sofia', 'Ben', 'Anika', 'Cole', 'Rosa', 'Ivan', 'Tara', 'Louis', 'Yuki', 'Sam',
] as const;

const FAMILY_NAMES = [
  'Osei', 'Tremblay', 'Nguyen', 'Kaur', 'Rossi', 'Ivanov', 'Okafor', 'Dubois', 'Sato', 'Ahmed',
  'MacLeod', 'Fernandes', 'Kim', 'Bouchard', 'Singh', 'Costa', 'Petrov', 'Diallo', 'Roy', 'Wong',
  'Silva', 'Byrne', 'Haddad', 'Larsen', 'Moreau', 'Adeyemi', 'Chen', 'Novak', 'Reyes', 'Gagnon',
] as const;

const STAFF = [
  { name: 'Beatrice Alvares', role: 'supervisor', qualified: true },
  { name: 'Dara Ocampo', role: 'rece', qualified: true },
  { name: 'Ellis Marchetti', role: 'rece', qualified: true },
  { name: 'Farah Iqbal', role: 'rece', qualified: true },
  { name: 'Gustav Lindqvist', role: 'rece', qualified: true },
  { name: 'Hye-jin Park', role: 'rece', qualified: true },
  { name: 'Iris Callahan', role: 'staff', qualified: false },
  { name: 'Jonah Weiss', role: 'student', qualified: false },
  { name: 'Karin Sedaris', role: 'volunteer', qualified: false },
] as const;

/** Room plan: [ageGroup, roomName, childCount, [minAgeMonths, maxAgeMonths]] */
const ROOM_PLAN = [
  { ageGroupId: 'infant', name: 'Infant room', count: 10, ages: [4, 17] },
  { ageGroupId: 'toddler', name: 'Toddler room', count: 15, ages: [18, 29] },
  { ageGroupId: 'preschool', name: 'Preschool room', count: 15, ages: [31, 60] },
] as const;

export function buildMapleLeaf(reference: Date): MapleLeafFixture {
  uuidCounter = 0;

  const licensee: Licensee = { id: uuid(), legalName: 'Maple Leaf Early Learning Inc.' };

  const centre: Centre = {
    id: uuid(),
    licenseeId: licensee.id,
    name: 'Maple Leaf Early Learning',
    licenceNumber: 'DEMO-2026-0001',
    province: 'ON',
    timezone: 'America/Toronto',
    address: '120 Carlton Street, Toronto, ON M5A 4K2',
    serviceSystemManager: 'Toronto Children’s Services',
    cwelccEnrolled: true,
    opensAt: '07:30',
    closesAt: '18:00',
  };

  const ageGroupConfigs: AgeGroupConfig[] = [];
  const rooms: Room[] = [];
  const people: Person[] = [];
  const personRoles: PersonRole[] = [];
  const households: Household[] = [];
  const children: Child[] = [];
  const childHouseholds: ChildHousehold[] = [];
  const householdMembers: HouseholdMember[] = [];

  // Staff
  const demoLogins = {
    supervisor: 'supervisor@mapleleaf.example',
    educator: 'educator@mapleleaf.example',
    parent: 'parent@mapleleaf.example',
  };
  STAFF.forEach((s, i) => {
    const person: Person = {
      id: uuid(),
      fullName: s.name,
      email:
        s.role === 'supervisor'
          ? demoLogins.supervisor
          : i === 1
            ? demoLogins.educator
            : `${s.name.toLowerCase().replace(/[^a-z]+/g, '.')}@mapleleaf.example`,
      phone: null,
    };
    people.push(person);
    personRoles.push({
      id: uuid(),
      personId: person.id,
      centreId: centre.id,
      role: s.role,
      qualified: s.qualified,
      active: true,
    });
  });

  // Rooms and children
  let childIndex = 0;
  let familyIndex = 0;
  const admission = isoDate(monthsBefore(reference, 6, 0));

  for (const plan of ROOM_PLAN) {
    const cfg: AgeGroupConfig = {
      id: uuid(),
      centreId: centre.id,
      ageGroupId: plan.ageGroupId,
      licensedCapacity: plan.count,
    };
    ageGroupConfigs.push(cfg);
    const room: Room = { id: uuid(), centreId: centre.id, ageGroupConfigId: cfg.id, name: plan.name };
    rooms.push(room);

    for (let i = 0; i < plan.count; i += 1) {
      const first = CHILD_FIRST[childIndex % CHILD_FIRST.length]!;
      // Siblings: every 7th child joins the previous family's household.
      const isSibling = childIndex > 0 && childIndex % 7 === 0;
      if (!isSibling) familyIndex += 1;
      const family = FAMILY_NAMES[(familyIndex - 1) % FAMILY_NAMES.length]!;

      const [minAge, maxAge] = plan.ages;
      const ageMonths = minAge + ((i * 5) % (maxAge - minAge + 1));
      const child: Child = {
        id: uuid(),
        centreId: centre.id,
        fullName: `${first} ${family}`,
        dateOfBirth: isoDate(monthsBefore(reference, ageMonths, i)),
        admissionDate: admission,
        dischargeDate: null,
        currentRoomId: room.id,
        attendsSchool: false,
      };
      children.push(child);

      let household = households.find((h) => h.name === `${family} household`);
      if (!household) {
        household = { id: uuid(), centreId: centre.id, name: `${family} household` };
        households.push(household);
        const adult: Person = {
          id: uuid(),
          fullName: `Alex ${family}`,
          email:
            childIndex === 0
              ? demoLogins.parent
              : `alex.${family.toLowerCase()}@family.example`,
          phone: `416-555-0${(100 + familyIndex).toString()}`,
        };
        people.push(adult);
        personRoles.push({
          id: uuid(),
          personId: adult.id,
          centreId: centre.id,
          role: 'family_adult',
          qualified: false,
          active: true,
        });
        householdMembers.push({
          id: uuid(),
          householdId: household.id,
          personId: adult.id,
          relationship: 'parent',
          canView: true,
          canMessage: true,
          canPickup: true,
          canConsent: true,
          canBill: true,
          revokedAt: null,
        });
      }
      childHouseholds.push({ childId: child.id, householdId: household.id });
      childIndex += 1;
    }
  }

  // Split household: the first toddler's other parent has their own household
  // with their own login, permissions and (view-only) access — the Brightwheel
  // co-parent failure is why this exists.
  const splitChild = children[10]!; // first toddler
  const otherParent: Person = {
    id: uuid(),
    fullName: `Jordan ${splitChild.fullName.split(' ')[1]}`,
    email: 'jordan.coparent@family.example',
    phone: '647-555-0199',
  };
  people.push(otherParent);
  personRoles.push({
    id: uuid(),
    personId: otherParent.id,
    centreId: centre.id,
    role: 'family_adult',
    qualified: false,
    active: true,
  });
  const secondHousehold: Household = {
    id: uuid(),
    centreId: centre.id,
    name: `${splitChild.fullName.split(' ')[1]} household (second)`,
  };
  households.push(secondHousehold);
  householdMembers.push({
    id: uuid(),
    householdId: secondHousehold.id,
    personId: otherParent.id,
    relationship: 'parent',
    canView: true,
    canMessage: true,
    canPickup: false, // pickup restriction placeholder — becomes a court-order record in Phase 1
    canConsent: false,
    canBill: false,
    revokedAt: null,
  });
  childHouseholds.push({ childId: splitChild.id, householdId: secondHousehold.id });

  return {
    licensee,
    centre,
    ageGroupConfigs,
    rooms,
    people,
    personRoles,
    households,
    children,
    childHouseholds,
    householdMembers,
    demoLogins,
  };
}
