/**
 * Today's photos of one child, for the family Home card — and a full-screen
 * viewer.
 *
 * The list comes from family_photos, which asks the FAMILY question — would
 * this adult's family see this photo — rather than a plain select, whose RLS
 * answers the staff question for an adult who also works at the centre. The
 * storage policy has the same staff branch, so for a dual-role adult a signed
 * URL alone would not have kept a consent-withdrawn group photo off this screen.
 */

import { useEffect, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Image } from 'expo-image';
import { localDateISO } from '@tucked/domain';
import { colour, radius, space, type } from '@tucked/ui-tokens';
import { supabase } from '@/lib/supabase';
import { signedPhotoUrls } from '@/lib/photos';
import { Body, Button, Caption } from './components';

interface PhotoRow {
  id: string;
  storage_path: string;
  captured_at: string;
  caption: string | null;
}

function fmt12(iso: string, timeZone: string): string {
  return new Date(iso).toLocaleTimeString('en-CA', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone });
}

export function PhotoStrip({ childId, firstName, timeZone }: { childId: string; firstName: string; timeZone: string }) {
  const [photos, setPhotos] = useState<PhotoRow[]>([]);
  const [urls, setUrls] = useState<Map<string, string>>(new Map());
  const [open, setOpen] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const { data } = await supabase.rpc('family_photos', {
        p_child: childId,
        p_date: localDateISO(timeZone),
      });
      const rows = (data as PhotoRow[]) ?? [];
      const signed = await signedPhotoUrls(rows.map((p) => p.storage_path));
      if (cancelled) return;
      // a path the storage policy refused has no URL — and so is not shown
      setPhotos(rows.filter((p) => signed.has(p.storage_path)));
      setUrls(signed);
    })();
    return () => {
      cancelled = true;
    };
  }, [childId, timeZone]);

  if (photos.length === 0) return null;
  const current = open === null ? null : photos[open];

  return (
    <View style={styles.wrap}>
      <Text style={styles.overline}>{photos.length === 1 ? 'A PHOTO FROM TODAY' : `${photos.length} PHOTOS FROM TODAY`}</Text>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.row}>
        {photos.map((p, i) => (
          <Pressable
            key={p.id}
            accessibilityRole="imagebutton"
            accessibilityLabel={p.caption ?? `Photo of ${firstName} at ${fmt12(p.captured_at, timeZone)}`}
            onPress={() => setOpen(i)}
          >
            <Image source={{ uri: urls.get(p.storage_path) }} style={styles.thumb} contentFit="cover" transition={150} />
          </Pressable>
        ))}
      </ScrollView>

      <Modal visible={current !== null} animationType="fade" onRequestClose={() => setOpen(null)}>
        {current ? (
          <View style={styles.viewer}>
            <Image source={{ uri: urls.get(current.storage_path) }} style={styles.full} contentFit="contain" />
            <View style={styles.viewerFoot}>
              {current.caption ? <Body>{current.caption}</Body> : null}
              <Caption>{`${fmt12(current.captured_at, timeZone)} · ${open! + 1} of ${photos.length}`}</Caption>
              <View style={styles.viewerButtons}>
                <Button label="Previous" kind="quiet" onPress={() => setOpen((i) => (i! + photos.length - 1) % photos.length)} />
                <Button label="Next" kind="quiet" onPress={() => setOpen((i) => (i! + 1) % photos.length)} />
              </View>
              <Button label="Close" onPress={() => setOpen(null)} />
            </View>
          </View>
        ) : null}
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { gap: space.sm },
  overline: { ...type.overline, color: colour.slateMuted, textTransform: 'uppercase' } as const,
  row: { gap: space.sm },
  thumb: { width: 96, height: 96, borderRadius: radius.md, backgroundColor: colour.canvas },
  viewer: { flex: 1, backgroundColor: colour.ink },
  full: { flex: 1 },
  viewerFoot: { backgroundColor: colour.surface, padding: space.lg, gap: space.sm },
  viewerButtons: { flexDirection: 'row', gap: space.sm },
});
