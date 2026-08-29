'use client';

import { createClient } from '@supabase/supabase-js';
import type { SupabaseClient } from '@supabase/supabase-js';

let client: SupabaseClient | null = null;

/**
 * Lazy browser client so importing this module never throws during Next's
 * build-time prerender (client components still render on the server). Called
 * only from effects and event handlers. The console moves to cookie-based auth
 * (@supabase/ssr) when server-rendered pages arrive in Phase 1.
 */
export function getSupabase(): SupabaseClient {
  if (!client) {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    if (!url || !anonKey) {
      throw new Error(
        'Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY (see .env.example).',
      );
    }
    client = createClient(url, anonKey);
  }
  return client;
}
