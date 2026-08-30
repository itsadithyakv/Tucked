import { useCallback, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { enCA } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Avatar } from '@/ui/SwipeChildCard';
import { Body, Button, Caption, Card, Heading, Pill, Screen, Title } from '@/ui/components';

interface ChildRow {
  id: string;
  full_name: string;
}

/** Everything that isn't the day itself: the enrolment records, account
 * details — and sign out, deliberately tucked away back here. */
export default function More() {
  const { profile } = useAuth();
  const [children, setChildren] = useState<ChildRow[]>([]);
  const [recordDone, setRecordDone] = useState<Map<string, number>>(new Map());

  useFocusEffect(
    useCallback(() => {
      supabase
        .from('child')
        .select('id, full_name')
        .order('full_name')
        .then(({ data }) => setChildren(data ?? []));
      supabase
        .from('child_record_item')
        .select('child_id, status')
        .then(({ data }) => {
          const map = new Map<string, number>();
          for (const i of (data as { child_id: string; status: string }[]) ?? []) {
            if (i.status !== 'missing') map.set(i.child_id, (map.get(i.child_id) ?? 0) + 1);
          }
          setRecordDone(map);
        });
    }, []),
  );

  return (
    <Screen>
      <ScrollView contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}>
        <Title>More</Title>
        {profile ? (
          <Card>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: space.md }}>
              <Avatar name={profile.fullName} size={44} />
              <View>
                <Heading>{profile.fullName}</Heading>
                <Caption>Family account</Caption>
              </View>
            </View>
          </Card>
        ) : null}

        <Heading>Enrolment records</Heading>
        {children.map((c) => {
          const done = recordDone.get(c.id) ?? 0;
          return (
            <Card key={c.id}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
                <Body>{c.full_name}</Body>
                <Pill kind={done >= 11 ? 'ok' : 'due'}>{done >= 11 ? 'Complete' : `${done} of 11`}</Pill>
              </View>
              <Button
                label={done >= 11 ? 'Review record' : 'Complete record'}
                kind="quiet"
                onPress={() => router.push({ pathname: '/enrolment/[childId]', params: { childId: c.id } })}
              />
            </Card>
          );
        })}

        <Card>
          <Heading>About sign-in</Heading>
          <Body muted>
            Your centre invites you by email. Signing in sends a one-time link to that address —
            open it on this phone and you are in. No password to remember or lose.
          </Body>
        </Card>

        <Button label={enCA.auth.signOut} kind="quiet" onPress={() => supabase.auth.signOut()} />
      </ScrollView>
    </Screen>
  );
}
