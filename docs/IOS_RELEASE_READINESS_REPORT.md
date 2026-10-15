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

## 5. Validation results (M5) — updated 2026-10-14 (O6-B)

- Server: `npm run build` (tsc) clean; `node functions/test/assessment_o6b.test.js` **PASS** (sanitizer stripping, fallbacks, contract surface, no-evaluate-endpoint); `migrate_teacher_to_doctor` 11/11 + `password_reset_target_role` 9/9 revalidated PASS. `npx eslint src/index.ts`: zero findings in new ranges; file-level `linebreak-style` (whole-file CRLF) + old JSDoc/`any` issues are pre-existing (Windows checkout), not regressions.
- Client: `flutter test test/assessment_taking/assessment_o6b_test.dart test/exams test/timeline_quizzes` **8/8 PASS** (4 new O6-B + existing suites with updated fakes); `dart analyze` on all touched Dart dirs **clean**.
- Staging: `functions:list --project dr-tarek-staging` → empty (expected, nothing deployed); prod listing read-only verified untouched. Functions deploy to staging **BLOCKED — requires Blaze billing approval** (no paid activation without owner).
- Role suites rerun rationale: untouched by this task (no role files changed) — prior PASS stands; migration + reset tests above re-ran green.

## 6. Known defects / risks blocking TestFlight (updated 2026-10-14: O6-B implemented)

1. **Assessment APIs (was P0-broken — now IMPLEMENTED, deploy pending):** `getAssessmentQuestions` callable added (sanitized `{id,type,text,options,marks,order}`, ownership + started-only + published + subject-entitlement + time gate; never keys/explanations/scores); `submitAssessmentAttempt` hardened with transactional subject-entitlement check (staff bypass); idempotent via started-status gate; client evaluate-flow removed (provider records locally; UI neutral selection, no correctness colors/explanations); `result.correct` Map defect eliminated (typed per-branch results); `evaluateQuestionAnswer` confirmed absent by test. Residual: embedded-keys latent risk IF keys ever embedded in quiz/exam docs (no writers exist — bank-only invariant); explanations omitted entirely (no Approved policy authorizes release).
2. **Legacy XOR vault is DEAD code** (`offline_drm_service.dart` — zero references in `lib/`/`test/`); live path is sound AES-256-GCM (`drm_repository_impl.dart`). Fix = delete or deprecate (deferred to authorized security pass; no beta exclusion warranted).
3. **Plaintext PDF exposure (Medium, local-only):** decrypted temp files (`temp_{resourceId}.pdf`, predictable name, `dispose`-only wipe) + `flutter_cached_pdfview` disk cache outside DRM wipe. Fixes identified (random names, startup sweep, logout cache clear) — deferred, no exclusion warranted.
4. **Staging service separation pending:** project + apps + client selector done; still open: rules/indexes/functions deploy to staging, staging APNs, staging App Check provider, staging Bunny secrets, Xcode plist wiring, device proof.
5. **App Check screenshot reconciled (VERIFIED via `firebase apps:list`):** row 1 = ANDROID (Play Integrity + Fraud Defense — correct, preserve); row 2 = **iOS app `…:ios:9718…` with provider UNREGISTERED** (app exists — do NOT re-register; provider registration is a future staging/prod decision, enforcement stays OFF); rows 3–4 = web apps. Client providers correct in `main.dart` (App Attest + DeviceCheck fallback / Debug). Web reCAPTCHA: prod web requires `--dart-define=RECAPTCHA_SITE_KEY` (CI injects); no change made.
6. **Compliance opens** (unchanged): privacy/terms/support URLs absent; manifest empty data-types; export answer pending; UGC report/block/moderation absent.
7. Full-project analyze + emulator suites + Apple pipeline await capable environments.

## 7. Milestones

M0 ✅ · M1 ✅ · M2 ✅ code-level (prod migration pending O1) · M3 🟡 project+apps+selector done; deploy/APNs/AppCheck/Bunny/Xcode-wiring pending (deploy BLOCKED: staging Firestore DB + Bunny test secrets + staging .env — see staging plan §4) · M4 🟡 · M5 🟡 (O6-B suites green; full analyze + emulator blocked) · M6 ❌ BLOCKED (no Mac) · M7 ❌ BLOCKED · M8 🟡 this handoff. O6-B: contract implemented + tested locally; staging deploy + device proof pending.
