# Phase 9 — QA & Verification Report

Date: 2026-11-03
Owner: Lead Architect / Implementation Coordinator
Scope authority: Owner decisions **D6** (Dashboard out of scope), **D7** (only
Figma-specified screens), **D8** (duplicate blues preserved), **D9** (brand
signature semantics).
Status: **PASS WITH LIMITATIONS** — all automated checks pass; on-device and
live-Figma verification are **BLOCKED** by the environment and are recorded
below rather than claimed.

---

## 1. What this phase verifies

Phase 9 is the independent QA pass over Phases 2–8. It answers four questions:

1. Does the appearance system actually behave as specified
   (`system` default, `light`, `dark`, persisted, no first-frame flash)?
2. Did Light Mode stay visually unchanged?
3. Were the two pre-existing fixes preserved (global white inputs, Hero
   signature underline)?
4. Did any of this introduce a regression anywhere else in the suite?

It does **not** re-open design decisions. Those are recorded in
`20_ADR_009_Theme_Mode_Support.md` and `docs/notion/03_UI_UX.md` §2.

---

## 2. Environment and commands of record

| Item | Value |
|---|---|
| Host | Windows, `win32` |
| Flutter | 3.44.4 (stable) |
| Dart | 3.12.2 |
| Branch | `ci/ios-staging-codemagic` |
| Analyzer | `dart analyze lib` and `dart analyze test` |
| Test runner | `flutter test` |
| Physical devices / emulators | **none available** |
| Figma MCP / design bridge | **none available** |

`flutter analyze` (the wrapper) repeatedly stalled in this environment while
starting the analysis server. `dart analyze` runs the same analyzer on the same
trees and is the command of record. Both `lib` and `test` are clean.

---

## 3. Requirement → verification matrix

| # | Requirement | Method | Result |
|---|---|---|---|
| 1 | Three modes exist: `system`, `light`, `dark` | `input_theme_test.dart` "OS appearance wiring" (4 tests) + `theme_controller_test.dart` | **PASS** |
| 2 | `system` is the default | `initialThemeModeProvider` defaults to `ThemeMode.system`; 2 controller tests assert the default | **PASS** |
| 3 | Preference persists locally, no Firebase | `shared_preferences` only; 4 controller tests + 1 state test; no Firebase import in `lib/core/theme` | **PASS** |
| 4 | Persisted mode is loaded before `runApp` (no flash) | `main.dart` awaits `loadPersistedThemeMode()` before `runApp`, then overrides `initialThemeModeProvider`; verified by code inspection | **PASS (code path)** — the production bootstrap (Firebase init) is not widget-tested, so first-frame brightness is not asserted end-to-end |
| 5 | Theme change must not reset navigation, lose form data, or re-init auth | New `theme_switch_state_test.dart`: pushes a route, types a draft, switches light→dark→light, asserts the route and draft survive; theme layer has no auth dependency | **PASS** |
| 6 | Light Mode appearance unchanged | Exact-value assertions in `input_theme_test`, `components_theme_test`, `migrated_screens_dark_test`; `name_screenshot_test` golden passes unchanged | **PASS (automated scope)**; live Figma comparison **BLOCKED** |
| 7 | Global white input-field fix preserved | `input_theme_test.dart`, 20 tests (Light + Dark input decoration) | **PASS** |
| 8 | Hero signature underline fix preserved | `brand_signature_hero_underline_test.dart` | **PASS** |
| 9 | 11 Figma screens use the semantic contract | `migrated_screens_hardcode_guard_test.dart` (3 tests) + `migrated_screens_dark_test.dart` (6 tests) | **PASS** |
| 10 | No new abstraction beyond the approved `ThemeExtension` | Code review; analyzer; no new state container or theme provider hierarchy | **PASS** |
| 11 | No deploy, schema, auth, or Firebase change | Working-tree review; `git diff --stat`; no functions/rules/schema edits | **PASS** |
| 12 | WCAG AA for approved Dark text pairs | Measured ratios in the ADR/Phase 1 table; `migrated_screens_dark_test` asserts ≥ 4.5 for the screens it pumps | **PASS**, with one documented pre-existing Light exception (`inputBorder #D0D0D0` on `#FFFFFF`, 1.54:1) preserved on purpose |
| 13 | No regression in the full suite | `flutter test` compared with the Phase 0 baseline | **PASS** — identical 52 pre-existing failures, net gain of 49 passes |
| 14 | Real-device rendering (fonts, glass, backdrop, safe areas) | — | **BLOCKED** — no iOS/Android device or emulator |
| 15 | Live comparison against Figma frames | — | **BLOCKED** — no Figma access in this environment |

---

## 4. Automated results

### 4.1 Static analysis

```
dart analyze lib   ->  No issues found!
dart analyze test  ->  No issues found!
```

### 4.2 Theme + regression tests

```
flutter test test/core/theme \
  test/authentication/new_student_end_screen_test.dart \
  test/responsive/brand_signature_hero_underline_test.dart
->  +58: All tests passed!
```

Theme test inventory:

| File | Tests | What it proves |
|---|---|---|
| `input_theme_test.dart` | 20 | Light input contract, Dark input contract, semantic token values, `system` follows the OS, explicit choice overrides the OS |
| `components_theme_test.dart` | 14 | Shared components (buttons, glass back, password meter, brand signature, typography) in both themes |
| `theme_controller_test.dart` | 9 | Parse, default, load, set, cycle, persistence round-trip |
| `theme_switch_state_test.dart` | 2 | **New in QA**: theme swap preserves the route and form draft; persistence still writes |
| `migrated_screens_dark_test.dart` | 6 | End + Grade under both themes: exact Light values, approved Dark roles, contrast ≥ 4.5 |
| `migrated_screens_hardcode_guard_test.dart` | 3 | Per-screen raw-literals allowlist, banned legacy roles, required `AppSemanticColors` lookup |

### 4.3 Full suite

```
flutter test
->  +516  ~4  -52: Some tests failed.
```

Phase 0 baseline:

```
flutter test
->  +467  ~4  -52
```

| Metric | Baseline | After theme work | Delta |
|---|---|---|---|
| Passing | 467 | 516 | **+49** |
| Skipped | 4 | 4 | 0 |
| Failing | 52 | 52 | **0** |

No test that passed at baseline now fails, and no failing test was deleted or
skipped to hide a regression. Coverage was only extended.

### 4.4 The 52 pre-existing failures

These are unchanged, pre-existing failures unrelated to theme work. They are
listed here so this report never implies "all tests pass".

| File | Failures | Subject |
|---|---|---|
| `test/responsive/user_type_selection_responsive_test.dart` | 19 | responsive layout of a screen whose spec predates this mission |
| `test/responsive/splash_brand_signature_test.dart` | 16 | splash logo width assertions |
| `test/responsive/user_type_selection_safe_area_test.dart` | 6 | safe-area assertions |
| `test/student_profile/student_profile_navigation_test.dart` | 4 | navigation expectations |
| `test/student_home/student_home_test.dart` | 4 | home layout expectations |
| `test/video_streaming/player_layout_test.dart` | 2 | player layout |
| `test/widget_test.dart` | 1 | legacy smoke test |

They were failing before any theme file was touched. Fixing them is a separate
mission; changing them here would have mixed unrelated work into the theme
change.

---

## 5. Platform matrix

| Target | Verification | Status |
|---|---|---|
| Android — widget | `flutter test`, viewports 320×568 → 393×852 (incl. 360×640 and 393×852) | **PASS** |
| iOS — widget | same widget suite | **PASS** |
| Android — physical/emulator | no device attached | **BLOCKED** |
| iOS — physical/simulator | no device attached (Windows host cannot run iOS) | **BLOCKED** |
| Web | not run in this phase; ADR-009 covers web as an implementation target | **NOT VERIFIED** |
| Live Figma | no design bridge | **BLOCKED** |

Widget tests confirm layout and colour resolution, not platform font metrics,
native glass blur, or real safe-area insets. Those remain device-QA items.

---

## 6. Defects found and fixed during QA

| # | Finding | Resolution |
|---|---|---|
| 1 | Photo and Welcome screens were missing the `app_semantic_colors.dart` import after migration | Added; analyzer clean |
| 2 | `_WelcomeBody.build` referenced `semantic` without resolving it | Resolved via `AppSemanticColors.of(context)` |
| 3 | Two screens kept unused `app_colors` imports; Login's import had been narrowed too far (`AppShapes` still needed) | Corrected imports; analyzer clean |
| 4 | Golden mismatch caused by alpha precision: `Colors.white.withValues(alpha: 0.25)` is exactly 0.25, while `Color(0x40FFFFFF)` is 0.25098 | Replaced with `Color.fromRGBO(255, 255, 255, 0.25)` for the back-glass roles so the Light golden is byte-identical |
| 5 | No automated proof that a theme switch preserves navigation/form state | Added `theme_switch_state_test.dart` (2 tests) |

---

## 7. Limitations and residual risk

1. **No on-device verification.** Glass/backdrop blur, platform fonts, native
   status-bar behaviour and safe areas are unverified here.
2. **No live Figma comparison.** Light preservation is verified against the
   checked-in specs, token table and goldens, not a live frame.
3. **Dark Mode is not app-wide.** 37 of the 48 screens inventoried in
   `PHASE_1_DARK_DESIGN_PROPOSAL.md` §7 remain Light-only by D7. Under the Dark
   theme their bodies would keep Light literals while the Material chrome
   darkens. **Dark Mode must not be enabled for users until those screens have
   approved Dark specifications.**
4. **No user-facing selector.** No Figma frame exists for a theme selector, so
   only the tested controller API exists. Shipping it would require a design.
5. **52 pre-existing failures remain.** They are outside this mission's scope
   and were not masked.
6. **Light contrast exception.** `inputBorder #D0D0D0` on white is 1.54:1.
   It is pre-existing and intentionally preserved to keep Light unchanged.

---

## 8. QA gate decision

**PASS WITH LIMITATIONS.**

Every automated gate that can run in this environment is green: analyzer clean,
58/58 targeted theme + regression tests, and a full suite identical to the
baseline failure set with +49 net passing tests. The limitations in §7 are
environmental or owner-scoped, not failures of the implementation, and none of
them is hidden in this report.

The implementation is **not** signed off for production Dark Mode release.
That sign-off requires (a) approved Dark specifications for the remaining
screens and (b) on-device QA.
