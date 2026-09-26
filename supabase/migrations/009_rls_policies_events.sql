-- =============================================================
-- Migration 009: Row Level Security — Campus Event Pulse
-- =============================================================
-- RLS is enabled on events and registrations tables.
-- profiles RLS from migration 004 is preserved and extended below.
-- =============================================================

-- ---------------------------------------------------------------
-- Enable RLS on new tables
-- ---------------------------------------------------------------
ALTER TABLE public.events        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.registrations ENABLE ROW LEVEL SECURITY;


-- ===============================================================
-- EVENTS TABLE POLICIES
-- ===============================================================

-- 1. Anyone authenticated can read PUBLISHED events
CREATE POLICY "events_select_published"
  ON public.events
  FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND status = 'published'
  );

-- 2. Organizer can read ALL their own events (draft + published + closed)
CREATE POLICY "events_select_own_organizer"
  ON public.events
  FOR SELECT
  USING (organizer_id = auth.uid());

-- 3. Organizer can INSERT events only for themselves
CREATE POLICY "events_insert_organizer"
  ON public.events
  FOR INSERT
  WITH CHECK (
    organizer_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role = 'organizer'
    )
  );

-- 4. Organizer can UPDATE only their OWN events
CREATE POLICY "events_update_own_organizer"
  ON public.events
  FOR UPDATE
  USING (organizer_id = auth.uid())
  WITH CHECK (
    organizer_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role = 'organizer'
    )
  );

-- 5. Organizer can DELETE only their own DRAFT events (safety valve)
CREATE POLICY "events_delete_own_draft_organizer"
  ON public.events
  FOR DELETE
  USING (
    organizer_id = auth.uid()
    AND status = 'draft'
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role = 'organizer'
    )
  );


-- ===============================================================
-- REGISTRATIONS TABLE POLICIES
-- ===============================================================

-- 1. Students can read their OWN registrations
CREATE POLICY "registrations_select_own_student"
  ON public.registrations
  FOR SELECT
  USING (student_id = auth.uid());

-- 2. Organizers can read registrations for their own events
CREATE POLICY "registrations_select_event_organizer"
  ON public.registrations
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = registrations.event_id
        AND e.organizer_id = auth.uid()
    )
  );

-- 3. Students can INSERT a registration only for themselves
--    Full business-logic checks (full? published? duplicate?) happen in
--    the SECURITY DEFINER function register_for_event().
--    This policy is an additional safety layer.
CREATE POLICY "registrations_insert_own_student"
  ON public.registrations
  FOR INSERT
  WITH CHECK (
    student_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role = 'student'
    )
  );

-- 4. Students can UPDATE their own registration (cancel only)
--    The cancel_registration() function enforces the status transition.
CREATE POLICY "registrations_update_own_student"
  ON public.registrations
  FOR UPDATE
  USING (student_id = auth.uid())
  WITH CHECK (student_id = auth.uid());


-- ===============================================================
-- PROFILES TABLE — extend existing policies from migration 004
-- ===============================================================
-- Migration 004 already has policies for student/admin.
-- We need organizers to also be able to read their own profile
-- and update their name. The existing "profiles_select_own" and
-- "profiles_update_own_name_only" policies already cover them
-- (they use auth.uid() = id, not role-specific).
-- No changes needed to profiles RLS for organizer support.
-- ===============================================================

-- ---------------------------------------------------------------
-- SECURITY NOTES
-- ---------------------------------------------------------------
-- Students CANNOT:
--   - See other students' registrations
--   - Create/update/delete events
--   - See participant lists for events they're not the organizer of
--   - Promote themselves to organizer (blocked in trigger + profiles RLS)
--
-- Organizers CANNOT:
--   - Edit another organizer's event (organizer_id = auth.uid() check)
--   - See registrations for events they don't own
--   - Register for events as a student (blocked by role check in insert policy)
--
-- All critical business logic (seat limit, duplicate check, status
-- transitions) happens in SECURITY DEFINER functions (migration 010).
-- ---------------------------------------------------------------
