import '../entities/lecture_access.dart';

/// Per-lecture student access data contract.
///
/// Reads:
/// - roster: students enrolled in a subject (non-deleted
///   `subject_access_assignments` for that subject, joined with approved
///   `users`). Section never affects eligibility.
/// - grants: stored per-lecture overrides (`lecture_access_grants`).
///
/// Writes go through audited batch saves with deterministic ids; audit
/// (`created_by`/`updated_by`, content-audit trigger) and permission
/// enforcement (doctor / `admin_students` / `admin_content` delegation)
/// live backend-side. The client never invents permission or audit
/// identifiers beyond passing the session actor id.
abstract interface class LectureAccessRepository {
  /// Students enrolled in [subjectId], ordered by name.
  Future<List<LectureAccessStudent>> getSubjectRoster(String subjectId);

  /// Stored per-lecture overrides for [lectureId] (non-deleted only).
  Future<List<LectureAccessGrant>> getLectureGrants(String lectureId);

  /// Persists [allowedByStudent] for [lectureId] as one logical batch
  /// save (repeat-safe deterministic ids, `created_*` preserved).
  Future<void> saveLectureGrants({
    required String lectureId,
    required Map<String, bool> allowedByStudent,
    required String actorId,
  });
}
