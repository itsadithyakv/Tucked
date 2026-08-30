import { useCallback, useEffect, useState } from 'react';
import { FlatList, StyleSheet, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { safeArrivalDue, staffRequiredEffective, activeWindow } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
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

function Rooms() {
  const { profile } = useAuth();
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

  const present = day ? presentByRoom(day.attendance) : new Map<string, Set<string>>();

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

  function roomRatio(roomId: string, preset: Parameters<typeof staffRequiredEffective>[0]) {
    if (!day) return null;
    const count = present.get(roomId)?.size ?? 0;
    const counted = day.shifts.filter((s) => s.room_id === roomId && s.counted_in_ratio && !s.out_at).length;
    const local = new Date().toLocaleTimeString('en-CA', { hour12: false, timeZone: day.centre.timezone });
    const nowMin = minutesOfDay(local);
    const openMin = minutesOfDay(day.centre.opens_at);
    const closeMin = minutesOfDay(day.centre.closes_at);
    const hours = (closeMin - openMin) / 60;
    const window = activeWindow(nowMin - openMin, closeMin - nowMin, hours, false);
    const { required } = staffRequiredEffective(preset, count, {
      window,
      programHoursPerDay: hours,
      outdoors: false,
    });
    return { count, counted, required, ok: counted >= required };
  }

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
      <Title>{day?.centre.name ?? 'Rooms'}</Title>
      <Caption>{profile ? profile.fullName : ''}</Caption>
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
      {chaseFor === null && chaseList.length > 0 ? (
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
        contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}
        renderItem={({ item, index }) => {
          const ratio = roomRatio(item.id, item.preset);
          return (
            <Card wash={(['mist', 'mint', 'sand'] as const)[index % 3]}>
              <View style={styles.rowBetween}>
                <Heading>{item.name}</Heading>
                {ratio ? (
                  <Pill kind={ratio.ok ? 'ok' : 'now'}>
                    {ratio.ok ? 'Ratio OK' : `Needs ${ratio.required}`}
                  </Pill>
                ) : null}
              </View>
              <Body muted>
                {ratio ? `${ratio.count} present · ${ratio.counted} staff in ratio` : ''}
              </Body>
              <Button
                label="Open room"
                onPress={() => router.push({ pathname: '/room/[id]', params: { id: item.id } })}
              />
            </Card>
          );
        }}
      />

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

export default function RoomsTab() {
  const [staff, setStaff] = useState<{ personId: string; fullName: string; role: string }[]>([]);
  useFocusEffect(
    useCallback(() => {
      loadRoomDay().then((d) => setStaff(d?.staff ?? []));
    }, []),
  );
  return (
    <RecorderProvider staff={staff}>
      <Rooms />
    </RecorderProvider>
  );
}

const styles = StyleSheet.create({
  rowBetween: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: space.sm,
  },
});
