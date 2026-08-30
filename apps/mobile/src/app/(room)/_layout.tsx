import { Redirect, Tabs } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colour, fontFamily } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';

/** Room mode: Rooms (the day's work), Staffing (who is where — supervisors
 * assign), Evacuation always one tap away, More for everything else. */
export default function RoomTabs() {
  const { session, loading, profile } = useAuth();
  if (!loading && !session) return <Redirect href="/sign-in" />;
  if (!loading && profile && profile.mode === 'family') return <Redirect href="/home" />;

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colour.blue700,
        tabBarInactiveTintColor: colour.slateMuted,
        tabBarStyle: {
          backgroundColor: colour.surface,
          borderTopColor: colour.line,
        },
        tabBarLabelStyle: { fontFamily: fontFamily.displaySemi, fontSize: 11 },
      }}
    >
      <Tabs.Screen
        name="rooms"
        options={{
          title: 'Rooms',
          tabBarIcon: ({ color, size }) => <Feather name="grid" size={size} color={color} />,
        }}
      />
      <Tabs.Screen
        name="staffing"
        options={{
          title: 'Staffing',
          tabBarIcon: ({ color, size }) => <Feather name="users" size={size} color={color} />,
        }}
      />
      <Tabs.Screen
        name="evacuation"
        options={{
          title: 'Evacuation',
          tabBarIcon: ({ color, size }) => <Feather name="alert-triangle" size={size} color={color} />,
        }}
      />
      <Tabs.Screen
        name="more"
        options={{
          title: 'More',
          tabBarIcon: ({ color, size }) => <Feather name="more-horizontal" size={size} color={color} />,
        }}
      />
    </Tabs>
  );
}
