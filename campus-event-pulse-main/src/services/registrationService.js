import { supabase, isSupabaseConfigured } from '../lib/supabaseClient';
import { INITIAL_REGISTRATIONS } from '../utils/mockData';

const MOCK_STORAGE_KEY_REGS = 'cep_mock_registrations';
const MOCK_STORAGE_KEY_EVENTS = 'cep_mock_events';

function getLocalRegistrations() {
  const stored = localStorage.getItem(MOCK_STORAGE_KEY_REGS);
  if (stored) {
    try {
      return JSON.parse(stored);
    } catch {
      // fallback
    }
  }
  localStorage.setItem(MOCK_STORAGE_KEY_REGS, JSON.stringify(INITIAL_REGISTRATIONS));
  return INITIAL_REGISTRATIONS;
}

function saveLocalRegistrations(regs) {
  localStorage.setItem(MOCK_STORAGE_KEY_REGS, JSON.stringify(regs));
}

export const registrationService = {
  /**
   * Calls PostgreSQL backend function: register_for_event
   */
  async registerForEvent(eventId) {
    if (!isSupabaseConfigured) {
      const regs = getLocalRegistrations();
      // Check duplicate
      const already = regs.find(
        (r) => String(r.event_id) === String(eventId) && r.status === 'Registered'
      );
      if (already) {
        throw new Error('You are already registered for this event.');
      }

      // Check event capacity and status
      const storedEvents = localStorage.getItem(MOCK_STORAGE_KEY_EVENTS);
      const events = storedEvents ? JSON.parse(storedEvents) : [];
      const eventIndex = events.findIndex((e) => String(e.id) === String(eventId));

      if (eventIndex !== -1) {
        const ev = events[eventIndex];
        if ((ev.status || '').toLowerCase() === 'closed') {
          throw new Error('Registration is closed for this event.');
        }
        if (ev.available_seats <= 0) {
          throw new Error('Sorry, this event has reached its maximum seat capacity.');
        }
        ev.registered_count = (ev.registered_count || 0) + 1;
        ev.available_seats = Math.max(0, ev.seat_limit - ev.registered_count);
        localStorage.setItem(MOCK_STORAGE_KEY_EVENTS, JSON.stringify(events));

        const newReg = {
          id: 'reg-' + Date.now(),
          event_id: ev.id,
          title: ev.title,
          event_date: ev.event_date || ev.date,
          venue: ev.venue,
          category: ev.category,
          status: 'Registered',
          registration_date: new Date().toISOString(),
        };
        regs.unshift(newReg);
        saveLocalRegistrations(regs);
        return { data: newReg, error: null };
      }

      throw new Error('Event not found');
    }

    const { data, error } = await supabase.rpc('register_for_event', {
      p_event_id: eventId,
    });

    if (error) throw error;
    return { data, error: null };
  },

  /**
   * Calls PostgreSQL backend function: cancel_registration
   */
  async cancelRegistration(eventId) {
    if (!isSupabaseConfigured) {
      const regs = getLocalRegistrations();
      const reg = regs.find((r) => String(r.event_id) === String(eventId));
      if (reg) {
        reg.status = 'Cancelled';
        saveLocalRegistrations(regs);

        // Adjust seat counts
        const storedEvents = localStorage.getItem(MOCK_STORAGE_KEY_EVENTS);
        const events = storedEvents ? JSON.parse(storedEvents) : [];
        const ev = events.find((e) => String(e.id) === String(eventId));
        if (ev && ev.registered_count > 0) {
          ev.registered_count -= 1;
          ev.available_seats = Math.min(ev.seat_limit, ev.available_seats + 1);
          localStorage.setItem(MOCK_STORAGE_KEY_EVENTS, JSON.stringify(events));
        }
      }
      return { data: true, error: null };
    }

    const { data, error } = await supabase.rpc('cancel_registration', {
      p_event_id: eventId,
    });

    if (error) throw error;
    return { data, error: null };
  },

  /**
   * Calls PostgreSQL backend function: get_my_registrations
   */
  async getMyRegistrations() {
    if (!isSupabaseConfigured) {
      const regs = getLocalRegistrations();
      return { data: regs, error: null };
    }

    const { data, error } = await supabase.rpc('get_my_registrations');

    if (error) throw error;
    return { data, error: null };
  }
};
