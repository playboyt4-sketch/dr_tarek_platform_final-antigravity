import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/components/video_player_layout.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/controllers/video_playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSourceGateway implements VideoSourceGateway {
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

class _FakeEntitlement implements VideoEntitlementGateway {
  @override
  Future<VideoEntitlement> resolve({
    required String userId,
    required String subjectId,
  }) async => const VideoEntitlement(
    allowed: true,
    allowedQualities: {VideoQuality.q720, VideoQuality.q480},
  );
}

class _FakePlaybackRepo implements PlaybackRepository {
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

const _ep1 = LectureSummary(
  id: 'lec-1',
  // Deliberately long Arabic title: must ellipsize on one line, never wrap
  // over the badge or sliders on narrow viewports.
  title:
      'المحاضرة الأولى: القوائم المالية المجمعة والشركات التابعة — شرح تفصيلي شامل',
  status: 'published',
  displayOrder: 0,
  isLocked: false,
  subjectId: 'subj-1',
  sectionId: 'sec-1',
  duration: Duration(minutes: 41, seconds: 5),
);

const _ep2 = LectureSummary(
  id: 'lec-2',
  title: 'المحاضرة الثانية: حسابات الشركات التابعة',
  status: 'published',
  displayOrder: 1,
  isLocked: false,
  subjectId: 'subj-1',
  sectionId: 'sec-1',
  duration: Duration(minutes: 42, seconds: 2),
);

VideoPlaybackController _readyController() {
  final controller = VideoPlaybackController(
    userId: 'test-user',
    subjectId: 'subj-1',
    sourceResolver: _FakeSourceGateway(),
    entitlementService: _FakeEntitlement(),
    playbackRepository: _FakePlaybackRepo(),
    episodes: const [_ep1, _ep2],
    episode: _ep1,
  );
  controller.controlsVisible = true;
  controller.hasDocuments = true;
  return controller;
}

Widget _playerPage(VideoPlaybackController controller) {
  // Mirrors the real route: single Scaffold, no AppBar, body fills 100%.
  // The whole tree is forced RTL like the shipped app (Arabic locale).
  return Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: Colors.black,
      body: VideoPlayerLayout(
        controller: controller,
        onBack: () {},
        onLecturesTap: () {},
        onPdfTap: () {},
        onQualityTap: () {},
        onNextTap: () {},
        onToggleControls: () {},
      ),
    ),
  );
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('player UI layer at 393x852 (iPhone)', (tester) async {
    await _setViewport(tester, const Size(393, 852));
    final controller = _readyController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: _playerPage(controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Exactly one back affordance in the whole layer (no double back).
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    await expectLater(
      find.byType(VideoPlayerLayout),
      matchesGoldenFile('goldens/player_layout_393x852.png'),
    );
  });

  testWidgets('player UI layer at 360x740 (Android)', (tester) async {
    await _setViewport(tester, const Size(360, 740));
    final controller = _readyController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: _playerPage(controller)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    await expectLater(
      find.byType(VideoPlayerLayout),
      matchesGoldenFile('goldens/player_layout_360x740.png'),
    );
  });

  testWidgets('body fills 100% of the route, no AppBar', (tester) async {
    await _setViewport(tester, const Size(393, 852));
    final controller = _readyController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: _playerPage(controller)));
    await tester.pumpAndSettle();
    final box = tester.renderObject<RenderBox>(
      find.byType(VideoPlayerLayout),
    );
    expect(box.size, const Size(393, 852));
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('ONE tap on the overlay chevron pops exactly once', (
    tester,
  ) async {
    await _setViewport(tester, const Size(393, 852));
    var pushes = 0;
    var pops = 0;
    final observer = _CountingObserver(
      onPush: () => pushes++,
      onPop: () => pops++,
    );
    final controller = _readyController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _playerPageWithPop(controller),
                  ),
                ),
                child: const Text('Open player'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open player'));
    await tester.pumpAndSettle();
    // didPush fires for the initial home route too, so the lecture tap must
    // add exactly one more push (2 total), with zero pops so far.
    expect(pushes, 2, reason: 'tapping a lecture pushes exactly one route');
    expect(pops, 0);
    expect(find.byType(VideoPlayerLayout), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);

    // The single overlay back chevron (wired to Navigator.pop exactly once
    // in the real screen) — one user tap must return to the previous page.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(pops, 1, reason: 'one back tap pops exactly once');
    expect(pushes, 2, reason: 'no extra route was ever pushed');
    expect(find.byType(VideoPlayerLayout), findsNothing);
    expect(find.text('Open player'), findsOneWidget);
  });
}

/// Player page variant whose overlay chevron is wired exactly like the real
/// screen: `onBack: () { Navigator.pop(context); }` — a single pop.
Widget _playerPageWithPop(VideoPlaybackController controller) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: Builder(
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        body: VideoPlayerLayout(
          controller: controller,
          onBack: () {
            Navigator.pop(context);
          },
          onLecturesTap: () {},
          onPdfTap: () {},
          onQualityTap: () {},
          onNextTap: () {},
          onToggleControls: () {},
        ),
      ),
    ),
  );
}

class _CountingObserver extends NavigatorObserver {
  final void Function() onPush;
  final void Function() onPop;

  _CountingObserver({required this.onPush, required this.onPop});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onPush();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => onPop();
}
