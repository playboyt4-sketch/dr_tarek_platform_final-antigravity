import '../entities/academic_period.dart';

abstract class AcademicPeriodRepository {
  Future<List<AcademicPeriod>> getPeriods();

  Future<void> initializeDefaultPeriods();

  Future<void> setStatus({
    required String periodId,
    required AcademicPeriodStatus status,
  });

  Future<void> createExceptionalPeriod({
    required String label,
    String? periodType,
  });
}
