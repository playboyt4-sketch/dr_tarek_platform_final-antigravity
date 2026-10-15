import '../../../applications/presentation/providers/application_decision_provider.dart'
    show DecisionFailure;

/// Per-subject outcome of a batch grant.
///
/// A failure for one subject never prevents sibling subjects from being
/// attempted (each subject's write is its own atomic unit server-side);
/// failures are collected here so the UI can report every row honestly
/// instead of aborting on the first error.
class SubjectGrantOutcome {
  final String subjectId;
  final String subjectName;
  final bool success;

  /// Backend message for a failed row; null when [success] is true.
  final String? errorMessage;

  const SubjectGrantOutcome({
    required this.subjectId,
    required this.subjectName,
    required this.success,
    this.errorMessage,
  });
}

/// Subject-access mutations for one student (05 Database v1.8 §24).
///
/// Domain-level seam between the Student Profile providers and the audited
/// Cloud Function callables. Implementations must surface failures as
/// [DecisionFailure] with the backend message — never raw
/// `FirebaseFunctionsException` — so presentation can render them directly.
///
/// Access (ON/OFF) lives in `subject_access_assignments`; the subject-scoped
/// plan (FREE / PRO / MAX) lives in the active `subscriptions` row for the
/// same (student, subject) pair. There is no global student plan.
abstract class SubjectAccessRepository {
  /// Immediate ON/OFF access change for an already-registered subject.
  /// When [restore] is true the assignment is also un-archived
  /// (`isDeleted: false`); otherwise the archive flag is left untouched.
  Future<void> setAccess({
    required String studentId,
    required String subjectId,
    required bool enabled,
    bool restore = false,
  });

  /// Soft-delete (archive) the student-subject assignment. The platform
  /// Subject document is untouched; other students are unaffected.
  Future<void> removeSubject({
    required String studentId,
    required String subjectId,
    required bool enabled,
  });

  /// Atomic per-subject grant: assignment + subscription at [plan]
  /// (`free`, `pro` or `max`) in a single server transaction
  /// (`grantSubjectAccessWithPlan`). Either the whole row is granted or
  /// nothing is written — never an enabled assignment without a plan.
  Future<void> grantAccessWithPlan({
    required String studentId,
    required String subjectId,
    required String studentType,
    required String plan,
  });

  /// Whether the FREE tier may currently be granted
  /// (`system_settings.free_plan_enabled`). `system_settings` is directly
  /// readable only by the Doctor / `admin_settings` delegates, so subject
  /// managers (Doctor or delegated `admin_students`) read it through this
  /// audited callable instead of Firestore.
  Future<bool> isFreePlanEnabled();
}
