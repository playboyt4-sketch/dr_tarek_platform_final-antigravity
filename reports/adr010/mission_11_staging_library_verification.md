# Mission 11 — Read-Only Staging Bunny Library Verification (`780700`)

**Date:** 2026-11-13
**Mode:** verification only. No code, config, secret, Bunny setting, Firestore, Rules or deployment change. Nothing staged, committed, reverted or discarded.
**Baseline:** `HEAD = 34a4b763e77087e0eeffd4aa8ad88bb820b61d46`.

---

## 0. Headline finding

**Staging library `780700` exists and is owned by the same Bunny account, and its Pull Zone is real — but the staging *environment* has no usable Bunny credentials at all and no video content.**

- `functions/.env.dr-tarek-staging` contains the Bunny variable **names** with **empty values** (`BUNNY_STREAM_API_KEY=`, `BUNNY_TOKEN_KEY=`, `BUNNY_PLAYBACK_URL_TEMPLATE=`, storage trio) — only `BUNNY_STREAM_LIBRARY_ID=780700` and `APP_CHECK_ENFORCEMENT=false` carry values.
- The staging Secret Manager secrets with those names exist but have **zero versions** (production's equivalents have 3 and 2).
- `ZoneSecurityEnabled = false` on the staging Pull Zone → **token authentication is disabled** there.
- The library has **0 videos** ("Let's upload your first video" in the dashboard).
- Therefore staging is **UNCONFIGURED for playback**, not "partially broken". Playback verification cannot be performed and was not performed.

**Correction to Mission 10 / Mission 9S:** the staging token-key fingerprint recorded earlier (`e1a3ddca`) is a **parsing artifact**, not a real key. The value in `functions/.env.dr-tarek-staging` is empty; a regex that allowed whitespace to span newlines captured a fragment of a following line. Mission 10 §4 row 5 and Mission 9S §8/§12 must be read with this correction. No real staging token key exists to fingerprint.

---

## 1. Repository integrity snapshot

| Check | Result |
|---|---|
| `git rev-parse HEAD` | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` |
| `git diff --cached --stat` | **empty** (nothing staged) |
| `git diff --stat` | 30 files changed, 1,246 insertions(+), 136 deletions(−) |
| `git status --short` | 55 entries (30 modified + collapsed untracked dirs) |
| `git status --porcelain -uall` | 96 entries before this report (97 after) |

Identical to the Mission 10 snapshot. All pre-existing modifications preserved; the only file added by this mission is this report.

---

## 2. Library identity and Pull Zone evidence

All obtained read-only with the account-level key already present in the authenticated dashboard session (no new credential was created, revealed into chat, copied to disk or logged). Only non-secret fields are reproduced.

| Request | Result |
|---|---|
| `GET https://api.bunny.net/videolibrary/780700` | **200** |
| `GET https://api.bunny.net/pullzone/6807898` | **200** |

| Field | Value |
|---|---|
| `videolibrary.Id` | `780700` |
| `videolibrary.Name` | `DrTarek-Staging-Test` |
| `videolibrary.DateCreated` | `2026-10-15T15:40:59` |
| `videolibrary.PullZoneId` | `6807898` |
| `videolibrary.StorageZoneId` | `1993982` |
| `pullzone.Id` | `6807898` |
| `pullzone.Name` | `vz-b5f9cb68-f06` |
| `pullzone.VideoLibraryId` | **`780700`** ✔ identity back-reference matches |
| `pullzone.Hostnames` | `vz-b5f9cb68-f06.b-cdn.net` (`IsSystemHostname = true`) |
| Ownership | 200 on the account's own API ⇒ the library belongs to this account (a foreign-account library returns 403) |

---

## 3. Token authentication status

| Signal | Value | Meaning |
|---|---|---|
| `pullzone.ZoneSecurityEnabled` | **`false`** | **CDN token authentication is OFF** on the staging zone |
| `videolibrary.PlayerTokenAuthenticationEnabled` | `false` | Embed-view token auth also OFF |
| `videolibrary.AllowDirectPlay` | `true` | Direct play permitted |
| `pullzone.BlockNoneReferrer` | `true` | Requests with an empty Referer are rejected |
| `pullzone.AllowedReferrers` | `[]` | **No origin allow-list** — any non-empty Referer is accepted |
| `pullzone.BlockedReferrers` | `[]` | No blocked origins |
| `pullzone.ZoneSecurityKey` | present, **36 characters, unmasked** (fingerprint `cbf22628`) | A key exists even though enforcement is off |

Behavioural confirmation (no video exists, so a random GUID control was used on `vz-b5f9cb68-f06.b-cdn.net`):

| Probe | Result | Reading |
|---|---|---|
| `/{guid}/playlist.m3u8` with `Referer: https://dr-tarek-platform.web.app/` | **404** | Passed the referer gate; object does not exist |
| Same URL, **no** Referer | **403** | Referer gate enforced |
| Signed URL (in-memory, non-matching key) + app Referer | **404** | Signature is not evaluated while enforcement is off |
| Wrong-key signed URL + app Referer | **404** | Same |

Interpretation: the staging zone applies a **Referer-only** filter and **no token authentication**. Any signed or unsigned request with a non-empty Referer reaches the origin.

---

## 4. Credential verification results

| Item | Expected | Actual | Verdict |
|---|---|---|---|
| `BUNNY_STREAM_API_KEY` in `functions/.env.dr-tarek-staging` | a 41-char library key | **empty string** | **MISSING** |
| Stream API call `GET video.bunnycdn.com/library/780700/videos` | 200 | **401** (no key was sent) | **NOT AUTHENTICATED** |
| Staging Secret Manager `BUNNY_STREAM_API_KEY` | — | **secret does not exist** in `dr-tarek-staging` (only the 5 Bunny secrets listed below) | **MISSING** |
| `BUNNY_TOKEN_KEY` in `functions/.env.dr-tarek-staging` | 36-char zone key | **empty string** | **MISSING** |
| Staging Secret Manager `BUNNY_TOKEN_KEY` | 1+ enabled version | secret exists, **0 versions** | **MISSING VALUE** |
| Staging Secret Manager `BUNNY_PLAYBACK_URL_TEMPLATE` | 1+ enabled version | secret exists, **0 versions** | **MISSING VALUE** |
| `BUNNY_PLAYBACK_URL_TEMPLATE` in `functions/.env.dr-tarek-staging` | `https://vz-b5f9cb68-f06.b-cdn.net/{video_id}/playlist.m3u8` | **empty string** | **MISSING** |
| `BUNNY_STORAGE_*` trio | values | **empty strings** | **MISSING** (not required for playback) |
| `BUNNY_STREAM_LIBRARY_ID` | `780700` | `780700` | present (correct intent) |
| `APP_CHECK_ENFORCEMENT` | `false` for staging | `false` | present |

Secret fingerprints (truncated SHA-256, first 8 hex — never a value):

| Key source | Fingerprint |
|---|---|
| API `ZoneSecurityKey` of zone `6807898` (library `780700`) | `cbf22628` |
| API `ZoneSecurityKey` of zone `6414868` (library `736742`, production) | `af89b2a5` |
| Production Secret Manager `BUNNY_TOKEN_KEY` (latest enabled) | `af89b2a5` |
| Staging Secret Manager `BUNNY_TOKEN_KEY` | **not computable — zero versions** |
| `functions/.env.dr-tarek-staging` `BUNNY_TOKEN_KEY` | **not computable — empty** |

**Conclusion:** the staging token key cannot be compared because it does not exist. It therefore cannot be shown to be "associated with `780700`". It is also **not** the production key (the production key exists only in `dr-tarek-platform` and matches production's zone).

---

## 5. Video availability

| Check | Result |
|---|---|
| Dashboard `Stream → 780700 → Overview` | "Let's upload your first video." |
| Stream API enumeration (`/library/780700/videos`) | **401** — cannot enumerate (no valid library key) |
| Videos with `status: 4` (Finished) | **0 confirmed** (dashboard empty library; API unreachable) |

**No processed video exists ⇒ Step 4 playback verification is not applicable and was not performed.** No signed URL was generated for a real video, saved, or logged.

---

## 6. Allowed Referer findings

Read for both zones (read-only):

| Zone | Library | `BlockNoneReferrer` | `AllowedReferrers` | `BlockedReferrers` |
|---|---|---|---|---|
| `6414868` (production) | `736742` | `true` | `[]` | `[]` |
| `6807898` (staging) | `780700` | `true` | `[]` | `[]` |

Consequences:

1. **No origin allow-list exists on either zone** — the only rule is "Referer must be non-empty". This closes the open risk flagged in Mission 10 §10: a web build on a custom domain, a preview channel, or `localhost` is accepted, because its browser-sent Referer is simply non-empty.
2. **Native clients are fine**: `lib/core/constants/bunny_playback_headers.dart` sends a fixed `Referer: https://dr-tarek-platform.web.app/`, which satisfies the non-empty rule (verified by existing widget tests and live probes).
3. **Clients that can still fail**: anything that strips the Referer — `Referrer-Policy: no-referrer` on the hosting page, browsers/extensions that remove it, some in-app webviews, or non-browser media tools. They receive **403** even with a valid signature.
4. Exact per-origin enforcement would break Flutter Web on any other origin; **do not add an `AllowedReferrers` entry** without a cross-client test matrix.

---

## 7. Exact staging drift diagnosis

**Verdict: MISCONFIGURED / UNCONFIGURED (playback impossible), not merely "partially configured".**

Drift layers:

| Layer | State | Evidence |
|---|---|---|
| Bunny account object | **Correct and owned** — library `780700`, Pull Zone `6807898`, hostname `vz-b5f9cb68-f06.b-cdn.net` known | §2 |
| Bunny protection model | **Different from production** — token auth OFF, `AllowDirectPlay=true`; production has token auth ON | §3 |
| Bunny content | **Empty** — 0 videos | §5 |
| Local env (`functions/.env.dr-tarek-staging`) | **Skeleton** — every Bunny value empty except the library id | §4 |
| Secret Manager (`dr-tarek-staging`) | **Placeholders** — secrets exist with no versions | §4 |
| Code default | **Production constant** — `DEFAULT_BUNNY_LIBRARY_ID = "736742"` | `bunny_library_registry.ts:26` |
| Documentation | **Stale** — `docs/IOS_STAGING_ENVIRONMENT_PLAN.md` still says secrets are absent and a test video exists | doc vs reality |

Relationship between the five items named in the mission:

1. **`BUNNY_STREAM_LIBRARY_ID=780700`** is read only by `resolveBunnyStreamApiRuntime` as `apiLibraryId` — i.e. it decides *which library the Stream metadata API path points at*, not which library the platform considers canonical.
2. **`DEFAULT_BUNNY_LIBRARY_ID="736742"`** is a compiled constant and stays the canonical id for anything resolved as "default".
3. **The `isDefault` bypass** means `736742` is always "active" regardless of `BUNNY_ACTIVE_LIBRARY_IDS`, so nothing ever fails closed on the staging side for that id.
4. **Legacy resources without `bunny_library_id`** always resolve to that constant (`source: "legacy_default"`), so in staging they would be labelled `736742` while the metadata path targets `780700` — a **split identity**.
5. **The empty `BUNNY_PLAYBACK_URL_TEMPLATE`** makes `resolveBunnyPlaybackRuntime` return `incomplete_configuration`, so issuance fails closed *before* the split identity can produce a wrong signed URL. Today the empty value is the only thing preventing a confusing failure mode; it is a symptom of an unfinished environment, not a safety feature.

Two additional consequences proven this mission:
- An empty `BUNNY_STREAM_API_KEY` yields `incomplete_configuration` from `resolveBunnyStreamApiRuntime` → metadata lookups return `null` and callers fall back exactly as if unconfigured. **No production credential is silently borrowed.**
- If someone later fills only the Stream key (`780700`) while the template stays empty, the split identity becomes reachable but still fail-closed; if they fill both, staging would sign with whatever `BUNNY_TOKEN_KEY` is supplied and would *not* be checked against the zone key — which is precisely why an activation probe gate is required in Option A.

---

## 8. Remaining blockers

| # | Blocker | Type | Smallest resolution |
|---|---|---|---|
| B1 | Staging has **no** Stream API key (empty + no Secret Manager secret) | Credential | Create/provision `BUNNY_STREAM_API_KEY` for `780700` (library API page) as a staging secret version |
| B2 | Staging `BUNNY_TOKEN_KEY` secret has **no versions**; env value empty | Credential | Add a version whose fingerprint equals the zone's `ZoneSecurityKey` (`cbf22628`) — read from the API, never pasted in chat |
| B3 | Staging `BUNNY_PLAYBACK_URL_TEMPLATE` missing (both mechanisms) | Config | Add `https://vz-b5f9cb68-f06.b-cdn.net/{video_id}/playlist.m3u8` as a staging secret version |
| B4 | Token authentication **disabled** on `6807898` | Bunny account (write) | Needs explicit approval: `PUT /videolibrary/780700 {EnableTokenAuthentication:true}` + re-read + probe matrix. **Not performed** |
| B5 | Staging library has **no video** | Content | Owner uploads one test clip, waits for status Finished |
| B6 | `DEFAULT_BUNNY_LIBRARY_ID` is a production constant | Code | Configurable default + startup invariant (Mission 10 §6.5). Needs approval |
| B7 | No activation gate that compares a supplied token key against the zone key | Code (Option A) | The Mission 9S probe matrix as a mandatory activation step |
| B8 | Documentation stale (`IOS_STAGING_ENVIRONMENT_PLAN.md`) | Docs | Update after staging intent is confirmed (Mission 10 D9) |

---

## 9. Recommended corrective actions (in order, none performed)

1. **Decide staging intent (Mission 10 D9).** If staging should not play video, the correct action is *documentation only*: remove the misleading Bunny variables from `functions/.env.dr-tarek-staging`, state "staging has no playback", and stop. Everything below applies only if staging must play.
2. **Provision the three staging values** (B1–B3) as Secret Manager **versions** in `dr-tarek-staging`, and stop duplicating the same names in `.env` files (one mechanism only).
3. **Enable token authentication on `6807898`** (B4) — a Bunny write requiring explicit approval; then re-run the 9S matrix (signed 200 / unsigned 403 / wrong-key 403) with the staging Referer.
4. **Upload one test clip** (B5) and re-run the playback matrix; record fingerprints, never keys.
5. **Code: remove the production constant** (B6) and add the invariant/log so a mismatch between `BUNNY_STREAM_LIBRARY_ID` and the canonical id is visible at boot; then add the activation probe gate (B7) as part of Option A.
6. **Update the staging documentation** (B8) and record the fingerprint→library mapping for every environment.
7. Keep `775315` inactive and unchanged (out of scope, per ADR-010).

---

## 10. Verification limits of this mission

- No Bunny write was made; token authentication was **not** enabled.
- The Stream API could not be enumerated (401) — the "0 videos" conclusion rests on the authenticated dashboard plus the API 401.
- The staging Secret Manager secrets were inspected by **name and version count only**; no value was read (there is none).
- Local `.env` files were inspected per-line for **value lengths** only; no secret value was printed, logged or stored. The empty-value finding is a length-0 observation.
- Production Pull Zone `6414868` was read again (same authorized `GET` as Mission 9S) solely to answer the Referer question; no other production object was read or changed.
- Mission 9S's `e1a3ddca` staging-key fingerprint is retracted as a parsing artifact (see §0). The production fingerprint (`af89b2a5`) stands and was recomputed consistently.

**Stop point:** verification complete. Report only — no implementation, no repair, no Bunny/Secret Manager write, no deployment, no Git action. Awaiting Platform Owner review.
