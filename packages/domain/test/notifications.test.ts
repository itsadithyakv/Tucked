import { describe, expect, it } from 'vitest';
import {
  LATER_EVENTS,
  NOW_EVENTS,
  channelFor,
  route,
} from '../src/notifications';

describe('Now / Later routing (build prompt §6)', () => {
  it('now_events_always_push_loud_and_require_acknowledgement', () => {
    for (const e of NOW_EVENTS) {
      const r = route(e);
      expect(r).toEqual({
        channel: 'now',
        delivery: 'push_loud',
        sound: true,
        bypassQuietHours: true,
        requiresAcknowledgement: true,
      });
    }
  });

  it('later_events_never_interrupt_by_default', () => {
    for (const e of LATER_EVENTS) {
      const r = route(e);
      expect(r.channel).toBe('later');
      expect(r.delivery).toBe('digest');
      expect(r.sound).toBe(false);
      expect(r.bypassQuietHours).toBe(false);
      expect(r.requiresAcknowledgement).toBe(false);
    }
  });

  it('later_opt_up_is_quiet_realtime_never_loud', () => {
    const r = route('photo', { realtimeOptIn: new Set(['photo']) });
    expect(r.delivery).toBe('push_quiet');
    expect(r.sound).toBe(false);
    expect(r.bypassQuietHours).toBe(false);
  });

  it('opt_up_is_per_category', () => {
    const prefs = { realtimeOptIn: new Set(['photo'] as const) };
    expect(route('meal', prefs).delivery).toBe('digest');
  });

  it('every_event_has_exactly_one_channel', () => {
    const all = [...NOW_EVENTS, ...LATER_EVENTS];
    expect(new Set(all).size).toBe(all.length);
    for (const e of all) expect(['now', 'later']).toContain(channelFor(e));
  });
});
