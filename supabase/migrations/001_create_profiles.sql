-- =============================================================
-- Migration 001: Create profiles table
-- Run this first in your Supabase SQL Editor
-- =============================================================

-- Enable UUID extension (usually already enabled in Supabase)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------------------------------------------------------------
-- Table: profiles
-- Stores public-facing user information and role.
-- The id column MUST match the authenticated user's ID from
-- Supabase Auth (auth.users table).
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  email       TEXT NOT NULL,
  role        TEXT NOT NULL DEFAULT 'student'
                CHECK (role IN ('student', 'admin')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for quick role lookups (used in RLS policies)
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);

-- ---------------------------------------------------------------
-- Trigger function: auto-create profile when a user registers
-- This runs server-side (trusted), so the user cannot fake
-- their role — it always starts as 'student'.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, name, email, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', 'User'),
    NEW.email,
    'student'  -- Always default to student; admin must be set via SQL
  );
  RETURN NEW;
END;
$$;

-- Attach trigger to auth.users (fires after every new registration)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

COMMENT ON TABLE public.profiles IS
  'User profile records. ID matches auth.users. Role defaults to student.';
COMMENT ON COLUMN public.profiles.role IS
  'Either student or admin. Never trust a role value from the browser — it is set server-side.';
