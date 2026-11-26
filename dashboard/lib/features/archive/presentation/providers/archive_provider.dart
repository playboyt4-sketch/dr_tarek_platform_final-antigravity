import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/firebase_providers.dart';
import '../../../applications/domain/grade.dart';
import '../../../applications/presentation/providers/application_decision_provider.dart';
import '../../../applications/presentation/providers/join_applications_provider.dart';
import '../../../home/presentation/providers/home_stats_provider.dart';
import '../../../students/domain/live_student.dart';
import '../../../students/presentation/providers/grade_pending_requests_provider.dart';
import '../../../students/presentation/providers/grade_students_provider.dart';
import '../../../students/presentation/providers/student_profile_subjects_provider.dart';
import '../../../students/presentation/providers/subject_details_provider.dart';

/// Reads `deleted_at` or `archived_at` timestamp from a Firestore document map.
DateTime? parseArchiveTimestamp(Map<String, dynamic> data) {
  final Object? raw = data['deleted_at'] ?? data['archived_at'] ?? data['updated_at'];
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  return null;
}

/// Formats an archive timestamp as `D/M/YYYY · HH:mm` (or `—` when absent).
String formatArchiveDate(DateTime? dt) {
  if (dt == null) return '—';
  final DateTime local = dt.toLocal();
  final String hh = local.hour.toString().padLeft(2, '0');
  final String mm = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month}/${local.year} · $hh:$mm';
}

class ArchivedStudentItem {
  final String id;
  final String name;
  final String phone;
  final String gradeKey;
  final bool isCenter;
  final DateTime? archivedAt;

  const ArchivedStudentItem({
    required this.id,
    required this.name,
    required this.phone,
    required this.gradeKey,
    required this.isCenter,
    this.archivedAt,
  });

  factory ArchivedStudentItem.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String name = ((data['full_name'] as String?) ??
            (data['name'] as String?) ??
            doc.id)
        .trim();
    final String phone = ((data['phone_number'] as String?) ?? '').trim();
    final String? normalizedGrade = normalizeGradeKey(data['grade']);
    return ArchivedStudentItem(
      id: doc.id,
      name: name.isEmpty ? doc.id : name,
      phone: phone.isEmpty ? '—' : phone,
      gradeKey: normalizedGrade ?? 'grade_one',
      isCenter: data['student_type'] == 'center_student',
      archivedAt: parseArchiveTimestamp(data),
    );
  }
}

class ArchivedSubjectItem {
  final String id;
  final String title;
  final String gradeKey;
  final DateTime? archivedAt;

  const ArchivedSubjectItem({
    required this.id,
    required this.title,
    required this.gradeKey,
    this.archivedAt,
  });

  factory ArchivedSubjectItem.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = doc.data();
    final String title = ((data['title'] as String?) ?? doc.id).trim();
    final String? normalizedGrade = normalizeGradeKey(data['grade']);
    return ArchivedSubjectItem(
      id: doc.id,
      title: title.isEmpty ? doc.id : title,
      gradeKey: normalizedGrade ?? 'grade_one',
      archivedAt: parseArchiveTimestamp(data),
    );
  }
}

class ArchivedLectureItem {
  final String id;
  final String title;
  final String subjectId;
  final String subjectTitle;
  final DateTime? archivedAt;

  const ArchivedLectureItem({
    required this.id,
    required this.title,
    required this.subjectId,
    required this.subjectTitle,
    this.archivedAt,
  });
}

int _compareArchiveNewestFirst(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

final archivedStudentsProvider =
    StreamProvider<List<ArchivedStudentItem>>((ref) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db
      .collection('users')
      .where('role', whereIn: <String>['student', 'new_student'])
      .snapshots()
      .map((QuerySnapshot<Map<String, dynamic>> snap) {
        final List<ArchivedStudentItem> items = snap.docs
            .where((doc) => isArchivedData(doc.data()))
            .map(ArchivedStudentItem.fromDoc)
            .toList(growable: true);
        items.sort((a, b) => _compareArchiveNewestFirst(a.archivedAt, b.archivedAt));
        return List<ArchivedStudentItem>.unmodifiable(items);
      });
});

final archivedSubjectsProvider =
    StreamProvider<List<ArchivedSubjectItem>>((ref) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  return db.collection('subjects').snapshots().map(
    (QuerySnapshot<Map<String, dynamic>> snap) {
      final List<ArchivedSubjectItem> items = snap.docs
          .where((doc) => isArchivedData(doc.data()))
          .map(ArchivedSubjectItem.fromDoc)
          .toList(growable: true);
      items.sort((a, b) => _compareArchiveNewestFirst(a.archivedAt, b.archivedAt));
      return List<ArchivedSubjectItem>.unmodifiable(items);
    },
  );
});

final archivedLecturesProvider =
    StreamProvider<List<ArchivedLectureItem>>((ref) {
  final FirebaseFirestore db = ref.watch(firebaseFirestoreProvider);
  late final StreamController<List<ArchivedLectureItem>> controller;
  Map<String, String> subjectTitles = <String, String>{};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> lectureDocs =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subjectsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? lecturesSub;

  void emit() {
    if (controller.isClosed) return;
    final List<ArchivedLectureItem> items = <ArchivedLectureItem>[];
    for (final doc in lectureDocs) {
      final Map<String, dynamic> data = doc.data();
      if (!isArchivedData(data)) continue;
      final String subjectId = ((data['subject_id'] as String?) ?? '').trim();
      final String title = ((data['title'] as String?) ?? doc.id).trim();
      items.add(
        ArchivedLectureItem(
          id: doc.id,
          title: title.isEmpty ? doc.id : title,
          subjectId: subjectId,
          subjectTitle: subjectTitles[subjectId] ?? (subjectId.isEmpty ? '—' : subjectId),
          archivedAt: parseArchiveTimestamp(data),
        ),
      );
    }
    items.sort((a, b) => _compareArchiveNewestFirst(a.archivedAt, b.archivedAt));
    controller.add(List<ArchivedLectureItem>.unmodifiable(items));
  }

  controller = StreamController<List<ArchivedLectureItem>>(
    onListen: () {
      subjectsSub = db.collection('subjects').snapshots().listen(
        (snap) {
          subjectTitles = <String, String>{
            for (final doc in snap.docs)
              doc.id: ((doc.data()['title'] as String?) ?? doc.id).trim(),
          };
          emit();
        },
        onError: controller.addError,
      );
      lecturesSub = db.collection('lectures').snapshots().listen(
        (snap) {
          lectureDocs = snap.docs;
          emit();
        },
        onError: controller.addError,
      );
    },
  );

  ref.onDispose(() async {
    await subjectsSub?.cancel();
    await lecturesSub?.cancel();
    await controller.close();
  });
  return controller.stream;
});

class ArchiveController {
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  const ArchiveController(this._db, this._functions);

  Future<void> archiveStudent(String studentId) async {
    await _functions.httpsCallable('archiveStudent').call(
      <String, dynamic>{'studentId': studentId},
    );
  }

  Future<void> restoreStudent(String studentId) async {
    await _functions.httpsCallable('restoreStudent').call(
      <String, dynamic>{'studentId': studentId},
    );
  }

  Future<void> archiveSubject(String subjectId) async {
    await _functions.httpsCallable('deleteSubject').call(
      <String, dynamic>{'subjectId': subjectId},
    );
  }

  Future<void> restoreSubject(String subjectId) async {
    await _functions.httpsCallable('restoreSubject').call(
      <String, dynamic>{'subjectId': subjectId},
    );
  }

  Future<void> archiveLecture(String lectureId) async {
    final String actorId = FirebaseAuth.instance.currentUser?.uid ?? 'staff';
    await _db.collection('lectures').doc(lectureId).update(<String, Object?>{
      'is_archived': true,
      'is_deleted': true,
      'deleted_at': FieldValue.serverTimestamp(),
      'archived_by': actorId,
      'status': 'archived',
      'first_video': null,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': actorId,
    });
  }

  Future<void> restoreLecture(String lectureId) async {
    await _functions.httpsCallable('restoreLecture').call(
      <String, dynamic>{'lectureId': lectureId},
    );
  }

  Future<void> permanentlyDelete({
    required String entityType,
    required String targetId,
  }) async {
    await _functions.httpsCallable('permanentlyDeleteArchivedItem').call(
      <String, dynamic>{
        'entityType': entityType,
        'targetId': targetId,
      },
    );
  }
}

final archiveControllerProvider = Provider<ArchiveController>((ref) {
  return ArchiveController(
    ref.watch(firebaseFirestoreProvider),
    ref.watch(firebaseFunctionsProvider),
  );
});

/// Refreshes active and archived views after any archive/restore/purge action.
void invalidateArchiveDependents(WidgetRef ref) {
  ref.invalidate(archivedStudentsProvider);
  ref.invalidate(archivedSubjectsProvider);
  ref.invalidate(archivedLecturesProvider);
  ref.invalidate(gradeStudentsProvider);
  ref.invalidate(gradeSubjectsProvider);
  ref.invalidate(gradePendingRequestsProvider);
  ref.invalidate(joinApplicationsProvider);
  ref.invalidate(homeStatsProvider);
  ref.invalidate(homeAnalyticsProvider);
  ref.invalidate(subjectDetailsProvider);
  ref.invalidate(tabLecturesProvider);
  ref.invalidate(studentProfileSubjectsProvider);
}
