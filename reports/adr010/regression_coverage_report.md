# ADR-010 — Regression Coverage Report (Mission 2, Workstream A)

Date: 2026-11-12
Baseline: `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` (unchanged; no commits)

## 1. Coverage that already existed (inspected, not duplicated)

| Area | Existing suite | What it already proves |
|---|---|---|
| Lecture identity / rolling window / Guest preview | `functions/test/issuance_lecture_matcher.test.js` | `matchIssuanceResource` outcomes, `decideVideoWatchWindow`, `resolveRollingWindowPolicy`, `resolveGuestPreviewSeconds` |
| First-video writer sync | `dashboard/test/first_video_writer_sync_test.dart` | `first_video` recompute after create/update/delete/reorder (FakeFirestore) |
| First-video selector | `dashboard/test/first_video_selection_test.dart` | eligibility + ordering + tie-break |
| Add-Lecture form | `dashboard/test/add_lecture_test.dart` | 24 widget/controller behaviours incl. resource flows |
| Quick upload | `dashboard/test/quick_upload_dialog_fixes_test.dart` | dialog validation/state |
| Library registry contract | `functions/test/bunny_library_registry.test.js` | resolution, activation, fallback switch, planner basics |

To avoid duplication, the new suites cover *different* surfaces (see below) rather than
re-asserting the same predicates.

## 2. Coverage added in this mission

### Backend — `functions/test/bunny_playback_regression.test.js` (33 assertions)
- Default library still resolved from the historical env names (playback **and** metadata).
- **No cross-library credential borrowing**: a default-library request never reads
  `BUNNY_775315_*` values; an inactive library is unreachable even when its credentials
  exist; failure never falls back sideways.
- `first_video` projection: lowest order wins, document-id tie-break, invisible /
  soft-deleted / empty-id / non-video rows ignored, null when none eligible, and the
  published key set (additive `bunny_library_id` included).
- `isServedLectureResource`, VIDEO-ID-ONLY `isValidBunnyVideoId`, and
  `normalizeBunnyVideoIdForLookup` (URLs are never extracted).
- Per-lecture deny semantics (`isLectureAccessDenied` incl. soft-deleted grants),
  `lectureAccessGrantId`, `documentFeatureKeys`, `isDocumentResourceType`.
- Window-over-tier denial precedence (`issuanceDenialPrecedence`).

### Backend — `functions/test/bunny_library_migration.test.js` (37 assertions)
See `migration_tool_hardening.md`: execution-mode guard, mapping validation,
planner decisions, stale-snapshot detection, backup/rollback metadata, idempotency.

### Flutter — `test/features/video_streaming/video_resource_library_test.dart` (6 tests)
Additive parse, legacy payload, malformed metadata (`''`, whitespace, non-numeric,
int, list) degrading to null, non-string video id not throwing, `FirstVideoRef`
library parse + legacy pointer.

### Dashboard — `dashboard/test/bunny_library_persistence_test.dart` (10 tests, FakeFirestore)
Real controller paths: new video persists the association, missing choice defaults to
the default library, malformed input never written verbatim, PDF/external-link rows carry
none, `getLectureForEdit` surfaces the stored value and reports legacy rows as null,
unrelated edit preserves the association, explicit update persists it, resource added
during an edit also gets an association.

### Dashboard — `dashboard/test/bunny_library_association_test.dart` (12 tests)
Write contract of `bunnyLibraryIdForCreate` / `ForUpdate` / validation.

### Dashboard — `dashboard/test/bunny_library_selection_test.dart` (20 tests)
Picker scaffolding state: catalog availability/selectability, validation, legacy state,
Video-ID-change review flag, edit preservation, quick-upload defaulting, serialization.

## 3. Commands and actual results

| # | Command | Result |
|---|---|---|
| 1 | `cd functions && npm run build` | **PASS** |
| 2 | `node test/bunny_library_registry.test.js` | **PASS** — 30 assertions |
| 3 | `node test/bunny_library_migration.test.js` | **PASS** — 37 assertions |
| 4 | `node test/bunny_playback_regression.test.js` | **PASS** — 33 assertions |
| 5 | `cd dashboard && flutter test test/first_video_selection_test.dart test/first_video_writer_sync_test.dart test/add_lecture_test.dart test/quick_upload_dialog_fixes_test.dart test/bunny_library_association_test.dart test/bunny_library_persistence_test.dart test/bunny_library_selection_test.dart` | **PASS** — `+89: All tests passed!` |
| 6 | `flutter test test/features/video_streaming test/lecture_viewer/lecture_viewer_smoke_test.dart test/features/lecture/lecture_remote_data_source_test.dart` | **PASS** — `+10: All tests passed!` |
| 7 | `cd functions && npm test` (emulator suite, 45 files) | **NOT RUN** — requires Firestore/Auth/Functions emulators; not started in this environment |
| 8 | Full `dashboard/test` folder (40 files) | **NOT RUN** — 7 relevant files were run (89 tests); the rest are unrelated features |

## 4. Authorization regression status

Authorization/idempotency logic was **not modified** in this mission. The pure
predicates it is built on were asserted (deny semantics, document feature keys,
VIDEO-ID-ONLY validation, window precedence) and the previously existing suites
(`issuance_lecture_matcher`, `first_video_writer_sync`) still pass. End-to-end
callable authorization (subscription/Feature Matrix/device tier/takeover) remains
**NOT RUN** because it needs the emulator suite.

## 5. Remaining gaps

1. `generateBunnySignedUrl` end-to-end (real callable + emulator) — NOT RUN.
2. `resolveVideoDisplayMedia` / `fetchBunnyVideoMeta` network paths — tested only through
   the pure library-selection layer; no HTTP fixture.
3. Real `775315` playback — BLOCKED (no credentials, library inactive).
4. Player-level Flutter regression (controller lifecycle, cache renewal, takeover) —
   NOT RUN; only parsing/fast-lane-pointer contracts plus the existing lecture-viewer
   smoke test ran.
5. Dashboard picker interaction — BLOCKED (no Figma); state model tested instead.
