# Feature 14 — Subject Access Schema Blocker Report

## Status

**Execution stopped before implementation.** No application source, Cloud Functions, Firestore Rules, database schema, tests, or UI files were modified.

The implementation cannot proceed past the Subject Access phase because the approved database specification does not provide a separate Subject Access Assignment structure, while the accepted Feature 14 specification explicitly requires one.

## Evidence from the approved database specification

`05_DATABASE.md` defines the current flow as:

```text
Approval
  ↓
Student (student_type assigned)
  ↓
Default Free Plan available implicitly
  ↓
Subject Subscription (explicit, created on first subject access or upgrade)
```

It defines `subscriptions` as subject-scoped, but it does not define a separate `subject_access_assignments` collection, a `subject_access` collection, or an approved Subject Access field on an existing document.

The current specification therefore contains subscription data, but not the required independent assignment representing:

```text
student + subject + enabled
```

## Required data from pasted_content_9.txt

The new implementation specification requires Subject Access to be independent from Subscription:

```text
Student
  ↓
Subject Access Assignment
  ↓
enabled = true / false
```

The required evaluation order is:

```text
Subject Access
  ↓
Subscription
  ↓
Active Plan
  ↓
plan_features
  ↓
Entitlement
```

A disabled Subject Access assignment must deny access even when an active subscription exists. It must also prevent first-open Free Plan activation.

Each administrative toggle must record at least:

- student
- subject
- previous state
- new state
- changed by
- actor role
- timestamp

Approval must also persist selected Subject Access assignments and approval attribution (`approved_by`, `approved_at`) and remain auditable.

## Current implementation evidence

The current Cloud Functions implementation has subscription-scoped checks and an `assertSubjectAccess` helper that evaluates the existing subscription document. This is not equivalent to the newly required independent Subject Access Assignment because it cannot represent:

- access disabled while subscription remains active;
- access enabled while no subscription exists and Free Plan activation is still allowed;
- independent administrative toggles without mutating subscription lifecycle;
- approval-time subject access selections independent of plan state.

The current `activateFreePlan` flow checks for an active subscription and can create one based on student type and current term. It has no independent Subject Access Assignment precondition.

## Proposed structure requiring approval

This is a proposal only; it has not been implemented.

### Option A — New top-level collection

```text
subject_access_assignments/{assignmentId}

student_id: string
subject_id: string
enabled: boolean
created_at: timestamp
updated_at: timestamp
created_by: string
updated_by: string
is_deleted: boolean
```

Recommended uniqueness convention:

```text
{student_id}_{subject_id}
```

or an equivalent deterministic document ID to enforce one assignment per student-subject pair.

### Option B — Subcollection under the student

```text
users/{studentId}/subject_access/{subjectId}

enabled: boolean
created_at: timestamp
updated_at: timestamp
created_by: string
updated_by: string
```

Option B naturally scopes reads to a student but requires the backend and rules to resolve subject access consistently for subject-scoped operations.

### Approval attribution

If not already covered by the existing registration/application document, the approval record needs approved/rejected attribution fields or an existing audit record must be extended to expose:

```text
approved_by: string
approved_at: timestamp
rejected_by: string | null
rejected_at: timestamp | null
```

No field placement is authorized by this report.

## Required indexes

The final choice depends on the approved collection structure. Likely requirements are:

- `(student_id, subject_id)` unique or deterministic lookup;
- `student_id, enabled` for dashboard subject access resolution;
- `subject_id, enabled` only if administrative subject-wide queries are required;
- approval/application queries by `approval_status` and creation time if not already indexed.

Firestore does not provide a general unique constraint, so deterministic document IDs or a transaction-backed uniqueness check are required.

## Security implications

Until an approved structure exists, the following cannot be implemented safely without inventing schema:

- student read access to assignment state;
- Teacher full mutation authority;
- delegated Admin mutation authority;
- denial of student direct-route access when assignment is disabled;
- denial of Free Plan activation when assignment is disabled;
- server-side entitlement evaluation using independent access state;
- audit of every toggle with previous and new values.

Any proposed rules must ensure:

- students cannot write Subject Access;
- Admins require explicit delegated permission;
- Admins cannot self-grant permission;
- Teacher remains authoritative;
- client writes cannot mutate protected Membership or Access data;
- Cloud Functions validate all mutations server-side.

## Migration impact

A migration strategy is required if the new structure is approved:

1. Determine the initial assignment for every existing student-subject relationship.
2. Decide whether absent assignment means enabled, disabled, or requires explicit administrative review. This is a business rule and must not be invented.
3. Avoid mutating or deleting existing subscriptions during migration.
4. Preserve progress, notes, exams, analytics, and history.
5. Backfill audit attribution where historical actor data is unavailable, or explicitly mark it as historical/system-generated according to an approved policy.
6. Deploy rules and backend enforcement in an order that does not create an authorization bypass.

## Conflict requiring decision

### Document one

`05_DATABASE.md` — current approved flow: Free Plan is activated implicitly on first subject access when no subscription exists.

### Document two

`pasted_content_9.txt` — new accepted implementation requirement: Subject Access is an independent assignment, and disabled access must prevent Free Plan activation and all content access regardless of subscription.

### Rule one

The existing database specification models subscription state but does not provide an independent Subject Access Assignment structure.

### Rule two

The new implementation specification requires independent Subject Access state and requires it to override subscription entitlement.

### Reason for conflict

The required rule cannot be enforced reliably with the current approved schema without either placing access state inside Subscription (explicitly prohibited) or inventing a new collection/field structure (explicitly prohibited without approval).

### Proposed resolution

Approve one Subject Access Assignment schema option, or update the approved database specification with the authoritative structure, indexes, migration behavior, and default state for existing relationships.

### Code impact after approval

Expected affected areas, not yet modified:

- domain Subject Access entities and repository contract;
- Membership/Entitlement resolver;
- `activateFreePlan` and all protected content callables;
- approval workflow and selected subject toggles;
- Dashboard subject cards;
- Firestore Rules;
- Admin audit integration;
- Cloud Functions tests and Flutter unit/integration tests.

Protected and intentionally unchanged at this stop:

- Video playback implementation;
- Device Binding;
- Authentication and Session Foundation;
- existing subscription schema;
- existing Membership lifecycle decisions;
- offline DRM implementation.

## Decision required before continuation

Please approve the authoritative Subject Access Assignment structure and migration/default-state policy. Implementation must remain stopped until that schema decision is confirmed.
