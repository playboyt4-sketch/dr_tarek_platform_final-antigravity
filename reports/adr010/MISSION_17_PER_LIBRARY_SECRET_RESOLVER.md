# ADR-010 — Mission 17: Per-Library Secret Manager Resolver

**Scope:** code only, Staging-targeted. No deployment, no Production access, no
catalog seeding, no Rules change, no IAM change, no secret creation or rotation.

**Branch:** `ci/ios-staging-codemagic`
**HEAD (unchanged):** `34a4b763e77087e0eeffd4aa8ad88bb820b61d46`

---

## 1. Preflight findings

The preflight was completed before any edit. Findings that shaped the design:

1. **The catalog schema is already implemented and is authoritative.**
   `bunny_libraries/{libraryId}` carries `status`, `token_auth_enabled`,
   `token_auth_verified`, `pull_zone_id`, `playback_host`, `display_name`,
   `source`, `config_version` and `credential_refs: {stream_api_key, token_key}`.
   Mission 8's hyphenated secret names and `token_auth_enforced` are **superseded**
   by this implemented schema; that is a documentation reconciliation, not a new
   architecture decision, so it did not trigger a stop condition.
2. **`credential_refs` contains names, never values.** `parseBunnyCatalogEntry`
   already drops any non-conforming key, and `isBunnyCatalogEntryUsable` already
   enforces active + token-auth-enabled + probe-verified.
3. **The naming convention already exists in code**:
   `bunnySecretNames(libraryId)` returns `BUNNY_<id>_STREAM_API_KEY` and
   `BUNNY_<id>_TOKEN_KEY`. Mission 17 therefore had a deterministic, testable
   contract to verify catalog rows against — no schema change was needed.
4. **There was no Secret Manager integration in the Functions runtime.** The only
   Bunny secrets were *mounted* (`defineSecret` → `SECRET_BUNNY_STREAM_API_KEY`,
   `SECRET_BUNNY_TOKEN_KEY`), i.e. a single global credential pair. Per-library
   resolution requires runtime reads, which is why `@google-cloud/secret-manager`
   was added.
5. **The registry is a compiled allow-list**, and `isBunnyLibraryActive` gates
   every non-default library on `BUNNY_ACTIVE_LIBRARY_IDS`. That gate was
   preserved verbatim rather than reimplemented.
6. **Playback templates are env/registry values**, not secrets. Mission 17 moves
   only the token key and the Stream API key to per-library Secret Manager; the
   template stays `BUNNY_<id>_PLAYBACK_URL_TEMPLATE`.
7. **Receipt signing uses the mounted `BUNNY_TOKEN_KEY`** (`getEnv`), which is a
   different trust purpose from the per-library playback token key. Mission 17
   deliberately did **not** move it.
8. **The signing algorithm, URL construction and expiry were already correct**
   and had regression coverage; Mission 17 had to leave them byte-identical.

No undocumented field, global-secret conflict, schema blocker or signing change
was found, so no stop condition was raised.

---

## 2. Files inspected (before any change)

| Area | Files |
|------|-------|
| Prior mission | `reports/adr010/MISSION_16_BUNNY_LIBRARY_CATALOG_READ_PATH.md` |
| Catalog (pure) | `functions/src/core/video/bunny_library_catalog.ts` |
| Catalog reader | `functions/src/core/video/bunny_library_catalog_reader.ts` |
| Registry (pure) | `functions/src/core/video/bunny_library_registry.ts` |
| Association (pure) | `functions/src/core/video/bunny_library_association.ts` |
| Validation (pure) | `functions/src/core/video/bunny_video_validation.ts` |
| Runtime | `functions/src/index.ts` (issuance, display media, validation, association, secret mounts, receipt signing) |
| Packaging | `functions/package.json`, `functions/package-lock.json` |
| Tests | `functions/test/run_all.js`, `bunny_library_registry.test.js`, `bunny_video_validation.test.js`, `bunny_library_association.test.js`, `bunny_library_catalog.test.js`, `bunny_library_catalog_reader.test.js`, `bunny_library_catalog_flow.test.js`, `bunny_library_validation_flow.test.js`, `bunny_association_flow.test.js`, `issuance_library_flow.test.js`, `bunny_playback_regression.test.js`, `bunny_library_migration.test.js`, `bunny_default_library_config.test.js` |
| Architecture | `reports/adr010/mission_8_library_onboarding_architecture.md` (§H.1 schema, §H.3 adapter, §H.4 receipt-key separation), `21_ADR_010_Amendment_1.md` |
| Rules (read-only) | `firestore.rules` — inspected, **not modified** |
| VCS | `git status --short`, `git diff`, `git show HEAD:…` |

---

## 3. Files changed (this mission only)

| File | Change |
|------|--------|
| `functions/src/core/video/bunny_library_secret_resolver.ts` | **New.** Pure credential planner + async resolver + env-snapshot adapter + Firestore catalog source + Secret Manager accessor (bounded positive cache, typed errors, emulator detection) + client-reason mapping. |
| `functions/src/core/video/bunny_library_registry.ts` | Additive optional `definitionOverride` on `resolveBunnyPlaybackRuntime` and `resolveBunnyStreamApiRuntime` (id must match; mismatch falls back to the compiled lookup, i.e. fails closed). |
| `functions/src/core/video/bunny_library_association.ts` | Extracted `planBunnyAssociationShape` (structural checks only) and added the same optional `definitionOverride` to the shape/write planners. Behaviour without the override is unchanged. |
| `functions/src/core/video/bunny_video_validation.ts` | Additive optional `resolvedCredentials` parameter on `planBunnyVideoValidation`; format gate still runs first, library-id mismatch fails closed. |
| `functions/src/index.ts` | Integration only: catalog source + lazy accessor + per-call deps, async issuance/file-URL/Stream-config/meta helpers, validation and association callables now resolve that library's secrets. |
| `functions/package.json` | Added `@google-cloud/secret-manager@^8.0.0`; appended the new pure suite to `test:pure` (one entry). Also normalised the missing trailing newline at EOF. |
| `functions/package-lock.json` | Additive dependency lock entries only. |
| `functions/test/run_all.js` | Registered the new emulator flow suite (one entry). |
| `functions/test/bunny_library_secret_resolver.test.js` | **New.** 29 pure checks (mocked catalog + mocked Secret Manager, no network). |
| `functions/test/bunny_library_secret_resolver_flow.test.js` | **New.** 9 emulator checks through the real callables, including token-key isolation proven by HMAC recomputation. |

Not changed: `firestore.rules`, `storage.rules`, any deployment/IAM/secret
resource, `BUNNY_ACTIVE_LIBRARY_IDS`, `BUNNY_DEFAULT_LIBRARY_ID`, and every
signing/expiry/receipt implementation.

The three modified `bunny_*` modules sit inside the already-untracked
`functions/src/core/video/` directory, so they add no new `git status` entries.

---

## 4. Resolver contract

Module: `functions/src/core/video/bunny_library_secret_resolver.ts`.

### Inputs (trusted server-side only)

```ts
resolveBunnyLibraryCredentials({
  libraryId,                                   // trusted stored/derived id
  need: {streamApiKey: boolean; tokenKey: boolean},
  deps: {catalog, secrets, env},
})
```

* `libraryId` comes from `lecture_resources.bunny_library_id` or a
  server-resolved registry id. No client-supplied library *name*, secret name or
  credential ever reaches this module.
* `need` makes least privilege explicit: a metadata-only flow passes
  `{streamApiKey: true, tokenKey: false}`; playback signing passes
  `{streamApiKey: false, tokenKey: true}`.
* `deps` are injected, so unit tests use doubles and production passes the
  Firestore catalog source plus the Secret Manager accessor.

### Outputs

`{ok: true, credentials}` carries `libraryId`, `source` (`catalog` |
`legacy_default`), `apiLibraryId`, `playbackUrlTemplate`, and **only** the
requested values (`streamApiKey` / `tokenKey` are `null` when not requested).
This object is server-only: it is never serialised into a callable response.

`{ok: false, reason, libraryId}` carries a typed reason and **no** secret value,
secret name or Secret Manager resource path.

### Fail-closed reasons

| Reason | Meaning |
|--------|---------|
| `unknown_library` | Malformed id, or id neither compiled nor catalogued |
| `library_not_activated` | Catalog status not active, or id outside `BUNNY_ACTIVE_LIBRARY_IDS` |
| `incomplete_configuration` | Active but unverified/incomplete, or non-default with no catalog row |
| `invalid_catalog_entry` | Document id mismatch, unparsable document, or bad secret-name shape |
| `credential_name_mismatch` | Catalog row names a secret that is not this library's deterministic name |
| `catalog_unavailable` | Firestore read threw |
| `secret_not_found` | Secret Manager returned no payload / `NOT_FOUND` |
| `secret_permission_denied` | `PERMISSION_DENIED` |
| `secret_unavailable` | Any other provider/transport failure |
| `invalid_secret_value` | Empty, whitespace-containing, or out-of-bounds value |

Client-visible mapping (`bunnyCredentialFailureReason`) preserves only
`unknown_library` and `library_not_activated`; **every** secret-specific reason
collapses to `incomplete_configuration`, so a caller cannot probe secret state.

### Guarantees

* No cross-library fallback of any kind.
* No global credential for an unknown/incomplete non-default library.
* No read of a secret before the catalog row has been validated against the
  deterministic name.
* No negative caching (a newly created secret is visible immediately).
* Positive cache bounded by `BUNNY_SECRET_CACHE_TTL_MS` (60 s) with an injectable
  clock, so rotation is never masked indefinitely.

---

## 5. Secret naming and resolution mechanism

1. **Deterministic names.** `bunnySecretNames(libraryId)` yields
   `BUNNY_<libraryId>_STREAM_API_KEY` and `BUNNY_<libraryId>_TOKEN_KEY`
   (library id must be numeric, 1–20 digits).
2. **Catalog is the eligibility gate.** `bunny_libraries/{libraryId}` must exist
   and pass `isBunnyCatalogEntryUsable` (active, token auth enabled,
   probe-verified, valid metadata).
3. **Name verification before any read.** The row's `credential_refs` must equal
   the deterministic names exactly. A row for library A that points at library
   B's secret fails `credential_name_mismatch` **before** the accessor is called.
   The document id must also equal the requested id.
4. **Catalog-only libraries.** A library onboarded through the catalog is not
   compiled into `BUNNY_LIBRARIES`. `deriveCatalogLibraryDefinition` reproduces
   the approved convention (`BUNNY_<id>_*`, `streamLibraryIdVar: null`, not
   default) so onboarding stays a configuration action. `findBunnyLibraryDefinition`
   is **not** widened: an id that is neither compiled nor catalogued still fails
   as `unknown_library`.
5. **Activation gate preserved.** `isBunnyLibraryActive` is still the authority:
   the default library is always active; any other library must be listed in
   `BUNNY_ACTIVE_LIBRARY_IDS`.
6. **Legacy default only.** With no catalog row, the canonical default library
   (`BUNNY_DEFAULT_LIBRARY_ID`, default `736742`) may read its own pre-existing
   `BUNNY_STREAM_API_KEY` / `BUNNY_TOKEN_KEY`. This path is disabled by
   `BUNNY_LEGACY_LIBRARY_FALLBACK=false`. A non-default library without a row
   never reaches it.
7. **Production read path.**
   `projects/{GCLOUD_PROJECT|GOOGLE_CLOUD_PROJECT}/secrets/{NAME}/versions/latest`
   through `@google-cloud/secret-manager`.
8. **Emulator read path.** When `FUNCTIONS_EMULATOR==="true"` or
   `FIRESTORE_EMULATOR_HOST` is set, the same secret *name* is read from the
   process environment (mirroring the existing `resolveBunnyStreamApiKey`
   behaviour). This branch is unreachable in production.
9. **Value validation.** 8–512 printable ASCII characters, no whitespace or
   control characters; anything else is `invalid_secret_value`.

---

## 6. Runtime integration points

| Flow | Entry point | Credentials read |
|------|-------------|------------------|
| Playback signing | `resolveIssuanceBunnyLibrary` → `generateBunnySignedUrl` | **token key only** |
| Signed file URL (poster / custom thumbnail / HQ preview) | `buildBunnyFileUrl` | **token key only** |
| Stream metadata | `bunnyStreamApiConfig` → `fetchBunnyVideoMeta` | **Stream API key only** |
| Display media | `resolveBestEffortBunnyLibraryId` (id only) → `fetchBunnyVideoMeta` / `buildBunnyFileUrl` | id first; then only what each helper needs |
| Validation callable | `validateBunnyVideoAssociation` | **Stream API key only** |
| Association callable | `associateBunnyVideoToLibrary` | **Stream API key only** |

Notable details:

* **Stored id is authoritative.** Playback resolves
  `lecture_resources.bunny_library_id`; a client hint that disagrees is rejected
  (`library_mismatch`) instead of being trusted. The legacy fallback runs only
  when the stored id is absent.
* **Validation order preserved.** `planBunnyVideoValidation` still validates
  formats first, so `invalid_video_id` precedence and no-secret-needed cases are
  unchanged. Credentials are resolved only after that gate, then the plan is
  re-run with the resolved runtime.
* **Association order.** Structural shape → Stream credential resolution →
  per-library env snapshot → full plan. The **same** snapshot/definition is
  reused inside the transaction, so the write path never depends on a global
  credential and cannot diverge from the pre-transaction decision.
* **Metadata-only flows never read the token key**, and signing flows never read
  the Stream API key. This is asserted in the pure suite by recording every
  `readSecret` call.
* **Signing semantics untouched.** `hashVideoDirectoryToken`, `hashPathToken`,
  `buildBunnyResourceAccessUrl` and `generateBunnyResourceUrl` are identical to
  HEAD (verified by extracting both versions and comparing). The playback
  `expires = Math.floor(Date.now()/1000) + 300`, the `bcdn_token` /
  `token_path` / `expires` URL construction, and the HMAC receipt
  sign/verify paths are unchanged; only the *source* of the template and token
  key moved from `getEnv(...)` to the per-library runtime.
* **Receipt signing still uses the mounted `BUNNY_TOKEN_KEY`.** Association
  receipts are a different purpose (server-issued proof) and were out of scope.

---

## 7. Cross-library isolation evidence

**Structural (cannot happen, by construction)**

* Secret names are derived from the id and compared with the catalog row; a
  cross-reference fails before any read.
* The registry lookup is never widened; an uncatalogued id is `unknown_library`.
* There is no "try the other library" branch anywhere in the module.
* A non-default library with no catalog row fails instead of borrowing global
  credentials.

**Pure tests (`bunny_library_secret_resolver.test.js`, mocked I/O)**

* A resolves only `BUNNY_780700_STREAM_API_KEY` / `BUNNY_780700_TOKEN_KEY`;
  the recorded read list is exactly one name per operation.
* B resolves only `BUNNY_781800_*`; no assertion ever sees a value containing the
  other library's marker.
* Metadata-only read list excludes the token key; signing read list excludes the
  Stream API key.
* Cross-referenced catalog row → `credential_name_mismatch` with an **empty**
  read list.
* Unknown, malformed, disabled, allow-list-excluded, unverified and structurally
  invalid entries → typed failure with an **empty** read list.
* Missing secret, permission denial, service failure, malformed value and catalog
  failure all fail closed and leak no value, name or `/secrets/` path.

**Emulator flow (`bunny_library_secret_resolver_flow.test.js`, real callables)**

* Library A's signed URL starts with A's pull zone and its `bcdn_token` is
  **recomputed independently** from A's token key; it is provably not the token
  produced by B's key or the default key.
* The same is proven for Library B in the opposite direction.
* An allow-listed library with no catalog row is denied at the callable with
  `unknown_library`, never falling back.
* Disabled → `inactive_library`; cross-referenced → rejected; missing secret →
  `incomplete_configuration` (never "secret missing").
* No response or error message contains a secret value or a secret name.

---

## 8. IAM requirements (least privilege)

Deployment prerequisite — **not applied in this mission**.

1. Enable `secretmanager.googleapis.com` on the target project (Staging).
2. Create, per library, exactly two secrets:
   `BUNNY_<libraryId>_STREAM_API_KEY` and `BUNNY_<libraryId>_TOKEN_KEY`.
3. Grant the Functions runtime service account
   `roles/secretmanager.secretAccessor` **per secret**
   (`google_secret_manager_secret_iam_member`), not project-wide. The only
   permission required is `secretmanager.versions.access` on
   `…/secrets/BUNNY_<id>_*/versions/latest`.
4. Do **not** grant `secretmanager.admin`, `secretmanager.secrets.list`,
   `secretmanager.versions.destroy` or project-level `secretAccessor`.
5. No secret needs to be mounted for the per-library path: names are dynamic, so
   access is a runtime API read under IAM. The default library's legacy path and
   the association receipt continue to use the existing mounted
   `BUNNY_STREAM_API_KEY` / `BUNNY_TOKEN_KEY`.
6. Rotation: add a new version; the resolver picks it up within the 60 s positive
   TTL (or immediately on a cache miss). Never disable/destroy the previous
   version before the TTL has elapsed.

IAM state is **unverified**; there was no access to Staging IAM in this mission.

---

## 9. Tests executed and actual results

| # | Command | Result |
|---|---------|--------|
| 1 | `npm run build` (`functions/`) | **exit 0** |
| 2 | `npm run test:pure` | **exit 0** — 11 offline suites, including the new 29-check resolver suite |
| 3 | `node test/bunny_library_secret_resolver.test.js` | **29 checks passed** |
| 4 | `firebase emulators:exec --project demo-tarek-platform --only firestore "node functions/test/bunny_library_secret_resolver_flow.test.js"` | **9 checks passed** |
| 5 | `FUNCTIONS_DISCOVERY_TIMEOUT=120 npm test` (full suite) | **56/56 files passed** (Mission 16 baseline: 55/55; +1 new flow suite) |
| 6 | `firebase emulators:exec --project dr-tarek-platform-rules-test --only firestore,storage "npm --prefix security-tests test"` | **exit 0** (Rules unchanged) |
| 7 | `npx eslint src/core/video/bunny_library_secret_resolver.ts bunny_library_registry.ts bunny_library_association.ts bunny_video_validation.ts` | **exit 0** (clean) |
| 8 | `npx eslint --rule 'linebreak-style: off' src/index.ts` | 15 errors / 19 warnings — **all pre-existing**. HEAD has 13 errors (verified by linting a HEAD copy); the +2 are the uncommitted Mission 16 diagnostic `quotes` errors at lines ~1669/1672. Mission 17 added **0** lint errors. `linebreak-style` is pre-existing because `index.ts` is entirely CRLF at HEAD. |
| 9 | `git diff` review of signing code | Signing helpers identical to HEAD; only credential *sources* changed |
| 10 | `git status --short` before/after | See §11; no staged/deleted entries, no probe files left behind |

Notes:

* Every new test uses mocked Secret Manager or the emulator env source. **No real
  Bunny call and no real Secret Manager call was made.**
* The emulator flow test recomputes the directory token independently with
  `node:crypto`, so token-key isolation is proven by construction, not by
  inspecting logs.
* Unrelated pre-existing failures were not "fixed"; the only lint delta is the
  two Mission 16 diagnostic lines noted above.

---

## 10. Security review

| Threat | Control | Evidence |
|--------|---------|----------|
| Client supplies a secret name / library | Only trusted stored/derived ids enter the resolver; catalog-only names; client hints are validated and rejected on mismatch | §4, §6 |
| Library A uses Library B's Stream key or token key | Deterministic name equality enforced before any read; no fallback; A/B read lists asserted; HMAC recomputation in the flow test | §7 |
| Unknown / disabled / incomplete library silently works | Typed fail-closed reasons; activation allow-list preserved | §4, §5 |
| Secret exfiltration through responses/errors/logs | Failures carry no value, name or path; client reasons collapse to `incomplete_configuration`; no logging added | §4, §7 |
| Secret leakage through provider errors | `BunnySecretAccessError` strips the provider message and the secret name | pure test 27 |
| Over-broad secret reads | `need` flags; metadata-only never reads the token key; signing never reads the Stream API key | pure tests 4–5 |
| Rotation masked indefinitely | Positive-only 60 s TTL, injectable clock; negatives never cached | pure test 25 |
| Cache poisoning / stale deny | Negative results are not cached; failed client import is retried | pure test 25 |
| Global credential used for a non-default library | Legacy path is default-only and can be disabled; non-default without a row fails | pure tests 19–21 |
| Authorization-relevant library id forged by a client | Stored id authoritative; hint mismatch rejected; association receipt unchanged | §6 |
| Metadata path becomes an authorization path | Metadata stays best-effort (`null` on failure); validation still returns `unavailable`, never `verified` | §6, flow test |
| Deployment-model regression | Per-library secrets are runtime reads under IAM; only the default/receipt secrets stay mounted | §8 |

Residual risks (documented, not exploitable in this change):

* A catalog row that is *correctly* named but points to a secret whose value is
  another library's key cannot be detected cryptographically. The control is
  catalog write authorization (admin-only, already enforced by Rules) plus the
  naming convention; operational verification is a deployment step.
* The 60 s TTL means a rotated-away key can still sign for up to 60 s. This is
  bounded and intentional; it is not indefinite masking.
* IAM misconfiguration (e.g. project-wide `secretAccessor`) would widen blast
  radius without changing code behaviour. §8 specifies the per-secret binding.

No Rules change was required or made: `bunny_libraries` remains server-managed,
and clients never read secrets.

---

## 11. Git status before and after

| Snapshot | Total | Modified | Untracked | Staged | Deleted |
|----------|-------|----------|-----------|--------|---------|
| Before (Mission 17 preflight) | 60 | 30 | 30 | 0 | 0 |
| After | 63 | 31 | 32 | 0 | 0 |

Delta = 2 new test files (`bunny_library_secret_resolver.test.js`,
`bunny_library_secret_resolver_flow.test.js`) + `functions/package-lock.json`
newly modified by the dependency install. `index.ts`, `functions/package.json`
and `run_all.js` were already modified before this mission; only additive hunks
were introduced (plus the `package.json` trailing-newline normalisation). This
report adds no status entry because the whole `reports/` directory is already
reported as a single untracked entry (`?? reports/`), exactly like the Mission 16
report.

No `git add`, `commit`, `push`, `reset`, `stash`, `clean` or deploy was run. No
unrelated file was deleted. The temporary HEAD-lint probe was created outside
tracked paths and removed; `git status` contains no probe entry.

---

## 12. Remaining blockers and Production confirmation

### Blockers (out of scope for Mission 17)

1. **Catalog-only libraries still need a playback template.** `playback_host`
   exists in the catalog but no approved derivation from host → template was
   given, so a catalog-only library requires
   `BUNNY_<id>_PLAYBACK_URL_TEMPLATE` in the environment. Documented; not
   invented here.
2. **Staging catalog is empty and the allow-list has no non-default ids.** The
   catalog path cannot be exercised operationally until an approved catalog write
   and `BUNNY_ACTIVE_LIBRARY_IDS` update happen (neither was performed).
3. **IAM is unverified** (`secretmanager.versions.access` / per-secret
   `secretAccessor`). Required before any deployment; see §8.
4. **No deployment.** The code is source-only; Staging does not serve it.
5. **Dashboard picker wiring** remains unwired (separate mission).
6. **Secret provisioning/rotation runbook** for per-library secrets is a
   deployment task, not a code task.
7. **`775315` remains inactive** — untouched, not activated, no configuration
   written.

### Production confirmation

Production was **not accessed and not modified** in this mission:

* No Production Firestore read or write; no catalog seeding; no
  `bunny_libraries` document created anywhere.
* No Production Secret Manager access; no secret created, read, versioned,
  disabled or destroyed.
* No Production environment variable, IAM binding, service account or rotation
  change.
* No deployment to Staging or Production.
* `firestore.rules` / `storage.rules` unchanged.
* `775315` remains inactive.
* All work is uncommitted on `ci/ios-staging-codemagic` at HEAD
  `34a4b763e77087e0eeffd4aa8ad88bb820b61d46`.

**Mission 17 stops here.** Catalog seeding, Dashboard integration, IAM changes
and deployment are not started.
