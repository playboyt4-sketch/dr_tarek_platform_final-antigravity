# 07 Flutter Architecture

Version: 1.1
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

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
- Cross-cutting providers (current user, connectivity state, device binding state)

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
   - Device-specific binding key (stored in Secure Storage, tied to `device_binding` record)
   - User-specific salt (from Custom Claims)
5. **Metadata Storage**: Encrypted file path, original filename, and encryption metadata stored in a local SQLite database (not Firestore — per FINAL_DECISIONS: "التحميلات على الجهاز فقط — مش على السحابة").

## 13.3 Decryption & Playback Flow

1. **Playback Request**: Student opens a downloaded lecture offline.
2. **Device Binding Validation**: `DrmLocalDataSource` verifies current device matches the `device_binding` record (see Section 15). If mismatch → `DrmFailure.deviceMismatch`.
3. **Key Retrieval**: Decryption key reconstructed from Secure Storage + Custom Claims salt.
4. **Streaming Decryption**: File decrypted chunk-by-chunk into a memory buffer fed to the video player (never written decrypted to disk).
5. **Cleanup on Unbind**: When Admin unbinds a device (or subscription ends), `DrmLocalDataSource` wipes all encrypted files and keys (per FINAL_DECISIONS: "لو الاشتراك اتقفل: التحميلات تتمسح فوراً").

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
- Factory Reset = new device ID → `DrmLocalDataSource` reports `deviceMismatch` → triggers Admin re-approval flow (per FINAL_DECISIONS Section 1).

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

## 14.2 Custom Claims Structure

Per FINAL_DECISIONS Section 10, Custom Claims contain:

```json
{
  "role": "student | new_student | teacher | admin",
  "student_type": "public_free | center_free | center_pro | center_max",
  "plan_id": "plan_document_id",
  "max_devices": 1,
  "subscription_status": "active | frozen | expired",
  "approved": true | false
}
```

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

final maxDevicesProvider = Provider<int>((ref) {
  final claims = ref.watch(customClaimsProvider).value;
  return (claims?['max_devices'] as int?) ?? 1;
});

final subscriptionStatusProvider = Provider<String?>((ref) {
  final claims = ref.watch(customClaimsProvider).value;
  return claims?['subscription_status'] as String?;
});
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

# 15. Device Binding Check

Per FINAL_DECISIONS Section 1 and Master Architecture Section 7 ("Device Binding enabled", device limit plan-based per Master Architecture v1.2), this section defines the Flutter architecture for device registration, validation, and enforcement.

## 15.1 Device Identity

Each device is identified by a composite fingerprint:
- `device_id`: `androidId` (Android) or `identifierForVendor` (iOS) — NOT `Build.FINGERPRINT` (survives factory reset).
- `device_name`: User-friendly name (e.g., "Samsung Galaxy S23").
- `os_version`: Android/iOS version string.
- `app_version`: Current app version from `package_info_plus`.

Stored in Secure Storage on first launch. If missing → treat as new device.

## 15.2 Registration Flow

```
First-time login on a new device
         ↓
Flutter: read device_id from Secure Storage
         ↓
Cloud Function: onLoginAttempt(device_id, user_id)
         ↓
Firestore: check users/{userId}/device_bindings for matching device_id
         ↓
┌─────────────────┬─────────────────┐
│  Match found    │  No match       │
│  → Allow login  │  → Check count  │
│                 │  → If < max     │
│                 │    → Auto-bind  │
│                 │  → If >= max    │
│                 │    → Block +    │
│                 │      notify Admin│
└─────────────────┴─────────────────┘
```

## 15.3 Validation at Runtime

Device binding is validated at two layers:

### A. Authentication Layer (Cloud Function)
- Every `verifyPhonePassword` call includes `device_id`.
- Cloud Function rejects login if device is not in `device_bindings` and max_devices reached.

### B. Application Layer (Flutter)
- `DeviceBindingRepository` validates current device on app launch and periodically.
- If validation fails (device unbound by Admin, or factory reset detected), user is logged out and shown a message: "جهازك غير مُفعّل. تواصل مع الأدمن."

## 15.4 Feature Folder — `features/device_binding/`

```
features/device_binding/
├── domain/
│   ├── entities/
│   │   └── device_binding.dart     # device_id, device_name, bound_at, last_active
│   ├── repositories/
│   │   └── device_binding_repository.dart
│   └── usecases/
│       ├── validate_current_device.dart
│       ├── register_new_device.dart
│       └── get_bound_devices.dart
├── data/
│   ├── models/
│   │   └── device_binding_model.dart
│   ├── datasources/
│   │   ├── device_binding_remote_datasource.dart   # Firestore: users/{uid}/device_bindings
│   │   └── device_info_local_datasource.dart       # Secure Storage + device_info_plus
│   └── repositories/
│       └── device_binding_repository_impl.dart
└── presentation/
    ├── providers/
    │   └── device_binding_status_provider.dart     # Stream<bool> — isCurrentDeviceValid
    └── screens/
        └── device_blocked_screen.dart              # shown when binding fails
```

## 15.5 Integration with DRM (Section 13)

- `DrmLocalDataSource` depends on `DeviceBindingRepository`.
- Before decrypting any offline content, `validate_current_device` is called.
- If device is unbound → all encrypted content is wiped immediately (per FINAL_DECISIONS: "تغيير جهاز = التحميلات ترجع من أول وجديد").

## 15.6 Multi-Device Plans (Center Max)

- `maxDevicesProvider` (from Section 14.3) returns the limit from Custom Claims.
- `DeviceBindingRepository` enforces this limit at registration time.
- Admin Dashboard can override `max_devices` per student; Custom Claims updated via Cloud Function.

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

| Plan | Available Qualities | Max Resolution |
|------|---------------------|----------------|
| Public Free | Preview only (first X minutes) | 480p |
| Center Free | All lectures, single quality | 720p |
| Center Pro | All lectures, multi-quality | 1080p |
| Center Max | All lectures, multi-quality + download | 1080p |

Quality availability is controlled from Dashboard (Feature Matrix) and enforced in Cloud Function, not client-side.

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
- Offline videos are AES-256 encrypted and bound to device (Section 13 + 15).
- No video URL is ever logged to Analytics or Crashlytics.

## 16.7 Integration with Offline DRM

- `VideoPlayerScreen` checks if lecture is available offline via `OfflineContentRepository` (Section 13).
- If offline: routes playback through `DecryptForPlaybackUseCase` → feeds decrypted stream to player.
- If online: routes through `GetSignedVideoUrlUseCase` → streams from Bunny CDN.
- Seamless fallback: if offline file is corrupted or device binding fails, auto-fallback to online stream (if connected).

---

# 17. Cross-Feature Integration Summary

The four new architectural components (Sections 13–16) integrate as follows:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Authentication (Feature 01)                   │
│  Custom Tokens → Custom Claims → userRole, maxDevices, etc.    │
├─────────────────────────────────────────────────────────────────┤
│                    Device Binding (Section 15)                   │
│  Validates device_id → gates login & gates DRM decryption       │
├─────────────────────────────────────────────────────────────────┤
│                    Offline DRM (Section 13)                      │
│  AES-256 encrypted downloads → bound to validated device        │
│  Wiped on unbind / subscription expiry / factory reset          │
├─────────────────────────────────────────────────────────────────┤
│                    Video Player (Section 16)                     │
│  Online: Signed URLs from Bunny CDN via Cloud Function          │
│  Offline: Decrypted stream from DRM local storage               │
│  Quality & access controlled by Custom Claims + Feature Matrix  │
└─────────────────────────────────────────────────────────────────┘
```

All four components share:
- `core/di/` for Firebase instances and cross-cutting providers.
- `core/errors/` for unified `Failure` types (`DrmFailure`, `DeviceBindingFailure`, `VideoFailure`, `AuthFailure`).
- Custom Claims as the single source of truth for permissions, plan, and device limits.

---

# 18. Document Change Log

| Version | Date | Changes | Reason |
|---------|------|---------|--------|
| 1.0 | — | Initial draft | Base architecture document |
| 1.1 | 2026-08-04 | Added Sections 13–17: Offline DRM, Custom Tokens, Device Binding, Video Player (Bunny CDN), Cross-Feature Integration, and Change Log | Per FINAL_DECISIONS review chat — integrating all architectural decisions into Flutter layer |

---

END OF DOCUMENT
