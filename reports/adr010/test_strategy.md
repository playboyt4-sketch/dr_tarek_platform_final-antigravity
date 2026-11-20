# ADR-010 — Workstream G: Test Strategy

Date: 2026-11-12
Mode: PLAN ONLY — no test written or run in this workstream.

## 1. Existing coverage (inventory)

Bunny/video-related tests already present:

- `test/video_streaming/`: `video_resource_payload_test.dart`, `video_source_lecture_identity_test.dart`,
  `guest_preview_contract_test.dart`, `video_playback_controller_test.dart`, `first_video_startup_test.dart`,
  `first_video_selection_test.dart`, `video_direct_open_window_test.dart`, `video_watch_window_client_test.dart`,
  `lecture_documents_test.dart`, `preview_cap_policy_test.dart`.
- `test/features/lecture/lecture_remote_data_source_test.dart`
- `test/features/content_authoring/{lecture_access_test.dart, admin_content_repository_test.dart}`
- `dashboard/test/{lecture_publish_visibility_test.dart, first_video_writer_sync_test.dart, first_video_selection_test.dart, online_section_test.dart, home_quick_actions_test.dart}`
- Cloud Functions: `functions/test/run_all.js` (+ suites), `scripts/check_bunny_playback_signing.cjs` (manual diag)

**Gap:** zero coverage for library selection, per-library credentials, unknown/mismatched library, or
cross-zone behaviour.

## 2. Matrix

| # | Case | Type | Where | Expected |
|---|---|---|---|---|
| 1 | Library A (736742) playback | CF unit + emulator | `functions/test/` | signed URL uses 736742 template/key, 200 |
| 2 | Library B (775315) playback | CF unit + emulator | same | uses 775315 config, 200 |
| 3 | Two libraries in the same subject | CF unit + Flutter | both | each resource resolves its own config |
| 4 | Legacy resource without `bunny_library_id` | CF unit | resolver test | default library while flag on |
| 5 | Unknown library id in Firestore | CF unit | resolver test | `failed-precondition`, no URL |
| 6 | Mismatched library/video association | CF unit + CDN probe | resolver test | fail closed (or explicit 404 contract) |
| 7 | Video missing from selected library | CF integration | emulator + probe | clear error, never silent fallback |
| 8 | Wrong Pull Zone / wrong token key | CF unit | URL builder test | token built with the resource's zone key only |
| 9 | Poster/preview from the same library as playback | CF unit | `resolveVideoDisplayMedia` | identical resolved library |
| 10 | Preview restrictions (Guest minutes/zero) | CF unit (exists) | extend | unchanged |
| 11 | Subscription entitlements (video.access / quality) | CF unit (exists) | extend | unchanged |
| 12 | Device binding + takeover | CF unit + emulator (exists) | extend | unchanged |
| 13 | Resource serialization compatibility | CF unit + Dart test | both | old payload parses; new key optional |
| 14 | PDF / external-link resources unaffected | CF unit + Dart test | existing suites | `resource_url` unchanged |
| 15 | Archived/deleted lecture behavior | CF unit | **document current behavior only** (out of scope fix) | records the known gap |

## 3. Layers

**Unit (fast, no network)**
- `resolveLibraryForResource`: present/absent/unknown/mismatch/legacy-flag.
- `buildSignedPlaybackUrl`: per-library host + key + scope; no cross-library leakage.
- Cache key includes library id (poster cache).

**Cloud Functions tests**
- Extend `functions/test/run_all.js` with a `bunny_library_resolution` suite (pure functions imported).
- Assert the issuance path never reads the client hint for credential choice.

**Emulator integration**
- Seed two libraries in the registry, one resource each, assert `getLectureResources` emits
  `bunnyLibraryId` and issuance returns URLs on the matching hosts (assert hostname, not token).

**Dashboard tests**
- Create/update/quick-upload persists `bunny_library_id`; edit form round-trips it; legacy null shows
  "default".

**Flutter tests**
- `VideoResource.fromCallablePayload` parses/omits `bunnyLibraryId`; resolver forwards it when present;
  controller unaffected (regression run of `video_playback_controller_test.dart`).

**Manual staging**
- Real playback on iOS for one video per library; verify Referer/hotlink, HLS, resume, quality, and
  Guest preview. Two accounts, two libraries, subject isolation.

## 4. Non-negotiables

- No test may weaken authorization to pass.
- Tests must not call production `generateBunnySignedUrl`; use emulator/local functions.
- CDN probes may assert status codes only; never print tokens or URLs with signatures.
