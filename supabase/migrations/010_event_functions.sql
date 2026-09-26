-- =============================================================
-- Migration 010: Event & Registration Functions
-- Campus Event Pulse — SECURITY DEFINER functions
-- =============================================================
-- All functions run with elevated trust via SECURITY DEFINER.
-- They perform auth checks internally.
-- Called from frontend via: supabase.rpc('function_name', params)
-- =============================================================


-- ---------------------------------------------------------------
-- HELPER: Verify caller is an organizer
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_organizer()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED: You must be logged in.'
      USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'organizer'
  ) THEN
    RAISE EXCEPTION 'ACCESS_DENIED: Only organizers can perform this action.'
      USING ERRCODE = 'P0006';
  END IF;
  RETURN v_uid;
END;
$$;

-- ---------------------------------------------------------------
-- HELPER: Verify caller is a student
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_student()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid UUID;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED: You must be logged in.'
      USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = v_uid AND role = 'student'
  ) THEN
    RAISE EXCEPTION 'ACCESS_DENIED: Only students can perform this action.'
      USING ERRCODE = 'P0006';
  END IF;
  RETURN v_uid;
END;
$$;


-- ===============================================================
-- FUNCTION 1: create_event
-- Organizer creates a new event (starts as draft).
-- ===============================================================
CREATE OR REPLACE FUNCTION public.create_event(
  p_title       TEXT,
  p_description TEXT,
  p_category    TEXT,
  p_event_date  TIMESTAMPTZ,
  p_venue       TEXT,
  p_seat_limit  INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organizer_id UUID;
  v_event        public.events%ROWTYPE;
BEGIN
  -- 1. Auth + role check
  v_organizer_id := public.assert_organizer();

  -- 2. Input validation
  IF TRIM(p_title) = '' OR p_title IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Title cannot be empty.' USING ERRCODE = 'P0010';
  END IF;
  IF TRIM(p_description) = '' OR p_description IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Description cannot be empty.' USING ERRCODE = 'P0010';
  END IF;
  IF p_category NOT IN ('Technical','Cultural','Sports','Workshop','Seminar','Club','Other') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Invalid category.' USING ERRCODE = 'P0010';
  END IF;
  IF p_event_date IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Event date is required.' USING ERRCODE = 'P0010';
  END IF;
  IF TRIM(p_venue) = '' OR p_venue IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Venue cannot be empty.' USING ERRCODE = 'P0010';
  END IF;
  IF p_seat_limit IS NULL OR p_seat_limit < 1 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Seat limit must be a positive integer.' USING ERRCODE = 'P0010';
  END IF;

  -- 3. Insert event (status defaults to 'draft')
  INSERT INTO public.events (
    organizer_id, title, description, category,
    event_date, venue, seat_limit, status
  )
  VALUES (
    v_organizer_id, TRIM(p_title), TRIM(p_description), p_category,
    p_event_date, TRIM(p_venue), p_seat_limit, 'draft'
  )
  RETURNING * INTO v_event;

  -- 4. Return
  RETURN json_build_object(
    'event_id',     v_event.id,
    'title',        v_event.title,
    'category',     v_event.category,
    'status',       v_event.status,
    'seat_limit',   v_event.seat_limit,
    'event_date',   v_event.event_date,
    'created_at',   v_event.created_at
  );
END;
$$;

COMMENT ON FUNCTION public.create_event IS
  'Organizer creates a new event. Status defaults to draft. Validates all inputs server-side.';


-- ===============================================================
-- FUNCTION 2: update_event
-- Organizer edits their own event (only if draft or published).
-- ===============================================================
CREATE OR REPLACE FUNCTION public.update_event(
  p_event_id    UUID,
  p_title       TEXT       DEFAULT NULL,
  p_description TEXT       DEFAULT NULL,
  p_category    TEXT       DEFAULT NULL,
  p_event_date  TIMESTAMPTZ DEFAULT NULL,
  p_venue       TEXT       DEFAULT NULL,
  p_seat_limit  INTEGER    DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organizer_id UUID;
  v_event        public.events%ROWTYPE;
BEGIN
  -- 1. Auth + role check
  v_organizer_id := public.assert_organizer();

  -- 2. Fetch and lock event
  SELECT * INTO v_event
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND: Event does not exist.' USING ERRCODE = 'P0020';
  END IF;

  -- 3. Ownership check
  IF v_event.organizer_id <> v_organizer_id THEN
    RAISE EXCEPTION 'ACCESS_DENIED: You can only edit your own events.' USING ERRCODE = 'P0006';
  END IF;

  -- 4. Cannot edit closed events
  IF v_event.status = 'closed' THEN
    RAISE EXCEPTION 'INVALID_STATUS: Cannot edit a closed event.' USING ERRCODE = 'P0021';
  END IF;

  -- 5. Validate non-null inputs
  IF p_title IS NOT NULL AND TRIM(p_title) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Title cannot be empty.' USING ERRCODE = 'P0010';
  END IF;
  IF p_description IS NOT NULL AND TRIM(p_description) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Description cannot be empty.' USING ERRCODE = 'P0010';
  END IF;
  IF p_category IS NOT NULL AND p_category NOT IN (
    'Technical','Cultural','Sports','Workshop','Seminar','Club','Other'
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Invalid category.' USING ERRCODE = 'P0010';
  END IF;
  IF p_venue IS NOT NULL AND TRIM(p_venue) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Venue cannot be empty.' USING ERRCODE = 'P0010';
  END IF;
  IF p_seat_limit IS NOT NULL AND p_seat_limit < 1 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Seat limit must be a positive integer.' USING ERRCODE = 'P0010';
  END IF;

  -- 6. Patch — only update provided fields
  UPDATE public.events SET
    title       = COALESCE(NULLIF(TRIM(p_title), ''),       title),
    description = COALESCE(NULLIF(TRIM(p_description), ''), description),
    category    = COALESCE(p_category,    category),
    event_date  = COALESCE(p_event_date,  event_date),
    venue       = COALESCE(NULLIF(TRIM(p_venue), ''),       venue),
    seat_limit  = COALESCE(p_seat_limit,  seat_limit)
  WHERE id = p_event_id
  RETURNING * INTO v_event;

  RETURN json_build_object(
    'event_id',   v_event.id,
    'title',      v_event.title,
    'category',   v_event.category,
    'status',     v_event.status,
    'seat_limit', v_event.seat_limit,
    'event_date', v_event.event_date,
    'updated_at', v_event.updated_at
  );
END;
$$;

COMMENT ON FUNCTION public.update_event IS
  'Organizer patches their own event. NULL params are ignored (partial update). Closed events cannot be edited.';


-- ===============================================================
-- FUNCTION 3: publish_event
-- Organizer transitions: draft → published
-- ===============================================================
CREATE OR REPLACE FUNCTION public.publish_event(p_event_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organizer_id UUID;
  v_event        public.events%ROWTYPE;
BEGIN
  v_organizer_id := public.assert_organizer();

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0020';
  END IF;
  IF v_event.organizer_id <> v_organizer_id THEN
    RAISE EXCEPTION 'ACCESS_DENIED: You can only publish your own events.' USING ERRCODE = 'P0006';
  END IF;
  IF v_event.status <> 'draft' THEN
    RAISE EXCEPTION 'INVALID_STATUS: Only draft events can be published. Current status: %', v_event.status
      USING ERRCODE = 'P0021';
  END IF;

  UPDATE public.events SET status = 'published' WHERE id = p_event_id RETURNING * INTO v_event;

  RETURN json_build_object(
    'event_id', v_event.id,
    'title',    v_event.title,
    'status',   v_event.status
  );
END;
$$;


-- ===============================================================
-- FUNCTION 4: close_event
-- Organizer transitions: published → closed
-- ===============================================================
CREATE OR REPLACE FUNCTION public.close_event(p_event_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organizer_id UUID;
  v_event        public.events%ROWTYPE;
BEGIN
  v_organizer_id := public.assert_organizer();

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0020';
  END IF;
  IF v_event.organizer_id <> v_organizer_id THEN
    RAISE EXCEPTION 'ACCESS_DENIED: You can only close your own events.' USING ERRCODE = 'P0006';
  END IF;
  IF v_event.status <> 'published' THEN
    RAISE EXCEPTION 'INVALID_STATUS: Only published events can be closed. Current status: %', v_event.status
      USING ERRCODE = 'P0021';
  END IF;

  UPDATE public.events SET status = 'closed' WHERE id = p_event_id RETURNING * INTO v_event;

  RETURN json_build_object(
    'event_id', v_event.id,
    'title',    v_event.title,
    'status',   v_event.status
  );
END;
$$;


-- ===============================================================
-- FUNCTION 5: get_event_details
-- Returns event details + seat counts + caller's registration status.
-- Works for both students and organizers.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.get_event_details(p_event_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid              UUID;
  v_event            public.events%ROWTYPE;
  v_organizer_name   TEXT;
  v_registered_count INTEGER;
  v_available_seats  INTEGER;
  v_my_status        TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Fetch event
  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0020';
  END IF;

  -- Students can only see published events
  IF v_event.status <> 'published' THEN
    IF v_event.organizer_id <> v_uid THEN
      RAISE EXCEPTION 'EVENT_NOT_FOUND: Event is not publicly available.' USING ERRCODE = 'P0020';
    END IF;
  END IF;

  -- Organizer name
  SELECT name INTO v_organizer_name FROM public.profiles WHERE id = v_event.organizer_id;

  -- Count active registrations
  SELECT COUNT(*) INTO v_registered_count
  FROM public.registrations
  WHERE event_id = p_event_id AND status = 'registered';

  v_available_seats := GREATEST(v_event.seat_limit - v_registered_count, 0);

  -- My registration status
  SELECT status INTO v_my_status
  FROM public.registrations
  WHERE event_id = p_event_id AND student_id = v_uid;

  IF NOT FOUND THEN
    v_my_status := 'not_registered';
  END IF;

  RETURN json_build_object(
    'event_id',          v_event.id,
    'title',             v_event.title,
    'description',       v_event.description,
    'category',          v_event.category,
    'event_date',        v_event.event_date,
    'venue',             v_event.venue,
    'status',            v_event.status,
    'seat_limit',        v_event.seat_limit,
    'registered_count',  v_registered_count,
    'available_seats',   v_available_seats,
    'organizer_id',      v_event.organizer_id,
    'organizer_name',    v_organizer_name,
    'my_registration',   v_my_status,
    'created_at',        v_event.created_at,
    'updated_at',        v_event.updated_at
  );
END;
$$;

COMMENT ON FUNCTION public.get_event_details IS
  'Returns full event details, seat counts, and the caller''s own registration status.';


-- ===============================================================
-- FUNCTION 6: register_for_event
-- CONCURRENCY-SAFE student registration.
-- Uses SELECT FOR UPDATE on the event row to serialize concurrent
-- registrations — two students cannot race to claim the last seat.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.register_for_event(p_event_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_student_id       UUID;
  v_event            public.events%ROWTYPE;
  v_registered_count INTEGER;
  v_existing         public.registrations%ROWTYPE;
  v_reg              public.registrations%ROWTYPE;
BEGIN
  -- 1. Auth + role
  v_student_id := public.assert_student();

  -- 2. Lock the event row — serializes concurrent registrations
  SELECT * INTO v_event
  FROM public.events
  WHERE id = p_event_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND: Event does not exist.' USING ERRCODE = 'P0020';
  END IF;

  -- 3. Event must be published
  IF v_event.status <> 'published' THEN
    IF v_event.status = 'draft' THEN
      RAISE EXCEPTION 'EVENT_NOT_PUBLISHED: This event is not yet open for registration.' USING ERRCODE = 'P0022';
    ELSIF v_event.status = 'closed' THEN
      RAISE EXCEPTION 'EVENT_CLOSED: This event is no longer accepting registrations.' USING ERRCODE = 'P0023';
    END IF;
  END IF;

  -- 4. Duplicate check (catches re-registration after cancellation too)
  SELECT * INTO v_existing
  FROM public.registrations
  WHERE event_id = p_event_id AND student_id = v_student_id;

  IF FOUND THEN
    IF v_existing.status = 'registered' THEN
      RAISE EXCEPTION 'DUPLICATE_REGISTRATION: You are already registered for this event.' USING ERRCODE = 'P0030';
    ELSIF v_existing.status = 'cancelled' THEN
      -- Allow re-registration after cancellation — update existing row
      UPDATE public.registrations
      SET status = 'registered', registered_at = NOW()
      WHERE id = v_existing.id
      RETURNING * INTO v_reg;

      -- Re-check seat limit after re-registration
      SELECT COUNT(*) INTO v_registered_count
      FROM public.registrations
      WHERE event_id = p_event_id AND status = 'registered';

      IF v_registered_count > v_event.seat_limit THEN
        -- Roll back
        UPDATE public.registrations SET status = 'cancelled' WHERE id = v_existing.id;
        RAISE EXCEPTION 'EVENT_FULL: This event is full. No seats available.' USING ERRCODE = 'P0031';
      END IF;

      RETURN json_build_object(
        'registration_id',  v_reg.id,
        'event_id',         p_event_id,
        'event_title',      v_event.title,
        'status',           v_reg.status,
        'registered_at',    v_reg.registered_at,
        'available_seats',  GREATEST(v_event.seat_limit - v_registered_count, 0)
      );
    END IF;
  END IF;

  -- 5. Count current active registrations (event row is locked, so this is safe)
  SELECT COUNT(*) INTO v_registered_count
  FROM public.registrations
  WHERE event_id = p_event_id AND status = 'registered';

  -- 6. Seat limit check
  IF v_registered_count >= v_event.seat_limit THEN
    RAISE EXCEPTION 'EVENT_FULL: This event is full. No seats available.' USING ERRCODE = 'P0031';
  END IF;

  -- 7. Insert registration
  INSERT INTO public.registrations (event_id, student_id, status)
  VALUES (p_event_id, v_student_id, 'registered')
  RETURNING * INTO v_reg;

  -- 8. Return
  RETURN json_build_object(
    'registration_id',  v_reg.id,
    'event_id',         p_event_id,
    'event_title',      v_event.title,
    'status',           v_reg.status,
    'registered_at',    v_reg.registered_at,
    'available_seats',  GREATEST(v_event.seat_limit - v_registered_count - 1, 0)
  );
END;
$$;

COMMENT ON FUNCTION public.register_for_event IS
  'Concurrency-safe student event registration using FOR UPDATE lock on event row.
   Validates: authenticated, student role, event published, not full, not duplicate.
   Allows re-registration after cancellation.';


-- ===============================================================
-- FUNCTION 7: cancel_registration
-- Student cancels their own active registration.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.cancel_registration(p_registration_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_student_id UUID;
  v_reg        public.registrations%ROWTYPE;
  v_event      public.events%ROWTYPE;
BEGIN
  v_student_id := public.assert_student();

  SELECT * INTO v_reg FROM public.registrations WHERE id = p_registration_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'REGISTRATION_NOT_FOUND' USING ERRCODE = 'P0040';
  END IF;
  IF v_reg.student_id <> v_student_id THEN
    RAISE EXCEPTION 'ACCESS_DENIED: You can only cancel your own registrations.' USING ERRCODE = 'P0006';
  END IF;
  IF v_reg.status <> 'registered' THEN
    RAISE EXCEPTION 'INVALID_STATUS: Only active registrations can be cancelled. Current status: %', v_reg.status
      USING ERRCODE = 'P0021';
  END IF;

  UPDATE public.registrations SET status = 'cancelled' WHERE id = p_registration_id RETURNING * INTO v_reg;

  SELECT title INTO v_event.title FROM public.events WHERE id = v_reg.event_id;

  RETURN json_build_object(
    'registration_id', v_reg.id,
    'event_id',        v_reg.event_id,
    'event_title',     v_event.title,
    'status',          v_reg.status
  );
END;
$$;


-- ===============================================================
-- FUNCTION 8: get_my_registrations
-- Student views their own registrations with event details.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.get_my_registrations(p_status TEXT DEFAULT NULL)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_student_id UUID;
  v_result     JSON;
BEGIN
  v_student_id := auth.uid();
  IF v_student_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('registered', 'cancelled') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Invalid status filter.' USING ERRCODE = 'P0010';
  END IF;

  SELECT COALESCE(
    json_agg(
      json_build_object(
        'registration_id', r.id,
        'status',          r.status,
        'registered_at',   r.registered_at,
        'event_id',        e.id,
        'event_title',     e.title,
        'event_category',  e.category,
        'event_date',      e.event_date,
        'event_venue',     e.venue,
        'event_status',    e.status
      )
      ORDER BY r.registered_at DESC
    ),
    '[]'::JSON
  ) INTO v_result
  FROM public.registrations r
  JOIN public.events e ON e.id = r.event_id
  WHERE r.student_id = v_student_id
    AND (p_status IS NULL OR r.status = p_status);

  RETURN v_result;
END;
$$;


-- ===============================================================
-- FUNCTION 9: get_event_participants
-- Organizer views participants for their own event.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.get_event_participants(p_event_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organizer_id UUID;
  v_event        public.events%ROWTYPE;
  v_result       JSON;
BEGIN
  v_organizer_id := public.assert_organizer();

  SELECT * INTO v_event FROM public.events WHERE id = p_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'EVENT_NOT_FOUND' USING ERRCODE = 'P0020';
  END IF;
  IF v_event.organizer_id <> v_organizer_id THEN
    RAISE EXCEPTION 'ACCESS_DENIED: You can only view participants for your own events.' USING ERRCODE = 'P0006';
  END IF;

  SELECT json_build_object(
    'event_id',          v_event.id,
    'event_title',       v_event.title,
    'seat_limit',        v_event.seat_limit,
    'registered_count',  (SELECT COUNT(*) FROM public.registrations WHERE event_id = p_event_id AND status = 'registered'),
    'available_seats',   GREATEST(
                           v_event.seat_limit - (SELECT COUNT(*) FROM public.registrations WHERE event_id = p_event_id AND status = 'registered'),
                           0
                         ),
    'participants', COALESCE(
      (
        SELECT json_agg(
          json_build_object(
            'registration_id', r.id,
            'student_name',    pr.name,
            'student_email',   pr.email,
            'status',          r.status,
            'registered_at',   r.registered_at
          )
          ORDER BY r.registered_at ASC
        )
        FROM public.registrations r
        JOIN public.profiles pr ON pr.id = r.student_id
        WHERE r.event_id = p_event_id
      ),
      '[]'::JSON
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_event_participants IS
  'Organizer-only: full participant list with names, emails, status. Validates ownership.';


-- ===============================================================
-- FUNCTION 10: get_organizer_dashboard
-- Returns dashboard summary for the logged-in organizer.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.get_organizer_dashboard()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_organizer_id UUID;
  v_result       JSON;
BEGIN
  v_organizer_id := public.assert_organizer();

  SELECT json_build_object(
    'organizer_id',       v_organizer_id,
    'total_events',       (SELECT COUNT(*)    FROM public.events WHERE organizer_id = v_organizer_id),
    'draft_events',       (SELECT COUNT(*)    FROM public.events WHERE organizer_id = v_organizer_id AND status = 'draft'),
    'published_events',   (SELECT COUNT(*)    FROM public.events WHERE organizer_id = v_organizer_id AND status = 'published'),
    'closed_events',      (SELECT COUNT(*)    FROM public.events WHERE organizer_id = v_organizer_id AND status = 'closed'),
    'total_registrations',(
      SELECT COUNT(*) FROM public.registrations r
      JOIN public.events e ON e.id = r.event_id
      WHERE e.organizer_id = v_organizer_id AND r.status = 'registered'
    ),
    'events', COALESCE(
      (
        SELECT json_agg(
          json_build_object(
            'event_id',           e.id,
            'title',              e.title,
            'category',           e.category,
            'event_date',         e.event_date,
            'status',             e.status,
            'seat_limit',         e.seat_limit,
            'registered_count',   (
              SELECT COUNT(*) FROM public.registrations r
              WHERE r.event_id = e.id AND r.status = 'registered'
            ),
            'available_seats',    GREATEST(
              e.seat_limit - (
                SELECT COUNT(*) FROM public.registrations r
                WHERE r.event_id = e.id AND r.status = 'registered'
              ), 0
            )
          )
          ORDER BY e.created_at DESC
        )
        FROM public.events e
        WHERE e.organizer_id = v_organizer_id
      ),
      '[]'::JSON
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_organizer_dashboard IS
  'Organizer dashboard: total events by status, total registrations, per-event seat counts.';


-- ===============================================================
-- FUNCTION 11: get_published_events
-- Students browse published events with optional filters.
-- ===============================================================
CREATE OR REPLACE FUNCTION public.get_published_events(
  p_category   TEXT       DEFAULT NULL,
  p_date_from  TIMESTAMPTZ DEFAULT NULL,
  p_date_to    TIMESTAMPTZ DEFAULT NULL,
  p_date_filter TEXT      DEFAULT NULL   -- 'today' | 'upcoming' | 'this_week'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    UUID;
  v_result JSON;
  v_from   TIMESTAMPTZ;
  v_to     TIMESTAMPTZ;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Resolve date_filter shortcuts
  IF p_date_filter = 'today' THEN
    v_from := DATE_TRUNC('day', NOW() AT TIME ZONE 'UTC');
    v_to   := v_from + INTERVAL '1 day';
  ELSIF p_date_filter = 'upcoming' THEN
    v_from := NOW();
    v_to   := NULL;
  ELSIF p_date_filter = 'this_week' THEN
    v_from := DATE_TRUNC('week', NOW() AT TIME ZONE 'UTC');
    v_to   := v_from + INTERVAL '7 days';
  ELSE
    -- Use explicit date range if provided
    v_from := p_date_from;
    v_to   := p_date_to;
  END IF;

  -- Validate category if provided
  IF p_category IS NOT NULL AND p_category NOT IN (
    'Technical','Cultural','Sports','Workshop','Seminar','Club','Other'
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Invalid category.' USING ERRCODE = 'P0010';
  END IF;

  SELECT COALESCE(
    json_agg(
      json_build_object(
        'event_id',          e.id,
        'title',             e.title,
        'description',       e.description,
        'category',          e.category,
        'event_date',        e.event_date,
        'venue',             e.venue,
        'seat_limit',        e.seat_limit,
        'status',            e.status,
        'organizer_name',    pr.name,
        'registered_count',  (
          SELECT COUNT(*) FROM public.registrations r
          WHERE r.event_id = e.id AND r.status = 'registered'
        ),
        'available_seats',   GREATEST(
          e.seat_limit - (
            SELECT COUNT(*) FROM public.registrations r
            WHERE r.event_id = e.id AND r.status = 'registered'
          ), 0
        ),
        'my_registration',   COALESCE(
          (SELECT status FROM public.registrations
           WHERE event_id = e.id AND student_id = v_uid),
          'not_registered'
        )
      )
      ORDER BY e.event_date ASC
    ),
    '[]'::JSON
  ) INTO v_result
  FROM public.events e
  JOIN public.profiles pr ON pr.id = e.organizer_id
  WHERE e.status = 'published'
    AND (p_category IS NULL OR e.category = p_category)
    AND (v_from    IS NULL OR e.event_date >= v_from)
    AND (v_to      IS NULL OR e.event_date <  v_to);

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_published_events IS
  'Browse published events with optional category and date filters.
   Returns seat counts and caller''s own registration status per event.
   Supports date_filter shortcuts: today, upcoming, this_week.';


-- ===============================================================
-- GRANT EXECUTE to authenticated users
-- (Internal role checks enforce what each role can actually do)
-- ===============================================================
GRANT EXECUTE ON FUNCTION public.create_event(TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,INTEGER)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_event(UUID,TEXT,TEXT,TEXT,TIMESTAMPTZ,TEXT,INTEGER)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_event(UUID)                                          TO authenticated;
GRANT EXECUTE ON FUNCTION public.close_event(UUID)                                            TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_event_details(UUID)                                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_for_event(UUID)                                     TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_registration(UUID)                                    TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_registrations(TEXT)                                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_event_participants(UUID)                                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_organizer_dashboard()                                     TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_published_events(TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT)      TO authenticated;
