// lib/supabase.ts — Supabase client for the mobile app
// We use the anon key here (safe for client-side) — RLS policies handle access control.
// URL polyfill is required because React Native doesn't have a native URL implementation.

import "react-native-url-polyfill/auto";
import { createClient } from "@supabase/supabase-js";

// These are the public-facing values — safe to include in the mobile bundle
const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL ?? "";
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? "";

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
