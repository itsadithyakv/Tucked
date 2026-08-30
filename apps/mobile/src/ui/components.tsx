/**
 * Phase 1 primitives, styled entirely from @tucked/ui-tokens — minimal
 * claymorphic: generous radii, soft ink-tinted shadows, gentle press-scale
 * feedback. Screens never hard-code a hex, radius or font name
 * (design-language.md §11).
 */

import { useState } from 'react';
import type { ReactNode } from 'react';
import {
  ActivityIndicator,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import type { TextInputProps } from 'react-native';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { a11y, colour, radius, shadow, space, type } from '@tucked/ui-tokens';
import { SparkleBurst } from './sparkle';

/** Every screen respects the device's status bar / camera cutout. */
export function Screen({ children }: { children: ReactNode }) {
  const insets = useSafeAreaInsets();
  return (
    <View style={[styles.screen, { paddingTop: insets.top + space.sm }]}>{children}</View>
  );
}

export function Card({
  children,
  wash,
  color,
}: {
  children: ReactNode;
  wash?: 'mist' | 'mint' | 'sand';
  /** A custom wash (e.g. a child's identity colour) overrides presets. */
  color?: string;
}) {
  return (
    <View
      style={[
        styles.card,
        wash === 'mist' && styles.cardMist,
        wash === 'mint' && styles.cardMint,
        wash === 'sand' && styles.cardSand,
        color ? { backgroundColor: color } : null,
      ]}
    >
      {children}
    </View>
  );
}

export function Title({ children }: { children: ReactNode }) {
  return <Text style={styles.title}>{children}</Text>;
}

export function Heading({ children }: { children: ReactNode }) {
  return <Text style={styles.heading}>{children}</Text>;
}

export function Body({ children, muted = false }: { children: ReactNode; muted?: boolean }) {
  return <Text style={[styles.body, muted && styles.bodyMuted]}>{children}</Text>;
}

export function Caption({ children }: { children: ReactNode }) {
  return <Text style={styles.caption}>{children}</Text>;
}

export function Pill({ children, kind }: { children: ReactNode; kind: 'ok' | 'due' | 'now' }) {
  return (
    <View style={[styles.pill, styles[`pill_${kind}`]]}>
      <Text style={[styles.pillText, styles[`pillText_${kind}`]]}>{children}</Text>
    </View>
  );
}

/** Squishy clay button: the press lands instantly (a fast dip + squash), the
 * release springs back with a soft overshoot. Primary presses sparkle. */
export function Button({
  label,
  onPress,
  busy = false,
  kind = 'primary',
}: {
  label: string;
  onPress: () => void;
  busy?: boolean;
  kind?: 'primary' | 'quiet';
}) {
  const squish = useSharedValue(0);
  const [burstKey, setBurstKey] = useState(0);

  const animated = useAnimatedStyle(() => ({
    transform: [
      { translateY: squish.value * 3 },
      { scaleX: 1 - squish.value * 0.04 },
      { scaleY: 1 - squish.value * 0.09 },
    ],
  }));

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
      onPressIn={() => {
        squish.value = withTiming(1, { duration: 70 });
      }}
      onPressOut={() => {
        squish.value = withSpring(0, { damping: 9, stiffness: 340 });
        if (kind === 'primary' && !busy) setBurstKey((k) => k + 1);
      }}
      disabled={busy}
    >
      <Animated.View style={[styles.button, kind === 'quiet' && styles.buttonQuiet, animated]}>
        {busy ? (
          <ActivityIndicator color={kind === 'primary' ? colour.surface : colour.blue600} />
        ) : (
          <Text style={[styles.buttonLabel, kind === 'quiet' && styles.buttonLabelQuiet]}>
            {label}
          </Text>
        )}
        {burstKey > 0 ? <SparkleBurst key={burstKey} /> : null}
      </Animated.View>
    </Pressable>
  );
}

/** Clay bottom sheet — the room device's one modal pattern. */
export function Sheet({
  visible,
  onClose,
  title,
  children,
}: {
  visible: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
}) {
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <View style={styles.sheetBackdrop}>
        <View style={styles.sheetPanel}>
          <Heading>{title}</Heading>
          <ScrollView
            style={{ maxHeight: 460 }}
            contentContainerStyle={{ gap: space.md }}
            keyboardShouldPersistTaps="handled"
          >
            {children}
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

/** A row of chunky choice chips (severity, meal, eaten…). */
export function Choices<T extends string>({
  options,
  value,
  onChange,
}: {
  options: { value: T; label: string }[];
  value: T | null;
  onChange: (v: T) => void;
}) {
  return (
    <View style={styles.choices}>
      {options.map((o) => (
        <Pressable
          key={o.value}
          accessibilityRole="button"
          onPress={() => onChange(o.value)}
          style={({ pressed }) => [
            styles.choice,
            value === o.value && styles.choiceActive,
            pressed && { transform: [{ scale: 0.96 }] },
          ]}
        >
          <Text style={[styles.choiceText, value === o.value && styles.choiceTextActive]}>
            {o.label}
          </Text>
        </Pressable>
      ))}
    </View>
  );
}

export function Field(props: TextInputProps) {
  return (
    <TextInput
      placeholderTextColor={colour.slateMuted}
      style={styles.field}
      autoCapitalize="none"
      {...props}
    />
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colour.canvas,
    padding: space.gutter,
    gap: space.cardGap,
  },
  card: {
    backgroundColor: colour.surface,
    borderRadius: radius.card,
    padding: space.lg,
    gap: space.sm,
    shadowColor: colour.ink,
    shadowOpacity: 0.07,
    shadowRadius: 14,
    shadowOffset: { width: 0, height: 6 },
    elevation: 2,
  },
  cardMist: { backgroundColor: colour.blue50 },
  cardMint: { backgroundColor: colour.okWash },
  cardSand: { backgroundColor: colour.dueWash },
  title: { ...type.title, color: colour.ink } as const,
  heading: { ...type.heading, color: colour.ink } as const,
  body: { ...type.body, color: colour.ink } as const,
  bodyMuted: { color: colour.slate } as const,
  caption: { ...type.caption, color: colour.slateMuted } as const,
  pill: {
    alignSelf: 'flex-start',
    borderRadius: radius.pill,
    paddingHorizontal: space.md,
    paddingVertical: 3,
  },
  pill_ok: { backgroundColor: colour.okWash },
  pill_due: { backgroundColor: colour.dueWash },
  pill_now: { backgroundColor: colour.nowWash },
  pillText: { ...type.overline } as const,
  pillText_ok: { color: colour.ok } as const,
  pillText_due: { color: colour.due } as const,
  pillText_now: { color: colour.now } as const,
  button: {
    backgroundColor: colour.blue500,
    borderRadius: radius.pill,
    minHeight: 50,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: space.xl,
    // the chunky clay edge: a solid deeper-blue base the button sits on
    borderBottomWidth: 4,
    borderBottomColor: colour.blue700,
    shadowColor: colour.blue600,
    shadowOpacity: 0.3,
    shadowRadius: 9,
    shadowOffset: { width: 0, height: 5 },
    elevation: 3,
  },
  buttonQuiet: {
    backgroundColor: colour.blue50,
    borderBottomColor: colour.blue100,
    borderBottomWidth: 3,
    shadowOpacity: 0,
    elevation: 0,
  },
  buttonPressed: {
    transform: [{ translateY: 3 }],
    borderBottomWidth: 1,
    shadowOpacity: 0.12,
  },
  buttonLabel: { ...type.label, color: colour.surface } as const,
  buttonLabelQuiet: { color: colour.blue700 } as const,
  field: {
    ...type.body,
    color: colour.ink,
    backgroundColor: colour.surface,
    borderColor: colour.line,
    borderWidth: 1,
    borderRadius: radius.md,
    minHeight: a11y.minTouchTarget + 4,
    paddingHorizontal: space.base,
  },
  sheetBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(23, 50, 92, 0.35)',
    justifyContent: 'flex-end',
    padding: space.base,
  },
  sheetPanel: {
    backgroundColor: colour.surface,
    borderRadius: radius.xl,
    padding: space.lg,
    gap: space.md,
    ...shadow.raised,
  },
  choices: { flexDirection: 'row', flexWrap: 'wrap', gap: space.sm },
  choice: {
    backgroundColor: colour.canvas,
    borderRadius: radius.pill,
    paddingHorizontal: space.base,
    minHeight: 44,
    justifyContent: 'center',
  },
  choiceActive: { backgroundColor: colour.blue600 },
  choiceText: { ...type.label, color: colour.slate } as const,
  choiceTextActive: { color: colour.surface } as const,
});
