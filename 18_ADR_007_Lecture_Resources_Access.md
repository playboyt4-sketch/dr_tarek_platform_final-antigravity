# ADR-007 — Lecture Resources Access: Option A (Current) vs Option B (Deferred)

Status: Approved
Date: 2026-09-20
Version: 1.0
Authority: Project Owner decision (documentation-only record)

This ADR records a Project-Owner-approved documentation decision only. It
does not rewrite older architectural documents, does not promote any Draft
document, does not silently modify any Approved document's version, and
does not alter any Flutter code, Cloud Functions, Firestore Rules, Storage
Rules, Firebase configuration, or tests. Current-system references use the
canonical role terminology: Doctor (Platform Owner).

## Decision

### Current version: Option A (approved, intentional, unchanged)

- The current version uses **Option A** for Lecture Resources.
- Lecture Resources may be client-readable **ONLY after all applicable
  Firestore Security Rules and subject/content authorization gates succeed**
  (reference, read-only: `firestore.rules` —
  `match /lecture_resources/{resourceId}` requires `isApprovedContent(...)`
  AND `hasSubjectAccess(uid, subject_id)` AND `!isLectureDenied(uid,
  lecture_id)`, or staff/Doctor access; `lecture_access_grants` remains
  non-client-readable for students with server-side enforcement in
  `getLectureResources` and document/signed-URL delivery).
- **Client readability does NOT mean unrestricted access.** Every
  client-readable path remains gated.
- **Firestore Security Rules and content/subject authorization remain
  mandatory.** No bypass is authorized.
- **The current implementation is intentional and must NOT be changed.**

### Next version: Option B (deferred future enhancement)

- **Option B — Backend-mediated access — is deferred to the next version
  as a future architecture enhancement.**
- Option B means: Flutter Client → Backend / Cloud Function →
  Authorization → Resource.
- **Option B is NOT a current security blocker.**
- **Do NOT implement Option B now.**

### Change authorization

- **No code change is authorized by this task.** No modification to
  Flutter code, Cloud Functions, Firestore Rules, Storage Rules, Firebase
  configuration, or tests is authorized by this ADR.

## Context

A question arose whether the current Lecture Resource read path (Option A,
Rules-gated client readability) constitutes a security defect requiring
immediate re-architecture to a backend-mediated path (Option B). The
Project Owner has resolved that the current Rules-plus-authorization-gate
model is the approved current-version posture, and that backend mediation
is a planned later-version enhancement, not a current-version defect.

## Alternatives Considered

1. Implement Option B now (Flutter Client → Backend / Cloud Function →
   Authorization → Resource in the current version). Rejected for now:
   deferred to the next version as a future architecture enhancement per
   Project Owner decision; not a current security blocker.
2. Treat Option A client readability as unrestricted access. Rejected:
   readability exists only after Firestore Security Rules and
   subject/content authorization gates succeed.
3. Relax or remove Firestore Security Rules / subject/content authorization
   gates for Lecture Resources. Rejected: those gates remain mandatory.
4. Modify an existing Approved document (e.g. ADR-006, Master
   Architecture, FINAL_DECISIONS, Database baseline) to record this
   decision. Rejected: per documentation governance, no Approved
   document is silently modified or version-bumped here; this standalone
   ADR is the minimum necessary entry and no existing Approved document
   was changed.

## Consequences

- The current Lecture Resource architecture (Option A) stays as-is.
- Option B is tracked as a next-version architecture enhancement only.
- Option B must not be cited as a current-version security blocker, and
  must not trigger current-version code, rules, or configuration changes.
- Cross-document consistency: this ADR introduces no new collection,
  field, function, rule, or protocol; owning documents are unchanged.

## Validation Evidence

- Documentation-only task. No code was modified; no tests were run.
- Read-only inspection only: documentation governance
  (`docs/notion/00_MASTER_ARCHITECTURE.md` §§5.1–5.3), existing ADRs
  (`16_ADR_003_Academic_Term_Lifecycle.md`,
  `17_ADR_006_Security_Hardening.md`), `docs/notion/FINAL_DECISIONS.md`,
  and `firestore.rules` (`match /lecture_resources/{resourceId}`).

## Production Safety

Recorded explicitly: no production deployment, no production Firestore
writes, no production Auth writes, no commit, no staging, and no
destructive git operations were performed as part of this work. Read-only
git inspection only (`git status`, `git log`, `git diff --stat`); all
pre-existing worktree changes preserved.
