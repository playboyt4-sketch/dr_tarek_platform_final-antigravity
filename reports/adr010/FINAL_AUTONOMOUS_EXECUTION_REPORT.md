# ADR-010 — Final Autonomous Execution Report

Date: 2026-11-12
Baseline: `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` · branch `ci/ios-staging-codemagic`
Scope executed: T1 → T2 → T3 → T4 (data layer) → T5 → T7 → T8, plus T6 preparation.
**Production changes: NONE. Deployments: NONE. Secrets created: NONE. Commits: NONE.**

## 1. Final status per task

| Task | Status | Evidence |
|---|---|---|
| T1 — Schema + pure resolver | **DONE** | `bunny_library_registry.ts`; nullable field in Dashboard/Flutter/backend/`first_video`; 30 + 12 + 6 tests pass |
| T2 — Backend configuration architecture | **DONE** | single resolution path in `index.ts`; default library unchanged; `775315` inert |
| T3 — Serialization & listing | **DONE** | additive `bunnyLibraryId`; `first_video.bunny_library_id`; no key removed or repurposed |
| T4 — Dashboard data layer | **PARTIAL** | data layer complete; picker UI blocked (no Figma) |
| T5 — Flutter integration | **DONE** | tolerant parse, hint-only request field, fast lane, no player/security change |
| T6 — Migration tool | **DONE (never executed)** | pure planner + CLI with dry-run, backup, `lastUpdateTime` preconditions |
| T7 — Automated testing | **PARTIAL** | targeted suites added and green; emulator/integration suites not run |
| T8 — Validation | **PARTIAL** | build, targeted lint, analyses and unit tests run; full suites not run |

## 2. Security review

- No secret value appears in any changed or new file (pattern scan clean); the registry
  stores env var **names** only.
- No new `defineSecret` entries were added, so an undeployable secret reference cannot
  be introduced. `775315` activation therefore requires an explicit allow-list entry
  plus its four env values — both deliberate operator actions.
- `generateBunnySignedUrl` still enforces every existing gate (auth, user existence,
  resource identity, lecture identity, subject access, active subscription, Feature
  Matrix, per-lecture deny, device tier, rolling window, quality, sessions) **before**
  library resolution; the only new failure is a config failure, and error precedence
  for existing denials is unchanged.
- A client-supplied `libraryId` cannot select credentials: mismatch ⇒
  `failed-precondition`; on a legacy row the hint is ignored.
- Display media resolves through the same library as playback, so a poster can never
  be signed for a different library's zone than the playback URL.
- Archived/deleted-lecture issuance gap remains untouched (out of scope, reported).

## 3. Compatibility statement

With no `bunny_library_id` stored anywhere (today's production state), every code path
resolves the default library `736742` and reads exactly the same env var names as
before (`BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_TOKEN_KEY`, `BUNNY_STREAM_API_KEY`,
`BUNNY_STREAM_LIBRARY_ID`). Signing scheme, expiry, URL shape, response keys, listing
keys, ordering and first-video selection are unchanged. `first_video` gains one
additive key that all consumers ignore unless they read it.

## 4. Migration readiness

- Planner + CLI ready; mapping file is explicit and validated; conflicts refuse the run.
- Blocked on a complete verified mapping (6 known Video IDs mapped; 7 rows have no
  Video ID and are skipped by design) and on B1–B3 credentials before `775315` may be
  activated.
- Recommended sequence: bind secrets → activate `775315` → dry-run plan → owner review
  of the plan/backup → apply → re-run plan (expect all `unchanged`) → validate playback
  → only then set `BUNNY_LEGACY_LIBRARY_FALLBACK=false`.

## 5. Recommended next implementation task

**Dashboard library picker (T4 UI)** once the Figma spec exists — it is the only
remaining piece that requires no production write and no new credentials. Until then,
the second unblocked option is extending the verified mapping for the 7 placeholder
resources (content decision, not engineering).
