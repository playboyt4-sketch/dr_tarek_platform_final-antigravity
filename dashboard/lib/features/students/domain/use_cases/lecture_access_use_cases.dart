import '../entities/lecture_access.dart';
import '../repositories/lecture_access_repository.dart';

/// Per-lecture student access operations (08 Development Standards §4:
/// one class per distinct operation). Widgets call these through
/// Riverpod providers — never Firestore directly.

class GetSubjectLectureRoster {
  final LectureAccessRepository repository;
  const GetSubjectLectureRoster(this.repository);

  Future<List<LectureAccessStudent>> execute(String subjectId) =>
      repository.getSubjectRoster(subjectId);
}

class GetLectureAccessGrants {
  final LectureAccessRepository repository;
  const GetLectureAccessGrants(this.repository);

  Future<List<LectureAccessGrant>> execute(String lectureId) =>
      repository.getLectureGrants(lectureId);
}

class SaveLectureAccessOverrides {
  final LectureAccessRepository repository;
  const SaveLectureAccessOverrides(this.repository);

  Future<void> execute({
    required String lectureId,
    required Map<String, bool> allowedByStudent,
    required String actorId,
  }) =>
      repository.saveLectureGrants(
        lectureId: lectureId,
        allowedByStudent: allowedByStudent,
        actorId: actorId,
      );
}
