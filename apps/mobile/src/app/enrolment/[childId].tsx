import { useCallback, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { Redirect, router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { Body, Button, Caption, Card, Field, Heading, Pill, Screen, Sheet, Title } from '@/ui/components';

/** The parent completes the s. 72(1) children's record from home — every item
 * answered as provided, not applicable, or "prefer not to provide"; NEVER left
 * blank. Optional consents are clearly optional: declining them all still
 * completes enrolment (s. 73), and the supervisor verifies at the end. */

const ITEMS: { type: string; label: string; hint?: string }[] = [
  { type: 'application', label: 'Signed application for enrolment' },
  { type: 'identity', label: 'Name, date of birth, home address' },
  { type: 'parent_contacts', label: 'Parents’ names, addresses and phone numbers' },
  { type: 'emergency_contact', label: 'An emergency contact we can reach during care hours' },
  { type: 'release_persons', label: 'People your child may be released to' },
  { type: 'admission', label: 'Date of admission' },
  { type: 'discharge', label: 'Date of discharge', hint: 'Not applicable while enrolled' },
  {
    type: 'health_immunisation',
    label: 'Health history, conditions, allergies and immunisation',
    hint: 'Allergies listed here appear on the room’s evacuation screen',
  },
  { type: 'symptoms_log', label: 'Ongoing symptoms log', hint: 'The centre records this day to day' },
  { type: 'medication_instructions', label: 'Medication instructions (if any)' },
  { type: 'care_instructions', label: 'Diet, rest or physical activity instructions' },
];

const CONSENTS: { type: string; label: string; required?: boolean }[] = [
  { type: 'care_required', label: 'Information needed to care for your child', required: true },
  { type: 'photo_internal', label: 'Photos shared with you in the app' },
  { type: 'photo_group', label: 'Your child appearing in group photos' },
  { type: 'photo_third_party', label: 'Photos shared outside the centre' },
  { type: 'social_media', label: 'Photos on social media' },
  { type: 'sunscreen_blanket', label: 'Sunscreen (blanket consent)' },
  { type: 'diaper_cream_blanket', label: 'Diaper cream (blanket consent)' },
  { type: 'data_sharing_professional', label: 'Sharing information with outside professionals' },
];

export default function EnrolmentScreen() {
  const params = useLocalSearchParams<{ childId: string }>();
  const { session, loading } = useAuth();
  const [childName, setChildName] = useState('');
  const [items, setItems] = useState<Map<string, { status: string }>>(new Map());
  const [consents, setConsents] = useState<Map<string, string>>(new Map());
  const [editing, setEditing] = useState<{ type: string; label: string } | null>(null);
  const [note, setNote] = useState('');
  const [allergies, setAllergies] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const refresh = useCallback(() => {
    supabase
      .from('child')
      .select('full_name')
      .eq('id', params.childId)
      .maybeSingle()
      .then(({ data }) => setChildName(data?.full_name ?? ''));
    supabase
      .from('child_record_item')
      .select('item_type, status')
      .eq('child_id', params.childId)
      .then(({ data }) => setItems(new Map((data ?? []).map((i) => [i.item_type, { status: i.status }]))));
    supabase
      .from('consent')
      .select('consent_type, status')
      .eq('child_id', params.childId)
      .is('revoked_at', null)
      .then(({ data }) => setConsents(new Map((data ?? []).map((c) => [c.consent_type, c.status]))));
  }, [params.childId]);
  useFocusEffect(refresh);

  async function saveItem(status: 'provided' | 'not_applicable' | 'parent_declined') {
    const target = editing;
    setEditing(null);
    if (!target) return;
    const content: Record<string, unknown> = {};
    if (note.trim()) content.note = note.trim();
    if (target.type === 'health_immunisation' && allergies.trim()) {
      content.allergies = allergies.split(',').map((a) => a.trim()).filter(Boolean);
    }
    const { error } = await supabase.rpc('complete_record_item', {
      p_child: params.childId,
      p_item: target.type,
      p_status: status,
      p_content: content,
    });
    setNotice(error ? error.message : null);
    refresh();
  }

  async function decide(consentType: string, status: 'granted' | 'declined') {
    const { error } = await supabase.rpc('give_consent', {
      p_child: params.childId,
      p_type: consentType,
      p_purpose: 'enrolment',
      p_status: status,
    });
    setNotice(error ? error.message : null);
    refresh();
  }

  if (!loading && !session) return <Redirect href="/sign-in" />;

  const answered = ITEMS.filter((i) => {
    const s = items.get(i.type)?.status;
    return s && s !== 'missing';
  }).length;

  return (
    <Screen>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
        <Title>{childName.split(' ')[0] || 'Enrolment'}</Title>
        <Button label="Back" kind="quiet" onPress={() => router.back()} />
      </View>
      <ScrollView contentContainerStyle={{ gap: space.cardGap, paddingBottom: space.x2l }}>
        <Card wash={answered === ITEMS.length ? 'mint' : 'mist'}>
          <Heading>{`${answered} of ${ITEMS.length} record items answered`}</Heading>
          <Caption>
            Every item needs an answer — “not applicable” and “prefer not to provide” count. The
            supervisor verifies the record once it is complete.
          </Caption>
        </Card>
        {notice ? (
          <Card wash="sand">
            <Body muted>{notice}</Body>
          </Card>
        ) : null}

        {ITEMS.map((item) => {
          const status = items.get(item.type)?.status ?? 'missing';
          return (
            <Card key={item.type}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
                <View style={{ flex: 1 }}>
                  <Body>{item.label}</Body>
                  {item.hint ? <Caption>{item.hint}</Caption> : null}
                </View>
                <Pill kind={status === 'missing' ? 'due' : 'ok'}>
                  {status === 'missing' ? 'Needed' : status.replace(/_/g, ' ')}
                </Pill>
              </View>
              <Button
                label={status === 'missing' ? 'Answer' : 'Change answer'}
                kind="quiet"
                onPress={() => {
                  setNote('');
                  setAllergies('');
                  setEditing(item);
                }}
              />
            </Card>
          );
        })}

        <Heading>Consents</Heading>
        <Caption>
          Only the first one is needed for care. Everything else is optional — declining any of
          them never affects enrolment.
        </Caption>
        {CONSENTS.map((c) => {
          const status = consents.get(c.type);
          return (
            <Card key={c.type}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: space.sm }}>
                <View style={{ flex: 1 }}>
                  <Body>{c.label}</Body>
                  {c.required ? <Caption>Required for care</Caption> : <Caption>Optional</Caption>}
                </View>
                {status ? <Pill kind={status === 'granted' ? 'ok' : 'due'}>{status}</Pill> : null}
              </View>
              <View style={{ flexDirection: 'row', gap: space.sm }}>
                <View style={{ flex: 1 }}>
                  <Button
                    label="Yes"
                    kind={status === 'granted' ? 'primary' : 'quiet'}
                    onPress={() => void decide(c.type, 'granted')}
                  />
                </View>
                <View style={{ flex: 1 }}>
                  <Button
                    label="No"
                    kind={status === 'declined' ? 'primary' : 'quiet'}
                    onPress={() => void decide(c.type, 'declined')}
                  />
                </View>
              </View>
            </Card>
          );
        })}
      </ScrollView>

      <Sheet
        visible={editing !== null}
        onClose={() => setEditing(null)}
        title={editing?.label ?? ''}
      >
        {editing?.type === 'health_immunisation' ? (
          <Field
            placeholder="Allergies, separated by commas (leave empty if none)"
            value={allergies}
            onChangeText={setAllergies}
          />
        ) : null}
        <Field placeholder="Details (optional)" value={note} onChangeText={setNote} />
        <Button label="Provided" onPress={() => void saveItem('provided')} />
        <Button label="Not applicable" kind="quiet" onPress={() => void saveItem('not_applicable')} />
        <Button label="Prefer not to provide" kind="quiet" onPress={() => void saveItem('parent_declined')} />
      </Sheet>
    </Screen>
  );
}
