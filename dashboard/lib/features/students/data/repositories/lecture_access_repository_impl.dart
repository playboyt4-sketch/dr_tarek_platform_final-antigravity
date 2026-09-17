import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/errors/failure.dart';
import '../../domain/entities/lecture_access.dart';
import '../../domain/repositories/lecture_access_repository.dart';

/// Firestore implementation of [LectureAccessRepository].
///
/// Query discipline mirrors the existing providers (single-equality
/// queries only — no composite indexes; soft-delete/approval filters
/// applied client-side):
/// - roster: `subject_access_assignments` by `subject_id` joined with
///   approved `users` by `role`. Non-deleted assignment = enrolled;
///   Section never affects eligibility.
/// - grants: `lecture_access_grants` by `lecture_id`, non-deleted only.
/// - save: one read (preserve `created_*`) + one batch of deterministic
///   `{lectureId}_{studentId}` sets (merge for existing docs).
///
/// Audit follows the approved schema: `created_at/by` set once,
/// `updated_at/by` on every write; revocation is `allowed: false`
/// (client delete stays prohibited by Security Rules). The
/// `onLectureAccessGrantWritten` trigger covers audit events — no
/// parallel audit system is created here.
class LectureAccessRepositoryImpl implements LectureAccessRepository {
  final FirebaseFirestore _db;

  const LectureAccessRepositoryImpl(this._db);

  @override
  Future<List<LectureAccessStudent>> getSubjectRoster(
      String subjectId) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> assignmentsSnap = await _db
          .collection('subject_access_assignments')
          .where('subject_id', isEqualTo: subjectId)
          .get();
      final Set<String> enrolledIds = <String>{
        for (final doc in assignmentsSnap.docs)
          if (doc.data()['is_deleted'] != true)
            (doc.data()['student_id'] as String?) ?? doc.id,
      };
      if (enrolledIds.isEmpty) return const <LectureAccessStudent>[];

      final QuerySnapshot<Map<String, dynamic>> usersSnap = await _db
          .collection('users')
          .where('role', isEqualTo: 'student')
          .get();
      final List<LectureAccessStudent> roster = <LectureAccessStudent>[];
      for (final doc in usersSnap.docs) {
        if (!enrolledIds.contains(doc.id)) continue;
        final Map<String, dynamic> data = doc.data();
        if (data['approval_status'] != 'approved') continue;
        roster.add(_studentFromUserDoc(doc.id, data));
      }
      roster.sort((a, b) => a.name.compareTo(b.name));
      return roster;
    } catch (error, stackTrace) {
      throw Failure.from(error, stackTrace);
    }
  }

  @override
  Future<List<LectureAccessGrant>> getLectureGrants(
      String lectureId) async {
    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await _db
          .collection('lecture_access_grants')
          .where('lecture_id', isEqualTo: lectureId)
          .get();
      return <LectureAccessGrant>[
        for (final doc in snap.docs)
          if (doc.data()['is_deleted'] != true)
            LectureAccessGrant(
              lectureId:
                  (doc.data()['lecture_id'] as String?) ?? lectureId,
              studentId: (doc.data()['student_id'] as String?) ?? '',
              allowed: doc.data()['allowed'] as bool? ?? true,
            ),
      ];
    } catch (error, stackTrace) {
      throw Failure.from(error, stackTrace);
    }
  }

  @override
  Future<void> saveLectureGrants({
    required String lectureId,
    required Map<String, bool> allowedByStudent,
    required String actorId,
  }) async {
    if (allowedByStudent.isEmpty) return;
    try {
      final QuerySnapshot<Map<String, dynamic>> existing = await _db
          .collection('lecture_access_grants')
          .where('lecture_id', isEqualTo: lectureId)
          .get();
      final Map<String, Object?> createdAtById = <String, Object?>{};
      final Map<String, Object?> createdByById = <String, Object?>{};
      for (final doc in existing.docs) {
        createdAtById[doc.id] = doc.data()['created_at'];
        createdByById[doc.id] = doc.data()['created_by'];
      }
      final WriteBatch batch = _db.batch();
      for (final MapEntry<String, bool> entry in allowedByStudent.entries) {
        final String id = lectureAccessGrantDocId(lectureId, entry.key);
        final LectureAccessGrantWrite write = lectureAccessGrantWrite(
          grant: LectureAccessGrant(
            lectureId: lectureId,
            studentId: entry.key,
            allowed: entry.value,
          ),
          existingCreatedAt: createdAtById[id],
          existingCreatedBy: createdByById[id],
          hadExistingDoc: createdAtById.containsKey(id),
          actorId: actorId,
          serverTimestamp: FieldValue.serverTimestamp(),
        );
        batch.set(
          _db.collection('lecture_access_grants').doc(id),
          write.fields,
          write.isNew ? null : SetOptions(merge: true),
        );
      }
      await batch.commit();
    } catch (error, stackTrace) {
      throw Failure.from(error, stackTrace);
    }
  }
}

/// User-doc → roster-row mapping. Key fallbacks mirror
/// `GradeStudent.fromDoc` (writers vary across `full_name` /
/// `display_name` / `name` and `phone_number` / `phone`); plan labels
/// use the same FREE / PRO / MAX normalization.
LectureAccessStudent _studentFromUserDoc(
    String id, Map<String, dynamic> data) {
  final String rawName = (data['full_name'] as String?) ??
      (data['display_name'] as String?) ??
      (data['name'] as String?) ??
      '';
  final String name = rawName.trim().isEmpty ? 'Unknown student' : rawName.trim();
  final String rawPlan = ((data['plan'] as String?) ??
          (data['plan_key'] as String?) ??
          (data['subscription_plan'] as String?) ??
          'FREE')
      .toUpperCase();
  final String plan;
  if (rawPlan.contains('MAX')) {
    plan = 'MAX';
  } else if (rawPlan.contains('PRO')) {
    plan = 'PRO';
  } else {
    plan = 'FREE';
  }
  return LectureAccessStudent(
    id: id,
    name: name,
    plan: plan,
    phone: (data['phone_number'] as String?) ?? (data['phone'] as String?),
  );
}

/// One batched grant write: document fields plus whether the target is
/// new (full set) or existing (merge, preserving created_*).
typedef LectureAccessGrantWrite = ({
  Map<String, Object?> fields,
  bool isNew,
});

/// Pure field mapping for `lecture_access_grants` documents (audit
/// convention: created_at/by set once, updated_at/by on every write;
/// clients always write the active state — revocation is
/// `allowed: false`, never a delete). Extracted pure so the
/// merge/audit behavior is unit-testable without Firestore;
/// [serverTimestamp] is injected by the caller.
LectureAccessGrantWrite lectureAccessGrantWrite({
  required LectureAccessGrant grant,
  required Object? existingCreatedAt,
  required Object? existingCreatedBy,
  required bool hadExistingDoc,
  required String actorId,
  required Object serverTimestamp,
}) {
  final Map<String, Object?> fields = <String, Object?>{
    'lecture_id': grant.lectureId,
    'student_id': grant.studentId,
    'allowed': grant.allowed,
    'updated_at': serverTimestamp,
    'updated_by': actorId,
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
