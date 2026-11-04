import 'package:dr_tarek_platform/config/environment.dart';
import 'package:dr_tarek_platform/firebase_options.dart'
    show DefaultFirebaseOptions;
import 'package:dr_tarek_platform/firebase_options_staging.dart'
    show StagingFirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseEnvironment', () {
    test('accepts prod spellings', () {
      expect(parseEnvironment('prod'), ReleaseEnvironment.production);
      expect(parseEnvironment('production'), ReleaseEnvironment.production);
      expect(parseEnvironment('  PROD  '), ReleaseEnvironment.production);
    });

    test('accepts staging spellings', () {
      expect(parseEnvironment('staging'), ReleaseEnvironment.staging);
      expect(parseEnvironment('stage'), ReleaseEnvironment.staging);
      expect(parseEnvironment('Staging'), ReleaseEnvironment.staging);
    });

    test('rejects missing/invalid values (fail closed)', () {
      expect(() => parseEnvironment(''), throwsStateError);
      expect(() => parseEnvironment('dev'), throwsStateError);
      expect(() => parseEnvironment('testflight'), throwsStateError);
      expect(() => parseEnvironment('production2'), throwsStateError);
    });
  });

  group('Environment.optionsFor', () {
    // flutter test runs on the host OS (windows/linux here), for which
    // neither options file has a configuration — pin Android so the
    // project-mapping assertions exercise the selector, not the host.
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('production and staging resolve to different projects', () {
      final prod = Environment.optionsFor(ReleaseEnvironment.production);
      final staging = Environment.optionsFor(ReleaseEnvironment.staging);
      expect(prod.projectId, 'dr-tarek-platform');
      expect(staging.projectId, 'dr-tarek-staging');
      expect(prod.appId, isNot(staging.appId));
    });

    test('both targets keep the ratified iOS Bundle ID', () {
      expect(DefaultFirebaseOptions.ios.iosBundleId, 'com.drtarek.platform');
      expect(StagingFirebaseOptions.ios.iosBundleId, 'com.drtarek.platform');
    });

    test('iOS release target resolves to the production Firebase app', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final prod = Environment.optionsFor(ReleaseEnvironment.production);
        expect(prod.projectId, 'dr-tarek-platform');
        expect(prod.appId, '1:606744934510:ios:9718f3e90867d668c54e7f');
        expect(prod.iosBundleId, 'com.drtarek.platform');
        expect(prod.storageBucket, 'dr-tarek-platform.firebasestorage.app');

        final staging = Environment.optionsFor(ReleaseEnvironment.staging);
        expect(staging.projectId, 'dr-tarek-staging');
        expect(staging.appId, isNot(prod.appId));
      } finally {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
      }
    });
  });
}
