# Theme Migration — Document Index

This folder records the Light/Dark/System appearance mission. Reading order and
authority differ: the **approved** documents below are the specification of
record. Phase reports are evidence and handoff material, not specifications.

## Specification of record (Approved)

| Document | Role |
|---|---|
| `20_ADR_009_Theme_Mode_Support.md` | ADR-009 — decision, scope, decisions D1–D9 |
| `docs/notion/03_UI_UX.md` v1.2 §2 | Light tokens (§2.1), Dark tokens (§2.2), component contract (§2.3) |
| `docs/notion/00_MASTER_ARCHITECTURE.md` v2.2 | amended architecture principle |
| `docs/notion/FINAL_DECISIONS.md` v2.2 | amended decisions |
| `docs/notion/01_Project_Vision.md` v2.2 | amended vision wording |
| `docs/notion/11_Assets.md` v1.2 | asset treatment rules |

## Phase records

| Phase | Document | Status |
|---|---|---|
| 0 | `PHASE_0_BASELINE.md` | PASS — baseline snapshot |
| 1 | `PHASE_1_DARK_DESIGN_PROPOSAL.md` | PASS — proposal, ratified into ADR-009 |
| 4 | `PHASE_4_SCREEN_MIGRATION.md` | PASS — 11 Figma screens |
| 9 | `PHASE_9_QA_REPORT.md` | PASS WITH LIMITATIONS |
| 10 | `PHASE_10_DELIVERY_REPORT.md` | PASS for the approved scope |

Phases 5–6 (37 screens without Dark specs) are **BLOCKED** by owner decision
D7. Phase 7 (Dashboard) is **OUT OF SCOPE** by D6. Phases 2, 3 and 8 are
evidenced by code, tests and the reports above.

## Verification commands

```bash
dart analyze lib
dart analyze test

flutter test test/core/theme \
  test/authentication/new_student_end_screen_test.dart \
  test/responsive/brand_signature_hero_underline_test.dart

flutter test
```

Baseline (Phase 0): `+467 ~4 -52`.
Current: `+516 ~4 -52` (same 52 pre-existing failures, +49 passing).

## Release status

Nothing was committed, pushed, deployed or released. Dark Mode is **not**
cleared for app-wide release until the remaining 37 screens receive approved
Dark specifications and on-device QA is completed.
