import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/drm_repository_impl.dart';
import '../../domain/repositories/drm_repository.dart';
import '../../../video_streaming/data/datasources/protected_offline_storage.dart';
import '../../../video_streaming/presentation/providers/video_streaming_providers.dart';

final drmRepositoryProvider = FutureProvider<DrmRepository>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  final storage = ProtectedOfflineStorageImpl(prefs: prefs);
  return DrmRepositoryImpl(protectedStorage: storage);
});
