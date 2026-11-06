# iOS Release Readiness Report — Dr. Tarek Platform

Date: 2026-10-14 (updated in-task: staging project created, env selector implemented+tested, App Check rows reconciled, assessment/DRM traced). Status: **BLOCKED for TestFlight** (see gates). All statements evidence-backed; `VERIFIED` = file/command observed, `NOT RUN` / `BLOCKED` marked explicitly.

## 1. Baseline (M0)

- Branch `main` (ahead state per `git status --short --branch`), repo root = Flutter app root (`pubspec.yaml`: `dr_tarek_platform 1.0.0+1`).
- Working tree: **~360 modified/untracked paths** at audit start (app, backend, Firebase, Android, iOS, config). Nothing discarded; all changes preserved.
- Toolchain on this workstation: Flutter 3.44.4 / Dart 3.12.2, Node 24.19, Java Temurin 21, firebase-tools 15.24. OS: **Windows 10 Pro — no macOS/Xcode** (all Apple build/sign/upload checks require macOS).

## 2. Identity (VERIFIED)

- iOS Bundle ID `com.drtarek.platform` (Runner Debug/Profile/Release identical; `…RunnerTests` for tests) — `ios/Runner.xcodeproj/project.pbxproj:385,564,586,401,418,433`. Owner-ratified FINAL 2026-10-14.
- Display name `Tarek El Araby Platform` (iOS `Info.plist:9-10`, Android manifest label). SKU `TAREK-PLATFORM-IOS-001`, category Education.
- Firebase project `dr-tarek-platform` everywhere (`.firebaserc`, `firebase.json`, `firebase_options.dart`, both native plists). iOS `appId …:ios:9718…` + `iosBundleId` match tree.
- Deployment target **13.0** (`project.pbxproj` ×3) — expected to fail CocoaPods against current Firebase iOS SDKs; bump on Mac.
- Version `1.0.0+1` kept temporarily; `100000`-style scheme NOT adopted (Draft-only proposal).

## 3. Changes implemented in this task (all minimal, reversible)

Prior task (verified present, not duplicated): purpose strings in `Info.plist`, identity-plan v1.1, `13_Releases` finals table, `14_…` screenshot row, root stub pointers, the five `docs/IOS_*` files.

This task:
1. Created Firebase project `dr-tarek-staging` (Spark, no billing) + registered staging Android/iOS/Web apps (same Bundle ID/package — allowed across projects).
2. Added `lib/firebase_options_staging.dart` (values verified against `sdkconfig`), `lib/config/environment.dart` (explicit `ENV`, fail-closed release), wired `lib/main.dart`, added `.firebaserc` staging alias, wrote `ios/Runner/GoogleService-Info-Staging.plist` (Xcode wiring pending Mac).
3. Added `test/core/environment_test.dart` — 5/5 PASS.
4. Updated all five `docs/IOS_*` files (this file included) with the new evidence; no duplicate reports created.

## 4. Role migration M2 (VERIFIED at code level)

- `firestore.rules`: `isDoctor()/isStaff()` doctor-based; zero `teacher` authorization literals. `storage.rules`: same.
- `functions/src`: zero `teacher` hits; `ADMIN_ROLES={admin,doctor}`, `requireDoctor` enforced.
- `dashboard/lib`, mobile guards: doctor-based; remnants cosmetic only (route/file names, `NoteType.teacher`, l10n strings) with no authz impact.
- Regression vectors already quarantined in tree: `seed_database.ts` + `set_teacher_password.ts` carry DO-NOT-RUN headers (no change made — header requires owner decision to alter).
- Tests PASS: `functions/test/migrate_teacher_to_doctor.test.js` (11 checks: preconditions, idempotency, rollback) and `password_reset_target_role.test.js` (9 checks incl. legacy-teacher denied). `security-tests/rules.test.js:577-579,1385-1405` asserts stale-teacher denial (code read; emulator run blocked — §6).
- **Not done:** production data migration (needs explicit ops approval) + owner re-login to mint doctor claims.

## 5. Validation results (M5) — updated 2026-10-15 (STAGING DEPLOYED)

- Server: `npm run build` (tsc) clean; `node functions/test/assessment_o6b.test.js` **PASS**; `migrate_teacher_to_doctor` 11/11 + `password_reset_target_role` 9/9 revalidated PASS. `npx eslint src/index.ts`: zero findings in new ranges; file-level `linebreak-style` (whole-file CRLF) + old JSDoc/`any` issues are pre-existing (Windows checkout), not regressions.
- Client: `flutter test test/assessment_taking/assessment_o6b_test.dart test/exams test/timeline_quizzes` **8/8 PASS**; `dart analyze` on all touched Dart dirs **clean**.
- Staging deploy 2026-10-15: **69/69 non-Bunny functions VERIFIED live** (0 missing, 0 extras, 6 Bunny absent; `us-central1`, nodejs24). Schedules live (1min/24h/5min), no ERROR/CRITICAL in logs. Cleanup policy applied as inspected. Live smoke: unauthenticated assessment call → 401 clean; unknown-phone reset → uniform success without writes.
- Deploy mechanics learned: firebase-tools 15.24.0 honors only the FIRST name of a comma `--only` list (proven 4×) → deployed via single-name batches; discovery needed `FUNCTIONS_DISCOVERY_TIMEOUT=180` on this host; one transient Eventarc failure retried green.
- Prod untouched (incl. `getAssessmentQuestions` absent from prod).
- Role suites rerun rationale: untouched by this task — prior PASS stands.
- Remaining: Auth providers (email/anonymous) NOT enabled on staging → no test-user flows possible until console enablement (CLI creds insufficient, 403).

## 6. Known defects / risks blocking TestFlight (updated 2026-10-14: O6-B implemented)

1. **Assessment APIs (IMPLEMENTED + DEPLOYED 2026-10-15, live proof partial):** contract as before, now live on staging (`getAssessmentQuestions` + `submitAssessmentAttempt` verified present); live smoke proves auth gate (401) + anonymous-safe reset; full owner/intruder/resubmit flow awaits test users (Auth providers).
2. **Legacy XOR vault is DEAD code** (`offline_drm_service.dart` — zero references in `lib/`/`test/`); live path is sound AES-256-GCM (`drm_repository_impl.dart`). Fix = delete or deprecate (deferred to authorized security pass; no beta exclusion warranted).
3. **Plaintext PDF exposure (Medium, local-only):** decrypted temp files (`temp_{resourceId}.pdf`, predictable name, `dispose`-only wipe) + `flutter_cached_pdfview` disk cache outside DRM wipe. Fixes identified (random names, startup sweep, logout cache clear) — deferred, no exclusion warranted.
4. **Staging separation:** project + apps + DB + rules/indexes + 69 functions + schedules + cleanup + client selector done; still open: Auth providers, APNs, App Check provider, Bunny secrets + video, synthetic fixtures, Xcode wiring, device proof.
5. **App Check screenshot reconciled (VERIFIED via `firebase apps:list`):** row 1 = ANDROID (Play Integrity + Fraud Defense — correct, preserve); row 2 = **iOS app `…:ios:9718…` with provider UNREGISTERED** (app exists — do NOT re-register; provider registration is a future staging/prod decision, enforcement stays OFF); rows 3–4 = web apps. Client providers correct in `main.dart` (App Attest + DeviceCheck fallback / Debug). Web reCAPTCHA: prod web requires `--dart-define=RECAPTCHA_SITE_KEY` (CI injects); no change made.
6. **Compliance opens** (unchanged): privacy/terms/support URLs absent; manifest empty data-types; export answer pending; UGC report/block/moderation absent.
7. Full-project analyze + emulator suites + Apple pipeline await capable environments.

## 7. Milestones

M0 ✅ · M1 ✅ · M2 ✅ code-level (prod migration pending O1) · M3 ✅ backend deployed (69/69 + schedules + cleanup; Auth providers pending console) · M4 🟡 (Xcode wiring needs Mac) · M5 ✅ (unit + live smoke green; full O6-B live flow needs test users) · M6 ❌ BLOCKED (no Mac) · M7 ❌ BLOCKED · M8 🟡 this handoff.
