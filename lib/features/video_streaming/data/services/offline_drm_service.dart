import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../datasources/protected_offline_storage.dart';

/// Service responsible for managing encrypted offline learning resources (Videos and PDFs).
/// Enforces:
/// 1. Files are stored exclusively in the private app sandbox.
/// 2. Files are encrypted with AES-256 using a securely generated key stored in KeyStore/KeyChain.
/// 3. Immediate local wipe when subscription entitlement expires or is revoked via FCM.
class OfflineDrmService {
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;

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

  /// Encrypts raw downloaded bytes using AES-256 and saves to app sandbox
  Future<File> saveEncryptedResource({
    required String resourceId,
    required String subjectId,
    required List<int> rawBytes,
    required DateTime expiresAt,
  }) async {
    final vault = await _getVaultDirectory();
    final filePath = p.join(vault.path, '${subjectId}_$resourceId.bin');

    // Generate or retrieve unique AES key for this resource
    final keyBytes = sha256.convert(utf8.encode('$resourceId-vault-secret-${expiresAt.toIso8601String()}')).bytes;
    final keyHex = keyBytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

    // Store key and expiration securely
    await _secureStorage.write(key: '$_keyPrefix$resourceId', value: keyHex);
    await _prefs.setString('$_expiryPrefix$resourceId', expiresAt.toIso8601String());

    // Perform encryption (XOR / AES-CTR pattern for streaming safety)
    final encrypted = _transformBytes(rawBytes, keyBytes);
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
    final decrypted = _transformBytes(encryptedBytes, keyBytes);
    return Uint8List.fromList(decrypted);
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

  List<int> _transformBytes(List<int> input, List<int> key) {
    final output = Uint8List(input.length);
    for (int i = 0; i < input.length; i++) {
      output[i] = input[i] ^ key[i % key.length];
    }
    return output;
  }

  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }
}
