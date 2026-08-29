import { useCallback, useEffect, useState } from 'react';
import { FlatList, View } from 'react-native';
import { Link, Redirect, useFocusEffect } from 'expo-router';
import Animated, { FadeInDown } from 'react-native-reanimated';
import { enCA } from '@tucked/domain';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { loadRoomDay, presentByRoom, refreshEvacuationCache } from '@/lib/roomData';
import type { RoomDay } from '@/lib/roomData';
import { loadQueue, queueState, startQueuePump, subscribeQueue } from '@/lib/queue';
import { Body, Button, Caption, Card, Heading, Pill, Screen, Title } from '@/ui/components';

/** Room-mode hub: pick a room board, reach the evacuation screen in one tap,
 * see sync state. The evacuation cache refreshes on every load so it is
 * always at most a few minutes old when the network disappears. */
export default function RoomHub() {
  const { session, loading, profile } = useAuth();
  const [day, setDay] = useState<RoomDay | null>(null);
  const [queue, setQueue] = useState(queueState());

  const refresh = useCallback(() => {
    loadRoomDay().then((d) => {
      setDay(d);
      if (d) void refreshEvacuationCache(d);
    });
  }, []);

  useFocusEffect(refresh);

  useEffect(() => {
    void loadQueue();
    const stop = startQueuePump();
    const unsub = subscribeQueue(() => setQueue(queueState()));
    return () => {
      stop();
      unsub();
    };
  }, []);

  if (!loading && !session) return <Redirect href="/sign-in" />;

  const present = day ? presentByRoom(day.attendance) : new Map<string, Set<string>>();

  return (
    <Screen>
      <Title>{day?.centre.name ?? enCA.terms.centre}</Title>
      <Caption>
        {profile ? `${profile.fullName} · ${profile.roles.map((r) => r.role).join(', ')}` : ''}
      </Caption>
      {queue.pending > 0 ? (
        <Card wash="mist">
          <Body muted>{`Working offline — ${queue.pending} item${queue.pending === 1 ? '' : 's'} will sync when the connection returns.`}</Body>
        </Card>
      ) : null}
      {queue.failed.length > 0 ? (
        <Card wash="sand">
          <Pill kind="due">Needs attention</Pill>
          <Body muted>{`${queue.failed.length} record${queue.failed.length === 1 ? '' : 's'} could not be saved: ${queue.failed[0]?.reason ?? ''}`}</Body>
        </Card>
      ) : null}
      <FlatList
        data={day?.rooms ?? []}
        keyExtractor={(r) => r.id}
        contentContainerStyle={{ gap: space.cardGap }}
        renderItem={({ item, index }) => {
          const count = present.get(item.id)?.size ?? 0;
          return (
            <Animated.View entering={FadeInDown.delay(index * 70).springify().damping(15)}>
              <Link href={{ pathname: '/room/[id]', params: { id: item.id } }} asChild>
                <View>
                  <Card wash={(['mist', 'mint', 'sand'] as const)[index % 3]}>
                    <Heading>{item.name}</Heading>
                    <Body muted>{`${count} present now`}</Body>
                    <Link href={{ pathname: '/room/[id]', params: { id: item.id } }} asChild>
                      <Button label={`Open ${item.name}`} kind="quiet" onPress={() => {}} />
                    </Link>
                  </Card>
                </View>
              </Link>
            </Animated.View>
          );
        }}
      />
      <View style={{ marginTop: 'auto', gap: space.sm }}>
        <Link href="/evacuation" asChild>
          <Button label="Evacuation screen" onPress={() => {}} />
        </Link>
        <Button label={enCA.auth.signOut} kind="quiet" onPress={() => supabase.auth.signOut()} />
      </View>
    </Screen>
  );
}
