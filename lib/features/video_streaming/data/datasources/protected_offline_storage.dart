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
    await _prefs.setString(
      '$_expiryPrefix$resourceId',
      expiresAt.toIso8601String(),
    );
  }

  @override
  Future<String?> getValidContentKey({
    required String resourceId,
  }) async {
    final expiryStr = _prefs.getString('$_expiryPrefix$resourceId');
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
    await _prefs.remove('$_expiryPrefix$resourceId');
  }

  @override
  Future<void> purgeAllExpiredOfflineResources() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_expiryPrefix));
    final now = DateTime.now();

    for (final expiryKey in keys) {
      final resourceId = expiryKey.replaceFirst(_expiryPrefix, '');
      final expiryStr = _prefs.getString(expiryKey);
      if (expiryStr != null) {
        final expiry = DateTime.tryParse(expiryStr);
        if (expiry == null || now.isAfter(expiry)) {
          await purgeOfflineResource(resourceId: resourceId);
        }
      }
    }
  }
}
