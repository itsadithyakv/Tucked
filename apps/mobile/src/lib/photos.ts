/**
 * Photos: capture, re-encode, upload, record — and signed URLs to read them.
 *
 * Three rules from references/01 §8 and migration 0041 live here, on the device,
 * because this is the only place they can:
 *
 *   RE-ENCODE EVERY PHOTO. Resized to a 2560 px long edge at ~0.85 JPEG. The
 *   re-encode writes pixels into a new file and carries no EXIF across, so a
 *   phone's GPS coordinates never leave the building. The bucket accepts
 *   image/jpeg only, so a raw HEIC cannot skip this step.
 *
 *   KEEP THE CAPTURE TIME, AS DATA. It is read from the original's EXIF before
 *   the re-encode drops it, and sent to record_photo — the "dated photos"
 *   promise survives even though the metadata does not.
 *
 *   UPLOAD, THEN RECORD. The path is derived from an id the device makes, so the
 *   bytes can land before the row exists; record_photo refuses to write a row
 *   that points at nothing.
 *
 * Not queued offline: a photo is bytes, and the command queue carries commands.
 */

import * as ImagePicker from 'expo-image-picker';
import { ImageManipulator, SaveFormat } from 'expo-image-manipulator';
import { supabase } from './supabase';

/** Long edge of every stored photo — zoomable, printable at 8×10, under 1 MB. */
export const PHOTO_LONG_EDGE = 2560;
export const PHOTO_QUALITY = 0.85;

export type PhotoSource = 'camera' | 'library';

export interface PreparedPhoto {
  uri: string;
  width: number;
  height: number;
  base64: string;
  sizeBytes: number;
  capturedAt: string;
}

/**
 * A v4-shaped id. Deliberately not cryptographic: it names a storage path, and
 * the storage policy — not the obscurity of the id — decides who may read it.
 */
export function newPhotoId(): string {
  const hex = '0123456789abcdef';
  let out = '';
  for (let i = 0; i < 36; i += 1) {
    if (i === 8 || i === 13 || i === 18 || i === 23) out += '-';
    else if (i === 14) out += '4';
    else if (i === 19) out += hex[(Math.random() * 4) | 8];
    else out += hex[(Math.random() * 16) | 0];
  }
  return out;
}

/** EXIF "2026:09:13 14:20:05" is the camera's local wall clock — this device's. */
function captureTime(exif: Record<string, unknown> | null | undefined): string {
  const raw = (exif?.DateTimeOriginal ?? exif?.DateTime) as string | undefined;
  const m = typeof raw === 'string' ? raw.match(/^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/) : null;
  const now = Date.now();
  if (!m) return new Date(now).toISOString();
  const taken = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]));
  // a camera with a wrong clock must not produce a photo "taken tomorrow" —
  // record_photo refuses those, and rightly
  return Number.isNaN(taken.getTime()) || taken.getTime() > now ? new Date(now).toISOString() : taken.toISOString();
}

export async function pickPhoto(source: PhotoSource): Promise<PreparedPhoto | null> {
  const permission =
    source === 'camera'
      ? await ImagePicker.requestCameraPermissionsAsync()
      : await ImagePicker.requestMediaLibraryPermissionsAsync();
  if (!permission.granted) {
    throw new Error(
      source === 'camera'
        ? 'Camera access is turned off for Tucked. Turn it on in Settings to take photos.'
        : 'Photo access is turned off for Tucked. Turn it on in Settings to choose a photo.',
    );
  }

  const options: ImagePicker.ImagePickerOptions = {
    mediaTypes: ['images'],
    quality: 1,
    exif: true,
    allowsMultipleSelection: false,
  };
  const result =
    source === 'camera'
      ? await ImagePicker.launchCameraAsync(options)
      : await ImagePicker.launchImageLibraryAsync(options);
  if (result.canceled || result.assets.length === 0) return null;
  const asset = result.assets[0]!;
  const capturedAt = captureTime(asset.exif);

  const context = ImageManipulator.manipulate(asset.uri);
  if (Math.max(asset.width, asset.height) > PHOTO_LONG_EDGE) {
    context.resize(asset.width >= asset.height ? { width: PHOTO_LONG_EDGE } : { height: PHOTO_LONG_EDGE });
  }
  const rendered = await context.renderAsync();
  const saved = await rendered.saveAsync({ compress: PHOTO_QUALITY, format: SaveFormat.JPEG, base64: true });
  if (!saved.base64) throw new Error('The photo could not be prepared. Try again.');

  return {
    uri: saved.uri,
    width: saved.width,
    height: saved.height,
    base64: saved.base64,
    // base64 carries 3 bytes per 4 characters, less padding
    sizeBytes: Math.floor((saved.base64.length * 3) / 4) - (saved.base64.endsWith('==') ? 2 : saved.base64.endsWith('=') ? 1 : 0),
    capturedAt,
  };
}

function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

export type RecordResult = { ok: true; photoId: string } | { ok: false; error: string };

export async function uploadAndRecordPhoto(input: {
  centreId: string;
  subjects: string[];
  photo: PreparedPhoto;
  caption: string | null;
  recorder: { personId: string; pin: string };
}): Promise<RecordResult> {
  const photoId = newPhotoId();
  const path = `${input.centreId}/p/${photoId}/full.jpg`;

  const { error: uploadError } = await supabase.storage
    .from('photos')
    .upload(path, base64ToBytes(input.photo.base64), { contentType: 'image/jpeg', upsert: false });
  if (uploadError) {
    return {
      ok: false,
      error: /network|fetch|timed out/i.test(uploadError.message)
        ? 'Photos need a connection. This one is still here — try again when you are back online.'
        : uploadError.message,
    };
  }

  const { error } = await supabase.rpc('record_photo', {
    p_centre: input.centreId,
    p_photo: photoId,
    p_subjects: input.subjects,
    p_captured_at: input.photo.capturedAt,
    p_width: input.photo.width,
    p_height: input.photo.height,
    p_size_bytes: input.photo.sizeBytes,
    p_caption: input.caption,
    p_recorder: input.recorder.personId,
    p_pin: input.recorder.pin,
  });
  if (error) return { ok: false, error: error.message };
  return { ok: true, photoId };
}

/**
 * Short-lived URLs for the photos this viewer may open. The storage policy
 * re-checks every path, so a path this viewer may not see simply comes back
 * without a URL — no screen has to know the consent rules to be safe.
 */
export async function signedPhotoUrls(paths: string[], seconds = 3600): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  if (paths.length === 0) return out;
  const { data } = await supabase.storage.from('photos').createSignedUrls(paths, seconds);
  for (const row of data ?? []) {
    if (row.signedUrl && row.path) out.set(row.path, row.signedUrl);
  }
  return out;
}
