import { Redirect } from 'expo-router';
import { ActivityIndicator, View } from 'react-native';
import { colour } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';

export default function Index() {
  const { session, profile, loading } = useAuth();

  if (loading) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colour.canvas }}>
        <ActivityIndicator color={colour.blue600} />
      </View>
    );
  }
  if (!session) return <Redirect href="/sign-in" />;
  return <Redirect href={profile?.mode === 'room' ? '/rooms' : '/home'} />;
}
