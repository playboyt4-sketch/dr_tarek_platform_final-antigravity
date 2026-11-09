import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/notifications/data/services/fcm_push_service.dart';

void main() {
  group('pollUntilReady', () {
    test('returns the first non-null value', () async {
      var calls = 0;
      final value = await pollUntilReady<String>(
        () async {
          calls++;
          return calls >= 3 ? 'ready' : null;
        },
        attempts: 5,
        interval: Duration.zero,
      );

      expect(value, 'ready');
      expect(calls, 3);
    });

    test('returns null after the attempt budget is exhausted', () async {
      var calls = 0;
      final value = await pollUntilReady<String>(
        () async {
          calls++;
          return null;
        },
        attempts: 3,
        interval: Duration.zero,
      );

      expect(value, isNull);
      expect(calls, 3);
    });

    test('propagates read failures', () async {
      await expectLater(
        pollUntilReady<String>(
          () async => throw StateError('keychain unavailable'),
          attempts: 3,
          interval: Duration.zero,
        ),
        throwsStateError,
      );
    });
  });

  group('retryWithBackoff', () {
    test('retries retryable failures and succeeds', () async {
      var calls = 0;
      final value = await retryWithBackoff<String>(
        () async {
          calls++;
          if (calls < 3) throw StateError('transient');
          return 'ok';
        },
        attempts: 3,
        baseDelay: Duration.zero,
        retryIf: (error) => error is StateError,
      );

      expect(value, 'ok');
      expect(calls, 3);
    });

    test('rethrows non-retryable failures immediately', () async {
      var calls = 0;
      await expectLater(
        retryWithBackoff<String>(
          () async {
            calls++;
            throw ArgumentError('permanent');
          },
          attempts: 3,
          baseDelay: Duration.zero,
          retryIf: (error) => error is StateError,
        ),
        throwsArgumentError,
      );

      expect(calls, 1);
    });

    test('rethrows the last error after exhausting attempts', () async {
      var calls = 0;
      await expectLater(
        retryWithBackoff<String>(
          () async {
            calls++;
            throw StateError('still failing');
          },
          attempts: 2,
          baseDelay: Duration.zero,
        ),
        throwsStateError,
      );

      expect(calls, 2);
    });

    test('does not retry when retryIf rejects the error', () async {
      var calls = 0;
      await expectLater(
        retryWithBackoff<String>(
          () async {
            calls++;
            throw StateError('permanent');
          },
          attempts: 5,
          baseDelay: Duration.zero,
          retryIf: (_) => false,
        ),
        throwsStateError,
      );

      expect(calls, 1);
    });
  });
}
