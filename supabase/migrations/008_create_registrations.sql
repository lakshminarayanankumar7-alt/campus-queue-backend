-- =============================================================
-- Migration 008: Create registrations table
-- Campus Event Pulse
-- =============================================================

-- ---------------------------------------------------------------
-- Table: registrations
-- One row per student per event.
-- UNIQUE(event_id, student_id) prevents double-registration.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.registrations (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id      UUID        NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  student_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status        TEXT        NOT NULL DEFAULT 'registered'
                              CHECK (status IN ('registered', 'cancelled')),
  registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- CRITICAL: Prevent a student from registering twice for the same event
  CONSTRAINT uq_registration_per_student_event
    UNIQUE (event_id, student_id)
);

-- ---------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------
-- Student querying their own registrations
CREATE INDEX IF NOT EXISTS idx_registrations_student_id
  ON public.registrations(student_id);

-- Organizer querying registrations for their event
CREATE INDEX IF NOT EXISTS idx_registrations_event_id
  ON public.registrations(event_id);

-- Count active registrations quickly (seat availability check)
CREATE INDEX IF NOT EXISTS idx_registrations_event_status
  ON public.registrations(event_id, status);

-- ---------------------------------------------------------------
-- Trigger: auto-update updated_at
-- ---------------------------------------------------------------
DROP TRIGGER IF EXISTS registrations_set_updated_at ON public.registrations;
CREATE TRIGGER registrations_set_updated_at
  BEFORE UPDATE ON public.registrations
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();
  -- Reuses the set_updated_at() function from migration 007

-- ---------------------------------------------------------------
-- Comments
-- ---------------------------------------------------------------
COMMENT ON TABLE public.registrations IS
  'Student event registrations. Unique per (event_id, student_id) pair.';
COMMENT ON COLUMN public.registrations.status IS
  'registered = active. cancelled = student withdrew. Never deleted to preserve history.';
COMMENT ON CONSTRAINT uq_registration_per_student_event ON public.registrations IS
  'Prevents a student from registering twice for the same event, even if cancelled then re-registering (handled in business logic).';
