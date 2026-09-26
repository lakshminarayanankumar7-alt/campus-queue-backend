// =============================================================
// src/lib/registrationService.js
// Campus Event Pulse — Registration operations
// =============================================================
// API Classification:
//   registerForEvent()     → B (RPC: register_for_event) — concurrency-safe
//   cancelRegistration()   → B (RPC: cancel_registration)
//   getMyRegistrations()   → B (RPC: get_my_registrations)
// =============================================================

import { supabase } from './supabaseClient.js';
import { parseEventError } from './_errorParser.js';

// ---------------------------------------------------------------
// TYPE B — REGISTER FOR EVENT (Student)
// Concurrency-safe. Uses FOR UPDATE lock in PostgreSQL function.
//
// Input:  { eventId }
// Output: {
//   data: {
//     registration_id, event_id, event_title,
//     status, registered_at, available_seats
//   },
//   error
// }
// Auth:   Required
// Role:   student
// Errors:
//   - NOT_AUTHENTICATED
//   - ACCESS_DENIED (not student)
//   - EVENT_NOT_FOUND
//   - EVENT_NOT_PUBLISHED (draft)
//   - EVENT_CLOSED
//   - DUPLICATE_REGISTRATION (already registered)
//   - EVENT_FULL (no seats left)
// ---------------------------------------------------------------
export async function registerForEvent({ eventId }) {
  const { data, error } = await supabase
    .rpc('register_for_event', { p_event_id: eventId });

  if (error) return { data: null, error: parseEventError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE B — CANCEL REGISTRATION (Student)
//
// Input:  { registrationId }
// Output: { data: { registration_id, event_id, event_title, status }, error }
// Auth:   Required
// Role:   student (own registration only)
// Errors:
//   - REGISTRATION_NOT_FOUND
//   - ACCESS_DENIED (not own registration)
//   - INVALID_STATUS (already cancelled)
// ---------------------------------------------------------------
export async function cancelRegistration({ registrationId }) {
  const { data, error } = await supabase
    .rpc('cancel_registration', { p_registration_id: registrationId });

  if (error) return { data: null, error: parseEventError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE B — GET MY REGISTRATIONS (Student)
//
// Input:  { status? } — 'registered' | 'cancelled' | null (all)
// Output: { registrations: [...], error }
// Auth:   Required
// ---------------------------------------------------------------
export async function getMyRegistrations({ status } = {}) {
  const { data, error } = await supabase
    .rpc('get_my_registrations', { p_status: status ?? null });

  if (error) return { registrations: null, error: parseEventError(error) };
  return { registrations: data ?? [], error: null };
}
