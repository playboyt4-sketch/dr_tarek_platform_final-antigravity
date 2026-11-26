/// Canonical "live student" predicate shared by every Dashboard student
/// list, count, and queue.
///
/// A record is live only when it is not soft-deleted and its account is not
/// disabled. The approved lifecycle (soft delete + audit retention) keeps
/// the historical row in `users`, so every read path must exclude it here
/// rather than assuming the row was removed.
bool isArchivedData(Map<String, dynamic> data) {
  return data['is_archived'] == true || data['is_deleted'] == true;
}

bool isLiveStudent(Map<String, dynamic> data) {
  if (isArchivedData(data)) return false;
  if (data['account_status'] == 'disabled') return false;
  return true;
}
