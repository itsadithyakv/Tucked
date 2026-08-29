import { useCallback, useEffect, useState } from 'react';
import { FlatList, View } from 'react-native';
import { Link, Redirect, useFocusEffect } from 'expo-router';
import Animated, { FadeInDown } from 'react-native-reanimated';
import { enCA, safeArrivalDue } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { runCommand } from '@/lib/queue';
import { RecorderProvider, useRecorder } from '@/lib/recorder';
import { loadRoomDay, presentByRoom, refreshEvacuationCache } from '@/lib/roomData';
import type { RoomDay } from '@/lib/roomData';
import { loadQueue, queueState, startQueuePump, subscribeQueue } from '@/lib/queue';
import {
  Body,
  Button,
  Caption,
  Card,
  Choices,
  Field,
  Heading,
  Pill,
  Screen,
  Sheet,
  Title,
} from '@/ui/components';

const CONTACT_VIA = [
  { value: 'phone', label: 'Phone' },
  { value: 'message', label: 'Message' },
  { value: 'in_person', label: 'In person' },
] as const;

function minutesOfDay(hhmmss: string): number {
  const [h, m] = hhmmss.split(':');
  return Number(h) * 60 + Number(m);
}

function Hub() {
  const { session, loading, profile } = useAuth();
  const { getRecorder, invalidate } = useRecorder();
  const [day, setDay] = useState<RoomDay | null>(null);
  const [queue, setQueue] = useState(queueState());
  const [chaseFor, setChaseFor] = useState<{ childId: string; name: string } | null>(null);
  const [via, setVia] = useState<(typeof CONTACT_VIA)[number]['value'] | null>(null);
  const [outcome, setOutcome] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const refresh = useCallback(() => {
    loadRoomDay().then((d) => {
      setDay(d);
      if (d) void refreshEvacuationCache(d);
    });
  }, []);

  useFocusEffect(refresh);

  useEffect(() => {
    void loadQueue();
    const stop = startQueuePump();
    const unsub = subscribeQueue(() => setQueue(queueState()));
    return () => {
      stop();
      unsub();
    };
  }, []);

  if (!loading && !session) return <Redirect href="/sign-in" />;

  const present = day ? presentByRoom(day.attendance) : new Map<string, Set<string>>();

  // s. 50 safe arrival: expected children unaccounted for after the cut-off.
  const chaseList = (() => {
    if (!day) return [];
    const local = new Date().toLocaleTimeString('en-CA', { hour12: false, timeZone: day.centre.timezone });
    const due = safeArrivalDue({
      expectedChildIds: day.children.map((c) => c.id),
      arrivedChildIds: day.attendance.filter((a) => a.event_type === 'arrive').map((a) => a.child_id),
      markedAbsentChildIds: day.attendance.filter((a) => a.event_type === 'absent').map((a) => a.child_id),
      alreadyPromptedChildIds: day.safeChecks.map((s) => s.child_id),
      nowMinutes: minutesOfDay(local),
      cutoffMinutes: minutesOfDay(day.centre.safe_arrival_cutoff),
    });
    const names = new Map(day.children.map((c) => [c.id, c.full_name]));
    return due.map((id) => ({ childId: id, name: names.get(id) ?? '' }));
  })();

  async function recordOutcome() {
    const target = chaseFor;
    if (!target || !via || !outcome.trim() || !day) return;
    setChaseFor(null);
    const recorder = await getRecorder();
    if (!recorder) return;
    const today = new Date().toLocaleDateString('en-CA', { timeZone: day.centre.timezone });
    const result = await runCommand('record_safe_arrival_outcome', {
      p_centre: day.centre.id,
      p_child: target.childId,
      p_date: today,
      p_contacted_via: via,
      p_outcome: outcome.trim(),
      p_recorder: recorder.personId,
      p_pin: recorder.pin,
    });
    if (!result.ok) {
      if (result.error?.includes('PIN')) invalidate();
      setNotice(result.error ?? 'That did not work.');
    } else {
      setNotice(null);
      refresh();
    }
  }

  return (
    <Screen>
      <Title>{day?.centre.name ?? enCA.terms.centre}</Title>
      <Caption>
        {profile ? `${profile.fullName} · ${profile.roles.map((r) => r.role).join(', ')}` : ''}
      </Caption>
      {queue.pending > 0 ? (
        <Card wash="mist">
          <Body muted>{`Working offline — ${queue.pending} item${queue.pending === 1 ? '' : 's'} will sync when the connection returns.`}</Body>
        </Card>
      ) : null}
      {queue.failed.length > 0 ? (
        <Card wash="sand">
          <Pill kind="due">Needs attention</Pill>
          <Body muted>{`${queue.failed.length} record${queue.failed.length === 1 ? '' : 's'} could not be saved: ${queue.failed[0]?.reason ?? ''}`}</Body>
        </Card>
      ) : null}
      {notice ? (
        <Card wash="mist">
          <Body muted>{notice}</Body>
        </Card>
      ) : null}
      {chaseList.length > 0 ? (
        <Card wash="sand">
          <Heading>Safe arrival</Heading>
          <Body muted>Expected but not arrived — contact the family and record the outcome.</Body>
          {chaseList.slice(0, 5).map((c) => (
            <Button
              key={c.childId}
              label={`Follow up on ${c.name}`}
              kind="quiet"
              onPress={() => {
                setVia(null);
                setOutcome('');
                setChaseFor(c);
              }}
            />
          ))}
        </Card>
      ) : null}
      <FlatList
        data={day?.rooms ?? []}
        keyExtractor={(r) => r.id}
        contentContainerStyle={{ gap: space.cardGap }}
        renderItem={({ item, index }) => {
          const count = present.get(item.id)?.size ?? 0;
          return (
            <Animated.View entering={FadeInDown.delay(index * 70).springify().damping(15)}>
              <Card wash={(['mist', 'mint', 'sand'] as const)[index % 3]}>
                <Heading>{item.name}</Heading>
                <Body muted>{`${count} present now`}</Body>
                <Link href={{ pathname: '/room/[id]', params: { id: item.id } }} asChild>
                  <Button label={`Open ${item.name}`} kind="quiet" onPress={() => {}} />
                </Link>
              </Card>
            </Animated.View>
          );
        }}
      />
      <View style={{ marginTop: 'auto', gap: space.sm }}>
        <Link href="/evacuation" asChild>
          <Button label="Evacuation screen" onPress={() => {}} />
        </Link>
        <Button label={enCA.auth.signOut} kind="quiet" onPress={() => supabase.auth.signOut()} />
      </View>

      <Sheet
        visible={chaseFor !== null}
        onClose={() => setChaseFor(null)}
        title={chaseFor ? `Reach ${chaseFor.name.split(' ')[0]}'s family` : ''}
      >
        <Body muted>Record the attempt and its outcome (safe arrival, s. 50).</Body>
        <Choices options={[...CONTACT_VIA]} value={via} onChange={setVia} />
        <Field
          placeholder="Outcome — e.g. reached mum, home sick today"
          value={outcome}
          onChangeText={setOutcome}
        />
        <Button label="Record outcome" onPress={() => void recordOutcome()} />
        <Button label="Cancel" kind="quiet" onPress={() => setChaseFor(null)} />
      </Sheet>
    </Screen>
  );
}

export default function RoomHub() {
  const [staff, setStaff] = useState<{ personId: string; fullName: string; role: string }[]>([]);

  useFocusEffect(
    useCallback(() => {
      loadRoomDay().then((d) => setStaff(d?.staff ?? []));
    }, []),
  );

  return (
    <RecorderProvider staff={staff}>
      <Hub />
    </RecorderProvider>
  );
}
