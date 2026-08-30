import { useCallback, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { Redirect, router, useFocusEffect } from 'expo-router';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Body, Button, Caption, Card, Heading, Pill, Screen, Title } from '@/ui/components';

interface Version {
  id: string;
  version: number;
  summary: string | null;
  published_at: string;
}

interface Section {
  section_key: string;
  ordinal: number;
  title: string;
  regulation: string;
  body: string;
}

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-CA', { day: 'numeric', month: 'long', year: 'numeric' });
}

/** s. 45: the handbook the centre must give you. Reading it here IS the copy —
 * the acknowledgement below is what lets the centre show you were given it. */
function HandbookInner() {
  const [version, setVersion] = useState<Version | null>(null);
  const [sections, setSections] = useState<Section[]>([]);
  const [acknowledged, setAcknowledged] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const refresh = useCallback(() => {
    supabase
      .from('handbook_version')
      .select('id, version, summary, published_at')
      .order('version', { ascending: false })
      .limit(1)
      .maybeSingle()
      .then(({ data }) => {
        const v = (data as Version | null) ?? null;
        setVersion(v);
        if (!v) return;
        supabase
          .from('handbook_version_section')
          .select('section_key, ordinal, title, regulation, body')
          .eq('handbook_version_id', v.id)
          .order('ordinal')
          .then(({ data: rows }) => setSections((rows as Section[]) ?? []));
        supabase
          .from('handbook_acknowledgement')
          .select('acknowledged_at')
          .eq('handbook_version_id', v.id)
          .maybeSingle()
          .then(({ data: ack }) => setAcknowledged((ack as { acknowledged_at: string } | null)?.acknowledged_at ?? null));
      });
  }, []);
  useFocusEffect(refresh);

  async function acknowledge() {
    if (!version) return;
    const { error } = await supabase.rpc('acknowledge_handbook', { p_version: version.id });
    setNotice(error ? error.message : 'Thank you — the centre knows you have it.');
    refresh();
  }

  return (
    <Screen>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
        <Title>Parent handbook</Title>
        <Button label="Back" kind="quiet" onPress={() => router.back()} />
      </View>
      <ScrollView contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}>
        {!version ? (
          <Card>
            <Body muted>Your centre has not published a handbook here yet.</Body>
          </Card>
        ) : (
          <>
            <Card wash={acknowledged ? 'mint' : 'sand'}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
                <Heading>{`Version ${version.version}`}</Heading>
                <Pill kind={acknowledged ? 'ok' : 'due'}>{acknowledged ? 'Read' : 'Please read'}</Pill>
              </View>
              <Caption>{`Issued ${fmtDate(version.published_at)}`}</Caption>
              {version.summary ? <Body>{version.summary}</Body> : null}
              {notice ? <Caption>{notice}</Caption> : null}
              {acknowledged ? (
                <Caption>{`You let the centre know on ${fmtDate(acknowledged)}.`}</Caption>
              ) : (
                <Button label="I have read this" onPress={() => void acknowledge()} />
              )}
            </Card>

            {sections.map((s) => (
              <Card key={s.section_key}>
                <Heading>{`${s.ordinal}. ${s.title}`}</Heading>
                <Caption>{s.regulation}</Caption>
                <Body>{s.body}</Body>
              </Card>
            ))}
          </>
        )}
      </ScrollView>
    </Screen>
  );
}

export default function Handbook() {
  const { session, loading } = useAuth();
  if (!loading && !session) return <Redirect href="/sign-in" />;
  return <HandbookInner />;
}
