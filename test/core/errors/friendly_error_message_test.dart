import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/errors/friendly_error_message.dart';

void main() {
  group('mapFunctionErrorCode — centralized Arabic user-facing mapping', () {
    test('permission denied', () {
      expect(
        mapFunctionErrorCode('permission-denied', 'grade access', 'x'),
        'لا تملك صلاحية تنفيذ هذه العملية.',
      );
    });

    test('invalid credentials', () {
      expect(
        mapFunctionErrorCode('unauthenticated', 'Invalid phone number or password.', 'x'),
        'بيانات الدخول غير صحيحة.',
      );
    });

    test('expired session surfaces through unauthenticated family', () {
      expect(
        mapFunctionErrorCode('unauthenticated', 'ID token expired.', 'x'),
        'بيانات الدخول غير صحيحة.',
      );
    });

    test('locked account preserves server-controlled cooldown minutes', () {
      final message = mapFunctionErrorCode(
        'resource-exhausted',
        'Too many failed attempts. Try again in 10 minute(s).',
        'fallback',
      );
      expect(message, contains('10'));
      expect(message, startsWith('عدد كبير من المحاولات الفاشلة.'));
    });

    test('resource exhaustion without cooldown text', () {
      expect(
        mapFunctionErrorCode('resource-exhausted', null, 'x'),
        'محاولات كثيرة جدًا، يرجى المحاولة لاحقًا.',
      );
    });

    test('unavailable backend', () {
      const expected = 'الخدمة غير متاحة حاليًا، حاول لاحقًا.';
      expect(mapFunctionErrorCode('unavailable', null, 'x'), expected);
      expect(mapFunctionErrorCode('internal', 'boom', 'x'), expected);
    });

    test('invalid subscription / state precondition', () {
      expect(
        mapFunctionErrorCode('failed-precondition', 'No active plan', 'x'),
        'لا يمكن تنفيذ العملية في الحالة الحالية.',
      );
    });

    test('unauthorized operation rejected via permission-denied (not leaked)',
        () {
      // The internal reason string ("grade access does not cover…") must
      // NEVER reach the user.
      final message = mapFunctionErrorCode(
        'permission-denied',
        'Your grade access does not cover this student.',
        'fallback',
      );
      expect(message, isNot(contains('grade')));
      expect(message, 'لا تملك صلاحية تنفيذ هذه العملية.');
    });

    test('deadline exceeded (exam timer)', () {
      expect(
        mapFunctionErrorCode('deadline-exceeded', 'time limit', 'x'),
        'انتهى الوقت المتاح لإكمال هذه العملية.',
      );
    });

    test('unknown code falls back to caller-supplied Arabic text', () {
      expect(mapFunctionErrorCode('data-loss', null, 'رسالة احتياطية.'), 'رسالة احتياطية.');
    });
  });

  group('friendlyFunctionErrorMessage — non-function errors', () {
    test('network failures fall back to caller Arabic text (never raw)', () {
      final error = Exception('SocketException: Failed host lookup');
      final shown = friendlyFunctionErrorMessage(error, 'تحقق من اتصالك بالإنترنت.');
      expect(shown, 'تحقق من اتصالك بالإنترنت.');
      expect(shown, isNot(contains('SocketException')));
    });

    test('null error falls back safely', () {
      expect(friendlyFunctionErrorMessage(null, 'حدث خطأ.'), 'حدث خطأ.');
    });
  });
}
