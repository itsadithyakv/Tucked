import { useEffect, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colour, radius, space, type } from '@tucked/ui-tokens';
import { useFamily } from '@/lib/childTheme';
import { supabase } from '@/lib/supabase';
import { ChildSwitcher } from '@/ui/ChildSwitcher';
import { Body, Caption, Card, Heading, Pill, Screen, Title } from '@/ui/components';

interface LogRow {
  id: string;
  log_type: string;
  logged_at: string;
  payload: Record<string, unknown>;
}

const LOG_META: Record<string, { icon: keyof typeof Ionicons.glyphMap; label: (p: Record<string, unknown>) => string }> = {
  meal: { icon: 'restaurant', label: (p) => `${String(p.meal ?? 'meal').replace('_', ' ')} — ate ${p.eaten}` },
  bottle: { icon: 'water', label: (p) => `Bottle — ${p.amount_ml} ml ${String(p.kind ?? '').replace('_', ' ')}` },
  nap_start: { icon: 'moon', label: () => 'Settled for a rest' },
  nap_end: { icon: 'sunny', label: () => 'Woke up' },
  sleep_check: { icon: 'eye', label: (p) => `Sleep check — ${p.breathing_ok ? 'all well' : 'attended to'}` },
  diaper: { icon: 'sync', label: (p) => `Diaper — ${p.kind}` },
  toilet: { icon: 'checkmark-circle', label: (p) => `Toileting — ${p.kind}` },
  outdoor: {
    icon: 'partly-sunny',
    label: (p) => (p.skipped_reason ? `Stayed in — ${p.skipped_reason}` : `Outdoor play — ${p.minutes} minutes`),
  },
  health_observation: { icon: 'heart', label: (p) => `Health note — ${p.observation}` },
  activity: { icon: 'color-palette', label: (p) => String(p.description ?? 'Activity') },
  note: { icon: 'create', label: (p) => String(p.text ?? 'Note') },
  photo: { icon: 'camera', label: () => 'New photo' },
};

function fmt12(iso: string): string {
  return new Date(iso).toLocaleTimeString('en-CA', { hour: 'numeric', minute: '2-digit', hour12: true });
}

/** The day, moment by moment — everything the room recorded for this child,
 * plus the supplies nudge when the diaper count runs low. */
export default function DayLog() {
  const { selected } = useFamily();
  const childId = selected?.id ?? null;
  const [logs, setLogs] = useState<LogRow[]>([]);
  const [diapersLeft, setDiapersLeft] = useState<number | null>(null);

  useEffect(() => {
    if (!childId) return;
    const today = new Date().toISOString().slice(0, 10);
    supabase
      .from('care_log')
      .select('id, log_type, logged_at, payload')
      .eq('child_id', childId)
      .eq('log_date', today)
      .order('logged_at', { ascending: false })
      .then(({ data }) => setLogs((data as LogRow[]) ?? []));
    supabase
      .from('care_log')
      .select('payload')
      .eq('child_id', childId)
      .eq('log_type', 'diaper')
      .not('payload->supplies_remaining', 'is', null)
      .order('logged_at', { ascending: false })
      .limit(1)
      .then(({ data }) => {
        const v = (data?.[0]?.payload as { supplies_remaining?: number } | undefined)?.supplies_remaining;
        setDiapersLeft(typeof v === 'number' ? v : null);
      });
  }, [childId]);

  return (
    <Screen>
      <View style={styles.headerRow}>
        <Title>Day log</Title>
        <ChildSwitcher />
      </View>

      {diapersLeft !== null ? (
        <Card wash={diapersLeft <= 5 ? 'sand' : 'mint'}>
          <View style={styles.inventoryRow}>
            <Heading>{`${diapersLeft} diapers left at the centre`}</Heading>
            {diapersLeft <= 5 ? <Pill kind="due">Bring more</Pill> : <Pill kind="ok">Stocked</Pill>}
          </View>
        </Card>
      ) : null}

      <FlatList
        data={logs}
        keyExtractor={(l) => l.id}
        contentContainerStyle={{ gap: space.sm, paddingBottom: space.x2l }}
        renderItem={({ item }) => {
          const meta = LOG_META[item.log_type] ?? { icon: 'circle' as const, label: () => item.log_type };
          return (
            <View style={styles.row}>
              <View style={[styles.iconWrap, selected ? { backgroundColor: selected.theme.wash } : null]}>
                <Ionicons name={meta.icon} size={19} color={selected?.theme.deep ?? colour.blue700} />
              </View>
              <View style={{ flex: 1 }}>
                <Text style={styles.rowText}>{meta.label(item.payload)}</Text>
                <Caption>{fmt12(item.logged_at)}</Caption>
              </View>
            </View>
          );
        }}
        ListEmptyComponent={
          <Card>
            <Body muted>Nothing logged yet today — entries appear here as the room records them.</Body>
          </Card>
        }
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  headerRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: space.sm,
  },
  inventoryRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: space.sm,
    flexWrap: 'wrap',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: space.md,
    backgroundColor: colour.surface,
    borderRadius: radius.lg,
    padding: space.md,
  },
  iconWrap: {
    width: 38,
    height: 38,
    borderRadius: 19,
    backgroundColor: colour.blue50,
    alignItems: 'center',
    justifyContent: 'center',
  },
  rowText: { ...type.body, color: colour.ink } as const,
});
