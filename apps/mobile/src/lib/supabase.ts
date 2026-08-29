import { createClient } from '@supabase/supabase-js';
import { Platform } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';

const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;

// The anon key is public by design; RLS is the boundary. Real secrets never
// ship in EXPO_PUBLIC_* (build prompt §11).
if (!url || !anonKey) {
  throw new Error('Set EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY (see .env.example).');
}

export const supabase = createClient(url, anonKey, {
  auth: {
    // TODO(security): before any pilot, wrap AsyncStorage with an encryption
    // key held in expo-secure-store (SecureStore itself caps values at 2 KB,
    // smaller than a session payload).
    // On web (and the Node prerender of the web target) supabase-js picks its
    // own storage; AsyncStorage is native-only.
    ...(Platform.OS === 'web' ? {} : { storage: AsyncStorage }),
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});
