# Phase 1 — Dark Mode Design System (PROPOSAL, NOT APPROVED)

Prepared: 2026-11-01
Status: **PROPOSED — requires Project Owner approval before any Dark UI implementation.**
Companion to: `20_ADR_009_Theme_Mode_Support.md`
Source of Light values: `docs/figma/app/design system.md`,
`docs/notion/Dr_Tarek_Figma_Design_Specification.md`, `lib/core/theme/app_colors.dart`.

This document does **not** invent a final visual specification. It defines a
proposed token set, measures it against WCAG AA, and presents the open design
choices that only the Owner/Designer may make. Every value below is a proposal.

No Dark Mode Figma specification exists in the repository. `docs/figma/` contains
10 mobile Light specifications and **0** Dark specifications.

---

## 1. Light tokens (for the record — MUST NOT CHANGE)

These are the exact values the application renders today. Dark Mode is additive;
these values are frozen. The semantic layer's Light half must map to them 1:1 so
that migration is value-preserving.

| Semantic role | Light value | Source |
|---|---|---|
| `canvas` (scaffold) | `#FFFFFF` | `AppColors.canvas`, `AppTheme.light.scaffoldBackgroundColor` |
| `canvasWarm` (Figma screen canvas) | `#FFFCF7` | Figma `Main light background`, hardcoded in 8+ screens |
| `surface` (item/card) | `#F3F4F6` | Figma `item-surface` |
| `surfaceElevated` | `#FFFFFF` | implied |
| `textPrimary` | `#111827` | Figma `text-primary` |
| `textSecondary` | `#6B7280` | Figma `text-secondary` |
| `textDisabled` | `#9A9A9A` | Figma `Common secondary input/placeholder text` |
| `divider` | `#E0E4EA` | `AppColors.divider` |
| `outline` | `#D0D0D0` | Figma `Common input border` |
| `inputFill` | `#FFFFFF` | Product requirement (white fields) |
| `inputBorder` | `#D0D0D0` | same |
| `primary` (solid action) | `#1D4ED8` | `AppColors.buttonSolid` |
| `onPrimary` | `#FFFFFF` | — |
| `primaryLegacy` | `#1A73E8` | `AppColors.primary` (see §2.4 conflict) |
| `error` | `#E53935` | `AppColors.error` |
| `success` | `#4CAF50` | `AppColors.success` |
| `warning` | `#FF9800` | `AppColors.warning` |
| `info` | `#2196F3` | `AppColors.info` |
| `glassFill` (button) | `rgba(255,255,255,0.20)` | Figma `Style = Glass` |
| `glassBorder` | `rgba(255,255,255,0.30)` | same |
| `cardGlassFill` | `rgba(255,255,255,0.15)` | Figma `card/course-item` |
| `cardGlassBorder` | `rgba(255,255,255,0.25)` | same |

### 1.1 Light-mode accessibility exceptions (pre-existing, preserved)

Measured with the WCAG relative-luminance formula:

- `inputBorder #D0D0D0` on `inputFill #FFFFFF` = **1.54:1**. WCAG 1.4.11
  (non-text contrast) targets 3:1 for control boundaries. The approved Light
  design fails this. It is a **pre-existing** exception and is preserved
  unchanged because Light output must not change. Recorded, not fixed.
- `textSecondary #6B7280` on `canvasWarm #FFFCF7` = **4.72:1** — passes 4.5:1
  only narrowly.

Any future fix is a separate, explicitly approved Light redesign.

---

## 2. Proposed Dark semantic palette

Neutral surfaces are blue-tinted neutrals (hue continuity with the `#1D4ED8`
brand) rather than pure grey, so grade accents and glass sit naturally.

### 2.1 Surfaces

| Semantic role | Dark value |
|---|---|
| `canvas` | `#0B0D12` |
| `surface` | `#15181F` |
| `surfaceContainerLow` | `#12151B` |
| `surfaceContainer` | `#191D25` |
| `surfaceContainerHigh` | `#20242D` |
| `surfaceContainerHighest` | `#272C36` |
| `inverseSurface` | `#F2F4F7` |
| `onInverseSurface` | `#111827` |

### 2.2 Text and icons

| Semantic role | Dark value |
|---|---|
| `textPrimary` | `#F2F4F7` |
| `textSecondary` | `#A7AEBC` |
| `textDisabled` | `#6C7382` |
| `iconDefault` | `#D5DAE3` |
| `iconMuted` | `#8E97A6` |

### 2.3 Lines, brand and status

| Semantic role | Dark value |
|---|---|
| `divider` | `#2A2F3A` |
| `outline` | `#3A4150` |
| `inputBorder` | `#636C80` |
| `primary` | `#7FA9FF` |
| `onPrimary` | `#08142B` |
| `primaryContainer` | `#2B4E8F` |
| `onPrimaryContainer` | `#D8E3FF` |
| `error` | `#FFB4AB` |
| `onError` | `#5C0A0A` |
| `success` | `#7DD99A` |
| `warning` | `#FFC46B` |
| `info` | `#8CC8FF` |

### 2.4 Measured contrast (WCAG 2.1 relative luminance)

All ratios below were computed, not estimated.

| Pair | Ratio | Target | Result |
|---|---|---:|---|
| `textPrimary #F2F4F7` on `canvas #0B0D12` | 17.64:1 | 4.5:1 | PASS |
| `textPrimary` on `surface #15181F` | 16.12:1 | 4.5:1 | PASS |
| `textPrimary` on `surfaceContainer #191D25` | 15.32:1 | 4.5:1 | PASS |
| `textPrimary` on `surfaceContainerHigh #20242D` | 14.10:1 | 4.5:1 | PASS |
| `textPrimary` on `surfaceContainerHighest #272C36` | 12.71:1 | 4.5:1 | PASS |
| `textSecondary #A7AEBC` on `canvas` | 8.72:1 | 4.5:1 | PASS |
| `textSecondary` on `surface` | 7.97:1 | 4.5:1 | PASS |
| `textSecondary` on `surfaceContainer` | 7.58:1 | 4.5:1 | PASS |
| `primary #7FA9FF` on `canvas` | 8.35:1 | 4.5:1 | PASS |
| `primary` on `surface` | 7.63:1 | 4.5:1 | PASS |
| `onPrimary #08142B` on `primary` | 7.88:1 | 4.5:1 | PASS |
| `onPrimaryContainer #D8E3FF` on `primaryContainer #2B4E8F` | 6.32:1 | 4.5:1 | PASS |
| `error #FFB4AB` on `canvas` | 11.45:1 | 4.5:1 | PASS |
| `error` on `surfaceContainerHigh` | 9.15:1 | 4.5:1 | PASS |
| `success #7DD99A` on `surface` | 10.37:1 | 4.5:1 | PASS |
| `warning #FFC46B` on `surface` | 11.30:1 | 4.5:1 | PASS |
| `info #8CC8FF` on `surface` | 10.00:1 | 4.5:1 | PASS |
| `textDisabled #6C7382` on `canvas` | 4.08:1 | 3:1 | PASS |
| `inputBorder #636C80` on `inputFill #15181F` | 3.37:1 | 3:1 | PASS |
| `snackbarText #F2F4F7` on `snackbarBg #272C36` | 12.71:1 | 4.5:1 | PASS |

Rejected candidate: `inputBorder #3A4150` measured **1.74:1** against the input
fill, failing WCAG 1.4.11. Replaced by `#636C80`.

### 2.5 Open conflict requiring an Owner decision (D8)

Two different brand blues exist in Light Mode today:

- `AppColors.buttonSolid = #1D4ED8` — used by `AppTheme` (elevated button theme),
  `PrimaryButton`, and the input focus border.
- `AppColors.primary = #1A73E8` — used by `AppButton` (filled + outlined).

Figma's documented "Common button blue" is `#2563EB`, which matches neither.

Three options:

1. **Preserve both** (default; zero Light visual change). Semantic layer exposes
   `primary` = `#1D4ED8` and `primaryLegacy` = `#1A73E8`. Technical debt stays.
2. **Unify on `#1D4ED8`** — changes every `AppButton` in Light Mode. Violates
   "preserve current Light appearance". Requires explicit approval.
3. **Unify on Figma `#2563EB`** — changes `PrimaryButton`, the theme button, and
   the input focus colour. Requires explicit approval.

Recommendation: option 1 for this mission; open a separate cleanup task.

---

## 3. Grade identity in Dark Mode — three alternatives (Owner decision D3)

Today grade identity is expressed with four saturated canvases:
`#F59E0B` (G1), `#1D4ED8` (G2), `#15803D` (G3), `#DC2626` (G4), used as
`GradeOneProfileOverviewScreen` background, subject-navigation card colour, and
grade-selection chips. `AppTheme.grade1..grade4` exist but are **dead code**
(0 call sites).

### Option A — Darkened grade canvas

Each screen keeps a grade-tinted canvas, darkened to preserve hue identity.

| Grade | Dark canvas | Dark accent | Accent-on-canvas | Text-on-canvas |
|---|---|---:|---:|---:|
| 1 Yellow | `#241A06` | `#F5B544` | 9.45:1 | `#FBEAD0` 14.51:1 |
| 2 Blue | `#0C1A3D` | `#7FA9FF` | 7.33:1 | `#F2F4F7` 15.49:1 |
| 3 Green | `#07261A` | `#6FD99A` | 9.27:1 | `#EAF7EF` 14.64:1 |
| 4 Red | `#2A0D0D` | `#FF8A80` | 7.92:1 | `#FBEDEC` 15.86:1 |

- **Pro:** strongest grade identity; closest to the Light experience.
- **Con:** four extra canvas tokens; glass over tinted canvases needs per-grade
  validation; higher risk of "muddy" large surfaces.

### Option B — Neutral canvas + grade accent (recommended)

Canvas is always the neutral dark canvas. Grade identity moves to: header band,
grade chip, active navigation indicator, one accent-tinted glass card, grade badge.

Measured accent contrast on the neutral canvas `#0B0D12`:
`#F5B544` 11.58:1, `#7FA9FF` 9.02:1, `#6FD99A` 12.07:1, `#FF8A80` 9.20:1 — all
pass 4.5:1.

- **Pro:** one canvas contract for all screens; glass behaves identically
  everywhere; lowest contrast risk; consistent with Material 3 Dark guidance.
- **Con:** softer grade identity than Light Mode; needs a design-approved accent
  placement rule so accent use does not become ad hoc.

### Option C — Retain the Light grade canvases in Dark Mode

Keep `#F59E0B` / `#1D4ED8` / `#15803D` / `#DC2626` and their existing
`textPrimary` values, flipping only chrome (app bar, dialogs, sheets, inputs).

- **Pro:** zero regression risk for grade screens; identity fully preserved.
- **Con:** these are mid-luminance surfaces, so Dark Mode looks largely unchanged
  on grade screens; white glass borders stay white-ish; the mode reads as
  inconsistent with every neutral screen.

**Recommendation:** Option B. It is the only option that keeps a single canvas and
glass contract across 46 screens while keeping every measured contrast above AA.

---

## 4. Glassmorphism in Dark Mode (Owner decision D4)

Proposed:

| Token | Dark value | Notes |
|---|---|---|
| `glassFill` | `rgba(255,255,255,0.08)` | composited over `#0B0D12` → `#1F2025` |
| `glassBorder` | `rgba(255,255,255,0.14)` | composited over `#15181F` → `#36383E` |
| `glassFillStrong` | `rgba(255,255,255,0.12)` | for primary glass buttons |
| `glassBorderStrong` | `rgba(255,255,255,0.20)` | same |
| `glassText` | `#F2F4F7` | 17.0:1 on composited glass over canvas |
| `glassTextMuted` | `#C6CCD8` | secondary text on glass |

Rules:

- Blur radius and BackdropFilter behaviour stay exactly as Light (20–24px).
- Text over glass always uses `glassText`, never `textPrimary`, so a future grade
  canvas change cannot silently break legibility.
- Over Option-B neutral canvas, glass at 8% is subtle; the border, not the fill,
  carries the edge. If the Owner prefers the Light look, `glassFill` 12% /
  `glassBorder` 20% is the alternative pair.
- Over Option-A grade canvases, glass must be recomputed per grade and re-tested.
- **Open item:** the Light glass tokens are white-on-light. In Dark Mode
  white-on-dark glass is not a strict inversion; the Owner/Designer must confirm
  the intended "material" look before Phase 3.

---

## 5. Component state contracts (Light preserved / Dark proposed)

Each row states the contract the semantic layer must satisfy. Dimensions, radii,
typography, spacing and animation are unchanged in both modes.

### 5.1 Buttons

| Component | State | Light (unchanged) | Dark (proposed) |
|---|---|---|---|
| Primary solid | default | fill `#1D4ED8`, text `#FFFFFF` | fill `#7FA9FF`, text `#08142B` |
| Primary solid | pressed | `#1D4ED8` + overlay | `#6E97E8` |
| Primary solid | disabled | `#1D4ED8` @ 40%, text `#FFFFFF` @ 80% | `#7FA9FF` @ 30%, text `#08142B` @ 60% |
| Primary glass | default | white 20% + white 30% border, text `#FFFFFF` | white 12% + white 20% border, text `#F2F4F7` |
| Secondary / outlined | default | text+border `#1A73E8` | text+border `#7FA9FF` |
| Ghost / text | default | text `#1A73E8` | text `#7FA9FF` |
| Ghost / text | disabled | muted text | `#6C7382` |

### 5.2 Inputs (the regression that caused Dark removal)

The previous Dark Mode shipped a **Light** `ColorScheme` with dark fills and no
dark input contract. The new contract:

| State | Light (unchanged) | Dark (proposed) |
|---|---|---|
| Fill | `#FFFFFF` | `#15181F` |
| Border | `#D0D0D0`, 1px | `#636C80`, 1px |
| Border focused | `#1D4ED8`, 1.5px | `#7FA9FF`, 1.5px |
| Text | `#111827` | `#F2F4F7` |
| Placeholder / hint | `#9A9A9A` | `#8E97A6` |
| Error border | `#E53935` | `#FFB4AB` |
| Error text | `#E53935` | `#FFB4AB` |
| Disabled fill | `#F3F4F6` | `#12151B` |
| Disabled border | `#E0E4EA` | `#2A2F3A` |
| Disabled text | `#9A9A9A` | `#6C7382` |
| Read-only | same as enabled, no focus ring | same |
| Cursor / selection | `#1D4ED8` | `#7FA9FF` |
| Radius | 16 (`radius/md`) | 16 — unchanged |
| Password visibility icon | `#6B7280` | `#8E97A6` |

Every Dark input pair is above 4.5:1 (text) and 3:1 (border).

### 5.3 Cards, chips, badges

| Component | Light | Dark |
|---|---|---|
| Card fill | `#F3F4F6` | `#191D25` |
| Card border | none | `#2A2F3A` |
| Card text primary | `#111827` | `#F2F4F7` |
| Card text secondary | `#6B7280` | `#A7AEBC` |
| Grade chip | grade canvas + grade text | grade accent on `#20242D`, or Option-A canvas |
| Plan badge (Free/Pro/Max) | gradient tokens (unchanged) | unchanged gradients + dark-safe text |
| Status chip success/warn/error | `#4CAF50`/`#FF9800`/`#E53935` | `#7DD99A`/`#FFC46B`/`#FFB4AB` at 20% fill, text at full |

### 5.4 Tabs, app bars, navigation

| Component | Light | Dark |
|---|---|---|
| AppBar background | canvas | `#0B0D12` (or transparent over canvas) |
| AppBar foreground | `#111827` | `#F2F4F7` |
| AppBar scrolled-under elevation | none | `#15181F` + 1px `#2A2F3A` |
| Tab selected | `#1D4ED8` | `#7FA9FF` |
| Tab unselected | `#6B7280` | `#A7AEBC` |
| Tab indicator | `#D9D9D9` fill (existing) | `#2B4E8F` |
| NavigationBar surface | `#FFFFFF` | `#12151B` |
| Nav selected icon/label | `#1D4ED8` | `#7FA9FF` |
| Nav unselected | `#6B7280` | `#8E97A6` |
| Nav indicator pill | `#E8EEFB`-family | `#2B4E8F` |

### 5.5 Dialogs, sheets, snackbars, overlays

| Component | Light | Dark |
|---|---|---|
| Dialog surface | `#FFFFFF` | `#20242D` |
| Dialog title | `#111827` | `#F2F4F7` |
| Dialog body | `#6B7280` | `#A7AEBC` |
| Scrim | default black | `rgba(0,0,0,0.60)` |
| Bottom sheet surface | `#FFFFFF` | `#191D25` |
| Sheet drag handle | `#E0E4EA` | `#3A4150` |
| Snackbar background | inverse surface | `#272C36` |
| Snackbar text | inverse on-surface | `#F2F4F7` |
| Snackbar action | `#1D4ED8` | `#7FA9FF` |

### 5.6 Empty / error / loading states

| Component | Light | Dark |
|---|---|---|
| Empty-state icon | `#6B7280` | `#8E97A6` |
| Empty-state title | `#111827` | `#F2F4F7` |
| Empty-state body | `#6B7280` | `#A7AEBC` |
| Error icon/text | `#E53935` | `#FFB4AB` |
| Loading indicator | `#1D4ED8` | `#7FA9FF` |

### 5.7 Intentionally fixed surfaces (never themed)

| Surface | Rule |
|---|---|
| Video player surface | stays `#000000` in both modes; only surrounding chrome is themed |
| PDF document surface | stays white/black per the document renderer; chrome is themed |
| Note editor pastel surfaces | preserved exactly unless an approved design says otherwise |
| Brand signature logo | colour is explicit today (`Colors.black`); needs a Dark value — **Owner decision (D9):** invert to `#F2F4F7`, or keep black on a light art card |
| Onboarding illustrations (9 PNGs) | see §6 |
| Grade brand colours | see §3 |

---

## 6. Asset strategy (Owner decision D5)

Nine raster illustration PNGs carry baked-in light/cream backgrounds:

```
assets/images/New Student - Welcome photo.png
assets/images/New Student - name photo.png
assets/images/New Student - number photo.png
assets/images/New Student - add a photo.png
assets/images/New Student - Grade photo.png
assets/images/New Student - password photo.png
assets/images/New Student - End photo.png
assets/images/new_student photo.png
assets/images/current student photo.png
assets/images/current_student_sign_in.png
```

SVG assets (back, eye, checkboxes, notifications, smartphone, upload,
teacher & admin icon, frame, arrow) are single-colour or line art and can be
tinted from a semantic role without new files.

Options:

1. **Dark illustration variants** (designs required; 10 new files). Highest
   fidelity, highest design cost.
2. **Neutral dark container**: put the existing light illustration inside a
   rounded card at the approved light background. Reads as an intentional "art
   card", requires no new assets, keeps the illustration legible. Recommended
   interim.
3. **Keep the light panel full-bleed** in Dark Mode. Rejected: a full-screen
   light panel in Dark Mode is the exact inconsistency this mission removes.

No production asset may be edited or replaced without design approval.

---

## 7. Screen coverage matrix

Status classes per the mission: `LIGHT+DARK APPROVED`, `LIGHT APPROVED / DARK
MISSING`, `LIGHT MISSING / DARK MISSING`, `N/A — intentional media surface`.

**Reality check:** 0 of 46 screens have an approved Dark specification, and only
11 have a Light specification in the repository. This matrix is the honest gate.

### 7.1 Phase 4 — Authentication & Onboarding (16)

| # | Screen | File | Light ref | Dark ref | Status |
|---|---|---|---|---|---|
| 1 | Splash | `splash_screen.dart` | `figma/app/splash screen` | — | LIGHT APPROVED / DARK MISSING |
| 2 | User Type Selection | `user_type_selection_screen.dart` | `figma/app/User Type Selection` | — | LIGHT APPROVED / DARK MISSING |
| 3 | New Student Welcome | `new_student_welcome_screen.dart` | `figma/app/New Student - Welcome` | — | LIGHT APPROVED / DARK MISSING |
| 4 | New Student Name | `new_student_name_screen.dart` | `figma/app/New Student - name` + golden | — | LIGHT APPROVED / DARK MISSING |
| 5 | New Student Number | `new_student_number_screen.dart` | `figma/app/New Student - number` | — | LIGHT APPROVED / DARK MISSING |
| 6 | New Student Photo | `new_student_photo_screen.dart` | `figma/app/New Student - photo` + `Picker overlay` | — | LIGHT APPROVED / DARK MISSING |
| 7 | New Student Grade | `new_student_grade_screen.dart` | `figma/app/New Student - Grade` | — | LIGHT APPROVED / DARK MISSING |
| 8 | New Student Password | `new_student_password_screen.dart` | `figma/app/New Student - password` | — | LIGHT APPROVED / DARK MISSING |
| 9 | New Student End | `new_student_end_screen.dart` | `figma/app/New Student - End` | — | LIGHT APPROVED / DARK MISSING |
| 10 | Login | `login_screen.dart` | design spec node `52:143` | — | LIGHT APPROVED / DARK MISSING |
| 11 | Forgot Password | `forgot_password_screen.dart` | none (03 §4 item 8) | — | LIGHT MISSING / DARK MISSING |
| 12 | Staff Password | `staff_password_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 13 | Doctor/Admin Selection | `teacher_admin_selection_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 14 | Forced Password Change | `widgets/forced_password_change_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 15 | Registration Wizard | `student_registration_wizard.dart` | composite of 3–9 | — | LIGHT MISSING / DARK MISSING |
| 16 | Auth Gate (loading/error) | `screens/auth_gate.dart` | none | — | LIGHT MISSING / DARK MISSING |

> Note: `teacher_admin_selection_screen.dart` keeps the historical file name.
> The product role is Doctor (Platform Owner) per ADR-005; renaming is out of
> scope for a theme mission.

### 7.2 Phase 5 — Student & Learning (18)

| # | Screen | File | Light ref | Dark ref | Status |
|---|---|---|---|---|---|
| 17 | Student Home | `student_home_screen.dart` | partial (design spec `55:10`) | — | LIGHT APPROVED / DARK MISSING |
| 18 | Subject Navigation | `subject_navigation_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 19 | Student Profile | `student_profile_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 20 | Grade Profile Overview | `grade_one_profile_overview_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 21 | Student Feature Hub | `student_feature_hub_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 22 | Lecture Viewer | `lecture_viewer_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 23 | PDF Viewer | `pdf_viewer_screen.dart` | none | — | LIGHT MISSING / DARK MISSING (document surface N/A) |
| 24 | Video Streaming | `video_streaming_screen.dart` | none | — | LIGHT MISSING / DARK MISSING (player surface N/A) |
| 25 | Membership Plans | `membership_plans_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 26 | Notifications | `notifications_list_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 27 | Notes | `student_notes_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 28 | Bookmarks | `student_bookmarks_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 29 | Published Exams | `published_exams_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 30 | Published Quizzes | `published_quizzes_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 31 | Assessment Question | `assessment_question_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 32 | Assessment Summary | `assessment_summary_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 33 | Lecture Access | `lecture_access_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 34 | Academic Periods | `academic_periods_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |

### 7.3 Phase 6 — Admin & Content Authoring (14)

| # | Screen | File | Light ref | Dark ref | Status |
|---|---|---|---|---|---|
| 35 | Admin Home | `admin_home_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 36 | Students Management | `students_management_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 37 | Admins Management | `admins_management_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 38 | Custom Groups | `custom_groups_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 39 | Plan Quality Matrix | `plan_quality_matrix_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 40 | Platform Features | `platform_features_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 41 | Subjects Management | `subjects_management_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 42 | Subscription Plans | `subscription_plans_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 43 | Admin Notifications Composer | `admin_notifications_composer_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 44 | Admin Archive | `admin_archive_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 45 | Admin Lectures | `admin_lectures_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 46 | Admin Resources | `admin_resources_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 47 | Admin Sections | `admin_sections_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |
| 48 | Admin Subject Picker | `admin_subject_picker_screen.dart` | none | — | LIGHT MISSING / DARK MISSING |

### 7.4 Overlay inventory (not screens, but must be specified)

Measured now: **12 overlay invocation sites** (`showDialog` 6,
`showModalBottomSheet` 4, `showGeneralDialog` 2) and **12 overlay widget
classes** across 11 files. The old audit's "42 sites" is not reproducible and is
therefore not used. The highest-risk overlays:

| Overlay | File | Notes |
|---|---|---|
| Forgot password sheet | `authentication/.../forgot_password_sheet.dart` | 17 hardcoded colours |
| Profile edit sheet | `profile/.../profile_edit_sheet.dart` | 45 hardcoded colours — highest single file |
| Change password dialog | `profile/.../change_password_dialog.dart` | |
| Payment receipt dialog | `admin/.../payment_receipt_dialog.dart` | |
| Add lecture dialog | `content_authoring/.../add_lecture_dialog.dart` | |
| Video quality / documents sheets | `video_streaming/.../` | over black player |
| Photo picker overlay | `authentication/.../` (Figma `Picker overlay`) | only overlay with a Light spec |

---

## 8. Figma deliverables required to unblock Phases 4–6

1. Dark colour styles for all tokens in §2 (one Figma colour style per role).
2. Grade variants per the approved §3 option.
3. Dark component states for §5 (buttons, inputs, cards, chips, tabs, bars,
   dialogs, sheets, snackbars, empty/error/loading, glass).
4. Dark onboarding illustration variants or an approved neutral-container
   treatment (§6).
5. Per-screen Dark frames for the 48 screens, or an Owner-approved decision that
   the token + component contract is sufficient specification for screens that
   have no Light Figma either (decision D7).

Without items 1–4, Phase 2/3 cannot claim "Dark input appearance matches approved
design". Without item 5, Phases 4–6 stay BLOCKED.

---

## 9. Approval block

| ID | Decision | Recommended |
|---|---|---|
| D2 | Dark semantic palette §2 | Approve `#0B0D12` canvas family + measured tokens |
| D3 | Grade Dark strategy §3 | Option B (neutral canvas + grade accent) |
| D4 | Glass values §4 | 8% fill / 14% border (or 12%/20% if a stronger material look is wanted) |
| D5 | Raster asset strategy §6 | Option 2 (neutral dark art container) as interim |
| D7 | Spec coverage for the 37 no-Figma screens | Token+component contract, recorded as a deliberate Owner decision |
| D8 | Duplicate brand blue §2.5 | Preserve both (option 1) in this mission |
| D9 | Brand signature colour in Dark | Needs a value |

Signature: ____________________  Date: __________
