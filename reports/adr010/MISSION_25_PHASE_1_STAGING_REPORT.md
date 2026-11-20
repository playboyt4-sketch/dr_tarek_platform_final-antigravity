# Mission 25 — Phase 1 (Staging) Report

**Date:** 2026-11-19
**Scope:** Staging only. Production was not modified in this phase.
**Status:** `COMPLETE — awaiting Phase 2 (ADR Amendment 3) approval`

No secret value appears here; secret names only.

---

## 1. Code changes (Phase 1.1 — Decision 4)

| File | Change |
| --- | --- |
| `functions/src/core/video/bunny_library_catalog.ts` | new `BunnyTokenAuthMode = "signed" \| "unsigned"`; `BunnyCatalogEntry.tokenAuthMode`; `token_auth_mode` parsing (`unknown_token_auth_mode` is a hard failure); new `bunnyCatalogTokenAuthMode()`; `isBunnyCatalogEntryUsable()` is now mode-aware (active + probe-verified + stored flag agrees with the mode) |
| `functions/src/core/video/bunny_library_lifecycle.ts` | registration writes `token_auth_mode: null`; verification outcome accepts the probed mode; `planBunnyLibraryVerificationWrite()` activates on a **proved** `signed` **or** `unsigned` outcome and writes `token_auth_mode`; new pure `bunnyProbeFailureReasonForStatus()` (200 → none, 404 → `library_not_found`, 401/403 → `credential_rejected`, else `video_list_unavailable`) |
| `functions/src/index.ts` | `verifyBunnyLibrary`: removed `GET video.bunnycdn.com/library/{id}` entirely; token key is now optional (unsigned libraries have none); probes `signed` first, then `unsigned`; writes `token_auth_mode`; audit row records the new status. `probeBunnyLibraryPlayback` now sends the platform Referer. New `probeBunnyLibraryUnsignedPlayback` and shared `findBunnyProbeVideo`. `listBunnyLibraryHealth` projects `tokenAuthMode` |
| `functions/test/bunny_library_verify_modes.test.js` | **new**, 40 assertions: enforced tokens, not-enforced tokens, failed signature, unknown library, catalog mode trust rules, registration declares no mode |
| `functions/package.json`, `functions/test/run_all.js` | the new suite registered in `test:pure` and the aggregate runner |

Behaviour preserved: the signed path, all fail-closed branches, the audit payload shape, and every
pre-existing assertion. `npm run build` (tsc) → **exit 0**. Lint on the touched files: **0 new errors**
(the 17 pre-existing `src/index.ts` findings and 4 in the catalog module are untouched lines; the repository
still reports ~10k `linebreak-style` errors from a CRLF checkout, unrelated to this change).

### Tests

| Suite | Result |
| --- | --- |
| `bunny_library_verify_modes` (new) | **40/40** |
| `bunny_library_lifecycle` | 77 assertions, exit 0 |
| `bunny_library_catalog` | 26 checks, exit 0 |
| `bunny_library_catalog_reader` | 30 checks, exit 0 |
| `bunny_library_registry` | exit 0 |
| `bunny_library_migration` | 37 tests, exit 0 |
| `bunny_playback_regression` | 33 tests, exit 0 |
| `bunny_library_association` | 37 assertions, exit 0 |

## 2. Staging secrets (Phase 1.2)

| Secret | Action |
| --- | --- |
| `BUNNY_780700_STREAM_API_KEY` | pre-existing (v1) — untouched |
| `BUNNY_780700_TOKEN_KEY` | pre-existing (v1) — untouched |
| `BUNNY_775315_STREAM_API_KEY` | **created** (v1) from the reviewed source file; `roles/secretmanager.secretAccessor` granted to `13159003436-compute@…` |
| `BUNNY_775315_TOKEN_KEY` | **deliberately not created** — 775315 is unsigned and has no token key |

No production secret was created or read.

## 3. Staging catalog (Phase 1.3)

The hand-written `bunny_libraries/780700` row (no `created_at`, no audit trail, manually-set
`token_auth_verified`) was backed up and replaced through the audited path:

1. backup → `D:\Temp\opencode\backups\adr010\20261119T122913Z\staging_bunny_libraries_before.json`
2. `registerBunnyLibrary(780700)` → `pending_verification`
3. `verifyBunnyLibrary(780700)` → `active`, mode **signed**
4. `registerBunnyLibrary(775315)` → `pending_verification`
5. `verifyBunnyLibrary(775315)` → `active`, mode **unsigned**

Results (callable responses, no URLs and no keys):

| Library | status | tokenAuthEnabled | tokenAuthVerified | tokenAuthMode |
| --- | --- | --- | --- | --- |
| 780700 | active | true | true | **signed** |
| 775315 | active | false | true | **unsigned** |

`listBunnyLibraryHealth` returns both rows with their mode; `listEligibleBunnyLibraries` returns both
`{libraryId, displayName}` pairs. Both documents now carry `created_at`, `updated_at`,
`token_auth_mode` and a real verification timestamp, and `admin_audit_log` holds 4 entries
(`bunny_library_register` ×2, `bunny_library_verify` ×2) with actor, permission basis and status transition.

Staging env now allows both libraries: `BUNNY_ACTIVE_LIBRARY_IDS=780700,775315` (in
`functions/.env.dr-tarek-staging`; functions deployed with this value: the six lifecycle callables — other
Staging functions still carry the previous value until their next deployment, which this phase does not require).

## 4. Deployment

`firebase deploy --only functions:registerBunnyLibrary,verifyBunnyLibrary,deactivateBunnyLibrary,reactivateBunnyLibrary,listBunnyLibraryHealth,listEligibleBunnyLibraries -P staging` → **Deploy complete**, 6 successful updates, `us-central1`, Node.js 24. No other function was touched.

## 5. IAM (Phase 1.5)

| Moment | Staging service-account policy |
| --- | --- |
| Phase 0 | empty (no bindings on any SA) — the binding the previous engineer disclosed **does not exist** |
| During Phase 1 | `roles/iam.serviceAccountTokenCreator` granted to `user:playboyt4@yahoo.com` on `13159003436-compute@…` for **≈2 minutes**, only to mint a doctor ID token for the two verification calls (propagation required ~100 s) |
| After Phase 1 | **removed** — policy returned to `{"etag":…,"version":1}` with **no bindings** (a stray self-binding produced by the grant/revoke cycle was removed too) |

Final state confirmed by name: no `user:` and no `serviceAccount:` binding on
`13159003436-compute@developer.gserviceaccount.com`.

## 6. Temporary secret files (Phase 1.5)

`D:\Temp\opencode\bunny_secrets\` held 11 files (8 credential files + 3 probe artefacts). All were deleted,
the directory verified empty and then removed. A scan of `D:\Temp\opencode` for key-shaped strings and
`AccessKey` payloads returns **no credential material** (only source files that contain the header name).

## 7. Production impact

None: production catalog is still empty, production functions were not deployed, `BUNNY_ACTIVE_LIBRARY_IDS`
is unset in production, and no Bunny object was written (all Bunny access in this phase was read-only).

## 8. Open items for the Owner

1. **Phase 2 approval** — `21_ADR_010_Amendment_3.md` is not written yet; it is the next gate.
2. **Referer decision (Decision 3)**: gate passes — unsigned playback returns 200 with the platform Referer
   and 403 without it. No Bunny change is needed; the client already sends the header.
3. Note for Phase 4: 775315 and 776525 will need `BUNNY_<id>_STREAM_API_KEY` in production only (no token
   key). The credential files deleted here can be re-read from the Bunny dashboard at that time.
