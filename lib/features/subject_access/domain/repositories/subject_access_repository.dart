import '../entities/subject_access_assignment.dart';

abstract class SubjectAccessRepository {
  Future<SubjectAccessAssignment?> getAssignment({
    required String studentId,
    required String subjectId,
  });

  Future<List<SubjectAccessAssignment>> getAssignmentsForStudent({
    required String studentId,
    bool includeDeleted = false,
  });

  Future<List<SubjectAccessAssignment>> getAssignmentsForSubject({
    required String subjectId,
    bool includeDeleted = false,
  });
}
