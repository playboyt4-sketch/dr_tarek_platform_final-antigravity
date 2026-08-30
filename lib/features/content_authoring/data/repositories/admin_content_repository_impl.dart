import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../../core/errors/failure.dart';
import '../../../lecture/domain/entities/lecture.dart';
import '../../../lecture/domain/entities/lecture_resource.dart'
    show LectureResourceType;
import '../../domain/entities/admin_content_entities.dart';
import '../../domain/repositories/admin_content_repository.dart';
import '../datasources/admin_content_data_source.dart';
import '../datasources/admin_content_remote_data_source_impl.dart'
    show adminResourceFields;
import '../storage/bunny_resource_storage_gateway.dart';
import '../storage/firebase_resource_storage_gateway.dart';
import '../storage/resource_storage_gateway.dart';
/// Firestore + dual-provider storage implementation of staff content
/// authoring. Enforces, at the Repository boundary (defense-in-depth
/// alongside firestore.rules / storage.rules):
///  - system sections can be edited but never deleted (Feature 03);
///  - custom sections cannot be deleted while active lectures remain
///    (05 Database v1.9 §9 — no orphaning);
///  - lectures/resources are only ever soft-archived (MA §10);
///  - uploaded files respect the 50MB ceiling (Teacher-confirmed
///    placeholder) before any bytes leave the device;
///  - the correct ResourceStorageGateway is selected per upload from the
///    Admin's per-file choice or system_settings.default_storage_provider
///    (FINAL_DECISIONS §15) — provider branching lives ONLY here and in
///    the gateway implementations, never above the data layer.
class AdminContentRepositoryImpl implements AdminContentRepository {
  final AdminContentDataSource dataSource;

  /// Both backends must be registered; selection happens at runtime.
  final Map<ResourceStorageProvider, ResourceStorageGateway> gateways;

  /// Production wiring reads system_settings.default_storage_provider once;
  /// tests inject fakes. Null result or absent loader → firebase default.
  final Future<String?> Function()? platformDefaultProviderLoader;

  AdminContentRepositoryImpl({
    required this.dataSource,
    Map<ResourceStorageProvider, ResourceStorageGateway>? gateways,
    this.platformDefaultProviderLoader,
  }) : gateways = gateways ??
            {
              ResourceStorageProvider.firebase:
                  FirebaseResourceStorageGateway(
                      storage: FirebaseStorage.instance,
                      functions: FirebaseFunctions.instance),
              ResourceStorageProvider.bunny: BunnyResourceStorageGateway(
                  functions: FirebaseFunctions.instance),
            };

  /// THE dispatch point of Part A.3: resolves override → platform default
  /// → firebase, then routes to the matching gateway. No caller above this
  /// layer ever learns which backend was picked.
  Future<ResourceStorageGateway> _gatewayFor(Object? explicitChoice) async {
    ResourceStorageProvider? chosen;
    if (explicitChoice is ResourceStorageProvider) {
      chosen = explicitChoice;
    } else if (explicitChoice is String && explicitChoice.isNotEmpty) {
      chosen = ResourceStorageProvider.fromWire(explicitChoice);
    } else {
      final loader = platformDefaultProviderLoader;
      chosen = ResourceStorageProvider.fromWire(loader == null ? null : await loader());
    }
    final gateway = gateways[chosen];
    if (gateway == null) {
      throw Failure(
        FailureCode.server,
        debugDetail: 'No storage gateway registered for provider '
            '${chosen.wireValue}.',
      );
    }
    return gateway;
  }

  // ---- Subjects ----
  @override
  Future<List<({String id, String title})>> listSubjects() =>
      dataSource.listSubjects();

  // ---- Sections ----
  @override
  Stream<List<AdminSection>> watchSections(String subjectId) =>
      dataSource.watchSections(subjectId);

  int _nextOrder(int currentMax) => currentMax + 1;

  @override
  Future<String> createSection({
    required String subjectId,
    required String title,
    required bool isVisible,
  }) async {
    final existing = await dataSource.watchSections(subjectId).first;
    final next = existing.isEmpty
        ? 1
        : _nextOrder(
            existing.map((s) => s.displayOrder).reduce((a, b) => a > b ? a : b));
    return dataSource.createSection(
      subjectId: subjectId,
      title: title.trim(),
      isVisible: isVisible,
      displayOrder: next,
    );
  }

  @override
  Future<void> updateSection(AdminSection section,
      {required String newTitle, required bool newIsVisible}) async {
    // section_key / is_system_section are intentionally NOT writable here —
    // system identity is immutable (Feature 03 Business Rules).
    await dataSource.updateSection(
      sectionId: section.id,
      title: newTitle.trim(),
      isVisible: newIsVisible,
    );
  }

  @override
  Future<void> reorderSections(List<AdminSection> ordered) {
    return _reorderAll(
      ordered.map((s) => s.id).toList(),
      dataSource.reorderSections,
    );
  }

  @override
  Future<void> deleteCustomSection(AdminSection section) async {
    if (section.isSystemSection) {
      throw const Failure(
        FailureCode.permissionDenied,
        debugDetail:
            'System sections can only be hidden, never deleted (Feature 03).',
      );
    }
    // Part B / ratified Open-Question answer: BLOCK deletion while any
    // non-archived lecture remains inside — never orphan content.
    final activeLectures = await dataSource.countActiveLectures(section.id);
    if (activeLectures > 0) {
      throw const Failure(
        FailureCode.sectionHasActiveLectures,
        debugDetail:
            'لا يمكن حذف القسم لوجود محاضرات نشطة بداخله. يرجى أرشفة المحاضرات أولاً.',
      );
    }
    await dataSource.deleteSection(section.id);
  }

  // ---- Lectures ----
  @override
  Stream<List<Lecture>> watchLectures(String sectionId) =>
      dataSource.watchLectures(sectionId);

  @override
  Future<String> createLecture({
    required String subjectId,
    required String sectionId,
    required String title,
    required String description,
    int? displayOrder,
    DateTime? publishDate,
    bool publicFreeEnabled = false,
    int? publicFreePreviewMinutes,
  }) async {
    final existing = await dataSource.watchLectures(sectionId).first;
    final next = existing.isEmpty
        ? 1
        : _nextOrder(existing
            .map((l) => l.displayOrder)
            .reduce((a, b) => a > b ? a : b));
    return dataSource.createLecture(
      subjectId: subjectId,
      sectionId: sectionId,
      title: title.trim(),
      description: description.trim(),
      displayOrder: displayOrder ?? next,
      publishDate: publishDate,
      publicFreeEnabled: publicFreeEnabled,
      publicFreePreviewMinutes: publicFreePreviewMinutes,
    );
  }

  @override
  Future<void> updateLectureMetadata({
    required String lectureId,
    required String title,
    required String description,
    required int displayOrder,
    DateTime? publishDate,
    bool? publicFreeEnabled,
    int? publicFreePreviewMinutes,
  }) {
    return dataSource.updateLectureMetadata(
      lectureId: lectureId,
      title: title.trim(),
      description: description.trim(),
      displayOrder: displayOrder,
      publishDate: publishDate,
      publicFreeEnabled: publicFreeEnabled,
      publicFreePreviewMinutes: publicFreePreviewMinutes,
    );
  }

  @override
  Future<void> setLecturePublished(
          {required String lectureId, required bool published}) =>
      dataSource.setLectureStatus(
          lectureId: lectureId, status: published ? 'published' : 'draft');

  @override
  Future<void> archiveLecture(String lectureId) =>
      dataSource.archiveLecture(lectureId);

  @override
  Future<void> restoreLecture(ArchivedLecture lecture) =>
      dataSource.restoreLecture(lecture.id);

  @override
  Future<void> reorderLectures(List<Lecture> ordered) {
    return _reorderAll(
      ordered.map((l) => l.id).toList(),
      dataSource.reorderLectures,
    );
  }

  // ---- Resources ----
  @override
  Stream<List<AdminLectureResource>> watchResources(String lectureId) =>
      dataSource.watchResources(lectureId);

  Future<int> _nextResourceOrder(String lectureId) async {
    final existing =
        await dataSource.watchResources(lectureId).first;
    if (existing.isEmpty) return 1;
    return _nextOrder(existing
        .map((r) => r.displayOrder)
        .reduce((a, b) => a > b ? a : b));
  }

  @override
  Future<String> createResource(AdminLectureResource resource) async {
    if (resource.resourceType == LectureResourceType.video &&
        (resource.bunnyVideoId?.trim().isEmpty ?? true)) {
      throw const Failure(
        FailureCode.validation,
        debugDetail: 'Video resources must carry a Bunny video id (06 §6.4).',
      );
    }
    if (resource.resourceType == LectureResourceType.externalLink &&
        (resource.externalUrl?.trim().isEmpty ?? true)) {
      throw const Failure(
        FailureCode.validation,
        debugDetail: 'External-link resources require a validated URL.',
      );
    }
    final id =
        DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final displayOrder = resource.displayOrder > 0
        ? resource.displayOrder
        : await _nextResourceOrder(resource.lectureId);
    await dataSource.setResourceDoc(
      resourceId: id,
      fields: adminResourceFields(
        AdminLectureResource(
          id: id,
          lectureId: resource.lectureId,
          resourceType: resource.resourceType,
          title: resource.title,
          displayOrder: displayOrder,
          bunnyVideoId: resource.bunnyVideoId,
          storagePath: resource.storagePath,
          externalUrl: resource.externalUrl,
          thumbnail: resource.thumbnail,
          duration: resource.duration,
          isVisible: resource.isVisible,
          isDeleted: resource.isDeleted,
        ),
      ),
    );
    return id;
  }

  @override
  Future<void> updateResource(AdminLectureResource resource) =>
      dataSource.updateResourceDoc(resource.id, adminResourceFields(resource));

  @override
  Future<String> createUploadedResource({
    required AdminLectureResource resource,
    required File file,
    Object? storageProvider,
    void Function(double progress)? onProgress,
  }) async {
    if (file.lengthSync() > AdminContentDataSource.maxDocumentBytes) {
      throw const Failure(
        FailureCode.validation,
        debugDetail:
            'FILE_TOO_LARGE: files must stay under the 50MB placeholder '
            'ceiling (mirrors storage.rules; Teacher-confirmed placeholder).',
      );
    }

    // The document id exists BEFORE the upload so bytes land at
    // /lecture_resources/{lecture_id}/{resource_id}/{file} with the REAL
    // resource id (11 Assets §4.2), and metadata + path land together.
    final resourceId =
        DateTime.now().microsecondsSinceEpoch.toRadixString(36);

    // Dual-provider dispatch (FINAL_DECISIONS §15): gateway chosen HERE,
    // from the explicit choice or the platform default.
    final gateway = await _gatewayFor(storageProvider);
    final stored = await gateway.upload(
      lectureId: resource.lectureId,
      resourceId: resourceId,
      file: file,
      contentTypeOverride: _contentTypeFor(file),
      onProgress: onProgress,
    );

    final displayOrder = resource.displayOrder > 0
        ? resource.displayOrder
        : await _nextResourceOrder(resource.lectureId);
    await dataSource.setResourceDoc(
      resourceId: resourceId,
      fields: adminResourceFields(
        AdminLectureResource(
          id: resourceId,
          lectureId: resource.lectureId,
          resourceType: resource.resourceType,
          title: resource.title,
          displayOrder: displayOrder,
          bunnyVideoId: null,
          storagePath: stored.storagePath,
          storageProvider: stored.provider,
          externalUrl: null,
          thumbnail: null,
          duration: null,
          isVisible: true,
          isDeleted: false,
        ),
      ),
    );
    return resourceId;
  }

  @override
  Future<String> uploadThumbnail({
    required String lectureId,
    required String resourceId,
    required File file,
    Object? storageProvider,
    void Function(double progress)? onProgress,
  }) async {
    if (file.lengthSync() > AdminContentDataSource.maxImageBytes) {
      throw const Failure(
        FailureCode.validation,
        debugDetail:
            'THUMBNAIL_TOO_LARGE: images must stay under the 5MB placeholder '
            'ceiling (mirrors storage.rules; pending Teacher confirmation).',
      );
    }
    final lower = file.path.toLowerCase();
    final isImage = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
    if (!isImage) {
      throw const Failure(
        FailureCode.validation,
        debugDetail: 'Thumbnails must be jpg/png/webp images.',
      );
    }
    final gateway = await _gatewayFor(storageProvider);
    final stored = await gateway.upload(
      lectureId: lectureId,
      resourceId: resourceId,
      file: file,
      contentTypeOverride: 'image/${lower.endsWith('.png') ? 'png' : lower.endsWith('.webp') ? 'webp' : 'jpeg'}',
      onProgress: onProgress,
    );
    await dataSource.updateResourceDoc(resourceId, {
      'thumbnail': stored.storagePath,
      'thumbnail_storage_provider': stored.provider.wireValue,
    });
    return stored.storagePath;
  }

  @override
  Future<void> setResourceVisibility(
          {required String resourceId, required bool visible}) =>
      dataSource.updateResourceDoc(resourceId, {
        'is_visible': visible,
        'visibility': visible,
      });

  @override
  Future<void> archiveResource(String resourceId) {
    return dataSource.updateResourceDoc(resourceId, {
      'is_deleted': true,
      'is_visible': false,
      'visibility': false,
    });
  }

  @override
  Future<void> restoreResource(String resourceId) =>
      dataSource.restoreResource(resourceId);

  @override
  Future<void> reorderResources(List<AdminLectureResource> ordered) {
    return _reorderAll(
      ordered.map((r) => r.id).toList(),
      dataSource.reorderResources,
    );
  }

  // ---- Archive System (Part B) ----

  @override
  Stream<List<AdminSection>> watchArchivedSections(String subjectId) =>
      dataSource.watchArchivedSections(subjectId);

  @override
  Stream<List<ArchivedLecture>> watchArchivedLectures(String subjectId) =>
      dataSource.watchArchivedLectures(subjectId);

  @override
  Stream<List<AdminLectureResource>> watchArchivedResources(
          String lectureId) =>
      dataSource.watchArchivedResources(lectureId);

  @override
  Future<void> restoreSection(AdminSection section) =>
      dataSource.restoreSection(section.id);

  /// Maps list positions to dense display_order values 1..n and pushes them
  /// through one atomic batched write.
  Future<void> _reorderAll(
    List<String> ids,
    Future<void> Function(List<({String id, int displayOrder})>) push,
  ) {
    return push(List.generate(
      ids.length,
      (i) => (id: ids[i], displayOrder: i + 1),
    ));
  }

  String? _contentTypeFor(File file) {
    final lower = file.path.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.zip')) return 'application/zip';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (lower.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    // Let Storage infer anything else (storage.rules still gates types).
    return null;
  }
}
