import type { ColorValue } from 'react-native';
import { Redirect, Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colour, fontFamily } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';

function icon(active: keyof typeof Ionicons.glyphMap, inactive: keyof typeof Ionicons.glyphMap) {
  return function TabIcon({ color, focused }: { color: ColorValue; focused: boolean }) {
    return <Ionicons name={focused ? active : inactive} size={24} color={color} />;
  };
}

/** Family mode: Home (today), Log (the child's day), Messages, More. */
export default function FamilyTabs() {
  const { session, loading, profile } = useAuth();
  if (!loading && !session) return <Redirect href="/sign-in" />;
  if (!loading && profile && profile.mode === 'room') return <Redirect href="/rooms" />;

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colour.blue700,
        tabBarInactiveTintColor: colour.slateMuted,
        tabBarStyle: {
          backgroundColor: colour.surface,
          borderTopColor: colour.line,
          height: 62,
          paddingTop: 6,
        },
        tabBarLabelStyle: { fontFamily: fontFamily.displaySemi, fontSize: 11 },
      }}
    >
      <Tabs.Screen
        name="home"
        options={{ title: 'Home', tabBarIcon: icon('home', 'home-outline') }}
      />
      <Tabs.Screen
        name="log"
        options={{ title: 'Log', tabBarIcon: icon('reader', 'reader-outline') }}
      />
      <Tabs.Screen
        name="messages"
        options={{ title: 'Messages', tabBarIcon: icon('chatbubble', 'chatbubble-outline') }}
      />
      <Tabs.Screen
        name="more"
        options={{ title: 'More', tabBarIcon: icon('ellipsis-horizontal-circle', 'ellipsis-horizontal-circle-outline') }}
      />
    </Tabs>
  );
}
