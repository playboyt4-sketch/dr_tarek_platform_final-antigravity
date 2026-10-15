import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/controllers/video_playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

// Identity fix regression: every issuance must assert the ROUTE lecture
// (controller.lectureId for playback, nextEpisode.id for prefetch) so the
// server authorizes the lecture the student actually opened — never a
// lecture derived from a shared bunny_video_id.

/// Channel-free engine backend: creation/initialization fail cleanly
/// (caught by the controller) while dispose stays a no-op for teardown.
class _FakeVideoPlatform extends VideoPlayerPlatform {
  // video_player invokes init() on every platform access: no-op it, or
  // nothing below is ever reached.
  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;

  @override
  Future<void> dispose(int playerId) async {}
}

class _RecordingGateway implements VideoSourceGateway {
  final List<Map<String, Object?>> resolveCalls = [];

  @override
  Future<List<VideoResource>> loadResources(String lectureId) async => [
        const VideoResource(
          id: 'res-1',
          title: 'Video',
          resourceType: 'video',
          bunnyVideoId: '66666666-6666-4666-8666-666666666666',
        ),
      ];

  @override
  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
    String? lectureId,
  }) async {
    resolveCalls.add({
      'resource': resource,
      'quality': quality,
      'subjectId': subjectId,
      'lectureId': lectureId,
    });
    return ResolvedVideoSource(
      url: Uri.parse('https://example.com/video.m3u8'),
      expiresAt: DateTime.now().add(const Duration(minutes: 4)),
      selectedQuality: VideoQuality.auto,
    );
  }
}

class _AllowEntitlement implements VideoEntitlementGateway {
  @override
  Future<VideoEntitlement> resolve({
    required String userId,
    required String subjectId,
  }) async =>
      const VideoEntitlement(
        allowed: true,
        allowedQualities: {VideoQuality.q720},
      );
}

class _FakePlaybackRepository implements PlaybackRepository {
  @override
  Future<List<PlaybackProgressRecord>> getContinueWatching({
    int limit = 20,
  }) async =>
      const [];

  @override
  Future<PlaybackProgressRecord?> read(String lectureId) async => null;

  @override
  Future<void> save(
    PlaybackProgressRecord record, {
    bool syncCloud = true,
  }) async {}
}

LectureSummary _episode(String id) => LectureSummary(
      id: id,
      title: 'Episode $id',
      status: 'not_started',
      displayOrder: 0,
      isLocked: false,
    );

VideoPlaybackController _controller(_RecordingGateway gateway) {
  final episodes = [_episode('ep-1'), _episode('ep-2')];
  return VideoPlaybackController(
    userId: 'student-1',
    subjectId: 'subject-1',
    sourceResolver: gateway,
    entitlementService: _AllowEntitlement(),
    playbackRepository: _FakePlaybackRepository(),
    episodes: episodes,
    episode: episodes.first,
  );
}

void main() {
  final previousPlatform = VideoPlayerPlatform.instance;
  setUpAll(() {
    VideoPlayerPlatform.instance = _FakeVideoPlatform();
  });
  tearDownAll(() {
    VideoPlayerPlatform.instance = previousPlatform;
  });

  // NOTE: testWidgets (not plain test) so platform channels exist as
  // catchable MissingPlugin errors: engine creation/initialization fails
  // cleanly and connectivity teardown works off-device.
  testWidgets('quality change asserts the current route lecture', (tester) async {
    final gateway = _RecordingGateway();
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    // Arms entitlement (startup issuance fails off-device at engine
    // creation, which is irrelevant here) then isolates the call below.
    await controller.initialize();
    gateway.resolveCalls.clear();

    // Engine creation fails off-device; the issuance call (and its
    // lecture identity) happens before that — outcome is irrelevant here.
    await controller.changeQuality(VideoQuality.q720);

    expect(gateway.resolveCalls, hasLength(1));
    expect(gateway.resolveCalls.single['lectureId'], 'ep-1');
  });

  testWidgets('next-episode prefetch asserts the next episode lecture', (tester) async {
    final gateway = _RecordingGateway();
    final controller = _controller(gateway);
    addTearDown(controller.dispose);

    await controller.prefetchNextEpisode();

    expect(gateway.resolveCalls, hasLength(1));
    expect(gateway.resolveCalls.single['lectureId'], 'ep-2');
  });
}
