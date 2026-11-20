# ADR-010 — Workstream H: Implementation Roadmap

Date: 2026-11-12
Mode: PLAN ONLY — no task executed, nothing deployed.

Legend for status: **UNBLOCKED** = can be implemented now after review; **BLOCKED-CRED** = needs library
credentials; **BLOCKED-MAP** = needs a verified mapping/decision; **BLOCKED-DESIGN** = needs Figma;
**APPROVAL** = needs explicit Platform Owner approval.

## A. Unblocked after readiness review

| ID | Task | Files | Depends on | Risk | Tests | Rollback |
|---|---|---|---|---|---|---|
| T1 | Add nullable `bunny_library_id` to models (Dart + Dashboard) — parsing/writing tolerant | `playback_entities.dart`, `admin_content_entities.dart`, `subject_details_provider.dart` | — | L | payload/round-trip tests | revert commit; field unused |
| T2 | Pure library registry resolver + signed URL builder (no wiring) | new `functions/src/bunny/library_registry.ts` | T1 types | M | unit suite | revert commit |
| T3 | Wire resolver into `generateBunnySignedUrl` with default fallback + fail-closed + migration flag | `functions/src/index.ts` (4272–4725) | T2 | H | CF unit + emulator | flag off + revert |
| T4 | Wire resolver into `resolveVideoDisplayMedia` / `fetchBunnyVideoMeta` / `buildBunnyFileUrl`; cache key includes library | `functions/src/index.ts` (1559–1734) | T2 | H | CF unit | revert |
| T5 | `getLectureResources` emits `bunnyLibraryId` (additive) | `index.ts:4988–5002` | T1 | L | payload tests | revert |
| T6 | Dry-run backfill script (read-only) + backup/rollback tooling | new `scripts/adr010/*` | T1 | M | dry-run on prod read-only | script not run |
| T7 | Test suites per matrix (unit + emulator) | `functions/test/`, `test/`, `dashboard/test/` | T2–T5 | M | self | revert |

## B. Blocked by missing credentials

| ID | Task | Blocker |
|---|---|---|
| T8 | Configure library `775315` (template + token key + Stream API key) | secrets must be created by the Owner in Secret Manager; token auth decision for that zone |
| T9 | Enable/verify token authentication on `775315` Pull Zone | Bunny setting change; requires Owner approval + key |
| T10 | End-to-end playback verification against `775315` (staging) | T8 + T9 |
| T11 | Move `BUNNY_STREAM_API_KEY` into Secret Manager (currently a plain env var) | Owner action on the deployed function config |

## C. Blocked by missing resource mapping

| ID | Task | Blocker |
|---|---|---|
| T12 | Backfill `bunny_library_id` for the 6 verified rows | T8/T3 (safe once defaults exist) — mapping already verified |
| T13 | Resolve the 7 empty-Video-ID resources | content decision (delete/ignore/fill) — not ADR-010 |
| T14 | Verify remaining/ future video resources (none today beyond the 6) | new uploads must capture library at authoring time (T15) |

## D. Blocked by missing Figma design

| ID | Task | Blocker |
|---|---|---|
| T15 | Dashboard library selector UI | no approved design/spec for the control; data layer (T1) can proceed first |

## E. Requires separate Platform Owner approval

| ID | Task | Why |
|---|---|---|
| T16 | Fix archived/deleted lecture issuance gap | explicitly out of ADR-010 scope |
| T17 | Cleanup of duplicate Video ID / empty rows | data change outside ADR-010 |
| T18 | Remove legacy default fallback | only after full backfill validation (ADR-010 step 8) |
| T19 | Deployment of functions/hosting | implementation gate |

## Suggested order

`T1 → T2 → T3 → T4 → T5 → T7 → (Owner: T8/T9/T11) → T15/T12 → T10 → T18 → T19`

T3/T4 can be merged behind the migration flag so production behavior is byte-identical until the flag is
enabled.
