import 'dart:io';

import '../../../lecture/domain/entities/lecture_resource.dart'
    show LectureResourceType;
import '../entities/admin_content_entities.dart';
import '../repositories/admin_content_repository.dart';

/// One class per distinct resource operation (08 Development Standards §4).

class WatchResources {
  final AdminContentRepository repository;
  const WatchResources(this.repository);

  Stream<List<AdminLectureResource>> execute(String lectureId) =>
      repository.watchResources(lectureId);
}

class AddVideoResource {
  final AdminContentRepository repository;
  const AddVideoResource(this.repository);

  /// Bunny video id ONLY — raw URLs are never accepted (06 §6.4 /
  /// 11 Assets §4.3). [sequenceNumber] is the explicit multi-part order
  /// (Feature 04 "Multiple Videos").
  Future<String> execute({
    required String lectureId,
    required String title,
    required int sequenceNumber,
    required String bunnyVideoId,
    int? durationSeconds,
  }) {
    final id = bunnyVideoId.trim();
    if (id.isEmpty) {
      throw ArgumentError('Bunny video id is required for video resources.');
    }
    return repository.createResource(AdminLectureResource(
      id: '',
      lectureId: lectureId,
      resourceType: LectureResourceType.video,
      title: title.trim(),
      displayOrder: sequenceNumber,
      bunnyVideoId: id,
      isVisible: true,
      isDeleted: false,
      duration: durationSeconds,
    ));
  }
}

class AddPdfResource {
  final AdminContentRepository repository;
  const AddPdfResource(this.repository);

  /// Uploads the file under the REAL resource document id, then writes the
  /// metadata document (11 Assets §4.2 path convention). [storageProvider]
  /// (FINAL_DECISIONS §15): explicit Admin per-file choice; null → the
  /// platform default from system_settings.default_storage_provider.
  Future<String> execute({
    required String lectureId,
    required String title,
    required File file,
    int? displayOrder,
    Object? storageProvider,
    void Function(double progress)? onProgress,
  }) {
    return repository.createUploadedResource(
      resource: AdminLectureResource(
        id: '',
        lectureId: lectureId,
        resourceType: LectureResourceType.pdf,
        title: title.trim(),
        displayOrder: displayOrder ?? 0,
        isVisible: true,
        isDeleted: false,
      ),
      file: file,
      storageProvider: storageProvider,
      onProgress: onProgress,
    );
  }
}

class AddAttachmentResource {
  final AdminContentRepository repository;
  const AddAttachmentResource(this.repository);

  /// Same dual-provider upload pattern as PDF, generic + image types
  /// (jpg/jpeg/png approved as attachment types, separate from thumbnails).
  Future<String> execute({
    required String lectureId,
    required String title,
    required File file,
    int? displayOrder,
    Object? storageProvider,
    void Function(double progress)? onProgress,
  }) {
    return repository.createUploadedResource(
      resource: AdminLectureResource(
        id: '',
        lectureId: lectureId,
        resourceType: LectureResourceType.attachment,
        title: title.trim(),
        displayOrder: displayOrder ?? 0,
        isVisible: true,
        isDeleted: false,
      ),
      file: file,
      storageProvider: storageProvider,
      onProgress: onProgress,
    );
  }
}

class AddExternalLinkResource {
  final AdminContentRepository repository;
  const AddExternalLinkResource(this.repository);

  /// [externalUrl] must already be validated well-formed by the caller.
  Future<String> execute({
    required String lectureId,
    required String title,
    required int displayOrder,
    required Uri externalUrl,
  }) {
    return repository.createResource(AdminLectureResource(
      id: '',
      lectureId: lectureId,
      resourceType: LectureResourceType.externalLink,
      title: title.trim(),
      displayOrder: displayOrder,
      externalUrl: externalUrl.toString(),
      isVisible: true,
      isDeleted: false,
    ));
  }
}

class SetResourceThumbnail {
  final AdminContentRepository repository;
  const SetResourceThumbnail(this.repository);

  /// Uploads a thumbnail image and stores its path (+ thumbnail storage
  /// provider, FINAL_DECISIONS §15) on the resource doc.
  Future<String> execute({
    required String lectureId,
    required String resourceId,
    required File file,
    Object? storageProvider,
    void Function(double progress)? onProgress,
  }) =>
      repository.uploadThumbnail(
        lectureId: lectureId,
        resourceId: resourceId,
        file: file,
        storageProvider: storageProvider,
        onProgress: onProgress,
      );
}

class UpdateResource {
  final AdminContentRepository repository;
  const UpdateResource(this.repository);

  Future<void> execute(AdminLectureResource resource) =>
      repository.updateResource(resource);
}

class SetResourceVisibility {
  final AdminContentRepository repository;
  const SetResourceVisibility(this.repository);

  Future<void> execute({required String resourceId, required bool visible}) =>
      repository.setResourceVisibility(resourceId: resourceId, visible: visible);
}

class ArchiveResource {
  final AdminContentRepository repository;
  const ArchiveResource(this.repository);

  /// Soft delete: is_deleted=true + visibility off.
  Future<void> execute(String resourceId) =>
      repository.archiveResource(resourceId);
}

class WatchArchivedResources {
  final AdminContentRepository repository;
  const WatchArchivedResources(this.repository);

  Stream<List<AdminLectureResource>> execute(String lectureId) =>
      repository.watchArchivedResources(lectureId);
}

class RestoreResource {
  final AdminContentRepository repository;
  const RestoreResource(this.repository);

  /// Clears is_deleted/deleted_*; stays hidden until re-shown deliberately.
  Future<void> execute(String resourceId) =>
      repository.restoreResource(resourceId);
}

class ReorderResources {
  final AdminContentRepository repository;
  const ReorderResources(this.repository);

  /// Persists display_order for ALL affected resources atomically.
  Future<void> execute(List<AdminLectureResource> ordered) =>
      repository.reorderResources(ordered);
}
