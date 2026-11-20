# ADR-010 — Test Results

All commands were run locally on 2026-11-12 from the repository root unless a
working directory is stated. PASS below means the command was executed and exited 0.

## Backend

| # | Command | Result | Notes |
|---|---|---|---|
| 1 | `cd functions && npm run build` (tsc) | **PASS** | exit 0, no diagnostics |
| 2 | `cd functions && node test/bunny_library_registry.test.js` | **PASS** | 30 assertions, `bunny_library_registry tests passed (30).` |
| 3 | `cd functions && npx eslint src/core/video src/scripts/backfill_bunny_library_id.ts` | **PASS** | 0 problems (new files only) |
| 4 | `cd functions && npx eslint src/index.ts` | **FAIL (pre-existing)** | ~9 030 `linebreak-style` errors: the working copy uses CRLF, `HEAD` is LF, and the file already carried uncommitted user modifications. Not reformatted (would rewrite unrelated user work). |
| 5 | `cd functions && npm test` (emulator suite incl. 43 files) | **NOT RUN** | Requires Firestore/Auth/Functions emulators; not needed to validate the pure resolver, and not required for a local-only change. Existing suites that could be affected by the additive fields were not executed. |

## Flutter (student app)

| # | Command | Result |
|---|---|---|
| 6 | `flutter analyze <4 changed files> test/features/video_streaming/video_resource_library_test.dart` | **PASS** — `No issues found!` |
| 7 | `flutter test test/features/video_streaming/video_resource_library_test.dart` | **PASS** — 6/6 tests |

Covered: additive library parse, legacy payload, malformed metadata
(`''`, whitespace, `library-a`, `775315` as int, list) degrading to null, non-string
video id not throwing, `first_video` pointer library, legacy pointer.

## Dashboard

| # | Command | Result |
|---|---|---|
| 8 | `cd dashboard && flutter analyze <5 changed files> test/bunny_library_association_test.dart` | **PASS** — `No issues found!` |
| 9 | `cd dashboard && flutter test test/bunny_library_association_test.dart` | **PASS** — 12/12 tests |

Covered: normalization/rejection, new-video default library, explicit selection,
non-video ⇒ null, update-null keeps stored association, malformed ⇒ keep,
validation of valid/unknown/missing/non-video associations.

## Regression coverage — what is and is not proven

| Behaviour | Status |
|---|---|
| Default library resolution + signing env names | **PASS** (unit) — byte-identical var names |
| Legacy row → default library; switch to disable it | **PASS** (unit) |
| Unknown / unactivated / incomplete library fail closed | **PASS** (unit) |
| Client hint cannot switch credentials | **PASS** (unit) |
| Per-library template/key selection (`775315` when activated) | **PASS** (unit, synthetic env only — no real credentials) |
| Per-library metadata config, best-effort null | **PASS** (unit) |
| Backfill planner: set/unchanged/skip/conflict/idempotency | **PASS** (unit) |
| `first_video` projection carries the library | **PASS** (unit) |
| Flutter/Dashboard additive parsing + write contract | **PASS** (unit) |
| Guest preview, Free/Pro/Max entitlements, quality selection, device binding, takeover, heartbeat, PDF/external-link access, resource ordering | **NOT RUN** — code paths untouched; emulator/integration suites not executed |
| Real issuance against `775315` | **BLOCKED** — no credentials; library not activated |
| Dashboard create/edit against Firestore | **BLOCKED** — would be a production write |
| Migration script execution | **NOT RUN** by design (dry-run utility only) |
