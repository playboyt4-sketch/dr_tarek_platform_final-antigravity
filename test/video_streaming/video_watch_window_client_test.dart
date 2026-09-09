import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';

void main() {
  group('classifyVideoSourceError - FINAL_DECISIONS S12 contract', () {
    test('maps the Center Free window sentinel to the typed exception', () {
      final error = classifyVideoSourceError(
        'resource-exhausted',
        'A Center Free 24-hour video window is already active for another video.',
        <String, dynamic>{
          'activeLectureId': 'lec-9',
          'windowExpiresAtMs': 123456789,
        },
      );

      expect(error, isA<FreeWindowBlockedException>());
      final blocked = error as FreeWindowBlockedException;
      expect(blocked.activeLectureId, 'lec-9');
      expect(blocked.windowExpiresAtMs, 123456789);
      expect(blocked.message, isNotEmpty);
    });

    test('sentinel without details still classifies', () {
      final error = classifyVideoSourceError(
        'resource-exhausted',
        ' A Center Free 24-hour video window is already active for another video. ',
        null,
      );

      expect(error, isA<FreeWindowBlockedException>());
      final blocked = error as FreeWindowBlockedException;
      expect(blocked.windowExpiresAtMs, isNull);
      expect(blocked.activeLectureId, isNull);
    });

    test('non-window errors keep their generic messages', () {
      final denied = classifyVideoSourceError(
        'permission-denied',
        'nope',
        null,
      );
      expect(denied, isNot(isA<FreeWindowBlockedException>()));
      expect(
        denied.message,
        'لا تملك صلاحية مشاهدة هذا الفيديو أو انتهى اشتراكك.',
      );

      final generic = classifyVideoSourceError('internal', null, null);
      expect(generic.message, 'تعذر تحميل الفيديو. حاول مرة أخرى.');
    });

    test('server windowHours override the default 24h message', () {
      final error = classifyVideoSourceError(
        'resource-exhausted',
        'A Center Free 24-hour video window is already active for another video.',
        <String, dynamic>{'windowHours': 12},
      );

      expect(error, isA<FreeWindowBlockedException>());
      final blocked = error as FreeWindowBlockedException;
      expect(blocked.windowHours, 12);
      expect(
        blocked.message,
        'باقتك تسمح بمشاهدة فيديو واحد كل 12 ساعة.',
      );
    });

    test('missing windowHours keeps the legacy 24h message', () {
      final error = classifyVideoSourceError(
        'resource-exhausted',
        'A Center Free 24-hour video window is already active for another video.',
        null,
      );

      final blocked = error as FreeWindowBlockedException;
      expect(blocked.windowHours, 24);
      expect(
        blocked.message,
        'باقتك المجانية تسمح بمشاهدة فيديو واحد كل ٢٤ ساعة.',
      );
    });

    test('client sentinel literal matches the server constant exactly', () {
      // Drift guard: functions/src/index.ts exports
      // FREE_WINDOW_BLOCKED_MESSAGE with this exact value.
      expect(
        kFreeWindowBlockedMessage,
        'A Center Free 24-hour video window is already active for another video.',
      );
    });
  });
}
