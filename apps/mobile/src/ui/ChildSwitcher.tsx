/**
 * The child switcher — the family app's steering wheel. Tap the avatar once
 * to pick from the list; tap it twice quickly (like switching Instagram
 * accounts) to jump straight to the next child, with a haptic tick.
 */

import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colour, radius, space, type } from '@tucked/ui-tokens';
import { useFamily, useTapOrDoubleTap } from '@/lib/childTheme';
import { Avatar } from './SwipeChildCard';
import { Body, Sheet } from './components';

export function ChildSwitcher() {
  const { children, selected, select, cycle } = useFamily();
  const [pickerOpen, setPickerOpen] = useState(false);
  const onTap = useTapOrDoubleTap(
    () => setPickerOpen(true),
    () => cycle(),
  );

  if (!selected) return null;
  if (children.length === 1) {
    return (
      <View style={styles.host}>
        <Avatar name={selected.fullName} size={40} theme={selected.theme} />
        <Text style={[styles.name, { color: selected.theme.deep }]}>{selected.firstName}</Text>
      </View>
    );
  }

  return (
    <>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`Viewing ${selected.firstName}. Tap to choose a child, double tap for the next one.`}
        onPress={onTap}
        style={({ pressed }) => [
          styles.host,
          styles.tappable,
          { backgroundColor: selected.theme.wash },
          pressed && { transform: [{ scale: 0.96 }] },
        ]}
      >
        <Avatar name={selected.fullName} size={36} theme={selected.theme} />
        <Text style={[styles.name, { color: selected.theme.deep }]}>{selected.firstName}</Text>
        <Ionicons name="chevron-down" size={16} color={selected.theme.deep} />
      </Pressable>

      <Sheet visible={pickerOpen} onClose={() => setPickerOpen(false)} title="Whose day?">
        <Body muted>Double-tap the avatar anywhere to jump to the next child.</Body>
        {children.map((child) => (
          <Pressable
            key={child.id}
            accessibilityRole="button"
            onPress={() => {
              select(child.id);
              setPickerOpen(false);
            }}
            style={({ pressed }) => [
              styles.row,
              { backgroundColor: child.theme.wash },
              pressed && { transform: [{ scale: 0.98 }] },
            ]}
          >
            <Avatar name={child.fullName} size={44} theme={child.theme} />
            <View style={{ flex: 1 }}>
              <Text style={[styles.rowName, { color: child.theme.deep }]}>{child.firstName}</Text>
              {child.roomName ? <Text style={styles.rowRoom}>{child.roomName}</Text> : null}
            </View>
            {selected.id === child.id ? (
              <Ionicons name="checkmark-circle" size={22} color={child.theme.deep} />
            ) : null}
          </Pressable>
        ))}
      </Sheet>
    </>
  );
}

const styles = StyleSheet.create({
  host: { flexDirection: 'row', alignItems: 'center', gap: space.sm },
  tappable: {
    borderRadius: radius.pill,
    paddingVertical: 4,
    paddingLeft: 4,
    paddingRight: space.md,
  },
  name: { ...type.label } as const,
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: space.md,
    borderRadius: radius.lg,
    padding: space.md,
  },
  rowName: { ...type.subheading } as const,
  rowRoom: { ...type.caption, color: colour.slate } as const,
});
