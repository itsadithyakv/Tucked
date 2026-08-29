import { ScrollView, Text, View } from 'react-native';
import { colour, fontFamily, radius, space, type } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { Caption, Card, Screen, Title } from '@/ui/components';

/** Session + theme smoke-test screen: proves auth state, role resolution, the
 * Gilroy weights, and the palette on-device. Not linked from Family mode. */
export default function Debug() {
  const { session, profile } = useAuth();

  const swatches: [string, string][] = [
    ['blue500', colour.blue500],
    ['blue600', colour.blue600],
    ['ink', colour.ink],
    ['ok', colour.ok],
    ['now', colour.now],
    ['due', colour.due],
  ];

  return (
    <Screen>
      <ScrollView contentContainerStyle={{ gap: space.cardGap }}>
        <Title>Session</Title>
        <Card>
          <Caption>{session ? `auth user ${session.user.id}` : 'no session'}</Caption>
          <Caption>{profile ? `person ${profile.personId} (${profile.fullName})` : 'no person row'}</Caption>
          <Caption>
            {profile ? profile.roles.map((r) => `${r.role}${r.qualified ? ' (qualified)' : ''}`).join(' · ') : ''}
          </Caption>
        </Card>
        <Title>Type</Title>
        <Card>
          {(Object.keys(fontFamily) as (keyof typeof fontFamily)[]).map((w) => (
            <Text key={w} style={{ fontFamily: fontFamily[w], fontSize: type.body.fontSize, color: colour.ink }}>
              {fontFamily[w]} — Maya is napping, since 12:40
            </Text>
          ))}
        </Card>
        <Title>Colour</Title>
        <Card>
          {swatches.map(([name, hex]) => (
            <View key={name} style={{ flexDirection: 'row', alignItems: 'center', gap: space.sm }}>
              <View style={{ width: 32, height: 32, borderRadius: radius.sm, backgroundColor: hex }} />
              <Caption>{`${name} ${hex}`}</Caption>
            </View>
          ))}
        </Card>
      </ScrollView>
    </Screen>
  );
}
