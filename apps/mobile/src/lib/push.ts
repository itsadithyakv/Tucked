/**
 * Device push registration. Quietly does nothing on web or in Expo Go (remote
 * push needs the dev build); on a real build it registers the Expo token and
 * creates the two Android channels the product promise depends on:
 * Now = loud and time-sensitive, Later = silent.
 */

import { Platform } from 'react-native';
import Constants from 'expo-constants';
import { supabase } from './supabase';

export async function registerForPush(personId: string): Promise<void> {
  if (Platform.OS === 'web') return;
  try {
    const Notifications = await import('expo-notifications');

    if (Platform.OS === 'android') {
      // MAX importance plays the system default sound; naming a sound here
      // means a bundled custom file, which we don't ship.
      await Notifications.setNotificationChannelAsync('now', {
        name: 'Now — urgent',
        importance: Notifications.AndroidImportance.MAX,
        bypassDnd: true,
      });
      await Notifications.setNotificationChannelAsync('later', {
        name: 'Later — the daily story',
        importance: Notifications.AndroidImportance.LOW,
      });
    }

    const perms = await Notifications.requestPermissionsAsync();
    if (perms.status !== 'granted') return;

    const projectId: string | undefined =
      (Constants.expoConfig?.extra as { eas?: { projectId?: string } } | undefined)?.eas?.projectId ??
      Constants.easConfig?.projectId ??
      undefined;
    const token = (await Notifications.getExpoPushTokenAsync(projectId ? { projectId } : undefined))
      .data;

    await supabase
      .from('device_push_token')
      .upsert({ person_id: personId, token, platform: Platform.OS }, { onConflict: 'token' });
  } catch {
    // Expo Go, simulator without push, or denied permissions — in-app delivery
    // still works; real push arrives with the EAS dev build.
  }
}
