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

      expect(error, isA<CenterFreeWindowBlockedException>());
      final blocked = error as CenterFreeWindowBlockedException;
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

      expect(error, isA<CenterFreeWindowBlockedException>());
      final blocked = error as CenterFreeWindowBlockedException;
      expect(blocked.windowExpiresAtMs, isNull);
      expect(blocked.activeLectureId, isNull);
    });

    test('non-window errors keep their generic messages', () {
      final denied = classifyVideoSourceError(
        'permission-denied',
        'nope',
        null,
      );
      expect(denied, isNot(isA<CenterFreeWindowBlockedException>()));
      expect(
        denied.message,
        'لا تملك صلاحية مشاهدة هذا الفيديو أو انتهى اشتراكك.',
      );

      final generic = classifyVideoSourceError('internal', null, null);
      expect(generic.message, 'تعذر تحميل الفيديو. حاول مرة أخرى.');
    });

    test('client sentinel literal matches the server constant exactly', () {
      // Drift guard: functions/src/index.ts exports
      // CENTER_FREE_WINDOW_BLOCKED_MESSAGE with this exact value (asserted
      // server-side in sections_12_13.test.js).
      expect(
        kCenterFreeWindowBlockedMessage,
        'A Center Free 24-hour video window is already active for another video.',
      );
    });
  });
}
