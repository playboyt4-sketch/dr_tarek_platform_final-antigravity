# 03 UI & UX

## Dr. Tarek Platform

Version: 1.0
Status: Draft — pending Teacher (Platform Owner) review before "Approved". Covers Feature 01 (Authentication & Registration) only — remaining features are documented as they are delivered in Figma.

## Version History

- **1.0** (2026-08-04): Initial document. Transcribes the approved Figma onboarding flow (Student Type → Welcome → Full Name → Phone Number → Photo → Grade → Password → Application Under Review → Login → Dashboard placeholder) into a formal screen-by-screen specification, cross-referenced to 04 Features v1.4, 05 Database v1.6, and 11 Assets. Per Master Architecture Section 14 ("Never invent business rules... Never infer missing requirements"), only screens actually present in the supplied Figma are documented here; all other features remain `⛔ Blocked` pending their own Figma delivery (see 09 Tasks Section 3).

---

# 1. Purpose

This document is the visual and interaction specification for the platform's UI, screen by screen, as delivered in Figma. Per Master Architecture Section 8, **Figma is the only visual source of truth** — this document transcribes and cross-references that source, it does not replace it. Where this document and Figma disagree, Figma wins until this document is updated.

This document does not restate business rules already defined in 04 Features — each screen section links to the relevant rule instead of duplicating it (Master Architecture Section 9.1, Single Source of Truth).

---

# 2. Design System Reference

Full token definitions live in 11 Assets Section 5. Summary relevant to the screens below:

| Token | Value | Usage |
| --- | --- | --- |
| Background | Warm off-white (`AppColors.background` family) | Screen background across all onboarding screens |
| Primary CTA | Blue (`AppColors.primary`) | Primary buttons ("Next", "Login", "Finish", "Get started") |
| Grade One | `#FBBC05` | Grade-selection chip / grade-based accents |
| Grade Two | `#4285F4` | Grade-selection chip / grade-based accents |
| Grade Three | `#34A853` | Grade-selection chip / grade-based accents |
| Grade Four | `#EA4335` | Grade-selection chip / grade-based accents |
| Font | Cairo (per 11 Assets Section 5.2) | All text — must support Arabic glyphs for RTL (see Section 6, Open Items) |
| Corner Radius | `AppShapes.radiusLarge` (16) / `radiusXLarge` (24) | Cards, illustration containers, buttons |

**Component pattern observed across all onboarding screens:** full-bleed illustration/color panel at top (rounded corners, ~55–60% of viewport height) → headline (bold, large) → optional subtext → input field(s) or selection card(s) → single full-width primary button pinned above the input area.

---

# 3. Screen Specifications — Feature 01 (Authentication & Registration)

Cross-reference: 04 Features Section "Feature 01 — Authentication & Registration" (Main Flow → Registration, steps 1–10).

## 3.1 Screen: "I am a" (Student Type Router)

| Attribute | Detail |
| --- | --- |
| **Purpose** | Routes the user to Registration (New Student) or Login (Current Student). Not a data-collection step. |
| **Layout** | Two large tappable cards, stacked vertically: "طالب جديد" (yellow) and "طالب حالي" (red), each with an illustration. Platform branding ("Tarek El Araby", term label "2026–2027") shown at top/bottom. |
| **Fields** | None — selection only. |
| **Primary Action** | Tap a card → navigate. "طالب جديد" → Screen 3.2 (Welcome). "طالب حالي" → Screen 3.9 (Login). |
| **States** | Default only; no loading/error state (pure navigation). |
| **Business Rule Ref** | 04 Features, Registration step 1. |
| **Open Question** | The "2026–2027" label under the logo — confirm whether this is the `system_settings.current_term` value (admin-only per 05 Database Section 10) surfaced here as a read-only branding label, or purely static branding text. Flag for Teacher confirmation; does not block build (display-only either way). |

## 3.2 Screen: Welcome ("welcome to our society with…")

| Attribute | Detail |
| --- | --- |
| **Purpose** | Marketing/orientation interstitial before data collection begins. |
| **Layout** | Illustration panel (four-quadrant character grid) → headline → platform name → subtext ("Go pro to unlock our features") → single primary button. |
| **Fields** | None. |
| **Primary Action** | "Get started" → Screen 3.3. |
| **States** | Default only. |
| **Business Rule Ref** | None (no business rule attaches to a purely orientational screen). |
| **Open Question** | "Go pro to unlock our features" reads as a monetization/upsell message shown to every new registrant regardless of eventual `student_type`. Confirm this copy is intentional for all registrants (including students who will end up on Public Free / Center Free) or whether it should be conditional/removed. |

## 3.3 Screen: Full Name

| Attribute | Detail |
| --- | --- |
| **Purpose** | Collect `users.full_name`. |
| **Layout** | Illustration panel → headline "What's your name?" → single text field → primary button. |
| **Fields** | `Full Name` (text, required, label "Full Name", placeholder "Enter your full name"). |
| **Primary Action** | "Next" → Screen 3.4. |
| **States** | Default, Focused, Error (empty submit — exact copy TBD by Teacher/copy owner), Filled. |
| **Business Rule Ref** | 04 Features, Registration step 2; 05 Database `users.full_name`. |
| **Validation** | Non-empty required. Max length not specified in Figma — recommend a sane default (e.g. 100 chars) and flag as open item rather than inventing a hard business rule. |

## 3.4 Screen: Phone Number

| Attribute | Detail |
| --- | --- |
| **Purpose** | Collect `users.phone_number`. |
| **Layout** | Illustration panel → headline "Your phone number?" → single text field (numeric) → primary button. |
| **Fields** | `phone number` (numeric, required, label "phone number", placeholder "Enter your phone number"). |
| **Primary Action** | "Next" → Screen 3.5. |
| **States** | Default, Focused, Error (invalid format / already registered), Filled. |
| **Business Rule Ref** | 04 Features, Registration step 3; 08 Development Standards Section 2.1 (Egypt format `0100...`, no country code in V1); 04 Features Preconditions ("The phone number is not already registered"). |
| **Validation** | Must enforce Egyptian mobile format per 08 Development Standards — Figma does not show inline format hints; recommend adding a placeholder/mask (e.g. `01xxxxxxxxx`) when this screen is rebuilt in Presentation-Final. |

## 3.5 Screen: Add a Photo

| Attribute | Detail |
| --- | --- |
| **Purpose** | Collect optional `users.profile_photo`. |
| **Layout** | Illustration panel → headline "Add a photo" → circular dashed upload placeholder with `+` icon → primary button. |
| **Fields** | Photo upload (single image). |
| **Primary Action** | "Next" → Screen 3.6. Button is enabled with or without a photo (optional field, per 04 Features step 4 "optionally adds"). |
| **States** | Empty (dashed circle + `+`), Selected (thumbnail preview replaces placeholder), Uploading (if upload happens inline rather than on Finish — implementation detail for Presentation-Final), Error (unsupported format / oversized file). |
| **Business Rule Ref** | 04 Features, Registration step 4 (optional); 11 Assets Section 7.1 (image optimization: WebP preferred, target size). |
| **Open Question** | Max file size / dimensions for a student-uploaded profile photo is listed as an explicit open item in 11 Assets Section 11 ("Define maximum file sizes for student-uploaded attachments"). Must be resolved before Presentation-Final for this screen. |

## 3.6 Screen: Which Year Are You In? (Grade / الفرقة)

| Attribute | Detail |
| --- | --- |
| **Purpose** | Collect `users.grade` — self-selected by the student (per Teacher decision, 2026-08-04; see 04 Features v1.4, 05 Database v1.6). |
| **Layout** | Illustration panel → headline "Which year are you in?" → single-select radio list (4 options, first pre-selected in Figma — likely a default selection state, not a business default; confirm) → primary button. |
| **Fields** | Radio group: Grade one / Grade two / Grade three / Grade four → maps to `grade_one` / `grade_two` / `grade_three` / `grade_four`. |
| **Primary Action** | "Next" → Screen 3.7. |
| **States** | Default (one option selected — Figma shows "Grade one" pre-selected), Changed selection. |
| **Business Rule Ref** | 04 Features, Registration step 5; 05 Database `users.grade`; 11 Assets Section 5.1.1 (Grade Color Mapping). |
| **Design Note** | Figma renders this as a plain radio list with no grade-color accents. 11 Assets defines a distinct color per grade (Section 5.1.1) for use *elsewhere in the app* (content organization, badges, etc.) — Figma does not show these colors applied on this specific selection screen. Confirm with Teacher whether the grade colors should also appear here (e.g. as a colored dot/chip per row) or are reserved for post-registration screens only. |

## 3.7 Screen: Secure Your Account (Password)

| Attribute | Detail |
| --- | --- |
| **Purpose** | Collect and confirm the account password. |
| **Layout** | Illustration panel (shield/lock) → headline "Secure your account" → password field with visibility toggle → confirm-password field with visibility toggle → primary button. |
| **Fields** | `Enter password` (masked, with show/hide eye icon), `Re-Enter password` (masked, with show/hide eye icon). |
| **Primary Action** | "Finish" → Screen 3.8. |
| **States** | Default, Focused, Mismatch error (passwords don't match), Weak-password error (rule TBD), Success (submits registration). |
| **Business Rule Ref** | 04 Features, Registration step 6–7; 08 Development Standards Section 2.1 (Custom Token auth, no pseudo-email fallback). |
| **Open Question** | Minimum password strength rule is not specified anywhere in the approved documents. Must be defined (length/complexity) before this screen reaches Presentation-Final — flagging rather than inventing a rule. |

## 3.8 Screen: Application Under Review

| Attribute | Detail |
| --- | --- |
| **Purpose** | Confirms registration was submitted; account is in Waiting-for-Approval state. |
| **Layout** | Illustration panel (clock/magnifier) → headline "Application under review" → subtext "We are reviewing your application. You will be notified soon!" |
| **Fields** | None — terminal/informational screen. |
| **Primary Action** | None shown in Figma (no button). Recommend confirming whether this screen auto-dismisses, offers a "Back to Login" action, or is a dead-end until the student reopens the app. |
| **States** | Single static state. |
| **Business Rule Ref** | 04 Features, Registration steps 8–10 ("Waiting for Approval" state; "The student cannot access the platform"). |
| **Open Question** | No navigation action is visible on this screen in the current Figma. Needs a defined exit path (e.g., "Got it" → returns to Login) before Presentation-Final. |

## 3.9 Screen: Welcome Back (Login)

| Attribute | Detail |
| --- | --- |
| **Purpose** | Authenticate an existing/approved student. Reached from "طالب حالي" on Screen 3.1, or after closing the app post-registration. |
| **Layout** | Illustration panel (waving character) → headline "Welcome back!" → phone number field (icon-prefixed) → password field (icon-prefixed, visibility toggle) → "Forget password?" link → primary button. |
| **Fields** | `phone number`, `Password`. |
| **Primary Action** | "Login" → Screen 3.10 (Dashboard) on success. |
| **States** | Default, Focused, Invalid Credentials error, Waiting-for-Approval error, Rejected-Account error, Disabled-Account error, Login-from-Another-Device error (see 04 Features Alternative Flow). |
| **Secondary Action** | "Forget password?" → triggers 08 Development Standards Section 9 flow (admin-triggered password reset) — no screen for this flow has been supplied yet; flag as pending Figma. |
| **Business Rule Ref** | 04 Features, First Login + Alternative Flow (all five rejection cases). |

## 3.10 Screen: Dashboard (Placeholder Only)

| Attribute | Detail |
| --- | --- |
| **Purpose** | Post-login landing screen. |
| **Layout** | Personalized greeting ("Hi, tarek") + a single placeholder content card + platform name footer. |
| **Status** | **Not a real specification** — this Figma frame is a placeholder/stub, not the actual Student Dashboard design. The real Feature 02 (Student Dashboard) screen — subject carousel, notification icon, messages icon, per 04 Features — has not been supplied yet. |
| **Action Required** | Do not build Presentation-Final for the Dashboard from this frame. Wait for the real Figma screen. |

---

# 4. Cross-Document Open Items Summary

Consolidated from the "Open Question" rows above, for Teacher review in one place:

1. Confirm the "2026–2027" label's data source (Screen 3.1).
2. Confirm whether "Go pro to unlock our features" welcome copy applies to all registrants regardless of eventual plan (Screen 3.2).
3. Define max profile-photo file size/dimensions — already an open item in 11 Assets Section 11 (Screen 3.5).
4. Confirm whether the pre-selected "Grade one" radio default is a UI default or implies a business default grade (Screen 3.6).
5. Confirm whether per-grade colors (11 Assets Section 5.1.1) should appear on the grade-selection screen itself (Screen 3.6).
6. Define minimum password strength rule — not specified anywhere currently (Screen 3.7).
7. Define the exit action for "Application under review" (Screen 3.8).
8. Forgot-password screen(s) not yet supplied in Figma (Screen 3.9, secondary action).
9. Real Student Dashboard screen not yet supplied — current frame is a placeholder (Screen 3.10).
10. **Language/RTL:** All supplied Figma frames are in English LTR. FINAL_DECISIONS Section 9 specifies Arabic RTL support as a UI requirement. Confirm whether English is placeholder-only during design iteration and the shipped app will be Arabic RTL, or whether bilingual support is expected. This affects every screen above and should be resolved before Presentation-Final begins on any screen (per Master Architecture Section 15, Presentation-Final work starts together across features once 03 UI & UX is approved).

---

# 5. Status of Remaining Features

Per 09 Tasks Section 3, Presentation-Final for all other features (02–15) remains `⛔ Blocked` until their corresponding Figma screens are supplied. This document will be extended feature-by-feature as Figma delivery continues — it is not regenerated from scratch each time (Master Architecture Section 5: "Never regenerate completed documents").

---

END OF DOCUMENT
