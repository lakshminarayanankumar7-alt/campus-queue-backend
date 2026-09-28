import { supabase, isSupabaseConfigured } from '../lib/supabaseClient';
import { INITIAL_EVENTS, INITIAL_PARTICIPANTS } from '../utils/mockData';

const MOCK_STORAGE_KEY_EVENTS = 'cep_mock_events';

function getLocalEvents() {
  const stored = localStorage.getItem(MOCK_STORAGE_KEY_EVENTS);
  if (stored) {
    try {
      return JSON.parse(stored);
    } catch {
      // fallback
    }
  }
  return INITIAL_EVENTS;
}

export const organizerService = {
  /**
   * Calls PostgreSQL backend function: get_organizer_dashboard
   * Returns dashboard metrics and organizer event list.
   */
  async getOrganizerDashboard() {
    if (!isSupabaseConfigured) {
      const events = getLocalEvents();
      const totalEvents = events.length;
      const draftEvents = events.filter((e) => (e.status || '').toLowerCase() === 'draft').length;
      const publishedEvents = events.filter((e) => (e.status || '').toLowerCase() === 'published').length;
      const closedEvents = events.filter((e) => (e.status || '').toLowerCase() === 'closed').length;
      const totalRegistrations = events.reduce((sum, e) => sum + (e.registered_count || 0), 0);

      return {
        data: {
          stats: {
            total_events: totalEvents,
            draft_events: draftEvents,
            published_events: publishedEvents,
            closed_events: closedEvents,
            total_registrations: totalRegistrations,
          },
          events: events.map((e) => ({
            id: e.id,
            title: e.title,
            category: e.category,
            event_date: e.event_date || e.date,
            venue: e.venue,
            status: e.status,
            seat_limit: e.seat_limit,
            registered_count: e.registered_count || 0,
            available_seats: e.available_seats !== undefined ? e.available_seats : (e.seat_limit - (e.registered_count || 0)),
          })),
        },
        error: null,
      };
    }

    const { data, error } = await supabase.rpc('get_organizer_dashboard');

    if (error) throw error;
    return { data, error: null };
  },

  /**
   * Calls PostgreSQL backend function: get_event_participants
   * Returns participant roster and seat statistics.
   */
  async getEventParticipants(eventId) {
    if (!isSupabaseConfigured) {
      const events = getLocalEvents();
      const event = events.find((e) => String(e.id) === String(eventId));
      const participants = INITIAL_PARTICIPANTS[eventId] || [
        {
          id: 'p-default',
          student_name: 'Alex Johnson',
          student_email: 'alex.j@campus.edu',
          status: 'Registered',
          registration_date: '2026-09-26T14:30:00Z',
        }
      ];

      return {
        data: {
          event: event || { title: 'Campus Event', seat_limit: 50, registered_count: participants.length, available_seats: 50 - participants.length },
          participants,
          total_participants: participants.length,
          seat_limit: event ? event.seat_limit : 50,
          available_seats: event ? (event.available_seats ?? (event.seat_limit - participants.length)) : (50 - participants.length),
        },
        error: null,
      };
    }

    const { data, error } = await supabase.rpc('get_event_participants', {
      p_event_id: eventId,
    });

    if (error) throw error;
    return { data, error: null };
  }
};
