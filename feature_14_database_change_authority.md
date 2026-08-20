# Feature 14 — Database Change Authority

**Project:** Dr. Tarek Platform  
**Change:** Membership Plans + Independent Subject Access + Approval/Access Rules  
**Baseline:** `05_DATABASE_v1.7.md`  
**Baseline status:** Version 1.7 — Approved  
**Target:** Proposed `05_DATABASE_v1.8.md`  
**Authority:** Teacher (Platform Owner)  
**Current implementation status:** Documentation proposal only — no code, Firebase, indexes, migration, or tests executed.

## 1. Purpose and authority boundary

This document authorizes the proposed **Database Change** for Feature 14 only. It translates the already-approved Teacher decisions into a versioned Firestore specification. It does not authorize application implementation, Cloud Functions, Firestore Rules deployment, migration execution, or production-data mutation. Those activities remain blocked until this Database Change and the proposed Version 1.8 are reviewed and approved.

The change is based directly on the verified `05_DATABASE_v1.7.md` baseline. Unrelated Version 1.7 sections remain unchanged unless this document explicitly supersedes a rule. No rule is inferred from the missing or partial database files, and no legacy data is deleted by this change.

> **Authoritative evaluation order:** Subject Access → Subscription → Active Plan → `plan_features` → Entitlement.

## 2. Verified baseline

The supplied file was copied into the project as `05_DATABASE_v1.7.md` without content modification. Its header is:

| Field | Verified value |
|---|---|
| Version | `1.7` |
| Status | `Approved` |
| Baseline reason | Added `devices.fcm_token` to the approved database schema. |
| Source checksum | `70132c313af4db45c1778d65fa695d398d96d7ae98b12b8d492ea5eb8aa1fa17` |

The project copy and the supplied attachment have the same SHA-256 checksum. Version 1.7 is preserved as the previous approved baseline and is not modified in place.

## 3. Subject Access collection

### 3.1 Collection and document identity

The new collection is a top-level Firestore collection named `subject_access_assignments`. It is independent from `subscriptions`; the boolean access state must not be stored inside a subscription document.

Each document uses the deterministic ID:

```text
{student_id}_{subject_id}
```

The implementation must construct this ID deterministically from the two referenced IDs. A second assignment document for the same student/subject pair is not permitted.

### 3.2 Complete schema

| Field | Type | Required | Meaning |
|---|---|---:|---|
| `student_id` | String | Yes | Reference to `users/{student_id}`. |
| `subject_id` | String | Yes | Reference to `subjects/{subject_id}`. |
| `enabled` | Boolean | Yes | Internal access decision. `true` grants the Subject Access gate; `false` denies it. |
| `created_at` | Timestamp | Yes | Creation timestamp. |
| `updated_at` | Timestamp | Yes | Last mutation timestamp. |
| `created_by` | String | Yes | Actor or server identity that created the assignment. |
| `updated_by` | String | Yes | Actor or server identity that last updated the assignment. |
| `is_deleted` | Boolean | Yes | Soft-delete flag. |
| `deleted_at` | Timestamp or null | Yes | Soft-delete timestamp, null while active. |
| `deleted_by` | String or null | Yes | Deleting actor, null while active. |

The document follows the common-field and soft-delete conventions of the baseline. The `id` is represented by the Firestore document ID and is not duplicated as a business field unless the existing repository convention requires it.

### 3.3 Relationships

`subject_access_assignments.student_id` references `users`. `subject_access_assignments.subject_id` references `subjects`. The assignment does not reference or contain `plan_id`, subscription status, payment state, or feature flags. Subscription remains the separate subject-scoped membership record.

The relationship graph gains the following edges:

```text
users ──< subject_access_assignments >── subjects
users ──< subscriptions >── subjects
```

A Grade-to-Subject relationship alone is not evidence of individual Subject Access and must not be used to create an enabled assignment during migration.

## 4. Access and entitlement constraints

The following constraints supersede conflicting Version 1.7 rules for this Feature 14 change:

1. Subject Access is evaluated before Subscription.
2. A missing Subject Access assignment denies access.
3. An assignment with `enabled = false` denies access.
4. The denial remains effective even if the subscription is active, the plan is `center_max`, and the relevant plan feature is enabled.
5. A soft-deleted assignment is not a valid enabled assignment.
6. A missing or disabled assignment prevents first-open Free Plan activation.
7. No default-all-subjects access is created for a new student.
8. Subject Access is not a substitute for Subscription, Active Plan, or `plan_features`; all later gates must still pass.
9. Student-facing UI may expose the resulting availability state, but the administrative boolean is represented only by a Toggle Switch. The UI must not display `true`, `false`, `ON`, or `OFF` as the primary control representation.

The normalized decision model is:

```text
subject_access_assignment exists
AND is_deleted = false
AND enabled = true
→ evaluate subscription

otherwise
→ DENY
```

## 5. Query patterns

The following query patterns are part of the proposed database contract:

| Use case | Query path | Required behavior |
|---|---|---|
| Student subject resolution | `subject_access_assignments/{student_id}_{subject_id}` | Read the deterministic assignment, require `is_deleted = false` and `enabled = true`, then continue to Subscription. |
| Student Dashboard | `student → grade → applicable subjects → subject_access_assignments → subscriptions → plan → plan_features` | Return each applicable subject with its resulting availability state; never bypass a disabled/missing assignment. |
| Admin/Teacher student access management | Query assignments by `student_id`, excluding soft-deleted records | Return all applicable subjects and their internal enabled state for Toggle Switch rendering. |
| Admin/Teacher subject roster/migration review | Query assignments by `subject_id`, excluding soft-deleted records | Support subject-scoped review without creating access from Grade membership alone. |
| First-open Free Plan guard | Deterministic assignment lookup followed by subscription lookup | Create a Free Plan only after enabled Subject Access is confirmed. |
| Existing-student migration | Read existing subject subscriptions. For each student/subject pair, an active, non-deleted subject Subscription produces `enabled = true`; no active, non-deleted subject Subscription produces `enabled = false`, unless an explicit authoritative administrative access source already exists in the approved project architecture. | Do not use `learning_progress`, `lecture_progress`, `bookmarks`, `notes`, `exam_attempts`, `analytics`, historical activity, or Grade-to-Subject membership as independent authorization evidence. The migration is idempotent and never mutates protected learning or history collections. |

A direct deterministic document lookup does not require a composite index. Collection queries that include soft-delete and enabled predicates use the indexes listed below.

## 6. Proposed composite indexes

The proposed Version 1.8 index additions are limited to the query patterns above:

```text
subject_access_assignments
student_id + is_deleted + enabled

subject_access_assignments
subject_id + is_deleted + enabled
```

No index is added for the deterministic document ID lookup. The index file must not be changed in this documentation-only step; deployment remains pending Database Change approval and implementation review.

## 7. Security model and authority

Teacher (`role = teacher`) remains authoritative. A Student cannot create, update, delete, enable, disable, or otherwise mutate Subject Access. An Admin may mutate Subject Access only when the Teacher has explicitly delegated the required permission through the existing data-driven `admin_permissions` mechanism. An Admin cannot self-grant the permission.

Client-side Flutter state is not the final authorization authority. Cloud Functions and Firestore Rules must enforce the same decision server-side. All mutations must validate the target student and subject, enforce the deterministic document ID, reject unauthorized actors, apply soft-delete conventions, and write audit attribution.

This change does not introduce a parallel permissions system. It uses the existing `admin_permissions` and `activeAdminPermission()` architecture, with a dedicated permission key for Subject Access to be defined during implementation only if it is not already present. The exact key must not be invented in this documentation beyond the required capability: manage Subject Access.

## 8. Audit integration

Every Subject Access mutation must record an auditable action containing at least:

| Audit attribute | Required meaning |
|---|---|
| Actor | Teacher or delegated Admin UID. |
| Actor role | `teacher` or `admin`. |
| Target | Student ID and Subject ID. |
| Previous state | Previous enabled/deleted values, or null for creation. |
| New state | New enabled/deleted values. |
| Timestamp | Server-side mutation timestamp. |
| Permission basis | Teacher authority or delegated permission. |
| Action | Create, enable, disable, soft-delete, or restore, as applicable. |

Audit records are server-authoritative and must not be client-created in `admin_audit_log`. Approval records separately require `approved_by` and `approved_at`.

## 9. Existing-student migration

Migration is a separate implementation step and is not executed by this Database Change document. Before migration, the implementation must inspect actual project data and code to identify valid access evidence.

The default and authoritative migration evidence is an active, non-deleted subject Subscription. If such a Subscription exists, the deterministic assignment is upserted with `enabled = true`; if no active, non-deleted subject Subscription exists, it is upserted with `enabled = false`, unless an explicit authoritative administrative access source is already documented in the approved project architecture. No alternative source may be inferred from learning artifacts. `learning_progress`, `lecture_progress`, `bookmarks`, `notes`, `exam_attempts`, `analytics`, historical activity, and Grade-to-Subject membership alone are not sufficient authorization evidence.

The migration must be idempotent and must preserve legitimate access. It must not delete or modify existing `subscriptions` or any learning data, including `learning_progress`, `lecture_progress`, `bookmarks`, `notes`, `exam_attempts`, `analytics`, or historical activity. Migration must not silently convert a missing assignment into access based on historical activity.

## 10. Free Plan guard

The existing automatic Free Plan behavior becomes conditional. The backend may create the first subject-scoped Free Plan only when all of the following are true:

1. The student exists and has the requested valid Student Type.
2. The subject exists and is not deleted.
3. A non-deleted Subject Access assignment exists for the deterministic student/subject ID.
4. `enabled = true`.
5. No active subject subscription already exists.
6. The existing approved Free Plan configuration is enabled and resolves to a plan compatible with the Student Type.

If the assignment is missing or disabled, the backend must deny the request and must not create a Subscription.

## 11. Approval integration

During new-student application review, the authorized reviewer selects `public_student` or `center_student`, sees the applicable subjects, and configures each subject with a Toggle Switch. The selected assignment states become the initial `subject_access_assignments` documents when the application is accepted.

Acceptance must persist the student, selected Student Type, selected Subject Access assignments, `approved_by`, `approved_at`, and the corresponding audit action as one authorized server-side workflow. There is no default-all-subjects behavior. The Toggle Switch is the only administrative control representation; the underlying boolean is not rendered as text.

## 12. Student Type conversion

Teacher or an explicitly delegated Admin may request conversion between `public_student` and `center_student`. Before changing `users.student_type`, the server checks every active, non-deleted subject Subscription against the target Student Type.

If any plan is incompatible, conversion stops and returns a conflict containing the student, subject, current Student Type, target Student Type, current plan, and conflicting subscription. The server must not delete the Subscription, downgrade it, convert it, replace it, or change the Student Type automatically. The reviewer must resolve the conflict explicitly before retrying.

If no incompatible Subscription exists, conversion may proceed. Progress, notes, quizzes, exams, analytics, and history are preserved, and the conversion is audited and recorded according to the existing analytics policy.

## 13. Gift Membership treatment

Gift Membership is removed from the current business flow. No Gift UI, callable, repository method, provider, permission, analytics event, test, or lifecycle is part of Version 1.8 implementation.

The existing `subscriptions.is_gifted` and `subscriptions.gifted_by` fields remain in the approved schema as **LEGACY / DEPRECATED** fields for compatibility. They are not deleted, populated, or used by the current Membership workflow. Destructive schema or data removal requires a separate migration decision.

## 14. Payment and term boundaries

Payment remains external only. The application does not implement checkout, a payment gateway, card payment, online subscription purchase, automatic online renewal payment, or promo-code checkout. Teacher/Admin may manually record externally collected payment through the existing payment log flow.

Term START and END actions remain immediate, authorized, and audited. END TERM does not automatically expire Membership or Subject Access. These boundaries do not change the Subject Access schema.

## 15. Chat and notifications boundaries

Chat remains available only to `center_student` according to subject entitlement. `public_student` has no Center Chat. Admin Chat remains two-way, while the Doctor Channel is read-only for students and the Doctor is the Teacher (Platform Owner).

Center communication and learning notifications are available to `center_student` and unavailable to `public_student`. System, authentication, and security notifications are not removed by this change.

## 16. Video and protected-content boundary

The current Video implementation, signed URL validation, Device Binding, playback implementation, and security architecture remain unchanged. The only permitted future integration is passing the unified entitlement result through the existing protected-content gate. This Database Change does not authorize rewriting Video/Auth/Device Binding.

## 17. Superseded Version 1.7 rules

Only the following Version 1.7 rules are superseded for Feature 14:

| Version 1.7 area | Superseding Feature 14 rule |
|---|---|
| User flow / Free Plan | First-open Free Plan activation requires enabled Subject Access. |
| Membership operations | Gift Membership is removed from current flow; legacy fields remain. |
| Student Type conversion | Incompatible active Subscription causes an explicit conversion conflict and STOP. |
| Relationships | `subject_access_assignments` is added independently between users and subjects. |
| Membership check | Subject Access is evaluated before Subscription. |
| Dashboard query | Applicable subjects pass through Subject Access before Subscription and Entitlement. |
| Security | Subject Access mutations require Teacher or explicitly delegated Admin and server audit. |
| New approval | Student Type and per-subject Toggle configuration are persisted on acceptance. |
| Migration | Existing evidence determines enabled state; Grade membership alone does not. |

All unrelated Version 1.7 content remains preserved in the proposed Version 1.8 document.

## 18. Deployment and approval gate

This document and `05_DATABASE_v1.8.md` are proposals for Teacher review. Until explicit Database Change approval is recorded:

- `05_DATABASE_v1.7.md` remains the approved baseline.
- `docs/notion/05_DATABASE.md` remains the older Version 1.6 reference.
- Root `05_DATABASE.md` remains the ADR-003 fragment.
- No application code, Cloud Functions, Firestore Rules, indexes, migration scripts, or Firestore data may be changed.
- No implementation tests or migration validation may be claimed.

## 19. References

1. [Verified Database baseline — 05_DATABASE_v1.7.md](./05_DATABASE_v1.7.md)
2. [Teacher decision — pasted_content_14.txt](../upload/pasted_content_14.txt)
3. [Proposed Database Version 1.8](./05_DATABASE_v1.8.md)
4. [Canonical-source reconciliation note](./feature_14_database_v1.8_source_reconciliation.md)
