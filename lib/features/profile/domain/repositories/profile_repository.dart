import 'dart:typed_data';

/// Profile data operations for the signed-in student.
abstract class ProfileRepository {
  /// Uploads an avatar to the student's protected Storage path and returns
  /// its download URL. Storage rules allow self-write under profile_photos/.
  Future<String> uploadProfilePhoto({
    required String userId,
    required Uint8List bytes,
    required String fileName,
  });

  /// Persists the avatar URL on the user document (self-editable field).
  Future<void> updateProfilePhotoUrl({
    required String userId,
    required String url,
  });
}
