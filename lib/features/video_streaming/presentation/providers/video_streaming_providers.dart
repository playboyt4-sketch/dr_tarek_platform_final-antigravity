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

/// FINAL_DECISIONS §12: callable-backed rolling-window self-read.
final watchWindowGatewayProvider = Provider<WatchWindowGateway>((ref) {
  return CallableWatchWindowGateway(functions: FirebaseFunctions.instance);
});

final videoEntitlementServiceProvider = Provider<VideoEntitlementService>((
  ref,
) {
  return VideoEntitlementService(
    membershipRepository: ref.watch(membershipRepositoryProvider),
  );
});

/// Max Subject playback-session gateway (server-owned sessions). Stateless:
/// session state lives in the per-Subject controller/coordinator, never here.
final playbackSessionGatewayProvider = Provider<PlaybackSessionGateway>((
  ref,
) {
  return CallablePlaybackSessionGateway(
    functions: FirebaseFunctions.instance,
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
