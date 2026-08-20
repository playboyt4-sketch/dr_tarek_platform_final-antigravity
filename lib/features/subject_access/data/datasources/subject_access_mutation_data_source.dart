abstract class SubjectAccessMutationDataSource {
  Future<void> setSubjectAccess({
    required String studentId,
    required String subjectId,
    required bool enabled,
    bool? isDeleted,
  });
}
