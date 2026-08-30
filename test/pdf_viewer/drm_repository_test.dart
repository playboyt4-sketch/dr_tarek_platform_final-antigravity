import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dr_tarek_platform/features/pdf_viewer/data/repositories/drm_repository_impl.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/datasources/protected_offline_storage.dart';

/// Deterministic 32-byte device secrets encoded canonically, mimicking what
/// the production FlutterSecureStorage loader returns.
final String _secretA = base64Encode(List<int>.filled(32, 0x0A));
final String _secretB = base64Encode(List<int>.filled(32, 0x0B));

/// In-memory fake of the protected key/expiry store so unit tests run
/// without platform channels.
class _FakeProtectedOfflineStorage implements ProtectedOfflineStorage {
  final Map<String, String> keys = {};
  final Map<String, DateTime> expiries = {};

  @override
  Future<void> saveEncryptedContentKey({
    required String resourceId,
    required String keyData,
    required DateTime expiresAt,
  }) async {
    keys[resourceId] = keyData;
    expiries[resourceId] = expiresAt;
  }

  @override
  Future<String?> getValidContentKey({required String resourceId}) async {
    final expiry = expiries[resourceId];
    if (expiry == null || DateTime.now().isAfter(expiry)) {
      await purgeOfflineResource(resourceId: resourceId);
      return null;
    }
    return keys[resourceId];
  }

  @override
  Future<void> purgeOfflineResource({required String resourceId}) async {
    keys.remove(resourceId);
    expiries.remove(resourceId);
  }

  @override
  Future<void> purgeAllExpiredOfflineResources() async {
    for (final id in List<String>.from(expiries.keys)) {
      final expiry = expiries[id]!;
      if (DateTime.now().isAfter(expiry)) {
        await purgeOfflineResource(resourceId: id);
      }
    }
  }
}

Future<(DrmRepositoryImpl, Directory, _FakeProtectedOfflineStorage)> _buildRepo(
  String masterSecret,
) async {
  final dir = await Directory.systemTemp.createTemp('drm_test_');
  final storage = _FakeProtectedOfflineStorage();
  final repo = DrmRepositoryImpl(
    protectedStorage: storage,
    directoryResolver: () async => dir,
    loadMasterSecret: () async => masterSecret,
  );
  return (repo, dir, storage);
}

void main() {
  test('1) encrypt/decrypt roundtrip restores plaintext, .drm on disk only',
      () async {
    final (repo, dir, _) = await _buildRepo(_secretA);
    const marker = 'TOP-SECRET-PLAINTEXT-CONTENT';
    final plaintext = Uint8List.fromList(marker.codeUnits);

    await repo.saveEncryptedFile(
      resourceId: 'res-1',
      plaintextBytes: plaintext,
      userId: 'user-1',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

    // No plaintext on disk; artifact uses the .drm extension.
    final drmFile = File('${dir.path}/res-1.drm');
    expect(await drmFile.exists(), isTrue);
    final rawOnDisk = await drmFile.readAsBytes();
    expect(String.fromCharCodes(rawOnDisk).contains(marker), isFalse);

    final decrypted = await repo.getDecryptedFile(
      resourceId: 'res-1',
      userId: 'user-1',
    );
    expect(decrypted, isNotNull);
    expect(String.fromCharCodes(decrypted!), marker);

    await dir.delete(recursive: true);
  });

  test('2) wrong device (rotated master secret) cannot decrypt and purges',
      () async {
    final (repoA, dir, storage) = await _buildRepo(_secretA);
    await repoA.saveEncryptedFile(
      resourceId: 'res-2',
      plaintextBytes: Uint8List.fromList('data'.codeUnits),
      userId: 'user-1',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

    // Simulate the same .drm file landing on a different device whose
    // master secret differs: derivation yields a different AES key.
    final repoB = DrmRepositoryImpl(
      protectedStorage: storage,
      directoryResolver: () async => dir,
      loadMasterSecret: () async => _secretB,
    );

    final result = await repoB.getDecryptedFile(
      resourceId: 'res-2',
      userId: 'user-1',
    );
    expect(result, isNull);
    // Unusable foreign-device artifact is wiped instead of lingering.
    expect(await File('${dir.path}/res-2.drm').exists(), isFalse);

    await dir.delete(recursive: true);
  });

  test('3) tampered file fails authentication and is purged', () async {
    final (repo, dir, _) = await _buildRepo(_secretA);
    await repo.saveEncryptedFile(
      resourceId: 'res-3',
      plaintextBytes: Uint8List.fromList('payload'.codeUnits),
      userId: 'user-1',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

    final file = File('${dir.path}/res-3.drm');
    final bytes = await file.readAsBytes();
    bytes[bytes.length - 1] ^= 0xFF; // flip MAC byte
    await file.writeAsBytes(bytes, flush: true);

    final result = await repo.getDecryptedFile(
      resourceId: 'res-3',
      userId: 'user-1',
    );
    expect(result, isNull);
    expect(await file.exists(), isFalse);

    await dir.delete(recursive: true);
  });

  test('4) expired subscription purges key + file immediately', () async {
    final (repo, dir, _) = await _buildRepo(_secretA);
    await repo.saveEncryptedFile(
      resourceId: 'res-4',
      plaintextBytes: Uint8List.fromList('soon-gone'.codeUnits),
      userId: 'user-1',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    final file = File('${dir.path}/res-4.drm');
    expect(await file.exists(), isTrue);

    final result = await repo.getDecryptedFile(
      resourceId: 'res-4',
      userId: 'user-1',
    );
    expect(result, isNull);
    expect(await file.exists(), isFalse);

    await dir.delete(recursive: true);
  });

  test('5) device unbind (secret rotation) invalidates prior downloads',
      () async {
    final (repoOld, dir, storage) = await _buildRepo(_secretA);
    await repoOld.saveEncryptedFile(
      resourceId: 'res-5',
      plaintextBytes: Uint8List.fromList('lecture-bytes'.codeUnits),
      userId: 'user-1',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    expect(await repoOld.hasEncryptedFile(resourceId: 'res-5'), isTrue);

    // Admin replaces the device -> fresh binding -> new master secret.
    final repoNewBinding = DrmRepositoryImpl(
      protectedStorage: storage,
      directoryResolver: () async => dir,
      loadMasterSecret: () async => _secretB,
    );

    expect(
      await repoNewBinding.hasEncryptedFile(resourceId: 'res-5'),
      isTrue,
    ); // metadata still present until first access
    final result = await repoNewBinding.getDecryptedFile(
      resourceId: 'res-5',
      userId: 'user-1',
    );
    expect(result, isNull); // content inaccessible under new binding
    expect(
      await repoNewBinding.hasEncryptedFile(resourceId: 'res-5'),
      isFalse,
    ); // artifact cleaned

    await dir.delete(recursive: true);
  });

  test('6) revoked access (key removal) blocks decryption and wipes file',
      () async {
    final (repo, dir, storage) = await _buildRepo(_secretA);
    await repo.saveEncryptedFile(
      resourceId: 'res-6',
      plaintextBytes: Uint8List.fromList('revoked-content'.codeUnits),
      userId: 'user-1',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );

    // Server-side revocation propagates locally as key removal
    // (revalidateOfflineAccess path).
    await storage.purgeOfflineResource(resourceId: 'res-6');

    final file = File('${dir.path}/res-6.drm');
    final result = await repo.getDecryptedFile(
      resourceId: 'res-6',
      userId: 'user-1',
    );
    expect(result, isNull);
    expect(await file.exists(), isFalse);

    await dir.delete(recursive: true);
  });
}
