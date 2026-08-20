import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/playback_entities.dart';
import 'video_streaming_providers.dart';

final continueWatchingProvider = FutureProvider.autoDispose
    .family<List<PlaybackProgressRecord>, String>((ref, userId) async {
      final preferences = await ref.watch(sharedPreferencesProvider.future);
      return playbackRepositoryFor(
        userId: userId,
        preferences: preferences,
      ).getContinueWatching(limit: 12);
    });
