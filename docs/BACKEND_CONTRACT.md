# 📋 Backend API Contract — For Member 1 (Frontend Developer)

> **Purpose:** This document tells Member 1 exactly what backend functions to call from the React frontend. Replace all dummy/mock data with these real Supabase calls.
>
> **Setup required first:** Member 2 must apply all SQL migrations and you must configure `.env` with the Supabase project URL and anon key.

---

## Quick Start

```bash
npm install @supabase/supabase-js
```

```js
// Import from the shared client (already configured)
import { supabase } from '../lib/supabaseClient.js';

// Import service helpers
import { loginUser, registerUser, getMyProfile } from '../lib/authService.js';
import { getActiveServices, joinQueue, getMyQueues, ... } from '../lib/queueService.js';
```

---

## Table of Contents

1. [Authentication Operations](#1-authentication-operations)
2. [Services Query](#2-services-query)
3. [Join Queue](#3-join-queue)
4. [My Queue Query](#4-my-queue-query)
5. [Queue Status (Position + Wait)](#5-queue-status-position--wait)
6. [Cancel Queue](#6-cancel-queue)
7. [Admin — View Service Queue](#7-admin--view-service-queue)
8. [Admin — Call Next](#8-admin--call-next)
9. [Admin — Complete Queue](#9-admin--complete-queue)
10. [Admin — Update Service](#10-admin--update-service)
11. [Error Handling](#11-error-handling)
12. [Role Checking](#12-role-checking)
13. [Data Types Reference](#13-data-types-reference)

---

## 1. Authentication Operations

### 1a. Register

```js
import { registerUser } from '../lib/authService.js';

const { user, session, error } = await registerUser({
  name:     'Alice Smith',
  email:    'alice@example.com',
  password: 'SecurePass123!',
});
```

| Field | Value |
|-------|-------|
| **Input** | `{ name: string, email: string, password: string }` |
| **Output** | `{ user: User, session: Session, error: null }` |
| **Auth required** | No |
| **On success** | Profile auto-created with `role = 'student'` |
| **Errors** | `"User already registered"`, `"Password too weak"` |

> ⚠️ After registration, Supabase may require email confirmation depending on your project settings. Check Dashboard → Auth → Email settings.

---

### 1b. Login

```js
import { loginUser } from '../lib/authService.js';

const { user, session, error } = await loginUser({
  email:    'alice@example.com',
  password: 'SecurePass123!',
});
```

| Field | Value |
|-------|-------|
| **Input** | `{ email: string, password: string }` |
| **Output** | `{ user: User, session: Session, error: null }` |
| **Auth required** | No |
| **Errors** | `"Invalid login credentials"` |

---

### 1c. Logout

```js
import { logoutUser } from '../lib/authService.js';

const { error } = await logoutUser();
```

| Field | Value |
|-------|-------|
| **Input** | None |
| **Output** | `{ error: null }` |
| **Auth required** | Yes |

---

### 1d. Get Current User Profile

```js
import { getMyProfile } from '../lib/authService.js';

const { profile, error } = await getMyProfile();
// profile = { id, name, email, role: 'student' | 'admin', created_at }
```

| Field | Value |
|-------|-------|
| **Input** | None |
| **Output** | `{ profile: Profile, error: null }` |
| **Auth required** | Yes |
| **Role** | Student or Admin |

---

### 1e. Listen for Auth State Changes

```js
import { onAuthStateChange } from '../lib/authService.js';

// Put this in your App component (useEffect)
const { data: { subscription } } = onAuthStateChange((event, session) => {
  if (event === 'SIGNED_IN')  { /* user logged in  */ }
  if (event === 'SIGNED_OUT') { /* user logged out */ }
});

// Clean up on unmount
return () => subscription.unsubscribe();
```

---

## 2. Services Query

### 2a. Get Active Services (for students to browse)

```js
import { getActiveServices } from '../lib/queueService.js';

const { services, error } = await getActiveServices();
```

**Response:**
```json
[
  {
    "id": "uuid-1",
    "name": "Accounts",
    "description": "Fee payment, receipts, scholarship queries...",
    "avg_service_time": 7,
    "is_active": true
  },
  {
    "id": "uuid-2",
    "name": "Library",
    "description": "Book borrowing, returns...",
    "avg_service_time": 5,
    "is_active": true
  },
  {
    "id": "uuid-3",
    "name": "Admin Office",
    "description": "Enrollment, document requests...",
    "avg_service_time": 10,
    "is_active": true
  }
]
```

| Field | Value |
|-------|-------|
| **Input** | None |
| **Output** | `{ services: Service[], error: null }` |
| **Auth required** | Yes |
| **Errors** | None expected |

---

## 3. Join Queue

```js
import { joinQueue } from '../lib/queueService.js';

const { data, error } = await joinQueue({
  serviceId: 'uuid-of-accounts-service',
});
```

**Success response:**
```json
{
  "queue_id": "uuid-abc",
  "token": "A-03",
  "token_number": 3,
  "service_id": "uuid-1",
  "service_name": "Accounts",
  "status": "waiting",
  "joined_at": "2026-09-25T10:30:00Z"
}
```

| Field | Value |
|-------|-------|
| **Input** | `{ serviceId: string (UUID) }` |
| **Output** | `{ data: QueueEntry, error: null }` |
| **Auth required** | Yes |
| **Role** | Student |
| **Errors** | |
| `"You must be logged in."` | Not authenticated |
| `"Service not found."` | Invalid service ID |
| `"This service is not currently available."` | `is_active = false` |
| `"You are already in the queue for this service. Token: A-02"` | Duplicate join attempt |

> **Important:** This calls a PostgreSQL function (`join_queue`) that generates tokens atomically. Never calculate tokens on the frontend.

---

## 4. My Queue Query

```js
import { getMyQueues } from '../lib/queueService.js';

// Get all my queues
const { queues, error } = await getMyQueues();

// Get only waiting queues
const { queues, error } = await getMyQueues({ status: 'waiting' });

// Get only completed/history
const { queues, error } = await getMyQueues({ status: 'completed' });
```

**Response:**
```json
[
  {
    "id": "queue-uuid",
    "token_number": 3,
    "token": "A-03",
    "status": "waiting",
    "joined_at": "2026-09-25T10:30:00Z",
    "served_at": null,
    "completed_at": null,
    "service_id": "service-uuid",
    "services": {
      "id": "service-uuid",
      "name": "Accounts",
      "avg_service_time": 7
    }
  }
]
```

| Field | Value |
|-------|-------|
| **Input** | `{ status?: 'waiting' | 'serving' | 'completed' | 'cancelled' }` |
| **Output** | `{ queues: QueueWithService[], error: null }` |
| **Auth required** | Yes |
| **Role** | Student (sees own only) |

---

## 5. Queue Status (Position + Wait)

```js
import { getQueueStatus } from '../lib/queueService.js';

const { data, error } = await getQueueStatus({
  queueId: 'queue-uuid-abc',
});
```

**Response for a waiting student:**
```json
{
  "queue_id": "uuid-abc",
  "token": "A-03",
  "token_number": 3,
  "service_name": "Accounts",
  "status": "waiting",
  "position": 3,
  "estimated_wait": 14,
  "avg_service_time": 7,
  "joined_at": "2026-09-25T10:30:00Z",
  "served_at": null,
  "completed_at": null
}
```

> `position: 3` means 2 people are ahead of this student (positions 1 and 2).
> `estimated_wait: 14` means approximately 14 minutes (2 people × 7 min each).

**Response for a serving student:**
```json
{
  "queue_id": "uuid-abc",
  "token": "A-01",
  "status": "serving",
  "position": null,
  "estimated_wait": null,
  "served_at": "2026-09-25T10:45:00Z"
}
```

| Field | Value |
|-------|-------|
| **Input** | `{ queueId: string (UUID) }` |
| **Output** | `{ data: QueueStatus, error: null }` |
| **Auth required** | Yes |
| **Role** | Student (own queue), Admin (any queue) |
| **Errors** | `"Queue entry not found."`, `"You can only check your own queue entries."` |

---

## 6. Cancel Queue

```js
import { cancelQueue } from '../lib/queueService.js';

const { data, error } = await cancelQueue({
  queueId: 'queue-uuid-abc',
});
```

**Success response:**
```json
{
  "queue_id": "uuid-abc",
  "token": "A-03",
  "service_name": "Accounts",
  "status": "cancelled"
}
```

| Field | Value |
|-------|-------|
| **Input** | `{ queueId: string (UUID) }` |
| **Output** | `{ data: CancelledEntry, error: null }` |
| **Auth required** | Yes |
| **Role** | Student (own entry only) |
| **Errors** | |
| `"Queue entry not found."` | Invalid queue ID |
| `"You can only cancel your own queue entries."` | Attempting to cancel someone else's |
| `"This action is not valid for the current queue status."` | Entry is not `waiting` (e.g., already serving) |

---

## 7. Admin — View Service Queue

```js
import { adminGetServiceQueue } from '../lib/queueService.js';

// Get all entries for Accounts
const { data, error } = await adminGetServiceQueue({
  serviceId: 'accounts-uuid',
});

// Get only waiting entries
const { data, error } = await adminGetServiceQueue({
  serviceId: 'accounts-uuid',
  status: 'waiting',
});
```

**Response:**
```json
{
  "service_id": "accounts-uuid",
  "service_name": "Accounts",
  "prefix": "A",
  "queue": [
    {
      "queue_id": "uuid-1",
      "token": "A-01",
      "token_number": 1,
      "status": "serving",
      "user_id": "student1-uuid",
      "student_name": "Alice Smith",
      "student_email": "alice@example.com",
      "joined_at": "2026-09-25T10:20:00Z",
      "served_at": "2026-09-25T10:30:00Z",
      "completed_at": null
    },
    {
      "queue_id": "uuid-2",
      "token": "A-02",
      "token_number": 2,
      "status": "waiting",
      "student_name": "Bob Jones",
      "joined_at": "2026-09-25T10:25:00Z",
      "served_at": null,
      "completed_at": null
    }
  ]
}
```

| Field | Value |
|-------|-------|
| **Input** | `{ serviceId: UUID, status?: string }` |
| **Output** | `{ data: ServiceQueue, error: null }` |
| **Auth required** | Yes |
| **Role** | **Admin only** |
| **Errors** | `"You do not have permission for this action."` (if student tries) |

---

## 8. Admin — Call Next

```js
import { adminCallNext } from '../lib/queueService.js';

const { data, error } = await adminCallNext({
  serviceId: 'accounts-uuid',
});
```

**Success response:**
```json
{
  "queue_id": "uuid-2",
  "token": "A-02",
  "service_name": "Accounts",
  "status": "serving",
  "served_at": "2026-09-25T10:45:00Z"
}
```

| Field | Value |
|-------|-------|
| **Input** | `{ serviceId: UUID }` |
| **Output** | `{ data: ServedEntry, error: null }` |
| **Auth required** | Yes |
| **Role** | **Admin only** |
| **Errors** | |
| `"No students are currently waiting in this queue."` | Empty queue |
| `"You do not have permission for this action."` | Not admin |

> **Concurrency safe:** Two admins cannot call the same person simultaneously.

---

## 9. Admin — Complete Queue

```js
import { adminCompleteQueue } from '../lib/queueService.js';

const { data, error } = await adminCompleteQueue({
  queueId: 'queue-uuid-being-served',
});
```

**Success response:**
```json
{
  "queue_id": "uuid-1",
  "token": "A-01",
  "service_name": "Accounts",
  "status": "completed",
  "completed_at": "2026-09-25T10:50:00Z"
}
```

| Field | Value |
|-------|-------|
| **Input** | `{ queueId: UUID }` |
| **Output** | `{ data: CompletedEntry, error: null }` |
| **Auth required** | Yes |
| **Role** | **Admin only** |
| **Errors** | |
| `"Queue entry not found."` | Invalid queue ID |
| `"This action is not valid for the current queue status."` | Entry is not `serving` |

---

## 10. Admin — Update Service

```js
import { adminUpdateService } from '../lib/queueService.js';

// Deactivate a service (students can't join)
const { service, error } = await adminUpdateService({
  serviceId: 'library-uuid',
  updates: { is_active: false },
});

// Update average service time
const { service, error } = await adminUpdateService({
  serviceId: 'accounts-uuid',
  updates: { avg_service_time: 10 },
});
```

| Field | Value |
|-------|-------|
| **Input** | `{ serviceId: UUID, updates: Partial<Service> }` |
| **Output** | `{ service: Service, error: null }` |
| **Auth required** | Yes |
| **Role** | **Admin only** (RLS enforced) |

---

## 11. Error Handling

All functions follow the same pattern:

```js
const { data, error } = await joinQueue({ serviceId });

if (error) {
  // error is a human-readable string
  console.error('Failed to join queue:', error);
  // Show to user: toast notification, alert, error state, etc.
  return;
}

// Success - use data
console.log('Joined queue:', data.token);
```

**Error messages are already formatted for display to users.** They come from `parseError()` in `queueService.js` which translates database error codes into friendly strings.

---

## 12. Role Checking

```js
import { getMyProfile } from '../lib/authService.js';

const { profile } = await getMyProfile();

if (profile.role === 'admin') {
  // Show admin dashboard
} else {
  // Show student dashboard
}
```

> **Security note:** Even if a student somehow gets `role = 'admin'` into their local state, all admin API calls check the role in the database (via RLS). Unauthorized calls will return an error.

---

## 13. Data Types Reference

### Token Format
```
A-01  →  Accounts, first student
A-09  →  Accounts, ninth student
A-10  →  Accounts, tenth student
L-01  →  Library, first student
L-07  →  Library, seventh student
```

### Status Values
```
waiting   →  In queue, waiting to be called
serving   →  Being served right now
completed →  Service done
cancelled →  Student cancelled their spot
```

### Status Transitions
```
Allowed (student):
  waiting → cancelled

Allowed (admin):
  waiting  → serving   (via admin_call_next)
  serving  → completed (via admin_complete_queue)

NOT allowed:
  serving  → waiting
  completed → anything
  cancelled → anything
```

### Complete Workflow Example (Full)

```js
// Student joins queue
const { data: queueEntry } = await joinQueue({ serviceId: accountsId });
console.log(queueEntry.token); // "A-03"

// Student checks position
const { data: status } = await getQueueStatus({ queueId: queueEntry.queue_id });
console.log(`Position: ${status.position}, Wait: ~${status.estimated_wait} min`);
// "Position: 3, Wait: ~14 min"

// Admin calls next (from admin panel)
const { data: called } = await adminCallNext({ serviceId: accountsId });
console.log(called.token); // "A-01"

// Admin completes service
const { data: done } = await adminCompleteQueue({ queueId: called.queue_id });
console.log(done.status); // "completed"
```

---

## Quick Reference Summary

| Operation | Function | Type | Auth | Role |
|-----------|----------|------|------|------|
| Register | `registerUser()` | Auth | No | - |
| Login | `loginUser()` | Auth | No | - |
| Logout | `logoutUser()` | Auth | Yes | Any |
| Get Profile | `getMyProfile()` | Direct SDK | Yes | Any |
| Get Services | `getActiveServices()` | Direct SDK | Yes | Any |
| Join Queue | `joinQueue()` | RPC | Yes | Student |
| My Queues | `getMyQueues()` | Direct SDK | Yes | Student |
| Queue Status | `getQueueStatus()` | RPC | Yes | Student/Admin |
| Cancel Queue | `cancelQueue()` | RPC | Yes | Student |
| Admin Queue View | `adminGetServiceQueue()` | RPC | Yes | Admin |
| Admin Call Next | `adminCallNext()` | RPC | Yes | Admin |
| Admin Complete | `adminCompleteQueue()` | RPC | Yes | Admin |
| Admin Update Service | `adminUpdateService()` | Direct SDK | Yes | Admin |
