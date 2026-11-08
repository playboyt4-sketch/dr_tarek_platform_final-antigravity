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
import 'config/environment.dart';
import 'core/errors/failure.dart';
import 'core/localization/locale_controller.dart';
import 'core/routing/app_router.dart';
import 'core/routing/notification_deep_link.dart';
import 'core/theme/theme_controller.dart';
import 'core/web/video_hls_backend_stub.dart'
    if (dart.library.js_interop) 'core/web/video_hls_backend_web.dart';
import 'features/authentication/data/remember_me_prefs.dart';
import 'features/notifications/data/services/fcm_push_service.dart';
import 'features/video_streaming/data/datasources/protected_offline_storage.dart';

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

/// Cold-start enforcement for "Remember me" OFF (primarily mobile: Firebase
/// Auth has no session-only mode there, so a restored session from a
/// previous login that opted out must be dropped). Runs once per process
/// start, before runApp — never during an active session, so the forced
/// password-change sign-out flow is unaffected. Best-effort, never blocks
/// startup.
Future<void> _dropUnrememberedSession() async {
  try {
    if (await loadRememberMeChoice()) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    await FirebaseAuth.instance.signOut();
  } catch (_) {
    // Never block startup on the session sweep.
  }
}

/// Opens the destination carried by a tapped push notification. Deferred to
/// the next frame because FCM can deliver the cold-start message before the
/// router has mounted its first frame.
void _openNotificationDestination(String? deepLink) {
  final String? path = notificationDeepLinkRoute(deepLink);
  if (path == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    appRouter.go(path);
  });
}

Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Web-only: install the HLS-capable video backend before any
      // VideoPlayerController is created. No-op on mobile/desktop.
      // Must run before first player creation (not only before first
      // play) so the plugin-owned <video> element is hls.js-backed.
      ensureWebHlsPlaybackBackend();

      try {
        // Explicit release environment: QA/TestFlight builds pass
        // --dart-define=ENV=staging, and the owner-approved production
        // TestFlight build passes ENV=prod. Release builds without ENV fail
        // closed here and surface the boot-error screen below.
        final env = Environment.resolve();
        await Firebase.initializeApp(
          options: Environment.optionsFor(env),
        );
      } catch (error) {
        // Never white-screen: show the boot failure explicitly so the
        // user (and support) sees the cause instead of a blank page.
        runApp(_BootErrorApp(message: 'تعذر تهيئة الاتصال بالخدمة: $error'));
        return;
      }

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
      //
      // Web/localhost development uses the official WebDebugProvider: the
      // FlutterFire web plugin sets self.FIREBASE_APPCHECK_DEBUG_TOKEN = true
      // before initializing App Check, so the Firebase JS SDK auto-generates
      // a debug token and prints it to the browser console. Register that
      // token once in Firebase Console → App Check → Manage debug tokens; it
      // is never committed to source. No web/index.html change is made on
      // purpose: a global flag there would ship into production builds and
      // downgrade production attestation to debug tokens. Production web
      // always uses ReCaptchaEnterpriseProvider and refuses to boot without
      // a site key (guard above).
      final WebProvider webAppCheckProvider = (kIsWeb && kDebugMode)
          ? WebDebugProvider()
          : ReCaptchaEnterpriseProvider(reCaptchaSiteKey);
      // Best-effort: server-side enforcement stays OFF, so an App Check
      // failure (blocked script, offline, unsupported browser) must never
      // white-screen the boot. The callable layer degrades gracefully.
      try {
        await FirebaseAppCheck.instance.activate(
          providerWeb: webAppCheckProvider,
          providerAndroid:
              kDebugMode ? AndroidDebugProvider() : AndroidPlayIntegrityProvider(),
          providerApple: kDebugMode
              ? AppleDebugProvider()
              : AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
      } catch (error) {
        debugPrint('AppCheck activation skipped: $error');
      }

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
      // alive for the process lifetime. Best-effort: must never block or
      // break boot (e.g. web without VAPID/permission).
      try {
        FcmPushService(
          messaging: FirebaseMessaging.instance,
          functions: FirebaseFunctions.instance,
          storage: const FlutterSecureStorage(),
          auth: FirebaseAuth.instance,
          onNotificationTap: _openNotificationDestination,
        ).start();
      } catch (error) {
        debugPrint('FCM start skipped: $error');
      }

      // --- Offline DRM hygiene ---
      unawaited(_purgeExpiredOfflineArtifacts());

      // --- Remember-me cold start: drop a restored session the user asked
      // not to keep. Awaited (fast, local-only) so the first frame never
      // flashes authenticated content for a dropped session.
      await _dropUnrememberedSession();

      // First-frame locale without flash: read persistence before runApp.
      // Falls back silently to platform default on any persistence error.
      Locale initialLocale;
      try {
        initialLocale = await loadPersistedLocale();
      } catch (_) {
        initialLocale = const Locale('ar');
      }

      // First-frame appearance without flash: the persisted mode is resolved
      // before runApp so the user never sees a frame in the wrong brightness.
      // Never throws; defaults to System.
      final initialThemeMode = await loadPersistedThemeMode();

      runApp(
        ProviderScope(
          overrides: [
            initialLocaleProvider.overrideWithValue(initialLocale),
            initialThemeModeProvider.overrideWithValue(initialThemeMode),
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

/// Fallback screen shown when boot itself fails (e.g. Firebase init).
/// Guarantees the user sees a message instead of a white screen.
class _BootErrorApp extends StatelessWidget {
  final String message;

  const _BootErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
