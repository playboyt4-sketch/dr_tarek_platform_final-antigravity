import '../../domain/entities/dashboard_subject.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_remote_data_source.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final DashboardRemoteDataSource remoteDataSource;

  const DashboardRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<DashboardSubject>> getAccessibleSubjects({
    required String studentId,
  }) {
    return remoteDataSource.getAccessibleSubjects(studentId: studentId);
  }
}
