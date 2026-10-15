import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Stable, UI-agnostic error codes mirroring the platform Failure hierarchy
/// (lib/core/errors/failure.dart in the mobile app). Never contain
/// user-facing text.
///
/// NOTE (Single Source of Truth gap, reported): this file is a drift-copy
/// of the mobile app's canonical hierarchy. A path dependency
/// (`dr_tarek_platform: path: ../`) was attempted so the dashboard could
/// import the canonical file directly, but version solving fails: the
/// parent's `flutter_local_notifications_windows` chain pins `xml ^6.5.0`
/// while the dashboard's `pdf 3.13.0` requires `xml ^7.0.1`. Until the team
/// aligns those dependency versions (or extracts a shared pure-Dart errors
/// package), this copy is kept in sync MANUALLY — any change to the
/// canonical file's mapping logic must be ported here, including the
/// BUG-AUTH `appCheckFailed` guard below.
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

  /// Client attestation failed (App Check): missing, expired, or
  /// unregistered (debug) token. Transport-level, never credential-level —
  /// it must never collapse into [wrongCredentials] (BUG-AUTH fix, ported
  /// from the canonical hierarchy).
  appCheckFailed,

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

    if (error is FirebaseException) {
      if (_isAppCheckSignal(error.code, error.message)) {
        return Failure(
          FailureCode.appCheckFailed,
          debugDetail: '${error.code}: ${error.message}',
          cause: error,
          stackTrace: stackTrace,
        );
      }
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
    // BUG-AUTH fix (ported): App Check enforcement rejections arrive with
    // generic gRPC codes (usually `unauthenticated`), so the message signal
    // MUST be checked before the code-based mapping below. Otherwise every
    // attestation failure collapses into [FailureCode.wrongCredentials].
    if (_isAppCheckSignal(e.code, e.message)) {
      return Failure(
        FailureCode.appCheckFailed,
        debugDetail: '${e.code}: ${e.message}',
        cause: e,
        stackTrace: stackTrace,
      );
    }
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

  /// True when the backend/client signal describes an App Check attestation
  /// failure. Both the Firebase JS SDK and Functions v2 `enforceAppCheck`
  /// rejections mention App Check in the code or message while reusing
  /// generic gRPC codes.
  static bool _isAppCheckSignal(String? code, String? message) {
    final haystack = '${code ?? ''} ${message ?? ''}'.toLowerCase();
    return haystack.contains('app check') || haystack.contains('app-check');
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
