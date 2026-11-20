# ADR-010 — Mission 16: Firestore-Backed Bunny Library Catalog Read Path

Date: 2026-11-14
Environment target: `dr-tarek-staging` (design only — **nothing was deployed**)
Mode: **code + local tests only.** No deployment, no production access, no production
Firestore writes, no Bunny API calls, no secret rotation, no migration/backfill, no
Rules change, library `775315` not activated.

Verdict: **IMPLEMENTED AND TESTED LOCALLY (Staging deployment not performed by design).**

---

## 1. Files inspected (before any change)

| # | Path | Why |
|---|------|-----|
| 1 | `functions/src/core/video/bunny_library_catalog.ts` | Authoritative catalog schema, parser, activation gate, projection |
| 2 | `functions/src/core/video/bunny_library_registry.ts` | Env registry, `isBunnyLibraryActive`, default-library rules |
| 3 | `functions/src/index.ts` | Existing callables, `db` handle, `requireContentManager`, `bunnyLibraryEnvSnapshot` |
| 4 | `functions/src/core/video/bunny_library_association.ts` | Association/playback callables that must stay untouched |
| 5 | `functions/src/core/video/bunny_video_validation.ts` | Pre-write validation contract |
| 6 | `functions/src/core/utils/security_helpers.ts` | `SECURE_CALL_OPTS` (App Check) |
| 7 | `functions/src/index.ts` auth helpers (`requireAuthenticated`, `callerRole`, `requireDoctor`, `requireAdminOrDoctor`, `requireContentManager`) | Authorization policy |
| 8 | `firestore.rules` (`bunny_libraries` at line 160) | Server-only collection; no Rules change needed |
| 9 | `storage.rules` | Confirmed no Bunny library surface |
| 10 | `functions/test/bunny_library_validation_flow.test.js` | Emulator auth/fixture pattern reused |
| 11 | `functions/test/bunny_library_catalog.test.js` | Pure catalog test style |
| 12 | `functions/test/run_all.js`, `functions/package.json` | Suite registration |
| 13 | `reports/adr010/mission_8_library_onboarding_architecture.md` | §F.3.7 deny-list, §H.1 schema, §H.2 callable contract |
| 14 | `reports/adr010/FINAL_BUNNY_MULTI_LIBRARY_COMPLETION_REPORT.md` | Mission 15 status and blockers |
| 15 | Git branch/HEAD/working tree | Baseline captured below |

Authoritative schema found in code (takes precedence over Mission 8 prose where they differ):

```
bunny_libraries/{library_id}
  library_id: string            // digits, must equal the document id
  display_name: string          // non-blank
  status: "active" | "disabled" | "pending_verification" | "error"
  pull_zone_id: positive int
  playback_host: "<zone>.b-cdn.net"
  token_auth_enabled: boolean
  token_auth_verified: boolean  // probe-verified
  credential_refs: {stream_api_key: <secret NAME>, token_key: <secret NAME>}
  source, last_error_code, last_verified_* (server metadata)
```

`token_auth_enabled` + `token_auth_verified` is the existing, stricter split (Mission 8
mentions a single `token_auth_enforced`); code was treated as authoritative. This was
recorded as a documentation-vs-code wording difference, not a schema conflict: no new
field was introduced.

---

## 2. Files changed (this mission only)

Added:

| Path | Purpose |
|------|---------|
| `functions/src/core/video/bunny_library_catalog_reader.ts` | Pure eligibility/deny-list/ordering selection + Firestore adapter |
| `functions/test/bunny_library_catalog_reader.test.js` | Pure unit suite (30 checks) |
| `functions/test/bunny_library_catalog_flow.test.js` | Emulator callable suite (15 checks) |
| `reports/adr010/MISSION_16_BUNNY_LIBRARY_CATALOG_READ_PATH.md` | This report |

Modified (minimal, additive hunks only):

| Path | Change |
|------|--------|
| `functions/src/index.ts` | Import + `export *` of the reader; `listEligibleBunnyLibraries` callable after `requireContentManager` |
| `functions/test/run_all.js` | Registered the two new suites |
| `functions/package.json` | Appended the reader suite to `test:pure` |

No other file was touched. All pre-existing working-tree changes were preserved.

---

## 3. Callable contract

**Name:** `listEligibleBunnyLibraries`
**Type:** HTTPS callable (`onCall`), v2, default region `us-central1`
**Options:** `SECURE_CALL_OPTS` — App Check is enforced exactly when
`APP_CHECK_ENFORCEMENT === "true"` (unchanged project behavior; staging currently `false`,
which this mission did not alter).

Request:

```jsonc
// Payload is ignored. No client field can select a library, credential,
// Pull Zone, CDN host, or filter the result.
{}
```

Response (success):

```jsonc
{
  "libraries": [
    { "libraryId": "736742", "displayName": "Production" },
    { "libraryId": "780700", "displayName": "DrTarek Staging" }
  ]
}
```

- Ordering: ascending numeric library id, deterministic.
- Duplicates: removed by library id.
- The projection is closed: exactly `libraryId` and `displayName`.

Errors:

| Code | Cause |
|------|-------|
| `unauthenticated` | No Firebase Auth context (`requireAuthenticated`) |
| `permission-denied` | Student/other role, or admin without active `admin_content` |
| `unavailable` | Firestore catalog read failed (never returns a fake empty list) |

The callable reads **no secret**: it passes `{...process.env}` to the reader, which only
consumes `BUNNY_ACTIVE_LIBRARY_IDS`. It deliberately does **not** call
`bunnyLibraryEnvSnapshot()` (which resolves the Stream API key), so a read-only endpoint
has zero secret surface.

---

## 4. Authorization matrix

Authorization is the existing `requireContentManager` helper — no new policy, no bypass.

| Caller | `role` claim | `admin_permissions/{uid}` | Result |
|--------|--------------|---------------------------|--------|
| Unauthenticated | — | — | `unauthenticated` |
| Student | `student` | — | `permission-denied` |
| Doctor (Platform Owner) | `doctor` | not required | **allowed** |
| Admin, active + `admin_content: true` | `admin` | `is_active: true`, `permissions.admin_content: true` | **allowed** |
| Admin, active, no `admin_content` | `admin` | `is_active: true`, `permissions: {}` | `permission-denied` |
| Admin, `admin_content: true` but inactive | `admin` | `is_active: false` | `permission-denied` |
| Any other role | e.g. `teacher` | — | `permission-denied` |

Firestore Rules are untouched: `match /bunny_libraries/{libraryId} { allow read, write: if false; }`.
Clients still cannot read the collection directly; the callable uses the Admin SDK.

---

## 5. Eligibility behavior (fail closed)

A document is eligible only when **all** of the following hold; otherwise it is dropped
silently (no fallback library, no partial entry):

1. Parses as a catalog entry (`parseBunnyCatalogEntry`):
   - `library_id` matches `^\d{1,20}$`;
   - `display_name` non-blank;
   - `status` in `active | disabled | pending_verification | error`;
   - `pull_zone_id` positive integer;
   - `playback_host` matches `^[a-z0-9][a-z0-9-]{0,62}\.b-cdn\.net$`;
   - `credential_refs.stream_api_key` / `credential_refs.token_key` are deterministic
     secret **names** (`BUNNY_<libraryId>_STREAM_API_KEY`, `BUNNY_<libraryId>_TOKEN_KEY`);
     a raw secret-looking value fails validation.
2. `status === "active"`.
3. `token_auth_enabled === true`.
4. `token_auth_verified === true` (a dashboard toggle alone is never enough).
5. Document id **equals** `library_id` (Mission 8 §H.1) — mismatches are malformed.
6. Emergency deny-list (`BUNNY_ACTIVE_LIBRARY_IDS`, Mission 8 §F.3.7):
   - unset/blank → not engaged, no reduction;
   - non-empty → only listed ids may pass (intersection with the gate above);
   - malformed non-empty (names no valid numeric id) → **deny all** (fail closed);
   - it can only reduce eligibility, never expand it (an inactive listed library stays out).

Deterministic ordering is length-aware numeric (`9` before `10`), and duplicate documents
are de-duplicated by `libraryId`.

---

## 6. Tests executed and actual results

All commands were run locally in `functions/` unless stated. Emulator suites used the
Firebase Emulator Suite only.

| # | Command | Exit | Result |
|---|---------|------|--------|
| 1 | `npm run build` (`tsc`) | 0 | Clean compile |
| 2 | `npx eslint src/core/video/bunny_library_catalog_reader.ts` | 0 | No findings |
| 3 | `node test/bunny_library_catalog_reader.test.js` | 0 | **30 checks passed** |
| 4 | `npm run test:pure` | 0 | All pure suites pass, incl. 30 new checks |
| 5 | `FUNCTIONS_DISCOVERY_TIMEOUT=120 npm test` (firestore+functions+auth) | 0 | **55/55 files passed** (was 53 files before this mission; 2 added) |
| 6 | `npx firebase emulators:exec --project dr-tarek-platform-rules-test --only firestore,storage "node security-tests/rules.test.js && node security-tests/adr010_association_rules.test.js"` | 0 | `Firestore and Storage rules tests passed.` + `adr010_association_rules: 21 assertions passed` |

New emulator suite output (`bunny_library_catalog_flow.test.js`, 15 checks):

```
ok - unauthenticated caller is denied (denied unauthenticated)
ok - student caller is denied (denied permission-denied)
ok - admin without admin_content is denied (denied permission-denied)
ok - inactive admin with admin_content is denied (denied permission-denied)
ok - doctor sees exactly the active + verified library
ok - delegated admin_content sees the same closed projection
ok - unverified/disabled/pending/incomplete/mismatched libraries are excluded
ok - library 775315 is never listed
ok - deny-list naming the eligible library keeps it
ok - deny-list cannot resurrect an ineligible library
ok - deny-list intersects with the eligibility gate
ok - malformed deny-list fails closed
ok - blank deny-list is treated as not engaged
ok - absent deny-list does not reduce eligibility
ok - empty catalog returns an empty list
```

New pure suite covers: eligible active, disabled, `pending_verification`, `error`,
token-auth disabled, token-auth unverified, missing display name, missing/invalid pull
zone, missing playback host, missing credentials, credential-value-masquerading-as-name,
invalid library id, document-id mismatch, null document, deny-list (absent / reducing /
empty result / no expansion / blank / malformed), empty catalog, mixed states, numeric
ordering, duplicates, closed projection (no `BUNNY_`, no host, no pull zone), Firestore
adapter mapping, and adapter read-failure propagation.

Two failures occurred during the work and were fixed/attributed:

1. **Test fixture bug (fixed):** the emulator flow test first seeded
   `credential_refs: undefined`, which the Firestore SDK rejects
   (`Cannot use "undefined" as a Firestore value`). The fixture now strips `undefined`
   fields before writing (`writeCatalog`). Test-only change.
2. **Wrong emulator project id (invocation error, not a regression):** the rules suite was
   first run with `--project demo-tarek-platform`, which produced a cross-project Storage
   `firestore.get()` null-value error at `storage.rules:26`. Re-running with the documented
   project id `dr-tarek-platform-rules-test` passed. No Rules or source file was changed.

Pre-existing noise, unrelated to this mission: the module-load ADR-010 boot diagnostic
(`if (process.env.NODE_ENV !== "test")`) calls `bunnyLibraryEnvSnapshot()`, so the
Functions emulator logs one `No value found for secret parameter "BUNNY_STREAM_API_KEY"`
warning per process. The new callable does not trigger it.

---

## 7. Security review

| Requirement | Status |
|-------------|--------|
| Never return Stream API keys | **Met** — response is `{libraryId, displayName}` only |
| Never return token signing keys | **Met** — no key material is read or returned |
| Never return Secret Manager values or references | **Met** — `credential_refs` is consumed only as a validation signal, never projected; callable reads no secret at all |
| Never return credentials/env/config | **Met** — closed projection; `pull_zone_id`, `playback_host`, `source`, `last_error_code`, verification stamps all dropped |
| Client cannot choose credentials / Pull Zone / CDN host | **Met** — request payload is ignored |
| Unknown/disabled/incomplete/invalid fails closed | **Met** — pure gate + doc-id check + deny-list; no fallback library |
| App Check preserved | **Met** — same `SECURE_CALL_OPTS` as every other callable |
| Staff authorization preserved | **Met** — `requireContentManager` (doctor always, delegated admin only with active `admin_content`) |
| Firestore Rules not weakened | **Met** — `bunny_libraries` remains `allow read, write: if false` |
| No new database field | **Met** — only existing §H.1 fields are read |
| Error messages do not leak internals | **Met** — generic `unavailable`; details only in server logs |
| Playback signing / subscription / device / preview / takeover untouched | **Met** — no edits to those modules |
| Library `775315` not activated | **Met** — no env/doc change; test asserts it is never listed |
| No migration/backfill | **Met** |

Threat notes:

- The deny-list is an environment variable only; a malformed non-empty value denies
  everything rather than silently disabling the kill switch.
- A malicious/incorrect catalog document cannot expose a secret: values that look like
  secrets fail the credential-name pattern, and the projection never includes refs.
- A Firestore outage cannot be mistaken for "no libraries available" (no silent empty
  success); it surfaces as `unavailable`.
- Reading `{...process.env}` exposes nothing to the client; only
  `BUNNY_ACTIVE_LIBRARY_IDS` is consumed by the reader.

---

## 8. Git status before and after

Branch: `ci/ios-staging-codemagic`
HEAD (unchanged): `34a4b763e77087e0eeffd4aa8ad88bb820b61d46`

| Snapshot | Total | Modified | Untracked | Staged | Deleted |
|----------|-------|----------|-----------|--------|---------|
| Before | 58 | 30 | 28 | 0 | 0 |
| After | 60 | 30 | 30 | 0 | 0 |

Delta = the 2 new test files (`bunny_library_catalog_reader.test.js`,
`bunny_library_catalog_flow.test.js`). The new reader source lives inside the
already-untracked `functions/src/core/video/` directory, so it does not add a status
entry. `index.ts`, `run_all.js` and `package.json` were already modified before this
mission; only additive hunks were introduced.

No `git add`, `commit`, `push`, `reset`, `stash`, `clean`, or deploy was run.

---

## 9. Remaining blockers (not addressed here)

1. **No staging deployment in this mission (by design).** The callable exists in source
   only; staging does not serve it yet. Deployment requires explicit approval.
2. **Staging catalog data is empty.** With no `bunny_libraries` documents, the callable
   correctly returns `{libraries: []}`; it cannot be validated against real staging data
   without a separately approved catalog write (no writes were performed).
3. **Dashboard picker is not wired.** No approved Figma spec; the Dashboard still uses its
   local catalog. The callable is ready for that wiring.
4. **Catalog is not yet consumed by playback resolution.** Wiring it requires an approved
   decision on the secret contract (`BUNNY_<libraryId>_*` vs per-environment `BUNNY_*`).
5. **Production drift (pre-existing):** production lacks
   `validateBunnyVideoAssociation` / `associateBunnyVideoToLibrary` and its deployed Rules
   are stale. Out of scope; untouched.
6. **`test:pure` gap (pre-existing):** `bunny_library_catalog.test.js` is still not listed
   in `test:pure`. Only the new reader suite was appended; the pre-existing gap was left
   alone to avoid unrelated changes.
7. **Staging App Check is `false`** (pre-existing). This mission preserved that behavior;
   enabling it is a separate decision.
8. **Boot-diagnostic warning noise** described in §6 (pre-existing).

---

## 10. Production confirmation

**Production was not touched.** No production deployment, no production Firestore read or
write, no production Bunny API call, no production secret access or rotation, no production
Rules/IAM/env change. All Firestore and Auth activity in this mission occurred inside the
local Firebase Emulator Suite. Library `775315` was not activated, and verified playback
signing was not modified.
