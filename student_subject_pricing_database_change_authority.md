# Manual Student-Subject Pricing — Database Change Authority

**Project:** Dr. Tarek Platform
**Change:** Manual per-Student × Subject Price/Discount/Net display/reference data (`student_subject_pricing`); student-level payments unchanged.
**Baseline:** `05_DATABASE_v1.7.md`
**Baseline status:** Version 1.7 — Approved
**Related proposal (untouched):** `05_DATABASE_v1.8.md` (Proposed — Pending Teacher Database Change Approval)
**Authority:** Teacher (Platform Owner)
**Current implementation status:** Documentation proposal only — no application code, Cloud Functions, Firestore Rules, indexes, migration, dashboard/mobile code, tests, or Firestore data executed.

## 1. Purpose and authority boundary

This document authorizes the proposed **Database Change** for Manual Student-Subject Pricing only. It records the finalized Teacher business decision: **Price and Discount are entered manually by the Teacher for EACH Student + Subject**, for display in the Payments Figma Subjects table:

```text
No. | Subjects | Grade | Price | Discount | Net
```

Example (Teacher-confirmed, illustrative only — no values are seeded by this change):

```text
Financial Accounting | Grade One | 500 EGP | 50 EGP | 450 EGP
Accounting Ethics    | Grade One | 100 EGP | 50 EGP |  50 EGP
```

This change introduces a **DISPLAY / FINANCIAL-REFERENCE** data structure only. It is **NOT a payment account**. It does not authorize application implementation, Cloud Functions, Firestore Rules deployment, index deployment, migration execution, or production-data mutation. Those activities remain blocked until this Database Change is reviewed and approved.

The change is evaluated against the verified `05_DATABASE_v1.7.md` baseline and the untouched `05_DATABASE_v1.8.md` proposal. Unrelated baseline sections remain unchanged unless this document explicitly supersedes a rule. No rule is inferred from missing or partial database files, and no legacy data is deleted by this change.

> **Authoritative evaluation order for Manual Subject Pricing:** Student Registration (`subject_access_assignments`) → Subject Catalog (`subjects`) → Subject Pricing Reference (`student_subject_pricing`) → Display. Finance and access evaluation never read this collection at any step.

## 2. Verified baseline

`05_DATABASE_v1.7.md` remains the approved baseline (Version 1.7 — Approved). Relevant verified facts:

- Student subject registration = non-deleted `subject_access_assignments/{student_id}_{subject_id}` (`enabled` gate), joined with subject-scoped `subscriptions` → `plans` → `plan_features` for membership/entitlement (carried into the `05_DATABASE_v1.8.md` proposal).
- Student-level finance = `student_financial_accounts/{student_id}` (one account per student: `price_egp`, `discount_egp`, `net_egp`) + student-level `payment_logs` aggregation, per `payments_student_level_database_change_authority.md`.
- `subjects` is a shared catalog (title, grade, visibility, display order). It carries no per-student manual price.
- No approved baseline or proposal defines a per-Student × Subject Price/Discount/Net display entity. Those concepts exist only as unapproved implementation (see §9).

## 3. Subject pricing reference collection

### 3.1 Collection and document identity

The new collection is a top-level Firestore collection named `student_subject_pricing`. It is independent from `subject_access_assignments`, `subscriptions`, plans, `student_financial_accounts`, and `payment_logs`. Pricing reference state must not be stored inside an assignment, subscription, financial-account, or payment document, and access/membership/finance state must not be stored inside a pricing document.

Each (student, subject) pair has **at most ONE** pricing document. Each document uses the deterministic ID:

```text
{student_id}_{subject_id}
```

i.e. the document ID is constructed deterministically from the two referenced IDs, following the `subject_access_assignments` precedent. A second pricing document for the same pair is not permitted.

### 3.2 Complete schema

| Field | Type | Required | Mutable | Meaning |
|---|---|---:|---|---|
| `student_id` | String | Yes | No | Reference to `users/{student_id}`; equals the document ID prefix. Immutable after creation. |
| `subject_id` | String | Yes | No | Reference to `subjects/{subject_id}`; equals the document ID suffix. Immutable after creation. |
| `price_egp` | Number | Yes | Yes | Teacher-entered manual price (≥ 0). Never invented, never defaulted from catalog or student account. |
| `discount_egp` | Number | Yes | Yes | Teacher-entered manual discount (≥ 0, ≤ `price_egp`). Never invented. |
| `net_egp` | Number | Yes | Server-derived | Derived: `price_egp − discount_egp`. Stored, never client-computed as truth. Recomputed server-side on every write. |
| `created_at` | Timestamp | Yes | No | Creation timestamp. |
| `updated_at` | Timestamp | Yes | Yes | Last mutation timestamp. |
| `created_by` | String | Yes | No | Actor or server identity that created the record (server-derived Teacher UID). |
| `updated_by` | String | Yes | Yes | Actor or server identity that last updated the record (server-derived Teacher UID). |
| `is_deleted` | Boolean | Yes | Yes | Soft-delete flag. |
| `deleted_at` | Timestamp or null | Yes | Yes | Soft-delete timestamp, null while active. |
| `deleted_by` | String or null | Yes | Yes | Deleting actor, null while active. |

The document follows the common-field and soft-delete conventions of the baseline (`05_DATABASE_v1.8.md` §4). The `id` is represented by the Firestore document ID and is not duplicated as a business field unless the existing repository convention requires it.

### 3.3 Derivation rule (normative)

```text
net_egp = price_egp − discount_egp
```

`net_egp` is stored for display stability and is always recomputed server-side from the Teacher-entered `price_egp` / `discount_egp`. Clients must never compute or supply it as truth.

### 3.4 Relationships

`student_subject_pricing.student_id` references `users`. `student_subject_pricing.subject_id` references `subjects`. The pricing document does not reference or contain `plan_id`, subscription status, access state, device state, feature flags, payment IDs, or financial-account state.

The relationship graph gains the following edge (display/reference only):

```text
users ──< student_subject_pricing >── subjects (reference only; no finance, no access, no membership)
```

## 4. Authorization, audit, correction, soft-delete

Teacher (Platform Owner, `role = teacher`) is the **only** role allowed to create or correct pricing records. Delegated admins have no pricing-write rights. `created_by` / `updated_by` are server-derived from the authenticated Teacher, never client-supplied.

- Writes go exclusively through a future Teacher-only callable (Admin SDK). **No direct client writes.**
- Corrections update the **same deterministic document ID** (`{student_id}_{subject_id}`); `student_id` / `subject_id` linkage, `created_by`, and `created_at` are immutable.
- Every pricing mutation must record a server-authoritative `admin_audit_log` action containing at least: actor, actor role (`teacher`), target student ID, target subject ID, previous/new values (for corrections), server timestamp, and permission basis (`teacher`).
- Soft-delete follows project convention: `is_deleted` filtering in all reads; a soft-deleted pricing document is excluded from the Subjects table (display falls back to "—", see §5).

## 5. Read purpose and read data (Dashboard Payments Subjects table only)

The **sole** read purpose of `student_subject_pricing` is the Dashboard Payments Subjects table:

```text
No. | Subjects | Grade | Price | Discount | Net
```

Read data per row:

1. **Subject title + grade** from the `subjects` catalog (authoritative for title/grade; a pricing or assignment row whose subject document is gone is skipped, never rendered with invented data).
2. **Student membership/registration** from existing non-deleted `subject_access_assignments` (registered rows only; existing access/subscription evaluation order is unchanged and never reads pricing).
3. **Price / Discount / Net** from `student_subject_pricing/{student_id}_{subject_id}` (stored `price_egp`, `discount_egp`, `net_egp`).
4. **Missing pricing document** (or soft-deleted pricing document) displays **"—"** for Price/Discount/Net. A missing value is never rendered as an invented `0`, never backfilled from `subjects`, and never derived by dividing the student-level account.

Row numbers (`No.`) are presentation-only.

## 6. Critical financial separation (normative)

Student-level Payment Summary is **unchanged** and **never reads** `student_subject_pricing`:

```text
netTotal = student_financial_accounts{student_id}.net_egp
paid     = SUM(payment_logs.amount WHERE student_id == X AND is_deleted != true)
balance  = netTotal − paid
```

Normative prohibitions for `student_subject_pricing`:

- Must NEVER authorize payments.
- Must NEVER calculate payment caps.
- Must NEVER aggregate payments.
- Must NEVER participate in subscription/membership evaluation.
- Must NEVER participate in access authorization (`subject_access_assignments` / entitlement checks).
- Must NEVER replace `student_financial_accounts`.
- Must NEVER be summed into `student_financial_accounts` (`SUM(student_subject_pricing.net_egp)` into the student Net is forbidden — per-pair Nets cannot be combined without inventing allocation).
- Must NEVER recreate `student_subject_accounts` (see §9).

Historical `payment_logs.subject_id` remains **nullable legacy metadata only** (descriptive tag; frozen on historical rows, omittable on new rows) and must not participate in any calculation, cap, lookup, or aggregation, per `payments_student_level_database_change_authority.md` §4.3.

## 7. Subscription/membership separation

Pricing reference is completely unrelated to Subscriptions and Memberships. Pricing records never grant, modify, or revoke access, plans, or entitlements; membership evaluation never reads pricing state. The per-Subject membership model (FINAL_DECISIONS §§5, 14, 16; 05 Database §12 Membership) is unaffected by this change.

## 8. Historical-data policy (normative)

1. No automatic creation of pricing documents (no backfill, no defaults, no invented values).
2. The Teacher manually enters the correct per-Student × Subject Price/Discount (data-entry step, not a migration).
3. No merging of `student_subject_accounts` (per-pair) records into pricing documents.
4. No summing of pricing Nets into student financial accounts.
5. No re-attribution or splitting of historical payments by Subject.

## 9. Supersession / retirement clause (explicit separation from `student_subject_accounts`)

This collection must NOT revive any retired construct documented in `payments_student_level_database_change_authority.md` §8–§9:

| Retired (must not revive) | Status reaffirmed by this document |
|---|---|
| `student_subject_accounts` collection (`{studentId}_{subjectId}` per-pair financial accounts) | Remains **retired / deprecated-inert**; `student_subject_pricing` is a display/reference collection, not a financial account, and inherits none of its enforcement semantics. |
| `setStudentSubjectAccount` callable | Remains **retired**; pricing writes require a distinct future Teacher-only callable with display-only semantics. |
| Per-subject payment caps (`sumPaidForPair`, subject-scoped Totals, subject-gated writes) | Remain **superseded**; the only cap stays student-level (`SUM(amount WHERE student_id) ≤ student_financial_accounts.net_egp`). |
| Payment-to-subject allocation (required `subjectId` on recording; subject-scoped ledger grouping for finance) | Remains **superseded**; `subject_id` on payments stays nullable legacy memo. |
| `subjects.price_egp` / `subjects.discount_egp` backfill as a pricing source | Remains **retired/inert**; catalog prices are never a source for per-student manual pricing. |

Supersession scope of THIS document: it adds the §3–§4 pricing-reference schema and the §5 display read path. It does not supersede, narrow, or widen the student-level finance rules (`payments_student_level_database_change_authority.md` §3–§6), the Subject Access rules (Feature 14 authority), or any membership/entitlement rule. Neither the approved baseline nor the pending v1.8 proposal is edited by this step.

## 10. Approved-documentation disposition (no silent rewrites)

- **Added in effect (explicitly, by this record):** the `student_subject_pricing` display/reference collection (§3), its Teacher-only write authority (§4), and its table-only read path (§5).
- **Compatible, no change needed:** FINAL_DECISIONS §6 (Teacher-only manual entry); Master Architecture §7 (external, record-keeping-only payments); PRD Financial Modules exclusion (no ERP/accounting in V1 — this change adds no ERP, only the mandated per-subject display reference); `09_TASKS.md` T-CF.14 scope; all subscription/membership sections; `payments_student_level_database_change_authority.md` §3–§6 (student-level finance untouched).
- **Fold-in instruction:** on Teacher approval of this change, its schema (§3), authority (§4), read path (§5), separation (§6–§7), and retirements (§9) are to be incorporated into the next proposed `05_DATABASE` snapshot and the Firebase Architecture function table as new version-history entries. This document remains the change authority; the snapshots themselves are not edited here.

## 11. Query patterns, Rules posture, and index disposition

| Use case | Query path | Required behavior |
|---|---|---|
| Pricing lookup (table join) | `student_subject_pricing WHERE student_id == X` (where-only; soft-delete filtered client-side) + `subjects` catalog join | Missing/soft-deleted pricing doc → display "—". Never invent values. No composite index required under the where-only + client-side filter pattern (same pattern as the Subjects-tab assignment/subscription providers). |
| Single-row correction target | `student_subject_pricing/{student_id}_{subject_id}` (direct doc read/write via callable) | Require Teacher authority; same-ID update; before/after audit. No composite index required. |

Firestore Rules posture (for the future implementation step, not executed here): new `match /student_subject_pricing/{pricingId}` with client reads gated to staff view permission (same posture as `payment_logs` / `student_financial_accounts`: staff read-only visibility) and **all writes denied** (`allow write: if false`) — every mutation goes through the Teacher-only callable via Admin SDK, never direct clients. Students have no direct access to this collection.

No index file is changed in this documentation-only step; deployment remains pending Database Change approval and implementation review.

## 12. Deployment and approval gate

This document is a proposal for Teacher review. Until explicit Database Change approval is recorded:

- `05_DATABASE_v1.7.md` remains the approved baseline.
- `05_DATABASE_v1.8.md` remains the untouched pending proposal.
- `docs/notion/05_DATABASE.md` remains the older reference; root `05_DATABASE.md` remains the ADR-003 fragment.
- `06_FIREBASE_ARCHITECTURE.md`, `firestore.rules`, `firestore.indexes.json`, `functions/`, `dashboard/`, mobile code, tests, and Firestore data remain unchanged.
- No application code, Cloud Functions, Firestore Rules, indexes, migration scripts, dashboard/mobile code, tests, or Firestore data may be changed.
- No implementation or migration validation may be claimed.

## 13. References

1. [Verified Database baseline — 05_DATABASE_v1.7.md](./05_DATABASE_v1.7.md)
2. [Proposed Database Version 1.8 (untouched)](./05_DATABASE_v1.8.md)
3. [Feature 14 Database Change Authority (governance precedent)](./feature_14_database_change_authority.md)
4. [Payments Student-Level Database Change Authority](./payments_student_level_database_change_authority.md)
5. [Master Architecture §7 — external manual record-keeping](./docs/notion/00_MASTER_ARCHITECTURE.md)
6. [FINAL_DECISIONS §6 — Teacher-only manual payment entry](./docs/notion/FINAL_DECISIONS.md)
