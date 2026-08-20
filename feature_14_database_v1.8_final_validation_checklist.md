# Feature 14 — Database v1.8 Final Validation Checklist

**Scope:** Final documentation correction only  
**Baseline:** `05_DATABASE_v1.7.md`, Version 1.7, Status Approved  
**Target:** `05_DATABASE_v1.8.md`, Proposed — Pending Teacher Database Change Approval

| Check | Status | Evidence / result |
|---|---|---|
| Gift Membership is absent from the current `analytics_events` examples. | **PASS** | The `analytics_events` section contains no `Gift Membership` entry. |
| `subscriptions.is_gifted` remains in the proposed schema. | **PASS** | Field retained and labeled `LEGACY / DEPRECATED`. |
| `subscriptions.gifted_by` remains in the proposed schema. | **PASS** | Field retained and labeled `LEGACY / DEPRECATED`. |
| Gift fields are not populated or used by the current Membership workflow. | **PASS** | v1.8 Change Authority explicitly prohibits use, population, and new Gift lifecycle behavior. |
| Migration grants `enabled = true` from an active, non-deleted subject Subscription. | **PASS** | v1.8 Section 24.5 and Change Authority Section 9 state this rule explicitly. |
| Migration grants `enabled = false` when no active, non-deleted subject Subscription exists. | **PASS** | The default migration rule is explicit, subject only to an already documented authoritative administrative source. |
| No arbitrary learning artifact independently grants Subject Access. | **PASS** | `learning_progress`, `lecture_progress`, `bookmarks`, `notes`, `exam_attempts`, `analytics`, historical activity, and Grade-to-Subject membership are explicitly excluded as authorization evidence. |
| Migration remains idempotent. | **PASS** | v1.8 Section 24.5, Change Authority, and Change Log preserve the idempotency requirement. |
| Change Authority Section 5 uses an explicit Migration Query Contract. | **PASS** | The contract reads existing subject subscriptions per student/subject pair, maps active non-deleted Subscription to `enabled = true`, maps no such Subscription to `enabled = false` unless an already documented authoritative administrative source exists, and excludes historical artifacts. |
| The phrase `learning-access evidence` is absent from the migration query contract. | **PASS** | The broad phrase was removed from the Change Authority query row. |
| Common `id` identity is clarified as the Firestore Document ID. | **PASS** | v1.8 Section 4 states that `id` is document identity and need not be duplicated as a stored field. |
| `subject_access_assignments` does not add a duplicated `id` field. | **PASS** | Its deterministic Firestore Document ID is `{student_id}_{subject_id}` and is explicitly sufficient. |
| Existing subscriptions and learning data are not deleted or modified by migration. | **PASS** | The corrected migration wording explicitly protects existing Subscriptions and learning data. |
| Subject Access collection and deterministic ID remain unchanged. | **PASS** | `subject_access_assignments` and `{student_id}_{subject_id}` remain present. |
| Subject Access precedes Subscription, Active Plan, `plan_features`, and Entitlement. | **PASS** | The authoritative order remains unchanged. |
| Missing or disabled Subject Access denies access and blocks first-open Free Plan activation. | **PASS** | Preserved in v1.8 and the Database Change Authority. |
| Version 1.7 baseline was not modified. | **PASS** | Project baseline checksum matches the supplied approved file: `70132c313af4db45c1778d65fa695d398d96d7ae98b12b8d492ea5eb8aa1fa17`. |
| Older v1.6 and ADR-003 files were not silently overwritten. | **PASS** | Existing file checksums remain unchanged and Source Reconciliation Note records their roles. |
| No unrelated Database rules were intentionally changed. | **PASS** | v1.8 was generated from the complete v1.7 baseline and changes are enumerated in the Version Change Log. |
| Database v1.8 is approved for deployment. | **BLOCKED** | Teacher review and explicit Database Change approval are still required. |
| Application code implementation. | **BLOCKED** | Explicitly prohibited in `pasted_content_15.txt`. |
| Firebase / Firestore Rules / indexes modification. | **BLOCKED** | Explicitly prohibited in `pasted_content_15.txt`. |
| Migration execution. | **BLOCKED** | Documentation only; no data inspection or mutation was authorized. |
| `flutter analyze`. | **NOT TESTED** | Application implementation was not changed and tests were explicitly prohibited. |
| `flutter test`. | **NOT TESTED** | Application implementation was not changed and tests were explicitly prohibited. |
| Runtime acceptance flows. | **NOT TESTED** | No implementation or runtime validation was authorized in this documentation step. |

## Final validation outcome

The requested documentation corrections are complete and validated: **Gift Membership is absent from current Analytics Events**, legacy Gift fields remain deprecated, the **Migration Query Contract** uses explicit Subscription-based evaluation without arbitrary learning-access evidence, and the **Firestore Document ID convention** is clarified without adding a duplicated Subject Access `id` field. The documentation package remains **BLOCKED for implementation and deployment** until Teacher grants Database Change approval.
