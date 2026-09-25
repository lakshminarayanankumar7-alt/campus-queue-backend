-- =============================================================
-- Migration 003: Create queues table
-- =============================================================

-- ---------------------------------------------------------------
-- Table: queues
-- Represents a single student's queue entry for a service.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.queues (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  service_id    UUID NOT NULL REFERENCES public.services(id) ON DELETE RESTRICT,
  token_number  INTEGER NOT NULL
                  CHECK (token_number > 0),
  status        TEXT NOT NULL DEFAULT 'waiting'
                  CHECK (status IN ('waiting', 'serving', 'completed', 'cancelled')),
  joined_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  served_at     TIMESTAMPTZ,
  completed_at  TIMESTAMPTZ
);

-- ---------------------------------------------------------------
-- Constraints
-- ---------------------------------------------------------------

-- Prevent a student from being in the same service twice actively
-- (waiting OR serving — only one active entry per student per service)
CREATE UNIQUE INDEX IF NOT EXISTS idx_queues_active_user_service
  ON public.queues(user_id, service_id)
  WHERE status IN ('waiting', 'serving');

-- Prevent duplicate token numbers for the same service (per active queue day)
-- Token numbers are sequential per service and should be unique among active entries
CREATE UNIQUE INDEX IF NOT EXISTS idx_queues_unique_token_per_service
  ON public.queues(service_id, token_number)
  WHERE status IN ('waiting', 'serving');

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_queues_service_id  ON public.queues(service_id);
CREATE INDEX IF NOT EXISTS idx_queues_user_id     ON public.queues(user_id);
CREATE INDEX IF NOT EXISTS idx_queues_status      ON public.queues(status);
CREATE INDEX IF NOT EXISTS idx_queues_joined_at   ON public.queues(joined_at);

-- Composite index for admin queue view (service + status + order)
CREATE INDEX IF NOT EXISTS idx_queues_service_status_joined
  ON public.queues(service_id, status, joined_at ASC);

COMMENT ON TABLE public.queues IS
  'Queue entries. Each row is one student waiting/being served/done at a service counter.';
COMMENT ON COLUMN public.queues.token_number IS
  'Sequential number per service. Used to display tokens like A-01, L-01, O-01.';
COMMENT ON COLUMN public.queues.status IS
  'waiting → serving → completed. Or waiting → cancelled by student.';
