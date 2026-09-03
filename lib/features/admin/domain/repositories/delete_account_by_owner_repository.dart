class DeleteAccountByOwnerResult {
  final Map<String, int> deletedCounts;

  const DeleteAccountByOwnerResult(this.deletedCounts);
}

abstract class DeleteAccountByOwnerRepository {
  Future<DeleteAccountByOwnerResult> deleteAccountByOwner({
    required String targetUid,
    required String password,
  });
}