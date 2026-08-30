import { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { Redirect, router, useFocusEffect } from 'expo-router';
import Animated, { FadeInDown } from 'react-native-reanimated';
import { enCA } from '@tucked/domain';
import { colour, radius, space, type } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Avatar } from '@/ui/SwipeChildCard';
import { Body, Button, Caption, Card, Heading, Screen, Title } from '@/ui/components';

interface ChildRow {
  id: string;
  full_name: string;
  room: { name: string } | null;
}

interface NowAlert {
  id: string;
  title: string;
  body: string;
  event_type: string;
  ref_id: string | null;
  created_at: string;
}

interface StoryRow {
  child_id: string;
  draft_text: string;
  educator_note: string | null;
  published_at: string;
}

function fmt12(iso: string): string {
  return new Date(iso).toLocaleTimeString('en-CA', { hour: 'numeric', minute: '2-digit', hour12: true });
}

/** The family home: the current decision first ("Maya is in the Infant room"),
 * one calm story per child, and loud alerts ONLY for things that matter now —
 * which stay until acknowledged, because the acknowledgement is the record. */
export default function FamilyHome() {
  const { session, loading, profile } = useAuth();
  const [children, setChildren] = useState<ChildRow[] | null>(null);
  const [alerts, setAlerts] = useState<NowAlert[]>([]);
  const [stories, setStories] = useState<Map<string, StoryRow>>(new Map());
  const [status, setStatus] = useState<Map<string, string>>(new Map());
  const [recordDone, setRecordDone] = useState<Map<string, number>>(new Map());
  const [busyAlert, setBusyAlert] = useState<string | null>(null);

  const refresh = useCallback(() => {
    if (!profile) return;
    const today = new Date().toISOString().slice(0, 10);
    supabase
      .from('child')
      .select('id, full_name, room:current_room_id(name)')
      .order('full_name')
      .then(({ data }) => setChildren((data as never as ChildRow[]) ?? []));
    supabase
      .from('notification')
      .select('id, title, body, event_type, ref_id, created_at')
      .eq('recipient_person_id', profile.personId)
      .eq('channel', 'now')
      .is('acknowledged_at', null)
      .order('created_at', { ascending: false })
      .then(({ data }) => setAlerts((data as NowAlert[]) ?? []));
    supabase
      .from('story')
      .select('child_id, draft_text, educator_note, published_at')
      .eq('story_date', today)
      .then(({ data }) => {
        setStories(new Map(((data as StoryRow[]) ?? []).map((s) => [s.child_id, s])));
      });
    supabase
      .from('child_record_item')
      .select('child_id, status')
      .then(({ data }) => {
        const map = new Map<string, number>();
        for (const i of (data as { child_id: string; status: string }[]) ?? []) {
          if (i.status !== 'missing') map.set(i.child_id, (map.get(i.child_id) ?? 0) + 1);
        }
        setRecordDone(map);
      });
    supabase
      .from('attendance_event')
      .select('child_id, event_type, actual_time')
      .eq('attendance_date', today)
      .order('actual_time')
      .then(({ data }) => {
        const map = new Map<string, string>();
        for (const e of (data as { child_id: string; event_type: string; actual_time: string }[]) ?? []) {
          if (e.event_type === 'arrive') map.set(e.child_id, `arrived ${fmt12(e.actual_time)}`);
          else if (e.event_type === 'depart') map.set(e.child_id, `picked up at ${fmt12(e.actual_time)}`);
          else if (e.event_type === 'absent') map.set(e.child_id, 'marked absent today');
        }
        setStatus(map);
      });
  }, [profile]);

  useFocusEffect(refresh);

  async function acknowledge(alert: NowAlert) {
    setBusyAlert(alert.id);
    if (alert.event_type === 'accident_report' && alert.ref_id) {
      // one press acknowledges the report copy (s. 36(4)) and settles the alert
      await supabase.rpc('acknowledge_accident_report', { p_report: alert.ref_id });
    } else {
      await supabase.rpc('acknowledge_notification', { p_notification: alert.id });
    }
    setBusyAlert(null);
    refresh();
  }

  if (!loading && !session) return <Redirect href="/sign-in" />;

  return (
    <Screen>
      <ScrollView contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}>
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
          <Title>{profile ? profile.fullName.split(' ')[0] : 'Family'}</Title>
          <Button label="Messages" kind="quiet" onPress={() => router.push('/messages')} />
        </View>

        {alerts.map((alert) => (
          <View key={alert.id} style={styles.nowCard}>
            <Text style={styles.nowOverline}>NOW</Text>
            <Heading>{alert.title}</Heading>
            <Body>{alert.body}</Body>
            <Caption>{`Sent ${fmt12(alert.created_at)}`}</Caption>
            <Button
              label={alert.event_type === 'accident_report' ? 'I have read the report' : 'Acknowledge'}
              busy={busyAlert === alert.id}
              onPress={() => void acknowledge(alert)}
            />
          </View>
        ))}

        {children !== null && children.length === 0 ? (
          <Card>
            <Body muted>{enCA.home.familyEmpty}</Body>
          </Card>
        ) : null}

        {(children ?? []).map((child, index) => {
          const story = stories.get(child.id);
          const firstName = child.full_name.split(' ')[0]!;
          const childStatus = status.get(child.id);
          return (
            <Animated.View
              key={child.id}
              entering={FadeInDown.delay(index * 80).springify().damping(15)}
            >
              <Card>
                <View style={styles.childRow}>
                  <Avatar name={child.full_name} size={44} />
                  <View style={{ flex: 1 }}>
                    <Heading>{firstName}</Heading>
                    <Caption>
                      {child.room ? `${child.room.name}${childStatus ? ` — ${childStatus}` : ''}` : (childStatus ?? '')}
                    </Caption>
                  </View>
                </View>
                {story ? (
                  <View style={styles.story}>
                    <Text style={styles.storyOverline}>TODAY&apos;S STORY</Text>
                    {story.educator_note ? <Body>{story.educator_note}</Body> : null}
                    <Body muted>{story.draft_text}</Body>
                    <Caption>{`Published ${fmt12(story.published_at)}`}</Caption>
                  </View>
                ) : (
                  <Caption>The day&apos;s story arrives at pick-up time.</Caption>
                )}
                {(recordDone.get(child.id) ?? 0) < 11 ? (
                  <Button
                    label={`Complete ${firstName}'s enrolment record`}
                    kind="quiet"
                    onPress={() => router.push({ pathname: '/enrolment/[childId]', params: { childId: child.id } })}
                  />
                ) : null}
              </Card>
            </Animated.View>
          );
        })}

        <Button label={enCA.auth.signOut} kind="quiet" onPress={() => supabase.auth.signOut()} />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  nowCard: {
    backgroundColor: colour.nowWash,
    borderRadius: radius.card,
    borderLeftWidth: 4,
    borderLeftColor: colour.now,
    padding: space.lg,
    gap: space.sm,
  },
  nowOverline: {
    ...type.overline,
    color: colour.now,
    textTransform: 'uppercase',
  } as const,
  childRow: { flexDirection: 'row', alignItems: 'center', gap: space.md },
  story: {
    backgroundColor: colour.canvas,
    borderRadius: radius.lg,
    padding: space.base,
    gap: space.sm,
  },
  storyOverline: {
    ...type.overline,
    color: colour.slateMuted,
    textTransform: 'uppercase',
  } as const,
});
