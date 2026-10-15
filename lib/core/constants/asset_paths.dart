// Central asset-path constants (per 11 Assets, Section 3.2 "Asset Keys").
//
// Bundled images are registered wholesale via `assets/images/` in
// `pubspec.yaml` (`flutter: assets:`), so no per-file pubspec entry is
// needed for the photo below — verified against the current pubspec.
//
// OPEN ITEM — resolved: the trailing space before the extension was
// removed (`New Student - name photo.png`); both copies below load.
// `new_student_name_photo.png` remains the canonical reference used here.
// Sibling `New Student - *.png` files were audited the same way
// (`Welcome photo` fixed; `End photo` fallback now points at the real file).

/// Bundled raster illustrations shipped with the app.
abstract final class AssetImages {
  /// "New Student - name" illustration (Figma: `New Student - name photo`,
  /// 369x344, 35px corner radius). Conforming snake_case copy.
  static const String newStudentNamePhoto =
      'assets/images/new_student_name_photo.png';

  /// "New Student - number" illustration (Figma: `New Student - number
  /// photo`, 369x355, 35px corner radius).
  ///
  /// OPEN ITEM — naming-convention violation (11 Assets, Section 3), same
  /// class as the Name photo: the shipped file is
  /// `New Student - number photo.png` (spaces + hyphens; verified present
  /// under `assets/images/` — no trailing-space variant for this one,
  /// unlike the Name photo). Not renamed without Teacher approval.
  static const String newStudentNumberPhoto =
      'assets/images/New Student - number photo.png';
}
