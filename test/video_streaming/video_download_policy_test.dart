import 'package:dr_tarek_platform/features/membership/domain/entities/membership_entities.dart';
import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_download_service.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/components/video_bottom_action_bar.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/controllers/video_playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubSourceGateway implements VideoSourceGateway {
  @override
  Future<List<VideoResource>> loadResources(String lectureId) async => const [];

  @override
  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
    String? lectureId,
  }) => throw UnimplementedError();
}

class _StubEntitlement implements VideoEntitlementGateway {
  @override
  Future<VideoEntitlement> resolve({
    required String userId,
    required String subjectId,
  }) async => const VideoEntitlement(
    allowed: true,
    allowedQualities: {VideoQuality.q720},
  );
}

class _StubPlaybackRepo implements PlaybackRepository {
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

VideoPlaybackController _controller() {
  return VideoPlaybackController(
    userId: 'u1',
    subjectId: 's1',
    sourceResolver: _StubSourceGateway(),
    entitlementService: _StubEntitlement(),
    playbackRepository: _StubPlaybackRepo(),
    episodes: const [
      LectureSummary(
        id: 'lec-1',
        title: 'المحاضرة الأولى',
        status: 'published',
        displayOrder: 0,
        isLocked: false,
      ),
    ],
    episode: const LectureSummary(
      id: 'lec-1',
      title: 'المحاضرة الأولى',
      status: 'published',
      displayOrder: 0,
      isLocked: false,
    ),
  );
}

void main() {
  group('Video download plan feature policy', () {
    test('checks video.download, max count, and MP4 quality candidates <= 1080p', () {
      const proFeatures = <PlanFeature>[
        PlanFeature(
          id: '1',
          planId: 'pro',
          featureKey: 'video.download',
          enabled: true,
        ),
        PlanFeature(
          id: '2',
          planId: 'pro',
          featureKey: 'video.download.max_count',
          enabled: true,
          featureValue: 24,
        ),
        PlanFeature(
          id: '3',
          planId: 'pro',
          featureKey: 'video.quality.720p',
          enabled: true,
        ),
        PlanFeature(
          id: '4',
          planId: 'pro',
          featureKey: 'video.quality.480p',
          enabled: true,
        ),
        PlanFeature(
          id: '5',
          planId: 'pro',
          featureKey: 'video.quality.max',
          enabled: true,
          featureValue: '720p',
        ),
      ];

      expect(isVideoDownloadFeatureEnabled(proFeatures), isTrue);
      expect(resolveVideoDownloadMaxCount(proFeatures), 24);
      expect(
        resolveDownloadQualityCandidates(
          features: proFeatures,
          preferredQuality: VideoQuality.q480,
        ),
        [
          VideoQuality.q480,
          VideoQuality.q720,
          VideoQuality.q360,
          VideoQuality.q240,
          VideoQuality.q144,
        ],
      );

      expect(
        isVideoDownloadFeatureEnabled(const [
          PlanFeature(
            id: 'f1',
            planId: 'free',
            featureKey: 'video.download',
            enabled: false,
          ),
        ]),
        isFalse,
      );
    });
  });

  group('VideoBottomActionBar download control', () {
    testWidgets('renders Download, progress %, and Saved states when wired', (
      tester,
    ) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      var taps = 0;

      Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(backgroundColor: Colors.black, body: child),
      );

      await tester.pumpWidget(
        wrap(
          VideoBottomActionBar(
            controller: controller,
            onLecturesTap: () {},
            onPdfTap: () {},
            onQualityTap: () {},
            onNextTap: () {},
            onDownloadTap: () => taps++,
          ),
        ),
      );
      expect(find.text('Download'), findsOneWidget);
      await tester.tap(find.text('Download'));
      expect(taps, 1);

      await tester.pumpWidget(
        wrap(
          VideoBottomActionBar(
            controller: controller,
            onLecturesTap: () {},
            onPdfTap: () {},
            onQualityTap: () {},
            onNextTap: () {},
            onDownloadTap: () {},
            isDownloading: true,
            downloadProgress: 0.42,
          ),
        ),
      );
      expect(find.text('42%'), findsOneWidget);

      await tester.pumpWidget(
        wrap(
          VideoBottomActionBar(
            controller: controller,
            onLecturesTap: () {},
            onPdfTap: () {},
            onQualityTap: () {},
            onNextTap: () {},
            onDownloadTap: () {},
            isDownloaded: true,
          ),
        ),
      );
      expect(find.text('Saved'), findsOneWidget);
    });
  });
}
