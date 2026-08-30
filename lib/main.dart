import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/errors/failure.dart';
import 'core/localization/locale_controller.dart';
import 'features/notifications/data/services/fcm_push_service.dart';
import 'features/video_streaming/data/datasources/protected_offline_storage.dart';
import 'firebase_options.dart';

/// Best-effort startup sweep: purges expired offline DRM artifacts (files +
/// keys) so revoked entitlements never survive an app restart.
Future<void> _purgeExpiredOfflineArtifacts() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await ProtectedOfflineStorageImpl(prefs: prefs)
        .purgeAllExpiredOfflineResources();
  } catch (_) {
    // Never block startup on the cleanup sweep.
  }
}

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      const reCaptchaSiteKey = String.fromEnvironment('RECAPTCHA_SITE_KEY', defaultValue: '');
      if (kIsWeb && !kDebugMode && reCaptchaSiteKey.isEmpty) {
        throw StateError('RECAPTCHA_SITE_KEY must be provided via --dart-define for production web builds.');
      }

      // --- App Check (client attestation) ---
      // Play Integrity on Android; App Attest with DeviceCheck fallback on
      // Apple platforms. Debug builds use the debug provider so local
      // development keeps working. NOTE: server-side enforcement stays OFF
      // until the app is registered in the Firebase console with the final
      // identifiers (owner action) — activating it earlier would break all
      // clients.
      await FirebaseAppCheck.instance.activate(
        providerWeb: ReCaptchaEnterpriseProvider(reCaptchaSiteKey),
        providerAndroid:
            kDebugMode ? AndroidDebugProvider() : AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? AppleDebugProvider()
            : AppleAppAttestWithDeviceCheckFallbackProvider(),
      );

      // --- Crash reporting (Crashlytics) ---
      // Route all uncaught framework + platform errors to Crashlytics.
      // Disable local collection in debug to keep prod data clean.
      if (!kIsWeb) {
        if (kDebugMode) {
          await FirebaseCrashlytics.instance
              .setCrashlyticsCollectionEnabled(false);
        }
        FlutterError.onError = FirebaseCrashlytics.instance
            .recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stackTrace) {
          final failure = Failure.from(error, stackTrace);
          FirebaseCrashlytics.instance.recordError(
            failure.cause ?? error,
            failure.stackTrace ?? stackTrace,
            reason: 'failure_code=${failure.code.name}',
            fatal: true,
          );
          return true;
        };
      } else {
        FlutterError.onError = (details) {
          debugPrint(details.exceptionAsString());
        };
        PlatformDispatcher.instance.onError = (error, stackTrace) {
          debugPrint(error.toString());
          return true;
        };
      }

      // --- Push notifications (FCM) ---
      // The service holds long-lived auth/token subscriptions, keeping it
      // alive for the process lifetime.
      FcmPushService(
        messaging: FirebaseMessaging.instance,
        functions: FirebaseFunctions.instance,
        storage: const FlutterSecureStorage(),
        auth: FirebaseAuth.instance,
      ).start();

      // --- Offline DRM hygiene ---
      unawaited(_purgeExpiredOfflineArtifacts());

      // First-frame locale without flash: read persistence before runApp.
      // Falls back silently to platform default on any persistence error.
      Locale initialLocale;
      try {
        initialLocale = await loadPersistedLocale();
      } catch (_) {
        initialLocale = const Locale('ar');
      }

      runApp(
        ProviderScope(
          overrides: [
            initialLocaleProvider.overrideWithValue(initialLocale),
          ],
          child: const DrTarekPlatformApp(),
        ),
      );
    },
    (error, stackTrace) {
      final failure = Failure.from(error, stackTrace);
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordError(
          failure.cause ?? error,
          failure.stackTrace ?? stackTrace,
          reason: 'failure_code=${failure.code.name}',
          fatal: true,
        );
      } else {
        debugPrint(error.toString());
      }
    },
  );
}
