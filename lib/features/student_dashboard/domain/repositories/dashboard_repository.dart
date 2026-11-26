import '../entities/dashboard_subject.dart';

abstract interface class DashboardRepository {
  Future<List<DashboardSubject>> getAccessibleSubjects({
    required String studentId,
  });

  Stream<List<DashboardSubject>> watchAccessibleSubjects({
    required String studentId,
  });
}
