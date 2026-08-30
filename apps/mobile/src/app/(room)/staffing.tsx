import { useCallback, useState } from 'react';
import { FlatList, StyleSheet, View } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { runCommand } from '@/lib/queue';
import { RecorderProvider, useRecorder } from '@/lib/recorder';
import { loadRoomDay } from '@/lib/roomData';
import type { RoomDay } from '@/lib/roomData';
import { Avatar } from '@/ui/SwipeChildCard';
import { Body, Button, Caption, Card, Choices, Heading, Pill, Screen, Sheet, Title } from '@/ui/components';

/** Who is where today. Supervisors assign educators to rooms (a PIN-signed
 * staff shift — the record behind the live ratios) and end shifts; everyone
 * else sees the day's staffing at a glance. Volunteers and students appear
 * but are never counted in ratio — the database enforces that. */
function Staffing() {
  const { profile } = useAuth();
  const { getRecorder, invalidate } = useRecorder();
  const [day, setDay] = useState<RoomDay | null>(null);
  const [assigning, setAssigning] = useState<{ personId: string; name: string } | null>(null);
  const [roomChoice, setRoomChoice] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const refresh = useCallback(() => {
    loadRoomDay().then(setDay);
  }, []);
  useFocusEffect(refresh);

  const canAssign =
    profile?.roles.some((r) => ['supervisor', 'designate', 'licensee_admin'].includes(r.role)) ?? false;

  const activeShift = new Map(
    (day?.shifts ?? []).filter((s) => !s.out_at).map((s) => [s.person_id, s]),
  );
  const roomName = new Map((day?.rooms ?? []).map((r) => [r.id, r.name]));

  async function assign() {
    const target = assigning;
    if (!target || !roomChoice || !day) return;
    setAssigning(null);
    const recorder = await getRecorder();
    if (!recorder) return;
    const result = await runCommand('record_staff_shift', {
      p_centre: day.centre.id,
      p_person: target.personId,
      p_room: roomChoice,
      p_in_at: new Date().toISOString(),
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

  async function endShift(personId: string) {
    const shift = (day?.shifts ?? []).find((s) => s.person_id === personId && !s.out_at);
    if (!day || !shift) return;
    setNotice(null);
    const recorder = await getRecorder();
    if (!recorder) return;
    const result = await runCommand('close_staff_shift', {
      p_shift: shift.id,
      p_out_at: new Date().toISOString(),
      p_recorder: recorder.personId,
      p_pin: recorder.pin,
    });
    if (!result.ok) {
      if (result.error?.includes('PIN')) invalidate();
      setNotice(result.error ?? 'That did not work.');
    } else refresh();
  }

  return (
    <Screen>
      <Title>Staffing</Title>
      <Caption>
        {canAssign
          ? 'Assign educators to rooms — assignments drive the live ratios.'
          : "Today's staffing. The supervisor assigns rooms."}
      </Caption>
      {notice ? (
        <Card wash="mist">
          <Body muted>{notice}</Body>
        </Card>
      ) : null}
      <FlatList
        data={day?.staff ?? []}
        keyExtractor={(s) => s.personId}
        contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}
        renderItem={({ item }) => {
          const shift = activeShift.get(item.personId);
          return (
            <Card>
              <View style={styles.row}>
                <Avatar name={item.fullName} size={44} />
                <View style={{ flex: 1 }}>
                  <Heading>{item.fullName}</Heading>
                  <Caption>{item.role.replace(/_/g, ' ')}</Caption>
                </View>
                {shift ? (
                  <Pill kind="ok">{shift.room_id ? (roomName.get(shift.room_id) ?? 'On shift') : 'On shift'}</Pill>
                ) : (
                  <Pill kind="due">Off</Pill>
                )}
              </View>
              {canAssign ? (
                shift ? (
                  <Button label="End shift" kind="quiet" onPress={() => void endShift(item.personId)} />
                ) : (
                  <Button
                    label="Assign to a room"
                    kind="quiet"
                    onPress={() => {
                      setRoomChoice(null);
                      setAssigning({ personId: item.personId, name: item.fullName });
                    }}
                  />
                )
              ) : null}
            </Card>
          );
        }}
      />

      <Sheet
        visible={assigning !== null}
        onClose={() => setAssigning(null)}
        title={assigning ? `Assign ${assigning.name.split(' ')[0]}` : ''}
      >
        <Choices
          options={(day?.rooms ?? []).map((r) => ({ value: r.id, label: r.name }))}
          value={roomChoice}
          onChange={setRoomChoice}
        />
        <Button label="Start shift" onPress={() => void assign()} />
        <Button label="Cancel" kind="quiet" onPress={() => setAssigning(null)} />
      </Sheet>
    </Screen>
  );
}

export default function StaffingTab() {
  const [staff, setStaff] = useState<{ personId: string; fullName: string; role: string }[]>([]);
  useFocusEffect(
    useCallback(() => {
      loadRoomDay().then((d) => setStaff(d?.staff ?? []));
    }, []),
  );
  return (
    <RecorderProvider staff={staff}>
      <Staffing />
    </RecorderProvider>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: space.md },
});
