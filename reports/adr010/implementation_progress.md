# ADR-010 — Implementation Progress

Date: 2026-11-12
Baseline commit: `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` (branch `ci/ios-staging-codemagic`)
Posture: local-only. No production write, no deployment, no secret creation, no Bunny change.

## Task status

| Task | Status | Summary |
|---|---|---|
| T1 — Schema + pure resolver | **DONE** | Nullable `bunny_library_id` in all four layers; pure registry/resolver with fail-closed behaviour; 30 backend assertions + 12 dashboard + 6 Flutter tests |
| T2 — Backend library configuration architecture | **DONE (architecture only, second library NOT activated)** | One centralized resolution path; default library behaviour byte-identical; `775315` defined but inert |
| T3 — Serialization and listing | **DONE** | `bunnyLibraryId` additive in `getLectureResources`; `first_video` projection carries the library additively |
| T4 — Dashboard data layer | **PARTIAL (data layer DONE, UI BLOCKED)** | Models, staging, create/update writes, legacy handling and validation done; no picker rendered (Figma gate) |
| T5 — Flutter integration | **DONE** | Tolerant additive parse, hint-only payload field, fast-lane pointer; player/device/window/quality untouched |
| T6 — Migration tool | **DONE (dry-run utility, never executed)** | Pure planner + CLI with backup, optimistic concurrency, per-resource results, idempotency, rollback source |
| T7 — Automated testing | **PARTIAL** | New pure suites pass; the emulator/dashboard/flow suites were not run (see `test_results.md`) |
| T8 — Validation | **PARTIAL** | Backend build + lint (new files) + pure tests, Flutter analyze/tests, Dashboard analyze/tests ran; emulator suite NOT RUN |

## What changed architecturally

1. **One trusted resolution path.** `resolveBunnyLibraryForResource` →
   `resolveBunnyPlaybackRuntime` / `resolveBunnyStreamApiRuntime`. It takes an env
   snapshot, so it is pure and unit-testable, and it never reads `process.env` itself.
2. **Fail closed, never fall back sideways.** Unknown id → `unknown_library`;
   defined-but-not-activated id → `library_not_activated`; missing env values →
   `incomplete_configuration`; client hint disagreeing with the stored value →
   `library_mismatch`.
3. **Legacy rows keep today's behaviour** by resolving to the default library
   (`736742`), whose env var names are exactly the existing
   `BUNNY_PLAYBACK_URL_TEMPLATE` / `BUNNY_TOKEN_KEY` / `BUNNY_STREAM_API_KEY` /
   `BUNNY_STREAM_LIBRARY_ID`. Behaviour can be frozen post-migration with
   `BUNNY_LEGACY_LIBRARY_FALLBACK=false`.
4. **Second library is inert by construction.** `775315` needs both an
   explicit `BUNNY_ACTIVE_LIBRARY_IDS` entry and its own four env values;
   neither exists, so every attempt fails closed with `library_not_activated`.
5. **Display media cannot diverge from playback.** Poster/preview resolution
   goes through the same registry; an unresolvable library yields no
   Bunny-derived media instead of another zone's poster. Poster cache keys are
   now `libraryId:videoId`.
6. **No new secrets, no placeholder secrets.** The registry stores env var
   *names* only. Nothing was added to Secret Manager and no value is logged,
   returned, or written to Firestore.

## Deliberate non-changes

- `resource_url` untouched.
- No change to authentication, per-lecture deny, subject access, subscription,
  Feature Matrix, device binding, takeover, playback windows, or quality logic.
- Archived/deleted lecture issuance gap **not** touched (out of ADR-010 scope).
- The seven placeholder video resources (empty `bunny_video_id`) are skipped by
  the planner.
- `docs/notion` naming inconsistency (`generateSignedVideoUrl`) untouched.
