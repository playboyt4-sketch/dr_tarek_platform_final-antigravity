# ADR-006 — Security Hardening (Authentication Throttling, Payment Idempotency, Audit Events)

Status: Approved
Date: 2026-09-19
Version: 1.0

This ADR records Project-Owner-approved security decisions only. It does
not rewrite older architectural documents, does not promote Draft
documents, and does not alter historical Teacher terminology in prior
records. Current-system references use the canonical role terminology:
Doctor (Platform Owner).

## Decision

### A. Registration throttling

- Scope: IP address.
- Maximum attempts: 10 valid registration submissions.
- Window: 15 minutes.
- Mechanism: the existing transactional sliding-window throttle
  (`slidingWindowAllowed`), evaluated after request-shape validation and
  before the users query, hashing, Auth creation, and notification
  fan-out.
- Registration throttling is isolated from Student login throttling
  (dedicated scope).
- No permanent account lock is created by this mechanism (the window
  slides; malformed requests never consume budget).
- Duplicate-phone `already-exists` behavior is unchanged within budget.

### B. Doctor/Admin login IP throttling

- Scope: IP address.
- Maximum failed attempts: 5.
- Lockout duration: 10 minutes (existing lock ladder value for 5 failures).
- Applies to Doctor/Admin staff authentication
  (`verifyStaffPassword`) only.
- Student login throttling remains separate (dedicated scope).
- The existing per-identity (`staff_login`) staff throttle remains in
  place; success continues to clear only the per-name scope, never the
  IP scope.
- Generic authentication behavior is preserved (identical
  `unauthenticated` / "Invalid name or password." for unknown names,
  wrong passwords, and throttled callers; ambiguous-name behavior
  unchanged).

### C. Payment operations — single-operator model

The Project Owner (Doctor) is the sole operator for payment and
subscription operations. The system does not require a multi-operator
payment concurrency model. Duplicate request protection is nevertheless
required because a single authorized operator can accidentally generate
duplicate requests through double-click, network retry, client retry,
repeated submission, or stale UI requests.

### D. `onPaymentLogged` idempotency

Approved implementation:

- Deterministic payment document identity derived from the request's
  business identity: studentId + receiptNumber + amount + method +
  rawDate (`pay_` + 32 hex chars of SHA-256).
- Transactional get-or-create: an identical logical request converges to
  the same payment record.
- A repeated identical request creates no duplicate ledger, audit,
  analytics, or notification side effects (identical response shape).
- Genuinely different payment data (different receipt, amount, method,
  or date) remains independently recordable.

Residual limitation (recorded, not a rule): a corrected payment whose
receipt number is later reused with otherwise identical identity inputs
could theoretically converge to the previous operation. This observation
does not authorize receipt-reuse semantics and must not be turned into
a business rule without a separate decision.

### E. `activateFreePlan` duplicate protection

Approved implementation:

- The active-subscription existence check and the creation occur inside
  one Firestore transaction (same query as before; no new index).
- Duplicate/concurrent activation converges to one active Free
  subscription via the established `alreadyActive` response convention.
- Existing subscription semantics, fields, and durations are unchanged.
- Analytics/entitlement/assignment side effects occur only on actual
  creation.

### F. Lockout security events

- Decision: audit/security event only.
- A transition-only `login_lock_engaged` event is written to the
  existing server-side `auth_security_events` collection on fresh lock
  transitions (hashed throttle-doc id as `key_hash`; no raw identity,
  no passwords, hashes, tokens, or secrets).
- No Push notification for lockout at this stage.

### G. App Check

Production App Check enforcement remains deferred. All callable
wiring (including the previously bare endpoints) remains in place for
future enforcement, but enforcement must not be documented or treated
as enabled.

### H. Mobile / documentation cleanup

Mobile Doctor/device-order cleanup and broader legacy documentation
cleanup remain deferred. No behavior or documentation changes are
authorized by this ADR in those areas.

## Context

Prior hardening (threat model: credential spraying, account-state
enumeration, concurrent duplicate approval, claim overwrites) left four
residual gaps: unbounded registration submission, name-rotation spray
against staff login, single-operator duplicate payment/subscription
execution, and silent lock transitions. Each fix reuses existing
infrastructure (sliding windows, `login_throttle` ladder, Firestore
transactions, server-side audit collections) with owner-approved
numeric policies, avoiding new systems and new thresholds.

## Alternatives Considered

1. Per-phone registration counting instead of IP scope. Rejected: rotating
   phone numbers evades it; IP scope matches the abusive resource
   (endpoint_submit volume), consistent with the staff-directory gate.
2. Clearing the IP spray budget on success. Rejected: a valid login must
   not reset another caller's budget behind shared egress (NAT); windows
   and locks already expire on their own schedule.
3. Receipt-number uniqueness enforcement for payments. Rejected: changes
   ledger business semantics and requires index/schema decisions beyond
   duplicate-execution prevention.
4. Lockout Push alerting. Rejected at this stage: no alerting policy is
   defined; audit-only events preserve observability without noise.
5. Enabling App Check enforcement with this change. Rejected: operational
   prerequisites (final app identifiers, Console registration, prod web
   key distribution, per-dev debug tokens) are outside code scope.

## Consequences

- Registration, staff login, payment logging, and free-plan activation
  carry server-side duplicate/abuse protection with no client changes
  required (response shapes unchanged).
- Over-Net guard, ledger schema/fields, plan semantics, renewal,
  upgrade/downgrade, correction, and financial-account logic are
  unchanged.
- Permissions, authentication, claims, throttling policies for other
  flows, and historical audit records are unchanged.
- Enforcement of App Check, mobile Doctor behavior, and legacy doc
  cleanup remain explicitly out of scope until separately approved.

## Validation Evidence

Implementation verified by local mock test suites against compiled
Cloud Functions output:

- Registration throttle: 7/7.
- Doctor/Admin staff IP throttle: 10/10.
- Payment idempotency: 13/13.
- Free Plan activation: 10/10.
- `payment_logged` regression: 20/20.
- `payment_correction`: 18/18.
- `membership_audit`: 5/5.
- `reset_claim`: 8/8.
- Enumeration: 15/15.
- Student login throttle: 13/13.
- Change-password throttle: 18/18.
- TypeScript compilation: clean.
- ESLint: no non-linebreak findings.

Known pre-existing issue (not caused by, and not modified by, this
work): `password_reset.test.js` still stops at the legacy
key-migration write assertion.

## Production Safety

Recorded explicitly: no production deployment, no production Firestore
writes, no production Auth writes, no commit, no staging, no
destructive git operations were performed as part of this work. All
validation used local mocks/test infrastructure.
