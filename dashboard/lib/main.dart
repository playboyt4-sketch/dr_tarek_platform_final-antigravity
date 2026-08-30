import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/dashboard_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyCCZFmVdGUd3n7hRX8vWpvWlp_t4TcUNj0',
      appId: '1:606744934510:web:b809f2ed62c9c9ffc54e7f',
      messagingSenderId: '606744934510',
      projectId: 'dr-tarek-platform',
      authDomain: 'dr-tarek-platform.firebaseapp.com',
      storageBucket: 'dr-tarek-platform.firebasestorage.app',
    ),
  );

  // --- App Check (Dashboard Client Attestation) ---
  // Uses placeholder Recaptcha Site Key for Web since it's missing from repo.
  await FirebaseAppCheck.instance.activate(
    // TODO: Replace with actual reCAPTCHA Enterprise site key when available in environment
    providerWeb: ReCaptchaEnterpriseProvider('BLOCKED_MISSING_KEY'),
    providerAndroid: kDebugMode ? AndroidDebugProvider() : AndroidPlayIntegrityProvider(),
    // iOS is explicitly blocked pending provider decision/documentation
    // providerApple: kDebugMode ? AppleDebugProvider() : AppleAppAttestWithDeviceCheckFallbackProvider(),
  );

  runApp(const ProviderScope(child: DashboardApp()));
}
