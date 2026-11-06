# Phase 4 — Figma-specified Screen Migration

Date: 2026-11-02
Owner: Lead Architect / Implementation Coordinator
Scope authority: Owner decision **D7** — implement only the screens that have a
supplied Figma Light specification. All other screens remain **BLOCKED**.
Status: **PASS** (evidence in §7; residual risks in §8).

---

## 1. Objective

Replace screen-local Light-only colour literals with the approved semantic
contract (`AppSemanticColors`) on the 11 Figma-specified screens, without
changing a single Light-mode pixel, and without touching navigation, form
state, authentication, Firebase, rules, schema, or deployment.

This phase is **presentation-only**. It introduces no new abstraction beyond
the semantic `ThemeExtension` already approved in Phase 1/2.

---

## 2. Scope — the 11 Figma screens

| # | Screen | File |
|---|---|---|
| 3.1 | Splash | `lib/features/authentication/presentation/screens/splash_screen.dart` |
| 3.2 | User type selection | `lib/features/authentication/presentation/screens/user_type_selection_screen.dart` |
| 3.3 | New Student — Welcome | `.../new_student_welcome_screen.dart` |
| 3.4 | New Student — Full name | `.../new_student_name_screen.dart` |
| 3.5 | New Student — Phone number | `.../new_student_number_screen.dart` |
| 3.6 | New Student — Photo | `.../new_student_photo_screen.dart` |
| 3.7 | New Student — Grade | `.../new_student_grade_screen.dart` |
| 3.8 | New Student — Password | `.../new_student_password_screen.dart` |
| 3.9 | New Student — Under review | `.../new_student_end_screen.dart` |
| 3.10 | Welcome back (Login) | `.../login_screen.dart` |
| 3.11 | Student Home | `lib/features/student_home/presentation/screens/student_home_screen.dart` |

Screens 3.1–3.9 live in
`lib/features/authentication/presentation/screens/`.

---

## 3. What changed

- Every surface, text, icon, border, input, glass and overlay role on these
  screens now resolves through `AppSemanticColors.of(context)`.
- Legacy `AppColors.*` reads were removed from these screens, except where the
  value is an intentional Light-only branch (grade capsule fills, grade canvas,
  brand cards, Shadows, `Colors.transparent`) or a documented brand literal.
- Unused screen-local colour constants were removed where they had become dead
  code (Login `borderGray` / `hintGray` / `canvas`).
- No widget geometry, no navigation, no validation, no backend call was
  changed. The existing constructor carry-forward of registration state is
  untouched, so a theme rebuild cannot lose form data.

### 3.1 Light-preservation technique

Where a Light value did not map 1:1 to an approved semantic role, the code
keeps an explicit Light branch instead of silently recolouring. Examples:

| Location | Light value preserved | Dark behaviour |
|---|---|---|
| Grade capsule fill | `AppColors.gradeNCanvas` | `surfaceContainer` + grade accent (D3 Option B) |
| Student Home canvas | full-bleed grade canvas | neutral `canvas` (D3 Option B) |
| Student Home greeting | `#FFFCF7` | `textPrimary` |
| Login "Remember me" / "Forget password?" | `Colors.black` | `textPrimary` |
| Password inline validation | `Colors.redAccent` | `error` |
| Message card text | `AppColors.onSurface` (`#424242`) | `textPrimary` |
| Photo action sheet | approved cream glass `0x4CFFFCF7` | dark canvas glass 30% |

### 3.2 Dark decisions exercised in this phase

- **Grade screen — D3 Option B:** Dark fill is `surfaceContainer` (`#191D25`),
  the accent is carried by the capsule border and the number badge, and the
  label uses the approved grade-text tint (`gradeText1…4`). Light keeps the
  saturated capsule and white label exactly.
- **Student Home — D3 Option B:** Dark canvas is `surfaceContainer`-neutral
  (`canvas`), with grade identity carried by the accent-bordered cards and
  grade dots; the bottom pill uses the approved glass material.
- **Photo picker sheet:** Dark uses a dark glass sheet (30% dark-canvas fill,
  white 20% border, `outline` drag handle, 8% tiles). Light keeps the approved
  cream glass, white 35% border, `#E5E7EB` handle and 15% tiles.
- **Back buttons:** all inline copies now use `glassBackFill/Border` and
  `glassText`, matching the shared `GlassBackButton` (Light 25%/35% unchanged).

---

## 4. Explicitly not changed

- The global white input-field fix (`InputDecorationTheme` in
  `app_theme.dart`) — protected by `test/core/theme/input_theme_test.dart`.
- The Hero signature underline fix (`TextDecoration.none`) — protected by
  `test/responsive/brand_signature_hero_underline_test.dart`.
- Brand literals (signature red, user-type card amber/red, tier colours).
- Intentional black media surfaces, raster illustrations (neutral Dark art
  container per D5), and pastel note-editor surfaces.
- No new dependency, no Firebase/Storage/Rules/schema/Auth change.

---

## 5. Blocked work (Owner D7)

The remaining **37 screens** without a supplied Figma specification are
**BLOCKED**, not redesigned. They still contain Light-only literals; under
`AppTheme.dark` their bodies stay Light while app-bar/chrome tokens turn Dark.
That is expected and is recorded as a release risk in §8.

Also out of scope: the Student Dashboard (D6) and the 32 presentation files
that use `appBar:` outside the 11 screens.

---

## 6. Files touched in this phase

```
lib/features/authentication/presentation/screens/splash_screen.dart
lib/features/authentication/presentation/screens/user_type_selection_screen.dart
lib/features/authentication/presentation/screens/new_student_welcome_screen.dart
lib/features/authentication/presentation/screens/new_student_name_screen.dart
lib/features/authentication/presentation/screens/new_student_number_screen.dart
lib/features/authentication/presentation/screens/new_student_photo_screen.dart
lib/features/authentication/presentation/screens/new_student_grade_screen.dart
lib/features/authentication/presentation/screens/new_student_password_screen.dart
lib/features/authentication/presentation/screens/new_student_end_screen.dart
lib/features/authentication/presentation/screens/login_screen.dart
lib/features/student_home/presentation/screens/student_home_screen.dart
test/core/theme/migrated_screens_dark_test.dart        (new)
docs/theme-migration/PHASE_4_SCREEN_MIGRATION.md      (this file)
```

---

## 7. Evidence

### 7.1 Static analysis

```
dart analyze lib   ->  No issues found!
dart analyze test  ->  No issues found!
```

`flutter analyze` (the wrapper) repeatedly stalled in this environment on the
first `pub get`/analysis-server start; `dart analyze` on the same trees
completed cleanly and is the command of record here.

### 7.2 Targeted theme + regression tests — 58 passed

```
flutter test test/core/theme \
  test/authentication/new_student_end_screen_test.dart \
  test/responsive/brand_signature_hero_underline_test.dart
->  +58: All tests passed!
```

Includes:

- `test/core/theme/input_theme_test.dart` — Light input contract + Dark.
- `test/core/theme/components_theme_test.dart` — shared components.
- `test/core/theme/theme_controller_test.dart` — persistence/controller.
- `test/core/theme/theme_switch_state_test.dart` — **added during Phase 9
  QA**: light→dark→light keeps the pushed route and the typed draft; the mode
  is still persisted.
- `test/core/theme/migrated_screens_dark_test.dart` — **new**: pumps the
  migrated End and Grade screens under `AppTheme.light` and `AppTheme.dark`
  and asserts the exact Light values, the approved Dark roles, and measured
  contrast ≥ 4.5 (End title 17.64:1 on canvas).
- `test/core/theme/migrated_screens_hardcode_guard_test.dart` — **new
  Phase 8 guardrail**: freezes the approved per-screen raw colour literals,
  bans the legacy direct roles, and requires every migrated screen to resolve
  `AppSemanticColors.of(context)`. Runs 3/3 green.
- `test/responsive/brand_signature_hero_underline_test.dart` — Hero guard.

### 7.3 Broader authentication / home subset — no new failures

```
flutter test test/authentication test/features/authentication \
  test/responsive/auth_screens_responsive_test.dart \
  test/responsive/new_student_welcome_responsive_test.dart \
  test/responsive/splash_brand_signature_test.dart \
  test/responsive/user_type_selection_responsive_test.dart \
  test/responsive/user_type_selection_safe_area_test.dart \
  test/student_home/student_home_test.dart
->  +166  -45
```

The 45 failures are exactly the known pre-existing baseline failures:

| File | Failures | Pre-existing? |
|---|---|---|
| `user_type_selection_responsive_test.dart` | 19 | yes |
| `splash_brand_signature_test.dart` | 16 | yes |
| `user_type_selection_safe_area_test.dart` | 6 | yes |
| `student_home_test.dart` | 4 | yes |

Zero new failures. The golden `name_screenshot_test.dart` passed unchanged.

### 7.4 Full suite

```
flutter test
->  +516  ~4  -52: Some tests failed.
```

Against the Phase 0 baseline of `+467 ~4 -52`, this is **+49 net new passing
tests with exactly the same 52 failures**. The 52 failures are exactly the pre-existing
set recorded in `PHASE_0_BASELINE.md`:

| File | Failures | Pre-existing? | Caused by this work? |
|---|---|---|---|
| `user_type_selection_responsive_test.dart` | 19 | yes | no |
| `splash_brand_signature_test.dart` | 16 | yes | no |
| `user_type_selection_safe_area_test.dart` | 6 | yes | no |
| `student_profile_navigation_test.dart` | 4 | yes | no |
| `student_home_test.dart` | 4 | yes | no |
| `player_layout_test.dart` | 2 | yes | no |
| `widget_test.dart` | 1 | yes | no |

No test that passed in the baseline now fails. Coverage was extended, never
reduced.

### 7.5 Status gate

Phase 4 is marked **PASS**. Every gate condition holds:

- §7.1 static analysis clean on `lib` and `test`.
- §7.2 targeted theme + regression tests `+58`, all green.
- §7.3 broader auth/home subset shows no new failures.
- §7.4 full suite `+516 ~4 -52`: failure count identical to the Phase 0
  baseline with a net gain of 49 passing tests.

The status is **PASS for the 11 in-scope screens only**. Phases 5–6 remain
**BLOCKED** for the 37 screens without a Figma specification, per Owner
decision D7.

---

## 8. Residual risk (must be reported honestly)

1. **Dark Mode is not shippable app-wide yet.** 37 screens and the Dashboard
   are still Light-only by Owner decision D7. Enabling Dark Mode in production
   would expose mixed-theme screens. Dark Mode should remain behind product
   gating until those screens receive approved Dark specifications.
2. **No on-device visual confirmation.** This environment has no iOS/Android
   device or emulator; all verification is widget-test based (393×852 and
   360×640). Real-device font metrics and glass/backdrop rendering are not
   verified here.
3. **No live Figma comparison.** No Figma MCP/design bridge is available, so
   Light preservation is verified against the checked-in specs, existing
   golden/tests and the approved token table — not against a live frame.
4. **D8 duplicate blues** remain (`#1D4ED8` vs `#1A73E8`), preserved on purpose
   to keep Light byte-identical; cleanup is deferred.
5. **Student Home** deliberately changes from full-bleed grade canvas to the
   neutral Dark canvas in Dark (approved Option B). This is a visual identity
   change that the Owner approved for Dark only; Light is untouched.
