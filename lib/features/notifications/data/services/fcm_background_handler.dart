import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dr_tarek_platform/features/pdf_viewer/data/repositories/drm_repository_impl.dart';
import 'package:dr_tarek_platform/features/video_streaming/data/datasources/protected_offline_storage.dart';

/// Top-level background message handler for Firebase Cloud Messaging.
/// Must be registered outside of any class scope.
///
/// Subject-partitioned wipe (ADR-004): each revoked Subject's offline
/// partition (files + keys) is purged independently; unrelated Subjects are
/// never touched. A parse failure falls back to a full wipe, matching the
/// previous fail-closed behavior for uninterpretable revocation signals.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  // Handle silent remote wipe when subscription is revoked
  if (message.data['type'] == 'subscription_revoked') {
    final rawSubjectIds = message.data['subject_ids'];
    final prefs = await SharedPreferences.getInstance();
    final drmRepo = DrmRepositoryImpl(
      protectedStorage: ProtectedOfflineStorageImpl(prefs: prefs),
    );
    if (rawSubjectIds != null) {
      try {
        final List<dynamic> parsed = jsonDecode(rawSubjectIds as String);
        final subjectIds = parsed.whereType<String>().toList();
        for (final subjectId in subjectIds) {
          await drmRepo.purgeSubjectResources(subjectId: subjectId);
        }
        return;
      } catch (_) {
        // Fall through to full wipe below.
      }
    }
    await drmRepo.wipeAllEncryptedFiles();
  }
}
