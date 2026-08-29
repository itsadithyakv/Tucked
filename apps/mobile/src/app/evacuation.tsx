import { useCallback, useState } from 'react';
import { Pressable, SectionList, StyleSheet, Text, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { colour, radius, space, type } from '@tucked/ui-tokens';
import { readEvacuationCache } from '@/lib/roomData';
import type { EvacCache, EvacChild } from '@/lib/roomData';
import { Body, Caption, Card, Heading, Pill, Screen, Title } from '@/ui/components';

/**
 * The evacuation screen (build prompt §7): the day's attendance list,
 * emergency contacts, allergies and medication, and a headcount tally —
 * reading ONLY the local cache, so it works with zero network, off-site,
 * mid-fire-drill. The manual specifically requires attendance to work
 * off-premises (s. 72(3)); this screen is why the app is offline-first.
 */
export default function Evacuation() {
  const [cache, setCache] = useState<EvacCache | null>(null);
  const [counted, setCounted] = useState<Set<string>>(new Set());

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
      <View style={styles.header}>
        <Title>Evacuation</Title>
        <Pressable accessibilityRole="button" onPress={() => router.back()} style={styles.back}>
          <Text style={styles.backText}>Back</Text>
        </Pressable>
      </View>
      <Card wash={tally === present.length && present.length > 0 ? 'mint' : 'sand'}>
        <Heading>{`Headcount ${tally} of ${present.length}`}</Heading>
        <Caption>
          {`Tap each child as you count them. Roster cached ${new Date(cache.refreshedAt).toLocaleTimeString('en-CA', { hour12: false, hour: '2-digit', minute: '2-digit' })} — works without any connection.`}
        </Caption>
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
  back: {
    backgroundColor: colour.blue50,
    borderRadius: radius.pill,
    paddingHorizontal: space.base,
    minHeight: 44,
    justifyContent: 'center',
  },
  backText: { ...type.label, color: colour.blue700 } as const,
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
