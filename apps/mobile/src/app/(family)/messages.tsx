import { useCallback, useState } from 'react';
import { FlatList, View } from 'react-native';
import { Link, router, useFocusEffect } from 'expo-router';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { AUDIENCE_LABEL, AUDIENCE_OPTIONS } from '@/lib/messaging';
import type { Audience } from '@/lib/messaging';
import { supabase } from '@/lib/supabase';
import { Body, Button, Caption, Card, Choices, Field, Heading, Screen, Sheet, Title } from '@/ui/components';

interface Thread {
  id: string;
  audience: Audience;
  created_at: string;
  child: { full_name: string } | null;
  message: { body: string; sent_at: string }[];
}

export default function Messages() {
  const { profile } = useAuth();
  const [threads, setThreads] = useState<Thread[]>([]);
  const [children, setChildren] = useState<{ id: string; full_name: string; centre_id: string }[]>([]);
  const [composerOpen, setComposerOpen] = useState(false);
  const [childId, setChildId] = useState<string | null>(null);
  const [audience, setAudience] = useState<Audience | null>(null);
  const [body, setBody] = useState('');

  const refresh = useCallback(() => {
    supabase
      .from('message_thread')
      .select('id, audience, created_at, child:child_id(full_name), message(body, sent_at)')
      .order('created_at', { ascending: false })
      .then(({ data }) => setThreads((data as never) ?? []));
    supabase
      .from('child')
      .select('id, full_name, centre_id')
      .order('full_name')
      .then(({ data }) => setChildren(data ?? []));
  }, []);
  useFocusEffect(refresh);

  async function send() {
    if (!profile || !childId || !audience || !body.trim()) return;
    const child = children.find((c) => c.id === childId);
    if (!child) return;
    setComposerOpen(false);
    const { data: thread } = await supabase
      .from('message_thread')
      .insert({ centre_id: child.centre_id, child_id: childId, audience, created_by: profile.personId })
      .select('id')
      .single();
    if (thread) {
      await supabase
        .from('message')
        .insert({ centre_id: child.centre_id, thread_id: thread.id, sender_person_id: profile.personId, body: body.trim() });
      setBody('');
      refresh();
      setTimeout(() => {
        router.push({ pathname: '/messages/[id]', params: { id: thread.id } });
      }, 250);
    }
  }

  return (
    <Screen>
      <Title>Messages</Title>
      <Button
        label="New message"
        onPress={() => {
          setChildId(children.length === 1 ? children[0]!.id : null);
          setAudience(null);
          setBody('');
          setComposerOpen(true);
        }}
      />
      <FlatList
        data={threads}
        keyExtractor={(t) => t.id}
        contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}
        renderItem={({ item }) => {
          const last = [...item.message].sort((a, b) => a.sent_at.localeCompare(b.sent_at)).at(-1);
          return (
            <Link href={{ pathname: '/messages/[id]', params: { id: item.id } }} asChild>
              <View>
                <Card>
                  <Heading>{item.child?.full_name.split(' ')[0] ?? 'Message'}</Heading>
                  <Caption>{AUDIENCE_LABEL[item.audience]}</Caption>
                  {last ? <Body muted>{last.body}</Body> : null}
                </Card>
              </View>
            </Link>
          );
        }}
        ListEmptyComponent={
          <Card>
            <Body muted>No messages yet. Anything you send shows exactly who will read it.</Body>
          </Card>
        }
      />

      <Sheet visible={composerOpen} onClose={() => setComposerOpen(false)} title="New message">
        {children.length > 1 ? (
          <Choices
            options={children.map((c) => ({ value: c.id, label: c.full_name.split(' ')[0]! }))}
            value={childId}
            onChange={setChildId}
          />
        ) : null}
        <Body muted>Who should read it?</Body>
        <Choices options={[...AUDIENCE_OPTIONS]} value={audience} onChange={setAudience} />
        <Field placeholder="Your message" value={body} onChangeText={setBody} multiline />
        <Button label="Send" onPress={() => void send()} />
        <Button label="Cancel" kind="quiet" onPress={() => setComposerOpen(false)} />
      </Sheet>
    </Screen>
  );
}
