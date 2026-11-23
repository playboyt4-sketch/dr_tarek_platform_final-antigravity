import 'dart:typed_data';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../datasources/protected_offline_storage.dart';

/// Service responsible for managing encrypted offline learning resources (Videos and PDFs).
/// Enforces:
/// 1. Files are stored exclusively in the private app sandbox.
/// 2. Files are encrypted with AES-GCM 256-bit using a securely generated key stored in KeyStore/KeyChain.
/// 3. Immediate local wipe when subscription entitlement expires or is revoked via FCM.
class OfflineDrmService {
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;
  static final AesGcm _aesGcm = AesGcm.with256bits();

  static const String _keyPrefix = 'drm_key_';
  static const String _expiryPrefix = 'drm_expiry_';
  static const String _offlineDirName = '.dr_tarek_vault';

  OfflineDrmService({
    FlutterSecureStorage? secureStorage,
    required this._prefs,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Returns the isolated directory path for offline encrypted media
  Future<Directory> _getVaultDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final vault = Directory(p.join(appDir.path, _offlineDirName));
    if (!await vault.exists()) {
      await vault.create(recursive: true);
    }
    return vault;
  }

  /// Encrypts raw downloaded bytes using AES-GCM 256-bit and saves to app sandbox
  Future<File> saveEncryptedResource({
    required String resourceId,
    required String subjectId,
    required List<int> rawBytes,
    required DateTime expiresAt,
  }) async {
    final vault = await _getVaultDirectory();
    final filePath = p.join(vault.path, '${subjectId}_$resourceId.bin');

    // Generate random 256-bit AES key for this resource
    final secretKey = await _aesGcm.newSecretKey();
    final keyBytes = await secretKey.extractBytes();
    final keyHex = keyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

    // Store key and expiration securely
    await _secureStorage.write(key: '$_keyPrefix$resourceId', value: keyHex);
    await _prefs.setString('$_expiryPrefix$resourceId', expiresAt.toIso8601String());

    // Perform AES-GCM 256-bit authenticated encryption
    final secretBox = await _aesGcm.encrypt(
      rawBytes,
      secretKey: secretKey,
    );
    final encrypted = secretBox.concatenation();
    final file = File(filePath);
    await file.writeAsBytes(encrypted, flush: true);

    return file;
  }

  /// Retrieves and decrypts bytes in-memory only when valid
  Future<Uint8List?> getDecryptedBytes({required String resourceId}) async {
    // 1. Verify expiry
    final expiryStr = _prefs.getString('$_expiryPrefix$resourceId');
    if (expiryStr == null) return null;

    final expiry = DateTime.tryParse(expiryStr);
    if (expiry == null || DateTime.now().isAfter(expiry)) {
      await purgeResource(resourceId);
      return null;
    }

    // 2. Retrieve key
    final keyHex = await _secureStorage.read(key: '$_keyPrefix$resourceId');
    if (keyHex == null) return null;

    final keyBytes = _hexToBytes(keyHex);
    final secretKey = SecretKey(keyBytes);

    // 3. Read encrypted file
    final vault = await _getVaultDirectory();
    final entities = await vault.list().toList();
    File? targetFile;
    for (final entity in entities) {
      if (entity is File && entity.path.contains(resourceId)) {
        targetFile = entity;
        break;
      }
    }

    if (targetFile == null || !await targetFile.exists()) return null;

    final encryptedBytes = await targetFile.readAsBytes();

    // 4. Decrypt via AES-GCM 256-bit
    try {
      final secretBox = SecretBox.fromConcatenation(
        encryptedBytes,
        nonceLength: _aesGcm.nonceLength,
        macLength: _aesGcm.macAlgorithm.macLength,
      );
      final decrypted = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );
      return Uint8List.fromList(decrypted);
    } catch (_) {
      return null;
    }
  }

  /// Purges a single offline resource and its key immediately
  Future<void> purgeResource(String resourceId) async {
    await _secureStorage.delete(key: '$_keyPrefix$resourceId');
    await _prefs.remove('$_expiryPrefix$resourceId');

    final vault = await _getVaultDirectory();
    final entities = await vault.list().toList();
    for (final entity in entities) {
      if (entity is File && entity.path.contains(resourceId)) {
        await entity.delete();
      }
    }
  }

  /// Wipes all offline resources belonging to specific subjects.
  /// Deletes both the Subject-prefixed files and their namespaced key/expiry
  /// records so no key material survives a Subject wipe (ADR-004 partition
  /// rule: one Subject's wipe never touches another Subject).
  Future<void> purgeSubjects(List<String> subjectIds) async {
    final vault = await _getVaultDirectory();
    final entities = await vault.list().toList();
    for (final entity in entities) {
      if (entity is File) {
        final filename = p.basename(entity.path);
        for (final subjectId in subjectIds) {
          if (filename.startsWith('${subjectId}_')) {
            await entity.delete();
          }
        }
      }
    }
    final keyStore = ProtectedOfflineStorageImpl(prefs: _prefs);
    for (final subjectId in subjectIds) {
      await keyStore.purgeSubjectResources(subjectId: subjectId);
    }
  }

  /// Complete local wipe of all offline data
  Future<void> wipeAllOfflineData() async {
    final vault = await _getVaultDirectory();
    if (await vault.exists()) {
      await vault.delete(recursive: true);
    }
    final keys = _prefs.getKeys().where((k) => k.startsWith(_expiryPrefix));
    for (final k in keys) {
      final resId = k.replaceFirst(_expiryPrefix, '');
      await _secureStorage.delete(key: '$_keyPrefix$resId');
      await _prefs.remove(k);
    }
  }


  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }
}
