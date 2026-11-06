# Security Events Database Change Proposal

Version: 0.2 (Proposed)
Status: Proposed — Pending Formal Database Approval
Date: 2026-10-22
Reconciliation context: `security_documentation_reconciliation_2026-10-22.md` records the governance status and the missing design approval prerequisites reflected in this revision.
Baseline: `05_DATABASE_v1.7.md` — Version 1.7 — Approved
Authority: Project Owner approved the security policy in ADR-008; the schemas
below have not been approved field by field.
Target database version: Unassigned pending formal database approval.
Implementation status: Not implemented.

## 1. Purpose and authority boundary

This document proposes two new Firestore collections:

- `security_events`
- `security_notification_outbox`

The approved policy is recorded in
`19_ADR_008_Security_Events_Alerting_Policy.md`. This document translates that
policy into a proposed schema only. It does not authorize application code,
Cloud Functions, Security Rules, indexes, Cloud Tasks configuration,
migrations, or deployment.

`05_DATABASE_v1.7.md` remains the Approved database baseline and is not
modified. `docs/notion/05 Database 1.8.md` is a Proposed revision and is not
authority for this change. Draft documents 06, 14, and 15 are not approval
authority.

### Approval status legend

| Label | Meaning |
|---|---|
| Approved policy | The Project Owner has approved the rule in ADR-008. |
| Proposed schema | A design recommendation in this document, not formally approved. |
| Pending | A required approval or implementation action that has not occurred. |

Every collection name, field name, field type, status value, document ID,
index, retention mechanism, and access-control rule in this document is
**Proposed schema** unless explicitly identified as approved policy.

## 2. Verified baseline and source reconciliation

| Source | Status | Relevance |
|---|---|---|
| `05_DATABASE_v1.7.md` | Version 1.7, Approved | Approved baseline. It does not define `security_events` or `security_notification_outbox`. |
| `docs/notion/05 Database 1.8.md` | Version 1.10, Proposed | Proposed database revision; not authority for this change. |
| `19_ADR_008_Security_Events_Alerting_Policy.md` | Version 1.0, Approved | Approved security policy. |
| `17_ADR_006_Security_Hardening.md` | Version 1.0, Approved | Approves `auth_security_events` for authentication-lockout auditing without push notification. That collection is distinct from `security_events`. |
| `docs/notion/14_Platform_Availability_Feature_Matrix_Permission_Matrix_Audit_System.md` | Version 1.1, Draft | Contains a proposed `security_events` schema and proposed retention values; not approved. |
| `docs/notion/15_Admin_Permissions_Audit_System.md` | Version 1.1, Draft | Contains Admin security-event review permissions; not approved. |

The Approved baseline has no `security_events` collection and no
`security_notification_outbox` collection. This proposal does not silently
insert either collection into the baseline.

## 3. Approved policy inputs

The following rules are approved in ADR-008 and are not schema proposals:

- Security notifications go exclusively to Doctor (Platform Owner).
- No Admin and no other Doctor accounts receive these notifications.
- Existing unrelated audit and security-event review permissions are not
  revoked.
- The server determines severity and action; clients cannot choose or
  override them.
- Medium events are recorded with no automatic punishment and no staff
  notification.
- High events are eligible for security notification.
- A generic `other` event is not accepted until separately approved.
- `device_mismatch` is excluded under ADR-004.
- Ingestion limits: 5 attempts per authenticated user per minute and 20 per
  hour; valid and rejected attempts count.
- Notification limits: 2 per user and event type in 10 minutes and 5 per hour.
- Enforcement is atomic and concurrency-safe.
- `security_events` retention is 3 years.
- General audit-log retention is at least 2 years and is distinct.
- `context` maximum is 8 KiB; `deviceInfo` maximum is 4 KiB; maximum depth is
  5.
- Malformed or oversized payloads are rejected, never silently truncated.
- Five total notification attempts with delays of 30 seconds, 2 minutes, 10
  minutes, and 30 minutes.
- Firestore Outbox + Cloud Tasks is the intended architecture.
- Exactly-once delivery is not promised.

Canonical event identifiers and exact action literals remain unapproved.
They are not proposed as approved values in this document.

### 3.1 Rate-limit counter storage — design approval prerequisite

The approved notification limits exist as policy; no Approved document defines
a storage design for atomic rate-limit counters (neither `05_DATABASE_v1.7.md`
nor any authoritative schema). The counter storage design — collection
identity, counter shape, sliding/fixed window mechanics, transaction
boundaries, and required indexes — is a **database/design approval
prerequisite**. This proposal deliberately does not propose a counter schema in
this revision and does not treat any Draft material as approved storage design.

Bindings from approved policy that any future counter design must satisfy:
server-side storage and trusted server time only; atomic and concurrency-safe
increment/decrement; both valid and rejected attempts counted for ingestion
limits; suppression of a notification never deletes or alters an accepted
`security_events` document.

### 3.2 Payload validation rejection behavior — pending owner decision

ADR-008 approves rejecting malformed or oversized payloads rather than silently
truncating them, but does **not** decide whether an invalid/oversized optional
metadata payload (`context` or `deviceInfo`) rejects the **entire event** or
only that metadata. That decision is a prerequisite recorded in the
reconciliation record. The recommended position (not yet approved policy) is
that when required payload validation fails the **entire event is rejected**
and no partial `security_events` record is stored; rejected events still count
against the ingestion rate limits.

Incompatibility note: the existing implementation degrades malformed maps to
`{}` (`securityEventMap` in `functions/src/index.ts`) and persists the event.
That behavior is incompatible with strict rejection and must be removed in any
authorized implementation. No code change is authorized by this proposal.

### 3.3 Recipient resolution — implementation prerequisite

The recipient is exactly one Doctor (Platform Owner) account. The Approved
architecture records the live owner's role as `teacher`, pending the approved
ADR-005 migration to `doctor` (not started as of the 2026-09-17 live
verification). Recipient resolution must therefore be a deterministic, secure,
server-side identification of the single Platform Owner account that does not
assume the migration completed, does not select every account holding role
`doctor` (or `teacher`), does not notify Admin or other Doctor accounts, and
does not rely on a configuration key or hardcoded UID invented without a
separate owner decision. The resolution mechanism is a design approval
prerequisite and is not proposed as a schema field in this revision.

### 3.4 Severity and action vocabulary — pending approvals

Approved severity concepts: Screenshot Medium; Screen recording High; Jailbreak
High; Rooted device High; Emulator Medium; generic `other` deferred until
separately defined; `device_mismatch` excluded (ADR-004). The canonical
event-type identifier set, the exact `action_taken` literals, the disposition
of the `low` and `critical` severities present in existing code/Draft 14, and
the classification of actions (recording-only / notification-only /
potentially punitive, including the older Feature 05 playback-interrupting
actions) all remain unresolved owner decisions and are prerequisites listed in
Section 7.

### 3.5 Outbox terminal-failure paths — design approval prerequisite

The proposed outbox schema does not yet include a complete terminal path for
permanent Cloud Tasks enqueue failures. The required open design questions
(terminal transition of a permanently un-enqueueable `pending` task, bounded
enqueue retries, expired-lease recovery, duplicate-scheduling prevention as far
as possible, the accepted duplicate-delivery window, and final-failure
recording/operational surfacing) are listed in Section 5.4 and the
reconciliation record. No exactly-once delivery is promised.

## 4. Proposed `security_events` collection

### 4.1 Purpose

One document per accepted security event. The event record is the
server-authoritative record of the occurrence and the policy outcome. It is
separate from general analytics and from `auth_security_events`.

### 4.2 Proposed document identity

- Collection: `security_events` (top-level).
- Document ID: UUID (Proposed).
- No deterministic event ID is proposed; the server creates the record.
- Creation is server-only.

### 4.3 Proposed fields

All fields below are **Proposed**.

| Proposed field | Proposed type | Proposed ownership | Approval | Notes |
|---|---|---|---|---|
| `event_type` | String | Server | Proposed | Canonical identifier is not approved; must validate against the eventual approved allowlist. |
| `severity` | String | Server | Proposed | Approved policy outcomes are Medium and High; exact enum values and canonical literals remain proposed. |
| `action_taken` | String | Server | Proposed | Server-derived outcome. The exact literals (`warning`, `notify_admin`) are existing code/test vocabulary, not formally approved canonical values. |
| `user_id` | String | Server | Proposed | Derived from verified authentication context; exact actor/subject semantics require approval. |
| `context` | Map \| null | Server-validated client observation | Proposed | Allowlisted fields, JSON-supported types, maximum 8 KiB serialized, maximum depth 5. |
| `device_info` | Map \| null | Server-validated client observation | Proposed | Allowlisted fields, JSON-supported types, maximum 4 KiB serialized, maximum depth 5. |
| `created_at` | Timestamp | Server | Proposed | Trusted server timestamp. |
| `created_by` | String | Server | Proposed | Server identity; intended value is `system` or the function identity. |
| `updated_at` | Timestamp | Server | Proposed | Server-only; event content is immutable after creation. |
| `updated_by` | String | Server | Proposed | Server-only. |
| `is_deleted` | Boolean | Server | Proposed | Server-only retention lifecycle flag; no client delete. |
| `deleted_at` | Timestamp \| null | Server | Proposed | Server-only retention lifecycle. |
| `deleted_by` | String \| null | Server | Proposed | Server-only retention lifecycle. |
| `retention_expires_at` | Timestamp | Server | Proposed | Derived from `created_at` plus 3 years for retention processing. |

### 4.4 Proposed status and lifecycle

No mutable workflow status is proposed for `security_events`. The event
content is immutable after creation. The only proposed lifecycle is
server-side retention:

1. Accepted event is written.
2. Event remains readable for approved review.
3. At `retention_expires_at`, the retention job archives or deletes the event
   according to the formally approved retention procedure.

The archive/delete mechanism is Proposed and Pending. No client create,
update, or delete is proposed.

### 4.5 Proposed access boundaries

- Client create: denied.
- Client update: denied.
- Client delete: denied.
- Server create: Cloud Functions only.
- Read/review: Doctor (Platform Owner), plus any unrelated approved audit or
  security-event review access that is not revoked by ADR-008.
- Admin read: allowed only if an existing approved audit/review permission
  grants it; no Admin notification recipient is created.
- Exact Firestore Security Rules are Pending formal approval and are not
  created by this proposal.

### 4.6 Proposed indexes

All indexes below are **Proposed** and are not created.

| Proposed index | Proposed purpose |
|---|---|
| `user_id` + `created_at` | User security-event history and review. |
| `event_type` + `created_at` | Event-type review and investigation. |
| `severity` + `created_at` | Severity review. |
| `created_at` | Retention processing. |
| `retention_expires_at` | Retention purge/archive selection. |

## 5. Proposed `security_notification_outbox` collection

### 5.1 Purpose

A durable notification-task record referencing an accepted `security_events`
document. The outbox must not duplicate the full `context` or `deviceInfo`
payload.

### 5.2 Proposed document identity

- Collection: `security_notification_outbox` (top-level).
- Proposed deterministic document ID:
  `{security_event_id}_{recipient_user_id}_{notification_kind}`.
- The deterministic ID is intended to prevent duplicate outbox records for the
  same event, recipient, and notification kind.
- Document identity is Proposed and Pending formal approval.

### 5.3 Proposed fields

All fields below are **Proposed**.

| Proposed field | Proposed type | Proposed ownership | Approval | Notes |
|---|---|---|---|---|
| `security_event_id` | String | Server | Proposed | Reference to `security_events`; do not duplicate full event payload. |
| `recipient_user_id` | String | Server | Proposed | Doctor (Platform Owner) account. |
| `recipient_role` | String | Server | Proposed | Intended value `doctor`; exact role literal follows ADR-005. |
| `event_type` | String | Server | Proposed | Denormalized for deduplication/rate-limit queries; canonical identifier remains unapproved. |
| `notification_kind` | String | Server | Proposed | Proposed value `security_event`; exact vocabulary pending. |
| `status` | String | Server | Proposed | Proposed values: `pending`, `enqueued`, `processing`, `retry_scheduled`, `succeeded`, `failed`. |
| `attempt_count` | Number | Server | Proposed | Initial attempt plus retries; maximum 5 total attempts under approved policy. |
| `next_attempt_at` | Timestamp \| null | Server | Proposed | Retry scheduling. |
| `lease_expires_at` | Timestamp \| null | Server | Proposed | Expired `processing` recovery. |
| `cloud_task_name` | String \| null | Server | Proposed | Reconciliation/idempotency reference. |
| `last_error_code` | String \| null | Server | Proposed | Non-sensitive error code only; no raw credentials or PII. |
| `completed_at` | Timestamp \| null | Server | Proposed | Terminal success or final failure time. |
| `created_at` | Timestamp | Server | Proposed | Server timestamp. |
| `created_by` | String | Server | Proposed | Server identity. |
| `updated_at` | Timestamp | Server | Proposed | Server timestamp. |
| `updated_by` | String | Server | Proposed | Server identity. |
| `is_deleted` | Boolean | Server | Proposed | Server-only cleanup/retention flag; no client delete. |
| `deleted_at` | Timestamp \| null | Server | Proposed | Server-only cleanup/retention. |
| `deleted_by` | String \| null | Server | Proposed | Server-only cleanup/retention. |
| `retention_expires_at` | Timestamp \| null | Server | Proposed | Proposed outbox retention deadline after terminal state. |

### 5.4 Proposed status values and transitions

The following values are **Proposed**, not approved schema:

- `pending`: outbox record exists; Cloud Tasks enqueue has not succeeded.
- `enqueued`: Cloud Tasks accepted the task reference.
- `processing`: a worker has claimed the task under a lease.
- `retry_scheduled`: a transient attempt failed and a retry is scheduled.
- `succeeded`: FCM accepted the message; this does not prove device delivery
  or that the recipient read it.
- `failed`: all attempts are exhausted and the final failure is recorded.

Proposed transitions:

```text
pending -> enqueued
enqueued -> processing
processing -> succeeded
processing -> retry_scheduled
processing -> failed
retry_scheduled -> pending | enqueued
```

Proposed recovery:

- An expired `processing` lease may be returned to `pending` or
  `retry_scheduled` by a reconciliation worker.
- A Firestore record that remains `pending` because Cloud Tasks enqueueing
  failed is reconciled by retrying enqueueing.
- A duplicate delivery remains possible if FCM accepts a message and the
  worker crashes before recording the outcome.
- Exactly-once delivery is not promised.

Open design questions pending approval (terminal-failure and leak-prevention
paths):

1. How a `pending` task whose Cloud Tasks enqueueing permanently fails becomes
   terminally `failed` (what distinguishes transient from permanent enqueue
   error, and what terminal transition/record is written).
2. How enqueue retries are bounded (attempt count and spacing), consistent
   with — but not conflated with — the five approved FCM send attempts.
3. How expired `processing` leases (dead workers) are recovered
   race-free against a still-running worker.
4. How duplicate scheduling is prevented as far as Firestore and Cloud Tasks
   allow (transactional claiming, task-name idempotency, lease-ownership
   checks) in addition to the deterministic document ID.
5. How an accepted FCM send followed by a worker crash before recording the
   result causes a duplicate delivery, documented as a known operational
   limitation (exactly-once delivery must not be promised).
6. How final failures are recorded (outbox fields: attempt count, error code,
   timestamps) and surfaced operationally so a security notification that
   permanently failed is noticed by Doctor/Admin operations.

These transitions and behaviors are **Proposed design requirements**, not an
approved state machine, and not implemented behavior.

### 5.5 Proposed retention

- Active outbox records: retained until terminal state.
- Terminal outbox records: proposed retention of 90 days after terminal state,
  then archive/delete.
- This outbox retention value is **Proposed and not approved**.
- `security_events` retention remains 3 years under approved policy and is
  separate from outbox retention.
- General audit-log retention remains at least 2 years and is separate from
  both.

### 5.6 Proposed access boundaries

- Client read: denied.
- Client create: denied.
- Client update: denied.
- Client delete: denied.
- Server/worker access: restricted service account and authenticated internal
  task endpoint only.
- No client read/write/create/update/delete access to the outbox.
- Exact Security Rules and service-account permissions are Pending formal
  approval and are not created by this proposal.

### 5.7 Proposed indexes

All indexes below are **Proposed** and are not created.

| Proposed index | Proposed purpose |
|---|---|
| `status` + `next_attempt_at` | Claim due pending/retry tasks. |
| `status` + `lease_expires_at` | Recover expired `processing` tasks. |
| `security_event_id` + `recipient_user_id` | Idempotency/duplicate prevention. |
| `recipient_user_id` + `event_type` + `created_at` | Notification rate-limit and deduplication queries. |
| `status` + `created_at` | Outbox retention processing. |
| `retention_expires_at` | Outbox cleanup/archive selection. |

## 6. Security boundaries and cross-references

- `security_events` is a general security-event record for this policy.
- `auth_security_events`, approved by ADR-006, is for authentication-lockout
  auditing and explicitly has no push notification at this stage. It must not
  be conflated with `security_events`.
- The outbox references `security_events` and must not duplicate full
  `context` or `deviceInfo`.
- No client access to the outbox is permitted.
- No collection, index, rule, queue, worker, or migration is created by this
  proposal.
- The older "Notify administrators" text in `04_FEATURES.md` is superseded for
  this policy's notifications by ADR-008, with a versioned feature-document
  amendment still pending.

## 7. Approval gate and pending decisions

This proposal is **BLOCKED pending formal database approval**. The following
items require explicit approval before implementation:

1. Target database version and formal database-change approval.
2. Approval of `security_events` collection and every field/type.
3. Approval of `security_notification_outbox` collection and every
   field/type.
4. Approval of outbox status values and transition rules, including the
   complete terminal path for permanent enqueue failures and
   final-failure recording/surfacing (Section 5.4 open questions).
5. Approval of both document identity strategies.
6. Approval of all proposed indexes, including counter/indexes of the
   rate-limit storage design (once designed).
7. Approval of Security Rules and service-account permissions.
8. Approval of outbox retention and both retention purge/archive
   mechanisms, and of the `security_events` retention purge/archive
   mechanism.
9. Approval of canonical event identifiers and action literals, including
   the disposition of `low`/`critical` severities and the
   recording/notification/punitive classification of actions.
10. Approval of the atomic rate-limit counter storage design
    (Section 3.1). No counter schema is proposed yet.
11. Approval of the payload-validation rejection decision: whole-event
    rejection versus metadata-only rejection for invalid/oversized
    metadata (Section 3.2), plus the payload-field allowlist and the
    rejection response shape.
12. Approval of the recipient-resolution design for the single Platform
    Owner account, verified against the actual ADR-005 migration state
    (Section 3.3).
13. Versioned textual alignment of `04_FEATURES.md`.
14. Separate implementation authorization.

Until those approvals exist, this document is a proposal only. It does not
create authoritative schema, does not modify `05_DATABASE_v1.7.md`, and does
not authorize implementation.

## 8. Explicit exclusions

This proposal does not:

- modify `05_DATABASE_v1.7.md` or `docs/notion/05 Database 1.8.md`;
- modify Draft documents 06, 14, or 15;
- modify source code, Cloud Functions, tests, Security Rules, indexes, or
  Firebase configuration;
- create Firestore collections or documents;
- configure Cloud Tasks;
- run migrations;
- deploy services; or
- send notifications.

## 9. Validation Evidence

- Documentation-only proposal (Version 0.2 adds design approval
  prerequisites only; no schema was proposed as approved and no schema field
  was marked approved).
- No source code, tests, Security Rules, indexes, Firebase configuration,
  Cloud Tasks configuration, or deployment files were modified.
- No deployment, migration, or notification was performed.
- Pre-existing working-tree changes and untracked files were preserved.
- `05_DATABASE_v1.7.md`, `docs/notion/04_FEATURES.md`, and
  `19_ADR_008_Security_Events_Alerting_Policy.md` were not modified by this
  revision; see `security_documentation_reconciliation_2026-10-22.md`.

## 10. Production Safety

Recorded explicitly: no production deployment, no production Firestore or Auth
writes, no commit, no staging, and no destructive git operations were
performed as part of this work.
