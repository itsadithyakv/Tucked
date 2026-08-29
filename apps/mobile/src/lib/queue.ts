/**
 * Offline command queue for Room mode (build prompt §7).
 *
 * Every regulated write is an RPC command. The happy path calls the RPC
 * directly; when the network is down the command is queued with its capture
 * timestamp (`p_offline_recorded_at` — part of the audit trail) and flushed
 * IN ORDER when connectivity returns. Logical rejections (bad PIN, rule
 * violations) are never retried silently — they land in `failed` and stay
 * visible until a human resolves them: a regulated record must never be
 * silently dropped.
 *
 * v1 persistence is AsyncStorage (works on device and web preview alike);
 * the SQLite upgrade lands with device testing (decision 2026-08-29).
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { supabase } from './supabase';

const QUEUE_KEY = 'tucked.queue.v1';
const FAILED_KEY = 'tucked.queue.failed.v1';

export interface QueuedCommand {
  id: string;
  rpc: string;
  args: Record<string, unknown>;
  enqueuedAt: string; // ISO — becomes p_offline_recorded_at
  attempts: number;
}

export interface FailedCommand extends QueuedCommand {
  reason: string;
}

type Listener = () => void;

let queue: QueuedCommand[] = [];
let failed: FailedCommand[] = [];
let loaded = false;
let flushing = false;
const listeners = new Set<Listener>();

function notify() {
  for (const l of listeners) l();
}

async function persist() {
  try {
    await AsyncStorage.setItem(QUEUE_KEY, JSON.stringify(queue));
    await AsyncStorage.setItem(FAILED_KEY, JSON.stringify(failed));
  } catch {
    /* storage hiccup: the in-memory queue still flushes this session */
  }
}

export async function loadQueue(): Promise<void> {
  if (loaded) return;
  loaded = true;
  try {
    queue = JSON.parse((await AsyncStorage.getItem(QUEUE_KEY)) ?? '[]');
    failed = JSON.parse((await AsyncStorage.getItem(FAILED_KEY)) ?? '[]');
  } catch {
    queue = [];
    failed = [];
  }
  notify();
}

function isNetworkError(message: string): boolean {
  const m = message.toLowerCase();
  return m.includes('fetch') || m.includes('network') || m.includes('timeout');
}

export interface RpcResult {
  ok: boolean;
  queued: boolean;
  error?: string;
  data?: unknown;
}

/** Run a regulated write: direct when online, queued when the network fails.
 * Logical errors (bad PIN, rule violations) return immediately — the person
 * holding the device fixes them now, nothing is queued. */
export async function runCommand(rpc: string, args: Record<string, unknown>): Promise<RpcResult> {
  await loadQueue();
  // Preserve ordering: if a queue already exists, this command joins the line
  // behind it rather than jumping ahead.
  if (queue.length === 0) {
    try {
      const { data, error } = await supabase.rpc(rpc, args);
      if (!error) return { ok: true, queued: false, data };
      if (!isNetworkError(error.message)) return { ok: false, queued: false, error: error.message };
    } catch (e) {
      if (!isNetworkError(String(e))) return { ok: false, queued: false, error: String(e) };
    }
  }
  const cmd: QueuedCommand = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    rpc,
    args,
    enqueuedAt: new Date().toISOString(),
    attempts: 0,
  };
  queue.push(cmd);
  await persist();
  notify();
  void flushQueue();
  return { ok: true, queued: true };
}

/** Flush in order; stop at the first network error; move logical rejections
 * to the visible failed list. */
export async function flushQueue(): Promise<void> {
  await loadQueue();
  if (flushing) return;
  flushing = true;
  try {
    while (queue.length > 0) {
      const cmd = queue[0]!;
      const args = { ...cmd.args, p_offline_recorded_at: cmd.enqueuedAt };
      let errorMessage: string | null = null;
      try {
        const { error } = await supabase.rpc(cmd.rpc, args);
        errorMessage = error ? error.message : null;
      } catch (e) {
        errorMessage = String(e);
      }
      if (errorMessage === null) {
        queue.shift();
      } else if (isNetworkError(errorMessage)) {
        cmd.attempts += 1;
        break; // still offline — try again later, order preserved
      } else {
        queue.shift();
        failed.push({ ...cmd, reason: errorMessage });
      }
      await persist();
      notify();
    }
  } finally {
    flushing = false;
  }
}

export function queueState() {
  return { pending: queue.length, failed: [...failed] };
}

export async function dismissFailed(id: string): Promise<void> {
  failed = failed.filter((f) => f.id !== id);
  await persist();
  notify();
}

export function subscribeQueue(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** Periodic retry while the app is open. */
export function startQueuePump(): () => void {
  const interval = setInterval(() => void flushQueue(), 15_000);
  return () => clearInterval(interval);
}
