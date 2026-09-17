import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../../../video_streaming/data/datasources/protected_offline_storage.dart';
import '../../domain/repositories/drm_repository.dart';

/// Resolves the sandbox directory that holds `.drm` files.
typedef DirectoryResolver = Future<Directory> Function();

/// Loads the device-bound master secret used for key derivation.
typedef MasterSecretLoader = Future<String> Function();

class DrmRepositoryImpl implements DrmRepository {
  final ProtectedOfflineStorage protectedStorage;
  final DirectoryResolver directoryResolver;
  final MasterSecretLoader loadMasterSecret;

  /// Secure-storage key of the device-bound master secret.
  static const String _masterSecretKey = 'drm_master_secret';

  DrmRepositoryImpl({
    required this.protectedStorage,
    DirectoryResolver? directoryResolver,
    MasterSecretLoader? loadMasterSecret,
  })  : directoryResolver = directoryResolver ?? getApplicationSupportDirectory,
        loadMasterSecret = loadMasterSecret ?? _defaultMasterSecretLoader;

  /// Default master-secret loader: a random 32-byte value generated once per
  /// device install and kept inside [FlutterSecureStorage]. It never leaves
  /// the device and is the root of the per-resource key derivation chain.
  static Future<String> _defaultMasterSecretLoader() async {
    const storage = FlutterSecureStorage();
    var secret = await storage.read(key: _masterSecretKey);
    if (secret == null) {
      final random = math.Random.secure();
      secret = base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
      await storage.write(key: _masterSecretKey, value: secret);
    }
    return secret;
  }

  /// Derives the AES-256 content key from the device-bound master secret
  /// using HKDF-SHA256 with `info = subjectId/resourceId` (same algorithm
  /// and provider as before; only the scope changed). Because the key
  /// material is derived — never stored — rotating the master secret
  /// (device change / unbind / reinstall) instantly invalidates every
  /// existing download: old files fail authentication on decrypt and are
  /// purged on access. Subject scoping additionally guarantees that one
  /// Subject's authorization state can never decrypt another Subject, and
  /// that revoking Subject A never affects Subject B.
  Future<List<int>> _derivedKeyBytes(String subjectId, String resourceId) async {
    final master = await loadMasterSecret();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final secretKey = await hkdf.deriveKey(
      secretKey: SecretKey(base64Decode(master)),
      nonce: utf8.encode('$subjectId/$resourceId'),
    );
    return secretKey.extractBytes();
  }

  /// Subject-partitioned file location: one subdirectory per Subject, so a
  /// per-Subject wipe is a directory delete that cannot touch siblings.
  Future<File> _getFile(String subjectId, String resourceId) async {
    final dir = await directoryResolver();
    return File('${dir.path}/$subjectId/$resourceId.drm');
  }

  Future<Directory> _getSubjectDir(String subjectId) async {
    final dir = await directoryResolver();
    return Directory('${dir.path}/$subjectId');
  }

  @override
  Future<void> saveEncryptedFile({
    required String subjectId,
    required String resourceId,
    required List<int> plaintextBytes,
    required String userId,
    required DateTime expiresAt,
  }) async {
    // 1. Device- and Subject-bound key derivation
    //    (HKDF-SHA256, info = subjectId/resourceId).
    final keyBytes = await _derivedKeyBytes(subjectId, resourceId);
    final keyData = base64Encode(keyBytes);

    // 2. Record key + expiry so entitlement expiry can purge both sides.
    await protectedStorage.saveEncryptedContentKey(
      subjectId: subjectId,
      resourceId: resourceId,
      keyData: keyData,
      expiresAt: expiresAt,
    );

    // 3. Encrypt file using AES-256-GCM.
    final algorithm = AesGcm.with256bits();
    final secretBox = await algorithm.encrypt(
      plaintextBytes,
      secretKey: SecretKey(keyBytes),
    );
    final encryptedBytes = secretBox.concatenation();

    // 4. Save to the Subject partition (.drm only, no plaintext).
    final file = await _getFile(subjectId, resourceId);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsBytes(encryptedBytes, flush: true);
  }

  @override
  Future<List<int>?> getDecryptedFile({
    required String subjectId,
    required String resourceId,
    required String userId,
  }) async {
    // 1. Entitlement gate: expired/revoked/missing -> wipe and refuse.
    //    The stored value acts as bookkeeping; the actual AES key below is
    //    always re-derived locally so restored copies of files + metadata
    //    are useless on any device other than the binding one.
    final entitlement = await protectedStorage.getValidContentKey(
      subjectId: subjectId,
      resourceId: resourceId,
    );
    if (entitlement == null) {
      await deleteEncryptedFile(subjectId: subjectId, resourceId: resourceId);
      return null;
    }
    final List<int> keyBytes;
    try {
      keyBytes = await _derivedKeyBytes(subjectId, resourceId);
    } catch (_) {
      // Undecryptable under this device's key material -> wipe artifact.
      await deleteEncryptedFile(subjectId: subjectId, resourceId: resourceId);
      return null;
    }

    // 2. Read encrypted file from this Subject's partition only.
    final file = await _getFile(subjectId, resourceId);
    if (!await file.exists()) return null;
    final fileBytes = await file.readAsBytes();

    // 3. Decrypt file using AES-256-GCM. A wrong device (different master
    //    secret), a wrong Subject (different derivation scope), or a
    //    tampered file fails authentication here.
    final algorithm = AesGcm.with256bits();
    final secretBox = SecretBox.fromConcatenation(
      fileBytes,
      nonceLength: 12,
      macLength: 16,
    );

    try {
      final decrypted = await algorithm.decrypt(
        secretBox,
        secretKey: SecretKey(keyBytes),
      );
      return decrypted;
    } catch (_) {
      // Tampering, foreign-device key, or foreign-Subject artifact ->
      // purge the unusable artifact.
      await deleteEncryptedFile(subjectId: subjectId, resourceId: resourceId);
      return null;
    }
  }

  @override
  Future<void> deleteEncryptedFile({
    required String subjectId,
    required String resourceId,
  }) async {
    await protectedStorage.purgeOfflineResource(
      subjectId: subjectId,
      resourceId: resourceId,
    );
    final file = await _getFile(subjectId, resourceId);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> hasEncryptedFile({
    required String subjectId,
    required String resourceId,
  }) async {
    final file = await _getFile(subjectId, resourceId);
    final keyData = await protectedStorage.getValidContentKey(
      subjectId: subjectId,
      resourceId: resourceId,
    );
    return await file.exists() && keyData != null;
  }

  @override
  Future<List<String>> listEncryptedResources({String? subjectId}) async {
    final dir = await directoryResolver();
    if (!await dir.exists()) return [];

    final list = <String>[];
    final scopes = subjectId != null
        ? [Directory('${dir.path}/$subjectId')]
        : dir.listSync().whereType<Directory>().toList();
    for (final scope in scopes) {
      if (!await scope.exists()) continue;
      for (final entity in scope.listSync()) {
        if (entity is File && entity.path.endsWith('.drm')) {
          final name = entity.path.split('/').last.split('\\').last.replaceAll('.drm', '');
          list.add(name);
        }
      }
    }
    return list;
  }

  @override
  Future<void> purgeSubjectResources({required String subjectId}) async {
    await protectedStorage.purgeSubjectResources(subjectId: subjectId);
    final subjectDir = await _getSubjectDir(subjectId);
    if (await subjectDir.exists()) {
      await subjectDir.delete(recursive: true);
    }
  }

  @override
  Future<void> wipeAllEncryptedFiles() async {
    final dir = await directoryResolver();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await protectedStorage.purgeAllSubjectResources();
  }
}
