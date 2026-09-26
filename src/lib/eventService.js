// =============================================================
// src/lib/eventService.js
// Campus Event Pulse — Event operations
// =============================================================
// API Classification:
//   getPublishedEvents()    → B (RPC: get_published_events)
//   getEventDetails()       → B (RPC: get_event_details)
//   createEvent()           → B (RPC: create_event)
//   updateEvent()           → B (RPC: update_event)
//   publishEvent()          → B (RPC: publish_event)
//   closeEvent()            → B (RPC: close_event)
//   getMyEvents()           → A (direct SDK — organizer's own events)
// =============================================================

import { supabase } from './supabaseClient.js';
import { parseEventError } from './_errorParser.js';

// ---------------------------------------------------------------
// TYPE B — GET PUBLISHED EVENTS (Student browse)
//
// Input:  {
//   category?:   'Technical'|'Cultural'|'Sports'|'Workshop'|'Seminar'|'Club'|'Other'
//   dateFilter?: 'today'|'upcoming'|'this_week'
//   dateFrom?:   ISO string
//   dateTo?:     ISO string
// }
// Output: { events: [...], error }
// Auth:   Required
// ---------------------------------------------------------------
export async function getPublishedEvents({
  category   = null,
  dateFilter = null,
  dateFrom   = null,
  dateTo     = null,
} = {}) {
  const { data, error } = await supabase.rpc('get_published_events', {
    p_category:    category,
    p_date_filter: dateFilter,
    p_date_from:   dateFrom,
    p_date_to:     dateTo,
  });

  if (error) return { events: null, error: parseEventError(error) };
  return { events: data ?? [], error: null };
}

// ---------------------------------------------------------------
// TYPE B — GET EVENT DETAILS
// Returns event + seat counts + caller's registration status.
//
// Input:  { eventId }
// Output: {
//   data: {
//     event_id, title, description, category, event_date, venue,
//     status, seat_limit, registered_count, available_seats,
//     organizer_name, my_registration, created_at, updated_at
//   },
//   error
// }
// Auth:   Required
// Role:   Student (published only) | Organizer (own events any status)
// ---------------------------------------------------------------
export async function getEventDetails({ eventId }) {
  const { data, error } = await supabase
    .rpc('get_event_details', { p_event_id: eventId });

  if (error) return { data: null, error: parseEventError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE B — CREATE EVENT (Organizer)
//
// Input:  { title, description, category, eventDate, venue, seatLimit }
// Output: { data: { event_id, title, status, ... }, error }
// Auth:   Required
// Role:   organizer
// Errors:
//   - NOT_AUTHENTICATED
//   - ACCESS_DENIED (not organizer)
//   - VALIDATION_ERROR (empty fields, invalid category/date/seatLimit)
// ---------------------------------------------------------------
export async function createEvent({ title, description, category, eventDate, venue, seatLimit }) {
  const { data, error } = await supabase.rpc('create_event', {
    p_title:       title,
    p_description: description,
    p_category:    category,
    p_event_date:  eventDate,
    p_venue:       venue,
    p_seat_limit:  seatLimit,
  });

  if (error) return { data: null, error: parseEventError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE B — UPDATE EVENT (Organizer, partial patch)
//
// Input:  { eventId, title?, description?, category?, eventDate?, venue?, seatLimit? }
// Output: { data: { event_id, title, status, updated_at, ... }, error }
// Auth:   Required
// Role:   organizer (own event only)
// Errors:
//   - EVENT_NOT_FOUND
//   - ACCESS_DENIED (not owner)
//   - INVALID_STATUS (event is closed)
//   - VALIDATION_ERROR
// ---------------------------------------------------------------
export async function updateEvent({ eventId, title, description, category, eventDate, venue, seatLimit }) {
  const { data, error } = await supabase.rpc('update_event', {
    p_event_id:    eventId,
    p_title:       title       ?? null,
    p_description: description ?? null,
    p_category:    category    ?? null,
    p_event_date:  eventDate   ?? null,
    p_venue:       venue       ?? null,
    p_seat_limit:  seatLimit   ?? null,
  });

  if (error) return { data: null, error: parseEventError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE B — PUBLISH EVENT (Organizer)
// Transitions draft → published
//
// Input:  { eventId }
// Output: { data: { event_id, title, status }, error }
// Auth:   Required
// Role:   organizer (own event only)
// Errors:
//   - EVENT_NOT_FOUND
//   - ACCESS_DENIED
//   - INVALID_STATUS (not draft)
// ---------------------------------------------------------------
export async function publishEvent({ eventId }) {
  const { data, error } = await supabase
    .rpc('publish_event', { p_event_id: eventId });

  if (error) return { data: null, error: parseEventError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE B — CLOSE EVENT (Organizer)
// Transitions published → closed
//
// Input:  { eventId }
// Output: { data: { event_id, title, status }, error }
// Auth:   Required
// Role:   organizer (own event only)
// Errors:
//   - EVENT_NOT_FOUND
//   - ACCESS_DENIED
//   - INVALID_STATUS (not published)
// ---------------------------------------------------------------
export async function closeEvent({ eventId }) {
  const { data, error } = await supabase
    .rpc('close_event', { p_event_id: eventId });

  if (error) return { data: null, error: parseEventError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE A — GET MY EVENTS (Organizer)
// Direct SDK query — RLS restricts to organizer's own events.
//
// Input:  { status? } — optional filter
// Output: { events: [...], error }
// Auth:   Required
// Role:   organizer
// ---------------------------------------------------------------
export async function getMyEvents({ status } = {}) {
  let query = supabase
    .from('events')
    .select('id, title, category, event_date, venue, seat_limit, status, created_at, updated_at')
    .order('created_at', { ascending: false });

  if (status) query = query.eq('status', status);

  const { data, error } = await query;
  if (error) return { events: null, error: parseEventError(error) };
  return { events: data, error: null };
}
