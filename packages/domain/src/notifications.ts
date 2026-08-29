/**
 * The Now / Later rule — build prompt §6. Routing is data, not scattered ifs,
 * so the table can be shown to a supervisor and tested exhaustively.
 *
 * Now: always pushes, sound on, bypasses quiet hours, requires acknowledgement.
 * Later: never interrupts; batched into the daily story plus a badge. Families
 * may opt UP to real-time per category; the default is quiet.
 */

export const NOW_EVENTS = [
  'illness_sent_home',
  'accident_report',
  'pickup_problem',
  'missing_expected_arrival',
  'emergency',
  'medication_issue',
  'supervisor_urgent',
] as const;

export const LATER_EVENTS = [
  'meal',
  'nap',
  'diaper_toileting',
  'photo',
  'activity',
  'menu',
  'announcement',
] as const;

export type NowEvent = (typeof NOW_EVENTS)[number];
export type LaterEvent = (typeof LATER_EVENTS)[number];
export type NotificationEvent = NowEvent | LaterEvent;

export type Channel = 'now' | 'later';
export type Delivery = 'push_loud' | 'push_quiet' | 'digest';

export interface Routing {
  channel: Channel;
  delivery: Delivery;
  sound: boolean;
  bypassQuietHours: boolean;
  requiresAcknowledgement: boolean;
}

export interface FamilyPrefs {
  /** Later categories this adult opted UP to real-time. Now is never optional. */
  realtimeOptIn: ReadonlySet<LaterEvent>;
}

const NOW_SET: ReadonlySet<string> = new Set(NOW_EVENTS);

export function channelFor(event: NotificationEvent): Channel {
  return NOW_SET.has(event) ? 'now' : 'later';
}

export function route(event: NotificationEvent, prefs?: FamilyPrefs): Routing {
  if (channelFor(event) === 'now') {
    return {
      channel: 'now',
      delivery: 'push_loud',
      sound: true,
      bypassQuietHours: true,
      requiresAcknowledgement: true,
    };
  }
  const optedUp = prefs?.realtimeOptIn.has(event as LaterEvent) ?? false;
  return {
    channel: 'later',
    delivery: optedUp ? 'push_quiet' : 'digest',
    sound: false,
    bypassQuietHours: false,
    requiresAcknowledgement: false,
  };
}
