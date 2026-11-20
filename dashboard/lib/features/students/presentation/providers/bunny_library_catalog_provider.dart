import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/bunny_library_catalog_repository_impl.dart';
import '../../domain/bunny_library_catalog.dart';
import '../../domain/repositories/bunny_library_catalog_repository.dart';

/// Provider for the [BunnyLibraryCatalogRepository].
final bunnyLibraryCatalogRepositoryProvider =
    Provider<BunnyLibraryCatalogRepository>((ref) {
  return CallableBunnyLibraryCatalogRepository(FirebaseFunctions.instance);
});

/// Async notifier for eligible Bunny libraries.
/// Handles:
/// - loading state
/// - data / empty state (data is empty list)
/// - error state
/// - retry via [retry]
final eligibleBunnyLibrariesProvider = AsyncNotifierProvider<
    EligibleBunnyLibrariesNotifier, List<BunnyLibraryOption>>(
  EligibleBunnyLibrariesNotifier.new,
);

class EligibleBunnyLibrariesNotifier
    extends AsyncNotifier<List<BunnyLibraryOption>> {
  @override
  Future<List<BunnyLibraryOption>> build() async {
    final BunnyLibraryCatalogRepository repo =
        ref.watch(bunnyLibraryCatalogRepositoryProvider);
    return repo.getEligibleLibraries();
  }

  /// Refreshes/retries fetching the catalog from the backend.
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final BunnyLibraryCatalogRepository repo =
          ref.read(bunnyLibraryCatalogRepositoryProvider);
      return repo.getEligibleLibraries();
    });
  }
}
