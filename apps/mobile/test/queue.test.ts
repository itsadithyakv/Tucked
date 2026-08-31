/**
 * The offline command queue (s. 82(2), build prompt §7).
 *
 * A phone in a church basement on a field trip still has to record that a
 * child was signed out, and that record has to survive, keep its place in the
 * order, and never disappear quietly. Until now the only proof of that was a
 * person putting a device in airplane mode and watching — which is worth
 * doing, and is now the runbook in references/airplane-mode-runbook.md, but it
 * is not something CI can run before every merge. These are.
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';

// ── the two things the queue talks to ────────────────────────────────────────
const store = new Map<string, string>();
vi.mock('@react-native-async-storage/async-storage', () => ({
  default: {
    getItem: async (k: string) => store.get(k) ?? null,
    setItem: async (k: string, v: string) => {
      store.set(k, v);
    },
    removeItem: async (k: string) => {
      store.delete(k);
    },
  },
}));

/** Calls made to the server, in order, so ordering can be asserted. */
const calls: { rpc: string; args: Record<string, unknown> }[] = [];
/** What the next RPC should do. */
let responder: (rpc: string, args: Record<string, unknown>) => { error: { message: string } | null };

vi.mock('../src/lib/supabase', () => ({
  supabase: {
    rpc: async (rpc: string, args: Record<string, unknown>) => {
      calls.push({ rpc, args: { ...args } });
      const { error } = responder(rpc, args);
      return { data: error ? null : { ok: true }, error };
    },
  },
}));

const ONLINE = () => ({ error: null });
const OFFLINE = () => ({ error: { message: 'TypeError: Failed to fetch' } });
const REFUSED = (message: string) => () => ({ error: { message } });

/** The queue holds module-level state, so each test gets a fresh copy. */
async function freshQueue() {
  vi.resetModules();
  return await import('../src/lib/queue');
}

/** runCommand fires a flush without awaiting it. Awaiting flushQueue JOINS
 * that in-flight attempt, so a test must let it settle before it changes what
 * the network is doing — otherwise it is asserting against the previous
 * attempt's outcome. */
async function settle(q: { flushQueue: () => Promise<void> }) {
  await q.flushQueue();
}

beforeEach(() => {
  store.clear();
  calls.length = 0;
  responder = ONLINE;
});

describe('online', () => {
  it('s82_2_an_online_write_goes_straight_through_and_is_not_queued', async () => {
    const q = await freshQueue();
    const result = await q.runCommand('record_attendance', { p_child: 'a' });

    expect(result).toMatchObject({ ok: true, queued: false });
    expect(calls).toHaveLength(1);
    expect(q.queueState().pending).toBe(0);
  });

  it('s82_2_a_refused_write_is_never_queued_because_the_person_is_standing_there', async () => {
    const q = await freshQueue();
    responder = REFUSED('that PIN is not right');

    const result = await q.runCommand('record_attendance', { p_child: 'a' });

    // A bad PIN or a broken rule is not a connectivity problem. Queuing it
    // would hide a mistake the educator could fix in three seconds.
    expect(result).toMatchObject({ ok: false, queued: false, error: 'that PIN is not right' });
    expect(q.queueState().pending).toBe(0);
    expect(q.queueState().failed).toHaveLength(0);
  });
});

describe('offline', () => {
  it('s82_2_a_write_with_no_signal_is_kept_rather_than_lost', async () => {
    const q = await freshQueue();
    responder = OFFLINE;

    const result = await q.runCommand('record_attendance', { p_child: 'a' });

    expect(result).toMatchObject({ ok: true, queued: true });
    expect(q.queueState().pending).toBe(1);
  });

  it('s82_2_later_writes_join_the_line_rather_than_jumping_it', async () => {
    const q = await freshQueue();
    responder = OFFLINE;
    await q.runCommand('record_attendance', { p_child: 'first' });
    await settle(q);
    calls.length = 0;

    // Even if the network came back this instant, the second command must not
    // reach the server before the first: an arrive that lands after its own
    // depart is a register nobody can defend.
    responder = ONLINE;
    const result = await q.runCommand('record_attendance', { p_child: 'second' });
    expect(result).toMatchObject({ queued: true });

    await q.flushQueue();
    expect(calls.map((c) => c.args.p_child)).toEqual(['first', 'second']);
  });

  it('s82_2_the_queue_flushes_in_the_order_it_was_written', async () => {
    const q = await freshQueue();
    responder = OFFLINE;
    await q.runCommand('record_attendance', { p_child: 'a' });
    await q.runCommand('record_attendance', { p_child: 'b' });
    await q.runCommand('record_attendance', { p_child: 'c' });
    await settle(q);
    calls.length = 0;

    responder = ONLINE;
    await q.flushQueue();

    expect(calls.map((c) => c.args.p_child)).toEqual(['a', 'b', 'c']);
    expect(q.queueState().pending).toBe(0);
  });

  it('s82_2_every_queued_write_carries_the_moment_it_actually_happened', async () => {
    const q = await freshQueue();
    responder = OFFLINE;
    await q.runCommand('record_attendance', { p_child: 'a' });
    await settle(q);
    calls.length = 0;

    responder = ONLINE;
    await q.flushQueue();

    // s. 72(3): the time is when the child arrived, not when the phone found
    // a signal. p_offline_recorded_at is that, and it is part of the audit
    // trail rather than a nicety.
    const sent = calls[0]!.args.p_offline_recorded_at;
    expect(typeof sent).toBe('string');
    expect(Number.isNaN(Date.parse(sent as string))).toBe(false);
  });

  it('s82_2_a_flush_that_hits_the_network_again_stops_and_keeps_the_order', async () => {
    const q = await freshQueue();
    responder = OFFLINE;
    await q.runCommand('record_attendance', { p_child: 'a' });
    await q.runCommand('record_attendance', { p_child: 'b' });
    await settle(q);
    calls.length = 0;

    // the first goes through, then the signal drops again
    let n = 0;
    responder = () => (n++ === 0 ? { error: null } : { error: { message: 'network request failed' } });
    await q.flushQueue();

    expect(q.queueState().pending).toBe(1);
    calls.length = 0;
    responder = ONLINE;
    await q.flushQueue();
    expect(calls.map((c) => c.args.p_child)).toEqual(['b']);
  });
});

describe('nothing is ever silently dropped', () => {
  it('s82_2_a_rule_the_server_refuses_lands_in_front_of_a_human', async () => {
    const q = await freshQueue();
    responder = OFFLINE;
    await q.runCommand('record_attendance', { p_child: 'a' });
    await settle(q);

    responder = REFUSED('sign-in blocked: Ivan is excluded');
    await q.flushQueue();

    // It leaves the queue — retrying forever would block everything behind
    // it — but it becomes visible, with the reason, until a person deals with
    // it. A regulated write must never just vanish.
    expect(q.queueState().pending).toBe(0);
    expect(q.queueState().failed).toHaveLength(1);
    expect(q.queueState().failed[0]!.reason).toContain('excluded');
  });

  it('s82_2_a_refusal_does_not_block_the_writes_behind_it', async () => {
    const q = await freshQueue();
    responder = OFFLINE;
    await q.runCommand('record_attendance', { p_child: 'bad' });
    await q.runCommand('record_attendance', { p_child: 'good' });
    await settle(q);
    calls.length = 0;

    responder = (_rpc, args) =>
      args.p_child === 'bad' ? { error: { message: 'refused' } } : { error: null };
    await q.flushQueue();

    expect(q.queueState().pending).toBe(0);
    expect(q.queueState().failed.map((f) => f.args.p_child)).toEqual(['bad']);
    expect(calls.map((c) => c.args.p_child)).toEqual(['bad', 'good']);
  });

  it('s82_2_a_failure_stays_until_a_person_dismisses_it', async () => {
    const q = await freshQueue();
    responder = OFFLINE;
    await q.runCommand('record_attendance', { p_child: 'a' });
    await settle(q);
    responder = REFUSED('refused');
    await q.flushQueue();

    const id = q.queueState().failed[0]!.id;
    await q.dismissFailed(id);
    expect(q.queueState().failed).toHaveLength(0);
  });
});

describe('the device can be closed and reopened', () => {
  it('s82_2_a_queued_write_survives_the_app_being_shut', async () => {
    const first = await freshQueue();
    responder = OFFLINE;
    await first.runCommand('record_attendance', { p_child: 'a' });
    await settle(first);
    expect(first.queueState().pending).toBe(1);

    // a fresh module registry is the app starting again; AsyncStorage persists
    const second = await freshQueue();
    await second.loadQueue();
    expect(second.queueState().pending).toBe(1);

    calls.length = 0;
    responder = ONLINE;
    await second.flushQueue();
    expect(calls.map((c) => c.args.p_child)).toEqual(['a']);
  });

  it('s82_2_a_visible_failure_survives_it_too', async () => {
    const first = await freshQueue();
    responder = OFFLINE;
    await first.runCommand('record_attendance', { p_child: 'a' });
    await settle(first);
    responder = REFUSED('refused');
    await first.flushQueue();
    expect(first.queueState().failed).toHaveLength(1);

    const second = await freshQueue();
    await second.loadQueue();
    expect(second.queueState().failed).toHaveLength(1);
  });

  it('s82_2_corrupt_storage_starts_empty_rather_than_crashing_the_room_device', async () => {
    store.set('tucked.queue.v1', 'not json at all');
    const q = await freshQueue();
    await q.loadQueue();

    // The room board must open. An unreadable queue file is a bad day; a
    // device that will not start is a worse one.
    expect(q.queueState().pending).toBe(0);
  });
});

describe('the screen is told', () => {
  it('s82_2_a_subscriber_hears_about_a_queued_write', async () => {
    const q = await freshQueue();
    const heard = vi.fn();
    q.subscribeQueue(heard);

    responder = OFFLINE;
    await q.runCommand('record_attendance', { p_child: 'a' });

    expect(heard).toHaveBeenCalled();
  });

  it('s82_2_and_when_the_flush_stalls_so_the_banner_can_say_so', async () => {
    const q = await freshQueue();
    responder = OFFLINE;
    await q.runCommand('record_attendance', { p_child: 'a' });

    const heard = vi.fn();
    q.subscribeQueue(heard);
    await q.flushQueue(); // still offline
    expect(heard).toHaveBeenCalled();
  });
});
