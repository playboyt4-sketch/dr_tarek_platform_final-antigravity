import 'package:cloud_functions/cloud_functions.dart';

import '../domain/bunny_library_catalog.dart';
import '../domain/repositories/bunny_library_catalog_repository.dart';

/// Production implementation of [BunnyLibraryCatalogRepository] backed by
/// trusted Cloud Functions callables (`listEligibleBunnyLibraries` and
/// `discoverBunnyVideoLibrary`).
class CallableBunnyLibraryCatalogRepository
    implements BunnyLibraryCatalogRepository {
  final FirebaseFunctions _functions;

  CallableBunnyLibraryCatalogRepository(this._functions);

  @override
  Future<List<BunnyLibraryOption>> getEligibleLibraries() async {
    try {
      final HttpsCallableResult<dynamic> result =
          await _functions.httpsCallable('listEligibleBunnyLibraries').call();
      final Object? data = result.data;
      final Map<String, dynamic> payload = data is Map
          ? Map<String, dynamic>.from(data)
          : const <String, dynamic>{};
      final List<dynamic> rawLibs =
          payload['libraries'] as List<dynamic>? ?? <dynamic>[];

      return rawLibs.map((dynamic item) {
        final Map<String, dynamic> map =
            Map<String, dynamic>.from(item as Map);
        final String id = (map['id'] ?? '').toString();
        final String name = (map['name'] ?? id).toString();
        return BunnyLibraryOption(
          id: id,
          displayName: name,
          isAvailable: true,
          isSelectable: true,
        );
      }).toList();
    } catch (e) {
      throw Exception('Failed to load eligible Bunny libraries: $e');
    }
  }

  @override
  Future<BunnyDiscoveryResult> discoverVideoLibrary(String videoId) async {
    try {
      final HttpsCallableResult<dynamic> result = await _functions
          .httpsCallable('discoverBunnyVideoLibrary')
          .call(<String, dynamic>{'videoId': videoId});
      final Object? data = result.data;
      final Map<String, dynamic> payload = data is Map
          ? Map<String, dynamic>.from(data)
          : const <String, dynamic>{};
      final String statusStr = (payload['status'] ?? '').toString();
      final String? libraryId = payload['libraryId'] as String?;
      final List<dynamic>? matched =
          payload['matchedLibraries'] as List<dynamic>?;
      final List<String> matchedLibs =
          matched?.map((dynamic e) => e.toString()).toList() ??
              const <String>[];

      return switch (statusStr) {
        'found' => BunnyDiscoveryResult(
            status: BunnyDiscoveryStatus.found,
            libraryId: libraryId,
            matchedLibraries: matchedLibs,
          ),
        'ambiguous' => BunnyDiscoveryResult(
            status: BunnyDiscoveryStatus.ambiguous,
            matchedLibraries: matchedLibs,
          ),
        'not_found' => const BunnyDiscoveryResult(
            status: BunnyDiscoveryStatus.notFound,
          ),
        _ => BunnyDiscoveryResult(
            status: BunnyDiscoveryStatus.error,
            errorMessage: 'Unexpected discovery status: $statusStr',
          ),
      };
    } on FirebaseFunctionsException catch (e) {
      return BunnyDiscoveryResult(
        status: BunnyDiscoveryStatus.error,
        errorMessage: e.message ?? 'Discovery failed',
      );
    } catch (e) {
      return BunnyDiscoveryResult(
        status: BunnyDiscoveryStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}
