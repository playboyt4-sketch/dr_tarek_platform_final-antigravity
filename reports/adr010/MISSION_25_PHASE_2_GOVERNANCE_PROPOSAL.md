# Mission 25 — Phase 2: Test Hardening and Governance Proposal

**Date:** 2026-11-19
**Scope:** Staging only for any live action. No Bunny write of any kind. Production untouched.
**Status:** `PROPOSED — awaiting the Owner's "معتمد" (approved)`

No secret value appears in this document; secret names only.

---

## 1. Owner review items and their outcome

| # | Owner instruction | Outcome |
| --- | --- | --- |
| 1 | Register `776525` on Staging through the audited path, add `BUNNY_776525_STREAM_API_KEY`, report the discovered mode, add it to `BUNNY_ACTIVE_LIBRARY_IDS` | **BLOCKED — source credential unavailable.** Nothing was registered or activated. Details in §3. |
| 2 | Run the full emulator suite, fix everything under "Needs fixes", prove verify/probe tests are mock-only | **DONE.** 59/59 → 60/60 files pass; the probe suite is now mock-only (24 assertions) and six emulator suites fail if any Bunny host is contacted. |
| 3 | Document the unsigned exposure explicitly in Amendment 3 | **DONE.** Amendment 3 §1.2, §1.3, §3.1–3.4. |
| 4 | Write Amendment 3 (Proposed) + 05 Database + 06 Firebase Architecture, show the summary and stop | **DONE.** §4–§6 below. |

---

## 2. Emulator-suite hardening (item 2)

### 2.1 Starting point

The full suite was run before any change: **59/59 files passed, exit 0** (`npm test`).
There was no entry under "Needs fixes"; the remaining risk was structural, not a failure:
the verification probes lived inside `index.ts` and could only be exercised by calling the
deployed callable — i.e. against the live service.

### 2.2 Change: probes extracted into a pure, transport-injected module

New `functions/src/core/video/bunny_playback_probe.ts`:

- `findBunnyProbeVideo`, `probeBunnyLibraryPlayback`, `probeBunnyLibraryUnsignedPlayback`,
  `buildBunnySignedProbeUrl`, `BUNNY_PLAYBACK_REFERER`;
- no Firestore, no Secret Manager, no `process.env`;
- the HTTP transport is an injected dependency (`deps.fetch`), with `nowMs` and `timeoutMs`
  also injectable; the production callable passes nothing and therefore uses the platform
  `fetch`;
- behaviour is byte-for-byte the same as the previous in-file implementation: same URLs,
  same `AccessKey` header, same HS256 directory-token scheme, same 8 s abort timeout, same
  platform Referer, same typed failure reasons.

`functions/src/index.ts` now imports these helpers; the duplicated local copies and the now
unused `bunnyProbeFailureReasonForStatus` import were removed. `npm run build` (tsc) exits 0.

### 2.3 New mock-only suite

`functions/test/bunny_playback_probe.test.js` — **24 assertions, zero network**:

- signed probe: two requests, correct list URL, `AccessKey` from that library only, platform
  `Referer`, HLS path on the library's own playback host, URL identical to the documented
  token builder, HMAC independently recomputed and matched, expiry present;
- typed outcomes: 404 → `library_not_found`, 401/403 → `credential_rejected`,
  500 → `video_list_unavailable`, empty/malformed list → `no_probe_target`, transport
  error → `probe_unreachable`, signed 403 → `signed_url_probe_failed`;
- unsigned probe: plain playlist (no `bcdn_token`), Referer still sent, 403 →
  `token_auth_enforced`, unexpected status → `unsigned_url_probe_failed`;
- the default transport is proven to be the process `fetch` (a mocked `global.fetch` is
  used when no dependency is passed);
- no probe result ever contains a key, token, URL or video id.

Registered in `test:pure` and in the aggregate emulator runner.

### 2.4 New offline guard for the emulator suites

`functions/test/bunny_network_guard.js` wraps `global.fetch` and rejects + records any
request to `*.bunnycdn.com`, `*.b-cdn.net` or `*.mediadelivery.net`. It is installed in the
six suites that execute Bunny callables:

`issuance_library_flow`, `bunny_library_validation_flow`, `bunny_association_flow`,
`bunny_library_lifecycle_flow`, `bunny_library_catalog_flow`,
`bunny_library_secret_resolver_flow`.

Each of those suites calls `assertNoBunnyCalls()` before reporting success, so a future
change that silently starts hitting Bunny fails the suite instead of measuring the service.

### 2.5 Results

| Run | Result |
| --- | --- |
| `npm run build` | exit 0 |
| `npm run test:pure` | exit 0 (includes `bunny_playback_probe` 24, `verify_modes` 40, `lifecycle` 77, `migration` 37, `association` 37, `playback_regression` 33, `secret_resolver` 40, `registry` 35) |
| `npm test` (full emulator suite, first post-change run) | 59/60 — one syntax error introduced while inserting the guard into a multi-line `console.log` in `bunny_library_secret_resolver_flow` |
| That file + the five other guarded suites, re-run in the emulator | all pass: 9, 49, 5, 15, 7, 11 assertions; exit 0; guard recorded 0 Bunny calls |
| `npm test` (full suite, final run) | see §7 |

No test was skipped, weakened or suppressed. The only test-side change was the added guard.

---

## 3. `776525` — blocked, and why

### 3.1 What is established

Library `776525` (pull zone `6782520`, playback host `vz-a9e3d4cc-384.b-cdn.net`) is
**unsigned**, proved read-only before Phase 1:

| Probe | Result |
| --- | --- |
| Plain playlist, no Referer | **403** |
| Plain playlist, platform Referer | **200** |
| Plain playlist, foreign Referers (dashboard, localhost, drtarek.com) | **200** each |
| `AllowedReferrers` | `[]` with `BlockNoneReferrer = true` |

So the mode is known even though the catalog row is not yet written.

### 3.2 Why it was not registered / activated

`verifyBunnyLibrary` must list one video with **that library's own** Stream key. The source
file used in Phase 1 (`D:\Temp\opencode\bunny_secrets\776525_stream_api_key.txt`, read only
by the out-of-repo probe harness) was deleted as required by Phase 1.5, and no copy exists:

- Secret Manager (both projects): only `BUNNY_775315_STREAM_API_KEY`,
  `BUNNY_780700_STREAM_API_KEY`, `BUNNY_780700_TOKEN_KEY`, `BUNNY_STREAM_API_KEY` — none of
  them reads `776525` (verified read-only: each returns **401** on
  `GET /library/776525/videos`);
- no `BUNNY_*` process environment variable exists; `functions/.env` and
  `.env.dr-tarek-staging` carry no key material;
- `D:\Temp\opencode\` contains no credential file (the directory was scanned in Phase 1.5);
- no `*776525*` / `*bunny*` file exists in the owner's Downloads folder.

Creating the secret with a placeholder, borrowing another library's key, or rotating a key
in Bunny are all forbidden. Registering the row without a verification would leave a
`pending_verification` catalog entry that can never become eligible, so nothing was written.

### 3.3 Exact unblock (no value in chat)

Owner action, either one:

1. Save the library's Stream API key as
   `D:\Temp\opencode\bunny_secrets\776525_stream_api_key.txt` (Bunny dashboard → Stream →
   library `776525` → API → Stream API key), and say it is there; or
2. Provide the path of any existing file that holds it.

I will then, without printing or logging the value: create `BUNNY_776525_STREAM_API_KEY`
(v1) in `dr-tarek-staging`, grant `roles/secretmanager.secretAccessor` to
`13159003436-compute@developer.gserviceaccount.com`, run `registerBunnyLibrary` then
`verifyBunnyLibrary` (expected `active` / `unsigned`), add `776525` to
`BUNNY_ACTIVE_LIBRARY_IDS` in `functions/.env.dr-tarek-staging` and redeploy the six
lifecycle callables, then delete the temporary file and verify the folder is empty.

---

## 4. `21_ADR_010_Amendment_3.md` (Proposed, v3.0)

Sections and what they decide:

| § | Content |
| --- | --- |
| 1.1 | Three root causes: the metadata verification call (account-scope credential), the absence of an unsigned mode, and the silent default library |
| 1.2 | Measured protection state of the four libraries (403/403 vs 403/200) |
| 1.3 | The external constraint: a legacy platform consumes `775315`/`776525`, so enabling token auth is impossible without breaking it |
| 1.4 | What Phase 1 already implemented on Staging |
| D1 | `token_auth_mode` (`signed` \| `unsigned`) is normative; `null`/unknown fails closed and is never read as `unsigned` |
| D2 | Verification proves the mode; no metadata read; token key optional; platform Referer on every probe; `unsigned` is a success |
| D3 | No silent default library; `library_not_resolved` is a typed denial; fallback only behind the explicit cutover flag |
| D4 | Authoring discovery + picker fallback; discovery never grants eligibility; playback library stays server-resolved |
| D5 | `bunny_library_id` is server-owned; Rules still force `null` on create and immutability on update |
| D6 | Unassociated rows are never played by guesswork; the 7 rows without a video id and the excluded `I36lvn3FGRPGCX3YKVLw` are named |
| D7 | N10 withdrawn: `775315`/`776525` are approved **unsigned** libraries (Staging now, Production gated) |
| D8 | `BUNNY_ACTIVE_LIBRARY_IDS` is a restriction only; catalog `disabled` + the planned `BUNNY_DENIED_LIBRARY_IDS` are the kill switches (closes the default-bypass gap) |
| D9 | Playback template derives from `playback_host`; the env template is legacy-only and retired with the fallback |
| D10 | A future `signed` library needs no new design; the platform never assumes `unsigned` and never enables token auth by itself |
| §3 | Exposure analysis, risk register R-1…R-5, interim controls, residual risk **Medium (accepted)**, **review date 2027-02-19**, and the six-step permanent path (new `signed` library → token auth → copy videos → verified registration → audited re-association → retire unsigned) |
| §6 | What the amendment does **not** authorize (no Bunny write, no secret/IAM change, no production deployment, no data write, no fallback flip) |

---

## 5. `05 Database` — v1.12 (Proposed)

File: `docs/notion/05 Database 1.8.md` (authoritative content; the filename is historical).
The document was already at v1.11 (approved), so the new version is **v1.12**, not v1.9 as
the mission text assumed.

| Location | Change |
| --- | --- |
| Header | `Version: 1.12`, `Status: Proposed (v1.12 — ADR-010 Amendment 3, documentation only)`; v1.11 stays the approved baseline |
| Version History | new v1.12 entry (mode field, unsigned rationale and risk, review date, permanent path, server-owned library id, no data operation authorized) |
| `bunny_libraries` → Contains | `Token Auth Mode` added |
| `bunny_libraries` field table | new `token_auth_mode` row: `"signed"` \| `"unsigned"`; `null` only before a successful verification; any other value invalidates the document; verification callable only; server-only |
| `bunny_libraries` state machine | `pending_verification → active` now requires a proved mode with a consistent `token_auth_enabled` (signed ⇒ true, unsigned ⇒ false) and the matching successful probe |
| Eligibility predicate | mode-aware: `status = active` ∧ `token_auth_verified` ∧ mode present ∧ `token_auth_enabled === (mode === "signed")`; missing/unknown mode fails closed |
| `lecture_resources.bunny_library_id` | explicitly **server-owned**; unassociated rows are not playable after the fallback is switched off and are repaired only by the audited migration |

---

## 6. `06 Firebase Architecture` — v1.6 (Draft)

File: `docs/notion/06_FIREBASE_ARCHITECTURE .md`.

| Location | Change |
| --- | --- |
| Header + changelog | `Version: 1.6`; v1.6 entry states it is Draft until Amendment 3 is approved and authorizes no callable behaviour by itself |
| §6.4 table | added `registerBunnyLibrary`, `verifyBunnyLibrary`, `deactivateBunnyLibrary` / `reactivateBunnyLibrary`, `listBunnyLibraryHealth`; `associateBunnyVideoToLibrary` row now states `bunny_library_id` is server-owned and no inference path exists |
| §6.4 Flow | library resolved from `bunny_library_id` with no silent default; issuance follows the proved mode (signed URL vs plain URL) |
| §6.4.1 | rewritten: `token_auth_mode` in the catalog; token key only for `signed`; mode-aware eligibility; metadata-free verification (signed probe → unsigned probe, Referer mandatory, 401/403 ⇒ still unverified); unsigned exposure and accepted risk + review date + permanent path; `playback_host`-derived URLs; no-silent-default and unassociated-row policy; authoring-only discovery/picker; `BUNNY_ACTIVE_LIBRARY_IDS` as restriction only, with catalog `disabled` and the planned `BUNNY_DENIED_LIBRARY_IDS` as kill switches |

No other document was modified. Mission 21–24 reports are untouched.

---

## 7. Verification

| Check | Command | Result |
| --- | --- | --- |
| TypeScript build | `npm run build` (functions) | exit 0 |
| Pure suites | `npm run test:pure` | exit 0 |
| New probe suite | `node test/bunny_playback_probe.test.js` | 24/24, exit 0 |
| Full emulator suite | `npm test` | 60/60 files, exit 0 (final run; see the log note below) |
| Guarded suites (re-run) | emulator `exec` of the six guarded files | all pass, 0 Bunny calls recorded |
| Production | — | not touched: no deployment, no secret, no catalog write |
| Bunny | — | read-only probes only; no write |

Final full-suite log: `D:\Temp\opencode\mission25\npm_test_final.log`.

---

## 8. Next gate

Phase 3 does not start until the Owner says **"معتمد"**. On approval, Phase 3 implements:
no silent default library, `playback_host`-derived template, signed/unsigned playback,
`discoverBunnyVideoLibrary`, the migration executor + `COLLECTION_GROUP` index, dashboard
picker/messaging, dead-code removal, and the matching tests. `776525` is completed as soon
as its Stream key is supplied (§3.3) — that is an execution detail, not a Phase 3 blocker.
