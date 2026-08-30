import { useCallback, useState } from 'react';
import { Pressable, SectionList, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { colour, radius, space, type } from '@tucked/ui-tokens';
import { runCommand } from '@/lib/queue';
import { RecorderProvider, useRecorder } from '@/lib/recorder';
import { readEvacuationCache } from '@/lib/roomData';
import type { EvacCache, EvacChild } from '@/lib/roomData';
import { Body, Button, Caption, Card, Choices, Heading, Pill, Screen, Sheet, Title } from '@/ui/components';

/**
 * The evacuation screen (build prompt §7): the day's attendance list,
 * emergency contacts, allergies and medication, and a headcount tally —
 * reading ONLY the local cache, so it works with zero network, off-site,
 * mid-fire-drill. The manual specifically requires attendance to work
 * off-premises (s. 72(3)); this screen is why the app is offline-first.
 */
function EvacuationInner({ cache }: { cache: EvacCache }) {
  const { getRecorder, invalidate } = useRecorder();
  const [counted, setCounted] = useState<Set<string>>(new Set());
  const [recordOpen, setRecordOpen] = useState(false);
  const [kind, setKind] = useState<'evacuation_drill' | 'evacuation' | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // Record the muster (Part 4 written record; auto-summarised into the
  // daily written record). Offline-queued with the PIN like every write.
  async function recordMuster() {
    if (!kind) return;
    setRecordOpen(false);
    const recorder = await getRecorder();
    if (!recorder) return;
    const present = cache.children.filter((c) => c.present);
    const missing = present
      .filter((c) => !counted.has(c.id))
      .map((c) => ({ child_id: c.id, full_name: c.fullName }));
    const result = await runCommand('record_headcount', {
      p_centre: cache.centreId,
      p_room: null,
      p_kind: kind,
      p_expected: present.length,
      p_counted: present.filter((c) => counted.has(c.id)).length,
      p_missing: missing,
      p_note: null,
      p_recorder: recorder.personId,
      p_pin: recorder.pin,
    });
    if (!result.ok) {
      if (result.error?.includes('PIN')) invalidate();
      setNotice(result.error ?? 'That did not work.');
    } else {
      setNotice(
        result.queued
          ? 'Headcount saved on this device — it will sync when the connection returns.'
          : 'Headcount recorded and summarised in the daily written record.',
      );
    }
  }

  const present = cache.children.filter((c) => c.present);
  const away = cache.children.filter((c) => !c.present);
  const tally = present.filter((c) => counted.has(c.id)).length;

  function toggle(id: string) {
    setCounted((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const sections = [
    { title: `Present (${present.length})`, data: present },
    { title: `Not in today (${away.length})`, data: away },
  ];

  return (
    <Screen>
      <Title>Evacuation</Title>
      <Card wash={tally === present.length && present.length > 0 ? 'mint' : 'sand'}>
        <Heading>{`Headcount ${tally} of ${present.length}`}</Heading>
        <Caption>
          {`Tap each child as you count them — face to name, not from memory. Roster cached ${new Date(cache.refreshedAt).toLocaleTimeString('en-CA', { hour12: false, hour: '2-digit', minute: '2-digit' })} — works without any connection.`}
        </Caption>
        <Button
          label="Record this headcount"
          kind={tally === present.length && present.length > 0 ? 'primary' : 'quiet'}
          onPress={() => {
            setKind(null);
            setRecordOpen(true);
          }}
        />
        {notice ? <Body muted>{notice}</Body> : null}
      </Card>
      <SectionList
        sections={sections}
        keyExtractor={(c) => c.id}
        stickySectionHeadersEnabled={false}
        contentContainerStyle={{ gap: space.sm, paddingBottom: space.x2l }}
        renderSectionHeader={({ section }) => <Heading>{section.title}</Heading>}
        renderItem={({ item }: { item: EvacChild }) => {
          const isCounted = counted.has(item.id);
          return (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={`Count ${item.fullName}`}
              onPress={() => item.present && toggle(item.id)}
              style={({ pressed }) => [
                styles.row,
                isCounted && styles.rowCounted,
                pressed && styles.rowPressed,
              ]}
            >
              <View style={styles.rowTop}>
                <Text style={styles.name}>{item.fullName}</Text>
                {item.present ? (
                  <Pill kind={isCounted ? 'ok' : 'due'}>{isCounted ? 'Counted' : 'Tap to count'}</Pill>
                ) : (
                  <Pill kind="due">Absent</Pill>
                )}
              </View>
              <Text style={styles.meta}>{item.roomName}</Text>
              {item.allergies.length > 0 ? (
                <Text style={styles.alert}>{`Allergies: ${item.allergies.join(', ')}`}</Text>
              ) : null}
              {item.medications.length > 0 ? (
                <Text style={styles.meta}>{`Medication: ${item.medications.join(', ')}`}</Text>
              ) : null}
              {item.contacts[0] ? (
                <Text style={styles.meta}>
                  {`${item.contacts[0].name} (${item.contacts[0].relationship})${item.contacts[0].phone ? ` · ${item.contacts[0].phone}` : ''}`}
                </Text>
              ) : null}
            </Pressable>
          );
        }}
      />

      <Sheet visible={recordOpen} onClose={() => setRecordOpen(false)} title="Record the headcount">
        <Body muted>
          {`${tally} of ${present.length} accounted for${tally < present.length ? ' — anyone uncounted is recorded by name' : ''}.`}
        </Body>
        <Choices
          options={[
            { value: 'evacuation_drill', label: 'Fire drill' },
            { value: 'evacuation', label: 'Real evacuation' },
          ]}
          value={kind}
          onChange={setKind}
        />
        <Button label="Record" onPress={() => void recordMuster()} />
        <Button label="Cancel" kind="quiet" onPress={() => setRecordOpen(false)} />
      </Sheet>
    </Screen>
  );
}

/** The screen itself never needs the network or a sign-in (s. 82(2)); only
 * recording the muster asks for a PIN, using the cached staff list. */
export default function Evacuation() {
  const [cache, setCache] = useState<EvacCache | null>(null);

  useFocusEffect(
    useCallback(() => {
      readEvacuationCache().then(setCache);
    }, []),
  );

  if (!cache) {
    return (
      <Screen>
        <Title>Evacuation</Title>
        <Card wash="sand">
          <Body muted>
            No cached roster on this device yet. Open Room mode once while online and the roster
            stays available here without a connection.
          </Body>
        </Card>
      </Screen>
    );
  }

  return (
    <RecorderProvider staff={cache.staff ?? []}>
      <EvacuationInner cache={cache} />
    </RecorderProvider>
  );
}

const styles = StyleSheet.create({
  row: {
    backgroundColor: colour.surface,
    borderRadius: radius.card,
    padding: space.base,
    gap: 2,
  },
  rowCounted: { backgroundColor: colour.okWash },
  rowPressed: { transform: [{ scale: 0.99 }] },
  rowTop: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: space.sm,
  },
  name: { ...type.subheading, color: colour.ink } as const,
  meta: { ...type.caption, color: colour.slate } as const,
  alert: { ...type.caption, color: colour.now } as const,
});
