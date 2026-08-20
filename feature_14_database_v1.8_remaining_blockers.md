# Feature 14 — Remaining Blockers

**Scope:** Documentation-only Database Change preparation  
**Current implementation status:** **BLOCKED** for code/Firebase/migration execution by explicit Teacher stop condition.

## 1. Database Change approval

**Status: BLOCKED.** The proposed `05_DATABASE_v1.8.md` and the accompanying Database Change Authority require Teacher review and explicit approval before Version 1.8 becomes an approved baseline.

Until that approval, `05_DATABASE_v1.7.md` remains the only approved baseline. No v1.8 schema, indexes, security rule, migration, or application behavior may be deployed.

## 2. Canonical-path promotion

**Status: BLOCKED pending separate authorization.** The current proposal intentionally does not replace `docs/notion/05_DATABASE.md` and does not replace the root `05_DATABASE.md` ADR fragment. If the project later requires promotion to `docs/notion/05_DATABASE.md`, that must be a separately controlled operation after v1.8 approval, preserving the older history.

## 3. Implementation authorization

**Status: BLOCKED by scope.** This step does not authorize changes to Flutter, Cloud Functions, Firestore Rules, `firestore.indexes.json`, migration scripts, Firestore data, or existing Video/Auth/Device Binding systems. Those changes require a later implementation instruction after Database Change approval.

## 4. Migration execution

**Status: BLOCKED pending implementation design and controlled run.** The migration policy is documented: an active, non-deleted subject Subscription creates `enabled = true`; no active, non-deleted subject Subscription creates `enabled = false`, unless an explicit authoritative administrative access source is already documented in the approved architecture. Learning artifacts and Grade-to-Subject membership alone are not authorization evidence. No production data has been inspected or changed and no migration has been run.

## 5. Runtime and implementation validation

**Status: NOT TESTED.** `flutter analyze`, `flutter test`, callable tests, Firestore Rules tests, migration validation, and complete runtime acceptance flows were not run because Teacher explicitly prohibited implementation and tests in this step.

## 6. No unresolved schema-decision blocker

**Status: PASS.** The Subject Access collection, deterministic ID, fields, independent entitlement order, approval boundaries, migration policy, Gift deprecation, external-payment boundary, and Student Type conflict handling are specified by the approved Teacher decisions. They are documented in the proposed Version 1.8 and have not been re-invented.
