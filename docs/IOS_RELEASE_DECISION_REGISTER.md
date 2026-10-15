# iOS Release Decision Register — Dr. Tarek Platform

Conventions: only Approved documents authorize implementation. Draft stays Draft until the Teacher (Platform Owner) promotes it. This register records decisions; it does not promote any document.

## 1. Confirmed owner decisions (do not re-ask)

| ID | Decision | Value | Recorded in | Status |
|---|---|---|---|---|
| D-ID | Final iOS Bundle ID | `com.drtarek.platform` | `docs/IDENTITY_MIGRATION_PLAN.md` v1.1 §2 | Decided |
| D-ID | Android application ID | `com.drtarek.platform` | same | Decided |
| D-NAME | Store-facing name | `Tarek El Araby Platform` | same + `13_Releases.md` finals table | Decided |
| D-SKU | SKU / category | `TAREK-PLATFORM-IOS-001` / Education | same | Decided |
| D-VER | Versioning | keep `1.0.0+1` temporarily; final policy open | same | Temporary |
| D-STG | TestFlight backend | Isolated Firebase Staging | same + staging plan | Project + apps + selector IMPLEMENTED 2026-10-14; service separation pending |
| D-ROLE | Role migration | `teacher`→`doctor` atomic before iOS | ADR-005 + `FINAL_DECISIONS.md` §26 | Decided, code-done, prod migration pending ops approval |
| D-SHOT | iOS screenshot promise | Detection-only | `14_…md` note + identity plan | Decided, UI-copy sweep pending |

## 2. Conflicts resolved in this task

- C1 identity-plan self-contradiction → closed by D-ID record (v1.1).
- C2 display-name brand prefix → corrected to `Tarek…` per D-NAME.
- C4 screenshot-prevent row → corrected per D-SHOT (Draft edit, not promoted).
- C8 root stubs shadowing SoT → deprecated-pointer lines added.
- Standing hierarchy reminders: notion `FINAL_DECISIONS.md` v2.1 + `00_MASTER_ARCHITECTURE.md` v2.1 are the authorities; `05_DATABASE_v1.7.md` is the Approved DB baseline (v1.8/v1.10 Proposed); `06/07/08/09/10/11/13/14/15` remain Draft.

## 3. Outstanding decisions (owner or delegate)

| ID | Question | Blocks | Default if undecided |
|---|---|---|---|
| O1 | Authorize production role-data migration window + owner re-login for doctor claims (runbook §4) | M2 completion, M7 | TestFlight waits |
| O2 | Billing posture for staging (Spark preferred) + who performs staging console steps (project/apps already created 2026-10-14) | M3 | Service separation waits |
| O3 | Final build-number policy (`+1` increment vs `100000`-style) | First upload | Keep incrementing `+N` |
| O4 | Deployment-target floor (accept Mac resolver minimum, likely 15/16+) | M6 | Resolver decides; drops old devices |
| O5 | Privacy/terms/support URLs + hosting + legal sign-off (privacy labels, export, age rating) | Submission | BLOCKED |
| O6 | Assessment behavior: ✅ DECIDED B (results at final submit only). Implemented 2026-10-14: `getAssessmentQuestions` sanitized callable + submit entitlement gate + client evaluate-flow removed + Map parsing defect fixed. Staging deploy pending (billing approval). | TestFlight QA | O6-B implemented locally; deploy + device proof pending |
| O7 | Legacy XOR vault: delete dead file vs deprecate marker (no installs affected — zero references) | Security sign-off | Leave untouched, do not wire |
| O8 | UGC moderation (report/block/24h review) for chat/Q&A/uploads | Age rating / review | Expect 17+ or rejection risk |
| O9 | Confirm no external purchase links in reviewer path (V1 manual-payments model) | Review notes | Must verify before upload |

## 4. Production role migration runbook (SAFE — takes effect only on explicit O1 approval)

Preconditions: code migration VERIFIED (rules/functions/dashboard/clients doctor-only; suites green — see readiness report §4/§5); full Firestore export downloaded and restorable; owner available for re-login within the window; announced maintenance if students active.

1. Dry run: `node scripts/migrate_teacher_to_doctor.cjs --dry-run` (operator is idempotent, marker-guarded; asserts single teacher candidate = pinned owner UID, aborts otherwise).
2. Backup: Firestore export + Auth user export stored off-project with checksums.
3. Execute: `node scripts/migrate_teacher_to_doctor.cjs --confirm` (role-only write `teacher`→`doctor` on owner doc + audit marker; claims untouched by script).
4. Claims: owner signs out/in (or admin SDK refresh) to mint `{role:"doctor"}`; verify via `auth.getUser` read-only check.
5. Verify: zero `users.role=="teacher"` docs (read-only query); negative test — stale teacher token denied by rules/functions tests; owner reaches `/doctor` + mobile admin gates; admin/student sessions unaffected.
6. Rollback: operator `--rollback --confirm` restores `doctor`→`teacher` for the pinned UID only (same marker discipline); re-login restores prior claims; restore export if data unexpectedly mutated.
7. Post: record migration marker + timestamps in decision register; NEVER run seed/set-teacher scripts (quarantined) afterwards.
