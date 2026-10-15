import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../authentication/domain/entities/auth_user.dart';
import '../../data/repositories/delete_account_repository_impl.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../domain/repositories/delete_account_repository.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/use_cases/delete_my_account_use_case.dart';
import '../../domain/use_cases/get_student_profile_use_case.dart';
import '../../domain/use_cases/update_student_grade_use_case.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepositoryImpl();
});

final deleteAccountRepositoryProvider = Provider<DeleteAccountRepository>((ref) {
  return DeleteAccountRepositoryImpl();
});

final deleteMyAccountUseCaseProvider = Provider<DeleteMyAccountUseCase>((ref) {
  return DeleteMyAccountUseCase(ref.watch(deleteAccountRepositoryProvider));
});

final getStudentProfileUseCaseProvider = Provider<GetStudentProfileUseCase>((ref) {
  return GetStudentProfileUseCase(ref.watch(profileRepositoryProvider));
});

final updateStudentGradeUseCaseProvider = Provider<UpdateStudentGradeUseCase>((ref) {
  return UpdateStudentGradeUseCase(ref.watch(profileRepositoryProvider));
});

/// Real student profile loaded from `users/{studentId}`.
///
/// Single source of truth for the Student Profile → Overview screen;
/// invalidating/refreshing this provider reloads the profile after
/// administrative changes (e.g. grade updates).
final studentProfileProvider =
    FutureProvider.family<AuthUser, String>((ref, studentId) {
  return ref.watch(getStudentProfileUseCaseProvider).execute(
        studentId: studentId,
      );
});
