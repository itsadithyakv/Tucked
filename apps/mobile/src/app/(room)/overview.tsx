import { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { space } from '@tucked/ui-tokens';
import { supabase } from '@/lib/supabase';
import { loadRoomDay, presentByRoom } from '@/lib/roomData';
import type { RoomDay } from '@/lib/roomData';
import { Body, Caption, Card, Heading, Pill, Screen, Title } from '@/ui/components';

interface Report {
  id: string;
  occurred_at: string;
  location: string;
  description: string;
  injury: string;
  severity: string;
  first_aid: string;
  head_injury: boolean;
  concussion_watch_note: string | null;
  parent_ack_at: string | null;
  child: { full_name: string } | null;
  completed_by_person: { full_name: string } | null;
  ack_person: { full_name: string } | null;
}

function fmt12(iso: string): string {
  return new Date(iso).toLocaleTimeString('en-CA', { hour: 'numeric', minute: '2-digit', hour12: true });
}

/** The supervisor's check on everything: who is in, what is due, what
 * happened — with every accident report readable in full, right here. */
export default function Overview() {
  const [day, setDay] = useState<RoomDay | null>(null);
  const [reports, setReports] = useState<Report[]>([]);
  const [openRecord, setOpenRecord] = useState<number>(0);
  const [unacked, setUnacked] = useState<number>(0);

  const refresh = useCallback(() => {
    loadRoomDay().then(setDay);
    const today = new Date().toISOString().slice(0, 10);
    supabase
      .from('accident_report')
      .select(
        'id, occurred_at, location, description, injury, severity, first_aid, head_injury, concussion_watch_note, parent_ack_at, child:child_id(full_name), completed_by_person:completed_by(full_name), ack_person:parent_ack_person_id(full_name)',
      )
      .eq('occurred_date', today)
      .order('occurred_at', { ascending: false })
      .then(({ data }) => setReports((data as never) ?? []));
    supabase
      .from('daily_written_record')
      .select('id', { count: 'exact', head: true })
      .is('closed_at', null)
      .then(({ count }) => setOpenRecord(count ?? 0));
    supabase
      .from('notification')
      .select('id', { count: 'exact', head: true })
      .eq('channel', 'now')
      .is('acknowledged_at', null)
      .then(({ count }) => setUnacked(count ?? 0));
  }, []);
  useFocusEffect(refresh);

  const presentTotal = day
    ? [...presentByRoom(day.attendance).values()].reduce((n, s) => n + s.size, 0)
    : 0;
  const arrived = new Set(day?.attendance.filter((a) => a.event_type === 'arrive').map((a) => a.child_id));
  const absent = new Set(day?.attendance.filter((a) => a.event_type === 'absent').map((a) => a.child_id));
  const unaccounted = (day?.children ?? []).filter((c) => !arrived.has(c.id) && !absent.has(c.id)).length;
  const staffIn = new Set(
    (day?.shifts ?? []).filter((s) => s.counted_in_ratio && !s.out_at).map((s) => s.person_id),
  ).size;

  return (
    <Screen>
      <Title>Overview</Title>
      <ScrollView contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}>
        <View style={styles.tiles}>
          <View style={styles.tile}>
            <Card wash="mist">
              <Title>{String(presentTotal)}</Title>
              <Caption>present now</Caption>
            </Card>
          </View>
          <View style={styles.tile}>
            <Card wash="mint">
              <Title>{String(staffIn)}</Title>
              <Caption>staff in ratio</Caption>
            </Card>
          </View>
          <View style={styles.tile}>
            <Card wash={unaccounted > 0 ? 'sand' : 'mint'}>
              <Title>{String(unaccounted)}</Title>
              <Caption>not accounted for</Caption>
            </Card>
          </View>
        </View>

        <Card wash={openRecord > 0 ? 'sand' : 'mint'}>
          <View style={styles.rowBetween}>
            <Body>Daily written record</Body>
            <Pill kind={openRecord > 0 ? 'due' : 'ok'}>
              {openRecord > 0 ? `${openRecord} open` : 'Closed'}
            </Pill>
          </View>
          <Caption>Review and close in the console at day&apos;s end.</Caption>
        </Card>

        <Card wash={unacked > 0 ? 'sand' : 'mint'}>
          <View style={styles.rowBetween}>
            <Body>Urgent alerts to families</Body>
            <Pill kind={unacked > 0 ? 'due' : 'ok'}>
              {unacked > 0 ? `${unacked} unacknowledged` : 'All acknowledged'}
            </Pill>
          </View>
        </Card>

        <Heading>Today&apos;s accident reports</Heading>
        {reports.length === 0 ? (
          <Card>
            <Body muted>No accidents recorded today.</Body>
          </Card>
        ) : (
          reports.map((r) => (
            <Card key={r.id}>
              <View style={styles.rowBetween}>
                <Heading>{r.child?.full_name}</Heading>
                {r.head_injury ? <Pill kind="now">Head injury</Pill> : null}
              </View>
              <Caption>{`${fmt12(r.occurred_at)} · ${r.location} · ${r.severity.replace('_', ' ')}`}</Caption>
              <Body>{r.description}</Body>
              <Body muted>{`Injury: ${r.injury}. First aid: ${r.first_aid}.`}</Body>
              {r.concussion_watch_note ? <Body muted>{`Watch: ${r.concussion_watch_note}`}</Body> : null}
              <Caption>{`Completed by ${r.completed_by_person?.full_name ?? '—'}`}</Caption>
              {r.parent_ack_at ? (
                <Pill kind="ok">{`Acknowledged by ${r.ack_person?.full_name ?? 'family'} at ${fmt12(r.parent_ack_at)}`}</Pill>
              ) : (
                <Pill kind="due">Awaiting family acknowledgement</Pill>
              )}
            </Card>
          ))
        )}
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  tiles: { flexDirection: 'row', gap: space.sm },
  tile: { flex: 1 },
  rowBetween: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: space.sm,
  },
});
