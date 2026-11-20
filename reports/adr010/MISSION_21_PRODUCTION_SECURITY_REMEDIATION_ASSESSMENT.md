# ADR-010 — Mission 21: Production Security Remediation Assessment

**Mission:** strictly read-only assessment of the Production security finding (malformed
`APP_CHECK_ENFORCEMENT`), its scope, and the safe remediation sequence.
**Date:** 2026-11-16
**Repository:** `D:\antigravity\dr_tarek_platform_final`
**Branch:** `ci/ios-staging-codemagic` — **HEAD `34a4b763e77087e0eeffd4aa8ad88bb820b61d46`** (unchanged)
**Mode:** READ-ONLY. No Production resource, Staging resource, secret, IAM binding, Firestore document,
rule, deployment or Git state was modified.

**Final decision: `READY FOR EXPLICIT PRODUCTION REMEDIATION APPROVAL`**

---

## 1. Executive Summary

The Production security problem is now fully characterised. It is **one root cause with three effects**:

1. **Configuration corruption (confirmed, deployed on every function).**
   `APP_CHECK_ENFORCEMENT` on **all 79 Production Cloud Functions** holds a single **97-character,
   whitespace-free value** composed of three separate intended assignments concatenated together:

   | Segment | Length | Meaning |
   | --- | --- | --- |
   | `false` | 5 | the intended boolean literal |
   | `BUNNY_STREAM_API_KEY` | 20 | an environment-variable **name** |
   | *(opaque token)* | 41 | a **Bunny Stream API key value** (charset `[A-Za-z0-9_-]`) |
   | `BUNNY_STREAM_LIBRARY_ID` | 23 | another environment-variable **name** |
   | `736742` | 6 | the Production Bunny library id |

   Total = 97 characters, 2 embedded `=` signs, no newline, no space. The three `KEY=value` lines were
   flattened into one line, so `APP_CHECK_ENFORCEMENT` no longer holds a boolean.

2. **Enforcement evaluates to `false` (confirmed by code + deployed value).**
   `SECURE_CALL_OPTS = { enforceAppCheck: process.env.APP_CHECK_ENFORCEMENT === "true" }`
   (`functions/src/core/utils/security_helpers.ts`, form introduced by commit `46e20f9`, 2026-08-31, and
   unchanged since). A 97-character value is never the literal `"true"`, so **App Check enforcement has
   been OFF on every Production callable since the 2026-10-08 deployment** — while the commit that
   introduced the switch was titled *"enabled appcheck enforcement"*.

3. **A Bunny Stream API key is stored in plaintext in Production control-plane metadata.**
   The same 41-character value is additionally present as a **separate plaintext environment variable
   `BUNNY_STREAM_API_KEY` on all 79 functions** (byte-identical to the segment embedded in
   `APP_CHECK_ENFORCEMENT` — verified by in-memory equality, never printed), and is also in the
   git-ignored local `functions/.env`. Production has **no `BUNNY_STREAM_API_KEY` Secret Manager secret**,
   and **no function mounts it from Secret Manager**; the Secret Manager path required by the current
   source code therefore does not exist in Production yet.

Exposure scope: **`POTENTIALLY EXPOSED`** — plaintext presence in readable control-plane metadata is
confirmed; actual reads, validity of the key, and any leak outside Google Cloud could not be established
without using the credential or reading its payload (both prohibited here).

Nothing was changed. The remediation plan (§11) is ordered, complete, and executable only after explicit
owner approval.

---

## 2. Verified Environment Identity

| Item | Verified value | Evidence |
| --- | --- | --- |
| Active gcloud project | `dr-tarek-platform` | `gcloud config list` |
| Production project id | `dr-tarek-platform` | `gcloud projects describe` |
| Production project number | `606744934510` | `gcloud projects describe` |
| Production project state / created | `ACTIVE`, `2026-08-10T15:34:37.094Z` | `gcloud projects describe` |
| Staging project id / number | `dr-tarek-staging` / `13159003436`, `ACTIVE` | `gcloud projects describe` (metadata only — see §13 D-1) |
| Active gcloud identity | authenticated **user** account present; domain `yahoo.com`; local part not recorded | `gcloud config list` (masked) |
| Firebase CLI project mapping | `default` → `dr-tarek-platform`; `staging` → `dr-tarek-staging` | `.firebaserc` |
| Cloud Functions region | `us-central1` (single region, all 79 functions) | function resource names |
| Firebase Hosting site | `dr-tarek-site` = `dr-tarek-platform` | `firebase.json` |
| Firestore database | `(default)`, `us-central1` | `firebase.json` |
| Production Bunny library id | `736742` | function env `BUNNY_STREAM_LIBRARY_ID` |
| Production catalog | `bunny_libraries` = **0 documents** | Firestore REST read, HTTP 200 |

**Separation:** Production and Staging are two distinct projects with distinct numbers, runtime service
accounts (`606744934510-compute@…` vs `13159003436-compute@…`), secret projects, and library ids
(`736742` vs `780700`). No Production value was found in Staging evidence and vice versa.

Every remote command in this mission was pinned with `--project=dr-tarek-platform` (or read the project
explicitly in the REST URL). Identity is conclusively established, so the assessment proceeded.

---

## 3. Production `APP_CHECK_ENFORCEMENT` Findings

### 3.1 Exact configuration mechanism

| Question | Finding |
| --- | --- |
| Where does the value come from? | A **plain Cloud Functions (Gen 2) environment variable**, materialised in `serviceConfig.environmentVariables` of every deployed function. |
| Is it a Secret Manager reference? | **No.** No `secretKeyRef`; `secretEnvironmentVariables` on the relevant functions list only `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STORAGE_*`. |
| Is it a `defineSecret` param? | **No.** Nothing declares it as a parameter or secret. |
| What writes it? | The repo's git-ignored `functions/.env`, loaded by the Firebase CLI at deploy time and shipped into each function's environment. |
| Is the malformed value actually deployed? | **Yes — on 79/79 functions** (`gcloud functions list --format=json`, read-only). |
| Where else does it exist? | The git-ignored working copy `functions/.env` (2 lines total; the whole value is on the `APP_CHECK_ENFORCEMENT` line). |

### 3.2 How the source evaluates it

`functions/src/core/utils/security_helpers.ts` (whole file, 5 lines):

```ts
export const SECURE_CALL_OPTS: CallableOptions = {
  enforceAppCheck: process.env.APP_CHECK_ENFORCEMENT === "true",
};
```

- Strict equality against the literal `"true"`; anything else (including a 97-character blob, `"TRUE"`,
  `"1"`, whitespace) evaluates to `false`.
- The value is read **once per isolate at module load**, so it cannot be corrected without a new
  deployment (or a new revision).
- `SECURE_CALL_OPTS` is applied to **69 callables** (70 references in `functions/src/index.ts`: 69
  `onCall(SECURE_CALL_OPTS, …)` + 1 import). The remaining deployed functions are triggers/schedules,
  which are not callables.

### 3.3 Which deployed functions consume it

**All of them.** Every one of the 79 deployed functions carries the identical 97-character value, e.g.
`generateBunnySignedUrl`, `getLectureResources`, `verifyPhonePassword`, `registerNewStudent`,
`recalculateSubjectProgress`, and the 73 others listed in §5.

### 3.4 Evaluation result

| Question | Answer |
| --- | --- |
| Does the malformed value cause `enforceAppCheck: true`? | **No.** |
| Does it cause `false`? | **Yes.** `"<97 chars>" === "true"` is `false`. |
| Any third state? | None. `enforceAppCheck` is a boolean; no parse error, no exception, no boot failure. |
| Was the deployed code the same comparison? | **Yes.** The deployed revision is from the 2026-10-08 deployment of code dated ≤ `ff85ce0` (2026-09-23); every revision of `security_helpers.ts` since `46e20f9` (2026-08-31) uses `=== "true"`. |
| Consequence | Callables still require a Firebase Auth ID token (authorization is intact), but **client attestation (App Check) is not enforced**, i.e. an attestation fail-open, not an authorization bypass. |

### 3.5 Logging and return surfaces

| Surface | Finding |
| --- | --- |
| Function code logging the value | **None.** The only boot diagnostic (`describeBunnyEnvironment`) logs library **ids** (`defaultLibraryId`, `streamApiLibraryId`) — never `APP_CHECK_ENFORCEMENT`. |
| Function code returning the value to a client | **None.** `bunnyLibraryEnvSnapshot()` is explicitly server-only and never serialised; `listEligibleBunnyLibraries` (not deployed in Production) projects only `{libraryId, displayName}`. |
| Cloud Logging | A 365-day query for entries mentioning `APP_CHECK_ENFORCEMENT` in `cloud_function` logs returned **0 entries**. |
| Error messages | `getEnv()` can echo a **variable name** in a `failed-precondition` message, never a value. |

### 3.6 Exposure surfaces for the embedded credential (metadata-only analysis)

| Surface | Status | Notes |
| --- | --- | --- |
| Function environment metadata (`cloudfunctions.functions.get`) | **CONFIRMED PRESENT** | Readable by any principal with function-viewer rights on `projects/606744934510` (or `roles/editor`/`roles/owner`). Present on **79 functions**, in two places per function (`BUNNY_STREAM_API_KEY` and inside `APP_CHECK_ENFORCEMENT`). |
| Local working copy `functions/.env` | **CONFIRMED PRESENT** | Git-ignored (`.gitignore:64`), never committed. |
| Git source control (working tree) | **NOT PRESENT** | In-memory scan of all **tracked** files for the exact 41-character token: **0 hits**. |
| Git history (all refs, all objects) | **NOT PRESENT** | In-memory scan of **5,115** blob objects across `--all`: **0 hits**. `functions/.env` was never added to history. |
| Deployed source archive (`gs://gcf-v2-sources-606744934510-us-central1/<function>/`) | **UNVERIFIED** | The per-function source archives exist (metadata listed). Whether the uploaded zip contains `functions/.env` (Mission 18 N-1 reported that it did on Staging) can only be established by downloading the archive — downloading may expose the key payload and is therefore out of scope. |
| Cloud Logging (value-level) | **UNVERIFIED** | Verifying that the exact token never appears in log payloads requires submitting the token as a query term (or writing it to disk), i.e. handling the payload, which this mission forbids. The variable-*name* query is clean (0 entries). |
| Cloud Audit Logs (who read function metadata) | **NO ENTRIES FOUND** | 90-day query for `CloudFunctionsService.GetFunction` / `FunctionService.GetFunction` returned 0 entries. This does **not** prove nobody read it (audit retention/shape limits apply); it only shows no such entries are queryable. |
| Build artifacts (`functions/lib`) | **NOT PRESENT** | Compiled JS contains the comparison, never env values. |
| Flutter/Hosting bundle (`build/web`) | **NOT PRESENT BY DESIGN** | Server-only variable; no client code reads it. |
| Reports in this repo | **NOT PRESENT** | All earlier reports state "value redacted"; the token scan over `reports/` found 0 hits. |

---

## 4. Production Secret Manager Inventory

Metadata only. No secret version payload, no fingerprint, no access token was read.

| Secret | Exists | Versions (state) | Created | Purpose |
| --- | --- | --- | --- | --- |
| `BUNNY_STREAM_API_KEY` | **NO — absent** | — | — | **Required by current source** (`defineSecret`); currently supplied only as a plaintext env var |
| `BUNNY_TOKEN_KEY` | yes | `1` enabled, `2` enabled, `3` enabled (latest 3, 2026-10-02) | 2026-08-25 | Pull-zone token signing |
| `BUNNY_PLAYBACK_URL_TEMPLATE` | yes | `1`, `2` enabled (latest 2, 2026-09-28) | 2026-08-25 | Playback URL template |
| `BUNNY_STORAGE_BASE_URL` | yes | `1` enabled | 2026-08-25 | Storage-zone base URL |
| `BUNNY_STORAGE_ZONE_NAME` | yes | `1` enabled | 2026-08-25 | Storage-zone name |
| `BUNNY_STORAGE_PASSWORD` | yes | `1` enabled | 2026-08-25 | Storage-zone password |

- **Per-library secrets (`BUNNY_<id>_STREAM_API_KEY` / `BUNNY_<id>_TOKEN_KEY`): none exist** (including
  none for `736742`).
- No disabled or destroyed versions block rotation; all listed versions are `enabled`.
- Secret replication: automatic (project default); all in `projects/606744934510`.

**Deployed functions that reference each secret (via `secretEnvironmentVariables`):**

| Function | Mounted secrets |
| --- | --- |
| `generateBunnySignedUrl` | `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE` |
| `getLectureResources` | `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_PLAYBACK_URL_TEMPLATE` |
| `getSectionDisplayMedia` | `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_PLAYBACK_URL_TEMPLATE` |
| `generateBunnyResourceUrl` | `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL` |
| `uploadBunnyResource` | `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STORAGE_PASSWORD` |
| `deleteBunnyResource` | `BUNNY_TOKEN_KEY`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STORAGE_PASSWORD` |

`BUNNY_STREAM_API_KEY` is mounted by **no** function — it is a plaintext env var on all 79, because the
deployed code predates the ADR-010 `defineSecret` change.

---

## 5. Cloud Functions Deployment Inventory

| Property | Value |
| --- | --- |
| Total deployed functions | **79** |
| Generation | GEN_2 (all) |
| Region | `us-central1` (all) |
| Runtime service account | `606744934510-compute@developer.gserviceaccount.com` (all 79) |
| Deployment window (updateTime) | **2026-10-08T17:11:19Z … 2026-10-08T17:12:40Z** (one batch) — no deployment since |
| `firebase-functions-hash` labels present | 7 distinct hashes (`aacc1445…`, `f044e57a…`, `f6775c4e…`, `450437b5…`, `2386ac0b…`, `e4c32fe8…`, `d0e32d43…`) → several source snapshots, all deployed the same day |
| Env vars present on all | `APP_CHECK_ENFORCEMENT` (97 chars, malformed), `BUNNY_STREAM_API_KEY` (41 chars, plaintext), `BUNNY_STREAM_LIBRARY_ID=736742`, plus platform vars (`GCLOUD_PROJECT`, `FIREBASE_CONFIG`, `EVENTARC_CLOUD_EVENT_SOURCE`, `FUNCTION_TARGET`, `FUNCTION_SIGNATURE_TYPE`, `LOG_EXECUTION_ID`) |
| Env vars **absent** | `BUNNY_DEFAULT_LIBRARY_ID`, `BUNNY_ACTIVE_LIBRARY_IDS`, `BUNNY_LEGACY_LIBRARY_FALLBACK` |
| Functions with Secret Manager mounts | 6 (table in §4) |
| ADR-010 callables present | **NONE** — `listEligibleBunnyLibraries`, `validateBunnyVideoAssociation`, `associateBunnyVideoToLibrary` are **not deployed** |
| Bunny callables present | `generateBunnySignedUrl`, `generateBunnyResourceUrl`, `getLectureResources`, `getSectionDisplayMedia`, `uploadBunnyResource`, `deleteBunnyResource` |
| Firestore catalog | `bunny_libraries` = 0 documents (HTTP 200) |
| Ingress | `ALLOW_ALL` (callables are intended to be public-invokable) |

Complete function list (79):
`activateFreePlan, addAdmin, approveStudent, autoPublishDueLectures, beginOrTakeoverPlayback,
changePassword, changeStudentGrade, cleanupInvalidDeviceTokens, convertStudentType, correctPaymentLog,
createCustomGroup, createExceptionalAcademicPeriod, createSubject, deleteAccountByOwner,
deleteBunnyResource, deleteMyAccount, deleteSubject, downgrade, enforceDisplayHandleUniqueness,
enforceOneSubscriptionPerSubject, generateBunnyResourceUrl, generateBunnySignedUrl,
generatePdfDownloadUrl, generateProtectedPdfUrl, getAcademicPeriods, getActiveCustomGroups,
getLectureResources, getSectionDisplayMedia, getSubjectAccessConfig, getVideoWatchWindow,
grantSubjectAccessWithPlan, heartbeatPlayback, initializeAcademicPeriods, listStaffDirectory,
onDeviceChangeRequest, onDeviceTokenRefresh, onLectureAccessGrantWritten, onLectureResourceWritten,
onLectureWritten, onLoginAttempt, onPasswordResetApproved, onPasswordResetRequest, onPaymentLogged,
onSectionWritten, onSecurityEvent, onStudentApproved, processNotificationQueue,
propagatePlanFeatureChange, recalculateSubjectProgress, registerNewStudent, rejectStudent, removeAdmin,
renew, resetStudentDevices, resolveSubjectTier, revalidateOfflineAccess, sendPushNotification,
setAcademicPeriodStatus, setAdminPermissions, setDefaultStorageProvider, setPlanFeature,
setPlanQualityFeature, setPlatformFeature, setStudentFinancialAccount, setStudentSubjectPricing,
setSubjectAccess, setSubscriptionDisciplinaryStatus, submitAssessmentAttempt, submitExamAttempt,
submitPasswordResetRequest, unbindSubjectDevice, updateCustomGroup, updateStudentGrade,
updateStudentProfileByStaff, updateSubject, upgrade, uploadBunnyResource, verifyPhonePassword,
verifyStaffPassword`

**Interpretation:** Production runs a **pre-ADR-010, single-library** deployment whose Stream metadata
path reads a plaintext global key, and whose App Check switch is a corrupted string. It is internally
consistent (it works as a v1 single-library system) but is **not** the Mission 16/17/19 architecture.

---

## 6. Service Account and IAM Findings

| Item | Finding |
| --- | --- |
| Runtime SA (all functions) | `606744934510-compute@developer.gserviceaccount.com` |
| Project roles of the runtime SA | `roles/editor`, `roles/eventarc.eventReceiver`, `roles/run.invoker`, and project-level `roles/iam.serviceAccountTokenCreator` (shared binding with 3 other SAs) |
| Secret access | `roles/secretmanager.secretAccessor` bound **per secret** on each of the 5 existing Bunny secrets, to the same SA — **least privilege, no project-level Secret Manager role** |
| Project-level Secret Manager roles | **none** (`roles/secretmanager.admin` / `secretAccessor` absent from the project policy) |
| Dedicated least-privilege runtime SA | does not exist (carried over as N-3 from Mission 18) |
| `roles/owner` members | 1 user member (the project owner) |
| Firebase Admin SDK SA | `firebase-adminsdk-fbsvc@dr-tarek-platform.iam.gserviceaccount.com` — has `firebaseappcheck.admin`, `firebaseauth.admin`, `storage.admin`, `iam.serviceAccountTokenCreator`, `firebase.sdkAdminServiceAgent` |
| Secret Manager IAM needed for the remediation | `roles/secretmanager.secretAccessor` on the **new** `BUNNY_STREAM_API_KEY` secret for `606744934510-compute@…` only. No project-level grant. |
| IAM changes performed | **none** |

Note: `roles/editor` does not include `secretmanager.versions.access`; secret payload access comes only
from the per-secret `secretAccessor` bindings. Plaintext env vars, by contrast, are readable by any
principal with `cloudfunctions.functions.get` on the project — a materially weaker trust boundary, which
is why §3.6 treats the env-var storage as an exposure surface while Secret Manager storage is not.

---

## 7. Credential Exposure Assessment

**Classification: `POTENTIALLY EXPOSED`.**

| Dimension | Status | Evidence |
| --- | --- | --- |
| Plaintext storage in a readable control plane | **CONFIRMED** | 79 functions × 2 copies (dedicated env var + embedded in `APP_CHECK_ENFORCEMENT`), via `gcloud functions list --format=json` |
| Present in local git-ignored file | **CONFIRMED** | `functions/.env` (2-line file, 97-char value) |
| Present in Git working tree (tracked files) | **NO EVIDENCE** | 0 hits across all tracked files |
| Present in Git history (all refs, 5,115 blobs) | **NO EVIDENCE** | 0 hits |
| Present in Cloud Function logs (by variable name) | **NO EVIDENCE** | 0 entries in 365 days |
| Present in Cloud Function logs (by value) | **UNKNOWN** | Would require handling the payload as a query term |
| Present in deployed GCS source archive | **UNKNOWN** | Would require downloading the archive |
| Present in client bundles / Hosting | **NO EVIDENCE** | Value is server-only; token scan of the repo found it nowhere in client code |
| Was it read by a third party | **UNKNOWN** | Audit query for function-get returned 0 entries; insufficient to prove non-access |
| Is the key still valid at Bunny | **UNKNOWN** | Proving validity requires sending it to the Bunny API — not authorised (would also create a new access event) |
| Was it rotated after the corruption | **UNKNOWN / NO EVIDENCE** | Production has no redacted rotation record; the value persists on all 79 functions since 2026-10-08 |

**Why not `CONFIRMED EXPOSED`:** presence in a plaintext configuration field is confirmed, but exposure is
only "exposure" once someone with read rights actually sees it. No evidence of a third-party read, of
publication, or of validity exists.

**Why not `NO EVIDENCE OF EXPOSURE`:** the value sits in the clearest plaintext location Google Cloud
offers (function env metadata, readable by every function-viewer), it has been there since 2026-10-08,
and it was also flattened into a *non-secret* variable whose content nobody audits. Any principal able to
describe functions — including CI service accounts and temporary elevated access — could have read it.

**Blast radius if valid:**
- **What it can do:** read Bunny Stream metadata for library `736742` (video list/details, thumbnail
  filenames, status, and any other Stream control-plane read); it is a **library-scoped Stream API key**,
  as proven on Staging evidence — it is rejected by the Bunny **account** API (HTTP 401), so it cannot
  read pull-zone `ZoneSecurityKey`, cannot create/delete videos at account scope, and cannot reach other
  libraries.
- **What it cannot do:** sign playback URLs (that is `BUNNY_TOKEN_KEY`), read Storage-zone credentials, or
  impersonate the platform.
- **Impact:** metadata disclosure/enumeration of one library; no playback forgery, no write access proven.

---

## 8. Source-versus-Production Consistency

| Area | Local source (HEAD) | Production deployment | Consistent? |
| --- | --- | --- | --- |
| Stream API key handling | `defineSecret("BUNNY_STREAM_API_KEY")` mounted per callable | plaintext env var, **not** a secret, **not** mounted | **NO** |
| Secret Manager surface | `BUNNY_STREAM_API_KEY` must exist | secret **does not exist** | **NO** — deploy blocker |
| Library registry (Mission 19 identity isolation) | present | absent (pre-ADR-010 code) | **NO** |
| Catalog reader (Mission 16) | present | absent | **NO** |
| Per-library secret resolver (Mission 17) | present | absent | **NO** |
| ADR-010 callables (`listEligibleBunnyLibraries`, `validateBunnyVideoAssociation`, `associateBunnyVideoToLibrary`) | present | **not deployed** | **NO** |
| `BUNNY_DEFAULT_LIBRARY_ID` / `BUNNY_ACTIVE_LIBRARY_IDS` / `BUNNY_LEGACY_LIBRARY_FALLBACK` | consumed by code | absent from env | **NO** (defaults apply) |
| `bunny_libraries` catalog | enforced by rules `allow read, write: if false` (local `firestore.rules:160`) | collection empty | **YES (empty = inert)** |
| `APP_CHECK_ENFORCEMENT` parsing | `=== "true"` | same comparison, corrupted value → `false` | logic same, **value broken** |
| Cross-library credential selection | impossible by design (catalog-name mismatch check, activation gate, no fallback) | not reachable (ADR-010 absent); legacy single-library path uses the global key for `736742` | **NO (structurally different, not a defect in deployed runtime)** |
| Fail-open behaviour | `enforceAppCheck` false when env ≠ `"true"` | **`false` today** | **fail-open confirmed** |

**Could the mismatch itself cause cross-library credential selection or fail-open?**
- *Cross-library selection:* no. Production has one library (`736742`) and one global credential set; the
  ADR-010 resolution machinery that could mis-select is not deployed. The Mission 19 defect (S-1) was a
  Staging-only artefact of compiling `736742` while overriding the default to `780700`; Production's
  default and compiled id agree.
- *Fail-open:* yes, but for a different reason — the corrupted *value*, not the resolver. Production
  `enforceAppCheck` is `false`.
- *Deployment hazard:* `firebase deploy --only functions` from HEAD would fail or require the missing
  `BUNNY_STREAM_API_KEY` secret, and would switch all 79 functions to ADR-010 behaviour. This is why the
  remediation plan treats secret creation as a **precondition** of any deployment.

---

## 9. Local Validation Results

| # | Command | Result |
| --- | --- | --- |
| 1 | `npm run build` (`tsc`, `functions/`) | **exit 0** |
| 2 | `npm run test:pure` (`functions/`) | **exit 0** — all pure suites passed, including the 40-check resolver suite (`staging explicit 736742 is rejected (allow-list cannot resurrect it)`, `library A and B never resolve each other's credentials or identity`) |
| 3 | ESLint on `bunny_library_registry.ts`, `bunny_library_catalog.ts`, `bunny_library_catalog_reader.ts`, `bunny_library_secret_resolver.ts`, `security_helpers.ts` | **not completed** — `npx eslint` exceeded the command budget twice in this environment (no lint exit code obtained). Report as a limitation, not a pass. |
| 4 | Structural analysis of the corrupted value (lengths/charsets only) | 97 chars, 2 `=`, segments 25 / 64 / 6, no whitespace |
| 5 | In-memory credential scan of all tracked files | 0 hits |
| 6 | In-memory credential scan of 5,115 Git history blobs (`--all`) | 0 hits |
| 7 | Firestore REST read of `bunny_libraries` (Production) | HTTP 200, 0 documents |
| 8 | Cloud Logging query for `APP_CHECK_ENFORCEMENT` (365 d) | 0 entries |
| 9 | Audit Logs query for `GetFunction` (90 d) | 0 entries |

No source file was modified to satisfy any check. `functions/lib` was regenerated by `tsc` (git-ignored
build output). Git state after the mission is byte-identical in structure: branch
`ci/ios-staging-codemagic`, HEAD `34a4b76`, **63 status entries, 0 staged, 0 deleted**.

---

## 10. Security Risks

| # | Risk | Severity | Affected | Notes |
| --- | --- | --- | --- | --- |
| R-1 | Bunny Stream API key stored in plaintext in function environment (79 functions, 2 copies each) | **High** | `projects/606744934510` function metadata | Readable by any function-viewer; long-lived since 2026-10-08 |
| R-2 | App Check enforcement effectively disabled on all 69 callables | **Medium** | Production callables | Auth still required, so this is an attestation gap: unattested clients / scripted abuse are not blocked at the edge |
| R-3 | Configuration silently wrong despite an "enforcement enabled" commit — no validation of boolean env values | **Medium** | `security_helpers.ts`, `.env` workflow | Any future hand-edit can reproduce this class of defect |
| R-4 | `functions/.env` is shipped to the deploy pipeline and can carry secrets (Mission 18 N-1) | **Medium** | deploy tooling, GCS source archive | Now demonstrably the carrier of a real key |
| R-5 | Production lacks the `BUNNY_STREAM_API_KEY` Secret Manager secret required by HEAD | **High (release blocker)** | any approved Production deploy | Deploy fails, or the key must be created first |
| R-6 | Production runs pre-ADR-010 code with a single global Bunny credential | **Low/Medium** | multi-library roadmap | Not a defect today (one library), but a release-ordering hazard |
| R-7 | `roles/editor` on the runtime SA | **Low** | runtime SA | Standard Firebase default; grants no secret payload access |
| R-8 | Same Stream key may still be live at Bunny | **High if live** | library `736742` metadata | Rotation must be assumed necessary |

---

## 11. Ordered Remediation Plan

> **Not executed.** Every step requires the owner's explicit approval (see §14). Steps are grouped by
> whether they can run independently.

### Phase 0 — Preconditions (independent, read-only)

| # | Action | Resource | Permission | Risk | Verification |
| --- | --- | --- | --- | --- | --- |
| 0.1 | Record the current function configuration snapshot (names, updateTime, `firebase-functions-hash`, env **key names**, secret mounts) as the rollback baseline | all 79 functions | `cloudfunctions.functions.list` | none | snapshot file stored outside the repo |
| 0.2 | Record current Bunny library `736742` metadata (library id, pull zone, token-auth state) **read-only** | Bunny dashboard / account API | account read key | none | dashboard screenshot / API 200 |
| 0.3 | Confirm the `.env` fix target content: `APP_CHECK_ENFORCEMENT=<true|false>` on its own line, no `BUNNY_*` lines | repo `functions/.env` | local edit | none | file re-read shows 2 clean `KEY=value` lines |

### Phase A — Containment and rotation (independent of deployment, order-critical inside the phase)

| # | Action | Resource | Permission | Risk | Dependencies | Verification | Rollback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A.1 | **Rotate the Bunny Stream API key** for library `736742` (issue new key, then revoke the old one) | Bunny dashboard → Stream library `736742` → API | Bunny account/library admin | **Medium**: production Stream metadata (poster filenames, HQ preview flags) will fail until the new key is deployed; thumbnails fall back to defaults (metadata path is best-effort, returns `null`) | — | old key returns HTTP 401 on a Stream control read; new key returns HTTP 200 | re-enable old key at Bunny if it was not revoked (do this only if the old key is judged uncompromised) |
| A.2 | Verify the rotated key **without printing it** (status codes only) | Bunny Stream API | — | none | A.1 | `GET video.bunnycdn.com/library/736742/videos?pageSize=1` → 200 with new key, 401 with old key | n/a |
| A.3 | **Create** Secret Manager secret `BUNNY_STREAM_API_KEY` in `projects/606744934510` with the rotated value as version 1 | `projects/606744934510/secrets/BUNNY_STREAM_API_KEY` | `secretmanager.secrets.create`, `secretmanager.versions.add` | Low | A.1 | `gcloud secrets versions list` → `1 enabled`; payload **not** printed | delete the new secret (it has no consumer until deploy) |
| A.4 | Grant `roles/secretmanager.secretAccessor` on **that secret only** to `606744934510-compute@developer.gserviceaccount.com` | same secret | `secretmanager.secrets.setIamPolicy` | Low | A.3 | `get-iam-policy` shows exactly one binding | remove the binding |
| A.5 | Scrub the local `functions/.env`: remove the embedded key, restore a single boolean | repo `functions/.env` (git-ignored) | local edit | none | — | value becomes exactly `true`/`false`; `git status` count unchanged (still ignored) | restore previous file from the owner's own offline copy |
| A.6 | Restrict who can read function metadata (optional hardening): review project IAM for `roles/editor`/viewer members and CI SAs; consider removing `functions.get` from non-operators | project IAM | `resourcemanager.projects.setIamPolicy` | Low/Medium (can break CI) | owner decision | `projects get-iam-policy` review | re-apply recorded policy |

**A.1→A.4 are safe and independent of any deployment.** A.5 is a local file edit that becomes effective
only at deploy. Note: rotation does **not** remove the plaintext copies already in the 79 functions'
metadata; only a deployment does (§ phase C).

### Phase B — App Check correctness (no behaviour change yet)

| # | Action | Resource | Permission | Risk | Dependencies | Verification | Rollback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B.1 | Set `APP_CHECK_ENFORCEMENT` to the **explicit literal `false`** in `functions/.env` (fix the corruption, keep current behaviour) | `functions/.env` | local edit | none | A.5 | value is exactly `false` | revert the line |
| B.2 | Decide the flip to `true` **separately**, only after App Check tokens are proven for Flutter web, Android, iOS and the dashboard, and debug tokens are registered for the release build | App Check console + clients | `firebaseappcheck.admin` (admin SDK SA already has it) | **High if flipped early**: every unattested callable call returns `unauthenticated` | B.1, client verification | staged: one callable enforced → client tests pass → then global | set back to `false` and redeploy |

Rationale: the *current* behaviour is `false`; publishing `false` explicitly is a no-op fix that removes
the ambiguity and the embedded secret, while a flip to `true` is a behaviour change that must be verified
with real clients first (Staging never proved App Check, and its web debug token was unregistered).

### Phase C — Deployment (requires the Production release approval of Blocker B)

| # | Action | Resource | Permission | Risk | Dependencies | Verification | Rollback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C.1 | Seed the Production catalog document `bunny_libraries/736742` (`status: active`, `token_auth_enabled: true`, `token_auth_verified: true`, `pull_zone_id`, valid `playback_host`, `credential_refs` = `BUNNY_736742_STREAM_API_KEY` / `BUNNY_736742_TOKEN_KEY`, `source: legacy_env`) | Firestore | `datastore.entities.create` | Medium (a malformed doc is inert: the reader drops it) | owner approval; values from 0.2 | `parseBunnyCatalogEntry` + activation gate validate locally before write; read-back after write | delete the document |
| C.2 | Create per-library secrets `BUNNY_736742_STREAM_API_KEY` (= the rotated value) and `BUNNY_736742_TOKEN_KEY` (= the current `BUNNY_TOKEN_KEY` value, read out-of-band by the owner, never via this repo) | Secret Manager | create + add-version | Medium (token key is playback-critical) | A.3, owner-supplied token value | `versions list` shows both enabled | delete the two secrets |
| C.3 | Grant per-secret `secretAccessor` for those two secrets to the runtime SA | Secret Manager | `setIamPolicy` | Low | C.2 | `get-iam-policy` per secret | remove bindings |
| C.4 | Set `BUNNY_ACTIVE_LIBRARY_IDS=736742` and `BUNNY_DEFAULT_LIBRARY_ID=736742` (explicit, no drift) in the deploy env | deploy config/`.env` | local edit | Low | C.1 | read-back of deployed env (key names + values for non-secrets) | remove the variables and redeploy |
| C.5 | **Deploy** the approved codebase: `firebase deploy --only functions` (79 functions, `us-central1`) | Cloud Functions | `cloudfunctions.functions.deploy`, `iam.serviceAccounts.actAs`, `run.services.*` | **High**: replaces the running Production backend for all 79 functions | owner approval; A.3/A.4 (secret must exist first), B.1, C.1–C.4 | see C.6 | §12 |

### Phase D — Post-deployment verification

| # | Check | Expected |
| --- | --- | --- |
| D.1 | `gcloud functions list --format=json` → per function env | `APP_CHECK_ENFORCEMENT` is exactly `false` (or `true` if B.2 approved); **no** occurrence of a key-shaped 41-char token anywhere in env values; `BUNNY_STREAM_API_KEY` appears only in `secretEnvironmentVariables` |
| D.2 | Secret mounts | `BUNNY_STREAM_API_KEY` (and per-library secrets) mounted from Secret Manager on the callables that need them |
| D.3 | Unauthenticated callable probe | `401 UNAUTHENTICATED` (fail closed) |
| D.4 | Attested vs unattested call (if B.2 flipped) | unattested → `unauthenticated` with App Check reason; attested → success |
| D.5 | Doctor/student product smoke (`verifyPhonePassword` → `listEligibleBunnyLibraries` → `getLectureResources` → `generateBunnySignedUrl`) | 200s; master playlist 200; unsigned 403 |
| D.6 | Library-scope negatives | `999999` → `unknown_library`; `775315` → `library_not_activated` (must stay inactive); hint mismatch → `library_mismatch` |
| D.7 | Stream metadata path | poster/thumbnail metadata returns non-null for a known video (proves the rotated key is mounted correctly) |
| D.8 | Log check | no secret value in logs; no new `permission-denied` on Secret Manager |
| D.9 | Audit | `secretmanager.versions.access` (if data-access logs enabled) shows only the runtime SA |

### Phase E — Hygiene (independent, no Production runtime impact)

| # | Action | Risk | Notes |
| --- | --- | --- | --- |
| E.1 | Add `.env*` to `firebase.json` → `functions[0].ignore` so secrets never enter the source archive (Mission 18 N-1/N-2) | Low | Prevents recurrence of R-4; affects future deploys only |
| E.2 | Add a boot-time assertion that fails/warns when `APP_CHECK_ENFORCEMENT` is not exactly `true`/`false` | Low | Prevents recurrence of R-3; code change needs its own approval |
| E.3 | Add a reset/verification job that lists any function env value containing `=` or a 65+ char token in a *non-secret* variable | Low | Detection, not prevention |

**Independent vs ordered summary**

| Can run independently, in any order | Must be ordered |
| --- | --- |
| 0.1, 0.2, 0.3, A.5, B.1, E.1–E.3 | A.1 → A.2 → A.3 → A.4 → (C.2 → C.3) → C.1 → C.4 → C.5 → D.* |

Hard constraints: **the secret must exist before any deployment** (A.3 → C.5); **rotation before
deployment** (A.1 → C.5); **catalog before deployment** so the new resolver has an authoritative row
(C.1 → C.5); **never deploy `true` before client App Check tokens are proven** (B.2 → C.5).

---

## 12. Rollback Plan

| Change | Rollback |
| --- | --- |
| Function deployment (C.5) | Gen 2 functions are Cloud Run services with revision history: shift traffic back with `gcloud run services update-traffic <service> --to-revisions=<previous>=100` for the affected functions, or redeploy the previous commit (`3c4d45e`/`ff85ce0` era) with the recorded `firebase-functions-hash`. Keep the pre-deploy snapshot (0.1) as the source of truth for env key names. |
| `APP_CHECK_ENFORCEMENT` | Set to `false` and redeploy, or shift traffic to the previous revision (previous revision also carried `false`). |
| New secret `BUNNY_STREAM_API_KEY` (A.3/A.4) | Unused until deploy: disable version, then delete the secret and its IAM binding. Prefer **disable** over destroy so an in-flight cold start is not broken. |
| Per-library secrets (C.2/C.3) | Disable versions, remove bindings, delete secrets. No consumer until the catalog row + allow-list point at them. |
| Catalog document (C.1) | Delete `bunny_libraries/736742`; the resolver then falls back to the legacy default path if `BUNNY_LEGACY_LIBRARY_FALLBACK` is not `false`. |
| Allow-list / default-id vars (C.4) | Remove the variables and redeploy (empty `BUNNY_ACTIVE_LIBRARY_IDS` disables non-default libraries; never set it to a malformed value — a non-empty value with no valid id **denies everything** by design). |
| Bunny key rotation (A.1) | Only possible if the old key was retained rather than revoked. If revocation already happened, the rollback is the *new* key — this is why A.2 verifies before C.5. |
| Local `.env` (A.5/B.1) | Restore the owner's offline copy. The file is git-ignored, so Git cannot help. |
| IAM changes (A.4/A.6) | Re-apply the recorded policy (0.1/A.4 `get-iam-policy` output). |

Rollback is **not** available for: the plaintext key having been readable before rotation (rotation is the
only remedy), and any secret value that already left the trust boundary.

---

## 13. Explicitly Unverified Items

| ID | Item | Why unverified | Effect on the decision |
| --- | --- | --- | --- |
| D-1 | Staging resource state | One read-only `gcloud projects describe dr-tarek-staging` was issued while establishing identity separation (project id/number/lifecycle only; no Staging data, secret, function or Firestore read). Recorded as a deviation from the "do not access Staging" rule. | None; no Staging change |
| U-1 | Whether the 41-char key is **still valid** at Bunny | Requires an authenticated Bunny call using the credential | None for remediation: rotation is prescribed regardless |
| U-2 | Whether the exact key value appears in Cloud Logging payloads | Requires submitting the payload as a query term / writing it to disk | Contained by rotation; a post-rotation log sweep is part of D.8 |
| U-3 | Whether the deployed GCS source archive contains `functions/.env` (and therefore the key) | Requires downloading the archive, which may expose the payload | Reinforces A.1 rotation + E.1 ignore rule |
| U-4 | Whether any third party read the function metadata | Audit query returned 0 `GetFunction` entries in 90 days; retention/shape limits prevent a proof | Rotation is the mitigation; classification stays `POTENTIALLY EXPOSED` |
| U-5 | Firebase App Check **service-level** enforcement modes (Firestore/Storage/Auth) | `firebaseappcheck.googleapis.com` list returned HTTP 403 (`quota project not set` on ADC); retrying with the Production project as quota project was deliberately not attempted (same class of call that caused the Mission 18 deviation) | Scope of R-2 is limited to **callables**, which is what `APP_CHECK_ENFORCEMENT` controls |
| U-6 | Whether Bunny Stream **write** operations are permitted by this key | Same as U-1 (would require using the credential) | Treat as metadata-read scoped (proven library-scoped on Staging); rotation still mandatory |
| U-7 | ESLint result for the five inspected modules | `npx eslint` exceeded the command budget | Build + 100% pure-suite pass are the validation evidence; lint recorded as not run |
| U-8 | Production Firestore **rules** currently deployed | Reading the deployed ruleset was not part of this mission's read set | Catalog is empty, so the `bunny_libraries` rule is inert today |

No limitation above creates ambiguity about **what must be done**; each is either mitigated by rotation or
verified during Phase D.

---

## 14. Final Decision

### `READY FOR EXPLICIT PRODUCTION REMEDIATION APPROVAL`

Justification against the required criteria:

| Criterion | Status |
| --- | --- |
| Production identity conclusively verified | **Met** — `dr-tarek-platform` / `606744934505`→`606744934510`, `us-central1`, runtime SA `606744934510-compute@…`, library `736742`, 79 functions |
| Security issue and scope sufficiently understood | **Met** — one corrupted env value, 79/79 functions, cause (flattened `.env` lines), effect (`enforceAppCheck: false`), and a plaintext library-scoped Stream key in two places per function |
| Remediation plan technically complete | **Met** — §11 covers containment, rotation, secret creation, IAM, env correction, App Check verification, catalog, deployment, verification, rollback |
| No unresolved critical ambiguity prevents safe remediation | **Met** — U-1…U-8 do not change any step; rotation makes key validity moot and Phase D verifies the rest |

**What the owner must decide (in a separate instruction):**

1. Approve **Phase A** (rotation at Bunny + creation of `BUNNY_STREAM_API_KEY` + per-secret IAM). This is
   the containment step and does not touch the running backend, but it **will degrade Stream metadata
   (poster filenames / HQ-preview flags) until the deploy in Phase C**, because Production currently reads
   the plaintext key.
2. Approve **B.1** (explicit `false`) now; treat **B.2** (flip to `true`) as a separate decision that
   requires proven App Check tokens on all clients.
3. Approve **Phase C** (catalog row, per-library secrets, allow-list, deployment) — this is the
   Blocker-B Production release and the only step that changes runtime behaviour and removes the
   plaintext copies.
4. Decide whether to also run **Phase E** hygiene in the same window.

**No production resource, secret, IAM binding, Firestore document, rule, function, or Git state was
modified by Mission 21.** No secret value appears in this report; the credential is referred to only by
length, charset class and storage location.
