# College Queue Management System

A digital queue management system for college departments and student services.

## Project Structure

```
plan a/
├── .env.example              # Environment variable template (copy to .env)
├── .gitignore                # Excludes secrets and build artifacts
│
├── supabase/
│   ├── migrations/
│   │   ├── 001_create_profiles.sql    # Profiles table + auth trigger
│   │   ├── 002_create_services.sql    # Services table + initial data
│   │   ├── 003_create_queues.sql      # Queues table + constraints
│   │   ├── 004_rls_policies.sql       # Row Level Security policies
│   │   └── 005_queue_functions.sql    # Queue management functions
│   ├── seed.sql              # Test data setup guide
│   └── README.md             # Full backend documentation
│
├── src/
│   └── lib/
│       ├── supabaseClient.js  # Shared Supabase client instance
│       ├── authService.js     # Auth: register, login, logout, profile
│       └── queueService.js    # Queue: join, status, cancel, admin ops
│
├── docs/
│   ├── BACKEND_CONTRACT.md   # API contract for Member 1 (frontend)
│   └── TESTING_GUIDE.md      # How to test everything
│
└── tests/
    └── queue_flow_test.sql   # SQL-based test queries
```

## Team

- **Member 1**: Frontend (React + Vite)
- **Member 2**: Backend/Database (Supabase + PostgreSQL)

## Quick Start (Backend Setup)

1. Create a [Supabase](https://supabase.com) project
2. Copy `.env.example` to `.env` and fill in your project URL + anon key
3. Apply migrations in order via Supabase SQL Editor
4. Create test users in Supabase Dashboard → Authentication
5. Promote admin user via SQL: `UPDATE profiles SET role='admin' WHERE email='admin@test.com'`

See [supabase/README.md](supabase/README.md) for full setup documentation.

## Core Workflow

```
LOGIN → JOIN QUEUE → TOKEN GENERATED → ADMIN VIEWS → CALL NEXT → COMPLETE
```

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React + Vite (Member 1) |
| Auth | Supabase Auth |
| Database | PostgreSQL (via Supabase) |
| API | PostgREST (automatic via Supabase) |
| Security | Row Level Security (RLS) |
| Client SDK | @supabase/supabase-js |

## Git Branch Strategy

```
main
 └── backend/database   ← Member 2's work
 └── frontend/ui        ← Member 1's work
```
