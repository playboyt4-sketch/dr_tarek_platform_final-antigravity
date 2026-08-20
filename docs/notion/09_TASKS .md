# 09 Tasks

Version: 1.1
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

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
| **T-000.8** | **Implement Custom Tokens authentication (Firebase Auth Custom Claims: `role` + `student_type` + `plan_id` + `max_devices`). Replaces deprecated Pseudo-Email approach per Final Decisions Section 3.** | **T-000.2** |
| **T-000.9** | **Configure Bunny CDN integration: Dashboard inputs Video ID only; Cloud Function generates Signed URL per request; student never sees raw URL; quality tiers controlled by membership (per Final Decisions Section 4).** | **T-000.7** |
| **T-000.10** | **Implement phone number validation (Egypt format: 0100... without country code in V1) per Final Decisions Section 3.** | **T-000.8** |
| **T-000.11** | **Implement "Forgot Password" flow: student requests reset → notification sent to Admin/Teacher → password changed from Dashboard per Final Decisions Section 3.** | **T-000.8** |
| **T-000.12** | **Set up AES-256 offline DRM infrastructure: encrypted local storage, Secure Storage integration, device binding validation before offline playback per Final Decisions Section 2.** | **T-000.2** |
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
| T-CF.2 | `onLoginAttempt` — device binding validation (Free/Pro: 1 device, Max: 2+ devices), factory reset = new device | 01 | Per Final Decisions Section 1 |
| T-CF.3 | `onStudentApproved` — activate free plan, set custom claims (`role`, `student_type`, `plan_id`, `max_devices`), send notification | 01, 14 | Per Final Decisions Section 3, 5 |
| T-CF.4 | `recalculateSubjectProgress` | 02, 04, 07 | — |
| T-CF.5 | `enforceDisplayHandleUniqueness` | 15 | — |
| T-CF.6 | `enforceOneSubscriptionPerSubject` | 14 | — |
| T-CF.7 | `sendPushNotification` — with Retry Logic, Dead Letter Queue, Rich Notifications, Grouping | 13 (and any feature triggering a notification) | Per Final Decisions Section 8 |
| T-CF.8 | `generateBunnySignedUrl` — generate time-limited signed URL for video playback; quality filtered by membership | 05 | Per Final Decisions Section 4 |
| T-CF.9 | `revalidateOfflineAccess` — verify membership validity, wipe downloads if revoked | 04, 05, 06, 14 | Per Final Decisions Section 2 |
| T-CF.10 | `generateProtectedPdfUrl` — signed URL for protected PDF downloads | 06 | — |
| **T-CF.11** | **`onDeviceChangeRequest` — Admin/Teacher approves device replacement → invalidate old device, allow new login** | **01, 14** | **Per Final Decisions Section 1** |
| **T-CF.12** | **`onPasswordResetRequest` — handle forgot-password flow, notify Admin/Teacher, apply reset from Dashboard** | **01, 15** | **Per Final Decisions Section 3** |
| **T-CF.13** | **`onSecurityEvent` — log screenshot/screen-recording/jailbreak/emulator detection as Security Event (separate from analytics)** | **05, 06, 08** | **Per Final Decisions Section 10** |
| **T-CF.14** | **`onPaymentLogged` — manual payment entry by Teacher (Platform Owner) only, send confirmation notification** | **14** | **Per Final Decisions Section 6** |

---

# 5. Admin/Teacher-Side Tasks

Every feature above is written from the Student-facing perspective by default (matches Feature docs' primary flows). Each feature also has an Admin/Teacher management counterpart (content upload, moderation, approvals) described in its own Feature doc — these follow the identical four-stage breakdown and are tracked as a `-admin` suffix of the same task IDs in the issue tracker (e.g., `04-admin` for Lecture content management), not duplicated again here.

**Additional Admin/Teacher tasks per Final Decisions:**
- **Payment logging UI**: Teacher (Platform Owner)-only manual payment entry with receipt number, amount, notes (per Final Decisions Section 6).
- **Device management UI**: Admin/Teacher can view bound devices, revoke old device, approve new device (per Final Decisions Section 1).
- **Password reset UI**: Admin/Teacher can reset student password from Dashboard (per Final Decisions Section 3).
- **Feature Matrix configuration UI**: Admin/Teacher can toggle features per plan without code changes (per Final Decisions Section 5).

---

# 6. Sequencing Recommendation

Not a hard dependency graph — a suggested order that unblocks the most features fastest:

1. **Foundation (Section 2)** — T-000.1 through T-000.13
2. **Feature 01 (Authentication)** — everything else needs a logged-in user; depends on T-000.8, T-000.10, T-000.11
3. **Feature 14 (Membership)** — access-gating logic that Features 04–08 depend on; depends on Custom Claims (`plan_id`, `max_devices`)
4. **Feature 03 → 04 → 05 → 06 (core content-consumption chain)** — depends on T-000.7, T-000.9, T-000.12
5. **Remaining features in any order** — no hard interdependency among 07–13, 15 beyond what's noted in Section 3/4

**Critical Path Note:** Device Binding (T-CF.2, T-CF.11) and DRM (T-000.12, T-CF.9) are security-critical and should be implemented and tested before any content-delivery feature (04–06) reaches production.

Presentation-Final work across all features starts together once `03 UI & UX` is approved, rather than feature-by-feature, since design-system components (buttons, cards, nav patterns) are shared and should be built once in `core/widgets/` first.

---

# 7. Open Items

- [ ] This document assumes Domain/Data/Scaffolding work can proceed without Figma — confirm this sequencing is acceptable, or if the team prefers to wait for Figma before starting anything (would change Section 6).
- [ ] Issue-tracker tool (Jira, Linear, GitHub Issues, etc.) not yet specified — task IDs here (T-xxx) are placeholders for whatever tool is chosen.
- [ ] **NEW**: Confirm `max_devices` values per plan (Free/Pro: 1, Max: 2+) are final or need adjustment (per Final Decisions Section 1).
- [ ] **NEW**: Confirm Bunny CDN Signed URL expiry duration (suggested: 5 minutes per request).
- [ ] **NEW**: Confirm AES-256 offline encryption key management strategy (per-device key vs. user-bound key).

---

END OF DOCUMENT
