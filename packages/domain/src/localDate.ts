/**
 * The centre's calendar day and clock — never the device's, and never UTC's.
 *
 * `new Date().toISOString().slice(0, 10)` is the UTC date. In Toronto that rolls
 * over to tomorrow at 8 p.m. in summer and 7 p.m. in winter, which is precisely
 * when a family opens the app to read the day's story. Every `date` column in
 * this schema is a CENTRE-LOCAL day — the database derives it with
 * `at time zone centre.timezone` — so a client query against one has to ask for
 * the day the database filed it under, or it asks for tomorrow and finds
 * nothing.
 *
 * Pure, and Intl-only: it runs on Hermes, in Node for tests, and in the browser.
 */

function parts(timeZone: string, at: Date): Record<string, string> {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    // h23, not hour12:false — some engines print midnight as "24" otherwise
    hourCycle: 'h23',
  });
  const out: Record<string, string> = {};
  for (const p of fmt.formatToParts(at)) out[p.type] = p.value;
  return out;
}

/** A calendar date from its Y/M/D, formatted without any clock involved. */
function isoFromYmd(y: number, m: number, d: number): string {
  return `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

/** The centre-local calendar day, as the `YYYY-MM-DD` a Postgres `date` takes. */
export function localDateISO(timeZone: string, at: Date = new Date()): string {
  const p = parts(timeZone, at);
  return `${p.year}-${p.month}-${p.day}`;
}

/** Minutes since centre-local midnight — what a safe-arrival cutoff compares to. */
export function localMinutes(timeZone: string, at: Date = new Date()): number {
  const p = parts(timeZone, at);
  return Number(p.hour) * 60 + Number(p.minute);
}

/** Whole days added to a calendar date. Pure arithmetic: no clock, no DST. */
export function addDaysISO(iso: string, days: number): string {
  const [y, m, d] = iso.split('-').map(Number) as [number, number, number];
  const date = new Date(Date.UTC(y, m - 1, d + days));
  return isoFromYmd(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate());
}

/** ISO weekday of a calendar date: Monday 1 … Sunday 7. */
export function isoWeekdayOf(iso: string): number {
  const [y, m, d] = iso.split('-').map(Number) as [number, number, number];
  const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return dow === 0 ? 7 : dow;
}

/** The Monday that starts the centre-local week — a `menu_week.week_start`. */
export function localWeekStartISO(timeZone: string, at: Date = new Date()): string {
  const today = localDateISO(timeZone, at);
  return addDaysISO(today, -(isoWeekdayOf(today) - 1));
}
