import 'dart:async';

import 'package:dr_tarek_platform/core/constants/bunny_playback_headers.dart';
import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/controllers/video_playback_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Fake engine backend: completes initialization immediately and reports
/// playing on play(), so controller startup can run end to end in tests.
class _FakeVideoPlatform extends VideoPlayerPlatform {
  int _nextId = 1;
  final Map<int, StreamController<VideoEvent>> _events = {};
  Duration lastSeek = Duration.zero;
  int playCalls = 0;
  /// Every creation request received by the platform layer. Used to prove
  /// playback headers survive every engine-rebuild path.
  final List<VideoCreationOptions> creations = <VideoCreationOptions>[];

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    creations.add(options);
    final id = _nextId++;
    // Single-subscription: buffers the initialized event until the
    // controller subscribes, preserving real platform ordering
    // (initialized always precedes playing).
    final controller = StreamController<VideoEvent>();
    _events[id] = controller;
    controller.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(minutes: 10),
      size: const Size(1280, 720),
    ));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _events[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {
    playCalls++;
    _events[playerId]!.add(VideoEvent(
      eventType: VideoEventType.isPlayingStateUpdate,
      isPlaying: true,
    ));
  }

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    lastSeek = position;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }
}

class _ScriptedGateway implements VideoSourceGateway {
  int loadResourcesCalls = 0;
  int resolveCalls = 0;
  Future<List<VideoResource>> Function(String lectureId)? loadImpl;
  Future<ResolvedVideoSource> Function(VideoResource resource)? resolveImpl;
  Future<List<VideoResource>> Function(String lectureId)? loadHook;

  _ScriptedGateway({this.loadImpl, this.resolveImpl, this.loadHook});

  @override
  Future<List<VideoResource>> loadResources(String lectureId) async {
    loadResourcesCalls++;
    if (loadHook != null) return loadHook!(lectureId);
    return loadImpl!(lectureId);
  }

  @override
  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
    String? lectureId,
  }) {
    resolveCalls++;
    return resolveImpl!(resource);
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
        allowedQualities: {VideoQuality.auto},
      );
}

class _QualityEntitlement implements VideoEntitlementGateway {
  @override
  Future<VideoEntitlement> resolve({
    required String userId,
    required String subjectId,
  }) async =>
      const VideoEntitlement(
        allowed: true,
        allowedQualities: {VideoQuality.auto, VideoQuality.q720},
      );
}

class _DenyEntitlement implements VideoEntitlementGateway {
  @override
  Future<VideoEntitlement> resolve({
    required String userId,
    required String subjectId,
  }) async =>
      const VideoEntitlement.denied('Denied.');
}

class _FakePlaybackRepo implements PlaybackRepository {
  PlaybackProgressRecord? recordToReturn;

  @override
  Future<List<PlaybackProgressRecord>> getContinueWatching({
    int limit = 20,
  }) async =>
      const [];

  @override
  Future<PlaybackProgressRecord?> read(String lectureId) async =>
      recordToReturn;

  @override
  Future<void> save(
    PlaybackProgressRecord record, {
    bool syncCloud = true,
  }) async {}
}

ResolvedVideoSource _source({int? previewLimitSeconds}) {
  return ResolvedVideoSource(
    url: Uri.parse('https://cdn.example.com/v/auto/playlist.m3u8'),
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    selectedQuality: VideoQuality.auto,
    previewLimitSeconds: previewLimitSeconds,
  );
}

VideoResource _listingVideo(String id,
    {String bunny = '11111111-1111-4111-8111-111111111111'}) {
  return VideoResource(
    id: id,
    title: 'listed $id',
    resourceType: 'video',
    bunnyVideoId: bunny,
    displayOrder: 0,
  );
}

const _fastRef = FirstVideoRef(
  resourceId: 'res-fast',
  bunnyVideoId: '22222222-2222-4222-8222-222222222222',
  title: 'Fast video',
  displayOrder: 1,
);

LectureSummary _episode(String id, {FirstVideoRef? firstVideo}) {
  return LectureSummary(
    id: id,
    title: 'Lecture $id',
    status: 'published',
    displayOrder: 0,
    isLocked: false,
    subjectId: 'subj-1',
    sectionId: 'sec-1',
    firstVideo: firstVideo,
  );
}

VideoPlaybackController _controller({
  required _ScriptedGateway gateway,
  VideoEntitlementGateway? entitlement,
  _FakePlaybackRepo? repo,
  List<LectureSummary>? episodes,
  String lectureId = 'lec-1',
}) {
  final LectureSummary episode = (episodes ??
          [
            _episode('lec-1', firstVideo: _fastRef),
          ])
      .firstWhere((item) => item.id == lectureId);
  return VideoPlaybackController(
    userId: 'test-user',
    subjectId: 'subj-1',
    sourceResolver: gateway,
    entitlementService: entitlement ?? _AllowEntitlement(),
    playbackRepository: repo ?? _FakePlaybackRepo(),
    episodes: episodes ?? [_episode('lec-1', firstVideo: _fastRef)],
    episode: episode,
    deviceIdProvider: () async => 'test-device',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousPlatform = VideoPlayerPlatform.instance;
  setUpAll(() {
    VideoPlayerPlatform.instance = _FakeVideoPlatform();
    // Silence the connectivity listener in unit tests (no platform).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => null,
    );
  });
  tearDownAll(() {
    VideoPlayerPlatform.instance = previousPlatform;
  });
  setUp(() {
    (VideoPlayerPlatform.instance as _FakeVideoPlatform).creations.clear();
  });

  group('firstVideoForEpisode (pure pointer lookup)', () {
    test('finds the pointer for the active lecture', () {
      expect(
        firstVideoForEpisode(
          [_episode('lec-1', firstVideo: _fastRef), _episode('lec-2')],
          'lec-1',
        ),
        _fastRef,
      );
    });

    test('missing episode or pointer yields null (legacy path)', () {
      expect(firstVideoForEpisode([_episode('lec-1')], 'nope'), isNull);
      expect(
        firstVideoForEpisode([_episode('lec-1')], 'lec-1'),
        isNull,
      );
    });
  });

  group('Phase 5 fast lane', () {
    test('Full: listing skipped, single resolve, plays', () async {
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => [_listingVideo('res-listed')],
        resolveImpl: (_) async => _source(),
      );
      final controller = _controller(gateway: gateway);
      addTearDown(controller.dispose);

      await controller.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.playbackStatus, PlayerPlaybackStatus.playing);
      expect(controller.resource?.id, 'res-fast');
      expect(controller.resource?.bunnyVideoId,
          '22222222-2222-4222-8222-222222222222');
      // Exactly one issuance; the listing fired only for background docs/art.
      expect(gateway.resolveCalls, 1);
    });

    test('Null pointer uses the legacy listing path', () async {
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => [_listingVideo('res-listed')],
        resolveImpl: (_) async => _source(),
      );
      final controller = _controller(
        gateway: gateway,
        episodes: [_episode('lec-1')],
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(gateway.loadResourcesCalls, 1);
      expect(controller.resource?.id, 'res-listed');
      expect(controller.playbackStatus, PlayerPlaybackStatus.playing);
    });

    test('Empty bunny id falls back to legacy (no fast attempt)', () async {
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => [_listingVideo('res-listed')],
        resolveImpl: (_) async => _source(),
      );
      const malformed = FirstVideoRef(resourceId: 'r', bunnyVideoId: '');
      final controller = _controller(
        gateway: gateway,
        episodes: [_episode('lec-1', firstVideo: malformed)],
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(gateway.loadResourcesCalls, 1);
      expect(controller.resource?.id, 'res-listed');
    });

    test('Stale pointer: backend rejection falls back safely, no bypass',
        () async {
      var fastAttempt = true;
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => [_listingVideo('res-listed')],
        resolveImpl: (_) async {
          if (fastAttempt) {
            fastAttempt = false;
            throw const VideoSourceException('Video not found.');
          }
          return _source();
        },
      );
      final controller = _controller(gateway: gateway);
      addTearDown(controller.dispose);

      await controller.initialize();

      // One fast attempt + one legacy issuance; playback from the listing.
      expect(gateway.resolveCalls, 2);
      expect(gateway.loadResourcesCalls, 1);
      expect(controller.resource?.id, 'res-listed');
      expect(controller.playbackStatus, PlayerPlaybackStatus.playing);
    });

    test('Denied everywhere surfaces the legacy error, stays stopped',
        () async {
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => const <VideoResource>[],
        resolveImpl: (_) async {
          throw const VideoSourceException('Denied.');
        },
      );
      final controller = _controller(gateway: gateway);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.playbackStatus, PlayerPlaybackStatus.error);
      expect(controller.errorMessage, isNotNull);
    });

    test('Entitlement denial issues no resolve and no listing', () async {
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => [_listingVideo('res-listed')],
        resolveImpl: (_) async => _source(),
      );
      final controller = _controller(
        gateway: gateway,
        entitlement: _DenyEntitlement(),
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.playbackStatus, PlayerPlaybackStatus.error);
      expect(gateway.resolveCalls, 0);
      expect(gateway.loadResourcesCalls, 0);
    });

    test('Guest verdict from issuance is enforced like the stamped cap',
        () async {
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => [_listingVideo('res-listed')],
        resolveImpl: (_) async => _source(previewLimitSeconds: 300),
      );
      final controller = _controller(gateway: gateway);
      addTearDown(controller.dispose);

      await controller.initialize();

      // Same cap the listing path would stamp; no upgrade wall for 300s.
      expect(controller.showUpgradePrompt, isFalse);
      expect(controller.playbackStatus, PlayerPlaybackStatus.playing);
    });

    test('Zero-second Guest verdict raises the upgrade wall', () async {
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => [_listingVideo('res-listed')],
        resolveImpl: (_) async => _source(previewLimitSeconds: 0),
      );
      final controller = _controller(gateway: gateway);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.showUpgradePrompt, isTrue);
    });

    test('Resume position survives the fast lane', () async {
      final platform = VideoPlayerPlatform.instance as _FakeVideoPlatform;
      final repo = _FakePlaybackRepo()
        ..recordToReturn = PlaybackProgressRecord(
          userId: 'test-user',
          lectureId: 'lec-1',
          position: const Duration(seconds: 90),
          duration: const Duration(minutes: 10),
          progressPercent: 15,
          completed: false,
          updatedAt: DateTime.now(),
        );
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => [_listingVideo('res-listed')],
        resolveImpl: (_) async => _source(),
      );
      final controller = _controller(gateway: gateway, repo: repo);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(platform.lastSeek, const Duration(seconds: 90));
    });

    test('Background listing cannot cross-contaminate episodes', () async {
      final listingGate = Completer<List<VideoResource>>();
      final gateway = _ScriptedGateway(
        loadHook: (id) => id == 'lec-1'
            ? listingGate.future
            : Future.value([_listingVideo('res-2')]),
        resolveImpl: (_) async => _source(),
      );
      final controller = _controller(
        gateway: gateway,
        episodes: [
          _episode('lec-1', firstVideo: _fastRef),
          _episode('lec-2', firstVideo: const FirstVideoRef(
            resourceId: 'res-fast-2',
            bunnyVideoId: '33333333-3333-4333-8333-333333333333',
          )),
        ],
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.resource?.id, 'res-fast');

      // Switch away while lec-1 background listing is still in flight;
      // lec-2 legacy listing resolves instantly without documents.
      unawaited(controller.switchEpisode(
        _episode('lec-2', firstVideo: const FirstVideoRef(
          resourceId: 'res-fast-2',
          bunnyVideoId: '33333333-3333-4333-8333-333333333333',
        )),
      ));
      listingGate.complete([
        _listingVideo('res-listed'),
        const VideoResource(
          id: 'pdf-1',
          title: 'Notes',
          resourceType: 'pdf',
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.lectureId, 'lec-2');
      expect(controller.hasDocuments, isFalse);
    });
  });

  group('Phase 6 background refresh isolation', () {
    Future<VideoPlaybackController> playingFastController(
      _ScriptedGateway gateway, {
      _FakePlaybackRepo? repo,
    }) async {
      final controller = _controller(
        gateway: gateway,
        repo: repo ?? _FakePlaybackRepo(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.playbackStatus, PlayerPlaybackStatus.playing);
      expect(controller.resource?.id, 'res-fast');
      return controller;
    }

    test('Success applies docs/art without touching source or playback',
        () async {
      final listingGate = Completer<List<VideoResource>>();
      final gateway = _ScriptedGateway(
        loadHook: (_) => listingGate.future,
        resolveImpl: (_) async => _source(),
      );
      final controller = await playingFastController(gateway);

      listingGate.complete([
        const VideoResource(
          id: 'res-listed',
          title: 'Listed',
          resourceType: 'video',
          bunnyVideoId: '11111111-1111-4111-8111-111111111111',
          thumbnailUrl: 'https://signed/art.jpg',
        ),
        const VideoResource(
          id: 'pdf-1',
          title: 'Notes',
          resourceType: 'pdf',
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Active source untouched; playback undisturbed; docs/art adopted.
      expect(controller.resource?.id, 'res-fast');
      expect(controller.resource?.bunnyVideoId,
          '22222222-2222-4222-8222-222222222222');
      expect(controller.playbackStatus, PlayerPlaybackStatus.playing);
      expect(controller.errorMessage, isNull);
      expect(controller.hasDocuments, isTrue);
      expect(controller.episodeThumbnailUrl, 'https://signed/art.jpg');
      expect(controller.episodes.first.thumbnailUrl, 'https://signed/art.jpg');
      // Background issues no signed-URL request of its own.
      expect(gateway.resolveCalls, 1);
    });

    test('Failure while playing changes nothing observable', () async {
      final listingGate = Completer<List<VideoResource>>();
      final gateway = _ScriptedGateway(
        loadHook: (_) => listingGate.future,
        resolveImpl: (_) async => _source(),
      );
      final controller = await playingFastController(gateway);

      listingGate.completeError(Exception('listing exploded'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.playbackStatus, PlayerPlaybackStatus.playing);
      expect(controller.errorMessage, isNull);
      expect(controller.resource?.id, 'res-fast');
      expect(controller.hasDocuments, isFalse);
    });

    test('Dispose before completion swallows the late result', () async {
      final listingGate = Completer<List<VideoResource>>();
      final gateway = _ScriptedGateway(
        loadHook: (_) => listingGate.future,
        resolveImpl: (_) async => _source(),
      );
      final controller = _controller(gateway: gateway);
      await controller.initialize();
      expect(controller.playbackStatus, PlayerPlaybackStatus.playing);

      controller.dispose();
      listingGate.complete([
        const VideoResource(
          id: 'pdf-1',
          title: 'Notes',
          resourceType: 'pdf',
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Guarded by _disposed: no mutation, no notify crash, no error.
      expect(controller.hasDocuments, isFalse);
      expect(controller.errorMessage, isNull);
    });

    test('Background completion preserves resume state', () async {
      final platform = VideoPlayerPlatform.instance as _FakeVideoPlatform;
      final repo = _FakePlaybackRepo()
        ..recordToReturn = PlaybackProgressRecord(
          userId: 'test-user',
          lectureId: 'lec-1',
          position: const Duration(seconds: 90),
          duration: const Duration(minutes: 10),
          progressPercent: 15,
          completed: false,
          updatedAt: DateTime.now(),
        );
      final listingGate = Completer<List<VideoResource>>();
      final gateway = _ScriptedGateway(
        loadHook: (_) => listingGate.future,
        resolveImpl: (_) async => _source(),
      );
      final controller = await playingFastController(gateway, repo: repo);

      listingGate.complete([_listingVideo('res-listed')]);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.resumeRecord?.position, const Duration(seconds: 90));
      expect(platform.lastSeek, const Duration(seconds: 90));
      // Autoplay clears the prompt via play() (pre-existing); the record
      // itself — the resume state — is what the background must not touch.
      expect(controller.showResumePrompt, isFalse);
      expect(controller.playbackStatus, PlayerPlaybackStatus.playing);
    });
  });

  group('Bunny playback headers reach every native engine creation', () {
    void expectBunnyHeader(VideoCreationOptions options) {
      expect(options.dataSource.sourceType, DataSourceType.network);
      expect(options.dataSource.httpHeaders, bunnyPlaybackHttpHeaders);
      expect(options.dataSource.httpHeaders['Referer'], isNotEmpty);
      expect(options.dataSource.formatHint, VideoFormat.hls);
    }

    test('initial load attaches the Referer and the HLS hint', () async {
      final platform = VideoPlayerPlatform.instance as _FakeVideoPlatform;
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => [_listingVideo('res-listed')],
        resolveImpl: (_) async => _source(),
      );
      final controller = _controller(gateway: gateway);
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(platform.creations, hasLength(1));
      expectBunnyHeader(platform.creations.single);
    });

    test('retry reattaches the Referer on the rebuilt engine', () async {
      final platform = VideoPlayerPlatform.instance as _FakeVideoPlatform;
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => [_listingVideo('res-listed')],
        resolveImpl: (_) async => _source(),
      );
      final controller = _controller(gateway: gateway);
      addTearDown(controller.dispose);
      await controller.initialize();

      await controller.retry();

      expect(platform.creations, hasLength(2));
      expect(platform.creations.map((c) => c.dataSource.httpHeaders),
          everyElement(bunnyPlaybackHttpHeaders));
      expect(platform.creations.map((c) => c.dataSource.formatHint),
          everyElement(VideoFormat.hls));
    });

    test('quality change reattaches the Referer on the rebuilt engine',
        () async {
      final platform = VideoPlayerPlatform.instance as _FakeVideoPlatform;
      final gateway = _ScriptedGateway(
        loadImpl: (_) async => [_listingVideo('res-listed')],
        resolveImpl: (_) async => _source(),
      );
      final controller = _controller(
        gateway: gateway,
        entitlement: _QualityEntitlement(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(await controller.changeQuality(VideoQuality.q720), isTrue);

      expect(platform.creations, hasLength(2));
      expect(platform.creations.map((c) => c.dataSource.httpHeaders),
          everyElement(bunnyPlaybackHttpHeaders));
    });
  });
}
