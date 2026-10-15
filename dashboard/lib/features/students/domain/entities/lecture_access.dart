/// Per-lecture student access entities (approved V1 backend:
/// `lecture_access_grants/{lectureId_studentId}` — 04 Features §07,
/// 05 Database `lecture_access_grants`, 06 §4.2).
///
/// This is a lecture-specific access override, NOT subscription,
/// membership, enrollment, or grade-level management. A missing grant
/// means "no override" (normal rules apply); `allowed: false` explicitly
/// denies this lecture even for MAX subscribers.
///
/// One staged per-lecture allow/deny decision for a single student.
class LectureAccessGrant {
  final String lectureId;
  final String studentId;
  final bool allowed;

  /// Soft-delete audit state. Read-only for clients: revocation is
  /// `allowed: false`, never a delete (enforced by Security Rules).
  final bool isDeleted;

  const LectureAccessGrant({
    required this.lectureId,
    required this.studentId,
    required this.allowed,
    this.isDeleted = false,
  });
}

/// One eligible roster row: a student enrolled in the lecture's subject.
/// Display-only view (name, student number, subject plan chip); carries
/// no access state — access resolves via [resolveLectureAccess].
class LectureAccessStudent {
  final String id;
  final String name;
  final String? phone;
  final String plan;

  const LectureAccessStudent({
    required this.id,
    required this.name,
    required this.plan,
    this.phone,
  });
}

/// Deterministic grant document id so the same (lecture, student) pair
/// can never produce two documents (repeat-safe saves by construction).
String lectureAccessGrantDocId(String lectureId, String studentId) =>
    '${lectureId}_$studentId';

/// Displayed/saved default for one student: an explicit staged toggle
/// wins, then the stored grant, otherwise ON — meaning "no override",
/// i.e. the student follows normal lecture eligibility. Default ON is
/// behavior-preserving: nothing is denied until the Doctor acts.
bool resolveLectureAccess({bool? staged, bool? grantAllowed}) =>
    staged ?? grantAllowed ?? true;

/// Pure search predicate for the overlay roster. Matches name, student
/// number (phone), or subject plan label; empty query matches all.
/// Extracted pure so filtering stays unit-testable without widgets.
bool matchesLectureAccessQuery({
  required String name,
  required String? phone,
  required String plan,
  required String query,
}) {
  final String needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  if (name.toLowerCase().contains(needle)) return true;
  if ((phone ?? '').toLowerCase().contains(needle)) return true;
  return plan.toLowerCase().contains(needle);
}
