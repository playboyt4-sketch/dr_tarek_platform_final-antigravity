# ADR-010 Option C — Final Completion Report

Status: **PARTIALLY COMPLETE — Staging delivered and validated; Production not authorized;
Figma UI blocked.**
Date: 2026-11-18
Branch: `ci/ios-staging-codemagic`, HEAD `34a4b763e77087e0eeffd4aa8ad88bb820b61d46`
Commits made by this mission: **none**.

This report states exactly what was delivered, what was verified, and what was **not**. It
does not use "complete" for anything that has not been executed and observed.

---

## 1. What was delivered

### 1.1 Governance (Phase 2 items A-E, approved)

| Item | Artifact | State |
|---|---|---|
| A | `21_ADR_010_Amendment_2.md` (N1-N12, contracts, supersessions) | Published; status refresh added 2026-11-18 |
| B | `00` ADR register — ADR-010 status "Amended by Amendment 2", v1.1 changelog | Applied |
| C | `05 Database 1.8.md` → v1.11 **Approved**: `bunny_libraries`, `lecture_resources` Bunny fields, `admin_audit_log` | Applied |
| D | `14`/`15` permissions: `bunny_library_*` actions, Doctor-only, audit vocabulary | Applied |
| E | Cross-document alignment in `04`, `06`, `07`, `08`, `09`, `11`, `13`, `FINAL_DECISIONS` §4 | Applied |

Decision values recorded in `09_TASKS` v1.4: video signed URL **3600 s**, Bunny Storage
**300 s**, association receipt **600 s**. The earlier 5-minute suggestion for video was
explicitly **not** adopted.

### 1.2 Backend implementation

| Artifact | Purpose |
|---|---|
| `functions/src/core/video/bunny_library_lifecycle.ts` (326 lines, new) | Pure registration plan, status state machine, verification-write mapping, audit payload, N5 receipt-key resolution. No I/O. |
| `functions/src/index.ts` (+417 / −6 lines) | Five new callables + helpers + receipt-key rotation |
| `registerBunnyLibrary` | Doctor-only; always writes `pending_verification`; `create()` so a duplicate can never overwrite |
| `deactivateBunnyLibrary` | Doctor-only; deactivation always wins |
| `reactivateBunnyLibrary` | Doctor-only; returns to `pending_verification`, never straight to `active` |
| `verifyBunnyLibrary` | Doctor-triggered on-demand probe; reads only that library's own secrets; never returns them |
| `listBunnyLibraryHealth` | Doctor-only projection: id, name, status, two token flags, timestamp, typed code |
| N5 receipt rotation | `BUNNY_ASSOCIATION_RECEIPT_KEY` optional; when bound it signs, and the verifier accepts both it and `BUNNY_TOKEN_KEY` |

### 1.3 Tests

| Suite | Result |
|---|---|
| `functions/test/bunny_library_lifecycle.test.js` (new, pure) | **77 assertions passed** |
| `functions/test/bunny_library_lifecycle_flow.test.js` (new, emulator) | **49 assertions passed** |
| `functions/test/bunny_library_association.test.js` | 37 assertions passed |
| `functions test:pure` (whole pure suite) | **0 failures**, all sub-suites passed |
| `npm --prefix functions test` (firestore + functions + auth emulators) | **58/58 files passed** |
| `security-tests/rules.test.js` + `adr010_association_rules.test.js` | **passed** (association rules: 21 assertions) |
| `flutter analyze` (dashboard) | No issues found |
| `flutter analyze` (app) | No issues found (775 s) |
| `flutter test` (dashboard) | **407 passed / 7 failed** — byte-identical to the pre-existing baseline (`subject_details_test.dart`, `subject_grade_context_sync_test.dart`) |

The 7 Dashboard failures are **pre-existing and unrelated**; no new failure was introduced.

### 1.4 Staging deployment (executed)

`dr-tarek-staging` only. 7 functions: 5 created, 2 updated. Deploy exited 0.

| Check | Result |
|---|---|
| Function count | 76 → **81** |
| State | all 7 `ACTIVE` |
| New revisions | `registerbunnylibrary-00001-xab`, `deactivatebunnylibrary-00001-guj`, `reactivatebunnylibrary-00001-yop`, `verifybunnylibrary-00001-zil`, `listbunnylibraryhealth-00001-bux`, `validatebunnyvideoassociation-00003-qub`, `associatebunnyvideotolibrary-00003-cax` |
| `APP_CHECK_ENFORCEMENT` (all 81) | **80 explicit `false`, 1 unset (`onPasswordResetRequest`, pre-existing), 0 `true`** |
| Secret mounts on the 5 new callables | **none** |
| Secret mounts on the 2 updated | unchanged (`BUNNY_TOKEN_KEY:1`, `BUNNY_STREAM_API_KEY:2`) |
| Unauthenticated POST to each new endpoint | **HTTP 401** on all 5 (not 404) |
| Deployed bundle vs working tree | `src/index.ts` 10,052 lines and the lifecycle module are **byte-identical** to the working tree |
| Firestore writes during deployment/validation | **none** |

V6-V10 (live Doctor-identity functional checks) were **not executed** — no Doctor test
credential exists in this environment. They are recorded as gaps, not as passes. The logic
they would exercise is covered end-to-end on the emulator by the flow suites.

---

## 2. Production state (unchanged by this mission)

| Item | Value |
|---|---|
| Functions | **83** (the 5 lifecycle callables are absent) |
| Secrets | 6 — no `BUNNY_ASSOCIATION_RECEIPT_KEY`, no `BUNNY_ACCOUNT_API_KEY` |
| Composite indexes | **36** |
| `bunny_libraries` documents | **0** |
| `lecture_resources` | 13 (13 video, 6 with `bunny_video_id`, **0** with `bunny_library_id`) |
| Visible / deleted video rows | 12 / 1 |
| `APP_CHECK_ENFORCEMENT` (sampled) | `false` |
| Default library | `BUNNY_STREAM_LIBRARY_ID=736742` |

**Correction to an earlier statement in this mission:** an intermediate census reported
"1 `bunny_libraries` document" in Production. That was a PowerShell artefact — counting
`@($null)` yields 1. The authoritative re-check returns an empty document list, so the
Production catalog is **empty**. Nothing in this mission depends on the earlier wrong number,
but the correction is recorded rather than silently dropped.

Production deployment is **prepared but not authorized**: see
`ADR_010_OPTION_C_PRODUCTION_DEPLOYMENT_MANIFEST.md` (§4 command, §6 rollback, §9 gates
G1-G6).

---

## 3. What is not done, and why

| # | Item | Classification | Blocking evidence |
|---|---|---|---|
| 1 | Phase 6 Dashboard/App UI (library picker, registration screen, fallback credential input, upload workflow) | **BLOCKED — external access** | No Figma MCP resource, no Figma tool, no `FIGMA_TOKEN`. Nodes `58011:1024`, `58335:1444`, `871:1074`, `58171:1964` are unreadable. No screen, widget, colour, spacing, copy or interaction was invented. |
| 2 | Production deployment of the 7 functions | **BLOCKED — authorization** | Gates G1-G6 ungranted |
| 3 | Production catalog creation and `bunny_library_id` backfill | **BLOCKED — data write approval** | Would change Production data; no approved backup/rollback plan for it |
| 4 | D-09 — 7 Production rows without a video id | **BLOCKED — business decision** | Owner must choose leave / hide / delete / re-upload |
| 5 | N2 account-level credential | **Posture fixed to B (no account-API automation)** | Bunny does not document a Stream-only or library-scoped account credential |
| 6 | N9 daily verification + alert channel | **Not implemented — no channel** | Manual, audited `verifyBunnyLibrary` exists instead; it is not claimed to satisfy N9 |
| 7 | Upload mechanism (U-05/U-06) | **Capability-blocked** | Needs an authorized test library (D-02) and, for TUS, an account credential (D-01). `uploadBunnyResource` / `deleteBunnyResource` are **not deployed** in Staging. |
| 8 | Live Staging functional validation (V6-V10) | **Not executed — credential dependency** | No Doctor test identity |

---

## 4. Decisions D-01…D-09

Full detail in `ADR_010_OPTION_C_DECISION_RESOLUTION_REGISTER.md`.

| ID | Subject | Outcome |
|---|---|---|
| D-01 | N2 credential strategy | Resolved to the safest reversible posture (**B**); the "ask Bunny" question is external |
| D-02 | `780700` as authorized test library | **External blocker** — business authorization; read-only inspection only |
| D-03 | Figma access | **External blocker** — access |
| D-04 | Alert channel for N9 | **External blocker** — business choice |
| D-05 | `05 Database` schema approval | **Resolved** (v1.11 Approved, documentation only) |
| D-06 | Default library vs emergency deny list | **Owner decision** — current behaviour preserved and documented |
| D-07 | Catalog/credential validity windows | **Owner decision**, depends on D-04; 60 s credential cache unchanged |
| D-08 | Upload mechanism | **Capability-blocked** |
| D-09 | 7 unmapped Production rows | **External blocker** — Production data write |

No decision was answered by assumption, and no approved decision was contradicted.

---

## 5. Residual risk

| Risk | Severity | Mitigation in place |
|---|---|---|
| A Doctor account is required to register or verify libraries; if the Doctor identity is lost, no one can manage the catalog | Medium | Doctor is the Platform Owner; recovery is the existing auth recovery path, unchanged by this work |
| `verifyBunnyLibrary` can be invoked repeatedly and performs two outbound HTTPS calls per invocation | Low | Doctor-only, audited, 8 s timeout; no loop, no scheduler |
| The emergency deny list does not cover the default library | Medium | Documented in three places; owner decision pending (D-06). Not described anywhere as a complete kill switch. |
| Receipt key rotation has never been exercised with a real second key | Low | Dual-key verification is unit-tested; the rotation itself requires creating the secret, which was not authorized |
| Staging runs a bundle that is identical to an uncommitted working tree | Medium | Working tree is the source of truth; the deployed archive was captured and compared. A commit remains the owner's call. |
| Production Rules release could not be read (`403` on both projects: the active account lacks `firebaserules.releases.list`) | Low | The Staging catalog document holds credential **names**, a host and a pull-zone id - no key value. No catalog document exists in Production at all, so deny-all is not yet load-bearing there. Both must be confirmed before any catalog write (gate G4). |

---

## 6. What the owner must decide or provide

1. **Figma** — a `FIGMA_TOKEN` with `file_read`, or 2x PNG exports plus the node spec panel for the four nodes. Until then, all Option C UI stays blocked.
2. **Production** — grant or withhold G1-G6 for the 7-function deployment (`ADR_010_OPTION_C_PRODUCTION_DEPLOYMENT_MANIFEST.md` §9).
3. **D-02** — authorize or refuse `780700` as the dedicated test library.
4. **D-06** — subject the default library to the emergency deny list, or keep the exemption.
5. **D-09** — leave, hide, delete, or re-upload the 7 Production rows without a video id.
6. **D-04 / D-07** — pick the N9 alert channel and the catalog/credential validity window.
7. **Commit policy** - the working tree holds 46 modified tracked files and 36 untracked entries, with no commits. Whether this becomes one commit, several, or a branch is the owner's decision. The uncommitted `firestore.rules` and `firestore.indexes.json` edits belong to earlier phases of this mission and are **not** part of the Staging deployment; their live deployment state in either project could not be read with the current credentials.

---

## 7. Claims made and not made

**Claimed, with evidence:** the Option C backend is implemented; it passes 58/58 emulator
suites, the full pure suite, and 126 assertions in its two dedicated suites; it is deployed
to Staging and validated V1-V5; Production is untouched; no secret was created, read into a
log, or rotated; no Firestore data was written; no rule, index, IAM binding or environment
variable was changed **by this deployment**.

**Not claimed:** that Option C is complete; that Production is ready without the G1-G6
authorizations; that the UI exists; that N9 is satisfied; that upload works; that the 7
legacy Production rows are resolved; that Staging functional validation V6-V10 passed.
