import 'package:dr_tarek_platform/features/subject_navigation/domain/entities/subject_learning_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/repositories/playback_repository.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:dr_tarek_platform/features/video_streaming/domain/entities/playback_entities.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/components/video_states.dart';
import 'package:dr_tarek_platform/features/video_streaming/presentation/controllers/video_playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePreviewAudience — contract literals only', () {
    test('accepts guest and center', () {
      expect(parsePreviewAudience('guest'), 'guest');
      expect(parsePreviewAudience('center'), 'center');
    });

    test('missing, null, unknown, and non-string degrade to null', () {
      expect(parsePreviewAudience(null), isNull);
      expect(parsePreviewAudience('vip'), isNull);
      expect(parsePreviewAudience(''), isNull);
      expect(parsePreviewAudience('GUEST'), isNull);
      expect(parsePreviewAudience(0), isNull);
      expect(parsePreviewAudience(true), isNull);
    });
  });

  group('selectUpgradePromptContent — wall precedence', () {
    test('window block wins with Pro action and countdown', () {
      const content = UpgradePromptContent(
        kind: UpgradeWallKind.window,
        showProAction: true,
        showCountdown: true,
      );
      final selected = selectUpgradePromptContent(
        windowBlocked: true,
        previewAudience: 'guest',
        immediateZero: true,
        stampedGuestPreview: true,
        deviceBlocked: true,
      );
      expect(selected.kind, content.kind);
      expect(selected.showProAction, isTrue);
      expect(selected.showCountdown, isTrue);
    });

    test('guest zero-preview shows the Center-enrollment wall, no Pro', () {
      final selected = selectUpgradePromptContent(
        windowBlocked: false,
        previewAudience: 'guest',
        immediateZero: true,
        stampedGuestPreview: false,
        deviceBlocked: false,
      );
      expect(selected.kind, UpgradeWallKind.guestCenterOnly);
      expect(selected.showProAction, isFalse);
      expect(selected.showCountdown, isFalse);
    });

    test('center zero-preview shows the device wall, never a Pro action',
        () {
      final selected = selectUpgradePromptContent(
        windowBlocked: false,
        previewAudience: 'center',
        immediateZero: true,
        stampedGuestPreview: false,
        deviceBlocked: false,
      );
      expect(selected.kind, UpgradeWallKind.deviceNotAuthorized);
      expect(selected.showProAction, isFalse);
      expect(selected.showCountdown, isFalse);
    });

    test('issuance-declared device block outranks every upsell wall', () {
      final selected = selectUpgradePromptContent(
        windowBlocked: false,
        previewAudience: null,
        immediateZero: false,
        stampedGuestPreview: false,
        deviceBlocked: true,
      );
      expect(selected.kind, UpgradeWallKind.deviceNotAuthorized);
      expect(selected.showProAction, isFalse);
      expect(selected.showCountdown, isFalse);
    });

    test('consumed device cap (center echo, Full listing) shows device wall',
        () {
      final selected = selectUpgradePromptContent(
        windowBlocked: false,
        previewAudience: 'center',
        immediateZero: false,
        stampedGuestPreview: false,
        deviceBlocked: false,
      );
      expect(selected.kind, UpgradeWallKind.deviceNotAuthorized);
      expect(selected.showProAction, isFalse);
      expect(selected.showCountdown, isFalse);
    });

    test('consumed positive cap keeps the minutes wall', () {
      final selected = selectUpgradePromptContent(
        windowBlocked: false,
        previewAudience: 'center',
        immediateZero: false,
        stampedGuestPreview: true,
        deviceBlocked: false,
      );
      expect(selected.kind, UpgradeWallKind.previewMinutes);
      expect(selected.showProAction, isTrue);
    });

    test('unknown audience degrades to the generic paid wall', () {
      for (final audience in <String?>[null, 'vip', '']) {
        final selected = selectUpgradePromptContent(
          windowBlocked: false,
          previewAudience: audience,
          immediateZero: true,
          stampedGuestPreview: false,
          deviceBlocked: false,
        );
        expect(selected.kind, UpgradeWallKind.genericPaid,
            reason: 'audience=$audience');
        expect(selected.showProAction, isTrue);
      }
    });
  });

  group('VideoUpgradePrompt — rendered variants', () {
    // No engine, platform fakes, or async startup: the test-only seam arms
    // the exact wall state, so each variant renders deterministically.
    VideoPlaybackController wallController() {
      final controller = VideoPlaybackController(
        userId: 'test-user',
        subjectId: 'subj-1',
        sourceResolver: _FakeSourceGateway(),
        entitlementService: _AllowEntitlement(),
        playbackRepository: _FakePlaybackRepo(),
        episodes: const [],
        episode: _episode('lec-1'),
      );
      addTearDown(controller.dispose);
      return controller;
    }

    Future<void> pumpWall(
      WidgetTester tester,
      VideoPlaybackController controller, {
      required void Function() onUpgrade,
      void Function()? onBack,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                VideoUpgradePrompt(
                  controller: controller,
                  onUpgrade: onUpgrade,
                  onBack: onBack ?? () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('guest zero-preview: Center copy, contact, no Pro action',
        (tester) async {
      final controller = wallController()
        ..debugArmUpgradeWall(
          previewCap: Duration.zero,
          audience: 'guest',
        );
      var upgraded = false;
      await pumpWall(tester, controller, onUpgrade: () => upgraded = true);
      expect(find.text(kGuestWallTitle), findsOneWidget);
      expect(find.text(kGuestWallMessage), findsOneWidget);
      expect(find.text(kGuestWallContact), findsOneWidget);
      expect(find.text('الترقية إلى Pro'), findsNothing);
      expect(upgraded, isFalse);
    });

    testWidgets('center zero-preview: device copy, never a Pro action',
        (tester) async {
      final controller = wallController()
        ..debugArmUpgradeWall(
          previewCap: Duration.zero,
          audience: 'center',
        );
      var upgraded = false;
      await pumpWall(tester, controller, onUpgrade: () => upgraded = true);
      expect(find.text(kDeviceBlockedWallTitle), findsOneWidget);
      expect(find.text(kGuestWallContact), findsNothing);
      expect(find.text('الترقية إلى Pro'), findsNothing);
      expect(upgraded, isFalse);
    });

    testWidgets('issuance-declared device block: device copy, no Pro action',
        (tester) async {
      final controller = wallController()
        ..debugArmUpgradeWall(
          previewCap: const Duration(seconds: 120),
          deviceBlocked: true,
        );
      await pumpWall(tester, controller, onUpgrade: () {});
      expect(find.text(kDeviceBlockedWallTitle), findsOneWidget);
      expect(find.text('الترقية إلى Pro'), findsNothing);
    });

    testWidgets('window block: daily headline, countdown, Pro action',
        (tester) async {
      final controller = wallController()
        ..debugArmUpgradeWall(
          windowExpiresAt: DateTime.now().add(const Duration(hours: 2)),
        );
      expect(controller.dailyWindowBlocked, isTrue);
      var upgraded = false;
      await pumpWall(tester, controller, onUpgrade: () => upgraded = true);
      expect(find.text(kWindowWallTitle), findsOneWidget);
      expect(find.textContaining('متبقّي'), findsOneWidget);
      await tester.tap(find.text('الترقية إلى Pro'));
      expect(upgraded, isTrue);
    });

    testWidgets('malformed audience: generic paid wall with Pro action',
        (tester) async {
      final controller = wallController()
        ..debugArmUpgradeWall(
          previewCap: Duration.zero,
          audience: 'vip',
        );
      await pumpWall(tester, controller, onUpgrade: () {});
      expect(
          find.text('هذا المحتوى متاح لمشتركي الباقة المدفوعة.'),
          findsOneWidget);
      expect(find.text('الترقية إلى Pro'), findsOneWidget);
    });
  });
}

LectureSummary _episode(String id) {
  return LectureSummary(
    id: id,
    title: 'Lecture $id',
    status: 'published',
    displayOrder: 0,
    isLocked: false,
    subjectId: 'subj-1',
    sectionId: 'sec-1',
  );
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
        allowedQualities: {VideoQuality.auto},
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


