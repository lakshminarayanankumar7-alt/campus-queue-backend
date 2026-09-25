-- =============================================================
-- Migration 002: Create services table + seed initial services
-- =============================================================

-- ---------------------------------------------------------------
-- Table: services
-- Represents a department or counter students can queue for.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.services (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name              TEXT NOT NULL UNIQUE,
  description       TEXT,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  avg_service_time  INTEGER NOT NULL DEFAULT 5
                      CHECK (avg_service_time > 0),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for active services (students always filter by is_active)
CREATE INDEX IF NOT EXISTS idx_services_active ON public.services(is_active);

-- ---------------------------------------------------------------
-- Seed: Initial sample services
-- These are inserted once. If they already exist, skip.
-- ---------------------------------------------------------------
INSERT INTO public.services (name, description, is_active, avg_service_time)
VALUES
  (
    'Library',
    'Book borrowing, returns, library card registration and reference queries.',
    TRUE,
    5
  ),
  (
    'Accounts',
    'Fee payment, receipts, scholarship queries and financial clearances.',
    TRUE,
    7
  ),
  (
    'Admin Office',
    'Enrollment, document requests, certificates and general administration.',
    TRUE,
    10
  )
ON CONFLICT (name) DO NOTHING;

COMMENT ON TABLE public.services IS
  'Departments/counters available for student queuing.';
COMMENT ON COLUMN public.services.avg_service_time IS
  'Average minutes to serve one student. Used for estimated wait time calculation.';
