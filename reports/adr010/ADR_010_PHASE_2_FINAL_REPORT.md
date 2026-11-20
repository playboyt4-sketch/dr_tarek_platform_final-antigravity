# ADR-010 Phase 2 — Final Report

Status: **PHASE 2 COMPLETE — proposals delivered, awaiting Platform Owner approval.**
Date: 2026-11-17
Phase: 2 of 7 (Governance and Documentation Proposals)
Implementation started: **No**
Authoritative documents modified: **None**

---

## 1. What Phase 2 produced

Seven files, all new, all in `reports/adr010/`. No existing report was overwritten.

| # | File | Purpose | Size |
|---|---|---|---|
| 1 | `ADR_010_AMENDMENT_2_PROPOSAL.md` | Normative amendment: Option C, N1–N12 with implementation status, catalog/isolation/fail-closed/emergency/receipt/upload contracts, N2 limitation, `775315` Open Item withdrawal | 7 sections |
| 2 | `ADR_010_OPTION_C_MASTER_ARCHITECTURE_CHANGE_PROPOSAL.md` | Exact ADR-register entry, version-history line, and one optional §3 sentence for `00` | 2 required + 1 optional insertion |
| 3 | `ADR_010_OPTION_C_DATABASE_SCHEMA_PROPOSAL.md` | `bunny_libraries` (11 fields), 3 `lecture_resources` fields, `admin_audit_log` vocabulary, state machine, eligibility predicate, migration plan | 10 sections |
| 4 | `ADR_010_OPTION_C_PERMISSION_AND_AUDIT_PROPOSAL.md` | 8 operations × actor/guard/rationale, explicit non-grants, exact `15` and `14` edits, audit constraints | 8 sections |
| 5 | `ADR_010_OPTION_C_CROSS_DOCUMENT_GOVERNANCE_PROPOSAL.md` | Exact edits for `04`, `06`, `07`, `08`, `09`, `11`, `13`; signing-duration resolution; Figma BLOCKED record | 10 sections |
| 6 | `ADR_010_OPTION_C_UNRESOLVED_DECISIONS.md` | D-01…D-09, each with question, evidence, options, security impact, blocking status, recommendation | 9 decisions |
| 7 | `ADR_010_PHASE_2_FINAL_REPORT.md` | This report | — |

---

## 2. Conflicts from Phase 0 — disposition

Every conflict identified in `ADR_010_OPTION_C_DOCUMENT_IMPACT_MATRIX.md` now has a
proposed resolution. None is applied.

| ID | Conflict | Resolution proposed in | Owner approval needed |
|---|---|---|---|
| C-01 | `FINAL_DECISIONS` §4 "Video ID only" vs library management and upload | File 5 §10 — exact Arabic replacement text + version 2.3 entry | Yes |
| C-02 | `05` has no `bunny_libraries` / `bunny_library_id` | File 3 | Yes (database approval) |
| C-03 | `06` §6.4 names a non-existent callable | File 5 §3 | No (Draft) |
| C-04 | `07` §16 names a non-existent callable | File 5 §4 | No (Draft) |
| C-05 | Three different signed-URL expiry statements | File 5 §1.1 + §6.1 | Yes (as part of cross-doc approval) |
| C-06 | `11` says "only `video_id`" | File 5 §7 | No (Draft) |
| C-07 | `00` ADR register omits ADR-010 | File 2 | Yes |
| C-08 | No permission for library management / upload | File 4 | Yes |
| C-09 | ADR-010 Open Items still require `775315` | File 1 §5 | Yes (as part of Amendment 2) |
| C-10 | Default library bypasses the emergency list | File 6 D-06 | Yes (decision) |
| C-11 | `03` has no video/library screens | File 5 §9 — **BLOCKED** | Blocked on Figma |
| C-12 | `04` Feature 05 has no library dimension | File 5 §2 | Yes |
| C-13 | `bunny_library_id` is null-by-construction but Option C needs it | File 3 §7 + File 6 D-09 | Yes (migration approval) |

---

## 3. Decisions that are now registered (not made)

`ADR_010_OPTION_C_UNRESOLVED_DECISIONS.md` holds nine decisions. Summary of what each
actually blocks:

| ID | Blocks | Recommendation offered |
|---|---|---|
| D-01 N2 strategy | N2/N3/N4 automation only | C now, build toward B |
| D-02 Test library `780700` | U-01…U-06, upload | Authorize |
| D-03 Figma | All Phase 6 UI | None possible |
| D-04 Alert channel | T-CF.16 only | None |
| D-05 `05` approval | Gate 2, catalog write | Approve |
| D-06 Default vs emergency list | Gate 6 | Subject default to list |
| D-07 Validity windows | N12 completeness | Tie to verification cadence |
| D-08 Upload mechanism | Phase 6 upload | After U-05/U-06 |
| D-09 7 unmapped rows | Absolute migration gate | Hide the 6 |

**Nine decisions, none made on the Owner's behalf.**

---

## 4. What is deliberately still blocked

| Item | Status | Reason |
|---|---|---|
| All Dashboard UI | `BLOCKED — Figma specification unavailable` | Nodes `58011:1024`, `58335:1444`, `871:1074`, `58171:1964` unreadable |
| `03_UI_UX` extension | Blocked | Same |
| Stream video upload design | Pending | U-05/U-06 unverified |
| Account-API automation | Pending | D-01 unresolved |
| Production catalog data | Not authorized | No database approval, no deployment approval |
| Receipt key creation | Not authorized | Gate 1 not approved |

---

## 5. Gaps found while writing Phase 2

Recorded honestly rather than papered over.

**G-1 — RESOLVED during Phase 2.** `FINAL_DECISIONS` §4 is an Approved document, so its
amendment was initially deferred out of caution about editing an approved text. The exact
Arabic replacement text and the version 2.3 entry are now delivered in
`ADR_010_OPTION_C_CROSS_DOCUMENT_GOVERNANCE_PROPOSAL.md` §10, including a line-by-line
table showing which rules are preserved and which single rule is replaced. No further
drafting is required; only Owner approval.

**G-2 — `05` currently documents `lecture_resources` with six fields, while Production
data carries eighteen.** Three are covered by File 3. Three more (`id`, `section_id`,
`thumbnail_storage_provider`) are observed but not proposed; File 3 §3.1 asks for a
decision rather than inventing a rationale.

**G-3 — No audit-retention policy exists anywhere.** File 4 explicitly declines to invent
one. It is a real gap for a system that will now record library lifecycle events.

---

## 6. Verification performed in Phase 2

Read-only, no mutation:

| Check | Result |
|---|---|
| Git branch / HEAD | `ci/ios-staging-codemagic` / `34a4b76…` — unchanged |
| Modified / staged / deleted | 34 / 0 / 0 — unchanged |
| `docs/notion` modifications | 0 |
| Existing reports overwritten | None |
| Function names and request contracts cited in the proposals | Read from `functions/src/index.ts` |
| Catalog field contract | Read from `bunny_library_catalog.ts` |
| Audit shape and access model | Read from `functions/src/index.ts` and `firestore.rules` L197 |
| Permission guards | `requireDoctor` (L958), `requireContentManager` (L7755) |
| Document conventions for `00`, `05`, `15`, `09` | Read from each document before drafting |
| Figma availability | Re-checked: still unavailable |

---

## 7. Approval checklist

Five approvals are requested. They are independent.

| # | Approve | File | Effect if approved |
|---|---|---|---|
| A | ADR-010 Amendment 2 | 1 | Option C becomes recorded; N1–N12 normative; `775315` Open Item withdrawn |
| B | `00` register entry + version 2.3 (+ optional §3 line) | 2 | ADR-010 becomes discoverable from the master document |
| C | `05` schema addition | 3 | Catalog and Bunny fields become authoritative; **documentation only** |
| D | `14` / `15` permission and audit model | 4 | Doctor-only registration/credentials; `ADMIN_CONTENT` limited to association + upload |
| E | `04`, `06`, `07`, `08`, `09`, `11`, `13` edits + expiry resolution | 5 | Cross-document consistency; `generateBunnySignedUrl` becomes the documented contract |

Plus one required follow-up: **F — draft the `FINAL_DECISIONS` §4 amendment text** (gap
G-1) before §4 can be edited.

Approving any of A–E does **not** authorize a deployment, secret, IAM change, Bunny
change, Firestore write, Rules change, index, Hosting deploy, or app release.

---

## 8. What Phase 3 needs from the Owner

Phase 3 is "resolve external dependencies and decisions". It can begin on the decisions
alone; it needs no deployment authority.

Minimum to unblock meaningful work, in order of leverage:

1. **D-05** (`05` approval) — unblocks the catalog write path.
2. **D-02** (`780700` authorization) — unblocks capability verification.
3. **D-06** (default vs emergency list) — unblocks a complete kill switch.
4. **D-01** (N2) — unblocks credential automation, but not the catalog itself.
5. **D-03** (Figma) — unblocks all UI.
6. **D-04**, **D-07**, **D-09** — unblock verification, N12 completeness, and the migration gate.

---

## 9. Phase 2 status

**PHASE 2 COMPLETE — GOVERNANCE PROPOSALS DELIVERED, NOT APPROVED.**

No authoritative document was modified. No code was changed. No Firebase, Bunny, secret,
IAM, Firestore, or deployment resource was touched. Implementation has not started and
will not start until the approvals above are granted.
