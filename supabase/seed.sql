-- =============================================================
-- seed.sql — Test Data for Development
-- =============================================================
-- ⚠️  DO NOT RUN IN PRODUCTION
-- This file creates test users and queue entries for development.
-- Run after all migrations are applied.
-- =============================================================

-- ---------------------------------------------------------------
-- STEP 1: Note on test user creation
-- ---------------------------------------------------------------
-- Supabase Auth users must be created through the Supabase Dashboard
-- or the Auth API (not raw SQL INSERT into auth.users — that bypasses
-- password hashing and email triggers).
--
-- Create these users manually in Supabase Dashboard → Authentication → Users:
--
--   Student 1:
--     Email: student1@test.com
--     Password: TestPass123!
--
--   Student 2:
--     Email: student2@test.com
--     Password: TestPass123!
--
--   Admin:
--     Email: admin@test.com
--     Password: AdminPass123!
--
-- After creating them, the trigger will auto-create their profiles
-- with role = 'student'. Then run STEP 2 to elevate the admin.
-- ---------------------------------------------------------------


-- ---------------------------------------------------------------
-- STEP 2: Promote admin user
-- Run this AFTER creating admin@test.com in Supabase Dashboard.
-- Replace the email below if you used a different one.
-- ---------------------------------------------------------------
UPDATE public.profiles
SET role = 'admin'
WHERE email = 'admin@test.com';


-- ---------------------------------------------------------------
-- STEP 3: Verify profiles were created
-- ---------------------------------------------------------------
SELECT id, name, email, role, created_at
FROM public.profiles
ORDER BY created_at;


-- ---------------------------------------------------------------
-- STEP 4: Verify services exist
-- (Services are seeded in migration 002)
-- ---------------------------------------------------------------
SELECT id, name, avg_service_time, is_active
FROM public.services
ORDER BY name;


-- ---------------------------------------------------------------
-- STEP 5: Test queue flow (run after Step 1-4)
-- Replace UUIDs with actual IDs from your profiles/services.
-- ---------------------------------------------------------------

-- View service IDs
SELECT id, name FROM public.services;

-- View user IDs
SELECT id, email, role FROM public.profiles;


-- ---------------------------------------------------------------
-- STEP 6: Simulate queue entries (insert directly for test data)
-- Use actual UUIDs from the SELECT queries above.
-- ---------------------------------------------------------------

-- Example: Insert test queue entries (replace UUIDs with real ones)
-- These simulate the state AFTER two students have joined Accounts
-- and one has joined Library.

-- INSERT INTO public.queues (user_id, service_id, token_number, status)
-- VALUES
--   ('<student1_uuid>', '<accounts_uuid>', 1, 'waiting'),
--   ('<student2_uuid>', '<accounts_uuid>', 2, 'waiting'),
--   ('<student1_uuid>', '<library_uuid>',  1, 'waiting');


-- ---------------------------------------------------------------
-- STEP 7: Verify queue entries
-- ---------------------------------------------------------------
SELECT
  q.id,
  public.format_token(public.get_service_prefix(s.name), q.token_number) AS token,
  s.name AS service,
  q.status,
  p.email AS student,
  q.joined_at
FROM public.queues q
JOIN public.services s ON s.id = q.service_id
JOIN public.profiles p ON p.id = q.user_id
ORDER BY s.name, q.token_number;


-- ---------------------------------------------------------------
-- STEP 8: Check queue position for a specific entry
-- Replace queue_id with a real UUID from your queues table.
-- ---------------------------------------------------------------
-- SELECT public.get_queue_status('<queue_uuid>');


-- ---------------------------------------------------------------
-- STEP 9: Admin views Accounts queue
-- Must be run as admin user (set auth.uid() = admin user's UUID)
-- ---------------------------------------------------------------
-- SELECT public.get_service_queue('<accounts_service_uuid>');


-- ---------------------------------------------------------------
-- STEP 10: Admin calls next (for Accounts)
-- ---------------------------------------------------------------
-- SELECT public.admin_call_next('<accounts_service_uuid>');


-- ---------------------------------------------------------------
-- STEP 11: Admin completes the serving entry
-- ---------------------------------------------------------------
-- SELECT public.admin_complete_queue('<queue_uuid_of_serving_entry>');
