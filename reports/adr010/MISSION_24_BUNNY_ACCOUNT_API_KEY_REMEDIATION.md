# Mission 24 — Bunny Account API Key Exposure Remediation

**Date:** 2026-11-17
**Project:** `dr-tarek-platform` / `606744934510`
**Scope:** Bunny **Account** API key only (not the Stream library key).
**Classification:** `PARTIALLY CLOSED — revocation verified, one non-critical regression check fails` (§7)

No secret value, partial value, fingerprint or screenshot of a credential appears in this report.

---

## 1. Dependency audit (Phase 1, read-only)

### 1.1 Where an Account API key could be used

| Location class | Searched for | Result |
| --- | --- | --- |
| Tracked source (all files, excluding build output) | `api.bunny.net`, `videolibrary`, `BUNNY_ACCOUNT*`, `BUNNY_API_KEY`, `bunnyAccount` | **0 matches** |
| Cloud Functions source (`functions/src/**`) | same | **0 matches**; the only Bunny hosts referenced are `video.bunnycdn.com` (library key) and the storage zone |
| Dashboard (`dashboard/lib/**`) | `bunnycdn`, `api.bunny.net` | **0 files** — the dashboard never talks to Bunny; it calls Cloud Functions |
| Flutter clients (`lib/**`) | same | **0 files** — clients call Cloud Functions only |
| CI/CD (`.github/workflows/**`) | `bunny` | `ci.yml` only, with **fake fixture values** (`fixture-signing-key`, `fixture-api-key`) and no account key |
| Local scripts (`scripts/**`, `tools/**`) | `bunny` | 3 scripts: `diagnose_bunny_403.cjs` (Stream API, library key), `check_bunny_playback_signing.cjs` (URL check), `backfill_first_video.cjs` (Firestore only). None uses the account API |
| Other deployed services | Cloud Run (79 non-function services filtered), Cloud Scheduler (3 Firebase-managed function schedules) | no account-key consumer |

### 1.2 Deployed configuration (names only)

| Evidence | Observed |
| --- | --- |
| Environment variable **names** on all 83 functions | `APP_CHECK_ENFORCEMENT`, `BUNNY_STREAM_LIBRARY_ID`, plus platform vars (`GCLOUD_PROJECT`, `FIREBASE_CONFIG`, `FUNCTION_TARGET`, `FUNCTION_SIGNATURE_TYPE`, `EVENTARC_CLOUD_EVENT_SOURCE`, `LOG_EXECUTION_ID`) — **no account-key variable** |
| Secret Manager secret **names** | `BUNNY_STREAM_API_KEY`, `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STORAGE_PASSWORD` — **no account-key secret** |
| Secret mounts | `BUNNY_STREAM_API_KEY` ×6, `BUNNY_TOKEN_KEY` ×8, playback template ×3, storage base URL ×5, storage zone name ×2, storage password ×2 |

### 1.3 Conclusion

The platform has **no dependency** on the Bunny Account API key. Every platform path uses product-scoped
credentials: the Stream library key (Secret Manager), the pull-zone token key, and the storage-zone
password. The exposed account key is used only by humans in the bunny.net dashboard.

**Replacement:** not required (no consumer). **Impact of revocation:** none for the platform; account-level
API access by scripts or tools using the exposed value stops working.

---

## 2. Revocation (Phase 2)

| Step | Result |
| --- | --- |
| Dashboard session already authenticated (owner logged in); no credential was read from the browser's password manager, cookies or session store | — |
| Page | `https://dash.bunny.net/account/api-key` |
| Control used | the field's **refresh (arrows-rotate) action**, verified in the DOM next to the masked value (the copy/eye actions were **not** used) |
| Confirmation dialog text | “Reset API access key? Resetting the API access key will disable your old key and create a new one.” → confirmed |
| Moment | **2026-11-17 ≈ 12:06 UTC** (Bunny does not expose a revocation timestamp through a readable API; the window is bounded by the session actions and the adjacent secret version created at `12:04:01Z`) |

Bunny replaced the key atomically: the previous value is disabled immediately and a new value is shown in the
dashboard. The new account key was **not** copied into this agent, a file, Git, or any store — nothing in the
platform needs it, and the owner can reveal it in the dashboard whenever account-level API work is required.

---

## 3. Verification (Phase 3, status codes only)

| Credential | Endpoint | HTTP |
| --- | --- | --- |
| **Old (exposed) account key** | `GET api.bunny.net/videolibrary` | **401** — rejected |
| New account key (as displayed by the dashboard) | `GET api.bunny.net/videolibrary` | **200** |
| Library inventory with the new account key | `GET api.bunny.net/videolibrary?page=1&perPage=100` | **200** — 5 libraries: `736742`, `763276`, `775315`, `776525`, `780700` (unchanged) |
| Library `736742` metadata | `GET api.bunny.net/videolibrary/736742` | **200**, pull zone `6414868` |
| Stream API with library `736742`'s current key | `GET video.bunnycdn.com/library/736742/videos?pageSize=1` | **200** |

Both probes were executed inside the authenticated page (values held in page memory), so no credential
entered the agent's context; only status codes were returned.

---

## 4. Regression checks (Phase 4)

| Check | Result |
| --- | --- |
| `BUNNY_TOKEN_KEY` (playback signing) unchanged | **PASS** — versions 1/2/3 still enabled, mounts untouched |
| Library `736742` still resolves through Secret Manager (no plaintext env var) | **PASS** — 6 functions mount `BUNNY_STREAM_API_KEY`; 0 plaintext env vars |
| Staging (`dr-tarek-staging`, library `780700`) untouched | **PASS** — no Staging command was issued |
| Other Bunny libraries modified | **PASS** — inventory still exactly 5 libraries; pull zone `6414868` unchanged for `736742` |
| Cloud Functions redeployed | **PASS** — update times unchanged (`2026-11-17T11:39:22Z` … `11:45:07Z`) |
| App Check / Firestore / unrelated Firebase settings | **PASS** — untouched |
| Git | **PASS** — no commit/reset/stash/clean; HEAD `34a4b76`, working tree unchanged |
| **Stream metadata path** | **FAIL — see §5** |

---

## 5. Incident during this mission (must be reported)

While looking for the account-key revocation control, the documented account-API endpoint
`POST api.bunny.net/videolibrary/736742/resetApiKey` was called with the account key. That endpoint rotates
the **Stream library** key (the path is `/videolibrary/{id}/…`), not the account key: the account key stayed
valid (`200`) and the library key was rotated a second time.

Consequences and handling:

| Item | State |
| --- | --- |
| Library `736742` key after the second rotation | valid — probe **200**; it was stored as **`BUNNY_STREAM_API_KEY` version 2** (`enabled`, `2026-11-17T12:04:01Z`) through a localhost relay that never echoed the value |
| Version 1 (the Mission 23 key) | now **revoked at Bunny**; still `enabled` in Secret Manager (its value is dead) |
| Function mounts | the six callables pin **`versions/1`** |
| Live impact | Stream **metadata** (poster filenames, HQ-preview flags, thumbnails) returns `null` → clients fall back to default artwork. **Playback is unaffected** (signed with `BUNNY_TOKEN_KEY`, untouched). No authorization, data or billing impact |
| Required fix | repoint the six mounts to version 2 — a six-function configuration deploy, which **Mission 24 forbids** and was therefore **not performed** |

Minimal follow-up (separate approval):

```
firebase deploy --only functions:generateBunnySignedUrl,getLectureResources,getSectionDisplayMedia,generateBunnyResourceUrl,validateBunnyVideoAssociation,associateBunnyVideoToLibrary
```

(expected to bind `BUNNY_STREAM_API_KEY:latest` → version 2, restoring metadata within one cold start)

Alternative, equally valid: keep the current deployment and accept default artwork until the next scheduled
deployment.

Mission 23 explicitly accepted this same degradation window between rotation and deployment, so the state is
known and bounded — but it is a regression relative to the state at the start of this mission and is recorded
as such.

---

## 6. Remaining risks

| # | Risk | Severity | Note |
| --- | --- | --- | --- |
| 1 | Six callables pin the dead secret version 1 → metadata-only degradation | Medium | Fix = the deploy above; playback and authorization unaffected |
| 2 | Secret version 1 remains `enabled` with a revoked value | Low | Left enabled deliberately: disabling it would make the six pinned mounts fail at instance start, which is worse than a dead value |
| 3 | No platform dependency on the account key, so no replacement was created | — | The dashboard-generated replacement exists and is visible only in bunny.net |
| 4 | Account-level API automation (if ever added) would need the new key from the dashboard | Low | Store it in Secret Manager at that time, never in `.env` or client code |
| 5 | Pre-existing (Mission 23): missing Firestore index on `retries.status` for `processNotificationQueue` | Medium | Unrelated to this mission; still open |

---

## 7. Classification

# `PARTIALLY CLOSED — SPECIFIC NON-CRITICAL ITEMS REMAIN`

- **Complete:** the exposed **Account API key is revoked** (old `401`, new `200`), no dependency existed, no
  replacement was needed, and every isolation/regression check passes except one.
- **Outstanding:** the Stream **metadata** path needs the six-function credential-version rebind described in
  §5. It is non-critical (cosmetic fallback, playback and security intact) and cannot be completed inside
  Mission 24's prohibition on redeploying Cloud Functions.
