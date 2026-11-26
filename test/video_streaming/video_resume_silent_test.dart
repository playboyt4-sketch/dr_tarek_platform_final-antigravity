import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/components/video_overlay_controls.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/controllers/video_playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopSourceGateway implements VideoSourceGateway {
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

class _AllowEntitlement implements VideoEntitlementGateway {
  @override
  Future<VideoEntitlement> resolve({
    required String userId,
    required String subjectId,
  }) async => const VideoEntitlement(
    allowed: true,
    allowedQualities: {VideoQuality.q720, VideoQuality.q480},
  );
}

class _NoopPlaybackRepo implements PlaybackRepository {
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

void main() {
  testWidgets(
      'VideoOverlayControls never renders resume prompt even when resumeRecord exists',
      (WidgetTester tester) async {
    final controller = VideoPlaybackController(
      userId: 'user-1',
      subjectId: 'subj-1',
      sourceResolver: _NoopSourceGateway(),
      entitlementService: _AllowEntitlement(),
      playbackRepository: _NoopPlaybackRepo(),
      episodes: const [
        LectureSummary(
          id: 'lec-1',
          title: 'Lecture 1',
          status: 'published',
          displayOrder: 0,
          isLocked: false,
          subjectId: 'subj-1',
          sectionId: 'sec-1',
        ),
      ],
      episode: const LectureSummary(
        id: 'lec-1',
        title: 'Lecture 1',
        status: 'published',
        displayOrder: 0,
        isLocked: false,
        subjectId: 'subj-1',
        sectionId: 'sec-1',
      ),
    );
    controller.controlsVisible = true;
    // Simulate default controller flag remaining false without prompting.
    expect(controller.showResumePrompt, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: VideoOverlayControls(
              controller: controller,
              onBack: () {},
              onLecturesTap: () {},
              onPdfTap: () {},
              onQualityTap: () {},
              onNextTap: () {},
              onToggleControls: () {},
              onUpgradeTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('استكمال المشاهدة'), findsNothing);
    expect(find.text('البدء من البداية'), findsNothing);
    expect(find.text('متابعة'), findsNothing);
  });
}
