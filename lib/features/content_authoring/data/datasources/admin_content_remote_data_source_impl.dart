import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../admin/domain/admin_grades.dart'
    show normalizeAdminGradeKey;
import '../../../lecture/domain/entities/lecture.dart';
import '../../../lecture/domain/entities/lecture_resource.dart'
    show LectureResourceType;
import '../../domain/entities/admin_content_entities.dart';
import 'admin_content_data_source.dart';

/// Phase 1 Guest preview field mapping (FINAL_DECISIONS §11).
/// Canonical keys first (`guest_enabled` / `guest_preview_minutes`);
/// bounded fallback to legacy `public_free_*` keys for lecture documents
/// not yet covered by the data migration.
/// TODO(PHASE2C): drop the legacy keys once Dashboard + migration cover all docs.
({bool guestEnabled, int? guestPreviewMinutes}) guestPreviewFromLectureMap(
    Map<String, dynamic> data) {
  return (
    guestEnabled: (data['guest_enabled'] as bool?) ??
        (data['public_free_enabled'] as bool?) ??
        false,
    guestPreviewMinutes: ((data['guest_preview_minutes'] as num?) ??
            (data['public_free_preview_minutes'] as num?))
        ?.toInt(),
  );
}

/// Canonical denormalized `first_video` projection for one video resource.
///
/// Mirrors the Dashboard selector and the server's
/// `firstVideoFieldsFromResources`: identity + display metadata only. The
/// ADR-010 `bunny_library_id` is additive (null for legacy rows) so the
/// fast-lane hint never diverges from the authoritative resource association.
Map<String, Object?> lectureFirstVideoFields({
  required String resourceId,
  required String bunnyVideoId,
  String? bunnyLibraryId,
  String? title,
  int displayOrder = 0,
}) {
  return <String, Object?>{
    'resource_id': resourceId,
    'bunny_video_id': bunnyVideoId,
    'bunny_library_id': bunnyLibraryId,
    'title': title,
    'display_order': displayOrder,
    'thumbnail_path': null,
    'thumbnail_storage_provider': null,
  };
}

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

  /// ADR-010: server-verified library association. Lazy so unit tests that
  /// never touch a video resource do not need a Functions instance.
  final FirebaseFunctions? _functionsOverride;

  FirebaseFunctions get _functions =>
      _functionsOverride ?? FirebaseFunctions.instance;

  /// Server default Bunny library (non-secret display value). New video
  /// resources are associated with it unless the row already has one.
  ///
  /// Overridable per build so a non-production environment names its own
  /// library instead of inheriting production `736742`:
  ///   flutter build apk --dart-define=BUNNY_DEFAULT_LIBRARY_ID=780700
  /// The server still verifies the association and remains the only
  /// authority that resolves credentials.
  static const String _defaultBunnyLibraryId = String.fromEnvironment(
    'BUNNY_DEFAULT_LIBRARY_ID',
    defaultValue: '736742',
  );

  AdminContentRemoteDataSourceImpl({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  })  : firestore = firestore ?? FirebaseFirestore.instance,
        auth = auth ?? FirebaseAuth.instance,
        _functionsOverride = functions;

  String get _actorId => auth.currentUser?.uid ?? 'unknown_staff';

  /// ADR-010: verify + persist a video row's library association through the
  /// trusted callables. `bunny_library_id` is server-owned (Firestore Rules
  /// deny client writes), so a video row stays PENDING — and unplayable —
  /// until this succeeds. Failures are surfaced, never silently downgraded to
  /// the legacy default-library path.
  Future<void> _associateVideoResource({
    required String resourceId,
    required String lectureId,
    required String? videoId,
    required String? resourceType,
    String? storedLibraryId,
    bool replaceVideo = false,
  }) async {
    final String? normalizedVideoId = videoId?.trim();
    if (normalizedVideoId == null || normalizedVideoId.isEmpty) return;
    if (resourceType != null && resourceType != 'video') return;
    final String? stored = storedLibraryId?.trim();
    final String libraryId =
        (stored != null && stored.isNotEmpty) ? stored : _defaultBunnyLibraryId;
    try {
      final HttpsCallableResult<dynamic> validation =
          await _functions.httpsCallable('validateBunnyVideoAssociation').call(
        <String, dynamic>{
          'libraryId': libraryId,
          'videoId': normalizedVideoId,
          'resourceId': resourceId,
          'lectureId': lectureId,
        },
      );
      final Object? raw = validation.data;
      final Map<String, dynamic> payload =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final Object? receipt = payload['receipt'];
      if (payload['status'] != 'verified' || receipt == null) {
        throw Exception(
          'Video verification failed (${payload['reason'] ?? 'unavailable'}).',
        );
      }
      await _functions.httpsCallable('associateBunnyVideoToLibrary').call(
        <String, dynamic>{
          'resourceId': resourceId,
          'lectureId': lectureId,
          'libraryId': libraryId,
          'videoId': normalizedVideoId,
          'replaceVideo': replaceVideo,
          'receipt': receipt,
        },
      );
    } on FirebaseFunctionsException catch (error) {
      throw Exception(
        error.message ?? 'The verified library association was not saved.',
      );
    }
  }

  Map<String, dynamic> get _createStamp => {
        'created_at': FieldValue.serverTimestamp(),
        'created_by': _actorId,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': _actorId,
      };

  /// Resolves the owning subject of a lecture for the `subject_id`
  /// denormalization on `lecture_resources` rows (required by the
  /// `hasSubjectAccess` Firestore gate). Returns null when the lecture
  /// or its subject is missing — callers then leave the field untouched.
  Future<String?> _subjectIdForLecture(String lectureId) async {
    final snap =
        await firestore.collection('lectures').doc(lectureId).get();
    final subjectId = snap.data()?['subject_id'] as String?;
    return (subjectId == null || subjectId.isEmpty) ? null : subjectId;
  }

  /// Canonical first-video sync shared by every resource mutation below,
  /// mirroring the Dashboard `SubjectDetailsController` writer sync:
  /// eligible = `video` + visible + not soft-deleted + non-empty Bunny id;
  /// winner = lowest `display_order` (document id breaks ties); null when
  /// nothing is eligible. The denormalized `first_video` map on
  /// `lectures/{lectureId}` keeps student listings + playback identical
  /// no matter which authoring surface wrote the resource.
  Future<void> _syncLectureFirstVideo(String lectureId) async {
    final snap = await firestore
        .collection('lecture_resources')
        .where('lecture_id', isEqualTo: lectureId)
        .get();
    String? winnerId;
    String? winnerTitle;
    String? winnerBunnyId;
    String? winnerLibraryId;
    int? winnerOrder;
    for (final doc in snap.docs) {
      final d = doc.data();
      if (d['is_deleted'] == true) continue;
      if ((d['is_visible'] ?? d['visibility']) != true) continue;
      if (d['resource_type'] != 'video') continue;
      final bunnyId = (d['bunny_video_id'] as String?)?.trim();
      if (bunnyId == null || bunnyId.isEmpty) continue;
      final order = (d['display_order'] as num?)?.toInt() ?? 0;
      if (winnerId == null ||
          order < winnerOrder! ||
          (order == winnerOrder && doc.id.compareTo(winnerId) < 0)) {
        winnerId = doc.id;
        winnerTitle = ((d['title'] ?? d['resource_title']) as String?) ?? '';
        winnerBunnyId = bunnyId;
        winnerLibraryId = (d['bunny_library_id'] as String?)?.trim();
        winnerOrder = order;
      }
    }
    await firestore.collection('lectures').doc(lectureId).update({
      'first_video': winnerId == null
          ? null
          : lectureFirstVideoFields(
              resourceId: winnerId,
              bunnyVideoId: winnerBunnyId!,
              bunnyLibraryId: winnerLibraryId,
              title: winnerTitle,
              displayOrder: winnerOrder ?? 0,
            ),
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': _actorId,
    });
  }

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

  /// Soft-deletes a custom section (archived, restorable via
  /// [restoreSection] and visible in `watchArchivedSections`). A hard
  /// `.delete()` is denied by `firestore.rules` (`allow delete: if false`)
  /// and would hide the section from the archive forever. System sections
  /// stay protected server-side: the rules reject `is_deleted: true` on
  /// them, so this update can only ever archive custom sections.
  @override
  Future<void> deleteSection(String sectionId) {
    return firestore.collection('subject_sections').doc(sectionId).update({
      'is_deleted': true,
      'is_visible': false,
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by': _actorId,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': _actorId,
    });
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
    final preview = guestPreviewFromLectureMap(data);
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
      guestEnabled: preview.guestEnabled,
      guestPreviewMinutes: preview.guestPreviewMinutes,
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
    bool guestEnabled = false,
    int? guestPreviewMinutes,
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
      // Denormalized first-video pointer (Dashboard writer sync keeps it
      // current on every resource mutation); null until a visible video
      // resource exists.
      'first_video': null,
      // FINAL_DECISIONS §11 per-lecture Guest preview control.
      'guest_enabled': guestEnabled,
      'guest_preview_minutes': guestPreviewMinutes,
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
    bool? guestEnabled,
    int? guestPreviewMinutes,
  }) async {
    await firestore.collection('lectures').doc(lectureId).update({
      'title': title,
      'description': description,
      'display_order': displayOrder,
      if (publishDate != null) 'publish_date': Timestamp.fromDate(publishDate),
      // FINAL_DECISIONS §11 per-lecture Guest preview control.
      'guest_enabled': ?guestEnabled,
      'guest_preview_minutes': ?guestPreviewMinutes,
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

  // ---- Lecture Access (V1 approved backend: lecture_access_grants) ----
  @override
  Future<String?> getSubjectGrade(String subjectId) async {
    final doc =
        await firestore.collection('subjects').doc(subjectId).get();
    final grade = doc.data()?['grade'] as String?;
    return (grade == null || grade.isEmpty) ? null : grade;
  }

  @override
  Stream<List<LectureStudent>> watchStudents({String? gradeKey}) {
    // Single-equality query (no composite index needed); grade scoping
    // and name ordering are applied client-side below.
    return firestore
        .collection('users')
        .where('role', isEqualTo: 'student')
        .snapshots()
        .map((snap) {
      final students = <LectureStudent>[];
      // Both sides normalized to canonical grade_one..grade_four so
      // legacy digit spellings (grade_3) and canonical values
      // (grade_three) match regardless of which side carries which.
      final normalizedFilter = normalizeAdminGradeKey(gradeKey);
      for (final doc in snap.docs) {
        final data = doc.data();
        final grade = data['grade'] as String?;
        if (gradeKey != null &&
            normalizeAdminGradeKey(grade) != normalizedFilter) {
          continue;
        }
        students.add(LectureStudent(
          id: doc.id,
          name: ((data['full_name'] as String?)?.trim().isEmpty ?? true)
              ? doc.id
              : (data['full_name'] as String).trim(),
          grade: grade,
        ));
      }
      students.sort((a, b) => a.name.compareTo(b.name));
      return students;
    });
  }

  @override
  Stream<List<LectureAccessGrant>> watchLectureAccessGrants(
      String lectureId) {
    return firestore
        .collection('lecture_access_grants')
        .where('lecture_id', isEqualTo: lectureId)
        .snapshots()
        .map((snap) => snap.docs
            // Soft-deleted grants carry no override (treated as missing,
            // mirroring server enforcement).
            .where((doc) => doc.data()['is_deleted'] != true)
            .map((doc) {
              final data = doc.data();
              return LectureAccessGrant(
                lectureId:
                    (data['lecture_id'] as String?) ?? lectureId,
                studentId: (data['student_id'] as String?) ?? '',
                allowed: data['allowed'] as bool? ?? true,
                isDeleted: data['is_deleted'] as bool? ?? false,
                deletedAt: (data['deleted_at'] as Timestamp?)?.toDate(),
                deletedBy: data['deleted_by'] as String?,
              );
            }).toList());
  }

  @override
  Future<void> saveLectureAccess(List<LectureAccessGrant> grants) async {
    if (grants.isEmpty) return;
    final lectureId = grants.first.lectureId;
    // One read: preserve created_* on existing grants so repeats and
    // updates never reset creation audit info.
    final existing = await firestore
        .collection('lecture_access_grants')
        .where('lecture_id', isEqualTo: lectureId)
        .get();
    final createdAtById = <String, Object?>{};
    final createdByById = <String, Object?>{};
    for (final doc in existing.docs) {
      createdAtById[doc.id] = doc.data()['created_at'];
      createdByById[doc.id] = doc.data()['created_by'];
    }
    // One batch: deterministic ids make duplicates structurally
    // impossible and the save repeat-safe.
    final batch = firestore.batch();
    for (final grant in grants) {
      final id = lectureAccessGrantDocId(grant.lectureId, grant.studentId);
      final ref = firestore.collection('lecture_access_grants').doc(id);
      final write = lectureAccessGrantWrite(
        grant: grant,
        existingCreatedAt: createdAtById[id],
        existingCreatedBy: createdByById[id],
        hadExistingDoc: createdAtById.containsKey(id),
        actorId: _actorId,
        serverTimestamp: FieldValue.serverTimestamp(),
      );
      batch.set(ref, write.fields,
          write.isNew ? null : SetOptions(merge: true));
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
  }) async {
    final payload = Map<String, dynamic>.from(fields);
    // Backfill the owning subject so the `hasSubjectAccess` gate can
    // resolve this row (the form entity only carries the lecture id).
    if ((payload['subject_id'] as String?)?.isNotEmpty != true) {
      final lectureId = payload['lecture_id'] as String?;
      if (lectureId != null && lectureId.isNotEmpty) {
        final subjectId = await _subjectIdForLecture(lectureId);
        if (subjectId != null) payload['subject_id'] = subjectId;
      }
    }
    // ADR-010: `bunny_library_id` is server-owned. A client value is dropped
    // here (the server writes the verified one), so rules stay enforce-only.
    payload.remove('bunny_library_id');
    await firestore
        .collection('lecture_resources')
        .doc(resourceId)
        .set({...payload, ..._createStamp});
    final lectureId = payload['lecture_id'] as String?;
    if (lectureId != null && lectureId.isNotEmpty) {
      await _syncLectureFirstVideo(lectureId);
    }
    if (lectureId != null && lectureId.isNotEmpty) {
      await _associateVideoResource(
        resourceId: resourceId,
        lectureId: lectureId,
        videoId: payload['bunny_video_id'] as String?,
        resourceType: payload['resource_type'] as String?,
      );
    }
  }

  @override
  Future<void> updateResourceDoc(
      String resourceId, Map<String, dynamic> fields) async {
    final payload = Map<String, dynamic>.from(fields);
    final existing = await firestore
        .collection('lecture_resources')
        .doc(resourceId)
        .get();
    final stored = existing.data();
    // Backfill `subject_id` on legacy rows that predate the field so the
    // `hasSubjectAccess` gate resolves them after any edit.
    if (!payload.containsKey('subject_id') &&
        ((stored?['subject_id'] as String?)?.isNotEmpty != true)) {
      final lectureId = (payload['lecture_id'] ?? stored?['lecture_id'])
          as String?;
      if (lectureId != null && lectureId.isNotEmpty) {
        final subjectId = await _subjectIdForLecture(lectureId);
        if (subjectId != null) payload['subject_id'] = subjectId;
      }
    }
    // ADR-010: the association is server-owned; a verified row's Video ID may
    // only change through the association callable (rules reject a direct
    // pointer swap), so an edited Video ID is deferred to the server below.
    payload.remove('bunny_library_id');
    final String? storedLibraryId =
        (stored?['bunny_library_id'] as String?)?.trim();
    final String? incomingVideoId = payload['bunny_video_id'] as String?;
    if (incomingVideoId != null &&
        storedLibraryId != null &&
        storedLibraryId.isNotEmpty) {
      payload.remove('bunny_video_id');
    }
    await firestore.collection('lecture_resources').doc(resourceId).update({
      ...payload,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': _actorId,
    });
    final lectureId =
        (payload['lecture_id'] ?? stored?['lecture_id']) as String?;
    if (lectureId != null && lectureId.isNotEmpty) {
      await _syncLectureFirstVideo(lectureId);
      await _associateVideoResource(
        resourceId: resourceId,
        lectureId: lectureId,
        videoId: incomingVideoId,
        resourceType: (payload['resource_type'] ?? stored?['resource_type'])
            as String?,
        storedLibraryId: storedLibraryId,
        replaceVideo: storedLibraryId != null && storedLibraryId.isNotEmpty,
      );
    }
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
    // Display order feeds first-video selection — resync every lecture
    // touched by the reorder.
    final lectureIds = <String>{};
    for (final item in order) {
      final doc = await firestore
          .collection('lecture_resources')
          .doc(item.id)
          .get();
      final lectureId = doc.data()?['lecture_id'] as String?;
      if (lectureId != null && lectureId.isNotEmpty) {
        lectureIds.add(lectureId);
      }
    }
    for (final lectureId in lectureIds) {
      await _syncLectureFirstVideo(lectureId);
    }
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
    final doc = await firestore
        .collection('lecture_resources')
        .doc(resourceId)
        .get();
    final lectureId = doc.data()?['lecture_id'] as String?;
    if (lectureId != null && lectureId.isNotEmpty) {
      await _syncLectureFirstVideo(lectureId);
    }
  }
}

/// Dual-provider wire value per FINAL_DECISIONS §15 / 05 Database v1.9:/// pdf/attachment documents always carry storage_provider; video stays
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

/// One batched grant write: document fields plus whether the target is
/// new (full set) or existing (merge, preserving created_*).
typedef LectureAccessGrantWrite = ({
  Map<String, Object?> fields,
  bool isNew,
});

/// Pure field mapping for `lecture_access_grants` documents (audit
/// convention: created_at/by set once, updated_at/by on every write;
/// soft-delete audit fields included for consistency — clients always
/// write active state, revocation is `allowed: false`, never a delete).
/// Extracted pure so the merge/audit behavior is unit-testable without
/// Firestore; [serverTimestamp] is injected by the caller.
LectureAccessGrantWrite lectureAccessGrantWrite({
  required LectureAccessGrant grant,
  required Object? existingCreatedAt,
  required Object? existingCreatedBy,
  required bool hadExistingDoc,
  required String actorId,
  required Object serverTimestamp,
}) {
  final Map<String, Object?> fields = {
    'lecture_id': grant.lectureId,
    'student_id': grant.studentId,
    'allowed': grant.allowed,
    'updated_at': serverTimestamp,
    'updated_by': actorId,
    // Clients never soft-delete: revocation is allowed=false.
    'is_deleted': false,
    'deleted_at': null,
    'deleted_by': null,
  };
  if (hadExistingDoc) {
    fields['created_at'] = existingCreatedAt ?? serverTimestamp;
    fields['created_by'] = existingCreatedBy ?? actorId;
    return (fields: fields, isNew: false);
  }
  fields['created_at'] = serverTimestamp;
  fields['created_by'] = actorId;
  return (fields: fields, isNew: true);
}
