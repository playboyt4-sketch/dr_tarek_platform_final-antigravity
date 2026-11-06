# Documentation Amendments — APPLIED (Owner approval recorded 2026-11-01)

Prepared: 2026-11-01
Companion to: `20_ADR_009_Theme_Mode_Support.md`
Status: **APPLIED** — the Project Owner approved A–G on 2026-11-01 and the
approved documents now carry the amended text. `03_UI_UX.md` was promoted from
Draft to Approved (v1.2) under option E1.

Master Architecture §5.1 forbids silently modifying architectural decisions, and
§15 requires a documented reason plus a version increment. Each amendment below
records the exact before/after text and the version increment applied.

| Amendment | Document | Applied version |
|---|---|---|
| A | `docs/notion/00_MASTER_ARCHITECTURE.md` §8 | 2.2 |
| B | `docs/notion/00_MASTER_ARCHITECTURE.md` §5.3 | 2.2 |
| C | `docs/notion/FINAL_DECISIONS.md` §9 | 2.2 |
| D | `docs/notion/01_Project_Vision.md` Design Principles | 2.2 |
| E | `docs/notion/03_UI_UX.md` §2.1–§2.3 (option E1) | 1.2, Approved |
| F | `docs/notion/11_Assets.md` §5.1 dark token block | 1.2 |
| G | `docs/notion/15_Admin_Permissions_Audit_System.md` | unchanged (out of scope) |

---

## Amendment A — `docs/notion/00_MASTER_ARCHITECTURE.md` §8 Design Principles

**Current (Version 2.1, Approved):**

```text
# 8. Design Principles

- Mobile First
- Material 3
- White-based UI
- Minimal Design
- Consistent Components
- Reusable UI
- Accessibility First
- Responsive Layouts

Figma is the only visual source of truth.
```

**Proposed (Version 2.2):**

```text
# 8. Design Principles

- Mobile First
- Material 3
- Light-first UI with full Light, Dark and System appearance support
- Minimal Design
- Consistent Components
- Reusable UI
- Accessibility First
- Responsive Layouts

Figma is the only visual source of truth.

Light Mode is the canonical, approved design and remains visually unchanged.
Dark Mode is a second, equally supported rendering of the same design system and
requires its own approved Figma specification before per-screen implementation
(see ADR-009).
```

**Reason:** resolves the `White-based UI` conflict with Project Vision's
`Dark Mode Ready` / `Light Mode Ready` and the Owner's decision that both
appearances are genuinely supported. `White-based UI` is retained in meaning
(light is canonical, white/cream surfaces) but no longer excludes Dark Mode.

**Version increment:** 2.1 → 2.2 (architectural change).

---

## Amendment B — `docs/notion/00_MASTER_ARCHITECTURE.md` §5.3 ADR History

**Append immediately after the ADR-005 block:**

```text
## ADR-009 — Genuine Light and Dark Appearance Support

- **Decision:** The mobile application supports three appearance modes — `system`, `light`, `dark` — with `system` as the default. Light Mode is the canonical design and must not change visually. Dark Mode is an additive rendering of the same design system requiring its own approved Figma specification before per-screen implementation. Appearance preference is persisted locally; no Firebase dependency and no duplicated theme state are introduced. Grade identity, intentional media surfaces and intentional pastel note surfaces are preserved in both modes.
- **Context:** Master Architecture §8 previously stated `White-based UI` while Project Vision stated `Dark Mode Ready` and `Light Mode Ready`. The Owner resolved the ambiguity on 2026-11-01 by deciding that both appearance modes are genuinely supported on iPhone and the other supported platforms. The prior OS-driven Dark Mode wiring had been removed because it applied a `Brightness.light` scheme with dark surfaces and no dark input contract.
- **Alternatives Considered:** (1) Keep Light-only and reword Vision to drop Dark Mode. Rejected — contradicts the Owner decision. (2) Restore the previous dark theme. Rejected — it reproduces the unreadable-input regression. (3) Derive Dark Mode mechanically from `ColorScheme.fromSeed` without an approved specification. Rejected — §8 and §14 forbid inventing visual specifications. (4) Semantic token layer plus per-screen gating on approved Dark specifications. Selected.
- **Consequences:** `AppTheme` must build Light and Dark `ColorScheme`s with the correct `Brightness`. A `ThemeExtension<AppSemanticColors>` layer becomes the presentation contract. `AppColors` legacy constants remain until fully migrated. `test/core/theme/input_theme_test.dart` must be rewritten (not deleted) to assert the new contract while preserving its Light-mode assertions. No database schema, Cloud Function, Security Rule, authentication or permission behaviour is introduced by this ADR. Dark Mode visual values remain a design decision pending approval.
- **Status:** Proposed — awaiting Owner approval.
- **Date:** 2026-11-01.
- **Version:** Master Architecture 2.2.
```

---

## Amendment C — `docs/notion/FINAL_DECISIONS.md` §9 UI & UX

**Current (Version 2.1, Approved):**

```text
## 9. UI & UX

- مؤجل — شات منفصل مع AI مصمم
- Mobile First
- Material 3
- White-based UI
- Arabic support (RTL)
```

**Proposed (Version 2.2):**

```text
## 9. UI & UX

- مؤجل — شات منفصل مع AI مصمم
- Mobile First
- Material 3
- Light-first UI (white/cream default) with fully supported Light, Dark and
  System appearance modes; System is the default appearance
- Arabic support (RTL)
```

**Reason:** keeps the Arabic FINAL_DECISIONS record consistent with ADR-009 and
removes the only remaining `White-based UI` statement in an approved document.

**Version increment:** 2.1 → 2.2. Add to Version History:

```text
- **2.2** (2026-11-01): §9 amended per ADR-009 — Light Mode remains the canonical
  design and Dark Mode is a fully supported appearance mode (System default).
  No enforcement, schema or permission change.
```

---

## Amendment D — `docs/notion/01_Project_Vision.md` Design Principles

**Current (Version 2.1, Approved):**

```text
# Design Principles

The user experience must always prioritize usability and consistency.

- Mobile First
- Clean Interface
- Consistent Components
- High Performance
- Accessibility
- Responsive Design
- Dark Mode Ready
- Light Mode Ready
```

**Proposed (Version 2.2):**

```text
# Design Principles

The user experience must always prioritize usability and consistency.

- Mobile First
- Clean Interface
- Consistent Components
- High Performance
- Accessibility
- Responsive Design
- Light Mode and Dark Mode both fully supported, with System appearance as the
  default (see ADR-009)
```

**Reason:** `Ready` was ambiguous — it did not distinguish "ships today" from
"structurally prepared". The Owner has decided the product ships both. This makes
the Vision statement testable.

**Version increment:** 2.1 → 2.2. Add to Version History:

```text
- **2.2** (2026-11-01): Design Principles amended per ADR-009. "Dark Mode Ready"
  and "Light Mode Ready" replaced with an explicit statement that both modes are
  supported and System appearance is the default. No business scope change.
```

---

## Amendment E — `docs/notion/03_UI_UX.md` §2 Design System Reference

`03_UI_UX.md` is currently **Draft** and is therefore **not** an approved
implementation reference. Two options exist; the Owner must choose one.

**Option E1 — extend 03 (recommended).** Insert a new §2.2 and §2.3 containing
the approved Dark tokens and component states exactly as approved in
`docs/theme-migration/PHASE_1_DARK_DESIGN_PROPOSAL.md`, and change the document
Status from `Draft` to `Approved` (version 1.2). This keeps one visual-spec
owner document.

**Option E2 — new document.** Create `20_Dark_Mode_Design_System.md` as a
standalone Approved document. This requires adding the file to the Master
Architecture §12 Documentation Structure list, which is itself an architectural
change.

Option E1 is recommended because it avoids changing §12 and because 03 §2
already owns the design-system token table.

---

## Amendment F — `docs/notion/11_Assets.md` §5 (optional, Draft document)

`11_Assets.md` is Draft. Its `// Dark Mode` token block
(`darkBackground #121212`, `darkSurface #1E1E1E`,
`darkOnBackground #FFFFFF`) is a three-token placeholder, not a design system.
After Dark tokens are approved, this block should be replaced by a reference to
the approved Dark token table rather than restating values (Master Architecture
§9.1 forbids duplication).

Recommended text:

```text
// Dark Mode
// Token values live in 03 UI & UX §2.2 (approved). Do not restate them here.
```

Asset row `App Logo (Dark) | Dark mode variant` already exists in §2 of the
Draft document, which confirms a dark logo asset was anticipated. Whether that
asset exists in `assets/` must be verified before Phase 4.

---

## Amendment G — `docs/notion/15_Admin_Permissions_Audit_System.md`

Draft checklist item `- [ ] Dark mode support.` under **Dashboard Implementation**
refers to the Flutter Web management Dashboard, not the mobile app. It stays
unchanged and does not authorize Dashboard Dark Mode work in this mission.
