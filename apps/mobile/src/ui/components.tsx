/**
 * Phase 0 primitives, styled entirely from @tucked/ui-tokens. Screens never
 * hard-code a hex, radius or font name — that rule is how the design language
 * survives (design-language.md §11).
 */

import type { ReactNode } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import type { TextInputProps } from 'react-native';
import { a11y, colour, radius, shadow, space, type } from '@tucked/ui-tokens';

export function Screen({ children }: { children: ReactNode }) {
  return <View style={styles.screen}>{children}</View>;
}

export function Card({ children }: { children: ReactNode }) {
  return <View style={styles.card}>{children}</View>;
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
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      onPress={onPress}
      disabled={busy}
      style={({ pressed }) => [
        styles.button,
        kind === 'quiet' && styles.buttonQuiet,
        pressed && styles.buttonPressed,
      ]}
    >
      {busy ? (
        <ActivityIndicator color={kind === 'primary' ? colour.surface : colour.blue600} />
      ) : (
        <Text style={[styles.buttonLabel, kind === 'quiet' && styles.buttonLabelQuiet]}>
          {label}
        </Text>
      )}
    </Pressable>
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
    borderRadius: radius.lg,
    padding: space.cardPadding,
    gap: space.sm,
    ...shadow.resting,
  },
  title: { ...type.title, color: colour.ink } as const,
  heading: { ...type.heading, color: colour.ink } as const,
  body: { ...type.body, color: colour.ink } as const,
  bodyMuted: { color: colour.slate } as const,
  caption: { ...type.caption, color: colour.slateMuted } as const,
  button: {
    backgroundColor: colour.blue600,
    borderRadius: radius.md,
    minHeight: a11y.minTouchTarget,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: space.base,
  },
  buttonQuiet: { backgroundColor: colour.blue50 },
  buttonPressed: { opacity: 0.85 },
  buttonLabel: { ...type.label, color: colour.surface } as const,
  buttonLabelQuiet: { color: colour.blue700 } as const,
  field: {
    ...type.body,
    color: colour.ink,
    backgroundColor: colour.surface,
    borderColor: colour.line,
    borderWidth: 1,
    borderRadius: radius.sm,
    minHeight: a11y.minTouchTarget,
    paddingHorizontal: space.md,
  },
});
