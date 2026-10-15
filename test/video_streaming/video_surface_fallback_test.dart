import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/components/video_surface.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/controllers/video_playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Swallows platform-channel calls (dispose) so engine injection stays
/// channel-free. `VideoPlayer` renders a plain [Container] for a
/// never-platform-initialized controller, so no view factory is needed.
class _FakeVideoPlatform extends VideoPlayerPlatform {
  @override
  Future<void> dispose(int playerId) async {}
}

class _FakeSourceGateway implements VideoSourceGateway {
  @override
  Future<List<VideoResource>> loadResources(String lectureId) async =>
      const <VideoResource>[];

  @override
  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
    String? lectureId,
  }) =>
      throw UnimplementedError();
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

class _FakePlaybackRepo implements PlaybackRepository {
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
      status: 'published',
      displayOrder: 0,
      isLocked: false,
      subjectId: 'subj-1',
      sectionId: 'sec-1',
    );

/// Builds a playback controller whose engine reports [size] with metadata
/// (duration) but without any platform initialization — the exact web state
/// when hls.js reports duration before video dimensions arrive.
VideoPlaybackController _controllerWithEngineSize(Size size) {
  final controller = VideoPlaybackController(
    userId: 'test-user',
    subjectId: 'subj-1',
    sourceResolver: _FakeSourceGateway(),
    entitlementService: _AllowEntitlement(),
    playbackRepository: _FakePlaybackRepo(),
    episodes: [_episode('lec-1')],
    episode: _episode('lec-1'),
  );
  final engine = VideoPlayerController.networkUrl(
    Uri.parse('https://example.com/video/playlist.m3u8'),
  );
  engine.value = engine.value.copyWith(
    isInitialized: true,
    duration: const Duration(minutes: 23, seconds: 13),
    size: size,
  );
  controller.debugInjectEngine(engine);
  addTearDown(() {
    engine.dispose();
    controller.dispose();
  });
  return controller;
}

Future<void> _pumpSurface(
  WidgetTester tester,
  VideoPlaybackController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: VideoSurface(controller: controller)),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() {
    VideoPlayerPlatform.instance = _FakeVideoPlatform();
  });

  group('hasRenderableSize', () {
    test('zero or partial dimensions are not renderable', () {
      expect(VideoSurface.hasRenderableSize(Size.zero), isFalse);
      expect(
        VideoSurface.hasRenderableSize(const Size(1280, 0)),
        isFalse,
      );
      expect(
        VideoSurface.hasRenderableSize(const Size(0, 720)),
        isFalse,
      );
    });

    test('positive dimensions are renderable', () {
      expect(
        VideoSurface.hasRenderableSize(const Size(1280, 720)),
        isTrue,
      );
    });
  });

  group('VideoSurface zero-size fallback', () {
    testWidgets(
      'initialized engine with Size.zero renders a visible 16:9 box, '
      'never a zero box',
      (tester) async {
        final controller = _controllerWithEngineSize(Size.zero);
        await _pumpSurface(tester, controller);

        final aspect = tester.widget<AspectRatio>(find.byType(AspectRatio));
        expect(aspect.aspectRatio, VideoSurface.kFallbackDisplayAspectRatio);
        expect(find.byType(FittedBox), findsNothing);
        // The fallback box must occupy real space (regression: zero box
        // hid decoded frames permanently while audio kept playing).
        expect(tester.getSize(find.byType(AspectRatio)).width, greaterThan(0));
      },
    );

    testWidgets(
      'initialized engine with valid size keeps the cover path unchanged',
      (tester) async {
        final controller =
            _controllerWithEngineSize(const Size(1280, 720));
        await _pumpSurface(tester, controller);

        expect(find.byType(FittedBox), findsOneWidget);
        expect(find.byType(AspectRatio), findsNothing);
      },
    );
  });
}
