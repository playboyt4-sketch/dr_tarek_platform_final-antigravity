import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_protector/screen_protector.dart';

/// Central screen protection service across Android and iOS.
///
/// Features:
/// 1. Android: Enforces FLAG_SECURE (black screenshots, black recordings).
/// 2. iOS: Enforces secure view layer via [ScreenProtector.preventScreenshotOn]
///    (black screenshots) and background data leakage protection with black color.
/// 3. iOS Screen Recording detection: [isRecording] updates live via
///    [ScreenProtector.addListener], MethodChannel notifications, and [ScreenProtector.isRecording].
/// 4. Web, Windows, Chrome, macOS, Linux: Safely no-op via platform guards.
class ScreenGuard {
  ScreenGuard._();

  static const MethodChannel _channel =
      MethodChannel('com.drtarek.platform/screen_guard');

  static final ValueNotifier<bool> isRecording = ValueNotifier<bool>(false);
  static bool _initialized = false;
  static bool _lifecycleObserverRegistered = false;

  /// Initializes screen protection and screen recording observers.
  /// Must be called during app boot after [WidgetsFlutterBinding.ensureInitialized].
  /// Never throws unhandled exceptions.
  static Future<void> init() async {
    try {
      if (kIsWeb) return;
      if (!Platform.isIOS && !Platform.isAndroid) return;
      if (_initialized) return;
      _initialized = true;

      // Listen to native MethodChannel events for immediate recording detection
      _channel.setMethodCallHandler((call) async {
        try {
          final dynamic arg = call.arguments;
          if (arg is bool) {
            isRecording.value = arg;
          } else if (call.method == 'onRecordingChanged' ||
              call.method == 'screenCaptureChanged') {
            isRecording.value = arg == true;
          }
        } catch (e) {
          debugPrint('[ScreenGuard] methodCallHandler error: $e');
        }
      });

      // Safely schedule screenshot prevention after the first frame renders
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          // Android: sets FLAG_SECURE on Window.
          // iOS: activates secure window overlay for screenshots.
          await ScreenProtector.preventScreenshotOn();
        } catch (e) {
          debugPrint('[ScreenGuard] preventScreenshotOn error: $e');
        }
      });

      if (Platform.isIOS) {
        try {
          // App switcher / multitasking preview concealment.
          await ScreenProtector.protectDataLeakageWithColor(Colors.black);
        } catch (e) {
          debugPrint('[ScreenGuard] protectDataLeakageWithColor error: $e');
        }

        try {
          // Query initial screen recording / AirPlay mirroring state.
          final bool initialCaptured = await ScreenProtector.isRecording();
          isRecording.value = initialCaptured;
        } catch (e) {
          debugPrint('[ScreenGuard] isRecording query error: $e');
        }

        try {
          // Subscribe to live screen recording state transitions.
          ScreenProtector.addListener(
            null, // Screenshot callback not needed: OS layer blanks it out.
            (bool isCaptured) {
              isRecording.value = isCaptured;
            },
          );
        } catch (e) {
          debugPrint('[ScreenGuard] addListener error: $e');
        }
      }
    } catch (e) {
      debugPrint('[ScreenGuard] init error: $e');
    }
  }

  /// Re-enforces screenshot prevention and re-evaluates screen recording state
  /// after the first frame completes. Also registers a lifecycle observer
  /// to re-apply whenever the app returns from background (resumed).
  static void reapplyAfterFirstFrame() {
    if (kIsWeb) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _reapplyProtection();
    });

    _registerLifecycleObserver();
  }

  static void _registerLifecycleObserver() {
    if (_lifecycleObserverRegistered) return;
    _lifecycleObserverRegistered = true;
    WidgetsBinding.instance.addObserver(_ScreenGuardLifecycleObserver());
  }

  static Future<void> _reapplyProtection() async {
    try {
      await ScreenProtector.preventScreenshotOn();
    } catch (e) {
      debugPrint('[ScreenGuard] reapply preventScreenshotOn error: $e');
    }

    if (Platform.isIOS) {
      try {
        final bool captured = await ScreenProtector.isRecording();
        isRecording.value = captured;
      } catch (e) {
        debugPrint('[ScreenGuard] reapply isRecording error: $e');
      }
    }
  }

  /// Cleans up listeners if needed.
  static void dispose() {
    if (kIsWeb) return;
    if (!Platform.isIOS) return;
    try {
      ScreenProtector.removeListener();
    } catch (_) {}
  }
}

class _ScreenGuardLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ScreenGuard._reapplyProtection();
    }
  }
}
