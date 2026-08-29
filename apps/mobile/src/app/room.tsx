import { useEffect, useState } from 'react';
import { FlatList, View } from 'react-native';
import { Link } from 'expo-router';
import { enCA } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Body, Button, Caption, Card, Heading, Screen, Title } from '@/ui/components';

interface RoomRow {
  id: string;
  name: string;
  child: { count: number }[];
}

/** Room-mode placeholder: the centre's rooms with enrolled counts. The PIN
 * gate, live ratios and sign-in flows are Phase 1. */
export default function RoomHome() {
  const { profile } = useAuth();
  const [centreName, setCentreName] = useState<string>('');
  const [rooms, setRooms] = useState<RoomRow[]>([]);

  useEffect(() => {
    supabase
      .from('centre')
      .select('name')
      .limit(1)
      .maybeSingle()
      .then(({ data }) => setCentreName(data?.name ?? ''));
    supabase
      .from('room')
      .select('id, name, child(count)')
      .order('name')
      .then(({ data }) => setRooms((data as unknown as RoomRow[]) ?? []));
  }, []);

  return (
    <Screen>
      <Title>{centreName || enCA.terms.centre}</Title>
      <Caption>
        {profile ? `${profile.fullName} · ${profile.roles.map((r) => r.role).join(', ')}` : ''}
      </Caption>
      <FlatList
        data={rooms}
        keyExtractor={(r) => r.id}
        contentContainerStyle={{ gap: space.cardGap }}
        renderItem={({ item }) => (
          <Card>
            <Heading>{item.name}</Heading>
            <Body muted>{`${item.child[0]?.count ?? 0} children enrolled`}</Body>
          </Card>
        )}
      />
      <View style={{ marginTop: 'auto', gap: space.sm }}>
        <Link href="/debug" asChild>
          <Button label="Session details" kind="quiet" onPress={() => {}} />
        </Link>
        <Button label={enCA.auth.signOut} kind="quiet" onPress={() => supabase.auth.signOut()} />
      </View>
    </Screen>
  );
}
