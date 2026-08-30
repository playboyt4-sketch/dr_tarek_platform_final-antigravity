import 'dart:io';

import '../../../lecture/domain/entities/lecture.dart';
import '../entities/admin_content_entities.dart';

/// Contract for staff content authoring (sections / lectures / resources).
/// Firestore writes are Rules-governed direct — staff writes are
/// Rules-governed, not callable-routed (06 §4.2); file bytes move through
/// ResourceStorageGateway implementations selected per upload by provider.
/// Always through this Repository, never from a widget (06 §4.1).
abstract class AdminContentRepository {
  // ---- Subjects (read-only picker) ----
  Future<List<({String id, String title})>> listSubjects();

  // ---- Sections ----
  Stream<List<AdminSection>> watchSections(String subjectId);
  Future<String> createSection({
    required String subjectId,
    required String title,
    required bool isVisible,
  });

  /// Edits title + visibility only; section_key / is_system_section are
  /// structurally immutable (Feature 03 Business Rules).
  Future<void> updateSection(
    AdminSection section, {
    required String newTitle,
    required bool newIsVisible,
  });

  /// Persists display_order for ALL affected sections atomically.
  Future<void> reorderSections(List<AdminSection> orderedSections);

  /// Deletes a CUSTOM section. Throws:
  ///  - [FailureCode.permissionDenied] for system sections — they may only
  ///    be hidden (Feature 03);
  ///  - [FailureCode.sectionHasActiveLectures] when any non-archived lecture
  ///    remains inside (05 Database v1.9 §9 — no orphaning).
  Future<void> deleteCustomSection(AdminSection section);

  // ---- Lectures ----
  Stream<List<Lecture>> watchLectures(String sectionId);

  Future<String> createLecture({
    required String subjectId,

    /// Required by the getLectureResources callable, which resolves the
    /// lecture's subscription from lecture.subject_id (functions §6.4).
    required String sectionId,
    required String title,
    required String description,
    int? displayOrder, // null -> appended after the last lecture
    DateTime? publishDate,
    bool publicFreeEnabled,
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

  Future<void> setLecturePublished({
    required String lectureId,
    required bool published,
  });

  /// Soft delete per Master Architecture §10: is_deleted=true +
  /// status='archived'. Never hard-deletes (Rules deny it as well).
  Future<void> archiveLecture(String lectureId);

  Future<void> reorderLectures(List<Lecture> orderedLectures);

  // ---- Resources ----
  Stream<List<AdminLectureResource>> watchResources(String lectureId);

  /// Creates a video/external-link resource (no file bytes involved).
  Future<String> createResource(AdminLectureResource resource);

  Future<void> updateResource(AdminLectureResource resource);

  /// Uploads a local pdf/attachment file through the gateway chosen by
  /// [storageProvider] (explicit Admin choice or the platform default,
  /// FINAL_DECISIONS §15) to
  /// /lecture_resources/{lectureId}/{resourceId}/{fileName} under the REAL
  /// resource document id, then writes the metadata document with the final
  /// storage_path AND storage_provider. Emits 0..1 progress via
  /// [onProgress]. Returns the created resource id.
  ///
  /// [storageProvider] accepts a [ResourceStorageProvider] or its wire
  /// string ("bunny"/"firebase"); null → platform default.
  Future<String> createUploadedResource({
    required AdminLectureResource resource,
    required File file,
    Object? storageProvider,
    void Function(double progress)? onProgress,
  });

  /// Uploads a thumbnail image for a resource to the same
  /// /lecture_resources/{lectureId}/{resourceId}/ prefix and stores its
  /// path + thumbnail_storage_provider on the document. Returns the path.
  Future<String> uploadThumbnail({
    required String lectureId,
    required String resourceId,
    required File file,
    Object? storageProvider,
    void Function(double progress)? onProgress,
  });

  Future<void> setResourceVisibility({
    required String resourceId,
    required bool visible,
  });

  /// Soft delete: is_deleted=true + visibility off (Master Arch §10).
  Future<void> archiveResource(String resourceId);

  Future<void> reorderResources(List<AdminLectureResource> orderedResources);

  // ---- Archive System (Part B) ----
  Stream<List<AdminSection>> watchArchivedSections(String subjectId);
  Stream<List<ArchivedLecture>> watchArchivedLectures(String subjectId);
  Stream<List<AdminLectureResource>> watchArchivedResources(String lectureId);
  Future<void> restoreSection(AdminSection section);
  Future<void> restoreLecture(ArchivedLecture lecture);
  Future<void> restoreResource(String resourceId);
}
