import '../../../lecture/domain/entities/lecture.dart';
import '../../domain/entities/admin_content_entities.dart';

/// Abstract Firestore/Storage surface for staff content authoring.
/// Declared as an interface so the Repository (and tests) never bind to
/// the concrete Firebase SDK wiring. File bytes move through
/// [ResourceStorageGateway] implementations, not through this surface.
abstract class AdminContentDataSource {
  // ---- Subjects ----
  Future<List<({String id, String title})>> listSubjects();

  // ---- Sections ----
  Stream<List<AdminSection>> watchSections(String subjectId);
  Future<String> createSection({
    required String subjectId,
    required String title,
    required bool isVisible,
    required int displayOrder,
  });
  Future<void> updateSection({
    required String sectionId,
    required String title,
    required bool isVisible,
  });

  /// Atomic batched rewrite of display_order for every affected section.
  Future<void> reorderSections(List<({String id, int displayOrder})> order);
  Future<void> deleteSection(String sectionId);

  /// Archive System (Part B): soft-deleted sections of one subject.
  Stream<List<AdminSection>> watchArchivedSections(String subjectId);
  Future<void> restoreSection(String sectionId);

  // ---- Lectures ----
  Stream<List<Lecture>> watchLectures(String sectionId);
  Stream<List<ArchivedLecture>> watchArchivedLectures(String subjectId);
  Future<String> createLecture({
    required String subjectId,
    required String sectionId,
    required String title,
    required String description,
    required int displayOrder,
    DateTime? publishDate,
    bool guestEnabled = false,
    int? guestPreviewMinutes,
  });
  Future<void> updateLectureMetadata({
    required String lectureId,
    required String title,
    required String description,
    required int displayOrder,
    DateTime? publishDate,
    bool? guestEnabled,
    int? guestPreviewMinutes,
  });
  Future<void> setLectureStatus({
    required String lectureId,
    required String status,
  });

  /// Soft archive: is_deleted=true + status='archived' (+ deleted_at/by).
  Future<void> archiveLecture(String lectureId);

  /// Archive System (Part B): clears is_deleted/deleted_* and returns the
  /// lecture to draft so it is never accidentally live after restore.
  Future<void> restoreLecture(String lectureId);
  Future<void> reorderLectures(List<({String id, int displayOrder})> order);

  /// Counts non-archived lectures inside a section — powers the
  /// section-deletion block (Part B / 05 Database v1.9 Section 9).
  Future<int> countActiveLectures(String sectionId);

  // ---- Lecture Access (V1 approved backend: lecture_access_grants) ----
  /// Reads the existing `grade` field of a subject document (the same
  /// field the Dashboard approval flow already depends on). Returns null
  /// when the subject carries no grade — callers fall back to the
  /// unfiltered student list instead of inventing a mapping.
  Future<String?> getSubjectGrade(String subjectId);

  /// Streams approved students (`users` where role == 'student').
  /// Grade filtering/sorting happen client-side so no new composite
  /// index is required. [gradeKey] null → all approved students.
  Stream<List<LectureStudent>> watchStudents({String? gradeKey});

  /// Live explicit per-student grants for one lecture. Missing grant =
  /// no override (normal eligibility applies); see docs/notion/05 Database.
  Stream<List<LectureAccessGrant>> watchLectureAccessGrants(String lectureId);

  /// Persists per-lecture allow/deny grants with deterministic document
  /// ids (`{lectureId}_{studentId}` — no duplicates by construction).
  /// One read (existing grants of the lecture, to preserve created_*)
  /// plus one batched write; safe to repeat.
  Future<void> saveLectureAccess(List<LectureAccessGrant> grants);

  // ---- Resources ----
  Stream<List<AdminLectureResource>> watchResources(String lectureId);
  Stream<List<AdminLectureResource>> watchArchivedResources(String lectureId);

  /// Writes a full resource metadata document under [resourceId].
  /// The caller controls the document id so files are uploaded to
  /// /lecture_resources/{lectureId}/{resourceId}/{file} under the REAL
  /// resource id (11 Assets §4.2).
  Future<void> setResourceDoc({
    required String resourceId,
    required Map<String, dynamic> fields,
  });
  Future<void> updateResourceDoc(
      String resourceId, Map<String, dynamic> fields);
  Future<void> reorderResources(List<({String id, int displayOrder})> order);

  /// Archive System (Part B): clears is_deleted/deleted_*, visibility off
  /// so the admin re-enables it deliberately.
  Future<void> restoreResource(String resourceId);

  /// Mirrors storage.rules limits (validDocument/validAttachment 50MB,
  /// validImage 5MB). Confirmed acceptable by the Teacher as placeholder.
  static const maxDocumentBytes = 50 * 1024 * 1024;
  static const maxImageBytes = 5 * 1024 * 1024;
}
