# App Store Compliance Checklist — Dr. Tarek Platform v1.0.0+1 (TestFlight beta)

Legend: ✅ verified · 🟡 pending · 🔴 blocked · ➖ N/A. No legal claims made; URLs never invented.

## Metadata

- ✅ Name `Tarek El Araby Platform` (`Info.plist:9-10`, manifest label) · Bundle `com.drtarek.platform` · SKU `TAREK-PLATFORM-IOS-001` · Category Education · Version `1.0.0+1` (temp policy).
- ✅ `ITSAppUsesNonExemptEncryption=false` present (`Info.plist:27-28`) — correctness PENDING legal/export review (AES-256 DRM + `cryptography` dep).

## Permissions

- ✅ `NSCameraUsageDescription` + `NSPhotoLibraryUsageDescription` added (bilingual, flow-truthful) — `ios/Runner/Info.plist`. Device prompt still to be proven on iPhone.
- ➖ Mic/location/contacts/calendar/speech: no API usage found — keys deliberately NOT added.
- 🟡 `NSPhotoLibraryAddUsageDescription` / iCloud file-picker entitlement: only if save-to-library / iCloud flows proven.

## Privacy

- 🟡 `PrivacyInfo.xcprivacy`: tracking=false + required-reason APIs declared; `CollectedDataTypes=[]` contradicts actual Auth/Firestore/FCM/photo collection — Connect nutrition labels must declare them explicitly (legal).
- 🔴 Privacy-policy / Terms / Support URLs: none in repo — must be published and added to listing + in-app before submission.

## Accounts / payments / login

- ✅ Creation = phone+password custom tokens; deletion = in-app self-delete (`deleteMyAccount` + dialog + bilingual retention copy) + owner delete — code satisfies Guideline 5.1.1(v); server behavior staging-verified pending.
- ✅ No IAP in binary; V1 = manual external Dashboard logging (FINAL §6). 🟡 Confirm zero external purchase links in reviewer path.
- ➖ Sign in with Apple: N/A (no third-party login; V1.2 revisit).

## Content / rating / review

- 🔴 UGC (chat/Q&A/uploads) has no in-app report/block/filter + 24h moderation evidence — age-rating questionnaire + moderation required.
- 🟡 Screenshot behavior now documented detection-only; sweep subscription/admin UI copy before upload.
- 🟡 Reviewer kit: test phone+password account with approved subject, Bunny playback note, push note, no-IAP statement, detection-only disclosure.
- 🟡 Push/APNs key, App Check provider/enforcement, distribution cert/profile, dSYM: all pending portal + Mac. (App Check prod rows reconciled 2026-10-14: Android = Play Integrity ✅ preserve; iOS app exists, provider unregistered — no action until staging decision.)
- 🟡 Assessment-taking is P0-broken (missing server callables + owner behavior decision A/B) — must resolve before reviewer testing, else rejection on core flows.
- 🟡 Store assets (screenshots/description/keywords), Hosting domain, backup schedule, approval SLA, AR+EN comms templates: open per `13_Releases.md` §12.
