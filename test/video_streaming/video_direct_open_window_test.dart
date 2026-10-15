import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/controllers/video_playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression: Center Free A → Exit → direct-open C must preserve Center Free
// identity and surface the SAME 24-hour rolling-window restriction as the
// Next flow — never Guest behavior, never a device wall.
//
// PATH A (Next): open A → Next → B. The controller walls from the
// client-side window snapshot without ever calling issuance for B.
// PATH B (direct open): open A → exit → directly open C. The fresh
// controller calls issuance for C; the server MUST answer with the same
// resource-exhausted window verdict (window-before-tier precedence), so the
// controller lands on the identical wall instead of Guest/device behavior.

class _RecordingGateway implements VideoSourceGateway {
  final List<String?> resolveLectureIds = [];
  int loadResourcesCalls = 0;
  Exception? resolveError;

  static const validBunnyId = '66666666-6666-4666-8666-666666666666';

  @override
  Future<List<VideoResource>> loadResources(String lectureId) async {
    loadResourcesCalls++;
    return const [
      VideoResource(
        id: 'res-1',
        title: 'Video',
        resourceType: 'video',
        bunnyVideoId: validBunnyId,
      ),
    ];
  }

  @override
  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
    String? lectureId,
  }) async {
    resolveLectureIds.add(lectureId);
    final error = resolveError;
    if (error != null) throw error;
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

class _BlockingWindowGateway implements WatchWindowGateway {
  final String activeLectureId;

  const _BlockingWindowGateway(this.activeLectureId);

  @override
  Future<WatchWindowSnapshot> load() async => WatchWindowSnapshot(
        active: true,
        activeLectureId: activeLectureId,
        expiresAt: DateTime.now().add(const Duration(hours: 23)),
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

VideoPlaybackController _controllerFor({
  required VideoSourceGateway gateway,
  required LectureSummary episode,
  required List<LectureSummary> episodes,
  WatchWindowGateway? windowGateway,
}) {
  return VideoPlaybackController(
    userId: 'student-1',
    subjectId: 'subject-1',
    sourceResolver: gateway,
    entitlementService: _AllowEntitlement(),
    playbackRepository: _FakePlaybackRepository(),
    episodes: episodes,
    episode: episode,
    watchWindowGateway: windowGateway,
  );
}

FreeWindowBlockedException _windowBlockedFor(String activeLectureId) =>
    FreeWindowBlockedException(
      message: 'window active',
      windowExpiresAtMs:
          DateTime.now().add(const Duration(hours: 23)).millisecondsSinceEpoch,
      activeLectureId: activeLectureId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'PATH A: Next to a window-blocked lecture walls without issuance '
      '(24-hour restriction works)', () async {
    final gateway = _RecordingGateway();
    final episodes = [_episode('lec-A'), _episode('lec-B')];
    final controller = _controllerFor(
      gateway: gateway,
      episode: episodes.first,
      episodes: episodes,
      windowGateway: const _BlockingWindowGateway('lec-A'),
    );
    addTearDown(controller.dispose);

    await controller.switchEpisode(episodes[1]);

    expect(gateway.resolveLectureIds, isEmpty,
        reason: 'Next must wall from the window snapshot, never minting a URL');
    expect(controller.showUpgradePrompt, isTrue);
    expect(controller.dailyWindowBlocked, isTrue);
    expect(controller.deviceBlocked, isFalse,
        reason: 'window wall is never a device wall');
    expect(controller.previewAudience, isNull,
        reason: 'window wall carries no Guest audience');
  });

  test(
      'PATH B: direct-open of a window-blocked lecture lands on the SAME '
      'wall — never Guest', () async {
    final gateway = _RecordingGateway()
      // Server window verdict for C while the window is active for A
      // (window-before-tier precedence: resource-exhausted, not Guest).
      ..resolveError = _windowBlockedFor('lec-A');
    final controller = _controllerFor(
      gateway: gateway,
      episode: _episode('lec-C'),
      episodes: [_episode('lec-A'), _episode('lec-C')],
      windowGateway: const _BlockingWindowGateway('lec-A'),
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    // Identity propagation: the route lecture is the issuance identity.
    expect(gateway.resolveLectureIds, ['lec-C']);
    // Same restriction as PATH A — Center Free identity intact.
    expect(controller.showUpgradePrompt, isTrue);
    expect(controller.dailyWindowBlocked, isTrue);
    expect(controller.dailyWindowExpiresAt, isNotNull);
    // Absolute no-Guest-fallback rule.
    expect(controller.deviceBlocked, isFalse,
        reason: 'Center Free must never downgrade to Guest/device');
    expect(controller.previewAudience, isNull,
        reason: 'window wall carries no Guest audience');
  });

  test('PATH A and PATH B produce the identical wall state', () async {
    final nextGateway = _RecordingGateway();
    final nextEpisodes = [_episode('lec-A'), _episode('lec-B')];
    final nextController = _controllerFor(
      gateway: nextGateway,
      episode: nextEpisodes.first,
      episodes: nextEpisodes,
      windowGateway: const _BlockingWindowGateway('lec-A'),
    );
    addTearDown(nextController.dispose);
    await nextController.switchEpisode(nextEpisodes[1]);

    final directGateway = _RecordingGateway()
      ..resolveError = _windowBlockedFor('lec-A');
    final directController = _controllerFor(
      gateway: directGateway,
      episode: _episode('lec-C'),
      episodes: [_episode('lec-A'), _episode('lec-C')],
      windowGateway: const _BlockingWindowGateway('lec-A'),
    );
    addTearDown(directController.dispose);
    await directController.initialize();

    expect(directController.showUpgradePrompt, nextController.showUpgradePrompt);
    expect(directController.dailyWindowBlocked, isTrue);
    expect(nextController.dailyWindowBlocked, isTrue);
    expect(directController.deviceBlocked, isFalse);
    expect(nextController.deviceBlocked, isFalse);
    expect(directController.playbackStatus, nextController.playbackStatus);
  });

  test(
      'device wall appears ONLY on genuine device denial with no window '
      'block (control)', () async {
    final gateway = _RecordingGateway()
      ..resolveError = const DeviceNotAuthorizedException('device blocked');
    final controller = _controllerFor(
      gateway: gateway,
      episode: _episode('lec-C'),
      episodes: [_episode('lec-A'), _episode('lec-C')],
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(gateway.resolveLectureIds, ['lec-C']);
    expect(controller.deviceBlocked, isTrue);
    expect(controller.showUpgradePrompt, isTrue);
    expect(controller.dailyWindowBlocked, isFalse,
        reason: 'a true device denial is not a window wall');
    expect(controller.dailyWindowExpiresAt, isNull);
  });
}
