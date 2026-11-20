# 06 Firebase Architecture

Version: 1.7
Status: Approved (v1.7 — ADR-010 Amendment 3 ratified per Platform Owner review)

## Changelog

- **1.7** (2026-11-20): ADR-010 Amendment 3 completion and approval. Corrected §6.4.1: the legacy-named `BUNNY_ACTIVE_LIBRARY_IDS` is the implemented activation allow-list for non-default libraries and the emergency deny switch; no third env var (`BUNNY_DENIED_LIBRARY_IDS`) is introduced — emergency shutdown is provided exclusively via audited `deactivateBunnyLibrary` (`status="disabled"`) and removing the default-library bypass once `BUNNY_LEGACY_LIBRARY_FALLBACK` is switched off. Added explicit deviation from FINAL_DECISIONS §4 for unsigned libraries (persistent static URL visible to network observers, accepted by Platform Owner until permanent exit). Documents `discoverBunnyVideoLibrary` authoring callable, client Referer evidence (iOS/Android `httpHeaders`, Web page origin), and completed Staging catalog (`736742`/`780700` signed, `775315`/`776525` unsigned). Approved per Platform Owner review.
- **1.6** (2026-11-19): ADR-010 Amendment 3 alignment. §6.4/§6.4.1 now document verified per-library protection modes (`token_auth_mode`: `signed` | `unsigned`), the metadata-free verification probe and its mandatory platform Referer, the unsigned-library exposure and its Owner-accepted risk, the removal of the silent default library, `playback_host`-derived playback URLs, server-owned `bunny_library_id`, the unassociated-row policy, and the separation of the legacy-named emergency list from the planned explicit deny list. Draft until the Platform Owner approves `21_ADR_010_Amendment_3.md`; this entry authorizes no callable behaviour by itself.
- **1.5** (2026-11-17): ADR-010 Option C alignment. §6.4 rewritten to the implemented callables (`generateBunnySignedUrl`, `listEligibleBunnyLibraries`, `validateBunnyVideoAssociation`, `associateBunnyVideoToLibrary`) with server-side library resolution; new §6.4.1 documents the catalog, per-library credential isolation, fail-closed eligibility and the legacy-named emergency eligibility list. Corrected the stale `generateSignedVideoUrl` reference. Approved by the Platform Owner as Phase 2 governance item E.
- **1.4** (2026-09-14): Implementation-design detail per the approved Implementation Architecture Specification. Documents the PROPOSED server-side direction: transactional first-access binding, no LRU auto-eviction, server-issued device handle, proposed callable names (explicitly labeled proposed), tier-checked artifact issuance, server-authoritative Max sessions, and the Rules trust boundary (client-provided device identity is never hardware proof; IP is metadata only).
- **1.3** (2026-09-14): Alignment with Subject-Level Device Binding (ADR-004, FINAL_DECISIONS.md v2.0). Claims de-scoped to identity; login decoupled from device authorization; Rules strategy moved to server-side per-Subject evaluation; login-gating responsibilities marked for redesign; offline revocation rescoped per Subject. No new function, rule, or protocol invented; device-identity mechanism for Rules marked as an open implementation decision.
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

**Deviation from FINAL_DECISIONS §4 (Unsigned Libraries):**
FINAL_DECISIONS §4 established that "URL auto-refreshes every time student opens video" and "Student never sees the URL". For unsigned libraries (`775315`, `776525`), the returned URL is persistent, unsigned, static, and visible to network observers. Deviation accepted by the Platform Owner, scoped to unsigned libraries until the permanent exit (section 3.3).

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
| `student_type` | `users.student_type` | Plan eligibility |
| `approved` | `users.approval_status` | Login gating |

Single global `plan_id` / `max_devices` / `subscription_status` values are never Subject authorization truth (per ADR-004): a student may hold different plans per Subject, so one claim cannot represent them. Subject subscription and Subject-Device authorization (Full vs Guest per Subject) resolve from the server-side source of truth at request time. The prior zero-read-claims gating for Subject content is superseded; affected Rules require live evaluation (see Section 4.2).

Claims are refreshed on every token refresh. Identity claims above remain suitable for zero-read role resolution; Subject-specific decisions always read live state.

## 3.4 Session & Device Binding

- Firebase Auth manages the session token lifecycle (FR-01.05).
- Subject-Device Authorization (FR-01.06, BR — Feature 01) is **not** a Firebase Authentication feature and **never gates login** — a valid student signs in from any device and keeps the session. Device identity is registered for recognition and audit at login time; Full vs Guest authorization is evaluated server-side per Subject on first actual Subject access, against that Subject's own subscription allowance (Free 1 / Pro 1 / Max 2; no cross-Subject effect). The prior login-time validation-and-rejection responsibility is superseded (see Section 6.2).

## 3.5 Password Reset Flow

Per Final Decisions Section 3:

- Student taps "Forgot Password" in the app.
- App sends a password-reset request (logged as Analytics Event).
- Admin/Teacher receives an in-app notification.
- Teacher (Platform Owner) always; Admin only when explicitly granted the `password.reset` permission (grant/revoke by Teacher at any time, enforced server-side) resets the password from the Dashboard.
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

Per ADR-004, Rules use identity **Custom Claims** (`request.auth.token.role`, `request.auth.token.student_type`, approval status) for zero-read role resolution. Subject subscription, plan features, and Subject-Device authorization (Full vs Guest per Subject) are evaluated from live server-side state, not from single global claims — the prior zero-read gating for Subject content is superseded. If Rules must identify the requesting device and no approved device-identity mechanism exists yet, that mechanism is an **OPEN DECISION — implementation architecture required** (not invented here).

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

`hasSubjectAccess()` is a Rules helper function that checks live Subject Access, the Subject's own subscription and plan features, and the requesting device's Subject-Device authorization tier (Full vs Guest) — never a single global claim. Exact helper design is an implementation detail for 08 Development Standards.

### Rules must enforce (cross-referenced to PRD Business Rules)

- BR-03/BR-04: only `approval_status == 'approved'` users read protected content; role-based feature gating.
- BR-06/BR-07/BR-08: content access strictly follows subscription/Feature Matrix (`plan_features`), re-checked server-side via custom claims, not just hidden client-side.
- BR-09: exam submissions become immutable after creation (`allow update: if false` once `submitted_at` exists).
- Database.md Section 19: one active subscription per subject, `display_handle` uniqueness — enforced via Cloud Function validation at write time (Rules alone cannot easily enforce cross-document uniqueness; see Section 6.3).
- V1 Individual Per-Lecture Access (project-owner approved): `lecture_access_grants/{lectureId_studentId}` managed by Teacher / `admin_students`- or `admin_content`-delegated Admins (centralized permission model — no new key); students have no read/write on the collection. Direct `lecture_resources` student reads additionally fail when an explicit `allowed == false` grant exists. Primary enforcement lives in Cloud Functions: `getLectureResources`, `generateBunnySignedUrl`, and document delivery (`resolveDocumentAccess` shared by `generateProtectedPdfUrl`, `generatePdfDownloadUrl`, `generateBunnyResourceUrl`) consult the grant via `assertLectureAccessNotDenied` before any plan checks — explicit deny wins; missing/`true` grants defer to the normal model. Grant writes are covered by the existing content-audit trigger (`onLectureAccessGrantWritten`).

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
| `verifyPhonePassword` | Callable, invoked by app at login | Verifies `phone_number` + password against Firestore; on success, mints Firebase Custom Token with identity claims (`role`, `student_type`, `approved`) and never rejects for device reasons; on failure, logs failed attempt and returns error |
| `onLoginAttempt` | **MARKED FOR REDESIGN per ADR-004 (not deleted)** | Prior responsibility (login-time device validation, first-login binding, mismatch rejection, factory-reset re-approval) is superseded. Required direction: device registration/recognition for audit only (always succeeds for a valid session); per-Subject Full vs Guest authorization moves to server-side Subject-access evaluation (first actual Subject access; Free 1 / Pro 1 / Max 2 for that Subject). No new function names are introduced here |
| `onStudentApproved` | Firestore trigger, `users.approval_status` → `approved` | Activates Free Plan (creates default `subscriptions` record per Database.md Section 7's Business Rule), sets identity custom auth claims (`role`, `student_type`, `approved`), sends approval notification |

## 6.3 Data Integrity

| Function | Trigger | Responsibility |
| --- | --- | --- |
| `recalculateSubjectProgress` | Firestore trigger, `lecture_progress.is_completed` write | Recalculates `subject_progress_summary` (Database.md Section 11.3 — explicitly specified as Repository-layer, not client-side) |
| `enforceDisplayHandleUniqueness` | Callable / trigger on `users.display_handle` write | Rejects the write if the handle is already taken by another user (Database.md Section 19 constraint) |
| `enforceOneSubscriptionPerSubject` | Firestore trigger on `subscriptions` create | Rejects/merges if an active subscription already exists for that (student, subject) pair |

## 6.4 Bunny CDN — Signed URL Generation

Per FINAL_DECISIONS Section 4, as amended for ADR-010 Option C.

| Function | Trigger | Responsibility |
| --- | --- | --- |
| `generateBunnySignedUrl` | Callable, invoked when a student opens a video | Receives `{videoId, deviceId, lectureId?, subjectId?, quality?}`; validates the caller's entitlement, device authorization and lecture access; resolves the resource's library from `bunny_libraries`; rejects unknown, not activated, unverified or disabled libraries; returns a playback URL for that library only (signed, or unsigned for a proved `unsigned` library); `videoId` must be a bare GUID — URLs are rejected. |
| `discoverBunnyVideoLibrary` | Callable, authoring (Doctor / delegated Admin) | Receives `{videoId}`; validates bare GUID with `isValidBunnyVideoId`; probes candidate active libraries (`BUNNY_ACTIVE_LIBRARY_IDS ∩ bunny_libraries` with `active`) via Stream API; returns `{status: "found" | "not_found" | "ambiguous", libraryId?, displayName?}`; rate-limited; audited; returns no secrets or URLs. |
| `listEligibleBunnyLibraries` | Callable, Dashboard | Returns `{libraries: [{libraryId, displayName}]}`. No host, pull zone, credential reference or verification stamp is ever returned. |
| `validateBunnyVideoAssociation` | Callable, authoring | Verifies, using that library's own Stream key, that the video exists in that library. Returns a short-lived receipt (600 s). Writes nothing. |
| `associateBunnyVideoToLibrary` | Callable, authoring | Verifies the receipt, then writes `bunny_video_id` and `bunny_library_id` on the resource. `bunny_library_id` is server-owned: no client write path exists, and an unassociated resource is never played by inference. |
| `registerBunnyLibrary` | Callable, Doctor only, audited | Creates the catalog row in `pending_verification` and derives the credential **names** from the library id. Never activates. |
| `verifyBunnyLibrary` | Callable, Doctor only, audited | Proves the library's protection mode without reading library metadata (see §6.4.1) and writes `token_auth_mode`, `token_auth_enabled`, `token_auth_verified`, `status` and the typed error code. |
| `deactivateBunnyLibrary` / `reactivateBunnyLibrary` | Callable, Doctor only, audited | Emergency deactivation always wins; reactivation returns to `pending_verification` and never straight to `active`. |
| `listBunnyLibraryHealth` | Callable, Doctor only | Read-only projection: id, display name, status, mode, verification stamp, typed error code. No host, pull zone or credential name. |

**Flow:**
1. A video is uploaded to, or registered in, a specific library.
2. The backend verifies the video belongs to that library and issues a receipt.
3. The association is written only after receipt verification.
4. The library is resolved server-side from `bunny_library_id`; there is no silent default.
5. Playback is issued in the mode proved for that library: a signed directory-token URL for
   `signed`, a plain URL for `unsigned`. The URL expires after 3600 s; a new one is issued on
   each open.
6. The student never sees the raw URL, the library id, or any credential.

**Non-goals:** the platform never creates Bunny libraries; the client never selects a
library for playback.

### 6.4.1 Library Catalog, Verified Modes and Credential Isolation

`bunny_libraries/{libraryId}` is the non-secret source of truth. It stores ids, host,
booleans, the **proved** `token_auth_mode`, verification stamps, error codes and Secret
Manager **names** only.

Credentials are stored in Secret Manager under deterministic names derived from the
library id: `BUNNY_<libraryId>_STREAM_API_KEY` and, only for a `signed` library,
`BUNNY_<libraryId>_TOKEN_KEY`. A request concerning one library may read only that
library's credentials. A missing credential is an error, never a reason to fall back to
another library.

**Eligibility** requires `status === "active"`, `token_auth_verified === true`, a present
`token_auth_mode`, and `token_auth_enabled === (token_auth_mode === "signed")`. A missing or
unknown mode fails closed: absence of evidence is never read as `unsigned`.

**Verification (`verifyBunnyLibrary`)** never reads library metadata. It lists one existing
video with that library's own Stream key, then:

- if a `BUNNY_<libraryId>_TOKEN_KEY` exists, requests a signed directory-token playlist URL;
  a 2xx proves mode `signed` (`token_auth_enabled = true`, `token_auth_verified = true`);
- otherwise, requests the plain playlist URL; a 2xx proves mode `unsigned`
  (`token_auth_enabled = false`, `token_auth_verified = true`);
- a 401/403 on the plain URL means the zone is protected and no signed proof exists, so the
  library stays unverified with a typed error code.

Every probe request carries the platform Referer (`https://dr-tarek-platform.web.app/`):
all pull zones in this account set `BlockNoneReferrer`, so a probe without it measures the
hotlink rule instead of token enforcement.

**Unsigned mode is exposure, not protection.** Such a pull zone enforces no CDN token and its
`AllowedReferrers` list is empty, so any client sending any Referer can play a video whose
GUID it knows. The platform's entitlement, device and lecture gates still run before a URL
is issued, but they cannot stop playback of a GUID obtained elsewhere. This is an external
constraint (a legacy platform consumes those libraries) and is accepted by the Platform
Owner with a mandatory review date of 2027-02-19 and the permanent remediation path recorded
in ADR-010 Amendment 3 §3: a new platform-only `signed` library, video copy, audited
re-association, then retirement of the unsigned libraries.

**Playback URL construction** derives from the catalog `playback_host`. The legacy
`BUNNY_PLAYBACK_URL_TEMPLATE` is a pre-cutover compatibility input only and is retired with
the default-library fallback.

**No silent default.** An unresolved library is a typed denial
(`library_not_resolved`), never library `736742`. `736742` remains usable only as a
registered, verified catalog entry. A legacy default path may exist only behind the explicit
`BUNNY_LEGACY_LIBRARY_FALLBACK` cutover flag, defaulted off after the production migration
and removed afterwards. A resource with a `bunny_video_id` and no `bunny_library_id` is not
playable after cutover; it is repaired by the audited migration, never by guessing.

**Authoring only:** the dashboard picker lists eligible catalog entries, and a server-side
discovery callable may list the account's Stream libraries. Discovery never implies
eligibility — a discovered library must still be registered and verified — and the client
never selects the library used for playback.

`BUNNY_ACTIVE_LIBRARY_IDS` keeps its legacy name but has two documented roles in the
implemented code, and one known gap:

1. **Activation allow-list (grant).** A non-default library is eligible only when its id is
   listed. Registration plus verification make a library eligible; listing it makes it active
   in that environment.
2. **Emergency deny switch (revoke).** Removing an id - or emptying the variable - disables
   that library immediately, without a deploy. An empty or unset value denies every non-default
   library (fail-closed); a malformed value is never read as "allow all".
3. **No third environment variable:** No `BUNNY_DENIED_LIBRARY_IDS` is introduced. Immediate emergency shutdown of ANY library is provided exclusively via the audited `deactivateBunnyLibrary` callable (`bunny_libraries/{id}.status = "disabled"`), taking immediate effect across all server resolution paths without deployment. Once `BUNNY_LEGACY_LIBRARY_FALLBACK` is switched off post-migration, the default-library bypass is closed permanently.

The list can never make an ineligible library usable: the catalog row and the proved mode
remain the authority, and a listed id with no valid catalog row still fails closed.

## 6.5 Notifications

| Function | Trigger | Responsibility |
| --- | --- | --- |
| `sendPushNotification` | Firestore trigger on `notifications` create, or direct callable from Admin/Teacher actions | Delivers via FCM; covers all BR-11 notification types (approval, rejection, new lecture, new exam, announcements, admin messages) |
| `processNotificationQueue` | Scheduled / trigger | Implements Retry Logic, Dead Letter Queue, and Grouping (Section 7) |

## 6.6 Analytics

Every business-logic Cloud Function above also writes the corresponding `analytics_events` record server-side (Database.md Section 15: "Every user action generates an Analytics Event") — this guarantees the event is logged even if the client disconnects mid-action, which a purely client-side write cannot guarantee.

## 6.7 Subject-Device Authorization — Server-Side Direction (PROPOSED per the Implementation Architecture Specification; names below are recommendations, not approvals)

- **First-access binding is transactional and server-side only.** The server atomically evaluates assignment → Subject's own subscription/plan → live authorization count vs allowance → creates the authorization or returns Guest. The forbidden shape — client checks slot, client decides, client writes — must never be implemented. Two devices racing for the final slot serialize deterministically (first committer Full, other Guest).
- **No LRU auto-eviction as authorization behavior.** Slots are never silently reassigned to make room; excess and contention resolve to Guest plus Admin/reset paths.
- **Server-issued device handle.** After registry upsert the server returns an opaque handle bound to the session for subsequent calls. The handle is a session reference, not hardware proof; client-provided identifiers remain untrusted input namespaced by the authenticated `uid`.
- **Protected artifact issuance.** Video/PDF/download/offline-key issuance checks Subject + subscription + tier (+ Guest eligibility/consumption where applicable) on every call; Guest requests receive limited artifacts or tier-coded denials. Max Full playback additionally requires a live session token (see below).
- **Max playback sessions (PROPOSED).** Recommended scope `playback_sessions/{student_id}_{subject_id}` (one live session per student×subject; content, active device, session token, lease/heartbeat, and position recorded). Server owns takeover via transaction; heartbeat extends the lease; stale sessions are claimable; the previous owner is stopped via directive plus enforcement on its next server contact. Heartbeat/lease values are technical tuning values, not business rules.
- **Reset/unbind are server operations.** Approved reset revokes all active authorizations for the student with audit; per-Subject unbind revokes one; neither blocks login.
- **Rules trust boundary.** Firestore Rules cannot trust client-provided device identity as hardware proof; Rules own static gates (session, role, assignment, subscription liveness, explicit deny, dates/prerequisites) while Functions own dynamic tier decisions. Request IP is logged as metadata/audit signal only.
- **Proposed callable direction (not approved names):** tier/first-access resolution, student-device reset, playback begin-or-takeover plus heartbeat. Existing callables keep their names; only responsibilities change per the table in Section 6.2.

## 6.8 Scheduled Auto-Publish & Resource Storage Callables (NEW in v1.2)

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

## 8.4 Device Change = Per-Subject Revalidation (per ADR-004)
- A new device identity (including Factory Reset) logs in normally — login is never blocked and no re-approval is needed to sign in.
- Offline content is revalidated per Subject against that Subject's subscription and the new device's authorization for it; content for Subjects the new device is not authorized for is unavailable to it (Guest has no protected downloads), while other Subjects' authorized-device content is unaffected.
- Encryption keys remain device-bound and are never transferred. Durations, lease design, and key-partitioning specifics are not invented here.

---

# 9. Open Items (flagged for Teacher review — not silently decided)

- [x] ~~Confirm Section 3.2's pseudo-email authentication approach~~ — **Resolved**: Custom Tokens approved per Final Decisions (2026-08-04).
- [ ] `devices.fcm_token` field needs to be formally added to 05 Database (Section 16) — flagged, not added here, to respect Database.md's ownership of schema.
- [x] ~~Confirm Bunny CDN token-signing responsibility~~ - **Resolved**: Cloud Function (`generateBunnySignedUrl`) approved per Final Decisions (2026-08-04). The library dimension was added by ADR-010 Option C: the function resolves the resource's library from `bunny_libraries` server-side before signing.
- [ ] Confirm AES-256 key derivation strategy (device ID + Firebase UID + server-secret salt) — proposed, pending security review.
- [ ] Per-Subject device allowances confirmed by ADR-004 (Free = 1, Pro = 1, Max = 2 for that Subject) — Dashboard UI specification for per-Subject authorization display still pending.
- [ ] OPEN DECISION — device-identity mechanism for Rules/Functions (client-asserted identifier vs server-bound session device vs attestation): requires implementation architecture; not invented here.

---

END OF DOCUMENT
