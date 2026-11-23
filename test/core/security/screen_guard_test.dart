import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/core/security/screen_guard.dart';
import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/controllers/video_playback_controller.dart';

class _FakeSourceResolver implements VideoSourceGateway {
  @override
  Future<List<VideoResource>> loadResources(String lectureId) async => [
        const VideoResource(
          id: 'res-1',
          title: 'Res 1',
          resourceType: 'video',
          duration: Duration(minutes: 10),
        ),
      ];

  @override
  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
    String? lectureId,
  }) async =>
      ResolvedVideoSource(
        url: Uri.parse('https://example.com/video.m3u8'),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        selectedQuality: VideoQuality.auto,
      );
}

class _FakeEntitlementGateway implements VideoEntitlementGateway {
  @override
  Future<VideoEntitlement> resolve({
    required String userId,
    required String subjectId,
  }) async =>
      const VideoEntitlement(
        allowed: true,
        allowedQualities: {VideoQuality.auto},
      );
}

class _FakePlaybackRepository implements PlaybackRepository {
  @override
  Future<List<PlaybackProgressRecord>> getContinueWatching({int limit = 20}) async =>
      const [];

  @override
  Future<PlaybackProgressRecord?> read(String lectureId) async => null;

  @override
  Future<void> save(PlaybackProgressRecord record, {bool syncCloud = true}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ScreenGuard.isRecording.value = false;
  });

  tearDown(() {
    ScreenGuard.isRecording.value = false;
  });

  test('ScreenGuard.isRecording defaults to false', () {
    expect(ScreenGuard.isRecording.value, isFalse);
  });

  test('VideoPlaybackController refuses play() when isRecording is true', () async {
    final episode = LectureSummary(
      id: 'lec-1',
      title: 'Lecture 1',
      status: 'not_started',
      displayOrder: 0,
      isLocked: false,
    );

    final controller = VideoPlaybackController(
      userId: 'user-1',
      subjectId: 'sub-1',
      sourceResolver: _FakeSourceResolver(),
      entitlementService: _FakeEntitlementGateway(),
      playbackRepository: _FakePlaybackRepository(),
      episodes: [episode],
      episode: episode,
    );

    // Set recording active
    ScreenGuard.isRecording.value = true;

    // Attempt to play while recording
    await controller.play();

    // Player status must not be playing
    expect(controller.isPlaying, isFalse);

    controller.dispose();
  });

  test('VideoPlaybackController does not auto-resume when isRecording becomes false', () async {
    final episode = LectureSummary(
      id: 'lec-2',
      title: 'Lecture 2',
      status: 'not_started',
      displayOrder: 0,
      isLocked: false,
    );

    final controller = VideoPlaybackController(
      userId: 'user-1',
      subjectId: 'sub-1',
      sourceResolver: _FakeSourceResolver(),
      entitlementService: _FakeEntitlementGateway(),
      playbackRepository: _FakePlaybackRepository(),
      episodes: [episode],
      episode: episode,
    );

    // Screen recording starts
    ScreenGuard.isRecording.value = true;
    expect(controller.isPlaying, isFalse);

    // Screen recording stops
    ScreenGuard.isRecording.value = false;

    // Must still remain paused until explicit user play gesture
    expect(controller.isPlaying, isFalse);

    controller.dispose();
  });

  test('ScreenGuard.reapplyAfterFirstFrame registers without throwing', () {
    expect(() => ScreenGuard.reapplyAfterFirstFrame(), returnsNormally);
  });
}
