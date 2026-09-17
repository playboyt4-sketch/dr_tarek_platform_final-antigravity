import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../applications/presentation/providers/application_decision_provider.dart'
    show DecisionFailure;

/// Data layer for the Dashboard Subject Details page.
///
/// Follows the established dashboard convention: Riverpod providers own
/// the Firestore queries (widgets only `watch` state and dispatch to
/// [SubjectDetailsController]). No Firestore access from widgets.
///
/// Content-tab model — product-level categories backed ONLY by the
/// canonical Section Type (05 Database §"Section Type" + §9 Subject
/// Sections: system `explanation` / `revision` / `final_review`, custom
/// sections carry a `null` key and are distinguished by title):
/// - Lectures tab → `explanation` system sections (main teaching);
/// - Revisions tab → `revision` system sections (separate revision
///   sessions, not lecture sections with a revision flag);
/// - Final tab → `final_review` system sections (pre-exam sessions);
/// - Online tab → custom sections representing Online Sessions
///   (recordings of externally conducted lessons, uploaded to Bunny CDN;
///   the lecture stores the Bunny video id like any normal lecture).
///   Online has no system key and no dedicated entity/collection — it is
///   a normal custom section matched by [isOnlineSection]. The dashboard
///   creates NO meetings: no Google Meet, live class, screen sharing, or
///   virtual classroom exists in V1.

/// Live subject header data.
class SubjectDetails {
  final String id;
  final String title;
  final bool isVisible;

  /// Existing thumbnail/cover field (dashboard `cover_url` convention).
  final String coverUrl;

  const SubjectDetails({
    required this.id,
    required this.title,
    required this.isVisible,
    this.coverUrl = '',
  });

  factory SubjectDetails.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};
    final String title = (data['title'] as String?)?.trim() ?? '';
    final Object? visible = data['is_visible'] ?? data['is_active'];
    return SubjectDetails(
      id: doc.id,
      title: title.isEmpty ? doc.id : title,
      isVisible: visible is bool ? visible : true,
      coverUrl: (data['cover_url'] as String?)?.trim() ?? '',
    );
  }
}

/// One content section inside the subject.
class SubjectSection {
  final String id;
  final String? sectionKey;

  /// Approved `is_system_section` flag. Documents written before the flag
  /// was populated fall back to key inference (system iff the key is one
  /// of the three canonical system keys).
  final bool isSystemSection;
  final String title;
  final int displayOrder;

  const SubjectSection({
    required this.id,
    required this.sectionKey,
    required this.isSystemSection,
    required this.title,
    required this.displayOrder,
  });

  factory SubjectSection.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String? key = data['section_key'] as String?;
    return SubjectSection(
      id: doc.id,
      sectionKey: key,
      isSystemSection: (data['is_system_section'] as bool?) ??
          (key == 'explanation' ||
              key == 'revision' ||
              key == 'final_review'),
      title: (data['title'] as String?)?.trim() ?? doc.id,
      displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One lecture row of the details table.
class SubjectLecture {
  final String id;
  final String title;
  final int displayOrder;
  final String status;

  const SubjectLecture({
    required this.id,
    required this.title,
    required this.displayOrder,
    required this.status,
  });

  factory SubjectLecture.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String title = (data['title'] as String?)?.trim() ?? '';
    return SubjectLecture(
      id: doc.id,
      title: title.isEmpty ? doc.id : title,
      displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
      status: (data['status'] as String?) ?? 'draft',
    );
  }
}

/// One staged resource payload for lecture creation. File-backed types
/// (pdf/attachment) carry picked bytes uploaded on save; video carries
/// a Bunny video id only; external links carry a validated http(s) URL.
/// Wire values (`video`/`pdf`/`attachment`/`external_link`) match the
/// approved `lecture_resources` format.
class NewLectureResource {
  final String type;
  final String title;
  final int displayOrder;
  final String? bunnyVideoId;
  final String? externalUrl;
  final Uint8List? fileBytes;
  final String? fileName;
  final String? contentType;

  const NewLectureResource({
    required this.type,
    required this.title,
    required this.displayOrder,
    this.bunnyVideoId,
    this.externalUrl,
    this.fileBytes,
    this.fileName,
    this.contentType,
  });
}

/// Content tabs of the Subject Details page.
enum SubjectContentTab {
  lectures('Lectures', 'Lecture Name', 'No lectures yet.'),
  revisions('Revisions', 'Revision Name', 'No revisions yet.'),
  finalTab('Final', 'Final Name', 'No final yet.'),
  online('Online', 'Online Name', 'No online sessions yet.');

  final String label;

  /// Middle-column header for the content table. Position and alignment
  /// are identical in all four states; only this semantic label changes.
  final String contentNameLabel;

  /// Empty-state message for the content table. Follows the active tab
  /// exactly like [contentNameLabel]; layout and style are unchanged.
  final String emptyStateLabel;

  const SubjectContentTab(this.label, this.contentNameLabel, this.emptyStateLabel);
}

/// Section keys shown under each tab. System tabs use ONLY the canonical
/// system labels (05 Database §"Section Type": `explanation` / `revision`
/// / `final_review`). The Online tab shows the subject's Online custom
/// section(s) via [isOnlineSection] — never Explanation / Revision /
/// Final Review content, never an aggregate of all sections, and never
/// arbitrary lecture-title matching.
bool sectionVisibleInTab(SubjectSection section, SubjectContentTab tab) {
  switch (tab) {
    case SubjectContentTab.lectures:
      return section.sectionKey == 'explanation';
    case SubjectContentTab.revisions:
      return section.sectionKey == 'revision';
    case SubjectContentTab.finalTab:
      return section.sectionKey == 'final_review';
    case SubjectContentTab.online:
      return isOnlineSection(section);
  }
}

/// Implementation-level key under which earlier dashboard builds persisted
/// Online sections (quick-upload path). It conflicts with the canonical
/// model (custom sections carry a `null` key) and is therefore accepted
/// READ-ONLY so existing data keeps working: records are never renamed,
/// and new Online sections are always created with the canonical
/// representation (`section_key: null`, `is_system_section: false`).
/// See the task implementation report for the stored-vs-canonical detail.
const String legacyOnlineSectionKey = 'online';

/// Whether [section] is the subject's Online custom section.
///
/// - System sections (`explanation` / `revision` / `final_review`) are
///   never Online.
/// - `section_key == 'online'` is existing persisted Online data (legacy
///   implementation key) and is honored as-is — never renamed, never
///   re-written by this matcher.
/// - Any other non-null key (e.g. legacy `center` / `final` artifacts) is
///   never Online.
/// - Canonical custom sections (`null` key) qualify only when their title
///   denotes Online Sessions. Title is the approved discriminator for
///   custom sections (05 Database §9 lists them by name: "Online
///   Sessions", "Important Announcements", …).
bool isOnlineSection(SubjectSection section) {
  switch (section.sectionKey) {
    case 'explanation':
    case 'revision':
    case 'final_review':
      return false;
    case legacyOnlineSectionKey:
      return true;
  }
  if (section.sectionKey != null) return false;
  return _titleIndicatesOnline(section.title);
}

/// Title discriminator for canonical (`null`-key) Online custom sections.
bool _titleIndicatesOnline(String title) {
  final String normalized = title.trim().toLowerCase();
  return normalized.contains('online') ||
      normalized.contains('أونلاين') ||
      normalized.contains('اونلاين') ||
      normalized.contains('أون لاين') ||
      normalized.contains('اون لاين');
}

/// Existing Online section of a subject: the first online-qualifying
/// section by display order, or null when the subject has none yet (the
/// caller then creates the canonical custom section). The existing
/// record — its id, title, order, and visibility — is always preferred;
/// a second section is never created while one exists.
SubjectSection? findOnlineSection(Iterable<SubjectSection> sections) {
  final List<SubjectSection> online =
      sections.where(isOnlineSection).toList(growable: false)
        ..sort((SubjectSection a, SubjectSection b) =>
            a.displayOrder.compareTo(b.displayOrder));
  return online.isEmpty ? null : online.first;
}

/// Live subject header for [subjectId].
final subjectDetailsProvider =
    StreamProvider.family<SubjectDetails, String>((ref, subjectId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('subjects')
      .doc(subjectId)
      .snapshots()
      .map(SubjectDetails.fromDoc);
});

/// Live non-deleted sections of one subject, ordered for display.
final subjectSectionsProvider =
    StreamProvider.family<List<SubjectSection>, String>((ref, subjectId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('subject_sections')
      .where('subject_id', isEqualTo: subjectId)
      .where('is_deleted', isEqualTo: false)
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
    final List<SubjectSection> sections =
        snapshot.docs.map(SubjectSection.fromDoc).toList();
    sections.sort(
        (SubjectSection a, SubjectSection b) =>
            a.displayOrder.compareTo(b.displayOrder));
    return sections;
  });
});

/// Query key for the flattened per-tab lecture list.
typedef TabLecturesQuery = ({String subjectId, SubjectContentTab tab});

/// Flattened lectures of every section visible under [query.tab],
/// ordered by (section display_order, lecture display_order).
/// Combines the section stream with one lecture stream per section so
/// the table watches a single list. Numbering across the flattened
/// list preserves the stored ordering.
final tabLecturesProvider =
    StreamProvider.family<List<SubjectLecture>, TabLecturesQuery>(
        (ref, query) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  late final StreamController<List<SubjectLecture>> controller;
  List<SubjectSection> sections = <SubjectSection>[];
  final Map<String, List<SubjectLecture>> cache = <String, List<SubjectLecture>>{};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      subs = <String,
          StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sectionsSub;

  void emit() {
    final List<SubjectLecture> flat = <SubjectLecture>[];
    final List<SubjectSection> ordered = sections
        .where((SubjectSection s) => sectionVisibleInTab(s, query.tab))
        .toList()
      ..sort((SubjectSection a, SubjectSection b) =>
          a.displayOrder.compareTo(b.displayOrder));
    for (final SubjectSection section in ordered) {
      final List<SubjectLecture> lectures =
          List<SubjectLecture>.from(cache[section.id] ?? const <SubjectLecture>[])
            ..sort((SubjectLecture a, SubjectLecture b) =>
                a.displayOrder.compareTo(b.displayOrder));
      flat.addAll(lectures);
    }
    if (!controller.isClosed) controller.add(List<SubjectLecture>.unmodifiable(flat));
  }

  controller = StreamController<List<SubjectLecture>>(onListen: () {
    sectionsSub = db
        .collection('subject_sections')
        .where('subject_id', isEqualTo: query.subjectId)
        .where('is_deleted', isEqualTo: false)
        .snapshots()
        .listen((QuerySnapshot<Map<String, dynamic>> snap) {
      sections =
          snap.docs.map(SubjectSection.fromDoc).toList(growable: false);
      final Set<String> liveIds =
          sections.map((SubjectSection s) => s.id).toSet();
      for (final String stale in subs.keys.toList()) {
        if (!liveIds.contains(stale)) {
          subs.remove(stale)?.cancel();
          cache.remove(stale);
        }
      }
      for (final SubjectSection section in sections) {
        if (subs.containsKey(section.id)) continue;
        subs[section.id] = db
            .collection('lectures')
            .where('section_id', isEqualTo: section.id)
            .where('is_deleted', isEqualTo: false)
            .snapshots()
            .listen((QuerySnapshot<Map<String, dynamic>> lecturesSnap) {
          cache[section.id] = lecturesSnap.docs
              .map(SubjectLecture.fromDoc)
              .toList(growable: false);
          emit();
        });
      }
      emit();
    });
  });

  ref.onDispose(() async {
    await sectionsSub?.cancel();
    for (final sub in subs.values) {
      await sub.cancel();
    }
    await controller.close();
  });
  return controller.stream;
});

/// Live non-deleted lectures of one section, ordered for display.
final sectionLecturesProvider =
    StreamProvider.family<List<SubjectLecture>, String>((ref, sectionId) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('lectures')
      .where('section_id', isEqualTo: sectionId)
      .where('is_deleted', isEqualTo: false)
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
    final List<SubjectLecture> lectures =
        snapshot.docs.map(SubjectLecture.fromDoc).toList();
    lectures.sort((SubjectLecture a, SubjectLecture b) =>
        a.displayOrder.compareTo(b.displayOrder));
    return lectures;
  });
});

/// Subject/lecture mutations for the details page (toggle, rename,
/// soft-delete). Centralized here so widgets never touch Firestore —
/// the same soft-delete semantics as the mobile content pipeline
/// (`is_deleted: true`; lectures additionally return to `archived`
/// status) and the existing dashboard subject flags.
class SubjectDetailsController {
  final FirebaseFirestore _db;

  const SubjectDetailsController(this._db);

  Future<void> setSubjectVisible(String subjectId, bool visible) {
    return _db.collection('subjects').doc(subjectId).update(
      <String, Object?>{
        'is_visible': visible,
        'updated_at': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> renameSubject(String subjectId, String title) {
    return updateSubject(subjectId, title: title);
  }

  /// Overlay-backed subject edit: updates ONLY the overlay-represented
  /// fields (title, grade, cover). `is_visible` and every other subject
  /// document field are left untouched; lectures/sections/resources are
  /// separate documents and are never affected. Writes go through
  /// Security Rules staff checks (teacher / content-management
  /// delegation) — no permission logic lives in widgets.
  Future<void> updateSubject(
    String subjectId, {
    String? title,
    String? gradeKey,
    String? coverUrl,
  }) {
    final Map<String, Object?> fields = <String, Object?>{
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (title != null) fields['title'] = title;
    if (gradeKey != null) fields['grade'] = gradeKey;
    if (coverUrl != null) fields['cover_url'] = coverUrl;
    return _db.collection('subjects').doc(subjectId).update(fields);
  }

  Future<void> deleteSubject(String subjectId) {
    return _db.collection('subjects').doc(subjectId).update(
      <String, Object?>{
        'is_deleted': true,
        'is_visible': false,
        'updated_at': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> deleteLecture(String lectureId) {
    return _db.collection('lectures').doc(lectureId).update(
      <String, Object?>{
        'is_deleted': true,
        'status': 'archived',
        'updated_at': FieldValue.serverTimestamp(),
      },
    );
  }

  /// Next lecture display order across the tab-visible sections of one
  /// subject (max + 1, minimum 1). The form prefills this and the
  /// teacher may edit it.
  Future<int> nextLectureOrder({
    required String subjectId,
    required SubjectContentTab tab,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> sectionsSnap = await _db
        .collection('subject_sections')
        .where('subject_id', isEqualTo: subjectId)
        .where('is_deleted', isEqualTo: false)
        .get();
    int maxOrder = 0;
    for (final QueryDocumentSnapshot<Map<String, dynamic>> section
        in sectionsSnap.docs) {
      if (!sectionVisibleInTab(
          SubjectSection.fromDoc(section), tab)) {
        continue;
      }
      final QuerySnapshot<Map<String, dynamic>> lecturesSnap = await _db
          .collection('lectures')
          .where('section_id', isEqualTo: section.id)
          .where('is_deleted', isEqualTo: false)
          .get();
      for (final QueryDocumentSnapshot<Map<String, dynamic>> lecture
          in lecturesSnap.docs) {
        final int order =
            (lecture.data()['display_order'] as num?)?.toInt() ?? 0;
        if (order > maxOrder) maxOrder = order;
      }
    }
    return maxOrder + 1;
  }

  /// Uploads PDF/attachment bytes through Firebase Storage under the
  /// approved path convention
  /// `/lecture_resources/{lectureId}/{resourceId}/{fileName}`
  /// (storage.rules: staff-only, 50 MB ceiling). Returns the storage path
  /// recorded on the resource document.
  Future<String> uploadLectureFile({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String lectureId,
    required String resourceId,
  }) async {
    if (bytes.lengthInBytes > 50 * 1024 * 1024) {
      throw DecisionFailure('The file is larger than the 50 MB limit.');
    }
    final String safeName =
        fileName.trim().isEmpty ? 'file' : fileName.trim();
    final String storagePath =
        'lecture_resources/$lectureId/$resourceId/$safeName';
    await FirebaseStorage.instance
        .ref(storagePath)
        .putData(bytes, SettableMetadata(contentType: contentType));
    return storagePath;
  }

  /// Full lecture creation for the Add New Lecture form: resolves the
  /// target section, writes the lecture document, uploads file-backed
  /// resources, then persists resource metadata + access grants in one
  /// batch. Field names mirror the approved mobile content-authoring
  /// wire format (`adminResourceFields`); Guest preview maps to the
  /// existing `public_free_enabled` / `public_free_preview_minutes`
  /// fields (legacy names preserved — no migration performed here).
  ///
  /// Publication: [publishNow] writes `published` immediately;
  /// otherwise the lecture stays `draft` with [publishDateTime] recorded
  /// for the scheduled auto-publish path (server authority decides).
  Future<String> createLectureFull({
    required String subjectId,
    required SubjectContentTab tab,
    required String title,
    required int displayOrder,
    DateTime? publishDateTime,
    required bool publishNow,
    required bool guestEnabled,
    int? previewMinutes,
    required List<NewLectureResource> resources,
    required Map<String, bool> accessByStudent,
    String actorId = 'dashboard',
  }) async {
    final String sectionId =
        await _resolveTabSection(subjectId: subjectId, tab: tab);
    final DocumentReference<Map<String, dynamic>> lectureRef =
        _db.collection('lectures').doc();
    final WriteBatch batch = _db.batch();
    batch.set(lectureRef, <String, Object?>{
      'subject_id': subjectId,
      'section_id': sectionId,
      'title': title,
      'description': '',
      'display_order': displayOrder,
      'publish_date':
          publishDateTime != null ? Timestamp.fromDate(publishDateTime) : (publishNow ? FieldValue.serverTimestamp() : null),
      'status': publishNow ? 'published' : 'draft',
      'is_deleted': false,
      'public_free_enabled': guestEnabled,
      'public_free_preview_minutes': guestEnabled ? previewMinutes : null,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': actorId,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorId,
    });

    for (final NewLectureResource resource in resources) {
      final DocumentReference<Map<String, dynamic>> resourceRef =
          _db.collection('lecture_resources').doc();
      String? storagePath;
      if (resource.fileBytes != null) {
        storagePath = await uploadLectureFile(
          bytes: resource.fileBytes!,
          fileName: resource.fileName ?? 'file',
          contentType: resource.contentType ?? 'application/octet-stream',
          lectureId: lectureRef.id,
          resourceId: resourceRef.id,
        );
      }
      batch.set(resourceRef, <String, Object?>{
        'lecture_id': lectureRef.id,
        'resource_type': resource.type,
        'title': resource.title,
        'display_order': resource.displayOrder,
        'bunny_video_id': resource.bunnyVideoId,
        'storage_path': storagePath,
        'storage_provider':
            resource.fileBytes != null ? 'firebase' : null,
        'resource_url': resource.type == 'external_link'
            ? (resource.externalUrl ?? '')
            : '',
        'thumbnail': null,
        'duration': null,
        'is_visible': publishNow,
        'visibility': publishNow,
        'is_deleted': false,
        'created_at': FieldValue.serverTimestamp(),
        'created_by': actorId,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': actorId,
      });
    }

    for (final MapEntry<String, bool> entry in accessByStudent.entries) {
      batch.set(
        _db
            .collection('lecture_access_grants')
            .doc('${lectureRef.id}_${entry.key}'),
        <String, Object?>{
          'lecture_id': lectureRef.id,
          'student_id': entry.key,
          'allowed': entry.value,
          'is_deleted': false,
          'deleted_at': null,
          'deleted_by': null,
          'created_at': FieldValue.serverTimestamp(),
          'created_by': actorId,
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': actorId,
        },
      );
    }
    await batch.commit();
    return lectureRef.id;
  }

  /// Target section for a new lecture: first tab-visible section by
  /// display order, else a newly created section for the tab. System tabs
  /// create their canonical system section; the Online tab reuses the
  /// existing Online custom section when one exists ([findOnlineSection]
  /// — identity, title, order, and visibility preserved, never
  /// duplicated) and otherwise creates the canonical custom section
  /// (`section_key: null`, `is_system_section: false`, title
  /// `Online Sessions` per 05 Database §9). No online-specific key,
  /// collection, or entity is ever introduced.
  Future<String> _resolveTabSection({
    required String subjectId,
    required SubjectContentTab tab,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> sectionsSnap = await _db
        .collection('subject_sections')
        .where('subject_id', isEqualTo: subjectId)
        .where('is_deleted', isEqualTo: false)
        .get();
    final List<SubjectSection> visible = sectionsSnap.docs
        .map(SubjectSection.fromDoc)
        .where((SubjectSection s) => sectionVisibleInTab(s, tab))
        .toList()
      ..sort((SubjectSection a, SubjectSection b) =>
          a.displayOrder.compareTo(b.displayOrder));
    if (visible.isNotEmpty) return visible.first.id;

    final ({String? key, String title, bool isSystem}) spec = switch (tab) {
      SubjectContentTab.lectures =>
        (key: 'explanation', title: 'Lectures', isSystem: true),
      SubjectContentTab.revisions =>
        (key: 'revision', title: 'Revisions', isSystem: true),
      SubjectContentTab.finalTab =>
        (key: 'final_review', title: 'Final', isSystem: true),
      SubjectContentTab.online =>
        (key: null, title: 'Online Sessions', isSystem: false),
    };
    int maxOrder = 0;
    for (final doc in sectionsSnap.docs) {
      final int order =
          (doc.data()['display_order'] as num?)?.toInt() ?? 0;
      if (order > maxOrder) maxOrder = order;
    }
    final DocumentReference<Map<String, dynamic>> ref =
        _db.collection('subject_sections').doc();
    await ref.set(<String, Object?>{
      'subject_id': subjectId,
      'section_key': spec.key,
      'is_system_section': spec.isSystem,
      'title': spec.title,
      'display_order': maxOrder + 1,
      'is_visible': true,
      'is_deleted': false,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': 'dashboard',
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': 'dashboard',
    });
    return ref.id;
  }
}

final subjectDetailsControllerProvider =
    Provider<SubjectDetailsController>((ref) {
  return SubjectDetailsController(ref.watch(firebaseFirestoreProvider));
});
