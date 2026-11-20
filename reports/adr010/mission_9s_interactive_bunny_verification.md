# Mission 9S — Interactive Bunny Account Access & Complete B.3 Verification

**Date:** 2026-11-13
**Scope:** Read-only. No production setting, credential, video, rule, function or repository state was changed.
**Repository baseline:** `HEAD = 34a4b763e77087e0eeffd4aa8ad88bb820b61d46`, 0 staged entries, 30 tracked modified files + untracked reports (identical before and after this mission; the only file added is this report).

---

## 1. Previous reports reviewed

| Report | Exists | What was taken from it |
|---|---|---|
| `reports/adr010/mission_8_library_onboarding_architecture.md` | yes | Option A/B/C analysis; §B.3 open question; §N decisions awaiting approval |
| `reports/adr010/mission_9_bunny_token_key_verification.md` | yes | BLOCKED verdict; the verification procedure (§7) executed here |
| `reports/adr010/mission_9r_production_readonly_verification.md` | yes | BLOCKED verdict; library-scoped key → `api.bunny.net/videolibrary/736742` = 401, `video.bunnycdn.com/library/736742/videos` = 200 |
| `reports/adr010/mission_7_implementation_gate.md` | yes | Registry status; `736742` default/active, `775315` not activated; prior "signed HLS 200" evidence |
| `reports/adr010/library_configuration_readiness.md` | yes | `BUNNY_TOKEN_KEY` exists as a Secret Manager secret; template host `vz-c6abe953-876.b-cdn.net` |
| `reports/adr010/bunny_resource_inventory.md` (+ `.csv`) | yes | Per-video "signed playlist 200 on `vz-c6abe953-876` only" for `6ffb23ad…`, `d0c31ca2…` |
| `reports/adr010/OVERNIGHT_EXECUTION_REPORT.md` | yes | Library topology and pull-zone compatibility summary |
| `reports/adr010/mission_9_production_readonly_verification.md` | **does not exist** | The handoff named this file; the actual file is `mission_9r_…` (reported, not invented) |

No prior Mission 9S report or notes existed before this run.

---

## 2. Browser authentication result

- The agent's browser session was already authenticated as the Platform Owner's Bunny account; the Owner confirmed the login and instructed continuation.
- Dashboard fully navigable (account, Stream, library, security, API pages).
- No password, MFA code, recovery code, session cookie or session token was read, captured, stored, logged or transmitted. No MFA/CAPTCHA challenge was bypassed.

---

## 3. Credential type and approved scopes

- Bunny exposes exactly **one** account-level API key (Account → API key), valid for every account resource. Official documentation confirms: "Your account has one API key… We're working on scoped API keys" (`bunny.net/docs/api-reference/authentication`) and "Your API key has full access to your account" (`bunny.net/docs/account/api-keys`).
- No Team / Sub-user / Scopes UI exists; `/account/sub-users`, `/account/subusers`, `/account/api-keys` all return 404 in-session.
- **Owner authorization (this mission):** use the account key for **only** `GET /videolibrary/736742` and `GET /pullzone/{PullZoneId}`. No other request was made. No POST/PUT/PATCH/DELETE was performed.
- The key was read only from the authenticated dashboard page, used in-browser for those two requests, never printed, logged, stored in a file, or committed. Its length is 72 characters; its value is not recorded anywhere.

---

## 4. API request status codes

| Request | Result |
|---|---|
| `GET https://api.bunny.net/videolibrary/736742` | **200** |
| `GET https://api.bunny.net/pullzone/6414868` (id returned by request 1) | **200** |
| `GET api.bunny.net/videolibrary/736742` with the library-scoped Stream key (Mission 9R) | 401 `authentication.failed` (recorded for contrast: the library key is scope-limited) |

No further API calls were made.

---

## 5. Library ID and Pull Zone identity

| Field | Value | Source |
|---|---|---|
| `videolibrary.Id` | `736742` | API 200 |
| `videolibrary.Name` | `اختبار` | API 200 |
| `videolibrary.PullZoneId` | `6414868` | API 200 |
| `pullzone.Id` | `6414868` | API 200 |
| `pullzone.Name` | `vz-c6abe953-876` | API 200 |
| `pullzone.VideoLibraryId` | **`736742`** | API 200 |
| `pullzone.Hostnames` | `vz-c6abe953-876.b-cdn.net` | API 200 |
| `pullzone.ZoneSecurityEnabled` | **`true`** | API 200 |
| `pullzone.BlockNoneReferrer` | `true` | API 200 |

Identity back-reference `VideoLibraryId == 736742` is confirmed by the API, not only by the dashboard.

Videos used for the signing probes (existing, unmodified): `6ffb23ad-f073-480d-9a68-43baaf9803d5`, `d0c31ca2-5bb0-4821-8f5d-64bde4bcc5de`.

---

## 6. Was `ZoneSecurityKey` returned unmasked?

**Yes.**

- `pullzone.ZoneSecurityKey` is present, **36 characters** (UUID shape), and **not masked** — no `*`/`•` substitution, unlike the dashboard's masked field.
- Only a truncated fingerprint (first 8 hex of SHA-256) was computed and recorded: `af89b2a5`. The value itself was never printed, logged or written to disk.

---

## 7. Token Authentication state

- API: `ZoneSecurityEnabled = true`.
- Dashboard: library `736742` → Security → General shows "CDN token authentication" and the token key field (masked/read-only; reveal does not populate a value — the UI never exposes the key to automation, and it was not reset or regenerated).
- Behavioural confirmation: unsigned HLS with the app Referer → **403**; wrong-key signed → **403**; correct-key signed → **200**. Token authentication is enforced on this pull zone.

---

## 8. Signed / unsigned / wrong-key HTTP status codes

All probes read-only, signing performed in memory with the unmodified `hashVideoDirectoryToken` algorithm, `Referer: https://dr-tarek-platform.web.app/`, no URL stored or printed.

| Probe | Video `6ffb23ad…` | Video `d0c31ca2…` |
|---|---|---|
| Signed with the platform key (`BUNNY_TOKEN_KEY`, Secret Manager) | **200** — `content-type: application/vnd.apple.mpegurl`, body starts `#EXTM3U` | **200** — same content type and manifest |
| Unsigned | **403** | **403** |
| Signed with a wrong key (random UUID) | **403** | **403** |
| Signed with correct key but **no Referer** | 403 | 403 |

Operational note: `BlockNoneReferrer = true`, so a request without a Referer is rejected even when correctly signed. The platform already sends the app Referer; any future client must do the same.

---

## 9. Key identity comparison (`ZoneSecurityKey` vs platform signing key)

**Result: MATCH.**

- API-returned `ZoneSecurityKey`: 36 characters, fingerprint `af89b2a5`.
- `BUNNY_TOKEN_KEY` (latest enabled version, Secret Manager, project `dr-tarek-platform`): 36 characters, fingerprint `af89b2a5`.
- Comparison done in memory on truncated fingerprints only; neither value was displayed, logged, written to disk, or sent anywhere.
- Cross-check: a signature produced with the Secret Manager key is accepted by the pull zone whose API reports that same key (200), and a wrong-key signature is refused (403). Identity is therefore confirmed by both fingerprint equality and cryptographic acceptance.

**Conclusion: `ZoneSecurityKey` is the same key used by Bunny Stream token authentication.** Hypothesis B.3 is confirmed.

---

## 10. Verdict

# **PASS**

All required conditions are satisfied:

| Condition | Result |
|---|---|
| API returns `ZoneSecurityKey` in clear text | **PASS** (36 chars, unmasked, fingerprint recorded) |
| Pull Zone belongs to library `736742` | **PASS** (`VideoLibraryId = 736742`, host `vz-c6abe953-876.b-cdn.net`) |
| Token authentication enabled | **PASS** (`ZoneSecurityEnabled = true`, enforcement observed) |
| Correct-key signature → 200 | **PASS** (2/2 videos, correct HLS content type) |
| Unsigned request → 401/403 | **PASS** (403 with app Referer) |
| Wrong-key request → 401/403 | **PASS** (403) |
| Key identity confirmed | **PASS** (MATCH, fingerprint + cryptographic acceptance) |

---

## 11. Recommended Mission 8 architectural consequence

Because B.3 is confirmed, **Option C may collapse into Option A**: onboarding no longer requires a manual "copy the token key from the dashboard" step. The token key is obtainable programmatically as `GET /pullzone/{PullZoneId}.ZoneSecurityKey`.

Recommended shape:

1. **Onboarding sequence:** account-key → `POST /videolibrary` → read `PullZoneId` → `GET /pullzone/{id}` → store `ZoneSecurityKey` per library (`BUNNY_<LIB>_TOKEN_KEY` in Secret Manager) → set the playback template from the returned hostname → enable token authentication → verify.
2. **Verification gate remains mandatory:** unsigned 401/403, wrong-key 401/403, correct-key 200 with `application/vnd.apple.mpegurl`. A 200 alone is still not accepted as proof.
3. **Referer requirement must be modelled explicitly** (`BlockNoneReferrer`), otherwise a correctly signed URL fails for a reason unrelated to signing.
4. **Account key handling:** the account key remains broad and cannot be narrowed in Bunny today. It must live server-side only (Secret Manager), be used exclusively by the provisioning path, and never reach clients, logs or repositories. Prefer a dedicated onboarding principal/runbook over ad-hoc operator use.
5. **Library activation policy unchanged:** `775315` stays inactive and out of `BUNNY_ACTIVE_LIBRARY_IDS` until its own configuration and token authentication are provisioned and verified.
6. Preserve every previously approved ADR-010 guarantee (server-side library association, receipts, cutover gate).

This mission implements none of the above.

---

## 12. Remaining risks and limitations

1. **Account key breadth:** Bunny has no scoped keys (feature announced as in development). Any programmatic onboarding inherits full-account authority. Mitigation is procedural (server-side only, dedicated path, audit logging), not technical.
2. **Local staging environment drift (independent of B.3, unchanged):** `functions/.env.dr-tarek-staging` declares `BUNNY_STREAM_LIBRARY_ID=780700` and an empty `BUNNY_PLAYBACK_URL_TEMPLATE`, while production is `736742` + `vz-c6abe953-876`. Local runs with that file target the wrong library and fail closed. Not modified in this mission.
3. **Dashboard never exposes the token key** (read-only empty field; only copy or destructive regenerate). Programmatic rotation therefore depends on the API path proven here, not on the UI.
4. **Referer coupling:** `BlockNoneReferrer = true` means any client that omits the Referer gets 403 even with a valid token — a future source of false "signing broken" reports.
5. **No setting was rotated or regenerated:** the token key was read, not reset. Rotation planning remains a separate, explicitly approved operation.
6. Fixture drift between earlier evidence and today's run was avoided by fingerprint comparison rather than assumption; the earlier 403s observed with the *staging* key are explained by that file's library `780700`, not by a production signing defect.

---

## 13. Exact list of actions performed

1. Read the Mission 8, 9, 9R reports plus Mission 7, readiness, inventory and overnight reports; confirmed `mission_9_production_readonly_verification.md` does not exist (the file is `mission_9r_…`).
2. Enumerated the authenticated dashboard navigation and user menu; confirmed the absence of any scoped/sub-user credential UI (three 404s observed).
3. Fetched the official Bunny authentication and API-key documentation.
4. Requested and received the Owner's explicit authorization for: two account-key `GET`s, the visual/fingerprint key comparison against Secret Manager, and repository integrity inspection.
5. Opened Account → API key and revealed the key in the authenticated page only (72 chars); used it for exactly two in-browser requests; never printed, logged or stored it.
6. Executed `GET /videolibrary/736742` → 200 (`PullZoneId = 6414868`) and `GET /pullzone/6414868` → 200 (`VideoLibraryId = 736742`, `ZoneSecurityEnabled = true`, `BlockNoneReferrer = true`, `ZoneSecurityKey` present, 36 chars, unmasked).
7. Computed only a truncated fingerprint of `ZoneSecurityKey` in-browser.
8. Read `BUNNY_TOKEN_KEY` (latest enabled version) from Secret Manager into process memory via `gcloud`, computed its truncated fingerprint, and compared: **MATCH**.
9. Reproduced `hashVideoDirectoryToken` verbatim in a temporary script and ran, for two existing videos: signed (platform key) → 200 with `application/vnd.apple.mpegurl` / `#EXTM3U`; unsigned → 403; wrong key → 403; signed without Referer → 403.
10. Deleted the temporary script; verified `HEAD`, staged count and working-tree state are unchanged by this mission.
11. Inspected tracked modifications: 30 tracked files are modified (Mission 4 and prior missions), not two. The two most recently touched are `scripts/backfill_first_video.cjs` and `functions/test/first_video_backfill.test.js`; both changed only to carry the additive `bunny_library_id` field in the `first_video` projection (`firstVideoFields` / `sameFirstVideo` in the script; matching assertions and fixtures in the test). Nothing was staged, committed, reverted or discarded.
12. Wrote and updated this report.

**Stop condition reached.** No Mission 10, no Option A/C implementation, no Dashboard/Figma change, no deployment.

---

## Appendix — Correction (2026-11-13, Mission 11 re-verification)

The staging-key fingerprint recorded in §8/§12 as `e1a3ddca` is **retracted**: it was a
parsing artifact (a regex whose leading `\s*` spanned newlines captured a fragment of a
following line). `functions/.env.dr-tarek-staging` holds **empty values** for every Bunny
variable except `BUNNY_STREAM_LIBRARY_ID`, and the staging Secret Manager secrets have
**zero versions**. No staging signing key exists to fingerprint.

Nothing in the production evidence changes: `ZoneSecurityKey` of zone `6414868` is returned
unmasked, its fingerprint `af89b2a5` matches the production `BUNNY_TOKEN_KEY`, and the
signed/unsigned/wrong-key matrix produced 200/403/403. The B.3 verdict **PASS** stands.
