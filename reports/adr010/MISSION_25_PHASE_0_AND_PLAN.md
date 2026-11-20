# Mission 25 — Phase 0 State Verification and Execution Plan

**Date:** 2026-11-19
**Projects:** `dr-tarek-platform` (606744934510) · `dr-tarek-staging` (13159003436)
**Mode:** read-only (this document contains no writes)
**Prepared by:** incoming engineer (continuation of the interrupted Phase 1)

No secret value appears in this document. Secret **names** only.

---

## 1. Repository state (read-only)

| Item | Observed |
| --- | --- |
| `HEAD` | `34a4b76 fix(ios): harden FCM token registration …` (no new commits) |
| Working tree | 33 modified + 33 untracked (the ADR-010 implementation, unchanged by Phase 0) |
| New since the last report | nothing: `verifyBunnyLibrary` still contains the broken `GET video.bunnycdn.com/library/{id}` call (index.ts:8069 → `PlayerTokenAuthenticationEnabled`), so the interrupted Phase 1 had **not** started editing code |
| `21_ADR_010_Amendment_3.md` | absent |
| `reports/adr010/` | 77 documents, no Mission 25 file before this one |
| Action taken | none (no commit / reset / stash / clean) |

## 2. Google Cloud / Firebase state

| Item | Production | Staging |
| --- | --- | --- |
| Secrets | `BUNNY_STREAM_API_KEY` (v1,v2 enabled), `BUNNY_TOKEN_KEY` (v1,v2,v3), `BUNNY_PLAYBACK_URL_TEMPLATE` (v1,v2), `BUNNY_STORAGE_*` (v1 each) | same set plus **`BUNNY_780700_STREAM_API_KEY`** (v1) and **`BUNNY_780700_TOKEN_KEY`** (v1) — created by the interrupted run |
| Secret accessor | `606744934510-compute@…` on every secret | `13159003436-compute@…` on every secret (incl. the two new ones) |
| `bunny_libraries` documents | **0** | **1** (`780700`) — hand-written: no `created_at`, no `admin_audit_log` row, `token_auth_verified: true` set manually |
| Catalog callables deployed | **none** (`registerBunnyLibrary`, `verifyBunnyLibrary`, `listBunnyLibraryHealth` absent) | deployed (81 functions total) |
| Function env | `APP_CHECK_ENFORCEMENT=false`, `BUNNY_STREAM_LIBRARY_ID=736742` | `APP_CHECK_ENFORCEMENT=false`, `BUNNY_DEFAULT_LIBRARY_ID=780700`, `BUNNY_STREAM_LIBRARY_ID=780700`, `BUNNY_ACTIVE_LIBRARY_IDS=780700` |
| Last function update | — | `2026-11-16T11:27:05Z` (before the interrupted Phase 1) |
| Temporary IAM (`roles/iam.serviceAccountTokenCreator` for `playboyt4@yahoo.com`) | **absent** | **absent** on every service account (all four SA policies were empty) |
| Project-level access | `playboyt4@yahoo.com` = `roles/owner` (pre-existing) | same |

## 3. "Found vs required" table

| # | Required (Mission 25 plan) | Found | Gap / action |
| --- | --- | --- | --- |
| 1 | No uncommitted drift from the interrupted run | 33M/33?? = the ADR-010 implementation; `verifyBunnyLibrary` untouched | none — nothing to revert |
| 2 | `verifyBunnyLibrary` fixed (Decision 4) | **not fixed** (`PlayerTokenAuthenticationEnabled`, probe without Referer) | **Phase 1.1** (done in this run) |
| 3 | `token_auth_mode` in the catalog | absent from code and documents | **Phase 1.1** (done in this run) |
| 4 | Per-library secrets on Staging | `BUNNY_780700_*` exist; `BUNNY_775315_*` absent | **Phase 1.2** — added `BUNNY_775315_STREAM_API_KEY` (unsigned → no token key) |
| 5 | Staging catalog registered through the audited path | one hand-written row, no audit trail | **Phase 1.3** — row replaced via `registerBunnyLibrary` + `verifyBunnyLibrary` |
| 6 | Temporary IAM removed | never present (the interrupted run's disclosed binding is not in the policy) | nothing to remove; verified by name (§4 below) |
| 7 | Temporary secret files deleted | `D:\Temp\opencode\bunny_secrets\` had **11 files** (8 keys + probes) | **Phase 1.5** — files and directory removed; 0 key-shaped strings remain anywhere under `D:\Temp\opencode` |
| 8 | Production untouched | production catalog empty, production functions unchanged, `BUNNY_ACTIVE_LIBRARY_IDS` unset | maintained throughout |
| 9 | Referer gate (Decision 3) | unverified at the previous stop | **verified read-only** (§4) |
| 10 | Production association rows | 14 `video` rows, **0** with `bunny_library_id`; 6 with a video id; 8 without (incl. one deleted) | matches the diagnosis; Phase 4 input |

## 4. Decision-3 gate (read-only CDN probes, status codes only)

Probes used real video ids resolved from `lecture_resources` and a Stream list call, and the platform's
fixed Referer (`lib/core/constants/bunny_playback_headers.dart` → `https://dr-tarek-platform.web.app/`).

| Library | Pull zone | Unsigned URL, no Referer | Unsigned URL with platform Referer |
| --- | --- | --- | --- |
| 775315 | `vz-c850a9e1-eb4.b-cdn.net` | **403** | **200** |
| 776525 | `vz-a9e3d4cc-384.b-cdn.net` | **403** | **200** |
| 736742 (control) | `vz-c6abe953-876.b-cdn.net` | **403** (token auth enforced) | prerequisite: signed only |

Additional Referer variants on 775315 (`dashboard…web.app`, `localhost:5000`, `drtarek.com`) all returned
**200**, confirming `AllowedReferrers = []` + `BlockNoneReferrer = true` (any non-empty Referer is accepted).

**Gate result: PASS.** An unsigned URL works for the new platform because every client already sends a
non-empty Referer (native via the fixed header, web via its own origin). No Bunny change is required, so the
`unsigned` design can proceed without Owner intervention.

## 5. Execution plan (phases and gates)

| Phase | Content | Gate |
| --- | --- | --- |
| 1 | `verifyBunnyLibrary` fix + `token_auth_mode` + unit tests; Staging secrets; audited registration of `780700` (signed) and `775315` (unsigned); IAM cleanup; temp-file cleanup | stop after the report |
| 2 | `21_ADR_010_Amendment_3.md` (Proposed) + `05 Database` v1.9 + `06 Firebase Architecture` updates | **mandatory stop until the Owner approves** |
| 3 | Code: no silent default library, `playback_host`-derived template, signed/unsigned playback, `discoverBunnyVideoLibrary`, `migrateBunnyLibraryAssociations`, `COLLECTION_GROUP` index, dashboard picker, client messaging, dead-code removal, tests | after Amendment 3 approval |
| 4 | Production catalog functions, verified registration of 3 libraries, `BUNNY_ACTIVE_LIBRARY_IDS`, backup, dry-run then apply migration, `BUNNY_LEGACY_LIBRARY_FALLBACK=false` | **stop before apply** |
| 5 | Real playback per library, regression checks, logs review | final report |

Invariants for every phase: no Bunny writes, no secret printed, Staging before Production, idempotent
production writes with a JSON backup under `D:\Temp\opencode\backups\adr010\<stamp>\`.
