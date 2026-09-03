import '../../domain/repositories/delete_account_by_owner_repository.dart';

class DeleteAccountByOwnerUseCase {
  final DeleteAccountByOwnerRepository repository;

  const DeleteAccountByOwnerUseCase(this.repository);

  Future<DeleteAccountByOwnerResult> execute({
    required String targetUid,
    required String password,
  }) async {
    return repository.deleteAccountByOwner(
      targetUid: targetUid,
      password: password,
    );
  }
}