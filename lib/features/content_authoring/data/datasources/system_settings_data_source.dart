import 'package:cloud_firestore/cloud_firestore.dart';

/// Read-only access to the platform-wide default storage provider
/// (system_settings.default_storage_provider, FINAL_DECISIONS §15 / Part E).
/// Rules allow staff reads of system_settings; writes are Teacher-only
/// callables (setDefaultStorageProvider), so this stays read-only.
class SystemSettingsDataSource {
  final FirebaseFirestore firestore;

  SystemSettingsDataSource({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  /// Returns "bunny" | "firebase" or null when unset (caller defaults).
  Future<String?> defaultStorageProvider() async {
    final snap = await firestore.collection('system_settings').limit(1).get();
    if (snap.docs.isEmpty) return null;
    final value = snap.docs.first.data()['default_storage_provider'];
    return value is String && value.isNotEmpty ? value : null;
  }
}
