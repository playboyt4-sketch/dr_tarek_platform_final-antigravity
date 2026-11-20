# ADR-010 Option C — Production Deployment Manifest

Status: **PREPARED — NOT AUTHORIZED. NOT EXECUTED.**
Date: 2026-11-18
Target environment: **`dr-tarek-platform`** (project number `606744934510`, region
`us-central1`).
This document is the change record required before a Production operation. It authorizes
nothing. Execution requires the explicit Production authorization described in §9.

It contains no secret value, no secret version payload and no credential fingerprint.

---

## 1. Pre-deploy census (verified 2026-11-18)

| Item | Production value |
|---|---|
| Functions | **83** |
| Secrets (names only) | 6 — `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_PASSWORD`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STREAM_API_KEY`, `BUNNY_TOKEN_KEY` |
| `BUNNY_ASSOCIATION_RECEIPT_KEY` | **does not exist** |
| `BUNNY_ACCOUNT_API_KEY` | **does not exist** |
| Composite indexes | **36** (0 need to be added by this deployment) |
| `bunny_libraries` documents | **0** |
| `lecture_resources` documents | 13 (13 `video`, 6 with `bunny_video_id`, **0** with `bunny_library_id`) |
| Video rows visible / deleted | 12 / 1 |
| `APP_CHECK_ENFORCEMENT` (sampled on all four Bunny callables) | `false` |
| `BUNNY_STREAM_LIBRARY_ID` | `736742` (legacy default) |
| `BUNNY_DEFAULT_LIBRARY_ID` | not set |
| `BUNNY_ACTIVE_LIBRARY_IDS` | not set (deny-list not engaged) |

### 1.1 Revisions captured before deployment (rollback anchors)

| Function | Revision | Source object | Generation |
|---|---|---|---|
| `validateBunnyVideoAssociation` | `validatebunnyvideoassociation-00002-juy` | `gs://gcf-v2-sources-606744934510-us-central1/validateBunnyVideoAssociation/function-source.zip` | `1794932292898770` |
| `associateBunnyVideoToLibrary` | `associatebunnyvideotolibrary-00002-zor` | `gs://gcf-v2-sources-606744934510-us-central1/associateBunnyVideoToLibrary/function-source.zip` | `1794932292973335` |
| `generateBunnySignedUrl` | `generatebunnysignedurl-00036-ruw` | — (not modified) | — |
| `getLectureResources` | `getlectureresources-00032-cix` | — (not modified) | — |
| `getSectionDisplayMedia` | `getsectiondisplaymedia-00005-kuv` | — (not modified) | — |
| `generateBunnyResourceUrl` | `generatebunnyresourceurl-00018-lij` | — (not modified) | — |
| `listEligibleBunnyLibraries` | `listeligiblebunnylibraries-00001-vof` | — (not modified) | — |

All seven were captured at `us-central1`, runtime `nodejs24`.

### 1.2 Why Production currently has zero catalog documents

Production never ran the catalog backfill. Playback therefore resolves the library through
the legacy default (`BUNNY_STREAM_LIBRARY_ID=736742`), exactly as before ADR-010. This
deployment does **not** create a catalog document, does **not** backfill
`bunny_library_id`, and therefore does **not** change playback resolution for any of the 13
existing rows.

---

## 2. Exact delta Production will receive

Measured against the deployed Production source archive (not against `HEAD`, which predates
the association callables):

| File | Change |
|---|---|
| `functions/src/index.ts` | +417 / −6 lines (9,641 → 10,052) |
| `functions/src/core/video/bunny_library_lifecycle.ts` | **new file**, 326 lines |
| `functions/package.json` | `test:pure` script only — no dependency change |
| Every other file in `functions/src` | **byte-identical** |

The `index.ts` delta is exactly three things:

1. the five lifecycle callables and their helpers;
2. the N5 receipt-key resolution (`resolveBunnyReceiptSigningKeys`) and the dual-key
   verifier;
3. the App Check enforcement-state boot diagnostic that is already reviewed and already
   present in the Staging deployment.

---

## 3. Exact resources affected

### 3.1 Functions created (5)

| Function | Trigger | Guard | Firestore | Secrets |
|---|---|---|---|---|
| `registerBunnyLibrary` | `onCall` | `requireDoctor` + `SECURE_CALL_OPTS` | create `bunny_libraries`, write `admin_audit_log` | none mounted |
| `deactivateBunnyLibrary` | `onCall` | `requireDoctor` + `SECURE_CALL_OPTS` | update `bunny_libraries`, write `admin_audit_log` | none |
| `reactivateBunnyLibrary` | `onCall` | `requireDoctor` + `SECURE_CALL_OPTS` | update `bunny_libraries`, write `admin_audit_log` | none |
| `verifyBunnyLibrary` | `onCall` | `requireDoctor` + `SECURE_CALL_OPTS` | update `bunny_libraries`, write `admin_audit_log` | reads only `BUNNY_<id>_STREAM_API_KEY` / `BUNNY_<id>_TOKEN_KEY` at call time through Secret Manager |
| `listBunnyLibraryHealth` | `onCall` | `requireDoctor` + `SECURE_CALL_OPTS` | read `bunny_libraries` | none |

Because Production has **no** `BUNNY_<id>_*` secrets, `verifyBunnyLibrary` will always fail
closed there with a typed error code until a library's own secrets exist. That is the
intended behaviour, not a defect: registration is metadata-only and verification is the
gate.

### 3.2 Functions updated (2)

| Function | From | To | Behavioural change |
|---|---|---|---|
| `validateBunnyVideoAssociation` | `00002-juy` | new revision | Receipt signer = `BUNNY_ASSOCIATION_RECEIPT_KEY` **if bound**, else `BUNNY_TOKEN_KEY`. Since the dedicated key does not exist, the signer is **identical**. |
| `associateBunnyVideoToLibrary` | `00002-zor` | new revision | Verifier accepts the dedicated key **and** the CDN token key. With one key bound, the accepted set is that one key. |

### 3.3 Explicitly non-target

- The other **81** Production functions — not deployed, not modified.
- `generateBunnySignedUrl` — **not** in the deploy set. Playback behaviour is untouched.
- `listEligibleBunnyLibraries` — **not** in the deploy set. It already exists in Production.
- Secrets — **none created, versioned, rotated, disabled or deleted.**
- IAM — **no binding added or removed.**
- Firestore Rules — **not deployed.** `bunny_libraries` deny-all is already in the repository
  rules file; whether the live Production ruleset contains it could not be read with the
  current credentials (the Firebase Rules API returned `403`). This deployment does not
  require it, because no catalog document is created and no client reads the collection.
  It **must** be confirmed before any catalog document is ever written in Production.
- Firestore indexes — **none added.** The lifecycle callables issue no composite query.
- Firestore data — **no write of any kind.**
- Hosting, Storage, Bunny account, Bunny libraries — **untouched.**
- Library `775315` — not referenced, not activated, not configured.
- Library `736742` — not used for any test in this mission.

---

## 4. Exact operation

```
$env:FUNCTIONS_DISCOVERY_TIMEOUT = "180"
firebase deploy --only functions:registerBunnyLibrary,functions:deactivateBunnyLibrary,functions:reactivateBunnyLibrary,functions:verifyBunnyLibrary,functions:listBunnyLibraryHealth,functions:validateBunnyVideoAssociation,functions:associateBunnyVideoToLibrary --project dr-tarek-platform --non-interactive
```

Two operator notes, both learned from the Staging execution:

- `--project dr-tarek-platform` is mandatory. `.firebaserc` defaults to Production, so a
  command without `--project` is a Production command and must never be issued casually.
- `FUNCTIONS_DISCOVERY_TIMEOUT=180` is required on this host. The bundle takes 15–28 s to
  load here (Windows filesystem + `firebase-admin` cold require), and the CLI's 10 s default
  aborts discovery with "Cannot determine backend specification". This is a build-host
  property, not a code property; the Staging deploy succeeded on the second attempt with
  exactly this override.

---

## 5. Security impact

| Area | Impact |
|---|---|
| New attack surface | Five `onCall` endpoints, all `SECURE_CALL_OPTS` + `requireDoctor`. |
| Authorization | Non-Doctor callers receive `permission-denied`; unauthenticated callers receive `unauthenticated`. No `ADMIN_*` permission grants access. |
| Secret exposure | Four of the five read no secret. `verifyBunnyLibrary` reads only the named library's own secrets, server-side, and never returns them. No secret is mounted on any of the five. |
| Data exposure | `listBunnyLibraryHealth` returns `libraryId`, `displayName`, `status`, two token flags, `lastVerifiedAt`, `errorCode`. It returns no host, pull zone, credential name or credential value. |
| Audit | All five write `admin_audit_log` with the approved action vocabulary and no credential/host/URL. |
| Playback | Unchanged: `generateBunnySignedUrl` is not in the deploy set, and all 13 rows resolve through the legacy default because `bunny_library_id` is absent. |
| App Check | Unchanged (`false`). No env var is set by this deployment. |
| Receipts | With no `BUNNY_ASSOCIATION_RECEIPT_KEY`, receipts are signed and verified with `BUNNY_TOKEN_KEY` exactly as today. |

---

## 6. Backup and rollback

### 6.1 What is backed up

| Item | How |
|---|---|
| Current source of both updated functions | Source archives in `gs://gcf-v2-sources-606744934510-us-central1/<Function>/function-source.zip`, generations captured in §1.1 |
| Current revisions | `validatebunnyvideoassociation-00002-juy`, `associatebunnyvideotolibrary-00002-zor` |
| Data | Nothing is written, so no data backup is required for the deployment itself |

### 6.2 Rollback procedure

1. **Updated functions** — redeploy each function from its captured source archive (or from
   the retained previous container). Confirm the resulting revision differs from the new one
   and that a receipt signed by `validateBunnyVideoAssociation` is still accepted by
   `associateBunnyVideoToLibrary`.
2. **Created functions** — `gcloud functions delete <name> --project dr-tarek-platform
   --region us-central1 --quiet`, one per function. Deleting a callable removes the endpoint
   only; it deletes no Firestore document.
3. **Rollback is per-function**, not all-or-nothing. The two updated functions and the five
   created functions roll back independently.
4. Rollback touches no secret, IAM binding, rule, index or environment variable, because the
   deployment changes none of them.

### 6.3 Rollback risk

Low. No data is written, no schema changes, no credential changes, and the only
behaviourally sensitive functions are updated in a way that is a no-op under the current
Production configuration (one signing key, one accepted key).

---

## 7. Validation procedure (Production)

Executed immediately after deployment, in this order:

| # | Check | Pass condition |
|---|---|---|
| P1 | `firebase functions:list --project dr-tarek-platform` | exactly **88** functions; the 5 new names present; the other 83 unchanged |
| P2 | `gcloud functions describe` for the 7 | state `ACTIVE`; revisions captured |
| P3 | `APP_CHECK_ENFORCEMENT` on the 7 and on a sample of 10 untouched functions | `false` everywhere; zero `true` |
| P4 | Secret mounts of the 7 | unchanged vs §1; no new mount on the five |
| P5 | Unauthenticated HTTPS POST to each new endpoint | `HTTP 401`, **not** `404` |
| P6 | `generateBunnySignedUrl` for one existing mapped video | still returns a signed URL (playback regression) |
| P7 | `validateBunnyVideoAssociation` → `associateBunnyVideoToLibrary` round trip | receipt accepted; association written only for the exact resource |
| P8 | `listBunnyLibraryHealth` as a non-Doctor identity | `permission-denied` |
| P9 | Firestore data | still 13 `lecture_resources`, still 0 `bunny_library_id`, still 0 `bunny_libraries` — **no data side effect** |
| P10 | Cloud Logging for the 7 over 15 minutes | no unhandled rejection, no secret value in any log line |

P6 and P7 require a Doctor test identity and a mapped video. If the executing agent is not
given one, those two are recorded as **not executed (credential dependency)** — never
assumed.

---

## 8. Expected end state

| Change | Before | After |
|---|---|---|
| Production functions | 83 | 88 |
| `registerBunnyLibrary` … `listBunnyLibraryHealth` | absent | present, Doctor-only |
| `validateBunnyVideoAssociation` | `00002-juy` | new revision, identical signer |
| `associateBunnyVideoToLibrary` | `00002-zor` | new revision, identical accepted key set |
| Secrets / IAM / Rules / indexes / data / Hosting | — | **no change** |
| Playback for the 13 existing rows | default library | default library (**no change**) |

---

## 9. Authorization required before execution

Execution requires **all** of the following, recorded in writing by the Platform Owner:

| Gate | Requirement | Current state |
|---|---|---|
| G1 | Explicit Production authorization naming the 7 functions and the target project | **Not granted** |
| G2 | Acknowledgement that Production will then have 5 Doctor-only callables that can write `bunny_libraries` and `admin_audit_log` | **Not acknowledged** |
| G3 | Acknowledgement that no catalog document, no `bunny_library_id` backfill and no secret is created by this deployment | **Not acknowledged** |
| G4 | Confirmation that the live Production Firestore ruleset denies client access to `bunny_libraries` (required before any future catalog write, not before this deployment) | **Unverified — Rules API returned 403** |
| G5 | A rollback window and the person authorized to trigger §6.2 | **Not assigned** |
| G6 | A decision on whether P6/P7 will be run with a Doctor test identity, or recorded as not executed | **Not decided** |

Until G1–G6 are satisfied, the Production deployment is **not executed** and no Production
write of any kind is performed.

---

## 10. Non-authorization statement

This manifest does **not** authorize:

- the deployment described in §4;
- creating `BUNNY_ASSOCIATION_RECEIPT_KEY` or `BUNNY_ACCOUNT_API_KEY`;
- creating a `bunny_libraries` document in Production;
- backfilling `bunny_library_id` on any of the 13 rows;
- resolving D-09 (the 7 rows without a video id);
- any IAM, Rules, index, Hosting, Storage or Bunny-side change;
- any Flutter release.
