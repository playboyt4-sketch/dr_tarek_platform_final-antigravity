import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Stable, UI-agnostic error codes mirroring the platform Failure hierarchy
/// (lib/core/errors/failure.dart in the mobile app). Never contain
/// user-facing text.
enum FailureCode {
  wrongCredentials,
  approvalPending,
  accountDisabled,
  unauthorizedDevice,
  validation,
  permissionDenied,
  notFound,
  tooManyRequests,
  noInternet,
  timeout,
  server,
  unknown,
}

class Failure implements Exception {
  final FailureCode code;

  /// Technical context for logging only — never displayed.
  final String? debugDetail;
  final Object? cause;
  final StackTrace? stackTrace;

  const Failure(this.code, {this.debugDetail, this.cause, this.stackTrace});

  static Failure from(Object error, [StackTrace? stackTrace]) {
    if (error is Failure) return error;

    if (error is FirebaseFunctionsException) {
      return _fromFunctionsException(error, stackTrace);
    }

    if (error is FirebaseAuthException) {
      return _fromAuthException(error, stackTrace);
    }

    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Network is unreachable')) {
      return Failure(
        FailureCode.noInternet,
        debugDetail: text,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return Failure(
      FailureCode.unknown,
      debugDetail: text,
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static Failure _fromFunctionsException(
    FirebaseFunctionsException e,
    StackTrace? stackTrace,
  ) {
    final mapped = switch (e.code) {
      'unauthenticated' => FailureCode.wrongCredentials,
      'permission-denied' => _accountStateCode(e.message),
      'not-found' => FailureCode.notFound,
      'resource-exhausted' => FailureCode.tooManyRequests,
      'invalid-argument' => FailureCode.validation,
      'failed-precondition' => FailureCode.validation,
      'unavailable' || 'internal' || 'data-loss' => FailureCode.server,
      'deadline-exceeded' => FailureCode.timeout,
      _ => FailureCode.unknown,
    };
    return Failure(
      mapped,
      debugDetail: '${e.code}: ${e.message}',
      cause: e,
      stackTrace: stackTrace,
    );
  }

  /// The backend signals account state through generic gRPC codes; the exact
  /// message disambiguates them (fixed message dictionary server-side).
  static FailureCode _accountStateCode(String? message) {
    switch (message?.trim()) {
      case 'Account approval is required before login.':
        return FailureCode.approvalPending;
      case 'Account is not active.':
        return FailureCode.accountDisabled;
      default:
        return FailureCode.permissionDenied;
    }
  }

  static Failure _fromAuthException(
    FirebaseAuthException e,
    StackTrace? stackTrace,
  ) {
    final mapped = switch (e.code) {
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => FailureCode.wrongCredentials,
      'user-disabled' => FailureCode.accountDisabled,
      'too-many-requests' => FailureCode.tooManyRequests,
      'network-request-failed' => FailureCode.noInternet,
      _ => FailureCode.unknown,
    };
    return Failure(
      mapped,
      debugDetail: '${e.code}: ${e.message}',
      cause: e,
      stackTrace: stackTrace,
    );
  }
}
