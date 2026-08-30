import { useCallback, useMemo, useState } from 'react';
import { FlatList, StyleSheet, View } from 'react-native';
import { Redirect, router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { activeWindow, sleepCheckRequired, staffRequiredEffective } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { runCommand } from '@/lib/queue';
import type { RpcResult } from '@/lib/queue';
import { RecorderProvider, useRecorder } from '@/lib/recorder';
import { loadRoomDay, presentByRoom } from '@/lib/roomData';
import type { RoomDay } from '@/lib/roomData';
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
import { SwipeChildCard } from '@/ui/SwipeChildCard';

interface PickupOption {
  personId: string | null;
  label: string;
}

const MEALS = [
  { value: 'breakfast', label: 'Breakfast' },
  { value: 'lunch', label: 'Lunch' },
  { value: 'snack_am', label: 'Morning snack' },
  { value: 'snack_pm', label: 'Afternoon snack' },
] as const;

const EATEN = [
  { value: 'all', label: 'Finished' },
  { value: 'most', label: 'Most' },
  { value: 'some', label: 'Some' },
  { value: 'none', label: 'Not interested' },
] as const;

const DIAPERS = [
  { value: 'wet', label: 'Wet' },
  { value: 'soiled', label: 'Soiled' },
  { value: 'both', label: 'Both' },
  { value: 'dry', label: 'Dry' },
] as const;

const SEVERITIES = [
  { value: 'none_apparent', label: 'No apparent injury' },
  { value: 'minor', label: 'Minor' },
  { value: 'moderate', label: 'Moderate' },
  { value: 'serious', label: 'Serious' },
] as const;

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

  // sheets
  const [pickupFor, setPickupFor] = useState<{ childId: string; options: PickupOption[] } | null>(null);
  const [namedPickup, setNamedPickup] = useState('');
  const [obsFor, setObsFor] = useState<{ childId: string; firstName: string } | null>(null);
  const [obsNote, setObsNote] = useState('');
  const [obsParent, setObsParent] = useState('');
  const [moreFor, setMoreFor] = useState<{ childId: string; firstName: string } | null>(null);
  const [moreView, setMoreView] = useState<
    'menu' | 'meal' | 'diaper' | 'note' | 'accident' | 'medication' | 'illness'
  >('menu');
  const [medAuths, setMedAuths] = useState<
    { id: string; drug_name: string; dose: string | null; schedule: string | null; symptoms: string | null; kind: string }[]
  >([]);
  const [medSelected, setMedSelected] = useState<string | null>(null);
  const [doseGiven, setDoseGiven] = useState('');
  const [medOutcome, setMedOutcome] = useState('');
  const [illSymptoms, setIllSymptoms] = useState('');
  const [meal, setMeal] = useState<(typeof MEALS)[number]['value'] | null>(null);
  const [eaten, setEaten] = useState<(typeof EATEN)[number]['value'] | null>(null);
  const [diaper, setDiaper] = useState<(typeof DIAPERS)[number]['value'] | null>(null);
  const [diaperSupplies, setDiaperSupplies] = useState('');
  const [noteText, setNoteText] = useState('');
  const [bulkOpen, setBulkOpen] = useState(false);
  // accident form
  const [accLocation, setAccLocation] = useState('');
  const [accWhat, setAccWhat] = useState('');
  const [accInjury, setAccInjury] = useState('');
  const [accSeverity, setAccSeverity] = useState<(typeof SEVERITIES)[number]['value'] | null>(null);
  const [accFirstAid, setAccFirstAid] = useState('');
  const [accHead, setAccHead] = useState(false);
  const [accWatch, setAccWatch] = useState('');

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

  const ratio = useMemo(() => {
    if (!day || !room) return null;
    const counted = day.shifts.filter((s) => s.room_id === roomId && s.counted_in_ratio && !s.out_at).length;
    const local = new Date().toLocaleTimeString('en-CA', { hour12: false, timeZone: day.centre.timezone });
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

  async function act(
    childId: string | null,
    fn: (recorder: { personId: string; pin: string }) => Promise<RpcResult>,
  ): Promise<RpcResult | null> {
    setNotice(null);
    const recorder = await getRecorder();
    if (!recorder) return null;
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
    return result;
  }

  async function signIn(childId: string) {
    const child = roomChildren.find((c) => c.id === childId);
    const result = await act(childId, (recorder) =>
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
    if (result?.ok && child) {
      // s. 32: each child is observed on arrival, before joining the others.
      setObsNote('');
      setObsParent('');
      setObsFor({ childId, firstName: child.full_name.split(' ')[0]! });
    }
  }

  function markAbsent(childId: string) {
    void act(childId, (recorder) =>
      runCommand('record_attendance', {
        p_centre: day!.centre.id,
        p_child: childId,
        p_event_type: 'absent',
        p_room: null,
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
    return act(childId, (recorder) =>
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

  function saveObservation(observation: string, parentReported: string) {
    const target = obsFor;
    setObsFor(null);
    if (!target) return;
    void careLog(target.childId, 'health_observation', {
      observation,
      ...(parentReported.trim() ? { parent_reported: parentReported.trim() } : {}),
    });
  }

  function openMore(childId: string, firstName: string) {
    setMoreView('menu');
    setMeal(null);
    setEaten(null);
    setDiaper(null);
    setDiaperSupplies('');
    setNoteText('');
    setAccLocation('');
    setAccWhat('');
    setAccInjury('');
    setAccSeverity(null);
    setAccFirstAid('');
    setAccHead(false);
    setAccWatch('');
    setMedAuths([]);
    setMedSelected(null);
    setDoseGiven('');
    setMedOutcome('');
    setIllSymptoms('');
    setMoreFor({ childId, firstName });
    void supabase
      .from('medication_authorisation')
      .select('id, drug_name, dose, schedule, symptoms, kind')
      .eq('child_id', childId)
      .is('revoked_at', null)
      .then(({ data }) => setMedAuths((data as never) ?? []));
  }

  function giveMedication() {
    const target = moreFor;
    const auth = medAuths.find((a) => a.id === medSelected);
    if (!target || !auth) return;
    setMoreFor(null);
    void act(target.childId, (recorder) =>
      runCommand('record_medication_administration', {
        p_authorisation: auth.id,
        p_administered_at: new Date().toISOString(),
        p_dose_given: doseGiven.trim() || auth.dose,
        p_outcome: medOutcome.trim() || null,
        p_recorder: recorder.personId,
        p_pin: recorder.pin,
      }),
    );
  }

  // Illness (s. 32 / s. 36): record the observation and send the Now alert —
  // the loud channel exists exactly for this.
  async function sendHomeSick() {
    const target = moreFor;
    if (!target || !illSymptoms.trim() || !day) return;
    setMoreFor(null);
    const symptoms = illSymptoms.trim();
    const obs = await careLog(target.childId, 'health_observation', {
      observation: 'unwell — family contacted to arrange pickup',
      symptoms: [symptoms],
    });
    if (obs?.ok) {
      await act(target.childId, (recorder) =>
        runCommand('create_now_alert', {
          p_child: target.childId,
          p_event_type: 'illness_sent_home',
          p_title: `${target.firstName} is unwell`,
          p_body: `${target.firstName} has ${symptoms}. Please call ${day.centre.name} to arrange pickup.`,
          p_recorder: recorder.personId,
          p_pin: recorder.pin,
        }),
      );
    }
  }

  function saveAccident() {
    const target = moreFor;
    if (!target || !accSeverity || !accLocation.trim() || !accWhat.trim() || !accInjury.trim() || !accFirstAid.trim()) {
      setNotice('An accident report needs the location, what happened, the injury, its severity and the first aid given.');
      return;
    }
    if (accHead && !accWatch.trim()) {
      setNotice('A head injury needs the concussion-watch note.');
      return;
    }
    setMoreFor(null);
    void act(target.childId, (recorder) =>
      runCommand('record_accident_report', {
        p_centre: day!.centre.id,
        p_child: target.childId,
        p_occurred_at: new Date().toISOString(),
        p_location: accLocation.trim(),
        p_description: accWhat.trim(),
        p_injury: accInjury.trim(),
        p_severity: accSeverity,
        p_first_aid: accFirstAid.trim(),
        p_head_injury: accHead,
        p_concussion_watch_note: accHead ? accWatch.trim() : null,
        p_recorder: recorder.personId,
        p_pin: recorder.pin,
      }),
    );
  }

  function saveBulkMeal() {
    if (!meal || !eaten) return;
    setBulkOpen(false);
    const ids = roomChildren.filter((c) => present.has(c.id)).map((c) => c.id);
    void act(null, (recorder) =>
      runCommand('record_care_log_bulk', {
        p_centre: day!.centre.id,
        p_children: ids,
        p_room: roomId,
        p_type: 'meal',
        p_logged_at: new Date().toISOString(),
        p_payload: { meal, eaten },
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
      <View style={styles.rowBetween}>
        <Caption>Swipe right to sign in — left to sign out or mark absent.</Caption>
        <Button label="Room meal" kind="quiet" onPress={() => { setMeal(null); setEaten(null); setBulkOpen(true); }} />
      </View>
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
          const subtitle = napping
            ? `Napping · last check ${napping.lastCheck ? new Date(napping.lastCheck).toLocaleTimeString('en-CA', { hour12: false, hour: '2-digit', minute: '2-digit' }) : 'not yet'}`
            : busyChild === item.id
              ? 'Saving…'
              : isPresent
                ? 'Present'
                : 'Swipe right to sign in';
          return (
            <SwipeChildCard
              name={item.full_name}
              present={isPresent}
              subtitle={subtitle}
              onSignIn={() => void signIn(item.id)}
              onSignOut={() => void openPickup(item.id)}
              onMarkAbsent={() => markAbsent(item.id)}
            >
              {isPresent ? (
                <View style={styles.actions}>
                  {needsChecks && !napping ? (
                    <Button label="Start nap" kind="quiet" onPress={() => void careLog(item.id, 'nap_start', {})} />
                  ) : null}
                  {napping ? (
                    <>
                      <Button
                        label={checkDue ? 'Sleep check due' : 'Record sleep check'}
                        kind={checkDue ? 'primary' : 'quiet'}
                        onPress={() => void careLog(item.id, 'sleep_check', { breathing_ok: true, position: 'back' })}
                      />
                      <Button label="End nap" kind="quiet" onPress={() => void careLog(item.id, 'nap_end', {})} />
                    </>
                  ) : null}
                  <Button
                    label="More"
                    kind="quiet"
                    onPress={() => openMore(item.id, item.full_name.split(' ')[0]!)}
                  />
                </View>
              ) : null}
            </SwipeChildCard>
          );
        }}
      />

      {/* s. 50: identity-confirmed release */}
      <Sheet visible={pickupFor !== null} onClose={() => setPickupFor(null)} title="Released to">
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
      </Sheet>

      {/* s. 32: arrival observation, one tap for the common case */}
      <Sheet
        visible={obsFor !== null}
        onClose={() => saveObservation('settled and well on arrival', '')}
        title={obsFor ? `How does ${obsFor.firstName} seem?` : ''}
      >
        <Button label="Settled and well" onPress={() => saveObservation('settled and well on arrival', obsParent)} />
        <Field placeholder="Anything you noticed (optional)" value={obsNote} onChangeText={setObsNote} />
        <Field
          placeholder="Anything the parent mentioned (optional)"
          value={obsParent}
          onChangeText={setObsParent}
        />
        <Button
          label="Save observation"
          kind="quiet"
          onPress={() => saveObservation(obsNote.trim() || 'settled and well on arrival', obsParent)}
        />
      </Sheet>

      {/* per-child quick actions */}
      <Sheet
        visible={moreFor !== null}
        onClose={() => setMoreFor(null)}
        title={moreFor ? `${moreFor.firstName}` : ''}
      >
        {moreView === 'menu' ? (
          <>
            <Button label="Record meal" kind="quiet" onPress={() => setMoreView('meal')} />
            <Button label="Record diaper" kind="quiet" onPress={() => setMoreView('diaper')} />
            <Button label="Add note" kind="quiet" onPress={() => setMoreView('note')} />
            {medAuths.length > 0 ? (
              <Button label="Give medication" kind="quiet" onPress={() => setMoreView('medication')} />
            ) : null}
            <Button label="Record accident report" kind="quiet" onPress={() => setMoreView('accident')} />
            <Button label="Illness — send home" kind="quiet" onPress={() => setMoreView('illness')} />
            <Button label="Close" kind="quiet" onPress={() => setMoreFor(null)} />
          </>
        ) : null}
        {moreView === 'medication' ? (
          <>
            <Body muted>
              Every administration is logged — blanket items included (s. 40). Expired or revoked
              authorisations are refused automatically.
            </Body>
            {medAuths.map((a) => (
              <Button
                key={a.id}
                label={`${a.drug_name}${a.dose ? ` — ${a.dose}` : ''}${a.schedule ? ` (${a.schedule})` : a.symptoms ? ` (${a.symptoms})` : ''}`}
                kind={medSelected === a.id ? 'primary' : 'quiet'}
                onPress={() => {
                  setMedSelected(a.id);
                  setDoseGiven(a.dose ?? '');
                }}
              />
            ))}
            {medSelected ? (
              <>
                <Field placeholder="Dose given" value={doseGiven} onChangeText={setDoseGiven} />
                <Field placeholder="Outcome (optional)" value={medOutcome} onChangeText={setMedOutcome} />
                <Button label="Log administration" onPress={giveMedication} />
              </>
            ) : null}
          </>
        ) : null}
        {moreView === 'illness' ? (
          <>
            <Body muted>
              Records the observation and sends the family a Now alert to arrange pickup. The alert
              stays until a parent acknowledges it.
            </Body>
            <Field
              placeholder="Symptoms — e.g. a fever of 38.9°C"
              value={illSymptoms}
              onChangeText={setIllSymptoms}
            />
            <Button label="Record and alert the family" onPress={() => void sendHomeSick()} />
          </>
        ) : null}
        {moreView === 'meal' ? (
          <>
            <Choices options={[...MEALS]} value={meal} onChange={setMeal} />
            <Choices options={[...EATEN]} value={eaten} onChange={setEaten} />
            <Button
              label="Save meal"
              onPress={() => {
                if (moreFor && meal && eaten) {
                  const id = moreFor.childId;
                  setMoreFor(null);
                  void careLog(id, 'meal', { meal, eaten });
                }
              }}
            />
          </>
        ) : null}
        {moreView === 'diaper' ? (
          <>
            <Choices options={[...DIAPERS]} value={diaper} onChange={setDiaper} />
            <Field
              placeholder="Diapers remaining at the centre (optional)"
              keyboardType="number-pad"
              value={diaperSupplies}
              onChangeText={setDiaperSupplies}
            />
            <Button
              label="Save diaper"
              onPress={() => {
                if (moreFor && diaper) {
                  const id = moreFor.childId;
                  const remaining = parseInt(diaperSupplies, 10);
                  setMoreFor(null);
                  void careLog(id, 'diaper', {
                    kind: diaper,
                    ...(Number.isFinite(remaining) ? { supplies_remaining: remaining } : {}),
                  });
                }
              }}
            />
          </>
        ) : null}
        {moreView === 'note' ? (
          <>
            <Field placeholder="Note for the day" value={noteText} onChangeText={setNoteText} />
            <Button
              label="Save note"
              onPress={() => {
                if (moreFor && noteText.trim()) {
                  const id = moreFor.childId;
                  setMoreFor(null);
                  void careLog(id, 'note', { text: noteText.trim() });
                }
              }}
            />
          </>
        ) : null}
        {moreView === 'accident' ? (
          <>
            <Body muted>
              The family receives a Now alert and acknowledges their copy in the app (s. 36(4)).
            </Body>
            <Field placeholder="Where it happened" value={accLocation} onChangeText={setAccLocation} />
            <Field placeholder="What happened" value={accWhat} onChangeText={setAccWhat} />
            <Field placeholder="The injury" value={accInjury} onChangeText={setAccInjury} />
            <Choices options={[...SEVERITIES]} value={accSeverity} onChange={setAccSeverity} />
            <Field placeholder="First aid given" value={accFirstAid} onChangeText={setAccFirstAid} />
            <Button
              label={accHead ? 'Head injury: yes' : 'Head injury: no'}
              kind={accHead ? 'primary' : 'quiet'}
              onPress={() => setAccHead(!accHead)}
            />
            {accHead ? (
              <Field
                placeholder="Concussion watch instructions for the family"
                value={accWatch}
                onChangeText={setAccWatch}
              />
            ) : null}
            <Button label="Send accident report" onPress={saveAccident} />
          </>
        ) : null}
      </Sheet>

      {/* one tap logs the meal for everyone present */}
      <Sheet visible={bulkOpen} onClose={() => setBulkOpen(false)} title="Meal for the room">
        <Body muted>{`Logs one meal entry for each of the ${present.size} children present.`}</Body>
        <Choices options={[...MEALS]} value={meal} onChange={setMeal} />
        <Choices options={[...EATEN]} value={eaten} onChange={setEaten} />
        <Button label="Log for the room" onPress={saveBulkMeal} />
        <Button label="Cancel" kind="quiet" onPress={() => setBulkOpen(false)} />
      </Sheet>
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
});
