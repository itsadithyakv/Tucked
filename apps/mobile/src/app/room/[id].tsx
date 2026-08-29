import { useCallback, useMemo, useState } from 'react';
import { FlatList, Modal, StyleSheet, View } from 'react-native';
import { Redirect, router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import {
  activeWindow,
  sleepCheckRequired,
  staffRequiredEffective,
} from '@tucked/domain';
import { colour, radius, shadow, space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { runCommand } from '@/lib/queue';
import { RecorderProvider, useRecorder } from '@/lib/recorder';
import { loadRoomDay, presentByRoom } from '@/lib/roomData';
import type { RoomDay } from '@/lib/roomData';
import { Body, Button, Caption, Card, Field, Heading, Pill, Screen, Title } from '@/ui/components';

interface PickupOption {
  personId: string | null;
  label: string;
}

function ageMonths(dob: string): number {
  const d = new Date(dob);
  const now = new Date();
  return (now.getFullYear() - d.getFullYear()) * 12 + (now.getMonth() - d.getMonth());
}

function minutesOfDay(hhmmss: string): number {
  const [h, m] = hhmmss.split(':');
  return Number(h) * 60 + Number(m);
}

function Board() {
  const params = useLocalSearchParams<{ id: string }>();
  const roomId = params.id;
  const { getRecorder, invalidate } = useRecorder();
  const [day, setDay] = useState<RoomDay | null>(null);
  const [busyChild, setBusyChild] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [pickupFor, setPickupFor] = useState<{ childId: string; options: PickupOption[] } | null>(null);
  const [namedPickup, setNamedPickup] = useState('');

  const refresh = useCallback(() => {
    loadRoomDay().then(setDay);
  }, []);
  useFocusEffect(refresh);

  const room = day?.rooms.find((r) => r.id === roomId) ?? null;
  const present = useMemo(
    () => (day ? (presentByRoom(day.attendance).get(roomId) ?? new Set<string>()) : new Set<string>()),
    [day, roomId],
  );
  const roomChildren = useMemo(
    () => (day ? day.children.filter((c) => c.current_room_id === roomId || present.has(c.id)) : []),
    [day, roomId, present],
  );

  // live ratio: staff on shift in this room and counted, vs required for the
  // present count in the current window (ss. 8–11 via the domain engine)
  const ratio = useMemo(() => {
    if (!day || !room) return null;
    const counted = day.shifts.filter((s) => s.room_id === roomId && s.counted_in_ratio && !s.out_at).length;
    const now = new Date();
    const local = now.toLocaleTimeString('en-CA', { hour12: false, timeZone: day.centre.timezone });
    const nowMin = minutesOfDay(local);
    const openMin = minutesOfDay(day.centre.opens_at);
    const closeMin = minutesOfDay(day.centre.closes_at);
    const hours = (closeMin - openMin) / 60;
    const window = activeWindow(nowMin - openMin, closeMin - nowMin, hours, false);
    const { required, reduced } = staffRequiredEffective(room.preset, present.size, {
      window,
      programHoursPerDay: hours,
      outdoors: false,
    });
    return { counted, required, reduced, ok: counted >= required };
  }, [day, room, roomId, present]);

  // sleep state per under-24-month child: napping since / last check
  const sleep = useMemo(() => {
    if (!day) return new Map<string, { napStart: string; lastCheck: string | null }>();
    const map = new Map<string, { napStart: string; lastCheck: string | null }>();
    for (const log of day.sleepLogs) {
      if (log.log_type === 'nap_start') map.set(log.child_id, { napStart: log.logged_at, lastCheck: null });
      else if (log.log_type === 'nap_end') map.delete(log.child_id);
      else if (log.log_type === 'sleep_check') {
        const s = map.get(log.child_id);
        if (s) s.lastCheck = log.logged_at;
      }
    }
    return map;
  }, [day]);

  async function act(childId: string, fn: (recorder: { personId: string; pin: string }) => Promise<{ ok: boolean; queued: boolean; error?: string }>) {
    setNotice(null);
    const recorder = await getRecorder();
    if (!recorder) return;
    setBusyChild(childId);
    const result = await fn(recorder);
    setBusyChild(null);
    if (!result.ok) {
      if (result.error?.includes('PIN')) invalidate();
      setNotice(result.error ?? 'That did not work.');
    } else {
      if (result.queued) setNotice('Saved on this device — will sync when the connection returns.');
      refresh();
    }
  }

  function signIn(childId: string) {
    void act(childId, (recorder) =>
      runCommand('record_attendance', {
        p_centre: day!.centre.id,
        p_child: childId,
        p_event_type: 'arrive',
        p_room: roomId,
        p_actual_time: new Date().toISOString(),
        p_recorder: recorder.personId,
        p_pin: recorder.pin,
      }),
    );
  }

  async function openPickup(childId: string) {
    const { data } = await supabase
      .from('pickup_authorisation')
      .select('person_id, named_person, person:person_id(full_name)')
      .eq('child_id', childId)
      .is('revoked_at', null);
    const options: PickupOption[] = ((data as never as { person_id: string | null; named_person: string | null; person: { full_name: string } | null }[]) ?? [])
      .map((row) => ({
        personId: row.person_id,
        label: row.person?.full_name ?? row.named_person ?? 'Authorised pickup',
      }));
    setNamedPickup('');
    setPickupFor({ childId, options });
  }

  function signOut(childId: string, releasedTo: PickupOption | null, namedName: string | null) {
    setPickupFor(null);
    void act(childId, (recorder) =>
      runCommand('record_attendance', {
        p_centre: day!.centre.id,
        p_child: childId,
        p_event_type: 'depart',
        p_room: roomId,
        p_actual_time: new Date().toISOString(),
        p_recorder: recorder.personId,
        p_pin: recorder.pin,
        p_released_to_person: releasedTo?.personId ?? null,
        p_released_to_name: releasedTo ? null : namedName,
      }),
    );
  }

  function careLog(childId: string, logType: string, payload: Record<string, unknown>) {
    void act(childId, (recorder) =>
      runCommand('record_care_log', {
        p_centre: day!.centre.id,
        p_child: childId,
        p_room: roomId,
        p_type: logType,
        p_logged_at: new Date().toISOString(),
        p_payload: payload,
        p_recorder: recorder.personId,
        p_pin: recorder.pin,
      }),
    );
  }

  if (!day || !room) {
    return (
      <Screen>
        <Title>Room</Title>
      </Screen>
    );
  }

  const interval = day.centre.sleep_check_interval_minutes;

  return (
    <Screen>
      <View style={styles.rowBetween}>
        <Title>{room.name}</Title>
        <Button label="Back" kind="quiet" onPress={() => router.back()} />
      </View>
      <Card wash={ratio?.ok ? 'mint' : 'sand'}>
        <View style={styles.rowBetween}>
          <Heading>{`${present.size} present · ${ratio?.counted ?? 0} staff`}</Heading>
          <Pill kind={ratio?.ok ? 'ok' : 'now'}>
            {ratio?.ok ? 'Ratio OK' : `Needs ${ratio?.required ?? '?'}`}
          </Pill>
        </View>
        <Caption>
          {`Requires ${ratio?.required ?? '—'} in ratio${ratio?.reduced ? ' (reduced-ratio window)' : ''}`}
        </Caption>
      </Card>
      {notice ? (
        <Card wash="mist">
          <Body muted>{notice}</Body>
        </Card>
      ) : null}
      <FlatList
        data={roomChildren}
        keyExtractor={(c) => c.id}
        contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}
        renderItem={({ item }) => {
          const isPresent = present.has(item.id);
          const months = ageMonths(item.date_of_birth);
          const needsChecks = sleepCheckRequired(months, room.preset);
          const napping = sleep.get(item.id);
          const lastCheckMs = napping ? Date.parse(napping.lastCheck ?? napping.napStart) : 0;
          const checkDue = napping ? Date.now() - lastCheckMs >= interval * 60_000 : false;
          return (
            <Card>
              <View style={styles.rowBetween}>
                <Heading>{item.full_name}</Heading>
                <Pill kind={isPresent ? 'ok' : 'due'}>{isPresent ? 'Present' : 'Not in'}</Pill>
              </View>
              {napping ? (
                <Caption>
                  {`Napping · last check ${napping.lastCheck ? new Date(napping.lastCheck).toLocaleTimeString('en-CA', { hour12: false, hour: '2-digit', minute: '2-digit' }) : 'not yet'}`}
                </Caption>
              ) : null}
              <View style={styles.actions}>
                {isPresent ? (
                  <>
                    <Button
                      label={`Sign out ${item.full_name.split(' ')[0]}`}
                      kind="quiet"
                      busy={busyChild === item.id}
                      onPress={() => void openPickup(item.id)}
                    />
                    {needsChecks && !napping ? (
                      <Button label="Start nap" kind="quiet" onPress={() => careLog(item.id, 'nap_start', {})} />
                    ) : null}
                    {napping ? (
                      <>
                        <Button
                          label={checkDue ? 'Sleep check due' : 'Record sleep check'}
                          kind={checkDue ? 'primary' : 'quiet'}
                          onPress={() => careLog(item.id, 'sleep_check', { breathing_ok: true, position: 'back' })}
                        />
                        <Button label="End nap" kind="quiet" onPress={() => careLog(item.id, 'nap_end', {})} />
                      </>
                    ) : null}
                  </>
                ) : (
                  <Button
                    label={`Sign in ${item.full_name.split(' ')[0]}`}
                    busy={busyChild === item.id}
                    onPress={() => signIn(item.id)}
                  />
                )}
              </View>
            </Card>
          );
        }}
      />

      <Modal visible={pickupFor !== null} transparent animationType="fade" onRequestClose={() => setPickupFor(null)}>
        <View style={styles.backdrop}>
          <View style={styles.sheet}>
            <Heading>Released to</Heading>
            <Body muted>Release only to an authorised person, with identity confirmed (s. 50).</Body>
            {pickupFor?.options.map((option) => (
              <Button
                key={option.personId ?? option.label}
                label={option.label}
                kind="quiet"
                onPress={() => signOut(pickupFor.childId, option, null)}
              />
            ))}
            <Field
              placeholder="Someone else on the authorised list (name)"
              value={namedPickup}
              onChangeText={setNamedPickup}
            />
            <Button
              label="Confirm release"
              onPress={() => {
                if (pickupFor && namedPickup.trim()) signOut(pickupFor.childId, null, namedPickup.trim());
              }}
            />
            <Button label="Cancel" kind="quiet" onPress={() => setPickupFor(null)} />
          </View>
        </View>
      </Modal>
    </Screen>
  );
}

export default function RoomBoard() {
  const { session, loading } = useAuth();
  const [staff, setStaff] = useState<{ personId: string; fullName: string; role: string }[]>([]);

  useFocusEffect(
    useCallback(() => {
      loadRoomDay().then((d) => setStaff(d?.staff ?? []));
    }, []),
  );

  if (!loading && !session) return <Redirect href="/sign-in" />;

  return (
    <RecorderProvider staff={staff}>
      <Board />
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
  actions: { gap: space.sm },
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(23, 50, 92, 0.35)',
    justifyContent: 'flex-end',
    padding: space.base,
  },
  sheet: {
    backgroundColor: colour.surface,
    borderRadius: radius.xl,
    padding: space.lg,
    gap: space.md,
    ...shadow.raised,
  },
});
