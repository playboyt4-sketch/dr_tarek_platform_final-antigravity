# ADR-010 Option C — Document Impact Matrix (Phase 0)

Status: Phase 0 deliverable — analysis only. **No document was edited.**
Date: 2026-11-17
Companion documents:
`ADR_010_OPTION_C_IMPLEMENTATION_BASELINE.md`,
`ADR_010_OPTION_C_DEPENDENCY_AND_PHASE_PLAN.md`,
`ADR_010_OPTION_C_PRODUCTION_DEPLOYMENT_GATES.md`

Scope: identify which documents must change for ADR-010 Option C, why, in what order,
and which existing approved statements Option C contradicts.

Rule applied: only documents marked **Approved** are authoritative. Where an approved
document contradicts Option C, the conflict is reported rather than resolved — Phase 0
does not amend approved documents.

---

## 1. Summary

| Verdict | Count | Documents |
|---|---|---|
| Must change, and is **Approved** (requires a formal amendment) | 4 | `00`, `04`, `03`, `FINAL_DECISIONS` |
| Must change, but is **not Approved** (safe to revise before approval) | 7 | `05`, `06`, `07`, `08`, `09`, `11`, `13` |
| Must be extended (ADR records) | 2 | ADR-010, ADR-010 Amendment 1 |
| No change required | 4 | `01`, `02`, `10`, `12` |
| Optional / low priority | 2 | `14`, `15` |

**Hard governance blocker:** `05 Database` is the only schema document and it is
`Proposed — Pending Teacher Database Change Approval`. Option C introduces a new
collection (`bunny_libraries`) and a new per-resource field usage
(`lecture_resources.bunny_library_id`). Neither has an authoritative home until `05` is
approved.

---

## 2. Per-document matrix

Legend for "Gate": which deployment gate (from
`ADR_010_OPTION_C_PRODUCTION_DEPLOYMENT_GATES.md`) is blocked until the document is
updated.

### 2.1 `00_MASTER_ARCHITECTURE.md`

| Field | Value |
|---|---|
| Version / Status | 2.2 / **Approved** |
| Current Bunny content | L67 "Bunny CDN" in the technology list; L221 "Bunny CDN is used for video delivery." |
| Option C gap | Architecture is written for one video provider with one library. No catalog, no multi-library identity, no per-library credential model. The ADR registry (L161–L211) lists ADR-004, ADR-005, ADR-009 only — **ADR-010 is not registered**. |
| Required update | (a) Add ADR-010 to the ADR registry with status, date, and one-paragraph summary. (b) Extend §3 to state that video delivery is multi-library with a server-managed catalog, and that library identity is a backend concern. (c) State that no Bunny library is created by the platform (N11). |
| Conflict | C-07 (registry omission — not a contradiction, an omission) |
| Priority | High — the registry is how future work discovers the decision |
| Gate | None directly; required before Gate 2 (Functions) for governance completeness |

### 2.2 `01_Project_Vision.md`

| Field | Value |
|---|---|
| Version / Status | 2.2 / **Approved** |
| Current Bunny content | 0 mentions |
| Option C gap | None. Vision is provider-agnostic. |
| Required update | **None.** |
| Priority | — |

### 2.3 `02_Product_Requirements__PRD.md`

| Field | Value |
|---|---|
| Version / Status | 1.4 / **Approved** |
| Current Bunny content | L695 "Bunny CDN for video delivery."; L2975 "Bunny CDN is used for secure video delivery."; L2999 technology list |
| Option C gap | No requirement covers library selection, registration, or multi-library playback. Requirements are silent, not contradictory. |
| Required update | **Optional.** Add one non-functional requirement: "Video delivery must support multiple Stream libraries resolved server-side, without exposing library identity or credentials to clients." |
| Conflict | None |
| Priority | Low |

### 2.4 `03_UI_UX.md`

| Field | Value |
|---|---|
| Version / Status | 1.2 / **Approved**, but explicitly limited to Feature 01 screens plus the design-token and component-state contract |
| Current Bunny content | **0 mentions** |
| Option C gap | N8 requires four UI surfaces (library picker, registration/management, fallback credential input, upload workflow). None is specified. `03` cannot be cited as authority for them. |
| Required update | Add the four surfaces after Figma nodes `58011:1024`, `58335:1444`, `871:1074`, `58171:1964` are inspected. Must cover: default/hover/focus/disabled/error states, empty catalog state, pending-verification state, credential-fallback state, upload progress/failure states, and RTL copy. |
| Conflict | C-11 — `03` is Approved but does not describe any video screen; treating it as complete would force UI invention, which the mission forbids |
| Priority | Critical for N7/N8 |
| Gate | Gate 5 (Dashboard Hosting) |
| Status | **[BLOCKED]** — Figma unavailable (B-03) |

### 2.5 `04_FEATURES.md`

| Field | Value |
|---|---|
| Version / Status | 2.0 / **Approved** |
| Current Bunny content | **0 mentions.** Feature 04 "Lecture" (L443) and Feature 05 "Video Player" (L730) describe playback without naming a provider or library. |
| Option C gap | Feature 05 assumes a single video identity. There is no concept of "which library", no registration flow, no upload flow, and no per-library playback failure mode. |
| Required update | (a) Feature 05: add the library dimension — playback resolves the library server-side, and a video belongs to exactly one library. (b) New Feature (or a sub-flow of Feature 04/05) for **library registration and management**, actor Doctor, with the N7 fallback credential path. (c) New sub-flow for **video upload** with library selection. |
| Conflict | C-12 |
| Priority | High — Feature documents drive acceptance tests |
| Gate | Gate 2 and Gate 5 |

### 2.6 `05 Database 1.8.md`

| Field | Value |
|---|---|
| Version / Status | 1.10 / **Proposed — Pending Teacher Database Change Approval** |
| Current Bunny content | **0 mentions.** `lecture_resources` (L466) documents only: Lecture ID, Resource Type, Resource URL, Thumbnail, Duration, Visibility. No `bunny_video_id`, no `bunny_library_id`, no `storage_provider`. There is **no `bunny_libraries` collection anywhere** in the document. |
| Option C gap | The entire Option C data model is undocumented. |
| Required update | (a) Document `bunny_libraries/{libraryId}` with the fields the code already expects: `library_id`, `display_name`, `status`, `pull_zone_id`, `playback_host`, `token_auth_enabled`, `token_auth_verified`, `credential_refs{stream_api_key,token_key}`, `source`, `last_verified_at`, `last_error_code`. (b) Document `lecture_resources.bunny_video_id`, `bunny_library_id`, `storage_provider`. (c) State that `bunny_library_id` is immutable after create and written only by the backend. (d) State that `bunny_libraries` is never client-readable. |
| Conflict | **C-02** — see §3 |
| Priority | **Critical** — blocks N1 |
| Gate | Gate 3 (indexes) and Gate 4 (Rules) both depend on the schema being approved |

### 2.7 `06_FIREBASE_ARCHITECTURE .md`

| Field | Value |
|---|---|
| Version / Status | 1.4 / **Draft** |
| Current Bunny content | 17 lines. §6.4 "Bunny CDN — Signed URL Generation" (L215); callable named `generateSignedVideoUrl` taking `video_id` (L221); flow at L226; L339 marks the token-signing question "Resolved" |
| Option C gap | §6.4 describes a single-library, video-id-addressed callable. Production has `generateBunnySignedUrl` addressed by **resource**, resolving library per resource. No catalog, no registration, no per-library credentials, no receipt key. |
| Required update | (a) Rename/realign §6.4 to `generateBunnySignedUrl` with the real input contract. (b) Add a §6.x for the library catalog, per-library secret resolution, and the emergency list. (c) Add the association receipt lifecycle and the dedicated receipt key (N5). (d) Document the account-credential access model once B-01 is decided. (e) Correct the "Resolved" checkbox at L339 to reference the real callable. |
| Conflict | **C-03** |
| Priority | High |
| Gate | Gate 2 |

### 2.8 `07_FLUTTER_ARCHITECTURE.md`

| Field | Value |
|---|---|
| Version / Status | 1.3 / **Draft** |
| Current Bunny content | 16 lines. §16 "Video Player Architecture (Bunny CDN)" (L463); `GetSignedVideoUrlUseCase` (L478); "calls Cloud Function: `getSignedVideoUrl`" (L498); "Generates Bunny CDN signed URL (expires in 1 hour)" (L503); "Signed URLs expire after 1 hour" (L568) |
| Option C gap | Client names a callable that does not exist (`getSignedVideoUrl`), with an input contract that does not exist. No library selection, no upload client, no per-library error handling. |
| Required update | (a) Align the data-source call to `generateBunnySignedUrl` with the real request/response shape. (b) Confirm the 3600 s expiry (matches code) and state it explicitly as the contract. (c) Add the upload client design: TUS resumable upload, presigned signature obtained from a callable, no key material in the client. (d) Add library-selection state to the admin authoring flow. |
| Conflict | **C-04** |
| Priority | High |
| Gate | Gate 6 (Flutter release) |

### 2.9 `08_DEVELOPMENT_STANDARDS.md`

| Field | Value |
|---|---|
| Version / Status | 1.3 / **Draft** |
| Current Bunny content | 0 mentions |
| Option C gap | No standard for: secret naming (`BUNNY_<libraryId>_STREAM_API_KEY`), secret-per-library provisioning, credential handling in callables, or receipt signing. Option C multiplies the number of secrets, so a naming/provisioning standard is needed. |
| Required update | Add a short section: per-library secret naming convention, the rule that library keys never leave the server, the rule that a callable may read only the credential of the library it is acting on, and the receipt-signing key separation. |
| Priority | Medium |
| Gate | Gate 1 (Secret Manager) — the naming standard must exist before secrets are created |

### 2.10 `09_TASKS .md`

| Field | Value |
|---|---|
| Version / Status | 1.3 / **Draft** |
| Current Bunny content | 6 lines. T-000.7 (L34); T-000.9 (L36) "Dashboard inputs Video ID only"; T-CF.8 (L87) `generateBunnySignedUrl`; L141 open question "Confirm Bunny CDN Signed URL expiry duration (suggested: 5 minutes per request)" |
| Option C gap | T-000.9 encodes the pre-Option-C model. L141 is an unresolved question that contradicts both `07` (1 hour) and the code (3600 s). |
| Required update | (a) Close L141: expiry is 3600 s for video, 300 s for storage resources — record as decided. (b) Rewrite T-000.9 to include library selection and catalog registration. (c) Add tasks for the 16 workstreams in the dependency plan. |
| Conflict | **C-05** (expiry) |
| Priority | Medium |
| Gate | None directly; the task list drives Phase 1–5 |

### 2.11 `10_Bugs.md`

| Field | Value |
|---|---|
| Version / Status | 1.3 / Draft |
| Current Bunny content | 1 line (L149, a category label) |
| Required update | **None** in Phase 0. Bug entries will be added as defects are found. |

### 2.12 `11_Assets.md`

| Field | Value |
|---|---|
| Version / Status | 1.3 / Draft |
| Current Bunny content | 11 lines. §4.3 "Bunny CDN Assets (Video)" (L198); L354 "Videos (Bunny CDN): Versioning handled by Bunny CDN; platform stores only `video_id`." |
| Option C gap | "platform stores only `video_id`" is no longer sufficient: the platform must also store **which library** the video belongs to. |
| Required update | Amend §4.3 and L354 to state that the platform stores `bunny_video_id` **and** `bunny_library_id`, and that library identity is server-resolved. Add the catalog as an asset-inventory source. |
| Conflict | **C-06** |
| Priority | Medium |

### 2.13 `12 AI Prompts.md`

| Field | Value |
|---|---|
| Current Bunny content | 1 line (L171, a data-layer category) |
| Required update | **None.** |

### 2.14 `13_Releases.md`

| Field | Value |
|---|---|
| Version / Status | Draft |
| Current Bunny content | 4 lines. L193 "Bunny CDN integration tested (signed URL generation, quality tiers)"; L356 "Bunny CDN Signed URL Integration (T-000.9)"; L500 environment matrix row "Bunny CDN \| Test library \| Test library \| Production library" |
| Option C gap | The release checklist tests one library. The environment matrix implies one library per environment. Option C is multi-library in every environment. |
| Required update | (a) Add a multi-library regression item (playback across ≥2 registered libraries). (b) Update the environment matrix to "Test libraries (≥2) \| Test libraries (≥2) \| Registered libraries". (c) Add catalog registration/revocation to the release checklist. |
| Priority | Medium |
| Gate | Gate 6 |

### 2.15 `14_Platform_Availability_Feature_Matrix_Permission_Matrix_Audit_System.md`

| Field | Value |
|---|---|
| Version / Status | Draft |
| Current Bunny content | 2 lines. L45 "Video Player"; §"Video & Media" L86–L103 defines `video.access`, `video.preview_duration`, `video.quality.max`, etc. |
| Option C gap | The feature matrix has a rich video capability model but **no library dimension and no admin-side capability** for library management or upload. `video.quality.max` assumes the platform controls quality tiers per library; with multiple libraries, max quality becomes a property of the library, not only of the plan. |
| Required update | (a) Add admin capabilities: `video.library.manage`, `video.upload`. (b) State the effective quality = min(plan max, library max). |
| Conflict | **C-08** (permission side) |
| Priority | Low–Medium |

### 2.16 `15_Admin_Permissions_Audit_System.md`

| Field | Value |
|---|---|
| Version / Status | Draft |
| Current Bunny content | 1 line (L92, `ADMIN_CONTENT` description) |
| Relevant content | L130: "Upload video (enter video_id) \| `ADMIN_CONTENT` \| Video file uploaded to Bunny CDN separately" |
| Option C gap | L130 defines video handling as "enter a video_id; upload happens elsewhere". Option C introduces in-platform upload with library selection, and library registration is a higher-privilege action than content editing. |
| Required update | (a) Replace L130 with two rows: "Associate verified video to lecture" (`ADMIN_CONTENT`) and "Upload video to a registered library" (`ADMIN_CONTENT`, new capability). (b) Add "Register / revoke Bunny library" as **Doctor only**. (c) Add "Enter fallback token key (one-time, masked)" as **Doctor only**. |
| Conflict | **C-08** |
| Priority | Medium |
| Gate | Gate 4 (Rules) and Gate 5 (Dashboard) — the permission model must be fixed before either ships |

### 2.17 `FINAL_DECISIONS.md` (`docs/notion/`, v2.2 Approved)

| Field | Value |
|---|---|
| Current Bunny content | 7 lines. §4 "Bunny CDN" (L49): "Dashboard: إدخال Video ID فقط" (Dashboard: enter Video ID only); signed URL via Cloud Function; student never sees the raw link; quality tiers from the plan; Dashboard inputs Video ID only. §15 (L150) dual storage provider; L167 "Video files remain Bunny-only (per FINAL_DECISIONS Section 4 — unchanged)". |
| Option C gap | §4 states that the Dashboard's only video action is entering a Video ID. Option C requires library registration, library selection, and in-platform upload. These are directly contradictory. |
| Required update | Amend §4 with an explicit Option C addendum: the Dashboard may register libraries, select a library for a video, and upload a video to a registered library; the platform never creates libraries; students never see library identity or raw URLs. Keep the existing guarantees (signed URL via Cloud Function, no raw URL exposure, plan-based quality). |
| Conflict | **C-01** — the most significant approved-document conflict |
| Priority | **Critical** |
| Gate | Gate 5 (Dashboard) — cannot ship a Dashboard library screen that contradicts an Approved decision |

### 2.18 `21_ADR_010_Multi_Library_Bunny_Stream.md` (v1.0 Approved)

| Field | Value |
|---|---|
| Current content | Records Option selection and guarantees. Its "Open Items" still require configuring library `775315`. |
| Option C gap | (a) The ADR does not record which option (A/B/C) was approved. (b) The Open Items entry for `775315` contradicts N10 ("deferred, keep inactive"). (c) N1–N12 are not part of the ADR text; they live only in a Mission 8 report. |
| Required update | Publish **ADR-010 Amendment 2**: record Option C as the approved option; incorporate N1–N12 as normative decisions; supersede the `775315` Open Item with the N10 deferral; add the catalog and receipt-key decisions. Do not restate or weaken existing guarantees. |
| Conflict | **C-09** (Open Items vs N10) |
| Priority | **Critical** — this is the record of authority |
| Gate | Gate 0 (governance) — precedes every technical gate |

### 2.19 `21_ADR_010_Amendment_1.md` (Implemented, pending deployment)

| Field | Value |
|---|---|
| Current content | `BUNNY_DEFAULT_LIBRARY_ID`, identity-split warning, client `--dart-define` default; §Consequences notes that making the default subject to the activation list is a separate decision. |
| Option C gap | That "separate decision" is now load-bearing (G-01). |
| Required update | Cross-reference Amendment 2 and record the G-01 resolution once decided. |
| Conflict | **C-10** |
| Priority | High |
| Gate | Gate 2 |

---

## 3. Conflict register

Each conflict states the exact documents, the exact rule, the consequence, and a
proposed resolution. **No resolution is applied in Phase 0.**

### C-01 — `FINAL_DECISIONS` §4 "Video ID only" vs Option C library management and upload

| Field | Detail |
|---|---|
| Documents | `docs/notion/FINAL_DECISIONS.md` §4 (Approved, v2.2) vs ADR-010 Option C + N1, N7, N8 |
| Exact rule | §4: "Dashboard: إدخال Video ID فقط" — the Dashboard's video action is entering a Video ID. |
| Consequence | Any Dashboard screen that registers a library, picks a library, or uploads a file contradicts an Approved decision. Shipping one without amending §4 creates an approved-document violation, which is exactly the class of defect ADR governance exists to prevent. |
| Proposed resolution | Amend §4 with a scoped addendum for Option C (see §2.17). Preserve all existing guarantees verbatim. Record the amendment as a versioned change in `FINAL_DECISIONS`'s version history. |
| Blocks | Gate 5, N7, N8 |
| Owner action | Approve the §4 amendment text |

### C-02 — `05 Database` has no schema for `bunny_libraries` or `bunny_library_id`

| Field | Detail |
|---|---|
| Documents | `05 Database 1.8.md` (Proposed 1.10) vs ADR-010 Option C + N1 |
| Exact rule | `lecture_resources` documents six fields; none is a Bunny identifier. No `bunny_libraries` collection is documented. |
| Consequence | The catalog is the source of truth for Option C, but it has no approved schema. `firestore.rules` already enforces `bunny_libraries` deny-all and `lecture_resources.bunny_library_id == null` on create — i.e. the code is ahead of the documentation. Approval of `05` is a prerequisite for declaring the implementation compliant. |
| Proposed resolution | Add the catalog and field definitions to `05` (see §2.6), then obtain the Teacher Database Change Approval. Do not deploy Rules or indexes referencing these fields before approval. |
| Blocks | Gate 3, Gate 4, N1 |
| Owner action | Approve `05` with the new schema |

### C-03 — `06` §6.4 callable name and contract do not match Production

| Field | Detail |
|---|---|
| Documents | `06_FIREBASE_ARCHITECTURE .md` §6.4 (Draft) vs `functions/src/index.ts` |
| Exact rule | `06` L221: callable `generateSignedVideoUrl`, "Receives `video_id`". Production: `generateBunnySignedUrl`, addressed by resource, resolving `bunny_library_id`. |
| Consequence | A developer following `06` would build a client call against a non-existent function. `06` L339 additionally marks the token-signing question "Resolved" against the wrong callable name. |
| Proposed resolution | Rewrite §6.4 against the real contract; keep `06` as Draft until rewritten, and do not treat it as authoritative in the meantime. |
| Blocks | Gate 2 |
| Owner action | None (draft document; engineering owns the rewrite) |

### C-04 — `07` §16 client calls a non-existent callable

| Field | Detail |
|---|---|
| Documents | `07_FLUTTER_ARCHITECTURE.md` §16 (Draft) vs Production |
| Exact rule | `07` L478 `GetSignedVideoUrlUseCase`; L498 "calls Cloud Function: `getSignedVideoUrl`"; L503/L568 "expires after 1 hour". |
| Consequence | The expiry statement is **correct** (code default 3600 s) but the callable name and the input contract are wrong. A client built to `07` fails at the first playback attempt. |
| Proposed resolution | Align names and contract; keep the 1-hour expiry as the documented contract; add upload and library-selection client design. |
| Blocks | Gate 6 |
| Owner action | None (draft document) |

### C-05 — Signed-URL expiry is stated three different ways

| Field | Detail |
|---|---|
| Documents | `09_TASKS .md` L141 (open question, "suggested 5 minutes") vs `07` L503/L568 ("1 hour") vs code (3600 s video / 300 s storage) |
| Exact rule | Three sources, three numbers; one is still an open question. |
| Consequence | Ambiguity in a security-relevant parameter. The code is the only unambiguous source today. |
| Proposed resolution | Record the decision: video 3600 s, storage resources 300 s. Close L141. Cite the constants in `06` and `07`. |
| Blocks | None directly; documentation quality |
| Owner action | Confirm the expiry values (recommended: keep current code values) |

### C-06 — `11_Assets` says the platform stores "only `video_id`"

| Field | Detail |
|---|---|
| Documents | `11_Assets.md` L354 (Draft) vs Option C data model |
| Exact rule | "platform stores only `video_id`". |
| Consequence | With multiple libraries, a bare `video_id` is ambiguous. Storage of library identity is required for correct playback and for revocation. |
| Proposed resolution | Amend to `bunny_video_id` + `bunny_library_id`. |
| Blocks | None |
| Owner action | None |

### C-07 — `00_MASTER_ARCHITECTURE` ADR registry omits ADR-010

| Field | Detail |
|---|---|
| Documents | `00_MASTER_ARCHITECTURE.md` §ADR registry (Approved) |
| Exact rule | Registry lists ADR-004, ADR-005, ADR-009. ADR-010 exists as a separate Approved file but is not registered. |
| Consequence | Future contributors and audits that rely on `00` will not discover ADR-010. This is an omission, not a contradiction. |
| Proposed resolution | Add ADR-010 (and Amendment 1) to the registry; state that Option C is the approved option once Amendment 2 exists. |
| Blocks | None |
| Owner action | Approve the registry edit |

### C-08 — Permission model has no library management or upload capability

| Field | Detail |
|---|---|
| Documents | `15` L130 ("Upload video (enter video_id) \| `ADMIN_CONTENT` \| Video file uploaded to Bunny CDN separately") and `14` §Video & Media, vs N7/N8 |
| Exact rule | Video handling is "enter an id"; upload is out of band; no admin capability exists for library management. |
| Consequence | Option C's registration and fallback-credential screens have no permission definition. If implemented ad hoc, a content admin could gain library-registration power, which is a privilege escalation. |
| Proposed resolution | Split the permission: association and upload stay `ADMIN_CONTENT`; registration/revocation and fallback token entry are **Doctor only**. |
| Blocks | Gate 4, Gate 5 |
| Owner action | Approve the permission split |

### C-09 — ADR-010 Open Items still require configuring `775315`

| Field | Detail |
|---|---|
| Documents | `21_ADR_010_Multi_Library_Bunny_Stream.md` Open Items (Approved) vs N10 |
| Exact rule | Open Items require configuring `775315`; N10 says remediation is deferred and the library stays inactive. |
| Consequence | The Approved ADR instructs an action the Owner has since deferred. Leaving both in force is an internal contradiction in the approved set. |
| Proposed resolution | Amendment 2 supersedes the Open Item with the N10 deferral and records the three unplayable videos as a known, accepted limitation. |
| Blocks | Gate 2 governance |
| Owner action | Approve Amendment 2 |

### C-10 — Amendment 1 defers the default-library activation question

| Field | Detail |
|---|---|
| Documents | `21_ADR_010_Amendment_1.md` §Consequences vs N6 |
| Exact rule | Amendment 1 notes that making the default library subject to the activation list is "a separate decision". N6 requires that the emergency list can reduce eligibility — including for the default library. |
| Consequence | An emergency kill switch that cannot disable the default library is not a complete kill switch. |
| Proposed resolution | Decide G-01 explicitly: either the default library is subject to the list (requires removing the `isDefault` bypass), or it is exempt and the residual risk is documented and accepted. |
| Blocks | Gate 2 |
| Owner action | Choose the G-01 resolution |

### C-11 — `03_UI_UX` is Approved but contains no video or library screens

| Field | Detail |
|---|---|
| Documents | `03_UI_UX.md` 1.2 (Approved, Feature 01 scope only) vs N8 |
| Exact rule | `03` covers Feature 01 screens plus the design-token contract. It contains zero Bunny mentions. |
| Consequence | There is no approved UI authority for the four required surfaces. Implementing without one means inventing UI, which the mission forbids. |
| Proposed resolution | Obtain Figma access (B-03), then add the four surfaces to `03` and approve them. |
| Blocks | N7, N8, Gate 5 |
| Owner action | Provide Figma access/export |

### C-12 — `04_FEATURES` Feature 05 has no library dimension

| Field | Detail |
|---|---|
| Documents | `04_FEATURES.md` 2.0 (Approved), Feature 04 / Feature 05 vs Option C |
| Exact rule | Playback is described without provider or library identity; there is no registration or upload feature. |
| Consequence | Acceptance criteria for Option C cannot be derived from the Approved feature set. |
| Proposed resolution | Add the library dimension to Feature 05 and add the registration/upload sub-flows (§2.5). |
| Blocks | Gate 2, Gate 5 |
| Owner action | Approve the feature additions |

### C-13 — `lecture_resources.bunny_library_id` is null-by-construction but Option C requires it

| Field | Detail |
|---|---|
| Documents | `firestore.rules` (create forces `bunny_library_id == null`), Production data (0/13 rows carry it), Option C (per-resource library resolution) |
| Exact rule | Rules forbid a client from setting `bunny_library_id`; the backend may set it. In practice no row has it, so playback always falls back to the default library. |
| Consequence | Option C's per-resource resolution is implemented but unexercised. The migration gate "every video has a verified library mapping" cannot pass today (7/13 rows lack `bunny_video_id` entirely). |
| Proposed resolution | Backfill `bunny_library_id` only for rows with a verified `bunny_video_id` (6 rows), and decide the fate of the 7 unmapped rows (1 deleted, 6 visible with no video identity at all) before requiring completeness. Do **not** make the field mandatory until the data supports it. |
| Blocks | Gate 2 migration, Gate 3 |
| Owner action | Approve the backfill scope and the handling of the 7 unmapped rows |

---

## 4. Required document update sequence

The order matters because several documents cite each other.

| Order | Document | Action | Precondition |
|---|---|---|---|
| 1 | ADR-010 Amendment 2 | Record Option C + N1–N12; supersede the `775315` Open Item | Owner approval |
| 2 | `00` ADR registry | Register ADR-010 | Amendment 2 published |
| 3 | `FINAL_DECISIONS` §4 | Option C addendum | Owner approval |
| 4 | `05 Database` | Catalog + field schema, then Teacher Database Change Approval | Schema text ready |
| 5 | `15` / `14` permissions | Split registration vs association/upload | Owner approval |
| 6 | `04_FEATURES` | Library dimension + registration/upload features | Owner approval |
| 7 | `06` §6.4 | Real callable contract + catalog/receipt sections | Draft rewrite |
| 8 | `07` §16 | Real callable + upload client | Draft rewrite |
| 9 | `08` | Secret naming and handling standard | Draft rewrite |
| 10 | `09` | Close expiry question; add Option C tasks | Draft rewrite |
| 11 | `11` | `video_id` + `library_id` | Draft rewrite |
| 12 | `13` | Multi-library release checklist | Draft rewrite |
| 13 | `03` | Four UI surfaces | **Blocked on Figma** |

Documents 1–6 are governance; 7–13 are engineering documentation. Gate 0 of the
deployment plan requires 1–6.

---

## 5. Documents explicitly **not** to be changed for Option C

| Document | Reason |
|---|---|
| `01_Project_Vision.md` | Provider-agnostic; no Bunny content |
| `02_Product_Requirements__PRD.md` | Silent on library topology; an optional NFR is sufficient and non-blocking |
| `10_Bugs.md` | Bug log, not specification |
| `12 AI Prompts.md` | Prompt library, not specification |
| Root `FINAL_DECISIONS.md` | Deprecated pointer; must not be resurrected as an authority |

---

## 6. Phase 0 attestation

No document in `docs/notion/` or at the repository root was modified. Every conflict
above is reported as found, with its exact location, and left unresolved for the
Platform Owner.
