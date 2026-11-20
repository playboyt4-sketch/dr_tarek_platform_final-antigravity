# ADR-010 Option C — Current-State Revalidation (Phase 1)

Status: Phase 1 deliverable — revalidation only. No implementation, no deployment,
no document edit, no repository mutation.
Date: 2026-11-17
Supersedes nothing. Complements the four Phase 0 reports, which remain unmodified.

Method: re-read the four Phase 0 reports, re-inspected the repository, re-ran every
read-only Production query that Phase 0 relied on, and additionally inspected **Staging**
(which Phase 0 did not cover). Every claim below is tagged:

- **[VERIFIED]** — observed in this session.
- **[HISTORICAL]** — from a prior report; not re-measured.
- **[NEW]** — not present in Phase 0.
- **[CORRECTED]** — Phase 0 stated it differently.
- **[UNVERIFIED]** — asserted but not proven.
- **[BLOCKED]** — cannot be resolved with current access.

---

## 1. Repository state

**[VERIFIED]**

| Item | Phase 0 | Now | Delta |
|---|---|---|---|
| Branch | `ci/ios-staging-codemagic` | same | none |
| HEAD | `34a4b763e77087e0eeffd4aa8ad88bb820b61d46` | same | none |
| HEAD commit date | — | 2026-11-09T22:55:19+02:00 | — |
| Ahead / behind upstream | 0 / 0 | 0 / 0 | none |
| Modified tracked files | 34 | 34 | none |
| Staged files | 0 | 0 | none |
| Deleted files | 0 | 0 | none |
| Untracked files | 103 | 107 | **+4 = the four Phase 0 reports** |
| Commits made | 0 | 0 | none |

Newest mtime among modified tracked files is `firestore.indexes.json` at
2026-11-17T18:20:45, i.e. **before** the Phase 0 reports were written (19:13–19:16).
No tracked file was touched after Phase 0.

**Conclusion: no code or configuration change has occurred since Phase 0.** The working
tree is byte-identical in content to the Phase 0 baseline; the only additions are the
four reports.

### 1.1 Phase 0 report integrity

**[VERIFIED]** — all four present, sizes and hashes as created, not modified:

| Report | Size | SHA-256 (first 16) | Headings |
|---|---|---|---|
| `ADR_010_OPTION_C_IMPLEMENTATION_BASELINE.md` | 33 852 | `130B63BE8DB86C4B` | 13 |
| `ADR_010_OPTION_C_DOCUMENT_IMPACT_MATRIX.md` | 29 070 | `F00E3CE793E4FF5A` | 7 |
| `ADR_010_OPTION_C_DEPENDENCY_AND_PHASE_PLAN.md` | 22 228 | `F7EE3AF2F4B0937D` | 11 |
| `ADR_010_OPTION_C_PRODUCTION_DEPLOYMENT_GATES.md` | 18 559 | `1253D48748CB9276` | 12 |

No report was overwritten. `docs/notion` shows 0 modifications.

---

## 2. Production baseline — re-verified

Every Phase 0 Production measurement was re-run. **All values are unchanged.**

| Item | Phase 0 | Now | Status |
|---|---|---|---|
| Project / number / region | `dr-tarek-platform` / `606744934510` / `us-central1` | same | confirmed |
| Deployed functions | 83 | 83 | confirmed |
| `APP_CHECK_ENFORCEMENT` | false=83, true=0, malformed=0 | false=83, true=0, malformed=0 | confirmed |
| Newest function update | 2026-11-17T16:18:21Z | 2026-11-17T16:18:21Z | confirmed (no deploy since) |
| Secrets | 6 names | 6 names | confirmed |
| `BUNNY_ACCOUNT_API_KEY` | absent | absent | confirmed |
| `BUNNY_ASSOCIATION_RECEIPT_KEY` | absent | absent | confirmed |
| `BUNNY_STREAM_API_KEY` versions | 2 enabled, 1 enabled | 2 enabled, 1 enabled | confirmed |
| Secret IAM | 1 `secretAccessor` binding each, compute SA only | same | confirmed |
| Composite indexes | 36 | 36 | confirmed |
| Field configurations | 2 | 2 | confirmed |
| `bunny_libraries` docs | 0 | 0 | confirmed |
| `bunny_libraries` rules | `allow read, write: if false` | same | confirmed |
| `lecture_resources` create gate | `bunny_library_id == null` forced | same | confirmed |
| Census (users/subjects/lectures/resources/plans/subs/settings) | 7/14/12/13/13/22/2 | same | confirmed |
| Video resources | 13 total, 6 with `bunny_video_id`, 7 without, 0 with `bunny_library_id` | same | confirmed |
| 7 unmapped rows | 1 deleted, 6 visible, 6 distinct lectures, no URL/path/thumbnail | same | confirmed |
| `functions/.env` | `APP_CHECK_ENFORCEMENT=false`, `BUNNY_STREAM_LIBRARY_ID=736742`, others unset | same | confirmed |

Production is in exactly the state Phase 0 described. Nothing drifted.

---

## 3. Corrections to the Phase 0 reports

Three Phase 0 statements were imprecise. Recorded here rather than silently editing the
Phase 0 reports.

| # | Phase 0 said | Actual | Impact |
|---|---|---|---|
| K-01 | `uploadBunnyResource` / `deleteBunnyResource` are bound to `BUNNY_STORAGE_*` **only** | Both also bind `BUNNY_TOKEN_KEY` v3 (plus the three storage secrets) | Cosmetic; does not change the conclusion that neither can touch Stream video. Correct in Phase 5 planning. |
| K-02 | Several draft documents listed as version 1.3 | Actual: `10_Bugs` 1.0, `11_Assets` 1.2, `12` 1.1, `13` 1.1, `14` 1.1, `15` 1.1 (all Draft); `05` 1.10 Proposed; `06`/`07`/`08`/`09` 1.3 Draft | None on the approval status — all remain non-authoritative. |
| K-03 | 33 untracked entries / 103 files | 107 files now = 103 + the 4 reports | Expected; confirms no other new files. |

---

## 4. New findings — Staging

Phase 0 inspected Production only. Staging reveals that **part of Option C has already
been exercised manually**, which materially changes the Phase 4 plan.

### 4.1 Staging project state

**[VERIFIED]** — `dr-tarek-staging`

| Item | Value |
|---|---|
| Deployed functions | 76 |
| `APP_CHECK_ENFORCEMENT` | false=75, true=0, **malformed=1** |
| Secrets | 8 |
| `bunny_libraries` documents | **1** |
| Census | users 2, subjects 1, lectures 3, `lecture_resources` 2, plans 1, subscriptions 1, `system_settings` 0 |

### 4.2 The Staging catalog document already exists

**[NEW]** `bunny_libraries/780700` exists with fields:

```
credential_refs, display_name, last_error_code, last_verified_at, library_id,
playback_host, pull_zone_id, source, status, token_auth_enabled, token_auth_verified
```

This is exactly the `BunnyCatalogEntry` contract implemented in
`functions/src/core/video/bunny_library_catalog.ts`. The catalog **shape is proven**;
what is missing is an authorized, audited, deployed write path.

### 4.3 Staging per-library credentials exist

**[NEW]** Staging secrets include:

| Secret | Version | State |
|---|---|---|
| `BUNNY_780700_STREAM_API_KEY` | 1 | enabled |
| `BUNNY_780700_TOKEN_KEY` | 1 | enabled |
| `BUNNY_STREAM_API_KEY` | 2 enabled, 1 **destroyed** | — |
| `BUNNY_TOKEN_KEY` | 1 | enabled |
| `BUNNY_PLAYBACK_URL_TEMPLATE`, `BUNNY_STORAGE_*` | 1 each | enabled |

This proves the `BUNNY_<libraryId>_*` naming convention from
`bunny_library_secret_resolver.ts` is already in use in a real environment. Production
still has **zero** per-library secrets.

Note the asymmetry: Staging destroyed its `BUNNY_STREAM_API_KEY` v1; Production keeps a
dead v1 `enabled`. Production cleanup remains a separate, unapproved action.

### 4.4 Staging data is already library-mapped

**[NEW]**

| Metric | Staging | Production |
|---|---|---|
| Video resources | 2 | 13 |
| With `bunny_video_id` | 2 | 6 |
| With `bunny_library_id` | **2** (both `780700`) | **0** |

Staging `lecture_resources` also carries `id` and `section_id` fields that Production
rows do not show. Staging is therefore the only place where per-resource library
resolution is exercised at all.

### 4.5 Staging environment variables

**[NEW]** — `generateBunnySignedUrl` in Staging:

| Variable | Value |
|---|---|
| `BUNNY_DEFAULT_LIBRARY_ID` | `780700` |
| `BUNNY_ACTIVE_LIBRARY_IDS` | `780700` |
| `BUNNY_STREAM_LIBRARY_ID` | `780700` |
| `BUNNY_LEGACY_LIBRARY_FALLBACK` | unset |

Because the emergency list is **engaged** in Staging with exactly one id, Staging is a
usable environment for testing N6 behaviour (set it to an empty/mismatched value and the
library must become ineligible). Production has it unset, so Production currently
cannot demonstrate the kill switch.

### 4.6 Staging hygiene findings

| ID | Finding | Severity |
|---|---|---|
| H-01 | `onPasswordResetRequest` has `APP_CHECK_ENFORCEMENT=''` (empty, not `false`), last updated 2026-10-15 | Low — Staging only; Production is exact `false` on 83/83 |
| H-02 | `getVideoWatchWindow` carries **plain environment variables** named `BUNNY_TOKEN_KEY`, `BUNNY_STREAM_API_KEY`, etc., all with length 0 (empty placeholders), not secret mounts | Low — empty values, no leak; but a naming pattern that should not be copied |
| H-03 | 7 Production functions are absent from Staging: `onLectureAccessGrantWritten`, `deleteBunnyResource`, `submitExamAttempt`, `onSectionWritten`, `onLectureResourceWritten`, `uploadBunnyResource`, `onLectureWritten` | Medium — Staging cannot fully validate upload/delete or those triggers |

H-03 matters directly for Phase 7: `uploadBunnyResource` and `deleteBunnyResource` are
**not deployed in Staging**, so upload testing cannot run there until they are deployed
as part of an approved Staging gate.

### 4.7 `775315` remains untouched

**[VERIFIED]** No secret matching `775315` exists in either project. The library is
defined but inert in `bunny_library_registry.ts` (L162–166) and absent from both
`BUNNY_ACTIVE_LIBRARY_IDS` values. N10 is satisfied.

Its live Bunny-side state cannot be verified read-only without an account credential,
which does not exist.

---

## 5. Documentation status — re-verified

**[VERIFIED]** — unchanged from Phase 0, with the version corrections in K-02.

| Document | Version | Status |
|---|---|---|
| `00_MASTER_ARCHITECTURE` | 2.2 | **Approved** |
| `01_Project_Vision` | 2.2 | **Approved** |
| `02_Product_Requirements__PRD` | 1.4 | **Approved** |
| `03_UI_UX` | 1.2 | **Approved** (Feature 01 screens + design tokens only) |
| `04_FEATURES` | 2.0 | **Approved** |
| `05 Database 1.8` | 1.10 | **Proposed** — Pending Teacher Database Change Approval |
| `06_FIREBASE_ARCHITECTURE` | 1.4 | Draft |
| `07_FLUTTER_ARCHITECTURE` | 1.3 | Draft |
| `08_DEVELOPMENT_STANDARDS` | 1.3 | Draft |
| `09_TASKS` | 1.3 | Draft |
| `10_Bugs` | 1.0 | Draft |
| `11_Assets` | 1.2 | Draft |
| `12 AI Prompts` | 1.1 | Draft |
| `13_Releases` | 1.1 | Draft |
| `14_Platform_Availability…` | 1.1 | Draft |
| `15_Admin_Permissions…` | 1.1 | Draft |
| `FINAL_DECISIONS` | 2.2 | **Approved** |

No document changed status. The governance blockers of Phase 0 stand unchanged.

---

## 6. Source-code state — re-verified

**[VERIFIED]** — HEAD unchanged, so the Phase 0 code findings hold. Spot-checked again:

| Check | Result |
|---|---|
| Bunny callables in source | `generateBunnySignedUrl` (L4541), `validateBunnyVideoAssociation` (L5056), `associateBunnyVideoToLibrary` (L5186), `listEligibleBunnyLibraries` (L7802), `uploadBunnyResource` (L8477), `deleteBunnyResource` (L8529), `generateBunnyResourceUrl` (L8560) |
| Registration / revocation / verification callables | **NONE** |
| `BUNNY_ASSOCIATION_RECEIPT_KEY` / `BUNNY_ACCOUNT_API_KEY` references | **NONE** |
| `uploadBunnyResource` secrets | `BUNNY_TOKEN_KEY` + `BUNNY_STORAGE_BASE_URL` + `BUNNY_STORAGE_ZONE_NAME` + `BUNNY_STORAGE_PASSWORD` — **no Stream credential**, Storage only |
| Migration helpers | `bunny_library_migration.ts` exports `validateBunnyLibraryMapping`, `planBunnyLibraryBackfill`, `resolveBunnyLibraryBackfillMode`, `evaluateBunnyLibraryBackfillWrite`, `buildBunnyLibraryBackfillBackup` — **implemented but exposed by no callable** |

**[NEW]** The migration module already contains a full backfill planner, validator, and
backup builder. Phase 5 backfill does not need to invent this logic; it needs an
authorized entry point and an approved migration decision (C-13).

---

## 7. Figma — still BLOCKED

**[VERIFIED]** — re-checked in this session:

| Check | Result |
|---|---|
| MCP servers / resources / templates | 0 |
| Figma tool in catalog | none |
| Browser tabs | `dash.bunny.net/account/api-key`, dead `127.0.0.1:8080` (502) |

Nodes `58011:1024`, `58335:1444`, `871:1074`, `58171:1964` remain uninspected. No UI
was invented. E-04 is unchanged and still blocks Phase 6.

---

## 8. Blocker and decision register — current status

| ID | Item | Status now | Changed since Phase 0? |
|---|---|---|---|
| B-01 / E-01 | N2 account-credential strategy | **Open** — needs owner decision (A / B / C) | No |
| B-02 / E-02 | Dedicated test library | **Partially resolved by evidence** — Staging `780700` is isolated, has its own pull zone, its own secrets, its own Firebase project, and a proven catalog document. Whether it is *authorized* as the test library is an owner decision. | **New evidence** |
| E-03 | `775315` deferred | Satisfied | No |
| B-03 / E-04 | Figma | **Blocked** | No |
| E-05 | Alert channel | **Open** | No |
| B-04 / E-06 | `05` schema approval | **Open** | No |
| E-07 | Emergency-list semantics / default bypass | **Open** | No (Staging now provides a test bed) |
| E-08 | Catalog validity windows | **Open** | No |
| B-05 | Production catalog empty | Unchanged (0 docs) | No |
| B-06 | No registration callables | Unchanged | No |
| B-07 | Receipt key absent | Unchanged | No |
| B-08 | No verification job | Unchanged | No |
| B-09 | No Stream upload | Unchanged | No |

---

## 9. What the Staging evidence changes about the plan

Three planning consequences, none of which authorize work:

1. **Phase 4 is smaller than Phase 0 assumed.** The catalog data model, the
   `BUNNY_<id>_*` credential convention, and per-resource library resolution have all
   been exercised in Staging. Phase 4 is about turning a manual/admin-SDK write into an
   authorized, audited, deployed callable path — not about proving the model.
2. **Staging can host the N6 and G-01 tests immediately** (the emergency list is engaged
   there). It cannot host upload tests until `uploadBunnyResource` /
   `deleteBunnyResource` are deployed there (H-03).
3. **E-02 can likely be closed cheaply.** If the Owner authorizes `780700` as the
   dedicated test library, U-01…U-04 and U-06 can run without provisioning anything new.
   `780700` is isolated from Production by library, pull zone, secrets, and project, and
   it is not `736742` and not `775315`. It does contain 3 test lectures / 2 videos, so
   destructive capability tests must be limited to new test assets. **This remains an
   owner decision, not an assumption.**

---

## 10. Attestation

No source code, authoritative document, Firebase resource, Bunny resource, secret, IAM
policy, Firestore document, or deployment target was modified in Phase 1. All
inspection was read-only list/describe/aggregate. No secret payload was read or printed.
The only file created is this report.
