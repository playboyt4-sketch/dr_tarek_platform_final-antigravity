# Feature 14 — Database Version Change Log

**Baseline:** `05_DATABASE_v1.7.md` — Version 1.7 — Approved  
**Proposed target:** `05_DATABASE_v1.8.md` — Version 1.8 — Proposed, pending Teacher Database Change approval  
**Reason:** Feature 14 Membership + Independent Subject Access + updated approval/access rules.

## Change summary

Version 1.8 preserves the complete Version 1.7 content and adds only the approved Feature 14 database changes. It does not authorize implementation or deployment. Version 1.7 remains the approved production baseline until this proposal is approved.

| # | Version 1.7 area | Version 1.8 change | Type |
|---:|---|---|---|
| 1 | Database collections | Added top-level `subject_access_assignments`. | Schema addition |
| 2 | Document identity | Added deterministic ID `{student_id}_{subject_id}` for one student/subject pair. | Constraint |
| 3 | Subject Access schema | Added `student_id`, `subject_id`, `enabled`, common audit fields, and soft-delete fields. | Schema addition |
| 4 | Relationships | Added `users → subject_access_assignments ← subjects`; kept `subscriptions` independent. | Relationship |
| 5 | Entitlement | Changed evaluation order to Subject Access → Subscription → Active Plan → `plan_features` → Entitlement. | Business/data rule |
| 6 | Denial | Missing or disabled Subject Access now returns DENY, including when Subscription and Plan would otherwise be valid. | Security/access rule |
| 7 | Free Plan | First-open Free Plan activation is conditional on a non-deleted enabled Subject Access assignment. | Membership rule |
| 8 | New Student Approval | Approval persists Student Type and per-subject Toggle Switch configuration as assignments. | Approval rule |
| 9 | New Student defaults | Removed default-all-subjects access; no assignment is created without explicit approved configuration. | Access rule |
| 10 | Subject Access mutation | Only Teacher or explicitly delegated Admin may mutate assignments; Students are denied and Admins cannot self-grant. | Security rule |
| 11 | Subject Access audit | Every mutation requires server-side actor, target, old/new state, permission basis, and timestamp audit data. | Audit rule |
| 12 | Migration | An active, non-deleted subject Subscription maps to `enabled = true`; no active, non-deleted subject Subscription maps to `enabled = false`, unless an explicit authoritative administrative access source is already documented in approved architecture. Learning artifacts and Grade membership alone do not grant access; migration must be idempotent. | Migration rule |
| 13 | Student Type conversion | Conversion checks active, non-deleted subscriptions; an incompatible plan causes STOP with no automatic conversion, downgrade, deletion, or Student Type change. | Membership rule |
| 14 | Gift Membership | Removed from current business flow, including UI/callable/repository/provider/permission/analytics/tests/lifecycle. | Deprecation |
| 15 | Subscription legacy fields | `is_gifted` and `gifted_by` remain as legacy/deprecated fields and are not deleted or used. | Compatibility rule |
| 16 | Payment | External/manual payment remains; checkout, gateway, card payment, in-app purchase, and automatic online payment are excluded. | Business boundary |
| 17 | Composite indexes | Added `student_id + is_deleted + enabled` and `subject_id + is_deleted + enabled` for assignment collection queries. | Index proposal |
| 18 | Security overview | Added delegated Subject Access management boundary and Student mutation denial. | Security documentation |
| 19 | Query patterns | Dashboard and Membership queries now traverse Subject Access before Subscription and feature resolution. | Query contract |
| 20 | Source reconciliation | Recorded v1.7 as current baseline, v1.6 Notion as older reference, and root `05_DATABASE.md` as ADR fragment. | Documentation |
| 21 | Migration query contract | Replaced broad "learning-access evidence" wording with an explicit active, non-deleted subject Subscription query contract and an explicit exclusion list for historical learning artifacts. | Documentation clarification |
| 22 | Common identity convention | Clarified that `id` is the Firestore Document ID and is not necessarily a duplicated stored field; the deterministic Subject Access Document ID is sufficient. | Documentation clarification |

## Explicitly unchanged

The following remain unchanged from Version 1.7 unless a future approved change says otherwise: Firestore as the database engine; Firebase Authentication; Firebase Storage; FCM storage policy; common audit and soft-delete conventions; Device Binding; video and offline learning data; learning progress and completion models; plan and `plan_features` structures; one active Subscription per subject; external payment logging; academic term visibility rules; Firestore as the source of truth; Repository-only access; and the existing legacy `is_gifted`/`gifted_by` fields. Historical learning artifacts remain historical data and do not independently authorize Subject Access migration.

The current Video, Auth, Device Binding, and Offline Learning implementations are outside this Database Change. No schema change in Version 1.8 authorizes rebuilding them. The Migration Query Contract and Firestore Document ID clarification are documentation corrections only and do not add a new business rule or stored field.

## Approval gate

**Status:** **BLOCKED pending Teacher review of the proposed Database Change.**

Until approval, Version 1.7 remains the sole approved baseline. No application code, Cloud Functions, Firestore Rules, `firestore.indexes.json`, migration, Firestore data, or implementation tests may be changed or executed under this documentation-only step.
