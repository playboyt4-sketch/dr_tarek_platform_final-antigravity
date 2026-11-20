# Mission 10 — Option A Readiness, Repository Integrity & Bunny Environment Drift Audit

**Date:** 2026-11-13
**Mode:** AUDIT AND PLANNING ONLY. No code, config, secret, Bunny setting, Firestore data, Rules, or deployment was changed. Nothing was staged, committed, reverted or discarded.
**Baseline:** `HEAD = 34a4b763e77087e0eeffd4aa8ad88bb820b61d46`.

---

## 1. Executive verdict

**Repository integrity: INTACT and larger than the handoff claimed.** The working tree contains **30 tracked modified files** (1,246 insertions / 136 deletions) plus a substantial untracked set (reports, the ADR-010 module directory, new tests and Dashboard domain files). The "two changed files" in the handoff is **incorrect**; the two-file figure matches only the two *most recently touched* files. Nothing was lost, staged or reverted.

**Option A: technically unblocked, organizationally not approved.**
Mission 9S removed the only technical unknown: `ZoneSecurityKey` is returned unmasked by `GET /pullzone/{id}` and is the same key Stream token authentication uses (fingerprint MATCH, 200/403/403 probe matrix). Therefore the token signing key can be provisioned programmatically. Option A remains blocked on **owner decisions** (catalog as source of truth, account-key custody, receipt-key separation, activation policy) and on **two runtime behaviours not yet proven**: whether `GET /videolibrary/{id}` returns `ApiKey`/`ReadOnlyApiKey` unmasked, and whether `PUT /videolibrary/{id}` token-auth enablement behaves as documented.

**Staging drift: real, and more dangerous than "wrong library id".**
`functions/.env.dr-tarek-staging` targets library `780700` (an intentional staging test library per `docs/IOS_STAGING_ENVIRONMENT_PLAN.md`) while the code's `DEFAULT_BUNNY_LIBRARY_ID` is hardcoded `"736742"`. The registry derives the *canonical* library id from code and the *Stream API* library id from `BUNNY_STREAM_LIBRARY_ID`. In staging that produces a **split identity**: `libraryId = 736742` (label used for registry/activation decisions) with `apiLibraryId = 780700` (actual metadata source), and playback runtime reading the staging template/key. Staging also has an **empty** `BUNNY_PLAYBACK_URL_TEMPLATE` locally, so playback fails closed — which masks the split rather than fixing it.

**No implementation, no repair, no activation was performed. `775315` remains inactive.**

---

## 2. Repository integrity snapshot

| Check | Result |
|---|---|
| `git rev-parse HEAD` | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` |
| `git diff --cached --stat` | **empty** — nothing staged |
| `git diff --name-only` | **30** files |
| `git diff --stat` | 30 files changed, 1,246 insertions(+), 136 deletions(−) |
| `git status --short` | 55 entries (30 modified + 25 collapsed untracked directories) |
| `git status --porcelain -uall` | **96** entries |
| Untracked top-level items | `reports/`, `21_ADR_010_Multi_Library_Bunny_Stream.md`, `functions/src/core/video/`, `functions/src/scripts/backfill_bunny_library_id.ts`, 13 `functions/test/*.js`, `security-tests/adr010_association_rules.test.js`, 5 `dashboard/test/*.dart`, 4 `dashboard/lib/.../domain/*.dart` + `bunny_association_gateway.dart`, `test/features/...` |

Interpretation of the "two changed files" claim: the two **most recently modified** tracked files are `scripts/backfill_first_video.cjs` (13:02) and `functions/test/first_video_backfill.test.js` (13:03) — both part of the Mission 4 `bunny_library_id` projection work. Every other tracked modification predates them. There is no two-file subset that represents the working tree.

Untracked reports were inspected separately (they are deliverables, not code): the `reports/adr010/` directory holds Missions 2–10, inventory, readiness, security reviews and test-strategy documents. They are untracked by design (no commit has been made since `34a4b76`).

---

## 3. Exact changed-file inventory

**A. ADR-010 backend (Mission 4/5/7) — 1,000+ lines**

| File | Change |
|---|---|
| `functions/src/index.ts` | +577/−? : library registry wiring, `associateBunnyVideoToLibrary`, receipt signing/verification, cutover gate in issuance and display media, per-library metadata runtime, validation callable expansion |
| `firestore.rules` | +33/−? : `lecture_resources` server-owned `bunny_library_id`, immutable `created_at`, immutable `resource_type`, verified-`bunny_video_id` immutability |
| `functions/package.json`, `security-tests/package.json` | test script registration (`test:pure`, ADR-010 suites) |
| `.github/workflows/ci.yml` | +49: ADR-010 emulator job |
| `functions/test/{first_video_backfill,playback_session,progress_percentage,protected_content,run_all}.js`, `security-tests/rules.test.js` | fixtures/assertions aligned with the new contract (GUIDs, `created_at`, `status`, `bunny_library_id`) |
| `scripts/backfill_first_video.cjs` | additive `bunny_library_id` in the `first_video` projection and in `sameFirstVideo` |

**B. Dashboard (Mission 3/4)** — `subject_details_provider.dart` (+136), `add_lecture_overlay.dart` (+52), `add_lecture_resources.dart` (+32), `quick_upload_modal.dart` (+25), `home_stats_provider.dart`, grade/join-application providers and screens, `lecture_publish_visibility_test.dart`; new untracked `bunny_association_gateway.dart`, `bunny_library_association.dart`, `bunny_library_catalog.dart` + 5 tests.

**C. Flutter (Missions 3/4)** — `admin_content_remote_data_source_impl.dart` (+144), `video_source_resolver.dart`, `playback_entities.dart`, `subject_learning_entities.dart`, `video_playback_controller.dart`; new untracked `test/features/video_streaming/`, `test/features/content_authoring/...`.

**D. New untracked backend module** — `functions/src/core/video/`: `bunny_library_registry.ts` (320 lines), `bunny_library_association.ts` (337), plus migration/validation modules and 13 test suites.

**E. Incidental** — `dashboard/.firebase/hosting.YnVpbGRcd2Vi.cache` (build cache, +48/−?), regenerated by a build.

No file in this inventory was modified by Mission 10.

---

## 4. Staging drift findings

Source of truth for staging intent: `docs/IOS_STAGING_ENVIRONMENT_PLAN.md` §4–§5 ("Bunny test credentials + test video in **780700** (6 media functions excluded by design)", "prod values must NOT be copied").

| # | Question | Finding | Evidence |
|---|---|---|---|
| 1 | Is `780700` intentionally reserved for staging? | **YES** | `docs/IOS_STAGING_ENVIRONMENT_PLAN.md:62`; Bunny dashboard lists `780700` = "DrTarek-Staging-Test", 0 videos |
| 2 | Does its Stream API key exist and is it valid? | **EXISTS — validity NOT VERIFIED** | `BUNNY_STREAM_API_KEY` present in `functions/.env.dr-tarek-staging` (name only). No live Stream API call was made in this mission |
| 3 | Is token authentication enabled on `780700`? | **NOT VERIFIED** | Requires a Pull Zone read on `780700`'s zone; no API call was authorized in Mission 10 |
| 4 | Does its Pull Zone belong to `780700`? | **NOT VERIFIED** | Same reason; no dashboard/API identity check performed for `780700` |
| 5 | Is its token key configured? | **YES (name-level)** | `BUNNY_TOKEN_KEY` exists in `functions/.env.dr-tarek-staging` (36 chars) and as a Secret Manager secret in `dr-tarek-staging`; its fingerprint differs from production's (`e1a3ddca` vs `af89b2a5`, computed in Mission 9S) |
| 6 | Can its playback host/template be resolved? | **NO (locally)** | `BUNNY_PLAYBACK_URL_TEMPLATE` in `functions/.env.dr-tarek-staging` is **empty** (length 0). The staging Secret Manager secret with the same name exists, so a value may exist there — RUNTIME-UNVERIFIED |
| 7 | Is the empty template intentional or a defect? | **DEFECT / incomplete provisioning** (high confidence) | `resolveBunnyPlaybackRuntime` requires a non-empty template; with `""` every staging issuance fails `incomplete_configuration`. Nothing in the staging plan says playback should be disabled |
| 8 | Does any staging path silently fall back to production `736742`? | **YES — structurally, and in a subtler way than "wrong id"** | `DEFAULT_BUNNY_LIBRARY_ID = "736742"` is a code constant (`bunny_library_registry.ts:26`), `isDefault` bypasses `BUNNY_ACTIVE_LIBRARY_IDS`, and legacy rows (no `bunny_library_id`) always resolve to `736742` (`resolveBunnyLibraryForResource`, `source: "legacy_default"`). In staging, `BUNNY_STREAM_LIBRARY_ID=780700` becomes `apiLibraryId` while `libraryId` stays `736742`, so metadata calls target `780700` under a `736742` label |

Additional staging observations:

- Secret Manager in `dr-tarek-staging` now holds `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_PASSWORD`, `BUNNY_STORAGE_ZONE_NAME` (names only). This contradicts the 2026-10-14 plan entry "5 Secret Manager secrets absent" — the drift is *stale documentation*, not missing secrets.
- Both projects expose the **same five secret names**. Same names + different values is the hazard that produces cross-environment leakage when a `.env` file is deployed to the wrong project.
- `functions/.env.dr-tarek-staging` declares `BUNNY_PLAYBACK_URL_TEMPLATE` as an environment variable while the same name is also a Secret Manager secret. Having one name in two provisioning mechanisms is a **shadowing hazard** (it is not documented which wins; the empty local value is the more dangerous one).
- `functions/.env` (prod-bound) has only `APP_CHECK_ENFORCEMENT`, `BUNNY_STREAM_API_KEY`, `BUNNY_STREAM_LIBRARY_ID`; no token key or template, so a local run fails closed. This is correct.
- `BUNNY_ACTIVE_LIBRARY_IDS` and `BUNNY_LEGACY_LIBRARY_FALLBACK` appear in **neither** env file, so the legacy fallback is ON in both environments and the default library is always active.

---

## 5. Root-cause analysis

| # | Root cause | Category | Explains |
|---|---|---|---|
| RC1 | Default library id is a **compiled constant** (`"736742"`), not configuration | Repository/code | Any environment whose real library differs still labels itself `736742` |
| RC2 | `BUNNY_STREAM_LIBRARY_ID` is overloaded: it is the *Stream API path id* for the default library, yet operators read it as "the platform's library" | Repository/config design | Staging sets it to `780700` and believes it has switched libraries, while canonical identity stays `736742` |
| RC3 | Library activation and credentials are **deploy-time env/secrets**, not catalog data | Architecture (documented in Mission 8 §D) | Every new library is a redeploy; env files drift silently |
| RC4 | `functions/.env.dr-tarek-staging` was hand-provisioned for a test library without a completed template | Repository configuration | Empty template + realistic-looking key = a half-configured environment |
| RC5 | Staging docs were written before secrets existed and never updated | Documentation drift | "5 secrets absent" is false today |
| RC6 | Same secret names in two projects with no environment marker | Secret Manager hygiene | A wrong `--project` or copied `.env` silently uses production values in staging (or vice versa) |
| RC7 | No per-environment guard on startup for known-inconsistent config | Runtime | Nothing logs "canonical id ≠ api id" at boot |

---

## 6. Drift repair plan (no item implemented)

### 6.1 Repository configuration drift

| Field | Detail |
|---|---|
| File | `functions/.env.dr-tarek-staging` |
| Current | `BUNNY_STREAM_LIBRARY_ID=780700`; `BUNNY_PLAYBACK_URL_TEMPLATE=` (empty); `BUNNY_TOKEN_KEY` for the staging zone |
| Expected | Consistent set for `780700`: its real playback host template, its own token key, and `BUNNY_STREAM_LIBRARY_ID=780700`, with **no** ambiguity about the canonical id |
| Root cause | RC1 + RC2 + RC4 |
| Smallest correction | (a) Fill `BUNNY_PLAYBACK_URL_TEMPLATE` with `https://<780700 system hostname>/{video_id}/playlist.m3u8`; (b) remove the duplicated template from the `.env` file **or** from Secret Manager (one mechanism only); (c) add an explicit `BUNNY_DEFAULT_LIBRARY_ID=780700` override **after** the code gains one (see 6.5) |
| Environment | Staging only |
| Production impact | None if and only if the file is never used for a production deploy (it is project-scoped, but `firebase deploy` ships the matching `.env.<project>` file) |
| Required tests | `resolveBunnyPlaybackRuntime` returns ok for staging env; signed probe 200, unsigned 403, wrong key 403 on `780700`'s zone; metadata call resolves `780700` without touching `736742` |
| Rollback | Restore the current empty template (fails closed), or delete `functions/.env.dr-tarek-staging` and rely on Secret Manager only |

### 6.2 Secret Manager drift

| Field | Detail |
|---|---|
| Secret names | `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE` (both projects) |
| Current | Identical names in `dr-tarek-platform` and `dr-tarek-staging`, different values (fingerprint proof for the token key) |
| Expected | Same names are acceptable **only** with a documented environment contract; simplest safe form is identical names + a hard deploy guard (see 6.5) plus a staging-only name suffix if isolation is preferred |
| Root cause | RC6 |
| Smallest correction | Keep names, add a pre-deploy assertion that the target project's `BUNNY_TOKEN_KEY` fingerprint equals the expected library's fingerprint (fingerprint only — never the value) |
| Environment | Both |
| Production impact | Guard only; no value change |
| Required tests | Deploy dry-run asserts fingerprints; a deliberately wrong mapping aborts |
| Rollback | Disable the guard step (it is additive) |

### 6.3 Bunny account configuration drift

| Field | Detail |
|---|---|
| Object | Library `780700` + its Pull Zone |
| Current | `780700` exists with 0 videos; zone identity, `ZoneSecurityEnabled`, hostname and key are **unverified** |
| Expected | Staging library must mirror production's protection model: token auth enabled, known hostname, known key, referer behaviour documented |
| Root cause | RC4 (provisioned for existence, not for verification) |
| Smallest correction | Read-only: `GET /videolibrary/780700` → `GET /pullzone/{id}` (account key, same two-call pattern authorized in 9S), then the signed/unsigned/wrong-key probe matrix |
| Environment | Bunny account (staging library) |
| Production impact | None (read-only) |
| Required tests | The 9S matrix on `780700` |
| Rollback | Not applicable (read-only) |

### 6.4 Runtime environment drift

| Field | Detail |
|---|---|
| Where | Deployed `dr-tarek-staging` functions (media functions are **not deployed** there by design) |
| Current | 6 media functions absent in staging; `BUNNY_*` secrets exist; template value at runtime unknown |
| Expected | Either deploy the media functions with a complete staging config, or document explicitly that staging cannot play video |
| Root cause | RC4 + RC5 |
| Smallest correction | Decide the intent (play vs no-play), then align secrets + deploy scope. No code change required for "no-play" |
| Environment | Staging |
| Production impact | None |
| Required tests | `generateBunnySignedUrl` absent (current) or present and returning 200/403 correctly |
| Rollback | Remove the functions from staging |

### 6.5 Code-level hardening (required for Option A, not part of the repair)

| Field | Detail |
|---|---|
| File | `functions/src/core/video/bunny_library_registry.ts` |
| Current | `DEFAULT_BUNNY_LIBRARY_ID = "736742"` compiled constant; no environment assertion |
| Expected | After the catalog exists: default comes from catalog/env, and a boot-time invariant logs/throws when `BUNNY_STREAM_LIBRARY_ID` ≠ the default library's id |
| Root cause | RC1 + RC2 + RC7 |
| Smallest correction | Add the invariant check first (pure function + unit test); move the constant into configuration in Phase 2 |
| Environment | All |
| Production impact | Detection only (no behaviour change) if implemented as a startup warning |
| Required tests | Unit: mismatch produces the documented failure; match produces silence |
| Rollback | Revert the single invariant call |

### 6.6 Documentation drift

`docs/IOS_STAGING_ENVIRONMENT_PLAN.md` §4 (secrets absent) and §5 (open item 2: "Bunny test credentials + test video in 780700") are stale: secrets now exist, and the test video does not (0 videos). Correction: update that section **after** the staging intent is confirmed by the Owner.

---

## 7. Option A target architecture

**Non-negotiables carried from ADR-010 / Mission 4:** server-owned `bunny_library_id`, HMAC receipts bound to (resource, lecture, library, video), immutable `created_at`, fail-closed resolution, per-library credential isolation, unchanged playback authorization (subscription, deny list, subject access, feature matrix, device tier, rolling window, quality matrix, playback sessions), no client-side credentials or URL construction.

### 7.1 Firestore catalog (proposal — **not** in the approved schema)

`bunny_libraries/{libraryId}` — server-only, no client reads:

| Field | Type | Source |
|---|---|---|
| `library_id` | string (= doc id) | account API `Id` |
| `display_name` | string | account API `Name` |
| `status` | `pending_verification` \| `active` \| `disabled` \| `error` | platform |
| `pull_zone_id` | number | `videolibrary.PullZoneId` |
| `playback_host` | string (system hostname only) | `pullzone.Hostnames[]` |
| `token_auth_enabled` | bool | library/Pull Zone field |
| `token_auth_verified` | bool | signed-200/unsigned-403/wrong-key-403 probe |
| `credential_refs` | map (names only) | `{stream_api_key, token_key}` |
| `verification` | map | `{verified_at, verified_by, probe_version}` |
| `last_error_code` | string \| null | stable platform code |
| `created_at`, `updated_at` | timestamps | server |

Status: **proposal only.** `05_DATABASE.md` (root) is a deprecated pointer; the approved baseline is `05_DATABASE_v1.7.md` and the proposed 1.8 lives in `docs/notion/`. Neither contains a `bunny_libraries` collection, so adding it is a **database-change decision**, not an implementation detail (see §14, D1). No field may be finalized before that decision.

### 7.2 Resolver evolution (minimal, provable)

Keep `bunny_library_registry.ts` pure and synchronous. Add an async adapter that builds the *same* env-shaped snapshot for exactly one library from catalog + Secret Manager, then calls the existing pure resolvers. This keeps every current unit test and fail-closed branch valid, and keeps cross-library materialisation impossible.

### 7.3 Callables

`listEligibleBunnyLibraries` (content manager), `registerBunnyLibrary`, `verifyBunnyLibrary`, `disableBunnyLibrary`, `rotateBunnyLibraryCredentials` (Owner only). Existing `validateBunnyVideoAssociation`, `associateBunnyVideoToLibrary`, `generateBunnySignedUrl` keep their contracts; only their internal resolution source changes. No callable returns a secret, a credential reference, a template, a host, or a Bunny error body.

### 7.4 Receipt key separation

Today `signBunnyAssociationReceipt` / `verifyBunnyAssociationReceipt` use `getEnv("BUNNY_TOKEN_KEY")` (`index.ts:4978`, `4987`, `5082`). That couples platform receipts to a rotatable playback credential. Introduce `BUNNY_ASSOCIATION_RECEIPT_KEY` with a 10-minute dual-verify window. Decision required (§14, D4).

### 7.5 Playback independence

Playback must resolve from **cached catalog metadata + injected secrets only**. No live account-API call on the playback path; an account-API outage may only block *provisioning*, never issuance.

---

## 8. Secret Manager strategy

| Credential | Scope | Where it lives | Who reads it | Rotation |
|---|---|---|---|---|
| Account API key | Whole Bunny account (no scoped keys exist today) | New secret, e.g. `BUNNY_ACCOUNT_API_KEY` | Provisioner only (separate IAM principal if possible) | Manual, Owner-approved; audit every access |
| Per-library Stream key | One library; prefer `ReadOnlyApiKey` | `BUNNY_<LIB>_STREAM_API_KEY` | Metadata/validation path | `POST /videolibrary/{id}/resetApiKey` (204, no body) then re-read — **runtime behaviour unverified** |
| Per-library token key | One pull zone | `BUNNY_<LIB>_TOKEN_KEY` (today `BUNNY_TOKEN_KEY` for 736742) | Issuance + display media | `PUT /videolibrary/{id}` `ResetToken` then re-read `ZoneSecurityKey`; **would invalidate live signed URLs** |
| Association receipt key | Platform-only HMAC | `BUNNY_ASSOCIATION_RECEIPT_KEY` | Association validation | Dual-verify window; independent of Bunny |

Rules: values never enter Firestore, logs, callable responses, Flutter or Dashboard; the catalog stores **names** only; `@google-cloud/secret-manager` is **not yet a dependency** (`functions/package.json` has no `@google-cloud/*`), so Phase 2 adds a package — an explicit decision, not a silent install. IAM: `secretmanager.versions.access` for the runtime SA; `secretmanager.admin` only for the provisioning path.

---

## 9. Bunny provisioning flow (mapped to verified APIs)

| # | Step | API | Status |
|---|---|---|---|
| 1 | Authorized content manager submits a library id | callable | new |
| 2 | Discover the library | `GET /videolibrary/{id}` | **200 proven for 736742 (Mission 9S)** |
| 3 | Prove account ownership | same call: 403 = not this account | documented (Mission 8 C3), not exercised |
| 4 | Read the library's API keys | `videolibrary.ApiKey` / `ReadOnlyApiKey` | **schema-verified; masking UNVERIFIED** |
| 5 | Resolve Pull Zone + hostname | `GET /pullzone/{PullZoneId}` → `Hostnames[]` | **200 proven (Mission 9S)** |
| 6 | Read the token signing key | `pullzone.ZoneSecurityKey` | **PROVEN unmasked, 36 chars, MATCH (Mission 9S)** |
| 7 | Verify `VideoLibraryId == requested id` | pull zone field | **proven: `6414868 → 736742`** |
| 8 | Verify token authentication | `ZoneSecurityEnabled` + unsigned-403 probe | **proven enabled for 736742** |
| 9 | Store credentials in Secret Manager | — | new |
| 10 | Write non-secret catalog metadata | Firestore Admin SDK | new (needs DB decision) |
| 11 | Activate only after all checks pass | catalog `status` | new |

Failure handling: unknown id → `library_not_found`; foreign account → `library_not_owned` (403); token auth off → either enable via `PUT /videolibrary/{id}` (needs approval, see D3) or stay `pending_verification`; probe mismatch → `token_auth_verification_failed`. **No step ever falls back to another library.**

---

## 10. Referer compatibility findings

1. `BlockNoneReferrer = true` on `6414868` — confirmed by API in Mission 9S; a correctly signed request **without** Referer returns 403.
2. The app already sends a fixed header: `lib/core/constants/bunny_playback_headers.dart` → `Referer: https://dr-tarek-platform.web.app/`, attached to native playback sources (`test/video_streaming/first_video_startup_test.dart` asserts it on initial load, retry and quality change).
3. **Native (iOS AVPlayer / Android ExoPlayer):** headers are applied by the app → compatible.
4. **Flutter Web:** JavaScript cannot set `Referer`. The browser sends the page origin instead. Today's web build is served from `dr-tarek-platform.web.app`, which matches the fixed value; **any other origin** (a custom domain, a Firebase preview channel, `localhost:*` during development) will send a *different* Referer. Whether that is accepted depends on the zone's `AllowedReferrers` list, which Mission 9S **did not read** — it recorded only `BlockNoneReferrer`. This is the single largest unverified client risk.
5. Per-library requirement: a newly onboarded library must have its referer policy verified against (a) the fixed native header and (b) the actual web origin(s). `env_secrets_guide.md` already warns: "Do not configure a rule that only accepts a specific browser origin."
6. No player behaviour was changed in this mission.

Verification needed (read-only): read `AllowedReferrers` for `6414868`, and probe a signed URL with a foreign Referer and with a `localhost` Referer. Until then, web playback on non-`web.app` origins is **UNVERIFIED**.

---

## 11. Database and security impact

| Area | Impact | Notes |
|---|---|---|
| `lecture_resources` | **none** | Rules already enforce server-owned `bunny_library_id`, immutable `created_at`/`resource_type`, verified-`bunny_video_id` immutability (`firestore.rules:310-331`) |
| `bunny_libraries` (new) | **new collection** | Requires an ADR/DB amendment decision; rules must explicitly deny all client access (the default-deny catch-all already covers it, but an explicit block documents intent) |
| Indexes | none expected | Catalog lookups are by doc id |
| Existing fallback | unchanged | `BUNNY_LEGACY_LIBRARY_FALLBACK` untouched; cutover `2026-11-13T00:00:00.000Z` untouched |
| Secrets exposure | no change | catalog stores names only |
| Playback authorization | no change | subscription, deny, subject, feature matrix, device tier, window, quality, session gates stay before issuance (`index.ts` order verified) |
| Audit | additive | provisioning/rotation events into existing `admin_audit_log` + analytics pattern |
| Rules weakening | **none proposed** | |

---

## 12. Required tests (for implementation, not run now)

1. **Pure catalog/resolver:** eligibility matrix; fail-closed reasons; per-library isolation (no cross-library materialisation); default-vs-`BUNNY_STREAM_LIBRARY_ID` mismatch invariant.
2. **Provisioner (mocked HTTP):** 200/401/403/404/429/500; masked `ApiKey`; missing hostname; token auth off; probe mismatch; idempotent re-registration; no secret in any response or log line.
3. **Receipt separation:** dual-verify window; tamper/expiry/cross-binding; rotation of a library key must not invalidate receipts.
4. **Callable auth matrix:** student / content manager / Owner; `listEligibleBunnyLibraries` returns active+verified only.
5. **Emulator end-to-end:** register → validate → associate → sign → playback-session (mocked Bunny).
6. **Regression:** Mission 7 suites (`bunny_library_registry`, `bunny_library_association`, `bunny_association_flow`, `issuance_library_flow`, `bunny_video_validation`, `bunny_playback_regression`), `functions npm test` (51 files), `security-tests` rules suite, Dashboard `lecture_publish_visibility` / `bunny_library_persistence`.
7. **Live staging verification (post-implementation):** the Mission 9S matrix on the staging library, plus Referer variants (fixed app header, foreign origin, `localhost`).

---

## 13. Rollback plan

| Change | Rollback |
|---|---|
| Catalog + async resolver | `BUNNY_CATALOG_ENABLED=false` → resolver uses the static env registry (today's behaviour); catalog rows remain for audit |
| Receipt key separation | Keep the old key in the dual-verify window; revert the env binding |
| Provisioning callables | Undeploy the new callables; existing authoring path unaffected |
| Per-library secrets | Secrets are additive; deleting a version returns that library to `incomplete_configuration` (fail closed), not to another library |
| Staging repair | Restore the empty template (fails closed) or remove `functions/.env.dr-tarek-staging` |
| Any Bunny-side change | **Out of scope for now**; if token auth is ever toggled, the rollback is the same API call plus key re-read, with an explicit approval |

No step in this plan requires deleting data or rotating a production key.

---

## 14. Owner decisions still required

| # | Decision | Mission 9S effect | Status |
|---|---|---|---|
| D1 | Add a server-managed `bunny_libraries` catalog (DB amendment to the approved schema) | none — implied only that automation is *possible* | **REQUIRES APPROVAL** |
| D2 | Store an account-level API key in Secret Manager as the provisioning credential | 9S proved the *key type* can read the needed fields; it does **not** authorize storing it | **REQUIRES APPROVAL** |
| D3 | Allow the backend to enable CDN token authentication on newly registered libraries (`PUT /videolibrary/{id}`) | B.3 proved the key exists/reports correctly, not that auto-enablement is approved | **REQUIRES APPROVAL** |
| D4 | Introduce `BUNNY_ASSOCIATION_RECEIPT_KEY` (10-minute dual-verify) | independent of B.3 | **REQUIRES APPROVAL** |
| D5 | Use `ReadOnlyApiKey` (not `ApiKey`) for platform metadata | none | **REQUIRES APPROVAL** |
| D6 | Keep `BUNNY_ACTIVE_LIBRARY_IDS` as an emergency deny list | none | **REQUIRES APPROVAL** |
| D7 | Replace the hardcoded `DEFAULT_BUNNY_LIBRARY_ID="736742"` with configuration + startup invariant | **B.3 PASS makes the constant obsolete** — the zone identity can now be derived | **IMPLIED BY B.3, still needs approval to change code** |
| D8 | Drop the one-time manual token-key step from the admin UI | **IMPLIED BY B.3** — the key is API-readable | **IMPLIED (no separate approval needed if D1–D3 approved)** |
| D9 | Staging intent: does staging play video? (drives the drift repair) | none | **REQUIRES APPROVAL** |
| D10 | Allow the read-only staging verification of `780700` (2 API GETs + probes) | same pattern as 9S, but new authorization | **REQUIRES APPROVAL** |
| D11 | `775315` remediation (enable token auth, provision, register) | B.3 gives the *method*; activation is a separate decision | **REQUIRES APPROVAL — deliberately deferred** |
| D12 | Daily verification job + alert channel | none | **REQUIRES APPROVAL** |
| D13 | Figma scope for the picker and the admin library screen | none | **REQUIRES APPROVAL** |
| D14 | Playback during an account-API outage: cached credentials (recommended) vs fail closed | none | **REQUIRES APPROVAL** |
| D15 | May the platform ever create libraries (`POST /videolibrary`)? | none | **REQUIRES APPROVAL (recommend NO)** |

Mission 9S PASS is **not** approval for D1–D6, D9–D15; it only removes the technical blocker for D7–D8.

---

## 15. Recommended implementation order

1. **D9 + D10 first (cheap):** settle staging intent, then verify `780700` read-only (identity, token auth, hostname, key fingerprint, probe matrix). This turns the drift report from "hypothesis" into facts.
2. **D7 invariant:** add the `BUNNY_STREAM_LIBRARY_ID` vs canonical-id check as a pure function + unit test (detection only) — smallest change that would have caught the staging split.
3. **D1–D5 decisions recorded** as an ADR-010 amendment, including the `bunny_libraries` schema and the receipt key.
4. **Phase 2 – catalog + Secret Manager adapter** behind `BUNNY_CATALOG_ENABLED=false`; seed `736742` from existing env with byte-identical behaviour.
5. **Phase 3 – provisioner + callables** with mocked-HTTP tests and zero secret leakage.
6. **Phase 4 – wire existing flows** (validate / associate / issuance / display media) to the catalog; Mission 7 suites must pass unchanged.
7. **Phase 5 – Dashboard domain/gateway**; demote the static catalog to a test fixture; **Phase 6 UI only after approved Figma**.
8. **Phase 7 – rollout:** shadow verification, then enable the flag, then decide the fate of `BUNNY_ACTIVE_LIBRARY_IDS`.
9. **Referer hardening before any new library goes live:** read `AllowedReferrers`, prove web origins (custom domain, preview channel, localhost) are accepted or documented as unsupported.

---

## Appendix A — Verification limits of this mission

- No Bunny API request was made in Mission 10 (the account-key authorization in 9S was scoped to two GETs). Therefore `780700`'s Pull Zone identity, token-auth state and hostname are **UNVERIFIED**.
- `videolibrary.ApiKey` / `ReadOnlyApiKey` masking and `PUT /videolibrary/{id}` behaviour remain **RUNTIME-UNVERIFIED** (documented only).
- `AllowedReferrers` for `6414868` was not read; the web-origin risk is therefore open.
- Secret Manager values were not read in this mission; only names, and fingerprints already recorded in Mission 9S.
- Local `.env` files were read for variable **names** and for the template **length** only; no secret value was printed, logged or stored.
- Documentation set: `00_MASTER_ARCHITECTURE.md`, `07_FLUTTER_ARCHITECTURE.md`, `08_DEVELOPMENT_STANDARDS.md` **do not exist at the repository root**; `05_DATABASE.md`, `06_FIREBASE_ARCHITECTURE.md`, `09_TASKS.md`, `04_FEATURES.md`, `FINAL_DECISIONS.md` are deprecated pointers to `docs/notion/`. The authoritative database baseline is `05_DATABASE_v1.7.md` (with 1.8 proposed). This is itself documentation drift worth a separate decision.

**Stop point:** audit and plan complete. No implementation, no repair, no deployment, no staging. Awaiting Platform Owner approval.

---

## Appendix — Correction (2026-11-13, Mission 11 re-verification)

- §4 row 5 / §4 "Additional staging observations": the staging token-key fingerprint
  `e1a3ddca` is a **parsing artifact**, not a key. The local staging env value is empty and
  the staging Secret Manager secrets have **zero versions** (Mission 11 §4). Treat the
  staging credential state as "absent", not "present but different".
- §6.1/§6.2 remain valid, but the smallest correction is now smaller: the staging
  environment has **nothing** to repair value-wise — it needs provisioning, not correction.
- §10 Referer risk is **closed**: both zones (`6414868`, `6807898`) have
  `AllowedReferrers = []` + `BlockNoneReferrer = true`, so any non-empty Referer is accepted
  (Mission 11 §6). The remaining failure mode is a client that strips the Referer.
