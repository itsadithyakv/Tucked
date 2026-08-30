import { useCallback, useState } from 'react';
import { FlatList, StyleSheet, View } from 'react-native';
import { Redirect, router, useFocusEffect } from 'expo-router';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Body, Button, Caption, Card, Heading, Pill, Screen, Title } from '@/ui/components';

interface Report {
  id: string;
  occurred_at: string;
  occurred_date: string;
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
}

function fmtDate(iso: string): string {
  return new Date(`${iso.slice(0, 10)}T12:00:00`).toLocaleDateString('en-CA', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

/** Every accident report for your children, in full, forever readable —
 * RLS scopes this to your own household automatically. */
export default function Reports() {
  const { session, loading } = useAuth();
  const [reports, setReports] = useState<Report[]>([]);

  useFocusEffect(
    useCallback(() => {
      supabase
        .from('accident_report')
        .select(
          'id, occurred_at, occurred_date, location, description, injury, severity, first_aid, head_injury, concussion_watch_note, parent_ack_at, child:child_id(full_name), completed_by_person:completed_by(full_name)',
        )
        .order('occurred_at', { ascending: false })
        .limit(50)
        .then(({ data }) => setReports((data as never) ?? []));
    }, []),
  );

  if (!loading && !session) return <Redirect href="/sign-in" />;

  return (
    <Screen>
      <View style={styles.header}>
        <Title>Accident reports</Title>
        <Button label="Back" kind="quiet" onPress={() => router.back()} />
      </View>
      <FlatList
        data={reports}
        keyExtractor={(r) => r.id}
        contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}
        renderItem={({ item }) => (
          <Card>
            <View style={styles.header}>
              <Heading>{item.child?.full_name.split(' ')[0]}</Heading>
              {item.head_injury ? <Pill kind="now">Head injury</Pill> : null}
            </View>
            <Caption>{`${fmtDate(item.occurred_date)} · ${item.location} · ${item.severity.replace('_', ' ')}`}</Caption>
            <Body>{item.description}</Body>
            <Body muted>{`Injury: ${item.injury}. First aid: ${item.first_aid}.`}</Body>
            {item.concussion_watch_note ? <Body muted>{`Watch for: ${item.concussion_watch_note}.`}</Body> : null}
            <Caption>{`Completed by ${item.completed_by_person?.full_name ?? 'the room team'}`}</Caption>
            {item.parent_ack_at ? (
              <Pill kind="ok">Copy acknowledged</Pill>
            ) : (
              <Pill kind="due">Not yet acknowledged</Pill>
            )}
          </Card>
        )}
        ListEmptyComponent={
          <Card>
            <Body muted>No accident reports on file — the kind of empty this should stay.</Body>
          </Card>
        }
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: space.sm,
  },
});
