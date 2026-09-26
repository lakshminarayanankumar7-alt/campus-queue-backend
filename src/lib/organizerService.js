// =============================================================
// src/lib/organizerService.js
// Campus Event Pulse — Organizer-specific operations
// =============================================================
// API Classification:
//   getOrganizerDashboard()  → B (RPC: get_organizer_dashboard)
//   getEventParticipants()   → B (RPC: get_event_participants)
// =============================================================

import { supabase } from './supabaseClient.js';
import { parseEventError } from './_errorParser.js';

// ---------------------------------------------------------------
// TYPE B — GET ORGANIZER DASHBOARD
// Returns summary stats and per-event counts for the organizer.
//
// Input:  none (uses auth.uid() inside PostgreSQL function)
// Output: {
//   data: {
//     organizer_id,
//     total_events, draft_events, published_events, closed_events,
//     total_registrations,
//     events: [
//       { event_id, title, category, event_date, status,
//         seat_limit, registered_count, available_seats }
//     ]
//   },
//   error
// }
// Auth:   Required
// Role:   organizer
// ---------------------------------------------------------------
export async function getOrganizerDashboard() {
  const { data, error } = await supabase
    .rpc('get_organizer_dashboard');

  if (error) return { data: null, error: parseEventError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE B — GET EVENT PARTICIPANTS (Organizer)
// Returns participant list for one of the organizer's events.
//
// Input:  { eventId }
// Output: {
//   data: {
//     event_id, event_title, seat_limit,
//     registered_count, available_seats,
//     participants: [
//       { registration_id, student_name, student_email,
//         status, registered_at }
//     ]
//   },
//   error
// }
// Auth:   Required
// Role:   organizer (own event only)
// Errors:
//   - ACCESS_DENIED (not owner of this event)
//   - EVENT_NOT_FOUND
// ---------------------------------------------------------------
export async function getEventParticipants({ eventId }) {
  const { data, error } = await supabase
    .rpc('get_event_participants', { p_event_id: eventId });

  if (error) return { data: null, error: parseEventError(error) };
  return { data, error: null };
}
