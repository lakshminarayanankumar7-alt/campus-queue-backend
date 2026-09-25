// =============================================================
// src/lib/queueService.js
// =============================================================
// Queue management operations for the college queue system.
// All operations use either:
//   A) Direct Supabase SDK queries (read-only, simple selects)
//   B) PostgreSQL RPC functions (write, admin, concurrency-sensitive)
//
// API Classification:
//   getActiveServices()      → A (direct query)
//   joinQueue()              → B (RPC: join_queue)
//   getMyQueues()            → A (direct query with RLS)
//   getQueueStatus()         → B (RPC: get_queue_status)
//   cancelQueue()            → B (RPC: cancel_queue)
//   adminGetServiceQueue()   → B (RPC: get_service_queue)
//   adminCallNext()          → B (RPC: admin_call_next)
//   adminCompleteQueue()     → B (RPC: admin_complete_queue)
// =============================================================

import { supabase } from './supabaseClient.js';

// ---------------------------------------------------------------
// Helper: parse Supabase/PostgreSQL errors into friendly messages
// ---------------------------------------------------------------
function parseError(error) {
  if (!error) return null;
  const msg = error.message || '';

  if (msg.includes('NOT_AUTHENTICATED'))  return 'You must be logged in.';
  if (msg.includes('SERVICE_NOT_FOUND'))  return 'Service not found.';
  if (msg.includes('SERVICE_INACTIVE'))   return 'This service is not currently available.';
  if (msg.includes('DUPLICATE_QUEUE'))    return msg.split(': ')[1] || 'You are already in this queue.';
  if (msg.includes('QUEUE_NOT_FOUND'))    return 'Queue entry not found.';
  if (msg.includes('ACCESS_DENIED'))      return 'You do not have permission for this action.';
  if (msg.includes('QUEUE_EMPTY'))        return 'No students are currently waiting in this queue.';
  if (msg.includes('INVALID_STATUS'))     return 'This action is not valid for the current queue status.';

  return error.message || 'An unexpected error occurred.';
}

// ---------------------------------------------------------------
// TYPE A — GET ACTIVE SERVICES
// Direct Supabase query. RLS allows authenticated users to see
// only is_active = true services.
//
// Input:  none
// Output: { services: [...], error }
// Auth:   Required (student or admin)
// ---------------------------------------------------------------
export async function getActiveServices() {
  const { data, error } = await supabase
    .from('services')
    .select('id, name, description, avg_service_time, is_active')
    .eq('is_active', true)
    .order('name', { ascending: true });

  if (error) return { services: null, error: parseError(error) };
  return { services: data, error: null };
}

// ---------------------------------------------------------------
// TYPE A — GET ALL SERVICES (Admin)
// Admins can see all services including inactive ones.
//
// Input:  none
// Output: { services: [...], error }
// Auth:   Required (admin only — RLS enforced)
// ---------------------------------------------------------------
export async function getAllServices() {
  const { data, error } = await supabase
    .from('services')
    .select('*')
    .order('name', { ascending: true });

  if (error) return { services: null, error: parseError(error) };
  return { services: data, error: null };
}

// ---------------------------------------------------------------
// TYPE B (RPC) — JOIN QUEUE
// Calls the PostgreSQL join_queue() function.
// Handles: auth check, service validation, duplicate check,
//          concurrency-safe token generation, insert.
//
// Input:  { serviceId }
// Output: {
//   data: {
//     queue_id, token, token_number, service_id,
//     service_name, status, joined_at
//   },
//   error
// }
// Auth:   Required (student)
// Role:   student (or admin)
// Errors:
//   - NOT_AUTHENTICATED
//   - SERVICE_NOT_FOUND
//   - SERVICE_INACTIVE
//   - DUPLICATE_QUEUE (already in this queue)
// ---------------------------------------------------------------
export async function joinQueue({ serviceId }) {
  const { data, error } = await supabase
    .rpc('join_queue', { p_service_id: serviceId });

  if (error) return { data: null, error: parseError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE A — GET MY QUEUES
// Fetch all queue entries for the currently logged-in student.
// RLS ensures they only see their own entries.
//
// Input:  { status? } — optional filter ('waiting','serving','completed','cancelled')
// Output: { queues: [...], error }
// Auth:   Required
// ---------------------------------------------------------------
export async function getMyQueues({ status } = {}) {
  let query = supabase
    .from('queues')
    .select(`
      id,
      token_number,
      status,
      joined_at,
      served_at,
      completed_at,
      service_id,
      services (
        id,
        name,
        avg_service_time
      )
    `)
    .order('joined_at', { ascending: false });

  if (status) {
    query = query.eq('status', status);
  }

  const { data, error } = await query;
  if (error) return { queues: null, error: parseError(error) };

  // Attach formatted token string
  const queues = data.map((q) => ({
    ...q,
    token: formatToken(q.services?.name, q.token_number),
  }));

  return { queues, error: null };
}

// ---------------------------------------------------------------
// TYPE B (RPC) — GET QUEUE STATUS
// Returns position, estimated wait, and details for one entry.
//
// Input:  { queueId }
// Output: {
//   data: {
//     queue_id, token, token_number, service_name,
//     status, position, estimated_wait, avg_service_time,
//     joined_at, served_at, completed_at
//   },
//   error
// }
// Auth:   Required
// Role:   Student (own entry only), Admin (any entry)
// ---------------------------------------------------------------
export async function getQueueStatus({ queueId }) {
  const { data, error } = await supabase
    .rpc('get_queue_status', { p_queue_id: queueId });

  if (error) return { data: null, error: parseError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE B (RPC) — CANCEL QUEUE
// Student cancels their own waiting queue entry.
//
// Input:  { queueId }
// Output: {
//   data: { queue_id, token, service_name, status },
//   error
// }
// Auth:   Required (student — own entry only)
// Errors:
//   - QUEUE_NOT_FOUND
//   - ACCESS_DENIED (not own entry)
//   - INVALID_STATUS (not in 'waiting' state)
// ---------------------------------------------------------------
export async function cancelQueue({ queueId }) {
  const { data, error } = await supabase
    .rpc('cancel_queue', { p_queue_id: queueId });

  if (error) return { data: null, error: parseError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE B (RPC) — ADMIN: GET SERVICE QUEUE
// Admin views the full queue for a service.
//
// Input:  { serviceId, status? }
// Output: {
//   data: {
//     service_id, service_name, prefix,
//     queue: [
//       { queue_id, token, status, student_name, student_email,
//         joined_at, served_at, completed_at }
//     ]
//   },
//   error
// }
// Auth:   Required
// Role:   Admin only (enforced in PostgreSQL function)
// ---------------------------------------------------------------
export async function adminGetServiceQueue({ serviceId, status = null }) {
  const { data, error } = await supabase
    .rpc('get_service_queue', {
      p_service_id: serviceId,
      p_status:     status,
    });

  if (error) return { data: null, error: parseError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE B (RPC) — ADMIN: CALL NEXT
// Admin calls the next waiting student for a service.
// Safe against two admins calling simultaneously.
//
// Input:  { serviceId }
// Output: {
//   data: { queue_id, token, service_name, status, served_at },
//   error
// }
// Auth:   Required
// Role:   Admin only (enforced in PostgreSQL function)
// Errors:
//   - QUEUE_EMPTY (no waiting students)
//   - ACCESS_DENIED (not admin)
// ---------------------------------------------------------------
export async function adminCallNext({ serviceId }) {
  const { data, error } = await supabase
    .rpc('admin_call_next', { p_service_id: serviceId });

  if (error) return { data: null, error: parseError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE B (RPC) — ADMIN: COMPLETE QUEUE
// Admin marks the currently serving entry as completed.
//
// Input:  { queueId }
// Output: {
//   data: { queue_id, token, service_name, status, completed_at },
//   error
// }
// Auth:   Required
// Role:   Admin only
// Errors:
//   - QUEUE_NOT_FOUND
//   - INVALID_STATUS (not in 'serving' state)
//   - ACCESS_DENIED (not admin)
// ---------------------------------------------------------------
export async function adminCompleteQueue({ queueId }) {
  const { data, error } = await supabase
    .rpc('admin_complete_queue', { p_queue_id: queueId });

  if (error) return { data: null, error: parseError(error) };
  return { data, error: null };
}

// ---------------------------------------------------------------
// TYPE A (Admin) — UPDATE SERVICE
// Toggle service active/inactive or update settings.
//
// Input:  { serviceId, updates: { is_active?, avg_service_time?, description? } }
// Output: { service, error }
// Auth:   Required
// Role:   Admin only (RLS policy enforces this)
// ---------------------------------------------------------------
export async function adminUpdateService({ serviceId, updates }) {
  const { data, error } = await supabase
    .from('services')
    .update(updates)
    .eq('id', serviceId)
    .select()
    .single();

  if (error) return { service: null, error: parseError(error) };
  return { service: data, error: null };
}

// ---------------------------------------------------------------
// LOCAL HELPER: Format token string (mirrors the SQL function)
// Used for display when we already have the data locally.
// Server always generates the authoritative token.
// ---------------------------------------------------------------
export function formatToken(serviceName, tokenNumber) {
  if (!serviceName || !tokenNumber) return '';
  const prefix = serviceName.trim().charAt(0).toUpperCase();
  const padded = String(tokenNumber).padStart(2, '0');
  return `${prefix}-${padded}`;
}
