import { supabase, isSupabaseConfigured } from '../lib/supabaseClient';
import { INITIAL_EVENTS } from '../utils/mockData';

/**
 * Combines separate date and time strings into a single TIMESTAMPTZ string
 * suitable for the Supabase backend.
 */
function combineDateTime(date, time) {
  if (!date) return null;
  if (!time) return `${date}T00:00:00`;
  return `${date}T${time.length === 5 ? `${time}:00` : time}`;
}

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
  localStorage.setItem(MOCK_STORAGE_KEY_EVENTS, JSON.stringify(INITIAL_EVENTS));
  return INITIAL_EVENTS;
}

function saveLocalEvents(events) {
  localStorage.setItem(MOCK_STORAGE_KEY_EVENTS, JSON.stringify(events));
}

export const eventService = {
  /**
   * Calls PostgreSQL backend function: get_published_events
   */
  async getPublishedEvents() {
    if (!isSupabaseConfigured) {
      const events = getLocalEvents();
      const published = events.filter((e) => (e.status || '').toLowerCase() === 'published');
      return { data: published, error: null };
    }

    const { data, error } = await supabase.rpc('get_published_events');

    if (error) throw error;
    return { data, error: null };
  },

  /**
   * Calls PostgreSQL backend function: get_event_details
   */
  async getEventDetails(eventId) {
    if (!isSupabaseConfigured) {
      const events = getLocalEvents();
      const event = events.find((e) => String(e.id) === String(eventId));
      if (!event) return { data: null, error: new Error('Event not found') };
      return { data: event, error: null };
    }

    const { data, error } = await supabase.rpc('get_event_details', {
      p_event_id: eventId,
    });

    if (error) throw error;
    return { data: Array.isArray(data) ? data[0] : data, error: null };
  },

  /**
   * Calls PostgreSQL backend function: create_event
   * Accepts { title, description, category, date, time, venue, seatLimit }
   * Combines date+time into event_date before sending to backend.
   */
  async createEvent({ title, description, category, date, time, venue, seatLimit }) {
    const seatLimitInt = parseInt(seatLimit, 10);

    if (!isSupabaseConfigured) {
      const events = getLocalEvents();
      const newEvent = {
        id: 'evt-' + Date.now(),
        title,
        description,
        category,
        date,
        time,
        event_date: combineDateTime(date, time),
        venue,
        seat_limit: seatLimitInt,
        registered_count: 0,
        available_seats: seatLimitInt,
        status: 'Draft',
        created_at: new Date().toISOString(),
        organizer_name: 'Campus Organizer',
      };
      events.unshift(newEvent);
      saveLocalEvents(events);
      return { data: newEvent, error: null };
    }

    const { data, error } = await supabase.rpc('create_event', {
      p_title: title,
      p_description: description,
      p_category: category,
      p_event_date: combineDateTime(date, time),
      p_venue: venue,
      p_seat_limit: seatLimitInt,
    });

    if (error) throw error;
    return { data, error: null };
  },

  /**
   * Calls PostgreSQL backend function: update_event
   * Accepts { title, description, category, date, time, venue, seatLimit }
   * Combines date+time into event_date before sending to backend.
   */
  async updateEvent(eventId, { title, description, category, date, time, venue, seatLimit }) {
    const seatLimitInt = parseInt(seatLimit, 10);

    if (!isSupabaseConfigured) {
      const events = getLocalEvents();
      const index = events.findIndex((e) => String(e.id) === String(eventId));
      if (index === -1) return { data: null, error: new Error('Event not found') };

      events[index] = {
        ...events[index],
        title,
        description,
        category,
        date,
        time,
        event_date: combineDateTime(date, time),
        venue,
        seat_limit: seatLimitInt,
        available_seats: Math.max(
          0,
          seatLimitInt - (events[index].registered_count || 0)
        ),
      };
      saveLocalEvents(events);
      return { data: events[index], error: null };
    }

    const { data, error } = await supabase.rpc('update_event', {
      p_event_id: eventId,
      p_title: title,
      p_description: description,
      p_category: category,
      p_event_date: combineDateTime(date, time),
      p_venue: venue,
      p_seat_limit: seatLimitInt,
    });

    if (error) throw error;
    return { data, error: null };
  },

  /**
   * Calls PostgreSQL backend function: publish_event
   */
  async publishEvent(eventId) {
    if (!isSupabaseConfigured) {
      const events = getLocalEvents();
      const index = events.findIndex((e) => String(e.id) === String(eventId));
      if (index === -1) return { error: new Error('Event not found') };
      events[index].status = 'Published';
      saveLocalEvents(events);
      return { data: events[index], error: null };
    }

    const { data, error } = await supabase.rpc('publish_event', {
      p_event_id: eventId,
    });

    if (error) throw error;
    return { data, error: null };
  },

  /**
   * Calls PostgreSQL backend function: close_event
   */
  async closeEvent(eventId) {
    if (!isSupabaseConfigured) {
      const events = getLocalEvents();
      const index = events.findIndex((e) => String(e.id) === String(eventId));
      if (index === -1) return { error: new Error('Event not found') };
      events[index].status = 'Closed';
      saveLocalEvents(events);
      return { data: events[index], error: null };
    }

    const { data, error } = await supabase.rpc('close_event', {
      p_event_id: eventId,
    });

    if (error) throw error;
    return { data, error: null };
  }
};