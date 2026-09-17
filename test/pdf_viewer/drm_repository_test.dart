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

  String _scoped(String subjectId, String resourceId) => '${subjectId}_$resourceId';

  @override
  Future<void> saveEncryptedContentKey({
    required String subjectId,
    required String resourceId,
    required String keyData,
    required DateTime expiresAt,
  }) async {
    final id = _scoped(subjectId, resourceId);
    keys[id] = keyData;
    expiries[id] = expiresAt;
  }

  @override
  Future<String?> getValidContentKey({
    required String subjectId,
    required String resourceId,
  }) async {
    final id = _scoped(subjectId, resourceId);
    final expiry = expiries[id];
    if (expiry == null || DateTime.now().isAfter(expiry)) {
      await purgeOfflineResource(subjectId: subjectId, resourceId: resourceId);
      return null;
    }
    return keys[id];
  }

  @override
  Future<void> purgeOfflineResource({
    required String subjectId,
    required String resourceId,
  }) async {
    final id = _scoped(subjectId, resourceId);
    keys.remove(id);
    expiries.remove(id);
  }

  @override
  Future<void> purgeAllExpiredOfflineResources() async {
    for (final id in List<String>.from(expiries.keys)) {
      final expiry = expiries[id]!;
      if (DateTime.now().isAfter(expiry)) {
        keys.remove(id);
        expiries.remove(id);
      }
    }
  }

  @override
  Future<void> purgeSubjectResources({required String subjectId}) async {
    for (final id in List<String>.from(keys.keys)) {
      if (id.startsWith('${subjectId}_')) {
        keys.remove(id);
        expiries.remove(id);
      }
    }
  }

  @override
  Future<void> purgeAllSubjectResources() async {
    keys.clear();
    expiries.clear();
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
      subjectId: 'sub-1',
      resourceId: 'res-1',
      plaintextBytes: plaintext,
      userId: 'user-1',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

    // No plaintext on disk; artifact lives in the Subject partition.
    final drmFile = File('${dir.path}/sub-1/res-1.drm');
    expect(await drmFile.exists(), isTrue);
    final rawOnDisk = await drmFile.readAsBytes();
    expect(String.fromCharCodes(rawOnDisk).contains(marker), isFalse);

    final decrypted = await repo.getDecryptedFile(
      subjectId: 'sub-1',
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
      subjectId: 'sub-1',
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
      subjectId: 'sub-1',
      resourceId: 'res-2',
      userId: 'user-1',
    );
    expect(result, isNull);
    // Unusable foreign-device artifact is wiped instead of lingering.
    expect(await File('${dir.path}/sub-1/res-2.drm').exists(), isFalse);

    await dir.delete(recursive: true);
  });

  test('3) tampered file fails authentication and is purged', () async {
    final (repo, dir, _) = await _buildRepo(_secretA);
    await repo.saveEncryptedFile(
      subjectId: 'sub-1',
      resourceId: 'res-3',
      plaintextBytes: Uint8List.fromList('payload'.codeUnits),
      userId: 'user-1',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

    final file = File('${dir.path}/sub-1/res-3.drm');
    final bytes = await file.readAsBytes();
    bytes[bytes.length - 1] ^= 0xFF; // flip MAC byte
    await file.writeAsBytes(bytes, flush: true);

    final result = await repo.getDecryptedFile(
      subjectId: 'sub-1',
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
      subjectId: 'sub-1',
      resourceId: 'res-4',
      plaintextBytes: Uint8List.fromList('soon-gone'.codeUnits),
      userId: 'user-1',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );

    final file = File('${dir.path}/sub-1/res-4.drm');
    expect(await file.exists(), isTrue);

    final result = await repo.getDecryptedFile(
      subjectId: 'sub-1',
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
      subjectId: 'sub-1',
      resourceId: 'res-5',
      plaintextBytes: Uint8List.fromList('lecture-bytes'.codeUnits),
      userId: 'user-1',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    expect(
        await repoOld.hasEncryptedFile(subjectId: 'sub-1', resourceId: 'res-5'),
        isTrue);

    // Admin replaces the device -> fresh binding -> new master secret.
    final repoNewBinding = DrmRepositoryImpl(
      protectedStorage: storage,
      directoryResolver: () async => dir,
      loadMasterSecret: () async => _secretB,
    );

    expect(
      await repoNewBinding.hasEncryptedFile(
          subjectId: 'sub-1', resourceId: 'res-5'),
      isTrue,
    ); // metadata still present until first access
    final result = await repoNewBinding.getDecryptedFile(
      subjectId: 'sub-1',
      resourceId: 'res-5',
      userId: 'user-1',
    );
    expect(result, isNull); // content inaccessible under new binding
    expect(
      await repoNewBinding.hasEncryptedFile(
          subjectId: 'sub-1', resourceId: 'res-5'),
      isFalse,
    ); // artifact cleaned

    await dir.delete(recursive: true);
  });

  test('6) revoked access (key removal) blocks decryption and wipes file',
      () async {
    final (repo, dir, storage) = await _buildRepo(_secretA);
    await repo.saveEncryptedFile(
      subjectId: 'sub-1',
      resourceId: 'res-6',
      plaintextBytes: Uint8List.fromList('revoked-content'.codeUnits),
      userId: 'user-1',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );

    // Server-side revocation propagates locally as key removal
    // (revalidateOfflineAccess path).
    await storage.purgeOfflineResource(subjectId: 'sub-1', resourceId: 'res-6');

    final file = File('${dir.path}/sub-1/res-6.drm');
    final result = await repo.getDecryptedFile(
      subjectId: 'sub-1',
      resourceId: 'res-6',
      userId: 'user-1',
    );
    expect(result, isNull);
    expect(await file.exists(), isFalse);

    await dir.delete(recursive: true);
  });

  test('7) same resourceId under two Subjects stays independent', () async {
    final (repo, dir, _) = await _buildRepo(_secretA);
    final expiresAt = DateTime.now().add(const Duration(hours: 2));
    await repo.saveEncryptedFile(
      subjectId: 'sub-A',
      resourceId: 'shared-res',
      plaintextBytes: Uint8List.fromList('subject-A-bytes'.codeUnits),
      userId: 'user-1',
      expiresAt: expiresAt,
    );
    await repo.saveEncryptedFile(
      subjectId: 'sub-B',
      resourceId: 'shared-res',
      plaintextBytes: Uint8List.fromList('subject-B-bytes'.codeUnits),
      userId: 'user-1',
      expiresAt: expiresAt,
    );

    final bytesA = await repo.getDecryptedFile(
      subjectId: 'sub-A', resourceId: 'shared-res', userId: 'user-1');
    final bytesB = await repo.getDecryptedFile(
      subjectId: 'sub-B', resourceId: 'shared-res', userId: 'user-1');
    expect(String.fromCharCodes(bytesA!), 'subject-A-bytes');
    expect(String.fromCharCodes(bytesB!), 'subject-B-bytes');

    await dir.delete(recursive: true);
  });

  test('8) Subject B file cannot be decrypted as Subject A', () async {
    final (repo, dir, _) = await _buildRepo(_secretA);
    await repo.saveEncryptedFile(
      subjectId: 'sub-B',
      resourceId: 'only-b',
      plaintextBytes: Uint8List.fromList('b-secret'.codeUnits),
      userId: 'user-1',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

    // No entitlement record exists under sub-A, so access is refused
    // without touching sub-B state.
    final result = await repo.getDecryptedFile(
      subjectId: 'sub-A', resourceId: 'only-b', userId: 'user-1');
    expect(result, isNull);
    expect(
      await repo.hasEncryptedFile(subjectId: 'sub-B', resourceId: 'only-b'),
      isTrue,
    );

    await dir.delete(recursive: true);
  });

  test('9) purging Subject A keeps Subject B fully usable', () async {
    final (repo, dir, _) = await _buildRepo(_secretA);
    final expiresAt = DateTime.now().add(const Duration(hours: 2));
    await repo.saveEncryptedFile(
      subjectId: 'sub-A',
      resourceId: 'gone',
      plaintextBytes: Uint8List.fromList('a'.codeUnits),
      userId: 'user-1',
      expiresAt: expiresAt,
    );
    await repo.saveEncryptedFile(
      subjectId: 'sub-B',
      resourceId: 'stays',
      plaintextBytes: Uint8List.fromList('b'.codeUnits),
      userId: 'user-1',
      expiresAt: expiresAt,
    );

    await repo.purgeSubjectResources(subjectId: 'sub-A');

    expect(
      await repo.hasEncryptedFile(subjectId: 'sub-A', resourceId: 'gone'),
      isFalse,
    );
    expect(Directory('${dir.path}/sub-A').existsSync(), isFalse);
    final bytesB = await repo.getDecryptedFile(
      subjectId: 'sub-B', resourceId: 'stays', userId: 'user-1');
    expect(String.fromCharCodes(bytesB!), 'b');
    expect(
      await repo.listEncryptedResources(subjectId: 'sub-B'), ['stays']);
    expect(await repo.listEncryptedResources(subjectId: 'sub-A'), isEmpty);

    await dir.delete(recursive: true);
  });

  test('10) listEncryptedResources is scoped per Subject', () async {
    final (repo, dir, _) = await _buildRepo(_secretA);
    final expiresAt = DateTime.now().add(const Duration(hours: 2));
    await repo.saveEncryptedFile(
      subjectId: 'sub-A',
      resourceId: 'a1',
      plaintextBytes: Uint8List.fromList('a'.codeUnits),
      userId: 'user-1',
      expiresAt: expiresAt,
    );
    await repo.saveEncryptedFile(
      subjectId: 'sub-B',
      resourceId: 'b1',
      plaintextBytes: Uint8List.fromList('b'.codeUnits),
      userId: 'user-1',
      expiresAt: expiresAt,
    );

    expect(await repo.listEncryptedResources(subjectId: 'sub-A'), ['a1']);
    expect(await repo.listEncryptedResources(subjectId: 'sub-B'), ['b1']);

    await dir.delete(recursive: true);
  });
}
