import { router } from 'expo-router';
import { View } from 'react-native';
import { enCA } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Avatar } from '@/ui/SwipeChildCard';
import { Body, Button, Caption, Card, Heading, Screen, Title } from '@/ui/components';

export default function More() {
  const { profile } = useAuth();
  return (
    <Screen>
      <Title>More</Title>
      {profile ? (
        <Card>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.md }}>
            <Avatar name={profile.fullName} size={44} />
            <View>
              <Heading>{profile.fullName}</Heading>
              <Caption>{profile.roles.map((r) => r.role.replace(/_/g, ' ')).join(' · ')}</Caption>
            </View>
          </View>
        </Card>
      ) : null}
      <Card>
        <Heading>Records &amp; exports</Heading>
        <Body muted>
          Registers, corrections, staff files and per-section exports live in the supervisor
          console on the web.
        </Body>
      </Card>
      <Button label="Session details" kind="quiet" onPress={() => router.push('/debug')} />
      <View style={{ marginTop: 'auto' }}>
        <Button label={enCA.auth.signOut} kind="quiet" onPress={() => supabase.auth.signOut()} />
      </View>
    </Screen>
  );
}
