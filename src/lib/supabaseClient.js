// =============================================================
// src/lib/supabaseClient.js
// =============================================================
// Single shared Supabase client instance for the entire app.
// Import this wherever you need to interact with Supabase.
//
// IMPORTANT: This uses the ANON key (safe for browsers).
// NEVER put the service-role key here.
// =============================================================

import { createClient } from '@supabase/supabase-js';

const supabaseUrl  = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Missing Supabase environment variables. ' +
    'Copy .env.example to .env and fill in your project URL and anon key.'
  );
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    // Persist the session in localStorage so the user stays logged in
    // across page refreshes.
    persistSession: true,
    autoRefreshToken: true,
  },
});

// ---------------------------------------------------------------
// Quick helper: get the currently authenticated user
// Returns null if not logged in.
// ---------------------------------------------------------------
export async function getCurrentUser() {
  const { data: { user } } = await supabase.auth.getUser();
  return user;
}

// ---------------------------------------------------------------
// Quick helper: get user session
// ---------------------------------------------------------------
export async function getSession() {
  const { data: { session } } = await supabase.auth.getSession();
  return session;
}
