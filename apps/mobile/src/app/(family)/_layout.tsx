import { Redirect, Tabs } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colour, fontFamily } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';

/** Family mode: a real app shape — Home (today), Log (the child's day),
 * Messages, More (records, settings, sign out lives here, not on the home). */
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
        },
        tabBarLabelStyle: { fontFamily: fontFamily.displaySemi, fontSize: 11 },
      }}
    >
      <Tabs.Screen
        name="home"
        options={{
          title: 'Home',
          tabBarIcon: ({ color, size }) => <Feather name="home" size={size} color={color} />,
        }}
      />
      <Tabs.Screen
        name="log"
        options={{
          title: 'Log',
          tabBarIcon: ({ color, size }) => <Feather name="list" size={size} color={color} />,
        }}
      />
      <Tabs.Screen
        name="messages"
        options={{
          title: 'Messages',
          tabBarIcon: ({ color, size }) => <Feather name="message-circle" size={size} color={color} />,
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
