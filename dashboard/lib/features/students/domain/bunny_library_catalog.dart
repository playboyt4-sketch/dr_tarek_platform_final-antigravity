/// ADR-010 — Bunny Stream library catalog and picker selection state.
///
/// NONVISUAL SCAFFOLDING ONLY. The visible selector stays blocked until an
/// approved Figma specification exists; nothing here renders UI, and no
/// existing Dashboard screen changes behaviour because of it.
///
/// This file answers the three questions the eventual picker needs:
/// 1. Which libraries may a doctor choose from (non-secret metadata only)?
/// 2. What is the current selection for one resource (new / existing / legacy)?
/// 3. What must be validated before the association is written?
///
/// It carries NO secrets, NO signing material and NO pull-zone/template data:
/// only an id, a display name and availability flags. The server remains the
/// only authority for credentials.
library;

import 'bunny_library_association.dart';

/// Client-visible, non-secret description of one Bunny library.
class BunnyLibraryOption {
  /// Canonical numeric library id stored on the resource.
  final String id;

  /// Human-readable label for the future selector.
  final String displayName;

  /// Whether the platform currently has the library configured at all.
  final bool isAvailable;

  /// Whether a doctor may pick it yet. A library can be available (known to
  /// the platform) while still not selectable (no approved design, or not
  /// activated server-side).
  final bool isSelectable;

  const BunnyLibraryOption({
    required this.id,
    required this.displayName,
    this.isAvailable = true,
    this.isSelectable = true,
  });

  /// Non-secret serialization for staging/debug output.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'displayName': displayName,
        'isAvailable': isAvailable,
        'isSelectable': isSelectable,
      };
}

/// Known libraries. Mirrors the server registry's numeric ids; `775315` is
/// intentionally NOT selectable yet (library not activated, no approved
/// design). This is a static local catalog because no approved Firestore
/// configuration source exists for it — do not invent one.
const List<BunnyLibraryOption> defaultBunnyLibraryCatalog = <BunnyLibraryOption>[
  BunnyLibraryOption(
    id: defaultBunnyLibraryId,
    displayName: 'Default library',
  ),
  BunnyLibraryOption(
    id: '775315',
    displayName: 'Legacy platform library',
    isSelectable: false,
  ),
];

/// Look up one option in the catalog (null when unknown).
BunnyLibraryOption? findBunnyLibraryOption(
  String? libraryId, {
  Iterable<BunnyLibraryOption> catalog = defaultBunnyLibraryCatalog,
}) {
  final String? normalized = normalizeBunnyLibraryId(libraryId);
  if (normalized == null) return null;
  for (final BunnyLibraryOption option in catalog) {
    if (option.id == normalized) return option;
  }
  return null;
}

/// Selection-boundary validation: returns an error message, or null.
/// Null/blank `libraryId` means "no selection" (legacy rows and new videos
/// that will use the default library) and is valid.
String? validateLibrarySelection({
  required String? libraryId,
  Iterable<BunnyLibraryOption> catalog = defaultBunnyLibraryCatalog,
}) {
  final String? normalized = normalizeBunnyLibraryId(libraryId);
  if (normalized == null) return null;
  final BunnyLibraryOption? option =
      findBunnyLibraryOption(normalized, catalog: catalog);
  if (option == null) return 'Unknown Bunny library: $normalized.';
  if (!option.isAvailable) return 'Bunny library $normalized is not available.';
  if (!option.isSelectable) {
    return 'Bunny library $normalized cannot be selected yet.';
  }
  return null;
}

/// Immutable selection state for one video resource.
///
/// Separation of concerns:
/// - [storedLibraryId] is what the resource document currently holds
///   (null = legacy row).
/// - [selectedLibraryId] is what the doctor (or the default rule) chose in
///   this editing session.
/// - [libraryIdForWrite] is the value the data layer should persist.
class BunnyLibrarySelection {
  /// Bunny video id currently in the form (bare GUID expected).
  final String? videoId;

  /// Library chosen in this session (null = no explicit choice).
  final String? selectedLibraryId;

  /// Library persisted on the resource at load time (null = legacy row).
  final String? storedLibraryId;

  /// True when the Video ID changed but the stored association was not
  /// re-reviewed: the picker (once it exists) must ask before saving.
  final bool requiresReview;

  /// Validation error for [selectedLibraryId], if any.
  final String? validationError;

  const BunnyLibrarySelection({
    required this.videoId,
    this.selectedLibraryId,
    this.storedLibraryId,
    this.requiresReview = false,
    this.validationError,
  });

  /// A brand-new video: no stored association, no explicit choice yet. The
  /// data layer defaults it to the default library at write time.
  factory BunnyLibrarySelection.forNewVideo({String? videoId}) =>
      BunnyLibrarySelection(videoId: _clean(videoId));

  /// An existing resource loaded from Firestore (legacy when null).
  factory BunnyLibrarySelection.forExisting({
    String? videoId,
    String? storedLibraryId,
  }) =>
      BunnyLibrarySelection(
        videoId: _clean(videoId),
        selectedLibraryId: normalizeBunnyLibraryId(storedLibraryId),
        storedLibraryId: normalizeBunnyLibraryId(storedLibraryId),
      );

  /// Whether this resource predates ADR-010 (no stored association).
  bool get isLegacy => normalizeBunnyLibraryId(storedLibraryId) == null;

  /// Whether the current selection can be written.
  bool get isValid => validationError == null;

  /// The id the data layer should persist. Null means "keep the stored
  /// value" (update path) / "use the default library" (create path), which is
  /// exactly what the provider helpers already implement.
  ///
  /// An INVALID selection is never written: the getter falls back to the
  /// stored value (null for new/legacy rows, i.e. the default rule), so a
  /// rejected choice cannot leak into Firestore even if a caller ignores
  /// [validationError].
  String? get libraryIdForWrite {
    final String? selected = normalizeBunnyLibraryId(selectedLibraryId);
    if (selected != null && validationError == null) return selected;
    return normalizeBunnyLibraryId(storedLibraryId);
  }

  /// Explicit choice (or clearing it). Validated against [catalog]; an
  /// invalid choice is retained together with its error so the future UI can
  /// show why it is blocked.
  BunnyLibrarySelection selectLibrary(
    String? libraryId, {
    Iterable<BunnyLibraryOption> catalog = defaultBunnyLibraryCatalog,
  }) {
    final String? normalized = normalizeBunnyLibraryId(libraryId);
    return BunnyLibrarySelection(
      videoId: videoId,
      selectedLibraryId: normalized,
      storedLibraryId: storedLibraryId,
      requiresReview: false,
      validationError: validateLibrarySelection(
        libraryId: normalized,
        catalog: catalog,
      ),
    );
  }

  /// Changing the Video ID may invalidate the association (a Video ID belongs
  /// to exactly one library). Without the picker we cannot resolve the new
  /// library, so the state becomes explicitly "needs review" instead of
  /// silently keeping an unrelated association.
  BunnyLibrarySelection withVideoId(String? nextVideoId) {
    final String? next = _clean(nextVideoId);
    final bool changed = next != videoId;
    return BunnyLibrarySelection(
      videoId: next,
      selectedLibraryId: selectedLibraryId,
      storedLibraryId: storedLibraryId,
      requiresReview: changed &&
          (normalizeBunnyLibraryId(storedLibraryId) != null ||
              normalizeBunnyLibraryId(selectedLibraryId) != null),
      validationError: validationError,
    );
  }

  /// Clears any explicit choice, returning to "use stored/default".
  BunnyLibrarySelection resetSelection() => BunnyLibrarySelection(
        videoId: videoId,
        storedLibraryId: storedLibraryId,
      );

  /// The exact resource fields the staging layer needs. Both are raw values:
  /// `bunny_video_id` is never a URL, and `bunny_library_id` is never a
  /// credential or a template.
  Map<String, String?> toResourceFields() => <String, String?>{
        'bunny_video_id': _clean(videoId),
        'bunny_library_id': libraryIdForWrite,
      };

  static String? _clean(String? raw) {
    if (raw is! String) return null;
    final String value = raw.trim();
    return value.isEmpty ? null : value;
  }
}
