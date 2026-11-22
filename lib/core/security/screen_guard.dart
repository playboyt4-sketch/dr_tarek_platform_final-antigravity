import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:screen_protector/screen_protector.dart';

/// Central screen protection service across Android and iOS.
///
/// Features:
/// 1. Android: Enforces FLAG_SECURE (black screenshots, black recordings).
/// 2. iOS: Enforces secure view layer via [ScreenProtector.preventScreenshotOn]
///    (black screenshots) and background data leakage protection with black color.
/// 3. iOS Screen Recording detection: [isRecording] updates live via
///    [ScreenProtector.addListener] and [ScreenProtector.isRecording].
/// 4. Web, Windows, Chrome, macOS, Linux: Safely no-op via platform guards.
class ScreenGuard {
  ScreenGuard._();

  static final ValueNotifier<bool> isRecording = ValueNotifier<bool>(false);
  static bool _initialized = false;

  /// Initializes screen protection and screen recording observers.
  /// Must be called during app boot after [WidgetsFlutterBinding.ensureInitialized].
  static Future<void> init() async {
    if (kIsWeb) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;
    if (_initialized) return;
    _initialized = true;

    try {
      // Android: sets FLAG_SECURE on Window.
      // iOS: activates secure window overlay for screenshots.
      await ScreenProtector.preventScreenshotOn();
    } catch (e) {
      debugPrint('[ScreenGuard] preventScreenshotOn error: $e');
    }

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
