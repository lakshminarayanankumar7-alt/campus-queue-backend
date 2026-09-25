// =============================================================
// src/lib/authService.js
// =============================================================
// Authentication operations: register, login, logout, profile.
// All password handling is done by Supabase Auth — never stored here.
// =============================================================

import { supabase } from './supabaseClient.js';

// ---------------------------------------------------------------
// REGISTER — Create new account
//
// Input:  { name, email, password }
// Output: { user, session, error }
//
// What happens:
//   1. Supabase Auth creates auth.users record (hashed password)
//   2. The trigger handle_new_user() fires and creates profiles record
//   3. Role is set to 'student' by the trigger (cannot be overridden)
// ---------------------------------------------------------------
export async function registerUser({ name, email, password }) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { name }, // Passed to trigger via raw_user_meta_data
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
//
// Uses RLS: students see only their own profile.
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
//
// NOTE: Role cannot be changed through this function.
//       RLS policy prevents role modification by students.
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
//
// Usage:
//   const { data: { subscription } } = onAuthStateChange((event, session) => {
//     console.log(event, session);
//   });
//   // To clean up: subscription.unsubscribe();
// ---------------------------------------------------------------
export function onAuthStateChange(callback) {
  return supabase.auth.onAuthStateChange(callback);
}
