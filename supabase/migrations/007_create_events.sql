-- =============================================================
-- Migration 007: Create events table
-- Campus Event Pulse — Campus Event Pulse
-- =============================================================

-- ---------------------------------------------------------------
-- Table: events
-- Created by organizers. Visible to students when published.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.events (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  organizer_id  UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title         TEXT        NOT NULL CHECK (LENGTH(TRIM(title)) > 0),
  description   TEXT        NOT NULL CHECK (LENGTH(TRIM(description)) > 0),
  category      TEXT        NOT NULL
                              CHECK (category IN (
                                'Technical', 'Cultural', 'Sports',
                                'Workshop', 'Seminar', 'Club', 'Other'
                              )),
  event_date    TIMESTAMPTZ NOT NULL,
  venue         TEXT        NOT NULL CHECK (LENGTH(TRIM(venue)) > 0),
  seat_limit    INTEGER     NOT NULL CHECK (seat_limit > 0),
  status        TEXT        NOT NULL DEFAULT 'draft'
                              CHECK (status IN ('draft', 'published', 'closed')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------
-- Organizer lookup (organizer dashboard, auth checks)
CREATE INDEX IF NOT EXISTS idx_events_organizer_id
  ON public.events(organizer_id);

-- Status filter (students browse published events)
CREATE INDEX IF NOT EXISTS idx_events_status
  ON public.events(status);

-- Category filter
CREATE INDEX IF NOT EXISTS idx_events_category
  ON public.events(category);

-- Date ordering/filter (upcoming events)
CREATE INDEX IF NOT EXISTS idx_events_event_date
  ON public.events(event_date);

-- Composite: most common student query — published + date
CREATE INDEX IF NOT EXISTS idx_events_status_date
  ON public.events(status, event_date);

-- ---------------------------------------------------------------
-- Trigger: auto-update updated_at on every UPDATE
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS events_set_updated_at ON public.events;
CREATE TRIGGER events_set_updated_at
  BEFORE UPDATE ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------
-- Comments
-- ---------------------------------------------------------------
COMMENT ON TABLE public.events IS
  'Campus events created by organizers. Students see only published events.';
COMMENT ON COLUMN public.events.status IS
  'draft → published → closed. Only organizer owner can transition.';
COMMENT ON COLUMN public.events.seat_limit IS
  'Maximum number of students that can register. Enforced by register_for_event() function.';
COMMENT ON COLUMN public.events.category IS
  'One of: Technical, Cultural, Sports, Workshop, Seminar, Club, Other.';
