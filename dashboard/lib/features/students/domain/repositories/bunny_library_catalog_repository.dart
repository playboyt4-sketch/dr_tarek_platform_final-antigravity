import '../bunny_library_catalog.dart';

/// Status of the automatic video discovery probe across eligible Bunny libraries.
enum BunnyDiscoveryStatus {
  /// The video was located in exactly one eligible library.
  found,

  /// The video was not found in any eligible library.
  notFound,

  /// The video exists in multiple eligible libraries (ambiguous).
  ambiguous,

  /// The discovery probe failed (e.g. network or permission error).
  error,
}

/// Result of auto-discovering a video across active Bunny libraries.
class BunnyDiscoveryResult {
  final BunnyDiscoveryStatus status;
  final String? libraryId;
  final List<String> matchedLibraries;
  final String? errorMessage;

  const BunnyDiscoveryResult({
    required this.status,
    this.libraryId,
    this.matchedLibraries = const <String>[],
    this.errorMessage,
  });

  bool get isFound => status == BunnyDiscoveryStatus.found && libraryId != null;
  bool get isNotFound => status == BunnyDiscoveryStatus.notFound;
  bool get isAmbiguous => status == BunnyDiscoveryStatus.ambiguous;
  bool get isError => status == BunnyDiscoveryStatus.error;
}

/// Clean Architecture repository contract for Bunny library catalog and discovery.
///
/// UI widgets NEVER query Firestore directly for libraries.
/// All catalog operations flow through this repository.
abstract class BunnyLibraryCatalogRepository {
  /// Loads the list of active/eligible Bunny libraries for the current environment.
  Future<List<BunnyLibraryOption>> getEligibleLibraries();

  /// Probes active Bunny libraries to discover which library owns the given [videoId].
  Future<BunnyDiscoveryResult> discoverVideoLibrary(String videoId);
}
