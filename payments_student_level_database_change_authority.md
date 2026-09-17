# Payments — Student-Level Financial Model: Database Change Authority

**Project:** Dr. Tarek Platform
**Change:** Student-level financial account + student-level payment aggregation, cap, and method set (incl. `bank`); `subject_id` demoted to nullable legacy metadata; retirement of the unapproved Student × Subject financial model.
**Baseline:** `05_DATABASE_v1.7.md`
**Baseline status:** Version 1.7 — Approved
**Related proposal (untouched):** `05_DATABASE_v1.8.md` (Proposed — Pending Teacher Database Change Approval)
**Authority:** Teacher (Platform Owner)
**Current implementation status:** Documentation proposal only — no application code, Cloud Functions, Firestore Rules, indexes, migration, dashboard/mobile code, or tests executed.

## 1. Purpose and authority boundary

This document authorizes the proposed **Database Change** for Payments only. It records the finalized Teacher business model for student-level payments and explicitly supersedes the previously *implemented but never approved* Student × Subject financial model. It does not authorize application implementation, Cloud Functions, Firestore Rules deployment, index deployment, migration execution, or production-data mutation. Those activities remain blocked until this Database Change is reviewed and approved.

The change is evaluated against the verified `05_DATABASE_v1.7.md` baseline and the untouched `05_DATABASE_v1.8.md` proposal. Unrelated baseline sections remain unchanged unless this document explicitly supersedes a rule. No rule is inferred from missing or partial database files, and no legacy data is deleted by this change.

> **Authoritative evaluation order for Payments:** Student Financial Account → Student Payment Aggregation → Student-Level Cap → Audit/Soft-Delete. Subject plays no role at any step.

## 2. Verified baseline

`05_DATABASE_v1.7.md` remains the approved baseline (Version 1.7 — Approved; added `devices.fcm_token`). Its `payment_logs` section (also carried into the `05_DATABASE_v1.8.md` proposal, `## payment_logs`) describes:

- Student ID, Subject ID, Amount, Payment Date, Collected By, Receipt Number, Notes.
- Purpose: externally-collected payments recorded manually, for record-keeping only.
- Relationship tree parents `payment_logs` under `users` only (not under `subjects`).
- Approved composite index: `payment_logs: student_id + payment_date` (no subject component).

No approved baseline or proposal defines Price, Discount, Net, Paid, Balance, a financial-account entity, per-Subject payment allocation, or per-Subject payment caps. Those concepts exist only in unapproved implementation (see §9).

## 3. Student financial account collection

### 3.1 Collection and document identity

The new collection is a top-level Firestore collection named `student_financial_accounts`. It is independent from `subscriptions`, `subject_access_assignments`, plans, and membership records. Payment state must not be stored inside a subscription document, and subscription state must not be stored inside a financial account.

Each student has exactly ONE financial account. Each document uses the deterministic ID:

```text
{student_id}
```

i.e. the document ID equals `users/{student_id}`. A second financial account document for the same student is not permitted.

### 3.2 Complete schema

| Field | Type | Required | Meaning |
|---|---|---:|---|
| `student_id` | String | Yes | Reference to `users/{student_id}`; equals the document ID. |
| `price_egp` | Number | Yes | Teacher-entered price (≥ 0). |
| `discount_egp` | Number | Yes | Teacher-entered discount (≥ 0, ≤ `price_egp`). |
| `net_egp` | Number | Yes | Derived: `price_egp − discount_egp`. Stored, never client-computed as truth. |
| `created_at` | Timestamp | Yes | Creation timestamp. |
| `updated_at` | Timestamp | Yes | Last mutation timestamp. |
| `created_by` | String | Yes | Actor or server identity that created the account. |
| `updated_by` | String | Yes | Actor or server identity that last updated the account. |
| `is_deleted` | Boolean | Yes | Soft-delete flag. |
| `deleted_at` | Timestamp or null | Yes | Soft-delete timestamp, null while active. |
| `deleted_by` | String or null | Yes | Deleting actor, null while active. |

The document follows the common-field and soft-delete conventions of the baseline. The `id` is represented by the Firestore document ID and is not duplicated as a business field unless the existing repository convention requires it.

### 3.3 Financial calculation (normative)

```text
net_egp = price_egp − discount_egp
paid    = SUM(payment_logs.amount WHERE student_id matches AND is_deleted != true)
balance = net_egp − paid
```

`paid` and `balance` are derived, never stored. `subject_id` must not participate in any term of these calculations.

### 3.4 Relationships

`student_financial_accounts.student_id` references `users`. The account does not reference or contain `subject_id`, `plan_id`, subscription status, device state, or feature flags.

The relationship graph gains the following edge:

```text
users ──< student_financial_accounts (one per student)
users ──< payment_logs (many per student)
```

## 4. Payment transaction contract (student-level)

### 4.1 Complete field set for new records

| Field | Type | Required | Meaning |
|---|---|---:|---|
| `student_id` | String | Yes | Payer; reference to `users/{student_id}`. Immutable after creation. |
| `amount` | Number | Yes | Transcribed collected amount (> 0). |
| `payment_date` | Timestamp | Yes | Transcribed paper date; today or past, never future. |
| `payment_method` | String | Yes | One of `cash`, `e_wallet`, `instapay`, `bank` (descriptive only). |
| `collected_by` | String | Yes | Manual free-text collector name (never a UID), ≤ 100 chars. |
| `receipt_number` | String | Yes | Non-empty receipt reference. |
| `notes` | String or null | No | Optional notes, ≤ 500 chars. |
| `created_by` | String | Yes | Transcribing Teacher UID, server-derived. |
| `created_at` | Timestamp | Yes | Server creation timestamp. |
| `updated_by` | String | Yes | Last correcting Teacher UID, server-derived. |
| `updated_at` | Timestamp | Yes | Last mutation timestamp. |
| `is_deleted` | Boolean | Yes | Soft-delete flag. |
| `deleted_at` | Timestamp or null | Yes | Soft-delete timestamp, null while active. |
| `deleted_by` | String or null | Yes | Deleting actor, null while active. |

### 4.2 Payment method set

The canonical method set is `cash`, `e_wallet`, `instapay`, **`bank`**. `bank` is intentionally supported because historical paper/Word records contain Bank transactions (see the approved Figma Payments history). The method remains descriptive only — no payment logic may depend on it.

### 4.3 `subject_id` treatment (normative)

- Existing `payment_logs` records may already contain `subject_id`. Those values are **not deleted, migrated, or re-attributed** by this change.
- For the new model, `subject_id` on new payment records is **OPTIONAL / nullable legacy metadata** (a descriptive tag only), unless a future approved decision requires another exact treatment.
- `subject_id` must NOT participate in: financial calculations, payment caps, balance calculations, account lookup, or payment aggregation.
- Correction must never mutate `subject_id` semantics: if present on a historical record it stays frozen as descriptive text; new records may omit it entirely.

## 5. Payment enforcement (normative)

A new payment is valid only when:

```text
SUM(existing non-deleted payment_logs.amount WHERE student_id matches)
  + new payment amount
  <= student_financial_accounts{student_id}.net_egp
```

- Recording requires an existing, non-deleted student financial account; otherwise the write is rejected (`failed-precondition` class).
- Correction performs the same student-level validation while **excluding the payment being corrected** from the sum.
- `student_id` linkage, `created_by`, and `created_at` are immutable on correction. Only amount, method, collector, date, receipt, and notes are correctable.
- Enforcement is server-side (callable + rules posture unchanged: client writes remain denied). No subscription or membership state may be read or mutated by payment enforcement.

## 6. Authorization, audit, soft-delete

Teacher (Platform Owner, `role = teacher`) remains the **only** role allowed to create or correct payment records and financial accounts. Delegated admins have no payment-write rights. `created_by` / `updated_by` are server-derived from the authenticated Teacher, never client-supplied.

Every payment and account mutation must record a server-authoritative `admin_audit_log` action containing at least: actor, actor role (`teacher`), target student ID, previous/new values (for corrections and account updates), server timestamp, and permission basis (`teacher`). Existing soft-delete conventions (`is_deleted` filtering in all aggregations) are preserved unchanged.

## 7. Subscription/membership separation

Payments are completely unrelated to Subscriptions and Memberships. Payment records never grant, modify, or revoke access, plans, or entitlements; membership evaluation never reads payment or financial-account state. The per-Subject membership model (FINAL_DECISIONS §§5, 14, 16; 05 Database §12 Membership) is unaffected by this change.

## 8. Historical-data policy (normative)

1. No automatic re-attribution of historical payments.
2. No splitting of historical payments by Subject.
3. No merging of `student_subject_accounts` (per-pair) records into student financial accounts — per-pair Nets cannot be combined without inventing allocation.
4. Existing `student_subject_accounts` documents, if present, are **deprecated/inert**: reads for finance must stop using them; physical deletion requires a separate approved migration decision.
5. `subjects.price_egp` / `subjects.discount_egp` (if ever backfilled) are inert leftovers, never a source for financial accounts; cleanup requires a separate approved decision.
6. The Teacher manually enters the correct student-level Price/Discount per student from the paper/Word records (data-entry step, not a migration). Until an account exists, new payments for that student are rejected per §5.

## 9. Superseded unapproved implementation

The following were **implemented without an approved decision** and are explicitly superseded by this change. They appear in no approved baseline, proposal, FINAL_DECISIONS section, or Master Architecture rule:

| Unapproved implementation | Location | Superseding rule in this document |
|---|---|---|
| Required `subjectId` on payment recording | `onPaymentLogged` contract | §4 (`student_id` only required), §4.3 |
| Per-Student × Subject account gate ("No financial record exists for this student and subject") | `onPaymentLogged`, `readSubjectAccount` | §3 (one account per student), §5 |
| Per-pair Over-Net cap via `sumPaidForPair` (student + subject filter) | `onPaymentLogged`, `correctPaymentLog` | §3.3, §5 (student-level sum + cap) |
| `setStudentSubjectAccount` callable + `student_subject_accounts` collection (`{studentId}_{subjectId}` docs) | backend + tests | §3 (replaced), §8.4 (deprecated/inert) — **retired** |
| `backfill_subject_prices` script (`price_egp`/`discount_egp` on `subjects`) + `backfill:prices` npm entry | `functions/src/scripts/`, `functions/package.json` | §8.5 — **retired**, never sourced |
| Method set without `bank` (`PAYMENT_METHODS = cash, e_wallet, instapay`) | `parsePaymentMethod` | §4.2 — **extended with `bank`** |
| Per-pair ledger expectations (subject-scoped Totals, subject-gated writes) | `payment_logged.test.js`, `payment_correction.test.js`, dashboard per-pair ledger | §3.3, §5 — tests to be rewritten to the student-level contract |

The "Payment Transcription ADR" cited in test-file headers is code-comment-only authority, not an approved project document; its per-pair clauses are superseded, while its Teacher-only, server-attribution, audit, and soft-delete clauses are ratified in §6.

## 10. Approved-documentation disposition (no silent rewrites)

- **Superseded in effect (explicitly, by this record):** the `payment_logs` "Subject ID" line and "membership tracking" purpose as stated in `05_DATABASE_v1.7.md` (`## payment_logs`) and carried into `05_DATABASE_v1.8.md` (`## payment_logs`). Neither file is edited by this step.
- **Compatible, no change needed:** FINAL_DECISIONS §6 (Teacher-only manual entry + confirmation); `00_MASTER_ARCHITECTURE.md` §7 (external, record-keeping-only; online payments deferred); PRD Financial Modules exclusion (no ERP/accounting in V1 — this change adds no ERP, only the mandated student balance); `09_TASKS.md` T-CF.14 scope (manual Teacher entry + notification); all subscription/membership sections.
- **Fold-in instruction:** on Teacher approval of this change, its schema (§3–§4), enforcement (§5), and retirements (§8–§9) are to be incorporated into the next proposed `05_DATABASE` snapshot and the Firebase Architecture function table as new version-history entries. This document remains the change authority; the snapshots themselves are not edited here.

## 11. Query patterns and indexes

| Use case | Query path | Required behavior |
|---|---|---|
| Account lookup | `student_financial_accounts/{student_id}` (direct doc read) | Require `is_deleted != true`; use `net_egp` as the cap. No composite index required. |
| Paid aggregation | `payment_logs WHERE student_id == X` (client-side soft-delete filter + sum, or server aggregation) | Ignore `subject_id` entirely. Existing approved composite `payment_logs: student_id + payment_date` already serves this pattern — no new index in this step. |
| Teacher student review | Query `payment_logs` by `student_id`, excluding soft-deleted | Oldest → newest ordering applied at read/display time. |

No index file is changed in this documentation-only step; deployment remains pending Database Change approval and implementation review.

## 12. Deployment and approval gate

This document is a proposal for Teacher review. Until explicit Database Change approval is recorded:

- `05_DATABASE_v1.7.md` remains the approved baseline.
- `05_DATABASE_v1.8.md` remains the untouched pending proposal.
- `docs/notion/05_DATABASE.md` remains the older reference; root `05_DATABASE.md` remains the ADR-003 fragment.
- No application code, Cloud Functions, Firestore Rules, indexes, migration scripts, dashboard/mobile code, tests, or Firestore data may be changed.
- No implementation or migration validation may be claimed.

## 13. References

1. [Verified Database baseline — 05_DATABASE_v1.7.md](./05_DATABASE_v1.7.md)
2. [Proposed Database Version 1.8 (untouched)](./05_DATABASE_v1.8.md)
3. [Feature 14 Database Change Authority (governance precedent)](./feature_14_database_change_authority.md)
4. [Master Architecture §7 — external manual record-keeping](./docs/notion/00_MASTER_ARCHITECTURE.md)
5. [FINAL_DECISIONS §6 — Teacher-only manual payment entry](./docs/notion/FINAL_DECISIONS.md)
6. [Tasks T-CF.14 — manual payment entry scope](./docs/notion/09_TASKS%20.md)
