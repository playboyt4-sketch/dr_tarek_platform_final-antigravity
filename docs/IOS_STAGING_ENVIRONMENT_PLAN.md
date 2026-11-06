# iOS Staging Environment Plan — Dr. Tarek Platform (TestFlight Isolation)

Goal: a TestFlight build must be **incapable** of reading/writing production. Status 2026-10-14: **project + app registrations + client selector IMPLEMENTED; service separation + Xcode wiring + device proof PENDING.**

## 1. Verified infrastructure (created 2026-10-14, Spark free tier, no billing touched)

- Project `dr-tarek-staging` (number `13159003436`, display `Dr Tarek Platform Staging`) — `firebase projects:list` VERIFIED. Production remains `dr-tarek-platform` (`606744934510`).
- Staging apps registered (VERIFIED via `firebase apps:list` equivalent + `sdkconfig`):
  - Android `1:13159003436:android:ce111f52a6ce2e42016889` (`com.drtarek.platform`)
  - iOS `1:13159003436:ios:f425a634a94b294e016889` (`com.drtarek.platform`)
  - Web `1:13159003436:web:ca447a3960b0eddf016889`
- `.firebaserc` now carries `"staging": "dr-tarek-staging"` (local alias only; default still production).

## 2. Client selector (IMPLEMENTED + tested, local tree)

- `lib/firebase_options_staging.dart` (new): staging options for android/ios/web, values cross-checked against `sdkconfig` output.
- `lib/config/environment.dart` (new): `parseEnvironment()` pure parser + `Environment.resolve()` (explicit `--dart-define=ENV=staging|prod`; missing ENV throws in release = fail closed, debug keeps historical prod workflow) + `optionsFor()`.
- `lib/main.dart`: Firebase init now uses `Environment.optionsFor(Environment.resolve())` inside the existing boot-error guard.
- `ios/Runner/GoogleService-Info-Staging.plist` (new, from `sdkconfig IOS`): **written but NOT wired into Xcode** — Mac step required (file reference + per-configuration selection), else the native FCM/Crashlytics layer still reads the prod plist.
- `test/core/environment_test.dart`: **5/5 PASS** (parser accept/reject, prod-vs-staging project split, Bundle ID parity).
- `dart analyze` on all touched Dart files: clean.

## 2. Target design (recommended: separate Firebase project)

1. Owner creates **`dr-tarek-staging`** (Spark plan if quotas suffice; Blaze only with explicit approval — FCM/APNs/Auth/Firestore/Storage/Functions all work on Spark; Blaze needed only for high egress/scheduled heavy use).
2. In staging console: register iOS app (`com.drtarek.platform`, staging config), Android staging app, Web staging app; upload **staging APNs key**; register App Check Apple provider; set `APP_CHECK_ENFORCEMENT=false` initially; configure staging `BUNNY_*` secrets (test library/zone).
3. Deploy to staging only: Firestore rules (same files), Storage rules, indexes, Functions (same codebase, staging secrets).
4. Seed staging with synthetic fixtures (never prod copies with PII). Owner test accounts + approved subjects for reviewers.

## 3. Client configuration strategy (implemented — see §2; assembled here for the record)

- `lib/config/environment.dart` with explicit `ReleaseEnvironment.production | .staging` selected **only** via `--dart-define=ENV=staging|prod` (fail-closed boot error on missing/invalid in release, mirroring the existing Firebase boot-error screen).
- Production stays the deliberate `firebase_options.dart` configuration; staging uses `firebase_options_staging.dart` (hand-verified against CLI output, not `flutterfire configure`).
- Staging secrets and Cloud Functions environment variables: NOT YET ISOLATED (see §4).
- Repeatable staging build: `flutter build ipa --release --dart-define=ENV=staging` (+ Mac signing/upload steps in the runbook).

## 4. Remaining separation work — preflight verdict 2026-10-14: DEPLOY BLOCKED (exact prerequisites below)

Preflight (all read-only + local build): target confirmed `dr-tarek-staging`; billing ✅; `npm run build` ✅ clean; unit suites green (`assessment_o6b`, `migrate_teacher_to_doctor`, `password_reset_target_role`); prod untouched. Deployment scope would be the full functions codebase (~83 callables incl. new `getAssessmentQuestions`).

Missing prerequisites (deploy STOPPED before any mutation):
1. **Staging Firestore database: CREATED 2026-10-14** (`(default)`, `us-central1`, `FIRESTORE_NATIVE`, STANDARD edition — verified via `databases describe`; prod identical and untouched). `firebase.json` (`database: (default)`, `location: us-central1`) matches — no conflict.
2. **Rules + indexes DEPLOYED to staging 2026-10-14** (`firebase deploy --only firestore:rules,firestore:indexes --project dr-tarek-staging` → "Deploy complete"; rules compiled with 3 pre-existing style warnings only; 36 indexes from `firestore.indexes.json` confirmed present via `firestore:indexes` listing). No validation failures, no doc conflicts. Production rules/indexes untouched.
2. **5 Secret Manager secrets absent** (`BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STORAGE_PASSWORD`) — Secret Manager API never enabled (hence zero secrets). Owner must supply **test-zone** values; prod values must NOT be copied. Secret values are never printed or committed.
3. **`functions/.env` is prod-bound** (untracked, gitignored ✅ — no committed sprawl) and `firebase deploy` ships `.env` to the target: deploying now would point staging functions at the **prod Bunny stream library**. Required: owner-supplied test values in `functions/.env.dr-tarek-staging` (auto-loaded per-project override; also gitignored), plus staging `APP_CHECK_ENFORCEMENT=false`.
4. Then: rules/indexes deploy to staging, functions deploy (`firebase deploy --only functions --project dr-tarek-staging`), APNs staging key, App Check staging provider, synthetic fixtures, device proof.
2. **Staging APNs key** + Firebase Cloud Messaging config; **staging App Check** Apple provider registration (enforcement OFF until proven).
3. **Staging `BUNNY_*` secrets** (test library/zone) + staging seed fixtures (synthetic, never prod PII copies).
4. **Xcode wiring**: reference `GoogleService-Info-Staging.plist` + per-configuration selection (exact UI steps for Mac — no hand-edited pbxproj from here).
5. **Validation** (before any TestFlight upload): boot staging IPA → confirm `PROJECT_ID=dr-tarek-staging`; mutate staging; assert production unchanged (read-only prod console); staging push + Crashlytics build UUID.

## 5. Owner actions — status 2026-10-15: FUNCTIONS DEPLOYED 69/69 ✅

- ✅ DONE: project, apps, Firestore DB, rules + 36 indexes, client ENV selector, billing linked, **all 69 non-Bunny functions deployed to `dr-tarek-staging`** (`us-central1`, nodejs24; verified by listing: 69 present, 0 missing, 0 extras, 6 Bunny absent).
- ✅ Cleanup policy applied as inspected (`gcf-artifacts`, `firebase-functions-cleanup`, DELETE >86400s).
- ✅ Schedules live: `processNotificationQueue` 1min, `cleanupInvalidDeviceTokens` 24h, `autoPublishDueLectures` 5min; recent logs show no ERROR/CRITICAL.
- ✅ Live smoke (synthetic, no users needed): unauthenticated `getAssessmentQuestions` → 401 clean; `submitPasswordResetRequest` unknown phone → uniform `{"submitted":true}` (no write).
- ✅ Prod untouched (incl. `getAssessmentQuestions` absent from prod).
- DEPLOY NOTES: firebase-tools 15.24.0 honors only the FIRST name of a comma `--only` list (proven 4×) → deployed via single-name batches; discovery needed `FUNCTIONS_DISCOVERY_TIMEOUT=180` on this host; one transient Eventarc failure retried green.
- OPEN:
  1. **Auth providers** (email + anonymous) must be enabled in staging console — required for ANY test-user flow (O6-B live test included). CLI credentials insufficient (403); no workaround without console.
  2. Bunny test credentials + test video in 780700 (6 media functions excluded by design).
  3. Staging APNs key + App Check provider + synthetic fixtures + device proof + Mac IPA/TestFlight.
