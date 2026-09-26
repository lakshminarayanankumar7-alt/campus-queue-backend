-- =============================================================
-- Migration 006: Extend profiles role for Campus Event Pulse
-- =============================================================
-- The existing profiles table has CHECK (role IN ('student','admin')).
-- Campus Event Pulse needs 'organizer' role.
-- This migration safely extends the constraint.
--
-- Run AFTER 001_create_profiles.sql is already applied.
-- If you have NOT run migration 001 yet, run it first.
-- =============================================================

-- ---------------------------------------------------------------
-- Step 1: Drop the existing role CHECK constraint
-- PostgreSQL requires dropping the old constraint by name before
-- adding a new one. The constraint name matches what migration 001
-- created implicitly — named by PostgreSQL as profiles_role_check.
-- We use a safe approach: alter the column.
-- ---------------------------------------------------------------
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

-- ---------------------------------------------------------------
-- Step 2: Add updated CHECK allowing student, organizer, admin
-- 'admin' is kept for backward compatibility with existing queue system.
-- ---------------------------------------------------------------
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('student', 'organizer', 'admin'));

-- ---------------------------------------------------------------
-- Step 3: Update the trigger so new users can register as organizer
-- The trigger now reads raw_user_meta_data->>'role' if provided.
-- If not provided (or invalid), defaults to 'student'.
-- This replaces the old handle_new_user() from migration 001.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  -- Read intended role from signup metadata; validate it
  v_role := COALESCE(NEW.raw_user_meta_data->>'role', 'student');

  -- Only allow safe roles via self-signup — never 'admin'
  IF v_role NOT IN ('student', 'organizer') THEN
    v_role := 'student';
  END IF;

  INSERT INTO public.profiles (id, name, email, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', 'User'),
    NEW.email,
    v_role
  );
  RETURN NEW;
END;
$$;

-- Trigger already exists from migration 001 — no need to recreate
-- The function replacement above is sufficient.

COMMENT ON COLUMN public.profiles.role IS
  'student, organizer, or admin. Set server-side by trigger. Never trust browser input.';
