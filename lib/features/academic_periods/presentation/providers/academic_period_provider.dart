import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/firebase_academic_period_repository.dart';
import '../../domain/entities/academic_period.dart';
import '../../domain/repositories/academic_period_repository.dart';

final academicPeriodRepositoryProvider =
    Provider<AcademicPeriodRepository>(
  (ref) => FirebaseAcademicPeriodRepository(),
);

final academicPeriodsProvider =
    FutureProvider.autoDispose<List<AcademicPeriod>>(
  (ref) {
    return ref
        .read(academicPeriodRepositoryProvider)
        .getPeriods();
  },
);
