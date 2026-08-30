'use client';

/** Messaging with a visible audience: the parent chose who reads each thread,
 * and that choice is shown on every message — the supervisor is never silently
 * copied, and never silently excluded either. */

import { useCallback, useEffect, useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { fmtTime, useConsole } from '@/lib/console';

interface Msg {
  id: string;
  body: string;
  sent_at: string;
  sender_person_id: string;
  sender: { full_name: string } | null;
}

interface Thread {
  id: string;
  audience: 'teacher' | 'supervisor' | 'both';
  created_at: string;
  child: { full_name: string } | null;
  created_by_person: { full_name: string } | null;
  message: Msg[];
}

const AUDIENCE_LABEL: Record<Thread['audience'], string> = {
  teacher: 'room team',
  supervisor: 'supervisor only',
  both: 'room team + supervisor',
};

export default function MessagesPage() {
  const { centre, personId } = useConsole();
  const [threads, setThreads] = useState<Thread[]>([]);
  const [replyFor, setReplyFor] = useState<string | null>(null);
  const [reply, setReply] = useState('');

  const load = useCallback(() => {
    getSupabase()
      .from('message_thread')
      .select(
        'id, audience, created_at, child:child_id(full_name), created_by_person:created_by(full_name), message(id, body, sent_at, sender_person_id, sender:sender_person_id(full_name))',
      )
      .eq('centre_id', centre.id)
      .order('created_at', { ascending: false })
      .then(({ data }) => setThreads((data as never) ?? []));
  }, [centre.id]);

  useEffect(load, [load]);

  async function sendReply(threadId: string) {
    if (!reply.trim()) return;
    await getSupabase().from('message').insert({
      centre_id: centre.id,
      thread_id: threadId,
      sender_person_id: personId,
      body: reply.trim(),
    });
    setReply('');
    setReplyFor(null);
    load();
  }

  return (
    <>
      <h1>Messages</h1>
      {threads.length === 0 ? <p className="muted">No messages from families yet.</p> : null}
      {threads.map((t) => (
        <section className="card" key={t.id}>
          <h2>
            {t.child?.full_name}{' '}
            <span className="pill ok">{AUDIENCE_LABEL[t.audience]}</span>
          </h2>
          <p className="caption">Started by {t.created_by_person?.full_name}</p>
          {[...t.message]
            .sort((a, b) => a.sent_at.localeCompare(b.sent_at))
            .map((m) => (
              <p key={m.id} className={m.sender_person_id === personId ? undefined : 'muted'}>
                <strong>{m.sender?.full_name ?? '—'}:</strong> {m.body}{' '}
                <span className="caption">{fmtTime(m.sent_at, centre.timezone)}</span>
              </p>
            ))}
          {replyFor === t.id ? (
            <div className="toolbar">
              <input
                value={reply}
                onChange={(e) => setReply(e.target.value)}
                placeholder="Your reply"
                size={50}
                autoFocus
              />
              <button onClick={() => void sendReply(t.id)}>Send</button>
              <button className="quiet" onClick={() => setReplyFor(null)}>
                Cancel
              </button>
            </div>
          ) : (
            <button
              className="quiet small"
              onClick={() => {
                setReply('');
                setReplyFor(t.id);
              }}
            >
              Reply
            </button>
          )}
        </section>
      ))}
    </>
  );
}
