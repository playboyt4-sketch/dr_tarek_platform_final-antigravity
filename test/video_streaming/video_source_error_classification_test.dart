import 'package:dr_tarek_platform/features/video_streaming/data/services/video_source_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ADR-010 Batch 3c — Video Source Error Classification', () {
    test('maps library_not_resolved to VideoLibraryNotResolvedException with Arabic message and retryable', () {
      final error = classifyVideoSourceError(
        'failed-precondition',
        'Video playback is not configured.',
        <String, dynamic>{'reason': 'library_not_resolved'},
      );

      expect(error, isA<VideoLibraryNotResolvedException>());
      expect(error.isRetryable, isTrue);
      expect(error.message, contains('الفيديو غير مرتبط بمكتبة تشغيل'));
    });

    test('maps unassociated string to VideoLibraryNotResolvedException', () {
      final error = classifyVideoSourceError(
        'failed-precondition',
        'unassociated video cannot be resolved',
        null,
      );

      expect(error, isA<VideoLibraryNotResolvedException>());
      expect(error.isRetryable, isTrue);
      expect(error.message, contains('الفيديو غير مرتبط بمكتبة تشغيل'));
    });

    test('maps verification_pending to VideoVerificationPendingException with Arabic message and retryable', () {
      final error = classifyVideoSourceError(
        'failed-precondition',
        'video is pending verification',
        <String, dynamic>{'reason': 'verification_pending'},
      );

      expect(error, isA<VideoVerificationPendingException>());
      expect(error.isRetryable, isTrue);
      expect(error.message, contains('الفيديو قيد التحقق حالياً'));
    });

    test('retains generic messages for standard errors', () {
      final denied = classifyVideoSourceError('permission-denied', 'no access', null);
      expect(denied, isA<VideoSourceException>());
      expect(denied.isRetryable, isFalse);
      expect(
        denied.message,
        'You do not have permission to watch this video, or your subscription has ended.',
      );
    });
  });
}
