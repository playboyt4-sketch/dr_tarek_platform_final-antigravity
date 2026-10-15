import '../../domain/repositories/subject_access_repository.dart';
import '../datasources/subject_access_remote_data_source.dart';

/// Firebase-backed [SubjectAccessRepository].
///
/// Thin delegation: callable wiring and error mapping live in
/// [SubjectAccessRemoteDataSource]; this class binds it to the domain
/// interface so providers (and tests) depend on the abstraction, never
/// on Firebase types.
class SubjectAccessRepositoryImpl implements SubjectAccessRepository {
  final SubjectAccessRemoteDataSource _remote;

  const SubjectAccessRepositoryImpl(this._remote);

  @override
  Future<void> setAccess({
    required String studentId,
    required String subjectId,
    required bool enabled,
    bool restore = false,
  }) {
    return _remote.setAccess(
      studentId: studentId,
      subjectId: subjectId,
      enabled: enabled,
      restore: restore,
    );
  }

  @override
  Future<void> removeSubject({
    required String studentId,
    required String subjectId,
    required bool enabled,
  }) {
    return _remote.removeSubject(
      studentId: studentId,
      subjectId: subjectId,
      enabled: enabled,
    );
  }

  @override
  Future<void> grantAccessWithPlan({
    required String studentId,
    required String subjectId,
    required String studentType,
    required String plan,
  }) {
    return _remote.grantAccessWithPlan(
      studentId: studentId,
      subjectId: subjectId,
      studentType: studentType,
      plan: plan,
    );
  }

  @override
  Future<bool> isFreePlanEnabled() {
    return _remote.isFreePlanEnabled();
  }
}
