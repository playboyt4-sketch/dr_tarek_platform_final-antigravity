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
    bool publicFreeEnabled = false,
    int? publicFreePreviewMinutes,
  });
  Future<void> updateLectureMetadata({
    required String lectureId,
    required String title,
    required String description,
    required int displayOrder,
    DateTime? publishDate,
    bool? publicFreeEnabled,
    int? publicFreePreviewMinutes,
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
