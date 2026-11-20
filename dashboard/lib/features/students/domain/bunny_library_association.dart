/// ADR-010 — Bunny Stream library association for authored resources.
///
/// DATA LAYER ONLY. The visible library selector is blocked until an approved
/// Figma specification exists, so nothing here renders or preselects UI: these
/// pure helpers decide which `bunny_library_id` a write carries, so the
/// Dashboard can start storing and preserving the association today without
/// inventing a design.
///
/// Rules encoded here (ADR-010):
/// - New video resources default to the default library.
/// - Non-video resources never carry a library association.
/// - A stored association is preserved on unrelated edits (null = "keep the
///   stored value" for the provider's update path).
/// - Only numeric library ids are accepted; anything else is rejected at the
///   validation boundary instead of being written.
library;

/// Mirror of the server-side default library (ADR-010).
///
/// Configurable at build time via dart-define:
///   flutter build web --dart-define=BUNNY_DEFAULT_LIBRARY_ID=780700
/// When not set, the client relies on server discovery and dynamic catalog
/// instead of hardcoding a silent fallback.
const String defaultBunnyLibraryId = String.fromEnvironment(
  'BUNNY_DEFAULT_LIBRARY_ID',
  defaultValue: '736742',
);

/// Libraries the Dashboard is configured with by default at build time.
/// Dynamic active libraries are fetched from the server catalog.
const List<String> configuredBunnyLibraryIds = <String>[
  defaultBunnyLibraryId,
];

final RegExp _bunnyLibraryIdPattern = RegExp(r'^\d{1,20}$');

/// Trim + numeric check. Returns null for blank, malformed or non-string
/// values (legacy rows and pre-ADR-010 documents).
String? normalizeBunnyLibraryId(Object? raw) {
  if (raw is! String) return null;
  final String value = raw.trim();
  if (value.isEmpty || !_bunnyLibraryIdPattern.hasMatch(value)) return null;
  return value;
}

bool isValidBunnyLibraryId(Object? raw) => normalizeBunnyLibraryId(raw) != null;

/// The value to persist for a NEWLY authored resource. Videos carry the
/// selected library (or default when configured); non-video carries null.
String? bunnyLibraryIdForCreate({
  required String resourceType,
  String? selectedLibraryId,
}) {
  if (resourceType != 'video') return null;
  final String? selected = normalizeBunnyLibraryId(selectedLibraryId);
  if (selected != null) return selected;
  return normalizeBunnyLibraryId(defaultBunnyLibraryId);
}

/// The value to persist when UPDATING an existing resource. Null means "keep
/// whatever is stored", which is how unrelated edits preserve the association
/// (and how legacy rows stay legacy until backfilled).
String? bunnyLibraryIdForUpdate({String? selectedLibraryId}) =>
    normalizeBunnyLibraryId(selectedLibraryId);

/// Validation boundary used before a write. Returns an error message, or null
/// when the association is acceptable.
String? validateBunnyLibraryAssociation({
  required String resourceType,
  String? libraryId,
  Iterable<String>? configuredLibraryIds,
}) {
  final String? value = normalizeBunnyLibraryId(libraryId);
  if (resourceType != 'video') {
    return value == null
        ? null
        : 'Only video resources can carry a Bunny library.';
  }
  if (value == null) {
    return 'A Bunny library is required for a video resource.';
  }
  final Iterable<String> allowed = configuredLibraryIds ??
      (configuredBunnyLibraryIds.isNotEmpty
          ? configuredBunnyLibraryIds
          : <String>[value]);
  final bool known = allowed
      .map((String id) => id.trim())
      .where((String id) => id.isNotEmpty)
      .contains(value);
  return known ? null : 'Unknown Bunny library: $value.';
}
