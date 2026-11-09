import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/device/device_identity_store.dart';

/// Bridges the push pipeline end-to-end: obtains the FCM token, keeps it
/// refreshed, registers it against the bound device via the existing
/// `onDeviceTokenRefresh` Cloud Function, creates the Android notification
/// channel, renders foreground messages as local notifications, and logs
/// background/terminated interactions.
///
/// Registration is skipped until the user is signed in; the device id is
/// resolved through [DeviceIdentityStore], so FCM and device binding always
/// observe the same install id.
///
/// iOS hardening:
/// * waits for the APNs token before asking FCM for a token
///   (`apns-token-not-set` is the failure mode when it is missing),
/// * retries transient token/callable failures with bounded backoff,
/// * reports non-fatal failures to Crashlytics in release builds without
///   ever including the token value.

const String _kChannelId = 'dr_tarek_general';
const String _kChannelName = 'إشعارات المنصة';

/// Polls [read] until it returns a non-null value or [attempts] runs out.
@visibleForTesting
Future<T?> pollUntilReady<T>(
  Future<T?> Function() read, {
  required int attempts,
  required Duration interval,
}) async {
  assert(attempts > 0, 'attempts must be positive');
  for (var attempt = 1; attempt <= attempts; attempt++) {
    final value = await read();
    if (value != null) return value;
    if (attempt < attempts) {
      await Future<void>.delayed(interval);
    }
  }
  return null;
}

/// Retries [action] with linear backoff when [retryIf] matches.
///
/// When [retryIf] is omitted every failure is retried. Non-matching failures
/// are rethrown immediately, and the last failure is rethrown after the
/// attempt budget is exhausted.
@visibleForTesting
Future<T> retryWithBackoff<T>(
  Future<T> Function() action, {
  required int attempts,
  required Duration baseDelay,
  bool Function(Object error)? retryIf,
}) async {
  assert(attempts > 0, 'attempts must be positive');
  Object? lastError;
  StackTrace? lastStackTrace;

  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await action();
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
      if (retryIf != null && !retryIf(error)) rethrow;
      if (attempt < attempts) {
        await Future<void>.delayed(baseDelay * attempt);
      }
    }
  }

  Error.throwWithStackTrace(lastError!, lastStackTrace!);
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background isolates cannot touch Riverpod; keep this side-effect free.
  developer.log(
    'FCM background message: ${message.messageId}',
    name: 'fcm',
  );
}

class FcmPushService {
  final FirebaseMessaging messaging;
  final FirebaseFunctions functions;
  final FlutterSecureStorage storage;
  final FirebaseAuth auth;
  final FlutterLocalNotificationsPlugin? localNotifications;

  /// Invoked with the `deep_link` payload when the user taps a push
  /// notification (foreground local notification, background, or terminated).
  final void Function(String? deepLink)? onNotificationTap;

  /// Bounded readiness/retry policy. Tests override the delays to zero.
  final Duration apnsTokenPollInterval;
  final int apnsTokenPollAttempts;
  final Duration tokenRetryBaseDelay;
  final int tokenRetryAttempts;
  final Duration callableRetryBaseDelay;
  final int callableRetryAttempts;

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<User?>? _authStateSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  bool _channelReady = false;

  /// Coalesces concurrent registration attempts (auth state + token refresh).
  Future<void>? _registrationInFlight;

  /// Diagnostics: report each stage at most once per app process so a denied
  /// permission or a missing entitlement does not flood Crashlytics.
  final Set<String> _reportedRegistrationStages = <String>{};

  AuthorizationStatus? _lastAuthorizationStatus;
  bool _apnsTokenReady = false;
  bool _deviceIdResolved = false;

  FcmPushService({
    required this.messaging,
    required this.functions,
    required this.storage,
    required this.auth,
    this.localNotifications,
    this.onNotificationTap,
    this.apnsTokenPollInterval = const Duration(milliseconds: 500),
    this.apnsTokenPollAttempts = 20,
    this.tokenRetryBaseDelay = const Duration(seconds: 1),
    this.tokenRetryAttempts = 3,
    // Wider than the token budget: on a first login `onLoginAttempt` may still
    // be creating the device row, and the callable rejects with
    // `permission-denied` until it lands. 1.5s + 3s + 4.5s spans bootstrap.
    this.callableRetryBaseDelay = const Duration(milliseconds: 1500),
    this.callableRetryAttempts = 4,
  });

  /// Wires listeners; safe to call once at app startup.
  void start() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    _authStateSub = auth.authStateChanges().listen((user) {
      if (user != null) {
        unawaited(_registerToken());
      } else {
        _tokenRefreshSub?.cancel();
        _tokenRefreshSub = null;
      }
    });

    // `authStateChanges` emits the restored user on listen, but make the
    // restart path explicit too. Registration is single-flight, so this
    // cannot double-call the backend.
    if (auth.currentUser != null) {
      unawaited(_registerToken());
    }

    _tokenRefreshSub ??= messaging.onTokenRefresh.listen((_) {
      if (auth.currentUser != null) unawaited(_registerToken());
    });

    // Foreground: render incoming pushes as local notifications through the
    // platform channel (FCM system tray delivery only covers background).
    unawaited(_initNotificationChannel());
    _foregroundSub = FirebaseMessaging.onMessage.listen(_showForeground);
    // Terminated-state cold start via notification tap.
    messaging.getInitialMessage().then((message) {
      if (message != null) _logTap(message, source: 'terminated');
    });
    // Background -> tap opens the app.
    _openedAppSub = FirebaseMessaging.onMessageOpenedApp
        .listen((m) => _logTap(m, source: 'background'));
    messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
  }

  Future<void> _initNotificationChannel() async {
    final plugin = localNotifications ?? FlutterLocalNotificationsPlugin();
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final android = plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (android != null) {
          await android.createNotificationChannel(
            const AndroidNotificationChannel(
              _kChannelId,
              _kChannelName,
              importance: Importance.high,
            ),
          );
        }
      }
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Foreground pushes are rendered locally; route them exactly like a
          // system-tray tap so the payload's destination is honored.
          onNotificationTap?.call(response.payload);
        },
      );
      _channelReady = true;
    } catch (error) {
      // Notifications must never break bootstrap (e.g. unit tests, web).
      if (kDebugMode) {
        developer.log('FCM channel init failed: $error', name: 'fcm');
      }
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    developer.log('FCM foreground message: ${message.messageId}', name: 'fcm');
    if (!_channelReady) return;
    final notification = message.notification;
    if (notification == null) return;
    try {
      await (localNotifications ?? FlutterLocalNotificationsPlugin()).show(
        message.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannelId,
            _kChannelName,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: message.data['deep_link'] as String?,
      );
    } catch (error) {
      if (kDebugMode) {
        developer.log('Foreground render failed: $error', name: 'fcm');
      }
    }
  }

  void _logTap(RemoteMessage message, {required String source}) {
    developer.log(
      'FCM notification tapped ($source): ${message.messageId} '
      'deep_link=${message.data['deep_link']}',
      name: 'fcm',
    );
    onNotificationTap?.call(message.data['deep_link'] as String?);
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _authStateSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedAppSub?.cancel();
  }

  /// Coalesces concurrent auth/token-refresh triggers into one registration.
  Future<void> _registerToken() {
    return _registrationInFlight ??= _runRegistration().whenComplete(() {
      _registrationInFlight = null;
    });
  }

  Future<void> _runRegistration() async {
    var stage = 'auth';
    try {
      if (auth.currentUser == null) return;

      // Ask once per install; Android 13+ shows the POST_NOTIFICATIONS dialog.
      stage = 'permission';
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _lastAuthorizationStatus = settings.authorizationStatus;
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        _reportRegistrationFailure(
          stage: 'permission_denied',
          error: StateError('Notification permission not granted'),
          stackTrace: StackTrace.current,
        );
        return;
      }

      // iOS requires an APNs token before FCM can mint a registration token.
      // The token arrives asynchronously after launch, so wait briefly instead
      // of failing the whole registration on the first attempt.
      if (_requiresApnsToken) {
        stage = 'apns_token';
        final apnsToken = await pollUntilReady<String>(
          () async {
            final value = await messaging.getAPNSToken();
            return (value == null || value.isEmpty) ? null : value;
          },
          attempts: apnsTokenPollAttempts,
          interval: apnsTokenPollInterval,
        );
        _apnsTokenReady = apnsToken != null;
        if (apnsToken == null) {
          _reportRegistrationFailure(
            stage: 'apns_token_missing',
            error: StateError('APNs token was not available after polling'),
            stackTrace: StackTrace.current,
          );
          return;
        }
      }

      stage = 'fcm_token';
      final token = await retryWithBackoff<String>(
        () async {
          final value = await messaging.getToken();
          if (value == null || value.isEmpty) {
            throw StateError('FCM token is empty');
          }
          return value;
        },
        attempts: tokenRetryAttempts,
        baseDelay: tokenRetryBaseDelay,
        retryIf: _isRetryableTokenError,
      );

      stage = 'device_id';
      final deviceId = await DeviceIdentityStore(storage: storage).getOrCreate();
      _deviceIdResolved = true;

      stage = 'callable';
      final callable = functions.httpsCallable('onDeviceTokenRefresh');
      await retryWithBackoff<void>(
        () async {
          await callable.call(<String, dynamic>{
            'deviceId': deviceId,
            'fcmToken': token,
          });
        },
        attempts: callableRetryAttempts,
        baseDelay: callableRetryBaseDelay,
        retryIf: _isRetryableCallableError,
      );
    } catch (error, stackTrace) {
      _reportRegistrationFailure(
        stage: stage,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool get _requiresApnsToken =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool _isRetryableTokenError(Object error) {
    if (error is FirebaseException) {
      return error.code == 'apns-token-not-set' ||
          error.code == 'unavailable' ||
          error.code == 'internal';
    }
    // An empty token is thrown as a StateError above; it is transient.
    return error is StateError;
  }

  bool _isRetryableCallableError(Object error) {
    if (error is! FirebaseFunctionsException) return false;
    return error.code == 'permission-denied' ||
        error.code == 'not-found' ||
        error.code == 'unavailable' ||
        error.code == 'internal';
  }

  /// Records a sanitized non-fatal failure: stage, permission state, APNs
  /// readiness, device-id presence, and platform. The FCM token is never
  /// included. Each stage is reported at most once per app process.
  void _reportRegistrationFailure({
    required String stage,
    required Object error,
    StackTrace? stackTrace,
  }) {
    final reason = 'fcm_registration_failed stage=$stage '
        'permission=${_lastAuthorizationStatus?.name ?? 'unknown'} '
        'apns_ready=$_apnsTokenReady '
        'device_id_resolved=$_deviceIdResolved '
        'platform=${kIsWeb ? 'web' : defaultTargetPlatform.name}';

    if (kDebugMode) {
      developer.log(
        reason,
        name: 'fcm',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (!_reportedRegistrationStages.add(stage)) return;
    unawaited(_recordNonFatal(error, stackTrace ?? StackTrace.current, reason));
  }

  Future<void> _recordNonFatal(
    Object error,
    StackTrace stackTrace,
    String reason,
  ) async {
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        reason: reason,
        fatal: false,
      );
    } catch (_) {
      // Diagnostics must never break the session (web/unsupported/test).
    }
  }
}
