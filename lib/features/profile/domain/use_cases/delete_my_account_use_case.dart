import '../../domain/repositories/delete_account_repository.dart';

class DeleteMyAccountUseCase {
  final DeleteAccountRepository repository;

  const DeleteMyAccountUseCase(this.repository);

  Future<DeleteAccountResult> execute({
    required String password,
  }) async {
    return repository.deleteMyAccount(password: password);
  }
}