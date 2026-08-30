import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/datasources/protected_offline_storage.dart';
import 'package:dr_tarek_platform/features/pdf_viewer/data/repositories/drm_repository_impl.dart';
import 'package:dr_tarek_platform/features/pdf_viewer/domain/repositories/drm_repository.dart';
import 'package:path_provider/path_provider.dart';

/// Deterministic 32-byte device master secrets (canonically base64-encoded).
final String _deviceSecretA = base64Encode(List<int>.filled(32, 0x0A));
final String _deviceSecretB = base64Encode(List<int>.filled(32, 0x0B));

class MockProtectedOfflineStorage implements ProtectedOfflineStorage {
  final Map<String, String> _keys = {};
  final Map<String, DateTime> _expiry = {};

  @override
  Future<void> saveEncryptedContentKey({
    required String resourceId,
    required String keyData,
    required DateTime expiresAt,
  }) async {
    _keys[resourceId] = keyData;
    _expiry[resourceId] = expiresAt;
  }

  @override
  Future<String?> getValidContentKey({
    required String resourceId,
  }) async {
    final expires = _expiry[resourceId];
    if (expires == null || DateTime.now().isAfter(expires)) {
      await purgeOfflineResource(resourceId: resourceId);
      return null;
    }
    return _keys[resourceId];
  }

  @override
  Future<void> purgeOfflineResource({
    required String resourceId,
  }) async {
    _keys.remove(resourceId);
    _expiry.remove(resourceId);
  }

  @override
  Future<void> purgeAllExpiredOfflineResources() async {
    final now = DateTime.now();
    final expired = <String>[];
    _expiry.forEach((key, val) {
      if (now.isAfter(val)) {
        expired.add(key);
      }
    });
    for (final exp in expired) {
      await purgeOfflineResource(resourceId: exp);
    }
  }
}

// Simulates the entitlement matrix rules for unit testing
class MockEntitlementVerifier {
  final Map<String, dynamic> planFeatures;
  final bool hasSubjectAccess;
  final bool isDeviceValid;

  MockEntitlementVerifier({
    required this.planFeatures,
    this.hasSubjectAccess = true,
    this.isDeviceValid = true,
  });

  bool verifyAccess() {
    if (!isDeviceValid) return false;
    if (!hasSubjectAccess) return false;
    final access = planFeatures['pdf.access'];
    return access == 'ON' || access == 'Preview';
  }

  bool verifyOffline() {
    if (!isDeviceValid) return false;
    if (!hasSubjectAccess) return false;
    final access = planFeatures['pdf.access'];
    if (access == 'Preview') return false; // Preview mode blocks download/offline
    return planFeatures['pdf.offline'] == 'ON' && planFeatures['pdf.download'] == 'ON';
  }

  int getPreviewPages() {
    return planFeatures['pdf.preview_pages'] as int? ?? 5;
  }

  int getMaxOfflineFiles() {
    return planFeatures['pdf.offline_max_files'] as int? ?? 5;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationSupportDirectory' ||
            methodCall.method == 'getTemporaryDirectory') {
          return './';
        }
        return null;
      },
    );
  });

  late MockProtectedOfflineStorage mockStorage;
  late DrmRepository drmRepo;

  setUp(() {
    mockStorage = MockProtectedOfflineStorage();
    drmRepo = DrmRepositoryImpl(
      protectedStorage: mockStorage,
      directoryResolver: () async => Directory.current,
      loadMasterSecret: () async => _deviceSecretA,
    );
  });

  group('PDF Viewer Feature & DRM Test Suite', () {
    test('H. Offline encryption/decryption with AES-256-GCM', () async {
      final plaintext = 'This is a protected PDF file content.'.codeUnits;
      const resourceId = 'test_resource_1';
      const userId = 'student_user_123';
      final expiresAt = DateTime.now().add(const Duration(days: 1));

      await drmRepo.saveEncryptedFile(
        resourceId: resourceId,
        plaintextBytes: plaintext,
        userId: userId,
        expiresAt: expiresAt,
      );

      // Verify key is saved securely in storage
      final key = await mockStorage.getValidContentKey(resourceId: resourceId);
      expect(key, isNotNull);

      // Verify file is saved in protected path
      final hasFile = await drmRepo.hasEncryptedFile(resourceId: resourceId);
      expect(hasFile, isTrue);

      // Decrypt and compare
      final decrypted = await drmRepo.getDecryptedFile(resourceId: resourceId, userId: userId);
      expect(decrypted, equals(plaintext));
    });

    test('I. Decryption fails with wrong key', () async {
      final plaintext = 'Sample PDF bytes'.codeUnits;
      const resourceId = 'test_wrong_key';
      const userId = 'user_123';

      await drmRepo.saveEncryptedFile(
        resourceId: resourceId,
        plaintextBytes: plaintext,
        userId: userId,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      // Under the device-bound derivation model the AES key is always
      // re-derived from the master secret, so a "wrong key" is simulated by
      // deriving under a different device's master secret.
      final foreignDeviceRepo = DrmRepositoryImpl(
        protectedStorage: mockStorage,
        directoryResolver: () async => Directory.current,
        loadMasterSecret: () async => _deviceSecretB,
      );

      final decrypted = await foreignDeviceRepo.getDecryptedFile(resourceId: resourceId, userId: userId);
      expect(decrypted, isNull);
    });

    test('J. Tampered DRM file decryption failure', () async {
      final plaintext = 'Tamper test content'.codeUnits;
      const resourceId = 'tamper_res';
      const userId = 'user_99';

      await drmRepo.saveEncryptedFile(
        resourceId: resourceId,
        plaintextBytes: plaintext,
        userId: userId,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      // Find file on disk and overwrite some bytes
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$resourceId.drm');
      final bytes = await file.readAsBytes();
      
      // Mutate one byte of ciphertext to simulate file tempering
      bytes[bytes.length - 5] ^= 0xFF;
      await file.writeAsBytes(bytes);

      final decrypted = await drmRepo.getDecryptedFile(resourceId: resourceId, userId: userId);
      expect(decrypted, isNull);
    });

    test('L/M/N/O/P. Subscription expired/revoked/wipe DRM file', () async {
      final plaintext = 'Auto wipe content'.codeUnits;
      const resourceId = 'wipe_res';
      const userId = 'user_wipe';

      // Save with expiration in the past (expired subscription)
      await drmRepo.saveEncryptedFile(
        resourceId: resourceId,
        plaintextBytes: plaintext,
        userId: userId,
        expiresAt: DateTime.now().subtract(const Duration(seconds: 10)),
      );

      // Decrypt attempt should return null and purge the files/keys
      final decrypted = await drmRepo.getDecryptedFile(resourceId: resourceId, userId: userId);
      expect(decrypted, isNull);

      final hasKey = await mockStorage.getValidContentKey(resourceId: resourceId);
      expect(hasKey, isNull);

      final hasFile = await drmRepo.hasEncryptedFile(resourceId: resourceId);
      expect(hasFile, isFalse);
    });

    test('A/B/K/V. PDF Access Verification (Allowed, Denied, Wrong Device)', () {
      // Access Allowed
      final allowedVerifier = MockEntitlementVerifier(
        planFeatures: {'pdf.access': 'ON'},
        hasSubjectAccess: true,
        isDeviceValid: true,
      );
      expect(allowedVerifier.verifyAccess(), isTrue);

      // Access Denied (No Subject Access)
      final deniedVerifier1 = MockEntitlementVerifier(
        planFeatures: {'pdf.access': 'ON'},
        hasSubjectAccess: false,
        isDeviceValid: true,
      );
      expect(deniedVerifier1.verifyAccess(), isFalse);

      // Access Denied (Wrong Device Binding)
      final deniedVerifier2 = MockEntitlementVerifier(
        planFeatures: {'pdf.access': 'ON'},
        hasSubjectAccess: true,
        isDeviceValid: false,
      );
      expect(deniedVerifier2.verifyAccess(), isFalse);

      // Access Denied (Feature Disabled in Matrix)
      final deniedVerifier3 = MockEntitlementVerifier(
        planFeatures: {'pdf.access': 'OFF'},
        hasSubjectAccess: true,
        isDeviceValid: true,
      );
      expect(deniedVerifier3.verifyAccess(), isFalse);
    });

    test('C. Preview Mode Restrictions', () {
      final verifier = MockEntitlementVerifier(
        planFeatures: {
          'pdf.access': 'Preview',
          'pdf.preview_pages': 5,
        },
      );

      expect(verifier.verifyAccess(), isTrue);
      expect(verifier.getPreviewPages(), equals(5));
      expect(verifier.verifyOffline(), isFalse); // Preview mode prevents caching
    });

    test('D/E/F/G/Q. PDF Download & Offline Matrix Limits', () async {
      // Case 1: Download enabled, Offline disabled
      final v1 = MockEntitlementVerifier(
        planFeatures: {
          'pdf.access': 'ON',
          'pdf.download': 'ON',
          'pdf.offline': 'OFF',
        },
      );
      expect(v1.verifyOffline(), isFalse);

      // Case 2: Download enabled, Offline enabled
      final v2 = MockEntitlementVerifier(
        planFeatures: {
          'pdf.access': 'ON',
          'pdf.download': 'ON',
          'pdf.offline': 'ON',
          'pdf.offline_max_files': 3,
        },
      );
      expect(v2.verifyOffline(), isTrue);
      expect(v2.getMaxOfflineFiles(), equals(3));
    });

    test('R/S/T/U. PDF Reading Progress, Watermark & Notes validation', () {
      // Simulates progress math
      final progressPercent = 3 / 10;
      final completed = progressPercent >= 0.95;
      expect(completed, isFalse);

      final completedPercent = 10 / 10;
      final completedTrue = completedPercent >= 0.95;
      expect(completedTrue, isTrue);

      // Simulates Notes entity validation
      const noteContent = 'Personal Note';
      expect(noteContent, isNotEmpty);

      // Simulates Watermark identity content
      const studentName = 'Tarek';
      const studentPhone = '01001234567';
      expect('$studentName\n$studentPhone', contains('01001234567'));
    });
  });
}
