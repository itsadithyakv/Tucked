import { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { enCA } from '@tucked/domain';
import { colour, radius, space, type } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { useFamily } from '@/lib/childTheme';
import { supabase } from '@/lib/supabase';
import { Avatar } from '@/ui/SwipeChildCard';
import { ChildSwitcher } from '@/ui/ChildSwitcher';
import { Body, Button, Caption, Card, Heading, Pill, Screen, Title } from '@/ui/components';

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

interface ReportDetail {
  id: string;
  location: string;
  description: string;
  injury: string;
  severity: string;
  first_aid: string;
  head_injury: boolean;
  concussion_watch_note: string | null;
  completed_by_person: { full_name: string } | null;
}

interface PlanDetail {
  id: string;
  plan_type: string;
  condition: string;
  allergens: string[];
  signs: string | null;
  emergency_procedure: string | null;
  devices_instructions: string | null;
  supports: string | null;
  developed_with: string;
  child: { full_name: string } | null;
}

function fmt12(iso: string): string {
  return new Date(iso).toLocaleTimeString('en-CA', { hour: 'numeric', minute: '2-digit', hour12: true });
}

/** The current decision first: each child's status, today's story, loud
 * alerts only when they matter — and the centre's quiet announcements. */
export default function FamilyHome() {
  const { profile } = useAuth();
  const { selected, ready } = useFamily();
  const [alerts, setAlerts] = useState<NowAlert[]>([]);
  const [stories, setStories] = useState<Map<string, StoryRow>>(new Map());
  const [status, setStatus] = useState<Map<string, string>>(new Map());
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
  const [reportDetails, setReportDetails] = useState<Map<string, ReportDetail>>(new Map());
  const [planDetails, setPlanDetails] = useState<Map<string, PlanDetail>>(new Map());
  const [busyAlert, setBusyAlert] = useState<string | null>(null);

  const refresh = useCallback(() => {
    if (!profile) return;
    const today = new Date().toISOString().slice(0, 10);
    supabase
      .from('notification')
      .select('id, title, body, event_type, ref_id, created_at')
      .eq('recipient_person_id', profile.personId)
      .eq('channel', 'now')
      .is('acknowledged_at', null)
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        const rows = (data as NowAlert[]) ?? [];
        setAlerts(rows);
        // read the report before acknowledging it: pull the full content
        const reportIds = rows.filter((a) => a.event_type === 'accident_report' && a.ref_id).map((a) => a.ref_id!);
        if (reportIds.length > 0) {
          void supabase
            .from('accident_report')
            .select(
              'id, location, description, injury, severity, first_aid, head_injury, concussion_watch_note, completed_by_person:completed_by(full_name)',
            )
            .in('id', reportIds)
            .then(({ data: reports }) =>
              setReportDetails(new Map(((reports as never as ReportDetail[]) ?? []).map((r) => [r.id, r]))),
            );
        }
        // a plan asks for real agreement — show it in full before the button
        const planIds = rows.filter((a) => a.event_type === 'plan_agreement' && a.ref_id).map((a) => a.ref_id!);
        if (planIds.length > 0) {
          void supabase
            .from('individualised_plan')
            .select(
              'id, plan_type, condition, allergens, signs, emergency_procedure, devices_instructions, supports, developed_with, child:child_id(full_name)',
            )
            .in('id', planIds)
            .then(({ data: plansRows }) =>
              setPlanDetails(new Map(((plansRows as never as PlanDetail[]) ?? []).map((p) => [p.id, p]))),
            );
        }
      });
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
    } else if (alert.event_type === 'plan_agreement' && alert.ref_id) {
      // s. 52: this IS the parental agreement — named, timestamped, in writing
      await supabase.rpc('agree_individualised_plan', { p_plan: alert.ref_id });
    } else {
      await supabase.rpc('acknowledge_notification', { p_notification: alert.id });
    }
    setBusyAlert(null);
    refresh();
  }

  return (
    <Screen>
      <ScrollView contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}>
        <View style={styles.headerRow}>
          <Title>{profile ? `Hi, ${profile.fullName.split(' ')[0]}` : 'Family'}</Title>
          <ChildSwitcher />
        </View>

        {alerts.map((alert) => {
          const report = alert.ref_id ? reportDetails.get(alert.ref_id) : undefined;
          const plan = alert.event_type === 'plan_agreement' && alert.ref_id ? planDetails.get(alert.ref_id) : undefined;
          return (
            <View key={alert.id} style={styles.nowCard}>
              <Pill kind="now">Now</Pill>
              <Heading>{alert.title}</Heading>
              {report ? (
                <View style={styles.reportBox}>
                  <Body>{`${report.location} — ${report.description}`}</Body>
                  <Body muted>{`Injury: ${report.injury} (${report.severity.replace('_', ' ')}).`}</Body>
                  <Body muted>{`First aid: ${report.first_aid}.`}</Body>
                  {report.concussion_watch_note ? (
                    <Body muted>{`Watch for: ${report.concussion_watch_note}.`}</Body>
                  ) : null}
                  <Caption>{`Completed by ${report.completed_by_person?.full_name ?? 'the room team'}`}</Caption>
                </View>
              ) : plan ? (
                <View style={styles.reportBox}>
                  <Body>{plan.condition}</Body>
                  {plan.allergens.length > 0 ? <Body muted>{`Allergens: ${plan.allergens.join(', ')}.`}</Body> : null}
                  {plan.signs ? <Body muted>{`Signs: ${plan.signs}.`}</Body> : null}
                  {plan.emergency_procedure ? <Body muted>{`Emergency: ${plan.emergency_procedure}`}</Body> : null}
                  {plan.devices_instructions ? <Body muted>{`Devices: ${plan.devices_instructions}`}</Body> : null}
                  {plan.supports ? <Body muted>{`Supports: ${plan.supports}`}</Body> : null}
                  <Caption>{`Developed with ${plan.developed_with}. Agreeing puts this plan into practice.`}</Caption>
                </View>
              ) : (
                <Body>{alert.body}</Body>
              )}
              <Caption>{`Sent ${fmt12(alert.created_at)}`}</Caption>
              <Button
                label={
                  alert.event_type === 'accident_report'
                    ? 'I have read the report'
                    : alert.event_type === 'plan_agreement'
                      ? 'I agree to this plan'
                      : 'Acknowledge'
                }
                busy={busyAlert === alert.id}
                onPress={() => void acknowledge(alert)}
              />
            </View>
          );
        })}

        {ready && !selected ? (
          <Card>
            <Body muted>{enCA.home.familyEmpty}</Body>
          </Card>
        ) : null}

        {selected
          ? (() => {
              const story = stories.get(selected.id);
              const childStatus = status.get(selected.id);
              return (
                <Card color={selected.theme.wash}>
                  <View style={styles.childRow}>
                    <Avatar name={selected.fullName} size={52} theme={selected.theme} />
                    <View style={{ flex: 1 }}>
                      <Heading>{selected.firstName}</Heading>
                      <Text style={[styles.themedCaption, { color: selected.theme.deep }]}>
                        {selected.roomName
                          ? `${selected.roomName}${childStatus ? ` — ${childStatus}` : ''}`
                          : (childStatus ?? '')}
                      </Text>
                    </View>
                  </View>
                  {story ? (
                    <View style={styles.story}>
                      <Text style={[styles.storyOverline, { color: selected.theme.deep }]}>
                        TODAY&apos;S STORY
                      </Text>
                      {story.educator_note ? <Body>{story.educator_note}</Body> : null}
                      <Body muted>{story.draft_text}</Body>
                      <Caption>{`Published ${fmt12(story.published_at)}`}</Caption>
                    </View>
                  ) : (
                    <View style={styles.story}>
                      <Caption>The day&apos;s story arrives at pick-up time.</Caption>
                    </View>
                  )}
                </Card>
              );
            })()
          : null}

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
  reportBox: {
    backgroundColor: colour.surface,
    borderRadius: radius.lg,
    padding: space.base,
    gap: space.xs,
  },
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: space.sm,
  },
  childRow: { flexDirection: 'row', alignItems: 'center', gap: space.md },
  themedCaption: { ...type.caption } as const,
  story: {
    backgroundColor: colour.surface,
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
