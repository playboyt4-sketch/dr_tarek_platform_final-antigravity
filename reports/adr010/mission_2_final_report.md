# ADR-010 — Mission 2 Final Report

Date: 2026-11-12
Baseline: `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` · branch `ci/ios-staging-codemagic`
Production changes: **NONE** · Deployments: **NONE** · Commits/pushes: **NONE**

## Status per workstream

| Workstream | Status |
|---|---|
| A — Regression coverage | **DONE (targeted)** — 3 new backend suites (100 assertions total), 2 new Dashboard suites (32 tests), 1 Flutter suite (6 tests); 89 dashboard + 10 Flutter existing/new tests pass. Emulator suite NOT RUN. |
| B — Migration dry-run hardening | **DONE** — write capability deleted, apply refused pre-connection, richer validation, concurrency evaluator, backup builder; 37 assertions |
| C — Dashboard picker scaffolding | **PARTIAL** — catalog + selection state + integration map complete and tested; visual selector BLOCKED on Figma |
| Cross-workstream security review | **DONE** — see `security_regression_review.md` |
| Validation (T8-style) | **PASS for what ran**; emulator + full-folder suites NOT RUN |

## Exact commands and results

| Command | Result |
|---|---|
| `cd functions && npm run build` | **PASS** |
| `npx eslint src/core/video src/scripts/backfill_bunny_library_id.ts` | **PASS** — 0 errors, 0 warnings |
| `node test/bunny_library_registry.test.js` | **PASS** — 30 assertions |
| `node test/bunny_library_migration.test.js` | **PASS** — 37 assertions |
| `node test/bunny_playback_regression.test.js` | **PASS** — 33 assertions |
| `node lib/scripts/backfill_bunny_library_id.js` | exit 1, `--mapping … required` (no connection) |
| `node lib/scripts/backfill_bunny_library_id.js --mapping package.json --apply` | exit 3, refused (no connection) |
| `cd dashboard && flutter analyze <changed files + new tests>` | **PASS** — No issues found |
| `flutter test` (7 dashboard files: first_video_selection, first_video_writer_sync, add_lecture, quick_upload, bunny association/persistence/selection) | **PASS** — +89 |
| `flutter test test/features/video_streaming test/lecture_viewer/… test/features/lecture/…` | **PASS** — +10 |
| `cd functions && npm test` (emulator, 45 files) | **NOT RUN** |
| Full `dashboard/test` (40 files) | **NOT RUN** (7 relevant files run) |
| `npx eslint src/index.ts` | **FAIL (pre-existing)** — CRLF vs LF linebreak-style on the user-modified working copy; not reformatted |

## Files added / changed in Mission 2

Added:
- `functions/test/bunny_library_migration.test.js`
- `functions/test/bunny_playback_regression.test.js`
- `dashboard/test/bunny_library_persistence_test.dart`
- `dashboard/test/bunny_library_selection_test.dart`
- `dashboard/lib/features/students/domain/bunny_library_catalog.dart`
- `reports/adr010/regression_coverage_report.md`, `migration_tool_hardening.md`,
  `dashboard_picker_scaffolding.md`, `security_regression_review.md`,
  `mission_2_final_report.md`

Rewritten (Mission 1 files, hardened):
- `functions/src/core/video/bunny_library_migration.ts` — validation, actions,
  execution guard, concurrency evaluator, backup builder.
- `functions/src/scripts/backfill_bunny_library_id.ts` — read-only CLI, pre-connection
  apply refusal, structured report.

Touched (minimal, additive):
- `functions/src/core/video/bunny_library_registry.ts` — `bunnyPosterCacheKey`.
- `functions/src/index.ts` — import + use of `bunnyPosterCacheKey` (2 lines).
- `functions/test/run_all.js`, `functions/package.json` — register the two new suites.

Pre-existing user modifications (dashboard applications/students/home files,
`functions/src/index.ts` body, `live_student.dart`, `acceptance_notification.test.js`)
remain intact; nothing was reverted, reformatted or line-ending-normalized.

## Acceptance criteria

1. Regression coverage materially expanded — **yes** (100 backend assertions, 32 new
   dashboard tests, 6 Flutter tests, plus 89/10 passing suites).
2. Dry-run tooling stronger and write-incapable — **yes**, verified by execution.
3. Picker nonvisual scaffolding ready — **yes** (catalog + selection + integration map).
4. Backward compatibility — **yes**: default library env names unchanged, legacy rows
   resolve as before, additive fields only, no authorization edits.
5. Tests actually run and reported — **yes**, with NOT RUN items listed explicitly.
6. No production data/config change — **yes**.
7. No deployment — **yes**.
8. Existing user changes intact — **yes**.

## Recommended next steps

1. Dashboard picker UI once Figma is approved (state model is ready).
2. Emulator run of the full backend suite in CI (needs the Firebase emulators).
3. Owner actions B1–B5 (775315 credentials, token auth, template, activation, secret
   migration) before any `775315` playback.
