import '../../../lecture/domain/entities/lecture.dart';
import '../entities/admin_content_entities.dart';
import '../repositories/admin_content_repository.dart';

/// One class per distinct lecture operation (08 Development Standards §4).

class WatchLectures {
  final AdminContentRepository repository;
  const WatchLectures(this.repository);

  Stream<List<Lecture>> execute(String sectionId) =>
      repository.watchLectures(sectionId);
}

class CreateLecture {
  final AdminContentRepository repository;
  const CreateLecture(this.repository);

  Future<String> execute({
    required String subjectId,
    required String sectionId,
    required String title,
    required String description,
    int? displayOrder,
    DateTime? publishDate,
    bool publicFreeEnabled = false,
    int? publicFreePreviewMinutes,
  }) =>
      repository.createLecture(
        subjectId: subjectId,
        sectionId: sectionId,
        title: title,
        description: description,
        displayOrder: displayOrder,
        publishDate: publishDate,
        publicFreeEnabled: publicFreeEnabled,
        publicFreePreviewMinutes: publicFreePreviewMinutes,
      );
}

class UpdateLectureMetadata {
  final AdminContentRepository repository;
  const UpdateLectureMetadata(this.repository);

  Future<void> execute({
    required String lectureId,
    required String title,
    required String description,
    required int displayOrder,
    DateTime? publishDate,
    bool? publicFreeEnabled,
    int? publicFreePreviewMinutes,
  }) =>
      repository.updateLectureMetadata(
        lectureId: lectureId,
        title: title,
        description: description,
        displayOrder: displayOrder,
        publishDate: publishDate,
        publicFreeEnabled: publicFreeEnabled,
        publicFreePreviewMinutes: publicFreePreviewMinutes,
      );
}

/// FINAL_DECISIONS §11: per-lecture Public Free availability toggle with
/// an independent minute cap. [minutes] null keeps/clears the override so
/// the plan default applies.
class SetLecturePublicFree {
  final AdminContentRepository repository;
  const SetLecturePublicFree(this.repository);

  Future<void> execute({
    required String lectureId,
    required int displayOrder,
    required String title,
    required String description,
    required bool enabled,
    int? minutes,
    DateTime? publishDate,
  }) =>
      repository.updateLectureMetadata(
        lectureId: lectureId,
        title: title,
        description: description,
        displayOrder: displayOrder,
        publishDate: publishDate,
        publicFreeEnabled: enabled,
        publicFreePreviewMinutes: minutes,
      );
}

class SetLecturePublished {
  final AdminContentRepository repository;
  const SetLecturePublished(this.repository);

  Future<void> execute({required String lectureId, required bool published}) =>
      repository.setLecturePublished(lectureId: lectureId, published: published);
}

class ArchiveLecture {
  final AdminContentRepository repository;
  const ArchiveLecture(this.repository);

  /// Soft delete per Master Architecture §10 — never hard-deletes.
  Future<void> execute(String lectureId) => repository.archiveLecture(lectureId);
}

class WatchArchivedLectures {
  final AdminContentRepository repository;
  const WatchArchivedLectures(this.repository);

  Stream<List<ArchivedLecture>> execute(String subjectId) =>
      repository.watchArchivedLectures(subjectId);
}

class RestoreLecture {
  final AdminContentRepository repository;
  const RestoreLecture(this.repository);

  /// Clears is_deleted/deleted_* and returns the lecture to draft.
  Future<void> execute(ArchivedLecture lecture) =>
      repository.restoreLecture(lecture);
}

class ReorderLectures {
  final AdminContentRepository repository;
  const ReorderLectures(this.repository);

  Future<void> execute(List<Lecture> orderedLectures) =>
      repository.reorderLectures(orderedLectures);
}
