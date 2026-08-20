import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/entities/academic_period.dart';
import '../../domain/repositories/academic_period_repository.dart';

class FirebaseAcademicPeriodRepository implements AcademicPeriodRepository {
  final FirebaseFunctions _functions;

  FirebaseAcademicPeriodRepository({
    FirebaseFunctions? functions,
  }) : _functions = functions ?? FirebaseFunctions.instance;

  @override
  Future<List<AcademicPeriod>> getPeriods() async {
    final result = await _functions
        .httpsCallable('getAcademicPeriods')
        .call();

    final data = Map<String, dynamic>.from(result.data as Map);
    final rawPeriods = List<Map<String, dynamic>>.from(
      (data['periods'] as List).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );

    return rawPeriods
        .map(AcademicPeriod.fromMap)
        .toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
  }

  @override
  Future<void> initializeDefaultPeriods() async {
    await _functions
        .httpsCallable('initializeAcademicPeriods')
        .call();
  }

  @override
  Future<void> setStatus({
    required String periodId,
    required AcademicPeriodStatus status,
  }) async {
    final value = switch (status) {
      AcademicPeriodStatus.active => 'active',
      AcademicPeriodStatus.ended => 'ended',
    };

    await _functions
        .httpsCallable('setAcademicPeriodStatus')
        .call({
          'periodId': periodId,
          'status': value,
        });
  }

  @override
  Future<void> createExceptionalPeriod({
    required String label,
    String? periodType,
  }) async {
    await _functions
        .httpsCallable('createExceptionalAcademicPeriod')
        .call({
          'label': label,
          'periodType': ?periodType,
        });
  }
}
