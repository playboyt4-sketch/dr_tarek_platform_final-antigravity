import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Stable, UI-agnostic error codes. Never contain user-facing text;
/// presentation layers translate them via [failureMessage].
enum FailureCode {
  wrongCredentials,
  approvalPending,
  accountDisabled,
  accountRejected,
  phoneAlreadyExists,
  unauthorizedDevice,
  wrongCurrentPassword,
  weakPassword,
  validation,
  permissionDenied,
  notFound,
  sectionHasActiveLectures,
  tooManyRequests,
  subscriptionRequired,
  subscriptionExpired,
  subscriptionInactive,
  disciplinaryDisabled,

  /// FINAL_DECISIONS §12: a Center Free student tried to start a DIFFERENT
  /// video while their rolling 24-hour window is still active.
  dailyVideoLimitReached,
  noInternet,
  timeout,
  server,
  unknown,
}

class Failure implements Exception {
  final FailureCode code;

  /// Technical context for logging/crash reporting only — never displayed.
  final String? debugDetail;
  final Object? cause;
  final StackTrace? stackTrace;

  const Failure(this.code, {this.debugDetail, this.cause, this.stackTrace});

  /// Maps any thrown object into a typed [Failure].
  ///
  /// Cloud Functions business messages are mapped by their exact strings
  /// (the backend has a fixed message dictionary); everything else falls
  /// back to the gRPC-style error code mapping.
  static Failure from(
    Object error, [
    StackTrace? stackTrace,
  ]) {
    if (error is Failure) return error;

    // --- Cloud Functions (primary backend surface) ---
    if (error is FirebaseFunctionsException) {
      return _fromFunctionsException(error, stackTrace);
    }

    // --- Firebase Auth (custom token sign-in) ---
    if (error is FirebaseAuthException) {
      return _fromAuthException(error, stackTrace);
    }

    // --- Firestore / General Firebase ---
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return Failure(
          FailureCode.permissionDenied,
          debugDetail: error.message ?? 'Permission denied.',
          stackTrace: stackTrace,
        );
      }
    }

    // --- Network ---
    if (error is NetworkUnreachableException ||
        error.toString().contains('SocketException') ||
        error.toString().contains('Failed host lookup')) {
      return Failure(
        FailureCode.noInternet,
        debugDetail: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is TimeoutException) {
      return Failure(
        FailureCode.timeout,
        debugDetail: error.toString(),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    return Failure(
      FailureCode.unknown,
      debugDetail: error.toString(),
      cause: error,
      stackTrace: stackTrace,
    );
  }

  static Failure _fromFunctionsException(
    FirebaseFunctionsException e,
    StackTrace? stackTrace,
  ) {
    if (e.details is Map) {
      final String? errorCode = e.details['errorCode'];
      if (errorCode != null) {
        final mapped = _businessCodeByErrorCode(errorCode);
        if (mapped != null) {
          return Failure(
            mapped,
            debugDetail: '${e.code}: ${e.message}',
            cause: e,
            stackTrace: stackTrace,
          );
        }
      }
    }

    final code = _businessCodeByMessage(e.message);
    if (code != null) {
      return Failure(
        code,
        debugDetail: '${e.code}: ${e.message}',
        cause: e,
        stackTrace: stackTrace,
      );
    }

    final mapped = switch (e.code) {
      'unauthenticated' => FailureCode.wrongCredentials,
      'permission-denied' => FailureCode.permissionDenied,
      'not-found' => FailureCode.notFound,
      'already-exists' => FailureCode.phoneAlreadyExists,
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

  static FailureCode? _businessCodeByErrorCode(String errorCode) {
    return switch (errorCode) {
      'wrong_credentials' => FailureCode.wrongCredentials,
      'approval_pending' => FailureCode.approvalPending,
      'account_disabled' => FailureCode.accountDisabled,
      'phone_already_exists' => FailureCode.phoneAlreadyExists,
      'wrong_current_password' => FailureCode.wrongCurrentPassword,
      'subscription_required' => FailureCode.subscriptionRequired,
      'subscription_inactive' => FailureCode.subscriptionInactive,
      'too_many_requests' => FailureCode.tooManyRequests,
      'daily_video_limit_reached' => FailureCode.dailyVideoLimitReached,
      'unauthorized_device' => FailureCode.unauthorizedDevice,
      'weak_password' => FailureCode.weakPassword,
      'subscription_expired' => FailureCode.subscriptionExpired,
      'disciplinary_disabled' => FailureCode.disciplinaryDisabled,
      _ => null,
    };
  }

  /// Exact-message map for backend business rules that reuse generic
  /// gRPC codes (e.g., login state signals sent as `permission-denied`).
  static FailureCode? _businessCodeByMessage(String? message) {
    if (message == null) return null;
    final m = message.trim();
    if (_exactMessageCodes.containsKey(m)) return _exactMessageCodes[m];

    // Substring fallbacks for messages with interpolated parts.
    if (m.startsWith('Subscription has expired')) {
      return FailureCode.subscriptionExpired;
    }
    if (m.contains('disciplinarily disabled')) {
      return FailureCode.disciplinaryDisabled;
    }
    if (m.contains('device is not authorized') ||
        m.contains('Unauthorized device')) {
      return FailureCode.unauthorizedDevice;
    }
    if (m.contains('Password must contain at least')) {
      return FailureCode.weakPassword;
    }
    return null;
  }

  static const Map<String, FailureCode> _exactMessageCodes = {
    'Invalid phone number or password.': FailureCode.wrongCredentials,
    'Account approval is required before login.':
        FailureCode.approvalPending,
    'Account is not active.': FailureCode.accountDisabled,
    'An account with this phone number already exists.':
        FailureCode.phoneAlreadyExists,
    'Current password is incorrect.': FailureCode.wrongCurrentPassword,
    'Subject subscription is required.': FailureCode.subscriptionRequired,
    'Subscription is not active.': FailureCode.subscriptionInactive,
    'Subscription is deleted.': FailureCode.subscriptionInactive,
    'Too many video requests. Please retry shortly.':
        FailureCode.tooManyRequests,
    // FINAL_DECISIONS §12 sentinel from generateBunnySignedUrl
    // (CENTER_FREE_WINDOW_BLOCKED_MESSAGE).
    'A Center Free 24-hour video window is already active for another video.':
        FailureCode.dailyVideoLimitReached,
    'Authentication is required.': FailureCode.wrongCredentials,
    'User identity mismatch.': FailureCode.unauthorizedDevice,
    'Only approved students may bind devices.':
        FailureCode.unauthorizedDevice,
  };

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
      'weak-password' => FailureCode.weakPassword,
      'email-already-in-use' => FailureCode.phoneAlreadyExists,
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

/// Connectivity-layer sentinel used by datasources when the device reports
/// no connectivity; converted to [FailureCode.noInternet] by [Failure.from].
class NetworkUnreachableException implements Exception {
  final String message;
  const NetworkUnreachableException([this.message = 'network unreachable']);

  @override
  String toString() => 'NetworkUnreachableException: $message';
}

class TimeoutException implements Exception {
  final String message;
  const TimeoutException([this.message = 'operation timed out']);

  @override
  String toString() => 'TimeoutException: $message';
}

/// Convenience for repository/data-layer authors: wrap any call so raw
/// exceptions never escape to providers as non-Failure objects.
extension FailureGuard<T> on Future<T> {
  Future<T> asFailureAware() =>
      catchError((Object e, StackTrace s) => throw Failure.from(e, s));
}
