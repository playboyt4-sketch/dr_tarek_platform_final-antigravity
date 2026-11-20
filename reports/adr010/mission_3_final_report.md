# ADR-010 — Mission 3 Final Report

Date: 2026-11-12
Baseline: `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` · branch `ci/ios-staging-codemagic`
Production writes: **NONE** · Deployments: **NONE** · Bunny changes: **NONE** · Commits/pushes: **NONE**
Library `775315`: **still inactive** (no allow-list entry, not selectable, no credentials added)

## 1. Workstream status

| Workstream | Status | Evidence |
|---|---|---|
| A — Picker state in dialogs | **DONE (nonvisual)** | 3 authoring paths wired; 6 new widget tests; no visual change |
| B — Emulator suite in CI | **DONE (locally verified; GH run NOT RUN)** | new `adr010-emulator` job; identical command executed locally with exit 0 |
| C — Pre-write metadata validation | **PARTIAL** | pure validator + doctor-only callable + signed receipts + 33 tests; write-time enforcement needs deployment |
| Security review | **DONE** | `mission_3_security_review.md` |

## 2. Exact commands and results

| # | Command | Result |
|---|---|---|
| 1 | `cd functions && npm run build` | **PASS** |
| 2 | `npx eslint src/core/video src/scripts/backfill_bunny_library_id.ts` | **PASS** — 0 problems |
| 3 | `node test/bunny_library_registry.test.js` | **PASS** — 30 |
| 4 | `node test/bunny_library_migration.test.js` | **PASS** — 37 |
| 5 | `node test/bunny_playback_regression.test.js` | **PASS** — 33 |
| 6 | `node test/bunny_video_validation.test.js` | **PASS** — 26 |
| 7 | `firebase emulators:exec --project demo-tarek-platform --only auth,firestore,functions "node functions/test/issuance_library_flow.test.js && node functions/test/bunny_library_validation_flow.test.js"` | **PASS** — 11 + 7 assertions, exit 0 |
| 8 | `cd functions && npm test` (full roster, 49 files) | **46/49 PASS** — 3 pre-existing failures (below) |
| 9 | `python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` | **PASS** — `YAML_OK` |
| 10 | `node --check` on run_all + both new suites; JSON parse of package.json | **PASS** |
| 11 | `cd dashboard && flutter analyze <changed files>` | **PASS** — No issues found |
| 12 | `cd dashboard && flutter test` (8 relevant files incl. 6 new dialog tests) | **PASS** — 95 tests |
| 13 | Flutter app suites (unchanged this mission) | previously **PASS** (10); not re-run because no app file changed |

### The three failures in the full suite (not caused by ADR-010)

| Suite | Failure | Assessment |
|---|---|---|
| `test/protected_content.test.js` | `videoId must be a bare Bunny Video ID (GUID)` — the fixture uses `pcont-vid-V` | Test and guard are both unmodified at `HEAD`; the VIDEO-ID-ONLY guard already exists at `HEAD`. Pre-existing contract mismatch, untouched by ADR-010. |
| `test/playback_session.test.js` | same error, fixture `pbs-vid-A` | Same pre-existing cause. |
| `test/progress_percentage.test.js` | `Expected 50 total_lectures, got 0` | Test unmodified; the aggregation trigger path was not touched by ADR-010. Treated as pre-existing, **not** verified against a clean baseline (stashing was avoided to protect user work). |

No test was modified, skipped or weakened to hide these failures.

## 3. Files added / changed

Added:
- `functions/src/core/video/bunny_video_validation.ts`
- `functions/test/bunny_video_validation.test.js`
- `functions/test/issuance_library_flow.test.js`
- `functions/test/bunny_library_validation_flow.test.js`
- `dashboard/test/bunny_library_dialog_test.dart`
- `reports/adr010/picker_dialog_integration.md`, `firebase_emulator_ci.md`,
  `pre_write_metadata_validation.md`, `mission_3_security_review.md`,
  `mission_3_final_report.md`

Modified:
- `functions/src/index.ts` — imports, module re-export, `validateBunnyVideoAssociation`
  callable + 10-minute verdict cache + receipt issuing (no authorization edits).
- `functions/test/run_all.js`, `functions/package.json` — register the new suites.
- `.github/workflows/ci.yml` — new `adr010-emulator` job.
- `dashboard/lib/features/students/presentation/widgets/add_lecture_resources.dart` —
  selection state in the Video dialog + `libraryReviewRequired`.
- `dashboard/lib/features/students/presentation/widgets/add_lecture_overlay.dart` —
  selection state in add/edit paths.
- `dashboard/lib/features/home/presentation/widgets/quick_upload_modal.dart` — routed
  through `bunnyLibraryIdForCreate`.

Pre-existing user modifications remain intact; no file was reformatted or
line-ending-normalized.

## 4. Acceptance criteria

1. Picker state wired into dialogs — **yes** (nonvisual, tested).
2. Emulator CI prepared — **yes**; YAML valid and command locally green; GitHub run NOT RUN.
3. Pre-write validation — **server boundary yes**, persistence enforcement **blocked**
   (requires deployment/approved design), explicitly documented.
4. Production untouched, `775315` inactive, no deployment, no commit — **yes**.
5. Results reported with DONE/PARTIAL/BLOCKED/NOT RUN — **yes**.

## 5. Remaining blockers / next steps

1. **Write-time enforcement** — choose one: pre-save callable, server-side write callable
   that consumes the receipt, or a trigger guard. All need deployment authorization.
2. **Figma picker** — integration points and missing specs listed in
   `picker_dialog_integration.md`.
3. **CI verification** — the `adr010-emulator` job must run on GitHub once a push is
   authorized; local execution proves the command, not the runner.
4. **Pre-existing failures** — `protected_content`, `playback_session` fixtures need real
   GUIDs (separate, approved test-only change); `progress_percentage` aggregation needs
   its own investigation.
5. Owner actions unchanged: `775315` credentials, token auth, template, activation,
   `BUNNY_STREAM_API_KEY` → Secret Manager.
