# 07 Flutter Architecture

Version: 1.3
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

## Version History (new)

- **1.3** (2026-09-14): Implementation-design detail per the approved Implementation Architecture Specification. Documents the server-issued device handle (opaque session reference), Subject context threading through content flows, Subject-partitioned DRM consumption, Max session-token integration, and explicit BLOCKED UI dependencies. No new names, measurements, copy, or components invented.
- **1.2** (2026-09-14): Alignment with Subject-Level Device Binding (ADR-004, FINAL_DECISIONS.md v2.0). Global device-binding gate removed (login always succeeds; no global blocked screen; no global `isCurrentDeviceValid` truth); authorization resolves per Subject to Full vs Guest; claims de-scoped to identity; DRM and video-player sections rescoped per Subject with Max single-session continuity. Existing folder/class/provider names kept and marked for rescoping — no new names invented.

---

# 1. Purpose

This document defines how the Flutter application is structured to implement Clean Architecture, Feature-First design, and the Repository Pattern mandated by Master Architecture (Sections 4, 9, 9.1). It covers project structure, state management, dependency injection, and cross-cutting concerns.

It does **not** define specific screens, widgets, or visual layouts — those depend on the approved Figma design and belong in `03 UI & UX` (currently pending). Where this document must reference a screen to explain a pattern, it uses a generic placeholder, not an invented design.

---

# 2. Tech Stack Recap

Per Master Architecture Section 3 (not redefined here, only referenced):

- Flutter
- Material 3
- Riverpod (state management)
- Firebase (backend — see 06 Firebase Architecture)

---

# 3. Architectural Layers

Per Master Architecture Section 4 (Clean Architecture, Repository Pattern, DI, Reusable Components):

```
Presentation Layer   (Widgets, Screens, Riverpod Providers/Notifiers)
        ↓ depends on
Domain Layer          (Entities, Use Cases, Repository Interfaces)
        ↓ implemented by
Data Layer            (Repository Implementations, Firebase/Bunny Data Sources, DTOs)
```

- **Presentation** never imports Firebase SDK or any Data-layer class directly (Master Architecture: "Widgets never access Firestore directly").
- **Domain** has zero Flutter/Firebase dependencies — pure Dart. This is what makes the codebase testable and framework-agnostic per NFR-06 (Maintainability).
- **Data** implements Domain's repository interfaces; this is the only layer allowed to import `cloud_firestore`, `firebase_storage`, `firebase_auth`, `firebase_messaging`, or Bunny CDN SDK/HTTP clients.

---

# 4. Feature-First Project Structure

Per Master Architecture Section 9 ("Feature First"), each Feature from `04 Features` maps to one top-level folder:

```
lib/
├── core/
│   ├── di/                     # Dependency injection setup (Riverpod providers root)
│   ├── errors/                 # Failure/Exception types (shared across features)
│   ├── network/                # Connectivity checks, offline queue
│   ├── theme/                  # Material 3 theme, dark/light mode (Vision: Dark/Light Ready)
│   ├── routing/                # App-wide route definitions
│   └── widgets/                # Truly generic reusable widgets (buttons, loaders, empty states)
│
├── features/
│   ├── authentication/         # Feature 01
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   ├── repositories/   # abstract interfaces only
│   │   │   └── usecases/
│   │   ├── data/
│   │   │   ├── models/         # DTOs, fromJson/toJson
│   │   │   ├── datasources/    # Firebase Auth calls (implements 06 Firebase Architecture Section 3)
│   │   │   └── repositories/   # implements domain interfaces
│   │   └── presentation/
│   │       ├── providers/      # Riverpod StateNotifiers/AsyncNotifiers
│   │       ├── screens/
│   │       └── widgets/
│   │
│   ├── student_dashboard/      # Feature 02
│   ├── subject_navigation/     # Feature 03
│   ├── lecture/                # Feature 04
│   ├── video_player/           # Feature 05
│   ├── pdf_viewer/             # Feature 06
│   ├── timeline_quizzes/       # Feature 07
│   ├── exams/                  # Feature 08
│   ├── notes/                  # Feature 09
│   ├── bookmarks/              # Feature 10
│   ├── student_questions/      # Feature 11
│   ├── chat/                   # Feature 12
│   ├── notifications/          # Feature 13
│   ├── membership/             # Feature 14
│   └── profile/                # Feature 15
│
└── main.dart
```

Each feature folder is self-contained: a feature's domain/data/presentation never import another feature's *internal* classes directly. Cross-feature communication happens through:
- Shared `core/` abstractions, or
- A feature exposing a narrow public interface (e.g., `membership` exposes a `hasAccess(subjectId)` use case that `lecture` and `video_player` call — not the other way around).

This mirrors Master Architecture's "Every feature must be reusable" and "No duplicated code" principles.

---

# 5. Repository Pattern — Implementation Contract

Every Repository interface in `domain/repositories/` has exactly one Firebase-backed implementation in `data/repositories/`, consistent with 06 Firebase Architecture Section 4.1's mandated flow:

```dart
// domain/repositories/lecture_repository.dart
abstract class LectureRepository {
  Future<Either<Failure, List<Lecture>>> getLecturesForSection(String sectionId);
  Stream<LectureProgress> watchProgress(String lectureId);
}

// data/repositories/lecture_repository_impl.dart
class LectureRepositoryImpl implements LectureRepository {
  final LectureRemoteDataSource remote; // wraps Firestore calls
  // ...
}
```

- Return types use a `Either<Failure, T>` (or equivalent Result type) pattern for explicit error handling — no unguarded exceptions crossing into Presentation (NFR-13, FR-19).
- Repositories never expose raw Firestore `DocumentSnapshot`/`QuerySnapshot` types to Domain or Presentation — only Domain Entities.

---

# 6. State Management (Riverpod)

- **AsyncNotifierProvider** / **NotifierProvider** for feature state that involves async Firestore reads (e.g., subject list, lecture progress).
- **Provider** (plain) for derived/computed values (e.g., a `hasAccessProvider` built from membership + Feature Matrix state).
- **StreamProvider** for real-time Firestore listeners where live updates matter (e.g., chat messages, notification badge count).
- Providers are scoped per-feature in `presentation/providers/` and composed at `core/di/` only when genuinely cross-feature (e.g., the current authenticated user, needed almost everywhere).

No `setState`-based business logic — `StatefulWidget` is reserved for purely local UI state (animation controllers, text field focus) with zero business meaning.

---

# 7. Dependency Injection

Riverpod's provider graph **is** the DI mechanism — no separate service locator (e.g., `get_it`) is introduced, to avoid two competing DI systems. `core/di/` holds:

- Firebase SDK instance providers (`firestoreProvider`, `firebaseAuthProvider`, `firebaseStorageProvider`, `firebaseMessagingProvider`)
- Repository providers (wire `XRepositoryImpl` behind the `XRepository` interface)
- Cross-cutting providers (current user, connectivity state, per-Subject authorization tier — never a global device boolean)

---

# 8. Routing

- Declarative routing (e.g., `go_router`) is assumed as the standard Flutter approach compatible with Web support (NFR-11) and deep-linking into notifications (Feature 13 — "Each notification opens its related feature directly").
- Route guards enforce role/approval-status checks at the navigation layer as a UX convenience — this is **not** a security boundary (that's Firestore Security Rules, per 06 Firebase Architecture Section 4.2); it only prevents an approved-looking screen from flashing before a redirect.

---

# 9. Error Handling & Offline

- `core/errors/` defines a shared `Failure` hierarchy (e.g., `NetworkFailure`, `AuthFailure`, `PermissionFailure`, `NotFoundFailure`) mapped from Firebase exceptions in the Data layer — Presentation only ever sees `Failure`, never a raw `FirebaseException` (NFR-13: "shall not expose sensitive information").
- `core/network/` wraps Firestore's native offline persistence (already the source of truth per 06 Firebase Architecture Section 8) and exposes a simple `isOnline` stream for UI banners — no custom offline cache is built, since Firestore's is used directly.

---

# 10. Responsive / Cross-Platform

Per NFR-10/NFR-11 and Vision's "Mobile First, Responsive Design": widgets use `LayoutBuilder`/breakpoint-aware wrappers in `core/widgets/`, not per-screen ad-hoc breakpoints — this keeps Android/iOS/Web/Tablet handling in one reusable place rather than duplicated across 15 features.

---

# 11. Testing Strategy (brief — full standards belong in 08 Development Standards)

- Domain layer: pure unit tests (no mocks needed beyond repository interfaces).
- Data layer: repository tests against Firebase emulator suite, not production Firestore.
- Presentation: widget tests for critical flows (login, exam submission) — full coverage strategy deferred to 08 Development Standards.

---

# 12. Open Items (flagged for Teacher review)

- [ ] Confirm `go_router` (or alternative) as the routing package — assumed here for Web/deep-link compatibility, not previously specified anywhere.
- [ ] Screen-level widget breakdown, navigation map, and visual hierarchy are explicitly deferred to `03 UI & UX` once Figma is available — this document intentionally stops at the architectural-pattern level.
- [ ] Confirm whether `Either<Failure, T>` (functional error handling, e.g., via `dartz` or `fpdart`) is acceptable, or whether a simpler try/catch + sealed-class Result type is preferred for the team's familiarity/onboarding (both satisfy NFR-13 equally — this is a style choice, not an architectural one).

---

# 13. Offline DRM Implementation

Per FINAL_DECISIONS Section 2, the platform supports offline video learning with AES-256 DRM. This section defines the Flutter-side architecture for encrypted offline content.

## 13.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Presentation Layer                                              │
│  - VideoPlayerScreen (plays from cache or stream)               │
│  - OfflineDownloadsScreen (lists available offline content)     │
│  - DownloadProgressProvider (Riverpod — download queue state)   │
├─────────────────────────────────────────────────────────────────┤
│  Domain Layer                                                    │
│  - OfflineContentRepository (interface)                         │
│  - DownloadUseCase (enqueue, pause, resume, delete)            │
│  - DecryptUseCase (AES-256 decryption for playback)            │
├─────────────────────────────────────────────────────────────────┤
│  Data Layer                                                      │
│  - OfflineContentRepositoryImpl                                 │
│  - DrmLocalDataSource (AES-256 encrypt/decrypt + Secure Storage)│
│  - DownloadManager (background download queue)                  │
│  - BunnyCdnRemoteDataSource (signed URL fetch)                 │
└─────────────────────────────────────────────────────────────────┘
```

## 13.2 Encryption Flow

1. **Download Request**: Student taps "Download" on a lecture video.
2. **Signed URL Fetch**: `BunnyCdnRemoteDataSource` calls Cloud Function to get a time-limited signed URL (per FINAL_DECISIONS Section 4).
3. **Background Download**: `DownloadManager` fetches the video file to app-private storage (not external/Downloads).
4. **AES-256 Encryption**: `DrmLocalDataSource` encrypts the file immediately after download completes using a key derived from:
   - Device-specific key material (stored in Secure Storage, scoped to this device's authorization for that Subject — per ADR-004)
   - User-specific salt (from the authenticated session; Subject-specific allowance is resolved server-side, never from a single global claim)
5. **Metadata Storage**: Encrypted file path, original filename, and encryption metadata stored in a local SQLite database (not Firestore — per FINAL_DECISIONS: "التحميلات على الجهاز فقط — مش على السحابة").

## 13.3 Decryption & Playback Flow

1. **Playback Request**: Student opens a downloaded lecture offline.
2. **Subject-Device Authorization Check**: `DrmLocalDataSource` verifies this device's authorization for that Subject (see Section 15). If unauthorized for Full access → Guest tier (limited playback only; Guest has no protected downloads); the login itself is never affected.
3. **Key Retrieval**: Decryption key reconstructed from Secure Storage + session-derived salt.
4. **Streaming Decryption**: File decrypted chunk-by-chunk into a memory buffer fed to the video player (never written decrypted to disk).
5. **Cleanup on Unbind/Expiry**: When authorization for a Subject is removed (per-Subject unbind, approved reset, or that Subject's subscription ends), `DrmLocalDataSource` wipes that Subject's encrypted files and keys only — other Subjects are unaffected (per FINAL_DECISIONS v2.0: "لو الاشتراك اتقفل: التحميلات تتمسح فوراً" applies to that subscription's Subject).

## 13.4 Feature Folder — `features/offline_drm/`

```
features/offline_drm/
├── domain/
│   ├── entities/
│   │   ├── offline_content.dart        # lecture_id, encrypted_path, size_bytes, downloaded_at
│   │   └── download_task.dart          # task_id, status (queued|downloading|completed|failed)
│   ├── repositories/
│   │   └── offline_content_repository.dart
│   └── usecases/
│       ├── download_content.dart
│       ├── delete_content.dart
│       ├── decrypt_for_playback.dart
│       └── get_downloaded_content.dart
├── data/
│   ├── models/
│   │   └── offline_content_model.dart  # SQLite row mapping
│   ├── datasources/
│   │   ├── drm_local_datasource.dart   # AES-256 + Secure Storage
│   │   ├── download_manager.dart       # background download queue
│   │   └── bunny_cdn_remote_datasource.dart  # signed URL via Cloud Function
│   └── repositories/
│       └── offline_content_repository_impl.dart
└── presentation/
    ├── providers/
    │   ├── download_queue_provider.dart
    │   └── offline_content_list_provider.dart
    ├── screens/
    │   └── offline_downloads_screen.dart
    └── widgets/
        └── download_progress_tile.dart
```

## 13.5 Security Rules (Flutter-side)

- Encrypted files live in `getApplicationDocumentsDirectory()` — inaccessible to other apps (Android 10+ scoped storage, iOS sandbox).
- Decryption keys never leave Secure Storage (`flutter_secure_storage`).
- No decrypted file ever written to persistent storage — only in-memory stream.
- Factory Reset = new device identity → login still succeeds; the new identity resolves per Subject to Full (free slot on first Subject access) or Guest. Re-authorization follows the approved reset/management path on student request — never a login precondition (per ADR-004).

---

# 14. Custom Tokens Integration

Per FINAL_DECISIONS Section 3 (V1: Custom Tokens) and Section 10 (Custom Claims), this section defines how Custom Tokens and Custom Claims integrate into the Flutter architecture.

## 14.1 Authentication Flow (V1)

```
Student enters phone (0100...) + password
         ↓
[Cloud Function: verifyPhonePassword]
         ↓
On success: Cloud Function generates Custom Token
         ↓
Flutter: firebaseAuth.signInWithCustomToken(token)
         ↓
Firebase Auth attaches Custom Claims to ID Token
         ↓
Flutter: ID Token refreshed → claims available in Riverpod
```

## 14.2 Custom Claims Structure (per ADR-004 — identity only)

Per FINAL_DECISIONS v2.0 Section 10, Custom Claims contain identity/general authorization only:

```json
{
  "role": "student | new_student | teacher | admin",
  "student_type": "public_student | center_student",
  "approved": true | false
}
```

Single global `plan_id` / `max_devices` / `subscription_status` values are never Subject authorization truth — a student may hold different plans per Subject. Subject subscription and Subject-Device authorization (Full vs Guest per Subject) resolve from the server-side source of truth, not from claims.

## 14.3 Claims Provider (Riverpod)

A cross-cutting provider in `core/di/` exposes decoded claims to all features:

```dart
// core/di/auth_providers.dart

final customClaimsProvider = StreamProvider<Map<String, dynamic>?>((ref) async* {
  final auth = ref.watch(firebaseAuthProvider);
  await for (final user in auth.authStateChanges()) {
    if (user == null) {
      yield null;
      continue;
    }
    final idToken = await user.getIdTokenResult(true); // force refresh
    yield idToken.claims;
  }
});

// Derived providers for common checks
final userRoleProvider = Provider<String?>((ref) {
  final claims = ref.watch(customClaimsProvider).value;
  return claims?['role'] as String?;
});

final isApprovedProvider = Provider<bool>((ref) {
  final claims = ref.watch(customClaimsProvider).value;
  return claims?['approved'] == true;
});

// SUPERSEDED per ADR-004: single-global `maxDevicesProvider` and
// `subscriptionStatusProvider` cannot represent per-Subject plans and
// allowances and must not gate content or login. Per-Subject Full vs Guest
// tier resolves server-side per Subject (see Section 15); claims expose
// identity only (`role`, `student_type`, `approved`).
```

## 14.4 Claims Refresh Strategy

- **On App Launch**: Force refresh ID token to get latest claims.
- **After Admin Action**: When Admin updates a student's plan/approval, Cloud Function triggers `auth.setCustomUserClaims()` → Student's next token refresh picks it up.
- **Periodic Refresh**: Every 15 minutes while app is active, or on every significant navigation (dashboard → lecture → video).
- **On Token Expiry**: `FirebaseAuth.instance.idTokenChanges()` stream auto-refreshes; `customClaimsProvider` re-emits.

## 14.5 Feature Folder — `features/authentication/`

The existing `authentication` feature is extended with Custom Token-specific data sources:

```
features/authentication/
├── data/
│   ├── datasources/
│   │   ├── custom_token_remote_datasource.dart   # calls verifyPhonePassword Cloud Function
│   │   └── custom_claims_local_datasource.dart   # caches claims in Secure Storage (offline fallback)
│   └── repositories/
│       └── auth_repository_impl.dart             # wires token flow + claims
```

## 14.6 "Forgot Password" Flow

Per FINAL_DECISIONS Section 3: Student taps "نسيت الباسورد" → request sent to Admin/Teacher (Platform Owner) → Admin changes password from Dashboard → Cloud Function updates claims if needed → Student notified via push notification.

Flutter-side: `ForgotPasswordUseCase` calls Cloud Function `requestPasswordReset(phone)` → returns `Either<Failure, void>` with success message "تم إرسال طلبك للأدمن".

---

# 15. Subject-Device Authorization Check (per ADR-004 — rescoped; no new names invented)

Per FINAL_DECISIONS v2.0 Section 1 and Master Architecture v2.0 Section 7.1, this section defines the Flutter architecture for device recognition and per-Subject authorization. The prior global login-gate model (bind-on-login, reject-on-mismatch, logout-on-mismatch, global blocked screen) is superseded. Existing folder/class/provider names below are kept and marked for rescoping.

## 15.1 Device Identity

Device recognition follows 08 Development Standards (stable identification; IP information is metadata only, never the sole permanent identity). The platform identifies devices independently from the phone number. Records carry the metadata needed for later recognition and audit (type/platform, identity/fingerprint information, device metadata, IP information).

Stored in Secure Storage on first launch. If missing → treat as new device identity (login still succeeds; per-Subject tier resolves on Subject access).

## 15.2 Recognition Flow (login never gated)

```
Login on any device (always succeeds for a valid session)
         ↓
Flutter: read local device identity from Secure Storage
         ↓
Device identity registered for recognition and audit (never a login precondition)
         ↓
Per Subject, on first actual Subject access:
┌─────────────────────────┬──────────────────────────────┐
│ Device authorized       │ Device not authorized        │
│ for this Subject        │ for this Subject             │
│ → Full access           │ → Free slot? bind on first   │
│                         │   access : Guest/limited     │
│                         │   (subscription unchanged)   │
└─────────────────────────┴──────────────────────────────┘
```

## 15.3 Evaluation at Runtime

Authorization is evaluated per Subject, never globally:

### A. Authentication Layer
- Login verifies account credentials only. No device check rejects login or logs the user out.

### B. Application Layer (Flutter)
- Per-Subject tier (Full vs Guest) is resolved server-side per Subject and consumed by dashboard, subject, lecture, video, PDF, and exam surfaces.
- There is no global `isCurrentDeviceValid` truth and no global device-blocked login screen. A Guest Subject shows its limited experience in place; other Subjects are unaffected.

## 15.4 Feature Folder — `features/device_binding/` (MARKED FOR RESCOPING per ADR-004)

Existing structure is retained as the starting point; responsibilities move from global binding to per-Subject authorization (existing names kept, no new names invented here):

```
features/device_binding/
├── domain/
│   ├── entities/
│   │   └── device_binding.dart     # RESCOPED: per-Subject authorization state, not one global binding
│   ├── repositories/
│   │   └── device_binding_repository.dart   # RESCOPED: per-Subject tier queries, not global validate
│   └── usecases/
│       ├── validate_current_device.dart     # SUPERSEDED as global gate; rescope to per-Subject tier
│       ├── register_new_device.dart         # RESCOPED: recognition/audit registration, never login-gating
│       └── get_bound_devices.dart           # RESCOPED: per-Subject authorized-device views
├── data/
│   ├── models/
│   │   └── device_binding_model.dart
│   ├── datasources/
│   │   ├── device_binding_remote_datasource.dart   # RESCOPED: server-side per-Subject evaluation
│   │   └── device_info_local_datasource.dart       # Secure Storage + device_info_plus
│   └── repositories/
│       └── device_binding_repository_impl.dart
└── presentation/
    ├── providers/
    │   └── device_binding_status_provider.dart     # SUPERSEDED as Stream<bool> global truth; rescope to per-Subject tier
    └── screens/
        └── device_blocked_screen.dart              # SUPERSEDED: no global blocked login screen
```

## 15.5 Integration with DRM (Section 13)

- `DrmLocalDataSource` checks this device's authorization for the Subject being decrypted (per-Subject, not global).
- Unauthorized-for-Full on that Subject → Guest tier (limited playback; no protected downloads); login and other Subjects unaffected.
- Removal of a Subject's authorization wipes that Subject's encrypted content only (per FINAL_DECISIONS v2.0).

## 15.6 Multi-Device Plans (Center Max — per ADR-004)

- Allowance comes from each Subject's own subscription (Max = 2 authorized devices for that Subject), resolved server-side — never from a single global claim.
- Max provides device continuity with a single active playback session (see Section 16); concurrent playback on both authorized devices is not allowed.

## 15.7 Implementation Consumption Notes (per the Implementation Architecture Specification; no new names invented)

- **Server-issued device handle.** After login the app holds the opaque handle returned with device registration and attaches it to authorization-relevant calls as a session reference. The handle is never treated as proof of hardware and never decides anything client-side.
- **Subject context in every content flow.** Video, PDF, download, offline, and exam paths carry the current Subject (and device handle) so tier resolution is always Subject-scoped; no flow performs client-side slot counting or caches a global verdict.
- **DRM consumption.** The offline store is consumed as Subject-partitioned; pre-decrypt checks and wipes operate on one Subject's partition at a time.
- **Max session integration.** The player holds the server-issued session token during Full playback, heartbeats while playing, honors server stop directives (including on takeover by the other authorized device), and resumes from the server-persisted position. Heartbeat/lease values are tuning values owned by the server.
- **UI dependencies — BLOCKED.** The following have no Figma specification and must not be invented here: Student Profile with multiple Subject plan badges; per-Subject Guest/limited state; Guest blocked download/PDF states; any Max continuity indication; per-Subject device/reset management surfaces. See 03_UI_UX §3.11.

---

# 16. Video Player Architecture (Bunny CDN)

Per FINAL_DECISIONS Section 4 and Master Architecture Section 3 ("Bunny CDN is used for video delivery"), this section defines the Flutter video player architecture with signed URLs, quality tiers, and security.

## 16.1 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Presentation Layer                                              │
│  - VideoPlayerScreen                                            │
│  - QualitySelectorWidget (adaptive based on plan)              │
│  - VideoProgressProvider (tracks watch time → Firestore)       │
├─────────────────────────────────────────────────────────────────┤
│  Domain Layer                                                    │
│  - VideoRepository (interface)                                  │
│  - GetSignedVideoUrlUseCase                                     │
│  - GetAvailableQualitiesUseCase                                 │
│  - ReportWatchProgressUseCase                                   │
├─────────────────────────────────────────────────────────────────┤
│  Data Layer                                                      │
│  - VideoRepositoryImpl                                          │
│  - BunnyCdnRemoteDataSource (Cloud Function → Signed URL)      │
│  - VideoPlayerLocalDataSource (progress cache, last position)   │
└─────────────────────────────────────────────────────────────────┘
```

## 16.2 Signed URL Flow

Per FINAL_DECISIONS Section 4: "التطبيق يطلب رابط موقّع من Cloud Function — الرابط يتجدد تلقائياً كل مرة الطالب يفتح الفيديو — الطالب ميشوفش الرابط أبداً."

```
Student opens lecture video
         ↓
GetSignedVideoUrlUseCase(lectureId, quality)
         ↓
BunnyCdnRemoteDataSource calls Cloud Function: getSignedVideoUrl
         ↓
Cloud Function:
  1. Verifies student has access to lecture (Firestore + Custom Claims)
  2. Checks quality tier against plan (Feature Matrix)
  3. Generates Bunny CDN signed URL (expires in 1 hour)
  4. Returns {url: "...", expires_at: timestamp, quality: "720p"}
         ↓
Flutter: feeds URL to video player (chewie/better_player/video_player)
         ↓
URL is never exposed in UI, logs, or network inspector (HTTPS only)
```

## 16.3 Quality Tiers & Plan Mapping

Per FINAL_DECISIONS Section 4: "الجودة المتاحة: محددة حسب الاشتراك (من Dashboard)."

| Plan (of that Subject) | Available Qualities | Max Resolution |
|------|---------------------|----------------|
| Public Free | Preview only (first X minutes) | 480p |
| Center Free | All lectures, single quality | 720p |
| Center Pro | All lectures, multi-quality | 1080p |
| Center Max | All lectures, multi-quality + download | 1080p |

Quality availability is controlled from Dashboard (Feature Matrix) and enforced server-side, not client-side. Qualities above apply at the Full tier; Guest tier receives limited playback only (per ADR-004; no minute values invented here). A Max Subject additionally provides device continuity: two authorized devices with a single active playback session — starting the same content on the second device stops the first and resumes from the saved position (mechanism not specified here).

## 16.4 Video Player Package

- **Primary**: `video_player` (official Flutter) + `chewie` (UI wrapper) for standard playback.
- **DRM/Offline**: Custom `DrmVideoPlayer` widget that streams decrypted bytes from `DrmLocalDataSource` (Section 13) into `video_player` via `VideoPlayerController.networkUrl` with custom headers or `VideoPlayerController.contentUri` (Android) / `AVPlayer` (iOS) with in-memory resource.
- **HLS/DASH**: If Bunny CDN provides HLS playlists, use `better_player` or `flutter_hls_parser` for adaptive streaming — quality selection UI driven by `GetAvailableQualitiesUseCase`.

## 16.5 Feature Folder — `features/video_player/`

```
features/video_player/
├── domain/
│   ├── entities/
│   │   ├── video_source.dart         # signed_url, expires_at, quality, type (stream|offline)
│   │   └── video_progress.dart       # lecture_id, watched_seconds, completed, last_updated
│   ├── repositories/
│   │   └── video_repository.dart
│   └── usecases/
│       ├── get_signed_video_url.dart
│       ├── get_available_qualities.dart
│       ├── report_watch_progress.dart
│       └── get_last_position.dart
├── data/
│   ├── models/
│   │   ├── video_source_model.dart
│   │   └── video_progress_model.dart
│   ├── datasources/
│   │   ├── bunny_cdn_remote_datasource.dart    # Cloud Function for signed URL
│   │   └── video_player_local_datasource.dart  # SQLite: last position, watch history
│   └── repositories/
│       └── video_repository_impl.dart
└── presentation/
    ├── providers/
    │   ├── video_source_provider.dart      # AsyncNotifier<VideoSource>
    │   └── video_progress_provider.dart    # Notifier<VideoProgress>
    ├── screens/
    │   └── video_player_screen.dart
    └── widgets/
        ├── quality_selector_sheet.dart
        ├── video_controls_overlay.dart
        └── offline_badge.dart
```

## 16.6 Security & Anti-Piracy

- Signed URLs expire after 1 hour; student never sees the raw Bunny CDN URL.
- Screen recording is discouraged via `flutter_windowmanager` (Android: `FLAG_SECURE`) and iOS `UIScreenCapture` detection.
- Offline videos are AES-256 encrypted and scoped to this device's authorization for that Subject (Section 13 + 15).
- No video URL is ever logged to Analytics or Crashlytics.

## 16.7 Integration with Offline DRM

- `VideoPlayerScreen` checks if lecture is available offline via `OfflineContentRepository` (Section 13).
- If offline: routes playback through `DecryptForPlaybackUseCase` → feeds decrypted stream to player.
- If online: routes through `GetSignedVideoUrlUseCase` → streams from Bunny CDN.
- Seamless fallback: if offline file is corrupted, auto-fallback to online stream (if connected). If this device is Guest for the Subject, playback follows the Guest tier in both modes; login is never affected.

---

# 17. Cross-Feature Integration Summary

The four new architectural components (Sections 13–16) integrate as follows:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Authentication (Feature 01)                   │
│  Custom Tokens → identity claims (role, student_type, approved) │
│  Login always succeeds; never gated by device                  │
├─────────────────────────────────────────────────────────────────┤
│              Subject-Device Authorization (Section 15)          │
│  Per-Subject Full vs Guest tier; Guest never mutates plan       │
├─────────────────────────────────────────────────────────────────┤
│                    Offline DRM (Section 13)                      │
│  AES-256 encrypted downloads → scoped to Subject authorization  │
│  Per-Subject wipe on unbind / expiry / approved reset           │
├─────────────────────────────────────────────────────────────────┤
│                    Video Player (Section 16)                     │
│  Online: Signed URLs from Bunny CDN via Cloud Function          │
│  Offline: Decrypted stream from DRM local storage               │
│  Quality & access: server-side per-Subject + Feature Matrix     │
│  Max: 2 authorized devices + single active playback session     │
└─────────────────────────────────────────────────────────────────┘
```

All four components share:
- `core/di/` for Firebase instances and cross-cutting providers.
- `core/errors/` for unified `Failure` types (`DrmFailure`, `DeviceBindingFailure`, `VideoFailure`, `AuthFailure`).
- Server-side evaluation as the source of truth for per-Subject subscription and authorization; claims carry identity only.

---

# 18. Document Change Log

| Version | Date | Changes | Reason |
|---------|------|---------|--------|
| 1.0 | — | Initial draft | Base architecture document |
| 1.1 | 2026-08-04 | Added Sections 13–17: Offline DRM, Custom Tokens, Device Binding, Video Player (Bunny CDN), Cross-Feature Integration, and Change Log | Per FINAL_DECISIONS review chat — integrating all architectural decisions into Flutter layer |
| 1.2 | 2026-09-14 | Rescoped Sections 13–17 to Subject-Level Device Binding (ADR-004) | Login decoupled from authorization; per-Subject Full/Guest; claims de-scoped; Max single-session continuity |

---

END OF DOCUMENT
