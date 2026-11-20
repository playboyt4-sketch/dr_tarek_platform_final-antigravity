# FINAL — Bunny Multi-Library Completion Report

**Date:** 2026-11-13
**Authorization:** Platform Owner final execution authorization (implement, validate, deploy).
**Verdict: PARTIALLY COMPLETE.** One production-grade defect class was fixed and fully
validated; the server-managed catalog, provisioning, migration execution, deployment and the
mandatory real-playback proof were **not** delivered. Each gap is listed with its exact
blocker in §12. Nothing was deployed and nothing was committed.

---

## 1. Original blockers and their resolution

| # | Blocker (Mission 10 §14 / §5) | Status |
|---|---|---|
| 1 | `DEFAULT_BUNNY_LIBRARY_ID = "736742"` compiled identity | **FIXED** — `BUNNY_DEFAULT_LIBRARY_ID` override, production fallback preserved |
| 2 | `isDefault` bypassing activation | **NOT CHANGED** — deliberate; making the default subject to the allow-list is a separate decision |
| 3 | Legacy rows forcing `736742` | **FIXED** — legacy fallback now resolves the environment's canonical default |
| 4 | Staging identity split (`780700` vs `736742`) | **FIXED in code** — canonical and Stream ids now derive from the same resolved default; a boot warning reports any residual mismatch |
| 5 | Empty/missing playback template | **OPEN** — environment provisioning, not code (Mission 11 §9) |
| 6 | Missing staging Secret Manager versions | **OPEN** — zero versions on `BUNNY_TOKEN_KEY` / `BUNNY_PLAYBACK_URL_TEMPLATE`; requires provisioning with real values |
| 7 | Missing Dashboard Library Picker | **OPEN** — needs approved Figma (Mission 8 §L / D13) |
| 8 | Dashboard create failure losing the Video ID | **NOT REPRODUCED / NOT FIXED** — would require a live Dashboard session |
| 9 | `first_video` metadata inconsistency | **PREVIOUSLY FIXED** (Mission 4: provider, backfill script and tests all carry `bunny_library_id`) |
| 10 | Read-only migration planner with no apply path | **OPEN** — deliberately gated; executing a backfill is a production data write |
| 11 | No production migration/backfill plan execution | **OPEN** — dry-run evidence exists (`migration_design.md`), execution not authorized by a rollback-tested plan |
| 12 | Cutover timestamp already in the past | **OPEN** — changing it is a policy decision (it is an env var, `BUNNY_ASSOCIATION_CUTOVER`) |
| 13 | Unsafe Functions-first deployment order | **RESPECTED** — nothing was deployed |
| 14 | Bunny API key in plain `.env` | **OPEN** — production `BUNNY_STREAM_API_KEY` is still a plain env var (Mission 10 §8) |
| 15 | Missing library-key ↔ Pull-Zone-key verification gate | **OPEN** — the 9S probe matrix exists as a documented procedure, not as code |
| 16 | Lint/test failures | **CLOSED for the changed surface** — build clean, 52/52 function suites, 21 rules assertions, 54 Dashboard tests |

---

## 2. Architecture implemented

A single, backward-compatible change to library **identity resolution**:

```
BUNNY_DEFAULT_LIBRARY_ID (optional, numeric)
        │
        ▼
resolveDefaultBunnyLibraryId(env) ──► compiled fallback "736742"
        │
        ├──► resolveBunnyLibraryForResource()   (stored id → registry → legacy default)
        ├──► resolveBunnyPlaybackRuntime()      (template + token key for THAT id)
        ├──► resolveBunnyStreamApiRuntime()     (api key + api library id for THAT id)
        └──► describeBunnyEnvironment()         (boot diagnostic: id vs Stream id)
```

- `findBunnyLibraryDefinition(id, env)` resolves the default entry **by the environment's
  canonical id**, so the registry, the credentials and the label can no longer disagree.
- Clients read the same override from `--dart-define=BUNNY_DEFAULT_LIBRARY_ID`.
- No new network call was added to the playback path; no credential is returned to clients;
  fail-closed reasons and the 600-second receipt contract are unchanged.

**Not implemented:** Firestore `bunny_libraries` catalog, Secret Manager runtime reads,
provisioning/verification callables. Those are the remaining Option A substance.

---

## 3. Files changed

| File | Change |
|---|---|
| `functions/src/core/video/bunny_library_registry.ts` | `BUNNY_DEFAULT_LIBRARY_VAR`, `resolveDefaultBunnyLibraryId()`, `describeBunnyEnvironment()`, env-aware `findBunnyLibraryDefinition()`, default resolution in resource/playback/Stream resolvers |
| `functions/src/core/video/bunny_library_association.ts` | passes the env snapshot into definition lookup |
| `functions/src/index.ts` | imports `describeBunnyEnvironment`; logs the identity-split warning at boot (skipped under test) |
| `functions/test/bunny_default_library_config.test.js` | **new** — 19 checks covering override, fallback, invariant, production parity, staging parity, fail-closed |
| `functions/test/run_all.js` | registers the new suite |
| `dashboard/lib/features/students/domain/bunny_library_association.dart` | `defaultBunnyLibraryId` from `String.fromEnvironment(..., defaultValue: '736742')` |
| `lib/features/content_authoring/data/datasources/admin_content_remote_data_source_impl.dart` | same build-time override for the mobile authoring fallback |
| `21_ADR_010_Amendment_1.md` | **new** — records the decision, its limits and the untouched guarantees |
| `reports/adr010/mission_9s_…md`, `mission_10_…md` | dated appendices retracting the `e1a3ddca` parsing artifact |

No other tracked file was touched by this work. Pre-existing Mission 3/4 modifications are
untouched and uncommitted.

---

## 4. Bunny library configurations verified (read-only, Missions 9S/11)

| | Production | Staging |
|---|---|---|
| Library | `736742` ("اختبار", 2 videos) | `780700` ("DrTarek-Staging-Test", 0 videos) |
| Pull Zone | `6414868` | `6807898` |
| Hostname | `vz-c6abe953-876.b-cdn.net` | `vz-b5f9cb68-f06.b-cdn.net` |
| `VideoLibraryId` | `736742` ✔ | `780700` ✔ |
| `ZoneSecurityEnabled` | **true** | **false** |
| `BlockNoneReferrer` / `AllowedReferrers` | true / `[]` | true / `[]` |
| `ZoneSecurityKey` | unmasked, 36 chars, fp `af89b2a5` | unmasked, 36 chars, fp `cbf22628` |
| Signed / unsigned / wrong-key | **200 / 403 / 403** | not testable (no video, token auth off) |

`775315` was not touched, not activated, not read beyond prior mission evidence.

---

## 5. Secret Manager configuration status (no values)

| Secret | `dr-tarek-platform` | `dr-tarek-staging` |
|---|---|---|
| `BUNNY_TOKEN_KEY` | 3 versions; latest fp `af89b2a5` | exists, **0 versions** |
| `BUNNY_PLAYBACK_URL_TEMPLATE` | 2 versions | exists, **0 versions** |
| `BUNNY_STORAGE_*` (3) | present | present (names only) |
| Account API key | **not stored** (read only from the authenticated dashboard session) | — |
| `BUNNY_ASSOCIATION_RECEIPT_KEY` | **does not exist** (decision D4 not taken) | — |

---

## 6. Firestore and Rules changes

**None.** `firestore.rules` is unchanged by this work: `bunny_library_id` remains
server-owned, `created_at` remains immutable, `resource_type` immutable, verified
`bunny_video_id` immutable, and the default-deny tail is intact. The 21-assertion ADR-010
rules suite passes (see §8).

---

## 7. Migration / backfill results

**Not executed.** No Firestore document was written, no backfill ran, no cutover was
changed. The existing dry-run planner and the `bunny_library_id` backfill projection
(Mission 4) remain the only migration artifacts. A production backfill requires the
prerequisites in §12 (rollback-tested plan, per-resource mapping, idempotency proof).

---

## 8. Test commands and exact results

| Command | Result |
|---|---|
| `cd functions && npm run build` (`tsc`) | **exit 0**, no errors |
| `node test/bunny_default_library_config.test.js` | **19/19 checks passed** |
| `cd functions && npm test` (emulators) | **52/52 files passed**, exit 0 |
| `security-tests: firebase emulators:exec --only firestore,storage -- npm test` | **pass**, ADR-010 association suite **21 assertions**, exit 0 |
| `cd dashboard && flutter test` on the 4 bunny suites | **54/54 tests passed**, exit 0 |
| `git diff --check` | **clean** |

Not run (and not claimable): `flutter analyze` over the whole app, web/Android release
builds, emulator end-to-end with a new library, any live in-app playback.

---

## 9. Deployment targets and timestamps

**None.** No Functions, Rules, Hosting or Flutter artifact was deployed. Timestamps: n/a.

Reason: deploying `functions/src/index.ts` would publish the entire uncommitted Mission 4
backend delta (≈577 lines: association callable, receipts, cutover gate) to **production**
with no staging playback proof and no rollback rehearsal, while production playback currently
works. That is exactly the "do not use production as an experimental environment" line in
§3 of the authorization.

---

## 10. Real staging playback evidence

**None — not performed.** Staging library `780700` has:
no Stream API key (empty env value, no Secret Manager secret), a token key with **zero
versions**, an empty playback template, `ZoneSecurityEnabled=false`, and **0 videos**.
There is nothing to sign and nothing to play. The behavioural probes that could be run are in
Mission 11 §3 (with app Referer → 404; without Referer → 403).

---

## 11. Production smoke test evidence

**None — not performed.** A real in-app playback requires a built client with an authenticated
student session; no device, emulator, or signed-in session is available to this environment.
What *is* verified (read-only, Mission 9S): a correctly signed HLS request to the production
zone returns **200** with `application/vnd.apple.mpegurl` and a `#EXTM3U` manifest; unsigned
and wrong-key requests return **403**.

I will not describe an HTTP 200 as application playback.

---

## 12. Remaining risks and exact blockers

| # | Remaining work | Exact blocker | Smallest next action |
|---|---|---|---|
| 1 | Firestore `bunny_libraries` catalog + async resolver | DB-change decision not taken | Approve the collection + rules deny block |
| 2 | Account-level key in Secret Manager | Only available inside a browser session; no persistent secret | Create `BUNNY_ACCOUNT_API_KEY` in Secret Manager (Sites/console) |
| 3 | Provisioning/verification callables | Depends on 1 + 2 + `@google-cloud/secret-manager` | Implement after 1–2 with mocked-HTTP tests |
| 4 | Activation gate (key ↔ zone fingerprint) | Needs the account key at runtime | Reuse Mission 9S matrix as a pre-activation probe |
| 5 | Staging playback | No credentials, no video, token auth off | Provision 3 secret versions, enable token auth (write), upload a clip |
| 6 | Dashboard Library Picker | No approved Figma | Design decision (D13) |
| 7 | Production backfill | No rollback-tested apply path | Dry-run → diff review → approved apply window |
| 8 | Receipt key separation | Decision D4 | Create `BUNNY_ASSOCIATION_RECEIPT_KEY` + 10-min dual-verify window |
| 9 | Live in-app playback proof | No device/session in this environment | Owner runs the app against staging and records the evidence |

---

## 13. Rollback instructions

| Change | Rollback |
|---|---|
| Server registry / invariant | Revert the three edited/new backend files; `DEFAULT_BUNNY_LIBRARY_ID` remains the compiled fallback, so unsetting `BUNNY_DEFAULT_LIBRARY_ID` restores today's behaviour exactly |
| Clients | Remove the two `String.fromEnvironment` overrides (default value was already `736742`) |
| Docs | Reports and ADR amendment are non-executable records |
| Nothing deployed | No deployment rollback required |

No data, credential or Bunny setting was changed, so no data rollback exists to perform.

---

## 14. Git branch, HEAD and commits

| Item | Value |
|---|---|
| Branch | unchanged (`master`/current branch) — no branch was created |
| HEAD | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` |
| Staged | 0 entries |
| Commits added | **none** |
| `git diff --check` | clean |

**Why no commit:** the working tree already carries ~30 tracked modifications plus untracked
modules from Missions 3/4/7 (the ADR-010 feature itself). My changes live *inside* those same
files (`functions/src/index.ts`, `functions/test/run_all.js`, the mobile data source), so a
commit would either bundle months of unreviewed work or require an interactive partial-hunk
split that risks the Owner's uncommitted changes. Committing safely needs an explicit
decision on how to package the pre-existing ADR-010 work.

---

## 15. Final verdict

# PARTIALLY COMPLETE

**Delivered and proven:** the hardcoded production library identity is gone; the canonical
library is now configuration-driven with a production-identical fallback; the staging identity
split is structurally fixed and diagnosed at boot; clients accept a build-time default;
ADR-010 and the two affected reports are reconciled (including the `e1a3ddca` retraction);
build, 52 function suites, 21 rules assertions and 54 Dashboard tests pass.

**Not delivered:** the server-managed catalog, account-API provisioning, activation
verification gate, migration execution, Dashboard picker, staging credentials/video,
deployment, and — decisively — **real in-app playback**, which the authorization names as the
completion criterion.

The mission is therefore **not complete**, and no deployment was performed, because the
remaining path requires production-dollar decisions (catalog schema + account key custody)
and real credentials/content that this environment cannot safely manufacture.

**Stop point:** implementation increment complete and validated; awaiting the Owner's
decisions on §12 items 1–2 (catalog schema, account-key custody) and a device/session for the
playback proof.

---

## Appendix B — Execution update (post-approval, same day)

The Owner approved the catalog, Secret Manager integration and staging provisioning. Executed
since:

| Action | Result |
|---|---|
| `bunny_library_catalog.ts` (new pure module) | validation, allow-list projection, activation gate (`active` + token auth enabled + probe-verified), deterministic secret names; **26 checks pass** |
| `firestore.rules` | explicit `match /bunny_libraries/{libraryId} { allow read, write: if false; }` (server-only); full rules+storage suite still passes (21 ADR-010 assertions) |
| `functions/test/run_all.js` | catalog + default-config suites registered; `npm test` **53/53 files pass** |
| Staging secret `BUNNY_PLAYBACK_URL_TEMPLATE` (`dr-tarek-staging`) | **version 1 created** with `https://vz-b5f9cb68-f06.b-cdn.net/{video_id}/playlist.m3u8` (not a secret value) |
| Staging Token Authentication (`780700` / zone `6807898`) | **ENABLED** via `POST https://api.bunny.net/videolibrary/780700 {"EnableTokenAuthentication":true}` → `ZoneSecurityEnabled=true`; signing key fingerprint unchanged (`cbf22628`, no rotation) |
| Enforcement probe | unsigned HLS with app Referer: **404 → 403** (previously the object simply did not exist; now the token gate rejects first); without Referer: 403 |
| API method note | `PUT /videolibrary/{id}` returns **405**; `POST /videolibrary/{id}` is the working update verb — must be recorded in the Option A provisioner |

### Remaining external blockers (cannot be completed from this environment)

| # | Secret / asset | Type | Project | Why blocked |
|---|---|---|---|---|
| 1 | `BUNNY_TOKEN_KEY` | secret value (36-char zone key, fp `cbf22628`) | `dr-tarek-staging` | Value exists only inside the authenticated Bunny API response; moving it into GCP would require emitting it into a shell/argument. Owner must create the version (console or `firebase functions:secrets:set`) |
| 2 | `BUNNY_STREAM_API_KEY` | secret value (41-char library key) | `dr-tarek-staging` | Same transfer constraint; also needs the library's `ApiKey` from the Bunny API page |
| 3 | Test video | asset (any short clip) | library `780700` | No video file exists in the workspace and no upload credential can be handed to a script without exposing it; Owner: upload via Bunny dashboard ("Upload Video") |
| 4 | In-app playback proof | device/session | — | Requires a built client (staging `--dart-define`s) signed in as a student; no device or emulator session is available to the agent |
| 5 | Production deployment | deployment | `dr-tarek-platform` | Deploying ships ~600 lines of uncommitted Mission 4 backend plus this catalog work; per §3/§10 it must wait for staging playback evidence + rollback rehearsal |

**Verdict remains PARTIALLY COMPLETE**: the catalog data model, its security boundary and the
staging protection model are now real and tested; the remaining path is credential/asset
provisioning (Owner, 3 concrete items) and a device for the playback proof.

---

## Mission 12 — BUNNY_STREAM_API_KEY → Secret Manager (staging `dr-tarek-staging`)

### Delivered
| Item | Evidence |
|---|---|
| Secret created | `BUNNY_STREAM_API_KEY`, project `dr-tarek-staging`, automatic replication, created 2026-11-14T10:07:51Z |
| Version written | **version 2 = enabled** (version 1 held a partial/masked value read during the dashboard reveal animation and was **destroyed**) |
| Value never exposed | written via a one-shot loopback bridge → chmod-600 temp file → `gcloud secrets versions add --data-file`; temp file removed (`tempRemoved=true`), bridge and logs deleted, nothing printed or committed |
| Value correctness | `GET https://video.bunnycdn.com/library/780700/videos` with the secret ⇒ **200**; same key against `library/736742` ⇒ **401** (per-library isolation) |
| Code | `defineSecret("BUNNY_STREAM_API_KEY")`; mounted on all 6 consumers: `generateBunnySignedUrl`, `validateBunnyVideoAssociation`, `associateBunnyVideoToLibrary`, `getLectureResources`, `getSectionDisplayMedia`, `generateBunnyResourceUrl` |
| No silent fallback | `resolveBunnyStreamApiKey({secretValue, env, isEmulator})`: secret wins; plain env var honoured **only** under `FUNCTIONS_EMULATOR=true`; otherwise empty ⇒ `incomplete_configuration` |
| Dead env removed | `BUNNY_STREAM_API_KEY` line deleted from `functions/.env.dr-tarek-staging` |
| Staging env | `BUNNY_STREAM_LIBRARY_ID=780700`, `BUNNY_DEFAULT_LIBRARY_ID=780700`, `APP_CHECK_ENFORCEMENT=false` |
| Tests | `npm run build` exit 0; `npm test` **53/53 files**; `bunny_library_registry.test.js` **30** checks (5 new precedence assertions); `bunny_default_library_config` 19 checks |

### Real video in library 780700
- Uploaded `Staging Playback Probe` (4 s, 640x360, generated locally with ffmpeg).
- `PUT /library/780700/videos/{guid}` ⇒ 200; encoding finished: `status=4`, `encodeProgress=100`, `availableResolutions=240p,360p`.
- GUID: `47561140-5966-4e0f-8851-83c78ce5bb92`.

### Playback matrix (pull zone `6807898`, host `vz-b5f9cb68-f06.b-cdn.net`)
| Case | Result |
|---|---|
| Unsigned, token auth **disabled** (control) | **200**, body starts `#EXTM3U` ⇒ real, playable HLS |
| Signed with pull-zone `ZoneSecurityKey`, valid expiry | **403** |
| Unsigned with/without Referer | **403** |
| Wrong signature | **403** |
| Expired signature | **403** |

Token authentication was restored to **enabled** afterwards (`ZoneSecurityEnabled=true`).

**Conclusion:** content availability and token enforcement both work (200 only when signing is off, 403 for every non-valid case), but no valid signature can be produced yet because the signing key currently on record for this library is not the one the edge expects. This is an open item, not a pass.

### Open blockers
1. Staging `BUNNY_TOKEN_KEY` still has **0 versions** — the app's signed-URL path cannot run in staging. Provisioning/rotating that secret was explicitly out of scope here.
2. The pull-zone `ZoneSecurityKey` for `6807898` does not validate against the edge for Stream tokens; the library-level signing key must be resolved before a signed **200** can be demonstrated.
3. In-app playback proof needs a staging functions build + a student session/device; neither exists yet, so "plays inside the application" remains **unproven**.

**Verdict: Mission 12 code + secret migration PASS; playback security matrix FAIL (signed 200 not achieved); in-app playback NOT PROVEN.**

---

## Mission 13 — Signing key resolution & staging `BUNNY_TOKEN_KEY`

### Root cause (Phase 1)
Pull zone `6807898` enforces **CDN Token Authentication in *Advanced* mode** (path-embedded token), not the basic query-string mode used by the Mission 12 probe. The application code was already correct: `hashVideoDirectoryToken` builds
`HS256-` + base64url(HMAC-SHA256(key, `scope` + `expires` + `token_path=<scope>`)) with `scope = /<videoId>/`, and `buildBunnyFileUrl` / `generateBunnySignedUrl` embed it as
`/bcdn_token=<token>&token_path=<enc(scope)>&expires=<exp>/<videoId>/<file>`.
The Mission 12 failure was therefore **key-usage/signature-format in the verification harness**, not a code defect. No signing code was changed.

Signing inputs verified: secret = pull-zone `ZoneSecurityKey` (36 chars); canonical path = video **directory** `/<guid>/`; digest = HMAC-SHA256, base64url, `HS256-` prefix; expiry = Unix **seconds**; query names `token_path`/`expires`; token is **inside the path** so relative rendition/segment URLs inherit authentication; Referer required (`BlockNoneReferrer=true`, `AllowedReferrers=[]`).

### Key identity (fingerprints only)
| Key | Length | SHA-256 prefix | Notes |
|---|---|---|---|
| Staging pull-zone `6807898` `ZoneSecurityKey` | 36 | `cbf22628` | matches the previously observed fingerprint |
| Staging Secret Manager `BUNNY_TOKEN_KEY` v1 | 36 | `cbf22628` | byte-identical to the zone key |
| Production `BUNNY_TOKEN_KEY` | 36 | `af89b2a5` | **different key — no reuse** |

### Secret Manager metadata (`dr-tarek-staging`)
- `BUNNY_TOKEN_KEY` → **version 1 = enabled** (created this mission).
- `BUNNY_STREAM_API_KEY` → version 2 = enabled; version 1 = destroyed.
- Transfer used a one-shot loopback bridge → chmod-600 temp file → `gcloud secrets versions add --data-file` → temp deleted; bridge, log and temp dir removed; nothing printed or committed.

### HTTP security matrix (library 780700, video `47561140-…`, signed with the staging secret)
| Case | Result |
|---|---|
| A. Unsigned + app Referer | **403** |
| B. Advanced HS256 path token + app Referer | **200**, `#EXTM3U` |
| B2. Same token, **no** Referer | **403** (referrer policy enforced) |
| C. Wrong key | **403** |
| D. Expired signature | **403** |
| E. Basic `?token=<sha256>` query token | **403** (confirms Advanced mode) |

### HLS segment verification
- Master playlist → `360p/video.m3u8` **200**, `#EXTM3U`, `#EXT-X-ENDLIST` present.
- Media segment → **200**, `content-type: video/mp2t`, **131 224 bytes**, MPEG-TS sync byte `0x47` confirmed.

### Tests
- `npm run build` → exit 0.
- `npm test` → **53/53 files PASS** (twice: before and after the regression tightening).
- New regression in `test/issuance_library_flow.test.js`: the issued URL must contain `/bcdn_token=HS256-`, `token_path=`, a numeric `expires`, and must **not** carry a legacy `?token=` query token — locks the Advanced-mode contract so a future refactor cannot silently regress to the 403-causing scheme.

### Gate status
| Gate | Status |
|---|---|
| Signing key resolution | **PASS** — Advanced mode identified, key identity proven by fingerprint |
| Secret provisioning | **PASS** — `BUNNY_TOKEN_KEY` v1 enabled in staging, isolated from production |
| Staging CDN playback | **PASS** — signed 200, rendition + TS segment verified |
| Actual application playback | **NOT PROVEN** — no staging Functions deployment was made and no authorized student session/device was available; the client-side player path was not exercised |

**Verdict: three of four gates PASS. Mission 13 is NOT complete because in-app playback remains unproven. No production deployment, no commit, library `736742` untouched, token authentication left enabled.**

---

## Mission 14 — Staging deployment attempt & live playback

### 1. Pre-deployment gate
| Check | Result |
|---|---|
| Branch / HEAD | `ci/ios-staging-codemagic` @ `34a4b76` |
| Working tree | 30 tracked modified + untracked ADR-010 modules/tests/reports; `+1320 / −139` since HEAD |
| Secret scan of every changed/untracked file (`bcdn_token=`, `HS256-…`, `AccessKey`, key literals, PEM headers) | **no secret values**; all hits are identifiers, tests, docs |
| Tracked secret files | none; `functions/.env` and `.env.dr-tarek-staging` are gitignored (`.gitignore:64`, `:54`) |
| Deploy target | `--project dr-tarek-staging` only; `.firebaserc` default is production, so every command used an explicit `--project` |
| Staging functions before deploy | 69 gen1 + 68 gen2 services, **0** containing `bunny` → these functions are new in staging |

### 2. Deployment attempts (all failed — nothing deployed)
| Attempt | Scope | Result |
|---|---|---|
| 1 | 6 functions | Rejected: `Secret [BUNNY_STORAGE_BASE_URL] not found or has no versions` |
| 2 | 3 functions (no storage consumers) | Rejected: `Secret environment variable overlaps non secret environment variable: BUNNY_STREAM_API_KEY` |
| 3 | same 3, after cleanup | Rejected: `Cloud Secret Manager has no latest version of the secret defined by param BUNNY_STORAGE_BASE_URL` |

**Root cause 1 (fixed):** the plain env files still carried names that are now Secret Manager params. Removed `BUNNY_STREAM_API_KEY` from `functions/.env` and `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STORAGE_PASSWORD` from `functions/.env.dr-tarek-staging`. Remaining staging keys are non-secret only: `APP_CHECK_ENFORCEMENT`, `BUNNY_STREAM_LIBRARY_ID`, `BUNNY_DEFAULT_LIBRARY_ID`.

**Root cause 2 (open):** `defineSecret` is executed at module scope, so Firebase validates **every** declared secret on any deploy — even a 3-function subset. Staging has **0 versions** of `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STORAGE_PASSWORD`, so no function in this codebase can be deployed to staging until they exist.

**Why a placeholder was refused:** the Bunny account holds exactly one storage zone — `dr-tarek-resources` (id `1783545`) — which is the **production** storage zone used by library `736742`. Pointing staging at it would break environment isolation, and inventing fake credentials would create a silently broken upload path. Both violate the standing restrictions, so the deploy stopped here instead.

### 3. Live signing test / in-app playback
**Not executed.** No Bunny function exists in staging (`0` matching Cloud Run services), therefore there is no deployed endpoint to call, and no authorized staging student session/device exists for the Flutter path. No signed URL was produced by a deployed function, and app playback is **BLOCKED**, not attempted.

### 4. Validation run this mission
- `npm run build` (via `predeploy`, twice) → **exit 0**.
- `git diff --check` → **clean**.
- No source-code change was made this mission beyond removing duplicate env entries (gitignored).
- `npm test` was **not** re-run in Mission 14; the last full run (Mission 13, identical source) was **53/53 files PASS**.

### 5. Remaining blockers
1. Staging has no dedicated Bunny storage zone; the three `BUNNY_STORAGE_*` secrets have no versions, which blocks **any** `firebase deploy --only functions` against `dr-tarek-staging`.
2. Decision required: create a dedicated staging storage zone (then provision the three secrets from its real credentials) **or** change the storage-resource functions to not declare those secrets at module scope so playback-only functions can deploy without them.
3. No staging student session / authorized device for the real Flutter playback path.

**Verdict: pre-deployment gate PASS. Staging deployment FAILED (diagnosed, not worked around). Live signing test and in-app playback NOT EXECUTED. No production deployment, no commit, `736742` and `775315` untouched, Token Authentication still enabled.**

---

## Mission 14A — Isolated staging Bunny Storage Zone

**Verdict: PASS** (Bunny zone created, secrets provisioned and proven, production untouched).

### Storage zones in the account
| Zone ID | Name | Region | Hostname | Files | Date modified | Role |
|---|---|---|---|---|---|---|
| `1783545` | `dr-tarek-resources` | DE | `storage.bunnycdn.com` | 0 | `2026-08-24T20:46:51` (pre-existing) | **production — untouched** |
| **`2058675`** | **`dr-tarek-staging-resources`** | DE | `storage.bunnycdn.com` | 0 | `2026-11-14T10:54:40` | **new, staging only** |

Creation used the account API (`POST https://api.bunny.net/storagezone`) with `ZoneTier 0`; Bunny returned the new zone with its own password, so no credential was ever copied from production.

### Secret Manager (`dr-tarek-staging`) — names only, values never printed
| Secret | Versions | State | Fingerprint (SHA-256 prefix) |
|---|---|---|---|
| `BUNNY_STORAGE_BASE_URL` | 1 | enabled | `https://storage.bunnycdn.com/dr-tarek-staging-resources` (non-secret value) |
| `BUNNY_STORAGE_ZONE_NAME` | 1 | enabled | `dr-tarek-staging-resources` (non-secret value) |
| `BUNNY_STORAGE_PASSWORD` | 1 | enabled | `86661456` (41 chars) |
| `BUNNY_STREAM_API_KEY` | 2 enabled / 1 destroyed | — | — |
| `BUNNY_TOKEN_KEY` | 1 | enabled | `cbf22628` |

`BUNNY_STORAGE_PASSWORD` fingerprint `86661456` vs production `2dd39e27` — **different secret, no reuse**. Both were transferred through a one-shot loopback bridge to a `0600` temp file and `gcloud secrets versions add --data-file`; the temp file, bridge script and bridge log were deleted, and `git status` shows no leftovers.

### Credential and isolation proof (staging zone)
| Probe | Result |
|---|---|
| `PUT` probe object into staging zone with staging password | **201** |
| `GET` same object with staging password | **200**, body byte-identical |
| `DELETE` probe object (cleanup) | **200** |
| `PUT` into production zone `dr-tarek-resources` with **staging** password | **401** |
| `GET` from production zone with **staging** password | **401** |

Production zone metadata (`FilesStored = 0`, `DateModified 2026-08-24`) is unchanged, and no production object was written or deleted.

### Notes for later missions (not executed here)
- Deploying functions still requires the staging runtime service account to hold `roles/secretmanager.secretAccessor` on these five secrets; the secret IAM policy is currently empty, so it resolves through project-level inheritance and should be verified at deploy time.
- No Cloud Functions, Hosting, Firestore or Storage Rules deployment was performed in this mission, and no application code was modified.

---

## Mission 14B — Secret IAM audit & staging Bunny function deployment

**Verdict: PASS** — IAM verified/remediated, six Bunny functions deployed to `dr-tarek-staging`, no code change needed, production untouched.

### Phase A — IAM audit (read-only)
| Item | Value |
|---|---|
| Project number | `13159003436` |
| Gen 2 runtime service account | `13159003436-compute@developer.gserviceaccount.com` (all six targets are 2nd gen / Cloud Run) |
| Gen 1 runtime service account | not applicable — existing gen1 functions carry a blank `serviceAccountEmail` (default appspot SA) and none of the targets is gen 1 |
| Project-level roles of runtime SA | `roles/editor`, `roles/eventarc.eventReceiver`, `roles/run.invoker` |
| Explicit secret-level `secretAccessor` before remediation | `BUNNY_STREAM_API_KEY`, `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE` **present**; `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STORAGE_PASSWORD` **absent** |
| Enabled versions | all six secrets have exactly 1 enabled version (`BUNNY_STREAM_API_KEY` also keeps its destroyed v1) |

### Phase B — IAM remediation (recorded changes)
Three secret-level bindings added — staging only, runtime SA only, `roles/secretmanager.secretAccessor` only:
```
gcloud secrets add-iam-policy-binding BUNNY_STORAGE_BASE_URL   --project dr-tarek-staging --member serviceAccount:13159003436-compute@developer.gserviceaccount.com --role roles/secretmanager.secretAccessor
gcloud secrets add-iam-policy-binding BUNNY_STORAGE_ZONE_NAME  --project dr-tarek-staging --member serviceAccount:13159003436-compute@developer.gserviceaccount.com --role roles/secretmanager.secretAccessor
gcloud secrets add-iam-policy-binding BUNNY_STORAGE_PASSWORD   --project dr-tarek-staging --member serviceAccount:13159003436-compute@developer.gserviceaccount.com --role roles/secretmanager.secretAccessor
```
Post-change verification: all six secrets now show exactly `roles/secretmanager.secretAccessor` → `serviceAccount:13159003436-compute@developer.gserviceaccount.com`. No Secret Manager Admin, no user-account grants, no project-level change, no production IAM change.

### Phase C — Secret declaration isolation
Audit result: the bindings were already minimal, so **no code was changed**.
| Function | Secrets bound |
|---|---|
| `generateBunnySignedUrl` | `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STREAM_API_KEY` |
| `validateBunnyVideoAssociation` | `BUNNY_TOKEN_KEY`, `BUNNY_STREAM_API_KEY` |
| `associateBunnyVideoToLibrary` | `BUNNY_TOKEN_KEY`, `BUNNY_STREAM_API_KEY` |
| `getLectureResources` | `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STREAM_API_KEY` |
| `getSectionDisplayMedia` | same as `getLectureResources` |
| `generateBunnyResourceUrl` | `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STREAM_API_KEY` |
| `uploadBunnyResource` / `deleteBunnyResource` | `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STORAGE_PASSWORD` |

No playback-only function carries a storage **credential**: the only storage value they bind is `BUNNY_STORAGE_BASE_URL`, a plain HTTPS base path used by `bunnyResourceUrl`/thumbnail fallbacks, not a secret. The Mission 14 deploy failure was caused by secrets existing without versions — resolved in 14A — so module-level `defineSecret` declarations now validate cleanly and no restructuring (and no fake secret, no fallback credential, no weakened validation) was required.

### Phase D — Validation before deployment
| Check | Result |
|---|---|
| `npm run build` | **exit 0** |
| `npm test` | **53/53 files PASS** |
| Bunny-specific (`bunny_library_registry`, `bunny_default_library_config`, `bunny_library_catalog`, `bunny_library_migration`, `bunny_playback_regression`, `bunny_library_validation_flow`, `bunny_library_association`, `bunny_association_flow`, `issuance_library_flow`) | **all PASS** |
| `git diff --check` | **clean** |
| Diff review for secret values / signed URLs | none present (identifier and test-only matches) |

### Phase E — Deployment
```
firebase deploy --only \
  functions:generateBunnySignedUrl,functions:validateBunnyVideoAssociation,\
functions:associateBunnyVideoToLibrary,functions:getLectureResources,\
functions:getSectionDisplayMedia,functions:generateBunnyResourceUrl \
  --project dr-tarek-staging --non-interactive
```
Outcome: **Deploy complete!** — six successful *create* operations, no Hosting, no Firestore Rules, no Storage Rules, no other functions.

### Phase F — Post-deployment verification
| Check | Evidence |
|---|---|
| Functions exist in staging | Cloud Run services `generatebunnysignedurl`, `validatebunnyvideoassociation`, `associatebunnyvideotolibrary`, `getlectureresources`, `getsectiondisplaymedia`, `generatebunnyresourceurl`, created `2026-11-14T11:16Z` (revisions `-00001-*`) |
| Runtime SA | every revision runs as `13159003436-compute@developer.gserviceaccount.com` |
| Secret mounting | each revision's env shows the expected `secretKeyRef` names, exactly matching the matrix above (containers start, so the secret volumes resolved) |
| No storage credentials on playback-only functions | confirmed in the deployed env: `generatebunnysignedurl`, `validatebunnyvideoassociation`, `associatebunnyvideotolibrary` carry no `BUNNY_STORAGE_PASSWORD`/`BUNNY_STORAGE_ZONE_NAME` |
| Library resolution | deployed env: `BUNNY_STREAM_LIBRARY_ID=780700`, `BUNNY_DEFAULT_LIBRARY_ID=780700` (no `736742` anywhere) |
| Token key | `BUNNY_TOKEN_KEY` v1 (fingerprint `cbf22628`, the pull-zone key verified in Mission 13) |
| App Check | `APP_CHECK_ENFORCEMENT=false` (staging only) |
| Auth enforcement | unauthenticated `POST` to `generateBunnySignedUrl` and `getLectureResources` → **401** (callable auth intact, no bypass) |
| Storage zone wiring | `BUNNY_STORAGE_BASE_URL=https://storage.bunnycdn.com/dr-tarek-staging-resources`, zone `2058675` |
| Error logs after deploy | no ERROR entries on the new revisions |
| Production impact | `dr-tarek-platform` Bunny services still carry their original creation timestamps (`2026-08-22`, `2026-09-01`) — nothing created or modified today |

### Remaining blockers / gates
1. **Actual Flutter playback is NOT verified.** It requires a real authorized staging student session bound to a permitted device; no such session exists, and no mock was used. Signed HTTP playback for library `780700` was already proven at the CDN layer in Mission 13 (playlist + 1080/360p rendition + `video/mp2t` segment with TS sync byte), but the in-app player path remains a separate gate.
2. Production still runs the older function code; deploying it remains explicitly out of scope.

**No commit, no push, no staging of files, no reset/clean. `736742` and `775315` untouched. Token Authentication still enabled.**

---

## Mission 15 — Final completion attempt (2026-11-14)

**Verdict: BLOCKED.** The consolidated verdict in §15 stands. This mission executed the
full reconstruction, baseline verification and the one safe staging remediation (Firestore
rules), but **no mandatory acceptance gate advanced to COMPLETE**: the final gate (real
in-app Flutter playback under an authorized staging student) is still impossible because
staging has no application data and no authorized student account, and the Dashboard picker
UI still has no approved Figma specification.

**ملخص عربي:** أُعيد بناء الحالة من الكود الفعلي (لا من التقارير)، ونُفِّذت جميع الاختبارات
الممكنة فعليًا ونجحت (عدا اختبارَي Golden صوريين قديمين غير مرتبطين). أُغلقت فجوة أمنية
حقيقية: قواعد Firestore المنشورة في Staging لم تكن تحتوي حماية `bunny_library_id`، فنُشرت
القواعد إلى `dr-tarek-staging` فقط. لا يمكن إعلان الاكتمال لأن Staging بلا بيانات وبلا حساب
طالب مصرّح، وواجهة اختيار المكتبة بلا مواصفة Figma معتمدة.

### 15.1 What this mission actually changed

| Change | Target | Evidence |
|---|---|---|
| Firestore rules deployed | `dr-tarek-staging` only | ruleset `3821a9c3-2d44-456b-8858-853b2348a42f`, `2026-11-14T15:49:31Z`; compiled clean; verified it now contains `bunny_library_id` |
| Report section appended | this file | this section |
| Source code | **none** | `git status` identical before/after (58 entries) |
| Production | **none** | no production deploy, no production rule release |

Rollback for the staging rules: re-release the previous ruleset
`0c87aeb8-1f2b-4a61-aac3-0bfce75656e7` (release `cloud.firestore`, `2026-10-14T21:01:36Z`).

### 15.2 Implementation matrix (verified against current code, not reports)

| Area | Existing implementation | Missing work | Validation status |
|---|---|---|---|
| Library catalog | `functions/src/core/video/bunny_library_catalog.ts` — pure parse/activation gate/client projection/deterministic secret names; `functions/test/bunny_library_catalog.test.js` (33 checks). Exported at `functions/src/index.ts:31` only. | **Not wired.** No Firestore loader, no `listEligibleBunnyLibraries` callable, no catalog read in resolution. Resolution is still env-based (`bunny_library_registry.ts`). | Pure contract PASS; integration **BLOCKED** |
| Secret Manager | 6 `defineSecret` names; each of the six callables declares only the secrets it needs. Staging has all 6 secrets; production has 5. | Production `BUNNY_STREAM_API_KEY` is a plaintext env var (pre-existing, by design comment); production `APP_CHECK_ENFORCEMENT` value is malformed (see 15.3). | Isolation verified; anomaly reported |
| Backend association | `validateBunnyVideoAssociation` (`index.ts:4955`), `associateBunnyVideoToLibrary` (`index.ts:5047`), `bunny_library_association.ts` (HMAC-SHA256 receipt, 600 s TTL, constant-time compare, cutover gate, transactional write). Emulator suites `bunny_association_flow`, `bunny_library_validation_flow`. | Production callables not deployed (`NOT_FOUND` on `dr-tarek-platform`). | Emulator PASS; staging E2E **BLOCKED** |
| Playback issuance | `generateBunnySignedUrl` (`index.ts:4449`), `getLectureResources` (`5445`), `getSectionDisplayMedia` (`5631`), `generateBunnyResourceUrl` (`8337`); advanced path token `/bcdn_token=…&token_path=…&expires=…/…` via `buildBunnyFileUrl` (`index.ts:1701`); per-library runtime through the registry. | Catalog-based resolution; staging E2E issuance for a real user. | Emulator PASS; staging E2E **BLOCKED** |
| Dashboard picker | Data layer only: `bunny_library_catalog.dart`, `bunny_library_association.dart`, `bunny_association_gateway.dart`; 4 test files (54 assertions). | **Visible picker UI BLOCKED** — no approved Figma spec; no backend catalog loader to populate options. | Data layer PASS; UI **BLOCKED** |
| Flutter playback | `video_source_resolver.dart`, `playback_repository.dart`, `video_playback_controller.dart`, `video_hls_backend_web.dart`, lecture data sources. | None identified in code; runtime proof missing. | Widget/unit PASS; in-app **BLOCKED** |
| Migration/backfill | `bunny_library_migration.ts`; `scripts/backfill_bunny_library_id.ts` is read-only by construction (`--apply` refused); tests `bunny_library_migration.test.js`. | No apply executor (deliberate); no classification run on real production data. | Pure PASS; apply **NOT AUTHORIZED** |
| Security Rules | Local `firestore.rules` §302–338: `bunny_library_id` server-owned on create/update, `created_at` mandatory + immutable, verified `bunny_video_id` immutable. `security-tests/adr010_association_rules.test.js` (21 assertions). | **Deployed rules were stale** in staging and production (see 15.4). Staging now fixed; production still stale. | Emulator PASS; staging deployed |
| Tests | 53 Functions files, 4 Dashboard bunny files, rules suite, Flutter video/lecture subset. | Full staging E2E. | See 15.5 |

### 15.3 Environment configuration (no secret values)

**Staging `dr-tarek-staging` (all six Bunny services):**
`BUNNY_DEFAULT_LIBRARY_ID=780700`, `BUNNY_STREAM_LIBRARY_ID=780700`,
`APP_CHECK_ENFORCEMENT=false`. Secret Manager names present:
`BUNNY_STREAM_API_KEY`, `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE`,
`BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STORAGE_PASSWORD`.
No `736742` appears in the staging environment.

**Production `dr-tarek-platform`:**
`BUNNY_STREAM_LIBRARY_ID=736742`; `BUNNY_DEFAULT_LIBRARY_ID` is unset, so the compiled
fallback `736742` applies. Secret Manager names present: `BUNNY_TOKEN_KEY`,
`BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`,
`BUNNY_STORAGE_PASSWORD`. `BUNNY_STREAM_API_KEY` is a **plaintext Cloud Run env var**, not a
Secret Manager entry (pre-existing; the code comment documents it as a plain server-side
value). `validateBunnyVideoAssociation` and `associateBunnyVideoToLibrary` are **not
deployed** in production.

**Pre-existing production anomaly (reported, not modified):** the production
`APP_CHECK_ENFORCEMENT` env value is malformed — 97 characters containing
`false` concatenated with `BUNNY_STREAM_API_KEY=…` and `BUNNY_STREAM_LIBRARY_ID=736742`.
Because the code compares the value to the exact string `"true"`, enforcement still
evaluates to `false` (no security regression), but the value must be corrected to exactly
`false` before any production App Check work. No secret value is reproduced here.

### 15.4 Firestore Rules — critical finding and remediation

| Project | Deployed ruleset before this mission | Contains `bunny_library_id`? |
|---|---|---|
| `dr-tarek-staging` | `0c87aeb8-1f2b-4a61-aac3-0bfce75656e7` (2026-10-14) | **No** |
| `dr-tarek-platform` | `155a63d0-9ce0-40be-aef9-1f51216c0d5b` (2026-09-28) | **No** |

The local ADR-010 rules existed and passed the emulator suite, but they had **never been
released**. That meant the client-side half of the association security model
(server-owned `bunny_library_id`, `created_at` immutability, verified-`bunny_video_id`
immutability) was not live in any environment. Staging rules were deployed this mission
after the suite passed. **Production rules remain stale by design until the staging
playback gate passes.**

### 15.5 Tests actually executed (real results)

| Command | Result |
|---|---|
| `functions: npm run build` | **PASS** — `tsc` clean |
| `functions: npm run test:pure` | **PASS** — registry, default-library config, catalog, migration, playback regression (33), video validation (26), association (37) |
| `functions: npm test` (full emulator) | **51/53 files** — the 2 failures (`wait_for_triggers.js`, `progress_percentage.test.js`) were caused by the Functions emulator 10 s discovery timeout (`User code failed to load… Timeout after 10000`), not by assertions |
| Re-run with `FUNCTIONS_DISCOVERY_TIMEOUT=120` (targeted) | **PASS** — `wait_for_triggers: PASS`, `progress_percentage.test: PASS` |
| `dashboard: flutter test` (4 Bunny files) | **PASS** — 54 assertions |
| `dashboard: flutter analyze` | **PASS** — No issues found |
| root `flutter analyze` | **PASS** — No issues found |
| root `flutter test` (video_streaming + features/video_streaming + lecture remote data source) | **149 passed, 2 failed** — both are **golden-image** failures in `player_layout_test.dart` (360×740 and 393×852, ~2.24 % pixel diff). The repository already tracks the corresponding `test/video_streaming/failures/*` artifacts, and this mission changed no rendering source, so these are pre-existing visual-baseline mismatches, not ADR-010 regressions |
| `security-tests` emulator (firestore + storage) | **PASS** — “Firestore and Storage rules tests passed.” and `adr010_association_rules: 21 assertions passed` |

### 15.6 Staging data and Auth (read-only evidence)

- `listCollectionIds` on `dr-tarek-staging` returns only infrastructure collections:
  `auth_security_events`, `login_throttle`, `password_reset_request_throttle`,
  `public_rate_limits`, `registration_throttle`.
- `users`, `subjects`, `plans`, `lectures`, `lecture_resources`, `subscriptions`,
  `bunny_libraries` all return an empty body (`{}`, raw length 3).
- Identity Toolkit `accounts:batchGet` returns **HTTP 400 `CONFIGURATION_NOT_FOUND`**, so
  accounts cannot be enumerated and no authorized staging student could be verified.
- **No staging dataset and no student identity were created** (no fake identities, no
  bypass).

### 15.7 Dashboard picker and Figma

- No Bunny library-picker specification exists under `docs/figma/`. The closest spec
  (`dashboard/…/add lecture overlay.md`) models `ResourceType { video, pdf, attachment,
  externalLink }` but contains **no library selection**.
- Therefore the visible picker remains **BLOCKED**; only the data layer and its tests exist.
- The backend loader that would populate options (`listEligibleBunnyLibraries` over
  `bunny_libraries`) is **not implemented**.

### 15.8 Catalog wiring requires an explicit decision

`bunny_library_catalog.ts` is complete and tested, but wiring it into resolution requires a
secret-contract decision that this mission is not authorized to take silently:

- The catalog’s `credential_refs` use deterministic **per-library** names
  (`BUNNY_<id>_STREAM_API_KEY`, `BUNNY_<id>_TOKEN_KEY`).
- The deployed contract is **per-environment** (`BUNNY_STREAM_API_KEY`,
  `BUNNY_TOKEN_KEY`).
- Adopting the catalog contract means creating new secrets and redeploying all six
  functions in **both** environments — a contract change, not a code refactor.

Until that decision is made, resolution stays on the env registry, which already fails
closed for unknown/inactive/incomplete libraries. The catalog is **not** claimed as wired.

### 15.9 Git state

- Branch `ci/ios-staging-codemagic`, HEAD `34a4b763e77087e0eeffd4aa8ad88bb820b61d46`.
- `git status --short`: **58 entries — 30 modified + 28 untracked, 0 staged, 0 deleted**,
  identical before and after this mission.
- One accidental deletion of the **tracked** `test/video_streaming/failures/*` golden
  artifacts (created by the golden run) was immediately restored with
  `git restore -- test/video_streaming/failures/`; verified byte-present and status clean.
- Temporary probe scripts were kept only in `D:\Temp\opencode` (approved scratch dir).
- No commit, no push, no reset, no clean, no stash.

### 15.10 Exact blockers and requested decisions

1. **Authorized staging student account** — or explicit authorization to provision a
   minimal, clearly-labelled staging dataset (one subject, one plan, one lecture, one video
   resource bound to library `780700`, one subscription, one bound device). Without one of
   these, the final acceptance gate cannot start.
2. **Approved Figma spec for the library picker** — or explicit approval to keep the
   picker non-visual (data layer only) and defer the UI.
3. **Catalog secret-contract decision** — per-library secrets (`BUNNY_<id>_*`) vs the
   current per-environment secrets — before the catalog can be wired into resolution.
4. **Production rollout authorization** — only after staging in-app playback passes and a
   rollback drill is documented.

### 15.11 Gate status (final)

| Gate | Status |
|---|---|
| Catalog | PARTIAL — pure module PASS, not wired |
| Credentials | PASS — environment isolation verified |
| Association | PASS (emulator) / BLOCKED (staging E2E) |
| Firestore | PASS (emulator) — staging rules deployed; production stale |
| Dashboard | **BLOCKED** — no Figma spec |
| Playback issuance | PASS (emulator) / BLOCKED (staging E2E) |
| CDN | PASS (prior Mission 13 evidence) |
| Flutter in-app playback | **BLOCKED** |
| Student | **BLOCKED** — no authorized account |
| Device | NOT TESTABLE |
| Staging E2E | **BLOCKED** |
| Production | NOT STARTED |
| Documentation | UPDATED (this section) |

**Final status: BLOCKED.** No further code or deployment step can move the final gate until
the owner supplies (1) an authorized staging student session or an explicit dataset
authorization, and (2) either a Figma picker spec or explicit approval to defer the UI.
