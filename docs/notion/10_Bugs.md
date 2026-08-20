# 10 Bugs

## Dr. Tarek Platform

Version: 1.0
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

---

# 1. Purpose

This document defines the bug tracking methodology, severity classification, lifecycle, and reporting standards for the Dr. Tarek Platform. It ensures systematic identification, documentation, prioritization, resolution, and verification of defects throughout the development and maintenance lifecycle.

This document does not list actual bugs — those belong in the project's issue tracker (Jira, Linear, GitHub Issues, or equivalent). Instead, it defines the *process* and *taxonomy* for managing bugs consistently across all teams.

---

# 2. Bug Tracking Principles

- Every bug is tracked in a single issue tracker — no spreadsheets, no chat threads, no undocumented fixes.
- Every bug has a unique identifier, a clear description, and a reproducible scenario.
- Bug severity is assigned objectively, not by the person who reported it.
- No bug is closed without verification by someone other than the fix author.
- Security bugs follow a separate, confidential workflow (see Section 9).
- Performance regressions are treated as bugs, not enhancements.

---

# 3. Bug Severity Classification

| Severity | Code | Definition | Response Time | Example |
|----------|------|------------|---------------|---------|
| **Critical** | P0 | Complete system failure, data loss, or security breach. No workaround. | Immediate (< 4 hours) | Student cannot log in at all; exam data lost; unauthorized access to premium content. |
| **High** | P1 | Major feature broken, significant functionality impaired. Workaround exists but is painful. | < 24 hours | Video player crashes on all Android 14 devices; payment log not recorded; device binding bypassed. |
| **Medium** | P2 | Feature partially broken, edge case, or UI/UX issue affecting usability. | < 72 hours | PDF viewer zoom broken on tablets; notification grouping fails for > 10 items; bookmark search slow. |
| **Low** | P3 | Cosmetic issue, minor inconvenience, or enhancement disguised as a bug. | Next sprint | Typo in error message; button misaligned on iPhone SE; dark mode inconsistency. |
| **Trivial** | P4 | Nitpick, documentation typo, or non-user-facing cleanup. | Backlog | Comment grammar; unused import; log formatting. |

---

# 4. Bug Lifecycle

```
[Open]
   ↓
[Triage] — Severity assigned, category tagged, owner assigned
   ↓
[In Progress] — Developer actively working
   ↓
[Code Review] — PR submitted, linked to bug ID
   ↓
[Testing] — QA or peer verification
   ↓
[Verified] — Fix confirmed in staging / emulator
   ↓
[Closed]
```

## Alternative Flows

### Cannot Reproduce
```
[Triage] → [Cannot Reproduce] → [Need More Info] → (reporter provides details) → [In Progress]
                                    ↓
                              (no response in 7 days) → [Closed — Stale]
```

### Duplicate
```
[Triage] → [Duplicate of #XXX] → [Closed — Duplicate]
```

### Won't Fix
```
[Triage] → [Won't Fix] → (documented justification required) → [Closed — Won't Fix]
```

### Reopened
```
[Closed] → (regression detected) → [Reopened] → [In Progress]
```

---

# 5. Bug Report Template

Every bug report must contain the following fields. Incomplete reports are returned to the reporter.

### Required Fields

| Field | Description |
|-------|-------------|
| **Bug ID** | Auto-generated (e.g., `BUG-2026-001`) |
| **Title** | One-line summary, action-oriented (e.g., "Video player freezes when switching quality on slow network") |
| **Severity** | P0 / P1 / P2 / P3 / P4 |
| **Category** | See Section 6 |
| **Reporter** | Name / role |
| **Date Reported** | ISO 8601 timestamp |
| **Environment** | OS version, device model, app version, build number |
| **Feature** | Feature key from 04 Features (e.g., `feature.05.video_player`) |
| **Description** | What happened, what was expected, what actually happened |
| **Steps to Reproduce** | Numbered, deterministic steps |
| **Expected Result** | Clear statement of correct behavior |
| **Actual Result** | Clear statement of observed behavior |
| **Screenshots / Logs** | Attachments mandatory for P0-P2 |
| **Frequency** | Always / Often / Sometimes / Once |
| **Regression?** | Yes / No / Unknown — if Yes, last known good version |
| **Workaround** | Any temporary workaround, or "None" |

### Optional Fields

| Field | Description |
|-------|-------------|
| **Firebase Crashlytics Link** | For crash reports |
| **Affected Users** | Count or percentage |
| **Business Impact** | Revenue, reputation, or operational impact |
| **Related Bugs** | Cross-references |

---

# 6. Bug Categories

Categories map to the architectural layers and features for routing and reporting.

## By Feature (from 04 Features)

```
BUG-AUTH    — Authentication & Registration (Feature 01)
BUG-DASH    — Student Dashboard (Feature 02)
BUG-SUBJ    — Subject Navigation (Feature 03)
BUG-LECT    — Lecture (Feature 04)
BUG-VID     — Video Player (Feature 05)
BUG-PDF     — PDF Viewer (Feature 06)
BUG-QUIZ    — Timeline Quizzes (Feature 07)
BUG-EXAM    — Exams (Feature 08)
BUG-NOTE    — Notes (Feature 09)
BUG-BMK     — Bookmarks (Feature 10)
BUG-QST     — Questions to Admin (Feature 11)
BUG-CHAT    — Chat (Feature 12)
BUG-NOTIF   — Notifications (Feature 13)
BUG-MEMB    — Membership Plans (Feature 14)
BUG-PROF    — Student Profile (Feature 15)
```

## By Layer

```
BUG-UI      — Presentation layer (Flutter widgets, screens, navigation)
BUG-DATA    — Data layer (Repositories, Firestore reads/writes, Storage, Bunny CDN)
BUG-DOMAIN  — Domain layer (Use cases, business logic, entities)
BUG-SEC     — Security (Auth, device binding, DRM, encryption)
BUG-PERF    — Performance (Slow queries, memory leaks, jank, startup time)
BUG-NET     — Network / Offline (Sync failures, connectivity edge cases)
BUG-DB      — Database schema / indexing (Composite index missing, query performance)
BUG-CF      — Cloud Functions (Triggers, callable functions, background jobs)
BUG-FCM     — Firebase Cloud Messaging (Push delivery, token management)
BUG-ADMIN   — Admin/Teacher Dashboard (Web or native management interface)
```

---

# 7. Regression Policy

A **regression** is a bug that reintroduces a previously fixed defect or breaks a previously working feature.

### Rules

- Every regression is automatically upgraded one severity level (P3 → P2, P2 → P1, etc.).
- Regressions require a root-cause analysis (RCA) before closure.
- RCA must answer: "What test should have caught this?" and "What process gap allowed it?"
- The missing test (if any) must be added before the regression is closed.
- Repeat regressions on the same feature trigger an architectural review.

---

# 8. Release Blocking Criteria

A release is **blocked** if any of the following conditions are true:

- Any **P0** bug is open.
- Any **P1** bug affecting > 10% of users is open.
- Any **security bug** (see Section 9) is open.
- Any **DRM/encryption bug** is open (content protection compromise).
- Any **payment-related bug** is open (even in manual-payment V1).
- Any **exam data integrity bug** is open (lost submissions, incorrect grading).
- Any **device binding bypass** is open.

A release may proceed with **P2** bugs if:
- They are documented in release notes.
- A workaround is documented.
- A fix is scheduled for the next patch release.

---

# 9. Security Bug Workflow

Security bugs follow a **confidential** workflow separate from the public issue tracker.

### Process

1. **Discovery** — Reported via private channel (email/secure form), not public tracker.
2. **Triage** — Security lead assigns severity: `SEC-CRITICAL`, `SEC-HIGH`, `SEC-MEDIUM`, `SEC-LOW`.
3. **Fix Window** — `SEC-CRITICAL`: 24h. `SEC-HIGH`: 72h. `SEC-MEDIUM`: 1 week.
4. **Verification** — Fix verified by security lead + QA.
5. **Disclosure** — After fix is deployed, a summary is published internally. No public disclosure in V1 (single-tenant platform).

### Security Bug Categories

```
SEC-AUTH    — Authentication bypass, token forgery, credential leakage
SEC-AUTHZ   — Authorization bypass, privilege escalation
SEC-DRM     — Offline content decryption, key extraction, download bypass
SEC-VID     — Video URL extraction, signed URL bypass, quality bypass
SEC-DATA    — Data exposure (PII, exam answers, payment logs)
SEC-DEVICE  — Device binding bypass, emulator/jailbreak not detected
SEC-NET     — Man-in-the-middle, insecure communication
SEC-INJ     — Injection (Firestore query injection, Cloud Function input validation)
```

---

# 10. Performance Bug Standards

Performance issues are bugs, not enhancements, when they violate NFR-01 (Performance).

### Thresholds

| Metric | Threshold | Bug Severity |
|--------|-----------|--------------|
| App cold start | > 3 seconds | P2 (P1 if > 5s) |
| Screen transition | > 300ms | P3 |
| Video start time | > 2 seconds | P2 |
| PDF open time | > 1.5 seconds | P3 |
| Firestore query | > 500ms (client-measured) | P2 |
| Memory leak | > 50MB growth over 30 min | P1 |
| Frame rate drop | < 55 FPS sustained | P2 |
| Offline sync | > 30 seconds for < 100 docs | P2 |

### Required Diagnostics

Every performance bug must include:
- Flutter DevTools timeline trace (`.json`)
- Memory profile screenshot
- Network waterfall (for Firestore queries)
- Device model and OS version

---

# 11. Bug Metrics & Reporting

### Sprint Metrics (tracked per sprint)

| Metric | Target | Action if Missed |
|--------|--------|------------------|
| Bug escape rate (bugs found in production / total bugs) | < 5% | Review test coverage |
| Average time to triage | < 4 hours | Add triage rotation |
| Average time to fix (P0-P1) | < 24 hours | Review capacity |
| Average time to fix (P2) | < 72 hours | Review prioritization |
| Reopen rate | < 10% | Review verification process |
| Regression rate | < 5% | Review RCA quality |

### Release Metrics

| Metric | Target |
|--------|--------|
| Open P0-P1 bugs at release | 0 |
| Open P2 bugs at release | < 5 |
| Security bugs at release | 0 |
| DRM bugs at release | 0 |

---

# 12. Tooling

### Recommended Stack

| Tool | Purpose | Status |
|------|---------|--------|
| GitHub Issues / Jira / Linear | Primary issue tracker | Pending decision (see 09 Tasks Open Items) |
| Firebase Crashlytics | Automatic crash reporting | To be configured in T-000.2 |
| Flutter DevTools | Performance profiling | Built-in |
| Sentry (optional) | Error tracking + breadcrumbs | Future consideration |

### Integration Requirements

- Every bug ID in code comments must be hyperlinked to the issue tracker.
- Every PR fixing a bug must reference the bug ID in the commit message: `fix(BUG-XXX): description`.
- Every release note must list fixed bugs with IDs.

---

# 13. Open Items

- [ ] Confirm issue tracker tool (GitHub Issues vs. Jira vs. Linear) — see 09 Tasks Open Items.
- [ ] Configure Firebase Crashlytics integration — depends on T-000.2.
- [ ] Define SLA for Teacher (Platform Owner) bug review — who triages P0 bugs outside business hours?
- [ ] Establish security bug reporting channel (email / form / private Slack).

---

END OF DOCUMENT
