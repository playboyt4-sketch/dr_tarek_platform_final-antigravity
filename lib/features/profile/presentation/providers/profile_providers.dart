import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/delete_account_repository_impl.dart';
import '../../data/repositories/profile_repository_impl.dart';
import '../../domain/repositories/delete_account_repository.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/use_cases/delete_my_account_use_case.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepositoryImpl();
});

final deleteAccountRepositoryProvider = Provider<DeleteAccountRepository>((ref) {
  return DeleteAccountRepositoryImpl();
});

final deleteMyAccountUseCaseProvider = Provider<DeleteMyAccountUseCase>((ref) {
  return DeleteMyAccountUseCase(ref.watch(deleteAccountRepositoryProvider));
});
