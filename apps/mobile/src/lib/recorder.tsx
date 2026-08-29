/**
 * "The PIN is who logged it" (build prompt §2). Every regulated write names a
 * staff member verified by their PIN. The recorder sheet asks once and then
 * remembers for five minutes of activity on this device — long enough to sign
 * a room in, short enough that a wandering tablet is useless.
 */

import { createContext, useCallback, useContext, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { FlatList, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { colour, radius, shadow, space, type } from '@tucked/ui-tokens';
import { Body, Button, Field, Heading } from '@/ui/components';

export interface Recorder {
  personId: string;
  pin: string;
}

export interface StaffOption {
  personId: string;
  fullName: string;
  role: string;
}

interface RecorderCtx {
  /** Resolve the current recorder, prompting with the PIN sheet if needed. */
  getRecorder: () => Promise<Recorder | null>;
  /** Invalid PIN came back from the server — forget the cache. */
  invalidate: () => void;
}

const Ctx = createContext<RecorderCtx | null>(null);

const CACHE_MS = 5 * 60 * 1000;

export function RecorderProvider({
  staff,
  children,
}: {
  staff: StaffOption[];
  children: ReactNode;
}) {
  const cache = useRef<{ recorder: Recorder; expiresAt: number } | null>(null);
  const pending = useRef<((r: Recorder | null) => void) | null>(null);
  const [visible, setVisible] = useState(false);
  const [selected, setSelected] = useState<StaffOption | null>(null);
  const [pin, setPin] = useState('');

  const getRecorder = useCallback(async (): Promise<Recorder | null> => {
    const cached = cache.current;
    if (cached && cached.expiresAt > Date.now()) {
      cached.expiresAt = Date.now() + CACHE_MS; // sliding window
      return cached.recorder;
    }
    return new Promise((resolve) => {
      pending.current = resolve;
      setSelected(null);
      setPin('');
      setVisible(true);
    });
  }, []);

  const invalidate = useCallback(() => {
    cache.current = null;
  }, []);

  function finish(recorder: Recorder | null) {
    if (recorder) cache.current = { recorder, expiresAt: Date.now() + CACHE_MS };
    setVisible(false);
    pending.current?.(recorder);
    pending.current = null;
  }

  return (
    <Ctx.Provider value={{ getRecorder, invalidate }}>
      {children}
      <Modal visible={visible} transparent animationType="fade" onRequestClose={() => finish(null)}>
        <View style={styles.backdrop}>
          <View style={styles.sheet}>
            {selected === null ? (
              <>
                <Heading>Who is recording?</Heading>
                <FlatList
                  data={staff}
                  keyExtractor={(s) => s.personId}
                  style={{ maxHeight: 320 }}
                  contentContainerStyle={{ gap: space.sm }}
                  renderItem={({ item }) => (
                    <Pressable
                      accessibilityRole="button"
                      style={({ pressed }) => [styles.staffRow, pressed && styles.staffRowPressed]}
                      onPress={() => setSelected(item)}
                    >
                      <Text style={styles.staffName}>{item.fullName}</Text>
                      <Text style={styles.staffRole}>{item.role.replace(/_/g, ' ')}</Text>
                    </Pressable>
                  )}
                />
                <Button label="Cancel" kind="quiet" onPress={() => finish(null)} />
              </>
            ) : (
              <>
                <Heading>{selected.fullName}</Heading>
                <Body muted>Enter your staff PIN to sign this record.</Body>
                <Field
                  placeholder="PIN"
                  secureTextEntry
                  keyboardType="number-pad"
                  maxLength={6}
                  value={pin}
                  onChangeText={setPin}
                  accessibilityLabel="Staff PIN"
                  autoFocus
                />
                <Button
                  label="Confirm"
                  onPress={() => {
                    if (pin.length >= 4) finish({ personId: selected.personId, pin });
                  }}
                />
                <Button label="Back" kind="quiet" onPress={() => setSelected(null)} />
              </>
            )}
          </View>
        </View>
      </Modal>
    </Ctx.Provider>
  );
}

export function useRecorder(): RecorderCtx {
  const ctx = useContext(Ctx);
  if (!ctx) throw new Error('useRecorder outside RecorderProvider');
  return ctx;
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(23, 50, 92, 0.35)',
    justifyContent: 'flex-end',
    padding: space.base,
  },
  sheet: {
    backgroundColor: colour.surface,
    borderRadius: radius.xl,
    padding: space.lg,
    gap: space.md,
    ...shadow.raised,
  },
  staffRow: {
    backgroundColor: colour.canvas,
    borderRadius: radius.md,
    paddingHorizontal: space.base,
    paddingVertical: space.md,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    minHeight: 52,
  },
  staffRowPressed: { backgroundColor: colour.blue50, transform: [{ scale: 0.98 }] },
  staffName: { ...type.subheading, color: colour.ink } as const,
  staffRole: { ...type.caption, color: colour.slateMuted } as const,
});
