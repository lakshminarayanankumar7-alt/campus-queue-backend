-- =============================================================
-- tests/campus_event_pulse_test.sql
-- Campus Event Pulse — Complete Backend Test Suite
-- Run in Supabase SQL Editor after applying all migrations.
-- =============================================================


-- ---------------------------------------------------------------
-- TEST BLOCK 1: Schema Verification
-- ---------------------------------------------------------------

-- 1a. Profiles table has correct columns + role constraint
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'profiles'
ORDER BY ordinal_position;
-- Expected: id, name, email, role (default 'student'), created_at

-- 1b. Events table exists with correct columns
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'events'
ORDER BY ordinal_position;
-- Expected: id, organizer_id, title, description, category, event_date,
--           venue, seat_limit, status (default 'draft'), created_at, updated_at

-- 1c. Registrations table with unique constraint
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'registrations'
ORDER BY ordinal_position;
-- Expected: id, event_id, student_id, status (default 'registered'), registered_at, updated_at

-- 1d. Verify unique constraint exists on registrations
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_name = 'registrations' AND constraint_type = 'UNIQUE';
-- Expected: uq_registration_per_student_event

-- 1e. Verify all functions exist
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'create_event', 'update_event', 'publish_event', 'close_event',
    'get_event_details', 'register_for_event', 'cancel_registration',
    'get_my_registrations', 'get_event_participants',
    'get_organizer_dashboard', 'get_published_events'
  )
ORDER BY routine_name;
-- Expected: 11 rows


-- ---------------------------------------------------------------
-- TEST BLOCK 2: Role Constraint
-- ---------------------------------------------------------------

-- 2a. Attempt to insert invalid role (should fail)
-- INSERT INTO public.profiles (id, name, email, role)
-- VALUES (gen_random_uuid(), 'Test', 'test@x.com', 'superuser');
-- Expected error: violates check constraint "profiles_role_check"

-- 2b. Verify allowed roles pass
-- (Done via trigger when users register — not via direct insert)


-- ---------------------------------------------------------------
-- TEST BLOCK 3: Format Helpers
-- ---------------------------------------------------------------

-- 3a. Verify set_updated_at function exists
SELECT routine_name FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name = 'set_updated_at';
-- Expected: 1 row


-- ---------------------------------------------------------------
-- TEST BLOCK 4: RLS Verification
-- ---------------------------------------------------------------

-- 4a. RLS enabled on events
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'events';
-- Expected: rowsecurity = true

-- 4b. RLS enabled on registrations
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND tablename = 'registrations';
-- Expected: rowsecurity = true

-- 4c. List all RLS policies on events
SELECT policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'events'
ORDER BY policyname;
-- Expected: 5 policies (select_published, select_own_organizer,
--           insert_organizer, update_own_organizer, delete_own_draft_organizer)

-- 4d. List all RLS policies on registrations
SELECT policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'registrations'
ORDER BY policyname;
-- Expected: 4 policies


-- ---------------------------------------------------------------
-- TEST BLOCK 5: Positive Flow Tests
-- (Run after creating test users via Dashboard)
-- Use supabase.rpc() from JS, or log in as user in SQL Editor
-- ---------------------------------------------------------------

-- 5a. Organizer creates event → should get draft event back
-- SELECT public.create_event(
--   'Test Workshop', 'A test description for the workshop.',
--   'Workshop', NOW() + INTERVAL '5 days', 'Room 101', 50
-- );
-- Expected: { event_id, status: 'draft', seat_limit: 50 }

-- 5b. Organizer publishes event
-- SELECT public.publish_event('<event_uuid>');
-- Expected: { status: 'published' }

-- 5c. Student registers
-- SELECT public.register_for_event('<event_uuid>');
-- Expected: { status: 'registered', available_seats: 49 }

-- 5d. Event details shows correct seat count
-- SELECT public.get_event_details('<event_uuid>');
-- Expected: registered_count=1, available_seats=49, my_registration='registered'

-- 5e. Student views their registrations
-- SELECT public.get_my_registrations();
-- Expected: array with 1 entry

-- 5f. Organizer views participant list
-- SELECT public.get_event_participants('<event_uuid>');
-- Expected: participants array with student name + email

-- 5g. Organizer dashboard
-- SELECT public.get_organizer_dashboard();
-- Expected: total_events=1, published_events=1, total_registrations=1

-- 5h. Browse events with category filter
-- SELECT public.get_published_events('Workshop', NULL, NULL, NULL);
-- Expected: 1 event

-- 5i. Browse with date filter
-- SELECT public.get_published_events(NULL, NULL, NULL, 'upcoming');
-- Expected: all future published events

-- 5j. Organizer closes event
-- SELECT public.close_event('<event_uuid>');
-- Expected: { status: 'closed' }

-- 5k. Student cancels registration
-- SELECT public.cancel_registration('<registration_uuid>');
-- Expected: { status: 'cancelled' }


-- ---------------------------------------------------------------
-- TEST BLOCK 6: Negative / Security Tests
-- ---------------------------------------------------------------

-- 6a. Student tries to create event
-- (As student user) SELECT public.create_event(
--   'Fake Event','Description','Cultural',NOW()+INTERVAL '1 day','Room',10
-- );
-- Expected error: ACCESS_DENIED: Only organizers can perform this action.

-- 6b. Student tries to publish event
-- SELECT public.publish_event('<any_event_uuid>');
-- Expected error: ACCESS_DENIED

-- 6c. Organizer tries to edit another organizer's event
-- (As organizer2) SELECT public.update_event('<organizer1_event_uuid>', 'Hacked', NULL, NULL, NULL, NULL, NULL);
-- Expected error: ACCESS_DENIED: You can only edit your own events.

-- 6d. Duplicate registration
-- (Student1 already registered) SELECT public.register_for_event('<event_uuid>');
-- Expected error: DUPLICATE_REGISTRATION: You are already registered for this event.

-- 6e. Register for draft event
-- SELECT public.register_for_event('<draft_event_uuid>');
-- Expected error: EVENT_NOT_PUBLISHED

-- 6f. Register for closed event
-- SELECT public.register_for_event('<closed_event_uuid>');
-- Expected error: EVENT_CLOSED

-- 6g. Register when event is full
-- (After all 50 seats taken) SELECT public.register_for_event('<event_uuid>');
-- Expected error: EVENT_FULL: This event is full.

-- 6h. Student views another student's registrations (RLS test)
-- (As student2) SELECT * FROM public.registrations WHERE student_id = '<student1_uuid>';
-- Expected: 0 rows (RLS silently filters)

-- 6i. Student views private participant list
-- (As student) SELECT public.get_event_participants('<event_uuid>');
-- Expected error: ACCESS_DENIED: Only organizers can perform this action.

-- 6j. Organizer tries to view another organizer's participants
-- (As organizer2) SELECT public.get_event_participants('<organizer1_event_uuid>');
-- Expected error: ACCESS_DENIED: You can only view participants for your own events.

-- 6k. Unauthenticated access
-- (Logged out) SELECT public.get_published_events();
-- Expected error: NOT_AUTHENTICATED

-- 6l. Invalid category
-- SELECT public.create_event('T','D','InvalidCategory', NOW()+INTERVAL '1 day', 'V', 10);
-- Expected error: VALIDATION_ERROR: Invalid category.

-- 6m. Seat limit = 0
-- SELECT public.create_event('T','D','Cultural', NOW()+INTERVAL '1 day', 'V', 0);
-- Expected error: VALIDATION_ERROR: Seat limit must be a positive integer.

-- 6n. Publish already published event
-- SELECT public.publish_event('<already_published_uuid>');
-- Expected error: INVALID_STATUS: Only draft events can be published.

-- 6o. Close a draft event
-- SELECT public.close_event('<draft_event_uuid>');
-- Expected error: INVALID_STATUS: Only published events can be closed.


-- ---------------------------------------------------------------
-- TEST BLOCK 7: Concurrency Test
-- ---------------------------------------------------------------
-- 7a. Create event with seat_limit = 1
-- 7b. Simultaneously (two browser tabs/sessions):
--     Tab A (student1): SELECT public.register_for_event('<event_uuid>');
--     Tab B (student2): SELECT public.register_for_event('<event_uuid>');
-- Expected: Exactly ONE succeeds. The other gets EVENT_FULL.
-- The FOR UPDATE lock on the events row prevents over-booking.


-- ---------------------------------------------------------------
-- TEST BLOCK 8: Seat Count Accuracy
-- ---------------------------------------------------------------
-- 8a. After 3 registrations on event with seat_limit=50:
-- SELECT public.get_event_details('<event_uuid>');
-- Expected: registered_count=3, available_seats=47

-- 8b. After 1 cancellation:
-- Expected: registered_count=2, available_seats=48

-- 8c. Available seats never negative (GREATEST constraint):
-- Even if somehow registered_count > seat_limit, available_seats returns 0


-- ---------------------------------------------------------------
-- CLEANUP (Reset test data — dev only)
-- ---------------------------------------------------------------
-- DELETE FROM public.registrations;
-- DELETE FROM public.events;
-- (Profiles remain — re-delete test users from Auth Dashboard)
