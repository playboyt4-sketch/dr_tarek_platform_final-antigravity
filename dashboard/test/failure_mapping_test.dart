// ignore_for_file: invalid_use_of_protected_member
import 'package:cloud_functions/cloud_functions.dart';
import 'package:drtarek_dashboard/core/errors/failure.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dashboard-scoped proof that the ported BUG-AUTH guard maps callable
/// failures correctly for Admin/Teacher dashboard actions.
/// Mirrors `test/core/errors/failure_appcheck_test.dart` in the parent app.
void main() {
  group('Dashboard callable failures — unified Failure mapping', () {
    test(
      'App Check rejection on an admin callable surfaces appCheckFailed, '
      'never wrongCredentials',
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
      'genuine staff wrong-password failure still surfaces '
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
      'non-staff gate signal still surfaces permissionDenied '
      '(no regression)',
      () {
        final failure = Failure.from(
          FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Only approved staff may access the dashboard.',
          ),
        );
        expect(failure.code, FailureCode.permissionDenied);
      },
    );
  });
}
