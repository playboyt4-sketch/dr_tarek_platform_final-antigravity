abstract class DrmRepository {
  Future<void> saveEncryptedFile({
    required String resourceId,
    required List<int> plaintextBytes,
    required String userId,
    required DateTime expiresAt,
  });

  Future<List<int>?> getDecryptedFile({
    required String resourceId,
    required String userId,
  });

  Future<void> deleteEncryptedFile({required String resourceId});
  Future<bool> hasEncryptedFile({required String resourceId});
  Future<List<String>> listEncryptedResources();
  Future<void> wipeAllEncryptedFiles();
}
