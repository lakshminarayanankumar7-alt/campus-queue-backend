-- =============================================================
-- Migration 005: Queue Management Functions (SECURITY DEFINER)
-- =============================================================
-- These PostgreSQL functions run with elevated privileges
-- (SECURITY DEFINER) so they can bypass RLS where necessary
-- for trusted, server-side logic only.
--
-- They are called by the frontend via Supabase RPC:
--   supabase.rpc('function_name', { param: value })
-- =============================================================

-- ---------------------------------------------------------------
-- HELPER: Get service token prefix from service name
-- Returns first letter uppercase. E.g., "Library" → "L"
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_service_prefix(service_name TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN UPPER(LEFT(TRIM(service_name), 1));
END;
$$;

-- ---------------------------------------------------------------
-- HELPER: Format a token string from prefix + number
-- E.g., prefix='A', number=3 → 'A-03'
-- Zero-pads to 2 digits (supports up to 99 per session)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.format_token(prefix TEXT, token_number INTEGER)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN prefix || '-' || LPAD(token_number::TEXT, 2, '0');
END;
$$;


-- ===============================================================
-- FUNCTION 1: join_queue
-- Called by students to join a service queue.
-- Handles: auth check, service check, duplicate check,
--          concurrency-safe token generation, insert.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.join_queue(p_service_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id       UUID;
  v_service       public.services%ROWTYPE;
  v_existing      public.queues%ROWTYPE;
  v_next_token    INTEGER;
  v_new_queue     public.queues%ROWTYPE;
  v_prefix        TEXT;
  v_token_str     TEXT;
BEGIN
  -- 1. Verify the caller is authenticated
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED: You must be logged in to join a queue.'
      USING ERRCODE = 'P0001';
  END IF;

  -- 2. Verify the service exists and fetch it (LOCK for concurrency safety)
  SELECT * INTO v_service
  FROM public.services
  WHERE id = p_service_id
  FOR UPDATE;  -- Lock this row so concurrent joins don't race

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SERVICE_NOT_FOUND: The requested service does not exist.'
      USING ERRCODE = 'P0002';
  END IF;

  -- 3. Verify the service is active
  IF NOT v_service.is_active THEN
    RAISE EXCEPTION 'SERVICE_INACTIVE: This service is currently not accepting new queue entries.'
      USING ERRCODE = 'P0003';
  END IF;

  -- 4. Check for duplicate active queue entry (student already in this service queue)
  SELECT * INTO v_existing
  FROM public.queues
  WHERE user_id = v_user_id
    AND service_id = p_service_id
    AND status IN ('waiting', 'serving');

  IF FOUND THEN
    RAISE EXCEPTION 'DUPLICATE_QUEUE: You are already in the queue for this service. Token: %',
      public.format_token(public.get_service_prefix(v_service.name), v_existing.token_number)
      USING ERRCODE = 'P0004';
  END IF;

  -- 5. Generate the next token number for this service (concurrency-safe)
  -- MAX() returns NULL if no rows exist, COALESCE turns that into 0
  SELECT COALESCE(MAX(token_number), 0) + 1
  INTO v_next_token
  FROM public.queues
  WHERE service_id = p_service_id;
  -- Note: The FOR UPDATE lock on services above prevents two simultaneous
  -- calls from reading the same MAX and generating duplicate tokens.

  -- 6. Build token string
  v_prefix    := public.get_service_prefix(v_service.name);
  v_token_str := public.format_token(v_prefix, v_next_token);

  -- 7. Insert the new queue entry
  INSERT INTO public.queues (user_id, service_id, token_number, status, joined_at)
  VALUES (v_user_id, p_service_id, v_next_token, 'waiting', NOW())
  RETURNING * INTO v_new_queue;

  -- 8. Return enriched response as JSON
  RETURN json_build_object(
    'queue_id',       v_new_queue.id,
    'token',          v_token_str,
    'token_number',   v_new_queue.token_number,
    'service_id',     v_new_queue.service_id,
    'service_name',   v_service.name,
    'status',         v_new_queue.status,
    'joined_at',      v_new_queue.joined_at
  );
END;
$$;

COMMENT ON FUNCTION public.join_queue IS
  'Called by student to join a queue. Handles auth, validation, concurrency-safe token generation.';


-- ===============================================================
-- FUNCTION 2: get_queue_status
-- Returns queue position and estimated wait time for a queue entry.
-- Called by student to check their position.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.get_queue_status(p_queue_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id       UUID;
  v_queue         public.queues%ROWTYPE;
  v_service       public.services%ROWTYPE;
  v_position      INTEGER;
  v_prefix        TEXT;
  v_token_str     TEXT;
  v_est_wait      INTEGER;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- 2. Fetch the queue entry (must belong to calling user unless admin)
  SELECT * INTO v_queue FROM public.queues WHERE id = p_queue_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'QUEUE_NOT_FOUND: Queue entry does not exist.' USING ERRCODE = 'P0005';
  END IF;

  -- 3. Students can only check their own queue; admins can check any
  IF v_queue.user_id <> v_user_id THEN
    -- Allow if caller is admin
    IF NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE id = v_user_id AND role = 'admin'
    ) THEN
      RAISE EXCEPTION 'ACCESS_DENIED: You can only check your own queue entries.' USING ERRCODE = 'P0006';
    END IF;
  END IF;

  -- 4. Fetch service info
  SELECT * INTO v_service FROM public.services WHERE id = v_queue.service_id;

  -- 5. Calculate position:
  --    Count waiting entries for the same service that joined BEFORE this entry
  SELECT COUNT(*) INTO v_position
  FROM public.queues
  WHERE service_id = v_queue.service_id
    AND status = 'waiting'
    AND joined_at < v_queue.joined_at;
  -- Position is 1-based: 0 people ahead = position 1 (next up)
  v_position := v_position + 1;

  -- 6. Calculate estimated wait time
  --    People ahead × avg service time
  --    (v_position - 1) = number of people ahead of this entry
  v_est_wait := (v_position - 1) * v_service.avg_service_time;

  -- 7. Build token string
  v_prefix    := public.get_service_prefix(v_service.name);
  v_token_str := public.format_token(v_prefix, v_queue.token_number);

  -- 8. Return result
  RETURN json_build_object(
    'queue_id',         v_queue.id,
    'token',            v_token_str,
    'token_number',     v_queue.token_number,
    'service_name',     v_service.name,
    'status',           v_queue.status,
    'position',         CASE WHEN v_queue.status = 'waiting' THEN v_position ELSE NULL END,
    'estimated_wait',   CASE WHEN v_queue.status = 'waiting' THEN v_est_wait  ELSE NULL END,
    'avg_service_time', v_service.avg_service_time,
    'joined_at',        v_queue.joined_at,
    'served_at',        v_queue.served_at,
    'completed_at',     v_queue.completed_at
  );
END;
$$;

COMMENT ON FUNCTION public.get_queue_status IS
  'Returns token, position, and estimated wait for a queue entry. Students see only own entries.';


-- ===============================================================
-- FUNCTION 3: admin_call_next
-- Admin operation: moves the next waiting entry → serving.
-- Safe against two admins calling simultaneously (FOR UPDATE SKIP LOCKED).
-- ===============================================================
CREATE OR REPLACE FUNCTION public.admin_call_next(p_service_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID;
  v_service   public.services%ROWTYPE;
  v_queue     public.queues%ROWTYPE;
  v_prefix    TEXT;
  v_token_str TEXT;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- 2. Admin role check
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = v_user_id AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'ACCESS_DENIED: Only admins can call the next queue entry.' USING ERRCODE = 'P0006';
  END IF;

  -- 3. Verify service exists
  SELECT * INTO v_service FROM public.services WHERE id = p_service_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SERVICE_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  -- 4. Find the earliest waiting entry and lock it atomically
  --    FOR UPDATE SKIP LOCKED: if another admin is processing this row, skip it
  --    This prevents two admins from calling the same person simultaneously
  SELECT * INTO v_queue
  FROM public.queues
  WHERE service_id = p_service_id
    AND status = 'waiting'
  ORDER BY joined_at ASC, token_number ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'QUEUE_EMPTY: No waiting students in this queue.' USING ERRCODE = 'P0007';
  END IF;

  -- 5. Update status: waiting → serving
  UPDATE public.queues
  SET status   = 'serving',
      served_at = NOW()
  WHERE id = v_queue.id
  RETURNING * INTO v_queue;

  -- 6. Build token string
  v_prefix    := public.get_service_prefix(v_service.name);
  v_token_str := public.format_token(v_prefix, v_queue.token_number);

  -- 7. Return result
  RETURN json_build_object(
    'queue_id',     v_queue.id,
    'token',        v_token_str,
    'service_name', v_service.name,
    'status',       v_queue.status,
    'served_at',    v_queue.served_at
  );
END;
$$;

COMMENT ON FUNCTION public.admin_call_next IS
  'Admin calls next waiting student. Uses FOR UPDATE SKIP LOCKED to prevent dual-call race condition.';


-- ===============================================================
-- FUNCTION 4: admin_complete_queue
-- Admin marks the currently serving entry as completed.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.admin_complete_queue(p_queue_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID;
  v_queue     public.queues%ROWTYPE;
  v_service   public.services%ROWTYPE;
  v_prefix    TEXT;
  v_token_str TEXT;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- 2. Admin role check
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = v_user_id AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'ACCESS_DENIED: Only admins can complete queue entries.' USING ERRCODE = 'P0006';
  END IF;

  -- 3. Fetch queue entry
  SELECT * INTO v_queue FROM public.queues WHERE id = p_queue_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'QUEUE_NOT_FOUND' USING ERRCODE = 'P0005';
  END IF;

  -- 4. Must be currently serving
  IF v_queue.status <> 'serving' THEN
    RAISE EXCEPTION 'INVALID_STATUS: Can only complete entries with status=serving. Current status: %', v_queue.status
      USING ERRCODE = 'P0008';
  END IF;

  -- 5. Update status: serving → completed
  UPDATE public.queues
  SET status       = 'completed',
      completed_at = NOW()
  WHERE id = p_queue_id
  RETURNING * INTO v_queue;

  -- 6. Fetch service info for token string
  SELECT * INTO v_service FROM public.services WHERE id = v_queue.service_id;
  v_prefix    := public.get_service_prefix(v_service.name);
  v_token_str := public.format_token(v_prefix, v_queue.token_number);

  -- 7. Return result
  RETURN json_build_object(
    'queue_id',      v_queue.id,
    'token',         v_token_str,
    'service_name',  v_service.name,
    'status',        v_queue.status,
    'completed_at',  v_queue.completed_at
  );
END;
$$;

COMMENT ON FUNCTION public.admin_complete_queue IS
  'Admin marks serving entry as completed. Validates status transition.';


-- ===============================================================
-- FUNCTION 5: cancel_queue
-- Student cancels their own waiting queue entry.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.cancel_queue(p_queue_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID;
  v_queue     public.queues%ROWTYPE;
  v_service   public.services%ROWTYPE;
  v_prefix    TEXT;
  v_token_str TEXT;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- 2. Fetch queue entry
  SELECT * INTO v_queue FROM public.queues WHERE id = p_queue_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'QUEUE_NOT_FOUND' USING ERRCODE = 'P0005';
  END IF;

  -- 3. Students can only cancel their OWN entries
  IF v_queue.user_id <> v_user_id THEN
    RAISE EXCEPTION 'ACCESS_DENIED: You can only cancel your own queue entries.' USING ERRCODE = 'P0006';
  END IF;

  -- 4. Can only cancel if status is 'waiting'
  IF v_queue.status <> 'waiting' THEN
    RAISE EXCEPTION 'INVALID_STATUS: Can only cancel entries with status=waiting. Current status: %', v_queue.status
      USING ERRCODE = 'P0008';
  END IF;

  -- 5. Update to cancelled
  UPDATE public.queues
  SET status = 'cancelled'
  WHERE id = p_queue_id
  RETURNING * INTO v_queue;

  -- 6. Fetch service info
  SELECT * INTO v_service FROM public.services WHERE id = v_queue.service_id;
  v_prefix    := public.get_service_prefix(v_service.name);
  v_token_str := public.format_token(v_prefix, v_queue.token_number);

  -- 7. Return result
  RETURN json_build_object(
    'queue_id',    v_queue.id,
    'token',       v_token_str,
    'service_name', v_service.name,
    'status',      v_queue.status
  );
END;
$$;

COMMENT ON FUNCTION public.cancel_queue IS
  'Student cancels their own waiting queue entry. Validates ownership and status.';


-- ===============================================================
-- FUNCTION 6: get_service_queue (Admin view)
-- Returns full queue for a service with token strings and user info.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.get_service_queue(p_service_id UUID, p_status TEXT DEFAULT NULL)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id   UUID;
  v_service   public.services%ROWTYPE;
  v_prefix    TEXT;
  v_result    JSON;
BEGIN
  -- 1. Auth check
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- 2. Admin role check
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = v_user_id AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'ACCESS_DENIED: Only admins can view the full service queue.' USING ERRCODE = 'P0006';
  END IF;

  -- 3. Fetch service
  SELECT * INTO v_service FROM public.services WHERE id = p_service_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SERVICE_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  v_prefix := public.get_service_prefix(v_service.name);

  -- 4. Build the queue list
  SELECT json_build_object(
    'service_id',   v_service.id,
    'service_name', v_service.name,
    'prefix',       v_prefix,
    'queue',        COALESCE(
      (
        SELECT json_agg(
          json_build_object(
            'queue_id',     q.id,
            'token',        public.format_token(v_prefix, q.token_number),
            'token_number', q.token_number,
            'status',       q.status,
            'user_id',      q.user_id,
            'student_name', pr.name,
            'student_email',pr.email,
            'joined_at',    q.joined_at,
            'served_at',    q.served_at,
            'completed_at', q.completed_at
          )
          ORDER BY q.joined_at ASC, q.token_number ASC
        )
        FROM public.queues q
        LEFT JOIN public.profiles pr ON pr.id = q.user_id
        WHERE q.service_id = p_service_id
          AND (p_status IS NULL OR q.status = p_status)
      ),
      '[]'::JSON
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_service_queue IS
  'Admin view of a service queue. Optional p_status filter (waiting/serving/completed/cancelled).';


-- ===============================================================
-- GRANT EXECUTE permissions to authenticated users
-- (RLS inside each function controls what they can actually do)
-- ===============================================================
GRANT EXECUTE ON FUNCTION public.join_queue(UUID)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_queue_status(UUID)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_call_next(UUID)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_complete_queue(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_queue(UUID)         TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_service_queue(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_service_prefix(TEXT)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.format_token(TEXT, INTEGER) TO authenticated;
