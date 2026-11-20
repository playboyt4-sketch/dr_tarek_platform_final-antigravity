# ADR-010 — Mission 23 Final Report: Production Security Remediation & Closure

**Date:** 2026-11-17
**Project:** `dr-tarek-platform` / project number `606744934510` / `us-central1`
**Branch / HEAD:** `ci/ios-staging-codemagic` / `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` (unchanged; no commits, no reset/stash/clean)
**Owner-selected target:** **Option 1** — ADR-010 code with the canonical legacy-default path for library `736742`, **no** `bunny_libraries` catalog document, **no** per-library secrets.
**Classification:** `PARTIALLY CLOSED — SPECIFIC NON-CRITICAL ITEMS REMAIN` (§20)

No secret value, partial value, fingerprint or secret-shaped token appears in this report. Secrets are
referred to by name, version number, state and length class only.

---

## 1. Executive summary

The Mission 21 Production findings are remediated:

| Finding (Mission 21) | Final state |
| --- | --- |
| Bunny Stream API key in plaintext on 79 functions | **removed** — `0` functions carry it (was `79/79`); the six credential-consuming callables now mount it from Secret Manager |
| Malformed `APP_CHECK_ENFORCEMENT` (97-char blob) on 79 functions | **removed** — `83/83` functions now carry the explicit literal `false`; `0` malformed values |
| Production had no `BUNNY_STREAM_API_KEY` secret | **created**, version `1` `enabled`, per-secret IAM scoped to the runtime SA |
| Potentially exposed key still valid at Bunny | **rotated** — new key `200`, old key `401` |
| Plaintext key in local `functions/.env` | **removed**; file now holds only `APP_CHECK_ENFORCEMENT=false` and `BUNNY_STREAM_LIBRARY_ID=736742` |
| Production ran pre-ADR-010 code | **deployed**: 79 functions updated, 4 created, 83 total, 0 deleted |

Verification evidence: 83/83 function configuration inspected live, 6/6 callables return `401`
unauthenticated, full Functions suite `56/56` files passed on the emulator, `tsc` build `0`, `npm run
test:pure` `0`.

Not executed (and therefore not claimed): live student/doctor playback smoke with real accounts (§15),
App Check enforcement (`false` by decision, §13), and client-side App Check readiness (§18).

---

## 2. Original Mission 21 risks and their disposition

| ID | Risk | Severity then | Final status |
| --- | --- | --- | --- |
| R-1 | Stream API key plaintext in function metadata (79 × 2 copies) | High | **Closed** — key rotated; plaintext env gone from all functions; first copy no longer exists because the value is dead |
| R-2 | App Check enforcement effectively off on all callables | Medium | **Configuration closed; behaviour intentionally unchanged** (`false`, explicit, §13) |
| R-3 | Corrupted boolean silently disabling enforcement | Medium | **Closed for detection** — Mission 22 parser + boot warning now surface it; value itself is clean |
| R-4 | `.env` shipped in deploy pipeline / source archive | Medium | **Closed** — `.env*` in `firebase.json` ignore; key absent from `.env` |
| R-5 | Missing `BUNNY_STREAM_API_KEY` secret = release blocker | High | **Closed** — secret version 1 enabled, mounted by 6 functions |
| R-6 | Production on pre-ADR-010 code | Low/Med | **Closed** — ADR-010 deployed |
| R-7 | `roles/editor` on runtime SA | Low | **Unchanged** (standard Firebase default; grants no secret payload access) |
| R-8 | Exposed key possibly still live at Bunny | High if live | **Closed** — old key returns `401` (§6) |

---

## 3. Mission 22 implementation verification (re-checked on disk, not taken from the report)

| Claim | Verified |
| --- | --- |
| `describeAppCheckEnforcement()` with `enforced` / `disabled` / `malformed` | **yes** |
| Only exact `"true"` enables enforcement | **yes** |
| `"false"` recognised; absent/empty treated as disabled | **yes** |
| Malformed state exposes only `rawLength` | **yes** |
| Boot warning guarded by `NODE_ENV !== "test"` | **yes** |
| `.env*` in `functions[0].ignore` | **yes** |
| New suite wired into `test:pure` | **yes** |
| ESLint on `security_helpers.ts` | **0 errors / 0 warnings** |
| ESLint on `index.ts` | **fails repo-wide**: 9,658 errors of which 9,641 are `linebreak-style` (whole file stored CRLF, pre-existing) plus 17 pre-existing code errors and 19 warnings. Documented, not "fixed" (out of scope; would rewrite the file). |

---

## 4. Phase 0 baseline (revalidated at the start of this mission)

79 deployed functions; `APP_CHECK_ENFORCEMENT` malformed on **79/79**; plaintext `BUNNY_STREAM_API_KEY` on
**79/79**; no `BUNNY_STREAM_API_KEY` secret; 5 Bunny secrets with per-secret IAM; no project-level Secret
Manager role; `bunny_libraries` empty; Git 33 modified + 33 untracked.

---

## 5. Gate A execution evidence (details: `MISSION_23_PHASE_A_GATE_A_REPORT.md`)

| Step | Evidence |
| --- | --- |
| Rotation mechanism | Dashboard library page has **no** rotate control; used the documented account-API reset endpoint from inside the authenticated dashboard session |
| `POST /videolibrary/736742/resetApiKey` | **204** |
| `GET /videolibrary/736742` (id check) | **200**, `Id = 736742` |
| Secret `BUNNY_STREAM_API_KEY` created | `projects/606744934510/secrets/BUNNY_STREAM_API_KEY`, labels `adr=adr010`, `mission=mission23` |
| Version | `1` — `enabled` — `2026-11-17T11:29:54` |
| Payload handling | written only via `gcloud secrets versions add --data-file=-` on **stdin**; never read back |
| Per-secret IAM | `roles/secretmanager.secretAccessor` → exactly `serviceAccount:606744934510-compute@developer.gserviceaccount.com` |
| Project-level Secret Manager roles | **none** |
| Local `.env` | `APP_CHECK_ENFORCEMENT=false` + `BUNNY_STREAM_LIBRARY_ID=736742`; no key; still Git-ignored |

Owner action outstanding (security hygiene, not a blocker): the account API key that was pasted into chat
earlier should be refreshed at `Account → API key`. The value used for the reset was read from the live
dashboard field, not from that paste.

---

## 6. Bunny key rotation verification

| Credential | Endpoint | Result |
| --- | --- | --- |
| New library key | `GET video.bunnycdn.com/library/736742/videos?pageSize=1` | **200** |
| Old library key (from the pre-scrub `.env`) | same | **401** (revoked) |
| New library key | `GET api.bunny.net/videolibrary/736742` | **401** (proves library scope, not account scope) |
| Library identity | response `Id` | `736742` |

Recorded deviation: an in-page probe of the new key returned `401` (cross-origin artifact); the CLI probe is
authoritative and returned `200`.

---

## 7. Secret Manager configuration (Production)

| Secret | Versions | Mounted by |
| --- | --- | --- |
| `BUNNY_STREAM_API_KEY` | 1 (enabled, 2026-11-17) | 6 callables |
| `BUNNY_TOKEN_KEY` | 3 (enabled) | 8 functions |
| `BUNNY_PLAYBACK_URL_TEMPLATE` | 2 (enabled) | 3 functions |
| `BUNNY_STORAGE_BASE_URL` | 1 (enabled) | 5 functions |
| `BUNNY_STORAGE_ZONE_NAME` | 1 (enabled) | 2 functions |
| `BUNNY_STORAGE_PASSWORD` | 1 (enabled) | 2 functions |

No per-library secrets were created (`BUNNY_736742_*` absent by design — Option 1). No payload was read.

## 8. IAM verification

- Runtime SA: `606744934510-compute@developer.gserviceaccount.com`.
- Secret access: per-secret `roles/secretmanager.secretAccessor` only, on the six Bunny secrets including the new one.
- No `roles/secretmanager.admin` / `secretAccessor` at project level.
- No unrelated IAM change.

---

## 9. Local `.env` cleanup

| | Before | After |
| --- | --- | --- |
| `APP_CHECK_ENFORCEMENT` | 97-char concatenation containing a key | `false` |
| `BUNNY_STREAM_API_KEY` | present inside that blob | **absent** |
| `BUNNY_STREAM_LIBRARY_ID` | `736742` | `736742` |
| New key in `.env` | — | **not present** (Secret Manager only) |

---

## 10. Deployment approval and execution

- Scope approved: Option 1 (no catalog document, no per-library secrets, `APP_CHECK_ENFORCEMENT=false`).
- Command: `firebase deploy --only functions --project dr-tarek-platform --non-interactive` (CLI 15.24.0, alias `default` → `dr-tarek-platform`).
- Predeploy `npm run build` ran inside the deploy.
- Transient `429 Per project mutation requests per minute` responses from the Cloud Functions API were retried by the CLI; every function ended in a successful operation.
- Result: **`Deploy complete!`**, `DEPLOY_EXIT=0`, **79 successful updates + 4 successful creates**, **0 deletions**.

## 11. Deployment manifest

Machine-readable: `reports/adr010/mission_23_deployment_manifest.csv` (83 rows: function, trigger, secret
mounts, action).

| Group | Count |
| --- | --- |
| Source function exports | 83 |
| Updated | 79 |
| Created | 4 — `associateBunnyVideoToLibrary`, `listEligibleBunnyLibraries`, `validateBunnyVideoAssociation`, `getAssessmentQuestions` |
| Deleted | 0 |
| Functions with secret mounts | 8 |
| Functions mounting `BUNNY_STREAM_API_KEY` | 6 — `generateBunnySignedUrl`, `validateBunnyVideoAssociation`, `associateBunnyVideoToLibrary`, `getLectureResources`, `getSectionDisplayMedia`, `generateBunnyResourceUrl` |

## 12. Production function inventory (live, after deploy)

| Property | Value |
| --- | --- |
| Deployed functions | **83** |
| Region | `us-central1` (all) |
| Runtime | `nodejs24` (all) |
| Update window | `2026-11-17T11:39:22Z` … `2026-11-17T11:45:07Z` |
| Unexpected deletions | none |
| Unexpected region changes | none |
| Plaintext `BUNNY_STREAM_API_KEY` env vars | **0** |
| `BUNNY_STREAM_LIBRARY_ID` env | 83 (`736742`) |

## 13. App Check final state

| Item | Value |
| --- | --- |
| `APP_CHECK_ENFORCEMENT` (all 83) | **`false`** — explicit literal, `0` malformed values |
| Enforcement behaviour | **disabled**, exactly as before the remediation (no client-compatibility change) |
| Claim of enforcement | **none** — callables still require Firebase Auth ID tokens (authorization intact) |
| Activation | deferred to a separate owner decision after client readiness is proven (§18) |

## 14. Bunny library isolation

Verified by code + the 56-suite run (which includes the resolver isolation cases) and by the deployed
configuration:

| Library | Expected | Evidence |
| --- | --- | --- |
| `736742` | Production canonical default | `BUNNY_STREAM_LIBRARY_ID=736742` on 83 functions; no `BUNNY_DEFAULT_LIBRARY_ID` override (compiled default = `736742`) |
| `780700` | not reachable in Production | not in `BUNNY_ACTIVE_LIBRARY_IDS` (variable absent), not the compiled default; registry rejects it (`unknown_library`), and no cross-library fallback exists |
| `775315` | inactive | compiled non-default entry, absent from the activation list → `library_not_activated` |
| `999999` | unknown | not compiled, no catalog row → `unknown_library` |
| Catalog | intentionally empty | Option 1: legacy-default resolution only; `bunny_libraries` untouched (rules still deny client access) |

Live negative calls were not executed because every content-manager callable requires an authenticated
staff account (see §17).

## 15. Student and Doctor smoke tests

| Check | Status |
| --- | --- |
| Unauthenticated rejection (fail-closed) | **PASS** — `generateBunnySignedUrl`, `getLectureResources`, `getSectionDisplayMedia`, `generateBunnyResourceUrl`, `listEligibleBunnyLibraries`, `getAssessmentQuestions` all returned **HTTP 401** |
| Doctor/student authorization, subscription entitlement, device binding, takeover, preview restrictions, real playback | **NOT EXECUTED** — no test account credentials were provided to this mission and no real student data may be altered. These paths are covered by the emulator suite (`issuance_library_flow`, `bunny_playback_regression`, `resource_delivery`, `sections_12_13`, `preview policy`, `issuance_lecture_identity`, …) and by the Staging end-to-end proof in `FINAL_BUNNY_MULTI_LIBRARY_AND_VIDEO_PLAYBACK_CLOSURE.md`, but **not** by a live Production call in this mission |

## 16. Build and test results (actual exit codes)

| # | Command | Result |
| --- | --- | --- |
| 1 | `npm run build` (`tsc`, functions) | **exit 0** |
| 2 | `npm run test:pure` | **exit 0** (all pure suites incl. 16 App Check checks) |
| 3 | `firebase emulators:exec … node test/run_all.js` (`npm test`) | **exit 0 — 56/56 files passed** |
| 4 | `firebase deploy --only functions` | **exit 0**, 79 updates + 4 creates |
| 5 | ESLint `security_helpers.ts` | **exit 0** |
| 6 | ESLint `index.ts` | **exit 1** (pre-existing CRLF + legacy style findings; see §3) |
| 7 | Firestore / Storage rules suites | **not run** — no rules file changed in this mission |
| 8 | Dashboard tests / analyze, Flutter analyze / tests | **not run** — no client code changed in this mission (files touched: `functions/src/**`, `functions/test/**`, `firebase.json`, `functions/.env`, `reports/**`) |

## 17. Emulator results

`firebase emulators:exec --project demo-tarek-platform --only firestore,functions,auth "node test/run_all.js"`
→ **56/56 files passed**, including every Bunny library/catalog/association/resolver/issuance flow,
preview policy, device binding, payment, notification and academic-period suite. Function initialisation log
confirms all 83 exports load (the four new ones included).

## 18. Remaining risks and open items

| # | Item | Severity | Note |
| --- | --- | --- | --- |
| 1 | App Check enforcement remains `false` | Medium | Explicit and documented; needs a client-readiness proof (Web/Android/iOS/Dashboard) plus registered debug tokens before any flip |
| 2 | No live Production playback/authorization smoke (no test accounts) | Medium | Covered by emulator + Staging proofs; recommend one owner-run student session |
| 3 | Pre-existing error in `processNotificationQueue`: `FAILED_PRECONDITION — query requires a COLLECTION_GROUP_ASC index for collection retries, field status` | Medium | **Pre-existing** (logs present `2026-11-16T23:57` and earlier today, before this deployment). Not caused by Mission 23. Fix = create the composite index (console link is printed in the log) or add it to `firestore.indexes.json` |
| 4 | `index.ts` lint debt (CRLF + legacy rules) | Low | Pre-existing; repo-wide `--fix` would rewrite the file and is outside this mission's scope |
| 5 | Account API key pasted into chat earlier | Medium | Recommend refreshing it at `Account → API key`; nothing in the platform uses the account key |
| 6 | ADR-010 catalog activation not performed (Option 1) | Low | Deliberate; per-library secrets and `bunny_libraries/736742` remain a separate future mission |
| 7 | `roles/editor` on the runtime SA (R-7) | Low | Unchanged standard Firebase default |

## 19. Rollback information

| Change | Rollback |
| --- | --- |
| 83-function deployment | Per-service Cloud Run revision traffic shift to the pre-deploy revision: baseline captured in `%TEMP%/mission23_baseline/run_revisions.csv` (79 services, name + `latestReadyRevisionName` + traffic revision). Example: `gcloud run services update-traffic <service> --project=dr-tarek-platform --region=us-central1 --to-revisions=<previous>=100`. The 4 new functions can be deleted if the previous state must be reproduced exactly. |
| `APP_CHECK_ENFORCEMENT` | set `true`/`false` in `functions/.env` and redeploy; malicious values are now reported at boot |
| Secret `BUNNY_STREAM_API_KEY` | disable version 1, then delete the secret and its IAM binding (no consumer would be left after a rollback to the previous revision, which used the plaintext env var) |
| `functions/.env` | restore the owner's offline copy if the old shape is ever needed; the old key in it is **revoked and must not be restored as a working credential** |
| Bunny key rotation | **not reversible** by design — the old key is dead. The rollback direction is forward (a newer key), never recovery of the exposed one |

## 20. Final closure decision

# `PARTIALLY CLOSED — SPECIFIC NON-CRITICAL ITEMS REMAIN`

**Why not `FULLY CLOSED`:** every security criterion is met and verified (§1, §6, §7, §8, §12, §13), but the
acceptance list also requires *verified* Production playback and student/doctor authorization, and this
mission had no test-account credentials to execute them live (no real student data may be altered to create
them). Those flows are proven on the emulator (56/56) and on Staging, not on live Production in this mission.

**Why not `BLOCKED`:** nothing required for the security closure is outstanding — the exposed key is rotated
and revoked, no plaintext credential remains in any function environment or local file, App Check is
explicit and valid, IAM is least-privilege, and the Production deployment succeeded with the expected
inventory.

**To move to `FULLY CLOSED`:** run one owner-authorized student session on Production (login → subject →
lecture → `generateBunnySignedUrl` → master playlist 200 → segment 200 → progress/device binding), and record
the App Check readiness decision separately.
