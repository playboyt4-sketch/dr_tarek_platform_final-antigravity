import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  /// Scheduled publish time (`publish_date`); null when unpublished-now
  /// or a plain draft. Lectures with `status == 'draft'` stay hidden
  /// from students until published (or auto-published by the
  /// `autoPublishDueLectures` scheduler once this passes).
  final DateTime? publishDate;

  const SubjectLecture({
    required this.id,
    required this.title,
    required this.displayOrder,
    required this.status,
    this.publishDate,
  });

  /// True when visible to students in the mobile app (the student query
  /// requires `status == 'published'`).
  bool get isPublished => status == 'published';

  factory SubjectLecture.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String title = (data['title'] as String?)?.trim() ?? '';
    final Object? rawDate = data['publish_date'];
    return SubjectLecture(
      id: doc.id,
      title: title.isEmpty ? doc.id : title,
      displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
      status: (data['status'] as String?) ?? 'draft',
      publishDate: rawDate is Timestamp ? rawDate.toDate() : null,
    );
  }
}

/// One persisted `lecture_resources` row, read for the lecture Edit form.
class LectureEditResource {
  final String id;
  final String type;
  final String title;
  final int displayOrder;
  final String? bunnyVideoId;
  final String? externalUrl;
  final String? storagePath;

  /// Strict `is_visible == true` mirror of the student listing query: only
  /// used for first-video candidacy (the row itself still shows in the
  /// form regardless).
  final bool isVisible;

  const LectureEditResource({
    required this.id,
    required this.type,
    required this.title,
    required this.displayOrder,
    this.bunnyVideoId,
    this.externalUrl,
    this.storagePath,
    required this.isVisible,
  });
}

/// Minimal projection of a `lecture_resources` row for canonical
/// first-video selection (Phase 2). The writer maps persisted + staged
/// form state into these (including visibility/deletion, which the edit
/// model above does not carry) and passes the list to
/// [selectFirstVideoCandidate]. Pure data — no Firestore, no security
/// semantics: the backend authorization stays authoritative.
class FirstVideoCandidate {
  final String id;
  final String type;
  final String title;
  final bool isVisible;
  final bool isDeleted;
  final String? bunnyVideoId;
  final int displayOrder;

  const FirstVideoCandidate({
    required this.id,
    required this.type,
    this.title = '',
    required this.isVisible,
    required this.isDeleted,
    this.bunnyVideoId,
    required this.displayOrder,
  });
}

/// Canonical first-video selector shared by the Dashboard writer sync
/// (Phase 3 calls this after every resource mutation).
///
/// Eligibility: `video` + visible + not soft-deleted + non-empty Bunny id.
/// Winner: lowest `displayOrder`; document id ascending breaks ties —
/// the same definition as backend listing order and client
/// `firstPlayableVideo`. Returns null when nothing is eligible (the
/// lecture's denormalized `first_video` must then be cleared to null).
/// Pure and side-effect-free.
FirstVideoCandidate? selectFirstVideoCandidate(
  Iterable<FirstVideoCandidate> candidates,
) {
  FirstVideoCandidate? winner;
  for (final candidate in candidates) {
    if (candidate.type != 'video') continue;
    if (!candidate.isVisible) continue;
    if (candidate.isDeleted) continue;
    final bunnyVideoId = candidate.bunnyVideoId;
    if (bunnyVideoId == null || bunnyVideoId.trim().isEmpty) continue;
    if (winner == null ||
        candidate.displayOrder < winner.displayOrder ||
        (candidate.displayOrder == winner.displayOrder &&
            candidate.id.compareTo(winner.id) < 0)) {
      winner = candidate;
    }
  }
  return winner;
}

/// Serializes a selected winner into the denormalized `first_video` map
/// stored on `lectures/{lectureId}`. Identity + display metadata only:
/// never signed URLs, secrets, storage URLs, or authorization verdicts.
/// Pure and side-effect-free.
Map<String, Object?> firstVideoFields(FirstVideoCandidate winner) {
  return <String, Object?>{
    'resource_id': winner.id,
    'bunny_video_id': winner.bunnyVideoId!.trim(),
    'title': winner.title,
    'display_order': winner.displayOrder,
    // Reserved poster keys (raw paths only, once thumbnail content exists).
    'thumbnail_path': null,
    'thumbnail_storage_provider': null,
  };
}

/// Pure merge of persisted + staged Edit-form state into first-video
/// candidates for one lecture. Applies in-place edits (null Bunny id =
/// keep the stored value, mirroring [UpdatedLectureResource]), drops
/// [deletedIds], and appends [createdById] rows; staged rows are visible
/// exactly when [createdVisible]. Used by [SubjectDetailsController]
/// before committing its batch — no Firestore here.
List<FirstVideoCandidate> collectFirstVideoCandidates({
  required List<LectureEditResource> persisted,
  required Map<String, UpdatedLectureResource> updatedById,
  required Map<String, NewLectureResource> createdById,
  required bool createdVisible,
  required Set<String> deletedIds,
}) {
  final List<FirstVideoCandidate> candidates = <FirstVideoCandidate>[];
  for (final LectureEditResource stored in persisted) {
    if (deletedIds.contains(stored.id)) continue;
    final UpdatedLectureResource? overlay = updatedById[stored.id];
    candidates.add(FirstVideoCandidate(
      id: stored.id,
      type: stored.type,
      title: overlay?.title ?? stored.title,
      isVisible: stored.isVisible,
      isDeleted: false,
      bunnyVideoId: overlay?.bunnyVideoId ?? stored.bunnyVideoId,
      displayOrder: overlay?.displayOrder ?? stored.displayOrder,
    ));
  }
  createdById.forEach((String id, NewLectureResource created) {
    candidates.add(FirstVideoCandidate(
      id: id,
      type: created.type,
      title: created.title,
      isVisible: createdVisible,
      isDeleted: false,
      bunnyVideoId: created.bunnyVideoId,
      displayOrder: created.displayOrder,
    ));
  });
  return candidates;
}

/// Full editable snapshot of one lecture for the Edit form (same page
/// as Add): lecture fields + persisted resources + per-student access
/// overrides. Missing grant = no override.
class LectureEditData {
  final String lectureId;
  final String title;
  final int displayOrder;
  final String status;
  final DateTime? publishDate;
  final bool guestEnabled;
  final int? previewMinutes;
  final List<LectureEditResource> resources;
  final Map<String, bool> accessOverrides;

  const LectureEditData({
    required this.lectureId,
    required this.title,
    required this.displayOrder,
    required this.status,
    this.publishDate,
    required this.guestEnabled,
    this.previewMinutes,
    required this.resources,
    required this.accessOverrides,
  });
}

/// One in-place update for an already-persisted `lecture_resources` row.
/// Only the fields the doctor actually changed are sent: title/order are
/// always written, while video id / external URL / replacement file bytes
/// are applied only when non-null (null = keep the stored value).
/// Wire values (`video`/`pdf`/`attachment`/`external_link`) match the
/// approved `lecture_resources` format.
class UpdatedLectureResource {
  final String id;
  final String title;
  final int displayOrder;
  final String? bunnyVideoId;
  final String? externalUrl;
  final Uint8List? fileBytes;
  final String? fileName;
  final String? contentType;

  const UpdatedLectureResource({
    required this.id,
    required this.title,
    required this.displayOrder,
    this.bunnyVideoId,
    this.externalUrl,
    this.fileBytes,
    this.fileName,
    this.contentType,
  });
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
  final FirebaseFunctions? _functions;

  /// [_functions] is optional so Firestore-only unit tests can keep
  /// building `SubjectDetailsController(db)` with a fake database;
  /// only [deleteSubject] needs Functions and falls back to the
  /// default instance when none was injected.
  const SubjectDetailsController(this._db, [this._functions]);

  /// Resolves the audit actor: explicit caller override wins, otherwise
  /// the signed-in dashboard uid, otherwise the legacy fallback.
  static String resolveActorId(String? actorId) {
    if (actorId != null && actorId.trim().isNotEmpty) return actorId;
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? 'dashboard';
    } catch (_) {
      return 'dashboard';
    }
  }

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
  /// Security Rules staff checks (doctor / content-management
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

  /// Soft-deletes a subject through the approved `deleteSubject` Cloud
  /// Function. A direct client `is_deleted: true` update is denied by
  /// `firestore.rules` (subjects updates must keep `is_deleted == false`),
  /// so the audited server path is the only write route.
  Future<void> deleteSubject(String subjectId) async {
    final FirebaseFunctions functions =
        _functions ?? FirebaseFunctions.instance;
    await functions.httpsCallable('deleteSubject').call(
      <String, dynamic>{'subjectId': subjectId},
    );
  }

  Future<void> deleteLecture(String lectureId) {
    return _db.collection('lectures').doc(lectureId).update(
      <String, Object?>{
        'is_deleted': true,
        'status': 'archived',
        // The archived lecture leaves student listings; its denormalized
        // pointer must not survive it.
        'first_video': null,
        'updated_at': FieldValue.serverTimestamp(),
      },
    );
  }

  /// Next lecture display order across the tab-visible sections of one
  /// subject (max + 1, minimum 0 — numbering starts at 00). The form
  /// prefills this and the doctor may edit it.
  Future<int> nextLectureOrder({
    required String subjectId,
    required SubjectContentTab tab,
  }) async {
    final QuerySnapshot<Map<String, dynamic>> sectionsSnap = await _db
        .collection('subject_sections')
        .where('subject_id', isEqualTo: subjectId)
        .where('is_deleted', isEqualTo: false)
        .get();
    int maxOrder = -1;
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
  /// wire format (`adminResourceFields`); Guest preview is written to
  /// the canonical `guest_enabled` / `guest_preview_minutes` fields
  /// alongside the legacy `public_free_*` aliases (both kept in sync).
  /// Every new `lecture_resources` row carries `subject_id` for the
  /// `hasSubjectAccess` Firestore gate.
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
    String? actorId,
  }) async {
    final String resolvedActor = resolveActorId(actorId);
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
      'guest_enabled': guestEnabled,
      'guest_preview_minutes': guestEnabled ? previewMinutes : null,
      'created_at': FieldValue.serverTimestamp(),
      'created_by': resolvedActor,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': resolvedActor,
    });

    final Map<String, NewLectureResource> stagedById =
        <String, NewLectureResource>{};
    for (final NewLectureResource resource in resources) {
      final DocumentReference<Map<String, dynamic>> resourceRef =
          _db.collection('lecture_resources').doc();
      stagedById[resourceRef.id] = resource;
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
        'subject_id': subjectId,
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
        'created_by': resolvedActor,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': resolvedActor,
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
          'created_by': resolvedActor,
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': resolvedActor,
        },
      );
    }
    // First-video sync (same batch): staged rows are visible exactly when
    // the lecture publishes now; ids were collected above. Null when
    // nothing staged is eligible (e.g. draft lectures).
    final FirstVideoCandidate? stagedWinner = selectFirstVideoCandidate(
      collectFirstVideoCandidates(
        persisted: const <LectureEditResource>[],
        updatedById: const <String, UpdatedLectureResource>{},
        createdById: stagedById,
        createdVisible: publishNow,
        deletedIds: const <String>{},
      ),
    );
    batch.update(lectureRef, <String, Object?>{
      'first_video':
          stagedWinner == null ? null : firstVideoFields(stagedWinner),
    });
    await batch.commit();
    return lectureRef.id;
  }

  /// Editable snapshot of one lecture for the Edit form (the same page
  /// as Add Lecture): lecture fields + non-deleted resources + stored
  /// per-student access overrides. Throws [DecisionFailure] when the
  /// lecture document is missing.
  Future<LectureEditData> getLectureForEdit(String lectureId) async {
    final DocumentSnapshot<Map<String, dynamic>> lectureSnap =
        await _db.collection('lectures').doc(lectureId).get();
    final Map<String, dynamic>? lecture = lectureSnap.data();
    if (lecture == null) {
      throw const DecisionFailure('Lecture not found.');
    }
    final QuerySnapshot<Map<String, dynamic>> resourcesSnap = await _db
        .collection('lecture_resources')
        .where('lecture_id', isEqualTo: lectureId)
        .get();
    final List<LectureEditResource> resources = <LectureEditResource>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in resourcesSnap.docs) {
      final Map<String, dynamic> data = doc.data();
      if (data['is_deleted'] == true) continue;
      resources.add(LectureEditResource(
        id: doc.id,
        type: (data['resource_type'] as String?) ?? 'video',
        title: ((data['title'] as String?) ?? '').trim(),
        displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
        bunnyVideoId: data['bunny_video_id'] as String?,
        externalUrl: data['resource_url'] as String?,
        storagePath: data['storage_path'] as String?,
        isVisible: data['is_visible'] == true,
      ));
    }
    resources.sort((LectureEditResource a, LectureEditResource b) =>
        a.displayOrder.compareTo(b.displayOrder));

    final QuerySnapshot<Map<String, dynamic>> grantsSnap = await _db
        .collection('lecture_access_grants')
        .where('lecture_id', isEqualTo: lectureId)
        .get();
    final Map<String, bool> overrides = <String, bool>{};
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in grantsSnap.docs) {
      final Map<String, dynamic> data = doc.data();
      if (data['is_deleted'] == true) continue;
      final String? studentId = data['student_id'] as String?;
      final Object? allowed = data['allowed'];
      if (studentId != null &&
          studentId.isNotEmpty &&
          allowed is bool) {
        overrides[studentId] = allowed;
      }
    }

    final Object? rawDate = lecture['publish_date'];
    return LectureEditData(
      lectureId: lectureId,
      title: ((lecture['title'] as String?) ?? '').trim(),
      displayOrder: (lecture['display_order'] as num?)?.toInt() ?? 0,
      status: (lecture['status'] as String?) ?? 'draft',
      publishDate: rawDate is Timestamp ? rawDate.toDate() : null,
      guestEnabled:
          lecture['guest_enabled'] == true || lecture['public_free_enabled'] == true,
      previewMinutes:
          (lecture['guest_preview_minutes'] as num?)?.toInt() ??
              (lecture['public_free_preview_minutes'] as num?)?.toInt(),
      resources: resources,
      accessOverrides: overrides,
    );
  }

  /// Lecture edit commit for the Edit form (same page as Add): updates
  /// ONLY the form-represented lecture fields, applies in-place edits of
  /// persisted rows from [updatedResources] (title, display order, Bunny
  /// video id, external URL, or a replacement file), appends
  /// [newResources] as fresh `lecture_resources` rows (pass ids in
  /// [deleteResourceIds] to soft-delete removed rows), and upserts
  /// [accessByStudent] grants by deterministic id.
  ///
  /// Publication semantics mirror creation: [publishNow] writes
  /// `published` immediately; a [publishDateTime] writes a scheduled
  /// `draft` (server auto-publishes on time); otherwise — when
  /// [preserveStatus] is true (plain Save in edit mode) — the stored
  /// status is left untouched, and any stored `publish_date` is kept
  /// unless [clearPublishDate] is set (Save Draft clears it).
  Future<void> updateLectureFull({
    required String lectureId,
    required String title,
    required int displayOrder,
    required bool publishNow,
    DateTime? publishDateTime,
    bool preserveStatus = false,
    bool clearPublishDate = false,
    required bool guestEnabled,
    int? previewMinutes,
    required List<NewLectureResource> newResources,
    required List<String> deleteResourceIds,
    List<UpdatedLectureResource> updatedResources = const <UpdatedLectureResource>[],
    required Map<String, bool> accessByStudent,
    String? actorId,
  }) async {
    final String resolvedActor = resolveActorId(actorId);
    // The lecture's subject scopes every new resource row for the
    // `hasSubjectAccess` Firestore gate; read once, reuse below.
    final DocumentSnapshot<Map<String, dynamic>> lectureSnap =
        await _db.collection('lectures').doc(lectureId).get();
    final String? lectureSubjectId =
        (lectureSnap.data()?['subject_id'] as String?)?.trim();
    final WriteBatch batch = _db.batch();
    final Map<String, Object?> fields = <String, Object?>{
      'title': title,
      'display_order': displayOrder,
      'public_free_enabled': guestEnabled,
      'public_free_preview_minutes': guestEnabled ? previewMinutes : null,
      'guest_enabled': guestEnabled,
      'guest_preview_minutes': guestEnabled ? previewMinutes : null,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': resolvedActor,
    };
    if (publishNow) {
      fields['status'] = 'published';
      fields['publish_date'] = FieldValue.serverTimestamp();
    } else if (publishDateTime != null) {
      fields['status'] = 'draft';
      fields['publish_date'] = Timestamp.fromDate(publishDateTime);
    } else if (!preserveStatus) {
      fields['status'] = 'draft';
      if (clearPublishDate) fields['publish_date'] = null;
    } else if (clearPublishDate) {
      fields['publish_date'] = null;
    }
    batch.update(_db.collection('lectures').doc(lectureId), fields);

    final Map<String, NewLectureResource> stagedById =
        <String, NewLectureResource>{};
    for (final NewLectureResource resource in newResources) {
      final DocumentReference<Map<String, dynamic>> resourceRef =
          _db.collection('lecture_resources').doc();
      stagedById[resourceRef.id] = resource;
      String? storagePath;
      if (resource.fileBytes != null) {
        storagePath = await uploadLectureFile(
          bytes: resource.fileBytes!,
          fileName: resource.fileName ?? 'file',
          contentType: resource.contentType ?? 'application/octet-stream',
          lectureId: lectureId,
          resourceId: resourceRef.id,
        );
      }
      batch.set(resourceRef, <String, Object?>{
        'lecture_id': lectureId,
        'subject_id': lectureSubjectId,
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
        'is_visible': true,
        'visibility': true,
        'is_deleted': false,
        'created_at': FieldValue.serverTimestamp(),
        'created_by': resolvedActor,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': resolvedActor,
      });
    }

    for (final UpdatedLectureResource resource in updatedResources) {
      String? storagePath;
      if (resource.fileBytes != null) {
        storagePath = await uploadLectureFile(
          bytes: resource.fileBytes!,
          fileName: resource.fileName ?? 'file',
          contentType: resource.contentType ?? 'application/octet-stream',
          lectureId: lectureId,
          resourceId: resource.id,
        );
      }
      final Map<String, Object?> updateFields = <String, Object?>{
        'title': resource.title,
        'display_order': resource.displayOrder,
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': resolvedActor,
      };
      // Null = keep the stored value; non-null = doctor edited it.
      if (resource.bunnyVideoId != null) {
        updateFields['bunny_video_id'] = resource.bunnyVideoId;
      }
      if (resource.externalUrl != null) {
        updateFields['resource_url'] = resource.externalUrl;
      }
      if (storagePath != null) {
        updateFields['storage_path'] = storagePath;
        updateFields['storage_provider'] = 'firebase';
      }
      batch.update(
        _db.collection('lecture_resources').doc(resource.id),
        updateFields,
      );
    }

    for (final String resourceId in deleteResourceIds) {
      batch.update(
        _db.collection('lecture_resources').doc(resourceId),
        <String, Object?>{
          'is_deleted': true,
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': resolvedActor,
        },
      );
    }

    // First-video sync (same batch): merge persisted rows with the staged
    // edits/deletes/creates above, recompute the canonical winner, and
    // store (or clear to null) `first_video` on the lecture. One extra
    // read of this lecture's rows; the commit stays a single batch.
    final QuerySnapshot<Map<String, dynamic>> persistedSnap = await _db
        .collection('lecture_resources')
        .where('lecture_id', isEqualTo: lectureId)
        .get();
    final List<LectureEditResource> persistedForSync = <LectureEditResource>[];
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in persistedSnap.docs) {
      final Map<String, dynamic> data = doc.data();
      if (data['is_deleted'] == true) continue;
      persistedForSync.add(LectureEditResource(
        id: doc.id,
        type: (data['resource_type'] as String?) ?? 'video',
        title: ((data['title'] as String?) ?? '').trim(),
        displayOrder: (data['display_order'] as num?)?.toInt() ?? 0,
        bunnyVideoId: data['bunny_video_id'] as String?,
        externalUrl: data['resource_url'] as String?,
        storagePath: data['storage_path'] as String?,
        isVisible: data['is_visible'] == true,
      ));
    }
    final FirstVideoCandidate? mergedWinner = selectFirstVideoCandidate(
      collectFirstVideoCandidates(
        persisted: persistedForSync,
        updatedById: <String, UpdatedLectureResource>{
          for (final UpdatedLectureResource updated in updatedResources)
            updated.id: updated,
        },
        createdById: stagedById,
        createdVisible: true,
        deletedIds: deleteResourceIds.toSet(),
      ),
    );
    batch.update(
      _db.collection('lectures').doc(lectureId),
      <String, Object?>{
        'first_video':
            mergedWinner == null ? null : firstVideoFields(mergedWinner),
      },
    );

    for (final MapEntry<String, bool> entry in accessByStudent.entries) {
      batch.set(
        _db
            .collection('lecture_access_grants')
            .doc('${lectureId}_${entry.key}'),
        <String, Object?>{
          'lecture_id': lectureId,
          'student_id': entry.key,
          'allowed': entry.value,
          'is_deleted': false,
          'deleted_at': null,
          'deleted_by': null,
          'created_at': FieldValue.serverTimestamp(),
          'created_by': resolvedActor,
          'updated_at': FieldValue.serverTimestamp(),
          'updated_by': resolvedActor,
        },
      );
    }
    await batch.commit();
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
    String? actorId,
  }) async {
    final String resolvedActor = resolveActorId(actorId);
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
      'created_by': resolvedActor,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': resolvedActor,
    });
    return ref.id;
  }
}

final subjectDetailsControllerProvider =
    Provider<SubjectDetailsController>((ref) {
  return SubjectDetailsController(
    ref.watch(firebaseFirestoreProvider),
    ref.watch(firebaseFunctionsProvider),
  );
});
