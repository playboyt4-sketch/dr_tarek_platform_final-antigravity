# 08 Development Standards

Version: 1.1
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

---

# 1. Purpose

This document defines coding conventions, naming rules, and quality gates for implementation. It applies the principles already declared in Master Architecture (Sections 9, 9.2) — it does not introduce new architectural decisions; those belong to 00 Master Architecture, 06 Firebase Architecture, and 07 Flutter Architecture.

---

# 2. Naming Conventions

Per Master Architecture Section 9.2 (not redefined, only extended to code-level specifics):

| Element | Convention | Example |
| --- | --- | --- |
| Firestore collections/fields | snake_case | `student_progress`, `created_at` (per Master Architecture 9.2) |
| Feature keys | dot.notation | `lecture.video.download` |
| Dart files | snake_case | `lecture_repository_impl.dart` |
| Dart classes | UpperCamelCase | `LectureRepositoryImpl` |
| Dart variables/functions | lowerCamelCase | `getLecturesForSection()` |
| Dart constants | lowerCamelCase with `k` prefix avoided; use `const` + descriptive name | `defaultPageSize`, not `kDefaultPageSize` |
| Riverpod providers | lowerCamelCase + `Provider` suffix | `lectureRepositoryProvider`, `currentUserProvider` |
| Enums (Dart) | UpperCamelCase type, lowerCamelCase values | `enum UserRole { newStudent, student, admin, teacher }` — mirrors the Database enum values from Master Architecture Section 6.1 |

## 2.1 Custom Tokens Naming (V1)

Per FINAL_DECISIONS Section 3 (Authentication V1: Custom Tokens):

| Element | Convention | Example |
| --- | --- | --- |
| Custom Token generation function | `generate{Role}CustomToken` | `generateStudentCustomToken()` |
| Custom Token provider | lowerCamelCase + `Provider` suffix | `customTokenProvider`, `authTokenProvider` |
| Token claim field (Firestore) | snake_case | `custom_token`, `token_expires_at` |
| Token payload key (JWT) | snake_case | `role`, `student_type`, `plan_id`, `max_devices` |
| Token verification method | `verifyCustomToken` | `verifyCustomToken(String token)` |
| Token refresh notifier | lowerCamelCase + `Notifier` suffix | `tokenRefreshNotifier` |

- Custom Tokens are the sole authentication mechanism in V1. No pseudo-email or anonymous auth fallback is permitted in production code.
- Token claims (`role`, `student_type`, `plan_id`, `max_devices`) must be read from the token payload only; never hardcode default claim values in client code.

---

# 3. File & Folder Rules

- One public class per file (matches 07 Flutter Architecture's feature-first structure).
- No file exceeds ~300 lines as a soft guideline; if a widget file grows beyond that, it must be decomposed into smaller widgets (Master Architecture Section 9: "Small Widgets").
- No business logic inside a `build()` method — extract to a Notifier/provider or a Domain use case.

---

# 4. SOLID & Code Quality

Per Master Architecture Section 9:

- **Single Responsibility** — a class does one thing (a Repository does data access; a Notifier holds state; a Widget renders).
- **Strong Typing** — no `dynamic` in Domain or Data layers except at the JSON-decoding boundary (`fromJson`).
- **No duplicated code** — shared logic extracted to `core/` (07 Flutter Architecture Section 4) rather than copy-pasted across features.
- Every public class/method that isn't self-explanatory from its name gets a doc comment (`///`).

---

# 5. Error Handling Standard

Per 07 Flutter Architecture Section 9: all Data-layer exceptions are caught and mapped to the shared `Failure` hierarchy before reaching Presentation. Raw `try/catch` blocks are not allowed to leak into widget code — errors surface via provider state (`AsyncValue.error`), rendered through a shared error-state widget from `core/widgets/`.

---

# 6. Git & Commit Conventions

- Branch naming: `feature/{feature-key}`, `fix/{short-description}`, `chore/{short-description}` — e.g. `feature/lecture-video-download`.
- Commit messages follow Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
- No direct commits to `main`/`production` branch — all changes via pull request.

---

# 7. Testing Standard

Building on 07 Flutter Architecture Section 11:

- Every new Repository implementation ships with at least one test against the Firebase emulator suite, not production Firestore.
- Every Domain use case with conditional logic (e.g., access-check use cases) ships with unit tests covering both the allow and deny path.
- Widget tests are required for any screen containing a form or payment-adjacent flow (membership, exam submission).

## 7.1 Device Binding Testing

Per FINAL_DECISIONS Section 1 (Device Binding):

| Scenario | Test Type | Expected Result |
| --- | --- | --- |
| Login within `max_devices` limit | Unit + Emulator | Access granted; device fingerprint stored in `user_devices` collection |
| Login exceeds `max_devices` limit | Unit + Emulator | Access denied; `DeviceLimitExceededFailure` returned |
| Admin revokes a bound device | Emulator | Revoked device fingerprint removed; new device can bind |
| Factory Reset (new device ID) | Emulator | Treated as new device; requires admin re-approval if limit reached |
| Device fingerprint mismatch | Unit | `DeviceBindingFailure` returned; no Firestore read permitted |
| Cloud sync after device change | Integration | `learning_progress`, `notes`, `exam_results` sync from Firestore to new device |

- Device fingerprint must be generated from a stable hardware identifier + app signature hash. Never rely on `androidId` or `UUID` alone.
- `max_devices` value is read from the user's Custom Claims (`max_devices` claim) — never hardcode `1` or `2` in client logic.
- All Device Binding logic lives in the Data layer (`auth/` or `device/` repository); no widget performs direct device validation.

---

# 8. DRM Implementation Standards

Per FINAL_DECISIONS Section 2 (Offline Learning) and Section 10 (Technical Notes):

| Element | Standard | Rationale |
| --- | --- | --- |
| Encryption algorithm | AES-256-GCM | Industry standard; authenticated encryption prevents tampering |
| Key storage | Flutter Secure Storage (Keychain/Keystore) | Keys must never be written to `SharedPreferences`, `getApplicationDocumentsDirectory()`, or any unencrypted storage |
| Key derivation | PBKDF2 with 100,000 iterations + device-bound salt | Prevents key extraction if device storage is dumped |
| Encrypted file extension | `.drm` | Clearly distinguishes protected content |
| Download directory | `getApplicationSupportDirectory()` / `NSLibraryDirectory` — never `Downloads` or `DCIM` | Prevents user access outside the app |
| File access | Only through the `DrmRepository` abstraction | No widget or service accesses the file system directly |
| Subscription expiry check | Before every playback attempt, verify `plan_expires_at` via Repository | If expired, delete all `.drm` files immediately and return `SubscriptionExpiredFailure` |
| Device change policy | On new device binding, all `.drm` files are invalidated; re-download required | Per FINAL_DECISIONS: "تغيير جهاز = التحميلات ترجع من أول وجديد" |
| Decryption stream | Chunked decryption into memory buffer; never write decrypted bytes to disk | Prevents extraction of raw video files |

### DRM Code Review Gate

Before any PR touching DRM code is merged, the following must be verified:

- [ ] No plaintext video file is ever written to device storage.
- [ ] Encryption key is not hardcoded; it is derived at runtime from device-bound parameters.
- [ ] `DrmRepository` is the only class that calls `flutter_secure_storage` or file I/O for `.drm` files.
- [ ] Subscription status is checked before decryption; expiry triggers immediate wipe.
- [ ] Unit tests cover: (a) successful encrypt/decrypt roundtrip, (b) wrong key failure, (c) tampered file failure, (d) expiry-triggered wipe.

---

# 9. Password Reset Workflow (Admin-Triggered)

Per FINAL_DECISIONS Section 3 (Authentication):

> نسيت الباسورد: الطالب يضغط "نسيت" → إشعار للأدمن/المالك → يغيّروه من Dashboard

### 9.1 Flow Overview

```
Student taps "Forgot Password"
    ↓
App sends `password_reset_request` document to Firestore
    ↓
Cloud Function `onPasswordResetRequest` triggers
    ↓
In-App Notification + Push Notification sent to Admin/Teacher
    ↓
Admin/Teacher opens Dashboard → views pending requests
    ↓
Admin/Teacher sets new temporary password
    ↓
Cloud Function `onPasswordResetApproved` updates Firebase Auth password
    ↓
Student receives In-App Notification: "Password reset by admin. Login with your phone number."
```

### 9.2 Implementation Rules

| Rule | Detail |
| --- | --- |
| Who can reset | **Teacher (Platform Owner) only** in V1. Admin role does NOT have this permission. |
| Student action | Student taps "Forgot Password" → app writes `password_reset_request` with `status: pending`, `requested_at: Timestamp`, `student_id`, `phone_number`. No password hint or security question is shown. |
| Notification | Dual notification (Push + In-App) sent to all users with `role == teacher` via Cloud Function. |
| Dashboard action | Teacher views request, enters new temporary password (plain text input; no auto-generation). |
| Password update | Cloud Function calls Firebase Admin SDK `updateUser(uid, { password: newPassword })`. |
| Student notification | After update, student receives In-App notification only (no SMS/email in V1). |
| Audit | `password_reset_request` document updated with `resolved_by`, `resolved_at`, `new_password_hash` (optional, for audit), `status: resolved`. |
| Security | The new password is temporary. Student must change it on first login (enforced by `force_password_change` flag in Custom Claims). |

### 9.3 Naming for Password Reset

| Element | Convention | Example |
| --- | --- | --- |
| Firestore collection | snake_case | `password_reset_requests` |
| Request document fields | snake_case | `student_id`, `phone_number`, `requested_at`, `status`, `resolved_by` |
| Cloud Function | camelCase trigger name | `onPasswordResetRequest`, `onPasswordResetApproved` |
| Repository method | lowerCamelCase | `submitPasswordResetRequest()`, `getPendingPasswordResetRequests()` |
| Notifier | lowerCamelCase + `Notifier` suffix | `passwordResetRequestNotifier` |
| UI widget | UpperCamelCase | `PasswordResetRequestScreen`, `PendingPasswordResetList` |

---

# 10. Code Review Checklist (minimum, before merge)

- [ ] No direct Firestore/Storage/Auth SDK call outside the Data layer.
- [ ] No hardcoded business rule or permission (Master Architecture Section 5: "No hardcoded business rules... All permissions are data-driven").
- [ ] No hardcoded strings for user-facing text (localization-ready, per Vision's Accessibility/Responsive principles) — even though multi-language is not an explicit Version 1 requirement, avoiding hardcoded strings costs nothing now and avoids a rewrite later.
- [ ] Naming matches Section 2 of this document.
- [ ] New Firestore reads are covered by a Security Rule (per 06 Firebase Architecture Section 4.2) — a Repository method must not be merged if the corresponding Rule doesn't exist yet.
- [ ] Device Binding logic uses `max_devices` from Custom Claims, not a hardcoded integer.
- [ ] DRM code passes the gate in Section 8.
- [ ] Password reset flow writes to `password_reset_requests` collection; no client-side direct password update.

---

# 11. Open Items (flagged for Teacher review)

- [ ] Confirm whether a linter config (e.g., `very_good_analysis` or `flutter_lints` with custom rules) should be standardized and checked in CI — assumed desirable but not previously specified.
- [ ] Confirm CI/CD tooling (GitHub Actions vs. other) — no prior document specifies this; deferred until decided, not invented here.

---

END OF DOCUMENT
