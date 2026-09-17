import '../entities/admin_content_entities.dart';
import '../repositories/admin_content_repository.dart';

/// Per-lecture student access (approved V1 backend: lecture_access_grants).
///
/// Reading is backed by existing schema (`subjects.grade`, `users`);
/// grants persist to `lecture_access_grants/{lectureId_studentId}` with
/// project audit conventions (08 Development Standards §4: one class per
/// distinct operation).

class GetSubjectGrade {
  final AdminContentRepository repository;
  const GetSubjectGrade(this.repository);

  Future<String?> execute(String subjectId) =>
      repository.getSubjectGrade(subjectId);
}

class WatchStudents {
  final AdminContentRepository repository;
  const WatchStudents(this.repository);

  Stream<List<LectureStudent>> execute({String? gradeKey}) =>
      repository.watchStudents(gradeKey: gradeKey);
}

class WatchLectureAccessGrants {
  final AdminContentRepository repository;
  const WatchLectureAccessGrants(this.repository);

  Stream<List<LectureAccessGrant>> execute(String lectureId) =>
      repository.watchLectureAccessGrants(lectureId);
}

class SaveLectureAccess {
  final AdminContentRepository repository;
  const SaveLectureAccess(this.repository);

  Future<void> execute(List<LectureAccessGrant> grants) =>
      repository.saveLectureAccess(grants);
}
