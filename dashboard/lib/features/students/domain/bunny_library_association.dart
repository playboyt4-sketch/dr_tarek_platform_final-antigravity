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
/// Configurable at build time so a non-production build (staging, QA) names
/// its own library instead of being pinned to production `736742`:
///   flutter build web --dart-define=BUNNY_DEFAULT_LIBRARY_ID=780700
/// The default keeps production behaviour byte-identical. This is
/// display/validation data, never a credential; the server remains the only
/// authority that resolves credentials.
const String defaultBunnyLibraryId = String.fromEnvironment(
  'BUNNY_DEFAULT_LIBRARY_ID',
  defaultValue: '736742',
);

/// Libraries the Dashboard is allowed to write. Activation of any further
/// library is a server configuration action; the Dashboard follows the
/// approved list rather than inventing ids.
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

/// The value to persist for a NEWLY authored resource. Videos always carry an
/// association (default library when the doctor has not chosen one);
/// everything else carries null.
String? bunnyLibraryIdForCreate({
  required String resourceType,
  String? selectedLibraryId,
}) {
  if (resourceType != 'video') return null;
  return normalizeBunnyLibraryId(selectedLibraryId) ?? defaultBunnyLibraryId;
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
  Iterable<String> configuredLibraryIds = configuredBunnyLibraryIds,
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
  final bool known = configuredLibraryIds
      .map((String id) => id.trim())
      .where((String id) => id.isNotEmpty)
      .contains(value);
  return known ? null : 'Unknown Bunny library: $value.';
}
