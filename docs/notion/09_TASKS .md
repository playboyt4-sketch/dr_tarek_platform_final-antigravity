# 09 Tasks

Version: 1.3
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

## Version History (new)

- **1.3** (2026-09-14): Implementation work breakdown per the approved Implementation Architecture Specification. Added tasks for registry rescope, transactional first access, Guest enforcement, Max session, unbind/reset operations, Subject-scoped DRM, Rules/Functions enforcement, indexes, audit, race/security tests, and staged cutover (T-CF.15–T-CF.24). Proposed callable names from 06 §6.7 referenced as proposals only; no implementation started.
- **1.2** (2026-09-14): Alignment with Subject-Level Device Binding (ADR-004, FINAL_DECISIONS.md v2.0). Login-rejection tasks converted to per-Subject authorization requirements (login always succeeds; Full vs Guest per Subject); claims tasks de-scoped to identity; device-management, DRM, sequencing, and open items updated. No new implementation names invented; affected function references kept and marked for redesign.

---

# 1. Purpose

Breaks down implementation work into trackable tasks, organized by Feature (per 04 Features) and by architectural layer (per 07 Flutter Architecture). This is a task index, not a design or requirements document — the source of truth for *what* each task must do remains 04 Features, 05 Database, 06 Firebase Architecture, and 07 Flutter Architecture.

Tasks are grouped into three categories:
- **Foundation** — one-time project setup, not tied to a single feature.
- **Per-Feature** — Domain / Data / Presentation-Scaffolding / Presentation-Final tasks for each of the 15 features.
- **Blocked** — tasks that cannot start until `03 UI & UX` (Figma) is available.

---

# 2. Foundation Tasks (do first, once)

| ID | Task | Depends On |
| --- | --- | --- |
| T-000.1 | Initialize Flutter project, folder structure per 07 Flutter Architecture Section 4 | — |
| T-000.2 | Configure Firebase project (Auth, Firestore, Storage, FCM, Cloud Functions) per 06 Firebase Architecture Section 2 | Firebase project created |
| T-000.3 | Deploy Firestore Security Rules skeleton (role helper functions: `getRole`, `isApproved`, `hasSubjectAccess`) per 06 Firebase Architecture Section 4.2 | T-000.2 |
| T-000.4 | Deploy Firestore composite indexes per 05 Database Section 20 | T-000.2 |
| T-000.5 | Set up `core/` (di, errors, network, theme, routing) per 07 Flutter Architecture Section 3 | T-000.1 |
| T-000.6 | Configure CI (lint + test on PR) per 08 Development Standards Section 9 | T-000.1, pending tooling decision |
| T-000.7 | Set up Bunny CDN account/library integration for video delivery | — |
| **T-000.8** | **Implement Custom Tokens authentication (Firebase Auth identity claims: `role` + `student_type` + `approved`; per-Subject subscription/authorization resolves server-side per ADR-004). Replaces deprecated Pseudo-Email approach per Final Decisions Section 3.** | **T-000.2** |
| **T-000.9** | **Configure Bunny CDN integration: Dashboard inputs Video ID only; Cloud Function generates Signed URL per request; student never sees raw URL; quality tiers controlled by membership (per Final Decisions Section 4).** | **T-000.7** |
| **T-000.10** | **Implement phone number validation (Egypt format: 0100... without country code in V1) per Final Decisions Section 3.** | **T-000.8** |
| **T-000.11** | **Implement "Forgot Password" flow: student requests reset → notification sent to Admin/Teacher → password changed from Dashboard per Final Decisions Section 3.** | **T-000.8** |
| **T-000.12** | **Set up AES-256 offline DRM infrastructure: encrypted local storage, Secure Storage integration, per-Subject authorization check before offline playback (Guest has no protected downloads; per-Subject wipe only) per ADR-004.** | **T-000.2** |
| **T-000.13** | **Configure Notifications infrastructure with all 7 enhancements: FCM Token Refresh, Retry Logic, Dead Letter Queue, Dual System (Push + In-App), Quiet Hours, Rich Notifications, Grouping per Final Decisions Section 8.** | **T-000.2** |

---

# 3. Per-Feature Task Template

Every feature (01–15) follows the same four-stage breakdown. Below, this template is instantiated for each feature at a summary level — the exhaustive method-by-method breakdown belongs in the project's issue tracker, not this document (avoids duplicating implementation detail across two places, per Master Architecture Section 9.1).

**Stages:**
1. **Domain** — entities, repository interfaces, use cases. (Not UI-dependent — can start now.)
2. **Data** — Firestore/Storage/Bunny data sources, repository implementations, Security Rules for this feature's collections. (Not UI-dependent — can start now.)
3. **Presentation-Scaffolding** — Riverpod providers/notifiers wired to Data layer, with placeholder/bare-bones widgets (no final visual design). (Can start now — produces a functionally-testable, visually-unstyled screen.)
4. **Presentation-Final** — actual screens/widgets matching the approved Figma design. (**Blocked** until `03 UI & UX` is approved.)

| # | Feature | Domain | Data | Presentation-Scaffolding | Presentation-Final |
| --- | --- | --- | --- | --- | --- |
| 01 | Authentication & Registration | ✅ Ready | ✅ Ready (needs T-000.8, T-000.10, T-000.11) | ✅ Ready | ⛔ Blocked |
| 02 | Student Dashboard | ✅ Ready | ✅ Ready | ✅ Ready | ⛔ Blocked |
| 03 | Subject Navigation | ✅ Ready | ✅ Ready | ✅ Ready | ⛔ Blocked |
| 04 | Lecture | ✅ Ready | ✅ Ready (needs T-000.9, T-000.12) | ✅ Ready | ⛔ Blocked |
| 05 | Video Player | ✅ Ready | ✅ Ready (needs T-000.7, T-000.9, T-000.12) | ✅ Ready | ⛔ Blocked |
| 06 | PDF Viewer | ✅ Ready | ✅ Ready (needs T-000.12) | ✅ Ready | ⛔ Blocked |
| 07 | Timeline Quizzes & Learning Access | ✅ Ready | ✅ Ready | ✅ Ready | ⛔ Blocked |
| 08 | Exams | ✅ Ready | ✅ Ready | ✅ Ready | ⛔ Blocked |
| 09 | Notes | ✅ Ready | ✅ Ready | ✅ Ready | ⛔ Blocked |
| 10 | Bookmarks | ✅ Ready | ✅ Ready | ✅ Ready | ⛔ Blocked |
| 11 | Questions to Admin | ✅ Ready | ✅ Ready | ✅ Ready | ⛔ Blocked |
| 12 | Chat | ✅ Ready | ✅ Ready | ✅ Ready | ⛔ Blocked |
| 13 | Notifications | ✅ Ready | ✅ Ready (needs T-000.13) | ✅ Ready | ⛔ Blocked |
| 14 | Membership Plans | ✅ Ready | ✅ Ready | ✅ Ready | ⛔ Blocked |
| 15 | Student Profile | ✅ Ready | ✅ Ready (needs `display_handle` field, per 06 Firebase Architecture Open Items) | ✅ Ready | ⛔ Blocked |

---

# 4. Cross-Feature / Cloud Functions Tasks

Per 06 Firebase Architecture Section 6 and Final Decisions — these are not tied to a single feature's Presentation layer and can proceed independently of Figma:

| ID | Task | Feature(s) Served | Notes |
| --- | --- | --- | --- |
| T-CF.1 | `verifyPhonePassword` — validate Egyptian phone (0100...) + password, issue Custom Token with claims | 01 | Per Final Decisions Section 3 |
| T-CF.2 | `onLoginAttempt` — **RESCOPED per ADR-004 (no login rejection)**: device recognition/audit registration only (always succeeds for a valid session); per-Subject Full vs Guest authorization on first actual Subject access (Free 1 / Pro 1 / Max 2 for that Subject); factory reset = new identity that still logs in | 01 | Per FINAL_DECISIONS v2.0 Section 1 |
| T-CF.3 | `onStudentApproved` — activate free plan, set identity custom claims (`role`, `student_type`, `approved`; no per-Subject authorization in claims), send notification | 01, 14 | Per Final Decisions Section 3, 5 |
| T-CF.4 | `recalculateSubjectProgress` | 02, 04, 07 | — |
| T-CF.5 | `enforceDisplayHandleUniqueness` | 15 | — |
| T-CF.6 | `enforceOneSubscriptionPerSubject` | 14 | — |
| T-CF.7 | `sendPushNotification` — with Retry Logic, Dead Letter Queue, Rich Notifications, Grouping | 13 (and any feature triggering a notification) | Per Final Decisions Section 8 |
| T-CF.8 | `generateBunnySignedUrl` — generate time-limited signed URL for video playback; quality filtered by membership | 05 | Per Final Decisions Section 4 |
| T-CF.9 | `revalidateOfflineAccess` — verify membership validity, wipe downloads if revoked | 04, 05, 06, 14 | Per Final Decisions Section 2 |
| T-CF.10 | `generateProtectedPdfUrl` — signed URL for protected PDF downloads | 06 | — |
| **T-CF.11** | **Device Reset / per-Subject authorization management — Teacher/authorized Admin acts on student request → clear authorization per the approved reset operation (login never blocked; ordinary logout is not a reset; lost device alone triggers nothing)** | **01, 14** | **Per FINAL_DECISIONS v2.0 Sections 21–22** |
| **T-CF.12** | **`onPasswordResetRequest` — handle forgot-password flow, notify Admin/Teacher, apply reset from Dashboard** | **01, 15** | **Per Final Decisions Section 3** |
| **T-CF.13** | **`onSecurityEvent` — log screenshot/screen-recording/jailbreak/emulator detection as Security Event (separate from analytics)** | **05, 06, 08** | **Per Final Decisions Section 10** |
| **T-CF.14** | **`onPaymentLogged` — manual payment entry by Teacher (Platform Owner) only, send confirmation notification** | **14** | **Per Final Decisions Section 6** |
| T-CF.15 | Device registry rescope — retire `active_device` / `current_device_id` as truth (stop writing, ignore in reads); deterministic registry lookup; FCM/metadata retained | 01 | Per 05 §16, 06 §6.7 |
| T-CF.16 | Transactional first-access binding — server-side atomic assignment → subscription → count → bind-or-Guest; deterministic race outcome; no client slot counting | 01, 03, 14 | Per 06 §6.7; proposed direction only |
| T-CF.17 | Guest server-side enforcement — tier-checked video/PDF/download issuance; Guest eligibility + consumption accounting; tier-coded denials | 05, 06 | Minute values and reset policy remain open business decisions |
| T-CF.18 | Max playback session — server-authoritative begin-or-takeover + heartbeat/lease; stop-directive enforcement; resume from persisted position | 05 | Lease values are tuning decisions |
| T-CF.19 | Per-Subject unbind + global approved reset operations with audit | 01, 14 | Request-driven; login never blocked |
| T-CF.20 | Subject-partitioned DRM — per-Subject key scope, store partition, per-Subject wipe and revalidation | 04, 05, 06 | Offline cadence is a tuning decision |
| T-CF.21 | Rules/Functions enforcement split — static gates in Rules; tier + issuance in Functions; authorization-collection rules | All content features | Device-identity mechanism for Rules is an open decision (06 §4.2) |
| T-CF.22 | Authorization indexes + audit views —declare query indexes; Admin per-Subject/stale-slot visibility | 14, 15 | Per 05 §16, 15 §ADMIN_DEVICES |
| T-CF.23 | Race/security test matrix — final-slot races, isolation, Guest bypass attempts, takeover storms, reset-during-playback (emulator) | 01, 05, 14 | Per 08 §7.1 |
| T-CF.24 | Staged cutover — additive server deploy → client rescope → Admin tooling → monitored cutover; no auto-migration; request-only bulk reset support | All | Never mark complete until Teacher-approved rollout |

---

# 5. Admin/Teacher-Side Tasks

Every feature above is written from the Student-facing perspective by default (matches Feature docs' primary flows). Each feature also has an Admin/Teacher management counterpart (content upload, moderation, approvals) described in its own Feature doc — these follow the identical four-stage breakdown and are tracked as a `-admin` suffix of the same task IDs in the issue tracker (e.g., `04-admin` for Lecture content management), not duplicated again here.

**Additional Admin/Teacher tasks per Final Decisions:**
- **Payment logging UI**: Teacher (Platform Owner)-only manual payment entry with receipt number, amount, notes (per Final Decisions Section 6).
- **Device management UI**: Admin/Teacher can view per-Subject authorized devices and Guest-tier resolutions, manage per-Subject authorization, and perform the approved Device Reset on student request (login never blocked; per FINAL_DECISIONS v2.0).
- **Password reset UI**: Admin/Teacher can reset student password from Dashboard (per Final Decisions Section 3).
- **Feature Matrix configuration UI**: Admin/Teacher can toggle features per plan without code changes (per Final Decisions Section 5).
- **Per-lecture student access UI + backend (V1, project-owner approved)**: Lecture Access screen (search + ON/OFF + explicit Save) backed by `lecture_access_grants/{lectureId_studentId}`; server-side enforcement in `getLectureResources`, `generateBunnySignedUrl`, and document delivery; Rules gate on direct `lecture_resources` reads (04 Features §07, 05 Database `lecture_access_grants`, 06 §4.2).

---

# 6. Sequencing Recommendation

Not a hard dependency graph — a suggested order that unblocks the most features fastest:

1. **Foundation (Section 2)** — T-000.1 through T-000.13
2. **Feature 01 (Authentication)** — everything else needs a logged-in user; depends on T-000.8, T-000.10, T-000.11
3. **Feature 14 (Membership)** — per-Subject access-gating logic that Features 04–08 depend on; per-Subject subscription/authorization resolves server-side (never single global claims)
4. **Feature 03 → 04 → 05 → 06 (core content-consumption chain)** — depends on T-000.7, T-000.9, T-000.12
5. **Remaining features in any order** — no hard interdependency among 07–13, 15 beyond what's noted in Section 3/4

**Critical Path Note:** Subject-Device Authorization (T-CF.2, T-CF.11) and per-Subject DRM (T-000.12, T-CF.9) are security-critical and should be implemented and tested before any content-delivery feature (04–06) reaches production. Guest tier (limited video, no protected downloads/PDFs, no subscription mutation) and Max single-session continuity are part of this gate.

Presentation-Final work across all features starts together once `03 UI & UX` is approved, rather than feature-by-feature, since design-system components (buttons, cards, nav patterns) are shared and should be built once in `core/widgets/` first.

---

# 7. Open Items

- [ ] This document assumes Domain/Data/Scaffolding work can proceed without Figma — confirm this sequencing is acceptable, or if the team prefers to wait for Figma before starting anything (would change Section 6).
- [ ] Issue-tracker tool (Jira, Linear, GitHub Issues, etc.) not yet specified — task IDs here (T-xxx) are placeholders for whatever tool is chosen.
- [ ] Per-Subject allowances confirmed by ADR-004 (Free: 1, Pro: 1, Max: 2 for that Subject). Confirm Dashboard UI for per-Subject authorization display (per FINAL_DECISIONS v2.0).
- [ ] **NEW**: Confirm Bunny CDN Signed URL expiry duration (suggested: 5 minutes per request).
- [ ] **NEW**: Confirm AES-256 offline encryption key management strategy (per-device key vs. user-bound key).

---

END OF DOCUMENT
