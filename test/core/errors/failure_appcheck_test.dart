// ignore_for_file: invalid_use_of_protected_member
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/core/errors/failure.dart';
import 'package:dr_tarek_platform/core/errors/friendly_error_message.dart';

/// Regression tests for BUG-AUTH: App Check attestation failures must never
/// collapse into [FailureCode.wrongCredentials] (Login's copy).
void main() {
  group('Failure.from — App Check attestation failures', () {
    test(
      'unauthenticated + App Check message maps to appCheckFailed, '
      'not wrongCredentials',
      () {
        final failure = Failure.from(
          FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'App Check token is invalid.',
          ),
        );
        expect(failure.code, FailureCode.appCheckFailed);
      },
    );

    test(
      'failed-precondition + App Check message maps to appCheckFailed',
      () {
        final failure = Failure.from(
          FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'App Check verification failed.',
          ),
        );
        expect(failure.code, FailureCode.appCheckFailed);
      },
    );

    test(
      'plain unauthenticated login failure still maps to '
      'wrongCredentials (no regression)',
      () {
        final failure = Failure.from(
          FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'Invalid phone number or password.',
          ),
        );
        expect(failure.code, FailureCode.wrongCredentials);
      },
    );

    test(
      'backend wrong_credentials errorCode still maps to '
      'wrongCredentials (no regression)',
      () {
        final failure = Failure.from(
          FirebaseFunctionsException(
            code: 'unauthenticated',
            message: 'Invalid phone number or password.',
            details: {'errorCode': 'wrong_credentials'},
          ),
        );
        expect(failure.code, FailureCode.wrongCredentials);
      },
    );

    test(
      'generic FirebaseException mentioning app-check maps to '
      'appCheckFailed',
      () {
        final failure = Failure.from(
          FirebaseException(
            plugin: 'firebase_app_check',
            code: 'unknown',
            message: 'Failed to get App Check token.',
          ),
        );
        expect(failure.code, FailureCode.appCheckFailed);
      },
    );
  });

  group('mapFunctionErrorCode — App Check guard', () {
    test(
      'unauthenticated + App Check detail returns the attestation copy, '
      'never Login\'s copy',
      () {
        final message = mapFunctionErrorCode(
          'unauthenticated',
          'App Check token is invalid.',
          'fallback',
        );
        expect(message, isNot(contains('بيانات الدخول')));
        expect(message, contains('سلامة التطبيق'));
      },
    );

    test(
      'unauthenticated + login detail still returns Login\'s copy '
      '(no regression)',
      () {
        expect(
          mapFunctionErrorCode(
            'unauthenticated',
            'Invalid phone number or password.',
            'x',
          ),
          'بيانات الدخول غير صحيحة.',
        );
      },
    );
  });
}
