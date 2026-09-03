import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/delete_account_by_owner_repository_impl.dart';
import '../../domain/repositories/delete_account_by_owner_repository.dart';
import '../../domain/use_cases/delete_account_by_owner_use_case.dart';

final deleteAccountByOwnerRepositoryProvider = Provider<DeleteAccountByOwnerRepository>(
  (ref) => DeleteAccountByOwnerRepositoryImpl(),
);

final deleteAccountByOwnerUseCaseProvider = Provider<DeleteAccountByOwnerUseCase>(
  (ref) => DeleteAccountByOwnerUseCase(
    ref.watch(deleteAccountByOwnerRepositoryProvider),
  ),
);