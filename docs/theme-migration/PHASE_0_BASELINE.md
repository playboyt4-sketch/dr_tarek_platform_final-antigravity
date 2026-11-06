# Phase 0 — Repository Baseline & Documentation Ratification

Date: 2026-11-01
Owner: Lead Architect / Implementation Coordinator
Production code modified in this phase: **none**

---

## 1. Objective

Establish the actual current state of the repository, verify documentation
approval status, identify architectural conflicts, and prepare the governance
artifacts required before any theme implementation begins.

---

## 2. Repository baseline

### 2.1 Git

| Item | Value |
|---|---|
| Branch | `ci/ios-staging-codemagic` |
| HEAD | `565b7559bbdd0132defcf9e7ad4d36a8f230a535` |
| HEAD subject | `docs(ios): point TestFlight runbook at external tester group` |
| Tracked files modified | 47 |
| Diff size | 1,750 insertions(+), 884 deletions(-) |
| Untracked paths (pre-existing) | 7 |
| Stashes | none |

Snapshots preserved in this folder:
`GIT_BASELINE_HEAD.txt`, `GIT_BASELINE_STATUS.txt`, `GIT_BASELINE_DIFFSTAT.txt`.

### 2.2 Pre-existing uncommitted work that MUST NOT be lost

This mission added **no** changes to these files. They were already dirty when
the mission started.

`??` (untracked, pre-existing):

```
19_ADR_008_Security_Events_Alerting_Policy.md
DEPENDENCY_SECURITY_AUDIT_2026-10-22.md
docs/RELEASE_READINESS_HANDOFF_2026-10-20.md
security_documentation_reconciliation_2026-10-22.md
security_events_database_change_proposal.md
test/core/theme/
test/responsive/brand_signature_hero_underline_test.dart
```

`M` (modified, pre-existing) — 47 paths, including:

- CI/tooling: `.github/workflows/ci.yml`, `android/.gitignore`,
  `android/app/build.gradle.kts`, `android/gradle.properties`,
  `functions/package-lock.json`, `functions/src/index.ts`,
  `functions/scripts/seed_database.ts`, `functions/test/security_event.test.js`
- Dashboard (separate app): `dashboard/pubspec.yaml`, `dashboard/pubspec.lock`,
  `dashboard/lib/app/shell/*`, 9 `dashboard/lib/features/students/**` overlays,
  5 dashboard tests
- Mobile theme-adjacent: `lib/app/app.dart`, `lib/core/theme/app_colors.dart`,
  `lib/core/theme/app_theme.dart`, `lib/core/theme/app_typography.dart`,
  `lib/core/responsive/responsive.dart`
- Mobile screens: `login_screen.dart`, `new_student_welcome_screen.dart`,
  `new_student_photo_screen.dart`, `new_student_end_screen.dart`,
  `student_home_screen.dart`, `subject_navigation_screen.dart`,
  `students_management_screen.dart`, `forgot_password_sheet.dart`
- Video/DRM: `offline_drm_service.dart`, `playback_session_coordinator.dart`
- Tests: `auth_gate_test.dart`, `login_screen_test.dart`,
  `auth_screens_responsive_test.dart`, `new_student_welcome_responsive_test.dart`
- Docs: `docs/IDENTITY_MIGRATION_PLAN.md`, `docs/IOS_*.md`

**Implication:** `lib/core/theme/app_colors.dart`, `app_theme.dart` and
`app_typography.dart` are already dirty. Any theme edit must be additive on top
of the current working-tree content, never a re-checkout of HEAD.

### 2.3 Toolchain

```
Flutter 3.44.4 • channel stable • revision ad70ec4617 (2026-06-24)
Framework • Dart 3.12.2 • DevTools 2.57.0
Dart SDK version: 3.12.2 (stable) on "windows_x64"
```

`pubspec.yaml` declares `sdk: ^3.12.2`. Riverpod `flutter_riverpod: ^3.4.2`,
`shared_preferences: ^2.5.3`, `go_router: ^18.0.1`, Material 3. No dependency
change is required for this mission.

### 2.4 Sub-agent / orchestration capability

The environment exposes a `subagent` tool with two agent types (`explore`,
`general`) that can run in foreground or background and return a session ID.
Limitations found:

- `explore` is read-only exploration only — suitable for Agent A/D audits.
- `general` has full tool access and could edit files, so file ownership must be
  enforced manually (one agent per file at a time).
- There is **no** Figma MCP server configured in this environment. `search` for
  Figma tooling returns nothing, and `docs/figma/` is a static export. Agent B
  therefore cannot open the live Figma file; it can only work from the exported
  specifications and PNGs in the repository.
- There is **no** iOS/Android device or emulator attached to this Windows
  environment. Physical-device verification is impossible here.

### 2.5 Code inventory (re-measured, not copied from the old audit)

| Metric | Old audit | Measured now |
|---|---:|---:|
| `lib/**/*.dart` files | — | 265 |
| Presentation Dart files | 97 | 97 |
| `*_screen.dart` files | 46 | 46 (+2 non-suffixed entry points) |
| `Color(0x...)` occurrences in `lib/` | 255 | 252 |
| `AppColors.*` references | 253 | 235 |
| `Theme.of(context)` references | 52 | 52 |
| `TextField`/`TextFormField` declarations | 54 | 54 |
| `AppInput(` usages | 13 | 14 |
| `ThemeExtension` implementations | 0 | 0 |
| Presentation files with hardcoded colours | 64 | 64 |

Counts drifted by a few units — confirming the old audit was stale. Every number
in this mission is re-measured.

Top hardcoded-colour offenders (presentation):

```
45  profile/presentation/widgets/profile_edit_sheet.dart
42  authentication/presentation/screens/student_registration_wizard.dart
40  lecture/presentation/screens/pdf_viewer_screen.dart
37  subject_navigation/presentation/screens/subject_navigation_screen.dart
36  lecture_viewer/presentation/screens/lecture_viewer_screen.dart
30  profile/presentation/screens/student_profile_screen.dart
29  video_streaming/presentation/components/video_states.dart
26  student_home/presentation/screens/student_home_screen.dart
26  admin/presentation/screens/students_management_screen.dart
25  authentication/presentation/screens/new_student_photo_screen.dart
```

---

## 3. Current theme wiring — root-cause analysis

`lib/app/app.dart`:

```dart
theme: AppTheme.light,   // no darkTheme, no themeMode
```

`lib/core/theme/app_theme.dart`:

```dart
static ThemeData get light => _buildTheme(canvasColor: AppColors.canvas, ...);
static ThemeData get dark  => _buildTheme(canvasColor: AppColors.darkBackground, ...);
...
static ThemeData _buildTheme({...}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.buttonSolid,
    brightness: Brightness.light,   // <-- hardcoded for EVERY theme
    ...
```

**Root cause of the removed Dark Mode:** `AppTheme.dark` passes dark surface
colours but builds a `Brightness.light` `ColorScheme`, and the global
`inputDecorationTheme` fills fields with the dark `surfaceColor` while
`textTheme` still yields light-mode text roles. The result is exactly the
reported symptom: unreadable inputs and inconsistent surfaces.

Secondary finding: `AppTheme.dark`, `AppTheme.grade1`, `AppTheme.grade2`,
`AppTheme.grade3`, `AppTheme.grade4` are **dead code** — `grep` for
`AppTheme.dark` / `AppTheme.gradeN` returns zero call sites. Only
`AppTheme.light` is referenced.

No `ThemeMode` reference exists anywhere in `lib/` today.

### 3.1 Existing colour-system inconsistencies found

| # | Finding | Impact |
|---|---|---|
| C1 | `AppColors.canvas = #FFFFFF` but 8+ screens hardcode `#FFFCF7` as the page background | two different light "canvases" |
| C2 | Two brand blues: `buttonSolid #1D4ED8` (theme/`PrimaryButton`) vs `primary #1A73E8` (`AppButton`) | inconsistent CTAs |
| C3 | Figma "Common button blue" documented as `#2563EB` | matches neither implementation |
| C4 | `AppColors.background #FFFFFF` duplicates `canvas`; `AppColors.surface #F5F7FB` duplicates nothing | redundant tokens |
| C5 | No snackbar / tab / navigation token exists at all | must be defined |
| C6 | `AppColors.darkBackground/#121212`, `darkSurface/#1E1E1E`, `darkOnBackground/#FFFFFF` are three placeholder tokens, not a design system | unusable as a Dark spec |

These are pre-existing. Fixing C1/C2/C3/C4 would change Light Mode appearance and
therefore requires explicit approval; they are recorded, not fixed.

---

## 4. Existing fixes — verified present

### 4.1 Global white input-field fix — PRESENT

`app_theme.dart` lines 97–138:

- `filled: true`
- `fillColor: inputFillColor ?? surfaceColor`, with `AppTheme.light` passing
  `inputFillColor: AppColors.canvas` (`#FFFFFF`)
- `enabledBorder` / `border` = `#D0D0D0`, radius 16
- `focusedBorder` = `#1D4ED8` @ 1.5px
- `errorBorder`/`focusedErrorBorder` = `#E53935`
- `disabledBorder` = `#E0E4EA`

Guard test: `test/core/theme/input_theme_test.dart` (4 tests).
**This fix must be preserved byte-for-byte in Light Mode.**

### 4.2 Hero signature underline fix — PRESENT

`app_typography.dart` `AppTypography.signature(...)` sets
`decoration: TextDecoration.none` with the explanatory comment for the
`_errorTextStyle` yellow double-underline during Hero shuttle re-parenting.

Guard test: `test/responsive/brand_signature_hero_underline_test.dart`
(1 test, passes at baseline).

### 4.3 Conflict introduced by the new Owner decision

`test/core/theme/input_theme_test.dart:106` asserts:

```dart
expect(app.darkTheme, isNull, reason: 'the app must not ship a dark theme');
expect(app.themeMode, isNot(ThemeMode.dark));
```

That assertion encodes the **superseded** decision. It must be rewritten in
Phase 2 to assert the new contract (Light fields still white, Dark fields
readable, OS appearance cannot break either), while every Light-mode assertion
in the same file stays unchanged. Deleting it is not acceptable; it is the only
regression guard on the original bug.

### 4.4 Existing Light-mode baseline assets

- Goldens: `test/features/authentication/.../goldens/name_screen_393x852.png`,
  `test/video_streaming/goldens/player_layout_360x740.png`,
  `test/video_streaming/goldens/player_layout_393x852.png`.
- Responsive tests: auth screens, splash, user type selection, welcome, safe area.

---

## 5. Test-suite baseline (before any change)

Command: `flutter test` (full suite, run at HEAD + current working tree).

```
03:14 +467 ~4 -52: Some tests failed.
```

| Metric | Count |
|---|---:|
| Passed | 467 |
| Skipped | 4 |
| Failed | 52 |

`flutter analyze`: **No issues found! (ran in 50.6s)** — baseline is clean.

### 5.1 Failure classification — ALL PRE-EXISTING

Reproduced on the untouched working tree **before any edit**, so none of these
are introduced by this mission.

| Failing test file | Failures | Classification |
|---|---:|---|
| `test/responsive/user_type_selection_responsive_test.dart` | 19 | Pre-existing — harness/layout |
| `test/responsive/splash_brand_signature_test.dart` | 16 | Pre-existing — harness/layout |
| `test/responsive/user_type_selection_safe_area_test.dart` | 6 | Pre-existing — layout overflow |
| `test/student_profile/student_profile_navigation_test.dart` | 4 | Pre-existing — missing GoRouter in test harness |
| `test/student_home/student_home_test.dart` | 4 | Pre-existing — `AppLocalizations.of` null without delegates (`_BottomPill`) |
| `test/video_streaming/player_layout_test.dart` | 2 | Pre-existing — golden pixel drift (2.19% / 2.24%) |
| `test/widget_test.dart` | 1 | Pre-existing — navigation timing |

Representative messages:

```
The following assertion was thrown running a test: No GoRouter found in context
The following _TypeError was thrown building _BottomPill(...): Null check operator used on a null value
A RenderFlex overflowed by 55 pixels on the bottom.
Golden "goldens/player_layout_393x852.png": Pixel test failed, 2.19%, 7339px diff detected.
Golden "goldens/player_layout_360x740.png": Pixel test failed, 2.24%, 5974px diff detected.
```

**Consequence for Phase 9:** this mission may not claim "all tests pass". The
acceptance bar is: the 467 passing tests stay passing, no new failures are
introduced, and the 52 pre-existing failures remain classified and unchanged
(except where this mission legitimately fixes one).

---

## 6. Documentation approval status

| Document | Version | Status | Authoritative? |
|---|---|---|---|
| `00_MASTER_ARCHITECTURE.md` | 2.1 | **Approved** | YES — highest authority |
| `01_Project_Vision.md` | 2.1 | **Approved** | YES |
| `02_Product_Requirements__PRD.md` | 1.4 | **Approved** | YES |
| `03_UI_UX.md` | 1.1 | Draft | NO |
| `04_FEATURES.md` | 2.0 | **Approved** | YES |
| `05 Database 1.8.md` | 1.10 | Proposed | NO |
| `06_FIREBASE_ARCHITECTURE` | 1.4 | Draft | NO |
| `07_FLUTTER_ARCHITECTURE.md` | 1.3 | Draft | NO |
| `08_DEVELOPMENT_STANDARDS.md` | 1.3 | Draft | NO |
| `09_TASKS.md` | 1.3 | Draft | NO |
| `10_Bugs.md` | 1.0 | Draft | NO |
| `11_Assets.md` | 1.1 | Draft | NO |
| `12 AI Prompts.md` | 1.1 | Draft | NO |
| `13_Releases.md` | 1.1 | Draft | NO |
| `14_Platform_Availability_...` | 1.1 | Draft | NO |
| `15_Admin_Permissions_...` | 1.1 | Draft | NO |
| `FINAL_DECISIONS.md` | 2.1 | **Approved** | YES |
| `Dr_Tarek_Figma_Design_Specification.md` | (unnumbered extract) | no status field | reference only |

ADR files: `16_ADR_003` Approved, `17_ADR_006` Approved, `18_ADR_007` Approved,
`19_ADR_008` untracked (new, not yet committed).

**Critical governance finding G1:** `07_FLUTTER_ARCHITECTURE.md` and
`08_DEVELOPMENT_STANDARDS.md` — the two documents that would normally define
theme and coding conventions — are **Draft**, so they are not authoritative
implementation references. Implementation must therefore follow the Approved
documents plus the existing codebase conventions. Notably
`07_FLUTTER_ARCHITECTURE.md:60` already anticipates
`theme/ # Material 3 theme, dark/light mode (Vision: Dark/Light Ready)`, which
matches this mission.

**Critical governance finding G2:** `03_UI_UX.md` — the document that owns
screen visual specifications — is **Draft**, and explicitly covers Feature 01
only. No approved document currently owns a Dark Mode visual specification.

---

## 7. Documented conflicts

| ID | Conflict | Documents | Resolution path |
|---|---|---|---|
| X1 | `White-based UI` vs `Dark Mode Ready` / `Light Mode Ready` | MA §8 and FINAL_DECISIONS §9 vs Vision | Amendment A/C/D + ADR-009 |
| X2 | "Ready" is ambiguous (ships vs prepared) | Vision | Amendment D |
| X3 | Light canvas is `#FFFFFF` in the theme but `#FFFCF7` in Figma/screens | `app_colors.dart` vs Figma | Recorded (C1); semantic layer must expose both values; no visual change |
| X4 | Three different primary blues | code (`#1D4ED8`, `#1A73E8`) vs Figma (`#2563EB`) | Recorded (C2/C3); Owner decision D8 |
| X5 | `11_Assets.md` dark tokens (`#121212/#1E1E1E`) vs the fact that no Dark design exists | Draft 11 vs reality | Amendment F, after D2 |
| X6 | `input_theme_test.dart` asserts no dark theme, while the Owner now requires one | test vs decision | Rewrite test in Phase 2 (contract change, not coverage loss) |
| X7 | `15_Admin_Permissions` checklist asks for Dashboard dark mode | Draft 15 vs mission scope | Out of scope; Phase 7 scope decision D6 |
| X8 | `teacher` file/screen names remain (`teacher_admin_selection_screen`, `avatarTeacherRing`) | ADR-005 target vs code | Out of scope for a theme mission; recorded |

None of these were silently resolved.

---

## 8. Figma & design-system inventory

- `docs/figma/app/design system.md` — Light tokens, typography, spacing, radius,
  3 components (primary button, course card, glass variant). **Light only.**
- `docs/figma/app/` — 10 Light-mode screen specifications (9 with PNGs:
  splash and picker overlay are Markdown-only).
- `docs/figma/dashboard/` — 10 specs; management Dashboard, separate app.
- `docs/notion/Dr_Tarek_Figma_Design_Specification.md` — MCP extract of file
  `N4XUVx81rLxVOADK5PB0Kd`, listing 15 top-level frames (adds
  `current Student - sign in`, `Student - home`, carousel and avatar sections).
- Dark specifications: **0**.
- Design-system version: no version field exists; the file has no status field,
  so it is a reference extract, not an Approved document.
- Assets: 10 raster illustration PNGs + 12 SVGs in `assets/images/`; no Dark
  variants; `11_Assets.md` (Draft) does list an anticipated "App Logo (Dark)".

---

## 9. Deliverables prepared in this phase

| File | Purpose | Status |
|---|---|---|
| `20_ADR_009_Theme_Mode_Support.md` | ADR proposing genuine Light/Dark/System support | **Proposed** |
| `docs/theme-migration/DOCUMENTATION_AMENDMENTS_PROPOSAL.md` | Exact before/after text for MA §8/§5.3, FINAL_DECISIONS §9, Vision, 03, 11 | **Proposed** |
| `docs/theme-migration/PHASE_1_DARK_DESIGN_PROPOSAL.md` | Dark tokens, measured contrast, grade alternatives, glass, component states, asset strategy, 48-row screen coverage matrix | **Proposed** |
| `docs/theme-migration/PHASE_0_BASELINE.md` | This report | Final |
| `docs/theme-migration/GIT_BASELINE_*.txt` | Working-tree snapshot | Final |

No approved document and no production file was modified.

---

## 10. Exit-gate checklist

- [x] Current repository baseline recorded (git head, branch, 47 modified,
      1,750/884 diff, 7 pre-existing untracked)
- [x] Existing uncommitted changes protected (snapshots written; no file
      overwritten; theme files noted as already dirty)
- [x] Documentation approval statuses verified (5 Approved, 1 Proposed, 11 Draft)
- [x] Theme conflicts documented (X1–X8)
- [x] Proposed ADR prepared (ADR-009, Status: Proposed)
- [x] Proposed documentation amendments prepared (A–G, exact text)
- [x] Existing Light Mode baseline tests identified (467 pass / 52 pre-existing
      fail / 4 skipped; analyze clean)
- [x] Existing Hero and input fixes confirmed (code + guard tests)
- [x] Phase 1 Dark design proposal prepared for approval

---

## 11. Phase status

`9. NOT_STARTED → IN_PROGRESS → VALIDATING` — all Phase 0 work items complete.

**Final status: VALIDATING → BLOCKED at the mandatory approval gate.**

Blocking reasons (all governance/design, none technical):

1. **D1** — ADR-009 and amendments A–G require explicit Owner approval. Master
   Architecture §5.1/§15 forbid applying architectural changes silently.
2. **D2–D5, D8, D9** — the Dark visual specification requires Owner/Design
   approval. Phase 1 exit requires "Project owner explicitly approves the visual
   specifications", and the mission forbids inventing Dark visual design.
3. **D7** — 37 of 48 screens have neither a Light nor a Dark Figma specification.
   Under the mission rules those screens cannot be marked VERIFIED and must be
   BLOCKED without an Owner decision on how they are specified.
4. **Environment** — no Figma MCP and no physical iOS/Android device, so live
   Figma comparison and device verification are impossible in this environment.

Phase 2 cannot start until D1 and D2 are approved, because Phase 2 requires the
Dark input contract to "come from approved Figma tokens".
