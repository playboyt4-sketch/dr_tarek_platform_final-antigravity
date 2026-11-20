# ADR-010 Option C — Dependency Map and Phase Plan (Phase 0)

Status: Phase 0 deliverable — planning only. No workstream started.
Date: 2026-11-17
Companion documents:
`ADR_010_OPTION_C_IMPLEMENTATION_BASELINE.md`,
`ADR_010_OPTION_C_DOCUMENT_IMPACT_MATRIX.md`,
`ADR_010_OPTION_C_PRODUCTION_DEPLOYMENT_GATES.md`

This plan describes *what depends on what*. It does not authorize any workstream to
start. Phase 1 begins only on explicit Platform Owner instruction.

---

## 1. Workstream inventory

| ID | Workstream | Current state (verified) |
|---|---|---|
| W01 | Bunny API capability verification | Not performed against this account |
| W02 | Account credential provisioning | No credential exists; N2 premise unsupported |
| W03 | Runtime Secret Manager access | Existing pattern works (1 binding per secret); no account/receipt secret |
| W04 | Library catalog | Read path implemented; write path absent; 0 documents |
| W05 | Library eligibility resolver | Implemented (allow-list intersection + `isDefault` bypass) |
| W06 | Per-library credential isolation | Implemented (`BUNNY_<id>_*` derivation, 60 s cache, legacy fallback flag) |
| W07 | Token Authentication verification | Not implemented; library model has no token-key field |
| W08 | Dedicated association receipt key | Not implemented; receipts signed with `BUNNY_TOKEN_KEY` |
| W09 | Registration and revocation callables | Not implemented |
| W10 | Audit records | Not implemented |
| W11 | Daily verification and alerting | Not implemented; no alert channel |
| W12 | Secure Stream upload architecture | Not implemented; Storage upload only |
| W13 | Dashboard library management | Not implemented; callable returns empty set; no UI authority |
| W14 | Student playback | Implemented for single library; per-resource resolution unexercised |
| W15 | Staging regression | Historical only (Mission 25); not re-run in Phase 0 |
| W16 | Production rollout | Not authorized |

---

## 2. Dependency graph

```
                        ┌──────────────────────────────────────┐
   B-02 test library ──►│ W01  Capability verification         │
   (external)           │      (Mission 9 protocol)            │
                        └───────┬──────────────┬───────────────┘
                                │              │
              ┌─────────────────┘              └──────────────┐
              ▼                                               ▼
   ┌──────────────────────┐                        ┌──────────────────────┐
   │ W02  Account cred    │◄── B-01 decision       │ W12  Stream upload   │
   │      (N2 resolution) │                        │      (U-05, U-06)    │
   └──────┬───────────────┘                        └──────┬───────────────┘
          │                                               │
          ▼                                               │
   ┌──────────────────────┐                               │
   │ W03  Runtime SM IAM  │                               │
   └──┬──────────┬────────┘                               │
      │          │                                        │
      │          ▼                                        │
      │   ┌──────────────────────┐                        │
      │   │ W08  Receipt key     │  (independent of W01)  │
      │   └──────────┬───────────┘                        │
      │              │                                    │
      ▼              │                                    │
   ┌──────────────────────┐                               │
   │ W07  Token auth      │                               │
   │      verification    │                               │
   └──────┬───────────────┘                               │
          │                                               │
          │        ┌──────────────────────┐               │
          └───────►│ W04  Catalog (write) │◄── B-04 (05 approval)
                   └──────┬───────────────┘               │
                          │                               │
        ┌─────────────────┼───────────────┐               │
        ▼                 ▼               ▼               │
 ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
 │ W05 elig.   │  │ W09 reg/rev │  │ W10 audit   │        │
 │ resolver    │  │ callables   │  │ records     │        │
 └──────┬──────┘  └──────┬──────┘  └─────────────┘        │
        │                │                                │
        │                ▼                                │
        │         ┌─────────────┐                         │
        │         │ W11 daily   │                         │
        │         │ verify+alert│◄── E-05 alert channel   │
        │         └──────┬──────┘                         │
        │                │                                │
        ▼                ▼                                ▼
 ┌──────────────────────────────────────────────────────────────┐
 │ W06  Per-library credential isolation  (already implemented) │
 └───────────────────────────┬──────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
 ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
 │ W14 Student │      │ W13 Dashboard│◄─────│ W12 upload  │
 │ playback    │      │ library mgmt │◄── B-03 Figma
 └──────┬──────┘      └──────┬──────┘      └─────────────┘
        │                    │
        └────────┬───────────┘
                 ▼
          ┌─────────────┐
          │ W15 Staging │
          │ regression  │
          └──────┬──────┘
                 ▼
          ┌─────────────┐
          │ W16 Prod    │
          │ rollout     │
          └─────────────┘
```

---

## 3. Dependency table

| Workstream | Depends on | Type | Notes |
|---|---|---|---|
| W01 | B-02 (test library) | External | Cannot start without a non-Production, non-`775315` library |
| W02 | W01, B-01 (owner decision) | Hard | The credential's scope is determined by the B-01 outcome |
| W03 | W02, W08 | Hard | Each new secret needs one `secretAccessor` binding before the consuming function deploys |
| W04 (write path) | B-04 (`05` approval), W09 | Hard | Schema must be approved; the writer is a callable |
| W05 | W04 (data) | Soft | Code exists; it returns nothing until the catalog has rows |
| W06 | W03 | Soft | Code exists; needs per-library secrets to be meaningful |
| W07 | W01, W02 | Hard | Requires the account credential (or manual verification if B-01 = N2-b) |
| W08 | W03 | **Independent** | New secret + dual-verify code; no account API needed |
| W09 | W02, W04, W10 | Hard | Registration needs catalog schema and audit writes |
| W10 | W04 | Soft | Audit collection schema can be defined alongside the catalog |
| W11 | W09, W07, E-05 | Hard | Needs registered libraries, a verification method, and a channel |
| W12 | W01 (U-05, U-06), W06 | Hard | Upload mechanism must be proven before design is fixed |
| W13 | W04, W09, W12, B-03 | Hard | UI needs a write API, an upload API, and an approved spec |
| W14 | W05, W06, W07 | Soft | Playback path exists; correctness depends on catalog and credentials |
| W15 | W13, W14, W12 | Hard | Regression requires the features to exist |
| W16 | W15, all gates | Hard | Governance gate |

---

## 4. Independent workstreams

These can proceed in parallel with the account-API workstream and do not wait on B-01:

| Workstream | Why it is independent |
|---|---|
| **W08** — receipt key | Purely local: one new secret, one dual-verify code path, one TTL window. Touches no Bunny API. |
| **W10** — audit records | Firestore-only; defines who did what and when. |
| **W04 (read half)** | Already implemented and deployed. |
| **W06** | Already implemented; only needs secrets to exist. |
| **W14 (default-library path)** | Works today; regression coverage can be written now. |
| **W05 (semantics)** | Implemented; only naming/doc alignment is outstanding. |
| **Documentation (Amendment 2, `00` registry, `FINAL_DECISIONS` §4, `05`)** | Governance text does not require any capability test. |
| **W12 (design only)** | TUS presigned upload is per-library-key based and documented; the *design* can be completed before W01, though the *proof* cannot. |

---

## 5. Hard blockers

| ID | Blocker | Blocks | Owner action required |
|---|---|---|---|
| B-01 | N2 is not implementable as written (no documented Stream-only sub-user key) | W02, W07, W09, W13 | Choose N2-a / N2-b / N2-c |
| B-02 | No dedicated test library (cannot use `736742` or `775315`) | W01, W12 proof | Provision or nominate a test library |
| B-03 | Figma unavailable for the four nodes | W13, N7, N8 | Provide token or export |
| B-04 | `05 Database` unapproved | W04 write, W09, W10, Gates 3–4 | Approve the schema |
| B-05 | `bunny_libraries` is empty in Production | W05 usefulness, W14 multi-library, migration | Sequence: register `736742` before requiring catalog completeness |
| B-06 | No registration/revocation callables | W13, W11 | Engineering (W09) |
| B-07 | Receipts coupled to `BUNNY_TOKEN_KEY` | N5, key rotation safety | Engineering (W08) |
| E-05 | No approved alert channel for N9 | W11 | Choose channel + credential |

**Blockers that cannot be resolved by engineering alone: B-01, B-02, B-03, B-04, E-05.**

---

## 6. Mission 9 capability test protocol

**Environment rules (non-negotiable):**

- Target a **dedicated test Stream library** on the Staging Bunny account, or a newly
  provisioned test library on the Production account **that is not** `736742` and
  **not** `775315`.
- Never use `736742` as a substitute. Never touch `775315`.
- Never call any key-reset endpoint.
- Never print, log, or persist a key value. Record only pass/fail and a redacted
  fingerprint (e.g. first 4 characters + length, or a SHA-256 of the value truncated
  to 8 hex characters — the fingerprint must not permit reconstruction).
- Read-only against Production. Any write happens only in the test library.

### 6.1 Unknown-level test matrix

| ID | Unknown | Evidence today | Exact test | Safe environment | Credential / permission | Pass criteria | Fail criteria | Fallback |
|---|---|---|---|---|---|---|---|---|
| U-01 | Stream API key returned unmasked by `GET /videolibrary/{id}` | `VideoLibraryModel.ApiKey` documented `string \| null`; masking unspecified | Call `GET https://api.bunny.net/videolibrary/{testLibraryId}` with the account credential. Inspect `ApiKey` and `ReadOnlyApiKey`. Compare against the library's key as shown in the test library's own API page (fingerprint only). | Test library | Account API key with read access to video libraries | Both fields present, non-null, and `ApiKey` fingerprint matches the library's own key | Null, absent, masked (`***`), or fingerprint mismatch | Use the manual/masked entry path (N7); do not attempt automatic retrieval |
| U-02 | `ZoneSecurityKey` available in clear text | `PullZoneModel.ZoneSecurityKey` documented, nullable, "security key used for secure URL token authentication" | Call `GET https://api.bunny.net/pullzone/{testPullZoneId}` with the account credential. Inspect `ZoneSecurityKey`. | Test library's pull zone | Account API key with pull-zone read | Non-null, non-masked string returned | Null, absent, or masked | Treat token key as manually supplied only |
| U-03 | `ZoneSecurityKey` equals the Stream library Token Authentication key | Library model has no token-key field; pull-zone model does | (a) Read `ZoneSecurityKey`. (b) Read the token key from the test library's Token Authentication settings in the dashboard. (c) Compare fingerprints. (d) Sign a short-lived token with `ZoneSecurityKey` and fetch a video through the test pull zone. | Test library + its pull zone | Account API key + dashboard read access | Fingerprints match **and** the token signed with `ZoneSecurityKey` plays | Mismatch, or token rejected | Token key must be supplied per library (N7 path); W07 cannot be automated |
| U-04 | Stream-only sub-user scope supports every required endpoint | No such scope documented; "Manage zones" is all-or-nothing | (a) Create a team member with only "Manage zones". (b) Attempt: list libraries, get one library, update one library (token auth flag), create a video, generate a TUS signature. (c) Record which succeed. | Test account/team | Owner-level access to create the team member | All five operations succeed with the restricted member | Any required operation returns 401/403 | Drop account-API automation (N2-b); manual registration only |
| U-05 | Secure browser-to-Bunny upload without exposing a library key | TUS presigned flow documented: server computes `SHA256(libraryId + apiKey + expire + videoId)` | (a) Server-side: `POST /library/{id}/videos` to create a video. (b) Server-side: compute the TUS signature. (c) Client: upload a small file to `https://video.bunnycdn.com/tusupload` with the signature and no key. (d) Verify the video appears and plays. (e) Confirm the browser never received the key (inspect network log). | Test library | Test library Stream API key (server-side only) | Upload completes; video plays; no key in any client-visible payload or log | Upload fails, or the key is required client-side | Server-side upload proxy (W12 alt) or keep out-of-band upload with manual video-id entry |
| U-06 | Server-side upload proxy necessary | Unknown; depends on U-05 and platform limits | If U-05 passes: measure max reliable file size through TUS from a browser on a poor connection; compare with expected lecture size. If U-05 fails: prototype a Cloud Functions proxy and measure the request timeout/body limit. | Test library | As U-05 | U-05 direct upload handles the largest expected lecture, or a proxy handles it within platform limits | Neither path handles the largest expected lecture | Chunked upload with resumable retry; or retain out-of-band upload |
| U-07 | Receipt-key transition supports old in-flight receipts | Current TTL 600 s; signing uses `BUNNY_TOKEN_KEY` | (a) With the old key, issue a receipt. (b) Deploy the dual-verify code. (c) Immediately present the old receipt and confirm acceptance. (d) At T+9 min present again; confirm acceptance. (e) At T+11 min confirm rejection. (f) Issue a new receipt and confirm it is signed with the new key only. | Staging Functions (not Production) | No external credential; uses the test/staging secret | Old receipts accepted for ≤10 min, rejected after; new receipts verify with the new key only | Old receipts rejected immediately (breaks in-flight users) or accepted after the window (key never retires) | Shorten the window to a duration shorter than the deploy window; or accept a brief re-association prompt |

### 6.2 Test ordering

U-01 and U-02 must run before U-03 (U-03 depends on both). U-04 can run independently.
U-05 before U-06. U-07 is independent of U-01…U-06 and can run in parallel.

### 6.3 Evidence to retain

For each unknown, retain: the request shape (endpoint + method, **no** key), the HTTP
status, a redacted response field list, pass/fail, and the date. Do not retain raw
response bodies that may contain key material.

---

## 7. Phase plan

Phases are sequential at the gate level, parallel inside. Each phase ends with a
report; none begins automatically.

### Phase 1 — Capability verification (Mission 9)

| Field | Value |
|---|---|
| Workstreams | W01 |
| Entry criteria | B-02 satisfied (dedicated test library exists); B-01 decided (needed for U-01/U-02/U-04) |
| Exit criteria | U-01…U-06 answered pass/fail with retained evidence |
| Outputs | Capability report; updated unknown register |
| Blocks on | Owner: test library, N2 decision |
| Deployment | None. Test library only. |

### Phase 2 — Governance

| Field | Value |
|---|---|
| Workstreams | Document updates 1–6 (Amendment 2, `00`, `FINAL_DECISIONS` §4, `05`, `15`/`14`, `04`) |
| Entry criteria | Owner approves the amendment texts |
| Exit criteria | Approved documents no longer contradict Option C |
| Outputs | ADR-010 Amendment 2; approved `05` |
| Deployment | None |
| Parallel | Yes — can run alongside Phase 1 |

### Phase 3 — Credential and secret layer

| Field | Value |
|---|---|
| Workstreams | W02, W03, W08 |
| Entry criteria | Phase 1 complete for the credential-scope questions; Phase 2 complete for `08` standards |
| Exit criteria | Account credential (if B-01 = N2-a) and receipt key exist; each has exactly one `secretAccessor` binding; no payload logged |
| Deployment | **Gate 1** |
| Parallel | W08 independent of W02 |

### Phase 4 — Catalog write path

| Field | Value |
|---|---|
| Workstreams | W04, W09, W10 |
| Entry criteria | `05` approved (B-04); Gate 1 complete |
| Exit criteria | Registration and revocation callables deployed to Staging; audit records written; catalog populated in Staging |
| Deployment | **Gate 2** (Staging first) |
| Note | Production catalog stays empty until Gate 6; the default-library fallback keeps playback working |

### Phase 5 — Verification and alerting

| Field | Value |
|---|---|
| Workstreams | W07, W11 |
| Entry criteria | Phase 1 (U-02/U-03), Phase 3 (W08), Phase 4 (W09) |
| Exit criteria | Daily verification runs in Staging; a deliberate drift (token auth disabled in the test library) raises an alert |
| Deployment | **Gate 2** |
| Blocks on | E-05 alert channel |

### Phase 6 — Upload, Dashboard, playback

| Field | Value |
|---|---|
| Workstreams | W12, W13, W14 |
| Entry criteria | Phase 1 (U-05/U-06), Phase 2 (`03` updated), B-03 resolved |
| Exit criteria | Upload works end-to-end in Staging; Dashboard manages libraries; playback resolves per-library |
| Deployment | **Gate 2** (Functions), **Gate 5** (Hosting) |

### Phase 7 — Staging regression

| Field | Value |
|---|---|
| Workstreams | W15 |
| Entry criteria | Phases 3–6 complete in Staging |
| Exit criteria | Full regression green: existing single-library playback, new multi-library playback, upload, revocation, kill switch |
| Deployment | None (test execution) |

### Phase 8 — Production rollout

| Field | Value |
|---|---|
| Workstreams | W16 |
| Entry criteria | Phase 7 green; all six gates approved individually |
| Exit criteria | Production serves ≥2 registered libraries with the default-library fallback still available |
| Deployment | **Gates 1–6**, each separately approved |
| Note | Not authorized by this mission |

---

## 8. Critical path

```
B-02 → W01 → B-01/W02 → W03 → W09 → W11 → W15 → W16
```

Length: 8 nodes. Every one of them is either an external prerequisite or a governance
decision except W01, W09, and W11.

**Second-longest path (playback-only, avoids the account API):**

```
W08 → W04(write, manual registration) → W09 → W14 → W15 → W16
```

This path is shorter and does not depend on B-01. If the Owner chooses **N2-b**
(no account-API automation), this becomes the primary path and the critical path
shortens by removing W02 and W07's account dependency.

**Consequence for sequencing:** the fastest safe increment is
**W08 + manual catalog registration + receipt-key separation**, which delivers N5 and
N1's write path without touching the account API at all.

---

## 9. Sequencing recommendation (not authorization)

| Recommendation | Rationale |
|---|---|
| Start with Phase 1 and Phase 2 in parallel | Phase 1 needs only B-02; Phase 2 needs only owner text approval |
| Treat W08 as the first code workstream | Independent, low risk, closes a real coupling (B-07) |
| Do not start W12 before U-05/U-06 | Designing an upload flow on an unproven mechanism risks a rewrite |
| Do not start W13 before B-03 | UI without an approved spec violates the mission rule against inventing UI |
| Register `736742` in the catalog **before** requiring catalog completeness | Otherwise the migration gate can never pass and playback depends on the fallback forever |

---

## 10. Phase 0 attestation

No workstream was started. No code, secret, Bunny setting, Firestore document, Rules
file, index, or deployment was changed. The only artifacts created are the four Phase 0
reports.
