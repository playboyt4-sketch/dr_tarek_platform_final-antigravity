import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/components/video_quality_sheet.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/controllers/video_playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Presentation regression tests for the reference quality modal
// (`docs/video player .html`): the sheet renders EXACTLY the entitlement's
// allowed qualities (already capped by `video.quality.max` in
// VideoEntitlementService) — disallowed renditions never appear (no locks,
// no disabled rows) — with the active rendition highlighted + checked.

class _FakeSourceGateway implements VideoSourceGateway {
  @override
  Future<List<VideoResource>> loadResources(String lectureId) async =>
      const [];

  @override
  Future<ResolvedVideoSource> resolve({
    required VideoResource resource,
    required VideoQuality quality,
    String? subjectId,
    String? lectureId,
  }) =>
      throw UnimplementedError();
}

class _FakeEntitlement implements VideoEntitlementGateway {
  VideoEntitlement verdict;

  _FakeEntitlement(this.verdict);

  @override
  Future<VideoEntitlement> resolve({
    required String userId,
    required String subjectId,
  }) async =>
      verdict;
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
      status: 'not_started',
      displayOrder: 0,
      isLocked: false,
    );

/// Arms [VideoEntitlement] on the controller without a playable engine:
/// resources are empty so source preparation fails AFTER the entitlement
/// gate — the verdict itself stays set, which is all the sheet reads.
Future<VideoPlaybackController> _controllerWith(
  Set<VideoQuality> allowed, {
  VideoQuality selected = VideoQuality.auto,
}) async {
  final episodes = [_episode('ep-1')];
  final controller = VideoPlaybackController(
    userId: 'student-1',
    subjectId: 'subject-1',
    sourceResolver: _FakeSourceGateway(),
    entitlementService: _FakeEntitlement(
      VideoEntitlement(allowed: true, allowedQualities: allowed),
    ),
    playbackRepository: _FakePlaybackRepo(),
    episodes: episodes,
    episode: episodes.first,
  );
  await controller.initialize();
  controller.selectedQuality = selected;
  return controller;
}

Future<void> _pumpSheet(
  WidgetTester tester,
  VideoPlaybackController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: VideoQualitySheet(controller: controller, onClose: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('480p subscription lists only 144p..480p, 480p checked',
      (tester) async {
    final controller = await _controllerWith(
      {VideoQuality.q144, VideoQuality.q240, VideoQuality.q360, VideoQuality.q480},
      selected: VideoQuality.q480,
    );
    addTearDown(controller.dispose);

    await _pumpSheet(tester, controller);

    expect(find.text('Quality'), findsOneWidget);
    for (final label in ['144p', '240p', '360p', '480p']) {
      expect(find.text(label), findsOneWidget, reason: '$label must be listed');
    }
    expect(find.text('720p'), findsNothing);
    expect(find.text('1080p'), findsNothing);
    // No Auto row, no cancel affordance, no lock/disabled rows.
    expect(find.text('Auto'), findsNothing);
    expect(find.text('إلغاء'), findsNothing);
    expect(find.byIcon(Icons.lock), findsNothing);
    // Exactly one checked (active) row.
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('720p subscription adds 720p only', (tester) async {
    final controller = await _controllerWith(
      {
        VideoQuality.q144,
        VideoQuality.q240,
        VideoQuality.q360,
        VideoQuality.q480,
        VideoQuality.q720,
      },
      selected: VideoQuality.q720,
    );
    addTearDown(controller.dispose);

    await _pumpSheet(tester, controller);

    expect(find.text('720p'), findsOneWidget);
    expect(find.text('1080p'), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('1080p subscription lists the full configured set',
      (tester) async {
    final controller = await _controllerWith(
      {
        VideoQuality.q144,
        VideoQuality.q240,
        VideoQuality.q360,
        VideoQuality.q480,
        VideoQuality.q720,
        VideoQuality.q1080,
      },
      selected: VideoQuality.q1080,
    );
    addTearDown(controller.dispose);

    await _pumpSheet(tester, controller);

    for (final label in ['144p', '240p', '360p', '480p', '720p', '1080p']) {
      expect(find.text(label), findsOneWidget, reason: '$label must be listed');
    }
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('options render ascending by rendition rank', (tester) async {
    final controller = await _controllerWith(
      // Deliberately unordered set: the sheet must still sort 144p first.
      {VideoQuality.q480, VideoQuality.q144, VideoQuality.q360, VideoQuality.q240},
      selected: VideoQuality.q144,
    );
    addTearDown(controller.dispose);

    await _pumpSheet(tester, controller);

    final labels = tester
        .widgetList<Text>(find.byWidgetPredicate(
            (widget) => widget is Text && widget.data?.endsWith('p') == true))
        .map((text) => text.data!)
        .toList();
    expect(labels, ['144p', '240p', '360p', '480p']);
  });
}
