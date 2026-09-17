/// Subject-partitioned offline DRM contract (ADR-004).
///
/// Every protected operation is scoped to one Subject: keys, files, and
/// entitlement records for Subject A can never authorize Subject B
/// content. The repository consumes authorization outcomes (Full vs Guest)
/// enforced server-side; it never counts device slots or resolves tiers.
abstract class DrmRepository {
  Future<void> saveEncryptedFile({
    required String subjectId,
    required String resourceId,
    required List<int> plaintextBytes,
    required String userId,
    required DateTime expiresAt,
  });

  Future<List<int>?> getDecryptedFile({
    required String subjectId,
    required String resourceId,
    required String userId,
  });

  Future<void> deleteEncryptedFile({
    required String subjectId,
    required String resourceId,
  });
  Future<bool> hasEncryptedFile({
    required String subjectId,
    required String resourceId,
  });
  Future<List<String>> listEncryptedResources({String? subjectId});

  /// Deletes one Subject's partition only: its files plus its key/expiry
  /// records. Other Subjects are untouched. Used for per-Subject revoke,
  /// expiry, and approved-reset signals.
  Future<void> purgeSubjectResources({required String subjectId});
  Future<void> wipeAllEncryptedFiles();
}
