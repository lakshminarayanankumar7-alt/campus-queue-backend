// =============================================================
// src/lib/_errorParser.js
// Campus Event Pulse — Shared error message parser
// =============================================================
// Translates PostgreSQL RAISE EXCEPTION codes into
// human-readable strings for display to users.
// Used by eventService, registrationService, organizerService.
// =============================================================

export function parseEventError(error) {
  if (!error) return null;
  const msg = error.message || '';

  // Auth errors
  if (msg.includes('NOT_AUTHENTICATED'))      return 'You must be logged in to continue.';
  if (msg.includes('ACCESS_DENIED'))          return msg.split(': ')[1] || 'You do not have permission for this action.';

  // Event errors
  if (msg.includes('EVENT_NOT_FOUND'))        return 'Event not found or is not available.';
  if (msg.includes('EVENT_NOT_PUBLISHED'))    return 'This event is not yet open for registration.';
  if (msg.includes('EVENT_CLOSED'))           return 'This event is no longer accepting registrations.';
  if (msg.includes('INVALID_STATUS'))         return msg.split(': ')[1] || 'This action is not valid for the current event status.';

  // Registration errors
  if (msg.includes('DUPLICATE_REGISTRATION')) return 'You are already registered for this event.';
  if (msg.includes('EVENT_FULL'))             return 'This event is full. No seats available.';
  if (msg.includes('REGISTRATION_NOT_FOUND')) return 'Registration not found.';

  // Validation errors
  if (msg.includes('VALIDATION_ERROR'))       return msg.split(': ')[1] || 'Invalid input. Please check your data.';

  // Fallback
  return error.message || 'An unexpected error occurred.';
}
