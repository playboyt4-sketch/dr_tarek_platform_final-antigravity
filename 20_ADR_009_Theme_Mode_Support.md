# ADR-009 — Genuine Light and Dark Appearance Support

Status: Approved — Project Owner approval recorded 2026-11-01
Date: 2026-11-01
Version: 1.0 (approved)
Supersedes: nothing (adds to, and resolves wording conflicts inside, Master Architecture 2.1 / FINAL_DECISIONS 2.1)
Related: 00_MASTER_ARCHITECTURE §8 and §5.3, 01_Project_Vision Design Principles, FINAL_DECISIONS §9

---

## 1. Decision

The Dr. Tarek Platform mobile application shall genuinely support three appearance
modes:1. `system` — follow the operating system appearance.
2. `light` — always the approved Light theme.
3. `dark` — always the approved Dark theme.

`system` is the default for every new installation and for every existing
installation that has no persisted preference.

The decision covers the Flutter mobile application (`lib/`) on Android, iOS and
Web. It does not, by itself, change the Flutter Web management Dashboard
(`dashboard/`), whose appearance scope remains a separate pending scope decision
(see §7).

The approved design system remains **light-first**: Light Mode is the canonical
design and must not change visually. Dark Mode is an additive second rendering of
the same design system, not a redesign.

Therefore the architectural principle recorded in Master Architecture §8 as
`White-based UI` is amended to `Light-first UI with full Light/Dark/System
appearance support`, and the Vision statements `Dark Mode Ready` / `Light Mode
Ready` are amended to state actual support rather than future readiness. Exact
amendment text is in
`docs/theme-migration/DOCUMENTATION_AMENDMENTS_PROPOSAL.md`.

---

## 2. Context

- Master Architecture 2.1 §8 lists `White-based UI` as an approved design
  principle.
- Master Architecture 2.1 is the highest-authority document and states that
  conflicts between documents must be resolved before implementation
  (§11.1), and that no architectural change may be applied silently (§5.1).
- Project Vision 2.1 lists `Dark Mode Ready` and `Light Mode Ready`.
- FINAL_DECISIONS 2.1 §9 lists `White-based UI`.
- Project Vision "Ready" wording does not specify whether the product ships
  Dark Mode or is merely structured to accept it later.
- The previous OS-driven Dark Mode wiring was removed from the code because
  `AppTheme.dark` was built with `Brightness.light` and no dark input contract,
  producing unreadable inputs and inconsistent surfaces. Two fixes were kept:
  the global white input-field fix and the Hero signature underline fix.
- `test/core/theme/input_theme_test.dart` encodes the *removal* decision by
  asserting `MaterialApp.darkTheme == null` and `themeMode != ThemeMode.dark`.
- The Project Owner has now explicitly decided that the application must
  genuinely support both Light and Dark Mode on iPhone and the other supported
  platforms, with System as the default appearance.
- No approved Dark Mode Figma specification exists in the repository
  (`docs/figma/` contains 10 Light-mode mobile specifications and 0 Dark-mode
  specifications). The only dark colour values on record are the three legacy
  tokens in Draft document `11_Assets.md` (`#121212`, `#1E1E1E`, `#FFFFFF`),
  which are not an approved design system and are not sufficient to specify
  surfaces, inputs, glass, grade variants or component states.

---

## 3. Alternatives Considered

1. **Keep Light-only and reword the Vision to remove "Dark Mode Ready".**
   Rejected: contradicts the Owner's explicit decision and the platform's
   Accessibility First principle.

2. **Restore the previous `AppTheme.dark` and wire `themeMode: ThemeMode.system`.**
   Rejected: that theme is `Brightness.light` with dark surface colours, has no
   dark input contract, no semantic token layer and no approved Dark visual
   specification. Re-enabling it would reproduce the exact regression that
   caused its removal.

3. **Ship Dark Mode without approved Dark Figma specifications, deriving colours
   mechanically from `ColorScheme.fromSeed`.** Rejected: Master Architecture §8
   and §14 forbid inventing visual specifications; §11.1 requires conflicts to
   be resolved first; the mission's Phase 1 gate forbids final Dark UI
   implementation without an approved specification.

4. **Implement a neutral Dark palette + semantic `ThemeExtension` layer, proven
   by measured contrast, and gate each screen on an approved Dark spec.**
   Selected. This satisfies the Owner decision, preserves Light output, gives a
   single maintainable source of theme truth, and keeps unimplementable screens
   honestly BLOCKED instead of guessed.

---

## 4. Consequences

### 4.1 Architectural

- `AppTheme.light` and `AppTheme.dark` must both pass the correct `Brightness`
  to `ColorScheme.fromSeed`.
- A `ThemeExtension<AppSemanticColors>` layer becomes the contract between the
  theme and presentation code. Feature screens consume semantic roles, not raw
  `Color(0x...)` values.
- Existing `AppColors` constants stay in place for backward compatibility until
  every dependency is migrated and verified; they are not deleted by this ADR.
- `AppTheme.dark` is rebuilt from approved Dark tokens. The legacy
  `AppTheme.dark`/`grade1..grade4` getters are currently unreferenced dead code
  (`grep` confirms zero call sites) and may be redefined without runtime effect.
- A `ThemeController` (Riverpod `Notifier<ThemeMode>`) plus a persisted
  `SharedPreferences` key mirror the existing `LocaleController` /
  `loadPersistedLocale()` / `initialLocaleProvider` bootstrap pattern. The
  preference is loaded before `runApp` so the first frame is never the wrong
  brightness.
- No new dependency is introduced. No Firebase read/write is introduced for
  appearance. Theme state is not duplicated.

### 4.2 Behavioural

- Changing the appearance must not reset navigation, lose form data, interrupt a
  workflow, or re-initialise authentication. Theme is a `MaterialApp` property
  change only; the router instance and widget state are preserved.
- A manual `light` choice overrides an OS `dark` appearance and vice versa.
  `system` reacts to live OS changes.

### 4.3 Visual

- Light Mode output must remain byte-identical at the widget level for the
  existing approved screens.
- Dark Mode is implemented per screen **only** when an approved Dark
  specification exists for that screen. Screens without one are BLOCKED, not
  guessed.
- Grade identity is preserved in both modes. The strategy for darkening or
  retaining grade canvases is a design decision that requires Owner/Design
  approval (see `docs/theme-migration/PHASE_1_DARK_DESIGN_PROPOSAL.md` §3).
- Intentionally dark media surfaces (video player, PDF document surface) stay
  black in both modes; only their surrounding chrome becomes theme-aware.
- Intentional pastel note-editor surfaces are preserved unless an approved
  design says otherwise.

### 4.4 Test impact

- `test/core/theme/input_theme_test.dart` currently asserts the absence of a
  dark theme. That assertion encoded the superseded decision and must be
  **rewritten, not deleted**, to assert the new contract:
  - Light Mode editable fields are still white with the `#D0D0D0` border;
  - Dark Mode editable fields are readable in every state;
  - OS appearance no longer produces an unreadable field.
  The Light-mode assertions in that file stay unchanged.
- `test/responsive/brand_signature_hero_underline_test.dart` must keep passing
  unchanged.

### 4.5 Documentation

This ADR requires, before implementation is treated as approved:

- Master Architecture §8 amendment + §5.3 ADR-009 entry + version 2.2.
- FINAL_DECISIONS §9 amendment + version 2.2.
- Project Vision Design Principles amendment + version 2.2.
- An approved Dark Mode specification (tokens, grade variants, glass,
  component states, asset strategy) — proposed in
  `docs/theme-migration/PHASE_1_DARK_DESIGN_PROPOSAL.md`.

Draft documents `03_UI_UX`, `07_FLUTTER_ARCHITECTURE`, `08_DEVELOPMENT_STANDARDS`
and `11_Assets` may be aligned in follow-up steps, but they are **not** approved
implementation references today and this ADR does not promote them.

---

## 5. Explicit Non-Decisions

This ADR does not decide:

- Specific Dark colour values (design decision — pending approval).
- Grade canvas darkening strategy (design decision — pending approval).
- Whether an in-app appearance selector screen ships (that needs an approved
  Figma specification; the underlying architecture is implemented regardless and
  the control stays behind an approved integration point).
- Dashboard (`dashboard/`) Dark Mode scope.
- Any change to Firestore schema, Security Rules, Cloud Functions,
  authentication behaviour or permissions.

---

## 6. Rollback

The change is reversible without data migration:

1. Set `themeMode: ThemeMode.light` and omit `darkTheme` in `MaterialApp.router`.
2. Remove the persisted `app_theme_mode` key read (the stale key is inert).
3. Screens migrated to semantic tokens keep working because the Light values of
   the semantic layer equal the approved light constants.

No backend, schema, rules or auth rollback is required.

---

## 7. Owner Decisions (recorded 2026-11-01)

| # | Decision | Outcome |
|---|---|---|
| D1 | Approve this ADR and the documentation amendments | **APPROVED** — amendments A–G applied |
| D2 | Approve the Dark semantic palette | **APPROVED** — canvas `#0B0D12`, surface `#15181F`, text `#F2F4F7`, primary `#7FA9FF`; glass 8%/14% |
| D3 | Grade identity strategy in Dark Mode | **APPROVED** — Option B: neutral canvas + grade accent |
| D4 | Glass opacity/border values | **APPROVED** — 8% fill / 14% border |
| D5 | Raster onboarding illustration strategy | **APPROVED** — neutral dark art container (no asset edits) |
| D6 | Dashboard (`dashboard/`) scope | **OUT OF SCOPE** — separate pending scope decision (Phase 7) |
| D7 | Spec coverage for screens without Figma | **RESTRICT TO FIGMA-SPECIFIED SCREENS** — all other screens remain BLOCKED, not implemented, not redesigned |
| D8 | Duplicate brand blue (`#1D4ED8` vs `#1A73E8`) | **PRESERVE BOTH** in this mission — zero Light visual change; cleanup deferred |
| D9 | Brand signature colour in Dark Mode | Not separately decided; implemented as Light `Colors.black` (unchanged) / Dark `#F2F4F7` (semantic `textPrimary`), consistent with D2 |
