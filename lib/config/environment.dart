import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kDebugMode;

import '../firebase_options.dart' show DefaultFirebaseOptions;
import '../firebase_options_staging.dart' show StagingFirebaseOptions;

/// Release backend environment selector.
///
/// TestFlight builds MUST pass `--dart-define=ENV=staging` so they can never
/// touch production (`dr-tarek-platform`). Selection is explicit and fails
/// closed: an unknown value always throws, and a missing value throws in
/// release/profile builds (fail-closed boot error). Debug builds without an
/// explicit value keep the historical developer workflow (production
/// emulators/local run) — release builds never silently default.
enum ReleaseEnvironment { production, staging }

/// Pure parser — unit-tested, no platform dependencies.
ReleaseEnvironment parseEnvironment(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'prod':
    case 'production':
      return ReleaseEnvironment.production;
    case 'stage':
    case 'staging':
      return ReleaseEnvironment.staging;
    default:
      throw StateError(
        'Invalid release environment "$raw". '
        'Pass --dart-define=ENV=staging (TestFlight) or --dart-define=ENV=prod.',
      );
  }
}

class Environment {
  static const String _defineName = 'ENV';
  static const String _raw = String.fromEnvironment(_defineName);

  /// Resolves the environment for this build. Throws in release when unset.
  static ReleaseEnvironment resolve() {
    if (_raw.isEmpty) {
      if (kDebugMode) return ReleaseEnvironment.production;
      throw StateError(
        'Missing --dart-define=$_defineName. Release builds must pass '
        'ENV=staging (TestFlight) or ENV=prod explicitly; refusing to guess.',
      );
    }
    return parseEnvironment(_raw);
  }

  /// Firebase options for an explicitly resolved environment.
  static FirebaseOptions optionsFor(ReleaseEnvironment env) {
    switch (env) {
      case ReleaseEnvironment.production:
        return DefaultFirebaseOptions.currentPlatform;
      case ReleaseEnvironment.staging:
        return StagingFirebaseOptions.currentPlatform;
    }
  }
}
