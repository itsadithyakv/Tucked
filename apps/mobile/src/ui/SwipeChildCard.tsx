/**
 * The swipeable attendance card — the room's main gesture. Swipe RIGHT to
 * sign a child in (mint reveal), swipe LEFT to sign out / mark absent (the
 * reveal names the action; sign-out still passes through the s. 50 release
 * sheet — a swipe never skips identity confirmation). Buttons inside the card
 * still tap normally; the pan only claims clearly-horizontal drags, so
 * vertical list scrolling is untouched. Haptics tick at the commit threshold
 * on device; a little gold sparkle burst celebrates a completed swipe.
 */

import { useEffect, useState } from 'react';
import type { ReactNode } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';
import * as Haptics from 'expo-haptics';
import { Image } from 'expo-image';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import Animated, {
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withSpring,
  withTiming,
} from 'react-native-reanimated';
import type { SharedValue } from 'react-native-reanimated';
import { colour, radius, space, type } from '@tucked/ui-tokens';

const THRESHOLD = 96;
const SPARKLE_GOLD = '#FFC94D';

function tick() {
  if (Platform.OS !== 'web') {
    void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
  }
}

function thud() {
  if (Platform.OS !== 'web') {
    void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
  }
}

const AVATAR_WASHES = [colour.blue50, colour.okWash, colour.dueWash] as const;
const AVATAR_INKS = [colour.blue700, colour.ok, colour.due] as const;

export function Avatar({ name, photoUrl, size = 52 }: { name: string; photoUrl?: string | null; size?: number }) {
  const initials = name
    .split(' ')
    .map((part) => part[0])
    .slice(0, 2)
    .join('');
  let hash = 0;
  for (const ch of name) hash = (hash * 31 + ch.charCodeAt(0)) % 997;
  const idx = hash % 3;
  if (photoUrl) {
    return (
      <Image
        source={{ uri: photoUrl }}
        style={{ width: size, height: size, borderRadius: size / 2 }}
        accessibilityLabel={name}
      />
    );
  }
  return (
    <View
      style={[
        styles.avatar,
        { width: size, height: size, borderRadius: size / 2, backgroundColor: AVATAR_WASHES[idx] },
      ]}
      accessibilityLabel={name}
    >
      <Text style={[styles.avatarText, { color: AVATAR_INKS[idx], fontSize: size * 0.36 }]}>{initials}</Text>
    </View>
  );
}

/** Six gold stars that fly out once and vanish. */
function SparkleBurst() {
  const progress = useSharedValue(0);
  useEffect(() => {
    progress.value = withTiming(1, { duration: 620 });
  }, [progress]);
  const dirs = [
    [0, -40], [34, -22], [40, 14], [8, 42], [-30, 30], [-40, -12],
  ] as const;
  return (
    <View pointerEvents="none" style={styles.burstHost}>
      {dirs.map(([dx, dy], i) => (
        <BurstStar key={i} dx={dx} dy={dy} progress={progress} big={i % 3 === 0} />
      ))}
    </View>
  );
}

function BurstStar({ dx, dy, progress, big }: { dx: number; dy: number; progress: SharedValue<number>; big: boolean }) {
  const style = useAnimatedStyle(() => ({
    opacity: 1 - progress.value,
    transform: [
      { translateX: dx * progress.value },
      { translateY: dy * progress.value },
      { scale: 0.5 + progress.value * 0.8 },
      { rotate: `${progress.value * 90}deg` },
    ],
  }));
  return (
    <Animated.Text style={[styles.burstStar, big && styles.burstStarBig, style]}>✦</Animated.Text>
  );
}

export interface SwipeChildCardProps {
  name: string;
  photoUrl?: string | null;
  present: boolean;
  subtitle?: string | null;
  /** Right swipe (sign in) — only offered when not present. */
  onSignIn: () => void;
  /** Left swipe: release flow when present, mark-absent when not. */
  onSignOut: () => void;
  onMarkAbsent: () => void;
  children?: ReactNode;
}

export function SwipeChildCard({
  name,
  photoUrl,
  present,
  subtitle,
  onSignIn,
  onSignOut,
  onMarkAbsent,
  children,
}: SwipeChildCardProps) {
  const tx = useSharedValue(0);
  const armed = useSharedValue(0);
  const [burstKey, setBurstKey] = useState(0);

  const canRight = !present;
  const leftLabel = present ? 'Sign out' : 'Mark absent';

  function commitRight() {
    thud();
    setBurstKey((k) => k + 1);
    onSignIn();
  }
  function commitLeft() {
    if (present) onSignOut();
    else {
      thud();
      onMarkAbsent();
    }
  }

  const pan = Gesture.Pan()
    .activeOffsetX([-16, 16])
    .failOffsetY([-12, 12])
    .onUpdate((e) => {
      let x = e.translationX;
      if (x > 0 && !canRight) x = x * 0.15; // present already: right swipe just squishes
      tx.value = Math.max(-160, Math.min(160, x));
      const nowArmed = Math.abs(tx.value) >= THRESHOLD ? 1 : 0;
      if (nowArmed !== armed.value) {
        armed.value = nowArmed;
        if (nowArmed) runOnJS(tick)();
      }
    })
    .onEnd(() => {
      if (tx.value >= THRESHOLD && canRight) runOnJS(commitRight)();
      else if (tx.value <= -THRESHOLD) runOnJS(commitLeft)();
      tx.value = withSpring(0, { damping: 16, stiffness: 180 });
      armed.value = 0;
    });

  const cardStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: tx.value }],
  }));
  const rightReveal = useAnimatedStyle(() => ({
    opacity: tx.value > 12 ? Math.min(1, tx.value / THRESHOLD) : 0,
  }));
  const leftReveal = useAnimatedStyle(() => ({
    opacity: tx.value < -12 ? Math.min(1, -tx.value / THRESHOLD) : 0,
  }));

  return (
    <View style={styles.host}>
      <Animated.View style={[styles.reveal, styles.revealRight, rightReveal]}>
        <Text style={[styles.revealText, { color: colour.ok }]}>{canRight ? 'Sign in  →' : ''}</Text>
      </Animated.View>
      <Animated.View style={[styles.reveal, styles.revealLeft, leftReveal]}>
        <Text style={[styles.revealText, { color: present ? colour.blue700 : colour.due }]}>
          {`←  ${leftLabel}`}
        </Text>
      </Animated.View>
      <GestureDetector gesture={pan}>
        <Animated.View style={[styles.card, cardStyle]}>
          <View style={styles.row}>
            <Avatar name={name} photoUrl={photoUrl} />
            <View style={styles.info}>
              <Text style={styles.name}>{name}</Text>
              {subtitle ? <Text style={styles.subtitle}>{subtitle}</Text> : null}
            </View>
            <View
              style={[styles.dot, { backgroundColor: present ? colour.ok : colour.line }]}
              accessibilityLabel={present ? 'Present' : 'Not in'}
            />
          </View>
          {children}
          {burstKey > 0 ? <SparkleBurst key={burstKey} /> : null}
        </Animated.View>
      </GestureDetector>
    </View>
  );
}

const styles = StyleSheet.create({
  host: { position: 'relative' },
  reveal: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    left: 0,
    right: 0,
    borderRadius: radius.card,
    justifyContent: 'center',
    paddingHorizontal: space.lg,
  },
  revealRight: { backgroundColor: colour.okWash, alignItems: 'flex-start' },
  revealLeft: { backgroundColor: colour.blue50, alignItems: 'flex-end' },
  revealText: { ...type.heading } as const,
  card: {
    backgroundColor: colour.surface,
    borderRadius: radius.card,
    padding: space.base,
    gap: space.sm,
    shadowColor: colour.ink,
    shadowOpacity: 0.07,
    shadowRadius: 14,
    shadowOffset: { width: 0, height: 6 },
    elevation: 2,
  },
  row: { flexDirection: 'row', alignItems: 'center', gap: space.md },
  info: { flex: 1, gap: 2 },
  name: { ...type.subheading, color: colour.ink } as const,
  subtitle: { ...type.caption, color: colour.slateMuted } as const,
  dot: { width: 14, height: 14, borderRadius: 7 },
  avatar: { alignItems: 'center', justifyContent: 'center' },
  avatarText: { fontFamily: type.heading.fontFamily } as const,
  burstHost: {
    position: 'absolute',
    right: 28,
    top: 20,
    width: 0,
    height: 0,
  },
  burstStar: {
    position: 'absolute',
    color: SPARKLE_GOLD,
    fontSize: 14,
  } as const,
  burstStarBig: { fontSize: 20 } as const,
});
