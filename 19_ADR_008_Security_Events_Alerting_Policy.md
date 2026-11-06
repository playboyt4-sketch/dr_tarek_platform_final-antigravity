# ADR-008 — Security Events and Alerting Policy

Status: Approved
Date: 2026-10-22
Version: 1.0
Authority: Project Owner decision (documentation-only record)

This ADR records Project-Owner-approved policy decisions only. It does not
authorize implementation, deployment, schema changes, Security Rules, indexes,
Cloud Tasks configuration, migrations, or notification delivery. It does not
promote Draft documents 06, 14, or 15. It does not modify the Approved
baseline `05_DATABASE_v1.7.md` or the Approved feature document
`docs/notion/04_FEATURES.md`.

## Decision

### A. Server-authoritative classification

- The server determines `severity` and `action_taken` from the approved
  event-type policy. The client reports an observed event and must not choose
  or override either field.
- Unsupported event types must not be accepted as though their classification
  were approved.
- `device_mismatch` is excluded from punishable security events under the
  existing ADR-004 decision.
- This policy introduces no automatic punishment by default. It does not
  authorize account suspension, subscription cancellation, device revocation,
  or any other punishment.
- Client-supplied `actionTaken`, `action_taken`, `severity`, recipient fields,
  routing instructions, and identity fields are not trusted for privileged
  server behavior. Authenticated identity remains derived from the verified
  server authentication context.

### B. Notification recipients and reconciliation with the older rule

Security notifications covered by this policy go exclusively to **Doctor
(Platform Owner)**.

- Do not route these notifications to Admin.
- Do not route them to other Doctor accounts.
- Recipient resolution must be server-side; clients must not specify recipient
  IDs, roles, or routing destinations.
- The canonical target role is `doctor` per ADR-005; historical `teacher`
  records remain historical.
- This policy does not revoke unrelated audit or security-event review
  permissions already granted by approved decisions.

The Approved `docs/notion/04_FEATURES.md` Version 2.0 states, under Security
Violation at line 795, "Notify administrators." That statement conflicts with
this policy's recipient rule. The related lines at `04_FEATURES.md:974`
(security-score visibility) and `04_FEATURES.md:1043` (Admin review of security
events) are not notification rules and remain in force.

This ADR records the later, more specific Project-Owner-approved decision and
therefore supersedes the notification-recipient aspect of that earlier rule
for security notifications covered by this policy. This ADR does not:

- edit or reinterpret the word "administrators" in `04_FEATURES.md`;
- change `04_FEATURES.md` status or version;
- remove Admin security-event review or audit access;
- supersede unrelated notification actions in other feature areas.

`04_FEATURES.md` remains Approved Version 2.0 and its text is stale for this
recipient aspect. Master Architecture Sections 5.1 and 5.2 require versioned
decision records and cross-document consistency. This ADR is the versioned
decision record; a separate versioned amendment of `04_FEATURES.md` is
required to align its wording and is recorded as a pending documentation
follow-up. Implementation must use this ADR for the recipient rule and must
not use the older "Notify administrators" sentence for these notifications.

Pending governance prerequisite: the versioned amendment of `04_FEATURES.md`
is required to make the feature text consistent; no implementation using this
recipient rule is authorized until that amendment is completed. This ADR does
not bypass that prerequisite, and no additional implementation or deployment
authority is created by this reconciliation.

### C. Event classification

The following severity and handling decisions are approved. The table uses
policy concepts, not approved machine identifiers.

| Event concept | Severity | Approved handling | Canonical identifier status |
|---|---|---|---|
| Screenshot | Medium | Record the event; no automatic punishment | The descriptive concept appears in Approved 04; the exact machine identifier is not formally approved. |
| Screen recording | High | Eligible for security notification | `screen_record` appears only in Draft 14 and existing code; not an approved canonical identifier. |
| Jailbreak | High | Eligible for security notification | `jailbreak` appears only in Draft 14 and existing code; not an approved canonical identifier. |
| Rooted device | High | Eligible for security notification | The descriptive concept appears in Approved 04; the exact `rooted` identifier is not formally approved. |
| Emulator | Medium | Record the event; no automatic punishment | The descriptive concept appears in Approved 04; the exact `emulator` identifier is not formally approved. |
| Other security violations | Undefined | Do not accept a generic `other` event until its definition and handling are separately approved | No generic `other` identifier or classification is approved. |
| Device mismatch | Excluded | Not a punishable security event | The concept is excluded by ADR-004; `device_mismatch` is Draft/code terminology, not an approved canonical identifier. |

The event-severity policy and handling outcomes above are approved. Canonical
machine-readable identifiers are not all approved by the authoritative
documentation. The strings `screen_record`, `jailbreak`, `other`, and
`device_mismatch` must not be represented as approved canonical identifiers
merely because they appear in Draft documents or existing code.

No aliases are authorized. The exact canonical identifier set must be
approved before implementation.

#### Action vocabulary boundary

The approved server-owned outcomes are:

- Medium: record the event and do not send a staff notification.
- High: record the event and make it eligible for the security notification,
  subject to the rate limits and retry policy below.

The exact persisted `action_taken` literals are not separately approved by
this ADR. Existing code/tests and Draft 14 use `warning` and `notify_admin`;
those strings remain proposed vocabulary until formally confirmed. The server
must not accept a client-provided action value in any case.

### D. Deferred "Other security violations" category

The Approved feature documentation contains the broad category "Other security
violations" at `docs/notion/04_FEATURES.md` line 958. That category is not
removed or rewritten by this ADR.

The Project Owner has decided to defer acceptance of a generic `other` event
until its meaning and handling are formally defined and approved. Therefore:

- no canonical generic `other` event is approved;
- no severity, notification behavior, or punishment rule is assigned to
  `other`;
- the server must not accept a generic `other` event as though its
  classification were approved;
- a future decision must define the event taxonomy, payload/evidence
  requirements, severity, action, notification behavior, and punishment
  boundary before `other` can be accepted.

### E. Rate limits

The following server-side limits are approved policy, not evidence of
implementation:

- Maximum 5 attempts per authenticated user per minute.
- Maximum 20 attempts per authenticated user per hour.
- Maximum 2 notifications per user and event type in 10 minutes.
- Maximum 5 notifications per user and event type per hour.
- Enforcement must be atomic and concurrency-safe.
- Both valid and rejected attempts count against the ingestion limits;
  rejected attempts must not bypass the limiter by changing event fields.
- Suppressing a notification must not delete or alter an accepted security
  event.
- Limits must use a trusted server time source and server-side storage. Client
  counters and client timestamps are not authoritative.
- The notification scope and deduplication key must be defined at
  implementation time; the approved limits are per user and event type.

### F. Payload validation and retention

The following are approved policy decisions:

- Security-event retention: 3 years.
- General audit-log retention: at least 2 years.
- Maximum `context` payload: 8 KiB.
- Maximum `deviceInfo` payload: 4 KiB.
- Maximum nested payload depth: 5.
- Only allowlisted fields and JSON-supported types are permitted.
- Malformed or oversized payloads must be rejected, not silently truncated.
- Passwords, credentials, tokens, secrets, and unnecessary personal
  information must not be stored.
- Security-event retention and general audit-log retention are distinct
  policies and must not be conflated.

The proposed measurement is the serialized JSON representation. The exact
allowlist, rejection response, retention deletion/archive mechanism, and
whether oversized metadata rejects the whole event or only the metadata are
implementation decisions that require formal approval before implementation.

### G. Reliable Retry policy

The approved notification retry policy is **Reliable Retry**:

- Preserve the accepted security event after its event record is successfully
  written.
- Five total notification attempts: one initial attempt plus four retries.
- Retry delays: 30 seconds, 2 minutes, 10 minutes, and 30 minutes.
- Record the final failure after all attempts are exhausted.
- Retry transient failures; avoid pointless retries for permanent errors.
- FCM provider acceptance does not prove device delivery or that the recipient
  read the notification.

This is an approved policy, not evidence that retries exist in production.

### H. Intended operational architecture: Firestore Outbox + Cloud Tasks

The Project Owner selected **Firestore Outbox + Cloud Tasks** as the intended
architecture. It is approved as an architectural direction, not as implemented
functionality.

The design must account for:

- a separate durable notification-task record referencing the security event;
- idempotency and duplicate prevention;
- atomic task claiming or a lease with expiry;
- recovery of expired `processing` tasks;
- reconciliation when the Firestore task is created but Cloud Tasks enqueueing
  fails;
- the possibility of duplicate delivery if FCM accepts a message but the
  worker crashes before recording the result;
- an authenticated internal task endpoint and restricted service-account
  permissions;
- no client read/write/create/update/delete access to the outbox;
- referencing the event rather than duplicating its full `context` and
  `deviceInfo`.

Exactly-once delivery must not be promised. Firestore, Cloud Tasks, and FCM do
not provide one shared atomic transaction. Duplicate delivery remains possible
and must be documented as an operational limitation.

### I. Security implications and operational limitations

- Server authority removes client control over alert triggering and
  suppression.
- Doctor-only recipient minimization reduces unnecessary staff exposure.
- Audit and security-event review access that is already approved remains
  intact; notification recipients and review permissions are separate.
- Payload allowlists and size/depth limits reduce accidental PII retention and
  oversized writes.
- The outbox isolates notification delivery from the accepted event record and
  prevents full event payload duplication.
- Duplicate delivery remains possible; FCM acceptance is not proof of device
  delivery or read status.
- Reconciliation is required when the Firestore task exists but Cloud Tasks
  enqueueing fails.
- Rate-limit storage, indexes, outbox retention, and retention purge mechanics
  are not implemented and require approval.
- No automatic punishment is introduced.

## Context

The existing `onSecurityEvent` implementation accepted client-supplied
severity and used it to trigger staff notifications. That allowed an
authenticated client to cause or suppress alerts by choosing a severity value.
The Approved feature documentation also contains an older generic instruction
to "Notify administrators," while the Project Owner has now approved a
Doctor-only recipient rule for this policy.

The Project Owner has since approved the recipient, classification, rate-limit,
payload, retention, retry, and outbox decisions recorded above. Approved
documents do not yet contain canonical machine identifiers, approved action
literals, or a field-by-field `security_events` schema. Therefore this ADR
records the approved policy while preserving the distinction between approved
policy and proposed schema.

## Alternatives Considered

1. Keep client-supplied severity and add only throttling. Rejected: the client
   would still control alert delivery and suppression.
2. Notify all Administrators as the older feature text says. Rejected for this
   policy: the Project Owner selected Doctor-only notification recipients.
3. Modify `04_FEATURES.md` directly. Rejected: the document is Approved, and
   silently editing or reinterpreting it would bypass documentation
   governance. This ADR records the supersession explicitly instead.
4. Enforce limits with in-memory counters. Rejected: Cloud Functions is
   distributed and in-memory counters are not concurrency-safe.
5. Promise exactly-once notification delivery. Rejected: Firestore, Cloud
   Tasks, and FCM cannot share one atomic transaction; duplicate delivery is
   possible.
6. Treat Draft 14's schema and identifiers as approved. Rejected: Draft
   documents are not implementation authority.

## Consequences

- The server becomes authoritative for severity and action; clients cannot
  manipulate alert delivery through those fields.
- Security notifications are restricted to Doctor (Platform Owner), subject
  to approved audit/review permissions that remain in force.
- The obsolete "Notify administrators" sentence remains in Approved
  `04_FEATURES.md` until a versioned amendment aligns it; this ADR is the
  controlling later decision for this policy and the amendment is a recorded
  follow-up.
- Canonical event identifiers and action literals remain unresolved and block
  implementation until approved.
- The rate-limit storage mechanism, indexes, retention purge, Cloud Tasks
  configuration, outbox schema, and internal endpoint remain unimplemented.
- No automatic punishment is introduced by this policy.

## Cross-document review

- `docs/notion/00_MASTER_ARCHITECTURE.md` Version 2.1, Approved: Sections 5.1
  (change management), 5.2 (ADR requirements), 5.3 (ADR history), and 11.1
  (conflict precedence) govern this record.
- `docs/notion/FINAL_DECISIONS.md` Version 2.1, Approved: Section 8 contains
  generic notification retry/dead-letter principles; this ADR adds the
  security-event-specific policy without rewriting it.
- `docs/notion/04_FEATURES.md` Version 2.0, Approved: the "Notify
  administrators" conflict is reconciled by this ADR; the versioned text
  amendment remains pending.
- `05_DATABASE_v1.7.md` Version 1.7, Approved: it does not define
  `security_events` or `security_notification_outbox`. Its Security Overview
  grants Admin a "Send Notifications" capability; that is a sending
  capability, not receipt of the security notifications covered here, and is
  unchanged.
- `17_ADR_006_Security_Hardening.md` Version 1.0, Approved: it approves
  `auth_security_events` for authentication-lockout auditing without push
  notification. That collection is distinct from the proposed general
  `security_events` collection and must not be conflated.
- Draft 06, 14, and 15 contain related material but are not approval
  authority. Draft 14 identifies proposed `security_events` fields and
  retention, and also contains proposed `device_mismatch`, `other`, action
  vocabulary, and "Client + Server" logging language that is not approved and
  must be aligned. Draft 15 grants Admin security-event review, which is
  compatible with preserved review access but is not authority for notification
  recipients. Those documents do not authorize implementation.

## Database governance

The approved policy and the proposed schema are separate:

- Approved policy: recipient rule, server authority, event-severity handling,
  deferral of generic `other`, rate limits, payload limits, retention periods,
  retry policy, and the intended Firestore Outbox + Cloud Tasks direction.
- Proposed schema: all collection names, field names, field types, status
  values, document IDs, indexes, access-control rules, outbox retention, and
  retention purge mechanics.

The proposed schema is recorded separately in
`security_events_database_change_proposal.md`. It is pending formal database
approval and is not authoritative. This ADR does not create collections,
indexes, Security Rules, Cloud Tasks queues, or backend functionality.

## Implementation status

Not implemented. No `onSecurityEvent` change, Cloud Function, Firestore
collection, index, Security Rule, Cloud Tasks queue, outbox worker, retry
mechanism, retention job, or notification delivery is authorized or performed
by this ADR.

The following remain pending before implementation:

1. Formal approval of canonical event identifiers.
2. Formal approval of action vocabulary.
3. Field-by-field approval of `security_events` and
   `security_notification_outbox`.
4. Approval of indexes, access-control rules, outbox retention, and retention
   purge mechanics.
5. Versioned textual alignment of `04_FEATURES.md`.
6. A separate implementation authorization.

Required validation before acceptance must include emulator/integration tests
for real Firestore behavior, recipient authorization, concurrency-safe rate
limits, retry/lease recovery, malformed payload rejection, and duplicate
delivery handling. Mock-only tests are insufficient.

## Validation Evidence

- Documentation-only task.
- No source code, tests, Security Rules, indexes, Firebase configuration,
  Cloud Tasks configuration, or deployment files were modified.
- No deployment, migration, or notification was performed.
- Existing unrelated working-tree changes and untracked files were preserved.

## Production Safety

Recorded explicitly: no production deployment, no production Firestore or Auth
writes, no commit, no staging, and no destructive git operations were
performed as part of this work.
