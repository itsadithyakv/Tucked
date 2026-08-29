/**
 * The daily story builder — one calm, specific letter per child per day,
 * assembled from the day's care logs. Template-drafted (AI polish is a
 * labelled, optional Phase 2 add-on and never a dependency). The educator's
 * own note always sits on top, untouched. Families read 12-hour times.
 */

export interface StoryInput {
  childFirstName: string;
  meals: { meal: 'breakfast' | 'lunch' | 'snack_am' | 'snack_pm'; eaten: 'none' | 'some' | 'most' | 'all' }[];
  naps: { start: string; end: string | null }[]; // "HH:MM" 24h in; rendered 12h
  diapers: number;
  outdoorMinutes: number;
  outdoorSkippedReason: string | null;
  activities: string[];
  photoCount: number;
}

const MEAL_LABEL = {
  breakfast: 'breakfast',
  lunch: 'lunch',
  snack_am: 'morning snack',
  snack_pm: 'afternoon snack',
} as const;

const EATEN_LABEL = {
  none: 'was not interested in',
  some: 'ate some of',
  most: 'ate most of',
  all: 'finished',
} as const;

export function twelveHour(hhmm: string): string {
  const [hStr, m] = hhmm.split(':');
  const h = Number(hStr);
  const suffix = h >= 12 ? 'p.m.' : 'a.m.';
  const hour = h % 12 === 0 ? 12 : h % 12;
  return `${hour}:${m} ${suffix}`;
}

export function buildStory(input: StoryInput): string {
  const name = input.childFirstName;
  const parts: string[] = [];

  if (input.outdoorMinutes > 0) {
    const first = input.activities[0];
    parts.push(
      first
        ? `We spent time outside today — ${first}.`
        : `We spent ${input.outdoorMinutes} minutes outside today.`,
    );
  } else if (input.outdoorSkippedReason) {
    parts.push(`We stayed in today (${input.outdoorSkippedReason}).`);
  } else if (input.activities[0]) {
    parts.push(`Today ${name} enjoyed ${input.activities[0]}.`);
  }

  for (const meal of input.meals) {
    parts.push(`${name} ${EATEN_LABEL[meal.eaten]} ${MEAL_LABEL[meal.meal]}.`);
  }

  for (const nap of input.naps) {
    parts.push(
      nap.end
        ? `Rest time went ${twelveHour(nap.start)} to ${twelveHour(nap.end)}.`
        : `${name} settled for a rest at ${twelveHour(nap.start)}.`,
    );
  }

  if (input.activities.length > 1) {
    parts.push(`Also today: ${input.activities.slice(1).join('; ')}.`);
  }

  if (input.photoCount > 0) {
    parts.push(
      input.photoCount === 1
        ? 'There is one new photo from today.'
        : `There are ${input.photoCount} new photos from today.`,
    );
  }

  if (parts.length === 0) {
    parts.push(`${name} had a steady, quiet day with us.`);
  }
  return parts.join(' ');
}
