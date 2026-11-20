# ADR-010 — Amendment 3: Verified Library Modes, Unsigned Libraries, and Server-Owned Library Identity

Status: **Approved** — Platform Owner review (with FINAL_DECISIONS §4 deviation recorded)
Date: 2026-11-20
Version: 3.2
Amends: `21_ADR_010_Multi_Library_Bunny_Stream.md` (v1.0), `21_ADR_010_Amendment_1.md`,
`21_ADR_010_Amendment_2.md` (v2.0)
Related: `reports/adr010/MISSION_25_PHASE_0_AND_PLAN.md`,
`reports/adr010/MISSION_25_PHASE_1_STAGING_REPORT.md`,
`reports/adr010/MISSION_25_PHASE_2_GOVERNANCE_PROPOSAL.md`
Authority: Platform Owner review of Mission 25 Phase 1 (accepted) and the Phase 2 instructions
(2026-11-19)

No secret value appears in this document. Secret **names** only. No Bunny object (library,
video, collection, pull zone, Referrer setting, token) is created, modified or deleted by
this amendment; it is a governance decision, not an execution.

---

## 1. Context

### 1.1 What was broken

The platform could only play videos from one Bunny Stream library (`736742`). The diagnosis
established three independent causes:

1. `verifyBunnyLibrary` called `GET https://video.bunnycdn.com/library/{id}` and read
   `PlayerTokenAuthenticationEnabled`. That endpoint needs the **account** credential, so
   the probe was rejected (401/403) for every library while a library-scoped Stream key was
   in use. Verification therefore never proved anything, and no library other than the
   hard-wired legacy default could become eligible.
2. The catalog had no way to describe a library whose pull zone does **not** enforce CDN
   token authentication. Two of the account's libraries are in that state.
3. Selection still contained a silent default-library fallback, so "no library resolved"
   and "library 736742" were indistinguishable — the exact failure mode that makes a
   multi-library design unsafe.

### 1.2 Measured protection state of the four libraries

Read-only probes (status codes only; platform Referer `https://dr-tarek-platform.web.app/`):

| Library | Pull zone | Unsigned URL, no Referer | Unsigned URL, platform Referer | Mode |
| --- | --- | --- | --- | --- |
| `736742` (legacy) | `vz-c6abe953-876.b-cdn.net` | 403 | 403 | **signed** (token auth enforced) |
| `780700` (Staging test) | `vz-b5f9cb68-f06.b-cdn.net` | 403 | 403 | **signed** |
| `775315` (content) | `vz-c850a9e1-eb4.b-cdn.net` | 403 | **200** | **unsigned** |
| `776525` (content) | `vz-a9e3d4cc-384.b-cdn.net` | 403 | **200** | **unsigned** |

The 403/200 split on the unsigned libraries is not token enforcement — it is the hotlink
rule: `AllowedReferrers = []` with `BlockNoneReferrer = true` rejects a **missing** Referer
and accepts **any** Referer. Additional probes with foreign Referrers (dashboard, localhost,
`drtarek.com`) all returned 200, confirming that no allow-list exists. The platform Referer
is not hypothetical: the student app sends it explicitly on iOS/Android and the web build
inherits a non-empty page origin (§1.5).

### 1.3 Why the two libraries are unsigned (external constraint)

Both libraries serve a **legacy platform** that consumes their videos directly. Enabling CDN
token authentication on those pull zones would stop that older platform from playing them.
The constraint is external to this platform and is not removable from inside this repository
or from this platform's credentials. Option B (record the mode, accept the risk, publish the
permanent remediation path) was therefore selected by the Owner instead of enabling token
authentication on `775315` / `776525` (which was, and remains, forbidden).

### 1.4 What Phase 1 implemented and verified (Staging only)

- `token_auth_mode` in the catalog contract, registration and verification planner.
- `verifyBunnyLibrary` rewritten: no metadata call, optional token key, signed probe first,
  unsigned probe second, platform Referer on every request, typed failure reasons.
- New pure probe module with an injected transport and 24 mock-only assertions. Six emulator
  suites install a Bunny network guard and call `assertNoBunnyCalls()` before reporting
  success, so a test can never silently measure the live service.
- Staging catalog, all `active` and without an error code, registered through the audited
  Doctor callables: `736742` (`signed`), `775315` (`unsigned`), `776525` (`unsigned`),
  `780700` (`signed`).
- Staging Secret Manager: `BUNNY_736742_STREAM_API_KEY`, `BUNNY_736742_TOKEN_KEY`,
  `BUNNY_775315_STREAM_API_KEY`, `BUNNY_776525_STREAM_API_KEY` (plus the pre-existing
  `BUNNY_780700_*` pair), readable only by the Staging runtime service account.
- No environment change was needed: `BUNNY_ACTIVE_LIBRARY_IDS` keeps its Phase 1 value and no
  playback template was added. Production remains untouched (empty catalog, no deployment, no
  secret).

### 1.5 Client Referer evidence (student app, proved from source)

`BlockNoneReferrer` rejects a request with no Referer, so every platform client must send one.
The code proves that it does:

| Layer | Evidence | Value / behaviour |
| --- | --- | --- |
| Flutter constant | `lib/core/constants/bunny_playback_headers.dart:13-15` | `{'Referer': 'https://dr-tarek-platform.web.app/'}` |
| Main player | `lib/features/video_streaming/presentation/controllers/video_playback_controller.dart:766-773` | `VideoPlayerController.networkUrl(..., httpHeaders: bunnyPlaybackHttpHeaders)` for every `.m3u8`/network source |
| Autoplay preview | `lib/features/subject_navigation/presentation/screens/subject_navigation_screen.dart:1218-1221` | same `httpHeaders` map |
| Android transport | `video_player_android 2.12.0`, `HttpVideoAsset.java:89-92` | `DefaultHttpDataSource.Factory.setDefaultRequestProperties(httpHeaders)` — applies to playlist and segment requests |
| iOS transport | `video_player_avfoundation 2.11.0`, `VideoPlayerPlugin.swift:274-279` | `AVURLAssetHTTPHeaderFieldsKey: headers` — applies to every resource load of the asset |
| Flutter Web | `video_player_web_hls 1.3.0`, `lib/video_player_web_hls.dart:62` and `lib/src/video_player.dart:90-103` | headers are forwarded to `hls.js` `xhrSetup`; `Referer` is a forbidden browser header, so the browser supplies the page origin. `web/index.html` and `firebase.json` set no `Referrer-Policy`, so the default policy sends a non-empty origin |

Conclusion: native builds send the exact platform Referer; the web build sends the page
origin, which is non-empty. No client change is required for `unsigned` libraries, and no
client relies on the Referer for authorization (token/CDN protection remains the control where
it exists).

---

## 2. Decisions

**D1 — `token_auth_mode` is normative catalog state.**
`bunny_libraries/{libraryId}.token_auth_mode` is exactly `"signed"` or `"unsigned"`.
A document whose value is anything else is invalid and **never** eligible. `null` means
"never determined" (a row written before this amendment, or a failed probe); `null` is not
`unsigned` and never makes a library usable. Exclusion is decided by an explicit, probed
mode, never by absence of evidence.

**D2 — Verification proves the mode; it no longer reads library metadata.**
`verifyBunnyLibrary` (and any future scheduled verifier) must:

1. read only that library's `BUNNY_<id>_STREAM_API_KEY`;
2. list one existing video through `GET https://video.bunnycdn.com/library/{id}/videos`
   with that key;
3. if a `BUNNY_<id>_TOKEN_KEY` exists, request a **signed** directory-token playlist URL;
   2xx ⇒ mode `signed`, `token_auth_enabled = true`, `token_auth_verified = true`;
4. otherwise request the **plain** playlist URL; 2xx ⇒ mode `unsigned`,
   `token_auth_enabled = false`, `token_auth_verified = true`;
5. 401/403 on the plain URL ⇒ the zone is protected and no signed proof exists ⇒ failures
   remain a typed denial, never `active`.

Every probe request carries the platform Referer (`https://dr-tarek-platform.web.app/`),
because the account's pull zones set `BlockNoneReferrer`; a probe without it measures the
hotlink rule, not token enforcement. The Referer is a fixed platform constant, not
operator input.

**D3 — No silent default library.**
The default-library fallback is removed from the playback path. A resource plays only when
its `bunny_library_id` resolves to an eligible catalog entry. Consequences:

- "unresolved" is a typed denial (`library_not_resolved`), never library `736742`;
- the legacy default path may survive only behind the explicit
  `BUNNY_LEGACY_LIBRARY_FALLBACK` cutover flag, defaulted **off** once the production
  migration is applied, and removed afterwards;
- `736742` remains usable only as a **registered, verified catalog entry**.

**D4 — Video-to-library auto-discovery and dropdown fallback (authoring only).**
Authoring workflows must not require manual library selection when the library can be determined automatically.
A new callable Cloud Function `discoverBunnyVideoLibrary` is introduced for authoring:
- **Authorization:** Authenticated Doctor (Teacher) or Admin with delegated `admin_content` permission.
- **Input:** `{ videoId: string }` only. The identifier must be a bare GUID validated by `isValidBunnyVideoId`; URLs and malformed strings are rejected fail-closed.
- **Behavior:** Probes candidate active libraries—defined strictly as the intersection `BUNNY_ACTIVE_LIBRARY_IDS ∩ bunny_libraries` where `status == "active"` and `token_auth_verified == true`—by querying Bunny Stream API `GET /library/{id}/videos/{videoId}` using each library's own resolved Stream API key.
- **Output:** Typed status only:
  - `found`: `{ status: "found", libraryId: string, displayName: string }` (exactly one library holds the video).
  - `not_found`: `{ status: "not_found" }` (video not present in any active library).
  - `ambiguous`: `{ status: "ambiguous", candidateLibraryIds: string[] }` (video GUID exists in more than one active library).
- **Security:** Returns no key material, token, or playback URL. Enforces rate limiting per actor (burst protection) and records an `admin_audit_log` event for authoring tracking.
- **Fallback:** If discovery returns `not_found`, `ambiguous`, or is temporarily unavailable, the authoring dashboard displays a fallback dropdown picker populated by `listEligibleBunnyLibraries`.
- **Scope:** Discovery is strictly an authoring convenience; no client ever selects or passes the library used for **playback**, which remains strictly server-resolved from `bunny_library_id`.

**D5 — `bunny_library_id` is server-owned.**
Only the verified association path (`validateBunnyVideoAssociation` →
`associateBunnyVideoToLibrary`) writes `bunny_library_id`. Firestore Rules keep forcing
`null` on client create and immutability on client update. Association is written only after
the backend has verified, with that library's **own** Stream key, that the video exists in
that library. A client-supplied library id is never trusted, including in
`generateBunnySignedUrl`.

**D6 — Unassociated rows are never played by guesswork.**
Rows with a `bunny_video_id` but no `bunny_library_id` are **not** eligible after the
cutover flag flips; they are reported (not guessed) by the migration dry run. Rows with no
`bunny_video_id` (seven at Phase 0, including one soft-deleted row) are out of scope of the
migration and keep their current non-playable state. The excluded staging fixture
`I36lvn3FGRPGCX3YKVLw` (`47561140-5966-4e0f-8851-83c78ce5bb92`) on `780700` remains excluded
from any mapping and is named in every report.

**D7 — N10 is withdrawn; `775315` and `776525` are approved unsigned libraries.**
Amendment 2's N10 ("`775315` remediation is deferred, keep it inactive") is superseded: the
"remediation" it anticipated (enabling token authentication) is no longer the chosen path.
`775315` and `776525` are approved for platform use **in `unsigned` mode**. Activation stays
environment-scoped: Staging now, Production only through the Phase 4 gate.

**D8 — `BUNNY_ACTIVE_LIBRARY_IDS` activation role and zero-extra-variable emergency shutoff.**
The variable keeps its legacy name but is, in the implemented code, the per-environment
activation allow-list for libraries:

1. **Activation allow-list (grant).** A non-default library is eligible only when its id is
   listed. Registration plus verification make a library *eligible*; listing it here is what
   makes it *active* in that environment.
2. **Emergency deny switch (revoke).** Removing an id, or emptying the variable, disables
   that library immediately without a deploy. An empty or unset value denies every
   non-default library (fail-closed); a malformed value is never read as "allow all".
3. **No third environment variable:** No `BUNNY_DENIED_LIBRARY_IDS` is introduced. Immediate
   emergency shutdown of ANY library (including the default) is provided exclusively via the
   audited `deactivateBunnyLibrary` callable (`bunny_libraries/{id}.status = "disabled"`), which
   takes immediate effect across all server resolution paths without any deployment. Furthermore,
   once `BUNNY_LEGACY_LIBRARY_FALLBACK` is turned off (false) post-migration, the legacy default
   library bypass is eliminated completely: every library without exception (including `736742`)
   is strictly subject to active catalog status and `BUNNY_ACTIVE_LIBRARY_IDS`.

The list can never make an ineligible library usable: the catalog row and the proved mode
remain the authority, and a listed id with no valid catalog row still fails closed.

**D9 — Playback template derives from `playback_host`.**
A library's playback URL is built from its catalog `playback_host`
(`vz-*.b-cdn.net`), not from a global `BUNNY_PLAYBACK_URL_TEMPLATE`. The environment
template survives only as a legacy compatibility input for the pre-cutover default library
and is removed with the fallback. Each library therefore needs no per-library template
secret — only its Stream key, and a token key when it is `signed`.

**D10 — A future `signed` library requires no new design.**
Onboarding a new library that enforces token authentication is the ordinary path: register →
provision `BUNNY_<id>_STREAM_API_KEY` and `BUNNY_<id>_TOKEN_KEY` → verify (proves `signed`)
→ activate. The platform must never assume `unsigned`, and must never enable token
authentication on an existing library without a separate Owner approval (Amendment 2 N4
remains binding and unimplemented).

---

## 3. The unsigned mode: exposure, risk and the permanent exit

### 3.1 What is actually exposed

| Property | State for `775315` / `776525` |
| --- | --- |
| Token authentication (`ZoneSecurityEnabled`) | **off** |
| `AllowedReferrers` | **empty** |
| `BlockNoneReferrer` | **true** — only requests *without* a Referer are rejected |
| Practical effect | any client that sends **any** Referer can fetch the HLS playlist and segments |
| Platform authorization gates (entitlement, device, lecture access) | **unchanged and still enforced** before any URL is issued |

Therefore: **anyone who possesses a video GUID can play that video without a platform
account.** Hotlink protection is not access control, and a globally-empty allow-list is
effectively no hotlink protection at all. The platform's own gates still decide who gets a
URL from us, but they cannot prevent playback of a GUID obtained elsewhere.

**Explicit Deviation from FINAL_DECISIONS §4:**
FINAL_DECISIONS §4 established that *"URL auto-refreshes every time student opens video"* (via short-lived HMAC tokens) and *"Student never sees the URL"*. For unsigned libraries (`775315`, `776525`), the issued playback URL is persistent, unsigned, static, and visible to any network observer or client-side traffic logger.
*Deviation accepted by the Platform Owner, scoped to unsigned libraries until the permanent exit (section 3.3).*

### 3.2 Risk register

| ID | Risk | Likelihood | Impact | Interim control |
| --- | --- | --- | --- | --- |
| R-1 | A video GUID leaks (screenshot, share, referrer logs, browser history) and plays outside the platform | High | Medium — paid content viewable without entitlement | Keep GUIDs out of client logs/UI; do not publish embed links; monitor CDN traffic for anomalous referrers (read-only reporting) |
| R-2 | Competitor/aggregator embeds the CDN URL directly | Medium | Medium | None available on the pull zone without breaking the legacy platform; track it |
| R-3 | Broad `Referer` spoofing is trivial for any HTTP client | High | Low–Medium (same as R-1/R-2) | Accepted: Referer is not a security boundary here |
| R-4 | The mode is mis-recorded and an actually-protected library is served unsigned | Low | High — broken playback | Verification probes both modes and records evidence; `null` is never usable |
| R-5 | A future library is assumed unsigned | Low | Medium | D10: signed is the ordinary path; mode is always probed |
| R-6 | Explicit deviation from FINAL_DECISIONS §4: issued URL for unsigned libraries is persistent, static, and visible to network observers | High | Medium | Keep direct URL out of UI layers; app player streams transparently; track access; accepted by Platform Owner until permanent exit (§3.3) |

Residual risk after interim controls: **Medium**, accepted by the Owner for as long as the
legacy platform consumes these two libraries.

### 3.3 Permanent remediation path (the exit)

1. Create a new Bunny Stream library that will be platform-only (owner action in Bunny; the
   platform never creates libraries — Amendment 2 N11).
2. Enable CDN token authentication on it and set a concrete `AllowedReferrers` list
   (owner action; separately approved).
3. Upload/copy the videos into it (Bunny-side copy or re-upload; the platform does not
   mutate libraries).
4. Register → provision `BUNNY_<id>_STREAM_API_KEY` + `BUNNY_<id>_TOKEN_KEY` → verify
   (mode `signed`) → activate in the catalog.
5. Re-associate the affected resources to the new library through the audited path
   (verified association, no guessing).
6. Retire the unsigned libraries from `BUNNY_ACTIVE_LIBRARY_IDS` and disable their catalog
   rows (audited). The legacy platform keeps its own copies untouched.

### 3.4 Mandatory review

- **Review date: 2027-02-19** (90 days from the original 2026-11-19 issue), or earlier if a
  GUID leak is detected, or if the legacy platform is retired — whichever comes first.
- The review must record: whether the permanent library exists, how many resources have been
  migrated, and whether unsigned mode can be withdrawn. Silence is not acceptance: if the
  review does not happen, the risk stays open and must be re-reported.

---

## 4. Data-model effect (delegated to `05 Database`)

`05 Database` v1.13 adds:

- `bunny_libraries.token_auth_mode` (`"signed"` | `"unsigned"`, nullable only for
  never-verified rows);
- mode-aware eligibility: `status = "active"` **and** `token_auth_verified = true` **and**
  `token_auth_mode` present **and** `token_auth_enabled` equal to
  `(mode = "signed")`;
- the environment activation allow-list (`BUNNY_ACTIVE_LIBRARY_IDS`) as both the grant for a
  non-default library and the emergency deny switch, with emergency shutdown of any library
  provided via `deactivateBunnyLibrary` (`status = "disabled"`);
- the verification state machine updated so an `unsigned` proof is a success;
- the `bunny_library_id` ownership statement (server-only writer) and the unassociated-row
  policy (D6);
- `admin_audit_log` vocabulary unchanged (`bunny_library_verify` now records the mode).

`06 Firebase Architecture` v1.7 mirrors the same contract on the callable side
(`verifyBunnyLibrary`, probe semantics, Referer, no silent default, discovery, template
derivation, the dual-role activation list, zero extra env vars for deny, and the explicit
FINAL_DECISIONS §4 deviation for unsigned libraries).

---

## 5. Consequences

1. Libraries `775315` and `776525` become usable from the platform in `unsigned` mode; their
   videos stop being unplayable without any Bunny write.
2. `736742` keeps working, but only as a registered, verified catalog entry — not as an
   implicit default.
3. Multi-library playback becomes mode-correct: `signed` libraries keep signed issuance,
   `unsigned` libraries get plain URLs, and both stay behind the same platform gates.
4. The catalog now carries a security-relevant field. A wrong or missing mode denies
   playback instead of silently degrading it.
5. Accepted risk R-1…R-3 remains until the permanent signed library exists (§3.3–3.4).
6. One more environment variable is retired over time: `BUNNY_PLAYBACK_URL_TEMPLATE`
   (replaced by `playback_host` in the catalog). It is not removed by this amendment.
7. Existing clients need no protocol change: an unsigned HLS URL is still an HLS URL, and
   the Referer the clients already send is exactly what the pull zones require.

---

## 6. What this amendment does not authorize

- Enabling or disabling Bunny token authentication, Referrer lists, or any pull-zone or
  library setting (forbidden; only the Owner acts in Bunny).
- Any Bunny write of any kind (videos, libraries, collections, settings).
- Creating, rotating or deleting a secret; any IAM change.
- Deploying Cloud Functions, Rules or indexes to Production.
- Writing or migrating Firestore data.
- Activating `775315` / `776525` in Production (Phase 4 gate; requires the production
  catalog, secrets and a backup first).
- Flipping `BUNNY_LEGACY_LIBRARY_FALLBACK`.
- Enabling App Check or changing `APP_CHECK_ENFORCEMENT`.

Each requires its own approval under
`reports/adr010/ADR_010_OPTION_C_PRODUCTION_DEPLOYMENT_GATES.md`.

---

## 7. Supersession summary

| Item | Before | After |
| --- | --- | --- |
| `775315` | Deferred, must stay inactive (Amendment 2 N10) | Approved `unsigned` library; active in Staging, Production gated |
| `776525` | Not covered | Approved `unsigned` library; same rules |
| Catalog token state | `token_auth_enabled` + `token_auth_verified` | Plus normative `token_auth_mode` |
| Verification | Metadata read + optional token probe | Mode probe (signed → unsigned) with platform Referer |
| Default library | Silent fallback to `736742` | No fallback; must be a verified catalog entry |
| Playback template | Global env template | Derived from catalog `playback_host` |
| Emergency list | Can only reduce; default bypasses it | Dual role: activation allow-list for non-default libraries + emergency deny switch; default bypass closed once BUNNY_LEGACY_LIBRARY_FALLBACK is switched off; emergency shutdown of any library via deactivateBunnyLibrary (no extra env var) |
| `bunny_library_id` writer | Backend only (Rules) | Backend only; unassociated rows never played |

---

## Change Log

- 3.0 (2026-11-19): Initial issue, **Proposed**. Records verified per-library protection
  modes, the external constraint that keeps `775315`/`776525` unsigned, the exposure and
  accepted risk with a review date and permanent remediation path, withdrawal of N10,
  no-silent-default selection, server-owned `bunny_library_id`, template derivation from
  `playback_host`, and the separation of the emergency eligibility list from catalog
  authority.
- 3.1 (2026-11-20): Phase 1 completed on Staging (all four catalog entries verified, including
  `776525`), §1.4 refreshed, §1.5 added with the client Referer evidence (files, lines and
  values), and D8 corrected to the implemented dual role of `BUNNY_ACTIVE_LIBRARY_IDS`
  (activation allow-list + emergency deny switch, with the default-library bypass documented).
  §4 now points at `05 Database` v1.13 and `06 Firebase Architecture` v1.7. No decision
  changed; no Bunny, secret, IAM or Production action is authorized by this revision.
- 3.2 (2026-11-20): **Approved** by Platform Owner. Explicit deviation from FINAL_DECISIONS §4
  recorded (§3.1, §3.2 R-6) for unsigned libraries (persistent static URL visible to network
  observers); R-1 likelihood raised to High; BUNNY_DENIED_LIBRARY_IDS dropped in favor of
  zero-extra-variable emergency shutoff via deactivateBunnyLibrary (status="disabled") and
  post-migration fallback elimination (D8, §4, §7); discoverBunnyVideoLibrary specification
  formalized (D4); headers and versions synchronized across 05 Database (v1.13), 06 Firebase
  Architecture (v1.7), and ADR-010.
