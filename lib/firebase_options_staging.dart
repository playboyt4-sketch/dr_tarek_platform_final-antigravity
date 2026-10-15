// Staging Firebase configuration for TestFlight isolation.
//
// Values below were retrieved read-only via
// `firebase apps:sdkconfig` against project `dr-tarek-staging`
// (sender 13159003436) on 2026-10-14. Same shape as the generated
// `firebase_options.dart` (production: dr-tarek-platform, sender
// 606744934510). API keys here are public client keys, consistent with
// the existing convention of committing the production options file.
// Never place server secrets (BUNNY_*, Admin SDK JSON) in this file.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Staging [FirebaseOptions] for TestFlight builds (project dr-tarek-staging).
class StagingFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'StagingFirebaseOptions have not been configured for macos.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'StagingFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'StagingFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'StagingFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBEyvedh_9PkVsOCV-yXvQb6Fu-vbL6hN4',
    appId: '1:13159003436:web:ca447a3960b0eddf016889',
    messagingSenderId: '13159003436',
    projectId: 'dr-tarek-staging',
    authDomain: 'dr-tarek-staging.firebaseapp.com',
    storageBucket: 'dr-tarek-staging.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBr4mwmfw04dfT231RaOwj56J4osyVv4pA',
    appId: '1:13159003436:android:ce111f52a6ce2e42016889',
    messagingSenderId: '13159003436',
    projectId: 'dr-tarek-staging',
    storageBucket: 'dr-tarek-staging.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBGtsdTNQODlMorO8Ki68a2o29qZ25FiWw',
    appId: '1:13159003436:ios:f425a634a94b294e016889',
    messagingSenderId: '13159003436',
    projectId: 'dr-tarek-staging',
    storageBucket: 'dr-tarek-staging.firebasestorage.app',
    iosBundleId: 'com.drtarek.platform',
  );
}
