# 🎓 Campus Event Pulse — Backend Documentation

> **Role: Backend / Database Developer**
> Built with Supabase · PostgreSQL · RLS · SECURITY DEFINER Functions

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Database Schema](#3-database-schema)
4. [Authentication & Roles](#4-authentication--roles)
5. [Row Level Security](#5-row-level-security)
6. [Database Functions (API)](#6-database-functions-api)
7. [Service Layer (JS)](#7-service-layer-js)
8. [Migration Guide](#8-migration-guide)
9. [Test Data Setup](#9-test-data-setup)
10. [Testing Guide](#10-testing-guide)
11. [Security Notes](#11-security-notes)
12. [Frontend Integration Contract](#12-frontend-integration-contract)

---

## 1. Project Overview

Campus Event Pulse is a college campus event management platform.

**Students** discover and register for events.
**Organizers** create, manage, and monitor events.

The backend uses:
- **Supabase** (hosted PostgreSQL + Auth + PostgREST API)
- **PostgreSQL SECURITY DEFINER functions** for all trusted business logic
- **Row Level Security** for database-level access control
- **Supabase JS SDK** as the client interface

---

## 2. Architecture

```
React Frontend
      ↓  (Supabase JS SDK)
Supabase PostgREST API
      ↓  (SQL query / RPC)
PostgreSQL Database
      ↓  (RLS checks every row)
Row Level Security

For trusted operations (registration, event management):
React → supabase.rpc() → SECURITY DEFINER function → PostgreSQL
```

### Co-existing Systems

This project runs alongside the existing Queue Management system.
The queue tables (`services`, `queues`) and functions are untouched.
Campus Event Pulse adds new tables (`events`, `registrations`) and new functions.

---

## 3. Database Schema

### Table: `profiles` (extended)

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | Matches `auth.users.id` |
| `name` | TEXT NOT NULL | Display name |
| `email` | TEXT NOT NULL | User email |
| `role` | TEXT NOT NULL | `student` \| `organizer` \| `admin` (default: `student`) |
| `created_at` | TIMESTAMPTZ | Auto-set |

> **Role is set server-side by the database trigger.** The trigger reads `raw_user_meta_data->>'role'` from signup metadata. If role is not `student` or `organizer`, it defaults to `student`. Admin can only be set via SQL by a DBA.

---

### Table: `events`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | Auto-generated |
| `organizer_id` | UUID FK | References `auth.users(id)` |
| `title` | TEXT NOT NULL | Non-empty CHECK |
| `description` | TEXT NOT NULL | Non-empty CHECK |
| `category` | TEXT NOT NULL | `Technical` \| `Cultural` \| `Sports` \| `Workshop` \| `Seminar` \| `Club` \| `Other` |
| `event_date` | TIMESTAMPTZ NOT NULL | Event date/time |
| `venue` | TEXT NOT NULL | Non-empty CHECK |
| `seat_limit` | INTEGER NOT NULL | Must be > 0 |
| `status` | TEXT NOT NULL | `draft` → `published` → `closed` (default: `draft`) |
| `created_at` | TIMESTAMPTZ | Auto-set |
| `updated_at` | TIMESTAMPTZ | Auto-updated by trigger |

**Indexes:** `organizer_id`, `status`, `category`, `event_date`, `(status, event_date)`

---

### Table: `registrations`

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | Auto-generated |
| `event_id` | UUID FK | References `events(id)` ON DELETE CASCADE |
| `student_id` | UUID FK | References `auth.users(id)` ON DELETE CASCADE |
| `status` | TEXT NOT NULL | `registered` \| `cancelled` (default: `registered`) |
| `registered_at` | TIMESTAMPTZ | Auto-set |
| `updated_at` | TIMESTAMPTZ | Auto-updated by trigger |

**Unique constraint:** `(event_id, student_id)` — prevents double registration at DB level.

**Indexes:** `student_id`, `event_id`, `(event_id, status)`

---

### Relationships

```
auth.users (1) ──── (1) profiles
auth.users (1) ──── (N) events          [as organizer]
auth.users (1) ──── (N) registrations   [as student]
events     (1) ──── (N) registrations
```

---

## 4. Authentication & Roles

### Registration Flow

```
User signs up (student or organizer)
      ↓
Supabase Auth creates auth.users record
      ↓
Trigger handle_new_user() fires
      ↓
Profile created with validated role
(never 'admin' via self-signup)
```

### Roles

| Role | Can do |
|------|--------|
| `student` | Browse published events, register, view own registrations, cancel |
| `organizer` | Create/edit/publish/close own events, view participants, dashboard |
| `admin` | (Legacy from queue system — set only via DBA SQL) |

### Creating Organizer Accounts

**Method A (programmatic):** Call `registerOrganizer()` from `authService.js`. This passes `role: 'organizer'` in signup metadata; the trigger sets the role.

**Method B (dashboard):** Create user in Auth Dashboard, then run:
```sql
UPDATE public.profiles SET role = 'organizer' WHERE email = 'user@domain.com';
```

---

## 5. Row Level Security

### events table

| Policy | Operation | Rule |
|--------|-----------|------|
| `events_select_published` | SELECT | Any authenticated user can read `status = 'published'` |
| `events_select_own_organizer` | SELECT | Organizer can read all their own events (any status) |
| `events_insert_organizer` | INSERT | Organizer can insert for themselves only |
| `events_update_own_organizer` | UPDATE | Organizer can update only their own events |
| `events_delete_own_draft_organizer` | DELETE | Organizer can delete only own draft events |

### registrations table

| Policy | Operation | Rule |
|--------|-----------|------|
| `registrations_select_own_student` | SELECT | Student sees own registrations |
| `registrations_select_event_organizer` | SELECT | Organizer sees registrations for own events |
| `registrations_insert_own_student` | INSERT | Student inserts for themselves only |
| `registrations_update_own_student` | UPDATE | Student updates own registration only |

---

## 6. Database Functions (API)

All called via `supabase.rpc('function_name', params)`.

| Function | Role | Purpose |
|----------|------|---------|
| `create_event(title, description, category, event_date, venue, seat_limit)` | Organizer | Create new draft event |
| `update_event(event_id, title?, ...)` | Organizer | Patch own event (partial update) |
| `publish_event(event_id)` | Organizer | draft → published |
| `close_event(event_id)` | Organizer | published → closed |
| `get_event_details(event_id)` | Any | Event + seat counts + my registration status |
| `register_for_event(event_id)` | Student | Concurrency-safe registration |
| `cancel_registration(registration_id)` | Student | Cancel own active registration |
| `get_my_registrations(status?)` | Student | Own registration history |
| `get_event_participants(event_id)` | Organizer | Participant list (own event only) |
| `get_organizer_dashboard()` | Organizer | Summary stats + per-event counts |
| `get_published_events(category?, date_from?, date_to?, date_filter?)` | Any | Browse with filters |

### Concurrency Safety

`register_for_event()` uses `SELECT ... FOR UPDATE` on the `events` row before counting registrations and inserting. This serializes concurrent registrations per event — two students cannot simultaneously claim the last seat.

### Status Transitions (enforced in functions)

```
Events:      draft → published → closed   (only forward)
Registration: registered → cancelled      (can re-register after cancel)
```

---

## 7. Service Layer (JS)

| File | Imports | Exports |
|------|---------|---------|
| `src/lib/supabaseClient.js` | — | `supabase`, `getCurrentUser`, `getSession` |
| `src/lib/authService.js` | `supabaseClient` | `registerUser`, `registerOrganizer`, `loginUser`, `logoutUser`, `getMyProfile`, `updateMyName`, `onAuthStateChange` |
| `src/lib/eventService.js` | `supabaseClient`, `_errorParser` | `getPublishedEvents`, `getEventDetails`, `createEvent`, `updateEvent`, `publishEvent`, `closeEvent`, `getMyEvents` |
| `src/lib/registrationService.js` | `supabaseClient`, `_errorParser` | `registerForEvent`, `cancelRegistration`, `getMyRegistrations` |
| `src/lib/organizerService.js` | `supabaseClient`, `_errorParser` | `getOrganizerDashboard`, `getEventParticipants` |
| `src/lib/_errorParser.js` | — | `parseEventError` (shared error translator) |

---

## 8. Migration Guide

Apply migrations **in this order** in Supabase SQL Editor:

### Old Queue System (apply first if not already done)
1. `001_create_profiles.sql`
2. `002_create_services.sql`
3. `003_create_queues.sql`
4. `004_rls_policies.sql`
5. `005_queue_functions.sql`

### Campus Event Pulse (new — apply after queue migrations)
6. `006_extend_profiles_for_events.sql` — Adds `organizer` role, updates trigger
7. `007_create_events.sql` — Events table, indexes, updated_at trigger
8. `008_create_registrations.sql` — Registrations table, unique constraint
9. `009_rls_policies_events.sql` — RLS for events + registrations
10. `010_event_functions.sql` — All 11 SECURITY DEFINER functions

> All migrations use `IF NOT EXISTS`, `CREATE OR REPLACE`, and `DROP ... IF EXISTS` making them **safe to re-run** without errors.

---

## 9. Test Data Setup

1. Go to **Supabase Dashboard → Authentication → Users → Add User**
2. Create:
   - `student1@test.com` / `TestPass123!`
   - `student2@test.com` / `TestPass123!`
   - `organizer1@test.com` / `OrgPass123!`
   - `organizer2@test.com` / `OrgPass123!`
3. Run in SQL Editor:
   ```sql
   UPDATE public.profiles SET role = 'organizer' WHERE email IN ('organizer1@test.com','organizer2@test.com');
   ```
4. Follow `supabase/seed_events.sql` for test event queries.

---

## 10. Testing Guide

See `tests/campus_event_pulse_test.sql` for the full SQL test suite covering:

- Schema verification (columns, constraints, indexes, functions)
- RLS policy existence
- Positive flow (create → publish → register → complete)
- 15 negative security tests
- Concurrency test (last-seat race condition)
- Seat count accuracy

---

## 11. Security Notes

| Risk | Mitigation |
|------|-----------|
| Student creates events | `assert_organizer()` inside all event mutation functions; RLS INSERT policy requires organizer role |
| Organizer edits another's event | `organizer_id = auth.uid()` check inside every update/publish/close function |
| Student sees other's registrations | RLS `USING (student_id = auth.uid())` on registrations |
| Student sees participant list | `assert_organizer()` in `get_event_participants()` |
| Double registration | `UNIQUE(event_id, student_id)` DB constraint + function-level check |
| Overbooking | `FOR UPDATE` lock in `register_for_event()` serializes per-event inserts |
| Role self-escalation | Trigger validates role metadata; `admin` never allowed via self-signup |
| Service-role key exposure | Never in any frontend file; only anon key in `.env` |
| SQL injection | All user input passes through parameterized RPC calls |

---

## 12. Frontend Integration Contract

### Available seats calculation
```
available_seats = GREATEST(seat_limit - COUNT(registrations WHERE status='registered'), 0)
```
Always returned by `get_event_details()`, `get_published_events()`, `get_event_participants()`, `get_organizer_dashboard()`.

### Registration status values
- `registered` — active registration
- `cancelled` — student cancelled
- `not_registered` — student has never registered (returned by `get_event_details`)

### Event status values
- `draft` — not visible to students
- `published` — visible and registrable
- `closed` — visible but not registrable

### Date filter shortcuts for `get_published_events`
- `'today'` — events starting today
- `'upcoming'` — all future events
- `'this_week'` — events in the current week
- Pass `dateFrom`/`dateTo` for custom range

### Error format
All service functions return `{ data: null, error: 'Human readable string' }` on failure.
Display `error` directly to users.
