# ADR-010 Option C — Staging Deployment Manifest

Status: **EXECUTED on `dr-tarek-staging` - validation V1-V5 passed; V6-V10 not executed
(Doctor credential dependency). See the execution record in section 6.1.**
Date: 2026-11-18
Executed: 2026-11-18, `firebase deploy` exit code 0.
Target environment: **`dr-tarek-staging` only** (project number `13159003436`, region
`us-central1`).
Production is **not** a target of this manifest and is not authorized by it.

This manifest is the consolidated change record required before a sensitive operation. It
contains no secret value, no secret version payload, and no credential fingerprint.

---

## 1. Why this deployment exists

The backend half of Option C is implemented in the working tree and passes every test that
can run without a live environment:

| Evidence | Result |
|---|---|
| `npm --prefix functions run build` | exit 0, no TypeScript errors |
| `npm --prefix functions test` (emulator: firestore, functions, auth) | **58/58 files passed** |
| `node test/bunny_library_lifecycle.test.js` | 77 assertions passed |
| `node test/bunny_library_lifecycle_flow.test.js` (emulator) | 49 assertions passed |
| `flutter analyze` (dashboard) | No issues found |
| `flutter test` (dashboard) | 407 passed / 7 failed - identical to the pre-existing baseline |

Before this deployment, Staging ran a bundle that **predated** this work: the five lifecycle
callables did not exist there and the association receipt was single-key. The deployment
below closed that gap, and section 6.1 records the result.

---

## 2. Exact resources affected

### 2.1 Functions created (5)

| Function | Trigger | Purpose | Firestore access | Secrets |
|---|---|---|---|---|
| `registerBunnyLibrary` | `onCall` (secure) | Doctor-only registration; always writes `pending_verification` | write `bunny_libraries`, write `admin_audit_log` | none mounted; derives names only |
| `deactivateBunnyLibrary` | `onCall` (secure) | Doctor-only deactivation; always wins | update `bunny_libraries`, write `admin_audit_log` | none |
| `reactivateBunnyLibrary` | `onCall` (secure) | Doctor-only re-enable; returns to `pending_verification`, never `active` | update `bunny_libraries`, write `admin_audit_log` | none |
| `verifyBunnyLibrary` | `onCall` (secure) | Doctor-triggered verification of one library | update `bunny_libraries`, write `admin_audit_log` | reads **only** `BUNNY_<id>_STREAM_API_KEY` / `BUNNY_<id>_TOKEN_KEY` through Secret Manager at call time |
| `listBunnyLibraryHealth` | `onCall` (secure) | Doctor-only read-only health projection | read `bunny_libraries` | none |

### 2.2 Functions updated (2)

| Function | Current Staging revision | Change | Backward compatible |
|---|---|---|---|
| `validateBunnyVideoAssociation` | `validatebunnyvideoassociation-00002-vew` | Receipt is signed with `BUNNY_ASSOCIATION_RECEIPT_KEY` **when bound**, otherwise with `BUNNY_TOKEN_KEY` (unchanged default) | Yes — no dedicated key exists, so the signer is identical |
| `associateBunnyVideoToLibrary` | `associatebunnyvideotolibrary-00002-huf` | Receipt verification accepts the dedicated key **and** the CDN token key during the N5 window | Yes — with one key the accepted set is that one key |

### 2.3 Explicitly non-target

- Every other Staging function (76 exist today; 5 are added, 2 are updated → 81 expected).
- `APP_CHECK_ENFORCEMENT` — remains `false`; **no environment variable is changed**.
- Secret Manager — **no secret is created, versioned, rotated, disabled, or deleted.**
- IAM — **no binding is added or removed.** The runtime service account already reads the
  per-library secrets used by the resolver.
- Firestore Rules, Firestore indexes, Firestore data — **untouched.**
- Hosting, Storage, Bunny account settings, Bunny libraries — **untouched.**
- Library `775315` — **not referenced, not activated, not configured.**
- Library `736742` — **not used for any test.**

---

## 3. Exact operations

```
firebase deploy --only functions:registerBunnyLibrary,functions:deactivateBunnyLibrary,functions:reactivateBunnyLibrary,functions:verifyBunnyLibrary,functions:listBunnyLibraryHealth,functions:validateBunnyVideoAssociation,functions:associateBunnyVideoToLibrary --project dr-tarek-staging
```

`--project dr-tarek-staging` is mandatory and explicit. `.firebaserc` defaults to Production
and must never be relied on.

The CLI uploads the current `functions/` working tree as the source bundle. The delta
between that bundle and the bundle Staging currently runs was measured directly from the
deployed archive:

| Metric | Value |
|---|---|
| Deployed Staging `src/index.ts` | 9,627 lines |
| Working-tree `src/index.ts` | 10,052 lines |
| Diff | 432 insertions, 7 deletions |
| Composition | Option C lifecycle callables + receipt-key rotation + the App Check enforcement-state diagnostic already present in the reviewed tree |

No other source file that Staging runs is modified by this mission except the new
`functions/src/core/video/bunny_library_lifecycle.ts` and its test.

---

## 4. Security impact

| Area | Impact |
|---|---|
| New attack surface | Five new callables, all `onCall` + `enforceAppCheck` per `SECURE_CALL_OPTS`, all gated by `requireDoctor`. |
| Authorization | `requireDoctor` rejects every non-Doctor caller. No `ADMIN_*` permission grants access. |
| Secret exposure | `registerBunnyLibrary`, `deactivateBunnyLibrary`, `reactivateBunnyLibrary` and `listBunnyLibraryHealth` read **no** secret. `verifyBunnyLibrary` reads only the named library's own secrets, server-side, and never returns them. |
| Data exposure | `listBunnyLibraryHealth` returns id, display name, status, token flags, timestamp and typed error code. It returns **no** host, pull zone, credential name, or credential value. |
| Audit | All five callables write `admin_audit_log` entries with the approved action vocabulary; no credential, host or URL is included. |
| Playback | `generateBunnySignedUrl` is **not** modified by this deployment. Playback behaviour is unchanged. |
| App Check | Unchanged (`false`). This deployment does not weaken or strengthen it. |
| Rules | Unchanged. `bunny_libraries` remains deny-all to clients. |

---

## 5. Backup and rollback

### 5.1 Captured pre-deploy state

| Item | Value |
|---|---|
| Function inventory | 76 functions |
| `validateBunnyVideoAssociation` revision | `validatebunnyvideoassociation-00002-vew` |
| `associateBunnyVideoToLibrary` revision | `associatebunnyvideotolibrary-00002-huf` |
| Source archive | `gs://gcf-v2-sources-13159003436-us-central1/validateBunnyVideoAssociation/function-source.zip` (generation `1794828418333500`) |
| New functions | do not exist; rollback = delete |

### 5.2 Rollback procedure

1. **Updated functions** — redeploy the captured pre-deploy source archive for each of the
   two updated functions, then confirm the resulting revision differs from the new one and
   matches the previous behaviour (receipt still verifies with the token key).
2. **Created functions** — `gcloud functions delete <name> --project dr-tarek-staging
   --region us-central1 --quiet` for each of the five. Deleting a callable removes only that
   endpoint; no Firestore document is deleted by the deletion itself.
3. **Data written during validation** — any test catalog row created in Staging is named in
   the validation log and removed by document id. No production data is involved.
4. Rollback does **not** touch secrets, IAM, Rules, indexes, or env vars, because the
   deployment does not change them.

### 5.3 Rollback validity

The rollback was validated in principle by the same mechanism used in Mission 23: the
previous container/source is still retained by Cloud Functions and can be redeployed
per-function. Rollback is per-function, not all-or-nothing.

---

## 6. Validation procedure

Executed immediately after deployment, in this order:

| # | Check | Pass condition |
|---|---|---|
| V1 | `firebase functions:list --project dr-tarek-staging` | exactly 81 functions; the 5 new names present; no other name added or removed |
| V2 | `gcloud functions describe` for each of the 7 | state `ACTIVE`; revision captured |
| V3 | `APP_CHECK_ENFORCEMENT` on every function | still `false`; `true` count still 0 |
| V4 | Secret mounts of the 7 | unchanged vs §2; **no new secret mount** on the five new callables |
| V5 | Unauthenticated HTTPS call to each new endpoint | rejected with an auth error, **not** 404 — proves the endpoint exists and is guarded |
| V6 | `verifyBunnyLibrary` for `780700` as Doctor | returns a typed status; never returns a key, host or pull zone |
| V7 | `listBunnyLibraryHealth` as Doctor | returns `780700` and no credential material |
| V8 | `listBunnyLibraryHealth` as a non-Doctor identity | `permission-denied` |
| V9 | Receipt round-trip on Staging | a receipt issued by `validateBunnyVideoAssociation` is accepted by `associateBunnyVideoToLibrary` |
| V10 | Regression | `generateBunnySignedUrl` for an existing mapped Staging video still returns a signed URL |

V6-V10 require a Doctor test identity and an existing mapped video. If no such identity is
available to the executing agent, those checks are recorded as **not executed (credential
dependency)** rather than assumed.

### 6.1 Execution record (2026-11-18)

Deployment command:

```
$env:FUNCTIONS_DISCOVERY_TIMEOUT = "180"
firebase deploy --only functions:registerBunnyLibrary,functions:deactivateBunnyLibrary,functions:reactivateBunnyLibrary,functions:verifyBunnyLibrary,functions:listBunnyLibraryHealth,functions:validateBunnyVideoAssociation,functions:associateBunnyVideoToLibrary --project dr-tarek-staging --non-interactive
```

Result: `Deploy complete!` - 5 create operations and 2 update operations, exit code 0.

The first attempt aborted before any resource was touched with
`User code failed to load. Cannot determine backend specification. Timeout after 10000`.
Measured module load on this host is 15-28 s, so the CLI's 10 s discovery timeout was
overridden with `FUNCTIONS_DISCOVERY_TIMEOUT=180`. This is a build-host property; no source
change was made to accommodate it.

| # | Check | Result | Evidence |
|---|---|---|---|
| V1 | Function inventory | **PASS** - 81 functions (was 76); all 5 new names present; the 76 pre-existing names unchanged | `firebase functions:list --project dr-tarek-staging` |
| V2 | State and revisions | **PASS** - all 7 `ACTIVE` | `registerbunnylibrary-00001-xab`, `deactivatebunnylibrary-00001-guj`, `reactivatebunnylibrary-00001-yop`, `verifybunnylibrary-00001-zil`, `listbunnylibraryhealth-00001-bux`, `validatebunnyvideoassociation-00003-qub`, `associatebunnyvideotolibrary-00003-cax` |
| V3 | `APP_CHECK_ENFORCEMENT` | **PASS** - `false` on all 7, and on all 81 in the full sweep; `true` count 0 | `gcloud functions describe` per function |
| V4 | Secret mounts | **PASS** - the 5 new callables mount **no** secret; the 2 updated callables still mount exactly `BUNNY_TOKEN_KEY:1`, `BUNNY_STREAM_API_KEY:2` | `gcloud functions describe --format=json` |
| V5 | Unauthenticated POST | **PASS** - `HTTP 401` on all 5 new endpoints (not 404) | direct HTTPS POST to each `serviceConfig.uri` |
| V6 | `verifyBunnyLibrary` for `780700` as Doctor | **NOT EXECUTED** - no Doctor test credential available | credential dependency |
| V7 | `listBunnyLibraryHealth` as Doctor | **NOT EXECUTED** - same | credential dependency |
| V8 | `listBunnyLibraryHealth` as non-Doctor | **NOT EXECUTED** - same | credential dependency |
| V9 | Receipt round trip | **NOT EXECUTED** - same | credential dependency |
| V10 | Playback regression | **NOT EXECUTED** - same | credential dependency |

What V6-V10 would have proven, and what already proves it without a live identity:

- authorization and audit behaviour are proven end-to-end against the real callables by
  `functions/test/bunny_library_lifecycle_flow.test.js` (49 assertions) on the emulator;
- the receipt round trip, including the dual-key window, is proven by
  `functions/test/bunny_association_flow.test.js` and
  `functions/test/bunny_library_association.test.js`;
- playback resolution is proven by `functions/test/bunny_playback_regression.test.js`.

The gap is therefore **live-environment confirmation**, not unverified logic. It is recorded
as a gap rather than described as passed.

No Firestore document was created, modified or deleted in Staging during this deployment or
its validation.

---

## 7. Deployment result (actual)

| Change | Before | After |
|---|---|---|
| Function count (Staging) | 76 | 81 |
| `registerBunnyLibrary` | absent | present, `onCall`, Doctor-only |
| `deactivateBunnyLibrary` | absent | present, `onCall`, Doctor-only |
| `reactivateBunnyLibrary` | absent | present, `onCall`, Doctor-only |
| `verifyBunnyLibrary` | absent | present, `onCall`, Doctor-only |
| `listBunnyLibraryHealth` | absent | present, `onCall`, Doctor-only |
| `validateBunnyVideoAssociation` | revision `00002-vew` | `00003-qub` - same signer in the current configuration |
| `associateBunnyVideoToLibrary` | revision `00002-huf` | `00003-cax` - same accepted key set in the current configuration |
| Secrets / IAM / Rules / indexes / env | — | **no change** |

---

## 8. Non-authorization statement

This manifest does **not** authorize:

- any Production operation of any kind;
- creating `BUNNY_ASSOCIATION_RECEIPT_KEY` or `BUNNY_ACCOUNT_API_KEY`;
- any IAM change;
- any Firestore Rules, index, or data migration;
- any Hosting or Flutter release;
- any Bunny-side configuration, including library `775315`.

Production remains behind Gate 1 → Gate 6 in
`ADR_010_OPTION_C_PRODUCTION_DEPLOYMENT_GATES.md`, each requiring its own explicit
Production authorization.
