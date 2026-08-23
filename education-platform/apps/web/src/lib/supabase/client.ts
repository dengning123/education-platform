"use client";

import { createBrowserClient } from "@supabase/ssr";
import type { SupabaseClient } from "@supabase/supabase-js";

import { getPublicSupabaseConfig } from "@/lib/supabase/config";

let browserClient: SupabaseClient | null = null;

export function createClient(): SupabaseClient {
  if (browserClient) return browserClient;

  const config = getPublicSupabaseConfig();
  browserClient = createBrowserClient(config.url, config.publishableKey);
  return browserClient;
}
