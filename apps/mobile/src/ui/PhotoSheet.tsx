/**
 * The room's photo sheet: take or choose, say who is in it, save.
 *
 * The tagging list comes from photo_consent_for_room, so an educator sees which
 * families have agreed BEFORE the shutter rather than after the upload. The
 * database still has the final word (record_photo): siblings may appear
 * together even if their family declined group photos, which this screen cannot
 * know, so it warns rather than forbids — and relays the refusal by name if the
 * write says no.
 */

import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Image } from 'expo-image';
import { colour, radius, space, type } from '@tucked/ui-tokens';
import { supabase } from '@/lib/supabase';
import { pickPhoto, uploadAndRecordPhoto } from '@/lib/photos';
import type { PhotoSource, PreparedPhoto } from '@/lib/photos';
import { Body, Button, Caption, Field, Sheet } from './components';

interface ConsentRow {
  child_id: string;
  full_name: string;
  photos_ok: boolean;
  group_ok: boolean;
}

export function PhotoSheet({
  visible,
  onClose,
  centreId,
  roomId,
  childId,
  getRecorder,
  onDone,
}: {
  visible: boolean;
  onClose: () => void;
  centreId: string;
  roomId: string;
  /** the child whose card the educator tapped — tagged to start with */
  childId: string | null;
  getRecorder: () => Promise<{ personId: string; pin: string } | null>;
  onDone: (message: string) => void;
}) {
  const [consent, setConsent] = useState<ConsentRow[]>([]);
  const [photo, setPhoto] = useState<PreparedPhoto | null>(null);
  const [tagged, setTagged] = useState<Set<string>>(new Set());
  const [caption, setCaption] = useState('');
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);

  useEffect(() => {
    if (!visible) return;
    setPhoto(null);
    setCaption('');
    setProblem(null);
    setTagged(new Set(childId ? [childId] : []));
    supabase
      .rpc('photo_consent_for_room', { p_room: roomId })
      .then(({ data }) => setConsent((data as ConsentRow[]) ?? []));
  }, [visible, roomId, childId]);

  const first = consent.find((c) => c.child_id === childId);
  const firstName = (id: string) => consent.find((c) => c.child_id === id)?.full_name.split(' ')[0] ?? '';
  const group = tagged.size > 1;
  const notInGroups = [...tagged].filter((id) => consent.find((c) => c.child_id === id)?.group_ok === false);

  async function take(source: PhotoSource) {
    setProblem(null);
    try {
      const prepared = await pickPhoto(source);
      if (prepared) setPhoto(prepared);
    } catch (e) {
      setProblem(e instanceof Error ? e.message : 'The photo could not be taken.');
    }
  }

  function toggle(row: ConsentRow) {
    if (!row.photos_ok) return;
    setTagged((prev) => {
      const next = new Set(prev);
      if (next.has(row.child_id)) next.delete(row.child_id);
      else next.add(row.child_id);
      return next;
    });
  }

  async function save() {
    if (!photo || tagged.size === 0) return;
    const recorder = await getRecorder();
    if (!recorder) return;
    setBusy(true);
    const result = await uploadAndRecordPhoto({
      centreId,
      subjects: [...tagged],
      photo,
      caption: caption.trim() || null,
      recorder,
    });
    setBusy(false);
    if (!result.ok) {
      // keep the photo in hand: a refused tag or a dropped connection should
      // not cost the educator the moment they caught
      setProblem(result.error);
      return;
    }
    const names = [...tagged].map(firstName).filter(Boolean);
    onDone(
      names.length === 1
        ? `Photo saved to ${names[0]}'s day.`
        : `Photo saved to ${names.slice(0, -1).join(', ')} and ${names[names.length - 1]}'s days.`,
    );
    onClose();
  }

  // The tapped child's family has not agreed to photos at all: say so first,
  // before anyone opens a camera.
  if (visible && first && !first.photos_ok) {
    return (
      <Sheet visible={visible} onClose={onClose} title="Photo">
        <Body>{`${first.full_name.split(' ')[0]}'s family has not agreed to photos in the app.`}</Body>
        <Caption>
          No photo of this child can be saved or shared. Families choose this during enrolment and can
          change it in the app.
        </Caption>
        <Button label="Close" kind="quiet" onPress={onClose} />
      </Sheet>
    );
  }

  return (
    <Sheet visible={visible} onClose={onClose} title={photo ? 'Who is in it?' : 'Photo'}>
      {!photo ? (
        <>
          <Button label="Take a photo" onPress={() => void take('camera')} />
          <Button label="Choose from this device" kind="quiet" onPress={() => void take('library')} />
          <Caption>Location and camera details are removed before the photo leaves this device.</Caption>
        </>
      ) : (
        <>
          <Image source={{ uri: photo.uri }} style={styles.preview} contentFit="cover" />
          <View style={styles.chips}>
            {consent.map((row) => {
              const on = tagged.has(row.child_id);
              return (
                <Pressable
                  key={row.child_id}
                  accessibilityRole="checkbox"
                  accessibilityState={{ checked: on, disabled: !row.photos_ok }}
                  accessibilityLabel={
                    row.photos_ok ? row.full_name : `${row.full_name} — family has not agreed to photos`
                  }
                  onPress={() => toggle(row)}
                  style={[styles.chip, on && styles.chipOn, !row.photos_ok && styles.chipOff]}
                >
                  <Text style={[styles.chipText, on && styles.chipTextOn, !row.photos_ok && styles.chipTextOff]}>
                    {row.full_name.split(' ')[0]}
                    {row.photos_ok ? '' : ' · no photos'}
                  </Text>
                </Pressable>
              );
            })}
          </View>
          {group && notInGroups.length > 0 ? (
            <Caption>
              {`${notInGroups.map(firstName).join(' and ')}'s family ${notInGroups.length === 1 ? 'has' : 'have'} not agreed to group photos. Siblings together are fine; with other children, leave them out.`}
            </Caption>
          ) : null}
          <Field
            placeholder="A few words (optional)"
            value={caption}
            onChangeText={setCaption}
            autoCapitalize="sentences"
            maxLength={280}
          />
          <Button
            label={tagged.size === 0 ? 'Tag at least one child' : 'Save photo'}
            busy={busy}
            onPress={() => void save()}
          />
          <Button label="Take another instead" kind="quiet" onPress={() => setPhoto(null)} />
        </>
      )}
      {problem ? <Body muted>{problem}</Body> : null}
    </Sheet>
  );
}

const styles = StyleSheet.create({
  preview: {
    width: '100%',
    aspectRatio: 4 / 3,
    borderRadius: radius.lg,
    backgroundColor: colour.canvas,
  },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: space.sm },
  chip: {
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: colour.line,
    backgroundColor: colour.surface,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    minHeight: 40,
    justifyContent: 'center',
  },
  chipOn: { backgroundColor: colour.blue50, borderColor: colour.blue600 },
  chipOff: { opacity: 0.55 },
  chipText: { ...type.label, color: colour.slate } as const,
  chipTextOn: { color: colour.blue700 },
  chipTextOff: { color: colour.slateMuted },
});
