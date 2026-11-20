# ADR-010 — Mission 8: Zero-Configuration Bunny Library Onboarding
## Architecture Discovery & Decision Proposal

Date: 2026-11-13
Mode: **discovery and decision preparation only.** No code, configuration, Bunny account, Firestore,
Rules, secret, deployment, or production data change was made. Library `775315` was not activated.
Architecture under review: **Option C — Multi-Library Bunny Stream** (`21_ADR_010_Multi_Library_Bunny_Stream.md`),
Mission 4 server-side verified association, Mission 6 rules fix, Mission 7 implementation gate.

**Verdict: MISSION 8 — COMPLETE AS A DECISION PROPOSAL.**
Recommended architecture: **Option C (hybrid automatic discovery + one-time secret fallback)**.
Implementation is **BLOCKED** pending (a) Platform Owner approval of the decisions in §N, and (b) one
runtime capability verification in §B.3. No capability was invented; everything not proven against
official documentation is marked **UNVERIFIED**.

---

## A. Executive Summary

### A.1 The problem

Today every new Bunny Stream library is a **code-and-deploy event**:

- `functions/src/core/video/bunny_library_registry.ts` contains a hardcoded `BUNNY_LIBRARIES` array that
  maps each library id to **environment-variable names**.
- `functions/src/index.ts` declares those variables with `defineSecret(...)`, which are injected at
  **deploy time**. A new library therefore requires a new env var, a new secret version, and a Cloud
  Functions redeploy.
- The Dashboard library catalog is a **static client-side list**
  (`dashboard/.../bunny_library_catalog.dart`) with `736742` selectable and `775315` not.
- There is no server endpoint that lists eligible libraries, and no admin workflow to register one.

That directly violates the business objective: the Doctor must only create a library, upload videos,
copy two ids, and save.

### A.2 What the investigation proved

| Finding | Status |
|---|---|
| An account-level Bunny API key can list **all** Stream libraries and read each library's configuration | **VERIFIED** (official OpenAPI: `GET /videolibrary`, `GET /videolibrary/{id}`) |
| The account API returns each library's **Stream API key** (`ApiKey`, `ReadOnlyApiKey`) | **VERIFIED in the schema**; runtime masking **UNVERIFIED** |
| The account API can resolve the library's **Pull Zone**, its **hostnames**, and its **token-auth state** | **VERIFIED** (`PullZoneModel.Hostnames`, `ZoneSecurityEnabled`, `VideoLibraryId`) |
| The account API can **enable** CDN token authentication on a library | **VERIFIED** (`PUT /videolibrary/{id}` → `EnableTokenAuthentication`) |
| The **token signing key** is **not exposed as a library field** by any public API | **VERIFIED NEGATIVE** — no `TokenAuthenticationKey` in either official OpenAPI spec |
| The signing key is **probably readable** as the Pull Zone's `ZoneSecurityKey` | **UNVERIFIED** — needs one runtime call (see §B.3) |
| Video identity can be proven per library | **VERIFIED** — `GET /library/{id}/videos/{videoId}` returns `videoLibraryId` |
| The account key is **not** a substitute for the library key on Stream endpoints | **VERIFIED** (official authentication guide) |

### A.3 Recommendation

**Option C — Hybrid.** The backend auto-discovers and provisions everything Bunny exposes through its
API (library existence, ownership, API key, pull zone, hostname, token-auth enablement, token-auth
verification). The only thing that may still need the Doctor is the **token signing key**, and only if
§B.3 fails. If §B.3 passes, Option C collapses into Option A with **zero** extra Doctor steps.

Resulting Doctor workflow (target):

1. Create the library in Bunny, upload videos.
2. Copy Library ID + Video ID.
3. Paste both into the Dashboard and save.
4. The server discovers, verifies, enables token auth, stores credentials, and activates the library.

No Flutter/Dashboard code change, no Cloud Functions edit, no registry edit, no Firestore hand-edit, no
redeploy — for any future library.

### A.4 What must change in the platform

| Change | Why |
|---|---|
| Static `BUNNY_LIBRARIES` registry → Firestore-backed **library catalog** | A registry in code cannot be extended without a deploy |
| `defineSecret` env injection → **runtime Secret Manager reads** | Env secrets are fixed at deploy time |
| Static Dashboard catalog → **`listEligibleBunnyLibraries` callable** | The client must not be the source of truth |
| Library-scoped token key as receipt secret → **dedicated receipt key** | Receipts must not depend on a rotatable library credential |
| New admin/registration callables + audit collection | Provisioning needs an authorized, auditable path |
| Figma: picker + admin library screen | UI cannot be invented |

ADR-010's security guarantees are preserved: server-side association, fail-closed resolution, per-library
credential isolation, no client credential selection, HMAC receipts, unchanged playback authorization.

---

## B. Verified Bunny API Capabilities

Status legend:

- **VERIFIED** — proven by the official bunny.net OpenAPI specification or official documentation.
- **SCHEMA-VERIFIED / RUNTIME-UNVERIFIED** — the field/endpoint is documented, but the live behaviour
  (e.g. whether a secret is masked) could not be tested because this mission must not call the Bunny API
  and has no account credentials.
- **UNVERIFIED** — plausible but not proven; must not be relied on.
- **BLOCKED** — cannot be determined in this environment.

### B.1 Credential model (three different keys — they are not interchangeable)

| Credential | Scope | Where it is used | Documented source |
|---|---|---|---|
| **Account API key** | Whole bunny.net account | `https://api.bunny.net` (libraries, pull zones, DNS, billing, …) | Account → API in the dashboard; `AccessKey` header |
| **Library Stream API key** | One video library | `https://video.bunnycdn.com/library/{id}/…` | Library → API page; `AccessKey` header |
| **Library token signing key** ("token authentication key", a.k.a. zone security key) | One pull zone / library CDN | Signing playback URLs (`HS256-…`) | Library → Security page (Stream) / Pull Zone → Security (CDN) |

Official authentication guide, verbatim: *"Bunny Stream | The video library API key"* under
"Product credentials", and *"Managing video libraries, storage zones, and databases themselves uses your
account API key."* The account key is therefore an **onboarding** credential, not a playback or Stream
metadata credential.

### B.2 Answers to the eight investigation questions

| # | Question | Answer | Evidence / limitation |
|---|---|---|---|
| 1 | Can an account-level API key list all Stream libraries? | **YES** | `GET https://api.bunny.net/videolibrary` (scopes include `User`, `UserApi`, `SubuserAPIStream`, `ScopedApiKey`). `page=0` returns a plain array; `page>=1` returns `Items/CurrentPage/TotalItems/HasMoreItems`. |
| 2 | Can it retrieve a specific library's configuration and metadata? | **YES** | `GET /videolibrary/{id}` → `VideoLibraryModel`: `Id`, `Name`, `ApiKey`, `ReadOnlyApiKey`, `PullZoneId`, `StorageZoneId`, `PlayerTokenAuthenticationEnabled`, `AllowedReferrers`, `BlockedReferrers`, `BlockNoneReferrer`, `AllowDirectPlay`, `EnableMP4Fallback`, `EnableDRM`, `DateCreated/Modified`, … |
| 3 | Can the platform retrieve or provision each library's required API credentials? | **PARTIAL — documented, runtime unverified** | The model exposes `ApiKey` and `ReadOnlyApiKey`. `POST /videolibrary/{id}/resetApiKey` returns **204 with no body**, so rotation = reset + re-read. Whether the API returns the value unmasked (vs. only in the dashboard) is **RUNTIME-UNVERIFIED**. |
| 4 | How are per-library token signing keys obtained and managed? | **NO PUBLIC API FIELD** | The token key is displayed on the library Security page. Neither the core OpenAPI spec nor the Stream OpenAPI spec contains `TokenAuthenticationKey` (verified by parsing both specs). It **may** be the Pull Zone's `ZoneSecurityKey` (§B.3). |
| 5 | Can token authentication be enabled and verified programmatically? | **Enable: YES. Verify: YES (indirectly)** | Enable: `PUT /videolibrary/{id}` with `EnableTokenAuthentication: true` (also `EnableTokenIPVerification`, `ResetToken`). Verify: an unsigned HLS request must return 401/403, and a correctly signed one 200; `GET …/videos/{id}/play` also exposes `tokenAuthEnabled`. |
| 6 | Can playback configuration and Pull Zone information be discovered? | **YES** | `GET /videolibrary/{id}` → `PullZoneId`; `GET /pullzone/{id}` → `Hostnames[]` (`Value`, `IsSystemHostname`), `VideoLibraryId`, `ZoneSecurityEnabled`, `ZoneSecurityKey`. The system hostname is the `vz-….b-cdn.net` playback host. |
| 7 | Which operations require manual intervention? | **Create library, upload videos, copy ids** — plus **the token key if §B.3 fails** | Everything else is API-exposed. |
| 8 | Which operations can be automated safely? | Discovery, ownership proof, API-key provisioning, host resolution, token-auth enablement, token-auth verification, video identity verification, credential storage/rotation, eligibility listing | All are idempotent read/verify operations plus one documented settings update on a library the platform owns. |

### B.3 The single critical unknown — and its exact verification test

**Hypothesis:** the Stream "token authentication key" shown on the library Security page **is** the
underlying Pull Zone's `ZoneSecurityKey`.

Supporting evidence (not proof):

1. `PUT /videolibrary/{id}`'s `ResetToken` is documented as *"reset the CDN and embed view token key"* —
   one key for CDN delivery and embed view.
2. The Stream library is backed by a pull zone whose model carries `VideoLibraryId`, `ZoneSecurityEnabled`
   and `ZoneSecurityKey` ("The security key used for secure URL token authentication").
3. The platform already signs Stream HLS URLs with the standard **CDN Advanced Token Authentication**
   algorithm (`HS256-` + HMAC-SHA256 over `token_path`, `expires`, `signingData`) and this was verified
   live against `736742`'s zone in Mission 5/7. There is only one HMAC key that can validate that scheme
   on that zone.

**Verification test (5 minutes, one library, no production change):**

1. `GET /videolibrary/{testId}` → note `PullZoneId`.
2. `GET /pullzone/{pullZoneId}` → record whether `ZoneSecurityKey` is returned in clear (it is a documented
   field; masking is the only risk).
3. If Stream token auth is already enabled on that library: sign a playlist URL with `ZoneSecurityKey`
   using the existing `hashVideoDirectoryToken` algorithm and confirm HTTP 200. If it is not enabled:
   `PUT /videolibrary/{testId}` `{EnableTokenAuthentication: true}`, re-read the pull zone, then sign and
   confirm 200 **and** confirm the unsigned URL is 401/403.
4. Compare the working key with the key displayed on the library Security page (owner-side visual check).

Outcomes:

- **Pass** → Option A is fully achievable; the token key is auto-provisioned; the Doctor never sees a secret field.
- **Fail (masked or different key)** → Option C's one-time secret fallback is required; the Doctor pastes
  the token key once per library into a protected admin form.

This test is the **only** thing standing between the recommendation and true zero-configuration. It must be
run by the Owner (or with Owner-supplied credentials) before implementation starts.

### B.4 Manual vs automatable (final classification)

| Operation | Automatable | Notes |
|---|---|---|
| Create a Stream library | Yes (`POST /videolibrary`) but **not recommended** | The Doctor creates it; the platform should not invent libraries |
| Upload videos | No (out of platform scope today) | Dashboard is video-ID-only |
| Read library config / API key / pull zone / hostname | **Yes** | Account API |
| Enable CDN token authentication | **Yes** | `PUT /videolibrary/{id}` |
| Read the token signing key | **Only if §B.3 passes** | Otherwise manual, once |
| Verify token auth enforcement | **Yes** | Unsigned vs signed CDN probe |
| Verify a video belongs to a library | **Yes** | `GET /library/{id}/videos/{videoId}` + `videoLibraryId` |
| Rotate library API key | **Yes** | `resetApiKey` (204) + re-read |
| Rotate token key | **Yes only if §B.3 passes** | `ResetToken` + re-read `ZoneSecurityKey`; otherwise manual re-paste |
| Disable / revoke a library | **Yes** | Catalog status (platform-side) |

---

## C. Official Documentation References

All were retrieved on 2026-11-13. Two OpenAPI specifications were parsed programmatically; no Bunny API
call was made with any credential.

| # | Reference | What it proves |
|---|---|---|
| C1 | <https://bunny.net/docs/api-reference/authentication> | Account key vs product credentials; Stream uses the library API key; scoped keys are "in progress"; account key must be kept in a secret store |
| C2 | <https://bunny.net/docs/api-reference/core/stream-video-library/list-video-libraries> | `GET /videolibrary`, pagination, `VideoLibraryModel` including `ApiKey`, `ReadOnlyApiKey`, `PullZoneId` |
| C3 | <https://bunny.net/docs/api-reference/core/stream-video-library/get-video-library> | `GET /videolibrary/{id}`, 403 = "not accessible for the authenticated account" (ownership proof) |
| C4 | <https://bunny.net/docs/api-reference/core/stream-video-library/update-video-library> | `EnableTokenAuthentication`, `EnableTokenIPVerification`, `ResetToken` ("reset the CDN and embed view token key") |
| C5 | `https://core-api-public-docs.b-cdn.net/docs/v3/public.json` (official core OpenAPI, parsed) | Full `VideoLibraryModel`, `VideoLibraryUpdateModel`, `PullZoneModel` (`ZoneSecurityKey`, `Hostnames`, `VideoLibraryId`), `HostnameModel`, `ApiKeyModel`, all `/videolibrary` and `/pullzone` paths; **no `TokenAuthenticationKey` anywhere** |
| C6 | <https://bunny.net/docs/api-reference/stream/openapi.json> (official Stream OpenAPI, parsed) | Base `https://video.bunnycdn.com/`, `AccessKey` header, `GET /library/{libraryId}/videos/{videoId}`, `VideoModel.videoLibraryId`, `VideoModelStatus`, `VideoPlayDataModel.tokenAuthEnabled` |
| C7 | <https://bunny.net/docs/stream/authentication> | Every Stream HTTP API request is authenticated with a **per-library** Stream API key |
| C8 | <https://bunny.net/docs/stream/token-authentication> | Token security key is copied from the library Security page; it is **not** the library API key; sign server-side only |
| C9 | <https://bunny.net/docs/cdn/security/token-authentication/advanced> | `HS256-` HMAC-SHA256, `token_path`, `expires`, path-embedded `bcdn_token` — the algorithm the platform already implements |
| C10 | <https://bunny.net/docs/cdn/security/token-authentication> | Pull Zone token authentication uses the "URL Token Authentication Key" (`ZoneSecurityKey` in the API) |

Explicit non-claims:

- No page states that the library token key equals `ZoneSecurityKey`.
- No page states that `ApiKey`/`ReadOnlyApiKey` are returned unmasked by the API.
- No page documents a programmatic read of the token key as a **library** field.

---

## D. Current Architecture Limitations

| # | Limitation | Evidence | Consequence |
|---|---|---|---|
| D1 | Library registry is **code** | `bunny_library_registry.ts:63-82` — `BUNNY_LIBRARIES` maps `736742`/`775315` to env-var **names** | Adding a library requires a code change + deploy |
| D2 | Credentials are **deploy-time env secrets** | `index.ts:54-62` `defineSecret(...)`; `secrets: [...]` on each callable | New library = new secret + redeploy; cannot be zero-config |
| D3 | Activation is an **env allow-list** | `BUNNY_ACTIVE_LIBRARY_IDS` (`bunny_library_registry.ts:29`) | Another deploy-time knob |
| D4 | Resolvers are **synchronous + pure** over an env snapshot | `resolveBunnyLibraryForResource(env, …)` | Dynamic credentials need an async catalog/secret lookup (or a pre-loaded snapshot) |
| D5 | Dashboard catalog is **static client data** | `bunny_library_catalog.dart:55-66` | Client-side source of truth; cannot know about new libraries |
| D6 | No backend catalog endpoint | Mission 7 §F; no `listBunnyLibraries` callable exists | Dashboard cannot discover eligible libraries |
| D7 | New-video authoring silently defaults to `736742` | `add_lecture_overlay.dart:862-865`, `quick_upload_modal.dart:512`, mobile `_defaultBunnyLibraryId = '736742'` | Violates "no permanent single library" |
| D8 | Association receipts are signed with the **default library's token key** | `index.ts:4977-4988` → `getEnv("BUNNY_TOKEN_KEY")` | A library credential signs platform receipts; rotation invalidates in-flight receipts (10-min TTL) |
| D9 | `775315` is registry-defined but inactive and not token-protected | Mission 7 §C | Cannot be used until Bunny-side configuration is fixed |
| D10 | No credential rotation, audit, or revocation workflow | No catalog, no audit collection | Operational/security gap for multi-library |

What is already correct and must be preserved:

- Resolution from the **stored resource** (`index.ts:4803-4818`), not from client input.
- Client hint compare-and-ignore (`bunny_library_registry.ts:205-207`).
- Fail-closed for unknown / inactive / incomplete / mismatched libraries.
- Per-library template, token key, Stream key isolation.
- Video identity proof via `videoLibraryId` (`bunny_video_validation.ts:161-171`).
- HMAC receipt binding (resource + lecture + library + video + expiry), 10-minute TTL.
- Firestore Rules deny client writes to `bunny_library_id`; default-deny catch-all at the end of the file.

---

## E. Comparison of Options A, B, and C

### E.1 Option A — Account-level API integration with automatic discovery and provisioning

Backend holds an account-level key, discovers libraries, reads per-library keys, enables token auth, and
activates libraries with no operator interaction.

### E.2 Option B — One-time secure registration through a protected Dashboard admin workflow

The Doctor registers each library once (Library ID + library API key + token key + host, or just the
secrets), and the server validates and stores them. No account-level key.

### E.3 Option C — Hybrid: automatic discovery + controlled manual provisioning for what Bunny does not expose

Account-level key handles discovery, metadata, API-key provisioning, host resolution and token-auth
enablement/verification. The token key (and, if needed, the API key) is submitted **once** through the
protected admin flow only when the API cannot supply it.

### E.4 Comparison

| Dimension | A — Full auto | B — Manual registration | C — Hybrid (recommended) |
|---|---|---|---|
| Technical feasibility | **Feasible if §B.3 passes**; otherwise impossible (no token key) | **Feasible today** with documented fields only | **Feasible today**; degrades gracefully |
| Required credentials | Account API key + derived per-library keys | Library API key + token key per library | Account API key + derived keys, plus token key only if §B.3 fails |
| Blast radius of the onboarding credential | **High** — account key can manage DNS/billing/zones | **None** beyond one library | High for the account key; mitigate with a Stream-only sub-user and Secret Manager |
| Owner effort per library | 3 steps (create, upload, paste ids) | 5–7 steps (create, upload, copy 3–4 secrets, paste) | **3 steps**, plus 1 secret if §B.3 fails |
| Bunny API limitations | Token key not a documented field; `ApiKey` masking unverified | None (owner supplies everything) | Only the token key fallback |
| Firebase work | Catalog + Secret Manager + provisioner + callables + async resolver | Catalog + Secret Manager + registration callable + async resolver | Same as A, plus a secret-submission field in the admin flow |
| Failure modes | Account key revoked/rate-limited; masking; token key unreadable; wrong library ownership | Typo in a pasted key; wrong host; owner must understand secrets | All of A + B, but each failure has a defined fallback |
| Maintenance | Key rotation, daily verification, alerting, account-key hygiene | Per-library secret rotation, no account key | Same as A, with a manual path for token rotation |
| Cost | Negligible (Secret Manager cents; Bunny API free) | Negligible | Negligible |
| Security posture | Best UX, largest credential | Smallest credential, worst UX, secret handling by a human | Best balance: server-only secrets, least privilege, auditable |

### E.5 Recommendation

**Option C.** It is the only option that is (a) provably implementable with today's documented API and
(b) capable of reaching the business objective. It avoids making the entire architecture depend on the
single unverified capability, and it does not force the Doctor to handle secrets unless Bunny leaves no
alternative.

Adopt Option A behaviour **automatically** if §B.3 passes — no code fork, just the fallback field never
being shown.

---

## F. Recommended Architecture

### F.1 Target flow

```
Doctor: create library in Bunny + upload videos + copy Library ID / Video ID
                    │
                    ▼
Dashboard: "Add video" → Library ID + Video ID  (no secrets, no host, no template)
                    │
                    ▼
associateBunnyVideoToLibrary / validateBunnyVideoAssociation
                    │
                    ▼
Library Catalog Service (server)
  1. catalog lookup (Firestore) ── hit ──────────────┐
  2. miss → discover via account API                │
  3. prove ownership + read ReadOnlyApiKey          │
  4. resolve Pull Zone + system hostname            │
  5. ensure + verify token authentication           │
  6. persist metadata + secrets (Secret Manager)    │
  7. mark active                                    │
                    │                                │
                    ▼                                ▼
        verify video identity              resolve credentials
        (GET /library/{id}/videos/{videoId})          │
                    │                                │
                    ▼                                ▼
        HMAC receipt → write bunny_library_id    signed playback URL
```

### F.2 Components

| Component | Responsibility |
|---|---|
| **Firestore `bunny_libraries/{libraryId}`** | Non-secret catalog: status, display name, pull zone id, playback host, token-auth state, credential **references**, verification timestamps, error code |
| **Secret Manager** | Actual secret values: `bunny-library-{id}-stream-api-key`, `bunny-library-{id}-token-key`, `bunny-account-api-key` |
| **`bunny_library_catalog.ts`** (pure) | Catalog document validation, eligibility rules, client projection, migration mapping |
| **`bunny_library_provisioner.ts`** | Account-API client: discover, prove ownership, read keys, resolve zone/host, enable + verify token auth, rotate |
| **`bunny_library_credentials.ts`** | Secret Manager read/write + in-memory TTL cache + negative cache |
| **Resolver adapter** | Async `resolveLibraryForResource` that builds the existing pure env-snapshot shape from catalog + secrets, so `bunny_library_registry.ts` decision logic stays unchanged and unit-testable |
| **Callables** | `listEligibleBunnyLibraries`, `registerBunnyLibrary`, `verifyBunnyLibrary`, `disableBunnyLibrary`, `rotateBunnyLibraryCredentials`, `submitBunnyLibraryTokenKey` |
| **Scheduled function** | Daily `verifyBunnyLibraries`: re-check token auth, host, API key; mark `error` on drift |
| **`bunny_library_audit`** | Append-only audit events (actor, action, library, result, no secrets) |

### F.3 Eligibility rules (all must hold)

1. Catalog status `active`.
2. Library exists in the Bunny account and is accessible with the account key (`GET /videolibrary/{id}` → 200; 403/404 → not eligible).
3. Stream read key present and working (`GET /library/{id}/videos?page=1&pageSize=1` → 200).
4. Pull zone resolved and a system hostname exists.
5. Token authentication **enabled** and **verified** (unsigned 401/403, signed 200).
6. Required secrets resolvable from Secret Manager.
7. If `BUNNY_ACTIVE_LIBRARY_IDS` is set in the environment, the library must also be listed there
   (emergency kill switch that can only **reduce** eligibility, never expand it).

Any failure → the library is **not** listed and playback/association fail closed. There is no fallback to
another library.

### F.4 Resolution path (post-change)

1. `generateBunnySignedUrl` → resolve library from the stored resource (unchanged).
2. Resolver loads catalog entry (memory cache, TTL ≤ 5 min) + credentials (memory cache, TTL ≤ 10 min).
3. Unknown / disabled / incomplete → typed failure, no credential fallback (unchanged semantics).
4. Signing uses only that library's key/template (unchanged).
5. Cache invalidation: catalog writes bump `config_version`; resolvers compare a cheaply cached version doc
   (or simply use the short TTL). `disableBunnyLibrary` additionally writes a short-lived revocation marker.

---

## G. Secure Credential Lifecycle

### G.1 Secret inventory

| Secret | Stored in | Read by | Never exposed to |
|---|---|---|---|
| Account API key (Stream-only sub-user recommended) | Secret Manager `bunny-account-api-key` | Provisioner / scheduled verifier only | Dashboard, Flutter, logs, reports, client responses |
| Per-library Stream **read-only** API key | Secret Manager `bunny-library-{id}-stream-api-key` | Validation + metadata/thumbnail paths | Clients |
| Per-library token signing key | Secret Manager `bunny-library-{id}-token-key` | Playback signer + provisioner verifier | Clients |
| Association receipt key | Secret Manager `bunny-association-receipt-key` | Validation + association callables | Clients |

**Least privilege:** the platform only **reads** Stream data (validation, metadata, posters). It does not
upload videos. Therefore provision `ReadOnlyApiKey`, not `ApiKey`. This removes write/delete capability from
the platform entirely. If uploads are added later, that is a separate decision.

### G.2 Provisioning (first use of a new library)

1. Doctor submits `libraryId` + `videoId`.
2. Server validates the library id format (numeric, bounded length) — never accepts a host/template/URL.
3. `GET /videolibrary/{id}` with the account key:
   - 200 → ownership proven; read `ReadOnlyApiKey`, `PullZoneId`, `Name`, `DateCreated`.
   - 403/404 → "library not found in this Bunny account"; fail closed, no catalog row.
4. `GET /pullzone/{pullZoneId}` → `VideoLibraryId` must equal the library id; read `Hostnames` (system
   hostname), `ZoneSecurityEnabled`, `ZoneSecurityKey` (if returned).
5. Token auth:
   - if disabled → `PUT /videolibrary/{id}` `{EnableTokenAuthentication: true}` (only with approval §N-4);
   - re-read; probe unsigned HLS (expect 401/403) and signed HLS (expect 200);
   - if the key is unavailable or the probe fails → status `pending_verification`; if Option C fallback is
     enabled, request the token key from the admin flow once.
6. Write secrets to Secret Manager (create version, never log values).
7. Write catalog row `status: active`, `last_verified_at`, `config_version: 1`, credential references only.
8. Audit event.

All steps are idempotent: re-running uses the existing catalog row and only re-verifies.

### G.3 Rotation

| Credential | Rotation procedure | Automation |
|---|---|---|
| Library read API key | `POST /videolibrary/{id}/resetApiKey` (204, no body) → `GET /videolibrary/{id}` → write new secret version → verify a read call | Automatic (owner-initiated or scheduled) |
| Token key | `PUT /videolibrary/{id}` `{ResetToken: true}` → re-read `ZoneSecurityKey` → write secret → signed probe | Automatic **only if §B.3 passes**; otherwise the owner pastes the new key once |
| Account API key | Owner creates/rotates the sub-user key → writes a new Secret Manager version → verify discovery | Owner action + one command |
| Receipt key | New version with dual-verify window (accept old for 10 min) | Automatic |

Rotation never requires a redeploy and never touches `lecture_resources`.

### G.4 Revocation and compromise response

1. `disableBunnyLibrary` → status `disabled` + revocation marker → playback fails closed within the cache
   TTL (≤ 5 min; marker makes it immediate for signing).
2. Delete/disable the Secret Manager versions.
3. Rotate the account key if it may be compromised; rotate the library keys via Bunny.
4. Audit + incident note. Existing resources keep their `bunny_library_id`; they simply stop playing until
   the library is restored or (with explicit approval) re-associated.

### G.5 What the Doctor never does

- Never sees or copies the Stream API key, token key, receipt key, or account key.
- Never edits env vars, Firestore, or code.
- Never chooses a host, template, or credential.
- Only exception: if §B.3 fails, one token-key paste per library, in a masked, write-only admin field.

---

## H. Backend Components and Callable Contracts

### H.1 Firestore catalog document

`bunny_libraries/{libraryId}` (doc id = canonical numeric id as a string):

| Field | Type | Notes |
|---|---|---|
| `library_id` | string | Must equal doc id |
| `display_name` | string | From Bunny `Name`; non-secret |
| `status` | string | `pending_verification` \| `active` \| `disabled` \| `error` |
| `pull_zone_id` | number | From library |
| `playback_host` | string | System hostname only (e.g. `vz-….b-cdn.net`) |
| `stream_api_library_id` | string | Numeric id used in Stream API paths |
| `token_auth_enforced` | bool | Result of the probe, not the dashboard toggle |
| `credential_refs` | map | `{stream_api_key: "<secret name>", token_key: "<secret name>"}` — **names only** |
| `config_version` | number | Incremented on every credential/config change |
| `source` | string | `auto_discovered` \| `manual_registration` \| `legacy_env` |
| `last_verified_at` | timestamp | |
| `last_verified_by` | string | `system` or uid |
| `last_error` | string\|null | Stable error code, never a secret or Bunny response body |
| `created_at/created_by/updated_at/updated_by` | | Audit fields |

Firestore Rules: **no client access** (the existing default-deny catch-all already covers it; add an
explicit documented deny block for clarity). The Dashboard reads through a callable, never the collection.

### H.2 Callable contracts

All callables use the existing secure-call options (App Check + auth) and existing authorization helpers.
No callable ever returns a secret, a credential reference, a signed URL, or a Bunny error body.

| Callable | Auth | Request | Response | Errors |
|---|---|---|---|---|
| `listEligibleBunnyLibraries` | content manager (`requireContentManager`) | `{}` | `{libraries: [{libraryId, displayName}]}` — active+verified only | `unauthenticated`, `permission-denied` |
| `registerBunnyLibrary` | Owner/admin only | `{libraryId}` | `{status, libraryId, displayName, tokenAuthEnforced, missing?: "token_key"}` | `invalid-argument` (bad id), `not-found` (not in account), `failed-precondition` (token auth could not be enabled/verified), `permission-denied` |
| `submitBunnyLibraryTokenKey` | Owner/admin only | `{libraryId, tokenKey}` | `{status}` | `invalid-argument`, `failed-precondition` (probe failed), `permission-denied` |
| `verifyBunnyLibrary` | Owner/admin only | `{libraryId}` | `{status, tokenAuthEnforced, lastVerifiedAt}` | `not-found`, `failed-precondition` |
| `disableBunnyLibrary` | Owner/admin only | `{libraryId}` | `{status: "disabled"}` | `not-found`, `permission-denied` |
| `rotateBunnyLibraryCredentials` | Owner/admin only | `{libraryId, target: "stream_api_key"\|"token_key"}` | `{status}` | `failed-precondition` (needs manual re-paste), `permission-denied` |
| `validateBunnyVideoAssociation` (existing) | content manager | unchanged (`libraryId`, `videoId`, `resourceId?`, `lectureId?`) | unchanged + receipt | unchanged + catalog-specific `failed-precondition` reasons |
| `associateBunnyVideoToLibrary` (existing) | content manager | unchanged | unchanged | unchanged |
| `generateBunnySignedUrl` (existing) | student/staff authorization unchanged | unchanged | unchanged | unchanged |

New stable failure reasons (mapped to user-facing messages, never raw Bunny data):
`library_not_found`, `library_not_owned`, `token_auth_disabled`, `token_key_unavailable`,
`token_auth_verification_failed`, `playback_host_missing`, `credential_unavailable`, `catalog_error`.

### H.3 Resolver refactor (minimal, preserves guarantees)

Keep `bunny_library_registry.ts` pure. Add:

```ts
type CatalogSnapshot = Readonly<Record<string, {
  libraryId: string;
  active: boolean;
  playbackUrlTemplate: string;
  tokenKey: string;
  streamApiKey: string;
  apiLibraryId: string;
}>>;
```

`resolveBunnyLibraryForResource` continues to accept a snapshot shaped like the current env record, so
every existing unit test and fail-closed branch stays valid. The new async adapter loads the catalog +
secrets and builds that snapshot for **only** the requested library (no cross-library material), then calls
the pure resolver. This keeps per-library isolation provable in tests.

### H.4 Receipt key separation

Replace `getEnv("BUNNY_TOKEN_KEY")` as the receipt secret with a dedicated
`BUNNY_ASSOCIATION_RECEIPT_KEY` (Secret Manager). Claims, binding, HMAC-SHA256, base64url and TTL stay
identical. During the transition, verification accepts both keys for 10 minutes so in-flight receipts do
not fail. This removes the coupling where rotating a library's playback key invalidates platform receipts.

### H.5 Scheduled verification

Daily (Cloud Scheduler): for each `active` library, re-run steps 3–5 of §G.2 (read-only). On drift
(401/403 on signed probe, missing host, disabled token auth, key reset), set `status: error` +
`last_error`, keep failing closed, and alert the Owner. Never auto-rotate without approval.

---

## I. Dashboard Workflow Requirements

### I.1 Content-authoring flow (Doctor)

1. "Add video" (Add Lecture overlay / Quick Upload).
2. Fields: **Library ID** (picker of eligible libraries + "Enter another Library ID"), **Video ID**.
3. On save:
   - client sends only `libraryId` + `videoId` + resource/lecture binding;
   - server validates and associates; the client never sees credentials or hosts.
4. States to render (wording is a design decision, states are mandatory):

| State | Trigger | Required UI |
|---|---|---|
| Idle | no input | neutral |
| Validating | callable in flight | progress, fields disabled |
| Verified | association persisted | success, resource playable |
| Library not owned / not found | `library_not_found` / `library_not_owned` | actionable: "check the Library ID belongs to this Bunny account" |
| Library not ready | `token_auth_disabled` / `token_key_unavailable` / `token_auth_verification_failed` | actionable: "this library is not protected yet — contact the administrator" |
| Video mismatch | `video_mismatch` / `not_found_in_library` | actionable: "this Video ID is not in the selected library" |
| Unauthorized | `permission-denied` | no retry loop |
| Unavailable | network / Bunny timeout | retry allowed, nothing persisted |

5. **No** credential, host, template, or secret input on the content-authoring screen.
6. Retry after a failed association reuses the same contract and the same selected library.

### I.2 Admin flow (Owner only)

- List of libraries: id, display name, status badge, token-auth verified, last verified, error code.
- Actions: register by Library ID, re-verify, disable, rotate credentials.
- If §B.3 fails: a single **write-only** "Token signing key" field (masked, never echoed, cleared after submit).
- Never displays any secret after submission; shows only "configured / missing".

### I.3 What the Dashboard must stop doing

- Delete the static `defaultBunnyLibraryCatalog` as the source of truth (keep it only as a test fixture).
- Stop defaulting new videos to `736742` when the eligible list is available.
- Stop hardcoding `736742` in the mobile authoring fallback; use the selected/eligible library, and fail
  closed if none is known.

---

## J. Migration and Backward Compatibility

| Concern | Plan |
|---|---|
| Existing `736742` | One-time seed: read the existing env values, write catalog row `source: legacy_env`, `status: active`; secrets copied into Secret Manager. Production behaviour must be byte-identical (same host, template, key). |
| Existing `775315` | **Not activated.** It is registered only after its security prerequisites are met (token auth enabled + verified) and the Owner approves. Its three videos stay associated with `775315`; no migration. |
| Existing `bunny_library_id` values | Unchanged; ids are the same canonical numeric strings. No data migration. |
| `BUNNY_ACTIVE_LIBRARY_IDS` | Keep as an optional **emergency deny** list; catalog status is the primary eligibility source. Removing it later is a separate decision. |
| `BUNNY_LEGACY_LIBRARY_FALLBACK` | Unchanged. Legacy rows without `bunny_library_id` keep resolving to the default library until the backfill/cutover is complete. |
| `BUNNY_ASSOCIATION_CUTOVER` | Unchanged by this mission. The catalog does not alter legacy/pending classification. |
| Receipts | Claims unchanged; signing key migrates to a dedicated secret with a 10-minute dual-verify window. |
| Rollback | Feature flag `BUNNY_CATALOG_ENABLED=false` → resolver falls back to the static env registry (current behaviour). The catalog rows remain for audit. |
| Firestore Rules | No weakening. Catalog collection is server-only; the existing default-deny already blocks it. |
| Flutter | Existing `first_video` / playback contracts unchanged. Only the authoring library selection changes, and only after Figma. |

---

## K. Security Threat Analysis

| # | Threat | Vector | Mitigation | Residual |
|---|---|---|---|---|
| K1 | Account API key compromise | Leaked secret / over-broad IAM | Stream-only sub-user key, Secret Manager, least-privilege IAM, no client exposure, rotation, audit alerts | Account-level Stream access until scoped keys ship |
| K2 | Malicious library registration | Staff account registers an attacker-owned library | Owner/admin-only callable; server proves ownership via the account key (403 for other accounts); audit | A compromised Owner account can register anything the account owns |
| K3 | Client selects credentials / host | Forged request fields | Server ignores client host/template; only a numeric library id is accepted; credentials resolved server-side | None |
| K4 | Confused deputy on playback | Client sends a different `libraryId` | Existing compare-with-stored + `library_mismatch` fail closed | None |
| K5 | Receipt forgery / replay | Reuse a receipt on another resource | Existing binding + TTL + HMAC; dedicated receipt key | None |
| K6 | Token-auth downgrade | Register a library with token auth off | Activation requires a verified unsigned-401/signed-200 probe; otherwise `pending_verification` | Owner could disable token auth later; daily verification detects it |
| K7 | Hotlinking | Playback URL shared | Per-library token auth with short expiry (existing) | Token TTL window (existing policy) |
| K8 | Secret exfiltration via API | Callable returns credential refs/values | Whitelisted projections; never return refs, values, Bunny bodies | None |
| K9 | Catalog poisoning | Direct Firestore write | Rules deny all client access; Admin SDK only | Compromised backend |
| K10 | Stale cache after disable | In-memory cache | Short TTL + revocation marker + `config_version` check | ≤ TTL for non-marker paths |
| K11 | SSRF via library id/host | Malicious id string | Numeric-id validation; host comes from Bunny, never from input | None |
| K12 | Secret sprawl / rotation failure | Many libraries | Deterministic secret names, versioning, scheduled verification, rotation runbook | Operational discipline |
| K13 | Denial of wallet | Repeated provisioning calls | Rate-limit admin callables, cache discovery, single-flight provisioning per library | None material |
| K14 | Wrong video accepted | Video exists in two libraries | `videoLibraryId` equality check (existing) + per-library Stream key | None |

Preserved controls (must not regress): App Check, staff authorization, subscription/window/session gates,
device binding, signed-URL expiry, Firestore default-deny, `created_at` immutability.

---

## L. Required Figma Changes

No UI may be implemented before these are approved. Minimum scope:

1. **Add/Edit video resource — Library field**
   - Picker listing eligible libraries (from the callable) + "Enter Library ID".
   - Compact "verified / not verified" affordance after validation.
   - Error states for §I.1 (6 states), including the two actionable "library not ready" variants.
   - Behavior when the Video ID changes on an existing resource (re-verify, keep stored library).
2. **Quick Upload — Library field**
   - Same component, compact variant, defaulting to the only eligible library when exactly one exists.
3. **Admin — Bunny Libraries screen (Owner)**
   - Table: id, name, status badge, token-auth verified, last verified, error code.
   - Actions: register, verify, disable, rotate.
   - Conditional write-only token-key field (only if §B.3 fails), masked, never echoed.
4. **States not to invent:** empty catalog, one library, multiple libraries, pending verification,
   disabled library, permission denied, offline.

Explicitly out of scope: any visual change to playback, student screens, or unrelated settings.

---

## M. Implementation Plan and Dependencies

### M.1 Phases

| Phase | Work | Exit criterion | Size |
|---|---|---|---|
| **0 — Capability verification** | Run §B.3 against a test library with Owner-supplied credentials | `ZoneSecurityKey` identity and `ApiKey` visibility decided | XS (hours) |
| **1 — ADR amendment** | Document catalog, dynamic credentials, receipt key, kill switch | Approved decision record | S |
| **2 — Catalog + secrets** | `bunny_libraries`, Secret Manager module, pure catalog rules, async resolver adapter, seed `736742` | Existing tests pass; `736742` behaviour identical; feature flag off by default | M |
| **3 — Provisioner + callables** | Account-API client, register/verify/disable/rotate/list, audit, rate limits | Emulator tests for every failure reason; no secret in any response | M |
| **4 — Wire existing flows** | `validate`/`associate`/issuance/thumbnails read the catalog | Mission 7 suites pass unchanged | M |
| **5 — Dashboard domain/gateway** | `listEligibleBunnyLibraries` client, selection state, error mapping (no UI) | Unit tests; static catalog demoted to fixture | S |
| **6 — UI per Figma** | Picker + admin screen | Approved Figma + widget tests | M |
| **7 — Rollout** | Seed, shadow verification, enable flag, then remove `BUNNY_ACTIVE_LIBRARY_IDS` dependency | Verified in staging; production cutover approved separately | S |

### M.2 Test plan (to be executed in implementation, not now)

- Pure catalog: eligibility matrix, fail-closed reasons, projection whitelist.
- Provisioner: mocked Bunny responses for 200/401/403/404/429/500, masked keys, missing host, token-auth
  probe mismatch, idempotent re-registration.
- Resolver: per-library isolation, no cross-library credentials, unknown/disabled/incomplete fail closed.
- Receipt: dedicated key, dual-verify window, tamper/expiry/cross-binding.
- Callables: auth matrix (content manager vs owner vs student), no secret leakage in responses/logs.
- Emulator end-to-end: new library → validate → associate → sign → play (no Bunny network; mocked).
- Regression: all Mission 7 suites + Firestore/Storage rules suite.

### M.3 Dependencies and prerequisites

1. Owner approval of §N decisions.
2. A Bunny **test library** (or explicit permission to probe an existing non-critical library) for §B.3.
3. Account API key (preferably a Stream-only sub-user key) stored in Secret Manager.
4. IAM: `secretmanager.versions.access` for the functions service account; `secretmanager.admin` only for
   the provisioning path (or a separate service account).
5. New dependency `@google-cloud/secret-manager` (functions) — a package change, not yet made.
6. Approved Figma for §L.
7. Explicit approval for the receipt-key change and for enabling token auth on newly registered libraries.

### M.4 Cost

- Secret Manager: ~$0.06 per secret/month + $0.03 per 10k accesses → cents at this scale.
- Bunny API: no extra charge; respect rate limits and cache.
- Operational: daily verification job (negligible) + on-call alerting.

---

## N. Outstanding Decisions Requiring Platform Owner Approval

| # | Decision | Recommendation | Impact if declined |
|---|---|---|---|
| N1 | Adopt a server-managed **library catalog** as the source of truth (amends ADR-010 *implementation*, not its guarantees) | Approve | Zero-config is impossible; every library stays a deploy |
| N2 | Store an **account-level API key** in Secret Manager for discovery/provisioning | Approve, using a **Stream-only sub-user** key | Only Option B remains (manual secrets per library) |
| N3 | Use `ReadOnlyApiKey` (not `ApiKey`) for the platform | Approve | Platform would hold write/delete capability it does not need |
| N4 | Let the backend **enable CDN token authentication** automatically on newly registered libraries | Approve for libraries registered by this platform only | Library stays `pending_verification` until the Owner enables it manually |
| N5 | Introduce a **dedicated receipt signing key** (`BUNNY_ASSOCIATION_RECEIPT_KEY`) with a 10-minute dual-verify window | Approve | Receipts remain coupled to a rotatable library key |
| N6 | Keep `BUNNY_ACTIVE_LIBRARY_IDS` as an **emergency deny list** (can only reduce eligibility) | Approve | Losing an incident kill switch |
| N7 | Decide the **§B.3 fallback UX**: masked one-time token-key field in the admin screen | Approve | If §B.3 fails, no path to activate a new library |
| N8 | Approve **Figma scope** in §L | Approve | UI implementation remains blocked |
| N9 | Approve the **daily verification** job + alert channel | Approve | Drift (key reset, token auth off) is detected only at playback failure |
| N10 | Approve the **`775315` remediation** (enable token auth, then register) as a separate change | Defer until after the catalog ships | Three existing videos stay unplayable |
| N11 | Decide whether the platform may ever create libraries (`POST /videolibrary`) | Recommend **no** | None; out of scope |
| N12 | Decide behavior when the account key is unavailable: use cached catalog+secrets until expiry, or fail closed immediately | Recommend: **use cached credentials** (playback must not depend on the account API); provisioning fails | Playback outage during an account-key incident |

---

## O. Final Verdict

**MISSION 8 — COMPLETE AS A DECISION PROPOSAL.**

- The Bunny capability model is verified against official documentation and both official OpenAPI
  specifications. Account-level discovery, library configuration, Stream read-key provisioning, pull-zone
  host discovery, token-auth enablement and video identity proof are all **API-supported**.
- The **token signing key is not a documented library API field**. Its probable source (`ZoneSecurityKey`)
  is explicitly marked **UNVERIFIED** with a precise test; no capability was invented.
- **Option C (hybrid)** is recommended: full automatic onboarding where the API supports it, with a single
  masked one-time secret fallback only if §B.3 fails. It meets the business objective (create → upload →
  paste two ids → save) and preserves every ADR-010/Mission 4 security guarantee.
- **Implementation is BLOCKED** pending Owner approval of §N and the §B.3 verification. No code,
  configuration, secret, Rules, Firestore, Bunny setting, or production data was changed by this mission.
  Library `775315` remains inactive.

**Stop point:** this report is the deliverable. No implementation, deployment, or Mission 9 work begins
without explicit approval.
