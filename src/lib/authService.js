// =============================================================
// src/lib/authService.js  (EXTENDED for Campus Event Pulse)
// =============================================================
// Extends the existing authService to support 'organizer' role signup.
// All existing functions are preserved unchanged.
// New additions:
//   - registerOrganizer()
// =============================================================

import { supabase } from './supabaseClient.js';

// ---------------------------------------------------------------
// REGISTER STUDENT — Create student account
// Role is set server-side by trigger (always 'student').
//
// Input:  { name, email, password }
// Output: { user, session, error }
// ---------------------------------------------------------------
export async function registerUser({ name, email, password }) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { name, role: 'student' },
    },
  });

  if (error) return { user: null, session: null, error };
  return { user: data.user, session: data.session, error: null };
}

// ---------------------------------------------------------------
// REGISTER ORGANIZER — Create organizer account
// Role is set server-side by the updated trigger (migration 006).
// Passing role: 'organizer' in metadata; trigger validates it.
//
// Input:  { name, email, password }
// Output: { user, session, error }
// ---------------------------------------------------------------
export async function registerOrganizer({ name, email, password }) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { name, role: 'organizer' },
    },
  });

  if (error) return { user: null, session: null, error };
  return { user: data.user, session: data.session, error: null };
}

// ---------------------------------------------------------------
// LOGIN — Sign in with email + password
//
// Input:  { email, password }
// Output: { user, session, error }
// ---------------------------------------------------------------
export async function loginUser({ email, password }) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error) return { user: null, session: null, error };
  return { user: data.user, session: data.session, error: null };
}

// ---------------------------------------------------------------
// LOGOUT — End session
//
// Output: { error }
// ---------------------------------------------------------------
export async function logoutUser() {
  const { error } = await supabase.auth.signOut();
  return { error };
}

// ---------------------------------------------------------------
// GET PROFILE — Fetch profile for the currently logged-in user
//
// Output: { profile: { id, name, email, role, created_at }, error }
// ---------------------------------------------------------------
export async function getMyProfile() {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .single();

  if (error) return { profile: null, error };
  return { profile: data, error: null };
}

// ---------------------------------------------------------------
// UPDATE PROFILE NAME — Update the logged-in user's display name
//
// Input:  { name }
// Output: { profile, error }
// NOTE: Role cannot be changed through this function.
// ---------------------------------------------------------------
export async function updateMyName({ name }) {
  const { data, error } = await supabase
    .from('profiles')
    .update({ name })
    .eq('id', (await supabase.auth.getUser()).data.user?.id)
    .select()
    .single();

  if (error) return { profile: null, error };
  return { profile: data, error: null };
}

// ---------------------------------------------------------------
// ON AUTH STATE CHANGE — Subscribe to login/logout events
// ---------------------------------------------------------------
export function onAuthStateChange(callback) {
  return supabase.auth.onAuthStateChange(callback);
}
