import { supabase, isSupabaseConfigured } from '../lib/supabaseClient';

const MOCK_STORAGE_KEY_USER = 'cep_mock_user';

/**
 * Normalize role string: backend stores lowercase ('student', 'organizer').
 * UI uses Title-case ('Student', 'Organizer') for display and route checks.
 * This helper converts UI-facing role to lowercase for backend writes.
 */
function normalizeRoleForBackend(role) {
  return (role || 'student').toLowerCase();
}

/**
 * Convert backend lowercase role to UI Title-case.
 */
function normalizeRoleForUI(role) {
  if (!role) return 'Student';
  const r = role.toLowerCase();
  if (r === 'organizer') return 'Organizer';
  if (r === 'admin') return 'Admin';
  return 'Student';
}

export const authService = {
  /**
   * Register a new user with Supabase Auth
   * Role: 'Student' | 'Organizer'
   */
  async signUp({ email, password, fullName, role }) {
    if (!isSupabaseConfigured) {
      const mockUser = {
        id: 'usr-' + Date.now(),
        email,
        user_metadata: {
          full_name: fullName,
          role: role || 'Student',
        },
      };
      localStorage.setItem(MOCK_STORAGE_KEY_USER, JSON.stringify(mockUser));
      return { user: mockUser, error: null };
    }

    // Backend expects lowercase role
    const backendRole = normalizeRoleForBackend(role);

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          full_name: fullName,
          role: backendRole,
        },
      },
    });

    if (error) throw error;

    // If profile table exists in backend, ensure role and name are recorded
    if (data?.user) {
      try {
        await supabase.from('profiles').upsert({
          id: data.user.id,
          full_name: fullName,
          role: backendRole,
          updated_at: new Date().toISOString(),
        });
      } catch (profileErr) {
        // Backend trigger may already handle profiles; ignore if trigger is authoritative
        console.warn('Profile sync notice:', profileErr?.message || profileErr);
      }
    }

    return { user: data.user, session: data.session, error: null };
  },

  /**
   * Sign in existing user with email and password
   */
  async signIn({ email, password }) {
    if (!isSupabaseConfigured) {
      // Allow seamless demo logins
      let role = 'Student';
      let fullName = 'Student User';
      if (email.toLowerCase().includes('organizer') || email.toLowerCase().includes('admin')) {
        role = 'Organizer';
        fullName = 'Campus Organizer';
      }

      const mockUser = {
        id: 'usr-demo-' + (role === 'Organizer' ? 'org' : 'std'),
        email,
        user_metadata: {
          full_name: fullName,
          role,
        },
      };
      localStorage.setItem(MOCK_STORAGE_KEY_USER, JSON.stringify(mockUser));
      return { user: mockUser, session: { access_token: 'demo-token' }, error: null };
    }

    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) throw error;
    return { user: data.user, session: data.session, error: null };
  },

  /**
   * Sign out current user
   */
  async signOut() {
    if (!isSupabaseConfigured) {
      localStorage.removeItem(MOCK_STORAGE_KEY_USER);
      return { error: null };
    }
    const { error } = await supabase.auth.signOut();
    return { error };
  },

  /**
   * Get active session
   */
  async getSession() {
    if (!isSupabaseConfigured) {
      const stored = localStorage.getItem(MOCK_STORAGE_KEY_USER);
      if (stored) {
        try {
          const user = JSON.parse(stored);
          return { session: { user, access_token: 'demo' }, user };
        } catch {
          return { session: null, user: null };
        }
      }
      return { session: null, user: null };
    }

    const { data, error } = await supabase.auth.getSession();
    if (error) throw error;
    return { session: data.session, user: data.session?.user || null };
  },

  /**
   * Get user profile details (including role from profiles table or auth metadata)
   * Normalizes role to UI Title-case ('Student' | 'Organizer') for consumption by AuthContext.
   */
  async getUserProfile(userId) {
    if (!isSupabaseConfigured) {
      const stored = localStorage.getItem(MOCK_STORAGE_KEY_USER);
      if (stored) {
        try {
          const user = JSON.parse(stored);
          return {
            id: user.id,
            email: user.email,
            full_name: user.user_metadata?.full_name || 'Demo User',
            role: normalizeRoleForUI(user.user_metadata?.role),
          };
        } catch {
          // fallback
        }
      }
      return {
        id: userId,
        email: 'student@campus.edu',
        full_name: 'Alex Johnson',
        role: 'Student',
      };
    }

    // Try fetching from profiles table
    // NOTE: profiles table uses 'name' column (migration 001), not 'full_name'.
    // Migration 006 keeps 'name'. We normalize to 'full_name' for the UI.
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single();

      if (!error && data) {
        // Normalize role from backend lowercase to UI Title-case
        // Also normalize 'name' -> 'full_name' for UI consistency
        return {
          ...data,
          full_name: data.full_name || data.name || '',
          role: normalizeRoleForUI(data.role),
        };
      }
    } catch {
      // profiles table RLS may block anonymous reads; fall back to auth metadata
    }

    // Fallback to user metadata (set during signUp or from Supabase Dashboard)
    try {
      const { data: authData } = await supabase.auth.getUser();
      const user = authData?.user;
      if (user) {
        return {
          id: user.id,
          email: user.email,
          full_name:
            user.user_metadata?.full_name ||
            user.user_metadata?.name ||
            user.email?.split('@')[0],
          role: normalizeRoleForUI(user.user_metadata?.role),
        };
      }
    } catch {
      // ignore auth fetch errors
    }

    return null;
  }
};
