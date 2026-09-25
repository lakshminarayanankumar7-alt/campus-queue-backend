# 🗄️ Backend Documentation — College Queue Management System

> **Member 2 — Backend/Database**
> Built with Supabase · PostgreSQL · Supabase Auth · RLS · PostgREST

---

## Table of Contents

1. [Technology Explained in Plain English](#1-technology-explained-in-plain-english)
2. [System Architecture](#2-system-architecture)
3. [Database Tables](#3-database-tables)
4. [Authentication Flow](#4-authentication-flow)
5. [Row Level Security (RLS)](#5-row-level-security-rls)
6. [Queue Logic](#6-queue-logic)
7. [Token Format](#7-token-format)
8. [Database Functions (API)](#8-database-functions-api)
9. [How to Set Up the Project](#9-how-to-set-up-the-project)
10. [How to Apply Migrations](#10-how-to-apply-migrations)
11. [How to Create Test Data](#11-how-to-create-test-data)
12. [Environment Variables](#12-environment-variables)
13. [Admin Role Setup](#13-admin-role-setup)
14. [Git Workflow](#14-git-workflow)
15. [Security Notes](#15-security-notes)

---

## 1. Technology Explained in Plain English

### What is Supabase?
Supabase is a **Backend-as-a-Service** platform. Think of it as a complete backend toolkit that handles the database, user authentication, file storage, and APIs — all in one place. Instead of building a server from scratch, you configure Supabase and it does the heavy lifting. It is open-source and based on PostgreSQL.

### What is PostgreSQL?
PostgreSQL (often called Postgres) is a **relational database** — like a very powerful spreadsheet where data is stored in tables with rows and columns. It supports advanced features like JSON, constraints, triggers and functions. Supabase uses PostgreSQL as its core database.

### What is Supabase Auth?
Supabase Auth is the **authentication system**. It handles:
- User registration (creating accounts)
- Password hashing (never stored as plain text)
- Login sessions (keeping users logged in)
- JWT tokens (proof that someone is logged in)

You never store or touch passwords yourself. Supabase Auth handles all of that securely.

### What is an API?
An API (Application Programming Interface) is how two programs talk to each other. The frontend (React) sends requests like "give me all services" or "I want to join the queue." The backend receives those requests and responds with data. Think of it like a waiter — you give your order (request), the kitchen makes the food (process), and the waiter brings it back (response).

### What is PostgREST?
PostgREST is a tool that automatically turns your PostgreSQL database tables into REST APIs. When you create a table called `services`, PostgREST automatically creates an API endpoint for it at `/rest/v1/services`. Supabase includes PostgREST built-in, so the frontend can query the database without you writing separate API server code.

### What is the Supabase JavaScript SDK?
The Supabase JS SDK (`@supabase/supabase-js`) is a JavaScript library that makes it easy for the frontend to communicate with Supabase. Instead of manually writing HTTP requests, you write simple code like:
```js
const { data } = await supabase.from('services').select('*');
```
The SDK handles authentication headers, error handling, and talking to the Supabase API.

### What is RLS (Row Level Security)?
RLS is a PostgreSQL feature that controls **which rows of a table a user can see or modify**. Think of it as a security guard at the database level. Even if someone bypasses the frontend entirely and tries to call the API directly, the database will only return rows that the security policies allow. Students can only see their own queue entries. Admins can see all entries. The database enforces this — not just the frontend.

### What is an Edge Function?
Edge Functions are small server-side TypeScript programs that run on Supabase's servers (Deno runtime). Use them when you need logic that absolutely cannot run in the browser — like sending emails, processing payments, or accessing secret API keys. **For this MVP, we don't need Edge Functions** because PostgreSQL SECURITY DEFINER functions handle all our trusted logic safely.

---

## 2. System Architecture

### Standard Flow (most operations)
```
React Frontend
      ↓  (uses Supabase JS SDK)
Supabase API (PostgREST)
      ↓  (SQL query)
PostgreSQL Database
      ↓  (checks every row)
Row Level Security Policies
      ↓  (returns only allowed data)
Response back to Frontend
```

### Trusted Operations Flow (queue join, call next, complete)
```
React Frontend
      ↓  (supabase.rpc('function_name', params))
Supabase API
      ↓  (calls function with SECURITY DEFINER)
PostgreSQL Function (runs as trusted role)
      ↓  (can bypass RLS for specific operations)
PostgreSQL Database
      ↓
Response back to Frontend
```

**Why two flows?** Simple reads (get services, get my profile) work fine with direct table access and RLS. Complex operations like joining a queue need concurrency protection (preventing two students from getting the same token number) — that requires PostgreSQL functions running server-side.

---

## 3. Database Tables

### Table: `profiles`
Stores user information and roles. Every user in `auth.users` has exactly one row here.

| Column       | Type        | Notes |
|-------------|-------------|-------|
| `id`         | UUID (PK)   | Same as `auth.users.id` |
| `name`       | text        | Display name |
| `email`      | text        | User email |
| `role`       | text        | `student` or `admin` (default: `student`) |
| `created_at` | timestamptz | Auto-set on creation |

**Security:** Role is always set to `student` by the server-side trigger. Students cannot change their own role to `admin`.

---

### Table: `services`
The departments or counters students can queue for.

| Column             | Type        | Notes |
|-------------------|-------------|-------|
| `id`               | UUID (PK)   | Auto-generated |
| `name`             | text        | Unique name (Library, Accounts, Admin Office) |
| `description`      | text        | Description |
| `is_active`        | boolean     | If false, students cannot join |
| `avg_service_time` | integer     | Minutes per student (used for wait estimate) |
| `created_at`       | timestamptz | Auto-set |

**Initial services:**

| Service      | Avg Time | Prefix |
|-------------|----------|--------|
| Accounts     | 7 min    | A-     |
| Admin Office | 10 min   | A-     |
| Library      | 5 min    | L-     |

---

### Table: `queues`
One row per student per queue entry. Tracks the full lifecycle.

| Column         | Type        | Notes |
|---------------|-------------|-------|
| `id`           | UUID (PK)   | Auto-generated |
| `user_id`      | UUID (FK)   | References `auth.users.id` |
| `service_id`   | UUID (FK)   | References `services.id` |
| `token_number` | integer     | Sequence per service (1, 2, 3...) |
| `status`       | text        | `waiting` → `serving` → `completed` or `cancelled` |
| `joined_at`    | timestamptz | When student joined |
| `served_at`    | timestamptz | When admin called them |
| `completed_at` | timestamptz | When service completed |

**Unique constraints:**
- A student cannot have two `waiting` or `serving` entries for the same service
- Two entries cannot have the same `token_number` for the same service while active

---

## 4. Authentication Flow

```
Student clicks Register
        ↓
Provide: name, email, password
        ↓
Supabase Auth creates auth.users record (password is hashed, never stored plain)
        ↓
PostgreSQL trigger fires: handle_new_user()
        ↓
Trigger creates profiles row with role = 'student'
        ↓
Student can now log in
        ↓
Supabase Auth returns session + JWT token
        ↓
Frontend stores session (persists across refreshes)
        ↓
All subsequent API calls include the JWT token automatically
```

**Admin accounts** are created the same way (register normally), then a database administrator runs:
```sql
UPDATE public.profiles SET role = 'admin' WHERE email = 'admin@yourdomain.com';
```
This must be done via the Supabase SQL Editor with service-role access — not through the frontend.

---

## 5. Row Level Security (RLS)

RLS is enabled on all three tables. Here's what each role can do:

### Student Permissions
| Action | Table | Rule |
|--------|-------|------|
| SELECT | profiles | Own row only |
| UPDATE | profiles | Own row, name only (not role) |
| SELECT | services | Active services only |
| INSERT | queues | Own entries only (via function) |
| SELECT | queues | Own entries only |
| UPDATE | queues | Own entry, only `waiting → cancelled` |

### Admin Permissions
| Action | Table | Rule |
|--------|-------|------|
| SELECT | profiles | All profiles |
| SELECT | services | All services (including inactive) |
| UPDATE | services | Can toggle is_active, update settings |
| SELECT | queues | All queue entries |
| UPDATE | queues | Any entry (for status transitions) |

### What students CANNOT do (enforced by database):
- ❌ See another student's queue entries
- ❌ Change their role to `admin`
- ❌ Mark a queue as `completed` or `serving`
- ❌ Join an inactive service
- ❌ Join the same service twice while already waiting/serving
- ❌ Change token numbers

---

## 6. Queue Logic

### Full Workflow
```
Student selects a service
        ↓
Student clicks Join Queue
        ↓
join_queue() function called (concurrency-safe)
        ↓
Token generated: e.g., A-03
        ↓
Queue entry created with status = 'waiting'
        ↓
Student sees their position: e.g., Position 3, ~21 min wait
        ↓
Admin views the queue (all waiting entries in order)
        ↓
Admin clicks Call Next
        ↓
admin_call_next() selects oldest waiting entry → sets serving
        ↓
Admin serves the student physically
        ↓
Admin clicks Complete
        ↓
admin_complete_queue() sets status = completed
        ↓
Process repeats for next waiting student
```

### Position Calculation
```
Position = (number of 'waiting' entries with earlier joined_at) + 1
```
Example: 3 entries joined before yours → your position = 4

### Estimated Wait Calculation
```
Estimated wait = (position - 1) × avg_service_time
```
Example: Position 4, avg = 7 min → wait = 3 × 7 = 21 minutes

These are calculated live from current queue state — not stored — so they always reflect the latest situation.

---

## 7. Token Format

Tokens are **per-service sequential numbers** with a letter prefix derived from the service name.

```
Service       Prefix   Tokens
-----------   ------   ----------------
Library        L        L-01, L-02, L-03
Accounts       A        A-01, A-02, A-03
Admin Office   A        A-01, A-02, A-03
```

> ⚠️ **Note:** Both "Accounts" and "Admin Office" start with 'A'. If you want unique prefixes, rename "Admin Office" to "Office" (prefix O). Tokens are formatted with zero-padding: `LPAD(number::TEXT, 2, '0')`.

**Concurrency safety:** The `join_queue()` function uses `SELECT ... FOR UPDATE` on the service row while calculating the next token number. This means only one join can proceed at a time per service, preventing two students from getting the same token.

---

## 8. Database Functions (API)

All complex operations use PostgreSQL `SECURITY DEFINER` functions called via `supabase.rpc()`.

| Function | Called By | Purpose |
|----------|-----------|---------|
| `join_queue(p_service_id)` | Student | Join a queue, get token |
| `get_queue_status(p_queue_id)` | Student/Admin | Get position + wait time |
| `cancel_queue(p_queue_id)` | Student | Cancel own waiting entry |
| `get_service_queue(p_service_id, p_status)` | Admin | Full queue view |
| `admin_call_next(p_service_id)` | Admin | Move next waiting → serving |
| `admin_complete_queue(p_queue_id)` | Admin | Move serving → completed |
| `format_token(prefix, number)` | Helper | Format token string |
| `get_service_prefix(name)` | Helper | Get prefix from service name |

**Why SECURITY DEFINER?** These functions run with elevated database privileges, similar to a trusted server process. They validate the caller's identity and role internally, then perform operations that require bypassing RLS for specific steps (like reading all queue entries to find the next one). The regular user never gets direct elevated access.

---

## 9. How to Set Up the Project

### Step 1: Create a Supabase Project
1. Go to [supabase.com](https://supabase.com)
2. Sign up / Log in
3. Click **New Project**
4. Choose a name, region, and database password
5. Wait for the project to be ready (~1 minute)

### Step 2: Get Your API Keys
1. Go to your project dashboard
2. Click **Settings** → **API**
3. Copy:
   - **Project URL** (e.g., `https://abcdef.supabase.co`)
   - **Anon public key** (safe for browser use)
4. **Never copy the service_role key into frontend code**

### Step 3: Configure Environment Variables
```bash
# In your project root:
cp .env.example .env
# Edit .env and fill in your URL and anon key
```

### Step 4: Install Dependencies (when frontend is ready)
```bash
npm install @supabase/supabase-js
```

---

## 10. How to Apply Migrations

Migrations are SQL files in `supabase/migrations/`. Apply them **in order** using the Supabase SQL Editor.

1. Go to Supabase Dashboard → **SQL Editor**
2. Click **New Query**
3. Copy and paste the content of each migration file, in order:
   - `001_create_profiles.sql`
   - `002_create_services.sql`
   - `003_create_queues.sql`
   - `004_rls_policies.sql`
   - `005_queue_functions.sql`
4. Click **Run** after each one
5. Verify no errors appear

> If you see "already exists" errors on re-running, that's fine — all statements use `IF NOT EXISTS` and `ON CONFLICT DO NOTHING`.

---

## 11. How to Create Test Data

### Create Test Users (Dashboard Method)
1. Go to Supabase Dashboard → **Authentication** → **Users**
2. Click **Add User** → **Create New User** for each:
   - `student1@test.com` / `TestPass123!`
   - `student2@test.com` / `TestPass123!`
   - `admin@test.com` / `AdminPass123!`
3. The trigger will auto-create their profiles as `student`

### Promote Admin User
In **SQL Editor**, run:
```sql
UPDATE public.profiles
SET role = 'admin'
WHERE email = 'admin@test.com';
```

### Verify
```sql
SELECT id, email, role FROM public.profiles;
SELECT id, name, is_active FROM public.services;
```

See `supabase/seed.sql` for the full step-by-step test data guide.

---

## 12. Environment Variables

| Variable | Where | Purpose |
|----------|-------|---------|
| `VITE_SUPABASE_URL` | Frontend `.env` | Your Supabase project URL |
| `VITE_SUPABASE_ANON_KEY` | Frontend `.env` | Public anon key for browser |

**Never** put `SUPABASE_SERVICE_ROLE_KEY` in any frontend file or commit it to git.

---

## 13. Admin Role Setup

**Why can't admins self-register as admin?**
The registration trigger always sets `role = 'student'`. This prevents anyone from signing up as an admin through the normal registration form. Admin status must be explicitly granted by someone with database access.

**To create an admin:**
1. Have the person register normally (gets `student` role)
2. A database administrator runs the SQL update above
3. That person now has admin privileges on next login

---

## 14. Git Workflow

```bash
# Create and switch to backend branch
git checkout -b backend/database

# Stage backend files
git add supabase/ src/lib/ tests/ .env.example .gitignore

# Commit with meaningful messages
git commit -m "feat: create supabase database schema"
git commit -m "feat: add authentication and profiles trigger"
git commit -m "feat: implement queue management functions"
git commit -m "feat: add row level security policies"
git commit -m "test: add queue flow test data and SQL tests"
git commit -m "docs: add backend API documentation"

# Push to remote
git push origin backend/database
```

**Files that must NEVER be committed:**
- `.env` (contains real secrets)
- Any file with actual API keys or passwords

---

## 15. Security Notes

| Risk | Mitigation |
|------|-----------|
| Student self-elevates to admin | RLS WITH CHECK prevents role update; trigger forces 'student' on registration |
| Two students get same token | `SELECT FOR UPDATE` on service row in `join_queue()` |
| Two admins call same entry | `FOR UPDATE SKIP LOCKED` in `admin_call_next()` |
| Frontend bypasses UI to access others' data | RLS on all tables enforces row-level access |
| Service-role key exposed | Never in frontend code; only used by trusted server processes |
| Unauthenticated API access | RLS requires `auth.uid() IS NOT NULL` for all reads/writes |
| Student marks queue as completed | Only admin-role functions can set `serving` or `completed` status |
