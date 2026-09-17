import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contract & Implementation for Protected In-App Offline DRM Storage.
///
/// Subject-partitioned (ADR-004): every key, expiry, and index entry is
/// namespaced by Subject, so one Subject's wipe can never leak into or
/// destroy another Subject's key material.
///
/// Ensures:
/// 1. Content is stored strictly in the internal application sandbox.
/// 2. Files CANNOT be exported to Gallery, Files, or shared with external apps.
/// 3. Offline access is bound to the device and the Subject's entitlement.
/// 4. When entitlement is revoked/expired, local cached keys and files are purged immediately.
abstract class ProtectedOfflineStorage {
  Future<void> saveEncryptedContentKey({
    required String subjectId,
    required String resourceId,
    required String keyData,
    required DateTime expiresAt,
  });

  Future<String?> getValidContentKey({
    required String subjectId,
    required String resourceId,
  });

  Future<void> purgeOfflineResource({
    required String subjectId,
    required String resourceId,
  });

  Future<void> purgeAllExpiredOfflineResources();

  /// Deletes one Subject's entire key/expiry partition (files are removed
  /// by the repository's Subject-directory delete).
  Future<void> purgeSubjectResources({required String subjectId});

  /// Deletes every Subject partition (full local reset, e.g. logout).
  Future<void> purgeAllSubjectResources();
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
  static const String _subjectIndexKey = 'drm_subject_index';

  String _scoped(String subjectId, String resourceId) => '${subjectId}_$resourceId';

  Future<List<String>> _getIndex() async {
    return _prefs.getStringList(_indexKey) ?? <String>[];
  }

  Future<void> _addToIndex(String scopedId, String subjectId) async {
    final index = await _getIndex();
    if (!index.contains(scopedId)) {
      index.add(scopedId);
      await _prefs.setStringList(_indexKey, index);
    }
    final subjects = await _getSubjectIndex();
    final resources = subjects[subjectId] ?? <String>[];
    if (!resources.contains(scopedId)) {
      resources.add(scopedId);
      subjects[subjectId] = resources;
      await _saveSubjectIndex(subjects);
    }
  }

  Future<void> _removeFromIndex(String scopedId, String subjectId) async {
    final index = await _getIndex();
    if (index.contains(scopedId)) {
      index.remove(scopedId);
      await _prefs.setStringList(_indexKey, index);
    }
    final subjects = await _getSubjectIndex();
    final resources = subjects[subjectId];
    if (resources != null) {
      resources.remove(scopedId);
      if (resources.isEmpty) {
        subjects.remove(subjectId);
      } else {
        subjects[subjectId] = resources;
      }
      await _saveSubjectIndex(subjects);
    }
  }

  Future<Map<String, List<String>>> _getSubjectIndex() async {
    final raw = _prefs.getString(_subjectIndexKey);
    if (raw == null || raw.isEmpty) return <String, List<String>>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(key, (value as List).whereType<String>().toList()),
      );
    } catch (_) {
      return <String, List<String>>{};
    }
  }

  Future<void> _saveSubjectIndex(Map<String, List<String>> subjects) async {
    await _prefs.setString(_subjectIndexKey, jsonEncode(subjects));
  }

  @override
  Future<void> saveEncryptedContentKey({
    required String subjectId,
    required String resourceId,
    required String keyData,
    required DateTime expiresAt,
  }) async {
    final scopedId = _scoped(subjectId, resourceId);
    await _secureStorage.write(
      key: '$_keyPrefix$scopedId',
      value: keyData,
    );
    await _secureStorage.write(
      key: '$_expiryPrefix$scopedId',
      value: expiresAt.toIso8601String(),
    );
    await _addToIndex(scopedId, subjectId);
  }

  @override
  Future<String?> getValidContentKey({
    required String subjectId,
    required String resourceId,
  }) async {
    final scopedId = _scoped(subjectId, resourceId);
    final expiryStr = await _secureStorage.read(key: '$_expiryPrefix$scopedId');
    if (expiryStr == null) return null;

    final expiry = DateTime.tryParse(expiryStr);
    if (expiry == null || DateTime.now().isAfter(expiry)) {
      // Expired — purge immediately
      await purgeOfflineResource(subjectId: subjectId, resourceId: resourceId);
      return null;
    }

    return _secureStorage.read(key: '$_keyPrefix$scopedId');
  }

  @override
  Future<void> purgeOfflineResource({
    required String subjectId,
    required String resourceId,
  }) async {
    final scopedId = _scoped(subjectId, resourceId);
    await _secureStorage.delete(key: '$_keyPrefix$scopedId');
    await _secureStorage.delete(key: '$_expiryPrefix$scopedId');
    await _removeFromIndex(scopedId, subjectId);
  }

  @override
  Future<void> purgeAllExpiredOfflineResources() async {
    final keys = await _getIndex();
    final subjects = await _getSubjectIndex();
    final now = DateTime.now();

    String subjectOf(String scopedId) {
      for (final entry in subjects.entries) {
        if (entry.value.contains(scopedId)) return entry.key;
      }
      final separator = scopedId.indexOf('_');
      return separator > 0 ? scopedId.substring(0, separator) : '';
    }

    for (final scopedId in keys.toList()) {
      final expiryStr = await _secureStorage.read(key: '$_expiryPrefix$scopedId');
      if (expiryStr != null) {
        final expiry = DateTime.tryParse(expiryStr);
        if (expiry == null || now.isAfter(expiry)) {
          final separator = scopedId.indexOf('_');
          final resourceId = separator >= 0 ? scopedId.substring(separator + 1) : scopedId;
          await purgeOfflineResource(subjectId: subjectOf(scopedId), resourceId: resourceId);
        }
      } else {
        // Missing expiry, purge it
        final separator = scopedId.indexOf('_');
        final resourceId = separator >= 0 ? scopedId.substring(separator + 1) : scopedId;
        await purgeOfflineResource(subjectId: subjectOf(scopedId), resourceId: resourceId);
      }
    }
  }

  @override
  Future<void> purgeSubjectResources({required String subjectId}) async {
    final subjects = await _getSubjectIndex();
    final resources = List<String>.from(subjects[subjectId] ?? const <String>[]);
    for (final scopedId in resources) {
      await _secureStorage.delete(key: '$_keyPrefix$scopedId');
      await _secureStorage.delete(key: '$_expiryPrefix$scopedId');
    }
    final index = await _getIndex();
    index.removeWhere((id) => subjects[subjectId]?.contains(id) ?? false);
    await _prefs.setStringList(_indexKey, index);
    subjects.remove(subjectId);
    await _saveSubjectIndex(subjects);
  }

  @override
  Future<void> purgeAllSubjectResources() async {
    final subjects = await _getSubjectIndex();
    for (final subjectId in subjects.keys.toList()) {
      await purgeSubjectResources(subjectId: subjectId);
    }
    // Defensive sweep for entries predating the subject index.
    await _prefs.remove(_subjectIndexKey);
    await _prefs.remove(_indexKey);
  }
}
