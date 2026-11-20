# ADR-010 — Mission 9R: Production Read-Only Bunny Verification (Library 736742)

Date: 2026-11-13
Authorization: Platform Owner explicitly authorized **read-only** use of production library `736742`
(library + pull zone metadata reads, token-auth state inspection, and playback verification only).
Mode: verification only. No `PUT`/`POST`/`PATCH`/`DELETE`, no setting change, no key reset, no video
change, no Firebase/Firestore/Functions/Rules/secret change, no deployment, no commit/push/stage.
No secret value, token, or signed URL is included in this report.

**Verdict: BLOCKED.**
The available Bunny credential is a **library-scoped Stream API key**, confirmed valid for the Stream API
(HTTP 200 on a control read) but **rejected by the account API** (HTTP 401). The account-level API key
required to read `GET /videolibrary/736742` and `GET /pullzone/{pullZoneId}` is not provisioned in this
environment, so `ZoneSecurityKey` could not be read and the B.3 hypothesis remains untested.

---

## 1. Result summary (required fields)

| Field | Result |
|---|---|
| Library ID | **736742** |
| Pull Zone ID | **NOT OBTAINED** (account API unauthorized) |
| API access result | `GET https://api.bunny.net/videolibrary/736742` → **HTTP 401** (`authentication.failed`); control `GET https://video.bunnycdn.com/library/736742/videos` → **HTTP 200** |
| Token Authentication state | **NOT INSPECTED via API** (no pull zone/library read). Prior mission evidence says it is enforced, but that is not evidence produced by this mission. |
| `ZoneSecurityKey` returned in clear text? | **NOT TESTED** |
| Signed HLS status (correct key) | **NOT EXECUTED** |
| Unsigned HLS status | **NOT EXECUTED** |
| Wrong-key signed status | **NOT EXECUTED** |
| Visual key comparison | **NOT PERFORMED** (no key retrieved; owner not interactively available) |
| Final verdict | **BLOCKED** |

---

## 2. Step 1 — Credential discovery and authorization probe

### 2.1 Inventory (names only; no values read into this report)

| Source | Finding |
|---|---|
| Process environment | No `BUNNY*` / `BUNNYNET*` variables |
| `functions/.env` | `BUNNY_STREAM_API_KEY`, `BUNNY_STREAM_LIBRARY_ID` (= `736742`), `APP_CHECK_ENFORCEMENT` |
| `functions/.env.dr-tarek-staging` | Default-library keys only (`BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE`, storage keys, Stream key/library id) |
| Secret Manager (`dr-tarek-platform`) | `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_PASSWORD`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_TOKEN_KEY` — **no account-level API key** |
| Bunny CLI | Not installed / not configured |

The only API-capable credential is `BUNNY_STREAM_API_KEY`. Per Bunny's official authentication guide,
that is a **per-library Stream** credential, not an account credential. The mission required this to be
tested rather than assumed.

### 2.2 Authorization probe (read-only GETs, status codes only)

| Request | Credential | Result |
|---|---|---|
| `GET https://api.bunny.net/videolibrary/736742` | library Stream key | **HTTP 401**, `ErrorKey=authentication.failed` |
| `GET https://video.bunnycdn.com/library/736742/videos?page=1&pageSize=1` (control) | same key | **HTTP 200** |

Interpretation:

- The key is **valid and authorized for the Stream API**, so the credential itself is not broken.
- The key is **not authorized for the account API**. Bunny's account endpoints require the account API key
  (dashboard → Account → API), or a sub-user/scoped key carrying `User` / `UserApi` /
  `SubuserAPIStream` / `ScopedApiKey` scope.
- Sending the library key to the account endpoint produced no state change; the request was a single
  read-only GET and was rejected before any resource access.

### 2.3 Exact missing credential type

**An account-level bunny.net API key** (not the Stream library key), with at least read access to
**Stream Video Libraries** and **Pull Zones**. It must be supplied at runtime (environment variable or
Secret Manager) and must never be committed to the repository.

---

## 3. Step 2 — Read-only library inspection

**NOT EXECUTED.** The account API rejected the only available credential, so the library's `PullZoneId`
could not be read and the pull zone could not be inspected.

Consequently the following remain unknown for this mission:

- `PullZoneId` for `736742`.
- Whether `GET /pullzone/{id}` returns `ZoneSecurityKey` in clear text or masked.
- Whether `PullZoneModel.VideoLibraryId == 736742` (identity check).
- The API-reported token-authentication state (`ZoneSecurityEnabled`).

No alternative endpoint was attempted, because every documented route to these fields is an account-level
API call and the mission forbids substituting write or unrelated operations.

---

## 4. Step 3 — Signing verification

**NOT EXECUTED.** Step 3 is gated on (a) token authentication already enabled, (b) a clear
`ZoneSecurityKey`, and (c) verified pull-zone identity. Conditions (b) and (c) could not be established.
No signature was generated, no URL was built, and no CDN request was made in this mission.

Note: re-running a signed-URL test with the platform's existing token key would only re-prove that the key
signs `736742` playback (already established in Missions 5/7). It would **not** answer the B.3 question,
which is about the value the **API field** `ZoneSecurityKey` returns. That distinction is why the test was
not run.

---

## 5. Step 4 — Key identity

**NOT PERFORMED.** No API key value was retrieved, so there is nothing to compare with the library's
displayed Token Authentication key. No MATCH/NO MATCH result exists.

---

## 6. Why this is BLOCKED and not FAIL

- **Not FAIL:** the hypothesis was not disproved. The account API was never reached with an authorized
  credential, so no evidence about `ZoneSecurityKey` exists either way.
- **Not PASS:** no identity, signing, negative-control, or visual-comparison check was performed.
- **BLOCKED:** a required credential type (account-level API key) is unavailable, and the mission
  correctly forbids substituting a production write, a library-scoped key workaround, or an unverified
  inference.

---

## 7. Exact unblock procedure (read-only, no secrets printed)

1. Owner creates or supplies an **account-level** Bunny API key with Stream + Pull Zone read access
   (preferably a sub-user key limited to Stream), delivered as a runtime env var or Secret Manager entry.
2. Run, in order:
   - `GET https://api.bunny.net/videolibrary/736742` → expect 200; record `PullZoneId` (non-secret).
   - `GET https://api.bunny.net/pullzone/{pullZoneId}` → assert `VideoLibraryId == 736742`.
   - Record whether `ZoneSecurityKey` is present and unmasked; record `ZoneSecurityEnabled` (read-only).
3. If `ZoneSecurityKey` is absent/masked or token auth is not enforced → **STOP** (FAIL/BLOCKED).
4. Select a `Finished` video with the existing Stream key; build the HLS playlist path on the system
   hostname; sign it **in memory** with the API-returned `ZoneSecurityKey` using the unmodified
   `hashVideoDirectoryToken`.
5. Request the signed URL (expect 200), the unsigned URL (expect 401/403), and a wrong-key signed URL
   (expect 401/403). Record status codes only.
6. Compare the returned key with the library's displayed Token Authentication key (owner-side visual check)
   and/or perform an exact in-memory equality check against the platform's configured signing key.
   Record only MATCH / NO MATCH.
7. PASS requires: clear key + matching `VideoLibraryId` + signed 200 + unsigned 401/403 + wrong-key 401/403
   + key identity confirmation. A 200 alone is not PASS.

No step above changes any Bunny setting.

---

## 8. Evidence and limitations

### 8.1 Evidence

- Credential inventory (names only) from env files and Secret Manager.
- One read-only account GET → `401 authentication.failed`.
- One read-only Stream control GET → `200` (proves the key is valid, isolating the failure to credential
  **type**, not key validity).
- No bodies, keys, video ids, or URLs were printed or stored.

### 8.2 Limitations

1. The B.3 hypothesis remains **UNVERIFIED**.
2. The account API key may exist in the production Cloud Functions runtime but is not accessible to this
   local environment; it was not retrieved, guessed, or reconstructed.
3. The `ZoneSecurityKey` masking behaviour remains unknown.
4. `775315` was not touched; its Token Authentication gap is unchanged.
5. Mission 8's Option A/C decision still depends on this test: PASS would let Option C collapse to full
   zero-configuration; FAIL would make the one-time token-key fallback mandatory.

### 8.3 Attestation

- No Bunny resource was modified.
- No production Firebase/Firestore/Functions/Rules/secret was read or changed.
- No working-tree file was modified; no commit, push, or staging occurred.
- No credential, token, or signed URL appears in this report.

---

## 9. Final verdict

**BLOCKED.**

Library `736742` is authorized for read-only inspection, but the only available credential is a
library-scoped Stream key. It is valid for Stream (control 200) and unauthorized for the account API
(401 `authentication.failed`). The account-level API key needed to read `ZoneSecurityKey` is not
provisioned, so the B.3 question could not be answered safely.

Re-run Mission 9R with an account-level key per §7. No implementation or deployment is proposed.
