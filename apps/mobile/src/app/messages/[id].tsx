import { useCallback, useState } from 'react';
import { FlatList, StyleSheet, Text, View } from 'react-native';
import { Redirect, router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { colour, radius, space, type } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { AUDIENCE_LABEL } from '../messages';
import { Button, Caption, Field, Screen, Title } from '@/ui/components';

interface Msg {
  id: string;
  body: string;
  sent_at: string;
  sender_person_id: string;
  sender: { full_name: string } | null;
}

interface ThreadInfo {
  id: string;
  centre_id: string;
  audience: 'teacher' | 'supervisor' | 'both';
  child: { full_name: string } | null;
}

export default function ThreadScreen() {
  const params = useLocalSearchParams<{ id: string }>();
  const { session, loading, profile } = useAuth();
  const [thread, setThread] = useState<ThreadInfo | null>(null);
  const [messages, setMessages] = useState<Msg[]>([]);
  const [body, setBody] = useState('');

  const refresh = useCallback(() => {
    supabase
      .from('message_thread')
      .select('id, centre_id, audience, child:child_id(full_name)')
      .eq('id', params.id)
      .maybeSingle()
      .then(({ data }) => setThread(data as never));
    supabase
      .from('message')
      .select('id, body, sent_at, sender_person_id, sender:sender_person_id(full_name)')
      .eq('thread_id', params.id)
      .order('sent_at')
      .then(({ data }) => setMessages((data as never) ?? []));
  }, [params.id]);
  useFocusEffect(refresh);

  async function send() {
    if (!profile || !thread || !body.trim()) return;
    const text = body.trim();
    setBody('');
    await supabase.from('message').insert({
      centre_id: thread.centre_id,
      thread_id: thread.id,
      sender_person_id: profile.personId,
      body: text,
    });
    refresh();
  }

  if (!loading && !session) return <Redirect href="/sign-in" />;

  return (
    <Screen>
      <View style={styles.header}>
        <Title>{thread?.child?.full_name.split(' ')[0] ?? 'Messages'}</Title>
        <Button label="Back" kind="quiet" onPress={() => router.back()} />
      </View>
      {thread ? <Caption>{AUDIENCE_LABEL[thread.audience]}</Caption> : null}
      <FlatList
        data={messages}
        keyExtractor={(m) => m.id}
        contentContainerStyle={{ gap: space.sm, paddingBottom: space.base }}
        renderItem={({ item }) => {
          const mine = item.sender_person_id === profile?.personId;
          return (
            <View style={[styles.bubble, mine ? styles.mine : styles.theirs]}>
              {!mine ? <Text style={styles.sender}>{item.sender?.full_name ?? 'The centre'}</Text> : null}
              <Text style={[styles.body, mine && styles.bodyMine]}>{item.body}</Text>
              <Text style={[styles.time, mine && styles.timeMine]}>
                {new Date(item.sent_at).toLocaleTimeString('en-CA', { hour: 'numeric', minute: '2-digit', hour12: true })}
              </Text>
            </View>
          );
        }}
      />
      <View style={styles.composer}>
        <View style={{ flex: 1 }}>
          <Field placeholder="Write a message" value={body} onChangeText={setBody} multiline />
        </View>
        <Button label="Send" onPress={() => void send()} />
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    gap: space.sm,
  },
  bubble: {
    maxWidth: '84%',
    borderRadius: radius.lg,
    padding: space.md,
    gap: 2,
  },
  mine: { alignSelf: 'flex-end', backgroundColor: colour.blue600 },
  theirs: { alignSelf: 'flex-start', backgroundColor: colour.surface },
  sender: { ...type.caption, color: colour.blue700 } as const,
  body: { ...type.body, color: colour.ink } as const,
  bodyMine: { color: colour.surface } as const,
  time: { ...type.caption, color: colour.slateMuted, alignSelf: 'flex-end' } as const,
  timeMine: { color: colour.blue100 } as const,
  composer: { flexDirection: 'row', gap: space.sm, alignItems: 'flex-end' },
});
