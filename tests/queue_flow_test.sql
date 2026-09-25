-- =============================================================
-- tests/queue_flow_test.sql
-- =============================================================
-- SQL-based tests for the queue management backend.
-- Run these in Supabase SQL Editor after applying all migrations
-- and creating test users via the dashboard.
--
-- These tests verify both POSITIVE flow and NEGATIVE security.
-- Run each block sequentially. Read comments carefully.
-- =============================================================

-- ---------------------------------------------------------------
-- SETUP: Get the UUIDs we'll need for all tests
-- Run this block first and note the IDs.
-- ---------------------------------------------------------------

-- Get service IDs
SELECT id, name, avg_service_time FROM public.services ORDER BY name;

-- Get profile IDs
SELECT id, email, role FROM public.profiles ORDER BY email;


-- ---------------------------------------------------------------
-- TEST BLOCK 1: POSITIVE — Full Queue Flow
-- ---------------------------------------------------------------
-- NOTE: PostgreSQL functions use auth.uid() to identify the caller.
-- To simulate different users in SQL Editor, you can only test as
-- the currently logged-in user. Use the Supabase JS SDK in your
-- app to test as different users simultaneously.
-- The function-level tests below validate the logic as admin.
-- ---------------------------------------------------------------

-- 1a. View active services (as any authenticated user)
SELECT id, name, description, avg_service_time
FROM public.services
WHERE is_active = TRUE
ORDER BY name;

-- Expected: Library, Accounts, Admin Office (all 3 visible)


-- 1b. Join Accounts queue as Student 1
-- Replace 'ACCOUNTS_UUID' with actual ID from the SELECT above
-- SELECT public.join_queue('ACCOUNTS_UUID');

-- Expected response:
-- {
--   "queue_id": "<uuid>",
--   "token": "A-01",
--   "token_number": 1,
--   "service_name": "Accounts",
--   "status": "waiting",
--   "joined_at": "<timestamp>"
-- }


-- 1c. Join Accounts queue as Student 2
-- (Log in as student2@test.com and run this)
-- SELECT public.join_queue('ACCOUNTS_UUID');
-- Expected token: A-02


-- 1d. Join Library queue as Student 1
-- (Log in as student1@test.com and run this)
-- SELECT public.join_queue('LIBRARY_UUID');
-- Expected token: L-01


-- 1e. Admin views Accounts queue
-- (Log in as admin@test.com and run this)
-- SELECT public.get_service_queue('ACCOUNTS_UUID', 'waiting');
-- Expected: A-01 (student1) and A-02 (student2) both waiting


-- 1f. Admin calls next for Accounts
-- SELECT public.admin_call_next('ACCOUNTS_UUID');
-- Expected: A-01 → serving


-- 1g. Check queue status as Student 1
-- SELECT public.get_queue_status('STUDENT1_ACCOUNTS_QUEUE_UUID');
-- Expected: status=serving, position=null (already serving)


-- 1h. Check queue position as Student 2 (A-02, position 1 — next up)
-- SELECT public.get_queue_status('STUDENT2_ACCOUNTS_QUEUE_UUID');
-- Expected: position=1, estimated_wait=7 (1 × 7 min avg)


-- 1i. Admin completes A-01
-- SELECT public.admin_complete_queue('STUDENT1_ACCOUNTS_QUEUE_UUID');
-- Expected: A-01 → completed


-- 1j. Admin calls next again
-- SELECT public.admin_call_next('ACCOUNTS_UUID');
-- Expected: A-02 → serving


-- ---------------------------------------------------------------
-- TEST BLOCK 2: NEGATIVE SECURITY TESTS
-- ---------------------------------------------------------------
-- These should all fail with appropriate error messages.
-- ---------------------------------------------------------------

-- 2a. Student joins inactive service
-- First, deactivate a service:
UPDATE public.services SET is_active = FALSE WHERE name = 'Library';

-- Then try to join (as any student):
-- SELECT public.join_queue('LIBRARY_UUID');
-- Expected error: SERVICE_INACTIVE

-- Reactivate it:
UPDATE public.services SET is_active = TRUE WHERE name = 'Library';


-- 2b. Student joins same active service twice
-- (After Student 1 already joined Accounts as A-01 and it's waiting)
-- SELECT public.join_queue('ACCOUNTS_UUID');  -- as student1
-- Expected error: DUPLICATE_QUEUE: You are already in the queue...


-- 2c. Admin calls next on empty queue
-- (After all students have been completed/cancelled)
-- SELECT public.admin_call_next('ACCOUNTS_UUID');
-- Expected error: QUEUE_EMPTY


-- 2d. Verify RLS: Student cannot see another student's queue entries
-- (Log in as student2 and try:)
-- SELECT * FROM public.queues WHERE user_id = '<student1_uuid>';
-- Expected: 0 rows returned (RLS filters it out silently)


-- 2e. Verify RLS: Student cannot change their role
-- (Log in as student1 and try:)
-- UPDATE public.profiles SET role = 'admin' WHERE id = auth.uid();
-- Expected: error or 0 rows updated (RLS WITH CHECK prevents this)


-- 2f. Student tries to complete their own queue (not allowed)
-- (Log in as student1 — only waiting→cancelled is allowed)
-- SELECT public.admin_complete_queue('STUDENT1_QUEUE_UUID');
-- Expected error: ACCESS_DENIED


-- 2g. Student tries to call next (not allowed)
-- SELECT public.admin_call_next('ACCOUNTS_UUID');
-- Expected error: ACCESS_DENIED


-- 2h. Invalid service ID
-- SELECT public.join_queue('00000000-0000-0000-0000-000000000000');
-- Expected error: SERVICE_NOT_FOUND


-- 2i. Invalid queue ID for complete
-- SELECT public.admin_complete_queue('00000000-0000-0000-0000-000000000000');
-- Expected error: QUEUE_NOT_FOUND (or ACCESS_DENIED if not admin)


-- 2j. Unauthenticated access test
-- Log out and try any RPC call or table read.
-- SELECT * FROM public.queues;
-- Expected: 0 rows (RLS blocks unauthenticated access)
-- SELECT public.join_queue('ACCOUNTS_UUID');
-- Expected error: NOT_AUTHENTICATED


-- 2k. Student tries to cancel a serving entry (already being served)
-- (After A-01 is set to serving by admin:)
-- SELECT public.cancel_queue('STUDENT1_ACCOUNTS_QUEUE_UUID');
-- Expected error: INVALID_STATUS (can only cancel 'waiting' entries)


-- ---------------------------------------------------------------
-- TEST BLOCK 3: CONCURRENCY SIMULATION
-- (These can't easily be tested in SQL Editor — use JS instead)
-- ---------------------------------------------------------------

-- 3a. Two students join simultaneously
-- Run these at the same time from two browser tabs/sessions:
--   Tab A (student1): joinQueue({ serviceId: 'ACCOUNTS_UUID' })
--   Tab B (student2): joinQueue({ serviceId: 'ACCOUNTS_UUID' })
-- Expected: One gets A-01, the other gets A-02 (never duplicate)

-- 3b. Two admins call next simultaneously
-- Open two admin sessions and call:
--   Admin A: adminCallNext({ serviceId: 'ACCOUNTS_UUID' })
--   Admin B: adminCallNext({ serviceId: 'ACCOUNTS_UUID' })
-- Expected: One gets the first entry, the other gets the second
--           (never both get the same entry — SKIP LOCKED prevents it)


-- ---------------------------------------------------------------
-- TEST BLOCK 4: TOKEN FORMAT VERIFICATION
-- ---------------------------------------------------------------

SELECT
  public.format_token('A', 1)  AS expected_A01,
  public.format_token('A', 9)  AS expected_A09,
  public.format_token('A', 10) AS expected_A10,
  public.format_token('L', 1)  AS expected_L01,
  public.format_token('O', 5)  AS expected_O05;

-- Expected: A-01, A-09, A-10, L-01, O-05


SELECT
  public.get_service_prefix('Library')      AS lib_prefix,    -- L
  public.get_service_prefix('Accounts')     AS acc_prefix,    -- A
  public.get_service_prefix('Admin Office') AS admin_prefix;  -- A

-- ⚠️  NOTE: Both Accounts and Admin Office start with 'A'.
-- This is expected behaviour — token prefixes reflect the first letter.
-- If you need them unique, rename 'Admin Office' to 'Office' → 'O'
-- or change the prefix logic in get_service_prefix().


-- ---------------------------------------------------------------
-- TEST BLOCK 5: CLEANUP
-- ---------------------------------------------------------------
-- Remove test queue entries (keeps services and profiles)
-- ONLY run this to reset for fresh testing:
-- DELETE FROM public.queues;
