# iOS TestFlight Runbook — Dr. Tarek Platform (refreshed 2026-10-14)

Recommended free route: **Codemagic Personal (500 M2-macOS min/mo, no card, Xcode 26.6)**. Fallback: **GitHub Actions `macos-26`** (private ≈200 effective macOS-min/mo at ~10× billing; `xcrun altool` is dead — use `fastlane pilot` / `upload-testflight-build` action + ASC API key). Xcode Cloud needs paid membership — not free. Nothing subscribed/activated from here. Apple rejects non-iOS-26-SDK IPAs since 2026-04-28 — pin Xcode 26.x.

## A. Codemagic route (recommended)

1. Owner: Codemagic login (GitHub) → connect repo → select Flutter/Xcode stack (latest stable) → open Usage tab to confirm 500-min quota.
2. Owner: provide signing via secure means — EITHER Apple Distribution `.p12` + password + provisioning profile (App Store) OR App Store Connect API key (Issuer ID + Key ID + `.p8`) + bundle/identifier already registered. Upload as Codemagic **secure env vars / code-signing identities** (never chat).
3. `codemagic.yaml` (add on Mac or via web editor):
   - `flutter --version`, `pod --version`, `xcodebuild -version` (record).
   - `flutter pub get` → `flutter analyze` → `flutter test test/core/errors test/authentication test/core/environment_test.dart`.
   - `cd ios && pod install --repo-update`.
   - Xcode step (Mac, once): add `GoogleService-Info-Staging.plist` file reference (already in `ios/Runner/`) and select it for the Staging/TestFlight configuration so the native FCM/Crashlytics layer reads `dr-tarek-staging` (Dart Auth/Firestore/Functions/Storage already isolate via `--dart-define=ENV=staging`).
   - `flutter build ipa --release --dart-define=ENV=staging --export-options-plist=$EXPORT_PLIST` (manual signing per uploaded profile) — or Xcode automatic signing with API key.
   - Publish step: App Store Connect (TestFlight external group "Dr Tarek External Testers"), beta review submission on, artifact retention on.
4. First run = cold pods (20–45 min); cached 12–25 min. On success: IPA artifact + TestFlight build processing → install on registered devices.
5. Failure diagnosis: check `Podfile.lock` Firebase iOS SDK pins (deployment-target errors → bump `IPHONEOS_DEPLOYMENT_TARGET` to 15/16+), `xcode_backend.sh` thin-binary errors (Flutter/Xcode mismatch → pin stack), signing errors (profile/Bundle ID mismatch → re-export profile).

## B. GitHub Actions fallback

1. Owner: make repo public (unlimited) or accept private cap; add encrypted Secrets: `IOS_P12_BASE64`, `P12_PASSWORD`, `PROVISION_PROFILE_BASE64`, `ASC_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`.
2. Workflow `ios-testflight.yml` on `macos-26`: setup Flutter (`subosito/flutter-action`), `pod install`, `flutter build ipa --dart-define=ENV=staging`, `xcodebuild -exportArchive`, upload via `fastlane pilot` (or `apple-actions/upload-testflight-build`) with the ASC API key. Pin actions by SHA; `retention-days: 14`.
3. Verify: IPA artifact + upload log + TestFlight processing status.

## C. Pre-upload gate (every staging build)

- `ENV=staging` proven (boot log project id), staging backend reachable, prod untouched.
- Bundle `com.drtarek.platform`, marketing `1.0.0`, build number = previous + 1 (monotonic).
- Capabilities/entitlements match portal (Push; App Attest/DeviceCheck if enforced); `NSCameraUsageDescription`/`NSPhotoLibraryUsageDescription` present (done in tree).
- dSYM uploaded → Crashlytics shows build UUID.
- Reviewer test account (phone+password, approved subject) ready for notes.

## D. Device smoke (TestFlight build, staging)

Fresh install → launch → custom-token login → role gates → Firestore reads/writes (staging) → foreground/background/terminated push → camera/gallery pick → Bunny HLS/MP4 playback + expiry denial → offline DRM encrypt/purge → screen-record shield (detection-only) → App Check → logout/session errors. Each PASS/FAIL recorded with device/iOS/build IDs. No PASS claimed without execution.

## E. Production TestFlight for real students (owner-approved 2026-10-31)

The Platform Owner runs pre-release testing with real students, so those beta builds must authenticate against **production** (`dr-tarek-platform`). This is an explicit exception to the staging-only rule in section C; the staging project is intentionally empty, so no real student can ever log in there.

- Workflow: `ios-production-testflight` in `codemagic.yaml` — manual trigger only, `--dart-define=ENV=prod`, same bundle `com.drtarek.platform`, same App Store Connect record and external group.
- Staging workflows (`ios-staging-validation`, `ios-staging-testflight`) are unchanged and remain the default for routine QA.
- Pre-upload gate for this workflow: boot log shows `PROJECT_ID=dr-tarek-platform`; production Auth/Firestore/Functions reachable; a `force_password_change` account can still sign in; the build number is higher than the last uploaded build (the workflow uses the UTC epoch as the build number).
- Testers moving from a staging build to a production build must **delete and reinstall** the app: the stored Firebase Auth session belongs to the previous project.
- Do not use this workflow for synthetic QA data; use `ios-staging-testflight` for that.

