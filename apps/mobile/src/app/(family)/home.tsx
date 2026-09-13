import { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { enCA, localDateISO, localMinutes } from '@tucked/domain';
import { colour, radius, space, type } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { useFamily } from '@/lib/childTheme';
import { supabase } from '@/lib/supabase';
import { Avatar } from '@/ui/SwipeChildCard';
import { ChildSwitcher } from '@/ui/ChildSwitcher';
import { PhotoStrip } from '@/ui/PhotoStrip';
import { Body, Button, Caption, Card, Field, Heading, Pill, Screen, Title } from '@/ui/components';

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
  status: string;
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

interface Notice {
  id: string;
  child_id: string;
  notice_date: string;
  kind: 'absent' | 'late';
  expected_at: string | null;
  reason: string | null;
}

interface Exclusion {
  id: string;
  child_id: string;
  exclusion_reason: string;
  return_criteria: string;
  may_return_at: string | null;
}

/** A time in the centre's clock, the way a family reads it. */
function fmt12(iso: string, timeZone?: string): string {
  return new Date(iso).toLocaleTimeString('en-CA', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
    timeZone,
  });
}

/** "10:15:00" → "10:15 a.m." */
function clock12(hhmmss: string): string {
  const [h, m] = hhmmss.split(':').map(Number) as [number, number];
  return `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, '0')} ${h >= 12 ? 'p.m.' : 'a.m.'}`;
}

/** A calendar date for a heading: "Tuesday 15 September". */
function dayName(iso: string): string {
  return new Date(`${iso}T12:00:00Z`).toLocaleDateString('en-CA', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    timeZone: 'UTC',
  });
}

const ABSENT_REASONS = ['Unwell', 'Family plans', 'No reason needed'] as const;
const LATE_BY = [
  { label: 'About 15 minutes', minutes: 15 },
  { label: 'About 30 minutes', minutes: 30 },
  { label: 'About an hour', minutes: 60 },
] as const;

/** The current decision first: each child's status, today's story, loud
 * alerts only when they matter — and the centre's quiet announcements. */
export default function FamilyHome() {
  const { profile } = useAuth();
  const { selected, ready, children } = useFamily();
  const [alerts, setAlerts] = useState<NowAlert[]>([]);
  const [stories, setStories] = useState<Map<string, StoryRow>>(new Map());
  const [status, setStatus] = useState<Map<string, string>>(new Map());
  const [announcements, setAnnouncements] = useState<Announcement[]>([]);
  const [reportDetails, setReportDetails] = useState<Map<string, ReportDetail>>(new Map());
  const [planDetails, setPlanDetails] = useState<Map<string, PlanDetail>>(new Map());
  const [busyAlert, setBusyAlert] = useState<string | null>(null);
  // a plan review the family is answering "something has changed" to
  const [changing, setChanging] = useState<string | null>(null);
  const [changeNote, setChangeNote] = useState('');
  const [alertError, setAlertError] = useState<{ id: string; message: string } | null>(null);
  const [notices, setNotices] = useState<Notice[]>([]);
  const [exclusions, setExclusions] = useState<Exclusion[]>([]);
  const [noticeMode, setNoticeMode] = useState<null | 'absent' | 'late'>(null);
  const [noticeBusy, setNoticeBusy] = useState(false);
  const [noticeError, setNoticeError] = useState<string | null>(null);

  const tz = selected?.timeZone ?? null;
  // a stable string, so the callback below does not change identity on every render
  const childKey = children.map((c) => c.id).join(',');

  const refresh = useCallback(() => {
    if (!profile || !tz || childKey === '') return;
    const childIds = childKey.split(',');
    // The CENTRE's day, not UTC's: from 8 p.m. in Toronto the UTC date is
    // tomorrow, which is exactly when a family sits down to read the story.
    const today = localDateISO(tz);

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
        // a plan asks for real agreement, or a real review — show it in full before the buttons
        const planIds = rows
          .filter((a) => (a.event_type === 'plan_agreement' || a.event_type === 'plan_review') && a.ref_id)
          .map((a) => a.ref_id!);
        if (planIds.length > 0) {
          void supabase
            .from('individualised_plan')
            .select(
              'id, status, plan_type, condition, allergens, signs, emergency_procedure, devices_instructions, supports, developed_with, child:child_id(full_name)',
            )
            .in('id', planIds)
            .then(({ data: plansRows }) =>
              setPlanDetails(new Map(((plansRows as never as PlanDetail[]) ?? []).map((p) => [p.id, p]))),
            );
        }
      });

    // Every child-shaped query below is scoped to THIS family's children. RLS
    // is not the filter on a family screen: a parent who also works at the
    // centre can see every child's day through their staff role, and none of
    // it belongs on the screen they open as a parent.
    supabase
      .from('story')
      .select('child_id, draft_text, educator_note, published_at')
      .eq('story_date', today)
      .in('child_id', childIds)
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
      .in('child_id', childIds)
      .order('actual_time')
      .then(({ data }) => {
        const map = new Map<string, string>();
        for (const e of (data as { child_id: string; event_type: string; actual_time: string }[]) ?? []) {
          if (e.event_type === 'arrive') map.set(e.child_id, `arrived ${fmt12(e.actual_time, tz)}`);
          else if (e.event_type === 'depart') map.set(e.child_id, `picked up at ${fmt12(e.actual_time, tz)}`);
          else if (e.event_type === 'absent') map.set(e.child_id, 'marked absent today');
        }
        setStatus(map);
      });
    supabase
      .from('absence_notice')
      .select('id, child_id, notice_date, kind, expected_at, reason')
      .in('child_id', childIds)
      .gte('notice_date', today)
      .is('withdrawn_at', null)
      .order('notice_date')
      .then(({ data }) => setNotices((data as Notice[]) ?? []));
    // s. 36: moved here from More. "When can she come back?" is the one
    // question a parent of a sick child has, and it was three screens away.
    supabase
      .from('health_exclusion')
      .select('id, child_id, exclusion_reason, return_criteria, may_return_at')
      .in('child_id', childIds)
      .is('returned_at', null)
      .then(({ data }) => setExclusions((data as Exclusion[]) ?? []));
  }, [profile, tz, childKey]);

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

  /** The plan is still right, or it is not and here is what changed. Either
   * way the family's answer IS the review: named, dated, in writing. */
  async function answerReview(alert: NowAlert, stillRight: boolean) {
    if (!alert.ref_id) return;
    setBusyAlert(alert.id);
    setAlertError(null);
    const { error } = await supabase.rpc('answer_plan_review', {
      p_plan: alert.ref_id,
      p_still_accurate: stillRight,
      p_note: stillRight ? null : changeNote,
    });
    setBusyAlert(null);
    if (error) {
      setAlertError({ id: alert.id, message: error.message });
      return;
    }
    setChanging(null);
    setChangeNote('');
    refresh();
  }

  /** s. 50: tell the room before anybody has to phone. */
  async function giveNotice(kind: 'absent' | 'late', opts: { reason?: string; inMinutes?: number }) {
    if (!selected || !tz) return;
    setNoticeBusy(true);
    setNoticeError(null);
    let expected: string | null = null;
    if (kind === 'late') {
      // from the CENTRE's clock: "about 30 minutes" means 30 minutes from now there
      const at = Math.min(localMinutes(tz) + (opts.inMinutes ?? 30), 23 * 60 + 59);
      expected = `${String(Math.floor(at / 60)).padStart(2, '0')}:${String(at % 60).padStart(2, '0')}`;
    }
    const { error } = await supabase.rpc('report_absence', {
      p_child: selected.id,
      p_date: localDateISO(tz),
      p_kind: kind,
      p_expected_at: expected,
      p_reason: opts.reason && opts.reason !== 'No reason needed' ? opts.reason : null,
    });
    setNoticeBusy(false);
    setNoticeMode(null);
    if (error) setNoticeError(error.message);
    refresh();
  }

  async function takeBack(id: string) {
    setNoticeError(null);
    const { error } = await supabase.rpc('withdraw_absence_notice', { p_notice: id });
    if (error) setNoticeError(error.message);
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
          const isPlanAlert = alert.event_type === 'plan_agreement' || alert.event_type === 'plan_review';
          const plan = isPlanAlert && alert.ref_id ? planDetails.get(alert.ref_id) : undefined;
          // asked to review a version the centre has since replaced
          const staleReview = alert.event_type === 'plan_review' && plan !== undefined && plan.status !== 'active';
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
                  <Caption>
                    {alert.event_type === 'plan_review'
                      ? staleReview
                        ? 'The centre has since replaced this version, so there is nothing to review here.'
                        : `Developed with ${plan.developed_with}. If it is still right, say so. If something has changed, tell the centre what; nothing changes until you both agree a new version.`
                      : `Developed with ${plan.developed_with}. Agreeing puts this plan into practice.`}
                  </Caption>
                </View>
              ) : (
                <Body>{alert.body}</Body>
              )}
              <Caption>{`Sent ${fmt12(alert.created_at, tz ?? undefined)}`}</Caption>
              {isPlanAlert && !plan ? (
                // No button until the plan itself is on screen: agreeing to, or
                // confirming, words the parent has not been shown is not consent.
                <Caption>Loading the plan…</Caption>
              ) : alert.event_type === 'plan_review' && !staleReview ? (
                changing === alert.id ? (
                  <>
                    <Field
                      value={changeNote}
                      onChangeText={setChangeNote}
                      placeholder="What has changed? A new allergy, a new medication, a new doctor's letter…"
                      multiline
                      maxLength={1000}
                      autoCapitalize="sentences"
                    />
                    <Button
                      label="Send to the centre"
                      busy={busyAlert === alert.id}
                      onPress={() => void answerReview(alert, false)}
                    />
                    <Button label="Cancel" kind="quiet" onPress={() => setChanging(null)} />
                  </>
                ) : (
                  <>
                    <Button
                      label="Yes, it is still right"
                      busy={busyAlert === alert.id}
                      onPress={() => void answerReview(alert, true)}
                    />
                    <Button
                      label="Something has changed"
                      kind="quiet"
                      onPress={() => {
                        setChanging(alert.id);
                        setChangeNote('');
                      }}
                    />
                  </>
                )
              ) : (
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
              )}
              {alertError?.id === alert.id ? <Caption>{alertError.message}</Caption> : null}
            </View>
          );
        })}

        {ready && !selected ? (
          <Card>
            <Body muted>{enCA.home.familyEmpty}</Body>
          </Card>
        ) : null}

        {selected && tz
          ? (() => {
              const today = localDateISO(tz);
              const story = stories.get(selected.id);
              const childStatus = status.get(selected.id);
              const exclusion = exclusions.find((e) => e.child_id === selected.id);
              const notice = notices.find((n) => n.child_id === selected.id && n.notice_date === today);
              const upcoming = notices.filter((n) => n.child_id === selected.id && n.notice_date > today);
              const notHereYet = !childStatus && !exclusion && !notice;
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

                  {exclusion ? (
                    <View style={styles.story}>
                      <View style={styles.rowBetween}>
                        <Heading>{`${selected.firstName} is home unwell`}</Heading>
                        <Pill kind="due">Away</Pill>
                      </View>
                      <Body>{exclusion.exclusion_reason}</Body>
                      <Body muted>{`Before coming back: ${exclusion.return_criteria}`}</Body>
                      {exclusion.may_return_at ? (
                        <Caption>
                          {`Earliest return: ${new Date(exclusion.may_return_at).toLocaleString('en-CA', { weekday: 'long', hour: 'numeric', minute: '2-digit', hour12: true, timeZone: tz })}. If a doctor says sooner, tell the centre and bring the note.`}
                        </Caption>
                      ) : null}
                    </View>
                  ) : null}

                  {notice ? (
                    <View style={styles.story}>
                      <Body>
                        {notice.kind === 'absent'
                          ? `You told the centre ${selected.firstName} is not coming today${notice.reason ? ` — ${notice.reason.toLowerCase()}` : ''}.`
                          : `You told the centre ${selected.firstName} is running late — about ${clock12(notice.expected_at ?? '00:00')}.`}
                      </Body>
                      <Caption>The room can see this.</Caption>
                      <Button label="Take it back" kind="quiet" onPress={() => void takeBack(notice.id)} />
                    </View>
                  ) : null}

                  {notHereYet ? (
                    <View style={styles.story}>
                      {noticeMode === null ? (
                        <>
                          <Caption>{`Not bringing ${selected.firstName} in, or on your way late? Tell the room here instead of waiting for a call.`}</Caption>
                          <View style={styles.rowWrap}>
                            <Button label="Not coming today" kind="quiet" onPress={() => setNoticeMode('absent')} />
                            <Button label="Running late" kind="quiet" onPress={() => setNoticeMode('late')} />
                          </View>
                        </>
                      ) : noticeMode === 'absent' ? (
                        <>
                          <Caption>A reason is optional — the centre does not need a diagnosis.</Caption>
                          {ABSENT_REASONS.map((r) => (
                            <Button
                              key={r}
                              label={r}
                              kind="quiet"
                              busy={noticeBusy}
                              onPress={() => void giveNotice('absent', { reason: r })}
                            />
                          ))}
                          <Button label="Cancel" kind="quiet" onPress={() => setNoticeMode(null)} />
                        </>
                      ) : (
                        <>
                          <Caption>Roughly when will you arrive?</Caption>
                          {LATE_BY.map((l) => (
                            <Button
                              key={l.minutes}
                              label={l.label}
                              kind="quiet"
                              busy={noticeBusy}
                              onPress={() => void giveNotice('late', { inMinutes: l.minutes })}
                            />
                          ))}
                          <Button label="Cancel" kind="quiet" onPress={() => setNoticeMode(null)} />
                        </>
                      )}
                    </View>
                  ) : null}

                  {noticeError ? <Caption>{noticeError}</Caption> : null}

                  {upcoming.map((n) => (
                    <View key={n.id} style={styles.rowBetween}>
                      <Caption>{`Not coming ${dayName(n.notice_date)}${n.reason ? ` — ${n.reason.toLowerCase()}` : ''}`}</Caption>
                      <Button label="Take back" kind="quiet" onPress={() => void takeBack(n.id)} />
                    </View>
                  ))}

                  <PhotoStrip childId={selected.id} firstName={selected.firstName} timeZone={selected.timeZone} />

                  {story ? (
                    <View style={styles.story}>
                      <Text style={[styles.storyOverline, { color: selected.theme.deep }]}>
                        TODAY&apos;S STORY
                      </Text>
                      {story.educator_note ? <Body>{story.educator_note}</Body> : null}
                      <Body muted>{story.draft_text}</Body>
                      <Caption>{`Published ${fmt12(story.published_at, tz)}`}</Caption>
                    </View>
                  ) : notice?.kind === 'absent' || exclusion ? null : (
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
                <Caption>{fmt12(a.published_at, tz ?? undefined)}</Caption>
              </Card>
            ))}
          </>
        ) : null}
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
  rowBetween: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: space.sm,
  },
  rowWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: space.sm },
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
