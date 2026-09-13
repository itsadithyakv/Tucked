import { useCallback, useState } from 'react';
import { ScrollView, View } from 'react-native';
import { Redirect, router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { space } from '@tucked/ui-tokens';
import { useAuth } from '@/lib/auth';
import { supabase } from '@/lib/supabase';
import { newPhotoId, pickPhoto } from '@/lib/photos';
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

/** Items where a family usually has a piece of paper to show: a photo of the
 * signed form goes onto the record itself, not just the answer "provided". */
const DOCUMENT_ITEMS = new Set([
  'application',
  'identity',
  'health_immunisation',
  'medication_instructions',
  'care_instructions',
]);

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
  const [centreId, setCentreId] = useState<string | null>(null);
  const [docCounts, setDocCounts] = useState<Map<string, number>>(new Map());
  const [uploading, setUploading] = useState(false);
  const [items, setItems] = useState<Map<string, { status: string }>>(new Map());
  const [consents, setConsents] = useState<Map<string, string>>(new Map());
  const [editing, setEditing] = useState<{ type: string; label: string } | null>(null);
  const [note, setNote] = useState('');
  const [allergies, setAllergies] = useState('');
  const [notice, setNotice] = useState<string | null>(null);

  const refresh = useCallback(() => {
    supabase
      .from('child')
      .select('full_name, centre_id')
      .eq('id', params.childId)
      .maybeSingle()
      .then(({ data }) => {
        setChildName(data?.full_name ?? '');
        setCentreId((data as { centre_id: string } | null)?.centre_id ?? null);
      });
    supabase
      .from('child_record_document')
      .select('item_type')
      .eq('child_id', params.childId)
      .is('superseded_at', null)
      .then(({ data }) => {
        const counts = new Map<string, number>();
        for (const d of (data as { item_type: string }[]) ?? []) {
          counts.set(d.item_type, (counts.get(d.item_type) ?? 0) + 1);
        }
        setDocCounts(counts);
      });
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

  /** A photo of the signed form, re-encoded on the phone (no location leaves
   * it) and filed on this item of the record. */
  async function addFormPhoto() {
    const target = editing;
    if (!target || !centreId) return;
    setUploading(true);
    try {
      const photo = await pickPhoto('camera');
      if (!photo) return;
      const path = `${centreId}/child/${params.childId}/${newPhotoId()}.jpg`;
      const bytes = Uint8Array.from(atob(photo.base64), (c) => c.charCodeAt(0));
      const { error: upErr } = await supabase.storage
        .from('evidence')
        .upload(path, bytes, { contentType: 'image/jpeg', upsert: false });
      if (upErr) {
        setNotice(/network|fetch|timed out/i.test(upErr.message)
          ? 'Adding a form needs a connection — try again when you are back online.'
          : upErr.message);
        return;
      }
      const { error } = await supabase.rpc('attach_record_document', {
        p_child: params.childId,
        p_item: target.type,
        p_storage_path: path,
        p_file_name: `${target.label}.jpg`,
        p_content_type: 'image/jpeg',
        p_size_bytes: photo.sizeBytes,
      });
      setNotice(error ? error.message : 'Photo of the form added to the record. The centre will check it.');
      refresh();
    } catch (e) {
      setNotice(e instanceof Error ? e.message : 'The photo could not be added.');
    } finally {
      setUploading(false);
    }
  }

  async function decide(consentType: string, label: string, status: 'granted' | 'declined') {
    const { error } = await supabase.rpc('give_consent', {
      p_child: params.childId,
      p_type: consentType,
      // what the family was actually asked — "enrolment" said nothing about
      // what they agreed to, which is the whole of informed consent
      p_purpose: label,
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
                  {docCounts.get(item.type) ? (
                    <Caption>
                      {docCounts.get(item.type) === 1
                        ? 'A document is on file'
                        : `${docCounts.get(item.type)} documents on file`}
                    </Caption>
                  ) : null}
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
                    onPress={() => void decide(c.type, c.label, 'granted')}
                  />
                </View>
                <View style={{ flex: 1 }}>
                  <Button
                    label="No"
                    kind={status === 'declined' ? 'primary' : 'quiet'}
                    onPress={() => void decide(c.type, c.label, 'declined')}
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
        {editing && DOCUMENT_ITEMS.has(editing.type) ? (
          <Button
            label={uploading ? 'Adding…' : 'Add a photo of the signed form'}
            kind="quiet"
            busy={uploading}
            onPress={() => void addFormPhoto()}
          />
        ) : null}
        <Button label="Provided" onPress={() => void saveItem('provided')} />
        <Button label="Not applicable" kind="quiet" onPress={() => void saveItem('not_applicable')} />
        <Button label="Prefer not to provide" kind="quiet" onPress={() => void saveItem('parent_declined')} />
      </Sheet>
    </Screen>
  );
}
