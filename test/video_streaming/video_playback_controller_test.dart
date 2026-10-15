import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/controllers/video_playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSourceResolver implements VideoSourceGateway {
  int resolveCalls = 0;
  List<VideoResource> resources = const [];
  Exception? resolveError;

  @override
  Future<List<VideoResource>> loadResources(String lectureId) async =>
      resources;

  @override
  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
    String? lectureId,
  }) async {
    resolveCalls++;
    final error = resolveError;
    if (error != null) throw error;
    return ResolvedVideoSource(
      url: Uri.parse('https://example.com/video.m3u8'),
      expiresAt: DateTime.now().add(const Duration(minutes: 4)),
      selectedQuality: VideoQuality.auto,
    );
  }
}

class _FakeEntitlementService implements VideoEntitlementGateway {
  VideoEntitlement verdict = const VideoEntitlement(
    allowed: true,
    allowedQualities: {VideoQuality.q720},
  );
  int resolveCalls = 0;

  @override
  Future<VideoEntitlement> resolve({
    required String userId,
    required String subjectId,
  }) async {
    resolveCalls++;
    return verdict;
  }
}

class _FakePlaybackRepository implements PlaybackRepository {
  @override
  Future<List<PlaybackProgressRecord>> getContinueWatching({
    int limit = 20,
  }) async => const [];

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

VideoPlaybackController _controller({
  required _FakeSourceResolver sourceResolver,
  required _FakeEntitlementService entitlementService,
}) {
  final episodes = [_episode('ep-1'), _episode('ep-2')];
  return VideoPlaybackController(
    userId: 'student-1',
    subjectId: 'subject-1',
    sourceResolver: sourceResolver,
    entitlementService: entitlementService,
    playbackRepository: _FakePlaybackRepository(),
    episodes: episodes,
    episode: episodes.first,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'initialize resolves entitlement first and never issues a signed URL '
      'when denied', () async {
    final sourceResolver = _FakeSourceResolver();
    final entitlementService = _FakeEntitlementService()
      ..verdict = const VideoEntitlement.denied('blocked for subject');
    final controller = _controller(
      sourceResolver: sourceResolver,
      entitlementService: entitlementService,
    );

    await controller.initialize();

    expect(entitlementService.resolveCalls, 1);
    expect(sourceResolver.resolveCalls, 0,
        reason: 'generateBunnySignedUrl must not run for a blocked student');
    expect(
      controller.playbackStatus,
      PlayerPlaybackStatus.error,
    );
    expect(controller.errorMessage, 'blocked for subject');
    controller.dispose();
  });

  test(
      'switchEpisode resolves entitlement first and never issues a signed '
      'URL when denied', () async {
    final sourceResolver = _FakeSourceResolver();
    final entitlementService = _FakeEntitlementService()
      ..verdict = const VideoEntitlement.denied('blocked for subject');
    final controller = _controller(
      sourceResolver: sourceResolver,
      entitlementService: entitlementService,
    );

    // Second episode: previously this path issued a signed URL without any
    // client-side entitlement check.
    await controller.switchEpisode(_episode('ep-2'));

    expect(entitlementService.resolveCalls, 1);
    expect(sourceResolver.resolveCalls, 0,
        reason: 'generateBunnySignedUrl must not run for a blocked student');
    expect(
      controller.playbackStatus,
      PlayerPlaybackStatus.error,
    );
    expect(controller.errorMessage, 'blocked for subject');
    controller.dispose();
  });

  test(
      'issuance Guest-tier throw surfaces the device wall, never an upsell',
      () async {
    final sourceResolver = _FakeSourceResolver()
      ..resources = const [
        VideoResource(
          id: 'res-1',
          title: 'Video 1',
          resourceType: 'video',
          bunnyVideoId: '55555555-5555-4555-8555-555555555555',
        ),
      ]
      ..resolveError = const DeviceNotAuthorizedException('device blocked');
    final entitlementService = _FakeEntitlementService();
    final controller = _controller(
      sourceResolver: sourceResolver,
      entitlementService: entitlementService,
    );

    await controller.initialize();

    expect(sourceResolver.resolveCalls, 1);
    expect(controller.deviceBlocked, isTrue);
    expect(controller.showUpgradePrompt, isTrue);
    expect(controller.dailyWindowBlocked, isFalse);
    expect(controller.playbackStatus, PlayerPlaybackStatus.paused);
    expect(controller.errorMessage, isNull);
    controller.dispose();
  });

  test('genuine plan-tier denial surfaces the upgrade wall', () async {
    final sourceResolver = _FakeSourceResolver();
    final entitlementService = _FakeEntitlementService()
      ..verdict = const VideoEntitlement.denied(
        'Video is not included in your current subscription.',
        denialKind: VideoDenialKind.planUpsell,
      );
    final controller = _controller(
      sourceResolver: sourceResolver,
      entitlementService: entitlementService,
    );

    await controller.initialize();

    expect(sourceResolver.resolveCalls, 0);
    expect(controller.showUpgradePrompt, isTrue);
    expect(controller.deviceBlocked, isFalse);
    expect(controller.playbackStatus, PlayerPlaybackStatus.paused);
    expect(controller.errorMessage, isNull);
    controller.dispose();
  });

  test('inactive per-subject subscription surfaces its own message, no wall',
      () async {
    final sourceResolver = _FakeSourceResolver();
    final entitlementService = _FakeEntitlementService()
      ..verdict = const VideoEntitlement.denied(
        'Your subscription is not active in the current academic term.',
        denialKind: VideoDenialKind.subscriptionInactive,
      );
    final controller = _controller(
      sourceResolver: sourceResolver,
      entitlementService: entitlementService,
    );

    await controller.initialize();

    expect(sourceResolver.resolveCalls, 0);
    expect(controller.showUpgradePrompt, isFalse);
    expect(controller.playbackStatus, PlayerPlaybackStatus.error);
    expect(controller.errorMessage, 'ليس لديك اشتراك فعال في هذه المادة.');
    controller.dispose();
  });
}
