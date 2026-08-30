import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Bridges the push pipeline end-to-end: obtains the FCM token, keeps it
/// refreshed, registers it against the bound device via the existing
/// `onDeviceTokenRefresh` Cloud Function, creates the Android notification
/// channel, renders foreground messages as local notifications, and logs
/// background/terminated interactions.
///
/// Registration is skipped until the user is signed in AND a device id is
/// available (device binding writes it during session bootstrap).

const String _kChannelId = 'dr_tarek_general';
const String _kChannelName = 'إشعارات المنصة';

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

  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<User?>? _authStateSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;
  bool _channelReady = false;

  FcmPushService({
    required this.messaging,
    required this.functions,
    required this.storage,
    required this.auth,
    this.localNotifications,
  });

  static const _deviceIdKey = 'device_binding_device_id';

  /// Wires listeners; safe to call once at app startup.
  void start() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    _authStateSub = auth.authStateChanges().listen((user) {
      if (user != null) {
        _registerToken();
      } else {
        _tokenRefreshSub?.cancel();
        _tokenRefreshSub = null;
      }
    });

    _tokenRefreshSub ??= messaging.onTokenRefresh.listen((_) {
      if (auth.currentUser != null) _registerToken();
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
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _authStateSub?.cancel();
    await _foregroundSub?.cancel();
    await _openedAppSub?.cancel();
  }

  Future<void> _registerToken() async {
    try {
      // Ask once per install; Android 13+ shows the POST_NOTIFICATIONS dialog.
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus !=
              AuthorizationStatus.provisional) {
        return;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;

      final deviceId = await storage.read(key: _deviceIdKey);
      if (deviceId == null || deviceId.isEmpty) {
        // Device binding has not completed yet; onDeviceTokenRefresh will be
        // retried on the next token refresh / sign-in.
        return;
      }

      final callable = functions.httpsCallable('onDeviceTokenRefresh');
      await callable.call({
        'deviceId': deviceId,
        'fcmToken': token,
      });
    } catch (error, stackTrace) {
      // Push registration must never break the user session.
      if (kDebugMode) {
        developer.log(
          'FCM registration failed: $error',
          name: 'fcm',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
}
