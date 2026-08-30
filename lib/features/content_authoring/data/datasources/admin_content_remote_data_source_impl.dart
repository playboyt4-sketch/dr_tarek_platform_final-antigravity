import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../lecture/domain/entities/lecture.dart';
import '../../../lecture/domain/entities/lecture_resource.dart'
    show LectureResourceType;
import '../../domain/entities/admin_content_entities.dart';
import 'admin_content_data_source.dart';

/// Firestore access for staff content authoring.
/// All writes land on collections governed by firestore.rules staff clauses;
/// file bytes move through ResourceStorageGateway implementations
/// (dual-provider, FINAL_DECISIONS §15).
///
/// Audit convention (functions/src/index.ts contentAuditTrigger): every
/// document carries created_by/updated_by so the server-side trigger can
/// attribute the write in admin_audit_log (Master Architecture §7).
class AdminContentRemoteDataSourceImpl implements AdminContentDataSource {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  AdminContentRemoteDataSourceImpl({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance;

  String get _actorId => auth.currentUser?.uid ?? 'unknown_staff';

  Map<String, dynamic> get _createStamp => {
        'created_at': FieldValue.serverTimestamp(),
        'created_by': _actorId,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': _actorId,
      };

  // ---- Subjects (picker) ----
  @override
  Future<List<({String id, String title})>> listSubjects() async {
    final snap = await firestore
        .collection('subjects')
        .where('is_deleted', isEqualTo: false)
        .orderBy('display_order')
        .get();
    return snap.docs
        .map((d) => (
              id: d.id,
              title: (d.data()['title'] as String?) ?? d.id,
            ))
        .toList();
  }

  // ---- Sections ----
  @override
  Stream<List<AdminSection>> watchSections(String subjectId) {
    return firestore
        .collection('subject_sections')
        .where('subject_id', isEqualTo: subjectId)
        .where('is_deleted', isEqualTo: false)
        .orderBy('display_order')
        .snapshots()
        .map((s) => s.docs.map(_sectionFrom).toList());
  }

  @override
  Stream<List<AdminSection>> watchArchivedSections(String subjectId) {
    return firestore
        .collection('subject_sections')
        .where('subject_id', isEqualTo: subjectId)
        .where('is_deleted', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map(_sectionFrom).toList());
  }

  AdminSection _sectionFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return AdminSection(
      id: doc.id,
      subjectId: d['subject_id'] as String? ?? '',
      sectionKey: d['section_key'] as String?,
      isSystemSection: d['is_system_section'] as bool? ?? false,
      title: d['title'] as String? ?? '',
      displayOrder: (d['display_order'] as num?)?.toInt() ?? 0,
      isVisible: d['is_visible'] as bool? ?? false,
      deletedAt: (d['deleted_at'] as Timestamp?)?.toDate(),
      deletedBy: d['deleted_by'] as String?,
    );
  }

  @override
  Future<String> createSection({
    required String subjectId,
    required String title,
    required bool isVisible,
    required int displayOrder,
  }) async {
    final ref = firestore.collection('subject_sections').doc();
    await ref.set({
      'subject_id': subjectId,
      'section_key': null, // custom sections never carry a system key
      'is_system_section': false,
      'title': title,
      'display_order': displayOrder,
      'is_visible': isVisible,
      'is_deleted': false,
      ..._createStamp,
    });
    return ref.id;
  }

  @override
  Future<void> updateSection({
    required String sectionId,
    required String title,
    required bool isVisible,
  }) async {
    await firestore.collection('subject_sections').doc(sectionId).update({
      'title': title,
      'is_visible': isVisible,
      // section_key / is_system_section are NEVER written here (Feature 03).
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': _actorId,
    });
  }

  /// Atomically rewrites display_order for every affected section.
  @override
  Future<void> reorderSections(
      List<({String id, int displayOrder})> order) async {
    final batch = firestore.batch();
    for (final item in order) {
      batch.update(
        firestore.collection('subject_sections').doc(item.id),
        {
          'display_order': item.displayOrder,
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': _actorId,
        },
      );
    }
    await batch.commit();
  }

  @override
  Future<void> deleteSection(String sectionId) {
    return firestore.collection('subject_sections').doc(sectionId).delete();
  }

  @override
  Future<void> restoreSection(String sectionId) async {
    await firestore.collection('subject_sections').doc(sectionId).update({
      'is_deleted': false,
      'deleted_at': null,
      'deleted_by': null,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': _actorId,
    });
  }

  // ---- Lectures ----
  @override
  Stream<List<Lecture>> watchLectures(String sectionId) {
    return firestore
        .collection('lectures')
        .where('section_id', isEqualTo: sectionId)
        .where('is_deleted', isEqualTo: false)
        .orderBy('display_order')
        .snapshots()
        .map((s) => s.docs.map(_lectureFrom).toList());
  }

  @override
  Stream<List<ArchivedLecture>> watchArchivedLectures(String subjectId) {
    return firestore
        .collection('lectures')
        .where('subject_id', isEqualTo: subjectId)
        .where('is_deleted', isEqualTo: true)
        .snapshots()
        .map((s) => s.docs.map(_archivedLectureFrom).toList());
  }

  ArchivedLecture _archivedLectureFrom(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return ArchivedLecture(
      id: doc.id,
      subjectId: data['subject_id'] as String? ?? '',
      sectionId: data['section_id'] as String? ?? '',
      title: data['title'] as String? ?? '',
      statusAtArchive: switch (data['status']) {
        'published' => LectureStatus.published,
        'archived' => LectureStatus.archived,
        _ => LectureStatus.draft,
      },
      deletedAt: (data['deleted_at'] as Timestamp?)?.toDate(),
      deletedBy: data['deleted_by'] as String?,
    );
  }

  Lecture _lectureFrom(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Lecture(
      id: doc.id,
      sectionId: data['section_id'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
      publishDate: (data['publish_date'] as Timestamp?)?.toDate(),
      status: switch (data['status']) {
        'published' => LectureStatus.published,
        'archived' => LectureStatus.archived,
        _ => LectureStatus.draft,
      },
      publicFreeEnabled: data['public_free_enabled'] as bool? ?? false,
      publicFreePreviewMinutes:
          (data['public_free_preview_minutes'] as num?)?.toInt(),
    );
  }

  @override
  Future<String> createLecture({
    required String subjectId,
    required String sectionId,
    required String title,
    required String description,
    required int displayOrder,
    DateTime? publishDate,
    bool publicFreeEnabled = false,
    int? publicFreePreviewMinutes,
  }) async {
    final ref = firestore.collection('lectures').doc();
    await ref.set({
      // subject_id is REQUIRED: the student-facing getLectureResources
      // callable resolves subscriptions from lecture.subject_id.
      'subject_id': subjectId,
      'section_id': sectionId,
      'title': title,
      'description': description,
      'display_order': displayOrder,
      'publish_date':
          publishDate == null ? null : Timestamp.fromDate(publishDate),
      'status': 'draft',
      'is_deleted': false,
      // FINAL_DECISIONS §11 per-lecture Public Free control.
      'public_free_enabled': publicFreeEnabled,
      'public_free_preview_minutes': publicFreePreviewMinutes,
      ..._createStamp,
    });
    return ref.id;
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
  }) async {
    await firestore.collection('lectures').doc(lectureId).update({
      'title': title,
      'description': description,
      'display_order': displayOrder,
      if (publishDate != null) 'publish_date': Timestamp.fromDate(publishDate),
      // FINAL_DECISIONS §11 per-lecture Public Free control.
      'public_free_enabled': ?publicFreeEnabled,
      'public_free_preview_minutes': ?publicFreePreviewMinutes,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': _actorId,
    });
  }

  @override
  Future<void> setLectureStatus({
    required String lectureId,
    required String status,
  }) async {
    await firestore.collection('lectures').doc(lectureId).update({
      'status': status,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': _actorId,
    });
  }

  @override
  Future<void> archiveLecture(String lectureId) async {
    await firestore.collection('lectures').doc(lectureId).update({
      'is_deleted': true,
      'status': 'archived',
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': _actorId,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': _actorId,
    });
  }

  @override
  Future<void> restoreLecture(String lectureId) async {
    await firestore.collection('lectures').doc(lectureId).update({
      'is_deleted': false,
      'deleted_at': null,
      'deleted_by': null,
      // Restored lectures come back as DRAFTS — never silently live.
      'status': 'draft',
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': _actorId,
    });
  }

  @override
  Future<int> countActiveLectures(String sectionId) async {
    final snap = await firestore
        .collection('lectures')
        .where('section_id', isEqualTo: sectionId)
        .where('is_deleted', isEqualTo: false)
        .limit(1)
        .get();
    return snap.size;
  }

  @override
  Future<void> reorderLectures(
      List<({String id, int displayOrder})> order) async {
    final batch = firestore.batch();
    for (final item in order) {
      batch.update(
        firestore.collection('lectures').doc(item.id),
        {
          'display_order': item.displayOrder,
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': _actorId,
        },
      );
    }
    await batch.commit();
  }

  // ---- Resources ----
  @override
  Stream<List<AdminLectureResource>> watchResources(String lectureId) {
    return firestore
        .collection('lecture_resources')
        .where('lecture_id', isEqualTo: lectureId)
        .where('is_deleted', isEqualTo: false)
        .orderBy('display_order')
        .snapshots()
        .map((s) => s.docs.map(_resourceFrom).toList());
  }

  @override
  Stream<List<AdminLectureResource>> watchArchivedResources(String lectureId) {
    return firestore
        .collection('lecture_resources')
        .where('lecture_id', isEqualTo: lectureId)
        .where('is_deleted', isEqualTo: true)
        .orderBy('display_order')
        .snapshots()
        .map((s) => s.docs.map(_resourceFrom).toList());
  }

  AdminLectureResource _resourceFrom(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return AdminLectureResource(
      id: doc.id,
      lectureId: d['lecture_id'] as String? ?? '',
      resourceType: switch (d['resource_type']) {
        'video' => LectureResourceType.video,
        'pdf' => LectureResourceType.pdf,
        'attachment' => LectureResourceType.attachment,
        _ => LectureResourceType.externalLink,
      },
      title: ((d['title'] ?? d['resource_title']) as String?) ?? '',
      displayOrder: (d['display_order'] as num?)?.toInt() ?? 0,
      bunnyVideoId: d['bunny_video_id'] as String?,
      storagePath: d['storage_path'] as String?,
      storageProvider:
          ResourceStorageProvider.fromWire(d['storage_provider'] as String?),
      thumbnailProvider: ResourceStorageProvider.fromWire(
          d['thumbnail_storage_provider'] as String?),
      externalUrl: d['resource_url'] as String?,
      thumbnail: d['thumbnail'] as String?,
      duration: (d['duration'] as num?)?.toInt(),
      isVisible: (d['is_visible'] ?? d['visibility']) as bool? ?? false,
      isDeleted: d['is_deleted'] as bool? ?? false,
      deletedAt: (d['deleted_at'] as Timestamp?)?.toDate(),
      deletedBy: d['deleted_by'] as String?,
    );
  }

  @override
  Future<void> setResourceDoc({
    required String resourceId,
    required Map<String, dynamic> fields,
  }) {
    return firestore
        .collection('lecture_resources')
        .doc(resourceId)
        .set({...fields, ..._createStamp});
  }

  @override
  Future<void> updateResourceDoc(
      String resourceId, Map<String, dynamic> fields) async {
    await firestore.collection('lecture_resources').doc(resourceId).update({
      ...fields,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': _actorId,
    });
  }

  @override
  Future<void> reorderResources(
      List<({String id, int displayOrder})> order) async {
    final batch = firestore.batch();
    for (final item in order) {
      batch.update(
        firestore.collection('lecture_resources').doc(item.id),
        {
          'display_order': item.displayOrder,
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': _actorId,
        },
      );
    }
    await batch.commit();
  }

  @override
  Future<void> restoreResource(String resourceId) async {
    await firestore.collection('lecture_resources').doc(resourceId).update({
      'is_deleted': false,
      'deleted_at': null,
      'deleted_by': null,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': _actorId,
    });
  }
}

/// Dual-provider wire value per FINAL_DECISIONS §15 / 05 Database v1.9:
/// pdf/attachment documents always carry storage_provider; video stays
/// implicitly Bunny with NO field; thumbnails carry their own key.
String? _storageProviderWire(AdminLectureResource r) {
  final isFileBacked = r.resourceType == LectureResourceType.pdf ||
      r.resourceType == LectureResourceType.attachment;
  if (!isFileBacked) return null;
  return (r.storageProvider ?? ResourceStorageProvider.firebase).wireValue;
}

/// Shared field mapping for resource metadata documents. Both visibility
/// spellings are kept in sync: `is_visible` is what the student-facing
/// getLectureResources callable filters on; `visibility` mirrors it for
/// the legacy client field name (05 Database §16 lecture_resources).
Map<String, dynamic> adminResourceFields(AdminLectureResource r) {
  return {
    'lecture_id': r.lectureId,
    'resource_type': switch (r.resourceType) {
      LectureResourceType.video => 'video',
      LectureResourceType.pdf => 'pdf',
      LectureResourceType.attachment => 'attachment',
      LectureResourceType.externalLink => 'external_link',
    },
    'title': r.title,
    'display_order': r.displayOrder,
    'bunny_video_id': r.bunnyVideoId,
    'storage_path': r.storagePath,
    // Null-aware elements keep video docs free of any provider field.
    'storage_provider': ?_storageProviderWire(r),
    'thumbnail_storage_provider': ?r.thumbnailProvider?.wireValue,
    // external_link keeps its target in resource_url; media types never do.
    'resource_url': r.resourceType == LectureResourceType.externalLink
        ? r.externalUrl ?? ''
        : '',
    'thumbnail': r.thumbnail,
    'duration': r.duration,
    'is_visible': r.isVisible,
    'visibility': r.isVisible,
    'is_deleted': r.isDeleted,
  };
}
