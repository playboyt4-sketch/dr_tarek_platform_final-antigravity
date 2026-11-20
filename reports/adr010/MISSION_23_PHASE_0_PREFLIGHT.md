# ADR-010 — Mission 23 Phase 0: Repository, Architecture and Credential Preflight

**Date:** 2026-11-16
**Mode:** READ-ONLY (no Production/Staging write, no secret read, no deploy, no Git mutation).
**Project verified:** `dr-tarek-platform` / `606744934510` / ACTIVE / region `us-central1`.
**Gate state:** Phase A **not started** — awaiting explicit Gate A approval.

---

## 1. Repository baseline (Phase 0.1)

| Item | Value |
| --- | --- |
| Branch | `ci/ios-staging-codemagic` |
| HEAD | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` (unchanged) |
| Working tree | 66 status entries: **33 modified, 33 untracked, 0 staged, 0 deleted** |
| Commits created | none |
| Reset / stash / clean / checkout | none |

Mission 22 changes present and identifiable (uncommitted, as intended):

| File | State | Mission-22 delta |
| --- | --- | --- |
| `functions/src/core/utils/security_helpers.ts` | modified | +59/−? — new parser |
| `functions/src/index.ts` | modified | whole-file diff includes earlier ADR-010 work; the Mission-22 delta is the import block + boot warning only |
| `firebase.json` | modified | +1 line `.env*` |
| `functions/package.json` | modified | `test:pure` gains `app_check_enforcement.test.js` |
| `functions/test/app_check_enforcement.test.js` | untracked | new (16 checks) |
| `reports/adr010/MISSION_22_APP_CHECK_ENFORCEMENT_HYGIENE.md` | untracked | new report |

The remaining 27 modified / 32 untracked entries are the earlier ADR-010 implementation (missions 12–19)
and unrelated CI/dashboard work. None were touched.

---

## 2. Mission 22 implementation verification (Phase 0.2)

Read from the actual files, not from the report:

| Claim | Verified |
| --- | --- |
| `describeAppCheckEnforcement()` exists and classifies `enforced` / `disabled` / `malformed` | **YES** (`security_helpers.ts`) |
| Only exact `"true"` enables enforcement | **YES** (`raw === "true"`) |
| `"false"` explicitly recognised | **YES** (`raw === "false" || undefined \|\| ""` → disabled) |
| Unexpected values → malformed | **YES** (fallthrough branch) |
| Diagnostic exposes only `rawLength`, never the value | **YES** (only field added in the malformed branch) |
| `SECURE_CALL_OPTS.enforceAppCheck = enabled` (behaviour unchanged) | **YES** |
| Boot warning guarded by `NODE_ENV !== "test"` | **YES** (`index.ts` same block as the ADR-010 identity diagnostic) |
| Boot warning prints no value | **YES** (only the variable name, the length and the words DISABLED) |
| `.env*` in `functions[0].ignore` | **YES** (`["node_modules",".git","firebase-debug.log","firebase-debug.*.log","*.local",".env*"]`) |
| `.env*` in `npm run test:pure` | **YES** (last entry) |

Executed checks:

| Check | Command | Result |
| --- | --- | --- |
| Functions build | `npm run build` (`tsc`) in `functions/` | **exit 0** |
| Pure suites | `npm run test:pure` | **exit 0** — all suites, incl. 16 App Check checks |
| ESLint — `security_helpers.ts` | `npx eslint` | **exit 0, 0 errors, 0 warnings** |
| ESLint — `index.ts` | `npx eslint` | **exit 1: 9,658 errors / 19 warnings — 9,641 are `linebreak-style` (whole file stored CRLF; pre-existing, not introduced by Mission 22); the other 17 are pre-existing (`valid-jsdoc` 9, `quotes` 4, `operator-linebreak` 2, `new-cap` 2) plus 19 pre-existing warnings (`no-explicit-any` 16, `no-non-null-assertion` 3)** |
| Emulator suites | not run in Phase 0 | deferred to Phase E |

Honest reading: the Mission-22 module is lint-clean; repository-wide lint for `index.ts` does **not**
pass, for reasons that existed before this mission (CRLF policy vs Windows checkout).

Local `.env` structure (keys/lengths only, no value printed):

| File | Key | valueLen | Notes |
| --- | --- | --- | --- |
| `functions/.env` | `APP_CHECK_ENFORCEMENT` | 97 | contains `=` (flattened 3-line blob) |
| `functions/.env` | `BUNNY_STREAM_LIBRARY_ID` | 6 | `736742` (identifier, not a secret) |

The flattened value is therefore exactly `false` + `BUNNY_STREAM_API_KEY=<41-char key>` +
`BUNNY_STREAM_LIBRARY_ID=736742`, matching Mission 21 §3.1. Both files are Git-ignored
(`.gitignore:54 .env.*`, `:55 *.env`). `git grep "BUNNY_STREAM_API_KEY="` still matches only the
*source identifier* in `src/index.ts` — no value in any tracked file.

---

## 3. ADR-010 architecture verification (Phase 0.3)

| Module | Verified behaviour |
| --- | --- |
| `bunny_library_registry.ts` | Compiled registry holds the default library (`736742`, env vars `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_TOKEN_KEY`, `BUNNY_STREAM_API_KEY`, `BUNNY_STREAM_LIBRARY_ID`) and `775315` (inactive). `isBunnyLibraryActive()` = default only when it equals the resolved canonical default; every other id requires `BUNNY_ACTIVE_LIBRARY_IDS`; empty list ⇒ inactive. `resolveDefaultBunnyLibraryId()` = `BUNNY_DEFAULT_LIBRARY_ID` when numeric, else `736742`. |
| `bunny_library_catalog.ts` | Strict allow-list parser; activation gate = `status active` + `token_auth_enabled` + `token_auth_verified`; `credential_refs` must match `BUNNY_<id>_STREAM_API_KEY` / `BUNNY_<id>_TOKEN_KEY`; client projection is `{libraryId, displayName}` only. |
| `bunny_library_secret_resolver.ts` | Reads only the requested library's secrets; `credential_name_mismatch` rejects a catalog row pointing at another library; no cross-library fallback; secret values/names/paths never in error text; 60 s positive cache, negatives not cached. |
| `security_helpers.ts` | Mission 22 parser (above). |
| Callables | `generateBunnySignedUrl`, `getLectureResources`, `getSectionDisplayMedia`, `generateBunnyResourceUrl`, `validateBunnyVideoAssociation`, `associateBunnyVideoToLibrary`, `listEligibleBunnyLibraries` present in source. |
| Mission 19 isolation | Intact: compiled default slot is never served as another id; a foreign default is skipped; per-library suites assert "A and B never resolve each other's credentials". |

Library statuses preserved: **Production `736742`, Staging `780700` (not touched), `775315` inactive**
(not in `BUNNY_ACTIVE_LIBRARY_IDS`, not default). No Staging resource was read or written in this phase.

### Production deployment reality (read-only)

| Property | Value |
| --- | --- |
| Deployed functions | **79** |
| Update windows | 2026-10-08 ×73, 2026-11-06 ×5, 2026-11-08 ×1 |
| `APP_CHECK_ENFORCEMENT` | **79/79 malformed 97-char values; 0 literal `true`/`false`** |
| Plaintext `BUNNY_STREAM_API_KEY` env var | **79/79** |
| `BUNNY_STREAM_LIBRARY_ID` env var | 79/79 (`736742`) |
| Secret mounts | `BUNNY_TOKEN_KEY` ×6, `BUNNY_STORAGE_BASE_URL` ×5, `BUNNY_PLAYBACK_URL_TEMPLATE` ×3, `BUNNY_STORAGE_ZONE_NAME` ×2, `BUNNY_STORAGE_PASSWORD` ×2 |
| `BUNNY_STREAM_API_KEY` secret mount | **none** (the secret does not exist) |

---

## 4. Secret dependency matrix (Phase 0.4)

Source truth: `defineSecret` declarations + per-callable `secrets:` arrays + resolver reads.

| Secret name | Required by source | Required by deployed function today | Purpose | Migration action |
| --- | --- | --- | --- | --- |
| `BUNNY_STREAM_API_KEY` | **YES** — `defineSecret("BUNNY_STREAM_API_KEY")`, mounted on 6 callables; also the legacy-default metadata credential | **NO** (plaintext env var; secret absent) | Stream metadata (poster/thumbnail/HQ flags) for the canonical default library | **Create** (Gate A) and mount at deploy; delete the plaintext env var |
| `BUNNY_TOKEN_KEY` | **YES** — mounted on 6 callables, pull-zone signing | yes (secret, 3 versions) | HLS URL signing | none (unchanged) |
| `BUNNY_PLAYBACK_URL_TEMPLATE` | **YES** — mounted on 3 callables | yes (secret) | playback host template | none |
| `BUNNY_STORAGE_BASE_URL` | **YES** — mounted on 5 callables | yes (secret) | storage-zone URL | none |
| `BUNNY_STORAGE_ZONE_NAME` | **YES** — mounted on 2 callables | yes (secret) | storage-zone uploads/deletes | none |
| `BUNNY_STORAGE_PASSWORD` | **YES** — mounted on 2 callables | yes (secret) | storage-zone auth | none |
| `BUNNY_<id>_STREAM_API_KEY` (e.g. `BUNNY_736742_STREAM_API_KEY`) | only when a `bunny_libraries/{id}` row exists | n/a (no catalog row) | catalog-path metadata key | **only if Gate B activates the catalog** |
| `BUNNY_<id>_TOKEN_KEY` (e.g. `BUNNY_736742_TOKEN_KEY`) | only when a catalog row exists | n/a | catalog-path signing key | **only if Gate B activates the catalog** |

Exact mounts required after deployment:

| Callable | Secrets it must mount |
| --- | --- |
| `generateBunnySignedUrl` | `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STREAM_API_KEY` |
| `validateBunnyVideoAssociation` | `BUNNY_TOKEN_KEY`, `BUNNY_STREAM_API_KEY` |
| `associateBunnyVideoToLibrary` | `BUNNY_TOKEN_KEY`, `BUNNY_STREAM_API_KEY` |
| `getLectureResources` | `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STREAM_API_KEY` |
| `getSectionDisplayMedia` | same as `getLectureResources` |
| `generateBunnyResourceUrl` | `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STREAM_API_KEY` |
| `uploadBunnyResource` | `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STORAGE_PASSWORD` |
| `deleteBunnyResource` | same as `uploadBunnyResource` |
| `listEligibleBunnyLibraries` | **none** (deliberate: reads only `BUNNY_ACTIVE_LIBRARY_IDS`) |

### 4.4 Conflict found between Mission 21 §11 and the source

Mission 21 proposes creating **both** the global `BUNNY_STREAM_API_KEY` (A.3) and the per-library
`BUNNY_736742_*` pair (C.2). The source does **not** require both, but it does force one of them to be
present in every scenario:

- `defineSecret("BUNNY_STREAM_API_KEY")` is mounted by 6 callables, so the **global secret must exist**
  before any deploy — irrespective of the catalog.
- The per-library secrets are read **only** when `bunny_libraries/736742` exists.
- With a catalog row, the global secret is still *mounted* but its value is no longer *used* for the
  default library (the catalog value wins). That duplication is inherent to the current code and is not
  a defect, only an extra secret to rotate.

No code change is proposed to "fix" this; it is recorded so Gate B can choose deliberately.

---

## 5. Deployment blast radius (Phase 0.5)

| Item | Finding |
| --- | --- |
| Function-like exports in source | **83** |
| Deployed | **79** |
| Newly created by a full deploy | **4** — `associateBunnyVideoToLibrary`, `listEligibleBunnyLibraries`, `validateBunnyVideoAssociation`, `getAssessmentQuestions` |
| Updated by a full deploy | **79** — all carry the ADR-010 code (missions 12–19) plus the Mission 22 parser; the 6 secret-mounting callables also gain the `BUNNY_STREAM_API_KEY` mount; all 79 lose the plaintext `BUNNY_STREAM_API_KEY` env var and the malformed `APP_CHECK_ENFORCEMENT` |
| Non-Bunny code in the same deploy | Yes — the uncommitted working tree contains unrelated dashboard/CI/video-player changes that compile into the same functions bundle. A deploy publishes the whole `functions/` build. |
| Narrower deployment possible? | Technically yes: `firebase deploy --only functions:<name>,…` for the 7–8 Bunny callables. **But** it leaves 72 functions holding the plaintext key and the malformed value, so it does not close R-1/R-2/R-3. |
| Is a full deploy required? | **For security closure: yes.** Only a full deploy removes the plaintext key and the corrupted value everywhere. |

Git protection: the working tree is preserved byte-for-byte; Phase 0 created no files inside the
repository except this report, and the metadata baseline lives outside it
(`%TEMP%/mission23_baseline/{functions.json,run_services.txt,secrets.txt}` — names, times and secret
names only, no payloads).

---

## 6. Exact Phase A operations proposed (awaiting Gate A)

| # | Operation | Command / mechanism | Risk | Reversible? |
| --- | --- | --- | --- | --- |
| A.1 | **Owner** rotates the Stream API key of library `736742` in the Bunny dashboard, keeping the old key active until A.2 passes | Bunny dashboard (owner only — no credential here) | Metadata (posters/thumbnails) degrades for pre-deploy functions once the old key is revoked | New key can be re-issued; **a revoked key cannot be restored** |
| A.2 | Verify new key works / old key rejected — **status codes only** | `curl -o /dev/null -s -w "%{http_code}"` against `video.bunnycdn.com/library/736742/videos?pageSize=1` | none | n/a |
| A.3 | Create the **empty** secret `BUNNY_STREAM_API_KEY` (no version, no value) | `gcloud secrets create BUNNY_STREAM_API_KEY --project=dr-tarek-platform --replication-policy=automatic` | none | delete secret |
| A.3b | **Owner** adds version 1 by typing the rotated key into their own terminal (never through this agent, never in an argument or file) | `gcloud secrets versions add BUNNY_STREAM_API_KEY --project=dr-tarek-platform --data-file=-` | low | disable/delete version |
| A.4 | Grant `roles/secretmanager.secretAccessor` on **that secret only** to `606744934510-compute@developer.gserviceaccount.com` | `gcloud secrets add-iam-policy-binding …` | low | remove binding |
| A.5 | Scrub `functions/.env`: `APP_CHECK_ENFORCEMENT=false` on its own line, keep `BUNNY_STREAM_LIBRARY_ID=736742`, **remove the key**, no new key added | local edit, keys/lengths verified after | none (ignored file) | owner's offline copy |
| A.6 | Verify: version enabled, per-secret IAM exactly one member, no project-wide Secret Manager role, `.env` key list clean, no tracked secret | gcloud + local checks | none | n/a |

**Not in Phase A:** Firestore catalog write, `BUNNY_DEFAULT_LIBRARY_ID` / `BUNNY_ACTIVE_LIBRARY_IDS` /
`BUNNY_LEGACY_LIBRARY_FALLBACK`, `APP_CHECK_ENFORCEMENT=true`, and any deployment — all belong to Gate B.

Known limitation for Gate A: A.1 and A.3b must be executed **by the owner**, because this mission
forbids handling the credential through the agent. I can execute A.3 (container), A.4, A.5 and A.6, and
verify A.2 with status codes only once the owner supplies the rotated key to Secret Manager.
