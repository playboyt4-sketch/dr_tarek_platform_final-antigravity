# ADR-010 — Mission 19: Default Library Identity Isolation Fix

**Mode:** local code remediation + regression tests + report. No deployment, no
remote write, no Production access, no Git history change.

**Branch:** `ci/ios-staging-codemagic`
**HEAD (unchanged):** `34a4b763e77087e0eeffd4aa8ad88bb820b61d46`
**Working tree:** preserved; 63 entries before and after (31 modified, 32
untracked, 0 staged, 0 deleted).

**Final status: PASS — LOCAL IDENTITY ISOLATION FIX VERIFIED**

---

## 1. Original Root Cause

Mission 18's S-1 defect was a two-part identity confusion:

1. `findBunnyLibraryDefinition` (in
   `functions/src/core/video/bunny_library_registry.ts`) special-cased the
   environment's canonical default, but then fell through to a loop over the
   compiled `BUNNY_LIBRARIES` array. In Staging
   (`BUNNY_DEFAULT_LIBRARY_ID=780700`) the loop still returned the compiled
   Production entry `736742`.
2. That compiled entry carries `isDefault: true`. `isBunnyLibraryActive`
   treated `isDefault` as an unconditional activation grant, and
   `planBunnyLibraryCredentialResolution`'s legacy branch
   (`!definition.isDefault || legacyFallbackDisabled`) therefore accepted
   `736742` with no catalog row and served it with the **environment's default**
   `BUNNY_STREAM_API_KEY` / `BUNNY_TOKEN_KEY` / `BUNNY_PLAYBACK_URL_TEMPLATE`,
   while the Stream API path came from `BUNNY_STREAM_LIBRARY_ID=780700`.

Observed in Mission 18 (Staging-like env, no catalog row):

```text
playback 736742 {"ok":true,"libraryId":"736742"}
stream   736742 {"ok":true,"libraryId":"736742","apiLibraryId":"780700"}
```

The compiled default entry was effectively a **second default library** in any
environment that overrode `BUNNY_DEFAULT_LIBRARY_ID`. That is the identity
substitution Mission 19 had to eliminate.

Preflight confirmed the working-tree source matched the Mission 18 findings
before any edit: the registry loop, the `isDefault` bypass and the resolver's
legacy branch were unchanged. The active Firebase alias is still
`dr-tarek-platform` with the `staging` alias `dr-tarek-staging`; no remote
command was needed or issued for this mission.

---

## 2. Exact Files Changed

| File | Change |
|---|---|
| `functions/src/core/video/bunny_library_registry.ts` | `findBunnyLibraryDefinition` no longer returns a compiled `isDefault` entry for a non-default id; `isBunnyLibraryActive` scopes the `isDefault` bypass to the environment's own canonical default. Comments updated to document the default-slot semantics. |
| `functions/test/bunny_library_secret_resolver.test.js` | Added the Mission 19 regression section (11 new checks, matrix below), including the exact Mission 18 probes and A/B identity isolation. |
| `functions/test/bunny_library_registry.test.js` | Added 5 pure registry checks for the same invariant (`findBunnyLibraryDefinition`, `isBunnyLibraryActive`, `resolveBunnyLibraryForResource`). |

Not changed: `functions/src/index.ts`, `bunny_library_secret_resolver.ts`,
`bunny_library_catalog*.ts`, `bunny_library_association.ts`,
`bunny_video_validation.ts`, `firebase.json`, `.firebaserc`, Rules, env files,
IAM, Firestore, Secret Manager, Bunny, deployment.

The three edited files are inside the pre-existing untracked Mission 17/18 set
(`functions/src/core/video/` and the new Bunny test files), so the working-tree
status counts did not change.

---

## 3. Exact Behavioral Changes

### 3.1 Registry lookup

`findBunnyLibraryDefinition(libraryId, env)` now has two disjoint paths:

- `libraryId === resolveDefaultBunnyLibraryId(env)` → the compiled default slot
  is returned with `libraryId` rewritten to the environment's default. This is
  the **only** way an `isDefault` definition is produced.
- Any other id → the compiled loop **skips every `isDefault` entry**. A
  non-default compiled entry (e.g. `775315`) still resolves. A foreign default
  id (e.g. `736742` while Staging runs `780700`) is `null` → `unknown_library`.

### 3.2 Activation

`isBunnyLibraryActive(definition, env)`:

```text
if definition.isDefault:
    return definition.libraryId === resolveDefaultBunnyLibraryId(env)
otherwise:
    return definition.libraryId is in BUNNY_ACTIVE_LIBRARY_IDS
```

`isDefault` is no longer a permission grant for an arbitrary id. Because the
lookup above never returns a foreign `isDefault` definition anyway, this is
defense in depth for direct callers and future registry edits.

### 3.3 Staging matrix (no catalog row, Staging-like env)

| Explicit id | Before | After |
|---|---|---|
| `780700` (canonical default) | accepted, own identity | accepted, own identity (unchanged) |
| `736742` (compiled Production default) | **accepted with 780700 credentials/API path** | `unknown_library` |
| `775315` (compiled non-default, inactive) | `library_not_activated` | `library_not_activated` (unchanged) |
| `999999` (unknown) | `unknown_library` | `unknown_library` (unchanged) |

Post-fix local probe (same environment as Mission 18):

```text
registry 780700 {"ok":true,"libraryId":"780700","source":"resource"}
registry 736742 {"ok":false,"reason":"unknown_library","libraryId":"736742"}
registry 775315 {"ok":false,"reason":"library_not_activated","libraryId":"775315"}
registry 999999 {"ok":false,"reason":"unknown_library","libraryId":"999999"}
playback 780700 {"ok":true,"libraryId":"780700"}
playback 736742 {"ok":false,"reason":"unknown_library","libraryId":"736742"}
playback 775315 {"ok":false,"reason":"library_not_activated","libraryId":"775315"}
playback 999999 {"ok":false,"reason":"unknown_library","libraryId":"999999"}
stream 780700 {"ok":true,"libraryId":"780700","apiLibraryId":"780700"}
stream 736742 {"ok":false,"reason":"unknown_library","libraryId":"736742"}
```

The two exact Mission 18 probes (`playback 736742`, `stream 736742`) now fail
closed before any secret read and never produce an `apiLibraryId`.

### 3.4 Callable impact

`validateBunnyVideoAssociation` already resolves the caller's library through
`resolveBunnyStreamApiCredentials`. With the fix, a Staging caller naming
`736742` receives the existing generic `unavailable` / `unknown_library` result
with `receipt: null`; no Bunny metadata call is made. `generateBunnySignedUrl`
and the display-media helpers already pass an explicit resolved library id, so
they inherit the same rejection.

---

## 4. Legacy Fallback Compatibility Impact

The approved ADR-010 legacy path is preserved exactly for the environment's
**own** canonical default:

- **Production (no override):** `resolveDefaultBunnyLibraryId` is still
  `736742`, the compiled default slot is returned for `736742`, the legacy
  branch still serves `BUNNY_STREAM_API_KEY` / `BUNNY_TOKEN_KEY` /
  `BUNNY_PLAYBACK_URL_TEMPLATE`, and `apiLibraryId` remains `736742`. Existing
  production behavior is byte-identical.
- **Staging (`BUNNY_DEFAULT_LIBRARY_ID=780700`):** `780700` remains the one
  default; its approved legacy path (no catalog row, fallback enabled) still
  uses the environment's global default values, and its Stream API path is
  `780700`. A catalog-backed `780700` still reads only
  `BUNNY_780700_STREAM_API_KEY` / `BUNNY_780700_TOKEN_KEY`.
- **Explicit `736742` in Staging:** no longer legacy, no longer default, no
  fallback → `unknown_library`.
- **`775315`:** unchanged; it stays inactive unless explicitly allow-listed,
  and even then cannot use legacy credentials without a catalog row.
- **`BUNNY_LEGACY_LIBRARY_FALLBACK=false`:** still turns the default's legacy
  path into `incomplete_configuration`; no fallback to any other library.

Compatibility loss is limited to the unsafe case: an environment that
overrides its canonical default and still expects explicit resources naming the
compiled Production id to resolve. Such a resource now fails closed until that
id is independently configured in the current environment (catalog row +
`BUNNY_ACTIVE_LIBRARY_IDS` + `BUNNY_<id>_*` secrets/template), at which point it
resolves with its **own** identity, not the local default's. Mission 18
recorded zero `lecture_resources` in Staging, so there is no live data impact
there.

No new environment-detection mechanism was introduced. The existing
`BUNNY_DEFAULT_LIBRARY_ID` override remains the sole environment selector, and
the compiled `736742` remains only the fallback for environments that do not
override it.

---

## 5. Environment Isolation Behavior

- The compiled Production id is **not** a universal default. It is reachable
  only when `resolveDefaultBunnyLibraryId(env) === "736742"`, i.e. in an
  environment that has not overridden the default (Production).
- In Staging, the compiled entry is a default **slot template** used only to
  synthesize the `780700` definition (legacy env-var names). It is never
  returned for `736742`.
- Allow-listing alone cannot resurrect a foreign default id: the lookup skips
  `isDefault` entries, so `BUNNY_ACTIVE_LIBRARY_IDS=736742` still yields
  `unknown_library` in Staging. Independent eligibility requires an
  authoritative `bunny_libraries/736742` row, which the resolver then derives
  with `BUNNY_736742_*` secret names and `apiLibraryId=736742` — no borrowing
  from `780700`.
- A Production runtime does not accept Staging's `780700` either: it is not a
  compiled entry and has no catalog row there → `unknown_library`.

---

## 6. Regression Test Matrix and Results

All checks below are in
`functions/test/bunny_library_secret_resolver.test.js` (Mission 19 section,
lines 688–1074) unless noted. The suite now reports **40 checks passed** (29
pre-existing + 11 new). `functions/test/bunny_library_registry.test.js` adds
**5** pure checks (35 total).

| # | Scenario | Expected | Result |
|---|---|---|---|
| 1 | Staging explicit `780700`, eligible catalog row | Accept exact id; own token key / Stream key / `apiLibraryId=780700`; default template | **PASS** |
| 2 | Staging explicit `780700`, approved legacy path | Accept exact id; global default values; `apiLibraryId=780700`; no Secret Manager read | **PASS** |
| 3 | Staging explicit `736742` (no catalog) | Reject `unknown_library`; no secret read; no fallback | **PASS** |
| 4 | Staging explicit `736742` + allow-list entry | Still reject `unknown_library` | **PASS** |
| 5 | Staging explicit `775315` | Reject `library_not_activated`; no secret read | **PASS** |
| 6 | Staging explicit `999999` | Reject `unknown_library` | **PASS** |
| 7 | Explicit unknown id with default configured | Reject; no fallback | **PASS** |
| 8 | Explicit inactive id with default configured | Reject; no fallback | **PASS** |
| 9 | Explicit incomplete id with default configured | `incomplete_configuration`; no fallback | **PASS** |
| 10 | Explicit disabled id with default configured | `library_not_activated`; no fallback | **PASS** |
| 11 | No explicit id + valid configured default | Resolve exact default `780700` (registry `legacy_default` + credentials) | **PASS** |
| 12 | Configured default absent from catalog, fallback disabled | Reject `incomplete_configuration` | **PASS** |
| 13 | Configured default catalog row disabled / unverified | Reject `library_not_activated` / `incomplete_configuration` | **PASS** |
| 14 | `isDefault` definition whose id is not the env default | `isBunnyLibraryActive=false`; runtime `library_not_activated` | **PASS** |
| 15 | Production id compiled but absent from Staging catalog | Reject `unknown_library` | **PASS** |
| 16 | Legacy fallback receives explicit non-default id | Reject; no legacy credentials | **PASS** |
| 17 | Library A request | Never resolves B's token key, Stream key, template or `apiLibraryId` | **PASS** |
| 18 | Library B request | Never resolves A's token key, Stream key, template or `apiLibraryId` | **PASS** |
| 19 | Exact Mission 18 playback probe (`736742`) | `unknown_library`, no secret read | **PASS** |
| 20 | Exact Mission 18 stream probe (`736742`) | `unknown_library`, no `apiLibraryId` | **PASS** |

Identity assertions in the successful cases cover `libraryId`, `apiLibraryId`,
the signing key value, the Stream API key value and the playback template
(including the per-id template for catalog libraries and the environment's
default template for the canonical default). Failure assertions check that no
secret value, secret name or Secret Manager path appears in the result; test
output prints only check names.

The registry-level checks additionally prove:

- `findBunnyLibraryDefinition("780700", stagingEnv)` → `{libraryId:"780700", isDefault:true}`
- `findBunnyLibraryDefinition("736742", stagingEnv)` → `null`
- `resolveBunnyLibraryForResource({storedLibraryId:"736742"}, stagingEnv)` →
  `unknown_library`
- `isBunnyLibraryActive(compiledDefaultEntry, stagingEnv)` → `false`
- `resolveBunnyLibraryForResource({storedLibraryId:"780700"}, stagingEnv)` →
  `{ok:true, libraryId:"780700", source:"resource"}`

No existing test expectation was weakened or deleted. The new tests extend the
existing suites; the pre-existing 29 resolver checks and 30 registry checks all
still pass unchanged.

---

## 7. Build, Lint, and Full Test Results

Actual commands and results (run from `functions/`):

| # | Command | Result |
|---|---|---|
| 1 | `npm run build` (`tsc`) | **exit 0** |
| 2 | `npm run test:pure` | **exit 0** — all 11 pure suites passed |
| 3 | `node test/bunny_library_registry.test.js` | **35 checks passed**, exit 0 |
| 4 | `node test/bunny_default_library_config.test.js` | **19 checks passed**, exit 0 |
| 5 | `node test/bunny_library_secret_resolver.test.js` | **40 checks passed**, exit 0 |
| 6 | `FUNCTIONS_DISCOVERY_TIMEOUT=120 npm test` | **56/56 files passed**, exit 0 |
| 7 | Emulator flow `bunny_library_secret_resolver_flow.test.js` (inside #6) | **9 checks passed**, exit 0 |
| 8 | ESLint on `bunny_library_registry.ts`, `bunny_library_secret_resolver.ts`, `bunny_library_association.ts`, `bunny_video_validation.ts` | **exit 0** (clean) |
| 9 | ESLint `src/index.ts` with `--rule 'linebreak-style: off'` | **15 errors / 19 warnings, all pre-existing**; `index.ts` was not modified by this mission |
| 10 | ESLint `src/core/video` (directory-wide) | **4 pre-existing JSDoc errors in `bunny_library_catalog.ts`** (lines 85/90, unchanged by this mission); the changed module is clean |

`test:pure` suite counts observed: registry 35, migration 37, playback
regression 33, video validation 26, association 37 assertions, catalog reader
30, secret resolver 40, plus the pre-existing non-Bunny suites (rolling window
11, guest migration 29, acceptance notification 7, final-decisions sub-suites).
The full suite includes the Mission 17 emulator flow (9 checks) and the
configurable-default suite (19 checks).

No test was skipped, and no security check was relaxed.

---

## 8. Git Status Before and After

| Item | Before | After |
|---|---|---|
| Branch | `ci/ios-staging-codemagic` | `ci/ios-staging-codemagic` |
| HEAD | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` |
| Total `git status --short` entries | 63 | 63 |
| Modified | 31 | 31 |
| Untracked | 32 | 32 |
| Staged | 0 | 0 |
| Deleted | 0 | 0 |

The complete status was captured before editing and re-checked after. The three
edited files are part of the pre-existing untracked set
(`functions/src/core/video/` and the Mission 17/18 test files), so no new
status entry was introduced. The new report lives under the already-untracked
`reports/` directory. No existing working-tree change was discarded or
overwritten; no commit, push, reset, stash, clean or checkout was performed.

---

## 9. Confirmation That No Remote Resources Were Changed

- No `firebase deploy`, `gcloud` mutation, Secret Manager write, IAM change,
  Firestore write, Rules change, Bunny API call, or environment change was
  made.
- The full suite ran against the local Firebase emulators
  (`demo-tarek-platform`); its Firestore writes are emulator-local only.
- No Production project was accessed.
- No secret payload was read.
- The only files created are this report and the two test/source edits above.

---

## 10. Remaining Blockers

Mission 19 fixes the local identity-isolation defect, but Staging is **not**
ready for per-library playback until the Mission 18 infrastructure gaps are
closed by separate, approved work:

| ID | Remaining item | Status |
|---|---|---|
| I-1 | Zero per-library secrets (`BUNNY_<id>_STREAM_API_KEY` / `_TOKEN_KEY`) exist in Staging | **Blocking provisioning** |
| I-2 | `bunny_libraries` catalog is empty and `BUNNY_ACTIVE_LIBRARY_IDS` is unset | **Blocking provisioning** |
| I-3 | Mission 17/19 code is not deployed to Staging (deployed bundle predates the resolver) | **Blocking deployment** |
| I-4 | Per-library `secretAccessor` bindings cannot exist until the secrets exist | **Blocking IAM verification** |
| I-5 | Provenance of the existing legacy secret values (Staging `780700` vs Production `736742`) is unverified; payload reads are forbidden | **Owner verification required** |
| N-1/N-2 | Deployed source archive contains `.env*`, tests and scripts | Non-blocking hardening |
| N-3 | Runtime SA holds `roles/editor` (no Secret Manager payload permission; per-secret bindings only) | Non-blocking hardening |
| N-4 | `buildBunnyFileUrl` / `bunnyStreamApiConfig` / `fetchBunnyVideoMeta` still have a compiled-default parameter default; all current call sites pass an explicit id, so it is latent | Non-blocking follow-up |
| N-5 | `BUNNY_LEGACY_LIBRARY_FALLBACK` is unset (implicitly enabled) | Set explicitly during migration |
| N-9 | Positive secret cache is 60 s, so a rotated-away key can be used briefly | Document in the rotation runbook |
| N-10 | `bunny_library_migration.ts` calls `findBunnyLibraryDefinition(id)` without the env snapshot, so a Staging dry-run would still treat the compiled id as the default for planner purposes. It issues no credentials and is not on the playback path. | Non-blocking follow-up: pass the env snapshot before running a Staging backfill |

One residual configuration invariant is worth stating explicitly: the default
library's Stream API path is still read from `BUNNY_STREAM_LIBRARY_ID`, as the
approved architecture requires for production compatibility. Staging currently
sets it to `780700` (equal to `BUNNY_DEFAULT_LIBRARY_ID`), so the default's
identity is consistent. The existing boot diagnostic
(`describeBunnyEnvironment`) warns if those two values ever diverge; a future
hardening mission can decide whether to turn that warning into a hard failure.

**What would change the status from PASS (local fix) to operational Staging
readiness:** provision `BUNNY_780700_*` secrets with per-secret accessor
bindings, seed `bunny_libraries/780700`, set
`BUNNY_ACTIVE_LIBRARY_IDS=780700`, deploy the Mission 17/19 code to Staging,
confirm the legacy secret provenance, and re-run this matrix plus the Mission 18
inventory/IAM audit.
