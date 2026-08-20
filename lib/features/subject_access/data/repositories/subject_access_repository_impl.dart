import '../../domain/entities/subject_access_assignment.dart';
import '../../domain/repositories/subject_access_repository.dart';
import '../../domain/repositories/subject_access_mutation_repository.dart';
import '../datasources/subject_access_data_source.dart';
import '../datasources/subject_access_mutation_data_source.dart';

class SubjectAccessRepositoryImpl
    implements SubjectAccessRepository, SubjectAccessMutationRepository {
  final SubjectAccessDataSource remoteDataSource;
  final SubjectAccessMutationDataSource mutationDataSource;

  const SubjectAccessRepositoryImpl({
    required this.remoteDataSource,
    required this.mutationDataSource,
  });

  @override
  Future<SubjectAccessAssignment?> getAssignment({
    required String studentId,
    required String subjectId,
  }) {
    return remoteDataSource.getAssignment(
      studentId: studentId,
      subjectId: subjectId,
    );
  }

  @override
  Future<List<SubjectAccessAssignment>> getAssignmentsForStudent({
    required String studentId,
    bool includeDeleted = false,
  }) {
    return remoteDataSource.getAssignmentsForStudent(
      studentId: studentId,
      includeDeleted: includeDeleted,
    );
  }

  @override
  Future<void> setSubjectAccess({
    required String studentId,
    required String subjectId,
    required bool enabled,
    bool? isDeleted,
  }) {
    return mutationDataSource.setSubjectAccess(
      studentId: studentId,
      subjectId: subjectId,
      enabled: enabled,
      isDeleted: isDeleted,
    );
  }

  @override
  Future<List<SubjectAccessAssignment>> getAssignmentsForSubject({
    required String subjectId,
    bool includeDeleted = false,
  }) {
    return remoteDataSource.getAssignmentsForSubject(
      subjectId: subjectId,
      includeDeleted: includeDeleted,
    );
  }
}
