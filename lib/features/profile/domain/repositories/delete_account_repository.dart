class DeleteAccountResult {
  final Map<String, int> deletedCounts;

  const DeleteAccountResult(this.deletedCounts);
}

abstract class DeleteAccountRepository {
  Future<DeleteAccountResult> deleteMyAccount({
    required String password,
  });
}