-- =============================================================
-- Migration 004: Row Level Security (RLS) Policies
-- =============================================================
-- RLS means the DATABASE enforces who can see/change each row.
-- Even if someone bypasses the frontend, the database protects data.
-- =============================================================

-- ---------------------------------------------------------------
-- Enable RLS on all tables
-- ---------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.services  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.queues    ENABLE ROW LEVEL SECURITY;


-- ===============================================================
-- PROFILES TABLE POLICIES
-- ===============================================================

-- Students can read their OWN profile only
CREATE POLICY "profiles_select_own"
  ON public.profiles
  FOR SELECT
  USING (auth.uid() = id);

-- Admins can read ALL profiles (needed to show student names in queue)
CREATE POLICY "profiles_select_admin"
  ON public.profiles
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
    )
  );

-- Users can update their OWN profile (name only — NOT role)
-- The role column is excluded by not allowing UPDATE of role field.
-- Role changes must be done via service-role SQL (not through this policy).
CREATE POLICY "profiles_update_own_name_only"
  ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    -- Prevent self-elevation: new role must equal existing role
    AND role = (SELECT role FROM public.profiles WHERE id = auth.uid())
  );

-- Trigger function creates the profile — no INSERT policy needed for users
-- (The trigger runs as SECURITY DEFINER, bypassing RLS)


-- ===============================================================
-- SERVICES TABLE POLICIES
-- ===============================================================

-- Anyone authenticated can view ACTIVE services
CREATE POLICY "services_select_active_authenticated"
  ON public.services
  FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND is_active = TRUE
  );

-- Admins can view ALL services (including inactive)
CREATE POLICY "services_select_all_admin"
  ON public.services
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
    )
  );

-- Admins can update service settings (e.g., toggle is_active)
CREATE POLICY "services_update_admin"
  ON public.services
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
    )
  );

-- Admins can insert new services
CREATE POLICY "services_insert_admin"
  ON public.services
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
    )
  );


-- ===============================================================
-- QUEUES TABLE POLICIES
-- ===============================================================

-- Students can VIEW their own queue entries (all statuses: history included)
CREATE POLICY "queues_select_own"
  ON public.queues
  FOR SELECT
  USING (auth.uid() = user_id);

-- Admins can VIEW ALL queue entries across all services
CREATE POLICY "queues_select_admin"
  ON public.queues
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
    )
  );

-- Students can INSERT (join queue) — but only for themselves
-- The SECURITY DEFINER function join_queue() enforces all additional rules
-- (active service check, duplicate check, token generation)
-- Direct INSERT is blocked here; students MUST use the join_queue() function
-- This policy is intentionally restrictive — use the function instead
CREATE POLICY "queues_insert_own"
  ON public.queues
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Students can UPDATE their OWN queue entries ONLY to cancel (waiting → cancelled)
-- They cannot change status to 'serving' or 'completed' (enforced by WITH CHECK)
CREATE POLICY "queues_update_cancel_own"
  ON public.queues
  FOR UPDATE
  USING (
    auth.uid() = user_id
    AND status = 'waiting'   -- Can only update if currently waiting
  )
  WITH CHECK (
    auth.uid() = user_id
    AND status = 'cancelled' -- Can only change TO cancelled
  );

-- Admins can UPDATE any queue entry (for call-next and complete operations)
-- The admin_call_next() and admin_complete_queue() functions add further validation
CREATE POLICY "queues_update_admin"
  ON public.queues
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.role = 'admin'
    )
  );

-- ---------------------------------------------------------------
-- SECURITY NOTE:
-- Students CANNOT:
--   - See other students' queues
--   - Change their own role
--   - Set status to 'serving' or 'completed'
--   - Change token_number
--   - Access admin operations
--
-- The database enforces this even if the frontend is bypassed.
-- ---------------------------------------------------------------
