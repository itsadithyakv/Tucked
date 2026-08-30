import { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { enCA } from '@tucked/domain';
import { colour, radius, space, type } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Avatar } from '@/ui/SwipeChildCard';
import { Body, Button, Caption, Card, Heading, Pill, Screen, Title } from '@/ui/components';

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

interface Announcement {
  id: string;
  title: string;
  body: string;
  published_at: string;
}

function fmt12(iso: string): string {
  return new Date(iso).toLocaleTimeString('en-CA', { hour: 'numeric', minute: '2-digit', hour12: true });
}

/** The current decision first: each child's status, today's story, loud
 * alerts only when they matter — and the centre's quiet announcements. */
export default function FamilyHome() {
  const { profile } = useAuth();
  const [children, setChildren] = useState<ChildRow[] | null>(null);
  const [alerts, setAlerts] = useState<NowAlert[]>([]);
  const [stories, setStories] = useState<Map<string, StoryRow>>(new Map());
  const [status, setStatus] = useState<Map<string, string>>(new Map());
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
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
      .then(({ data }) => setStories(new Map(((data as StoryRow[]) ?? []).map((s) => [s.child_id, s]))));
    supabase
      .from('announcement')
      .select('id, title, body, published_at')
      .order('published_at', { ascending: false })
      .limit(3)
      .then(({ data }) => setAnnouncements((data as Announcement[]) ?? []));
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
      await supabase.rpc('acknowledge_accident_report', { p_report: alert.ref_id });
    } else {
      await supabase.rpc('acknowledge_notification', { p_notification: alert.id });
    }
    setBusyAlert(null);
    refresh();
  }

  return (
    <Screen>
      <ScrollView contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}>
        <Title>{profile ? `Hi, ${profile.fullName.split(' ')[0]}` : 'Family'}</Title>

        {alerts.map((alert) => (
          <View key={alert.id} style={styles.nowCard}>
            <Pill kind="now">Now</Pill>
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

        {(children ?? []).map((child) => {
          const story = stories.get(child.id);
          const firstName = child.full_name.split(' ')[0]!;
          const childStatus = status.get(child.id);
          return (
            <Card key={child.id}>
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
            </Card>
          );
        })}

        {announcements.length > 0 ? (
          <>
            <Heading>From the centre</Heading>
            {announcements.map((a) => (
              <Card key={a.id} wash="mist">
                <Heading>{a.title}</Heading>
                <Body muted>{a.body}</Body>
                <Caption>{fmt12(a.published_at)}</Caption>
              </Card>
            ))}
          </>
        ) : null}

        <Button
          label="See the full day log"
          kind="quiet"
          onPress={() => router.push('/log')}
        />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  // the Now card is a clay surface on the rose wash — no rail, the pill and
  // the colour carry the urgency
  nowCard: {
    backgroundColor: colour.nowWash,
    borderRadius: radius.xl,
    padding: space.lg,
    gap: space.sm,
    shadowColor: colour.ink,
    shadowOpacity: 0.08,
    shadowRadius: 14,
    shadowOffset: { width: 0, height: 6 },
    elevation: 2,
  },
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
