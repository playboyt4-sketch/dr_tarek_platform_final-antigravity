# ADR-010 — Mission 18: Staging Secret Manager & IAM Readiness Audit

**Mode:** read-only audit. No code, infrastructure, IAM, Firestore, secret,
Rules, deployment or Git-history change was made.

**Target:** `dr-tarek-staging` only. Production was not queried for data.

**Branch:** `ci/ios-staging-codemagic`
**HEAD (unchanged):** `34a4b763e77087e0eeffd4aa8ad88bb820b61d46`

**Final status: BLOCKED — SECURITY ISSUE**

---

## 1. Executive Summary

The Mission 17 resolver is **correctly isolated in code** (verified by 29 pure
checks and 9 emulator checks), but Staging is **not ready** for per-library
secret provisioning or multi-library playback, for two independent reasons:

1. **Security blocker (S-1).** In Staging, the compiled Production default id
   `736742` is still treated as a *known, active, default* library even though
   `BUNNY_DEFAULT_LIBRARY_ID=780700`. An explicit request for `736742` therefore
   succeeds and is served with the **Staging default library's** credentials
   (`BUNNY_TOKEN_KEY` / `BUNNY_PLAYBACK_URL_TEMPLATE` / `BUNNY_STREAM_API_KEY`),
   with the Stream API path silently pointing at `780700`. That is a silent
   cross-library credential fallback for an explicitly requested non-default
   library — exactly what the mission's critical rule forbids. No Production
   secret is exposed, and Staging currently holds no video resources, but the
   path is reachable through the validation callable (client-supplied library
   id) and through any resource row carrying `736742`.
2. **Missing infrastructure evidence (I-1…I-5).** There are **zero**
   per-library secrets (`BUNNY_<id>_*`) in Staging; the `bunny_libraries`
   catalog is empty; `BUNNY_ACTIVE_LIBRARY_IDS` is unset; Mission 17 code is
   **not deployed**; and the provenance of the legacy global secret values
   cannot be confirmed without reading payloads (forbidden).

What *is* healthy: all six existing Bunny secrets are in the Staging project,
enabled, with per-secret `secretAccessor` bindings only (no project-level
Secret Manager role), and `roles/editor` does **not** include
`secretmanager.versions.access`. Mission 17's cross-library isolation is proven
by tests. `775315` fails closed. Unknown ids fail closed.

---

## 2. Environment Verification

| Item | Result |
|------|--------|
| Firebase default alias | `dr-tarek-platform` (**not used in this audit**) |
| Firebase `staging` alias | `dr-tarek-staging` |
| Active gcloud account | authenticated user account present (address masked in this report) |
| Staging project describe | `dr-tarek-staging`, number `13159003436`, `ACTIVE` |
| Explicit project scoping | every remote command carried `--project=dr-tarek-staging` |
| Production data access | none (no Firestore/Secret Manager/Functions data read from Production) |
| Branch / HEAD | `ci/ios-staging-codemagic` / `34a4b763…` |
| Working tree | preserved; 63 entries before and after (31 modified, 32 untracked, 0 staged, 0 deleted) |

**Procedural incident (disclosed).** A read-only `gcloud policy-troubleshoot iam`
attempt used the local gcloud quota project (`dr-tarek-platform`) for API
enablement. The call failed with `SERVICE_DISABLED` before returning any
Production data, and no Production resource was read or modified. The command
was not retried; the permission question was answered from the role definition
and IAM policy instead. This is recorded as a deviation, not a data access.

The environment is positively identified as Staging, so the audit proceeded.

---

## 3. Legacy Default Fallback Security Analysis

### 3.1 Exact conditions for the legacy default path

`planBunnyLibraryCredentialResolution` returns `source: "legacy_default"` only
when **all** of the following hold:

1. the id normalizes to a numeric id (`^\d{1,20}$`);
2. a registry definition exists for it (compiled entry, or id equal to
   `resolveDefaultBunnyLibraryId(env)`);
3. `isBunnyLibraryActive(definition, env)` is true (default → always true;
   otherwise the id must be in `BUNNY_ACTIVE_LIBRARY_IDS`);
4. the Firestore catalog returned **no** `bunny_libraries/{id}` document;
5. `definition.isDefault === true`;
6. `BUNNY_LEGACY_LIBRARY_FALLBACK` is not the literal `"false"`.

It then reads `BUNNY_STREAM_API_KEY` / `BUNNY_TOKEN_KEY` from the server-only env
snapshot (deployed: the mounted Staging secrets), validates their shape, and
never touches Secret Manager for that library.

### 3.2 Answers to the required questions

| # | Question | Finding |
|---|----------|---------|
| 1 | When is legacy allowed? | Exactly the six conditions above. |
| 2 | Can a missing catalog document trigger legacy credentials? | **Yes — but only for a definition with `isDefault === true`.** Non-default → `incomplete_configuration`. In Staging that means `780700` **and** the compiled `736742` entry. |
| 3 | Can an explicitly supplied *unknown* id fall back to the default? | **No.** `999999` → `unknown_library`, no secret read (probe + tests). **However**, the compiled `736742` is not "unknown" to the registry and *does* resolve — see S-1. |
| 4 | Can an inactive library fall back? | **No.** `775315` → `library_not_activated` before any read (probe + tests). Default/isDefault definitions bypass the allow-list by design. |
| 5 | Can an incomplete catalog entry fall back? | **No.** Unverified/disabled entries → `library_not_activated`; malformed entries → `invalid_catalog_entry`; cross-referenced names → `credential_name_mismatch`; all before any secret read. |
| 6 | Can the fallback resolve Production credentials from Staging? | **Not by code path.** It reads only the Staging project's mounted secrets; there is no cross-project lookup. Whether the *values* are Production credentials is **unverified** (payload read forbidden) — see I-5. |
| 7 | Can the fallback bypass the allow-list? | **Yes for `isDefault` definitions** (`780700` and the compiled `736742`). Non-default libraries cannot. This is documented backward compatibility, but it is the mechanism behind S-1. |
| 8 | Do all playback/resource-URL flows share trusted resolution? | **Yes in the working tree.** Playback uses the stored id as authoritative; display media resolves the stored id and passes it explicitly to `buildBunnyFileUrl`; metadata uses the resolved id. No call site uses the default-argument shortcut (see N-4). |

### 3.3 S-1 evidence (local probe, Staging-like env, no remote calls)

Env: `BUNNY_DEFAULT_LIBRARY_ID=780700`, `BUNNY_STREAM_LIBRARY_ID=780700`,
`BUNNY_ACTIVE_LIBRARY_IDS=""`.

```
registry 780700 {"ok":true,"libraryId":"780700","source":"resource"}
registry 736742 {"ok":true,"libraryId":"736742","source":"resource"}   <-- accepted
registry 775315 {"ok":false,"reason":"library_not_activated"}
registry 999999 {"ok":false,"reason":"unknown_library"}
playback 736742 {"ok":true,"libraryId":"736742"}                      <-- default creds
stream   736742 {"ok":true,"libraryId":"736742","apiLibraryId":"780700"} <-- split identity
```

Root cause: `findBunnyLibraryDefinition` (registry line ~237) only treats the id
as the *env* default when it equals `resolveDefaultBunnyLibraryId(env)`. The
loop below it still returns the compiled `736742` entry, which carries
`isDefault: true`; `isBunnyLibraryActive` then returns true unconditionally, and
the resolver's legacy branch accepts it. The `BUNNY_DEFAULT_LIBRARY_ID` override
therefore creates **two** default-like libraries in Staging.

Impact: no Production secret disclosure; the credentials used are the Staging
environment's default set. The defect is identity/integrity: a resource or
validation request explicitly naming `736742` is silently served by `780700`'s
signing material and `780700`'s Stream API path, and a validation receipt can be
issued bound to `736742`. Reachable today through `validateBunnyVideoAssociation`
(client-supplied `libraryId`, authorized content manager) and through any stored
resource with `bunny_library_id = "736742"` (none exist in Staging today).

---

## 4. Staging Secret Manager Inventory

Metadata only. **No secret payload, fingerprint or access token was read.**

Project for every secret: `projects/13159003436` (`dr-tarek-staging`),
replication `automatic`, no labels.

### 4.1 Per-library secrets (expected by Mission 17)

| Library ID | Stream secret name | Stream exists | Stream enabled | Token secret name | Token exists | Token enabled | Latest version enabled | Secret project |
|---|---|---|---|---|---|---|---|---|
| `780700` (Staging default) | `BUNNY_780700_STREAM_API_KEY` | **NO** | N/A | `BUNNY_780700_TOKEN_KEY` | **NO** | N/A | N/A | `projects/13159003436` |
| `775315` (compiled, must stay inactive) | `BUNNY_775315_STREAM_API_KEY` | **NO** | N/A | `BUNNY_775315_TOKEN_KEY` | **NO** | N/A | N/A | `projects/13159003436` |
| `736742` (compiled Production default id) | `BUNNY_736742_STREAM_API_KEY` | **NO** | N/A | `BUNNY_736742_TOKEN_KEY` | **NO** | N/A | N/A | `projects/13159003436` |

Total per-library secrets matching `^BUNNY_\d+_(STREAM_API_KEY|TOKEN_KEY)$`:
**0**.

### 4.2 Legacy global secrets actually used by the default library

| Item | Result |
|---|---|
| Stream secret name | `BUNNY_STREAM_API_KEY` |
| Stream secret exists / enabled | **YES / YES** |
| Stream latest version enabled | **version 2 enabled; version 1 destroyed** |
| Token secret name | `BUNNY_TOKEN_KEY` |
| Token secret exists / enabled | **YES / YES** |
| Token latest version enabled | **version 1 enabled** |
| Secret project | `projects/13159003436` |

Related non-library secrets present: `BUNNY_PLAYBACK_URL_TEMPLATE`,
`BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`,
`BUNNY_STORAGE_PASSWORD` (all enabled, version 1). The local
`functions/.env.dr-tarek-staging` now contains only non-secret keys
(`APP_CHECK_ENFORCEMENT`, `BUNNY_STREAM_LIBRARY_ID`,
`BUNNY_DEFAULT_LIBRARY_ID`) and is git-ignored.

Limitation: whether the legacy values belong to Staging library `780700` rather
than Production `736742` cannot be established without reading payloads, which
is forbidden. See I-5.

---

## 5. IAM and Service Account Analysis

| Item | Result | Confidence |
|------|--------|-----------|
| Service account (all 6 Bunny functions) | `13159003436-compute@developer.gserviceaccount.com` | **Confirmed** (`functions list` / `describe`) |
| Resolver uses Secret Manager client library | Working tree: **yes** (`@google-cloud/secret-manager`); deployed bundle: **no** | **Confirmed** (bundle symbol scan) |
| `secretmanager.versions.access` on the 6 existing secrets | `roles/secretmanager.secretAccessor` bound **per secret** to the compute SA | **Confirmed** (`get-iam-policy` on each secret) |
| Project-level Secret Manager roles | **none** | **Confirmed** (`projects get-iam-policy`) |
| `roles/editor` includes `secretmanager.versions.access` | **no** (12,543 included permissions; `versions.access` absent) | **Confirmed** (role definition) |
| Effective secret scope broader than necessary | **no** for secrets; the SA can read only the 6 bound secrets | **Inferred** from confirmed bindings + role definition (not exercised at runtime) |
| Per-library secret permission | **not applicable / not verified** — the secrets do not exist | **Not verified** |
| Staging SA can access Production secrets | **not verified** — requires a Production-side IAM read, which is out of scope. Secret Manager is project-scoped; no cross-project binding is visible from Staging. | **Not verified** |

Other project roles held by the compute SA: `roles/editor`,
`roles/eventarc.eventReceiver`, `roles/run.invoker`. Editor is broad for general
GCP resources but grants no secret payload access (see above). This is the
standard Firebase default SA and is reported as N-3, not a secret-access issue.

---

## 6. Cross-Library Isolation Results

Verified by local execution (no Bunny or Secret Manager network calls):

| Property | Evidence | Result |
|---|---|---|
| A metadata uses A Stream key | pure test: A read list = `BUNNY_780700_STREAM_API_KEY` only | **PASS** |
| A signing uses A token key | pure test + emulator HMAC recomputation | **PASS** |
| B metadata uses B Stream key | pure test: B read list = `BUNNY_781800_STREAM_API_KEY` only | **PASS** |
| B signing uses B token key | pure test + emulator HMAC recomputation | **PASS** |
| Token key never used for metadata | metadata-only read list excludes the token key | **PASS** |
| Stream key never used for signing | signing read list excludes the Stream key | **PASS** |
| Unknown id cannot inherit credentials | `999999` → `unknown_library`, zero reads | **PASS** |
| Disabled id cannot inherit credentials | disabled catalog row → `library_not_activated`, zero reads | **PASS** |
| Cross-referenced catalog row rejected before read | → `credential_name_mismatch`, zero reads | **PASS** |
| Client cannot choose secret names/credentials | names derived from the trusted id; catalog names must match exactly | **PASS** |
| Client library id is fully untrusted | validation accepts a client id, but resolution is constrained to registry/catalog + activation; unknown → fail closed | **PASS** |
| Explicit non-default compiled id cannot use default creds | **FAIL** — `736742` resolves to the Staging default credentials (S-1) | **FAIL (S-1)** |

---

## 7. Runtime Configuration Findings

| Item | Finding |
|------|---------|
| Deployed functions | 6 Bunny functions ACTIVE, all on the compute SA, last updated **2026-11-14T11:16Z** |
| Mission 17 deployed? | **No.** Deployed bundle has no `bunny_library_secret_resolver`, no `resolveBunnyPlaybackCredentials`, no `@google-cloud/secret-manager`. |
| Mission 16 reader deployed? | **No.** Deployed `lib/core/video/` has no `bunny_library_catalog_reader.js`; no catalog callable is deployed. |
| Legacy secret mounts | `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STREAM_API_KEY` (plus storage secrets on resource/media functions) — all Staging secret names |
| `BUNNY_DEFAULT_LIBRARY_ID` | `780700` (Staging default; not Production `736742`) |
| `BUNNY_STREAM_LIBRARY_ID` | `780700` |
| `BUNNY_ACTIVE_LIBRARY_IDS` | **unset** → no non-default library active |
| `BUNNY_LEGACY_LIBRARY_FALLBACK` | **unset** → legacy fallback **enabled** (default) |
| Production project id in env values | **none** (`dr-tarek-platform` not present in any env value) |
| Emulator fallback in deployed runtime | **unreachable** — no `FUNCTIONS_EMULATOR`, no `FIRESTORE_EMULATOR_HOST` |
| Missing configuration error shape | generic `failed-precondition` with a reason code (`unknown_library`, `library_not_activated`, `incomplete_configuration`); no secret name/value/path |
| Firestore catalog | `bunny_libraries` **empty** (0 documents) |
| Stored library associations | `lecture_resources` **empty** (0 rows) |
| Rules for catalog | `bunny_libraries` is `allow read, write: if false` (clients cannot read it) |

---

## 8. Test Results

All local; no remote writes, no Bunny calls, no secret payload reads.

| # | Command | Result |
|---|---------|--------|
| 1 | `npm run build` (`functions/`) | **exit 0** |
| 2 | `npm run test:pure` | **exit 0** (11 suites; resolver suite 29 checks) |
| 3 | `node test/bunny_library_secret_resolver.test.js` | **29 checks passed** |
| 4 | `firebase emulators:exec --project demo-tarek-platform --only firestore "node functions/test/bunny_library_secret_resolver_flow.test.js"` | **9 checks passed**, script exit 0 |
| 5 | `FUNCTIONS_DISCOVERY_TIMEOUT=120 npm test` | **56/56 files passed**, exit 0 |
| 6 | ESLint on the 4 core video modules | **exit 0** (clean) |
| 7 | ESLint `src/index.ts` with `linebreak-style` off | 15 errors / 19 warnings, **all pre-existing** (13 at HEAD + 2 Mission 16 diagnostic `quotes`); 0 added by Mission 17/18 |
| 8 | Local identity probe (Staging-like env) | reproduced S-1; confirmed `775315` and `999999` fail closed |

Rules were not re-run (no Rules change); Mission 17 already recorded the rules
suite at exit 0.

---

## 9. Security Blockers

### S-1 — Explicit non-default compiled id silently uses the default credentials (BLOCKER)

* **Severity:** Medium (integrity / library-identity confusion; no Production
  secret disclosure).
* **Where:** `functions/src/core/video/bunny_library_registry.ts`
  (`findBunnyLibraryDefinition` loop + `isDefault` activation bypass) combined
  with the Mission 17 legacy branch in `bunny_library_secret_resolver.ts`.
* **Trigger in Staging:** `BUNNY_DEFAULT_LIBRARY_ID=780700` while the compiled
  `736742` entry remains `isDefault: true`.
* **Observed:** `736742` → `ok`, served by `780700`'s token key/template and
  `780700`'s Stream API path (`apiLibraryId=780700`).
* **Reachability:** `validateBunnyVideoAssociation` accepts a client
  `libraryId`; a content manager can name `736742`. Any stored resource with
  `bunny_library_id="736742"` would also hit it. Staging currently has no such
  rows.
* **Rule violated:** "An explicitly requested unknown, inactive, or incomplete
  library must fail closed. It must never silently fall back to another
  library's credentials."

### I-1 — Per-library secrets do not exist (BLOCKING EVIDENCE GAP)

Zero `BUNNY_<id>_STREAM_API_KEY` / `BUNNY_<id>_TOKEN_KEY` secrets in Staging.
The per-library path cannot be exercised; provisioning is a prerequisite.

### I-2 — Catalog is empty and the allow-list is unset (BLOCKING EVIDENCE GAP)

No `bunny_libraries` rows and no `BUNNY_ACTIVE_LIBRARY_IDS`, so no catalog-only
library can be active. Multi-library playback is not testable operationally.

### I-3 — Mission 17 is not deployed (BLOCKING EVIDENCE GAP)

The deployed bundle predates the resolver; all per-library behaviour described
here is source-only until an approved deployment.

### I-4 — Per-library IAM cannot be verified (BLOCKING EVIDENCE GAP)

No per-library secrets exist, so no `secretAccessor` binding can exist for them.

### I-5 — Legacy secret value provenance is unverified (BLOCKING EVIDENCE GAP)

The six existing secrets are in the Staging project, but whether their values
are Staging (`780700`) or Production (`736742`) material cannot be confirmed
without reading payloads, which this mission forbids. Metadata (creation dates,
staging-only ids in env) is consistent with Staging provisioning but is not
proof.

---

## 10. Non-Blocking Findings

| ID | Finding | Recommendation |
|----|---------|----------------|
| N-1 | The deployed function source archive contains `.env` and `.env.dr-tarek-staging`. Today they hold only non-secret keys, but a future edit could embed secrets in GCS. | Exclude `.env*` from the Functions source via `firebase.json` `ignore`, or keep env files outside the deploy directory. |
| N-2 | The source archive also contains `test/`, `scripts/`, `behavioral_tests.js`, `extract_ts.js`, `firestore-debug.log`. | Tighten the Functions `ignore` list. |
| N-3 | The compute SA holds `roles/editor` project-wide (standard Firebase default). It does **not** grant Secret Manager payload access. | Consider a dedicated least-privilege runtime SA in a later hardening pass. |
| N-4 | `buildBunnyFileUrl`, `fetchBunnyVideoMeta` and `bunnyStreamApiConfig` default to the compiled `DEFAULT_BUNNY_LIBRARY_ID` (`736742`), not `resolveDefaultBunnyLibraryId(env)`. All current call sites pass an explicit id, so this is latent. | Make the library id a required parameter, or default to the env-resolved default. |
| N-5 | `BUNNY_LEGACY_LIBRARY_FALLBACK` is unset, so the legacy fallback is implicitly enabled. | Set it explicitly (`true` during migration, `false` after backfill). |
| N-6 | `APP_CHECK_ENFORCEMENT=false` in Staging (pre-existing). | Separate decision; unchanged here. |
| N-7 | `onPasswordResetRequest` is in `FAILED` state (pre-existing, unrelated to Bunny). | Track separately. |
| N-8 | `BUNNY_STREAM_API_KEY` version 1 is destroyed, version 2 enabled. | Expected after rotation; no action, but keep the previous version until consumers refresh. |
| N-9 | Positive secret cache is 60 s, so a rotated-away key can still be used for up to 60 s. | Bounded and intentional; document in the rotation runbook. |

---

## 11. Exact Remediation Plan

Ordered; nothing below was executed.

1. **Fix S-1 (code, separate mission).**
   In `findBunnyLibraryDefinition`, when
   `resolveDefaultBunnyLibraryId(env) !== DEFAULT_BUNNY_LIBRARY_ID`, do not
   return the compiled entry whose id is `DEFAULT_BUNNY_LIBRARY_ID` unless it is
   explicitly allow-listed or catalogued (i.e., treat `736742` as
   `unknown_library` in Staging). Add a regression test:
   *env default `780700`* → `736742` must fail `unknown_library`; `780700`
   still resolves legacy; `775315` still `library_not_activated`.
2. **Make the fallback explicit.** Set `BUNNY_LEGACY_LIBRARY_FALLBACK=true` in
   Staging while legacy rows exist; plan `false` after backfill.
3. **Provision per-library secrets (owner action, requires approval).**
   For the Staging library `780700`, create `BUNNY_780700_STREAM_API_KEY` and
   `BUNNY_780700_TOKEN_KEY` with Staging-only values. Do **not** create
   `BUNNY_775315_*`; keep `775315` inactive.
4. **Grant least privilege.** Bind `roles/secretmanager.secretAccessor` per
   secret to `13159003436-compute@developer.gserviceaccount.com` (or to the
   dedicated runtime SA chosen in N-3). Do not grant project-level Secret
   Manager roles.
5. **Seed the catalog (separate approved write).** Add
   `bunny_libraries/780700` with `status: active`, `token_auth_enabled: true`,
   `token_auth_verified: true`, a valid `playback_host`/`pull_zone_id`, and
   `credential_refs` exactly `BUNNY_780700_STREAM_API_KEY` /
   `BUNNY_780700_TOKEN_KEY`. Then set `BUNNY_ACTIVE_LIBRARY_IDS=780700` (the
   allow-list is still required for non-default libraries).
6. **Provide the playback template.** Ensure
   `BUNNY_780700_PLAYBACK_URL_TEMPLATE` exists in the environment (or decide a
   catalog-derived template, which is still an open blocker from Mission 17).
7. **Deploy (separate approval).** Deploy the Mission 17 code to Staging only,
   then re-run this audit's inventory/IAM checks and the emulator flow suite.
8. **Verify value provenance (I-5)** with the secret owner out-of-band (Bunny
   dashboard or a controlled comparison), without reading payloads in this
   repository.
9. **Re-audit** and only then consider `READY FOR STAGING SECRET PROVISIONING`.

---

## 12. Final Readiness Decision

**BLOCKED — SECURITY ISSUE**

* S-1 must be fixed (and regression-tested) before any multi-library Staging
  playback is trusted.
* Independently, I-1…I-5 prevent a "verified ready" conclusion: no per-library
  secrets, empty catalog, unset allow-list, undeployed resolver, and unverified
  legacy value provenance.

What would change the decision:

* S-1 fixed + tested, **and**
* `BUNNY_780700_*` secrets created with per-secret `secretAccessor`, **and**
* `bunny_libraries/780700` seeded + `BUNNY_ACTIVE_LIBRARY_IDS=780700`, **and**
* Mission 17 deployed to Staging, **and**
* legacy value provenance confirmed by the owner.

Until then, the only safe Staging posture is the current one: legacy default
`780700` via the global secrets, `775315` inactive, and no per-library claims.

**Production was not accessed or modified.** One read-only tooling call was
scoped to the Production quota project for API enablement and was refused with
`SERVICE_DISABLED` before any data access; it was not retried. No secret payload
was read. No code, IAM, Firestore, Rules, environment or Git history was
changed; the working tree is exactly as found.
