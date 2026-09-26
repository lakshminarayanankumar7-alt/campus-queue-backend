-- =============================================================
-- supabase/seed_events.sql
-- Campus Event Pulse — Test Data Setup
-- =============================================================
-- ⚠️ DO NOT RUN IN PRODUCTION
-- Run AFTER all migrations 006–010 are applied.
--
-- STEP 1: Create test users via Supabase Dashboard
--   → Authentication → Users → Add User → Create New User
--
--   student1@test.com  / TestPass123!
--   student2@test.com  / TestPass123!
--   organizer1@test.com / OrgPass123!
--   organizer2@test.com / OrgPass123!
--
-- STEP 2: The trigger will create profiles with:
--   student1, student2   → role = 'student'    (no metadata needed)
--   organizer1, organizer2 → need role = 'organizer' in metadata
--
-- For organizers created via dashboard (no metadata), promote them:
-- =============================================================

-- STEP 3: Promote organizer users
UPDATE public.profiles SET role = 'organizer' WHERE email = 'organizer1@test.com';
UPDATE public.profiles SET role = 'organizer' WHERE email = 'organizer2@test.com';

-- STEP 4: Verify profiles
SELECT id, email, role, name FROM public.profiles ORDER BY role, email;

-- STEP 5: Verify services table (from old queue system, unrelated)
-- SELECT * FROM public.services;  -- Old system, ignore

-- STEP 6: View events (empty initially)
SELECT * FROM public.events;

-- =============================================================
-- MANUAL TEST FLOW
-- (Run via supabase.rpc() from the frontend or use SQL below
--  with auth context set to the correct user)
-- =============================================================

-- As organizer1, create events:
-- SELECT public.create_event(
--   'Python Workshop',
--   'Learn Python basics and data structures in this hands-on workshop.',
--   'Workshop',
--   NOW() + INTERVAL '3 days',
--   'CS Lab 101',
--   30
-- );

-- SELECT public.create_event(
--   'Annual Cultural Fest',
--   'A celebration of music, dance, and art from across the college.',
--   'Cultural',
--   NOW() + INTERVAL '7 days',
--   'Main Auditorium',
--   200
-- );

-- SELECT public.create_event(
--   'Inter-College Cricket',
--   'Cricket tournament between top college teams.',
--   'Sports',
--   NOW() + INTERVAL '14 days',
--   'Sports Ground',
--   500
-- );

-- Publish first event:
-- SELECT public.publish_event('<event_uuid>');

-- As student1, register:
-- SELECT public.register_for_event('<event_uuid>');

-- Check position/details:
-- SELECT public.get_event_details('<event_uuid>');

-- As organizer1, view participants:
-- SELECT public.get_event_participants('<event_uuid>');

-- View organizer dashboard:
-- SELECT public.get_organizer_dashboard();

-- As student1, view registrations:
-- SELECT public.get_my_registrations();

-- Browse events with filters:
-- SELECT public.get_published_events('Workshop', NULL, NULL, NULL);
-- SELECT public.get_published_events(NULL, NULL, NULL, 'upcoming');
-- SELECT public.get_published_events(NULL, NULL, NULL, 'this_week');

-- Cancel registration:
-- SELECT public.cancel_registration('<registration_uuid>');

-- Close event:
-- SELECT public.close_event('<event_uuid>');
