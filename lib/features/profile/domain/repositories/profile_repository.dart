import 'dart:typed_data';

import '../../../authentication/domain/entities/auth_user.dart';

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

  /// Updates the student's display name on the user document.
  ///
  /// `full_name` is self-editable per firestore.rules (students may edit
  /// only non-sensitive profile fields); [fullName] must be non-blank.
  /// Permission failures propagate for UI mapping via
  /// `friendlyFunctionErrorMessage`.
  Future<void> updateFullName({
    required String userId,
    required String fullName,
  });

  /// Loads a student's profile from `users/{studentId}`.
  ///
  /// Returns the authoritative [AuthUser] (whose `grade` maps to the
  /// canonical `users.grade` field). Throws [StateError] when the
  /// document does not exist.
  Future<AuthUser> getStudentProfile(String studentId);

  /// Updates a student's canonical grade via the `updateStudentGrade`
  /// callable (`users/{studentId}.grade`).
  ///
  /// [grade] must be a canonical key (`grade_one` … `grade_four`).
  /// Server authorization is authoritative; [FirebaseFunctionsException]
  /// (e.g. `permission-denied`) propagates to the caller for mapping
  /// via `friendlyFunctionErrorMessage`.
  Future<void> updateStudentGrade({
    required String studentId,
    required String grade,
  });
}
