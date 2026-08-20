import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../membership/presentation/providers/membership_providers.dart';
import '../../data/repositories/playback_repository.dart';
import '../../data/services/video_source_resolver.dart';

final videoSourceResolverProvider = Provider<VideoSourceResolver>((ref) {
  return VideoSourceResolver(functions: FirebaseFunctions.instance);
});

final videoEntitlementServiceProvider = Provider<VideoEntitlementService>((
  ref,
) {
  return VideoEntitlementService(
    membershipRepository: ref.watch(membershipRepositoryProvider),
  );
});

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

PlaybackRepository playbackRepositoryFor({
  required String userId,
  required SharedPreferences preferences,
}) {
  return PlaybackRepositoryImpl(
    userId: userId,
    localStore: preferences,
    firestore: FirebaseFirestore.instance,
  );
}
