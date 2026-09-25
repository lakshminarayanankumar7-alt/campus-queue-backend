# Testing Guide — College Queue Management System Backend

## Overview

This guide explains how to test the backend end-to-end after applying all migrations.

---

## Prerequisites

- All 5 migration files applied in Supabase SQL Editor (in order)
- Three test users created in Supabase Auth Dashboard:
  - `student1@test.com` / `TestPass123!`
  - `student2@test.com` / `TestPass123!`
  - `admin@test.com` / `AdminPass123!`
- Admin promoted: `UPDATE public.profiles SET role = 'admin' WHERE email = 'admin@test.com';`

---

## Test 1: Token Format

Run in SQL Editor (any user):
```sql
SELECT
  public.format_token('A', 1)  AS "A-01",
  public.format_token('A', 9)  AS "A-09",
  public.format_token('A', 10) AS "A-10",
  public.format_token('L', 1)  AS "L-01";
```
Expected: `A-01`, `A-09`, `A-10`, `L-01` ✓

---

## Test 2: Positive Queue Flow

Using the Supabase JS SDK (or run in frontend):

```js
// 1. Login as student1
const { session } = await loginUser({ email: 'student1@test.com', password: 'TestPass123!' });

// 2. Get services
const { services } = await getActiveServices();
const accountsId = services.find(s => s.name === 'Accounts').id;
const libraryId  = services.find(s => s.name === 'Library').id;

// 3. Student1 joins Accounts → should get A-01
const { data: q1 } = await joinQueue({ serviceId: accountsId });
console.assert(q1.token === 'A-01', 'Token should be A-01');

// 4. Student1 joins Library → should get L-01
const { data: q2 } = await joinQueue({ serviceId: libraryId });
console.assert(q2.token === 'L-01', 'Token should be L-01');

// 5. Login as student2, join Accounts → should get A-02
await logoutUser();
await loginUser({ email: 'student2@test.com', password: 'TestPass123!' });
const { data: q3 } = await joinQueue({ serviceId: accountsId });
console.assert(q3.token === 'A-02', 'Token should be A-02');

// 6. Check student2's position (should be 2, wait = 7 min)
const { data: status } = await getQueueStatus({ queueId: q3.queue_id });
console.assert(status.position === 2, 'Position should be 2');
console.assert(status.estimated_wait === 7, 'Wait should be 7 min');

// 7. Login as admin, view Accounts queue
await logoutUser();
await loginUser({ email: 'admin@test.com', password: 'AdminPass123!' });
const { data: serviceQueue } = await adminGetServiceQueue({ serviceId: accountsId, status: 'waiting' });
console.assert(serviceQueue.queue.length === 2, 'Should see 2 waiting entries');

// 8. Admin calls next → A-01 becomes serving
const { data: called } = await adminCallNext({ serviceId: accountsId });
console.assert(called.token === 'A-01', 'A-01 should be called');
console.assert(called.status === 'serving', 'Status should be serving');

// 9. Admin completes A-01
const { data: completed } = await adminCompleteQueue({ queueId: called.queue_id });
console.assert(completed.status === 'completed', 'Status should be completed');

// 10. Admin calls next → A-02 becomes serving
const { data: called2 } = await adminCallNext({ serviceId: accountsId });
console.assert(called2.token === 'A-02', 'A-02 should be called');
console.assert(called2.status === 'serving', 'Status should be serving');

console.log('✅ All positive flow tests passed!');
```

---

## Test 3: Negative Security Tests

```js
// Login as student1
await loginUser({ email: 'student1@test.com', password: 'TestPass123!' });

// 3a: Join inactive service
await adminUpdateService({ serviceId: libraryId, updates: { is_active: false } });
// (Login as student1 again)
const { error: inactiveErr } = await joinQueue({ serviceId: libraryId });
console.assert(inactiveErr.includes('not currently available'), '3a: Should reject inactive service');

// 3b: Join same service twice
const { error: dupErr } = await joinQueue({ serviceId: accountsId });
console.assert(dupErr.includes('already in the queue'), '3b: Should reject duplicate');

// 3c: Try admin operation as student
const { error: callErr } = await adminCallNext({ serviceId: accountsId });
console.assert(callErr.includes('permission'), '3c: Student cannot call next');

// 3d: Try to complete as student
const { error: completeErr } = await adminCompleteQueue({ queueId: 'some-uuid' });
console.assert(completeErr.includes('permission'), '3d: Student cannot complete');

// 3e: Admin queue empty
await loginUser({ email: 'admin@test.com', password: 'AdminPass123!' });
// (after all students are completed)
const { error: emptyErr } = await adminCallNext({ serviceId: accountsId });
console.assert(emptyErr.includes('No students'), '3e: Empty queue error');

console.log('✅ All negative security tests passed!');
```

---

## Test 4: SQL-Level RLS Verification

Run in Supabase SQL Editor (logged in as student1):

```sql
-- Student1 cannot see student2's queues
SELECT * FROM public.queues WHERE user_id = '<student2_uuid>';
-- Expected: 0 rows

-- Student1 cannot change own role
UPDATE public.profiles SET role = 'admin' WHERE id = auth.uid();
-- Expected: 0 rows updated (no error, but silently blocked)

-- Verify role unchanged
SELECT role FROM public.profiles WHERE id = auth.uid();
-- Expected: 'student'
```

---

## Checklist

### Positive Flow
- [ ] Register creates profile with role = student
- [ ] Login works and returns session
- [ ] Active services are visible
- [ ] Student1 joins Accounts → A-01
- [ ] Student2 joins Accounts → A-02 (not A-01)
- [ ] Student1 joins Library → L-01
- [ ] Queue position is correct (position 2 = 1 person ahead)
- [ ] Estimated wait = people_ahead × avg_service_time
- [ ] Admin sees all queue entries
- [ ] Admin calls next → oldest waiting becomes serving
- [ ] Admin completes → serving becomes completed
- [ ] Student can cancel own waiting entry

### Negative Security
- [ ] Joining inactive service is rejected
- [ ] Joining same service twice is rejected
- [ ] Student cannot call next
- [ ] Student cannot complete queue
- [ ] Student cannot see other students' queues
- [ ] Student cannot change own role to admin
- [ ] Empty queue returns clear error
- [ ] Invalid service ID returns error
- [ ] Invalid queue ID returns error
- [ ] Unauthenticated access returns no data
