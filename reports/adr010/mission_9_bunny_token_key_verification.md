# ADR-010 — Mission 9: Bunny Token Signing Key Runtime Verification (B.3)

Date: 2026-11-13
Mode: **verification only.** No Bunny setting, Firebase, Firestore, Rules, Cloud Functions, secret, or
production data was read, written, or changed. No library was activated, no key was reset, no token
authentication was enabled or disabled, and no signed URL or credential was printed or stored.

**Verdict: BLOCKED.**
Step 1 of the mission cannot be satisfied: there is **no dedicated non-production Bunny Stream library
that is both available to this agent and explicitly authorized** for the test, and there is **no
account-level Bunny API credential** available to perform the read-only `GET /videolibrary` /
`GET /pullzone` verification. The only two real libraries known to the project are explicitly excluded by
the mission rules.

---

## 1. Scope and success criteria

This mission was to prove or disprove exactly one hypothesis from Mission 8 §B.3:

> The Pull Zone field `ZoneSecurityKey` is the same secret that Bunny Stream uses as its Token
> Authentication signing key — i.e. the key the platform's existing `hashVideoDirectoryToken`
> implementation must use for a library's HLS playback.

A **PASS** requires all of the following, not merely an HTTP 200:

1. `GET /videolibrary/{testLibraryId}` succeeds and `PullZoneId` is identified.
2. `GET /pullzone/{pullZoneId}` returns `ZoneSecurityKey` **in clear text** (not masked/omitted).
3. `PullZoneModel.VideoLibraryId` equals the test library id.
4. Token Authentication is **already enabled** on that library (the mission forbids enabling it).
5. A URL signed with the returned `ZoneSecurityKey` using the **unmodified**
   `hashVideoDirectoryToken` algorithm returns HTTP 200.
6. The equivalent unsigned URL returns HTTP 401/403.
7. A control signature made with a wrong key returns HTTP 401/403 (differential proof that the zone
   validates with exactly the returned key).
8. The returned key is confirmed to be the library's displayed **Token Authentication key** (authorized
   visual comparison) — without this, the result proves only "zone key", not "Stream library token key".

---

## 2. Step 1 — Find a safe test library

### 2.1 What was checked (read-only, no secrets printed)

| Check | Result |
|---|---|
| Process environment for `BUNNY*` / `STREAM*` variables | **None present** |
| Repository env files | `functions/.env`, `functions/.env.dr-tarek-staging` only |
| Credential **names** present in those files | Default-library only: `BUNNY_STREAM_API_KEY`, `BUNNY_STREAM_LIBRARY_ID`, `BUNNY_TOKEN_KEY`, `BUNNY_PLAYBACK_URL_TEMPLATE`, plus storage/app-check keys |
| Account-level API key (any name) in env or files | **Not present** |
| Secret Manager secret **names** in `dr-tarek-platform` | `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_PASSWORD`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_TOKEN_KEY` — **no account API key** |
| Bunny CLI installed / configured | **No** (`bunny` not found; no `~/.bunny`, `%APPDATA%\bunny`, or `~/.config/bunny`) |
| Real library ids referenced anywhere in the repo/reports | `736742` (production default) and `775315` (inactive) only |
| Other 6-digit ids found near "library" | `123456`, `424242`, `999999` — unit-test fixtures, not real libraries |
| Explicit authorization for any non-production test library | **None provided** |

### 2.2 Result

- `736742` — **excluded by the mission** (production default library).
- `775315` — **excluded by the mission** (inactive, incompletely configured, and not authorized).
- No third library id is known, configured, or authorized.
- Even if a third library existed in the Bunny account, it could not be discovered or inspected without
  an account-level API key, which is not provisioned.

**Step 1 outcome: FAIL (prerequisite missing). Mission must stop here.**

---

## 3. Step 2 — Read-only API verification

**NOT EXECUTED.**

Reason: the only credentials available are scoped to the production default library (`736742`), which the
mission forbids using for this test. The account-level credential required for `GET /videolibrary` and
`GET /pullzone` does not exist in the environment, the repository, or Secret Manager. No read-only Bunny
API call was made.

The following required fields therefore have no values:

| Required field | Result |
|---|---|
| Test library id | **NONE — no test library available/authorized** |
| Pull Zone id | **NOT OBTAINED** |
| Token-authentication state | **NOT INSPECTED** (no library was queried) |
| `ZoneSecurityKey` returned in clear? | **NOT TESTED** |
| Pull Zone `VideoLibraryId` matches library? | **NOT TESTED** |

For context only (not used as evidence for this mission): prior read-only inventory work recorded that
`736742`'s zone enforces token authentication and `775315`'s zone does not. Neither library was contacted
in this mission, and neither may be used to answer the B.3 question under these rules.

---

## 4. Step 3 — Signing verification

**NOT EXECUTED.**

Depends on Step 2. No signature was generated, no URL was constructed, no HTTP request was made, and no
key material was loaded. Consequently:

| Check | Result |
|---|---|
| Signed test HLS URL status | **NOT EXECUTED** |
| Unsigned equivalent status | **NOT EXECUTED** |
| Wrong-key control status | **NOT EXECUTED** |
| Returned `ZoneSecurityKey` validates the signature | **NOT TESTED** |
| Key matches the library's displayed Token Authentication key | **NOT TESTED** |

---

## 5. Step 4 — Outcome classification

**BLOCKED.**

Blocking reasons, in order:

1. **No authorized non-production test library exists** (Step 1 hard stop).
2. **No account-level Bunny API credential is available**, so the Pull Zone cannot be read even if a test
   library were named.
3. No permission to enable Token Authentication was granted, and the mission forbids enabling it — so a
   test library with token auth disabled would remain untestable until the Owner enables it manually.

---

## 6. Exact prerequisites to unblock (Owner actions)

To run this verification safely, all of the following are required:

| # | Prerequisite | Who |
|---|---|---|
| 1 | A dedicated **non-production** Stream library (not `736742`, not `775315`) created solely for verification | Owner |
| 2 | **Token Authentication already enabled** on that library (owner enables it in the Bunny dashboard; the mission must not) | Owner |
| 3 | At least one playable video in that library, fully processed | Owner |
| 4 | Explicit written authorization naming that library id for this test | Owner |
| 5 | An **account-level API key** (read-only use for `GET /videolibrary` + `GET /pullzone`), provided as a runtime environment variable or Secret Manager entry — **not** committed to the repo | Owner |
| 6 | Authorization to visually compare the library's displayed Token Authentication key with the API value (owner-side screenshot/read-back) | Owner |
| 7 | A short execution window with no concurrent library changes | Owner |

Note: the existing `BUNNY_STREAM_API_KEY` is a **library-scoped Stream key**, not an account key, and cannot
perform the account-level reads. It must not be repurposed for this test.

---

## 7. Ready-to-run verification procedure (for when prerequisites exist)

This procedure is safe, read-only, and prints no secrets. It should be executed with the unmodified
`hashVideoDirectoryToken` implementation.

1. **Identity**
   - `GET https://api.bunny.net/videolibrary/{testId}` with the account key.
   - Assert HTTP 200; record `PullZoneId`, `Name`, `DateCreated` (non-secret).
2. **Pull Zone**
   - `GET https://api.bunny.net/pullzone/{pullZoneId}`.
   - Assert `VideoLibraryId == testId`.
   - Record whether `ZoneSecurityKey` is non-empty and not a mask pattern (e.g. `****`, `redacted`).
   - Record `ZoneSecurityEnabled` (read-only; do **not** change it).
   - Resolve the system hostname from `Hostnames[]` where `IsSystemHostname == true`.
3. **Preconditions**
   - If `ZoneSecurityEnabled` is false / Token Authentication is not enforced → **STOP and report BLOCKED**.
     Do not enable it.
4. **Choose a video**
   - `GET https://video.bunnycdn.com/library/{testId}/videos?page=1&pageSize=1` with the **library** key
     (owner-supplied for the test library) → pick a video whose `status` is `Finished` (4).
   - Confirm `videoLibraryId == testId`.
5. **Signed probe**
   - Build the HLS playlist path for that video on the system hostname.
   - Sign it **in memory** with the API-returned `ZoneSecurityKey` using `hashVideoDirectoryToken`
     (`token_path` = video directory, short expiry).
   - `GET` the signed URL; record only the status code. Expected **200** with
     `application/vnd.apple.mpegurl`.
6. **Negative controls**
   - `GET` the same URL unsigned → expect **401/403**.
   - `GET` the same URL signed with a freshly generated random key of the same shape → expect **401/403**.
7. **Key correspondence**
   - Compare the API-returned value with the library's displayed **Token Authentication key** (owner-side
     visual check). Record only "match / no match", never the value.
8. **Classification**
   - PASS only if steps 5, 6 (both), and 7 all pass and step 2 returned a clear key.
   - FAIL if the key is masked/absent, the identity check fails, the signed probe is not 200, either
     negative control is not 401/403, or the visual comparison does not match.
   - BLOCKED for any precondition failure (no test library, token auth disabled, credentials missing).

**Anti-conclusion guard:** a 200 response on a signed URL proves only that *some* key validated the
request. Because HMAC-SHA256 is collision-resistant, the wrong-key control plus the visual comparison are
what prove the *identity* of the key. A 200 alone must never be recorded as PASS.

---

## 8. Evidence and limitations

### 8.1 Evidence collected

- Environment variable **names** (values never read into this report): no `BUNNY*` process variables.
- `functions/.env` and `functions/.env.dr-tarek-staging` **key names** only: default-library credentials.
- Secret Manager **secret names** in `dr-tarek-platform`: five entries, none account-level.
- Repository/report search: only `736742` and `775315` are real library ids; `123456`, `424242`, `999999`
  are test fixtures.
- Tooling: no Bunny CLI and no Bunny CLI configuration.

### 8.2 Limitations

1. No Bunny API request of any kind was made in this mission.
2. No credential value was read, compared, or transmitted.
3. The B.3 hypothesis remains **UNVERIFIED** — neither confirmed nor refuted.
4. Mission 8's recommendation therefore still depends on this test: if `ZoneSecurityKey` is returned and
   matches the library key, Option C collapses to Option A (zero manual secret steps); if not, the
   one-time token-key fallback is required.
5. The `775315` readiness gap (Token Authentication not enforced) is unchanged and remains a separate
   security prerequisite.

### 8.3 Non-claims

- It is **not** claimed that `ZoneSecurityKey` is or is not the Stream token key.
- It is **not** claimed that the API masks or reveals the key.
- No production library was used, directly or indirectly, to infer the answer.

---

## 9. Final verdict

**BLOCKED.**

No authorized non-production test library exists and no account-level Bunny credential is available, so
neither the read-only API step nor the signing step could be executed safely. The mission's own safety
rules correctly prevented substituting `736742` or `775315`.

Re-run this mission once the prerequisites in §6 are supplied. The procedure in §7 is ready to execute
without further design work.
