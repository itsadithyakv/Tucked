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

/** Room mode: Overview (supervisors keep a check on everything), Rooms (the
 * day's work), Staffing, Evacuation, More. */
export default function RoomTabs() {
  const { session, loading, profile } = useAuth();
  if (!loading && !session) return <Redirect href="/sign-in" />;
  if (!loading && profile && profile.mode === 'family') return <Redirect href="/home" />;

  const isSupervisor =
    profile?.roles.some((r) => ['supervisor', 'designate', 'licensee_admin'].includes(r.role)) ?? false;

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
        name="overview"
        options={{
          title: 'Overview',
          tabBarIcon: icon('sparkles', 'sparkles-outline'),
          href: isSupervisor ? '/overview' : null,
        }}
      />
      <Tabs.Screen
        name="rooms"
        options={{ title: 'Rooms', tabBarIcon: icon('grid', 'grid-outline') }}
      />
      <Tabs.Screen
        name="staffing"
        options={{ title: 'Staffing', tabBarIcon: icon('people', 'people-outline') }}
      />
      <Tabs.Screen
        name="evacuation"
        options={{ title: 'Evacuation', tabBarIcon: icon('warning', 'warning-outline') }}
      />
      <Tabs.Screen
        name="more"
        options={{ title: 'More', tabBarIcon: icon('ellipsis-horizontal-circle', 'ellipsis-horizontal-circle-outline') }}
      />
    </Tabs>
  );
}
