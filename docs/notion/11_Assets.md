# 11 Assets

## Dr. Tarek Platform

Version: 1.0
Status: Draft — pending Teacher (Platform Owner) review before "Approved"

---

# 1. Purpose

This document serves as the central inventory and governance guide for all project assets — visual, audio, textual, and binary — used across the Dr. Tarek Platform. It defines asset categories, naming conventions, storage locations, access rules, version control, and optimization standards.

This document does not contain the assets themselves; those reside in:
- **Figma** — UI/UX designs, component libraries, design tokens (source of truth for visual design).
- **Firebase Storage** — Runtime assets (profile photos, lecture resources, subject thumbnails).
- **Bunny CDN** — Video content (see 06 Firebase Architecture Section 5).
- **Git Repository** — Static assets bundled with the application (icons, splash screens, logos).
- **This Document's Index** — References to all asset locations and their metadata.

---

# 2. Asset Categories

## 2.1 Brand Assets

| Asset | Description | Format | Location | Owner |
|-------|-------------|--------|----------|-------|
| App Logo | Primary app icon (launcher, store listing) | SVG, PNG (1024×1024) | `/assets/images/logo/` | Teacher |
| App Logo (Dark) | Dark mode variant | SVG, PNG | `/assets/images/logo/` | Teacher |
| Favicon | Web app favicon | ICO, PNG (16×16 to 512×512) | `/assets/images/favicon/` | Teacher |
| Brand Colors | Primary, secondary, accent, semantic | Design tokens | Figma + `core/theme/` | Teacher |
| Typography | Font family, weights, sizes | TTF/OTF + design tokens | `/assets/fonts/` + Figma | Teacher |
| Splash Screen | App launch screen | PNG, Lottie | `/assets/images/splash/` | Teacher |
| Onboarding Illustrations | Welcome/tutorial screens | SVG, Lottie | `/assets/images/onboarding/` | Teacher |

## 2.2 UI Assets

| Asset | Description | Format | Location | Owner |
|-------|-------------|--------|----------|-------|
| Icons | System icons (navigation, actions, status) | SVG (preferred), PNG | `/assets/icons/` + `core/widgets/icons/` | Design Team |
| Empty State Illustrations | No data, error, offline states | SVG, Lottie | `/assets/images/empty_states/` | Design Team |
| Achievement Badges | Gamification / ranking badges | SVG, PNG | `/assets/images/badges/` | Design Team |
| Flags / Localization | Language selection icons | SVG | `/assets/icons/flags/` | Design Team |
| Animations | Loading, success, transition animations | Lottie JSON | `/assets/animations/` | Design Team |

## 2.3 Content Assets (Educational)

| Asset | Description | Format | Location | Owner |
|-------|-------------|--------|----------|-------|
| Subject Thumbnails | Cover images for subjects | JPG, WebP (16:9) | Firebase Storage: `/subject_thumbnails/` | Teacher / Admin |
| Lecture Resource Thumbnails | Preview images for videos/PDFs | JPG, WebP | Firebase Storage: `/lecture_resources/` | Teacher / Admin |
| Profile Photos | User avatars | JPG, WebP (square, 1:1) | Firebase Storage: `/profile_photos/` | Student / Admin |
| Video Content | Educational video files | MP4 (H.264), HLS | Bunny CDN | Teacher / Admin |
| PDF Documents | Educational materials | PDF | Firebase Storage: `/lecture_resources/` | Teacher / Admin |
| Attachments | Supplementary files (ZIP, DOC, etc.) | Various | Firebase Storage: `/lecture_resources/` | Teacher / Admin |

## 2.4 Audio Assets

| Asset | Description | Format | Location | Owner |
|-------|-------------|--------|----------|-------|
| Notification Sounds | Push notification tones | MP3, WAV (short, < 3s) | `/assets/audio/notifications/` | Design Team |
| UI Sounds | Button clicks, success chimes | MP3, WAV | `/assets/audio/ui/` | Design Team |
| Voice Notes (Future) | Student/admin voice messages | AAC, MP3 | Firebase Storage | Student / Admin |

---

# 3. Naming Conventions

### 3.1 File Names

```
{category}_{purpose}_{variant}_{size}.{ext}
```

| Segment | Values | Example |
|---------|--------|---------|
| `category` | `logo`, `icon`, `illust`, `thumb`, `badge`, `anim`, `audio` | `logo_primary_dark_1024.png` |
| `purpose` | Descriptive name | `icon_nav_home`, `illust_empty_subjects` |
| `variant` | `light`, `dark`, `mono`, `color`, `outline`, `filled` | `logo_primary_dark` |
| `size` | Pixel dimension or `vector` for SVG | `1024`, `48`, `vector` |

### Examples

```
logo_primary_light_1024.png
logo_primary_dark_1024.png
icon_nav_home_24.svg
icon_nav_subjects_24.svg
icon_action_bookmark_24.svg
illust_empty_subjects_vector.svg
illust_offline_vector.svg
anim_loading_success.json
anim_loading_error.json
thumb_default_subject_16_9.jpg
badge_rank_gold_128.png
audio_notification_default.mp3
audio_ui_button_click.mp3
```

### 3.2 Asset Keys (Dart Code)

```dart
// core/constants/asset_paths.dart
class AssetImages {
  static const String logoPrimary = 'assets/images/logo/logo_primary_light_1024.png';
  static const String logoPrimaryDark = 'assets/images/logo/logo_primary_dark_1024.png';
  static const String splashScreen = 'assets/images/splash/splash_screen.png';
}

class AssetIcons {
  static const String navHome = 'assets/icons/icon_nav_home_24.svg';
  static const String navSubjects = 'assets/icons/icon_nav_subjects_24.svg';
  static const String actionBookmark = 'assets/icons/icon_action_bookmark_24.svg';
}

class AssetIllustrations {
  static const String emptySubjects = 'assets/images/empty_states/illust_empty_subjects_vector.svg';
  static const String offline = 'assets/images/empty_states/illust_offline_vector.svg';
}

class AssetAnimations {
  static const String loading = 'assets/animations/anim_loading.json';
  static const String success = 'assets/animations/anim_success.json';
}
```

---

# 4. Storage & Access Rules

### 4.1 Git-Tracked Assets (Bundled with App)

**Location:** `assets/` directory in Flutter project.

**What goes here:**
- App logo and splash screen
- System icons and illustrations
- Empty state graphics
- Animation files (Lottie)
- Audio files (notification sounds, UI sounds)
- Font files

**Rules:**
- Maximum bundled asset size: **10 MB total** (per platform store guidelines).
- All images must be optimized before commit (see Section 7).
- SVG preferred over PNG for vector graphics.
- WebP preferred over JPG/PNG for raster images where supported.

**pubspec.yaml:**
```yaml
flutter:
  assets:
    - assets/images/logo/
    - assets/images/splash/
    - assets/images/empty_states/
    - assets/images/onboarding/
    - assets/images/badges/
    - assets/icons/
    - assets/animations/
    - assets/audio/notifications/
    - assets/audio/ui/
  fonts:
    - family: Cairo
      fonts:
        - asset: assets/fonts/Cairo-Regular.ttf
        - asset: assets/fonts/Cairo-Bold.ttf
          weight: 700
```

### 4.2 Firebase Storage Assets (Dynamic Content)

**Location:** Firebase Storage buckets.

**Structure:**
```
/profile_photos/{user_id}/{timestamp}_{file}
/lecture_resources/{lecture_id}/{resource_id}/{file}
/subject_thumbnails/{subject_id}/{timestamp}_{file}
```

**Access Rules:**
- Profile photos: Readable by authenticated users; writable by owner or admin/teacher.
- Lecture resources (PDF/attachments): Readable only via signed URLs generated by Cloud Function (see 06 Firebase Architecture Section 5.2).
- Subject thumbnails: Publicly readable (no auth required for listing subjects).

**See:** 06 Firebase Architecture Section 5 for full Storage Rules.

### 4.3 Bunny CDN Assets (Video)

**Location:** Bunny CDN Video Library.

**Access:**
- Videos are never accessed via raw Bunny URL.
- App requests signed URL via `generateSignedVideoUrl` Cloud Function (see 06 Firebase Architecture Section 6.4).
- Admin/Teacher enters only `video_id` in Dashboard; the actual file path is opaque to the platform.

**See:** 06 Firebase Architecture Section 5.2 and FINAL_DECISIONS Section 4.

---

# 5. Design Tokens

Design tokens are the single source of truth for visual properties. They are defined in Figma and mirrored in code.

### 5.1 Color Tokens

```dart
// core/theme/design_tokens.dart
class AppColors {
  // Primary
  static const Color primary = Color(0xFF1A73E8);      // Example — actual values from Figma
  static const Color primaryLight = Color(0xFF4A9EFF);
  static const Color primaryDark = Color(0xFF0049B0);

  // Secondary
  static const Color secondary = Color(0xFF00C853);
  static const Color secondaryLight = Color(0xFF5EFF84);
  static const Color secondaryDark = Color(0xFF009624);

  // Semantic
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF2196F3);

  // Neutral
  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF5F5F5);
  static const Color onBackground = Color(0xFF212121);
  static const Color onSurface = Color(0xFF424242);
  static const Color divider = Color(0xFFE0E0E0);

  // Grade (الفرقة) — confirmed final by Teacher, 2026-08-04
  static const Color gradeOne = Color(0xFFFBBC05);
  static const Color gradeTwo = Color(0xFF4285F4);
  static const Color gradeThree = Color(0xFF34A853);
  static const Color gradeFour = Color(0xFFEA4335);

  // Dark Mode
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkOnBackground = Color(0xFFFFFFFF);
}
```

### 5.1.1 Grade Color Mapping

| Grade (الفرقة) | Field Value (`users.grade`) | Color |
| --- | --- | --- |
| الفرقة الأولى | `grade_one` | `AppColors.gradeOne` `#FBBC05` |
| الفرقة الثانية | `grade_two` | `AppColors.gradeTwo` `#4285F4` |
| الفرقة الثالثة | `grade_three` | `AppColors.gradeThree` `#34A853` |
| الفرقة الرابعة | `grade_four` | `AppColors.gradeFour` `#EA4335` |

### 5.2 Typography Tokens

```dart
// core/theme/design_tokens.dart
class AppTypography {
  static const String fontFamily = 'Cairo'; // Or Figma-specified font

  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.bold,
    height: 1.2,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.bold,
    height: 1.3,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  static const TextStyle labelLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
}
```

### 5.3 Spacing Tokens

```dart
// core/theme/design_tokens.dart
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const double screenPadding = md;
  static const double cardPadding = md;
  static const double sectionGap = lg;
}
```

### 5.4 Shape Tokens

```dart
// core/theme/design_tokens.dart
class AppShapes {
  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 16;
  static const double radiusXLarge = 24;
  static const double radiusCircular = 999;
}
```

---

# 6. Asset Versioning

### 6.1 Static Assets (Git-Tracked)

- Versioned alongside code (Git commits).
- Breaking visual changes require design review and Teacher approval.
- Asset updates in a release must be documented in release notes.

### 6.2 Dynamic Assets (Firebase Storage / Bunny CDN)

- **Subject Thumbnails:** Overwriting a thumbnail creates a new file with timestamp suffix; old file soft-deleted after 30 days.
- **Profile Photos:** New upload replaces old; old file retained for 90 days (audit/compliance).
- **Lecture Resources:** Versioning handled by lecture publishing workflow; unpublished resources remain in Storage but are inaccessible via Security Rules.
- **Videos (Bunny CDN):** Versioning handled by Bunny CDN; platform stores only `video_id`.

---

# 7. Optimization Standards

### 7.1 Images

| Format | Use Case | Tool | Target Size |
|--------|----------|------|-------------|
| SVG | Icons, illustrations, logos | SVGO | < 50 KB |
| WebP | Photos, thumbnails | cwebp | < 200 KB |
| PNG | Transparency required | oxipng | < 500 KB |
| JPG | Photos (fallback) | jpegoptim | < 300 KB |

### 7.2 Videos

- Upload to Bunny CDN in original quality; Bunny handles transcoding.
- Platform references only `video_id`.
- No video file is stored in Firebase Storage or bundled with the app.

### 7.3 Audio

- Notification sounds: < 100 KB, mono, 44.1 kHz.
- UI sounds: < 20 KB, mono, 44.1 kHz.

### 7.4 Fonts

- Use variable fonts if available (reduces file count).
- Subset fonts to include only required glyphs (Arabic + Latin + numerals).
- Target: < 500 KB per font family.

---

# 8. Accessibility Requirements

- All icons must have semantic labels (`Semantics` widget in Flutter).
- Color contrast ratio minimum: 4.5:1 for normal text, 3:1 for large text (per WCAG AA).
- Empty state illustrations must have descriptive alt text.
- Animations must respect `prefers-reduced-motion` (Flutter: `MediaQuery.of(context).disableAnimations`).
- Audio notifications must have visual equivalents (in-app notification + badge).

---

# 9. Asset Request Workflow

### For Design Team

```
1. Identify need (new feature, missing asset, outdated design)
2. Create asset in Figma (source of truth)
3. Export in required formats (SVG, PNG, WebP, Lottie)
4. Optimize using approved tools (Section 7)
5. Submit PR to `assets/` directory
6. Update this document's index (Section 2)
7. Link PR to feature task ID
```

### For Teacher / Admin (Content Assets)

```
1. Upload via Admin Dashboard
2. Dashboard validates: format, size, dimensions
3. Dashboard optimizes automatically (WebP conversion, resizing)
4. Stored in Firebase Storage or Bunny CDN
5. URL recorded in Firestore (lecture_resources, subjects, etc.)
```

---

# 10. Asset Inventory Template

Use this template to track assets in the issue tracker or project wiki:

```
| Asset ID | Name | Category | Format | Size | Location | Status | Last Updated | Owner |
|----------|------|----------|--------|------|----------|--------|--------------|-------|
| AST-001 | Primary Logo | Brand | SVG | 12 KB | assets/images/logo/ | Approved | 2026-08-01 | Design Team |
| AST-002 | Splash Screen | Brand | PNG | 45 KB | assets/images/splash/ | Approved | 2026-08-01 | Design Team |
| AST-003 | Home Icon | UI | SVG | 2 KB | assets/icons/ | Approved | 2026-08-01 | Design Team |
```

---

# 11. Open Items

- [ ] Confirm primary font family (Cairo, Tajawal, or other) — depends on 03 UI & UX.
- [ ] Confirm brand color palette — depends on 03 UI & UX / Teacher preference.
- [ ] Confirm if Lottie animations are approved for loading states, or if native Flutter animations are preferred.
- [ ] Define maximum file sizes for student-uploaded attachments (profile photo, question attachments).
- [ ] Confirm audio feedback strategy — minimal (current), or richer sound design?
- [ ] Establish Figma-to-Flutter design token sync process (manual vs. automated via Figma API).

---

END OF DOCUMENT
