/**
 * Native sparkle burst — six gold stars fly out once and vanish. Decorative
 * only: never on Now/serious content. Shared by buttons and swipe cards.
 */

import { useEffect } from 'react';
import { StyleSheet, View } from 'react-native';
import Animated, { useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';
import type { SharedValue } from 'react-native-reanimated';

export const SPARKLE_GOLD = '#FFC94D';

const DIRECTIONS = [
  [0, -40], [34, -22], [40, 14], [8, 42], [-30, 30], [-40, -12],
] as const;

export function SparkleBurst() {
  const progress = useSharedValue(0);
  useEffect(() => {
    progress.value = withTiming(1, { duration: 620 });
  }, [progress]);
  return (
    <View pointerEvents="none" style={styles.host}>
      {DIRECTIONS.map(([dx, dy], i) => (
        <BurstStar key={i} dx={dx} dy={dy} progress={progress} big={i % 3 === 0} />
      ))}
    </View>
  );
}

function BurstStar({
  dx,
  dy,
  progress,
  big,
}: {
  dx: number;
  dy: number;
  progress: SharedValue<number>;
  big: boolean;
}) {
  const style = useAnimatedStyle(() => ({
    opacity: 1 - progress.value,
    transform: [
      { translateX: dx * progress.value },
      { translateY: dy * progress.value },
      { scale: 0.5 + progress.value * 0.8 },
      { rotate: `${progress.value * 90}deg` },
    ],
  }));
  return <Animated.Text style={[styles.star, big && styles.starBig, style]}>✦</Animated.Text>;
}

const styles = StyleSheet.create({
  host: { position: 'absolute', right: 28, top: 20, width: 0, height: 0 },
  star: { position: 'absolute', color: SPARKLE_GOLD, fontSize: 14 } as const,
  starBig: { fontSize: 20 } as const,
});
