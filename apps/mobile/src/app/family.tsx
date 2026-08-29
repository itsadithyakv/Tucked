import { useEffect, useState } from 'react';
import { FlatList, View } from 'react-native';
import { enCA } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Body, Button, Caption, Card, Heading, Screen, Title } from '@/ui/components';

interface ChildRow {
  id: string;
  full_name: string;
  date_of_birth: string;
  room: { name: string } | null;
}

/** Family home placeholder. RLS scopes the query: a parent sees exactly the
 * children of households where they are an un-revoked viewing member. */
export default function FamilyHome() {
  const { profile } = useAuth();
  const [children, setChildren] = useState<ChildRow[] | null>(null);

  useEffect(() => {
    supabase
      .from('child')
      .select('id, full_name, date_of_birth, room:current_room_id(name)')
      .order('full_name')
      .then(({ data }) => setChildren((data as unknown as ChildRow[]) ?? []));
  }, []);

  return (
    <Screen>
      <Title>{profile ? profile.fullName : 'Family'}</Title>
      {children !== null && children.length === 0 ? (
        <Card>
          <Body muted>{enCA.home.familyEmpty}</Body>
        </Card>
      ) : (
        <FlatList
          data={children ?? []}
          keyExtractor={(c) => c.id}
          contentContainerStyle={{ gap: space.cardGap }}
          renderItem={({ item }) => (
            <Card>
              <Heading>{item.full_name}</Heading>
              <Body muted>{item.room ? item.room.name : 'No room assigned yet'}</Body>
              <Caption>Born {item.date_of_birth}</Caption>
            </Card>
          )}
        />
      )}
      <View style={{ marginTop: 'auto' }}>
        <Button label={enCA.auth.signOut} kind="quiet" onPress={() => supabase.auth.signOut()} />
      </View>
    </Screen>
  );
}
