# 06 Firebase Architecture

Version: 1.2
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

## Changelog

- **1.2** (2026-08-25): Ratified addendum FINAL_DECISIONS §11–15. Section 5 rewritten to document the DUAL storage-provider architecture (Bunny Storage zone `dr-tarek-resources` + Firebase Storage simultaneously, per-resource `storage_provider` dispatch), the Bunny signed-URL pattern extended to PDFs/attachments/thumbnails, and the new resource callables (`generateBunnyResourceUrl`, `uploadBunnyResource`, `deleteBunnyResource`) plus the scheduled auto-publish function (`autoPublishDueLectures`, Section 6.7).
- **1.1**: Academic-period enforcement additions.

---

# 1. Purpose

This document defines how Firebase services implement the data, security, and business-logic decisions already established in **00 Master Architecture** and **05 Database**. It does not redefine collections, fields, or business rules — those remain the sole responsibility of 05 Database and the PRD/Features documents (Single Source of Truth, per Master Architecture Section 9.1).

---

# 2. Firebase Services Used

Per Master Architecture Section 3 and 11:

- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Firebase Cloud Messaging (FCM)
- Cloud Functions (for Firestore triggers and server-side business logic — see Section 6)

Firebase Analytics is explicitly listed as **Future** in PRD (Dependencies section) — the current `analytics_events` collection in Database.md is a custom Firestore collection, not Firebase Analytics, and remains so in Version 1.

---

# 3. Authentication Strategy

## 3.1 Requirement

Per PRD (FR-01.02) and Features (Feature 01), login uses **phone number + password** — not phone/OTP, not email/password directly.

## 3.2 Decision — Custom Tokens (Approved)

Per the Final Decisions (2026-08-04), Version 1 uses **Custom Authentication Tokens** minted by a Cloud Function. This replaces the previously-considered pseudo-email workaround.

**Flow:**

1. Student enters `phone_number` (Egypt format: `0100...`, no country code in V1) and `password` in the Flutter app.
2. App calls the `verifyPhonePassword` Cloud Function (see Section 6.2).
3. Cloud Function verifies credentials against the `users` collection in Firestore (`phone_number` uniqueness enforced at registration; password stored hashed).
4. On successful verification, the Cloud Function mints a Firebase Custom Token via the Admin SDK.
5. App signs in with `signInWithCustomToken()`.
6. Firebase Auth manages the session token lifecycle (FR-01.05).

**Advantages over pseudo-email:**
- No synthetic email collisions or provider-migration risk.
- Full server-side control over credential verification.
- Clean path to V1.2 social providers (OTP, Email, Facebook, Google) without Firebase Auth provider conflicts.

### Rejected Alternative
Pseudo-email workaround (`{phone}@drtarek.internal` with Email/Password provider). Rejected per Final Decisions in favor of Custom Tokens for stronger security and future flexibility.

## 3.3 Custom Claims

Per Final Decisions Section 10, the following custom claims are set server-side by Cloud Functions and are available in Security Rules via `request.auth.token`:

| Claim | Source | Used In |
|-------|--------|---------|
| `role` | `users.role` | Security Rules role-based access |
| `student_type` | `users.student_type` | Plan eligibility, content gating |
| `plan_id` | Active `subscriptions.plan_id` | Feature Matrix enforcement |
| `max_devices` | Derived from active plan via `plan_features` | Device binding validation |

Claims are refreshed on every token refresh and on any subscription/plan change. Security Rules read these claims directly (zero Firestore document reads per request), per Final Decisions.

## 3.4 Session & Device Binding

- Firebase Auth manages the session token lifecycle (FR-01.05).
- Device Binding (FR-01.06, BR — Feature 01) is **not** a Firebase Authentication feature — it is enforced via Cloud Function (`onLoginAttempt`, Section 6.2) at login time, checking the requesting device against the user's allowed device count and registered devices, per Database.md Section 14 (Device Policy) and Final Decisions Section 1.

## 3.5 Password Reset Flow

Per Final Decisions Section 3:

- Student taps "Forgot Password" in the app.
- App sends a password-reset request (logged as Analytics Event).
- Admin/Teacher receives an in-app notification.
- Admin/Teacher resets the password from the Dashboard.
- Student is notified via push notification that the password has been changed.
- No automated email/SMS reset link in V1.

---

# 4. Cloud Firestore

Schema, collections, fields, enums, relationships, and constraints are fully defined in **05 Database** — not duplicated here.

## 4.1 Access Pattern

Per Master Architecture Section 5 ("Widgets never access Firestore directly. All data passes through Repositories.") and Database.md Section 23 ("No UI accesses Firestore directly"):

```
UI (Flutter Widgets)
   ↓
Repository (Flutter, abstract interface + Firebase implementation)
   ↓
Cloud Firestore (governed by Security Rules)
```

No screen or widget calls the Firestore SDK directly. Every read/write goes through a Repository implementation, per 07 Flutter Architecture (once written).

## 4.2 Firestore Security Rules — Strategy

Security Rules are the **only** enforcement layer that cannot be bypassed by a compromised or modified client — the Repository pattern above is a code-organization discipline, not a security boundary by itself. Rules must independently re-validate every rule already described in PRD's Business Rules section.

### Role resolution inside Rules

Per Final Decisions, Rules use **Custom Claims** (`request.auth.token.role`, `request.auth.token.student_type`, `request.auth.token.plan_id`) for zero-read role resolution. No extra Firestore document read is performed per rule evaluation.

### Representative rule patterns (illustrative, not exhaustive — full rule set belongs in implementation, not this document)

```
match /users/{userId} {
  allow read: if request.auth.uid == userId
              || request.auth.token.role in ['admin', 'teacher'];
  allow update: if request.auth.uid == userId
                && onlyEditableFieldsChanged() // full_name, profile_photo, display_handle, password fields
                || request.auth.token.role in ['admin', 'teacher'];
}

match /lectures/{lectureId} {
  allow read: if request.auth.token.approval_status == 'approved'
              && hasSubjectAccess(request.auth.token, resource.data.subject_id)
              && resource.data.status == 'published';
  allow write: if request.auth.token.role in ['admin', 'teacher'];
}
```

`hasSubjectAccess()` is a Rules helper function that checks `request.auth.token.plan_id` and the Feature Matrix — implementation detail for 08 Development Standards.

### Rules must enforce (cross-referenced to PRD Business Rules)

- BR-03/BR-04: only `approval_status == 'approved'` users read protected content; role-based feature gating.
- BR-06/BR-07/BR-08: content access strictly follows subscription/Feature Matrix (`plan_features`), re-checked server-side via custom claims, not just hidden client-side.
- BR-09: exam submissions become immutable after creation (`allow update: if false` once `submitted_at` exists).
- Database.md Section 19: one active subscription per subject, `display_handle` uniqueness — enforced via Cloud Function validation at write time (Rules alone cannot easily enforce cross-document uniqueness; see Section 6.3).

## 4.3 Composite Indexes

Already fully enumerated in Database.md Section 20 — deploy as-is via `firestore.indexes.json`. No changes here.

---

# 5. Firebase Storage

## 5.1 Structure

```
/profile_photos/{user_id}/{file}
/lecture_resources/{lecture_id}/{resource_id}/{file}   ← Firebase-hosted pdf/attachment/thumbnail files
/subject_thumbnails/{subject_id}/{file}
```

## 5.2 Access Rules

- `profile_photos`: Teacher (Platform Owner) can write their own; Admin/Teacher can write any; publicly readable only if `display_handle` is used as the public-facing identity (Section 3, Database.md `users.display_handle`).
- `lecture_resources` (video/PDF): **never** publicly readable. Per BR-07/BR-08 and Master Architecture ("Secure video streaming"), actual video delivery goes through **Bunny CDN** (Master Architecture Section 3), not raw Firebase Storage URLs — Storage here holds only PDFs/attachments and thumbnails; video files are uploaded to Bunny CDN separately, with `lecture_resources.resource_url` pointing to a Bunny-signed/tokenized URL, not a Storage path. This preserves BR-06 ("Protect premium educational content") since Bunny supports token-authenticated, time-limited playback URLs that Firebase Storage alone does not provide as cleanly.
- PDF files: readable only via a short-lived signed URL generated by a Cloud Function that re-validates the requester's subscription/Feature Matrix access at request time (not a static public Storage rule) — this is what "Download Protection" (Feature 06, PDF Viewer) requires.

## 5.3 Dual Storage Providers (NEW in v1.2 — FINAL_DECISIONS §11–15 addendum, approved)

The platform runs **Bunny Storage AND Firebase Storage simultaneously** for PDFs/attachments/thumbnails. Every stored resource carries its own `storage_provider` ("bunny" | "firebase") recorded at upload time; video remains implicitly Bunny-only.

**Dispatch contract (single abstraction, two implementations):**

- The Flutter Data layer defines one abstract `ResourceStorageGateway` (`upload`, `getSignedAccessUrl`, `delete`) with exactly two implementations: `BunnyResourceStorageGateway` and `FirebaseResourceStorageGateway`. `AdminContentRepositoryImpl` selects the gateway at runtime from the chosen/default provider; the Presentation layer never branches on provider.
- **Reads:** the existing student callables (`generateProtectedPdfUrl` / `generatePdfDownloadUrl`) now read `resource.storage_provider` server-side and return either a Firebase Storage short-lived signed URL or a Bunny token-authenticated URL for the same resource path in zone `dr-tarek-resources`. Same request shape, same plan-feature gates (`pdf.access` / `pdf.download`) — the client cannot tell which backend served the bytes.
- **Bunny reads** reuse the exact HMAC/token signing mechanism already used for video (`generateBunnySignedUrl`): `sha256(secret + path + expires)` base64url token + `expires` query parameter against the storage-zone hostname. Credentials (storage-zone password/API key, zone name, pull-zone hostname) live only in Cloud Functions env config/secrets — never hardcoded, never logged, never returned to the client.
- **Firebase reads** stay protected exactly as today: Storage Rules keep `allow read: if false` on `/lecture_resources/**`; delivery happens through Cloud-Function-issued short-lived signed URLs after per-request subscription validation. This approach is retained (instead of custom-claim-checked Storage Rules) because it matches the established video-adjacent protection pattern, keeps zero public surface, and centralizes entitlement checks in one auditable place.

**Uploads:**

- Firebase provider: direct SDK upload from the Data layer to `/lecture_resources/{lecture_id}/{resource_id}/{file}` under staff-only write rules (unchanged).
- Bunny provider: proxied through the `uploadBunnyResource` callable. Bunny Storage has no presigned-upload mechanism, so the only alternatives are embedding the storage-zone password in the app (rejected — credential exposure) or proxying via Cloud Functions (chosen). Tradeoff: Cloud Run caps request bodies (~32MB), so Bunny uploads above that must either use the Firebase provider or wait for a chunked-upload decision (flagged in Open Items). The 50MB placeholder ceiling therefore applies in full only to the Firebase path today.

## 5.4 Scheduled Auto-Publish (NEW in v1.2)

See Section 6.7 — `autoPublishDueLectures` flips due draft lectures to published every 5 minutes and writes an analytics event + admin_audit_log entry with actor `system_scheduler`. Manual publish stays available at any time.

---

# 6. Cloud Functions

## 6.1 Purpose

Cloud Functions handle everything that must not run purely on the client: privileged writes, cross-document consistency, and side effects (notifications). Per the approved approach: **security/critical logic in Cloud Functions, routine reads/writes through Repositories governed by Security Rules.**

## 6.2 Auth & Device Binding

| Function | Trigger | Responsibility |
| --- | --- | --- |
| `verifyPhonePassword` | Callable, invoked by app at login | Verifies `phone_number` + password against Firestore; on success, mints Firebase Custom Token with claims (`role`, `student_type`, `plan_id`, `max_devices`); on failure, logs failed attempt and returns error |
| `onLoginAttempt` | Callable, invoked by app immediately after `signInWithCustomToken()` | Validates device against user's registered devices and `max_devices` claim (Final Decisions Section 1); on first login, binds device; on mismatch, rejects and logs `Unauthorized Device Attempt` analytics event + notifies student + flags for Admin review (Feature 01, Alternative Flow); Factory Reset = new device ID = requires Admin re-approval |
| `onStudentApproved` | Firestore trigger, `users.approval_status` → `approved` | Activates Free Plan (creates default `subscriptions` record per Database.md Section 7's Business Rule), sets custom auth claims (`role`, `student_type`, `plan_id`, `max_devices`), sends approval notification |

## 6.3 Data Integrity

| Function | Trigger | Responsibility |
| --- | --- | --- |
| `recalculateSubjectProgress` | Firestore trigger, `lecture_progress.is_completed` write | Recalculates `subject_progress_summary` (Database.md Section 11.3 — explicitly specified as Repository-layer, not client-side) |
| `enforceDisplayHandleUniqueness` | Callable / trigger on `users.display_handle` write | Rejects the write if the handle is already taken by another user (Database.md Section 19 constraint) |
| `enforceOneSubscriptionPerSubject` | Firestore trigger on `subscriptions` create | Rejects/merges if an active subscription already exists for that (student, subject) pair |

## 6.4 Bunny CDN — Signed URL Generation

Per Final Decisions Section 4:

| Function | Trigger | Responsibility |
| --- | --- | --- |
| `generateSignedVideoUrl` | Callable, invoked by app when student opens a video | Receives `video_id` (Bunny Video ID entered by Admin/Teacher in Dashboard); validates student's subscription and Feature Matrix (`plan_features` video quality, preview duration); returns a Bunny CDN **signed URL** (time-limited, token-authenticated) at the allowed quality level; URL is never exposed to the student — the app streams through the signed URL transparently |

**Flow:**
1. Admin/Teacher uploads video to Bunny CDN (Bunny handles transcoding).
2. Admin/Teacher enters only the Bunny `video_id` in the Dashboard.
3. App requests playback → calls `generateSignedVideoUrl(video_id)`.
4. Cloud Function validates access and returns a signed URL.
5. App plays video; student never sees the raw URL.
6. Each video open generates a fresh signed URL (auto-refresh).

## 6.5 Notifications

| Function | Trigger | Responsibility |
| --- | --- | --- |
| `sendPushNotification` | Firestore trigger on `notifications` create, or direct callable from Admin/Teacher actions | Delivers via FCM; covers all BR-11 notification types (approval, rejection, new lecture, new exam, announcements, admin messages) |
| `processNotificationQueue` | Scheduled / trigger | Implements Retry Logic, Dead Letter Queue, and Grouping (Section 7) |

## 6.6 Analytics

Every business-logic Cloud Function above also writes the corresponding `analytics_events` record server-side (Database.md Section 15: "Every user action generates an Analytics Event") — this guarantees the event is logged even if the client disconnects mid-action, which a purely client-side write cannot guarantee.

## 6.7 Scheduled Auto-Publish & Resource Storage Callables (NEW in v1.2)

| Function | Trigger | Responsibility |
| --- | --- | --- |
| `autoPublishDueLectures` | Scheduled (`every 5 minutes`) | Finds `status == 'draft'`, non-deleted lectures whose `publish_date <= now` and flips them to `published`; writes one analytics event + one admin_audit_log entry per lecture with actor `system_scheduler`. Manual publish (نشر المحاضرة) remains available at any time regardless of `publish_date`. |
| `generateBunnyResourceUrl` logic (inside `generateProtectedPdfUrl` / `generatePdfDownloadUrl`) | Callable | Reads `resource.storage_provider`; Bunny-hosted resources get a time-limited token-authenticated URL for zone `dr-tarek-resources` (same HMAC scheme as video); Firebase-hosted resources keep the existing signed-URL flow. Plan-feature gates unchanged. |
| `uploadBunnyResource` | Callable (staff only, audited) | Proxies a base64 payload into the Bunny storage zone under `/lecture_resources/{lecture_id}/{resource_id}/{file}`; validates staff role, content type and size before forwarding; returns the canonical storage path. |
| `deleteBunnyResource` | Callable (staff only, audited) | Deletes a Bunny-hosted resource file by path; mirrors the staff-only delete rule of the Firebase path. |
| `setDefaultStorageProvider` | Callable (Teacher only, audited) | Writes `system_settings.default_storage_provider` ("bunny" | "firebase") used to pre-select the upload provider in admin screens. |

---

# 7. Firebase Cloud Messaging (FCM) — 7 Improvements

Per Final Decisions Section 8, the notification system implements the following seven enhancements:

## 7.1 FCM Token Refresh
- Device tokens are monitored for invalidation/expiry.
- On token refresh, the new token is automatically updated in the `devices` collection (Database.md Section 16).
- Invalid tokens are pruned periodically by a Cloud Function.

## 7.2 Retry Logic
- If an FCM send fails (network error, device unreachable), the Cloud Function retries with exponential backoff (up to 3 attempts).
- Retry state is tracked in a sub-collection under `notifications`.

## 7.3 Dead Letter Queue (DLQ)
- Notifications that exhaust all retries are moved to a `notification_dlq` collection.
- Admin Dashboard exposes the DLQ for manual inspection and re-trigger.
- DLQ entries include failure reason and timestamp.

## 7.4 Dual System (Push + In-App)
- Every notification is written to the `notifications` collection (In-App inbox) **and** sent via FCM (Push).
- If push delivery fails, the in-app notification remains visible.
- Read status is synchronized: marking as read in-app also suppresses the push badge.

## 7.5 Quiet Hours
- Each user can configure quiet hours (stored in `users` or a sub-collection).
- During quiet hours, push notifications are queued and delivered when the window ends.
- Critical notifications (approval, payment confirmation, security alerts) bypass quiet hours.

## 7.6 Rich Notifications
- Push notifications support rich payloads: images (subject thumbnails), action buttons ("Open Lecture", "Mark as Read"), and deep links.
- Payload structure is standardized in 08 Development Standards.

## 7.7 Grouping
- Notifications of the same type (e.g., "New Lecture" from the same subject) are grouped into a single collapsible notification on Android/iOS.
- Grouping key is `{user_id}:{notification_type}:{subject_id}`.
- Summary text shows count (e.g., "3 new lectures in Mathematics").

## 7.8 Device Token Storage
- `devices.fcm_token` is stored per device (flagged for formal addition to 05 Database Section 16; tracked as follow-up).
- Notification types map 1:1 to Database.md's `Notification Types` enum (`lecture`, `payment`, `chat`, `reminder`, `trial`, `subscription`, `system`).

---

# 8. Offline Support & DRM

Per Database.md Section 19 ("Offline Learning Rules") and Final Decisions Section 2:

## 8.1 Firestore Offline Persistence
- Firestore's native offline persistence handles reads/writes while disconnected.
- Local progress reconciles against Firestore as source of truth on reconnect (already specified in Database.md).
- Membership/Feature Matrix re-validation after reconnect is a Cloud Function responsibility (`revalidateOfflineAccess`, triggered on reconnect sync), consistent with Section 6.1's split.

## 8.2 DRM — AES-256 Offline Encryption
- Downloaded content (video segments, PDFs) is stored **locally only** — never on Firebase Storage or any cloud path accessible outside the app.
- All offline files are encrypted with **AES-256** before being written to local storage.
- Encryption keys are derived from device-specific identifiers + Firebase Auth UID and stored in platform Secure Storage (Keychain/Keystore), never in plain files.
- Files are **inaccessible outside the application** — cannot be opened via file managers, shared, or extracted.

## 8.3 Subscription Revocation
- If a subscription expires, is cancelled, or is revoked, a Cloud Function triggers local content wipe.
- The app receives a silent push notification (`subscription_revoked`) and immediately deletes all encrypted offline content for that subject.
- Progress data remains in Firestore (cloud-synced) and is not lost.

## 8.4 Device Change = Fresh Downloads
- Per Final Decisions Section 2, changing devices (including Factory Reset) treats the device as new.
- All previous downloads are lost; the student must re-download content on the new device after Admin re-approves the device binding.
- This is enforced by the fact that encryption keys are device-bound and never transferred.

---

# 9. Open Items (flagged for Teacher review — not silently decided)

- [x] ~~Confirm Section 3.2's pseudo-email authentication approach~~ — **Resolved**: Custom Tokens approved per Final Decisions (2026-08-04).
- [ ] `devices.fcm_token` field needs to be formally added to 05 Database (Section 16) — flagged, not added here, to respect Database.md's ownership of schema.
- [x] ~~Confirm Bunny CDN token-signing responsibility~~ — **Resolved**: Cloud Function (`generateSignedVideoUrl`) approved per Final Decisions (2026-08-04).
- [ ] Confirm AES-256 key derivation strategy (device ID + Firebase UID + server-secret salt) — proposed, pending security review.
- [ ] Confirm max device counts per plan (Free/Pro = 1, Max = 2+) — proposed per Final Decisions, pending Dashboard UI specification.

---

END OF DOCUMENT
