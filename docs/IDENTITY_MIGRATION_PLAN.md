# IDENTITY MIGRATION PLAN

Status: **EXECUTED 2026-08-22 — Final identity adopted by owner delegation: com.drtarek.platform**
Version: 1.0
Date: 2026-08-22
Owner decision required: **Final Identifier value** (see Section 2). This plan
must NOT be executed until the Project Owner selects the Final Identifier.
No identifier value is proposed or chosen here.

---

## 1. Current State (verified 2026-08-22)

### 1.1 Display names — ALREADY CORRECT (do not touch)

| Platform | Key | Value | File |
|---|---|---|---|
| Android | `android:label` | Dr. Tarek El Araby Platform | `android/app/src/main/AndroidManifest.xml:6` |
| iOS | `CFBundleDisplayName` | Dr. Tarek El Araby Platform | `ios/Runner/Info.plist:9-10` |
| iOS | `CFBundleName` | DrTarekElArabyPlatform | `ios/Runner/Info.plist:17-18` |
| Web | `<title>` / apple title / manifest name+short_name | Dr. Tarek El Araby Platform | fixed during Final Verification phase |

Display Name, Application ID, Bundle Identifier, and Firebase App
Registration are four different things; only the technical identifiers below
are wrong.

### 1.2 Technical identity remnants — FUNCTIONAL files (8)

Old identity values:
- Android/Linux style: `com.example.flutter_analyzer_test`
- Apple camelCase style: `com.example.flutterAnalyzerTest`

| # | File | What carries the old identity |
|---|---|---|
| 1 | `android/app/build.gradle.kts:23,37` | `namespace`, `applicationId` |
| 2 | `android/app/src/main/kotlin/com/example/flutter_analyzer_test/MainActivity.kt` | Kotlin package declaration AND its directory path |
| 3 | `android/app/google-services.json` | `package_name` registered as old applicationId (single registration) |
| 4 | `lib/firebase_options.dart:73` | `iosBundleId: 'com.example.flutterAnalyzerTest'` |
| 5 | `ios/Runner.xcodeproj/project.pbxproj` lines 385,564,586 | Runner target PRODUCT_BUNDLE_IDENTIFIER (Debug/Profile/Release) |
| 6 | `ios/Runner.xcodeproj/project.pbxproj` lines 401,418,433 | RunnerTests target PRODUCT_BUNDLE_IDENTIFIER (`<id>.RunnerTests`) |
| 7 | `macos/Runner/Configs/AppInfo.xcconfig` | macOS bundle id (out of V1 release scope, still carries old id) |
| 8 | `macos/Runner.xcodeproj/project.pbxproj` | macOS runner bundle id references |

Non-functional references also exist (IDE metadata `.idea/modules.xml`,
root `.iml`, build logs, historical reports). They are not shipped and are
listed only for completeness.

### 1.3 Firebase registrations (console side — owner action)

- Firebase project: `dr-tarek-platform`
- Android app registered under OLD applicationId (matches current
  google-services.json)
- iOS app registered under OLD Bundle ID (appId `1:606744934510:ios:…`)
- Web app registered (unaffected by this migration)

## 2. Required Owner Decision

The Project Owner must supply exactly two values:

1. **Android Application ID** (final, permanent after first Play upload).
   Convention: reverse-domain owned by the business.
2. **iOS/macOS Bundle ID** (final). May equal the Android application id;
   that is an owner choice, not an assumption of this plan.

Until these values arrive, NO file listed above is modified.

## 3. Execution Steps (after owner supplies values)

### 3.1 Order matters

1. Register new app identities in the Firebase console (owner):
   - Add Android app with the NEW applicationId → download NEW
     `google-services.json`.
   - Add iOS app with the NEW Bundle ID → download NEW
     `GoogleService-Info.plist` (also fixes the currently MISSING iOS plist).
   - Keep old registrations intact until step 5 passes.
2. FlutterFire reconfigure: run `flutterfire configure` with all platforms
   selected → regenerates `lib/firebase_options.dart` (replaces manual edit
   of `iosBundleId`) and places both platform config files.
3. Android:
   - `applicationId` and `namespace` → new value.
   - Move `MainActivity.kt` to the matching package directory tree and
     update its `package` line.
4. iOS: update all six PRODUCT_BUNDLE_IDENTIFIER entries (Runner ×3,
   RunnerTests ×3 = `<new>.RunnerTests`).
5. macOS (optional, out of release scope): AppInfo.xcconfig + pbxproj.
6. Sweep: repo-wide search for `flutter_analyzer_test|flutterAnalyzerTest`
   must return ZERO functional-file hits (reports/logs excluded).

### 3.2 Validation gates (all must pass before closing the blocker)

- [ ] `flutter analyze` — no issues
- [ ] `flutter test` — all tests pass
- [ ] `flutter build apk --release` succeeds
- [ ] `flutter build appbundle --release` succeeds
- [ ] AAB signature fingerprint == dr-tarek-upload.jks SHA-256
      `E968DD3BFFF13E7C16B557E7C16B557E7C6EB969754897833CCED3EA1C5A2A07756104B3F`
- [ ] google-services.json contains ONLY the new package_name
- [ ] firebase_options.dart iosBundleId == new iOS Bundle ID
- [ ] Firebase console registrations match the built artifacts
- [ ] Zero old-identity references in functional files

## 4. Risks & Notes

- applicationId is permanent after first store publication — this is why no
  placeholder may be committed.
- Changing applicationId invalidates existing installs as "different app"
  (acceptable pre-production).
- App Check registration must be repeated for the NEW identifiers when the
  owner activates enforcement.
