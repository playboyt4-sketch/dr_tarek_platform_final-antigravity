# Security Documentation Reconciliation Record — Security Events & Alerting

Version: 1.0
Date: 2026-10-22
Status: Documentation-only reconciliation record. Not an approval of any schema, identifier, or behavior.
Scope: documentation reconciliation only. No source code, tests, Security Rules, indexes, Firebase configuration, Cloud Tasks configuration, or deployment files were modified by this record.
Authority basis: `19_ADR_008_Security_Events_Alerting_Policy.md` (Version 1.0, Approved policy record), `docs/notion/00_MASTER_ARCHITECTURE.md` (Version 2.1, Approved), `docs/notion/FINAL_DECISIONS.md` (Version 2.1, Approved), `17_ADR_006_Security_Hardening.md` (Version 1.0, Approved), `05_DATABASE_v1.7.md` (Version 1.7, Approved), `docs/notion/04_FEATURES.md` (Version 2.0, Approved).

---

## 1. Purpose

This record reconciles the security documentation with the Project Owner's approved policy decisions in ADR-008, records the actual status of the existing partial implementation, and lists the remaining owner decisions and formal governance blockers. It is the governance-compliant baseline for any subsequent, separately authorized implementation of the security-events and alerting policy.

Nothing in this record authorizes implementation, deployment, schema creation, rules changes, indexes, Cloud Tasks configuration, migrations, notification delivery, or commits.

## 2. Status taxonomy — what "approved" means here

The following five categories must be kept distinct. Conflating them is treated in this project as a documentation defect (Master Architecture Section 9.1).

1. **Approved policy** — decisions the Project Owner approved in an authoritative Approved document. For this area: the policy content of ADR-008 (recipient rule, server authority, severity concepts, rate limits, payload limits, retention periods, Reliable Retry, Firestore Outbox + Cloud Tasks direction), ADR-006 (`auth_security_events`), ADR-005 (role migration direction), and the Approved baseline documents.
2. **Formal cross-document governance prerequisites** — versioned actions required by Master Architecture Sections 5.1/5.2/11.1 before related implementation may proceed, such as the versioned amendment of `04_FEATURES.md`, formal database approval, and a separate implementation authorization. An Approved policy record alone does not satisfy these.
3. **Proposed database schemas** — the field-by-field schemas in `security_events_database_change_proposal.md` and related Draft 06/14/15 material. Proposed schema is never authority, even when consistent with approved policy.
4. **Existing partial implementation** — code, rules, and tests that already exist in the working tree. Existence is evidence only; it is not compliance with ADR-008 and is not implementation authorization.
5. **Implementation authorization** — a decision that does not yet exist. Nothing currently authorizes production use of the security-events notification path under the new policy.

## 3. ADR-008 governance status (reconciled, status label unchanged)

ADR-008 is recorded with **Status: Approved** as a policy record. Its own text (Section B, "Pending governance prerequisite") states that the versioned amendment of `04_FEATURES.md` is required and that no implementation using the Doctor-only recipient rule is authorized until that amendment is completed.

Verified on 2026-10-22: `docs/notion/04_FEATURES.md` remains **Version 2.0, Approved** and still contains the sentence "Notify administrators." under Feature 05 "Video Player" → "Alternative Flow" → "Security Violation" (line 795). No versioned amendment of that document exists, and no separate owner approval for that amendment is recorded in any file reviewed during this reconciliation.

**Governance blocker B-1:** the versioned amendment of `docs/notion/04_FEATURES.md` required by ADR-008 Section B has not been performed. Until it is performed, the following apply:

- ADR-008's Approved status covers the **policy record**; it does not cover, and does not create, implementation readiness.
- The Doctor-only notification decision is **not implementation-ready**: its formal governance prerequisite (the feature-document amendment) remains unresolved.
- This record does not change ADR-008's status label, edit ADR-008, or amend `04_FEATURES.md`. Editing an Approved document outside the authorized versioned-amendment process would violate Master Architecture Sections 5.1 and 5.2 and ADR-006/ADR-008 precedent (see ADR-008 Alternatives Considered, item 3, which explicitly rejected silently modifying `04_FEATURES.md`).

If the Project Owner requires the `04_FEATURES.md` amendment, it must be executed as a separate, versioned documentation change.

## 4. Existing partial implementation — accurate status

The feature must be documented as **existing partial implementation that has not been verified as compliant with ADR-008 and is not authorized for production use under the new policy.** It is not "entirely unimplemented," and it is not compliant.

### 4.1 What exists today

| Area | Location | Existing behavior |
|---|---|---|
| Cloud Function | `functions/src/index.ts`, handler `onSecurityEvent` (section heading `onSecurityEvent`, lines ~5232–5304) | Authenticated-only callable. Accepts client-supplied `severity` (default `medium`, case-normalized) from the set `low, medium, high, critical`. Event-type allowlist: `screenshot`, `screen_record`, `jailbreak`, `rooted`, `emulator` (no `other`, no `device_mismatch`). Maps severity to `action_taken` server-side: `high`/`critical` → `notify_admin`; `low`/`medium` → `warning`. Writes one `security_events` document and one analytics event. **No ingestion rate limiting. No payload size/depth/allowlist enforcement. No retention fields.** |
| Notification fan-out | `onSecurityEvent`, lines ~5298–5301 | When `action_taken == "notify_admin"`, sends to **all users with role `doctor` AND all users with role `admin`** (`notifyUsersByRole` twice). This conflicts with the ADR-008 Doctor-only recipient rule. |
| Payload normalization | `securityEventMap` (lines ~5254–5259) | Malformed `context`/`deviceInfo` values (non-map, array, primitive) degrade to an empty map `{}` instead of being rejected. |
| Security Rules | `firestore.rules`, "security_events" match block (lines 252–255) | Read for `canManageDevices() \|\| canViewAnalytics()`; all writes denied. Separate `auth_security_events` block (lines 247–250, ADR-006) exists. |
| Dashboard consumers | `dashboard/lib/features/students/presentation/providers/student_profile_security_provider.dart`, `dashboard/lib/features/students/presentation/screens/student_profile_security_tab.dart` | Read `security_events` per student for the profile security-review tab; the provider documents accepted backend severities including `low` and `critical`. |
| Tests | `functions/test/security_event.test.js` (mock-only), `dashboard/test/student_profile_security_test.dart` | Mock-based tests assert current behavior including Doctor+Admin fan-out. Mock-only tests are insufficient per ADR-008's required validation. |
| Mobile app (`lib/`) | — | No caller of `onSecurityEvent` was found in the Flutter app source reviewed; the client-reporting side is not wired, so end-to-end production reporting does not exist. |

### 4.2 Known conflicts between the existing implementation and ADR-008

1. Recipient scope: implementation notifies Doctor + Admin; policy is Doctor (Platform Owner) only.
2. Severity authority: implementation derives action from a client-supplied severity; policy requires the server to determine `severity` and `action_taken` from the approved event-type policy (client severity is not trusted).
3. Rate limits: no 5/min and 20/hour ingestion limits, and no notification limits, exist for this path.
4. Payload policy: no size, depth, allowlist, or strict-rejection enforcement; `{}` degradation contradicts the approved "reject, not silently truncate" direction.
5. Vocabulary: code accepts `low` and `critical` severities and persists `warning`/`notify_admin`; those literals are not approved (Section 8 below).
6. No outbox: the implementation sends inline (no Firestore Outbox, no Cloud Tasks, no 5-attempt Retry, no terminal failure record).

No source code, tests, or rules were changed by this record; the deltas above remain for a separately authorized implementation task.

## 5. Recipient resolution — required implementation prerequisite

The intended recipient of every ADR-008 security notification is **exactly one Doctor (Platform Owner) account.**

Constraint from the Approved architecture: Master Architecture Version 2.1 / ADR-005 documents the platform-owner role migration `teacher` → `doctor` as **approved but not started** in live systems (live verification dated 2026-09-17 recorded the owner claims as `role: "teacher"`); FINAL_DECISIONS Section 26 reiterates that partial migration is unsafe and not prescribed. The ADR-008 policy uses the canonical target role `doctor`.

Required implementation prerequisites (to be satisfied in a separately authorized implementation task; **not** implemented here):

- Establish a deterministic, secure, server-side way to resolve the single intended Platform Owner account. The exact mechanism is an open design/owner decision — resolution must survive both the pre-migration (`teacher`) and post-migration (`doctor`) states and must not select "the account that happens to hold the role today" by accident.
- Do not select every account with role `doctor` (or `teacher`); the recipient is one account, not a role population.
- Do not send security notifications to Admin or to other Doctor accounts.
- Do not assume the ADR-005 migration has completed (it has not).
- Do not invent a configuration key or hardcode an owner UID in documentation or code now.
- Account resolution design, like the recipient rule generally, is formally blocked by governance blocker B-1 (Section 3) until the `04_FEATURES.md` amendment and the other ADR-008 prerequisites are completed.

## 6. Rate limiting — approved policy and missing storage design

Approved policy (ADR-008 Section E — approved rules, not evidence of implementation):

- Maximum 5 attempts per authenticated user per minute; maximum 20 per hour (ingestion).
- Maximum 2 notifications per user and event type per 10 minutes; maximum 5 per user and event type per hour.
- Enforcement must be atomic and concurrency-safe (server-side storage and trusted server time; client counters/timestamps are not authoritative).
- Both valid and rejected attempts count against the ingestion limits; rejected attempts must not bypass the limiter by changing event fields.
- Suppressing a notification must never delete or alter an accepted security event.
- The notification scope and deduplication key must be defined at implementation time.

**Database/design approval prerequisite (grid-gap identified):** no Approved document and no Approved database section defines a storage design for atomic rate-limit counters (neither `05_DATABASE_v1.7.md`, nor the proposal, nor any Draft as authority). A counter storage design (collection identity, counter shape, window mechanics, transaction boundaries, and indexes) must be formally approved as part of the database approval gating this feature. This reconciliation deliberately does **not** invent an approved storage schema; `security_events_database_change_proposal.md` records this as a pending design approval, without proposing a schema in this revision.

## 7. Payload validation — approved policy, open rejection decision, and recommendation

Approved policy (ADR-008 Section F):

- `context` maximum 8 KiB, `deviceInfo` maximum 4 KiB (approved measurement: serialized JSON representation), maximum nested depth 5, allowlisted fields and JSON-supported types only.
- Malformed or oversized payloads must be **rejected, not silently truncated**.
- No passwords, credentials, tokens, secrets, or unnecessary personal information stored.
- Retention: `security_events` 3 years; general audit logs at least 2 years; distinct policies.

**Open decision (not covered by approved policy):** whether a malformed/oversized optional-metadata payload (`context` or `deviceInfo`) rejects the **entire event** or only that metadata. ADR-008 explicitly defers the rejection response and this whole-event-or-metadata question to a formal approval. This documentation originally leaves that ambiguity open; the approved policy text alone does not resolve it.

**Recommendation (requires owner/governance approval; not currently approved policy):** when required payload validation fails, reject the **entire event** rather than storing a misleading partial record — a `security_events` document whose `context`/`device_info` was silently degraded offers an audit trail that does not match what actually happened. Rejected events must still count against the ingestion rate limits and, where the client continues violating the contract, should surface as part of the abuse/monitoring picture designed at implementation time.

**Incompatibility recorded:** the existing implementation converts malformed `context`/`deviceInfo` maps to `{}` (`securityEventMap`) and persists the event. That behavior is incompatible with strict rejection and must be removed/replaced in any authorized implementation of the approved payload policy. The current implementation and its tests are **not** changed by this record.

## 8. Severity and action vocabulary — approved outcomes and unresolved literals

### 8.1 Approved severity policy (by event concept — ADR-008 Section C)

| Event concept | Severity | Approved handling |
|---|---|---|
| Screenshot | Medium | Record the event; no automatic punishment; no staff notification |
| Screen recording | High | Record; eligible for the Doctor-only security notification under rate limits and retry policy |
| Jailbreak | High | Record; eligible for the security notification |
| Rooted device | High | Record; eligible for the security notification |
| Emulator | Medium | Record; no automatic punishment; no staff notification |
| Generic `other` | Undefined | Deferred: do not accept a generic `other` event until definition and handling are separately approved |
| `device_mismatch` | Excluded | Not a punishable security event (ADR-004); Guest-tier analytics only |

### 8.2 Canonical identifiers — unresolved

No canonical machine-readable event identifier set is formally approved by authoritative documentation. The strings `screen_record`, `jailbreak`, `rooted`, `emulator`, `screenshot`, `other`, and `device_mismatch` appear in ADR-008 as concepts/references to Draft 14 and existing code, and the exact allowlist must be approved before implementation.

**Cross-reference correction (governance-permitted, recorded here):** Draft 14 ("14 Platform Availability … Audit System", Version 1.1, Draft) does **not** define a canonical `other` identifier. Its proposed `security_events` schema line reads `event_type: String (screenshot, screen_record, jailbreak, emulator, device_mismatch, etc.)` (Draft 14, Section "5.3 Audit Log Schema" → "Security Events Schema (new collection)"), and its proposed severity line and action line are respectively `(low, medium, high, critical)` and `(warning, pause, stop, logout, notify_admin)`. Any previous claim that Draft 14 defines a canonical `other` identifier is inaccurate; Draft 14's identifiers are proposed Draft material and are not approval authority in any case.

### 8.3 Unresolved owner questions (minimum decisions needed)

The existing implementation and Draft documentation use severity literals `low, medium, high, critical` and action values such as `notify_admin` (code: `warning`, `notify_admin`; Draft 14 proposes `warning, pause, stop, logout, notify_admin`). The approved policy does not fully define these literals. The following are genuine unresolved policy questions; no answer is invented here and no business behavior is changed:

1. **What happens to `low` and `critical`?** The approved policy defines only Medium concepts (record, no notification) and High concepts (record, notification-eligible). The code accepts `low` and `critical`. An owner decision is required: retain them (and define their handling), map them onto Medium/High, or remove them from the accepted vocabulary.
2. **What exact `action_taken` vocabulary is allowed?** `warning` and `notify_admin` exist in code/tests; Draft 14 proposes `pause`, `stop`, `logout` additionally. None is formally approved. The approved server-owned outcome boundary is: Medium = record only; High = record + notification-eligible. The exact persisted literals must be approved.
3. **How are the older Feature 05 actions "Pause playback", "Stop playback", and "End session" (`04_FEATURES.md`, Feature 05 → Alternative Flow → Security Violation) reconciled with the no-automatic-punishment policy?** ADR-008 introduces no automatic punishment and the Feature document's own Business Rules state "Security actions are administrative decisions and are never applied automatically." An owner decision is required on whether those playback-interrupting actions remain part of the approved configurable Security Policy execution list (as administrative/configured behaviors), are reclassified as recording-only or notification-only outcomes, or are removed from the automatic execution list.
4. **Which actions are recording-only, notification-only, or potentially punitive?** A single owner decision should classify each action in the vocabulary against the no-automatic-punishment boundary, so the server-side mapping table can be approved once, coherently.

These four questions are additive to, and are satisfied together with, the canonical identifier approval already listed in ADR-008 ("Implementation status").

## 9. Outbox failure-state design — open design questions

The Firestore Outbox + Cloud Tasks direction and the Reliable Retry policy (5 total attempts; 30 s / 2 m / 10 m / 30 m) are approved. The proposed `security_notification_outbox` schema (Proposed, `security_events_database_change_proposal.md` Sections 5.2–5.6) does **not yet include a complete terminal path for permanent Cloud Tasks enqueue failures.** The following design questions must be answered and formally approved before/with the database approval; they are recorded here as required design decisions, not as implemented behavior and not as an approved state machine:

1. **Terminal failure of a pending task:** how does a `pending` outbox record whose Cloud Tasks enqueueing permanently fails (e.g., task construction error, quota, misconfiguration) become terminally `failed` rather than looping in enqueue retry forever? What bounds the enqueue-retry loop and what distinguishes transient from permanent enqueue failure?
2. **Bounded enqueue retries:** how many enqueue attempts are permitted before the record is treated as terminally failed, and with what backoff/spacing consistent with (but not conflated with) the five FCM send attempts?
3. **Expired-lease recovery:** how does a `processing` task whose worker died (lease expired) get recovered, and how is that kept race-free against a still-running worker?
4. **Duplicate scheduling prevention:** the proposed deterministic document ID prevents duplicate outbox records; how is duplicate *enqueueing* and duplicate *claiming* prevented as far as Firestore/Cloud Tasks segmentation allows (transactional claiming, task-name idempotency keys, lease ownership checks)?
5. **Duplicate delivery window:** a duplicate delivery can occur when FCM accepts a send and the worker crashes before recording the result — the retry will send again. This must be documented as a known operational limitation; **exactly-once delivery must not be promised** (ADR-008 Section H).
6. **Final-failure recording and operational surfacing:** after all attempts (or terminal enqueue failure), where is the final failure recorded (outbox record fields — error code, attempt count, timestamps), how is it distinguished from a transient failure, and how is it surfaced to Doctor/Admin operations (dashboard review surface, alert, or scheduled reconciliation report) so a permanently undelivered security alert is noticed?

The outbox state machine is not implemented and its full transition/failure design remains a schema/design approval prerequisite recorded in the proposal.

## 10. Cross-document alignment notes (ADR-008 vs Draft 06)

Conflict to be aligned in future governance-approved work:

- **ADR-008 (Approved policy):** five total notification attempts (1 initial + 4 retries) with fixed delays 30 s / 2 m / 10 m / 30 m, delivered via the Firestore Outbox + Cloud Tasks intended architecture, with final failure recorded after exhaustion.
- **Draft 06 (`docs/notion/06_FIREBASE_ARCHITECTURE .md`, Draft — not authoritative):** Section "7.2 Retry Logic" proposes retries with exponential backoff "up to 3 attempts" and Section "7.3 Dead Letter Queue (DLQ)" proposes a `notification_dlq` collection for exhausted notifications.

The existing production notification code (general notifications, outside ADR-008's scope) follows the Draft-06-style pattern: `MAX_NOTIFICATION_RETRIES = 3` with a fixed retry-delay ladder and a `notification_dlq` collection (`functions/src/index.ts`, section "Dead Letter Queue"). The general-notification retry policy is **out of ADR-008's scope** and unchanged. Required future alignment, without silently editing the Draft and without claiming any of this is implemented: when the security-event notification path is implemented under ADR-008, the security notification path uses the approved 5-attempt Reliable Retry within the Outbox + Cloud Tasks architecture; Draft 06 should be aligned (as a Draft, through its own document workflow) so it no longer implies that all notifications — including security notifications — use the 3-attempt/exponential-backoff/DLQ model, or it should explicitly scope the DLQ model to the inline `notifications` collection path only.

Other cross-reference corrections/clarifications recorded (per Section 8.2): Draft 14 does not define a canonical `other` identifier; Draft 14's proposed `security_events` retention value (3 years) coincides with the approved retention period but Draft 14 remains non-authoritative; Draft 15's Admin action-review permissions concern auditing Admin actions, not security-notification recipients, and do not make Admin a recipient.

`04_FEATURES.md` remains Approved Version 2.0 with its stale "Notify administrators." recipient text pending the versioned amendment (governance blocker B-1). The Admin "Send Notifications" capability in `05_DATABASE_v1.7.md` Section 21 ("Security Overview") is a sending capability for the general notification system, not receipt of ADR-008 security notifications, and is unchanged.

## 11. Database governance alignment

- `05_DATABASE_v1.7.md` (Version 1.7, Approved) is **not modified** by this reconciliation and remains the database baseline. It defines neither `security_events` nor `security_notification_outbox`.
- `security_events` and `security_notification_outbox` remain **Proposed** pending formal database approval, per the proposal document, which this reconciliation updates with the missing design approval prerequisites (rate-limit counter storage, payload rejection behavior, recipient resolution, vocabulary, outbox terminal-failure design, retention mechanics, indexes/access boundaries, target database version).
- No individual schema field or index is marked Approved by this work; the only Approved content for these collections is the policy layer in ADR-008.
- The ADR-006 `auth_security_events` collection (authentication-lockout auditing, no push notification) remains a distinct, Approved-purpose collection and must not be conflated with the proposed general `security_events` collection.

## 12. Security goals and platform constraints (recorded, not implementation authority)

The following owner-level objectives and constraints are recorded. They state goals and constraints, not implemented controls, and do not authorize architectural changes or production implementation. None of these is claimed as an implemented control without evidence:

- Protect videos, PDFs, account access, and backend services from unauthorized access (approved baseline: content protection layers, Subject-Level Device Binding, server-signed delivery, Security Rules, callable-scoped Functions).
- Use platform-supported screenshot and screen-recording protections/detection **where available** on each platform; capability is platform-dependent.
- External cameras pointed at the screen and compromised/rooted devices **cannot be completely controlled by the application**; this limitation is acknowledged and not claimed away by the watermark or detection features.
- Use server-side rate limiting and abuse protection (ADR-006 for registration/staff-login/payment/activation flows; ADR-008 for security-event ingestion/pages) to reduce brute-force attempts, excessive load, and avoidable service cost.
- Preserve normal Student, Doctor, and Admin workflows; no workflow is interrupted by this documentation reconciliation.
- Preserve approved Figma designs and existing UI behavior unless a separately approved requirement demands a change.
- Do not introduce punitive behavior merely because a device or event is suspicious: ADR-008 already excludes automatic punishment; the older playback-interrupting actions remain an open owner question (Section 8.3, item 3).
- No security control may be described as implemented without evidence; the statements in this record and the related documents distinguish implemented behavior from approved policy and proposed design.

## 13. Remaining owner decisions and governance blockers (consolidated)

| ID | Type | Item |
|---|---|---|
| B-1 | Governance blocker | Versioned amendment of `docs/notion/04_FEATURES.md` aligning the "Notify administrators." sentence with the approved Doctor-only recipient rule. Implementation of the recipient rule is formally blocked until completed. Currently NOT performed. |
| B-2 | Owner decision | Approve the canonical event identifier set (for the concepts Screenshot, Screen recording, Jailbreak, Rooted device, Emulator — and explicitly resolving the deferred generic `other`). |
| B-3 | Owner decision | Approve the exact `action_taken` vocabulary and classify every action as recording-only, notification-only, or potentially punitive; reconcile the older Feature 05 playback-interrupting actions with the no-automatic-punishment policy. |
| B-4 | Owner decision | Decide the disposition of `low` and `critical` severity literals present in code and Draft 14. |
| B-5 | Governance blocker | Formal database approval (field-by-field `security_events` + `security_notification_outbox`, document identity, indexes, Security Rules/service-account permissions, outbox retention and both purge/archive mechanics, target database version) **plus** the newly recorded design prerequisites: atomic rate-limit counter storage design; whole-event vs metadata-only payload rejection decision; recipient-resolution design; complete outbox state transitions including terminal enqueue-failure handling. |
| B-6 | Implementation prerequisite | Deterministic, secure server-side resolution of the single Platform Owner recipient account, verified against the actual migration state of ADR-005 (`teacher` not yet migrated). Design approach itself requires an owner decision. |
| B-7 | Governance blocker | Separate, explicit implementation authorization. |

## 14. Validation evidence

- Documentation-only task. This record and the updated proposal are the only documentation changes made in this reconciliation.
- No source code (Dart, TypeScript, JavaScript), tests, Security Rules, indexes, Firebase configuration, Cloud Tasks configuration, IAM, service accounts, or deployment files were modified.
- No deployment, migration, notification delivery, or Firestore/Auth writes were performed.
- Pre-existing modified working-tree files and pre-existing untracked files (`19_ADR_008…`, `security_events_database_change_proposal.md`, `docs/RELEASE_READINESS_HANDOFF_2026-10-20.md`, …) were preserved; nothing was deleted, reverted, reset, stashed, staged, or committed.
- `05_DATABASE_v1.7.md` was left unchanged and was not altered.

## 15. Production safety

Recorded explicitly: no production deployment, no production Firestore or Auth writes, no commits, no staging, and no destructive git operations were performed as part of this reconciliation. Implementation was not started. Nothing in this record should be cited as evidence that the platform is secure or release-ready.
