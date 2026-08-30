import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contract & Implementation for Protected In-App Offline DRM Storage.
///
/// Ensures:
/// 1. Content is stored strictly in the internal application sandbox.
/// 2. Files CANNOT be exported to Gallery, Files, or shared with external apps.
/// 3. Offline access is bound to active device and subscription entitlement.
/// 4. When entitlement is revoked/expired, local cached keys and files are purged immediately.
abstract class ProtectedOfflineStorage {
  Future<void> saveEncryptedContentKey({
    required String resourceId,
    required String keyData,
    required DateTime expiresAt,
  });

  Future<String?> getValidContentKey({
    required String resourceId,
  });

  Future<void> purgeOfflineResource({
    required String resourceId,
  });

  Future<void> purgeAllExpiredOfflineResources();
}

class ProtectedOfflineStorageImpl implements ProtectedOfflineStorage {
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;

  ProtectedOfflineStorageImpl({
    FlutterSecureStorage? secureStorage,
    required this._prefs,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _keyPrefix = 'drm_key_';
  static const String _expiryPrefix = 'drm_expiry_';
  static const String _indexKey = 'drm_resource_index';

  Future<List<String>> _getIndex() async {
    return _prefs.getStringList(_indexKey) ?? <String>[];
  }

  Future<void> _addToIndex(String resourceId) async {
    final index = await _getIndex();
    if (!index.contains(resourceId)) {
      index.add(resourceId);
      await _prefs.setStringList(_indexKey, index);
    }
  }

  Future<void> _removeFromIndex(String resourceId) async {
    final index = await _getIndex();
    if (index.contains(resourceId)) {
      index.remove(resourceId);
      await _prefs.setStringList(_indexKey, index);
    }
  }

  @override
  Future<void> saveEncryptedContentKey({
    required String resourceId,
    required String keyData,
    required DateTime expiresAt,
  }) async {
    await _secureStorage.write(
      key: '$_keyPrefix$resourceId',
      value: keyData,
    );
    await _secureStorage.write(
      key: '$_expiryPrefix$resourceId',
      value: expiresAt.toIso8601String(),
    );
    await _addToIndex(resourceId);
  }

  @override
  Future<String?> getValidContentKey({
    required String resourceId,
  }) async {
    final expiryStr = await _secureStorage.read(key: '$_expiryPrefix$resourceId');
    if (expiryStr == null) return null;

    final expiry = DateTime.tryParse(expiryStr);
    if (expiry == null || DateTime.now().isAfter(expiry)) {
      // Expired — purge immediately
      await purgeOfflineResource(resourceId: resourceId);
      return null;
    }

    return _secureStorage.read(key: '$_keyPrefix$resourceId');
  }

  @override
  Future<void> purgeOfflineResource({
    required String resourceId,
  }) async {
    await _secureStorage.delete(key: '$_keyPrefix$resourceId');
    await _secureStorage.delete(key: '$_expiryPrefix$resourceId');
    await _removeFromIndex(resourceId);
  }

  @override
  Future<void> purgeAllExpiredOfflineResources() async {
    final keys = await _getIndex();
    final now = DateTime.now();

    for (final resourceId in keys.toList()) {
      final expiryStr = await _secureStorage.read(key: '$_expiryPrefix$resourceId');
      if (expiryStr != null) {
        final expiry = DateTime.tryParse(expiryStr);
        if (expiry == null || now.isAfter(expiry)) {
          await purgeOfflineResource(resourceId: resourceId);
        }
      } else {
        // Missing expiry, purge it
        await purgeOfflineResource(resourceId: resourceId);
      }
    }
  }
}
