abstract class SubjectAccessMutationRepository {
  Future<void> setSubjectAccess({
    required String studentId,
    required String subjectId,
    required bool enabled,
    bool? isDeleted,
  });
}
