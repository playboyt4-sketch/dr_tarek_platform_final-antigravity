# ADR-010 Option C — Implementation Baseline (Phase 0)

Status: Phase 0 deliverable — evidence baseline only. No implementation, no deployment.
Date: 2026-11-17
Author role: Lead Software Architect / Firebase Engineer / Bunny Stream Integration Engineer / Technical Project Lead
Scope: ADR-010 Option C — Hybrid Multi-Library Bunny Stream
Authority: Platform Owner approval of ADR-010 Option C and Mission 8 recommendations N1–N12
(architecture and implementation direction only — **not** a deployment authorization)

This report records what is true today. It does not propose code, does not create
secrets, does not change Bunny settings, does not change Firestore, and does not
deploy anything. Every statement below is tagged with its evidence class:

- **[APPROVED]** — a recorded Platform Owner decision (ADR / N-item / FINAL_DECISIONS).
- **[VERIFIED]** — observed directly in this session from the live Production project,
  the repository working tree, or the deployed configuration.
- **[DOCUMENTED]** — stated by vendor documentation; not proven against this account.
- **[UNVERIFIED]** — capability asserted or assumed but not proven; requires a test.
- **[EXTERNAL]** — depends on a third party or an owner action outside this repository.
- **[BLOCKED]** — cannot be resolved without evidence that does not currently exist.

---

## 1. Mission boundary and stop-condition audit

Phase 0 was executed strictly read-only. The following were **not** performed:

| Prohibited action | Performed? |
|---|---|
| Source code change | No |
| New secret creation / new secret version | No |
| Secret payload read, printed, copied, or logged | No |
| Bunny setting change | No |
| Bunny key-reset endpoint call | No |
| Activation or configuration of library `775315` | No |
| Firestore data write (Production or Staging) | No |
| Firestore Rules / index deployment | No |
| Cloud Functions deployment | No |
| Hosting deployment | No |
| Flutter build / release | No |
| `git commit` / `push` / `reset` / `clean` / `stash` / `checkout` / `discard` | No |
| Overwrite of an existing report | No |

Two stop conditions from the mission brief were triggered and are recorded here
rather than resolved by assumption:

1. **Missing credential** — no account-level Bunny credential exists in Production
   Secret Manager, and the approved N2 premise ("Stream-only sub-user with least
   privilege") is not supported by Bunny's published account model. See §6.2 / §8.
2. **Missing evidence (external)** — Figma integration is not available, so the four
   N8 nodes cannot be inspected. See §9.

A third, pre-existing condition is recorded but was not a hard stop because it
requires no Production mutation to describe: the migration gate "every existing
video resource has a verified library mapping" is unsatisfiable against the current
data (§5.7).

---

## 2. Evidence sources

| Class | Source |
|---|---|
| Approved documents | `docs/notion/00_MASTER_ARCHITECTURE.md` (2.2), `01_Project_Vision.md` (2.2), `02_Product_Requirements__PRD.md` (1.4), `03_UI_UX.md` (1.2), `04_FEATURES.md` (2.0), `docs/notion/FINAL_DECISIONS.md` (2.2) |
| Non-approved documents (read for conflict detection only) | `05 Database 1.8.md` (1.10 Proposed), `06_FIREBASE_ARCHITECTURE .md` (1.4 Draft), `07_FLUTTER_ARCHITECTURE.md` (1.3 Draft), `08_DEVELOPMENT_STANDARDS.md` (1.3 Draft), `09_TASKS .md` (1.3 Draft), `10_Bugs.md`, `11_Assets.md`, `12 AI Prompts.md`, `13_Releases.md`, `14_…Permission_Matrix…md`, `15_Admin_Permissions_Audit_System.md` |
| ADR records | `21_ADR_010_Multi_Library_Bunny_Stream.md` (v1.0 Approved), `21_ADR_010_Amendment_1.md` (Implemented, pending deployment), root `FINAL_DECISIONS.md` (deprecated pointer) |
| Mission reports | `reports/adr010/mission_2`–`mission_11`, `MISSION_16`–`MISSION_24`, `FINAL_*` set (Mission 25 equivalent) |
| Live Production | `gcloud` read-only describes/lists, Firestore read-only aggregate queries |
| Source of truth for behaviour | `functions/src/**` (read), `firestore.rules` (read), `functions/.env` (read, secrets not present in file) |
| Vendor documentation | `bunny.net/docs` (Stream authentication, TUS resumable uploads, account API keys, team permissions, OpenAPI v3 public spec) |

**Mission 26 report does not exist.** The most recent closure set in the repository is
the `FINAL_*` group, which is the Mission 25 output.

---

## 3. Repository state

**[VERIFIED]**

| Item | Value |
|---|---|
| Branch | `ci/ios-staging-codemagic` |
| HEAD | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` |
| Ahead / behind upstream | `0 / 0` |
| Modified tracked files | 34 |
| Staged files | 0 |
| Deleted files | 0 |
| Untracked entries | 33 (103 files, including the entire `reports/adr010/` tree) |
| Merge/rebase in progress | No |
| Commits made in this mission | None |

Existing user work is present in the working tree (34 modified tracked files and the
untracked report tree). It was left untouched. No existing report was overwritten;
all four Phase 0 deliverables are new files.

Divergence from historical reports: none material. Mission 25's report set describes
the same HEAD lineage and the same deployed-function inventory observed here
(83 functions, `APP_CHECK_ENFORCEMENT=false` on all of them). The one difference worth
recording is that Missions 23–25 describe `BUNNY_STREAM_API_KEY` at version 2 as the
remediation target; that is confirmed live (§5.4).

**Existing test status (not re-run in Phase 0).** The last recorded status, from
Mission 25, is: Functions `npm run build` exit 0, full suite 56/56 files with 0 FAIL;
Dashboard `flutter analyze` exit 0, `flutter test` 407 pass / 7 fail, with the failures
confined to `subject_details_test.dart` and `subject_grade_context_sync_test.dart`.
Phase 0 did not execute any test command, so this is historical evidence, not a
current measurement. It is recorded here only so Phase 1 does not start from a false
"green" assumption.

---

## 4. Document status audit

**[VERIFIED]** — read from each document's own header.

| Document | Version | Status | Authoritative for Option C implementation? |
|---|---|---|---|
| `00_MASTER_ARCHITECTURE.md` | 2.2 | Approved | Yes |
| `01_Project_Vision.md` | 2.2 | Approved | Yes |
| `02_Product_Requirements__PRD.md` | 1.4 | Approved | Yes |
| `03_UI_UX.md` | 1.2 | Approved (Feature 01 screens + design tokens only) | Yes, but no video screens exist |
| `04_FEATURES.md` | 2.0 | Approved | Yes |
| `05 Database 1.8.md` | 1.10 | **Proposed — Pending Teacher Database Change Approval** | **No** |
| `06_FIREBASE_ARCHITECTURE .md` | 1.4 | **Draft** | **No** |
| `07_FLUTTER_ARCHITECTURE.md` | 1.3 | **Draft** | **No** |
| `08_DEVELOPMENT_STANDARDS.md` | 1.3 | **Draft** | **No** |
| `09_TASKS .md` | 1.3 | **Draft** | **No** |
| `10_Bugs.md` | 1.3 | Draft | No |
| `11_Assets.md` | 1.3 | Draft | No |
| `12 AI Prompts.md` | — | Draft | No |
| `13_Releases.md` | — | Draft | No |
| `14_…Permission_Matrix…md` | — | Draft | No |
| `15_Admin_Permissions_Audit_System.md` | — | Draft | No |
| `docs/notion/FINAL_DECISIONS.md` | 2.2 | Approved | Yes |
| `21_ADR_010_Multi_Library_Bunny_Stream.md` | 1.0 | Approved (implementation pending) | Yes |
| `21_ADR_010_Amendment_1.md` | — | Implemented (code + tests), pending deployment | Yes, as amendment |
| `FINAL_DECISIONS.md` (repository root) | — | Deprecated pointer | No |

**Consequence for Option C.** The collection that Option C depends on
(`bunny_libraries`) and the per-resource field that Option C depends on
(`lecture_resources.bunny_library_id`) have **no authoritative schema home**, because
`05 Database` is the only database document and it is not Approved. This is a
governance blocker, not a technical one: implementation can be designed, but it cannot
be declared compliant until `05` is approved with the new schema. See
`ADR_010_OPTION_C_DOCUMENT_IMPACT_MATRIX.md` C-02.

---

## 5. Verified Production baseline

### 5.1 Project identity

**[VERIFIED]**

| Item | Value |
|---|---|
| Firebase project (default) | `dr-tarek-platform` |
| Project number | `606744934510` |
| Region | `us-central1` |
| Active gcloud account | `playboyt4@yahoo.com` |
| `.firebaserc` default | `dr-tarek-platform` |
| `.firebaserc` staging alias | `dr-tarek-staging` |
| Runtime service account | `606744934510-compute@developer.gserviceaccount.com` |

The `.firebaserc` default target is **Production**. Any command that omits
`--project` operates on Production. This is the single most dangerous property of the
current tooling state and is why every deployment gate in
`ADR_010_OPTION_C_PRODUCTION_DEPLOYMENT_GATES.md` requires an explicit `--project`
argument.

### 5.2 Deployed Functions inventory

**[VERIFIED]** — 83 deployed functions; `APP_CHECK_ENFORCEMENT` exact value `false`
on 83, `true` on 0, malformed/absent on 0.

Bunny- and video-related deployed callables:

| Callable | Purpose | Secrets bound |
|---|---|---|
| `generateBunnySignedUrl` | Playback signed-URL generation | `BUNNY_TOKEN_KEY` v3, `BUNNY_PLAYBACK_URL_TEMPLATE` v2, `BUNNY_STREAM_API_KEY` v2 |
| `getLectureResources` | Resource listing for a lecture | `BUNNY_TOKEN_KEY` v3, `BUNNY_STORAGE_*` v1, `BUNNY_STREAM_API_KEY` v2 |
| `getSectionDisplayMedia` | Section-level media resolution | `BUNNY_TOKEN_KEY` v3, `BUNNY_STREAM_API_KEY` v2, `BUNNY_PLAYBACK_URL_TEMPLATE` v2 |
| `generateBunnyResourceUrl` | Signed URL for Bunny Storage resources (PDF/attachment) | `BUNNY_TOKEN_KEY` v3, `BUNNY_STORAGE_*` v1 |
| `validateBunnyVideoAssociation` | Confirms a Video ID belongs to a library; issues a receipt | `BUNNY_TOKEN_KEY` v3, `BUNNY_STREAM_API_KEY` v2 |
| `associateBunnyVideoToLibrary` | Writes the verified association | `BUNNY_TOKEN_KEY` v3, `BUNNY_STREAM_API_KEY` v2 |
| `listEligibleBunnyLibraries` | Returns eligible libraries to the Dashboard | **None** (Firestore + env only) |
| `uploadBunnyResource` | Server-side upload proxy for Bunny Storage assets | `BUNNY_STORAGE_*` v1 only |
| `deleteBunnyResource` | Server-side delete for Bunny Storage assets | `BUNNY_STORAGE_*` v1 only |

**[VERIFIED]** `fetchBunnyVideoMeta` exists in `functions/src/index.ts` (L1862) as an
internal helper and is **not** deployed as a callable.

**[VERIFIED]** `listEligibleBunnyLibraries` has no secret binding. It reads the
catalog from Firestore and the activation list from the process environment. It
therefore cannot verify credentials, cannot refresh the catalog, and cannot fail over
to the account API.

### 5.3 Bunny secret inventory (names and versions only)

**[VERIFIED]** — no payload was read.

| Secret | Versions | State |
|---|---|---|
| `BUNNY_STREAM_API_KEY` | 2, 1 | Both `enabled`; v2 is bound to functions; v1 holds a dead value |
| `BUNNY_TOKEN_KEY` | 3, 2, 1 | All `enabled`; v3 bound |
| `BUNNY_PLAYBACK_URL_TEMPLATE` | 2, 1 | Both `enabled`; v2 bound |
| `BUNNY_STORAGE_BASE_URL` | 1 | `enabled` |
| `BUNNY_STORAGE_ZONE_NAME` | 1 | `enabled` |
| `BUNNY_STORAGE_PASSWORD` | 1 | `enabled` |

**Absent:** `BUNNY_ACCOUNT_API_KEY` and `BUNNY_ASSOCIATION_RECEIPT_KEY`. Neither
exists in any state. N2 and N5 are therefore unimplemented at the credential layer,
not merely in code.

### 5.4 Runtime IAM

**[VERIFIED]** — every secret has exactly one binding:

```
roles/secretmanager.secretAccessor
  -> serviceAccount:606744934510-compute@developer.gserviceaccount.com
```

No additional principal, no `secretVersionAdder`, no `secretManagerAdmin`. Functions
can read secret values but cannot create or rotate them. This is correct for Option C
runtime access and must be preserved when a new account credential is added.

### 5.5 Firestore indexes and field configuration

**[VERIFIED]**

| Item | Count / Value |
|---|---|
| Composite indexes | 36 |
| Field configurations | 2 |
| `collectionGroups/__default__/fields/*` | wildcard (default) |
| `collectionGroups/retries/fields/status` | `COLLECTION_GROUP`, ASCENDING |

No index exists for `bunny_libraries` and none is currently required, because the
collection is empty and the catalog read path performs no compound query. Option C's
"list eligible libraries ordered by display name" and "list libraries pending
verification" screens may introduce the first such requirement. That is a gate
condition, not a Phase 0 change.

### 5.6 Firestore Rules — Bunny-relevant surface

**[VERIFIED]**

```
match /bunny_libraries/{libraryId} {
  allow read, write: if false;
}
```

```
match /lecture_resources/{resourceId} {
  allow create: if canManageContent()
    && request.resource.data.get('bunny_library_id', null) == null
    && request.resource.data.get('created_at', null) == request.time;
  ...
}
```

Two consequences:

1. `bunny_libraries` is fully deny-all for clients. The catalog is server-only. Option C
   requires Dashboard library management, which means either (a) all reads/writes go
   through callables, or (b) Rules are opened to `isDoctor()`. Option (a) is consistent
   with the current design and requires no Rules change for the catalog itself.
2. `lecture_resources` create **forces** `bunny_library_id == null`, and update keeps
   the field immutable. A verified association can therefore only be written by the
   backend (Admin SDK bypasses Rules). This is a deliberate, working control and must
   not be relaxed by Option C. Any Option C design that lets a client write
   `bunny_library_id` would break it.

### 5.7 Production data census

**[VERIFIED]** — aggregate counts only; no document values, names, phone numbers, or
emails were read.

| Collection | Documents |
|---|---|
| `users` | 7 |
| `subjects` | 14 |
| `lectures` | 12 |
| `lecture_resources` | 13 |
| `bunny_libraries` | **0** |
| `plans` | 13 |
| `subscriptions` | 22 |
| `system_settings` | 2 |

Video resource breakdown:

| Metric | Value |
|---|---|
| Video resources total | 13 |
| With non-empty `bunny_video_id` | 6 (0 deleted, 6 visible) |
| Without `bunny_video_id` | 7 (1 deleted, 6 visible) |
| With explicit `bunny_library_id` | **0** |
| Distinct lectures touched by the 7 unmapped rows | 6 |
| Unmapped rows with `resource_url` | 0 |
| Unmapped rows with `storage_path` | 0 |
| Unmapped rows with `thumbnail` | 0 |

Observed `lecture_resources` field names:

```
bunny_video_id, created_at, created_by, display_order, duration, is_deleted,
is_visible, lecture_id, resource_type, resource_url, storage_path,
storage_provider, subject_id, thumbnail, title, updated_at, updated_by, visibility
```

Three findings matter for Option C:

1. **`bunny_libraries` is empty in Production.** The catalog that Option C treats as
   the source of truth does not exist as data. Every library, including the current
   Production library `736742`, would have to be registered before the catalog read
   path can return anything. Registration is therefore a **precondition of playback**,
   not a later enhancement — unless the legacy default-library path is retained
   during the transition.
2. **`bunny_library_id` is null on 100% of video rows.** Playback currently resolves
   every video through the legacy default-library path. Option C's per-resource library
   resolution is implemented in code (L1703 / L1768 / L1774) but is **not exercised by
   any Production data**.
3. **`storage_provider` exists in data and in `06` but not in `05`.** It is an
   undocumented field in the only database document, which is itself unapproved. This
   is a pre-existing documentation gap that Option C inherits.

### 5.8 Existing upload implementation and its actual destination

**[VERIFIED]**

- `uploadBunnyResource` / `deleteBunnyResource` operate on **Bunny Storage**
  (`BUNNY_STORAGE_BASE_URL`, `BUNNY_STORAGE_ZONE_NAME`, `BUNNY_STORAGE_PASSWORD`),
  i.e. PDFs, attachments, and thumbnails.
- They bind **no Stream credential**. They cannot create a Stream video, cannot issue
  a TUS signature, and cannot target a Stream library.
- There is therefore **no Stream video upload implementation in Production today.**
  Videos reach Bunny out-of-band (Dashboard upload), and the platform stores the
  resulting `bunny_video_id`.

This is the single largest functional gap between "current state" and Option C, and it
is why N8's upload workflow is not a UI-only item.

### 5.9 Existing Dashboard library catalog

**[VERIFIED]**

- `listEligibleBunnyLibraries` is deployed and callable-gated by
  `requireContentManager`.
- Its data source is `loadEligibleBunnyLibraries(db, process.env)`, i.e. Firestore
  `bunny_libraries` filtered by the emergency list.
- Production `bunny_libraries` is empty, so the callable currently returns an empty
  set.
- There is **no registration, revocation, or verification callable**. The catalog can
  be read but never written by the platform.

Net effect: the Dashboard can ask "which libraries are eligible?" and the answer is
always "none". The catalog read path exists; the write path does not.

### 5.10 Video association and playback chain

**[VERIFIED]** — read from `functions/src/index.ts` and `firestore.rules`.

Association:

1. `validateBunnyVideoAssociation` — `requireContentManager`, format gate, then reads
   **only that library's** Stream API key through the per-library resolver, calls
   `GET https://video.bunnycdn.com/library/{id}/videos/{videoId}` (8s timeout), and
   returns a signed receipt with TTL `BUNNY_VALIDATION_RECEIPT_TTL_SECONDS = 600`
   (10 minutes). Nothing is written.
2. `associateBunnyVideoToLibrary` — verifies the receipt, then writes the association.
3. Receipt signing uses **`BUNNY_TOKEN_KEY`** (`signBunnyAssociationReceipt`, L5157).
   `BUNNY_ASSOCIATION_RECEIPT_KEY` is not referenced anywhere.

Playback:

1. `generateBunnySignedUrl` resolves `resource.bunny_library_id` (L1703 / L1768 /
   L1774); when absent it falls back to `DEFAULT_BUNNY_LIBRARY_ID`.
2. The per-library secret resolver derives `BUNNY_<libraryId>_STREAM_API_KEY` and
   `BUNNY_<libraryId>_TOKEN_KEY`, with a **60 000 ms** cache
   (`BUNNY_SECRET_CACHE_TTL_MS = 60_000`) and a legacy-fallback flag
   (`BUNNY_LEGACY_LIBRARY_FALLBACK`).
3. Signed URL default TTL is **3600 s** (L1790), consistent with `07`'s "1 hour".
   Storage-resource URLs default to **300 s** (`buildBunnyResourceAccessUrl`).

Consequences for Option C:

- The **library-resolution and per-library-credential machinery already exists and is
  in production**. Option C is not a green-field build; it is a completion of an
  existing read path plus a missing write path.
- N5 is **not** implemented: receipt integrity is coupled to `BUNNY_TOKEN_KEY`, a key
  that is also used for CDN token signing. Rotating the token key invalidates in-flight
  receipts. This is exactly the coupling N5 exists to remove.
- N9 is **not** implemented: no daily verification job, no alert channel.
- The emergency list is implemented as an **intersection/allow-list over catalog rows**
  (`if (denyList && !denyList.has(option.libraryId)) continue;`). It can only reduce
  eligibility and never grant it — which is the *security* behaviour N6 requires — but
  the variable name `BUNNY_ACTIVE_LIBRARY_IDS` and the "deny list" wording describe the
  opposite mental model. This is a naming/documentation defect, not a security defect.
  See `ADR_010_OPTION_C_DOCUMENT_IMPACT_MATRIX.md` C-09.

### 5.11 Environment configuration

**[VERIFIED]** — `functions/.env` contains no secret values.

| Variable | Value |
|---|---|
| `APP_CHECK_ENFORCEMENT` | `false` |
| `BUNNY_STREAM_LIBRARY_ID` | `736742` (resolves to `BUNNY_DEFAULT_LIBRARY_ID`) |
| `BUNNY_DEFAULT_LIBRARY_ID` | unset |
| `BUNNY_LEGACY_LIBRARY_FALLBACK` | unset |
| `BUNNY_ACTIVE_LIBRARY_IDS` | unset |

Because `BUNNY_ACTIVE_LIBRARY_IDS` is unset, the emergency list is **not engaged**
(`null`, not an empty set). Because `BUNNY_ACTIVE_LIBRARY_IDS` is unset and
`bunny_libraries` is empty, the only reason playback works today is the
`isDefault` bypass in the registry — not the catalog.

### 5.12 Registry state

**[VERIFIED]** — `bunny_library_registry.ts` contains a hardcoded definition for
`775315` using `BUNNY_775315_*` variable names. It is inert because `775315` is not
listed in `BUNNY_ACTIVE_LIBRARY_IDS`, and the variable is unset. The default library is
always treated as active via `isDefault`, bypassing the activation list.

This satisfies N10 today ("`775315` remains deferred and inactive") but only by
configuration, not by code. If anyone sets `BUNNY_ACTIVE_LIBRARY_IDS`, the default
library is still active regardless — which is the opposite of what N6 intends for an
emergency kill switch.

---

## 6. Approved decision record (N1–N12)

Recorded verbatim from the Platform Owner's approval. Classification follows the
mission requirement to separate approved decisions from verified facts, unverified
capabilities, external prerequisites, and blocked items.

> **N1** — Server-managed library catalog.
> **N2** — Account-level API credential stored in Secret Manager, using a Stream-only sub-user with least privilege.
> **N3** — Use ReadOnlyApiKey for read operations where supported.
> **N4** — Backend may enable CDN Token Authentication only for libraries registered through the platform and after the documented ownership and safety checks.
> **N5** — Dedicated `BUNNY_ASSOCIATION_RECEIPT_KEY`, with a 10-minute dual-verification transition.
> **N6** — `BUNNY_ACTIVE_LIBRARY_IDS` is an emergency deny list only. It can reduce eligibility, never grant eligibility.
> **N7** — Protected Dashboard workflow with masked one-time token-key fallback only when automatic retrieval is not proven.
> **N8** — Figma scope includes library picker, registration/management, fallback credential input, and upload workflow as specified in Mission 8.
> **N9** — Daily verification job and an approved alert channel.
> **N10** — `775315` remediation is deferred. Keep it inactive.
> **N11** — The platform must not create Bunny libraries.
> **N12** — During Account API unavailability, existing playback may use valid cached catalog and credentials until their defined validity expires. New provisioning must fail closed.

### 6.1 Decision status matrix

| # | Class | Current implementation state | Blocker |
|---|---|---|---|
| N1 | **[APPROVED]** | Read path implemented (`bunny_library_catalog.ts`, `_reader.ts`, `listEligibleBunnyLibraries`); write path absent; collection empty | `05` not Approved (schema home); no registration callable |
| N2 | **[APPROVED] + [BLOCKED]** | Not implemented; no `BUNNY_ACCOUNT_API_KEY` exists | Documented Bunny model has no per-library sub-user API key; account key is full access |
| N3 | **[APPROVED] + [UNVERIFIED]** | Not implemented | `ReadOnlyApiKey` usability for every required read endpoint is unproven |
| N4 | **[APPROVED] + [DOCUMENTED]** | Not implemented | `PlayerTokenAuthenticationEnabled` is writable via Update Video Library; not proven on this account |
| N5 | **[APPROVED]** | **Not implemented** — receipts signed with `BUNNY_TOKEN_KEY` | Requires new secret + dual-verify code path |
| N6 | **[APPROVED]** | Implemented as allow-list intersection; default library bypasses it; variable name says "active" | Naming/doc conflict; default-bypass decision needed |
| N7 | **[APPROVED]** | Not implemented (no UI) | Blocked by N8 Figma access |
| N8 | **[APPROVED]** | Not implemented | **Figma unavailable** — 4 nodes cannot be inspected |
| N9 | **[APPROVED]** | Not implemented | Needs scheduler + alert channel selection (external) |
| N10 | **[APPROVED]** | Satisfied by configuration only; hardcoded registry entry remains | Code-level guarantee deferred |
| N11 | **[APPROVED] + [VERIFIED]** | Satisfied — no library-creation endpoint exists in source | None |
| N12 | **[APPROVED]** | Partially: secret cache 60 s; no defined catalog validity window | "Defined validity" is undefined — needs a decision |

### 6.2 The N2 problem, stated precisely

**[DOCUMENTED]** Bunny's published model:

- The account API key is described as granting full access to the account
  ("Your API key lets you programmatically update your zones and account settings").
- Team permissions are **dashboard** permissions and are coarse. "Manage zones" is a
  single permission covering *all* CDN pull zones, storage zones, DNS zones, **and
  Stream libraries**.
- No documentation describes a per-library sub-user API key, nor a scoped key that is
  limited to one Stream library.
- `ScopedApiKey` and `Subuser*` appear in the OpenAPI specification **only** as
  authentication-scheme names on operations. No endpoint is documented that creates a
  scoped or sub-user key.

**[VERIFIED]** No code in `functions/src` calls the account API (`api.bunny.net`). The
only Bunny host contacted is `video.bunnycdn.com`, and only for
`GET /library/{id}/videos/{videoId}`.

**Therefore N2, as written, cannot be implemented from documented capability.** Three
resolutions exist and only the Platform Owner can choose:

| Option | Meaning | Consequence |
|---|---|---|
| N2-a | Store the **full-access account key** in Secret Manager, restricted by IAM to the runtime service account | Works, but violates the "least privilege" intent: the key can create/delete libraries and zones |
| N2-b | **Drop account-API automation.** No discovery, no automatic key retrieval, no automatic token-auth enablement. Libraries are registered manually (N7 fallback path becomes the primary path) | Preserves least privilege; N4 becomes manual; N9 verification limited to what a library key can prove |
| N2-c | **Ask Bunny support** to confirm whether a Stream-only scoped key exists and how to create it | Blocks N2 until answered; may unblock N2-a/N3 cleanly |

Phase 0 does **not** choose. This is recorded as blocker **B-01**.

### 6.3 Decision-level gaps that are not yet decisions

Three items are load-bearing for Option C and are **not** covered by N1–N12. They are
recorded here so they are not silently decided during implementation:

| Gap | Why it matters | Needed decision |
|---|---|---|
| G-01 — Default-library bypass of the emergency list | The default library is always active. An emergency kill switch that cannot disable the default library does not kill anything. | Make the default subject to the activation list, or explicitly exempt it and document the residual risk |
| G-02 — Catalog "defined validity" for N12 | N12 permits cached catalog and credentials "until their defined validity expires", but no validity window is defined anywhere | Set an explicit catalog staleness threshold and a credential cache policy |
| G-03 — Whether `lecture_resources.bunny_library_id` is required or optional | Rules force it to `null` on create; 0 rows carry it; playback falls back to the default | Decide whether Option C makes it mandatory (migration required) or keeps the fallback indefinitely |

---

## 7. Critical technical unknowns

These are recorded as unknowns. None is assumed to be true anywhere in this report.

| ID | Unknown | Current evidence |
|---|---|---|
| U-01 | Does Bunny return the Stream API key **unmasked** through `GET /videolibrary/{id}`? | **[DOCUMENTED]** `VideoLibraryModel.ApiKey` is `string \| null`. Masking behaviour is unspecified. **[UNVERIFIED]** |
| U-02 | Is `ZoneSecurityKey` available in clear text via the pull-zone API? | **[DOCUMENTED]** `PullZoneModel.ZoneSecurityKey` = "The security key used for secure URL token authentication", nullable. **[UNVERIFIED]** |
| U-03 | Does `ZoneSecurityKey` equal the Stream library's Token Authentication key? | **[DOCUMENTED]** The library model has **no** token-key field; the pull-zone model does. Whether they are the same secret is undocumented. **[UNVERIFIED]** |
| U-04 | Does the selected Stream-only sub-user scope support every required endpoint? | **[BLOCKED]** No such scope is documented (§6.2). Depends on B-01. |
| U-05 | Is there a secure browser-to-Bunny upload path without exposing a library API key? | **[DOCUMENTED]** TUS presigned upload: server computes `SHA256(libraryId + apiKey + expire + videoId)`, client uploads to `https://video.bunnycdn.com/tusupload`. Requires Create Video first, which requires the library key server-side. **[UNVERIFIED]** end-to-end |
| U-06 | Is a server-side upload proxy necessary? | **[UNVERIFIED]** — depends on U-05, file-size limits, and Cloud Functions request limits |
| U-07 | Can the receipt-key transition support old in-flight receipts? | **[VERIFIED]** current TTL is 600 s and signing uses `BUNNY_TOKEN_KEY`. A 10-minute dual-verify window is therefore **exactly** the receipt lifetime — feasible, but only if the verifier tries both keys for the full window |

Full test protocol for each unknown — environment, credential, pass/fail, fallback —
is in `ADR_010_OPTION_C_DEPENDENCY_AND_PHASE_PLAN.md` §6.

---

## 8. External prerequisites

| ID | Prerequisite | Owner | Blocking |
|---|---|---|---|
| E-01 | Decision on B-01 (N2 resolution: full-access key / no account API / ask Bunny) | Platform Owner | N2, N3, N4, N7 |
| E-02 | A **dedicated test Stream library** for the Mission 9 capability test (must not be `736742` and must not be `775315`) | Platform Owner | U-01…U-06 |
| E-03 | Confirmation that `775315` stays inactive and is not configured | Platform Owner | N10 (already satisfied; needs continued enforcement) |
| E-04 | Figma access or an exported spec for nodes `58011:1024`, `58335:1444`, `871:1074`, `58171:1964` | Platform Owner | N7, N8, all Dashboard UI |
| E-05 | Approved alert channel for N9 (email / Slack / other) and its credential | Platform Owner | N9 |
| E-06 | Approval of `05 Database` including `bunny_libraries` and `bunny_library_id` | Platform Owner (Teacher Database Change Approval) | N1, G-03 |
| E-07 | Decision on the default-library bypass (G-01) | Platform Owner | N6 completeness |
| E-08 | Decision on catalog/credential validity windows (G-02) | Platform Owner | N12 completeness |

---

## 9. Figma availability — BLOCKED

**[VERIFIED]**

| Check | Result |
|---|---|
| MCP servers / resources / templates | 0 |
| Figma tool in the tool catalog | None |
| `FIGMA_TOKEN` / `FIGMA_API_TOKEN` / `FIGMA_PERSONAL_ACCESS_TOKEN` | Not present |
| Browser session | A logged-in `dash.bunny.net` tab exists; no Figma tab |

None of the four required nodes (`58011:1024`, `58335:1444`, `871:1074`,
`58171:1964`) could be inspected. No UI specification has been invented.

**Exact access required (either one):**

1. A Figma personal access token with `file_read` scope on the design file, exposed to
   this environment as `FIGMA_TOKEN`; **or**
2. A read-only share link per node plus an export (PNG at 2× and the node's spec
   panel), delivered as files in the repository or an accessible URL.

**What will be read when access exists:** frame names, layer hierarchy, spacing,
typography tokens, component states (default/hover/focus/disabled/error), copy strings,
empty/loading/error states, and responsive breakpoints for each of the four nodes. Until
then, all Dashboard UI workstreams are blocked.

---

## 10. Baseline gap register

| ID | Gap | Severity | Evidence |
|---|---|---|---|
| B-01 | N2 is not implementable as written (§6.2) | Critical | Bunny docs + no account-API code |
| B-02 | No dedicated test library for the capability test | Critical | `775315` deferred, `736742` prohibited |
| B-03 | Figma unavailable (4 nodes) | High | No MCP/token/tool |
| B-04 | `05 Database` unapproved; no schema home for `bunny_libraries` | High | Document status |
| B-05 | `bunny_libraries` empty in Production (0 docs) | High | Census |
| B-06 | No registration / revocation / verification callable | High | Source scan |
| B-07 | N5 unimplemented; receipts coupled to `BUNNY_TOKEN_KEY` | High | L5157 |
| B-08 | N9 unimplemented; no verification job, no alert channel | Medium | Source scan |
| B-09 | No Stream video upload path at all | High | `uploadBunnyResource` binds Storage only |
| B-10 | Default library bypasses the emergency list (G-01) | Medium | Registry `isDefault` |
| B-11 | `BUNNY_ACTIVE_LIBRARY_IDS` naming contradicts its semantics | Low | `parseBunnyEmergencyDenyList` |
| B-12 | 7/13 video rows have no `bunny_video_id`; 6 visible | Medium | Census |
| B-13 | 0/13 video rows have `bunny_library_id` | Medium | Census |
| B-14 | `storage_provider` undocumented in `05` | Low | Field present in data |
| B-15 | `BUNNY_STREAM_API_KEY` v1 still enabled with a dead value | Low | Secret versions |
| B-16 | `.firebaserc` default is Production | Medium (operational) | `.firebaserc` |
| B-17 | N12 "defined validity" is undefined (G-02) | Medium | No policy |
| B-18 | N11 satisfied only by absence of code, not by policy | Low | No create endpoint |

---

## 11. Phase 0 conclusion

Option C is **architecturally compatible with the current system** in the read
direction: the catalog read path, the per-library secret resolver, the per-resource
library resolution, and the deny-list semantics all exist in Production today. What
does not exist is the **write and lifecycle half**: catalog registration, revocation,
verification, receipt-key separation, account-credential access, upload, and UI.

Four items must be resolved by the Platform Owner before any implementation work can
be planned with confidence: **B-01** (N2), **B-02** (test library), **B-03** (Figma),
**B-04** (database approval). Everything else is engineering work with a known shape.

Phase 1 has **not** been started.

---

## 12. Non-mutation attestation

No code, Production resource, Bunny setting, secret, Firestore data, or deployment was
changed during Phase 0. The only files created are the four Phase 0 reports in
`reports/adr010/`. All Production inspection used read-only list/describe/aggregate
operations. No secret payload was read, printed, copied, or logged.
