# ADR-010 Option C — Master Architecture Change Proposal

Status: **PROPOSED — awaiting Platform Owner approval. Not applied.**
Date: 2026-11-17
Target: `docs/notion/00_MASTER_ARCHITECTURE.md` (v2.2, Approved)
Scope: **exactly two insertions** (one ADR register entry, one version-history line) plus
one optional sentence. No other section is touched.

> This is a proposal file in `reports/adr010/`. It does not modify
> `00_MASTER_ARCHITECTURE.md`.

---

## 1. Why a change is required

`00_MASTER_ARCHITECTURE.md` is the project's single source of truth and holds the ADR
register. Its register currently lists ADR-004, ADR-005 and ADR-009 only. ADR-010 exists
as a separate Approved file but is **not registered**, so an auditor or contributor who
works from `00` alone will not discover that the platform is multi-library.

This is an omission, not a contradiction. The fix is additive.

---

## 2. Insertion 1 — ADR register entry

**Location:** immediately after the ADR-009 block, before the `# 6. User Roles` heading.

**Convention verified from the existing register:** each entry is
`## ADR-00X - Title`, followed by bullets `Decision`, `Context`, `Alternatives
Considered`, `Consequences`, `Status`, `Date`, `Version`.

**Exact proposed text:**

```markdown
## ADR-010 - Multi-Library Bunny Stream (Option C)

- **Decision:** Video delivery supports multiple independently managed Bunny Stream libraries. A server-managed catalog (`bunny_libraries`) is the sole source of truth for which libraries the platform may use; library identity is a numeric Bunny library id, and each library's credentials live in Secret Manager under deterministic names derived from that id (`BUNNY_<libraryId>_STREAM_API_KEY`, `BUNNY_<libraryId>_TOKEN_KEY`). Library selection and credential resolution are server-side only: no client may choose a library, receive a library credential, or read the catalog. A library is usable only when it is registered, active, has CDN Token Authentication enabled, and has had that configuration verified; every other state fails closed with no cross-library fallback. An emergency eligibility list can only reduce eligibility and can never grant it. Video association is written only after the backend has verified, with that library's own credential, that the video belongs to that library. The platform never creates Bunny libraries. Library `775315` is deferred and inactive. The approved recommendations N1-N12 are recorded, with their implementation status, in `21_ADR_010_Amendment_2.md`; N2 (an account-level credential scoped to Stream with least privilege) is approved in intent but blocked in feasibility because Bunny documents a single full-access account key and account-wide team permissions only.
- **Context:** ADR-010 v1.0 recorded that the account owns several Stream libraries while the backend was configured for exactly one, and enumerated options without selecting one. The Project Owner subsequently approved Option C together with recommendations N1-N12. Phase 0 established that the catalog read path, the per-library secret resolver, the per-resource library resolution and the emergency-list semantics already exist in Production, while registration, revocation, verification, receipt-key separation, account-credential access and Stream upload do not exist at all. Phase 0 also established that N2 as written cannot be implemented from documented Bunny capability.
- **Alternatives Considered:** (1) Option A - keep a single library and treat additional libraries as deploy-time configuration. Rejected by the Owner: it preserves the zero-configuration failure that motivated ADR-010 and cannot express per-library credentials without a redeploy. (2) Option B - manual Secret Manager entries per library with no catalog. Rejected as the primary architecture: it makes library identity operator-chosen and unverifiable, and removes any server-side eligibility gate. (3) Option C - server-managed catalog plus per-library credential isolation. Selected. (4) Implement an account-level discovery credential immediately. Rejected for now: the required least-privilege scope is not documented by Bunny, so the credential model remains an open decision rather than an assumption.
- **Consequences:** `05 Database` must document `bunny_libraries` and the Bunny fields on `lecture_resources` before any catalog write path is deployed; until that approval the Production catalog remains empty and playback continues through the legacy default-library path. `FINAL_DECISIONS` Section 4 must be amended because it currently permits only Video-ID entry in the Dashboard. `03 UI/UX` contains no approved video or library screen, so Dashboard work stays blocked until the Figma specification is available. The emergency eligibility list cannot yet be described as a complete kill switch because the default library bypasses it. Receipts are still signed with the CDN token key until N5 is implemented. No database schema, collection design, Cloud Function behaviour, Security Rule, authentication behaviour or permission behaviour is introduced by this ADR; those belong to their owning documents.
- **Status:** Approved (amended by `21_ADR_010_Amendment_2.md`).
- **Date:** 2026-11-12.
- **Version:** Master Architecture 2.3.
```

---

## 3. Insertion 2 — Version history line

**Location:** top of `00_MASTER_ARCHITECTURE.md`, in the `## Version History` list, as the
new first item.

**Exact proposed text:**

```markdown
- **2.3** (2026-11-17): Registered ADR-010 - Multi-Library Bunny Stream (Option C) in the ADR register. Adds a server-managed library catalog, per-library credential isolation in Secret Manager, server-only library selection, fail-closed eligibility, and an emergency eligibility list that can only reduce eligibility. No other architectural change; no database, Firebase, authentication or permission change. N1-N12 and their implementation status are recorded in `21_ADR_010_Amendment_2.md`.
```

---

## 4. Optional insertion 3 — Section 3 technology statement

**Location:** Section 3, the existing line `- Bunny CDN is used for video delivery.`
(L221).

**Current text:**

```markdown
- Bunny CDN is used for video delivery.
```

**Proposed replacement (one line, additive):**

```markdown
- Bunny CDN is used for video delivery. Delivery may span multiple Bunny Stream libraries; library identity and credentials are resolved server-side and are never exposed to clients (see ADR-010).
```

**Status of this insertion: OPTIONAL.** It is not required for governance
completeness, because the register entry already carries the decision. It is proposed
because a reader of Section 3 alone would otherwise still infer a single library. If the
Owner prefers the smallest possible change, approve Insertions 1 and 2 only.

---

## 5. What is deliberately not proposed

| Not proposed | Reason |
|---|---|
| Rewriting Section 8 (design principles) | Unrelated to Option C |
| Adding a new top-level section for video | Duplicates ADR-010; violates single-source-of-truth |
| Editing Section 6 (roles) | Permissions belong to `15`, not `00` |
| Registering ADR-006/007/008 | Out of scope for this mission |
| Changing the ADR registry table format | Existing convention is preserved exactly |

---

## 6. Consistency check performed

| Check | Result |
|---|---|
| Heading level matches existing entries (`## ADR-00X - Title`) | Yes |
| Bullet order matches (`Decision`, `Context`, `Alternatives`, `Consequences`, `Status`, `Date`, `Version`) | Yes |
| Version-history entry format matches (`- **2.x** (date): ...`) | Yes |
| ADR number is the next available | Yes — registry holds 004, 005, 009; 010 is already used by the ADR file and is now registered |
| No statement conflicts with ADR-004 / ADR-005 / ADR-009 | Confirmed — no role, device, or theme content is touched |
| "No database schema... introduced by this ADR" clause retained | Yes — matches ADR-004/005/009 convention |

---

## 7. Approval block

Proposed approval sentence:

> "I approve the `00_MASTER_ARCHITECTURE.md` change as proposed: the ADR-010 register
> entry and the 2.3 version-history line, and [optionally] the Section 3 one-line
> clarification. No other section may change."
